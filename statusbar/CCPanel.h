// CCPanel.h -- our own Control Center: the panel (1.8.0 P2; plans/control-center-1.8.0.md, plans/control-center.md "Spike (phase 1)"), iPadOS
// 15-17 with Control Center Style Mac: the style common/CCStyle.h's rule gives (P1, CCStyleSB.h's DMCCStyleChosenNow), so "mac" stored (Mac is
// never the default: everyone keeps the Control Center they have, KT 3 Nov), and this file's check passed on this build. Any other
// style ("stock", "bigsurcenter", or false, which the crash guard writes after our Control Center crashed SpringBoard: tools/crashmap-rules.txt
// "controlcenter") is iPadOS's own Control Center, exactly as before: nothing of this file is hooked then.
// Included once by StatusBar.x, after the menus' look (DMMakeBlur, DMSystemInterfaceStyle), the Control Center helpers (DMCCTypes, DMCCGet,
// gCCWindowSeen, DMControlCenterController) and Control Center Style (CCStyleSB.h).
//
// Where it lives: inside Apple's own Control Center view controller (CCUIModularControlCenterOverlayViewController, in SBControlCenterWindow), as
// BigSurCenter's panel does. Apple still presents and dismisses Control Center, so every way iPadOS opens it shows ours (the status bar pull, the
// top right edge swipe, a click on the status icons, our menu bar's Control Center icon, the Lock Screen, -presentAnimated:), and iPadOS's look is
// just not building ours. Our host view (full screen, on top of Apple's views in the overlay's view) holds the panel; Apple's full-screen backdrop
// is hidden while ours shows (behind one of Apple's modules opened expanded a backdrop of ours of the same material shows, as stock), Apple's grid
// and header stay, empty, under it: nothing of them shows (the header's status bar copy is held at alpha 0, DMCCPHeaderBarAway; its background is
// transparent).
// The rules from the spike (17.5, 30 Oct):
//  1. Containment: each of Apple's module containers moves into our panel WITH its controller (out of Apple's grid controller, into our panel's
//     controller, a child of Apple's overlay). Closing an expanded module re-adds the container controller to the parent it had with UIKit's
//     hierarchy check; with Apple's grid still the parent and the view in our panel, SpringBoard aborted (cc03). The same check wants the view
//     first: a controller is added only under the controller its view is in (DMCCPAdopt, DMCCPGiveBack). DMCCPCheck reads it (debug).
//  2. Apple's grid and header stay: their dismissal recognizers live there (a tap outside, a swipe up outside); hiding them took the dismissal
//     with them (cc02).
//  3. Built when Apple builds it (1.5-2.6 s after start: the overlay's -viewDidLoad, then -moduleCollectionViewController:didAdd... per module),
//     laid out while hidden, sizes from Apple's own grid rects (CCSupport's included), plain frames (common/CCLayout.h, Mac-tested). Nothing of
//     ours asks for Control Center before SpringBoard made it.
// iPadOS's look back while running (Mac -> iPadOS, or BigSurCenter loaded late: DMCCPGiveBack) is a start's: what the panel changed on Apple's
// own objects -- the backdrop's hidden flag, the header's status bar alpha, each container's place among Apple's grid's views, its hidden flag
// and Apple's presentation values on its views -- was kept as Apple had it (or as Apple asked for it since) when ours first changed it, and is
// handed back so (common/CCGiveBack.h; 1.8.0 regression F1: the header's status icons row stayed hidden until the next respring).
// Everything Apple's is asked through the checked table below (DMCCPCheckAPI: class, method, type encoding, instance variable), all or nothing:
// one row missing or of another shape and nothing is hooked, Control Center stays iPadOS's, and the verdict says why (common/CCMacCheck.h, for
// Settings and Report a Problem). Optional rows only take their part away (the motion's join with Apple's spring, our tiles opening Apple's
// expanded views, a swipe on Apple's tiles, the room made under Apple's sensor indicator and the step back for its list of apps -- 15 has no list).
// The indicator's own reads differ between 15 and 16 / 17 and are checked where they are read (DMCCPSensorNow): one not there, and the panel
// stays under the bar as before P4 (it covers the indicator then).
// Performance: nothing runs while Control Center is closed (no timer, no observer; the tiles read their states once after Apple's build, hidden);
// at a presentation the tiles get their state once (tileWillPresent) and Apple's order and sizes are compared with the last layout's; each
// presentation step adds one animation to Apple's own batch; a turn, a module list change (Apple's adds of one pass: DMCCPLayoutSoon) or a reorder
// lays the panel out once.
// The tile interface (the Mac tiles drawn by us: Connectivity, Display, Sound, Now Playing -- CCTiles.h, P3): DMCCTile below. A tile that could
// not be made leaves a placeholder there; a tap on one opens the Apple module it stands for, expanded, out of our tile.
// With the rest of SpringBoard (P4): Esc closes it, an open page goes back first (DMCCPanelEscape, from SpringBoard's press hook: Control Center's
// window has the keys while it shows); the menu bar's Control Center icon shows while ours is the style, Battery Menu off too (DMCCPanelWanted),
// and is lit while it is open (BatteryMenu.h); RAM & CPU's add by itself measures the panel (DMCCPanelRoomForModule) and the walks over Control
// Center's labels skip our views (DMCCPanelOwnView); the panel hangs under Apple's sensor indicator when that shows (DMCCPSensorLook).
#pragma once
#include "../common/CCLayout.h"     // (where every tile goes, the panel's place and motion -- plain C, tools/test-cclayout.sh)
#include "../common/CCMacCheck.h"   // (the self-check's verdict for Settings: MSBD_CC_CHECK_KEY)
#include "../common/CCGiveBack.h"   // (Apple's values kept and handed back with iPadOS's look -- plain C, tools/test-ccgiveback.sh)
#include "../common/Diag.h"         // (the check's record on untested iPadOS builds: MSBDDiagWrite "ControlCenter")

#define kDMCCPOverlay "CCUIModularControlCenterOverlayViewController"
#define kDMCCPGrid "CCUIModuleCollectionViewController"
#define kDMCCPContainerVC "CCUIContentModuleContainerViewController"
#define kDMCCPContainerView "CCUIContentModuleContainerView"
#define kDMCCPProvider "CCUIOverlayStatusBarPresentationProvider"   // (the iPad's: Apple's +_presentationProviderForDevice, 15.6.1 / 16.7.7 / 17.5.1)
#define kDMCCPRectType "{CGRect={CGPoint=dd}{CGSize=dd}}"

// ---- the style -----------------------------------------------------------------------------------------------------------------------------
// Mac when Control Center Style's rule gives Mac (common/CCStyle.h, as SpringBoard reads it: CCStyleSB.h, looked at again when the stored style
// changed): the check's verdict it reads is the one DMCCPanelInit published at this start, before its first look. False is the crash guard's "back
// to stock" (iPadOS's).
static BOOL DMCCPStyleIsMac(void) { return DMCCStyleChosenNow() == kMSBDCCStyleMac; }
// Another Control Center in SpringBoard: BigSurCenter's panel lives in the same overlay. Ours never goes in next to it (P1's exclusivity table
// keeps only the chosen one loaded; this is the last word in SpringBoard).
static BOOL DMCCPOtherCC(void) { return objc_getClass("SCMainViewController") != Nil; }

// ---- the tile interface (P3) ---------------------------------------------------------------------------------------------------------------
// A Mac tile drawn by us. Its place is its role's in the Mac section (CCLayout.h: Connectivity 2 x 2, the wide Display / Sound / Now Playing);
// the Apple modules it stands for (CCLayout.h MSBDCCRoleForModule) stay adopted but hidden at its frame, so Apple's expanded view of one grows out
// of this tile (DMCCPanelExpandModule). Its view is made once, when the panel is built; it is laid out by the panel (tileLayoutInBounds:scale:).
@protocol DMCCTile <NSObject>
- (int)tileRole;                  // MSBDCCRoleTile... (CCLayout.h)
- (NSString *)tileID;             // e.g. "mac.connectivity" (logs, triggers): unique, never a module's identifier (DMCCPanelAddTile)
- (UIView *)tileView;
@optional
- (void)tileLayoutInBounds:(CGRect)bounds scale:(CGFloat)scale;   // its frame changed; scale: Menu Bar Size's (1, 1.125, 1.25) for our text and symbols
- (void)tileWillPresent;          // Control Center is about to show: the state marked dirty while it was closed goes in now (nothing runs closed)
- (void)tileDidDismiss;           // closed: stop what tileWillPresent started (a scan, a timer)
- (void)tileLockedChanged:(BOOL)locked;   // the Lock Screen's Control Center: rows needing Settings or our menu window are disabled
- (UIView *)tileDetailViewForWidth:(CGFloat)width;   // a detail page in place of the tiles (its frame's height is the page's), or nil: none
- (NSString *)tileDetailTitle;    // the page's title on its back row
- (BOOL)tileDetailNeedsUnlock;    // the page needs Settings or our menu window: not opened while locked
- (void)tileDetailDidClose;
@end

// ---- state ---------------------------------------------------------------------------------------------------------------------------------
static BOOL gCCPSupported = NO;   // 15-17, the API check passed (DMCCPanelInit)
static BOOL gCCPHooked = NO;      // our hooks are in (Mac was chosen at the start, or since)
static BOOL gCCPOn = NO;          // the panel is in force: Apple's containers are adopted as Apple builds them, the panel shows
static BOOL gCCPPending = NO;     // a style change waits for Control Center to close (DMCCPApplyStyle)
static unsigned gCCPPendingGen = 0;   // (its look a second later: the latest one only)
static BOOL gCCPUpdating = NO, gCCPJoined = NO;   // (inside Apple's presentation step; our motion went into Apple's batch for it)
static BOOL gCCPLocked = NO;      // the Lock Screen's Control Center (at the last presentation)
// Control Center shows: from its controller's -_willPresent to its -_didDismiss (our hooks). Our hooks of Apple's views read this, never
// DMControlCenterActive: Apple calls them inside -[SBControlCenterController init] too (the overlay's -viewDidDisappear: updates its header's
// sensor status), and asking the controller there re-enters its +sharedInstance's dispatch_once: SpringBoard trapped at its start (M1 15.6.1,
// 1.8.0~i11, twice, then started without tweaks).
static BOOL gCCPShown = NO;
static __weak UIViewController *gCCPOverlay, *gCCPGrid;
@class DMCCPPanelController, DMCCPHostView, DMCCPPanelView;
static DMCCPPanelController *gCCPVC;   // our panel's controller: a child of Apple's overlay controller; Apple's adopted containers are ITS children
static DMCCPHostView *gCCPHost;        // its view: full screen, on top of Apple's views
static DMCCPPanelView *gCCPPanel;      // the panel
static UIVisualEffectView *gCCPMaterial;
static UIView *gCCPDim;               // our backdrop behind an expanded module (DMCCPMakeDim)
static UIScrollView *gCCPScroll;       // the panel's content: our tiles and Apple's containers (it scrolls only when taller than the room)
static NSMutableDictionary<NSString *, UIView *> *gCCPContainers;              // module identifier -> Apple's container view, adopted
static NSMapTable<UIViewController *, NSString *> *gCCPByVC;                   // container controller -> module identifier (weak keys)
static NSMapTable<NSString *, UIViewController *> *gCCPVCOf;                   // module identifier -> its container controller (weak values)
static NSMutableArray<NSString *> *gCCPOrder;                                  // Apple's order of building them: the user's own
static NSMutableDictionary<NSString *, NSValue *> *gCCPFrames;                 // module identifier or tile ID -> its frame in the content
static NSMutableSet<NSString *> *gCCPHidden;                                   // the stand-ins, hidden at their Mac tile's frame
static NSHashTable<UIGestureRecognizer *> *gCCPBlocking;                       // Apple's modules' blocking gestures (a slider's drag): our swipe waits for them
static NSMutableArray<id<DMCCTile>> *gCCPTiles;
static MSBDCCMetrics gCCPMetrics;      // Apple's module unit and spacing on this iPad, our margin
static CGRect gCCPSensor;              // Apple's sensor indicator in the header while it shows (screen points; empty: none) -- the panel hangs under it
static BOOL gCCPSensorList = NO;       // Apple's list of the apps that used a sensor is open (a tap on the indicator): the panel steps back
static BOOL gCCPSensorDue = NO;        // (looked at in the presentation's first step: the header has its presented layout from then on)
static double gCCPBuildMs = 0;         // our time inside Apple's build (adoption, layout): the perf notes
static NSString *gCCPExpanded;         // the module whose expanded view is open
static id<DMCCTile> gCCPDetailTile; static UIView *gCCPDetail;   // the detail page shown in place of the tiles
static __weak UIScrollView *gCCPDetailScroll; static __weak UIView *gCCPDetailPage;   // (its scroll view and the tile's page in it)
static int gCCPEngine = -1;            // the window engine at the last layout (CCLayout.h kMSBDCCEngine...: Apple's Stage Manager spot)
// Settings' Control Center Size (controlCenterScale: StatusBar.x DMLoadPrefs reads it; CCLayout.h MSBDCCSize: never set 1) and the size the panel
// was laid out at (our tiles read it, CCTiles.h DMCCTSize).
static BOOL gCCPSizeStored = NO; static double gCCPSizeValue = 1.0;
static double gCCPSize = 1.0;
static NSMutableArray<NSString *> *gCCPCheckOptional;           // the optional rows missing here (their parts left out)
// Apple's own values the panel replaced, handed back by DMCCPGiveBack (CCGiveBack.h): the backdrop ours hid (it showed: shown again), each header
// whose status bar alpha ours holds at 0 (Apple's value kept on it, DMCCPAppleBarOf), each adopted container as Apple had it (DMCCPAppleKeep, in
// the order of the moves).
static __weak UIView *gCCPHidBackdrop;
static NSHashTable<UIView *> *gCCPAppleBarHeaders;
@class DMCCPAppleKeep;
static NSMutableArray<DMCCPAppleKeep *> *gCCPAppleKeeps;
static void DMCCPLayout(NSString *why);
static void DMCCPPlace(UIView *cv, CGRect f, double size);
static void DMCCPSensorLook(NSString *why, BOOL animated);
static void DMCCPSetWanted(BOOL want);
static void DMCCPApplyStyle(NSString *why);
static void DMCCPanelCloseDetail(BOOL animated);
static UIView *DMCCPBackdrop(void);

// ---- the API table -------------------------------------------------------------------------------------------------------------------------
// Every method we hook, call or read, with the type encoding read on 15.6.1 (M1, research disassembly + runtime), 16.7.7 (iPad 2, its dyld
// cache read on the Mac, 3 Nov; live on the iPad 2 in P4, the same) and 17.5.1 (the spike, and this build's own check; P4's sensor rows are named
// in 17.5.1's disassembly, their shapes read live on 15.6.1 and 16.7.7 only: elsewhere the part goes in only where they match). 15 keeps
// -willRemove... and -didClose... on the base class CCUIModularControlCenterViewController: class_getInstanceMethod finds them there, and
// MSHookMessageEx hooks them on the overlay class.
static void (*o_DMCCPViewDidLoad)(id, SEL);
static void (*o_DMCCPDidAdd)(id, SEL, id, id);
static void (*o_DMCCPWillRemove)(id, SEL, id, id);
static void (*o_DMCCPWillOpen)(id, SEL, id, id);
static void (*o_DMCCPDidClose)(id, SEL, id, id);
static void (*o_DMCCPDidFinish)(id, SEL, id, id);
static void (*o_DMCCPUpdate)(id, SEL, id, id);
static BOOL (*o_DMCCPTapBegin)(id, SEL, id);
static CGRect (*o_DMCCPCompact)(id, SEL, id);
static void (*o_DMCCPWillPresent)(id, SEL);
static void (*o_DMCCPDidDismiss)(id, SEL);
static id (*o_DMCCPBatch)(id, SEL, id, id);
static void (*o_DMCCPSensorUpdate)(id, SEL);
static void (*o_DMCCPSensorListOpen)(id, SEL);
static void (*o_DMCCPSensorListClose)(id, SEL);
static void (*o_DMCCPHeaderBarAlpha)(id, SEL, double);
static UIView *(*o_DMCCPHeaderHit)(id, SEL, CGPoint, UIEvent *);
static void DMCCPViewDidLoad(id self, SEL _cmd);
static void DMCCPDidAdd(id self, SEL _cmd, id grid, id containerVC);
static void DMCCPWillRemove(id self, SEL _cmd, id grid, id containerVC);
static void DMCCPWillOpen(id self, SEL _cmd, id grid, id module);
static void DMCCPDidClose(id self, SEL _cmd, id grid, id module);
static void DMCCPDidFinish(id self, SEL _cmd, id grid, id module);
static void DMCCPUpdate(id self, SEL _cmd, id state, id completion);
static BOOL DMCCPTapBegin(id self, SEL _cmd, id gr);
static CGRect DMCCPCompact(id self, SEL _cmd, id containerVC);
static void DMCCPWillPresentHook(id self, SEL _cmd);
static void DMCCPGiveBack(NSString *why);
static void DMCCPDidDismissHook(id self, SEL _cmd);
static id DMCCPBatch(id self, SEL _cmd, id state, id previous);
static void DMCCPSensorUpdate(id self, SEL _cmd);
static void DMCCPSensorListOpen(id self, SEL _cmd);
static void DMCCPSensorListClose(id self, SEL _cmd);
static void DMCCPHeaderBarAlpha(id self, SEL _cmd, double a);
static UIView *DMCCPHeaderHit(id self, SEL _cmd, CGPoint p, UIEvent *e);
// A row's part: core rows (all or nothing), or an optional part that is only left out without its rows.
enum { kDMCCPCore = 0, kDMCCPPartJoin, kDMCCPPartSensor, kDMCCPPartSensorList, kDMCCPPartFinish };
typedef struct { const char *cls, *sel, *enc; void *fn; void **orig; int part; const char *what; } DMCCPHookRow;
static DMCCPHookRow kDMCCPHooks[] = {
    { kDMCCPOverlay, "viewDidLoad", "v16@0:8", (void *)DMCCPViewDidLoad, (void **)&o_DMCCPViewDidLoad, kDMCCPCore, "the panel built with Apple's Control Center" },
    { kDMCCPOverlay, "moduleCollectionViewController:didAddModuleContainerViewController:", "v32@0:8@16@24", (void *)DMCCPDidAdd, (void **)&o_DMCCPDidAdd, kDMCCPCore, "a module adopted as Apple builds it" },
    { kDMCCPOverlay, "moduleCollectionViewController:willRemoveModuleContainerViewController:", "v32@0:8@16@24", (void *)DMCCPWillRemove, (void **)&o_DMCCPWillRemove, kDMCCPCore, "a module let go" },
    { kDMCCPOverlay, "moduleCollectionViewController:willOpenExpandedModule:", "v32@0:8@16@24", (void *)DMCCPWillOpen, (void **)&o_DMCCPWillOpen, kDMCCPCore, "an expanded module opens" },
    { kDMCCPOverlay, "moduleCollectionViewController:didCloseExpandedModule:", "v32@0:8@16@24", (void *)DMCCPDidClose, (void **)&o_DMCCPDidClose, kDMCCPCore, "it closed" },
    { kDMCCPOverlay, "moduleCollectionViewController:didFinishInteractionWithModule:", "v32@0:8@16@24", (void *)DMCCPDidFinish, (void **)&o_DMCCPDidFinish, kDMCCPPartFinish, "a module Apple held (a press, its expanded view) goes where the panel laid it out meanwhile" },
    { kDMCCPOverlay, "_updatePresentationForTransitionState:withCompletionHander:", "v32@0:8@16@?24", (void *)DMCCPUpdate, (void **)&o_DMCCPUpdate, kDMCCPCore, "every presentation step" },
    { kDMCCPOverlay, "_dismissalTapGestureRecognizerShouldBegin:", "B24@0:8@16", (void *)DMCCPTapBegin, (void **)&o_DMCCPTapBegin, kDMCCPCore, "a tap in our panel is not outside" },
    { kDMCCPGrid, "compactModeFrameForContentModuleContainerViewController:", kDMCCPRectType "24@0:8@16", (void *)DMCCPCompact, (void **)&o_DMCCPCompact, kDMCCPCore, "expanded views from our tiles" },
    { "SBControlCenterController", "_willPresent", "v16@0:8", (void *)DMCCPWillPresentHook, (void **)&o_DMCCPWillPresent, kDMCCPCore, "Control Center about to show" },
    { "SBControlCenterController", "_didDismiss", "v16@0:8", (void *)DMCCPDidDismissHook, (void **)&o_DMCCPDidDismiss, kDMCCPCore, "Control Center closed" },
    { kDMCCPProvider, "animationBatchForTransitionState:previousTransitionState:", "@32@0:8@16@24", (void *)DMCCPBatch, (void **)&o_DMCCPBatch, kDMCCPPartJoin, "the panel moves in Apple's own spring" },
    { kDMCCPOverlay, "_updateSensorActivityStatusForHeaderPocketView", "v16@0:8", (void *)DMCCPSensorUpdate, (void **)&o_DMCCPSensorUpdate, kDMCCPPartSensor, "the panel makes room for Apple's sensor indicator" },
    { "CCUIHeaderPocketView", "setStatusBarAlpha:", "v24@0:8d16", (void *)DMCCPHeaderBarAlpha, (void **)&o_DMCCPHeaderBarAlpha, kDMCCPPartSensor, "the header's copy of the status icons stays hidden (the panel under the indicator would show it)" },
    { "CCUIHeaderPocketView", "hitTest:withEvent:", "@40@0:8{CGPoint=dd}16@32", (void *)DMCCPHeaderHit, (void **)&o_DMCCPHeaderHit, kDMCCPPartSensor, "a touch over our menu bar is not the sensor indicator's (its touch area reached our Control Center icon)" },
    { kDMCCPOverlay, "willOpenExpandedSensorAttributionViewController", "v16@0:8", (void *)DMCCPSensorListOpen, (void **)&o_DMCCPSensorListOpen, kDMCCPPartSensorList, "the panel steps back for Apple's list of the apps using a sensor" },
    { kDMCCPOverlay, "didCloseExpandedSensorAttributionViewController", "v16@0:8", (void *)DMCCPSensorListClose, (void **)&o_DMCCPSensorListClose, kDMCCPPartSensorList, "the panel back when that list closed" },
};
// The calls (instance methods unless meta) and instance variables ("ivar": any object type, checked by class when read).
typedef struct { const char *cls, *sel, *enc; BOOL meta, optional, ivar; const char *what; } DMCCPNeedRow;
static const DMCCPNeedRow kDMCCPNeeds[] = {
    { kDMCCPOverlay, "_handleDismissalPanGestureRecognizer:", "v24@0:8@16", NO, NO, NO, "a swipe up on the panel dismisses (Apple's own pan dismissal)" },
    { kDMCCPOverlay, "presentationState", NULL, NO, NO, NO, "the swipe only once presented (its type: Q or q)" },
    { kDMCCPOverlay, "_backgroundView", NULL, NO, NO, YES, "Apple's full-screen backdrop (hidden while ours shows)" },
    { kDMCCPGrid, "_layoutOptions", NULL, NO, NO, YES, "Apple's module unit and spacing" },
    { kDMCCPGrid, "moduleViewForIdentifier:", "@24@0:8@16", NO, NO, NO, "a module's container view" },
    { kDMCCPGrid, "moduleCollectionView", "@16@0:8", NO, NO, NO, "Apple's grid view" },
    { kDMCCPGrid, "layoutView:layoutRectForSubview:", "{CCUILayoutRect={CCUILayoutPoint=QQ}{CCUILayoutSize=QQ}}32@0:8@16@24", NO, NO, NO, "Apple's size of a module" },
    { kDMCCPGrid, "bs_presentationContextDefiningViewController", "@16@0:8", NO, NO, NO, "where an expanded view is framed" },
    { kDMCCPContainerVC, "moduleIdentifier", "@16@0:8", NO, NO, NO, "a module's identifier" },
    { kDMCCPContainerVC, "isExpanded", "B16@0:8", NO, NO, NO, "a module expanded" },
    { kDMCCPContainerVC, "topLevelBlockingGestureRecognizers", "@16@0:8", NO, YES, NO, "a swipe on Apple's tiles waits for their own gestures" },
    { kDMCCPContainerVC, "expandModule", "v16@0:8", NO, YES, NO, "our tiles open Apple's expanded views" },
    { kDMCCPContainerView, "moduleIdentifier", "@16@0:8", NO, NO, NO, "a container view's module" },
    { "CCUILayoutOptions", "itemEdgeSize", "d16@0:8", NO, NO, NO, "Apple's module unit" },
    { "CCUILayoutOptions", "itemSpacing", "d16@0:8", NO, NO, NO, "Apple's module spacing" },
    { "CCUIOverlayTransitionState", "presentationProgress", "d16@0:8", NO, NO, NO, "the presentation's progress" },
    { "CCUIOverlayTransitionState", "isInteractive", "B16@0:8", NO, NO, NO, "a finger pull" },
    { "SBControlCenterController", "dismissAnimated:", "v20@0:8B16", NO, NO, NO, "Control Center put away" },
    { "SBControlCenterController", "viewController", "@16@0:8", NO, NO, NO, "Apple's overlay (a style change while running)" },
    { kDMCCPOverlay, "moduleCollectionViewController", "@16@0:8", NO, NO, NO, "Apple's grid (a style change while running)" },
    { kDMCCPProvider, "_baseC2AnimationParametersForTransitionState:", "@24@0:8@16", YES, YES, NO, "Apple's spring for a step" },
    { "CCUIAnimationBatch", "addAnimation:", "v24@0:8@16", NO, YES, NO, "our animation in Apple's batch" },
    { "CCUIAnimation", "animationWithParameters:animations:", "@32@0:8@16@?24", YES, YES, NO, "an animation of Apple's kind" },
    { kDMCCPGrid, "_updateModuleControllers", "v16@0:8", NO, YES, NO, "a module's own size change (Uptime's Module Size) reaches Apple's grid through ours" },
    { kDMCCPGrid, "_settingsManager", NULL, NO, YES, YES, "the user's order now (a reorder in Settings while running)" },
    { "CCUIModuleSettingsManager", "sortModuleIdentifiers:forInterfaceOrientation:", "@32@0:8@16q24", NO, YES, NO, "the user's order now (a reorder in Settings while running)" },
    { "CCUIHeaderPocketView", "statusBarAlpha", "d16@0:8", NO, YES, NO, "the header's own status bar alpha, handed back with iPadOS's look (the room made for the sensor indicator)" },
};
static BOOL gCCPHaveJoin = NO, gCCPHaveExpand = NO, gCCPHaveBlocking = NO, gCCPHaveOrder = NO, gCCPHaveUpdate = NO;   // (the optional parts: all their rows here)
static BOOL gCCPHaveSensor = NO, gCCPHaveSensorList = NO, gCCPHaveFinish = NO;
static BOOL DMCCPHookPartHere(int part) {   // (an optional hook goes in only with all of its part's rows; core rows always)
    return part == kDMCCPCore || (part == kDMCCPPartJoin && gCCPHaveJoin) || (part == kDMCCPPartSensor && gCCPHaveSensor) || (part == kDMCCPPartSensorList && gCCPHaveSensorList) || (part == kDMCCPPartFinish && gCCPHaveFinish);
}
static NSString *DMCCPRowName(const char *cls, const char *sel, BOOL meta, BOOL ivar) { return ivar ? [NSString stringWithFormat:@"%s.%s", cls, sel] : [NSString stringWithFormat:@"%c[%s %s]", meta ? '+' : '-', cls, sel]; }
// One row: nil when it is there as expected, else why not.
static NSString *DMCCPRowProblem(const char *cls, const char *sel, const char *enc, BOOL meta, BOOL ivar) {
    Class c = objc_getClass(cls);
    if (!c) return @"class missing";
    if (ivar) {
        Ivar iv = class_getInstanceVariable(c, sel);
        const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
        if (!t) return @"missing";
        return t[0] == '@' ? nil : [NSString stringWithFormat:@"is %s, not an object", t];
    }
    Method m = meta ? class_getClassMethod(c, sel_registerName(sel)) : class_getInstanceMethod(c, sel_registerName(sel));
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    if (!t) return @"missing";
    if (!enc) return (!strcmp(t, "Q16@0:8") || !strcmp(t, "q16@0:8")) ? nil : [NSString stringWithFormat:@"is %s", t];   // (presentationState: either integer)
    return strcmp(t, enc) ? [NSString stringWithFormat:@"is %s, we use %s", t, enc] : nil;
}
// The whole table: the rows that fail (core: nothing is hooked then); optionalMissing gets the optional ones that do.
// debug /tmp/msb-ccp-simulate-missing: one core row pretends to be missing (the all-or-nothing path, Settings' greyed row).
static NSArray<NSString *> *DMCCPCheckAPI(NSMutableArray<NSString *> *optionalMissing, NSUInteger *checked) {
    NSMutableArray *bad = [NSMutableArray array];
    BOOL join = YES, expand = YES, blocking = YES, order = YES, update = YES, sensor = YES, sensorList = YES, finish = YES;
    NSUInteger n = 0;
    for (size_t i = 0; i < sizeof(kDMCCPHooks) / sizeof(kDMCCPHooks[0]); i++) {
        n++;
        NSString *p = DMCCPRowProblem(kDMCCPHooks[i].cls, kDMCCPHooks[i].sel, kDMCCPHooks[i].enc, NO, NO);
        if (!p) continue;
        NSString *line = [NSString stringWithFormat:@"%@ %@ (%s)", DMCCPRowName(kDMCCPHooks[i].cls, kDMCCPHooks[i].sel, NO, NO), p, kDMCCPHooks[i].what];
        int part = kDMCCPHooks[i].part;
        if (part == kDMCCPCore) { [bad addObject:line]; continue; }
        [optionalMissing addObject:line];
        if (part == kDMCCPPartJoin) join = NO; else if (part == kDMCCPPartSensor) sensor = NO; else if (part == kDMCCPPartFinish) finish = NO; else sensorList = NO;
    }
    for (size_t i = 0; i < sizeof(kDMCCPNeeds) / sizeof(kDMCCPNeeds[0]); i++) {
        const DMCCPNeedRow *r = &kDMCCPNeeds[i];
        n++;
        NSString *p = DMCCPRowProblem(r->cls, r->sel, r->enc, r->meta, r->ivar);
        if (!p) continue;
        NSString *line = [NSString stringWithFormat:@"%@ %@ (%s)", DMCCPRowName(r->cls, r->sel, r->meta, r->ivar), p, r->what];
        if (!r->optional) { [bad addObject:line]; continue; }
        [optionalMissing addObject:line];
        if (!strcmp(r->sel, "expandModule")) expand = NO;
        else if (!strcmp(r->sel, "topLevelBlockingGestureRecognizers")) blocking = NO;
        else if (!strcmp(r->sel, "_settingsManager") || !strcmp(r->sel, "sortModuleIdentifiers:forInterfaceOrientation:")) order = NO;
        else if (!strcmp(r->sel, "_updateModuleControllers")) update = NO;
        else if (!strcmp(r->sel, "statusBarAlpha")) sensor = NO;   // (the header's copy is held at 0 only where Apple's own value can be handed back)
        else join = NO;
    }
#if DEBUG
    if (DMTestFlag("/tmp/msb-ccp-simulate-missing")) [bad addObject:@"-[CCUIModularControlCenterOverlayViewController viewDidLoad] missing (SIMULATED, debug)"];
#endif
    gCCPHaveJoin = join; gCCPHaveExpand = expand; gCCPHaveBlocking = blocking; gCCPHaveOrder = order; gCCPHaveUpdate = update;
    gCCPHaveSensor = sensor; gCCPHaveSensorList = sensorList && sensor;   // (the list's step back goes with the room made for the indicator)
    gCCPHaveFinish = finish;
    if (checked) *checked = n;
    return bad;
}
// The verdict for Settings and Report a Problem (CCMacCheck.h), written only when it changed.
static void DMCCPPublishVerdict(BOOL ok, NSString *reason, NSArray *details, NSArray *optional) {
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    v[@"build"] = MSBDOSBuild() ?: @"";
    v[@"os"] = [[NSProcessInfo processInfo] operatingSystemVersionString] ?: @"";
    v[@"ok"] = @(ok);
    if (reason) v[@"reason"] = reason;
    if (details.count) v[@"details"] = details.count > 16 ? [details subarrayWithRange:NSMakeRange(0, 16)] : details;
    if (optional.count) v[@"optional"] = optional.count > 8 ? [optional subarrayWithRange:NSMakeRange(0, 8)] : optional;
    id cur = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_CC_CHECK_KEY, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if ([cur isEqual:v]) return;
    CFPreferencesSetValue(MSBD_CC_CHECK_KEY, (__bridge CFPropertyListRef)v, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static NSString *DMCCPOSLabel(void) {   // ("iPadOS 17.5.1 (21F90)": the verdict's words)
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    return [NSString stringWithFormat:@"iPadOS %ld.%ld.%ld (%@)", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion, MSBDOSBuild() ?: @"?"];
}
// The hooks, all or nothing (the optional one only with its rows), tried once: a second try would hook again the rows that went in, and their
// originals would then be our own functions (a loop). One that did not go in: the panel stays off this run (the rows that went in only pass
// through: gCCPOn stays NO) and the verdict says so. Called on the main thread: at the start, or when Mac is chosen while running.
static BOOL DMCCPInstallHooks(void) {
    static BOOL tried = NO;
    if (gCCPHooked) return YES;
    if (!gCCPSupported || tried) return NO;
    tried = YES;
    int count = 0;
    for (size_t i = 0; i < sizeof(kDMCCPHooks) / sizeof(kDMCCPHooks[0]); i++) {
        if (!DMCCPHookPartHere(kDMCCPHooks[i].part)) continue;
        MSHookMessageEx(objc_getClass(kDMCCPHooks[i].cls), sel_registerName(kDMCCPHooks[i].sel), (IMP)kDMCCPHooks[i].fn, (IMP *)kDMCCPHooks[i].orig);
        count++;
    }
    for (size_t i = 0; i < sizeof(kDMCCPHooks) / sizeof(kDMCCPHooks[0]); i++) {   // (each went in: its original kept)
        if (!DMCCPHookPartHere(kDMCCPHooks[i].part)) continue;
        if (*kDMCCPHooks[i].orig) continue;
        NSString *line = [NSString stringWithFormat:@"-[%s %s] did not take our hook (%s)", kDMCCPHooks[i].cls, kDMCCPHooks[i].sel, kDMCCPHooks[i].what];
        DMLog([NSString stringWithFormat:@"[ccpanel] the hook on -[%s %s] did not go in: the panel stays off", kDMCCPHooks[i].cls, kDMCCPHooks[i].sel]);
        gCCPSupported = NO;
        DMCCPPublishVerdict(NO, [NSString stringWithFormat:@"%@: a system method our Control Center uses did not take its hook", DMCCPOSLabel()], @[line], gCCPCheckOptional);
        return NO;
    }
    gCCPHooked = YES;
    DMLog([NSString stringWithFormat:@"[ccpanel] hooks in (%d; Apple's spring %@; room for the sensor indicator %d, its list %d)", count, gCCPHaveJoin ? @"joined" : @"not here: our own", gCCPHaveSensor, gCCPHaveSensorList]);
    return YES;
}

// ---- small readers -------------------------------------------------------------------------------------------------------------------------
static NSString *DMCCPModuleID(id obj) {   // (a container controller's or a container view's module identifier; checked by the table)
    id m = obj && DMCCTypes(obj, @"moduleIdentifier", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(obj, @selector(moduleIdentifier)) : nil;
    return [m isKindOfClass:[NSString class]] ? m : nil;
}
static id DMCCPIvarObject(id obj, const char *name) {   // (an object ivar the table found, read once at a build or a layout -- never per frame)
    Ivar iv = obj ? class_getInstanceVariable(object_getClass(obj), name) : NULL;
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    return t && t[0] == '@' ? object_getIvar(obj, iv) : nil;
}
// The user's order now: Apple's own sort (its settings manager's, the one its grid is packed with; DMCCMeasureApple asks it the same way). The
// modules come in that order when Apple builds them, but a reorder in Settings while running moves no container (Apple only packs its grid
// again): sorted at each layout and each presentation. YES when ours changed; nothing changes unless Apple answers the same modules.
static BOOL DMCCPSyncOrder(void) {
    if (!gCCPHaveOrder || gCCPOrder.count < 2) return NO;
    id sm = DMCCIvarOf(gCCPGrid, "_settingsManager", "@\"CCUIModuleSettingsManager\"");
    if (!sm || !DMCCTypes(sm, @"sortModuleIdentifiers:forInterfaceOrientation:", "@32@0:8@16q24")) return NO;
    NSArray *sorted = ((id (*)(id, SEL, id, long long))objc_msgSend)(sm, NSSelectorFromString(@"sortModuleIdentifiers:forInterfaceOrientation:"), [gCCPOrder copy], (long long)UIInterfaceOrientationPortrait);
    if (![sorted isKindOfClass:[NSArray class]] || sorted.count != gCCPOrder.count || [sorted isEqualToArray:gCCPOrder]) return NO;
    if (![[NSSet setWithArray:sorted] isEqualToSet:[NSSet setWithArray:gCCPOrder]]) return NO;
    [gCCPOrder setArray:sorted];
    return YES;
}
static UIView *DMCCPBackdrop(void) {   // (Apple's full-screen material behind its modules)
    id v = DMCCPIvarObject(gCCPOverlay, "_backgroundView");
    return [v isKindOfClass:[UIView class]] ? v : nil;
}
// Apple's backdrop while our panel shows: hidden (nothing of it drawn). Shown again, hidden or transparent before, Apple's material did not draw
// behind an expanded module (17.5.1, p01-p03: unhidden at alpha 1 with its weighting 1, still nothing), so our own backdrop takes that part
// (DMCCPMakeDim). Apple's comes back with iPadOS's look (DMCCPGiveBack): shown again if ours hid it. Its alpha is never ours: Apple's
// presentation sets it (the iPad's backdrop takes its weighting as its alpha, -backdropViewShouldUseAlphaTransformer).
static void DMCCPBackdropAway(void) {
    UIView *back = DMCCPBackdrop();
    if (back && !back.hidden) { back.hidden = YES; gCCPHidBackdrop = back; }
}
static BOOL DMCCPExpandedNow(UIViewController *vc) { return vc && DMCCTypes(vc, @"isExpanded", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(vc, @selector(isExpanded)); }
// Which adopted module an expansion is (Apple hands over the module itself, not its container: no identifier on it on 17.5.1): its own, else the
// adopted container that is expanded, else "?" (it still counts as one open).
static NSString *DMCCPExpandedID(id module) {
    NSString *mid = DMCCPModuleID(module);
    if (mid) return mid;
    for (NSString *m in gCCPOrder) if (DMCCPExpandedNow([gCCPVCOf objectForKey:m])) return m;
    return @"?";
}
static double DMCCPProgress(id state) {
    return state && DMCCTypes(state, @"presentationProgress", "d16@0:8") ? ((double (*)(id, SEL))objc_msgSend)(state, NSSelectorFromString(@"presentationProgress")) : 1.0;
}
static BOOL DMCCPInteractive(id state) { return state && DMCCTypes(state, @"isInteractive", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(state, NSSelectorFromString(@"isInteractive")); }
static long long DMCCPPresentationState(void) {   // (Apple's own: 0 closed and 3 going away take no dismissal tap, -_dismissalTapGestureRecognizerShouldBegin:)
    UIViewController *ov = gCCPOverlay;
    SEL s = NSSelectorFromString(@"presentationState");
    if (!ov || !(DMCCTypes(ov, @"presentationState", "Q16@0:8") || DMCCTypes(ov, @"presentationState", "q16@0:8"))) return -1;
    return ((long long (*)(id, SEL))objc_msgSend)(ov, s);
}
static BOOL DMCCPLockedNow(void) { return DMLockUp(DMSBManager("SBLockScreenManager")); }
static BOOL DMCCPRTL(void) { return [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft; }   // (the bar is mirrored then)
// Apple's grid size of one module (units), as its own layout places it: its active position provider's rect (CCSupport's sizes included).
static BOOL DMCCPAppleSize(NSString *mid, int *w, int *h) {
    UIViewController *g = gCCPGrid;
    UIView *cv = gCCPContainers[mid];
    SEL lr = NSSelectorFromString(@"layoutView:layoutRectForSubview:");
    UIView *grid = g ? DMCCGet(g, @"moduleCollectionView") : nil;
    if (!g || !cv || !grid || !DMCCTypes(g, @"layoutView:layoutRectForSubview:", "{CCUILayoutRect={CCUILayoutPoint=QQ}{CCUILayoutSize=QQ}}32@0:8@16@24")) return NO;
    DMCCLayoutRect r = ((DMCCLayoutRect (*)(id, SEL, id, id))objc_msgSend)(g, lr, grid, cv);
    if (r.w < 1 || r.h < 1 || r.w > kMSBDCCCols || r.h > 4) return NO;   // (not placed by Apple yet: told again at the settle pass)
    *w = (int)r.w; *h = (int)r.h;
    return YES;
}
// Apple's module unit and spacing (CCUILayoutOptions, the grid's): an adopted tile keeps Apple's size, our grid takes its pitch.
static BOOL DMCCPReadMetrics(void) {
    id o = DMCCPIvarObject(gCCPGrid, "_layoutOptions");
    if (!o || !DMCCTypes(o, @"itemEdgeSize", "d16@0:8") || !DMCCTypes(o, @"itemSpacing", "d16@0:8")) return NO;
    MSBDCCMetrics m = { ((double (*)(id, SEL))objc_msgSend)(o, NSSelectorFromString(@"itemEdgeSize")), ((double (*)(id, SEL))objc_msgSend)(o, NSSelectorFromString(@"itemSpacing")), kMSBDCCPad };
    if (!MSBDCCMetricsSane(m)) return NO;
    gCCPMetrics = m;
    return YES;
}
static CGFloat DMCCPScale(void) { return MSBDMenuBarSizeScale(gDMBarSize); }
// Apple's sensor indicator in Control Center's header (the camera, the microphone or the location in use: a pill right under the status bar, over the
// status icons -- where the panel hangs; P4, it lay under the panel): 16 / 17 the header's compact attribution control while the header
// -isDisplayingSensorStatus, at the frame the header gives it (-compactModeFrameForSensorView); 15 its -sensorStatusView (CCUISensorStatusView,
// -isDisplayingSensorStatus). Read while Control Center is closed, the header's layout is its dismissed one (the indicator 5 pt lower, 16.7.7):
// the presentation's first step reads it again (DMCCPUpdate). In the overlay's space -- the screen's --, worked out from the layers' positions and
// bounds up to the overlay's view (not frames: Apple's presentation moves the header with a transform). Empty when none shows or it cannot be read.
static CGPoint DMCCPOriginIn(UIView *v, UIView *top) {   // (where v's bounds origin lies in top, without the transforms on the way)
    CGPoint o = CGPointZero;
    for (UIView *x = v; x && x != top; x = x.superview) {
        CALayer *l = x.layer;
        o.x += l.position.x - l.anchorPoint.x * l.bounds.size.width - (x.superview ? x.superview.bounds.origin.x : 0);
        o.y += l.position.y - l.anchorPoint.y * l.bounds.size.height - (x.superview ? x.superview.bounds.origin.y : 0);
    }
    return o;
}
static CGRect DMCCPSensorNow(BOOL layOut) {
    UIView *ov = gCCPOverlay.viewIfLoaded, *hp = DMCCPIvarObject(gCCPOverlay, "_headerPocketView");
    if (!ov || ![hp isKindOfClass:[UIView class]] || ![hp isDescendantOfView:ov]) return CGRectZero;
    if (layOut) [hp layoutIfNeeded];   // (just after Apple changed it: the header places it at its next layout -- now)
    SEL disp = NSSelectorFromString(@"isDisplayingSensorStatus");
    CGRect r = CGRectZero;
    if (DMCCTypes(hp, @"sensorStatusView", "@16@0:8")) {   // (15)
        UIView *sv = DMCCGet(hp, @"sensorStatusView");
        if (![sv isKindOfClass:[UIView class]] || sv.hidden || ![sv isDescendantOfView:hp] || !DMCCTypes(sv, @"isDisplayingSensorStatus", "B16@0:8") || !((BOOL (*)(id, SEL))objc_msgSend)(sv, disp)) return CGRectZero;
        CGPoint o = DMCCPOriginIn(sv, ov);
        r = CGRectMake(o.x, o.y, sv.bounds.size.width, sv.bounds.size.height);
    } else {   // (16, 17)
        UIView *sv = DMCCPIvarObject(hp, "_compactSensorAttributionControl");
        if (![sv isKindOfClass:[UIView class]] || sv.hidden || !DMCCTypes(hp, @"isDisplayingSensorStatus", "B16@0:8") || !((BOOL (*)(id, SEL))objc_msgSend)(hp, disp)) return CGRectZero;
        if (DMCCTypes(hp, @"compactModeFrameForSensorView", kDMCCPRectType "16@0:8")) {   // (in the header's space)
            CGRect c = ((CGRect (*)(id, SEL))objc_msgSend)(hp, NSSelectorFromString(@"compactModeFrameForSensorView"));
            CGPoint o = DMCCPOriginIn(hp, ov);
            r = CGRectMake(o.x + c.origin.x - hp.bounds.origin.x, o.y + c.origin.y - hp.bounds.origin.y, c.size.width, c.size.height);
        } else if ([sv isDescendantOfView:hp]) {   // (else where the control lies, through the layers as on 15)
            CGPoint o = DMCCPOriginIn(sv, ov);
            r = CGRectMake(o.x, o.y, sv.bounds.size.width, sv.bounds.size.height);
        }
    }
    return isfinite(r.origin.x) && isfinite(r.origin.y) && r.size.width >= 1 && r.size.height >= 1 ? r : CGRectZero;
}
// Control Center's header shows its own copy of the status icons right under the bar (Apple's presented look: a row under its sensor indicator).
// Under our panel that row is covered -- until the panel moves down under the indicator, where it peeked out between the two (16.7.7, P4). Our
// menu bar shows the icons, so the header's copy stays at alpha 0 while the panel is Control Center: the header's -setStatusBarAlpha: (its
// -_updateAlpha then gives the copy that alpha) gets 0 from us, at each presentation's start (DMCCPHeaderBarAway) and whenever Apple sets it
// meanwhile (the hook below), as keepbar keeps Control Center's UIStatusBar copies at 0. On the iPad Apple sets it ONCE, in -[CCUIHeaderPocketView
// initWithFrame:] (1.0; only the iPhone's slide-up provider animates it with its progress: 15.6.1's code), so nothing of Apple's ever sets it
// again: Apple's value -- read before ours first goes in, or the one Apple asked for since -- is kept on the header and handed back with
// iPadOS's look (DMCCPGiveBack; without it iPadOS's status icons row stayed hidden until the next respring, 1.8.0 regression F1).
static char kDMCCPAppleBarKey;
static MSBDCCApple DMCCPAppleBarOf(UIView *hp) {   // (Apple's status bar alpha kept on this header, CCGiveBack.h)
    MSBDCCApple k = { 0, 0.0 };
    NSValue *v = hp ? objc_getAssociatedObject(hp, &kDMCCPAppleBarKey) : nil;
    if ([v isKindOfClass:[NSValue class]]) [v getValue:&k size:sizeof k];
    return k;
}
static void DMCCPAppleBarSet(UIView *hp, MSBDCCApple k) {
    if (!hp) return;
    objc_setAssociatedObject(hp, &kDMCCPAppleBarKey, k.kept ? [NSValue valueWithBytes:&k objCType:@encode(MSBDCCApple)] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!gCCPAppleBarHeaders) gCCPAppleBarHeaders = [NSHashTable weakObjectsHashTable];
    if (k.kept) [gCCPAppleBarHeaders addObject:hp]; else [gCCPAppleBarHeaders removeObject:hp];
}
static void DMCCPHeaderBarAlpha(id self, SEL _cmd, double a) {
    BOOL ours = gCCPOn && ((UIView *)gCCPHost).superview;   // (our host: the view below)
    MSBDCCApple k = DMCCPAppleBarOf(self);
    if (ours || k.kept) { MSBDCCKeepAsked(&k, a); DMCCPAppleBarSet(self, k); }   // (what Apple asks for is Apple's: the value handed back)
    o_DMCCPHeaderBarAlpha(self, _cmd, ours ? 0.0 : a);
}
// Apple's header gives its sensor indicator a touch area 20 pt beyond its frame on every side (its -hitTest:withEvent:; 16.7.7's x 803 to 883 for
// the pill, 18.5's code the same) and lays it out under its own, lower status bar: over our taller menu bar that area took the tap on our Control
// Center icon, which opened Apple's list of the apps instead of closing Control Center (1.8.0 regression iPad 2, finding 3; 1.8.1 item 12). While
// the panel shows, a touch over our bar is the header's own (a tap outside it, as without the indicator); a touch on the indicator itself below the
// bar stays the indicator's. The indicator: 15's -sensorStatusView, 16 / 17's compact attribution control (DMCCPSensorNow's reads).
static UIView *DMCCPHeaderHit(id self, SEL _cmd, CGPoint p, UIEvent *e) {
    UIView *r = o_DMCCPHeaderHit(self, _cmd, p, e);
    if (!r || r == self || !gCCPOn || !((UIView *)gCCPHost).superview) return r;
    UIView *sv = DMCCTypes(self, @"sensorStatusView", "@16@0:8") ? DMCCGet(self, @"sensorStatusView") : DMCCPIvarObject(self, "_compactSensorAttributionControl");
    if (![sv isKindOfClass:[UIView class]] || ![r isDescendantOfView:sv]) return r;
    UIView *top = gCCPOverlay.viewIfLoaded;   // (the overlay's space: the screen's, where our bar's height counts from its top)
    return MSBDCCOverOurBar([(UIView *)self convertPoint:p toView:top].y, DMMenuBarHeight()) ? self : r;
}
static void DMCCPHeaderBarAway(void) {   // (at once, before Apple's next step: Apple's own setter, so the hook above never takes our 0 for Apple's)
    UIView *hp = DMCCPIvarObject(gCCPOverlay, "_headerPocketView");
    if (!gCCPHaveSensor || !o_DMCCPHeaderBarAlpha || ![hp isKindOfClass:[UIView class]] || !DMCCTypes(hp, @"statusBarAlpha", "d16@0:8")) return;
    MSBDCCApple k = DMCCPAppleBarOf(hp);
    if (!k.kept) {   // (Apple's own value now -- once kept, what the header has is ours)
        MSBDCCKeepBefore(&k, ((double (*)(id, SEL))objc_msgSend)(hp, NSSelectorFromString(@"statusBarAlpha")));
        DMCCPAppleBarSet(hp, k);
    }
    o_DMCCPHeaderBarAlpha(hp, NSSelectorFromString(@"setStatusBarAlpha:"), 0.0);
}
// The panel's frame for a width and a content height: under our bar at the screen's side (CCLayout.h), below Apple's sensor indicator while that
// shows over the panel's column.
static CGRect DMCCPFrame(CGFloat width, CGFloat contentH) {
    CGRect s = gCCPSensor; CGSize screen = ((UIView *)gCCPHost).bounds.size;   // (the host: full screen, below)
    return MSBDCCPanelFrameUnder(screen.width, screen.height, DMMenuBarHeight(), width, contentH, DMCCPRTL(), s.origin.x, s.origin.y, s.size.width, s.size.height);
}

// ---- our views -----------------------------------------------------------------------------------------------------------------------------
// The panel's controller: Apple's container controllers become ITS children while their views are in its view (rule 1). Appearance stays
// Apple's: its grid forwards it to its modules by hand from its own table (-childViewControllersForAppearancePropagation), so this one forwards
// nothing.
// It is the overlay's last child (DMCCPEnsurePanel adds it after Apple's grid), and modules made for Apple's Control Center take that child for
// Apple's grid: Uptime's Module Size control saves the size, then sends Apple's -_updateModuleControllers, unchecked, to its expanded view's
// presentingViewController.childViewControllers.lastObject (Apple's overlay's), so Apple's grid reads the modules' sizes again (CCSupport's
// runtime ones). Ours did not answer it: "unrecognized selector", SpringBoard aborted, twice in a row, Safe Mode (M1 15.6.1, 1.8.2;
// plans/v1821-uptime.md). So it answers there as Apple's grid: that call goes on to Apple's grid and the panel is laid out at Apple's new sizes
// (the tile's new size at once, as on stock), and a call only Apple's grid answers goes to it (one no one answers still raises).
@interface DMCCPPanelController : UIViewController
@end
@implementation DMCCPPanelController
- (BOOL)shouldAutomaticallyForwardAppearanceMethods { return NO; }
- (void)_updateModuleControllers {
    UIViewController *g = gCCPGrid;
    BOOL apple = gCCPHaveUpdate && g && DMCCTypes(g, @"_updateModuleControllers", "v16@0:8");
    if (apple) ((void (*)(id, SEL))objc_msgSend)(g, _cmd);
    DMLog([NSString stringWithFormat:@"[ccpanel] a module asked for Apple's grid's update (-_updateModuleControllers): %@", apple ? @"passed on to it" : @"not on this iPadOS"]);
    DMCCPLayout(@"a module's size changed");   // (an expanded module's own place too: Apple's close goes to its new frame, DMCCPCompact)
}
- (id)forwardingTargetForSelector:(SEL)s {
    // (only Apple's grid's own questions and actions: a setter of its (-setDelegate:, -setModuleCollectionView: ...) sent to us by a module that took us for
    //  the grid would rewire Apple's grid quietly, so it raises as before. Code review 1.8.2.1, 1)
    UIViewController *g = gCCPGrid;
    return g && ![NSStringFromSelector(s) hasPrefix:@"set"] && [g respondsToSelector:s] ? g : [super forwardingTargetForSelector:s];
}
@end
// The host: full screen on top of Apple's views. A touch outside the panel is not ours (Apple's grid and header take it: a tap outside, a swipe
// up). With Apple's backdrop hidden, a fully transparent SpringBoard region over an app sent the touch to the app (and the tap did not close
// Control Center): its layer is hit-tested as opaque, which routes the touch here -- the render server goes by that, not by a fill (the 2 % tint
// our menus use cost every opening 3-4 long frames on iPadOS 18, P5 spike, 3 Nov; no fill on 15-17 too: DMCCPMakeViews). While one of Apple's
// modules is expanded, nothing of the panel takes a touch (the expanded view and Apple's dismissal have them).
@interface DMCCPHostView : UIView
@end
@implementation DMCCPHostView {
    CGSize _laidFor;
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (gCCPExpanded) return nil;
    UIView *hit = [super hitTest:p withEvent:e];
    return hit == self ? nil : hit;
}
- (void)layoutSubviews {   // (a turn, the overlay's first size: the panel laid out again; nothing when the size did not change)
    [super layoutSubviews];
    if (CGSizeEqualToSize(self.bounds.size, _laidFor)) return;
    _laidFor = self.bounds.size;
    DMCCPLayout(@"its screen's size");
    if (gCCPHaveSensor && gCCPShown) dispatch_async(dispatch_get_main_queue(), ^{ DMCCPSensorLook(@"its screen's size", NO); });   // (Apple's indicator's place after the turn)
}
@end
// The panel: our material, the scrolling content (our tiles, Apple's adopted containers), the detail page when one is open, and the swipe up
// that hands over to Apple's own dismissal pan (-_handleDismissalPanGestureRecognizer: with our recognizer: Apple's handler reads only its state,
// translation and velocity, 15.6.1). Like Apple's own dismissal pans it waits for the modules' own blocking gestures (a slider's drag stays the
// slider's: -topLevelBlockingGestureRecognizers, as Apple's -_setupPanGestureFailureRequirements uses them) and only starts once Control Center is
// presented, upwards.
@interface DMCCPPanelView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIPanGestureRecognizer *swipe;
@end
static void DMCCPanelDismiss(void);
@implementation DMCCPPanelView
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.accessibilityIdentifier = @"MSBDControlCenterPanel";
        self.layer.shadowColor = [[UIColor blackColor] CGColor];
        self.layer.shadowOpacity = 0.25; self.layer.shadowRadius = 18.0; self.layer.shadowOffset = CGSizeMake(0, 8);
        _swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_swipe:)];
        _swipe.maximumNumberOfTouches = 1; _swipe.delegate = self;
        [self addGestureRecognizer:_swipe];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    gCCPMaterial.frame = b;
    if (gCCPScroll.superview == self) gCCPScroll.frame = b;
    if (gCCPDetail.superview == self) DMCCPPlace(gCCPDetail, b, gCCPSize);   // (an open page: laid out at size 1, drawn at the panel's size)
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:gCCPMaterial.layer.cornerRadius].CGPath;
}
- (BOOL)accessibilityPerformEscape {   // (VoiceOver's escape: a detail page goes back, else Control Center closes -- as Esc does)
    if (gCCPDetail) DMCCPanelCloseDetail(YES);
    else DMCCPanelDismiss();
    return YES;
}
- (void)dm_swipe:(UIPanGestureRecognizer *)g {
    UIViewController *ov = gCCPOverlay;
    if (!ov || !DMCCTypes(ov, @"_handleDismissalPanGestureRecognizer:", "v24@0:8@16")) return;
    if (g.state == UIGestureRecognizerStateBegan) DMLog(@"[ccpanel] a swipe up on the panel: handed to Apple's dismissal");
    ((void (*)(id, SEL, id))objc_msgSend)(ov, NSSelectorFromString(@"_handleDismissalPanGestureRecognizer:"), g);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (g != _swipe) return YES;
    if (gCCPDetail || gCCPExpanded) return NO;   // (a detail page keeps its own touches; an expanded module is Apple's)
    long long st = DMCCPPresentationState();
    if (st == 0 || st == 3 || st < 0) return NO;   // (as Apple's own dismissal tap: not closed, not already going away)
    CGPoint v = [_swipe velocityInView:self];
    return v.y < 0 && fabs(v.y) > fabs(v.x);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    if (g != _swipe) return NO;
    if ([gCCPBlocking containsObject:other]) return YES;   // (Apple's modules' own: a slider drag)
    return other == gCCPScroll.panGestureRecognizer && gCCPScroll.scrollEnabled;   // (a panel taller than the room scrolls first)
}
@end

// The panel's content. When it scrolls (taller than the room), its pan waits for the modules' own blocking gestures (a slider's drag stays the
// slider's), as Apple's own Control Center scroll view does (-_setupPanGestureFailureRequirements). (The scroll view is its pan's delegate.)
@interface DMCCPScrollView : UIScrollView
@end
@implementation DMCCPScrollView
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    if (g == self.panGestureRecognizer && [gCCPBlocking containsObject:other]) return YES;
    if (![UIScrollView instancesRespondToSelector:_cmd]) return NO;
    struct objc_super sup = { self, [UIScrollView class] };
    return ((BOOL (*)(struct objc_super *, SEL, id, id))objc_msgSendSuper)(&sup, _cmd, g, other);
}
@end

// ---- placeholders (until P3's Mac tiles) ---------------------------------------------------------------------------------------------------
// An empty Mac-style tile: a rounded platter, a symbol and a title. A tap opens the Apple module it stands for, expanded, out of this tile (the
// module's container is adopted and hidden at this tile's frame): nothing is lost meanwhile.
@interface DMCCPPlaceholderTile : NSObject <DMCCTile>
- (instancetype)initWithRole:(int)role tileID:(NSString *)tid title:(NSString *)title symbol:(NSString *)symbol module:(NSString *)mid;
@end
static BOOL DMCCPanelExpandModule(NSString *mid);
static void DMCCPanelOpenDetail(id<DMCCTile> tile);
static void DMCC18PageOpen(id<DMCCTile> tile);   // (iPadOS 18: CC18Tiles.h)
@implementation DMCCPPlaceholderTile {
    int _role; NSString *_id, *_title, *_symbol, *_module;
    UIView *_view; UIImageView *_icon; UILabel *_label;
}
- (instancetype)initWithRole:(int)role tileID:(NSString *)tid title:(NSString *)title symbol:(NSString *)symbol module:(NSString *)mid {
    if ((self = [super init])) { _role = role; _id = tid; _title = title; _symbol = symbol; _module = mid; }
    return self;
}
- (int)tileRole { return _role; }
- (NSString *)tileID { return _id; }
- (UIView *)tileView {
    if (_view) return _view;
    _view = [UIView new];
    _view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.10] : [UIColor colorWithWhite:0.0 alpha:0.05];
    }];
    _view.layer.cornerCurve = kCACornerCurveContinuous;
    _icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:_symbol]];
    _icon.tintColor = [UIColor labelColor]; _icon.contentMode = UIViewContentModeScaleAspectFit;
    _label = [UILabel new]; _label.text = _title; _label.textColor = [UIColor labelColor]; _label.textAlignment = NSTextAlignmentLeft;
    [_view addSubview:_icon]; [_view addSubview:_label];
    _view.isAccessibilityElement = YES; _view.accessibilityLabel = _title; _view.accessibilityTraits = UIAccessibilityTraitButton;
    _view.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;   // (our content stays English, left to right: our menus' rule)
    UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_tapped:)];
    [_view addGestureRecognizer:t];
    return _view;
}
- (void)tileLayoutInBounds:(CGRect)b scale:(CGFloat)scale {   // (at the panel's size, gCCPSize, as the Mac tiles)
    CGFloat z = gCCPSize > 0.0 && gCCPSize <= 1.0 ? gCCPSize : 1.0;
    _view.layer.cornerRadius = MIN(18.0, round(gCCPMetrics.unit * 0.26)) * z;
    CGFloat sym = round(17.0 * scale) * z, pad = 12.0 * z;
    _label.font = [UIFont systemFontOfSize:13.0 * scale * z weight:UIFontWeightSemibold];
    _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:sym weight:UIImageSymbolWeightSemibold];
    _icon.frame = CGRectMake(pad, (b.size.height > 100 ? pad : (b.size.height - sym - 4) / 2.0), sym + 4, sym + 4);
    CGFloat lx = CGRectGetMaxX(_icon.frame) + 8.0;
    _label.frame = CGRectMake(lx, _icon.frame.origin.y, MAX(0, b.size.width - lx - pad), sym + 4);
}
- (void)dm_tapped:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded) return;
    BOOL opened = _module && DMCCPanelExpandModule(_module);
    DMLog([NSString stringWithFormat:@"[ccpanel] placeholder %@ tapped: %@", _id, opened ? [NSString stringWithFormat:@"Apple's %@ opened from it", _module] : @"nothing to open"]);
}
- (UIView *)tileDetailViewForWidth:(CGFloat)width {   // (the detail page's mechanism, for P3: an empty page with its title)
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, width, 120)];
    l.text = _title; l.textAlignment = NSTextAlignmentCenter; l.textColor = [UIColor secondaryLabelColor];
    l.font = [UIFont systemFontOfSize:14.0 * DMCCPScale()];
    return l;
}
- (NSString *)tileDetailTitle { return _title; }
@end
static void DMCCPAddPlaceholders(void) {
    if (gCCPTiles.count >= 4) return;
    BOOL have[MSBDCCRoleTileNowPlaying + 1] = { NO };
    for (id<DMCCTile> t in gCCPTiles) { int r = [t tileRole]; if (r >= 0 && r <= MSBDCCRoleTileNowPlaying) have[r] = YES; }
    if (!have[MSBDCCRoleTileConnectivity]) [gCCPTiles addObject:[[DMCCPPlaceholderTile alloc] initWithRole:MSBDCCRoleTileConnectivity tileID:@"mac.connectivity" title:@"Wi-Fi" symbol:@"wifi" module:@"com.apple.control-center.ConnectivityModule"]];
    if (!have[MSBDCCRoleTileDisplay]) [gCCPTiles addObject:[[DMCCPPlaceholderTile alloc] initWithRole:MSBDCCRoleTileDisplay tileID:@"mac.display" title:@"Display" symbol:@"sun.max.fill" module:@"com.apple.control-center.DisplayModule"]];
    if (!have[MSBDCCRoleTileSound]) [gCCPTiles addObject:[[DMCCPPlaceholderTile alloc] initWithRole:MSBDCCRoleTileSound tileID:@"mac.sound" title:@"Sound" symbol:@"speaker.wave.2.fill" module:@"com.apple.mediaremote.controlcenter.audio"]];
    if (!have[MSBDCCRoleTileNowPlaying]) [gCCPTiles addObject:[[DMCCPPlaceholderTile alloc] initWithRole:MSBDCCRoleTileNowPlaying tileID:@"mac.nowplaying" title:@"Not Playing" symbol:@"play.fill" module:@"com.apple.mediaremote.controlcenter.nowplaying"]];
}
// A tile's own drag (a slider's): one of the panel's blocking gestures -- the swipe up and the content's scroll wait for it, as for Apple's modules.
static void DMCCPanelAddBlocking(UIGestureRecognizer *g) { if (g) { if (!gCCPBlocking) gCCPBlocking = [NSHashTable weakObjectsHashTable]; [gCCPBlocking addObject:g]; } }
// P3's way in: a tile of a role (or of an identifier) replaces the one there (its view moves into the panel; the layout runs once). One without
// an identifier or a view is not taken (the layout keys its frame by the identifier).
__attribute__((unused)) static void DMCCPanelAddTile(id<DMCCTile> tile) {
    NSString *tid = [tile tileID];
    if (![tid isKindOfClass:[NSString class]] || !tid.length || ![[tile tileView] isKindOfClass:[UIView class]]) { DMLog(@"[ccpanel] a tile without an identifier or a view: not added"); return; }
    if (!gCCPTiles) gCCPTiles = [NSMutableArray array];
    for (NSUInteger i = 0; i < gCCPTiles.count; i++) if ([gCCPTiles[i] tileRole] == [tile tileRole] || [[gCCPTiles[i] tileID] isEqual:tid]) { [[gCCPTiles[i] tileView] removeFromSuperview]; [gCCPTiles removeObjectAtIndex:i]; i--; }
    [gCCPTiles addObject:tile];
    if (gCCPScroll) { [gCCPScroll addSubview:[tile tileView]]; DMCCPLayout(@"a tile added"); }
}

// ---- building it ---------------------------------------------------------------------------------------------------------------------------
// Behind one of Apple's modules opened expanded: a backdrop of ours over the whole screen, of Apple's own Control Center material where this
// iPadOS has it (+[CCUIControlCenterMaterialView _controlCenterBackgroundRecipe] for +[MTMaterialView materialViewWithRecipe:]), else a dark blur.
// It lies in our host under the panel: Apple presents expanded views above the overlay's view (a transition view of their own, 17.5.1), so it is
// behind them. Transparent otherwise (nothing drawn).
static UIView *DMCCPMakeDim(void) {
    Class mt = objc_getClass("MTMaterialView"), cc = objc_getClass("CCUIControlCenterMaterialView");
    UIView *v = nil;
    if (mt && cc && DMCCTypes(cc, @"_controlCenterBackgroundRecipe", "q16@0:8") && DMCCTypes(mt, @"materialViewWithRecipe:", "@24@0:8q16")) {
        long long recipe = ((long long (*)(id, SEL))objc_msgSend)((id)cc, NSSelectorFromString(@"_controlCenterBackgroundRecipe"));
        id m = ((id (*)(id, SEL, long long))objc_msgSend)((id)mt, NSSelectorFromString(@"materialViewWithRecipe:"), recipe);
        if ([m isKindOfClass:[UIView class]]) v = m;
    }
    if (!v) v = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    DMLog([NSString stringWithFormat:@"[ccpanel] our backdrop: %@", NSStringFromClass([v class])]);
    v.userInteractionEnabled = NO;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    v.alpha = 0.0;
    return v;
}
static void DMCCPMakeViews(void) {
    if (gCCPVC) return;
    gCCPContainers = [NSMutableDictionary dictionary]; gCCPFrames = [NSMutableDictionary dictionary]; gCCPHidden = [NSMutableSet set];
    gCCPByVC = [NSMapTable weakToStrongObjectsMapTable]; gCCPVCOf = [NSMapTable strongToWeakObjectsMapTable]; gCCPOrder = [NSMutableArray array];
    gCCPBlocking = [NSHashTable weakObjectsHashTable];
    if (!gCCPTiles) gCCPTiles = [NSMutableArray array];
    gCCPVC = [DMCCPPanelController new];
    gCCPHost = [[DMCCPHostView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gCCPHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    gCCPHost.backgroundColor = [UIColor clearColor];   // (no fill: the opaque hit-testing below routes a touch here, DMCCPHostView)
    SEL opaque = NSSelectorFromString(@"setHitTestsAsOpaque:");
    if ([gCCPHost.layer respondsToSelector:opaque]) ((void (*)(id, SEL, BOOL))objc_msgSend)(gCCPHost.layer, opaque, YES);
    gCCPHost.alpha = 0.0;   // (Apple's presentation brings it in: DMCCPBatch / DMCCPUpdate)
    gCCPVC.view = gCCPHost;
    gCCPDim = DMCCPMakeDim();
    gCCPDim.frame = gCCPHost.bounds;
    [gCCPHost addSubview:gCCPDim];
    gCCPPanel = [[DMCCPPanelView alloc] initWithFrame:CGRectMake(0, 0, 345, 200)];
    gCCPMaterial = DMMakeBlur(22.0);   // (our menus' material, rounded as macOS's Control Center)
    gCCPMaterial.userInteractionEnabled = NO;
    [gCCPPanel addSubview:gCCPMaterial];
    gCCPScroll = [DMCCPScrollView new];
    gCCPScroll.backgroundColor = [UIColor clearColor]; gCCPScroll.clipsToBounds = YES; gCCPScroll.layer.cornerRadius = 22.0; gCCPScroll.layer.cornerCurve = kCACornerCurveContinuous;
    gCCPScroll.showsHorizontalScrollIndicator = NO; gCCPScroll.alwaysBounceVertical = NO; gCCPScroll.scrollEnabled = NO;
    gCCPScroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [gCCPPanel addSubview:gCCPScroll];
    [gCCPHost addSubview:gCCPPanel];
    DMCCTMakeTiles();   // (our Mac tiles, CCTiles.h; a role none of them took gets its placeholder)
    DMCCPAddPlaceholders();
    for (id<DMCCTile> t in gCCPTiles) [gCCPScroll addSubview:[t tileView]];
}
// Our controller under Apple's overlay controller, our host on top of its views (made once; joins again if its view was made again).
static void DMCCPEnsurePanel(UIViewController *overlay) {
    if (!overlay || !overlay.isViewLoaded) return;
    DMCCPMakeViews();
    @try {
        if (gCCPVC.parentViewController != overlay) {
            if (gCCPVC.parentViewController) { [gCCPVC willMoveToParentViewController:nil]; [gCCPVC removeFromParentViewController]; }
            [overlay addChildViewController:gCCPVC];
            [overlay.view addSubview:gCCPHost];
            [gCCPVC didMoveToParentViewController:overlay];
        } else if (gCCPHost.superview != overlay.view) [overlay.view addSubview:gCCPHost];
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[ccpanel] our controller could not join %@: %@", NSStringFromClass([overlay class]), e.reason]); }
    gCCPHost.frame = overlay.view.bounds;
    if (overlay.view.subviews.lastObject != gCCPHost) [overlay.view bringSubviewToFront:gCCPHost];
    gCCPOverlay = overlay;
}
// Apple's presented look on an adopted container: a container Apple has presented and put away keeps its dismissal's look as its own values --
// the container view moved toward the status bar (its transform), its inner wrapper transparent -- until Apple's next presentation sets them
// again, and Apple's presentation only walks its own grid: every tile was invisible in our panel after iPadOS's look had shown once and Mac was
// chosen again (17.5.1, p01: the transform and an alpha of 0 read on each container). The views from the container view down to its
// controller's view get what Apple's presentation leaves them at, once Control Center is presented: no transform, opaque. Apple's own values
// are kept (DMCCPAppleKeep) and handed back with iPadOS's look: Apple's next presentation animates from its own dismissal's look, as on stock
// (a presentation without a finger goes to its presented state in one animated step, from what the views have: -presentAnimated:
// withCompletionHandler:'s block, 15.6.1).
// One adopted container as Apple had it, for DMCCPGiveBack: the view it was in and the views before it there (put back in the reverse order of the
// moves, each right after the last of those that is back: Apple's order whole again, CCGiveBack.h MSBDCCPutBackAt), its hidden flag, and each
// transform and alpha DMCCPPresentedLook replaced on its views (Apple's last dismissal's look, or as Apple built them).
@interface DMCCPAppleKeep : NSObject
@property (nonatomic, weak) UIView *cv, *home;
@property (nonatomic, weak) UIViewController *vc;
@property (nonatomic, strong) NSPointerArray *before;   // (weak: Apple's views, and containers ours took later)
@property (nonatomic) BOOL hidden;
@property (nonatomic, strong) NSMapTable<UIView *, NSValue *> *transforms;   // (weak keys: Apple's views)
@property (nonatomic, strong) NSMapTable<UIView *, NSNumber *> *alphas;
@end
@implementation DMCCPAppleKeep
@end
static DMCCPAppleKeep *DMCCPAppleKeepOf(UIView *cv) {
    if (cv) for (DMCCPAppleKeep *k in gCCPAppleKeeps) if (k.cv == cv) return k;
    return nil;
}
static void DMCCPAppleKeepDrop(UIView *cv) { DMCCPAppleKeep *k = DMCCPAppleKeepOf(cv); if (k) [gCCPAppleKeeps removeObjectIdenticalTo:k]; }
static void DMCCPPresentedLook(UIView *cv, UIViewController *containerVC, DMCCPAppleKeep *keep) {
    UIView *inner = containerVC.viewIfLoaded;
    if (!cv || ![inner isDescendantOfView:cv]) return;
    for (UIView *v = inner.superview; v; v = v.superview) {
        if (!CGAffineTransformIsIdentity(v.transform)) {
            if (keep && ![keep.transforms objectForKey:v]) [keep.transforms setObject:[NSValue valueWithCGAffineTransform:v.transform] forKey:v];
            v.transform = CGAffineTransformIdentity;
        }
        if (v.alpha != 1.0) {
            if (keep && ![keep.alphas objectForKey:v]) [keep.alphas setObject:@(v.alpha) forKey:v];
            v.alpha = 1.0;
        }
        if (v == cv) break;
    }
}
// Apple's own transform and alpha on a container's views again, where they are still the ones DMCCPPresentedLook set (else Apple set its own since).
static void DMCCPAppleLookBack(DMCCPAppleKeep *k) {
    for (UIView *v in k.transforms.keyEnumerator.allObjects) if (CGAffineTransformIsIdentity(v.transform)) v.transform = [[k.transforms objectForKey:v] CGAffineTransformValue];
    for (UIView *v in k.alphas.keyEnumerator.allObjects) if (MSBDCCStillOurs(v.alpha, 1.0)) v.alpha = [[k.alphas objectForKey:v] doubleValue];
}
// One of Apple's containers into our panel, with its controller (rule 1), as Apple built it (or, when Mac was chosen while running, as it was).
static void DMCCPAdopt(UIViewController *overlay, UIViewController *grid, UIViewController *containerVC, NSString *why) {
    CFTimeInterval t0 = CACurrentMediaTime();
    NSString *mid = DMCCPModuleID(containerVC);
    UIView *cv = nil;
    if (mid && DMCCTypes(grid, @"moduleViewForIdentifier:", "@24@0:8@16")) {   // (the grid's own table: the same view -compactModeFrame... reads)
        id v = ((id (*)(id, SEL, id))objc_msgSend)(grid, NSSelectorFromString(@"moduleViewForIdentifier:"), mid);
        if ([v isKindOfClass:objc_getClass(kDMCCPContainerView)]) cv = v;
    }
    if (!cv) for (UIView *v = containerVC.viewIfLoaded.superview; v; v = v.superview) if ([v isKindOfClass:objc_getClass(kDMCCPContainerView)]) { cv = v; break; }
    if (!mid || !cv) { DMLog([NSString stringWithFormat:@"[ccpanel] NOT adopted (%@): %@, identifier %@, container view %@ -- it stays in Apple's grid", why, NSStringFromClass([containerVC class]), mid, cv]); return; }
    gCCPGrid = grid;
    DMCCPEnsurePanel(overlay);
    if (!gCCPVC || gCCPVC.parentViewController != overlay) return;
    // Rule 1, the view first and then its controller: UIKit adds a child only under the controller its view is already in (with the controller
    // first, every add threw "child view controller ... should have parent view controller ... but requested parent is ...", 17.5.1 p09). A
    // controller that cannot move takes its view back to Apple's grid, where it was, so the two are never apart (the cc03 abort).
    UIView *home = cv.superview;
    NSArray<UIView *> *before = home.subviews;   // (Apple's views as Apple has them: what the give-back puts this one back after)
    NSUInteger at = home ? [before indexOfObjectIdenticalTo:cv] : NSNotFound;
    BOOL appleHidden = cv.hidden;
    [gCCPScroll insertSubview:cv atIndex:0];   // (under our tiles: a hidden stand-in never covers the tile it stands under)
    @try {
        if (containerVC.parentViewController != gCCPVC) {
            [containerVC willMoveToParentViewController:nil];
            [containerVC removeFromParentViewController];
            [gCCPVC addChildViewController:containerVC];
            [containerVC didMoveToParentViewController:gCCPVC];
        }
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[ccpanel] %@: its controller could not move to ours (%@)", mid, e.reason]); }
    if (containerVC.parentViewController != gCCPVC) {
        if (home) { if (at < home.subviews.count) [home insertSubview:cv atIndex:at]; else [home addSubview:cv]; } else [cv removeFromSuperview];
        if (!containerVC.parentViewController) { @try { [grid addChildViewController:containerVC]; [containerVC didMoveToParentViewController:grid]; } @catch (NSException *e) {} }
        DMLog([NSString stringWithFormat:@"[ccpanel] NOT adopted (%@): %@ stays in Apple's grid (its controller is %@'s)", why, mid, NSStringFromClass([containerVC.parentViewController class])]);
        return;
    }
    UIView *old = gCCPContainers[mid];
    if (old && old != cv) {   // (a new container for a module whose old one Apple did not tell us it removed: the old one out of our panel)
        UIViewController *oldVC = [gCCPVCOf objectForKey:mid];
        if (old.superview == gCCPScroll) [old removeFromSuperview];
        if (oldVC && oldVC != containerVC) {
            if (oldVC.parentViewController == gCCPVC) { [oldVC willMoveToParentViewController:nil]; [oldVC removeFromParentViewController]; }
            [gCCPByVC removeObjectForKey:oldVC];
        }
        DMCCPAppleKeepDrop(old);   // (Apple's grid never gets it back)
        DMLog([NSString stringWithFormat:@"[ccpanel] %@: a new container in place of the old one", mid]);
    }
    // Apple's own, for the give-back: where it was among Apple's views, its hidden flag (a container already ours keeps what its first move kept).
    DMCCPAppleKeep *keep = DMCCPAppleKeepOf(cv);
    if (!keep && home && home != gCCPScroll) {
        keep = [DMCCPAppleKeep new];
        keep.cv = cv; keep.vc = containerVC; keep.home = home; keep.hidden = appleHidden;
        keep.before = [NSPointerArray weakObjectsPointerArray];
        for (NSUInteger i = 0; at != NSNotFound && i < at && i < before.count; i++) [keep.before addPointer:(__bridge void *)before[i]];
        keep.transforms = [NSMapTable weakToStrongObjectsMapTable]; keep.alphas = [NSMapTable weakToStrongObjectsMapTable];
        if (!gCCPAppleKeeps) gCCPAppleKeeps = [NSMutableArray array];
        [gCCPAppleKeeps addObject:keep];
    }
    DMCCPPresentedLook(cv, containerVC, keep);   // (before our layout sets its frame: a frame under a transform is not what it says)
    gCCPContainers[mid] = cv;
    [gCCPByVC setObject:mid forKey:containerVC];
    [gCCPVCOf setObject:containerVC forKey:mid];
    if (![gCCPOrder containsObject:mid]) [gCCPOrder addObject:mid];
    if (gCCPHaveBlocking && DMCCTypes(containerVC, @"topLevelBlockingGestureRecognizers", "@16@0:8")) {
        NSArray *b = ((id (*)(id, SEL))objc_msgSend)(containerVC, NSSelectorFromString(@"topLevelBlockingGestureRecognizers"));
        if ([b isKindOfClass:[NSArray class]]) for (id r in b) if ([r isKindOfClass:[UIGestureRecognizer class]]) [gCCPBlocking addObject:r];
    }
    double ms = (CACurrentMediaTime() - t0) * 1000.0; gCCPBuildMs += ms;
    DMLog([NSString stringWithFormat:@"[ccpanel] adopted %@ (%@, %.2f ms)", mid, why, ms]);
}
// Laid out once Apple's own sizes are current: 0.4 s after the last module Apple built (its position providers are updated after the modules are
// made: at adoption RAM & CPU's CCSupport size was not known yet, spike), and laid out right away while Control Center is hidden, so the first
// pull finds every tile in place.
// One layout after Apple's adds of one pass (it adds every module of a build or a list change in one turn of the main run loop): once, not per
// module.
static void DMCCPLayout(NSString *why);
static BOOL gCCPLayoutSoon = NO;
static void DMCCPLayoutSoon(void) {
    if (gCCPLayoutSoon) return;
    gCCPLayoutSoon = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ gCCPLayoutSoon = NO; DMCCPLayout(@"modules added"); });
}
static unsigned gCCPSettleGen = 0;
static void DMCCPSettleSoon(void) {
    unsigned gen = ++gCCPSettleGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen != gCCPSettleGen || !gCCPOn || !gCCPPanel) return;
        CFTimeInterval t0 = CACurrentMediaTime();
        DMCCPLayout(@"settled");
        BOOL hidden = !gCCPHost.window || gCCPHost.window.hidden;
        if (hidden) { [gCCPHost layoutIfNeeded]; [gCCPPanel layoutIfNeeded]; for (UIView *v in gCCPScroll.subviews) { [v setNeedsLayout]; [v layoutIfNeeded]; } }
        double ms = (CACurrentMediaTime() - t0) * 1000.0; gCCPBuildMs += ms;
        DMLog([NSString stringWithFormat:@"[ccpanel] settled: %lu modules, %lu tiles laid out %@ in %.2f ms (ours in Apple's build %.2f ms in all)", (unsigned long)gCCPContainers.count,
            (unsigned long)gCCPTiles.count, hidden ? @"while hidden" : @"on screen", ms, gCCPBuildMs]);
        // The tiles read their states once now, hidden: the first reads after a start are slow ones (the iPad 2, 16.7.7: Connectivity's 7-8 ms,
        // Bluetooth's alone 2.5-5, the first presentation's 14-16 ms in all, later ones 1-5 ms; P4), and the first pull should not pay them.
        // Each presentation still reads them (tileWillPresent): this only warms what they read.
        static BOOL warmed = NO;
        if (!warmed && hidden) {
            warmed = YES;
            CFTimeInterval tw = CACurrentMediaTime();
            for (id<DMCCTile> t in gCCPTiles) if ([(id)t respondsToSelector:@selector(tileWillPresent)]) [t tileWillPresent];
            DMLog([NSString stringWithFormat:@"[ccpanel] the tiles' first reads done while hidden: %.2f ms", (CACurrentMediaTime() - tw) * 1000.0]);
        }
    });
}
// The window engine for Apple's Stage Manager spot (CCLayout.h MSBDCCLeftOut): another engine of ours (Aerial, Zetsu, MilkyWay: our Stage Manager
// guard holds that button then), the Stage Manager engine, or none of ours (windowing off: iPadOS's own Stage Manager is the user's).
static int DMCCPEngineKind(void) {
#if DEBUG
    if (DMTestFlag("/tmp/msb-ccp-engine-other")) return kMSBDCCEngineOther;   // (tests: as with Aerial, Zetsu or MilkyWay, without switching the user's engine)
#endif
    if (!DMWindowingEnabled()) return kMSBDCCEngineNone;
    if (DMSMEnginePicked()) return kMSBDCCEngineStageManager;
    return DMActiveEngine() != DMEngineNone || DMPlainEngineLoaded() ? kMSBDCCEngineOther : kMSBDCCEngineNone;
}
// The layout: Apple's sizes and pitch in, CCLayout.h's frames out, the views put there. Never during a pull: at build, at a turn, at a module
// list change, at a presentation only when something changed while closed (the bar's height, the user's order; Apple's sensor indicator, read in
// the presentation's first step, before anything shows).
static CGFloat gCCPLaidBar = 0;
static NSString *gCCPLaidSizes;    // (Apple's size of each module at the last layout, in its order: DMCCPSizesNow)
static BOOL gCCPLaidSkipped = NO;  // (a container was Apple's at the last layout -- expanded --: laid out again when it is back)
static NSString *DMCCPSizesNow(void) {
    NSMutableString *sig = [NSMutableString string];
    for (NSString *mid in gCCPOrder) { if (!gCCPContainers[mid]) continue; int w = 0, h = 0; DMCCPAppleSize(mid, &w, &h); [sig appendFormat:@"%d.%d,", w, h]; }
    return sig;
}
// The panel's tiles for CCLayout.h: Apple's adopted containers in the user's order at Apple's sizes, then our Mac tiles. items: room for every
// module and tile; ids (optional): each item's module identifier or tile; sig (optional): Apple's sizes in order (DMCCPSizesNow's form).
static int DMCCPFillItems(MSBDCCItem *items, NSMutableArray *ids, NSMutableString *sig) {
    int k = 0;
    for (NSString *mid in gCCPOrder) {
        if (!gCCPContainers[mid]) continue;
        MSBDCCItem *it = &items[k];
        it->role = MSBDCCRoleForModule(mid.UTF8String, &it->standsFor, &it->firstRow);
        it->order = k; it->w = it->h = 1;
        it->leftOut = MSBDCCLeftOut(it->role, gCCPEngine);
        int w = 0, h = 0;
        if (DMCCPAppleSize(mid, &w, &h)) { it->w = w; it->h = h; }
        [sig appendFormat:@"%d.%d,", w, h];
        [ids addObject:mid]; k++;
    }
    for (id<DMCCTile> t in gCCPTiles) {
        if (![[t tileID] isKindOfClass:[NSString class]]) continue;   // (DMCCPanelAddTile takes none such; one that lost its identifier is left out)
        MSBDCCItem *it = &items[k]; it->role = [t tileRole]; it->order = -1; it->w = it->h = 1; [ids addObject:t]; k++;
    }
    return k;
}
// Apple's container at its frame in the panel: at size 1 the frame itself; smaller, Apple's own size drawn at the panel's size (CCLayout.h
// MSBDCCPlaceAt: its bounds Apple's, a scale about its middle) -- the module lays itself out as Apple made it, a touch goes through the scale, and
// its expanded view grows out of the place it shows at (-compactModeFrame..., DMCCPCompact: the frame at the size).
static void DMCCPPlace(UIView *cv, CGRect f, double size) {
    if (size >= 0.999) {
        if (!CGAffineTransformIsIdentity(cv.transform)) cv.transform = CGAffineTransformIdentity;
        if (!CGRectEqualToRect(cv.frame, f)) cv.frame = f;
        return;
    }
    MSBDCCPlaced p = MSBDCCPlaceAt(f, size);
    CGAffineTransform t = CGAffineTransformMakeScale(p.scale, p.scale);
    if (!CGRectEqualToRect(cv.bounds, p.bounds)) cv.bounds = p.bounds;
    if (!CGPointEqualToPoint(cv.center, p.center)) cv.center = p.center;
    if (!CGAffineTransformEqualToTransform(cv.transform, t)) cv.transform = t;
}
// The panel's own look at the size: its corners (22 pt at 1, as macOS's Control Center) and its shadow.
static void DMCCPChrome(double size) {
    CGFloat r = 22.0 * size;
    if (fabs(gCCPMaterial.layer.cornerRadius - r) > 0.01) { gCCPMaterial.layer.cornerRadius = r; gCCPScroll.layer.cornerRadius = r; [gCCPPanel setNeedsLayout]; }
    gCCPPanel.layer.shadowRadius = 18.0 * size; gCCPPanel.layer.shadowOffset = CGSizeMake(0, 8.0 * size);
}
static void DMCCPLayout(NSString *why) {
    if (!gCCPOn || !gCCPPanel || !gCCPHost.superview) return;
    if (!DMCCPReadMetrics()) { DMLog([NSString stringWithFormat:@"[ccpanel] layout (%@): Apple's module unit not told yet", why]); return; }
    CFTimeInterval t0 = CACurrentMediaTime();
    DMCCPSyncOrder();
    gCCPEngine = DMCCPEngineKind();
    NSUInteger n = gCCPOrder.count + gCCPTiles.count;
    MSBDCCItem *items = calloc(MAX(n, 1), sizeof(MSBDCCItem));
    NSMutableArray *ids = [NSMutableArray array];
    NSMutableString *sig = [NSMutableString string];
    int k = DMCCPFillItems(items, ids, sig);
    gCCPLaidSizes = sig;
    MSBDCCResult r = MSBDCCLayout(items, k, gCCPMetrics);
    double size = MSBDCCSize(gCCPSizeStored, gCCPSizeValue);   // (Control Center Size: every frame and the panel's size at it; 1 as before)
    MSBDCCScaleLayout(items, k, &r, size);
    gCCPSize = size;
    DMCCPChrome(size);
    gCCPLaidBar = DMMenuBarHeight();
    CGRect pf = DMCCPFrame(r.width, r.contentHeight);
    CGAffineTransform keep = gCCPPanel.transform; gCCPPanel.transform = CGAffineTransformIdentity;
    if (!gCCPDetail) gCCPPanel.frame = pf;
    else gCCPPanel.frame = CGRectMake(pf.origin.x, pf.origin.y, pf.size.width, gCCPPanel.bounds.size.height);
    gCCPPanel.transform = keep;
    gCCPPanel.autoresizingMask = DMCCPRTL() ? UIViewAutoresizingFlexibleRightMargin : UIViewAutoresizingFlexibleLeftMargin;
    gCCPScroll.contentSize = CGSizeMake(r.width, r.contentHeight);
    gCCPScroll.scrollEnabled = r.contentHeight > pf.size.height + 0.5;
    [gCCPFrames removeAllObjects]; [gCCPHidden removeAllObjects];
    gCCPLaidSkipped = NO;
    CGFloat scale = DMCCPScale();
    for (int i = 0; i < k; i++) {
        id who = ids[i];
        BOOL isTile = ![who isKindOfClass:[NSString class]];
        NSString *key = isTile ? [(id<DMCCTile>)who tileID] : who;
        if (![key isKindOfClass:[NSString class]]) continue;
        if (items[i].col < 0 && !items[i].hidden) {   // (no room: not shown)
            if (isTile) [(id<DMCCTile>)who tileView].hidden = YES;
            else if (gCCPContainers[key].superview == gCCPScroll) gCCPContainers[key].hidden = YES;   // (Apple's while expanded: not touched)
            continue;
        }
        gCCPFrames[key] = [NSValue valueWithCGRect:items[i].frame];
        if (isTile) {
            UIView *v = [(id<DMCCTile>)who tileView];
            v.hidden = NO;
            if (!CGRectEqualToRect(v.frame, items[i].frame)) v.frame = items[i].frame;
            if ([(id)who respondsToSelector:@selector(tileLayoutInBounds:scale:)]) [(id<DMCCTile>)who tileLayoutInBounds:v.bounds scale:scale];
            [gCCPScroll bringSubviewToFront:v];
            continue;
        }
        UIView *cv = gCCPContainers[key];
        if (items[i].hidden) [gCCPHidden addObject:key];
        if (cv.superview != gCCPScroll) { gCCPLaidSkipped = YES; continue; }   // (expanded, or on its way: Apple's for now, not even its hidden flag)
        cv.hidden = items[i].hidden;   // (a stand-in: hidden at its Mac tile's frame)
        SEL ig = NSSelectorFromString(@"ignoreFrameUpdates");
        if (DMCCTypes(cv, @"ignoreFrameUpdates", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(cv, ig)) { gCCPLaidSkipped = YES; continue; }   // (Apple holds its frame: placed when Apple lets go, DMCCPDidFinish)
        DMCCPPlace(cv, items[i].frame, size);
    }
    // (assistive features read the panel in its order on the screen, row by row: CCLayout.h MSBDCCAXOrder)
    int *ax = calloc(MAX(k, 1), sizeof(int));
    int na = MSBDCCAXOrder(items, k, ax);
    NSMutableArray *els = [NSMutableArray array];
    for (int a = 0; a < na; a++) {
        id who = ids[ax[a]];
        UIView *v = [who isKindOfClass:[NSString class]] ? gCCPContainers[who] : [(id<DMCCTile>)who tileView];
        if (v.superview == gCCPScroll) [els addObject:v];
    }
    gCCPScroll.accessibilityElements = els;
    free(ax);
    free(items);
    double ms = (CACurrentMediaTime() - t0) * 1000.0;
    DMLog([NSString stringWithFormat:@"[ccpanel] layout (%@): %d tiles (%d placed, %lu stand-ins hidden), %d rows, unit %.1f gap %.1f, size %.2f, panel %@, content %.0f, %.2f ms", why, k, r.placed,
        (unsigned long)gCCPHidden.count, r.rows, gCCPMetrics.unit, gCCPMetrics.gap, size, NSStringFromCGRect(pf), r.contentHeight, ms]);
}

// ---- the hooks -----------------------------------------------------------------------------------------------------------------------------
// BigSurCenter loaded after our start (its panel lives in the same overlay): ours steps back before Apple fills its grid, and whatever was
// adopted goes back to Apple's. YES when it did.
static BOOL DMCCPOtherCCNow(void) {
    if (!gCCPOn || !DMCCPOtherCC()) return NO;
    DMCCPGiveBack(@"BigSurCenter is loaded");
    DMCCPSetWanted(NO);   // (the menu bar's Control Center icon: Battery Menu's again)
    return YES;
}
static void DMCCPViewDidLoad(id self, SEL _cmd) {
    DMCCPOtherCCNow();
    CFTimeInterval t0 = CACurrentMediaTime();
    o_DMCCPViewDidLoad(self, _cmd);
    if (!gCCPOn) return;
    DMCCPEnsurePanel(self);
    DMCCPBackdropAway();
    DMCCPLayout(@"Control Center built");
    double ms = (CACurrentMediaTime() - t0) * 1000.0;
    DMLog([NSString stringWithFormat:@"[ccpanel] Apple's Control Center built %.1f s after start: its -viewDidLoad %.1f ms with ours, %lu modules adopted in it", DMProcessAge(), ms, (unsigned long)gCCPContainers.count]);
}
static void DMCCPDidAdd(id self, SEL _cmd, id grid, id containerVC) {
    o_DMCCPDidAdd(self, _cmd, grid, containerVC);
    if (!gCCPOn || DMCCPOtherCCNow()) return;
    DMCCPAdopt(self, grid, containerVC, @"Apple built it");
    DMCCPLayoutSoon();
    DMCCPSettleSoon();
}
static void DMCCPWillRemove(id self, SEL _cmd, id grid, id containerVC) {
    NSString *mid = gCCPOn ? [gCCPByVC objectForKey:containerVC] : nil;
    o_DMCCPWillRemove(self, _cmd, grid, containerVC);   // (Apple takes the container away -- its view and its controller, under any parent)
    if (!mid) return;
    UIView *cv = gCCPContainers[mid];
    if (cv.superview == gCCPScroll) [cv removeFromSuperview];
    DMCCPAppleKeepDrop(cv);   // (Apple's grid does not get it back: Apple removed it)
    [gCCPContainers removeObjectForKey:mid]; [gCCPByVC removeObjectForKey:containerVC]; [gCCPVCOf removeObjectForKey:mid]; [gCCPOrder removeObject:mid];
    DMLog([NSString stringWithFormat:@"[ccpanel] let go of %@ (Apple removed it)", mid]);
    DMCCPLayout(@"a module removed");
}
// One of Apple's modules opens expanded (a hold, a tap on one that opens so, our tile's tap): our material and tiles step back and our backdrop of
// Apple's material (DMCCPMakeDim) shows behind it, as on stock; Apple fades its other modules itself (adopted ones included). Back when it closed.
static void DMCCPExpandedLookSet(BOOL expanded) {
    gCCPMaterial.alpha = expanded ? 0.0 : 1.0;
    gCCPPanel.layer.shadowOpacity = expanded ? 0.0 : 0.25;
    for (id<DMCCTile> t in gCCPTiles) [t tileView].alpha = expanded ? 0.0 : 1.0;
    gCCPDim.alpha = expanded ? 1.0 : 0.0;
}
static void DMCCPExpandedLook(BOOL expanded) {
    [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ DMCCPExpandedLookSet(expanded); } completion:nil];
}
static void DMCCPWillOpen(id self, SEL _cmd, id grid, id module) {
    o_DMCCPWillOpen(self, _cmd, grid, module);
    if (!gCCPOn || self != gCCPOverlay) return;
    NSString *mid = DMCCPExpandedID(module);
    gCCPExpanded = mid;
    DMCCPExpandedLook(YES);
    DMLog([NSString stringWithFormat:@"[ccpanel] %@ opens expanded%@", mid, [gCCPHidden containsObject:mid] ? @" (from its Mac tile)" : @""]);
}
// At Control Center Size under 1, Apple's close sizes the module's own view to the compact frame it asked us for -- the frame at the panel's size,
// in the space it presented in -- and puts it back into a container that keeps Apple's own size under our scale: smaller twice over (17.5.1,
// 1.8.0~a02: Screen Mirroring's view 54.9 pt in its 69 pt container). Each view from the module's own up to the container fills its parent again,
// as at size 1 (there the compact frame is Apple's own size). The view comes back after Apple's -didCloseExpandedModule: (it was still in
// UIKit's transition view then, a03; back ~19 ms later through the main queue, a04): looked at once the run loop has finished this turn, right
// before Core Animation commits it (an observer of the run loop's wait, ordered before the commit's), so the frame drawn shows it filled, and
// again every 30 ms for a moment while it is not back. YES when the view is back (filled or as it should be).
static BOOL DMCCPContentFill(NSString *mid) {
    UIView *cv = mid ? gCCPContainers[mid] : nil, *inner = [gCCPVCOf objectForKey:mid].viewIfLoaded;
    if (!cv || !inner || ![inner isDescendantOfView:cv]) return NO;
    for (UIView *v = inner; v && v != cv; v = v.superview) {
        CGRect want = v.superview.bounds; want.origin = CGPointZero;
        if (!CGAffineTransformIsIdentity(v.transform) || CGRectEqualToRect(v.frame, want)) continue;   // (one Apple keeps transformed is its own)
        DMLog([NSString stringWithFormat:@"[ccpanel] %@: %@ back at %@ (was %@)", mid, NSStringFromClass([v class]), NSStringFromCGRect(want), NSStringFromCGRect(v.frame)]);
        v.frame = want;
    }
    return YES;
}
static void DMCCPContentFillSoon(NSString *mid, int tries) {
    dispatch_block_t look = ^{ if (!DMCCPContentFill(mid) && tries > 0 && gCCPOn && !gCCPExpanded) DMCCPContentFillSoon(mid, tries - 1); };
    if (tries < 10) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), look); return; }
    CFRunLoopObserverRef o = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopBeforeWaiting, false, 1999999, ^(CFRunLoopObserverRef ob, CFRunLoopActivity a) { look(); });   // (one turn: not repeating)
    if (!o) { dispatch_async(dispatch_get_main_queue(), look); return; }
    CFRunLoopAddObserver(CFRunLoopGetMain(), o, kCFRunLoopCommonModes);
    CFRelease(o);
}
static void DMCCPDidClose(id self, SEL _cmd, id grid, id module) {
    o_DMCCPDidClose(self, _cmd, grid, module);
    if (!gCCPOn || self != gCCPOverlay) return;
    NSString *mid = gCCPExpanded ?: DMCCPExpandedID(module);   // (the one that was open: told at its opening)
    gCCPExpanded = nil;
    DMCCPExpandedLook(NO);
    DMLog([NSString stringWithFormat:@"[ccpanel] %@ closed", mid ?: @"the expanded module"]);
#if DEBUG
    { UIView *cv = mid ? gCCPContainers[mid] : nil, *inner = mid ? [gCCPVCOf objectForKey:mid].viewIfLoaded : nil;
      if (cv) DMLog([NSString stringWithFormat:@"[ccpanel] %@ back from Apple: frame %@ bounds %@ scale %.3f in %@; its controller's view %@ in %@ %@", mid, NSStringFromCGRect(cv.frame), NSStringFromCGRect(cv.bounds), cv.transform.a,
          NSStringFromClass([cv.superview class]), NSStringFromCGRect(inner.frame), NSStringFromClass([inner.superview class]), NSStringFromCGRect(inner.superview.frame)]); }
#endif
    if (gCCPSize < 0.999 && !DMCCPContentFill(mid)) DMCCPContentFillSoon(mid, 10);
    // (laid out again when a layout passed it while it was Apple's, and at Control Center Size under 1: the container as Apple's own size again)
    if (gCCPLaidSkipped || gCCPSize < 0.999) DMCCPLayout(@"an expanded module back");
}
// Apple lets go of a module's container: the end of a press on it or of its expanded view (-[CCUIModuleCollectionViewController contentModule
// ContainerViewController:didFinishInteractionWithModule:] clears the container's ignoreFrameUpdates, then tells its delegate; after a close that
// is right after -didCloseExpandedModule:, in the same call, 15.6.1). A layout that passed it while Apple held its frame -- a module's own size
// change while it was expanded (Uptime's Module Size): its new frame kept, the other tiles moved -- left it at its old frame, under its new
// neighbours (16.7.7, 1.8.2.1~u01: Uptime 142 pt wide at 1x1, under the tile after it). Now it goes where that layout put it, and Apple's own
// -layoutSubviews of the container fills it again at that size.
static void DMCCPDidFinish(id self, SEL _cmd, id grid, id module) {
    if (o_DMCCPDidFinish) o_DMCCPDidFinish(self, _cmd, grid, module);   // (code review 1.8.2.1, 2)
    if (!gCCPOn || self != gCCPOverlay || !gCCPLaidSkipped) return;
    DMCCPLayout(@"Apple let go of a module");
}
// Apple's sensor indicator (DMCCPSensorNow): looked at in a presentation's first step (DMCCPUpdate: the header has its presented layout then; laid out
// at once, nothing shows yet -- an animation there would slide the panel in as Control Center comes, and its transform is Apple's drop then), after a
// turn while it shows (DMCCPHostView), and when Apple updates its header's sensor status while it shows (-_updateSensorActivityStatusForHeaderPocket
// View: an app began or stopped using one; read while closed, the header's layout is the dismissed one). When it comes or goes over the panel's
// column the panel moves down under it, or back up: in one animation then (an open page keeps to the room under it, DMCCPanelDetailResized).
static void DMCCPanelDetailResized(void);
static void DMCCPSensorLook(NSString *why, BOOL animated) {
    if (!gCCPOn || !gCCPPanel || !gCCPHaveSensor) return;
    CGRect now = DMCCPSensorNow(YES);
    if (CGRectEqualToRect(CGRectIntegral(now), CGRectIntegral(gCCPSensor))) return;
    gCCPSensor = now;
    DMLog([NSString stringWithFormat:@"[ccpanel] Apple's sensor indicator %@ (%@): the panel %@", CGRectIsEmpty(now) ? @"gone" : NSStringFromCGRect(now), why, CGRectIsEmpty(now) ? @"back under the bar" : @"under it"]);
    if (animated) [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ DMCCPLayout(why); [gCCPPanel layoutIfNeeded]; } completion:nil];
    else [UIView performWithoutAnimation:^{ DMCCPLayout(why); }];
    if (gCCPDetail) DMCCPanelDetailResized();   // (a page open: its height for the room under the panel's new top)
}
static void DMCCPSensorUpdate(id self, SEL _cmd) {
    o_DMCCPSensorUpdate(self, _cmd);
    if (!gCCPOn || self != gCCPOverlay || !gCCPShown) return;   // (closed: the next presentation's first step looks)
    dispatch_async(dispatch_get_main_queue(), ^{ if (gCCPShown) DMCCPSensorLook(@"Apple updated it", gCCPHost.layer.presentationLayer.opacity > 0.01); });
}
// A tap on the indicator opens Apple's list of the apps that used a sensor in its header's own full-screen view, under our panel: the panel steps
// back while it is open (touches there are Apple's then: a hidden view takes none), and comes back when it closes or Control Center does.
static void DMCCPSensorListLook(BOOL open) {
    gCCPSensorList = open;
    [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ gCCPPanel.alpha = open ? 0.0 : 1.0; } completion:nil];
}
static void DMCCPSensorListOpen(id self, SEL _cmd) {
    o_DMCCPSensorListOpen(self, _cmd);
    if (!gCCPOn || self != gCCPOverlay) return;
    DMLog(@"[ccpanel] Apple's list of the apps using a sensor opens: the panel steps back");
    DMCCPSensorListLook(YES);
}
static void DMCCPSensorListClose(id self, SEL _cmd) {
    o_DMCCPSensorListClose(self, _cmd);
    if (!gCCPOn || self != gCCPOverlay || !gCCPSensorList) return;
    long long st = DMCCPPresentationState();
    if (st == 0 || st == 3) { gCCPSensorList = NO; return; }   // (closed with Control Center, or as it goes away: the panel stays out until -_didDismiss puts it back)
    DMLog(@"[ccpanel] that list closed: the panel is back");
    DMCCPSensorListLook(NO);
}
// Expanded views grow out of our tiles and close back into them: Apple frames them from this (its grid would answer the module's old place).
// A hidden stand-in answers its Mac tile's frame.
static CGRect DMCCPCompact(id self, SEL _cmd, id containerVC) {
    CGRect apple = o_DMCCPCompact(self, _cmd, containerVC);
    if (!gCCPOn) return apple;
    NSString *mid = [gCCPByVC objectForKey:containerVC];
    NSValue *f = mid ? gCCPFrames[mid] : nil;
    if (!f || !gCCPScroll.window) return apple;
    UIViewController *pc = DMCCGet(self, @"bs_presentationContextDefiningViewController");
    UIView *to = pc.viewIfLoaded ?: gCCPScroll.window;
    return [gCCPScroll convertRect:f.CGRectValue toView:to];
}
// A tap in our panel is not a tap outside Control Center (Apple only asks its own grid and header).
static BOOL DMCCPTapBegin(id self, SEL _cmd, id gr) {
    BOOL r = o_DMCCPTapBegin(self, _cmd, gr);
    UIView *p = gCCPPanel;
    if (r && gCCPOn && p.window && !gCCPExpanded && !gCCPSensorList && [gr isKindOfClass:[UIGestureRecognizer class]] && [p pointInside:[(UIGestureRecognizer *)gr locationInView:p] withEvent:nil]) return NO;
    return r;
}
// The panel's motion for one presentation step: it fades with Apple's progress and drops a few points into place (MSBDCCMotion), in the very
// spring Apple runs its own step with -- our animation goes into Apple's batch (DMCCPBatch) --, or, where that is not here, a short spring of
// our own (the spike's).
static void DMCCPApplyMotion(double progress) {
    double alpha = 1, dy = 0;
    MSBDCCMotion(progress, MSBReduceMotion(), &alpha, &dy);
    gCCPHost.alpha = alpha;
    gCCPPanel.transform = CGAffineTransformMakeTranslation(0, dy);
}
static id DMCCPBatch(id self, SEL _cmd, id state, id previous) {
    id batch = o_DMCCPBatch(self, _cmd, state, previous);
    if (!gCCPOn || !gCCPUpdating || !batch || !gCCPHost) return batch;
    Class pc = object_getClass(self);
    id params = DMCCTypes(pc, @"_baseC2AnimationParametersForTransitionState:", "@24@0:8@16") ? ((id (*)(id, SEL, id))objc_msgSend)((id)pc, NSSelectorFromString(@"_baseC2AnimationParametersForTransitionState:"), state) : nil;
    Class ac = objc_getClass("CCUIAnimation");
    if (!params || !ac || !DMCCTypes(batch, @"addAnimation:", "v24@0:8@16")) return batch;
    double progress = DMCCPProgress(state);
    id anim = ((id (*)(id, SEL, id, id))objc_msgSend)((id)ac, NSSelectorFromString(@"animationWithParameters:animations:"), params, ^{ DMCCPApplyMotion(progress); });
    if (!anim) return batch;
    ((void (*)(id, SEL, id))objc_msgSend)(batch, NSSelectorFromString(@"addAnimation:"), anim);
    gCCPJoined = YES;
    return batch;
}
static void DMCCPUpdate(id self, SEL _cmd, id state, id completion) {
    BOOL ours = gCCPOn && self == gCCPOverlay && gCCPHost;
    gCCPUpdating = ours; gCCPJoined = NO;
    o_DMCCPUpdate(self, _cmd, state, completion);
    gCCPUpdating = NO;
    if (ours && gCCPSensorDue) { gCCPSensorDue = NO; DMCCPSensorLook(@"Control Center presenting", NO); }   // (Apple's header has its presented layout now)
    if (!ours || gCCPJoined) return;
    double progress = DMCCPProgress(state);   // (not joined: our own motion, the spike's spring; a finger pull follows at once)
    if (DMCCPInteractive(state) || [UIView inheritedAnimationDuration] > 0) DMCCPApplyMotion(progress);
    else [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:1.0 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                          animations:^{ DMCCPApplyMotion(progress); } completion:nil];
}
// Control Center about to show: what changed while it was closed goes in now, once (nothing of ours runs while it is closed).
static void DMCCPWillPresent(void) {
    UIViewController *ov = gCCPOverlay;
    if (!ov.isViewLoaded || !gCCPHost) return;
    if (gCCPHost.superview != ov.view || ov.view.subviews.lastObject != gCCPHost) DMCCPEnsurePanel(ov);   // (Apple added a view of its own on top since)
    DMCCPBackdropAway();
    DMCCPHeaderBarAway();
    gCCPPanel.overrideUserInterfaceStyle = DMSystemInterfaceStyle();   // (Settings > Display & Brightness, as our menus)
    BOOL reordered = DMCCPSyncOrder();   // (a reorder in Settings since the last layout)
    BOOL resized = !reordered && ![DMCCPSizesNow() isEqualToString:gCCPLaidSizes ?: @""];   // (a module of another size now: CCSupport's)
#if DEBUG
    CFTimeInterval te = CACurrentMediaTime();
#endif
    BOOL engine = DMCCPEngineKind() != gCCPEngine;   // (Apple's Stage Manager spot follows the window engine)
#if DEBUG
    double engineMs = (CACurrentMediaTime() - te) * 1000.0;
#endif
    gCCPSensorDue = gCCPHaveSensor;   // (Apple's sensor indicator: looked at in the first presentation step, DMCCPUpdate)
    if (reordered || resized || engine || fabs(DMMenuBarHeight() - gCCPLaidBar) > 0.25)
        DMCCPLayout(reordered ? @"the user's order changed" : resized ? @"a module's size changed" : engine ? @"the window engine changed" : @"the bar's height known");
    BOOL locked = DMCCPLockedNow();
    BOOL lockChanged = locked != gCCPLocked; gCCPLocked = locked;
    DMCCTPanelWillPresent();
#if DEBUG
    CFTimeInterval tt = CACurrentMediaTime();
#endif
    for (id<DMCCTile> t in gCCPTiles) {
        if (lockChanged && [(id)t respondsToSelector:@selector(tileLockedChanged:)]) [t tileLockedChanged:locked];
        if ([(id)t respondsToSelector:@selector(tileWillPresent)]) [t tileWillPresent];
    }
#if DEBUG
    DMLog([NSString stringWithFormat:@"[ccpanel] about to show: the window engine %.2f ms, the tiles %.2f ms", engineMs, (CACurrentMediaTime() - tt) * 1000.0]);
#endif
}
static void DMCCPWillPresentHook(id self, SEL _cmd) {
    o_DMCCPWillPresent(self, _cmd);
    gCCPShown = YES;
    if (!gCCPOn) return;
#if DEBUG
    CFTimeInterval t0 = CACurrentMediaTime();
#endif
    DMCCPWillPresent();
#if DEBUG
    DMLog([NSString stringWithFormat:@"[ccpanel] about to show: ours %.2f ms (order, sizes, bar, lock, tiles)", (CACurrentMediaTime() - t0) * 1000.0]);   // (the presentation's start: its cost)
#endif
}
static void DMCCPDidDismissHook(id self, SEL _cmd) {
    o_DMCCPDidDismiss(self, _cmd);
    gCCPShown = NO;
    if (gCCPOn) {
        if (gCCPExpanded) {   // (an expansion that ended without Apple's -didCloseExpandedModule:: nothing is open once Control Center has closed)
            DMLog([NSString stringWithFormat:@"[ccpanel] %@ still counted as expanded at the close: reset", gCCPExpanded]);
            gCCPExpanded = nil; DMCCPExpandedLookSet(NO);
        }
        if (gCCPDetail) DMCCPanelCloseDetail(NO);
        gCCPSensorList = NO;   // (Apple's sensor list was open as Control Center closed, or closed as it went away: the panel back for the next time)
        if (gCCPPanel.alpha != 1.0) gCCPPanel.alpha = 1.0;
        for (id<DMCCTile> t in gCCPTiles) if ([(id)t respondsToSelector:@selector(tileDidDismiss)]) [t tileDidDismiss];
        DMCCTPanelDidDismiss();   // (a page's row that closed Control Center: its action now, CCTiles.h)
    }
    if (gCCPPending) dispatch_async(dispatch_get_main_queue(), ^{ DMCCPApplyStyle(@"Control Center closed"); });
}

// ---- the tiles' calls ----------------------------------------------------------------------------------------------------------------------
// Apple's expanded view of an adopted module, opened out of its tile (ours for a stand-in): -[CCUIContentModuleContainerViewController
// expandModule], what a hold on it does. NO when it cannot (not adopted, already open, not on this iPadOS).
static BOOL DMCCPanelExpandModule(NSString *mid) {
    if (DMCC18TilesAreOurs()) return DMCC18AppleModuleOpen(mid);   // (iPadOS 18: CC18Tiles.h)
    UIViewController *vc = mid ? [gCCPVCOf objectForKey:mid] : nil;
    if (!gCCPOn || !gCCPHaveExpand || !vc || gCCPExpanded || DMCCPExpandedNow(vc) || !DMCCTypes(vc, @"expandModule", "v16@0:8")) return NO;
    ((void (*)(id, SEL))objc_msgSend)(vc, NSSelectorFromString(@"expandModule"));
    return YES;
}
__attribute__((unused)) static BOOL DMCCPanelLocked(void) { return gCCPLocked; }
static void DMCCPanelDismiss(void) {   // (Apple's own animated dismissal)
    id cc = DMControlCenterController();
    if (DMCCTypes(cc, @"dismissAnimated:", "v20@0:8B16")) ((void (*)(id, SEL, BOOL))objc_msgSend)(cc, @selector(dismissAnimated:), YES);
}
// A page coming or going in place of the tiles takes the assistive features with it (P4, the live passes, 15.6.1): VoiceOver moves to the page's
// back row and back to the tile (a screen change); the tiles under an open page are no one's while it shows -- Full Keyboard Access's focus
// had stayed on the hidden chevron that opened the page; now its next key goes on in the page's rows, and after the page near its tile.
static void DMCCPAXMoveTo(UIView *v, BOOL pageOpen) {
    gCCPScroll.accessibilityElementsHidden = pageOpen;
    gCCPScroll.userInteractionEnabled = !pageOpen;
    if (v) DMAXScreenChanged(v);   // (only while an assistive feature runs)
}
// A detail page in place of the tiles (P3's pages): its height is worked out first (MSBDCCDetailHeight), then one animation changes the panel's
// height and cross-fades the tiles out and the page in; a back row (a chevron and the page's title) closes it. A page that needs Settings or our
// menu window is not opened on the Lock Screen.
static void DMCCPanelCloseDetail(BOOL animated) {
    if (DMCC18TilesAreOurs()) { DMCC18PageClose(animated); return; }   // (iPadOS 18: CC18Tiles.h)
    UIView *page = gCCPDetail; id<DMCCTile> tile = gCCPDetailTile;
    if (!page) return;
    gCCPDetail = nil; gCCPDetailTile = nil;
    CGRect f = gCCPPanel.frame; f.size.height = MIN(gCCPScroll.contentSize.height, DMCCPFrame(f.size.width, gCCPScroll.contentSize.height).size.height);
    void (^go)(void) = ^{ page.alpha = 0.0; gCCPScroll.alpha = 1.0; gCCPPanel.bounds = CGRectMake(0, 0, f.size.width, f.size.height); gCCPPanel.center = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f)); [gCCPPanel layoutIfNeeded]; };
    if (animated) [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:go completion:^(BOOL d) { [page removeFromSuperview]; }];
    else go();
    DMCCPAXMoveTo(animated ? [tile tileView] : nil, NO);   // (not animated: Control Center has closed, no one to move)
    if (!animated) [page removeFromSuperview];
    if ([(id)tile respondsToSelector:@selector(tileDetailDidClose)]) [tile tileDetailDidClose];
}
// The open page's height changed (the tile filled it again: a scan's results, a device that connected): the panel follows in one animation, its top
// where it is; the page scrolls when it is taller than the room.
static void DMCCPanelDetailResized(void) {
    if (DMCC18TilesAreOurs()) { DMCC18PageResized(); return; }   // (iPadOS 18: CC18Tiles.h)
    UIView *d = gCCPDetail, *page = gCCPDetailPage; UIScrollView *s = gCCPDetailScroll;
    if (!d || !page || !s || !gCCPPanel) return;
    CGFloat w = gCCPPanel.bounds.size.width, headerH = MSBDMenuRowScaled(gDMBarSize, 36.0), z = gCCPSize;
    CGRect room = DMCCPFrame(w, 1.0e6);
    CGFloat h = MSBDCCDetailHeightAt(page.frame.size.height, headerH, kMSBDCCPad, room.size.height, gCCPMetrics.unit, z), wU = w / z, hU = h / z;   // (the page's own space: size 1)
    CGRect f = gCCPPanel.frame;
    [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        gCCPPanel.bounds = CGRectMake(0, 0, f.size.width, h); gCCPPanel.center = CGPointMake(CGRectGetMidX(f), f.origin.y + h / 2.0);
        s.frame = CGRectMake(kMSBDCCPad, kMSBDCCPad + headerH, wU - 2 * kMSBDCCPad, hU - headerH - 2 * kMSBDCCPad);
        [gCCPPanel layoutIfNeeded];
    } completion:nil];
    s.contentSize = page.frame.size; s.scrollEnabled = page.frame.size.height > s.bounds.size.height + 0.5;
    DMLog([NSString stringWithFormat:@"[ccpanel] %@'s page now %.0f pt", [gCCPDetailTile tileID], h]);
}
static void DMCCPanelOpenDetail(id<DMCCTile> tile) {
    if (DMCC18TilesAreOurs()) { DMCC18PageOpen(tile); return; }   // (iPadOS 18: CC18Tiles.h)
    if (!gCCPOn || !gCCPPanel || !tile || gCCPDetail || gCCPExpanded || ![(id)tile respondsToSelector:@selector(tileDetailViewForWidth:)]) return;
    if (gCCPLocked && [(id)tile respondsToSelector:@selector(tileDetailNeedsUnlock)] && [tile tileDetailNeedsUnlock]) { DMLog([NSString stringWithFormat:@"[ccpanel] %@'s page needs the iPad unlocked", [tile tileID]]); return; }
    // (at Control Center Size under 1 the page is laid out at size 1 -- the panel's width over the size, w here -- and drawn at the size: its rows
    //  are the menus' own; DMCCPPlace in the panel's layout)
    CGFloat pw = gCCPPanel.bounds.size.width, z = gCCPSize, w = pw / z, scale = DMCCPScale(), headerH = MSBDMenuRowScaled(gDMBarSize, 36.0);
    UIView *page = [tile tileDetailViewForWidth:w - 2 * kMSBDCCPad];
    if (!page) return;
    CGRect room = DMCCPFrame(pw, 1.0e6);
    CGFloat hp = MSBDCCDetailHeightAt(page.frame.size.height, headerH, kMSBDCCPad, room.size.height, gCCPMetrics.unit, z), h = hp / z;   // (hp the panel's, h the page's own)
    UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    d.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    back.frame = CGRectMake(kMSBDCCPad - 4, kMSBDCCPad, w - 2 * kMSBDCCPad, headerH);
    back.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [back setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 * scale weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    NSString *title = [(id)tile respondsToSelector:@selector(tileDetailTitle)] ? [tile tileDetailTitle] : nil;
    [back setTitle:[@" " stringByAppendingString:title ?: @""] forState:UIControlStateNormal];
    back.titleLabel.font = [UIFont systemFontOfSize:15.0 * scale weight:UIFontWeightSemibold];
    back.tintColor = [UIColor labelColor];
    back.accessibilityLabel = title.length ? [NSString stringWithFormat:@"Back from %@", title] : @"Back";
    [back addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMCCPanelCloseDetail(YES); }] forControlEvents:UIControlEventTouchUpInside];
    [d addSubview:back];
    UIScrollView *s = [[UIScrollView alloc] initWithFrame:CGRectMake(kMSBDCCPad, kMSBDCCPad + headerH, w - 2 * kMSBDCCPad, h - headerH - 2 * kMSBDCCPad)];
    s.contentSize = page.frame.size; s.alwaysBounceVertical = NO; s.scrollEnabled = page.frame.size.height > s.bounds.size.height + 0.5;
    [s addSubview:page];
    [d addSubview:s];
    gCCPDetailScroll = s; gCCPDetailPage = page;
    d.alpha = 0.0;
    [gCCPPanel addSubview:d];
    DMCCPPlace(d, gCCPPanel.bounds, z);   // (where the panel's layout keeps it: its own space at size 1, drawn at the size)
    gCCPDetail = d; gCCPDetailTile = tile;
    CGRect f = gCCPPanel.frame;
    [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        gCCPScroll.alpha = 0.0; d.alpha = 1.0;
        gCCPPanel.bounds = CGRectMake(0, 0, f.size.width, hp); gCCPPanel.center = CGPointMake(CGRectGetMidX(f), f.origin.y + hp / 2.0);
        [gCCPPanel layoutIfNeeded];
    } completion:nil];
    DMCCPAXMoveTo(back, YES);
    DMLog([NSString stringWithFormat:@"[ccpanel] %@'s page open (%.0f pt, size %.2f)", [tile tileID], hp, z]);
}

// ---- turning it on and off -----------------------------------------------------------------------------------------------------------------
// Control Center's overlay as SpringBoard made it, nil before. Asking makes nothing, at any time: the controller's lookup never makes it (common/SBShared.h, 1.8.0.1) and
// -viewController only reads its variable (read on 15.6.1 and 18.5). It was refused for SpringBoard's first 8 s while Control Center's window had not been seen, from when asking
// could make Control Center: a change to Mac there, with Apple's -viewDidLoad over before our hooks went in, was in force with nothing built, and every later look stopped at
// want == gCCPOn until the next respring (review 1.8.0.1, 1.8.1 item 16). So gCCPOn means: applied, or to be applied by our hooks as Apple builds it (DMCCPApplyStyle).
static UIViewController *DMCCPFindOverlay(void) {
    if (gCCPOverlay) return gCCPOverlay;
    id ov = DMCCGet(DMControlCenterController(), @"viewController");
    return [ov isKindOfClass:objc_getClass(kDMCCPOverlay)] ? ov : nil;
}
// Mac chosen while Control Center is built already: Apple's containers come into our panel as they are (Apple's grid's children, in its order).
static void DMCCPBuildLive(UIViewController *ov) {
    id grid = DMCCGet(ov, @"moduleCollectionViewController");
    if (![grid isKindOfClass:objc_getClass(kDMCCPGrid)]) { DMLog(@"[ccpanel] Apple's grid not found: built at the next start"); return; }
    DMCCPEnsurePanel(ov);
    DMCCPBackdropAway();
    for (UIViewController *vc in [[(UIViewController *)grid childViewControllers] copy]) if ([vc isKindOfClass:objc_getClass(kDMCCPContainerVC)]) DMCCPAdopt(ov, grid, vc, @"Mac chosen");
    gCCPGrid = grid;
    DMCCPLayout(@"Mac chosen");
    DMCCPSettleSoon();
}
// iPadOS chosen while running: every container back into Apple's grid with its controller (as -_setupAndAddModuleViewControllerToHierarchy: put
// it there), each as Apple had it (DMCCPAppleKeep: its place among the grid's views, its hidden flag, Apple's values on its views), the backdrop
// and the header's status bar alpha as Apple had them, our views out: iPadOS's look is a start's (CCGiveBack.h). Apple's own layout places the
// containers again (-ccui_setFramePreservingTransform:, a transform of Apple's kept); its bookkeeping never knew they had left.
static void DMCCPGiveBack(NSString *why) {
    UIViewController *grid = gCCPGrid, *ov = gCCPOverlay;
    UIView *home = DMCCGet(grid, @"moduleCollectionView");   // (Apple's layout view: its grid lays out and animates only its subviews)
    if (![home isKindOfClass:[UIView class]]) home = grid.viewIfLoaded;
    int n = 0, kept = 0, bars = 0;
    if (gCCPDetail) DMCCPanelCloseDetail(NO);
    gCCPExpanded = nil; DMCCPExpandedLookSet(NO);
    gCCPSensorList = NO; gCCPPanel.alpha = 1.0; gCCPSensor = CGRectZero;
    // (every adopted container with what its move kept, in the order of the moves; one without -- never so -- goes at the end of Apple's view)
    NSMutableArray<DMCCPAppleKeep *> *keeps = [NSMutableArray array];
    NSArray *adopted = gCCPContainers.allValues;
    for (DMCCPAppleKeep *k in gCCPAppleKeeps) if (k.cv && [adopted indexOfObjectIdenticalTo:k.cv] != NSNotFound) [keeps addObject:k];
    for (NSString *mid in gCCPOrder) {
        UIView *cv = gCCPContainers[mid];
        if (!cv || [keeps indexOfObjectPassingTest:^BOOL(DMCCPAppleKeep *k, NSUInteger i, BOOL *stop) { return k.cv == cv; }] != NSNotFound) continue;
        DMCCPAppleKeep *k = [DMCCPAppleKeep new]; k.cv = cv; k.vc = [gCCPVCOf objectForKey:mid];
        [keeps addObject:k];
    }
    // The views first, then their controllers (UIKit adds a child only under the controller its view is in, as DMCCPAdopt): the views in the
    // reverse order of their moves, each right after the last of the views that came before it (Apple's order whole again); the controllers in the
    // order Apple had them.
    for (DMCCPAppleKeep *k in keeps.reverseObjectEnumerator) {
        UIView *cv = k.cv;
        if (!cv || !k.vc || !home) continue;
        if (!CGAffineTransformIsIdentity(cv.transform)) cv.transform = CGAffineTransformIdentity;   // (drawn at Control Center Size: its bounds are Apple's own size)
        cv.hidden = k.hidden;
        NSArray<UIView *> *now = home.subviews;
        long nPrev = k.home == home ? (long)k.before.count : 0, at = (long)now.count;
        if (nPrev > 0) {
            long *prevAt = calloc((size_t)nPrev, sizeof(long));
            for (long i = 0; i < nPrev; i++) { UIView *p = (__bridge UIView *)[k.before pointerAtIndex:(NSUInteger)i]; NSUInteger x = p ? [now indexOfObjectIdenticalTo:p] : NSNotFound; prevAt[i] = x == NSNotFound ? -1 : (long)x; }
            at = MSBDCCPutBackAt(prevAt, nPrev);
            free(prevAt);
        } else if (k.home == home) at = 0;   // (first among Apple's views when it was taken)
        [home insertSubview:cv atIndex:(NSUInteger)at];
    }
    for (DMCCPAppleKeep *k in keeps) {
        UIView *cv = k.cv; UIViewController *vc = k.vc;
        if (!cv || !vc || !home) continue;
        @try {
            if (vc.parentViewController != grid) { [vc willMoveToParentViewController:nil]; [vc removeFromParentViewController]; [grid addChildViewController:vc]; [vc didMoveToParentViewController:grid]; }
        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[ccpanel] %@: its controller could not go back (%@)", DMCCPModuleID(vc) ?: @"?", e.reason]); }
        if (vc.parentViewController != grid) {   // (it keeps its view with ours, out of sight until the next start: the two are never apart, the cc03 abort)
            [gCCPScroll addSubview:cv];
            if (!vc.parentViewController) { @try { [gCCPVC addChildViewController:vc]; [vc didMoveToParentViewController:gCCPVC]; } @catch (NSException *e) {} }
            kept++; continue;
        }
        DMCCPAppleLookBack(k);   // (Apple's next presentation starts from Apple's own values, as on stock)
        n++;
    }
    [home setNeedsLayout]; [grid.viewIfLoaded setNeedsLayout];
    [gCCPContainers removeAllObjects]; [gCCPByVC removeAllObjects]; [gCCPVCOf removeAllObjects]; [gCCPOrder removeAllObjects]; [gCCPFrames removeAllObjects]; [gCCPHidden removeAllObjects];
    [gCCPAppleKeeps removeAllObjects];
    // Apple's backdrop shown again if ours hid it (its alpha is Apple's presentation's); each header's status bar alpha as Apple had it or asked for
    // it -- through Apple's own setter: on the iPad nothing of Apple's sets it again.
    UIView *back = gCCPHidBackdrop;
    if (back.hidden) back.hidden = NO;
    gCCPHidBackdrop = nil;
    for (UIView *hp in gCCPAppleBarHeaders.allObjects) {
        MSBDCCApple k = DMCCPAppleBarOf(hp);
        double a = 1.0;
        if (MSBDCCGiveBack(&k, &a) && o_DMCCPHeaderBarAlpha) { o_DMCCPHeaderBarAlpha(hp, NSSelectorFromString(@"setStatusBarAlpha:"), a); bars++; }
        DMCCPAppleBarSet(hp, k);
    }
    gCCPDim.alpha = 0.0;
    @try { [gCCPVC willMoveToParentViewController:nil]; [gCCPHost removeFromSuperview]; [gCCPVC removeFromParentViewController]; } @catch (NSException *e) {}
    gCCPOn = NO;
    DMLog([NSString stringWithFormat:@"[ccpanel] iPadOS's Control Center back (%@): %d modules given back to Apple's grid (%@)%@, %@%@", why, n, home == grid.viewIfLoaded ? @"its view" : NSStringFromClass([home class]),
        kept ? [NSString stringWithFormat:@", %d kept: their controllers could not go back", kept] : @"", bars ? @"the header's status icons at Apple's alpha" : @"no header's alpha to give back", ov ? @"" : @" (no overlay)"]);
}
// Ours is the style in force, or will be once Control Center has closed (the hooks in, or still to try): the menu bar's Control Center icon shows
// then even with Battery Menu off (KT 3 Nov, BatteryMenu.h DMBattCCLayout), so the bar is laid out again when this changes.
static BOOL gCCPWant = NO;
static void DMCCPSetWanted(BOOL want) {
    want = want && gCCPSupported;
    if (want == gCCPWant) return;
    gCCPWant = want;
    DMLog([NSString stringWithFormat:@"[ccpanel] our Control Center %@: the menu bar's Control Center icon %@", want ? @"is the style" : @"is not the style", want ? @"shows" : @"shows with Battery Menu only"]);
    dispatch_async(dispatch_get_main_queue(), ^{ for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout]; });
}
// The style in force, applied while Control Center is closed (an open one keeps its look until it closes: DMCCPDidDismissHook). Mac needs the
// check passed and no other Control Center loaded; the hooks go in the first time Mac is chosen and stay (they only act while it is).
static BOOL gCCPInConstructor = NO;   // (the start's look: SpringBoard's launch has not begun, nothing is asked of it: DMCCPanelInit)
static void DMCCPApplyStyle(NSString *why) {
    BOOL want = gCCPSupported && DMCCPStyleIsMac() && !DMCCPOtherCC();
    DMCCPSetWanted(want);
    if (want == gCCPOn) { gCCPPending = NO; return; }
    if (DMControlCenterActive()) {   // (applied once Control Center has closed: our -_didDismiss hook, and a look a second later -- no hook before Mac was ever chosen here, and right after its close Control Center can still answer that it shows)
        if (!gCCPPending) DMLog([NSString stringWithFormat:@"[ccpanel] style %@ (%@): when Control Center closes", want ? @"Mac" : @"iPadOS", why]);
        gCCPPending = YES;
        unsigned gen = ++gCCPPendingGen;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gCCPPending && gen == gCCPPendingGen) DMCCPApplyStyle(@"Control Center closed"); });
        return;
    }
    gCCPPending = NO;
    if (!want) { DMCCPGiveBack(why); return; }
    if (!DMCCPInstallHooks()) { DMCCPSetWanted(NO); return; }
    DM_FEATURE_MARK("cc-mac");
    gCCPOn = YES;
    UIViewController *ov = gCCPInConstructor ? nil : DMCCPFindOverlay();
    if (ov.isViewLoaded) DMCCPBuildLive(ov);   // (else built with Apple's: our -viewDidLoad and -didAdd... hooks)
    DMLog([NSString stringWithFormat:@"[ccpanel] style Mac (%@)%@", why, ov.isViewLoaded ? @": Apple's modules adopted now" : @": built when Apple builds Control Center"]);
}
static void DMCCPPrefsChanged(void) {
    if (!gCCPSupported) return;
    DMCCPApplyStyle(@"the preference changed");
    // Control Center Size moved (Settings' slider, while it is dragged): laid out again at once -- for the next opening, or in one animation while
    // Control Center shows.
    if (!gCCPOn || fabs(MSBDCCSize(gCCPSizeStored, gCCPSizeValue) - gCCPSize) < 1e-6) return;
    if (gCCPDetail) DMCCPanelCloseDetail(NO);   // (a page is laid out at its opening's size)
    if (gCCPShown && !gCCPExpanded) [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ DMCCPLayout(@"Control Center Size"); [gCCPPanel layoutIfNeeded]; } completion:nil];
    else [UIView performWithoutAnimation:^{ DMCCPLayout(@"Control Center Size"); }];
}
// Control Center's own status bar copies (its header's) are not dressed as our menu bar while the panel shows: they stay hidden behind it
// (keepbar), and dressing them cost ~40 ms of every open on 15-17 (spike samples). StatusBar.x DMBarCopyIsCCDuplicate.
static BOOL DMCCPanelOwnsCCBars(void) { return gCCPOn && gCCPHost.superview != nil; }
// Esc on a hardware keyboard while the panel shows (StatusBar.x's -[SpringBoard pressesBegan:withEvent:] hook, DMOverlayPressesBegan): as
// VoiceOver's escape (DMCCPPanelView -accessibilityPerformEscape), an open page goes back, else Control Center closes. Esc alone; YES when taken.
static BOOL DMCCPanelEscape(NSSet<UIPress *> *presses) {
    if (!gCCPOn || !gCCPHost.window || !DMControlCenterActive()) return NO;
    for (UIPress *p in presses) {
        if (p.key.keyCode != UIKeyboardHIDUsageKeyboardEscape || (p.key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierControl | UIKeyModifierAlternate | UIKeyModifierShift))) continue;
        DM_FEATURE_MARK("esc-closes-cc");
        DMLog([NSString stringWithFormat:@"[ccpanel] Esc: %@", gCCPDetail ? @"the page goes back" : @"Control Center closes"]);
        if (gCCPDetail) DMCCPanelCloseDetail(YES); else DMCCPanelDismiss();
        return YES;
    }
    return NO;
}
// ---- for the rest of SpringBoard (StatusBar.x's declarations) ----
static BOOL DMCCPanelWanted(void) { return gCCPWant || DMCC18PanelWanted(); }   // (18: CC18Shape.h)
static BOOL DMCCPanelOn(void) { return DMCCPanelOwnsCCBars(); }
// RAM & CPU put in Control Center by itself (StatusBar.x DMCCAutoAddMeasureNow, 1.7.7 item 8) while the panel is Control Center: the room by the
// panel's own rules (CCLayout.h MSBDCCRoomForOne; Apple's grid under the panel is empty). NO (with why) when it cannot be told; *room the answer.
static BOOL DMCCPanelRoomForModule(NSString *mid, int w, int h, BOOL *room, NSString **why) {
    *room = NO;
    if (!DMCCPanelOn() || !gCCPHost.window) { if (why) *why = @"our Control Center is not laid out on the screen"; return NO; }
    if (!DMCCPReadMetrics()) { if (why) *why = @"Apple's module unit not told yet"; return NO; }
    NSUInteger n = gCCPOrder.count + gCCPTiles.count;
    if (n > 250) { if (why) *why = @"more modules than the panel lays out"; return NO; }
    MSBDCCItem *items = calloc(n + 1, sizeof(MSBDCCItem));
    int k = DMCCPFillItems(items, nil, nil);
    MSBDCCItem extra; memset(&extra, 0, sizeof extra);
    extra.role = MSBDCCRoleForModule(mid.UTF8String, &extra.standsFor, &extra.firstRow);
    extra.w = w; extra.h = h; extra.leftOut = MSBDCCLeftOut(extra.role, gCCPEngine);
    CGSize sz = gCCPHost.bounds.size;
    double need = 0, roomH = 0;
    *room = MSBDCCRoomForOneAt(items, k, extra, gCCPMetrics, gCCPSize, MIN(sz.width, sz.height), DMMenuBarHeight(), &need, &roomH, NULL);   // (at Control Center Size)
    free(items);
    if (why) *why = [NSString stringWithFormat:@"%.0f pt with it, %.0f pt of room under the bar on the screen's shorter side%@", need, roomH, *room ? @"" : @": it would scroll"];
    return YES;
}
// Ours among Control Center's views: a Mac tile's view, the open page, our backdrop and material (Apple's adopted containers are Apple's). The
// label walks over Control Center's window (StatusBar.x DMApplyControlCenterScale: Memory Magic's lines, the uptime module's text) skip them: a
// network's, a device's or a track's name that reads like "Free RAM" or "12m 30s" is ours, not a module's.
static BOOL DMCCPanelOwnView(UIView *v) {
    if (!gCCPOn || !v) return NO;
    if (v == gCCPDetail || v == gCCPDim || v == gCCPMaterial) return YES;
    for (id<DMCCTile> t in gCCPTiles) if ([t tileView] == v) return YES;
    return NO;
}

// ---- the start -----------------------------------------------------------------------------------------------------------------------------
// %ctor, before Apple builds Control Center (1.5 s after start): the check on 15-17 (its verdict for Settings whatever the style), then the
// hooks only if Mac is chosen. iPadOS 18: nothing (1.8.0 ships Mac on 15-17; CCMacCheck.h answers "not supported" there).
static void DMCCPanelInit(void) {
    NSInteger major = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    if (major < 15 || major > 17) return;
    CFTimeInterval t0 = CACurrentMediaTime();
    gCCPCheckOptional = [NSMutableArray array];
    NSUInteger checked = 0;
    NSArray<NSString *> *bad = DMCCPCheckAPI(gCCPCheckOptional, &checked);
    gCCPSupported = bad.count == 0;
    NSString *reason = gCCPSupported ? nil : [NSString stringWithFormat:@"%@: %lu of the system methods our Control Center uses are missing or different", DMCCPOSLabel(), (unsigned long)bad.count];
    DMCCPPublishVerdict(gCCPSupported, reason, bad, gCCPCheckOptional);
    if (MSBDDiagEnabled()) MSBDDiagWrite(@"ControlCenter", [NSString stringWithFormat:@"check: %@ (%lu rows)%@%@\n", gCCPSupported ? @"ok" : reason, (unsigned long)checked,
        bad.count ? [@"\nfailed: " stringByAppendingString:[bad componentsJoinedByString:@"; "]] : @"", gCCPCheckOptional.count ? [@"\noptional missing: " stringByAppendingString:[gCCPCheckOptional componentsJoinedByString:@"; "]] : @""]);
    DMLog([NSString stringWithFormat:@"[ccpanel] API check: %@ (%lu rows, %.2f ms)%@", gCCPSupported ? @"passed" : reason, (unsigned long)checked, (CACurrentMediaTime() - t0) * 1000.0,
        gCCPCheckOptional.count ? [NSString stringWithFormat:@"; optional missing: %@", [gCCPCheckOptional componentsJoinedByString:@"; "]] : @""]);
    for (NSString *l in bad) DMLog([@"[ccpanel]   " stringByAppendingString:l]);
    if (!gCCPSupported) return;
    if (DMCCPOtherCC()) DMLog(@"[ccpanel] BigSurCenter is loaded: ours stays off");
    gCCPInConstructor = YES;
    DMCCPApplyStyle(@"start");
    gCCPInConstructor = NO;
}

#if DEBUG
// ---- debug read-outs and triggers (ccp_*) --------------------------------------------------------------------------------------------------
static NSString *DMCCPGestures(UIView *v) {
    NSMutableArray *o = [NSMutableArray array];
    for (UIGestureRecognizer *g in v.gestureRecognizers) [o addObject:[NSString stringWithFormat:@"%@%@", NSStringFromClass([g class]), g.enabled ? @"" : @"(off)"]];
    return o.count ? [o componentsJoinedByString:@","] : @"-";
}
static void DMCCPTree(void) {   // ccp_tree: the overlay's views two levels down (class, frame, hidden, alpha, touches, recognizers), read-only
    UIViewController *ov = DMCCPFindOverlay();
    if (!ov.isViewLoaded) { DMLog(@"[ccpanel] tree: no overlay yet"); return; }
    DMLog([NSString stringWithFormat:@"[ccpanel] tree: overlay %@ view %@ hidden %d, window %@ level %.0f", NSStringFromClass([ov class]), NSStringFromCGRect(ov.view.frame), ov.view.hidden,
        NSStringFromClass([ov.view.window class]), ov.view.window.windowLevel]);
    for (UIView *v in ov.view.subviews) {
        NSString *extra = @"";
        if ([v isKindOfClass:[UIScrollView class]]) extra = [NSString stringWithFormat:@" content %@ offset %@ inset %@ scroll %d", NSStringFromCGSize(((UIScrollView *)v).contentSize),
            NSStringFromCGPoint(((UIScrollView *)v).contentOffset), NSStringFromUIEdgeInsets(((UIScrollView *)v).contentInset), ((UIScrollView *)v).scrollEnabled];
        DMLog([NSString stringWithFormat:@"[ccpanel]   %@ %@ hidden %d alpha %.2f touches %d gestures %@%@", NSStringFromClass([v class]), NSStringFromCGRect(v.frame), v.hidden, v.alpha, v.userInteractionEnabled, DMCCPGestures(v), extra]);
        for (UIView *s in v.subviews) DMLog([NSString stringWithFormat:@"[ccpanel]     %@ %@ hidden %d alpha %.2f touches %d gestures %@ (%lu subviews)", NSStringFromClass([s class]), NSStringFromCGRect(s.frame), s.hidden, s.alpha,
            s.userInteractionEnabled, DMCCPGestures(s), (unsigned long)s.subviews.count]);
    }
    id lo = DMCCPIvarObject(gCCPGrid ?: DMCCGet(ov, @"moduleCollectionViewController"), "_layoutOptions");
    UIView *back = DMCCPIvarObject(ov, "_backgroundView");
    double weighting = DMCCTypes(back, @"weighting", "d16@0:8") ? ((double (*)(id, SEL))objc_msgSend)(back, NSSelectorFromString(@"weighting")) : -1;
    DMLog([NSString stringWithFormat:@"[ccpanel] tree: layout options %@, backdrop %@ hidden %d alpha %.2f weighting %.2f", lo, NSStringFromClass([back class]), back.hidden, back.alpha, weighting]);
}
static void DMCCPState(void) {   // ccp_state: the panel, its tiles and their frames
    DMLog([NSString stringWithFormat:@"[ccpanel] state: supported %d hooked %d on %d pending %d style-mac %d, overlay %@, panel %@ host alpha %.2f in %@, %lu modules, %lu tiles, expanded %@, page %@, locked %d, build %.2f ms",
        gCCPSupported, gCCPHooked, gCCPOn, gCCPPending, DMCCPStyleIsMac(), NSStringFromClass([gCCPOverlay class]), gCCPPanel ? NSStringFromCGRect(gCCPPanel.frame) : @"-", gCCPHost.alpha,
        NSStringFromClass([gCCPHost.superview class]), (unsigned long)gCCPContainers.count, (unsigned long)gCCPTiles.count, gCCPExpanded ?: @"-", [gCCPDetailTile tileID] ?: @"-", gCCPLocked, gCCPBuildMs]);
    int ccCopies = 0, dressed = 0;   // (Control Center's own status bar copies, and those dressed as our menu bar: none while ours shows, DMCCPanelOwnsCCBars)
    for (UIView *fg in gAllBarCopies.allObjects) {
        if (![NSStringFromClass([fg.window class]) isEqualToString:@"SBControlCenterWindow"]) continue;
        ccCopies++;
        if (objc_getAssociatedObject(fg, kLogoKey)) dressed++;
    }
    DMLog([NSString stringWithFormat:@"[ccpanel] state: Control Center's own status bar copies %d, dressed as our menu bar %d", ccCopies, dressed]);
    for (NSString *mid in gCCPOrder) {
        UIView *cv = gCCPContainers[mid];
        CGRect scr = cv.window ? [cv convertRect:cv.bounds toCoordinateSpace:cv.window.screen.coordinateSpace] : CGRectZero;
        int w = 0, h = 0; DMCCPAppleSize(mid, &w, &h);
        UIView *inner = [gCCPVCOf objectForKey:mid].viewIfLoaded;
        DMLog([NSString stringWithFormat:@"[ccpanel]   %@: %dx%d, frame %@ (screen centre %.0f,%.0f, on the screen %.1f x %.1f; bounds %@, scale %.3f; its controller's view %@ in %@)%@ in %@", mid, w, h, NSStringFromCGRect(cv.frame),
            CGRectGetMidX(scr), CGRectGetMidY(scr), scr.size.width, scr.size.height, NSStringFromCGRect(cv.bounds), cv.transform.a, NSStringFromCGRect(inner.frame), NSStringFromClass([inner.superview class]),
            [gCCPHidden containsObject:mid] ? @" HIDDEN stand-in" : @"", NSStringFromClass([cv.superview class])]);
    }
    for (id<DMCCTile> t in gCCPTiles) {
        UIView *v = [t tileView];
        CGRect scr = v.window ? [v convertRect:v.bounds toCoordinateSpace:v.window.screen.coordinateSpace] : CGRectZero;
        DMLog([NSString stringWithFormat:@"[ccpanel]   tile %@: frame %@ (screen centre %.0f,%.0f)", [t tileID], NSStringFromCGRect(v.frame), CGRectGetMidX(scr), CGRectGetMidY(scr)]);
    }
}
static void DMCCPCheck(void) {   // ccp_check: UIKit's own containment rule for every adopted module (its parent = the controller nearest its view)
    int ok = 0, n = 0;
    SEL near = NSSelectorFromString(@"_viewControllerForAncestor");
    for (UIViewController *vc in gCCPByVC.keyEnumerator.allObjects) {
        n++;
        UIView *sup = vc.viewIfLoaded.superview;
        id nearest = [sup respondsToSelector:near] ? ((id (*)(id, SEL))objc_msgSend)(sup, near) : nil;
        BOOL good = vc.parentViewController == gCCPVC && nearest == gCCPVC && [vc.viewIfLoaded isDescendantOfView:gCCPPanel];
        if (good) ok++;
        else DMLog([NSString stringWithFormat:@"[ccpanel] check %@: parent %@, nearest %@, in our panel %d -- NOT CONSISTENT", [gCCPByVC objectForKey:vc], NSStringFromClass([vc.parentViewController class]),
            NSStringFromClass([nearest class]), [vc.viewIfLoaded isDescendantOfView:gCCPPanel]]);
    }
    DMLog([NSString stringWithFormat:@"[ccpanel] check: %d of %d modules consistent; our controller's parent %@", ok, n, NSStringFromClass([gCCPVC.parentViewController class])]);
}
// ccp_layers_<module>: one adopted container's views four levels down -- class, frame, hidden, alpha, the layer's opacity (model and on screen),
// a transform that is not the identity, running animations -- for a module that is in our panel but does not draw (read-only)
static void DMCCPLayers(NSString *mid) {
    UIView *root = gCCPContainers[mid];
    if (!root) { DMLog([NSString stringWithFormat:@"[ccpanel] layers: %@ not adopted", mid]); return; }
    NSMutableArray *todo = [NSMutableArray arrayWithObject:@[root, @0]];
    int n = 0;
    while (todo.count && n < 40) {
        NSArray *e = todo.firstObject; [todo removeObjectAtIndex:0];
        UIView *v = e[0]; int depth = [e[1] intValue];
        CALayer *l = v.layer, *pl = l.presentationLayer;
        DMLog([NSString stringWithFormat:@"[ccpanel] layers %@%@ %@ hidden %d alpha %.2f opacity %.2f/%.2f%@%@%@", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], NSStringFromClass([v class]),
            NSStringFromCGRect(v.frame), v.hidden, v.alpha, l.opacity, pl ? pl.opacity : -1.0, CATransform3DIsIdentity(l.transform) ? @"" : @" TRANSFORM", l.animationKeys.count ? [@" anim " stringByAppendingString:[l.animationKeys componentsJoinedByString:@","]] : @"",
            l.mask ? @" MASK" : @""]);
        n++;
        if (depth < 4) for (UIView *c in v.subviews) [todo addObject:@[c, @(depth + 1)]];
    }
}
static void DMCCPAPIReport(void) {   // ccp_api: every row of the table as this iPadOS has it
    for (size_t i = 0; i < sizeof(kDMCCPHooks) / sizeof(kDMCCPHooks[0]); i++) {
        Class c = objc_getClass(kDMCCPHooks[i].cls); Method m = c ? class_getInstanceMethod(c, sel_registerName(kDMCCPHooks[i].sel)) : NULL;
        DMLog([NSString stringWithFormat:@"[ccpanel] api hook %@ %s%s", DMCCPRowName(kDMCCPHooks[i].cls, kDMCCPHooks[i].sel, NO, NO), m ? method_getTypeEncoding(m) : "MISSING", kDMCCPHooks[i].part != kDMCCPCore ? " (optional)" : ""]);
    }
    for (size_t i = 0; i < sizeof(kDMCCPNeeds) / sizeof(kDMCCPNeeds[0]); i++) {
        const DMCCPNeedRow *r = &kDMCCPNeeds[i]; Class c = objc_getClass(r->cls);
        const char *t = NULL;
        if (r->ivar) { Ivar iv = c ? class_getInstanceVariable(c, r->sel) : NULL; t = iv ? ivar_getTypeEncoding(iv) : NULL; }
        else { Method m = c ? (r->meta ? class_getClassMethod(c, sel_registerName(r->sel)) : class_getInstanceMethod(c, sel_registerName(r->sel))) : NULL; t = m ? method_getTypeEncoding(m) : NULL; }
        DMLog([NSString stringWithFormat:@"[ccpanel] api %@ %s%s", DMCCPRowName(r->cls, r->sel, r->meta, r->ivar), t ?: "MISSING", r->optional ? " (optional)" : ""]);
    }
}
// ccp_gap_<s>: every frame's interval for s seconds, summed up at the end (late = over 1.5 frames): the spike's measure, no log while it runs.
@interface DMCCPGapWatch : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval last, start, until;
@property (nonatomic) int frames, late, missed; @property (nonatomic) double worst, nominal;
@property (nonatomic, strong) NSMutableArray<NSString *> *lates;
@end
@implementation DMCCPGapWatch
- (void)tick:(CADisplayLink *)l {
    CFTimeInterval now = l.timestamp;
    double nominal = l.targetTimestamp - l.timestamp;
    if (nominal > 0.001) self.nominal = nominal;
    if (self.last > 0) {
        double dt = now - self.last;
        self.frames++;
        if (self.nominal > 0 && dt > self.nominal * 1.5) {
            self.late++; self.missed += (int)lround(dt / self.nominal) - 1;
            if (self.lates.count < 40) [self.lates addObject:[NSString stringWithFormat:@"%.0f:%.1f", (now - self.start) * 1000.0, dt * 1000.0]];
        }
        self.worst = MAX(self.worst, dt);
    }
    self.last = now;
    if (CACurrentMediaTime() > self.until) {
        [l invalidate];
        DMLog([NSString stringWithFormat:@"[ccgap] done: %d frames at %.1f ms, %d late (%d missed), worst %.1f ms; late at ms:interval %@", self.frames, self.nominal * 1000.0, self.late, self.missed,
            self.worst * 1000.0, [self.lates componentsJoinedByString:@" "]]);
    }
}
@end
static DMCCPGapWatch *gCCPGap;
static void DMCCPGapStart(double secs) {
    gCCPGap = [DMCCPGapWatch new];
    gCCPGap.lates = [NSMutableArray array];
    gCCPGap.start = CACurrentMediaTime(); gCCPGap.until = gCCPGap.start + MAX(0.3, MIN(10.0, secs));
    gCCPGap.link = [CADisplayLink displayLinkWithTarget:gCCPGap selector:@selector(tick:)];
    if (@available(iOS 15.0, *)) gCCPGap.link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    DMLog([NSString stringWithFormat:@"[ccgap] start (%.1f s, panel on %d)", secs, gCCPOn]);
    [gCCPGap.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
// ccp_header: Apple's header over the panel -- its status bar copy, the grabber line, the chevron, the sensor indicator (the camera, microphone and
// location use) -- where each is on the screen and whether it shows, next to our panel's frame (read-only)
static NSString *DMCCPScreenRect(UIView *v) {
    if (![v isKindOfClass:[UIView class]]) return @"-";
    CGRect r = v.window ? [v convertRect:v.bounds toCoordinateSpace:v.window.screen.coordinateSpace] : CGRectNull;
    return [NSString stringWithFormat:@"%@ %@ hidden %d alpha %.2f (shown %.2f)", NSStringFromClass([v class]), NSStringFromCGRect(r), v.hidden, v.alpha, DMEffectiveAlpha(v)];
}
static void DMCCPHeader(void) {
    UIViewController *ov = DMCCPFindOverlay();
    UIView *hp = DMCCPIvarObject(ov, "_headerPocketView");
    if (![hp isKindOfClass:[UIView class]]) { DMLog(@"[ccpanel] header: no header pocket view"); return; }
    DMLog([NSString stringWithFormat:@"[ccpanel] header: %@; our panel %@", DMCCPScreenRect(hp), gCCPPanel.window ? NSStringFromCGRect([gCCPPanel convertRect:gCCPPanel.bounds toCoordinateSpace:gCCPPanel.window.screen.coordinateSpace]) : @"-"]);
    for (NSString *name in @[@"_headerLineView", @"_headerChevronView", @"_compactSensorAttributionControl", @"_statusBar", @"_headerBackgroundView", @"_statusLabelView", @"_sensorAttributionExpandedWrapperView", @"_customBackgroundView"])
        DMLog([NSString stringWithFormat:@"[ccpanel] header %@: %@", name, DMCCPScreenRect(DMCCPIvarObject(hp, name.UTF8String))]);
    int showing = DMCCTypes(hp, @"isDisplayingSensorStatus", "B16@0:8") ? ((BOOL (*)(id, SEL))objc_msgSend)(hp, NSSelectorFromString(@"isDisplayingSensorStatus")) : -1;
    CGRect compact = DMCCTypes(hp, @"compactModeFrameForSensorView", kDMCCPRectType "16@0:8") ? ((CGRect (*)(id, SEL))objc_msgSend)(hp, NSSelectorFromString(@"compactModeFrameForSensorView")) : CGRectNull;
    Ivar iv = class_getInstanceVariable(object_getClass(hp), "_sensorAttributionEdgeInsets");
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    UIEdgeInsets ins = UIEdgeInsetsZero;
    if (t && !strncmp(t, "{UIEdgeInsets=", 14)) memcpy(&ins, (uint8_t *)(__bridge void *)hp + ivar_getOffset(iv), sizeof ins);
    DMLog([NSString stringWithFormat:@"[ccpanel] header: sensor status shown %d, compact frame %@ (header space), sensor insets %@; the overlay's leading status bar %@", showing, NSStringFromCGRect(compact),
        t ? NSStringFromUIEdgeInsets(ins) : @"?", DMCCPScreenRect(DMCCPIvarObject(ov, "_compactLeadingStatusBar"))]);
}
// ccp_keys: who has the hardware keyboard now (SpringBoard's keyboard focus: the app scene holding it, or none) -- read-only
static void DMCCPKeys(void) {
    id kfc = DMKeyboardFocusController();
    id scene = MSBDFocusHas(kfc, NSSelectorFromString(@"externalSceneWithFocus"), @"@@:") ? DMCall(kfc, @"externalSceneWithFocus") : nil;
    UIWindow *key = nil;
    for (UIWindow *w in DMAllWindows()) if (w.isKeyWindow) { key = w; break; }
    DMLog([NSString stringWithFormat:@"[ccpanel] keys: hardware keyboard %d, focus controller %@, the app scene with the focus %@ (%@), SpringBoard's key window %@ level %.0f, Control Center up %d, panel on %d, an assistive feature %d",
        DMHardwareKeyboardAttached(), kfc ? NSStringFromClass([kfc class]) : @"-", scene ? NSStringFromClass([scene class]) : @"none", DMBundleOfSceneID(scene) ?: @"-", key ? NSStringFromClass([key class]) : @"-", key.windowLevel,
        DMControlCenterActive(), DMCCPanelOn(), DMAXRunning()]);
}
// ccp_focus: what the assistive features have in focus now -- VoiceOver's (or Switch Control's) element, the focus system's item in Control Center's
// window (Full Keyboard Access moves that one) -- with its label and frame on the screen (read-only)
static NSString *DMCCPFocusName(id f) {
    if (!f) return @"none";
    NSString *label = [f respondsToSelector:@selector(accessibilityLabel)] ? [f accessibilityLabel] : nil;
    CGRect r = [f respondsToSelector:@selector(accessibilityFrame)] ? [f accessibilityFrame] : CGRectNull;
    return [NSString stringWithFormat:@"%@ \"%@\" %@%@", NSStringFromClass([f class]), label ?: @"", NSStringFromCGRect(r), [f isKindOfClass:[UIView class]] && [(UIView *)f isDescendantOfView:gCCPPanel] ? @" (in our panel)" : @""];
}
static void DMCCPFocus(void) {
    id vo = UIAccessibilityFocusedElement(UIAccessibilityNotificationVoiceOverIdentifier) ?: UIAccessibilityFocusedElement(UIAccessibilityNotificationSwitchControlIdentifier);
    UIWindow *ccw = gCCPHost.window;
    id item = nil;
    if (ccw) { UIFocusSystem *fs = [UIFocusSystem focusSystemForEnvironment:ccw]; item = fs.focusedItem; }
    DMLog([NSString stringWithFormat:@"[ccpanel] focus: VoiceOver %d %@; focus system in %@: %@; an assistive feature %d", UIAccessibilityIsVoiceOverRunning(), DMCCPFocusName(vo),
        ccw ? NSStringFromClass([ccw class]) : @"no window", DMCCPFocusName(item), DMAXRunning()]);
}
// ccp_vol: the media volume as the Sound tile reads it, exactly (to put it back after a test; read-only)
static void DMCCPVolume(void) {
    id av = DMCCTypes(objc_getClass("AVSystemController"), @"sharedAVSystemController", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(objc_getClass("AVSystemController"), NSSelectorFromString(@"sharedAVSystemController")) : nil;
    float v = -1; NSString *name = nil;
    BOOL ok = av && DMCCTypes(av, @"getActiveCategoryVolume:andName:", "B32@0:8^f16^@24") && ((BOOL (*)(id, SEL, float *, NSString **))objc_msgSend)(av, NSSelectorFromString(@"getActiveCategoryVolume:andName:"), &v, &name);
    DMLog([NSString stringWithFormat:@"[ccpanel] volume: %@ %.6f (%@)", ok ? @"read" : @"not read", v, name ?: @"-"]);
}
// ccp_axescape: VoiceOver's escape (its two-finger scrub) as UIKit hands it on: -accessibilityPerformEscape to the element in VoiceOver's focus, then
// to each view above it until one takes it
static void DMCCPAXEscape(void) {
    id f = UIAccessibilityFocusedElement(UIAccessibilityNotificationVoiceOverIdentifier);
    NSString *answered = @"nobody";
    for (id v = f; v; v = [v isKindOfClass:[UIView class]] ? [(UIView *)v superview] : nil) if ([v accessibilityPerformEscape]) { answered = NSStringFromClass([v class]); break; }
    DMLog([NSString stringWithFormat:@"[ccpanel] VoiceOver's escape from %@: taken by %@", f ? NSStringFromClass([f class]) : @"no focus", answered]);
}
// ccp_dump_<name>: Apple's Control Center as it is now, into /tmp/msb-ccp-dump-<name>.txt (read-only) -- every view of Apple's overlay (ours left
// out; a module's own views four levels under its container: deeper is its content) with its frame, size, transform, alpha, hidden flag, touches
// and recognizers, a material's weighting; the header's own alphas; the grid's controllers and views in their order, the overlay's controllers;
// Control Center's status bar copies (dressed as our bar or not, held or not); what the panel keeps of Apple's. iPadOS's look after a live switch
// compared line for line with a start's (1.8.0 regression F1).
static void DMCCPDumpView(UIView *v, int depth, int below, NSMutableString *out, int *n) {
    if (!v || v == (UIView *)gCCPHost || *n > 2000) return;
    (*n)++;
    NSMutableString *l = [NSMutableString stringWithFormat:@"%@%@ f%@ b%@", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], NSStringFromClass([v class]),
        NSStringFromCGRect(v.frame), NSStringFromCGSize(v.bounds.size)];
    if (!CGAffineTransformIsIdentity(v.transform)) [l appendFormat:@" t%@", NSStringFromCGAffineTransform(v.transform)];
    else if (!CATransform3DIsIdentity(v.layer.transform)) [l appendString:@" t3D"];
    [l appendFormat:@" a%.3f h%d", v.alpha, v.hidden];
    if (fabs(v.layer.opacity - v.alpha) > 0.0005) [l appendFormat:@" o%.3f", v.layer.opacity];
    if (!v.userInteractionEnabled) [l appendString:@" noTouch"];
    if (v.clipsToBounds) [l appendString:@" clip"];
    if (DMCCTypes(v, @"weighting", "d16@0:8")) [l appendFormat:@" weighting %.3f", ((double (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"weighting"))];
    NSString *mid = [v isKindOfClass:objc_getClass(kDMCCPContainerView)] ? DMCCPModuleID(v) : nil;
    if (mid) [l appendFormat:@" module %@", mid];
    for (UIGestureRecognizer *g in v.gestureRecognizers) [l appendFormat:@" g:%@%@", NSStringFromClass([g class]), g.enabled ? @"" : @"(off)"];
    [out appendFormat:@"%@\n", l];
    if (mid) below = 0; else if (below >= 0) below++;
    if (below >= 4) return;
    for (UIView *s in v.subviews) DMCCPDumpView(s, depth + 1, below, out, n);
}
static void DMCCPDump(NSString *name) {
    UIViewController *ov = DMCCPFindOverlay();
    NSMutableString *out = [NSMutableString stringWithFormat:@"dump %@: style-mac %d on %d hooked %d shown %d presentationState %lld\n", name, DMCCPStyleIsMac(), gCCPOn, gCCPHooked, gCCPShown, DMCCPPresentationState()];
    if (!ov.isViewLoaded) { [out appendString:@"no overlay yet\n"]; }
    else {
        UIViewController *grid = gCCPGrid ?: DMCCGet(ov, @"moduleCollectionViewController");
        UIView *home = DMCCGet(grid, @"moduleCollectionView"), *hp = DMCCPIvarObject(ov, "_headerPocketView");
        NSMutableArray *a = [NSMutableArray array];
        for (UIViewController *c in ov.childViewControllers) [a addObject:NSStringFromClass([c class])];
        [out appendFormat:@"overlay children: %@\n", [a componentsJoinedByString:@" "]];
        [a removeAllObjects]; for (UIViewController *c in grid.childViewControllers) [a addObject:DMCCPModuleID(c) ?: NSStringFromClass([c class])];
        [out appendFormat:@"grid children: %@\n", [a componentsJoinedByString:@" "]];
        [a removeAllObjects]; for (UIView *s in home.subviews) [a addObject:DMCCPModuleID(s) ?: NSStringFromClass([s class])];
        [out appendFormat:@"grid views (%@): %@\n", NSStringFromClass([home class]), [a componentsJoinedByString:@" "]];
        for (NSString *g in @[@"statusBarAlpha", @"contentAlphaMultiplier", @"chevronAlpha", @"sensorStatusViewAlpha"])
            if (DMCCTypes(hp, g, "d16@0:8")) [out appendFormat:@"header %@ %.3f\n", g, ((double (*)(id, SEL))objc_msgSend)(hp, NSSelectorFromString(g))];
        UIView *back = DMCCPIvarObject(ov, "_backgroundView");   // (this overlay's: gCCPOverlay is set only once the panel has been on)
        [out appendFormat:@"backdrop %@ hidden %d alpha %.3f\n", NSStringFromClass([back class]), back.hidden, back.alpha];
        int n = 0;
        DMCCPDumpView(ov.view, 0, -1, out, &n);
        [out appendFormat:@"(%d views)\n", n];
    }
    for (UIView *fg in gAllBarCopies.allObjects) {   // (Control Center's status bar copies: the header's, inside CCUIStatusBar, and the full-width one)
        if (![NSStringFromClass([fg.window class]) isEqualToString:@"SBControlCenterWindow"]) continue;
        BOOL inHeader = NO; for (UIView *v = fg.superview; v; v = v.superview) if ([NSStringFromClass([v class]) isEqualToString:@"CCUIStatusBar"]) { inHeader = YES; break; }
        UIView *modern = fg.superview.superview;
        [out appendFormat:@"bar copy %@: frame %@ alpha %.3f shown %.3f hidden %d, dressed %d held %d, its bar %@ alpha %.3f\n", inHeader ? @"in the header" : @"full width", NSStringFromCGRect(fg.frame), fg.alpha, DMEffectiveAlpha(fg),
            fg.hidden, objc_getAssociatedObject(fg, kLogoKey) != nil, [objc_getAssociatedObject(fg, kHoldKey) boolValue], NSStringFromClass([modern class]), modern.alpha];
    }
    [out appendFormat:@"kept: backdrop %d, headers %lu, containers %lu\n", gCCPHidBackdrop != nil, (unsigned long)gCCPAppleBarHeaders.allObjects.count, (unsigned long)gCCPAppleKeeps.count];
    for (UIView *h in gCCPAppleBarHeaders.allObjects) { MSBDCCApple k = DMCCPAppleBarOf(h); [out appendFormat:@"kept: a header's status bar alpha %.3f (kept %d)\n", k.apple, k.kept]; }
    for (DMCCPAppleKeep *k in gCCPAppleKeeps) [out appendFormat:@"kept: %@ after %lu views in %@, hidden %d, %lu transforms, %lu alphas\n", DMCCPModuleID(k.cv) ?: @"?", (unsigned long)k.before.count, NSStringFromClass([k.home class]), k.hidden,
        (unsigned long)k.transforms.count, (unsigned long)k.alphas.count];
    NSString *path = [NSString stringWithFormat:@"/tmp/msb-ccp-dump-%@.txt", name];
    BOOL ok = [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    DMLog([NSString stringWithFormat:@"[ccpanel] dump %@: %@ (%lu lines)", name, ok ? path : @"NOT written", (unsigned long)[out componentsSeparatedByString:@"\n"].count - 1]);
}
static void DMCCPDebugTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"ccp_state"]) DMCCPState();
    else if ([cmd hasPrefix:@"ccp_dump_"]) DMCCPDump([cmd substringFromIndex:9]);
    else if ([cmd isEqualToString:@"ccp_axescape"]) DMCCPAXEscape();
    else if ([cmd isEqualToString:@"ccp_focus"]) DMCCPFocus();
    else if ([cmd isEqualToString:@"ccp_vol"]) DMCCPVolume();
    else if ([cmd isEqualToString:@"ccp_header"]) DMCCPHeader();
    else if ([cmd isEqualToString:@"ccp_keys"]) DMCCPKeys();
    else if ([cmd isEqualToString:@"ccp_tree"]) DMCCPTree();
    else if ([cmd isEqualToString:@"ccp_check"]) DMCCPCheck();
    else if ([cmd isEqualToString:@"ccp_api"]) DMCCPAPIReport();
    else if ([cmd isEqualToString:@"ccp_apply"]) DMCCPApplyStyle(@"debug");
    else if ([cmd hasPrefix:@"ccp_gap_"]) DMCCPGapStart([[cmd substringFromIndex:8] doubleValue]);
    else if ([cmd isEqualToString:@"ccp_open"] || [cmd isEqualToString:@"ccp_close"]) {   // (Apple's own present / dismiss, as our Control Center icon calls them)
        id cc = DMControlCenterController();
        SEL s = NSSelectorFromString([cmd hasSuffix:@"_open"] ? @"presentAnimated:" : @"dismissAnimated:");
        if (DMCCTypes(cc, NSStringFromSelector(s), "v20@0:8B16")) ((void (*)(id, SEL, BOOL))objc_msgSend)(cc, s, YES);
        DMLog([NSString stringWithFormat:@"[ccpanel] %@ through %@", cmd, cc ? NSStringFromClass([cc class]) : @"no controller"]);
    }
    else if ([cmd hasPrefix:@"ccp_expand_"]) { NSString *mid = [cmd substringFromIndex:11]; DMLog([NSString stringWithFormat:@"[ccpanel] expand %@: %d", mid, DMCCPanelExpandModule(mid)]); }
    else if ([cmd hasPrefix:@"ccp_detail_"]) {
        NSString *tid = [cmd substringFromIndex:11];
        for (id<DMCCTile> t in gCCPTiles) if ([[t tileID] isEqualToString:tid]) DMCCPanelOpenDetail(t);
    }
    else if ([cmd isEqualToString:@"ccp_back"]) DMCCPanelCloseDetail(YES);
    else if ([cmd hasPrefix:@"ccp_layers_"]) DMCCPLayers([cmd substringFromIndex:11]);
    else if ([cmd hasPrefix:@"ccp_first_"]) {   // ccp_first_<module>: that module first in the user's list, as a drag in Settings (tests: a reorder while running)
        NSString *mid = [cmd substringFromIndex:10];
        id provider = DMCCSettingsProvider();
        NSArray *list = DMCCGet(provider, @"orderedUserEnabledModuleIdentifiers");
        if (![list isKindOfClass:[NSArray class]] || ![list containsObject:mid]) { DMLog([NSString stringWithFormat:@"[ccpanel] first %@: not in the user's list", mid]); return; }
        NSMutableArray *m = [list mutableCopy]; [m removeObject:mid]; [m insertObject:mid atIndex:0];
        ((void (*)(id, SEL, id))objc_msgSend)(provider, NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:"), m);
        DMLog([NSString stringWithFormat:@"[ccpanel] first %@: the user's list now starts %@", mid, [[m subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, m.count))] componentsJoinedByString:@", "]]);
    }
}
#endif
