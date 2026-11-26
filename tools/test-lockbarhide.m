// test-lockbarhide.m -- Mac test of the Lock Screen's status bar (1.8.9: B113 "Hide Status Bar on Lock Screen does not hide iPadOS 18's Lock Screen
// bar", and F49 rev 2's one-status-drawing rule, plans/design-mac-lock-screen.md 12.1): common/LockBarHide.h as built, and LockStatusBar.x's
// functions as built (test-lockbarhide.sh cuts LSBCoverShown, LSBSetFlag, LSBRealBar and LSBTruth out of macsettings/LockStatusBar.x into
// lockbar-gen.h). This file gives them stand-ins for UIKit and a SpringBoard modelled on 18.5's code read from the IPSW:
// -[SBDashBoardStatusBarController setStatusBarHidden:forReason:] keeps a set of reasons and holds one "hidden" assertion at level 8 while it is
// not empty; -setStatusBarAlpha:style:legibilitySettings: holds the Cover Sheet's own level-8 assertion (modified in place, made again after
// -clearStatusBarParameters); the bar's alpha is the assertions applied level by level, in the order they were added. Its arguments are as
// 15.6.1-18.5 have them ("v40@0:8@16q24@32"): the alpha an NSNumber (nil: the alpha left as it is), the style an integer (-1: left as it is),
// the legibility settings an object or nil (18.5's block sets each only when given); a 1.8.9 test build's hooks took the alpha for a double.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit stand-ins: a view is its origin in its superview; a window turned by 90 degrees maps its own coordinates onto the screen's ----
@interface UICoordSpace : NSObject @property (nonatomic) CGRect bounds; @end
@implementation UICoordSpace @end
@interface UIScreen : NSObject @property (nonatomic, strong) UICoordSpace *coordinateSpace; + (UIScreen *)mainScreen; @end
@implementation UIScreen
+ (UIScreen *)mainScreen { static UIScreen *s; if (!s) { s = [UIScreen new]; s.coordinateSpace = [UICoordSpace new]; s.coordinateSpace.bounds = CGRectMake(0, 0, 1366, 1024); } return s; }
@end
@class UIWindow, UIWindowScene, UIViewController;
@interface UIView : NSObject
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, strong) NSMutableArray *subviews;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) CGRect frame;   // (in the superview)
- (CGRect)bounds;
- (UIWindow *)window;
- (void)addSubview:(UIView *)v;
- (void)removeFromSuperview;
- (CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space;
@end
@interface UIWindow : UIView
@property (nonatomic, strong) UIScreen *screen;
@property (nonatomic) CGFloat windowLevel;
@property (nonatomic, weak) UIWindowScene *windowScene;
@property (nonatomic, strong) UIViewController *rootViewController;
@property (nonatomic) BOOL turned;    // (its own coordinates turned 90 degrees against the screen's)
@end
@implementation UIView
- (instancetype)init { if ((self = [super init])) { _alpha = 1; _subviews = [NSMutableArray array]; } return self; }
- (CGRect)bounds { return CGRectMake(0, 0, _frame.size.width, _frame.size.height); }
- (UIWindow *)window { UIView *v = self; while (v && ![v isKindOfClass:[UIWindow class]]) v = v.superview; return (UIWindow *)v; }
- (void)addSubview:(UIView *)v { [v.superview.subviews removeObject:v]; v.superview = self; [_subviews addObject:v]; }
- (void)removeFromSuperview { [self.superview.subviews removeObject:self]; self.superview = nil; }
- (CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space {
    UIView *v = self;
    while (v && ![v isKindOfClass:[UIWindow class]]) { r.origin.x += v.frame.origin.x; r.origin.y += v.frame.origin.y; v = v.superview; }
    UIWindow *w = (UIWindow *)v;
    if (w.turned) { CGFloat W = w.frame.size.width; r = CGRectMake(r.origin.y, W - r.origin.x - r.size.width, r.size.height, r.size.width); }   // (window x -> screen y)
    return r;
}
@end
@implementation UIWindow @end
@interface UILabel : UIView @property (nonatomic, copy) NSString *text; @end
@implementation UILabel @end
@interface UIImageView : UIView @end
@implementation UIImageView @end
@interface UIWindowScene : NSObject @property (nonatomic, strong) NSMutableArray *windows; @end
@implementation UIWindowScene @end
@interface UIViewController : NSObject @property (nonatomic, strong) UIView *view; - (BOOL)isViewLoaded; @end
@implementation UIViewController - (BOOL)isViewLoaded { return _view != nil; } @end

// ---- SpringBoard, modelled on 18.5 ----
@interface SBAssertion : NSObject @property (nonatomic) double alpha; @property (nonatomic) BOOL hasAlpha; @property (nonatomic) BOOL live; @end
@implementation SBAssertion @end
static NSMutableArray<SBAssertion *> *gLevel8;   // (level 8's assertions in the order they were added)
@interface SBDashBoardStatusBarController : NSObject { @public NSMutableSet *_reasons; SBAssertion *_hidden, *_alphaAssertion; }
- (void)setStatusBarHidden:(BOOL)hidden forReason:(NSString *)reason;
- (void)setStatusBarAlpha:(NSNumber *)alpha style:(long long)style legibilitySettings:(id)ls;
- (void)clearStatusBarParameters;
@end
@implementation SBDashBoardStatusBarController
- (instancetype)init { if ((self = [super init])) _reasons = [NSMutableSet set]; return self; }
- (void)setStatusBarHidden:(BOOL)hidden forReason:(NSString *)reason {
    if (hidden) { [_reasons addObject:reason]; if (!_hidden) { _hidden = [SBAssertion new]; _hidden.alpha = 0; _hidden.hasAlpha = YES; _hidden.live = YES; [gLevel8 addObject:_hidden]; } }
    else { [_reasons removeObject:reason]; if (!_reasons.count && _hidden) { _hidden.live = NO; [gLevel8 removeObject:_hidden]; _hidden = nil; } }
}
- (void)setStatusBarAlpha:(NSNumber *)alpha style:(long long)style legibilitySettings:(id)ls {
    if (!_alphaAssertion) { _alphaAssertion = [SBAssertion new]; _alphaAssertion.live = YES; [gLevel8 addObject:_alphaAssertion]; }   // (modifySettingsWithBlock: keeps its place)
    if (alpha) { _alphaAssertion.alpha = alpha.doubleValue; _alphaAssertion.hasAlpha = YES; }   // (nil: the alpha left as it is, as 18.5's block)
}
- (void)clearStatusBarParameters { if (_alphaAssertion) { [gLevel8 removeObject:_alphaAssertion]; _alphaAssertion = nil; } }
@end
static double SBMergedAlpha(void) { double a = 1; for (SBAssertion *x in gLevel8) if (x.hasAlpha) a = x.alpha; return a; }   // (applied in order: the last one with an alpha wins)
@interface SBDefaultCoverSheetContext : NSObject @property (nonatomic, strong) SBDashBoardStatusBarController *statusBarController; @end
@implementation SBDefaultCoverSheetContext @end
@interface SBStatusBarWindow : UIWindow { @public UIView *_statusBar; } - (UIView *)statusBar; @end
@implementation SBStatusBarWindow - (UIView *)statusBar { return _statusBar; } @end
@interface _UIPortalView : UIView @property (nonatomic, weak) UIView *sourceView; @end
@implementation _UIPortalView @end
// the Cover Sheet (18.5 has -coverSheetContext; 15.6.1 only the ivar)
@interface CSCoverSheetView : UIView { @public UIView *_fakeStatusBar; UIView *_fakeStatusBarWrapperView; } @end
@implementation CSCoverSheetView @end
@interface CSCoverSheetViewController : UIViewController { @public id _coverSheetContext; UIView *_fakeStatusBar; } - (id)coverSheetContext; @end
@implementation CSCoverSheetViewController - (id)coverSheetContext { return _coverSheetContext; } @end
@interface CSCoverSheetViewController15 : UIViewController { @public id _coverSheetContext; UIView *_fakeStatusBar; } @end
@implementation CSCoverSheetViewController15 @end
@interface BadController : NSObject - (void)setStatusBarHidden:(int)h forReason:(int)r; @end
@implementation BadController - (void)setStatusBarHidden:(int)h forReason:(int)r {} @end
@interface BadContext : NSObject @property (nonatomic, strong) id statusBarController; @end
@implementation BadContext @end

#define LBH_REASON @"com.besiktasliseba.maclockstatusbar"
#include LBH_HEADER
#include "../common/HookTypes.h"

// ---- the rest of LockStatusBar.x at that moment ----
static BOOL gOther = NO;
static NSMutableArray<NSString *> *gLog;
static BOOL LSBIsCoverSheet(id c) { return [c isKindOfClass:[UIViewController class]]; }
#define kMSBDDupLockStatusBar 3
static BOOL MSBDOtherTweakDoing(int what, BOOL x) { return gOther; }
static void LSBBarLog(NSString *line) { [gLog addObject:line]; }
static BOOL gLSBDismissing;
static int gLSBHeals;
static BOOL gLSBNoCallLogged;
static BOOL gLSBTruthQueued;
static BOOL gLSBSwitchCache;
#include "lockbar-gen.h"
static void Drain(void) { for (int i = 0; i < 4; i++) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]]; }

// ---- a Lock Screen: the Cover Sheet's window (1050), SpringBoard's status bar window (1070) with its bar's items at the top right ----
typedef struct { CSCoverSheetViewController *cs; CSCoverSheetView *cv; UIWindow *cover; SBStatusBarWindow *sbw; UIView *bar, *wifi, *battery; SBDashBoardStatusBarController *sbc; UIWindowScene *scene; } Lock;
static UIView *V(CGRect f) { UIView *v = [UIView new]; v.frame = f; return v; }
static Lock MakeLock(void) {
    Lock L = {0};
    gLevel8 = [NSMutableArray array];
    L.scene = [UIWindowScene new]; L.scene.windows = [NSMutableArray array];
    L.cover = [UIWindow new]; L.cover.frame = CGRectMake(0, 0, 1366, 1024); L.cover.screen = [UIScreen mainScreen]; L.cover.windowLevel = 1050; L.cover.windowScene = L.scene;
    L.cv = [CSCoverSheetView new]; L.cv.frame = L.cover.frame; [L.cover addSubview:L.cv];
    L.cs = [CSCoverSheetViewController new]; L.cs.view = L.cv;
    L.sbc = [SBDashBoardStatusBarController new];
    SBDefaultCoverSheetContext *ctx = [SBDefaultCoverSheetContext new]; ctx.statusBarController = L.sbc;
    L.cs->_coverSheetContext = ctx;
    L.sbw = [SBStatusBarWindow new]; L.sbw.frame = CGRectMake(0, 0, 1366, 1024); L.sbw.screen = [UIScreen mainScreen]; L.sbw.windowLevel = 1070; L.sbw.windowScene = L.scene;
    L.bar = V(CGRectMake(0, 0, 1366, 24)); [L.sbw addSubview:L.bar]; L.sbw->_statusBar = L.bar;
    UIView *fg = V(CGRectMake(0, 0, 1366, 24)); [L.bar addSubview:fg];
    L.wifi = [UIImageView new]; L.wifi.frame = CGRectMake(1300, 6, 17, 12); [fg addSubview:L.wifi];
    L.battery = [UIImageView new]; L.battery.frame = CGRectMake(1325, 6, 29, 12); [fg addSubview:L.battery];
    [L.scene.windows addObjectsFromArray:@[ L.cover, L.sbw ]];
    return L;
}
// SpringBoard draws its bar at the merged alpha of the Lock Screen's assertions (and the Cover Sheet's own alpha request first)
static void SBApply(Lock *L) { L->bar.alpha = SBMergedAlpha(); }

int main(void) { @autoreleasepool {
    gLog = [NSMutableArray array];
    CGSize S = CGSizeMake(1366, 1024);
    // ---- the band and the drawn rule ----
    Expect(LBHInBand(CGRectMake(1300, 6, 17, 12), S) && !LBHInBand(CGRectMake(600, 6, 17, 12), S) && !LBHInBand(CGRectMake(1300, 50, 17, 12), S), @"the band: the right quarter, the top 44 pt");
    Expect(!LBHInBand(CGRectMake(1300, 6, 0.5, 12), S), @"an item under 1 pt wide draws nothing");
    LBHFacts ok = { YES, YES, 1, 1070, 1050, YES, 1, YES };
    Expect(LBHDrawn(ok), @"a shown bar above the Cover Sheet with an item in the band is drawn");
    LBHFacts f;
    f = ok; f.ownScreen = NO;       Expect(!LBHDrawn(f), @"a bar on the TV's screen does not count");
    f = ok; f.windowShown = NO;     Expect(!LBHDrawn(f), @"a hidden window does not count");
    f = ok; f.windowAlpha = 0;      Expect(!LBHDrawn(f), @"a window at alpha 0 does not count");
    f = ok; f.windowLevel = 1035;   Expect(!LBHDrawn(f), @"a bar below the Cover Sheet's level does not count");
    f = ok; f.windowLevel = 1050;   Expect(LBHDrawn(f), @"a bar at the Cover Sheet's own level counts");
    f = ok; f.chainShown = NO;      Expect(!LBHDrawn(f), @"a hidden ancestor: not drawn");
    f = ok; f.effectiveAlpha = 0.005; Expect(!LBHDrawn(f), @"an alpha-0 ancestor (or an animation ending at 0): not drawn");
    f = ok; f.itemInBand = NO;      Expect(!LBHDrawn(f), @"no item in the band: not drawn");
    // ---- our reason's step ----
    Expect(LBHStep(NO, YES, NO, YES, NO) == 1 && LBHStep(YES, YES, NO, YES, NO) == 0, @"switch on, Cover Sheet shown: added once");
    Expect(LBHStep(YES, YES, NO, YES, YES) == -1, @"the dismissal starts: given back");
    Expect(LBHStep(YES, NO, NO, YES, NO) == -1 && LBHStep(YES, YES, YES, YES, NO) == -1 && LBHStep(YES, YES, NO, NO, NO) == -1, @"switched off / another modification does it / not shown: given back");
    Expect(LBHStep(NO, NO, NO, YES, NO) == 0 && LBHStep(NO, YES, NO, NO, NO) == 0, @"nothing to give back: nothing done");
    // ---- the pair's truth table (12.1) ----
    LBHPairFacts p0 = { YES, NO, YES, NO, YES, NO };
    Expect(LBHPairShows(p0), @"pair: part on, nothing drawn, hidden by our switch, the page wants a bar");
    LBHPairFacts p = p0; p.barDrawn = YES; Expect(!LBHPairShows(p), @"pair: a bar drawn -> never a second set");
    p = p0; p.hidByLSB = NO; Expect(!LBHPairShows(p), @"pair: the top right emptied by something else -> nothing of ours");
    p = p0; p.hidByLSB = NO; p.hidByUs = YES; Expect(LBHPairShows(p), @"pair: hidden by the part itself (Q27) -> ours");
    p = p0; p.pageWantsBar = NO; Expect(!LBHPairShows(p), @"pair: iPadOS's page wants no bar (the camera page) -> none");
    p = p0; p.today = YES; Expect(!LBHPairShows(p), @"pair: Today -> none");
    p = p0; p.partOn = NO; Expect(!LBHPairShows(p), @"pair: the part off -> none");
    Expect(LBHPartHides(YES, YES, NO, NO, NO, YES, NO) && !LBHPartHides(YES, YES, YES, NO, NO, YES, NO) && !LBHPartHides(YES, NO, NO, NO, NO, YES, NO) && !LBHPartHides(NO, YES, NO, NO, NO, YES, NO) && LBHPartHides(YES, NO, NO, YES, NO, YES, NO),
           @"Q27: iPadOS's own bar is hidden by the part; our menu bar's copy is left as it is; nothing drawn: nothing to hide; once hidden it stays");
    Expect(!LBHPartHides(YES, YES, NO, YES, NO, YES, YES) && !LBHPartHides(YES, YES, NO, YES, NO, NO, NO), @"Q27: given back on Today and where iPadOS's page wants no bar (never none drawn where the user hid nothing)");
    Expect(!LBHPartHides(YES, YES, NO, NO, YES, YES, NO), @"Q27: never while Hide Status Bar on Lock Screen hides the bar (one reason, so its re-ask can re-make the request)");

    // ---- SpringBoard's alpha request as iPadOS has it (the model's method), and as LockStatusBar.x's hook table is written ----
    {
        char b[64]; Method am = class_getInstanceMethod([SBDashBoardStatusBarController class], @selector(setStatusBarAlpha:style:legibilitySettings:));
        Expect(am && MSBDHookBareTypes(method_getTypeEncoding(am), b, sizeof b) && strcmp(b, "v@:@q@") == 0, [NSString stringWithFormat:@"the model's -setStatusBarAlpha:style:legibilitySettings: is iPadOS's v40@0:8@16q24@32 (%s)", am ? method_getTypeEncoding(am) : "none"]);
        MSBDHookSig real[] = { {"SBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:@q@"} }, old[] = { {"SBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:dq@"} };
        Expect(MSBD_HOOK_SIGS_WRONG(real) == nil && MSBD_HOOK_SIGS_WRONG(old) != nil, @"a hook written for an NSNumber alpha goes in; the test build's (a double alpha) is kept out");
        Lock A = MakeLock();
        [A.sbc setStatusBarAlpha:@0 style:1 legibilitySettings:nil]; [A.sbc setStatusBarAlpha:nil style:-1 legibilitySettings:nil]; SBApply(&A);
        Expect(A.bar.alpha == 0, @"a request with no alpha (nil) leaves the alpha as it is (18.5's block)");
    }
    // ---- the controller: by the accessor (16-18) and by the ivar (15.6.1 has no accessor) ----
    Lock L = MakeLock();
    Expect(LBHController(L.cs) == L.sbc, @"SpringBoard's controller found through -coverSheetContext");
    CSCoverSheetViewController15 *cs15 = [CSCoverSheetViewController15 new]; cs15.view = L.cv; cs15->_coverSheetContext = L.cs->_coverSheetContext;
    Expect(LBHController(cs15) == L.sbc, @"15.6.1: found through the _coverSheetContext ivar");
    BadContext *bad = [BadContext new]; bad.statusBarController = [BadController new];
    CSCoverSheetViewController *csBad = [CSCoverSheetViewController new]; csBad->_coverSheetContext = bad;
    Expect(LBHController(csBad) == nil && LBHSet(csBad, YES) == -2, @"a call of another shape is never made (-2: no call here)");
    // ---- balance ----
    [L.sbc setStatusBarHidden:YES forReason:@"iPadOS"];
    Expect(LBHSet(L.cs, YES) == 1 && LBHSet(L.cs, YES) == 0 && L.sbc->_reasons.count == 2, @"ours goes in once beside iPadOS's own");
    Expect(LBHSet(L.cs, NO) == -1 && LBHSet(L.cs, NO) == 0 && [L.sbc->_reasons isEqualToSet:[NSSet setWithObject:@"iPadOS"]], @"ours comes out once; iPadOS's own reason untouched");
    [L.sbc setStatusBarHidden:NO forReason:@"iPadOS"];

    // ---- VISIBLE BAR on synthetic states ----
    L = MakeLock();
    [L.sbc setStatusBarAlpha:@1 style:0 legibilitySettings:nil]; SBApply(&L);
    LBHBar b = LBHVisibleBar(L.cs);
    Expect(b.drawn && !b.ourMenuBar && b.window == L.sbw, @"18.5 at rest: SpringBoard's status bar window's bar is drawn at the top right");
    L.sbw.hidden = YES; Expect(!LBHVisibleBar(L.cs).drawn, @"its window hidden: nothing drawn"); L.sbw.hidden = NO;
    L.bar.superview.alpha = 1; L.bar.alpha = 0; Expect(!LBHVisibleBar(L.cs).drawn, @"the bar at alpha 0: nothing drawn"); L.bar.alpha = 1;
    L.wifi.superview.alpha = 0.0; Expect(!LBHVisibleBar(L.cs).drawn, @"an alpha-0 ancestor of every item: nothing drawn"); L.wifi.superview.alpha = 1;
    L.sbw.windowLevel = 1000; Expect(!LBHVisibleBar(L.cs).drawn, @"a bar below the Cover Sheet's window: not counted"); L.sbw.windowLevel = 1070;
    L.wifi.frame = CGRectMake(40, 6, 17, 12); L.battery.frame = CGRectMake(70, 6, 29, 12);
    Expect(!LBHVisibleBar(L.cs).drawn, @"no item in the band: not counted");
    L.wifi.frame = CGRectMake(1300, 6, 17, 12); L.battery.frame = CGRectMake(1325, 6, 29, 12);
    UIScreen *tv = [UIScreen new]; tv.coordinateSpace = [UICoordSpace new]; tv.coordinateSpace.bounds = CGRectMake(0, 0, 1920, 1080);
    L.sbw.screen = tv; Expect(!LBHVisibleBar(L.cs).drawn, @"a bar on the TV's screen: not counted"); L.sbw.screen = [UIScreen mainScreen];
    // a turned window: its own top right is not the screen's
    L.sbw.turned = YES; L.sbw.frame = CGRectMake(0, 0, 1024, 1366);
    L.wifi.frame = CGRectMake(990, 6, 17, 12);   // (the window's own top right: the screen's top left)
    BOOL turnedOut = !LBHVisibleBar(L.cs).drawn;
    L.wifi.frame = CGRectMake(1000, 1300, 17, 12); L.battery.frame = CGRectMake(1000, 1320, 17, 29);   // (the window's bottom right = the screen's top right)
    BOOL turnedIn = LBHVisibleBar(L.cs).drawn;
    Expect(turnedOut && turnedIn, @"frames in a turned window are judged on the screen");
    L.sbw.turned = NO; L.sbw.frame = CGRectMake(0, 0, 1366, 1024); L.wifi.frame = CGRectMake(1300, 6, 17, 12); L.battery.frame = CGRectMake(1325, 6, 29, 12);
    // our own copy (our menu bar's Apple logo label in it)
    UILabel *logo = [UILabel new]; logo.text = @""; logo.frame = CGRectMake(12, 4, 14, 16); [L.wifi.superview addSubview:logo];
    b = LBHVisibleBar(L.cs); Expect(b.drawn && b.ourMenuBar, @"our menu bar's copy is recognised as ours");
    logo.hidden = YES; Expect(!LBHVisibleBar(L.cs).ourMenuBar, @"a hidden logo label: not our copy"); [logo.superview.subviews removeObject:logo];
    // the Cover Sheet's own copy, and a portal of a bar
    L.bar.alpha = 0;
    UIView *fake = V(CGRectMake(0, 0, 1366, 24)); UIView *fi = [UIImageView new]; fi.frame = CGRectMake(1320, 4, 20, 12); [fake addSubview:fi];
    [L.cv addSubview:fake]; L.cs->_fakeStatusBar = fake;
    b = LBHVisibleBar(L.cs); Expect(b.drawn && b.view == fake, @"the Cover Sheet's copy (15-17 at rest) is found by its ivar");
    fake.hidden = YES; Expect(!LBHVisibleBar(L.cs).drawn, @"the copy turned off: nothing drawn");
    L.bar.alpha = 1; L.sbw.hidden = NO;
    _UIPortalView *portal = [_UIPortalView new]; portal.frame = CGRectMake(0, 0, 1366, 24); portal.sourceView = L.bar;
    UIView *pi = [UIImageView new]; pi.frame = CGRectMake(1310, 5, 20, 12); [portal addSubview:pi];
    UIView *wrap = V(CGRectMake(0, 0, 1366, 1024)); [L.cv addSubview:wrap]; L.cv->_fakeStatusBarWrapperView = wrap; [wrap addSubview:portal];
    L.sbw->_statusBar = nil; [L.bar removeFromSuperview];
    b = LBHVisibleBar(L.cs); Expect(!b.drawn, @"a portal whose source is not a bar of the Lock Screen: not counted");
    L.sbw->_statusBar = L.bar; [L.sbw addSubview:L.bar]; L.bar.alpha = 0;
    b = LBHVisibleBar(L.cs); Expect(b.drawn && b.view == portal, @"a portal of SpringBoard's bar drawn in the Cover Sheet counts");
    [wrap.subviews removeObject:portal];

    // ---- B113 on 18.5: the switch hides the bar the user sees ----
    // the old code: the Cover Sheet's copy turned off (it was off already on 18), nothing else
    L = MakeLock(); [gLog removeAllObjects];
    [L.sbc setStatusBarAlpha:@1 style:0 legibilitySettings:nil]; SBApply(&L);
    BOOL oldDrawn = LBHVisibleBar(L.cs).drawn;
    Expect(oldDrawn, @"(the published code's way: only the Cover Sheet's copy off -- iPadOS's bar is still drawn on 18, B113's photo)");
    // the new code, as built: an appearance with the switch on
    gLSBDismissing = NO; gLSBHeals = 0;
    LSBRealBar((UIViewController *)L.cs, YES, "appearing"); SBApply(&L); Drain(); SBApply(&L);
    Expect(!LBHVisibleBar(L.cs).drawn, @"B113: with the switch on, nothing is drawn at the Lock Screen's top right on 18");
    Expect(objc_getAssociatedObject(L.cs, LBH_FLAG_KEY) != nil, @"the flag \"hid the bar for this appearance\" is set for Mac Lock Screen");
    Expect([gLog.lastObject containsString:@"is hidden: nothing drawn"], [NSString stringWithFormat:@"the log reads what is drawn: %@", gLog.lastObject]);
    // the Cover Sheet's own request made again after ours (cleared and asked again: a wake, a page change, a comeback), as the hooks see it:
    // its alpha request reaches SpringBoard's controller (LSBRealAlpha) and its status update returns (LSBReal): read the next turn, ours
    // made again; three such requests in ONE appearance, each answered (review finding 2: the re-ask was once per appearance)
    gLSBSwitchCache = YES;
    for (int round = 1; round <= 3; round++) {
        [gLog removeAllObjects];
        [L.sbc clearStatusBarParameters]; [L.sbc setStatusBarAlpha:@1 style:0 legibilitySettings:nil]; SBApply(&L);
        Expect(LBHVisibleBar(L.cs).drawn, [NSString stringWithFormat:@"(request %d: the Cover Sheet's request after ours wins at the same level)", round]);
        LSBStatusUpdated((UIViewController *)L.cs, "the Cover Sheet's alpha request");
        LSBStatusUpdated((UIViewController *)L.cs, "a status update");
        for (int i = 0; i < 3; i++) { Drain(); SBApply(&L); }
        Expect(!LBHVisibleBar(L.cs).drawn && [[gLog componentsJoinedByString:@"\n"] containsString:@"STILL drawn"] && [[gLog componentsJoinedByString:@"\n"] containsString:@"made again"],
               [NSString stringWithFormat:@"request %d in one appearance: the bar read as drawn, our request made again, then hidden", round]);
    }
    // the dismissal's start, a cancelled swipe, the Cover Sheet gone, iPadOS's own invalidation, the switch off
    gLSBDismissing = YES; LSBRealBar((UIViewController *)L.cs, YES, "the dismissal starts"); SBApply(&L);
    Expect(!LBHReasonIn() && LBHVisibleBar(L.cs).drawn && objc_getAssociatedObject(L.cs, LBH_FLAG_KEY) == nil, @"the dismissal starts: ours given back at once, the flag cleared");
    gLSBDismissing = NO; LSBRealBar((UIViewController *)L.cs, YES, "appearing"); SBApply(&L);
    Expect(LBHReasonIn() && !LBHVisibleBar(L.cs).drawn, @"a swipe let go (it appears again): hidden again");
    LSBRealBar((UIViewController *)L.cs, NO, "switched off"); SBApply(&L);
    Expect(!LBHReasonIn() && LBHVisibleBar(L.cs).drawn, @"switched off while shown: given back");
    L.cover.hidden = YES; LSBRealBar((UIViewController *)L.cs, YES, "a status update"); Expect(!LBHReasonIn(), @"a Cover Sheet not shown never takes ours"); L.cover.hidden = NO;
    gOther = YES; LSBRealBar((UIViewController *)L.cs, YES, "appearing"); Expect(!LBHReasonIn() && objc_getAssociatedObject(L.cs, LBH_FLAG_KEY) == nil, @"another modification hides it: ours stays out"); gOther = NO;
    // ---- 17 at rest: the Cover Sheet's copy is the bar; with it off and SpringBoard's at alpha 0 nothing is drawn, and ours changes nothing visible ----
    L = MakeLock(); [L.sbc setStatusBarAlpha:@0 style:0 legibilitySettings:nil]; SBApply(&L);
    Expect(!LBHVisibleBar(L.cs).drawn, @"17 at rest with the copy off: nothing drawn (the published behaviour kept)");
    LSBRealBar((UIViewController *)L.cs, YES, "appearing"); SBApply(&L); Drain();
    Expect(!LBHVisibleBar(L.cs).drawn && LBHReasonIn(), @"17: ours in as well, still nothing drawn");
    LBHSet(L.cs, NO);
    // ---- no call on this iPadOS: the copy only, and the log says so ----
    [gLog removeAllObjects];
    gLSBNoCallLogged = NO;
    CSCoverSheetViewController *csNone = [CSCoverSheetViewController new]; csNone.view = L.cv; csNone->_coverSheetContext = bad;
    LSBRealBar((UIViewController *)csNone, YES, "appearing"); Drain();
    Expect([[gLog componentsJoinedByString:@"\n"] containsString:@"has no SpringBoard call"] && !LBHReasonIn(), @"no call: nothing asked, the log says only the copy is turned off");

    printf("test-lockbarhide: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
} }
