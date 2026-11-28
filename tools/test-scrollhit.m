// test-scrollhit.m -- the scroll routing's decision asks our own layer first (1.8.7.4, audit O4 of 1.8.7.2).
// SpringBoard gets every trackpad or mouse scroll as a global copy for its system gesture window. While a native window (Finder, Activity Monitor,
// Display Settings) is on screen, the routing (StatusBar.x DMScrollWSWindow, DMNativeScrollIsOurs) decides for each such scroll whether it is over
// a native window. It built the list of every window and hit-tested each one above our layer (DMNativeWindowTaking) before it asked the layer
// (DMNativeLayerHitTest), which over an app -- where most scrolls are -- answers nothing at once: 60-120 window walks a second while scrolling in
// any app with a Finder window open. Now the layer is asked first, as a touch's own test does (DMNativeWindowAtScreenPoint); the windows above it
// are walked only for a point on a native window. Both are AND conditions: the answer is the same for every scroll.
// The real code is cut out by test-scrollhit.sh (scrollhit-real.inc): DMNativeLayerHitTest and DMNativeWindowTaking from statusbar/NativeWindow.h,
// and from statusbar/StatusBar.x the range from DMNativeScrollIsOurs to the end of DMScrollWSWindow (the decision and the hook that makes it once
// per event). Stand-ins: UIKit's views, windows and scroll event (Foundation only; every point is the screen's), the window list (DMAllWindows:
// each build counted), the window server's own hit test (DMScrollAlsoToLayer: each decision counted), the system's windows by their class names.
// Every window hit test outside our layer is counted (the walk's cost).
//   t <scenario>           one scenario (exit code: its failed checks); t list: the scenarios
//   t trace <seed> <n>     n random worlds, one line per scroll (for the .sh to compare with the code before the fix)
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <os/lock.h>

// ---- UIKit, as far as the real code uses it (every coordinate space is the screen's: conversions are the identity)
@protocol UICoordinateSpace <NSObject>
@end
@class UIView, UIWindow;
@interface UIScreen : NSObject <UICoordinateSpace>
@property (nonatomic, readonly) id<UICoordinateSpace> coordinateSpace;
@end
@implementation UIScreen
- (id<UICoordinateSpace>)coordinateSpace { return self; }
@end
@interface UIViewController : NSObject
@property (nonatomic, strong) UIViewController *presentedViewController;
@property (nonatomic, strong) UIView *view;
@end
@implementation UIViewController
@end
@interface UIEvent : NSObject
@property (nonatomic) NSTimeInterval timestamp;
@end
@implementation UIEvent
@end
static UIWindow *gNativeLayer;
static NSMutableArray<NSString *> *gHits;   // the windows hit-tested outside our layer, in order (the walk's cost)
static int gBuilds, gDecisions;              // window lists built (DMAllWindows); decisions made (the window server's hit test read)
@interface UIView : NSObject <UICoordinateSpace>
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, readonly) NSMutableArray<UIView *> *subviews;
@property (nonatomic) BOOL hidden, userInteractionEnabled;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) CGRect frame;
- (instancetype)initWithFrame:(CGRect)f;
- (void)addSubview:(UIView *)v;
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e;
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e;
- (BOOL)isDescendantOfView:(UIView *)v;
- (CGPoint)convertPoint:(CGPoint)p toView:(UIView *)v;
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id<UICoordinateSpace>)s;
- (CGPoint)convertPoint:(CGPoint)p fromCoordinateSpace:(id<UICoordinateSpace>)s;
@end
@interface UIWindow : UIView
@property (nonatomic) CGFloat windowLevel;
@property (nonatomic, strong) UIScreen *screen;
@property (nonatomic, strong) UIViewController *rootViewController;
@end
@implementation UIView
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super init])) { _frame = f; _alpha = 1.0; _userInteractionEnabled = YES; _subviews = [NSMutableArray array]; } return self; }
- (void)addSubview:(UIView *)v { [v.superview.subviews removeObject:v]; [_subviews addObject:v]; v.superview = self; }
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e { return CGRectContainsPoint(_frame, p); }
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {   // (UIKit's: the frontmost view at the point that takes touches, else the view itself)
    if ([self isKindOfClass:[UIWindow class]] && self != (UIView *)gNativeLayer) [gHits addObject:NSStringFromClass([self class])];
    if (_hidden || _alpha < 0.01 || !_userInteractionEnabled || ![self pointInside:p withEvent:e]) return nil;
    for (UIView *s in [_subviews reverseObjectEnumerator]) { UIView *h = [s hitTest:p withEvent:e]; if (h) return h; }
    return self;
}
- (BOOL)isDescendantOfView:(UIView *)v { for (UIView *s = self; s; s = s.superview) if (s == v) return YES; return NO; }
- (CGPoint)convertPoint:(CGPoint)p toView:(UIView *)v { return p; }
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id<UICoordinateSpace>)s { return p; }
- (CGPoint)convertPoint:(CGPoint)p fromCoordinateSpace:(id<UICoordinateSpace>)s { return p; }
@end
@implementation UIWindow
@end

// ---- the native windows (NativeWindow.h): a window takes its own frame (its grips are not modelled)
@interface DMNativeWindow : UIView
- (BOOL)dm_takesPoint:(CGPoint)q;
@end
@implementation DMNativeWindow
- (BOOL)dm_takesPoint:(CGPoint)q { return CGRectContainsPoint(self.frame, q); }
- (BOOL)pointInside:(CGPoint)q withEvent:(UIEvent *)e { return [self dm_takesPoint:q]; }
@end
static NSMutableArray<DMNativeWindow *> *gNativeWindows;   // front last
static UIView *gNativeRotator;
static UIView *gNativeKeys;
static UIView *gOverlay;
static BOOL gNativeAway;
static const CGFloat kScreenW = 1366, kScreenH = 1024, kBarH = 24;
static BOOL DMViewNearlyScreen(UIView *v) {
    CGSize b = v.frame.size;
    return (b.width >= kScreenW * 0.9 && b.height >= kScreenH * 0.75) || (b.height >= kScreenW * 0.9 && b.width >= kScreenH * 0.75);
}
static CGRect DMNativeDesktop(void) { return CGRectMake(0, kBarH, kScreenW, kScreenH - kBarH); }

// ---- the rest of SpringBoard the real code asks
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s ?: @""]; }
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }
static NSString *NSStringFromCGPoint(CGPoint p) { return [NSString stringWithFormat:@"{%g, %g}", p.x, p.y]; }
#define DM_FEATURE_MARK(name)
static BOOL DMSBIsBarWindowName(NSString *name) { return [name isEqualToString:@"UIStatusBarWindow"]; }
static NSMutableArray<UIWindow *> *gWindows;   // every window (UIKit's list), the layer among them
static NSArray<UIWindow *> *DMAllWindows(void) { gBuilds++; return [gWindows copy]; }
static BOOL DMScrollOldPath(void) { return NO; }
static BOOL DMScrollNone(void) { return NO; }

// UIKit's scroll event: the window the window server named it for, whether the layer gets its own copy as well, the pointer
@interface UIScrollEvent : UIEvent
@property (nonatomic, strong) UIWindow *tNamed;
@property (nonatomic) BOOL tAlsoToLayer;
@property (nonatomic) CGPoint tPoint;
@property (nonatomic) int tAsks;
- (id)_windowServerHitTestWindow;
- (void *)_hidEvent;
- (CGPoint)locationInView:(UIView *)v;
@end
@implementation UIScrollEvent {
    char _hid;
}
- (id)_windowServerHitTestWindow { _tAsks++; return _tNamed; }
- (void *)_hidEvent { return &_hid; }
- (CGPoint)locationInView:(UIView *)v { (void)[self _windowServerHitTestWindow]; return _tPoint; }   // (UIKit asks the window again for the location)
@end
static BOOL DMScrollAlsoToLayer(UIEvent *event, UIWindow *layer) { gDecisions++; return ((UIScrollEvent *)event).tAlsoToLayer; }

#include "scrollhit-real.inc"

// ---- the world
static NSMutableDictionary<NSString *, Class> *gClasses;
static Class KClass(NSString *name, Class base) {   // (a class of that name, made from base: the real code reads the system's windows by class name)
    Class c = gClasses[name] ?: objc_getClass(name.UTF8String);
    if (!c) { c = objc_allocateClassPair(base, name.UTF8String, 0); objc_registerClassPair(c); }
    gClasses[name] = c;
    return c;
}
static UIWindow *KWindow(NSString *cls, CGFloat level) {   // (a full-screen window with a full-screen root view, as SpringBoard's are)
    UIWindow *w = [[KClass(cls, [UIWindow class]) alloc] initWithFrame:CGRectMake(0, 0, kScreenW, kScreenH)];
    w.windowLevel = level; w.screen = [UIScreen new];
    w.rootViewController = [UIViewController new];
    w.rootViewController.view = [[UIView alloc] initWithFrame:w.frame];
    [w addSubview:w.rootViewController.view];
    [gWindows addObject:w];
    return w;
}
static UIView *KView(UIView *in, NSString *cls, CGRect f) { UIView *v = [[KClass(cls, [UIView class]) alloc] initWithFrame:f]; [in addSubview:v]; return v; }
static UIWindow *gSysGesture, *gSwitcher, *gDock, *gMenuWin, *gCC;
static UIView *gPlatter, *gDockRoot;
static void KReset(void) {
    gHits = [NSMutableArray array]; gLog = [NSMutableArray array]; gWindows = [NSMutableArray array]; gNativeWindows = [NSMutableArray array];
    gBuilds = gDecisions = 0; gOverlay = nil; gNativeAway = NO; gNativeLayer = nil; gNativeRotator = nil;
}
// SpringBoard with one Finder window: the system gesture window (2000), Control Center (1100, hidden), our menu window (1050, no menu open),
// the text effects window (1040) and the status bar (1036), these three answering every hit test, the Dock's window (1035: over the active layer,
// its platter at the bottom), the switcher's window with the apps (3: under the active layer; the inactive layer sits at 2, under it), the Home
// Screen (1). Finder's window: 200,100 600x500, its list in it. The active layer at 1034. Above the active layer two windows are hit-tested (the
// Dock's and the menu window); above the inactive one three (the switcher's too).
static DMNativeWindow *gFinder;
static UIView *gList;
static void KWorld(BOOL finderActive) {
    KReset();
    KWindow(@"SBHomeScreenWindow", 1);
    gSwitcher = KWindow(@"SBMainSwitcherWindow", 3);
    gSwitcher.rootViewController.view = KView(gSwitcher, @"SBFluidSwitcherContentView", gSwitcher.frame);   // (the apps' windows go in it)
    gNativeLayer = KWindow(@"MSBNativeLayer", finderActive ? 1034 : 2);
    gNativeLayer.rootViewController = [UIViewController new];
    gNativeRotator = KView(gNativeLayer, @"UIView", gNativeLayer.frame);
    gFinder = [[DMNativeWindow alloc] initWithFrame:CGRectMake(200, 100, 600, 500)];
    [gNativeRotator addSubview:gFinder]; [gNativeWindows addObject:gFinder];
    gList = KView(gFinder, @"UITableView", CGRectMake(200, 130, 600, 470));
    gDock = KWindow(@"SBFloatingDockWindow", 1035);
    gDockRoot = gDock.rootViewController.view;
    gPlatter = KView(gDockRoot, @"SBFloatingDockPlatterView", CGRectMake(383, 924, 600, 90));
    // (the status bar, the text effects window and the system gesture window answer every hit test: the walk leaves them out by their names)
    KView(KWindow(@"UIStatusBarWindow", 1036).rootViewController.view, @"UIStatusBar", CGRectMake(0, 0, kScreenW, kScreenH));
    KView(KWindow(@"UITextEffectsWindow", 1040).rootViewController.view, @"UIInputSetHostView", CGRectMake(0, 0, kScreenW, kScreenH));
    gMenuWin = KWindow(@"MSBMenuWindow", 1050);
    gCC = KWindow(@"SBControlCenterWindow", 1100); gCC.hidden = YES;
    gSysGesture = KWindow(@"_UISystemGestureWindow", 2000);
    KView(gSysGesture.rootViewController.view, @"UIView", CGRectMake(0, 0, kScreenW, kScreenH));
}
static double gTime = 100.0;
static UIScrollEvent *KScroll(CGPoint p, UIWindow *named, BOOL alsoToLayer) {
    UIScrollEvent *e = [UIScrollEvent new];
    e.tPoint = p; e.tNamed = named; e.tAlsoToLayer = alsoToLayer; e.timestamp = (gTime += 1.0 / 120.0);
    return e;
}
// one scroll as UIKit handles it: the window it goes to is asked three times (the windows to send it to, the recognisers to find, its location)
static UIWindow *KRoute(UIScrollEvent *e) {
    UIWindow *w = nil;
    for (int i = 0; i < 3; i++) { UIWindow *a = [e _windowServerHitTestWindow]; if (i && a != w) return (UIWindow *)[NSNull null]; w = a; }
    return w;
}
static void KInstall(void) {   // (the hook as DMScrollRoutingInit puts it in)
    static BOOL done; if (done) return; done = YES;
    Method m = class_getInstanceMethod([UIScrollEvent class], @selector(_windowServerHitTestWindow));
    o_DMScrollWS = (id (*)(id, SEL))method_setImplementation(m, (IMP)DMScrollWSWindow);
}

// ---- checks
static int gFails;
static void CHECK(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (!ok) gFails++; }
static NSString *KCost(void) { return [NSString stringWithFormat:@"%d window list(s), %lu window hit test(s)%@", gBuilds, (unsigned long)gHits.count, gHits.count ? [NSString stringWithFormat:@" (%@)", [gHits componentsJoinedByString:@" "]] : @""]; }
static void KZero(void) { gBuilds = gDecisions = 0; [gHits removeAllObjects]; }
// one scroll at p: where UIKit sends it, and what the decision cost
static UIWindow *KOne(CGPoint p, UIWindow *named, BOOL also) { KZero(); return KRoute(KScroll(p, named, also)); }

static void ScenarioOverApp(void) {
    KWorld(YES);
    UIWindow *to = KOne(CGPointMake(1100, 500), gSysGesture, NO);   // (right of Finder's window, over the app)
    CHECK(to == gSysGesture, @"a scroll over an app beside an active Finder window is left to the system gesture window (the app's own copy scrolls it)");
    CHECK(gDecisions == 1 && gBuilds == 0 && gHits.count == 0, [NSString stringWithFormat:@"  ... decided once with no window walk: %d decision(s), %@ (before the fix: 1 window list, 2 window hit tests)", gDecisions, KCost()]);
    KWorld(NO);
    to = KOne(CGPointMake(1100, 500), gSysGesture, NO);
    CHECK(to == gSysGesture && gBuilds == 0 && gHits.count == 0, [NSString stringWithFormat:@"  ... the same with Finder inactive behind the apps: %@ (before: 1 list, 3 hit tests)", KCost()]);
}
static void ScenarioOverApp120(void) {
    KWorld(YES);
    int left = 0, asks = 0;
    KZero();
    for (int i = 0; i < 120; i++) { UIScrollEvent *e = KScroll(CGPointMake(900 + i, 300 + i), gSysGesture, NO); if (KRoute(e) == gSysGesture) left++; asks += e.tAsks; }
    CHECK(left == 120 && gDecisions == 120, [NSString stringWithFormat:@"a second of scrolling over an app at 120 Hz with Finder open: 120 scrolls left to the system gesture window, %d decision(s) for %d asks (one per scroll)", gDecisions, asks]);
    CHECK(gBuilds == 0 && gHits.count == 0, [NSString stringWithFormat:@"  ... no window walked: %d window list(s), %lu window hit test(s) (before the fix: 120 and 240)", gBuilds, (unsigned long)gHits.count]);
}
static void ScenarioMenuBar(void) {
    KWorld(YES);
    UIWindow *to = KOne(CGPointMake(300, 10), gSysGesture, NO);
    CHECK(to == gSysGesture && gBuilds == 0 && gHits.count == 0, [NSString stringWithFormat:@"a scroll on the menu bar above Finder's window is not Finder's, with no window walk: %@ (before: 1 list, 2 hit tests)", KCost()]);
}
static void ScenarioOverList(void) {
    KWorld(YES);
    UIWindow *to = KOne(CGPointMake(500, 400), gSysGesture, NO);
    CHECK(to == gNativeLayer, @"a scroll over Finder's list, nothing above it there: named for our layer (UIKit scrolls the list itself), as before");
    CHECK(gBuilds == 1 && [[gHits componentsJoinedByString:@" "] isEqualToString:@"SBFloatingDockWindow MSBMenuWindow"], [NSString stringWithFormat:@"  ... the windows above the layer asked once, as before: %@", KCost()]);
    KZero(); int ours = 0, asks = 0;
    for (int i = 0; i < 120; i++) { UIScrollEvent *e = KScroll(CGPointMake(400 + i, 300), gSysGesture, NO); if (KRoute(e) == gNativeLayer) ours++; asks += e.tAsks; }
    CHECK(ours == 120 && gDecisions == 120 && gBuilds == 120, [NSString stringWithFormat:@"  ... 120 scrolls over the list: %d to the layer, %d decisions, %d window lists for %d asks (one per scroll, as before)", ours, gDecisions, gBuilds, asks]);
    to = KOne(CGPointMake(500, 400), nil, NO);
    CHECK(to == gNativeLayer, @"  ... named for no window: ours as well, as before");
}
static void ScenarioInactive(void) {
    KWorld(NO);
    UIView *app = KView(gSwitcher.rootViewController.view, @"SBSceneLayoutView", CGRectMake(600, 50, 700, 900));   // (an app's window over Finder's right part)
    UIWindow *to = KOne(CGPointMake(700, 400), gSysGesture, NO);
    CHECK(to == gSysGesture && gBuilds == 1 && [gHits containsObject:@"SBMainSwitcherWindow"], [NSString stringWithFormat:@"Finder inactive behind an app window that covers it at the pointer: the app's (the switcher's window takes the point), as before: %@", KCost()]);
    to = KOne(CGPointMake(300, 400), gSysGesture, NO);
    CHECK(to == gNativeLayer, @"  ... on Finder's part that no app window covers: ours, as before");
    app.hidden = YES;
    to = KOne(CGPointMake(700, 400), gSysGesture, NO);
    CHECK(to == gNativeLayer, @"  ... the app window gone: the switcher's own content view answers, which is no window -- ours, as before");
}
static void ScenarioDock(void) {
    KWorld(YES);
    gFinder.frame = CGRectMake(200, 100, 600, 880); gList.frame = CGRectMake(200, 130, 600, 850);   // (reaching under the Dock's platter)
    UIWindow *to = KOne(CGPointMake(500, 950), gSysGesture, NO);
    CHECK(to == gSysGesture && gBuilds == 1, [NSString stringWithFormat:@"Finder's window under the Dock's platter, the pointer on the platter: the Dock's, as before: %@", KCost()]);
    to = KOne(CGPointMake(500, 910), gSysGesture, NO);
    CHECK(to == gNativeLayer, @"  ... just above the platter, where only the Dock window's root view answers: Finder's, as before");
}
static void ScenarioMenus(void) {
    KWorld(YES);
    KView(gMenuWin.rootViewController.view, @"UIControl", CGRectMake(250, 24, 220, 300));   // (a menu bar menu over Finder)
    UIWindow *to = KOne(CGPointMake(300, 200), gSysGesture, NO);
    CHECK(to == gSysGesture && [gHits containsObject:@"MSBMenuWindow"], [NSString stringWithFormat:@"a menu bar menu over Finder at the pointer: the menu's, as before: %@", KCost()]);
    to = KOne(CGPointMake(600, 400), gSysGesture, NO);
    CHECK(to == gNativeLayer, @"  ... over Finder beside the menu: Finder's, as before");
}
static void ScenarioItemMenu(void) {
    KWorld(YES);
    gOverlay = KView(gNativeLayer, @"UIView", gNativeLayer.frame);   // (a Finder item menu: its catch-all over the whole layer)
    UIWindow *to = KOne(CGPointMake(1100, 500), gSysGesture, NO);
    CHECK(to == gNativeLayer && gBuilds == 1, [NSString stringWithFormat:@"a Finder item menu open: a scroll over the app area is the menu's (ours), as before: %@", KCost()]);
    gOverlay = KView(gMenuWin.rootViewController.view, @"UIControl", CGRectMake(250, 24, 220, 300));   // (a menu bar menu: not in the layer)
    to = KOne(CGPointMake(1100, 500), gSysGesture, NO);
    CHECK(to == gSysGesture && gBuilds == 0, [NSString stringWithFormat:@"  ... a menu bar menu open elsewhere: a scroll over the app is the app's, no window walk: %@", KCost()]);
}
static void ScenarioSheet(void) {
    KWorld(YES);
    gNativeLayer.rootViewController.presentedViewController = [UIViewController new];
    gNativeLayer.rootViewController.presentedViewController.view = KView(gNativeLayer, @"UIDimmingView", gNativeLayer.frame);   // (Quick Look over the windows)
    UIWindow *to = KOne(CGPointMake(1100, 500), gSysGesture, NO);
    CHECK(to == gNativeLayer && gBuilds == 1, [NSString stringWithFormat:@"a sheet presented over the native windows: a scroll anywhere below the bar is the sheet's (ours), as before: %@", KCost()]);
}
static void ScenarioCatchAlls(void) {
    KWorld(YES);
    KView(KWindow(@"SBSwitcherPassThroughWindow", 1040).rootViewController.view, @"SBFPassThroughView", CGRectMake(0, 0, kScreenW, kScreenH));
    UIWindow *to = KOne(CGPointMake(500, 400), gSysGesture, NO);
    CHECK(to == gNativeLayer, [NSString stringWithFormat:@"windows that answer every hit test (the system gesture window, text effects, the status bar, a pass-through view) do not take a scroll over Finder, as before: %@", KCost()]);
    to = KOne(CGPointMake(1100, 500), gSysGesture, NO);
    CHECK(to == gSysGesture && gBuilds == 0 && gHits.count == 0, [NSString stringWithFormat:@"  ... and over the app none of them is asked: %@", KCost()]);
}
static void ScenarioEarly(void) {   // (answered before either test, in both orders)
    struct { NSString *what; void (^set)(void); UIWindow *(^named)(void); BOOL also; } cases[] = {
        { @"the layer hidden (no native window on screen)", ^{ gNativeLayer.hidden = YES; }, ^{ return gSysGesture; }, NO },
        { @"the native windows faded out of the way (App Switcher, App Library)", ^{ gNativeAway = YES; }, ^{ return gSysGesture; }, NO },
        { @"the windows' touches off", ^{ gNativeRotator.userInteractionEnabled = NO; }, ^{ return gSysGesture; }, NO },
        { @"named for our layer (UIKit's already)", ^{}, ^{ return gNativeLayer; }, NO },
        { @"named for Control Center's window", ^{ gCC.hidden = NO; }, ^{ return gCC; }, NO },
        { @"the window server sends the layer its own copy", ^{}, ^{ return gSysGesture; }, YES },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        KWorld(YES); cases[i].set();
        UIWindow *named = cases[i].named();
        UIWindow *to = KOne(CGPointMake(500, 400), named, cases[i].also);
        CHECK(to == named && gBuilds == 0 && gHits.count == 0, [NSString stringWithFormat:@"%@: over Finder's list, the window it was named for, no window walk (as before): %@", cases[i].what, KCost()]);
    }
}

// ---- random worlds (trace): one line per scroll -- decision, whether our layer's own test hits, window lists, the windows hit-tested
static double R(void) { return drand48(); }
static CGRect RRect(void) { CGFloat x = R() * kScreenW, y = R() * kScreenH; return CGRectMake(x - 100, y - 100, 80 + R() * 700, 60 + R() * 600); }
static void RandomWorld(void) {
    KWorld(R() < 0.6);
    if (R() < 0.1) gNativeLayer.hidden = YES;
    if (R() < 0.05) gNativeLayer.alpha = 0.0;
    if (R() < 0.1) gNativeAway = YES;
    if (R() < 0.05) gNativeRotator.alpha = 0.0;
    if (R() < 0.05) gNativeRotator.userInteractionEnabled = NO;
    gFinder.frame = RRect(); gList.frame = CGRectInset(gFinder.frame, 0, 15);
    if (R() < 0.15) gFinder.hidden = YES;
    for (int i = 0, n = (int)(R() * 3); i < n; i++) {   // (more native windows: Activity Monitor, Quick Look, TextEdit, other folders)
        DMNativeWindow *w = [[DMNativeWindow alloc] initWithFrame:RRect()];
        [gNativeRotator addSubview:w]; [gNativeWindows addObject:w];
        if (R() < 0.5) KView(w, @"UITableView", CGRectInset(w.frame, 0, 15));
        if (R() < 0.15) w.hidden = YES;
    }
    double o = R();
    if (o < 0.15) gOverlay = KView(gNativeLayer, @"UIView", gNativeLayer.frame);
    else if (o < 0.3) gOverlay = KView(gMenuWin.rootViewController.view, @"UIControl", RRect());
    if (R() < 0.1) {
        gNativeLayer.rootViewController.presentedViewController = [UIViewController new];
        gNativeLayer.rootViewController.presentedViewController.view = KView(gNativeLayer, @"UIDimmingView", R() < 0.7 ? gNativeLayer.frame : RRect());
    }
    if (R() < 0.3) gPlatter.hidden = YES;
    gDock.windowLevel = R() < 0.5 ? 1035 : 25;
    if (R() < 0.2) gCC.hidden = NO;
    NSArray *apps = @[@"SBSceneLayoutView", @"SBAppWindowView", @"SBFPassThroughView", @"SBFluidSwitcherContentView"];
    for (int i = 0, n = (int)(R() * 4); i < n; i++) KView(gSwitcher.rootViewController.view, apps[(int)(R() * apps.count)], RRect());
    if (R() < 0.3) gSwitcher.windowLevel = 1040;   // (the App Switcher's window over the layer)
    if (R() < 0.3) KView(gCC.rootViewController.view, @"CCUIModuleView", RRect());
    NSArray *extra = @[@"SBBannerWindow", @"SBSystemApertureWindow", @"SBSwitcherPassThroughWindow", @"UIRemoteKeyboardWindow", @"SBRecordingIndicatorWindow"];
    for (int i = 0, n = (int)(R() * 3); i < n; i++) {
        UIWindow *w = KWindow(extra[(int)(R() * extra.count)], R() < 0.7 ? 1010 + R() * 80 : R() * 10);
        if (R() < 0.6) KView(w.rootViewController.view, R() < 0.3 ? @"SBFPassThroughView" : @"UIView", RRect());
        if (R() < 0.2) w.alpha = 0.0;
        if (R() < 0.1) w.rootViewController = nil;   // (a window with no root view controller: it answers itself)
    }
    for (NSUInteger i = gWindows.count - 1; i > 0; i--) [gWindows exchangeObjectAtIndex:i withObjectAtIndex:(NSUInteger)(R() * (i + 1))];   // (in any order)
}
static void Trace(long seed, int n) {
    srand48(seed);
    KInstall();
    int line = 0;
    for (int world = 0; world < n; world++) {
        RandomWorld();
        for (int k = 0; k < 20; k++) {
            CGPoint p = CGPointMake(R() * kScreenW, R() * kScreenH);
            double q = R();
            UIWindow *named = q < 0.75 ? gSysGesture : q < 0.85 ? nil : q < 0.92 ? gNativeLayer : gCC;
            BOOL also = R() < 0.15;
            UIWindow *to = KOne(p, named, also);
            int builds = gBuilds, decisions = gDecisions; NSString *hits = [gHits componentsJoinedByString:@"+"];
            BOOL layerHit = DMNativeLayerHitTest(gNativeLayer, @selector(hitTest:withEvent:), p, nil) != nil;   // (our layer's own test at that point, as the decision asks it)
            printf("s%d w%d %s decided %d layer %d lists %d hits %s\n", line++, world, to == gNativeLayer ? "ours" : to == (UIWindow *)[NSNull null] ? "MIXED" : "theirs", decisions, layerHit, builds, hits.length ? hits.UTF8String : "-");
        }
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gClasses = [NSMutableDictionary dictionary];
        if (argc >= 4 && !strcmp(argv[1], "trace")) { Trace(atol(argv[2]), atoi(argv[3])); return 0; }
        NSDictionary<NSString *, void (^)(void)> *all = @{
            @"overapp": ^{ ScenarioOverApp(); }, @"overapp120": ^{ ScenarioOverApp120(); }, @"menubar": ^{ ScenarioMenuBar(); },
            @"overlist": ^{ ScenarioOverList(); }, @"inactive": ^{ ScenarioInactive(); }, @"dock": ^{ ScenarioDock(); }, @"menus": ^{ ScenarioMenus(); },
            @"itemmenu": ^{ ScenarioItemMenu(); }, @"sheet": ^{ ScenarioSheet(); }, @"catchalls": ^{ ScenarioCatchAlls(); }, @"early": ^{ ScenarioEarly(); },
        };
        if (argc < 2 || !strcmp(argv[1], "list")) { for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) printf("%s\n", k.UTF8String); return 0; }
        void (^s)(void) = all[@(argv[1])];
        if (!s) { printf("FAIL  no scenario %s\n", argv[1]); return 1; }
        KInstall();
        s();
        return gFails;
    }
}
