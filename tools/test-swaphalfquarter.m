// test-swaphalfquarter.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the Window menu's Swap Half and Quarter on every engine (1.8.7.3, audit
// L30 of 1.8.7.2). One window in a half of the desktop and two in the quarters of the other half: the row is there to trade the half's window with
// one of the quarter windows (the two quarters light up and a tap picks one). On MilkyWay4 the row was always greyed, while Aerial, Zetsu and the
// Stage Manager engine offered it and the plan and the move behind it work for MilkyWay4's windows as they do for the others.
// Runs the real DMHalfQuarterAvailable (the row's state), DMHalfQuarterPlan, DMSMHalfQuarterPlan, DMOtherHalfQuarter, DMApplyHalfQuarterSwap,
// DMSwapHalfWithQuarter (the row's action, its chooser), the Swap Top and Bottom / Left and Right rows beside it (DMSwapAvailable, DMSwapPlan,
// DMSMSwapPlan, DMSwapWindows, DMMirrorSlot), DMSlotNameForFrame, and the engines' move (DMAerialMoveStage, DMSetStageFrameSafe), cut out of
// statusbar/StatusBar.x by test-swaphalfquarter.sh into swq-real.inc, with the real common/ReduceMotion.h, common/DockSide.h,
// statusbar/FitQuestionPlace.h and statusbar/SMWindowKey.h. SpringBoard's side (the engine's windows in their layer, back to front; the layouts'
// frames; the Stage Manager engine's stage; the menu's overlay and panels) is the stand-ins below, which record what they are asked.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../common/ReduceMotion.h"
#include "../common/DockSide.h"
#include "../statusbar/FitQuestionPlace.h"
#include "../statusbar/SMWindowKey.h"

// ---- what the real code logs
static NSMutableArray<NSString *> *gQLog;
static void QLog(NSString *s) { [gQLog addObject:s ?: @""]; }
#define DMLog(...) QLog(__VA_ARGS__)
#define DMTestFlag(path) 0

// ---- the engine: one layer, its subviews the windows back to front (Aerial's stages, Zetsu's windows, MilkyWay4's AXWindowViews)
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;   // (StatusBar.x's)
static DMEngine gQEngine; static BOOL gQSM;
static DMEngine DMActiveEngine(void) { return gQEngine; }
static BOOL DMSMEngine(void) { return gQSM; }
static int gAerialFlavor = 3;   // (Aerial 3.0's names: none of Aerial 5.x's holds)
@interface AXWindowView : UIView @end   // (MilkyWay4's window)
@implementation AXWindowView @end
@interface ZetsuWindow : UIView @end    // (a Zetsu window: objc_getClass("ZetsuWindow") in the real move)
@implementation ZetsuWindow @end
@interface QStage : UIView @end         // (an Aerial stage)
@implementation QStage @end
static UIView *gQLayer;
static const void *kQBundleKey = &kQBundleKey, *kQMinKey = &kQMinKey;
// (this desktop's windows, back to front; none without an engine of ours, as DMAerialStagesAll: its windows are left alone)
static NSArray<UIView *> *DMAerialStages(void) { return DMActiveEngine() == DMEngineNone ? @[] : [gQLayer.subviews copy]; }
static NSString *DMStageBundle(UIView *stage) { return stage ? objc_getAssociatedObject(stage, kQBundleKey) : nil; }
static BOOL DMStageMinimized(UIView *stage) { return [objc_getAssociatedObject(stage, kQMinKey) boolValue]; }
// ---- the layouts: a 1024 x 768 screen, the menu bar 24 pt, the Dock 64 pt: the desktop {0, 24, 1024, 680}
static CGRect DMLayoutFrameWindow(NSString *name) {
    static NSDictionary<NSString *, NSValue *> *f;
    if (!f) f = @{@"fill": @(CGRectMake(0, 24, 1024, 680)), @"center": @(CGRectMake(212, 109, 600, 510)),
                  @"left": @(CGRectMake(0, 24, 512, 680)), @"right": @(CGRectMake(512, 24, 512, 680)),
                  @"top": @(CGRectMake(0, 24, 1024, 340)), @"bottom": @(CGRectMake(0, 364, 1024, 340)),
                  @"topleft": @(CGRectMake(0, 24, 512, 340)), @"topright": @(CGRectMake(512, 24, 512, 340)),
                  @"bottomleft": @(CGRectMake(0, 364, 512, 340)), @"bottomright": @(CGRectMake(512, 364, 512, 340))};
    NSValue *v = name ? f[name] : nil;
    return v ? v.CGRectValue : CGRectNull;
}
static CGRect DMLayoutFrame(NSString *name) { return DMLayoutFrameWindow(name); }   // (the engine's frame: the window itself, as on all but Aerial 5.x)
// ---- the engines' move: what it asks beside setting the frame
static NSMutableArray<NSString *> *gQAsked;
static const void *kA5BornKey = &kA5BornKey, *kA5EntranceTargetKey = &kA5EntranceTargetKey;
static void DMA5HoldStageAt(UIView *stage, CGRect target, CFTimeInterval until) { [gQAsked addObject:@"aerial5 hold"]; }
static void DMAerial5SyncState(UIView *stage, CGRect frame) {}
static void DMZetsuMove(UIWindow *w, CGRect target, BOOL animated, void (^done)(void)) {   // (Zetsu's own move of its window)
    [gQAsked addObject:[NSString stringWithFormat:@"zetsu move %@", DMStageBundle((UIView *)w)]];
    ((UIView *)w).frame = target;
    if (done) done();
}
static void DMShowMilkyWayVeil(UIView *window) { [gQAsked addObject:[NSString stringWithFormat:@"milkyway veil %@", DMStageBundle(window)]]; }
static BOOL DMStageStillZooming(UIView *stage) { return NO; }
static void DMRememberStageFrame(UIView *stage) {}
static SEL DMAerialSel(NSString *name) { return NSSelectorFromString(name); }
static BOOL gMoveKeepsOrder = NO;
static NSMutableArray<NSString *> *gFitGroup = nil;
static NSMutableDictionary<NSString *, NSString *> *gFitSlots = nil;
static NSMutableArray<NSString *> *gQRecorded;   // (the title bar's frame from before: each placement of ours)
static void DMTitleRecordEngineTo(UIView *v, CGRect to) { [gQRecorded addObject:DMStageBundle(v) ?: @"?"]; }
// ---- the Stage Manager engine: its windows' frames on its working stage, by window key
static NSMutableDictionary<NSString *, NSValue *> *gQSMOpen;
static NSMutableArray<NSDictionary *> *gQSMApplied;
static NSString *DMSlotNameForFrame(CGRect f);
static id DMSMWorkingStage(void) { return @"the working stage"; }
static NSDictionary<NSString *, NSValue *> *DMSMOpenWindowFrames(void) { return [gQSMOpen copy]; }
static NSString *DMSMSlotNameForFrameIn(CGRect f, id stage) { return DMSlotNameForFrame(f); }
static BOOL DMSMApplyLayouts(NSDictionary<NSString *, NSString *> *keyToLayout) {
    [gQSMApplied addObject:[keyToLayout copy]];
    for (NSString *k in keyToLayout) if (gQSMOpen[k]) gQSMOpen[k] = @(DMLayoutFrame(keyToLayout[k]));
    return YES;
}
static void DMTitleRecordSMPlan(NSDictionary *plan, id stage) { for (NSString *k in plan) [gQRecorded addObject:k]; }
// ---- the menu's overlay, its panels and the apps' names
static UIView *gQHost;
static UIView *DMMenuHost(void) { return gQHost; }
static UIView *gOverlay = nil;
static const void *kOverlayEscapeKey = &kOverlayEscapeKey;
static UIControl *DMMakeOverlay(UIView *host, CGFloat dimAlpha) {
    UIControl *o = [[UIControl alloc] initWithFrame:host.bounds];
    [host addSubview:o]; gOverlay = o;
    return o;
}
static void DMCloseOverlay(void) { [gOverlay removeFromSuperview]; gOverlay = nil; }
static NSMutableArray<UIControl *> *gQPanels; static NSMutableArray<NSString *> *gQPanelText;
static UIControl *DMSidePanel(NSString *side, NSString *title, NSString *subtitle) {
    UIControl *p = [[UIControl alloc] initWithFrame:MSBDFitQuestionPanel(DMLayoutFrameWindow(side))];
    [gQPanels addObject:p]; [gQPanelText addObject:[NSString stringWithFormat:@"%@: %@ (%@)", side, title, subtitle]];
    return p;
}
static BOOL DMIsExtMenuHost(UIView *host) { return NO; }
static int DMDockSideNow(CGSize screen) { return MSBDDockBottom; }
static id DMProxyForBundle(NSString *bundleID) { return bundleID; }
static NSDictionary *gQNames;
static id DMCall(id obj, NSString *name) { return [name isEqualToString:@"localizedName"] && obj ? gQNames[obj] : nil; }
static NSString *DMOtherHalfQuarter(NSString *halfSlot, BOOL first);   // (StatusBar.x declares it before the Stage Manager plan too)

#include "swq-real.inc"

// ---- the checks
static int gFails = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    printf("%s  %s%s\n", ok ? "PASS" : "FAIL", what.UTF8String, ok ? "" : [NSString stringWithFormat:@" (got: %@)", got].UTF8String);
    if (!ok) gFails++;
}
static NSString *const kNotes = @"com.apple.mobilenotes", *const kSafari = @"com.apple.mobilesafari", *const kCalc = @"com.apple.calculator",
                *const kMaps = @"com.apple.Maps";
static const char *EngineName(DMEngine e, BOOL sm) { return sm ? "Stage Manager" : e == DMEngineAerial ? "Aerial" : e == DMEngineZetsu ? "Zetsu" : e == DMEngineMilkyWay ? "MilkyWay4" : "no engine"; }
static void Fresh(DMEngine e, BOOL sm, BOOL withHost) {
    gQLog = [NSMutableArray array]; gQAsked = [NSMutableArray array]; gQRecorded = [NSMutableArray array];
    gQSMOpen = [NSMutableDictionary dictionary]; gQSMApplied = [NSMutableArray array];
    gQPanels = [NSMutableArray array]; gQPanelText = [NSMutableArray array];
    gQEngine = e; gQSM = sm; gMoveKeepsOrder = NO; gFitGroup = nil; gFitSlots = nil;
    gQNames = @{kNotes: @"Notes", kSafari: @"Safari", kCalc: @"Calculator", kMaps: @"Maps"};
    gQLayer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    if (gOverlay) DMCloseOverlay();
    gQHost = withHost ? [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)] : nil;
}
static UIView *Window(NSString *bundle, NSString *slot) {   // a window of the engine at that layout, opened in front
    if (gQSM) { gQSMOpen[bundle] = @(DMLayoutFrame(slot)); return nil; }
    Class c = gQEngine == DMEngineMilkyWay ? [AXWindowView class] : gQEngine == DMEngineZetsu ? [ZetsuWindow class] : [QStage class];
    UIView *v = [[c alloc] initWithFrame:DMLayoutFrame(slot)];
    objc_setAssociatedObject(v, kQBundleKey, bundle, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [gQLayer addSubview:v];
    return v;
}
static void Minimized(UIView *v) { objc_setAssociatedObject(v, kQMinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static NSString *SlotOf(NSString *bundle) {   // where an app's window is now (a layout's name, or its frame)
    CGRect f = CGRectNull;
    if (gQSM) f = gQSMOpen[bundle] ? gQSMOpen[bundle].CGRectValue : CGRectNull;
    else for (UIView *v in gQLayer.subviews) if ([DMStageBundle(v) isEqualToString:bundle]) f = v.frame;
    if (CGRectIsNull(f)) return @"(none)";
    return DMSlotNameForFrame(f) ?: NSStringFromCGRect(f);
}
static NSString *Places(NSArray<NSString *> *bundles) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *b in bundles) [a addObject:[NSString stringWithFormat:@"%@ %@", gQNames[b], SlotOf(b)]];
    return [a componentsJoinedByString:@", "];
}
static NSString *Snapshot(void) { return Places(@[kNotes, kSafari, kCalc, kMaps]); }
// The row is greyed exactly when its action would do nothing: the state is read, then the action run (with no menu host it trades with the
// first quarter at once).
static void RowMatchesAction(NSString *what) {
    BOOL row = DMHalfQuarterAvailable();
    NSString *before = Snapshot();
    UIView *host = gQHost; gQHost = nil;
    DMSwapHalfWithQuarter();
    gQHost = host;
    BOOL moved = ![Snapshot() isEqualToString:before];
    Check([NSString stringWithFormat:@"%@: the row is %@ and choosing it %@", what, row ? @"enabled" : @"greyed", moved ? @"trades two windows" : @"does nothing"],
          row == moved, [NSString stringWithFormat:@"row %@, windows %@ -> %@", row ? @"enabled" : @"greyed", before, Snapshot()]);
}

int main(void) {
    @autoreleasepool {
        const DMEngine engines[] = {DMEngineAerial, DMEngineZetsu, DMEngineMilkyWay, DMEngineNone};
        for (int i = 0; i < 5; i++) {
            BOOL sm = i == 4; DMEngine e = sm ? DMEngineNone : engines[i];
            const char *en = EngineName(e, sm);
            BOOL ours = sm || e != DMEngineNone;

            // 1. Notes in the left half, Safari top right, Calculator bottom right (Maps minimized: it does not count): the row; no menu host, the
            //    half trades with the first quarter at once
            Fresh(e, sm, NO);
            Window(kNotes, @"left"); Window(kSafari, @"topright"); Window(kCalc, @"bottomright");
            if (!sm) Minimized(Window(kMaps, @"fill"));
            gFitGroup = [@[kNotes, kSafari, kCalc] mutableCopy];
            gFitSlots = [@{kNotes: @"left", kSafari: @"topright", kCalc: @"bottomright"} mutableCopy];
            BOOL row = DMHalfQuarterAvailable();
            Check([NSString stringWithFormat:@"%s: a half and two quarters (a minimized window beside them): Swap Half and Quarter is %s", en, ours ? "enabled" : "greyed (no engine of ours)"],
                  row == ours, row ? @"enabled" : @"greyed");
            if (ours) {
                DMSwapHalfWithQuarter();
                NSString *got = Places(@[kNotes, kSafari, kCalc]);
                Check([NSString stringWithFormat:@"%s:   ... chosen with no chooser: Notes and Safari trade places, Calculator stays", en],
                      [got isEqualToString:@"Notes topright, Safari left, Calculator bottomright"], got);
                if (!sm) {
                    Check([NSString stringWithFormat:@"%s:   ... Fit to Window's tiles follow, and each move is a placement of ours", en],
                          [gFitSlots[kNotes] isEqualToString:@"topright"] && [gFitSlots[kSafari] isEqualToString:@"left"] && [gFitSlots[kCalc] isEqualToString:@"bottomright"]
                          && gQRecorded.count == 2 && !gMoveKeepsOrder,
                          [NSString stringWithFormat:@"tiles %@, recorded %@, keeps order %d", gFitSlots, gQRecorded, gMoveKeepsOrder]);
                    if (e == DMEngineMilkyWay)
                        Check(@"MilkyWay4:   ... each window moves as MilkyWay4's (its veil over the content while it catches up)",
                              [gQAsked isEqualToArray:@[@"milkyway veil com.apple.mobilenotes", @"milkyway veil com.apple.mobilesafari"]], [gQAsked componentsJoinedByString:@"; "]);
                    if (e == DMEngineZetsu)
                        Check(@"Zetsu:   ... each window moves as Zetsu's", [gQAsked isEqualToArray:@[@"zetsu move com.apple.mobilenotes", @"zetsu move com.apple.mobilesafari"]], [gQAsked componentsJoinedByString:@"; "]);
                } else {
                    Check(@"Stage Manager:   ... one plan for the stage", gQSMApplied.count == 1 && [gQSMApplied[0] isEqualToDictionary:@{kNotes: @"topright", kSafari: @"left"}],
                          [NSString stringWithFormat:@"%@", gQSMApplied]);
                }
            }

            // 2. the same with the menu on screen: the two quarters light up, named, and a tap on the second trades it with the half
            Fresh(e, sm, YES);
            Window(kNotes, @"left"); Window(kSafari, @"topright"); Window(kCalc, @"bottomright");
            if (ours) {
                DMSwapHalfWithQuarter();
                NSString *panels = [gQPanelText componentsJoinedByString:@"; "];
                Check([NSString stringWithFormat:@"%s: the chooser shows the two quarter windows, each to trade with Notes", en],
                      gOverlay != nil && [panels isEqualToString:@"topright: Safari (Trades places with Notes); bottomright: Calculator (Trades places with Notes)"], panels);
                if (gQPanels.count == 2) [gQPanels[1] sendActionsForControlEvents:UIControlEventTouchUpInside];
                NSString *got = Places(@[kNotes, kSafari, kCalc]);
                Check([NSString stringWithFormat:@"%s:   ... a tap on Calculator: Notes and Calculator trade places, the chooser closes", en],
                      gOverlay == nil && [got isEqualToString:@"Notes bottomright, Safari topright, Calculator left"], [NSString stringWithFormat:@"%@, chooser %@", got, gOverlay ? @"open" : @"closed"]);
            }

            // 3. the other halves: the row and its action agree (Notes on top over the bottom quarters, on the right beside the left ones)
            Fresh(e, sm, NO);
            Window(kNotes, @"top"); Window(kSafari, @"bottomleft"); Window(kCalc, @"bottomright");
            RowMatchesAction([NSString stringWithFormat:@"%s: Notes in the top half, the bottom quarters", en]);
            if (ours) Check([NSString stringWithFormat:@"%s:   ... Notes and Safari traded", en], [Places(@[kNotes, kSafari]) isEqualToString:@"Notes bottomleft, Safari top"], Places(@[kNotes, kSafari]));
            Fresh(e, sm, NO);
            Window(kNotes, @"right"); Window(kSafari, @"topleft"); Window(kCalc, @"bottomleft");
            RowMatchesAction([NSString stringWithFormat:@"%s: Notes in the right half, the left quarters", en]);

            // 4. nothing to trade: greyed, and the action leaves every window where it is (the row's state is not a promise it cannot keep)
            Fresh(e, sm, NO);
            Window(kNotes, @"left"); Window(kSafari, @"right");
            RowMatchesAction([NSString stringWithFormat:@"%s: two halves only", en]);
            Fresh(e, sm, NO);
            Window(kNotes, @"left"); Window(kSafari, @"topleft"); Window(kCalc, @"bottomright");
            RowMatchesAction([NSString stringWithFormat:@"%s: a quarter on the half's side", en]);
            Fresh(e, sm, NO);
            Window(kNotes, @"left"); Window(kSafari, @"topright"); Window(kCalc, @"center");
            RowMatchesAction([NSString stringWithFormat:@"%s: one window in no layout", en]);
            Fresh(e, sm, NO);
            Window(kNotes, @"left"); Window(kSafari, @"topright"); Window(kCalc, @"bottomright"); Window(kMaps, @"right");
            RowMatchesAction([NSString stringWithFormat:@"%s: a fourth window open", en]);

            // 5. the rows beside it (unchanged): Swap Left and Right with two halves, on the same engines
            Fresh(e, sm, NO);
            Window(kNotes, @"left"); Window(kSafari, @"right");
            BOOL lr = DMSwapAvailable(YES);
            if (lr) DMSwapWindows(YES);
            Check([NSString stringWithFormat:@"%s: Swap Left and Right (two halves) is %s, as Swap Half and Quarter", en, ours ? "enabled and swaps them" : "greyed"],
                  lr == ours && (!ours || [Places(@[kNotes, kSafari]) isEqualToString:@"Notes right, Safari left"]), [NSString stringWithFormat:@"row %d, %@", lr, Places(@[kNotes, kSafari])]);
        }
    }
    return gFails;
}
