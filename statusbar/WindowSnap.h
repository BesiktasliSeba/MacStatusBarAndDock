// WindowSnap.h -- window snapping on every engine (1.7.3 item 3, KT 31 Oct: "option 1"), plain C on CoreGraphics so the Mac test
// (tools/test-windowsnap.c) runs this very code. StatusBar.x calls it where each engine ends a move or a resize by hand: Aerial (3.0 and 5.x), Zetsu,
// MilkyWay4, and our Stage Manager engine's moves on 16-18 and resizes on 16 (17 and 18 snap a resized side themselves: left as Apple has it).
// What it copies -- Stage Manager on 17.5.1 / 18.5, measured 31 Oct (release-1.7.3.md, "v173 window snapping"):
//  - Moves: SpringBoard's auto-layout pass snaps a window when it is put down (-[SBContinuousExposeAutoLayoutController
//    snapPositionToNearestEdgesIfNecessaryForSpace:stageArea:configuration:]): each edge to the stage area's edge, and the window in front to every
//    other window's edges -- the same side lined up, or the facing side one gap away (stageInterItemSpacing) -- within the snap padding's edgePadding,
//    45 pt (-[SBSwitcherChamoisSnapPaddingSettings initWithDefaultValues], 18.5). Nothing moves during the drag: the window jumps when it is let go.
//  - Resizes: the dragged side is drawn rubber-banded towards the same kind of place and lands on it when the finger lifts, within 10 pt of it
//    (18.5 by real drags: 9 pt away snapped, 10 did not).
// Ours: the same edges and the same two distances; the gap between neighbours is our layouts' 6 pt (StatusBar.x kLayoutTileGap) instead of Stage
// Manager's 10, so a snapped window lines up with the Window menu's tiles; the area is the desktop every layout uses (the screen's sides, right
// under the menu bar -- whatever Menu Bar Size makes it -- and down to the Dock line). Never into the menu bar, never further under the Dock than
// the window already was, never further off the screen's sides, never smaller than a window may be (WindowMinSize.h). A window counts as a
// neighbour on an axis only when it is level with this one on the other axis (within the gap and the distance): a window far below does not pull
// a side. Centres are not snapped (Stage Manager's pass also centres a lone window and lines up centres: KT asked for edges -- a question for KT).
#ifndef MSBD_WINDOW_SNAP_H
#define MSBD_WINDOW_SNAP_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <math.h>

#define kMSBDSnapMoveDistance 45.0     // a move: Stage Manager's edgePadding (17.5.1 and 18.5)
#define kMSBDSnapResizeDistance 10.0   // a resized side: Stage Manager's resize step on 18.5, measured
#define kMSBDSnapGap 6.0               // between neighbours: our layouts' tile gap

enum { MSBDSnapLeft = 1, MSBDSnapRight = 2, MSBDSnapTop = 4, MSBDSnapBottom = 8, MSBDSnapMove = 15 };   // (a move: every side, together)
// What a side snapped to (the log's words): nothing, the desktop's edge, a neighbour's side lined up, next to a neighbour (the gap between).
enum { MSBDSnapNone = 0, MSBDSnapToArea = 1, MSBDSnapToAligned = 2, MSBDSnapToNext = 3 };
typedef struct { int x, y; } MSBDSnapWhy;

// (one axis: lo..hi is the window, olo..ohi a neighbour on it; a neighbour counts when it is level with the window on the other axis)
static inline bool MSBDSnapLevel(CGFloat lo, CGFloat hi, CGFloat olo, CGFloat ohi, CGFloat reach) { return olo <= hi + reach && ohi >= lo - reach; }

// A move: the shift on one axis that puts a side on its nearest place within dist, or 0. lo..hi: the window; alo..ahi: the area; nb: the neighbours
// (lo, hi pairs on this axis, already level on the other), n of them. forbidLo: the shift may never take lo below alo (the menu bar); a shift
// outwards past the area's sides is refused (never further off the screen, never further under the Dock).
static inline CGFloat MSBDSnapShift(CGFloat lo, CGFloat hi, CGFloat alo, CGFloat ahi, const CGFloat *nb, int n, CGFloat gap, CGFloat dist, bool forbidLo, int *why) {
    CGFloat best = 0, bestAbs = INFINITY; int kind = MSBDSnapNone;
    #define MSBD_SNAP_TRY(d, k) do { CGFloat dd = (d), ad = fabs(dd); \
        bool outLo = lo + dd < alo - 0.5 && dd < 0, outHi = hi + dd > ahi + 0.5 && dd > 0, intoBar = forbidLo && lo + dd < alo - 0.5; \
        if (ad <= dist && ad < bestAbs && !outLo && !outHi && !intoBar) { best = dd; bestAbs = ad; kind = (k); } } while (0)
    MSBD_SNAP_TRY(alo - lo, MSBDSnapToArea);
    MSBD_SNAP_TRY(ahi - hi, MSBDSnapToArea);
    for (int i = 0; i < n; i++) {
        CGFloat olo = nb[2 * i], ohi = nb[2 * i + 1];
        MSBD_SNAP_TRY(olo - lo, MSBDSnapToAligned);         // (the same side lined up)
        MSBD_SNAP_TRY(ohi - hi, MSBDSnapToAligned);
        MSBD_SNAP_TRY(ohi + gap - lo, MSBDSnapToNext);      // (after the neighbour, the gap between)
        MSBD_SNAP_TRY(olo - gap - hi, MSBDSnapToNext);      // (before it)
    }
    #undef MSBD_SNAP_TRY
    if (why) *why = kind;
    return bestAbs <= dist ? best : 0;
}

// A resize: where one dragged side ends (the low side when low, else the high side), or where it is when nothing is within dist. other: the side
// that stays; minLen: the window's smallest length on this axis; the same places as a move, the same refusals.
static inline CGFloat MSBDSnapSide(CGFloat side, bool low, CGFloat other, CGFloat alo, CGFloat ahi, const CGFloat *nb, int n, CGFloat gap, CGFloat dist,
                                   CGFloat minLen, bool forbidLo, int *why) {
    CGFloat best = side, bestAbs = INFINITY; int kind = MSBDSnapNone;
    #define MSBD_SIDE_TRY(p, k) do { CGFloat pp = (p), ad = fabs(pp - side); \
        bool small = low ? other - pp < minLen - 0.01 : pp - other < minLen - 0.01; \
        bool out = low ? (pp < alo - 0.5 && pp < side) : (pp > ahi + 0.5 && pp > side); \
        bool intoBar = low && forbidLo && pp < alo - 0.5; \
        if (ad <= dist && ad < bestAbs && !small && !out && !intoBar) { best = pp; bestAbs = ad; kind = (k); } } while (0)
    MSBD_SIDE_TRY(low ? alo : ahi, MSBDSnapToArea);
    for (int i = 0; i < n; i++) {
        CGFloat olo = nb[2 * i], ohi = nb[2 * i + 1];
        if (low) { MSBD_SIDE_TRY(olo, MSBDSnapToAligned); MSBD_SIDE_TRY(ohi + gap, MSBDSnapToNext); }
        else { MSBD_SIDE_TRY(ohi, MSBDSnapToAligned); MSBD_SIDE_TRY(olo - gap, MSBDSnapToNext); }
    }
    #undef MSBD_SIDE_TRY
    if (why) *why = kind;
    return best;
}

// The frame a window ends at when a move (how = MSBDSnapMove) or a resize (how = the dragged sides) by hand ends at f. others: the other windows on
// screen on this desktop, n of them (at most 32 are looked at); area: the desktop (the screen's sides, under the menu bar, down to the Dock line);
// dist: kMSBDSnapMoveDistance / kMSBDSnapResizeDistance; minSize: the smallest the window may be (a resize never snaps it smaller). Each axis on its
// own; f as it is where nothing is within reach. why (may be NULL): what each axis snapped to.
static inline CGRect MSBDSnapFrame(CGRect f, unsigned how, const CGRect *others, int n, CGRect area, CGFloat gap, CGFloat dist, CGSize minSize, MSBDSnapWhy *why) {
    MSBDSnapWhy w = { MSBDSnapNone, MSBDSnapNone };
    if (why) *why = w;
    if (CGRectIsNull(f) || CGRectIsEmpty(f) || CGRectIsNull(area) || CGRectIsEmpty(area) || !(dist > 0) || !how) return f;
    if (n > 32) n = 32;
    if (n < 0 || !others) n = 0;
    CGFloat nx[64], ny[64]; int cx = 0, cy = 0;
    CGFloat reach = gap + dist;
    for (int i = 0; i < n; i++) {
        CGRect o = others[i];
        if (CGRectIsNull(o) || CGRectIsEmpty(o) || !isfinite(o.origin.x) || !isfinite(o.origin.y)) continue;
        if (MSBDSnapLevel(CGRectGetMinY(f), CGRectGetMaxY(f), CGRectGetMinY(o), CGRectGetMaxY(o), reach)) { nx[2 * cx] = CGRectGetMinX(o); nx[2 * cx + 1] = CGRectGetMaxX(o); cx++; }
        if (MSBDSnapLevel(CGRectGetMinX(f), CGRectGetMaxX(f), CGRectGetMinX(o), CGRectGetMaxX(o), reach)) { ny[2 * cy] = CGRectGetMinY(o); ny[2 * cy + 1] = CGRectGetMaxY(o); cy++; }
    }
    CGFloat alx = CGRectGetMinX(area), ahx = CGRectGetMaxX(area), aly = CGRectGetMinY(area), ahy = CGRectGetMaxY(area);
    if ((how & MSBDSnapMove) == MSBDSnapMove) {
        CGFloat dx = MSBDSnapShift(CGRectGetMinX(f), CGRectGetMaxX(f), alx, ahx, nx, cx, gap, dist, false, &w.x);
        CGFloat dy = MSBDSnapShift(CGRectGetMinY(f), CGRectGetMaxY(f), aly, ahy, ny, cy, gap, dist, true, &w.y);
        if (why) *why = w;
        return CGRectOffset(f, dx, dy);
    }
    CGFloat x0 = CGRectGetMinX(f), x1 = CGRectGetMaxX(f), y0 = CGRectGetMinY(f), y1 = CGRectGetMaxY(f);
    if (how & MSBDSnapLeft) x0 = MSBDSnapSide(x0, true, x1, alx, ahx, nx, cx, gap, dist, minSize.width, false, &w.x);
    else if (how & MSBDSnapRight) x1 = MSBDSnapSide(x1, false, x0, alx, ahx, nx, cx, gap, dist, minSize.width, false, &w.x);
    if (how & MSBDSnapTop) y0 = MSBDSnapSide(y0, true, y1, aly, ahy, ny, cy, gap, dist, minSize.height, true, &w.y);
    else if (how & MSBDSnapBottom) y1 = MSBDSnapSide(y1, false, y0, aly, ahy, ny, cy, gap, dist, minSize.height, false, &w.y);
    if (why) *why = w;
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

// 16's resize step (SMResizeAnchor.h DMSMRASnapEnd) finds the window being resized among the stage's windows by its held sides: every side that is not
// dragged (how) still where the drag began (start), within a point; the dragged sides are wherever the finger has them now.
static inline bool MSBDSnapHeldSidesMatch(CGRect now, CGRect start, unsigned how) {
    return ((how & MSBDSnapLeft) || fabs(CGRectGetMinX(now) - CGRectGetMinX(start)) < 1.0) && ((how & MSBDSnapRight) || fabs(CGRectGetMaxX(now) - CGRectGetMaxX(start)) < 1.0)
        && ((how & MSBDSnapTop) || fabs(CGRectGetMinY(now) - CGRectGetMinY(start)) < 1.0) && ((how & MSBDSnapBottom) || fabs(CGRectGetMaxY(now) - CGRectGetMaxY(start)) < 1.0);
}

// The log's words for what a side snapped to.
static inline const char *MSBDSnapWhyText(int k) {
    return k == MSBDSnapToArea ? "the desktop's edge" : k == MSBDSnapToAligned ? "a window's side" : k == MSBDSnapToNext ? "next to a window" : "-";
}
#endif
