// NativeWindow.h -- our own Mac windows, drawn and run inside SpringBoard (2026-09-30), included into StatusBar.x.
// The first native window is Finder (Finder.h). A native window is not an app and not a window engine's window: it looks and behaves the
// same whichever engine runs (Stage Manager, Aerial, MilkyWay, Zetsu, or none), and it is always a window.
//  - All native windows live in ONE layer window (MSBNativeLayer, SpringBoard's own active-interface-orientation window class, like our menu
//    window), each a view with a title bar, traffic lights and resize grips. Touches outside them fall through to what is below.
//  - The layer has two places, like a Mac's window order reduced to what SpringBoard allows: while a native window is active it sits just above
//    the engine's app windows (below our menu bar, and below the Dock with Stage Manager, as on a Mac); a touch in an app window or on the Home
//    Screen makes it inactive and the layer drops behind every app, just above the Home Screen.
//  - While one is active the menu bar shows its app's name and menus (DMNativeActiveApp), as if it were the front app.

@class DMNativeWindow;
static NSMutableArray<DMNativeWindow *> *gNativeWindows;   // front last
static DMNativeWindow *gNativeActive;                      // the active one (lights colored, menu bar shows its menus), or nil
static NSString *gNativeFrontAtActivation;                 // the app in front when a native window became active (DMNativeTick: a DIFFERENT app coming
static CFTimeInterval gNativeActivatedAt;                  //  to the front makes the native windows inactive)
static UIWindow *gNativeLayer;
static const CGFloat kNWTitleH = 30.0;
static const CGFloat kNWCorner = 10.0;
static const CGFloat kNWGrip = 22.0;    // the resize corners' touch size
static const CGFloat kNWBackLevel = -1.5;   // above the Home Screen (-2), below every app (0 and up)

static void DMNativeApplyLevel(void);
static CGRect DMNativeDesktop(void);
@interface UIResponder (DMNativeFirst)
+ (BOOL)dm_currentFirstResponderIsIn:(UIWindow *)w;
@end
@implementation UIResponder (DMNativeFirst)
+ (BOOL)dm_currentFirstResponderIsIn:(UIWindow *)w {
    UIResponder *r = nil;
    @try { r = [w valueForKey:@"firstResponder"]; } @catch (id e) {}
    return [r isKindOfClass:[UITextField class]] || [r isKindOfClass:[UITextView class]];
}
@end
static void DMNativeMenuBarChanged(void);

@interface DMNativeWindow : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *appName;             // what the menu bar shows while it is active ("Finder")
@property (nonatomic, strong, readonly) UIView *titleBar;  // the title bar: subclasses may add their toolbar items to it
@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, assign) CGSize minSize;
@property (nonatomic, assign) CGFloat titleBarHeight;      // 30 (a plain title bar); a unified toolbar is taller (Finder: 52)
@property (nonatomic, assign) BOOL fullSizeContent;        // the content reaches under the title bar (a sidebar up to the top, like a Mac's Finder)
@property (nonatomic, assign) BOOL showsTitle;             // the centred title in the title bar (NO when a toolbar shows it)
@property (nonatomic, assign) CGRect restoreFrame;         // the frame before Zoom filled the desktop (CGRectNull: not zoomed)
@property (nonatomic, copy) void (^onClose)(DMNativeWindow *w);
@property (nonatomic, assign) BOOL dm_wasMinimized;
@property (nonatomic, copy) void (^onActiveChanged)(DMNativeWindow *w, BOOL active);
@property (nonatomic, copy) NSString *layoutName;          // the Window menu's layout it was put in ("left", "right"...): kept after a turn; nil once moved
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame;
- (BOOL)dm_takesPoint:(CGPoint)q;                          // (the window, or one of its resize grips, which reach a little outside it)
- (void)show;          // on screen, in front, active
- (void)activate;
- (void)close;
- (void)minimize;
- (void)zoom;
- (BOOL)dm_isChrome:(UIView *)v;   // (v is in the title bar or a resize corner)
@end
// A sheet, like a Mac's: a panel dropping from under the title bar over the dimmed window (UIKit alerts presented on the layer would not turn
// with the Home Screen, see DMNativeUpdateRotation). field: the text of a text field in it, or nil for none. then: the action's handler.
@interface DMNativeWindow (Sheet)
- (void)sheetTitle:(NSString *)title message:(NSString *)message field:(NSString *)field action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(NSString *text))then;
- (void)sheetTitle:(NSString *)title message:(NSString *)message field:(NSString *)field action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(NSString *text))then cancel:(void (^)(void))cancel;
- (BOOL)hasSheet;
@end

// ---- the layer ------------------------------------------------------------------------------------------------------------------------------
// The layer's root controller: first responder while a native window is active, so a hardware keyboard's shortcuts reach that window
// (its -dm_keyCommands, sent on to it by -forwardingTargetForSelector:).
@interface DMNativeKeyView : UIView
@end
static DMNativeKeyView *gNativeKeys;
@implementation DMNativeKeyView
- (BOOL)canBecomeFirstResponder { return YES; }
- (NSArray<UIKeyCommand *> *)keyCommands {
    id w = gNativeActive;
    return [w respondsToSelector:@selector(dm_keyCommands)] ? ((NSArray *(*)(id, SEL))objc_msgSend)(w, @selector(dm_keyCommands)) : @[];
}
- (id)forwardingTargetForSelector:(SEL)sel { return [gNativeActive respondsToSelector:sel] ? gNativeActive : [super forwardingTargetForSelector:sel]; }
- (BOOL)respondsToSelector:(SEL)sel { return [super respondsToSelector:sel] || (NSStringFromSelector(sel).length > 6 && [NSStringFromSelector(sel) hasPrefix:@"dm_key"] && [gNativeActive respondsToSelector:sel]); }
@end
// SpringBoard holds the keyboard focus while a native window is active (normally the front app has it), and gives it back when it is not:
// -lockFocusToSpringBoardWindowScene:forReason: on iPadOS 16, -lockFocusToSpringBoardForReason: on iPadOS 15.
static id gNativeFocusLock;
static void DMNativeFocus(BOOL take) {
    if (!take) {
        id l = gNativeFocusLock; gNativeFocusLock = nil;
        if (!l) return;
        if ([l respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(l, @selector(invalidate));
        DMLog(@"[native] keyboard focus given back to the apps");
        return;
    }
    if (gNativeFocusLock) return;
    DM_FEATURE_MARK("native-focus-lock");
    id ws = nil; Class wsc = objc_getClass("SBMainWorkspace");
    if (wsc && [(id)wsc respondsToSelector:@selector(sharedInstance)]) ws = ((id (*)(id, SEL))objc_msgSend)((id)wsc, @selector(sharedInstance));
    SEL kfcSel = NSSelectorFromString(@"keyboardFocusController");
    id kfc = [ws respondsToSelector:kfcSel] ? ((id (*)(id, SEL))objc_msgSend)(ws, kfcSel) : nil;
    SEL l16 = NSSelectorFromString(@"lockFocusToSpringBoardWindowScene:forReason:"), l15 = NSSelectorFromString(@"lockFocusToSpringBoardForReason:");
    @try {
        if ([kfc respondsToSelector:l16] && gNativeLayer.windowScene) gNativeFocusLock = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, l16, gNativeLayer.windowScene, @"MacStatusBar Finder");
        else if ([kfc respondsToSelector:l15]) gNativeFocusLock = ((id (*)(id, SEL, id))objc_msgSend)(kfc, l15, @"MacStatusBar Finder");
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[native] keyboard focus lock threw %@", e]); }
    DMLog([NSString stringWithFormat:@"[native] keyboard focus to SpringBoard: %@", gNativeFocusLock ? NSStringFromClass([gNativeFocusLock class]) : @"no lock"]);
}
static BOOL DMNativeYes(id self, SEL _cmd) { return YES; }
static void DMNativeUpdateRotation(void);
static void DMNativeRelayoutForTurn(void);
// (the layer's own layout pass: the system turns the window inside its rotation animation, so the container and the windows follow in the same
//  animation, at once -- not on the next timer tick)
static void DMNativeLayerLayout(UIWindow *self, SEL _cmd) {
    struct objc_super sup = { self, [self superclass] };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    DMNativeUpdateRotation();
    DMNativeRelayoutForTurn();
}
static id DMNativeLayerHitTest(UIWindow *self, SEL _cmd, CGPoint p, UIEvent *e) {
    if (gOverlay && gOverlay.superview && [gOverlay isDescendantOfView:self]) {   // (a Finder item menu is open: its catch-all takes every touch, closing it)
        struct objc_super sup = { self, [self superclass] };
        return ((id (*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
    }
    if (self.rootViewController.presentedViewController) {   // (a Quick Look panel, an alert, a share sheet: modal, it takes every touch)
        struct objc_super sup = { self, [self superclass] };
        id hit = ((id (*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
        if (DMTestFlag("/tmp/macstatusbar-debug") && e) DMLog([NSString stringWithFormat:@"[native] presented: hit at %@ -> %@", NSStringFromCGPoint(p), NSStringFromClass([hit class])]);
        return hit;
    }
    // (never in the menu bar's strip: a window whose top sits at the desktop's top grew its touch area 11 pt up over the menu bar on every side,
    //  and on iPadOS 15 the menu bar (UIStatusBarWindow, 999) is below the active layer -- the lower half of the menu titles and status items did
    //  nothing, M1 30 Sep. Only the two bottom resize grips reach outside a window now.)
    CGPoint sp = [self convertPoint:p toCoordinateSpace:self.screen.coordinateSpace];
    if (sp.y < CGRectGetMinY(DMNativeDesktop())) return nil;
    for (DMNativeWindow *w in [gNativeWindows reverseObjectEnumerator]) {
        if (w.hidden) continue;
        CGPoint q = [self convertPoint:p toView:w];
        if ([w dm_takesPoint:q]) {
            struct objc_super sup = { self, [self superclass] };
            UIView *hit = ((id (*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
            return hit ?: w;
        }
    }
    return nil;   // (outside every native window: the touch goes to whatever is below)
}
static UIWindow *DMNativeLayer(void) {
    if (gNativeLayer) return gNativeLayer;
    @try {
        Class base = objc_getClass("SBMainScreenActiveInterfaceOrientationWindow");
        SEL initRole = NSSelectorFromString(@"initWithRole:debugName:");
        if (!base || ![base instancesRespondToSelector:initRole]) { DMLog(@"[native] the window class or initializer is missing"); return nil; }
        Class sub = objc_getClass("MSBNativeLayer");
        if (!sub) {
            sub = objc_allocateClassPair(base, "MSBNativeLayer", 0);
            class_addMethod(sub, @selector(hitTest:withEvent:), (IMP)DMNativeLayerHitTest, "@@:{CGPoint=dd}@");
            // (it has to be able to become the key window, or a text field in a native window never gets the keys: SpringBoard's
            //  orientation-window class refused, the layer stayed non-key while Search was first responder)
            class_addMethod(sub, @selector(canBecomeKeyWindow), (IMP)DMNativeYes, "B@:");
            class_addMethod(sub, @selector(layoutSubviews), (IMP)DMNativeLayerLayout, "v@:");
            class_addMethod(sub, NSSelectorFromString(@"_canBecomeKeyWindow"), (IMP)DMNativeYes, "B@:");
            objc_registerClassPair(sub);
        }
        UIWindow *w = ((id (*)(id, SEL, id, id))objc_msgSend)([sub alloc], initRole, @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarNativeWindows");
        w.backgroundColor = [UIColor clearColor];
        w.windowLevel = kNWBackLevel;
        w.hidden = YES;
        if (!w.rootViewController) w.rootViewController = [UIViewController new];   // (a presenter for alerts and share sheets)
        w.rootViewController.view.backgroundColor = [UIColor clearColor];
        gNativeKeys = [[DMNativeKeyView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];   // (the keyboard's first responder while a native window is active)
        gNativeKeys.userInteractionEnabled = NO;
        [(w.rootViewController.view ?: w) addSubview:gNativeKeys];
        w.rootViewController.view.backgroundColor = [UIColor clearColor];
        gNativeLayer = w;
        DMSnapInvalidate();
        DMLog([NSString stringWithFormat:@"[native] layer window made: %@ frame %@", NSStringFromClass([w class]), NSStringFromCGRect(w.frame)]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[native] layer window failed: %@", e]); }
    return gNativeLayer;
}
// The windows live in a container with the screen's shape, turned with the screen. On iPadOS 16 SpringBoard's orientation window keeps its
// portrait bounds while the scene is turned (our menu window has the same, see DMMenuHost): content put in it directly stayed portrait when the
// Home Screen turned. The container is turned to how the layer really lies on the screen (UIKit's own conversion), like the menus' rotator.
static UIView *gNativeRotator;
static void DMNativeUpdateRotation(void) {
    UIWindow *l = gNativeLayer; if (!l || !gNativeRotator) return;
    // (only measured while the layer is on screen: a hidden window keeps stale bounds -- iPadOS 15 turns this window class itself once it
    //  shows, and a turn worked out while hidden launched Finder sideways on the M1)
    if (l.hidden) return;
    CGSize screen = [UIScreen mainScreen].bounds.size, win = l.bounds.size;
    CGFloat angle = 0;
    id<UICoordinateSpace> scr = [UIScreen mainScreen].coordinateSpace;
    CGPoint o = [l convertPoint:CGPointZero toCoordinateSpace:scr], x = [l convertPoint:CGPointMake(100, 0) toCoordinateSpace:scr];
    if (hypot(x.x - o.x, x.y - o.y) > 50.0) angle = -round(atan2(x.y - o.y, x.x - o.x) / M_PI_2) * M_PI_2;
    CGAffineTransform t = fabs(angle) > 0.01 ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity;
    CGRect b = CGRectMake(0, 0, fabs(angle) > 0.01 ? screen.width : win.width, fabs(angle) > 0.01 ? screen.height : win.height);
    if (CGAffineTransformEqualToTransform(gNativeRotator.transform, t) && CGRectEqualToRect(gNativeRotator.bounds, b)) return;
    gNativeRotator.transform = CGAffineTransformIdentity;
    gNativeRotator.bounds = b;
    gNativeRotator.center = CGPointMake(win.width / 2.0, win.height / 2.0);
    gNativeRotator.transform = t;
    DMLog([NSString stringWithFormat:@"[native] turned: container %@ angle %.0f (layer %@, screen %@)", NSStringFromCGRect(b), angle * 180.0 / M_PI, NSStringFromCGSize(win), NSStringFromCGSize(screen)]);
}
static UIView *DMNativeHost(void) {
    UIWindow *l = DMNativeLayer(); if (!l) return nil;
    UIView *root = l.rootViewController.view ?: l;
    if (!gNativeRotator) { gNativeRotator = [UIView new]; gNativeRotator.backgroundColor = [UIColor clearColor]; }
    if (gNativeRotator.superview != root) [root addSubview:gNativeRotator];
    DMNativeUpdateRotation();
    return gNativeRotator;
}
// Where the app windows are right now: the highest level any engine's app window uses (Stage Manager's switcher window 5, Aerial / MilkyWay
// window layer, Zetsu's own windows). The active native window sits just above; our menu bar (1040) stays above everything.
static CGFloat DMNativeFrontLevel(void) {
    CGFloat top = 5.0;
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || w == gNativeLayer || w.windowLevel >= kMenuWindowLevel - 1.0) continue;
        NSString *c = NSStringFromClass([w class]);
        if ([c isEqualToString:@"AerialWindow"] || [c containsString:@"MilkyWay"] || DMIsZetsuWindow(w)) top = MAX(top, w.windowLevel);
    }
    CGFloat want = MIN(top + 1.0, kMenuWindowLevel - 2.0);
    // (a status bar menu or dialog is open: the native windows stand just below the window it is shown in, like the engines' windows -- on
    //  iPadOS 15 menus open in the status bar's own window (999), under an active Finder (1034): the menu was hidden behind Finder, M1 30 Sep)
    UIWindow *menuHost = gOverlay.window;
    if (menuHost && menuHost != gNativeLayer) want = MIN(want, menuHost.windowLevel - 0.5);
    return want;
}
static void DMFinderPublishWindowCount(void);
static void DMNativeApplyLevel(void) {
    DMFinderPublishWindowCount();   // (the Dock's Finder dot: a window opened, closed or minimized passes here)
    if (!gNativeLayer) return;
    BOOL any = NO; for (DMNativeWindow *w in gNativeWindows) if (!w.hidden) any = YES;
    gNativeLayer.hidden = !any;
    CGFloat want = gNativeActive ? DMNativeFrontLevel() : kNWBackLevel;
    if (fabs(gNativeLayer.windowLevel - want) > 0.01) {
        gNativeLayer.windowLevel = want;
        DMLog([NSString stringWithFormat:@"[native] layer at level %.1f (%@)", want, gNativeActive ? [@"active: " stringByAppendingString:gNativeActive.title ?: @"?"] : @"inactive"]);
    }
}
// The native window that acts as the front app for the menu bar, or nil.
static DMNativeWindow *DMNativeActiveApp(void) { return (gNativeActive && !gNativeActive.hidden && !gNativeLayer.hidden) ? gNativeActive : nil; }
// Traffic lights: each native window's lights stand for it alone ("native:<address>"), and while one is active that is the active window for every
// set of lights (DMActiveBundleForLights) -- exactly one colored set on the screen, as on a Mac.
static NSString *DMNativeLightsTokenFor(DMNativeWindow *w) { return w ? [NSString stringWithFormat:@"native:%p", w] : nil; }
static NSString *DMNativeLightsToken(void) { return DMNativeLightsTokenFor(DMNativeActiveApp()); }
static void DMNativeSetActive(DMNativeWindow *w) {
    if (!w) DMNativeFocus(NO);   // (no native window active: the keyboard goes back to the apps, whatever the path here)
    if (w == gNativeActive) { DMNativeApplyLevel(); return; }
    DMNativeWindow *was = gNativeActive;
    gNativeActive = w;
    if (was) { [was setNeedsLayout]; if (was.onActiveChanged) was.onActiveChanged(was, NO); }
    if (w && !was) { gNativeFrontAtActivation = [DMActiveApp() bundleIdentifier] ?: @""; gNativeActivatedAt = CACurrentMediaTime(); }
    if (w) {
        [gNativeWindows removeObjectIdenticalTo:w]; [gNativeWindows addObject:w];
        [w.superview bringSubviewToFront:w];
        [w setNeedsLayout]; if (w.onActiveChanged) w.onActiveChanged(w, YES);
        DMNativeFocus(YES);
        if (!gNativeLayer.isKeyWindow) [gNativeLayer makeKeyWindow];
        if (!gNativeLayer.rootViewController.presentedViewController && ![UIResponder dm_currentFirstResponderIsIn:gNativeLayer]) [gNativeKeys becomeFirstResponder];
    } else {
        if ([gNativeLayer isKeyWindow]) [gNativeLayer endEditing:YES];
        [gNativeKeys resignFirstResponder];
        DMNativeFocus(NO);
    }
    DMNativeApplyLevel();
    DMNativeMenuBarChanged();
    DMLightGroupsRefresh();   // (the lights: this window's colored, every other window's grey)
}
// SpringBoard saw a touch begin (-[SpringBoard sendEvent:]): in a native window it becomes active; in an app window or on the Home Screen the
// native windows become inactive. Touches on our menu bar, menus, the Dock or the system's own overlays change nothing (Finder's menus are used
// from the menu bar while Finder stays active).
// A window above the native layer that really takes a touch there (our menus, the Dock, an alert) -- not SpringBoard's full-screen helpers that
// answer every hit test (the keyboard's text-effects windows, the system gesture window, the status bar, Stage Manager's pass-through views).
static UIWindow *DMNativeWindowTaking(CGPoint p, CGFloat aboveLevel) {
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || w == gNativeLayer || w.windowLevel <= aboveLevel || w.alpha < 0.01) continue;
        NSString *c = NSStringFromClass([w class]);
        if (DMSBIsBarWindowName(c) || [c isEqualToString:@"_UISystemGestureWindow"] || [c containsString:@"Recording"] || [c containsString:@"TextEffects"]
            || [c containsString:@"RemoteKeyboard"] || [c containsString:@"InputWindow"]) continue;
        UIView *h = [w hitTest:[w convertPoint:p fromCoordinateSpace:w.screen.coordinateSpace] withEvent:nil];   // (p: the SCREEN's point)
        if (!h || h == w || h == w.rootViewController.view || [NSStringFromClass([h class]) containsString:@"PassThrough"] || [NSStringFromClass([h class]) isEqualToString:@"SBFluidSwitcherContentView"]) continue;
        return w;
    }
    return nil;
}
// The native window a touch at this SCREEN point is for, or nil: a visible native window there that nothing above it takes (while inactive the
// layer sits behind the apps: an app window over it keeps its touches). A panel or sheet up over Finder: the active window (modal, every touch).
static BOOL gNativeLastHitChrome;   // (the last DMNativeWindowAtScreenPoint answer was on a window's title bar or resize corner)
static DMNativeWindow *DMNativeWindowAtScreenPoint(CGPoint p) {
    gNativeLastHitChrome = NO;
    if (!gNativeLayer || gNativeLayer.hidden || gNativeAway || !gNativeWindows.count || gNativeRotator.alpha < 0.01) return nil;
    CGPoint lp = [gNativeLayer convertPoint:p fromCoordinateSpace:gNativeLayer.screen.coordinateSpace];
    UIView *hit = DMNativeLayerHitTest(gNativeLayer, @selector(hitTest:withEvent:), lp, nil);
    if (!hit) return nil;
    for (UIView *v = hit; v; v = v.superview) if ([v isKindOfClass:[DMNativeWindow class]]) { gNativeLastHitChrome = [(DMNativeWindow *)v dm_isChrome:hit]; break; }
    if (!gNativeActive && DMNativeWindowTaking(p, gNativeLayer.windowLevel)) return nil;
    for (UIView *v = hit; v; v = v.superview) if ([v isKindOfClass:[DMNativeWindow class]]) return (DMNativeWindow *)v;
    return gNativeActive;
}
// The same for a touch SpringBoard's system gestures see (-[SBFluidSwitcherGestureManager gestureRecognizer:shouldReceiveTouch:]): its screen
// point from the touch's own window (the system gesture window is portrait on iPadOS 16 in landscape). Asked once per recogniser for the same
// touch: the answer is kept for that touch.
static DMNativeWindow *DMNativeWindowForTouch(UITouch *t, BOOL *onChrome) {
    static __weak UITouch *lastTouch; static NSTimeInterval lastStamp; static __weak DMNativeWindow *lastWin; static BOOL lastChrome;
    if (onChrome) *onChrome = NO;
    if (!t) return nil;
    if (t == lastTouch && t.timestamp == lastStamp) { if (onChrome) *onChrome = lastChrome; return lastWin; }
    UIScreen *screen = t.window.screen ?: [UIScreen mainScreen];
    if (screen != [UIScreen mainScreen]) return nil;   // (native windows are on the iPad's screen only)
    CGPoint p = t.window ? [t.window convertPoint:[t locationInView:t.window] toCoordinateSpace:screen.coordinateSpace] : [t locationInView:nil];
    DMNativeWindow *w = DMNativeWindowAtScreenPoint(p);
    lastTouch = t; lastStamp = t.timestamp; lastWin = w; lastChrome = w && gNativeLastHitChrome;
    if (onChrome) *onChrome = lastChrome;
    return w;
}
__attribute__((noinline)) static void DMNativeTouchBegan(UITouch *t) {   // (kept a symbol of its own: the crash guard names it -- tools/test-crashstep.sh)
    if (!gNativeLayer || gNativeLayer.hidden || !gNativeWindows.count) return;
    DM_FEATURE_MARK("native-touch-activation");
    // (only a finger (direct) or a pointer click (indirect pointer) decides which window is active, as on a Mac: a trackpad's scroll / movement
    //  arrives as an INDIRECT touch (type 1) -- one of those, 288 ms after a Dock tap and away from the Dock, sent Finder back, M1 30 Sep 13:49)
    if (t.type == UITouchTypeIndirect) return;

    if (gNativeLayer.rootViewController.presentedViewController) return;   // (something presented over Finder: it keeps Finder active)
    // (every point here is the SCREEN's: a touch's window point is in THAT window's space -- on iPadOS 15 in landscape the system gesture
    //  window is still portrait, and a tap on Finder's sidebar came as {640, 1091}: it missed Finder and went through to the window behind, M1 30 Sep)
    CGPoint wp = [t locationInView:nil];
    CGPoint p = t.window ? [t.window convertPoint:wp toCoordinateSpace:t.window.screen.coordinateSpace] : wp;
    CGPoint lp = [gNativeLayer convertPoint:p fromCoordinateSpace:gNativeLayer.screen.coordinateSpace];
    UIView *hit = DMNativeLayerHitTest(gNativeLayer, @selector(hitTest:withEvent:), lp, nil);
#if DEBUG
    if (hit && !gNativeActive && DMTestFlag("/tmp/macstatusbar-debug")) { UIWindow *cov = DMNativeWindowTaking(p, gNativeLayer.windowLevel);
        DMLog([NSString stringWithFormat:@"[native] touch at %@ on an inactive native window (touch window %@, layer level %.1f): %@", NSStringFromCGPoint(p), NSStringFromClass([t.window class]), gNativeLayer.windowLevel,
               cov ? [NSString stringWithFormat:@"covered by %@ (%.1f) -> %@", NSStringFromClass([cov class]), cov.windowLevel, NSStringFromClass([[cov hitTest:[cov convertPoint:p fromCoordinateSpace:cov.screen.coordinateSpace] withEvent:nil] class])] : @"not covered"]); }
#endif
    if (hit && !gNativeActive && DMNativeWindowTaking(p, gNativeLayer.windowLevel)) hit = nil;   // (behind the apps: an app window above covers it there)
    // (the system gestures' copy of a touch on an inactive native window comes first: raising the layer now put it above the window the touch was
    //  already routed to, and UIKit then never offered the touch to it -- the first touch only activated Finder, iPad 2 30 Sep. The touch itself
    //  follows, let through to the layer by the switcher window (SBMainSwitcherWindow's hit test), and activates the window then.)
    if (hit && !gNativeActive && [NSStringFromClass([t.window class]) isEqualToString:@"_UISystemGestureWindow"]) return;
    if (hit) {
        for (UIView *v = hit; v; v = v.superview) if ([v isKindOfClass:[DMNativeWindow class]]) { DMNativeSetActive((DMNativeWindow *)v); return; }
        return;
    }
    if (!gNativeActive) return;
    // (the menu bar: judged on the SCREEN's coordinates -- the touch's window point is in that window's own space, which on iPadOS 15 in landscape
    //  is still portrait: the top of the screen came as {833, 66}, and a tap on the menu bar's "Finder" title sent Finder back, M1 30 Sep 14:04)
    if (p.y < 26.0) return;
    if (gOverlay) return;     // (a menu or dialog is open: that touch is its -- choosing a row, or closing it -- not a click on another window)
    if (CACurrentMediaTime() - gNativeActivatedAt < 0.5) {   // (the rest of the tap that made it active -- a Dock icon tap is recognised as its touch ends)
        DMLog([NSString stringWithFormat:@"[native] a touch %.0f ms after activation at %@ (type %ld): not a new click, Finder stays active", (CACurrentMediaTime() - gNativeActivatedAt) * 1000.0, NSStringFromCGPoint(p), (long)t.type]);
        return;
    }
    UIWindow *taker = DMNativeWindowTaking(p, gNativeLayer.windowLevel);   // (our menus, the Dock, alerts: Finder stays active)
    // (the desktop's own chrome keeps Finder active at ANY level: with Aerial the active layer sits at 1034, above the Dock's window (25), so the
    //  Dock was never "above" it -- a tap on the Dock's Finder icon made Finder active and the same touch sent it back, M1 30 Sep 13:27)
    if (!taker) for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || w == gNativeLayer || w.alpha < 0.01) continue;
        NSString *c = NSStringFromClass([w class]);
        if (![c isEqualToString:@"SBFloatingDockWindow"] && ![c hasPrefix:@"MSB"]) continue;
        UIView *h = [w hitTest:[w convertPoint:p fromCoordinateSpace:w.screen.coordinateSpace] withEvent:nil];
        if (h && h != w && h != w.rootViewController.view) { taker = w; break; }
    }
    if (taker) { DMLog([NSString stringWithFormat:@"[native] a touch outside Finder went to %@: Finder stays active", NSStringFromClass([taker class])]); return; }
    DMLog([NSString stringWithFormat:@"[native] a touch outside at %@ (type %ld, window %@, view %@): native windows inactive", NSStringFromCGPoint(p), (long)t.type, NSStringFromClass([t.window class]), NSStringFromClass([t.view class])]);
    DMNativeSetActive(nil);
}

// ---- the window ---------------------------------------------------------------------------------------------------------------------------
@implementation DMNativeWindow {
    UIVisualEffectView *_chrome;
    UIView *_titleBar, *_content, *_lights;
    NSArray<UIView *> *_dots;
    UILabel *_titleLabel;
    UIView *_gripL, *_gripR;
    CGRect _panStart;
}
- (UIView *)titleBar { return _titleBar; }
- (UIView *)contentView { return _content; }
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _title = [title copy];
    _appName = @"Finder";
    _minSize = CGSizeMake(420.0, 260.0);
    _titleBarHeight = kNWTitleH; _showsTitle = YES;
    _restoreFrame = CGRectNull;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.35;
    self.layer.shadowRadius = 18.0;
    self.layer.shadowOffset = CGSizeMake(0, 10);
    _chrome = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    _chrome.layer.cornerRadius = kNWCorner; _chrome.layer.cornerCurve = kCACornerCurveContinuous;
    _chrome.clipsToBounds = YES;
    _chrome.layer.borderWidth = 0.5;
    _chrome.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.35].CGColor;
    [self addSubview:_chrome];
    _content = [UIView new];
    _content.backgroundColor = [UIColor systemBackgroundColor];
    _content.clipsToBounds = YES;
    [_chrome.contentView addSubview:_content];
    _titleBar = [UIView new];
    [_chrome.contentView addSubview:_titleBar];
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.text = title;
    [_titleBar addSubview:_titleLabel];
    // traffic lights: our shared dots (hover / press symbols through the shared light group)
    _lights = [UIView new];
    NSMutableArray *buttons = [NSMutableArray array], *dots = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = i;
        UIView *dot = DMMakeLightDot(i, NO, NULL);
        dot.userInteractionEnabled = NO;
        [b addSubview:dot];
        [b addTarget:self action:@selector(dm_light:) forControlEvents:UIControlEventTouchUpInside];
        [_lights addSubview:b];
        [buttons addObject:b]; [dots addObject:dot];
    }
    _dots = dots;
    __weak DMNativeWindow *weakSelf = self;
    DMLightGroupAttach(_lights, buttons, dots, ^NSString *{ return DMNativeLightsTokenFor(weakSelf); });
    [_titleBar addSubview:_lights];
    UIPanGestureRecognizer *move = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_move:)];
    move.maximumNumberOfTouches = 1;
    [_titleBar addGestureRecognizer:move];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(zoom)];
    dbl.numberOfTapsRequired = 2;
    [_titleBar addGestureRecognizer:dbl];
    for (int side = 0; side < 2; side++) {   // resize grips: both bottom corners, as in our other windows
        UIView *g = DMMakeResizeGrip();
        g.transform = CGAffineTransformMakeRotation(side == 0 ? -M_PI_4 : M_PI_4);
        UIView *hot = [UIView new];
        hot.tag = side;
        [hot addSubview:g];
        g.center = CGPointMake(kNWGrip / 2.0, kNWGrip / 2.0);
        UIPanGestureRecognizer *rs = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_resize:)];
        rs.maximumNumberOfTouches = 1;
        [hot addGestureRecognizer:rs];
        [self addSubview:hot];
        if (side == 0) _gripL = hot; else _gripR = hot;
    }
    return self;
}
- (void)setTitle:(NSString *)title { _title = [title copy]; _titleLabel.text = title; }
- (BOOL)dm_isChrome:(UIView *)v { return v && ([v isDescendantOfView:_titleBar] || [v isDescendantOfView:_gripL] || [v isDescendantOfView:_gripR]); }
- (BOOL)dm_takesPoint:(CGPoint)q { return CGRectContainsPoint(self.bounds, q) || (!_gripL.hidden && CGRectContainsPoint(_gripL.frame, q)) || (!_gripR.hidden && CGRectContainsPoint(_gripR.frame, q)); }
- (BOOL)pointInside:(CGPoint)q withEvent:(UIEvent *)e { return [self dm_takesPoint:q]; }   // (so the grips' parts outside the window get their touches)
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _chrome.frame = b;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:kNWCorner].CGPath;
    CGFloat th = self.titleBarHeight;
    _titleBar.frame = CGRectMake(0, 0, b.size.width, th);
    _content.frame = self.fullSizeContent ? b : CGRectMake(0, th, b.size.width, b.size.height - th);
    [_chrome.contentView bringSubviewToFront:_titleBar];
    _lights.frame = CGRectMake(8.0, 0, kLightCell * 3.0, th);
    for (UIButton *btn in _lights.subviews) {
        btn.frame = CGRectMake(btn.tag * kLightCell, 0, kLightCell, th);
        UIView *dot = btn.subviews.firstObject; dot.center = CGPointMake(kLightCell / 2.0, th / 2.0);
    }
    [_titleBar bringSubviewToFront:_lights];
    _titleLabel.hidden = !self.showsTitle;
    BOOL active = (self == gNativeActive);
    [(DMLightGroup *)objc_getAssociatedObject(_lights, kLightGroupKey) apply];   // (colored only while this window is the active one, see DMNativeLightsToken)
    _titleLabel.frame = CGRectMake(kLightCell * 3.0 + 16.0, 0, b.size.width - 2.0 * (kLightCell * 3.0 + 16.0), th);
    _titleLabel.alpha = active ? 1.0 : 0.55;
    _gripL.frame = CGRectMake(-kNWGrip / 2.0 + 6.0, b.size.height - kNWGrip / 2.0 - 6.0, kNWGrip, kNWGrip);
    _gripR.frame = CGRectMake(b.size.width - kNWGrip / 2.0 - 6.0, b.size.height - kNWGrip / 2.0 - 6.0, kNWGrip, kNWGrip);
    for (UIView *g in @[_gripL, _gripR]) { UIView *grip = g.subviews.firstObject; grip.backgroundColor = DMResizeGripColor(self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark); }
}
- (void)dm_light:(UIButton *)b {
    if (b.tag == 0) [self close];
    else if (b.tag == 1) [self minimize];
    else [self zoom];
}
// The desktop a native window may use: under the menu bar, above the Dock (the same area the Window menu's layouts use).
static CGRect DMNativeDesktop(void) { CGRect u = DMUsableArea(); return CGRectIsEmpty(u) ? CGRectInset([UIScreen mainScreen].bounds, 0, 30) : u; }
static CGRect DMNativeClamp(CGRect f, CGSize minSize) {
    CGRect d = DMNativeDesktop();
    f.size.width = MIN(MAX(f.size.width, minSize.width), d.size.width);
    f.size.height = MIN(MAX(f.size.height, minSize.height), d.size.height);
    f.origin.y = MAX(CGRectGetMinY(d), MIN(f.origin.y, CGRectGetMaxY(d) - 40.0));   // (the title bar always reachable)
    f.origin.x = MAX(CGRectGetMinX(d) - f.size.width + 80.0, MIN(f.origin.x, CGRectGetMaxX(d) - 80.0));
    return f;
}
- (void)dm_move:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) { _panStart = self.frame; DMNativeSetActive(self); }
    CGPoint d = [g translationInView:self.superview];
    CGRect f = _panStart; f.origin.x += d.x; f.origin.y += d.y;
    self.frame = DMNativeClamp(f, self.minSize);
    if (g.state == UIGestureRecognizerStateEnded) { self.restoreFrame = CGRectNull; self.layoutName = nil; }
}
// A resize by a bottom corner (tag 0 left: the right edge stays; 1 right): never below the minimum size, never wider than the desktop, never past
// its bottom (a window dragged low got 40 pt tall -- its content laid out with negative heights; the left grip made it 4760 pt wide).
static CGRect DMNativeResized(CGRect start, CGPoint d, int tag, CGSize minSize, CGRect desk) {
    CGRect f = start;
    CGFloat right = CGRectGetMaxX(start);
    if (tag == 0) f.size.width -= d.x; else f.size.width += d.x;
    f.size.width = MAX(minSize.width, MIN(f.size.width, desk.size.width));
    if (tag == 0) f.origin.x = right - f.size.width;
    f.size.height = MAX(minSize.height, MIN(start.size.height + d.y, CGRectGetMaxY(desk) - f.origin.y));
    if (CGRectGetMaxY(f) > CGRectGetMaxY(desk)) f.origin.y = MAX(CGRectGetMinY(desk), CGRectGetMaxY(desk) - f.size.height);   // (too low for the minimum: it moves up)
    return f;
}
- (void)dm_resize:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) { _panStart = self.frame; DMNativeSetActive(self); }
    CGPoint d = [g translationInView:self.superview];
    self.frame = DMNativeResized(_panStart, d, (int)g.view.tag, self.minSize, DMNativeDesktop());
    if (g.state == UIGestureRecognizerStateEnded) { self.restoreFrame = CGRectNull; self.layoutName = nil; }
}
- (void)show {
    UIView *host = DMNativeHost();
    if (!host) return;
    if (!gNativeWindows) gNativeWindows = [NSMutableArray array];
    if (![gNativeWindows containsObject:self]) [gNativeWindows addObject:self];
    if (self.superview != host) [host addSubview:self];
    self.hidden = NO;
    if (gNativeLayer.hidden) { gNativeLayer.hidden = NO; [gNativeLayer layoutIfNeeded]; }
    DMNativeUpdateRotation();   // (now that the layer is on screen: its real turn)
    self.frame = DMNativeClamp(self.frame, self.minSize);
    DMNativeSetActive(self);
    CGRect target = (self.dm_wasMinimized && !MSBReduceMotion()) ? DMNativeDockTarget() : CGRectNull;   // (back from the Dock: grows out of Finder's icon)
    self.dm_wasMinimized = NO;
    if (!CGRectIsNull(target)) {
        self.transform = [self dm_transformToRect:target]; self.alpha = 0.2;
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ self.alpha = 1; self.transform = CGAffineTransformIdentity; } completion:nil];
    } else {
        self.alpha = 0; self.transform = CGAffineTransformMakeScale(0.96, 0.96);
        MSBAnimate(0.18, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ self.alpha = 1; self.transform = CGAffineTransformIdentity; }, nil);
    }
}
- (void)activate { DMNativeSetActive(self); }
- (void)close {
    for (UIView *v in [self.subviews copy]) if ([v isKindOfClass:NSClassFromString(@"DMNativeSheet")]) [(id)v performSelector:@selector(dm_cancel)];   // (a sheet's handlers let go of the window: it was kept alive)
    if (self.onClose) self.onClose(self);
    [gNativeWindows removeObjectIdenticalTo:self];
    // (gNativeActive is NOT cleared here: DMNativeSetActive below must see the change, or it returned early and never gave the keyboard back --
    //  apps could not be typed in after a Finder window was closed, iPad 2 30 Sep 12:41)
    MSBAnimate(0.15, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ self.alpha = 0; self.transform = CGAffineTransformMakeScale(0.96, 0.96); }, ^(BOOL f) { [self removeFromSuperview]; });
    DMNativeWindow *next = gNativeWindows.lastObject;
    DMNativeSetActive(next && !next.hidden ? next : nil);
    DMNativeApplyLevel();
}
// Where the Dock's Finder icon is, in the native layer's container (dock/FinderIcon.m's view, found by its class): minimize shrinks into it and
// the window grows back out of it, like a Mac's Dock. CGRectNull when the Dock has no Finder icon.
static CGRect DMNativeDockTarget(void) {
    Class c = NSClassFromString(@"DMFinderIconView");
    if (!c || !gNativeRotator) return CGRectNull;
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || ![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if ([v isKindOfClass:c] && !v.hidden && v.window) {
                CGRect scr = [v convertRect:v.bounds toCoordinateSpace:v.window.screen.coordinateSpace];
                return [gNativeRotator convertRect:scr fromCoordinateSpace:v.window.screen.coordinateSpace];
            }
            [todo addObjectsFromArray:v.subviews];
        }
    }
    return CGRectNull;
}
- (CGAffineTransform)dm_transformToRect:(CGRect)r {
    CGRect f = self.frame;
    CGFloat k = MAX(0.02, MIN(r.size.width / MAX(f.size.width, 1.0), r.size.height / MAX(f.size.height, 1.0)));
    CGAffineTransform t = CGAffineTransformMakeTranslation(CGRectGetMidX(r) - CGRectGetMidX(f), CGRectGetMidY(r) - CGRectGetMidY(f));
    return CGAffineTransformScale(t, k, k);
}
- (void)minimize {   // (put away into the Dock's Finder icon; the icon / the Window menu / File > New Finder Window bring it back)
    CGRect target = DMNativeDockTarget();
    if (!CGRectIsNull(target) && !MSBReduceMotion()) {
        self.userInteractionEnabled = NO;
        CGAffineTransform t = [self dm_transformToRect:target];
        [UIView animateWithDuration:0.32 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{ self.transform = t; self.alpha = 0.2; } completion:^(BOOL f) {
            self.transform = CGAffineTransformIdentity; self.alpha = 1; self.userInteractionEnabled = YES;
            [self dm_minimizeNow];
        }];
        DMNativeWindow *next = nil; for (DMNativeWindow *w in gNativeWindows) if (!w.hidden && w != self) next = w;
        DMNativeSetActive(next);
        return;
    }
    [self dm_minimizeNow];
}
- (void)dm_minimizeNow {
    self.dm_wasMinimized = YES;
    self.hidden = YES;
    DMNativeWindow *next = nil; for (DMNativeWindow *w in gNativeWindows) if (!w.hidden) next = w;
    DMNativeSetActive(next);
    DMNativeApplyLevel();
}
- (void)zoom {
    self.layoutName = nil;
    if (!CGRectIsNull(self.restoreFrame)) { CGRect r = self.restoreFrame; self.restoreFrame = CGRectNull; MSBAnimate(0.2, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ self.frame = DMNativeClamp(r, self.minSize); }, nil); return; }
    self.restoreFrame = self.frame;
    CGRect d = CGRectInset(DMNativeDesktop(), 4.0, 4.0);
    MSBAnimate(0.2, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ self.frame = d; }, nil);
}
@end
// Esc with a native window in front and nothing of its own to cancel: the keys are SpringBoard's then, so the app windows can't see it -- they are
// asked to put their typing away instead (MacAppBridge's resign notification: the app that was in front when the native window came forward, and
// with Aerial every window), the same Esc-ends-typing the app does itself when it has the keys.
static void DMNativeEscToApps(void) {
    NSMutableSet *bundles = [NSMutableSet set];
    if (gNativeFrontAtActivation.length) [bundles addObject:gNativeFrontAtActivation];
    NSString *front = [DMActiveApp() bundleIdentifier]; if (front.length) [bundles addObject:front];
    for (NSString *b in bundles) {
        uint32_t hash = 2166136261u;
        for (const char *c = b.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
        char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.resign.%08x", hash);
        notify_post(name);
    }
    DMResignWindowedKeyboards(nil);
    DMLog([NSString stringWithFormat:@"[native] Esc: the app windows are asked to put their typing away (%@)", [bundles.allObjects componentsJoinedByString:@", "]]);
}
// A hardware key reached SpringBoard (-[SpringBoard pressesBegan:withEvent:]): the active native window has it first.
__attribute__((noinline)) static BOOL DMNativeHandlePress(UIPress *p) {   // (kept a symbol of its own: inlined into the transparent pressesBegan: hook, a crash here would have no owner)
    DM_FEATURE_MARK("native-keys");
    id w = DMNativeActiveApp();
    if (!w || !p.key || ![w respondsToSelector:@selector(dm_handleKey:)]) return NO;
    BOOL done = ((BOOL (*)(id, SEL, id))objc_msgSend)(w, @selector(dm_handleKey:), p.key);
    if (done) DMLog([NSString stringWithFormat:@"[native] key 0x%02lx (modifiers 0x%lx) handled by %@", (long)p.key.keyCode, (long)p.key.modifierFlags, [w title]]);
    return done;
}

// ---- sheets -------------------------------------------------------------------------------------------------------------------------------
@interface DMNativeSheet : UIView <UITextFieldDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, copy) void (^then)(NSString *text);
@property (nonatomic, copy) void (^cancelled)(void);   // (Cancel, Esc, or the window closed with the sheet up)
@property (nonatomic, weak) UIResponder *restoreFocus;   // (what was being typed in when the sheet came: it gets the typing back, like a Mac)
@end
@implementation DMNativeSheet
- (void)dm_done:(BOOL)ok {
    void (^h)(NSString *) = ok ? self.then : nil; NSString *text = self.field.text;
    void (^c)(void) = ok ? nil : self.cancelled;
    self.then = nil; self.cancelled = nil;
    if (c) c();
    [self.field resignFirstResponder];
    UIResponder *back = self.restoreFocus; self.restoreFocus = nil;
    MSBAnimate(0.15, 0, 0, UIViewAnimationOptionCurveEaseIn, ^{ self.alpha = 0; self.panel.transform = CGAffineTransformMakeTranslation(0, -20); }, ^(BOOL f) { [self removeFromSuperview]; });
    if (h) h(text);
    // (Search typed on after a sheet over it, 30 Sep: the typing goes back -- after the sheet's own action, only into the ACTIVE native window, and
    //  only if the field and everything around it is still shown; logic test L3)
    if ([back isKindOfClass:[UIView class]] && ((UIView *)back).window) {
        BOOL shown = YES; DMNativeWindow *owner = nil;
        for (UIView *v = (UIView *)back; v; v = v.superview) { if (v.hidden || v.alpha < 0.01) shown = NO; if (!owner && [v isKindOfClass:[DMNativeWindow class]]) owner = (DMNativeWindow *)v; }
        BOOL otherSheet = NO; for (UIView *v in owner.subviews) if ([v isKindOfClass:[DMNativeSheet class]] && v != self) otherSheet = YES;   // (a sheet opened by the action keeps its own field)
        if (shown && owner && owner == gNativeActive && !otherSheet && !back.isFirstResponder) [back becomeFirstResponder];
    }
}
- (void)dm_ok { [self dm_done:YES]; }
- (void)dm_cancel { [self dm_done:NO]; }
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self dm_done:YES]; return NO; }
@end
@implementation DMNativeWindow (Sheet)
- (BOOL)hasSheet { for (UIView *v in self.subviews) if ([v isKindOfClass:[DMNativeSheet class]]) return YES; return NO; }
- (void)sheetTitle:(NSString *)title message:(NSString *)message field:(NSString *)field action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(NSString *text))then {
    [self sheetTitle:title message:message field:field action:action destructive:destructive then:then cancel:nil];
}
- (void)sheetTitle:(NSString *)title message:(NSString *)message field:(NSString *)field action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(NSString *text))then cancel:(void (^)(void))onCancel {
    for (UIView *v in [self.subviews copy]) if ([v isKindOfClass:[DMNativeSheet class]]) { [(DMNativeSheet *)v dm_done:NO]; [v removeFromSuperview]; }   // (a sheet replaced: the old one counts as cancelled)
    DMNativeSheet *sh = [[DMNativeSheet alloc] initWithFrame:CGRectMake(0, self.titleBarHeight, self.bounds.size.width, self.bounds.size.height - self.titleBarHeight)];
    sh.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sh.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    sh.then = then; sh.cancelled = onCancel;
    {   // (the text field that has the typing now, if any: it gets it back when the sheet goes)
        NSMutableArray<UIView *> *q = [NSMutableArray arrayWithObject:self];
        while (q.count && !sh.restoreFocus) {
            UIView *v = q.firstObject; [q removeObjectAtIndex:0];
            if (([v isKindOfClass:[UITextField class]] || [v isKindOfClass:[UITextView class]]) && v.isFirstResponder) { sh.restoreFocus = v; break; }
            if (![v isKindOfClass:[DMNativeSheet class]]) [q addObjectsFromArray:v.subviews];
        }
    }
    CGFloat w = MIN(380.0, self.bounds.size.width - 40.0);
    UIVisualEffectView *panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterial]];
    panel.layer.cornerRadius = 12.0; panel.layer.cornerCurve = kCACornerCurveContinuous; panel.clipsToBounds = YES;
    panel.layer.borderWidth = 0.5; panel.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:0.35].CGColor;
    UIView *c = panel.contentView;
    CGFloat y = 18.0;
    UILabel *t = [UILabel new]; t.text = title; t.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold]; t.numberOfLines = 0; t.textAlignment = NSTextAlignmentCenter;
    t.frame = CGRectMake(18, y, w - 36, 0); [t sizeToFit]; t.frame = CGRectMake(18, y, w - 36, t.frame.size.height); [c addSubview:t]; y = CGRectGetMaxY(t.frame) + 8.0;
    if (message.length) {
        UILabel *m = [UILabel new]; m.text = message; m.font = [UIFont systemFontOfSize:12.0]; m.textColor = [UIColor secondaryLabelColor]; m.numberOfLines = 0; m.textAlignment = NSTextAlignmentCenter;
        m.frame = CGRectMake(18, y, w - 36, 0); [m sizeToFit]; m.frame = CGRectMake(18, y, w - 36, m.frame.size.height); [c addSubview:m]; y = CGRectGetMaxY(m.frame) + 10.0;
    }
    if (field) {
        UITextField *f = [UITextField new]; f.text = field; f.borderStyle = UITextBorderStyleRoundedRect; f.font = [UIFont systemFontOfSize:13.0];
        f.clearButtonMode = UITextFieldViewModeWhileEditing; f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.returnKeyType = UIReturnKeyDone; f.delegate = sh;
        f.frame = CGRectMake(18, y, w - 36, 28); [c addSubview:f]; y += 40.0;
        sh.field = f;
    }
    CGFloat bw = (w - 18 * 2 - 10) / 2.0;
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem]; [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    UIButton *ok = [UIButton buttonWithType:UIButtonTypeSystem]; [ok setTitle:action forState:UIControlStateNormal];
    for (UIButton *b in @[cancel, ok]) { b.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:b == ok ? UIFontWeightSemibold : UIFontWeightRegular]; b.layer.cornerRadius = 6.0; b.clipsToBounds = YES; [c addSubview:b]; }
    cancel.backgroundColor = [UIColor tertiarySystemFillColor]; [cancel setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    ok.backgroundColor = destructive ? [UIColor systemRedColor] : [UIColor systemBlueColor]; [ok setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    if (!action.length || [action isEqualToString:@"OK"]) { cancel.hidden = YES; ok.frame = CGRectMake(w - 18 - bw, y, bw, 28); }
    else { cancel.frame = CGRectMake(18, y, bw, 28); ok.frame = CGRectMake(18 + bw + 10, y, bw, 28); }
    [cancel addTarget:sh action:@selector(dm_cancel) forControlEvents:UIControlEventTouchUpInside];
    [ok addTarget:sh action:@selector(dm_ok) forControlEvents:UIControlEventTouchUpInside];
    y += 28.0 + 16.0;
    panel.frame = CGRectMake((sh.bounds.size.width - w) / 2.0, 0, w, y);
    panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    sh.panel = panel;
    [sh addSubview:panel];
    [self addSubview:sh];
    DMNativeSetActive(self);
    sh.alpha = 0; panel.transform = CGAffineTransformMakeTranslation(0, -panel.bounds.size.height);
    MSBAnimate(0.22, 0, 0.9, UIViewAnimationOptionCurveEaseOut, ^{ sh.alpha = 1; panel.transform = CGAffineTransformIdentity; }, nil);
    if (sh.field) { if (!gNativeLayer.isKeyWindow) [gNativeLayer makeKeyWindow]; [sh.field becomeFirstResponder]; [sh.field selectAll:nil]; }
}
@end
// The layer turned with the iPad: every native window kept inside the new desktop -- at once (in the rotation's own animation), and once more
// when the turn has settled: the usable desktop (above the Dock, which moves after the turn) was still the old one's height at first (a Left
// Half window in portrait was only 745 pt tall, M1 30 Sep).
static void DMNativeLayoutForDesktop(BOOL log) {
    CGRect desk = DMNativeDesktop();
    for (DMNativeWindow *w in gNativeWindows) {
        if (!CGRectIsNull(w.restoreFrame)) { w.frame = CGRectInset(desk, 4.0, 4.0); continue; }   // (zoomed: fills the new desktop)
        if (w.layoutName) {   // (put in a layout from the Window menu -- Right Half...: laid out again for the new desktop, like the engines' tiles)
            CGRect f = DMLayoutFrameInArea(w.layoutName, desk, [UIScreen mainScreen].bounds.size);
            if (!CGRectIsNull(f) && !CGRectIsEmpty(f)) { w.frame = f; continue; }
        }
        CGRect f = DMNativeClamp(w.frame, w.minSize);   // (anywhere else: kept whole on the new desktop when it fits -- a turn left windows mostly off screen)
        f.origin.x = MAX(CGRectGetMinX(desk), MIN(f.origin.x, CGRectGetMaxX(desk) - f.size.width));
        f.origin.y = MAX(CGRectGetMinY(desk), MIN(f.origin.y, CGRectGetMaxY(desk) - f.size.height));
        w.frame = f;
    }
    if (log && gNativeWindows.count) DMLog([NSString stringWithFormat:@"[native] turned: %lu window(s) laid out for the new desktop %@", (unsigned long)gNativeWindows.count, NSStringFromCGRect(desk)]);
}
static void DMNativeRelayoutForTurn(void) {
    static CGSize last;
    CGSize now = gNativeRotator.bounds.size;
    if (CGSizeEqualToSize(now, last)) return;
    last = now;
    DMNativeLayoutForDesktop(YES);
    static int pass = 0; int mine = ++pass;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != pass || !CGSizeEqualToSize(gNativeRotator.bounds.size, now)) return;   // (another turn since)
        DMNativeLayoutForDesktop(YES);
    });
}
