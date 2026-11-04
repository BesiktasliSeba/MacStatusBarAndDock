// FitPlan.h -- where Fit to Window's windows go when its set of windows changes: one rule for every engine (1.8.0 engine parity, KT 3 Nov: a
// behaviour that differs between engines is a bug). Plain Foundation: StatusBar.x (Aerial, Zetsu, MilkyWay4 and our Stage Manager engine, with
// SMFitPlan.h), MacSwitcher.h and MacSwitcherSM.h call it; the Mac test tools/test-fitorder.sh runs this very code.
// A window keeps its place, as on a Mac. When the tiles close up (a tiled window closed, quit, went full screen for good or to another desktop)
// or a window joins them, every window that stays takes the tile of the new arrangement that keeps the most of where it was: it grows into the
// space next to it and never jumps across the desktop while another choice keeps it where it is. A window that had no tile there (the one that
// opens, one that comes from another desktop) takes the first tile, newest first -- the left half, the top-left quarter --, as Fit has always
// placed a new window. Before 1.8.0 an order of the windows decided where they went, and not the same one: Aerial, Zetsu and MilkyWay4 the order
// they had joined the tiles in (gFitGroup), our Stage Manager engine the order of their last use (lastInteractionTime). On the same desktop the
// same close gave the left half to another window depending on the engine (three tiles, the oldest window used last, the middle one closed:
// Aerial kept Notes in the left half, Stage Manager gave it to Maps; M1 15.6.1 Aerial 5.1 and iPad 2 16.7.7, 3 Nov), and either order moved
// windows across: a tile of three closed and the other two swapped sides (Aerial), a fourth window joined and two others swapped corners (both),
// the top-right quarter of four closed and the bottom-left one jumped to the top right (both).
#pragma once
#import <Foundation/Foundation.h>
#include <math.h>
#include <string.h>

// The default tiles for n windows, newest first: two are the halves, three are a left half with the right half split, four are the quarters
// (StatusBar.x DMDefaultSlotNames is this list).
static NSArray<NSString *> *MSBDFitDefaultTiles(NSUInteger n) {
    return n == 2 ? @[@"left", @"right"] : (n == 3 ? @[@"left", @"topright", @"bottomright"] : @[@"topleft", @"topright", @"bottomleft", @"bottomright"]);
}
// Three windows' other arrangement, the half on the right (the side question's "Left": the new window on top of the left side). Tiles that only
// close up may take it: the top-right quarter of four closed, and the window under it grows up into the space, the left two keep their quarters
// (with the default arrangement the bottom-left window jumped to the top right).
static NSArray<NSString *> *MSBDFitHalfRightTiles(void) { return @[@"topleft", @"bottomleft", @"right"]; }

// A tile of Fit's as a part of the desktop, the desktop being 1 x 1 (x, y: its top-left corner). 0 for a name that is not one of Fit's tiles (a
// window put somewhere by hand, the middle place): such a window has no tile to keep.
typedef struct { double x, y, w, h; } MSBDFitUnit;
static int MSBDFitTileUnit(id tile, MSBDFitUnit *out) {
    static const struct { const char *name; MSBDFitUnit u; } t[] = {
        {"fill", {0, 0, 1, 1}}, {"left", {0, 0, 0.5, 1}}, {"right", {0.5, 0, 0.5, 1}}, {"top", {0, 0, 1, 0.5}}, {"bottom", {0, 0.5, 1, 0.5}},
        {"topleft", {0, 0, 0.5, 0.5}}, {"topright", {0.5, 0, 0.5, 0.5}}, {"bottomleft", {0, 0.5, 0.5, 0.5}}, {"bottomright", {0.5, 0.5, 0.5, 0.5}},
    };
    if (![tile isKindOfClass:[NSString class]]) return 0;
    const char *s = [(NSString *)tile UTF8String];
    for (size_t i = 0; s && i < sizeof t / sizeof t[0]; i++) if (!strcmp(s, t[i].name)) { if (out) *out = t[i].u; return 1; }
    return 0;
}
// How much of tile a a window keeps in tile b (the area they share: 0 to 1, in quarters of the desktop on Fit's tiles -- exact in binary).
static double MSBDFitKept(MSBDFitUnit a, MSBDFitUnit b) {
    double w = fmin(a.x + a.w, b.x + b.w) - fmax(a.x, b.x), h = fmin(a.y + a.h, b.y + b.h) - fmax(a.y, b.y);
    return w > 0 && h > 0 ? w * h : 0;
}
// Reading order of two tiles: the one whose top-left corner is higher comes first, then the one further left (left, top-right, bottom-right; the
// quarters row by row: the default tiles' own order); from one corner, the taller and then the wider first (fill, left, top, topleft -- never two
// tiles of one arrangement, but a window's old tile may be any of them), so two different tiles are never in a tie.
static int MSBDFitReadsBefore(MSBDFitUnit a, MSBDFitUnit b) {
    if (a.y != b.y) return a.y < b.y;
    if (a.x != b.x) return a.x < b.x;
    return a.h != b.h ? a.h > b.h : a.w > b.w;
}

// Fit to Window's tiles for windows (their keys or apps, newest first: the engine's own order) when the set of windows changed; was: the tiles
// they had (window -> tile name; windows without one are new). Returns window -> tile for the first four of windows (past four no window is
// tiled -- the callers' rules for more windows stay theirs); one window fills the space; none: an empty plan.
//  - the new windows take the default arrangement's first tiles, in windows' order;
//  - every other window the tile that keeps the most of its own (MSBDFitKept, summed over them); when no window is new (the tiles only close
//    up), three windows may take the arrangement with the half on the right (MSBDFitHalfRightTiles) when that keeps more;
//  - on a tie: the default arrangement, then reading order -- the window whose old tile reads first takes the tile that reads first (two windows
//    stacked in the right column, the left half closed: the top one takes the left half) --, then windows' order (two windows with one tile).
// Neither when a window opened nor when it was last used decides any more where it goes.
static NSDictionary<NSString *, NSString *> *MSBDFitPlanKeepingPlaces(NSArray<NSString *> *windows, NSDictionary<NSString *, NSString *> *was) {
    NSMutableArray<NSString *> *w = [NSMutableArray array];   // (the windows that take part: the first four, each once)
    for (id x in windows) {
        if (![x isKindOfClass:[NSString class]] || ![(NSString *)x length] || [w containsObject:x]) continue;
        [w addObject:x];
        if (w.count == 4) break;
    }
    NSUInteger n = w.count;
    if (!n) return @{};
    if (n == 1) return @{ w[0]: @"fill" };
    int oldIx[4], newIx[4], nOld = 0, nNew = 0;
    MSBDFitUnit oldU[4];
    NSDictionary *had = [was isKindOfClass:[NSDictionary class]] ? was : nil;
    for (int i = 0; i < (int)n; i++) {
        MSBDFitUnit u;
        if (MSBDFitTileUnit(had[w[i]], &u)) { oldIx[nOld] = i; oldU[nOld] = u; nOld++; } else newIx[nNew++] = i;
    }
    for (int a = 1; a < nOld; a++) for (int b = a; b > 0; b--) {   // (the windows that had a tile, in reading order of their tiles, then windows')
        int p = b - 1;
        BOOL swap = MSBDFitReadsBefore(oldU[b], oldU[p]) || (!MSBDFitReadsBefore(oldU[p], oldU[b]) && oldIx[b] < oldIx[p]);
        if (!swap) break;
        int ti = oldIx[p]; oldIx[p] = oldIx[b]; oldIx[b] = ti;
        MSBDFitUnit tu = oldU[p]; oldU[p] = oldU[b]; oldU[b] = tu;
    }
    NSArray<NSArray<NSString *> *> *arrangements = n == 3 && !nNew ? @[MSBDFitDefaultTiles(3), MSBDFitHalfRightTiles()] : @[MSBDFitDefaultTiles(n)];
    double bestKept = -1; int bestArr = -1, bestRank[4] = {0, 0, 0, 0}, bestPerm[4] = {0, 1, 2, 3};
    for (int ai = 0; ai < (int)arrangements.count; ai++) {
        NSArray<NSString *> *tiles = arrangements[ai];
        MSBDFitUnit tu[4];
        int rank[4];
        for (int t = 0; t < (int)n; t++) MSBDFitTileUnit(tiles[t], &tu[t]);
        for (int t = 0; t < (int)n; t++) { rank[t] = 0; for (int o = 0; o < (int)n; o++) if (MSBDFitReadsBefore(tu[o], tu[t])) rank[t]++; }
        // (the new windows have taken tiles 0 ..< nNew: every order of the tiles left is tried for the others -- at most 4! = 24)
        int perm[4];
        for (int k = 0; k < nOld; k++) perm[k] = nNew + k;
        for (;;) {
            double kept = 0;
            int seq[4];
            for (int k = 0; k < nOld; k++) { kept += MSBDFitKept(oldU[k], tu[perm[k]]); seq[k] = rank[perm[k]]; }
            BOOL better = bestArr < 0 || kept > bestKept + 1e-9;
            if (!better && fabs(kept - bestKept) <= 1e-9 && ai == bestArr) {
                for (int k = 0; k < nOld; k++) if (seq[k] != bestRank[k]) { better = seq[k] < bestRank[k]; break; }
            }
            if (better) { bestKept = kept; bestArr = ai; for (int k = 0; k < nOld; k++) { bestRank[k] = seq[k]; bestPerm[k] = perm[k]; } }
            int i = nOld - 2;   // (the next order, lexicographic: the classic next permutation)
            while (i >= 0 && perm[i] > perm[i + 1]) i--;
            if (i < 0) break;
            int j = nOld - 1;
            while (perm[j] < perm[i]) j--;
            int t = perm[i]; perm[i] = perm[j]; perm[j] = t;
            for (int l = i + 1, r = nOld - 1; l < r; l++, r--) { t = perm[l]; perm[l] = perm[r]; perm[r] = t; }
        }
    }
    NSArray<NSString *> *tiles = arrangements[bestArr < 0 ? 0 : bestArr];
    NSMutableDictionary<NSString *, NSString *> *plan = [NSMutableDictionary dictionaryWithCapacity:n];
    for (int k = 0; k < nNew; k++) plan[w[newIx[k]]] = tiles[k];
    for (int k = 0; k < nOld; k++) plan[w[oldIx[k]]] = tiles[bestPerm[k]];
    return plan;
}

// A window opens on a desktop with Fit to Window on: it joins the tiles while fewer than four other windows take part there -- the tiled ones and
// the regular windows over them (the windows that opened past four); a No Fit window takes no part and is not counted. Then every one of them joins with it: the new window first, the regular ones after it, newest first -- each takes a tile as a new window
// does, the tiled ones keep their places (MSBDFitPlanKeepingPlaces). Otherwise it opens as a regular window over the tiles, and the regular windows
// stay where they are when a tile closes: only the tiled windows close up. One rule for every engine (1.8.0 engine parity, KT 3 Nov): Aerial, Zetsu
// and MilkyWay4 when a window opens (StatusBar.x DMCascadeStage) or comes from another desktop (MacSwitcher.h DMMSWFitBringHere), our Stage Manager
// engine at Fit's look (SMFitPlan.h DMSMFitTakingPart, the launch's open-in-tile with it). Before 1.8.0 Stage Manager pulled the newest regular
// window into the tiles whenever one of four closed, where the others leave it until a window opens with room for it; and Aerial / Zetsu /
// MilkyWay4 counted a No Fit window among the four, where Stage Manager does not.
// tiled, loose: the other windows of the desktop of each kind (keys or apps), newest first; the new window is in neither. Returns the windows to
// tile, in the order MSBDFitPlanKeepingPlaces takes them (the new one, the regular ones, the tiled ones), or nil: it is a regular window.
static NSArray<NSString *> *MSBDFitWhenOneOpens(NSString *fresh, NSArray<NSString *> *tiled, NSArray<NSString *> *loose) {
    if (![fresh isKindOfClass:[NSString class]] || !fresh.length) return nil;
    NSMutableArray<NSString *> *w = [NSMutableArray arrayWithObject:fresh];
    for (NSArray<NSString *> *kind in @[loose ?: @[], tiled ?: @[]])
        for (id x in kind) if ([x isKindOfClass:[NSString class]] && [(NSString *)x length] && ![w containsObject:x]) [w addObject:x];
    return w.count <= 4 ? w : nil;   // (it and at most three others)
}

// The tiles at a turn (the screen changed shape; no window joined or closed): a tiled window keeps its tile while it is there, on screen or
// minimized -- minimizing is not closing, so a minimized window comes back into its tile, laid out for the new shape. Only a window that has gone,
// is on its way out (closing, to full screen) or was left out of Fit (No Fit) leaves the tiles, and the others close up, each keeping its place.
// One rule for every engine (1.8.0 engine parity, KT 3 Nov): Aerial, Zetsu and MilkyWay4 in StatusBar.x DMRelayoutForOrientation; our Stage
// Manager engine's Fit tick keeps the tiles of minimized windows while they are all that is missing from the screen. Before 1.8.0 a turn took a
// minimized window out of Aerial's, Zetsu's and MilkyWay4's tiles: the others closed up and it came back as a regular window over them. (A window
// that opens is another matter: a minimized window gives its tile up to it, on every engine.)
static inline BOOL MSBDFitTileStaysAtTurn(BOOL there, BOOL leaving, BOOL noFit, BOOL onScreen, BOOL minimized) {
    return there && !leaving && !noFit && (onScreen || minimized);
}
