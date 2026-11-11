// ChargeQuiet.x -- the end of the Charge Limit's adapter cut kept quiet (1.7.8 item 5; the job: chargehelper/, its notes: common/ChargeLimit.h).
// When the job lets go of its adapter cut (coming down has reached the limit), iPadOS takes the power coming back for a new connection: the
// charging chime, and the Lock Screen lit for its charging UI (the A12Z lit it for ~9 s, 1 Nov). The job posts MSBD_CHARGE_CUT_ENDING right
// before it lets go. For the next 20 s SpringBoard's chime (-[SBUIController playChargingChimeIfAppropriate]) and its screen wake for a power
// change (-possiblyWakeForPowerStatusChangeWithUnlockSource:) are skipped -- the same two methods on 16.7.7 and 17.5.1 (read 2 Nov) -- unless
// another adapter is in by then: the battery service's AdapterDetails (kept through the cut on every iPad) differ from those seen at the note,
// so a real plug-in of another charger chimes and wakes as always. Each hook goes in only where its method is, with the types it was read with.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <objc/runtime.h>
#import <notify.h>
#import <unistd.h>
#import "../common/ChargeLimit.h"

static void CQLog(NSString *line) {   // (debug builds only)
#if DEBUG
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macstatusbar.log", "a"); if (!f) return;
    NSData *d = [[NSString stringWithFormat:@"[chargequiet] %@\n", line] dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    if (d.length) fwrite(d.bytes, 1, d.length, f);
    fclose(f);
#else
    (void)line;
#endif
}

#define kCQWindow MSBD_CHARGE_QUIET_SECONDS   // seconds after the job's note
static CFAbsoluteTime gCQCutEndAt;      // the job's last "cut ending" note
static MSBDChargeAdapter gCQAdapterAtEnd;

// The adapter as the battery service describes it (the job reads the same, chargehelper/main.m AdapterNow).
static MSBDChargeAdapter CQAdapterNow(void) {
    MSBDChargeAdapter a = { 0, 0, 0, 0 };
    io_service_t s = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!s) s = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleARMPMUCharger"));
    if (!s) return a;
    CFTypeRef v = IORegistryEntryCreateCFProperty(s, CFSTR("AdapterDetails"), kCFAllocatorDefault, 0);
    IOObjectRelease(s);
    NSDictionary *ad = (__bridge_transfer id)v;
    if (![ad isKindOfClass:[NSDictionary class]]) return a;
    a.watts = [ad[@"Watts"] respondsToSelector:@selector(longLongValue)] ? [ad[@"Watts"] longLongValue] : 0;
    a.familyCode = [ad[@"FamilyCode"] respondsToSelector:@selector(longLongValue)] ? [ad[@"FamilyCode"] longLongValue] : 0;
    a.adapterID = [ad[@"AdapterID"] respondsToSelector:@selector(longLongValue)] ? [ad[@"AdapterID"] longLongValue] : 0;
    a.descriptionHash = [ad[@"Description"] isKindOfClass:[NSString class]] ? [(NSString *)ad[@"Description"] hash] : 0;
    if (a.watts < 0) a.watts = 0;
    return a;
}

// Inside the window after our own cut ended, with the same adapter: quiet.
static BOOL CQQuiet(NSString *what) {
    if (gCQCutEndAt <= 0) return NO;
    CFAbsoluteTime since = CFAbsoluteTimeGetCurrent() - gCQCutEndAt;
    if (since < 0 || since > kCQWindow) return NO;
    MSBDChargeAdapter now = CQAdapterNow();
    if (!MSBDChargeQuietAfterCut(since, gCQAdapterAtEnd, now)) {
        CQLog([NSString stringWithFormat:@"%@ %.1f s after our cut ended, but another adapter is in (%lld W, kind %llx): as always", what, since, now.watts,
               (unsigned long long)now.familyCode]);
        return NO;
    }
    CQLog([NSString stringWithFormat:@"%@ %.1f s after our cut ended (the same adapter): skipped", what, since]);
    return YES;
}

%group CQChime
%hook SBUIController
- (void)playChargingChimeIfAppropriate {
    if (CQQuiet(@"the charging chime")) return;
    %orig;
}
%end
%end

%group CQWake
%hook SBUIController
- (void)possiblyWakeForPowerStatusChangeWithUnlockSource:(long long)source {   // (read as one integer argument: see MSBDChargeQuietInit)
    if (CQQuiet(@"the screen wake for a power change")) return;
    %orig;
}
%end
%end

static BOOL CQHas(Class c, const char *sel, const char *const *types) {
    Method m = c ? class_getInstanceMethod(c, sel_registerName(sel)) : NULL;
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    for (int i = 0; t && types[i]; i++) if (!strcmp(t, types[i])) return YES;
    if (m) CQLog([NSString stringWithFormat:@"-[SBUIController %s] has types %s: not hooked", sel, t ?: "?"]);
    return NO;
}

// Called from StatusBar.x's start (after the tweak's own on / off): SpringBoard only.
void MSBDChargeQuietInit(void) {
    Class ui = objc_getClass("SBUIController");
    if (!ui) return;
    static const char *const chimeTypes[] = { "v16@0:8", NULL };
    static const char *const wakeTypes[] = { "v24@0:8q16", "v24@0:8Q16", "v20@0:8i16", "v20@0:8I16", NULL };   // (void, one integer)
    BOOL chime = CQHas(ui, "playChargingChimeIfAppropriate", chimeTypes), wake = CQHas(ui, "possiblyWakeForPowerStatusChangeWithUnlockSource:", wakeTypes);
    if (chime) %init(CQChime);
    if (wake) %init(CQWake);
    if (!chime && !wake) return;
    static int token;
    notify_register_dispatch(MSBD_CHARGE_CUT_ENDING, &token, dispatch_get_main_queue(), ^(int t) {
        gCQCutEndAt = CFAbsoluteTimeGetCurrent();
        gCQAdapterAtEnd = CQAdapterNow();
        CQLog([NSString stringWithFormat:@"the Charge Limit's cut ends: chime and power wake quiet for %.0f s (adapter %lld W, kind %llx)", kCQWindow,
               gCQAdapterAtEnd.watts, (unsigned long long)gCQAdapterAtEnd.familyCode]);
    });
    CQLog([NSString stringWithFormat:@"installed (chime %d, wake %d)", chime, wake]);
}
