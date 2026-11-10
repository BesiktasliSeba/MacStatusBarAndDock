// DesktopArrows.h -- the arrow keys on the desktop (1.8.4.2, KT 9 Nov): the selection moves to the next icon that way, as on a Mac. The desktop's icons
// are placed freely, so there are no rows to count: the nearest icon in that direction, an icon more or less straight ahead before one off to the side.
// Plain C, so the Mac test (tools/test-desktoparrows.c) runs this very code; Desktop.h feeds it. Moves as in PreviewStep.h (MSBD_STEP_*).
#ifndef MSBD_DESKTOP_ARROWS_H
#define MSBD_DESKTOP_ARROWS_H
#include "PreviewStep.h"

// The icons' centres in reading order from where new icons start (top right): columns' worth of icons sorted by row, then from the right.
// Fills order[] with n indexes.
static inline void MSBDDesktopReadingOrder(const double *x, const double *y, long n, double cellH, long *order) {
    if (cellH < 1.0) cellH = 1.0;
    for (long i = 0; i < n; i++) order[i] = i;
    for (long i = 1; i < n; i++) {
        long k = order[i], j = i - 1;
        long rk = (long)(y[k] / cellH + 0.5);
        while (j >= 0) {
            long o = order[j], ro = (long)(y[o] / cellH + 0.5);
            if (ro < rk || (ro == rk && x[o] >= x[k])) break;
            order[j + 1] = o; j--;
        }
        order[j + 1] = k;
    }
}

// The icon an arrow moves to from icon `from` (-1: none selected, the first icon in reading order, or the last going back); -1: nothing that way.
static inline long MSBDDesktopArrowTarget(int move, const double *x, const double *y, long n, long from, double cellW, double cellH) {
    if (n <= 0) return -1;
    if (cellW < 1.0) cellW = 1.0;
    if (cellH < 1.0) cellH = 1.0;
    if (from < 0 || from >= n) {
        long best = 0;
        for (long i = 1; i < n; i++) {
            int rowI = (int)(y[i] / cellH + 0.5), rowB = (int)(y[best] / cellH + 0.5);
            int before = rowI < rowB || (rowI == rowB && x[i] > x[best]);
            if (move == MSBD_STEP_UP || move == MSBD_STEP_LEFT ? !before && !(rowI == rowB && x[i] == x[best]) : before) best = i;
        }
        return best;
    }
    int vertical = move == MSBD_STEP_UP || move == MSBD_STEP_DOWN;
    if (!vertical && move != MSBD_STEP_LEFT && move != MSBD_STEP_RIGHT) return -1;
    double sign = move == MSBD_STEP_UP || move == MSBD_STEP_LEFT ? -1.0 : 1.0;
    long best = -1; double bestScore = 0;
    for (long i = 0; i < n; i++) {
        if (i == from) continue;
        double dx = (x[i] - x[from]) / cellW, dy = (y[i] - y[from]) / cellH;
        double along = (vertical ? dy : dx) * sign, across = vertical ? dx : dy;
        if (across < 0) across = -across;
        if (along < 0.25) continue;   // (behind it, or beside it in the same row or column)
        if (across < 0.5) across = 0;   // (the same row or column, near enough)
        double score = along + across * 2.0 + (across > along ? 1000.0 : 0.0);   // (well off to the side: only if nothing is ahead)
        if (best < 0 || score < bestScore) { best = i; bestScore = score; }
    }
    return best;
}
#endif
