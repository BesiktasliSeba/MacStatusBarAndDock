// test-fitgreen.m -- Mac test (Mac Catalyst) of Fit to Window when a tiled window goes full screen (green), one rule for Aerial, Zetsu and MilkyWay4
// (1.8.7.5, audit L28 of 1.8.7.2). The closure check (DMWatchFitClosures) told "going full screen" from "closed" only by a mark Aerial's green puts
// on its stage (kStageGoingFullKey); Zetsu's and MilkyWay4's greens close the window itself, so their tile counted as closed: the other window slid to
// Fill (mostly under the green's cover) and back when the app returned. Now the app the green named (DMRememberFitForFullScreen, every engine) whose
// window is gone or closing has gone full screen too, once per green. Runs the real closure check, the Fit records (DMRememberFitForFullScreen,
// DMFitForgetFullScreenTile, DMFitFullScreenAppGone, DMFitRejoinAfterFullScreen) and their helpers, cut out of statusbar/StatusBar.x by
// test-fitgreen.sh into fg-real.inc, with the real statusbar/FitPlan.h; the windows are stand-in views, each engine's green as it marks them.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "../statusbar/FitPlan.h"

#define DM_FEATURE_MARK(name) do { } while (0)
#define DM_PERF(label, stmt) do { stmt; } while (0)
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
// ---- the windows: one view per app, in order (the engine's own list), each with its app
static NSMutableArray<UIView *> *gKStages;
static char kKBundleKey;
static NSString *DMStageBundle(UIView *stage) { return objc_getAssociatedObject(stage, &kKBundleKey); }
static BOOL DMStageMinimized(UIView *stage) { return NO; }
static NSArray<UIView *> *DMAerialStages(void) { return [gKStages copy]; }
static UIView *DMStageForBundle(NSString *bundleID) { for (UIView *s in gKStages) if ([DMStageBundle(s) isEqualToString:bundleID]) return s; return nil; }
static BOOL DMFitEnabled(void) { return YES; }
static void DMFitRepairOverlappingSlots(void) { }
BOOL DMSofaRelaunchKeepsFrame(NSString *bundleID) { return NO; }
BOOL DMA5ReopenKeepsFrame(NSString *bundleID) { return NO; }
// ---- what Fit asks for: its tiles applied (the windows moved into them), a window moved back into its tile
static int gKApplied;
static void DMApplyGroupSlots(UIView *fresh) { gKApplied++; }
static CGRect DMSlotFrame(NSString *bundleID);
static void DMTitleRecordEngineTo(UIView *v, CGRect to) { }
static int gKMoved;
static void DMAerialMoveStage(UIView *stage, CGRect target, void (^done)(void)) { gKMoved++; }

#include "fg-real.inc"

static CGRect DMSlotFrame(NSString *bundleID) { return gFitSlots[bundleID] ? CGRectMake(0, 0, 100, 100) : CGRectNull; }

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Logged(NSString *part) { for (NSString *l in gKLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }

typedef enum { KAerial, KZetsu, KMilkyWay } KEngine;
static NSString *const kNotes = @"com.apple.mobilenotes", *const kSettings = @"com.apple.Preferences", *const kSafari = @"com.apple.mobilesafari";
static UIView *Window(NSString *b) { UIView *v = [UIView new]; objc_setAssociatedObject(v, &kKBundleKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC); [gKStages addObject:v]; return v; }
static void Gone(NSString *b) { UIView *s = DMStageForBundle(b); if (s) [gKStages removeObject:s]; }
static void Tick(void) { gFitClosureCheckDue = YES; DMWatchFitClosures(); }
// Notes in the left half, Settings in the right one (Fit's group as the closure check last saw it)
static void TwoTiles(void) {
    gKLog = [NSMutableArray array]; gKStages = [NSMutableArray array]; gKApplied = 0; gKMoved = 0; gFreeWindows = nil;
    gFSFitBundle = nil; gFSFitGroup = nil; gFSFitSlots = nil;
    Window(kNotes); Window(kSettings);
    gFitGroup = [@[kNotes, kSettings] mutableCopy]; gFitSlots = [@{kNotes: @"left", kSettings: @"right"} mutableCopy];
    DMFitWatchSync();
}
// Each engine's green, as it marks the window (StatusBar.x DMStageLightAction / DMAerialToFullScreen, DMZetsuToFullScreen / DMZetsuClose,
// DMMilkyWayToFullScreen / DMExpandWindowToFullScreen): the tiling recorded first, then the window on its way out, then gone
static void Green(KEngine e, NSString *b) {
    DMRememberFitForFullScreen(b);
    UIView *s = DMStageForBundle(b);
    if (e == KAerial) { objc_setAssociatedObject(s, kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(s, kStageGoingFullKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    else if (e == KZetsu) objc_setAssociatedObject(s, kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (Zetsu's close of the window)
    Tick();
    Gone(b);   // (MilkyWay4's own close takes the window away: no mark of ours)
    Tick(); Tick();
}
static void Red(NSString *b) { objc_setAssociatedObject(DMStageForBundle(b), kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); Tick(); Gone(b); Tick(); }
static BOOL Slots(NSDictionary *want) { return [gFitSlots isEqualToDictionary:want]; }

int main(void) {
    @autoreleasepool {
        NSArray *names = @[@"Aerial", @"Zetsu", @"MilkyWay4"];
        for (int e = KAerial; e <= KMilkyWay; e++) {
            NSString *en = names[e];
            // green on a tiled window: the other keeps its tile; back as a window: its tile again
            TwoTiles();
            Green(e, kNotes);
            Check(gKApplied == 0 && Slots(@{kSettings: @"right"}), [NSString stringWithFormat:@"%@: green on Notes: Settings keeps its half (no re-tile to Fill)", en]);
            Check(Logged(@"com.apple.mobilenotes goes full screen: the other 1 window(s) keep their tiles") && !Logged(@"closed:"), [NSString stringWithFormat:@"%@: ... the log says it went full screen, not that it closed", en]);
            Window(kNotes);
            DMFitRejoinAfterFullScreen(kNotes);
            Tick();
            Check([gFitGroup isEqualToArray:@[kNotes, kSettings]] && Slots(@{kNotes: @"left", kSettings: @"right"}) && gKApplied == 0, [NSString stringWithFormat:@"%@: Notes back as a window: it takes its tile again, Settings stays", en]);
            Check(Logged(@"is back from full screen: it takes its tile again") && !gFSFitBundle, [NSString stringWithFormat:@"%@: ... and the record is gone", en]);
            // a second green on the same window, after its return: the same again
            Green(e, kNotes);
            Check(gKApplied == 0 && Slots(@{kSettings: @"right"}), [NSString stringWithFormat:@"%@: a second green after the return: Settings keeps its half again", en]);

            // red still closes the tile up
            TwoTiles();
            Red(kNotes);
            Check(gKApplied >= 1 && Slots(@{kSettings: @"fill"}) && Logged(@"com.apple.mobilenotes closed: 1 window(s) left"), [NSString stringWithFormat:@"%@: red on Notes: Settings fills (as before)", en]);

            // quit while full screen: the tile is closed up then, once
            TwoTiles();
            Green(e, kNotes);
            DMFitFullScreenAppGone(kNotes);
            Tick(); Tick();
            Check(gKApplied == 1 && Slots(@{kSettings: @"fill"}) && Logged(@"quit while full screen"), [NSString stringWithFormat:@"%@: Notes quit while full screen: Settings fills, once", en]);

            // once per green: back by another way (no return of the green's), tiled again, then closed: a close
            TwoTiles();
            Green(e, kNotes);
            Window(kNotes);
            gFitGroup = [@[kNotes, kSettings] mutableCopy]; gFitSlots = [@{kNotes: @"left", kSettings: @"right"} mutableCopy]; DMFitWatchSync();
            gKApplied = 0;
            Red(kNotes);
            Check(gKApplied >= 1 && Slots(@{kSettings: @"fill"}), [NSString stringWithFormat:@"%@: the green's record taken once: a later real close of the window closes its tile up", en]);

            // a green on a window outside the tiles records nothing: a tile closed after it is a close
            TwoTiles();
            Window(kSafari);
            Green(e, kSafari);
            Check(!gFSFitBundle && gKApplied == 0 && Slots(@{kNotes: @"left", kSettings: @"right"}), [NSString stringWithFormat:@"%@: green on a window outside the tiles: the tiles stay, nothing recorded", en]);
            Red(kNotes);
            Check(gKApplied >= 1 && Slots(@{kSettings: @"fill"}), [NSString stringWithFormat:@"%@: ... then red on a tile: Settings fills", en]);

            // placed from the Window menu while full screen: no tile back, and no full-screen reading of a later close
            TwoTiles();
            Green(e, kNotes);
            DMFitForgetFullScreenTile(kNotes);
            Check(!gFSFitBundle && Logged(@"placed from the Window menu"), [NSString stringWithFormat:@"%@: placed from the Window menu: its tile from before is not taken back (as before)", en]);
        }
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
