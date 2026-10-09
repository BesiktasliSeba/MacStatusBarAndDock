// MacSwitcher.h -- Mac Switcher (1.4), included into StatusBar.x. Settings > Status Bar > Mac Switcher (pref macSwitcher, off until the user
// switches it on; iPadOS 15/16, and 17 (DMMSWOSOK), and only when the self-check below passes).
// Mission Control and desktops as on a Mac, in place of the App Switcher: our own layer window over everything (just under the menu window) shows
// the current desktop's windows -- the engine's windows, Finder's native windows and the full-screen app -- as live thumbnails, spread out without
// overlapping, each with its title under it. A tap or click on one brings it forward and closes the view; Esc or a tap on empty space closes it. A
// strip at the top shows the desktops (the current one live, the others as they were left) and "+" for a new one (at most 8); a window can be
// dragged onto a desktop. Every desktop shows the same Home Screen page 1 and desktop icons (one Desktop folder, Desktop.h); only the windows
// differ. Opened by the Home gesture's hold, a double press of the Home button, Control-Up, the Apple menu and iPadOS's other ways to its App
// Switcher (the gestures section); a side swipe or Control-Left / Control-Right slides to the desktop beside (the Spaces slide). Every window
// engine: Aerial, Zetsu and MilkyWay4 here, the Stage Manager engine in MacSwitcherSM.h.
// Live thumbnails are _UIPortalViews: the render server draws the window's layers again, no copy, no app work. They exist only while the view
// is shown and are let go on close.
// Every private call goes through a checked wrapper (class, selector and type encoding); a mismatch keeps the feature off.

#include "MSWSlideMath.h"   // (the slide's arithmetic: the spring, its speed, the slot a taken slide goes to -- plain C, tools/test-mswslide.sh)
static BOOL gMSWOn = NO;                 // the switch is on, iPadOS 15-17, and the self-check passed
// Where it runs: iPadOS 15/16 (tested), and 17 (untested there: every class, method and type encoding it calls is in iPadOS 17's SpringBoard
// and UIKit -- 17.0.3 headers, 17.6.1 code --, the home gesture's destinations are the same numbers, the gesture's completion lives on the gesture
// manager, see DMMSWHookGestures). 18+: not yet (the keyboard focus lock is renamed there and asserts on a string reason).
static BOOL DMMSWOSOK(void) { return [NSProcessInfo processInfo].operatingSystemVersion.majorVersion <= 17; }
static UIWindow *gMSWWindow;             // our layer window (made on first open; hidden and empty while closed)
static UIView *gMSWRoot;                 // the content, turned with the screen (nil while closed)
static NSMutableArray *gMSWTiles;        // the window thumbnails (DMMSWTile) of the open view
static NSMutableArray<UIView *> *gMSWPortals;   // every portal of the open view (let go on close)
static BOOL gMSWOpen = NO, gMSWClosing = NO;
static CFTimeInterval gMSWTurnAt = 0;    // the screen is turning: the thumbnails wait until it has settled (DMMSWTick)
static CGSize gMSWBuiltSize;             // the root size the view was laid out for
static NSInteger gMSWBuiltTurn = -1;     // and the screen's turn then (DMMSWTurnKey; a turn lays it out again, also a half turn)
static CGRect gMSWDeskRect, gMSWPlusRect;   // the strip's current desktop and "+" (root coordinates)
static NSMutableArray<NSValue *> *gMSWDeskRects;   // every desktop's tile, in strip order
static NSMutableArray *gMSWXViews;                 // their remove buttons (NSNull for Desktop 1)
static BOOL gMSWAllX = NO;                         // a held finger showed every remove button
static UIView *gMSWHilite;               // the highlight around the tile under the pointer
static const CGFloat kMSWMaxScale = 0.8;    // a thumbnail is never bigger than this part of its window (Mission Control keeps them smaller)
static UIView *gMSWStrip;                          // the strip (laid out again in place when a window dropped on "+" makes a desktop)
static NSMutableArray<UIView *> *gMSWDeskClips;    // every desktop's tile in it, in strip order
static NSMutableArray<UIView *> *gMSWDeskLabels;   // and their names
static UIView *gMSWPlusView;                       // "+"
static NSMutableArray<UIView *> *gMSWStripPortals; // the current desktop's live tile's portals (let go when the strip is laid out again)
static CGRect gMSWArea;                            // where the window thumbnails are laid out (DMMSWArrange), root coordinates
static CGFloat gMSWStripH = 0, gMSWTitleH = 26.0;
static CFTimeInterval gMSWOwnHomeAt = 0;           // (the Mac Switcher asked for the Home Screen itself while its view stays open: MacSwitcherButton.h)
// ---- a window dragged onto another desktop (the drag section, after the view's taps) ----
static const NSInteger kMSWDropNew = -1, kMSWDropNone = -2;   // (a drop target: a desktop's place, "+" -- a new desktop --, or nothing)
@class DMMSWTile;
static DMMSWTile *gMSWDragTile;          // the thumbnail being dragged (out of gMSWTiles meanwhile)
static BOOL gMSWDropping = NO;           // a dropped window is on its way into its desktop's tile
static void DMMSWDragReset(void);        // (the view's content goes: no drag is left behind)
static NSString *gMSWDropHold;           // a dropped window stays on the screen until its thumbnail has landed (DMMSWApply leaves it: its live portal flies)
static __weak DMNativeWindow *gMSWDropHoldNative;
static dispatch_block_t gMSWDropFinish;  // what a drop still has to do when it lands -- run at once when the view goes or a switch starts first
static void DMMSWDropFinishNow(void);
static void DMMSWDragAbort(void);        // (the view closes mid-drag: the window goes back among the others first)

// ---- measurement (debug builds only; defined at the end of this file): a frame-by-frame recording of a desktop switch or a gesture, armed while
// /tmp/msw-rec exists. A release build compiles these calls away (their arguments are type-checked, never evaluated). ----
#if DEBUG
static void DMMSWRecBegin(NSString *why);      // starts a recording (or names the running one)
static void DMMSWRecMark(NSString *mark);      // a named moment in the running recording
static void DMMSWRecEndAfter(double seconds);  // the running recording ends this long from now (a later call moves the end)
static void DMMSWRecTrack(UIView *v);          // the view whose on-screen x is recorded every frame (the slide's moving layer)
#define DMMSWMark(...) DMMSWRecMark(__VA_ARGS__)   // (variadic: an Objective-C message in the argument has commas)
#define DMMSWSpanBegin() DMSpanSample(YES, nil)        // (StatusBar.x: the main thread's stacks inside one call, armed by /tmp/msw-span)
#define DMMSWSpanEnd(...) DMSpanSample(NO, (__VA_ARGS__))
#else
#define DMMSWRecBegin(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#define DMMSWMark(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#define DMMSWRecEndAfter(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#define DMMSWRecTrack(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#define DMMSWSpanBegin() do {} while (0)
#define DMMSWSpanEnd(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#endif

// ---- checked access to the private classes ----
// The type encoding without its frame offsets ("q24@0:8@16" -> "q@:@"), to compare with what we call.
static NSString *DMMSWBareTypes(const char *enc) {
    if (!enc) return nil;
    NSMutableString *s = [NSMutableString string];
    for (const char *p = enc; *p; p++) if (!isdigit((unsigned char)*p)) [s appendFormat:@"%c", *p];
    return s;
}
static BOOL DMMSWHasMethod(Class c, NSString *sel, NSString *types) {
    Method m = c ? class_getInstanceMethod(c, NSSelectorFromString(sel)) : NULL;
    return m && [DMMSWBareTypes(method_getTypeEncoding(m)) isEqualToString:types];
}
// What the Mac Switcher needs: the portal view and the window class our layers use. Asked once; a NO keeps the feature off.
static BOOL DMMSWSelfCheck(void) {
    static int result = -1;
    if (result >= 0) return result;
    NSMutableArray *missing = [NSMutableArray array];
    Class pc = objc_getClass("_UIPortalView");
    if (!pc || ![pc isSubclassOfClass:[UIView class]]) [missing addObject:@"_UIPortalView"];
    else {
        NSDictionary *need = @{ @"initWithSourceView:": @"@@:@", @"setSourceView:": @"v@:@", @"setMatchesPosition:": @"v@:B", @"setMatchesTransform:": @"v@:B", @"setMatchesAlpha:": @"v@:B" };
        for (NSString *sel in need) if (!DMMSWHasMethod(pc, sel, need[sel])) [missing addObject:sel];
    }
    if (!DMMSWHasMethod(objc_getClass("SBMainScreenActiveInterfaceOrientationWindow"), @"initWithRole:debugName:", @"@@:@@")) [missing addObject:@"window initWithRole:debugName:"];
    result = missing.count == 0;
    DMLog(result ? @"[macswitcher] self-check passed" : [NSString stringWithFormat:@"[macswitcher] self-check failed (%@): the Mac Switcher stays off", [missing componentsJoinedByString:@", "]]);
    return result;
}
static void DMMSWSetBool(id o, NSString *sel, BOOL v) {
    SEL s = NSSelectorFromString(sel);
    if (DMMSWHasMethod(object_getClass(o), sel, @"v@:B")) ((void (*)(id, SEL, BOOL))objc_msgSend)(o, s, v);
}
// A live copy of source (a portal): drawn by the render server where we put it, at the source's own size. Touches pass through it.
static UIView *DMMSWPortal(UIView *source) {
    if (!source || !DMMSWSelfCheck()) return nil;
    UIView *p = nil;
    @try {
        p = ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("_UIPortalView") alloc], @selector(initWithSourceView:), source);
        DMMSWSetBool(p, @"setMatchesPosition:", NO);
        DMMSWSetBool(p, @"setMatchesTransform:", NO);
        DMMSWSetBool(p, @"setMatchesAlpha:", NO);
        DMMSWSetBool(p, @"setHidesSourceView:", NO);
        DMMSWSetBool(p, @"setAllowsHitTesting:", NO);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] portal of %@ failed: %@", NSStringFromClass([source class]), e]); p = nil; }
    p.userInteractionEnabled = NO;
    if (p) { if (!gMSWPortals) gMSWPortals = [NSMutableArray array]; [gMSWPortals addObject:p]; }
    return p;
}
static void DMMSWPortalLetGo(UIView *p) {
    @try { if (DMMSWHasMethod(object_getClass(p), @"setSourceView:", @"v@:@")) ((void (*)(id, SEL, id))objc_msgSend)(p, @selector(setSourceView:), nil); } @catch (id e) {}
    [p removeFromSuperview];
}
// Puts a portal of src into holder where src lies on the screen, in the coordinates of space (a view on screen: UIKit converts through the
// screen, so windows that keep another orientation come out right; holder has space's coordinates but need not be on screen yet). The
// rectangle it covers is returned in *rect.
static UIView *DMMSWPortalInPlace(UIView *src, UIView *space, UIView *holder, CGRect *rect) {
    if (!src || !space || !holder || !space.window) return nil;
    CGRect b = src.bounds;
    if (b.size.width < 2.0 || b.size.height < 2.0) return nil;
    CGPoint o = [src convertPoint:b.origin toView:space];
    CGPoint x = [src convertPoint:CGPointMake(b.origin.x + 100.0, b.origin.y) toView:space];
    CGPoint c = [src convertPoint:CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b)) toView:space];
    CGFloat k = hypot(x.x - o.x, x.y - o.y) / 100.0, angle = atan2(x.y - o.y, x.x - o.x);
    if (k < 0.01) return nil;
    UIView *p = DMMSWPortal(src);
    if (!p) return nil;
    p.bounds = b;
    p.center = c;
    p.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(angle), k, k);
    [holder addSubview:p];
    if (rect) *rect = p.frame;
    return p;
}

// ---- the keyboard: SpringBoard holds the keyboard focus while the view is open (Esc reaches us even when an app was being typed in; the
// keys do not go on into the app under the view), and gives it back on close. The same calls as a native window's (NativeWindow.h DMNativeFocus):
// -lockFocusToSpringBoardWindowScene:forReason: on iPadOS 16, -lockFocusToSpringBoardForReason: on iPadOS 15, each checked first. ----
static id gMSWFocusLock;
static void DMMSWFocus(BOOL take) {
    if (!take) {
        id l = gMSWFocusLock; gMSWFocusLock = nil;
        if (l && [l respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(l, @selector(invalidate));
        if (l) DMLog(@"[macswitcher] keyboard focus given back");
        return;
    }
    if (gMSWFocusLock) return;
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    id kfc = DMCall(ws, @"keyboardFocusController");
    @try {
        if (DMMSWHasMethod(object_getClass(kfc), @"lockFocusToSpringBoardWindowScene:forReason:", @"@@:@@") && gMSWWindow.windowScene)
            gMSWFocusLock = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, NSSelectorFromString(@"lockFocusToSpringBoardWindowScene:forReason:"), gMSWWindow.windowScene, @"MacStatusBar Mac Switcher");
        else if (DMMSWHasMethod(object_getClass(kfc), @"lockFocusToSpringBoardForReason:", @"@@:@"))
            gMSWFocusLock = ((id (*)(id, SEL, id))objc_msgSend)(kfc, NSSelectorFromString(@"lockFocusToSpringBoardForReason:"), @"MacStatusBar Mac Switcher");
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] keyboard focus lock threw %@", e]); gMSWFocusLock = nil; }
    DMLog([NSString stringWithFormat:@"[macswitcher] keyboard focus to SpringBoard: %@", gMSWFocusLock ? NSStringFromClass([gMSWFocusLock class]) : @"no lock"]);
}

// ---- the current desktop's windows ----
typedef NS_ENUM(NSInteger, DMMSWKind) { DMMSWKindStage = 1, DMMSWKindNative = 2, DMMSWKindFullScreen = 3 };
@interface DMMSWTile : UIView
@property (nonatomic, assign) DMMSWKind kind;
@property (nonatomic, copy) NSString *bundle;            // the app (stage / full screen)
@property (nonatomic, weak) DMNativeWindow *native;      // the native window
@property (nonatomic, weak) UIView *source;              // what the portal shows
@property (nonatomic, assign) CGRect sourceRect;         // where the window is on the screen (root coordinates)
@property (nonatomic, assign) CGRect layoutRect;         // where its thumbnail goes
@property (nonatomic, strong) UIView *inner;             // holds the portal at the window's real place; scaled and moved onto layoutRect
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, copy) NSString *title;
@end
@implementation DMMSWTile
@end

static NSString *DMMSWAppName(NSString *bundle) {
    SBApplication *app = DMAppForBundle(bundle);
    NSString *n = [app respondsToSelector:@selector(displayName)] ? [app displayName] : nil;
    return n.length ? n : bundle;
}
// The app a scene view shows (SBSceneView -sceneHandle -application), or nil.
static NSString *DMMSWSceneViewBundle(UIView *v) {
    id app = DMCall(DMCall(v, @"sceneHandle"), @"application");
    id b = DMCall(app, @"bundleIdentifier");
    return [b isKindOfClass:[NSString class]] ? b : nil;
}
// (MilkyWay4's windows live in its full-screen layer window, AXPassthroughWindow (DMMilkyWayLayer): as an engine window it is never one of the
//  "shared" windows every desktop shows -- a picture drawn from parts showed the desktop on screen's MilkyWay windows live in the coming desktop)
static BOOL DMMSWOurOrEngineWindow(UIWindow *w) {
    NSString *c = NSStringFromClass([w class]);
    return w == gMSWWindow || w == gNativeLayer || [c hasPrefix:@"Aerial"] || [c containsString:@"MilkyWay"] || [c isEqualToString:@"AXPassthroughWindow"] || DMIsZetsuWindow(w);
}
// The full-screen app's live view: its SBDeviceApplicationSceneView in SpringBoard's own windows (not one inside an engine's window), the
// biggest one showing that app; any big one when the scene does not say its app.
static UIView *DMMSWFullScreenView(NSString *bundle, BOOL logAll) {
    Class c = objc_getClass("SBDeviceApplicationSceneView");
    if (!c) return nil;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat big = MIN(screen.width, screen.height) * 0.6;
    UIView *best = nil; CGFloat bestArea = 0;
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || DMMSWOurOrEngineWindow(w)) continue;
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        for (int depth = 0; depth < 40 && todo.count; depth++) {   // (iPadOS 15: ~20 levels down in SBMainSwitcherWindow's page view)
            NSMutableArray *next = [NSMutableArray array];
            for (UIView *v in todo) {
                if (v.hidden || v.alpha < 0.01) continue;
                if ([v isKindOfClass:c]) {
                    NSString *b = DMMSWSceneViewBundle(v);
                    CGRect r = [v convertRect:v.bounds toView:nil];
                    if (logAll) DMLog([NSString stringWithFormat:@"[macswitcher] scene view %p of %@ in %@ (level %.0f): %@, depth %d", v, b ?: @"?", NSStringFromClass([w class]), w.windowLevel, NSStringFromCGRect(r), depth]);
                    CGFloat area = r.size.width * r.size.height;
                    if (MIN(r.size.width, r.size.height) >= big && (!b || [b isEqualToString:bundle]) && area > bestArea) { best = v; bestArea = area; }
                    continue;
                }
                [next addObjectsFromArray:v.subviews];
            }
            todo = next;
        }
    }
    return best;
}
// The full-screen app as it shows, for its picture in a desktop drawn from its parts (DMMSWLeftFromParts): its scene view and the menu bar beside it.
// With an app full screen the menu bar on the screen is the status bar SpringBoard draws for that app inside its switcher page, NEXT TO the scene
// view (one container holds both: SBDeviceApplicationSceneView and the status bar's orientation wrapper), while UIStatusBarWindow's status bar is
// transparent (alpha 0) meanwhile -- so the scene view's picture had no menu bar and the shared windows' portal of UIStatusBarWindow showed none
// either (M1, landscape, fsbar probe 9 Oct; 1.4.1 logic test L-2's note). That container is pictured instead when it is the scene's own (the same
// place on the screen) and holds a status bar outside the scene view. Debug /tmp/msw-fsbar-old = the scene view alone.
static UIView *DMMSWFullScreenWithBar(UIView *fsv) {
    UIView *up = fsv.superview;
    if (!up || DMTestFlag("/tmp/msw-fsbar-old")) return fsv;
    id<UICoordinateSpace> sp = [UIScreen mainScreen].coordinateSpace;
    CGRect a = CGRectIntegral([fsv convertRect:fsv.bounds toCoordinateSpace:sp]), b = CGRectIntegral([up convertRect:up.bounds toCoordinateSpace:sp]);
    if (!CGRectEqualToRect(a, b)) return fsv;   // (not the scene's own container)
    Class barClass = NSClassFromString(DMSBName("UIStatusBar_Modern"));
    if (!barClass) return fsv;
    NSMutableArray<UIView *> *todo = [NSMutableArray array];
    for (UIView *x in up.subviews) if (x != fsv) [todo addObject:x];
    for (int depth = 0; depth < 6 && todo.count; depth++) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in todo) {
            if (v.hidden || v.alpha < 0.01) continue;
            if ([v isKindOfClass:barClass]) return up;
            [next addObjectsFromArray:v.subviews];
        }
        todo = next;
    }
    return fsv;
}
// The windows of the current desktop, back to front: the full-screen app, the engine's windows, the native windows.
static NSArray<DMMSWTile *> *DMMSWCollect(UIView *root) {
    if (DMSMEngine()) return DMMSWSMCollect(root);   // (Stage Manager: its window cards, MacSwitcherSM.h)
    NSMutableArray<DMMSWTile *> *out = [NSMutableArray array];
    DMMSWTile *(^add)(DMMSWKind, UIView *, NSString *) = ^DMMSWTile *(DMMSWKind kind, UIView *src, NSString *title) {
        DMMSWTile *t = [DMMSWTile new];
        t.kind = kind; t.source = src; t.title = title;
        t.inner = [[UIView alloc] initWithFrame:root.bounds];
        t.inner.userInteractionEnabled = NO;
        CGRect r = CGRectNull;
        if (!DMMSWPortalInPlace(src, root, t.inner, &r) || CGRectIsNull(r) || r.size.width < 20.0 || r.size.height < 20.0) { for (UIView *p in [t.inner.subviews copy]) { [gMSWPortals removeObjectIdenticalTo:p]; DMMSWPortalLetGo(p); } return nil; }
        t.sourceRect = r;
        [out addObject:t];
        return t;
    };
    SBApplication *front = DMFrontApp();
    if (front && DMFullScreenAppInFront()) {
        UIView *v = DMMSWFullScreenView([front bundleIdentifier], NO);
        DMMSWTile *t = v ? add(DMMSWKindFullScreen, v, [front displayName] ?: [front bundleIdentifier]) : nil;
        t.bundle = [front bundleIdentifier];
        if (!v) DMLog([NSString stringWithFormat:@"[macswitcher] the full-screen app %@: no scene view found", [front bundleIdentifier]]);
    }
    if (DMActiveEngine() != DMEngineNone)
        for (UIView *s in DMAerialStages()) {
            NSString *b = DMStageBundle(s);
            if (s.hidden || s.alpha < 0.05 || DMStageMinimized(s) || !b.length || [objc_getAssociatedObject(s, kStageClosingKey) boolValue]) continue;
            DMMSWTile *t = add(DMMSWKindStage, s, DMMSWAppName(b));
            t.bundle = b;
        }
    if (gNativeLayer && !gNativeLayer.hidden)
        for (DMNativeWindow *w in [gNativeWindows copy]) {
            if (w.hidden || !w.superview || w.alpha < 0.05) continue;
            DMMSWTile *t = add(DMMSWKindNative, w, w.title.length ? w.title : (w.appName ?: @"Window"));
            t.native = w;
        }
    return out;
}

// ---- Mission Control layout: no overlap, aspect kept, one scale for all, rows centred ----
static void DMMSWArrange(NSArray<DMMSWTile *> *tiles, CGRect area, CGFloat titleH) {
    NSUInteger n = tiles.count;
    if (!n) return;
    const CGFloat gap = 28.0;
    NSArray<DMMSWTile *> *byY = [tiles sortedArrayUsingComparator:^NSComparisonResult(DMMSWTile *a, DMMSWTile *b) {
        CGFloat ya = CGRectGetMidY(a.sourceRect), yb = CGRectGetMidY(b.sourceRect);
        return ya < yb ? NSOrderedAscending : ya > yb ? NSOrderedDescending : NSOrderedSame;
    }];
    NSArray<NSArray<DMMSWTile *> *> *bestRows = nil; CGFloat bestScale = -1;
    for (NSUInteger rows = 1; rows <= n; rows++) {
        NSUInteger per = (n + rows - 1) / rows;
        NSMutableArray *rowList = [NSMutableArray array];
        for (NSUInteger i = 0; i < n; i += per) {
            NSArray *row = [[byY subarrayWithRange:NSMakeRange(i, MIN(per, n - i))] sortedArrayUsingComparator:^NSComparisonResult(DMMSWTile *a, DMMSWTile *b) {
                CGFloat xa = CGRectGetMidX(a.sourceRect), xb = CGRectGetMidX(b.sourceRect);
                return xa < xb ? NSOrderedAscending : xa > xb ? NSOrderedDescending : NSOrderedSame;
            }];
            [rowList addObject:row];
        }
        CGFloat scale = kMSWMaxScale, heights = 0;
        for (NSArray<DMMSWTile *> *row in rowList) {
            CGFloat widths = 0, tallest = 0;
            for (DMMSWTile *t in row) { widths += t.sourceRect.size.width; tallest = MAX(tallest, t.sourceRect.size.height); }
            scale = MIN(scale, (area.size.width - gap * (row.count - 1)) / widths);
            heights += tallest;
        }
        scale = MIN(scale, (area.size.height - rowList.count * titleH - gap * (rowList.count - 1)) / heights);
        if (scale > bestScale + 0.001) { bestScale = scale; bestRows = rowList; }
    }
    CGFloat s = MAX(0.05, bestScale), total = 0;
    for (NSArray<DMMSWTile *> *row in bestRows) { CGFloat tallest = 0; for (DMMSWTile *t in row) tallest = MAX(tallest, t.sourceRect.size.height); total += tallest * s + titleH; }
    total += gap * (bestRows.count - 1);
    CGFloat y = CGRectGetMidY(area) - total / 2.0;
    for (NSArray<DMMSWTile *> *row in bestRows) {
        CGFloat widths = 0, tallest = 0;
        for (DMMSWTile *t in row) { widths += t.sourceRect.size.width * s; tallest = MAX(tallest, t.sourceRect.size.height * s); }
        CGFloat x = CGRectGetMidX(area) - (widths + gap * (row.count - 1)) / 2.0;
        for (DMMSWTile *t in row) {
            CGSize sz = CGSizeMake(t.sourceRect.size.width * s, t.sourceRect.size.height * s);
            t.layoutRect = CGRectIntegral(CGRectMake(x, y + (tallest - sz.height) / 2.0, sz.width, sz.height));
            x += sz.width + gap;
        }
        y += tallest + titleH + gap;
    }
}
// inner (the root's size, the portal at the window's real place) shown on rect: scaled about its centre and moved.
static void DMMSWPlace(UIView *inner, CGRect from, CGRect to) {
    CGFloat s = from.size.width > 0 ? to.size.width / from.size.width : 1.0;
    CGPoint fc = CGPointMake(CGRectGetMidX(from), CGRectGetMidY(from)), tc = CGPointMake(CGRectGetMidX(to), CGRectGetMidY(to));
    CGPoint bc = CGPointMake(CGRectGetMidX(inner.bounds), CGRectGetMidY(inner.bounds));
    // (a scale s about bc puts fc at bc + s*(fc - bc); then the move lands it on tc)
    CGAffineTransform t = CGAffineTransformMakeTranslation(tc.x - (bc.x + s * (fc.x - bc.x)), tc.y - (bc.y + s * (fc.y - bc.y)));
    inner.transform = CGAffineTransformScale(t, s, s);
}

// ---- the layer window, turned with the screen ----
static UIWindow *DMMSWLayer(void) {
    if (gMSWWindow) return gMSWWindow;
    if (!DMMSWSelfCheck()) return nil;
    @try {
        Class base = objc_getClass("SBMainScreenActiveInterfaceOrientationWindow");
        UIWindow *w = ((id (*)(id, SEL, id, id))objc_msgSend)([base alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarMacSwitcher");
        w.backgroundColor = [UIColor clearColor];
        w.windowLevel = kMenuWindowLevel - 0.5;   // (over every app window, Finder and the Dock; our menu window stays above)
        w.hidden = YES;
        gMSWWindow = w;
        DMSnapInvalidate();
        DMLog([NSString stringWithFormat:@"[macswitcher] layer window made: %@ frame %@", NSStringFromClass([w class]), NSStringFromCGRect(w.frame)]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] layer window failed: %@", e]); }
    return gMSWWindow;
}
// The content's bounds and turn: the screen as it is seen now (iPadOS 16 keeps this window class portrait while the scene turns; 15 turns it).
static void DMMSWTurnIn(UIWindow *l, UIView *root) {
    CGSize screen = [UIScreen mainScreen].bounds.size, win = l.bounds.size;
    id<UICoordinateSpace> scr = [UIScreen mainScreen].coordinateSpace;
    CGPoint o = [l convertPoint:CGPointZero toCoordinateSpace:scr], x = [l convertPoint:CGPointMake(100, 0) toCoordinateSpace:scr];
    CGFloat angle = hypot(x.x - o.x, x.y - o.y) > 50.0 ? -round(atan2(x.y - o.y, x.x - o.x) / M_PI_2) * M_PI_2 : 0;
    BOOL turned = fabs(angle) > 0.01;
    root.transform = CGAffineTransformIdentity;
    root.bounds = CGRectMake(0, 0, turned ? screen.width : win.width, turned ? screen.height : win.height);
    root.center = CGPointMake(win.width / 2.0, win.height / 2.0);
    root.transform = turned ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity;
}

static void DMMSWClose(DMMSWTile *pick, BOOL animated);
static void DMMSWTapped(UITapGestureRecognizer *g);
static void DMMSWHover(UIHoverGestureRecognizer *g);
static void DMMSWHold(UILongPressGestureRecognizer *g);
static void DMMSWDragPan(UIPanGestureRecognizer *g);   // (the drag section)
static void DMMSWDragFrame(void);
static BOOL DMMSWDragMayBegin(UIPanGestureRecognizer *g);
static BOOL DMMSWHoldMayBegin(UILongPressGestureRecognizer *g);
static UITouchType gMSWDragTouchType = UITouchTypeDirect;   // (the drag's last touch: a finger or the pointer, for the log)
static BOOL gMSWDragPointer = NO;   // (it is the pointer's: SpringBoard does not opt into indirect input, so a trackpad click comes as a type-0 touch, told
                                    //  apart by -[UITouch _isPointerTouch] -- see docs/ios15-second-desktop.md)
@interface DMMSWTarget : NSObject <UIGestureRecognizerDelegate>
@end
@implementation DMMSWTarget
- (void)tap:(UITapGestureRecognizer *)g { DMMSWTapped(g); }
- (void)hover:(UIHoverGestureRecognizer *)g { DMMSWHover(g); }
- (void)hold:(UILongPressGestureRecognizer *)g { DMMSWHold(g); }
- (void)pan:(UIPanGestureRecognizer *)g { DMMSWDragPan(g); }
- (void)dragFrame:(CADisplayLink *)link { DMMSWDragFrame(); }
// (the drag begins only on a window's thumbnail; the hold that shows the remove buttons only on a desktop -- it no longer takes a finger held on a
//  window, which may then still be dragged)
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if ([g isKindOfClass:[UIPanGestureRecognizer class]]) return DMMSWDragMayBegin((UIPanGestureRecognizer *)g);
    if ([g isKindOfClass:[UILongPressGestureRecognizer class]]) return DMMSWHoldMayBegin((UILongPressGestureRecognizer *)g);
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    if ([g isKindOfClass:[UIPanGestureRecognizer class]]) {
        static int has = -1;
        if (has < 0) has = DMMSWHasMethod([UITouch class], @"_isPointerTouch", @"B@:");
        gMSWDragTouchType = touch.type;
        gMSWDragPointer = touch.type == UITouchTypeIndirectPointer || (has > 0 && ((BOOL (*)(id, SEL))objc_msgSend)(touch, NSSelectorFromString(@"_isPointerTouch")));
    }
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return [a isKindOfClass:[UIHoverGestureRecognizer class]] || [b isKindOfClass:[UIHoverGestureRecognizer class]];   // (the pointer's hover never holds a drag back)
}
@end
static DMMSWTarget *gMSWTarget;

static UILabel *DMMSWLabel(NSString *text, CGFloat size, UIFontWeight weight) {
    UILabel *l = [UILabel new];
    l.text = text; l.textColor = [UIColor whiteColor]; l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textAlignment = NSTextAlignmentCenter; l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.layer.shadowColor = [UIColor blackColor].CGColor; l.layer.shadowOpacity = 0.6; l.layer.shadowRadius = 2.0; l.layer.shadowOffset = CGSizeZero;
    return l;
}
// The windows of the screen as they are seen, back to front, for the desktop's thumbnail and the background (ours and the ones above us left out).
static NSArray<UIWindow *> *DMMSWScreenWindows(void) {
    NSMutableArray<UIWindow *> *list = [NSMutableArray array];
    // (SBRootSceneWindow: "visible", but laid out in another space (1668 x 2388 at y -1554 on the M1) and its portal is solid black -- it hid
    //  the Home Screen and the wallpaper in Desktop 1's thumbnail; DMMSWBuild also drops any window that does not land on the screen exactly)
    NSSet *skip = [NSSet setWithObjects:@"UITextEffectsWindow", @"_UISystemGestureWindow", @"SBRecordingIndicatorWindow", @"UIRemoteKeyboardWindow", @"SBRootSceneWindow", nil];
    for (UIWindow *w in DMAllWindows()) {
        if (w == gMSWWindow || w.hidden || w.alpha < 0.01 || w.windowLevel >= gMSWWindow.windowLevel || w.screen != [UIScreen mainScreen]) continue;
        if ([skip containsObject:NSStringFromClass([w class])] || [NSStringFromClass([w class]) containsString:@"Screenshot"]) continue;
        [list addObject:w];
    }
    [list sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        return a.windowLevel < b.windowLevel ? NSOrderedAscending : a.windowLevel > b.windowLevel ? NSOrderedDescending : NSOrderedSame;
    }];
    return list;
}

// ---- the background: the Home Screen wallpaper as a still picture, lightly dimmed, like Mission Control on a Mac ----
// Read from SpringBoard's own wallpaper objects: the wallpaper window's SBWWallpaperViewController -homescreenWallpaperView (or the view both
// variants share), and in it the image view the wallpaper is drawn with. Exact: its contents (the very image SpringBoard shows -- the current
// light / dark variant -- shared, not copied), contents rectangle and place, converted into our view, used when that comes out upright and
// covering the screen. Otherwise (the wallpaper window is hidden while an app is full screen and may not have followed a turn) the view's
// -wallpaperImage, filling the screen from its centre. Nothing readable: the live blur, and the log says why. Kept between openings and taken
// again when the wallpaper's image (its hash), our size or the screen's turn changes.
static NSInteger DMMSWTurnKey(void);
static id gMSWWallContents;                // the picture (a CGImage or whatever SpringBoard's layer holds)
static NSString *gMSWWallKey;              // what it was taken for
static CGRect gMSWWallBounds, gMSWWallContentsRect;
static CGPoint gMSWWallCenter;
static CGAffineTransform gMSWWallTransform;
static NSString *gMSWWallGravity;
static CGSize gMSWWallSize;                // the screen's size it was placed for
static UIView *DMMSWWallpaperView(void) {
    Class wvc = objc_getClass("SBWWallpaperViewController"), wv = objc_getClass("SBFWallpaperView");
    for (UIWindow *w in DMAllWindows()) {
        NSString *wc = NSStringFromClass([w class]);
        if (wvc && wv && [wc isEqualToString:@"_SBWallpaperWindow"] && [w.rootViewController isKindOfClass:wvc]) {   // (iPadOS 15)
            UIView *v = DMMSWHasMethod(wvc, @"homescreenWallpaperView", @"@@:") ? DMCall(w.rootViewController, @"homescreenWallpaperView") : nil;
            if (![v isKindOfClass:wv] && DMMSWHasMethod(wvc, @"sharedWallpaperView", @"@@:")) v = DMCall(w.rootViewController, @"sharedWallpaperView");
            if ([v isKindOfClass:wv]) return v;
        }
        // (iPadOS 16: PosterBoard draws it -- _SBWallpaperSecureWindow > PBUIWallpaperViewController > ... > PBUIStaticWallpaperView, whose
        //  PBUIStaticWallpaperImageView holds the picture; read on the iPad 2. The Mac Switcher showed the dark blur there instead.)
        if (![wc hasPrefix:@"_SBWallpaper"]) continue;
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        for (int depth = 0; depth < 6 && todo.count; depth++) {
            NSMutableArray *next = [NSMutableArray array];
            for (UIView *x in todo) {
                NSString *c = NSStringFromClass([x class]);
                if (!x.hidden && [c hasPrefix:@"PBUI"] && [c hasSuffix:@"WallpaperView"]) return x;
                [next addObjectsFromArray:x.subviews];
            }
            todo = next;
        }
    }
    return nil;
}
static UIView *DMMSWWallpaperImageView(UIView *wall) {   // (the view whose layer holds the picture: SBFStaticWallpaperImageView on 15.6.1)
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:wall];
    for (int depth = 0; depth < 5 && todo.count; depth++) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in todo) { if (v != wall && v.layer.contents && !v.hidden) return v; [next addObjectsFromArray:v.subviews]; }
        todo = next;
    }
    return nil;
}
static UIView *DMMSWWallpaperBackground(UIView *root, NSString **why) {
    if (DMTestFlag("/tmp/msw-liveblur")) { *why = @"debug: /tmp/msw-liveblur"; return nil; }   // (the live blur's fade checked on a device, L-3)
    UIView *wall = DMMSWWallpaperView();
    if (!wall) { *why = @"no Home Screen wallpaper view"; return nil; }
    UIView *iv = DMMSWWallpaperImageView(wall);
    id hash = DMMSWHasMethod(object_getClass(wall), @"displayedImageHashString", @"@@:") ? DMCall(wall, @"displayedImageHashString") : nil;
    CGRect b = root.bounds;
    NSString *key = [NSString stringWithFormat:@"%@ %p %@ %ld", [hash isKindOfClass:[NSString class]] ? hash : @"-", (__bridge void *)iv.layer.contents, NSStringFromCGSize(b.size), (long)DMMSWTurnKey()];
    if (![key isEqualToString:gMSWWallKey]) {
        gMSWWallKey = nil; gMSWWallContents = nil;
        NSString *mode = nil;
        if (iv && iv.layer.contents && iv.window) {   // exact: as SpringBoard shows it
            CGRect ib = iv.bounds;
            CGPoint o = [iv convertPoint:ib.origin toView:root], x = [iv convertPoint:CGPointMake(ib.origin.x + 100.0, ib.origin.y) toView:root];
            CGPoint c = [iv convertPoint:CGPointMake(CGRectGetMidX(ib), CGRectGetMidY(ib)) toView:root];
            CGFloat k = hypot(x.x - o.x, x.y - o.y) / 100.0, angle = atan2(x.y - o.y, x.x - o.x);
            CGRect r = CGRectMake(c.x - ib.size.width * k / 2.0, c.y - ib.size.height * k / 2.0, ib.size.width * k, ib.size.height * k);
            if (k > 0.01 && fabs(angle) < 0.01 && CGRectContainsRect(CGRectInset(r, -1.0, -1.0), b)) {
                gMSWWallContents = iv.layer.contents; gMSWWallBounds = ib; gMSWWallCenter = c; gMSWWallTransform = CGAffineTransformMakeScale(k, k);
                gMSWWallContentsRect = iv.layer.contentsRect; gMSWWallGravity = iv.layer.contentsGravity; gMSWWallSize = b.size;
                mode = [NSString stringWithFormat:@"as shown (%@ at %@)", NSStringFromClass([iv class]), NSStringFromCGRect(r)];
            } else DMLog([NSString stringWithFormat:@"[macswitcher] wallpaper as shown does not fit (angle %.2f, %@ for %@): its picture fills the screen instead", angle, NSStringFromCGRect(r), NSStringFromCGSize(b.size)]);
        }
        if (!gMSWWallContents) {   // fill: the wallpaper's picture, from its centre
            UIImage *img = nil;
            @try { for (NSString *sel in @[@"wallpaperImage", @"_displayedImage"]) if (!img && DMMSWHasMethod(object_getClass(wall), sel, @"@@:")) { id i = DMCall(wall, sel); if ([i isKindOfClass:[UIImage class]]) img = i; } } @catch (id e) { img = nil; }
            if (!img.CGImage || img.size.width < 1 || img.size.height < 1) { *why = @"the wallpaper view gave no picture"; return nil; }
            CGFloat s = MAX(b.size.width / img.size.width, b.size.height / img.size.height);
            gMSWWallContents = (__bridge id)img.CGImage; gMSWWallBounds = CGRectMake(0, 0, img.size.width, img.size.height);
            gMSWWallCenter = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b)); gMSWWallTransform = CGAffineTransformMakeScale(s, s);
            gMSWWallContentsRect = CGRectMake(0, 0, 1, 1); gMSWWallGravity = kCAGravityResize; gMSWWallSize = b.size;
            mode = [NSString stringWithFormat:@"filling the screen (%@ picture)", NSStringFromCGSize(img.size)];
        }
        gMSWWallKey = key;
        DMLog([NSString stringWithFormat:@"[macswitcher] wallpaper taken %@", mode]);
    }
    UIView *v = [UIView new];
    v.userInteractionEnabled = NO;
    v.layer.contents = gMSWWallContents; v.layer.contentsRect = gMSWWallContentsRect; v.layer.contentsGravity = gMSWWallGravity ?: kCAGravityResize;
    v.bounds = gMSWWallBounds; v.center = gMSWWallCenter; v.transform = gMSWWallTransform;
    return v;
}

// A desktop drawn from its parts before the wallpaper was ever taken (the Mac Switcher not opened since a respring: it slid in without its
// wallpaper, O4) -- or after memory pressure let its picture go (M-5) --, or one taken for the screen's other shape (a turn since: it covered
// the screen only in part): the wallpaper's picture now, filling the screen from its centre, as the view's own fallback reads it (cheap:
// SpringBoard's image, shared). The exact placement comes with the view's next opening (the key stays unset).
static void DMMSWWallLazy(void) {
    if (gMSWWallContents && CGSizeEqualToSize(gMSWWallSize, [UIScreen mainScreen].bounds.size)) return;
    UIView *wall = DMMSWWallpaperView();
    UIImage *img = nil;
    @try { for (NSString *sel in @[@"wallpaperImage", @"_displayedImage"]) if (!img && wall && DMMSWHasMethod(object_getClass(wall), sel, @"@@:")) { id i = DMCall(wall, sel); if ([i isKindOfClass:[UIImage class]]) img = i; } } @catch (id e) { img = nil; }
    if (!img.CGImage || img.size.width < 1 || img.size.height < 1) return;
    CGRect b = [UIScreen mainScreen].bounds;
    CGFloat s = MAX(b.size.width / img.size.width, b.size.height / img.size.height);
    gMSWWallContents = (__bridge id)img.CGImage; gMSWWallBounds = CGRectMake(0, 0, img.size.width, img.size.height);
    gMSWWallCenter = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b)); gMSWWallTransform = CGAffineTransformMakeScale(s, s);
    gMSWWallContentsRect = CGRectMake(0, 0, 1, 1); gMSWWallGravity = kCAGravityResize; gMSWWallKey = nil; gMSWWallSize = b.size;
    DMLog([NSString stringWithFormat:@"[macswitcher] wallpaper taken for a desktop drawn from its parts (filling the screen %@, %@ picture)", NSStringFromCGSize(b.size), NSStringFromCGSize(img.size)]);
}

// How the screen is turned now: SpringBoard's interface orientation (1-4), or -1.
static NSInteger DMMSWTurnKey(void) {
    id sb = [UIApplication sharedApplication];
    SEL s = NSSelectorFromString(@"activeInterfaceOrientation");
    return DMMSWHasMethod(object_getClass(sb), @"activeInterfaceOrientation", @"q@:") ? ((long long (*)(id, SEL))objc_msgSend)(sb, s) : -1;
}
// The content's root view with its background only (a turn shows just this until it has settled).
static const void *kMSWLiveBlurKey = &kMSWLiveBlurKey;   // (the view's background is the live blur: never faded as a group, DMMSWCloseUnderSlide)
static UIView *DMMSWBuildRoot(void) {
    UIWindow *w = gMSWWindow;
    UIView *host = w.rootViewController.view ?: w;
    UIView *root = [UIView new];
    root.backgroundColor = [UIColor clearColor];
    [host addSubview:root];
    gMSWRoot = root;
    DMMSWTurnIn(gMSWWindow, root);
    gMSWBuiltSize = root.bounds.size;
    gMSWBuiltTurn = DMMSWTurnKey();
    CGRect b = root.bounds;
    // the background: the Home Screen wallpaper, lightly dimmed; the live blur of the screen only when the wallpaper can't be read
    NSString *why = nil;
    UIView *wall = DMMSWWallpaperBackground(root, &why);
    UIView *back = nil;
    if (wall) {
        back = [[UIView alloc] initWithFrame:b];
        back.backgroundColor = [UIColor blackColor];
        back.clipsToBounds = YES;
        [back addSubview:wall];
        UIView *dim = [[UIView alloc] initWithFrame:b];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
        [back addSubview:dim];
    } else {
        DMLog([NSString stringWithFormat:@"[macswitcher] background: the live blur (%@)", why]);
        objc_setAssociatedObject(root, kMSWLiveBlurKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        back = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
        back.frame = b;
        UIView *dim = [[UIView alloc] initWithFrame:b];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
        [((UIVisualEffectView *)back).contentView addSubview:dim];
    }
    back.userInteractionEnabled = NO;
    [root addSubview:back];
    return root;
}

// ==== a picture of a view without SpringBoard's main thread waiting for it (F5, 7 Oct) ===========================================================
// UIKit's -snapshotViewAfterScreenUpdates: asks the render server (backboardd) for the picture and WAITS on the main thread until the server has
// drawn it (-[UIView resizableSnapshotViewFromRect:afterScreenUpdates:withCapInsets:] -> CARenderServerSnapshot, a synchronous message; sampled
// on the M1: the main thread sat in mach_msg the whole time -- 3-250 ms per window during a desktop switch, 1-3.5 s after a half turn, while the
// server went on drawing the slide). The same request goes from a background queue here: the options UIKit 15.6.1 itself sends (read from its
// code: snapshot mode "layer", the screen's name, the layer's context id and the layer itself as its id, a scale transform, a destination slot,
// reuse backdrop contents, ignore the root's accessibility filters), the destination an image slot of the layer's own context (as
// _UISlotId makes one), the picture a view showing that slot. The main thread never waits; the picture is there when the server has drawn it.
// Everything is looked up and type-checked once; anything missing -> no picture (the caller's fallback), never UIKit's waiting call instead.
typedef BOOL (*DMMSWSnapFn)(mach_port_t, NSDictionary *);
static DMMSWSnapFn gMSWSnapFn;
static NSString *gMSWSnapKeyMode, *gMSWSnapModeLayer, *gMSWSnapKeyName, *gMSWSnapKeyCtx, *gMSWSnapKeyLayer, *gMSWSnapKeyDest, *gMSWSnapKeyTransform, *gMSWSnapKeyReuse, *gMSWSnapKeyIgnoreAX;
static NSString *gMSWSnapModeStopAfter, *gMSWSnapKeyList;   // (the screen's picture: mode "stop after context list", the screen's windows' contexts)
static NSString *DMMSWSnapConst(const char *name) {
    NSString *const *p = (NSString *const *)dlsym(RTLD_DEFAULT, name);
    return p && [*p isKindOfClass:[NSString class]] ? *p : nil;
}
static BOOL DMMSWAsyncPicturesOK(void) {
    static int ok = -1;
    if (ok >= 0) return ok;
    // (read and verified on iPadOS 15.6.1 -- UIKit's own call, BOOL CARenderServerSnapshot(mach_port_t, NSDictionary *), and the M1's pictures. 16 and 17
    //  keep the waiting pictures until UIKit's call is read there too: the debug hook snaphook logs it; then this line lets them in)
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion != 15) { ok = 0; DMLog(@"[macswitcher] window pictures without waiting: only on iPadOS 15 so far (read there) -- the waiting pictures, as before"); return NO; }
    NSMutableArray *missing = [NSMutableArray array];
    gMSWSnapFn = (DMMSWSnapFn)dlsym(RTLD_DEFAULT, "CARenderServerSnapshot");
    if (!gMSWSnapFn) [missing addObject:@"CARenderServerSnapshot"];
    gMSWSnapKeyMode = DMMSWSnapConst("kCASnapshotMode"); gMSWSnapModeLayer = DMMSWSnapConst("kCASnapshotModeLayer"); gMSWSnapKeyName = DMMSWSnapConst("kCASnapshotDisplayName");
    gMSWSnapKeyCtx = DMMSWSnapConst("kCASnapshotContextId"); gMSWSnapKeyLayer = DMMSWSnapConst("kCASnapshotLayerId"); gMSWSnapKeyDest = DMMSWSnapConst("kCASnapshotDestination");
    gMSWSnapKeyTransform = DMMSWSnapConst("kCASnapshotTransform"); gMSWSnapKeyReuse = DMMSWSnapConst("kCASnapshotReuseBackdropContents"); gMSWSnapKeyIgnoreAX = DMMSWSnapConst("kCASnapshotIgnoreRootAccessibilityFilters");
    gMSWSnapModeStopAfter = DMMSWSnapConst("kCASnapshotModeStopAfterContextList"); gMSWSnapKeyList = DMMSWSnapConst("kCASnapshotContextList");
    if (!gMSWSnapKeyMode || !gMSWSnapModeLayer || !gMSWSnapKeyName || !gMSWSnapKeyCtx || !gMSWSnapKeyLayer || !gMSWSnapKeyDest || !gMSWSnapKeyTransform) [missing addObject:@"kCASnapshot keys"];
    Class ctx = objc_getClass("CAContext");
    if (!DMMSWHasMethod(ctx, @"createImageSlot:hasAlpha:", @"I@:{CGSize=dd}B")) [missing addObject:@"-[CAContext createImageSlot:hasAlpha:]"];
    if (!DMMSWHasMethod(ctx, @"deleteSlot:", @"v@:I")) [missing addObject:@"-[CAContext deleteSlot:]"];
    if (!DMMSWHasMethod(ctx, @"contextId", @"I@:")) [missing addObject:@"-[CAContext contextId]"];
    Method os = ctx ? class_getClassMethod(ctx, NSSelectorFromString(@"objectForSlot:")) : NULL;
    if (!os || ![DMMSWBareTypes(method_getTypeEncoding(os)) isEqualToString:@"@@:I"]) [missing addObject:@"+[CAContext objectForSlot:]"];
    if (!DMMSWHasMethod([CALayer class], @"context", @"@@:")) [missing addObject:@"-[CALayer context]"];
    ok = missing.count == 0;
    DMLog(ok ? @"[macswitcher] window pictures without waiting: available (the render server's own snapshot, from a background queue)"
             : [NSString stringWithFormat:@"[macswitcher] window pictures without waiting: not here (%@) -- no window pictures on the switch path", [missing componentsJoinedByString:@", "]]);
    return ok;
}
// The slot a picture shows: deleted when the picture view goes.
@interface DMMSWSlotHolder : NSObject
@property (nonatomic, strong) id context;
@property (nonatomic) uint32_t slot;
@end
@implementation DMMSWSlotHolder
- (void)dealloc {
    id c = _context; uint32_t s = _slot;
    if (!c || !s) return;
    void (^del)(void) = ^{ @try { ((void (*)(id, SEL, unsigned int))objc_msgSend)(c, NSSelectorFromString(@"deleteSlot:"), s); } @catch (id e) {} };
    if ([NSThread isMainThread]) del(); else dispatch_async(dispatch_get_main_queue(), del);
}
@end
static const void *kMSWSlotKey = &kMSWSlotKey;
static dispatch_queue_t DMMSWPicQueue(void) {   // (concurrent: a picture the server is slow with never holds the next one -- the screen's for a switch)
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("MacStatusBar.macswitcher.pictures", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0)); });
    return q;
}
// A picture of v as it is drawn now (its bounds, at the screen's scale), handed to done on the main thread: a view showing it, or nil (not drawn by
// the server, or no such call here). NO: nothing was asked (done is not called). ms: from the ask to the picture.
static BOOL DMMSWPictureAsync(UIView *v, void (^done)(UIView *pic, double ms)) {
    if (!v || !done || !DMMSWAsyncPicturesOK()) return NO;
    CALayer *l = v.layer;
    id ctx = DMCall(l, @"context");   // (the CAContext the layer is drawn in -- its window's: nil before that window was ever drawn)
    id slotCtx = ctx;                 // (the slot belongs to the same context, as UIKit's own picture: it goes when the picture view goes)
    NSString *why = nil;
    if (!ctx) why = @"its window has no render context yet";
    else if ([l respondsToSelector:NSSelectorFromString(@"hasBeenCommitted")] && !((BOOL (*)(id, SEL))objc_msgSend)(l, NSSelectorFromString(@"hasBeenCommitted"))) why = @"not drawn by the server yet";
    uint32_t cid = ctx ? ((uint32_t (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"contextId")) : 0;
    CGRect b = v.bounds;
    CGFloat s = [UIScreen mainScreen].scale;
    if (!why && (!cid || b.size.width < 1 || b.size.height < 1)) why = @"no context id or an empty view";
    if (why) { static NSMutableSet *told; if (!told) told = [NSMutableSet set]; if (![told containsObject:why]) { [told addObject:why]; DMLog([NSString stringWithFormat:@"[macswitcher] a picture without waiting could not be asked: %@", why]); } return NO; }
    CGSize px = CGSizeMake(ceil(b.size.width * s), ceil(b.size.height * s));
    CATransform3D t = CATransform3DConcat(CATransform3DMakeTranslation(-b.origin.x, -b.origin.y, 0), CATransform3DMakeScale(s, s, 1));   // (as UIKit's)
    id name = DMCall([UIScreen mainScreen], @"_name");
    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    opts[gMSWSnapKeyMode] = gMSWSnapModeLayer;
    if ([name isKindOfClass:[NSString class]]) opts[gMSWSnapKeyName] = name;
    opts[gMSWSnapKeyCtx] = @(cid);
    opts[gMSWSnapKeyLayer] = @((unsigned long long)(uintptr_t)(__bridge void *)l);   // (UIKit's layer id: the layer itself)
    opts[gMSWSnapKeyTransform] = [NSValue valueWithCATransform3D:t];
    if (gMSWSnapKeyReuse) opts[gMSWSnapKeyReuse] = @YES;
    if (gMSWSnapKeyIgnoreAX) opts[gMSWSnapKeyIgnoreAX] = @YES;
    CFTimeInterval t0 = CACurrentMediaTime();
    UIView *keep = v;   // (the layer stays alive until the server has drawn it)
    dispatch_async(DMMSWPicQueue(), ^{
        uint32_t slot = 0; BOOL ok = NO;
        @try { slot = ((uint32_t (*)(id, SEL, CGSize, BOOL))objc_msgSend)(slotCtx, NSSelectorFromString(@"createImageSlot:hasAlpha:"), px, YES); } @catch (id e) { slot = 0; }
        if (slot) { opts[gMSWSnapKeyDest] = @(slot); ok = gMSWSnapFn(MACH_PORT_NULL, opts); }
        if (DMTestFlag("/tmp/msw-slowpic")) usleep(450000);   // (debug: a server that answers late -- the waits and their limits are tried with it)
        dispatch_async(dispatch_get_main_queue(), ^{
            (void)keep;
            double ms = (CACurrentMediaTime() - t0) * 1000.0;
            DMMSWSlotHolder *h = nil;
            if (slot) { h = [DMMSWSlotHolder new]; h.context = slotCtx; h.slot = slot; }
            if (!ok) { done(nil, ms); return; }   // (h goes: its slot is deleted)
            id contents = ((id (*)(id, SEL, unsigned int))objc_msgSend)(objc_getClass("CAContext"), NSSelectorFromString(@"objectForSlot:"), slot);
            if (!contents) { done(nil, ms); return; }
            UIView *pic = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, b.size.height)];
            pic.userInteractionEnabled = NO;
            pic.layer.contents = contents;
            objc_setAssociatedObject(pic, kMSWSlotKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            done(pic, ms);
        });
    });
    return YES;
}

// ==== desktops ==================================================================================================================================
// A desktop has an id (1 = Desktop 1: always first, never removed; another gets the lowest free number from 2 when it is made) and is named by its
// place in the strip ("Desktop 2" is the second). Its windows are records: Aerial stages by their app (gMSWWinDesk, app -> id; a window that is in
// no record yet joins the current desktop), native windows by an associated id. A window of another desktop is "away" (StatusBar.x kMSWAwayKey):
// hidden, its app in the background (DMSyncMinimizedScenes counts it as not on screen), out of DMAerialStages(); native ones leave the layer.
// Files, as on a Mac: ONE Desktop folder for all desktops (owner's decision) -- every desktop shows the same page 1 with the same desktop icons
// (Desktop.h, On My iPad > Desktop); only the windows differ per desktop.
// A full-screen app stays on its desktop (owner's decision): leaving the desktop sends it Home and remembers it; coming back opens it again.
// Saved in com.besiktasliseba.macstatusbar.desktops.plist (the desktops, the current one, the window records); the windows themselves come back
// with the window state as before, then the records hide the ones of other desktops. Settings off: everything on Desktop 1 again.
static NSMutableArray<NSNumber *> *gMSWDesks;                        // the desktops' ids, in strip order
static NSUInteger gMSWCur = 0;                                       // the current desktop's place
static NSMutableDictionary<NSString *, NSNumber *> *gMSWWinDesk;     // app -> its window's desktop id
static NSMutableDictionary<NSString *, NSString *> *gMSWWinFrame;    // app -> its window's frame when it went away (an app iPadOS closed meanwhile comes back there)
static NSMutableDictionary<NSString *, NSString *> *gMSWFullScreen;  // desktop id ("2") -> the app that was full screen when it was left
static NSMutableDictionary<NSNumber *, UIView *> *gMSWShots;         // desktop id -> how it looked when it was left (its thumbnail in the strip)
static NSMutableArray<DMNativeWindow *> *gMSWAwayNatives;            // native windows of other desktops
static NSMutableDictionary<NSString *, UIView *> *gMSWWinShots;      // app -> its away window's picture (taken as it went away: thumbnails are made of them)
static NSMutableDictionary<NSNumber *, NSArray *> *gMSWShotSet;      // desktop id -> its windows when its picture was taken (another set now: the picture is stale)
static NSMutableDictionary<NSString *, NSDictionary *> *gMSWFit;    // desktop id ("2") -> its Fit to Window group, slots and free windows while away
static NSMutableDictionary<NSString *, NSString *> *gMSWLeftSize;    // desktop id ("2") -> the screen's size when it was left (turned since: arranged on return)
static const void *kMSWNativeDeskKey = &kMSWNativeDeskKey;
static BOOL gMSWSwitching = NO, gMSWDesksDirty = NO;
static BOOL gMSWSwInChange = NO;   // (a switch's windows change runs: the pictures of windows coming back are kept until the switch ends, DMMSWSwEnd)
static NSMutableDictionary<NSString *, NSNumber *> *gMSWRelaunching;   // app -> until when its window is on its way (not forgotten meanwhile)
static NSMutableDictionary<NSString *, NSNumber *> *gMSWQuitting;      // app -> until when its force-quit window, still in the engine's layer while
                                                                       //  it goes, is left as it is (DMMSWForgetApp, DMMSWApply)
static const NSUInteger kMSWMaxDesks = 8;
static NSInteger DMMSWCurId(void) { return gMSWDesks.count ? gMSWDesks[MIN(gMSWCur, gMSWDesks.count - 1)].integerValue : 1; }
// (every engine: Aerial, Zetsu and MilkyWay4 by the same records and the same away windows -- each engine's window is one of DMAerialStagesAll()'s
//  "stages": an AerialStage, a ZetsuWindow, an AXWindowView --; Stage Manager by its stages, MacSwitcherSM.h; no engine: Finder's windows)
static BOOL DMMSWDesktopsHere(void) { return gMSWOn; }
static BOOL DMMSWMulti(void) { return DMMSWDesktopsHere() && gMSWDesks.count > 1; }
static NSString *DMMSWDeskName(NSUInteger i) { return [NSString stringWithFormat:@"Desktop %lu", (unsigned long)i + 1]; }
static NSString *DMMSWStatePath(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.besiktasliseba.macstatusbar.desktops.plist"]; }
static void DMMSWSwitchTo(NSUInteger to, NSString *why, void (^done)(void));

// A desktop's windows now (its apps, sorted), to tell a stale picture.
static NSArray *DMMSWWindowSet(NSInteger did) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *b in gMSWWinDesk) if (gMSWWinDesk[b].integerValue == did) [a addObject:b];
    return [a sortedArrayUsingSelector:@selector(compare:)];
}
static void DMMSWSave(void) {
    gMSWDesksDirty = NO;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSNumber *n in gMSWDesks ?: @[@1]) [ids addObject:n];
    NSDictionary *st = @{@"desktops": ids, @"current": @(DMMSWCurId()), @"windows": [gMSWWinDesk copy] ?: @{}, @"frames": [gMSWWinFrame copy] ?: @{},
                         @"fullscreen": [gMSWFullScreen copy] ?: @{}, @"leftSizes": [gMSWLeftSize copy] ?: @{}, @"fit": [gMSWFit copy] ?: @{}};
    static NSDictionary *last;
    if ([st isEqualToDictionary:last]) return;
    last = st;
    // (written from a serial background queue, in order: the file write cost SpringBoard's main thread ~4 ms in the middle of a desktop switch, F5)
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("MacStatusBar.macswitcher.save", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0)); });
    NSString *path = DMMSWStatePath();
    dispatch_async(q, ^{ [st writeToFile:path atomically:YES]; });
    DMLog([NSString stringWithFormat:@"[macswitcher] desktops saved: %@, current %ld, %lu window records", [ids componentsJoinedByString:@","], (long)DMMSWCurId(), (unsigned long)gMSWWinDesk.count]);
}
static void DMMSWLoad(void) {
    NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:DMMSWStatePath()];
    gMSWDesks = [NSMutableArray arrayWithObject:@1]; gMSWCur = 0;
    gMSWWinDesk = [NSMutableDictionary dictionary]; gMSWWinFrame = [NSMutableDictionary dictionary]; gMSWFullScreen = [NSMutableDictionary dictionary]; gMSWLeftSize = [NSMutableDictionary dictionary]; gMSWFit = [NSMutableDictionary dictionary];
    if (!gMSWShots) gMSWShots = [NSMutableDictionary dictionary];
    if (!gMSWAwayNatives) gMSWAwayNatives = [NSMutableArray array];
    if ([st isKindOfClass:[NSDictionary class]]) {
        NSArray *ids = st[@"desktops"];
        if ([ids isKindOfClass:[NSArray class]]) for (id n in ids) if ([n isKindOfClass:[NSNumber class]] && [n integerValue] > 1 && ![gMSWDesks containsObject:n] && gMSWDesks.count < kMSWMaxDesks) [gMSWDesks addObject:@([n integerValue])];
        NSNumber *cur = st[@"current"];
        NSUInteger i = [cur isKindOfClass:[NSNumber class]] ? [gMSWDesks indexOfObject:@(cur.integerValue)] : NSNotFound;
        gMSWCur = i == NSNotFound ? 0 : i;
        NSDictionary *w = st[@"windows"], *f = st[@"frames"], *fs = st[@"fullscreen"];
        if ([w isKindOfClass:[NSDictionary class]]) for (id k in w) if ([k isKindOfClass:[NSString class]] && [w[k] isKindOfClass:[NSNumber class]] && [gMSWDesks containsObject:w[k]]) gMSWWinDesk[k] = w[k];
        if ([f isKindOfClass:[NSDictionary class]]) for (id k in f) if ([k isKindOfClass:[NSString class]] && [f[k] isKindOfClass:[NSString class]]) gMSWWinFrame[k] = f[k];
        NSDictionary *fit = st[@"fit"];
        if ([fit isKindOfClass:[NSDictionary class]]) for (id k in fit) if ([k isKindOfClass:[NSString class]] && [fit[k] isKindOfClass:[NSDictionary class]]) gMSWFit[k] = fit[k];
        NSDictionary *ls = st[@"leftSizes"];
        if ([ls isKindOfClass:[NSDictionary class]]) for (id k in ls) if ([k isKindOfClass:[NSString class]] && [ls[k] isKindOfClass:[NSString class]]) gMSWLeftSize[k] = ls[k];
        if ([fs isKindOfClass:[NSDictionary class]]) for (id k in fs) if ([k isKindOfClass:[NSString class]] && [fs[k] isKindOfClass:[NSString class]] && [gMSWDesks containsObject:@([k integerValue])]) gMSWFullScreen[k] = fs[k];
    }
    DMLog([NSString stringWithFormat:@"[macswitcher] desktops loaded: %@, current %@ (%lu window records)", [gMSWDesks componentsJoinedByString:@","], DMMSWDeskName(gMSWCur), (unsigned long)gMSWWinDesk.count]);
}

// Keyboard focus never stays on another desktop: while a window is away, SpringBoard's keyboard focus controller is told to keep focus off its
// app's scene (-preventFocusForSceneWithIdentityToken:reason:, an assertion, checked first); it is let go when the window is back. Without it the
// keys went on to the hidden window's text field after a switch to an empty desktop (M1 3 Oct, kbfocus).
static NSMutableDictionary<NSString *, id> *gMSWNoFocus;   // app -> the assertion
static void DMMSWFocusAway(NSString *b, BOOL away) {
    if (!away) {
        id a = gMSWNoFocus[b];
        if (!a) return;
        [gMSWNoFocus removeObjectForKey:b];
        @try { if ([a respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(a, @selector(invalidate)); } @catch (id e) {}
        return;
    }
    if (gMSWNoFocus[b]) return;
    id kfc = DMKeyboardFocusController(), scene = DMSceneForBundle(b);
    id token = scene && DMMSWHasMethod(object_getClass(scene), @"identityToken", @"@@:") ? DMCall(scene, @"identityToken") : nil;
    static NSMutableSet *told; if (!told) told = [NSMutableSet set];
    if (!token || !DMMSWHasMethod(object_getClass(kfc), @"preventFocusForSceneWithIdentityToken:reason:", @"@@:@@")) { if ([told containsObject:b]) return; [told addObject:b]; DMLog([NSString stringWithFormat:@"[macswitcher] %@: its keyboard focus could not be held off (scene %d, token %d)", b, scene != nil, token != nil]); return; }
    id a = nil;
    @try { a = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, NSSelectorFromString(@"preventFocusForSceneWithIdentityToken:reason:"), token, @"MacStatusBar: its window is on another desktop"); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] prevent focus threw %@", e]); }
    if (!a) return;
    [told removeObject:b];
    DMLog([NSString stringWithFormat:@"[macswitcher] %@: keyboard focus held off while its window is away", b]);
    if (!gMSWNoFocus) gMSWNoFocus = [NSMutableDictionary dictionary];
    gMSWNoFocus[b] = a;
}
// A window Aerial is making (the window state's restore after a respring, a launch): one recorded on another desktop is away and hidden at once,
// before its first frame -- the tick hid it only a moment later, and the restored windows of other desktops flashed up at every respring.
static void DMMSWNewStage(UIView *stage, NSString *b) {
    if (!DMMSWMulti() || !b.length) return;
    NSNumber *d = gMSWWinDesk[b];
    if (!d || d.integerValue == DMMSWCurId() || ![gMSWDesks containsObject:d]) return;
    objc_setAssociatedObject(stage, kMSWAwayKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    stage.hidden = YES;
    gMSWAwayCount++;
    DMLog([NSString stringWithFormat:@"[macswitcher] %@'s new window is on %@: hidden from the start", b, DMMSWDeskName([gMSWDesks indexOfObject:d])]);
}
// The screen as it is drawn, without SpringBoard waiting: the request UIKit 15.6.1 sends for -[UIScreen snapshotViewAfterScreenUpdates:] (read
// with the debug hook snaphook: mode "stop after context list", the screen's visible windows' contexts in UIKit's order, the screen's name, a
// transform from the display's fixed portrait points to the picture's pixels as the screen is turned now, a destination slot), from the background
// queue. exclude: windows left out (ours: the Mac Switcher's view is never in it). NO: nothing was asked (done is not called).
static BOOL DMMSWScreenPictureAsync(NSArray<UIWindow *> *exclude, void (^done)(UIView *pic, double ms)) {
    if (!done || !DMMSWAsyncPicturesOK() || !gMSWSnapModeStopAfter || !gMSWSnapKeyList) return NO;
    UIScreen *scr = [UIScreen mainScreen];
    SEL ws = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:forScreen:");
    Method wm = class_getClassMethod([UIWindow class], ws);
    if (!wm || ![DMMSWBareTypes(method_getTypeEncoding(wm)) isEqualToString:@"@@:BB@"]) return NO;
    NSArray *wins = ((id (*)(id, SEL, BOOL, BOOL, id))objc_msgSend)([UIWindow class], ws, YES, YES, scr);
    NSMutableArray *list = [NSMutableArray array];
    id slotCtx = nil;
#if DEBUG
    NSInteger subLo = -1, subHi = -1, idx = -1;   // (K-1 test: /tmp/msw-snapsub "<lo> <hi>" lists only those windows, by their place in this order)
    { NSArray *f = [[[NSString stringWithContentsOfFile:@"/tmp/msw-snapsub" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@" "];
      if (f.count == 2) { subLo = [f[0] integerValue]; subHi = [f[1] integerValue]; } }
#endif
    for (UIWindow *w in wins) {
        if (![w isKindOfClass:[UIWindow class]] || [exclude containsObject:w]) continue;
#if DEBUG
        idx++;
        if (subLo >= 0 && (idx < subLo || idx > subHi)) continue;
        if (subLo >= 0) DMLog([NSString stringWithFormat:@"[mswpic] listed %ld: %@ level %.1f", (long)idx, NSStringFromClass([w class]), w.windowLevel]);
#endif
        id c = DMCall(w.layer, @"context");
        uint32_t cid = c ? ((uint32_t (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"contextId")) : 0;
        if (!cid) continue;
        [list addObject:@{ gMSWSnapKeyCtx: @(cid) }];
        if (!slotCtx) slotCtx = c;   // (the slot belongs to the first window's context: SpringBoard's lowest, kept all along)
    }
    if (!list.count || !slotCtx) return NO;
    CGRect b = scr.bounds;
    CGFloat s = scr.scale;
    id<UICoordinateSpace> fixed = scr.fixedCoordinateSpace, now = scr.coordinateSpace;
    CGPoint o = [now convertPoint:CGPointZero fromCoordinateSpace:fixed], ex = [now convertPoint:CGPointMake(1, 0) fromCoordinateSpace:fixed], ey = [now convertPoint:CGPointMake(0, 1) fromCoordinateSpace:fixed];
    CGAffineTransform a = CGAffineTransformMake(ex.x - o.x, ex.y - o.y, ey.x - o.x, ey.y - o.y, o.x, o.y);   // (fixed points -> the turned screen's points)
    a = CGAffineTransformConcat(a, CGAffineTransformMakeScale(s, s));                                     // (-> pixels)
    CGSize px = CGSizeMake(ceil(b.size.width * s), ceil(b.size.height * s));
    id name = DMCall(scr, @"_name");
    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    opts[gMSWSnapKeyMode] = gMSWSnapModeStopAfter;
#if DEBUG
    if (DMTestFlag("/tmp/msw-snapinclude")) { NSString *inc = DMMSWSnapConst("kCASnapshotModeIncludeContextList"); if (inc) opts[gMSWSnapKeyMode] = inc; }   // (K-1 test: only the listed contexts)
#endif
    opts[gMSWSnapKeyList] = list;
    if ([name isKindOfClass:[NSString class]]) opts[gMSWSnapKeyName] = name;
    opts[gMSWSnapKeyTransform] = [NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(a)];
    CFTimeInterval t0 = CACurrentMediaTime();
    dispatch_async(DMMSWPicQueue(), ^{
        uint32_t slot = 0; BOOL ok = NO;
        @try { slot = ((uint32_t (*)(id, SEL, CGSize, BOOL))objc_msgSend)(slotCtx, NSSelectorFromString(@"createImageSlot:hasAlpha:"), px, NO); } @catch (id e) { slot = 0; }
        if (slot) { opts[gMSWSnapKeyDest] = @(slot); ok = gMSWSnapFn(MACH_PORT_NULL, opts); }
        dispatch_async(dispatch_get_main_queue(), ^{
            double ms = (CACurrentMediaTime() - t0) * 1000.0;
            DMMSWSlotHolder *h = nil;
            if (slot) { h = [DMMSWSlotHolder new]; h.context = slotCtx; h.slot = slot; }
            id contents = ok ? ((id (*)(id, SEL, unsigned int))objc_msgSend)(objc_getClass("CAContext"), NSSelectorFromString(@"objectForSlot:"), slot) : nil;
            if (!contents) { done(nil, ms); return; }
            UIView *pic = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, b.size.height)];
            pic.userInteractionEnabled = NO;
            pic.layer.contents = contents;
            objc_setAssociatedObject(pic, kMSWSlotKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            done(pic, ms);
        });
    });
    return YES;
}
static BOOL DMMSWAsyncScreenOn(void) {
#if DEBUG
    if (DMTestFlag("/tmp/msw-syncscreen")) return NO;   // (debug comparison: the waiting screen picture of before)
#endif
    return YES;
}
// F5: the pictures of windows and of the screen, without SpringBoard waiting for them (where DMMSWAsyncPicturesOK: iPadOS 15).
static BOOL DMMSWAsyncPicsOn(void) {
#if DEBUG
    if (DMTestFlag("/tmp/msw-syncpic")) return NO;   // (debug comparison: the waiting picture of before)
#endif
    return DMMSWAsyncPicturesOK();
}
// The windows about to go away get their pictures cut out of the left desktop's picture -- the screen as it was when the switch began, taken for
// the slide anyway -- so no picture of a single window is asked from the render server at all (F5). A single window's picture makes the server
// draw that window's layers once more on their own: with some windows (M1 7 Oct, right after a window was made from a full-screen app) that took the
// server ~200 ms, and while it did SpringBoard's next commit waited for it (sampled: the main thread in mach_msg inside Core Animation's commit) --
// waited for or not, that picture held SpringBoard. The screen's picture costs the server 5-15 ms in the same state. A cut-out of a window that
// another window of its desktop covered in part shows that part as it was; only a change of that desktop's windows while it is away (a force
// quit) can show it without its window.
static NSMutableDictionary<NSString *, UIView *> *gMSWFreshPics;   // app -> its picture cut out just before its window goes away
static const void *kMSWOverKey = &kMSWOverKey;                    // (a cut-out's windows in front of it, covering part of it: their parts are in it)
// After a window is dragged away in the open view, the view's opening picture (gMSWOpenShot) shows it still: it is no longer the desktop's picture
// (DMMSWMoveRecords drops it), but every other window's part of it is still right -- kept here for their pictures (DMMSWLeftFromParts, and their
// cut-outs when the desktop is left, DMMSWSwChange), with the windows each one had a dragged-away window in front of (gMSWCutSpoiled: those parts
// show that window -- a picture of theirs from it is true only where that window is too, DMMSWCutTrue / DMMSWPicTrueOn). Let go with the view or
// the switch.
static UIView *gMSWCutShot;
static NSInteger gMSWCutShotId = 0;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *gMSWCutSpoiled;   // window (app, or "native:<address>") -> dragged-away windows over it
static void DMMSWCutLetGo(void) { gMSWCutShot = nil; gMSWCutShotId = 0; gMSWCutSpoiled = nil; }
static NSString *DMMSWNativeCutKey(UIView *w) { return [NSString stringWithFormat:@"native:%p", w]; }
static BOOL DMMSWCutTrue(NSString *key, NSInteger did) {   // (its part of gMSWCutShot shows no window that has left desktop `did` since)
    for (NSString *o in gMSWCutSpoiled[key]) if (gMSWWinDesk[o].integerValue != did) return NO;
    return YES;
}
// A window's picture is true on a desktop drawn from parts while every window that covered part of it when it was cut out is still on that desktop
// (a force quit while away: that window's part would show in the picture of the one behind it -- an app icon card is drawn for it instead).
static BOOL DMMSWPicTrueOn(UIView *pic, NSInteger did) {
    NSSet *over = objc_getAssociatedObject(pic, kMSWOverKey);
    for (NSString *o in over) if (gMSWWinDesk[o].integerValue != did) return NO;
    return YES;
}
static UIView *DMMSWCutOut(UIView *old, CGRect r) {   // (r: the window in screen points; a view of the window's whole size, its part on the screen cut out)
    id contents = old.layer.contents;
    CGSize s = old.bounds.size;
    if (!contents || s.width < 1 || s.height < 1 || r.size.width < 1 || r.size.height < 1) return nil;
    CGRect on = CGRectIntersection(r, CGRectMake(0, 0, s.width, s.height));
    if (CGRectIsNull(on) || on.size.width < 1 || on.size.height < 1) return nil;
    UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, r.size.width, r.size.height)];
    holder.userInteractionEnabled = NO; holder.clipsToBounds = YES;
    UIView *cut = [[UIView alloc] initWithFrame:CGRectOffset(on, -r.origin.x, -r.origin.y)];
    cut.userInteractionEnabled = NO;
    cut.layer.contents = contents;
    cut.layer.contentsRect = CGRectMake(on.origin.x / s.width, on.origin.y / s.height, on.size.width / s.width, on.size.height / s.height);
    id h = objc_getAssociatedObject(old, kMSWSlotKey);   // (the picture's slot lives while any cut-out of it does)
    if (h) objc_setAssociatedObject(cut, kMSWSlotKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [holder addSubview:cut];
    return holder;
}
static void DMMSWCutOutsFrom(UIView *old, NSInteger fromId) {
    gMSWFreshPics = nil;
    if (!DMMSWAsyncPicsOn() || DMTestFlag("/tmp/msw-nowinpics") || DMSMEngine()) return;   // (no picture without waiting here: DMMSWApply takes them the old way)
    gMSWFreshPics = [NSMutableDictionary dictionary];
    UIScreen *scr = [UIScreen mainScreen];
    if (!old.layer.contents || !CGSizeEqualToSize(old.bounds.size, scr.bounds.size)) { DMMSWMark(@"cut-outs: none (the left picture is drawn from parts or of another shape)"); return; }
    NSUInteger n = 0;
    NSMutableArray<UIView *> *shown = [NSMutableArray array];   // (the left desktop's windows on the screen, back to front)
    for (UIView *st in DMAerialStagesAll()) {
        NSString *b = DMStageBundle(st);
        if (!b.length || st.hidden || DMStageMinimized(st) || [objc_getAssociatedObject(st, kMSWAwayKey) boolValue]) continue;
        NSNumber *d = gMSWWinDesk[b];
        if (d && d.integerValue != fromId) continue;   // (the left desktop's windows; one in no record yet is the left desktop's too)
        [shown addObject:st];
    }
    for (NSUInteger i = 0; i < shown.count; i++) {
        UIView *st = shown[i];
        NSString *b = DMStageBundle(st);
        if (st.bounds.size.width <= 100 || gMSWWinShots[b]) continue;
        CGRect r = [st convertRect:st.bounds toCoordinateSpace:scr.coordinateSpace];
        UIView *c = DMMSWCutOut(old, r);
        if (!c) continue;
        NSMutableSet *over = [NSMutableSet set];   // (the windows in front of it that cover part of it: in its cut-out too)
        for (NSUInteger j = i + 1; j < shown.count; j++) if (CGRectIntersectsRect(r, [shown[j] convertRect:shown[j].bounds toCoordinateSpace:scr.coordinateSpace])) [over addObject:DMStageBundle(shown[j])];
        if (old == gMSWCutShot && gMSWCutSpoiled[b].count) [over unionSet:gMSWCutSpoiled[b]];   // (the windows dragged away since that covered part of it there)
        objc_setAssociatedObject(c, kMSWOverKey, over, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gMSWFreshPics[b] = c; n++;
    }
    DMMSWMark([NSString stringWithFormat:@"cut-outs: %lu window(s)", (unsigned long)n]);
}
// Puts every window where its record says: the current desktop's shown, the others' away. Run every tick (a new window joins the current desktop;
// a window Aerial showed again while away is hidden again) and at once by a switch. With one desktop (or the feature off) nothing is away.
// Records made by the Stage Manager engine name each window by its own key, "<bundle>|<scene>" (SMWindowKey.h, since the 1.3.9 merge); the other
// engines know one window per app and look records up by the app. After an engine change from Stage Manager (the desktops stay) such a record was
// no app of theirs: DMMSWRelaunchClosed took it for an app closed while its desktop was away and asked to launch "<bundle>|<scene>". They become their
// apps' records here (two windows of one app on two desktops: the app's window goes to one of them -- these engines have one window per app). Only
// while such an engine runs (DMActiveEngine): DMSMEngine() also reads NO for a moment with Stage Manager still the engine -- a Control Center tap
// that Stage Manager is switched back on after, the extra respring after a package switch -- and folding then lost a window's own desktop (re-check).
// (the records are by app now: an engine that keys windows by app runs -- Aerial, Zetsu, MilkyWay4 -- and Stage Manager is not the user's pick. In the
//  run right after a package was removed and installed again (beta <-> release), Choicy has given an engine back: it loads next to Stage Manager,
//  DMSMEngine() reads NO and DMActiveEngine() names that engine for one run -- the records must stay as Stage Manager keeps them, re-check N-1)
static BOOL DMMSWAppKeysOnly(void) { return DMActiveEngine() != DMEngineNone && ![gEnginePref isEqualToString:@"stagemanager"]; }
// A window we minimized stays hidden when its desktop comes back: Aerial's and Zetsu's by DMMinimizeStage (kStageHiddenKey), MilkyWay4's by
// DMMinimizeWindow (kMinimizedKey; a minimized MilkyWay4 window came back shown).
static BOOL DMMSWMinimizedByUs(UIView *st) { return [objc_getAssociatedObject(st, kStageHiddenKey) boolValue] || DMWindowMinimized(st); }
// Zetsu's own title-bar pill (_isReduction): the Lock Screen collapses every Zetsu window into it, and DMZetsuAfterUnlock reopens the windows on
// screen; an away one it marks (kZetsuLockPillKey, StatusBar.x). That one is opened again when its desktop comes, as a tap on its pill does, and goes
// back to its place (Zetsu reopens a window at its own default size), its front order kept.
static BOOL DMMSWZetsuReduced(UIView *w) {
    if (!DMIsZetsuWindow(w)) return NO;
    BOOL found = NO, reduced = DMBoolIvar(w, "_isReduction", &found);
    if (!found) @try { reduced = [[w valueForKey:@"_isReduction"] boolValue]; } @catch (id e) {}
    return reduced;
}
static void DMMSWZetsuReopen(UIWindow *w) {
    DMLog([NSString stringWithFormat:@"[macswitcher] %@: Zetsu collapsed its window while its desktop was away (the Lock Screen): opened again", DMZetsuWindowBundle(w)]);
    DMZetsuTap(w);
    gZetsuReopenedAt = CACurrentMediaTime();
    __weak UIWindow *ww = w;
    for (NSNumber *delay in @[@0.6, @1.6]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *x = ww;
        NSValue *intent = x ? objc_getAssociatedObject(x, kStageIntentKey) : nil;
        if (!intent || x.hidden || DMStageMinimized(x) || [objc_getAssociatedObject(x, kMSWAwayKey) boolValue]) return;
        CGRect want = intent.CGRectValue, f = x.frame;
        if (fabs(want.origin.x - f.origin.x) <= 1.0 && fabs(want.origin.y - f.origin.y) <= 1.0 && fabs(want.size.width - f.size.width) <= 1.0 && fabs(want.size.height - f.size.height) <= 1.0) return;
        gZetsuReopenedAt = CACurrentMediaTime();
        gMoveKeepsOrder = YES; DMZetsuMove(x, want, NO, nil); gMoveKeepsOrder = NO;
    });
}
static void DMMSWFoldWindowKeys(void) {
    NSMutableArray<NSString *> *wk = nil;
    for (NSString *k in gMSWWinDesk) if (!DMSMKeyIsApp(k)) { if (!wk) wk = [NSMutableArray array]; [wk addObject:k]; }
    if (!wk) return;
    for (NSString *k in wk) {
        NSString *b = DMSMKeyBundle(k);
        if (b.length && !gMSWWinDesk[b]) { gMSWWinDesk[b] = gMSWWinDesk[k]; if (gMSWWinFrame[k]) gMSWWinFrame[b] = gMSWWinFrame[k]; }
        [gMSWWinDesk removeObjectForKey:k]; [gMSWWinFrame removeObjectForKey:k]; [gMSWWinShots removeObjectForKey:k];
    }
    gMSWDesksDirty = YES;
    DMLog([NSString stringWithFormat:@"[macswitcher] %lu window record(s) of the Stage Manager engine are their apps' records now (this engine has one window per app)", (unsigned long)wk.count]);
}
static void DMMSWApply(void) {
    if (DMSMEngine()) DMMSWSMApply();   // (Stage Manager: a desktop is a stage, MacSwitcherSM.h; below only the native windows apply there)
    else if (DMMSWAppKeysOnly()) DMMSWFoldWindowKeys();   // (records by window key, from the Stage Manager engine before an engine change: by app here)
    BOOL multi = DMMSWMulti();
    if (!multi && !gMSWAwayCount && !gMSWAwayNatives.count) return;
    NSInteger cur = DMMSWCurId();
    NSUInteger away = 0;
    NSMutableSet<NSString *> *alive = [NSMutableSet set];
    NSArray<UIView *> *stages = DMAerialStagesAll();
    for (UIView *st in stages) {
        NSString *b = DMStageBundle(st);
        if (!b.length) continue;
        [alive addObject:b];
        NSNumber *quit = gMSWQuitting[b];
        if (quit && CACurrentMediaTime() < quit.doubleValue) {   // (force quit: its window goes as it is -- an away one stays hidden and away until
            if ([objc_getAssociatedObject(st, kMSWAwayKey) boolValue]) { st.hidden = YES; away++; }   //  the engine has taken it out; with its record
            continue;                                             //  gone it was taken for a new window here and shown on this desktop, 7 Oct)
        }
        NSNumber *d = gMSWWinDesk[b];
        if (multi && (!d || ![gMSWDesks containsObject:d])) { gMSWWinDesk[b] = d = @(cur); gMSWDesksDirty = YES; }
        BOOL want = multi && d.integerValue != cur && !(gMSWDropHold && [b isEqualToString:gMSWDropHold]), is = [objc_getAssociatedObject(st, kMSWAwayKey) boolValue];
        if (want) {
            if (!is) {
                CFTimeInterval a0 = CACurrentMediaTime();
                NSString *how = @"";
                if (!st.hidden && st.bounds.size.width > 100 && !gMSWWinShots[b] && !DMTestFlag("/tmp/msw-nowinpics")) {   // (its picture, for the desktop's thumbnail if its set of windows changes
                                                                                       //  while away; one taken just now -- a drop -- is kept)
                    UIView *fresh = gMSWFreshPics[b];   // (cut out of the left desktop's picture just before the switch's windows change, DMMSWCutOutsFrom)
                    if (fresh) { if (!gMSWWinShots) gMSWWinShots = [NSMutableDictionary dictionary]; gMSWWinShots[b] = fresh; [gMSWFreshPics removeObjectForKey:b]; how = @" cut out of the left picture"; }
                    else if (DMMSWAsyncPicsOn()) how = @": none (not a switch)";
                    else {
                        DMMSWSpanBegin();
                        UIView *pic = [st snapshotViewAfterScreenUpdates:NO];
                        DMMSWSpanEnd([NSString stringWithFormat:@"away picture of %@", b]);
                        if (pic) { if (!gMSWWinShots) gMSWWinShots = [NSMutableDictionary dictionary]; gMSWWinShots[b] = pic; }
                    }
                }
                CFTimeInterval a1 = CACurrentMediaTime();
                objc_setAssociatedObject(st, kMSWAwayKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                DMMSWFocusAway(b, YES);
                gMSWWinFrame[b] = NSStringFromCGRect(st.frame); gMSWDesksDirty = YES;
                DMLog([NSString stringWithFormat:@"[macswitcher] %@'s window is on Desktop %lu: away (picture %.1f ms%@, focus %.1f ms)", b, (unsigned long)[gMSWDesks indexOfObject:d] + 1, (a1 - a0) * 1000, how, (CACurrentMediaTime() - a1) * 1000]);
            } else if (!st.hidden) DMLog([NSString stringWithFormat:@"[macswitcher] %@'s window was shown while away: hidden again", b]);
            st.hidden = YES;
            DMMSWFocusAway(b, YES);   // (again until its scene is there: after a respring the window comes before its scene)
            away++;
        } else if (is) {
            objc_setAssociatedObject(st, kMSWAwayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DMMSWFocusAway(b, NO);
            if (!gMSWSwInChange) [gMSWWinShots removeObjectForKey:b];   // (a switch's change keeps it until the switch ends: a redirect may leave at once, DMMSWSwEnd)
            if (!DMMSWMinimizedByUs(st)) st.hidden = NO;   // (one we minimized stays minimized)
            if ([objc_getAssociatedObject(st, kZetsuLockPillKey) boolValue] && !DMMSWMinimizedByUs(st)) {   // (the lock collapsed it while away; one we minimized
                objc_setAssociatedObject(st, kZetsuLockPillKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   //  keeps the mark: opened when its app is, DMZetsuSurface)
                if (DMMSWZetsuReduced(st)) DMMSWZetsuReopen((UIWindow *)st);
            }
            DMLog([NSString stringWithFormat:@"[macswitcher] %@'s window is back (its desktop is current)", b]);
        }
    }
    gMSWAwayCount = away;
    for (NSString *b in gMSWQuitting.allKeys) if (CACurrentMediaTime() >= gMSWQuitting[b].doubleValue) [gMSWQuitting removeObjectForKey:b];
    for (NSString *b in gMSWNoFocus.allKeys) if (![alive containsObject:b]) DMMSWFocusAway(b, NO);
    // (a picture of a window recorded nowhere goes; a Stage Manager window's picture is kept by its key, and its record may still be its app's -- an
    //  older build's, taken over by MacSwitcherSM.h's tick within 20 s of a start: its picture stays meanwhile)
    for (NSString *b in gMSWWinShots.allKeys) if (!gMSWWinDesk[b] && !(DMSMEngine() && !DMSMKeyIsApp(b) && gMSWWinDesk[DMSMKeyBundle(b)])) [gMSWWinShots removeObjectForKey:b];
    // closed windows of the current desktop are forgotten; another desktop's record stays (its app may have been closed by iPadOS meanwhile: it
    // comes back when its desktop does, DMMSWRelaunchClosed)
    if (multi && gWindowSaveOn && !gRestoringWindows && !DMSMEngine())
        // (a Stage Manager window's key "<bundle>|<scene>" is never an app of this engine's: kept -- re-check N-1)
        for (NSString *b in gMSWWinDesk.allKeys) if (DMSMKeyIsApp(b) && ![alive containsObject:b] && gMSWWinDesk[b].integerValue == cur && CACurrentMediaTime() > gMSWRelaunching[b].doubleValue) { [gMSWWinDesk removeObjectForKey:b]; [gMSWWinFrame removeObjectForKey:b]; gMSWDesksDirty = YES; }
    BOOL nativesChanged = NO;
    for (DMNativeWindow *w in [gNativeWindows copy]) {
        NSNumber *d = objc_getAssociatedObject(w, kMSWNativeDeskKey);
        if (!multi) continue;
        if (!d || ![gMSWDesks containsObject:d]) { d = @(cur); objc_setAssociatedObject(w, kMSWNativeDeskKey, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (d.integerValue == cur || w.hidden || w == gMSWDropHoldNative) continue;   // (a minimized one stays in Finder's list where it is; a dropped one until it lands)
        if (gNativeActive == w) DMNativeSetActive(nil);
        [w removeFromSuperview]; [gNativeWindows removeObjectIdenticalTo:w]; [gMSWAwayNatives addObject:w];
        nativesChanged = YES;
        DMLog([NSString stringWithFormat:@"[macswitcher] native window %@ is away", w.title]);
    }
    for (DMNativeWindow *w in [gMSWAwayNatives copy]) {
        NSNumber *d = objc_getAssociatedObject(w, kMSWNativeDeskKey);
        if (multi && d && d.integerValue != cur && [gMSWDesks containsObject:d]) continue;
        UIView *host = DMNativeHost();
        if (!host) continue;
        [gMSWAwayNatives removeObjectIdenticalTo:w];
        if (!gNativeWindows) gNativeWindows = [NSMutableArray array];
        [gNativeWindows addObject:w]; [host addSubview:w]; w.hidden = NO;
        nativesChanged = YES;
        DMLog([NSString stringWithFormat:@"[macswitcher] native window %@ is back", w.title]);
    }
    if (nativesChanged) { if (gNativeLayer && gNativeWindows.count) gNativeLayer.hidden = NO; DMNativeApplyLevel(); }
    if (gMSWDesksDirty) DMMSWSave();
}
// Quit on purpose (Force Quit): the app's desktop record goes, so opening it later is a new window on the current desktop, as on a Mac.
// (a full-screen app remembered on another desktop has no window record: it was kept -- returned early -- and that desktop opened the quit app
//  again when it came; seen with a full-screen app dragged onto another desktop, 4 Oct)
// Its window, if it has one, is left as it is while the engine takes it out (DMMSWApply: an away one stays hidden -- with the record gone the tick
// took the dying window for a new one of the current desktop and showed it there for 0.2-1 s, 7 Oct).
static void DMMSWForgetApp(NSString *b) {
    if (!b.length) return;
    if (!gMSWQuitting) gMSWQuitting = [NSMutableDictionary dictionary];
    gMSWQuitting[b] = @(CACurrentMediaTime() + 4.0);
    // (every record of the app: Aerial's by app; the Stage Manager engine's one per window, "<bundle>|<scene>" -- SMWindowKey.h, M-2)
    NSMutableArray<NSString *> *mine = [NSMutableArray array];
    for (NSString *k in gMSWWinDesk.allKeys) if ([DMSMKeyBundle(k) isEqualToString:b]) [mine addObject:k];
    BOOL had = mine.count > 0;
    for (NSString *k in gMSWFullScreen.allKeys) if ([gMSWFullScreen[k] isEqualToString:b]) { [gMSWFullScreen removeObjectForKey:k]; had = YES; }
    if (!had) return;
    for (NSString *k in mine) { [gMSWWinDesk removeObjectForKey:k]; [gMSWWinFrame removeObjectForKey:k]; [gMSWWinShots removeObjectForKey:k]; }
    // (and out of the Fit to Window arrangements other desktops keep while away: their tiles close up as when a tiled window closes -- two or
    //  more take the default tiles, one fills (DMFitPlanAfterLeave). Kept, that desktop came back with a tile for a window that was gone, re-tiled
    //  only a tick later by the closure check, 1.4 logic test L-4. Aerial / Zetsu / MilkyWay4: group, slots, free by app. A Stage Manager desktop's
    //  arrangement (smslots / smfree, by window key) is the engine's own Fit tick's: an arrangement that no longer covers its windows is laid out
    //  the default way when the desktop comes)
    for (NSString *dk in [gMSWFit allKeys]) {
        NSDictionary *fit = gMSWFit[dk];
        if (![fit isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *nf = [fit mutableCopy];
        BOOL changed = NO;
        NSArray *group = [fit[@"group"] isKindOfClass:[NSArray class]] ? fit[@"group"] : nil;
        if ([group containsObject:b]) {
            NSMutableArray *left = [NSMutableArray array];
            for (id x in group) if ([x isKindOfClass:[NSString class]] && ![x isEqualToString:b]) [left addObject:x];
            nf[@"group"] = left; nf[@"slots"] = left.count ? DMFitPlanAfterLeave(left) : @{};
            changed = YES;
        }
        NSArray *free = [fit[@"free"] isKindOfClass:[NSArray class]] ? fit[@"free"] : nil;
        if ([free containsObject:b]) { NSMutableArray *f2 = [free mutableCopy]; [f2 removeObject:b]; nf[@"free"] = f2; changed = YES; }
        if (changed) { gMSWFit[dk] = nf; DMLog([NSString stringWithFormat:@"[macswitcher] %@ force quit: out of desktop id %@'s Fit to Window arrangement too", b, dk]); }
    }
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ force quit: its desktop record is forgotten", b]);
    DMMSWSave();
}
// A window whose app iPadOS closed while its desktop was away: opened again as a window at its place (a normal launch, never an empty frame).
static void DMMSWRelaunchClosed(void) {
    NSInteger cur = DMMSWCurId();
    NSMutableSet *alive = [NSMutableSet set];
    // (MilkyWay4 keeps the window of an app iPadOS closed -- grey, its app gone -- where Aerial and Zetsu take theirs away: an away window of the
    //  coming desktop whose app is not running is taken for closed, goes with MilkyWay's own close, and its app opens again at its place below,
    //  as on the other engines -- it came back as an empty grey window, M1 7 Oct. Minimized ones stay as they are.)
    BOOL mw = DMActiveEngine() == DMEngineMilkyWay;
    NSMutableSet<NSString *> *deadMW = [NSMutableSet set];
    NSSet *running = nil;
    for (UIView *st in DMAerialStagesAll()) {
        NSString *b = DMStageBundle(st);
        if (!b.length) continue;
        if (mw && gMSWWinDesk[b].integerValue == cur && [objc_getAssociatedObject(st, kMSWAwayKey) boolValue] && !DMMSWMinimizedByUs(st)) {
            id sc = DMStageScene(st, b);
            if (!sc && !running) running = DMLiveRunningBundleIDs();
            if (sc ? !DMSceneAlive(sc) : ![running containsObject:b]) {
                DMLog([NSString stringWithFormat:@"[macswitcher] %@'s MilkyWay window kept no app while its desktop was away (closed by iPadOS): closed, its app opens again", b]);
                objc_setAssociatedObject(st, kFitSizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (no full screen to give back to an app that is gone)
                SEL close = NSSelectorFromString(@"closeButtonAction:");
                if ([st respondsToSelector:close]) ((void (*)(id, SEL, id))objc_msgSend)(st, close, nil);
                [deadMW addObject:b];
                continue;
            }
        }
        [alive addObject:b];
    }
    for (NSString *b in gMSWWinDesk.allKeys) {
        if (gMSWWinDesk[b].integerValue != cur || [alive containsObject:b] || !DMSMKeyIsApp(b)) continue;   // (a Stage Manager window's key "<bundle>|<scene>" is no app to open)
        CGRect f = gMSWWinFrame[b] ? CGRectFromString(gMSWWinFrame[b]) : CGRectNull;
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ was closed while its desktop was away: opened again as a window at %@", b, NSStringFromCGRect(f)]);
        if (!gMSWRelaunching) gMSWRelaunching = [NSMutableDictionary dictionary];
        gMSWRelaunching[b] = @(CACurrentMediaTime() + 8.0);
        BOOL placed = !CGRectIsNull(f) && f.size.width > 100 && f.size.height > 100;
        DMEngine e = DMActiveEngine();
        if (e == DMEngineZetsu || e == DMEngineMilkyWay) {
            // (Zetsu / MilkyWay4: the engine's own launch makes the window, placed at its frame when it appears -- the place it is given as the app's
            //  remembered frame, which their adoption takes. DMLaunchIntoTile is Aerial's: under Zetsu nothing opened, iPad 2 7 Oct.)
            if (placed) { if (!gLastWindowFrames) gLastWindowFrames = [NSMutableDictionary dictionary]; gLastWindowFrames[b] = [NSValue valueWithCGRect:f]; }
            if (e == DMEngineZetsu) DMZetsuLaunch(b);
            else if ([deadMW containsObject:b]) { NSString *bb = [b copy]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMLaunchAsWindow(bb); }); }   // (once MilkyWay's close is through)
            else DMLaunchAsWindow(b);
        } else if (placed) DMLaunchIntoTile(b, f); else DMOpenApp(b);
    }
}

// ==== the Spaces slide: how a desktop switch looks (every engine) ===============================================================================
// As on a Mac, the desktop that is left and the one that comes lie side by side and move together: with the fingers while a side swipe is held
// (the tracker, DMMSWTrack* in the gestures section), then on a spring that starts at the fingers' speed and never overshoots. A switch without a
// gesture (a tap in the Mac Switcher's strip, "+", opening an app whose window is on another desktop) is the same slide from rest. Reduce Motion:
// a cross-fade, nothing follows the fingers.
// Both desktops are PICTURES in our layer window: the left one's (taken when the gesture began, when the Mac Switcher opened, or now) and the
// coming one's (as it was left -- its thumbnail -- or drawn from its parts, DMMSWDeskPicture). A picture is one layer the render server moves; the
// committed spring plays on in the render server while SpringBoard's main thread does the switch's work under the slide (the first build slid live
// portals of every window and did the work between frames of the slide). Once the slide has landed and the live screen under it is drawn still
// (each engine says when: DMMSWWhenDrawn here, the stage wait in MacSwitcherSM.h), the slide fades to it.
static UIView *gMSWSlRoot;            // the slide's root in our layer window (turned with the screen); nil: no slide
static UIView *gMSWSlStrip;           // the pictures side by side, moved as one: its x translation is the slide's offset
static UIView *gMSWSlOld;             // the left desktop's picture (at the strip's x 0)
static UIView *gMSWSlSide[2];         // the pictures beside it: [0] the desktop on the left (at -W), [1] the one on the right (at +W)
static NSMutableArray<UIView *> *gMSWSlPortals;   // the live parts of pictures drawn from parts (let go with the slide)
static CGFloat gMSWSlW = 0;           // how far one desktop is from the next on the strip: the screen's width
static NSUInteger gMSWSlGen = 0, gMSWSlFinGen = 0;   // which slide / which ending a late completion belongs to
static UIView *gMSWOpenShot;          // the screen as it was when the Mac Switcher opened: the left desktop's picture for a switch from its strip
static const void *kMSWSharedKey = &kMSWSharedKey;   // (a picture that wants the shared windows' portals)
static const void *kMSWDrawnKey = &kMSWDrawnKey;     // (a desktop's kept picture drawn from its parts: wants the shared windows again at every slide)
static const void *kMSWNotKeptKey = &kMSWNotKeptKey;   // (a left picture never kept as its desktop's thumbnail: drawn from parts, DMMSWLeftFromParts / DMMSWSwEnd)
static NSInteger gMSWOpenShotId = 0;
static NSUInteger gMSWOpenShotGen = 0; // (which opening a picture on its way belongs to: a late one of an earlier opening, or one taken before a drop, is dropped)
static void DMMSWOpenShotDrop(void) { gMSWOpenShot = nil; gMSWOpenShotGen++; }
static UIView *gMSWLiftPic;           // the screen as it was when the last side-swipe-able gesture began (until a switch takes it, or 2 s)
static CFTimeInterval gMSWLiftPicAt = 0;
static NSInteger gMSWLiftPicId = 0;
static NSUInteger gMSWTrackPicGen = 0;   // (which gesture a picture on its way belongs to: counted at each gesture's start, the gestures section)
static NSUInteger gMSWLiftPicGen = 0; // (which gesture it belongs to: gMSWTrackPicGen then)
static BOOL DMMSWGestureAlive(id gesture);   // (the gestures section: still held)
static __weak id gMSWLiftPicGesture;  // (that gesture: kept while it is still held -- a hold that opens the view may last more than 2.5 s)
static int gMSWTrack = 0;             // the tracker (gestures section): 0 idle, 1 armed (a gesture began), 2 the slide follows the fingers, 3 lifted
static BOOL gMSWTrackCommit = NO;     // (the tracker hands its slide to the switch it starts: DMMSWSwitchRun / DMMSWSMSwitch take that slide)
static NSInteger gMSWPendingSide = 0; // a side swipe that ended while a switch was still on its way: its desktop comes right after
static const CGFloat kMSWSlideOmega = 20.0;   // the spring (critically damped): from rest, done to the eye in ~0.38 s, within 1 pt in ~0.49 s
static BOOL gMSWSlFresh = NO;         // (the slide's window was shown in this very frame: its first motion waits one frame, DMMSWSlFinish)
static CFTimeInterval gMSWSlQuietAt = 0;   // (when the ending slide has 97% of its way behind it: the switch's own work goes there, DMMSWSwitchRun)
static const NSTimeInterval kMSWRevealFade = 0.15, kMSWViewFade = 0.18;
static UIView *DMMSWDeskPicture(NSUInteger i, CGRect b);   // (below DMMSWComposedDesktop: the coming desktop's picture)
static UIView *DMMSWLeftFromParts(UIView *fsPic, UIView *fsSrc);   // (below DMMSWDeskPicture: the desktop on the screen drawn from its parts)
static void DMMSWSlShared(UIView *pic);                    // (below it: a picture drawn from parts gets the shared windows, live)
static void DMMSWTrackTick(void);                          // (the gestures section: a followed gesture that ended without its end)
// More desktops on the strip than the two beside the left one: a slide that a swipe or a Control-arrow sent on further while it ran (the running
// switch, DMMSWSwRedirect) gets the next desktop's picture at its place, k screens from the left desktop (k = its place minus the left one's).
static NSMutableDictionary<NSNumber *, UIView *> *gMSWSlMore;
static NSMutableDictionary<NSNumber *, NSNumber *> *gMSWSlPlaces;   // (the running switch, below: slot -> the desktop place whose picture is there)
// The spring the strip is on now (DMMSWSlFinishTo): a redirect starts the next one where it is, at the speed it has there -- no jump, no stop.
static CFTimeInterval gMSWSlSpT0 = 0;   // when it began (media time; 0: none running)
static CGFloat gMSWSlSpE0 = 0, gMSWSlSpU0 = 0, gMSWSlSpW = 0;   // its distance from the end then, its speed along x then, its omega
static BOOL gMSWSlSpFade = NO;          // (Reduce Motion: a cross-fade, nothing moves)
static __weak UIView *gMSWSlFadeTop;    // (Reduce Motion: the picture that shows now -- the clip on top, opaque --; the next one fades in over it)

@interface DMMSWSlideDelegate : NSObject <CAAnimationDelegate>
@property (nonatomic, copy) void (^done)(void);
@end
@implementation DMMSWSlideDelegate
- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag { void (^d)(void) = self.done; self.done = nil; if (d) d(); }
@end

// A picture on the strip at r: in a clip of that size, scaled to fill it from its centre (one taken in the other orientation still covers it).
static void DMMSWSlPut(UIView *pic, CGRect r) {
    UIView *clip = [[UIView alloc] initWithFrame:r];
    clip.clipsToBounds = YES; clip.userInteractionEnabled = NO; clip.backgroundColor = [UIColor blackColor];
    clip.layer.allowsGroupOpacity = !DMTestFlag("/tmp/msw-nogroupop");   // (Reduce Motion fades a clip in over the other: as one picture, see DMMSWSlBegin)
    [pic removeFromSuperview];
    pic.transform = CGAffineTransformIdentity; pic.alpha = 1;
    CGSize s = pic.bounds.size;
    CGFloat k = MAX(r.size.width / MAX(1.0, s.width), r.size.height / MAX(1.0, s.height));
    if (fabs(k - 1.0) > 0.001) pic.transform = CGAffineTransformMakeScale(k, k);
    pic.center = CGPointMake(r.size.width / 2.0, r.size.height / 2.0);
    [clip addSubview:pic];
    [gMSWSlStrip addSubview:clip];
}
// Gone at once: the pictures go back to whoever keeps them (thumbnails), the portals are let go, the layer window hides (unless the view is up).
static void DMMSWSlDrop(void) {
    if (!gMSWSlRoot) return;
    gMSWSlGen++;
    [gMSWSlStrip.layer removeAllAnimations];
    UIView *pics[3] = { gMSWSlOld, gMSWSlSide[0], gMSWSlSide[1] };
    for (int i = 0; i < 3; i++) if (pics[i]) { [pics[i] removeFromSuperview]; pics[i].transform = CGAffineTransformIdentity; pics[i].alpha = 1; }
    for (UIView *p in gMSWSlMore.allValues) { [p removeFromSuperview]; p.transform = CGAffineTransformIdentity; p.alpha = 1; }
    for (UIView *p in gMSWSlPortals) DMMSWPortalLetGo(p);
    gMSWSlPortals = nil; gMSWSlMore = nil; gMSWSlPlaces = nil; gMSWSlSpT0 = 0; gMSWSlSpFade = NO;
    [gMSWSlRoot removeFromSuperview];
    gMSWSlRoot = nil; gMSWSlStrip = nil; gMSWSlOld = nil; gMSWSlSide[0] = gMSWSlSide[1] = nil;
    if (!gMSWOpen) gMSWWindow.hidden = YES;
}
// The layer window shown -- measured on the M1, the render server drew no frame for ~13 ms after the window came up in the frame the motion began
// in; so a gesture that may become a slide shows it (empty, touches going through) when it begins, and a slide from rest starts moving a frame
// after its window is up (gMSWSlFresh).
static BOOL DMMSWLayerUp(BOOL interactive) {
    UIWindow *w = DMMSWLayer();
    if (!w) return NO;
    w.userInteractionEnabled = interactive;
    if (w.hidden) { w.hidden = NO; gMSWSlFresh = YES; dispatch_async(dispatch_get_main_queue(), ^{ gMSWSlFresh = NO; }); }
    return YES;
}
// The slide comes up: the left desktop's picture covers the screen; the pictures of the desktops on its left and right (nil: none) wait beside it.
static BOOL DMMSWSlBegin(UIView *old, UIView *leftPic, UIView *rightPic) {
    UIWindow *w = DMMSWLayer();
    if (!w || !old) return NO;
    DMMSWSlDrop();
    DMMSWLayerUp(YES);
    UIView *host = w.rootViewController.view ?: w;
    UIView *root = [UIView new];
    root.userInteractionEnabled = YES;                 // (touches wait until the slide is over)
    root.backgroundColor = [UIColor blackColor];       // (what shows past the last desktop, under the rubber band)
    // (faded as ONE picture: SpringBoard's layers do not composite a subtree as a group by default -- the reveal's fade showed the black backgrounds
    //  under the pictures through them, the screen dipping ~35% darker mid-fade on every switch; K-1 / K-3, M1 8 Oct)
    root.layer.allowsGroupOpacity = !DMTestFlag("/tmp/msw-nogroupop");
    [host insertSubview:root atIndex:0];               // (under the Mac Switcher's view while that fades away)
    DMMSWTurnIn(w, root);
    CGRect b = root.bounds;
    UIView *strip = [[UIView alloc] initWithFrame:b];
    strip.userInteractionEnabled = NO;
    [root addSubview:strip];
    gMSWSlRoot = root; gMSWSlStrip = strip; gMSWSlW = b.size.width; gMSWSlGen++;
    gMSWSlOld = old; DMMSWSlPut(old, b);
    gMSWSlFadeTop = old.superview;   // (Reduce Motion: it shows; the coming one fades in over it)
    if (leftPic && leftPic != old) { gMSWSlSide[0] = leftPic; DMMSWSlPut(leftPic, CGRectOffset(b, -gMSWSlW, 0)); }
    if (rightPic && rightPic != old && rightPic != leftPic) { gMSWSlSide[1] = rightPic; DMMSWSlPut(rightPic, CGRectOffset(b, gMSWSlW, 0)); }
    DMMSWSlShared(old);   // (only a picture drawn from parts takes them: the left desktop drawn from its parts, DMMSWLeftFromParts)
    if (gMSWSlSide[0]) DMMSWSlShared(gMSWSlSide[0]);
    if (gMSWSlSide[1]) DMMSWSlShared(gMSWSlSide[1]);
    DMMSWRecTrack(strip);
    return YES;
}
// (DMMSWSpringTime / DMMSWSpringQuiet / DMMSWSpringE / DMMSWSpringU: the critically damped spring's settling time, slow tail, position and
//  speed -- MSWSlideMath.h)
static CGFloat DMMSWSlOffsetNow(void) {
    CALayer *pl = gMSWSlStrip.layer.presentationLayer;
    return pl ? pl.transform.m41 : gMSWSlStrip.transform.tx;
}
static void DMMSWSlSetOffset(CGFloat o) {
    if (!gMSWSlStrip) return;
    gMSWSlStrip.transform = CGAffineTransformMakeTranslation(o, 0);   // (outside an animation block: a UIView change is not animated)
}
// The picture k screens from the left desktop's on the strip (0: the left desktop's own, -1 / +1 the ones beside it), or nil.
static UIView *DMMSWSlPicAt(NSInteger k) {
    if (k == 0) return gMSWSlOld;
    if (k == -1 || k == 1) return gMSWSlSide[k > 0 ? 1 : 0];
    return gMSWSlMore[@(k)];
}
// The slide's speed along x now (points per second), read from its spring's equation (critically damped: e(t) = (e0 + (u0 + w e0) t) e^-wt, so
// e'(t) = (u0 - w (u0 + w e0) t) e^-wt); 0 when nothing moves.
static CGFloat DMMSWSlSpeedNow(void) {
    if (!gMSWSlStrip || gMSWSlSpT0 <= 0 || gMSWSlSpFade) return 0;
    double t = CACurrentMediaTime() - gMSWSlSpT0;
    if (t < 0) return gMSWSlSpU0;   // (it begins a frame later: still its start)
    double u = DMMSWSpringU(gMSWSlSpE0, gMSWSlSpU0, gMSWSlSpW, t);
    return isfinite(u) ? (CGFloat)u : 0;
}
// The slide goes to the desktop k screens from the left one: +1 = the desktop on the right comes (the strip moves left by a screen), -1 = the
// one on the left, 0 = back; further after a redirect (DMMSWSwRedirect puts that desktop's picture on the strip first). v: the speed along x it
// starts with (points per second): the fingers' at a lift, the running slide's for a redirect, so the desktop neither jumps nor stops. A
// critically damped spring overshoots only when it starts towards its end faster than omega x the distance; such a start gets a stiffer spring
// instead (it lands sooner, still without overshoot). Reduce Motion: the coming picture fades in over the one that shows, nothing moves.
static CGFloat gMSWSlMaxAway = 900.0;   // (how fast the slide may start away from its end: a lift's flick back a short way; a redirect's turn more)
static void DMMSWSlFinishTo(NSInteger k, CGFloat v, void (^landed)(void)) {
    UIView *strip = gMSWSlStrip;
    if (!strip) { if (landed) landed(); return; }
    NSUInteger gen = gMSWSlGen, fin = ++gMSWSlFinGen;
    void (^land)(void) = ^{ if (gen != gMSWSlGen || fin != gMSWSlFinGen) return; gMSWSlSpT0 = 0; DMMSWMark(@"slide end"); if (landed) landed(); };
    UIView *in = DMMSWSlPicAt(k);
    if (k && !in) { k = 0; in = gMSWSlOld; }
    CGFloat target = -k * gMSWSlW;
    if (MSBReduceMotion()) {   // (a cross-fade: the coming picture's clip on top, fading in over what shows now; one that shows already: no change)
        [strip.layer removeAllAnimations];
        strip.transform = CGAffineTransformIdentity;
        gMSWSlSpT0 = 0; gMSWSlSpFade = YES;
        UIView *inClip = in.superview;
        if (!inClip || inClip == gMSWSlFadeTop) { land(); return; }
        inClip.frame = strip.bounds;
        [inClip.layer removeAllAnimations];
        inClip.alpha = 0;
        [strip bringSubviewToFront:inClip];
        gMSWSlFadeTop = inClip;
        DMMSWMark(@"slide start (cross-fade)");
        gMSWSlQuietAt = CACurrentMediaTime() + kMSBRMDuration * 0.7;
        [UIView animateWithDuration:kMSBRMDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{ inClip.alpha = 1; } completion:^(BOOL f) { land(); }];
        return;
    }
    gMSWSlSpFade = NO;
    CGFloat from = DMMSWSlOffsetNow(), d = target - from;
    [strip.layer removeAnimationForKey:@"msw.slide"]; [strip.layer removeAnimationForKey:@"msw.catch"];
    strip.transform = CGAffineTransformMakeTranslation(target, 0);
    gMSWSlQuietAt = CACurrentMediaTime();
    if (fabs(d) < 0.5) { gMSWSlSpT0 = 0; land(); return; }
    CGFloat toward = v * (d > 0 ? 1.0 : -1.0);   // (> 0: the fingers were moving towards the end)
    CGFloat omega = kMSWSlideOmega;
    if (toward > 0) omega = MIN(42.0, MAX(omega, toward / (0.9 * fabs(d))));
    else toward = MAX(toward, -gMSWSlMaxAway);   // (moving away from it: a short way on, then back -- never flung)
    CASpringAnimation *a = [CASpringAnimation animationWithKeyPath:@"transform.translation.x"];
    a.mass = 1.0; a.stiffness = omega * omega; a.damping = 2.0 * omega;
    a.initialVelocity = toward / fabs(d);        // (in distances per second, as Core Animation's springs take it)
    a.fromValue = @(from); a.toValue = @(target);
    a.duration = DMMSWSpringTime(from - target, toward * (d > 0 ? 1.0 : -1.0), omega);   // (the speed the spring starts with, along x)
    BOOL fresh = gMSWSlFresh;
    if (fresh) { a.beginTime = [strip.layer convertTime:CACurrentMediaTime() fromLayer:nil] + 1.0 / 120.0; a.fillMode = kCAFillModeBackwards; }   // (the window came up this frame)
    gMSWSlQuietAt = CACurrentMediaTime() + (fresh ? 1.0 / 120.0 : 0) + DMMSWSpringQuiet(from - target, toward * (d > 0 ? 1.0 : -1.0), omega);
    gMSWSlSpT0 = CACurrentMediaTime() + (fresh ? 1.0 / 120.0 : 0); gMSWSlSpE0 = from - target; gMSWSlSpU0 = toward * (d > 0 ? 1.0 : -1.0); gMSWSlSpW = omega;
    DMMSWSlideDelegate *dl = [DMMSWSlideDelegate new];
    dl.done = land;
    a.delegate = dl;
    [strip.layer addAnimation:a forKey:@"msw.slide"];
    [CATransaction flush];   // (to the render server now: SpringBoard's own work in this turn -- a gesture's end runs ~50 ms -- must not hold the start back)
    DMMSWMark([NSString stringWithFormat:@"slide start (to %+ld, %.0f -> %.0f pt, %.0f pt/s, omega %.1f, %.0f ms%@)", (long)k, from, target, v, omega, a.duration * 1000.0, gMSWSlFresh ? @", a frame after its window" : @""]);
}
static void DMMSWSlFinish(NSInteger side, CGFloat v, void (^landed)(void)) { DMMSWSlFinishTo(side, v, landed); }   // (one desktop either way, or back)
// The slide has landed and the live screen under it is drawn: the slide fades to it and goes.
static void DMMSWSlReveal(NSTimeInterval fade, void (^done)(void)) {
    UIView *root = gMSWSlRoot;
    if (!root) { if (done) done(); return; }
    NSUInteger gen = gMSWSlGen;
    DMMSWMark(@"reveal");
    root.userInteractionEnabled = NO;
    [UIView animateWithDuration:fade delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ root.alpha = 0; } completion:^(BOOL f) {
        if (gen == gMSWSlGen) DMMSWSlDrop();
        DMMSWMark(@"revealed");
        if (done) done();
    }];
}

// No picture of the coming desktop (Stage Manager: a desktop not seen since the respring): once the live screen shows the coming desktop, live
// portals of the screen's windows take the place of its picture beside the left one, and the slide goes there.
static void DMMSWSlLive(NSInteger side, CGFloat v, void (^done)(void)) {
    if (!gMSWSlRoot || !side) { DMMSWSlDrop(); if (done) done(); return; }
    CGRect b = gMSWSlRoot.bounds;
    UIView *fresh = [[UIView alloc] initWithFrame:b];
    fresh.backgroundColor = [UIColor blackColor]; fresh.userInteractionEnabled = NO;
    for (UIWindow *sw in DMMSWScreenWindows()) {
        CGRect r = CGRectNull;
        UIView *p = DMMSWPortalInPlace(sw, gMSWSlRoot, fresh, &r);
        if (!p) continue;
        [gMSWPortals removeObjectIdenticalTo:p];
        if (!CGRectEqualToRect(CGRectIntegral(CGRectInset(r, 0.5, 0.5)), CGRectIntegral(CGRectInset(b, 0.5, 0.5)))) { DMMSWPortalLetGo(p); continue; }
        if (!gMSWSlPortals) gMSWSlPortals = [NSMutableArray array];
        [gMSWSlPortals addObject:p];
    }
    int k = side > 0 ? 1 : 0;
    if (gMSWSlSide[k]) { [gMSWSlSide[k].superview removeFromSuperview]; [gMSWSlSide[k] removeFromSuperview]; gMSWSlSide[k].transform = CGAffineTransformIdentity; }
    gMSWSlSide[k] = fresh;
    DMMSWSlPut(fresh, CGRectOffset(b, side * gMSWSlW, 0));
    DMMSWSlFinish(side, v, ^{ DMMSWSlDrop(); if (done) done(); });
}

// The left desktop's picture for a switch: the one from when the Mac Switcher opened (a switch from its strip -- a picture taken now would have to
// wait for the screen to be drawn again without the view, ~80 ms of SpringBoard's main thread on the M1), the one from the start of the gesture
// (the card SpringBoard moved during the gesture is not in it), or the screen now.
// The screen as it is drawn now WITHOUT the Mac Switcher's own window: UIKit's -[UIScreen _snapshotExcludingWindows:withRect:] (checked; 15.6.1:
// @@:@{CGRect}), the call -snapshotViewAfterScreenUpdates: is built on. The desktop under the open view, e.g. once a window was dragged away from
// it (the picture from when the view opened still shows that window). nil when UIKit has no such call.
static UIView *DMMSWScreenWithoutView(void) {
    UIScreen *s = [UIScreen mainScreen];
    static int has = -1;
    if (has < 0) has = DMMSWHasMethod([UIScreen class], @"_snapshotExcludingWindows:withRect:", @"@@:@{CGRect={CGPoint=dd}{CGSize=dd}}");
    if (has <= 0) return nil;
    NSArray *skip = gMSWWindow ? @[gMSWWindow] : @[];
    UIView *v = nil;
    @try { v = ((id (*)(id, SEL, id, CGRect))objc_msgSend)(s, NSSelectorFromString(@"_snapshotExcludingWindows:withRect:"), skip, s.bounds); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] screen picture without the view threw %@", e]); v = nil; }
    return [v isKindOfClass:[UIView class]] ? v : nil;
}
// The left desktop's picture kept from the view's opening or the gesture's start (nil: none fits -- DMMSWSwitchRun asks for the screen then).
static UIView *DMMSWLeftPictureKept(BOOL wasOpen, NSString **src) {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    UIView *pic = nil;
    if (wasOpen && gMSWOpenShot && gMSWOpenShotId == DMMSWCurId() && CGSizeEqualToSize(gMSWOpenShot.bounds.size, screen)) { pic = gMSWOpenShot; *src = @"when the Mac Switcher opened"; }
    else if (!wasOpen && gMSWLiftPic && CACurrentMediaTime() - gMSWLiftPicAt < 2.0 && gMSWLiftPicId == DMMSWCurId() && CGSizeEqualToSize(gMSWLiftPic.bounds.size, screen)) { pic = gMSWLiftPic; *src = @"when the gesture began"; }
    DMMSWOpenShotDrop(); gMSWLiftPic = nil;
    return pic;
}
// The screen now, the waiting way (only where no picture can be asked without waiting): with the view open, the screen under it (a plain screen
// picture would show the view itself sliding away).
static UIView *DMMSWLeftPictureNow(BOOL wasOpen, NSString **src) {
    UIView *pic = nil;
    if (wasOpen) { pic = DMMSWScreenWithoutView(); if (pic) *src = @"now, without the view"; }
    if (!pic) { DMMSWSpanBegin(); pic = [[UIScreen mainScreen] snapshotViewAfterScreenUpdates:wasOpen]; DMMSWSpanEnd(@"left picture (the screen now)"); *src = wasOpen ? @"now, the screen as drawn" : @"now"; }
    return pic;
}
// Stage Manager's switch (MacSwitcherSM.h): the kept picture, else the screen now the waiting way -- as before (the iPad 2's path is not changed here).
static UIView *DMMSWLeftPicture(BOOL wasOpen) {
    NSString *src = nil;
    UIView *pic = DMMSWLeftPictureKept(wasOpen, &src);
    if (!pic) pic = DMMSWLeftPictureNow(wasOpen, &src);
    DMMSWMark([NSString stringWithFormat:@"left picture: %@", src]);
    return pic;
}
// The Mac Switcher's view, open when a switch starts from it: it fades away over the slide instead of vanishing (its thumbnails stay live until it
// is gone: the windows change under the slide only after it, DMMSWSwitchRun).
static void DMMSWCloseUnderSlide(void) {
    DMMSWDropFinishNow();
    DMMSWDragReset();   // (a drag in the view goes with it)
    UIView *vr = gMSWRoot;
    NSArray *portals = gMSWPortals;
    gMSWPortals = nil; gMSWTiles = nil; gMSWHilite = nil; gMSWRoot = nil;
    gMSWStrip = nil; gMSWStripPortals = nil; gMSWDeskClips = nil; gMSWDeskLabels = nil; gMSWPlusView = nil;
    gMSWOpen = NO; gMSWClosing = NO; gMSWTurnAt = 0;
    for (UIGestureRecognizer *g in [vr.gestureRecognizers copy]) [vr removeGestureRecognizer:g];
    DMMSWFocus(NO);
    DMMenuKeyboardOrder();
    if (!vr) return;
    vr.userInteractionEnabled = NO;
    // (the view fades over the slide as one picture, see DMMSWSlBegin -- not over the live blur: a blur inside a group drawn off screen sees
    //  nothing behind the group and went flat for the fade; that background is used only when the wallpaper can't be read. 1.4.1 logic test L-3)
    vr.layer.allowsGroupOpacity = !DMTestFlag("/tmp/msw-nogroupop") && ![objc_getAssociatedObject(vr, kMSWLiveBlurKey) boolValue];
    [vr.superview bringSubviewToFront:vr];
    [UIView animateWithDuration:kMSWViewFade delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{ vr.alpha = 0; } completion:^(BOOL f) {
        for (UIView *p in portals) DMMSWPortalLetGo(p);
        [vr removeFromSuperview];
        DMLog([NSString stringWithFormat:@"[macswitcher] closed under the slide: %lu portals let go", (unsigned long)portals.count]);
    }];
}

// ---- a full-screen app's change under the slide, without SpringBoard's animations (F8, 7 Oct) ----
// A switch that sends the left desktop's full-screen app Home, or opens the coming desktop's again, did it the way a user does: a simulated Home
// press (DMMinimize: -[SpringBoard _simulateHomeButtonPressWithCompletion:]) and a launch (DMOpenFullScreen). Both play SpringBoard's own ~0.5 s
// animations: unseen under the slide, yet their set-up held the main thread 25-47 ms at the slide's start (frames of 43-125 ms, the M1's F8
// measurements) and the reveal waited 0.2-0.3 s after the landing for them to end. As nothing of them can be seen under the slide, the same
// workspace transitions are asked for, as SpringBoard itself builds them -- read on the M1 (debug probe /tmp/msw-wsprobe): the Home press asks
// SBMainWorkspace for a request whose application context's activating entity is an SBHomeScreenEntity, a launch for one with the app's scene
// entity in the primary layout role (-requestTransitionWithBuilder:) -- with the animation off (-setAnimationDisabled:YES). (A context asking only
// for the Home Screen's environment mode was taken, yet left the app in front and the Home Screen half shown.) One transition when both happen:
// the left app goes, the coming one comes. Each class and method is type-checked once; anything missing, a request SpringBoard does not take, or
// one that has not changed the front app when the slide has landed (DMMSWSwChange): the animated way, as before (also with the debug flag
// /tmp/msw-animfs, for comparisons).
static int gMSWQuietOK = -1;
static BOOL DMMSWQuietOK(void) {
    if (gMSWQuietOK >= 0) return gMSWQuietOK;
    // (read and verified on iPadOS 15.6.1, the M1 -- SpringBoard's own requests with the debug probe, the switches measured. 16 and 17 keep the
    //  animated way until the same is read there: then this line lets them in)
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion != 15) { gMSWQuietOK = 0; DMLog(@"[macswitcher] a full-screen app's change under the slide: the animated way (without animation only on iPadOS 15 so far)"); return NO; }
    NSMutableArray *missing = [NSMutableArray array];
    Class ws = objc_getClass("SBMainWorkspace"), rq = objc_getClass("SBMainWorkspaceTransitionRequest"), cx = objc_getClass("SBWorkspaceApplicationSceneTransitionContext");
    Class en = objc_getClass("SBDeviceApplicationSceneEntity"), ac = objc_getClass("SBApplicationController"), he = objc_getClass("SBHomeScreenEntity");
    Method wsShared = ws ? class_getClassMethod(ws, NSSelectorFromString(@"sharedInstance")) : NULL, acShared = ac ? class_getClassMethod(ac, NSSelectorFromString(@"sharedInstance")) : NULL;
    if (!wsShared || ![DMMSWBareTypes(method_getTypeEncoding(wsShared)) isEqualToString:@"@@:"] || !DMMSWHasMethod(ws, @"requestTransitionWithBuilder:", @"B@:@?")) [missing addObject:@"-[SBMainWorkspace requestTransitionWithBuilder:]"];
    if (!DMMSWHasMethod(rq, @"modifyApplicationContext:", @"v@:@?") || !DMMSWHasMethod(rq, @"setEventLabel:", @"v@:@")) [missing addObject:@"the request's -modifyApplicationContext: / -setEventLabel:"];
    if (!DMMSWHasMethod(cx, @"setAnimationDisabled:", @"v@:B")) [missing addObject:@"-setAnimationDisabled:"];
    if (!DMMSWHasMethod(cx, @"setActivatingEntity:", @"v@:@")) [missing addObject:@"-setActivatingEntity:"];
    if (!DMMSWHasMethod(he, @"init", @"@@:") || ![he isSubclassOfClass:objc_getClass("SBWorkspaceEntity")]) [missing addObject:@"SBHomeScreenEntity"];
    if (!DMMSWHasMethod(cx, @"setEntity:forLayoutRole:", @"v@:@q")) [missing addObject:@"-setEntity:forLayoutRole:"];
    if (!DMMSWHasMethod(en, @"initWithApplicationForMainDisplay:", @"@@:@")) [missing addObject:@"-[SBDeviceApplicationSceneEntity initWithApplicationForMainDisplay:]"];
    if (!acShared || ![DMMSWBareTypes(method_getTypeEncoding(acShared)) isEqualToString:@"@@:"] || !DMMSWHasMethod(ac, @"applicationWithBundleIdentifier:", @"@@:@")) [missing addObject:@"SBApplicationController"];
    gMSWQuietOK = missing.count == 0;
    DMLog(gMSWQuietOK ? @"[macswitcher] a full-screen app's change under the slide: without SpringBoard's animations (workspace transitions with the animation off)"
                      : [NSString stringWithFormat:@"[macswitcher] a full-screen app's change under the slide: the animated way (missing here: %@)", [missing componentsJoinedByString:@", "]]);
    return gMSWQuietOK;
}
static BOOL DMMSWQuietOn(void) { return DMMSWQuietOK() && !DMTestFlag("/tmp/msw-animfs"); }
static NSString *gMSWQuietAsked;   // (what the last windows change asked for without animation: an app, @"" for the Home Screen, nil nothing)
static BOOL gMSWChangeAskedWS = NO;   // (the last windows change asked SpringBoard for a workspace transition: a full-screen app sent Home or opened)
// One workspace transition without animation: the app `open` full screen in front, or (nil) the Home Screen. YES: SpringBoard took it.
static BOOL DMMSWQuietTransition(NSString *open, NSString *why) {
    if (!DMMSWQuietOn()) return NO;
    id entity = nil, home = nil;
    if (!open.length) {
        @try { home = ((id (*)(id, SEL))objc_msgSend)([objc_getClass("SBHomeScreenEntity") alloc], @selector(init)); } @catch (id e) { home = nil; }
        if (!home) { DMLog(@"[macswitcher] the Home Screen: no entity for it -- the animated way"); return NO; }
    } else {
        id app = ((id (*)(id, SEL, id))objc_msgSend)(DMCall(objc_getClass("SBApplicationController"), @"sharedInstance"), NSSelectorFromString(@"applicationWithBundleIdentifier:"), open);
        @try { entity = app ? ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("SBDeviceApplicationSceneEntity") alloc], NSSelectorFromString(@"initWithApplicationForMainDisplay:"), app) : nil; } @catch (id e) { entity = nil; }
        if (!entity) { DMLog([NSString stringWithFormat:@"[macswitcher] %@: no scene entity for it -- the animated way", open]); return NO; }
    }
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    __block BOOL wrote = NO;
    BOOL taken = NO;
    CFTimeInterval t0 = CACurrentMediaTime();
    void (^builder)(id) = ^(id req) {
        ((void (*)(id, SEL, id))objc_msgSend)(req, NSSelectorFromString(@"setEventLabel:"), @"MacSwitcherDesktopSwitch");
        ((void (*)(id, SEL, id))objc_msgSend)(req, NSSelectorFromString(@"modifyApplicationContext:"), ^(id ctx) {
            @try {
                if (entity) ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, NSSelectorFromString(@"setEntity:forLayoutRole:"), entity, 1);   // (as a launch: the primary role)
                else ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setActivatingEntity:"), home);   // (as the Home press: the Home Screen activating)
                ((void (*)(id, SEL, BOOL))objc_msgSend)(ctx, NSSelectorFromString(@"setAnimationDisabled:"), YES);
                wrote = YES;
            } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] the transition's context refused: %@", e.reason]); }
        });
    };
    gForceFullScreenLaunch = YES;   // (our own launch hooks leave the app full screen, should one see it)
    @try { taken = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, NSSelectorFromString(@"requestTransitionWithBuilder:"), builder); }
    @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] the workspace refused the transition: %@", e.reason]); taken = NO; }
    gForceFullScreenLaunch = NO;
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ without animation (%@): %@ (%.1f ms)", open ? [NSString stringWithFormat:@"%@ full screen", open] : @"the Home Screen", why,
        taken && wrote ? @"taken" : [NSString stringWithFormat:@"NOT taken (taken %d, written %d) -- the animated way", taken, wrote], (CACurrentMediaTime() - t0) * 1000]);
    return taken && wrote;
}

// The windows change under the slide (Aerial, Zetsu, MilkyWay4 / no engine): the left desktop's full-screen app stays there (Home now, opened again with its
// desktop), the keyboard and Finder's windows let go, Fit to Window per desktop, then every window where its record says. Returns the app that
// is to be full screen on the coming desktop (nil: none).
static NSString *DMMSWChangeDesktop(NSUInteger from, NSUInteger to) {
    NSInteger fromId = gMSWDesks[from].integerValue, toId = gMSWDesks[to].integerValue;
    SBApplication *front = DMFrontApp();
    NSString *leaving = nil;   // (the left desktop's full-screen app, sent Home at the end without animation -- with the coming one's, one transition)
    gMSWQuietAsked = nil; gMSWChangeAskedWS = NO;
    if (front && DMFullScreenAppInFront() && !DMSwitcherVisible() && [front bundleIdentifier].length) {
        NSString *fb = [front bundleIdentifier];
        gMSWFullScreen[[@(fromId) stringValue]] = fb;
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ is full screen on %@: it stays there", fb, DMMSWDeskName(from)]);
        // (an app full screen here has no window anywhere -- iPadOS's own App Switcher, a card of a window away on another desktop, gave it the full
        //  screen and Aerial took its window away -- so its window record goes: kept, it opened the app again as a window on that desktop, whose
        //  full-screen record here then took it back, to and fro at every switch, M1 7 Oct)
        BOOL hasWindow = NO;
        for (UIView *st in DMAerialStagesAll()) if ([DMStageBundle(st) isEqualToString:fb]) { hasWindow = YES; break; }
        if (gMSWWinDesk[fb] && !hasWindow) {
            DMLog([NSString stringWithFormat:@"[macswitcher] %@ is full screen now: its window record of desktop id %@ is forgotten", fb, gMSWWinDesk[fb]]);
            [gMSWWinDesk removeObjectForKey:fb]; [gMSWWinFrame removeObjectForKey:fb]; [gMSWWinShots removeObjectForKey:fb];
        }
        if (DMMSWQuietOn()) leaving = fb;   // (Home without animation, at the end)
        else DMMinimize();                  // (the animated way, where it always was)
        gMSWChangeAskedWS = YES;
    }
    if (gNativeActive) DMNativeSetActive(nil);
    DMResignWindowedKeyboards(nil);
    CGSize screen = [UIScreen mainScreen].bounds.size;
    if (!gMSWLeftSize) gMSWLeftSize = [NSMutableDictionary dictionary];
    gMSWLeftSize[[@(fromId) stringValue]] = NSStringFromCGSize(screen);
    // Fit to Window per desktop (owner's decision): the left desktop keeps its group, the new one's comes back
    if (!gMSWFit) gMSWFit = [NSMutableDictionary dictionary];
    gMSWFit[[@(fromId) stringValue]] = @{@"group": [gFitGroup copy] ?: @[], @"slots": [gFitSlots copy] ?: @{}, @"free": [gFreeWindows allObjects] ?: @[], @"fitOn": @(DMFitEnabled())};
    NSDictionary *fit = gMSWFit[[@(toId) stringValue]];
    [gMSWFit removeObjectForKey:[@(toId) stringValue]];
    gFitGroup = [NSMutableArray array]; gFitSlots = [NSMutableDictionary dictionary]; [gFreeWindows removeAllObjects];
    if ([fit[@"group"] isKindOfClass:[NSArray class]]) for (id b in fit[@"group"]) if ([b isKindOfClass:[NSString class]]) [gFitGroup addObject:b];
    if ([fit[@"slots"] isKindOfClass:[NSDictionary class]]) for (id b in fit[@"slots"]) if ([b isKindOfClass:[NSString class]] && [fit[@"slots"][b] isKindOfClass:[NSString class]]) gFitSlots[b] = fit[@"slots"][b];
    if ([fit[@"free"] isKindOfClass:[NSArray class]]) for (id b in fit[@"free"]) if ([b isKindOfClass:[NSString class]]) { if (!gFreeWindows) gFreeWindows = [NSMutableSet set]; [gFreeWindows addObject:b]; }
    gMSWCur = to;
    DMMSWMark(@"change: full screen, keyboard, Fit saved");
    DMMSWRelaunchClosed();   // (before DMMSWApply, which forgets the current desktop's records without a window)
    gMSWSwitching = NO; DMMSWApply(); gMSWSwitching = YES;
    DMMSWMark(@"change: windows applied");
    // (Fit to Window switched on while this desktop was away -- its arrangement was kept with Fit off, so it names no window, or only one dragged
    //  here since: its other windows join its tiles now, up to Fit's four, as the desktop on screen's did when Fit came on. Kept, a window dragged
    //  here filled the desktop over the window already there, 1.4 logic test)
    if (DMFitEnabled() && ![fit[@"fitOn"] boolValue]) {
        NSMutableArray<NSString *> *joined = [NSMutableArray array];
        for (UIView *st in DMAerialStagesAll()) {
            NSString *b = DMStageBundle(st);
            if (gFitGroup.count >= 4) break;
            if (!b.length || gMSWWinDesk[b].integerValue != toId || [gFitGroup containsObject:b] || [gFreeWindows containsObject:b] || !DMStageTakesPartInFit(st)) continue;
            [gFitGroup addObject:b]; [joined addObject:b];
        }
        if (joined.count) {
            if (gFitGroup.count >= 2) DMAssignDefaultSlots();
            DMLog([NSString stringWithFormat:@"[macswitcher] Fit to Window came on while %@ was away: %@ join%@ its tiles", DMMSWDeskName(to), [joined componentsJoinedByString:@", "], joined.count == 1 ? @"s" : @""]);
        }
    }
    // (Fit to Window's own rule: one window fills the space -- a window dragged alone onto "+" or onto an empty desktop kept the quarter it had,
    //  F4 7 Oct; DMMSWFitMove gives a group of one no slots)
    if (DMFitEnabled() && gFitGroup.count == 1 && ![gFitSlots[gFitGroup[0]] isEqualToString:@"fill"]) gFitSlots = [@{ gFitGroup[0]: @"fill" } mutableCopy];
    NSString *leftAt = gMSWLeftSize[[@(toId) stringValue]];
    if (leftAt && !CGSizeEqualToSize(CGSizeFromString(leftAt), screen) && CGSizeFromString(leftAt).width > 1) {   // (turned while away: its windows are arranged
        CGSize was = CGSizeFromString(leftAt);                                                                    //  for the new shape, as a turn arranges the shown ones)
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ was left at %@, the screen is %@ now: its windows are arranged for the turn", DMMSWDeskName(to), leftAt, NSStringFromCGSize(screen)]);
        dispatch_async(dispatch_get_main_queue(), ^{ DMRelayoutForOrientation(was, [UIScreen mainScreen].bounds.size); });   // (its Fit group is tiled again there)
    } else if (DMFitEnabled() && gFitGroup.count >= 1) {   // (its Fit group, tiled again for the screen as it is; one window fills)
        DMLog([NSString stringWithFormat:@"[macswitcher] %@'s Fit to Window group (%@) tiled again", DMMSWDeskName(to), [gFitGroup componentsJoinedByString:@", "]]);
        gMoveKeepsOrder = YES; DMApplyGroupSlots(nil); gMoveKeepsOrder = NO;
    }
    NSString *fs = gMSWFullScreen[[@(toId) stringValue]];
    if (fs) {
        [gMSWFullScreen removeObjectForKey:[@(toId) stringValue]];
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ was full screen on %@: opened again", fs, DMMSWDeskName(to)]);
        gMSWChangeAskedWS = YES;
        if (DMMSWQuietTransition(fs, leaving ? [NSString stringWithFormat:@"%@ goes with the same transition", leaving] : @"its desktop came")) gMSWQuietAsked = fs;
        else DMOpenFullScreen(fs);
        DMMSWMark(@"change: the coming full-screen app asked for");
    } else if (leaving) {
        if (DMMSWQuietTransition(nil, [NSString stringWithFormat:@"%@ stays on the left desktop", leaving])) gMSWQuietAsked = @"";
        else DMMinimize();
        DMMSWMark(@"change: the Home Screen asked for");
    }
    DMMSWSave();
    DM_FEATURE_MARK("mac-switcher-desktops");
    return fs;
}

// SpringBoard is between transitions: its workspace has no transaction running (the -currentTransaction it keeps, checked once), no switcher shows.
static BOOL DMMSWSpringBoardIdle(void) {
    if (DMSwitcherVisible()) return NO;
    static int has = -1;
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    if (has < 0 && ws) { has = DMMSWHasMethod(object_getClass(ws), @"currentTransaction", @"@@:"); DMLog([NSString stringWithFormat:@"[macswitcher] SpringBoard's workspace transaction %@", has ? @"is watched for the reveal" : @"cannot be asked: the reveal waits for still frames only"]); }
    return has <= 0 || DMCall(ws, @"currentTransaction") == nil;
}
// What the live screen under the slide shows now, as far as it can move: the front app, Aerial's layer, the current desktop's windows, Finder's
// windows and the full-screen app's view -- where they are drawn (presentation layers) and how opaque. The same string 3 frames running = still.
static NSString *DMMSWDrawnState(UIView *fsView) {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@|", [DMFrontApp() bundleIdentifier] ?: @"-"];
    void (^add)(UIView *) = ^(UIView *v) {
        CALayer *pl = v.layer.presentationLayer ?: v.layer;
        [s appendFormat:@"%.0f,%.0f,%.0f,%.0f,%.2f,%d;", pl.position.x, pl.position.y, pl.bounds.size.width, pl.bounds.size.height, pl.opacity, v.hidden];
    };
    UIWindow *al = DMActiveEngine() != DMEngineNone ? DMWindowLayer() : nil;
    if (al) add(al);
    for (UIView *st in DMAerialStages()) add(st);
    for (DMNativeWindow *w in gNativeWindows) add(w);
    if (fsView.window) add(fsView);
    return s;
}
// Aerial hides its whole layer while SpringBoard's switcher is up (a gesture shows it for a moment) and shows it again afterwards: when the desktop
// has windows to show, its layer must be up again. MilkyWay4's layer and Zetsu's windows (each one a window of its own) are faded out for the
// switcher the same way by us (DMZetsuSwitcherCheck): faded in again too.
static BOOL DMMSWWindowsShown(void) {
    DMEngine e = DMActiveEngine();
    if (e != DMEngineAerial && e != DMEngineMilkyWay && e != DMEngineZetsu) return YES;
    BOOL any = NO;
    for (UIView *st in DMAerialStages()) {
        if (st.hidden || DMStageMinimized(st)) continue;
        any = YES;
        if (e != DMEngineZetsu) break;
        CALayer *zl = st.layer.presentationLayer ?: st.layer;
        if (zl.opacity < 0.95) return NO;
    }
    if (e == DMEngineZetsu) return YES;
    UIWindow *l = any ? DMWindowLayer() : nil;
    if (!l) return YES;
    CALayer *pl = l.layer.presentationLayer ?: l.layer;
    return !l.hidden && pl.opacity > 0.95;
}
// Waits (each frame, at most 1.2 s after the slide landed) until the live screen is drawn still with what the coming desktop shows -- its
// full-screen app in front (wantFront), or none -- and SpringBoard is idle; then `then` (how: "drawn" or "not settled"). gone (may be nil): the
// wait is over without `then` (a redirect gave the slide another aim, whose own wait ends it).
static void DMMSWWhenDrawn(NSString *wantFront, BOOL (^landed)(void), BOOL (^gone)(void), void (^then)(NSString *how)) {
    __block NSString *before = nil;
    __block int still = 0, frames = 0;
    __block CFTimeInterval landedAt = 0;
    __block UIView *fsView = nil;
    __block void (^poll)(void);
    void (^p)(void) = ^{
        if (gone && gone()) { poll = nil; return; }
        frames++;
        BOOL frontOK = wantFront ? ([[DMFrontApp() bundleIdentifier] isEqualToString:wantFront] && DMFullScreenAppInFront()) : !DMFullScreenAppInFront();
        if (wantFront && frontOK && !fsView) fsView = DMMSWFullScreenView(wantFront, NO);
        NSString *now = DMMSWDrawnState(fsView);
        still = [now isEqualToString:before] ? still + 1 : 0;
        before = now;
        BOOL l = landed();
        if (l && !landedAt) landedAt = CACurrentMediaTime();
        BOOL ready = l && frontOK && still >= 3 && DMMSWSpringBoardIdle() && DMMSWWindowsShown();
        if (!ready && !(landedAt && CACurrentMediaTime() - landedAt > 1.2)) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 120)), dispatch_get_main_queue(), poll); return; }
        poll = nil;
        then(ready ? [NSString stringWithFormat:@"drawn after %d frames", frames] : [NSString stringWithFormat:@"not settled after %d frames (front %@, still %d, idle %d, windows shown %d): shown anyway", frames, frontOK ? @"ok" : @"not yet", still, DMMSWSpringBoardIdle(), DMMSWWindowsShown()]);
    };
    poll = p;
    dispatch_async(dispatch_get_main_queue(), poll);
}

// The switch to the desktop at place `to`: the slide (begun by the fingers -- the tracker --, or here from rest) goes there at speed v; a frame
// later the windows change under it (after the Mac Switcher's view has faded, when it was open); once the slide has landed and the live screen
// is drawn still, the slide fades to it. The left desktop's picture becomes its thumbnail.
static void DMMSWSwitchRun(NSUInteger to, NSString *why, CGFloat v, void (^done)(void));
static void DMMSWSwitchGo(NSUInteger to, NSString *why, CGFloat v, void (^done)(void), BOOL fromGesture, CFTimeInterval t0, UIView *old);
static void DMMSWSwitchTo(NSUInteger to, NSString *why, void (^done)(void)) { DMMSWSwitchRun(to, why, 0, done); }
static void DMMSWSwitchRun(NSUInteger to, NSString *why, CGFloat v, void (^done)(void)) {
    DMMSWDropFinishNow();   // (a window dropped in the view a moment ago leaves the screen first)
    if (DMSMEngine() && DMMSWDesktopsHere()) { DMMSWSMSwitchRun(to, why, v, done); return; }   // (Stage Manager: its stages swap, MacSwitcherSM.h)
    BOOL fromGesture = gMSWTrackCommit && gMSWSlRoot != nil;
    if (!DMMSWDesktopsHere() || to >= gMSWDesks.count || to == gMSWCur || gMSWSwitching || gMSWTrack == 2 || (gMSWTrack == 3 && !fromGesture)) {
        DMLog([NSString stringWithFormat:@"[macswitcher] no switch to %lu (%@): %@", (unsigned long)to, why, gMSWSwitching || gMSWTrack ? @"a slide is on its way" : @"no such desktop here"]);
        if (done) done();
        return;
    }
    gMSWSwitching = YES;
    CFTimeInterval t0 = CACurrentMediaTime();
    DMMSWRecBegin([NSString stringWithFormat:@"switch (%@)", why]);
    DMMSWMark(@"switch");
    if (fromGesture) { DMMSWSwitchGo(to, why, v, done, YES, t0, gMSWSlOld); return; }
    // the left desktop's picture: kept from the view's opening or the gesture's start; else the screen now, asked without waiting (F5) -- the slide
    // comes up when it is in (typically 5-20 ms; SpringBoard's main thread stays free meanwhile), drawn from its parts if it takes over 0.3 s
    NSString *src = nil;
    UIView *kept = DMMSWLeftPictureKept(gMSWOpen, &src);
    if (kept) { DMMSWMark([NSString stringWithFormat:@"left picture: %@", src]); DMMSWSwitchGo(to, why, v, done, NO, t0, kept); return; }
    // (the view open and no picture of the desktop under it kept: a window was dragged away in the view, and the view's opening picture showed it
    //  still. On iPadOS 15 a picture of the screen taken now has the view itself in it -- our window is drawn through SBRootSceneWindow, which every
    //  picture of the screen draws (found with K-1, M1 8 Oct): it became that desktop's thumbnail and its windows' pictures. So the left desktop is
    //  drawn from its parts (DMMSWLeftFromParts): its full-screen app's own picture, asked without waiting -- the slide comes up when it is in, at
    //  most 0.3 s --, its wallpaper, the shared windows live, its windows' parts of the opening picture. 16 and 17 take UIKit's picture of the
    //  screen without the view as before (DMMSWLeftPictureNow) until it is read there.)
    if (gMSWOpen && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion == 15 && !DMTestFlag("/tmp/msw-nopartsleft")) {
        NSString *whyCopy = [why copy];
        __block BOOL went = NO;
        SBApplication *front = DMFrontApp();
        NSString *fb = front && DMFullScreenAppInFront() ? [front bundleIdentifier] : nil;
        if (fb && [[gMSWFullScreen allValues] containsObject:fb]) fb = nil;   // (dragged to another desktop in the view: it goes Home when it lands)
        UIView *fsv = fb ? DMMSWFullScreenView(fb, NO) : nil;
        if (fsv) fsv = DMMSWFullScreenWithBar(fsv);   // (with the menu bar SpringBoard draws beside the app's scene)
        void (^go)(UIView *, NSString *) = ^(UIView *fsPic, NSString *how) {
            if (went) return;
            went = YES;
            DMMSWMark([NSString stringWithFormat:@"left picture: drawn from its parts (the view is open; %@)", how]);
            DMMSWSwitchGo(to, whyCopy, v, done, NO, t0, DMMSWLeftFromParts(fsPic, fsPic ? fsv : nil));
        };
        if (fsv && DMMSWPictureAsync(fsv, ^(UIView *pic, double ms) { go(pic, pic ? [NSString stringWithFormat:@"the full-screen app's picture in %.1f ms", ms] : @"the full-screen app's picture not drawn"); })) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ go(nil, @"the full-screen app's picture not in within 0.3 s"); });
            return;
        }
        go(nil, fb ? @"no picture of its full-screen app could be asked" : @"no full-screen app");
        return;
    }
    if (DMMSWAsyncScreenOn() && DMMSWAsyncPicturesOK()) {
        __block BOOL went = NO;
        NSString *whyCopy = [why copy];
        void (^go)(UIView *, NSString *) = ^(UIView *pic, NSString *how) {
            if (went) return;
            went = YES;
            if (!pic) pic = DMMSWDeskPicture(gMSWCur, [UIScreen mainScreen].bounds);   // (its wallpaper and what every desktop shows: drawn from its parts)
            DMMSWMark([NSString stringWithFormat:@"left picture: %@", how]);
            DMMSWSwitchGo(to, whyCopy, v, done, NO, t0, pic);
        };
        BOOL asked = DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], ^(UIView *pic, double ms) {
            go(pic, pic ? [NSString stringWithFormat:@"now, asked without waiting (%.1f ms)", ms] : @"not drawn: drawn from its parts");
        });
        if (asked) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (!went) DMLog(@"[macswitcher] the screen's picture did not come within 0.3 s: the left desktop slides drawn from its parts"); go(nil, @"none within 0.3 s: drawn from its parts"); });
            return;
        }
    }
    UIView *now = DMMSWLeftPictureNow(gMSWOpen, &src);
    DMMSWMark([NSString stringWithFormat:@"left picture: %@", src]);
    DMMSWSwitchGo(to, why, v, done, NO, t0, now);
}
// ---- the running switch (Aerial, Zetsu, MilkyWay4 / no engine): where it started and where it goes now ----
// A side swipe or a Control-arrow made while it runs gives it another aim at once (DMMSWSwRedirect): as on a Mac the slide goes on from where it
// is, at the speed it has, to the next desktop that way -- or back --, and the windows change under it for that aim: once, straight from the
// desktop on screen, when the change had not happened yet; else again, from the desktop it had changed to. An aim's change, landing and reveal
// belong to it (gMSWSwGen): a redirect leaves those of the aim before doing nothing.
// The strip's pictures are kept by slot -- k screens from the left desktop's -- with the desktop place each shows (gMSWSlPlaces): a switch from
// the strip to a desktop further away slides one screen, so a redirect is taken only where the next desktop's slot is free or holds it already;
// else (and for a switch with its own follow-up: a launch, a remove) the desktop comes right after, as before. Stage Manager's switch is re-aimed
// the same way by MacSwitcherSM.h (DMMSWSMRedirect).
static NSUInteger gMSWSwFrom = 0, gMSWSwTo = 0;   // the desktop places it started from (slot 0) and goes to now
static NSInteger gMSWSwToSlot = 0;                // the slot of the one it goes to
static NSInteger gMSWSwFromId = 0;
static UIView *gMSWSwOld;                         // the left desktop's picture (its thumbnail at the end; nil: none -- it was not left)
static NSUInteger gMSWSwGen = 0;                  // the aim
static BOOL gMSWSwLanded = NO, gMSWSwRevealing = NO, gMSWSwRedirectable = NO, gMSWSwChanged = NO;
static NSInteger gMSWSwQueued = 0;                // (Reduce Motion: sides asked for while a cross-fade runs -- each next fade starts when one ends)
static NSString *gMSWSwWhy;
static CFTimeInterval gMSWSwT0 = 0;
static BOOL gMSWSwFromGesture = NO;
static void (^gMSWSwDone)(void);
static NSUInteger gMSWSwRedirects = 0;
static CFTimeInterval gMSWSwViewGoneAt = 0;       // (when the Mac Switcher's view, fading over the slide, is gone: no windows change before, any aim)
static void DMMSWSwChange(NSUInteger gen, CFTimeInterval since);
static void DMMSWSwWait(NSUInteger gen, NSString *fs, NSString *quiet, BOOL retry, NSString *head, CFTimeInterval t3);
static void DMMSWSwEnd(void);
static BOOL DMMSWSwRedirect(NSInteger side, CGFloat v, NSString *why);
// The picture of the desktop at `place`, put at slot k if that slot is empty (a redirect's next desktop). nil: none.
static UIView *DMMSWSlEnsurePic(NSInteger k, NSUInteger place) {
    UIView *have = DMMSWSlPicAt(k);
    if (have || !gMSWSlStrip || place >= gMSWDesks.count) return have;
    UIView *pic = DMMSWDeskPicture(place, [UIScreen mainScreen].bounds);
    if (!pic) return nil;
    if (k == -1 || k == 1) gMSWSlSide[k > 0 ? 1 : 0] = pic;
    else { if (!gMSWSlMore) gMSWSlMore = [NSMutableDictionary dictionary]; gMSWSlMore[@(k)] = pic; }
    DMMSWSlPut(pic, CGRectOffset(gMSWSlRoot.bounds, k * gMSWSlW, 0));
    DMMSWSlShared(pic);
    if (!gMSWSlPlaces) gMSWSlPlaces = [NSMutableDictionary dictionary];
    gMSWSlPlaces[@(k)] = @(place);
    return pic;
}
static void DMMSWSlSetPlace(NSInteger k, NSUInteger place) { if (!gMSWSlPlaces) gMSWSlPlaces = [NSMutableDictionary dictionary]; gMSWSlPlaces[@(k)] = @(place); }
// The picture on the strip of the desktop at `place` (the left desktop's own: the switch's start picture), or nil.
static UIView *DMMSWSlPicOfPlace(NSUInteger place) {
    if (place == gMSWSwFrom && gMSWSwOld) return gMSWSwOld;
    for (NSNumber *k in gMSWSlPlaces) if (gMSWSlPlaces[k].unsignedIntegerValue == place) return DMMSWSlPicAt(k.integerValue);
    return nil;
}
// The slide on to the aim (gMSWSwToSlot / gMSWSwTo) at speed v, its landing, and when its windows change: once the slide is in its slow tail
// (measured on the M1, the main thread's commit of the change cost the render server a frame, and a frame missed at the start of the slide is a
// ~70 pt jump, in the tail a few points); never before the Mac Switcher's view has faded, as its thumbnails show the windows live. A full-screen
// app that comes with the desktop is asked for at once -- it is drawn by its app, which needs the time --; one that only goes Home is a change
// like the windows' (without animation: one quiet transition, F8). Without the quiet transitions both start at once, as before (the animated
// Home press and launch take ~0.5 s of their own). Nothing to change (back where it is): only the wait for the landing.
static void DMMSWSwAim(CGFloat v, BOOL wasOpen) {
    NSUInteger gen = gMSWSwGen;
    DMMSWSlFinishTo(gMSWSwToSlot, v, ^{
        if (gen != gMSWSwGen) return;
        gMSWSwLanded = YES;
        if (gMSWSwQueued) { NSInteger s = gMSWSwQueued > 0 ? 1 : -1; gMSWSwQueued -= s; DMMSWSwRedirect(s, 0, @"asked during the cross-fade"); }
    });
    double delay = 0;
    if (gMSWCur != gMSWSwTo) {
        NSInteger toId = gMSWDesks[gMSWSwTo].integerValue;
        BOOL comes = gMSWFullScreen[[@(toId) stringValue]] != nil, goes = DMFrontApp() && DMFullScreenAppInFront();
        double tail = MAX(0.0, gMSWSlQuietAt - CACurrentMediaTime());
        delay = DMMSWQuietOn() ? (comes ? 0 : tail) : ((comes || goes) ? 0 : tail);
#if DEBUG
        if (DMTestFlag("/tmp/msw-change-early")) delay = 0;                     // (debug comparisons: every change a frame after the start,
        if (DMTestFlag("/tmp/msw-change-tail") && (comes || goes)) delay = tail; //  or a full-screen app's in the slow tail too)
#endif
    }
    if (wasOpen) gMSWSwViewGoneAt = CACurrentMediaTime() + kMSWViewFade;
    delay = MAX(delay, MAX(1.0 / 60.0, gMSWSwViewGoneAt - CACurrentMediaTime()));   // (a redirect right after a tap in the strip waits for the view too)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMSWSwChange(gen, CACurrentMediaTime()); });
}
// The switch itself, the left desktop's picture in hand (old; from the gesture: the slide that follows the fingers is up already).
static void DMMSWSwitchGo(NSUInteger to, NSString *why, CGFloat v, void (^done)(void), BOOL fromGesture, CFTimeInterval t0, UIView *old) {
    if (to >= gMSWDesks.count || to == gMSWCur) {   // (cannot happen while gMSWSwitching holds the desktops; kept safe)
        DMLog([NSString stringWithFormat:@"[macswitcher] switch to %lu (%@) dropped: that desktop is not there now", (unsigned long)to, why]);
        DMMSWSlDrop(); gMSWSwitching = NO; if (gMSWTrack == 3) gMSWTrack = 0;
        if (done) done();
        return;
    }
    NSUInteger from = gMSWCur;
    BOOL wasOpen = gMSWOpen;
    if (!fromGesture) {
        UIView *in = DMMSWDeskPicture(to, [UIScreen mainScreen].bounds);
        if (wasOpen) DMMSWCloseUnderSlide();
        if (!DMMSWSlBegin(old, to < from ? in : nil, to > from ? in : nil)) DMLog(@"[macswitcher] the slide could not come up: the switch goes on without it");
        DMMSWSlSetPlace(0, from); if (in) DMMSWSlSetPlace(to > from ? 1 : -1, to);
    }
    gMSWSwFrom = from; gMSWSwTo = to; gMSWSwToSlot = to > from ? 1 : -1; gMSWSwFromId = DMMSWCurId(); gMSWSwOld = old; gMSWSwGen++;
    gMSWSwLanded = gMSWSwRevealing = gMSWSwChanged = NO; gMSWSwRedirectable = done == nil; gMSWSwDone = done; gMSWSwWhy = why; gMSWSwT0 = t0;
    gMSWSwFromGesture = fromGesture; gMSWSwRedirects = 0; gMSWSwQueued = 0;
    DMMSWMark([NSString stringWithFormat:@"slide set up (%.1f ms after the switch)", (CACurrentMediaTime() - t0) * 1000]);
    DMMSWSwAim(v, wasOpen);
}
// The followed side swipe went back: the slide springs back to where it began -- an aim of its own (a swipe or a Control-arrow on the way sends it
// on, as on a Mac) --, and goes once SpringBoard's own "stay" has settled under it.
static void DMMSWSwBack(CGFloat v) {
    gMSWSwitching = YES;
    gMSWSwFrom = gMSWSwTo = gMSWCur; gMSWSwToSlot = 0; gMSWSwFromId = DMMSWCurId(); gMSWSwOld = gMSWSlOld; gMSWSwGen++;
    gMSWSwLanded = gMSWSwRevealing = gMSWSwChanged = NO; gMSWSwRedirectable = YES; gMSWSwDone = nil; gMSWSwWhy = @"side swipe"; gMSWSwT0 = CACurrentMediaTime();
    gMSWSwFromGesture = YES; gMSWSwRedirects = 0; gMSWSwQueued = 0;
    DMMSWSwAim(v, NO);
}
// The aim's windows change (none when it is back where it is), then the wait for the landing and the live screen drawn still, then the reveal.
static void DMMSWSwChange(NSUInteger gen, CFTimeInterval since) {
    if (gen != gMSWSwGen || !gMSWSwitching) return;
    // (the change of a redirected switch whose change before asked for a workspace transition -- a full-screen app sent Home or opened -- waits
    //  while SpringBoard still runs one, at most 0.4 s: SpringBoard runs one transition after another; a gesture's own end needs no wait)
    if (gMSWCur != gMSWSwTo && gMSWSwChanged && gMSWChangeAskedWS && !DMMSWSpringBoardIdle() && CACurrentMediaTime() - since < 0.4) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 120)), dispatch_get_main_queue(), ^{ DMMSWSwChange(gen, since); });
        return;
    }
    NSUInteger at = gMSWCur, to = gMSWSwTo;
    NSString *fs = nil;
    CFTimeInterval t2 = CACurrentMediaTime(), t3 = t2;
    if (at != to) {
        DMMSWSpanBegin();   // (debug, /tmp/msw-span: the main thread from here to 120 ms after the windows change)
        UIView *leftPic = DMMSWSlPicOfPlace(at);   // (one drawn from its parts: its windows' pictures come out of the view's opening picture, gMSWCutShot)
        if ([objc_getAssociatedObject(leftPic, kMSWNotKeptKey) boolValue] && gMSWCutShot && gMSWCutShotId == gMSWDesks[at].integerValue) leftPic = gMSWCutShot;
        DMMSWCutOutsFrom(leftPic, gMSWDesks[at].integerValue);   // (the leaving windows' pictures: cut out of their desktop's picture)
        gMSWSwInChange = YES;
        fs = DMMSWChangeDesktop(at, to);
        gMSWSwInChange = NO; gMSWSwChanged = YES;
        gMSWFreshPics = nil;
        t3 = CACurrentMediaTime();
        DMMSWMark([NSString stringWithFormat:@"windows changed (%.1f ms)", (t3 - t2) * 1000]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{ DMMSWMark(@"after the change's commit"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{ DMMSWSpanEnd(@"the windows change and 120 ms after it"); });
    } else fs = DMFullScreenAppInFront() ? [DMFrontApp() bundleIdentifier] : nil;   // (back where it is: what is in front stays)
    NSString *head;
    if (gMSWSwFrom == to) head = [NSString stringWithFormat:@"[macswitcher] %@ back to %@ (%@%@)", gMSWSwWhy, DMMSWDeskName(to), gMSWSwRedirects ? [NSString stringWithFormat:@"%lu redirect(s), ", (unsigned long)gMSWSwRedirects] : @"", at != to ? @"windows changed back" : @"nothing changed"];
    else head = [NSString stringWithFormat:@"[macswitcher] %@ -> %@ (%@%@): %@, windows %.1f ms (%.0f ms after the start)", DMMSWDeskName(gMSWSwFrom), DMMSWDeskName(to), gMSWSwWhy,
        gMSWSwRedirects ? [NSString stringWithFormat:@", %lu redirect(s)", (unsigned long)gMSWSwRedirects] : @"", gMSWSwFromGesture ? @"slide from the fingers" : @"pictures + slide", (t3 - t2) * 1000, (t2 - gMSWSwT0) * 1000];
    DMMSWSwWait(gen, fs, at != to ? gMSWQuietAsked : nil, NO, head, t3);
}
// The wait for the landing and the live screen drawn still, then the reveal. A transition asked for without animation (quiet: the app it opened, @""
// for the Home Screen) that has not changed the front app by then gets the animated way, and one more wait.
static void DMMSWSwWait(NSUInteger gen, NSString *fs, NSString *quiet, BOOL retry, NSString *head, CFTimeInterval t3) {
    DMMSWWhenDrawn(fs, ^BOOL{ return gMSWSwLanded || !gMSWSlRoot; }, ^BOOL{ return gen != gMSWSwGen; }, ^(NSString *how) {
        BOOL frontOK = fs ? ([[DMFrontApp() bundleIdentifier] isEqualToString:fs] && DMFullScreenAppInFront()) : !DMFullScreenAppInFront();
        if (!frontOK && quiet && !retry && gMSWSlRoot) {
            DMLog([NSString stringWithFormat:@"[macswitcher] the transition without animation has not changed the front app (%@ in front): %@ the animated way", [DMFrontApp() bundleIdentifier] ?: @"none", fs ? [NSString stringWithFormat:@"%@ opened", fs] : @"the Home Screen asked for"]);
            if (fs) DMOpenFullScreen(fs); else DMMinimize();
            DMMSWSwWait(gen, fs, quiet, YES, head, t3);
            return;
        }
        gMSWSwRevealing = YES;
        DMMSWSlReveal(kMSWRevealFade, ^{ DMMSWSwEnd(); });
        DMLog([NSString stringWithFormat:@"%@: %@ %.0f ms after the windows%@", head, how, (CACurrentMediaTime() - t3) * 1000, retry ? @" (after the animated way)" : @""]);
    });
}
// Pictures cost the render server's memory: on an iPad with less than 4 GB (the iPad 2, 2 GB: a whole-screen picture is ~12.6 MB of backboardd's)
// only the desktop left last keeps its pictures -- the screen's and its windows' --, as Stage Manager's desktops do there (MacSwitcherSM.h
// DMMSWSMTrimPictures); an older desktop is drawn from its parts (wallpaper, window places, app icons) in the strip and for the slide. Measured on the
// iPad 2 with Zetsu: the pictures of 2 desktops and 2 windows were ~49 MB of backboardd, every desktop kept its picture (7 Oct). 4 GB and more:
// every desktop keeps its picture, as before.
static void DMMSWTrimPictures(NSInteger keepId) {
    if (DMSMEngine() || [NSProcessInfo processInfo].physicalMemory >= 3.5e9) return;
    NSMutableArray<NSNumber *> *dropped = [NSMutableArray array];
    for (NSNumber *did in [gMSWShots allKeys]) if (did.integerValue != keepId) { [gMSWShots removeObjectForKey:did]; [gMSWShotSet removeObjectForKey:did]; [dropped addObject:did]; }
    NSUInteger wins = 0;
    for (NSString *b in [gMSWWinShots allKeys]) { NSNumber *d = gMSWWinDesk[b]; if (d && d.integerValue != keepId) { [gMSWWinShots removeObjectForKey:b]; wins++; } }
    if (dropped.count || wins) DMLog([NSString stringWithFormat:@"[macswitcher] pictures kept for the desktop left last (less than 4 GB); let go: desktop(s) %@, %lu window picture(s)", dropped.count ? [dropped componentsJoinedByString:@", "] : @"none", (unsigned long)wins]);
}
// The slide has faded to the live screen: the left desktop's picture is its thumbnail (when it was left), the desktop on screen is drawn live; then
// the switch's own follow-up and a side swipe that waited.
static void DMMSWSwEnd(void) {
    NSInteger fromId = gMSWSwFromId, toId = DMMSWCurId();
    UIView *old = gMSWSwOld;
    BOOL notKept = old && [objc_getAssociatedObject(old, kMSWNotKeptKey) boolValue];
    if (notKept && fromId != toId) [gMSWShots removeObjectForKey:@(fromId)];   // (it left drawn from its parts: so is its next visit)
    if (old && fromId != toId && !notKept) {   // (the left desktop's thumbnail, with the windows it showed)
        if (!gMSWShots) gMSWShots = [NSMutableDictionary dictionary];
        if (!gMSWShotSet) gMSWShotSet = [NSMutableDictionary dictionary];
        gMSWShots[@(fromId)] = old; gMSWShotSet[@(fromId)] = DMMSWWindowSet(fromId);
    }
    [gMSWShots removeObjectForKey:@(toId)];   // (the current one is drawn live)
    // (the windows of the desktop on screen keep no pictures -- a redirected switch kept those of a desktop shown under the slide for a moment, to be
    //  cut out again should it be left at once)
    for (NSString *b in [gMSWWinShots allKeys]) if (gMSWWinDesk[b].integerValue == toId) [gMSWWinShots removeObjectForKey:b];
    if (fromId != toId) DMMSWTrimPictures(fromId);
    if (fromId == toId) gMSWLiftPic = nil;
    gMSWSwOld = nil; gMSWSlPlaces = nil; DMMSWCutLetGo();
    gMSWSwitching = NO; gMSWSwRevealing = NO;
    if (gMSWTrack == 3) gMSWTrack = 0;
    DMMSWRecEndAfter(0.5);
    void (^done)(void) = gMSWSwDone; gMSWSwDone = nil;
    if (done) done();
    NSInteger pend = gMSWPendingSide; gMSWPendingSide = 0;   // (a side swipe that ended on the way and could not redirect: its desktop now)
    if (pend && (NSInteger)gMSWCur + pend >= 0 && (NSInteger)gMSWCur + pend < (NSInteger)gMSWDesks.count) {
        DMLog(@"[macswitcher] the side swipe made on the way: its desktop comes now");
        DMMSWSwitchRun((NSUInteger)((NSInteger)gMSWCur + pend), @"side swipe made on the way", 0, nil);
    }
}
// A side swipe or a Control-arrow while the switch runs: the slide goes on from where it is to the next desktop that way (or back), at once. NO:
// not here (Stage Manager, a switch with its own follow-up, a far switch with a desktop between, the reveal already fading) -- the caller then
// keeps it for right after (gMSWPendingSide).
static BOOL DMMSWSwRedirect(NSInteger side, CGFloat v, NSString *why) {
    if (DMSMEngine()) return DMMSWSMRedirect(side, v, why);   // (Stage Manager's switch has its own aim: MacSwitcherSM.h)
    if (!side || !gMSWSwitching || !gMSWSlRoot || !gMSWSwRedirectable || gMSWSwRevealing || gMSWTrack == 1 || gMSWTrack == 2) return NO;
    NSInteger to = (NSInteger)gMSWSwTo + side, k = gMSWSwToSlot + side;
    if (to < 0 || to >= (NSInteger)gMSWDesks.count) {
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ while sliding to %@: no desktop on that side, it slides on", why, DMMSWDeskName(gMSWSwTo)]);
        return YES;
    }
    NSNumber *there = gMSWSlPlaces[@(k)];
    if (there && there.integerValue != to) return NO;   // (that slot shows another desktop: a far switch from the strip)
    if (gMSWSlSpFade && !gMSWSwLanded) { gMSWSwQueued += side; DMLog([NSString stringWithFormat:@"[macswitcher] %@ during the cross-fade: the next one starts when it ends", why]); return YES; }
    if (!DMMSWSlEnsurePic(k, (NSUInteger)to)) return NO;
    // (the speed: the slide's own where it is -- no jump in its motion; moving the other way it turns back on the spring --, or the fingers' when
    //  they flicked that way faster)
    CGFloat now = DMMSWSlSpeedNow(), dir = side > 0 ? -1.0 : 1.0, vv = (v * dir > 0 && v * dir > now * dir) ? v : now;
    gMSWSwGen++; gMSWSwTo = (NSUInteger)to; gMSWSwToSlot = k; gMSWSwLanded = NO; gMSWSwRedirects++;
    DMMSWRecBegin([NSString stringWithFormat:@"redirect (%@)", why]);
    DMMSWMark([NSString stringWithFormat:@"redirect to %@ (slot %+ld, slide at %.0f pt, %.0f pt/s)", DMMSWDeskName((NSUInteger)to), (long)k, DMMSWSlOffsetNow(), vv]);
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ while the slide runs: on to %@ (the windows are on %@, the slide at %.0f pt, %.0f pt/s)", why, DMMSWDeskName((NSUInteger)to), DMMSWDeskName(gMSWCur), DMMSWSlOffsetNow(), vv]);
    DM_FEATURE_MARK("mac-switcher-redirect");
    gMSWSlMaxAway = 3000.0;   // (a slide sent back the other way turns on its spring, ~80 pt further at most, as a Mac's does -- no stop and jump)
    DMMSWSwAim(vv, NO);
    gMSWSlMaxAway = 900.0;
    return YES;
}
// A Control-arrow towards no desktop: the screen gives way a little and comes back, as a Mac's does (nothing with Reduce Motion, or while a slide
// or the view is up). The screen's picture is asked without waiting; the bump plays when it is in, on our layer window (a switch asked meanwhile
// takes the slide over).
static void DMMSWBump(NSInteger side) {
    if (!side || gMSWSwitching || gMSWSlRoot || gMSWOpen || MSBReduceMotion() || !DMMSWAsyncScreenOn()) return;
    DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], ^(UIView *pic, double ms) {
        if (!pic || gMSWSwitching || gMSWSlRoot || gMSWOpen || !DMMSWSlBegin(pic, nil, nil)) return;
        UIView *strip = gMSWSlStrip; NSUInteger gen = gMSWSlGen;
        CGFloat d = side > 0 ? -44.0 : 44.0;   // (the strip moves left for the desktop on the right that is not there)
        DMMSWSlSetOffset(0);
        [UIView animateWithDuration:0.11 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ strip.transform = CGAffineTransformMakeTranslation(d, 0); } completion:^(BOOL f) {
            if (gen != gMSWSlGen) return;
            [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0 options:0 animations:^{ strip.transform = CGAffineTransformIdentity; } completion:^(BOOL g) { if (gen == gMSWSlGen) DMMSWSlDrop(); }];
        }];
    });
}
// A side swipe or a Control-arrow: the desktop on that side -- at once from where the slide is when one runs (DMMSWSwRedirect), else a switch.
static void DMMSWSideRequest(NSInteger side, CGFloat v, NSString *why) {
    if (gMSWSwitching || gMSWSlRoot) {
        if (DMMSWSwRedirect(side, v, why)) return;
        gMSWPendingSide = side;
        DMLog([NSString stringWithFormat:@"[macswitcher] %@ while a desktop is still sliding in: its desktop comes next", why]);
        return;
    }
    NSInteger to = (NSInteger)gMSWCur + side;
    if (to >= 0 && to < (NSInteger)gMSWDesks.count) { DMMSWSwitchRun((NSUInteger)to, why, v, nil); return; }
    DMLog([NSString stringWithFormat:@"[macswitcher] %@: no desktop on that side", why]);
    if ([why hasPrefix:@"Control-"]) DMMSWBump(side);   // (a swipe's own rubber band shows it already)
}
// A new desktop at the end of the strip, not shown yet ("+" then goes there; a window dropped on "+" only goes there itself). The first one beyond
// Desktop 1 records the windows there are on Desktop 1. Its id, or 0 (the Mac Switcher is off, or already the most).
static NSInteger DMMSWMakeDesktop(void) {
    if (!DMMSWDesktopsHere() || gMSWDesks.count >= kMSWMaxDesks) return 0;
    NSInteger nid = 2;
    while ([gMSWDesks containsObject:@(nid)]) nid++;
    if (gMSWDesks.count == 1) { gMSWWinDesk = gMSWWinDesk ?: [NSMutableDictionary dictionary]; for (UIView *st in DMAerialStagesAll()) { NSString *b = DMStageBundle(st); if (b.length) gMSWWinDesk[b] = @1; } }
    if (gMSWDesks.count == 1 && DMSMEngine()) DMMSWSMRecordFirst();   // (Stage Manager: the engine's desktop stage, MacSwitcherSM.h)
    // (a new desktop starts with nothing of an earlier desktop that had its id: a removed one's screen size, picture, Fit group or full-screen app
    //  -- the size made the new desktop "turned while away" on its first visit, iPad 2 7 Oct; DMMSWRemoveDesktop clears them too, this covers the
    //  state saved by builds before that)
    NSString *nk = [@(nid) stringValue];
    [gMSWLeftSize removeObjectForKey:nk]; [gMSWFit removeObjectForKey:nk]; [gMSWFullScreen removeObjectForKey:nk]; [gMSWShots removeObjectForKey:@(nid)]; [gMSWShotSet removeObjectForKey:@(nid)];
    [gMSWDesks addObject:@(nid)];
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ made", DMMSWDeskName(gMSWDesks.count - 1)]);
    return nid;
}
static void DMMSWAddDesktop(void) {
    if (!DMMSWDesktopsHere()) { DMLog(@"[macswitcher] \"+\": the Mac Switcher is off"); return; }
    if (gMSWDesks.count >= kMSWMaxDesks) { DMLog(@"[macswitcher] \"+\": already the most desktops"); return; }
    if (!DMMSWMakeDesktop()) return;
    DMLog([NSString stringWithFormat:@"[macswitcher] \"+\": %@ made", DMMSWDeskName(gMSWDesks.count - 1)]);
    DMMSWSave();
    DMMSWSwitchTo(gMSWDesks.count - 1, @"+", nil);
}
static void DMMSWRebuildOpen(void);
static BOOL gMSWRemovingCurrent = NO;   // (the desktop being removed was the one on screen: its windows are shown on the neighbour it slid to)
static void DMMSWRemoveDesktop(NSUInteger i) {
    if (i == 0 || i >= gMSWDesks.count || gMSWSwitching) return;   // (Desktop 1 stays)
    if (i == gMSWCur) {   // (the desktop on screen: the neighbour slides in first, then it goes -- never again from the completion: a refused switch looped)
        DMMSWSwitchTo(i - 1, @"its desktop is removed", ^{
            if (gMSWCur == i || i >= gMSWDesks.count) { DMLog(@"[macswitcher] the desktop on screen was not removed: the slide to its neighbour did not happen"); return; }
            gMSWRemovingCurrent = YES; DMMSWRemoveDesktop(i); gMSWRemovingCurrent = NO;
        });
        return;
    }
    NSUInteger nb = i - 1;
    NSNumber *rid = gMSWDesks[i], *nid = gMSWDesks[nb];
    NSUInteger moved = 0;
    for (NSString *b in gMSWWinDesk.allKeys) if ([gMSWWinDesk[b] isEqual:rid]) { gMSWWinDesk[b] = nid; moved++; }
    for (DMNativeWindow *w in [gMSWAwayNatives arrayByAddingObjectsFromArray:gNativeWindows ?: @[]]) if ([objc_getAssociatedObject(w, kMSWNativeDeskKey) isEqual:rid]) { objc_setAssociatedObject(w, kMSWNativeDeskKey, nid, OBJC_ASSOCIATION_RETAIN_NONATOMIC); moved++; }
    NSString *fs = gMSWFullScreen[rid.stringValue];
    if (fs && !gMSWFullScreen[nid.stringValue]) gMSWFullScreen[nid.stringValue] = fs;
    [gMSWFullScreen removeObjectForKey:rid.stringValue];
    [gMSWFit removeObjectForKey:rid.stringValue];   // (its windows join the neighbour untiled)
    [gMSWLeftSize removeObjectForKey:rid.stringValue];   // (a later desktop with this id is not "turned while away")
    [gMSWShots removeObjectForKey:rid];
    [gMSWDesks removeObjectAtIndex:i];
    if (gMSWCur > i) gMSWCur--;
    DMLog([NSString stringWithFormat:@"[macswitcher] desktop %ld removed: %lu windows moved to %@", (long)rid.integerValue, (unsigned long)moved, DMMSWDeskName(nb)]);
    // (Stage Manager: shown together when the neighbour is on screen, MacSwitcherSM.h -- before the records go with the last but one desktop: the
    //  merge reads them, and found none, so removing Desktop 2 of two sent the iPad 2 to the Home Screen)
    if (DMSMEngine()) DMMSWSMMerged(nb);
    if (gMSWDesks.count == 1) { [gMSWWinDesk removeAllObjects]; [gMSWWinFrame removeAllObjects]; [gMSWFullScreen removeAllObjects]; [gMSWLeftSize removeAllObjects]; [gMSWShots removeAllObjects]; [gMSWFit removeAllObjects]; }   // (one desktop: no records needed)
    DMMSWApply();
    DMMSWSave();
    DMMSWRebuildOpen();
}
// The place of the desktop an app's window -- or its remembered full-screen app -- is on, when that is another desktop; NSNotFound otherwise.
static NSUInteger DMMSWElsewhereIndex(NSString *b) {
    if (!DMMSWMulti() || DMSMEngine() || gRestoringWindows || !b.length) return NSNotFound;
    NSNumber *d = nil;
    BOOL hasStage = NO;
    for (UIView *st in DMAerialStagesAll()) if ([DMStageBundle(st) isEqualToString:b]) { hasStage = YES; if ([objc_getAssociatedObject(st, kMSWAwayKey) boolValue]) d = gMSWWinDesk[b]; }
    if (!d) for (NSString *k in gMSWFullScreen) if ([gMSWFullScreen[k] isEqualToString:b]) d = @(k.integerValue);
    if (!d && !hasStage && gMSWWinDesk[b] && gMSWWinDesk[b].integerValue != DMMSWCurId()) d = gMSWWinDesk[b];   // (closed by iPadOS while away)
    NSUInteger i = d ? [gMSWDesks indexOfObject:d] : NSNotFound;
    return i == gMSWCur ? NSNotFound : i;
}
// (StatusBar.x, SBMainWorkspace's open requests: an app opened by Spotlight, a link, a notification or LaunchServices whose window is on another
//  desktop takes the window path, which brings its desktop; it was "left alone" and opened full screen on the current desktop, its window still
//  recorded on the other one -- found on the M1, 4 Oct)
static BOOL DMMSWWindowElsewhere(NSString *b) { return DMMSWElsewhereIndex(b) != NSNotFound; }
// Launching an app (StatusBar.x DMSurfaceWindowForApp): its window, or its full-screen app, on another desktop -> that desktop comes, as on a Mac.
static BOOL DMMSWLaunchSwitches(NSString *b) {
    if (!DMMSWMulti() || gRestoringWindows || gMSWSwitching || !b.length || DMSMEngine()) return NO;
    NSUInteger i = DMMSWElsewhereIndex(b);
    if (i == NSNotFound) return NO;
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ opened: it is on %@, which comes", b, DMMSWDeskName(i)]);
    NSString *bc = [b copy];
    // (its window comes to the front there, as the launch asked: Zetsu / MilkyWay4 by the launch's own window path -- DMRaiseStageForBundle is a tap's
    //  follow-up, which Zetsu does itself and MilkyWay4 has no Aerial raise for, as the Mac Switcher's pick found, F7)
    DMMSWSwitchTo(i, @"launch", ^{ if (DMActiveEngine() == DMEngineZetsu || DMActiveEngine() == DMEngineMilkyWay) DMSurfaceWindowForApp(bc); else DMRaiseStageForBundle(bc); });
    return YES;
}
// Settings off (or the self-check): everything on Desktop 1 again.
static void DMMSWCollapse(void) {
    if (!gMSWDesks) return;
    if (gMSWDesks.count > 1) DMLog(@"[macswitcher] one desktop again: every window on Desktop 1");
    gMSWDesks = [NSMutableArray arrayWithObject:@1]; gMSWCur = 0;
    [gMSWWinDesk removeAllObjects]; [gMSWWinFrame removeAllObjects]; [gMSWFullScreen removeAllObjects]; [gMSWShots removeAllObjects]; [gMSWFit removeAllObjects];
    DMMSWApply();
    DMMSWSave();
}

// A window without a picture, where it is (f): a dark card with its app's icon (nil: too small to show).
static UIView *DMMSWIconCard(NSString *bundle, CGRect f) {
    if (f.size.width < 40.0 || f.size.height < 40.0) return nil;
    UIView *card = [[UIView alloc] initWithFrame:f];
    card.userInteractionEnabled = NO;
    card.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.92];
    card.layer.cornerRadius = 10.0; card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor; card.layer.borderWidth = 1.0;
    UIImage *icon = DMAppIcon(bundle);
    if (icon) {
        CGFloat side = MIN(96.0, MIN(f.size.width, f.size.height) * 0.4);
        UIImageView *iv = [[UIImageView alloc] initWithImage:icon];
        iv.frame = CGRectMake((f.size.width - side) / 2.0, (f.size.height - side) / 2.0, side, side);
        [card addSubview:iv];
    }
    return card;
}
// An away desktop drawn from its parts, when its picture is stale (windows moved onto it by a remove, or one closed while away): the wallpaper
// and each of its windows' own pictures at their places, back to front. b: the screen in root coordinates.
static UIView *DMMSWComposedDesktop(NSInteger did, CGRect b) {
    if (DMSMEngine()) return DMMSWSMComposedDesktop(did, b);   // (Stage Manager: its window cards' pictures, MacSwitcherSM.h)
    DMMSWWallLazy();
    UIView *c = [[UIView alloc] initWithFrame:b];
    c.backgroundColor = [UIColor blackColor];
    c.clipsToBounds = YES;
    if (gMSWWallContents) {
        UIView *wv = [UIView new];
        wv.layer.contents = gMSWWallContents; wv.layer.contentsRect = gMSWWallContentsRect; wv.layer.contentsGravity = gMSWWallGravity ?: kCAGravityResize;
        wv.bounds = gMSWWallBounds; wv.center = gMSWWallCenter; wv.transform = gMSWWallTransform;
        [c addSubview:wv];
    }
    NSUInteger n = 0, icons = 0;
    for (UIView *st in DMAerialStagesAll()) {
        NSString *b2 = DMStageBundle(st);
        if (!b2.length || gMSWWinDesk[b2].integerValue != did || DMStageMinimized(st)) continue;
        UIView *pic = gMSWWinShots[b2];
        if (pic && !DMMSWPicTrueOn(pic, did)) pic = nil;   // (a window that covered part of it left that desktop: an icon card instead of its picture)
        CGRect f = gMSWWinFrame[b2] ? CGRectFromString(gMSWWinFrame[b2]) : st.frame;
        if (pic) {
            [pic removeFromSuperview];
            pic.transform = CGAffineTransformIdentity;
            pic.frame = f;
            pic.tag = 0x4D53;   // (a window's picture: over the shared windows' portals, DMMSWSlShared)
            [c addSubview:pic];
            n++;
            continue;
        }
        // (no picture of it yet -- hidden since a respring, not seen since, or let go under memory pressure: its place, a dark card with its app's
        //  icon, as the Stage Manager desktops draw it; a desktop that a window was dropped on showed that window alone)
        UIView *card = DMMSWIconCard(b2, f);
        if (!card) continue;
        card.tag = 0x4D53;
        [c addSubview:card];
        icons++;
    }
    objc_setAssociatedObject(c, kMSWDrawnKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (kept as its thumbnail: DMMSWDeskPicture asks for the shared windows at each slide)
    DMLog([NSString stringWithFormat:@"[macswitcher] desktop %ld's thumbnail drawn from its wallpaper, %lu window pictures and %lu app icons (its picture was out of date)", (long)did, (unsigned long)n, (unsigned long)icons]);
    return c;
}
// The coming desktop's picture for the slide: as it was left (its thumbnail), while its windows are the same and the screen has its shape. Else it
// is drawn from its parts: its wallpaper, what every desktop shows alike -- the Home Screen, the Dock, the menu bar --, live (portals of their
// windows, made once the slide is up: DMMSWSlShared), and its windows' own pictures where they were (when it was left in this shape). Stage
// Manager: its own pictures (MacSwitcherSM.h); none yet: the wallpaper.
static UIView *DMMSWDeskPicture(NSUInteger i, CGRect b) {
    if (i >= gMSWDesks.count) return nil;
    NSInteger did = gMSWDesks[i].integerValue;
    UIView *pic = DMSMEngine() ? DMMSWSMDeskPicture(did, b) : nil;
    NSString *left = gMSWLeftSize[[@(did) stringValue]];
    BOOL sameShape = !left || CGSizeEqualToSize(CGSizeFromString(left), b.size);
    if (!DMSMEngine()) {
        UIView *shot = gMSWShots[@(did)];
        if (shot && sameShape && CGSizeEqualToSize(shot.bounds.size, b.size) && [gMSWShotSet[@(did)] isEqualToArray:DMMSWWindowSet(did)]) pic = shot;
        // (kept but drawn from its parts -- a window dropped on it in the view, moved onto it by a remove, closed while it was away
        //  (DMMSWComposedDesktop) --: the Home Screen, the Dock and the menu bar come live on every slide, under its windows, as on a desktop drawn
        //  from its parts here below; they were missing in the slide and popped in at the reveal, 1.4.2 -- the same as Stage Manager's, item 2)
        if (pic && [objc_getAssociatedObject(pic, kMSWDrawnKey) boolValue] && !DMTestFlag("/tmp/msw-drawnshared-old")) objc_setAssociatedObject(pic, kMSWSharedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (pic) return pic;
    DMMSWWallLazy();
    UIView *c = [[UIView alloc] initWithFrame:b];
    c.backgroundColor = [UIColor blackColor]; c.clipsToBounds = YES; c.userInteractionEnabled = NO;
    if (gMSWWallContents) {
        UIView *wv = [UIView new];
        wv.userInteractionEnabled = NO;
        wv.layer.contents = gMSWWallContents; wv.layer.contentsRect = gMSWWallContentsRect; wv.layer.contentsGravity = gMSWWallGravity ?: kCAGravityResize;
        wv.bounds = gMSWWallBounds; wv.center = gMSWWallCenter; wv.transform = gMSWWallTransform;
        [c addSubview:wv];
    }
    objc_setAssociatedObject(c, kMSWSharedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSUInteger n = 0, cards = 0;
    if (sameShape && !DMSMEngine())
        for (UIView *st in DMAerialStagesAll()) {
            NSString *b2 = DMStageBundle(st);
            if (!b2.length || gMSWWinDesk[b2].integerValue != did || DMStageMinimized(st)) continue;
            UIView *wp = gMSWWinShots[b2];
            if (wp && !DMMSWPicTrueOn(wp, did)) wp = nil;
            CGRect f = gMSWWinFrame[b2] ? CGRectFromString(gMSWWinFrame[b2]) : st.frame;
            UIView *holder = wp ? [[UIView alloc] initWithFrame:f] : DMMSWIconCard(b2, f);   // (no picture of it -- since a respring, or let go
            if (!holder) continue;                                                          //  under memory pressure --: its app icon card, as the strip)
            holder.tag = 0x4D53;   // (a window's picture: over the shared windows' portals)
            if (wp) { [wp removeFromSuperview]; wp.transform = CGAffineTransformIdentity; wp.frame = holder.bounds; [holder addSubview:wp]; n++; } else cards++;
            [c addSubview:holder];
        }
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ for the slide: drawn from its parts (%@wallpaper, %lu window pictures, %lu app icon cards%@)", DMMSWDeskName(i), gMSWWallContents ? @"" : @"no ", (unsigned long)n, (unsigned long)cards, sameShape ? @"" : @"; it was left in the other orientation"]);
    return c;
}
// The desktop on the screen drawn from its parts, for a switch from the open view when no picture of it is kept (DMMSWSwitchRun: a window was
// dragged away in the view, and no picture of the screen taken now can leave the view out on iPadOS 15). As the coming desktop's parts
// (DMMSWDeskPicture): its full-screen app's picture (fsPic, asked just before), its wallpaper, what every desktop shows alike live (DMMSWSlShared),
// and its windows where they are, back to front -- each one's part of the view's opening picture (gMSWCutShot); one that a window dragged away
// since covered in part gets its app icon card instead (that part would show the window that went). Native windows in their layer's place: just
// above the engine's windows while one is active, else behind them. Never kept as the desktop's thumbnail (kMSWNotKeptKey, DMMSWSwEnd): its next
// visit is drawn from its parts too.
static UIView *DMMSWLeftFromParts(UIView *fsPic, UIView *fsSrc) {
    CGRect b = [UIScreen mainScreen].bounds;
    UIScreen *scr = [UIScreen mainScreen];
    NSInteger did = DMMSWCurId();
    DMMSWWallLazy();
    UIView *c = [[UIView alloc] initWithFrame:b];
    c.backgroundColor = [UIColor blackColor]; c.clipsToBounds = YES; c.userInteractionEnabled = NO;
    if (gMSWWallContents) {
        UIView *wv = [UIView new];
        wv.userInteractionEnabled = NO;
        wv.layer.contents = gMSWWallContents; wv.layer.contentsRect = gMSWWallContentsRect; wv.layer.contentsGravity = gMSWWallGravity ?: kCAGravityResize;
        wv.bounds = gMSWWallBounds; wv.center = gMSWWallCenter; wv.transform = gMSWWallTransform;
        [c addSubview:wv];
    }
    objc_setAssociatedObject(c, kMSWSharedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(c, kMSWNotKeptKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fsPic && fsSrc) {   // (where its scene view is on the screen, turned as it is; over the Home Screen: the shared windows go under it)
        CGRect fb = fsSrc.bounds;
        CGPoint o = [fsSrc convertPoint:fb.origin toCoordinateSpace:scr.coordinateSpace];
        CGPoint x = [fsSrc convertPoint:CGPointMake(fb.origin.x + 100.0, fb.origin.y) toCoordinateSpace:scr.coordinateSpace];
        CGPoint m = [fsSrc convertPoint:CGPointMake(CGRectGetMidX(fb), CGRectGetMidY(fb)) toCoordinateSpace:scr.coordinateSpace];
        CGFloat k = hypot(x.x - o.x, x.y - o.y) / 100.0;
        if (k > 0.01) {
            fsPic.transform = CGAffineTransformIdentity;
            fsPic.bounds = CGRectMake(0, 0, fb.size.width, fb.size.height);
            fsPic.center = m;
            fsPic.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(atan2(x.y - o.y, x.x - o.x)), k, k);
            fsPic.tag = DMTestFlag("/tmp/msw-fsportals-old") ? 0x4D53 : 0x4D54;   // (the full-screen app's picture: the shared windows above apps go over it, DMMSWSlShared)
            [c addSubview:fsPic];
        } else fsPic = nil;
    }
    UIView *shot = gMSWCutShot && gMSWCutShotId == did && CGSizeEqualToSize(gMSWCutShot.bounds.size, b.size) ? gMSWCutShot : nil;
    __block NSUInteger n = 0, cards = 0, none = 0;
    void (^place)(UIView *, NSString *, NSString *) = ^(UIView *w, NSString *key, NSString *bundle) {
        CGRect r = [w convertRect:w.bounds toCoordinateSpace:scr.coordinateSpace];
        UIView *cut = shot && DMMSWCutTrue(key, did) ? DMMSWCutOut(shot, r) : nil;   // (the window's whole size, its part on the screen in it)
        if (cut) cut.frame = r;
        UIView *pic = cut ?: (bundle ? DMMSWIconCard(bundle, r) : nil);
        if (!pic) { none++; return; }
        pic.tag = 0x4D53; pic.userInteractionEnabled = NO;   // (a window's picture: over the shared windows' portals)
        if (cut) n++; else cards++;
        [c addSubview:pic];
    };
    NSMutableArray<UIView *> *natives = [NSMutableArray array];   // (this desktop's, on the screen, back to front)
    for (DMNativeWindow *w in gNativeWindows) {
        NSNumber *d = objc_getAssociatedObject(w, kMSWNativeDeskKey);
        if (!w.hidden && w.superview && (!d || d.integerValue == did)) [natives addObject:w];
    }
    BOOL nativesFront = gNativeLayer && gNativeLayer.windowLevel > kNWBackLevel + 0.01;
    if (!nativesFront) for (UIView *w in natives) place(w, DMMSWNativeCutKey(w), nil);
    for (UIView *st in DMAerialStagesAll()) {
        NSString *b2 = DMStageBundle(st);
        if (!b2.length || st.hidden || st.alpha < 0.05 || DMStageMinimized(st) || [objc_getAssociatedObject(st, kMSWAwayKey) boolValue]) continue;
        NSNumber *d = gMSWWinDesk[b2];
        if (d && d.integerValue != did) continue;   // (a window dragged to another desktop that has not landed yet: not this desktop's)
        place(st, b2, b2);
    }
    if (nativesFront) for (UIView *w in natives) place(w, DMMSWNativeCutKey(w), nil);
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ leaves drawn from its parts (the view is open, its opening picture shows a window dragged away): %@%@wallpaper, %lu window pictures from the opening picture, %lu app icon cards%@",
        DMMSWDeskName(gMSWCur), fsPic ? @"its full-screen app's picture, " : @"", gMSWWallContents ? @"" : @"no ", (unsigned long)n, (unsigned long)cards, none ? [NSString stringWithFormat:@", %lu native window(s) left out (a dragged one covered them)", (unsigned long)none] : (shot ? @"" : @" (no opening picture)")]);
    return c;
}
// A picture drawn from parts gets the shared windows live, under its window pictures -- once the slide's root is on screen (portals are placed
// through the screen's coordinates).
// A full-screen app's picture in it (tag 0x4D54, DMMSWLeftFromParts): the shared windows that are above apps -- the menu bar, the Dock -- go over
// that picture (under the windows' pictures), the ones behind apps (the Home Screen) under it. All went under it: the leaving picture of a desktop
// with a full-screen app lost its menu bar (b6ba9a0's branch; 1.4.1 logic test L-2).
static void DMMSWSlShared(UIView *pic) {
    if (![objc_getAssociatedObject(pic, kMSWSharedKey) boolValue] || !gMSWSlRoot) return;
    objc_setAssociatedObject(pic, kMSWSharedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIView *v in [pic.subviews copy]) if (v.tag == 0x4D55) [v removeFromSuperview];   // (a kept picture drawn from parts: the last slide's holders, their portals let go)
    UIView *firstWin = nil, *fsApp = nil;
    for (UIView *v in pic.subviews) { if (v.tag == 0x4D53 && !firstWin) firstWin = v; if (v.tag == 0x4D54 && !fsApp) fsApp = v; }
    CGRect b = gMSWSlRoot.bounds;
    for (UIWindow *w in DMMSWScreenWindows()) {
        NSString *cn = NSStringFromClass([w class]);
        if (DMMSWOurOrEngineWindow(w) || [cn isEqualToString:@"SBMainSwitcherWindow"] || ([cn hasPrefix:@"_SBWallpaper"] && gMSWWallContents)) continue;
        UIView *holder = [[UIView alloc] initWithFrame:b];
        holder.userInteractionEnabled = NO;
        holder.tag = 0x4D55;   // (a shared window's place in the picture)
        CGRect r = CGRectNull;
        // (SpringBoard's own status bar while a full-screen app is in front: transparent (alpha 0) -- the menu bar on the screen is the one drawn in
        //  that app's switcher page --, so a desktop drawn from its parts had no menu bar in the slide and it popped in at the reveal (M1 9 Oct, an
        //  arriving desktop drawn from its parts after Tips full screen). Such a picture gets the bar itself, whose portal does not take its alpha.
        //  Not a picture with a full-screen app's own picture in it: that one carries the app's menu bar, DMMSWFullScreenWithBar. Debug
        //  /tmp/msw-sharedbar-old = before.)
        UIView *src = w, *bar = nil;
        if (!fsApp && DMSBIsBarWindowName(cn) && !DMTestFlag("/tmp/msw-sharedbar-old")) {
            Class barClass = NSClassFromString(DMSBName("UIStatusBar_Modern"));
            for (UIView *v in w.subviews) if (barClass && [v isKindOfClass:barClass]) { bar = v; break; }
            if (bar && !bar.hidden && bar.alpha < 0.01) src = bar; else bar = nil;
        }
        UIView *p = DMMSWPortalInPlace(src, gMSWSlRoot, holder, &r);
        if (!p) continue;
        [gMSWPortals removeObjectIdenticalTo:p];
        if (bar ? !CGRectContainsRect(CGRectInset(b, -0.5, -0.5), r) : !CGRectEqualToRect(CGRectIntegral(CGRectInset(r, 0.5, 0.5)), CGRectIntegral(CGRectInset(b, 0.5, 0.5)))) {
#if DEBUG
            if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[mswshared] %@ (level %.0f) left out: it lands at %@", cn, w.windowLevel, NSStringFromCGRect(r)]);
#endif
            DMMSWPortalLetGo(p); continue;
        }
        if (!gMSWSlPortals) gMSWSlPortals = [NSMutableArray array];
        [gMSWSlPortals addObject:p];
        BOOL underApp = fsApp && w.windowLevel <= UIWindowLevelNormal + 0.5;
        if (underApp) [pic insertSubview:holder belowSubview:fsApp];   // (behind apps: under the full-screen app)
        else if (firstWin) [pic insertSubview:holder belowSubview:firstWin]; else [pic addSubview:holder];
#if DEBUG
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[mswshared] %@ (level %.0f)%@: %@", cn, w.windowLevel, bar ? @" -- its status bar, transparent on the screen (a full-screen app in front), opaque here" : @"",
            underApp ? @"under the full-screen app's picture" : (fsApp ? @"over the full-screen app's picture" : (firstWin ? @"under the window pictures" : @"on top"))]);
#endif
    }
}

// The strip's places for `count` desktops (and "+" while there is room for another and withPlus): each desktop's tile (appended to rects), "+"
// (CGRectNull: none) and, returned, the strip's height. b: the root's bounds.
static CGFloat DMMSWStripLayout(CGRect b, NSUInteger count, BOOL withPlus, NSMutableArray<NSValue *> *rects, CGRect *plus) {
    CGFloat stripH = MIN(150.0, MAX(96.0, b.size.height * 0.15)), labelH = 18.0;
    CGFloat thumbH = stripH - labelH - 22.0, thumbW = thumbH * b.size.width / b.size.height;
    BOOL hasPlus = withPlus && count < kMSWMaxDesks;
    NSUInteger n = MAX((NSUInteger)1, count), tiles = n + (hasPlus ? 1 : 0);
    CGFloat gap = 30.0;
    if (tiles * thumbW + (tiles - 1) * gap > b.size.width - 40.0) { CGFloat k = (b.size.width - 40.0 - (tiles - 1) * gap) / (tiles * thumbW); thumbW *= k; thumbH *= k; }
    CGFloat x0 = (b.size.width - (tiles * thumbW + (tiles - 1) * gap)) / 2.0;
    for (NSUInteger i = 0; i < n; i++) [rects addObject:[NSValue valueWithCGRect:CGRectIntegral(CGRectMake(x0 + i * (thumbW + gap), 12.0, thumbW, thumbH))]];
    if (plus) *plus = hasPlus ? CGRectIntegral(CGRectMake(x0 + n * (thumbW + gap), 12.0, thumbW, thumbH)) : CGRectNull;
    return stripH;
}
// The strip: the desktops (the current one live, the others as they were left) and "+". Made for root (on screen; b its bounds) and returned
// (the caller adds it); its places and views are kept in gMSWDeskRects / gMSWDeskClips / gMSWDeskLabels / gMSWXViews / gMSWPlusRect.
static UIView *DMMSWBuildStrip(UIView *root, CGRect b) {
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    CGRect plusRect = CGRectNull;
    // (desktops with every engine: DMMSWDesktopsHere is NO only while the Mac Switcher is off -- the desktop on screen alone then, and no "+")
    BOOL desks = DMMSWDesktopsHere();
    CGFloat stripH = DMMSWStripLayout(b, desks ? gMSWDesks.count : 1, desks, rects, &plusRect), labelH = 18.0;
    UIView *strip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, stripH)];
    strip.userInteractionEnabled = NO;
    NSUInteger n = rects.count;
    gMSWDeskRects = [NSMutableArray array]; gMSWXViews = [NSMutableArray array];
    gMSWDeskClips = [NSMutableArray array]; gMSWDeskLabels = [NSMutableArray array]; gMSWStripPortals = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) {
        CGRect r = [rects[i] CGRectValue];
        [gMSWDeskRects addObject:rects[i]];
        UIView *clip = [[UIView alloc] initWithFrame:r];
        clip.clipsToBounds = YES; clip.layer.cornerRadius = 6.0; clip.backgroundColor = [UIColor blackColor];
        BOOL current = i == MIN(gMSWCur, n - 1);
        if (current) {
            clip.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor; clip.layer.borderWidth = 2.0;
            UIView *desk = [[UIView alloc] initWithFrame:b];
            for (UIWindow *sw in DMMSWScreenWindows()) {
                CGRect pr = CGRectNull;
                UIView *p = DMMSWPortalInPlace(sw, root, desk, &pr);
                // (a Zetsu window is a window of its own the size of the app's window: it lands where it is on the screen -- left out, the current
                //  desktop's tile showed no windows under Zetsu)
                if (p && !DMIsZetsuWindow(sw) && !CGRectEqualToRect(CGRectIntegral(CGRectInset(pr, 0.5, 0.5)), CGRectIntegral(CGRectInset(b, 0.5, 0.5)))) {
                    DMLog([NSString stringWithFormat:@"[macswitcher] the desktop's thumbnail leaves out %@: it lands at %@, not on the screen", NSStringFromClass([sw class]), NSStringFromCGRect(pr)]);
                    [gMSWPortals removeObjectIdenticalTo:p]; DMMSWPortalLetGo(p);
                } else if (p) [gMSWStripPortals addObject:p];
            }
            desk.transform = CGAffineTransformMakeScale(r.size.width / b.size.width, r.size.height / b.size.height);
            desk.center = CGPointMake(r.size.width / 2.0, r.size.height / 2.0);
            [clip addSubview:desk];
        } else {
            NSNumber *did = gMSWDesks.count > i ? gMSWDesks[i] : nil;
            UIView *shot = did ? gMSWShots[did] : nil;
            if (did && (!shot || ![gMSWShotSet[did] isEqualToArray:DMMSWWindowSet(did.integerValue)]) && (shot || DMMSWWindowSet(did.integerValue).count)) shot = DMMSWComposedDesktop(did.integerValue, b);   // (stale or none)
            if (shot) {   // (as it was left: scaled to fill the tile)
                [shot removeFromSuperview];
                shot.transform = CGAffineTransformIdentity;
                CGSize ss = shot.bounds.size;
                CGFloat k = MAX(r.size.width / MAX(1.0, ss.width), r.size.height / MAX(1.0, ss.height));
                shot.transform = CGAffineTransformMakeScale(k, k);
                shot.center = CGPointMake(r.size.width / 2.0, r.size.height / 2.0);
                [clip addSubview:shot];
            } else if (gMSWWallContents) {   // (not seen since the respring: its wallpaper)
                UIView *wv = [[UIView alloc] initWithFrame:clip.bounds];
                wv.layer.contents = gMSWWallContents; wv.layer.contentsRect = gMSWWallContentsRect; wv.layer.contentsGravity = kCAGravityResizeAspectFill;
                [clip addSubview:wv];
            }
        }
        [strip addSubview:clip];
        [gMSWDeskClips addObject:clip];
        UILabel *dl = DMMSWLabel(DMMSWDeskName(i), 12.0, UIFontWeightMedium);
        dl.frame = CGRectMake(CGRectGetMinX(r) - 20, CGRectGetMaxY(r) + 3.0, r.size.width + 40, labelH);
        [strip addSubview:dl];
        [gMSWDeskLabels addObject:dl];
        // the remove button (not on Desktop 1): shown while the pointer is over the desktop, or after a held finger
        UIView *x = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetMinX(r) - 9, CGRectGetMinY(r) - 9, 22, 22)];
        x.backgroundColor = [UIColor colorWithWhite:0.25 alpha:0.95]; x.layer.cornerRadius = 11.0;
        x.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor; x.layer.borderWidth = 1.0;
        UILabel *xl = DMMSWLabel(@"×", 16.0, UIFontWeightSemibold); xl.frame = x.bounds; [x addSubview:xl];
        x.hidden = YES;
        [strip addSubview:x];
        [gMSWXViews addObject:i == 0 ? (id)[NSNull null] : x];
    }
    gMSWDeskRect = [gMSWDeskRects[MIN(gMSWCur, n - 1)] CGRectValue];
    gMSWPlusRect = plusRect; gMSWPlusView = nil;
    if (!CGRectIsNull(gMSWPlusRect)) {
        UIView *plus = [[UIView alloc] initWithFrame:gMSWPlusRect];
        plus.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        plus.layer.cornerRadius = 6.0;
        plus.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor; plus.layer.borderWidth = 1.0;
        UILabel *plusLabel = DMMSWLabel(@"+", gMSWPlusRect.size.height * 0.45, UIFontWeightLight);
        plusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        plusLabel.frame = plus.bounds;
        [plus addSubview:plusLabel];
        [strip addSubview:plus];
        gMSWPlusView = plus;
    }
    gMSWStrip = strip; gMSWStripH = stripH;
    return strip;
}
// A window's thumbnail made ready to show: its portal holder, its title under it (round corners for a full-screen app: its portal fills inner).
static CGRect DMMSWLabelFrame(DMMSWTile *t) { return CGRectMake(t.layoutRect.origin.x - 10, CGRectGetMaxY(t.layoutRect) + 6.0, t.layoutRect.size.width + 20, 18.0); }
static void DMMSWTileCorners(DMMSWTile *t, CGRect shownAt) {
    if (t.kind == DMMSWKindFullScreen && shownAt.size.width > 1) { t.inner.layer.cornerRadius = 10.0 * t.sourceRect.size.width / shownAt.size.width; t.inner.layer.masksToBounds = YES; }
}
static void DMMSWSetUpTile(DMMSWTile *t, CGRect b) {
    DMMSWTileCorners(t, t.layoutRect);
    t.frame = b; t.userInteractionEnabled = NO;
    [t addSubview:t.inner];
    t.label = DMMSWLabel(t.title, 13.0, UIFontWeightMedium);
    t.label.frame = DMMSWLabelFrame(t);
    [t addSubview:t.label];
}

static void DMMSWBuild(BOOL animated) {
    UIView *root = DMMSWBuildRoot();
    CGRect b = root.bounds;

    UIView *back = root.subviews.firstObject;

    // the strip: the desktops (the current one live, the others as they were left) and "+"
    UIView *strip = DMMSWBuildStrip(root, b);
    [root addSubview:strip];
    CGFloat stripH = gMSWStripH;

    // the windows
    gMSWTitleH = 26.0;
    gMSWArea = CGRectMake(40.0, stripH + 24.0, b.size.width - 80.0, b.size.height - stripH - 24.0 - 36.0);
    gMSWTiles = [DMMSWCollect(root) mutableCopy];
    DMMSWArrange(gMSWTiles, gMSWArea, gMSWTitleH);
    for (DMMSWTile *t in gMSWTiles) {
        DMMSWSetUpTile(t, b);
        [root addSubview:t];
    }
    gMSWHilite = [UIView new];
    gMSWHilite.userInteractionEnabled = NO; gMSWHilite.hidden = YES;
    gMSWHilite.layer.borderColor = [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:1.0].CGColor; gMSWHilite.layer.borderWidth = 3.0; gMSWHilite.layer.cornerRadius = 8.0;
    [root addSubview:gMSWHilite];

    if (!gMSWTarget) gMSWTarget = [DMMSWTarget new];
    [root addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:gMSWTarget action:@selector(tap:)]];
    [root addGestureRecognizer:[[UIHoverGestureRecognizer alloc] initWithTarget:gMSWTarget action:@selector(hover:)]];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:gMSWTarget action:@selector(hold:)];
    hold.minimumPressDuration = 0.5;
    hold.delegate = gMSWTarget;
    [root addGestureRecognizer:hold];
    // a window's thumbnail dragged onto another desktop (the drag section): a finger, or the pointer's click-and-drag (indirect pointer touches)
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:gMSWTarget action:@selector(pan:)];
    pan.maximumNumberOfTouches = 1;
    pan.allowedTouchTypes = @[@(UITouchTypeDirect), @(UITouchTypeIndirect), @(UITouchTypeIndirectPointer), @(UITouchTypePencil)];
    pan.delegate = gMSWTarget;
    [root addGestureRecognizer:pan];
    gMSWAllX = NO;

    // in: the windows fly from where they are to their places, the strip comes down, the background fades in
    for (DMMSWTile *t in gMSWTiles) { DMMSWPlace(t.inner, t.sourceRect, animated ? t.sourceRect : t.layoutRect); t.label.alpha = animated ? 0 : 1; }
    if (!animated) return;
    back.alpha = 0; strip.transform = CGAffineTransformMakeTranslation(0, -stripH);
    if (MSBReduceMotion()) { strip.transform = CGAffineTransformIdentity; strip.alpha = 0; }
    MSBAnimate(0.36, 0, 0.88, UIViewAnimationOptionCurveEaseOut, ^{
        back.alpha = 1; strip.transform = CGAffineTransformIdentity; strip.alpha = 1;
        for (DMMSWTile *t in gMSWTiles) { DMMSWPlace(t.inner, t.sourceRect, t.layoutRect); t.label.alpha = 1; }
    }, nil);
}

// Lets every portal go and drops the content (the window stays).
static NSUInteger DMMSWDropContent(void) {
    DMMSWDropFinishNow();   // (a dropped window still on its way: it leaves the screen now, while its thumbnail's portal is still there for its picture)
    DMMSWDragReset();   // (a drag in the view goes with it: its thumbnail's portal is let go below)
    for (UIView *p in gMSWPortals) DMMSWPortalLetGo(p);
    NSUInteger n = gMSWPortals.count;
    gMSWPortals = nil;
    gMSWTiles = nil;
    gMSWHilite = nil;
    gMSWStrip = nil; gMSWStripPortals = nil; gMSWDeskClips = nil; gMSWDeskLabels = nil; gMSWPlusView = nil;
    for (UIGestureRecognizer *g in [gMSWRoot.gestureRecognizers copy]) [gMSWRoot removeGestureRecognizer:g];
    [gMSWRoot removeFromSuperview];
    gMSWRoot = nil;
    return n;
}
static void DMMSWTeardown(void) {
    DMMSWCutLetGo();
    NSUInteger n = DMMSWDropContent();
    DMMSWOpenShotDrop();   // (closed without a switch: the picture goes)
    if (!gMSWSlRoot) gMSWWindow.hidden = YES;
    gMSWOpen = NO; gMSWClosing = NO; gMSWTurnAt = 0;
    DMMSWFocus(NO);
    DMMenuKeyboardOrder();   // (a windowed app's keyboard goes back to its level)
    DMLog([NSString stringWithFormat:@"[macswitcher] closed: %lu portals let go", (unsigned long)n]);
}
static BOOL DMMSWIsOpen(void) { return gMSWOpen; }

static CFTimeInterval gMSWGestureAt = 0;   // (a gesture just opened the view: SpringBoard's own switcher is still on its way back for a moment)
static BOOL DMMSWGestureGrace(void) { return CACurrentMediaTime() - gMSWGestureAt < 1.5; }
static void DMMSWOpen(NSString *why) {
    DM_FEATURE_MARK("mac-switcher");
    if (!gMSWOn) { DMLog([NSString stringWithFormat:@"[macswitcher] not opened (%@): switched off", why]); return; }
    if (DMMSWIsOpen()) { if (!gMSWClosing) DMMSWClose(nil, YES); return; }   // (opened again while open: it closes, like the Mission Control key)
    if (DMGARefuses([NSString stringWithFormat:@"the Mac Switcher (%@)", why])) return;   // (Guided Access keeps the iPad in one app: no other desktop, no other window -- 1.3.7, audit M-7)
    if ((DMSwitcherVisible() && !DMMSWGestureGrace()) || DMCoverSheetShown() || gMSWSwitching || gMSWTrack >= 2) { DMLog(@"[macswitcher] not opened: the App Switcher or the Lock Screen is up, or a desktop is sliding in"); return; }
    UIWindow *w = DMMSWLayer();
    if (!w) return;
    // (the desktop under the view, as a picture: the left desktop's for a switch from the strip -- the one from the start of the gesture that
    //  opens the view when there is one, as SpringBoard's card moved after it; else the screen now, before the view is drawn: a cheap picture)
    //  F5: the screen picture is asked for without waiting (DMMSWScreenPictureAsync, our window left out) -- UIKit's waiting one once held
    //  SpringBoard 3.7 s when the view opened during an app's cold launch; the view opens at once and the picture is there long before a tap in
    //  the strip can use it (else that switch takes the screen without the view, DMMSWLeftPicture)
    // (only for the gesture's own opening: a keyboard, Home double press or accessibility opening within 2 s of a gesture took that gesture's start
    //  picture -- the screen before the gesture --, and since K-1 that picture exists with one desktop too; 1.4.1 logic test L-4. Debug
    //  /tmp/msw-liftany = before.)
    BOOL byGesture = DMMSWGestureGrace() || DMTestFlag("/tmp/msw-liftany");
    BOOL lift = byGesture && gMSWLiftPic && gMSWLiftPicId == DMMSWCurId() && (CACurrentMediaTime() - gMSWLiftPicAt < 2.0 || (DMMSWGestureGrace() && gMSWLiftPicGen == gMSWTrackPicGen));
    DMMSWOpenShotDrop();
    gMSWOpenShotId = DMMSWCurId();
    // (opened by the hold: the picture from the gesture's start, taken before SpringBoard moved anything (DMMSWTrackBegin / DMMSWStartPicture) --
    //  the screen now is SpringBoard's own return from the hold still on screen (the Home Screen zoomed, K-1). It belongs to the gesture that opened
    //  the view whatever its age: a hold may last more than 2 s.)
#if DEBUG
    if (DMMSWGestureGrace()) DMLog([NSString stringWithFormat:@"[macswitcher] opened by the hold: the desktop's picture %@", lift ? @"from the gesture's start" : @"none from its start: the screen now"]);
#endif
    if (lift) gMSWOpenShot = gMSWLiftPic;
    else {
        NSUInteger gen = gMSWOpenShotGen;
        NSInteger did = DMMSWCurId();
        BOOL asked = DMMSWAsyncScreenOn() && DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], ^(UIView *pic, double ms) {
            BOOL use = pic && gen == gMSWOpenShotGen && gMSWOpen && DMMSWCurId() == did;
            if (use) gMSWOpenShot = pic;
            DMLog([NSString stringWithFormat:@"[macswitcher] the view's picture of the desktop under it: %@ after %.1f ms (asked without waiting)", !pic ? @"not drawn" : use ? @"in" : @"no longer needed", ms]);
        });
        if (!asked) {
            DMMSWSpanBegin();
            gMSWOpenShot = [[UIScreen mainScreen] snapshotViewAfterScreenUpdates:NO];
            DMMSWSpanEnd(@"the view's open picture (the screen now)");
        }
    }
    gMSWLiftPic = nil;
    w.userInteractionEnabled = YES;
    w.hidden = NO;
    [w layoutIfNeeded];
    gMSWOpen = YES;
    DMMSWFocus(YES);
    DMMenuKeyboardOrder();   // (a windowed app's keyboard steps under the view, as under a menu)
    DMMSWBuild(YES);
    DMLog([NSString stringWithFormat:@"[macswitcher] open (%@): %lu windows, %lu portals, root %@", why, (unsigned long)gMSWTiles.count, (unsigned long)gMSWPortals.count, NSStringFromCGSize(gMSWBuiltSize)]);
}
// Brings the picked window forward (as a click on it would).
static void DMMSWBringForward(DMMSWTile *t) {
    switch (t.kind) {
        case DMMSWKindNative: {
            DMNativeWindow *w = t.native;
            if (w && [gNativeWindows containsObject:w]) [w show];
            break;
        }
        case DMMSWKindStage:
        case DMMSWKindFullScreen:
            if (gNativeActive) DMNativeSetActive(nil);   // (an app's window comes forward: the native windows step back)
            if (t.bundle.length && DMSMEngine()) DMSMBringToFront(t.bundle);   // (Stage Manager: in front of its stage)
            else if (t.bundle.length && t.kind == DMMSWKindStage && (DMActiveEngine() == DMEngineZetsu || DMActiveEngine() == DMEngineMilkyWay))
                DMSurfaceWindowForApp(t.bundle);   // (Zetsu / MilkyWay4: DMRaiseStageForBundle is a tap's follow-up -- Zetsu raises a window on its own
                                                   //  tap, MilkyWay has no Aerial raise -- so a pick here left the window where it was, M1 7 Oct; this
                                                   //  is what opening the app does: that engine's own raise)
            else if (t.bundle.length) DMRaiseStageForBundle(t.bundle);
            break;
    }
    DMLog([NSString stringWithFormat:@"[macswitcher] picked %@ (%@)", t.title, t.kind == DMMSWKindNative ? @"native window" : t.kind == DMMSWKindStage ? @"window" : @"full-screen app"]);
}
static void DMMSWClose(DMMSWTile *pick, BOOL animated) {
    if (!DMMSWIsOpen() || gMSWClosing) return;
    DMMSWDragAbort();   // (closed mid-drag -- Esc, Home, the App Switcher --: the window goes back among the others and closes with them)
    gMSWClosing = YES;
    if (pick) DMMSWBringForward(pick);
    gMSWHilite.hidden = YES;
    if (!animated || !gMSWRoot || gMSWTurnAt > 0) { DMMSWTeardown(); return; }
    if (pick) [gMSWRoot bringSubviewToFront:pick];
    UIView *root = gMSWRoot;
    MSBAnimate(0.3, 0, 0.92, UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState, ^{
        for (UIView *v in root.subviews) if (![v isKindOfClass:[DMMSWTile class]]) v.alpha = 0;
        for (DMMSWTile *t in gMSWTiles) { DMMSWPlace(t.inner, t.sourceRect, t.sourceRect); t.label.alpha = 0; }
    }, ^(BOOL f) { if (gMSWRoot == root) DMMSWTeardown(); });
}
static DMMSWTile *DMMSWTileAt(CGPoint p) {
    for (DMMSWTile *t in [gMSWTiles reverseObjectEnumerator]) if (CGRectContainsPoint(CGRectInset(t.layoutRect, -4, -4), p)) return t;
    return nil;
}
static void DMMSWPlusTapped(void) {
    DMLog(@"[macswitcher] \"+\" tapped");
    DMMSWAddDesktop();
}
static NSInteger DMMSWDeskAt(CGPoint p) {
    for (NSUInteger i = 0; i < gMSWDeskRects.count; i++) if (CGRectContainsPoint(CGRectInset([gMSWDeskRects[i] CGRectValue], -6, -6), p)) return (NSInteger)i;
    return -1;
}
static NSInteger DMMSWXAt(CGPoint p) {   // a shown remove button under p
    for (NSUInteger i = 0; i < gMSWXViews.count; i++) {
        UIView *x = gMSWXViews[i];
        if ([x isKindOfClass:[UIView class]] && !x.hidden && CGRectContainsPoint(CGRectInset(x.frame, -8, -8), p)) return (NSInteger)i;
    }
    return -1;
}
static void DMMSWShowX(NSInteger only) {   // only: that desktop's (-1 none), or all with gMSWAllX
    for (NSUInteger i = 0; i < gMSWXViews.count; i++) { UIView *x = gMSWXViews[i]; if ([x isKindOfClass:[UIView class]]) x.hidden = !(gMSWAllX || (NSInteger)i == only); }
}
static void DMMSWRebuildOpen(void) {   // (the open view laid out again in place: a desktop was removed)
    if (!gMSWOpen || gMSWClosing) return;
    DMMSWDropContent();
    DMMSWBuild(NO);
}
static void DMMSWTapped(UITapGestureRecognizer *g) {
    if (gMSWClosing || gMSWSwitching || gMSWDragTile || gMSWDropping || g.state != UIGestureRecognizerStateEnded) return;   // (another finger's tap while a window is dragged: nothing)
    CGPoint p = [g locationInView:gMSWRoot];
    NSInteger xi = DMMSWXAt(p);
    if (xi > 0) { DMLog([NSString stringWithFormat:@"[macswitcher] remove button of %@ tapped", DMMSWDeskName(xi)]); DMMSWRemoveDesktop((NSUInteger)xi); return; }
    if (!CGRectIsNull(gMSWPlusRect) && CGRectContainsPoint(gMSWPlusRect, p)) { DMMSWPlusTapped(); return; }
    NSInteger di = DMMSWDeskAt(p);
    if (di >= 0 && (NSUInteger)di != gMSWCur && DMMSWMulti()) { DMLog([NSString stringWithFormat:@"[macswitcher] %@ tapped: switching", DMMSWDeskName(di)]); DMMSWSwitchTo((NSUInteger)di, @"strip", nil); return; }
    DMMSWTile *t = DMMSWTileAt(p);
    if (t) { DMMSWClose(t, YES); return; }
    DMLog(di >= 0 ? @"[macswitcher] the current desktop tapped: closed" : @"[macswitcher] a tap on empty space: closed");
    DMMSWClose(nil, YES);
}
static void DMMSWHover(UIHoverGestureRecognizer *g) {
    if (gMSWClosing || !gMSWHilite || gMSWDragTile) return;   // (a window being dragged has its own highlight: the desktop it would go to)
    CGPoint p = [g locationInView:gMSWRoot];
    BOOL gone = g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled;
    DMMSWTile *t = gone ? nil : DMMSWTileAt(p);
    NSInteger di = gone ? -1 : DMMSWDeskAt(p);
    if (di < 0 && !gone) { NSInteger xi = DMMSWXAt(p); if (xi > 0) di = xi; }   // (on its remove button, which reaches outside the tile)
    DMMSWShowX(di);
    CGRect r = t ? t.layoutRect : (di >= 0 ? [gMSWDeskRects[di] CGRectValue] : CGRectNull);
    gMSWHilite.hidden = CGRectIsNull(r);
    if (!CGRectIsNull(r)) { gMSWHilite.frame = CGRectInset(r, -4, -4); [gMSWRoot bringSubviewToFront:gMSWHilite]; }
}
static void DMMSWHold(UILongPressGestureRecognizer *g) {
    if (g.state != UIGestureRecognizerStateBegan || gMSWClosing) return;
    if (DMMSWDeskAt([g locationInView:gMSWRoot]) < 0) return;
    gMSWAllX = YES;
    DMMSWShowX(-1);
    DMLog(@"[macswitcher] a desktop held: the remove buttons show");
}

// ==== a window dragged onto another desktop (as in Mission Control on a Mac) ====
// Press on a window's thumbnail and move: it lifts and follows the finger or the pointer (the other thumbnails stay); near the strip it gets
// small, as on a Mac, so it fits on a desktop there. Over another desktop that desktop is highlighted; let go there and the window goes to that
// desktop -- it leaves this view (the others close up), lands where it is in that desktop's picture in the strip, and the current desktop stays
// current (no slide). Over "+" or the empty end of the strip: a new desktop holding that window. Anywhere else (its own desktop too) it goes back
// to its place. A tap still picks a window: the drag begins only once the finger or pointer has moved past UIKit's pan threshold (~10 points), so
// a tap that wobbles a little is still a tap; a finger held on a window may still drag it (the remove buttons' hold is the strip's only).
// The move is engine-neutral (records, Fit to Window per desktop, pictures: DMMSWMoveRecords / DMMSWMoveFinish). Aerial, Zetsu, MilkyWay4 / no engine take the window off the screen
// as a switch does (DMMSWApply: hidden, its app in the background, keyboard focus held off). Stage Manager moves it out of the desktop's stage
// (MacSwitcherSM.h DMMSWSMMoveRecord / DMMSWSMMoveFinish); a desktop there holds as many windows as a stage can (DMSMWindowCap(): 7 on 16.7.7), and
// a full desktop does what MacSwitcherSM.h DMMSWSMAtCap says -- today it refuses the drop with a short shake (macOS has no limit to imitate; "no
// room" changes nothing). A full-screen app can be dragged too: it becomes that desktop's full-screen app -- opened full screen
// when that desktop comes, as a full-screen app left on a desktop is -- and this desktop shows what is behind it (its windows, or the Home
// Screen) once the view closes; a desktop that keeps a full-screen app already refuses another (one per desktop). Zetsu and MilkyWay4 move it as
// Aerial does (their windows are away the same way: hidden, the app in the background, keyboard focus held off).
static NSUInteger gMSWDragIndex = 0;     // the dragged thumbnail's place in gMSWTiles (it goes back there)
static CGPoint gMSWDragGrab;             // where it was taken, as a part of the thumbnail (0..1 each way): kept under the finger
static CGPoint gMSWDragAt;               // the finger / pointer now (root coordinates)
static CGFloat gMSWDragSize = 1.0;       // its size, a part of its thumbnail's (lifted 1.04, small near the strip), eased each frame
static CGFloat gMSWDragLift = 0;         // 0..1: its shadow, eased in
static CGRect gMSWDragRect;              // where it is drawn now
static NSInteger gMSWDragTarget = -2;    // the target highlighted now (kMSWDropNone: none)
static NSInteger gMSWDragUnder = -2;     // what is under the finger now (a target it may be refused by: asked again only when this changes -- with
                                         //  Stage Manager the full-desktop check reads its stages, not for every movement)
static CFTimeInterval gMSWDragFrameAt = 0;
static CADisplayLink *gMSWDragLink;
static UIView *gMSWDragShadow;           // its shadow while lifted
static UIView *gMSWDropHilite;           // the highlight on the desktop (or "+") it would go to

static BOOL DMMSWDragAllowed(DMMSWTile *t) {
    if (!t || !gMSWOn || !gMSWOpen || gMSWClosing || gMSWSwitching || gMSWDropping || gMSWDragTile || gMSWTurnAt > 0 || !gMSWRoot || gMSWTrack >= 2) return NO;
    if (!DMMSWDesktopsHere()) return NO;
    return t.kind == DMMSWKindNative ? t.native != nil : t.bundle.length > 0;
}
static BOOL DMMSWDragMayBegin(UIPanGestureRecognizer *g) {
    if (!gMSWRoot) return NO;
    CGPoint p = [g locationInView:gMSWRoot], tr = [g translationInView:gMSWRoot];   // (where the finger went down: the pan reports past its threshold)
    return DMMSWDragAllowed(DMMSWTileAt(CGPointMake(p.x - tr.x, p.y - tr.y)));
}
static BOOL DMMSWHoldMayBegin(UILongPressGestureRecognizer *g) {
    return gMSWRoot && !gMSWDragTile && !gMSWDropping && DMMSWDeskAt([g locationInView:gMSWRoot]) >= 0;
}
// What a window let go at p goes to: a desktop's place, kMSWDropNew ("+", or the strip's empty end right of the last desktop), or kMSWDropNone.
static NSInteger DMMSWDropTargetAt(CGPoint p) {
    if (!gMSWDeskRects.count || p.y > gMSWStripH + 4.0) return kMSWDropNone;
    NSInteger di = DMMSWDeskAt(p);
    if (di >= 0) return di;
    if (CGRectIsNull(gMSWPlusRect)) return kMSWDropNone;
    return p.x > CGRectGetMaxX([gMSWDeskRects.lastObject CGRectValue]) + 6.0 ? kMSWDropNew : kMSWDropNone;
}
// Why the window can't go to that target: nil = it can; @"" = no target there (it goes back to its place); a reason = refused (a short shake).
static NSString *DMMSWDropRefusal(DMMSWTile *t, NSInteger target) {
    if (!t || target == kMSWDropNone) return @"";
    if (target == kMSWDropNew) return gMSWDesks.count >= kMSWMaxDesks ? @"there are the most desktops already" : nil;
    if (target < 0 || target >= (NSInteger)gMSWDesks.count || target == (NSInteger)gMSWCur) return @"";
    NSInteger did = gMSWDesks[target].integerValue;
    if (DMSMEngine()) return t.kind != DMMSWKindNative && DMMSWSMDropRefused(did) ? [NSString stringWithFormat:@"%@ holds %lu windows already (Stage Manager's most)", DMMSWDeskName(target), (unsigned long)DMSMWindowCap()] : nil;   // (full: MacSwitcherSM.h DMMSWSMAtCap)
    if (t.kind == DMMSWKindFullScreen && gMSWFullScreen[[@(did) stringValue]]) return [NSString stringWithFormat:@"%@ keeps a full-screen app already", DMMSWDeskName(target)];
    return nil;
}
// The highlight on the target (the hover highlight's blue), or none; "+" lights up too.
static void DMMSWDropHighlight(NSInteger target) {
    if (!gMSWRoot) return;
    CGRect r = target >= 0 && target < (NSInteger)gMSWDeskRects.count ? [gMSWDeskRects[target] CGRectValue] : (target == kMSWDropNew ? gMSWPlusRect : CGRectNull);
    BOOL show = !CGRectIsNull(r);
    if (!gMSWDropHilite) {
        UIView *nh = [UIView new];
        nh.userInteractionEnabled = NO; nh.alpha = 0;
        nh.layer.borderColor = [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:1.0].CGColor; nh.layer.borderWidth = 3.0; nh.layer.cornerRadius = 9.0;
        nh.backgroundColor = [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:0.18];
        gMSWDropHilite = nh;
    }
    UIView *h = gMSWDropHilite;
    if (gMSWDragTile.superview == gMSWRoot) [gMSWRoot insertSubview:h belowSubview:gMSWDragTile];   // (over the strip, under the window)
    else if (h.superview != gMSWRoot) [gMSWRoot addSubview:h];
    if (show && h.alpha < 0.01) h.frame = CGRectInset(r, -5, -5);
    UIView *plus = gMSWPlusView;
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (show) h.frame = CGRectInset(r, -5, -5);
        h.alpha = show ? 1 : 0;
        plus.backgroundColor = [UIColor colorWithWhite:1 alpha:target == kMSWDropNew ? 0.32 : 0.14];
    } completion:nil];
}
// One frame of the drag: the thumbnail where the finger is (the place it was taken at stays under it), its size eased toward what it should be
// there -- lifted a little; in reach of the strip small enough to sit on one of its desktops, as a Mac shrinks a window dragged to its Spaces.
static void DMMSWDragFrame(void) {
    DMMSWTile *t = gMSWDragTile;
    if (!t || !gMSWRoot) return;
    CFTimeInterval now = CACurrentMediaTime();
    double dt = gMSWDragFrameAt > 0 ? MIN(0.05, MAX(0.0, now - gMSWDragFrameAt)) : 1.0 / 120.0;
    gMSWDragFrameAt = now;
    CGRect home = t.layoutRect;
    CGFloat thumbW = gMSWDeskRects.count ? [gMSWDeskRects.firstObject CGRectValue].size.width : 120.0;
    CGFloat small = MIN(1.04, thumbW * 0.62 / MAX(1.0, home.size.width));
    CGFloat reach = gMSWArea.origin.y + 70.0, top = gMSWStripH * 0.5;
    CGFloat near = MAX(0.0, MIN(1.0, (reach - gMSWDragAt.y) / MAX(1.0, reach - top)));
    near = near * near * (3.0 - 2.0 * near);
    CGFloat want = 1.04 + (small - 1.04) * near, k = 1.0 - exp(-dt / 0.05);
    gMSWDragSize += (want - gMSWDragSize) * k;
    gMSWDragLift += (1.0 - gMSWDragLift) * k;
    CGSize sz = CGSizeMake(home.size.width * gMSWDragSize, home.size.height * gMSWDragSize);
    CGRect r = CGRectMake(gMSWDragAt.x - gMSWDragGrab.x * sz.width, gMSWDragAt.y - gMSWDragGrab.y * sz.height, sz.width, sz.height);
    gMSWDragRect = r;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    DMMSWPlace(t.inner, t.sourceRect, r);
    DMMSWTileCorners(t, r);
    UIView *sh = gMSWDragShadow;
    if (sh) {
        sh.frame = r;
        sh.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:sh.bounds cornerRadius:MIN(10.0, r.size.width * 0.03)].CGPath;
        sh.layer.shadowOpacity = 0.45 * gMSWDragLift;
    }
    [CATransaction commit];
}
static void DMMSWDragTargetUpdate(void) {
    NSInteger target = DMMSWDropTargetAt(gMSWDragAt);
    if (target == gMSWDragUnder) return;
    gMSWDragUnder = target;
    if (DMMSWDropRefusal(gMSWDragTile, target)) target = kMSWDropNone;   // (only a desktop it can go to lights up)
    if (target == gMSWDragTarget) return;
    gMSWDragTarget = target;
    DMMSWDropHighlight(target);
}
static void DMMSWDragStart(DMMSWTile *t, CGPoint start, CGPoint now) {
    NSUInteger i = [gMSWTiles indexOfObjectIdenticalTo:t];
    if (i == NSNotFound) return;
    gMSWDragIndex = i;
    [gMSWTiles removeObjectAtIndex:i];
    gMSWDragTile = t;
    CGRect home = t.layoutRect;
    gMSWDragGrab = CGPointMake(MAX(0.0, MIN(1.0, (start.x - home.origin.x) / MAX(1.0, home.size.width))), MAX(0.0, MIN(1.0, (start.y - home.origin.y) / MAX(1.0, home.size.height))));
    gMSWDragAt = now; gMSWDragSize = 1.0; gMSWDragLift = 0; gMSWDragRect = home; gMSWDragTarget = kMSWDropNone; gMSWDragUnder = kMSWDropNone; gMSWDragFrameAt = 0;
    [gMSWRoot bringSubviewToFront:t];
    gMSWHilite.hidden = YES;
    if (!gMSWAllX) DMMSWShowX(-1);
    UIView *sh = [[UIView alloc] initWithFrame:home];   // (its shadow: a lifted window)
    sh.userInteractionEnabled = NO;
    sh.layer.shadowColor = [UIColor blackColor].CGColor; sh.layer.shadowOffset = CGSizeMake(0, 10); sh.layer.shadowRadius = 18.0; sh.layer.shadowOpacity = 0;
    [t insertSubview:sh belowSubview:t.inner];
    gMSWDragShadow = sh;
    UILabel *label = t.label;
    [UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{ label.alpha = 0; } completion:nil];
    [gMSWDragLink invalidate];
    gMSWDragLink = [CADisplayLink displayLinkWithTarget:gMSWTarget selector:@selector(dragFrame:)];
    gMSWDragLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
    [gMSWDragLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    DMMSWDragFrame();
    DMLog([NSString stringWithFormat:@"[macswitcher] dragging %@ (%@, by %@)", t.title, t.kind == DMMSWKindNative ? @"native window" : t.kind == DMMSWKindStage ? @"window" : @"full-screen app",
        gMSWDragPointer ? @"the pointer" : gMSWDragTouchType == UITouchTypeDirect ? @"a finger" : [NSString stringWithFormat:@"touch type %ld", (long)gMSWDragTouchType]]);
}
// Back to its place among the others (let go over no desktop, its own desktop, or refused).
static void DMMSWDragHome(void) {
    DMMSWTile *t = gMSWDragTile;
    if (!t) return;
    gMSWDragTile = nil;
    [gMSWDragLink invalidate]; gMSWDragLink = nil;
    if (gMSWTiles) [gMSWTiles insertObject:t atIndex:MIN(gMSWDragIndex, gMSWTiles.count)];
    UIView *sh = gMSWDragShadow; gMSWDragShadow = nil;
    CGRect home = t.layoutRect;
    DMMSWTileCorners(t, home);
    MSBAnimate(0.34, 0, 0.84, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{
        DMMSWPlace(t.inner, t.sourceRect, home);
        sh.frame = home; sh.alpha = 0;
        t.label.alpha = 1;
    }, ^(BOOL f) { [sh removeFromSuperview]; });
}
// The view closes (or is laid out again) mid-drag: the window is put back among the others at once, without a drop.
static void DMMSWDragAbort(void) {
    DMMSWTile *t = gMSWDragTile;
    if (!t) return;
    gMSWDragTile = nil;
    [gMSWDragLink invalidate]; gMSWDragLink = nil;
    [gMSWDragShadow removeFromSuperview]; gMSWDragShadow = nil;
    gMSWDropHilite.alpha = 0; gMSWDragTarget = kMSWDropNone;
    if (gMSWTiles) [gMSWTiles insertObject:t atIndex:MIN(gMSWDragIndex, gMSWTiles.count)];
    t.label.alpha = 1;
    DMLog(@"[macswitcher] the view closes mid-drag: the window goes back among the others");
}
static void DMMSWDragReset(void) {   // (the view's content goes: nothing of a drag is left)
    [gMSWDragLink invalidate]; gMSWDragLink = nil;
    gMSWDragTile = nil; gMSWDragShadow = nil; gMSWDropping = NO; gMSWDragTarget = kMSWDropNone;
    [gMSWDropHilite removeFromSuperview]; gMSWDropHilite = nil;
}
// A refused drop: the desktop shakes its head (Reduce Motion: its border flashes red once instead).
static void DMMSWShake(NSInteger target) {
    UIView *v = target >= 0 && target < (NSInteger)gMSWDeskClips.count ? gMSWDeskClips[target] : (target == kMSWDropNew ? gMSWPlusView : nil);
    if (!v) return;
    if (MSBReduceMotion()) {
        UIView *flash = [[UIView alloc] initWithFrame:CGRectInset(v.frame, -4, -4)];
        flash.userInteractionEnabled = NO;
        flash.layer.borderColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0].CGColor; flash.layer.borderWidth = 3.0; flash.layer.cornerRadius = 9.0;
        [v.superview addSubview:flash];
        [UIView animateWithDuration:0.5 delay:0.1 options:UIViewAnimationOptionCurveEaseIn animations:^{ flash.alpha = 0; } completion:^(BOOL f) { [flash removeFromSuperview]; }];
        return;
    }
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    a.values = @[@0, @-10, @9, @-7, @5, @-3, @0]; a.duration = 0.42; a.additive = YES;
    [v.layer addAnimation:a forKey:@"msw.shake"];
}

// ---- the thumbnail's picture: a still copy of what its portal shows, where the window is (root coordinates) ----
static UIView *DMMSWTilePortal(DMMSWTile *t) {
    for (UIView *v in t.inner.subviews) if ([gMSWPortals indexOfObjectIdenticalTo:v] != NSNotFound) return v;
    return nil;
}
// For the desktop it is dropped on (its picture in the strip), taken when it has landed, before the window leaves the screen. Stage Manager: the card
// with our title bar above it (MacSwitcherSM.h). nil: nothing to draw.
static UIView *DMMSWTilePicture(DMMSWTile *t) {
    if (!t.source || !gMSWRoot) return nil;
    if (DMSMEngine() && t.kind != DMMSWKindNative) {
        CGRect r = CGRectNull;
        UIView *pic = DMMSWSMCardPicture(t.source, &r);
        if (!pic || CGRectIsNull(r)) return nil;
        pic.userInteractionEnabled = NO;
        pic.frame = [gMSWRoot convertRect:r fromCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
        return pic;
    }
    UIView *portal = DMMSWTilePortal(t);
    if (!portal) return nil;
    UIView *pic = [t.source snapshotViewAfterScreenUpdates:NO];
    if (!pic) return nil;
    pic.userInteractionEnabled = NO;
    pic.bounds = portal.bounds; pic.center = portal.center; pic.transform = portal.transform;   // (placed as the portal is: through the screen, turned if its window is)
    return pic;
}

// ---- the move itself (engine-neutral) ----
// The Home Screen comes under the open view (a full-screen app went to another desktop): the same simulated press as Minimize, which the Home
// button's handlers (MacSwitcherButton.h) do not take for the user's -- the view stays open.
static void DMMSWOwnHome(void) {
    gMSWOwnHomeAt = CACurrentMediaTime();
    DMMinimize();
    gMSWOwnHomeAt = CACurrentMediaTime();
}
// Fit to Window per desktop (Aerial, Zetsu, MilkyWay4 / no engine): the window leaves this desktop's tiles and the rest close up -- as when a tiled window closes
// (DMWatchFitClosures' rule: two or more take the default tiles, one fills the space) --, and it takes a place in the other desktop's tiles: in
// front (newest first) while there are fewer than four, tiled there when that desktop comes (DMMSWChangeDesktop); a free window (No Fit) stays
// free there. YES when this desktop's windows were tiled again (their thumbnails move).
static BOOL DMMSWFitMove(NSString *b, NSInteger toId) {
    BOOL wasFree = [gFreeWindows containsObject:b], wasTiled = [gFitGroup containsObject:b], retiled = NO;
    [gFreeWindows removeObject:b];
    if (wasTiled) {
        DMFitGroupForget(b);
        NSMutableArray<NSString *> *left = [NSMutableArray array];
        for (NSString *x in gFitGroup) { UIView *s = DMStageForBundle(x); if (s && DMStageTakesPartInFit(s)) [left addObject:x]; }
        gFitGroup = left;
        if (DMFitEnabled() && left.count) {
            gFitSlots = [DMFitPlanAfterLeave(left) mutableCopy];   // (two or more: the default tiles; one fills -- the plan Stage Manager's drag takes too)
            gMoveKeepsOrder = YES; DMApplyGroupSlots(nil); gMoveKeepsOrder = NO;
            retiled = YES;
            DMLog([NSString stringWithFormat:@"[fit] %@ went to another desktop: %lu window(s) left here, tiled again to fill the space", b, (unsigned long)left.count]);
        }
        DMFitWatchSync();   // (the closure check must not take the window that left for a closed one and tile the rest a second time)
    }
    if (!DMFitEnabled()) return retiled;
    NSString *k = [@(toId) stringValue];
    NSDictionary *fit = gMSWFit[k];
    NSMutableArray<NSString *> *group = [NSMutableArray array], *free = [NSMutableArray array];
    if ([fit[@"group"] isKindOfClass:[NSArray class]]) for (id x in fit[@"group"]) if ([x isKindOfClass:[NSString class]] && ![x isEqualToString:b]) [group addObject:x];
    if ([fit[@"free"] isKindOfClass:[NSArray class]]) for (id x in fit[@"free"]) if ([x isKindOfClass:[NSString class]] && ![x isEqualToString:b]) [free addObject:x];
    if (wasFree) [free addObject:b];
    else if (group.count < 4) [group insertObject:b atIndex:0];
    NSMutableDictionary<NSString *, NSString *> *slots = [NSMutableDictionary dictionary];
    NSArray<NSString *> *names = DMDefaultSlotNames(group.count);
    if (group.count >= 2) for (NSUInteger i = 0; i < group.count && i < names.count; i++) slots[group[i]] = names[i];
    if (!gMSWFit) gMSWFit = [NSMutableDictionary dictionary];
    gMSWFit[k] = @{@"group": group, @"slots": slots, @"free": free, @"fitOn": fit[@"fitOn"] ?: @NO};   // (made with Fit off there: its windows join when it comes)
    return retiled;
}
// What the desktop a window went to needs for its new picture (DMMSWDeskTakesWindow): whether its picture as it was left was still true before the
// move, and whether a picture drawn from its parts shows the window by itself.
typedef struct { BOOL shotOK, drawnHasIt; } DMMSWMoveInfo;
// A window dragged away in the open view: every window it covered in part keeps that part of it in the view's opening picture (gMSWCutShot), so
// their pictures from it name it (gMSWCutSpoiled): true only on a desktop where it is too. The engine's windows behind it are the ones before it
// in DMAerialStagesAll (back to front). Native windows have their own layer, in front of the engine's windows or behind them: they count as
// covering every window they overlap, and as covered by every one -- an app icon card at worst, never a window that has gone.
static void DMMSWCutSpoil(UIView *gone, NSString *goneKey) {
    if (!gMSWCutShot || !gone || !goneKey.length) return;
    UIScreen *scr = [UIScreen mainScreen];
    CGRect g = [gone convertRect:gone.bounds toCoordinateSpace:scr.coordinateSpace];
    if (!gMSWCutSpoiled) gMSWCutSpoiled = [NSMutableDictionary dictionary];
    __block NSUInteger n = 0;
    void (^spoil)(NSString *, UIView *) = ^(NSString *key, UIView *w) {
        if (!key.length || [key isEqualToString:goneKey] || !CGRectIntersectsRect(g, [w convertRect:w.bounds toCoordinateSpace:scr.coordinateSpace])) return;
        NSMutableSet *set = gMSWCutSpoiled[key] ?: [NSMutableSet set];
        [set addObject:goneKey]; gMSWCutSpoiled[key] = set; n++;
    };
    for (UIView *st in DMAerialStagesAll()) {
        if (st == gone) break;   // (the ones in front of it: not covered by it)
        if (st.hidden || [objc_getAssociatedObject(st, kMSWAwayKey) boolValue]) continue;
        spoil(DMStageBundle(st), st);
    }
    for (DMNativeWindow *w in gNativeWindows) if (w != gone && !w.hidden) spoil(DMMSWNativeCutKey(w), w);
    if (n) DMLog([NSString stringWithFormat:@"[macswitcher] %@ covered part of %lu window(s) in the view's opening picture: their pictures from it name it", goneKey, (unsigned long)n]);
}
// A drop happens in two steps, so that nothing holds the thumbnail back when the finger lifts (measured on the M1: three pictures of the window
// taken at the lift -- ~35 ms, ~4 ms and ~29 ms -- held the frame for 93 ms before the thumbnail flew):
//  1. at the lift (DMMSWMoveRecords): the records -- the window belongs to that desktop now (saved), Fit to Window per desktop --, and the
//     thumbnail flies at once, its portal live: the window itself stays on the screen under the opaque view until it has landed (gMSWDropHold);
//  2. when it has landed (DMMSWMoveFinish; at once when the view goes or a switch starts first): the window's picture for its new desktop, then
//     the window leaves the screen -- Aerial / no engine: away, as a switch takes it (DMMSWApply); a full-screen app: Home under the view;
//     Stage Manager: out of this desktop's stage (DMMSWSMMoveFinish) -- and that desktop's picture shows it.
// Moves the thumbnail's window to the desktop at place `to` (gMSWDesks.count: a new desktop at the end, made here). The current desktop stays.
// Returns that desktop's id, or 0 (nothing moved); *retiled: this desktop's windows were tiled again (Fit to Window).
static NSInteger DMMSWMoveRecords(DMMSWTile *t, NSUInteger to, BOOL *retiled, DMMSWMoveInfo *info) {
    if (retiled) *retiled = NO;
    if (info) *info = (DMMSWMoveInfo){ NO, NO };
    if (!t || !DMMSWDesktopsHere() || (to < gMSWDesks.count && to == gMSWCur)) return 0;
    CGRect bounds = gMSWRoot ? gMSWRoot.bounds : [UIScreen mainScreen].bounds;
    NSInteger toId = to < gMSWDesks.count ? gMSWDesks[to].integerValue : 0;
    UIView *shot = toId ? gMSWShots[@(toId)] : nil;   // (that desktop's picture as it was left: still true until now? read before the records change)
    BOOL shotOK = shot && [gMSWShotSet[@(toId)] isEqualToArray:DMMSWWindowSet(toId)] && CGSizeEqualToSize(shot.bounds.size, bounds.size);
    BOOL fresh = !toId;
    if (fresh) toId = DMMSWMakeDesktop();   // (dropped on "+": a new desktop, not shown)
    if (!toId) return 0;
    NSUInteger ti = [gMSWDesks indexOfObject:@(toId)];
    NSNumber *key = @(toId);
    NSString *bundle = t.bundle;
    BOOL drawnHasIt = NO;   // (a picture drawn from parts -- DMMSWComposedDesktop -- shows the window already)
    switch (t.kind) {
        case DMMSWKindNative:
            if (!t.native) { if (fresh) { [gMSWDesks removeObject:key]; if (gMSWDesks.count == 1) [gMSWWinDesk removeAllObjects]; } return 0; }   // (nothing moved: the desktop made for it goes again)
            objc_setAssociatedObject(t.native, kMSWNativeDeskKey, key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            gMSWDropHoldNative = t.native;
            break;
        case DMMSWKindStage:
        case DMMSWKindFullScreen:
            if (DMSMEngine()) {   // (Stage Manager: a card of the desktop's stage, full size or not -- MacSwitcherSM.h)
                DMMSWSMMoveRecord(bundle, toId);
                drawnHasIt = YES;
            } else if (t.kind == DMMSWKindFullScreen) {   // (that desktop's full-screen app, opened full screen when it comes; here: Home when it lands)
                if (!gMSWFullScreen) gMSWFullScreen = [NSMutableDictionary dictionary];
                gMSWFullScreen[key.stringValue] = bundle;
            } else {
                gMSWWinDesk[bundle] = key;
                gMSWDropHold = bundle;
                BOOL r = DMMSWFitMove(bundle, toId);
                if (retiled) *retiled = r;
                drawnHasIt = YES;
            }
            break;
    }
    gMSWDesksDirty = YES;
    DMMSWSave();
    if (info) *info = (DMMSWMoveInfo){ shotOK, drawnHasIt };
    if (gMSWOpenShot && !DMSMEngine() && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion == 15) {   // (its other windows' pictures, see
        DMMSWCutLetGo(); gMSWCutShot = gMSWOpenShot; gMSWCutShotId = gMSWOpenShotId;                                    //  gMSWCutShot; where DMMSWSwitchRun
    }                                                                                                                    //  draws the left desktop from parts)
    if (gMSWCutShot && gMSWCutShotId == DMMSWCurId()) DMMSWCutSpoil(t.kind == DMMSWKindNative ? t.native : t.kind == DMMSWKindStage ? t.source : nil, t.kind == DMMSWKindNative ? DMMSWNativeCutKey(t.native) : bundle);
    DMMSWOpenShotDrop();   // (this desktop's picture from when the view opened shows the window still: a switch from the strip takes the screen anew)
    DM_FEATURE_MARK("mac-switcher-drag-to-desktop");
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ dragged to %@%@: it is there now; %@ stays the current desktop", t.title ?: bundle, DMMSWDeskName(ti), fresh ? @" (a new desktop)" : @"", DMMSWDeskName(gMSWCur)]);
    return toId;
}
static void DMMSWDeskTakesWindow(NSInteger toId, UIView *pic, DMMSWMoveInfo info);
// asked: the window's picture asked for at the drop without waiting (F5) -- a view, NSNull when it was asked but is not in (the view went or a
// switch started first: no picture then), nil when it was not asked (Stage Manager, or no such call here: the waiting pictures, as before).
static UIView *DMMSWPicCopy(UIView *pic) {   // (another view showing the same picture: its slot lives while any of them does)
    UIView *c = [[UIView alloc] initWithFrame:pic.bounds];
    c.userInteractionEnabled = NO;
    c.layer.contents = pic.layer.contents;
    id h = objc_getAssociatedObject(pic, kMSWSlotKey);
    if (h) objc_setAssociatedObject(c, kMSWSlotKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return c;
}
static UIView *DMMSWPicAsPortal(UIView *pic, DMMSWTile *t) {   // (placed as the thumbnail's portal is: through the screen, turned if its window is)
    UIView *portal = DMMSWTilePortal(t);
    if (!pic || !portal) return nil;
    UIView *c = DMMSWPicCopy(pic);
    c.bounds = portal.bounds; c.center = portal.center; c.transform = portal.transform;
    return c;
}
static void DMMSWMoveFinish(DMMSWTile *t, NSInteger toId, DMMSWMoveInfo info, id asked) {
    CFTimeInterval t0 = CACurrentMediaTime();
    // the window's pictures, while it is still on the screen: for its new desktop's picture, for the resting thumbnail (its window leaves the screen
    // now -- a portal of a hidden window shows nothing, of a full-screen app its way Home -- and it fades out), and the away window's own (DMMSWApply
    // would take it again otherwise). F5: one picture asked for at the drop without waiting, shown three times (the waiting ones held the landing
    // 20-130 ms -- 131 ms measured on the M1 7 Oct)
    BOOL showing = t.superview && t.superview == gMSWRoot;
    UIView *pic = nil, *still = nil, *awayPic = nil;
    NSString *how = @"";
    if (!asked) {
        pic = DMMSWTilePicture(t);
        still = showing ? DMMSWTilePicture(t) : nil;
        awayPic = (t.kind == DMMSWKindStage && !DMSMEngine() && t.bundle.length && !t.source.hidden) ? [t.source snapshotViewAfterScreenUpdates:NO] : nil;
    } else if ([asked isKindOfClass:[UIView class]]) {
        pic = DMMSWPicAsPortal(asked, t);   // (the portal's place in its holder is the window's in root coordinates: as DMMSWTilePicture's)
        still = showing ? DMMSWPicAsPortal(asked, t) : nil;
        awayPic = (t.kind == DMMSWKindStage && t.bundle.length) ? DMMSWPicCopy(asked) : nil;
        how = @" (asked at the drop, without waiting)";
    } else how = @" (none: not in when the landing had to go on)";
    if (still) { UIView *portal = DMMSWTilePortal(t); [t.inner addSubview:still]; if (portal) { [gMSWPortals removeObjectIdenticalTo:portal]; DMMSWPortalLetGo(portal); } }
    if (awayPic) { if (!gMSWWinShots) gMSWWinShots = [NSMutableDictionary dictionary]; gMSWWinShots[t.bundle] = awayPic; }
    CFTimeInterval t1 = CACurrentMediaTime();
    gMSWDropHold = nil; gMSWDropHoldNative = nil;
    if (t.kind != DMMSWKindNative && DMSMEngine()) DMMSWSMMoveFinish(t.bundle, toId);
    else if (t.kind == DMMSWKindFullScreen) { DMLog([NSString stringWithFormat:@"[macswitcher] %@ is %@'s full-screen app now: Home here", t.bundle, DMMSWDeskName([gMSWDesks indexOfObject:@(toId)])]); DMMSWOwnHome(); }
    DMMSWApply();   // (the window goes from the screen: hidden, its picture and place kept, its keyboard focus held off; Stage Manager: the native ones)
    CFTimeInterval t2 = CACurrentMediaTime();
    DMMSWSave();
    DMMSWDeskTakesWindow(toId, pic, info);
    DMLog([NSString stringWithFormat:@"[macswitcher] %@ landed: picture %.1f ms%@, off the screen %.1f ms, its desktop's picture %.1f ms", t.title, (t1 - t0) * 1000, how, (t2 - t1) * 1000, (CACurrentMediaTime() - t2) * 1000]);
}
static void DMMSWDropFinishNow(void) { dispatch_block_t f = gMSWDropFinish; gMSWDropFinish = nil; if (f) f(); }

// The desktop the window went to gets a picture that shows it (its tile in the strip, and its picture for a slide there): its picture as it was left
// with the window's picture over it where the window is, or drawn from its parts (wallpaper and its windows' pictures, the window among them).
// pic: the window's still picture in root coordinates (or nil). Made when the dropped window lands (the old picture stays in its tile meanwhile).
static void DMMSWDeskTakesWindow(NSInteger toId, UIView *pic, DMMSWMoveInfo info) {
    if (!toId || ![gMSWDesks containsObject:@(toId)] || toId == DMMSWCurId()) return;
    NSNumber *key = @(toId);
    CGRect bounds = gMSWRoot ? gMSWRoot.bounds : [UIScreen mainScreen].bounds;
    if (!gMSWShots) gMSWShots = [NSMutableDictionary dictionary];
    if (!gMSWShotSet) gMSWShotSet = [NSMutableDictionary dictionary];
    UIView *base = info.shotOK ? gMSWShots[key] : DMMSWComposedDesktop(toId, bounds);
    if (!info.shotOK && base && !DMTestFlag("/tmp/msw-drawnshared-old")) {
        // (drawn from its parts: the window goes in among its windows' pictures, and that picture itself is kept -- marked drawn, its window pictures
        //  tagged --, so a slide to the desktop puts the Home Screen, the Dock and the menu bar under them, live: DMMSWDeskPicture / DMMSWSlShared)
        if (pic && !info.drawnHasIt) { [pic removeFromSuperview]; pic.tag = 0x4D53; [base addSubview:pic]; }
        gMSWShots[key] = base; gMSWShotSet[key] = DMMSWWindowSet(toId);
        return;
    }
    UIView *c = [[UIView alloc] initWithFrame:bounds];
    c.clipsToBounds = YES; c.userInteractionEnabled = NO; c.backgroundColor = [UIColor blackColor];
    if (base) {
        [base removeFromSuperview];
        base.transform = CGAffineTransformIdentity;
        base.center = CGPointMake(CGRectGetMidX(c.bounds), CGRectGetMidY(c.bounds));
        [c addSubview:base];
    }
    if (pic && (info.shotOK || !info.drawnHasIt)) { [pic removeFromSuperview]; [c addSubview:pic]; }
    gMSWShots[key] = c; gMSWShotSet[key] = DMMSWWindowSet(toId);
}

// ---- the view follows ----
// The window thumbnails laid out again where they are (one went away): they slide to their new places.
static void DMMSWLayOutTiles(void) {
    if (!gMSWRoot) return;
    DMMSWArrange(gMSWTiles, gMSWArea, gMSWTitleH);
    for (DMMSWTile *t in gMSWTiles) DMMSWTileCorners(t, t.layoutRect);
    NSArray<DMMSWTile *> *tiles = [gMSWTiles copy];
    MSBAnimate(0.36, 0, 0.86, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{
        for (DMMSWTile *t in tiles) { DMMSWPlace(t.inner, t.sourceRect, t.layoutRect); t.label.frame = DMMSWLabelFrame(t); }
    }, nil);
}
static NSString *DMMSWTileKey(DMMSWTile *t) { return t.kind == DMMSWKindNative ? [NSString stringWithFormat:@"native %p", t.native] : (t.bundle ?: @"?"); }
// Whether a thumbnail shows a window of the current desktop (one dragged away can still be on screen for a moment: Stage Manager asks for the
// desktop's stage a frame later, a full-screen app is on its way Home).
static BOOL DMMSWTileHere(DMMSWTile *t) {
    if (!DMMSWMulti()) return YES;
    NSInteger cur = DMMSWCurId();
    if (t.kind == DMMSWKindNative) { NSNumber *d = t.native ? objc_getAssociatedObject(t.native, kMSWNativeDeskKey) : nil; return !d || d.integerValue == cur; }
    if (!t.bundle.length) return YES;
    NSNumber *d = gMSWWinDesk[t.bundle];
    if (!d && DMSMEngine() && !DMSMKeyIsApp(t.bundle)) d = gMSWWinDesk[DMSMKeyBundle(t.bundle)];   // (Stage Manager: a tile is a window's key; a record by app stands for its windows, MacSwitcherSM.h)
    if (DMSMEngine() || t.kind == DMMSWKindStage) return !d || d.integerValue == cur;
    for (NSString *k in gMSWFullScreen) if ([gMSWFullScreen[k] isEqualToString:t.bundle] && k.integerValue != cur) return NO;
    return YES;
}
// The window thumbnails made again from the screen (their windows moved: Fit to Window tiled them again, or Stage Manager laid its stage out
// anew): each slides from where its old thumbnail was to its new place.
static void DMMSWRecollect(void) {
    if (!gMSWOpen || gMSWClosing || !gMSWRoot || gMSWTurnAt > 0 || gMSWDragTile) return;
    NSMutableDictionary<NSString *, NSValue *> *was = [NSMutableDictionary dictionary];
    for (DMMSWTile *t in gMSWTiles) {
        was[DMMSWTileKey(t)] = [NSValue valueWithCGRect:t.layoutRect];
        UIView *p = DMMSWTilePortal(t);
        if (p) { [gMSWPortals removeObjectIdenticalTo:p]; DMMSWPortalLetGo(p); }
        [t removeFromSuperview];
    }
    NSMutableArray<DMMSWTile *> *tiles = [NSMutableArray array];
    for (DMMSWTile *t in DMMSWCollect(gMSWRoot)) {
        if (DMMSWTileHere(t)) { [tiles addObject:t]; continue; }
        UIView *p = DMMSWTilePortal(t);
        if (p) { [gMSWPortals removeObjectIdenticalTo:p]; DMMSWPortalLetGo(p); }
    }
    DMMSWArrange(tiles, gMSWArea, gMSWTitleH);
    CGRect b = gMSWRoot.bounds;
    for (DMMSWTile *t in tiles) {
        DMMSWSetUpTile(t, b);
        if (gMSWHilite.superview == gMSWRoot) [gMSWRoot insertSubview:t belowSubview:gMSWHilite]; else [gMSWRoot addSubview:t];
        NSValue *from = was[DMMSWTileKey(t)];
        if (from) { DMMSWPlace(t.inner, t.sourceRect, from.CGRectValue); t.label.frame = CGRectMake(from.CGRectValue.origin.x - 10, CGRectGetMaxY(from.CGRectValue) + 6.0, from.CGRectValue.size.width + 20, 18.0); }
        else { DMMSWPlace(t.inner, t.sourceRect, t.layoutRect); t.alpha = 0; }
    }
    gMSWTiles = tiles;
    MSBAnimate(0.36, 0, 0.86, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{
        for (DMMSWTile *t in tiles) { DMMSWPlace(t.inner, t.sourceRect, t.layoutRect); t.label.frame = DMMSWLabelFrame(t); t.alpha = 1; }
    }, nil);
    DMLog([NSString stringWithFormat:@"[macswitcher] the view's windows made again: %lu", (unsigned long)tiles.count]);
}
// The strip laid out again in place: a desktop made by a drop on "+" (`added`: its place, else -1) or a desktop's new picture. The tiles slide to
// their new places; the new desktop's tile comes in after newDelay (once the window flying to it is there).
static void DMMSWStripRefresh(NSInteger added, NSTimeInterval newDelay) {
    if (!gMSWRoot || !gMSWStrip || gMSWClosing) return;
    UIView *old = gMSWStrip;
    NSArray<NSValue *> *oldRects = [gMSWDeskRects copy];
    CGRect oldPlus = gMSWPlusRect;
    NSArray<UIView *> *oldPortals = gMSWStripPortals;
    UIView *strip = DMMSWBuildStrip(gMSWRoot, gMSWRoot.bounds);
    [gMSWRoot insertSubview:strip aboveSubview:old];
    [old removeFromSuperview];
    for (UIView *p in oldPortals) { [gMSWPortals removeObjectIdenticalTo:p]; DMMSWPortalLetGo(p); }
    if (gMSWAllX) DMMSWShowX(-1);
    CGAffineTransform (^from)(CGRect, CGRect) = ^CGAffineTransform(CGRect was, CGRect now) {   // (the move that puts a view laid out at `now` back at `was`)
        CGAffineTransform m = CGAffineTransformMakeTranslation(CGRectGetMidX(was) - CGRectGetMidX(now), CGRectGetMidY(was) - CGRectGetMidY(now));
        return now.size.width > 0 && fabs(was.size.width - now.size.width) > 0.5 ? CGAffineTransformScale(m, was.size.width / now.size.width, was.size.width / now.size.width) : m;
    };
    NSMutableArray<UIView *> *moving = [NSMutableArray array];
    for (NSUInteger i = 0; i < gMSWDeskClips.count; i++) {
        UIView *clip = gMSWDeskClips[i], *label = gMSWDeskLabels[i];
        UIView *x = [gMSWXViews[i] isKindOfClass:[UIView class]] ? gMSWXViews[i] : nil;
        if ((NSInteger)i == added) {   // (the new desktop: comes in once the window is in it; newDelay < 0: hidden until it is)
            clip.alpha = 0; label.alpha = 0;
            if (newDelay < 0) continue;
            if (!MSBReduceMotion()) clip.transform = CGAffineTransformMakeScale(0.9, 0.9);
            [UIView animateWithDuration:0.18 delay:newDelay options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{ clip.alpha = 1; label.alpha = 1; clip.transform = CGAffineTransformIdentity; } completion:nil];
            continue;
        }
        if (i >= oldRects.count) continue;
        CGRect was = [oldRects[i] CGRectValue], now = [gMSWDeskRects[i] CGRectValue];
        if (CGRectEqualToRect(was, now)) continue;
        CGAffineTransform m = from(was, now);
        clip.transform = m; label.transform = m; x.transform = m;
        [moving addObjectsFromArray:x ? @[clip, label, x] : @[clip, label]];
    }
    if (gMSWPlusView && !CGRectIsNull(oldPlus) && !CGRectEqualToRect(oldPlus, gMSWPlusRect)) { gMSWPlusView.transform = from(oldPlus, gMSWPlusRect); [moving addObject:gMSWPlusView]; }
    if (moving.count) MSBAnimate(0.32, 0, 0.9, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction, ^{ for (UIView *v in moving) v.transform = CGAffineTransformIdentity; }, nil);
}
// Let go over a desktop it can go to: the window goes there (DMMSWMoveRecords at once, DMMSWMoveFinish once landed), its thumbnail flies -- its
// portal live, nothing is done before it starts -- to where the window is in that desktop's picture, rests there while the window's picture is
// taken and the window leaves the screen, and fades out as the desktop's picture takes it; the others close up.
static void DMMSWDrop(DMMSWTile *t, NSInteger target) {
    NSUInteger oldCount = gMSWDesks.count, to = target == kMSWDropNew ? oldCount : (NSUInteger)target;
    CFTimeInterval t0 = CACurrentMediaTime();
    BOOL retiled = NO;
    DMMSWMoveInfo info;
    NSInteger toId = DMMSWMoveRecords(t, to, &retiled, &info);
    if (!toId) { DMLog([NSString stringWithFormat:@"[macswitcher] %@ could not be moved: back to its place", t.title]); DMMSWDragHome(); return; }
    CFTimeInterval t1 = CACurrentMediaTime();
    to = [gMSWDesks indexOfObject:@(toId)];
    BOOL added = gMSWDesks.count > oldCount, rm = MSBReduceMotion();
    gMSWDragTile = nil; gMSWDropping = YES;
    UIView *sh = gMSWDragShadow; gMSWDragShadow = nil;
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    DMMSWStripLayout(gMSWRoot.bounds, gMSWDesks.count, YES, rects, NULL);   // (a drop: only where desktops are)
    CGRect tile = to < rects.count ? [rects[to] CGRectValue] : gMSWDragRect;
    CGFloat k = tile.size.width / MAX(1.0, gMSWRoot.bounds.size.width);
    CGRect into = CGRectMake(tile.origin.x + t.sourceRect.origin.x * k, tile.origin.y + t.sourceRect.origin.y * k, t.sourceRect.size.width * k, t.sourceRect.size.height * k);
    // F5: the window's picture for the landing, asked for now without waiting -- it is still on the screen, held there until it has landed (Stage
    // Manager's cards: the waiting picture, as before)
    __block UIView *dropPic = nil;
    __block BOOL dropPicIn = NO;
    BOOL dropPicAsked = (t.kind == DMMSWKindNative || !DMSMEngine()) && t.source && DMMSWAsyncPicsOn() && DMMSWPictureAsync(t.source, ^(UIView *pic, double ms) {
        dropPic = pic; dropPicIn = YES;
        DMMSWMark([NSString stringWithFormat:@"drop picture in (%.0f ms)", ms]);
    });
    gMSWDropFinish = ^{   // (once landed -- or at once when the view goes or a switch starts first)
        DMMSWMoveFinish(t, toId, info, !dropPicAsked ? nil : (dropPic ?: (id)[NSNull null]));
        if (DMSMEngine() && t.kind != DMMSWKindNative)   // (Stage Manager lays its stage out anew a moment later: the thumbnails follow)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gMSWOpen && !gMSWClosing && !gMSWDropping && !gMSWDragTile) DMMSWRecollect(); });
    };
    [UIView animateWithDuration:rm ? kMSBRMDuration : 0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (rm) t.alpha = 0;   // (Reduce Motion: it fades where it is)
        else { DMMSWPlace(t.inner, t.sourceRect, into); DMMSWTileCorners(t, into); sh.frame = into; }
        sh.alpha = 0;
    } completion:^(BOOL f) {
        [sh removeFromSuperview];
        void (^landed)(void) = ^{
            DMMSWDropFinishNow();   // (the window's picture, then it leaves the screen: the thumbnail rests on its desktop meanwhile)
            if (!gMSWRoot || t.superview != gMSWRoot) { [t removeFromSuperview]; gMSWDropping = NO; return; }   // (the view closed meanwhile)
            CFTimeInterval s0 = CACurrentMediaTime();
            DMMSWStripRefresh(added ? (NSInteger)to : -1, 0);   // (its desktop's picture shows it now; a new desktop's tile comes in)
            DMLog([NSString stringWithFormat:@"[macswitcher] the strip shows it: %.1f ms", (CACurrentMediaTime() - s0) * 1000]);
            [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ t.alpha = 0; } completion:^(BOOL f2) {
                [t removeFromSuperview];
                gMSWDropping = NO;
            }];
        };
        if (!dropPicAsked || dropPicIn || !gMSWDropFinish) { landed(); return; }
        // (its picture is not in yet: the thumbnail rests where it landed -- the main thread free -- until it is, at most 0.25 s more)
        CFTimeInterval w0 = CACurrentMediaTime();
        __block void (^poll)(void);
        void (^p)(void) = ^{
            if (dropPicIn || !gMSWDropFinish || CACurrentMediaTime() - w0 > 0.25) { poll = nil; landed(); return; }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(NSEC_PER_SEC / 120)), dispatch_get_main_queue(), poll);
        };
        poll = p;
        dispatch_async(dispatch_get_main_queue(), poll);
    }];
    [CATransaction flush];   // (the flight to the render server now)
    if (added) DMMSWStripRefresh((NSInteger)to, -1);   // (the tiles make room for the new desktop; its tile shows once the window is in it)
    if (retiled) DMMSWRecollect(); else DMMSWLayOutTiles();     // (the others close up: Fit to Window tiled this desktop's windows again -- new places)
    DMLog([NSString stringWithFormat:@"[macswitcher] drop: records %.1f ms, the view %.1f ms", (t1 - t0) * 1000, (CACurrentMediaTime() - t1) * 1000]);
}
static void DMMSWDragEnd(CGPoint p, BOOL cancelled) {
    DMMSWTile *t = gMSWDragTile;
    if (!t) return;
    gMSWDragAt = p;
    DMMSWDragFrame();
    [gMSWDragLink invalidate]; gMSWDragLink = nil;
    NSInteger target = cancelled ? kMSWDropNone : DMMSWDropTargetAt(p);
    NSString *no = DMMSWDropRefusal(t, target);
    gMSWDragTarget = kMSWDropNone;
    DMMSWDropHighlight(kMSWDropNone);
    if (no) {
        if (no.length) { DMMSWShake(target); DMLog([NSString stringWithFormat:@"[macswitcher] %@ let go on %@: refused (%@), back to its place", t.title, target == kMSWDropNew ? @"\"+\"" : DMMSWDeskName((NSUInteger)target), no]); }
        else DMLog([NSString stringWithFormat:@"[macswitcher] %@ let go %@: back to its place", t.title, cancelled ? @"(the drag was cancelled)" : target >= 0 ? @"on its own desktop" : @"over no desktop"]);
        DMMSWDragHome();
        return;
    }
    DMMSWDrop(t, target);
}
static void DMMSWDragPan(UIPanGestureRecognizer *g) {
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            if (!gMSWRoot) return;
            CGPoint now = [g locationInView:gMSWRoot], tr = [g translationInView:gMSWRoot];
            CGPoint start = CGPointMake(now.x - tr.x, now.y - tr.y);
            DMMSWTile *t = DMMSWTileAt(start);
            if (DMMSWDragAllowed(t)) DMMSWDragStart(t, start, now);
            break;
        }
        case UIGestureRecognizerStateChanged:
            if (!gMSWDragTile || !gMSWRoot) return;
            gMSWDragAt = [g locationInView:gMSWRoot];
            DMMSWDragTargetUpdate();
            DMMSWDragFrame();
            break;
        case UIGestureRecognizerStateEnded:
            if (gMSWDragTile && gMSWRoot) DMMSWDragEnd([g locationInView:gMSWRoot], NO);
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (gMSWDragTile) DMMSWDragEnd(gMSWDragAt, YES);
            break;
        default:
            break;
    }
}

// ---- memory: the kept pictures go under memory pressure (audit M-5) ----
// Each desktop left keeps its picture (its thumbnail in the strip, the slide's picture of it) and each window that went away keeps one (cut out of
// its desktop's picture, or its own): render-server images of the screen's size -- ~16 MB each on the M1 (docs/native-engine-notes.md 18(f)) --,
// held by backboardd for as long as SpringBoard runs. When the system warns of memory pressure (UIKit's memory warning, and the kernel's pressure
// level through a dispatch memory-pressure source: warning or critical) they are let go -- the ones a slide or the open view shows right now stay
// with that view until it goes -- and are made again when needed: a desktop without its picture is drawn from its parts (its wallpaper, its
// windows' pictures or their app icons: DMMSWComposedDesktop / DMMSWDeskPicture), and its picture is taken again the next time it is left.
static void DMMSWSMFreePictures(void);   // (MacSwitcherSM.h: Stage Manager's own -- the Home Screen's picture of an empty desktop)
static NSUInteger gMSWFreedTimes = 0;
static void DMMSWFreePictures(NSString *why) {
    NSUInteger desks = gMSWShots.count, wins = gMSWWinShots.count;
    BOOL lift = gMSWLiftPic != nil && !gMSWLiftPic.superview, open = gMSWOpenShot != nil && !gMSWOpen;
    [gMSWShots removeAllObjects]; [gMSWShotSet removeAllObjects]; [gMSWWinShots removeAllObjects];
    if (lift) gMSWLiftPic = nil;
    if (open) DMMSWOpenShotDrop();
    DMMSWSMFreePictures();
    gMSWFreedTimes++;
    DM_FEATURE_MARK("mac-switcher-memory-pressure");
    DMLog([NSString stringWithFormat:@"[macswitcher] %@: pictures let go -- %lu desktop(s), %lu window(s)%@%@ (drawn again when needed)", why, (unsigned long)desks, (unsigned long)wins, lift ? @", the gesture's" : @"", open ? @", the view's" : @""]);
}
static void DMMSWWatchMemory(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { DMMSWFreePictures(@"UIKit's memory warning"); }];
    static dispatch_source_t src;
    src = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0, DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, dispatch_get_main_queue());
    if (!src) { DMLog(@"[macswitcher] no memory-pressure source here: UIKit's memory warning only"); return; }
    dispatch_source_set_event_handler(src, ^{ unsigned long level = dispatch_source_get_data(src); DMMSWFreePictures((level & DISPATCH_MEMORYPRESSURE_CRITICAL) ? @"memory pressure (critical)" : @"memory pressure (warning)"); });
    dispatch_resume(src);
}

// ---- iPadOS's own App Switcher, this once (Apple menu > Show App Switcher) ----
// Owner's design (4 Oct; replaces 3 Oct's, where the row switched the Mac Switcher off -- found confusing): the row opens iPadOS's App Switcher ONE
// time and the Mac Switcher stays on; nothing is written. From the request until that switcher has gone, every takeover stands aside so it shows,
// is used and closes the way iPadOS has it (a swipe up, the Home button, a card picked, a hold inside it): the hold's fly-in and lift
// (DMMSWGesturesOn), the desktop slide's tracker (armed only with the gestures on), the completion safety net and the Home button's double press
// (MacSwitcherButton.h). Then the next hold or double press is the Mac Switcher's again. The stock switcher never comes by itself: only this request
// lets it through, and only until it has closed.
static CFTimeInterval gMSWStockAskedAt = 0;   // (the menu asked for iPadOS's switcher: the takeovers stand aside from then until it has gone)
static BOOL gMSWStockSeen = NO;               // (it has come up)
static int gMSWStockGoneTicks = 0;            // (ticks without it since it came up: two in a row = gone, a one-tick gap in its state never ends it)
static BOOL DMMSWStockOnce(void) { return gMSWStockAskedAt > 0; }
static void DMMSWStockEnd(NSString *why) {
    gMSWStockAskedAt = 0; gMSWStockSeen = NO; gMSWStockGoneTicks = 0;
    DMLog([NSString stringWithFormat:@"[macswitcher] iPadOS's App Switcher (from the menu) %@: the hold and the Home button's double press are the Mac Switcher's again", why]);
}
// The tick (DMMSWTick): when it came up, and when it has gone (or never came: the request was not taken, 2 s).
static void DMMSWStockTick(void) {
    if (!gMSWStockAskedAt) return;
    if (DMSwitcherVisible()) {
        gMSWStockGoneTicks = 0;
        if (!gMSWStockSeen) { gMSWStockSeen = YES; DMLog([NSString stringWithFormat:@"[macswitcher] iPadOS's App Switcher is up (from the menu, %.0f ms after the request): it is iPadOS's until it closes", (CACurrentMediaTime() - gMSWStockAskedAt) * 1000]); }
        return;
    }
    if (gMSWStockSeen) { if (++gMSWStockGoneTicks >= 2) DMMSWStockEnd(@"has closed"); }
    else if (CACurrentMediaTime() - gMSWStockAskedAt > 2.0) DMMSWStockEnd(@"did not come up");
}

// The tick (StatusBar.x's watcher): the view goes when the App Switcher or the Lock Screen comes up or the switch goes off; a turn lays it out again.
// A turn: the thumbnails go at once (measured mid-turn they came out sideways: the engine's windows turn after the screen does) and the view is
// laid out again once the screen has kept its shape for 0.8 s.
static void DMMSWKeysRefresh(void);
static void DMMSWTick(void) {
    DMMSWStockTick();   // (iPadOS's own App Switcher asked for from the menu: is it still up)
    DMMSWKeysRefresh();   // (the Control-arrows SpringBoard is to get: registered again when that changes)
    if (!gMSWSwitching) DMMSWApply();   // (desktops: cheap with one desktop and nothing away)
    if (gMSWTrack) DMMSWTrackTick();
    if (gMSWLiftPic && !gMSWLiftPic.superview && CACurrentMediaTime() - gMSWLiftPicAt > 2.5 && !DMMSWGestureAlive(gMSWLiftPicGesture)) gMSWLiftPic = nil;   // (nothing took the gesture's picture)
    if (!gMSWOpen || gMSWClosing) return;
    if (!gMSWOn || (DMSwitcherVisible() && !DMMSWGestureGrace()) || DMCoverSheetShown()) { DMLog(@"[macswitcher] the App Switcher / Lock Screen came up or the switch went off: closed"); DMMSWClose(nil, NO); return; }
    CGSize screen = [UIScreen mainScreen].bounds.size;
    BOOL portraitNow = screen.height > screen.width, portraitBuilt = gMSWBuiltSize.height > gMSWBuiltSize.width;
    CFTimeInterval now = CACurrentMediaTime();
    if (portraitNow != portraitBuilt || DMMSWTurnKey() != gMSWBuiltTurn) {
#if DEBUG
        if (DMTestFlag("/tmp/msw-oldturn")) {   // (test: the first build's behaviour, laid out again at once, mid-turn -- the 3 Oct stall hunt)
            DMLog(@"[macswitcher] (msw-oldturn) the screen turned: laid out again at once");
            DMMSWDropContent(); DMMSWBuild(NO);
            return;
        }
#endif
        if (!gMSWTurnAt) DMLog([NSString stringWithFormat:@"[macswitcher] the screen is turning: %lu thumbnails let go until it settles", (unsigned long)DMMSWDropContent()]);
        else DMMSWDropContent();
        gMSWTurnAt = now;
        DMMSWBuildRoot();   // (the background alone meanwhile; its size is the new one)
        return;
    }
    if (gMSWTurnAt && now - gMSWTurnAt > 0.8) {
        gMSWTurnAt = 0;
        DMMSWDropContent();
        DMMSWBuild(NO);
        DMLog([NSString stringWithFormat:@"[macswitcher] the screen has turned: laid out again (%lu windows, root %@)", (unsigned long)gMSWTiles.count, NSStringFromCGSize(gMSWBuiltSize)]);
    }
}
// The screen went off (StatusBar.x, DMCloseOverlaysForScreenOff).
static void DMMSWScreenOff(void) { if (DMMSWIsOpen()) { DMLog(@"[macswitcher] the screen went off: closed"); DMMSWClose(nil, NO); } }

// ---- iPadOS's own App Switcher, on purpose (Apple menu > Show App Switcher) ----
// iPadOS 15: SBMainSwitcherViewController -toggleMainSwitcherNoninteractivelyWithSource:animated:; 16: the coordinator's per-scene call. Only
// opened when no switcher is showing (it is a toggle). YES when it was asked.
static BOOL DMMSWAppSwitcherAvailable(void) {
    if (DMMSWHasMethod(objc_getClass("SBMainSwitcherViewController"), @"toggleMainSwitcherNoninteractivelyWithSource:animated:", @"B@:qB")) return YES;
    return DMMSWHasMethod(objc_getClass("SBMainSwitcherControllerCoordinator"), @"toggleMainSwitcherNoninteractivelyWithSource:animated:windowScene:", @"B@:qB@");
}
static BOOL DMMSWShowAppSwitcher(void) {
    if (DMSwitcherVisible()) { DMLog(@"[macswitcher] Show App Switcher: it is already showing"); return NO; }
    // (this once, the Mac Switcher stays on: the takeovers stand aside until it has gone -- DMMSWStockOnce, above; set before the request, so a
    //  gesture or press already under way while it opens is iPadOS's too)
    if (DMMSWIsOpen()) DMMSWClose(nil, NO);   // (a window dropped onto another desktop still landing finishes first, DMMSWDropContent)
    gMSWStockAskedAt = CACurrentMediaTime(); gMSWStockSeen = NO; gMSWStockGoneTicks = 0;
    DM_FEATURE_MARK("mac-switcher-stock-once");
    DMLog(@"[macswitcher] Show App Switcher: iPadOS's own switcher this once, the Mac Switcher stays on");
    BOOL ok = NO;
    @try {
        Class vc = objc_getClass("SBMainSwitcherViewController");
        if (DMMSWHasMethod(vc, @"toggleMainSwitcherNoninteractivelyWithSource:animated:", @"B@:qB")) {
            id c = DMSwitcherController();
            if ([c isKindOfClass:vc]) ok = ((BOOL (*)(id, SEL, long long, BOOL))objc_msgSend)(c, NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:animated:"), 1, YES);
        } else if (DMMSWHasMethod(objc_getClass("SBMainSwitcherControllerCoordinator"), @"toggleMainSwitcherNoninteractivelyWithSource:animated:windowScene:", @"B@:qB@")) {
            id co = DMSwitcherController();
            id scene = DMStatusBarWindow().windowScene;
            if ([co isKindOfClass:objc_getClass("SBMainSwitcherControllerCoordinator")] && [scene isKindOfClass:[UIWindowScene class]])
                ok = ((BOOL (*)(id, SEL, long long, BOOL, id))objc_msgSend)(co, NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:animated:windowScene:"), 1, YES, scene);
        }
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] Show App Switcher failed: %@", e]); ok = NO; }
    DMLog([NSString stringWithFormat:@"[macswitcher] Show App Switcher: %@", ok ? @"asked" : @"not possible here"]);
    if (!ok) DMMSWStockEnd(@"was not asked for");
    return ok;
}

// ---- iPadOS's own App Switcher never comes by another way while the Mac Switcher is on (audit M-4) ----
// The gestures and the Home button's double press are taken over at their source (above; MacSwitcherButton.h). Every other way asks SpringBoard's
// switcher controller directly: AssistiveTouch's App Switcher (its menu or a custom action), Back Tap, Voice Control's "Open App Switcher" and
// Switch Control (through the accessibility server, -[AXSpringBoardServerHelper openAppSwitcherWithServerInstance:]) and the keyboard's shortcut
// (-[SpringBoard _handleOpenAppSwitcherShortcut:], Globe-Up). They end in the controller's noninteractive toggle / activate -- iPadOS 15:
// SBMainSwitcherViewController's; 16 / 17: SBMainSwitcherControllerCoordinator's and the per-display SBSwitcherController's toggle --, taken over
// here: the Mac Switcher opens instead (or closes, as a second press of the same key does). They go through unchanged with the Mac Switcher off,
// while iPadOS's switcher asked for from the Apple menu is on its way or up (DMMSWStockOnce: the one deliberate way in), while a switcher shows
// already (a toggle then closes it, as always) and on the Lock Screen.
#if DEBUG
static NSString *DMMSWProbeStackN(int n);   // (debug, below)
#endif
static BOOL DMMSWGesturesOn(void);   // (the gestures section: the switch on, not on the Lock Screen, not iPadOS's switcher this once)
static BOOL DMMSWStockAskTakenOver(NSString *how) {
    if (!DMMSWGesturesOn() || DMSwitcherVisible()) return NO;
    DM_FEATURE_MARK("mac-switcher-stock-paths");
#if DEBUG
    DMLog([NSString stringWithFormat:@"[macswitcher] %@: the Mac Switcher instead of iPadOS's App Switcher%@", how, DMTestFlag("/tmp/msw-wsprobe") ? DMMSWProbeStackN(12) : @""]);
#endif
    NSString *h = [how copy];
    dispatch_async(dispatch_get_main_queue(), ^{ DMMSWOpen(h); });   // (after the caller's own handling: a toggle, as the Home button's double press)
    return YES;
}
static BOOL (*o_MSWSwToggle)(id, SEL, long long, BOOL), (*o_MSWSwActivate)(id, SEL, long long, BOOL), (*o_MSWSwToggleScene)(id, SEL, long long, BOOL, id);
static BOOL (*o_MSWSwToggleDisplay)(id, SEL, long long, BOOL), (*o_MSWSwActivateCo)(id, SEL, long long, BOOL);
static BOOL DMMSWSwToggle(id self, SEL _cmd, long long source, BOOL animated) { return DMMSWStockAskTakenOver([NSString stringWithFormat:@"the App Switcher asked for (toggle, source %lld)", source]) || o_MSWSwToggle(self, _cmd, source, animated); }
static BOOL DMMSWSwActivate(id self, SEL _cmd, long long source, BOOL animated) { return DMMSWStockAskTakenOver([NSString stringWithFormat:@"the App Switcher asked for (activate, source %lld)", source]) || o_MSWSwActivate(self, _cmd, source, animated); }
static BOOL DMMSWSwToggleScene(id self, SEL _cmd, long long source, BOOL animated, id scene) { return DMMSWStockAskTakenOver([NSString stringWithFormat:@"the App Switcher asked for (toggle, source %lld)", source]) || o_MSWSwToggleScene(self, _cmd, source, animated, scene); }
static BOOL DMMSWSwToggleDisplay(id self, SEL _cmd, long long source, BOOL animated) { return DMMSWStockAskTakenOver([NSString stringWithFormat:@"the App Switcher asked for (a display's toggle, source %lld)", source]) || o_MSWSwToggleDisplay(self, _cmd, source, animated); }
static BOOL DMMSWSwActivateCo(id self, SEL _cmd, long long source, BOOL animated) { return DMMSWStockAskTakenOver([NSString stringWithFormat:@"the App Switcher asked for (activate, source %lld)", source]) || o_MSWSwActivateCo(self, _cmd, source, animated); }
static NSString *gMSWDiagStock = @"-";   // (which of them were hooked: the diagnostic record)
static void DMMSWHookStockPaths(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class vc = objc_getClass("SBMainSwitcherViewController"), co = objc_getClass("SBMainSwitcherControllerCoordinator"), sc = objc_getClass("SBSwitcherController");
    NSMutableArray *in = [NSMutableArray array];
    if (DMMSWHasMethod(vc, @"toggleMainSwitcherNoninteractivelyWithSource:animated:", @"B@:qB")) { MSHookMessageEx(vc, NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:animated:"), (IMP)DMMSWSwToggle, (IMP *)&o_MSWSwToggle); [in addObject:@"vc-toggle"]; }
    if (DMMSWHasMethod(vc, @"activateMainSwitcherNoninteractivelyWithSource:animated:", @"B@:qB")) { MSHookMessageEx(vc, NSSelectorFromString(@"activateMainSwitcherNoninteractivelyWithSource:animated:"), (IMP)DMMSWSwActivate, (IMP *)&o_MSWSwActivate); [in addObject:@"vc-activate"]; }
    if (DMMSWHasMethod(co, @"toggleMainSwitcherNoninteractivelyWithSource:animated:windowScene:", @"B@:qB@")) { MSHookMessageEx(co, NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:animated:windowScene:"), (IMP)DMMSWSwToggleScene, (IMP *)&o_MSWSwToggleScene); [in addObject:@"co-toggle"]; }
    if (DMMSWHasMethod(co, @"activateMainSwitcherNoninteractivelyWithSource:animated:", @"B@:qB")) { MSHookMessageEx(co, NSSelectorFromString(@"activateMainSwitcherNoninteractivelyWithSource:animated:"), (IMP)DMMSWSwActivateCo, (IMP *)&o_MSWSwActivateCo); [in addObject:@"co-activate"]; }
    if (DMMSWHasMethod(sc, @"toggleMainSwitcherNoninteractivelyWithSource:animated:", @"B@:qB")) { MSHookMessageEx(sc, NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:animated:"), (IMP)DMMSWSwToggleDisplay, (IMP *)&o_MSWSwToggleDisplay); [in addObject:@"sc-toggle"]; }
    gMSWDiagStock = in.count ? [in componentsJoinedByString:@"+"] : @"none";
    DMLog([NSString stringWithFormat:@"[macswitcher] iPadOS's App Switcher asked for directly (accessibility, keyboard): %@", in.count ? [NSString stringWithFormat:@"the Mac Switcher instead (%@)", gMSWDiagStock] : @"no switcher toggle of the expected kind here -- those ways stay iPadOS's"]);
}

// ---- keys: Esc closes (SpringBoard's own key handler: UIKeyCommands in its windows never fire, see NativeWindow.h) ----
static void (*o_MSWPressesBegan)(id, SEL, NSSet *, UIPressesEvent *);
static void DMMSWPressesBegan(id self, SEL _cmd, NSSet<UIPress *> *presses, UIPressesEvent *event) {
    static BOOL inside = NO;
#if DEBUG
    if (DMTestFlag("/tmp/msw-keylog")) for (UIPress *p in presses) DMLog([NSString stringWithFormat:@"[mswkey] SpringBoard press: key 0x%lx modifiers 0x%llx \"%@\" (view open %d)", (long)p.key.keyCode, (unsigned long long)p.key.modifierFlags, p.key.charactersIgnoringModifiers, gMSWOpen]);
#endif
    if (!inside && gMSWOpen && !gMSWClosing) {
        inside = YES;
        BOOL esc = NO;
        for (UIPress *p in presses) if (p.key.keyCode == UIKeyboardHIDUsageKeyboardEscape) esc = YES;
        if (esc) DMLog(@"[macswitcher] Esc: closed");
        if (esc) DMMSWClose(nil, YES);
        inside = NO;
        if (esc) return;
    }
    o_MSWPressesBegan(self, _cmd, presses, event);
}
// ---- Control-arrows, as on a Mac (a hardware keyboard): Control-Left / Control-Right bring the desktop on that side with the same slide -- pressed
// while a slide runs, it goes on from where it is (DMMSWSideRequest) --, Control-Up opens the Mac Switcher (pressed again: closes it, as Mission
// Control's key does). They are key commands of SpringBoard's own, next to its system shortcuts (-[SpringBoard keyCommands]: Command-Tab,
// Command-Space, Globe-H ...). Left / Right only while there is more than one desktop (with one, the keys stay the app's: a terminal's word
// jumps, a text field's line start / end); Up while the Mac Switcher is on. None while iPadOS's own switcher is asked for from the Apple menu, on
// the Lock Screen, or with the Mac Switcher off.
static NSArray *(*o_MSWKeyCommands)(id, SEL);
static NSArray<UIKeyCommand *> *gMSWKeyCmds;   // Control-Left, Control-Right, Control-Up
// What the key commands offer now: 0 none, 1 Control-Up, 2 all three. One answer for SpringBoard's -keyCommands (DMMSWKeyCommands) and the
// registration refresh (DMMSWKeysRefresh): none while iPadOS's own switcher is up by a way the Mac Switcher did not take over -- e.g. opened during
// a Guided Access session that has ended since: a Control-arrow switched the desktops under it (1.4 logic test); the hook still listed the arrows
// then and a re-registration by UIKit delivered one (the re-check). DMMSWOpen stands aside the same way.
static int DMMSWKeysWanted(void) {
    if (!DMMSWGesturesOn() || (DMSwitcherVisible() && !DMMSWGestureGrace())) return 0;
    return DMMSWMulti() ? 2 : 1;
}
static NSArray *DMMSWKeyCommands(id self, SEL _cmd) {
    NSArray *orig = o_MSWKeyCommands(self, _cmd);
    int want = gMSWKeyCmds.count == 3 ? DMMSWKeysWanted() : 0;
    if (!want) return orig;
    NSMutableArray *all = [NSMutableArray arrayWithArray:[orig isKindOfClass:[NSArray class]] ? orig : @[]];
    if (want == 2) { [all addObject:gMSWKeyCmds[0]]; [all addObject:gMSWKeyCmds[1]]; }
    [all addObject:gMSWKeyCmds[2]];
    return all;
}
// SpringBoard gets the keys its key commands name, whichever app has the keyboard, because UIKit registers that list with backboardd
// (-[UIApplication _updateSerializableKeyCommandsForResponder:], read on the M1: the responder chain's key commands -> BKSHIDEventKeyCommandsRegistration
// per deferring environment, -registerKeyCommands:) -- only when its first responder changes. So the list stayed as it was registered: back to one
// desktop, Control-Left / Control-Right still went to SpringBoard and no app got them (M1 7 Oct). When what we offer changes (DMMSWTick, 4 times a
// second: the desktops, the switch, the Lock Screen, iPadOS's switcher this once) the registration is made again (a nil responder: always).
static int gMSWKeysOffered = -1;   // (0 none, 1 Control-Up, 2 all three)
static void DMMSWKeysRefresh(void) {
    if (gMSWKeyCmds.count != 3) return;
    int want = DMMSWKeysWanted();
    if (want == gMSWKeysOffered) return;
    gMSWKeysOffered = want;   // (also the first look: the hook may have come after UIKit's first registration at start)
    UIApplication *app = [UIApplication sharedApplication];
    SEL upd = NSSelectorFromString(@"_updateSerializableKeyCommandsForResponder:");
    if (!DMMSWHasMethod(object_getClass(app), @"_updateSerializableKeyCommandsForResponder:", @"v@:@")) return;
    @try { ((void (*)(id, SEL, id))objc_msgSend)(app, upd, nil); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] the key commands' registration refused: %@", e.reason]); return; }
    DMLog([NSString stringWithFormat:@"[macswitcher] key commands registered again: %@", want == 2 ? @"Control-Left / Control-Right / Control-Up" : want == 1 ? @"Control-Up" : @"none"]);
}
static void DMMSWControlKey(id self, SEL _cmd, id sender) {
    NSString *name = NSStringFromSelector(_cmd);
    NSInteger side = [name isEqualToString:@"dm_mswControlLeft:"] ? -1 : [name isEqualToString:@"dm_mswControlRight:"] ? 1 : 0;
    NSString *key = side < 0 ? @"Control-Left" : side > 0 ? @"Control-Right" : @"Control-Up";
    if (!DMMSWGesturesOn()) return;
    if (DMSwitcherVisible() && !DMMSWGestureGrace()) { DMLog([NSString stringWithFormat:@"[macswitcher] %@: iPadOS's App Switcher is up -- nothing switches under it", key]); return; }
    DM_FEATURE_MARK("mac-switcher-control-keys");
    if (!side) { DMLog(@"[macswitcher] Control-Up: the Mac Switcher"); DMMSWOpen(@"Control-Up"); return; }
    if (!DMMSWMulti()) return;
    if (gMSWOpen && gMSWSwitching) return;   // (the view is fading over a slide already)
    DMMSWSideRequest(side, 0, side < 0 ? @"Control-Left" : @"Control-Right");
}
static void DMMSWHookKeys(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class sb = objc_getClass("SpringBoard");
    if (DMMSWHasMethod(sb, @"pressesBegan:withEvent:", @"v@:@@")) MSHookMessageEx(sb, @selector(pressesBegan:withEvent:), (IMP)DMMSWPressesBegan, (IMP *)&o_MSWPressesBegan);
    else DMLog(@"[macswitcher] SpringBoard's key handler differs: Esc is not hooked");
    if (DMMSWHasMethod(sb, @"keyCommands", @"@@:")) {
        NSArray *sels = @[@"dm_mswControlLeft:", @"dm_mswControlRight:", @"dm_mswControlUp:"], *inputs = @[UIKeyInputLeftArrow, UIKeyInputRightArrow, UIKeyInputUpArrow];
        NSMutableArray *cmds = [NSMutableArray array];
        for (NSUInteger i = 0; i < sels.count; i++) {
            class_addMethod(sb, NSSelectorFromString(sels[i]), (IMP)DMMSWControlKey, "v@:@");
            UIKeyCommand *c = [UIKeyCommand keyCommandWithInput:inputs[i] modifierFlags:UIKeyModifierControl action:NSSelectorFromString(sels[i])];
            SEL prio = NSSelectorFromString(@"setWantsPriorityOverSystemBehavior:");   // (iPadOS 15+: before a text field's own arrow handling)
            if ([c respondsToSelector:prio]) ((void (*)(id, SEL, BOOL))objc_msgSend)(c, prio, YES);
            if (c) [cmds addObject:c];
        }
        gMSWKeyCmds = cmds;
        MSHookMessageEx(sb, @selector(keyCommands), (IMP)DMMSWKeyCommands, (IMP *)&o_MSWKeyCommands);
        DMLog(@"[macswitcher] Control-Left / Control-Right / Control-Up: SpringBoard's key commands");
    } else DMLog(@"[macswitcher] SpringBoard has no key commands of its own here: no Control-arrows");
}

// ==== the gestures ====
// SpringBoard decides what a bottom-edge swipe, a four-finger swipe and a trackpad swipe mean -- all one pipeline, the probes below showed --
// through SBHomeGestureSwitcherModifier (destination 0 stay, 1 previous app, 2 next app, 3 App Switcher, 4 Home). Two things make a difference
// (found by reading SpringBoard on this device, 3 Oct; round 1 only touched the lift-off and so the App Switcher still flew in and a side swipe
// still switched apps):
//  1. The stock App Switcher's cards fly in DURING the hold, before any lift-off hook can act. They are started from the modifier's own display
//     link / multitasking-start, both gated by -_hasPausedEnoughForFlyIn. So, while the feature is on, that returns NO and no stock card ever
//     spreads. The destination the gesture ends at is computed by a SEPARATE object (SBHomeGestureFinalDestinationSwitcherModifier) and still
//     reaches 3, which we act on.
//  2. A destination becomes an action in ONE place: -[SBHomeGestureSwitcherModifier _responseForActivatingFinalDestination:], which builds the
//     SBSwitcherTransitionRequest -- the App Switcher for 3, the PREVIOUS/NEXT APP'S LAYOUT for 1/2 (so a side swipe switches apps through the
//     request's app layout, not its environment mode: rewriting the mode alone, as round 1 did, left the app switch in place). Here that method
//     is given 0 (stay on the current layout: the app returns to where it was) for the destinations we take over, so SpringBoard never opens its
//     App Switcher and never switches app, and our own view / desktop slide runs instead.
//  - 3 (App Switcher): our Mac Switcher opens;
//  - 1 / 2 (side swipe) with more than one desktop: the desktop on that side slides in (none on that side: nothing happens); with one desktop,
//    the stock previous / next app, untouched;
//  - 0 and 4 (Home) are never touched; Control Center, Notification Center, Reachability and Slide Over are other recognisers, never here.
// Kill switch: the Settings switch is asked for every gesture (and, in debug builds only, the test flag /tmp/msb-noswitcher, DMTestFlag): off,
// SpringBoard's own behaviour goes through unchanged.
static CFTimeInterval gMSWTookOverAt = 0;   // (a gesture was just taken over: the completion safety net watches for a moment afterwards)
static __weak id gMSWHomeMod;               // (the gesture's home gesture modifier: SpringBoard's live final destination, for the tracker)
static BOOL gMSWTrackEnding = NO;          // (the followed gesture is ending: its lift-off activation is ours, "stay")
// (and while iPadOS's own App Switcher asked for from the Apple menu is opening or up: its swipes, holds and lifts are iPadOS's, DMMSWStockOnce)
// (a Guided Access session too: it keeps the iPad in one app and stops SpringBoard's own ways out -- its gestures, switcher, Home -- but knows
//  nothing of ours: the Mac Switcher's hold, side swipe, Control-arrows and the App Switcher paths it takes over stand aside, so the gestures are
//  SpringBoard's again, which Guided Access holds back. 1.3.7, audit M-7)
static BOOL DMMSWGesturesOn(void) { return gMSWOn && !DMTestFlag("/tmp/msb-noswitcher") && !DMCoverSheetShown() && !DMMSWStockOnce() && !MSBDGuidedAccessActive(); }
// Root cause 1: the stock fly-in during the hold. While the feature is on, SpringBoard is told the finger never paused enough to fly its cards in.
static BOOL (*o_MSWFlyIn)(id, SEL);
static BOOL DMMSWFlyIn(id self, SEL _cmd) { gMSWHomeMod = self; return DMMSWGesturesOn() ? NO : o_MSWFlyIn(self, _cmd); }
// Root cause 2: the one place a final destination becomes a transition request. The taken-over destinations are given 0 (stay); our action runs.
// With Reduce Motion on, SpringBoard runs the home gesture through SBReduceMotionHomeGestureSwitcherModifier instead (iPad 2, 16.7.7: Reduce Motion
// is on there, the hooks above never ran, and the stock App Switcher came up on a hold): its own -_responseForActivatingFinalDestination: (no
// fly-in there: the gesture goes to the App Switcher the moment it pauses) is taken over the same way, by the same code.
static id (*o_MSWActivate)(id, SEL, long long), (*o_MSWActivateRM)(id, SEL, long long);
static id DMMSWActivateWith(id self, SEL _cmd, long long dest, id (*orig)(id, SEL, long long));
static id DMMSWActivate(id self, SEL _cmd, long long dest) { return DMMSWActivateWith(self, _cmd, dest, o_MSWActivate); }
static id DMMSWActivateRM(id self, SEL _cmd, long long dest) { return DMMSWActivateWith(self, _cmd, dest, o_MSWActivateRM); }
// The gesture's final destination as the modifier has it (its -currentFinalDestination, checked), or -1.
static long long DMMSWFinalDestinationOf(id modifier) {
    return modifier && DMMSWHasMethod(object_getClass(modifier), @"currentFinalDestination", @"q@:") ? ((long long (*)(id, SEL))objc_msgSend)(modifier, NSSelectorFromString(@"currentFinalDestination")) : -1;
}
// Which way the fingers went, read as a Mac reads a swipe between desktops: from SpringBoard's own judgement of the gesture's sideways motion, its
// final destination. SpringBoard makes it previous (1) when the motion went left (negative x velocity -- or translation, for a low arc) and next
// (2) when it went right, the other way round with a right-to-left language (read in -[SBHomeGestureFinalDestinationSwitcherModifier] on 15.6.1;
// measured on the M1: the bottom edge, four fingers and the trackpad's three, with and without Reduce Motion, all 1 = left; iPad 2: 1 = left).
// The modifier's _translation is no source: it is how far SpringBoard's card follows the fingers, and it stays 0 when no card can follow that way
// (measured: every swipe to the left that starts on the Home Screen, bottom edge, four fingers and trackpad alike) -- read as travel, a 0 said
// "not to the right" whichever way the fingers went, and was right only where it happened to fall on a swipe to the left.
static BOOL DMMSWFingersWentRight(id modifier, long long dest) {
    BOOL rtl = NO;
    if (modifier && DMMSWHasMethod(object_getClass(modifier), @"isRTLEnabled", @"B@:")) rtl = ((BOOL (*)(id, SEL))objc_msgSend)(modifier, NSSelectorFromString(@"isRTLEnabled"));
    else rtl = [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    return (dest == 2) != rtl;
}
#if DEBUG
// The card's sideways offset of the gesture (the modifier's _translation, read where it is a CGPoint), or NAN -- debug probe only (0 when no card follows).
static CGFloat DMMSWGestureTravelX(id modifier) {
    Ivar iv = modifier ? class_getInstanceVariable(object_getClass(modifier), "_translation") : NULL;
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!t || strncmp(t, "{CGPoint", 8) != 0) return NAN;
    CGPoint p; memcpy(&p, (const char *)(__bridge const void *)modifier + ivar_getOffset(iv), sizeof p);
    return isfinite(p.x) ? p.x : NAN;
}
#endif
// ---- the side swipe follows the fingers (the Spaces slide's tracker) ----
// With more than one desktop, every bottom-edge, four-finger and trackpad gesture is watched from its start, through the gesture manager's
// -fluidSwitcherGestureTransaction:didBeginGesture: / didUpdateGesture: / didEndGesture:, whose SBFluidSwitcherGesture carries the event SpringBoard
// itself reads: the fingers' translation and velocity in its switcher's view (the screen as the user sees it), touch and trackpad alike.
//  - it begins: the screen's picture is taken -- the left desktop for the slide, before SpringBoard has moved anything;
//  - the fingers go sideways (more sideways than up, past a few points; or SpringBoard already reads a side swipe): the slide comes up from that
//    point, without a jump, and follows them 1:1; from then on SpringBoard is not told the gesture's updates (its own response, the card that
//    follows the finger, stays where it was, under the slide);
//  - at an outer desktop the slide gives way with resistance (a rubber band) and goes back;
//  - the fingers lift: past half a screen, or a flick that way -- the switch, at the fingers' speed (DMMSWSwitchRun); else back. SpringBoard is told
//    "stay" (DMMSWActivateWith), whatever it would have done.
// A gesture that goes up instead (Home, a hold for the Mac Switcher) is never touched; its picture serves a switch or the view that follows it.
// Nothing is watched with one desktop, with Reduce Motion (a cross-fade at the lift instead), while the view is open, or with /tmp/msw-notrack
// (a test flag, debug builds only: the side swipe then slides at the lift, as before).
static UIView *gMSWTrackPic;             // the picture taken when the gesture began
static CGPoint gMSWTrackStart;           // the gesture's translation then
static CGFloat gMSWTrackZero = 0;        // its x when the slide came up (the slide starts there, at no offset)
static CGFloat gMSWTrackV = 0;           // the fingers' x speed, last seen (points per second)
static CGFloat gMSWTrackLastX = NAN; static CFTimeInterval gMSWTrackMovedAt = 0;   // (where and when the fingers last moved)
static CFTimeInterval gMSWTrackAt = 0, gMSWTrackSince = 0;   // the last event; when the slide came up
static double gMSWTrackArmMs = 0;        // (what the picture at the gesture's start cost SpringBoard's main thread, for the log)
static __weak id gMSWTrackGesture;       // the gesture followed
static SEL sMSWGestureEvent, sMSWTranslation, sMSWVelocity, sMSWType;
// The fingers' translation and velocity, as SpringBoard's gesture has them (its event; each class checked once). NO: this SpringBoard has none.
static BOOL DMMSWGestureMotion(id gesture, CGPoint *tr, CGPoint *ve) {
    static Class gc = Nil, ec = Nil;
    static BOOL gok = NO, tok = NO, vok = NO;
    if (!gesture) return NO;
    if (!sMSWGestureEvent) { sMSWGestureEvent = NSSelectorFromString(@"gestureEvent"); sMSWTranslation = NSSelectorFromString(@"translationInContainerView"); sMSWVelocity = NSSelectorFromString(@"velocityInContainerView"); sMSWType = NSSelectorFromString(@"type"); }
    if (object_getClass(gesture) != gc) { gc = object_getClass(gesture); gok = DMMSWHasMethod(gc, @"gestureEvent", @"@@:"); }
    id ev = gok ? ((id (*)(id, SEL))objc_msgSend)(gesture, sMSWGestureEvent) : nil;
    if (!ev) return NO;
    if (object_getClass(ev) != ec) {
        ec = object_getClass(ev);
        tok = DMMSWHasMethod(ec, @"translationInContainerView", @"{CGPoint=dd}@:"); vok = DMMSWHasMethod(ec, @"velocityInContainerView", @"{CGPoint=dd}@:");
        DMLog([NSString stringWithFormat:@"[macswitcher] gesture event %@: translation %d, velocity %d", NSStringFromClass(ec), tok, vok]);
    }
    if (!tok) return NO;
    *tr = ((CGPoint (*)(id, SEL))objc_msgSend)(ev, sMSWTranslation);
    if (ve) *ve = vok ? ((CGPoint (*)(id, SEL))objc_msgSend)(ev, sMSWVelocity) : CGPointMake(NAN, NAN);
    return isfinite(tr->x) && isfinite(tr->y);
}
static long long DMMSWGestureTypeOf(id gesture) {   // (1: the bottom edge, four fingers and the trackpad's swipes -- every one of ours)
    static Class gc = Nil; static BOOL ok = NO;
    if (!gesture) return -1;
    if (object_getClass(gesture) != gc) { gc = object_getClass(gesture); ok = DMMSWHasMethod(gc, @"type", @"q@:"); }
    if (!sMSWType) sMSWType = NSSelectorFromString(@"type");
    return ok ? ((long long (*)(id, SEL))objc_msgSend)(gesture, sMSWType) : -1;
}
static BOOL DMMSWGestureAlive(id gesture) {   // (still held: its state is not ended / cancelled / failed, when it says)
    static Class gc = Nil; static BOOL ok = NO;
    if (!gesture) return NO;
    if (object_getClass(gesture) != gc) { gc = object_getClass(gesture); ok = DMMSWHasMethod(gc, @"state", @"q@:"); }
    if (!ok) return YES;
    long long st = ((long long (*)(id, SEL))objc_msgSend)(gesture, NSSelectorFromString(@"state"));
    return st < 3;
}
static CGFloat DMMSWRubber(CGFloat a, CGFloat d) { return (1.0 - 1.0 / (a * 0.55 / d + 1.0)) * d; }   // (UIKit's rubber band: gives less and less)
// The slide's offset for the fingers' travel since it came up: 1:1 towards a desktop that is there; with resistance where there is none, and past
// a whole screen.
static CGFloat DMMSWTrackOffset(CGFloat raw) {
    CGFloat W = gMSWSlW > 1.0 ? gMSWSlW : [UIScreen mainScreen].bounds.size.width, a = fabs(raw), o;
    BOOL has = raw > 0 ? gMSWSlSide[0] != nil : gMSWSlSide[1] != nil;   // (the strip moving right shows the desktop on the left)
    if (!has) o = DMMSWRubber(a, W * 0.25);
    else o = a <= W ? a : W + DMMSWRubber(a - W, W * 0.25);
    return raw < 0 ? -o : o;
}
static void DMMSWTrackSpeed(CGPoint ve) { if (isfinite(ve.x)) gMSWTrackV = ve.x; }
static void DMMSWTrackMoved(CGPoint tr) { if (!isfinite(gMSWTrackLastX) || fabs(tr.x - gMSWTrackLastX) > 0.01) { gMSWTrackLastX = tr.x; gMSWTrackMovedAt = CACurrentMediaTime(); } }
// The fingers' speed at the lift. A finger that rests sends no updates (SpringBoard's recognisers report no still touches), so the last speed seen
// is stale after a pause: measured on the M1, a drag that stopped 150 ms before the lift still said 531 pt/s and counted as a flick. So the speed
// fades to nothing 20-50 ms after the last movement, as a finger's does.
static CGFloat DMMSWTrackLiftSpeed(void) {
    double idle = CACurrentMediaTime() - gMSWTrackMovedAt;
    if (gMSWTrackMovedAt <= 0 || idle >= 0.05) return 0;
    return idle <= 0.02 ? gMSWTrackV : gMSWTrackV * (0.05 - idle) / 0.03;
}
static void DMMSWTrackDisarm(void);
#if DEBUG
static void DMMSWRecEvent(id gesture, NSString *tag);   // (the frame recording, at the end of this file)
static void DMMSWRecordEvent(id gesture, NSString *tag) { DMMSWRecEvent(gesture, tag); }
#else
static inline void DMMSWRecordEvent(id gesture, NSString *tag) {}
#endif
// ---- a side swipe made while a slide runs takes it (as on a Mac): the slide stops under the fingers where it is and follows them from there, over
// the desktops on either side; at the lift it goes on to the desktop the fingers chose (the nearest one, or the next one a flick points to) -- the
// running switch's new aim (DMMSWSwAim), its windows changing under it as for a redirect. Only a switch that can be redirected (DMMSWSwRedirect's
// rules) and a strip that holds the desktops in their order (a switch from the strip to a desktop further away does not: its side swipe comes at the
// lift, DMMSWSideRequest). ----
static BOOL gMSWTrackGrab = NO;       // (the followed gesture took a running slide)
static CGFloat gMSWTrackGrabBase = 0; // (the slide's offset when the fingers took it)
static BOOL DMMSWSlInOrder(void) {    // (every picture on the strip is the desktop k places from the left one's)
    for (NSNumber *k in gMSWSlPlaces) if (gMSWSlPlaces[k].integerValue != (NSInteger)gMSWSwFrom + k.integerValue) return NO;
    return gMSWSlPlaces.count > 0;
}
static BOOL DMMSWGrabbable(void) {   // (Stage Manager's switch: its own aim, MacSwitcherSM.h DMMSWSMCanTake)
    return gMSWSwitching && gMSWSlRoot && gMSWSlStrip && (DMSMEngine() ? DMMSWSMCanTake() : (gMSWSwRedirectable && !gMSWSwRevealing)) && !gMSWSlSpFade && !MSBReduceMotion() && !gMSWOpen
        && DMMSWMulti() && DMMSWGesturesOn() && DMMSWSlInOrder() && !DMTestFlag("/tmp/msw-notrack") && !DMTestFlag("/tmp/msw-nograb");
}
// The offset for the fingers on a taken slide: 1:1 between the outer desktops, with resistance past them.
static CGFloat DMMSWGrabOffset(CGFloat raw) {
    CGFloat W = gMSWSlW > 1.0 ? gMSWSlW : [UIScreen mainScreen].bounds.size.width;
    CGFloat hi = gMSWSwFrom * W, lo = -((CGFloat)gMSWDesks.count - 1.0 - gMSWSwFrom) * W;   // (the first desktop's offset, the last one's)
    if (raw > hi) return hi + DMMSWRubber(raw - hi, W * 0.25);
    if (raw < lo) return lo - DMMSWRubber(lo - raw, W * 0.25);
    return raw;
}
static void DMMSWGrabPictures(CGFloat o) {   // (the pictures around where the slide is: a desktop the fingers may bring into view)
    CGFloat W = gMSWSlW > 1.0 ? gMSWSlW : 1.0;
    NSInteger k = (NSInteger)floor(-o / W);
    for (NSInteger j = k - 1; j <= k + 2; j++) { NSInteger place = (NSInteger)gMSWSwFrom + j; if (place >= 0 && place < (NSInteger)gMSWDesks.count) DMMSWSlEnsurePic(j, (NSUInteger)place); }
}
// The fingers take the running slide (the gesture went sideways): it stops where it is; the aim it had is given up (its landing, change and reveal
// do nothing; the windows stay where its change, if any, put them).
static BOOL DMMSWTrackGrabEngage(CGFloat x) {
    if (!DMMSWGrabbable()) return NO;
    CGFloat o = DMMSWSlOffsetNow();
    [gMSWSlStrip.layer removeAnimationForKey:@"msw.slide"]; [gMSWSlStrip.layer removeAnimationForKey:@"msw.catch"];
    gMSWSlFinGen++; gMSWSlSpT0 = 0;
    if (DMSMEngine()) DMMSWSMTaken(); else { gMSWSwGen++; gMSWSwLanded = NO; }
    gMSWTrackGrabBase = o; gMSWTrackZero = gMSWTrackStart.x; gMSWTrack = 2; gMSWTrackSince = CACurrentMediaTime();
    // (SpringBoard reads the first sideways motion late -- its first update carries 20-70 pt --: the slide takes the whole travel at once and an
    //  additive animation takes that much back over 0.15 s, as when a slide comes up, so it neither jumps nor lags the fingers)
    CGFloat travel = x - gMSWTrackZero, to = DMMSWGrabOffset(o + travel);
    DMMSWGrabPictures(to);
    DMMSWSlSetOffset(to);
    if (fabs(to - o) > 0.5) {
        CABasicAnimation *c = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        c.additive = YES; c.fromValue = @(o - to); c.toValue = @0; c.duration = 0.15;
        c.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [gMSWSlStrip.layer addAnimation:c forKey:@"msw.catch"];
    }
    DM_FEATURE_MARK("mac-switcher-take-slide");
    DMMSWMark([NSString stringWithFormat:@"slide taken by the fingers at %.0f pt", o]);
    DMLog([NSString stringWithFormat:@"[macswitcher] side swipe while the slide runs: the fingers take it at %.0f pt (it was going to %@, the windows are on %@)", o, DMMSWDeskName(DMSMEngine() ? DMMSWSMAimPlace() : gMSWSwTo), DMMSWDeskName(gMSWCur)]);
    return YES;
}
// Where a taken slide goes at the lift: the nearest desktop, or the next one the way a flick points (450 pt/s and more), never past the outer ones.
static NSInteger DMMSWGrabDecide(CGFloat o, CGFloat v) {
    return (NSInteger)DMMSWGrabSlot(o, gMSWSlW, v, -(long)gMSWSwFrom, (long)gMSWDesks.count - 1 - (long)gMSWSwFrom);   // (MSWSlideMath.h)
}
static void DMMSWGrabFinish(NSInteger k, CGFloat v) {
    gMSWTrackGrab = NO; gMSWTrackPic = nil; gMSWTrackGesture = nil;
    if (DMSMEngine()) { DMMSWSMTakenLift(k, v); return; }   // (Stage Manager's switch: its own aim)
    NSUInteger place = (NSUInteger)((NSInteger)gMSWSwFrom + k);
    if (place >= gMSWDesks.count || !DMMSWSlEnsurePic(k, place)) { k = 0; place = gMSWSwFrom; }
    gMSWSwTo = place; gMSWSwToSlot = k; gMSWSwLanded = NO; gMSWSwRedirects++;
    DMMSWMark([NSString stringWithFormat:@"lifted (a taken slide): to %@ (slot %+ld, %.0f pt/s)", DMMSWDeskName(place), (long)k, v]);
    gMSWSlMaxAway = 3000.0; DMMSWSwAim(v, NO); gMSWSlMaxAway = 900.0;
}
// The view a gesture can open (the hold) shows the desktop it left -- and "+" or a tap in its strip slides that desktop away and keeps that picture
// as its thumbnail. Its picture is the screen as it was when the gesture began, before SpringBoard moved anything (DMMSWOpen's "lift"): the screen
// once the hold has ended is SpringBoard's own return still on screen (iPadOS 15: the Home Screen zoomed out, the app's card shrunk). With more than
// one desktop the tracker takes that picture; with one desktop, or with Reduce Motion, nothing did, so the first trip back to a desktop left by "+"
// slid in the zoomed Home Screen and faded it into the real one (K-1, M1 8 Oct). Taken without waiting (iPadOS 15 only: there SpringBoard's return
// is still on screen when the view opens; on 16 the hold ends before SpringBoard's switcher comes up -- iPad 2, Stage Manager: no difference).
static void DMMSWStartPicture(id gesture) {
    if (!gMSWOn || !DMMSWGesturesOn() || gMSWOpen || gMSWSwitching || gMSWSlRoot || DMMSWGestureTypeOf(gesture) != 1 || !DMMSWAsyncScreenOn() || !DMMSWAsyncPicturesOK()) return;
#if DEBUG
    if (DMTestFlag("/tmp/msw-nostartpic")) return;   // (debug comparison: no picture at the start with one desktop, as before)
#endif
    NSUInteger tgen = ++gMSWTrackPicGen;
    NSInteger did = DMMSWCurId();
    CFTimeInterval t = CACurrentMediaTime();
    __weak id g = gesture;
    DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], ^(UIView *pic, double ms) {
        if (!pic || tgen != gMSWTrackPicGen || DMMSWCurId() != did || gMSWOpen) return;   // (a later gesture's, another desktop now, or the view opened at once)
        gMSWLiftPic = pic; gMSWLiftPicAt = t; gMSWLiftPicId = did; gMSWLiftPicGen = tgen; gMSWLiftPicGesture = g;
    });
}
static void DMMSWTrackBegin(id gesture) {
    gMSWTrackV = 0;
    if (gMSWTrack < 2) gMSWHomeMod = nil;   // (this gesture's modifier is seen again in DMMSWFlyIn / DMMSWActivateWith)
    if (gMSWTrack == 2) return;   // (the fingers move a slide already)
    if (gMSWTrack == 1) DMMSWTrackDisarm();
    if (DMMSWGrabbable() && DMMSWGestureTypeOf(gesture) == 1) {   // (a slide on its way: the fingers may take it, once they go sideways)
        CGPoint tr, ve;
        if (!DMMSWGestureMotion(gesture, &tr, &ve)) return;
        gMSWTrack = 1; gMSWTrackGrab = YES; gMSWTrackGesture = gesture; gMSWTrackStart = tr; gMSWTrackAt = CACurrentMediaTime();
        gMSWTrackLastX = NAN; DMMSWTrackMoved(tr); DMMSWTrackSpeed(ve);
        DMMSWMark(@"armed (the running slide can be taken)");
        return;
    }
    if (gMSWTrack == 3) return;   // (a slide on its way that cannot be taken: a side swipe this gesture ends with comes at the lift, DMMSWSideRequest)
    if (!DMMSWMulti() || !DMMSWGesturesOn() || MSBReduceMotion() || gMSWOpen || gMSWSwitching || gMSWSlRoot || DMTestFlag("/tmp/msw-notrack")) { DMMSWStartPicture(gesture); return; }
    if (DMMSWGestureTypeOf(gesture) != 1) return;
    CGPoint tr, ve;
    if (!DMMSWGestureMotion(gesture, &tr, &ve)) return;
    CFTimeInterval t = CACurrentMediaTime();
    // (the screen as drawn now: SpringBoard has not moved anything yet. F5: asked without waiting -- the slide comes up only once it is in, at a
    //  later update of the gesture; UIKit's waiting picture held every gesture's start 4-10 ms, and could hold it seconds)
    gMSWTrackPic = nil;
    NSUInteger tgen = ++gMSWTrackPicGen;
    NSInteger did = DMMSWCurId();
    BOOL asked = DMMSWAsyncScreenOn() && DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], ^(UIView *pic, double ms) {
        if (!pic || tgen != gMSWTrackPicGen) return;   // (a later gesture's, or none)
        if (gMSWTrack == 1) gMSWTrackPic = pic;
        if (DMMSWCurId() == did) { gMSWLiftPic = pic; gMSWLiftPicAt = t; gMSWLiftPicId = did; gMSWLiftPicGen = tgen; gMSWLiftPicGesture = gesture; }
        gMSWTrackArmMs = ms;
        DMMSWMark([NSString stringWithFormat:@"the gesture's picture is in (%.1f ms, asked without waiting)", ms]);
    });
    if (!asked) {
        DMMSWSpanBegin();
        gMSWTrackPic = [[UIScreen mainScreen] snapshotViewAfterScreenUpdates:NO];
        DMMSWSpanEnd(@"the gesture's start picture (the screen now)");
        gMSWTrackArmMs = (CACurrentMediaTime() - t) * 1000.0;
        if (!gMSWTrackPic) return;
        gMSWLiftPic = gMSWTrackPic; gMSWLiftPicAt = t; gMSWLiftPicId = DMMSWCurId(); gMSWLiftPicGen = tgen; gMSWLiftPicGesture = gesture;
    }
    gMSWTrack = 1; gMSWTrackGesture = gesture; gMSWTrackStart = tr; gMSWTrackAt = t;
    gMSWTrackLastX = NAN; DMMSWTrackMoved(tr);
    DMMSWTrackSpeed(ve);
    DMMSWLayerUp(NO);   // (empty, touches going through: if the gesture becomes a slide, its window is up already)
    DMMSWMark([NSString stringWithFormat:@"armed (%.1f ms on the main thread)", (CACurrentMediaTime() - t) * 1000.0]);
}
static void DMMSWTrackDisarm(void) {   // (the gesture did not become a slide: its picture stays for a switch or the view; the empty window goes)
    BOOL grab = gMSWTrackGrab;
    gMSWTrack = grab && gMSWSwitching ? 3 : 0; gMSWTrackGesture = nil; gMSWTrackPic = nil; gMSWTrackGrab = NO;   // (armed on a running slide: it runs on)
    if (gMSWWindow && !gMSWSlRoot && !gMSWOpen) gMSWWindow.hidden = YES;
    gMSWWindow.userInteractionEnabled = YES;
}
static BOOL DMMSWTrackEngage(CGFloat x) {
    CGRect b = [UIScreen mainScreen].bounds;
    CFTimeInterval t = CACurrentMediaTime();
    UIView *left = gMSWCur > 0 ? DMMSWDeskPicture(gMSWCur - 1, b) : nil;
    UIView *right = gMSWCur + 1 < gMSWDesks.count ? DMMSWDeskPicture(gMSWCur + 1, b) : nil;
    if (!DMMSWSlBegin(gMSWTrackPic, left, right)) return NO;
    DMMSWSlSetPlace(0, gMSWCur); if (left) DMMSWSlSetPlace(-1, gMSWCur - 1); if (right) DMMSWSlSetPlace(1, gMSWCur + 1);   // (the desktops beside: a switch's redirect knows them)
    gMSWTrackZero = gMSWTrackStart.x; gMSWTrack = 2; gMSWTrackSince = t;
    // (SpringBoard reads the first sideways motion late -- its first update already carries 20-70 pt -- so the slide starts at the whole travel
    //  and an additive animation takes that much back at the start, decaying to nothing in 0.15 s: no jump, and the desktop is under the fingers
    //  1:1 from then on, not that far behind them)
    CGFloat o = DMMSWTrackOffset(x - gMSWTrackZero);
    DMMSWSlSetOffset(o);
    if (fabs(o) > 0.5) {
        CABasicAnimation *c = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        c.additive = YES; c.fromValue = @(-o); c.toValue = @0; c.duration = 0.15;
        c.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [gMSWSlStrip.layer addAnimation:c forKey:@"msw.catch"];
    }
    DM_FEATURE_MARK("mac-switcher-spaces-tracking");
    DMMSWMark([NSString stringWithFormat:@"slide follows the fingers (set up %.1f ms)", (CACurrentMediaTime() - t) * 1000.0]);
    DMLog([NSString stringWithFormat:@"[macswitcher] side swipe on %@: the slide follows the fingers (%@ on the left, %@ on the right; picture at the start %.1f ms, slide set up %.1f ms)", DMMSWDeskName(gMSWCur),
        left ? DMMSWDeskName(gMSWCur - 1) : @"nothing", right ? DMMSWDeskName(gMSWCur + 1) : @"nothing", gMSWTrackArmMs, (CACurrentMediaTime() - t) * 1000.0]);
    return YES;
}
// One update of the gesture: the slide comes up when the fingers go sideways, and follows them. YES: SpringBoard is not told this update.
static BOOL DMMSWTrackUpdate(id gesture) {
    CGPoint tr, ve;
    if (!DMMSWGestureMotion(gesture, &tr, &ve)) return NO;
    gMSWTrackAt = CACurrentMediaTime();
    DMMSWTrackSpeed(ve);
    DMMSWTrackMoved(tr);
    CGFloat dx = tr.x - gMSWTrackStart.x, dy = tr.y - gMSWTrackStart.y;
    if (gMSWTrack == 1) {
        long long fd = DMMSWFinalDestinationOf(gMSWHomeMod);
        BOOL sideways = fabs(dx) >= 16.0 && fabs(dx) >= fabs(dy), sbSide = (fd == 1 || fd == 2) && fabs(dx) >= 10.0 && fabs(dx) >= 0.5 * fabs(dy);
        if (!(sideways || sbSide) || fabs(dy) > 150.0) return NO;
        if (gMSWTrackGrab) { if (!DMMSWTrackGrabEngage(tr.x)) { DMMSWTrackDisarm(); return NO; } }
        else {
            if (!gMSWTrackPic) { static int told = 0; if (told++ < 20) DMLog(@"[macswitcher] side swipe: the gesture's picture is not in yet, the slide comes up at a later update"); return NO; }
            if (!DMMSWTrackEngage(tr.x)) { gMSWTrack = 0; return NO; }
        }
    }
    if (gMSWTrack != 2) return NO;
    if (gMSWTrackGrab) { CGFloat o = DMMSWGrabOffset(gMSWTrackGrabBase + (tr.x - gMSWTrackZero)); DMMSWGrabPictures(o); DMMSWSlSetOffset(o); }
    else DMMSWSlSetOffset(DMMSWTrackOffset(tr.x - gMSWTrackZero));
    return !DMTestFlag("/tmp/msw-nofreeze");   // (debug comparison: SpringBoard keeps responding under the slide)
}
// Where the lifted slide goes: past half a screen (unless the fingers flicked back), or a flick that way; at an outer desktop, back.
static NSInteger DMMSWTrackDecide(CGFloat o, CGFloat v) {
    NSInteger side = o < 0 ? 1 : -1;   // (the strip moved left: the desktop on the right was coming)
    if (fabs(o) < 6.0 && fabs(v) >= 600.0) side = v < 0 ? 1 : -1;   // (a flick that had hardly started: its way)
    if (!(side > 0 ? gMSWSlSide[1] : gMSWSlSide[0])) return 0;
    CGFloat along = side > 0 ? -v : v;   // (> 0: still moving that way)
    if (fabs(o) >= 0.5 * gMSWSlW && along > -450.0) return side;
    if (along >= 450.0 && (fabs(o) >= 6.0 || fabs(v) >= 600.0)) return side;
    return 0;
}
static void DMMSWTrackFinish(NSInteger side, CGFloat v) {
    gMSWTrackPic = nil; gMSWTrackGesture = nil;
    if (side) {
        DMMSWMark([NSString stringWithFormat:@"lifted: to the desktop on the %@ (%.0f pt/s)", side > 0 ? @"right" : @"left", v]);
        gMSWTrackCommit = YES;
        DMMSWSwitchRun((NSUInteger)((NSInteger)gMSWCur + side), side > 0 ? @"swipe left" : @"swipe right", v, nil);
        gMSWTrackCommit = NO;
        if (!gMSWSwitching) { DMLog(@"[macswitcher] the switch did not start: the slide goes back"); DMMSWTrackFinish(0, v); }
        return;
    }
    // back: the slide springs back (an aim of the running switch: a swipe or a Control-arrow on the way sends it on); it goes once SpringBoard's own
    // "stay" has settled under it
    DMMSWMark([NSString stringWithFormat:@"lifted: back (%.0f pt/s)", v]);
    DMMSWSwBack(v);
}
static void (*o_MSWGBegin)(id, SEL, id, id), (*o_MSWGUpdate)(id, SEL, id, id), (*o_MSWGEnd)(id, SEL, id, id);
static void DMMSWGBegin(id self, SEL _cmd, id transaction, id gesture) {
    static BOOL inside = NO;
    if (!inside) {
        inside = YES;
        @try { DMMSWTrackBegin(gesture); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] tracker begin threw %@", e]); gMSWTrack = 0; }
        if (gMSWTrack == 1) { DMMSWRecBegin(@"gesture (followed)"); DMMSWRecordEvent(gesture, @"B"); }
        inside = NO;
    }
    o_MSWGBegin(self, _cmd, transaction, gesture);
}
static void DMMSWGUpdate(id self, SEL _cmd, id transaction, id gesture) {
    static BOOL inside = NO;
    if (inside || (gMSWTrack != 1 && gMSWTrack != 2) || gesture != gMSWTrackGesture) { o_MSWGUpdate(self, _cmd, transaction, gesture); return; }
    inside = YES;
    BOOL swallow = NO;
    @try { swallow = DMMSWTrackUpdate(gesture); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] tracker update threw %@", e]); swallow = NO; }
    DMMSWRecordEvent(gesture, swallow ? @"S" : @"U");
    inside = NO;
    if (!swallow) o_MSWGUpdate(self, _cmd, transaction, gesture);
}
static void DMMSWGEnd(id self, SEL _cmd, id transaction, id gesture) {
    static BOOL inside = NO;
    if (inside || (gMSWTrack != 1 && gMSWTrack != 2) || gesture != gMSWTrackGesture) { o_MSWGEnd(self, _cmd, transaction, gesture); return; }
    inside = YES;
    DMMSWRecordEvent(gesture, @"E");
    CGPoint tr, ve;
    BOOL have = DMMSWGestureMotion(gesture, &tr, &ve);
    if (have) { DMMSWTrackSpeed(ve); DMMSWTrackMoved(tr); }
    if (gMSWTrack == 1) {   // (it never went sideways: SpringBoard's own end -- a side swipe it reads at the lift still slides, from this gesture's picture)
        DMMSWTrackDisarm();
        inside = NO;
        o_MSWGEnd(self, _cmd, transaction, gesture);
        return;
    }
    if (gMSWTrackGrab) {   // (a taken slide: on to the desktop the fingers chose)
        CGFloat o = have ? DMMSWGrabOffset(gMSWTrackGrabBase + (tr.x - gMSWTrackZero)) : gMSWSlStrip.transform.tx, v = DMMSWTrackLiftSpeed();
        DMMSWSlSetOffset(o);
        NSInteger k = DMMSWGrabDecide(o, v);
        gMSWTrack = 3;
        DMLog([NSString stringWithFormat:@"[macswitcher] the taken slide lifted at %.0f pt (%.0f pt/s, %.0f ms after the fingers took it): to %@", o, v, (CACurrentMediaTime() - gMSWTrackSince) * 1000.0, DMMSWDeskName((NSUInteger)MAX(0, (NSInteger)gMSWSwFrom + k))]);
        @try { DMMSWGrabFinish(k, v); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] taken slide end threw %@", e]); DMMSWSlDrop(); gMSWTrack = 0; gMSWSwitching = NO; }
        [CATransaction flush];
        gMSWTrackEnding = YES;   // (SpringBoard is told "stay" for this gesture, as for any followed one)
        o_MSWGEnd(self, _cmd, transaction, gesture);
        gMSWTrackEnding = NO;
        inside = NO;
        return;
    }
    if (have) DMMSWSlSetOffset(DMMSWTrackOffset(tr.x - gMSWTrackZero));
    CGFloat o = gMSWSlStrip.transform.tx, v = DMMSWTrackLiftSpeed();
    NSInteger side = DMMSWTrackDecide(o, v);
    gMSWTrack = 3;
    DMLog([NSString stringWithFormat:@"[macswitcher] side swipe lifted at %.0f pt (%.0f pt/s, %.0f ms after the slide came up): %@", o, v, (CACurrentMediaTime() - gMSWTrackSince) * 1000.0,
        side ? [NSString stringWithFormat:@"to the desktop on the %@", side > 0 ? @"right" : @"left"] : @"back"]);
    @try { DMMSWTrackFinish(side, v); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] tracker end threw %@", e]); DMMSWSlDrop(); gMSWTrack = 0; gMSWSwitching = NO; }
    [CATransaction flush];   // (the spring to the render server before SpringBoard's own end, ~50 ms of its main thread, runs)
    gMSWTrackEnding = YES;   // (SpringBoard ends its gesture now -- its lift-off activation runs inside this call -- and is told "stay", DMMSWActivateWith)
    o_MSWGEnd(self, _cmd, transaction, gesture);
    gMSWTrackEnding = NO;
    inside = NO;
}
// The tick: a followed gesture that ended without an end (its gesture gone, or no longer held) goes back; one armed for long is let go.
static void DMMSWTrackTick(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (gMSWTrack == 2 && (!DMMSWGestureAlive(gMSWTrackGesture) || now - gMSWTrackSince > 20.0) && now - gMSWTrackAt > 0.5) {
        gMSWTrack = 3;
        if (gMSWTrackGrab) { DMLog(@"[macswitcher] the gesture that took the slide ended without its end: it goes to the nearest desktop"); DMMSWGrabFinish(DMMSWGrabDecide(gMSWSlStrip.transform.tx, 0), 0); return; }
        DMLog(@"[macswitcher] the followed gesture ended without its end: the slide goes back");
        DMMSWTrackFinish(0, 0);
    } else if (gMSWTrack == 1 && (!DMMSWGestureAlive(gMSWTrackGesture) || now - gMSWTrackAt > 6.0)) {
        DMMSWTrackDisarm();
    }
}
static id DMMSWActivateWith(id self, SEL _cmd, long long dest, id (*orig)(id, SEL, long long)) {
    static BOOL inside = NO;
    static CFTimeInterval lastAct = 0;
    // (Reduce Motion's modifier ends a side swipe by activating 0 itself -- "stay": with Reduce Motion iPadOS does not switch apps from the
    //  bottom edge -- while its final destination says 1 / 2, previous / next layout by a fast bottom swipe: that is the side swipe we take)
    long long eff = dest;
    if (dest == 0 && orig == o_MSWActivateRM) { long long fd = DMMSWFinalDestinationOf(self); if (fd == 1 || fd == 2) eff = fd; }
    if (!inside) DMMSWMark([NSString stringWithFormat:@"lift: activating %lld (final %lld)", dest, eff]);
#if DEBUG
    if (!inside && DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[mswprobe] activating destination %lld (final %lld, travel x %.0f, fingers went %@, %@)", dest, eff, DMMSWGestureTravelX(self),
        eff == 1 || eff == 2 ? (DMMSWFingersWentRight(self, eff) ? @"right" : @"left") : @"-", NSStringFromClass(object_getClass(self))]);
#endif
    if (!inside) gMSWHomeMod = self;
    if (!inside && gMSWTrackEnding) {   // (the slide follows this gesture: SpringBoard stays where it is, whatever it would have done -- the slide ends it)
        gMSWTookOverAt = CACurrentMediaTime();
        inside = YES;
        id r = orig(self, _cmd, 0);
        inside = NO;
        DMLog([NSString stringWithFormat:@"[macswitcher] gesture ended on %lld while the slide follows it: stay", eff]);
        return r;
    }
    if (inside || (eff != 3 && eff != 1 && eff != 2) || !DMMSWGesturesOn()) return orig(self, _cmd, dest);
    dispatch_block_t act = nil;
    if (eff == 3) act = ^{ gMSWGestureAt = CACurrentMediaTime(); DMMSWOpen(@"the App Switcher gesture"); };
    else if (DMMSWMulti()) {
        // (which way, as on a Mac -- the desktop follows the fingers: moving left brings the desktop on the right, moving right the one on the left;
        //  touch and trackpad alike, DMMSWFingersWentRight). A side swipe the slide did not follow (a quick flick, Reduce Motion, the tracker off)
        // slides from rest at the fingers' speed; one made while a switch is still on its way sends that slide on at once (DMMSWSideRequest).
        BOOL fingerRight = DMMSWFingersWentRight(self, eff);
        NSInteger side = fingerRight ? -1 : 1;
        CGFloat v = MSBReduceMotion() ? 0 : DMMSWTrackLiftSpeed();
        act = ^{ DMMSWSideRequest(side, v, fingerRight ? @"swipe right" : @"swipe left"); };
    }
    if (!act) return orig(self, _cmd, dest);   // (1/2 with one desktop: the stock previous / next app)
    gMSWTookOverAt = CACurrentMediaTime();
    inside = YES;
    id r = orig(self, _cmd, 0);   // (0: stay on the current layout -- no App Switcher, no app switch)
    inside = NO;
    if (CACurrentMediaTime() - lastAct > 0.4) {   // (one action per gesture, should this fire more than once)
        lastAct = CACurrentMediaTime();
        DM_FEATURE_MARK("mac-switcher-gestures");
        DMLog([NSString stringWithFormat:@"[macswitcher] gesture ended on %lld: stay instead, ours runs", eff]);
        dispatch_async(dispatch_get_main_queue(), act);
    }
    return r;
}
// Safety net (iPadOS 15: the gesture manager's completion; 16: the coordinator's): a gesture-initiated request that still asks for the App Switcher
// (mode 2) within a moment of a takeover is made a request without an environment change. With the remap above this never fires; it guards an
// unforeseen path only.
static void (*o_MSWComplete15)(id, SEL, id);
static void DMMSWComplete15(id self, SEL _cmd, id request) {
    static BOOL inside = NO;
    if (!inside && gMSWTookOverAt > 0 && CACurrentMediaTime() - gMSWTookOverAt < 0.6 && !DMMSWStockOnce()) {   // (never the menu's own stock switcher)
        inside = YES;
        @try {
            if (DMMSWHasMethod(object_getClass(request), @"unlockedEnvironmentMode", @"q@:") && ((long long (*)(id, SEL))objc_msgSend)(request, NSSelectorFromString(@"unlockedEnvironmentMode")) == 2
                && DMMSWHasMethod(object_getClass(request), @"setUnlockedEnvironmentMode:", @"v@:q")) {
                ((void (*)(id, SEL, long long))objc_msgSend)(request, NSSelectorFromString(@"setUnlockedEnvironmentMode:"), 0);
                DMLog(@"[macswitcher] safety net: a completion still asked for the App Switcher -> made a request without a change");
            }
        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[macswitcher] completion check threw %@", e]); }
        inside = NO;
    }
    o_MSWComplete15(self, _cmd, request);
}
static NSString *gMSWDiagGestures = @"-";   // (untested iPadOS: which gesture hooks went on, for the StatusBar diagnostic record, DMMSWDiagLine)
static void DMMSWHookGestures(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = objc_getClass("SBHomeGestureSwitcherModifier");
    Class gm = objc_getClass("SBFluidSwitcherGestureManager"), co = objc_getClass("SBMainSwitcherControllerCoordinator");
    BOOL ok15 = DMMSWHasMethod(gm, @"completeGestureWithTransitionRequest:", @"v@:@"), ok16 = DMMSWHasMethod(co, @"handleTransitionRequestForGestureComplete:", @"v@:@");
    // (iPadOS 17 -- 17.0.3 headers, 17.6.1 code, and 18.2 --: -handleTransitionRequestForGestureComplete: is the gesture MANAGER's, the coordinator
    //  has none. Asked only where neither of the two above is there, so 15/16 keep exactly the path they had.)
    BOOL okGM = !ok15 && !ok16 && DMMSWHasMethod(gm, @"handleTransitionRequestForGestureComplete:", @"v@:@");
    BOOL flyIn = DMMSWHasMethod(c, @"_hasPausedEnoughForFlyIn", @"B@:"), dest = DMMSWHasMethod(c, @"_responseForActivatingFinalDestination:", @"@@:q");
    if (!dest || !flyIn || (!ok15 && !ok16 && !okGM)) {
        gMSWDiagGestures = [NSString stringWithFormat:@"none(flyin%d,dest%d,done0)", flyIn, dest];
        DMLog(@"[macswitcher] the gesture hooks are not as expected here: the gestures stay iPadOS's own");
        return;
    }
    MSHookMessageEx(c, NSSelectorFromString(@"_hasPausedEnoughForFlyIn"), (IMP)DMMSWFlyIn, (IMP *)&o_MSWFlyIn);
    MSHookMessageEx(c, NSSelectorFromString(@"_responseForActivatingFinalDestination:"), (IMP)DMMSWActivate, (IMP *)&o_MSWActivate);
    if (ok15) MSHookMessageEx(gm, NSSelectorFromString(@"completeGestureWithTransitionRequest:"), (IMP)DMMSWComplete15, (IMP *)&o_MSWComplete15);
    else if (ok16) MSHookMessageEx(co, NSSelectorFromString(@"handleTransitionRequestForGestureComplete:"), (IMP)DMMSWComplete15, (IMP *)&o_MSWComplete15);
    else MSHookMessageEx(gm, NSSelectorFromString(@"handleTransitionRequestForGestureComplete:"), (IMP)DMMSWComplete15, (IMP *)&o_MSWComplete15);
    gMSWDiagGestures = ok15 ? @"flyin,dest,done:gm15" : ok16 ? @"flyin,dest,done:co16" : @"flyin,dest,done:gm17";
    DMLog(@"[macswitcher] gesture hook installed (fly-in suppressed, destination remapped at the source)");
    // the side swipe that follows the fingers (the tracker): the gesture manager's begin / update / end of each gesture
    if (DMMSWHasMethod(gm, @"fluidSwitcherGestureTransaction:didBeginGesture:", @"v@:@@") && DMMSWHasMethod(gm, @"fluidSwitcherGestureTransaction:didUpdateGesture:", @"v@:@@")
        && DMMSWHasMethod(gm, @"fluidSwitcherGestureTransaction:didEndGesture:", @"v@:@@")) {
        MSHookMessageEx(gm, NSSelectorFromString(@"fluidSwitcherGestureTransaction:didBeginGesture:"), (IMP)DMMSWGBegin, (IMP *)&o_MSWGBegin);
        MSHookMessageEx(gm, NSSelectorFromString(@"fluidSwitcherGestureTransaction:didUpdateGesture:"), (IMP)DMMSWGUpdate, (IMP *)&o_MSWGUpdate);
        MSHookMessageEx(gm, NSSelectorFromString(@"fluidSwitcherGestureTransaction:didEndGesture:"), (IMP)DMMSWGEnd, (IMP *)&o_MSWGEnd);
        gMSWDiagGestures = [gMSWDiagGestures stringByAppendingString:@",track"];
        DMLog(@"[macswitcher] side swipes followed by the fingers (gesture updates hooked)");
    } else DMLog(@"[macswitcher] the gesture manager's updates are not as expected here: side swipes slide at the lift only");
    Class rm = objc_getClass("SBReduceMotionHomeGestureSwitcherModifier");   // (Reduce Motion's own home gesture, DMMSWActivateRM)
    if (DMMSWHasMethod(rm, @"_responseForActivatingFinalDestination:", @"@@:q")) {
        MSHookMessageEx(rm, NSSelectorFromString(@"_responseForActivatingFinalDestination:"), (IMP)DMMSWActivateRM, (IMP *)&o_MSWActivateRM);
        DMLog(@"[macswitcher] gesture hook installed for Reduce Motion's home gesture too");
    } else DMLog(@"[macswitcher] Reduce Motion's home gesture is not as expected here: with Reduce Motion on, the gestures stay iPadOS's own");
}
// The StatusBar diagnostic record's Mac Switcher line (untested iPadOS: StatusBar.x DMSBDiagFlush). Compact, no spaces: on, self-check, the
// gesture hooks and which completion they found, the App Switcher toggle, and the desktops. Names and numbers only.
static NSString *DMMSWDiagLine(void) {
    return [NSString stringWithFormat:@"msw on%d,check%d,gest:%@,appsw%d,stock:%@,desks%lu", gMSWOn, DMMSWSelfCheck(), gMSWDiagGestures, DMMSWAppSwitcherAvailable(), gMSWDiagStock, (unsigned long)gMSWDesks.count];
}

// Settings > Status Bar > Mac Switcher (DMLoadPrefs).
static void DMMSWApplyPref(BOOL want) {
    BOOL on = want && DMMSWOSOK() && DMMSWSelfCheck();
    if (on == gMSWOn) return;
    gMSWOn = on;
    DMLog([NSString stringWithFormat:@"[macswitcher] Mac Switcher %@", on ? @"on" : @"off"]);
    if (on) { DMMSWHookKeys(); DMMSWHookGestures(); DMMSWHookStockPaths(); DMMSWWatchMemory(); DMMSWLoad(); }
    if (!on) dispatch_async(dispatch_get_main_queue(), ^{
        DMMSWDropFinishNow();
        if (DMMSWIsOpen()) DMMSWClose(nil, NO);
        if (gMSWTrack && !gMSWSwitching) { DMMSWSlDrop(); gMSWTrack = 0; gMSWTrackPic = nil; }   // (a slide following the fingers goes with the switch)
        gMSWLiftPic = nil; DMMSWOpenShotDrop();
        DMMSWCollapse();
    });
}

#if DEBUG
static NSString *DMProbeStack(void);   // (StatusBar.x: the caller's methods, symbolized)
// ==== probes (debug builds only, read-only): what SpringBoard decides during the bottom-edge gestures ====
// Logged as "[mswprobe] ...": the gesture type and the recogniser it came from, each change of the final destination (Home / App Switcher /
// arc swipe ...), the hold moment (the App Switcher's fly-in), the destination at the end and the environment mode the transition goes to.
// Every hook checks the method's type encoding first and only reads; a re-entered call goes straight to the original.
static CFTimeInterval gMSWProbeBegan = 0;
static long long gMSWProbeDest = LLONG_MIN, gMSWProbeType = LLONG_MIN;
static BOOL gMSWProbeHold = NO;
static void *gMSWProbeFDInst[4]; static long long gMSWProbeFDLast[4];   // (each final-destination modifier's own last answer: two of them answer)
static int DMMSWProbeMs(void) { return gMSWProbeBegan > 0 ? (int)((CACurrentMediaTime() - gMSWProbeBegan) * 1000.0) : -1; }

// ==== measurement: a frame recording of a desktop switch or a gesture (armed while /tmp/msw-rec exists) ====
// From a gesture's or a switch's start to a moment after it is over, every display frame of SpringBoard's main thread is one line "t dt rs x a":
// t ms since the start, dt the gap since the frame before (a main-thread stall is a long one), rs how many frames the render server (backboardd)
// drew meanwhile (CARenderServerGetFrameCounter -- a committed animation is played there on its own, so a main-thread stall need not cost one of
// its frames), x / a the tracked view's on-screen translation and opacity (presentation layer). Gesture events ("U t tx ty vx vy lx ly fd") and
// marks ("M t name") go in between. At the end everything is appended to /tmp/msw-rec.log and one summary line goes to the debug log: main
// frames, slow ones (over 1.5 periods), the longest gap and where, and while the slide ran (marks "slide ..." .. "slide end") the render server's
// frames against the display's. Nothing is written per frame.
@interface DMMSWRecTarget : NSObject
- (void)tick:(CADisplayLink *)l;
@end
static CADisplayLink *gMSWRecLink;
static DMMSWRecTarget *gMSWRecTarget;
static CFTimeInterval gMSWRecT0, gMSWRecPrev, gMSWRecStopAt;
static uint32_t gMSWRecRS;
static NSMutableString *gMSWRecLines, *gMSWRecMarks;
static NSString *gMSWRecWhy;
static int gMSWRecNo, gMSWRecFrames, gMSWRecSlow, gMSWRecEvents;
static double gMSWRecMaxGap, gMSWRecMaxAt, gMSWRecPeriod = 8.333, gMSWRecSlideDisp, gMSWRecSlideRend, gMSWRecSlideMaxGap;
static BOOL gMSWRecInSlide, gMSWRecNoRS;
static __weak UIView *gMSWRecView, *gMSWRecCard;
static uint32_t DMMSWRecRS(void) {
    if (gMSWRecNoRS) return 0;   // (/tmp/msw-rec-nors: no render-server frame count -- that call waits on the server, and a busy server stalls the recorder's frames)
    static uint32_t (*fn)(mach_port_t); static BOOL tried;
    if (!tried) { tried = YES; fn = (uint32_t (*)(mach_port_t))dlsym(RTLD_DEFAULT, "CARenderServerGetFrameCounter"); }
    return fn ? fn(MACH_PORT_NULL) : 0;
}
static double DMMSWRecT(void) { return (CACurrentMediaTime() - gMSWRecT0) * 1000.0; }
static void DMMSWRecFinish(void) {
    [gMSWRecLink invalidate]; gMSWRecLink = nil;
    NSString *sum = [NSString stringWithFormat:@"[mswrec] #%d %@: %.0f ms, %d main frames (period %.2f ms), %d slow (> 1.5 periods), longest %.1f ms at +%.0f; slide: render %.0f of %.0f display frames (%.0f dropped), longest main gap in it %.1f ms; %d events; marks:%@",
        gMSWRecNo, gMSWRecWhy, DMMSWRecT(), gMSWRecFrames, gMSWRecPeriod, gMSWRecSlow, gMSWRecMaxGap, gMSWRecMaxAt, gMSWRecSlideRend, gMSWRecSlideDisp, MAX(0.0, gMSWRecSlideDisp - gMSWRecSlideRend), gMSWRecSlideMaxGap, gMSWRecEvents, gMSWRecMarks];
    DMLog(sum);
    NSString *all = [NSString stringWithFormat:@"# %@\n%@", sum, gMSWRecLines];
    gMSWRecLines = nil; gMSWRecMarks = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        FILE *f = fopen("/tmp/msw-rec.log", "a");
        if (f) { fputs(all.UTF8String, f); fclose(f); }
    });
}
@implementation DMMSWRecTarget
- (void)tick:(CADisplayLink *)l {
    if (!gMSWRecLines) { [l invalidate]; return; }
    CFTimeInterval now = l.timestamp;
    uint32_t rs = DMMSWRecRS(), drs = rs - gMSWRecRS;
    gMSWRecRS = rs;
    double period = (l.targetTimestamp - l.timestamp) * 1000.0;
    if (period > 3.0 && period < 40.0) gMSWRecPeriod = period;
    double dt = gMSWRecPrev > 0 ? (now - gMSWRecPrev) * 1000.0 : 0, t = (now - gMSWRecT0) * 1000.0;
    gMSWRecPrev = now;
    if (dt > 0) {
        gMSWRecFrames++;
        if (dt > gMSWRecPeriod * 1.5) gMSWRecSlow++;
        if (dt > gMSWRecMaxGap) { gMSWRecMaxGap = dt; gMSWRecMaxAt = t; }
        if (gMSWRecInSlide) { gMSWRecSlideDisp += MAX(1.0, round(dt / gMSWRecPeriod)); gMSWRecSlideRend += drs; gMSWRecSlideMaxGap = MAX(gMSWRecSlideMaxGap, dt); }
    }
    [gMSWRecLines appendFormat:@"%.1f %.1f %u", t, dt, drs];
    UIView *v = gMSWRecView;
    if (v.window) { CALayer *pl = v.layer.presentationLayer ?: v.layer; [gMSWRecLines appendFormat:@" x%.1f a%.2f", pl.transform.m41, pl.opacity]; }
    UIView *c = gMSWRecCard;
    if (c.window) {   // (the stock visuals: where SpringBoard draws the full-screen app's scene view now)
        CALayer *pl = c.layer.presentationLayer ?: c.layer, *wl = c.window.layer.presentationLayer ?: c.window.layer;
        CGRect r = [pl convertRect:pl.bounds toLayer:wl];
        [gMSWRecLines appendFormat:@" card %.0f,%.0f %.0fx%.0f", r.origin.x, r.origin.y, r.size.width, r.size.height];
    }
    UIWindow *al = DMActiveEngine() == DMEngineAerial ? DMWindowLayer() : nil;
    if (al) [gMSWRecLines appendFormat:@" aw%d/%.2f", al.hidden, (al.layer.presentationLayer ?: al.layer).opacity];
    [gMSWRecLines appendString:@"\n"];
    if (CACurrentMediaTime() >= gMSWRecStopAt) DMMSWRecFinish();
}
@end
static void DMMSWRecBegin(NSString *why) {
    if (!DMTestFlag("/tmp/msw-rec")) return;
    if (gMSWRecLines) {   // (one recording: a switch that a gesture started is part of the gesture's)
        gMSWRecWhy = [gMSWRecWhy stringByAppendingFormat:@" + %@", why];
        gMSWRecStopAt = MAX(gMSWRecStopAt, CACurrentMediaTime() + 6.0);
        return;
    }
    gMSWRecNo++; gMSWRecWhy = why;
    gMSWRecNoRS = DMTestFlag("/tmp/msw-rec-nors");
    gMSWRecLines = [NSMutableString string]; gMSWRecMarks = [NSMutableString string];
    gMSWRecT0 = CACurrentMediaTime(); gMSWRecPrev = 0; gMSWRecStopAt = gMSWRecT0 + 6.0; gMSWRecRS = DMMSWRecRS();
    gMSWRecFrames = gMSWRecSlow = gMSWRecEvents = 0; gMSWRecMaxGap = gMSWRecMaxAt = gMSWRecSlideDisp = gMSWRecSlideRend = gMSWRecSlideMaxGap = 0;
    gMSWRecInSlide = NO; gMSWRecView = nil; gMSWRecCard = nil;
    if (DMTestFlag("/tmp/msw-rec-card")) { SBApplication *front = DMFrontApp(); if (front && DMFullScreenAppInFront()) gMSWRecCard = DMMSWFullScreenView([front bundleIdentifier], NO); }
    if (!gMSWRecTarget) gMSWRecTarget = [DMMSWRecTarget new];
    gMSWRecLink = [CADisplayLink displayLinkWithTarget:gMSWRecTarget selector:@selector(tick:)];
    if ([gMSWRecLink respondsToSelector:@selector(setPreferredFrameRateRange:)]) gMSWRecLink.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [gMSWRecLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
static void DMMSWRecMark(NSString *mark) {
    if (!gMSWRecLines || !mark) return;
    double t = DMMSWRecT();
    [gMSWRecLines appendFormat:@"M %.1f %@\n", t, mark];
    [gMSWRecMarks appendFormat:@" %@ +%.0f;", mark, t];
    if ([mark hasPrefix:@"slide end"]) gMSWRecInSlide = NO;
    else if ([mark hasPrefix:@"slide"]) gMSWRecInSlide = YES;
}
static void DMMSWRecEndAfter(double seconds) { if (gMSWRecLines) gMSWRecStopAt = CACurrentMediaTime() + seconds; }
static void DMMSWRecTrack(UIView *v) { if (gMSWRecLines) gMSWRecView = v; }
static CGPoint DMMSWPointOf(id o, NSString *sel) {   // (a CGPoint getter, read only when it is one)
    if (!o || !DMMSWHasMethod(object_getClass(o), sel, @"{CGPoint=dd}@:")) return CGPointMake(NAN, NAN);
    return ((CGPoint (*)(id, SEL))objc_msgSend)(o, NSSelectorFromString(sel));
}
// One gesture event into the recording (tag B / U / E: begin, update, end), as SpringBoard's gesture has it.
static void DMMSWRecEvent(id gesture, NSString *tag) {
    if (!gMSWRecLines) return;
    id ev = gesture && DMMSWHasMethod(object_getClass(gesture), @"gestureEvent", @"@@:") ? DMCall(gesture, @"gestureEvent") : nil;
    static BOOL told = NO;
    if (!told && ev) {
        told = YES;
        DMLog([NSString stringWithFormat:@"[mswrec] gesture event class %@: translation %d velocity %d location %d phase %d", NSStringFromClass([ev class]),
            DMMSWHasMethod(object_getClass(ev), @"translationInContainerView", @"{CGPoint=dd}@:"), DMMSWHasMethod(object_getClass(ev), @"velocityInContainerView", @"{CGPoint=dd}@:"),
            DMMSWHasMethod(object_getClass(ev), @"locationInContainerView", @"{CGPoint=dd}@:"), DMMSWHasMethod(object_getClass(ev), @"phase", @"q@:")]);
    }
    CGPoint tr = DMMSWPointOf(ev, @"translationInContainerView"), ve = DMMSWPointOf(ev, @"velocityInContainerView"), lo = DMMSWPointOf(ev, @"locationInContainerView");
    gMSWRecEvents++;
    [gMSWRecLines appendFormat:@"%@ %.1f %.1f %.1f %.0f %.0f %.1f %.1f %lld\n", tag, DMMSWRecT(), tr.x, tr.y, ve.x, ve.y, lo.x, lo.y, gMSWProbeDest];
}
static NSString *DMMSWIvarNameOf(id owner, id value) {
    unsigned n = 0; Ivar *list = class_copyIvarList(object_getClass(owner), &n);
    NSString *name = nil;
    for (unsigned i = 0; i < n && !name; i++) {
        const char *t = ivar_getTypeEncoding(list[i]);
        if (t && t[0] == '@' && object_getIvar(owner, list[i]) == value) name = @(ivar_getName(list[i]));
    }
    free(list);
    return name ?: @"?";
}
static long long (*o_MSWGestureType)(id, SEL, id);
static long long DMMSWProbeGestureType(id self, SEL _cmd, UIGestureRecognizer *g) {
    static BOOL inside = NO;
    long long t = o_MSWGestureType(self, _cmd, g);
    if (inside) return t;
    inside = YES;
    static __weak id lastG; static long long lastT = LLONG_MIN; static CFTimeInterval lastAt = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (g != lastG || t != lastT || now - lastAt > 1.0) {
        lastG = g; lastT = t; lastAt = now;
        NSUInteger touches = [g isKindOfClass:[UIGestureRecognizer class]] ? g.numberOfTouches : 0;
        DMLog([NSString stringWithFormat:@"[mswprobe] gesture type %lld from %@ (%@, state %ld, touches %lu)", t, DMMSWIvarNameOf(self, g), NSStringFromClass([g class]), [g isKindOfClass:[UIGestureRecognizer class]] ? (long)g.state : -1L, (unsigned long)touches]);
    }
    inside = NO;
    return t;
}
static long long DMMSWGestureFieldQ(id gesture, NSString *sel) {
    return DMMSWHasMethod(object_getClass(gesture), sel, @"q@:") ? ((long long (*)(id, SEL))objc_msgSend)(gesture, NSSelectorFromString(sel)) : LLONG_MIN;
}
static void (*o_MSWDidBegin)(id, SEL, id, id);
static void DMMSWProbeDidBegin(id self, SEL _cmd, id transaction, id gesture) {
    static BOOL inside = NO;
    if (inside) { o_MSWDidBegin(self, _cmd, transaction, gesture); return; }
    inside = YES;
    gMSWProbeBegan = CACurrentMediaTime(); gMSWProbeDest = LLONG_MIN; gMSWProbeHold = NO;
    memset(gMSWProbeFDInst, 0, sizeof gMSWProbeFDInst);
    gMSWProbeType = DMMSWGestureFieldQ(gesture, @"type");
    DMMSWRecBegin([NSString stringWithFormat:@"gesture type %lld", gMSWProbeType]);
    DMMSWMark(@"gesture begin");
    DMMSWRecEvent(gesture, @"B");
    DMLog([NSString stringWithFormat:@"[mswprobe] BEGIN gesture type %lld, transaction %@", gMSWProbeType, NSStringFromClass([transaction class])]);
    inside = NO;
    o_MSWDidBegin(self, _cmd, transaction, gesture);
}
static void (*o_MSWDidEnd)(id, SEL, id, id);
static void DMMSWProbeDidEnd(id self, SEL _cmd, id transaction, id gesture) {
    static BOOL inside = NO;
    if (!inside) { inside = YES;
    DMMSWRecEvent(gesture, @"E");
    DMMSWMark(@"gesture end");
    DMMSWRecEndAfter(1.6);
    DMLog([NSString stringWithFormat:@"[mswprobe] END gesture type %lld after %d ms: last final destination %lld, hold %d", DMMSWGestureFieldQ(gesture, @"type"), DMMSWProbeMs(), gMSWProbeDest, gMSWProbeHold]);
    inside = NO; }
    o_MSWDidEnd(self, _cmd, transaction, gesture);
}
// (measurement: each update of the gesture -- its event's translation, velocity and place, as SpringBoard reads them -- into the running recording)
static void (*o_MSWDidUpdate)(id, SEL, id, id);
static void DMMSWProbeDidUpdate(id self, SEL _cmd, id transaction, id gesture) {
    static BOOL inside = NO;
    if (!inside && !gMSWTrack) { inside = YES; DMMSWRecEvent(gesture, @"U"); inside = NO; }   // (a followed gesture's updates are recorded by the tracker)
    o_MSWDidUpdate(self, _cmd, transaction, gesture);
}
static long long (*o_MSWFinalDest)(id, SEL);
static long long DMMSWProbeFinalDest(id self, SEL _cmd) {
    static BOOL inside = NO;
    long long d = o_MSWFinalDest(self, _cmd);
    if (inside) return d;
    int slot = -1;
    for (int i = 0; i < 4 && slot < 0; i++) if (gMSWProbeFDInst[i] == (__bridge void *)self) slot = i;
    if (slot < 0) { for (int i = 0; i < 4 && slot < 0; i++) if (!gMSWProbeFDInst[i]) slot = i; if (slot < 0) slot = 0; gMSWProbeFDInst[slot] = (__bridge void *)self; gMSWProbeFDLast[slot] = LLONG_MIN; }
    if (d == gMSWProbeFDLast[slot]) return d;
    inside = YES;
    gMSWProbeFDLast[slot] = d;
    gMSWProbeDest = d;
    id reason = DMMSWHasMethod(object_getClass(self), @"finalDestinationReason", @"@@:") ? ((id (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"finalDestinationReason")) : nil;
    DMLog([NSString stringWithFormat:@"[mswprobe] final destination -> %lld at +%d ms (reason %@) [FD %p]", d, DMMSWProbeMs(), [reason isKindOfClass:[NSString class]] ? reason : NSStringFromClass([reason class]), self]);
    inside = NO;
    return d;
}
static BOOL (*o_MSWPaused)(id, SEL);
static BOOL DMMSWProbePaused(id self, SEL _cmd) {
    static BOOL inside = NO;
    BOOL y = o_MSWPaused(self, _cmd);
    if (inside) return y;
    inside = YES;
    if (y && !gMSWProbeHold) { gMSWProbeHold = YES; DMLog([NSString stringWithFormat:@"[mswprobe] HOLD (paused enough for the fly-in) at +%d ms, final destination %lld", DMMSWProbeMs(), gMSWProbeDest]); }
    inside = NO;
    return y;
}
static NSString *DMMSWProbeChain(id m) {   // (the modifier's parents up to the root, and the root's delegate)
    NSMutableString *c = [NSMutableString string];
    id top = m;
    for (int i = 0; i < 8 && m; i++) { [c appendFormat:@"%@%@", i ? @" < " : @"", NSStringFromClass([m class])]; top = m; m = DMCall(m, @"parentModifier"); }
    id del = DMCall(top, @"delegate");
    [c appendFormat:@" | delegate %@ %p", del ? NSStringFromClass([del class]) : @"-", del];
    return c;
}
static long long DMMSWIvarQ(id o, const char *name) {   // (a long long ivar, read only when it is one)
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    return t && !strcmp(t, "q") ? *(long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : LLONG_MIN;
}
static id (*o_MSWEndResponse)(id, SEL, id, long long);
static id DMMSWProbeEndResponse(id self, SEL _cmd, id event, long long dest) {
    static BOOL inside = NO;
    if (!inside) { inside = YES;
        id sel = nil; Ivar iv = class_getInstanceVariable(object_getClass(self), "_selectedAppLayout"); if (iv && ivar_getTypeEncoding(iv)[0] == '@') sel = object_getIvar(self, iv);
        DMLog([NSString stringWithFormat:@"[mswprobe] gesture end event: final destination %lld at +%d ms [HG %p start mode %lld, selected %@] %@", dest, DMMSWProbeMs(), self, DMMSWIvarQ(self, "_startingEnvironmentMode"), sel ? DMCall(sel, @"succinctDescription") : @"-", DMMSWProbeChain(self)]);
        inside = NO; }
    id r = o_MSWEndResponse(self, _cmd, event, dest);
    if (!inside) { inside = YES; DMLog([NSString stringWithFormat:@"[mswprobe]   -> response %@", r ? DMCall(r, @"succinctDescription") ?: NSStringFromClass([r class]) : @"nil"]); inside = NO; }
    return r;
}
static void (*o_MSWComplete)(id, SEL, id);
static void DMMSWProbeComplete(id self, SEL _cmd, id request) {
    static BOOL inside = NO;
    if (inside) { o_MSWComplete(self, _cmd, request); return; }
    inside = YES;
    long long mode = DMMSWHasMethod(object_getClass(request), @"unlockedEnvironmentMode", @"q@:") ? ((long long (*)(id, SEL))objc_msgSend)(request, NSSelectorFromString(@"unlockedEnvironmentMode")) : LLONG_MIN;
    DMLog([NSString stringWithFormat:@"[mswprobe] complete: transition request to environment mode %lld (%@) at +%d ms: %@%@", mode, NSStringFromClass([request class]), DMMSWProbeMs(), DMCall(request, @"succinctDescription"), DMTestFlag("/tmp/msw-stack") ? DMProbeStack() : @""]);
    inside = NO;
    o_MSWComplete(self, _cmd, request);
}
static id (*o_MSWRMEnd)(id, SEL, id);
static id DMMSWProbeRMEnd(id self, SEL _cmd, id event) {   // (Reduce Motion's home gesture: what its end does -- the response it returns)
    static BOOL inside = NO;
    id r = o_MSWRMEnd(self, _cmd, event);
    if (inside) return r;
    inside = YES;
    NSString *d = [[r description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    DMLog([NSString stringWithFormat:@"[mswprobe] Reduce Motion gesture end at +%d ms: destination %lld, response %@", DMMSWProbeMs(), DMMSWGestureFieldQ(self, @"currentFinalDestination"), d.length > 600 ? [d substringToIndex:600] : d]);
    inside = NO;
    return r;
}
static void DMMSWProbeHook(const char *cls, NSString *sel, NSString *types, IMP repl, IMP *orig) {
    Class c = objc_getClass(cls);
    if (!DMMSWHasMethod(c, sel, types)) { DMLog([NSString stringWithFormat:@"[mswprobe] not hooked: -[%s %@] missing or not %@", cls, sel, types]); return; }
    MSHookMessageEx(c, NSSelectorFromString(sel), repl, orig);
}
// ---- (debug, /tmp/msw-wsprobe) workspace transitions: every request SpringBoard executes (one line) and who asked -- what a Home press, a launch
// and the keyboard's / accessibility's App Switcher ask for (F8, M-4) ----
static NSString *DMNearestObjCMethod(uintptr_t a);   // (StatusBar.x, debug)
static NSString *DMMSWProbeStackN(int n) {
    NSMutableString *m = [NSMutableString string]; NSArray *ra = [NSThread callStackReturnAddresses];
    for (NSUInteger i = 1; i < MIN(ra.count, (NSUInteger)n + 1); i++) [m appendFormat:@"\n  %@", DMNearestObjCMethod((uintptr_t)ptrauth_strip((void *)[ra[i] unsignedLongValue], ptrauth_key_asia))];
    return m;
}
static BOOL (*o_MSWWSExec)(id, SEL, id, unsigned long long, id);
static BOOL DMMSWProbeWSExec(id self, SEL _cmd, id req, unsigned long long opts, id validator) {
    BOOL on = DMTestFlag("/tmp/msw-wsprobe");
    if (on) {
        NSString *d = [[req description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        while ([d rangeOfString:@"  "].location != NSNotFound) d = [d stringByReplacingOccurrencesOfString:@"  " withString:@" "];
        DMLog([NSString stringWithFormat:@"[mswws] execute (options %llu): %@%@", opts, d.length > 4000 ? [d substringToIndex:4000] : d, DMMSWProbeStackN(14)]);
    }
    CFTimeInterval t = CACurrentMediaTime();
    BOOL r = o_MSWWSExec(self, _cmd, req, opts, validator);
    if (on) DMLog([NSString stringWithFormat:@"[mswws] -> %d (%.1f ms)", r, (CACurrentMediaTime() - t) * 1000]);
    return r;
}
static void (*o_MSWOpenSwShortcut)(id, SEL, id), (*o_MSWExposeShortcut)(id, SEL, id);
static void DMMSWProbeOpenSwShortcut(id self, SEL _cmd, id arg) {
    if (DMTestFlag("/tmp/msw-wsprobe")) DMLog([NSString stringWithFormat:@"[mswws] the keyboard's App Switcher shortcut (%@)%@", arg, DMMSWProbeStackN(8)]);
    o_MSWOpenSwShortcut(self, _cmd, arg);
}
static void DMMSWProbeExposeShortcut(id self, SEL _cmd, id arg) {
    if (DMTestFlag("/tmp/msw-wsprobe")) DMLog([NSString stringWithFormat:@"[mswws] the keyboard's App Expose shortcut (%@)%@", arg, DMMSWProbeStackN(8)]);
    o_MSWExposeShortcut(self, _cmd, arg);
}
static void DMMSWInstallProbes(void) {
    static BOOL done = NO;
    if (done || DMCtorSkip("mswprobe")) return;
    done = YES;
    DMMSWProbeHook("SBFluidSwitcherGestureManager", @"_gestureTypeForGestureRecognizer:", @"q@:@", (IMP)DMMSWProbeGestureType, (IMP *)&o_MSWGestureType);
    DMMSWProbeHook("SBFluidSwitcherGestureManager", @"fluidSwitcherGestureTransaction:didBeginGesture:", @"v@:@@", (IMP)DMMSWProbeDidBegin, (IMP *)&o_MSWDidBegin);
    DMMSWProbeHook("SBFluidSwitcherGestureManager", @"fluidSwitcherGestureTransaction:didEndGesture:", @"v@:@@", (IMP)DMMSWProbeDidEnd, (IMP *)&o_MSWDidEnd);
    DMMSWProbeHook("SBFluidSwitcherGestureManager", @"fluidSwitcherGestureTransaction:didUpdateGesture:", @"v@:@@", (IMP)DMMSWProbeDidUpdate, (IMP *)&o_MSWDidUpdate);
    DMMSWProbeHook("SBHomeGestureFinalDestinationSwitcherModifier", @"currentFinalDestination", @"q@:", (IMP)DMMSWProbeFinalDest, (IMP *)&o_MSWFinalDest);
    DMMSWProbeHook("SBHomeGestureSwitcherModifier", @"_hasPausedEnoughForFlyIn", @"B@:", (IMP)DMMSWProbePaused, (IMP *)&o_MSWPaused);
    DMMSWProbeHook("SBHomeGestureSwitcherModifier", @"_responseForSBEventGestureEndWithEvent:finalDestination:", @"@@:@q", (IMP)DMMSWProbeEndResponse, (IMP *)&o_MSWEndResponse);
    if (DMMSWHasMethod(objc_getClass("SBFluidSwitcherGestureManager"), @"completeGestureWithTransitionRequest:", @"v@:@"))   // (iPadOS 15)
        DMMSWProbeHook("SBFluidSwitcherGestureManager", @"completeGestureWithTransitionRequest:", @"v@:@", (IMP)DMMSWProbeComplete, (IMP *)&o_MSWComplete);
    else if (DMMSWHasMethod(objc_getClass("SBMainSwitcherControllerCoordinator"), @"handleTransitionRequestForGestureComplete:", @"v@:@"))   // (iPadOS 16, as first read)
        DMMSWProbeHook("SBMainSwitcherControllerCoordinator", @"handleTransitionRequestForGestureComplete:", @"v@:@", (IMP)DMMSWProbeComplete, (IMP *)&o_MSWComplete);
    else DMMSWProbeHook("SBFluidSwitcherGestureManager", @"handleTransitionRequestForGestureComplete:", @"v@:@", (IMP)DMMSWProbeComplete, (IMP *)&o_MSWComplete);   // (iPadOS 17: the gesture manager's)
    DMMSWProbeHook("SBReduceMotionHomeGestureSwitcherModifier", @"_updateForGestureDidEndWithEvent:", @"@@:@", (IMP)DMMSWProbeRMEnd, (IMP *)&o_MSWRMEnd);
    DMMSWProbeHook("SBMainWorkspace", @"_executeTransitionRequest:options:validator:", @"B@:@Q@?", (IMP)DMMSWProbeWSExec, (IMP *)&o_MSWWSExec);
    DMMSWProbeHook("SpringBoard", @"_handleOpenAppSwitcherShortcut:", @"v@:@", (IMP)DMMSWProbeOpenSwShortcut, (IMP *)&o_MSWOpenSwShortcut);
    DMMSWProbeHook("SpringBoard", @"_handleActivateAppExposeKeyShortcut:", @"v@:@", (IMP)DMMSWProbeExposeShortcut, (IMP *)&o_MSWExposeShortcut);
    DMLog(@"[mswprobe] gesture probes installed");
}

// ---- debug test tool mswpath_<kind>_<x,y>_<x,y,ms[,ease]>...: a finger path sent from a background thread at the touch screen's own 120 Hz ----
// For timing the tracking, the touches must not depend on SpringBoard's main thread: the dragedge_ / dragmulti_ / dragpad_ steps are dispatched on
// it, and a busy main thread bunches them up, as a real finger never is. kind: e = one finger from the bottom edge (event-mask 0x800, as dragedge_),
// t = one plain finger, m<N> = N fingers side by side (70 pt apart), p<N> = N fingers on the hardware keyboard's trackpad (0..1 of its surface).
// The first waypoint is where the fingers go down (screen points as the user sees the screen; trackpad 0..1); each next one is reached in ms
// (ease 0 linear, 1 slowing down, 2 speeding up, 3 both); the same point again is a rest (the fingers stay down at a true zero velocity). The
// fingers lift at the last point.
static uint64_t DMTrackpadSenderID(void);   // (StatusBar.x, debug)
static void DMPadTouchN(uint64_t sender, const CGPoint *pts, int count, DMTouchPhase phase);   // (StatusBar.x, debug)
static void DMMSWRawTouch(const double *fx, const double *fy, int n, DMTouchPhase phase, uint32_t extraMask) {   // (fingers at native 0..1 places)
    static void *(*createHand)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, BOOL, BOOL, uint32_t) = NULL;
    static void *(*createFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double, double, double, BOOL, BOOL, uint32_t) = NULL;
    static void (*append)(void *, void *, uint32_t) = NULL;
    static void (*setInt)(void *, uint32_t, int) = NULL;
    static void (*setFloat)(void *, uint32_t, double) = NULL;
    static void (*setSender)(void *, uint64_t) = NULL;
    static void (*sysDispatch)(HIDClientRef2, void *) = NULL;
    static HIDClientRef2 client = NULL;
    static uint64_t sender = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{   // (first called on the main thread, by the set-up in DMMSWPath)
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        createHand = dlsym(iokit, "IOHIDEventCreateDigitizerEvent"); createFinger = dlsym(iokit, "IOHIDEventCreateDigitizerFingerEvent");
        append = dlsym(iokit, "IOHIDEventAppendEvent"); setInt = dlsym(iokit, "IOHIDEventSetIntegerValue"); setFloat = dlsym(iokit, "IOHIDEventSetFloatValue");
        setSender = dlsym(iokit, "IOHIDEventSetSenderID"); sysDispatch = dlsym(iokit, "IOHIDEventSystemClientDispatchEvent");
        HIDClientRef2 (*create)(CFAllocatorRef) = dlsym(iokit, "IOHIDEventSystemClientCreate");
        if (create) client = create(kCFAllocatorDefault);
        sender = DMTouchscreenSenderID(client);
    });
    if (!createHand || !createFinger || !append || !client || !sysDispatch || n < 1 || n > 5 || phase == DMTouchWarm) return;
    uint32_t mask; BOOL down;
    switch (phase) {
        case DMTouchDown: mask = 0x2 | 0x20; down = YES; break;
        case DMTouchMove: mask = 0x4 | 0x40; down = YES; break;
        default:          mask = 0x2 | 0x20; down = NO;  break;
    }
    mask |= extraMask;
    double cx = 0, cy = 0;
    for (int i = 0; i < n; i++) { cx += fx[i] / n; cy += fy[i] / n; }
    uint64_t now = mach_absolute_time();
    void *hand = createHand(kCFAllocatorDefault, now, 3, 0, 0, mask, 0, cx, cy, 0, 0, 0, NO, down, 0);
    if (!hand) return;
    if (setInt) setInt(hand, 0xb0019, 1);   // (display integrated: the touch screen)
    for (int i = 0; i < n; i++) {
        void *finger = createFinger(kCFAllocatorDefault, now, 2 + (uint32_t)i, 2 + (uint32_t)i, mask, fx[i], fy[i], 0, down ? 0.5 : 0, 0, down, down, 0);
        if (!finger) continue;
        if (setFloat) { setFloat(finger, 0xb0014, 0.04); setFloat(finger, 0xb0015, 0.04); }
        append(hand, finger, 0);
        CFRelease(finger);
    }
    if (setSender) setSender(hand, sender);
    sysDispatch(client, hand);
    CFRelease(hand);
}
// The pointer, as the hardware keyboard's trackpad moves it: relative pointer events sent AS the trackpad (its HID service's registry ID -- measured
// on the M1: backboardd moves the pointer by exactly the event's amount along the screen's axes as the user sees them); where backboardd has the
// pointer (BKSMousePointerService, the display's native portrait points). No click: a button inside a relative event begins a pointer touch that
// its release never ends (docs/ios15-second-desktop.md, a test-harness trap only a respring clears -- msw42's first pointer drag began, followed
// the pointer onto Desktop 2 and stayed held), and the trackpad's own button in an injected digitizer event is no click either (msw43: it came as
// a plain indirect trackpad touch). A real pointer drag reaches the view as SpringBoard's pointer touches (type 0, _isPointerTouch) -- the path
// the injected finger drags take.
static void DMMSWPointerEvent(uint64_t sender, double dx, double dy, uint32_t buttons) {
    static void *(*mk)(CFAllocatorRef, uint64_t, double, double, double, uint32_t, uint32_t) = NULL;
    static void (*setSender)(void *, uint64_t) = NULL;
    static void (*sysDispatch)(HIDClientRef2, void *) = NULL;
    static HIDClientRef2 client = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        mk = dlsym(iokit, "IOHIDEventCreateRelativePointerEvent"); setSender = dlsym(iokit, "IOHIDEventSetSenderID"); sysDispatch = dlsym(iokit, "IOHIDEventSystemClientDispatchEvent");
        HIDClientRef2 (*create)(CFAllocatorRef) = dlsym(iokit, "IOHIDEventSystemClientCreate");
        if (create) client = create(kCFAllocatorDefault);
    });
    if (!mk || !sysDispatch || !client) return;
    void *ev = mk(kCFAllocatorDefault, mach_absolute_time(), dx, dy, 0, buttons, 0);
    if (!ev) return;
    if (setSender && sender) setSender(ev, sender);
    sysDispatch(client, ev);
    CFRelease(ev);
}
static CGPoint DMMSWPointerNative(void) {
    id svc = DMCall(objc_getClass("BKSMousePointerService"), @"sharedInstance");
    if (!svc || !DMMSWHasMethod(object_getClass(svc), @"globalPointerPosition", @"{CGPoint=dd}@:")) return CGPointMake(NAN, NAN);
    return ((CGPoint (*)(id, SEL))objc_msgSend)(svc, NSSelectorFromString(@"globalPointerPosition"));
}
static CGPoint DMMSWNativeToScreen(CGPoint n, long orientation, CGSize native) {   // (the inverse of DMScreenToNative)
    switch (orientation) {
        case 3:  return CGPointMake(n.y, native.width - n.x);
        case 4:  return CGPointMake(native.height - n.y, n.x);
        case 2:  return CGPointMake(native.width - n.x, native.height - n.y);
        default: return n;
    }
}
// mswpath_h_...: the pointer hovers along the path (no button): to the first point, then at 120 Hz, each step aiming at the path's point from where
// backboardd has the pointer now (closed loop: pointer acceleration cannot pull it off the path).
static void DMMSWPointerPath(NSArray<NSValue *> *pts) {
    uint64_t sender = DMTrackpadSenderID();
    if (!sender || pts.count < 2) { DMLog(@"[mswpath] no trackpad (or no path): no pointer to drag"); return; }
    CGSize screen = [UIScreen mainScreen].bounds.size, native = CGSizeMake(MIN(screen.width, screen.height), MAX(screen.width, screen.height));
    long orient = DMRealInterfaceOrientation();
    NSUInteger count = pts.count;
    DMLog([NSString stringWithFormat:@"[mswpath] pointer: %lu steps (%.0f ms), hovering from %@ (trackpad sender 0x%llx)", (unsigned long)count, (count - 1) * 1000.0 / 120.0, NSStringFromCGPoint([pts[0] CGPointValue]), sender]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        const double step = 1000.0 / 120.0;
        CGPoint (^where)(void) = ^CGPoint {
            __block CGPoint n = CGPointMake(NAN, NAN);
            dispatch_sync(dispatch_get_main_queue(), ^{ n = DMMSWPointerNative(); });
            return DMMSWNativeToScreen(n, orient, native);
        };
        void (^toward)(CGPoint, uint32_t) = ^(CGPoint want, uint32_t buttons) {
            CGPoint at = where();
            double dx = want.x - at.x, dy = want.y - at.y;
            if (!isfinite(dx) || !isfinite(dy)) { dx = 0; dy = 0; }
            DMMSWPointerEvent(sender, MAX(-80.0, MIN(80.0, dx)), MAX(-80.0, MIN(80.0, dy)), buttons);
        };
        CGPoint first = [pts[0] CGPointValue];
        for (int i = 0; i < 60; i++) {   // (onto the first point, no button: at most 0.5 s)
            CGPoint at = where();
            if (hypot(first.x - at.x, first.y - at.y) < 1.0) break;
            toward(first, 0);
            usleep(8333);
        }
        CGPoint startAt = where();
        uint64_t t0 = mach_absolute_time();
        for (NSUInteger i = 1; i < count; i++) {
            mach_wait_until(t0 + (uint64_t)(i * step * 1e6 * tb.denom / tb.numer));
            toward([pts[i] CGPointValue], 0);
        }
        usleep(40000);
        CGPoint endAt = where();
        dispatch_async(dispatch_get_main_queue(), ^{ DMLog([NSString stringWithFormat:@"[mswpath] pointer hovered from %@ to %@ (the path: %@ -> %@)", NSStringFromCGPoint(startAt), NSStringFromCGPoint(endAt), NSStringFromCGPoint(first), NSStringFromCGPoint([pts.lastObject CGPointValue])]); });
    });
}
static void DMMSWPath(NSString *spec) {
    NSArray<NSString *> *q = [spec componentsSeparatedByString:@"_"];
    if (q.count < 3) { DMLog(@"[mswpath] usage: mswpath_<e|t|mN|pN|h>_<x,y>_<x,y,ms[,ease]>... (h: the pointer hovering)"); return; }
    NSString *kind = q[0];
    BOOL pad = [kind hasPrefix:@"p"], edge = [kind isEqualToString:@"e"];
    int fingers = ([kind hasPrefix:@"m"] || pad) ? MAX(1, MIN(5, [[kind substringFromIndex:1] intValue])) : 1;
    // the path, one point per 120 Hz step
    NSMutableArray<NSValue *> *pts = [NSMutableArray array];
    NSArray *first = [q[1] componentsSeparatedByString:@","];
    CGPoint at = CGPointMake([first[0] doubleValue], [first.count > 1 ? first[1] : @"0" doubleValue]);
    [pts addObject:[NSValue valueWithCGPoint:at]];
    const double step = 1000.0 / 120.0;
    for (NSUInteger i = 2; i < q.count; i++) {
        NSArray *w = [q[i] componentsSeparatedByString:@","];
        if (w.count < 3) continue;
        CGPoint to = CGPointMake([w[0] doubleValue], [w[1] doubleValue]);
        int ease = w.count > 3 ? [w[3] intValue] : 0, n = MAX(1, (int)lround([w[2] doubleValue] / step));
        for (int k = 1; k <= n; k++) {
            double s = (double)k / n;
            if (ease == 1) s = 1.0 - (1.0 - s) * (1.0 - s);
            else if (ease == 2) s = s * s;
            else if (ease == 3) s = s < 0.5 ? 2 * s * s : 1.0 - 2 * (1.0 - s) * (1.0 - s);
            [pts addObject:[NSValue valueWithCGPoint:CGPointMake(at.x + (to.x - at.x) * s, at.y + (to.y - at.y) * s)]];
        }
        at = to;
    }
    NSUInteger count = pts.count;
    if ([kind isEqualToString:@"h"]) { DMMSWPointerPath(pts); return; }   // (the pointer hovering, screen points)
    DMLog([NSString stringWithFormat:@"[mswpath] %@: %lu steps (%.0f ms), %d finger(s)%@", kind, (unsigned long)count, (count - 1) * step, fingers, pad ? @" on the trackpad" : edge ? @" from the bottom edge" : @""]);
    if (pad) {
        uint64_t sender = DMTrackpadSenderID();
        if (!sender) { DMLog(@"[mswpath] no trackpad: nothing sent"); return; }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            mach_timebase_info_data_t tb; mach_timebase_info(&tb);
            uint64_t t0 = mach_absolute_time();
            for (NSUInteger i = 0; i < count; i++) {
                mach_wait_until(t0 + (uint64_t)(i * step * 1e6 * tb.denom / tb.numer));
                CGPoint c = [pts[i] CGPointValue], p[5];
                for (int f = 0; f < fingers; f++) p[f] = CGPointMake(MIN(1.0, MAX(0.0, c.x + (f - (fingers - 1) / 2.0) * 0.12)), MIN(1.0, MAX(0.0, c.y)));
                DMPadTouchN(sender, p, fingers, i == 0 ? DMTouchDown : DMTouchMove);
                if (i == count - 1) { mach_wait_until(mach_absolute_time() + (uint64_t)(step * 1e6 * tb.denom / tb.numer)); DMPadTouchN(sender, p, fingers, DMTouchUp); }
            }
        });
        return;
    }
    // touch: every finger's place in the screen's native 0..1 space, worked out here on the main thread (UIKit), sent from the background
    CGSize screen = [UIScreen mainScreen].bounds.size, native = CGSizeMake(MIN(screen.width, screen.height), MAX(screen.width, screen.height));
    long orient = DMRealInterfaceOrientation();
    NSMutableData *fxy = [NSMutableData dataWithLength:count * fingers * 2 * sizeof(double)];
    double *v = fxy.mutableBytes;
    for (NSUInteger i = 0; i < count; i++) {
        CGPoint c = [pts[i] CGPointValue];
        for (int f = 0; f < fingers; f++) {
            CGPoint n = DMScreenToNative(CGPointMake(c.x + (f - (fingers - 1) / 2.0) * 70.0, c.y), orient, native);
            v[(i * fingers + f) * 2] = n.x / native.width; v[(i * fingers + f) * 2 + 1] = n.y / native.height;
        }
    }
    uint32_t extra = edge ? 0x800 : 0;
    DMMSWRawTouch(NULL, NULL, 0, DMTouchUp, 0);   // (the one-time set-up, here on the main thread)
    DMSysTouchReady(^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            const double *vv = fxy.bytes;
            mach_timebase_info_data_t tb; mach_timebase_info(&tb);
            uint64_t t0 = mach_absolute_time();
            double fx[5], fy[5];
            for (NSUInteger i = 0; i < count; i++) {
                mach_wait_until(t0 + (uint64_t)(i * step * 1e6 * tb.denom / tb.numer));
                for (int f = 0; f < fingers; f++) { fx[f] = vv[(i * fingers + f) * 2]; fy[f] = vv[(i * fingers + f) * 2 + 1]; }
                DMMSWRawTouch(fx, fy, fingers, i == 0 ? DMTouchDown : DMTouchMove, extra);
            }
            mach_wait_until(mach_absolute_time() + (uint64_t)(step * 1e6 * tb.denom / tb.numer));
            DMMSWRawTouch(fx, fy, fingers, DMTouchUp, extra);
            usleep(120000);
            DMMSWRawTouch(fx, fy, fingers, DMTouchUp, extra);   // (a second lift, as DMSysTouchSecondUp: a lone lift does nothing)
        });
    });
}

// ---- debug triggers: msw_open / msw_close / msw_pick_<n> / msw_plus / msw_state / msw_appswitcher / mswfind / mswportal_<1|0> ----
static UIWindow *gMSWProbeWindow;
static UIView *gMSWProbeRoot, *gMSWProbePortal;
static BOOL DMMSWTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"msw_open"]) DMMSWOpen(@"trigger");
    else if ([cmd isEqualToString:@"msw_close"]) DMMSWClose(nil, YES);
    else if ([cmd hasPrefix:@"msw_pick_"]) {
        NSInteger i = [[cmd substringFromIndex:9] integerValue];
        if (i >= 0 && i < (NSInteger)gMSWTiles.count) DMMSWClose(gMSWTiles[i], YES); else DMLog(@"[macswitcher] msw_pick: no such tile");
    }
    else if ([cmd isEqualToString:@"msw_plus"]) DMMSWPlusTapped();
    else if ([cmd hasPrefix:@"msw_move_"]) {   // msw_move_<tile>_<desktop place | new>: what a drag of that thumbnail onto that desktop (or "+") does, without the drag
        NSArray *a = [[cmd substringFromIndex:9] componentsSeparatedByString:@"_"];
        NSInteger i = a.count ? [a[0] integerValue] : -1;
        CGRect onto = a.count < 2 ? CGRectNull : [a[1] isEqualToString:@"new"] ? gMSWPlusRect : ([a[1] integerValue] >= 0 && [a[1] integerValue] < (NSInteger)gMSWDeskRects.count ? [gMSWDeskRects[[a[1] integerValue]] CGRectValue] : CGRectNull);
        if (!gMSWOpen || i < 0 || i >= (NSInteger)gMSWTiles.count || CGRectIsNull(onto)) DMLog(@"[macswitcher] msw_move: no such thumbnail or desktop (or the view is closed)");
        else if (!DMMSWDragAllowed(gMSWTiles[i])) DMLog(@"[macswitcher] msw_move: no drag here now (the Mac Switcher off, a slide, a turn, or a drag on its way)");
        else { DMMSWTile *t = gMSWTiles[i]; CGPoint c = CGPointMake(CGRectGetMidX(t.layoutRect), CGRectGetMidY(t.layoutRect)); DMMSWDragStart(t, c, c); DMMSWDragEnd(CGPointMake(CGRectGetMidX(onto), CGRectGetMidY(onto)), NO); }
    }
    else if ([cmd hasPrefix:@"msw_desk_"]) DMMSWSwitchTo((NSUInteger)[[cmd substringFromIndex:9] integerValue], @"trigger", nil);   // msw_desk_<place from 0>
    else if ([cmd hasPrefix:@"msw_remove_"]) DMMSWRemoveDesktop((NSUInteger)[[cmd substringFromIndex:11] integerValue]);
    else if ([cmd isEqualToString:@"msw_desks"]) {
        NSMutableString *o = [NSMutableString stringWithFormat:@"[macswitcher] desktops %@ current %@ (id %ld), away stages %lu, away native %lu, switching %d", [gMSWDesks componentsJoinedByString:@","], DMMSWDeskName(gMSWCur), (long)DMMSWCurId(), (unsigned long)gMSWAwayCount, (unsigned long)gMSWAwayNatives.count, gMSWSwitching];
        for (NSString *b in gMSWWinDesk) [o appendFormat:@"\n  %@ -> %@", b, gMSWWinDesk[b]];
        for (NSString *k in gMSWFullScreen) [o appendFormat:@"\n  full screen on id %@: %@", k, gMSWFullScreen[k]];
        for (UIView *st in DMAerialStagesAll()) [o appendFormat:@"\n  stage %@ hidden %d away %d minimized %d", DMStageBundle(st), st.hidden, [objc_getAssociatedObject(st, kMSWAwayKey) boolValue], DMStageMinimized(st)];
        DMLog(o);
    }
    else if ([cmd isEqualToString:@"msw_appswitcher"]) DMMSWShowAppSwitcher();
    else if ([cmd isEqualToString:@"mswkeys"]) {   // mswkeys: SpringBoard's key commands now (input, modifiers, action) -- the Control-arrows among them (read-only)
        NSMutableString *o = [NSMutableString stringWithString:@"[mswkey] SpringBoard's key commands:"];
        NSArray *cmds = [[UIApplication sharedApplication] keyCommands];
        for (UIKeyCommand *c in cmds) if ([c isKindOfClass:[UIKeyCommand class]]) [o appendFormat:@"\n  %@ mod 0x%lx -> %@%@", [c.input stringByReplacingOccurrencesOfString:@"\x1b" withString:@"<esc>"], (long)c.modifierFlags, NSStringFromSelector(c.action), c.discoverabilityTitle.length ? [NSString stringWithFormat:@" (%@)", c.discoverabilityTitle] : @""];
        DMLog(o);
    }
    else if ([cmd isEqualToString:@"mswax_switcher"]) {   // mswax_switcher: what AssistiveTouch / Back Tap / Voice Control / Switch Control's "App Switcher" asks SpringBoard for (M-4 test)
        Class h = objc_getClass("AXSpringBoardServerHelper");
        Method sm = h ? class_getClassMethod(h, NSSelectorFromString(@"sharedServerHelper")) : NULL;
        id helper = sm ? ((id (*)(id, SEL))objc_msgSend)(h, NSSelectorFromString(@"sharedServerHelper")) : nil;
        Method om = helper ? class_getInstanceMethod(object_getClass(helper), NSSelectorFromString(@"openAppSwitcherWithServerInstance:")) : NULL;
        NSString *enc = om ? DMMSWBareTypes(method_getTypeEncoding(om)) : nil;
        DMLog([NSString stringWithFormat:@"[mswax] accessibility helper %@, -openAppSwitcherWithServerInstance: %@", helper ? @"found" : @"NOT found", enc ?: @"missing"]);
        if ([enc isEqualToString:@"v@:@"]) ((void (*)(id, SEL, id))objc_msgSend)(helper, NSSelectorFromString(@"openAppSwitcherWithServerInstance:"), nil);
        else if ([enc isEqualToString:@"B@:@"]) ((BOOL (*)(id, SEL, id))objc_msgSend)(helper, NSSelectorFromString(@"openAppSwitcherWithServerInstance:"), nil);
    }
    else if ([cmd isEqualToString:@"mswmem"]) DMMSWFreePictures(@"trigger (as on memory pressure)");   // mswmem: what memory pressure does (M-5 test)
    else if ([cmd isEqualToString:@"mswmemwarn"]) [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:[UIApplication sharedApplication]];   // mswmemwarn: UIKit's memory warning, as posted
    else if ([cmd hasPrefix:@"mswside_"]) DMMSWSideRequest([[cmd substringFromIndex:8] integerValue] < 0 ? -1 : 1, 0, @"trigger");   // mswside_<-1|1>: a side swipe's / Control-arrow's request (redirects a running slide)
    else if ([cmd hasPrefix:@"mswquiet_"]) {   // mswquiet_<bundle|home>: one workspace transition without animation, as a switch asks (F8 test)
        NSString *a = [cmd substringFromIndex:9];
        DMMSWQuietTransition([a isEqualToString:@"home"] ? nil : a, @"trigger");
    }
    else if ([cmd hasPrefix:@"mswcut_"]) {   // mswcut_<n>: the screen's picture (without waiting), the n-th current window cut out of it, shown in the probe corner for 6 s (F5)
        NSArray<UIView *> *st = DMAerialStages();
        NSInteger i = [[cmd substringFromIndex:7] integerValue];
        UIView *src = i >= 0 && i < (NSInteger)st.count ? st[i] : nil;
        if (!src) { DMLog(@"[mswpic] no such window"); return YES; }
        CGRect r = [src convertRect:src.bounds toCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
        DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], ^(UIView *pic, double ms) {
            UIView *c = pic ? DMMSWCutOut(pic, r) : nil;
            DMLog([NSString stringWithFormat:@"[mswpic] cut-out of %@ at %@: %@ (screen picture %.1f ms)", DMStageBundle(src), NSStringFromCGRect(r), c ? NSStringFromCGRect(c.bounds) : @"none", ms]);
            if (!c) return;
            if (!gMSWProbeWindow) {
                gMSWProbeWindow = ((id (*)(id, SEL, id, id))objc_msgSend)([objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarPortalProbe");
                gMSWProbeWindow.userInteractionEnabled = NO; gMSWProbeWindow.backgroundColor = [UIColor clearColor];
            }
            gMSWProbeWindow.windowLevel = kMenuWindowLevel - 0.25;
            gMSWProbeWindow.hidden = NO;
            UIView *root = [UIView new];
            [gMSWProbeWindow addSubview:root];
            DMMSWTurnIn(gMSWProbeWindow, root);
            CGFloat k = MIN(420.0 / MAX(1, c.bounds.size.width), 300.0 / MAX(1, c.bounds.size.height));
            c.transform = CGAffineTransformMakeScale(k, k);
            c.center = CGPointMake(root.bounds.size.width - 230, root.bounds.size.height - 170);
            c.layer.borderColor = [UIColor magentaColor].CGColor; c.layer.borderWidth = 3.0 / k;
            [root addSubview:c];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [root removeFromSuperview]; gMSWProbeWindow.hidden = YES; });
        });
    }
    else if ([cmd isEqualToString:@"mswpics"] || [cmd isEqualToString:@"mswopenshot"] || [cmd hasPrefix:@"mswshot_"]) {   // mswpics: the screen's picture asked without waiting (our window left out);
        // mswopenshot: the open view's picture of the desktop under it -- each shown in the probe corner (over the view) for 6 s (F5)
        void (^show)(UIView *, double) = ^(UIView *pic, double ms) {
            DMLog([NSString stringWithFormat:@"[mswpic] screen: %@ after %.1f ms", pic ? NSStringFromCGRect(pic.bounds) : @"none", ms]);
            if (!pic) return;
            if (!gMSWProbeWindow) {
                gMSWProbeWindow = ((id (*)(id, SEL, id, id))objc_msgSend)([objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarPortalProbe");
                gMSWProbeWindow.userInteractionEnabled = NO; gMSWProbeWindow.backgroundColor = [UIColor clearColor];
            }
            gMSWProbeWindow.windowLevel = kMenuWindowLevel - 0.25;   // (over the Mac Switcher's view)
            gMSWProbeWindow.hidden = NO;
            UIView *root = [UIView new];
            [gMSWProbeWindow addSubview:root];
            DMMSWTurnIn(gMSWProbeWindow, root);
            [pic removeFromSuperview];
            UIView *holder = [[UIView alloc] initWithFrame:pic.bounds];
            [holder addSubview:pic]; pic.transform = CGAffineTransformIdentity; pic.frame = holder.bounds;
            CGFloat k = MIN(460.0 / MAX(1, pic.bounds.size.width), 330.0 / MAX(1, pic.bounds.size.height));
            holder.transform = CGAffineTransformMakeScale(k, k);
            holder.center = CGPointMake(root.bounds.size.width - 250, root.bounds.size.height - 185);
            holder.layer.borderColor = [UIColor greenColor].CGColor; holder.layer.borderWidth = 3.0 / k;
            [root addSubview:holder];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [root removeFromSuperview]; gMSWProbeWindow.hidden = YES; });
        };
        if ([cmd isEqualToString:@"mswopenshot"]) { UIView *o = gMSWOpenShot; if (!o) DMLog(@"[mswpic] no open picture"); else { UIView *copy = [[UIView alloc] initWithFrame:o.bounds]; copy.layer.contents = o.layer.contents; if (!copy.layer.contents) { DMLog(@"[mswpic] the open picture has no plain contents (a UIKit picture): not shown"); } else show(copy, 0); } return YES; }
        if ([cmd hasPrefix:@"mswshot_"]) {   // mswshot_<desktop id>: that desktop's kept picture (its thumbnail, and the slide's picture of it) in the probe corner for 6 s
            NSInteger did = [[cmd substringFromIndex:8] integerValue];
            UIView *o = gMSWShots[@(did)];
            if (!o) { DMLog([NSString stringWithFormat:@"[mswpic] desktop %ld: no kept picture (drawn from its parts)", (long)did]); return YES; }
            UIView *copy = [[UIView alloc] initWithFrame:o.bounds]; copy.layer.contents = o.layer.contents;
            DMLog([NSString stringWithFormat:@"[mswpic] desktop %ld's kept picture: %@, %@, %lu window(s) then", (long)did, NSStringFromCGRect(o.bounds), copy.layer.contents ? @"plain contents" : @"a UIKit picture (not shown)", (unsigned long)gMSWShotSet[@(did)].count]);
            if (copy.layer.contents) show(copy, 0);
            return YES;
        }
        BOOL asked = DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], show);
        DMLog([NSString stringWithFormat:@"[mswpic] screen picture %@", asked ? @"asked" : @"could not be asked"]);
    }
    else if ([cmd hasPrefix:@"mswswwatch_"]) {   // mswswwatch_<ms>: every 50 ms for <ms>, SpringBoard's switcher windows -- hidden, alpha, the opacity drawn now, how many of
        // their layers have animations running -- and SpringBoard's idle reading (K-1: what is still on screen when the slide's reveal uncovers it)
        double ms = MAX(100.0, [[cmd substringFromIndex:11] doubleValue]);
        CFTimeInterval t0 = CACurrentMediaTime();
        __block void (^tick)(void);
        tick = ^{
            NSMutableString *o = [NSMutableString stringWithFormat:@"[swwatch] +%.0f idle %d switcher %d:", (CACurrentMediaTime() - t0) * 1000.0, DMMSWSpringBoardIdle(), DMSwitcherVisible()];
            for (UIWindow *w in DMAllWindows()) {
                NSString *cn = NSStringFromClass([w class]);
                if (![cn containsString:@"Switcher"] && ![cn containsString:@"HomeScreen"]) continue;
                NSInteger anim = 0, layers = 0; CGFloat minOp = 1.0;
                NSMutableArray<CALayer *> *stack = [NSMutableArray arrayWithObject:w.layer];
                while (stack.count && layers < 4000) {
                    CALayer *l = stack.lastObject; [stack removeLastObject]; layers++;
                    if (l.animationKeys.count) anim++;
                    CALayer *pl = l.presentationLayer; if (pl && pl.opacity < minOp && l.sublayers.count) minOp = pl.opacity;
                    if (l.sublayers) [stack addObjectsFromArray:l.sublayers];
                }
                CALayer *wp = w.layer.presentationLayer ?: w.layer;
                [o appendFormat:@" %@ hidden %d alpha %.2f drawn %.2f, %ld/%ld animating", cn, w.hidden, w.alpha, wp.opacity, (long)anim, (long)layers];
            }
            DMLog(o);
            if ((CACurrentMediaTime() - t0) * 1000.0 < ms) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), tick);
            else tick = nil;
        };
        tick();
    }
    else if ([cmd isEqualToString:@"mswctx"]) {   // mswctx: the screen's visible windows in the order a screen picture lists them (class, level, context id), and the
        // render server's snapshot modes this iPadOS has (K-1: which windows a picture "without our window" really leaves out)
        NSArray *wins = ((id (*)(id, SEL, BOOL, BOOL, id))objc_msgSend)([UIWindow class], NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:forScreen:"), YES, YES, [UIScreen mainScreen]);
        NSMutableString *o = [NSMutableString stringWithFormat:@"[mswctx] %lu visible windows (ours %p, level %.1f):", (unsigned long)wins.count, gMSWWindow, gMSWWindow.windowLevel];
        for (UIWindow *w in wins) {
            id c = DMCall(w.layer, @"context");
            uint32_t cid = c ? ((uint32_t (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"contextId")) : 0;
            [o appendFormat:@"\n  %@ level %.1f context %u%@", NSStringFromClass([w class]), w.windowLevel, cid, w == gMSWWindow ? @" (OURS)" : @""];
        }
        for (NSString *k in @[@"kCASnapshotModeStopAfterContextList", @"kCASnapshotModeExcludeContextList", @"kCASnapshotModeIncludeContextList", @"kCASnapshotModeLayer", @"kCASnapshotModeDisplay", @"kCASnapshotContextList", @"kCASnapshotExcludeContextList", @"kCASnapshotIncludeContextList"])
            [o appendFormat:@"\n  %@ = %@", k, DMMSWSnapConst(k.UTF8String) ?: @"(none)"];
        DMLog(o);
    }
    else if ([cmd isEqualToString:@"mswwithout"]) {   // mswwithout: UIKit's own picture of the screen without our window (DMMSWScreenWithoutView, waiting), in the probe corner for 6 s
        CFTimeInterval t0 = CACurrentMediaTime();
        UIView *pic = DMMSWScreenWithoutView();
        DMLog([NSString stringWithFormat:@"[mswpic] UIKit's screen without our window: %@ (%.1f ms)", pic ? NSStringFromCGRect(pic.bounds) : @"none", (CACurrentMediaTime() - t0) * 1000.0]);
        if (pic) {
            if (!gMSWProbeWindow) {
                gMSWProbeWindow = ((id (*)(id, SEL, id, id))objc_msgSend)([objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarPortalProbe");
                gMSWProbeWindow.userInteractionEnabled = NO; gMSWProbeWindow.backgroundColor = [UIColor clearColor];
            }
            gMSWProbeWindow.windowLevel = kMenuWindowLevel - 0.25; gMSWProbeWindow.hidden = NO;
            UIView *root = [UIView new]; [gMSWProbeWindow addSubview:root]; DMMSWTurnIn(gMSWProbeWindow, root);
            UIView *holder = [[UIView alloc] initWithFrame:pic.bounds]; [holder addSubview:pic]; pic.frame = holder.bounds;
            CGFloat k = MIN(460.0 / MAX(1, pic.bounds.size.width), 330.0 / MAX(1, pic.bounds.size.height));
            holder.transform = CGAffineTransformMakeScale(k, k); holder.center = CGPointMake(root.bounds.size.width - 250, root.bounds.size.height - 185);
            holder.layer.borderColor = [UIColor magentaColor].CGColor; holder.layer.borderWidth = 3.0 / k;
            [root addSubview:holder];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [root removeFromSuperview]; gMSWProbeWindow.hidden = YES; });
        }
    }
    else if ([cmd hasPrefix:@"mswburst_"]) {   // mswburst_<n>_<every ms>[_<delay ms>]: n pictures of the whole screen (nothing left out, asked without waiting -- the
        // main thread is not held, a slide keeps its timing), one every <every> ms from <delay> ms on; then shown side by side in the probe window for 12 s
        // with their times (K-1: what a trip between desktops shows, frame by frame)
        NSArray *q = [[cmd substringFromIndex:9] componentsSeparatedByString:@"_"];
        NSInteger n = q.count > 0 ? MIN(12, MAX(1, [q[0] integerValue])) : 8;
        double every = q.count > 1 ? MAX(8.0, [q[1] doubleValue]) : 60.0, delay = q.count > 2 ? MAX(0.0, [q[2] doubleValue]) : 0.0;
        NSMutableArray *pics = [NSMutableArray array], *times = [NSMutableArray array];
        for (NSInteger i = 0; i < n; i++) { [pics addObject:[NSNull null]]; [times addObject:@0]; }
        for (UIView *older in [gMSWProbeWindow.subviews copy]) [older removeFromSuperview];   // (an earlier grid is never in these pictures)
        gMSWProbeWindow.hidden = YES;
        __block NSInteger left = n;
        CFTimeInterval t0 = CACurrentMediaTime();
        void (^showAll)(void) = ^{
            if (!gMSWProbeWindow) {
                gMSWProbeWindow = ((id (*)(id, SEL, id, id))objc_msgSend)([objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarPortalProbe");
                gMSWProbeWindow.userInteractionEnabled = NO; gMSWProbeWindow.backgroundColor = [UIColor clearColor];
            }
            gMSWProbeWindow.windowLevel = kMenuWindowLevel - 0.25;
            gMSWProbeWindow.hidden = NO;
            UIView *root = [UIView new];
            [gMSWProbeWindow addSubview:root];
            DMMSWTurnIn(gMSWProbeWindow, root);
            root.backgroundColor = [UIColor blackColor];
            CGSize b = root.bounds.size;
            NSInteger cols = n <= 4 ? n : (n + 1) / 2, rows = n <= 4 ? 1 : 2;
            CGFloat cw = b.width / cols, ch = b.height / rows;
            for (NSInteger i = 0; i < n; i++) {
                UIView *pic = pics[i] == [NSNull null] ? nil : pics[i];
                CGRect cell = CGRectMake((i % cols) * cw, (i / cols) * ch, cw, ch);
                UIView *holder = [[UIView alloc] initWithFrame:CGRectInset(cell, 3, 3)];
                holder.clipsToBounds = YES; holder.layer.borderColor = [UIColor greenColor].CGColor; holder.layer.borderWidth = 1.0;
                if (pic) {
                    [pic removeFromSuperview];
                    CGFloat k = MIN(holder.bounds.size.width / MAX(1, pic.bounds.size.width), holder.bounds.size.height / MAX(1, pic.bounds.size.height));
                    pic.transform = CGAffineTransformMakeScale(k, k);
                    pic.center = CGPointMake(holder.bounds.size.width / 2.0, holder.bounds.size.height / 2.0);
                    [holder addSubview:pic];
                }
                UILabel *l = DMMSWLabel([NSString stringWithFormat:@"%ld: %.0f ms", (long)i, [times[i] doubleValue]], 12.0, UIFontWeightBold);
                l.frame = CGRectMake(4, 4, 120, 16); l.textAlignment = NSTextAlignmentLeft;
                [holder addSubview:l];
                [root addSubview:holder];
            }
            for (UIView *older in [gMSWProbeWindow.subviews copy]) if (older != root) [older removeFromSuperview];   // (only the newest grid)
            DMLog([NSString stringWithFormat:@"[mswburst] %ld pictures shown (times %@ ms)", (long)n, [times componentsJoinedByString:@","]]);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [root removeFromSuperview]; if (!gMSWProbeWindow.subviews.count) gMSWProbeWindow.hidden = YES; });
        };
        for (NSInteger i = 0; i < n; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay + i * every) * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                double at = (CACurrentMediaTime() - t0) * 1000.0;
                BOOL asked = DMMSWScreenPictureAsync(@[], ^(UIView *pic, double ms) {
                    if (pic) pics[i] = pic;
                    times[i] = @(at);
                    if (--left == 0) showAll();
                });
                if (!asked && --left == 0) showAll();
            });
        }
        DMLog([NSString stringWithFormat:@"[mswburst] %ld pictures, every %.0f ms from %.0f ms", (long)n, every, delay]);
    }
    else if ([cmd hasPrefix:@"mswpic_"]) {   // mswpic_<n>: a picture of the n-th current window asked without waiting (F5); shown in the probe corner for 6 s
        NSArray<UIView *> *st = DMAerialStages();
        NSInteger i = [[cmd substringFromIndex:7] integerValue];
        UIView *src = i >= 0 && i < (NSInteger)st.count ? st[i] : nil;
        if (!src) { DMLog(@"[mswpic] no such window"); return YES; }
        NSString *b = DMStageBundle(src);
        CFTimeInterval t0 = CACurrentMediaTime();
        BOOL asked = DMMSWPictureAsync(src, ^(UIView *pic, double ms) {
            DMLog([NSString stringWithFormat:@"[mswpic] %@: %@ after %.1f ms", b, pic ? [NSString stringWithFormat:@"picture %@ contents %@", NSStringFromCGRect(pic.bounds), NSStringFromClass([pic.layer.contents class])] : @"none", ms]);
            if (!pic) return;
            if (!gMSWProbeWindow) {
                gMSWProbeWindow = ((id (*)(id, SEL, id, id))objc_msgSend)([objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarPortalProbe");
                gMSWProbeWindow.windowLevel = kMenuWindowLevel - 0.5; gMSWProbeWindow.userInteractionEnabled = NO; gMSWProbeWindow.backgroundColor = [UIColor clearColor];
            }
            gMSWProbeWindow.hidden = NO;
            UIView *root = [UIView new];
            [gMSWProbeWindow addSubview:root];
            DMMSWTurnIn(gMSWProbeWindow, root);
            CGFloat k = MIN(420.0 / MAX(1, pic.bounds.size.width), 300.0 / MAX(1, pic.bounds.size.height));
            pic.transform = CGAffineTransformMakeScale(k, k);
            pic.center = CGPointMake(root.bounds.size.width - 230, root.bounds.size.height - 170);
            pic.layer.borderColor = [UIColor greenColor].CGColor; pic.layer.borderWidth = 3.0 / k;
            [root addSubview:pic];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [root removeFromSuperview]; gMSWProbeWindow.hidden = YES; DMLog(@"[mswpic] probe picture removed"); });
        });
        DMLog([NSString stringWithFormat:@"[mswpic] %@: %@ (%.2f ms on the main thread)", b, asked ? @"asked" : @"could not be asked", (CACurrentMediaTime() - t0) * 1000]);
    }
    else if ([cmd hasPrefix:@"mswpath_"]) DMMSWPath([cmd substringFromIndex:8]);   // (measurement: a finger path at a steady 120 Hz, see DMMSWPath)
    else if ([cmd isEqualToString:@"msworig"]) {   // msworig: where the original code behind our gesture hooks is (for reading it in a disassembly; read-only)
        NSDictionary *o = @{ @"_hasPausedEnoughForFlyIn (probe)": [NSValue valueWithPointer:(void *)o_MSWPaused], @"_hasPausedEnoughForFlyIn (fix)": [NSValue valueWithPointer:(void *)o_MSWFlyIn],
                             @"_responseForActivatingFinalDestination: (fix)": [NSValue valueWithPointer:(void *)o_MSWActivate], @"_responseForSBEventGestureEndWithEvent:finalDestination: (probe)": [NSValue valueWithPointer:(void *)o_MSWEndResponse],
                             @"FD currentFinalDestination (probe)": [NSValue valueWithPointer:(void *)o_MSWFinalDest],
                             @"completion (fix)": [NSValue valueWithPointer:(void *)o_MSWComplete15], @"completion (probe)": [NSValue valueWithPointer:(void *)o_MSWComplete],
                             @"didBegin": [NSValue valueWithPointer:(void *)o_MSWDidBegin], @"didEnd": [NSValue valueWithPointer:(void *)o_MSWDidEnd], @"gestureType": [NSValue valueWithPointer:(void *)o_MSWGestureType] };
        NSMutableString *out = [NSMutableString stringWithString:@"[msworig]"];
        for (NSString *k in o) {
            void *p = ptrauth_strip([o[k] pointerValue], ptrauth_key_function_pointer);
            Dl_info d; memset(&d, 0, sizeof d); if (p) dladdr(p, &d);
            [out appendFormat:@"\n  %@: %p (%s)", k, p, d.dli_fname ? strrchr(d.dli_fname, '/') + 1 : "-"];
        }
        DMLog(out);
    }
    else if ([cmd isEqualToString:@"msw_state"]) {
        NSMutableString *s = [NSMutableString stringWithFormat:@"[macswitcher] state: on %d, open %d, window %@ level %.1f hidden %d, root %@, portals %lu, desk %@, plus %@", gMSWOn, DMMSWIsOpen(), gMSWWindow ? NSStringFromClass([gMSWWindow class]) : @"-", gMSWWindow.windowLevel, gMSWWindow.hidden, gMSWRoot ? NSStringFromCGRect(gMSWRoot.bounds) : @"-", (unsigned long)gMSWPortals.count, NSStringFromCGRect(gMSWDeskRect), NSStringFromCGRect(gMSWPlusRect)];
        NSUInteger i = 0;
        for (DMMSWTile *t in gMSWTiles) {
            CGRect onScreen = gMSWRoot ? [gMSWRoot convertRect:t.layoutRect toCoordinateSpace:[UIScreen mainScreen].coordinateSpace] : CGRectNull;
            [s appendFormat:@"\n  %lu: %@ (%ld) from %@ -> %@ (screen %@)", (unsigned long)i++, t.title, (long)t.kind, NSStringFromCGRect(t.sourceRect), NSStringFromCGRect(t.layoutRect), NSStringFromCGRect(onScreen)];
        }
        for (NSUInteger d = 0; gMSWRoot && d < gMSWDeskRects.count; d++)   // (the strip, in screen points as the user sees them: where to drag to)
            [s appendFormat:@"\n  desktop %lu: screen %@", (unsigned long)d, NSStringFromCGRect([gMSWRoot convertRect:[gMSWDeskRects[d] CGRectValue] toCoordinateSpace:[UIScreen mainScreen].coordinateSpace])];
        if (gMSWRoot && !CGRectIsNull(gMSWPlusRect)) [s appendFormat:@"\n  plus: screen %@", NSStringFromCGRect([gMSWRoot convertRect:gMSWPlusRect toCoordinateSpace:[UIScreen mainScreen].coordinateSpace])];
        DMLog(s);
    }
    else if ([cmd isEqualToString:@"mswfind"]) {
        SBApplication *front = DMFrontApp();
        DMLog([NSString stringWithFormat:@"[macswitcher] front %@, full screen in front %d", [front bundleIdentifier], DMFullScreenAppInFront()]);
        UIView *v = DMMSWFullScreenView([front bundleIdentifier], YES);
        DMLog([NSString stringWithFormat:@"[macswitcher] full-screen view: %@", v ? [NSString stringWithFormat:@"%@ %p", NSStringFromClass([v class]), v] : @"none"]);
    }
    else if ([cmd hasPrefix:@"mswportal_"]) {   // the portal probe: one live portal of the front window in the bottom-right corner
        if (gMSWProbePortal) DMMSWPortalLetGo(gMSWProbePortal);
        gMSWProbePortal = nil;
        [gMSWProbeRoot removeFromSuperview]; gMSWProbeRoot = nil;
        gMSWProbeWindow.hidden = YES;
        NSString *arg = [cmd substringFromIndex:10];
        if ([arg isEqualToString:@"0"]) { DMLog(@"[mswprobe] portal probe removed"); return YES; }
        UIView *src = nil;
        if (![arg isEqualToString:@"1"]) for (UIWindow *w in DMAllWindows()) if ([NSStringFromClass([w class]) isEqualToString:arg] && !w.hidden) src = w;   // (mswportal_<window class>)
        if (!src) src = gNativeActive ?: DMTopStage();
        SBApplication *front = DMFrontApp();
        if (!src && front && DMFullScreenAppInFront()) src = DMMSWFullScreenView([front bundleIdentifier], NO);
        if (!src) for (UIWindow *w in DMAllWindows()) if ([NSStringFromClass([w class]) isEqualToString:@"SBHomeScreenWindow"]) src = w;
        if (!DMMSWSelfCheck() || !src) { DMLog(@"[mswprobe] portal probe: nothing to show"); return YES; }
        if (!gMSWProbeWindow) {
            gMSWProbeWindow = ((id (*)(id, SEL, id, id))objc_msgSend)([objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") alloc], NSSelectorFromString(@"initWithRole:debugName:"), @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarPortalProbe");
            gMSWProbeWindow.windowLevel = kMenuWindowLevel - 0.5;
            gMSWProbeWindow.userInteractionEnabled = NO;   // (touches go to the windows below)
            gMSWProbeWindow.backgroundColor = [UIColor clearColor];
        }
        gMSWProbeWindow.hidden = NO;
        UIView *root = [UIView new];
        [gMSWProbeWindow addSubview:root];
        gMSWProbeRoot = root;
        DMMSWTurnIn(gMSWProbeWindow, root);
        UIView *inner = [[UIView alloc] initWithFrame:root.bounds];
        CGRect r = CGRectNull;
        UIView *p = DMMSWPortalInPlace(src, root, inner, &r);
        gMSWProbePortal = p;
        CGRect slot = CGRectMake(root.bounds.size.width - 340, root.bounds.size.height - 300, 320, 220);
        CGFloat s = MIN(slot.size.width / MAX(1, r.size.width), slot.size.height / MAX(1, r.size.height));
        CGRect to = CGRectMake(CGRectGetMaxX(slot) - r.size.width * s, CGRectGetMaxY(slot) - r.size.height * s, r.size.width * s, r.size.height * s);
        [root addSubview:inner];
        if (p) DMMSWPlace(inner, r, to);
        UIView *frame = [[UIView alloc] initWithFrame:CGRectInset(to, -2, -2)];
        frame.layer.borderColor = [UIColor redColor].CGColor; frame.layer.borderWidth = 2;
        [root addSubview:frame];
        DMLog([NSString stringWithFormat:@"[mswprobe] portal probe: %@ of %@ %p (window %@), on screen %@ -> shown at %@; portal layer %@", p ? NSStringFromClass([p class]) : @"NO portal", NSStringFromClass([src class]), src, NSStringFromClass([src.window class]), NSStringFromCGRect(r), NSStringFromCGRect(to), p ? NSStringFromClass([DMCall(p, @"portalLayer") class]) : @"-"]);
        [gMSWPortals removeObjectIdenticalTo:p];   // (not the open view's)
    }
    else return NO;
    return YES;
}
#endif
