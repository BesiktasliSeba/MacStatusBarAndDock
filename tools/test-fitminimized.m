// test-fitminimized.m -- Mac test of KT's decision A (19 Nov, 1.8.8 H2): minimized tiled windows keep their tiles on every engine, here
// Aerial, Zetsu and MilkyWay4 (our Stage Manager engine: test-fitminimized-sm.m). Rows Z8, Z11 and Z11c of p03 (iPad 2, Zetsu), played as the
// device ran them: Settings in the left half, Clock in the right one; Clock's green; Home with Home Minimizes Windows (Settings minimized); Clock's
// Dock icon (a new window: each engine's green left none); Settings' Dock icon. Before, a window that opened while the other tiled windows were
// only minimized took them out of the arrangement (DMCascadeStage's Fit part), the close-up of a window back free skipped them (G2's
// DMFitFullScreenTileGoes), and nothing tiled at a minimized window's return: Settings came back at its old half next to Clock, in no tile (Z11c,
// Z11), or at its old half after Clock's free return (Z8). Now:
//  - a window that opens while every window of the arrangement is minimized opens on its own, at its own size (the owner's old bug stays fixed:
//    not squeezed into a half), and the arrangement stays; marked, it joins the tiles when one of them is shown again (DMFitShownAgain);
//  - a window that opens next to tiled windows on screen and minimized ones takes the first tile, the others keeping theirs (no question while one
//    of the two halves is minimized, as the question before the launch counts them);
//  - with no window of the arrangement on screen, G2's close-up and the closure watcher close the tile up among the minimized windows (Z8:
//    Settings' tile becomes Fill while it is minimized); with one on screen, as before (O1);
//  - a window back from full screen by the green light's way back rejoins next to a minimized tile;
//  - a minimized window is placed in its tile while out of sight (DMApplyGroupSlots, DMFitPlaceAway), not slid.
// The H2-H5 review's fixes (20 Nov): R1 -- the full-screen record's app back by its Dock icon next to a window that opened on its own is a window
// of the arrangement, so the minimized tiles stay and it joins them (finding 1); R2 the close-ups with two or more windows on screen (finding 2);
// R3 the Mac Switcher (finding 3); R5 the green light's way back takes the windows that opened on their own into the tiles, and Aerial's with no
// entrance cover is placed as Zetsu's and MilkyWay4's (finding 5); R6 a minimized window put in its tile notes the tile's layout (finding 6).
// The real code is cut out of statusbar/StatusBar.x by test-fitminimized.sh into fm-real.inc: the closure check, the full-screen record, the free
// mark, DMApplyGroupSlots, DMCascadeStage's Fit part as written (KCascadeFitPart), DMFitKeepsTile and DMFitShownAgain (when the file has them).
// A Home press with Home Minimizes Windows is DMMinimizeAllWindows (every window on screen minimized: hidden, or Zetsu's pill), a Dock icon of a
// minimized window DMSurfaceWindowForApp (DMFitShownAgain while it is still minimized, then shown again): their calls are checked by the .sh.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../statusbar/FitPlan.h"
#include "../statusbar/TurnPlace.h"   // (the layouts a window is noted in: DMStageSetLayoutNote, the H2-H5 review fix 6)
#include "../common/AppWindowSize.h"

static NSMutableArray<NSString *> *gKLog, *gKMarks, *gKSlid;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
#define DM_FEATURE_MARK(name) [gKMarks addObject:@name]
#define DM_PERF(label, stmt) do { stmt; } while (0)
static NSMutableArray<UIView *> *gKStages;
static char kKBundleKey, kKMinKey;
static NSString *DMStageBundle(UIView *stage) { return objc_getAssociatedObject(stage, &kKBundleKey); }
static BOOL DMStageMinimized(UIView *stage) { return [objc_getAssociatedObject(stage, &kKMinKey) boolValue]; }   // (ours: hidden; Zetsu's own pill: not hidden)
static NSArray<UIView *> *DMAerialStages(void) { return [gKStages copy]; }   // (back to front)
static UIView *DMStageForBundle(NSString *bundleID) { for (UIView *s in gKStages) if ([DMStageBundle(s) isEqualToString:bundleID]) return s; return nil; }
static BOOL DMFitEnabled(void) { return YES; }
static void DMFitRepairOverlappingSlots(void) { }
BOOL DMSofaRelaunchKeepsFrame(NSString *bundleID) { return NO; }
BOOL DMA5ReopenKeepsFrame(NSString *bundleID) { return NO; }
static void DMApplyGroupSlots(UIView *fresh);
static CGRect DMSlotFrame(NSString *bundleID);
static void DMTitleRecordEngineTo(UIView *v, CGRect to) { }
static void DMAutoHideBeforeRetile(void) { }
static void DMAutoHideAfterRetile(void) { }
static char kKIntentKey;
static void DMSetStageIntent(UIView *v, CGRect f) { objc_setAssociatedObject(v, &kKIntentKey, [NSValue valueWithCGRect:f], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void DMSetStageFrameSafe(UIView *s, CGRect f) { s.frame = f; }
static void DMAerial5SyncState(UIView *stage, CGRect frame) { }
static void DMAerialMoveStage(UIView *stage, CGRect target, void (^done)(void)) { [gKSlid addObject:DMStageBundle(stage) ?: @"?"]; stage.frame = target; }   // (a slide on screen)
static BOOL DMIsZetsuWindow(UIView *v) { return NO; }
static void DMZetsuMove(UIWindow *w, CGRect target, BOOL animated, void (^done)(void)) { [gKSlid addObject:DMStageBundle(w) ?: @"?"]; w.frame = target; }
static BOOL gPreferRememberedFrame = NO;
static NSMutableDictionary<NSString *, NSValue *> *gLastWindowFrames;
static NSMutableDictionary<NSString *, NSNumber *> *gKSizes;
static int DMAppSizeOf(NSString *b) { NSNumber *n = b ? gKSizes[b] : nil; return n ? n.intValue : MSBDAppSizeNone; }
static BOOL gNewWindowsFill = NO;
static BOOL DMTestFlag(const char *p) { return NO; }
static CGRect KTile(NSString *slot) {
    MSBDFitUnit u;
    if (!MSBDFitTileUnit(slot, &u)) return CGRectNull;
    return CGRectMake(u.x * 1024, 20 + u.y * 676, u.w * 1024, u.h * 676);
}
static NSString *DMSlotNameForFrame(CGRect f) { for (NSString *n in @[@"left", @"right", @"top", @"bottom", @"topleft", @"topright", @"bottomleft", @"bottomright"]) if (CGRectEqualToRect(KTile(n), f)) return n; return nil; }
static NSString *gPreSideBundle, *gPreSide; static CFTimeInterval gPreSideUntil;
static void DMApplySideChoice(UIView *stage, NSString *n, NSString *l, NSString *r, NSString *side) { }
static int gKAsked;
static void DMPromptForSide(UIView *stage, NSString *n, NSString *l, NSString *r) { gKAsked++; DMLog([NSString stringWithFormat:@"asked where %@ goes", n]); }
static SEL DMAerialSel(NSString *s) { return NSSelectorFromString(s); }
static void DMZetsuRaise(UIWindow *w) { }
enum { DMEngineAerial = 1, DMEngineMilkyWay = 2, DMEngineZetsu = 3 };
static int DMActiveEngine(void) { return DMEngineAerial; }
static void DMApplyWindowLevel(void) { }
static NSMutableDictionary *gSidePromptCtx;   // (the side question's context: none up)
static NSArray<UIView *> *DMAerialStagesAll(void);

#include "fm-real.inc"

#ifndef K_HAS_ASKED
static BOOL KCascadeAsked(UIView *stage, NSString *me, CGRect base) { return NO; }   // (the file before the H2-H5 review: the cascade's Fit part runs)
#endif
#ifndef K_HAS_H2
static const void *kStageFitAloneKey = &kStageFitAloneKey;   // (the file before H2: no mark, nothing at a return)
static void DMFitShownAgain(NSString *bundleID) { }
#endif
static CGRect DMSlotFrame(NSString *bundleID) { return gFitSlots[bundleID] ? KTile(gFitSlots[bundleID]) : CGRectNull; }
static NSArray<UIView *> *DMAerialStagesAll(void) { return [gKStages copy]; }   // (every desktop's: the one brought here is in it)

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Logged(NSString *part) { for (NSString *l in gKLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }
static NSString *Short(NSString *b) { return [b componentsSeparatedByString:@"."].lastObject; }
static NSString *State(void) {   // (fitcheck's view: the group with its tiles, the windows on screen not tiled)
    NSMutableArray *g = [NSMutableArray array];
    for (NSString *b in gFitGroup) [g addObject:[NSString stringWithFormat:@"%@=%@", Short(b), gFitSlots[b] ?: @"(null)"]];
    NSMutableArray *nt = [NSMutableArray array];
    for (UIView *s in gKStages) if (![gFitGroup containsObject:DMStageBundle(s)]) [nt addObject:[NSString stringWithFormat:@"%@%@", Short(DMStageBundle(s)), DMStageMinimized(s) ? @"(min)" : @""]];
    return [NSString stringWithFormat:@"group %lu: %@ | not tiled: %@", (unsigned long)gFitGroup.count, [g componentsJoinedByString:@" "], nt.count ? [nt componentsJoinedByString:@" "] : @"none"];
}

typedef enum { KAerial, KZetsu, KMilkyWay } KEngine;
static NSString *const kClock = @"com.apple.mobiletimer", *const kSettings = @"com.apple.Preferences", *const kMaps = @"com.apple.Maps", *const kSafari = @"com.apple.mobilesafari", *const kNotes = @"com.apple.mobilenotes";
static UIView *Window(NSString *b, CGRect f) { UIView *v = [[UIView alloc] initWithFrame:f]; objc_setAssociatedObject(v, &kKBundleKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC); [gKStages addObject:v]; return v; }
static void Gone(NSString *b) { UIView *s = DMStageForBundle(b); if (s) [gKStages removeObject:s]; }
static void Tick(void) { gFitClosureCheckDue = YES; DMWatchFitClosures(); }
static BOOL At(NSString *b, NSString *slot) { UIView *s = DMStageForBundle(b); return s && CGRectEqualToRect(s.frame, KTile(slot)); }
static BOOL Tiles(NSDictionary *want) { return gFitGroup.count == want.count && [[NSSet setWithArray:gFitGroup] isEqualToSet:[NSSet setWithArray:want.allKeys]] && [gFitSlots isEqualToDictionary:want]; }
static void Fresh(void) {
    gKLog = [NSMutableArray array]; gKMarks = [NSMutableArray array]; gKSlid = [NSMutableArray array]; gKStages = [NSMutableArray array]; gKAsked = 0; gFreeWindows = nil;
    gFSFitBundle = nil; gFSFitGroup = nil; gFSFitSlots = nil; gLastWindowFrames = [NSMutableDictionary dictionary]; gKSizes = [NSMutableDictionary dictionary];
    gFitGroup = nil; gFitSlots = nil;
}
// The windows in their tiles (Fit's group as the closure check last saw it)
static void Tiled(NSDictionary<NSString *, NSString *> *slots) {
    Fresh();
    gFitGroup = [NSMutableArray array];
    for (NSString *b in [slots.allKeys sortedArrayUsingSelector:@selector(compare:)]) { Window(b, KTile(slots[b])); [gFitGroup addObject:b]; }
    gFitSlots = [slots mutableCopy];
    DMFitWatchSync();
}
static void TwoTiles(void) { Tiled(@{kSettings: @"left", kClock: @"right"}); }
static void Unslid(void) { [gKSlid removeAllObjects]; }
// Each engine's green, as test-fitgreen.m plays it (the record first, the window on its way out, then gone)
static void Green(KEngine e, NSString *b) {
    DMRememberFitForFullScreen(b);
    UIView *s = DMStageForBundle(b);
    if (e == KAerial) { objc_setAssociatedObject(s, kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(s, kStageGoingFullKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    else if (e == KZetsu) objc_setAssociatedObject(s, kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Tick(); Gone(b); Tick(); Tick();
}
// A minimize (the yellow light; Home with Home Minimizes Windows: DMMinimizeAllWindows, every window on screen): ours hide the window (Aerial's and
// Zetsu's DMMinimizeStage, MilkyWay4's DMMinimizeWindow); pill: Zetsu's own title-bar pill instead (minimized, not hidden)
static BOOL gKPill = NO;
static void Minimize(NSString *b) { UIView *s = DMStageForBundle(b); objc_setAssociatedObject(s, &kKMinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); if (!gKPill) s.hidden = YES; Tick(); }
static void Home(void) { for (UIView *s in [gKStages copy]) if (!s.hidden && !DMStageMinimized(s)) { objc_setAssociatedObject(s, &kKMinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); if (!gKPill) s.hidden = YES; } Tick(); }
// App Window Sizes in Settings while the app is full screen: DMAppSizeForgetPlace (its Fit call as written; its place forgotten)
static void SizeWhileFull(NSString *b, int size) { gKSizes[b] = @(size); [gLastWindowFrames removeObjectForKey:b]; KAppSizeForgetFit(b); }
// A Dock icon (Open Apps as Windows on) of an app with no window: a new one -> DMCascadeStage: the record line, then the free mark (the app's own
// size, no place of its own) or the Fit part as written. own: the engine reopened it at its own last place (Zetsu's DMMarkOwnPlace, Aerial's
// gLastWindowFrames)
static UIView *DockOpensNew(NSString *b, BOOL own, CGRect f) {
    UIView *st = Window(b, f);
    NSMutableArray *others = [NSMutableArray array];
    for (UIView *s in gKStages) if (s != st && !s.hidden && !DMStageMinimized(s)) [others addObject:s];
    KCascadeFitLines(b, YES, DMAppSizeOf(b), own, NO);
    if (MSBDOpensFree(DMAppSizeOf(b), gNewWindowsFill, own, NO)) DMMarkFreeWindow(b);   // (ownSizeOpening: regularWindow, then the free mark)
    else if (![gFreeWindows containsObject:b]) KCascadeFitPart(st, b, others, f);
    Tick();
    return st;
}
// A minimized window's Dock icon: DMSurfaceWindowForApp -- Fit's call while it is still minimized, then the window shown again where it was put
static void DockRestores(NSString *b) {
    UIView *s = DMStageForBundle(b);
    if (DMStageMinimized(s)) DMFitShownAgain(b);
    objc_setAssociatedObject(s, &kKMinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); s.hidden = NO;
    Tick();
}
// The status bar's green light on the full-screen app (DMWindowLayout's way back to the place it had): the window opens at its place through the
// cascade (an own place: DMCascadeStage's Fit part), then DMFitRejoinAfterFullScreen
// -- Zetsu's and MilkyWay4's adoption mark it placed (DMMarkStagePlaced: the cascade skips it), and so does Aerial's entrance with its cover; with
// no cover Aerial's window meets the cascade, which places it there since the H2-H5 review's fix 5 (KCascadeAsked, as written; the file before:
// its Fit part ran) -- then the way back gives it its tile (DMFitRejoinAfterFullScreen)
static void GreenBack(KEngine e, NSString *b, CGRect place) {
    gLastWindowFrames[b] = [NSValue valueWithCGRect:place];
    UIView *st = Window(b, place);
    if (e == KAerial) {   // (no entrance cover; DMWindowLayout's open block asked for its place)
        gA5EntranceBundle = [b copy]; gA5EntranceFrame = place; gA5EntranceAt = CACurrentMediaTime();
        if (!KCascadeAsked(st, b, place)) {
            NSMutableArray *others = [NSMutableArray array];
            for (UIView *s in gKStages) if (s != st && !s.hidden && !DMStageMinimized(s)) [others addObject:s];
            KCascadeFitPart(st, b, others, place);
        }
        gA5EntranceBundle = nil;
    } else DMMarkStagePlaced(st, place);
    DMFitRejoinAfterFullScreen(b);
    Tick();
}

// The Mac Switcher (MacSwitcher.h as written): a window brought here from desktop 2 (DMMSWBringHere: DMMSWFitBringHere, then the tiles applied
// with it in front); a tiled window dragged to desktop 2 (DMMSWFitMove; its stage goes from this desktop)
static BOOL gKBringAsked;
static UIView *KBring(NSString *b, CGRect f) {
    UIView *st = Window(b, f);
    gMSWFit = [@{@"2": @{@"group": @[b], @"slots": @{b: @"fill"}, @"free": @[]}} mutableCopy];
    NSString *l = nil, *r = nil;
    BOOL tiled = DMMSWFitBringHere(b, 2, YES, &l, &r);
    gKBringAsked = l != nil || r != nil;
    if (tiled) DMApplyGroupSlots(st);
    Tick();
    return st;
}
static void KMoveAway(NSString *b) { gMSWFit = [NSMutableDictionary dictionary]; DMMSWFitMove(b, 2); Gone(b); Tick(); }

int main(void) {
    @autoreleasepool {
        NSArray *names = @[@"Aerial", @"Zetsu", @"MilkyWay4"];
        NSMutableDictionary<NSString *, NSMutableArray *> *seen = [NSMutableDictionary dictionary];
        void (^note)(NSString *, NSString *) = ^(NSString *row, NSString *s) { if (!seen[row]) seen[row] = [NSMutableArray array]; [seen[row] addObject:s]; printf("      %s\n", s.UTF8String); };
        for (int e = KAerial; e <= KMilkyWay; e++) {
            NSString *en = names[e];
            gKPill = NO;
            // Z11c: no size change. Green on Clock, Home, Clock's Dock icon (back at its own place), Settings' Dock icon
            TwoTiles();
            Green(e, kClock);
            Home();
            UIView *clock = DockOpensNew(kClock, YES, KTile(@"right"));
            note(@"Z11c-a", [NSString stringWithFormat:@"%@ Z11c after Clock's Dock icon: %@", en, State()]);
            Check(Tiles(@{kSettings: @"left"}) && At(kClock, @"right") && !gKAsked, [NSString stringWithFormat:@"%@: Z11c Clock back by its Dock icon while Settings is minimized: Clock opens on its own at its place, Settings keeps its tile", en]);
            Check([objc_getAssociatedObject(clock, kStageFitAloneKey) boolValue] && Logged(@"opens on its own: the 1 tiled window(s) are minimized and keep their tiles"), [NSString stringWithFormat:@"%@: Z11c ... marked as opened on its own (it joins the tiles at a return), the log says why", en]);
            Unslid();
            DockRestores(kSettings);
            note(@"Z11c-b", [NSString stringWithFormat:@"%@ Z11c after Settings' Dock icon: %@", en, State()]);
            Check(Tiles(@{kClock: @"left", kSettings: @"right"}) && At(kClock, @"left") && At(kSettings, @"right") && !gKAsked, [NSString stringWithFormat:@"%@: Z11c ... Settings back: both tiled, Clock joins as a new window -- the left half, Settings the right one (C12's halves on Stage Manager)", en]);
            Check([gKSlid isEqualToArray:@[kClock]] && Logged(@"shown again (it was minimized): com.apple.mobiletimer join(s) the tiles"), [NSString stringWithFormat:@"%@: Z11c ... Clock slides into its tile, Settings is put in its tile before it is shown (no slide), the log says why", en]);

            // Z11c counter, no Home (Settings on screen): Clock's Dock icon joins as a new window (D13 item 4: Stage Manager gives it its old tile)
            TwoTiles();
            Green(e, kClock);
            DockOpensNew(kClock, YES, KTile(@"right"));
            Check(Tiles(@{kClock: @"left", kSettings: @"right"}) && !gKAsked, [NSString stringWithFormat:@"%@: counter, no Home: Clock's Dock icon tiles it with Settings (unchanged)", en]);

            // Home with nothing full screen: both minimized, both back from the Dock: the arrangement kept, nothing slides
            TwoTiles();
            Home(); Unslid(); DockRestores(kClock); DockRestores(kSettings);
            Check(Tiles(@{kSettings: @"left", kClock: @"right"}) && At(kSettings, @"left") && At(kClock, @"right") && !gKSlid.count, [NSString stringWithFormat:@"%@: counter, Home with no window full screen, both back from the Dock: the arrangement kept, nothing moves (unchanged)", en]);

            // Z11: Large while full screen, the entry removed, Home, Clock's Dock icon (a new window Fit tiles), Settings' Dock icon
            TwoTiles();
            Green(e, kClock);
            SizeWhileFull(kClock, MSBDAppSizeLarge);
            SizeWhileFull(kClock, MSBDAppSizeNone);
            Home();
            DockOpensNew(kClock, NO, CGRectMake(113, 32, 799, 614));
            note(@"Z11-a", [NSString stringWithFormat:@"%@ Z11 after Clock's Dock icon: %@", en, State()]);
            Check(Logged(@"opens a new window (its place was forgotten while it was full screen)"), [NSString stringWithFormat:@"%@: Z11 the record line as designed (the device's log)", en]);
            Check(Tiles(@{kSettings: @"left"}) && CGRectEqualToRect(DMStageForBundle(kClock).frame, CGRectMake(113, 32, 799, 614)), [NSString stringWithFormat:@"%@: Z11 ... Clock opens on its own at Window Size's place, Settings (minimized) keeps its tile (Stage Manager C12: Fit keeps Settings' tile)", en]);
            DockRestores(kSettings);
            note(@"Z11-b", [NSString stringWithFormat:@"%@ Z11 after Settings' Dock icon: %@", en, State()]);
            Check(Tiles(@{kClock: @"left", kSettings: @"right"}) && At(kClock, @"left") && At(kSettings, @"right"), [NSString stringWithFormat:@"%@: Z11 ... Settings back: Clock left, Settings right (C12's halves)", en]);

            // Z8: Large while full screen, Home, Clock's Dock icon (free at Large), Settings' Dock icon
            TwoTiles();
            Green(e, kClock);
            SizeWhileFull(kClock, MSBDAppSizeLarge);
            Home(); Unslid();
            DockOpensNew(kClock, NO, CGRectMake(41, 34, 942, 650));
            note(@"Z8-a", [NSString stringWithFormat:@"%@ Z8 after Clock's Dock icon: %@", en, State()]);
            Check(Logged(@"comes back from full screen as a free window, not into its tile"), [NSString stringWithFormat:@"%@: Z8 Clock back free: the close-up line (decision c; the device: none)", en]);
            Check(Tiles(@{kSettings: @"fill"}) && At(kSettings, @"fill") && !gKSlid.count, [NSString stringWithFormat:@"%@: Z8 ... Settings' tile closed up to Fill while minimized, put there out of sight (Stage Manager C8: close up (Settings fill))", en]);
            Check([objc_getAssociatedObject(DMStageForBundle(kSettings), kStageLayoutNameKey) isEqual:@"fill"], [NSString stringWithFormat:@"%@: R6 Z8 ... Settings' layout noted as Fill while minimized: a turn puts it back at Fill (the H2-H5 review, finding 6)", en]);
            DockRestores(kSettings);
            note(@"Z8-b", [NSString stringWithFormat:@"%@ Z8 after Settings' Dock icon: %@", en, State()]);
            Check(Tiles(@{kSettings: @"fill"}) && At(kSettings, @"fill") && [gFreeWindows containsObject:kClock], [NSString stringWithFormat:@"%@: Z8 ... Settings back: it fills, Clock stays free at Large", en]);

            // Z8 counter, no Home (G2 row 3 with Settings on screen): the close-up as designed
            TwoTiles();
            Green(e, kClock);
            SizeWhileFull(kClock, MSBDAppSizeLarge);
            DockOpensNew(kClock, NO, CGRectMake(41, 34, 942, 650));
            Check(Logged(@"comes back from full screen as a free window, not into its tile") && Tiles(@{kSettings: @"fill"}), [NSString stringWithFormat:@"%@: counter, no Home: Clock back free closes its tile up, Settings fills (unchanged)", en]);

            // The H2-H5 review, finding 1 (Stage Manager's row 12, Home Minimizes Windows on): Settings left, Clock right; Clock's green; Home; Maps from
            // the Dock (it opens on its own); Clock's Dock icon (a new window; the record keeps its way back): a window of the arrangement, so the
            // minimized Settings keeps a tile -- Clock the first tile (D13 item 4's default), Maps the next, Settings the last, placed there out of sight
            TwoTiles();
            Green(e, kClock);
            Home();
            UIView *maps1 = DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
            Check(Tiles(@{kSettings: @"left"}) && [objc_getAssociatedObject(maps1, kStageFitAloneKey) boolValue] && CGRectEqualToRect(maps1.frame, CGRectMake(113, 32, 799, 614)),
                  [NSString stringWithFormat:@"%@: R1 Maps from the Dock after Home: it opens on its own at its own size, Settings keeps its tile", en]);
            Unslid();
            DockOpensNew(kClock, YES, KTile(@"right"));
            note(@"R1-a", [NSString stringWithFormat:@"%@ R1 after Clock's Dock icon: %@", en, State()]);
            Check(Tiles(@{kClock: @"left", kMaps: @"topright", kSettings: @"bottomright"}) && At(kClock, @"left") && At(kMaps, @"topright") && At(kSettings, @"bottomright") && !gKAsked && ![gKSlid containsObject:kSettings],
                  [NSString stringWithFormat:@"%@: R1 ... Clock's Dock icon: Clock the left half, Maps the top right, Settings keeps the bottom right (put there out of sight), no question", en]);
            Check(![objc_getAssociatedObject(maps1, kStageFitAloneKey) boolValue], [NSString stringWithFormat:@"%@: R1 ... Maps is in the tiles now: no longer marked as opened on its own", en]);
            Unslid(); DockRestores(kSettings);
            note(@"R1-b", [NSString stringWithFormat:@"%@ R1 after Settings' Dock icon: %@", en, State()]);
            Check(Tiles(@{kClock: @"left", kMaps: @"topright", kSettings: @"bottomright"}) && At(kSettings, @"bottomright") && !gKSlid.count && !gKAsked,
                  [NSString stringWithFormat:@"%@: R1 ... Settings' Dock icon: into its tile, nothing moves, no question", en]);
            // ... counter: its way back forgotten while full screen (App Window Sizes: Large, then the entry removed): Clock is a new window, not one of the
            //     arrangement -- tiled with Maps as a new set, Settings' tile goes (unchanged; our Stage Manager engine's join the same: no tile kept)
            TwoTiles();
            Green(e, kClock);
            SizeWhileFull(kClock, MSBDAppSizeLarge); SizeWhileFull(kClock, MSBDAppSizeNone);
            Home();
            DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
            DockOpensNew(kClock, NO, CGRectMake(113, 32, 799, 614));
            Check(Tiles(@{kClock: @"left", kMaps: @"right"}) && !gKAsked, [NSString stringWithFormat:@"%@: R1 counter, its way back forgotten while full screen: Clock and Maps as a new set, Settings' tile goes (unchanged)", en]);

            // The H2-H5 review, finding 5: the green light's way back takes the windows that opened on their own into the tiles, as a minimized
            // window's return does and as our Stage Manager engine's tick at a window's way back (its row 12: Maps left, Clock bottom right,
            // Settings top right); Aerial's with no entrance cover is placed, not cascaded. Settings left, Clock right; Clock's green; Settings'
            // yellow; Maps from the Dock (on its own); the status bar's green on Clock
            TwoTiles();
            Green(e, kClock);
            Minimize(kSettings);
            UIView *maps5 = DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
            Unslid();
            GreenBack(e, kClock, KTile(@"right"));
            note(@"R5-a", [NSString stringWithFormat:@"%@ R5 after Clock's way back: %@", en, State()]);
            Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kMaps, @"left") && At(kClock, @"bottomright") && At(kSettings, @"topright") && ![gKSlid containsObject:kSettings] && !gKAsked
                  && ![objc_getAssociatedObject(maps5, kStageFitAloneKey) boolValue] && Logged(@"join(s) the tiles (opened on their own while the tiled windows were minimized)"),
                  [NSString stringWithFormat:@"%@: R5 Settings minimized, Maps opened on its own, Clock's way back: Maps joins (the left half), Clock the bottom right, Settings keeps the top right (put there out of sight), no question; the log says why", en]);
            Unslid(); DockRestores(kSettings);
            Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kSettings, @"topright") && !gKSlid.count, [NSString stringWithFormat:@"%@: R5 ... Settings back: into its tile, nothing moves", en]);
            // ... nothing else on screen: Clock is not taken for a window that opened on its own (Aerial: placed, not cascaded); its tile again
            TwoTiles();
            Green(e, kClock);
            Minimize(kSettings);
            GreenBack(e, kClock, KTile(@"right"));
            Check(Tiles(@{kSettings: @"left", kClock: @"right"}) && At(kClock, @"right") && !Logged(@"opens on its own") && ![objc_getAssociatedObject(DMStageForBundle(kClock), kStageFitAloneKey) boolValue],
                  [NSString stringWithFormat:@"%@: R5 Clock's way back with Settings minimized and nothing else on screen: no \"opens on its own\" line nor mark, its tile again", en]);
            // ... Settings closed while minimized, Maps on its own: Clock's way back tiles Maps with it (Maps the new one), as Stage Manager's
            TwoTiles();
            Green(e, kClock);
            Minimize(kSettings);
            DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
            Gone(kSettings); Tick();
            GreenBack(e, kClock, KTile(@"right"));
            Check(Tiles(@{kMaps: @"left", kClock: @"right"}) && At(kMaps, @"left") && At(kClock, @"right"), [NSString stringWithFormat:@"%@: R5 Settings closed while minimized, Maps on its own, Clock's way back: Maps and Clock as halves, Maps the left one", en]);

            for (int pill = 0; pill <= (e == KZetsu); pill++) {   // (Zetsu: also with its own title-bar pill as the minimize)
                gKPill = pill;
                NSString *how = pill ? @" (Zetsu's pill)" : @"";
                // The owner's old bug stays fixed: both tiles minimized, Maps opened: on its own at its own size, not squeezed into a half; the
                // arrangement stays; Clock back: Maps joins as a new window
                TwoTiles();
                Minimize(kSettings); Minimize(kClock); Unslid();
                UIView *maps = DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
                Check(Tiles(@{kSettings: @"left", kClock: @"right"}) && CGRectEqualToRect(maps.frame, CGRectMake(113, 32, 799, 614)) && !gKSlid.count && !gKAsked,
                      [NSString stringWithFormat:@"%@%@: every tile minimized, Maps opens: at its own size, not tiled (the owner's old bug stays fixed); the arrangement kept", en, how]);
                DockRestores(kClock);
                Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kMaps, @"left") && At(kClock, @"bottomright") && !gKAsked,
                      [NSString stringWithFormat:@"%@%@: ... Clock back: Maps joins as a new window (the left half), Clock and Settings keep their places (Settings' quarter for its return)", en, how]);
                DockRestores(kSettings);
                Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kSettings, @"topright") && !gKAsked, [NSString stringWithFormat:@"%@%@: ... Settings back: into its tile, no question", en, how]);
                // ... the same, Maps placed by the user meanwhile (a regular window): it stays where it is at the return
                TwoTiles();
                Minimize(kSettings); Minimize(kClock);
                maps = DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
                DMFitGroupForget(kMaps);   // (placed by the user: a Window menu layout, a drag)
                Unslid(); DockRestores(kClock);
                Check(Tiles(@{kSettings: @"left", kClock: @"right"}) && CGRectEqualToRect(maps.frame, CGRectMake(113, 32, 799, 614)) && !gKSlid.count,
                      [NSString stringWithFormat:@"%@%@: ... Maps placed by the user meanwhile: Clock back into its tile, Maps stays where it was put", en, how]);

                // A window opens next to a tiled window on screen and a minimized one: no question (one of the halves is minimized), it takes the
                // first tile and the minimized one keeps a tile for its return (placed there out of sight)
                TwoTiles();
                Minimize(kClock); Unslid();
                DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
                Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && !gKAsked && At(kClock, @"bottomright") && ![gKSlid containsObject:kClock],
                      [NSString stringWithFormat:@"%@%@: Settings on screen, Clock minimized, Maps opens: no question, three tiles, Clock's kept and put there out of sight", en, how]);
                Unslid(); DockRestores(kClock);
                Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kClock, @"bottomright") && !gKSlid.count && !gKAsked, [NSString stringWithFormat:@"%@%@: ... Clock back: into its tile, nothing moves", en, how]);

                // The green light's way back next to a minimized tile: Clock's green, Settings' yellow, the way back: Clock rejoins, Settings keeps its tile
                TwoTiles();
                Green(e, kClock);
                Minimize(kSettings);
                GreenBack(e, kClock, KTile(@"right"));
                Check(Tiles(@{kSettings: @"left", kClock: @"right"}) && At(kClock, @"right"), [NSString stringWithFormat:@"%@%@: Clock back from full screen by its green while Settings is minimized: its tile again, Settings keeps hers", en, how]);
                Unslid(); DockRestores(kSettings);
                Check(Tiles(@{kSettings: @"left", kClock: @"right"}) && At(kSettings, @"left") && At(kClock, @"right") && !gKSlid.count, [NSString stringWithFormat:@"%@%@: ... Settings back: the two halves as they were, nothing moves", en, how]);

                // A tile closes with no window on screen (the closure watcher): the minimized windows close it up among themselves
                TwoTiles();
                Home(); Unslid(); Gone(kClock); Tick();
                Check(Tiles(@{kSettings: @"fill"}) && At(kSettings, @"fill") && !gKSlid.count, [NSString stringWithFormat:@"%@%@: both minimized, Clock quits: Settings' tile closes up to Fill, put there out of sight", en, how]);
                DockRestores(kSettings);
                Check(Tiles(@{kSettings: @"fill"}) && At(kSettings, @"fill"), [NSString stringWithFormat:@"%@%@: ... Settings back: it fills", en, how]);
                // ... with one on screen, as before (O1): Settings on screen, Safari minimized, Clock quits: Settings fills, Safari's tile goes
                Tiled(@{kSettings: @"left", kSafari: @"topright", kClock: @"bottomright"});
                Minimize(kSafari); Gone(kClock); Tick();
                Check(Tiles(@{kSettings: @"fill"}), [NSString stringWithFormat:@"%@%@: counter (O1): Settings on screen, Safari minimized, Clock quits: Settings fills, Safari's tile goes (unchanged)", en, how]);

                // The H2-H5 review, finding 2: a close-up with two or more windows on screen keeps the minimized window's tile, as our Stage Manager
                // engine's (DMSMFitLeftAfterClose; test-fitminimized-sm.m's R2): four tiles, Clock minimized, Notes quits
                NSDictionary *four = @{kSettings: @"topleft", kSafari: @"topright", kNotes: @"bottomleft", kClock: @"bottomright"};
                NSDictionary *threeLeft = @{kSettings: @"left", kSafari: @"topright", kClock: @"bottomright"};
                Tiled(four);
                Minimize(kClock); Unslid(); Gone(kNotes); Tick();
                if (!pill) note(@"R2-a", [NSString stringWithFormat:@"%@ R2 after Notes quits: %@", en, State()]);
                Check(Tiles(threeLeft) && At(kSettings, @"left") && At(kSafari, @"topright") && At(kClock, @"bottomright") && ![gKSlid containsObject:kClock],
                      [NSString stringWithFormat:@"%@%@: R2 four tiles, Clock minimized, Notes quits: the two on screen and Clock close the tile up, each keeping its place (Clock keeps the bottom right, put there out of sight)", en, how]);
                Check([objc_getAssociatedObject(DMStageForBundle(kClock), kStageLayoutNameKey) isEqual:@"bottomright"], [NSString stringWithFormat:@"%@%@: R6 ... Clock's layout noted as the bottom right quarter while minimized", en, how]);
                Unslid(); DockRestores(kClock);
                Check(Tiles(threeLeft) && At(kClock, @"bottomright") && !gKSlid.count && !gKAsked, [NSString stringWithFormat:@"%@%@: R2 ... Clock back: into its tile, nothing moves", en, how]);
                // ... G2's close-up the same: Notes back free from full screen (Large given while full screen)
                Tiled(four);
                Minimize(kClock); Green(e, kNotes); SizeWhileFull(kNotes, MSBDAppSizeLarge); Unslid();
                DockOpensNew(kNotes, NO, CGRectMake(41, 34, 942, 650));
                Check(Logged(@"comes back from full screen as a free window, not into its tile") && Tiles(threeLeft) && At(kClock, @"bottomright") && ![gKSlid containsObject:kClock],
                      [NSString stringWithFormat:@"%@%@: R2 four tiles, Clock minimized, Notes back free from full screen: the same close-up, Clock keeps the bottom right", en, how]);
                // ... counter (O1 on that close-up): three tiles, Clock minimized, Safari back free: Settings fills alone, Clock's tile goes (unchanged)
                Tiled(@{kSettings: @"left", kSafari: @"topright", kClock: @"bottomright"});
                Minimize(kClock); Green(e, kSafari); SizeWhileFull(kSafari, MSBDAppSizeLarge);
                DockOpensNew(kSafari, NO, CGRectMake(41, 34, 942, 650));
                Check(Tiles(@{kSettings: @"fill"}), [NSString stringWithFormat:@"%@%@: counter (O1): three tiles, Clock minimized, Safari back free: Settings fills alone (unchanged)", en, how]);
            }
            gKPill = NO;
            // Counter: the question for a third window still comes with both halves on screen
            TwoTiles();
            DockOpensNew(kMaps, NO, CGRectMake(113, 32, 799, 614));
            Check(gKAsked == 1, [NSString stringWithFormat:@"%@: counter, both halves on screen, Maps opens: asked where it goes (unchanged)", en]);
        }
#ifdef K_HAS_ASKED
        {   // (the ask for Aerial's place, the H2-H5 review's fix 5: taken once, for its app only, while it holds)
            gA5EntranceBundle = kClock; gA5EntranceFrame = KTile(@"right"); gA5EntranceAt = CACurrentMediaTime();
            CGRect f1 = CGRectNull, f2 = CGRectNull;
            BOOL t1 = DMAerialAskedPlaceTake(kClock, &f1), t2 = DMAerialAskedPlaceTake(kClock, &f2);
            gA5EntranceBundle = kClock; gA5EntranceAt = CACurrentMediaTime() - 5.0; BOOL t3 = DMAerialAskedPlaceTake(kClock, NULL);
            gA5EntranceBundle = kClock; gA5EntranceAt = CACurrentMediaTime(); BOOL t4 = DMAerialAskedPlaceTake(kMaps, NULL);
            gA5EntranceBundle = nil;
            Check(t1 && CGRectEqualToRect(f1, KTile(@"right")) && !t2 && !t3 && !t4, @"DMAerialAskedPlaceTake: the ask for a place is taken once, for its app only, while it holds (4 s)");
        }
#endif
        for (int e = KAerial; e <= KMilkyWay; e++) {   // (the Mac Switcher, the same on every engine: the H2-H5 review, finding 3)
            NSString *en = names[e];
            gKPill = NO;
            // A window brought from another desktop meets this desktop's minimized tiles as a window that opens here does (as our Stage Manager
            // engine's tick keeps them for a window joining its stage): Settings left, Clock right, Clock minimized, Maps brought here
            TwoTiles();
            Minimize(kClock); Unslid();
            KBring(kMaps, CGRectMake(113, 32, 799, 614));
            note(@"R3-a", [NSString stringWithFormat:@"%@ R3 after Maps is brought here: %@", en, State()]);
            Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kMaps, @"left") && At(kSettings, @"topright") && At(kClock, @"bottomright") && ![gKSlid containsObject:kClock] && !gKBringAsked,
                  [NSString stringWithFormat:@"%@: R3 Maps brought from another desktop, Clock minimized: Maps the left half, Settings the top right, Clock keeps the bottom right (put there out of sight), no question", en]);
            Unslid(); DockRestores(kClock);
            Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kClock, @"bottomright") && !gKSlid.count, [NSString stringWithFormat:@"%@: R3 ... Clock back: into its tile, nothing moves", en]);
            // ... every tile minimized: it keeps its size, on its own, and joins the tiles when one comes back
            TwoTiles();
            Home(); Unslid();
            UIView *mapsB = KBring(kMaps, CGRectMake(113, 32, 799, 614));
            Check(Tiles(@{kSettings: @"left", kClock: @"right"}) && CGRectEqualToRect(mapsB.frame, CGRectMake(113, 32, 799, 614)) && [objc_getAssociatedObject(mapsB, kStageFitAloneKey) boolValue] && !gKSlid.count,
                  [NSString stringWithFormat:@"%@: R3 every tile minimized, Maps brought here: it keeps its size, on its own, the arrangement kept", en]);
            DockRestores(kClock);
            Check(Tiles(@{kMaps: @"left", kSettings: @"topright", kClock: @"bottomright"}) && At(kMaps, @"left") && At(kClock, @"bottomright"),
                  [NSString stringWithFormat:@"%@: R3 ... Clock back: Maps joins the tiles (the left half), Settings keeps the top right for its return", en]);
            // A tiled window dragged to another desktop: the tiles left close up by the rule of every close-up -- two on screen: Clock's tile kept
            Tiled(@{kSettings: @"topleft", kSafari: @"topright", kNotes: @"bottomleft", kClock: @"bottomright"});
            Minimize(kClock); Unslid();
            KMoveAway(kNotes);
            Check(Tiles(@{kSettings: @"left", kSafari: @"topright", kClock: @"bottomright"}) && At(kClock, @"bottomright") && ![gKSlid containsObject:kClock] && [gMSWFit[@"2"][@"group"] containsObject:kNotes],
                  [NSString stringWithFormat:@"%@: R3 four tiles, Clock minimized, Notes dragged to another desktop: Settings left, Safari top right, Clock keeps the bottom right; Notes in desktop 2's tiles", en]);
            // ... none left on screen: Clock keeps the plan alone (it fills when it comes back), as our Stage Manager engine's move
            TwoTiles();
            Minimize(kClock);
            KMoveAway(kSettings);
            Check(Tiles(@{kClock: @"fill"}) && At(kClock, @"fill"), [NSString stringWithFormat:@"%@: R3 Settings and Clock, Clock minimized, Settings dragged away: Clock keeps the plan, at Fill for its return", en]);
            // ... counter (O1): three tiles, Clock minimized, Safari dragged away: Settings fills alone, Clock's tile goes (unchanged)
            Tiled(@{kSettings: @"left", kSafari: @"topright", kClock: @"bottomright"});
            Minimize(kClock);
            KMoveAway(kSafari);
            Check(Tiles(@{kSettings: @"fill"}), [NSString stringWithFormat:@"%@: counter (O1): three tiles, Clock minimized, Safari dragged to another desktop: Settings fills alone (unchanged)", en]);
        }
        for (NSString *row in [seen.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSMutableSet *rest = [NSMutableSet set];
            for (NSString *s in seen[row]) { NSRange r = [s rangeOfString:@": "]; [rest addObject:[s substringFromIndex:r.location]]; }
            BOOL same = rest.count == 1;
            Check(same, [NSString stringWithFormat:@"%@: the three engines end in one state", row]);
        }
        printf("%d checks, %d failed\n", gChecks, gFails);
    }
    return gFails;
}
