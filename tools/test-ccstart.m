// test-ccstart.m -- Mac test of a Control Center Style change in SpringBoard's first seconds (1.8.1 item 16, review 1.8.0.1 finding 1). It runs the code as built:
// test-ccstart.sh cuts DMCCPFindOverlay, DMCCPApplyStyle (statusbar/CCPanel.h), DMCC18MainIfOurs, DMCC18FindMain, DMCC18ApplyStyle and DMCC18StoreInit (statusbar/CC18Shape.h)
// out of the sources into ccstart-gen.h, and this file gives them stand-ins for UIKit, SpringBoard and the rest of the panel. The lookups answered nil for the first 8 s after our
// constructor while Control Center's window had not been seen: a change to Mac there, after Apple's -viewDidLoad had run without our hooks, was in force with nothing built, and
// every later look stopped at want == on until the next respring. A style's on state means here: applied, or to be applied by our hooks as Apple builds it.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include "../common/CCStyle.h"
#include "../common/CC18MacLayout.h"
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit's parts these functions read ------------------------------------------------------------------------------------------------------
@interface UIScreen : NSObject + (UIScreen *)mainScreen; @end
@implementation UIScreen + (UIScreen *)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; } @end
@interface UIWindow : NSObject @property (nonatomic, strong) UIScreen *screen; @end
@implementation UIWindow @end
@interface UIView : NSObject @property (nonatomic, strong) UIWindow *window; @end
@implementation UIView @end
@interface UIViewController : NSObject
@property (nonatomic) BOOL isViewLoaded;
@property (nonatomic, strong) UIView *viewIfLoaded;
@end
@implementation UIViewController @end
// ---- Apple's controllers, by their names (the sources find them with objc_getClass) -----------------------------------------------------------
@interface CCUIModularControlCenterOverlayViewController : UIViewController @end
@implementation CCUIModularControlCenterOverlayViewController @end
@interface CCUIMainViewController : UIViewController @property (nonatomic) BOOL isEditing; @end
@implementation CCUIMainViewController @end
#define kDMCCPOverlay "CCUIModularControlCenterOverlayViewController"
#define kDMCC18Main "CCUIMainViewController"

// ---- SpringBoard as it stands at that moment ---------------------------------------------------------------------------------------------------
static id gController = nil;               // (the controller SpringBoard made; nil: not yet)
static UIViewController *gVC = nil;        // (what its -viewController reads)
static int gAsked = 0;                     // (how often the lookup asked SpringBoard)
static BOOL gCCWindowSeen = NO, gStartingNow = NO;   // (what the old lookups' refusal read: a copy of the old sources compiles and fails its rows)
static BOOL gShowing = NO, gMacStored = NO;
static id DMControlCenterController(void) { gAsked++; return gController; }
static id DMCCGet(id target, NSString *sel) { return target && [sel isEqualToString:@"viewController"] ? gVC : nil; }
static BOOL DMCCTypes(id target, NSString *sel, const char *types) { return [target respondsToSelector:NSSelectorFromString(sel)]; }
static BOOL DMStarting(void) { return gStartingNow; }
static BOOL DMControlCenterActive(void) { return gShowing; }
static void DMLog(NSString *s) { }
#define DM_FEATURE_MARK(x)
static int DMCCStyleChosenNow(void) { return gMacStored ? kMSBDCCStyleMac : kMSBDCCStyleStock; }
static BOOL DMCCPOtherCC(void) { return NO; }

// ---- the rest of the 15-17 panel: what it was asked to do ----------------------------------------------------------------------------------------
static BOOL gCCPSupported = YES, gCCPOn = NO, gCCPPending = NO, gCCPInConstructor = NO;
static unsigned gCCPPendingGen = 0;
static __weak UIViewController *gCCPOverlay;
static int gBuilt = 0, gGaveBack = 0, gHooks = 0;
static BOOL DMCCPStyleIsMac(void) { return gMacStored; }
static void DMCCPSetWanted(BOOL want) { }
static void DMCCPGiveBack(NSString *why) { gGaveBack++; gCCPOn = NO; }
static BOOL gCCPHookedNow = NO;
static BOOL DMCCPInstallHooks(void) { if (!gCCPHookedNow) gHooks++; gCCPHookedNow = YES; return YES; }
static void DMCCPBuildLive(UIViewController *ov) { gBuilt++; gCCPOverlay = ov; }
// ---- ... and of the 18 shape ------------------------------------------------------------------------------------------------------------------------
static BOOL gCC18Supported = YES, gCC18Hooked = NO, gCC18On = NO, gCC18Pending = NO, gCC18Shown = NO, gCC18Editing = NO, gCC18InConstructor = NO, gCC18HaveTiles = YES, gCC18MacLayoutInForce = NO;
static unsigned gCC18PendingGen = 0;
static __weak UIViewController *gCC18Main;
static NSURL *gCC18AppleDesired;
static int gFollowed = 0, gRelaid = 0;
static NSString *gStoreRead = nil;   // (the file Apple's store was made with)
static void DMCC18SetWanted(BOOL want) { }
static BOOL DMCC18InstallHooks(void) { if (!gCC18Hooked) gHooks++; gCC18Hooked = YES; return YES; }
static void DMCC18LayoutFollowsStyle(UIViewController *m) { gFollowed++; gCC18MacLayoutInForce = gCC18On; }
static void DMCC18Relayout(NSString *why) { gRelaid++; }
static NSURL *DMCC18MacLayoutURL(void) { return [NSURL fileURLWithPath:kMSBDCC18MacLayoutFile]; }
static id o_DMCC18StoreInit(id self, SEL _cmd, NSURL *current, NSURL *desired) { gStoreRead = current.lastPathComponent; return self; }

#include "ccstart-gen.h"   // (the code as built)

static void World(BOOL macStored, BOOL on) {
    gController = nil; gVC = nil; gAsked = 0; gCCWindowSeen = NO; gStartingNow = YES; gShowing = NO; gMacStored = macStored;
    gCCPOn = on; gCCPPending = NO; gCCPInConstructor = NO; gCCPOverlay = nil; gBuilt = gGaveBack = gHooks = 0; gCCPHookedNow = on;
    gCC18On = on; gCC18Hooked = on; gCC18Pending = NO; gCC18Shown = NO; gCC18Editing = NO; gCC18InConstructor = NO; gCC18Main = nil; gCC18MacLayoutInForce = on; gFollowed = gRelaid = 0; gStoreRead = nil;
}
// Apple's build has run: the controller, its overlay, the view, in a window on the iPad's own screen
static UIViewController *AppleBuilt(Class c) {
    gController = [NSObject new];
    UIViewController *v = [c new];
    v.isViewLoaded = YES; v.viewIfLoaded = [UIView new]; v.viewIfLoaded.window = [UIWindow new]; v.viewIfLoaded.window.screen = [UIScreen mainScreen];
    gVC = v;
    return v;
}

int main(void) {
    @autoreleasepool {
        // ---- 15-17 ----
        World(YES, NO); gCCPInConstructor = YES; DMCCPApplyStyle(@"start");
        Expect(gCCPOn && gHooks == 1 && gBuilt == 0 && gAsked == 0, @"15-17, the constructor's look with Mac: on, the hooks in for Apple's build, nothing asked of SpringBoard (its launch has not begun)");
        World(NO, NO); gCCPInConstructor = YES; DMCCPApplyStyle(@"start");
        Expect(!gCCPOn && gHooks == 0 && gAsked == 0, @"  ... with iPadOS: nothing at all");
        World(NO, NO); UIViewController *ov = AppleBuilt([CCUIModularControlCenterOverlayViewController class]); DMCCPApplyStyle(@"the preference changed");
        Expect(!gCCPOn && gBuilt == 0 && gGaveBack == 0 && gHooks == 0 && gAsked == 0, @"  no change of style in the first seconds (our settings told SpringBoard something else): nothing asked, nothing built");
        World(YES, NO); ov = AppleBuilt([CCUIModularControlCenterOverlayViewController class]); DMCCPApplyStyle(@"the preference changed");
        Expect(gCCPOn && gHooks == 1 && gBuilt == 1, @"15-17, iPadOS to Mac in the first seconds, Apple built without our hooks, its window not seen: applied live (the bug: on with nothing built)");
        DMCCPApplyStyle(@"the preference changed");
        Expect(gBuilt == 1 && gHooks == 1, @"  ... a later look: nothing again");
        World(YES, NO); ov = AppleBuilt([CCUIModularControlCenterOverlayViewController class]); gCCWindowSeen = YES; DMCCPApplyStyle(@"the preference changed");
        Expect(gCCPOn && gBuilt == 1, @"  ... its window seen: applied live, as before");
        World(YES, NO); ov = AppleBuilt([CCUIModularControlCenterOverlayViewController class]); gStartingNow = NO; DMCCPApplyStyle(@"the preference changed");
        Expect(gCCPOn && gBuilt == 1, @"  ... after the first seconds: applied live, as before");
        World(YES, NO); DMCCPApplyStyle(@"the preference changed");
        Expect(gCCPOn && gHooks == 1 && gBuilt == 0, @"  ... SpringBoard has not made the controller yet: on, the hooks in, Apple's -viewDidLoad builds it; nothing made by us");
        World(YES, NO); ov = AppleBuilt([CCUIModularControlCenterOverlayViewController class]); ov.isViewLoaded = NO; DMCCPApplyStyle(@"the preference changed");
        Expect(gCCPOn && gHooks == 1 && gBuilt == 0, @"  ... the overlay made, its view not loaded: on, the hooks in, Apple's -viewDidLoad builds it");
        World(YES, NO); ov = AppleBuilt([CCUIModularControlCenterOverlayViewController class]); gShowing = YES; DMCCPApplyStyle(@"the preference changed");
        Expect(!gCCPOn && gCCPPending && gBuilt == 0, @"  ... Control Center showing: it waits for the close, as always");
        gShowing = NO; DMCCPApplyStyle(@"Control Center closed");
        Expect(gCCPOn && !gCCPPending && gBuilt == 1, @"  ... closed: applied live");
        World(NO, YES); DMCCPApplyStyle(@"the preference changed");
        Expect(!gCCPOn && gGaveBack == 1 && gBuilt == 0, @"15-17, Mac to iPadOS in the first seconds: given back");
        World(YES, NO); ov = AppleBuilt([CCUIModularControlCenterOverlayViewController class]); DMCCPApplyStyle(@"x"); gMacStored = NO; DMCCPApplyStyle(@"x"); gMacStored = YES; DMCCPApplyStyle(@"x");
        Expect(gCCPOn && gBuilt == 2 && gGaveBack == 1 && gHooks == 1, @"  iPadOS, Mac, iPadOS, Mac in the first seconds: each applied");

        // ---- 18 ----
        World(YES, NO); gCC18InConstructor = YES; DMCC18ApplyStyle(@"start");
        Expect(gCC18On && gHooks == 1 && gFollowed == 0 && gRelaid == 0 && gAsked == 0, @"18, the constructor's look with Mac: on, the hooks in for Apple's build, nothing asked of SpringBoard");
        DMCC18StoreInit([NSObject new], NULL, [NSURL fileURLWithPath:kMSBDCC18AppleLayoutFile], [NSURL fileURLWithPath:@"/d.plist"]);
        Expect([gStoreRead isEqualToString:kMSBDCC18MacLayoutFile.lastPathComponent] && gCC18MacLayoutInForce, @"  ... Apple's build makes the tiles' store: the Mac layout, as before");
        World(NO, NO); gCC18InConstructor = YES; DMCC18ApplyStyle(@"start");
        Expect(!gCC18On && gHooks == 0 && gAsked == 0, @"  ... with iPadOS: nothing at all");
        World(NO, NO); UIViewController *m = AppleBuilt([CCUIMainViewController class]); DMCC18ApplyStyle(@"the preference changed");
        Expect(!gCC18On && gFollowed == 0 && gRelaid == 0 && gHooks == 0 && gAsked == 0, @"  no change of style in the first seconds: nothing asked, nothing laid out");
        World(YES, NO); m = AppleBuilt([CCUIMainViewController class]); DMCC18ApplyStyle(@"the preference changed");
        Expect(gCC18On && gHooks == 1 && gFollowed == 1 && gRelaid == 1 && gCC18Main == m && gCC18MacLayoutInForce, @"18, iPadOS to Mac in the first seconds, Apple built without our hooks, its window not seen: the Mac layout in Apple's live steps, laid out again (the bug: on, Apple's tiles)");
        DMCC18ApplyStyle(@"the preference changed");
        Expect(gFollowed == 1 && gRelaid == 1, @"  ... a later look: nothing again");
        World(NO, YES); m = AppleBuilt([CCUIMainViewController class]); DMCC18ApplyStyle(@"the preference changed");
        Expect(!gCC18On && gFollowed == 1 && gRelaid == 1 && gCC18Main == m && !gCC18MacLayoutInForce, @"18, Mac to iPadOS in the first seconds, before any hook of ours learned Apple's controller: Apple's layout back in the live steps (the bug: iPadOS's look on the Mac layout's tiles)");
        World(NO, YES); m = AppleBuilt([CCUIMainViewController class]); gCC18Main = m; DMCC18ApplyStyle(@"the preference changed");
        Expect(!gCC18On && gFollowed == 1 && gRelaid == 1, @"  ... the controller learned from a hook: the same, as before");
        World(YES, NO); m = AppleBuilt([CCUIMainViewController class]); gCCWindowSeen = YES; DMCC18ApplyStyle(@"the preference changed");
        Expect(gCC18On && gFollowed == 1 && gRelaid == 1, @"18, iPadOS to Mac, its window seen: live, as before");
        World(YES, NO); m = AppleBuilt([CCUIMainViewController class]); gStartingNow = NO; DMCC18ApplyStyle(@"the preference changed");
        Expect(gCC18On && gFollowed == 1 && gRelaid == 1, @"  ... after the first seconds: live, as before");
        World(YES, NO); DMCC18ApplyStyle(@"the preference changed");
        Expect(gCC18On && gHooks == 1 && gFollowed == 0 && gRelaid == 0, @"18, iPadOS to Mac, SpringBoard has not made the controller yet: on, the hooks in, nothing laid out or made by us");
        DMCC18StoreInit([NSObject new], NULL, [NSURL fileURLWithPath:kMSBDCC18AppleLayoutFile], [NSURL fileURLWithPath:@"/d.plist"]);
        Expect([gStoreRead isEqualToString:kMSBDCC18MacLayoutFile.lastPathComponent], @"  ... Apple's -viewDidLoad makes the tiles' store: the Mac layout");
        World(NO, YES); DMCC18ApplyStyle(@"the preference changed");
        Expect(!gCC18On && gFollowed == 0 && gRelaid == 0, @"18, Mac to iPadOS before SpringBoard made it: off, nothing laid out");
        DMCC18StoreInit([NSObject new], NULL, [NSURL fileURLWithPath:kMSBDCC18AppleLayoutFile], [NSURL fileURLWithPath:@"/d.plist"]);
        Expect([gStoreRead isEqualToString:kMSBDCC18AppleLayoutFile.lastPathComponent], @"  ... Apple's -viewDidLoad makes the store: Apple's file");
        World(YES, NO); m = AppleBuilt([CCUIMainViewController class]); m.isViewLoaded = NO; m.viewIfLoaded = nil; DMCC18ApplyStyle(@"the preference changed");
        Expect(gCC18On && gHooks == 1 && gFollowed == 0 && gRelaid == 0, @"18, the controller made, its view not loaded: on, nothing laid out (its -viewDidLoad makes the store: our hook picks the file then)");
        World(YES, YES); gCC18On = NO; gCC18Hooked = YES; m = AppleBuilt([CCUIMainViewController class]); gCC18Shown = YES; DMCC18ApplyStyle(@"the preference changed");
        Expect(!gCC18On && gCC18Pending && gFollowed == 0, @"18, Control Center showing: it waits for the close, as always");
        gCC18Shown = NO; DMCC18ApplyStyle(@"Control Center closed");
        Expect(gCC18On && !gCC18Pending && gFollowed == 1 && gRelaid == 1, @"  ... closed: live");
        World(YES, NO); m = AppleBuilt([CCUIMainViewController class]); DMCC18ApplyStyle(@"x"); gMacStored = NO; DMCC18ApplyStyle(@"x"); gMacStored = YES; DMCC18ApplyStyle(@"x");
        Expect(gCC18On && gFollowed == 3 && gRelaid == 3 && gHooks == 1, @"  iPadOS, Mac, iPadOS, Mac in the first seconds: each applied, the layout with it");
    }
    printf("test-ccstart: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
