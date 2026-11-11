// Battery Health on iPad (MacStatusBar&Dock 1.7.8, plans/battery-charging.md): Apple's own Settings > Battery > Battery Health page, which
// iPadOS builds only on an iPhone, opened on iPad and given real figures. Same page, same strings, on 15, 16, 17 and 18.
//
// The page is all there on iPad, behind one question: BatteryUsageUI adds the Battery Health row only if +[PLModelingUtilities isiPhone] says
// yes, asked from -[BatteryUIController setUpBatteryHealthSpecifiers] (15 / 16) or -setUpBatteryHealthGroup (17 / 18) (read on 15.6.1, 16.7.7,
// 17.5.1, 18.5). It is answered "yes" only while one of those two runs, on the main thread -- nowhere else (iPadOS asks it all over Settings).
// Apple's page itself reads nothing on iPad: the maximum capacity getter answers -1 ("noBatteryData" on 18), the service state -1 ("unable to
// determine"), the battery check 0 and the performance-management state 0 (each a spinner instead of the page). They get ours (common/BatteryHealthFigures.h): Maximum Capacity from the battery service's
// NominalChargeCapacity / DesignCapacity, the normal state and a checked battery once there is a figure. Only when Apple's own answer is
// missing: an iPad that one day gets Apple's figures keeps Apple's.
// Left out, as they are iPhone features that do nothing on iPad: Peak Performance Capability (performance management) and Apple's Optimized
// Battery Charging switch (PowerUI runs its "unsupported" manager on iPad: +[PowerUISmartChargeUtilities isOBCSupported] is [self isiPhone]) --
// on 17 / 18 its charging options group and Clean Energy Charging. Added: a Cycle Count row (the battery service's CycleCount) under Maximum
// Capacity, on every version; and the header says what Apple's iPad page says there (MSBHSetHeaderText), not its iPhone text. And, where the
// Charge Limit's job is installed (chargehelper/), our Charging group in Peak Performance's place, right under Maximum Capacity and Cycle Count:
// Charge Limit (Off, 80, 85, 90, 95 %), Run on Power Adapter (off unless set), Charge to Full Now while it holds the battery below full, and a
// footer saying what it does now.
// With another tweak that opens this page all of this is installed too, and the page is ours (KT, 1.7.9: ours is the default even with another
// battery health tweak). The two read on KT's iPads (plans/battery-charging.md, section 1) hook some of the same methods without a row of their
// own on the page: PoomSmart's Battery Health Enabler 1.0.0 rebuilds the 15 / 16 row builder as Apple's (one group, one Battery Health row) and
// Brend0n's BatteryHealthEnabler 0.0.1 answers isiPhone "yes" inside BatteryUsageUI, so either way the one builder makes the one row, whichever
// hook runs first (ours only lets that builder ask), and their state getters answer what ours answer once there is a figure (service state 0,
// performance management 2, PoomSmart's battery check 1). Ours alone: Maximum Capacity, Cycle Count, the iPad header text, Peak Performance and
// Optimized Battery Charging left out (PoomSmart's greyed switch goes with Apple's group), our Charging group in Peak Performance's place
// and our groups after them (BatteryUse.x).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <unistd.h>
#import <os/lock.h>
#import <notify.h>
#import "../common/BatteryHealthFigures.h"
#import "../common/ChargeLimit.h"

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithID:(NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
- (void)setButtonAction:(SEL)action;
@end
@interface UIViewController (MSBHPage)
- (void)reloadSpecifiers;
@end

enum { kMSBHCellLinkList = 2, kMSBHCellTitleValue = 4, kMSBHCellSwitch = 6, kMSBHCellButton = 13 };

static void MSBHLog(NSString *line) {   // (debug builds only, with /tmp/macsettings-debug: release builds write no /tmp log)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a");
    if (!f) return;
    fprintf(f, "batteryhealth: %s\n", line.UTF8String);
    fclose(f);
#endif
}

// ---- the figures, read from the battery service (a fresh read at most every 20 s: the page asks several getters per build)
typedef struct { int percent; int cycles; } MSBHFigures;
static int MSBHInt(NSDictionary *d, NSString *key) {
    id v = d[key];
    return [v isKindOfClass:[NSNumber class]] ? [v intValue] : -1;
}
static MSBHFigures MSBHReadFigures(void) {
    MSBHFigures f = { -1, -1 };
    static void *iokit;
    if (!iokit) iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    CFMutableDictionaryRef (*matching)(const char *) = iokit ? (CFMutableDictionaryRef (*)(const char *))dlsym(iokit, "IOServiceMatching") : NULL;
    unsigned int (*service)(unsigned int, CFDictionaryRef) = iokit ? (unsigned int (*)(unsigned int, CFDictionaryRef))dlsym(iokit, "IOServiceGetMatchingService") : NULL;
    int (*props)(unsigned int, CFMutableDictionaryRef *, CFAllocatorRef, unsigned int) = iokit ? (int (*)(unsigned int, CFMutableDictionaryRef *, CFAllocatorRef, unsigned int))dlsym(iokit, "IORegistryEntryCreateCFProperties") : NULL;
    int (*release)(unsigned int) = iokit ? (int (*)(unsigned int))dlsym(iokit, "IOObjectRelease") : NULL;
    if (!matching || !service || !props || !release) return f;
    // the battery: AppleSmartBattery on the SMC iPads (M1, A12Z), AppleARMPMUCharger on the PMU ones (A9X, A10X); any other power source last
    const char *classes[] = { "AppleSmartBattery", "AppleARMPMUCharger", "IOPMPowerSource" };
    for (size_t i = 0; i < sizeof classes / sizeof *classes; i++) {
        unsigned int s = service(0, matching(classes[i]));   // (the matching dictionary is consumed)
        if (!s) continue;
        CFMutableDictionaryRef p = NULL;
        props(s, &p, kCFAllocatorDefault, 0);
        release(s);
        NSDictionary *d = (__bridge_transfer NSDictionary *)p;
        if (![d isKindOfClass:[NSDictionary class]] || !d[@"DesignCapacity"]) continue;
        NSDictionary *bd = [d[@"BatteryData"] isKindOfClass:[NSDictionary class]] ? d[@"BatteryData"] : nil;
        int design = MSBHInt(d, @"DesignCapacity"); if (design <= 0) design = MSBHInt(bd, @"DesignCapacity");
        f.percent = MSBDBatteryHealthPercent(MSBHInt(d, @"NominalChargeCapacity"), MSBHInt(d, @"AppleRawMaxCapacity"), design);
        f.cycles = MSBHInt(d, @"CycleCount"); if (f.cycles < 0) f.cycles = MSBHInt(bd, @"CycleCount");
        break;
    }
    return f;
}
static MSBHFigures MSBHFiguresNow(void) {
    static MSBHFigures last = { -1, -1 }; static CFAbsoluteTime at;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (!at || now - at > 20 || now < at) { last = MSBHReadFigures(); at = now; }
    return last;
}

// ---- the row on the Battery page: isiPhone answered "yes" only while BatteryUsageUI builds that row
static int gMSBHGateDepth;
%group MSBHGate15
%hook BatteryUIController
- (id)setUpBatteryHealthSpecifiers {
    gMSBHGateDepth++;
    id r = %orig;
    gMSBHGateDepth--;
    return r;
}
%end
%end
%group MSBHGate17
%hook BatteryUIController
- (id)setUpBatteryHealthGroup {
    gMSBHGateDepth++;
    id r = %orig;
    gMSBHGateDepth--;
    return r;
}
%end
%end
%group MSBHIsPhone
%hook PLModelingUtilities
+ (BOOL)isiPhone {
    return gMSBHGateDepth > 0 && [NSThread isMainThread] ? YES : %orig;
}
%end
%end

// ---- Apple's own strings from the page's table (BatteryUI), nil where this iPadOS has none
static NSString *MSBHString(Class page, NSString *key) {
    NSString *none = @"\u2063msbd-none";
    NSString *v = [[NSBundle bundleForClass:page] localizedStringForKey:key value:none table:@"BatteryUI"];
    return v.length && ![v isEqualToString:none] && ![v isEqualToString:key] ? v : nil;
}
// The page's header text is an iPhone one: 15 / 16 "Phone batteries, like all rechargeable batteries, ..." (ABOUT_BATTERIES_TEXT), and 17 / 18 ask
// for an iPad variant their tables do not have (ABOUT_BATTERIES_TEXT_IPAD, shown as that key, read on 17.5.1 and 18.5). On iPad it says what
// Apple's iPad page says in that place: "This iPad battery is performing as expected." (BATTERY_HEALTH_STATE_FOOTER_NORMAL_IPAD, 17 / 18; under
// 80 % its "Battery service may be covered by warranty."), in the user's language where the table has it, English on 15 / 16 -- with Apple's own
// "Learn more…" link, its place recomputed.
static void MSBHSetHeaderText(id specs, Class page) {
    NSString *const *titleKey = (NSString *const *)dlsym(RTLD_DEFAULT, "PSFooterHyperlinkViewTitleKey");
    NSString *const *rangeKey = (NSString *const *)dlsym(RTLD_DEFAULT, "PSFooterHyperlinkViewLinkRangeKey");
    if (!titleKey || !rangeKey || !*titleKey || !*rangeKey) return;
    int percent = MSBHFiguresNow().percent;
    if (percent < 0) return;   // (no figure: Apple's page as it is)
    BOOL normal = percent >= 80;
    NSString *fmt = MSBHString(page, normal ? @"BATTERY_HEALTH_STATE_FOOTER_NORMAL_IPAD" : @"BATTERY_HEALTH_STATE_FOOTER_SERVICE");
    if (!fmt || [fmt componentsSeparatedByString:@"%@"].count != 2)
        fmt = normal ? @"This iPad battery is performing as expected. %@" : @"Battery service may be covered by warranty. %@";
    NSString *link = MSBHString(page, @"ABOUT_BATTERIES_LINK") ?: @"Learn more…";
    NSString *text = [fmt stringByReplacingOccurrencesOfString:@"%@" withString:link];
    for (PSSpecifier *s in [specs isKindOfClass:[NSArray class]] ? specs : (specs ? @[specs] : @[])) {
        if (![s respondsToSelector:@selector(propertyForKey:)] || ![[s propertyForKey:*titleKey] isKindOfClass:[NSString class]]) continue;
        [s setProperty:text forKey:*titleKey];
        NSRange r = [text rangeOfString:link];
        if (r.location != NSNotFound) [s setProperty:NSStringFromRange(r) forKey:*rangeKey];   // (a string: PSFooterHyperlinkView reads it with NSRangeFromString)
    }
}

// ---- our Charging group (common/ChargeLimit.h): only where the Charge Limit's job is installed. Its row is a stock list of Apple's own kind
// (PSListItemsController), read and written by Apple's page itself through our domain, which posts the job's settings notification.
#define kMSBHChargeJob "/var/jb/usr/libexec/msbdcharge"
static __weak UIViewController *gMSBHChargingPage;   // the page showing the group: rebuilt when the job's state changes
static BOOL gMSBHChargingStale;                      // ... or when it comes back into view, if the state changed while it was covered
static uint64_t MSBHChargeWord(void) {
    int t = 0; uint64_t w = 0;
    if (notify_register_check(MSBD_CHARGE_STATE, &t) == NOTIFY_STATUS_OK) { notify_get_state(t, &w); notify_cancel(t); }
    return w;
}
static int MSBHChargeLimitPref(void) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR(MSBD_CHARGE_LIMIT_KEY), CFSTR(MSBD_CHARGE_DOMAIN));
    int n = kMSBDChargeLimitOff;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n);
    if (v) CFRelease(v);
    return n;
}
static BOOL MSBHChargeComeDownPref(void) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR(MSBD_CHARGE_COMEDOWN_KEY), CFSTR(MSBD_CHARGE_DOMAIN));
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue((CFBooleanRef)v) : kMSBDChargeComeDownDefault;
    if (v) CFRelease(v);
    return on;
}
static BOOL MSBHChargeAdapterPref(void) {   // (Run on Power Adapter: missing = off)
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR(MSBD_CHARGE_ADAPTER_KEY), CFSTR(MSBD_CHARGE_DOMAIN));
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)v);
    if (v) CFRelease(v);
    return on;
}
static NSArray *MSBHChargingSpecifiers(UIViewController *page) {
    if (access(kMSBHChargeJob, X_OK) != 0) return @[];
    gMSBHChargingPage = page; gMSBHChargingStale = NO;
    uint64_t w = MSBHChargeWord();
    int pref = MSBHChargeLimitPref();
    char text[600]; MSBDChargeFooterText(w, pref, MSBHChargeComeDownPref(), MSBHChargeAdapterPref(), text, sizeof text);
    PSSpecifier *g = [PSSpecifier groupSpecifierWithID:@"MSBD_CHARGING_GROUP"];   // (later rows of ours about charging and sleep join this group)
    [g setProperty:[NSString stringWithUTF8String:text] forKey:@"footerText"];
    PSSpecifier *limit = [PSSpecifier preferenceSpecifierNamed:@"Charge Limit" target:page set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
                                                        detail:NSClassFromString(@"PSListItemsController") cell:kMSBHCellLinkList edit:Nil];
    [limit setProperty:@MSBD_CHARGE_LIMIT_KEY forKey:@"key"];
    [limit setProperty:@MSBD_CHARGE_DOMAIN forKey:@"defaults"];
    [limit setProperty:@(kMSBDChargeLimitOff) forKey:@"default"];
    [limit setProperty:@MSBD_CHARGE_PREFS_CHANGED forKey:@"PostNotification"];
    NSArray *titles = @[@"Off", @"80%", @"85%", @"90%", @"95%"];
    [limit setValues:@[@(kMSBDChargeLimitOff), @80, @85, @90, @95] titles:titles shortTitles:titles];
    [limit setIdentifier:@"MSBD_CHARGE_LIMIT"];
    // Run on Power Adapter (common/ChargeLimit.h MSBDChargeAdapterLimit): a stock switch, read and written by Apple's page through our domain like
    // the limit's row; off unless set
    PSSpecifier *adapter = [PSSpecifier preferenceSpecifierNamed:@"Run on Power Adapter" target:page set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
                                                          detail:Nil cell:kMSBHCellSwitch edit:Nil];
    [adapter setProperty:@MSBD_CHARGE_ADAPTER_KEY forKey:@"key"];
    [adapter setProperty:@MSBD_CHARGE_DOMAIN forKey:@"defaults"];
    [adapter setProperty:@NO forKey:@"default"];
    [adapter setProperty:@MSBD_CHARGE_PREFS_CHANGED forKey:@"PostNotification"];
    [adapter setIdentifier:@"MSBD_CHARGE_RUN_ON_ADAPTER"];
    NSMutableArray *specs = [NSMutableArray arrayWithObjects:g, limit, adapter, nil];
    if (MSBDChargeOffersFullNow(w, pref)) {
        PSSpecifier *full = [PSSpecifier preferenceSpecifierNamed:@"Charge to Full Now" target:page set:NULL get:NULL detail:Nil cell:kMSBHCellButton edit:Nil];
        [full setButtonAction:sel_registerName("msbdChargeToFullNow:")];
        [full setIdentifier:@"MSBD_CHARGE_FULL_NOW"];
        [specs addObject:full];
    }
    return specs;
}
static void MSBHChargeToFullNow(id self, SEL _cmd, id specifier) {
    notify_post(MSBD_CHARGE_FULL_NOW);
    MSBHLog(@"Charge to Full Now");
}
static void MSBHChargingChanged(void) {   // (the job's state word or our setting changed)
    UIViewController *page = gMSBHChargingPage;
    if (!page) return;
    if (page.isViewLoaded && page.view.window) [page reloadSpecifiers];
    else gMSBHChargingStale = YES;
}

// ---- the page's data: ours only where Apple's is missing
// (debug builds, with /tmp/macsettings-debug: Apple's own answer and ours, each time either changes -- how each iPadOS answers on iPad)
static int MSBHAnswer(NSString *what, int apple, int ours) {
#if DEBUG
    static NSMutableDictionary *last; static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    NSString *now = [NSString stringWithFormat:@"%d -> %d", apple, ours];
    os_unfair_lock_lock(&lock);
    if (!last) last = [NSMutableDictionary dictionary];
    BOOL changed = ![last[what] isEqualToString:now];
    last[what] = now;
    os_unfair_lock_unlock(&lock);
    if (changed) MSBHLog([NSString stringWithFormat:@"%@: Apple's %@ (ours)", what, now]);
#endif
    return ours;
}
%group MSBHData
%hook BatteryUIResourceClass
+ (int)getBatteryHealthServiceState {
    int apple = %orig;
    return MSBHAnswer(@"service state", apple, MSBDBatteryHealthServiceState(apple, MSBHFiguresNow().percent));
}
+ (int)genuineBatteryStatus {
    int apple = %orig;
    return MSBHAnswer(@"battery check", apple, MSBDBatteryGenuineStatus(apple, MSBHFiguresNow().percent));
}
+ (int)getManagementState {
    int apple = %orig;
    return MSBHAnswer(@"management state", apple, MSBDBatteryManagementState(apple, MSBHFiguresNow().percent));
}
%end
%hook BatteryHealthUIController
- (id)aboutBatteriesGroupSpecifier {
    id r = %orig;
    MSBHSetHeaderText(r, [(id)self class]);
    return r;
}
- (id)peakPowerCapacityGroupSpecifier {   // (performance management, an iPhone feature: our Charging group instead, where the job is installed)
    return MSBHChargingSpecifiers((UIViewController *)self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (gMSBHChargingStale && gMSBHChargingPage == (UIViewController *)self) { gMSBHChargingStale = NO; [(UIViewController *)self reloadSpecifiers]; }
}
- (id)chargeCapacityGroupSpecifier {
    id r = %orig;
    int cycles = MSBHFiguresNow().cycles;
    if (cycles < 0 || ![r isKindOfClass:[NSArray class]]) return r;
    PSSpecifier *g = [PSSpecifier groupSpecifierWithID:@"MSBD_CYCLE_COUNT_GROUP"];
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:MSBHString([(id)self class], @"CYCLE_COUNT_TITLE") ?: @"Cycle Count" target:self set:NULL get:NSSelectorFromString(@"msbdCycleCount:") detail:Nil
                                                         cell:kMSBHCellTitleValue edit:Nil];
    [row setIdentifier:@"MSBD_CYCLE_COUNT"];
    return [r arrayByAddingObjectsFromArray:@[g, row]];
}
%end
%end
%group MSBHCapacity   // 15 - 17
%hook BatteryUIResourceClass
+ (int)getBatteryMaximumCapacityPercent {
    int apple = %orig;
    if (apple >= 0) return apple;
    int ours = MSBHFiguresNow().percent;
    return ours >= 0 ? ours : apple;
}
%end
%end
%group MSBHCapacity18
%hook BatteryUIResourceClass
+ (int)getBatteryMaximumCapacityPercentWithError:(NSError **)error {
    int apple = %orig;
    if (apple >= 0) return apple;
    int ours = MSBHFiguresNow().percent;
    if (ours < 0) return apple;
    if (error) *error = nil;
    return ours;
}
%end
%end
%group MSBHQMax   // 17 / 18: "the maximum capacity is being estimated" footer, while Apple's gauge has no Qmax -- ours is a figure
%hook BatteryUIResourceClass
+ (BOOL)isQMaxUnknown {
    return MSBHFiguresNow().percent >= 0 ? NO : %orig;
}
%end
%end
%group MSBHNoSmartCharging15   // 15 / 16: the Optimized Battery Charging switch
%hook BatteryHealthUIController
- (id)smartChargingGroupSpecifier {
    return @[];
}
%end
%end
%group MSBHNoSmartCharging17   // 17 / 18: the charging options (Optimized Battery Charging, the iPhone 15's limits)
%hook BatteryHealthUIController
- (id)setUpChargingOptionsSpecifiers {
    return @[];
}
%end
%end
%group MSBHNoCleanEnergy   // 17 / 18: Clean Energy Charging (PowerUI's, iPhone only)
%hook BatteryHealthUIController
- (id)cleanEnergyChargingGroupSpecifier {
    return @[];
}
%end
%end

static NSString *MSBHCycleCountValue(id self, SEL _cmd, id specifier) {
    int cycles = MSBHFiguresNow().cycles;
    return cycles >= 0 ? [NSNumberFormatter localizedStringFromNumber:@(cycles) numberStyle:NSNumberFormatterDecimalStyle] : @"";
}

static BOOL MSBHHas(Class c, BOOL meta, const char *sel) {
    return c && (meta ? class_getClassMethod(c, sel_registerName(sel)) : class_getInstanceMethod(c, sel_registerName(sel))) != NULL;
}
// BatteryUsageUI.bundle is loaded when the Battery page is first opened: the hooks go in as soon as it is (NSBundle's load notification comes
// right after its classes are registered and before the page is made, so the first Battery page already has the row).
// What the check below decided (1.7.9, for the Settings search: common/OwnPageState.h): 0 not yet (Apple's battery pages not loaded in this
// process), 1 Apple's page left as it is -- no Battery Health on iPad, so our groups are not there --, 2 the page is ours.
static int gMSBHVerdict = 0;
__attribute__((visibility("hidden"))) int MSBHPageVerdict(void) { return gMSBHVerdict; }   // (TweakSearch.x)
static void MSBHTryInit(void) {
    static BOOL done; if (done) return;
    Class page = objc_getClass("BatteryUIController"), health = objc_getClass("BatteryHealthUIController"), resource = objc_getClass("BatteryUIResourceClass");
    Class modeling = objc_getClass("PLModelingUtilities");
    if (!page || !health || !resource || !modeling) return;
    done = YES;
    BOOL gate15 = MSBHHas(page, NO, "setUpBatteryHealthSpecifiers"), gate17 = MSBHHas(page, NO, "setUpBatteryHealthGroup");
    if ((!gate15 && !gate17) || !MSBHHas(modeling, YES, "isiPhone")) { gMSBHVerdict = 1; MSBHLog(@"no row builder or isiPhone: Apple's page untouched"); return; }   // (a page we do not know)
    gMSBHVerdict = 2;
    class_addMethod(health, sel_registerName("msbdCycleCount:"), (IMP)MSBHCycleCountValue, "@24@0:8@16");
    class_addMethod(health, sel_registerName("msbdChargeToFullNow:"), (IMP)MSBHChargeToFullNow, "v24@0:8@16");
    if (access(kMSBHChargeJob, X_OK) == 0) {   // (the group follows the job's state and our setting while it is shown)
        int t1 = 0, t2 = 0;
        notify_register_dispatch(MSBD_CHARGE_STATE, &t1, dispatch_get_main_queue(), ^(int t) { MSBHChargingChanged(); });
        notify_register_dispatch(MSBD_CHARGE_PREFS_CHANGED, &t2, dispatch_get_main_queue(), ^(int t) { MSBHChargingChanged(); });
    }
    if (gate15) %init(MSBHGate15); else %init(MSBHGate17);
    %init(MSBHIsPhone);
    if (MSBHHas(resource, YES, "getBatteryHealthServiceState") && MSBHHas(resource, YES, "genuineBatteryStatus") && MSBHHas(resource, YES, "getManagementState")
        && MSBHHas(health, NO, "aboutBatteriesGroupSpecifier") && MSBHHas(health, NO, "peakPowerCapacityGroupSpecifier")
        && MSBHHas(health, NO, "chargeCapacityGroupSpecifier"))
        %init(MSBHData);
    if (MSBHHas(resource, YES, "getBatteryMaximumCapacityPercent")) %init(MSBHCapacity);
    else if (MSBHHas(resource, YES, "getBatteryMaximumCapacityPercentWithError:")) %init(MSBHCapacity18);
    if (MSBHHas(resource, YES, "isQMaxUnknown")) %init(MSBHQMax);
    if (MSBHHas(health, NO, "setUpChargingOptionsSpecifiers")) %init(MSBHNoSmartCharging17);
    else if (MSBHHas(health, NO, "smartChargingGroupSpecifier")) %init(MSBHNoSmartCharging15);
    if (MSBHHas(health, NO, "cleanEnergyChargingGroupSpecifier")) %init(MSBHNoCleanEnergy);
    MSBHFigures f = MSBHFiguresNow();
    MSBHLog([NSString stringWithFormat:@"installed (row builder %@, capacity getter %@, Apple's charging group %@, our Charging group %@): Maximum Capacity %d %%, Cycle Count %d",
             gate15 ? @"15/16" : @"17/18", MSBHHas(resource, YES, "getBatteryMaximumCapacityPercent") ? @"15-17" : @"18", MSBHHas(health, NO, "setUpChargingOptionsSpecifiers") ? @"17/18" : @"15/16",
             access(kMSBHChargeJob, X_OK) == 0 ? @"yes" : @"no (no job)", f.percent, f.cycles]);
}
static void MSBHBundleLoaded(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) {
    MSBHTryInit();
}
static void MSBHImageAdded(const struct mach_header *mh, intptr_t slide) {   // (a load that is not NSBundle's: not inside the dyld callback itself)
    static BOOL queued; if (queued || !objc_getClass("BatteryHealthUIController")) return;
    queued = YES; dispatch_async(dispatch_get_main_queue(), ^{ MSBHTryInit(); });
}
%ctor {
    MSBHTryInit();
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, MSBHBundleLoaded, (__bridge CFStringRef)NSBundleDidLoadNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    _dyld_register_func_for_add_image(MSBHImageAdded);
}
