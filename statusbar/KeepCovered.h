// KeepCovered.h -- Keep Covered Windows in Front (Settings > Windows & Multitasking, 1.8.4.1 item 7, KT 8 Nov ~00:40; off unless switched on; the rule
// and why: common/WindowOrder.h MSBDOrderKeepCovered). Included at the end of StatusBar.x after WindowFront.h, whose raise it follows.
// When a window comes forward, the windows it covers completely go above it, each in its own order:
//  - Aerial, Zetsu, MilkyWay4: right after every raise of ours (DMEngineRaise: a tap or click in a window, its Dock icon, Command-Tab, the Mac
//    Switcher, our menus), and from the tick for the engine's own (a tap on its title bar, Aerial's own touch to front): the window seen in front is
//    not the last one seen and is none of the windows kept above another. The window that came forward stays the active one -- the menu bar's app, the
//    window keys' window -- while only windows it kept are above it, still inside it (MSBDActiveWithKept; DMActiveApp asks DMKeepCoveredActive): the
//    keyboard is that app's, which a touch gave it. A kept window touched, on its title bar too, moved or resized by hand is an ordinary one again.
//  - Stage Manager: from the tick, once its own transition is over (a request asked during one can be undone by it), in one request as Stage Manager
//    asks it (DMSMRequestStageOrderAs): the kept windows newer than the window that came forward. Stage Manager's front window is its newest, and the
//    keyboard goes with it, so there the window kept in front is the active one (the menu bar follows the keyboard).
// Nothing while the Mac Switcher shows its desktops, for minimized or hidden windows, or windows of another desktop or screen.
#pragma once
#include "../common/WindowOrder.h"

static BOOL gDMKeepCoveredBusy = NO;               // (our own raises of the kept windows: no rule asked again from inside)
static __weak UIView *gDMKeptUnder = nil;          // (the window that came forward and kept windows above it: the active one, MSBDActiveWithKept)
static NSHashTable<UIView *> *gDMKeptAbove = nil;  // (the windows it kept above it, weakly)
static __weak UIView *gDMKeepLastTop = nil;        // (the window the tick saw in front last)
// A window as it shows on its screen, for "inside": Aerial 5.x's window inside its stage; every engine's windows are in one window of SpringBoard's
// (Zetsu's are windows of their own: their frames are the screen's).
static CGRect DMKeepCoveredFrame(UIView *s) {
    if (DMIsZetsuWindow(s)) return s.frame;
    return s.superview ? [s.superview convertRect:DMA5WindowFromStage(s.frame) toView:nil] : CGRectNull;
}
static BOOL DMKeepCoveredShows(UIView *s, UIScreen *scr) {
    return s && !s.hidden && s.alpha > 0.05 && !DMStageMinimized(s) && ![objc_getAssociatedObject(s, kStageClosingKey) boolValue] && DMSnapScreenOf(s) == scr;
}
static void DMKeepCoveredForget(void) { gDMKeptUnder = nil; [gDMKeptAbove removeAllObjects]; }
// w came forward (Aerial, Zetsu, MilkyWay4): the windows it covers completely raised above it, in their order; it is the active one while they are.
// (kept out of line, as DMKeepCoveredSMTick: the crash guard's map names them -- tools/crashmap-rules.txt keepCoveredInFront)
__attribute__((noinline)) static void DMKeepCoveredAfterRaise(UIView *w, NSString *why) {
    if (!gKeepCoveredInFront || gDMKeepCoveredBusy || !w || DMSMEngine() || DMActiveEngine() == DMEngineNone || gMSWOpen) return;
    DMKeepCoveredForget();   // (another window came forward: the one before is no longer the active one for its kept windows)
    NSArray<UIView *> *stages = DMAerialStages();   // (back to front, this desktop)
    int n = (int)MIN(stages.count, (NSUInteger)64), at = -1, kept = 0, order[64];
    CGRect frames[64]; bool shown[64];
    UIScreen *scr = DMSnapScreenOf(w);
    for (int i = 0; i < n; i++) {
        frames[i] = DMKeepCoveredFrame(stages[i]);
        shown[i] = DMKeepCoveredShows(stages[i], scr);
        if (stages[i] == w) at = i;
    }
    if (at < 0) return;
    int m = MSBDOrderKeepCovered(frames, shown, n, at, order, &kept);
    if (!kept) return;
    if (!gDMKeptAbove) gDMKeptAbove = [NSHashTable weakObjectsHashTable];
    gDMKeptUnder = w;
    gDMKeepCoveredBusy = YES;
    NSMutableArray *names = [NSMutableArray array];
    BOOL past = NO;
    for (int i = 0; i < m; i++) {
        if (order[i] == at) { past = YES; continue; }
        if (!past) continue;
        UIView *s = stages[order[i]];
        [gDMKeptAbove addObject:s];
        DMEngineRaise(s, @"kept in front of the window that covers it");
        [names addObject:DMStageBundle(s) ?: @"?"];
    }
    gDMKeepCoveredBusy = NO;
    gDMKeepLastTop = DMTopStage();
    DMApplyWindowLevel();
    DM_FEATURE_MARK("keep-covered-windows-in-front");
    DMLog([NSString stringWithFormat:@"[keepcovered] %@: %@ came forward; kept in front of it: %@", why, DMStageBundle(w), [names componentsJoinedByString:@", "]]);
}
// The active window (DMActiveApp, Aerial / Zetsu / MilkyWay4): top, unless only windows kept above the window that came forward are above it -- each
// counted while it is still inside that window, as it shows now (review 1.8.4.1 M1: one dragged out of it is an ordinary window again).
static UIView *DMKeepCoveredActive(UIView *top) {
    UIView *under = gDMKeptUnder;
    if (!gKeepCoveredInFront || !under || !top || top == under || ![gDMKeptAbove containsObject:top]) return top;
    NSArray<UIView *> *stages = DMAerialStages();
    int n = (int)MIN(stages.count, (NSUInteger)64), at = -1;
    bool shown[64], keptAbove[64]; CGRect frames[64];
    UIScreen *scr = DMSnapScreenOf(under);
    for (int i = 0; i < n; i++) {
        shown[i] = DMKeepCoveredShows(stages[i], scr); keptAbove[i] = [gDMKeptAbove containsObject:stages[i]];
        frames[i] = (keptAbove[i] || stages[i] == under) ? DMKeepCoveredFrame(stages[i]) : CGRectNull;   // (only these are looked at)
        if (stages[i] == under) at = i;
    }
    int a = MSBDActiveWithKept(shown, keptAbove, frames, n, at);
    return a >= 0 && a < n ? stages[a] : top;
}
// A window handled by hand (review 1.8.4.1 M1): a touch on its title bar or its lights (TitleBarTap.h: every engine's bar), a move or a resize by hand
// ended (DMTitleRecordHandEnded, DMSnapMoveEnded; Zetsu's own, seen by its watcher). A window kept above another -- v, or the window v is part of -- is
// an ordinary one again, the active one where it is in front, as a tap in it makes it (DMKeepCoveredTouched); a raise its engine then makes comes
// through the tick as the engine's own. The window under it, or any other, handled by hand: nothing here (DMKeepCoveredActive asks the frames).
static void DMKeepCoveredByHand(UIView *v) {
    if (!gKeepCoveredInFront || !gDMKeptAbove.count) return;
    for (; v; v = v.superview) if ([gDMKeptAbove containsObject:v]) { DMKeepCoveredForget(); return; }
}
// A window touched where it is (DMRaiseStageForBundle: in front already): one of the kept windows is the active one now; any other came forward only if
// it was not in front at the last raise or tick (the engine's own raise of it, not yet seen by the tick). One in front since then is the active one as
// the top window, and nothing goes above it: a big window moved or resized over a smaller one on purpose stays over it at the next tap in it (review
// 1.8.4.1 L6: nothing came forward).
static void DMKeepCoveredTouched(UIView *s) {
    if (!gKeepCoveredInFront || !s) return;
    if ([gDMKeptAbove containsObject:s]) { DMKeepCoveredForget(); gDMKeepLastTop = s; return; }
    if (s == gDMKeepLastTop) return;
    DMKeepCoveredAfterRaise(s, @"a tap or click in it");
}
// Off for now, with its row (KT 9 Nov, review 1.8.4.1 M3): Stage Manager gives the keyboard to the newest window, so a click on a big window to type in it
// would send the typing to the small window kept above it, every time. The other engines keep the two apart (DMKeepCoveredActive). Back on once they can be
// kept apart here too.
static const BOOL kDMKeepCoveredOnStageManager = NO;
// ---- Stage Manager: from the tick, the front window's covered windows newer than it, in one request ----
static NSString *gDMSMKeepLastFront = nil;
static NSMutableSet<NSString *> *gDMSMKeptKeys = nil;   // (the windows kept above the front one: the front change they make is ours)
// The switch turned on or off (DMLoadPrefs): nothing is kept from before -- the window that came forward and its kept windows, the window last seen in
// front, Stage Manager's. Turned on again later, the active window was one from back then, and the tick passed over the window in front (review 1.8.4.1
// L5); now the first tick takes the window in front as the one that came forward, as at the first time on.
static void DMKeepCoveredReset(void) {
    DMKeepCoveredForget();
    gDMKeepLastTop = nil;
    gDMSMKeepLastFront = nil;
    [gDMSMKeptKeys removeAllObjects];
}
__attribute__((noinline)) static void DMKeepCoveredSMTick(void) {
    NSString *front = DMSMFrontWindowKey();
    if (!front.length || [front isEqualToString:gDMSMKeepLastFront]) return;
    if (DMSMWorkspaceBusy()) return;   // (its own transition first: asked at the next tick)
    gDMSMKeepLastFront = [front copy];
    if ([gDMSMKeptKeys containsObject:front]) return;   // (our own request made it the front one)
    [gDMSMKeptKeys removeAllObjects];
    id stage = DMSMWorkingStage();
    NSDictionary *map = DMSMStageItemsMap(stage);
    NSDictionary<NSString *, NSValue *> *open = DMSMOpenWindowFrames();
    if (map.count < 2 || open.count < 2) return;
    NSArray *items = [[map allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {   // (back to front)
        long long ta = DMSMAttrTimeOr(map[a], 0), tb = DMSMAttrTimeOr(map[b], 0);
        return ta < tb ? NSOrderedAscending : (ta > tb ? NSOrderedDescending : NSOrderedSame);
    }];
    int n = (int)MIN(items.count, (NSUInteger)64), at = -1, kept = 0, order[64];
    CGRect frames[64]; bool shown[64]; long long newest = 0;
    for (int i = 0; i < n; i++) {
        NSString *k = DMSMItemKey(items[i]);
        NSValue *f = k ? open[k] : nil;
        frames[i] = f ? f.CGRectValue : CGRectNull;
        shown[i] = f != nil && !DMSMAttrsFullScreen(map[items[i]]);
        newest = MAX(newest, DMSMAttrTimeOr(map[items[i]], 0));
        if (k && [k isEqualToString:front]) at = i;
    }
    if (at < 0) return;
    int m = MSBDOrderKeepCovered(frames, shown, n, at, order, &kept);
    if (!kept) return;
    NSMutableDictionary *times = [NSMutableDictionary dictionary];
    BOOL past = NO; id last = nil; long long t = newest;
    if (!gDMSMKeptKeys) gDMSMKeptKeys = [NSMutableSet set];
    for (int i = 0; i < m; i++) {
        if (order[i] == at) { past = YES; continue; }
        if (!past) continue;
        times[items[order[i]]] = @(++t); last = items[order[i]];
        NSString *k = DMSMItemKey(items[order[i]]); if (k) [gDMSMKeptKeys addObject:k];
    }
    BOOL ok = last && DMSMRequestStageOrderAs(stage, times, last, NO);
    DMLog([NSString stringWithFormat:@"[keepcovered] %@ came forward: %lu window(s) it covers kept in front of it (%@)", DMSMKeyText(front), (unsigned long)times.count, ok ? @"asked" : @"refused"]);
}
// Every tick (0.2 s) while the switch is on: a window the engine brought forward itself, or Stage Manager's front window changed.
static void DMKeepCoveredTick(void) {
    if (!gKeepCoveredInFront || gMSWOpen) return;
    if (DMSMEngine()) { if (kDMKeepCoveredOnStageManager) DMKeepCoveredSMTick(); return; }
    if (DMActiveEngine() == DMEngineNone) return;
    UIView *top = DMTopStage();
    if (top == gDMKeepLastTop) return;
    gDMKeepLastTop = top;
    if (top && ![gDMKeptAbove containsObject:top]) DMKeepCoveredAfterRaise(top, @"came forward (the engine's own)");
}
