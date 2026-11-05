// CC18Shape.h -- our own Control Center on iPadOS 18 (Control Center Style Mac; 1.8.0 P5b, plans/control-center-1.8.0.md 1.3; the P5 spike's path
// (b), plans/control-center-evidence/p5-18/; KT 3 Nov ~16:10): Apple's own 18 Control Center re-shaped into the Mac panel. On 18 every tile --
// Apple's modules and the WidgetKit controls alike -- is a SpringBoardHome icon view on Apple's paging controller's icon lists, which Apple tears
// down and builds again as its pages scroll, drags and resizes in edit mode and takes out of its parent for an expansion: adopting them into a
// panel of ours (15-17, CCPanel.h) would be an icon engine of our own (the spike's NO-GO for path (a)). So the tiles stay Apple's, in Apple's
// grid, and the grid is told where to go:
//  - one answer: -[CCUIOverlayStatusBarPresentationProvider _edgeInsetsForContentSize:withinBounds:contentEdgeInsets:orientation:], the insets
//    Apple lays its grid out with (common/CCLayout.h MSBDCC18Insets, Mac-tested): the tiles under our menu bar at the screen's right (left in a
//    right-to-left language), where the 15-17 panel's are. Everything of Apple's that follows the grid's place follows by itself: the
//    presentation's module motion, expanded modules out of their tiles and back, edit mode, the gallery, the controls, the pages;
//  - our material behind the tiles (the panel: our menus' material, kept dark -- Apple's 18 content is white on dark in both appearances),
//    Apple's + (edit) and power buttons in its top row (KT: shown, working as on stock -- Apple's own buttons, moved into our row with their
//    targets; a hold there is the button's own, never edit mode's), Apple's page dots beside it (KT: shown) on a capsule of our material (Apple
//    draws them white for its own backdrop); a tap on the panel's empty places is not a tap outside; Apple's full-screen backdrop and its header
//    (the status bar copy, its labels, the chevron) hidden while the panel shows -- our menu bar stays visible over Control Center;
//  - Apple's look back behind one of its modules opened expanded (its backdrop, our material and row away) and while editing (Apple's insets,
//    header, backdrop and dots: edit mode, the gallery and the controls stay Apple's, KT);
//  - the render server's routing: where SpringBoard's window draws nothing a touch goes to the app beneath (with Apple's backdrop hidden a tap
//    outside the panel reached the app, Control Center stayed open): a full-screen layer hit-tested as opaque, with no fill (a 2 % fill cost every
//    opening 3-4 more long frames than stock on the A12Z, the spike's measure), brings it back to Apple's own dismissal;
//  - our material, row and the dots' capsule fade with Apple's presentation progress; while the pages scroll the panel stays and takes the next
//    page's height once they rest; on the Lock Screen it hangs under our bar as everywhere (our bar's locked look is drawn there: SpringBoard's
//    status bar window over the Cover Sheet, the status icons on its band);
//  - Apple's page dots beside the panel wherever Apple places them: each of its placements (its layout, a presentation step, its own handling
//    of a touch on them) is turned into ours as Apple makes it; and a pull opens the panel on its page wherever it starts -- Apple's pull goes
//    on into its paging when the finger, past the full presentation, is in the dots' area, which beside the panel lay under our status icons;
//    nothing goes on past the full presentation in the panel (Apple shrank its pages about the screen's middle as a paging hint and
//    rubber-banded its tiles down: they slid out of the panel while the finger kept pulling);
//  - Esc on a hardware keyboard goes one level back (what Apple presents closes: an expanded module, the sensor list, edit mode), else
//    Control Center closes -- as the 15-17 panel's page and close;
//  - Apple's sensor attribution (the camera or microphone in use: "Camera" with its dots, a tap opens Apple's list of the apps) in the panel's
//    top row between + and power, as macOS shows what uses them at the top of its Control Center: Apple's header then shows, with nothing of its
//    own but that control, and takes no touch but the control's within the row (an optional part of the table: without it, 1.8.0's panel).
// Everything Apple's is asked through the checked table below (class, method, type encoding, instance variable), all or nothing: one row missing or
// of another shape and nothing is hooked, Control Center stays iPadOS's, and the verdict says why (common/CCMacCheck.h's record, the one CCPanel.h
// writes on 15-17: Settings' Style page, Report a Problem). Mac only when it is the style (common/CCStyle.h as SpringBoard reads it, CCStyleSB.h:
// "mac" stored); false (the crash guard's: tools/crashmap-rules.txt "controlcenter") or any other style is iPadOS's own Control Center, untouched.
// Performance: nothing runs while Control Center is closed; each presentation step sets two alphas in Apple's own animation; our part of Apple's
// layout is a walk over the page's icon views (0.2-0.3 ms in a debug build, the spike).
// Included once by StatusBar.x, after CCPanel.h (its verdict's writer, the style's reader, DMCCPRTL, DMCCPLockedNow).
#pragma once
#include "../common/CCLayout.h"     // (the insets, the panel, its top row and the dots beside it -- plain C, tools/test-cclayout.sh)
#include "../common/CCMacCheck.h"   // (the verdict's record: MSBD_CC_CHECK_KEY)
#include "../common/CC18MacLayout.h" // (the Mac panel's own layout of tiles, 1.8.1 item 1)
#include "../common/Diag.h"

#define kDMCC18Main "CCUIMainViewController"
#define kDMCC18Paging "CCUIPagingViewController"
#define kDMCC18Provider "CCUIOverlayStatusBarPresentationProvider"   // (the iPad's: +[CCUIMainViewController _presentationProviderForDevice], 18.5)
#define kDMCC18Header "CCUIHeaderPocketView"
#define kDMCC18Folder "_TtC15ControlCenterUI22IconListRootFolderView"   // (ControlCenterUI.IconListRootFolderView: Control Center's pages' root folder view)
#define kDMCC18RectT "{CGRect={CGPoint=dd}{CGSize=dd}}"
#define kDMCC18InsetsT "{UIEdgeInsets=dddd}"

// ---- state ---------------------------------------------------------------------------------------------------------------------------------
static BOOL gCC18Supported = NO;   // iPadOS 18, the API check passed (DMCC18Init)
static BOOL gCC18Hooked = NO;      // our hooks are in (Mac was chosen at the start, or since); they only act while gCC18On
static BOOL gCC18On = NO;          // the Mac shape is in force
static BOOL gCC18Pending = NO;     // a style change waits for Control Center to close (DMCC18ApplyStyle)
static unsigned gCC18PendingGen = 0;
static BOOL gCC18Want = NO;        // ours is the style (or will be once Control Center has closed): the menu bar's Control Center icon (BatteryMenu.h)
static BOOL gCC18Shown = NO;       // Control Center shows: its controller's -_willPresent to its -_didDismiss (our hooks; never asked of the controller here)
static BOOL gCC18Editing = NO;     // Apple's edit mode: Apple's whole look while it lasts
static BOOL gCC18Expanded = NO;    // one of Apple's modules is open expanded: Apple's backdrop behind it, our material and row away
static __weak UIViewController *gCC18Main;   // the main screen's CCUIMainViewController (the one shaped)
static UIView *gCC18Material;      // the panel: our material (a blur in a shadowed view) behind Apple's tiles
static UIVisualEffectView *gCC18Blur;
static UIView *gCC18Route;         // the routing layer (full screen, no fill, hit-tested as opaque)
static UIView *gCC18Row;           // the panel's top row: Apple's + and power buttons, moved in
static UIVisualEffectView *gCC18DotsPill;   // our material behind Apple's page dots beside the panel (they are white for Apple's backdrop, hidden here)
static __weak UIView *gCC18Edit, *gCC18Power;      // Apple's buttons while they are in our row ...
static __weak UIView *gCC18ButtonsHome;            // ... the header they came from, and where in it
static NSUInteger gCC18EditAt = NSNotFound, gCC18PowerAt = NSNotFound;
static BOOL gCC18HidBack = NO, gCC18HidHeader = NO;   // what the shape hid (only that is shown again)
static NSHashTable<UIView *> *gCC18HidHeaderParts;    // (the header's own views hidden while it shows only its sensor control: shown again)
static NSURL *gCC18AppleDesired;                      // (Apple's own desired-state file, seen when the store changes: put back with its layout)
static BOOL gCC18HaveSensor = NO;                     // Apple's sensor attribution rows passed: its control in the panel (DMCC18HeaderLook)
static BOOL gCC18HaveTiles = NO;                      // the Mac layout's rows passed: Apple's grid reads the Mac panel's own layout of tiles (DMCC18StoreInit)
static BOOL gCC18HavePull = NO;                       // the pull's rows passed: nothing past the full presentation in the panel (DMCC18PullState)
static BOOL gCC18HaveEsc = NO;                        // Esc's rows passed: one level back or Control Center closes (DMCC18PanelEscape)
static CGPoint gCC18DotsApple, gCC18DotsOurs;            // Apple's page dots: where Apple had them, where we put them (Apple's place back with its look)
static CGRect gCC18DotsAppleBounds;                      // (and the size Apple gave them)
static BOOL gCC18DotsMoved = NO;
static __weak UIView *gCC18Dots;                         // (the page control placed: its setters' hooks know it)
static BOOL gCC18PlacingDots = NO;                       // (our own writes of its place: they pass those hooks)
#if DEBUG
static int gCC18InStep = 0, gCC18InFolder = 0, gCC18InLayoutViews = 0, gCC18InMainLayout = 0;   // (the dots' trace: which of Apple's calls we are in)
#endif
static CGRect gCC18Grid;           // the grid's columns and rows as our insets placed them (the main view's space); empty: not answered yet
static double gCC18PanelTop = 0;   // the panel's top there
static BOOL gCC18GridRTL = NO;
static double gCC18LaidBar = -1;   // (the bar's height our last answer was worked out for: laid out again when it changes)
static unsigned gCC18SettleGen = 0;
static NSMutableArray<NSString *> *gCC18CheckOptional;
static void DMCC18Views(NSString *why);
static void DMCC18Relayout(NSString *why);
static void DMCC18ApplyStyle(NSString *why);
static BOOL DMCC18PanelWanted(void) { return gCC18Want; }

// ---- the API table -------------------------------------------------------------------------------------------------------------------------
// Every method we hook, call or read, with the type encoding read on 18.5 (22F76, the A12Z: the spike's c18_api, plans/control-center-evidence/
// p5-18/hook-table-18.5.txt, and this build's own check).
static UIEdgeInsets (*o_DMCC18Insets)(id, SEL, CGSize, CGRect, UIEdgeInsets, long long);
static void (*o_DMCC18LayoutViews)(id, SEL);
static void (*o_DMCC18MainLayout)(id, SEL);
static void (*o_DMCC18Update)(id, SEL, id, id);
static void (*o_DMCC18Editing)(id, SEL, id, BOOL);
static void (*o_DMCC18WillExpand)(id, SEL, id, id);
static void (*o_DMCC18DidClose)(id, SEL, id, id);
static void (*o_DMCC18DidScroll)(id, SEL, id);
static void (*o_DMCC18WillPresent)(id, SEL);
static void (*o_DMCC18DidDismiss)(id, SEL);
static void (*o_DMCC18HeaderLayout)(id, SEL);
static BOOL (*o_DMCC18TapBegin)(id, SEL, id);
static BOOL (*o_DMCC18EditPressBegin)(id, SEL, id);
static void (*o_DMCC18FolderLayout)(id, SEL);
static void (*o_DMCC18Continue)(id, SEL, CGPoint);
static void (*o_DMCC18ExtendArea)(id, SEL, BOOL);
static void (*o_DMCC18DotsSetCenter)(id, SEL, CGPoint);
static void (*o_DMCC18DotsSetBounds)(id, SEL, CGRect);
static void (*o_DMCC18DotsSetFrame)(id, SEL, CGRect);
static id (*o_DMCC18PullState)(id, SEL, unsigned long long, BOOL, CGPoint);
static CGRect (*o_DMCC18SensorFrame)(id, SEL);
static UIView *(*o_DMCC18HeaderHit)(id, SEL, CGPoint, UIEvent *);
static id (*o_DMCC18StoreInit)(id, SEL, NSURL *, NSURL *);
static UIEdgeInsets DMCC18Insets(id self, SEL _cmd, CGSize size, CGRect bounds, UIEdgeInsets edge, long long orientation);
static void DMCC18LayoutViews(id self, SEL _cmd);
static void DMCC18MainLayout(id self, SEL _cmd);
static void DMCC18Update(id self, SEL _cmd, id state, id completion);
static void DMCC18Editing(id self, SEL _cmd, id paging, BOOL editing);
static void DMCC18WillExpand(id self, SEL _cmd, id paging, id vc);
static void DMCC18DidClose(id self, SEL _cmd, id paging, id vc);
static void DMCC18DidScroll(id self, SEL _cmd, id scrollView);
static void DMCC18WillPresentHook(id self, SEL _cmd);
static void DMCC18DidDismissHook(id self, SEL _cmd);
static void DMCC18HeaderLayout(id self, SEL _cmd);
static BOOL DMCC18TapBegin(id self, SEL _cmd, id gr);
static BOOL DMCC18EditPressBegin(id self, SEL _cmd, id gr);
static void DMCC18FolderLayout(id self, SEL _cmd);
static void DMCC18Continue(id self, SEL _cmd, CGPoint location);
static void DMCC18ExtendArea(id self, SEL _cmd, BOOL extend);
static void DMCC18DotsSetCenter(id self, SEL _cmd, CGPoint c);
static void DMCC18DotsSetBounds(id self, SEL _cmd, CGRect b);
static void DMCC18DotsSetFrame(id self, SEL _cmd, CGRect f);
static id DMCC18PullState(id self, SEL _cmd, unsigned long long type, BOOL interactive, CGPoint translation);
static CGRect DMCC18SensorFrame(id self, SEL _cmd);
static UIView *DMCC18HeaderHit(id self, SEL _cmd, CGPoint p, UIEvent *e);
static id DMCC18StoreInit(id self, SEL _cmd, NSURL *current, NSURL *desired);
static void DMCC18TilesWillPresent(void);   // (CC18Tiles.h)
static void DMCC18TilesDidDismiss(void);
static BOOL DMCC18PagePanelEscape(void);
static void DMCC18PageFollowsPanel(void);
enum { kDMCC18Core = 0, kDMCC18PartSensor, kDMCC18PartTiles, kDMCC18PartPull, kDMCC18PartEsc };   // (a part's rows not there: that part only is left out -- the rest of the panel goes on)
typedef struct { const char *cls, *sel, *enc; void *fn; void **orig; const char *what; int part; } DMCC18HookRow;
static DMCC18HookRow kDMCC18Hooks[] = {
    { kDMCC18Provider, "_edgeInsetsForContentSize:withinBounds:contentEdgeInsets:orientation:", kDMCC18InsetsT "104@0:8{CGSize=dd}16" kDMCC18RectT "32" kDMCC18InsetsT "64q96",
      (void *)DMCC18Insets, (void **)&o_DMCC18Insets, "where Apple lays its grid out (the Mac panel's place)" },
    { kDMCC18Provider, "layoutViews", "v16@0:8", (void *)DMCC18LayoutViews, (void **)&o_DMCC18LayoutViews, "Apple's layout of Control Center: our material, row and the dots after it" },
    { kDMCC18Main, "viewWillLayoutSubviews", "v16@0:8", (void *)DMCC18MainLayout, (void **)&o_DMCC18MainLayout, "the main view's layout (the same)" },
    { kDMCC18Main, "_updatePresentationForTransitionState:withCompletionHander:", "v32@0:8@16@?24", (void *)DMCC18Update, (void **)&o_DMCC18Update, "every presentation step: our material fades with it" },
    { kDMCC18Main, "pagingViewController:editingDidChange:", "v28@0:8@16B24", (void *)DMCC18Editing, (void **)&o_DMCC18Editing, "edit mode: Apple's whole look" },
    { kDMCC18Main, "pagingViewController:willExpand:", "v32@0:8@16@24", (void *)DMCC18WillExpand, (void **)&o_DMCC18WillExpand, "a module opens expanded: Apple's backdrop behind it" },
    { kDMCC18Main, "pagingViewController:didClose:", "v32@0:8@16@24", (void *)DMCC18DidClose, (void **)&o_DMCC18DidClose, "it closed: the panel back" },
    { kDMCC18Main, "scrollViewDidScroll:", "v24@0:8@16", (void *)DMCC18DidScroll, (void **)&o_DMCC18DidScroll, "the pages scroll: the next page's height once they rest" },
    { "SBControlCenterController", "_willPresent", "v16@0:8", (void *)DMCC18WillPresentHook, (void **)&o_DMCC18WillPresent, "Control Center about to show (the Lock Screen's place)" },
    { "SBControlCenterController", "_didDismiss", "v16@0:8", (void *)DMCC18DidDismissHook, (void **)&o_DMCC18DidDismiss, "Control Center closed (a style change waiting)" },
    { kDMCC18Header, "layoutSubviews", "v16@0:8", (void *)DMCC18HeaderLayout, (void **)&o_DMCC18HeaderLayout, "Apple's + and power buttons kept in our row" },
    { kDMCC18Main, "_dismissalTapGestureRecognizerShouldBegin:", "B24@0:8@16", (void *)DMCC18TapBegin, (void **)&o_DMCC18TapBegin, "a tap in our panel is not a tap outside" },
    { kDMCC18Main, "_editingLongPressGestureRecognizerShouldBegin:", "B24@0:8@16", (void *)DMCC18EditPressBegin, (void **)&o_DMCC18EditPressBegin, "a hold on the + or power button in our row is not edit mode's" },
    { kDMCC18Folder, "layoutSubviews", "v16@0:8", (void *)DMCC18FolderLayout, (void **)&o_DMCC18FolderLayout, "Apple's page dots placed again beside the panel after Apple places them" },
    { kDMCC18Main, "_evaluatePresentationContinuationIntoPagingWithLocation:", "v32@0:8{CGPoint=dd}16", (void *)DMCC18Continue, (void **)&o_DMCC18Continue, "a pull goes on into Apple's paging: not in the panel (it opens on its page)" },
    { kDMCC18Folder, "setShouldExtendAreaForPagingContinuation:", "v20@0:8B16", (void *)DMCC18ExtendArea, (void **)&o_DMCC18ExtendArea, "the area Apple makes for that while a pull lasts: none in the panel" },
    { "SBIconListPageControl", "setCenter:", "v32@0:8{CGPoint=dd}16", (void *)DMCC18DotsSetCenter, (void **)&o_DMCC18DotsSetCenter, "Apple places its page dots: beside the panel at once" },
    { "SBIconListPageControl", "setBounds:", "v48@0:8" kDMCC18RectT "16", (void *)DMCC18DotsSetBounds, (void **)&o_DMCC18DotsSetBounds, "(the same, their size)" },
    { "SBIconListPageControl", "setFrame:", "v48@0:8" kDMCC18RectT "16", (void *)DMCC18DotsSetFrame, (void **)&o_DMCC18DotsSetFrame, "(the same, their frame)" },
    { kDMCC18Provider, "transitionStateForType:interactive:translation:", "@44@0:8Q16B24{CGPoint=dd}28", (void *)DMCC18PullState, (void **)&o_DMCC18PullState, "a pull's transition state: nothing past the full presentation in the panel (Apple's paging hint and rubber band took the tiles out of it)", kDMCC18PartPull },
    { kDMCC18Header, "compactModeFrameForSensorView", kDMCC18RectT "16@0:8", (void *)DMCC18SensorFrame, (void **)&o_DMCC18SensorFrame, "Apple's sensor attribution in the panel's top row", kDMCC18PartSensor },
    { kDMCC18Header, "hitTest:withEvent:", "@40@0:8{CGPoint=dd}16@32", (void *)DMCC18HeaderHit, (void **)&o_DMCC18HeaderHit, "the header takes only its sensor control's touches in the panel's row", kDMCC18PartSensor },
    { "SBIconModelPropertyListFileStore", "initWithIconStateURL:desiredIconStateURL:", "@32@0:8@16@24", (void *)DMCC18StoreInit, (void **)&o_DMCC18StoreInit, "the Mac panel's own layout of tiles (Apple's file untouched)", kDMCC18PartTiles },
};
// The calls and reads (instance methods; "ivar": any object type, checked by class when read).
typedef struct { const char *cls, *sel, *enc; BOOL ivar; const char *what; BOOL meta; int part; } DMCC18NeedRow;   // (meta: a class method)
static const DMCC18NeedRow kDMCC18Needs[] = {
    { "SBControlCenterController", "viewController", "@16@0:8", NO, "Apple's Control Center (a style change while running)" },
    { kDMCC18Main, "pagingViewController", "@16@0:8", NO, "Apple's pages" },
    { kDMCC18Main, "overlayBackgroundView", "@16@0:8", NO, "Apple's full-screen backdrop (hidden while the panel shows)" },
    { kDMCC18Main, "overlayHeaderView", "@16@0:8", NO, "Apple's header (hidden while the panel shows)" },
    { kDMCC18Main, "overlayPageControl", "@16@0:8", NO, "Apple's page dots (beside the panel)" },
    { kDMCC18Main, "isEditing", "B16@0:8", NO, "edit mode (a style change while editing)" },
    { kDMCC18Main, "_presentationProvider", NULL, YES, "Apple's layout (laid out again for a style change)" },
    { kDMCC18Provider, "viewProvider", "@16@0:8", NO, "the provider's Control Center" },
    { kDMCC18Paging, "currentIconlistView", "@16@0:8", NO, "the page that shows (the panel's height)" },
    { kDMCC18Paging, "scrollView", "@16@0:8", NO, "the pages' scroll view (the panel stays while they scroll)" },
    { "SBIconView", "icon", "@16@0:8", NO, "the tiles are SpringBoardHome icon views" },
    { kDMCC18Header, "editButton", "@16@0:8", NO, "Apple's + button (in the panel's top row)" },
    { kDMCC18Header, "powerButton", "@16@0:8", NO, "Apple's power button (in the panel's top row)" },
    { "CCUIOverlayTransitionState", "presentationProgress", "d16@0:8", NO, "the presentation's progress" },
    { "CCUIOverlayTransitionState", "isInteractive", "B16@0:8", NO, "a finger pull" },
    { "CCUIOverlayTransitionState", "progress", "d16@0:8", NO, "a pull's progress (at most the full presentation in the panel)", NO, kDMCC18PartPull },
    { "CCUIOverlayTransitionState", "pagingProgress", "d16@0:8", NO, "a pull's paging part past the full presentation (none in the panel)", NO, kDMCC18PartPull },
    { "CCUIOverlayTransitionState", "stateWithType:interactive:progress:pagingProgress:", "@44@0:8Q16B24d28d36", NO, "(Apple's own factory of a transition state: the pull's, made again)", YES, kDMCC18PartPull },
    { kDMCC18Main, "canDismissPresentedContent", "B16@0:8", NO, "Esc: content Apple presents (an expanded module, the sensor list, edit mode: it closes first)", NO, kDMCC18PartEsc },
    { kDMCC18Main, "dismissPresentedContentAnimated:completion:", "v28@0:8B16@?20", NO, "Esc: Apple's own closing of it", NO, kDMCC18PartEsc },
    { "SBControlCenterController", "dismissAnimated:", "v20@0:8B16", NO, "Esc: Control Center closes (Apple's own animated dismissal)", NO, kDMCC18PartEsc },
    { kDMCC18Header, "isDisplayingSensorStatus", "B16@0:8", NO, "Apple's sensor attribution shows (the camera or microphone in use)", NO, kDMCC18PartSensor },
    { kDMCC18Header, "compactSensorAttributionControl", "@16@0:8", NO, "its control (in the panel's top row)", NO, kDMCC18PartSensor },
    { kDMCC18Paging, "iconModel", "@16@0:8", NO, "Apple's model of the tiles (the layout that goes with the style)", NO, kDMCC18PartTiles },
    { "SBHIconModel", "store", "@16@0:8", NO, "the file it reads and saves", NO, kDMCC18PartTiles },
    { "SBHIconModel", "setStore:", "v24@0:8@16", NO, "(the other style's file)", NO, kDMCC18PartTiles },
    { "SBHIconModel", "layout", "v16@0:8", NO, "(read again from it, as Apple's reset to the default layout)", NO, kDMCC18PartTiles },
    { "SBHIconModel", "saveIconStateIfNeeded", "B16@0:8", NO, "(the file it leaves saved)", NO, kDMCC18PartTiles },
    { "SBHIconModel", "isIconStateDirty", "B16@0:8", NO, "(... and clean)", NO, kDMCC18PartTiles },
    { "SBHIconModel", "rootFolder", "@16@0:8", NO, "(the tiles' root folder)", NO, kDMCC18PartTiles },
    { "SBFolder", "addFolderObserver:", "v24@0:8@16", NO, "(Control Center follows the new root folder)", NO, kDMCC18PartTiles },
    { "SBFolder", "removeFolderObserver:", "v24@0:8@16", NO, "(... off the old one)", NO, kDMCC18PartTiles },
    { "SBRootFolder", "setDelegate:", "v24@0:8@16", NO, "(... its delegate too)", NO, kDMCC18PartTiles },
    { "SBIconModelPropertyListFileStore", "currentIconStateURL", "@16@0:8", NO, "(which file a store has)", NO, kDMCC18PartTiles },
    { "SBIconModelPropertyListFileStore", "desiredIconStateURL", "@16@0:8", NO, "(and its desired state's)", NO, kDMCC18PartTiles },
    { "CALayer", "setHitTestsAsOpaque:", "v20@0:8B16", NO, "the routing layer (a tap outside closes Control Center, never reaches the app)" },
};
static NSString *DMCC18RowProblem(const char *cls, const char *sel, const char *enc, BOOL ivar, BOOL meta) {
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
    return strcmp(t, enc) ? [NSString stringWithFormat:@"is %s, we use %s", t, enc] : nil;
}
// The whole table: the rows that fail (nothing is hooked then). debug /tmp/msb-cc18-simulate-missing: one row pretends to be missing (the
// all-or-nothing path, the Style page's greyed row).
static NSArray<NSString *> *DMCC18CheckAPI(NSUInteger *checked) {
    NSMutableArray *bad = [NSMutableArray array];
    NSUInteger n = 0;
    BOOL sensor = YES, tiles = YES, pull = YES, esc = YES;
    for (size_t i = 0; i < sizeof(kDMCC18Hooks) / sizeof(kDMCC18Hooks[0]); i++) {
        n++;
        NSString *p = DMCC18RowProblem(kDMCC18Hooks[i].cls, kDMCC18Hooks[i].sel, kDMCC18Hooks[i].enc, NO, NO);
        if (!p) continue;
        NSString *line = [NSString stringWithFormat:@"-[%s %s] %@ (%s)", kDMCC18Hooks[i].cls, kDMCC18Hooks[i].sel, p, kDMCC18Hooks[i].what];
        if (kDMCC18Hooks[i].part == kDMCC18PartSensor) { sensor = NO; [gCC18CheckOptional addObject:line]; }
        else if (kDMCC18Hooks[i].part == kDMCC18PartTiles) { tiles = NO; [gCC18CheckOptional addObject:line]; }
        else if (kDMCC18Hooks[i].part == kDMCC18PartPull) { pull = NO; [gCC18CheckOptional addObject:line]; }
        else if (kDMCC18Hooks[i].part == kDMCC18PartEsc) { esc = NO; [gCC18CheckOptional addObject:line]; }
        else [bad addObject:line];
    }
    for (size_t i = 0; i < sizeof(kDMCC18Needs) / sizeof(kDMCC18Needs[0]); i++) {
        const DMCC18NeedRow *r = &kDMCC18Needs[i];
        n++;
        NSString *p = DMCC18RowProblem(r->cls, r->sel, r->enc, r->ivar, r->meta);
        if (!p) continue;
        NSString *line = [NSString stringWithFormat:@"%@ %@ (%s)", r->ivar ? [NSString stringWithFormat:@"%s.%s", r->cls, r->sel] : [NSString stringWithFormat:@"%c[%s %s]", r->meta ? '+' : '-', r->cls, r->sel], p, r->what];
        if (r->part == kDMCC18PartSensor) { sensor = NO; [gCC18CheckOptional addObject:line]; }
        else if (r->part == kDMCC18PartTiles) { tiles = NO; [gCC18CheckOptional addObject:line]; }
        else if (r->part == kDMCC18PartPull) { pull = NO; [gCC18CheckOptional addObject:line]; }
        else if (r->part == kDMCC18PartEsc) { esc = NO; [gCC18CheckOptional addObject:line]; }
        else [bad addObject:line];
    }
    gCC18HaveSensor = sensor; gCC18HaveTiles = tiles; gCC18HavePull = pull; gCC18HaveEsc = esc;
#if DEBUG
    if (DMTestFlag("/tmp/msb-cc18-simulate-missing")) [bad addObject:@"-[CCUIOverlayStatusBarPresentationProvider layoutViews] missing (SIMULATED, debug)"];
    if (DMTestFlag("/tmp/msb-cc18-simulate-nopull")) { gCC18HavePull = NO; [gCC18CheckOptional addObject:@"-[CCUIOverlayStatusBarPresentationProvider transitionStateForType:interactive:translation:] missing (SIMULATED, debug)"]; }
    if (DMTestFlag("/tmp/msb-cc18-simulate-noesc")) { gCC18HaveEsc = NO; [gCC18CheckOptional addObject:@"-[CCUIMainViewController canDismissPresentedContent] missing (SIMULATED, debug)"]; }
#endif
    if (checked) *checked = n;
    return bad;
}
// The hooks, all or nothing, tried once (a second try would hook again the rows that went in: their originals would be our own functions). One
// that did not take its hook: the shape stays off this run (the rows that went in only pass through) and the verdict says so. Main thread: at
// the start, or when Mac is chosen while running.
static BOOL DMCC18HookLeftOut(int part) {   // (Esc's part has no hook: its calls ask gCC18HaveEsc)
    return (part == kDMCC18PartSensor && !gCC18HaveSensor) || (part == kDMCC18PartTiles && !gCC18HaveTiles) || (part == kDMCC18PartPull && !gCC18HavePull);
}
static BOOL DMCC18InstallHooks(void) {
    static BOOL tried = NO;
    if (gCC18Hooked) return YES;
    if (!gCC18Supported || tried) return NO;
    tried = YES;
    int count = 0;
    for (size_t i = 0; i < sizeof(kDMCC18Hooks) / sizeof(kDMCC18Hooks[0]); i++) {
        if (DMCC18HookLeftOut(kDMCC18Hooks[i].part)) continue;
        MSHookMessageEx(objc_getClass(kDMCC18Hooks[i].cls), sel_registerName(kDMCC18Hooks[i].sel), (IMP)kDMCC18Hooks[i].fn, (IMP *)kDMCC18Hooks[i].orig);
        count++;
    }
    for (size_t i = 0; i < sizeof(kDMCC18Hooks) / sizeof(kDMCC18Hooks[0]); i++) {
        if (*kDMCC18Hooks[i].orig || DMCC18HookLeftOut(kDMCC18Hooks[i].part)) continue;
        DMLog([NSString stringWithFormat:@"[cc18] the hook on -[%s %s] did not go in: the Mac shape stays off", kDMCC18Hooks[i].cls, kDMCC18Hooks[i].sel]);
        gCC18Supported = NO;
        DMCCPPublishVerdict(NO, [NSString stringWithFormat:@"%@: a system method our Control Center uses did not take its hook", DMCCPOSLabel()],
                            @[[NSString stringWithFormat:@"-[%s %s] did not take our hook (%s)", kDMCC18Hooks[i].cls, kDMCC18Hooks[i].sel, kDMCC18Hooks[i].what]], gCC18CheckOptional);
        return NO;
    }
    gCC18Hooked = YES;
    DMLog([NSString stringWithFormat:@"[cc18] hooks in (%d; Apple's sensor attribution in the panel %d, the Mac layout %d, the pull's end %d, Esc %d)", count, gCC18HaveSensor, gCC18HaveTiles, gCC18HavePull, gCC18HaveEsc]);
    return YES;
}

// ---- small readers -------------------------------------------------------------------------------------------------------------------------
// The main screen's Control Center: a CCUIMainViewController whose view is on the iPad's own screen (or not in a window yet). Learned from Apple's
// own calls into our hooks (never by asking the scene's controller there: Apple calls them inside the controller's own build, P4's i11 trap).
static UIViewController *DMCC18MainIfOurs(id vc) {
    static Class main; if (!main) main = objc_getClass(kDMCC18Main);
    if (!vc || ![vc isKindOfClass:main]) return nil;
    UIViewController *m = vc;
    UIWindow *w = m.viewIfLoaded.window;
    if (w && w.screen != [UIScreen mainScreen]) return nil;
    if (gCC18Main != m) gCC18Main = m;
    return m;
}
// ... or, outside Apple's calls (a style change while running, SpringBoard's first seconds too), the main scene's controller's as SpringBoard made it, nil before. Asking makes
// nothing: the scene, its delegate, its context and -viewController only read theirs (18.5). As CCPanel.h's DMCCPFindOverlay (1.8.1 item 16): gCC18On means applied, or to be
// applied as Apple builds it: Apple's -viewDidLoad makes the tiles' store (our hook picks the file then, DMCC18StoreInit), so a loaded view is the live steps, any other Apple's build.
static UIViewController *DMCC18FindMain(void) {
    if (gCC18Main) return gCC18Main;
    return DMCC18MainIfOurs(DMCCGet(DMControlCenterController(), @"viewController"));
}
static UIView *DMCC18ViewOf(id owner, NSString *getter) { id v = DMCCGet(owner, getter); return [v isKindOfClass:[UIView class]] ? v : nil; }
static double DMCC18Progress(id state) { return state && DMCCTypes(state, @"presentationProgress", "d16@0:8") ? ((double (*)(id, SEL))objc_msgSend)(state, NSSelectorFromString(@"presentationProgress")) : 1.0; }
static BOOL DMCC18Interactive(id state) { return state && DMCCTypes(state, @"isInteractive", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(state, NSSelectorFromString(@"isInteractive")); }
// The bar the panel hangs under: our menu bar (the Lock Screen's too: its locked look is drawn there).
static double DMCC18PanelTopNow(void) { return MSBDCC18PanelTop(DMMenuBarHeight()); }
// A right-to-left language (the bar is mirrored then: the panel at the left). Debug: /tmp/msb-cc18-rtl mirrors our side of it in any language
// (the panel's place, its top row, the dots), to see it on a device without changing its language; Apple's own content stays as it is then.
static BOOL DMCC18RTL(void) {
#if DEBUG
    if (DMTestFlag("/tmp/msb-cc18-rtl")) return YES;
#endif
    return DMCCPRTL();
}
// The page that shows: its icon views (SpringBoardHome's), and the height they take from its first row in the page's own space (the same while
// the pages scroll; their model frames: the presentation's per-module transforms are not in them).
static double DMCC18RowsHeight(UIViewController *m) {
    UIView *list = DMCC18ViewOf(DMCCGet(m, @"pagingViewController"), @"currentIconlistView");
    static Class iconView; if (!iconView) iconView = objc_getClass("SBIconView");
    double top = INFINITY, bottom = -INFINITY;
    for (UIView *v in list.subviews) {
        if (!iconView || ![v isKindOfClass:iconView] || v.hidden) continue;
        CGSize b = v.bounds.size;
        top = fmin(top, v.center.y - b.height / 2.0); bottom = fmax(bottom, v.center.y + b.height / 2.0);
    }
    return isfinite(top) && isfinite(bottom) && bottom > top ? bottom - top : 0.0;
}

// ---- our views -----------------------------------------------------------------------------------------------------------------------------
// The routing layer: only the render server's routing (hit-tested as opaque, no fill); UIKit's touches go to Apple's views under it.
@interface DMCC18RouteView : UIView
@end
@implementation DMCC18RouteView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return nil; }
@end
// The top row: Apple's buttons take their touches; the row itself none (a touch on it is the panel's: Apple's dismissal tap is not asked for it,
// as the material under the tiles takes none either -- the routing layer under the panel sends it to Apple's views, which do nothing there).
@interface DMCC18RowView : UIView
@end
@implementation DMCC18RowView
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { UIView *hit = [super hitTest:p withEvent:e]; return hit == self ? nil : hit; }
@end
static void DMCC18MakeViews(void) {
    if (gCC18Material) return;
    gCC18Route = [DMCC18RouteView new];
    gCC18Route.backgroundColor = [UIColor clearColor];
    gCC18Route.isAccessibilityElement = NO; gCC18Route.accessibilityElementsHidden = YES;
    SEL opaque = NSSelectorFromString(@"setHitTestsAsOpaque:");
    if ([gCC18Route.layer respondsToSelector:opaque]) ((void (*)(id, SEL, BOOL))objc_msgSend)(gCC18Route.layer, opaque, YES);
    gCC18Material = [UIView new];   // (the shadow; the blur inside it clips to its corners)
    gCC18Material.userInteractionEnabled = NO; gCC18Material.accessibilityElementsHidden = YES;
    gCC18Material.layer.shadowColor = [[UIColor blackColor] CGColor];
    gCC18Material.layer.shadowOpacity = 0.25; gCC18Material.layer.shadowRadius = 18.0; gCC18Material.layer.shadowOffset = CGSizeMake(0, 8);
    gCC18Blur = DMMakeBlur(22.0);   // (our menus' material, rounded as the 15-17 panel)
    // Dark in both appearances: Apple's 18 tiles, its + and power buttons and page dots are white on its own darkening material in Light Mode
    // too (stock does not recolour them); on our light material the buttons' white glyphs all but vanished (A12Z, Light Mode).
    gCC18Blur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    gCC18Blur.userInteractionEnabled = NO;
    gCC18Blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [gCC18Material addSubview:gCC18Blur];
    gCC18Row = [DMCC18RowView new];
    gCC18Row.backgroundColor = [UIColor clearColor];
    // Apple's page dots are white on its darkening backdrop; beside the panel, over a light window, they all but vanished (A12Z, Light Mode): a
    // capsule of the panel's material, dark as it, behind them (MSBDCC18DotsPillFrame).
    gCC18DotsPill = DMMakeBlur(kMSBDCC18DotsMaxW / 2.0);
    gCC18DotsPill.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    gCC18DotsPill.userInteractionEnabled = NO; gCC18DotsPill.accessibilityElementsHidden = YES;
}
static void DMCC18SetMaterialFrame(CGRect f) {
    if (CGRectEqualToRect(gCC18Material.frame, f)) return;
    gCC18Material.frame = f;
    gCC18Blur.frame = gCC18Material.bounds;
    gCC18Material.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:gCC18Material.bounds cornerRadius:22.0].CGPath;
}
// Apple's + and power buttons into our row (they keep their targets: the header's own actions run, as on stock), and back. A button laid out by
// Auto Layout is left where it is (its constraints would go with the move): the row then shows without it, and the log says so.
static BOOL DMCC18Movable(UIView *b, UIView *home) {
    if (!b || !b.translatesAutoresizingMaskIntoConstraints) return NO;
    for (NSLayoutConstraint *c in home.constraints) if (c.firstItem == b || c.secondItem == b) return NO;
    return YES;
}
static void DMCC18ButtonsIn(UIView *header) {
    UIView *edit = DMCC18ViewOf(header, @"editButton"), *power = DMCC18ViewOf(header, @"powerButton");
    for (UIView *b in @[edit ?: (id)[NSNull null], power ?: (id)[NSNull null]]) {
        if (![b isKindOfClass:[UIView class]] || b.superview == gCC18Row) continue;
        if (b.superview != header || !DMCC18Movable(b, header)) {
            static BOOL told = NO;
            if (!told) { told = YES; DMLog([NSString stringWithFormat:@"[cc18] %@ not moved into the panel's row (%@)", NSStringFromClass([b class]), b.superview != header ? @"not in Apple's header" : @"laid out by constraints"]); }
            continue;
        }
        NSUInteger at = [header.subviews indexOfObjectIdenticalTo:b];
        if (b == edit) { gCC18Edit = b; gCC18EditAt = at; } else { gCC18Power = b; gCC18PowerAt = at; }
        gCC18ButtonsHome = header;
        [gCC18Row addSubview:b];
    }
}
static void DMCC18ButtonsBack(void) {   // (in the reverse order of their moves: each place was read with the one moved before it already out)
    UIView *home = gCC18ButtonsHome;
    for (int k = 1; k >= 0; k--) {
        UIView *b = k == 0 ? gCC18Edit : gCC18Power;
        NSUInteger at = k == 0 ? gCC18EditAt : gCC18PowerAt;
        if (!b || b.superview != gCC18Row) continue;
        if (home) { if (at != NSNotFound && at <= home.subviews.count) [home insertSubview:b atIndex:at]; else [home addSubview:b]; }
        else [b removeFromSuperview];
    }
    gCC18Edit = nil; gCC18Power = nil; gCC18EditAt = gCC18PowerAt = NSNotFound;
    [home setNeedsLayout];
}
static void DMCC18PlaceButtons(void) {
    CGRect panel = gCC18Material.frame;
    if (!gCC18Row.superview || CGRectIsEmpty(panel)) return;
    CGRect row = CGRectMake(panel.origin.x, panel.origin.y, panel.size.width, kMSBDCCPad + kMSBDCC18TopRow);
    if (!CGRectEqualToRect(gCC18Row.frame, row)) gCC18Row.frame = row;
    CGRect inRow = CGRectMake(0, 0, panel.size.width, panel.size.height);
    for (UIView *b in @[gCC18Edit ?: (id)[NSNull null], gCC18Power ?: (id)[NSNull null]]) {
        if (![b isKindOfClass:[UIView class]] || b.superview != gCC18Row) continue;
        CGSize s = b.bounds.size;
        CGRect e, p;
        MSBDCC18TopRowFrames(inRow, s.width, s.height, DMCC18RTL(), &e, &p);
        CGRect f = b == gCC18Edit ? e : p;
        CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
        if (!CGPointEqualToPoint(b.center, c)) b.center = c;   // (the center: Apple's presentation may give the buttons a transform of its own)
    }
}
// Apple's page dots beside the panel (they stay Apple's: its own taps and its own look), our material's capsule behind them (in the main view, as the
// panel: it shows only while they do -- Apple shows none for a single page).
static void DMCC18PlaceDotsPill(UIView *dots, CGPoint c, double w, double h) {
    if (!gCC18DotsPill.superview) return;
    BOOL show = dots.window && !dots.hidden;
    if (gCC18DotsPill.hidden == show) gCC18DotsPill.hidden = !show;
    CGRect f = MSBDCC18DotsPillFrame(c, w, h);
    if (!CGRectIsEmpty(f) && !CGRectEqualToRect(gCC18DotsPill.frame, f)) gCC18DotsPill.frame = f;
}
static void DMCC18PlaceDots(UIViewController *m) {
    UIView *dots = DMCC18ViewOf(m, @"overlayPageControl");
    if (!dots.superview || CGRectIsEmpty(gCC18Material.frame)) { if (gCC18DotsPill && !gCC18DotsPill.hidden) gCC18DotsPill.hidden = YES; return; }
    if (dots != gCC18Dots) { gCC18Dots = dots; gCC18DotsMoved = NO; }   // (another control of Apple's: placed for the first time)
    CGRect b = dots.bounds;
    double w = MSBDCC18DotsWidth(b.size.width);
    CGPoint c = MSBDCC18DotsCenter(gCC18Material.frame, gCC18Grid, w, b.size.height, m.view.bounds.size.width, gCC18GridRTL);
    DMCC18PlaceDotsPill(dots, c, w, b.size.height);
    c = [m.view convertPoint:c toView:dots.superview];
    if (fabs(dots.center.x - c.x) <= 0.25 && fabs(dots.center.y - c.y) <= 0.25 && fabs(b.size.width - w) <= 0.25) return;
    if (!gCC18DotsMoved) { gCC18DotsApple = dots.center; gCC18DotsAppleBounds = b; }   // (Apple's place: where they are now; its later ones its setters' hooks keep)
    gCC18PlacingDots = YES;
    if (fabs(b.size.width - w) > 0.25) dots.bounds = CGRectMake(b.origin.x, b.origin.y, w, b.size.height);
    dots.center = c; gCC18DotsOurs = c; gCC18DotsMoved = YES;
    gCC18PlacingDots = NO;
}
static void DMCC18DotsBack(UIViewController *m) {   // (iPadOS's look or edit mode: where Apple had them, unless Apple has placed them again since)
    UIView *dots = DMCC18ViewOf(m, @"overlayPageControl");
    gCC18PlacingDots = YES;
    if (gCC18DotsMoved && dots && CGPointEqualToPoint(dots.center, gCC18DotsOurs)) { dots.bounds = gCC18DotsAppleBounds; dots.center = gCC18DotsApple; }
    gCC18PlacingDots = NO;
    gCC18DotsMoved = NO;
}
// The panel is the shape in force (DMCC18Views's rule): Mac, not editing, Apple's grid answered into its place.
static BOOL DMCC18PanelInForce(void) { return gCC18On && !gCC18Editing && !CGRectIsEmpty(gCC18Grid); }
// Apple's header in the panel: hidden (its status bar copy and labels: our bar shows; its + and power are in our row) -- unless it shows Apple's
// sensor attribution (the camera or microphone in use): then the header shows with nothing of its own but that control, which sits in our top
// row (DMCC18SensorFrame); its other views are hidden and remembered (shown again with Apple's look). Apple's list of the apps opens from the
// control in a full-screen view of its own over the panel, not in the header (18.5).
static BOOL DMCC18SensorShows(UIView *header) {
    return gCC18HaveSensor && header && DMCCTypes(header, @"isDisplayingSensorStatus", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(header, NSSelectorFromString(@"isDisplayingSensorStatus"));
}
static void DMCC18HeaderLook(UIView *header) {
    if (!header) return;
    if (!DMCC18SensorShows(header)) {
        if (!header.hidden) { header.hidden = YES; gCC18HidHeader = YES; }
        return;
    }
    UIView *control = DMCC18ViewOf(header, @"compactSensorAttributionControl");
    if (!gCC18HidHeaderParts) gCC18HidHeaderParts = [NSHashTable weakObjectsHashTable];
    for (UIView *v in header.subviews) if (v != control && !v.hidden) { v.hidden = YES; [gCC18HidHeaderParts addObject:v]; }
    if (header.hidden && gCC18HidHeader) { header.hidden = NO; gCC18HidHeader = NO; }   // (only a header the shape hid: one Apple hid stays so)
}
static void DMCC18HeaderPartsBack(UIView *header) {
    BOOL any = gCC18HidHeaderParts.count > 0;
    for (UIView *v in gCC18HidHeaderParts.allObjects) if (v.hidden) v.hidden = NO;
    [gCC18HidHeaderParts removeAllObjects];
    if (any) [header setNeedsLayout];   // (its control back at Apple's place: our answer stands only while the panel does)
}
// The sensor control's place in our row, in the header's space: centred between Apple's + and power (as they sit in the row, DMCC18PlaceButtons),
// on their middle, at Apple's size or narrower (CCLayout.h MSBDCC18SensorFrame). Empty: no row, or no room.
static CGRect DMCC18SensorRect(UIView *header, CGSize apple) {
    if (!gCC18Row.superview || !header || !gCC18Edit || !gCC18Power) return CGRectZero;
    CGRect panel = gCC18Material.frame, e, pw;
    CGRect inRow = CGRectMake(0, 0, panel.size.width, panel.size.height);
    MSBDCC18TopRowFrames(inRow, gCC18Edit.bounds.size.width, gCC18Edit.bounds.size.height, DMCC18RTL(), &e, &pw);
    CGRect band = CGRectMake(0, kMSBDCCPad, panel.size.width, kMSBDCC18TopRow);
    CGRect f = MSBDCC18SensorFrame(band, e, pw, apple.width, apple.height);
    return CGRectIsEmpty(f) ? CGRectZero : [gCC18Row convertRect:f toView:header];
}
// After Apple's layout of its header: the control at our place (Apple's layout may place it without asking for its frame; its centre and size --
// Apple's presentation may give it a transform of its own, as the buttons).
static void DMCC18PlaceSensor(UIView *header) {
    UIView *control = DMCC18ViewOf(header, @"compactSensorAttributionControl");
    if (!control || control.superview != header || !DMCC18SensorShows(header)) return;
    CGRect f = DMCC18SensorRect(header, control.bounds.size);
    if (CGRectIsEmpty(f)) return;
    CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    if (fabs(control.bounds.size.width - f.size.width) > 0.25) control.bounds = CGRectMake(control.bounds.origin.x, control.bounds.origin.y, f.size.width, control.bounds.size.height);
    if (fabs(control.center.x - c.x) > 0.25 || fabs(control.center.y - c.y) > 0.25) control.center = c;
}
// The panel's views as the style, edit mode and an expansion want them -- after Apple's every layout, and when one of them changes.
static void DMCC18Views(NSString *why) {
    UIViewController *m = gCC18Main;
    if (!m.isViewLoaded) return;
    UIView *back = DMCC18ViewOf(m, @"overlayBackgroundView"), *header = DMCC18ViewOf(m, @"overlayHeaderView");
    BOOL mac = gCC18On && !gCC18Editing && !CGRectIsEmpty(gCC18Grid);
    if (!mac) {
        if (gCCPDetail) DMCCPanelCloseDetail(NO);   // (the grid has no place in the panel any more, or edit mode came: never a page left floating with the material gone, CC18Tiles.h)
        BOOL had = gCC18Material.superview || gCC18Route.superview || gCC18Row.superview || gCC18HidBack || gCC18HidHeader || gCC18HidHeaderParts.count;
        if (gCC18Edit || gCC18Power) DMCC18ButtonsBack();
        [gCC18Material removeFromSuperview]; [gCC18Route removeFromSuperview]; [gCC18Row removeFromSuperview]; [gCC18DotsPill removeFromSuperview];
        if (gCC18HidBack) { back.hidden = NO; gCC18HidBack = NO; }
        if (gCC18HidHeader) { header.hidden = NO; gCC18HidHeader = NO; }
        DMCC18HeaderPartsBack(header);
        DMCC18DotsBack(m);
        if (had) DMLog([NSString stringWithFormat:@"[cc18] Apple's look (%@)", why]);
        return;
    }
    DMCC18MakeViews();
    UIView *v = m.view;
    if (gCC18Route.superview != v) [v insertSubview:gCC18Route atIndex:0];
    if (!CGRectEqualToRect(gCC18Route.frame, v.bounds)) gCC18Route.frame = v.bounds;
    if (gCC18Material.superview != v) {
        if (back.superview == v) [v insertSubview:gCC18Material aboveSubview:back]; else [v insertSubview:gCC18Material aboveSubview:gCC18Route];
        gCC18Material.alpha = gCC18Expanded ? 0.0 : (gCC18Shown ? 1.0 : 0.0);   // (closed: Apple's presentation brings it in, DMCC18Update)
    }
    if (gCC18DotsPill.superview != v) { [v insertSubview:gCC18DotsPill aboveSubview:gCC18Material]; gCC18DotsPill.alpha = gCC18Material.alpha; }   // (under Apple's dots: they are in its pages' view, above)
    if (gCC18Row.superview != v) {
        if (header.superview == v) [v insertSubview:gCC18Row aboveSubview:header]; else [v addSubview:gCC18Row];
        gCC18Row.alpha = gCC18Material.alpha;
    }
    UIScrollView *sv = [DMCCGet(DMCCGet(m, @"pagingViewController"), @"scrollView") isKindOfClass:[UIScrollView class]] ? DMCCGet(DMCCGet(m, @"pagingViewController"), @"scrollView") : nil;
    BOOL scrolling = sv && (sv.isDragging || sv.isDecelerating);
    if (gCCPDetail) DMCC18PageFollowsPanel();   // (one of our pages keeps its own height, wherever the grid is now: CC18Tiles.h)
    else if (!scrolling || CGRectIsEmpty(gCC18Material.frame)) DMCC18SetMaterialFrame(MSBDCC18PanelFrame(gCC18Grid, gCC18PanelTop, DMCC18RowsHeight(m)));   // (scrolling: the panel stays, DMCC18DidScroll)
    if (header) DMCC18ButtonsIn(header);
    DMCC18PlaceButtons();
    DMCC18PlaceDots(m);

    if (back && !back.hidden && !gCC18Expanded) { back.hidden = YES; gCC18HidBack = YES; }
    DMCC18HeaderLook(header);
    if (header) DMCC18PlaceSensor(header);
}
// Apple's own layout again (its insets asked again: ours or Apple's), then our views -- a style change, a lock state or bar height the last
// answer was not worked out for, edit mode's end.
static void DMCC18Relayout(NSString *why) {
    UIViewController *m = gCC18Main;
    if (!m.isViewLoaded) return;
    if (!gCC18On || gCC18Editing) gCC18Grid = CGRectZero;   // (Apple's insets now: none of ours stands)
    [m.view setNeedsLayout]; [m.view layoutIfNeeded];
    id prov = DMCCIvarOf(m, "_presentationProvider", "@\"<CCUIOverlayPresentationProvider>\"");
    if (DMCCTypes(prov, @"layoutViews", "v16@0:8")) ((void (*)(id, SEL))objc_msgSend)(prov, NSSelectorFromString(@"layoutViews"));
    DMCC18Views(why);
    DMLog([NSString stringWithFormat:@"[cc18] laid out again (%@): Mac %d, grid %@, panel %@", why, gCC18On && !gCC18Editing, NSStringFromCGRect(gCC18Grid), gCC18Material.superview ? NSStringFromCGRect(gCC18Material.frame) : @"-"]);
}

// ---- the hooks -----------------------------------------------------------------------------------------------------------------------------
// Where Apple puts its grid: these insets around the content's size (CCLayout.h). Only for our Control Center, with the Mac shape on and not
// editing; Apple's answer otherwise, and wherever ours would not fit.
static UIEdgeInsets DMCC18Insets(id self, SEL _cmd, CGSize size, CGRect bounds, UIEdgeInsets edge, long long orientation) {
    UIEdgeInsets r = o_DMCC18Insets(self, _cmd, size, bounds, edge, orientation);
    if (!gCC18On || gCC18Editing) return r;
    UIViewController *m = DMCC18MainIfOurs(DMCCGet(self, @"viewProvider"));
    if (!m) return r;
    double top = DMCC18PanelTopNow();
    MSBDCCInsets e = { edge.top, edge.left, edge.bottom, edge.right }, out;
    BOOL rtl = DMCC18RTL();
    if (!MSBDCC18Insets(size.width, size.height, bounds.size.width, bounds.size.height, e, MSBDCC18TilesTop(top), rtl, &out)) {
        static BOOL told = NO;
        if (!told) { told = YES; DMLog([NSString stringWithFormat:@"[cc18] the panel does not fit: content %@ in %@ (Apple's place)", NSStringFromCGSize(size), NSStringFromCGRect(bounds)]); }
        gCC18Grid = CGRectZero;
        return r;
    }
    CGRect g = MSBDCC18GridRect(size.width, size.height, e, out);
    gCC18Grid = CGRectOffset(g, bounds.origin.x, bounds.origin.y);
    gCC18PanelTop = top + bounds.origin.y; gCC18GridRTL = rtl;
    gCC18LaidBar = DMMenuBarHeight();
    return UIEdgeInsetsMake(out.top, out.left, out.bottom, out.right);
}
static void DMCC18LayoutViews(id self, SEL _cmd) {
#if DEBUG
    gCC18InLayoutViews++;
#endif
    o_DMCC18LayoutViews(self, _cmd);
#if DEBUG
    gCC18InLayoutViews--;
#endif
    if (!gCC18On && !gCC18Material.superview && !gCC18HidBack && !gCC18HidHeader) return;
    if (!DMCC18MainIfOurs(DMCCGet(self, @"viewProvider"))) return;
    DMCC18Views(@"Apple's layout");
}
static void DMCC18MainLayout(id self, SEL _cmd) {
#if DEBUG
    gCC18InMainLayout++;
#endif
    o_DMCC18MainLayout(self, _cmd);
#if DEBUG
    gCC18InMainLayout--;
#endif
    if (!gCC18On && !gCC18Material.superview) return;
    if (DMCC18MainIfOurs(self)) DMCC18Views(@"the main view's layout");
}
// A presentation step: our material and row fade with Apple's progress, in Apple's own animation for the step (a finger pull follows at once).
// Apple places its page dots again during an interactive pull (at Apple's place by the screen's edge, under the panel's corner: A12Z 18.5, k04):
// beside the panel again after each step.
static void DMCC18Update(id self, SEL _cmd, id state, id completion) {
#if DEBUG
    gCC18InStep++;
#endif
    o_DMCC18Update(self, _cmd, state, completion);
#if DEBUG
    gCC18InStep--;
#endif
    if (!gCC18On || self != gCC18Main || !gCC18Material.superview) return;
    if (!gCC18Editing) DMCC18PlaceDots(gCC18Main);
    if (gCC18Expanded) return;
    double a = fmax(0.0, fmin(1.0, DMCC18Progress(state)));
    void (^go)(void) = ^{ gCC18Material.alpha = a; gCC18Row.alpha = a; gCC18DotsPill.alpha = a; };
    if ([UIView inheritedAnimationDuration] > 0 || DMCC18Interactive(state)) go();
    else [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:go completion:nil];
}
// Edit mode is Apple's whole look (its place for the grid -- Apple's edit transition lays the grid out again and asks the insets: Apple's while
// editing --, its header, backdrop and dots); the panel comes back with the transition out of it (ours asked again).
static void DMCC18Editing(id self, SEL _cmd, id paging, BOOL editing) {
    BOOL ours = gCC18On && DMCC18MainIfOurs(self);
    if (ours) {
        gCC18Editing = editing;
        DMLog([NSString stringWithFormat:@"[cc18] edit mode %@: %@", editing ? @"on" : @"off", editing ? @"Apple's look" : @"the panel back"]);
        if (editing) DMCC18Views(@"edit mode");
    }
    o_DMCC18Editing(self, _cmd, paging, editing);
    if (ours && !editing) DMCC18Views(@"edit mode over");
}
// One of Apple's modules opens expanded: Apple's own backdrop behind it (a cross-fade) and our material and row away, as stock; back when it closed.
static void DMCC18ExpandedLook(BOOL expanded) {
    UIView *back = DMCC18ViewOf(gCC18Main, @"overlayBackgroundView");
    gCC18Expanded = expanded;
    if (!gCC18On || gCC18Editing || !gCC18Material.superview) return;
    NSTimeInterval d = MSBReduceMotion() ? 0.2 : 0.25;
    if (expanded && gCC18HidBack && back) { gCC18HidBack = NO; [UIView transitionWithView:back duration:d options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ back.hidden = NO; } completion:nil]; }
    if (!expanded && back && !back.hidden) { gCC18HidBack = YES; [UIView transitionWithView:back duration:d options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ back.hidden = YES; } completion:nil]; }
    gCC18Row.userInteractionEnabled = !expanded;
    [UIView animateWithDuration:d delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ gCC18Material.alpha = expanded ? 0.0 : 1.0; gCC18Row.alpha = expanded ? 0.0 : 1.0; gCC18DotsPill.alpha = expanded ? 0.0 : 1.0; } completion:nil];
}
// Control Center closing or opening with an expansion still counted (it ended without Apple's -didClose:): nothing is open then; the panel
// transparent until the presentation brings it in, Apple's backdrop hidden again.
static void DMCC18ExpandedReset(void) {
    UIView *back = DMCC18ViewOf(gCC18Main, @"overlayBackgroundView");
    gCC18Expanded = NO;
    gCC18Row.userInteractionEnabled = YES;
    if (!gCC18On || gCC18Editing || !gCC18Material.superview) return;
    gCC18Material.alpha = 0.0; gCC18Row.alpha = 0.0; gCC18DotsPill.alpha = 0.0;
    if (back && !back.hidden) { back.hidden = YES; gCC18HidBack = YES; }
}
static void DMCC18WillExpand(id self, SEL _cmd, id paging, id vc) {
    o_DMCC18WillExpand(self, _cmd, paging, vc);
    if (gCC18On && self == gCC18Main) DMCC18ExpandedLook(YES);
}
static void DMCC18DidClose(id self, SEL _cmd, id paging, id vc) {
    o_DMCC18DidClose(self, _cmd, paging, vc);
    if (gCC18On && self == gCC18Main) DMCC18ExpandedLook(NO);
}
// The pages scroll (the main controller is their scroll view's delegate): the panel stays where it is; once they rest it takes the page's height
// (Apple names the page that shows after the scroll).
static void DMCC18DidScroll(id self, SEL _cmd, id scrollView) {
    o_DMCC18DidScroll(self, _cmd, scrollView);
    if (!gCC18On || self != gCC18Main || !gCC18Material.superview) return;
    unsigned gen = ++gCC18SettleGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIScrollView *sv = [scrollView isKindOfClass:[UIScrollView class]] ? scrollView : nil;
        if (gen != gCC18SettleGen || !gCC18On || gCC18Editing || gCCPDetail || !gCC18Material.superview || (sv && (sv.isDragging || sv.isDecelerating))) return;
        CGRect f = MSBDCC18PanelFrame(gCC18Grid, gCC18PanelTop, DMCC18RowsHeight(gCC18Main));
        if (CGRectEqualToRect(f, gCC18Material.frame) || CGRectIsEmpty(f)) return;
        [UIView animateWithDuration:MSBReduceMotion() ? 0.2 : 0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            DMCC18SetMaterialFrame(f); DMCC18PlaceButtons(); DMCC18PlaceDots(gCC18Main);
        } completion:nil];
    });
}
// Control Center about to show: the bar's height our answer was worked out for (known only once a bar was read after the start); an expansion
// that ended without Apple's -didClose: (nothing is open at a presentation).
static void DMCC18WillPresentHook(id self, SEL _cmd) {
    o_DMCC18WillPresent(self, _cmd);
    gCC18Shown = YES;
    DMCC18TilesWillPresent();
    if (!gCC18On || !gCC18Main.isViewLoaded) return;
    if (gCC18Expanded) DMCC18ExpandedReset();
    if (fabs(DMMenuBarHeight() - gCC18LaidBar) > 0.25 || CGRectIsEmpty(gCC18Grid)) DMCC18Relayout(@"the bar's height");
    else DMCC18Views(@"about to show");
}
static void DMCC18DidDismissHook(id self, SEL _cmd) {
    o_DMCC18DidDismiss(self, _cmd);
    gCC18Shown = NO;
    if (gCCPDetail) DMCCPanelCloseDetail(NO);   // (one of our pages open as it closed: CC18Tiles.h)
    DMCC18TilesDidDismiss();
    if (gCC18On && gCC18Expanded) DMCC18ExpandedReset();
    if (gCC18Pending) dispatch_async(dispatch_get_main_queue(), ^{ DMCC18ApplyStyle(@"Control Center closed"); });
}
// Apple's header laid out again (it places its buttons then): ours stay in our row, at their places.
static void DMCC18HeaderLayout(id self, SEL _cmd) {
    o_DMCC18HeaderLayout(self, _cmd);
    if (!gCC18On || gCC18Editing || !gCC18Row.superview || self != DMCC18ViewOf(gCC18Main, @"overlayHeaderView")) return;
    DMCC18ButtonsIn(self);
    DMCC18PlaceButtons();
    DMCC18HeaderLook(self);   // (Apple's sensor attribution came or went: the header lays itself out then)
    DMCC18PlaceSensor(self);
}
// Apple's own place for its sensor control (Apple's header lays it out there; the list of the apps opens from it): in the panel, our top row's
// middle (DMCC18SensorRect), at Apple's size or narrower; Apple's elsewhere.
static CGRect DMCC18SensorFrame(id self, SEL _cmd) {
    CGRect r = o_DMCC18SensorFrame(self, _cmd);
    if (!DMCC18PanelInForce() || !gCC18Row.superview || self != DMCC18ViewOf(gCC18Main, @"overlayHeaderView")) return r;
    CGRect f = DMCC18SensorRect(self, r.size);
    return CGRectIsEmpty(f) ? r : f;
}
// The header's touches in the panel: its sensor control's, within our top row (Apple gives it 20 pt more on every side, which here reached into the
// first row of tiles); nothing else of the header's (it shows nothing else: its touches go on to the tiles and the panel below it, as when it is
// hidden). With Apple's sensor indicator, a tap on our menu bar's Control Center icon then closes Control Center (1.8.1 item 12, on 18).
static UIView *DMCC18HeaderHit(id self, SEL _cmd, CGPoint p, UIEvent *e) {
    UIView *r = o_DMCC18HeaderHit(self, _cmd, p, e);
    if (!r || !DMCC18PanelInForce() || !gCC18Row.superview || self != DMCC18ViewOf(gCC18Main, @"overlayHeaderView")) return r;
    UIView *control = DMCC18ViewOf(self, @"compactSensorAttributionControl");
    return MSBDCC18SensorTouch(control && [r isDescendantOfView:control], p, [gCC18Row convertRect:gCC18Row.bounds toView:self]) ? r : nil;
}

// A tap in our panel (on the material between Apple's tiles, the top row's empty part) is not a tap outside Control Center: Apple takes a tap on
// its grid's empty places as one (as 15-17's panel, CCPanel.h DMCCPTapBegin; a Mac's panel stays open too).
static BOOL DMCC18TapBegin(id self, SEL _cmd, id gr) {
    BOOL r = o_DMCC18TapBegin(self, _cmd, gr);
    if (!r || !gCC18On || gCC18Editing || gCC18Expanded || self != gCC18Main || !gCC18Material.superview || ![gr isKindOfClass:[UIGestureRecognizer class]]) return r;
    return [gCC18Material pointInside:[(UIGestureRecognizer *)gr locationInView:gCC18Material] withEvent:nil] ? NO : r;
}

// A hold on Apple's + or power button in our row: the button's own (power: Apple's power-off slider after a hold), never edit mode's long press
// too -- Apple's own check keeps its header out of edit mode's hold; the buttons are not in the header while they are in our row (it went into
// edit mode under the power-off slider, A12Z 18.5; stock: the slider only).
static BOOL DMCC18EditPressBegin(id self, SEL _cmd, id gr) {
    BOOL r = o_DMCC18EditPressBegin(self, _cmd, gr);
    if (!r || !gCC18On || gCC18Editing || self != gCC18Main || !gCC18Row.superview || ![gr isKindOfClass:[UIGestureRecognizer class]]) return r;
    return [gCC18Row pointInside:[(UIGestureRecognizer *)gr locationInView:gCC18Row] withEvent:nil] ? NO : r;
}
// Apple's page dots are placed by its pages' root folder view at its own layout, after the main view's (an interactive pull, edit mode's end, a
// turn): beside our panel again right after it.
static void DMCC18FolderLayout(id self, SEL _cmd) {
#if DEBUG
    gCC18InFolder++;
#endif
    o_DMCC18FolderLayout(self, _cmd);
#if DEBUG
    gCC18InFolder--;
#endif
    if (!gCC18On || gCC18Editing || !gCC18Material.superview || ![(UIView *)self isDescendantOfView:gCC18Main.viewIfLoaded]) return;
    DMCC18PlaceDots(gCC18Main);
}
// ... and from its own handling of a touch on them (touch down and up: a tap on the dots beside the panel put them back at Apple's place by the
// screen's edge, and the page did not change -- A12Z 18.5), and from anywhere else: each of Apple's placements of the dots (their -setCenter:,
// -setBounds:, -setFrame:) is turned into ours as Apple makes it while the panel shows, and kept as Apple's place for its look. Our own writes
// pass (DMCC18PlaceDots, DMCC18DotsBack); every other page control is left alone.
static void DMCC18DotsPlacedByApple(NSString *what) {
#if DEBUG
    if (DMTestFlag("/tmp/msb-cc18-dotstrace")) DMLog([NSString stringWithFormat:@"[cc18] dots %@ (%.1f, %.1f): in a step %d, Apple's layout %d, the main layout %d, the folder's %d, editing %d", what, gCC18DotsApple.x, gCC18DotsApple.y, gCC18InStep, gCC18InLayoutViews, gCC18InMainLayout, gCC18InFolder, gCC18Editing]);
#endif
    if (!gCC18Editing && gCC18Material.superview) DMCC18PlaceDots(gCC18Main);
}
static void DMCC18DotsSetCenter(id self, SEL _cmd, CGPoint c) {
    o_DMCC18DotsSetCenter(self, _cmd, c);
    if (gCC18PlacingDots || !gCC18On || self != gCC18Dots) return;
    gCC18DotsApple = c;
    DMCC18DotsPlacedByApple(@"setCenter:");
}
static void DMCC18DotsSetBounds(id self, SEL _cmd, CGRect b) {
    o_DMCC18DotsSetBounds(self, _cmd, b);
    if (gCC18PlacingDots || !gCC18On || self != gCC18Dots) return;
    gCC18DotsAppleBounds = b;
    DMCC18DotsPlacedByApple(@"setBounds:");
}
static void DMCC18DotsSetFrame(id self, SEL _cmd, CGRect f) {
    o_DMCC18DotsSetFrame(self, _cmd, f);
    if (gCC18PlacingDots || !gCC18On || self != gCC18Dots) return;
    gCC18DotsApple = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f)); gCC18DotsAppleBounds = CGRectMake(0, 0, f.size.width, f.size.height);
    DMCC18DotsPlacedByApple(@"setFrame:");
}
// A pull that goes past the full presentation goes on into Apple's paging when its finger is in the page dots' area (read on 18.5: the finger's
// place hit-tests Apple's page control, -canBeginPagingAtLocation:inView:; then Apple hands the pull's touches to the control, which scrubs the
// pages). Not in the panel: it opens on its page wherever the pull starts. Beside the panel the dots' area lay under our status icons (x 1004 to
// 1032 on the A12Z: our Wi-Fi icon), so only a pull starting there went on into the pages -- and left the dots at Apple's place by the screen's
// edge, its touch handling's (1.8.0 regression F1); one from the battery or the top right corner never did.
static void DMCC18Continue(id self, SEL _cmd, CGPoint location) {
    if (DMCC18PanelInForce() && self == gCC18Main) return;
    o_DMCC18Continue(self, _cmd, location);
}
// ... and the area Apple makes for that while a pull lasts: its page control enlarged over the rows from the screen's leading edge
// (-setShouldExtendAreaForPagingContinuation:, 2712 x 510.5 pt on the A12Z), which our placement took for the dots' own frame (their capsule
// 510.5 pt tall beside the panel through every pull). None in the panel: the dots keep their own frame.
static void DMCC18ExtendArea(id self, SEL _cmd, BOOL extend) {
    if (extend && DMCC18PanelInForce() && [(UIView *)self isDescendantOfView:gCC18Main.viewIfLoaded]) extend = NO;
    o_DMCC18ExtendArea(self, _cmd, extend);
}
// ... and nothing past the full presentation in the panel: Apple's provider makes a transition state for each step of a finger pull, and past
// the full presentation gives it a paging part (-pagingProgress, 0 to 1: how far the finger has gone on towards the page dots; read on 18.5), by
// which Apple shrinks its pages as a paging hint (-_addPageContentTransformAnimationsToBatch:transitionState:: their scale to 0.8 and alpha to
// 0.7, about the screen's middle), and its progress goes on past 1, by which Apple's module views rubber-band down (-_transformForTransitionState:
// rubberBandingHeight:, less as the paging part grows). In the panel the grid sits at the right under our bar: its tiles slid left and down out
// of the panel while the finger kept pulling and came back when it lifted (cc18dots' finding; without the paging part the rubber band alone took
// them out of the panel's bottom). A presentation step's state is made again there by Apple's own factory with the step's type and finger, its
// progress at most 1 and no paging part, as the 15-17 panel's motion stops at the full presentation (Apple's continuation into its paging then
// ends at its own first test as well). Dismissal steps and iPadOS's own Control Center keep Apple's.
#define kDMCC18PresentType 1ULL   // (Apple's transition type of a presentation: its provider gives only those states a paging part, 18.5)
static id DMCC18PullState(id self, SEL _cmd, unsigned long long type, BOOL interactive, CGPoint translation) {
    id s = o_DMCC18PullState(self, _cmd, type, interactive, translation);
    if (!s || !DMCC18PanelInForce() || !DMCC18MainIfOurs(DMCCGet(self, @"viewProvider"))) return s;
    double progress = ((double (*)(id, SEL))objc_msgSend)(s, NSSelectorFromString(@"progress")), paging = ((double (*)(id, SEL))objc_msgSend)(s, NSSelectorFromString(@"pagingProgress"));
    if (!MSBDCC18PullState(1, type == kDMCC18PresentType, &progress, &paging)) return s;
    id plain = ((id (*)(id, SEL, unsigned long long, BOOL, double, double))objc_msgSend)(objc_getClass("CCUIOverlayTransitionState"),
        NSSelectorFromString(@"stateWithType:interactive:progress:pagingProgress:"), type, interactive, progress, paging);
    return plain ?: s;
}

// Esc on a hardware keyboard while the panel shows (StatusBar.x's -[SpringBoard pressesBegan:withEvent:] hook, DMOverlayPressesBegan, after the
// 15-17 panel's DMCCPanelEscape): Control Center's window has no first responder on 18, so Esc reaches SpringBoard as on 15-17 and went nowhere
// (A12Z 18.5). One level back, as the 15-17 panel's page goes back first: what Apple counts as content it presents -- a module open expanded (a
// UIKit presentation of its container on 18), the sensor list, edit mode, its gallery: -canDismissPresentedContent, read on 18.5 -- closes by
// Apple's own -dismissPresentedContentAnimated:completion:, else Control Center closes (Apple's own animated dismissal, the 15-17 panel's).
// Anything else presented over Control Center keeps the key. Esc alone; YES when taken.
static BOOL DMCC18PanelEscape(NSSet<UIPress *> *presses) {
    UIViewController *m = gCC18Main;
    if (!gCC18On || !gCC18Shown || !m.viewIfLoaded.window || !DMControlCenterActive()) return NO;
    for (UIPress *p in presses) {
        if (p.key.keyCode != UIKeyboardHIDUsageKeyboardEscape || (p.key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierControl | UIKeyModifierAlternate | UIKeyModifierShift))) continue;
        if (DMCC18PagePanelEscape()) { DM_FEATURE_MARK("esc-closes-cc-18"); DMLog(@"[cc18] Esc: the page goes back"); return YES; }   // (one of our pages, CC18Tiles.h)
        if (!gCC18HaveEsc) return NO;   // (its rows not as read, another 18.x: Apple's handling of the key, as before 1.8.1; an optional part of the table)
        BOOL content = DMCCTypes(m, @"canDismissPresentedContent", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(m, NSSelectorFromString(@"canDismissPresentedContent"));
        int step = MSBDCC18EscStep(content, m.presentedViewController != nil);
        if (step == kMSBDCC18EscNone) return NO;
        DM_FEATURE_MARK("esc-closes-cc-18");
        DMLog([NSString stringWithFormat:@"[cc18] Esc: %@", step == kMSBDCC18EscClosePresented ? @"one level back (Apple's presented content closes)" : @"Control Center closes"]);
        if (step == kMSBDCC18EscClosePresented && DMCCTypes(m, @"dismissPresentedContentAnimated:completion:", "v28@0:8B16@?20"))
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(m, NSSelectorFromString(@"dismissPresentedContentAnimated:completion:"), YES, nil);
        else DMCCPanelDismiss();
        return YES;
    }
    return NO;
}

// ---- the Mac panel's own layout of tiles (1.8.1 item 1; common/CC18MacLayout.h) ------------------------------------------------------------------
// While Mac is the style Apple's grid reads and saves a file of its own: made once from the user's layout, our Mac tiles at the top in place of the
// Apple tiles they stand for; iPadOS's file is never touched (edit mode and the gallery save into the store the model has). Made with the data-protection
// class Apple's own layout has (none: SpringBoard reads it before a first unlock). Any failure: Apple's file, and Mac as 1.8.0.
static NSURL *DMCC18MacLayoutURL(void) {
    NSString *mac = kMSBDCC18MacLayoutFile;
    NSData *d = [NSData dataWithContentsOfFile:mac];
    NSDictionary *have = d ? [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:NULL error:nil] : nil;
    NSArray *(*registered)(void) = (NSArray *(*)(void))dlsym(RTLD_DEFAULT, kMSBDCCRegisteredControlsFn);
    NSArray *controls = registered ? registered() : nil;
    BOOL sshInstalled = access(kMSBDSSHDaemon, F_OK) == 0;
    if (!MSBDCC18MacLayoutReadable(have, controls, sshInstalled)) { DMLog(@"[cc18] the Mac layout stays unread: a module of ours is not in the repository"); return nil; }
    int step = MSBDCC18MacFileStep(d || [[NSFileManager defaultManager] fileExistsAtPath:mac], have);
    if (step == kMSBDCC18MacFileUse) return [NSURL fileURLWithPath:mac];
    if (step == kMSBDCC18MacFileAppleForNow) { DMLog(@"[cc18] the Mac layout is there but could not be read or does not parse: Apple's file for now, nothing written over it"); return nil; }
    if (!MSBDCC18MacLayoutMayBeMade(controls, sshInstalled)) { DMLog(@"[cc18] the Mac layout is not made now: RAM & CPU or SSH is off (the crash guard), its tile would be lost: Apple's file for that while"); return nil; }
    d = [NSData dataWithContentsOfFile:kMSBDCC18AppleLayoutFile];
    NSDictionary *state = d ? [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:NULL error:nil] : nil;
    NSDictionary *made = MSBDCC18MacLayoutFrom(state, 8, ^NSString *{ return [NSUUID UUID].UUIDString; });
    NSData *out = made ? [NSPropertyListSerialization dataWithPropertyList:made format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil] : nil;
    BOOL ok = out && [out writeToFile:mac options:NSDataWritingAtomic | NSDataWritingFileProtectionNone error:nil];
    DMLog([NSString stringWithFormat:@"[cc18] the Mac layout %@ from the user's (%lu pages)", ok ? @"made" : @"NOT made: Apple's file stays", (unsigned long)[made[@"iconLists"] count]]);
    return ok ? [NSURL fileURLWithPath:mac] : nil;
}
static BOOL gCC18MacLayoutInForce = NO;   // (Apple's grid has the Mac layout now)
__attribute__((visibility("default"))) BOOL MSBDCCMacLayoutInForce(void) { return gCC18MacLayoutInForce; }   // (kMSBDCCMacLayoutInForceFn: "Add a Control" offers our Mac tiles only then, CCModuleRegister.h)
static id DMCC18StoreInit(id self, SEL _cmd, NSURL *current, NSURL *desired) {
    if (gCC18On && gCC18HaveTiles && [current isKindOfClass:[NSURL class]] && [current.path isEqualToString:kMSBDCC18AppleLayoutFile]) {
        NSURL *mac = DMCC18MacLayoutURL();
        if (mac) { gCC18AppleDesired = desired; current = mac; desired = [NSURL fileURLWithPath:kMSBDCC18MacDesiredFile]; gCC18MacLayoutInForce = YES; DMLog(@"[cc18] Control Center's tiles read the Mac layout"); }
    }
    return o_DMCC18StoreInit(self, _cmd, current, desired);
}
// A style change while Control Center exists, in Apple's own steps for a layout changed under a live Control Center (-[CCUIPagingViewController resetToDefaultLayout],
// 18.5): the model saves where it is and must be clean (-layout saves too: what is unsaved would go to the other file), gets the other file, Control Center leaves the
// root folder, the model lays out again (-layout: a new root folder from the store; -reloadIcons only reloads its icons), Control Center takes the new root folder, its
// controller shows it. Nothing started when a part of that is not there.
static void DMCC18LayoutFollowsStyle(UIViewController *m) {
    if (!gCC18HaveTiles || !o_DMCC18StoreInit || !m.isViewLoaded) return;
    UIViewController *paging = DMCCGet(m, @"pagingViewController");
    id model = DMCCGet(paging, @"iconModel");
    Class storeClass = objc_getClass("SBIconModelPropertyListFileStore");
    id store = DMCCGet(model, @"store"), root = DMCCGet(model, @"rootFolder");
    if (!model || !root || !storeClass || ![store isKindOfClass:storeClass]) return;
    NSURL *now = DMCCGet(store, @"currentIconStateURL");
    NSURL *want = gCC18On ? DMCC18MacLayoutURL() : nil;
    if (!want) want = [NSURL fileURLWithPath:kMSBDCC18AppleLayoutFile];
    if ([now.path isEqualToString:want.path]) return;
    UIViewController *folders = nil;
    for (UIViewController *c in paging.childViewControllers) if (DMCCTypes(c, @"setFolder:", "v24@0:8@16")) { folders = c; break; }
    if (!folders) { DMLog(@"[cc18] the layout stays: no root folder controller here"); return; }
    ((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"saveIconStateIfNeeded"));
    if (((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"isIconStateDirty"))) { DMLog(@"[cc18] the layout stays: not saved"); return; }
    if ([now.path isEqualToString:kMSBDCC18AppleLayoutFile]) gCC18AppleDesired = DMCCGet(store, @"desiredIconStateURL");
    NSURL *desired = [want.path isEqualToString:kMSBDCC18MacLayoutFile] ? [NSURL fileURLWithPath:kMSBDCC18MacDesiredFile] : gCC18AppleDesired;
    id fresh = o_DMCC18StoreInit([storeClass alloc], NSSelectorFromString(@"initWithIconStateURL:desiredIconStateURL:"), want, desired);
    if (!fresh) return;
    void (*send)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
    send(root, NSSelectorFromString(@"setDelegate:"), nil);
    send(root, NSSelectorFromString(@"removeFolderObserver:"), paging);
    send(model, NSSelectorFromString(@"setStore:"), fresh);
    gCC18MacLayoutInForce = [want.path isEqualToString:kMSBDCC18MacLayoutFile];
    ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"layout"));
    id newRoot = DMCCGet(model, @"rootFolder");
    send(newRoot, NSSelectorFromString(@"addFolderObserver:"), paging);
    send(newRoot, NSSelectorFromString(@"setDelegate:"), paging);
    send(folders, NSSelectorFromString(@"setFolder:"), newRoot);
    DMLog([NSString stringWithFormat:@"[cc18] Control Center's tiles now read %@", want.lastPathComponent]);
}

// ---- turning it on and off -----------------------------------------------------------------------------------------------------------------
static void DMCC18SetWanted(BOOL want) {
    want = want && gCC18Supported;
    if (want == gCC18Want) return;
    gCC18Want = want;
    DMLog([NSString stringWithFormat:@"[cc18] our Control Center %@: the menu bar's Control Center icon %@", want ? @"is the style" : @"is not the style", want ? @"shows" : @"shows with Battery Menu only"]);
    dispatch_async(dispatch_get_main_queue(), ^{ for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout]; });
}
// The style in force, applied while Control Center is closed (an open one keeps its look until it closes: DMCC18DidDismissHook, and a look a
// second later -- no hook before Mac was ever chosen). The hooks go in the first time Mac is chosen and stay (they act only while it is). Mac
// steps aside while another Control Center is loaded, as on 15-17 (CCPanel.h DMCCPOtherCC: BigSurCenter until the respring that keeps it out --
// both reshaped the same Control Center; code review 1.8.0, 11).
static BOOL gCC18InConstructor = NO;   // (the start's look: SpringBoard's launch has not begun, nothing is asked of it: DMCC18Init)
static void DMCC18ApplyStyle(NSString *why) {
    BOOL want = gCC18Supported && DMCCStyleChosenNow() == kMSBDCCStyleMac && !DMCCPOtherCC();
    DMCC18SetWanted(want);
    if (want == gCC18On) { gCC18Pending = NO; return; }
    if (gCC18Hooked ? gCC18Shown : DMControlCenterActive()) {
        if (!gCC18Pending) DMLog([NSString stringWithFormat:@"[cc18] style %@ (%@): when Control Center closes", want ? @"Mac" : @"iPadOS", why]);
        gCC18Pending = YES;
        unsigned gen = ++gCC18PendingGen;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gCC18Pending && gen == gCC18PendingGen) DMCC18ApplyStyle(@"Control Center closed"); });
        return;
    }
    gCC18Pending = NO;
    if (want && !DMCC18InstallHooks()) { DMCC18SetWanted(NO); return; }
    gCC18On = want;
    if (want) DM_FEATURE_MARK("cc-mac-18");
    UIViewController *m = gCC18InConstructor ? nil : DMCC18FindMain();
    gCC18Editing = m.isViewLoaded && DMCCTypes(m, @"isEditing", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(m, NSSelectorFromString(@"isEditing"));
    if (m.isViewLoaded) DMCC18LayoutFollowsStyle(m);
    if (m.isViewLoaded) DMCC18Relayout(want ? @"Mac chosen" : @"iPadOS chosen");   // (else at Apple's build: our insets are asked then)
    DMLog([NSString stringWithFormat:@"[cc18] style %@ (%@)%@", want ? @"Mac" : @"iPadOS", why, m.isViewLoaded ? @"" : @": at Apple's build"]);
}
static void DMCC18PrefsChanged(void) { if (gCC18Supported) DMCC18ApplyStyle(@"the preference changed"); }
// Control Center's own status bar copies are not dressed as our menu bar while the panel shows: its header is hidden then, our bar shows.
static BOOL DMCC18OwnsCCBars(void) { return gCC18On && !gCC18Editing && gCC18Material.superview != nil; }

// ---- the start -----------------------------------------------------------------------------------------------------------------------------
// %ctor, before Apple builds Control Center (7 s after the start on the A12Z): the check on 18 (its verdict for Settings whatever the style), then
// the hooks only if Mac is chosen. Not on other majors (15-17: CCPanel.h; after 18: never read).
static void DMCC18Init(void) {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion != 18) return;
    CFTimeInterval t0 = CACurrentMediaTime();
    gCC18CheckOptional = [NSMutableArray array];
    NSUInteger checked = 0;
    NSArray<NSString *> *bad = DMCC18CheckAPI(&checked);
    gCC18Supported = bad.count == 0;
    NSString *reason = gCC18Supported ? nil : [NSString stringWithFormat:@"%@: %lu of the system methods our Control Center uses are missing or different", DMCCPOSLabel(), (unsigned long)bad.count];
    DMCCPPublishVerdict(gCC18Supported, reason, bad, gCC18CheckOptional);
    if (MSBDDiagEnabled()) MSBDDiagWrite(@"ControlCenter", [NSString stringWithFormat:@"check (18): %@ (%lu rows)%@\n", gCC18Supported ? @"ok" : reason, (unsigned long)checked,
        bad.count ? [@"\nfailed: " stringByAppendingString:[bad componentsJoinedByString:@"; "]] : @""]);
    DMLog([NSString stringWithFormat:@"[cc18] API check: %@ (%lu rows, %.2f ms)", gCC18Supported ? @"passed" : reason, (unsigned long)checked, (CACurrentMediaTime() - t0) * 1000.0]);
    for (NSString *l in bad) DMLog([@"[cc18]   " stringByAppendingString:l]);
    if (!gCC18Supported) return;
    gCC18InConstructor = YES;
    DMCC18ApplyStyle(@"start");
    gCC18InConstructor = NO;
}

#if DEBUG
// ---- debug read-outs and triggers (c18m_*) -------------------------------------------------------------------------------------------------
static NSString *DMCC18ColorName(UIColor *c) {
    if (!c) return @"-";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) { CGFloat w = 0; if ([c getWhite:&w alpha:&a]) return [NSString stringWithFormat:@"w%.2f/a%.2f", w, a]; return [c description]; }
    return [NSString stringWithFormat:@"rgb(%.0f,%.0f,%.0f)/a%.2f", r * 255, g * 255, b * 255, a];
}
static NSString *DMCC18ScreenRect(UIView *v) {
    if (![v isKindOfClass:[UIView class]]) return @"-";
    CGRect r = v.window ? [v convertRect:v.bounds toCoordinateSpace:v.window.screen.coordinateSpace] : CGRectNull;
    return [NSString stringWithFormat:@"%@ %@ h%d a%.2f", NSStringFromClass([v class]), CGRectIsNull(r) ? @"(no window)" : NSStringFromCGRect(r), v.hidden, v.alpha];
}
// c18m_state: the shape, its views and Apple's pieces it moves
static void DMCC18State(void) {
    UIViewController *m = DMCC18FindMain();
    UIView *header = DMCC18ViewOf(m, @"overlayHeaderView"), *dots = DMCC18ViewOf(m, @"overlayPageControl"), *back = DMCC18ViewOf(m, @"overlayBackgroundView");
    DMLog([NSString stringWithFormat:@"[cc18] state: supported %d hooked %d on %d pending %d want %d shown %d editing %d expanded %d locked %d; bar %.1f (stock %.1f), panel top %.1f, grid %@, rtl %d",
        gCC18Supported, gCC18Hooked, gCC18On, gCC18Pending, gCC18Want, gCC18Shown, gCC18Editing, gCC18Expanded, DMCCPLockedNow(), DMMenuBarHeight(), DMMenuBarStockHeight(), gCC18PanelTop, NSStringFromCGRect(gCC18Grid), gCC18GridRTL]);
    DMLog([NSString stringWithFormat:@"[cc18] state: material %@; row %@; route %@", DMCC18ScreenRect(gCC18Material.superview ? gCC18Material : nil), DMCC18ScreenRect(gCC18Row.superview ? gCC18Row : nil), DMCC18ScreenRect(gCC18Route.superview ? gCC18Route : nil)]);
    DMLog([NSString stringWithFormat:@"[cc18] state: + %@ in %@; power %@ in %@", DMCC18ScreenRect(DMCC18ViewOf(header, @"editButton")), NSStringFromClass([DMCC18ViewOf(header, @"editButton").superview class]),
        DMCC18ScreenRect(DMCC18ViewOf(header, @"powerButton")), NSStringFromClass([DMCC18ViewOf(header, @"powerButton").superview class])]);
    UIPageControl *pc = [dots isKindOfClass:[UIPageControl class]] ? (UIPageControl *)dots : nil;
    DMLog([NSString stringWithFormat:@"[cc18] state: dots %@ in %@ (their capsule %@), page %ld of %ld; backdrop %@; header %@; rows on this page %.1f", DMCC18ScreenRect(dots), NSStringFromClass([dots.superview class]),
        DMCC18ScreenRect(gCC18DotsPill.superview ? gCC18DotsPill : nil), pc ? (long)pc.currentPage : -1L, pc ? (long)pc.numberOfPages : -1L, DMCC18ScreenRect(back), DMCC18ScreenRect(header), m ? DMCC18RowsHeight(m) : -1]);
    DMLog([NSString stringWithFormat:@"[cc18] state: sensor part %d, attribution shows %d, its control %@ (Apple's place %@), the header's own views hidden by us %lu", gCC18HaveSensor, DMCC18SensorShows(header),
        DMCC18ScreenRect(DMCC18ViewOf(header, @"compactSensorAttributionControl")), gCC18HaveSensor && o_DMCC18SensorFrame && header ? NSStringFromCGRect(o_DMCC18SensorFrame(header, NSSelectorFromString(@"compactModeFrameForSensorView"))) : @"-", (unsigned long)gCC18HidHeaderParts.count]);
}
// c18m_header: Apple's header's views (frames, hidden, alpha, constraints on them, Auto Layout) and its edge insets, read-only
static void DMCC18Header(void) {
    UIView *h = DMCC18ViewOf(DMCC18FindMain(), @"overlayHeaderView");
    if (!h) { DMLog(@"[cc18] header: none"); return; }
    UIEdgeInsets ei = DMCCTypes(h, @"edgeInsets", kDMCC18InsetsT "16@0:8") ? ((UIEdgeInsets (*)(id, SEL))objc_msgSend)(h, NSSelectorFromString(@"edgeInsets")) : UIEdgeInsetsMake(-1, -1, -1, -1);
    DMLog([NSString stringWithFormat:@"[cc18] header %@ bounds %@ transform %@ edgeInsets %@ constraints %lu", DMCC18ScreenRect(h), NSStringFromCGRect(h.bounds), NSStringFromCGAffineTransform(h.transform), NSStringFromUIEdgeInsets(ei), (unsigned long)h.constraints.count]);
    for (UIView *s in h.subviews) {
        int n = 0; for (NSLayoutConstraint *c in h.constraints) if (c.firstItem == s || c.secondItem == s) n++;
        DMLog([NSString stringWithFormat:@"[cc18]   %@ frame %@ autoresizing->constraints %d, constraints with the header %d, own %lu, transform %@", DMCC18ScreenRect(s), NSStringFromCGRect(s.frame), s.translatesAutoresizingMaskIntoConstraints, n, (unsigned long)s.constraints.count,
            NSStringFromCGAffineTransform(s.transform)]);
    }
    for (UIView *b in @[gCC18Edit ?: (id)[NSNull null], gCC18Power ?: (id)[NSNull null]]) if ([b isKindOfClass:[UIView class]]) DMLog([NSString stringWithFormat:@"[cc18]   (in our row) %@ frame %@ transform %@", DMCC18ScreenRect(b), NSStringFromCGRect(b.frame), NSStringFromCGAffineTransform(b.transform)]);
}
// c18m_tree_<depth>: the main controller's views (class, screen frame, hidden, alpha, touches, recognizers), read-only
static void DMCC18TreeOf(UIView *v, int depth, int max, int *n) {
    if (!v || *n > 500) return;
    (*n)++;
    NSMutableArray *g = [NSMutableArray array]; for (UIGestureRecognizer *r in v.gestureRecognizers) [g addObject:NSStringFromClass([r class])];
    DMLog([NSString stringWithFormat:@"[cc18] tree %@%@ t%d g:%@", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], DMCC18ScreenRect(v), v.userInteractionEnabled, g.count ? [g componentsJoinedByString:@","] : @"-"]);
    if (depth < max) for (UIView *s in v.subviews) DMCC18TreeOf(s, depth + 1, max, n);
}
// c18m_tint: the colours of Apple's Connectivity buttons as drawn now -- each round button (its class, the controller it belongs to, selected or
// not) with the colours in its views (background, tint, a layer's fill) -- on 15-17 too (any Control Center window; our own tiles' circles as
// well): Airplane Mode's on-state is Apple's orange, not the blue of Wi-Fi (KT 3 Nov). Read-only.
static UIViewController *DMCC18OwnerVC(UIView *v) {
    SEL near = NSSelectorFromString(@"_viewControllerForAncestor");
    for (UIView *x = v; x; x = x.superview) { id r = [x respondsToSelector:near] ? ((id (*)(id, SEL))objc_msgSend)(x, near) : nil; if (r) return r; }
    return nil;
}
static void DMCC18ColorsUnder(UIView *v, int depth, NSMutableArray *out) {
    if (!v || depth > 6 || out.count > 40) return;
    NSMutableArray *c = [NSMutableArray array];
    if (v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor) > 0.01) [c addObject:[@"bg " stringByAppendingString:DMCC18ColorName(v.backgroundColor)]];
    if (v.layer.backgroundColor && CGColorGetAlpha(v.layer.backgroundColor) > 0.01) [c addObject:[@"layer " stringByAppendingString:DMCC18ColorName([UIColor colorWithCGColor:v.layer.backgroundColor])]];
    if ([v isKindOfClass:[UIImageView class]] || [v isKindOfClass:objc_getClass("CCUICAPackageView") ?: [UIImageView class]]) [c addObject:[@"tint " stringByAppendingString:DMCC18ColorName(v.tintColor)]];
    for (CALayer *l in v.layer.sublayers) if (l.backgroundColor && CGColorGetAlpha(l.backgroundColor) > 0.01 && out.count < 40) [c addObject:[NSString stringWithFormat:@"sublayer %@ %@", NSStringFromClass([l class]), DMCC18ColorName([UIColor colorWithCGColor:l.backgroundColor])]];
    if (c.count) [out addObject:[NSString stringWithFormat:@"%@%@ %@", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0], NSStringFromClass([v class]), [c componentsJoinedByString:@", "]]];
    for (UIView *s in v.subviews) if (!s.hidden && s.alpha > 0.01) DMCC18ColorsUnder(s, depth + 1, out);
}
static void DMCC18Tint(BOOL fakeAirplane, BOOL fakeOn) {
    int found = 0;
    for (UIWindow *w in DMAllWindows()) {
        if (![NSStringFromClass([w class]) isEqualToString:@"SBControlCenterWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            NSString *cls = NSStringFromClass([v class]);
            if ([cls isEqualToString:@"DMCCTConnRow"]) {   // (our own Connectivity rows on 15-17: Airplane Mode Apple's orange when on, Wi-Fi and Bluetooth macOS's blue)
                UIView *circle = [v valueForKey:@"circle"]; UILabel *title = [v valueForKey:@"title"];
                DMLog([NSString stringWithFormat:@"[cc18] tint: our %@ row at %@: circle %@", title.text, DMCC18ScreenRect(v), DMCC18ColorName(circle.backgroundColor)]);
                found++; continue;
            }
            BOOL round = [cls containsString:@"RoundButton"] && ![cls containsString:@"Labeled"];
            if (!round) { for (UIView *s in v.subviews) [todo addObject:s]; continue; }
            UIViewController *vc = DMCC18OwnerVC(v);
            NSString *owner = NSStringFromClass([vc class]);
            BOOL selected = [v isKindOfClass:[UIControl class]] && ((UIControl *)v).selected;
            if (fakeAirplane && [owner containsString:@"Airplane"] && [v isKindOfClass:[UIControl class]]) {   // (the button's look only: no action is sent, the radio is never asked)
                ((UIControl *)v).selected = fakeOn; selected = fakeOn;
                DMLog([NSString stringWithFormat:@"[cc18] tint: %@'s button shown %@ (its look only: no action, the radio untouched)", owner, fakeOn ? @"on" : @"as it was"]);
            }
            NSMutableArray *colors = [NSMutableArray array];
            DMCC18ColorsUnder(v, 0, colors);
            DMLog([NSString stringWithFormat:@"[cc18] tint: %@ of %@ selected %d at %@: %@", cls, owner, selected, DMCC18ScreenRect(v), [colors componentsJoinedByString:@" | "]]);
            found++;
        }
    }
    DMLog([NSString stringWithFormat:@"[cc18] tint: %d round buttons in Control Center's windows", found]);
}
// c18m_ax: the accessibility elements of Control Center's window in the order assistive features walk them (an element's own, or a container's
// -accessibilityElements / its elements by index, else its subviews in order; hidden views and hidden elements skipped), with label, value,
// traits and frame -- Apple's + and power buttons must be among them while they are in our row; our material and routing layer never (read-only)
static void DMCC18AXWalk(id e, int depth, NSMutableArray *out) {
    if (!e || depth > 40 || out.count > 200) return;
    if ([e isKindOfClass:[UIView class]]) { UIView *v = e; if (v.hidden || v.alpha < 0.01 || v.accessibilityElementsHidden) return; }
    if ([e respondsToSelector:@selector(isAccessibilityElement)] && [e isAccessibilityElement]) {
        CGRect f = [e respondsToSelector:@selector(accessibilityFrame)] ? [e accessibilityFrame] : CGRectNull;
        [out addObject:[NSString stringWithFormat:@"%@ \"%@\" value \"%@\" traits 0x%llx %@", NSStringFromClass([e class]), [e accessibilityLabel] ?: @"", [e accessibilityValue] ?: @"", (unsigned long long)[e accessibilityTraits], NSStringFromCGRect(f)]];
        return;
    }
    NSArray *els = [e respondsToSelector:@selector(accessibilityElements)] ? [e accessibilityElements] : nil;
    if (els.count) { for (id c in els) DMCC18AXWalk(c, depth + 1, out); return; }
    NSInteger n = [e respondsToSelector:@selector(accessibilityElementCount)] ? [e accessibilityElementCount] : 0;
    if (n > 0 && n != NSNotFound) { for (NSInteger i = 0; i < n && i < 200; i++) DMCC18AXWalk([e accessibilityElementAtIndex:i], depth + 1, out); return; }
    if ([e isKindOfClass:[UIView class]]) for (UIView *sub in ((UIView *)e).subviews) DMCC18AXWalk(sub, depth + 1, out);
}
static void DMCC18AX(void) {
    UIViewController *m = DMCC18FindMain();
    if (!m.viewIfLoaded.window) { DMLog(@"[cc18] ax: Control Center is not in a window"); return; }
    NSMutableArray *out = [NSMutableArray array];
    DMCC18AXWalk(m.view, 0, out);
    NSMutableString *s = [NSMutableString stringWithFormat:@"[cc18] ax: %lu elements in Control Center's main view (VoiceOver %d)", (unsigned long)out.count, UIAccessibilityIsVoiceOverRunning()];
    for (NSUInteger i = 0; i < out.count; i++) [s appendFormat:@"\n  %2lu %@", (unsigned long)i + 1, out[i]];
    DMLog(s);
}
static void DMCC18DebugTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"c18m_state"]) DMCC18State();
    else if ([cmd isEqualToString:@"c18m_ax"]) DMCC18AX();
    else if ([cmd isEqualToString:@"c18m_header"]) DMCC18Header();
    else if ([cmd hasPrefix:@"c18m_tree"]) { UIViewController *m = DMCC18FindMain(); int n = 0; if (m.isViewLoaded) DMCC18TreeOf(m.view, 0, cmd.length > 10 ? [[cmd substringFromIndex:10] intValue] : 3, &n); else DMLog(@"[cc18] tree: no Control Center yet"); }
    else if ([cmd isEqualToString:@"c18m_tint"]) DMCC18Tint(NO, NO);
    else if ([cmd isEqualToString:@"c18m_fakeair_1"] || [cmd isEqualToString:@"c18m_fakeair_0"]) DMCC18Tint(YES, [cmd hasSuffix:@"_1"]);
    else if ([cmd isEqualToString:@"c18m_relayout"]) DMCC18Relayout(@"debug");
    else if ([cmd hasPrefix:@"c18m_turnsim_"]) {   // c18m_turnsim_<dx|none>: what a turn does to an open page: the grid dx points further on (none: no place left for it), our views as after Apple's layout; c18m_relayout: the grid back
        NSString *arg = [cmd substringFromIndex:13];
        gCC18Grid = [arg isEqualToString:@"none"] ? CGRectZero : CGRectOffset(gCC18Grid, arg.doubleValue, 0);
        DMCC18Views(@"a turn simulated");
        DMLog([NSString stringWithFormat:@"[cc18] a turn simulated: grid %@, material %@ on the view %d, page %@", NSStringFromCGRect(gCC18Grid), NSStringFromCGRect(gCC18Material.frame), gCC18Material.superview != nil, gCCPDetail ? NSStringFromCGRect(gCCPDetail.frame) : @"closed"]);
    }
    else if ([cmd isEqualToString:@"c18m_layout"]) {   // the file Apple's model has, the model's page sizes (read-only)
        UIViewController *m = DMCC18FindMain(); id model = DMCCGet(DMCCGet(m, @"pagingViewController"), @"iconModel"), store = DMCCGet(model, @"store");
        DMLog([NSString stringWithFormat:@"[cc18] layout: model %@, store %@, file %@, desired %@", model ? NSStringFromClass([model class]) : @"-", store ? NSStringFromClass([store class]) : @"-", [DMCCGet(store, @"currentIconStateURL") path], [DMCCGet(store, @"desiredIconStateURL") path]]);
    }
    else if ([cmd isEqualToString:@"c18m_layout_forget"]) { [[NSFileManager defaultManager] removeItemAtPath:kMSBDCC18MacLayoutFile error:nil]; DMLog(@"[cc18] the Mac layout file removed"); }
    else if ([cmd isEqualToString:@"c18m_layout_follow"]) DMCC18LayoutFollowsStyle(DMCC18FindMain());
    else if ([cmd isEqualToString:@"c18m_apply"]) DMCC18ApplyStyle(@"debug");
    else if ([cmd isEqualToString:@"c18m_api"]) {
        for (size_t i = 0; i < sizeof(kDMCC18Hooks) / sizeof(kDMCC18Hooks[0]); i++) DMLog([NSString stringWithFormat:@"[cc18] api hook -[%s %s]: %@", kDMCC18Hooks[i].cls, kDMCC18Hooks[i].sel, DMCC18RowProblem(kDMCC18Hooks[i].cls, kDMCC18Hooks[i].sel, kDMCC18Hooks[i].enc, NO, NO) ?: @"as expected"]);
        for (size_t i = 0; i < sizeof(kDMCC18Needs) / sizeof(kDMCC18Needs[0]); i++) DMLog([NSString stringWithFormat:@"[cc18] api %s %s: %@", kDMCC18Needs[i].cls, kDMCC18Needs[i].sel, DMCC18RowProblem(kDMCC18Needs[i].cls, kDMCC18Needs[i].sel, kDMCC18Needs[i].enc, kDMCC18Needs[i].ivar, kDMCC18Needs[i].meta) ?: @"as expected"]);
    }
    else if ([cmd isEqualToString:@"c18m_open"] || [cmd isEqualToString:@"c18m_close"]) {   // (Apple's own present / dismiss, as our Control Center icon calls them)
        id cc = DMControlCenterController();
        SEL s = NSSelectorFromString([cmd hasSuffix:@"_open"] ? @"presentAnimated:" : @"dismissAnimated:");
        if (DMCCTypes(cc, NSStringFromSelector(s), "v20@0:8B16")) ((void (*)(id, SEL, BOOL))objc_msgSend)(cc, s, YES);
        DMLog([NSString stringWithFormat:@"[cc18] %@ through %@", cmd, cc ? NSStringFromClass([cc class]) : @"no controller"]);
    }
    else if ([cmd hasPrefix:@"c18m_expand_"]) {   // c18m_expand_<module>: Apple's own expansion of a tile's module (as a hold)
        UIViewController *m = DMCC18FindMain();
        if (DMCCTypes(m, @"expandModuleWithIdentifier:", "v24@0:8@16")) ((void (*)(id, SEL, id))objc_msgSend)(m, NSSelectorFromString(@"expandModuleWithIdentifier:"), [cmd substringFromIndex:12]);
    }
    else if ([cmd isEqualToString:@"c18m_edit_1"] || [cmd isEqualToString:@"c18m_edit_0"]) {   // (Apple's own edit mode, as a long press asks for it)
        UIViewController *m = DMCC18FindMain();
        if (DMCCTypes(m, @"setEditing:", "v20@0:8B16")) ((void (*)(id, SEL, BOOL))objc_msgSend)(m, NSSelectorFromString(@"setEditing:"), [cmd hasSuffix:@"_1"]);
    }
}
#endif
