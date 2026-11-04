// BatteryMenu.h -- the battery menu and the Control Center icon (2 Nov 2026, MacStatusBar&Dock 1.7.9 items 1-2), included into StatusBar.x.
// Settings > Status Bar > Battery Menu (pref batteryMenu, on unless switched off -- updaters too: DMBattApplyPref):
//  - the battery in the menu bar opens a Mac-style battery menu, to a finger or the pointer: our own button over iOS's battery item, its glyph and
//    its percentage (DMBattItemViews), so the status icons' region action -- Control Center, for a click -- is not run there (StatusBar.x
//    DMPointOverOurControl);
//  - a Control Center icon left of the clock (two switches, a Mac's; DMBattCCLayout) opens Control Center, as a click on the status icons does.
// Off: the battery is iOS's again (a click on it opens Control Center; a finger's tap there does nothing, as on a stock iPad) and there is no icon.
// The pull from the top-right edge opens Control Center either way (a system gesture, not the bar's). The menu, in a Mac's order: Battery with the
// level; the power source; what the Charge Limit's job does now; Low Power Mode, iPadOS's own, switched as Control Center's toggle switches it
// (DMBattSetLowPower); our battery settings -- Charge Limit and Charge to Full Now where the job is installed (common/ChargeLimit.h), Sleep Guard's
// state (common/SleepGuard.h) --; Battery Settings….
// Where the two items go and the job's words: common/BatteryMenu.h (plain C, tools/test-batterymenu.sh).
// Not in it: a Mac's "Using Significant Energy". iPadOS keeps the apps' energy only in powerlog's database (root's, summed per hour for Settings'
// Battery page); a live list from here would be a CPU sample called energy.

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

// ---- the battery: what the menu bar's own battery shows -- SpringBoard's SBUIController, -batteryCapacityAsPercentage, -isOnAC (the adapter
// powering the iPad now: not during the Charge Limit job's adapter cut) and -isBatteryCharging, its cached state, which the bar's battery item is
// drawn from (16.7.7, 17.5.1). Where those are not there with those types: IOKit's power sources (IOPSCopyPowerSourcesInfo), whose level is
// rounded another way -- 80 % there, 79 % in the bar and the battery service's CurrentCapacity (17.5.1, 2 Nov). Asked when the menu is built and
// read aloud, never on a timer of its own.
typedef struct { int percent; BOOL onAC, charging, known; } DMBattInfo;
static DMBattInfo DMBattNow(void) {
    DMBattInfo b = { -1, NO, NO, NO };
    id ui = DMSBManager("SBUIController");
    if (DMBattTypes(ui, @"batteryCapacityAsPercentage", "i16@0:8") && DMBattTypes(ui, @"isOnAC", "B16@0:8") && DMBattTypes(ui, @"isBatteryCharging", "B16@0:8")) {
        b.percent = ((int (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(@"batteryCapacityAsPercentage"));
        b.onAC = ((BOOL (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(@"isOnAC"));
        b.charging = ((BOOL (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(@"isBatteryCharging"));
        b.known = b.percent >= 0 && b.percent <= 100;
        if (b.known) return b;
    }
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
// Settings part takes to the page's row (common/BatteryHealthLink.h, macsettings/BatteryHealthLink.x). Battery Settings… opens Battery.
static void DMBattOpenSettings(NSString *group, NSString *why) { DMOpenURL(group ? MSBDBatteryHealthLink(group) : @"prefs:root=BATTERY_USAGE", why); }

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
- (CGFloat)dmRowHeight { return MSBDMenuRowScaled(gDMBarSize, kBattSwitchRowH); }
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
#if MSBD_BATT_CHARGE
    BOOL job = DMBattChargeJob();
    uint64_t word = job ? DMBattChargeWord() : 0;
    int limitPref = job ? DMBattChargeLimitPref() : kMSBDChargeLimitOff;
    char line[96] = "";
    if (job && MSBDBattChargeLine(word, b.percent, line, sizeof line)) [items addObject:[[DMBattInfoRow alloc] initWithText:@(line)]];
    [sig appendFormat:@"%d%s|", job, line];
#endif
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
    DMLog([NSString stringWithFormat:@"[battmenu] menu %@: %@", what, [rows componentsJoinedByString:@" | "]]);
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
    UIView *panel = DMMakePanel(items);
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
    btn.frame = DMBarRect(fg, rtl, CGRectMake(a, 0, b - a, fg.bounds.size.height));
    btn.hidden = NO;
    [fg bringSubviewToFront:btn];
    DMBattCoverAX(fg, views, YES);
}

// The Lock Screen's layout of a copy (StatusBar.x DMLayoutWithoutClock: only passive icons there): the battery is iOS's own -- no menu on the Lock
// Screen -- and the Control Center icon goes, as the Spotlight icon does; both come back with the unlocked look's layout.
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
        btn.frame = DMBarRect(fg, rtl, CGRectMake(side.ccBtnLead, 0, side.ccBtnTrail - side.ccBtnLead, fg.bounds.size.height));
        // (the highlight: the glyph and 5 pt at each side, the bar's height less 3 pt top and bottom -- a title pill's insets -- x Menu Bar Size)
        pill.frame = DMBarRect(fg, rtl, CGRectMake(side.ccLead - 5.0 * k, 3.0 * k, w + 10.0 * k, MAX(0.0, fg.bounds.size.height - 6.0 * k)));
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
        notify_register_dispatch("com.apple.system.powersources", &t, dispatch_get_main_queue(), ^(int tok) { DMBattMenuChanged(); });
        notify_register_dispatch(MSBD_SG_UPDATED, &t, dispatch_get_main_queue(), ^(int tok) { DMBattMenuChanged(); });
#if MSBD_BATT_CHARGE
        notify_register_dispatch(MSBD_CHARGE_STATE, &t, dispatch_get_main_queue(), ^(int tok) { DMBattMenuChanged(); });
#endif
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gBattMenuOn && gBattPanel) DMCloseOverlay();
        for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
    });
}

#if DEBUG
// ---- debug triggers (battmenu, battmenu_cc, battmenu_pref_<on|off>, battmenu_probe, battmenu_lpm_<0|1>, battmenu_lpmwatch, battmenu_word_<hex>,
// battmenu_size_<0|1|2>, battmenu_ax, battmenu_ccstack_<0|1>) ----
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
        [o appendFormat:@"\n  the menu's battery: known %d, %d%%, on AC %d, charging %d;", b.known, b.percent, b.onAC, b.charging];
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
