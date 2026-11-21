// BatteryMenu.h -- the battery menu and the Control Center icon (2 Nov 2026, MacStatusBar&Dock 1.7.9 items 1-2), included into StatusBar.x.
// Settings > Status Bar > Battery Menu (pref batteryMenu, on unless switched off -- updaters too: DMBattApplyPref):
//  - the battery in the menu bar opens a Mac-style battery menu, to a finger or the pointer: our own button over iOS's battery item, its glyph and
//    its percentage (DMBattItemViews), so the status icons' region action -- Control Center, for a click -- is not run there (StatusBar.x
//    DMPointOverOurControl);
//  - a Control Center icon left of the clock (two switches, a Mac's; DMBattCCLayout) opens Control Center, as a click on the status icons does.
// Off: the battery is iOS's again (a click on it opens Control Center; a finger's tap there does nothing, as on a stock iPad) and there is no icon.
// The pull from the top-right edge opens Control Center either way (a system gesture, not the bar's). The menu, in a Mac's order: Battery with the
// level; the power source; what the Charge Limit's job does now, or why iPad is not charging on the adapter (1.8.8.1: DMBattWhyRead); Low Power
// Mode, iPadOS's own, switched as Control Center's toggle switches it
// (DMBattSetLowPower); our battery settings -- Charge Limit and Charge to Full Now where the job is installed (common/ChargeLimit.h), Sleep Guard's
// state (common/SleepGuard.h) --; Battery Settings….
// Where the two items go and the job's words: common/BatteryMenu.h (plain C, tools/test-batterymenu.sh).
// Not in it: a Mac's "Using Significant Energy". iPadOS keeps the apps' energy only in powerlog's database (root's, summed per hour for Settings'
// Battery page); a live list from here would be a CPU sample called energy.

#import <IOKit/IOKitLib.h>   // (the battery read from the battery service, DMBattNow and DMBattWhyRead; IOKit is linked)
static UIView *DMTrailingContainer(UIView *fg);   // (StatusBar.x: the status icons' region of a bar copy)
static const void *kBattMenuLabelKey = &kBattMenuLabelKey, *kBattMenuPillKey = &kBattMenuPillKey;   // (DMPresentMenu: no title label or pill, as the Wi-Fi menu)
static const void *kBattAXWasKey = &kBattAXWasKey;   // (an iOS battery view under our button: its own accessibility element setting, given back)
static const CGFloat kBattSwitchRowH = 34.0;         // (the Low Power Mode row: the Wi-Fi menu's switch row's height, at Small)
static __weak UIView *gBattPanel = nil;   // the open battery menu's panel (nil: none open)
static NSString *gBattMenuSignature = nil;   // (what the open menu shows: rebuilt only when this changes)
static NSTimer *gBattTimer = nil;   // (while it is open: the battery read again every 3 s)
#define MSBD_SG_CHECK   "com.besiktasliseba.sleepguard.check"     // (as Settings' Battery Use group, macsettings/BatteryUse.x: the helper looks again,
#define MSBD_SG_UPDATED "com.besiktasliseba.sleepguard.updated"   //  and says when it has written its state -- sshtoggled/SleepGuardDaemon.h)
#if DEBUG
static uint64_t gBattFakeWord = 0;   // (tests: battmenu_word_<hex> -- the Charge Limit job's state word shown as if the job had published it; 0: the real one)
#endif

// A method of exactly these types here (every private call of this file is made only with the types it was read with).
static BOOL DMBattTypes(id obj, NSString *sel, const char *types) {
    Method m = obj ? class_getInstanceMethod(object_getClass(obj), NSSelectorFromString(sel)) : NULL;
    return m && !strcmp(method_getTypeEncoding(m) ?: "", types);
}
static const char *DMBattTypesOf(id obj, NSString *sel) {   // (what a method's types are here: the probe and the fallbacks' logs)
    Method m = obj ? class_getInstanceMethod(object_getClass(obj), NSSelectorFromString(sel)) : NULL;
    return m ? (method_getTypeEncoding(m) ?: "?") : "none";
}

// ---- the battery: its level, on the power adapter or not, charging or not -- for the menu, the battery's VoiceOver value (DMBattAXValue) and the
// number in the icon (DMBattInsideNow). Read from the battery service itself (IOPMPowerSource: AppleSmartBattery, else AppleARMPMUCharger, found as
// the Charge Limit's job and ChargeQuiet.x find it), one key at a time, each only with its type: CurrentCapacity and MaxCapacity (numbers),
// ExternalConnected and IsCharging (flags). These are the keys SpringBoard's SBUIController is fed with (-batteryCapacityAsPercentage, -isOnAC,
// -isBatteryCharging: what the menu read up to 1.8.7.5), so they say what it said. Its feed is UIKit's battery monitoring, one switch for the whole
// process with no count (UIDevice batteryMonitoringEnabled): code in SpringBoard that switches it off -- another tweak reading the level, say --
// stops it, and SBUIController kept its level and "Battery" until a respring, while the bar's battery, drawn from BatteryCenter's own feed, not
// from SBUIController, moved on (issue #15). The level is CurrentCapacity, the bar's own number (79 there and in the bar while IOKit's power sources
// said 80, 17.5.1, 2 Nov), scaled where MaxCapacity is not 100 (100 on all four iPads). On the adapter is ExternalConnected, not the cable: 0
// during the Charge Limit job's adapter cut on every iPad (the PMU iPads keep AppleRawExternalConnected 1), so the menu says "Power Source:
// Battery" there, as -isOnAC did ("Using Battery Until 80%" under it, the 17.5, 1.8.7), and "Power Adapter" during its hold. A read that fails (a
// key missing, or not of its type) looks the service up once more; then IOKit's power sources (IOPSCopyPowerSourcesInfo, whose level can be a
// point off the bar's: 80 there, 79 in the bar, 17.5.1); SBUIController's stored state last, with the types it was read with. Asked when the
// menu is built (opened, its 3 s refresh, the power sources note), when the battery is read aloud, and by the number in the icon (every 5 s at
// most): never on a timer of its own.
typedef struct { int percent; BOOL onAC, charging, known; } DMBattInfo;
typedef enum { kDMBattFromNone = 0, kDMBattFromService, kDMBattFromPowerSources, kDMBattFromSBUI } DMBattFrom;
static DMBattFrom gBattFrom = kDMBattFromNone;   // (where DMBattNow's last answer came from: the probe, the debug log)
static io_service_t gBattService = MACH_PORT_NULL;
static BOOL gBattServiceLooked = NO, gBattServicePMU = NO;
static io_service_t DMBattService(BOOL *pmu) {   // (looked up once; again after a read that failed: DMBattServiceForget)
    if (!gBattServiceLooked) {
        gBattServiceLooked = YES;
        gBattService = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("AppleSmartBattery"));
        gBattServicePMU = NO;
        if (!gBattService) { gBattService = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("AppleARMPMUCharger")); gBattServicePMU = gBattService != MACH_PORT_NULL; }
        static int told = -1; int found = gBattService ? (gBattServicePMU ? 2 : 1) : 0;   // (said when what is found changes, not at each look)
        if (found != told) { told = found; DMLog([NSString stringWithFormat:@"[battmenu] the battery service: %@", @[@"none found", @"AppleSmartBattery", @"AppleARMPMUCharger"][found]]); }
    }
    if (pmu) *pmu = gBattServicePMU;
    return gBattService;
}
static void DMBattServiceForget(void) {
    if (gBattService) IOObjectRelease(gBattService);
    gBattService = MACH_PORT_NULL; gBattServiceLooked = NO;
}
static id DMBattProp(io_service_t s, NSString *key) { return s ? (__bridge_transfer id)IORegistryEntryCreateCFProperty(s, (__bridge CFStringRef)key, kCFAllocatorDefault, 0) : nil; }
// One key of the service, only with its type: a number is a CFNumber with an integer value (not a flag); a flag a CFBoolean, or a CFNumber.
static BOOL DMBattReadKey(io_service_t s, NSString *key, BOOL flag, int *out) {
    id v = DMBattProp(s, key);
    CFTypeID t = v ? CFGetTypeID((__bridge CFTypeRef)v) : 0;
    if (flag && t == CFBooleanGetTypeID()) { *out = CFBooleanGetValue((__bridge CFBooleanRef)v) ? 1 : 0; return YES; }
    long long n = 0;
    if (!v || t != CFNumberGetTypeID() || !CFNumberGetValue((__bridge CFNumberRef)v, kCFNumberLongLongType, &n)) return NO;
    if (flag) { *out = n != 0; return YES; }
    if (n < -1000000 || n > 1000000) return NO;
    *out = (int)n;
    return YES;
}
// The battery as the service says it now. NO: a key not read (*why says which).
static BOOL DMBattServiceRead(io_service_t s, DMBattInfo *b, NSString **why) {
    int cur = 0, max = 0, ext = 0, chg = 0;
    NSString *bad = !s ? @"no service" : !DMBattReadKey(s, @"CurrentCapacity", NO, &cur) ? @"CurrentCapacity" : !DMBattReadKey(s, @"MaxCapacity", NO, &max) ? @"MaxCapacity"
                  : !DMBattReadKey(s, @"ExternalConnected", YES, &ext) ? @"ExternalConnected" : !DMBattReadKey(s, @"IsCharging", YES, &chg) ? @"IsCharging" : nil;
    int p = max > 0 && max != 100 ? (int)MIN(100L, lround(100.0 * cur / max)) : cur;
    if (!bad && (cur < 0 || p < 0 || p > 100)) bad = [NSString stringWithFormat:@"CurrentCapacity %d of %d", cur, max];
    if (bad) { if (why) *why = bad; return NO; }
    *b = (DMBattInfo){ p, ext != 0, chg != 0, YES };
    return YES;
}
static DMBattInfo DMBattSBUI(void) {   // (SBUIController's stored state, with the types it was read with: 16.7.7, 17.5.1)
    DMBattInfo b = { -1, NO, NO, NO };
    id ui = DMSBManager("SBUIController");
    if (DMBattTypes(ui, @"batteryCapacityAsPercentage", "i16@0:8") && DMBattTypes(ui, @"isOnAC", "B16@0:8") && DMBattTypes(ui, @"isBatteryCharging", "B16@0:8")) {
        b.percent = ((int (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(@"batteryCapacityAsPercentage"));
        b.onAC = ((BOOL (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(@"isOnAC"));
        b.charging = ((BOOL (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(@"isBatteryCharging"));
        b.known = b.percent >= 0 && b.percent <= 100;
    }
    return b;
}
static DMBattInfo DMBattPowerSources(void) {   // (IOKit's power sources: the internal battery's description)
    DMBattInfo b = { -1, NO, NO, NO };
    static CFTypeRef (*copyInfo)(void); static CFArrayRef (*copyList)(CFTypeRef); static CFDictionaryRef (*describe)(CFTypeRef, CFTypeRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (h) { copyInfo = dlsym(h, "IOPSCopyPowerSourcesInfo"); copyList = dlsym(h, "IOPSCopyPowerSourcesList"); describe = dlsym(h, "IOPSGetPowerSourceDescription"); }
    });
    CFTypeRef info = copyInfo && copyList && describe ? copyInfo() : NULL;
    CFArrayRef list = info ? copyList(info) : NULL;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        NSDictionary *d = (__bridge NSDictionary *)describe(info, CFArrayGetValueAtIndex(list, i));
        if (![d isKindOfClass:[NSDictionary class]] || ![d[@"Type"] isEqual:@"InternalBattery"]) continue;
        int cur = [d[@"Current Capacity"] respondsToSelector:@selector(intValue)] ? [d[@"Current Capacity"] intValue] : -1;
        int max = [d[@"Max Capacity"] respondsToSelector:@selector(intValue)] ? [d[@"Max Capacity"] intValue] : 0;
        if (cur < 0) continue;
        b.percent = max > 0 && max != 100 ? (int)lround(100.0 * cur / max) : cur;
        b.onAC = [d[@"Power Source State"] isEqual:@"AC Power"];
        b.charging = [d[@"Is Charging"] respondsToSelector:@selector(boolValue)] && [d[@"Is Charging"] boolValue];
        b.known = YES;
        break;
    }
    if (list) CFRelease(list);
    if (info) CFRelease(info);
    return b;
}
#if DEBUG
// (debug) Where the battery was read from, said when that changes; and SBUIController's stored state apart from the service's for more than 60 s
// -- its feed stopped (issue #15) --, said once until the two agree again.
static void DMBattFromSaid(DMBattFrom from, NSString *why, DMBattInfo b) {
    static int told = -1;
    if ((int)from == told) return;
    told = from;
    NSString *what = [NSString stringWithFormat:@"%d%%, on AC %d, charging %d", b.percent, b.onAC, b.charging];
    if (from == kDMBattFromService) DMLog([NSString stringWithFormat:@"[battmenu] the battery read from the battery service (%@): %@", gBattServicePMU ? @"AppleARMPMUCharger" : @"AppleSmartBattery", what]);
    else if (from == kDMBattFromPowerSources) DMLog([NSString stringWithFormat:@"[battmenu] the battery read from iPadOS's power sources (the battery service: %@): %@", why ?: @"?", what]);
    else if (from == kDMBattFromSBUI) DMLog([NSString stringWithFormat:@"[battmenu] the battery read from SBUIController's stored state (the battery service: %@; no power sources): %@", why ?: @"?", what]);
    else DMLog([NSString stringWithFormat:@"[battmenu] the battery could not be read (the battery service: %@; no power sources; no SBUIController)", why ?: @"?"]);
}
static void DMBattSBUIApart(DMBattInfo svc) {
    static CFTimeInterval apartSince = 0; static BOOL told = NO;
    DMBattInfo ui = DMBattSBUI();
    if (!ui.known || (ui.percent == svc.percent && ui.onAC == svc.onAC && ui.charging == svc.charging)) { apartSince = 0; told = NO; return; }
    CFTimeInterval now = CACurrentMediaTime();
    if (apartSince <= 0) { apartSince = now; return; }
    if (told || now - apartSince <= 60.0) return;
    told = YES;
    DMLog([NSString stringWithFormat:@"[battmenu] SBUIController's stored battery has differed from the battery service for %.0f s: %d%%, on AC %d, charging %d there; %d%%, on AC %d, charging %d in the service (its feed stopped: UIDevice battery monitoring switched off in SpringBoard?)",
           now - apartSince, ui.percent, ui.onAC, ui.charging, svc.percent, svc.onAC, svc.charging]);
}
#endif
static DMBattInfo DMBattNow(void) {
    DMBattInfo b = { -1, NO, NO, NO };
    NSString *why = nil;
    DMBattFrom from = kDMBattFromService;
    if (!DMBattServiceRead(DMBattService(NULL), &b, &why)) {
        DMBattServiceForget();   // (once more: a service that went away and came back is another object)
        if (!DMBattServiceRead(DMBattService(NULL), &b, &why)) {
            b = DMBattPowerSources(); from = kDMBattFromPowerSources;
            if (!b.known) { b = DMBattSBUI(); from = b.known ? kDMBattFromSBUI : kDMBattFromNone; }
        }
    }
    gBattFrom = from;
#if DEBUG
    DMBattFromSaid(from, why, b);
    if (from == kDMBattFromService) DMBattSBUIApart(b);
#endif
    return b;
}
static NSString *DMBattPercentText(DMBattInfo b) { return b.known ? [NSString stringWithFormat:@"%d%%", b.percent] : @""; }   // (our menus are English: "82%")
// What the battery button says when it is read (VoiceOver and the other assistive features): the level, and charging or on the adapter.
static NSString *DMBattAXValue(void) {
    DMBattInfo b = DMBattNow();
    if (!b.known) return nil;
    return MSBDAXJoin(@[DMBattPercentText(b), b.charging ? @"Charging" : (b.onAC ? @"Power Adapter" : @"")]);
}

// ---- Low Power Mode: iPadOS's own, switched the way Control Center's toggle switches it. LowPowerMode.framework's _PMLowPowerMode (powerd's own
// client) -setPowerMode:fromSource:withCompletion: with Control Center's source, the framework's kPMLPMSourceControlCenter; where only
// -setPowerMode:fromSource: is there, that; else CoreDuet's _CDBatterySaver -setPowerMode:error:. Each only with the types it was read with
// (DMBattLPMHow), on a queue of its own (the calls go to powerd). The state is the public one (NSProcessInfo -isLowPowerModeEnabled).
typedef enum { kDMBattLPMNone = 0, kDMBattLPMCompletion, kDMBattLPMSource, kDMBattLPMSaver } DMBattLPMWay;
static DMBattLPMWay DMBattLPMHow(id *target, NSString **source) {
    static DMBattLPMWay way = kDMBattLPMNone; static id who = nil; static NSString *src = nil; static BOOL looked = NO;
    if (!looked) {
        looked = YES;
        if (!objc_getClass("_PMLowPowerMode")) dlopen("/System/Library/PrivateFrameworks/LowPowerMode.framework/LowPowerMode", RTLD_LAZY);
        Class pm = objc_getClass("_PMLowPowerMode");
        id lpm = [pm respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(pm, @selector(sharedInstance)) : nil;
        CFStringRef *cc = (CFStringRef *)dlsym(RTLD_DEFAULT, "kPMLPMSourceControlCenter");
        src = cc && *cc && CFGetTypeID(*cc) == CFStringGetTypeID() ? (__bridge NSString *)*cc : nil;
        if (lpm && src && DMBattTypes(lpm, @"setPowerMode:fromSource:withCompletion:", "v40@0:8q16@24@?32")) { way = kDMBattLPMCompletion; who = lpm; }
        else if (lpm && src && DMBattTypes(lpm, @"setPowerMode:fromSource:", "B32@0:8q16@24")) { way = kDMBattLPMSource; who = lpm; }
        else {
            if (!objc_getClass("_CDBatterySaver")) dlopen("/System/Library/PrivateFrameworks/CoreDuet.framework/CoreDuet", RTLD_LAZY);
            Class cd = objc_getClass("_CDBatterySaver");
            id saver = [cd respondsToSelector:NSSelectorFromString(@"batterySaver")] ? ((id (*)(id, SEL))objc_msgSend)(cd, NSSelectorFromString(@"batterySaver")) : nil;
            if (saver && DMBattTypes(saver, @"setPowerMode:error:", "B32@0:8q16^@24")) { way = kDMBattLPMSaver; who = saver; }
        }
        DMLog([NSString stringWithFormat:@"[battmenu] Low Power Mode is switched through %@ (source %@)", @[@"nothing: the switch is left out", @"_PMLowPowerMode -setPowerMode:fromSource:withCompletion:",
               @"_PMLowPowerMode -setPowerMode:fromSource:", @"_CDBatterySaver -setPowerMode:error:"][way], src ?: @"-"]);
    }
    if (target) *target = who;
    if (source) *source = src;
    return way;
}
static BOOL DMBattLowPowerOn(void) { return [NSProcessInfo processInfo].isLowPowerModeEnabled; }
static void DMBattMenuChanged(void);
static void DMBattSetLowPower(BOOL on) {
    id who = nil; NSString *src = nil;
    DMBattLPMWay way = DMBattLPMHow(&who, &src);
    if (way == kDMBattLPMNone) return;
    DM_FEATURE_MARK("battery-menu-low-power");
    DMLog([NSString stringWithFormat:@"[battmenu] Low Power Mode switched %@ from the menu", on ? @"on" : @"off"]);
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.macstatusbar.lowpower", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(q, ^{
        BOOL ok = YES; NSError *err = nil;
        if (way == kDMBattLPMCompletion) {
            void (^done)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
                if (!success || error) DMLog([NSString stringWithFormat:@"[battmenu] Low Power Mode: powerd refused (%@)", error.localizedDescription ?: @"no reason"]);
                dispatch_async(dispatch_get_main_queue(), ^{ DMBattMenuChanged(); });   // (the real state shown, whatever the answer)
            };
            ((void (*)(id, SEL, long long, id, id))objc_msgSend)(who, NSSelectorFromString(@"setPowerMode:fromSource:withCompletion:"), on ? 1 : 0, src, done);
            return;
        }
        if (way == kDMBattLPMSource) ok = ((BOOL (*)(id, SEL, long long, id))objc_msgSend)(who, NSSelectorFromString(@"setPowerMode:fromSource:"), on ? 1 : 0, src);
        else ok = ((BOOL (*)(id, SEL, long long, NSError **))objc_msgSend)(who, NSSelectorFromString(@"setPowerMode:error:"), on ? 1 : 0, &err);
        if (!ok) DMLog([NSString stringWithFormat:@"[battmenu] Low Power Mode: refused (%@)", err.localizedDescription ?: @"no reason"]);
        dispatch_async(dispatch_get_main_queue(), ^{ DMBattMenuChanged(); });
    });
}

// ---- the Charge Limit's job (only where it is part of the build: common/BatteryMenu.h MSBD_BATT_CHARGE), from what it publishes: its state word
// (notify state MSBD_CHARGE_STATE) and the setting it reads (chargeLimit); its rows only while it is installed, as Settings' Charging group.
#if MSBD_BATT_CHARGE
// Installed: its executable is there. Read from the file's own mode, not asked with access(X_OK): SpringBoard's sandbox answers that exec check with
// EPERM on 18.5 (the file there, mode 755, F_OK and stat fine: no charge rows in the menu on the A12Z with the job running, 2 Nov).
static BOOL DMBattChargeJob(void) { struct stat st; return stat(MSBD_BATT_CHARGE_JOB, &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & S_IXUSR); }
static uint64_t DMBattChargeWord(void) {
#if DEBUG
    if (gBattFakeWord) return gBattFakeWord;
#endif
    static int token; static BOOL registered = NO;
    if (!registered) registered = notify_register_check(MSBD_CHARGE_STATE, &token) == NOTIFY_STATUS_OK;
    uint64_t w = 0;
    if (registered) notify_get_state(token, &w);
    return w;
}
static int DMBattChargeLimitPref(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_CHARGE_LIMIT_KEY), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    int n = kMSBDChargeLimitOff;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n);
    if (v) CFRelease(v);
    return n;
}
#endif

// ---- why iPad is not charging on the adapter (1.8.8.1 BATTWHY, KT 15 Nov; the rule: common/ChargeWhy.h MSBDBattWhyDecide, the line: common/
// BatteryMenu.h MSBDBattMenuLine). SBUIController's charging flag cannot say it (iPadOS draws its bolt on a hold too: DMBattHoldBar), so the battery
// service itself is read: the one DMBattNow reads the level from (DMBattService, looked up again after a read that failed), one key at a time
// (never its whole dictionary). Charging or not is DMBattNow's (the service's IsCharging; where the service cannot be read, iPadOS's power sources'
// or SBUIController's); the rest only on the adapter while it does not charge, and only when the menu is built (and on the open menu's 3 s
// refresh). How long it has not charged, and has given 100 mA or more: stamped by the power sources note the menu already listens to
// (DMBattApplyPref: DMBattNow's read, and one key more -- the current -- only while it does not charge under 95 % with no hold of the job's; no
// timer, no new note) and by the menu's own read; after a respring not known until then (nothing said meanwhile). When the job's own hold or cut
// ends: its state note (also DMBattApplyPref's) and the menu's read of its word (common/ChargeWhy.h MSBDBattWhyClock, as the job keeps it). Where
// SpringBoard cannot read the service: "Not Charging" after 3 minutes, or iPadOS's own hold where its power sources say so; never a guessed reason.
static MSBDBattWhyClock gBattWhyClock;   // (CACurrentMediaTime)
#if DEBUG
static BOOL gBattFakeWhyOn = NO;   // (tests: battmenu_why_... -- the battery service read as given, and how long it has not charged at that current)
static MSBDBattWhyIn gBattFakeWhy, gBattWhyLast;   // (... and what the menu read last, for its log)
#endif
static int DMBattPropInt(id v, int *known) {   // (a number of the service: its value, *known 1; anything else: 0, *known 0)
    BOOL k = [v isKindOfClass:[NSNumber class]];
    if (known) *known = k;
    return k ? [v intValue] : 0;
}
// IOPS's "Optimized Battery Charging Engaged" of the internal battery: 1, 0, -1 not there (read only when the battery's own statements say nothing).
static int DMBattOBC(void) {
    static CFTypeRef (*copyInfo)(void); static CFArrayRef (*copyList)(CFTypeRef); static CFDictionaryRef (*describe)(CFTypeRef, CFTypeRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (h) { copyInfo = dlsym(h, "IOPSCopyPowerSourcesInfo"); copyList = dlsym(h, "IOPSCopyPowerSourcesList"); describe = dlsym(h, "IOPSGetPowerSourceDescription"); }
    });
    CFTypeRef info = copyInfo && copyList && describe ? copyInfo() : NULL;
    CFArrayRef list = info ? copyList(info) : NULL;
    int obc = -1;
    for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
        NSDictionary *d = (__bridge NSDictionary *)describe(info, CFArrayGetValueAtIndex(list, i));
        if (![d isKindOfClass:[NSDictionary class]] || ![d[@"Type"] isEqual:@"InternalBattery"]) continue;
        id v = d[@"Optimized Battery Charging Engaged"];
        if ([v isKindOfClass:[NSNumber class]]) obc = [v boolValue] ? 1 : 0;
        break;
    }
    if (list) CFRelease(list);
    if (info) CFRelease(info);
    return obc;
}
// The power sources changed (DMBattApplyPref's note, Battery Menu on): the stamps, from DMBattNow's read, the current too only where it can give
// a reason (read from the battery service, not charging, under 95 %, no hold of the job's); nothing more read off the adapter.
static void DMBattWhyNote(void) {
    if (!gBattMenuOn) { gBattWhyClock.notChargingSince = gBattWhyClock.drainingSince = 0; return; }
    DMBattInfo b = DMBattNow();
    if (!b.known || !b.onAC) { MSBDBattWhyTick(&gBattWhyClock, CACurrentMediaTime(), 0, 0); return; }
    int notCharging = !b.charging, draining = -1;
    if (gBattFrom == kDMBattFromService && notCharging && b.percent < 95 && !gBattWhyClock.ours) { int k = 0, amp = DMBattPropInt(DMBattProp(DMBattService(NULL), @"Amperage"), &k); draining = k ? amp <= MSBD_WHY_DRAIN_MA : -1; }
    MSBDBattWhyTick(&gBattWhyClock, CACurrentMediaTime(), notCharging, draining);
}
// What the menu decides from (b: DMBattNow; the job's own hold, now or just ended: gBattWhyClock, MSBDBattWhyOurs before this).
static MSBDBattWhyIn DMBattWhyRead(DMBattInfo b) {
    double now = CACurrentMediaTime();
    MSBDBattWhyIn in = { .onAdapter = b.known && b.onAC, .charging = -1, .full = -1, .soc = b.known ? b.percent : -1, .ext = -1, .raw = -1,
                         .inhibit = -1, .obc = -1, .notChargingFor = -1, .drainingFor = -1 };
#if DEBUG
    if (gBattFakeWhyOn) {
        MSBDBattWhyIn f = gBattFakeWhy;
        MSBDBattWhyTimes(&gBattWhyClock, now, &f);
        f.onAdapter = in.onAdapter; f.soc = in.soc; f.notChargingFor = gBattFakeWhy.notChargingFor; f.drainingFor = gBattFakeWhy.drainingFor;   // (how long: as given)
        gBattWhyLast = f;
        return f;
    }
#endif
    if (!in.onAdapter) {
        MSBDBattWhyTick(&gBattWhyClock, now, 0, 0);
        MSBDBattWhyTimes(&gBattWhyClock, now, &in);
#if DEBUG
        gBattWhyLast = in;
#endif
        return in;
    }
    BOOL pmu = NO; io_service_t s = gBattFrom == kDMBattFromService ? DMBattService(&pmu) : MACH_PORT_NULL;   // (nothing more where the service was not read)
    int k = 0;
    in.charging = b.charging ? 1 : 0;   // (DMBattNow's: the service's IsCharging, read just now)
    in.amp = DMBattPropInt(DMBattProp(s, @"Amperage"), &in.ampKnown);
    MSBDBattWhyTick(&gBattWhyClock, now, MSBDBattWhyCharging(in) ? 0 : 1, in.ampKnown ? in.amp <= MSBD_WHY_DRAIN_MA : -1);
    MSBDBattWhyTimes(&gBattWhyClock, now, &in);
    if (!MSBDBattWhyCharging(in)) {   // (charging: nothing more to read)
        in.pmu = pmu;
        in.full = DMBattPropInt(DMBattProp(s, @"FullyCharged"), &k); if (!k) in.full = -1;
        in.ext = DMBattPropInt(DMBattProp(s, @"ExternalConnected"), &k); if (!k) in.ext = -1;
        in.raw = DMBattPropInt(DMBattProp(s, @"AppleRawExternalConnected"), &k); if (!k) in.raw = -1;
        NSDictionary *ad = DMBattProp(s, @"AdapterDetails"), *cd = DMBattProp(s, @"ChargerData");
        in.watts = [ad isKindOfClass:[NSDictionary class]] ? DMBattPropInt(ad[@"Watts"], NULL) : 0;
        if (in.watts < 0) in.watts = 0;
        id ncr = [cd isKindOfClass:[NSDictionary class]] ? cd[@"NotChargingReason"] : nil, inhibit = [cd isKindOfClass:[NSDictionary class]] ? cd[@"ChargerInhibitReason"] : nil;
        if ([ncr isKindOfClass:[NSNumber class]]) { in.ncrKnown = 1; in.ncr = [ncr unsignedLongLongValue]; }
        in.inhibit = [inhibit isKindOfClass:[NSNumber class]] ? [inhibit longLongValue] : -1;
        in.tempCC = DMBattPropInt(DMBattProp(s, @"Temperature"), &in.tempKnown);
        if (MSBDBattWhyFirst(in) < 0) in.obc = DMBattOBC();
    }
#if DEBUG
    gBattWhyLast = in;
#endif
    return in;
}

// ---- Sleep Guard (sshtoggled, common/SleepGuard.h): its switch (sleepGuard, on unless switched off) and the helper's state file, as Settings'
// Battery Use group shows them: "iPad Can't Sleep" only while something is stuck and the guard will not or could not clear it.
static BOOL DMBattSleepGuardOn(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_SG_KEY), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = !(v && CFGetTypeID(v) == CFBooleanGetTypeID()) || CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return on;
}
static NSString *DMBattCantSleep(void) {   // (nil: nothing stuck; else the row's value, as Settings': "Since 3:12 AM" / "Sleep Guard Off")
    NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:@MSBD_SG_STATE];
    if (![st isKindOfClass:[NSDictionary class]]) return nil;
    static time_t asked = 0;   // (an old state: the helper looks -- once a minute at most, the open menu is read again every 3 s; MSBD_SG_UPDATED rebuilds it)
    if (time(NULL) - [st[@"checked"] doubleValue] > 60 && time(NULL) - asked > 60) { asked = time(NULL); notify_post(MSBD_SG_CHECK); }
    if (![st[@"cantSleep"] boolValue] || [st[@"stuck"] intValue] <= 0) return nil;
    NSString *why = [st[@"why"] isKindOfClass:[NSString class]] ? st[@"why"] : @"";
    double since = [st[@"stuckSince"] doubleValue];
    if ([why isEqualToString:@"Sleep Guard is off"]) return @"Sleep Guard Off";
    if (since > 0) return [@"Since " stringByAppendingString:[NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:since] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle]];
    return @"";
}
// Our battery settings live on Settings > Battery > Battery Health (Battery Health & Charging from 16; macsettings/BatteryHealth.x's Charging
// group, BatteryUse.x's Battery Use group), an iPhone page our Settings part opens on iPad: their rows open it at their group, by the link our
// Settings part takes to the page's row (common/BatteryHealthLink.h, macsettings/BatteryHealthLink.x). Battery Settings… opens the page itself, at
// its top (1.8.8.1 BATTSETTINGS, KT 15 Nov: "clicking battery settings in the menu should launch into the battery health settings directly"; it
// opened Settings > Battery): Battery Health on 15, Battery Health & Charging on 16-18 (where the Charge Limit is, and on 18 iPadOS's own charging
// options), the same link on all, as the rows' without a group. Where Settings has no Battery Health row (our page not built there), the link stays
// on Battery, as before.
static void DMBattOpenSettings(NSString *group, NSString *why) { DMOpenURL(MSBDBatteryHealthLink(group), why); }

// ---- the menu's own rows ----
// "Battery" and the level, a Mac menu's heading: not a tap target.
@interface DMBattHeaderRow : DMRow
@end
@implementation DMBattHeaderRow
- (instancetype)initWithLevel:(NSString *)level {
    self = [super initWithTitle:@"Battery" enabled:NO handler:nil];
    if (!self) return nil;
    self.label.font = [UIFont systemFontOfSize:DMMenuTextPt() weight:UIFontWeightSemibold];
    self.hint = level;
    return self;
}
- (void)refresh { [super refresh]; self.label.textColor = [UIColor labelColor]; self.hintLabel.textColor = [UIColor secondaryLabelColor]; }
- (NSString *)accessibilityValue { return self.hint; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitHeader; }
@end
// A line that only says something ("Power Source: Battery", "Charging On Hold at 80%"): grey, not a tap target.
@interface DMBattInfoRow : DMRow
@end
@implementation DMBattInfoRow
- (instancetype)initWithText:(NSString *)text { return [super initWithTitle:text enabled:NO handler:nil]; }
- (void)refresh { [super refresh]; self.label.textColor = [UIColor secondaryLabelColor]; }
@end
// One of our settings with its value at the right ("Charge Limit  80%"): opens Settings' Battery Health page at its group (DMBattOpenSettings). Read
// as the setting and its value.
@interface DMBattValueRow : DMRow
@end
@implementation DMBattValueRow
- (instancetype)initWithTitle:(NSString *)title value:(NSString *)value handler:(dispatch_block_t)handler {
    self = [super initWithTitle:title enabled:YES handler:handler];
    if (self) self.hint = value;
    return self;
}
- (NSString *)accessibilityValue { return self.hint; }
@end
// "Low Power Mode" with its switch, like the Wi-Fi menu's first row.
@interface DMBattSwitchRow : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UISwitch *toggle;
@end
@implementation DMBattSwitchRow
- (instancetype)initWithTitle:(NSString *)title on:(BOOL)on onChange:(void (^)(BOOL))onChange {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _label = [UILabel new];
    _label.text = title;
    _label.font = [UIFont systemFontOfSize:DMMenuTextPt()];
    _label.textColor = [UIColor labelColor];
    _label.isAccessibilityElement = NO;   // (the switch carries the name: "Low Power Mode, switch button, off")
    [self addSubview:_label];
    _toggle = [UISwitch new];
    _toggle.accessibilityLabel = title;
    _toggle.on = on;
    _toggle.onTintColor = [UIColor systemBlueColor];
    _toggle.transform = CGAffineTransformMakeScale(0.72, 0.72);
    void (^change)(BOOL) = [onChange copy];
    __weak UISwitch *weakToggle = _toggle;
    [_toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { if (weakToggle && change) change(weakToggle.on); }] forControlEvents:UIControlEventValueChanged];
    [self addSubview:_toggle];
    return self;
}
- (CGFloat)dmRowHeight { return MSBDMenuRowScaled(DMMenuSize(), kBattSwitchRowH); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.toggle.bounds.size;   // (unscaled; the transform shrinks it around its centre)
    self.toggle.center = CGPointMake(self.bounds.size.width - 12.0 - s.width * 0.72 / 2.0, self.bounds.size.height / 2.0);
    self.label.frame = CGRectMake(16.0, 0.0, self.bounds.size.width - 32.0 - s.width * 0.72, self.bounds.size.height);
}
@end

// ---- the menu ----
static NSArray *DMBattMenuItems(NSString **signatureOut) {
    NSMutableArray *items = [NSMutableArray array];
    NSMutableString *sig = [NSMutableString string];
    DMBattInfo b = DMBattNow();
    [items addObject:[[DMBattHeaderRow alloc] initWithLevel:DMBattPercentText(b)]];
    [items addObject:[[DMBattInfoRow alloc] initWithText:b.onAC ? @"Power Source: Power Adapter" : @"Power Source: Battery"]];
    [sig appendFormat:@"%d%d%d|", b.percent, b.onAC, b.known];
    BOOL job = NO; uint64_t word = 0;
#if MSBD_BATT_CHARGE
    job = DMBattChargeJob();
    word = job ? DMBattChargeWord() : 0;
    int limitPref = job ? DMBattChargeLimitPref() : kMSBDChargeLimitOff;
#endif
    // the job's line, or why iPad is not charging in its place (1.8.8.1), with or without the job; none under its hold and for 3 minutes after it
    MSBDBattWhyOurs(&gBattWhyClock, CACurrentMediaTime(), MSBDBattOurHold(word));
    MSBDBattWhyIn why = DMBattWhyRead(b);
    char line[96] = "", after[96] = "";
    int whyNow = MSBDBattWhyDecide(why);
    if (MSBDBattMenuLine(word, b.percent, whyNow, why.watts, line, sizeof line)) [items addObject:[[DMBattInfoRow alloc] initWithText:@(line)]];
    if (MSBDBattMenuLineAfter(word, b.percent, whyNow, why.watts, after, sizeof after)) [items addObject:[[DMBattInfoRow alloc] initWithText:@(after)]];   // ("Charging Can't Be Paused" after its reason)
    [sig appendFormat:@"%d%s|%s|", job, line, after];
    if (DMBattLPMHow(NULL, NULL) != kDMBattLPMNone) {
        BOOL lpm = DMBattLowPowerOn();
        [items addObject:[NSNull null]];
        [items addObject:[[DMBattSwitchRow alloc] initWithTitle:@"Low Power Mode" on:lpm onChange:^(BOOL on) { DMBattSetLowPower(on); }]];
        [sig appendFormat:@"l%d|", lpm];
    }
    // our battery settings: Charge Limit and Charge to Full Now where the job is installed, Sleep Guard's state
    [items addObject:[NSNull null]];
#if MSBD_BATT_CHARGE
    if (job) {
        char value[32]; MSBDBattChargeLimitValue(word, limitPref, value, sizeof value);
        [items addObject:[[DMBattValueRow alloc] initWithTitle:@"Charge Limit" value:@(value) handler:DMCloseThen(^{ DMBattOpenSettings(@MSBD_BH_CHARGING_GROUP, @"battery settings (charge limit)"); })]];
        BOOL full = MSBDChargeOffersFullNow(word, limitPref);
        if (full) [items addObject:[[DMRow alloc] initWithTitle:@"Charge to Full Now" enabled:YES handler:DMCloseThen(^{
            notify_post(MSBD_CHARGE_FULL_NOW);   // (the job charges to 100 % until the cable comes out, as Settings' button asks)
            DMLog(@"[battmenu] Charge to Full Now asked from the menu");
        })]];
        [sig appendFormat:@"c%s%d|", value, full];
    }
#endif
    BOOL guardOn = DMBattSleepGuardOn();
    [items addObject:[[DMBattValueRow alloc] initWithTitle:@"Sleep Guard" value:guardOn ? @"On" : @"Off" handler:DMCloseThen(^{ DMBattOpenSettings(@MSBD_BH_BATTERY_USE_GROUP, @"battery settings (sleep guard)"); })]];
    NSString *cant = DMBattCantSleep();
    if (cant) [items addObject:[[DMBattValueRow alloc] initWithTitle:@"iPad Can't Sleep" value:cant handler:DMCloseThen(^{ DMBattOpenSettings(@MSBD_BH_BATTERY_USE_GROUP, @"battery settings (can't sleep)"); })]];
    [sig appendFormat:@"g%d%@|", guardOn, cant ?: @"-"];
    [items addObject:[NSNull null]];
    [items addObject:[[DMRow alloc] initWithTitle:@"Battery Settings…" enabled:YES handler:DMCloseThen(^{ DMBattOpenSettings(nil, @"battery settings"); })]];
    if (signatureOut) *signatureOut = sig;
    return items;
}
static void DMBattLogMenu(NSString *what, NSArray *items) {
#if DEBUG
    NSMutableArray *rows = [NSMutableArray array];
    for (id it in items) {
        if (it == [NSNull null]) { [rows addObject:@"--"]; continue; }
        if ([it isKindOfClass:[DMBattSwitchRow class]]) { [rows addObject:[NSString stringWithFormat:@"%@ [%@]", ((DMBattSwitchRow *)it).label.text, ((DMBattSwitchRow *)it).toggle.on ? @"on" : @"off"]]; continue; }
        DMRow *r = it;
        [rows addObject:r.hint.length ? [NSString stringWithFormat:@"%@ = %@", r.label.text, r.hint] : r.label.text];
    }
    MSBDBattWhyIn w = gBattWhyLast;   // (why it is not charging, from what was read: -1 unknown)
    DMLog([NSString stringWithFormat:@"[battmenu] menu %@: %@ (not charging: %s%@; on the adapter %d, charging %d, %@ mA, full %d, %d %%, connected %d / %d, %d W, reasons %@ / %lld, %@ C, %@, iPadOS's optimized charging %d, ours %d, not charging for %.0f s, the battery giving 100 mA or more for %.0f s)",
           what, [rows componentsJoinedByString:@" | "], MSBDBattWhyName(MSBDBattWhyDecide(w)), gBattFakeWhyOn ? @" (test readings)" : @"", w.onAdapter, w.charging, w.ampKnown ? (id)@(w.amp) : @"-", w.full, w.soc, w.ext, w.raw,
           w.watts, w.ncrKnown ? [NSString stringWithFormat:@"0x%llx", w.ncr] : @"-", w.inhibit, w.tempKnown ? [NSString stringWithFormat:@"%.2f", w.tempCC / 100.0] : @"-", w.pmu ? @"PMU" : @"SMC",
           w.obc, w.ourHold, w.notChargingFor, w.drainingFor]);
#endif
}
// The open menu is rebuilt in place when what it shows changes (the level, the source, Low Power Mode, the job, the guard: at most once per 0.3 s).
static void DMBattRebuildOpenMenu(void) {
    UIView *old = gBattPanel;
    if (!old.window || !old.superview) return;
    NSString *sig = nil;
    NSArray *items = DMBattMenuItems(&sig);
    if ([sig isEqualToString:gBattMenuSignature]) return;
    gBattMenuSignature = sig;
    UIView *panel = DMMakePanelLike(items, old);   // (fitted to the room the open one had: StatusBar.x DMMakeFitPanel)
    CGRect f = panel.frame; f.origin = old.frame.origin;
    if ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) f.origin.x = CGRectGetMaxX(old.frame) - f.size.width;   // (hung from its right edge then: that edge stays)
    panel.frame = f;
    panel.accessibilityLabel = old.accessibilityLabel; panel.accessibilityContainerType = old.accessibilityContainerType;   // (still the "Battery menu" group)
    [old.superview insertSubview:panel aboveSubview:old];
    [old removeFromSuperview];
    gBattPanel = panel;
    DMBattLogMenu(@"updated", items);
}
static BOOL gBattRebuildPending = NO;
static void DMBattMenuChanged(void) {
    if (!gBattPanel || gBattRebuildPending) return;
    gBattRebuildPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gBattRebuildPending = NO; DMBattRebuildOpenMenu(); });
}
static void DMBattMenuGone(NSString *why) {
    if (!gBattPanel && !gBattTimer) return;
    gBattPanel = nil;
    [gBattTimer invalidate]; gBattTimer = nil;
    DMLog([NSString stringWithFormat:@"[battmenu] menu %@", why]);
}
static void DMOpenBatteryMenu(UIButton *btn) {
    if (DMTitleTapWithMenuOpen(btn)) return;
    DM_FEATURE_MARK("battery-menu");
    NSString *sig = nil;
    NSArray *items = DMBattMenuItems(&sig);
    DMPresentMenu(btn, kBattMenuLabelKey, kBattMenuPillKey, items);
    UIView *panel = gOverlay.subviews.lastObject;
    if (!gOverlay || !panel) return;   // (not opened: the Lock Screen, Guided Access)
    gBattPanel = panel;
    gBattMenuSignature = sig;
    [gBattTimer invalidate];
    gBattTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *t) { if (!gBattPanel) { [t invalidate]; if (gBattTimer == t) gBattTimer = nil; return; } DMBattMenuChanged(); }];
    DMGateTimer(gBattTimer);   // (with the screen off it waits: every menu closes then anyway)
    DMBattLogMenu(@"opened", items);
}

// ---- the battery's button in a bar copy ----
// The battery item's views, as the bar's own regions list them (each region's display items, each with its item and its view -- 15/16 UIKit's,
// 17+ SystemStatusUI's, the same calls): the glyph and the percentage come together, and a Bluetooth device's battery (another item) is not
// taken. Where a bar lists nothing that way: the battery glyph alone (_UIBatteryView's family) in the status icons' region. Shown views only.
static Class DMBattItemClass(void) { return objc_getClass(DMSBUseSTUI() ? "STUIStatusBarBatteryItem" : "_UIStatusBarBatteryItem"); }
static BOOL DMBattViewShown(UIView *v, UIView *fg) {
    if (v.bounds.size.width < 1.0 || ![v isDescendantOfView:fg]) return NO;
    for (UIView *x = v; x && x != fg; x = x.superview) if (x.hidden || x.alpha < 0.05) return NO;
    return YES;
}
static NSArray<UIView *> *DMBattItemViews(UIView *fg) {
    static SEL sRegions, sItems, sItem, sView;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sRegions = NSSelectorFromString(@"regions"); sItems = NSSelectorFromString(@"displayItems"); sItem = NSSelectorFromString(@"item"); sView = NSSelectorFromString(@"view"); });
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    UIView *bar = fg.superview;
    Class ic = DMBattItemClass();
    id regions = ic && [bar respondsToSelector:sRegions] ? ((id (*)(id, SEL))objc_msgSend)(bar, sRegions) : nil;
    if ([regions isKindOfClass:[NSDictionary class]]) for (id r in [(NSDictionary *)regions allValues]) {
        id list = [r respondsToSelector:sItems] ? ((id (*)(id, SEL))objc_msgSend)(r, sItems) : nil;
        if (![list conformsToProtocol:@protocol(NSFastEnumeration)]) continue;
        for (id di in list) {
            id it = [di respondsToSelector:sItem] ? ((id (*)(id, SEL))objc_msgSend)(di, sItem) : nil;
            if (![it isKindOfClass:ic]) continue;
            id v = [di respondsToSelector:sView] ? ((id (*)(id, SEL))objc_msgSend)(di, sView) : nil;
            if ([v isKindOfClass:[UIView class]] && DMBattViewShown(v, fg)) [views addObject:v];
        }
    }
    if (views.count) return views;
    Class glyph = objc_getClass("_UIBatteryView");
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithArray:DMTrailingContainer(fg).subviews ?: @[]];
    for (NSUInteger i = 0; i < todo.count && i < 64; i++) {
        UIView *v = todo[i];
        if (glyph && [v isKindOfClass:glyph]) { if (DMBattViewShown(v, fg)) [views addObject:v]; continue; }
        [todo addObjectsFromArray:v.subviews];
    }
    return views;
}
static CGRect DMBattItemRect(UIView *fg, NSArray<UIView *> *views) {
    CGRect u = CGRectNull;
    for (UIView *v in views) u = CGRectUnion(u, [v convertRect:v.bounds toView:fg]);   // (the status icons' shift included)
    return u;
}
// iOS's battery views under our button are not read a second time by VoiceOver (as the clock's: StatusBar.x, kClockButtonKey): their own setting
// is kept on each and given back when the button goes.
static void DMBattCoverAX(UIView *fg, NSArray<UIView *> *views, BOOL cover) {
    static const void *kCoveredKey = &kCoveredKey;
    NSHashTable<UIView *> *was = objc_getAssociatedObject(fg, kCoveredKey);
    for (UIView *v in was.allObjects) {
        if (cover && [views containsObject:v]) continue;
        NSNumber *own = objc_getAssociatedObject(v, kBattAXWasKey);
        if (own) v.isAccessibilityElement = own.boolValue;
        objc_setAssociatedObject(v, kBattAXWasKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [was removeObject:v];
    }
    if (!cover) return;
    if (!was) { was = [NSHashTable weakObjectsHashTable]; objc_setAssociatedObject(fg, kCoveredKey, was, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    for (UIView *v in views) {
        if ([was containsObject:v]) continue;
        objc_setAssociatedObject(v, kBattAXWasKey, @(v.isAccessibilityElement), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        v.isAccessibilityElement = NO;
        [was addObject:v];
    }
}
// Places the battery's button over iOS's battery item in a status bar copy (Battery Menu on; hidden otherwise, the bar then exactly as before).
// `left`: where the status icons start (leading coordinates, DMBarRTL); our Wi-Fi icon's button ends 2 pt (x k) before it. The full bar's height,
// as our other icons' buttons; 4 pt (x k) past the item at each side (common/BatteryMenu.h MSBDBattButtonSpan).
// ---- the battery percentage inside the icon (Settings > Status Bar, 1.8.4.2; off by default; the rules: common/BatteryInside.h) ------------------
// Our number on top of the battery view, on every iPadOS: iPadOS's own showsPercentage drew nothing on the static battery view of 17.5.1 and 18.5, and on 16.7.7 the bar's own
// update took it back after a Low Power Mode change or a respring (device pass, 9 Nov). Read at each bar layout and when the power state changes. The inline charging bolt, which sits
// where the number goes, is switched off while the number shows wherever the view has that switch; where it hasn't, the bolt wins while charging.
// Two-tone, split exactly at the fill's edge, as iPadOS draws its own number in the icon (1.8.7.4 round 2, KT 14 Nov: one colour for all of it
// left part of the number unreadable at most levels): two copies of the number, the same font, text and frame so their glyphs fall on the same
// pixels, the one on top masked to the fill's rect as the battery view draws it now (its own fill layer) and the other to the rest; their
// colours: common/BatteryInside.h MSBDBattInsideInksFor, from the icon's colour and the fill's as iPadOS draws it (red, green, yellow).
static BOOL gBattInsideOn = NO;
static const void *kBattInsideLabelKey = &kBattInsideLabelKey, *kBattInsideBoltKey = &kBattInsideBoltKey, *kBattInsideFillLabelKey = &kBattInsideFillLabelKey, *kBattInsideToldKey = &kBattInsideToldKey;
static CFTimeInterval gBattInsideReadAt = -100;   // (set back by the power state's changes, DMBattInsideApplyPref)
static DMBattInfo DMBattInsideNow(void) {   // (a bar is laid out often: asked once every 5 s, or when the power state says so)
    static DMBattInfo cached;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gBattInsideReadAt > 5.0) { cached = DMBattNow(); gBattInsideReadAt = now; }
    return cached;
}
static UILabel *DMBattInsideLabel(UIView *v) {   // (one copy of the number, masked to its side of the fill's edge: DMBattInsideOne)
    UILabel *label = [UILabel new]; label.textAlignment = NSTextAlignmentCenter; label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = 0.7; label.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    label.userInteractionEnabled = NO; label.isAccessibilityElement = NO;
    [v addSubview:label];
    return label;
}
static CAShapeLayer *DMBattInsideSide(UILabel *label, CGPathRef path) {   // (its mask: the fill's rect, or the rest -- the label's bounds less that rect)
    CAShapeLayer *m = (CAShapeLayer *)label.layer.mask;
    if (![m isKindOfClass:[CAShapeLayer class]]) { m = [CAShapeLayer layer]; m.fillRule = kCAFillRuleEvenOdd; label.layer.mask = m; }
    m.frame = label.layer.bounds; m.path = path;
    return m;
}
// iPadOS's fill of this battery as drawn now (_UIBatteryView's -fillLayer, both kinds: the shape layers' and the static battery's image; its frame
// is the body's inner left .. inner left + inner width x the level), its types read and in this battery's own layers; nil where it isn't.
static CALayer *DMBattInsideFillLayer(UIView *v) {
    if (!DMBattTypes(v, @"fillLayer", "@16@0:8")) return nil;
    CALayer *fill = ((CALayer *(*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"fillLayer"));
    if (![fill isKindOfClass:[CALayer class]]) return nil;
    for (CALayer *l = fill.superlayer; l; l = l.superlayer) if (l == v.layer) return fill;
    return nil;
}
static void DMBattInsideRGBA(UIColor *c, UITraitCollection *traits, double rgba[4]) {   // (a colour as drawn in this battery: for its traits; none: white)
    CGFloat r = 1, g = 1, b = 1, a = 1, w = 1;
    UIColor *k = c && traits ? [c resolvedColorWithTraitCollection:traits] : c;
    if (![k getRed:&r green:&g blue:&b alpha:&a] && [k getWhite:&w alpha:&a]) r = g = b = w;
    rgba[0] = r; rgba[1] = g; rgba[2] = b; rgba[3] = a;
}
__attribute__((noinline)) static void DMBattInsideOne(UIView *v, BOOL shown, DMBattInfo b) {
    static NSString *const boltSet = @"setShowsInlineChargingIndicator:", *const boltGet = @"showsInlineChargingIndicator";
    UILabel *label = objc_getAssociatedObject(v, kBattInsideLabelKey), *onFill = objc_getAssociatedObject(v, kBattInsideFillLabelKey);
    BOOL canHideBolt = DMBattTypes(v, boltSet, "v20@0:8B16") && DMBattTypes(v, boltGet, "B16@0:8");
    BOOL show = b.known && MSBDBattInsideShows(shown, 0, 0, 1, b.charging && !canHideBolt);
    if (canHideBolt) {   // (the bolt back as it was once the number goes; off while it shows, again at each read: the bar's own updates may put it back)
        NSNumber *was = objc_getAssociatedObject(v, kBattInsideBoltKey);
        BOOL now = ((BOOL (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(boltGet));
        if (show && now) { if (!was) objc_setAssociatedObject(v, kBattInsideBoltKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); ((void (*)(id, SEL, BOOL))objc_msgSend)(v, NSSelectorFromString(boltSet), NO); }
        else if (!show && was) { objc_setAssociatedObject(v, kBattInsideBoltKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); ((void (*)(id, SEL, BOOL))objc_msgSend)(v, NSSelectorFromString(boltSet), YES); }
    }
    if (!show) { label.hidden = YES; onFill.hidden = YES; return; }
    if (!label || !onFill) {
        [label removeFromSuperview];
        label = DMBattInsideLabel(v); onFill = DMBattInsideLabel(v);   // (the copy over the fill on top)
        objc_setAssociatedObject(v, kBattInsideLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kBattInsideFillLabelKey, onFill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMLog([NSString stringWithFormat:@"[battinside] %@: our number on top of it", NSStringFromClass([v class])]);
    }
    CGSize size = v.bounds.size;
    double level = b.percent / 100.0;
    char text[8]; MSBDBattInsideText(level, text, sizeof text);
    UIColor *icon = DMBattTypes(v, @"fillColor", "@16@0:8") ? ((UIColor *(*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"fillColor")) : v.tintColor;
    UIColor *fillColour = DMBattTypes(v, @"_batteryFillColor", "@16@0:8") ? ((UIColor *(*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"_batteryFillColor")) : nil;   // (the fill's, as iPadOS draws it)
    double ic[4], fc[4];
    DMBattInsideRGBA(icon, v.traitCollection, ic); DMBattInsideRGBA(fillColour ?: icon, v.traitCollection, fc);
    MSBDBattInsideInks inks = MSBDBattInsideInksFor(ic[0], ic[1], ic[2], fc[0], fc[1], fc[2], fc[3]);
    UIFont *font = [UIFont systemFontOfSize:MAX(6.0, size.height * MSBD_BATT_INSIDE_FONT_SHARE) weight:UIFontWeightBold];
    NSString *number = [NSString stringWithUTF8String:text];
    CGRect frame = CGRectMake(0, 0, size.width * MSBD_BATT_INSIDE_BODY_SHARE, size.height);
    for (UILabel *l in @[label, onFill]) { l.font = font; l.text = number; l.frame = frame; }
    // the fill's rect in the number's coordinates (right to left too: the battery draws its fill from the right there), its corners as the battery
    // rounds them (on the static battery they are drawn into its image, not set on the layer)
    CALayer *fill = DMBattInsideFillLayer(v);
    MSBDBattInsideBox part = { 0, 0, 0, 0, 0 };
    if (fill && !fill.hidden) {
        CGRect r = [label.layer convertRect:fill.bounds fromLayer:fill], own = CGRectZero;
        double radius = fill.cornerRadius;
        if (DMBattTypes(v, @"_fillLayerFrame:cornerRadius:", "v32@0:8^{CGRect={CGPoint=dd}{CGSize=dd}}16^d24")) ((void (*)(id, SEL, CGRect *, double *))objc_msgSend)(v, NSSelectorFromString(@"_fillLayerFrame:cornerRadius:"), &own, &radius);
        part = MSBDBattInsideFillPart((MSBDBattInsideBox){ r.origin.x, r.origin.y, r.size.width, r.size.height, radius }, frame.size.width, frame.size.height);
    }
    BOOL split = part.w > 0, restDark = fill ? inks.emptyDark : MSBDBattInsideOneInk(level, inks);   // (no fill to read: one colour, by the level)
    label.textColor = restDark ? [UIColor blackColor] : [UIColor whiteColor];
    onFill.textColor = inks.fillDark ? [UIColor blackColor] : [UIColor whiteColor];
    CGPathRef over = split ? CGPathCreateWithRoundedRect(CGRectMake(part.x, part.y, part.w, part.h), part.r, part.r, NULL) : NULL;
    CGMutablePathRef rest = CGPathCreateMutable();
    CGPathAddRect(rest, NULL, CGRectMake(0, 0, frame.size.width, frame.size.height));
    if (over) CGPathAddPath(rest, NULL, over);   // (even-odd: the fill's rect left out)
    [CATransaction begin]; [CATransaction setDisableActions:YES];   // (the masks are layers of their own: no animation of theirs)
    DMBattInsideSide(label, rest); DMBattInsideSide(onFill, over);
    [CATransaction commit];
    CGPathRelease(rest); if (over) CGPathRelease(over);
    label.hidden = NO; onFill.hidden = !split;
    int told = (fill ? 1 : 0) | (split ? 2 : 0) | (inks.fillDark ? 4 : 0) | (restDark ? 8 : 0);   // (each change of how it is drawn, once)
    NSNumber *was = objc_getAssociatedObject(v, kBattInsideToldKey);
    if (was && was.intValue == told) return;
    objc_setAssociatedObject(v, kBattInsideToldKey, @(told), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!fill) DMLog([NSString stringWithFormat:@"[battinside] %@ at %d %%: no fill layer as read (-fillLayer %s): the number in one colour, %@", NSStringFromClass([v class]), b.percent, DMBattTypesOf(v, @"fillLayer"), restDark ? @"black" : @"white"]);
    else DMLog([NSString stringWithFormat:@"[battinside] %@ at %d %%: %@ over the fill (%.2f %.2f %.2f), %@ over the rest, split at %.1f of %.1f pt", NSStringFromClass([v class]), b.percent,
                inks.fillDark ? @"black" : @"white", fc[0], fc[1], fc[2], inks.emptyDark ? @"black" : @"white", split ? part.x + part.w : 0.0, frame.size.width]);
}
// One switch (1.8.7.4 round 2, KT 14 Nov: "currently I have to toggle it on first and then turn off the battery percentage in the battery
// settings"): while it is on, iPadOS's own number beside the icon (Settings > Battery > Battery Percentage, and the one Low Power Mode shows) is
// left out of our bars and ours is inside the icon whatever iPadOS's setting says (common/BatteryInside.h MSBDBattInsideOwnLeftOut). At its
// source, as iOS's own Wi-Fi item is (StatusBar.x DMHideStockWiFi): at every data update a bar asks each item whether each of its display items
// may show (-canEnableDisplayItem:fromData:; the display item's state takes its data enability from the answer), and for the battery item's
// percentage (+percentDisplayIdentifier) in a bar of ours the answer is no, so the bar lays the battery out alone and the items beside it close
// up, with no gap. The battery item does not answer that itself (its methods as read in 15.5's and 16.4's UIKit and 17.6.1's and 18.2's
// SystemStatusUI: its superclass answers, from its data entries; the 17.6.1 and 18.2 code shows its own -applyUpdate:toDisplayItem: only ever
// turning the percentage off, when iPadOS's setting is off), so the method is added to it, calling the superclass's, as for the Wi-Fi item. Added the first time the switch is on; iPadOS's setting is never written. A change of the
// switch asks our bars again at once (DMStockVPNRecheck): switched off, the item's own answer stands again and the number beside the icon is
// back exactly as iPadOS's setting says. Our bars: dressed (kLogoKey), being set up (kHoldKey) -- as for iOS's VPN badge and Wi-Fi item -- and
// laid out the Lock Screen's way while that is their layout (StatusBar.x kNoClockLayoutKey: a copy that comes up on the Lock Screen, after a
// respring, never has the clock layout until an unlock; held while iPadOS fills it, it had iPadOS's number left out and no layout of ours put our
// number in) -- the copies the hold itself takes for ours (released as ours by their layout pass). Not a copy laid out without its clock while
// unlocked (one still being built, held, ours only while held: Control Center's header copy with iPadOS's own Control Center) nor one the hold
// gave up on (left to iOS from now on, DMBattInsideLeftToIOS). Kill switch /tmp/msb-stockbattpercent.
static BOOL gBattInsideOwnHook = NO;   // (the method went on: our bars leave iPadOS's number out while the switch is on)
static Class gBattInsideOwnItem = Nil;   // (the battery item's class it went on)
static id gBattInsideOwnID = nil;   // (that class's +percentDisplayIdentifier)
static BOOL DMBattInsideOwnCan(void) { return gBattInsideOwnHook && !DMTestFlag("/tmp/msb-stockbattpercent"); }   // (the bar's rule and the item's answer alike)
static BOOL DMBattInsideBarOurs(UIView *fg) {   // (a bar of ours: dressed, being set up, or laid out the Lock Screen's way now)
    return objc_getAssociatedObject(fg, kLogoKey) || [objc_getAssociatedObject(fg, kHoldKey) boolValue] || objc_getAssociatedObject(fg, kNoClockLayoutKey);
}
static BOOL DMBattInsideOwnOut(id item, id displayItem) {   // (iPadOS's number beside the icon: left out of this item's bar now)
    if (!gBattInsideOn || !DMBattInsideOwnCan()) return NO;
    id ident = DMBattTypes(displayItem, @"identifier", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(displayItem, NSSelectorFromString(@"identifier")) : nil;
    if (!ident || !(ident == gBattInsideOwnID || [ident isEqual:gBattInsideOwnID])) return NO;
    UIView *fg = DMCall(DMCall(item, @"statusBar"), @"foregroundView");
    return [fg isKindOfClass:[UIView class]] && MSBDBattInsideOwnLeftOut(gBattInsideOn, DMBattInsideOwnCan(), DMBattInsideBarOurs(fg));
}
static BOOL DMBattInsideCanEnable(id self, SEL _cmd, id displayItem, id data) {
    if (DMBattInsideOwnOut(self, displayItem)) return NO;
    BOOL (*orig)(id, SEL, id, id) = (BOOL (*)(id, SEL, id, id))class_getMethodImplementation(class_getSuperclass(gBattInsideOwnItem), _cmd);
    return orig ? orig(self, _cmd, displayItem, data) : YES;
}
static void DMBattInsideOwnHookInit(void) {   // (the first time the switch is on)
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = DMBattItemClass();
    SEL sel = NSSelectorFromString(@"canEnableDisplayItem:fromData:");
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    id ident = c && DMBattTypes(c, @"percentDisplayIdentifier", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"percentDisplayIdentifier")) : nil;
    BOOL asRead = m && ident && !strcmp(method_getTypeEncoding(m) ?: "", "B32@0:8@16@24");
    if (asRead) { gBattInsideOwnItem = c; gBattInsideOwnID = ident; }   // (before the method goes on: it reads them)
    if (!asRead || !class_addMethod(c, sel, (IMP)DMBattInsideCanEnable, method_getTypeEncoding(m))) {   // (not added where the class answers it itself)
        DMLog([NSString stringWithFormat:@"[battinside] %s: -canEnableDisplayItem:fromData: %s, +percentDisplayIdentifier %s, not added: iPadOS's own number stays beside the icon where its setting is on, and ours is not shown there",
               c ? class_getName(c) : "no battery item", m ? (method_getTypeEncoding(m) ?: "?") : "none", ident ? "read" : "none"]);
        return;
    }
    gBattInsideOwnHook = YES;
    DMLog([NSString stringWithFormat:@"[battinside] iPadOS's own number beside the icon is left out of our bars while the switch is on (%s -canEnableDisplayItem:fromData: added)", class_getName(c)]);
}
static void DMBattInsideOwnAskAgain(void) {   // (the switch changed: our bars' items asked again now -- iPadOS's number beside the icon out, or back)
    if (!gBattInsideOwnHook) return;   // (a held copy is asked again at its release: DMReleaseStatusBarCopy)
    for (UIView *fg in gAllBarCopies.allObjects) {
        if (!objc_getAssociatedObject(fg, kLogoKey) && !objc_getAssociatedObject(fg, kNoClockLayoutKey)) continue;
        DMStockVPNRecheck(fg);
        [fg setNeedsLayout];
    }
}
__attribute__((noinline)) static void DMBattInsideBar(UIView *fg);
// Our layout of a copy without its clock (StatusBar.x -dm_layoutLogoBody, after its record kNoClockLayoutKey: the Lock Screen's way, or a copy
// still being built): our number goes in the icon at this layout (DMBattInsideBar; the full layout places it at its own pass). Whether the bar is
// ours comes from that record with the rest (DMBattInsideBarOurs); one that this layout made ours, or not ours, without a hold to release (a copy
// the hold gave up on, laid out on the Lock Screen) has its items asked again after this layout -- iPadOS's number beside the icon out, or back
// -- and the number follows.
__attribute__((noinline)) static void DMBattInsideLockLayout(UIView *fg, BOOL wasOurs) {
    if (DMBattInsideBarOurs(fg) != wasOurs && gBattInsideOn && DMBattInsideOwnCan()) {
        __weak UIView *weakFg = fg;
        dispatch_async(dispatch_get_main_queue(), ^{ UIView *f = weakFg; if (f) { DMStockVPNRecheck(f); DMBattInsideBar(f); } });
    }
    DMBattInsideBar(fg);
}
__attribute__((noinline)) static void DMBattInsideBar(UIView *fg) {
    static BOOL everOn = NO;
    if (gBattInsideOn) everOn = YES;
    if (!everOn) return;   // (never switched on since this start: nothing of ours is on any battery)
    NSArray<UIView *> *views = DMBattItemViews(fg);
    BOOL iosOwn = NO;
    for (UIView *v in views) if ([v isKindOfClass:[UILabel class]]) iosOwn = YES;
    DMBattInfo b = DMBattInsideNow();
    BOOL shown = MSBDBattInsideShows(gBattInsideOn, iosOwn, MSBDBattInsideOwnLeftOut(gBattInsideOn, DMBattInsideOwnCan(), DMBattInsideBarOurs(fg)), 0, b.charging);
    for (UIView *v in views) if (![v isKindOfClass:[UILabel class]]) DMBattInsideOne(v, shown, b);
}
static void DMBattInsideEveryBar(void) {
    for (NSHashTable *copies in @[gCopies ?: [NSHashTable weakObjectsHashTable], gAllBarCopies ?: [NSHashTable weakObjectsHashTable]]) for (UIView *fg in copies.allObjects) DMBattInsideBar(fg);
}
// The hold gave up on this copy (StatusBar.x DMHoldSafetyCheck: left to iOS from now on): no longer ours (no hold, no record of our layouts), so
// iPadOS's number beside the icon is back where its setting is on -- the release asks the items again (DMReleaseStatusBarCopy, queued first) --
// and our number in the icon follows after that, as in any bar not ours: then, and at the layout that places iPadOS's number.
static void DMBattInsideLeftToIOS(UIView *fg) {
    if (!gBattInsideOwnHook) return;   // (iPadOS's number never left out of a bar: nothing to follow)
    __weak UIView *weakFg = fg;
    dispatch_async(dispatch_get_main_queue(), ^{ UIView *f = weakFg; if (!f) return; DMBattInsideBar(f); [f setNeedsLayout]; });
}
// Our number shown in a battery of this bar while the switch leaves iPadOS's out (StatusBar.x DMCopyHasStockText: it stands for the battery
// percentage, iPadOS's text item that a copy being set up no longer has -- the only one of a copy without its time, the Lock Screen's or Control
// Center's header copy -- so the hold still sees that iPadOS has filled the copy).
static BOOL DMBattInsideNumberIn(UIView *fg) {
    if (!gBattInsideOn || !DMBattInsideOwnCan()) return NO;
    for (UIView *v in DMBattItemViews(fg)) {
        UILabel *l = objc_getAssociatedObject(v, kBattInsideLabelKey);
        if (l && !l.hidden && l.superview == v && l.text.length) return YES;
    }
    return NO;
}
// The power state changed (the level, charging, Low Power Mode): every bar's number now, and once more 1 s later. iPadOS's bars take the same
// change from SpringBoard and redraw their batteries (the fill's width and colour) on their own, with no layout of a bar, and that may come after
// us: the number's split and colours follow the fill then (a level change: the fill's edge moves; Low Power Mode on a light bar: the fill turns
// from black to yellow, the number over it from white to black).
static void DMBattInsidePowerChanged(void) {
    gBattInsideReadAt = -100; DMBattInsideEveryBar();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gBattInsideReadAt = -100; DMBattInsideEveryBar(); });
}
static void DMBattInsideApplyPref(BOOL on) {
    static BOOL first = YES, observing = NO;
    if (on == gBattInsideOn && !first) return;
    BOOL logIt = !first || on;
    first = NO; gBattInsideOn = on;
    if (logIt) DMLog([NSString stringWithFormat:@"[battinside] Battery Percentage in Icon %@", on ? @"on" : @"off"]);
    if (on) DMBattInsideOwnHookInit();
    if (on && !observing) {
        observing = YES;
        int t = 0;
        notify_register_dispatch("com.apple.system.powersources", &t, dispatch_get_main_queue(), ^(int tok) { DMBattInsidePowerChanged(); });
        [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ DMBattInsidePowerChanged(); }); }];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ DMBattInsideOwnAskAgain(); DMBattInsideEveryBar(); });
}

// ---- the battery glyph during a charge hold (1.8.6; the rule: common/BatteryMenu.h MSBDBattHoldPlug) ------------------------------------------------
// iOS draws its charging bolt (and the green fill) for every state but 0 (on battery) -- on a hold too, since iPadOS reads the adapter as charging:
// the bolt said "charging" while the battery stayed at 80 %. While the Charge Limit's job holds (or uses the battery down to the limit, or Run on Power
// Adapter holds), our bars' batteries are kept at state 0 -- iOS's own look on battery -- and get a plug where the bolt goes, cut through the fill with
// a gap around it as iOS cuts its bolt: a Mac's "on the power adapter, not charging". The state iOS sets meanwhile is kept and given back when the hold
// ends. Only the batteries of our bars (DMBattItemViews of our copies, the TV's too); with the number inside the icon (Battery Percentage in Icon), the
// number takes the plug's place as it takes the bolt's.
#if MSBD_BATT_CHARGE
static BOOL gBattHoldPlug = NO;
static const void *kBattHoldMarkKey = &kBattHoldMarkKey, *kBattHoldOwnKey = &kBattHoldOwnKey, *kBattHoldPlugKey = &kBattHoldPlugKey, *kBattHoldMaskKey = &kBattHoldMaskKey;
static void DMBattHoldHookInit(void);   // (StatusBar.x: the battery's -setChargingState: hook, made the first time a hold is seen)
static BOOL DMBattHoldCan(UIView *v) {
    return DMBattTypes(v, @"setChargingState:", "v24@0:8q16") && DMBattTypes(v, @"chargingState", "q16@0:8");
}
// The hook's question: a battery we keep at state 0 takes `state` as iOS's own (given back later) and is set to 0 instead.
static BOOL DMBattHoldTakes(id battery, long long *state) {
    if (!objc_getAssociatedObject(battery, kBattHoldMarkKey)) return NO;
    objc_setAssociatedObject(battery, kBattHoldOwnKey, @(*state), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    *state = 0;
    return YES;
}
static UIBezierPath *DMBattPlugPath(CGRect r) {   // a plug lying towards the pin: its cord, its body, two prongs (unit 1.5 x 1)
    CGFloat u = r.size.height, x = r.origin.x, y = r.origin.y;
    UIBezierPath *p = [UIBezierPath bezierPathWithRect:CGRectMake(x, y + u * 0.42, u * 0.36, u * 0.16)];
    [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x + u * 0.3, y + u * 0.1, u * 0.75, u * 0.8) cornerRadius:u * 0.18]];
    [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(x + u * 1.05, y + u * 0.24, u * 0.45, u * 0.14)]];
    [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(x + u * 1.05, y + u * 0.62, u * 0.45, u * 0.14)]];
    return p;
}
static void DMBattHoldUnmask(UIView *v) {
    CALayer *m = objc_getAssociatedObject(v, kBattHoldMaskKey);
    if (m) { if (v.layer.mask == m) v.layer.mask = nil; objc_setAssociatedObject(v, kBattHoldMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }   // (only ours)
    CAShapeLayer *plug = objc_getAssociatedObject(v, kBattHoldPlugKey);
    plug.hidden = YES;
}
// YES: it changed the battery's charging state -- and so the fill's colour, which iPadOS draws from it (green while charging, the icon's colour at
// state 0): the number inside the icon takes its inks from that colour (DMBattInsideOne), so the bar's number is placed again (DMBattHoldBar).
__attribute__((noinline)) static BOOL DMBattHoldOne(UIView *v, BOOL hold) {
    if (!DMBattHoldCan(v)) {
        static BOOL told = NO;
        if (hold && !told) { told = YES; DMLog([NSString stringWithFormat:@"[battplug] %@: -chargingState / -setChargingState: are %s / %s here, not as read: iOS's bolt stays", NSStringFromClass([v class]), DMBattTypesOf(v, @"chargingState"), DMBattTypesOf(v, @"setChargingState:")]); }
        return NO;
    }
    SEL get = NSSelectorFromString(@"chargingState"), set = NSSelectorFromString(@"setChargingState:");
    BOOL marked = objc_getAssociatedObject(v, kBattHoldMarkKey) != nil;
    if (!hold) {
        if (!marked) return NO;
        NSNumber *own = objc_getAssociatedObject(v, kBattHoldOwnKey);
        objc_setAssociatedObject(v, kBattHoldMarkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kBattHoldOwnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMBattHoldUnmask(v);
        long long back = own ? own.longLongValue : 0;
        BOOL changed = ((long long (*)(id, SEL))objc_msgSend)(v, get) != back;
        ((void (*)(id, SEL, long long))objc_msgSend)(v, set, back);   // (iOS's state back: its bolt, if it charges now)
        [v setNeedsLayout];
        return changed;
    }
    if (!marked) {
        DMBattHoldHookInit();
        objc_setAssociatedObject(v, kBattHoldOwnKey, @(((long long (*)(id, SEL))objc_msgSend)(v, get)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kBattHoldMarkKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL changed = NO;
    if (((long long (*)(id, SEL))objc_msgSend)(v, get) != 0) { long long s = 0; ((void (*)(id, SEL, long long))objc_msgSend)(v, set, s); [v layoutIfNeeded]; changed = YES; }
    UILabel *number = objc_getAssociatedObject(v, kBattInsideLabelKey);
    CGSize size = v.bounds.size;
    MSBDBattPlugBox b = MSBDBattPlugPlace(size.width, size.height);
    if ((number && !number.hidden) || b.w <= 0) { DMBattHoldUnmask(v); return changed; }   // (the number inside the icon takes the plug's place)
    CGRect plugRect = CGRectMake(b.x, b.y, b.w, b.h);
    UIBezierPath *path = DMBattPlugPath(plugRect);
    CAShapeLayer *plug = objc_getAssociatedObject(v, kBattHoldPlugKey);
    if (!plug) {
        plug = [CAShapeLayer layer];
        objc_setAssociatedObject(v, kBattHoldPlugKey, plug, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMLog([NSString stringWithFormat:@"[battplug] %@: a plug where the bolt goes while the battery is on hold", NSStringFromClass([v class])]);
    }
    UIColor *icon = DMBattTypes(v, @"fillColor", "@16@0:8") ? ((UIColor *(*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"fillColor")) : v.tintColor;
    plug.fillColor = (icon ?: [UIColor whiteColor]).CGColor;
    plug.path = path.CGPath; plug.frame = v.layer.bounds; plug.contentsScale = v.window.screen.scale ?: 2.0; plug.hidden = NO;
    if (plug.superlayer != v.layer || v.layer.sublayers.lastObject != plug) [v.layer addSublayer:plug];   // (on top of iOS's layers)
    // the gap: one mask on the battery view's own layer -- everything shown but a band around the plug, the plug itself kept -- so it outlives iOS's
    // redraws of its own layers (a level change dropped masks set on them: the plug, the fill's colour, disappeared into the fill at 83 %, iPad 2)
    CALayer *m = objc_getAssociatedObject(v, kBattHoldMaskKey);
    if (v.layer.mask && v.layer.mask != m) { DMBattHoldUnmask(v); return changed; }   // (a mask of iOS's own on the view: left as it is, no plug)
    CGFloat scale = plug.contentsScale;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat]; fmt.scale = scale; fmt.opaque = NO;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [[UIColor whiteColor] setFill]; UIRectFill(CGRectMake(0, 0, size.width, size.height));
        UIBezierPath *cut = DMBattPlugPath(plugRect);
        cut.lineWidth = b.halo * 2; cut.lineJoinStyle = kCGLineJoinRound;
        CGContextSetBlendMode(c.CGContext, kCGBlendModeClear);
        [[UIColor whiteColor] setStroke]; [cut stroke];   // (the band, on both sides of the outline...)
        CGContextSetBlendMode(c.CGContext, kCGBlendModeNormal);
        [cut fill];                                       // (... the plug's inside back: the band stays only outside it)
    }];
    if (!m) { m = [CALayer layer]; objc_setAssociatedObject(v, kBattHoldMaskKey, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    m.frame = v.layer.bounds; m.contents = (__bridge id)img.CGImage; m.contentsScale = scale;
    if (v.layer.mask != m) v.layer.mask = m;
    return changed;
}
static void DMBattHoldWatch(void);
static CFTimeInterval gBattHoldJobAt = -100; static BOOL gBattHoldJob = NO;
__attribute__((noinline)) static void DMBattHoldBar(UIView *fg) {
    CFTimeInterval now = CACurrentMediaTime();
    // (turned off by the crash guard after a crash in it -- a piece of the status bar, CrashStep.h: on its skip list until Turn Back On clears the
    //  guard's note; read once per SpringBoard, as the loaders read the list -- iOS's battery as it is then)
    static int skipped = -1;
    if (skipped < 0) skipped = MSBDCrashSkipped(MSBD_BATT_HOLD_PIECE);
    if (skipped) return;
    if (now - gBattHoldJobAt > 10.0) { gBattHoldJob = DMBattChargeJob(); gBattHoldJobAt = now; }   // (installed or not: read every 10 s at most)
    if (gBattHoldJob) DMBattHoldWatch();
    BOOL hold = gBattHoldJob && MSBDBattHoldPlug(DMBattChargeWord());
    if (hold != gBattHoldPlug) {
        gBattHoldPlug = hold;
        DMLog([NSString stringWithFormat:@"[battplug] %@", hold ? @"on the adapter, not charging: the bars' batteries show a plug" : @"no hold: iOS's battery as it is"]);
    }
    static BOOL everOn = NO;
    if (hold) everOn = YES;
    if (!everOn) return;   // (no hold since this start: nothing of ours on any battery)
    BOOL changed = NO;
    for (UIView *v in DMBattItemViews(fg)) if (![v isKindOfClass:[UILabel class]]) changed |= DMBattHoldOne(v, hold);
    // (the hold changed a battery's state, so its fill's colour: the number inside the icon placed again, its inks for that fill -- whether this
    //  runs from the job's notification or from the bar's layout, where the number's own pass came first)
    if (changed) DMBattInsideBar(fg);
}
static void DMBattHoldEveryBar(void) {
    for (NSHashTable *copies in @[gCopies ?: [NSHashTable weakObjectsHashTable], gAllBarCopies ?: [NSHashTable weakObjectsHashTable]]) for (UIView *fg in copies.allObjects) DMBattHoldBar(fg);
}
static void DMBattHoldWatch(void) {   // (the job's state changes: every bar at once, not at its next layout)
    static BOOL watching = NO;
    if (watching) return;
    watching = YES;
    int t = 0;
    notify_register_dispatch(MSBD_CHARGE_STATE, &t, dispatch_get_main_queue(), ^(int tok) { DMBattHoldEveryBar(); });
    notify_register_dispatch("com.apple.system.powersources", &t, dispatch_get_main_queue(), ^(int tok) { DMBattHoldEveryBar(); });
}
#endif

static void DMBattLayoutButton(UIView *fg, CGFloat left, CGFloat k) {
    UIButton *btn = objc_getAssociatedObject(fg, kBattButtonKey);
    NSArray<UIView *> *views = gBattMenuOn && left < CGFLOAT_MAX ? DMBattItemViews(fg) : @[];
    CGRect r = DMBattItemRect(fg, views);
    BOOL rtl = DMBarRTL(fg);
    double a = 0, b = 0;
    if (CGRectIsNull(r) || !MSBDBattButtonSpan(DMBarLead(fg, rtl, r), DMBarTrail(fg, rtl, r), 4.0 * k, left - 2.0 * k, &a, &b)) {
        btn.hidden = YES;
        DMBattCoverAX(fg, @[], NO);
        return;
    }
    if (!btn) {
        DMAXButton *bb = [DMAXButton buttonWithType:UIButtonTypeCustom];
        bb.pointerInteractionEnabled = DMButtonPointerEffects();   // (iPadOS's highlight and pull only with its own pointer, StatusBar.x)
        bb.accessibilityLabel = @"Battery";
        bb.axValue = ^NSString *{ return DMBattAXValue(); };
        bb.accessibilityHint = @"Opens the battery menu.";
        btn = bb;
        __weak UIButton *weakBtn = btn;
        [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction *x) { if (weakBtn) DMOpenBatteryMenu(weakBtn); }] forControlEvents:UIControlEventTouchUpInside];
        [fg addSubview:btn];
        objc_setAssociatedObject(fg, kBattButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    btn.frame = DMBarRect(fg, rtl, CGRectMake(a, 0, b - a, DMBarCopyHeight(fg)));
    btn.hidden = NO;
    [fg bringSubviewToFront:btn];
    DMBattCoverAX(fg, views, YES);
}

// The Lock Screen's layout of a copy (StatusBar.x DMLayoutWithoutClock: only passive icons there): the battery is iOS's own -- no menu on the Lock
// Screen -- and the Control Center icon goes, as the Spotlight icon does; both come back with the unlocked look's layout. (Battery Percentage in
// Icon's part comes after the layout's record of what it was: DMBattInsideLockLayout, from -dm_layoutLogoBody.)
static void DMBattLockLayout(UIView *fg) {
    for (NSValue *k in @[[NSValue valueWithPointer:kCCIconKey], [NSValue valueWithPointer:kCCButtonKey], [NSValue valueWithPointer:kCCPillKey], [NSValue valueWithPointer:kBattButtonKey]])
        ((UIView *)objc_getAssociatedObject(fg, k.pointerValue)).hidden = YES;
    DMBattCoverAX(fg, @[], NO);
}

// ---- the Control Center icon ----
// SF Symbols' switch.2 (two switches: a Mac's Control Center icon) at the Spotlight icon's size and weight (the time's size + 0.5, semibold: the bar's
// size, Menu Bar Size, comes with the time's font), tinted with the bar's other items (StatusBar.x DMApplyBarItemColor), mirrored in a
// right-to-left language with the bar.
static UIImage *DMBattCCGlyph(CGFloat timePt) {
    UIImage *g = [UIImage systemImageNamed:@"switch.2" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:timePt + 0.5 weight:UIImageSymbolWeightSemibold]];
    return [[g imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] imageFlippedForRightToLeftLayoutDirection];
}
// Opens Control Center the way a click on the status icons does: their region's action runs -[SpringBoard handleStatusBarHoverActionForRegion:]
// 1, which asks Control Center's controller for -handleIndirectStatusBarAction, which presents it (-presentAnimated:completion:; read on 16.7.7 and
// 17.5.1, 2 Nov) -- BigSurCenter's panel comes down in its place where it is installed. The call takes nothing; what it returns (nothing, or
// whether it acted) is not needed. Where it is not there with those types, -presentAnimated:.
// Up already (the icon is under it then, so only from a test): put away. Not on the Lock Screen or the Cover Sheet (the icon is not there then)
// or in Guided Access.
static void DMBattOpenControlCenter(UIButton *btn) {
    { id lm = DMSBManager("SBLockScreenManager"); if (DMLockUp(lm) || DMCoverSheetShown()) { DMLog(@"[battmenu] the Lock Screen or Cover Sheet is up: Control Center not opened"); return; } }
    if (DMGARefuses(@"Control Center")) return;
    DM_FEATURE_MARK("control-center-icon");
    id cc = DMControlCenterController();
    BOOL up = DMControlCenterActive();
    if (!up && (DMBattTypes(cc, @"handleIndirectStatusBarAction", "v16@0:8") || DMBattTypes(cc, @"handleIndirectStatusBarAction", "B16@0:8"))) {
        DMLog(@"[battmenu] Control Center icon: opened (-handleIndirectStatusBarAction)");
        ((void (*)(id, SEL))objc_msgSend)(cc, NSSelectorFromString(@"handleIndirectStatusBarAction"));
        return;
    }
    NSArray *names = up ? @[@"dismissAnimated:", @"dismissAnimated:completion:"] : @[@"presentAnimated:", @"presentAnimated:completion:"];
    for (NSString *n in names) {
        SEL sel = NSSelectorFromString(n);
        if (![cc respondsToSelector:sel]) continue;
        DMLog([NSString stringWithFormat:@"[battmenu] Control Center icon: %@ (%@; -handleIndirectStatusBarAction: %s)", up ? @"put away" : @"opened", n, DMBattTypesOf(cc, @"handleIndirectStatusBarAction")]);
        if ([n hasSuffix:@"completion:"]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(cc, sel, YES, nil); else ((void (*)(id, SEL, BOOL))objc_msgSend)(cc, sel, YES);
        return;
    }
    DMLog(@"[battmenu] Control Center icon: no way to open Control Center here");
}
// The icon is lit while Control Center is open, as a Mac's menu bar item is while its menu is: a rounded highlight behind it, the bar items' colour
// at the menus' 25 % (the title pills', DMLayoutTitle), from Control Center's -_willPresent to its -_didDismiss (StatusBar.x, CCPresentSeen) --
// whichever Control Center Style shows (Apple's covers the bar with its backdrop; ours and BigSurCenter's hang under it). A tap on the icon while
// Control Center is open lands on Control Center's window, which closes it (a tap outside its panel): the icon toggles it.
static BOOL gCCIconLit = NO;
static void DMBattCCLightCopy(UIView *fg) {
    UIView *pill = objc_getAssociatedObject(fg, kCCPillKey);
    UIImageView *icon = objc_getAssociatedObject(fg, kCCIconKey);
    if (!pill) return;
    BOOL on = gCCIconLit && icon && !icon.hidden;
    if (on) pill.backgroundColor = [icon.tintColor ?: [UIColor whiteColor] colorWithAlphaComponent:0.25];
    if (pill.hidden == on) pill.hidden = !on;
}
static void DMBattCCLight(BOOL lit) {
    if (lit == gCCIconLit) return;
    gCCIconLit = lit;
    for (UIView *fg in gCopies.allObjects) DMBattCCLightCopy(fg);
}
// Lays out the bar's right end left of the clock (common/BatteryMenu.h MSBDBattRightSideLayout): the Control Center icon (Battery Menu on, or our
// own Control Center the style in force: KT 3 Nov, it is how a Mac opens it) and, for the caller, where the Spotlight icon and its button go and
// where the status icons end. clockEdge: where the clock (and anything drawn with it) starts, leading coordinates. The icon's picture is made once
// per copy (Menu Bar Size applies after a respring).
static MSBDBattRightSide DMBattCCLayout(UIView *fg, BOOL rtl, CGFloat clockEdge, CGFloat midY, UIFont *timeFont, CGFloat k, BOOL spot, CGFloat spotW, CGFloat spotSlop, CGFloat gap) {
    UIImageView *icon = objc_getAssociatedObject(fg, kCCIconKey);
    UIButton *btn = objc_getAssociatedObject(fg, kCCButtonKey);
    UIView *pill = objc_getAssociatedObject(fg, kCCPillKey);
    BOOL want = gBattMenuOn || DMCCPanelWanted();
    if (want && !icon) {
        pill = [UIView new];
        pill.userInteractionEnabled = NO; pill.hidden = YES;
        pill.layer.cornerCurve = kCACornerCurveContinuous;
        [fg addSubview:pill];
        objc_setAssociatedObject(fg, kCCPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        icon = [UIImageView new];
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.userInteractionEnabled = NO;
        icon.image = DMBattCCGlyph(timeFont.pointSize);
        [fg addSubview:icon];
        objc_setAssociatedObject(fg, kCCIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMAXButton *cb = [DMAXButton buttonWithType:UIButtonTypeCustom];
        cb.pointerInteractionEnabled = DMButtonPointerEffects();
        cb.accessibilityLabel = @"Control Center";
        cb.accessibilityHint = @"Opens Control Center.";
        btn = cb;
        __weak UIButton *weakBtn = btn;
        [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMBattOpenControlCenter(weakBtn); }] forControlEvents:UIControlEventTouchUpInside];
        [fg addSubview:btn];
        objc_setAssociatedObject(fg, kCCButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL show = want && icon.image != nil;
    CGFloat w = show ? ceil(icon.image.size.width) : 0.0, h = show ? ceil(icon.image.size.height) : 0.0;
    MSBDBattRightSide side = MSBDBattRightSideLayout(clockEdge, show, w, spot, spotW, gap, spotSlop);
    icon.hidden = btn.hidden = !show;
    if (show) {
        icon.frame = DMBarRect(fg, rtl, CGRectMake(side.ccLead, round(midY - h / 2.0), w, h));
        btn.frame = DMBarRect(fg, rtl, CGRectMake(side.ccBtnLead, 0, side.ccBtnTrail - side.ccBtnLead, DMBarCopyHeight(fg)));
        // (the highlight: the glyph and 5 pt at each side, the bar's height less 3 pt top and bottom -- a title pill's insets -- x Menu Bar Size)
        pill.frame = DMBarRect(fg, rtl, CGRectMake(side.ccLead - 5.0 * k, 3.0 * k, w + 10.0 * k, MAX(0.0, DMBarCopyHeight(fg) - 6.0 * k)));
        pill.layer.cornerRadius = 5.0 * k;
        [fg bringSubviewToFront:pill]; [fg bringSubviewToFront:icon]; [fg bringSubviewToFront:btn];
    }
    DMBattCCLightCopy(fg);
    return side;
}

// ---- the switch (StatusBar.x DMLoadPrefs) ----
static void DMBattApplyPref(BOOL on) {
    if (on == gBattMenuOn) return;
    gBattMenuOn = on;
    DMLog([NSString stringWithFormat:@"[battmenu] Battery Menu %@", on ? @"on: the battery opens its menu, the Control Center icon shows" : @"off: the battery opens Control Center"]);
    static BOOL observing = NO;
    if (on && !observing) {
        observing = YES;
        // (what the open menu shows: Low Power Mode -- posted on another thread --, the battery's power sources, the job's state, the guard's)
        [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ DMBattMenuChanged(); });
        }];
        int t = 0;
        // (and how long the battery has not charged on the adapter: DMBattWhyNote, one key read per note on the adapter -- what the menu says why from)
        notify_register_dispatch("com.apple.system.powersources", &t, dispatch_get_main_queue(), ^(int tok) { DMBattWhyNote(); DMBattMenuChanged(); });
        notify_register_dispatch(MSBD_SG_UPDATED, &t, dispatch_get_main_queue(), ^(int tok) { DMBattMenuChanged(); });
#if MSBD_BATT_CHARGE
        // (and when the job's own hold or cut ends: no reason decided for 3 minutes after it, MSBDBattWhyOursEnded -- seen as its word changes)
        MSBDBattWhyOurs(&gBattWhyClock, CACurrentMediaTime(), MSBDBattOurHold(DMBattChargeWord()));
        notify_register_dispatch(MSBD_CHARGE_STATE, &t, dispatch_get_main_queue(), ^(int tok) {
            MSBDBattWhyOurs(&gBattWhyClock, CACurrentMediaTime(), MSBDBattOurHold(DMBattChargeWord()));
            DMBattMenuChanged();
        });
#endif
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gBattMenuOn && gBattPanel) DMCloseOverlay();
        for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
    });
}

#if DEBUG
// ---- debug triggers (battmenu, battmenu_cc, battmenu_pref_<on|off>, battmenu_probe, battmenu_lpm_<0|1>, battmenu_lpmwatch, battmenu_word_<hex>,
// battmenu_why_<ncr hex>_<mA>_<W>_<centi-C>_<s>[_<full>] / battmenu_why_off, battmenu_size_<0|1|2>, battmenu_ax, battmenu_ccstack_<0|1>, battmenu_monitor_<0|1>) ----
static BOOL gBattLPMWatch = NO;
static void (*o_BattPMSet)(id, SEL, long long, id, id);
static void DMBattPMSet(id self, SEL _cmd, long long mode, id source, id done) {
    DMLog([NSString stringWithFormat:@"[lpmwatch] -[%@ setPowerMode:%lld fromSource:%@ withCompletion:] on %@", NSStringFromClass([self class]), mode, source, [NSThread isMainThread] ? @"the main thread" : @"another thread"]);
    NSArray<NSNumber *> *ret = [NSThread callStackReturnAddresses]; for (NSUInteger i = 1; i < ret.count && i < 9; i++) DMSymbolize(ret[i].unsignedLongLongValue);
    o_BattPMSet(self, _cmd, mode, source, done);
}
static BOOL (*o_BattPMSet2)(id, SEL, long long, id);
static BOOL DMBattPMSet2(id self, SEL _cmd, long long mode, id source) {
    DMLog([NSString stringWithFormat:@"[lpmwatch] -[%@ setPowerMode:%lld fromSource:%@] on %@", NSStringFromClass([self class]), mode, source, [NSThread isMainThread] ? @"the main thread" : @"another thread"]);
    NSArray<NSNumber *> *ret = [NSThread callStackReturnAddresses]; for (NSUInteger i = 1; i < ret.count && i < 9; i++) DMSymbolize(ret[i].unsignedLongLongValue);
    return o_BattPMSet2(self, _cmd, mode, source);
}
static BOOL (*o_BattCDSet)(id, SEL, long long, NSError **);
static BOOL DMBattCDSet(id self, SEL _cmd, long long mode, NSError **err) {
    DMLog([NSString stringWithFormat:@"[lpmwatch] -[%@ setPowerMode:%lld error:]", NSStringFromClass([self class]), mode]);
    NSArray<NSNumber *> *ret = [NSThread callStackReturnAddresses]; for (NSUInteger i = 1; i < ret.count && i < 9; i++) DMSymbolize(ret[i].unsignedLongLongValue);
    return o_BattCDSet(self, _cmd, mode, err);
}
static NSString *DMBattMethods(Class c, NSArray<NSString *> *words, BOOL meta) {   // (the methods whose names have one of the words, with their types)
    NSMutableString *o = [NSMutableString string];
    unsigned n = 0; Method *ms = c ? class_copyMethodList(meta ? object_getClass((id)c) : c, &n) : NULL;
    for (unsigned i = 0; i < n; i++) {
        NSString *s = NSStringFromSelector(method_getName(ms[i]));
        for (NSString *w in words) if ([s rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) { [o appendFormat:@" %c%@=%s", meta ? '+' : '-', s, method_getTypeEncoding(ms[i])]; break; }
    }
    free(ms);
    return o;
}
static BOOL DMBattTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"battmenu"]) {   // open the battery menu from the visible status bar
        for (UIView *fg in gCopies.allObjects) {
            UIButton *b = objc_getAssociatedObject(fg, kBattButtonKey);
            if (b && !b.hidden && fg.window && !fg.window.hidden && DMEffectiveAlpha(fg) > 0.5) { DMOpenBatteryMenu(b); return YES; }
        }
        DMLog(@"[battmenu] battmenu: no battery button on the screen (switch off?)");
        return YES;
    }
    if ([cmd isEqualToString:@"battmenu_cc"]) {   // what the Control Center icon's tap does
        for (UIView *fg in gCopies.allObjects) {
            UIButton *b = objc_getAssociatedObject(fg, kCCButtonKey);
            if (b && !b.hidden && fg.window && !fg.window.hidden && DMEffectiveAlpha(fg) > 0.5) { DMBattOpenControlCenter(b); return YES; }
        }
        DMLog(@"[battmenu] battmenu_cc: no Control Center icon on the screen (switch off?)");
        return YES;
    }
    if ([cmd hasPrefix:@"battmenu_pref_"]) {   // battmenu_pref_on / _off / _delete: the Settings switch, as Settings writes it (delete: never set)
        NSString *w = [cmd substringFromIndex:14];
        CFPreferencesSetValue(CFSTR(MSBD_BATT_MENU_KEY), [w isEqualToString:@"delete"] ? NULL : ([w isEqualToString:@"on"] ? kCFBooleanTrue : kCFBooleanFalse), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
        DMLog([NSString stringWithFormat:@"[battmenu] pref %@", w]);
        return YES;
    }
    if ([cmd hasPrefix:@"battmenu_size_"]) {   // battmenu_size_<0|1|2>: Menu Bar Size as Settings writes it (Small / Medium / Large: applies after a respring)
        int s = [[cmd substringFromIndex:14] intValue];
        CFPreferencesSetValue(CFSTR(kMSBDMenuBarSizeKey), (__bridge CFNumberRef)@(MAX(0, MIN(2, s))), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        DMLog([NSString stringWithFormat:@"[battmenu] Menu Bar Size stored: %d (now %d until a respring)", s, gDMBarSize]);
        return YES;
    }
    if ([cmd hasPrefix:@"battmenu_lpm_"]) { DMBattSetLowPower([[cmd substringFromIndex:13] boolValue]); return YES; }   // battmenu_lpm_<0|1>: as the menu's switch
    if ([cmd hasPrefix:@"battmenu_monitor_"]) {   // battmenu_monitor_<0|1>: UIDevice battery monitoring in SpringBoard switched as another tweak would (0: SBUIController's feed stops, issue #15; 1 or a respring: back)
        BOOL on = [[cmd substringFromIndex:17] boolValue];
        [UIDevice currentDevice].batteryMonitoringEnabled = on;
        DMLog([NSString stringWithFormat:@"[battmenu] UIDevice battery monitoring switched %@ in SpringBoard (now %d): SBUIController's feed %@", on ? @"on" : @"off",
               [UIDevice currentDevice].batteryMonitoringEnabled, on ? @"back" : @"stops"]);
        return YES;
    }
    if ([cmd hasPrefix:@"battmenu_lpmraw_"]) {   // battmenu_lpmraw_<0|1>: Low Power Mode switched as Settings' switch does, nothing of the menu's own (an open menu follows by itself)
        Class pm = objc_getClass("_PMLowPowerMode");
        id lpm = [pm respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(pm, @selector(sharedInstance)) : nil;
        CFStringRef *src = (CFStringRef *)dlsym(RTLD_DEFAULT, "kPMLPMSourceSettings");
        if (lpm && src && *src && DMBattTypes(lpm, @"setPowerMode:fromSource:withCompletion:", "v40@0:8q16@24@?32"))
            ((void (*)(id, SEL, long long, id, id))objc_msgSend)(lpm, NSSelectorFromString(@"setPowerMode:fromSource:withCompletion:"), [[cmd substringFromIndex:16] longLongValue], (__bridge NSString *)*src, ^(BOOL ok, NSError *e) {});
        DMLog([NSString stringWithFormat:@"[battmenu] Low Power Mode %@ (as Settings, %@)", [[cmd substringFromIndex:16] boolValue] ? @"on" : @"off", lpm ? @"sent" : @"no _PMLowPowerMode"]);
        return YES;
    }
    if ([cmd hasPrefix:@"battmenu_appearance_"]) {   // battmenu_appearance_<1|2>: the system's Light (1) / Dark (2) appearance, as Control Center's Dark Mode toggle sets it (put it back)
        Class m = objc_getClass("UISUserInterfaceStyleMode");
        if (!m) { dlopen("/System/Library/PrivateFrameworks/UIKitServices.framework/UIKitServices", RTLD_LAZY); m = objc_getClass("UISUserInterfaceStyleMode"); }
        SEL init = NSSelectorFromString(@"initWithDelegate:"), set = NSSelectorFromString(@"setModeValue:");
        id mode = [m instancesRespondToSelector:init] ? ((id (*)(id, SEL, id))objc_msgSend)([m alloc], init, nil) : nil;
        if ([mode respondsToSelector:set]) ((void (*)(id, SEL, long long))objc_msgSend)(mode, set, [[cmd substringFromIndex:20] longLongValue]);
        DMLog([NSString stringWithFormat:@"[battmenu] appearance %@ (%@)", [cmd substringFromIndex:20], mode ? @"set" : @"no UISUserInterfaceStyleMode"]);
        return YES;
    }
    if ([cmd hasPrefix:@"battmenu_word_"]) {   // battmenu_word_<hex>: the job's state word shown as if published (0: the real one)
        gBattFakeWord = strtoull([[cmd substringFromIndex:14] UTF8String], NULL, 16);
        DMLog([NSString stringWithFormat:@"[battmenu] test state word %llx", gBattFakeWord]);
        DMBattMenuChanged();
#if MSBD_BATT_CHARGE
        DMBattHoldEveryBar();   // (the bars' batteries as with that word: the plug, 1.8.6)
#endif
        return YES;
    }
    if ([cmd hasPrefix:@"battmenu_why_"]) {   // battmenu_why_<NotChargingReason hex>_<Amperage mA>_<Watts>_<Temperature, centi-C>_<s not charging>[_<FullyCharged>]: the battery
                                              // service read as these (connected, not charging, no inhibit, that current for as long; the bar's level and power source real);
                                              // battmenu_why_off: as read
        NSArray<NSString *> *p = [[cmd substringFromIndex:13] componentsSeparatedByString:@"_"];
        gBattFakeWhyOn = p.count >= 5;
        if (gBattFakeWhyOn) {
            BOOL pmu = NO; DMBattService(&pmu);
            gBattFakeWhy = (MSBDBattWhyIn){ .charging = 0, .ampKnown = 1, .amp = p[1].intValue, .full = p.count > 5 ? p[5].intValue : 0, .ext = 1, .raw = 1, .watts = p[2].intValue,
                                            .ncrKnown = 1, .ncr = strtoull(p[0].UTF8String, NULL, 16), .inhibit = 0, .tempKnown = 1, .tempCC = p[3].intValue, .pmu = pmu, .obc = 0,
                                            .notChargingFor = p[4].doubleValue, .drainingFor = p[4].doubleValue };
        }
        DMLog(gBattFakeWhyOn ? [NSString stringWithFormat:@"[battmenu] test readings: reasons 0x%llx, %d mA, %d W, %.2f C, not charging for %.0f s, full %d (%@)", gBattFakeWhy.ncr, gBattFakeWhy.amp,
                                gBattFakeWhy.watts, gBattFakeWhy.tempCC / 100.0, gBattFakeWhy.notChargingFor, gBattFakeWhy.full, gBattFakeWhy.pmu ? @"PMU" : @"SMC"] : @"[battmenu] the battery service as read again");
        DMBattMenuChanged();
        return YES;
    }
    if ([cmd isEqualToString:@"battmenu_rows"]) { DMBattLogMenu(@"now", DMBattMenuItems(NULL)); return YES; }   // what the menu would show now
    if ([cmd hasPrefix:@"battmenu_ccstack_"]) {   // battmenu_ccstack_<0|1>: log who presents Control Center (StatusBar.x's -_willPresent hook)
        BOOL on = [[cmd substringFromIndex:17] boolValue];
        if (on) { FILE *f = fopen("/tmp/msb-ccstack", "w"); if (f) fclose(f); } else unlink("/tmp/msb-ccstack");
        DMLog([NSString stringWithFormat:@"[battmenu] Control Center presenters %@", on ? @"logged" : @"not logged"]);
        return YES;
    }
    if ([cmd isEqualToString:@"battmenu_lpmwatch"]) {   // log every Low Power Mode change made through the framework calls (Control Center's toggle, ours)
        if (gBattLPMWatch) return YES;
        gBattLPMWatch = YES;
        DMBattLPMHow(NULL, NULL);
        Class pm = objc_getClass("_PMLowPowerMode"), cd = objc_getClass("_CDBatterySaver");
        SEL a = NSSelectorFromString(@"setPowerMode:fromSource:withCompletion:"), b = NSSelectorFromString(@"setPowerMode:fromSource:"), c = NSSelectorFromString(@"setPowerMode:error:");
        Method ma = pm ? class_getInstanceMethod(pm, a) : NULL, mb = pm ? class_getInstanceMethod(pm, b) : NULL, mc = cd ? class_getInstanceMethod(cd, c) : NULL;
        if (ma && !strcmp(method_getTypeEncoding(ma), "v40@0:8q16@24@?32")) MSHookMessageEx(pm, a, (IMP)DMBattPMSet, (IMP *)&o_BattPMSet);
        if (mb && !strcmp(method_getTypeEncoding(mb), "B32@0:8q16@24")) MSHookMessageEx(pm, b, (IMP)DMBattPMSet2, (IMP *)&o_BattPMSet2);
        if (mc && !strcmp(method_getTypeEncoding(mc), "B32@0:8q16^@24")) MSHookMessageEx(cd, c, (IMP)DMBattCDSet, (IMP *)&o_BattCDSet);
        DMLog([NSString stringWithFormat:@"[lpmwatch] watching: completion %d, source %d, battery saver %d", o_BattPMSet != NULL, o_BattPMSet2 != NULL, o_BattCDSet != NULL]);
        return YES;
    }
    if ([cmd isEqualToString:@"battmenu_probe"]) {   // read-only: the calls and classes this menu uses, on this iPadOS
        NSMutableString *o = [NSMutableString stringWithString:@"[battprobe]"];
        id who = nil; NSString *src = nil; DMBattLPMWay way = DMBattLPMHow(&who, &src);
        [o appendFormat:@"\n  low power: way %d target %@ source %@, on %d; Control Center's -handleIndirectStatusBarAction: %s", way, who ? NSStringFromClass([who class]) : @"-", src,
            DMBattLowPowerOn(), DMBattTypesOf(DMControlCenterController(), @"handleIndirectStatusBarAction")];
#if MSBD_BATT_CHARGE
        {   // (the Charge Limit's job as the menu looks for it, and the ways a process can see the file)
            errno = 0; int x = access(MSBD_BATT_CHARGE_JOB, X_OK), ex = errno;
            errno = 0; int f = access(MSBD_BATT_CHARGE_JOB, F_OK), ef = errno;
            struct stat st; errno = 0; int sr = stat(MSBD_BATT_CHARGE_JOB, &st), es = errno;
            [o appendFormat:@"\n  charge job %s: access X_OK %d (errno %d), F_OK %d (errno %d), stat %d (errno %d, mode %o); job %d, word %llx", MSBD_BATT_CHARGE_JOB, x, ex, f, ef, sr, es,
                sr == 0 ? (unsigned)st.st_mode : 0u, DMBattChargeJob(), DMBattChargeWord()];
        }
#endif
        for (NSString *cn in @[@"_PMLowPowerMode", @"_CDBatterySaver", @"SBUIController", @"_UIStatusBarBatteryItem", @"STUIStatusBarBatteryItem"]) {
            Class c = objc_getClass(cn.UTF8String);
            [o appendFormat:@"\n  %@ %@:%@%@", cn, c ? @"present" : @"MISSING", DMBattMethods(c, @[@"PowerMode", @"batterySaver", @"sharedInstance", @"attery", @"OnAC", @"Charg"], YES),
                DMBattMethods(c, @[@"PowerMode", @"setMode", @"getMode", @"attery", @"OnAC", @"Charg", @"Display"], NO)];
            unsigned ni = 0; Ivar *iv = c ? class_copyIvarList(c, &ni) : NULL;
            if (ni) { [o appendString:@" ivars:"]; for (unsigned i = 0; i < ni; i++) [o appendFormat:@" %s=%s", ivar_getName(iv[i]), ivar_getTypeEncoding(iv[i])]; }
            free(iv);
        }
        for (NSString *sym in @[@"kPMLPMSourceControlCenter", @"kPMLPMSourceSettings", @"kPMLPMSourceSpringBoardAlert"]) {
            CFStringRef *p = (CFStringRef *)dlsym(RTLD_DEFAULT, sym.UTF8String);
            [o appendFormat:@"\n  %@ = %@", sym, p && *p ? (__bridge NSString *)*p : @"(no symbol)"];
        }
        DMBattInfo b = DMBattNow();
        [o appendFormat:@"\n  the menu's battery: known %d, %d%%, on AC %d, charging %d, from %@;", b.known, b.percent, b.onAC, b.charging,
            @[@"nothing", @"the battery service", @"iPadOS's power sources", @"SBUIController"][gBattFrom]];
        {   // (the battery service's keys as SpringBoard reads them here, raw)
            BOOL pmu = NO; io_service_t s = DMBattService(&pmu);
            [o appendFormat:@" service %@:", s ? (pmu ? @"AppleARMPMUCharger" : @"AppleSmartBattery") : @"none"];
            for (NSString *k in @[@"CurrentCapacity", @"MaxCapacity", @"ExternalConnected", @"IsCharging", @"AppleRawExternalConnected"]) {
                id v = DMBattProp(s, k);
                [o appendFormat:@" %@ %@ (%@);", k, v ?: @"-", v ? NSStringFromClass([v class]) : @"not read"];
            }
            // (1.8.8.1 BATTWHY: the keys why iPad is not charging is read from, whether SpringBoard may read them -- on battery too, A-B1 on 18.5)
            for (NSString *k in @[@"Amperage", @"FullyCharged", @"Temperature", @"AdapterDetails", @"ChargerData"]) {
                id v = DMBattProp(s, k);
                NSString *shown = ![v isKindOfClass:[NSDictionary class]] ? [NSString stringWithFormat:@"%@", v ?: @"-"]
                                : [NSString stringWithFormat:@"%lu keys, Watts %@, NotChargingReason %@, ChargerInhibitReason %@", (unsigned long)[v count], v[@"Watts"] ?: @"-",
                                   v[@"NotChargingReason"] ?: @"-", v[@"ChargerInhibitReason"] ?: @"-"];
                [o appendFormat:@" %@ %@ (%@);", k, shown, v ? NSStringFromClass([v class]) : @"not read"];
            }
            [o appendFormat:@" UIDevice battery monitoring %d;", [UIDevice currentDevice].batteryMonitoringEnabled];
        }
        id ui = DMSBManager("SBUIController");
        for (NSString *s in @[@"batteryCapacityAsPercentage", @"isOnAC", @"isBatteryCharging", @"batteryCapacity"]) {
            SEL sel = NSSelectorFromString(s); Method m = ui ? class_getInstanceMethod(object_getClass(ui), sel) : NULL;
            if (!m) { [o appendFormat:@" SBUIController -%@: none;", s]; continue; }
            const char *t = method_getTypeEncoding(m);
            if (t[0] == 'B' || t[0] == 'c') [o appendFormat:@" -%@ = %d;", s, ((BOOL (*)(id, SEL))objc_msgSend)(ui, sel)];
            else if (t[0] == 'i' || t[0] == 'q' || t[0] == 'l') [o appendFormat:@" -%@ = %lld;", s, (long long)((long long (*)(id, SEL))objc_msgSend)(ui, sel)];
            else if (t[0] == 'f' || t[0] == 'd') [o appendFormat:@" -%@ (%s);", s, t];
            else [o appendFormat:@" -%@ (%s);", s, t];
        }
        UIImage *g = [UIImage systemImageNamed:@"switch.2"];
        [o appendFormat:@"\n  switch.2: %@", g ? NSStringFromCGSize(g.size) : @"MISSING"];
        Class glyph = objc_getClass("_UIBatteryView");
        for (UIView *fg in gCopies.allObjects) {
            if (!fg.window || fg.window.hidden || fg.bounds.size.width < 300.0) continue;
            NSArray *views = DMBattItemViews(fg);
            [o appendFormat:@"\n  copy %p in %@ (alpha %.2f): battery views %lu, rect %@, button %@ hidden %d; regions:", fg, NSStringFromClass([fg.window class]), DMEffectiveAlpha(fg), (unsigned long)views.count,
                NSStringFromCGRect(DMBattItemRect(fg, views)), NSStringFromCGRect(((UIView *)objc_getAssociatedObject(fg, kBattButtonKey)).frame), ((UIView *)objc_getAssociatedObject(fg, kBattButtonKey)).hidden];
            id regions = DMCall(fg.superview, @"regions");
            if ([regions isKindOfClass:[NSDictionary class]]) for (id rid in regions) {
                id list = DMCall(regions[rid], @"displayItems");
                [o appendFormat:@"\n    region %@ (%@):", rid, NSStringFromClass([list class])];
                if ([list conformsToProtocol:@protocol(NSFastEnumeration)]) for (id di in list) {
                    id it = DMCall(di, @"item"), v = DMCall(di, @"view"), iid = DMCall(di, @"identifier");
                    [o appendFormat:@" %@<%@ %@ %@>", iid, it ? NSStringFromClass([it class]) : @"-", v ? NSStringFromClass([v class]) : @"-",
                        [v isKindOfClass:[UIView class]] ? NSStringFromCGRect([(UIView *)v convertRect:((UIView *)v).bounds toView:fg]) : @"-"];
                }
            }
            NSMutableArray *todo = [NSMutableArray arrayWithArray:DMTrailingContainer(fg).subviews ?: @[]];
            [o appendString:@"\n    trailing:"];
            for (NSUInteger i = 0; i < todo.count && i < 40; i++) {
                UIView *v = todo[i];
                [o appendFormat:@" %@%@ %@ ax %d;", NSStringFromClass([v class]), glyph && [v isKindOfClass:glyph] ? @"(battery)" : @"", NSStringFromCGRect([v convertRect:v.bounds toView:fg]), v.isAccessibilityElement];
                [todo addObjectsFromArray:v.subviews];
            }
            break;
        }
        DMLog(o);
        return YES;
    }
    if ([cmd isEqualToString:@"battmenu_ax"]) {   // the bar's accessibility elements as VoiceOver gets them (labels and values only; read-only)
        for (UIView *fg in gCopies.allObjects) {
            if (!fg.window || fg.window.hidden || fg.bounds.size.width < 300.0 || DMEffectiveAlpha(fg) < 0.5) continue;
            NSMutableString *o = [NSMutableString stringWithFormat:@"[battmenu] accessibility of copy %p:", fg];
            NSMutableArray *todo = [NSMutableArray arrayWithObject:fg.superview ?: fg];
            for (NSUInteger i = 0; i < todo.count && i < 200; i++) {
                id e = todo[i];
                if ([e isAccessibilityElement]) [o appendFormat:@" [%@: %@ / %@]", NSStringFromClass([e class]), [e accessibilityLabel], [e accessibilityValue]];
                NSArray *kids = [e accessibilityElements];
                if (kids.count) [todo addObjectsFromArray:kids];
                else if ([e isKindOfClass:[UIView class]] && ![e isAccessibilityElement]) [todo addObjectsFromArray:((UIView *)e).subviews];
            }
            DMLog(o);
            break;
        }
        return YES;
    }
    return NO;
}
#endif
