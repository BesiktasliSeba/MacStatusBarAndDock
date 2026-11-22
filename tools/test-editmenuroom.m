// tools/test-editmenuroom.m: Mac test (Mac Catalyst) of the edit menu's keyboard room in a turned SpringBoard (1.8.8.2), run by
// test-editmenuroom.sh. The real statusbar/EditMenuRoom.h (a copy whose UIKit class names point at the stand-ins below) on models of UIKit's
// two shapes of the insets method, transcribed from UIKit's code: iPadOS 16.7.7's -[_UIEditMenuPresentation
// _preferredContentInsetsForContainerView] (read on an iPad) and the iOS 18 code base's -[_UIEditMenuContentPresentation
// _preferredContentInsetsForContainerViewWithConfiguration:] (read in the Mac's own Mac Catalyst UIKit), with a keyboard scene delegate whose
// visibleInputViewFrameInView: converts as UIKit's does (from the screen's space into view.window.windowScene.coordinateSpace, never into the
// view), and a window scene whose space is the screen's fixed portrait space, turned against the interface as SpringBoard's is.
// One scenario per process (the hook goes in once): main (the values), skip (the crash guard's piece), badksd (a UIKit call of another shape),
// bad16 (16's method of another shape), no18 (no 18 shape), mid17 (16's method shape on 18's class). Prints PASS / FAIL lines.
// The review's two guards (1.8.8.2 B75 review): a container on another display (the TV) keeps UIKit's answer, and so does an answer UIKit made
// another way than its keyboard formula on the frame it read (a guard of an iPadOS this fix has not read, or another tweak's change to it).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

static NSMutableArray<NSString *> *gLog;
#if DEBUG
#define DMLog(...) [gLog addObject:(__VA_ARGS__)]
static NSMutableSet<NSString *> *gFlags;
#define DMTestFlag(path) [gFlags containsObject:@(path)]
#else
#define DMLog(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#define DMTestFlag(path) 0
#endif
static int gMarks;
#define DM_FEATURE_MARK(name) do { gMarks++; } while (0)
static int gSkip; static char gSkipAsked[64];
static int MSBDCrashSkipped(const char *name) { snprintf(gSkipAsked, sizeof gSkipAsked, "%s", name); return gSkip; }
static int gHooks;
static void MSHookMessageEx(Class c, SEL s, IMP imp, IMP *orig) { gHooks++; Method m = class_getInstanceMethod(c, s); *orig = m ? method_setImplementation(m, imp) : NULL; }
#include "cut-sig.h"        // (DMSMNormEncoding, DMSMExpect, DMSMSigOfMethod: cut out of statusbar/SMEngineAPI.h)
#include "EditMenuRoom.h"   // (the real one, its UIKit class names pointed at the stand-ins)

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)

// ---- the world: an interface (the window's space) and the scene's space, a quarter turn k apart ----
@interface TSpace : NSObject <UICoordinateSpace>
@property (nonatomic) CGAffineTransform toSpace;   // (the interface's points -> this space's)
@property (nonatomic) CGRect spaceBounds;
@end
@implementation TSpace
- (CGRect)bounds { return self.spaceBounds; }
static CGRect TToInterface(id<UICoordinateSpace> s, CGRect r) {
    if ([(id)s isKindOfClass:[TSpace class]]) return CGRectApplyAffineTransform(r, CGAffineTransformInvert(((TSpace *)s).toSpace));
    if ([(id)s isKindOfClass:[UIView class]]) return [(UIView *)s convertRect:r toView:nil];
    return CGRectNull;
}
static CGRect TFromInterface(id<UICoordinateSpace> s, CGRect r) {
    if ([(id)s isKindOfClass:[TSpace class]]) return CGRectApplyAffineTransform(r, ((TSpace *)s).toSpace);
    if ([(id)s isKindOfClass:[UIView class]]) return [(UIView *)s convertRect:r fromView:nil];
    return CGRectNull;
}
- (CGRect)convertRect:(CGRect)r toCoordinateSpace:(id<UICoordinateSpace>)o { return TFromInterface(o, TToInterface(self, r)); }
- (CGRect)convertRect:(CGRect)r fromCoordinateSpace:(id<UICoordinateSpace>)o { return TFromInterface(self, TToInterface(o, r)); }
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id<UICoordinateSpace>)o { return [self convertRect:CGRectMake(p.x, p.y, 0, 0) toCoordinateSpace:o].origin; }
- (CGPoint)convertPoint:(CGPoint)p fromCoordinateSpace:(id<UICoordinateSpace>)o { return [self convertRect:CGRectMake(p.x, p.y, 0, 0) fromCoordinateSpace:o].origin; }
@end
@interface TScene : NSObject
@property (nonatomic, strong) TSpace *coordinateSpace;
@end
@implementation TScene
@end

static TSpace *gScreenSpace;   // (the screen's coordinate space: the interface's)
static TScene *gScene;         // (the window's scene; nil: none)
static BOOL gSceneOn;          // (the window answers with gScene only while a menu is measured: UIKit's own window code never sees it)
static BOOL gRemote, gTextEffects = YES;
static BOOL gOtherScreen;          // (the window is on another display while a menu is measured: the TV)
static NSObject *gTV;              // (that display: any other object than the main screen)
static UIEdgeInsets gSafe;
@interface TWindow : UIWindow
@end
@implementation TWindow
- (BOOL)_isRemoteKeyboardWindow { return gRemote; }
- (BOOL)_isTextEffectsWindow { return gTextEffects; }
- (UIWindowScene *)windowScene { return gSceneOn ? (UIWindowScene *)gScene : [super windowScene]; }
- (UIScreen *)screen { return !gSceneOn ? [super screen] : gOtherScreen ? (UIScreen *)gTV : [UIScreen mainScreen]; }   // (the iPad's own screen, or the TV)
@end
@interface TContainer : UIView
@end
@implementation TContainer
- (UIEdgeInsets)safeAreaInsets { return gSafe; }
@end

// ---- UIKit's keyboard scene delegate, as its methods behave (visibleInputViewFrameInView: added per scenario: its shape is a check) ----
static BOOL gKSDOn = YES, gOnScreen = YES, gUndocked;
static CGRect gKeyboard;          // (the keyboard's frame in the screen's space: the interface's)
static double gOtherOverlap = 100.0;
static BOOL gUnknownGuard;        // (the review's: UIKit returns the safe area only, by a guard this fix has not read)
static double gTweakAdds;         // (the review's: added to UIKit's bottom inset, as another tweak's hook under ours would)
@interface TKeyboardSceneDelegate : NSObject
@end
static TKeyboardSceneDelegate *gKSD;
@implementation TKeyboardSceneDelegate
+ (id)activeKeyboardSceneDelegate { return gKSDOn ? gKSD : nil; }
- (BOOL)isOnScreen { return gOnScreen; }
- (double)verticalOverlapForView:(UIView *)v usingKeyboardInfo:(id)info { return gOtherOverlap; }
@end
// UIKit's (16.7.7 and the 18 code base alike): undocked: CGRectZero; the frame in its screen's space converted into the view's window's scene's
// space, or as it is when the view has no window.
static CGRect TVisibleInputViewFrameInView(id self, SEL _cmd, UIView *view) {
    if (gUndocked) return CGRectZero;
    UIWindow *w = view.window;
    if (!w) return gKeyboard;
    return [gScreenSpace convertRect:gKeyboard toCoordinateSpace:w.windowScene.coordinateSpace];
}
static id TVisibleInputViewFrameBad(id self, SEL _cmd, UIView *view) { return nil; }

// ---- the two shapes of UIKit's method, transcribed ----
static int gCalls16, gCalls18;
static BOOL TAsk(id o, SEL s) { return o && [o respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(o, s); }
// iPadOS 16.7.7, UIKitCore+0x64c140: the container from the ivar; safe area; remote keyboard window: as is; keyboard not on screen: as is; a text
// effects window: MAX(maxY(bounds) minus minY(kb), 0) (fmaxnm), else verticalOverlapForView:usingKeyboardInfo:nil; + 6; bottom raised to it
// (fcsel mi: kept when the comparison fails).
@interface TEMPresentation16 : NSObject { @public UIView *_containerView; }
@end
@implementation TEMPresentation16
@end
@interface TEMPresentation16Getter : TEMPresentation16   // (the same with a containerView getter: the fix reads a getter first)
@end
@implementation TEMPresentation16Getter
- (UIView *)containerView { return _containerView; }
@end
static UIEdgeInsets TInsets16(TEMPresentation16 *self, SEL _cmd) {
    gCalls16++;
    UIView *c = self->_containerView;
    UIEdgeInsets in = c ? [c safeAreaInsets] : UIEdgeInsetsZero;
    if (TAsk(c.window, sel_registerName("_isRemoteKeyboardWindow"))) return in;
    id<DMEditMenuKeyboard> ksd = ((id (*)(id, SEL))objc_msgSend)([TKeyboardSceneDelegate class], sel_registerName("activeKeyboardSceneDelegate"));
    if (![ksd isOnScreen]) return in;
    if (gUnknownGuard) return in;   // (the review's: a guard of another iPadOS this fix has not read: the safe area only)
    double overlap;
    if (TAsk(c.window, sel_registerName("_isTextEffectsWindow"))) {
        CGRect kb = [ksd visibleInputViewFrameInView:c];
        overlap = fmax(CGRectGetMaxY(c.bounds) - CGRectGetMinY(kb), 0.0);
    } else overlap = ((double (*)(id, SEL, id, id))objc_msgSend)(ksd, sel_registerName("verticalOverlapForView:usingKeyboardInfo:"), c, nil);
    double want = overlap + 6.0;
    if (in.bottom < want) in.bottom = want;
    in.bottom += gTweakAdds;   // (the review's: another tweak's hook under ours changed UIKit's answer)
    return in;
}
// The iOS 18 code base: the container from -containerView (the in-process subclass's); the same, with the configuration's
// _ignoresKeyboardAvoidance (safe area only) after the remote keyboard window; bottom = maxsd(overlap + 6, bottom).
@interface TEMPresentation18 : TEMPresentation16   // (as on 18: _UIEditMenuContentPresentation is a _UIEditMenuPresentation)
@end
@implementation TEMPresentation18
@end
@interface TEMPresentation18InProcess : TEMPresentation18 { @public UIView *_menuContainerView; }
@end
@implementation TEMPresentation18InProcess
- (UIView *)containerView { return _menuContainerView; }
@end
@interface TConfig : NSObject
@property (nonatomic) BOOL ignores;
@end
@implementation TConfig
- (BOOL)_ignoresKeyboardAvoidance { return self.ignores; }
@end
static UIEdgeInsets TInsets18(id self, SEL _cmd, id config) {
    gCalls18++;
    UIView *c = [self respondsToSelector:@selector(containerView)] ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(containerView)) : nil;
    UIEdgeInsets in = c ? [c safeAreaInsets] : UIEdgeInsetsZero;
    if (TAsk(c.window, sel_registerName("_isRemoteKeyboardWindow"))) return in;
    if (TAsk(config, sel_registerName("_ignoresKeyboardAvoidance"))) return in;
    id<DMEditMenuKeyboard> ksd = ((id (*)(id, SEL))objc_msgSend)([TKeyboardSceneDelegate class], sel_registerName("activeKeyboardSceneDelegate"));
    if (![ksd isOnScreen]) return in;
    if (gUnknownGuard) return in;   // (the review's: a guard of another iPadOS this fix has not read: the safe area only)
    double overlap;
    if (TAsk(c.window, sel_registerName("_isTextEffectsWindow"))) {
        CGRect kb = ksd ? [ksd visibleInputViewFrameInView:c] : CGRectZero, b = c ? c.bounds : CGRectZero;
        overlap = fmax(CGRectGetMaxY(b) - CGRectGetMinY(kb), 0.0);
    } else overlap = ((double (*)(id, SEL, id, id))objc_msgSend)(ksd, sel_registerName("verticalOverlapForView:usingKeyboardInfo:"), c, nil);
    double want = overlap + 6.0;
    in.bottom = want > in.bottom ? want : in.bottom;
    in.bottom += gTweakAdds;
    return in;
}
static UIEdgeInsets TInsetsRect(id self, SEL _cmd) { return UIEdgeInsetsZero; }   // (bad16: registered with a CGRect's encoding)
static UIEdgeInsets TInsets17(id self, SEL _cmd) { return TInsets18(self, _cmd, nil); }   // (mid17: 16's shape on 18's class)

// ---- the setup ----
static TWindow *gWin; static TContainer *gC;
static TEMPresentation16 *gP16; static TEMPresentation16Getter *gP16G; static TEMPresentation18InProcess *gP18; static TConfig *gConfig;
static SEL s16, s18;
// k quarter turns between the interface (w x h) and the scene's fixed space: 0 none, 1 landscape (as read: the interface's bottom is the scene's
// x 0), 2 upside down, 3 landscape the other way; k 4: a scene shifted 30 points down (no turn)
static void TWorld(int k, double w, double h) {
    TSpace *s = [TSpace new];
    switch (k) {
        case 1: s.toSpace = (CGAffineTransform){ 0, 1, -1, 0, h, 0 }; s.spaceBounds = CGRectMake(0, 0, h, w); break;
        case 2: s.toSpace = (CGAffineTransform){ -1, 0, 0, -1, w, h }; s.spaceBounds = CGRectMake(0, 0, w, h); break;
        case 3: s.toSpace = (CGAffineTransform){ 0, -1, 1, 0, 0, w }; s.spaceBounds = CGRectMake(0, 0, h, w); break;
        case 4: s.toSpace = CGAffineTransformMakeTranslation(0, 30); s.spaceBounds = CGRectMake(0, 0, w, h + 30); break;
        default: s.toSpace = CGAffineTransformIdentity; s.spaceBounds = CGRectMake(0, 0, w, h); break;
    }
    gScene = [TScene new]; gScene.coordinateSpace = s;
    gScreenSpace = [TSpace new]; gScreenSpace.toSpace = CGAffineTransformIdentity; gScreenSpace.spaceBounds = CGRectMake(0, 0, w, h);
    [gC removeFromSuperview];
    gWin = [[TWindow alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    gC = [[TContainer alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    [gWin addSubview:gC];
    gP16 = [TEMPresentation16 new]; gP16->_containerView = gC;
    gP16G = [TEMPresentation16Getter new]; gP16G->_containerView = gC;
    gP18 = [TEMPresentation18InProcess new]; gP18->_menuContainerView = gC;
    gRemote = NO; gTextEffects = YES; gKSDOn = YES; gOnScreen = YES; gUndocked = NO; gSafe = UIEdgeInsetsMake(20, 0, 0, 0); gConfig.ignores = NO;
}
static UIEdgeInsets TCall16(id p) {   // (the method as UIKit's layout calls it: whatever its implementation is now)
    gSceneOn = YES;
    UIEdgeInsets r = ((UIEdgeInsets (*)(id, SEL))method_getImplementation(class_getInstanceMethod(object_getClass(p), s16)))(p, s16);
    gSceneOn = NO; return r;
}
static UIEdgeInsets TCall18(id p, id config) {
    gSceneOn = YES;
    UIEdgeInsets r = ((UIEdgeInsets (*)(id, SEL, id))method_getImplementation(class_getInstanceMethod(object_getClass(p), s18)))(p, s18, config);
    gSceneOn = NO; return r;
}
// (DEBUG: the line the last call wrote names this case: each of UIKit's own conditions keeps its answer by its own name, not only by the review's
//  formula check behind it)
#if DEBUG
#define TLASTCASE(text, what) CHECK([gLog.lastObject hasPrefix:@"[editmenu] " text ";"], "DEBUG: %s: its line names its own case (%s)", what, [gLog.lastObject UTF8String])
#else
#define TLASTCASE(text, what) do { } while (0)
#endif
static BOOL TSame(UIEdgeInsets a, UIEdgeInsets b) { return fabs(a.top - b.top) < 1e-9 && fabs(a.left - b.left) < 1e-9 && fabs(a.bottom - b.bottom) < 1e-9 && fabs(a.right - b.right) < 1e-9; }
static NSString *TStr(UIEdgeInsets e) { return [NSString stringWithFormat:@"{%g, %g, %g, %g}", e.top, e.left, e.bottom, e.right]; }
// UIKit's own answer for the world as it is now (the transcriptions called directly, not through the method).
static UIEdgeInsets TUIKit16(id p) { gSceneOn = YES; UIEdgeInsets r = TInsets16(p, s16); gSceneOn = NO; gCalls16--; return r; }
static UIEdgeInsets TUIKit18(id p, id config) { gSceneOn = YES; UIEdgeInsets r = TInsets18(p, s18, config); gSceneOn = NO; gCalls18--; return r; }
// One case on every shape: the bottom inset wanted with the fix, and UIKit's own (also checked against the number given, when one is).
static void TCase(const char *what, double want, double uikitWant) {
    UIEdgeInsets u16 = TUIKit16(gP16), u18 = TUIKit18(gP18, gConfig);
    int c16 = gCalls16, c18 = gCalls18;
    UIEdgeInsets a = TCall16(gP16), g = TCall16(gP16G), b = TCall18(gP18, gConfig);
    BOOL once = gCalls16 == c16 + 2 && gCalls18 == c18 + 1;
    BOOL keep = a.top == u16.top && a.left == u16.left && a.right == u16.right && b.top == u18.top && b.left == u18.left && b.right == u18.right;
    if (!isnan(uikitWant)) CHECK(u16.bottom == uikitWant && u18.bottom == uikitWant, "%s: UIKit's own bottom inset %g (16 %g, 18 %g)", what, uikitWant, u16.bottom, u18.bottom);
    CHECK(a.bottom == want && g.bottom == want && b.bottom == want && keep && once, "%s: bottom inset %g with the fix (16 %s, 16 with a getter %s, 18 %s; top, left, right UIKit's; UIKit's method called once each)",
          what, want, TStr(a).UTF8String, TStr(g).UTF8String, TStr(b).UTF8String);
}

static void TMain(void) {
    gConfig = [TConfig new];
    // (1) the B75 case, as read on iPadOS 16.7.7 in landscape: the docked keyboard {0, 360, 1024, 408}, safe area top 20: UIKit 774, the fix 414
    TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
    TCase("landscape, the docked keyboard (the device's own numbers)", 414, 774);
    gSceneOn = YES; CGRect kbScene = [(id<DMEditMenuKeyboard>)gKSD visibleInputViewFrameInView:gC]; gSceneOn = NO;
    CHECK(CGRectEqualToRect(kbScene, CGRectMake(0, 0, 408, 1024)), "  ... the model gives UIKit's keyboard in the scene's space as read there: %s", NSStringFromCGRect(kbScene).UTF8String);
    // (2) a 12.9-inch screen in landscape, its keyboard {0, 626, 1366, 398}
    TWorld(1, 1366, 1024); gKeyboard = CGRectMake(0, 626, 1366, 398);
    TCase("landscape 1366 x 1024", 404, 1030);
    // (3) upside down (a half turn: the uneven probe sees it), (4) landscape the other way
    TWorld(2, 768, 1024); gKeyboard = CGRectMake(0, 616, 768, 408);
    TCase("portrait upside down", 414, 1030);
    TWorld(3, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
    TCase("landscape the other way", 414, 774);
    // (5) the spaces agree (portrait, an app): UIKit's own, the same numbers
    TWorld(0, 768, 1024); gKeyboard = CGRectMake(0, 616, 768, 408);
    TCase("portrait: the scene's space is the container's", 414, 414);
    // (6) a scene shifted, no turn: the keyboard taken the last step as well
    TWorld(4, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
    TCase("a scene shifted 30 points down", 414, 384);
    // (7) a hardware keyboard's shortcuts bar; (8) a keyboard moved below the screen; (9) a safe area larger than the keyboard's part
    TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 713, 1024, 55);
    TCase("landscape, a hardware keyboard's bar", 61, 774);
    gKeyboard = CGRectMake(0, 768, 1024, 0);
    TCase("landscape, the keyboard below the screen", 6, 774);
    gKeyboard = CGRectMake(0, 700, 1024, 68); gSafe = UIEdgeInsetsMake(20, 10, 100, 10);
    TCase("landscape, a safe area bottom of 100 over a 68 point keyboard", 100, 774);
    // UIKit's own conditions, each in the turned world (where the fix would otherwise act): UIKit's answer kept
    TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
    gRemote = YES; TCase("the remote keyboard window: UIKit's safe area only", 0, 0); gRemote = NO;
    TLASTCASE("UIKit's own: the remote keyboard window", "the remote keyboard window");
    gOnScreen = NO; TCase("no keyboard on screen", 0, 0); gOnScreen = YES;
    TLASTCASE("UIKit's own: no keyboard on screen", "no keyboard on screen");
    gKSDOn = NO; TCase("no keyboard scene delegate", 0, 0); gKSDOn = YES;
    TLASTCASE("UIKit's own: no keyboard on screen", "no keyboard scene delegate");
    gTextEffects = NO; TCase("not a text effects window: UIKit's other branch", gOtherOverlap + 6, gOtherOverlap + 6); gTextEffects = YES;
    TLASTCASE("UIKit's own: not a text effects window (its other branch)", "not a text effects window");
    gUndocked = YES; TCase("an undocked keyboard (UIKit's CGRectZero): UIKit's answer kept", 774, 774); gUndocked = NO;
    TLASTCASE("UIKit's own: the keyboard's frame is zero or not a number", "an undocked keyboard");
    // the review's two guards, in the same turned world: a container on another display (the TV: SpringBoard's keyboard is on the iPad's own
    // screen, and the TV never turns), and an answer UIKit made another way than its keyboard formula on the frame it read
    gOtherScreen = YES; TCase("a container on another display (the TV): UIKit's answer kept, whatever its spaces", 774, 774); gOtherScreen = NO;
    TLASTCASE("UIKit's own: another display (the keyboard is on the iPad's own)", "a container on another display");
    gUnknownGuard = YES; TCase("a guard of UIKit's this fix has not read (another iPadOS): UIKit's safe area only kept", 0, 0); gUnknownGuard = NO;
    TLASTCASE("UIKit's own: its bottom inset is not its keyboard formula on that frame", "a guard of UIKit's this fix has not read");
    gTweakAdds = 10; TCase("another tweak's hook under ours changed UIKit's answer: its answer kept", 784, 784); gTweakAdds = 0;
    TLASTCASE("UIKit's own: its bottom inset is not its keyboard formula on that frame", "another tweak's change");
    TCase("  ... and with them gone the fix again", 414, 774);
    TLASTCASE("the keyboard taken into the container's space", "the fix again");
    {   // a keyboard frame that is not a number: UIKit's answer kept, whatever it is
        gKeyboard = CGRectMake(NAN, 360, 1024, 408);
        UIEdgeInsets u = TUIKit16(gP16), a = TCall16(gP16);
        CHECK(TSame(a, u) || (isnan(a.bottom) && isnan(u.bottom)), "a keyboard frame that is not a number: UIKit's answer kept (%s, UIKit's %s)", TStr(a).UTF8String, TStr(u).UTF8String);
        gKeyboard = CGRectMake(0, 360, 1024, 408);
    }
    {   // the configuration that ignores the keyboard (18 only)
        gConfig.ignores = YES;
        UIEdgeInsets u = TUIKit18(gP18, gConfig), b = TCall18(gP18, gConfig);
        CHECK(u.bottom == 0 && TSame(b, u), "18's configuration ignoring the keyboard: UIKit's safe area only (%s)", TStr(b).UTF8String);
        TLASTCASE("UIKit's own: the menu ignores the keyboard", "18's configuration ignoring the keyboard");
        gConfig.ignores = NO;
        UIEdgeInsets n = TCall18(gP18, nil);
        CHECK(n.bottom == 414, "18 with no configuration: the fix (%s)", TStr(n).UTF8String);
    }
    {   // no window, no scene, no container
        gScene = nil; UIEdgeInsets u = TUIKit16(gP16), a = TCall16(gP16); TWorld(1, 1024, 768);
        CHECK(TSame(a, u) || (isnan(a.bottom) && isnan(u.bottom)), "no window scene: UIKit's answer kept (%s)", TStr(a).UTF8String);
        [gC removeFromSuperview]; u = TUIKit16(gP16); a = TCall16(gP16);
        CHECK(TSame(a, u), "a container in no window: UIKit's answer kept (%s)", TStr(a).UTF8String);
        TWorld(1, 1024, 768); gP16->_containerView = nil; u = TUIKit16(gP16); a = TCall16(gP16);
        CHECK(TSame(a, u), "no container: UIKit's answer kept (%s)", TStr(a).UTF8String);
    }
    CHECK(gMarks > 0, "the release marker is on the fix's path");
#if DEBUG
    {   // the debug switch keeps UIKit's answer; the lines
        TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
        [gFlags addObject:@"/tmp/msb-editmenu-uikit"]; UIEdgeInsets k = TCall16(gP16); [gFlags removeObject:@"/tmp/msb-editmenu-uikit"];
        CHECK(k.bottom == 774, "DEBUG: /tmp/msb-editmenu-uikit keeps UIKit's answer (%g)", k.bottom);
        NSString *all = [gLog componentsJoinedByString:@"\n"];
        CHECK([all containsString:@"[editmenu] the edit menu's keyboard room in one space: -[TEMPresentation16 _preferredContentInsetsForContainerView] hooked; -[TEMPresentation18 _preferredContentInsetsForContainerViewWithConfiguration:] hooked\n"],
              "DEBUG: the start-up line names both shapes hooked, each where its class has it itself (18's class inherits 16's: not hooked twice)");
        CHECK([all containsString:@"[editmenu] the keyboard taken into the container's space; container {{0, 0}, {1024, 768}} in TWindow at level 0.0, scene space {{0, 0}, {768, 1024}}, insets {20, 0, 774, 0}: keyboard {{0, 0}, {408, 1024}} in the scene's space, {{0, 360}, {1024, 408}} in the container; bottom inset 414.0 (UIKit's 774.0)"],
              "DEBUG: the line of the B75 case (container, window, scene, UIKit's insets, the keyboard both ways, the bottom inset and UIKit's)");
        CHECK([all containsString:@"[editmenu] UIKit's own: the scene's space is the container's"] && [all containsString:@"[editmenu] UIKit's own: the debug switch"]
              && [all containsString:@"[editmenu] UIKit's own: not a text effects window (its other branch)"], "DEBUG: the cases UIKit's answer is kept in are named");
        CHECK([all containsString:@"[editmenu] UIKit's own: another display (the keyboard is on the iPad's own); container {{0, 0}, {1024, 768}} in TWindow"]
              && [all containsString:@"[editmenu] UIKit's own: its bottom inset is not its keyboard formula on that frame; container {{0, 0}, {1024, 768}} in TWindow at level 0.0, scene space {{0, 0}, {768, 1024}}, insets {20, 0, 0, 0}: keyboard {{0, 0}, {408, 1024}} in the scene's space; UIKit's formula on it 774.0, its answer 0.0"]
              && [all containsString:@"insets {20, 0, 784, 0}: keyboard {{0, 0}, {408, 1024}} in the scene's space; UIKit's formula on it 774.0, its answer 784.0"],
              "DEBUG: the review's two cases are named, the second with UIKit's formula on the frame and its answer");
        NSUInteger n = gLog.count; for (int i = 0; i < 5; i++) TCall16(gP16);
        CHECK(gLog.count == n + 1, "DEBUG: one line per container and case, not one per layout pass (%lu new)", (unsigned long)(gLog.count - n));
    }
#endif
}

int main(int argc, char **argv) { @autoreleasepool {
    gLog = [NSMutableArray array];
#if DEBUG
    gFlags = [NSMutableSet set];
#endif
    const char *mode = argc > 1 ? argv[1] : "main";
    gKSD = [TKeyboardSceneDelegate new];
    gTV = [NSObject new];
    s16 = sel_registerName("_preferredContentInsetsForContainerView"); s18 = sel_registerName("_preferredContentInsetsForContainerViewWithConfiguration:");
    // the shapes as they are here (UIKit's own type encodings), or another shape for the scenario
    const char *rect = @encode(CGRect), *ins = @encode(UIEdgeInsets);
    char e16[64], e18[64], ev[96];
    snprintf(e16, sizeof e16, "%s16@0:8", ins); snprintf(e18, sizeof e18, "%s24@0:8@16", ins); snprintf(ev, sizeof ev, "%s24@0:8@16", rect);
    if (!strcmp(mode, "bad16")) { char eb[64]; snprintf(eb, sizeof eb, "%s16@0:8", rect); class_addMethod([TEMPresentation16 class], s16, (IMP)TInsetsRect, eb); }
    else if (!strcmp(mode, "mid17")) class_addMethod([TEMPresentation18 class], s16, (IMP)TInsets17, e16);
    else class_addMethod([TEMPresentation16 class], s16, (IMP)TInsets16, e16);
    if (strcmp(mode, "no18") && strcmp(mode, "mid17")) class_addMethod([TEMPresentation18 class], s18, (IMP)TInsets18, e18);
    if (!strcmp(mode, "badksd")) class_addMethod([TKeyboardSceneDelegate class], @selector(visibleInputViewFrameInView:), (IMP)TVisibleInputViewFrameBad, "@24@0:8@16");
    else class_addMethod([TKeyboardSceneDelegate class], @selector(visibleInputViewFrameInView:), (IMP)TVisibleInputViewFrameInView, ev);
    gSkip = !strcmp(mode, "skip");
    gConfig = [TConfig new];
    DMEditMenuRoomInit();
    DMEditMenuRoomInit();   // (once only)
    if (!strcmp(mode, "main")) {
        CHECK(gHooks == 2 && (void *)o_DMEditMenuInsets16 == (void *)TInsets16 && (void *)o_DMEditMenuInsets18 == (void *)TInsets18, "both shapes hooked once, UIKit's methods kept as the originals (%d hooks)", gHooks);
        TMain();
    } else if (!strcmp(mode, "skip")) {
        TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
        CHECK(!strcmp(gSkipAsked, "editMenuRoom") && gHooks == 0 && TCall16(gP16).bottom == 774 && TCall18(gP18, gConfig).bottom == 774,
              "after a crash in it (the crash guard's piece \"%s\"): no hook, UIKit's own 774", gSkipAsked);
    } else if (!strcmp(mode, "badksd")) {
        CHECK(gHooks == 0 && !o_DMEditMenuInsets16 && !o_DMEditMenuInsets18 && method_getImplementation(class_getInstanceMethod([TEMPresentation16 class], s16)) == (IMP)TInsets16,
              "UIKit's visibleInputViewFrameInView: of another shape: no hook at all, UIKit's methods untouched (%d hooks)", gHooks);
    } else if (!strcmp(mode, "bad16")) {
        TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
        CHECK(gHooks == 1 && o_DMEditMenuInsets18 && !o_DMEditMenuInsets16 && TCall18(gP18, gConfig).bottom == 414, "16's method of another shape: not hooked, 18's still is (%d hooks)", gHooks);
    } else if (!strcmp(mode, "mid17")) {
        TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
        CHECK(gHooks == 1 && (void *)o_DMEditMenuInsets16 == (void *)TInsets17 && !o_DMEditMenuInsets18 && TCall16(gP18).bottom == 414 && TUIKit18(gP18, nil).bottom == 774,
              "16's shape on 18's class (a 17 in between): hooked there, once (%d hooks)", gHooks);
    } else if (!strcmp(mode, "no18")) {
        TWorld(1, 1024, 768); gKeyboard = CGRectMake(0, 360, 1024, 408);
        CHECK(gHooks == 1 && o_DMEditMenuInsets16 && !o_DMEditMenuInsets18 && TCall16(gP16).bottom == 414, "no 18 shape (iPadOS 16): only 16's hooked (%d hooks)", gHooks);
    }
    printf("test-editmenuroom %s: %d passed, %d failed\n", mode, passes, fails);
    return fails ? 1 : 0;
} }
