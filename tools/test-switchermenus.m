// test-switchermenus.m: the model test-switchermenus.sh builds the real code into (1.8.8.2 B71: a switcher opening closes every menu of ours).
// The .sh cuts out of the source, into the folder it builds in:
//   open.inc   statusbar/MacSwitcher.h DMMSWOpenNow, the Mac Switcher's one open point (Control-Up, Home double press, the App Switcher gesture's
//              hold, the Apple menu's row, a TV's, a request kept while busy: every way ends there)
//   close.inc  statusbar/StatusBar.x DMCloseMenusForSwitcher, the switchers' one close (empty in a tree before 1.8.8.2)
//   tick.inc   statusbar/StatusBar.x the tick's block that closes a menu for iPadOS's system UI
//   stack.inc  dock/Downloads.m MSBDDownloadsPanelSwitcherClose, the Dock part's close of its stack panel (empty before 1.8.8.2)
//   shown.inc  statusbar/StatusBar.x DMMenusOfOursShown, and dlshown.inc dock/Downloads.m MSBDDownloadsPanelShown: something of ours on the screen
//              (B71 review; empty before it, then HAVE_SHOWN is not defined)
//   start.inc  statusbar/MacSwitcher.h DMMSWStartPicture, a gesture's start picture (the hold's, B71 review: marked when a menu of ours was on it)
// and 1.8.8.1's own DMMSWOpenNow and tick block are kept below as they were (the .sh compares them with 56d9461b when the history has it).
// Everything they call is a stub: it writes one event to the trace, and the checks read the traces and the model's state. The Dock part's
// export is found by the real dlsym in this program, by the name StatusBar.x asks for.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include "OverlayClose.h"

static NSMutableArray<NSString *> *T;   // the trace
static void ev(NSString *s) { [T addObject:s]; }
#define DMLog(...) ev([@"log " stringByAppendingString:(__VA_ARGS__)])
#define DM_FEATURE_MARK(name) ev(@"mark " name)
#define DMMSWSpanBegin() ev(@"span begin")
#define DMMSWSpanEnd(...) ev([@"span end " stringByAppendingString:(__VA_ARGS__)])

// ---- UIKit, as far as the cut code touches it ----
@interface UIView : NSObject
@property (nonatomic, copy) NSString *name;
@end
@implementation UIView
@end
@interface UIWindow : UIView
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic) BOOL hidden;
- (void)layoutIfNeeded;
@end
@implementation UIWindow
- (void)setHidden:(BOOL)h { _hidden = h; ev(h ? @"window hidden" : @"window shown"); }
- (void)setUserInteractionEnabled:(BOOL)u { _userInteractionEnabled = u; ev(u ? @"window takes touches" : @"window lets touches through"); }
- (void)layoutIfNeeded { ev(@"window laid out"); }
@end
@interface UIScreen : NSObject
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)after;
@end
@implementation UIScreen
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)after { ev(@"picture: the screen, waiting"); UIView *v = [UIView new]; v.name = @"waiting"; return v; }
@end
static NSString *NSStringFromCGSize(CGSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }

// ---- the world ----
typedef struct {
    BOOL on, open, closing, gaRefuses, switcherUp, grace, cover, switching, noLayer, stripOut;
    int track;
    BOOL liftAny, liftPic, liftIdSame, liftFresh, liftGenSame, asyncOn, main, asyncAsks, withoutView, keep;
    BOOL menu, panel;   // a menu of ours open (gOverlay), the Dock's Downloads stack panel open
    BOOL liftMenu;      // the gesture's start picture was asked for with a menu of ours on the screen (B71 review: it is in that picture)
} World;
static World W;
static double gNow = 1000.0;
static double CACurrentMediaTime(void) { return gNow; }
static BOOL DMTestFlag(const char *path) {
    if (!strcmp(path, "/tmp/msw-liftany")) return W.liftAny;
    if (!strcmp(path, "/tmp/msb-overlay-keep")) return W.keep;
    return NO;
}
// the menu window's overlay, and its one close (StatusBar.x DMCloseOverlay: its state is its own tests')
static UIView *gOverlay;
static void DMCloseOverlay(void) { ev(gOverlay ? @"DMCloseOverlay (a menu open)" : @"DMCloseOverlay (none open)"); gOverlay = nil; }
// the Dock part's panel (dock/Downloads.m's class, as far as its export uses it)
@interface DMDownloadsPanel : NSObject
+ (instancetype)shared;
- (BOOL)isOpen;
- (void)dismissAnimated:(BOOL)animated;
@property (nonatomic) BOOL opened;
@end
@implementation DMDownloadsPanel
+ (instancetype)shared { static DMDownloadsPanel *p; if (!p) p = [DMDownloadsPanel new]; return p; }
- (BOOL)isOpen { return self.opened; }
- (void)dismissAnimated:(BOOL)animated { ev(animated ? @"stack panel closes (animated)" : @"stack panel closes"); self.opened = NO; }
@end
// the Mac Switcher's state
static BOOL gMSWOn, gMSWClosing, gMSWSwitching, gMSWOpen;
static int gMSWTrack;
static UIView *gMSWLiftPic, *gMSWOpenShot;
static BOOL gMSWLiftPicMenu;
static __weak id gMSWLiftPicGesture;
static UIView *gMSWSlRoot;
static NSInteger gMSWLiftPicId, gMSWOpenShotId;
static CFTimeInterval gMSWLiftPicAt;
static NSUInteger gMSWLiftPicGen, gMSWTrackPicGen, gMSWOpenShotGen;
static UIWindow *gMSWWindow, *gLayer;
static NSMutableArray *gMSWTiles;
static NSMutableArray<UIView *> *gMSWPortals;
static CGSize gMSWBuiltSize;
static UIScreen *gScreen;
static void (^gAsyncDone)(UIView *pic, double ms);
static BOOL DMMSWIsOpen(void) { return gMSWOpen; }
static void DMMSWClose(id pick, BOOL animated) { ev(@"the view closes (asked again while open)"); }
static BOOL DMGARefuses(NSString *what) { if (W.gaRefuses) ev(@"Guided Access refuses"); return W.gaRefuses; }
static BOOL DMSwitcherVisible(void) { return W.switcherUp; }
static BOOL DMMSWGestureGrace(void) { return W.grace; }
static BOOL DMCoverSheetShown(void) { return W.cover; }
static UIWindow *DMMSWLayer(void) { if (W.noLayer) return nil; gMSWWindow = gLayer; return gLayer; }
static void DMDesktopTypingEnd(NSString *why) { ev([@"typing ends: " stringByAppendingString:why]); }
static BOOL DMSMStripPresentationEnd(NSString *why) { if (W.stripOut) ev(@"the strip goes"); return W.stripOut; }
static NSInteger DMMSWCurId(void) { return 3; }
static void DMMSWOpenShotDrop(void) { gMSWOpenShot = nil; gMSWOpenShotGen++; }
static BOOL DMMSWAsyncScreenOn(void) { return W.asyncOn; }
static BOOL DMMSWIsMain(void) { return W.main; }
static BOOL DMMSWScreenPictureAsync(NSArray<UIWindow *> *exclude, void (^done)(UIView *pic, double ms)) {
    if (!W.asyncAsks) return NO;
    ev([NSString stringWithFormat:@"picture: asked without waiting, %lu window(s) left out", (unsigned long)exclude.count]);
    gAsyncDone = done;
    return YES;
}
static UIView *DMMSWScreenWithoutView(void) { if (!W.withoutView) return nil; ev(@"picture: the screen without the view"); UIView *v = [UIView new]; v.name = @"without"; return v; }
static UIScreen *DMMSWScreen(void) { return gScreen; }
static void DMMSWFocus(BOOL take) { ev(take ? @"keyboard focus to the view" : @"keyboard focus back"); }
static void DMMenuKeyboardOrder(void) { ev(@"keyboard order"); }
static void DMMSWBuild(BOOL animated) { ev(@"the view is built"); }
// the tick's reads
static BOOL gOverlayOpenedOverSpotlight, gOverlayOpenedOverCover;
static long long gEnvMode;
static UIWindow *gKbLowered;
typedef struct { BOOL switcher, lock, spot, cover, env2, ccPresented, kb; } TickWorld;
static TickWorld TW;
static BOOL DMSpotlightShown(void) { return TW.spot; }
static id DMSBManager(const char *cls) { return @"the lock screen manager"; }
static BOOL DMLockUp(id mgr) { return TW.lock; }
static id DMControlCenterController(void) { return @"cc"; }
static NSString *DMBoolStr(id obj, NSString *name) { return TW.ccPresented ? @"Y" : @"N"; }

// the gesture's start (DMMSWStartPicture)
static BOOL gGesturesOn = YES, gAsyncPicturesOK = YES;
static BOOL DMMSWGesturesOn(void) { return gGesturesOn; }
static long long DMMSWGestureTypeOf(id gesture) { return gesture ? 1 : 0; }
static BOOL DMMSWAsyncPicturesOK(void) { return gAsyncPicturesOK; }

// iPadOS's App Switcher asked for from the Apple menu while the Mac Switcher is on (MacSwitcher.h DMMSWStockOnce)
static BOOL gStockOnce;
static BOOL DMMSWStockOnce(void) { return gStockOnce; }
// ---- the code under test ----
#include "close.inc"
#include "stack.inc"
#include "dlshown.inc"
#include "shown.inc"
#include "open.inc"
#include "start.inc"
#if HAVE_ENV
#include "env.inc"   // (1.8.8.3: StatusBar.x DMSwitcherEnvCloseMenus, iPadOS's App Switcher on its way: its transition event)
#endif
static void DMTickClose(BOOL ccActive) {
    BOOL (^DMSwitcherVisible)(void) = ^{ return TW.switcher; };   // (the tick's own reading)
    BOOL (^DMCoverSheetShown)(void) = ^{ return TW.cover; };
#include "tick.inc"
}
// ==== 1.8.8.1 (56d9461b), as it was: statusbar/MacSwitcher.h DMMSWOpenNow ====
#define DMMSWOpenNow DMMSWOpenNow1881
static void DMMSWOpenNow(NSString *why) {
    DM_FEATURE_MARK("mac-switcher");
    if (!gMSWOn) { DMLog([NSString stringWithFormat:@"[macswitcher] not opened (%@): switched off", why]); return; }
    if (DMMSWIsOpen()) { if (!gMSWClosing) DMMSWClose(nil, YES); return; }   // (opened again while open: it closes, like the Mission Control key)
    if (DMGARefuses([NSString stringWithFormat:@"the Mac Switcher (%@)", why])) return;   // (Guided Access keeps the iPad in one app: no other desktop, no other window -- 1.3.7, audit M-7)
    if ((DMSwitcherVisible() && !DMMSWGestureGrace()) || DMCoverSheetShown() || gMSWSwitching || gMSWTrack >= 2) { DMLog(@"[macswitcher] not opened: the App Switcher or the Lock Screen is up, or a desktop is sliding in"); return; }
    UIWindow *w = DMMSWLayer();
    if (!w) return;
    // (1.8.8.1: a name or a sticky note being typed ends first, its typing kept: the view's layer is above the typing window, its keyboard would be under it)
    DMDesktopTypingEnd(@"the Mac Switcher opens");
    // (a strip a swipe brought out goes first: the view shows the desktops' windows, StatusBar.x. No picture of the desktop is kept from a moment the
    //  strip was out, the gesture's start included: it would show the strip and the stage pushed aside for it, review 1.8.4.4 L7. A switch from the
    //  view takes the screen under the view then, as when no picture is kept)
    BOOL stripOut = DMSMStripPresentationEnd(@"the Mac Switcher opens");
    // (the desktop under the view, as a picture: the left desktop's for a switch from the strip -- the one from the start of the gesture that
    //  opens the view when there is one, as SpringBoard's card moved after it; else the screen now, before the view is drawn: a cheap picture)
    //  F5: the screen picture is asked for without waiting (DMMSWScreenPictureAsync, our window left out) -- UIKit's waiting one once held
    //  SpringBoard 3.7 s when the view opened during an app's cold launch; the view opens at once and the picture is there long before a tap in
    //  the strip can use it (else that switch takes the screen without the view, DMMSWLeftPicture)
    // (only for the gesture's own opening: a keyboard, Home double press or accessibility opening within 2 s of a gesture took that gesture's start
    //  picture -- the screen before the gesture --, and since K-1 that picture exists with one desktop too; 1.4.1 logic test L-4. Debug
    //  /tmp/msw-liftany = before.)
    BOOL byGesture = DMMSWGestureGrace() || DMTestFlag("/tmp/msw-liftany");
    BOOL lift = !stripOut && byGesture && gMSWLiftPic && gMSWLiftPicId == DMMSWCurId() && (CACurrentMediaTime() - gMSWLiftPicAt < 2.0 || (DMMSWGestureGrace() && gMSWLiftPicGen == gMSWTrackPicGen));
    DMMSWOpenShotDrop();
    gMSWOpenShotId = DMMSWCurId();
    // (opened by the hold: the picture from the gesture's start, taken before SpringBoard moved anything (DMMSWTrackBegin / DMMSWStartPicture) --
    //  the screen now is SpringBoard's own return from the hold still on screen (the Home Screen zoomed, K-1). It belongs to the gesture that opened
    //  the view whatever its age: a hold may last more than 2 s.)
#if DEBUG
    if (DMMSWGestureGrace()) DMLog([NSString stringWithFormat:@"[macswitcher] opened by the hold: the desktop's picture %@", lift ? @"from the gesture's start" : (stripOut ? @"none, the strip was out" : @"none from its start: the screen now")]);
#endif
    if (lift) gMSWOpenShot = gMSWLiftPic;
    else if (!stripOut) {
        NSUInteger gen = gMSWOpenShotGen;
        NSInteger did = DMMSWCurId();
        BOOL asked = DMMSWAsyncScreenOn() && DMMSWIsMain() && DMMSWScreenPictureAsync(gMSWWindow ? @[gMSWWindow] : @[], ^(UIView *pic, double ms) {
            BOOL use = pic && gen == gMSWOpenShotGen && gMSWOpen && DMMSWCurId() == did;
            if (use) gMSWOpenShot = pic;
            DMLog([NSString stringWithFormat:@"[macswitcher] the view's picture of the desktop under it: %@ after %.1f ms (asked without waiting)", !pic ? @"not drawn" : use ? @"in" : @"no longer needed", ms]);
        });
        if (!asked) {   // (another display: its screen the waiting way -- the picture without waiting is read for the iPad's screen only)
            // (without our window: the screen's picture is drawn at the commit, after the window below is shown and the view built in it -- the
            //  TV's Desktop 1 kept the Mac Switcher itself as its thumbnail at "+", iPad 2 over AirPlay d27)
            DMMSWSpanBegin();
            gMSWOpenShot = DMMSWScreenWithoutView() ?: [DMMSWScreen() snapshotViewAfterScreenUpdates:NO];
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
#undef DMMSWOpenNow
// ==== end of 1.8.8.1's DMMSWOpenNow ====
// ==== 1.8.8.1 (56d9461b), as it was: statusbar/StatusBar.x the tick's block that closes a menu for iPadOS's system UI ====
static void DMTickClose1881(BOOL ccActive) {
    BOOL (^DMSwitcherVisible)(void) = ^{ return TW.switcher; };
    BOOL (^DMCoverSheetShown)(void) = ^{ return TW.cover; };
    {
        static int systemUITicks = 0;
        NSString *systemUI = nil;
        BOOL spotNow = gOverlay && DMSpotlightShown();
        gOverlayOpenedOverSpotlight = MSBDSpotlightStillFromOpen(spotNow, gOverlayOpenedOverSpotlight);
        BOOL coverNow = gOverlay && DMCoverSheetShown();
        gOverlayOpenedOverCover = MSBDCoverSheetStillFromOpen(coverNow, gOverlayOpenedOverCover);
        if (gOverlay) {
            if (DMSwitcherVisible()) systemUI = @"the App Switcher";
            else if (ccActive) systemUI = @"Control Center";
            else if (DMLockUp(DMSBManager("SBLockScreenManager"))) systemUI = @"the Lock Screen";
            // (layering audit F11: the menu stayed open behind Spotlight and was still there after; but not the Spotlight the side question was opened
            //  from by a pick, on its way out -- OverlayClose.h, 1.8.1 item 11)
            else if (MSBDSpotlightCameUp(spotNow, gOverlayOpenedOverSpotlight)) systemUI = @"Spotlight";
            else if (MSBDCoverSheetCameUp(coverNow, gOverlayOpenedOverCover)) systemUI = @"Notification Center";   // (pulled down while unlocked: it is not "locked"; layering audit #10)
        }
        if (gOverlay || gKbLowered) DMMenuKeyboardOrder();
        if (!systemUI) systemUITicks = 0;
        // (a switcher transition event to mode 2, or Control Center's own window, is not a passing reading: one tick is enough there; the Today
        // panel sat over the App Switcher / Control Center for ~0.6 s with two, M1 26 Sep)
        // (Control Center at once only while it is really presented: during its dismissal it still reads "visible" for ~0.3 s, and a menu opened
        // then must not close on the next tick -- two ticks there, like any passing reading; layering audit #11)
        else if ((++systemUITicks >= 2 || (gEnvMode == 2 && DMSwitcherVisible())
                  || (ccActive && [DMBoolStr(DMControlCenterController(), @"isPresented") isEqualToString:@"Y"]))
                 && !DMTestFlag("/tmp/msb-overlay-keep")) {
            systemUITicks = 0;
            DMLog([NSString stringWithFormat:@"[overlay] %@ came up while a menu or question was open: closed", systemUI]);
            DMCloseOverlay();
        }
    }
}
// ==== end of 1.8.8.1's tick block ====

// ---- running it ----
static int fails = 0, checks = 0;
static void check(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static DMDownloadsPanel *Panel(void) { return [DMDownloadsPanel shared]; }
static void SetUp(World w) {
    W = w;
    T = [NSMutableArray array];
    gMSWOn = w.on; gMSWOpen = w.open; gMSWClosing = w.closing; gMSWSwitching = w.switching; gMSWTrack = w.track;
    gLayer = [UIWindow new]; gLayer.name = @"layer"; gMSWWindow = nil; gScreen = [UIScreen new];
    gMSWLiftPic = nil; if (w.liftPic) { gMSWLiftPic = [UIView new]; gMSWLiftPic.name = @"lift"; }
    gMSWLiftPicId = w.liftIdSame ? 3 : 2; gMSWLiftPicAt = gNow - (w.liftFresh ? 0.5 : 5.0); gMSWLiftPicMenu = w.liftMenu;
    gMSWTrackPicGen = 7; gMSWLiftPicGen = w.liftGenSame ? 7 : 6;
    gMSWOpenShot = nil; gMSWOpenShotId = 0; gAsyncDone = nil;
    gMSWTiles = [NSMutableArray array]; gMSWPortals = [NSMutableArray array]; gMSWBuiltSize = CGSizeMake(1180, 820);
    gOverlay = nil; if (w.menu) { gOverlay = [UIView new]; gOverlay.name = @"a menu"; }
    Panel().opened = w.panel;
    T = [NSMutableArray array];   // (the set-up's own events are not the code's)
}
// One opening: the trace, then the picture the view kept once the picture asked without waiting came in.
typedef struct { NSArray<NSString *> *trace; NSString *shot; BOOL opened, menuLeft, panelLeft; } Run;
static Run Open(World w, NSString *why, BOOL old) {
    SetUp(w);
    if (old) DMMSWOpenNow1881(why); else DMMSWOpenNow(why);
    if (gAsyncDone) { UIView *pic = [UIView new]; pic.name = @"without waiting"; void (^d)(UIView *, double) = gAsyncDone; gAsyncDone = nil; d(pic, 12.0); }
    Run r = { [T copy], gMSWOpenShot.name ?: @"none", gMSWOpen && !w.open, gOverlay != nil, Panel().opened };
    return r;
}
static NSUInteger At(NSArray<NSString *> *t, NSString *prefix) { NSUInteger i = 0; for (NSString *s in t) { if ([s hasPrefix:prefix]) return i; i++; } return NSNotFound; }
static NSArray *Without(NSArray<NSString *> *t, NSArray<NSString *> *prefixes) {
    NSMutableArray *o = [NSMutableArray array];
    for (NSString *s in t) { BOOL drop = NO; for (NSString *p in prefixes) if ([s hasPrefix:p]) drop = YES; if (!drop) [o addObject:s]; }
    return o;
}
static World Ready(void) { World w = {0}; w.on = YES; w.main = YES; w.asyncOn = YES; w.asyncAsks = YES; w.withoutView = YES; return w; }
static void DMTickClose(BOOL ccActive);
// (B71 review) One hold as on iPadOS 15: the gesture begins (the real DMMSWStartPicture asks for its picture), iPadOS's App Switcher is up during
// the hold (two of the real tick's closes, and the stack's own watch closes the panel), then the hold opens the view (the real DMMSWOpenNow).
// menuAtStart / panelAtStart: open as the gesture begins; tickFirst: closed before the picture comes in. The view's picture and the open's trace.
typedef struct { NSString *shot; NSArray<NSString *> *trace; BOOL marked, menuLeft; } Hold;
static Hold HoldRun(BOOL menuAtStart, BOOL panelAtStart, BOOL keep, BOOL tickFirst) {
    World w = Ready(); w.keep = keep; w.grace = YES; w.switcherUp = YES;
    SetUp(w);
    gGesturesOn = YES; gAsyncPicturesOK = YES; gMSWSlRoot = nil;
    if (menuAtStart) { gOverlay = [UIView new]; gOverlay.name = @"a menu"; }
    Panel().opened = panelAtStart;
    id gesture = [NSObject new];
    DMMSWStartPicture(gesture);
    void (^pic)(UIView *, double) = gAsyncDone; gAsyncDone = nil;
    void (^deliver)(void) = ^{ if (pic) { UIView *v = [UIView new]; v.name = @"the gesture's start"; pic(v, 9.0); } };
    if (!tickFirst) deliver();
    TW = (TickWorld){0}; TW.switcher = YES; gEnvMode = 1; gKbLowered = nil; gOverlayOpenedOverSpotlight = gOverlayOpenedOverCover = NO;
    DMTickClose(NO); DMTickClose(NO);
    Panel().opened = NO;   // (the stack's own watch: the App Switcher up for 0.2 s)
    if (tickFirst) deliver();
    BOOL marked = gMSWLiftPicMenu;
    T = [NSMutableArray array];
    DMMSWOpenNow(@"the App Switcher gesture");
    if (gAsyncDone) { UIView *v = [UIView new]; v.name = @"without waiting"; void (^d)(UIView *, double) = gAsyncDone; gAsyncDone = nil; d(v, 12.0); }
    Hold h = { gMSWOpenShot.name ?: @"none", [T copy], marked, gOverlay != nil };
    (void)gesture;
    return h;
}
static NSArray<NSString *> *kClose, *kPicture;

int main(void) {
    @autoreleasepool {
        kClose = @[@"log [overlay] the Mac Switcher came up", @"mark switcher-closes", @"DMCloseOverlay", @"stack panel closes", @"log [downloads]"];
        kPicture = @[@"picture: ", @"span begin", @"span end ", @"log [macswitcher] the view's picture", @"log [macswitcher] opened by the hold"];
        BOOL haveClose = dlsym(RTLD_DEFAULT, "MSBDDownloadsPanelSwitcherClose") != NULL;
        check(haveClose, @"the Dock part's close of its stack panel is exported by the name StatusBar.x asks for (MSBDDownloadsPanelSwitcherClose)");

        // ---- KT's case and each way of opening: a menu of ours open, the Mac Switcher opens ----
        NSArray *ways = @[@"Control-Up", @"Home button double press", @"the App Switcher gesture", @"the App Switcher gesture on the other display", @"trigger", @"Control-Up, asked while busy"];
        for (NSString *why in ways) {
            World w = Ready(); w.menu = YES; w.grace = [why hasPrefix:@"the App Switcher gesture"]; w.switcherUp = w.grace;
            Run r = Open(w, why, NO);
            check(r.opened && !r.menuLeft, [NSString stringWithFormat:@"%@ with a menu of ours open: the view opens and the menu is gone", why]);
            NSUInteger c = At(r.trace, @"DMCloseOverlay"), shown = At(r.trace, @"window shown"), focus = At(r.trace, @"keyboard focus to the view"), typing = At(r.trace, @"typing ends");
            check(c != NSNotFound && [r.trace[c] isEqualToString:@"DMCloseOverlay (a menu open)"] && [[r.trace filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'DMCloseOverlay'"]] count] == 1,
                  [NSString stringWithFormat:@"  ... closed once, with DMCloseOverlay (the close Control Center and the Cover Sheet use) (%@)", why]);
            check(c != NSNotFound && typing < c && c < shown && c < focus, [NSString stringWithFormat:@"  ... after the typing ends and before the view shows and takes the keys (%@)", why]);
            check(At(r.trace, @"log [overlay] the Mac Switcher came up while a menu or question was open: closed") != NSNotFound, [NSString stringWithFormat:@"  ... with the tick's line, naming the Mac Switcher (%@)", why]);
            check([r.shot isEqualToString:@"none"] && At(r.trace, @"picture: ") == NSNotFound, [NSString stringWithFormat:@"  ... and the view keeps no picture of the desktop (the menu fades in it) (%@)", why]);
            // the next open of a menu works: nothing of the closed one is left for it (gOverlay nil), and the view closes on Esc as before
            Run old = Open(w, why, YES);
            check(old.menuLeft, [NSString stringWithFormat:@"  ... (1.8.8.1: the menu stayed open over the view) (%@)", why]);
        }
        { World w = Ready(); w.panel = YES;
          Run r = Open(w, @"Control-Up", NO);
          check(r.opened && !r.panelLeft && At(r.trace, @"stack panel closes (animated)") < At(r.trace, @"window shown"), @"the Downloads stack's panel open: it closes (its own animated close) before the view shows");
          check([r.shot isEqualToString:@"none"], @"  ... and the view keeps no picture of the desktop (the panel fades in it)");
          check(At(r.trace, @"DMCloseOverlay") == NSNotFound, @"  ... no menu open: DMCloseOverlay is not called");
          check(Open(w, @"Control-Up", YES).panelLeft, @"  ... (1.8.8.1: the panel stayed open under the view and after it)"); }
        { World w = Ready(); w.panel = YES; w.menu = YES;
          Run r = Open(w, @"Home button double press", NO);
          check(r.opened && !r.panelLeft && !r.menuLeft, @"the stack's panel with an item's menu over it: both go"); }
        { World w = Ready();
          Run r = Open(w, @"Control-Up", NO);
          check(r.opened && [r.shot isEqualToString:@"without waiting"] && At(r.trace, @"DMCloseOverlay") == NSNotFound && At(r.trace, @"stack panel") == NSNotFound, @"nothing open: the view opens with its picture asked without waiting, as before, and nothing is closed"); }
        { World w = Ready(); w.grace = YES; w.switcherUp = YES; w.liftPic = YES; w.liftIdSame = YES; w.liftFresh = YES;
          check([Open(w, @"the App Switcher gesture", NO).shot isEqualToString:@"lift"], @"the hold with nothing open: the picture from the gesture's start, as before");
          w.menu = YES;
          Run r = Open(w, @"the App Switcher gesture", NO);
          check([r.shot isEqualToString:@"none"] && At(r.trace, @"log [macswitcher] opened by the hold: the desktop's picture none, a menu of ours was open") != NSNotFound,
                @"  ... with a menu open at the gesture's start: no picture (the menu is in the gesture's one too), and the log says why"); }
        { World w = Ready(); w.main = NO; w.menu = YES;
          Run r = Open(w, @"Control-Up", NO);
          check(r.opened && !r.menuLeft && [r.shot isEqualToString:@"none"] && At(r.trace, @"picture: ") == NSNotFound, @"another display's view (the waiting picture there): the menu goes, no picture either");
          w.menu = NO;
          check([Open(w, @"Control-Up", NO).shot isEqualToString:@"without"], @"  ... nothing open there: the screen without the view, as before"); }

        // ---- (B71 review) the hold's picture from the gesture's start, with a menu of ours on the screen at that start ----
#ifdef HAVE_SHOWN
        { SetUp(Ready());
          check(!DMMenusOfOursShown() && T.count == 0, @"something of ours on the screen (DMMenusOfOursShown): nothing open, NO, nothing done");
          gOverlay = [UIView new];
          check(DMMenusOfOursShown() && gOverlay != nil && T.count == 0, @"  ... a menu, panel or question open: YES, left open");
          gOverlay = nil; Panel().opened = YES;
          check(DMMenusOfOursShown() && Panel().opened && T.count == 0, @"  ... the Downloads stack's panel open: YES (the Dock part's export), left open");
          W.keep = YES; gOverlay = [UIView new];
          check(!DMMenusOfOursShown() && gOverlay != nil && Panel().opened, @"  ... debug /tmp/msb-overlay-keep: NO, as the switchers' close keeps them (before)"); }
#else
        check(NO, @"something of ours on the screen: DMMenusOfOursShown is not in this tree (a tree before the B71 review)");
#endif
        { BOOL (*shownF)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "MSBDDownloadsPanelShown");
          check(shownF != NULL, @"the Dock part tells whether its stack panel is on the screen, by the name StatusBar.x asks for (MSBDDownloadsPanelShown)");
          if (shownF) { T = [NSMutableArray array]; Panel().opened = YES; BOOL a = shownF(); Panel().opened = NO; BOOL b = shownF();
                        check(a && !b && T.count == 0, @"  ... YES while it is open, NO when not; nothing changes"); } }
        for (int tickFirst = 0; tickFirst < 2; tickFirst++) {
            NSString *when = tickFirst ? @"closed before the picture came in" : @"closed after the picture came in";
            Hold h = HoldRun(YES, NO, NO, tickFirst);
            check(h.marked && !h.menuLeft && [h.shot isEqualToString:@"none"] && At(h.trace, @"picture: ") == NSNotFound
                  && At(h.trace, @"log [macswitcher] opened by the hold: the desktop's picture none, a menu of ours was open at its start") != NSNotFound,
                  [NSString stringWithFormat:@"the hold, a menu of ours open as the gesture began and closed by the tick for iPadOS's App Switcher during the hold (%@): no picture (the menu is in the gesture's), the log says why", when]);
            h = HoldRun(NO, YES, NO, tickFirst);
            check(h.marked && [h.shot isEqualToString:@"none"] && At(h.trace, @"picture: ") == NSNotFound, [NSString stringWithFormat:@"  ... the stack's panel open then, closed by its own watch (%@): no picture either", when]);
        }
        { Hold h = HoldRun(NO, NO, NO, NO);
          check(!h.marked && [h.shot isEqualToString:@"the gesture's start"] && At(h.trace, @"log [macswitcher] opened by the hold: the desktop's picture from the gesture's start") != NSNotFound,
                @"  ... nothing open as the gesture began: the picture from the gesture's start, as before");
          h = HoldRun(YES, NO, YES, NO);
          check(!h.marked && h.menuLeft && [h.shot isEqualToString:@"the gesture's start"], @"  ... debug /tmp/msb-overlay-keep: the menu kept and the gesture's picture used, as before"); }
        { World w = Ready(); w.liftPic = YES; w.liftIdSame = YES; w.liftFresh = YES; w.liftGenSame = YES; w.liftMenu = YES;
          check([Open(w, @"Control-Up", NO).shot isEqualToString:@"without waiting"], @"  ... a keyboard opening after such a gesture: the screen now, as before (the gesture's picture is the hold's only)"); }

        // ---- every refusal opens nothing and leaves the menu and the panel ----
        NSArray *rnames = @[@"the Mac Switcher switched off", @"Guided Access running", @"iPadOS's App Switcher up", @"the Lock Screen or the Cover Sheet up", @"a desktop sliding in",
                            @"a gesture's slide following the fingers", @"no layer window", @"the view already open (the toggle closes it)", @"the view closing"];
        for (NSUInteger i = 0; i < rnames.count; i++) {
            World w = Ready(); w.menu = YES; w.panel = YES;
            switch (i) { case 0: w.on = NO; break; case 1: w.gaRefuses = YES; break; case 2: w.switcherUp = YES; break; case 3: w.cover = YES; break; case 4: w.switching = YES; break;
                         case 5: w.track = 2; break; case 6: w.noLayer = YES; break; case 7: w.open = YES; break; case 8: w.open = YES; w.closing = YES; break; }
            Run r = Open(w, @"Control-Up", NO), old = Open(w, @"Control-Up", YES);
            check(!r.opened && r.menuLeft && r.panelLeft && [r.trace isEqualToArray:old.trace], [NSString stringWithFormat:@"%@: nothing opens, the menu and the panel stay, the same calls as 1.8.8.1", rnames[i]]);
        }
        { World w = Ready(); w.menu = YES; w.panel = YES; w.keep = YES;
          Run r = Open(w, @"Control-Up", NO), old = Open(w, @"Control-Up", YES);
          check(r.opened && r.menuLeft && r.panelLeft && [r.trace isEqualToArray:old.trace], @"debug /tmp/msb-overlay-keep (tests keep menus over system UI): kept over the Mac Switcher too, as 1.8.8.1"); }

        // ---- the sweep: every state of the open's inputs, against 1.8.8.1's own DMMSWOpenNow ----
        // nothing open: the very same calls; something open and the view opens: 1.8.8.1's calls but the picture's, with the close before the view;
        // refused: the same calls.
        int states = 0, sameIdle = 0, idle = 0, sameRefused = 0, refused = 0, closedOk = 0, opened = 0, dropped = 0, droppedOk = 0;
        NSString *firstBad = nil;
        // (A: the 9 refusal inputs and the track's 3 values, all 1536, at 4 picture settings; B: the 10 picture inputs, all 1024, with the hold's 2
        //  inputs both ways and nothing refusing; each with the debug keep both ways, each of the 4 open things, and the gesture's start picture
        //  marked or not (B71 review: a menu of ours was on the screen at the gesture's start): marked, no picture where 1.8.8.1 took that one)
        for (int part = 0; part < 2; part++) {
            unsigned n = part == 0 ? 1536u * 4u : 1024u * 4u;
            for (unsigned i = 0; i < n; i++) {
                World w = Ready();
                if (part == 0) {
                    unsigned r = i % 1536u, pic = i / 1536u;
                    w.on = r & 1; w.open = (r >> 1) & 1; w.closing = (r >> 2) & 1; w.gaRefuses = (r >> 3) & 1; w.switcherUp = (r >> 4) & 1;
                    w.grace = (r >> 5) & 1; w.cover = (r >> 6) & 1; w.switching = (r >> 7) & 1; w.noLayer = (r >> 8) & 1; w.track = (int)((r >> 9) % 3u);
                    w.stripOut = pic == 1; w.asyncOn = pic != 2; w.liftPic = w.liftIdSame = w.liftFresh = pic == 3;
                } else {
                    unsigned q = i % 1024u, hold = i / 1024u;
                    w.stripOut = q & 1; w.liftAny = (q >> 1) & 1; w.liftPic = (q >> 2) & 1; w.liftIdSame = (q >> 3) & 1; w.liftFresh = (q >> 4) & 1;
                    w.liftGenSame = (q >> 5) & 1; w.asyncOn = (q >> 6) & 1; w.main = (q >> 7) & 1; w.asyncAsks = (q >> 8) & 1; w.withoutView = (q >> 9) & 1;
                    w.grace = hold & 1; w.switcherUp = (hold >> 1) & 1;
                }
                for (int k = 0; k < 16; k++) {
                    w.menu = k & 1; w.panel = (k >> 1) & 1; w.keep = (k >> 2) & 1; w.liftMenu = (k >> 3) & 1;
                    BOOL open = w.menu || w.panel;
                    states++;
                    Run r = Open(w, @"Control-Up", NO), old = Open(w, @"Control-Up", YES);
                    BOOL ok;
                    if ((!open || w.keep) && w.liftMenu && [old.shot isEqualToString:@"lift"]) {
                        dropped++;
                        ok = r.opened == old.opened && [r.shot isEqualToString:@"none"] && At(r.trace, @"picture: ") == NSNotFound && [Without(r.trace, kPicture) isEqualToArray:Without(old.trace, kPicture)]
                             && r.menuLeft == w.menu && r.panelLeft == w.panel;
                        if (ok) droppedOk++;
                    }
                    else if (!open || w.keep) { idle++; ok = [r.trace isEqualToArray:old.trace] && [r.shot isEqualToString:old.shot] && r.opened == old.opened && r.menuLeft == w.menu && r.panelLeft == w.panel; if (ok) sameIdle++; }
                    else if (!old.opened) { refused++; ok = [r.trace isEqualToArray:old.trace] && !r.opened && r.menuLeft == w.menu && r.panelLeft == w.panel; if (ok) sameRefused++; }
                    else {
                        opened++;
                        NSUInteger shown = At(r.trace, @"window shown"), focus = At(r.trace, @"keyboard focus to the view");
                        NSUInteger c1 = w.menu ? At(r.trace, @"DMCloseOverlay (a menu open)") : 0, c2 = w.panel ? At(r.trace, @"stack panel closes (animated)") : 0;
                        ok = r.opened && !r.menuLeft && !r.panelLeft && [r.shot isEqualToString:@"none"] && c1 < shown && c2 < shown && c1 < focus && c2 < focus
                             && [Without(Without(r.trace, kClose), kPicture) isEqualToArray:Without(old.trace, kPicture)];
                        if (ok) closedOk++;
                    }
                    if (!ok && !firstBad) firstBad = [NSString stringWithFormat:@"part %d state %u, menu %d panel %d keep %d marked %d:\n    fix  %@ (%@)\n    1881 %@ (%@)", part, i, w.menu, w.panel, w.keep, w.liftMenu, [r.trace componentsJoinedByString:@" | "], r.shot, [old.trace componentsJoinedByString:@" | "], old.shot];
                }
            }
        }
        check(idle > 0 && sameIdle == idle, [NSString stringWithFormat:@"the sweep, nothing open (or the debug keep): the same calls and picture as 1.8.8.1 in %d of %d states", sameIdle, idle]);
        check(dropped > 0 && droppedOk == dropped, [NSString stringWithFormat:@"the sweep, nothing open now but the gesture's start picture marked where 1.8.8.1 took it: no picture, otherwise 1.8.8.1's calls, in %d of %d states", droppedOk, dropped]);
        check(refused > 0 && sameRefused == refused, [NSString stringWithFormat:@"the sweep, something open and the open refused: the same calls, both left, in %d of %d states", sameRefused, refused]);
        check(opened > 0 && closedOk == opened, [NSString stringWithFormat:@"the sweep, something open and the view opening: closed before the view, no picture, otherwise 1.8.8.1's calls, in %d of %d states", closedOk, opened]);
        if (firstBad) printf("      first state that differs: %s\n", firstBad.UTF8String);
        printf("      (%d states)\n", states);

        // ---- the Dock part's close by itself ----
        if (haveClose) {
            BOOL (*close)(const char *) = (BOOL (*)(const char *))dlsym(RTLD_DEFAULT, "MSBDDownloadsPanelSwitcherClose");
            T = [NSMutableArray array]; Panel().opened = NO;
            check(!close("the Mac Switcher") && T.count == 0, @"the stack panel's close with the panel closed: NO, nothing done");
            T = [NSMutableArray array]; Panel().opened = YES;
            BOOL yes = close("the Mac Switcher");
            check(yes && !Panel().opened && [T containsObject:@"stack panel closes (animated)"] && [T containsObject:@"log [downloads] closes: the Mac Switcher came up"], @"  ... open: YES, the panel's own animated close, its line names the switcher");
            T = [NSMutableArray array]; Panel().opened = YES;
            check(close(NULL) && [T containsObject:@"log [downloads] closes: a switcher came up"], @"  ... with no name: a switcher");
        }

        // ---- the tick: iPadOS's App Switcher closes with the same close, every other system UI as before ----
        // each state: a tick with nothing (the count back to 0), then two ticks with the state; the fix's calls against 1.8.8.1's
        int tstates = 0, tsame = 0, tswitch = 0, tswitchOk = 0;
        NSString *tbad = nil;
        for (unsigned bits = 0; bits < (1u << 11); bits++) {
            TickWorld tw = { bits & 1, (bits >> 1) & 1, (bits >> 2) & 1, (bits >> 3) & 1, (bits >> 4) & 1, (bits >> 5) & 1, (bits >> 6) & 1 };
            BOOL cc = (bits >> 7) & 1, menu = (bits >> 8) & 1, panel = (bits >> 9) & 1, keep = (bits >> 10) & 1;
            NSArray *traces[2]; BOOL menuLeft[2], panelLeft[2];
            for (int k = 0; k < 2; k++) {
                W = (World){0}; W.keep = keep;
                TW = (TickWorld){0}; gOverlay = nil; gEnvMode = 0; gKbLowered = nil; gOverlayOpenedOverSpotlight = gOverlayOpenedOverCover = NO;
                T = [NSMutableArray array];
                if (k) DMTickClose1881(NO); else DMTickClose(NO);   // (no system UI: the count goes back to 0)
                TW = tw; gEnvMode = tw.env2 ? 2 : 1; gKbLowered = tw.kb ? [UIWindow new] : nil;
                if (menu) { gOverlay = [UIView new]; gOverlay.name = @"a menu"; }
                Panel().opened = panel;
                T = [NSMutableArray array];
                for (int t = 0; t < 2; t++) { if (k) DMTickClose1881(cc); else DMTickClose(cc); }
                traces[k] = [T copy]; menuLeft[k] = gOverlay != nil; panelLeft[k] = Panel().opened;
            }
            tstates++;
            BOOL switcherClose = menu && tw.switcher && !keep;
            if (switcherClose) {
                tswitch++;
                BOOL ok = !menuLeft[0] && !panelLeft[0] && [Without(traces[0], @[@"stack panel closes", @"log [downloads]", @"mark switcher-closes"]) isEqualToArray:traces[1]] && menuLeft[1] == NO;
                if (ok) tswitchOk++; else if (!tbad) tbad = [NSString stringWithFormat:@"tick state %u:\n    fix  %@\n    1881 %@", bits, [traces[0] componentsJoinedByString:@" | "], [traces[1] componentsJoinedByString:@" | "]];
            } else {
                BOOL ok = [traces[0] isEqualToArray:traces[1]] && menuLeft[0] == menuLeft[1] && panelLeft[0] == panel;
                if (ok) tsame++; else if (!tbad) tbad = [NSString stringWithFormat:@"tick state %u:\n    fix  %@\n    1881 %@", bits, [traces[0] componentsJoinedByString:@" | "], [traces[1] componentsJoinedByString:@" | "]];
            }
        }
        check(tswitch > 0 && tswitchOk == tswitch, [NSString stringWithFormat:@"the tick, a menu open and iPadOS's App Switcher up: the menu closes as in 1.8.8.1 (the same calls and line) and the stack's panel with it, in %d of %d states", tswitchOk, tswitch]);
        check(tsame == tstates - tswitch, [NSString stringWithFormat:@"the tick, every other state (Control Center, the Lock Screen, Spotlight, Notification Center, nothing, the debug keep): the same calls as 1.8.8.1, the panel left to its own watch, in %d of %d states", tsame, tstates - tswitch]);
        if (tbad) printf("      first state that differs: %s\n", tbad.UTF8String);

        // ---- iPadOS's App Switcher on its way (1.8.8.3): its transition event (environment mode 2) closes every menu of ours at once, before it
        // shows -- also one iPadOS dismisses again 0.2 s later, before any tick has seen it up (a sticky note's menu, Show App Switcher, 18.5) ----
#if HAVE_ENV
        {
            struct { BOOL on, stock, open, menu, panel, keep; long long mode; BOOL want; const char *what; } cs[] = {
                { NO,  NO,  NO,  YES, NO,  NO,  2, YES, "the Mac Switcher off, a menu open, a transition to the App Switcher that is gone again before a tick: the menu closes" },
                { NO,  NO,  NO,  YES, YES, NO,  2, YES, "  ... with the Downloads stack's panel open too: both close" },
                { NO,  NO,  NO,  NO,  YES, NO,  2, YES, "  ... the stack's panel alone: it closes" },
                { YES, YES, NO,  YES, NO,  NO,  2, YES, "the Mac Switcher on, iPadOS's App Switcher asked for from the Apple menu (Show App Switcher): the menu closes" },
                { YES, NO,  NO,  YES, NO,  NO,  2, NO,  "the Mac Switcher on and nothing asked: left to the Mac Switcher's own open (its own line, before its view)" },
                { NO,  NO,  YES, YES, NO,  NO,  2, NO,  "the Mac Switcher's view open: nothing here" },
                { NO,  NO,  NO,  YES, NO,  NO,  1, NO,  "a transition Home: nothing" },
                { NO,  NO,  NO,  YES, NO,  NO,  3, NO,  "a transition to an app: nothing" },
                { NO,  NO,  NO,  NO,  NO,  NO,  2, NO,  "nothing open: nothing done, no line" },
                { NO,  NO,  NO,  YES, NO,  YES, 2, NO,  "the debug keep: kept" },
            };
            for (size_t i = 0; i < sizeof cs / sizeof cs[0]; i++) {
                World w = Ready(); w.on = cs[i].on; w.open = cs[i].open; w.menu = cs[i].menu; w.panel = cs[i].panel; w.keep = cs[i].keep;
                SetUp(w); W.switcherUp = NO; gStockOnce = cs[i].stock;   // (the App Switcher gone again before anything reads it)
                DMSwitcherEnvCloseMenus(cs[i].mode);
                BOOL inside = T.count > 0;   // (nothing inside SpringBoard's own call: the main queue's next turn)
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                BOOL menuGone = gOverlay == nil, panelGone = !Panel().opened;
                BOOL line = [T containsObject:@"log [overlay] the App Switcher came up while a menu or question was open: closed"], dline = [T containsObject:@"log [downloads] closes: the App Switcher came up"];
                BOOL ok = !inside && (cs[i].want ? menuGone && panelGone && line == cs[i].menu && dline == cs[i].panel && [T containsObject:@"mark app-switcher-closes-menus"]
                                                 : menuGone == !cs[i].menu && panelGone == !cs[i].panel && !line && !dline && ![T containsObject:@"mark app-switcher-closes-menus"]);
                check(ok, [NSString stringWithFormat:@"App Switcher on its way: %s (%@)", cs[i].what, [T componentsJoinedByString:@" | "]]);
            }
            gStockOnce = NO; gMSWOn = NO; gMSWOpen = NO; gOverlay = nil; Panel().opened = NO;
        }
#else
        check(NO, @"App Switcher on its way: no close at its transition event (DMSwitcherEnvCloseMenus is not in this tree): a menu stays when iPadOS's App Switcher is gone again before a tick");
#endif

        printf("%d checks, %d failed\n", checks, fails);
    }
    return fails ? 1 : 0;
}
