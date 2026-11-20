// test-fitgreen.m -- Mac test (Mac Catalyst) of Fit to Window when a tiled window goes full screen (green), one rule for Aerial, Zetsu and MilkyWay4
// (1.8.7.5, audit L28 of 1.8.7.2). The closure check (DMWatchFitClosures) told "going full screen" from "closed" only by a mark Aerial's green puts
// on its stage (kStageGoingFullKey); Zetsu's and MilkyWay4's greens close the window itself, so their tile counted as closed: the other window slid to
// Fill (mostly under the green's cover) and back when the app returned. Now the app the green named (DMRememberFitForFullScreen, every engine) whose
// window is gone or closing has gone full screen too, once per green. Runs the real closure check, the Fit records (DMRememberFitForFullScreen,
// DMFitForgetFullScreenTile, DMFitFullScreenAppGone, DMFitRejoinAfterFullScreen) and their helpers, cut out of statusbar/StatusBar.x by
// test-fitgreen.sh into fg-real.inc, with the real statusbar/FitPlan.h; the windows are stand-in views, each engine's green as it marks them.
// App Window Sizes (1.8.8, the review of F1-F4): its forget on change takes only the way back into the tile (DMFitForgetFullScreenWayBack, called
// as DMAppSizeForgetPlace calls it: KAppSizeForgetFit), so a quit while full screen still closes the tile up, as without the change and as on our
// Stage Manager engine; the green light's way back with no place kept ends the record on every engine (DMWindowLayout's lines: KLayoutFitLines).
// KT's decision c (19 Nov, 1.8.8 G2): a window that comes back from full screen as a free window -- that way back at the app's own size or at Fill,
// or a new window of the app opened free some other way while it was full screen (its Dock icon: the free mark, DMMarkFreeWindow) -- has its tile
// closed up at once (the other window fills, once), and its later quit changes nothing more; a window that Fit tiles, or that comes back to its
// own place, keeps the old rule. Our Stage Manager engine: test-smfitfullaway.
// The review of G1-G2, finding 1 (engine parity): a window that comes back from full screen as a window Fit tiles (its entry removed, Open at Fill
// off) is a new window -- DMCascadeStage's Fit part, played here as written there (FitJoinsAsNew): the first tile, the others keeping their places
// (FitPlan.h, through the real DMAssignTilesKeepingPlaces). Two tiles with Notes on the right: Notes the left half, Settings the right one; three,
// Notes the left half, Safari the top right, Settings the bottom right. test-smfitfullaway checks the same tiles on our Stage Manager engine.
// Finding 2: the record ends when the app is back as a window, so G2's close-ups act only on an app still full screen -- DMCascadeStage's line as
// the app's window opens not free while the record keeps no way back (KCascadeFitLines, as written; DMFitFullScreenOpensNew), and the forget once
// the app is a window again (the mark DMFitFullScreenOpensNew leaves on a record that keeps its way back, gFSFitBack; every green clears it).
// Before, the record of a green outlived the window its Dock icon opened: a size given then
// and the status bar's green light on that window closed the tiles up as if it came back from full screen as a free window.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "../statusbar/FitPlan.h"
#include "../statusbar/TurnPlace.h"   // (the layouts a window is noted in: DMStageSetLayoutNote, the H2-H5 review fix 6)
#include "../common/AppWindowSize.h"

#define DM_FEATURE_MARK(name) do { } while (0)
#define DM_PERF(label, stmt) do { stmt; } while (0)
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
// ---- the windows: one view per app, in order (the engine's own list), each with its app
static NSMutableArray<UIView *> *gKStages;
static char kKBundleKey;
static NSString *DMStageBundle(UIView *stage) { return objc_getAssociatedObject(stage, &kKBundleKey); }
static BOOL DMStageMinimized(UIView *stage) { return NO; }
static void DMSetStageIntent(UIView *v, CGRect f) { }   // (1.8.8 H2's DMFitPlaceAway: a minimized window put in its tile out of sight -- none here)
static void DMAerial5SyncState(UIView *stage, CGRect frame) { }
static BOOL gStageFrameBypass = NO;
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
// ---- what DMWindowLayout's lines read: the status bar's green light (back to where the window was), the apps' last places
static BOOL gPreferRememberedFrame = NO;
static NSMutableDictionary<NSString *, NSValue *> *gLastWindowFrames;
// ---- ... and whether the window opens free (G2): the apps' own sizes (DMAppSizeOf, App Window Sizes) and New Windows Open at Fill
static NSMutableDictionary<NSString *, NSNumber *> *gKSizes;
static int DMAppSizeOf(NSString *b) { NSNumber *n = b ? gKSizes[b] : nil; return n ? n.intValue : MSBDAppSizeNone; }
static BOOL gNewWindowsFill = NO;

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
    gFSFitBundle = nil; gFSFitGroup = nil; gFSFitSlots = nil; gLastWindowFrames = [NSMutableDictionary dictionary]; gKSizes = [NSMutableDictionary dictionary]; gNewWindowsFill = NO;
    Window(kNotes); Window(kSettings);
    gFitGroup = [@[kNotes, kSettings] mutableCopy]; gFitSlots = [@{kNotes: @"left", kSettings: @"right"} mutableCopy];
    DMFitWatchSync();
}
// Settings in the left half, Notes in the right one
static void TwoTilesNotesRight(void) {
    TwoTiles();
    gFitGroup = [@[kNotes, kSettings] mutableCopy]; gFitSlots = [@{kSettings: @"left", kNotes: @"right"} mutableCopy];
    DMFitWatchSync();
}
// Settings in the left half, Safari in the top right quarter, Notes in the bottom right one
static void ThreeTiles(void) {
    TwoTiles();
    Window(kSafari);
    gFitGroup = [@[kNotes, kSafari, kSettings] mutableCopy]; gFitSlots = [@{kSettings: @"left", kSafari: @"topright", kNotes: @"bottomright"} mutableCopy];
    DMFitWatchSync();
}
// Each engine's green, as it marks the window (StatusBar.x DMStageLightAction / DMAerialToFullScreen, DMZetsuToFullScreen / DMZetsuClose,
// DMMilkyWayToFullScreen / DMExpandWindowToFullScreen): the tiling recorded first, then the window on its way out, then gone
static void GreenWindowGoes(KEngine e, NSString *b) {
    UIView *s = DMStageForBundle(b);
    if (e == KAerial) { objc_setAssociatedObject(s, kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(s, kStageGoingFullKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    else if (e == KZetsu) objc_setAssociatedObject(s, kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (Zetsu's close of the window)
    Tick();
    Gone(b);   // (MilkyWay4's own close takes the window away: no mark of ours)
    Tick(); Tick();
}
static void Green(KEngine e, NSString *b) { DMRememberFitForFullScreen(b); GreenWindowGoes(e, b); }
// DMCascadeStage's Fit to Window part for a window that opens as a new one and is not free (no regular windows over the tiles here, and no side
// question: the windows left are never two halves when one of three or four tiles went): the window first, it and the others in the group, the
// tiles of the real DMAssignTilesKeepingPlaces (FitPlan.h: it takes the first tile, the others keep their places), applied
static void FitJoinsAsNew(NSString *me) {
    [gFitGroup removeObject:me];
    gFitGroup = [MSBDFitWhenOneOpens(me, gFitGroup, @[]) mutableCopy];
    [gFitGroup removeObject:me];
    [gFitGroup insertObject:me atIndex:0];
    if (gFitGroup.count >= 2) { DMAssignTilesKeepingPlaces(me); DMApplyGroupSlots(nil); }
}
// The status bar's green light on the full-screen app (DMLightAction -> DMWindowLayout with gPreferRememberedFrame): DMWindowLayout's lines, then
// the window opens; Aerial's and Zetsu's way back call DMFitRejoinAfterFullScreen always, MilkyWay4's only for a frame asked for (its last place)
static void GreenBack(KEngine e, NSString *b) {
    BOOL place = gLastWindowFrames[b] != nil;
    gPreferRememberedFrame = YES; KLayoutFitLines(b); gPreferRememberedFrame = NO;
    Window(b);
    // (DMCascadeStage: no place of its own and the app's own size or Fill -- free, the real free mark; no place of its own and not free -- a new
    //  window Fit tiles, FitJoinsAsNew; with a place of its own it is placed there, the way back below gives it its tile)
    if (!place) KCascadeFitLines(b, YES, DMAppSizeOf(b), NO, NO);   // (the window opens through the cascade: its record line as written)
    if (MSBDOpensFree(DMAppSizeOf(b), gNewWindowsFill, place, NO)) DMMarkFreeWindow(b);
    else if (!place) FitJoinsAsNew(b);
    if (e != KMilkyWay || place) DMFitRejoinAfterFullScreen(b);
    Tick();
}
// A new window of the app opened some other way while it was full screen (its Dock icon, Open Apps as Windows: DMWindowedLaunch, then
// DMCascadeStage: its record line as written, then the free mark -- the app's own size or Fill, no place of its own -- or Fit's join as a new
// window); no way back of the green's. Its place: where its window last was (gLastWindowFrames), as the cascade reads it
static void DockOpens(NSString *b) {
    BOOL place = gLastWindowFrames[b] != nil;
    Window(b);
    KCascadeFitLines(b, YES, DMAppSizeOf(b), place, NO);
    if (MSBDOpensFree(DMAppSizeOf(b), gNewWindowsFill, place, NO)) DMMarkFreeWindow(b); else FitJoinsAsNew(b);
    Tick();
}
static void DockOpensFree(NSString *b) { DockOpens(b); }
// The app quits from its window (red: the window closes, then the app exits)
static void Red(NSString *b);
static void QuitFromWindow(NSString *b) { Red(b); DMFitFullScreenAppGone(b); Tick(); }
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
            KLayoutFitLines(kNotes);   // (DMWindowLayout's lines as written, a layout: gPreferRememberedFrame NO)
            Check(!gFSFitBundle && Logged(@"placed from the Window menu"), [NSString stringWithFormat:@"%@: placed from the Window menu: its tile from before is not taken back (as before)", en]);

            // the green light's way back with its place kept (no size change): its tile again, the record not ended before the window is back
            TwoTiles();
            Green(e, kNotes);
            gLastWindowFrames[kNotes] = [NSValue valueWithCGRect:CGRectMake(0, 0, 100, 100)];
            GreenBack(e, kNotes);
            Check([gFitGroup isEqualToArray:@[kNotes, kSettings]] && Slots(@{kNotes: @"left", kSettings: @"right"}) && gKApplied == 0 && !gFSFitBundle && Logged(@"is back from full screen: it takes its tile again"),
                  [NSString stringWithFormat:@"%@: green back with its place kept: its tile again, Settings as it was (DMWindowLayout's lines as written)", en]);
#if KAPPSIZES
            // App Window Sizes (1.8.8, the review of F1-F4), row A7 c with Fit: green on Notes, then Notes given a size while full screen. The forget
            // takes only the way back into the tile: it comes back as a new window at its new size, and a quit while full screen still closes its tile
            // up (before, the whole record went and Settings kept its half: Stage Manager filled it, DMSMFitForgetClosed)
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes);
            Tick(); Tick();
            Check(gKApplied == 0 && Slots(@{kSettings: @"right"}) && !gFSFitGroup && !gFSFitSlots && [gFSFitBundle isEqualToString:kNotes] && Logged(@"has a new size (App Window Sizes): it does not take back its tile"),
                  [NSString stringWithFormat:@"%@: A7 c + Fit: a size given while full screen: Settings keeps its half; the way back into the tile gone, the record kept", en]);
            DMFitFullScreenAppGone(kNotes);
            Tick(); Tick();
            Check(gKApplied == 1 && Slots(@{kSettings: @"fill"}) && Logged(@"quit while full screen") && !gFSFitBundle,
                  [NSString stringWithFormat:@"%@: ... then Notes quits while full screen: Settings fills, once (as without the change, as on Stage Manager)", en]);
            // ... and green back instead: a new window at its new size (no place kept, free), not in its old tile. KT's decision c (19 Nov, G2): its
            // tile is closed up at once -- Settings fills, once -- the record ending there, so a later quit of that window changes nothing more, the
            // same on Aerial, Zetsu and MilkyWay4 (before: the record just ended and Settings kept its half next to the empty one for good)
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes); gKSizes[kNotes] = @(MSBDAppSizeLarge);
            GreenBack(e, kNotes);
            Check(!gFSFitBundle && gKApplied == 1 && Slots(@{kSettings: @"fill"}) && ![gFitGroup containsObject:kNotes] && [gFreeWindows containsObject:kNotes]
                  && Logged(@"comes back from full screen as a free window, not into its tile: 1 window(s) left") && !Logged(@"comes back from full screen with no place of its own kept"),
                  [NSString stringWithFormat:@"%@: G2 ... green back free at its new size: Settings fills at once, once; the record ended", en]);
            gKApplied = 0;
            QuitFromWindow(kNotes);
            Check(gKApplied == 0 && Slots(@{kSettings: @"fill"}) && !Logged(@"quit while full screen"),
                  [NSString stringWithFormat:@"%@: G2 ... then Notes quits from that window: nothing more (Settings stays filling)", en]);
            // three tiles: the two left close it up, each keeping its place (Settings its half, Safari the right half)
            ThreeTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes); gKSizes[kNotes] = @(MSBDAppSizeIPhone);
            GreenBack(e, kNotes);
            Check(!gFSFitBundle && gKApplied == 1 && Slots(@{kSettings: @"left", kSafari: @"right"}) && [gFreeWindows containsObject:kNotes],
                  [NSString stringWithFormat:@"%@: G2 three tiles, Notes back free: Settings keeps its half, Safari takes the right half, at once", en]);
            gKApplied = 0;
            QuitFromWindow(kNotes);
            Check(gKApplied == 0 && Slots(@{kSettings: @"left", kSafari: @"right"}), [NSString stringWithFormat:@"%@: G2 ... then Notes quits: nothing more", en]);
            // its Dock icon instead of the green light (Open Apps as Windows): a new window at its new size, free -- its tile closed up then, once
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes); gKSizes[kNotes] = @(MSBDAppSizeLarge);
            DockOpensFree(kNotes);
            Check(!gFSFitBundle && gKApplied == 1 && Slots(@{kSettings: @"fill"}) && Logged(@"comes back from full screen as a free window, not into its tile"),
                  [NSString stringWithFormat:@"%@: G2 ... Notes from its Dock icon instead, free: Settings fills at once, once", en]);
            gKApplied = 0;
            QuitFromWindow(kNotes);
            Check(gKApplied == 0 && Slots(@{kSettings: @"fill"}) && !Logged(@"quit while full screen"), [NSString stringWithFormat:@"%@: G2 ... then Notes quits: nothing more", en]);
            // the entry removed while full screen (Window Size, Open at Fill off): the way back is a new window Fit tiles as any other -- no close-up
            // first (Settings would fill, then go back to a half), the record just ends there, as before; MilkyWay4 has no other end of it
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes);
            GreenBack(e, kNotes);
            Check(!gFSFitBundle && gKApplied == 1 && Slots(@{kNotes: @"left", kSettings: @"right"}) && ![gFreeWindows containsObject:kNotes]
                  && Logged(@"comes back from full screen with no place of its own kept") && !Logged(@"as a free window") && !Logged(@"re-tiled to fill the space"),
                  [NSString stringWithFormat:@"%@: G2 the entry removed instead: a window Fit tiles, no close-up first; the record ended (as before)", en]);
            // ... (the review of G1-G2, finding 1) Notes on the right: a new window takes the first tile -- Notes the left half, Settings the right one,
            //     the same on our Stage Manager engine now (test-smfitfullaway, case 10)
            TwoTilesNotesRight();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes);
            GreenBack(e, kNotes);
            Check(!gFSFitBundle && gKApplied == 1 && Slots(@{kNotes: @"left", kSettings: @"right"}) && !Logged(@"as a free window") && !Logged(@"re-tiled to fill the space"),
                  [NSString stringWithFormat:@"%@: the entry removed, Notes on the right: back as a new window, Notes the left half, Settings the right one", en]);
            // ... three tiles, Notes in the bottom right quarter: Notes the left half, Safari the top right, Settings the bottom right
            ThreeTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes);
            GreenBack(e, kNotes);
            Check(!gFSFitBundle && gKApplied == 1 && Slots(@{kNotes: @"left", kSafari: @"topright", kSettings: @"bottomright"}) && !Logged(@"as a free window"),
                  [NSString stringWithFormat:@"%@: the entry removed, three tiles: back as a new window, Notes the left half, Safari the top right, Settings the bottom right", en]);
            // ... with New Windows Open at Fill on: it comes back free, at Fill -- its tile closed up at once
            TwoTiles(); gNewWindowsFill = YES;
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes);
            GreenBack(e, kNotes);
            Check(!gFSFitBundle && gKApplied == 1 && Slots(@{kSettings: @"fill"}) && [gFreeWindows containsObject:kNotes] && Logged(@"as a free window"),
                  [NSString stringWithFormat:@"%@: G2 ... with New Windows Open at Fill on: back free at Fill, Settings fills at once", en]);
            // A7 b': Notes tiled and given a size while it is a window (its place kept by the green), then green to full screen and back: its tile
            // again, Settings as it was -- not free, no close-up
            TwoTiles();
            gKSizes[kNotes] = @(MSBDAppSizeIPhone);
            Green(e, kNotes);
            gLastWindowFrames[kNotes] = [NSValue valueWithCGRect:CGRectMake(0, 0, 100, 100)];   // (the green's own record of its place, DMStageLightAction)
            GreenBack(e, kNotes);
            Check([gFitGroup isEqualToArray:@[kNotes, kSettings]] && Slots(@{kNotes: @"left", kSettings: @"right"}) && gKApplied == 0 && !gFSFitBundle && ![gFreeWindows containsObject:kNotes] && !Logged(@"as a free window"),
                  [NSString stringWithFormat:@"%@: G2 A7 b' (a size given while tiled, its place kept): green back into its tile, no close-up", en]);
            // another app's window opening free while Notes is full screen (Safari at its own size): Notes' tile and record stay
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes); gKSizes[kSafari] = @(MSBDAppSizeLarge);
            DockOpensFree(kSafari);
            Check([gFSFitBundle isEqualToString:kNotes] && gKApplied == 0 && Slots(@{kSettings: @"right"}) && !Logged(@"as a free window"),
                  [NSString stringWithFormat:@"%@: G2 another app's window opening free meanwhile: Notes' tile and record stay", en]);
            // (the review of G1-G2, finding 2) green on Notes, then Notes back by its Dock icon at its place (a new window Fit tiles: the record keeps its
            // way back -- on Aerial the green's own way back can come this way too), then a size given while it is a window, then the status bar's
            // green light on that window: the record ended at the forget, so no close-up (before: Settings filled, "as a free window")
            TwoTilesNotesRight();
            Green(e, kNotes);
            gLastWindowFrames[kNotes] = [NSValue valueWithCGRect:CGRectMake(0, 0, 100, 100)];
            DockOpens(kNotes);
            Check([gFSFitBundle isEqualToString:kNotes] && gFSFitGroup && Slots(@{kNotes: @"left", kSettings: @"right"}),
                  [NSString stringWithFormat:@"%@: finding 2: Notes back by its Dock icon at its place: a new window tiled, the record kept with its way back", en]);
            [gLastWindowFrames removeObjectForKey:kNotes]; gKSizes[kNotes] = @(MSBDAppSizeLarge); KAppSizeForgetFit(kNotes);
            Check(!gFSFitBundle && Logged(@"has a new size (App Window Sizes) while it is a window again: it does not take back its tile"),
                  [NSString stringWithFormat:@"%@: finding 2: ... a size given while it is a window again: the record ends", en]);
            gKApplied = 0;
            gPreferRememberedFrame = YES; KLayoutFitLines(kNotes); gPreferRememberedFrame = NO;
            Check(gKApplied == 0 && Slots(@{kNotes: @"left", kSettings: @"right"}) && !Logged(@"as a free window") && !gFSFitBundle,
                  [NSString stringWithFormat:@"%@: finding 2: ... the status bar's green on that window: no close-up, the record gone", en]);
            // ... the forget while full screen, then its Dock icon as a window Fit tiles (the entry removed): the app is back as a window, the record
            //     ends as it opens; its later quit is a tiled window's close (Settings fills, once), not one while full screen
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes);
            DockOpens(kNotes);
            Check(!gFSFitBundle && Slots(@{kNotes: @"left", kSettings: @"right"}) && Logged(@"opens a new window (its place was forgotten while it was full screen): it does not take back its tile") && !Logged(@"re-tiled to fill the space"),
                  [NSString stringWithFormat:@"%@: finding 2: the forget while full screen, then its Dock icon as a window Fit tiles: the record ends as it opens", en]);
            gKApplied = 0;
            QuitFromWindow(kNotes);
            Check(Slots(@{kSettings: @"fill"}) && !Logged(@"quit while full screen") && Logged(@"com.apple.mobilenotes closed: 1 window(s) left"),
                  [NSString stringWithFormat:@"%@: finding 2: ... then Notes quits from that window: no close-up as if full screen (its tile closes up as a window's)", en]);
            // ... unchanged: a record that keeps its way back stays through a window's open, so the green light's way back that opens through the cascade
            //     (Aerial with no entrance cover: the cascade tiles it as a new window first) takes its tile back right after
            TwoTilesNotesRight();
            Green(e, kNotes);
            gLastWindowFrames[kNotes] = [NSValue valueWithCGRect:CGRectMake(0, 0, 100, 100)];
            DockOpens(kNotes);
            DMFitRejoinAfterFullScreen(kNotes);
            Check(!gFSFitBundle && Slots(@{kSettings: @"left", kNotes: @"right"}) && Logged(@"is back from full screen: it takes its tile again"),
                  [NSString stringWithFormat:@"%@: finding 2: a record with its way back stays through the cascade: the green's way back after it, its tile again", en]);
            // ... a new green after that window: a fresh record, not marked back -- a size given while full screen takes only the way back, and its
            //     quit while full screen still closes the tile up
            TwoTilesNotesRight();
            Green(e, kNotes);
            gLastWindowFrames[kNotes] = [NSValue valueWithCGRect:CGRectMake(0, 0, 100, 100)];
            DockOpens(kNotes);   // (the record stays, marked back)
            Green(e, kNotes);
            KAppSizeForgetFit(kNotes);
            Check([gFSFitBundle isEqualToString:kNotes] && !gFSFitGroup && !Logged(@"while it is a window again"), [NSString stringWithFormat:@"%@: finding 2: a new green after it: a fresh record, a size given while full screen takes only the way back", en]);
            gKApplied = 0;
            DMFitFullScreenAppGone(kNotes); Tick(); Tick();
            Check(gKApplied == 1 && Slots(@{kSettings: @"fill"}) && Logged(@"quit while full screen"), [NSString stringWithFormat:@"%@: finding 2: ... then it quits while full screen: Settings fills, once", en]);
            // the size given in the same moment as the green, before Fit saw the window go: still full screen's, not a close
            TwoTiles();
            DMRememberFitForFullScreen(kNotes);
            KAppSizeForgetFit(kNotes);
            GreenWindowGoes(e, kNotes);
            Check(gKApplied == 0 && Slots(@{kSettings: @"right"}) && Logged(@"com.apple.mobilenotes goes full screen: the other 1 window(s) keep their tiles") && !Logged(@"closed:"),
                  [NSString stringWithFormat:@"%@: a size given before Fit saw the window go: it went full screen, Settings keeps its half", en]);
            // a size given to another app: Notes' way back into its tile is kept
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kSettings);
            Check(gFSFitGroup && gFSFitSlots && [gFSFitBundle isEqualToString:kNotes], [NSString stringWithFormat:@"%@: a size given to another app: Notes' way back into its tile kept", en]);
            // ... one with no window open (Safari)
            TwoTiles();
            Green(e, kNotes);
            KAppSizeForgetFit(kSafari);
            Check(gFSFitGroup && gFSFitSlots && [gFSFitBundle isEqualToString:kNotes], [NSString stringWithFormat:@"%@: a size given to another app with no window open: Notes' way back into its tile kept", en]);
#endif
        }
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
