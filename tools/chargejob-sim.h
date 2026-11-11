// chargejob-sim.h -- the Charge Limit's job (chargehelper/main.m) run on the Mac as it is, on a simulated iPad. Included by the job's behaviour
// tests (tools/test-charge*.m); each test runs one scenario per process (its globals are the job's). What the job calls on the iPad is played
// here: powerd's assertions (by pid, with its record of each process: a record whose exit is not watched keeps a dead process's assertions,
// as the M1 kept three "Charge Limit (on hold)" holds, 5-7 Nov; nobody but the owner process can let go of one; a restart drops them all
// and the scheduled wakes), the battery service (the level, the cable, the adapter, the hold and the cut as each chip obeys them, read as the
// four iPads showed them: plans/battery-charging.md), notify, the settings as mobile, the clock, getpid, and launchctl for powerd.
// Build: clang -fobjc-arc -DDEBUG=0 -DkStateDir=... -DkLogFile=... -framework Foundation (no IOKit: its calls are these).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <spawn.h>
#include <sys/wait.h>

static void SimJobIdleEnd(void);   // (the job's clean end when nothing is set: below)
#define MSBD_CHARGE_IDLE_EXIT() do { SimJobIdleEnd(); return; } while (0)
#define MSBD_CHARGE_SOC_SIM   // (powerd's SOC-limit service is played below)
#define MSBD_CHARGE_LOCK_SIM  // (the job's one-at-a-time lock is played below: every simulated process is this one real process)
#define main msbdcharge_main
#include "../chargehelper/main.m"
#undef main

// ---- checks
static int gSimFails, gSimChecks;
static void Expect(const char *what, int ok) { gSimChecks++; if (!ok) gSimFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
static int SimDone(void) { printf("%d checks, %d failed\n", gSimChecks, gSimFails); return gSimFails ? 1 : 0; }

// ---- the clock (the job reads [NSDate date]; sleep / usleep move it)
static double gSimNow = 1800000000;
static id SimDate(id cls, SEL _cmd) { return [[NSDate alloc] initWithTimeIntervalSince1970:gSimNow]; }
__attribute__((constructor)) static void SimClockInit(void) {
    method_setImplementation(class_getClassMethod([NSDate class], @selector(date)), (IMP)SimDate);
}

// ---- processes: the one running now (getpid), and which are alive
static int gSimPid = 100;
pid_t getpid(void) { return gSimPid; }
#define kSimMaxProcs 64
static struct { int pid; char name[40]; int alive; } gSimProcs[kSimMaxProcs];
static int gSimProcN;
static void SimProcStart(int pid, const char *name) {
    for (int i = 0; i < gSimProcN; i++) if (gSimProcs[i].pid == pid) { gSimProcs[i].alive = 1; snprintf(gSimProcs[i].name, 40, "%s", name); return; }
    if (gSimProcN < kSimMaxProcs) { gSimProcs[gSimProcN].pid = pid; snprintf(gSimProcs[gSimProcN].name, 40, "%s", name); gSimProcs[gSimProcN++].alive = 1; }
}
static int SimProcAlive(int pid) { for (int i = 0; i < gSimProcN; i++) if (gSimProcs[i].pid == pid) return gSimProcs[i].alive; return 0; }
static const char *SimProcName(int pid) { for (int i = 0; i < gSimProcN; i++) if (gSimProcs[i].pid == pid) return gSimProcs[i].name; return ""; }
// launchctl as spawned (pid 4242): running until gSimSpawnDoneAt (it hangs gSimLaunchctlHangs seconds when set), or killed
static double gSimSpawnDoneAt; static int gSimSpawnKilled, gSimLaunchctlHangs;
int kill(pid_t pid, int sig) {
    if (pid == 4242 && gSimNow < gSimSpawnDoneAt) { if (sig == SIGKILL) { gSimSpawnKilled = 1; gSimSpawnDoneAt = gSimNow; } return 0; }
    if (SimProcAlive(pid)) return 0;
    errno = ESRCH; return -1;
}
int proc_name(int pid, void *buffer, uint32_t buffersize) {   // (libproc: the name of the process at pid now)
    if (!SimProcAlive(pid) || !buffer || !buffersize) return 0;
    snprintf(buffer, buffersize, "%s", SimProcName(pid));
    return (int)strlen(buffer);
}

// ---- the battery service
typedef struct {
    int smc;            // 1 AppleSmartBattery (M1, A12Z), 0 AppleARMPMUCharger (A9X, A10X)
    int holdObeyed;     // charging stops at powerd's IsCharging = false (M1 15.6.1: yes; A12Z 18.5: no; the PMU chargers: no)
    int pciObeyed;      // charging stops at PredictiveChargingInhibit (the PMU iPads on their bricks: yes)
    int cutObeyed;      // ExternalConnected = false makes the battery run the iPad (all four on their bricks)
    int cable;          // the cable is in
    long long watts, family; const char *desc;
    double soc, capacity; int chargeMA, loadMA;
    int allowCharge, allowInflow, pci;   // what the driver keeps (powerd's last writes, our key): across a powerd restart too
} SimBattery;
static SimBattery B = { 1, 1, 0, 1, 1, 17, (long long)0xFFFFFFFFE0024005ULL, "", 80, 7044, 2500, 150, 1, 1, 0 };
// powerd's SOC-limit service (iPadOS 18 on the SMC iPads with CHLS: the A12Z): policies by token, kept after their owner is gone and across a
// powerd restart (powerd archives them with the boot session: plans/release-1.8.7.md; gSimSocLostAtRestart plays a powerd that loses them), gone
// at a restart of the iPad (SimSocReboot); a policy stops charging once the battery is at its level.
static int gSimSocOffered, gSimSocLostAtRestart;
#define kSimMaxSoc 16
static struct { char tok[40]; int soc, pid, live; char why[64]; } gSimSoc[kSimMaxSoc];
static int gSimSocN, gSimSocSeq;
static int SimSocLive(void) { int n = 0; for (int i = 0; i < gSimSocN; i++) if (gSimSoc[i].live) n++; return n; }
static int SimSocHolds(void) {
    if (!gSimSocOffered) return 0;
    for (int i = 0; i < gSimSocN; i++) if (gSimSoc[i].live && gSimSoc[i].soc > 0 && B.soc + 0.5 >= gSimSoc[i].soc) return 1;
    return 0;
}
static int SimHoldTakes(void) { return (!B.allowCharge && B.holdObeyed) || (B.pci && B.pciObeyed) || SimSocHolds(); }
static int SimCutTakes(void) { return !B.allowInflow && B.cutObeyed; }
static int SimCharging(void) { return B.cable && !SimCutTakes() && !SimHoldTakes() && B.soc < 100; }
static int gSimShortMA;   // more load than the adapter carries: what the battery gives under a hold
static int SimAmperage(void) { return SimCharging() ? B.chargeMA : (!B.cable || SimCutTakes()) ? -B.loadMA : -gSimShortMA; }
static void SimAdvance(double seconds) {
    while (seconds > 0) {
        double dt = seconds > 10 ? 10 : seconds;
        B.soc += SimAmperage() * dt / 3600.0 / B.capacity * 100.0;
        if (B.soc > 100) B.soc = 100;
        if (B.soc < 0) B.soc = 0;
        gSimNow += dt; seconds -= dt;
    }
}
unsigned int sleep(unsigned int s) { SimAdvance(s); return 0; }
int usleep(useconds_t us) { SimAdvance(us / 1e6); return 0; }
static int gSimNoAmperage, gSimNoIsCharging;   // the battery service without that reading (the key missing)
static NSDictionary *SimBatteryPropsAll(void);
static NSDictionary *SimBatteryProps(void) {
    NSMutableDictionary *p = [SimBatteryPropsAll() mutableCopy];
    if (gSimNoAmperage) [p removeObjectForKey:@"Amperage"];
    if (gSimNoIsCharging) [p removeObjectForKey:@"IsCharging"];
    return p;
}
static NSDictionary *SimBatteryPropsAll(void) {
    int soc = (int)(B.soc + 0.5);
    int raw = B.smc ? (B.cable && B.allowInflow) : B.cable;   // (the SMC iPads read the cable as out during a cut)
    uint64_t reason = 0; long long inhibit = 0;
    if (B.smc) { if (SimCutTakes()) { reason |= 1ULL << 54; inhibit = 0x10001; } else if (SimHoldTakes()) reason |= 0x4000; }
    else { if (SimCutTakes()) reason |= 0x80; else if (SimHoldTakes()) reason |= 0x8000; }
    NSMutableDictionary *cd = [@{ @"NotChargingReason": @(reason), @"ChargingCurrent": @(SimCharging() ? B.chargeMA : 0) } mutableCopy];
    if (B.smc) cd[@"ChargerInhibitReason"] = @(inhibit);
    NSDictionary *ad = B.cable ? @{ @"Watts": @(B.watts), @"FamilyCode": @(B.family), @"AdapterID": @0, @"Description": @(B.desc) }
                               : @{ @"Watts": @0, @"FamilyCode": @0, @"Description": @"batt" };
    return @{ @"CurrentCapacity": @(soc), @"AppleRawExternalConnected": @(raw ? YES : NO), @"ExternalConnected": @(B.cable && B.allowInflow ? YES : NO),
              @"IsCharging": @(SimCharging() ? YES : NO), @"FullyCharged": @(soc >= 100 && B.cable ? YES : NO), @"Amperage": @(SimAmperage()),
              @"ChargerData": cd, @"AdapterDetails": ad };
}

// ---- powerd: its assertions, its record of each process, the scheduled wakes
#define kSimMaxAsserts 64
typedef struct { uint32_t id; int pid; char type[40], name[100], proc[40]; double since; } SimAssert;
static SimAssert gSA[kSimMaxAsserts]; static int gSAN; static uint32_t gSimNextID = 0x1001;
#define kSimMaxRecords 64
static struct { int pid; char name[40]; int watched; } gRec[kSimMaxRecords];
static int gRecN, gSimPowerdRestarts;
// A powerd started over answers gSimPowerdSlow seconds later (0: at once): until then nothing is raised, listed or scheduled.
static double gSimPowerdUpAt; static int gSimPowerdSlow;
static int SimPowerdUp(void) { return gSimNow >= gSimPowerdUpAt; }
static int SimRecord(int pid) {
    for (int i = 0; i < gRecN; i++) if (gRec[i].pid == pid) return i;
    if (gRecN >= kSimMaxRecords) return -1;
    gRec[gRecN].pid = pid; snprintf(gRec[gRecN].name, 40, "%s", SimProcName(pid)); gRec[gRecN].watched = 1;
    return gRecN++;
}
// powerd still has a record for this pid from a process that is gone (its exit already seen): a new process given this pid joins it -- its
// assertions take that name and stay after its death (the M1's "dasd" and "backboardd" holds named "Charge Limit (on hold)").
static void SimStaleRecord(int pid, const char *name) { int r = SimRecord(pid); if (r >= 0) { snprintf(gRec[r].name, 40, "%s", name); gRec[r].watched = 0; } }
static int SimCount(const char *type) { int n = 0; for (int i = 0; i < gSAN; i++) if (!strcmp(gSA[i].type, type)) n++; return n; }
static void SimApply(const char *type, int before) {   // powerd's raise / lower handler: written to the battery when the first comes and the last goes
    int after = SimCount(type);
    if (!strcmp(type, "ChargeInhibit") && (before > 0) != (after > 0)) B.allowCharge = after == 0;
    if (!strcmp(type, "DisableInflow") && (before > 0) != (after > 0)) B.allowInflow = after == 0;
}
static uint32_t SimAddAssertion(int pid, const char *type, const char *name) {
    int r = SimRecord(pid);
    if (gSAN >= kSimMaxAsserts || r < 0) return 0;
    int before = SimCount(type);
    SimAssert *a = &gSA[gSAN++];
    a->id = gSimNextID++; a->pid = pid; a->since = gSimNow;
    snprintf(a->type, 40, "%s", type); snprintf(a->name, 100, "%s", name); snprintf(a->proc, 40, "%s", gRec[r].name);
    SimApply(type, before);
    return a->id;
}
static void SimRemoveAt(int i) {
    char type[40]; snprintf(type, 40, "%s", gSA[i].type);
    int before = SimCount(type);
    gSA[i] = gSA[--gSAN];
    SimApply(type, before);
}
IOReturn IOPMAssertionCreateWithProperties(CFDictionaryRef properties, IOPMAssertionID *assertionID) {
    if (!SimPowerdUp()) { *assertionID = 0; return kIOReturnNotResponding; }
    NSDictionary *p = (__bridge NSDictionary *)properties;
    *assertionID = SimAddAssertion(gSimPid, [p[@"AssertType"] UTF8String] ?: "", [p[@"AssertName"] UTF8String] ?: "");
    return *assertionID ? kIOReturnSuccess : kIOReturnNoMemory;
}
IOReturn IOPMAssertionRelease(IOPMAssertionID assertionID) {
    for (int i = 0; i < gSAN; i++) if (gSA[i].id == assertionID) {
        if (gSA[i].pid != gSimPid) return kIOReturnNotPrivileged;   // (nothing in powerd lets another process drop it)
        SimRemoveAt(i); return kIOReturnSuccess;
    }
    return kIOReturnNotFound;
}
IOReturn IOPMCopyAssertionsByProcess(CFDictionaryRef *assertionsByPID) {
    if (!SimPowerdUp()) { *assertionsByPID = NULL; return kIOReturnNotResponding; }
    NSMutableDictionary *byPID = [NSMutableDictionary dictionary];
    for (int i = 0; i < gSAN; i++) {
        NSMutableArray *list = byPID[@(gSA[i].pid)] ?: (byPID[@(gSA[i].pid)] = [NSMutableArray array]);
        [list addObject:@{ @"AssertType": @(gSA[i].type), @"AssertName": @(gSA[i].name), @"AssertLevel": @255, @"AssertionId": @(gSA[i].id),
                           @"Process Name": @(gSA[i].proc), @"AssertStartWhen": [NSDate dateWithTimeIntervalSince1970:gSA[i].since] }];
    }
    *assertionsByPID = (CFDictionaryRef)CFBridgingRetain(byPID);
    return kIOReturnSuccess;
}
static int SimHeldBy(int pid, const char *type) { for (int i = 0; i < gSAN; i++) if (gSA[i].pid == pid && !strcmp(gSA[i].type, type)) return 1; return 0; }
static int SimOursHeld(void) { int n = 0; for (int i = 0; i < gSAN; i++) if (!strncmp(gSA[i].name, "MacStatusBar&Dock Charge Limit", 30)) n++; return n; }
static int gSimJobPid;
static int SimLeftovers(void) {   // ours by name, held under any pid but the running job's
    int n = 0;
    for (int i = 0; i < gSAN; i++) if (!strncmp(gSA[i].name, "MacStatusBar&Dock Charge Limit", 30) && gSA[i].pid != gSimJobPid) n++;
    return n;
}
// A process ends: powerd lets go of its assertions if it watches that process; a record from a pid's earlier process does not see it end.
static void SimProcExit(int pid);
static void SimKill(int pid) {
    for (int i = 0; i < gSimProcN; i++) if (gSimProcs[i].pid == pid) gSimProcs[i].alive = 0;
    int r = -1; for (int i = 0; i < gRecN; i++) if (gRec[i].pid == pid) r = i;
    if (r >= 0 && gRec[r].watched) { for (int i = gSAN - 1; i >= 0; i--) if (gSA[i].pid == pid) SimRemoveAt(i); gRec[r] = gRec[--gRecN]; }
    SimProcExit(pid);
}
// The wakes powerd has scheduled (IOPMCopyScheduledPowerEvents / IOPMSchedulePowerEvent): a restart loses them.
static NSMutableArray *gSimWakes;
CFArrayRef IOPMCopyScheduledPowerEvents(void) { return SimPowerdUp() ? (CFArrayRef)CFBridgingRetain([gSimWakes ?: @[] copy]) : NULL; }
IOReturn IOPMSchedulePowerEvent(CFDateRef time, CFStringRef myid, CFStringRef type) {
    if (!SimPowerdUp()) return kIOReturnNotResponding;
    if (!gSimWakes) gSimWakes = [NSMutableArray array];
    [gSimWakes addObject:@{ @"time": (__bridge NSDate *)time, @"scheduledby": (__bridge NSString *)myid, @"eventtype": (__bridge NSString *)type }];
    return kIOReturnSuccess;
}
static void SimPowerdRestart(void) {   // (the driver keeps what it had; the SOC-limit policies are archived: kept, unless gSimSocLostAtRestart)
    if (gSimSocLostAtRestart) gSimSocN = 0;
    gSAN = 0; gRecN = 0; [gSimWakes removeAllObjects]; gSimPowerdRestarts++; gSimPowerdUpAt = gSimNow + gSimPowerdSlow;
}
// launchctl, as the job and the prerm start it: only "kickstart -k system/com.apple.powerd" does something here. gSimKickstartFails: that many
// kickstarts fail first (launchctl exits 1, powerd left as it is); gSimLaunchctlHangs: launchctl hangs that long first, doing nothing.
static int gSimSpawns, gSimKickstartFails, gSimSpawnExit;
int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *fa, const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    gSimSpawns++; gSimSpawnExit = 0; gSimSpawnKilled = 0; gSimSpawnDoneAt = gSimNow + gSimLaunchctlHangs;
    int n = 0; while (argv[n]) n++;
    if (n >= 4 && !strcmp(argv[1], "kickstart") && !strcmp(argv[2], "-k") && !strcmp(argv[3], "system/com.apple.powerd") && !gSimLaunchctlHangs) {
        if (gSimKickstartFails > 0) { gSimKickstartFails--; gSimSpawnExit = 1; } else SimPowerdRestart();
    }
    if (pid) *pid = 4242;
    return 0;
}
pid_t waitpid(pid_t pid, int *status, int options) {
    if (gSimNow < gSimSpawnDoneAt) {
        if (options & WNOHANG) return 0;
        SimAdvance(gSimSpawnDoneAt - gSimNow);   // (the caller blocked until launchctl ends)
    }
    if (status) *status = gSimSpawnKilled ? SIGKILL : gSimSpawnExit << 8;
    return pid;
}

// ---- IOKit's registry, as the job asks it
const mach_port_t kIOMasterPortDefault = 0;
CFMutableDictionaryRef IOServiceMatching(const char *name) {
    return (CFMutableDictionaryRef)CFBridgingRetain([@{ @"IOProviderClass": @(name) } mutableCopy]);
}
io_service_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching) {
    NSString *cls = ((__bridge NSDictionary *)matching)[@"IOProviderClass"];
    CFRelease(matching);
    return [cls isEqualToString:B.smc ? @"AppleSmartBattery" : @"AppleARMPMUCharger"] ? 77 : 0;
}
kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, IOOptionBits options) {
    if (entry != 77) return kIOReturnNotFound;
    *properties = (CFMutableDictionaryRef)CFBridgingRetain([SimBatteryProps() mutableCopy]);
    return KERN_SUCCESS;
}
kern_return_t IORegistryEntrySetCFProperties(io_registry_entry_t entry, CFTypeRef properties) {
    id v = ((__bridge NSDictionary *)properties)[@"PredictiveChargingInhibit"];
    if (entry != 77 || !v) return kIOReturnBadArgument;
    B.pci = [v boolValue];
    return KERN_SUCCESS;
}
static void (*gSimPSCallback)(void *);
CFRunLoopSourceRef IOPSNotificationCreateRunLoopSource(void (*callback)(void *context), void *context) { gSimPSCallback = callback; return NULL; }
void CFRunLoopRun(void) {}   // (the job's start returns to the scenario instead of running for weeks)

// ---- notify: names with a state each, handlers run at once in their own process (getpid is theirs while they run)
#define kSimMaxTokens 256
static struct { char name[100]; void (^handler)(int); int pid, live; } gTok[kSimMaxTokens];
static int gTokN = 1;
static NSMutableDictionary *gSimState;
static int SimToken(const char *name, void (^h)(int)) {
    if (gTokN >= kSimMaxTokens) return 0;
    snprintf(gTok[gTokN].name, 100, "%s", name); gTok[gTokN].handler = h; gTok[gTokN].pid = gSimPid; gTok[gTokN].live = 1;
    return gTokN++;
}
uint32_t notify_register_check(const char *name, int *out_token) { *out_token = SimToken(name, nil); return NOTIFY_STATUS_OK; }
uint32_t notify_register_dispatch(const char *name, int *out_token, dispatch_queue_t queue, notify_handler_t handler) {
    *out_token = SimToken(name, handler); return NOTIFY_STATUS_OK;
}
uint32_t notify_cancel(int token) { if (token > 0 && token < gTokN) gTok[token].live = 0; return NOTIFY_STATUS_OK; }
uint32_t notify_get_state(int token, uint64_t *state64) {
    if (!gSimState) gSimState = [NSMutableDictionary dictionary];
    *state64 = token > 0 && token < gTokN ? [gSimState[@(gTok[token].name)] unsignedLongLongValue] : 0;
    return NOTIFY_STATUS_OK;
}
uint32_t notify_set_state(int token, uint64_t state64) {
    if (!gSimState) gSimState = [NSMutableDictionary dictionary];
    if (token > 0 && token < gTokN) gSimState[@(gTok[token].name)] = @(state64);
    return NOTIFY_STATUS_OK;
}
static NSMutableArray *gSimPosts;
uint32_t notify_post(const char *name) {
    if (!gSimPosts) gSimPosts = [NSMutableArray array];
    [gSimPosts addObject:@(name)];
    for (int i = 1; i < gTokN; i++) if (gTok[i].live && gTok[i].handler && !strcmp(gTok[i].name, name) && SimProcAlive(gTok[i].pid)) {
        int was = gSimPid; gSimPid = gTok[i].pid; gTok[i].handler(i); gSimPid = was;
    }
    return NOTIFY_STATUS_OK;
}
static uint64_t SimWord(void) { return [gSimState[@MSBD_CHARGE_STATE] unsignedLongLongValue]; }
static void SimProcExit(int pid) { for (int i = 1; i < gTokN; i++) if (gTok[i].pid == pid) gTok[i].live = 0; }

// ---- the settings as mobile reads them, and the device
static NSMutableDictionary *gSimPrefs;
Boolean CFPreferencesSynchronize(CFStringRef applicationID, CFStringRef userName, CFStringRef hostName) { return true; }
CFPropertyListRef CFPreferencesCopyValue(CFStringRef key, CFStringRef applicationID, CFStringRef userName, CFStringRef hostName) {
    id v = gSimPrefs[(__bridge NSString *)key];
    return v ? CFBridgingRetain(v) : NULL;
}
static const char *gSimOS = "15.6.1";
int sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    const char *v = !strcmp(name, "hw.machine") ? "iPad13,5" : !strcmp(name, "kern.osproductversion") ? gSimOS
                  : !strcmp(name, "kern.osversion") ? (!strcmp(gSimOS, "18.5") ? "22F76" : "19G82") : NULL;
    if (!v || !oldp || !oldlenp) { errno = ENOENT; return -1; }
    snprintf(oldp, *oldlenp, "%s", v); *oldlenp = strlen(v) + 1;
    return 0;
}

// ---- the iPads as read on 1-6 Nov (adapter kinds: 0xe0024005 the SMC iPads' USB-C, 0xe0004003 a "usb brick")
static void SimM1(void) { B = (SimBattery){ 1, 1, 0, 1, 1, 17, (long long)0xFFFFFFFFE0024005ULL, "", 80, 7044, 2500, 150, 1, 1, 0 }; gSimOS = "15.6.1"; }
static void SimA12Z(void) { B = (SimBattery){ 1, 0, 0, 1, 1, 16, (long long)0xFFFFFFFFE0024005ULL, "", 80, 8444, 2500, 120, 1, 1, 0 }; gSimOS = "18.5"; }
static void SimIPad2(void) { B = (SimBattery){ 0, 0, 1, 1, 1, 10, (long long)0xFFFFFFFFE0004003ULL, "usb brick", 80, 6476, 1300, 150, 1, 1, 0 }; gSimOS = "16.7.7"; }
// the 17.5 on its 5-10 W brick (run72: held, came down) and on the 19 W adapter of 6 Nov (93 % -> 100 % under the job's cut)
static void SimIPad17(int pd) {
    B = (SimBattery){ 0, 0, !pd, !pd, 1, pd ? 19 : 10, (long long)0xFFFFFFFFE0004003ULL, pd ? "pd charger" : "usb brick", 80, 9589, pd ? 2200 : 1300, 150, 1, 1, 0 };
    gSimOS = "17.5.1";
}
static void SimSettings(int limit, int comeDown) {
    gSimPrefs = [NSMutableDictionary dictionary];
    if (limit) gSimPrefs[@MSBD_CHARGE_LIMIT_KEY] = @(limit);
    gSimPrefs[@MSBD_CHARGE_COMEDOWN_KEY] = @(comeDown ? YES : NO);
}
static void SimSetGate(void) { int t = 0; notify_register_check(MSBD_GATE_STATE, &t); notify_set_state(t, 2); }   // (SpringBoard: the tweak runs)
// The screen as SpringBoard publishes it ("com.apple.springboard.hasBlankedScreen", state 1 = blank; nothing published = on)
static void SimScreenOff(int off) { int t = 0; notify_register_check("com.apple.springboard.hasBlankedScreen", &t); notify_set_state(t, off ? 1 : 0); }

// ---- running the job and its commands
static int gSimJobEnded;   // the job ended by itself (nothing set, chargehelper/main.m EndIdle): its process gone, what it held with it
static void SimJobIdleEnd(void) { gSimJobEnded = 1; SimKill(gSimJobPid); }
static void SimStartJob(int pid) {
    SimSetGate();
    gSimJobPid = pid; SimProcStart(pid, "msbdcharge");
    int was = gSimPid; gSimPid = pid;
    char *argv[] = { "msbdcharge", NULL };
    msbdcharge_main(1, argv);
    gSimPid = was;
}
static void SimCommand(int pid, const char *arg) {   // msbdcharge --reset / --stop / --status, as its own process
    SimProcStart(pid, "msbdcharge");
    int was = gSimPid; gSimPid = pid;
    char *argv[] = { "msbdcharge", (char *)arg, NULL };
    msbdcharge_main(2, argv);
    gSimPid = was;
    SimKill(pid);
}
// The job's minute: time goes on, the job looks (its timer, as main.m's handler: a look, then the idle end when nothing is set), as long as it runs.
static void SimMinutes(int n) {
    for (int i = 0; i < n; i++) {
        SimAdvance(60);
        if (!SimProcAlive(gSimJobPid)) continue;
        int was = gSimPid; gSimPid = gSimJobPid; Evaluate(nil); if (!ChargeWanted()) EndIdle(@"tick"); gSimPid = was;
    }
}
static void SimPowerSourceChanged(void) {
    if (!SimProcAlive(gSimJobPid) || !gSimPSCallback) return;
    int was = gSimPid; gSimPid = gSimJobPid; gSimPSCallback(NULL); gSimPid = was;
}
static int SimPublishedState(void) { return MSBDChargeWordState(SimWord()); }
static int SimLogHas(const char *s) {
    NSString *log = [NSString stringWithContentsOfFile:@kLogFile encoding:NSUTF8StringEncoding error:nil];
    return log && [log rangeOfString:@(s)].location != NSNotFound;
}

// ---- the job's one-at-a-time lock (chargehelper/main.m JobLockTake, MSBD_CHARGE_LOCK_SIM): held by a process until it dies, as flock's is
static int gSimLockPid;
static BOOL JobLockTake(void) {
    if (gSimLockPid && gSimLockPid != getpid() && SimProcAlive(gSimLockPid)) return NO;
    gSimLockPid = getpid();
    return YES;
}
static void JobLockRelease(void) { if (gSimLockPid == getpid()) gSimLockPid = 0; }   // (the job ended at its start: its process gone, as a real one is)

// ---- the job's calls to powerd's SOC-limit service (chargehelper/main.m, MSBD_CHARGE_SOC_SIM)
static int gSimSocCalls;
static BOOL SocQueryOurs(int *ours) {
    gSimSocCalls++;
    if (!gSimSocOffered || !SimPowerdUp()) return NO;
    int n = 0; for (int i = 0; i < gSimSocN; i++) if (gSimSoc[i].live && !strcmp(gSimSoc[i].why, kSocReason)) n++;
    if (ours) *ours = n;
    return YES;
}
static NSString *SocCreate(void) {
    gSimSocCalls++;
    if (!gSimSocOffered || !SimPowerdUp() || gSimSocN >= kSimMaxSoc) return nil;
    snprintf(gSimSoc[gSimSocN].tok, 40, "TOKEN-%d", ++gSimSocSeq);
    gSimSoc[gSimSocN].soc = 0; gSimSoc[gSimSocN].pid = getpid(); gSimSoc[gSimSocN].live = 1; gSimSoc[gSimSocN].why[0] = 0;
    return @(gSimSoc[gSimSocN++].tok);
}
static int SimSocFind(NSString *tok) { for (int i = 0; i < gSimSocN; i++) if (gSimSoc[i].live && !strcmp(gSimSoc[i].tok, tok.UTF8String)) return i; return -1; }
static BOOL SocSet(NSString *tok, int soc) {
    gSimSocCalls++;
    int i = SimPowerdUp() ? SimSocFind(tok) : -1;
    if (i < 0) return NO;
    gSimSoc[i].soc = soc; snprintf(gSimSoc[i].why, 64, "%s", kSocReason);
    return YES;
}
static BOOL SocRemove(NSString *tok) {
    gSimSocCalls++;
    int i = SimPowerdUp() ? SimSocFind(tok) : -1;
    if (i < 0) return NO;
    gSimSoc[i].live = 0;
    return YES;
}
static void SimSocReboot(void) { gSimSocN = 0; }   // (the iPad restarted: powerd's policies of the earlier boot session gone)
static int SimSocLevel(void) { for (int i = 0; i < gSimSocN; i++) if (gSimSoc[i].live) return gSimSoc[i].soc; return -1; }
// the A12Z on 18.5 with its SMC's CHLS: powerd's ChargeInhibit ignored, the SOC-limit service offered
static void SimA12ZSoc(void) { SimA12Z(); gSimSocOffered = 1; }
