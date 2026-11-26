// test-smbartouch.m -- Mac test of what a touch on the menu bar is with the Stage Manager engine (1.8.1, GitHub #10): the code as built. test-smbartouch.sh cuts DMSMMainBarOn,
// DMSMMainBarShown, DMSMStripIsMenuBar, DMSMScreenPointOnMenuBar, DMSMTouchOnMenuBar, DMSMIsWindowDrag, DMSMWindowDragLeavesTouch and DMSMUnpinBegin out of statusbar/StatusBar.x into
// smbartouch-gen.h, and this file gives them stand-ins for UIKit and SpringBoard. iPadOS 17 and 18 leave the screen's own bar on over a full-screen window with a window in front of it: a
// point on that bar read as not on the menu bar, and a slide along it began Stage Manager's window drag, which brought the full-screen window over the small one. 1.8.4 device pass (A12Z
// 18.5): with one of our menus or cards open, a drag on it over a window's top part (the Now Playing card's scrubber) moved that window: such a touch stays out of the drag too.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit's parts these functions read (a view is its origin on its screen and its size: the turned spaces are the device rows' part) ---------------------
@interface UIScreen : NSObject + (UIScreen *)mainScreen; - (id)coordinateSpace; @end
@implementation UIScreen + (UIScreen *)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; } - (id)coordinateSpace { return self; } @end
@class UIWindow;
@interface UIView : NSObject
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, strong) UIWindow *ownWindow;
@property (nonatomic) BOOL hidden, inFullCard;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) CGRect bounds;
@property (nonatomic) CGPoint origin;   // (of the bounds, on the screen)
- (UIWindow *)window;
- (CGPoint)convertPoint:(CGPoint)p fromCoordinateSpace:(id)s;
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id)s;
- (CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)s;
- (BOOL)isDescendantOfView:(UIView *)v;
@end
@interface UIWindow : UIView @property (nonatomic, strong) UIScreen *screen; @end
@implementation UIView
- (instancetype)init { if ((self = [super init])) _alpha = 1.0; return self; }
- (UIWindow *)window { return self.ownWindow ?: self.superview.window; }
- (CGPoint)convertPoint:(CGPoint)p fromCoordinateSpace:(id)s { return CGPointMake(p.x - self.origin.x, p.y - self.origin.y); }
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id)s { return CGPointMake(p.x + self.origin.x, p.y + self.origin.y); }
- (CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)s { return CGRectOffset(r, self.origin.x, self.origin.y); }
- (BOOL)isDescendantOfView:(UIView *)v { for (UIView *x = self; x; x = x.superview) if (x == v) return YES; return NO; }
@end
@implementation UIWindow @end
@interface SBStatusBarWindow : UIWindow @end @implementation SBStatusBarWindow @end
@interface UIStatusBarWindow : UIWindow @end @implementation UIStatusBarWindow @end
@interface SBMainSwitcherWindow : UIWindow @end @implementation SBMainSwitcherWindow @end
@interface _UISystemGestureWindow : UIWindow @end @implementation _UISystemGestureWindow @end
typedef long UITouchType;
enum { UITouchTypeDirect = 0, UITouchTypeIndirectPointer = 3 };
@interface UITouch : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic) CGPoint at;
@property (nonatomic) UITouchType type;
- (CGPoint)locationInView:(id)v;
@end
@implementation UITouch - (CGPoint)locationInView:(id)v { return self.at; } @end
@interface UIGestureRecognizer : NSObject @property (nonatomic, strong) UIView *view; @end
@implementation UIGestureRecognizer @end
@interface UIPanGestureRecognizer : UIGestureRecognizer
@property (nonatomic) CGPoint now, moved;
- (CGPoint)locationInView:(id)v;
- (CGPoint)translationInView:(id)v;
@end
@implementation UIPanGestureRecognizer - (CGPoint)locationInView:(id)v { return self.now; } - (CGPoint)translationInView:(id)v { return self.moved; } @end
// ---- SpringBoard's manager, by the ivar the sources read ------------------------------------------------------------------------------------------------
@interface SBFluidSwitcherGestureManager : NSObject { @public UIGestureRecognizer *_unpinSplitViewApplicationGestureRecognizer; } @end
@implementation SBFluidSwitcherGestureManager @end
// ---- the rest of the tweak at that moment ----------------------------------------------------------------------------------------------------------------
static long long gEnvMode = 3;
static BOOL gSTUI = YES, gFree = YES, gOverWindows = NO, gFullOwn = NO, gAppleAnswer = YES, gAsBuilt = NO;
static int gAppleAsked = 0;
static NSHashTable *gCopies, *gAllBarCopies;
static const void *kHoldKey = &kHoldKey, *kHoldWantAlphaKey = &kHoldWantAlphaKey;
static BOOL DMSBUseSTUI(void) { return gSTUI; }
static BOOL DMSMFree(void) { return gFree; }
static BOOL DMSMOverWindows(void) { return gOverWindows; }
static BOOL DMSMTouchFullScreenOwn(UITouch *t) { return gFullOwn; }
static BOOL DMSMTouchOnDock(UITouch *t) { return NO; }   // (1.8.9 GitHub #20: the Dock's own question, test-smdocktouch.sh)
static BOOL gMenuOpen = NO;
static UIScreen *gMenuScreen = nil;   // (the screen our open menu is on: nil the iPad's)
static BOOL DMSMOurMenuOpen(void) { return gMenuOpen; }   // (the code before review 1.8.4 P3-L3 asked this: any screen)
static UIScreen *DMSMTouchScreen(id t) { return ([t isKindOfClass:[UITouch class]] ? ((UITouch *)t).window.screen : nil) ?: [UIScreen mainScreen]; }
static BOOL DMSMOurMenuOpenOn(UIScreen *screen) { return gMenuOpen && (screen ?: [UIScreen mainScreen]) == (gMenuScreen ?: [UIScreen mainScreen]); }
static BOOL DMSMInFullScreenCard(UIView *v) { return v.inFullCard; }
static BOOL DMSMScreenInSwitcher(UIScreen *screen) { return gEnvMode == 2; }   // (1.8.7: that screen's own switcher; its rule per display is test-smbarhome's)
static BOOL DMTestFlag(const char *f) { return gAsBuilt && strcmp(f, "/tmp/msb-sm-bartouch-asbuilt") == 0; }
static void DMLog(NSString *s) { }
#define DM_FEATURE_MARK(x) do { } while (0)
static BOOL (*o_SMUnpinBegin)(id, SEL, id);
static BOOL AppleBegin(id self, SEL _cmd, id g) { gAppleAsked++; return gAppleAnswer; }
// ---- 1.8.9 (B114): our title bars (DMSMTitleBar: its window's key, its card), the windows' own hit test (DMSMTouchTarget: what the test sets), the card a
//      view is in and its key, Stage Manager's own drag's transaction (SMGestureHook.h's list), the pointer's resize band (which card it marks)
@interface DMSMTitleBar : UIView
@property (nonatomic, copy) NSString *key, *bundle;
@property (nonatomic, strong) UIView *card;
@end
@implementation DMSMTitleBar @end
static NSHashTable *gSMBars;
static UIView *gHit; static int gHitAsked = 0;
static UIView *DMSMTouchTarget(UITouch *x, id event, UIScreen *screen, CGPoint p) { gHitAsked++; return gHit; }
static NSMapTable *gCardKeys;   // (card view -> its window's key)
static UIView *DMSMCardOfView(UIView *v) { for (UIView *x = v; x; x = x.superview) if ([gCardKeys objectForKey:x]) return x; return nil; }
static NSString *DMSMCardKey(UIView *card) { return [gCardKeys objectForKey:card]; }
static BOOL DMSMEngine(void) { return gFree; }
static UIView *gResizeCard;   // (the card whose resize band the pointer marks)
static BOOL DMSMPointerOnResizeEdge(UIView *card) { return card && card == gResizeCard; }
static NSString *DMSMKeyText(NSString *k) { return k; }
@interface SBWindowDragGestureWorkspaceTransaction : NSObject
@property (nonatomic) BOOL complete;
@end
@implementation SBWindowDragGestureWorkspaceTransaction
- (bool)isComplete { return self.complete; }   // (bool: 'B', as BOOL is on the iPads' arm64)
@end
static NSHashTable *gSMGestureTxs;
static BOOL DMSMGTGetter(id t, SEL s, char ret) {   // (SMGestureHold.h's)
    Method m = t ? class_getInstanceMethod(object_getClass(t), s) : NULL;
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char r[8] = {0}; method_getReturnType(m, r, sizeof r);
    return r[0] == ret;
}
static NSString *gSMAppleDragKey; static BOOL gSMAppleDragPast;
static NSString *gSMPastEdgeResizeKey;   // (a resize by hand followed: a drag ends it)
#include "smbartouch-gen.h"

// ---- a screen, 1366 x 1024, with a bar and a full-screen card's strip -----------------------------------------------------------------------------------
static UIView *Bar(Class wc, UIScreen *scr, CGRect barRect, NSMutableArray *keep) {   // (the foreground view of a bar in a window of that class; its superview is the whole bar)
    UIWindow *w = [wc new]; w.screen = scr; w.ownWindow = w; w.bounds = CGRectMake(0, 0, 1366, 1024);
    UIView *bar = [UIView new]; bar.superview = w; bar.bounds = CGRectMake(0, 0, barRect.size.width, barRect.size.height); bar.origin = barRect.origin;
    UIView *fg = [UIView new]; fg.superview = bar; fg.bounds = bar.bounds; fg.origin = bar.origin;
    [keep addObject:w]; [keep addObject:bar]; [keep addObject:fg];
    [gAllBarCopies addObject:fg]; [gCopies addObject:fg];
    return fg;
}
static BOOL On(CGFloat x, CGFloat y) { return DMSMScreenPointOnMenuBar(CGPointMake(x, y), [UIScreen mainScreen]); }
static UITouch *Touch(CGFloat x, CGFloat y) { UITouch *t = [UITouch new]; UIWindow *w = [_UISystemGestureWindow new]; w.screen = [UIScreen mainScreen]; w.ownWindow = w; t.window = w; t.at = CGPointMake(x, y); return t; }

int main(void) { @autoreleasepool {
    SBFluidSwitcherGestureManager *mgr = [SBFluidSwitcherGestureManager new];
    UIPanGestureRecognizer *drag = [UIPanGestureRecognizer new];
    UIGestureRecognizer *other = [UIGestureRecognizer new];
    mgr->_unpinSplitViewApplicationGestureRecognizer = drag;
    UIWindow *gw = [_UISystemGestureWindow new]; gw.screen = [UIScreen mainScreen]; gw.ownWindow = gw;
    UIView *gv = [UIView new]; gv.superview = gw; drag.view = gv;
    o_SMUnpinBegin = AppleBegin;
    NSMutableArray *keep;
    #define RESET() do { keep = [NSMutableArray array]; gCopies = [NSHashTable weakObjectsHashTable]; gAllBarCopies = [NSHashTable weakObjectsHashTable]; gEnvMode = 3; gSTUI = YES; gFree = YES; gOverWindows = NO; gFullOwn = NO; gAppleAnswer = YES; gAppleAsked = 0; gAsBuilt = NO; gMenuOpen = NO; gMenuScreen = nil; } while (0)

    // iPadOS 17 and 18: a full-screen window with a smaller one in front. The screen's own bar shows; the card's strip is there, hidden.
    RESET();
    UIView *own = Bar([SBStatusBarWindow class], [UIScreen mainScreen], CGRectMake(0, 0, 1366, 37), keep);
    UIView *strip = Bar([SBMainSwitcherWindow class], [UIScreen mainScreen], CGRectMake(0, 0, 1366, 37), keep); strip.inFullCard = YES; strip.alpha = 0.0;
    Expect(On(600, 18), @"17/18, a window in front: a point on the screen's own bar is on the menu bar");
    Expect(On(600, 0) && On(0, 18) && On(1365.5, 36.5), @"  ... to its corners");
    Expect(!On(600, 37) && !On(600, 45) && !On(600, 400), @"  ... and not a point under it (the full-screen window's own, a title bar right under the bar)");
    Expect(!DMSMStripIsMenuBar(strip), @"  ... the card's strip is not the menu bar then, as before");
    gEnvMode = 2; Expect(!On(600, 18), @"  ... not in the App Switcher (a card's touch is the card's)"); gEnvMode = 3;
    gAsBuilt = YES; Expect(!On(600, 18), @"  ... the debug A/B flag: as before the fix"); gAsBuilt = NO;
    Expect(DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 18)), @"Stage Manager's window drag leaves a touch that starts on that bar");
    Expect(!DMSMWindowDragLeavesTouch(mgr, other, Touch(600, 18)), @"  ... no other recogniser of the manager's is asked to");
    gFree = NO; Expect(!DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 18)), @"  ... and not without the engine (Apple's layout)"); gFree = YES;
    Expect(!DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 45)), @"  ... a touch under the bar stays the drag's while it is no full-screen window under windows");
    gFullOwn = YES; Expect(DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 45)), @"  ... a touch on a full-screen window under windows stays out of it from its start"); gFullOwn = NO;
    // one of our menus, cards or dialogs open: its catch-all takes every point, so the touch is the menu's (1.8.4 device pass, A12Z 18.5: the card's scrubber moved a window)
    gMenuOpen = YES;
    Expect(DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 45)), @"one of our menus or cards open: a touch on a window's top part stays out of the window drag (the card's scrubber, a menu's row)");
    Expect(DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 400)), @"  ... anywhere else too (the catch-all's, which closes the menu)");
    Expect(!DMSMWindowDragLeavesTouch(mgr, other, Touch(600, 45)), @"  ... no other recogniser of the manager's is asked to (the Home and App Switcher swipes stay)");
    gFree = NO; Expect(!DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 45)), @"  ... and not without the engine (Apple's layout)"); gFree = YES;
    // review 1.8.4 P3-L3: only on the screen the menu is open on (a menu on the TV has no catch-all on the iPad, and the other way round)
    UIScreen *tvScreen = [UIScreen new];
    gMenuScreen = tvScreen;
    Expect(!DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 45)), @"P3-L3: a menu open on the TV: a touch on the iPad's window top stays the window drag's");
    UITouch *tvTouch = Touch(600, 45); tvTouch.window.screen = tvScreen;
    Expect(DMSMWindowDragLeavesTouch(mgr, drag, tvTouch), @"  ... a touch on the TV, where the menu is: left out of the TV's window drag");
    gMenuScreen = nil;
    Expect(!DMSMWindowDragLeavesTouch(mgr, drag, tvTouch), @"  ... a menu open on the iPad: the TV's window drag keeps its touch");
    gMenuOpen = NO;
    Expect(!DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 45)), @"  ... closed again: the touch is the window drag's");
    // the begin question: its own start, with no touch at hand
    drag.now = CGPointMake(900, 18); drag.moved = CGPointMake(300, 0); gAppleAsked = 0;
    Expect(!DMSMUnpinBegin(mgr, NULL, drag) && gAppleAsked == 0, @"the begin question: a start on the bar: no, Apple's not asked");
    drag.now = CGPointMake(600, 300); drag.moved = CGPointMake(0, 255); gAppleAsked = 0;
    Expect(DMSMUnpinBegin(mgr, NULL, drag) && gAppleAsked == 1, @"  ... a start under the bar: Apple's answer");
    drag.now = CGPointMake(100, 18); drag.moved = CGPointMake(90, 0); gAppleAsked = 0;
    Expect(!DMSMUnpinBegin(mgr, NULL, drag) && gAppleAsked == 0, @"  ... the left edge's rule stays");
    gOverWindows = YES; drag.now = CGPointMake(600, 300); drag.moved = CGPointMake(0, 255); Expect(!DMSMUnpinBegin(mgr, NULL, drag), @"  ... and the Mac Switcher's view over the windows"); gOverWindows = NO;

    // A full-screen window with none in front, on any of them: the screen's own bar is faded, the card's strip is the menu bar.
    own.superview.alpha = 0.0; strip.alpha = 1.0;
    Expect(DMSMStripIsMenuBar(strip) && On(600, 18) && !On(600, 37), @"17/18, none in front (the screen's bar faded): the card's strip is the menu bar, as before");
    Expect(!DMSMWindowDragLeavesTouch(mgr, drag, Touch(600, 50)), @"  ... under it the drag stays Apple's");
    own.superview.alpha = 1.0; own.hidden = YES;
    Expect(DMSMStripIsMenuBar(strip) && On(600, 18), @"  ... a hidden copy of the screen's bar does not show either");
    own.hidden = NO; strip.alpha = 0.0;
    // what iPadOS asked for counts, not our hold (a new copy after a respring, or at an unlock, is held at 0)
    own.alpha = 0.0; objc_setAssociatedObject(own, kHoldKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(own, kHoldWantAlphaKey, @1.0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Expect(On(600, 18), @"a copy of the screen's bar we hold: judged by the opacity iOS asked for (shown)");
    objc_setAssociatedObject(own, kHoldWantAlphaKey, @0.0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Expect(!On(600, 18), @"  ... (not shown)");
    objc_setAssociatedObject(own, kHoldKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); own.alpha = 1.0;
    // a bar of another size: its own rectangle
    own.superview.bounds = CGRectMake(0, 0, 1024, 26); own.bounds = own.superview.bounds;
    Expect(On(500, 25.5) && !On(500, 26) && !On(1100, 10), @"the bar's own rectangle: Small, in portrait");
    // a small copy (the mini bars of a hidden switcher) is no bar
    own.bounds = CGRectMake(0, 0, 200, 26);
    Expect(!On(100, 10), @"a narrow copy in that window is not the bar");

    // A copy in a window card that is no full-screen one (a plain window's strip, shown or not): no menu bar, and not the screen's own either.
    RESET();
    Bar([SBMainSwitcherWindow class], [UIScreen mainScreen], CGRectMake(100, 100, 800, 24), keep);
    Expect(!On(500, 110), @"a plain window's strip is no menu bar: only the status bar window's copy is the screen's own");

    // Another screen's bar says nothing about this one.
    RESET();
    UIScreen *tv = [UIScreen new];
    Bar([SBStatusBarWindow class], tv, CGRectMake(0, 0, 1920, 30), keep);
    Expect(!On(600, 18), @"the TV's bar is not this screen's");
    Expect(DMSMScreenPointOnMenuBar(CGPointMake(1500, 10), tv), @"  ... and a point on it is on that screen's");

    // iPadOS 15 and 16: the screen's bar window has another class and was never asked by name; a full-screen card's strip stays the menu bar under windows too.
    RESET(); gSTUI = NO;
    Bar([UIStatusBarWindow class], [UIScreen mainScreen], CGRectMake(0, 0, 1024, 20), keep);
    Expect(!On(500, 10), @"15/16: no strip is the menu bar: the answer stays no (a plain window: nothing asks Apple's drag there)");
    UIView *s16 = Bar([SBMainSwitcherWindow class], [UIScreen mainScreen], CGRectMake(0, 0, 1024, 20), keep); s16.inFullCard = YES;
    Expect(On(500, 10) && !On(500, 20), @"  ... the full-screen card's strip counts, as item 8 made it");
    s16.alpha = 0.0; Expect(!On(500, 10), @"  ... not while it does not show");
    RESET(); gSTUI = NO;
    Bar([SBStatusBarWindow class], [UIScreen mainScreen], CGRectMake(0, 0, 1024, 20), keep);
    Expect(!On(500, 10), @"  ... and that window's name is only asked on 17 and 18");

    // 1.8.9 (B114, the NIT): two windows' title bars at one point -- the front window's over the one behind -- : the bar a touch there is on is the front
    // one, the one the windows' own hit test lands in (the first of the set was taken: the log named the window behind, and a pointer's press was asked
    // about its card's resize band). One bar there: as before, no hit test.
    RESET();
    gSMBars = [NSHashTable weakObjectsHashTable]; gCardKeys = [NSMapTable strongToStrongObjectsMapTable];
    UIWindow *sw = [SBMainSwitcherWindow new]; sw.screen = [UIScreen mainScreen]; sw.ownWindow = sw; [keep addObject:sw];
    DMSMTitleBar *(^bar)(NSString *, CGRect) = ^DMSMTitleBar *(NSString *k, CGRect r) {
        UIView *card = [UIView new]; card.superview = sw; card.origin = CGPointMake(r.origin.x, r.origin.y + 24); card.bounds = CGRectMake(0, 0, r.size.width, 400);
        DMSMTitleBar *b = [DMSMTitleBar new]; b.superview = card; b.origin = r.origin; b.bounds = CGRectMake(0, 0, r.size.width, 24); b.key = k; b.card = card;
        [gCardKeys setObject:k forKey:card]; [keep addObject:card]; [keep addObject:b]; [gSMBars addObject:b];
        return b;
    };
    DMSMTitleBar *behind = bar(@"com.apple.tips|sceneID:com.apple.tips-default", CGRectMake(100, 100, 600, 24));
    DMSMTitleBar *front = bar(@"com.apple.Preferences|sceneID:com.apple.Preferences-default", CGRectMake(300, 100, 600, 24));
    UIView *light = [UIView new]; light.superview = front; [keep addObject:light];
    DMSMTitleBar *firstOfSet = nil; for (DMSMTitleBar *b in gSMBars.allObjects) { firstOfSet = b; break; }
    DMSMTitleBar *otherOfSet = firstOfSet == front ? behind : front;
    UITouch *tb = Touch(500, 110);
    gHit = otherOfSet; gHitAsked = 0;
    Expect(DMSMTitleBarAt(CGPointMake(500, 110), [UIScreen mainScreen], tb) == otherOfSet && gHitAsked == 1, @"B114: two title bars at the point: the one the hit test lands in (not the first of the set)");
    gHit = firstOfSet;
    Expect(DMSMTitleBarAt(CGPointMake(500, 110), [UIScreen mainScreen], tb) == firstOfSet, @"  ... the other way round too");
    gHit = light;
    Expect(DMSMTitleBarAt(CGPointMake(500, 110), [UIScreen mainScreen], tb) == front, @"  ... a light of the front bar: that bar");
    gHit = nil;
    Expect(DMSMTitleBarAt(CGPointMake(500, 110), [UIScreen mainScreen], tb) == firstOfSet, @"  ... the hit test reaching neither: the first, as before");
    gHit = otherOfSet; gHitAsked = 0;
    Expect(DMSMTitleBarAt(CGPointMake(200, 110), [UIScreen mainScreen], Touch(200, 110)) == behind && gHitAsked == 0, @"  ... one bar at the point: that bar, no hit test (as before)");
    Expect(DMSMTitleBarAt(CGPointMake(200, 300), [UIScreen mainScreen], Touch(200, 300)) == nil, @"  ... none there: none");
    // the pointer's press on the overlap: only the window behind has its resize band there; the front window's bar is the drag's
    gHit = front; gResizeCard = behind.card;
    UITouch *tp = Touch(500, 110); tp.type = UITouchTypeIndirectPointer;
    Expect(DMSMTitleBarDragTouch(mgr, drag, tp), @"B114: a pointer's press on the front window's bar, over the band of the window behind it: the bar's drag (Apple's window drag left out)");
    gResizeCard = front.card;
    Expect(!DMSMTitleBarDragTouch(mgr, drag, tp), @"  ... on the front window's own resize band: SpringBoard's live resize, as before");
    gResizeCard = nil;
    Expect(DMSMTitleBarDragTouch(mgr, drag, Touch(500, 110)) && !DMSMTitleBarDragTouch(mgr, other, Touch(500, 110)) && !DMSMTitleBarDragTouch(mgr, drag, Touch(500, 300)),
           @"  ... a finger on a title bar: the bar's; another recogniser, or a point on no bar: not asked to");

    // (review: a third window's card in front of both bars there: the touch is that window's -- no title bar's; a view that is no window card's: the first, as before)
    UIView *third = [UIView new]; third.superview = sw; [keep addObject:third]; [gCardKeys setObject:@"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-x" forKey:third];
    UIView *thirdContent = [UIView new]; thirdContent.superview = third; [keep addObject:thirdContent];
    gHit = thirdContent;
    Expect(DMSMTitleBarAt(CGPointMake(500, 110), [UIScreen mainScreen], tb) == nil, @"B114: a third window's card in front of both bars: no title bar's touch (Apple's drag of that window may take it)");
    gHit = front.card;
    Expect(DMSMTitleBarAt(CGPointMake(500, 110), [UIScreen mainScreen], tb) == firstOfSet, @"  ... the hit in one of the two bars' own cards (not their bars): the first, as before");

    // 1.8.9 (B114): Stage Manager's own window drag begins (Apple's begin answer yes): the window under the finger where it went down -- the windows' own hit
    // test there, its card -- is noted for the layout passes (a resize by hand's follow ends); Apple's no, our refusals, no engine: nothing noted
    gSMGestureTxs = [NSHashTable weakObjectsHashTable]; gSMAppleDragKey = nil;
    UIView *inCard = [UIView new]; inCard.superview = front.card; [keep addObject:inCard];
    gHit = inCard; gSMPastEdgeResizeKey = @"a resize followed";
    drag.now = CGPointMake(600, 300); drag.moved = CGPointMake(100, 160); gAppleAsked = 0; gAppleAnswer = YES;
    Expect(DMSMUnpinBegin(mgr, NULL, drag) && [gSMAppleDragKey isEqualToString:front.key] && gSMPastEdgeResizeKey == nil,
           @"B114: Stage Manager's own drag begins: the window under the finger noted (its card's key), a resize's follow ended");
    gHit = behind; gAppleAnswer = NO;
    Expect(!DMSMUnpinBegin(mgr, NULL, drag) && [gSMAppleDragKey isEqualToString:front.key], @"  ... Apple's answer no (no drag): nothing noted");
    gAppleAnswer = YES; drag.now = CGPointMake(100, 300); drag.moved = CGPointMake(90, 0);
    Expect(!DMSMUnpinBegin(mgr, NULL, drag) && [gSMAppleDragKey isEqualToString:front.key], @"  ... a start in the left edge's zone (refused): nothing noted");
    drag.now = CGPointMake(600, 300); drag.moved = CGPointMake(100, 160);
    gHit = [UIView new]; [keep addObject:gHit];
    Expect(DMSMUnpinBegin(mgr, NULL, drag) && gSMAppleDragKey == nil, @"  ... a start on no window card: no window noted (the one before forgotten)");
    gHit = inCard; gFree = NO;
    Expect(DMSMUnpinBegin(mgr, NULL, drag) && gSMAppleDragKey == nil, @"  ... without the engine: nothing noted");
    gFree = YES;
    SBWindowDragGestureWorkspaceTransaction *tx = [SBWindowDragGestureWorkspaceTransaction new];
    Expect(!DMSMWindowDragLive(), @"  ... no drag transaction: not running");
    [gSMGestureTxs addObject:tx]; Expect(DMSMWindowDragLive(), @"  ... running while its transaction is in SpringBoard's list");
    tx.complete = YES; Expect(!DMSMWindowDragLive(), @"  ... complete (not out of the list yet): over"); [gSMGestureTxs removeObject:tx];

    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
} }
