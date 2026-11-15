// test-battinsideone.m -- see test-battinsideone.sh. Battery Percentage in Icon with one switch (1.8.7.4 round 2, KT 14 Nov: "currently I have
// to toggle it on first and then turn off the battery percentage in the battery settings"). The real code, cut out of statusbar/BatteryMenu.h
// (the number's whole block, gBattInsideOn .. DMBattInsideApplyPref, and DMBattItemClass / DMBattViewShown / DMBattItemViews) with
// common/BatteryInside.h, and StatusBar.x's DMCall and DMStockVPNRecheck, run on stand-ins of iPadOS's bar as read in 17.6.1's and 18.2's
// SystemStatusUI (15.5's and 16.4's UIKit: the same methods):
//  - the bar (_UIStatusBar, 17+ STUIStatusBar): -_updateWithAggregatedData: runs each display item's state as STUIStatusBarDisplayItemState
//    -updateWithData:styleAttributes: does: its data enability from [item canEnableDisplayItem:fromData:], then the item's -_applyUpdate:
//    (enabled set when the enability changed, the item's -applyUpdate:, off again if the update says so); then its region lays out the enabled
//    display items from the trailing edge (Wi-Fi, iPadOS's percentage, the battery: an iPad's order) and takes the others' views out; a bar of ours
//    is then laid out by us (DMBattInsideBar, as StatusBar.x's layout pass does). A display item turned off keeps its place while its removal
//    animation runs (the state says enabled while it has running animations, as read); when that ends the region closes up on its own, with
//    no layout of ours (Settle); a copy without its clock (on the Lock Screen, or Control Center's header copy with iPadOS's own Control Center)
//    is laid out by StatusBar.x's own no-clock layout (the real branch of -dm_layoutLogoBody, one-noclock.inc, with BatteryMenu.h's real
//    DMBattLockLayout inside a stand-in DMLayoutWithoutClock), held, checked and released or given up by StatusBar.x's real hold
//    (DMHoldStatusBarCopy, DMCopyHasStockText, DMHoldSafetyCheck, DMReleaseStatusBarCopy: one-hold.inc) on a foreground view whose layout pass is
//    the -layoutSubviews hook's (held, laid out, released when ours);
//  - the base item (_UIStatusBarItem): -canEnableDisplayItem:fromData: in the iPad's types (B32@0:8@16@24), YES if one of its data entries is on;
//  - the battery item (_UIStatusBarBatteryItem): +percentDisplayIdentifier, no -canEnableDisplayItem:fromData: of its own, and -applyUpdate:
//    turning the percentage off when iPadOS's setting is off (the entry's prominentlyShowsDetailString), else giving it the entry's text.
// UIKit's own pieces where this Mac has them: _UIBatteryView (the icon, our number drawn on it), _UIStatusBarStringView (the percentage, a
// UILabel, in a region: a plain UIView in the foreground view, as the hold's text test reads them), _UIStatusBarData and
// _UIStatusBarDataBatteryEntry (the data: Battery Percentage, Low Power Mode, the level). BO_SB_X: another StatusBar.x (the code before).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#include "BatteryInside.h"

#ifdef T_STUI   // (17+: SystemStatusUI's names, DMSBUseSTUI)
#define TItem STUIStatusBarItem
#define TBatteryItem STUIStatusBarBatteryItem
#define TBar STUIStatusBar
static BOOL gSTUI = YES;
#else
#define TItem _UIStatusBarItem
#define TBatteryItem _UIStatusBarBatteryItem
#define TBar _UIStatusBar
static BOOL gSTUI = NO;
#endif

// ---- what the cut code needs ---------------------------------------------------------------------------------------------------------------
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static BOOL DMSBUseSTUI(void) { return gSTUI; }
static Class DMSBClass(const char *name) { return objc_getClass(gSTUI && !strcmp(name, "_UIStatusBar") ? "STUIStatusBar" : name); }
static UIView *DMTrailingContainer(UIView *fg) { return nil; }
static const void *kLogoKey __attribute__((unused)) = &kLogoKey, *kHoldKey __attribute__((unused)) = &kHoldKey;
static const void *kNoClockLayoutKey __attribute__((unused)) = &kNoClockLayoutKey;   // (StatusBar.x: our Lock Screen layout is on the copy)
static NSHashTable *gCopies, *gAllBarCopies;
static BOOL gKill __attribute__((unused));   // (the kill switch's file, /tmp/msb-stockbattpercent)
#define DMTestFlag(path) (gKill && !strcmp((path), "/tmp/msb-stockbattpercent"))
#include "one-call.inc"
#include "one-recheck.inc"
#include "one-types.inc"
#include "one-info.inc"
static DMBattInfo gFake = { 80, NO, NO, YES };
static DMBattInfo DMBattNow(void) { return gFake; }
#include "one-views.inc"
static uint32_t BORegister(const char *name, int *token, dispatch_queue_t q, notify_handler_t h) { if (token) *token = 1; return 0; }
#define notify_register_dispatch BORegister
#include "one-block.inc"
#undef notify_register_dispatch

// ---- StatusBar.x's no-clock layout and hold, as built (one-noclock.inc, one-hold.inc), and BatteryMenu.h's DMBattLockLayout (one-locklayout.inc)
static BOOL gLocked;   // (DMBarLockedNow: the Lock Screen up, as the layout reads it)
static const void *kHoldWantAlphaKey = &kHoldWantAlphaKey, *kHoldGaveUpKey = &kHoldGaveUpKey, *kBarLookLockedKey = &kBarLookLockedKey;
static const void *kBarLaidOutLockedKey = &kBarLaidOutLockedKey, *kBarClosedUpKey = &kBarClosedUpKey;
static const void *kCCIconKey = &kCCIconKey, *kCCButtonKey = &kCCButtonKey, *kCCPillKey = &kCCPillKey, *kBattButtonKey = &kBattButtonKey;
static BOOL gDMHoldOwnAlpha = NO;
static void DMSBDiagStep(NSString *s) {}
static BOOL DMBarLockedNow(void) { return gLocked; }
static BOOL DMBarCopyPooled(UIView *fg) { return NO; }
static BOOL DMBarCopyIsCCDuplicate(UIView *fg) { return NO; }   // (iPadOS's own Control Center: its header copy is not a duplicate)
static BOOL DMSMEngine(void) { return NO; }
static BOOL DMSMInFullScreenCard(UIView *fg) { return NO; }
static void DMSMMainBarChanged(UIView *fg) {}
static void DMHideAppBarItemsOf(UIView *fg) {}
static void DMBattCoverAX(UIView *fg, NSArray *views, BOOL on) {}
static UIView *DMFirstStringView(UIView *container) { return nil; }   // (no time label: the copy has no clock)
static UIView *DMLeadingContainer(UIView *fg) { return fg.subviews.firstObject; }   // (a leading region is there, without the time)
#include "one-locklayout.inc"
static BOOL DMLayoutWithoutClock(UIView *fg) { DMBattLockLayout(fg); return YES; }   // (the real one: the icons closed up, our items hidden -- BatteryMenu.h's part real)
static void DMReleaseStatusBarCopy(UIView *fg);
static void DMHoldSafetyCheck(UIView *fg, int checks);
#include "one-hold.inc"
static void NoClockLayout(UIView *fg) {   // (StatusBar.x -dm_layoutLogoBody for a copy without its time label: its real no-clock branch)
#include "one-noclock.inc"
}
static void LockLayout(UIView *fg) { NoClockLayout(fg); }   // (our layout pass of a copy on the Lock Screen: the no-clock layout)
static void OurPass(UIView *fg) {   // (the -layoutSubviews hook, for a copy without its clock: held, laid out, released when ours)
    DMHoldStatusBarCopy(fg);
    NoClockLayout(fg);
    if (objc_getAssociatedObject(fg, kLogoKey) || objc_getAssociatedObject(fg, kNoClockLayoutKey)) DMReleaseStatusBarCopy(fg);
}
@interface TForeground : UIView   // (a copy's foreground view, its layout pass ours as the hook makes it: DMHoldSafetyCheck lays it out)
@end
@implementation TForeground
- (void)layoutSubviews { [super layoutSubviews]; OurPass(self); }
@end

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the stand-ins ---------------------------------------------------------------------------------------------------------------------------
@interface NSObject (TStatusBarData)   // (UIKit's own _UIStatusBarData and _UIStatusBarDataBatteryEntry on this Mac: their methods as read here)
- (id)mainBatteryEntry;
- (void)setMainBatteryEntry:(id)entry;
- (NSString *)detailString;
- (void)setDetailString:(NSString *)s;
- (BOOL)prominentlyShowsDetailString;
- (void)setProminentlyShowsDetailString:(BOOL)on;
- (long long)capacity;
- (void)setCapacity:(long long)c;
- (BOOL)saverModeActive;
- (void)setSaverModeActive:(BOOL)on;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)on;
@end
static NSString *const kIconID = @"batteryIcon", *const kPercentID = @"batteryPercent", *const kWiFiID = @"wifi";
@interface TDisplayItem : NSObject
@property (nonatomic, strong) id identifier;
@property (nonatomic, weak) id item;
@property (nonatomic, strong) UIView *view;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@end
@implementation TDisplayItem
@end
@interface TUpdate : NSObject
@property (nonatomic, strong) id data;
@property (nonatomic) BOOL enablementChanged, enabled, dataChanged;
@end
@implementation TUpdate
@end
@interface TRegion : NSObject
@property (nonatomic, copy) NSArray *displayItems;
@end
@implementation TRegion
@end
@interface TItem : NSObject
@property (nonatomic, weak) UIView *statusBar;
@end
@implementation TItem
- (NSSet *)dependentEntryKeys { return [NSSet setWithObject:@"mainBatteryEntry"]; }
- (id)applyUpdate:(TUpdate *)u toDisplayItem:(TDisplayItem *)di { return nil; }
- (id)_applyUpdate:(TUpdate *)u toDisplayItem:(TDisplayItem *)di {   // (as read)
    if (u.enablementChanged) di.enabled = u.enabled;
    [self applyUpdate:u toDisplayItem:di];
    if (u.enablementChanged && !u.enabled) di.enabled = NO;
    return nil;
}
@end
static BOOL TItemCanEnable(id self, SEL _cmd, id displayItem, id data) {   // (the base item's, as read: one of its data entries on)
    for (NSString *k in [self dependentEntryKeys]) if ([[data valueForKey:k] isEnabled]) return YES;
    return NO;
}
static BOOL TBatteryOwnCanEnable(id self, SEL _cmd, id displayItem, id data) { return TItemCanEnable(self, _cmd, displayItem, data); }
@interface TWiFiItem : TItem
@end
@implementation TWiFiItem
- (BOOL)canEnableDisplayItem:(id)displayItem fromData:(id)data { return YES; }
@end
@interface TBatteryItem : TItem
@property (nonatomic, strong) UIView *batteryView;
@property (nonatomic, strong) UILabel *percentView;
@end
@implementation TBatteryItem
- (id)applyUpdate:(TUpdate *)u toDisplayItem:(TDisplayItem *)di {   // (as read: the percentage turned off when iPadOS's setting is off)
    id e = [u.data mainBatteryEntry];
    if (di.identifier == kPercentID) {
        NSString *detail = [e detailString];
        if (![e prominentlyShowsDetailString]) detail = nil;
        if (detail.length) self.percentView.text = detail;
        else di.enabled = NO;
    } else if (u.dataChanged && e) {
        ((void (*)(id, SEL, double))objc_msgSend)(self.batteryView, sel_registerName("setChargePercent:"), [e capacity] / 100.0);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self.batteryView, sel_registerName("setSaverModeActive:"), [e saverModeActive]);
    }
    return nil;
}
@end
static id TPercentDisplayIdentifier(id self, SEL _cmd) { return kPercentID; }
@interface TBox : UIView
@end
@implementation TBox
- (CGSize)intrinsicContentSize { return CGSizeMake(15, 11); }
@end
@interface TBar : UIView
@property (nonatomic, strong) UIView *foregroundView;
@property (nonatomic, strong) NSDictionary *regions;
@property (nonatomic, strong) id currentAggregatedData;
@property (nonatomic, strong) NSArray<TDisplayItem *> *order;   // (leading to trailing)
@property (nonatomic, strong) TBatteryItem *battery;
@property (nonatomic, strong) NSArray *items;   // (the bar keeps its items; a display item's is weak)
@property (nonatomic, strong) UIView *region;   // (the trailing region's view: a plain UIView in the foreground view, as iPadOS's)
@property (nonatomic) BOOL ours, lockScreen, hooked;   // (hooked: laid out by its own pass, the -layoutSubviews hook's -- held, laid out, released)
@property (nonatomic) int updates;
@property (nonatomic, strong) NSMutableSet *removing;   // (display items whose removal animation runs: still in the region)
@end
@implementation TBar
- (void)_updateWithAggregatedData:(id)data {   // (each display item's state, as read; then the region's layout)
    self.currentAggregatedData = data; self.updates++;
    SEL can = sel_registerName("canEnableDisplayItem:fromData:");
    for (TDisplayItem *di in self.order) {
        id item = di.item;
        BOOL was = di.enabled, now = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(item, can, di, data);
        TUpdate *u = [TUpdate new]; u.data = data;
        if (now && was) u.dataChanged = YES;
        else if (now) { u.dataChanged = YES; u.enablementChanged = YES; u.enabled = YES; }
        else if (was) { u.data = nil; u.enablementChanged = YES; u.enabled = NO; }
        else continue;
        [item _applyUpdate:u toDisplayItem:di];
        if (!self.removing) self.removing = [NSMutableSet set];
        if (was && !di.enabled) [self.removing addObject:di];
        if (di.enabled) [self.removing removeObject:di];
    }
    [self layOutWithUs:YES];
}
- (void)settle { [self.removing removeAllObjects]; [self layOutWithUs:NO]; }   // (the removal animations over: the region alone)
- (void)layOutWithUs:(BOOL)us {   // (the region: its enabled display items -- and those on their way out -- from the trailing edge, 6 pt apart; the others' views out of it)
    NSMutableArray *on = [NSMutableArray array];
    for (TDisplayItem *di in self.order) if (di.enabled || [self.removing containsObject:di]) [on addObject:di];
    ((TRegion *)self.regions[@"trailing"]).displayItems = on;
    CGFloat x = self.foregroundView.bounds.size.width - 10, h = self.foregroundView.bounds.size.height;
    for (TDisplayItem *di in on.reverseObjectEnumerator) {
        CGSize s = di.view.intrinsicContentSize;
        if (di.view.superview != self.region) [self.region addSubview:di.view];
        di.view.frame = CGRectMake(x - s.width, (h - s.height) / 2, s.width, s.height);
        x -= s.width + 6;
    }
    for (TDisplayItem *di in self.order) if (![on containsObject:di]) [di.view removeFromSuperview];
    if (us && self.hooked) {}   // (iPadOS's update lays out the region's view, not the copy: its own pass, OurPass, when UIKit lays it out -- Relaid)
    else if (us && self.lockScreen) LockLayout(self.foregroundView);   // (our layout pass of a copy on the Lock Screen: the no-clock layout)
    else if (us && self.ours) DMBattInsideBar(self.foregroundView);   // (our layout pass of a bar of ours: StatusBar.x)
}
@end

// ---- the world ----------------------------------------------------------------------------------------------------------------------------
typedef enum { kOurs, kHeld, kNotOurs, kLockHeld, kLockLeft, kHooked } BarKind;   // (Lock: a copy that comes up on the Lock Screen -- held, or left to iOS;
                                                                               //  Hooked: laid out by its own pass, held by the hold as built)
static NSArray<TBar *> *gBars;
static TBar *MakeBar(BarKind kind) {
    TBar *bar = [[TBar alloc] initWithFrame:CGRectMake(0, 0, 400, 24)];
    UIView *fg = [[(kind == kHooked ? [TForeground class] : [UIView class]) alloc] initWithFrame:bar.bounds];
    [bar addSubview:fg]; bar.foregroundView = fg;
    bar.region = [[UIView alloc] initWithFrame:fg.bounds]; [fg addSubview:bar.region];
    TRegion *region = [TRegion new]; bar.regions = @{ @"trailing": region };
    TWiFiItem *wifi = [TWiFiItem new]; wifi.statusBar = bar;
    TBatteryItem *battery = [TBatteryItem new]; battery.statusBar = bar; bar.battery = battery;
    battery.batteryView = [[NSClassFromString(@"_UIBatteryView") alloc] initWithFrame:CGRectZero];
    ((void (*)(id, SEL, id))objc_msgSend)(battery.batteryView, sel_registerName("setFillColor:"), UIColor.whiteColor);
    battery.percentView = [[NSClassFromString(@"_UIStatusBarStringView") alloc] initWithFrame:CGRectZero];
    battery.percentView.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    TDisplayItem *(^di)(id, id, UIView *) = ^TDisplayItem *(id ident, id item, UIView *view) { TDisplayItem *d = [TDisplayItem new]; d.identifier = ident; d.item = item; d.view = view; return d; };
    bar.order = @[di(kWiFiID, wifi, [TBox new]), di(kPercentID, battery, battery.percentView), di(kIconID, battery, battery.batteryView)];
    bar.items = @[wifi, battery];
    if (!gAllBarCopies) gAllBarCopies = [NSHashTable weakObjectsHashTable];
    [gAllBarCopies addObject:fg];
    if (kind == kOurs) {
        objc_setAssociatedObject(fg, kLogoKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gCopies) gCopies = [NSHashTable weakObjectsHashTable];
        [gCopies addObject:fg];
    }
    if (kind == kHeld || kind == kLockHeld) objc_setAssociatedObject(fg, kHoldKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    bar.ours = kind == kOurs || kind == kHeld;
    bar.lockScreen = kind == kLockHeld || kind == kLockLeft;
    bar.hooked = kind == kHooked;
    static NSMutableArray *bars; if (!bars) bars = [NSMutableArray array];
    [bars addObject:bar]; gBars = bars;
    return bar;
}
// iPadOS's data: Battery Percentage (Settings > Battery) on or off, the level, Low Power Mode (which shows iPadOS's number too)
static id Data(BOOL percentage, int level, BOOL lowPower, BOOL entryOn) {
    id e = [NSClassFromString(@"_UIStatusBarDataBatteryEntry") new];
    [e setEnabled:entryOn]; [e setCapacity:level]; [e setSaverModeActive:lowPower];
    [e setDetailString:[NSString stringWithFormat:@"%d%%", level]];
    [e setProminentlyShowsDetailString:percentage || lowPower];
    id d = [NSClassFromString(@"_UIStatusBarData") new];
    [d setMainBatteryEntry:e];
    return d;
}
static void Feed(TBar *bar, id data) {   // (iPadOS's update: the level read anew by us too)
    gFake.percent = (int)[[data mainBatteryEntry] capacity]; gBattInsideReadAt = -100;
    [bar _updateWithAggregatedData:data];
    [bar settle];
}
static void LaidOut(TBar *bar) { DMBattInsideBar(bar.foregroundView); }   // (the bar's next layout of ours: StatusBar.x's layout pass)
static void Drain(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static void SwitchNow(BOOL on) { DMBattInsideApplyPref(on); Drain(); }   // (the animations still running)
static void Switch(BOOL on) { SwitchNow(on); for (TBar *b in gBars) [b settle]; }

typedef struct { CGRect wifi, percent, icon; } Frames;
static TDisplayItem *Item(TBar *bar, id ident) { for (TDisplayItem *d in bar.order) if (d.identifier == ident) return d; return nil; }
static Frames FramesOf(TBar *bar) {
    Frames f = { CGRectNull, CGRectNull, CGRectNull };
    if (Item(bar, kWiFiID).view.superview) f.wifi = Item(bar, kWiFiID).view.frame;
    if (Item(bar, kPercentID).view.superview) f.percent = Item(bar, kPercentID).view.frame;
    if (Item(bar, kIconID).view.superview) f.icon = Item(bar, kIconID).view.frame;
    return f;
}
static BOOL SameFrames(Frames a, Frames b) { return CGRectEqualToRect(a.wifi, b.wifi) && CGRectEqualToRect(a.percent, b.percent) && CGRectEqualToRect(a.icon, b.icon); }
static NSString *Text(Frames f) { return [NSString stringWithFormat:@"Wi-Fi %@, number %@, battery %@", NSStringFromCGRect(f.wifi), CGRectIsNull(f.percent) ? @"none" : NSStringFromCGRect(f.percent), NSStringFromCGRect(f.icon)]; }
static NSString *Ours(TBar *bar) {   // (our number inside the icon: its text, or nil when none shows)
    UILabel *l = objc_getAssociatedObject(bar.battery.batteryView, kBattInsideLabelKey);
    return l && !l.hidden && l.superview == bar.battery.batteryView ? l.text : nil;
}
static BOOL Theirs(TBar *bar) {   // (iPadOS's number beside the icon: on, in the region, laid out, showing)
    TDisplayItem *d = Item(bar, kPercentID);
    return d.enabled && [((TRegion *)bar.regions[@"trailing"]).displayItems containsObject:d] && d.view.superview == bar.region && !d.view.hidden && d.view.alpha > 0.05;
}
static Frames gA, gB;   // (the bar never switched on: iPadOS's Battery Percentage on, and off)
static void Baselines(TBar *bar, int level) {
    Feed(bar, Data(YES, level, NO, YES)); gA = FramesOf(bar);
    Feed(bar, Data(NO, level, NO, YES)); gB = FramesOf(bar);
    Feed(bar, Data(YES, level, NO, YES));
    Check(!CGRectIsNull(gA.percent) && CGRectGetMaxX(gA.wifi) + 6 == CGRectGetMinX(gA.percent) && CGRectGetMaxX(gA.percent) + 6 == CGRectGetMinX(gA.icon) && CGRectIsNull(gB.percent)
          && CGRectGetMaxX(gB.wifi) + 6 == CGRectGetMinX(gB.icon) && CGRectEqualToRect(gA.icon, gB.icon) && CGRectGetMinX(gA.wifi) < CGRectGetMinX(gB.wifi),
          [NSString stringWithFormat:@"the stand-in bar, never switched on: Battery Percentage on: %@; off: %@ (closed up)", Text(gA), Text(gB)]);
}
static void State(TBar *bar, NSString *ours, BOOL theirs, Frames want, NSString *what) {
    NSString *got = Ours(bar);
    BOOL ok = (ours ? [got isEqual:ours] : !got) && Theirs(bar) == theirs && SameFrames(FramesOf(bar), want);
    Check(ok, [NSString stringWithFormat:@"%@: %@ inside the icon, %@ beside it, %@%@", what, ours ? [NSString stringWithFormat:@"our number %@", ours] : @"no number",
               theirs ? @"iPadOS's number" : @"nothing", SameFrames(want, gB) ? @"the items closed up (no gap)" : @"laid out as with iPadOS's number",
               ok ? @"" : [NSString stringWithFormat:@" -- got: %@, %@, %@", got ? [NSString stringWithFormat:@"our number %@", got] : @"no number", Theirs(bar) ? @"iPadOS's number" : @"nothing", Text(FramesOf(bar))]]);
}
static NSUInteger Said(NSString *s) { return [gLog indexesOfObjectsPassingTest:^BOOL(NSString *l, NSUInteger i, BOOL *stop) { return [l containsString:s]; }].count; }

// ---- the scenarios ------------------------------------------------------------------------------------------------------------------------
static BOOL OwnMethod(Class c, SEL sel) {   // (the class itself has the method, not only a superclass)
    unsigned n = 0; BOOL has = NO;
    Method *list = class_copyMethodList(c, &n);
    for (unsigned i = 0; i < n; i++) if (method_getName(list[i]) == sel) has = YES;
    free(list);
    return has;
}
static void OneSwitch(void) {   // (a bar of ours: Battery Percentage on and off, x ours on and off, live)
    TBar *bar = MakeBar(kOurs);
    Baselines(bar, 80);
    DMBattInsideApplyPref(NO); Drain();   // (SpringBoard's start with the switch off, as the settings are read)
    SEL can = sel_registerName("canEnableDisplayItem:fromData:");
    Check(!OwnMethod([TBatteryItem class], can) && !Said(@"-canEnableDisplayItem:fromData: added") && !Said(@"not added"),
          @"never switched on: nothing added to iPadOS's battery item (its -canEnableDisplayItem:fromData: is its superclass's), nothing logged");
    State(bar, nil, YES, gA, @"never switched on, iPadOS's Battery Percentage on");
    UIView *batteryView = bar.battery.batteryView, *percentView = bar.battery.percentView; int updates = bar.updates;
    SwitchNow(YES);
    Check([Ours(bar) isEqual:@"80"] && [bar.removing containsObject:Item(bar, kPercentID)] && percentView.superview == bar.region,
          [NSString stringWithFormat:@"switched on: our number at once (%@), while iPadOS's goes (its removal animation)", Ours(bar) ?: @"none"]);
    for (TBar *b in gBars) [b settle];
    State(bar, @"80", NO, gB, @"switched on, iPadOS's Battery Percentage on (one switch), its removal over (no layout of ours since)");
    Check(bar.updates == updates + 1, @"switched on: the bar's items asked again at once, no respring (one data update of the bar's own data)");
    Check(DMBattItemViews(bar.foregroundView).count == 1 && DMBattItemViews(bar.foregroundView).firstObject == batteryView, @"the battery's views (Battery Menu's button over them): the battery alone");
    Check([[bar.currentAggregatedData mainBatteryEntry] prominentlyShowsDetailString], @"iPadOS's setting not written: its data still says Battery Percentage on");
    NSString *added = [NSString stringWithFormat:@"[battinside] iPadOS's own number beside the icon is left out of our bars while the switch is on (%s -canEnableDisplayItem:fromData: added)", class_getName([TBatteryItem class])];
    Check(Said(added) == 1 && OwnMethod([TBatteryItem class], can), [NSString stringWithFormat:@"logged once: \"%@\" (the battery item's own method now)", added]);
    Feed(bar, Data(NO, 80, NO, YES)); State(bar, @"80", NO, gB, @"on, iPadOS's Battery Percentage switched off");
    Feed(bar, Data(YES, 80, NO, YES)); State(bar, @"80", NO, gB, @"on, iPadOS's Battery Percentage switched on again");
    Feed(bar, Data(NO, 80, YES, YES)); State(bar, @"80", NO, gB, @"on, Low Power Mode (iPadOS shows its number then)");
    Feed(bar, Data(YES, 79, NO, YES)); State(bar, @"79", NO, gB, @"on, the level down to 79 %");
    Feed(bar, Data(YES, 80, NO, YES)); State(bar, @"80", NO, gB, @"on, the level back to 80 %");
    SwitchNow(NO);
    Check(!Ours(bar) && Theirs(bar), @"switched off: our number gone at once, iPadOS's number back at once (no respring)");
    for (TBar *b in gBars) [b settle];
    State(bar, nil, YES, gA, @"switched off, iPadOS's Battery Percentage on: iPadOS's number back, live");
    Check([bar.battery.percentView.text isEqual:@"80%"] && bar.battery.percentView == percentView && bar.battery.batteryView == batteryView, @"  the same bar and views, iPadOS's number with the level (80%)");
    Feed(bar, Data(NO, 80, NO, YES)); State(bar, nil, NO, gB, @"off, iPadOS's Battery Percentage off: no number (as iPadOS's setting says)");
    Switch(YES); State(bar, @"80", NO, gB, @"switched on, iPadOS's Battery Percentage off");
    Switch(NO); State(bar, nil, NO, gB, @"switched off, iPadOS's Battery Percentage off: still no number beside the icon (as its setting says)");
    Feed(bar, Data(YES, 80, NO, YES)); State(bar, nil, YES, gA, @"off, iPadOS's Battery Percentage on again: its number back");
    Switch(YES);
    Feed(bar, Data(YES, 80, NO, NO));
    Check(!Item(bar, kIconID).enabled && !Item(bar, kPercentID).enabled, @"on, iPadOS's battery entry off: no battery at all (the item's own answer kept)");
    Feed(bar, Data(YES, 80, NO, YES)); State(bar, @"80", NO, gB, @"on, the entry back: the battery with our number, iPadOS's left out");
    Check(Said(added) == 1, @"the method added once (switched on three times)");
}
static void OtherBars(void) {   // (a bar not ours -- Control Center's -- keeps iPadOS's number; a copy being set up is ours)
    TBar *ours = MakeBar(kOurs), *cc = MakeBar(kNotOurs), *held = MakeBar(kHeld);
    Baselines(ours, 80);
    Feed(cc, Data(YES, 80, NO, YES)); Feed(held, Data(YES, 80, NO, YES));
    SwitchNow(YES);
    Check([Ours(ours) isEqual:@"80"] && !Ours(cc) && Theirs(cc), @"switched on: our number at once in our bar, not in Control Center's (iPadOS's number kept there)");
    for (TBar *b in gBars) [b settle];
    State(ours, @"80", NO, gB, @"a bar of ours, switched on, iPadOS's Battery Percentage on");
    State(cc, nil, YES, gA, @"Control Center's bar (not ours), switched on: iPadOS's number kept, ours not added (one number)");
    Feed(cc, Data(YES, 80, NO, YES)); State(cc, nil, YES, gA, @"  and after its next update");
    Feed(held, Data(YES, 80, NO, YES)); State(held, @"80", NO, gB, @"a copy being set up (held): ours, iPadOS's number left out");
    Feed(cc, Data(NO, 80, NO, YES)); DMBattInsideEveryBar();
    State(cc, @"80", NO, gB, @"Control Center's bar, iPadOS's Battery Percentage off: our number there, as before");
    Switch(NO);
    State(cc, nil, NO, gB, @"switched off: Control Center's bar as iPadOS's setting says");
    State(ours, nil, YES, gA, @"switched off: our bar's iPadOS number back");
}
static void LockScreen(void) {   // (a copy that comes up on the Lock Screen after a respring: never the clock layout until an unlock)
    TBar *ref = MakeBar(kNotOurs);
    Baselines(ref, 80);
    Switch(YES);
    gLocked = YES;
    TBar *bar = MakeBar(kLockHeld);
    Feed(bar, Data(YES, 80, NO, YES));   // (iPadOS fills it while it is held; our Lock Screen layout follows; then it is released)
    objc_setAssociatedObject(bar.foregroundView, kHoldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    State(bar, @"80", NO, gB, @"the Lock Screen's bar, switched on, iPadOS's Battery Percentage on: our number from its first layout");
    Feed(bar, Data(YES, 80, NO, YES)); State(bar, @"80", NO, gB, @"  and after iPadOS's next update, released (still ours: one number)");
    TBar *left = MakeBar(kLockLeft);   // (a copy left to iOS -- never held -- laid out the Lock Screen's way: newly ours)
    Feed(left, Data(YES, 80, NO, YES));
    Drain(); [left settle];
    State(left, @"80", NO, gB, @"a Lock Screen copy left to iOS, laid out by us the Lock Screen's way: asked again, our number only");
    Switch(NO);
    State(bar, nil, YES, gA, @"switched off: the Lock Screen's bar has iPadOS's number back at once");
    State(left, nil, YES, gA, @"  and the other Lock Screen copy too");
}
static void RunFor(double seconds) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static void Relaid(TBar *bar) { [bar.foregroundView setNeedsLayout]; [bar.foregroundView layoutIfNeeded]; }   // (the copy's next layout pass, by UIKit)
static BOOL Held(TBar *bar) { return [objc_getAssociatedObject(bar.foregroundView, kHoldKey) boolValue]; }
static BOOL GaveUp(TBar *bar) { return objc_getAssociatedObject(bar.foregroundView, kHoldGaveUpKey) != nil; }
// Control Center's header copy with iPadOS's own Control Center (its status icons and battery, no time: the 17.5's "safety release ... in
// SBControlCenterWindow under STUIStatusBar_Wrapper ... its items exist" lines): laid out by our no-clock layout unlocked, held while it is
// being built, then given up by the hold -- left to iOS. Ours only while held: iPadOS's number beside its battery as before once it is left to
// iOS, and at every layout after (the mark of "ours" is the Lock Screen's layout, not any layout without a clock); our number follows.
static void CCHeader(void) {
    TBar *ref = MakeBar(kNotOurs);
    Baselines(ref, 80);
    Switch(YES);
    gLocked = NO;
    TBar *cc = MakeBar(kHooked);
    DMHoldStatusBarCopy(cc.foregroundView);   // (it came into Control Center's window: held, StatusBar.x -didMoveToWindow)
    Feed(cc, Data(YES, 80, NO, YES)); Relaid(cc);   // (iPadOS fills it, then its first layout pass: held, laid out without a clock, unlocked: still held)
    Check(Held(cc) && !objc_getAssociatedObject(cc.foregroundView, kNoClockLayoutKey), @"Control Center's header copy, unlocked, no clock: held while it is being built, not laid out the Lock Screen's way");
    State(cc, @"80", NO, gB, @"  while it is held (ours): our number, iPadOS's left out");
    RunFor(1.5);
    Check(Held(cc), @"  still held 1.5 s after (the hold's first look at 1 s: iPadOS's items are there, one more second)");
    RunFor(1.0);
    Check(!Held(cc) && GaveUp(cc) && Said(@"safety release: a status bar copy was not attached (its items exist but the layout would not attach); left to iOS from now on") == 1,
          @"  given up 2 s after it was held, as a copy with iPadOS's battery percentage (our number inside the icon stands for it), not after 30 s");
    [cc.foregroundView layoutIfNeeded]; [cc settle];   // (the copy's layout pass, if one was asked for at the give-up: none comes otherwise)
    State(cc, nil, YES, gA, @"  left to iOS: iPadOS's number beside its battery as before, ours not in it");
    Feed(cc, Data(YES, 80, NO, YES)); Relaid(cc); Drain(); [cc settle];
    State(cc, nil, YES, gA, @"  after its next update and layout without a clock (unlocked): still iPadOS's number only");
    Check(!Held(cc) && cc.foregroundView.alpha == 1.0, @"  not held again (shown: left to iOS)");
    Feed(cc, Data(NO, 80, NO, YES)); Drain(); [cc settle]; Relaid(cc);
    State(cc, @"80", NO, gB, @"  iPadOS's Battery Percentage off: our number there, as in any bar not ours (at its next layout)");
    Feed(cc, Data(YES, 80, NO, YES)); Relaid(cc); Drain(); [cc settle];
    State(cc, nil, YES, gA, @"  and on again: iPadOS's number back, ours gone");
    gLocked = YES;   // (the same copy laid out on the Lock Screen: ours by that layout, with no hold to release -- asked again)
    Relaid(cc); Drain(); [cc settle];
    State(cc, @"80", NO, gB, @"  laid out the Lock Screen's way: ours, our number only");
}
// A copy held on the Lock Screen whose last layout came before the lock state could be read (iPadOS 17 starts on the Lock Screen): no layout
// comes after; the hold's look 2 s on lays it out once more -- the Lock Screen's way now -- and releases it as ours (DMHoldSafetyCheck). Our
// number is its only text item then (iPadOS's left out while held): that look must still come at 2 s, not 30 s.
static void LockStart(void) {
    TBar *ref = MakeBar(kNotOurs);
    Baselines(ref, 80);
    Switch(YES);
    gLocked = NO;   // (the lock state not readable yet)
    TBar *bar = MakeBar(kHooked);
    DMHoldStatusBarCopy(bar.foregroundView);
    Feed(bar, Data(YES, 80, NO, YES)); Relaid(bar);   // (filled, then its first layout pass, unlocked as read then: still held)
    gLocked = YES;   // (readable now; no layout comes)
    RunFor(2.5);
    Check(!Held(bar) && !GaveUp(bar) && Said(@"[hold] a status bar copy laid out at its safety check: ours, released") == 1 && objc_getAssociatedObject(bar.foregroundView, kNoClockLayoutKey),
          @"the Lock Screen's copy laid out before the lock state could be read: laid out the Lock Screen's way at the hold's look 2 s on, released as ours (not after 30 s)");
    Drain(); [bar settle];
    State(bar, @"80", NO, gB, @"  and ours: our number only, iPadOS's left out");
}
static void KillSwitch(void) {   // (debug: /tmp/msb-stockbattpercent -- iPadOS's number kept, and then ours gives way to it: one number)
    TBar *bar = MakeBar(kOurs);
    Baselines(bar, 80);
    gKill = YES; Switch(YES);
    State(bar, nil, YES, gA, @"kill switch, switched on, iPadOS's Battery Percentage on: iPadOS's number kept, not ours too");
    Feed(bar, Data(NO, 80, NO, YES)); LaidOut(bar); State(bar, @"80", NO, gB, @"kill switch, iPadOS's Battery Percentage off: our number (at the bar's next layout, as before)");
    gKill = NO; Feed(bar, Data(YES, 80, NO, YES)); State(bar, @"80", NO, gB, @"kill switch gone, iPadOS's Battery Percentage on: one switch again");
}
static void NotAsRead(const char *how) {   // (a battery item not as read: nothing added, and as before -- one number, iPadOS's wins)
    TBar *bar = MakeBar(kOurs);
    Baselines(bar, 80);
    Switch(YES);
    Check(Said(@"not added: iPadOS's own number stays beside the icon where its setting is on") == 1 && !Said(@"left out of our bars"), [NSString stringWithFormat:@"%s: not added, logged", how]);
    State(bar, nil, YES, gA, [NSString stringWithFormat:@"%s, switched on, iPadOS's Battery Percentage on: as before (iPadOS's number, not ours too)", how]);
    Feed(bar, Data(NO, 80, NO, YES)); LaidOut(bar); State(bar, @"80", NO, gB, [NSString stringWithFormat:@"%s, iPadOS's Battery Percentage off: our number (at the bar's next layout, as before)", how]);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSString *s = argc > 1 ? @(argv[1]) : @"list";
        if ([s isEqual:@"list"]) { printf("oneswitch otherbars lockscreen ccheader lockstart kill own types noid\n"); return 0; }
        // the base item's -canEnableDisplayItem:fromData: in the iPad's types (an Intel Mac's BOOL is 'c'), the battery item's identifier
        SEL can = sel_registerName("canEnableDisplayItem:fromData:"), pid = sel_registerName("percentDisplayIdentifier");
        class_addMethod([TItem class], can, (IMP)TItemCanEnable, [s isEqual:@"types"] ? "c32@0:8@16@24" : "B32@0:8@16@24");
        if (![s isEqual:@"noid"]) class_addMethod(object_getClass([TBatteryItem class]), pid, (IMP)TPercentDisplayIdentifier, "@16@0:8");
        if ([s isEqual:@"own"]) class_addMethod([TBatteryItem class], can, (IMP)TBatteryOwnCanEnable, "B32@0:8@16@24");
        if ([s isEqual:@"oneswitch"]) OneSwitch();
        else if ([s isEqual:@"otherbars"]) OtherBars();
        else if ([s isEqual:@"lockscreen"]) LockScreen();
        else if ([s isEqual:@"ccheader"]) CCHeader();
        else if ([s isEqual:@"lockstart"]) LockStart();
        else if ([s isEqual:@"kill"]) KillSwitch();
        else if ([s isEqual:@"own"]) NotAsRead("the battery item answers it itself");
        else if ([s isEqual:@"types"]) NotAsRead("its types not the iPad's");
        else if ([s isEqual:@"noid"]) NotAsRead("no +percentDisplayIdentifier");
        else { printf("FAIL  no scenario %s\n", argv[1]); return 1; }
    }
    return gFails ? 1 : 0;
}
