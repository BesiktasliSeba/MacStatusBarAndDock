// msbdcharge -- MacStatusBar&Dock's Charge Limit helper (1.7.8 item 5, plans/battery-charging.md; decisions: common/ChargeLimit.h). A root launchd
// job of its own (com.besiktasliseba.chargelimit, KeepAlive), so a fault here cannot touch the root helper's other jobs and the other way round.
//
// How it stops charging, per charger (read on the four iPads, 1 Nov 2026, "does each chip obey"):
//   SMC iPads (AppleSmartBattery: M1, A12Z): powerd's own "ChargeInhibit" power assertion. powerd turns it into IsCharging = false on the battery
//     service, allows it for root without any entitlement, and drops it the moment our process ends (any end, even SIGKILL): charging comes back
//     by itself (M1: a top-off of +495 mA stopped within 20 s, held, released cleanly).
//   PMU iPads (AppleARMPMUCharger: A9X, A10X): their charger driver does not keep powerd's IsCharging = false (the iPad 2 went on charging at
//     1.0-1.6 A under it); it keeps Apple's own Optimized Battery Charging key, PredictiveChargingInhibit, on the battery service (iPad 2: +1279 mA
//     -> 0 in 30 s, held, released -> charging in 20 s). That key does not end with our process: it is cleared first thing at every start
//     (launchd starts us again within seconds after any end), at SIGTERM (launchctl unload: the package's prerm), and by --reset (the prerm).
//   iPadOS 18 (the SMC iPads whose SMC has CHLS: the A12Z): their battery driver ignores powerd's IsCharging = false; the hold there is a policy
//     of powerd's own SOC-limit service (what the iPhone's 80 % Limit uses), which powerd writes to the SMC key CHLS (below: "iPadOS 18's own
//     charge limit"). It outlives our process: its token is kept and it is removed at every let-go and at every start.
//   Coming down (the adapter cut so the iPad runs from its battery while plugged in; unless switched off, MSBD_CHARGE_COMEDOWN_KEY): powerd's
//     "DisableInflow" assertion on both kinds (obeyed on all four; ends with our process). While it is up the SMC iPads read the cable as out (AppleRawExternalConnected 0) but keep the adapter's
//     details (A12Z: 13 W before and during the cut), and its end looks like plugging in to iPadOS (the A12Z lit its Lock Screen for ~9 s).
// Nothing else is ever written by us: no SMC key (CHLS is powerd's own write, on our policy), no PMU register, none of Apple's preferences.
//
// What powerd forgets when it restarts (an assertion of ours) the driver keeps (the hold or cut it set): the helper checks with powerd that its
// assertions are still held and raises them again, and a hold or cut showing in the battery service that nobody holds is raised and let go once,
// so powerd writes "allowed" back to the driver (BattSafePro's fix for the same).
//
//   msbdcharge            the job (launchd)
//   msbdcharge --reset    charging back to iPadOS's own: PredictiveChargingInhibit cleared, a hold or an adapter cut still showing raised and let go
//                         (so powerd writes "allowed" to the battery), nothing left held. For the package's prerm. Run by hand while the job
//                         runs (its lock held): the job's own levers are left to it (its policies, the PMU key, its published state).
//   msbdcharge --stop     the job lets go of its hold, cut and stay-awake now and holds nothing until it is stopped (2 minutes at most); waits up
//                         to 3 s for it to say so. For the package's prerm, before it stops the job.
//   msbdcharge --status   what it reads and would do now (read only)
//   msbdcharge --poke     the job looks again now (posts our settings notification, as Settings does after a change)
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <notify.h>
#import <signal.h>
#import <unistd.h>
#import <spawn.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <sys/file.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import "../common/ChargeLimit.h"
#import "../common/SleepGuard.h"
#import "../common/DeviceGate.h"
#import "../common/VersionGate.h"

typedef uint32_t IOPMAssertionID;
extern IOReturn IOPMAssertionCreateWithProperties(CFDictionaryRef properties, IOPMAssertionID *assertionID);
extern IOReturn IOPMAssertionRelease(IOPMAssertionID assertionID);
extern IOReturn IOPMCopyAssertionsByProcess(CFDictionaryRef *assertionsByPID);
extern CFRunLoopSourceRef IOPSNotificationCreateRunLoopSource(void (*callback)(void *context), void *context);

#ifndef kStateDir   // (the Mac tests run the job on a simulated iPad, tools/chargejob-sim.h, with these in a folder of their own)
#define kStateDir "/var/jb/var/lib/macstatusbaranddock"
#endif
#define kStateFile kStateDir "/chargelimit.plist"
#ifndef kLogFile
#define kLogFile "/var/jb/var/log/msbdcharge.log"
#endif

// ---- log (a few lines per change; kept under 256 KB, one old copy)
static void Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void Log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    struct stat st;
    if (stat(kLogFile, &st) == 0 && st.st_size > 256 * 1024) rename(kLogFile, kLogFile ".old");
    FILE *f = fopen(kLogFile, "a");
    if (!f) return;
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fprintf(f, "%s %s\n", [df stringFromDate:[NSDate date]].UTF8String, line.UTF8String);
    fclose(f);
}

// ---- the battery service
static io_service_t gBattery;
static BOOL gPMU;   // AppleARMPMUCharger (A9X, A10X): the hold is PredictiveChargingInhibit; else (AppleSmartBattery) powerd's ChargeInhibit
static BOOL FindBattery(void) {
    if (gBattery) return YES;
    gBattery = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (gBattery) { gPMU = NO; return YES; }
    gBattery = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleARMPMUCharger"));
    if (gBattery) { gPMU = YES; return YES; }
    return NO;
}
static NSDictionary *BatteryProps(void) {
    if (!FindBattery()) return nil;
    CFMutableDictionaryRef p = NULL;
    if (IORegistryEntryCreateCFProperties(gBattery, &p, kCFAllocatorDefault, 0) != KERN_SUCCESS || !p) return nil;
    return (__bridge_transfer NSDictionary *)p;
}
static int Int(NSDictionary *d, NSString *k) { id v = d[k]; return [v respondsToSelector:@selector(intValue)] ? [v intValue] : -1; }
static long long LL(id v) { return [v respondsToSelector:@selector(longLongValue)] ? [v longLongValue] : -1; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:[NSDictionary class]] ? v : nil; }
// an adapter cut showing in the battery service (ours or one left behind): common/ChargeLimit.h
static int CutShown(NSDictionary *b) {
    NSDictionary *cd = Dict(b[@"ChargerData"]);
    id ncr = cd[@"NotChargingReason"];
    uint64_t reason = [ncr respondsToSelector:@selector(unsignedLongLongValue)] ? [ncr unsignedLongLongValue] : 0;
    return MSBDChargeCutShown(Int(b, @"AppleRawExternalConnected"), Int(b, @"ExternalConnected"), reason,
                              cd[@"ChargerInhibitReason"] ? LL(cd[@"ChargerInhibitReason"]) : -1);
}
// the adapter as the battery service describes it (kept while our cut is up on the SMC iPads: common/ChargeLimit.h)
static MSBDChargeAdapter AdapterNow(NSDictionary *b) {
    NSDictionary *ad = Dict(b[@"AdapterDetails"]);
    MSBDChargeAdapter a = { ad[@"Watts"] ? LL(ad[@"Watts"]) : 0, ad[@"FamilyCode"] ? LL(ad[@"FamilyCode"]) : 0, ad[@"AdapterID"] ? LL(ad[@"AdapterID"]) : 0,
                            [ad[@"Description"] isKindOfClass:[NSString class]] ? [(NSString *)ad[@"Description"] hash] : 0 };
    if (a.watts < 0) a.watts = 0;
    return a;
}
static IOReturn SetPredictiveInhibit(BOOL on) {
    if (!FindBattery() || !gPMU) return kIOReturnUnsupported;
    return IORegistryEntrySetCFProperties(gBattery, (__bridge CFTypeRef)@{ @"PredictiveChargingInhibit": on ? @YES : @NO });
}

// ---- powerd's assertions
static IOPMAssertionID gHold, gDown;
static BOOL gPCIOn;
static IOPMAssertionID Raise(NSString *type, NSString *name) {
    IOPMAssertionID a = 0;
    IOReturn r = IOPMAssertionCreateWithProperties((__bridge CFDictionaryRef)@{ @"AssertType": type, @"AssertName": name, @"AssertLevel": @255 }, &a);
    if (r != kIOReturnSuccess) { Log(@"%@ not raised: 0x%x", type, r); return 0; }
    return a;
}
static void Lower(IOPMAssertionID *a) { if (*a) { IOPMAssertionRelease(*a); *a = 0; } }
// What powerd holds for this process now: the kinds and the names of its assertions (a powerd that started again knows none of ours). nil: no
// answer -- taken as all held, so nothing is raised twice; the next check asks again.
static NSSet *PowerdHolds(void) {
    CFDictionaryRef all = NULL;
    if (IOPMCopyAssertionsByProcess(&all) != kIOReturnSuccess || !all) return nil;
    NSDictionary *byPID = (__bridge_transfer NSDictionary *)all;
    NSMutableSet *held = [NSMutableSet set];
    id mine = byPID[@(getpid())];
    for (NSDictionary *a in [mine isKindOfClass:[NSArray class]] ? mine : @[]) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        if ([a[@"AssertType"] isKindOfClass:[NSString class]]) [held addObject:a[@"AssertType"]];
        if ([a[@"AssertName"] isKindOfClass:[NSString class]]) [held addObject:a[@"AssertName"]];
    }
    return held;
}

// ---- the stay-awake (charging toward the limit, coming down: the job must be awake to see the limit reached)
// iPadOS 16-18 drop a daemon's PreventUserIdleSystemSleep about 10 minutes after it is raised, with the display off on battery (iPad 2 16.7.7,
// 17.5.1, A12Z 18.5, 2 Nov: the job's went 9-20 minutes after each raise, whether powerd had made it at once or IOKit handed it over later;
// 15.6.1 kept it), and the iPad then sleeps: past the limit while charging to it, for days while coming down. (SystemIsActive is not dropped,
// but it does not keep the iPad awake either: it slept with one held.) So the stay-awake is renewed every 5 minutes, overlapping: a new one is
// raised under the other name, and the old one let go only once powerd lists the new one (IOKit hands a process's later assertions over within
// about a minute) -- none gets old enough to be dropped, and there is never a moment with none.
static IOPMAssertionID gAwake, gAwakeNext;   // the stay-awake, and the one taking over from it
static int gAwakeSlot = 1, gAwakeNextSlot;   // which name each has: "... (stay awake 1)" / "(stay awake 2)"
static double gAwakeSince, gAwakeNextSince;
static int gAwakeNotListed;                  // renewals in a row whose new one powerd never listed (said once, retried slower)
static NSString *AwakeName(int slot) { return [NSString stringWithFormat:@"MacStatusBar&Dock Charge Limit (stay awake %d)", slot]; }
static void StayAwakeOff(void) { Lower(&gAwake); Lower(&gAwakeNext); gAwakeNotListed = 0; }
// A powerd that started again (2 Nov, iPad 2 16.7.7, launchctl kickstart): it knows none of our assertions and does not answer a process's
// "what do I hold" (IOPMCopyAssertionsByProcess fails) until that process has made one with it -- so the job's checks only ever got "no
// answer" and raised nothing again: the cut stayed in the driver, unknown to powerd, and the stay-awake was simply gone. Two looks in a row
// without an answer: each of ours raised anew (the new one first, the old one let go after: a cut or a hold never blinks off, which would
// look like plugging in), at most once every 10 minutes.
static double gLastRefresh;
static int gNoAnswer;
static void RaiseAgainAfter(IOPMAssertionID *a, NSString *type, NSString *name) {
    if (!*a) return;
    IOPMAssertionID fresh = Raise(type, name), old = *a;
    if (!fresh) return;   // (kept: Raise said why)
    *a = fresh; IOPMAssertionRelease(old);
}
static void StayAwake(NSSet *held, double now) {
    if (!gAwake) { gAwake = Raise(@"PreventUserIdleSystemSleep", AwakeName(gAwakeSlot)); gAwakeSince = now; return; }
    if (!held) return;   // (powerd did not answer: as it is, asked again at the next look)
    if (gAwakeNext) {
        if ([held containsObject:AwakeName(gAwakeNextSlot)]) {   // the new one is held: the old one goes
            Lower(&gAwake); gAwake = gAwakeNext; gAwakeSlot = gAwakeNextSlot; gAwakeSince = gAwakeNextSince; gAwakeNext = 0; gAwakeNotListed = 0;
#if DEBUG
            Log(@"stay-awake renewed (%@)", AwakeName(gAwakeSlot));
#endif
            return;
        }
        if (now - gAwakeNextSince < 180) return;   // (not handed over yet: the old one stays meanwhile)
#if DEBUG
        if (!gAwakeNotListed) Log(@"powerd did not list the new stay-awake within 3 minutes: raised again");
#endif
        gAwakeNotListed++;
        Lower(&gAwakeNext);
    }
    if (now - gAwakeSince > 120 && ![held containsObject:AwakeName(gAwakeSlot)]) {   // the one we hold is gone (a restarted powerd, or dropped)
        Log(@"powerd does not hold our stay-awake (restarted, or dropped): raised again");
        Lower(&gAwake); gAwakeSlot = 3 - gAwakeSlot; gAwake = Raise(@"PreventUserIdleSystemSleep", AwakeName(gAwakeSlot)); gAwakeSince = now; return;
    }
    if (now - gAwakeSince >= 300 * (gAwakeNotListed > 2 ? 3 : 1)) {   // renewed every 5 minutes (every 15 after three that powerd never listed)
        gAwakeNextSlot = 3 - gAwakeSlot; gAwakeNext = Raise(@"PreventUserIdleSystemSleep", AwakeName(gAwakeNextSlot)); gAwakeNextSince = now;
    }
}
// A hold or an adapter cut raised and let go at once: powerd's lower handler writes "charging allowed" (IsCharging) / "adapter connected"
// (ExternalConnected) back to the battery service -- what clears one that a restarted powerd left in the driver. When another process holds
// the same kind, nothing changes (powerd only acts when the last one goes).
static void Pulse(NSString *type) { IOPMAssertionID a = Raise(type, @"MacStatusBar&Dock Charge Limit (reset)"); Lower(&a); }
// The same for --reset, where powerd may just have been started over and answers only some seconds later: tried each second until powerd takes
// it, 10 s at most. NO: never taken.
static BOOL PulseOncePowerdAnswers(NSString *type) {
    for (int i = 0; i < 10; i++) {
        if (i) sleep(1);
        IOPMAssertionID a = 0;
        if (IOPMAssertionCreateWithProperties((__bridge CFDictionaryRef)@{ @"AssertType": type, @"AssertName": @"MacStatusBar&Dock Charge Limit (reset)", @"AssertLevel": @255 },
                                              &a) == kIOReturnSuccess) { IOPMAssertionRelease(a); return YES; }
    }
    Log(@"%@ not raised: powerd did not answer for 10 s", type);
    return NO;
}

// ---- iPadOS 18's own charge limit (1.8.6; plans/release-1.8.7.md "Charge Limit on iPadOS 18")
// On 18.5 the SMC battery driver ignores powerd's IsCharging = false: the A12Z charged at 1.3-2.8 A under ChargeInhibit on a 7 W and a 17 W
// charger. iPadOS 18 stops charging at a level through powerd's own SOC-limit service (com.apple.iokit.powerdxpc, "chargeSocLimit"), which writes
// the SMC key CHLS: what the iPhone's 80 % Limit uses. powerd offers it only where the SMC has CHLS; there the hold is a policy of ours. A policy
// outlives the process that set it (powerd lists it as "Terminated" and keeps it until it is removed or the iPad restarts; it archives them per
// boot session, so a powerd started over may well still have it), so each token is kept in the state file before its policy is set, and every
// start and --reset removes the ones kept (ResetCharging); the job removes its own at every let-go (HoldOff, --stop, SIGTERM, the idle end). A
// token stays kept until its policy is removed or powerd lists no policy of ours it could be: one powerd did not take (no answer, a powerd just
// started over) is tried again at each look, and the job does not end while one is left (SocRemoveLeftovers, EndIdle). Elsewhere (the M1, the
// PMU iPads) the hold is as before.
static int gSoc;                 // 1: the hold is powerd's SOC-limit policy (decided once at start, logged)
static NSString *gSocToken;      // our policy now (nil: none)
static int gSocAt = -1;          // the level it was set to
static int gSocWant = -1;        // the level the hold asks for (Evaluate)
static NSMutableDictionary *gState;
static void SaveState(void);
#define kSocReason "MacStatusBar&Dock Charge Limit"
#ifndef MSBD_CHARGE_SOC_SIM
// libxpc's C calls, looked up at run time (no xpc header in the SDK); every object we get back is released.
typedef void *MSBDXPC;
static struct {
    MSBDXPC (*dictCreate)(const char *const *, const MSBDXPC *, size_t);
    void (*setInt)(MSBDXPC, const char *, int64_t); void (*setBool)(MSBDXPC, const char *, bool); void (*setString)(MSBDXPC, const char *, const char *);
    void (*setValue)(MSBDXPC, const char *, MSBDXPC);
    MSBDXPC (*getValue)(MSBDXPC, const char *); const char *(*getString)(MSBDXPC, const char *); uint64_t (*getUInt)(MSBDXPC, const char *);
    size_t (*arrayCount)(MSBDXPC); MSBDXPC (*arrayGet)(MSBDXPC, size_t);
    MSBDXPC (*connect)(const char *, void *, uint64_t); void (*setHandler)(MSBDXPC, void (^)(MSBDXPC)); void (*resume)(MSBDXPC);
    MSBDXPC (*sendSync)(MSBDXPC, MSBDXPC); const void *(*type)(MSBDXPC); void (*release)(MSBDXPC);
    const void *typeDict, *typeArray;
    MSBDXPC conn; int ready;
} X;
static BOOL SocXPC(void) {
    if (X.ready) return X.ready > 0;
    X.ready = -1;
    void *h = RTLD_DEFAULT;
    X.dictCreate = dlsym(h, "xpc_dictionary_create"); X.setInt = dlsym(h, "xpc_dictionary_set_int64"); X.setBool = dlsym(h, "xpc_dictionary_set_bool");
    X.setString = dlsym(h, "xpc_dictionary_set_string"); X.setValue = dlsym(h, "xpc_dictionary_set_value"); X.getValue = dlsym(h, "xpc_dictionary_get_value");
    X.getString = dlsym(h, "xpc_dictionary_get_string"); X.getUInt = dlsym(h, "xpc_dictionary_get_uint64"); X.arrayCount = dlsym(h, "xpc_array_get_count");
    X.arrayGet = dlsym(h, "xpc_array_get_value"); X.connect = dlsym(h, "xpc_connection_create_mach_service"); X.setHandler = dlsym(h, "xpc_connection_set_event_handler");
    X.resume = dlsym(h, "xpc_connection_resume"); X.sendSync = dlsym(h, "xpc_connection_send_message_with_reply_sync"); X.type = dlsym(h, "xpc_get_type");
    X.release = dlsym(h, "xpc_release"); X.typeDict = dlsym(h, "_xpc_type_dictionary"); X.typeArray = dlsym(h, "_xpc_type_array");
    if (!X.dictCreate || !X.setInt || !X.setBool || !X.setString || !X.setValue || !X.getValue || !X.getString || !X.getUInt || !X.arrayCount || !X.arrayGet ||
        !X.connect || !X.setHandler || !X.resume || !X.sendSync || !X.type || !X.release || !X.typeDict || !X.typeArray) return NO;
    X.conn = X.connect("com.apple.iokit.powerdxpc", NULL, 0);
    if (!X.conn) return NO;
    X.setHandler(X.conn, ^(MSBDXPC e) { (void)e; });
    X.resume(X.conn);
    X.ready = 1;
    return YES;
}
// One request: the inner dictionary under "chargeSocLimit". The reply (a dictionary whose returnCode is 0) or NULL: the caller releases it.
static MSBDXPC SocRequest(int64_t action, const char *token, int soc) {
    if (!SocXPC()) return NULL;
    MSBDXPC in = X.dictCreate(NULL, NULL, 0), msg = X.dictCreate(NULL, NULL, 0);
    X.setInt(in, "chargeSocLimitAction", action);
    if (token) X.setString(in, "chargeSocLimitToken", token);
    if (action == 3) {
        X.setInt(in, "chargeSocLimitSoc", soc); X.setBool(in, "chargeSocLimitDrain", false); X.setBool(in, "chargeSocLimitNoChargeToFull", true);
        X.setString(in, "chargeSocLimitReason", kSocReason);
    }
    X.setValue(msg, "chargeSocLimit", in);
    MSBDXPC r = X.sendSync(X.conn, msg);
    X.release(msg); X.release(in);
    if (r && (X.type(r) != X.typeDict || X.getUInt(r, "returnCode") != 0)) { X.release(r); r = NULL; }
    return r;
}
static BOOL SocQueryOurs(int *ours) {   // action 4: the policies powerd has now; how many are ours (by their reason). NO: no such service here
    MSBDXPC r = SocRequest(4, NULL, 0);
    if (!r) return NO;
    int n = 0;
    MSBDXPC a = X.getValue(r, "chargeSocLimit");
    if (a && X.type(a) == X.typeArray)
        for (size_t i = 0; i < X.arrayCount(a); i++) {
            MSBDXPC p = X.arrayGet(a, i);
            const char *why = p && X.type(p) == X.typeDict ? X.getString(p, "chargeSocLimitReason") : NULL;
            if (why && !strcmp(why, kSocReason)) n++;
        }
    X.release(r);
    if (ours) *ours = n;
    return YES;
}
static NSString *SocCreate(void) {   // action 1: a new policy's token
    MSBDXPC r = SocRequest(1, NULL, 0);
    if (!r) return nil;
    const char *t = X.getString(r, "chargeSocLimitToken");
    NSString *tok = t && *t ? @(t) : nil;
    X.release(r);
    return tok;
}
static BOOL SocSet(NSString *tok, int soc) { MSBDXPC r = SocRequest(3, tok.UTF8String, soc); if (r) X.release(r); return r != NULL; }
static BOOL SocRemove(NSString *tok) { MSBDXPC r = SocRequest(2, tok.UTF8String, 0); if (r) X.release(r); return r != NULL; }
#else
static BOOL SocQueryOurs(int *ours);
static NSString *SocCreate(void);
static BOOL SocSet(NSString *tok, int soc);
static BOOL SocRemove(NSString *tok);
#endif
// The tokens kept (the state file's "socTokens"): added before the policy is set, dropped once removed.
static void SocKeep(NSDictionary *st, NSString *tok, BOOL add) {
    NSMutableDictionary *s = (NSMutableDictionary *)st;
    NSMutableArray *a = [NSMutableArray array];
    for (id t in [s[@"socTokens"] isKindOfClass:[NSArray class]] ? s[@"socTokens"] : @[]) if ([t isKindOfClass:[NSString class]] && ![t isEqual:tok]) [a addObject:t];
    if (add) [a addObject:tok];
    if (a.count) s[@"socTokens"] = a; else [s removeObjectForKey:@"socTokens"];
}
// The kept policies other than `live` (the job's own now; nil: none) removed. A token is dropped from the list once its policy is removed, or once
// powerd answers and lists no policy of ours beyond the live one (liveListed: 1 when the live one is set, so listed by our reason): a token from
// before a restart of the iPad, or one powerd lost, has nothing left to remove. A removal powerd did not take while it lists more of ours, or with
// no answer at all, keeps the token: tried again later. Nothing is asked when no token but the live one is kept.
typedef struct { int removed, dropped; NSUInteger left; BOOL changed; } SocKept;
static SocKept SocRemoveKept(NSMutableDictionary *st, NSString *live, int liveListed) {
    SocKept k = { 0, 0, 0, NO };
    NSMutableArray *keep = [NSMutableArray array], *failed = [NSMutableArray array];
    for (id t in [st[@"socTokens"] isKindOfClass:[NSArray class]] ? st[@"socTokens"] : @[]) {
        if (![t isKindOfClass:[NSString class]]) { k.changed = YES; continue; }
        if ([t isEqual:live]) { [keep addObject:t]; continue; }
        if (SocRemove(t)) { k.removed++; k.changed = YES; } else { [keep addObject:t]; [failed addObject:t]; }
    }
    int ours = 0;
    if (failed.count && SocQueryOurs(&ours) && ours <= liveListed) {
        [keep removeObjectsInArray:failed]; k.dropped = (int)failed.count; [failed removeAllObjects]; k.changed = YES;
    }
    k.left = failed.count;
    if (k.changed) { if (keep.count) st[@"socTokens"] = keep; else [st removeObjectForKey:@"socTokens"]; }
    return k;
}
static NSUInteger SocKeptCount(NSDictionary *st) { return [st[@"socTokens"] isKindOfClass:[NSArray class]] ? [st[@"socTokens"] count] : 0; }
static void SocHoldOn(int at, BOOL again) {
    if (at < 1) at = 1;
    if (gSocToken && gSocAt == at && !again) return;
    if (gSocToken && SocSet(gSocToken, at)) { if (gSocAt != at || again) Log(@"iPadOS's charge limit set to %d %%%@", at, again ? @" (again)" : @""); gSocAt = at; return; }
    if (gSocToken) {   // (not taken: powerd has no policy with this token now, or did not answer. A new one; the old token stays kept, removed later if
                       //  powerd still has it: SocRemoveLeftovers)
        Log(@"iPadOS's charge limit: powerd did not take our policy at %d %%: a new one", at);
        gSocToken = nil; gSocAt = -1;
    }
    NSString *t = SocCreate();
    if (!t) { Log(@"iPadOS's charge limit: powerd gave no policy"); return; }
    gSocToken = t;
    if (gState) { SocKeep(gState, t, YES); SaveState(); }   // (kept before it is set: a policy outlives the job)
    if (SocSet(t, at)) { Log(@"iPadOS's charge limit set to %d %%%@", at, again ? @" (again)" : @""); gSocAt = at; }
    else Log(@"iPadOS's charge limit: setting %d %% failed", at);
}
static void SocHoldOff(void) {
    if (!gSocToken) return;
    if (SocRemove(gSocToken)) { Log(@"iPadOS's charge limit removed"); if (gState) { SocKeep(gState, gSocToken, NO); SaveState(); } }
    else Log(@"iPadOS's charge limit: removing it failed (kept: tried again at each look, and the job does not end before)");
    gSocToken = nil; gSocAt = -1;
}
// The job's look at the kept policies that are not its own now (one whose removal powerd did not take, an earlier run's): removed (SocRemoveKept).
// gSocLeft: how many are still to be removed; the job looks every minute and does not end while one is left (EndIdle).
static NSUInteger gSocLeft;
static void SocRemoveLeftovers(void) {
    if (!gState) return;
    SocKept k = SocRemoveKept(gState, gSocToken, gSocToken && gSocAt >= 0);
    if (k.changed) SaveState();
    if (k.removed) Log(@"iPadOS's charge limit: %d kept policy of ours removed", k.removed);
    if (k.dropped) Log(@"iPadOS's charge limit: %d kept token dropped (powerd lists no such policy of ours)", k.dropped);
    if (k.left && k.left != gSocLeft) Log(@"iPadOS's charge limit: %lu kept policy of ours not removed yet (powerd did not take it): tried again each minute", (unsigned long)k.left);
    gSocLeft = k.left;
}
// A powerd just started over answers some seconds later (the Sleep Guard tells the job right after its kickstart): waited for, 10 s at most.
static BOOL SocWaitPowerd(void) {
    for (int i = 0; i < 10; i++) { if (i) sleep(1); if (SocQueryOurs(NULL)) return YES; }
    return NO;
}

static void HoldOn(NSSet *held) {
    if (gSoc) { SocHoldOn(gSocWant, held == nil); return; }
    if (gPMU) {
        if (!gPCIOn) { IOReturn r = SetPredictiveInhibit(YES); gPCIOn = r == kIOReturnSuccess; if (!gPCIOn) Log(@"PredictiveChargingInhibit not set: 0x%x", r); }
    } else {
        if (gHold && held && ![held containsObject:@"ChargeInhibit"]) { Log(@"powerd no longer holds our hold (restarted?): raised again"); Lower(&gHold); }
        if (!gHold) gHold = Raise(@"ChargeInhibit", @"MacStatusBar&Dock Charge Limit (on hold)");
    }
}
static void HoldOff(void) {
    SocHoldOff();
    if (gPMU) { if (gPCIOn) { SetPredictiveInhibit(NO); gPCIOn = NO; } }
    else Lower(&gHold);
}
static double gOwnCutEnded;
// (SpringBoard is told first: the power coming back is not a new connection, so no charging chime and no Lock Screen lit for it -- statusbar/ChargeQuiet.x)
static void CutOff(double now) { if (gDown) { notify_post(MSBD_CHARGE_CUT_ENDING); Lower(&gDown); gOwnCutEnded = now; } }

// ---- a hold or cut of ours that no job holds any more (common/ChargeLimit.h MSBDChargeLeftoverKind): what powerd lists by our name under another
// pid -- but not one of a live msbdcharge (the job, while --reset is run by hand; a helper's raise-and-let-go under way): its owner lets go of it.
extern int proc_name(int pid, void *buffer, uint32_t buffersize);
static BOOL LiveChargeProcess(int pid) {
    char name[64] = "";
    return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM) && proc_name(pid, name, sizeof name) > 0 && !strcmp(name, "msbdcharge");
}
typedef struct { int hold, cut; NSString *what; } Leftovers;
static Leftovers FindLeftovers(void) {
    Leftovers l = { 0, 0, @"" };
    CFDictionaryRef all = NULL;
    if (IOPMCopyAssertionsByProcess(&all) != kIOReturnSuccess || !all) return l;
    NSDictionary *byPID = (__bridge_transfer NSDictionary *)all;
    NSMutableArray *what = [NSMutableArray array];
    for (id pid in byPID) {
        if (![pid respondsToSelector:@selector(intValue)]) continue;
        for (NSDictionary *a in [byPID[pid] isKindOfClass:[NSArray class]] ? byPID[pid] : @[]) {
            if (![a isKindOfClass:[NSDictionary class]] || ![a[@"AssertType"] isKindOfClass:[NSString class]] || ![a[@"AssertName"] isKindOfClass:[NSString class]]) continue;
            int kind = MSBDChargeLeftoverKind([a[@"AssertType"] UTF8String], [a[@"AssertName"] UTF8String], [pid intValue], getpid());
            if (!kind || LiveChargeProcess([pid intValue])) continue;
            if (kind == 1) l.hold = 1; else l.cut = 1;
            [what addObject:[NSString stringWithFormat:@"%@ \"%@\" (pid %@, listed as %@)", a[@"AssertType"], a[@"AssertName"], pid,
                             [a[@"Process Name"] isKindOfClass:[NSString class]] ? a[@"Process Name"] : @"?"]];
        }
    }
    l.what = [what componentsJoinedByString:@"; "];
    return l;
}
// What the Sleep Guard waits for before it starts powerd over (common/SleepGuard.h), read the way it reads them. The screen: SpringBoard's own
// "com.apple.springboard.hasBlankedScreen" (state 1 = blank); no answer counts as on.
static BOOL ScreenOff(void) {
    static int token; static BOOL registered;
    if (!registered) registered = notify_register_check("com.apple.springboard.hasBlankedScreen", &token) == NOTIFY_STATUS_OK;
    uint64_t blank = 0;
    return registered && notify_get_state(token, &blank) == NOTIFY_STATUS_OK && blank != 0;
}
// Keep-awake assertions of live processes that a powerd restart would drop (MSBDSGLiveOther: a download, a backup, audio; not powerd's own, not
// a Charge Limit job's -- ours are raised anew at once): how many, and which in *what. -1: powerd did not answer (counted as some: wait). Owners
// are told apart by pid and name only, not by start time: an owner counts as live more often, and waiting is the safe side.
static int LiveKeepAwake(NSString **what) {
    CFDictionaryRef all = NULL;
    if (IOPMCopyAssertionsByProcess(&all) != kIOReturnSuccess || !all) return -1;
    NSDictionary *byPID = (__bridge_transfer NSDictionary *)all;
    double now = [NSDate date].timeIntervalSince1970;
    NSMutableArray *live = [NSMutableArray array];
    for (id pid in byPID) {
        if (![pid respondsToSelector:@selector(intValue)] || [pid intValue] == getpid()) continue;
        int p = [pid intValue];
        BOOL exists = p > 0 && (kill(p, 0) == 0 || errno == EPERM);
        char proc[64] = "";
        if (exists) proc_name(p, proc, sizeof proc);
        for (NSDictionary *a in [byPID[pid] isKindOfClass:[NSArray class]] ? byPID[pid] : @[]) {
            if (![a isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = [a[@"AssertType"] isKindOfClass:[NSString class]] ? a[@"AssertType"] : @"";
            NSString *owner = [a[@"Process Name"] isKindOfClass:[NSString class]] ? a[@"Process Name"] : @"";
            long level = [a[@"AssertLevel"] respondsToSelector:@selector(longValue)] ? [a[@"AssertLevel"] longValue] : 0;
            int gone = MSBDSGOwnerGone(p, exists, proc, owner.UTF8String, 0, -1, 0, now);
            if (MSBDSGLiveOther(type.UTF8String, level, gone, !strcmp(proc, "powerd") || [owner isEqualToString:@"powerd"], *proc ? proc : owner.UTF8String))
                [live addObject:[NSString stringWithFormat:@"%@ \"%@\" (%@ %d)", type, a[@"AssertName"], owner, p]];
        }
    }
    if (what) *what = [live componentsJoinedByString:@"; "];
    return (int)live.count;
}
// powerd started over: the only way an assertion of a process that is gone goes (the Sleep Guard's way, macsettings/sshtoggled/
// SleepGuardDaemon.h). It drops every assertion -- libIOKit hands a live process's async ones to the new powerd, the others go unless their
// owner raises them again -- and every scheduled wake: those are copied first and scheduled again (still ahead, not back already: same time,
// id and type, so their owner can still cancel them). The battery keeps what powerd last wrote to it: the caller raises and lets go what was
// left (Pulse), so the new powerd writes "allowed". IOKit's wake calls looked up, as the Sleep Guard does (none: the wakes are not put back).
extern char **environ;
static NSString *WakeKey(NSDictionary *e) {
    return [NSString stringWithFormat:@"%@|%@|%.3f", e[@"scheduledby"], e[@"eventtype"], [(NSDate *)e[@"time"] timeIntervalSinceReferenceDate]];
}
static BOOL WakeUsable(id e) {
    return [e isKindOfClass:[NSDictionary class]] && [e[@"time"] isKindOfClass:[NSDate class]] && [e[@"scheduledby"] isKindOfClass:[NSString class]]
        && [e[@"eventtype"] isKindOfClass:[NSString class]];
}
// A program run and waited for, 15 s at most (looked at every 100 ms): one that hangs is killed and counts as failed -- this is the job's only
// thread, and what it holds would stay as it is meanwhile (a cut nobody ends at the limit, a stop note not heard). YES: it exited 0.
static BOOL RunWaited(const char *path, char *const argv[]) {
    pid_t pid = 0; int st = -1;
    if (posix_spawn(&pid, path, NULL, NULL, argv, environ) != 0) return NO;
    for (int i = 0; i < 150; i++) {
        pid_t w = waitpid(pid, &st, WNOHANG);
        if (w == pid) return WIFEXITED(st) && WEXITSTATUS(st) == 0;
        if (w < 0 && errno != EINTR) return NO;
        usleep(100000);
    }
    kill(pid, SIGKILL);
    for (int i = 0; i < 20 && waitpid(pid, &st, WNOHANG) == 0; i++) usleep(100000);   // (reaped once it is gone)
    Log(@"%s did not finish within 15 s: stopped", argv[0]);
    return NO;
}
static BOOL RestartPowerd(NSString **result) {
    CFArrayRef (*copyWakes)(void) = (CFArrayRef (*)(void))dlsym(RTLD_DEFAULT, "IOPMCopyScheduledPowerEvents");
    IOReturn (*schedule)(CFDateRef, CFStringRef, CFStringRef) = (IOReturn (*)(CFDateRef, CFStringRef, CFStringRef))dlsym(RTLD_DEFAULT, "IOPMSchedulePowerEvent");
    CFArrayRef w0 = copyWakes ? copyWakes() : NULL;
    NSArray *before = w0 ? CFBridgingRelease(w0) : @[];
    const char *lc = access("/var/jb/usr/bin/launchctl", X_OK) == 0 ? "/var/jb/usr/bin/launchctl" : "/bin/launchctl";
    char *argv[] = { (char *)"launchctl", (char *)"kickstart", (char *)"-k", (char *)"system/com.apple.powerd", NULL };
    BOOL ok = RunWaited(lc, argv);
    sleep(3);   // (powerd up again)
    // (a wake refused -- a powerd not answering yet -- is tried again, up to 3 more times 2 s apart: those not back are scheduled each time)
    int again = 0, refused = 0;
    for (int tries = 0; tries < 4 && (!tries || refused); tries++) {
        if (tries) sleep(2);
        CFArrayRef w1 = copyWakes ? copyWakes() : NULL;
        NSMutableSet *have = [NSMutableSet set];
        for (id e in w1 ? CFBridgingRelease(w1) : @[]) if (WakeUsable(e)) [have addObject:WakeKey(e)];
        double t = [NSDate date].timeIntervalSinceReferenceDate;
        refused = 0;
        for (id e in before) {
            if (!WakeUsable(e) || [(NSDate *)e[@"time"] timeIntervalSinceReferenceDate] <= t + 2 || [have containsObject:WakeKey(e)]) continue;
            [have addObject:WakeKey(e)];
            if (schedule && schedule((__bridge CFDateRef)e[@"time"], (__bridge CFStringRef)e[@"scheduledby"], (__bridge CFStringRef)e[@"eventtype"]) == kIOReturnSuccess) again++;
            else refused++;
        }
    }
    if (result) *result = [NSString stringWithFormat:@"powerd %@; scheduled wakes: %lu before, %d scheduled again%@", ok ? @"started over" : @"NOT started over (launchctl failed)",
                           (unsigned long)before.count, again, refused ? [NSString stringWithFormat:@", %d refused", refused] : @""];
    return ok;
}

// Charging back to iPadOS's own, whatever an earlier run left: the inhibit key cleared (PMU); a hold still showing in the battery service (on the
// cable, not charging though well under full) raised and let go at once. A cut still showing: the same, but only for the prerm's --reset, and
// only once it has had 15 s to end by itself (a cut ends some seconds after its owner lets it go, and each end of a cut lights the Lock Screen);
// at a start the job's own check (Evaluate) lets one go once it has shown for a minute. The prerm's --reset also clears a hold or cut of ours that
// powerd still lists 10 s after the job was stopped (it kept it after its owner was gone: it would keep charging off for good -- F3 on the M1):
// powerd started over and looked at again (one still listed -- the restart failed -- is started over once more), each kind that was left raised
// and let go once the new powerd answers (it can take some seconds). And --reset reads the battery again after its raise-and-let-go, and does it
// once more while a hold or cut still shows (up to 3 more times, 5 s apart): one the new powerd missed would leave F3 with the job removed.
// jobRuns: --reset run by hand while a job runs (it holds the job lock): what is the job's own -- the PMU key, its policies of iPadOS's charge
// limit (its live one among the kept tokens: removed, the A12Z charged past the limit with the job still saying "on hold") -- is left to it, as
// FindLeftovers leaves a live job's assertions; the job removes its own kept tokens but the live one itself (SocRemoveLeftovers).
static void ResetCharging(NSString *why, BOOL cuts, BOOL jobRuns) {
    FindBattery();
    if (gPMU && !jobRuns) SetPredictiveInhibit(NO);
    gPCIOn = NO;
    BOOL leftCut = NO;
    NSMutableArray *cleared = [NSMutableArray array];
    // iPadOS 18's charge limit: the policies an earlier run kept the tokens of (it outlives its process) removed first (SocRemoveKept). A token is
    // dropped only once its policy is removed or powerd lists none of ours it could be (a restart of the iPad since); one powerd did not take
    // stays kept: --reset tries for 10 s (powerd may just have been started over), the job's start leaves it to the job's looks.
    NSMutableDictionary *st = jobRuns ? nil : [NSMutableDictionary dictionaryWithContentsOfFile:@kStateFile];
    NSUInteger toks = SocKeptCount(st);
    if (toks) {
        SocKept k = SocRemoveKept(st, nil, 0);
        int removed = k.removed, dropped = k.dropped;
        for (int i = 0; cuts && k.left && i < 10; i++) { sleep(1); k = SocRemoveKept(st, nil, 0); removed += k.removed; dropped += k.dropped; }
        mkdir(kStateDir, 0755); [st writeToFile:@kStateFile atomically:YES];
        [cleared addObject:[NSString stringWithFormat:@"iPadOS's charge limit of an earlier run: %d of %lu removed%@%@", removed, (unsigned long)toks,
                            dropped ? [NSString stringWithFormat:@", %d dropped (powerd lists no such policy of ours)", dropped] : @"",
                            k.left ? [NSString stringWithFormat:@", %lu kept to be removed (powerd did not take it)", (unsigned long)k.left] : @""]];
    }
    gSocToken = nil; gSocAt = -1;
    if (cuts) {
        Leftovers lo = FindLeftovers();
        for (int i = 0; i < 10 && (lo.hold || lo.cut); i++) { sleep(1); lo = FindLeftovers(); }
        for (int n = 0; n < 2 && (lo.hold || lo.cut); n++) {
            NSString *r = nil;
            // (a job still running -- --reset run by hand -- is told, as after the Sleep Guard's restart, and raises its own anew before the
            // raise-and-let-go below: it would otherwise write "allowed" under the job's hold, which the restart dropped)
            if (RestartPowerd(&r)) { notify_post(MSBD_SG_POWERD); sleep(1); }
            if (lo.hold) PulseOncePowerdAnswers(@"ChargeInhibit");
            if (lo.cut) { PulseOncePowerdAnswers(@"DisableInflow"); leftCut = YES; }
            [cleared addObject:[NSString stringWithFormat:@"%@; %@", lo.what, r]];
            lo = FindLeftovers();
        }
        if (lo.hold || lo.cut) [cleared addObject:[NSString stringWithFormat:@"still listed: %@", lo.what]];
    }
    NSDictionary *b = BatteryProps();
    BOOL holdLeft = NO, cutLeft = NO;
    for (int i = 0; i < (cuts ? 4 : 1); i++) {
        if (i) { sleep(5); b = BatteryProps(); }
        int soc = Int(b, @"CurrentCapacity");
        BOOL hold = Int(b, @"AppleRawExternalConnected") == 1 && Int(b, @"IsCharging") == 0 && Int(b, @"FullyCharged") != 1 && soc >= 0 && soc < 95, cut = NO;
        if (hold) { holdLeft = YES; if (cuts) PulseOncePowerdAnswers(@"ChargeInhibit"); else Pulse(@"ChargeInhibit"); }
        if (cuts) {
            if (!i && !leftCut) for (int j = 0; j < 15 && b && CutShown(b); j++) { sleep(1); b = BatteryProps(); }
            cut = b && CutShown(b);
            if (cut) { cutLeft = YES; PulseOncePowerdAnswers(@"DisableInflow"); }
        }
        if (!hold && !cut) break;
    }
    if (why || holdLeft || cutLeft || cleared.count)
        Log(@"charging reset (%@%@)%@%@%@", why ?: @"start", jobRuns ? @"; a job is running: its own hold left to it" : @"", holdLeft ? @": a hold was showing in the battery service" : @"", cutLeft ? @": an adapter cut was showing" : @"",
            cleared.count ? [@": left with powerd after its owner was gone: " stringByAppendingString:[cleared componentsJoinedByString:@"; then "]] : @"");
}

// ---- what the tweak's settings say (read as mobile: this job runs as root): the limit, and whether to come down to it
static int SettingsNow(BOOL *comeDown) {
    CFStringRef d = CFSTR(MSBD_CHARGE_DOMAIN);
    CFPreferencesSynchronize(d, CFSTR("mobile"), kCFPreferencesAnyHost);
    int limit = kMSBDChargeLimitOff;
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_CHARGE_LIMIT_KEY), d, CFSTR("mobile"), kCFPreferencesAnyHost);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); limit = MSBDChargeLimitFromPref(n); }
    if (v) CFRelease(v);
#if DEBUG
    v = CFPreferencesCopyValue(CFSTR(MSBD_CHARGE_TEST_LIMIT_KEY), d, CFSTR("mobile"), kCFPreferencesAnyHost);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); if (MSBDChargeTestLimit(n)) limit = n; }
    if (v) CFRelease(v);
#endif
    if (comeDown) {
        v = CFPreferencesCopyValue(CFSTR(MSBD_CHARGE_COMEDOWN_KEY), d, CFSTR("mobile"), kCFPreferencesAnyHost);
        *comeDown = v && CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)v) : kMSBDChargeComeDownDefault;
        if (v) CFRelease(v);
    }
    return limit;
}
// Run on Power Adapter (common/ChargeLimit.h MSBDChargeAdapterLimit): on only when set (missing = off).
static BOOL RunOnAdapterNow(void) {
    CFStringRef d = CFSTR(MSBD_CHARGE_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_CHARGE_ADAPTER_KEY), d, CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)v);
    if (v) CFRelease(v);
    return on;
}
// The tweak meant to run (the root helper's TweakMeantToRun): SpringBoard's decision at its start when it has made one, else the switches as mobile.
static BOOL TweakMeantToRun(void) {
    uint64_t sb = MSBDGateReadState(MSBD_GATE_STATE);
    if (sb) return sb == 2;
    CFStringRef domain = CFSTR(MSBD_GATE_DOMAIN);
    CFPreferencesSynchronize(domain, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFStringRef key = MSBDVersionTested() ? CFSTR(MSBD_SAFE_KEY) : CFSTR(MSBD_GATE_KEY);
    CFPropertyListRef v = CFPreferencesCopyValue(key, domain, CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return MSBDVersionTested() ? !on : on;
}

// ---- our own state across runs
static NSMutableDictionary *gState;
static void SaveState(void) {
    mkdir(kStateDir, 0755);
    [gState writeToFile:@kStateFile atomically:YES];
}
static double StateDouble(NSString *k) { return [gState[k] respondsToSelector:@selector(doubleValue)] ? [gState[k] doubleValue] : 0; }

// ---- the decision, applied
static int gPrev = kMSBDChargeAllow, gRunning = 1;
static double gActionSince, gLastPulse, gCutSeenSince, gFullSince, gLastLoggedFull;
static BOOL gHoldPulsed, gCutPulsed;           // the self-checks' one raise-and-let-go per episode (a second would not help: something else is the cause)
// The hold and the cut checked against the battery (common/ChargeLimit.h MSBDChargeLeverCheck), [0] the hold, [1] the cut: when it went up, since
// when charge has gone in while it is up (0: none now), when it was raised again (0: not yet), the level when it went up. Given up for the plug-in:
static double gLeverUp[2], gLeverIn[2], gLeverAgain[2];
static int gLeverSoc[2];
static BOOL gHoldIgnored, gCutIgnored;
// This job's own build: the UUID the linker gave its executable (another build of msbdcharge, another UUID); "?" when it cannot be read.
static NSString *HelperBuild(void) {
    static NSString *build;
    if (build) return build;
    // (the job's own executable: _mh_execute_header. Image 0 of dyld's list is not it on the iPad -- c02 and c03, two builds, read the same
    //  build there, so a hold remembered as not taking stayed remembered for a new build, A12Z 10 Nov)
    extern const struct mach_header_64 _mh_execute_header;
    const struct mach_header_64 *h = &_mh_execute_header;
    const uint8_t *p = h && h->magic == MH_MAGIC_64 ? (const uint8_t *)(h + 1) : NULL;
    for (uint32_t i = 0; p && i < h->ncmds && !build; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            const uint8_t *u = ((const struct uuid_command *)lc)->uuid;
            NSMutableString *s = [NSMutableString string];
            for (int j = 0; j < 16; j++) [s appendFormat:@"%02x", u[j]];
            build = s;
        }
        p += lc->cmdsize;
    }
    return build ?: (build = @"?");
}
// What a hold that did not take is remembered for (common/ChargeLimit.h MSBDChargeHoldKnownIgnored): this build of the job (a later one may hold
// where this one could not: another lever for 18.5), the iPadOS build, the adapter (its kind and name: USB-C PD chargers share both, so "another
// adapter" here is a brick against a PD charger, not one PD charger against another).
static NSString *HoldKey(NSDictionary *b) {
    char build[32] = ""; size_t n = sizeof build - 1;
    if (sysctlbyname("kern.osversion", build, &n, NULL, 0) != 0) build[0] = 0;
    NSDictionary *ad = Dict(b[@"AdapterDetails"]);
    // (and the hold this iPad uses: one remembered as not taking with powerd's ChargeInhibit never stands for iPadOS's own charge limit)
    return [NSString stringWithFormat:@"%@%@|%s|%llx|%@", HelperBuild(), gSoc ? @"|soc" : @"", build, (unsigned long long)AdapterNow(b).familyCode,
            [ad[@"Description"] isKindOfClass:[NSString class]] ? ad[@"Description"] : @""];
}
static int gAdapterLevel = -1;                 // Run on Power Adapter: the level this plug-in holds (where the battery was when the cable went in or
                                               // the option was switched on; -1: not on, or not on power)
static MSBDChargeAdapter gCutAdapter;          // the adapter when our cut went up
static double gCutStarted, gCutEndedOut;       // when our last cut went up; when one ended because the cable read as out
static BOOL gCutMisread;                       // a cut ended as "cable out" but the cable read in right after: no new cut until it really comes out
static uint64_t gPublished = UINT64_MAX;
static dispatch_source_t gTimer;
static int gTimerFast = -1;
static void SetTimer(int fast) {   // every minute on power with a limit on, else every 15 minutes (the power-source notification brings the rest)
    if (!gTimer || fast == gTimerFast) return;
    gTimerFast = fast;
    uint64_t every = (fast ? 60 : 900) * NSEC_PER_SEC;
    dispatch_source_set_timer(gTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)every), every, every / 6);
}
static int gStateToken;
static NSString *const kActionNames[] = { @"charging allowed", @"on hold", @"coming down" };
static double gLeftoverSince;   // a hold or cut of an earlier job first seen with powerd (0: none now)
static double gLeftoverInWaySince;   // ... first seen in the way (MSBDChargeLeftoverInTheWay; 0: not in the way now)
static const char *gLeftoverWhy;     // why it was last not cleared (said once per reason)
// powerd started over (by the job for a leftover, or by the Sleep Guard): it knows none of the job's assertions, and the battery keeps the hold or
// cut they set, so a death of the job now would leave it there with nobody to let go of it. Each of ours raised anew at once (the new one first:
// a cut or hold never blinks off), and the self-checks may raise and let go again.
static void PowerdStartedOver(void) {
    // (iPadOS's charge limit: powerd archives its policies per boot session, so ours may still be there. Once the new powerd answers, set again on
    //  its own token; a new policy only if powerd does not take that one, the old token kept until it is removed: SocHoldOn, SocRemoveLeftovers)
    if (gSocToken) { SocWaitPowerd(); SocHoldOn(gSocWant, YES); }
    RaiseAgainAfter(&gHold, @"ChargeInhibit", @"MacStatusBar&Dock Charge Limit (on hold)");
    RaiseAgainAfter(&gDown, @"DisableInflow", @"MacStatusBar&Dock Charge Limit (coming down to the limit)");
    Lower(&gAwakeNext);
    RaiseAgainAfter(&gAwake, @"PreventUserIdleSystemSleep", AwakeName(gAwakeSlot)); gAwakeSince = [NSDate date].timeIntervalSince1970;
    gHoldPulsed = gCutPulsed = NO; gLastPulse = 0; gLastRefresh = gAwakeSince; gNoAnswer = 0;
}

static void Publish(uint64_t w) {
    if (w == gPublished) return;
    gPublished = w;
    if (!gStateToken && notify_register_check(MSBD_CHARGE_STATE, &gStateToken) != NOTIFY_STATUS_OK) { gStateToken = 0; return; }
    notify_set_state(gStateToken, w);
    notify_post(MSBD_CHARGE_STATE);
}

// ---- told to stop (msbdcharge --stop: the package's prerm, right before its launchctl unload)
// Dopamine's launchctl unload ends the job without a SIGTERM it sees, so whatever it still held was left to powerd to let go at its death -- and
// powerd does not always: the M1 kept three "Charge Limit (on hold)" holds after the jobs that raised them were gone (5-7 Nov), listed under
// dead pids with other programs' names (dasd, backboardd: pids it still had a record of from a process before ours, whose end it had already
// seen), and with the job removed charging stayed off until a reboot (regression-1.8.2-m1.md F3). So the prerm asks first: the job lets go of
// its hold (the PMU key too), its cut (SpringBoard told, as always) and its stay-awake itself, publishes "no job" -- what --stop waits for --
// and raises nothing until it is stopped (common/ChargeLimit.h MSBDChargeStopping).
static double gStopAsked;
static void LetGoForStop(BOOL first) {
    double now = [NSDate date].timeIntervalSince1970;
    if (first) gStopAsked = now;
    if (gPMU) SetPredictiveInhibit(NO);
    SocHoldOff();
    gPCIOn = NO; Lower(&gHold); CutOff(now); StayAwakeOff();
    gPrev = kMSBDChargeAllow;
    Publish(0);
    if (first) Log(@"letting go of everything: the package stops the job (msbdcharge --stop)");
}

static void Evaluate(NSString *why) { @autoreleasepool {   // (run-loop callbacks have no pool of their own, and the job runs for weeks)
    NSDictionary *b = BatteryProps();
    double now = [NSDate date].timeIntervalSince1970;
    if (MSBDChargeStopping(gStopAsked, now)) { LetGoForStop(NO); return; }   // (about to be stopped: nothing raised again)
    if (gStopAsked > 0) { gStopAsked = 0; Log(@"still running 2 minutes after --stop (the package step failed?): back at work"); }
    if (!b) { HoldOff(); CutOff(now); StayAwakeOff(); Publish(0); return; }
    int soc = Int(b, @"CurrentCapacity"), isCharging = Int(b, @"IsCharging") == 1, full = Int(b, @"FullyCharged") == 1, amp = Int(b, @"Amperage");
    int raw = Int(b, @"AppleRawExternalConnected") == 1;
    // On the cable: the raw reading -- except while our cut is up, and for 30 s after we let it go (the SMC iPads read the cable as out until
    // they settle, ~10 s on the A12Z): then in while the adapter is the one seen when the cut went up (common/ChargeLimit.h).
    BOOL ourCut = (gDown && gPrev == kMSBDChargeDown) || (gOwnCutEnded > 0 && now - gOwnCutEnded < 30);
    MSBDChargeAdapter adapter = AdapterNow(b);
    int plugged = MSBDChargePlugged(raw, ourCut, gCutAdapter, adapter);
    // Under iPadOS's charge limit the A12Z read the cable as out for a moment and in again (18.5, 10 Nov, ~90 s into a hold): taken as a new
    // plug-in, Run on Power Adapter's level was taken again a percent up. While our policy is up, the cable counts as out only once it has read
    // out for 15 s (looked at again then); the policy up for those seconds after a real unplug changes nothing (nothing charges off the cable).
    static double socOutSince;
    if (gSoc && gSocToken && !plugged && !ourCut) {
        if (!socOutSince) {
            socOutSince = now;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(16 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Evaluate(@"cable read as out"); });
        }
        if (now - socOutSince < 15) plugged = 1;
    } else socOutSince = 0;
    if (ourCut && !plugged) {
        gCutEndedOut = now;
        Log(@"the cable came out during the cut (adapter %lld W, kind %llx -> %lld W, kind %llx)", gCutAdapter.watts, (unsigned long long)gCutAdapter.familyCode,
            adapter.watts, (unsigned long long)adapter.familyCode);
    }
    if (!ourCut && raw && gCutEndedOut > 0) {
        if (now - gCutEndedOut < 180) { gCutMisread = YES; Log(@"the cable read as out during the cut but is in: no new cut until it comes out"); }
        gCutEndedOut = 0;
    }
    if (!raw && !gDown && gCutMisread && !CutShown(b)) gCutMisread = NO;   // (really out: no cut of any kind up)
    if (!plugged && (gHoldIgnored || gCutIgnored)) {   // (what did not take is tried again at the next plug-in: another adapter, another level)
        gHoldIgnored = gCutIgnored = NO; Log(@"cable out: the hold and the cut will be tried again at the next plug-in");
    }
    BOOL comeDown = NO;
    int limit = SettingsNow(&comeDown);
    BOOL limitOn = MSBDChargeLimitOn(limit), runOnAdapterSet = RunOnAdapterNow();
    // A hold given up (for this plug-in, and remembered: MSBDChargeHoldKnownIgnored) is tried again when a charge setting changes -- the Charge
    // Limit, coming down, Run on Power Adapter -- as compared with what the job last saw (kept in the state file across starts). Not at every note
    // of the tweak's settings: about 50 rows of Status Bar, Windows and Live Activities post the same one, and each would have taken the A12Z
    // down from 90 % again for hours only to fail at 80 %. (No record yet, a first start or an older build's state: kept as it is.)
    NSString *chargeSettings = [NSString stringWithFormat:@"%d|%d|%d", limit, comeDown, runOnAdapterSet];
    if (![gState[@"chargeSettings"] isEqual:chargeSettings]) {
        NSString *was = [gState[@"chargeSettings"] isKindOfClass:[NSString class]] ? gState[@"chargeSettings"] : nil;
        // A change made in Settings is planned again now, and may start a cut at once: the limit of one cut start per 30 minutes is against cuts
        // that come and go by themselves, not against the user's own change (17.5 load test, 10 Nov: Run on Power Adapter switched off at 98 %
        // with an 80 % limit stayed on hold, silently, until the job was restarted, because a cut had started 30 minutes before).
        if (was) { gCutStarted = 0; Log(@"a charge setting changed (%@ -> %@, as limit|coming down|run on power adapter): planned again now", was, chargeSettings); }
        if (was && (gHoldIgnored || gState[@"holdIgnored"])) {
            gHoldIgnored = NO; [gState removeObjectForKey:@"holdIgnored"]; Log(@"a charge setting changed: the hold will be tried again");
        }
        gState[@"chargeSettings"] = chargeSettings; SaveState();
    }
    NSDictionary *known = Dict(gState[@"holdIgnored"]);
    if (plugged && !gHoldIgnored && known && MSBDChargeHoldKnownIgnored([known[@"key"] isKindOfClass:[NSString class]] ? [known[@"key"] UTF8String] : "",
                                                                         [known[@"at"] respondsToSelector:@selector(doubleValue)] ? [known[@"at"] doubleValue] : 0, HoldKey(b).UTF8String, now)) {
        gHoldIgnored = YES;
        Log(@"the hold did not take with this adapter %.1f days ago: given up for this plug-in too (tried again after %d days or a change to a charge setting)",
            (now - [known[@"at"] doubleValue]) / 86400, MSBD_CHARGE_REMEMBER_DAYS);
    }
    // full on power: remembered (the monthly full charge counts from it), and how long it has been full (the full charge's hour)
    if (plugged && soc >= 100 && full) {
        if (!gFullSince) gFullSince = now;
        if (now - gLastLoggedFull > 3600) { gState[@"lastFull"] = @(now); SaveState(); gLastLoggedFull = now; }
    } else gFullSince = 0;
    if (!plugged && [gState[@"fullNow"] boolValue]) { [gState removeObjectForKey:@"fullNow"]; SaveState(); Log(@"Charge to Full Now ended (cable out)"); }
    BOOL calibrating = [gState[@"calibrating"] boolValue];
    if (calibrating && !comeDown) { calibrating = NO; [gState removeObjectForKey:@"calibrating"]; SaveState(); Log(@"monthly full charge: dropped (coming down is off)"); }
    if (!calibrating && plugged && MSBDChargeCalibrationDue(now, StateDouble(@"lastFull"), StateDouble(@"firstStart"), limitOn && comeDown)) {
        calibrating = YES; gState[@"calibrating"] = @YES; SaveState();
        Log(@"monthly full charge: due (last full %.0f days ago)", (now - MAX(StateDouble(@"lastFull"), StateDouble(@"firstStart"))) / 86400);
    }
    if (calibrating && MSBDChargeCalibrationDone(gFullSince, now)) {
        calibrating = NO; [gState removeObjectForKey:@"calibrating"]; gState[@"lastFull"] = @(now); SaveState(); Log(@"monthly full charge: done (an hour at 100 %%)");
    }
    // Run on Power Adapter: the level this plug-in holds, the limit the decision works to (never above the Charge Limit: above it, the limit's own
    // coming down; else no cut -- the level only goes down by a load the adapter cannot carry). The monthly full charge (only with a Charge Limit
    // and coming down on) leaves the battery full, so the level held becomes full: capped at the limit, it comes back down to the limit after it,
    // as Settings says ("then back to 80%", "up to 80%") -- not held at 100 % for the rest of the plug-in.
    BOOL onAdapter = plugged && runOnAdapterSet;
    if (!onAdapter) gAdapterLevel = -1;
    else if (gAdapterLevel < 0) { gAdapterLevel = soc; Log(@"Run on Power Adapter: the battery held at %d %% while plugged in", MSBDChargeAdapterLimit(limit, 1, soc)); }
    if (onAdapter && calibrating && limitOn && gAdapterLevel < 100) {
        gAdapterLevel = 100; Log(@"Run on Power Adapter: the monthly full charge, then back down to the Charge Limit (%d %%)", limit);
    }
    int holdAt = MSBDChargeAdapterLimit(limit, onAdapter, gAdapterLevel);
    BOOL holdOn = MSBDChargeLimitOn(holdAt), comeDownTo = comeDown && holdAt == limit;
    MSBDChargeIn in = { holdAt, soc, plugged, [gState[@"fullNow"] boolValue] || calibrating, gPrev, gRunning && MSBDIsIPad() && TweakMeantToRun(),
                        MSBDChargeCutAllowed(now, gCutStarted, gCutMisread), comeDownTo, gHoldIgnored, gCutIgnored,
                        gPrev == kMSBDChargeHold && (gLeverIn[0] > 0 || (gLeverUp[0] > 0 && now - gLeverUp[0] < 120)) };
    MSBDChargeOut o = MSBDChargeDecide(in);
    if (o.action != gPrev) {
        Log(@"%@ (%@): battery %d %%, cable %d%@, limit %@%@%@, %@", kActionNames[o.action], why ?: @"check", soc, plugged, raw == plugged ? @"" : @" (read as out: our cut)",
            limitOn ? [NSString stringWithFormat:@"%d %%", limit] : @"off", limitOn && !comeDown ? @" (no coming down)" : @"",
            onAdapter ? [NSString stringWithFormat:@", Run on Power Adapter at %d %%", holdAt] : @"",
            gPMU ? @"PMU charger: PredictiveChargingInhibit" : gSoc ? @"SMC charger: iPadOS's charge limit" : @"SMC charger: ChargeInhibit");
        gActionSince = now;
    }
    // iPadOS's charge limit holds at a level: the level held (the limit, Run on Power Adapter's), or where the battery is when that is lower
    // (the hold's band below the limit) -- set when the hold begins or its level changes, not after every reading under it
    if (gSoc && o.action == kMSBDChargeHold && (gPrev != kMSBDChargeHold || gSocWant < 0 || (gSocAt >= 0 && holdAt != gSocAt && soc >= holdAt)))
        gSocWant = soc >= holdAt ? holdAt : MAX(soc, 1);
    NSSet *held = gHold || gDown || gAwake || gAwakeNext ? PowerdHolds() : [NSSet set];
    if (held) gNoAnswer = 0;
    else if (++gNoAnswer >= 2 && now - gLastRefresh >= 600) {   // (powerd started again: see RaiseAgainAfter)
        gLastRefresh = now; gNoAnswer = 0;
        Log(@"powerd does not answer for our assertions (started again?): each raised anew");
        RaiseAgainAfter(&gHold, @"ChargeInhibit", @"MacStatusBar&Dock Charge Limit (on hold)");
        RaiseAgainAfter(&gDown, @"DisableInflow", @"MacStatusBar&Dock Charge Limit (coming down to the limit)");
        Lower(&gAwakeNext);
        RaiseAgainAfter(&gAwake, @"PreventUserIdleSystemSleep", AwakeName(gAwakeSlot)); gAwakeSince = now;
    }
    switch (o.action) {
        case kMSBDChargeHold: HoldOn(held); CutOff(now); break;   // (the hold first, then the cut let go: no moment of charging between)
        case kMSBDChargeDown:
            if (gDown && held && ![held containsObject:@"DisableInflow"]) { Log(@"powerd no longer holds our cut (restarted?): raised again"); Lower(&gDown); }
            if (!gDown) {
                if (gPrev != kMSBDChargeDown) {
                    gCutAdapter = adapter; gCutStarted = now;
                    Log(@"adapter when the cut goes up: %lld W, kind %llx, ID %lld", adapter.watts, (unsigned long long)adapter.familyCode, adapter.adapterID);
                }
                gDown = Raise(@"DisableInflow", @"MacStatusBar&Dock Charge Limit (coming down to the limit)");
            }
            HoldOff(); break;
        default: HoldOff(); CutOff(now); break;
    }
    if (o.keepAwake) StayAwake(held, now); else StayAwakeOff();
    // A hold or cut of ours that no job holds any more, cleared only while it visibly blocks what this job does with the cable in (common/
    // ChargeLimit.h MSBDChargeLeftoverInTheWay) and by the Sleep Guard's own rule (common/SleepGuard.h MSBDSGDecide): in the way for a minute, the
    // screen off, no live keep-awake assertion of another process (the restart drops those too), at most once in 30 minutes and 6 times a day (the
    // clears kept in the state file across starts). One that blocks nothing -- off the cable, or on a charger that ignores the hold -- stays.
    Leftovers lo = FindLeftovers();
    if (lo.hold || lo.cut) {
        if (!gLeftoverSince) { gLeftoverSince = now; Log(@"a hold or cut of an earlier job is still with powerd: %@", lo.what); }
    } else if (gLeftoverSince) { gLeftoverSince = 0; Log(@"no hold or cut of an earlier job with powerd any more"); }
    if (!MSBDChargeLeftoverInTheWay(lo.hold, lo.cut, o.action, raw, adapter.watts > 0 && adapter.familyCode != 0, Int(b, @"IsCharging") == 0 && amp <= 100,
                                    full, soc, CutShown(b))) { gLeftoverInWaySince = 0; gLeftoverWhy = NULL; }
    else {
        if (!gLeftoverInWaySince) gLeftoverInWaySince = now;
        NSMutableArray *clears = [NSMutableArray array];
        for (id c in [gState[@"leftoverClears"] isKindOfClass:[NSArray class]] ? gState[@"leftoverClears"] : @[])
            if ([c respondsToSelector:@selector(doubleValue)] && now - MIN([c doubleValue], now) <= 86400) [clears addObject:@(MIN([c doubleValue], now))];
        double last = clears.count ? [[clears valueForKeyPath:@"@max.doubleValue"] doubleValue] : 0, oldest = clears.count ? [[clears valueForKeyPath:@"@min.doubleValue"] doubleValue] : 0;
        NSString *liveWhat = nil;
        int live = LiveKeepAwake(&liveWhat);
        const char *why = "";
        if (MSBDSGDecide(gLeftoverInWaySince, now, ScreenOff(), live < 0 ? 1 : live, 1, last, (int)clears.count, oldest, &why, NULL) != kMSBDSGClear) {
            if (now - gLeftoverInWaySince >= 60 && (!gLeftoverWhy || strcmp(why, gLeftoverWhy))) {
                gLeftoverWhy = why;
                Log(@"a hold or cut of an earlier job keeps %@: not cleared yet (%s%@)", lo.hold ? @"charging off" : @"the adapter cut", why,
                    live > 0 ? [@": " stringByAppendingString:liveWhat] : live < 0 ? @": powerd did not answer" : @"");
            }
        } else {
            [clears addObject:@(now)]; gState[@"leftoverClears"] = clears; SaveState();   // (counted first: the limits hold even if the job starts over now)
            NSString *r = nil; RestartPowerd(&r);
            PowerdStartedOver();
            if (lo.hold && !gHold) Pulse(@"ChargeInhibit");   // (the new powerd writes "charging allowed" / "adapter connected" to the battery)
            if (lo.cut && !gDown) Pulse(@"DisableInflow");
            Leftovers after = FindLeftovers();
            Log(@"cleared what an earlier job left with powerd (%@): %@; left now: %@", lo.what, r, after.hold || after.cut ? after.what : @"nothing");
            gLeftoverSince = after.hold || after.cut ? now : 0;
            gLeftoverInWaySince = 0; gLeftoverWhy = NULL;
        }
    }
    // The hold and the cut checked against the battery: charge still going in, raised again once (old one first: powerd writes "inhibited" to the
    // battery anew; the cut's end is kept quiet as always), then given up for the plug-in -- and decided again at once without it. Charge going in:
    // an Amperage reading over 100 mA, or the battery saying it charges (IsCharging 1: the A12Z under its ignored hold). None: an Amperage reading of
    // at most 100 mA, IsCharging not 1. No Amperage reading and IsCharging not 1: unknown, never "it takes" (common/ChargeLimit.h MSBDChargeLeverCheck).
    BOOL ampRead = [b[@"Amperage"] respondsToSelector:@selector(intValue)];
    int chargeIn = (ampRead && amp > 100) || isCharging ? 1 : ampRead ? 0 : -1;
    NSString *inNow = ampRead ? [NSString stringWithFormat:@"%d mA in", amp] : isCharging ? @"charging (no current reading)" : @"no current reading";
    BOOL gaveUp = NO;
    for (int k = 0; k < 2; k++) {
        BOOL up = o.action == (k ? kMSBDChargeDown : kMSBDChargeHold);
        if (!up) { gLeverUp[k] = gLeverIn[k] = gLeverAgain[k] = 0; continue; }
        if (!gLeverUp[k]) { gLeverUp[k] = now; gLeverSoc[k] = soc; }
        if (!chargeIn) gLeverIn[k] = 0; else if (!gLeverIn[k]) gLeverIn[k] = now;
        if (!k && chargeIn == 0 && now - gLeverUp[0] >= 120 && gState[@"holdIgnored"] && [Dict(gState[@"holdIgnored"])[@"key"] isEqual:HoldKey(b)]) {
            [gState removeObjectForKey:@"holdIgnored"]; SaveState(); Log(@"the hold takes with this adapter now: no longer remembered as not taking");
        }
        int v = MSBDChargeLeverCheck(chargeIn, chargeIn ? now - MAX(gLeverIn[k], gLeverUp[k]) : 0, gLeverAgain[k] > 0, gLeverAgain[k] > 0 ? now - gLeverAgain[k] : 0,
                                     soc - gLeverSoc[k]);
        if (v == kMSBDLeverRaiseAgain) {
            gLeverAgain[k] = now;
            Log(@"self-check: %@ %@: raised again", inNow, k ? @"during the cut" : @"while on hold");
            if (k) { CutOff(now); gDown = Raise(@"DisableInflow", @"MacStatusBar&Dock Charge Limit (coming down to the limit)"); }
            else { if (gPMU) { SetPredictiveInhibit(NO); gPCIOn = NO; } else Lower(&gHold); HoldOn(nil); }
        } else if (v == kMSBDLeverIgnored) {
            if (k) gCutIgnored = YES;
            else { gHoldIgnored = YES; if (chargeIn > 0) { gState[@"holdIgnored"] = @{ @"key": HoldKey(b), @"at": @(now) }; SaveState(); } }   // (unknown: this plug-in only)
            MSBDChargeAdapter ad = AdapterNow(b);
            NSDictionary *adDict = Dict(b[@"AdapterDetails"]);
            Log(@"the %@ %@: %@, battery %d %% (%d %% when it went up %.0f s ago), adapter %lld W, kind %llx, \"%@\": %@ until the cable comes out",
                k ? @"adapter cut" : @"hold", chargeIn > 0 ? @"does not take here" : @"cannot be checked here", inNow, soc, gLeverSoc[k], now - gLeverUp[k],
                ad.watts, (unsigned long long)ad.familyCode, [adDict[@"Description"] isKindOfClass:[NSString class]] ? adDict[@"Description"] : @"",
                k ? @"held where it is instead" : @"iPadOS charges as always");
            gLeverUp[k] = gLeverIn[k] = gLeverAgain[k] = 0;
            gaveUp = YES;
        }
    }
    // self-checks. Allowed but not charging well under full (a hold left in the driver): raised and let go, once while it lasts.
    if (MSBDChargeNeedsPulse(o.action, plugged, isCharging, full, soc, now - gActionSince, now - gLastPulse)) {
        if (!gHoldPulsed) {
            gHoldPulsed = YES; gLastPulse = now;
            if (gPMU) SetPredictiveInhibit(NO);
            Pulse(@"ChargeInhibit");
            Log(@"self-check: not charging at %d %% though allowed: hold raised and let go", soc);
        }
    } else if (o.action != kMSBDChargeAllow || isCharging || !plugged) gHoldPulsed = NO;
    // A cut showing that is not ours (left by a powerd that restarted while ours was up): let go once it has shown for a minute (ours takes some
    // seconds to clear after we let it go), once while it lasts.
    if (!gDown && now - gOwnCutEnded >= 60 && CutShown(b)) {
        if (!gCutSeenSince) gCutSeenSince = now;
        if (now - gCutSeenSince >= 60 && !gCutPulsed) {
            gCutPulsed = YES; Pulse(@"DisableInflow"); Log(@"self-check: an adapter cut nobody holds was showing: raised and let go");
        }
    } else { gCutSeenSince = 0; gCutPulsed = NO; }
    SocRemoveLeftovers();   // (a kept policy that is not the hold now: removed, looked at every minute until it is)
    gPrev = o.action;
    SetTimer((plugged && holdOn) || gCutSeenSince > 0 || gLeftoverInWaySince > 0 || gSocLeft > 0);
    Publish(MSBDChargeStateWord(o.state == kMSBDChargeStateToFull && calibrating && ![gState[@"fullNow"] boolValue] ? kMSBDChargeStateMonthlyFull : o.state, holdAt, plugged));
    if (gaveUp) Evaluate(@"given up");   // (without what does not take, at once)
} }

static void PowerSourceChanged(void *ctx) { Evaluate(@"power source"); }
// ---- nothing set: the job ends (1.8.6, the public line: no root job runs for someone who never sets a Charge Limit or Run on Power Adapter).
// launchd restarts it only after a crash (KeepAlive SuccessfulExit false); the root helper starts it when one of the two is set (sshtoggled
// ChargeJobKick), and every start lets go of anything an earlier run left first (ResetCharging, main).
#ifndef MSBD_CHARGE_IDLE_EXIT
#define MSBD_CHARGE_IDLE_EXIT() exit(0)   // (tools/chargejob-sim.h, which runs this job inside a test process, ends only the simulated job)
#endif
// One job at a time (A12Z load test, 10 Nov: an unknown word on the command line ran a second job beside launchd's for ~70 s, and it moved the
// adapter cut): the job takes an exclusive lock on a file in its state folder before it touches any lever, and keeps it for its life (the lock
// ends with the process, a crash too). A second job finds it taken and ends without touching anything; --stop, --reset, --status and --poke talk
// to the running one (notes) or read, as before, and take no lock; --reset takes it while it runs, and leaves the levers of a job that holds it to
// that job (ResetCharging).
#ifndef MSBD_CHARGE_LOCK_SIM
static BOOL JobLockTake(void) {
    static int fd = -1;
    if (fd >= 0) return YES;
    mkdir(kStateDir, 0755);
    int f = open(kStateDir "/chargelimit.lock", O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (f < 0) return YES;   // (no lock file can be made: run as before rather than leave the limit unheld)
    if (flock(f, LOCK_EX | LOCK_NB) != 0) { close(f); return NO; }
    fd = f;   // (kept open: the lock lasts as long as this job)
    return YES;
}
static void JobLockRelease(void) {}   // (the process ends right after: its lock with it)
#else
static BOOL JobLockTake(void);
static void JobLockRelease(void);
#endif
static BOOL ChargeWanted(void) { return MSBDIsIPad() && (MSBDChargeLimitOn(SettingsNow(NULL)) || RunOnAdapterNow()); }
static void EndIdle(NSString *why) {
    // only once nothing of ours is raised (a cut ending is given its 30 s to settle, as Evaluate does) and no kept policy of iPadOS's charge limit
    // is left to remove (it would keep charging stopped at its level with the job gone): else the next tick looks again
    double now = [NSDate date].timeIntervalSince1970;
    SocRemoveLeftovers();
    if (gHold || gDown || gAwake || gAwakeNext || gPCIOn || gSocToken || gSocLeft || (gOwnCutEnded > 0 && now - gOwnCutEnded < 30)) return;
    if (gPMU) SetPredictiveInhibit(NO);
    if (gStateToken) { notify_set_state(gStateToken, 0); notify_post(MSBD_CHARGE_STATE); }
    if (gState) { [gState removeObjectForKey:@"starts"]; SaveState(); }   // (a clean end is no start loop)
    Log(@"no Charge Limit or Run on Power Adapter set (%@): the job ends", why);
    MSBD_CHARGE_IDLE_EXIT();
}
static void Terminate(int sig) {
    // launchctl unload (the prerm) or a shutdown: nothing of ours left behind (the assertions would end with us anyway; the PMU key would not)
    if (gPMU) SetPredictiveInhibit(NO);
    SocHoldOff();
    if (gDown) notify_post(MSBD_CHARGE_CUT_ENDING);
    Lower(&gHold); Lower(&gDown); StayAwakeOff();
    if (gStateToken) { notify_set_state(gStateToken, 0); notify_post(MSBD_CHARGE_STATE); }
    Log(@"stopped (signal %d)", sig);
    exit(0);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc > 1 && !strcmp(argv[1], "--reset")) {
            // (the prerm, after the job was unloaded: its hold and cut have already ended with it; the inhibit key does not end by itself. Nor
            // does the state it published: Dopamine's launchctl unload stops the job without a SIGTERM it sees, and the name keeps its last value
            // while SpringBoard and Settings watch it -- "on hold" would stay on the battery and in Settings (M1, 2 Nov): set to "no job".)
            // (run by hand while the job runs: the job lock is taken by it. Its own levers are left to it -- ResetCharging -- and its published state
            // stays: "no job" would stay in Settings and on the battery while it holds, as it publishes only a change)
            BOOL jobRuns = !JobLockTake();
            ResetCharging(@"--reset", YES, jobRuns);
            int socLeft = 0;
            NSUInteger kept = SocKeptCount([NSDictionary dictionaryWithContentsOfFile:@kStateFile]);
            if (SocQueryOurs(&socLeft) && socLeft) {
                if (jobRuns) printf("iPadOS's charge limit: %d policies of ours with powerd, left to the running job\n", socLeft);
                else printf("iPadOS's charge limit: %d policies of ours still with powerd (%lu kept to be removed by the job's next start; one with no token kept ends at a restart of the iPad)\n",
                            socLeft, (unsigned long)kept);
            }
            int t = 0;
            if (!jobRuns && notify_register_check(MSBD_CHARGE_STATE, &t) == NOTIFY_STATUS_OK) { notify_set_state(t, 0); notify_post(MSBD_CHARGE_STATE); notify_cancel(t); }
            printf(jobRuns ? "charging reset (a job is running: its own hold left to it)\n" : "charging reset\n"); return 0;
        }
        if (argc > 1 && !strcmp(argv[1], "--poke")) { notify_post(MSBD_CHARGE_PREFS_CHANGED); return 0; }
        if (argc > 1 && !strcmp(argv[1], "--stop")) {
            // (the prerm, right before it stops the job: see LetGoForStop. A job that is not running has published nothing, or "no job" since the
            // last --reset: no wait then. One that does not answer in 3 s: the prerm goes on, and its --reset looks at what is left.)
            int t = 0; uint64_t w = 0;
            BOOL registered = notify_register_check(MSBD_CHARGE_STATE, &t) == NOTIFY_STATUS_OK;
            notify_post(MSBD_CHARGE_STOP);
            for (int i = 0; registered && i < 30; i++) { notify_get_state(t, &w); if (!((w >> 17) & 1)) break; usleep(100000); }
            if (registered) notify_cancel(t);
            printf("%s\n", (w >> 17) & 1 ? "the job did not say it let go within 3 s" : "the job holds nothing");
            return 0;
        }
        if (argc > 1 && !strcmp(argv[1], "--status")) {   // (one line each: the battery, the job's published state, powerd's view of ours)
            NSDictionary *b = BatteryProps(), *cd = Dict(b[@"ChargerData"]);
            MSBDChargeAdapter a = AdapterNow(b);
            BOOL comeDown = NO; int limit = SettingsNow(&comeDown);
            printf("battery %s (%s): %d %%, cable %d, connected %d, charging %d, full %d, %d mA, adapter %lld W, cut showing %d, reasons 0x%llx / 0x%llx; limit %d, coming down %d, run on power adapter %d; tweak meant to run %d\n",
                   gBattery ? "found" : "not found", gPMU ? "PMU" : "SMC", Int(b, @"CurrentCapacity"), Int(b, @"AppleRawExternalConnected"), Int(b, @"ExternalConnected"),
                   Int(b, @"IsCharging"), Int(b, @"FullyCharged"), Int(b, @"Amperage"), a.watts, b ? CutShown(b) : -1,
                   [cd[@"NotChargingReason"] respondsToSelector:@selector(unsignedLongLongValue)] ? [cd[@"NotChargingReason"] unsignedLongLongValue] : 0ULL,
                   (unsigned long long)(cd[@"ChargerInhibitReason"] ? LL(cd[@"ChargerInhibitReason"]) : 0), limit, comeDown, RunOnAdapterNow(), TweakMeantToRun());
            int t = 0; uint64_t w = 0;
            if (notify_register_check(MSBD_CHARGE_STATE, &t) == NOTIFY_STATUS_OK) { notify_get_state(t, &w); notify_cancel(t); }
            printf("published state %d, limit %d, on power %d, job running %d\n", MSBDChargeWordState(w), MSBDChargeWordLimit(w), MSBDChargeWordPlugged(w), (int)((w >> 17) & 1));
            CFDictionaryRef all = NULL; NSMutableArray *ours = [NSMutableArray array];
            if (IOPMCopyAssertionsByProcess(&all) == kIOReturnSuccess && all) {
                NSDictionary *byPID = (__bridge_transfer NSDictionary *)all;
                for (id pid in byPID) for (NSDictionary *as in [byPID[pid] isKindOfClass:[NSArray class]] ? byPID[pid] : @[])
                    if ([as isKindOfClass:[NSDictionary class]] && [as[@"AssertName"] isKindOfClass:[NSString class]] && [as[@"AssertName"] hasPrefix:@"MacStatusBar&Dock Charge Limit"])
                        [ours addObject:[NSString stringWithFormat:@"%@ (pid %@)", as[@"AssertType"], pid]];
                printf("powerd holds for the Charge Limit: %s\n", ours.count ? [ours componentsJoinedByString:@", "].UTF8String : "nothing");
            } else printf("powerd holds for the Charge Limit: (no answer)\n");
            int socOurs = 0;
            BOOL socHere = SocQueryOurs(&socOurs);
            printf("iPadOS's charge limit: %s", socHere ? "offered here" : "not offered here");
            if (socHere) printf(", policies of ours %d", socOurs);
            printf("\n");
            return 0;
        }
        if (argc > 1) {   // (any other word: how to use it, and nothing touched -- an unknown one used to start a second job, A12Z 10 Nov)
            BOOL help = !strcmp(argv[1], "--help") || !strcmp(argv[1], "-h");
            fprintf(help ? stdout : stderr, "usage: msbdcharge [--status | --stop | --reset | --poke]\n"
                    "  with no argument: the Charge Limit's job, as launchd runs it (one at a time)\n");
            return help ? 0 : 2;
        }
        if (!JobLockTake()) {   // (another job holds the levers: this one touches nothing. Not 0: launchd's own job, if it was refused, is tried again)
            Log(@"another Charge Limit job is running: this one ends without touching anything");
            fprintf(stderr, "msbdcharge: another Charge Limit job is running\n");
            return 3;
        }
        // First of all, before anything that could fail: what an earlier run can have left (the PMU key, a hold in the driver) is let go.
        ResetCharging(nil, NO, NO);
        // (nothing set: nothing to hold. "No job" published, as --reset does, and no start counted. Unless a kept policy of iPadOS's charge limit
        //  could not be removed yet: the job runs until it is, then ends -- EndIdle)
        if (!ChargeWanted() && !SocKeptCount([NSDictionary dictionaryWithContentsOfFile:@kStateFile])) {
            JobLockRelease();
            int t = 0;
            if (notify_register_check(MSBD_CHARGE_STATE, &t) == NOTIFY_STATUS_OK) { notify_set_state(t, 0); notify_post(MSBD_CHARGE_STATE); notify_cancel(t); }
            return 0;
        }
        // SIGTERM (launchctl unload: the prerm), SIGINT, SIGHUP: handled on the main queue, not inside the signal handler (IOKit and Foundation)
        static dispatch_source_t signals[3];
        const int sigs[3] = { SIGTERM, SIGINT, SIGHUP };
        for (int i = 0; i < 3; i++) {
            int sig = sigs[i];
            signal(sig, SIG_IGN);
            signals[i] = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, (uintptr_t)sig, 0, dispatch_get_main_queue());
            dispatch_source_set_event_handler(signals[i], ^{ Terminate(sig); });
            dispatch_resume(signals[i]);
        }
        gState = [NSMutableDictionary dictionaryWithContentsOfFile:@kStateFile] ?: [NSMutableDictionary dictionary];
        double now = [NSDate date].timeIntervalSince1970;
        if (!StateDouble(@"firstStart")) gState[@"firstStart"] = @(now);
        // a start loop (5 starts in 10 minutes): idle for this run, holding nothing
        NSMutableArray *starts = [NSMutableArray array];
        for (id s in [gState[@"starts"] isKindOfClass:[NSArray class]] ? gState[@"starts"] : @[]) if ([s respondsToSelector:@selector(doubleValue)] && now - [s doubleValue] <= 600) [starts addObject:s];
        [starts addObject:@(now)];
        gState[@"starts"] = starts;
        SaveState();
        double times[8] = {0}; int n = 0;
        for (id s in starts) if (n < 8) times[n++] = [s doubleValue];
        if (MSBDChargeStartLoop(times, n, now)) { gRunning = 0; Log(@"started %d times in 10 minutes: holding nothing in this run", n); }
        // the hold on this iPad: iPadOS's own charge limit where powerd offers it (an SMC iPad whose SMC has CHLS: the A12Z on 18), else as before
        gSoc = 0; gSocWant = -1;
        if (gBattery && !gPMU && SocQueryOurs(NULL)) gSoc = 1;
        Log(@"started (%@ charger, %@)%@", !gBattery ? @"no" : gPMU ? @"PMU" : @"SMC", gRunning ? @"running" : @"idle",
            gPMU || !gBattery ? @"" : gSoc ? @": the hold is iPadOS's own charge limit" : @": the hold is powerd's ChargeInhibit");
        if (!MSBDIsIPad()) Log(@"not an iPad: nothing to do");
        CFRunLoopSourceRef src = IOPSNotificationCreateRunLoopSource(PowerSourceChanged, NULL);
        if (src) { CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopDefaultMode); CFRelease(src); }
        int t1 = 0, t2 = 0, t3 = 0, t4 = 0;
        // (the tweak-wide settings note: posted by the charge rows and by every other row of the tweak. Evaluate looks at the charge settings'
        // values: a hold given up is tried again only when one of them changed)
        notify_register_dispatch(MSBD_CHARGE_PREFS_CHANGED, &t1, dispatch_get_main_queue(), ^(int t) { Evaluate(@"settings"); if (!ChargeWanted()) EndIdle(@"settings"); });
        notify_register_dispatch(MSBD_CHARGE_FULL_NOW, &t2, dispatch_get_main_queue(), ^(int t) {
            gState[@"fullNow"] = @YES; SaveState(); Log(@"Charge to Full Now"); Evaluate(@"Charge to Full Now");
        });
        notify_register_dispatch(MSBD_CHARGE_FULL_CANCEL, &t3, dispatch_get_main_queue(), ^(int t) {
            [gState removeObjectForKey:@"fullNow"]; [gState removeObjectForKey:@"calibrating"]; SaveState(); Log(@"back to the limit"); Evaluate(@"back to the limit");
        });
        notify_register_dispatch(MSBD_GATE_STATE, &t4, dispatch_get_main_queue(), ^(int t) { Evaluate(@"tweak on/off"); });
        int t5 = 0, t6 = 0;
        notify_register_dispatch(MSBD_CHARGE_STOP, &t5, dispatch_get_main_queue(), ^(int t) { LetGoForStop(YES); });
        notify_register_dispatch(MSBD_SG_POWERD, &t6, dispatch_get_main_queue(), ^(int t) {
            if (MSBDChargeStopping(gStopAsked, [NSDate date].timeIntervalSince1970)) return;
            PowerdStartedOver(); Log(@"powerd was started over (the Sleep Guard, or msbdcharge --reset): ours raised anew"); Evaluate(@"powerd started over");
        });
        gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(gTimer, ^{ Evaluate(nil); if (!ChargeWanted()) EndIdle(@"tick"); });
        SetTimer(1);
        dispatch_resume(gTimer);
        Evaluate(@"start");
        CFRunLoopRun();
    }
    return 0;
}
