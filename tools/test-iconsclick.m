// test-iconsclick.m -- see test-iconsclick.sh. A click on iPadOS's own status icons in our bar no longer opens Control Center while our Control
// Center icon shows (1.8.7.9, KT 18 Nov: Control Center opens only from our icon); the pulls, our controls, the time's region, pills and bars
// without our icon stay as they were. The real code, cut out of statusbar/StatusBar.x (the %hook _UIStatusBar -gestureRecognizerShouldBegin: and
// -statusBarGesture: bodies with %orig as iOS's part, DMPointOverOurControl, DMIconsClickRefused, DMBarDropTarget, DMCall, and in a DEBUG build
// DMIconsActionableText / DMIconsLog) and BatteryMenu.h (DMBattItemClass), run on a stand-in of iPadOS's bar as read in 17's SystemStatusUI
// (battone/hdr/17-STUIStatusBar.m: -gestureRecognizerShouldBegin: :4445-4560, -statusBarGesture: :4378-4443; 16.7.7 has the same selectors):
//  - -gestureRecognizerShouldBegin: (asked for any recognizer on the bar): the hovered actionable is the target; else, in a region that is enabled,
//    has display items and holds the touch, a display item with an enabled action under the touch, else -- only while no target is set (an old
//    one stays: nothing clears it here) -- the region if its own action is enabled. YES when a target is set. IC late: the target is stored only
//    when the gesture begins (an iOS version that picks it later; the rule then reads the hovered actionable).
//  - -statusBarGesture:: Began/Changed: the target's pressed look; Ended: if the touch is inside the target, its hoverAction ?: action ?: the bar's
//    action is run; Ended, Cancelled, Failed: the pressed look off and the target cleared.
//  - the action recognizer as Mac UIKit's _UIStatusBarActionGestureRecognizer: asked to begin at touch down; Ended when it lifts inside the bar,
//    else Failed; Cancelled when another gesture (the pull) takes the touch. Refused, it fails: SpringBoard's scroll-to-top tap (which waits for it
//    to fail) gets the touch, as on empty bar space.
//  - the regions' click actions are the Mac's real +[_UIStatusBarHoverRegionAction leadingHoverAction] (Notification Center) and
//    +trailingHoverAction (Control Center); a pill's is a real _UIStatusBarAction. Run = recorded (performWithStatusBar: is iOS's).
#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <objc/runtime.h>
#import <objc/message.h>

#ifdef T_STUI   // (17+: SystemStatusUI's names, DMSBUseSTUI)
#define TBatteryItem STUIStatusBarBatteryItem
#define TBluetoothItem STUIStatusBarBluetoothItem
static BOOL gSTUI = YES;
#else
#define TBatteryItem _UIStatusBarBatteryItem
#define TBluetoothItem _UIStatusBarBluetoothItem
static BOOL gSTUI = NO;
#endif

// ---- what the cut code needs ---------------------------------------------------------------------------------------------------------------
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static BOOL gKill __attribute__((unused));   // (the kill switch's file, /tmp/msb-iconscc)
#define DMTestFlag(path) (gKill && !strcmp((path), "/tmp/msb-iconscc"))
static BOOL DMSBUseSTUI(void) { return gSTUI; }
static const void *kLogoKey = &kLogoKey, *kButtonKey = &kButtonKey, *kLightsKey = &kLightsKey;
static const void *kAppButtonKey = &kAppButtonKey, *kFileButtonKey = &kFileButtonKey, *kEditButtonKey = &kEditButtonKey, *kViewButtonKey = &kViewButtonKey;
static const void *kGoButtonKey = &kGoButtonKey, *kWinButtonKey = &kWinButtonKey, *kDispButtonKey = &kDispButtonKey, *kAudioButtonKey = &kAudioButtonKey;
static const void *kSSHButtonKey = &kSSHButtonKey, *kVPNButtonKey = &kVPNButtonKey, *kWiFiButtonKey = &kWiFiButtonKey, *kSpotButtonKey = &kSpotButtonKey;
static const void *kClockButtonKey = &kClockButtonKey, *kBattButtonKey = &kBattButtonKey, *kCCButtonKey = &kCCButtonKey;
static const void *kAirPodsButtonKey = &kAirPodsButtonKey;   // (1.8.8.1: the AirPods menu's button over iPadOS's AirPods item, one of our controls)
static char gAMButtonKeys[7];
#define DM_AM_BUTTONS (const void *)&gAMButtonKeys[0], (const void *)&gAMButtonKeys[1], (const void *)&gAMButtonKeys[2], (const void *)&gAMButtonKeys[3], (const void *)&gAMButtonKeys[4], (const void *)&gAMButtonKeys[5], (const void *)&gAMButtonKeys[6]
static id DMLAPillAt(UIView *fg, CGPoint p) { return nil; }   // (no Live Activity pill of ours here)
#include "one-call.inc"
#include "one-battclass.inc"
#include "one-over.inc"
#include "one-refused.inc"
#if DEBUG
#include "one-log.inc"
#endif

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the stand-ins ---------------------------------------------------------------------------------------------------------------------------
@interface NSObject (TStatusBarAction)   // (Mac UIKit's _UIStatusBarAction)
+ (id)actionWithBlock:(id)block;
+ (id)leadingHoverAction;
+ (id)trailingHoverAction;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)on;
@end
@interface TItem : NSObject
@end
@implementation TItem
@end
@interface TBatteryItem : TItem
@end
@implementation TBatteryItem
@end
@interface TBluetoothItem : TItem
@end
@implementation TBluetoothItem
@end
@interface TActionable : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) CGRect frame;   // (in the bar)
@property (nonatomic, strong) id action, hoverAction;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@end
@implementation TActionable
@end
@interface TDisplayItem : TActionable
@property (nonatomic, strong) id item;
@end
@implementation TDisplayItem
@end
@interface TRegion : TActionable
@property (nonatomic, copy) NSArray *displayItems;
@end
@implementation TRegion
@end

@interface TGR : UIGestureRecognizer   // (a recognizer on the bar: where the touch is, its state)
@property (nonatomic, weak) UIView *bar;
@property (nonatomic) CGPoint at;   // (in the bar)
@property (nonatomic) UIGestureRecognizerState tstate;
@end
@implementation TGR
- (CGPoint)locationInView:(UIView *)v { return v ? [self.bar convertPoint:self.at toView:v] : self.at; }
- (UIGestureRecognizerState)state { return self.tstate; }
@end

static id gTrailing, gLeading, gTrailingOff, gPillAction;
static NSMutableArray<NSString *> *gRan;
static void Ran(id a) {   // (-performWithStatusBar:completionHandler: runs the action's block only while it is enabled)
    NSString *n = a == gTrailing ? @"Control Center" : a == gLeading ? @"Notification Center" : a == gPillAction ? @"the pill's own" : a == gTrailingOff ? @"Control Center (disabled: runs nothing)" : @"the bar's own";
    [gRan addObject:n];
}
static BOOL gLateTarget;
@interface TBarBase : UIView   // (iPadOS's bar, as read)
@property (nonatomic, strong) TGR *actionGestureRecognizer;
@property (nonatomic, strong) id targetActionable, hoveredActionable, pending, action;
@property (nonatomic, strong) NSDictionary *regions;
@property (nonatomic, strong) UIView *foregroundView;
@property (nonatomic) BOOL pressed;
@end
@implementation TBarBase
- (BOOL)_gestureRecognizer:(UIGestureRecognizer *)g isInsideActionable:(id)a {
    return [a isKindOfClass:[TActionable class]] && CGRectContainsPoint(((TActionable *)a).frame, [g locationInView:self]);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    __block id t = self.targetActionable;
    if (self.hoveredActionable) t = self.hoveredActionable;
    else [self.regions enumerateKeysAndObjectsUsingBlock:^(id k, TRegion *r, BOOL *stop) {
        if (!r.isEnabled || !r.displayItems.count || ![self _gestureRecognizer:g isInsideActionable:r]) return;
        [r.displayItems enumerateObjectsUsingBlock:^(TDisplayItem *di, NSUInteger i, BOOL *stop2) {
            if ([di.action isEnabled] && [self _gestureRecognizer:g isInsideActionable:di]) { t = di; *stop2 = YES; }
        }];
        if (!t && [r.action isEnabled]) { t = r; *stop = YES; }
    }];
    if (gLateTarget) self.pending = t; else self.targetActionable = t;
    return t != nil;
}
- (void)statusBarGesture:(UIGestureRecognizer *)g {
    UIGestureRecognizerState s = g.state;
    if (s == UIGestureRecognizerStateBegan && gLateTarget) self.targetActionable = self.pending;
    if (s >= UIGestureRecognizerStateBegan && s <= UIGestureRecognizerStateEnded) {
        TActionable *in = [self _gestureRecognizer:g isInsideActionable:self.targetActionable] ? self.targetActionable : nil;
        if (s != UIGestureRecognizerStateEnded) { if (self.targetActionable) self.pressed = in != nil; return; }
        id a = in.hoverAction ?: in.action ?: self.action;
        if (a) Ran(a);
    } else if (s != UIGestureRecognizerStateCancelled && s != UIGestureRecognizerStateFailed) return;
    self.pressed = NO;
    self.targetActionable = nil;
}
@end
@interface TStatusBar : TBarBase   // (our hook on the bar: StatusBar.x's %hook _UIStatusBar, cut out; %orig = iPadOS's)
@end
@implementation TStatusBar
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
#include "one-begin.inc"
}
- (void)statusBarGesture:(UIGestureRecognizer *)g {
#include "one-gesture.inc"
}
@end

// ---- the bar ---------------------------------------------------------------------------------------------------------------------------------
// Landscape, 1194 x 24 (the M1). Regions: the status icons (880-1106: AirPods 885-915, iPadOS's Wi-Fi 920-944, a call pill 950-990 with its own
// action, iPadOS's battery 1040-1080; our mute icon, which has no button, at 996-1016; a 2 pt strip at 1032-1036; our battery button 1036-1084 and
// Control Center button 1088-1104 lie inside its frame, as on 15/16) and the time (1110-1194, under our clock's button). Our logo button at 8-38.
static const CGPoint kAirPods = {900, 12}, kWiFi = {932, 12}, kPill = {970, 12}, kMute = {1006, 12}, kStrip = {1034, 12}, kBattery = {1060, 12},
                     kCC = {1096, 12}, kTime = {1150, 12}, kLogo = {20, 12}, kEmpty = {500, 12};
typedef struct { BOOL ours, ccIcon, battMenu, clockButton, airPods; } TSetup;
static const TSetup kUsual = {YES, YES, YES, YES};
static TDisplayItem *Item(NSString *ident, CGFloat x, CGFloat w, id item, id action) {
    TDisplayItem *d = [TDisplayItem new]; d.identifier = ident; d.frame = CGRectMake(x, 0, w, 24); d.item = item; d.action = action; d.enabled = YES; return d;
}
static UIButton *Button(UIView *fg, const void *key, CGFloat x, CGFloat w, BOOL shown) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.frame = CGRectMake(x, 0, w, 24); b.hidden = !shown;
    [fg addSubview:b]; objc_setAssociatedObject(fg, key, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC); return b;
}
static TBarBase *MakeBarOf(Class cls, TSetup s, id trailing) {
    TBarBase *bar = [[cls alloc] initWithFrame:CGRectMake(0, 0, 1194, 24)];
    UIView *fg = [[UIView alloc] initWithFrame:bar.bounds]; [bar addSubview:fg]; bar.foregroundView = fg;
    TGR *g = [[TGR alloc] initWithTarget:nil action:NULL]; g.bar = bar; bar.actionGestureRecognizer = g;
    TRegion *icons = [TRegion new]; icons.identifier = @"trailing"; icons.frame = CGRectMake(880, 0, 226, 24); icons.hoverAction = trailing ?: gTrailing; icons.enabled = YES;
    icons.displayItems = @[Item(@"bluetooth", 885, 30, [TBluetoothItem new], nil), Item(@"wifi", 920, 24, [TItem new], nil), Item(@"pill", 950, 40, [TItem new], gPillAction),
                           Item(@"batteryIcon", 1040, 40, [TBatteryItem new], nil)];
    TRegion *time = [TRegion new]; time.identifier = @"leading"; time.frame = CGRectMake(1110, 0, 84, 24); time.hoverAction = gLeading; time.enabled = YES;
    time.displayItems = @[Item(@"time", 1115, 70, [TItem new], nil)];
    bar.regions = @{@"leading": time, @"trailing": icons};
    if (s.ours) {
        objc_setAssociatedObject(fg, kLogoKey, [UIImageView new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Button(fg, kButtonKey, 8, 30, YES);
        Button(fg, kBattButtonKey, 1036, 48, s.battMenu);
        Button(fg, kCCButtonKey, 1088, 16, s.ccIcon);
        Button(fg, kClockButtonKey, 1110, 84, s.clockButton);
        Button(fg, kAirPodsButtonKey, 881, 38, s.airPods);   // (AirPods Menu on, iPadOS's AirPods item showing its battery: 4 pt past it)
    }
    return bar;
}
static TStatusBar *MakeBar(TSetup s) { return (TStatusBar *)MakeBarOf([TStatusBar class], s, nil); }
static id Under(TBarBase *bar, CGPoint p, BOOL itemsToo) {   // (the pointer resting there: what -pointerInteraction:willEnterRegion: makes hovered)
    for (TRegion *r in bar.regions.allValues) {
        if (!CGRectContainsPoint(r.frame, p)) continue;
        if (itemsToo) for (TDisplayItem *d in r.displayItems) if (d.action && CGRectContainsPoint(d.frame, p)) return d;
        return r;
    }
    return nil;
}
static void Hover(TBarBase *bar, CGPoint p) { bar.hoveredActionable = Under(bar, p, NO); }
static void HoverOff(TBarBase *bar) { bar.hoveredActionable = nil; }

enum { kLift, kMoveOut, kCancel };
// One touch on the bar's action recognizer, at p: down, then it lifts there, moves down out of the bar and lifts, or is cancelled (a pull).
static NSString *Touch(TBarBase *bar, CGPoint p, int how) {
    TGR *g = bar.actionGestureRecognizer;
    if (!gRan) gRan = [NSMutableArray array];
    [gRan removeAllObjects];
    g.at = p; g.tstate = UIGestureRecognizerStatePossible;
    if (![bar gestureRecognizerShouldBegin:g]) { g.tstate = UIGestureRecognizerStateFailed; return how == kLift ? @"refused (the tap goes on, as on empty bar space)" : @"refused"; }
    g.tstate = UIGestureRecognizerStateBegan; [bar statusBarGesture:g];
    if (how == kCancel) { g.tstate = UIGestureRecognizerStateCancelled; [bar statusBarGesture:g]; }
    else {
        if (how == kMoveOut) { g.at = CGPointMake(p.x, 300); g.tstate = UIGestureRecognizerStateChanged; [bar statusBarGesture:g]; }
        g.tstate = [bar pointInside:[g locationInView:bar] withEvent:nil] ? UIGestureRecognizerStateEnded : UIGestureRecognizerStateFailed;
        [bar statusBarGesture:g];
    }
    if (bar.pressed) return @"taken, the pressed look left on";
    return [NSString stringWithFormat:@"taken, runs %@", gRan.count ? [gRan componentsJoinedByString:@", "] : @"nothing"];
}
static NSString *Click(TBarBase *bar, CGPoint p) { Hover(bar, p); NSString *r = Touch(bar, p, kLift); return r; }
static NSString *TargetName(TBarBase *bar) { return bar.targetActionable ? ((TActionable *)bar.targetActionable).identifier : @"none"; }
static NSString *const kRefusedTap = @"refused (the tap goes on, as on empty bar space)";

// ---- the cases -------------------------------------------------------------------------------------------------------------------------------
static void Expect(NSString *got, NSString *want, NSString *what) {
    Check([got isEqualToString:want], [NSString stringWithFormat:@"%@: %@%@", what, got, [got isEqualToString:want] ? @"" : [NSString stringWithFormat:@" (wanted: %@)", want]]);
}
int main(int argc, char **argv) {
    @autoreleasepool {
        Class H = objc_getClass("_UIStatusBarHoverRegionAction"), A = objc_getClass("_UIStatusBarAction");
        if (!H || !A) { printf("FAIL  no _UIStatusBarHoverRegionAction / _UIStatusBarAction on this Mac\n"); return 1; }
        gTrailing = [H trailingHoverAction]; gLeading = [H leadingHoverAction]; gTrailingOff = [H trailingHoverAction]; [gTrailingOff setEnabled:NO];
        gPillAction = [A actionWithBlock:^(id bar, id done) {}];
        Check([gTrailing isEnabled] && [gLeading isEnabled] && [gPillAction isEnabled] && ![gTrailingOff isEnabled] && gTrailing != gTrailingOff,
              @"setup: the Mac's real region actions (+trailingHoverAction a new object per call), enabled; a pill's action");
        const char *only = argc > 1 ? argv[1] : NULL;
#define CASE(name) if (!only || !strcmp(only, name))
        NSString *empty = Click(MakeBar(kUsual), kEmpty);   // (a click on empty bar space: no region there)
        Expect(empty, kRefusedTap, @"(a click on empty bar space)");

        CASE("C1") {   // KT's report: the AirPods item
            TStatusBar *bar = MakeBar(kUsual);
            NSString *r = Click(bar, kAirPods);
            Expect(r, kRefusedTap, @"C1 pointer click on the AirPods item, our icon showing: Control Center not opened");
            Check([r isEqualToString:empty], @"C1 ... it does what a click on empty bar space does (KT's Q4)");
            Expect(TargetName(bar), @"none", @"C1 ... no target kept");
            Expect(Touch(bar, kAirPods, kLift), kRefusedTap, @"C1 ... a finger tap there while the pointer rests on it: the same");
#if DEBUG
            BOOL told = NO; for (NSString *l in gLog) if ([l isEqualToString:@"[iconscc] a click on iPadOS's status icons: Control Center only from our icon"]) told = YES;
            Check(told, @"C1 ... (debug) the [iconscc] line");
#endif
        }
        CASE("C1L") {   // an iOS that stores the target only when the gesture begins: the rule reads the hovered actionable
            gLateTarget = YES;
            TStatusBar *bar = MakeBar(kUsual);
            Expect(Click(bar, kAirPods), kRefusedTap, @"C1L (target picked late) pointer click on the AirPods item: Control Center not opened");
            gLateTarget = NO;
        }
        CASE("C2") {   // one rule for every iPadOS item, no list
            Expect(Click(MakeBar(kUsual), kWiFi), kRefusedTap, @"C2 pointer click on iPadOS's Wi-Fi item (Wi-Fi Menu off): Control Center not opened");
            Expect(Click(MakeBar(kUsual), kMute), kRefusedTap, @"C2 ... on our mute icon (no button of its own)");
            Expect(Click(MakeBar(kUsual), kStrip), kRefusedTap, @"C2 ... on the 2 pt strip before our battery button");
            TSetup off = kUsual; off.battMenu = NO;   // (Battery Menu off, our Control Center icon showing: KT's Q1)
            Expect(Click(MakeBar(off), kBattery), kRefusedTap, @"C2 ... on iPadOS's battery with Battery Menu off, our icon showing (Q1)");
        }
        CASE("C3") {   // the old target: a finger tap after a refused begin
            TStatusBar *bar = MakeBar(kUsual);
            Hover(bar, kAirPods);
            Expect(Touch(bar, kLogo, kLift), @"refused (the tap goes on, as on empty bar space)", @"C3 finger tap on our logo, the pointer resting on the icons: not the bar's");
            HoverOff(bar);
            Expect(Touch(bar, kAirPods, kLift), kRefusedTap, @"C3 ... then, the pointer gone, a finger tap on the AirPods item: Control Center not opened");
            TStatusBar *b2 = MakeBar(kUsual);   // (R3's likelier order: a click on our battery, then a finger tap)
            Expect(Click(b2, kBattery), kRefusedTap, @"C3 click on our battery button (inside the icons' region): not the bar's");
            HoverOff(b2);
            Expect(Touch(b2, kAirPods, kLift), kRefusedTap, @"C3 ... then, the pointer gone, a finger tap on the AirPods item: Control Center not opened");
        }
        CASE("C4") {   // the drop (its own change): no old target after a refused begin
            TStatusBar *bar = MakeBar(kUsual);
            Click(bar, kBattery);
            HoverOff(bar);
            Expect(TargetName(bar), @"none", @"C4 after a refused begin (our battery clicked, the pointer resting on the icons): no target kept");
            Expect(Touch(bar, kEmpty, kLift), kRefusedTap, @"C4 ... a finger tap on empty bar space then goes on (not taken and swallowed)");
        }
        CASE("C5") {
            TStatusBar *bar = MakeBar(kUsual);
            Expect(Click(bar, kCC), kRefusedTap, @"C5 click on our Control Center icon: not the bar's (its own button opens Control Center)");
        }
        CASE("C6") {
            TSetup s = kUsual; s.clockButton = NO;   // (Clock Opens Today View off: the time's region under the clock)
            Expect(Click(MakeBar(s), kTime), @"taken, runs Notification Center", @"C6 click on the time, Clock Opens Today View off: Notification Center as before");
        }
        CASE("C7") {
            TSetup s = kUsual; s.ccIcon = NO; s.battMenu = NO;   // (the Lock Screen look: DMBattLockLayout hides both)
            Expect(Click(MakeBar(s), kAirPods), @"taken, runs Control Center", @"C7 Lock Screen look (our icon hidden): the click opens Control Center as before (Q2)");
        }
        CASE("C8") {
            TSetup s = {NO, NO, NO, NO};
            Expect(Click(MakeBar(s), kAirPods), @"taken, runs Control Center", @"C8 a bar not ours (a strip, Control Center's header copy): as before");
            TSetup t = kUsual; t.ccIcon = NO; t.battMenu = NO;   // (Battery Menu off with iPadOS's Control Center style: no icon of ours)
            Expect(Click(MakeBar(t), kBattery), @"taken, runs Control Center", @"C8 ours without our icon (Battery Menu off, iPadOS's style): the battery click as before (Q2)");
            TStatusBar *b3 = MakeBar(kUsual);   // ((b) asks both: a copy not marked ours, though a Control Center button is in it)
            objc_setAssociatedObject(b3.foregroundView, kLogoKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            Expect(Click(b3, kAirPods), @"taken, runs Control Center", @"C8 a copy not marked ours (no kLogoKey), a Control Center button in it: as before");
        }
        CASE("C9") {
            TStatusBar *bar = MakeBar(kUsual);
            Expect(Touch(bar, kPill, kLift), @"taken, runs the pill's own", @"C9 finger tap on a call pill: its own action");
            TStatusBar *b2 = MakeBar(kUsual);
            b2.hoveredActionable = Under(b2, kPill, YES);
            Expect(Touch(b2, kPill, kLift), @"taken, runs the pill's own", @"C9 click on the pill, the pointer on the pill itself: its own action");
        }
        CASE("C10") {
            TStatusBar *bar = MakeBar(kUsual);
            Expect(Touch(bar, kAirPods, kLift), kRefusedTap, @"C10 finger tap on the AirPods item with no pointer: nothing, as on a stock iPad");
        }
        CASE("C12") {   // 1.8.8.1: the AirPods menu's button over the AirPods item is one of our controls: our menu, never iPadOS's region action
            TSetup s = kUsual; s.ccIcon = NO; s.battMenu = NO; s.airPods = YES;   // (no Control Center icon of ours: 1.8.7.9's rule does not apply there)
            Expect(Click(MakeBar(s), kAirPods), kRefusedTap, @"C12 click on the AirPods button (AirPods Menu on, no Control Center icon of ours): not the bar's -- our menu, not Control Center");
            Expect(Touch(MakeBar(s), kAirPods, kLift), kRefusedTap, @"C12 ... a finger tap on it: the same");
            TSetup u = kUsual; u.airPods = YES;
            Expect(Click(MakeBar(u), kAirPods), kRefusedTap, @"C12 ... with our Control Center icon: the same (our control, before 1.8.7.9's rule)");
            s.airPods = NO;
            Expect(Click(MakeBar(s), kAirPods), @"taken, runs Control Center", @"C12 ... AirPods Menu off (no button), no icon of ours: Control Center as before (C8)");
        }
        CASE("C11") {   // other recognizers asked through the same method: iPadOS's answer, the target as iPadOS left it
            for (int over = 0; over < 2; over++) {
                TStatusBar *bar = MakeBar(kUsual); TBarBase *twin = MakeBarOf([TBarBase class], kUsual, nil);
                Hover(bar, kAirPods); Hover(twin, kAirPods);
                TGR *peep = [[TGR alloc] initWithTarget:nil action:NULL]; peep.bar = bar; peep.at = over ? kLogo : kAirPods;
                TGR *peep2 = [[TGR alloc] initWithTarget:nil action:NULL]; peep2.bar = twin; peep2.at = peep.at;
                BOOL got = [bar gestureRecognizerShouldBegin:peep], ios = [twin gestureRecognizerShouldBegin:peep2];
                if (over) Check(!got && ios, @"C11 another tweak's gesture over our logo: refused, as before (our controls)");
                else Check(got == ios && got, @"C11 another tweak's gesture on the AirPods item (pointer resting there): iPadOS's answer");
                Expect(TargetName(bar), TargetName(twin), [NSString stringWithFormat:@"C11 ... the target as iPadOS left it (%@)", over ? @"over our logo" : @"on the item"]);
            }
        }
        CASE("C12") {   // the pull from the top edge: the touch leaves the bar, or the pull cancels the bar's recognizer
            for (int hov = 0; hov < 2; hov++) for (int how = kMoveOut; how <= kCancel; how++) {
                TStatusBar *bar = MakeBar(kUsual);
                if (hov) Hover(bar, kAirPods);
                NSString *r = Touch(bar, kAirPods, how);
                Check(![r containsString:@"Control Center"] && ![r containsString:@"pressed"], [NSString stringWithFormat:@"C12 a touch on the AirPods item that %@%@: %@",
                      how == kMoveOut ? @"moves out of the bar" : @"a pull cancels", hov ? @", the pointer resting there" : @"", r]);
            }
        }
        CASE("C14") {   // (e): a touch outside the icons while the pointer rests on them is iPadOS's, as before
            TStatusBar *bar = MakeBar(kUsual);
            Hover(bar, kAirPods);
            Expect(Touch(bar, kEmpty, kLift), @"taken, runs nothing", @"C14 the pointer resting on the icons, a finger tap on empty bar space: as before");
        }
        CASE("C17") {   // (d): a region whose action is off is left to iPadOS
            TStatusBar *bar = (TStatusBar *)MakeBarOf([TStatusBar class], kUsual, gTrailingOff);
            Expect(Click(bar, kAirPods), @"taken, runs Control Center (disabled: runs nothing)", @"C17 the icons' action switched off by iPadOS: left to iPadOS, as before");
        }
#if DEBUG
        CASE("C13") {   // the kill switch: 1.8.7.8's rule, for before/after rows on one build
            gKill = YES;
            Expect(Click(MakeBar(kUsual), kAirPods), @"taken, runs Control Center", @"C13 (debug) /tmp/msb-iconscc: the click on the AirPods item as 1.8.7.8");
            TStatusBar *bar = MakeBar(kUsual);
            Click(bar, kBattery); HoverOff(bar);
            Expect(TargetName(bar), @"trailing", @"C13 ... the old target kept, as 1.8.7.8");
            gKill = NO;
        }
#endif
    }
    return gFails ? 1 : 0;
}
