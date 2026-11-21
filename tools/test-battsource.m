// test-battsource.m -- see test-battsource.sh. Where the battery menu, the battery's VoiceOver value and the number in the icon read the battery
// (issue #15): the real code cut out of statusbar/BatteryMenu.h -- the battery's read (from its DMBattInfo to DMBattAXValue: bs-read.inc), the
// menu's rows and DMBattMenuItems (bs-rows.inc, bs-items.inc), the number in the icon (from gBattInsideOn to DMBattInsideApplyPref: bs-block.inc),
// why iPad is not charging (1.8.8.1 BATTWHY: its section, bs-why.inc, empty in a copy from before it)
// -- with common/BatteryMenu.h, common/ChargeLimit.h, common/ChargeWhy.h, common/BatteryInside.h and common/AXText.h, on stand-ins: the battery service (IOKit's
// matching and registry calls: AppleSmartBattery and/or AppleARMPMUCharger with their keys, an object that goes away), IOKit's power sources (the
// internal battery's description, through dlopen/dlsym as the code asks for it), SpringBoard's SBUIController (its stored state, in the iPad's
// types), the Charge Limit's job (installed, its state word), the clock (CACurrentMediaTime) and UIKit's own battery view in a bar. One scenario
// per process; built twice, release and DEBUG (the debug log of SBUIController's stopped feed).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <notify.h>
#include "AXText.h"
#include "BatteryInside.h"
#include "BatteryMenu.h"   // (common/: the job's words; ChargeLimit.h beside it, so MSBD_BATT_CHARGE is 1)
#if DEBUG
#define DEBUG_BUILD YES
#else
#define DEBUG_BUILD NO
#endif

static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; if (getenv("BS_LOG")) printf("   log: %s\n", s.UTF8String); }
static int LogCount(NSString *part) { int n = 0; for (NSString *l in gLog) if ([l rangeOfString:part].location != NSNotFound) n++; return n; }
static double gNow = 1000.0;
static CFTimeInterval TNow(void) { return gNow; }

// ---- the battery service: AppleSmartBattery (the SMC iPads) and/or AppleARMPMUCharger (the PMU iPads), each with its keys (nil: not there). An
// object handed out is the service as it is now (gGen); after TServiceGone it reads nothing, and a new lookup hands out another object.
static NSDictionary *gSmart, *gPMU;
static int gGen = 1, gLookups, gReads, gReleases;
static NSMutableDictionary<NSNumber *, NSArray *> *gObjs;
static io_service_t gNextObj = 100;
static CFMutableDictionaryRef TIOServiceMatching(const char *name) {
    CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFStringRef n = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
    CFDictionarySetValue(d, CFSTR("IOProviderClass"), n); CFRelease(n);
    return d;
}
static io_service_t TIOServiceGetMatchingService(mach_port_t port, CFDictionaryRef matching) {
    gLookups++;
    NSString *cls = [[(__bridge NSDictionary *)matching objectForKey:@"IOProviderClass"] copy];
    if (matching) CFRelease(matching);   // (IOKit consumes the matching dictionary)
    NSDictionary *p = [cls isEqualToString:@"AppleSmartBattery"] ? gSmart : [cls isEqualToString:@"AppleARMPMUCharger"] ? gPMU : nil;
    if (!p) return MACH_PORT_NULL;
    if (!gObjs) gObjs = [NSMutableDictionary dictionary];
    io_service_t o = gNextObj++;
    gObjs[@(o)] = @[cls, @(gGen)];
    return o;
}
static CFTypeRef TIORegistryEntryCreateCFProperty(io_registry_entry_t e, CFStringRef key, CFAllocatorRef a, IOOptionBits o) {
    gReads++;
    NSArray *rec = gObjs[@(e)];
    if (!rec || [rec[1] intValue] != gGen) return NULL;
    NSDictionary *p = [rec[0] isEqualToString:@"AppleSmartBattery"] ? gSmart : gPMU;
    id v = p[(__bridge NSString *)key];
    return v ? CFBridgingRetain(v) : NULL;
}
static kern_return_t TIOObjectRelease(io_object_t o) { gReleases++; return KERN_SUCCESS; }
static void TServiceGone(void) { gGen++; }   // (the driver went away and came back: every object handed out reads nothing now)

// ---- IOKit's power sources: the internal battery's description (nil: none)
static NSDictionary *gIOPS;
static CFTypeRef TCopyInfo(void) { return gIOPS ? CFBridgingRetain(@[gIOPS]) : NULL; }
static CFArrayRef TCopyList(CFTypeRef info) { return info ? (CFArrayRef)CFRetain(info) : NULL; }
static CFDictionaryRef TDescribe(CFTypeRef info, CFTypeRef ps) { return (CFDictionaryRef)ps; }
static void *TDlopen(const char *path, int mode) { return strstr(path ?: "", "IOKit") ? (void *)TCopyInfo : NULL; }
static void *TDlsym(void *h, const char *sym) {
    if (!strcmp(sym, "IOPSCopyPowerSourcesInfo")) return (void *)TCopyInfo;
    if (!strcmp(sym, "IOPSCopyPowerSourcesList")) return (void *)TCopyList;
    if (!strcmp(sym, "IOPSGetPowerSourceDescription")) return (void *)TDescribe;
    return NULL;
}

// ---- SpringBoard's SBUIController: its stored state, in the iPad's types (BOOL is 'B' there, 'c' on an Intel Mac)
static int gUIPercent = 43; static BOOL gUIOnAC = NO, gUICharging = NO, gUIThere = YES;
static int TUIPercent(id s, SEL c) { return gUIPercent; }
static BOOL TUIOnAC(id s, SEL c) { return gUIOnAC; }
static BOOL TUICharging(id s, SEL c) { return gUICharging; }
static int gUIAsked;
static id DMSBManager(const char *cls) {
    static id ui;
    if (!gUIThere || strcmp(cls, "SBUIController")) return nil;
    gUIAsked++;
    if (!ui) {
        Class c = objc_allocateClassPair([NSObject class], "TSBUIController", 0);
        class_addMethod(c, sel_registerName("batteryCapacityAsPercentage"), (IMP)TUIPercent, "i16@0:8");
        class_addMethod(c, sel_registerName("isOnAC"), (IMP)TUIOnAC, "B16@0:8");
        class_addMethod(c, sel_registerName("isBatteryCharging"), (IMP)TUICharging, "B16@0:8");
        objc_registerClassPair(c);
        ui = [c new];
    }
    return ui;
}

// ---- the menu's surroundings (StatusBar.x's row, the menu's size, Settings' links), Low Power Mode left out, Sleep Guard on, the job
@interface DMRow : UIControl
@property (nonatomic, copy) NSString *hint;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, copy) dispatch_block_t handler;
@property (nonatomic, strong) UILabel *label;
- (instancetype)initWithTitle:(NSString *)title enabled:(BOOL)enabled handler:(dispatch_block_t)handler;
- (void)refresh;
@end
@implementation DMRow
- (instancetype)initWithTitle:(NSString *)title enabled:(BOOL)enabled handler:(dispatch_block_t)handler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _label = [UILabel new]; _label.text = title; _hintLabel = [UILabel new]; _handler = [handler copy]; self.enabled = enabled;
    return self;
}
- (void)refresh {}
@end
static int DMMenuSize(void) { return 0; }
static CGFloat DMMenuTextPt(void) { return 14.0; }
static double MSBDMenuRowScaled(int size, double small) { return small; }
static const CGFloat kBattSwitchRowH = 34.0;
static dispatch_block_t DMCloseThen(dispatch_block_t action) { return action; }
static void DMBattOpenSettings(NSString *group, NSString *why) {}
#define MSBD_BH_CHARGING_GROUP "MSBD_CHARGING_GROUP"
#define MSBD_BH_BATTERY_USE_GROUP "MSBD_BATTERY_USE_GROUP"
typedef enum { kDMBattLPMNone = 0, kDMBattLPMCompletion, kDMBattLPMSource, kDMBattLPMSaver } DMBattLPMWay;
static DMBattLPMWay DMBattLPMHow(id *target, NSString **source) { return kDMBattLPMNone; }
static BOOL DMBattLowPowerOn(void) { return NO; }
static void DMBattSetLowPower(BOOL on) {}
static BOOL DMBattSleepGuardOn(void) { return YES; }
static NSString *DMBattCantSleep(void) { return nil; }
static BOOL gJob = NO; static uint64_t gWord = 0;
static BOOL DMBattChargeJob(void) { return gJob; }
static uint64_t DMBattChargeWord(void) { return gWord; }
static int DMBattChargeLimitPref(void) { return 80; }
static BOOL gBattMenuOn __attribute__((unused)) = YES;   // (StatusBar.x's: Battery Menu on -- the power sources note's stamps, DMBattWhyNote)

// ---- the number in the icon's surroundings (as test-battinsideink.m has them): the bar's batteries, our bars' keys, no battery item to add to
static NSHashTable *gCopies, *gAllBarCopies;
static const void *kTestBatteries = &kTestBatteries;
static NSArray<UIView *> *DMBattItemViews(UIView *fg) { return objc_getAssociatedObject(fg, kTestBatteries) ?: @[]; }
static const void *kLogoKey __attribute__((unused)) = &kLogoKey, *kHoldKey __attribute__((unused)) = &kHoldKey;
static const void *kNoClockLayoutKey __attribute__((unused)) = &kNoClockLayoutKey;
static id DMCall(id obj, NSString *name) __attribute__((unused));
static id DMCall(id obj, NSString *name) { SEL s = NSSelectorFromString(name); return obj && [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil; }
static void DMStockVPNRecheck(UIView *fg) __attribute__((unused));
static void DMStockVPNRecheck(UIView *fg) {}
#define DMTestFlag(path) 0
static Class DMBattItemClass(void) __attribute__((unused));
static Class DMBattItemClass(void) { return Nil; }
static uint32_t TRegister(const char *name, int *token, dispatch_queue_t q, notify_handler_t h) { if (token) *token = 1; return 0; }

#include "bs-types.inc"
#define IOServiceMatching TIOServiceMatching
#define IOServiceGetMatchingService TIOServiceGetMatchingService
#define IORegistryEntryCreateCFProperty TIORegistryEntryCreateCFProperty
#define IOObjectRelease TIOObjectRelease
#define dlopen TDlopen
#define dlsym TDlsym
#define CACurrentMediaTime TNow
#define notify_register_dispatch TRegister
#include "bs-read.inc"
#include "bs-why.inc"
#include "bs-rows.inc"
#include "bs-items.inc"
#include "bs-block.inc"
#undef notify_register_dispatch
#undef CACurrentMediaTime
#undef dlsym
#undef dlopen

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static void Same(NSString *got, NSString *want, NSString *what) {
    BOOL ok = (got == nil && want == nil) || [got isEqualToString:want];
    Check(ok, ok ? [NSString stringWithFormat:@"%@: %@", what, want ?: @"(none)"] : [NSString stringWithFormat:@"%@: \"%@\", expected \"%@\"", what, got ?: @"(none)", want ?: @"(none)"]);
}

// ---- the battery service's keys, IOKit's power sources' description ------------------------------------------------------------------------
static NSDictionary *Service(int cur, int max, BOOL ext, BOOL charging, BOOL raw) {
    return @{ @"CurrentCapacity": @(cur), @"MaxCapacity": @(max), @"ExternalConnected": ext ? @YES : @NO, @"IsCharging": charging ? @YES : @NO,
              @"AppleRawExternalConnected": raw ? @YES : @NO, @"FullyCharged": @NO, @"AdapterDetails": @{ @"Watts": @(raw ? 20 : 0) } };
}
static NSDictionary *PowerSource(int cur, BOOL ac, BOOL charging) {
    return @{ @"Type": @"InternalBattery", @"Current Capacity": @(cur), @"Max Capacity": @100, @"Power Source State": ac ? @"AC Power" : @"Battery Power",
              @"Is Charging": @(charging) };
}
static void SBUI(int percent, BOOL ac, BOOL charging) { gUIPercent = percent; gUIOnAC = ac; gUICharging = charging; }

// ---- what the user sees: the menu (its rows, as the debug log writes them), the battery's VoiceOver value, the number in the icon ------------
static NSString *Menu(void) {
    NSMutableArray *rows = [NSMutableArray array];
    for (id it in DMBattMenuItems(NULL)) {
        if (it == [NSNull null]) { [rows addObject:@"--"]; continue; }
        if (![it isKindOfClass:[DMRow class]]) { [rows addObject:NSStringFromClass([it class])]; continue; }
        DMRow *r = it;
        [rows addObject:r.hint.length ? [NSString stringWithFormat:@"%@ = %@", r.label.text, r.hint] : r.label.text];
    }
    return [rows componentsJoinedByString:@" | "];
}
static NSString *MenuRow(int i) { NSArray *rows = [Menu() componentsSeparatedByString:@" | "]; return i < (int)rows.count ? rows[i] : nil; }
// UIKit's own battery view in a bar; its two methods for the charging bolt in the iPad's types (as test-battinsideink.m makes them)
static Class BSiPadBools(Class c) {
    SEL set = sel_registerName("setShowsInlineChargingIndicator:"), get = sel_registerName("showsInlineChargingIndicator");
    const char *t = method_getTypeEncoding(class_getInstanceMethod(c, set));
    if (!t || strcmp(t, "v20@0:8c16")) return c;
    Class sub = objc_getClass("_UIBatteryView_iPadBOOL");
    if (sub) return sub;
    sub = objc_allocateClassPair(c, "_UIBatteryView_iPadBOOL", 0);
    class_addMethod(sub, set, method_getImplementation(class_getInstanceMethod(c, set)), "v20@0:8B16");
    class_addMethod(sub, get, method_getImplementation(class_getInstanceMethod(c, get)), "B16@0:8");
    objc_registerClassPair(sub);
    return sub;
}
static UIView *gBar, *gBattery;
static NSString *Icon(void) {   // (the bar's layout pass, the level read anew: our number's text, nil when none shows)
    if (!gBar) {
        gBattery = [[BSiPadBools(NSClassFromString(@"_UIBatteryView")) alloc] initWithFrame:CGRectZero];
        CGSize size = gBattery.intrinsicContentSize;
        gBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size.width + 4, size.height + 4)];
        gBattery.frame = CGRectMake(2, 2, size.width, size.height);
        [gBar addSubview:gBattery];
        objc_setAssociatedObject(gBar, kTestBatteries, @[gBattery], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gBattInsideOn = YES;   // (Battery Percentage in Icon on)
    }
    gBattInsideReadAt = -100;
    DMBattInsideBar(gBar);
    for (UIView *s in gBattery.subviews) if ([s isKindOfClass:[UILabel class]] && !s.hidden && ((UILabel *)s).text.length) return ((UILabel *)s).text;
    return nil;
}
// Everything the user sees, at once: the menu's level and source (and the job's line, if any), the VoiceOver value, the number in the icon.
static void Sees(NSString *step, NSString *level, NSString *source, NSString *jobLine, NSString *ax, NSString *icon) {
    printf("   %s\n", step.UTF8String);
    Same(MenuRow(0), level ? [@"Battery = " stringByAppendingString:level] : @"Battery", [step stringByAppendingString:@": the menu's heading"]);
    Same(MenuRow(1), [@"Power Source: " stringByAppendingString:source], [step stringByAppendingString:@": the menu's power source"]);
    if (gJob) Same(MenuRow(2), jobLine, [step stringByAppendingString:@": the job's line"]);
    Same(DMBattAXValue(), ax, [step stringByAppendingString:@": the battery's VoiceOver value"]);
    Same(Icon(), icon, [step stringByAppendingString:@": the number in the icon"]);
}

// ---- scenarios --------------------------------------------------------------------------------------------------------------------------------
static void Scenario(NSString *name) {
    BOOL debug = DEBUG_BUILD;
    if ([name isEqualToString:@"user"]) {   // issue #15: SBUIController's feed stopped at 43 % on battery; the battery at 47 % on the adapter, charging
        gSmart = Service(47, 100, YES, YES, YES); gIOPS = PowerSource(46, YES, YES); SBUI(43, NO, NO);
        Sees(@"plugged in, 47 % (SBUIController still 43 %, Battery)", @"47%", @"Power Adapter", nil, @"47%, Charging", @"47");
        gSmart = Service(48, 100, YES, YES, YES);
        Sees(@"a percent more (SBUIController still 43 %)", @"48%", @"Power Adapter", nil, @"48%, Charging", @"48");
        gSmart = Service(48, 100, NO, NO, NO);
        Sees(@"unplugged", @"48%", @"Battery", nil, @"48%", @"48");
        gSmart = Service(47, 100, YES, YES, YES);
        Sees(@"plugged in again, 47 %", @"47%", @"Power Adapter", nil, @"47%, Charging", @"47");
    } else if ([name isEqualToString:@"pmu"]) {   // the same on a PMU iPad (the iPad 2, the 17.5: AppleARMPMUCharger, no AppleSmartBattery)
        gPMU = Service(47, 100, YES, YES, YES); gIOPS = PowerSource(46, YES, YES); SBUI(43, NO, NO);
        Sees(@"PMU, plugged in, 47 % (SBUIController still 43 %, Battery)", @"47%", @"Power Adapter", nil, @"47%, Charging", @"47");
        gPMU = Service(52, 100, NO, NO, NO);
        Sees(@"PMU, unplugged at 52 %", @"52%", @"Battery", nil, @"52%", @"52");
    } else if ([name isEqualToString:@"rounding"]) {   // the level is the bar's own (CurrentCapacity), not the power sources' (17.5.1, 2 Nov: 79 / 80)
        gSmart = Service(79, 100, NO, NO, NO); gIOPS = PowerSource(80, NO, NO); SBUI(79, NO, NO);
        Sees(@"79 % in the service and the bar, 80 % in the power sources", @"79%", @"Battery", nil, @"79%", @"79");
    } else if ([name isEqualToString:@"scaled"]) {   // MaxCapacity not 100 (100 on all four iPads): the level scaled, to the nearest, at most 100
        gSmart = Service(3900, 8254, NO, NO, NO); gIOPS = PowerSource(40, NO, NO); SBUI(43, NO, NO);
        Sees(@"3900 of 8254 (47.25 %)", @"47%", @"Battery", nil, @"47%", @"47");
        gSmart = Service(3923, 8254, NO, NO, NO);
        Sees(@"3923 of 8254 (47.53 %)", @"48%", @"Battery", nil, @"48%", @"48");
        gSmart = Service(8300, 8254, YES, NO, YES);
        Sees(@"8300 of 8254 (over: the gauge's own)", @"100%", @"Power Adapter", nil, @"100%, Power Adapter", @"100");
    } else if ([name isEqualToString:@"flagnumber"]) {   // flags published as numbers are flags too; a level that is a flag is not a level
        gSmart = @{ @"CurrentCapacity": @47, @"MaxCapacity": @100, @"ExternalConnected": @1, @"IsCharging": @0 }; gIOPS = PowerSource(46, NO, NO); SBUI(43, NO, NO);
        Sees(@"ExternalConnected 1, IsCharging 0 as numbers", @"47%", @"Power Adapter", nil, @"47%, Power Adapter", @"47");
        gSmart = @{ @"CurrentCapacity": @YES, @"MaxCapacity": @100, @"ExternalConnected": @YES, @"IsCharging": @YES };
        Sees(@"CurrentCapacity a flag: not a level (iPadOS's power sources)", @"46%", @"Battery", nil, @"46%", @"46");
    } else if ([name isEqualToString:@"badtype"]) {   // a key not of its type: looked up once more, then iPadOS's power sources
        gSmart = @{ @"CurrentCapacity": @"47", @"MaxCapacity": @100, @"ExternalConnected": @YES, @"IsCharging": @YES }; gIOPS = PowerSource(46, YES, YES); SBUI(43, NO, NO);
        Sees(@"CurrentCapacity a string", @"46%", @"Power Adapter", nil, @"46%, Charging", @"46");
        int l = gLookups, r = gReleases;
        DMBattAXValue();
        Check(gLookups - l == 1 && gReleases - r == 1, [NSString stringWithFormat:@"a read that failed: the service looked up once more, the old object let go (%d lookup(s), %d release(s))", gLookups - l, gReleases - r]);
        gSmart = @{ @"CurrentCapacity": @47, @"MaxCapacity": @100, @"ExternalConnected": @"Yes", @"IsCharging": @YES };
        Sees(@"ExternalConnected a string", @"46%", @"Power Adapter", nil, @"46%, Charging", @"46");
        gSmart = @{ @"CurrentCapacity": @47, @"MaxCapacity": @100, @"ExternalConnected": @YES };
        Sees(@"IsCharging missing", @"46%", @"Power Adapter", nil, @"46%, Charging", @"46");
        gSmart = @{ @"CurrentCapacity": @(-1), @"MaxCapacity": @100, @"ExternalConnected": @NO, @"IsCharging": @NO };
        Sees(@"CurrentCapacity -1", @"46%", @"Power Adapter", nil, @"46%, Charging", @"46");
        gSmart = Service(47, 100, YES, YES, YES);
        Sees(@"the keys right again", @"47%", @"Power Adapter", nil, @"47%, Charging", @"47");
        int l2 = gLookups;
        DMBattAXValue(); DMBattAXValue();
        Check(gLookups == l2, [NSString stringWithFormat:@"a read that works: no new lookup (%d)", gLookups - l2]);
    } else if ([name isEqualToString:@"relookup"]) {   // the service went away and came back as another object: found again at once
        gSmart = Service(47, 100, YES, YES, YES); gIOPS = PowerSource(46, YES, YES); SBUI(43, NO, NO);
        Sees(@"47 %", @"47%", @"Power Adapter", nil, @"47%, Charging", @"47");
        TServiceGone(); gSmart = Service(49, 100, YES, YES, YES);
        int l = gLookups;
        Same(DMBattAXValue(), @"49%, Charging", @"the service is another object now: the battery's VoiceOver value");
        Check(gLookups - l == 1, [NSString stringWithFormat:@"  ... found again with one lookup (%d)", gLookups - l]);
        Sees(@"49 %", @"49%", @"Power Adapter", nil, @"49%, Charging", @"49");
    } else if ([name isEqualToString:@"noservice"]) {   // no battery service (or one SpringBoard may not read): iPadOS's power sources, not SBUIController
        gIOPS = PowerSource(46, YES, YES); SBUI(43, NO, NO);
        Sees(@"no service; power sources 46 % on AC", @"46%", @"Power Adapter", nil, @"46%, Charging", @"46");
        int l = gLookups;
        DMBattAXValue();
        Check(gLookups - l <= 2, [NSString stringWithFormat:@"  ... each read looks it up once more, no more (%d lookups: AppleSmartBattery, AppleARMPMUCharger)", gLookups - l]);
        Check(LogCount(@"[battmenu] the battery service: none found") == 1, [NSString stringWithFormat:@"  ... said once, not at each look (%d)", LogCount(@"[battmenu] the battery service: none found")]);
        gIOPS = PowerSource(45, NO, NO);
        Sees(@"no service; power sources 45 % on battery", @"45%", @"Battery", nil, @"45%", @"45");
    } else if ([name isEqualToString:@"iopsonly"]) {   // iPadOS's power sources only (no service, no SBUIController)
        gIOPS = PowerSource(46, YES, NO); gUIThere = NO;
        Sees(@"power sources only, 46 % on AC, not charging", @"46%", @"Power Adapter", nil, @"46%, Power Adapter", @"46");
    } else if ([name isEqualToString:@"sbuionly"]) {   // SBUIController only (no service, no power sources): today's read, as the last one
        SBUI(43, NO, NO);
        Sees(@"SBUIController only, 43 % on battery", @"43%", @"Battery", nil, @"43%", @"43");
        SBUI(44, YES, YES);
        Sees(@"SBUIController only, 44 % charging", @"44%", @"Power Adapter", nil, @"44%, Charging", @"44");
    } else if ([name isEqualToString:@"nothing"]) {   // nothing to read: no level, no value, no number
        gUIThere = NO;
        Sees(@"nothing readable", nil, @"Battery", nil, nil, nil);
    } else if ([name isEqualToString:@"hold"]) {   // the Charge Limit's hold at 80 % (SMC): the adapter powers the iPad, the battery does not charge
        gJob = YES; gWord = MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1);
        gSmart = Service(80, 100, YES, NO, YES); gIOPS = PowerSource(80, YES, NO); SBUI(80, YES, NO);
        Sees(@"SMC, our hold at 80 %", @"80%", @"Power Adapter", @"Charging On Hold at 80%", @"80%, Power Adapter", @"80");
        gWord = MSBDChargeStateWord(kMSBDChargeStateCharging, 80, 1);
        gSmart = Service(76, 100, YES, YES, YES); SBUI(76, YES, YES);
        Sees(@"SMC, charging to the limit", @"76%", @"Power Adapter", @"Charging to 80%", @"76%, Charging", @"76");
    } else if ([name isEqualToString:@"cutpmu"]) {   // the job's adapter cut on a PMU iPad: the cable in (AppleRawExternalConnected 1), ExternalConnected 0
        gJob = YES; gWord = MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1);
        gPMU = Service(90, 100, NO, NO, YES); gIOPS = PowerSource(90, NO, NO); SBUI(90, NO, NO);
        Sees(@"PMU, our cut (coming down from 90 %)", @"90%", @"Battery", @"Using Battery Until 80%", @"90%", @"90");
        gWord = MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1);
        gPMU = Service(80, 100, YES, NO, YES); gIOPS = PowerSource(80, YES, NO); SBUI(80, YES, NO);
        Sees(@"PMU, the cut ended at 80 %: our hold", @"80%", @"Power Adapter", @"Charging On Hold at 80%", @"80%, Power Adapter", @"80");
    } else if ([name isEqualToString:@"cutsmc"]) {   // the job's adapter cut on an SMC iPad: the cable read as out too
        gJob = YES; gWord = MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1);
        gSmart = Service(88, 100, NO, NO, NO); gIOPS = PowerSource(88, NO, NO); SBUI(88, NO, NO);
        Sees(@"SMC, our cut (coming down from 88 %)", @"88%", @"Battery", @"Using Battery Until 80%", @"88%", @"88");
    } else if ([name isEqualToString:@"why"]) {   // 1.8.8.1 BATTWHY: why iPad is not charging, read from the service the level is read from (one lookup)
        NSMutableDictionary *weak = [Service(45, 100, YES, NO, YES) mutableCopy];   // (KT's A12Z on 7 W: connected, not charging, the battery giving 800 mA)
        weak[@"Amperage"] = @(-800); weak[@"AdapterDetails"] = @{ @"Watts": @7 }; weak[@"ChargerData"] = @{ @"NotChargingReason": @0, @"ChargerInhibitReason": @0 }; weak[@"Temperature"] = @3000;
        gSmart = weak; gIOPS = PowerSource(45, YES, NO); SBUI(45, YES, YES);
        gNow = 1000;
        Same(MenuRow(2), @"--", @"on 7 W, not charging: nothing said in the first 3 minutes");
        gNow = 1181;
        Same(MenuRow(2), @"Not Charging: Power Adapter Too Weak (7 W)", @"  ... after 3 minutes: the reason, from the battery service's own readings");
        TServiceGone();
        int l = gLookups;
        Same(MenuRow(2), @"Not Charging: Power Adapter Too Weak (7 W)", @"the service went away and came back as another object: the reason read from the new one");
        Check(gLookups - l == 1, [NSString stringWithFormat:@"  ... one lookup for the level and the reason together (%d)", gLookups - l]);
        gSmart = Service(45, 100, NO, NO, NO);
        int r = gReads;
        Same(MenuRow(2), @"--", @"unplugged: no reason");
        Check(gReads - r == 4, [NSString stringWithFormat:@"  ... and off the adapter nothing read for it: the level's 4 keys only (%d reads)", gReads - r]);
        NSMutableDictionary *charging = [Service(46, 100, YES, YES, YES) mutableCopy]; charging[@"Amperage"] = @1500;
        gSmart = charging; r = gReads;
        Same(MenuRow(2), @"--", @"plugged in, charging: no reason");
        Check(gReads - r == 5, [NSString stringWithFormat:@"  ... and only the current read for it (%d reads: the level's 4 and Amperage)", gReads - r]);
        NSMutableDictionary *odd = [weak mutableCopy]; odd[@"CurrentCapacity"] = @"45";   // (the level's read fails: the power sources' level)
        gSmart = odd; gNow = 1400; Menu(); gNow = 1600; r = gReads;
        Same(MenuRow(2), @"Not Charging", @"the service's level not readable: after 3 minutes \"Not Charging\", never a reason from that service");
        Check(gReads - r == 2, [NSString stringWithFormat:@"  ... nothing read from it for the reason (%d reads: CurrentCapacity, once more after the second lookup)", gReads - r]);
    } else if ([name isEqualToString:@"apart"]) {   // (debug) SBUIController apart from the service for more than 60 s: said once, again after they agreed
        gSmart = Service(47, 100, YES, YES, YES); gIOPS = PowerSource(46, YES, YES); SBUI(43, NO, NO);
        NSString *line = @"SBUIController's stored battery has differed from the battery service";
        gNow = 1000; DMBattAXValue();
        gNow = 1030; DMBattAXValue();
        Check(LogCount(line) == 0, [NSString stringWithFormat:@"apart for 30 s: not said yet (%d)", LogCount(line)]);
        gNow = 1061; DMBattAXValue(); Menu();
        gNow = 1200; DMBattAXValue(); Icon();
        Check(LogCount(line) == (debug ? 1 : 0), [NSString stringWithFormat:@"apart for 61 s and 200 s: said %s (%d)", debug ? "once" : "never (a release build)", LogCount(line)]);
        if (debug) {
            NSString *said = nil; for (NSString *l in gLog) if ([l rangeOfString:line].location != NSNotFound) said = l;
            Check([said rangeOfString:@"43%, on AC 0, charging 0 there; 47%, on AC 1, charging 1 in the service"].location != NSNotFound, [NSString stringWithFormat:@"  ... with both: %@", said]);
            Check(LogCount(@"the battery read from the battery service (AppleSmartBattery)") == 1, @"where the battery is read from: said once");
        }
        gNow = 1300; SBUI(47, YES, YES); DMBattAXValue();
        gNow = 1400; SBUI(48, YES, YES); DMBattAXValue();
        gNow = 1430; DMBattAXValue();
        Check(LogCount(line) == (debug ? 1 : 0), @"agreed again, then apart for 30 s: nothing new");
        gNow = 1470; DMBattAXValue();
        Check(LogCount(line) == (debug ? 2 : 0), [NSString stringWithFormat:@"apart again for 70 s: said once more (%d)", LogCount(line)]);
        gIOPS = PowerSource(46, YES, YES); gSmart = nil; TServiceGone(); DMBattAXValue();
        if (debug) Check(LogCount(@"the battery read from iPadOS's power sources (the battery service: no service)") == 1, @"read from the power sources: said, with why");
        Same(DMBattAXValue(), @"46%, Charging", @"  ... and read from them");
    } else { printf("FAIL  no scenario %s\n", name.UTF8String); gFails++; }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSArray *all = @[@"user", @"pmu", @"rounding", @"scaled", @"flagnumber", @"badtype", @"relookup", @"noservice", @"iopsonly", @"sbuionly", @"nothing", @"hold", @"cutpmu", @"cutsmc", @"why", @"apart"];
        if (argc < 2 || !strcmp(argv[1], "list")) { for (NSString *s in all) printf("%s\n", s.UTF8String); return 0; }
        Scenario(@(argv[1]));
        if (gFails && getenv("BS_LOG") == NULL) for (NSString *l in gLog) printf("   log: %s\n", l.UTF8String);
        return gFails ? 1 : 0;
    }
}
