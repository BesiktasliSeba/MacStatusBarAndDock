// test-typingends.m (1.8.8.2, B74): the desktop's typing (a sticky note, a name) ends at a layout transition SpringBoard begins when Spotlight is
// presented or the iPad's display goes to a full-screen window or app. Built by test-typingends.sh with cut.h: the real DMDesktopTypingGet,
// DMDesktopTypingAtTransition, DMDesktopTypingPass and DMDesktopTypingWatch cut out of statusbar/Desktop.h, and the signature helpers cut out of
// statusbar/SMEngineAPI.h, run here on a model of SpringBoard's objects (the same class and selector names, the same type encodings). The rule is
// common/StickyNotes.h's own. -DTE_ODD: SpringBoard's begin of another shape; -DTE_NONE: no such class (the watch must not hook either).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static int fails = 0;
static void check(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); fflush(stdout); if (!ok) fails++; }   // (each line out at once: a made-to-fail copy may crash the model)

// ---- stand-ins for what the cut-out code calls ----
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; }
@end
static id gMainIdentity;   // (the iPad's own display identity; nil: it cannot be read)
static id DMSMIdentityOfScreen(UIScreen *sc) { return sc == [UIScreen mainScreen] ? gMainIdentity : nil; }
static BOOL gSM;           // (our Stage Manager engine runs)
static BOOL DMSMEngine(void) { return gSM; }
@interface TAttrs : NSObject
@property BOOL full;       // (maximized, or zoomed to fill: what DMSMAttrsFullScreen answers)
@end
@implementation TAttrs
@end
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[NSDictionary class]] ? stage : nil; }   // (the model's stage is its map)
static BOOL DMSMAttrsFullScreen(id a) { return [a isKindOfClass:[TAttrs class]] && ((TAttrs *)a).full; }
static NSMutableArray<NSString *> *gOrder;   // ("begin": SpringBoard's own; "end <why>": the desktop's typing ended)
static void DMDesktopTypingEnd(NSString *why) { [gOrder addObject:[@"end " stringByAppendingString:why ?: @"(none)"]]; }
static BOOL gTyping;
static BOOL DMDesktopTypingNow(void) { return gTyping; }
// (1.8.8.3: the Mac Switcher's state, as DMDesktopTypingSwitcherEvent reads it: on, its view open, iPadOS's switcher asked for from the Apple menu)
static BOOL gMSWOn, gMSWViewOpen, gMSWStock;
static BOOL DMMSWIsOpen(void) { return gMSWViewOpen; }
static BOOL DMMSWStockOnce(void) { return gMSWStock; }
#define DMLog(...) do { (void)(__VA_ARGS__); } while (0)
#define DM_FEATURE_MARK(n) do { } while (0)
static int gHooks;
static void MSHookMessageEx(Class c, SEL s, IMP imp, IMP *orig) { gHooks++; Method m = class_getInstanceMethod(c, s); *orig = m ? method_setImplementation(m, imp) : NULL; }

// ---- SpringBoard's objects, as the code reads them ----
@interface SBWorkspaceTransitionRequest : NSObject
@property (strong) id applicationContext, transientOverlayContext, displayIdentity;
@end
@implementation SBWorkspaceTransitionRequest
@end
@interface SBWorkspaceApplicationSceneTransitionContext : NSObject
@property (strong) id layoutState;
@end
@implementation SBWorkspaceApplicationSceneTransitionContext
@end
@interface SBMainDisplayLayoutState : NSObject
@property long long unlockedEnvironmentMode;
@property (strong) id appLayout;
@end
@implementation SBMainDisplayLayoutState
@end
@interface TOddLayoutState : NSObject   // (a mode of another shape: a 32-bit number, 3, read as SpringBoard's 64-bit one only if its shape is not asked)
@property unsigned int unlockedEnvironmentMode;
@end
@implementation TOddLayoutState
@end
@interface SBWorkspaceTransientOverlayTransitionContext : NSObject
@property (strong) id transientOverlay;
@end
@implementation SBWorkspaceTransientOverlayTransitionContext
@end
@interface SBWorkspaceTransientOverlay : NSObject
@property (strong) id viewController;
@end
@implementation SBWorkspaceTransientOverlay
@end
@interface SBSpotlightTransientOverlayViewController : NSObject
@end
@implementation SBSpotlightTransientOverlayViewController
@end
@interface SBShareSheetOverlayViewController : NSObject   // (any other overlay)
@end
@implementation SBShareSheetOverlayViewController
@end
@interface SBWorkspaceTransaction : NSObject
@property (strong) id transitionRequest;
@end
@implementation SBWorkspaceTransaction
@end
@interface SBTransientOverlayPresentWorkspaceTransaction : SBWorkspaceTransaction
@end
@implementation SBTransientOverlayPresentWorkspaceTransaction
@end
@interface SBTransientOverlayDismissWorkspaceTransaction : SBWorkspaceTransaction
@end
@implementation SBTransientOverlayDismissWorkspaceTransaction
@end
@interface SBAppToAppWorkspaceTransaction : SBWorkspaceTransaction
@end
@implementation SBAppToAppWorkspaceTransaction
@end
// (a request getter of another shape: Spotlight's presentation whose -transitionRequest gives a class, which answers as a request would; made at run
//  time, below, so no declaration disagrees with the transactions' own)
static id gOddOverlayContext;
@interface TOddRequest : NSObject
+ (id)transientOverlayContext;
@end
@implementation TOddRequest
+ (id)transientOverlayContext { return gOddOverlayContext; }
@end
#ifndef TE_NONE
@interface SBLayoutStateTransitionCoordinator : NSObject
#ifdef TE_ODD
- (BOOL)beginTransitionForWorkspaceTransaction:(id)tx;
#else
- (void)beginTransitionForWorkspaceTransaction:(id)tx;
#endif
@end
@implementation SBLayoutStateTransitionCoordinator
#ifdef TE_ODD
- (BOOL)beginTransitionForWorkspaceTransaction:(id)tx { [gOrder addObject:@"begin"]; return YES; }
#else
- (void)beginTransitionForWorkspaceTransaction:(id)tx { [gOrder addObject:@"begin"]; }
#endif
@end
#endif

#include "../common/StickyNotes.h"
#include "cut.h"

// ---- building the model's transactions ----
static id Identity(NSString *n) { return [@"display:" stringByAppendingString:n]; }
static id Stage(NSArray<NSNumber *> *full) {   // (a stage: one window per entry, YES = full screen)
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < full.count; i++) { TAttrs *a = [TAttrs new]; a.full = full[i].boolValue; m[[NSString stringWithFormat:@"item%lu", (unsigned long)i]] = a; }
    return m;
}
static id AppTx(Class txClass, long long mode, id stage, id display) {
    SBMainDisplayLayoutState *s = [SBMainDisplayLayoutState new]; s.unlockedEnvironmentMode = mode; s.appLayout = stage;
    SBWorkspaceApplicationSceneTransitionContext *c = [SBWorkspaceApplicationSceneTransitionContext new]; c.layoutState = s;
    SBWorkspaceTransitionRequest *r = [SBWorkspaceTransitionRequest new]; r.applicationContext = c; r.displayIdentity = display;
    SBWorkspaceTransaction *t = [txClass new]; t.transitionRequest = r;
    return t;
}
static id OverlayTx(Class txClass, Class vcClass, id display) {
    SBWorkspaceTransientOverlay *o = [SBWorkspaceTransientOverlay new]; o.viewController = [vcClass new];
    SBWorkspaceTransientOverlayTransitionContext *oc = [SBWorkspaceTransientOverlayTransitionContext new]; oc.transientOverlay = o;
    SBWorkspaceTransitionRequest *r = [SBWorkspaceTransitionRequest new]; r.transientOverlayContext = oc; r.displayIdentity = display;
    SBWorkspaceTransaction *t = [txClass new]; t.transitionRequest = r;
    return t;
}
// The real decision on a transaction, the desktop typing: the ends it gave ("" none).
static NSString *Decide(id tx, BOOL sm) {
    gSM = sm; gTyping = YES; [gOrder removeAllObjects];
    DMDesktopTypingAtTransition(tx);
    return [gOrder componentsJoinedByString:@","];
}

// The rule as written in the design (B74 section of release-1.8.8.2.md), stated again independently for the sweep.
static int Expected(BOOL spot, BOOL read, BOOL onIPad, long long mode, BOOL sm, BOOL full) {
    if (spot) return 1;                                  // Spotlight presented, any display
    BOOL fullScreenOnIPad = read && onIPad && mode == 3 && (sm ? full : YES);
    return fullScreenOnIPad ? 2 : 0;
}

int main(void) {
    @autoreleasepool {
        gOrder = [NSMutableArray array];
        gMainIdentity = Identity(@"iPad");
        id iPad = Identity(@"iPad"), tv = Identity(@"TV");
#if !defined(TE_ODD) && !defined(TE_NONE)
        // ---- the rule ----
        check(MSBDStickyTypingAt(YES, NO, NO, 0, NO, NO) == MSBDStickyTypingSpotlight && MSBDStickyTypingAt(YES, YES, NO, 1, YES, NO) == MSBDStickyTypingSpotlight,
              @"rule: Spotlight being presented ends the typing, on any display and whatever the layout");
        check(MSBDStickyTypingAt(NO, YES, YES, 3, YES, YES) == MSBDStickyTypingFullScreen && MSBDStickyTypingAt(NO, YES, YES, 3, YES, NO) == MSBDStickyTypingGoesOn,
              @"rule: our Stage Manager engine, application mode on the iPad: a stage with a full-screen window ends it, a stage of windows does not");
        check(MSBDStickyTypingAt(NO, YES, YES, 3, NO, NO) == MSBDStickyTypingFullScreen,
              @"rule: Aerial, Zetsu, MilkyWay4 and no windowing: application mode on the iPad is an app full screen, it ends");
        check(MSBDStickyTypingAt(NO, YES, YES, 1, NO, NO) == MSBDStickyTypingGoesOn && MSBDStickyTypingAt(NO, YES, YES, 2, YES, YES) == MSBDStickyTypingGoesOn,
              @"rule: Home (1) and the App Switcher (2) keep it");
        check(MSBDStickyTypingAt(NO, YES, NO, 3, YES, YES) == MSBDStickyTypingGoesOn && MSBDStickyTypingAt(NO, YES, NO, 3, NO, NO) == MSBDStickyTypingGoesOn,
              @"rule: another display's transition keeps it (a TV window full screen does not cover the iPad's note)");
        check(MSBDStickyTypingAt(NO, NO, YES, 3, NO, YES) == MSBDStickyTypingGoesOn, @"rule: a state that could not be read keeps it (the tick and the touches decide)");
        check([MSBDStickyTypingWhy(MSBDStickyTypingSpotlight) isEqualToString:@"Spotlight opens"] && [MSBDStickyTypingWhy(MSBDStickyTypingFullScreen) isEqualToString:@"a window or app went full screen"]
              && MSBDStickyTypingWhy(MSBDStickyTypingGoesOn) == nil, @"rule: the reasons the log and the end give");
        {
            int n = 0, bad = 0;
            for (int sp = 0; sp < 2; sp++) for (int rd = 0; rd < 2; rd++) for (int ip = 0; ip < 2; ip++) for (long long md = 0; md <= 4; md++) for (int sm = 0; sm < 2; sm++) for (int fu = 0; fu < 2; fu++) {
                n++;
                if ((int)MSBDStickyTypingAt(sp, rd, ip, md, sm, fu) != Expected(sp, rd, ip, md, sm, fu)) bad++;
            }
            check(n == 160 && bad == 0, [NSString stringWithFormat:@"rule: the sweep of every input (%d states) answers as the design says (%d differ)", n, bad]);
        }
        // ---- the real decision on SpringBoard's objects (Desktop.h DMDesktopTypingAtTransition) ----
        Class present = [SBTransientOverlayPresentWorkspaceTransaction class], dismiss = [SBTransientOverlayDismissWorkspaceTransaction class], app = [SBAppToAppWorkspaceTransaction class];
        Class spotVC = [SBSpotlightTransientOverlayViewController class], otherVC = [SBShareSheetOverlayViewController class];
        check([Decide(OverlayTx(present, spotVC, iPad), YES) isEqualToString:@"end Spotlight opens"] && [Decide(OverlayTx(present, spotVC, iPad), NO) isEqualToString:@"end Spotlight opens"],
              @"decision: Spotlight presented on the iPad ends the typing, every engine (F2-F8: Cmd-Space with no touch)");
        check([Decide(OverlayTx(present, spotVC, tv), YES) isEqualToString:@"end Spotlight opens"] && [Decide(OverlayTx(present, spotVC, nil), NO) isEqualToString:@"end Spotlight opens"],
              @"decision: ... and on the TV, or with no display named (its keys are Spotlight's)");
        check([Decide(OverlayTx(dismiss, spotVC, iPad), YES) isEqualToString:@""] && [Decide(OverlayTx(dismiss, spotVC, iPad), NO) isEqualToString:@""],
              @"decision: Spotlight's dismissal ends nothing");
        check([Decide(OverlayTx(present, otherVC, iPad), YES) isEqualToString:@""] && [Decide(OverlayTx(present, otherVC, iPad), NO) isEqualToString:@""],
              @"decision: another overlay presented ends nothing by this rule");
        check([Decide(AppTx(app, 3, Stage(@[@NO, @YES]), iPad), YES) isEqualToString:@"end a window or app went full screen"],
              @"decision: Stage Manager engine, the iPad's stage with a full-screen window (F2-F6: smfull_, Globe-F) ends the typing");
        check([Decide(AppTx(app, 3, Stage(@[@NO, @NO, @NO]), iPad), YES) isEqualToString:@""] && [Decide(AppTx(app, 3, Stage(@[]), iPad), YES) isEqualToString:@""],
              @"decision: Stage Manager engine, a stage of windows only (a window opened, closed, moved, resized: P3) keeps it");
        check([Decide(AppTx(app, 3, Stage(@[@YES]), tv), YES) isEqualToString:@""], @"decision: Stage Manager engine, a TV window full screen keeps the iPad's typing");
        check([Decide(AppTx(app, 1, Stage(@[@YES]), iPad), YES) isEqualToString:@""] && [Decide(AppTx(app, 2, Stage(@[@YES]), iPad), YES) isEqualToString:@""],
              @"decision: Home and the App Switcher keep it, whatever their stage");
        check([Decide(AppTx(app, 3, nil, iPad), NO) isEqualToString:@"end a window or app went full screen"] && [Decide(AppTx(app, 3, Stage(@[@NO]), nil), NO) isEqualToString:@"end a window or app went full screen"],
              @"decision: Aerial, Zetsu, MilkyWay4 and none, an app full screen on the iPad (or no display named: 15) ends it, its stage not asked");
        check([Decide(AppTx(app, 1, nil, iPad), NO) isEqualToString:@""] && [Decide(AppTx(app, 3, nil, tv), NO) isEqualToString:@""],
              @"decision: ... their Home and another display's app keep it");
        gMainIdentity = nil;
        check([Decide(AppTx(app, 3, Stage(@[@YES]), iPad), YES) isEqualToString:@"end a window or app went full screen"] && [Decide(AppTx(app, 3, nil, tv), NO) isEqualToString:@"end a window or app went full screen"],
              @"decision: the iPad's own identity not readable: the request's display is the iPad's");
        gMainIdentity = Identity(@"iPad");
        {
            TOddLayoutState *odd = [TOddLayoutState new]; odd.unlockedEnvironmentMode = 3;
            SBWorkspaceApplicationSceneTransitionContext *c = [SBWorkspaceApplicationSceneTransitionContext new]; c.layoutState = odd;
            SBWorkspaceTransitionRequest *r = [SBWorkspaceTransitionRequest new]; r.applicationContext = c; r.displayIdentity = iPad;
            SBWorkspaceTransaction *t = [app new]; t.transitionRequest = r;
            SBWorkspaceTransientOverlay *o = [SBWorkspaceTransientOverlay new]; o.viewController = [spotVC new];
            SBWorkspaceTransientOverlayTransitionContext *oc = [SBWorkspaceTransientOverlayTransitionContext new]; oc.transientOverlay = o; gOddOverlayContext = oc;
            Class oddPresent = objc_allocateClassPair(present, "TOddPresentTransaction", 0);
            class_addMethod(oddPresent, @selector(transitionRequest), imp_implementationWithBlock(^Class(id me) { return [TOddRequest class]; }), "#16@0:8");
            objc_registerClassPair(oddPresent);
            check([Decide(t, NO) isEqualToString:@""] && [Decide([oddPresent new], NO) isEqualToString:@""] && [Decide(nil, YES) isEqualToString:@""]
                  && [Decide([app new], NO) isEqualToString:@""] && [Decide([present new], NO) isEqualToString:@""],
                  @"decision: a mode, a request or a transaction of another shape, or none, reads as nothing: no end (as 1.8.8.1)");
        }
        // ---- the pass-through and the watch (DMDesktopTypingPass, DMDesktopTypingWatch) ----
        SBLayoutStateTransitionCoordinator *co = [SBLayoutStateTransitionCoordinator new];
        gTyping = YES; gSM = YES; [gOrder removeAllObjects];
        [co beginTransitionForWorkspaceTransaction:OverlayTx(present, spotVC, iPad)];
        check(gHooks == 0 && [[gOrder componentsJoinedByString:@","] isEqualToString:@"begin"], @"watch: nothing is hooked before the first typing");
        DMDesktopTypingWatch(); DMDesktopTypingWatch();
        check(gHooks == 1 && o_DMDesktopTypingPass != NULL, @"watch: SpringBoard's begin is hooked once (asked at every typing)");
        [gOrder removeAllObjects];
        [co beginTransitionForWorkspaceTransaction:OverlayTx(present, spotVC, iPad)];
        check([[gOrder componentsJoinedByString:@","] isEqualToString:@"begin,end Spotlight opens"], @"pass-through: SpringBoard's own begin first, then the typing ends");
        [gOrder removeAllObjects];
        [co beginTransitionForWorkspaceTransaction:AppTx(app, 3, Stage(@[@NO]), iPad)];
        check([[gOrder componentsJoinedByString:@","] isEqualToString:@"begin"], @"pass-through: a same-stage transition: SpringBoard's begin only");
        gTyping = NO; [gOrder removeAllObjects];
        [co beginTransitionForWorkspaceTransaction:OverlayTx(present, spotVC, iPad)];
        [co beginTransitionForWorkspaceTransaction:AppTx(app, 3, Stage(@[@YES]), iPad)];
        check([[gOrder componentsJoinedByString:@","] isEqualToString:@"begin,begin"], @"pass-through: nothing types: SpringBoard's begin only, nothing read or ended");
        // ---- 1.8.8.3: iPadOS's App Switcher on its way ends the typing (Desktop.h DMDesktopTypingSwitcherEvent, from the switcher's transition event) ----
        NSString *(^event)(long long, BOOL, BOOL, BOOL, BOOL, BOOL *) = ^NSString *(long long mode, BOOL typing, BOOL on, BOOL open, BOOL stock, BOOL *atOnce) {
            gTyping = typing; gMSWOn = on; gMSWViewOpen = open; gMSWStock = stock; [gOrder removeAllObjects];
            DMDesktopTypingSwitcherEvent(mode);
            if (atOnce) *atOnce = gOrder.count > 0;
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            return [gOrder componentsJoinedByString:@","];
        };
        BOOL atOnce = YES;
        check([event(2, YES, NO, NO, NO, &atOnce) isEqualToString:@"end the App Switcher opens"] && !atOnce,
              @"App Switcher: its transition event (mode 2) ends the typing, a note's or a name's, on the main queue's next turn (never inside SpringBoard's transition)");
        check([event(1, YES, NO, NO, NO, NULL) isEqualToString:@""] && [event(3, YES, NO, NO, NO, NULL) isEqualToString:@""] && [event(0, YES, NO, NO, NO, NULL) isEqualToString:@""],
              @"App Switcher: Home (1), an app or the windows (3), none (0): the typing goes on");
        check([event(2, NO, NO, NO, NO, NULL) isEqualToString:@""], @"App Switcher: nothing typed: nothing ended");
        check([event(2, YES, YES, YES, YES, NULL) isEqualToString:@""], @"App Switcher: the Mac Switcher shows (its open ended the typing): nothing more");
        check([event(2, YES, YES, NO, NO, NULL) isEqualToString:@""], @"App Switcher: the Mac Switcher on and iPadOS's not asked for (the Mac Switcher's gesture: its open ends it)");
        check([event(2, YES, YES, NO, YES, NULL) isEqualToString:@"end the App Switcher opens"], @"App Switcher: the Mac Switcher on, iPadOS's asked for from the Apple menu (Show App Switcher): ends");
#else
        // ---- the watch refuses a begin it does not know ----
        DMDesktopTypingWatch();
#ifdef TE_ODD
        SBLayoutStateTransitionCoordinator *co = [SBLayoutStateTransitionCoordinator new];
        gTyping = YES; [gOrder removeAllObjects];
        [co beginTransitionForWorkspaceTransaction:OverlayTx([SBTransientOverlayPresentWorkspaceTransaction class], [SBSpotlightTransientOverlayViewController class], iPad)];
        check(gHooks == 0 && [[gOrder componentsJoinedByString:@","] isEqualToString:@"begin"], @"watch: SpringBoard's begin of another shape is not hooked (the typing ends as in 1.8.8.1)");
#else
        check(gHooks == 0, @"watch: no such class: nothing hooked");
#endif
        (void)tv; (void)iPad;
#endif
    }
    return fails ? 1 : 0;
}
