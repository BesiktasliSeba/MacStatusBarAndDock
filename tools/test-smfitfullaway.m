// test-smfitfullaway.m -- Mac test of Fit to Window on our Stage Manager engine while a tiled window is full screen out of sight (1.8.8 G1, KT's
// decision b, 19 Nov: as Aerial keeps the tiles). The desktop's windows came over the full-screen window in its stage (the Dock, Command-Tab, Bring
// All to Front), or the full-screen window is in a stage of its own while the desktop is on screen (sent to the background by Home, opened from the
// strip, the desktop tapped in the strip again). Fit's look took it for gone: the windows on screen were tiled again without it (three tiles: the two
// left as a pair) and its way back was dropped ("closed meanwhile"), so back on the desktop it was a new window -- the third window's question, at
// its launch from the Dock (DMSMFitAsksAbout) and at Fit's look. Aerial: a window gone full screen leaves the tiles, the others keep theirs, and it
// takes its tile back on its return (DMWatchFitClosures, DMFitRejoinAfterFullScreen; test-fitgreen). Runs the engine's real code, cut out of
// statusbar/StatusBar.x by test-smfitfullaway.sh into sfa-real.inc: Fit's look (DMSMFitTick), the windows full screen out of sight (DMSMFitFullAway,
// when the file has it), the closed windows' forget (DMSMFitForgetClosed), the question before a launch (DMSMFitAsksAbout), with the real
// statusbar/SMFitPlan.h, FitPlan.h, SMWindowKey.h and common/AppWindowSize.h; SpringBoard's stages are stand-ins (a stage: window key -> full screen,
// interaction time; the iPad's stages, the one on screen first).
// 1.8.8 G2 (KT's decision c, 19 Nov): a window back from full screen as a free window -- App Window Sizes' forget took its place before full screen
// while it was full screen, so it joins as a new one at its own size or at Fill, which Fit leaves out -- gives its tile up at once: the windows left
// close it up, and its later quit changes nothing more (DMSMFitBackFree, from the join's free mark: DMSMJoinAttributesOn's lines as written, KJoinFreeLines).
// The review of G1-G2, finding 1 (engine parity): the same window back as a window Fit tiles -- its entry removed while it was full screen, Open at
// Fill off -- is a new window (design 1.6): its old tile, kept only for a quit while full screen, is no way back (DMSMFitBackAsNew, the join's line
// after G2's). It takes the first tile and the others keep their places, as Aerial, Zetsu and MilkyWay4 tile it (test-fitgreen, the same tiles);
// before, it took its old tile again (two tiles with Notes on the right: kept on the right; three: the bottom right quarter, not the left half).
// 1.8.8 H3 (the iPad 2's row C14 of p03): a window back from full screen into the tile Fit kept for it is done with its way back there too, when
// Fit's look returns early -- the minimized rule (another tile minimized or full screen out of sight) and the one-window rule (DMSMFitBackInTile,
// when the file has it). Before, it stayed full screen's for Fit until the arrangement's other windows were back: Clock back in its tile was
// listed as full screen while Settings stayed minimized, "its tile again" came only with Settings, its next full screen noted no arrangement
// left, and with its tile taken meanwhile it was asked about as a third window on its return (case 11).
// The H-round review of H3, finding 1: the one-window rule ends the way back only where it lays the window out (at Fill). A window back alone in a
// stage of its own, its tile kept and the desktop's other window on another stage (L-7: nothing laid out), keeps its way back until it joins the
// desktop; H3 as first written logged "its tile again" for it there, in no tile, and smfit listed it full screen none (case 11, L-7).
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include "../statusbar/SMFitPlan.h"
#include "../common/AppWindowSize.h"

static NSMutableArray<NSString *> *gKLog, *gKMarks, *gKAsked;
static NSMutableArray<NSDictionary *> *gKApplied;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
#define DM_FEATURE_MARK(name) [gKMarks addObject:@name]
#define DMTestFlag(path) 0
@class UIView;
// ---- what Fit keeps (StatusBar.x's own globals, the same types)
static NSMutableDictionary *gSidePromptCtx;
static NSMutableDictionary<NSString *, NSString *> *gSMFitSlots;
static NSMutableSet<NSString *> *gSMFreeWindows, *gSMFitLoose, *gSMFitWentFull;
static NSMutableDictionary<NSString *, NSNumber *> *gSMFitPending;
static NSDictionary<NSString *, NSString *> *gSMFitSlotsBeforeFull;
static NSMutableDictionary<NSString *, NSDictionary *> *gSMFitByDesk;
static NSMutableArray<NSString *> *gSMFitByDeskOrder;
static NSArray<NSString *> *gSMFitAdopt;
static CFTimeInterval gSMFitAdoptUntil;
static BOOL gMSWSwitching = NO, gNewWindowsFill = NO, gSMSkipFitAsk = NO, gSMFitLookAgain = NO, gKFitOff = NO;
static unsigned gSMTurns;
// ---- the screen (its shape is part of Fit's set)
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@property (nonatomic) CGRect bounds;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; if (!s) { s = [UIScreen new]; s.bounds = CGRectMake(0, 0, 1366, 1024); } return s; }
@end
static NSString *NSStringFromCGSize(CGSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
// ---- SpringBoard's stages: each a dictionary window key -> @{full, t}, a new object at every change (as SpringBoard makes a new stage)
static NSArray<NSDictionary *> *gKStages;
static NSMutableSet<NSString *> *gKMin;
static NSArray *DMSMRecentStages(void) { return gKStages; }
static id DMSMFrontStage(void) { return gKStages.firstObject; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[NSDictionary class]] ? stage : nil; }
static id DMSMStageDisplayIdentity(id stage) { return stage ? @"main" : nil; }
static BOOL DMSMIsMainIdentity(id identity) { return [identity isEqual:@"main"]; }
static NSString *DMSMItemKey(id item) { return item; }
static BOOL DMSMAttrsFullScreen(id attrs) { return [attrs[@"full"] boolValue]; }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { NSNumber *t = attrs[@"t"]; return t ? t.longLongValue : dflt; }
static NSString *KFrontKey(void) {   // (the front stage's newest window)
    NSDictionary *m = DMSMFrontStage(); NSString *best = nil; long long t = LLONG_MIN;
    for (NSString *k in m) if (DMSMAttrTimeOr(m[k], 0) > t) { t = DMSMAttrTimeOr(m[k], 0); best = k; }
    return best;
}
static NSString *DMFrontApp(void) { return DMSMKeyBundle(KFrontKey()); }   // (nil: the Home Screen)
static BOOL DMSMFrontIsFullScreen(void) { NSString *k = KFrontKey(); return k && DMSMAttrsFullScreen(((NSDictionary *)DMSMFrontStage())[k]); }
static NSArray<NSString *> *DMSMWindowKeys(void) {   // (the windows on screen: the front stage's, not full screen)
    NSMutableArray *a = [NSMutableArray array]; NSDictionary *m = DMSMFrontStage();
    for (NSString *k in m) if (!DMSMAttrsFullScreen(m[k])) [a addObject:k];
    return a;
}
static BOOL DMSMIsMinimized(NSString *key) { return DMSMKeySetHas(gKMin, key); }
static BOOL DMSMEngine(void) { return YES; }
static BOOL DMFitEnabled(void) { return !gKFitOff; }
static BOOL DMSMWorkspaceBusy(void) { return NO; }
static BOOL DMSMTurnSettling(void) { return NO; }
static BOOL DMSMSpotlightHolds(void) { return NO; }
static BOOL DMSwitcherVisible(void) { return NO; }
static BOOL DMSMGestureLive(void) { return NO; }
// ---- what Fit asks for: layouts (recorded), the question (recorded, not answered); the respring's adopt is not played here
static void DMTitleRecordSMPlan(NSDictionary *plan, id stage) { }
static BOOL DMSMApplyLayoutsIn(NSDictionary<NSString *, NSString *> *plan, id stage) { [gKApplied addObject:[plan copy]]; return YES; }
static BOOL DMSMApplyPlacesIn(NSDictionary<NSString *, id> *plan, id stage) { [gKApplied addObject:[plan copy]]; return YES; }
static void DMSMBringToFront(NSString *key) { }
static id DMSMNoFitPlace(id stage) { return @"center"; }
static void DMPromptForSideApply(UIView *stage, NSString *newBundle, NSString *leftBundle, NSString *rightBundle, void (^apply)(NSString *side)) { [gKAsked addObject:newBundle ?: @"?"]; }
static BOOL DMSMFitWindowsInTilesNow(NSArray<NSString *> *keys) { return NO; }
static NSArray<NSString *> *DMSMFitWindowsSittingInTiles(NSArray<NSString *> *keys) { return @[]; }
static NSDictionary<NSString *, NSString *> *DMSMFitTilesFromPlaces(NSDictionary *map, NSArray *items, NSArray<NSString *> *keys) { return nil; }
static int DMAppSizeOf(NSString *bundle) { return 0; }   // (no App Window Sizes entry)
static BOOL DMSMOpensAtOwnSize(NSString *key) { return NO; }

#include "sfa-real.inc"

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) {
    gChecks++; if (!ok) gFails++;
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    if (!ok) printf("      tiles %s; full screen's %s; asked %s; last layout %s\n", [gSMFitSlots.description stringByReplacingOccurrencesOfString:@"\n" withString:@" "].UTF8String,
                    [[gSMFitWentFull.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "].UTF8String, [gKAsked componentsJoinedByString:@", "].UTF8String,
                    [gKApplied.lastObject.description stringByReplacingOccurrencesOfString:@"\n" withString:@" "].UTF8String);
}
static BOOL Logged(NSString *part) { for (NSString *l in gKLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }
static BOOL Marked(NSString *m) { return [gKMarks containsObject:m]; }
// A window of a stage: key, full screen or not, its interaction time (the newest of the front stage is in front)
static NSArray *E(NSString *k, long long t) { return @[k, @NO, @(t)]; }
static NSArray *EF(NSString *k, long long t) { return @[k, @YES, @(t)]; }
static NSDictionary *Stage(NSArray<NSArray *> *wins) {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSArray *w in wins) m[w[0]] = @{@"full": w[1], @"t": w[2]};
    return [m copy];
}
static void Stages(NSArray<NSDictionary *> *s) { gKStages = [s copy]; }
static void Clear(void) { gKLog = [NSMutableArray array]; gKMarks = [NSMutableArray array]; gKAsked = [NSMutableArray array]; gKApplied = [NSMutableArray array]; }
static void Tick(void) { DMSMFitTick(NO); }
static void Turn(void) { CGRect b = [UIScreen mainScreen].bounds; [UIScreen mainScreen].bounds = CGRectMake(0, 0, b.size.height, b.size.width); gSMTurns++; }
// Fit with this arrangement and these windows on the desktop (the tick's own memory of the last set cleared: Fit off for one look)
static void Reset(NSDictionary *slots, NSArray<NSDictionary *> *stages) {
    gKFitOff = YES; DMSMFitTick(NO); gKFitOff = NO;
    gSMFitSlots = [slots mutableCopy]; gSMFreeWindows = [NSMutableSet set]; gSMFitLoose = nil; gSMFitWentFull = nil; gSMFitSlotsBeforeFull = nil;
    gSMFitByDesk = nil; gSMFitByDeskOrder = nil; gSMFitPending = nil; gKMin = [NSMutableSet set];
    if ([UIScreen mainScreen].bounds.size.width < [UIScreen mainScreen].bounds.size.height) Turn();
    Stages(stages); Clear(); Tick(); Clear();
}
static BOOL Laid(NSDictionary *want) { return [gKApplied.lastObject isEqualToDictionary:want]; }
static BOOL Tiles(NSDictionary *want) { return [gSMFitSlots isEqualToDictionary:want]; }
static BOOL FullScreens(NSArray *want) { return [[NSSet setWithArray:want] isEqualToSet:gSMFitWentFull ?: [NSSet set]]; }

#define K(app) @"com.apple." app "|sceneID:com.apple." app "-default"
int main(void) {
    @autoreleasepool {
        NSString *A = K("Preferences"), *B = K("mobilesafari"), *C = K("mobilenotes"), *D = K("Maps"), *F = K("mobiletimer"), *T = K("tips");
        NSDictionary *three = @{A: @"left", B: @"topright", C: @"bottomright"};

        // 1. Three tiles; green on Notes (full screen in the desktop's stage); the desktop's windows come over it (the Dock, Command-Tab)
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(C, 4)])]); Tick();
        Check(FullScreens(@[C]) && Tiles(three) && !gKApplied.count, @"1. green on Notes: noted as full screen with its tile, nothing laid out");
        Stages(@[Stage(@[E(A, 5), E(B, 6), EF(C, 4)])]); Tick();
        Check(Laid(@{A: @"left", B: @"topright"}) && gKApplied.count == 1 && Tiles(three), @"1. Settings and Safari over the full-screen Notes: they keep their tiles (no re-tile as a pair), Notes keeps its own");
        Check(FullScreens(@[C]) && Marked(@"sm-fit-full-away-keep-tiles") && Logged(@"1 window(s) full screen out of sight (0 minimized besides) keep their tiles for their way back -- the 2 on screen keep theirs"),
              @"1. ... Notes keeps its way back; the log says why");
        Turn(); Tick();
        Check(Laid(@{A: @"left", B: @"topright"}) && Tiles(three) && FullScreens(@[C]), @"1. the iPad turns meanwhile: the same tiles, laid out for the new shape");
        Clear(); Tick();
        Check(!gKApplied.count && !gKAsked.count, @"1. the next look: nothing to do");
        Stages(@[Stage(@[E(A, 5), E(B, 6), E(C, 7)])]); Tick();
        Check(Laid(three) && Tiles(three) && !gKAsked.count && FullScreens(@[]) && Logged(@"back from full screen -- its tile again"), @"1. Notes back from full screen (green): its tile again, no question");

        // 2. ... Home sent Notes to the background (minimized: a stage of its own), the strip opened it again (no longer minimized), and the
        //    desktop is tapped in the strip: the desktop's stage on screen, Notes full screen in its own
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(C, 4)])]); Tick();
        [gKMin addObject:C]; Stages(@[Stage(@[E(A, 5), E(B, 6)]), Stage(@[EF(C, 4)])]); Tick();
        Check(Laid(@{A: @"left", B: @"topright"}) && Tiles(three) && FullScreens(@[C]) && Logged(@"1 minimized window(s) keep their tiles -- the 2 on screen keep theirs"),
              @"2. Home: Notes to the background, minimized: the tiles kept (as before, the minimized rule)");
        [gKMin removeObject:C]; Stages(@[Stage(@[EF(C, 8)]), Stage(@[E(A, 5), E(B, 6)])]); Clear(); Tick();
        Check(!gKApplied.count && FullScreens(@[C]), @"2. Notes opened from the strip, full screen in front: nothing laid out");
        Stages(@[Stage(@[E(A, 9), E(B, 6)]), Stage(@[EF(C, 8)])]); Tick();
        Check(Laid(@{A: @"left", B: @"topright"}) && Tiles(three), @"2. the desktop tapped in the strip, Notes full screen in its own stage: Settings and Safari keep their tiles (no re-tile as a pair)");
        Check(FullScreens(@[C]), @"2. ... and Notes keeps its way back (not taken for closed)");
        NSString *l = nil, *r = nil;
        Check(!DMSMFitAsksAbout(DMSMKeyBundle(C), @[A, B], &l, &r), @"2. Notes opened from the Dock now: no third window's question before its launch");
        Stages(@[Stage(@[E(A, 9), E(B, 6), E(C, 10)])]); Tick();
        Check(Laid(three) && Tiles(three) && !gKAsked.count && FullScreens(@[]) && Logged(@"back from full screen -- its tile again"),
              @"2. Notes back on the desktop as a window: its tile again, no third window's question");

        // 3. Two tiles; Notes full screen in its own stage, Settings on the desktop: Settings keeps its half; a window opened on the desktop meanwhile
        //    (SpringBoard's launch) and a turn: Notes still comes back as itself, not as a new window to ask about (Aerial: its tile back, no question)
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(C, 3)])]); Tick();
        Check(Tiles(@{A: @"left", C: @"right"}) && FullScreens(@[C]) && (!gKApplied.count || Laid(@{A: @"left"})) && !gKAsked.count, @"3. two tiles, Notes full screen out of sight: Settings keeps its half");
        Stages(@[Stage(@[E(A, 4), E(D, 5)]), Stage(@[EF(C, 3)])]); Tick();
        Check(gSMFitSlots.count == 2 && gSMFitSlots[A] && gSMFitSlots[D] && FullScreens(@[C]), @"3. Maps opens on the desktop: tiled with Settings; Notes keeps its way back");
        Turn(); Tick();
        Check(FullScreens(@[C]), @"3. ... a turn later still (its tile now Maps', the arrangement it left still names it)");
        Stages(@[Stage(@[E(A, 4), E(D, 5), E(C, 6)])]); Tick();
        Check(!gKAsked.count && FullScreens(@[]) && Logged(@"back from full screen") && gSMFitSlots.count == 3, @"3. Notes back from full screen: tiled with the two, no third window's question");

        // 4. Notes quits while full screen out of sight: its tile is closed up, as on every engine (DMSMFitForgetClosed; unchanged)
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(C, 4)])]); Tick();
        Stages(@[Stage(@[E(A, 5), E(B, 6), EF(C, 4)])]); Tick();
        Stages(@[Stage(@[E(A, 5), E(B, 6)])]); Tick();
        Check(Tiles(@{A: @"left", B: @"right"}) && Laid(@{A: @"left", B: @"right"}) && FullScreens(@[]) && !gKAsked.count, @"4. Notes quits while full screen: Settings and Safari close its tile up");

        // 5. a minimized tile (its own stage, a window): the tiles kept, the log as before (unchanged)
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        [gKMin addObject:C]; Stages(@[Stage(@[E(A, 4), E(B, 5)]), Stage(@[E(C, 3)])]); Tick();
        Check(Laid(@{A: @"left", B: @"topright"}) && Tiles(three) && !Marked(@"sm-fit-full-away-keep-tiles") && Logged(@"1 minimized window(s) keep their tiles -- the 2 on screen keep theirs"),
              @"5. Notes minimized: the tiles kept, the log as before");

        // 6. a tile as a window in a stage of its own (not full screen, not minimized): Fit lays the desktop out again, as before
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 4), E(B, 5)]), Stage(@[E(C, 3)])]); Tick();
        Check(gSMFitSlots.count == 2 && gSMFitSlots[A] && gSMFitSlots[B] && ![gKApplied.lastObject objectForKey:C] && gKApplied.count == 1, @"6. Notes a window in a stage of its own: the two on screen tiled again (unchanged)");

        // 7. a No Fit window full screen, the desktop's windows over it: it left no tile, so nothing is kept for it (unchanged)
        Reset(@{A: @"left", B: @"right"}, @[Stage(@[E(A, 1), E(B, 2)])]);
        [gSMFreeWindows addObject:F];
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(F, 3)])]); Tick();
        Check(FullScreens(@[F]), @"7. green on a No Fit window: noted as full screen");
        Stages(@[Stage(@[E(A, 4), E(B, 5), EF(F, 3)])]); Tick();
        Check(Tiles(@{A: @"left", B: @"right"}) && FullScreens(@[]) && !gKAsked.count, @"7. the desktop over it: the tiles as they were; it is not kept as full screen's (no tile left)");

        // 8. App Window Sizes' forget for Notes while it is full screen out of sight (its way back gone, its tile kept: a quit closes it up):
        //    the desktop keeps its tiles while Notes is full screen, as with Aerial (the forget takes only the way back)
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(C, 4)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil;   // (DMSMAppSizeForgetPlace's Fit part)
        Stages(@[Stage(@[E(A, 5), E(B, 6), EF(C, 4)])]); Tick();
        Check(Laid(@{A: @"left", B: @"topright"}) && Tiles(three), @"8. a size given to Notes while full screen, then the desktop: the tiles kept while Notes is full screen");

        // 9. (G2, KT's decision c) Two tiles; green on Notes; a size given to it while full screen (the forget: its way back and its place before
        //    full screen gone, its tile kept); our green light's way back joins it as a new window at its new size, free (DMSMToggleZoom ->
        //    DMSMJoinAttributesOn): its tile is given up at once, Settings fills; its later quit changes nothing more
        NSDictionary *fullAttrs = @{@"full": @YES};
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil;   // (DMSMAppSizeForgetPlace's Fit part)
        Tick();   // (Notes still full screen in front: noted again by the tick's own line)
        Clear();
        KJoinFreeLines(C, fullAttrs, YES);
        Stages(@[Stage(@[E(A, 1), E(C, 4)])]); Tick();
        Check(Tiles(@{A: @"fill"}) && Laid(@{A: @"fill"}) && gKApplied.count == 1 && [gSMFreeWindows containsObject:C] && FullScreens(@[]) && !gSMFitSlotsBeforeFull
              && Marked(@"sm-fit-back-free-closes-up") && Logged(@"back from full screen as a free window -- its tile is not taken back; the 1 window(s) left close up"),
              @"9. two tiles, Notes back from full screen as a free window: Settings fills at once");
        Clear(); Stages(@[Stage(@[E(A, 1)])]); Tick();
        Check(!gKApplied.count && Tiles(@{A: @"fill"}) && Logged(@"closed -- forgotten") && !Logged(@"close up"), @"9. ... then Notes quits: nothing more (Settings stays filling)");
        // ... three tiles: the two left close it up, each keeping its place (Fit's look tiled them again so before G2 too)
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(C, 4)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil;
        Clear();
        KJoinFreeLines(C, fullAttrs, YES);
        Stages(@[Stage(@[E(A, 1), E(B, 2), E(C, 5)])]); Tick();
        Check(Tiles(@{A: @"left", B: @"right"}) && Laid(@{A: @"left", B: @"right"}) && gKApplied.count == 1 && !gKAsked.count, @"9. three tiles, Notes back free: Settings keeps its half, Safari takes the right half");
        Clear(); Stages(@[Stage(@[E(A, 1), E(B, 2)])]); Tick();
        Check(!gKApplied.count && Tiles(@{A: @"left", B: @"right"}), @"9. ... then Notes quits: nothing more");
        // ... its Dock icon instead: Notes full screen in a stage of its own (Home, then the desktop), joining the desktop as a window, free
        //    (DMSMAddToStage -> DMSMJoinAttributesOn): the same
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil;
        Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(C, 3)])]); Tick();
        Check(Tiles(@{A: @"left", C: @"right"}), @"9. Notes full screen in a stage of its own after the forget: Settings keeps its half while it is (G1)");
        Clear();
        KJoinFreeLines(C, fullAttrs, YES);
        Stages(@[Stage(@[E(A, 4), E(C, 5)])]); Tick();
        Check(Tiles(@{A: @"fill"}) && Laid(@{A: @"fill"}) && gKApplied.count == 1, @"9. from its Dock icon instead (Notes full screen in a stage of its own, joining the desktop free): Settings fills at once");
        // ... the entry removed instead (Window Size, Open at Fill off): it joins as a window Fit tiles -- not free, no close-up (case 10: as a new window)
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil;
        Clear();
        KJoinFreeLines(C, fullAttrs, NO);
        Stages(@[Stage(@[E(A, 1), E(C, 4)])]); Tick();
        Check(gSMFitSlots.count == 2 && gSMFitSlots[A] && gSMFitSlots[C] && ![gSMFreeWindows containsObject:C] && !Marked(@"sm-fit-back-free-closes-up") && !Logged(@"as a free window") && !Logged(@"fills"),
              @"9. the entry removed instead: Notes back as a window Fit tiles, tiled with Settings, no close-up first");
        // ... a tiled window joining free that was not full screen (its own attributes a size Stage Manager works out: fresh): not a way back from
        //     full screen, its tile not touched here
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Clear();
        KJoinFreeLines(C, @{@"full": @NO}, YES);
        Check(Tiles(@{A: @"left", C: @"right"}) && !gSMFitLookAgain && !Marked(@"sm-fit-back-free-closes-up"), @"9. a tiled window joining free that was not full screen: no tile given up by the join");
        // ... another window joining free while Notes is full screen (Maps at its own size, a new window): Notes keeps its tile and way back
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        Clear();
        KJoinFreeLines(D, nil, YES);
        Check(Tiles(@{A: @"left", C: @"right"}) && FullScreens(@[C]) && !Marked(@"sm-fit-back-free-closes-up"), @"9. another app's new window joining free meanwhile: Notes keeps its tile and its way back");

        // 10. (the review of G1-G2, finding 1) Two tiles, Settings left, Notes right; green on Notes; its entry removed while it is full screen (the
        //     forget: its way back and its place before full screen gone, its tile kept for a quit); the tick notes it again while it is in front; our
        //     green light's way back joins it as a window Fit tiles (Window Size, Open at Fill off). A new window: its old tile no way back -- it takes
        //     the first tile, Settings keeps its place as far as it can (FitPlan.h): Notes left, Settings right, as Aerial, Zetsu and MilkyWay4 tile it
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil;   // (DMSMAppSizeForgetPlace's Fit part)
        Tick();   // (Notes still full screen in front: noted again by the tick's own line)
        Check(FullScreens(@[C]) && gSMFitSlotsBeforeFull[C], @"10. (the forget's way back noted again by the tick while Notes is in front, as the review read it)");
        Clear();
        KJoinFreeLines(C, fullAttrs, NO);
        Check(Tiles(@{A: @"left"}) && FullScreens(@[]) && !gSMFitSlotsBeforeFull && !gSMFitLookAgain && !gKApplied.count && Marked(@"sm-fit-back-new-window")
              && Logged(@"back from full screen with no place of its own -- a new window, its tile from before is not taken back; the 1 tiled window(s) keep theirs"),
              @"10. two tiles, Notes back as a window Fit tiles: its tile and way back go, Settings keeps its half (no close-up)");
        Stages(@[Stage(@[E(A, 1), E(C, 4)])]); Tick();
        Check(Tiles(@{C: @"left", A: @"right"}) && Laid(@{C: @"left", A: @"right"}) && gKApplied.count == 1 && !gKAsked.count && !Logged(@"its tile again") && !Logged(@"back from full screen --")
              && !Logged(@"arrangement from before"), @"10. ... Fit's look tiles it as a new window: Notes the left half, Settings the right one (as the other engines)");
        Clear(); Stages(@[Stage(@[E(A, 1)])]); Tick();
        Check(Tiles(@{A: @"fill"}) && Laid(@{A: @"fill"}), @"10. ... then Notes quits: a tiled window closing, Settings fills (as the other engines)");
        // ... Notes had the left half: the same halves
        Reset(@{C: @"left", A: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil; Tick();
        Clear();
        KJoinFreeLines(C, fullAttrs, NO);
        Stages(@[Stage(@[E(A, 1), E(C, 4)])]); Tick();
        Check(Tiles(@{C: @"left", A: @"right"}) && !gKAsked.count, @"10. Notes had the left half: the left half again, Settings the right one");
        // ... three tiles, Notes in the bottom right quarter: Notes the left half, Safari keeps the top right, Settings the bottom right (as the others)
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(C, 4)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil; Tick();
        Clear();
        KJoinFreeLines(C, fullAttrs, NO);
        Check(Tiles(@{A: @"left", B: @"topright"}) && FullScreens(@[]), @"10. three tiles, Notes back as a window Fit tiles: its tile goes, the two keep theirs");
        Stages(@[Stage(@[E(A, 1), E(B, 2), E(C, 5)])]); Tick();
        Check(Tiles(@{C: @"left", B: @"topright", A: @"bottomright"}) && Laid(@{C: @"left", B: @"topright", A: @"bottomright"}) && !gKAsked.count,
              @"10. ... three tiles: Notes the left half, Safari the top right, Settings the bottom right, no question (as the other engines)");
        // ... its Dock icon instead: Notes full screen in a stage of its own (G1 keeps the half), joining the desktop as a window Fit tiles
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        [gSMFitWentFull removeObject:C]; gSMFitSlotsBeforeFull = nil;
        Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(C, 3)])]); Tick();
        Clear();
        KJoinFreeLines(C, fullAttrs, NO);
        Stages(@[Stage(@[E(A, 4), E(C, 5)])]); Tick();
        Check(Tiles(@{C: @"left", A: @"right"}) && Laid(@{C: @"left", A: @"right"}) && !gKAsked.count, @"10. from its Dock icon instead (a stage of its own): Notes the left half, Settings the right one");
        // ... the tile Notes left taken meanwhile (Maps opened on the desktop: tiled with Settings), and the arrangement Notes left still naming it
        //     when Notes joins as a window Fit tiles with no place of its own: that way back goes too, so it is a new window -- with two halves there,
        //     the third window's question, as DMCascadeStage asks on the other engines. (After the forget's own Fit part the arrangement names it no
        //     more, and the tick notes Notes again as full screen while it is in front: then it still comes back "from full screen", with no question
        //     -- the release record's KT item with the review's finding 4, a window that took Notes' tile.)
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(C, 3)])]); Tick();
        Stages(@[Stage(@[E(A, 4), E(D, 5)]), Stage(@[EF(C, 3)])]); Tick();
        Check(gSMFitSlots.count == 2 && gSMFitSlots[A] && gSMFitSlots[D] && gSMFitSlotsBeforeFull[C], @"10. (Maps took Notes' tile while it is away; the arrangement Notes left still names it)");
        Clear();
        KJoinFreeLines(C, fullAttrs, NO);
        Check(FullScreens(@[]) && !gSMFitSlotsBeforeFull && gSMFitSlots.count == 2, @"10. ... Notes back as a window Fit tiles, the arrangement it left naming it: that way back goes too, the two tiles stay");
        Stages(@[Stage(@[E(A, 4), E(D, 5), E(C, 6)])]); Tick();
        Check(gKAsked.count == 1 && [gKAsked.firstObject isEqualToString:C], @"10. ... Notes then a new window next to two halves: asked where it goes, as on the other engines");
        // ... unchanged: a tiled window joining (not free) that was not full screen -- not a way back from full screen, its tile not touched
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Clear();
        KJoinFreeLines(C, @{@"full": @NO}, NO);
        Check(Tiles(@{A: @"left", C: @"right"}) && !Marked(@"sm-fit-back-new-window") && gSMFitByDesk.count, @"10. a tiled window joining that was not full screen: its tile and the arrangements remembered not touched");
        // ... unchanged: a window that left no tile (opened full screen, never tiled) joining as a window: nothing of Fit's changes for it
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), E(C, 2), EF(D, 3)])]); Tick();
        Clear();
        KJoinFreeLines(D, fullAttrs, NO);
        Check(Tiles(@{A: @"left", C: @"right"}) && FullScreens(@[D]) && !Marked(@"sm-fit-back-new-window"), @"10. a window that left no tile, back from full screen: nothing changes for it here (as before)");
        // ... unchanged: another app's window joining while Notes is full screen: Notes keeps its tile and its way back
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        Clear();
        KJoinFreeLines(D, nil, NO);
        Check(Tiles(@{A: @"left", C: @"right"}) && FullScreens(@[C]) && !Marked(@"sm-fit-back-new-window"), @"10. another app's new window joining meanwhile: Notes keeps its tile and its way back");

        // 11. (1.8.8 H3, the iPad 2's row C14 of p03) Three tiles, Settings left, Safari top right, Clock bottom right; Clock's green; Home (Home
        //     Minimizes Windows: all three minimized); Clock from the Home Screen's Dock (full screen); Safari's Dock icon (the desktop: Safari in its
        //     tile, Clock full screen out of sight, Settings minimized); Clock's Dock icon (full screen again, in the desktop's stage); Clock's green:
        //     back in its tile while Settings stays minimized. Fit's minimized rule keeps the tiles and returns before the tick's last path, which
        //     ends a way back from full screen: Clock stayed full screen's ("its tile again" only once Settings came back from the Dock)
        NSDictionary *c14 = @{A: @"left", B: @"topright", F: @"bottomright"};
        Reset(c14, @[Stage(@[E(A, 1), E(B, 2), E(F, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(F, 4)])]); Tick();   // (Clock's green)
        [gKMin addObjectsFromArray:@[A, B, F]]; Stages(@[Stage(@[]), Stage(@[E(A, 1)]), Stage(@[E(B, 2)]), Stage(@[EF(F, 4)])]); Tick();   // (Home: the Home Screen)
        [gKMin removeObject:F]; Stages(@[Stage(@[EF(F, 5)]), Stage(@[E(A, 1)]), Stage(@[E(B, 2)])]); Tick();   // (Clock from the Home Screen's Dock)
        [gKMin removeObject:B]; Stages(@[Stage(@[E(B, 6)]), Stage(@[EF(F, 5)]), Stage(@[E(A, 1)])]); Clear(); Tick();   // (Safari's Dock icon)
        Check(Laid(@{B: @"topright"}) && Tiles(c14) && FullScreens(@[F]) && Logged(@"1 window(s) full screen out of sight (1 minimized besides) keep their tiles for their way back -- the 1 on screen keep theirs"),
              @"11. C14: Safari from the Dock, Clock full screen out of sight, Settings minimized: the tiles kept, Clock's way back kept (G1, unchanged)");
        Stages(@[Stage(@[E(B, 6), EF(F, 7)]), Stage(@[E(A, 1)])]); Tick();   // (Clock's Dock icon: full screen, in the desktop's stage)
        Stages(@[Stage(@[E(B, 6), E(F, 8)]), Stage(@[E(A, 1)])]); Clear(); Tick();   // (Clock's green)
        Check(Laid(@{B: @"topright", F: @"bottomright"}) && Tiles(c14) && !gKAsked.count && Logged(@"1 minimized window(s) keep their tiles -- the 2 on screen keep theirs"),
              @"11. C14: Clock back by its green, Settings still minimized: Clock in its tile, Safari in its own, Settings' kept (unchanged)");
        Check(FullScreens(@[]) && !gSMFitSlotsBeforeFull && Marked(@"sm-fit-back-in-kept-tile") && Logged(@"back from full screen -- its tile again"),
              @"11. C14: ... and Clock is full screen's no more: its way back used there, \"its tile again\" now (smfit: full screen none, arrangement left none)");
        [gKMin removeObject:A]; Stages(@[Stage(@[E(B, 6), E(F, 8), E(A, 9)])]); Clear(); Tick();   // (Settings from the Dock)
        Check(Laid(c14) && Tiles(c14) && !gKAsked.count && FullScreens(@[]) && !Logged(@"back from full screen"),
              @"11. C14: Settings back from the Dock: the three tiles as they were, nothing back from full screen any more");
        // ... the same with Settings minimized by its yellow light (no Home), then what the stale way back did later: Safari quits (Settings and
        //     Clock close its tile up), Clock's green again (the arrangement it now leaves must be noted: it was not, Clock being full screen's
        //     still), Maps and Tips open over it and take the tiles, a turn (Clock's way back kept only by that arrangement: G1), Clock back: no
        //     third window's question (KT's decision b; before, it was asked)
        Reset(c14, @[Stage(@[E(A, 1), E(B, 2), E(F, 3)])]);
        [gKMin addObject:A]; Stages(@[Stage(@[E(B, 2), E(F, 3)]), Stage(@[E(A, 1)])]); Tick();   // (Settings' yellow)
        Stages(@[Stage(@[E(B, 2), EF(F, 4)]), Stage(@[E(A, 1)])]); Tick();   // (Clock's green)
        Stages(@[Stage(@[E(B, 2), E(F, 5)]), Stage(@[E(A, 1)])]); Clear(); Tick();   // (and back)
        Check(Tiles(c14) && Laid(@{B: @"topright", F: @"bottomright"}) && FullScreens(@[]) && !gSMFitSlotsBeforeFull && Logged(@"back from full screen -- its tile again"),
              @"11. Settings minimized by its yellow light, Clock full screen and back: in its tile, its way back used at once");
        Stages(@[Stage(@[E(F, 5)]), Stage(@[E(A, 1)])]); Tick();   // (Safari quits)
        Check(gSMFitSlots.count == 2 && gSMFitSlots[A] && gSMFitSlots[F] && FullScreens(@[]), @"11. ... Safari quits: Settings (minimized) and Clock close its tile up");
        Stages(@[Stage(@[EF(F, 6)]), Stage(@[E(A, 1)])]); Tick();   // (Clock's green again)
        Check(FullScreens(@[F]) && gSMFitSlotsBeforeFull.count == 2 && [gSMFitSlotsBeforeFull isEqualToDictionary:gSMFitSlots], @"11. ... Clock full screen again: the arrangement it now leaves is noted");
        Stages(@[Stage(@[EF(F, 6), E(D, 7)]), Stage(@[E(A, 1)])]); Tick();
        Stages(@[Stage(@[EF(F, 6), E(D, 7), E(T, 8)]), Stage(@[E(A, 1)])]); Tick();   // (Maps, then Tips, over it)
        Turn(); Tick();
        Check(gSMFitSlots.count == 2 && gSMFitSlots[D] && gSMFitSlots[T] && FullScreens(@[F]), @"11. ... Maps and Tips over it take the tiles, a turn: Clock keeps its way back (G1)");
        Stages(@[Stage(@[E(F, 9), E(D, 7), E(T, 8)]), Stage(@[E(A, 1)])]); Clear(); Tick();   // (Clock's green: back)
        Check(!gKAsked.count && FullScreens(@[]) && Logged(@"back from full screen") && gSMFitSlots.count == 3, @"11. ... Clock back: tiled with the two, no third window's question (decision b)");
        // ... the one-window rule's way: two tiles, Notes' green, Settings quits while Notes is full screen (Notes' tile fills), Notes back by its
        //     green alone, filling: its way back used there too; then the same later steps
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        Stages(@[Stage(@[EF(C, 3)])]); Tick();   // (Settings quits)
        Stages(@[Stage(@[E(C, 4)])]); Clear(); Tick();   // (Notes' green)
        Check(Tiles(@{C: @"fill"}) && Laid(@{C: @"fill"}) && FullScreens(@[]) && !gSMFitSlotsBeforeFull && Logged(@"back from full screen -- its tile again"),
              @"11. Settings quit while Notes was full screen, Notes back alone: it fills, its way back used");
        Stages(@[Stage(@[EF(C, 5)])]); Tick();
        Check(FullScreens(@[C]) && [gSMFitSlotsBeforeFull isEqualToDictionary:@{C: @"fill"}], @"11. ... Notes full screen again: the arrangement it now leaves is noted");
        Stages(@[Stage(@[EF(C, 5), E(D, 6)])]); Tick();
        Stages(@[Stage(@[EF(C, 5), E(D, 6), E(T, 7)])]); Tick();
        Turn(); Tick();
        Check(FullScreens(@[C]), @"11. ... Maps and Tips over it take the tiles, a turn: Notes keeps its way back");
        Stages(@[Stage(@[E(C, 8), E(D, 6), E(T, 7)])]); Clear(); Tick();
        Check(!gKAsked.count && FullScreens(@[]) && gSMFitSlots.count == 3, @"11. ... Notes back: tiled with the two, no third window's question");
        // ... another tiled window still full screen out of sight when one comes back through the minimized rule: the arrangement left stays (it
        //     names that window: its way back, G1), so with its tile taken later that window still comes back from full screen
        Reset(three, @[Stage(@[E(A, 1), E(B, 2), E(C, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(C, 4)])]); Tick();   // (Notes' green)
        Stages(@[Stage(@[E(A, 5), E(B, 6), EF(C, 4)])]); Tick();   // (Settings and Safari over it)
        Stages(@[Stage(@[E(A, 5), EF(B, 7), EF(C, 4)])]); Tick();   // (Safari's green)
        Stages(@[Stage(@[E(A, 8), EF(B, 7), EF(C, 4)])]); Tick();   // (Settings in front)
        Check(Laid(@{A: @"left"}) && Tiles(three) && FullScreens(@[B, C]), @"11. Notes and Safari full screen out of sight, Settings on screen: the tiles kept (G1, unchanged)");
        Stages(@[Stage(@[E(A, 8), EF(B, 7), E(C, 9)])]); Clear(); Tick();   // (Notes' green: back)
        Check(Laid(@{A: @"left", C: @"bottomright"}) && Tiles(three) && FullScreens(@[B]) && gSMFitSlotsBeforeFull[B] && Logged(@"back from full screen -- its tile again"),
              @"11. ... Notes back in its tile: its way back used; Safari's kept, with the arrangement it left");
        Stages(@[Stage(@[E(A, 8), EF(B, 7), E(C, 9), E(D, 10)])]); Tick();   // (Maps opens: the three on screen tiled, Safari's tile taken)
        Turn(); Tick();
        Check(FullScreens(@[B]) && !gSMFitSlots[B], @"11. ... Maps takes the tiles, a turn: Safari keeps its way back (G1)");
        Stages(@[Stage(@[E(A, 8), E(B, 11), E(C, 9), E(D, 10)])]); Clear(); Tick();   // (Safari's green: back)
        Check(!gKAsked.count && FullScreens(@[]) && Logged(@"back from full screen"), @"11. ... Safari back: back from full screen, no question");
        // ... unchanged: a window back on screen alone whose tile was taken while it was away keeps its way back for the desktop (G1: it takes part
        //     with the tile it left when it joins); only a window back in a tile Fit kept for it is done with it there
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(C, 3)])]); Tick();
        Stages(@[Stage(@[E(A, 4), E(D, 5)]), Stage(@[EF(C, 3)])]); Tick();   // (Maps opens on the desktop: tiled with Settings, Notes' tile taken)
        Stages(@[Stage(@[E(C, 6)]), Stage(@[E(A, 4), E(D, 5)])]); Clear(); Tick();   // (Notes a window again, alone in its own stage on screen)
        Check(FullScreens(@[C]) && !gSMFitSlots[C] && !Logged(@"back from full screen"), @"11. Notes back alone in its own stage, its tile taken meanwhile: its way back kept for the desktop (unchanged)");
        Stages(@[Stage(@[E(A, 4), E(D, 5), E(C, 7)])]); Tick();
        Check(!gKAsked.count && FullScreens(@[]) && Logged(@"back from full screen") && gSMFitSlots.count == 3, @"11. ... Notes joins the desktop: back from full screen, tiled with the two, no question (unchanged)");
        // ... (the H-round review of H3, finding 1) the same window back alone in a stage of its own with its tile kept (L-7): two halves, Notes'
        //     green, the desktop tapped in the strip, Notes' stage tapped (full screen in front), its green -- Notes alone on screen, Settings on the
        //     desktop's stage and not minimized. The one-window rule lays nothing out then, so Notes keeps its way back and the arrangement it left
        //     (no "its tile again" for a window in no tile) until it joins the desktop: its tile again there, no question
        NSDictionary *halves = @{A: @"left", C: @"right"};
        Reset(halves, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();   // (Notes' green)
        Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(C, 3)])]); Tick();   // (the desktop tapped in the strip: Notes full screen in its own stage)
        Stages(@[Stage(@[EF(C, 5)]), Stage(@[E(A, 4)])]); Tick();   // (Notes' stage tapped: full screen in front)
        Stages(@[Stage(@[E(C, 6)]), Stage(@[E(A, 4)])]); Clear(); Tick();   // (its green: Notes alone in its own stage, a window)
        Check(!gKApplied.count && Tiles(halves) && FullScreens(@[C]) && [gSMFitSlotsBeforeFull isEqualToDictionary:halves] && !Marked(@"sm-fit-back-in-kept-tile") && !Logged(@"back from full screen"),
              @"11. L-7: Notes back alone in its own stage, its tile kept, Settings on the desktop: nothing laid out, Notes keeps its way back (no \"its tile again\")");
        Stages(@[Stage(@[E(A, 7)]), Stage(@[E(C, 6)])]); Clear(); Tick();   // (the desktop in front again)
        Check(FullScreens(@[C]) && [gSMFitSlotsBeforeFull isEqualToDictionary:halves] && !Logged(@"back from full screen"), @"11. L-7: ... the desktop in front again: Notes still keeps its way back");
        Stages(@[Stage(@[E(A, 7), E(C, 8)])]); Clear(); Tick();   // (Notes joins the desktop)
        Check(Laid(halves) && Tiles(halves) && !gKAsked.count && FullScreens(@[]) && !gSMFitSlotsBeforeFull && Logged(@"back from full screen -- its tile again"),
              @"11. L-7: ... Notes joins the desktop: \"its tile again\" there, the two halves, no question");
#ifdef K_HAS_BACK_IN_TILE
        // ... DMSMFitBackInTile itself, given a window with no tile kept (its tile taken while it was away). Both calls pass only windows with a
        //     kept tile (the minimized rule's windows all have theirs, the one-window rule's window fills), so no look reaches this now: its way
        //     back and the arrangement it left stay (G1: it takes part with the tile it left when it joins the desktop), nothing logged
        Reset(halves, @[Stage(@[E(A, 1), E(C, 2)])]);
        gSMFitWentFull = [NSMutableSet setWithObject:D]; gSMFitSlotsBeforeFull = @{A: @"left", D: @"right"}; Clear();
        DMSMFitBackInTile(@[D]);
        Check(FullScreens(@[D]) && [gSMFitSlotsBeforeFull isEqualToDictionary:@{A: @"left", D: @"right"}] && !Marked(@"sm-fit-back-in-kept-tile") && !gKLog.count,
              @"11. DMSMFitBackInTile given a window with no tile kept: its way back and the arrangement it left kept, nothing logged");
#endif
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
