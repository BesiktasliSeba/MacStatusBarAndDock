// test-wifirecheck.m -- the menu bar after a respring onto the Lock Screen (GitHub issue #14, iPad Air 5 16.3.1, 1.8.7.5: "There will be two wifi
// markers in the status bar after Respring, and one will automatically disappear after a while"; "Whether unlocking immediately or waiting for more
// than 1 minute to unlock, two Wi Fi icons will be displayed. Sometimes the status bar may not load properly").
// iOS's items in a bar (here its Wi-Fi item) say whether they show only when asked: at iOS's data updates (the items whose data changed) and when we
// ask again (DMStockVPNRecheck, the whole data). For a bar of ours (kLogoKey) or one being set up (kHoldKey) the Wi-Fi item answers no
// (DMHideStockWiFi): our Wi-Fi icon replaces it. The Lock Screen's copy after a respring is laid out the Lock Screen's way (no clock there: not ours,
// iOS's Wi-Fi item shows); at the unlock its time label comes back with no layout pass of the copy (15/16 and 17+ alike). Before 1.8.7.7, on 15/16
// only DMEnsureLogo's look (once a second for ~42 s of awake time, with no hold) gave it the clock layout: ours with no hold, and nothing asked the
// Wi-Fi item again -- two Wi-Fi icons until iOS's next Wi-Fi update; after its last look nothing at all -- iPadOS's stock bar. Now the ask follows
// every change of ours-ness (DMBarItemsAskAgain: at a hold's release and when a copy with no hold becomes ours; owed when it found no bar or no data)
// and 15/16 lays the copy out, held, when its time label comes back (DMClockBackNow) and at the unlock's cues (DMRelayoutUnattachedBars), as 17+ does.
// An update that itself makes the copy ours (it places the time label, laid out at once) drops that layout's ask when it is our own ask: the update
// asks once more (the regressions review's race, row 19). The held copy's ask (1.8.7.8, below) is itself such an update: never made inside one
// (StockVPNItem's hook counts them, run here as it is); every row checks that no update of the bar starts inside another.
// A Notification Center pull let go (1.8.7.6, the iPad 2's f03 pass, rows 20-24): the Cover Sheet takes the time label of a copy that is ours, the pull's
// going back lays it out without its clock (closed up, unlocked), and the label comes back with no layout pass of the copy, inside the bar's own
// constraint pass or outside it. 17+ laid it out again (DMClosedUpClockBack); 15/16 left it closed up, the icons over the time, until the next minute.
// The unlock after a respring as the iPad 2 (16.7.7) does it (1.8.7.8, rows 25-27; 1.8.7.6~f04 r1 / r2a / r2c): the time label comes back inside the
// bar's own constraint pass, in Core Animation's commit, after the copy's layout ran there; the copy is laid out ours by the pre-commit layout
// (DMBarLayoutAgainBeforeDraw, real, with Core Animation's commit handlers stood in) and released there: iOS's items must have answered as ours
// before that layout, or iOS's Wi-Fi item is drawn beside ours in that frame (before 1.8.7.8: their ask came after the layout pass).
// The bar places the rest of its trailing region only at its own layout (1.8.7.9 W2; 1.8.7.8~h01 D1, iPad 2 and M1): an answer that takes iOS's Wi-Fi
// item out removes its view at once, but the airplane icon stays at its old place, and our icons with it (18 pt left), until the region is laid out.
// UIKit's order, as the review of W2 found it (17 decompile; a Mac Catalyst probe of the real UIKit): an update with no animation (the held ask) only
// asks for the bar's constraint pass, and marks nothing for layout; -layoutIfNeeded on a view with nothing marked at or below it runs nothing; one
// that lays something out runs that pass first (17+: SystemStatusUI's -_updateRegionItems, our hook as it is), which gives the region its new places;
// the region's items take them in the region's own layout, after the copy's (a view is laid out before its subviews). Every row with a held ask: the
// copy's first layout after that ask (outside the ask: one inside it is laid out again right after, in the same turn) already has the final icons
// start, and the region's placement after it is made with no animation.
// The real code is cut out of statusbar/StatusBar.x by test-wifirecheck.sh (see there). Stand-ins: UIKit's views and their layout (setNeedsLayout:
// laid out at the turn's commit), the bar and its Wi-Fi item, the display link, SpringBoard's lock manager and Cover Sheet, the time label, and the main
// queue on the test's own clock -- the awake clock (dispatch_after and CACurrentMediaTime stop while the iPad sleeps; the screen's frames too). A turn
// runs the blocks due at its start, the display link and the 0.2 s library timer (DMWatchLock), then the commit's layout pass; a frame's commit is what
// is drawn. One row per process (the real code keeps its state in statics).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
#include <sys/wait.h>
#include "BarUnlock.h"

// ---- the test's clock and main queue ----
static double gNow = 0;          // (awake time: the iPad's clock for timers)
static double gWall = 0;         // (wall time: the row's events)
static int gCaller;              // (whose layout: 0 the watcher, 1 the main queue's work, 2 the copy's own pass, 3 a direct layout)
static NSMutableArray *gQueue;   // @[@(at), block]
static void TAfter(double delay, dispatch_block_t b) { [gQueue addObject:@[@(gNow + delay), [b copy]]]; }
#define dispatch_time(base, delta) ((dispatch_time_t)(delta))
#define dispatch_after(when, queue, blk) TAfter((double)(when) / 1e9, (blk))
#define dispatch_async(queue, blk) TAfter(0.0, (blk))
#define DM_FEATURE_MARK(name) ((void)0)
#define CACurrentMediaTime() (gNow)

// ---- UIKit stand-ins ----
@class UIWindow;
@interface UIView : NSObject
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL hidden, needsLayout;
@property (nonatomic) CGRect bounds;
@property (nonatomic, strong) NSMutableArray<UIView *> *subs;
@property (nonatomic, weak) UIView *superview;
- (UIWindow *)window;
- (NSArray<UIView *> *)subviews;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (CGRect)convertRect:(CGRect)r toView:(UIView *)v;
+ (void)performWithoutAnimation:(void (^)(void))b;
@end
@interface UIWindow : UIView
@end
@interface UIStatusBarWindow : UIWindow   // (15/16: SpringBoard's status bar window)
@end
@implementation UIStatusBarWindow
@end
@interface SBStatusBarWindow : UIWindow   // (17+: SystemStatusUI's family, DMSBName("UIStatusBarWindow"))
@end
@implementation SBStatusBarWindow
@end
@interface _UIStatusBarForegroundView : UIView   // (a status bar copy)
- (void)dm_layoutLogo;
- (void)dm_layoutLogoBody;
@end
static NSString *NSStringFromCGRect(CGRect r) { return NSStringFromRect(NSRectFromCGRect(r)); }
#define CADisplayLink TDisplayLink   // (macOS has a CADisplayLink of its own: the stand-in under another name, the real code's word for it kept)
@interface CADisplayLink : NSObject
@property (nonatomic) CFTimeInterval timestamp;
@property (nonatomic, strong) id target;
@property (nonatomic) SEL sel;
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)sel;
- (void)addToRunLoop:(NSRunLoop *)rl forMode:(NSRunLoopMode)mode;
- (void)invalidate;
@end
@implementation CADisplayLink
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)sel { CADisplayLink *l = [self new]; l.target = target; l.sel = sel; return l; }
- (void)addToRunLoop:(NSRunLoop *)rl forMode:(NSRunLoopMode)mode { (void)rl; (void)mode; }
- (void)invalidate { _target = nil; }
@end
@interface TLockManager : NSObject   // (SBLockScreenManager: -isUILocked, the unlock request DMSkipLockAfterRespring checks for)
- (BOOL)isUILocked;
- (void)_unlockWithRequest:(id)r cancelPendingRequests:(BOOL)c completion:(id)b;
@end
@interface SBLockScreenUnlockRequest : NSObject
@end
@implementation SBLockScreenUnlockRequest
@end

// ---- the row's world ----
static BOOL gSTUI;               // (17/18: SystemStatusUI's bar)
static NSMutableArray<UIWindow *> *gWindows;
static UIWindow *gBarWindow;
static _UIStatusBarForegroundView *gFG;
static UIView *gLeading, *gTimeLabel, *gTrailing, *gHolder;
static TLockManager *gLockMgr;
static BOOL gUILocked, gCover;   // (-isUILocked; the Cover Sheet over the bar, -isVisibleAndNotDisappearing)
static BOOL gClock;              // (the leading region has its time label)
static BOOL gNoData;             // (the bar's -currentAggregatedData is nil)
static BOOL gSkip;               // (Skip Lock Screen After Respring)
static int gPass;                // (DMNoPasscodeSet: 0 a passcode, 1 none, 2 none but unsure in SpringBoard's first second)
static BOOL gUnlockAsked;        // (DMTryUnlock was called: the unlock follows)
static NSMutableArray<NSString *> *gLog;
static int gLayoutsBy[4], gOursBy = -1, gOursHeld = -1;
static int gLayoutsInPass;       // (layouts of ours run inside the bar's own constraint pass: the NC-pull crash's way, 1.8.7.6)

// what StatusBar.x keeps, as the cut code reads it
static NSHashTable *gCopies = nil, *gAllBarCopies = nil;
static const void *kLogoKey = &kLogoKey;
static const void *kHoldKey = &kHoldKey;
static const void *kHoldWantAlphaKey = &kHoldWantAlphaKey;
static const void *kHoldGaveUpKey = &kHoldGaveUpKey;
static const void *kNoClockLayoutKey = &kNoClockLayoutKey;
static const void *kBarLaidOutLockedKey = &kBarLaidOutLockedKey;
static const void *kBarLookLockedKey = &kBarLookLockedKey;
static const void *kBarClosedUpKey = &kBarClosedUpKey;
static const void *kAttachNextTurnKey = &kAttachNextTurnKey;
static BOOL gDMHoldOwnAlpha = NO;
static int gDMBarLayoutDepth = 0, gDMBarUpdateDepth = 0;
static int gDMBarConstraintDepth = 0;   // (1.8.7.6: a bar inside its own -updateConstraints -- the pull rows' label inside it; tools/test-barbackground.sh plays the pass)
static __unsafe_unretained UIView *gDMBarLayingOut = nil;
static BOOL gWiFiMenuOn = YES, gVPNActive = NO, gSSHActive = NO, gMuteIconShown = NO;
static unsigned gSBItemHooks;
static BOOL gDMScreenOff = NO, gDMOffSinceBack = NO;
static int gDMTouchWatchArm = 5;
static NSString *gDMTouchWatchWhy = @"SpringBoard start";
typedef struct { const char *name; double sum, max; int n; } DMPerfSlot;

static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }
static void DMSBDiagStep(NSString *s) { (void)s; }
static BOOL DMSBUseSTUI(void) { return gSTUI; }
static NSString *DMSBName(const char *uikitName) { return gSTUI && !strcmp(uikitName, "UIStatusBarWindow") ? @"SBStatusBarWindow" : @(uikitName); }   // (the one name these paths read)
static Class DMSBClass(const char *uikitName) { return objc_getClass(uikitName); }
static NSArray<UIWindow *> *DMAllWindows(void) { return gWindows; }
static BOOL DMBarCopyIsCCDuplicate(UIView *fg) { (void)fg; return NO; }
static BOOL DMSMEngine(void) { return NO; }
static BOOL DMSMInFullScreenCard(UIView *v) { (void)v; return NO; }
static void DMSMMainBarChanged(UIView *fg) { (void)fg; }
static BOOL DMCopyHasStockText(UIView *fg) { (void)fg; return YES; }   // (iOS has filled the copy: its battery, its time or date)
static void DMBattInsideLeftToIOS(UIView *fg) { (void)fg; }
static UIView *DMLeadingContainer(UIView *fg) { return fg == gFG ? gLeading : nil; }
static UIView *DMFirstStringView(UIView *container) { return container && gClock ? gTimeLabel : nil; }
static UIView *DMTrailingContainer(UIView *fg) { return fg == gFG ? gTrailing : nil; }
static void DMHideAppBarItemsOf(UIView *fg) { (void)fg; }
static BOOL DMLayoutWithoutClock(UIView *fg) { return DMTrailingContainer(fg) != nil; }   // (closes the status icons up: whenever there is a status icons region)
static BOOL DMBattInsideBarOurs(UIView *fg) { (void)fg; return NO; }
static void DMBattInsideLockLayout(UIView *fg, BOOL wasOurs) { (void)fg; (void)wasOurs; }
static BOOL DMWiFiOSOK(void) { return YES; }
static id DMSBManager(const char *cls) { return !strcmp(cls, "SBLockScreenManager") ? gLockMgr : nil; }   // (no backlight controller: the screen is on)
static void DMSettleLockScreenClock(void) {}
static BOOL DMCoverSheetCoversBar(void) { return gCover; }
static BOOL DMCoverSheetShown(void) { return gCover; }
static void DMBackAfterScreenOff(NSString *why, double zetsuDelay) { (void)why; (void)zetsuDelay; }
static BOOL DMSkipLockWanted(void) { return gSkip; }
static BOOL DMNoPasscodeSet(void) { return gPass == 1 || (gPass == 2 && gNow >= 1.0); }
static BOOL DMTryUnlock(id mgr, int mode, int n) { (void)mgr; (void)mode; (void)n; gUnlockAsked = YES; return YES; }
static void DMSnapBegin(void) {}
static void DMSnapEnd(void) {}
static BOOL DMPerfOn(void) { return NO; }
static DMPerfSlot *DMPerfSlotFor(const char *name) { (void)name; return NULL; }
#define CATransaction TCATransaction   // (macOS has a CATransaction of its own: the stand-in under another name, the real code's word kept)
@interface CATransaction : NSObject   // (Core Animation's commit handlers: the pre-commit phase runs after the commit's layout pass, before the frame)
+ (void)addCommitHandler:(void (^)(void))block forPhase:(unsigned long)phase;
@end
static NSMutableArray *gPreCommit;   // (this commit's pre-commit handlers)
static BOOL gInPreCommit; static int gLateHandlers;   // (a handler added while that phase runs: not taken -- counted)
@implementation CATransaction
+ (void)addCommitHandler:(void (^)(void))block forPhase:(unsigned long)phase { if (phase != 1) return; if (gInPreCommit) { gLateHandlers++; return; } if (!gPreCommit) gPreCommit = [NSMutableArray array]; [gPreCommit addObject:[block copy]]; }
@end
static BOOL DMBarItemsAskBeforeOurs(UIView *fg);   // (1.8.7.8: before the layout that makes a held copy ours -- a stand-in doing nothing in the code before)
static BOOL DMLockUp(id mgr);
static BOOL DMBarLockedNow(void) { return MSBDBarLockedLook(DMLockUp(gLockMgr), gCover); }   // (15/16's: BarUnlock.h's rule on the manager and the Cover Sheet)

// ---- iOS's bar and its Wi-Fi item ----
@interface TStatusBarItem : NSObject   // (the item's superclass: answers -canEnableDisplayItem:fromData: itself -- yes, the data has Wi-Fi)
- (BOOL)canEnableDisplayItem:(id)displayItem fromData:(id)data;
@end
@implementation TStatusBarItem
- (BOOL)canEnableDisplayItem:(id)displayItem fromData:(id)data { (void)displayItem; (void)data; return YES; }
@end
@interface _UIStatusBarWifiItem : TStatusBarItem   // (iOS's Wi-Fi item: no answer of its own, DMStockWiFiInit adds DMWiFiItemCanEnable)
- (id)statusBar;
@end
@interface _UIStatusBar : UIView   // (the bar: the copy's ancestor)
- (id)foregroundView;
- (id)currentAggregatedData;
- (void)_updateWithAggregatedData:(id)data;
- (void)_updateRegionItems;
@end
static _UIStatusBar *gBar;
static _UIStatusBarWifiItem *gItem;
static BOOL gItemShown;          // (iOS's Wi-Fi item shows: its answer when last asked)
static int gAsks, gAsksAsOurs;   // (our asks that reached the bar; those while the copy was ours)
static int gNoAnimAsks;          // (1.8.7.8: asks made with no animation -- the held copy's, before the layout that makes it ours)
static BOOL gInNoAnim;           // (inside +performWithoutAnimation:)
static BOOL gConstraintsDue;     // (W2 review: the bar's constraint pass is due -- an update that changed its items asks only for that; nothing is marked)
static BOOL gRegionPlan;         // (... the trailing region as that pass last set it -- with iOS's Wi-Fi item)
static BOOL gRegionItem;         // (W2: the trailing region as its items last took their places -- in the region's own layout, after the copy's)
static int gHeldAsked;           // (W2: held asks that reached the bar: our whole-data update with no animation)
static double gFirstStartAfterAsk = -1;   // (W2: our icons start at the copy's first layout after the held ask, outside the ask)
static int gPlacedAfterAskNoAnim = -1;    // (W2: the region's first placement after the held ask: with no animation 1, animated 0, none -1)
static double gLastStart = -1;           // (W2 review: our icons start at the copy's last layout -- what a frame shows)
static int gOldPlaceFrames;              // (... frames drawn after the held ask, the copy ours and shown, our icons at the old place)
static double TIconsStart(void) { return gRegionItem ? 646.0 : 664.0; }   // (our icons follow the region: iPad 2 16.7.7's numbers, h01 D1)
static void TConstraintPass(void);
static void TRegionPart(id self);
static void DMAttachIfFilled(UIView *fg, const char *why);
@implementation _UIStatusBarWifiItem
- (id)statusBar { return gBar; }
@end

#include "wr-again.inc"    // (StatusBar.x DMBarLayoutAgainBeforeDraw, real)
#include "wr-decide.inc"   // (StatusBar.x DMBarLayingOut, DMBarDecideNextTurn: the copy's layout at the next turn, outside its bar's constraint pass)
#include "wr-base.inc"
static void DMHoldStatusBarCopy(UIView *fg);
static void DMReleaseStatusBarCopy(UIView *fg);
static void DMHoldSafetyCheck(UIView *fg, int checks);
static void DMStatusIconsUpdated(id bar);
static void DMRelayoutUnattachedBars(NSString *why);
static void DMClosedUpClockBack(UIView *fg);
static void DMClockBackLayout(UIView *fg);
#include "wr-item.inc"
#include "wr-hold.inc"

static BOOL gLabelInData;   // (row 19: the data has the time back, the bar has not placed the label yet)
static int gLabelInAsk = -1;   // (row 19: the update that placed it was our own ask (1) or iOS's (0))
static void TLabelBack(BOOL hook, BOOL iosPass);
static BOOL ours(void) { return objc_getAssociatedObject(gFG, kLogoKey) != nil; }
static int gUpdDepth, gNestedUpdates;   // (1.8.7.8 review of W, F1: data updates of the bar started inside another one -- never: UIKit's is not run inside itself)
static void TIOSUpdatePart(id self, NSDictionary *data) {   // (iOS's own part, %orig: the items whose data the update has are asked; ours passes the whole data)
    (void)self;
    if (gUpdDepth > 0) gNestedUpdates++;
    gUpdDepth++;
    if (data[@"wifi"]) gItemShown = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(gItem, @selector(canEnableDisplayItem:fromData:), nil, data);
    if (gItemShown != gRegionPlan) gConstraintsDue = YES;   // (W2: the item's view goes at once; the rest of the region: the bar's constraint pass, then its layout)
    if (data[@"whole"]) { gAsks++; if (ours()) gAsksAsOurs++; if (gInNoAnim) gHeldAsked++; }
    if (gLabelInData && data[@"time"]) {   // (row 19: this update places the label, after the items have answered)
        gLabelInData = NO; gLabelInAsk = data[@"whole"] != nil;
        TLabelBack(YES, NO);
    }
    gUpdDepth--;
}
@implementation _UIStatusBar
- (id)foregroundView { return gFG; }
- (id)currentAggregatedData { return gNoData ? nil : @{ @"wifi": @YES, @"time": @YES, @"whole": @YES }; }
- (void)_updateWithAggregatedData:(id)data {   // (our hook of it as it is, StockVPNItem: its %orig is iOS's part above)
#include "wr-update.inc"
}
- (void)_updateRegionItems {   // (17+: our hook of it as it is, SBAttach17Regions: its %orig is iOS's part, TRegionPart)
#include "wr-regions.inc"
}
@end
static void TRegionPart(id self) {   // (iOS's part of the bar's constraint pass: the trailing region's new places, as the items last answered)
    (void)self;
    gRegionPlan = gItemShown;
    if (gRegionPlan != gRegionItem) gTrailing.needsLayout = YES;   // (taken in the region's own layout)
}
static void TRegionLayout(void) {   // (the region's own layout, after the copy's: its items take their places)
    gTrailing.needsLayout = NO;
    if (gHeldAsked > 0 && gPlacedAfterAskNoAnim < 0 && gRegionItem != gRegionPlan) gPlacedAfterAskNoAnim = gInNoAnim;
    gRegionItem = gRegionPlan;
}
static void TConstraintPass(void) {   // (the bar's -updateConstraints, our BarForeground hook's count around it -- 17+: -_updateRegionItems, our hook)
    gConstraintsDue = NO;
    gDMBarConstraintDepth++;
    if (gSTUI) [gBar _updateRegionItems]; else TRegionPart(gBar);
    gDMBarConstraintDepth--;
}
static void TIOSUpdate(NSDictionary *d) { [gBar _updateWithAggregatedData:d]; }   // (iOS's own data update: the time each minute, ...)

#include "wr-lock.inc"
#include "wr-attach.inc"
#include "wr-watch.inc"

static void TIOSPart(id self) { (void)self; }   // (iOS's own part of the copy's layout pass: nothing of the items')
static void TLayoutSubviews(_UIStatusBarForegroundView *self) {   // (the -layoutSubviews hook, as it is)
    self.needsLayout = NO;
    int was = gCaller; gCaller = 2;
#include "wr-layoutsubviews.inc"
    gCaller = was;
}
static void TDidMoveToWindow(_UIStatusBarForegroundView *self) {   // (the -didMoveToWindow hook, as it is)
#include "wr-didmove.inc"
}
@implementation _UIStatusBarForegroundView
- (void)dm_layoutLogo {
#include "wr-wrapper.inc"
}
- (void)dm_layoutLogoBody {
    UIView *fg = self;
    gLayoutsBy[gCaller]++;
    if (gDMBarConstraintDepth > 0) gLayoutsInPass++;
    if (gHeldAsked > 0 && gFirstStartAfterAsk < 0 && !gInNoAnim) gFirstStartAfterAsk = TIconsStart();   // (W2: where this layout puts our icons)
    gLastStart = TIconsStart();
#include "wr-noclock.inc"
    // the clock layout: the logo, and our Wi-Fi icon with it (WiFiMenu.h), as it makes them; then its newlyOurs part as it is
    if (!objc_getAssociatedObject(fg, kLogoKey)) objc_setAssociatedObject(fg, kLogoKey, [UIView new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#include "wr-newly.inc"
    if (newlyOurs) { gOursBy = gCaller; gOursHeld = [objc_getAssociatedObject(fg, kHoldKey) boolValue]; }
    BOOL locked = DMBarLockedNow();   // (its marks at the end, as it sets them -- site check)
    objc_setAssociatedObject(fg, kBarLaidOutLockedKey, @(locked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(fg, kBarLookLockedKey, @(locked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end
static BOOL TMarked(UIView *v) { if (v.needsLayout) return YES; for (UIView *s in v.subs) if (TMarked(s)) return YES; return NO; }
static void TLayoutTree(UIView *v) {   // (the marked views of a subtree, each before its subviews: the copy before its region)
    if (v.needsLayout) {
        if ([v isKindOfClass:[_UIStatusBarForegroundView class]]) TLayoutSubviews((_UIStatusBarForegroundView *)v);
        else if (v == gTrailing) TRegionLayout();
        else v.needsLayout = NO;   // (the bar's own -layoutSubviews, the rest: nothing the test reads)
    }
    for (UIView *s in [v.subs copy]) TLayoutTree(s);
}
@implementation UIView
- (instancetype)init { if ((self = [super init])) { _alpha = 1.0; _subs = [NSMutableArray array]; } return self; }
- (UIWindow *)window { UIView *v = self; while (v && ![v isKindOfClass:[UIWindow class]]) v = v.superview; return (UIWindow *)v; }
- (NSArray<UIView *> *)subviews { return [_subs copy]; }
- (void)setNeedsLayout { _needsLayout = YES; }
- (void)layoutIfNeeded {   // (UIKit, the review's probe: nothing marked at or below the receiver -- nothing, even with the bar's constraint pass due;
                           //  else that pass first, then the marked views -- the bar, the copy, then its region)
    if (!TMarked(self)) return;
    if (gConstraintsDue && self.window) TConstraintPass();
    TLayoutTree(self);
}
- (CGRect)convertRect:(CGRect)r toView:(UIView *)v { (void)v; return r; }
+ (void)performWithoutAnimation:(void (^)(void))b { gNoAnimAsks++; BOOL was = gInNoAnim; gInNoAnim = YES; b(); gInNoAnim = was; }   // (counted: the held ask's)
@end
@implementation UIWindow
- (UIWindow *)window { return self; }
@end
@implementation TLockManager
- (BOOL)isUILocked { return gUILocked; }
- (void)_unlockWithRequest:(id)r cancelPendingRequests:(BOOL)c completion:(id)b { (void)r; (void)c; (void)b; }
@end

// the ways the model lays the copy out directly: DMSMRefreshBars' (released when ours) and DMSMChrome's (nothing more) -- site check: both are there
static void TDirect(BOOL release) {
    int was = gCaller; gCaller = 3;
    [gFG dm_layoutLogo];
    if (release && (objc_getAssociatedObject(gFG, kLogoKey) || objc_getAssociatedObject(gFG, kNoClockLayoutKey))) DMReleaseStatusBarCopy(gFG);
    gCaller = was;
}

// ---- what shows ----
static BOOL held(void) { return [objc_getAssociatedObject(gFG, kHoldKey) boolValue]; }
static BOOL shown(void) { return gFG.window && !gFG.window.hidden && gFG.alpha >= 0.01; }
static int wifiIcons(void) { return (ours() && gWiFiMenuOn ? 1 : 0) + (gItemShown ? 1 : 0); }   // (ours, while the Wi-Fi Menu is on; iOS's, as last asked)
static double gLabelAt = -1;     // (wall time the time label came back after the unlock)
static int gStockFrames, gTwoFrames, gFrames;   // (frames drawn after the label came back: iOS's stock bar; both Wi-Fi icons)
static int gClosedFrames;        // (... ours, still closed up: its status icons over the time, no date -- the pull let go)

// ---- the run loop ----
static BOOL gLibOn; static double gNextLib, gNextMinute;
static BOOL TDue(void) { for (NSArray *e in gQueue) if ([e[0] doubleValue] <= gNow + 1e-9) return YES; return NO; }
static double gLabelInCommitAt = -1;   // (rows 25-27: the label back inside the bar's constraint pass in this commit, the iPad 2's unlock)
static void TLabelBack(BOOL hook, BOOL iosPass);
static void TCommit(void) {   // (the commit's layout pass, then Core Animation's pre-commit phase)
    if (gConstraintsDue || TMarked(gBarWindow)) {   // (the window's: a constraint pass due marks the window -- that pass first, then the marked views)
        if (gConstraintsDue) TConstraintPass();
        TLayoutTree(gBarWindow);
    }
    if (gLabelInCommitAt >= 0 && gWall + 1e-9 >= gLabelInCommitAt) {   // (the bar's own pass, after the copy's: its region places the label)
        gLabelInCommitAt = -1;
        gDMBarConstraintDepth++; if (gSTUI) gDMBarUpdateDepth++;
        TLabelBack(YES, NO);
        if (gSTUI) gDMBarUpdateDepth--; gDMBarConstraintDepth--;
        gFG.needsLayout = NO;   // (UIKit drops a setNeedsLayout made inside that pass: 18.5's frame bursts; 16.7.7: the pre-commit layout made it ours)
    }
    NSArray *h = gPreCommit ?: @[]; gPreCommit = [NSMutableArray array];
    gInPreCommit = YES; for (void (^b)(void) in h) b(); gInPreCommit = NO;
}
static void TTurn(BOOL frame) {
    NSMutableArray *due = [NSMutableArray array];
    for (NSArray *e in gQueue) if ([e[0] doubleValue] <= gNow + 1e-9) [due addObject:e];
    [due sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    for (NSArray *e in due) [gQueue removeObjectIdenticalTo:e];
    for (NSArray *e in due) { int was = gCaller; gCaller = 1; ((dispatch_block_t)e[1])(); gCaller = was; }
    if (frame && gStartupLink && gStartupLink.target) {
        gStartupLink.timestamp = gNow + 100.0; int was = gCaller; gCaller = 0;
        ((void (*)(id, SEL, id))objc_msgSend)(gStartupLink.target, gStartupLink.sel, gStartupLink);
        gCaller = was;
    }
    if (frame && gLibOn && gNow + 1e-9 >= gNextLib) { gNextLib += 0.2; DMWatchLock(); }   // (the 0.2 s library timer: DMSyncWindowsForLibraryBody)
    if (frame && gNow + 1e-9 >= gNextMinute) { gNextMinute += 60.0; TIOSUpdate(@{ @"time": @YES }); }   // (iOS's time, each minute)
    TCommit();
    if (!frame) return;
    if (gHeldAsked > 0 && shown() && ours() && gLastStart != (gItemShown ? 646.0 : 664.0)) gOldPlaceFrames++;   // (W2 review: one frame in 1 of 6 on the iPad 2, h01 D1)
    if (gLabelAt >= 0 && gWall + 1e-9 >= gLabelAt) {
        gFrames++;
        if (shown() && gClock && !ours() && !DMBarLockedNow()) gStockFrames++;
        if (shown() && wifiIcons() == 2) gTwoFrames++;
        if (shown() && gClock && ours() && objc_getAssociatedObject(gFG, kBarClosedUpKey)) gClosedFrames++;
    }
}
typedef void (^TEvent)(double wall);
// 60 Hz frames on the wall clock from `from` to `until`; asleep from `sleepFrom` to `sleepTo` (nothing runs, the awake clock stands)
static double gSleepFrom = -1, gSleepTo = -1;
static void TRun(double from, double until, TEvent ev) {
    for (long i = lround(from * 60.0);; i++) {
        double w = i / 60.0;
        if (w > until + 1e-9) break;
        if (gSleepFrom >= 0 && w >= gSleepFrom - 1e-9 && w < gSleepTo - 1e-9) continue;
        double slept = gSleepFrom >= 0 && w >= gSleepTo - 1e-9 ? gSleepTo - gSleepFrom : 0;
        gWall = w; gNow = w - slept;
        if (ev) ev(w);
        TTurn(YES);
        for (int n = 0; TDue() && n < 100; n++) TTurn(NO);
    }
}

// ---- iOS's side of a row ----
static void TLabelBack(BOOL hook, BOOL iosPass) {   // (the leading region gets its time label back: no layout pass of the copy, unless iosPass)
    gClock = YES;
    if (![gLeading.subs containsObject:gTimeLabel]) [gLeading.subs addObject:gTimeLabel];
    gTimeLabel.superview = gLeading;
    if (hook) {   // (the label's -didMoveToSuperview: SBClockBack on 15/16, SBAttach17 on 17+ -- site check)
        if (gSTUI) DMAttachIfFilledNow(((UIView *)gTimeLabel).superview.superview, "a label arrived", YES);
        else DMClockBackNow(((UIView *)gTimeLabel).superview.superview);
    }
    if (iosPass) [gFG setNeedsLayout];
}
static void TUnlockStart(void) {   // (the Cover Sheet starts to leave, the UI unlocked: SpringBoard's dismissal start, our CoverSheetLeaving hook)
    gUILocked = NO; gCover = NO;
    DMBarCoverLeaving();
}
static void TLock(void) {
    gUILocked = YES; gCover = YES; gClock = NO;
    [gLeading.subs removeObject:gTimeLabel]; gTimeLabel.superview = nil;
}
// a new world: SpringBoard starts (locked = onto the Lock Screen); the copy made with its data (iOS asks the items), into its window (the
// -didMoveToWindow hook), iOS's first layout pass due; the constructor's timeline (the watcher, DMEnsureLogo at 2 s, the library timer at 8 s,
// 17+: "start-up over" at 8.5 s)
static void TWorld(BOOL stui, BOOL locked) {
    gSTUI = stui; gUILocked = gCover = locked; gClock = !locked; gNoData = NO;
    gWindows = [NSMutableArray array]; gQueue = [NSMutableArray array]; gLog = [NSMutableArray array];
    gLockMgr = [TLockManager new];
    gFG = [_UIStatusBarForegroundView new]; gFG.bounds = (CGRect){{0, 0}, {1024, 24}};
    gBar = [_UIStatusBar new]; gItem = [_UIStatusBarWifiItem new];
    gLeading = [UIView new]; gTimeLabel = [UIView new]; gTrailing = [UIView new]; gHolder = [UIView new];
    gLeading.superview = gFG; gTrailing.superview = gFG; [gFG.subs addObject:gLeading]; [gFG.subs addObject:gTrailing];
    if (gClock) { [gLeading.subs addObject:gTimeLabel]; gTimeLabel.superview = gLeading; }
    for (int i = 0; i < 2; i++) { UIView *icon = [UIView new]; icon.bounds = (CGRect){{0, 0}, {20, 12}}; icon.superview = gTrailing; [gTrailing.subs addObject:icon]; }
    gBarWindow = stui ? [SBStatusBarWindow new] : [UIStatusBarWindow new];
    [gWindows addObject:[UIWindow new]]; [gWindows addObject:gBarWindow];
    [gBarWindow.subs addObject:gBar]; gBar.superview = gBarWindow;
    [gBarWindow.subs addObject:gHolder]; gHolder.superview = gBarWindow;
    TIOSUpdate(@{ @"wifi": @YES, @"time": @YES });
    [gBar.subs addObject:gFG]; gFG.superview = gBar;
    TDidMoveToWindow(gFG);
    gFG.needsLayout = YES;
    gNextMinute = 60.0; gLibOn = NO; gNextLib = 8.0;
    TAfter(0.0, ^{ DMStartStartupWatcher(); });
    TAfter(2.0, ^{ DMEnsureLogo(0); });
    TAfter(8.0, ^{ gLibOn = YES; gNextLib = gNow; });
    if (stui) TAfter(8.5, ^{ DMRelayoutUnattachedBars(@"start-up over"); });
}

// ---- checks ----
static int gFails = 0, gChecks = 0;
static void check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static NSString *fam(void) { return gSTUI ? @"17/18" : @"15/16"; }
static NSString *by(void) { return gOursBy < 0 ? @"never" : [NSString stringWithFormat:@"%@%@", @[@"the watcher", @"the main queue (DMEnsureLogo, the label's next turn)", @"its own layout pass", @"a direct layout"][gOursBy], gOursHeld ? @", held" : @", NOT held"]; }
// the row's checks: 2 s after the label came back, and at the end (the bar ours, iOS's Wi-Fi item out); asked once as ours; no stock frame after the
// label came back (stockMax frames when the label's arrival is not seen); both Wi-Fi icons in at most one frame (the ask comes after the layout pass)
typedef struct { int at2; BOOL ours2, oursEnd, shownEnd, itemEnd; } TSeen;
static TSeen gSeen;
static void TRow(NSString *name, int stockMax, BOOL twoCheck) {
    printf("-- %s %s: ours by %s; Wi-Fi icons 2 s after the label %d, at the end %d; asked as ours %d; stock frames %d, two-icon frames %d of %d\n",
           fam().UTF8String, name.UTF8String, by().UTF8String, gSeen.at2, wifiIcons(), gAsksAsOurs, gStockFrames, gTwoFrames, gFrames);
    check(gSeen.ours2 && gSeen.at2 == 1, [NSString stringWithFormat:@"%@ %@: 2 s after the unlock the bar is ours with one Wi-Fi icon (%d, ours %d)", fam(), name, gSeen.at2, gSeen.ours2]);
    check(ours() && shown() && !gItemShown, [NSString stringWithFormat:@"%@ %@: at the end the bar is ours and shown, iOS's Wi-Fi item out", fam(), name]);
    check(gAsksAsOurs == 1, [NSString stringWithFormat:@"%@ %@: iOS's items asked exactly once as ours (%d)", fam(), name, gAsksAsOurs]);
    check(gStockFrames <= stockMax, [NSString stringWithFormat:@"%@ %@: iPadOS's stock bar after the time came back in %d frame(s), at most %d", fam(), name, gStockFrames, stockMax]);
    if (twoCheck) check(gTwoFrames <= 1, [NSString stringWithFormat:@"%@ %@: both Wi-Fi icons in %d frame(s), at most 1", fam(), name, gTwoFrames]);
    int before = gAsks;
    TRun(gWall + 1.0 / 60.0, gWall + 5.0, nil);
    check(gAsks == before, [NSString stringWithFormat:@"%@ %@: no ask in 5 s more at rest (%d)", fam(), name, gAsks - before]);
}
static void TProbe(double w) { if (gLabelAt >= 0 && fabs(w - (gLabelAt + 2.0)) < 0.5 / 60.0) { gSeen.at2 = shown() ? wifiIcons() : -1; gSeen.ours2 = ours(); } }

// ---- the rows ----
// a respring onto the Lock Screen; the user unlocks at `unlockAt` (wall), the label back `labelAfter` later
static void RowLock(BOOL stui, NSString *name, double unlockAt, double sleepFrom, double sleepTo, BOOL hook, BOOL iosPass, double labelAfter, int stockMax) {
    gSleepFrom = sleepFrom; gSleepTo = sleepTo;
    TWorld(stui, YES);
    __block BOOL u = NO, l = NO; BOOL early = labelAfter < 0;
    gLabelAt = unlockAt + labelAfter;
    TRun(0, unlockAt + 10.0, ^(double w) {
        if (early && !l && w >= gLabelAt - 1e-9) { l = YES; TLabelBack(hook, iosPass); }
        if (!u && w >= unlockAt - 1e-9) { u = YES; TUnlockStart(); }
        if (!early && !l && w >= gLabelAt - 1e-9) { l = YES; TLabelBack(hook, iosPass); }
        TProbe(w);
    });
    TRow(name, stockMax, YES);
}
// Skip Lock Screen After Respring on: no passcode (SpringBoard starts unlocked: SBBootDefaults' -dontLockAfterCrash), or an answer not sure at the
// start (the Lock Screen, then DMSkipLockAfterRespring's unlock at ~8 s), or a passcode (the Lock Screen stays; the user unlocks at 5 s)
static void RowSkip(BOOL stui, NSString *name, int pass) {
    gSkip = YES; gPass = pass;
    BOOL startsUnlocked = pass == 1;
    TWorld(stui, !startsUnlocked);
    __block double unlockAt = pass == 0 ? 5.0 : -1;
    if (startsUnlocked) gLabelAt = 0;
    TRun(0, 25.0, ^(double w) {
        if (gUnlockAsked && unlockAt < 0) { unlockAt = w; gLabelAt = w + 0.35; TUnlockStart(); }
        if (pass == 0 && unlockAt > 0 && w >= unlockAt - 1e-9 && gUILocked) { gLabelAt = w + 0.35; TUnlockStart(); }
        if (!gClock && gLabelAt > 0 && w >= gLabelAt - 1e-9) TLabelBack(YES, NO);
        TProbe(w);
    });
    if (pass == 2) check(unlockAt > 7.9 && unlockAt < 9.0, [NSString stringWithFormat:@"%@ %@: DMSkipLockAfterRespring unlocked at %.2f s (as before)", fam(), name, unlockAt]);
    TRow(name, 0, YES);
}
// lock and unlock again with no respring (BASICS-GATE row 3): the bar ours all along
static void RowRelock(BOOL stui) {
    gSkip = YES; gPass = 1;
    TWorld(stui, NO);
    gLabelAt = 0;
    __block BOOL lk = NO, u = NO, l = NO;
    TRun(0, 30.0, ^(double w) {
        if (!lk && w >= 20.0 - 1e-9) { lk = YES; TLock(); }
        if (!u && w >= 25.0 - 1e-9) { u = YES; TUnlockStart(); }
        if (!l && w >= 25.35 - 1e-9) { l = YES; gLabelAt = w; TLabelBack(YES, NO); }
        TProbe(w);
    });
    TRow(@"lock at 20 s and unlock at 25 s, no respring", 0, YES);
}
// 1.8.1.1: a copy the safety release gave up on (unlocked, filled, no time label for 2 s: never held again), its time back later, laid out by its
// own pass with no hold
static void RowGaveUp(BOOL stui) {
    gSkip = YES; gPass = 1;
    TWorld(stui, NO);
    gClock = NO; [gLeading.subs removeObject:gTimeLabel]; gTimeLabel.superview = nil;
    gLabelAt = 20.0;
    __block BOOL l = NO, gaveUp = NO;
    TRun(0, 30.0, ^(double w) {
        if (!gaveUp && objc_getAssociatedObject(gFG, kHoldGaveUpKey)) gaveUp = YES;
        if (!l && w >= 20.0 - 1e-9) { l = YES; TLabelBack(NO, YES); }
        TProbe(w);
    });
    check(gaveUp, [NSString stringWithFormat:@"%@ given-up copy: the safety release gave it up first (%d, as before)", fam(), gaveUp]);
    TRow(@"1.8.1.1's copy the safety release gave up on, made ours by its own pass", 0, YES);
}
// Stage Manager's direct layouts: the Lock Screen's copy (released, not ours), its time back with no hook and laid out directly with no hold
// (DMSMRefreshBars' way); or held and laid out directly with nothing more (DMSMChrome's way), released by its own pass a moment later
static void RowDirect(BOOL stui, BOOL heldChrome) {
    TWorld(stui, YES);
    gLabelAt = 20.35;
    __block BOOL u = NO, l = NO, p = NO; __block int asksInLayout = -1;
    TRun(0, 30.0, ^(double w) {
        if (!u && w >= 20.0 - 1e-9) { u = YES; TUnlockStart(); }
        if (!l && w >= 20.35 - 1e-9) {
            l = YES; TLabelBack(NO, NO);
            if (heldChrome) { DMHoldStatusBarCopy(gFG); TDirect(NO); } else TDirect(YES);
        }
        if (heldChrome && l && asksInLayout == -1 && w >= 20.35 + 0.5 / 60.0) asksInLayout = held() ? gAsksAsOurs : -2;   // (the next frame: still held, not asked)
        if (heldChrome && !p && w >= 20.6 - 1e-9) { p = YES; [gFG setNeedsLayout]; }
        TProbe(w);
    });
    if (heldChrome) check(asksInLayout == 0, [NSString stringWithFormat:@"%@ held copy laid out directly: ours, still held, and not asked in the frame after (%d; -2: not held)", fam(), asksInLayout]);
    TRow(heldChrome ? @"a held copy laid out directly (DMSMChrome's way), released by its own pass" : @"a direct layout with no hold (DMSMRefreshBars' way)", 0, YES);
}
// the ask finds no data (the bar's data nil for 1.5 s from the unlock; iOS's next update is the minute's) or no bar above the copy (the copy moved out
// of its bar for 1 s from the moment it becomes ours, then back, laid out by its own pass)
static void RowNoBarNoData(BOOL stui, BOOL noBar) {
    TWorld(stui, YES);
    gLabelAt = 20.35;
    __block BOOL u = NO, l = NO, back = NO, moved = NO;
    TRun(0, 75.0, ^(double w) {
        if (!u && w >= 20.0 - 1e-9) { u = YES; TUnlockStart(); if (!noBar) gNoData = YES; }
        if (!l && w >= 20.35 - 1e-9) {
            l = YES; TLabelBack(YES, NO);
            if (noBar && ours() && !moved) { moved = YES; [gBar.subs removeObject:gFG]; [gHolder.subs addObject:gFG]; gFG.superview = gHolder; }
        }
        if (noBar && !moved && ours()) { moved = YES; [gBar.subs removeObject:gFG]; [gHolder.subs addObject:gFG]; gFG.superview = gHolder; }
        if (!noBar && gNoData && w >= 21.85 - 1e-9) gNoData = NO;
        if (noBar && moved && !back && w >= 21.35 - 1e-9) { back = YES; [gHolder.subs removeObject:gFG]; [gBar.subs addObject:gFG]; gFG.superview = gBar; [gFG setNeedsLayout]; }
        TProbe(w);
    });
    gSeen.at2 = 1; gSeen.ours2 = YES;   // (2 s after: both icons allowed here -- the ask is owed until the next layout)
    TRow(noBar ? @"the ask finds no bar above the copy" : @"the ask finds no data (iOS's next update the minute's)", 0, NO);
}
// the Wi-Fi Menu off: iOS's own item in every bar, ours never (as before)
static void RowMenuOff(BOOL stui) {
    gWiFiMenuOn = NO;
    TWorld(stui, YES);
    gLabelAt = 5.35;
    __block BOOL u = NO, l = NO;
    TRun(0, 15.0, ^(double w) { if (!u && w >= 5.0 - 1e-9) { u = YES; TUnlockStart(); } if (!l && w >= 5.35 - 1e-9) { l = YES; TLabelBack(YES, NO); } });
    check(ours() && gItemShown && wifiIcons() == 1, [NSString stringWithFormat:@"%@ Wi-Fi Menu off: iOS's Wi-Fi item alone after the unlock (as before)", fam()]);
}
// the time label placed by the first data update after the unlock, inside it (the label's arrival hook runs there, its layout at once): our own ask
// when one is on its way (the copy's release or newlyOurs asked it), else iOS's next update. Its items answered as not ours first; the layout's ask
// inside it found ours on its way and was dropped (regressions review of WIFI2, F1: two Wi-Fi icons until iOS's next Wi-Fi update)
static void RowLabelInAsk(BOOL stui) {
    TWorld(stui, YES);
    __block BOOL u = NO, l = NO;
    gLabelAt = 5.35;
    TRun(0, 15.0, ^(double w) {
        if (!u && w >= 5.0 - 1e-9) { u = YES; gLabelInData = YES; TUnlockStart(); }
        if (!l && w >= 5.35 - 1e-9) { l = YES; if (gLabelInData) TIOSUpdate(@{ @"time": @YES }); }
        TProbe(w);
    });
    check(gLabelInAsk == 1, [NSString stringWithFormat:@"%@ label in an update: the time label was placed inside our own ask (%d; 0: iOS's update, -1: never)", fam(), gLabelInAsk]);
    TRow(@"Lock Screen start, unlock at 5 s, the label placed inside the first data update after it (our ask)", 0, YES);
}
// 1.8.7.6 (the iPad 2's f03 pass, BASICS-GATE row 8 / W10): a Notification Center pull from the Home Screen, the copy ours from the start (Skip on, no
// passcode). The pull begins at 20 s: the Cover Sheet takes the screen's copy's time label (a pull not committed yet is not over the bar: BarUnlock.h). It
// commits to going back at 20.4 s, the Cover Sheet starts to leave: DMBarCoverLeaving lays the copy out without its clock -- closed up, unlocked, not the
// locked look. The label comes back with no layout pass of the copy (iPad 2 16.7.7: the watch flag saw none, f03 nc3):
//   order 0, the iPad 2's (f03 nc2-nc4): nothing lays the copy out in the pull; the label back at 20.9 s inside the bar's own constraint pass, as at every
//            15/16 unlock in f03 (each with "the layout for its time label deferred")
//   order 1: the same, the label back outside any pass
//   order 2, the M1's (15.6.1, check-1.8.1.1 log, 5 Nov 13:57:33): iOS's passes lay the copy out without its clock in the pull (20.05 s) and 0.15 s after
//            the commit (20.55 s); the label back in the next frame inside the bar's constraint pass
//   order 3: the M1's with the layout pass of the copy that came right after the label there (+7 ms, no clock-back line of ours): whole with or without
//            us -- why the M1 passed W10 on f03 (control: passes on the code before too)
//   order 4: a full pull (committed at 20.4 s: the locked look), pushed up by a Home press at 22.4 s, the label back at 22.75 s inside the constraint
//            pass: the locked look's way, as before (control)
// After the label: no frame drawn with the copy still closed up (its icons over the time), none of our layouts inside the bar's constraint pass
// (the NC-pull crash's way: deferred to the next turn, the log says so), the copy ours, shown, one Wi-Fi icon, not asked again.
static void RowPull(BOOL stui, int order) {
    static NSString *names[] = { @"a pull let go, the iPad 2's order (16.7.7: the label back inside the bar's constraint pass, no layout pass)",
        @"a pull let go, the label back outside any pass, no layout pass", @"a pull let go, the M1's order (15.6.1: iOS's closed-up passes, the label in the constraint pass)",
        @"a pull let go, the M1's order with its layout pass after the label (control)", @"a full pull, pushed up by a Home press (control)" };
    gSkip = YES; gPass = 1;
    TWorld(stui, NO);
    BOOL full = order == 4, inPass = order != 1, m1 = order == 2 || order == 3;
    double commitAt = 20.4, labelAt = full ? 22.75 : (m1 ? 20.55 + 1.0 / 60.0 : 20.9);
    gLabelAt = labelAt;
    __block BOOL began = NO, committed = NO, m1Pass1 = NO, m1Pass2 = NO, pushedUp = NO, l = NO;
    __block int closedBefore = -1, lockedLookBefore = -1, deferredBefore = 0;
    TRun(0, labelAt + 5.0, ^(double w) {
        if (!began && w >= 20.0 - 1e-9) { began = YES; gClock = NO; [gLeading.subs removeObject:gTimeLabel]; gTimeLabel.superview = nil; }
        if (m1 && !m1Pass1 && w >= 20.05 - 1e-9) { m1Pass1 = YES; [gFG setNeedsLayout]; }   // (iOS's own pass in the pull)
        if (!committed && w >= commitAt - 1e-9) {
            committed = YES;
            if (full) { gCover = YES; DMHideAppBarItemsNow(); DMRelayoutUnattachedBars(@"Notification Center pulled down"); [gFG setNeedsLayout]; }   // (DMCSPullCommit; the Cover Sheet over the bar)
            else TUnlockStart();   // (the pull commits to going back: the Cover Sheet starts to leave, our CoverSheetLeaving hook)
        }
        if (full && !pushedUp && w >= 22.4 - 1e-9) { pushedUp = YES; TUnlockStart(); }
        if (m1 && !m1Pass2 && w >= 20.55 - 1e-9) { m1Pass2 = YES; [gFG setNeedsLayout]; }    // (iOS's own passes 0.15 s after the commit, the label not back yet)
        if (!l && w >= labelAt - 1e-9) {
            l = YES;
            closedBefore = objc_getAssociatedObject(gFG, kBarClosedUpKey) != nil; lockedLookBefore = [objc_getAssociatedObject(gFG, kBarLookLockedKey) boolValue];
            for (NSString *s in gLog) if ([s containsString:@"the layout for its time label deferred"]) deferredBefore++;
            if (inPass) gDMBarConstraintDepth++;   // (the bar's -updateConstraints places its region items: the label into its region)
            TLabelBack(YES, order == 3);
            if (inPass) gDMBarConstraintDepth--;
        }
        TProbe(w);
    });
    NSString *name = names[order];
    int deferred = -deferredBefore;
    for (NSString *s in gLog) if ([s containsString:@"the layout for its time label deferred"]) deferred++;
    printf("-- %s %s: before the label closed up %d, locked look %d; after it closed-up frames %d of %d, our layouts in the constraint pass %d, deferred %d\n",
           fam().UTF8String, name.UTF8String, closedBefore, lockedLookBefore, gClosedFrames, gFrames, gLayoutsInPass, deferred);
    check(closedBefore == 1 && lockedLookBefore == (full ? 1 : 0), [NSString stringWithFormat:@"%@ %@: as the label comes back the copy is ours and closed up, %@ (closed up %d, locked look %d)",
                                                                    fam(), name, full ? @"in the locked look" : @"NOT in the locked look", closedBefore, lockedLookBefore]);
    check(gClosedFrames == 0, [NSString stringWithFormat:@"%@ %@: no frame drawn with the time back and the copy still closed up (its icons over the time) (%d)", fam(), name, gClosedFrames]);
    check(!objc_getAssociatedObject(gFG, kBarClosedUpKey), [NSString stringWithFormat:@"%@ %@: at the end the copy has its clock layout (not closed up)", fam(), name]);
    check(gLayoutsInPass == 0, [NSString stringWithFormat:@"%@ %@: none of our layouts inside the bar's own constraint pass (%d)", fam(), name, gLayoutsInPass]);
    if (order == 0 || order == 2 || order == 4)
        check(deferred == 1, [NSString stringWithFormat:@"%@ %@: the log says the layout for its time label waited for the next turn, once (%d)", fam(), name, deferred]);
    else if (order == 1) check(deferred == 0, [NSString stringWithFormat:@"%@ %@: nothing deferred (%d)", fam(), name, deferred]);
    TRow(name, 0, YES);
}

// 1.8.7.8: the iPad 2's unlock after a respring (1.8.7.6~f04 r1 / r2a / r2c: Home press at 6.7 s / 60.9 s / 180.8 s on the Lock Screen; the Cover
// Sheet starts to leave, the label back 0.24 s later inside the bar's constraint pass, "the layout for its time label deferred", the copy laid out
// ours and released by the pre-commit layout). Both Wi-Fi icons in no frame: iOS's items answered as ours before that layout.
static void RowLockInCommit(BOOL stui, NSString *name, double unlockAt, double sleepFrom, double sleepTo) {
    gSleepFrom = sleepFrom; gSleepTo = sleepTo;
    TWorld(stui, YES);
    __block BOOL u = NO;
    gLabelAt = unlockAt + 0.24;
    TRun(0, unlockAt + 10.0, ^(double w) {
        if (!u && w >= unlockAt - 1e-9) { u = YES; TUnlockStart(); gLabelInCommitAt = gLabelAt; }
        TProbe(w);
    });
    int deferred = 0; for (NSString *s in gLog) if ([s containsString:@"the layout for its time label deferred"]) deferred++;
    printf("-- %s %s: the label inside the bar's pass in the commit; deferred %d, late pre-commit handlers %d\n", fam().UTF8String, name.UTF8String, deferred, gLateHandlers);
    if (!stui) check(deferred == 1, [NSString stringWithFormat:@"%@ %@: the log says the layout for its time label waited for the next turn, once, as on the iPad 2 (%d)", fam(), name, deferred]);
    check(gTwoFrames == 0, [NSString stringWithFormat:@"%@ %@: both Wi-Fi icons in no frame (%d of %d): iOS's items answered as ours before the layout that made the copy ours", fam(), name, gTwoFrames, gFrames]);
    if (!stui) check(gNoAnimAsks == 1, [NSString stringWithFormat:@"%@ %@: iOS's items asked once while held, with no animation, before that layout (%d)", fam(), name, gNoAnimAsks]);
    check(gLateHandlers == 0, [NSString stringWithFormat:@"%@ %@: no pre-commit layout asked for inside the pre-commit phase (%d)", fam(), name, gLateHandlers]);
    TRow(name, 0, YES);
}

static int RunRow(int r) {
    BOOL s = r >= 100; int k = r % 100;
    DMStockWiFiInit();
    if (k == 0) check((gSBItemHooks & 16) && class_getMethodImplementation([_UIStatusBarWifiItem class], @selector(canEnableDisplayItem:fromData:)) == (IMP)DMWiFiItemCanEnable,
                      @"set-up: iOS's Wi-Fi item answers through DMWiFiItemCanEnable, added as on the iPad (DMStockWiFiInit)");
    switch (k) {
        case 0: RowLock(s, @"Lock Screen start (Skip off), unlock at 5 s", 5.0, -1, -1, YES, NO, 0.35, 0); break;
        case 1: RowLock(s, @"Lock Screen start, unlock at 20 s", 20.0, -1, -1, YES, NO, 0.35, 0); break;
        case 2: RowLock(s, @"Lock Screen start, unlock at 60 s, the screen on", 60.0, -1, -1, YES, NO, 0.35, 0); break;
        case 3: RowLock(s, @"Lock Screen start, unlock at 60 s, asleep from 15 s to 58 s", 60.0, 15.0, 58.0, YES, NO, 0.35, 0); break;
        case 4: RowLock(s, @"Lock Screen start, unlock at 10 min, the screen on", 600.0, -1, -1, YES, NO, 0.35, 0); break;
        case 5: RowLock(s, @"Lock Screen start, unlock at 10 min, asleep from 15 s to 9:58", 600.0, 15.0, 598.0, YES, NO, 0.35, 0); break;
        case 6: RowLock(s, @"Lock Screen start, unlock at 60 s, the label's arrival not seen (the unlock's cues only)", 60.0, -1, -1, NO, NO, 0.3, 30); break;
        case 7: RowLock(s, @"Lock Screen start, unlock at 20 s, the label back just before the Cover Sheet leaves", 20.0, -1, -1, YES, NO, -0.1, 1); break;
        case 8: RowLock(s, @"Lock Screen start, unlock at 5 s, iOS lays the copy out at the unlock (control)", 5.0, -1, -1, NO, YES, 0.35, 0); break;
        case 9: RowSkip(s, @"Skip on, no passcode: unlocked start", 1); break;
        case 10: RowSkip(s, @"Skip on, the passcode answer unsure at the start: unlocked by us at ~8 s", 2); break;
        case 11: RowSkip(s, @"Skip on, a passcode: the user unlocks at 5 s", 0); break;
        case 12: RowRelock(s); break;
        case 13: RowGaveUp(s); break;
        case 14: RowDirect(s, NO); break;
        case 15: RowDirect(s, YES); break;
        case 16: RowNoBarNoData(s, NO); break;
        case 17: RowNoBarNoData(s, YES); break;
        case 18: RowMenuOff(s); break;
        case 19: RowLabelInAsk(s); break;
        case 20: case 21: case 22: case 23: case 24: RowPull(s, k - 20); break;
        case 25: RowLockInCommit(s, @"Lock Screen start, unlock at 6.7 s, the label back in the bar's pass in the commit (f04 r1)", 6.7, -1, -1); break;
        case 26: RowLockInCommit(s, @"Lock Screen start, unlock at 60.9 s, the screen on, the label in the commit (f04 r2a)", 60.9, -1, -1); break;
        case 27: RowLockInCommit(s, @"Lock Screen start, unlock at 180.8 s, asleep from 20 s to 178 s, the label in the commit (f04 r2c)", 180.8, 20.0, 178.0); break;
        default: return -1;
    }
    // (every row with a held ask, W2: the bar laid out right after it, with no animation -- our first layout after it has the final icons start, and
    //  no frame shows our icons at the old place: the review of W2)
    if (gHeldAsked > 0) {
        printf("-- %s row %d: held asks %d; our icons start at the first layout after it %.1f, final %.1f; the region placed after it with no animation %d; frames at the old place %d\n",
               fam().UTF8String, k, gHeldAsked, gFirstStartAfterAsk, TIconsStart(), gPlacedAfterAskNoAnim, gOldPlaceFrames);
        check(gFirstStartAfterAsk == TIconsStart(), [NSString stringWithFormat:@"%@ row %d: the copy's first layout after the held ask has the final icons start (%.1f, final %.1f): the bar placed its region first",
                                                     fam(), k, gFirstStartAfterAsk, TIconsStart()]);
        check(gPlacedAfterAskNoAnim != 0, [NSString stringWithFormat:@"%@ row %d: the region placed after the held ask with no animation (%d; -1: unchanged)", fam(), k, gPlacedAfterAskNoAnim]);
        check(gOldPlaceFrames == 0, [NSString stringWithFormat:@"%@ row %d: no frame drawn after the held ask with our icons at the old place, 18 pt left (%d)", fam(), k, gOldPlaceFrames]);
    }
    // (every row, 1.8.7.8 review of W, F1: the held copy's ask, an update of the bar, never inside one -- row 19's label is placed inside an update)
    check(gNestedUpdates == 0 && gDMBarDataUpdateDepth == 0, [NSString stringWithFormat:@"%@ row %d: no data update of the bar started inside another one (%d), the hook's count back at 0 (%d)",
                                                             fam(), k, gNestedUpdates, gDMBarDataUpdateDepth]);
    return gFails;
}
int main(int argc, char **argv) {
    (void)argc; (void)argv;
    int fails = 0, rows = 0;
    for (int f = 0; f < 2; f++)
        for (int k = 0; k < 28; k++) {
            int r = f * 100 + k;
            fflush(stdout);
            pid_t pid = fork();
            if (pid == 0) { int n; @autoreleasepool { n = RunRow(r); } fflush(stdout); _exit(n < 0 ? 0 : (n > 100 ? 100 : n)); }
            int st = 0; waitpid(pid, &st, 0); rows++;
            if (WIFEXITED(st)) fails += WEXITSTATUS(st);
            else { printf("FAIL  row %d ended by signal %d\n", r, WTERMSIG(st)); fails++; }
        }
    printf("%d row(s), %d check(s) fail\n", rows, fails);
    return fails > 90 ? 90 : fails;
}
