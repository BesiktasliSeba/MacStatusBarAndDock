// test-smfront.c -- Mac test of which Stage Manager window a finger's resize corner and an app's launch are for (statusbar/SMFrontRule.h, used by
// SMResizeEdges.h DMSMTouchCornersInstall and StatusBar.x DMSMItemInFront): 1.7.9.2, GitHub #10 follow-up.
//  - Stage Manager's own pick for a finger (read on 16.3.1 20D67 and 17.5.1: -[SBFluidSwitcherGestureManager
//    _shouldLiveResizeItemContainerGestureWithTouch:receiveTouch:], -[SBLiveWindowResizeGestureWorkspaceTransaction _beginWithGesture:] and
//    -_shouldBeginLiveWindowResizeGesture: all ask -[SBFluidSwitcherViewController _itemContainerNearestLocation:environment:
//    prioritizeForegroundedItemContainers:]): the windows not marked occluded, sorted by the finger's distance to their nearest corner; the first
//    one takes the touch when the finger is in one of its allowed corners' squares (side 50 pt + the screen edge padding, centred 10 pt in from the
//    corner). Modelled here as read, once as Apple has it and once with our rule (a window covered at the finger by one in front counts occluded).
//  - A launch's "in front": newer than every other window (a tie is not in front).
#include <stdio.h>
#include <math.h>
#include "../statusbar/SMFrontRule.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }

typedef struct { const char *name; CGRect frame; int occluded; } Win;   // a window card, front to back in the array (index 0 in front)
enum { kBL = 4, kBR = 8 };   // (UIRectCorner: bottom left, bottom right -- with our handles a finger may take both, StatusBar.x allowedTouchResizeCorners)
static const double kSide = 50.0 + 10.0;   // (50 pt x the sizing factor 1, plus a screen edge padding of 10 pt)

static double CornerDistance(CGRect f, CGPoint p) {   // (the sort's key: the finger to the window's nearest corner)
    double xs[2] = { CGRectGetMinX(f), CGRectGetMaxX(f) }, ys[2] = { CGRectGetMinY(f), CGRectGetMaxY(f) }, best = INFINITY;
    for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) best = fmin(best, hypot(xs[i] - p.x, ys[j] - p.y));
    return best;
}
static int InCornerSquare(CGRect f, CGPoint p, int corners) {   // (the touch check on the window picked)
    CGPoint c[2] = { { CGRectGetMinX(f) + 10.0, CGRectGetMaxY(f) - 10.0 }, { CGRectGetMaxX(f) - 10.0, CGRectGetMaxY(f) - 10.0 } };
    int bits[2] = { kBL, kBR };
    for (int i = 0; i < 2; i++) {
        if (!(corners & bits[i])) continue;
        CGRect sq = CGRectMake(c[i].x - kSide / 2, c[i].y - kSide / 2, kSide, kSide);
        if (CGRectContainsPoint(sq, p)) return bits[i];
    }
    return 0;
}
// The window a finger at p resizes (-1: none, the touch goes to the app under it). ours: our rule's occluded answer (MSBDSMCoveredAt over the windows
// in front of each one).
static int Pick(const Win *w, int n, CGPoint p, int ours, int *corner) {
    int best = -1; double bd = INFINITY;
    for (int i = 0; i < n; i++) {
        int occ = w[i].occluded;
        if (ours && !occ) {
            CGRect fronts[16]; int m = 0;
            for (int j = 0; j < i && m < 16; j++) fronts[m++] = w[j].frame;
            occ = MSBDSMCoveredAt(p, fronts, m);
        }
        if (occ) continue;   // (prioritizeForegroundedItemContainers: YES -- occluded ones passed over)
        double d = CornerDistance(w[i].frame, p);
        if (d < bd) { bd = d; best = i; }
    }
    if (best < 0) return -1;
    int c = InCornerSquare(w[best].frame, p, kBL | kBR);
    if (corner) *corner = c;
    return c ? best : -1;
}

int main(void) {
    // ---- the reporter's case, as reproduced on the 17.5 (17.5.1): Settings big in front, Tips small behind it, fully covered
    Win two[2] = { { "Settings", { { 77, 164 }, { 870.4, 983.5 } }, 0 }, { "Tips", { { 297, 410 }, { 430, 410 } }, 0 } };
    CGPoint underBR = { 724, 817 }, underBL = { 300, 817 };
    int corner = 0;
    Expect("Apple's pick (as read): a drag on Settings over Tips' bottom-right corner resizes Tips -- the bug", Pick(two, 2, underBR, 0, &corner) == 1 && corner == kBR);
    Expect("  ... and over its bottom-left corner (our handles: both bottom corners take a finger) resizes Tips too", Pick(two, 2, underBL, 0, &corner) == 1 && corner == kBL);
    Expect("ours: the same drag is Settings' own touch (no window resized, the app gets it)", Pick(two, 2, underBR, 1, NULL) == -1);
    Expect("  ... the bottom-left one too", Pick(two, 2, underBL, 1, NULL) == -1);
    CGPoint ownBR = { 77 + 870.4 - 6, 164 + 983.5 - 6 }, ownBL = { 77 + 6, 164 + 983.5 - 6 }, outBR = { 77 + 870.4 + 8, 164 + 983.5 + 8 };
    Expect("ours: Settings' own bottom-right corner still resizes Settings", Pick(two, 2, ownBR, 1, &corner) == 0 && corner == kBR);
    Expect("ours: Settings' own bottom-left corner still resizes Settings", Pick(two, 2, ownBL, 1, &corner) == 0 && corner == kBL);
    Expect("ours: just outside Settings' corner (its zone reaches out) still resizes Settings", Pick(two, 2, outBR, 1, &corner) == 0 && corner == kBR);
    // ---- a covered corner close to the front window's own corner: Apple took the nearer, covered one
    Win close[2] = { { "front", { { 100, 100 }, { 600, 600 } }, 0 }, { "back", { { 400, 400 }, { 285, 285 } }, 0 } };   // (back's BR at 685,685; front's at 700,700)
    CGPoint between = { 688, 688 };
    Expect("Apple's pick: between the front window's corner and a covered corner 15 pt inside it, the covered one resizes", Pick(close, 2, between, 0, NULL) == 1);
    Expect("ours: the front window's own corner resizes", Pick(close, 2, between, 1, &corner) == 0 && corner == kBR);
    // ---- a back window's corner that shows (outside the front window) still takes the finger
    Win shows[2] = { { "front", { { 100, 100 }, { 500, 500 } }, 0 }, { "back", { { 450, 450 }, { 300, 300 } }, 0 } };   // (back's BR at 750,750, out in the open)
    CGPoint open = { 745, 745 };
    Expect("ours: a back window's corner out in the open still resizes it", Pick(shows, 2, open, 1, &corner) == 1 && corner == kBR);
    Expect("  ... as Apple has it", Pick(shows, 2, open, 0, &corner) == 1 && corner == kBR);
    CGPoint backBL = { 452, 748 };   // (back's bottom-left corner at 450,750 -- outside the front window too: front ends at y 600)
    Expect("ours: its bottom-left corner below the front window resizes it as well", Pick(shows, 2, backBL, 1, &corner) == 1 && corner == kBL);
    // ---- three windows: the middle one covers the back one's corner; the front one is elsewhere
    Win three[3] = { { "front", { { 600, 100 }, { 300, 300 } }, 0 }, { "middle", { { 100, 300 }, { 500, 500 } }, 0 }, { "back", { { 200, 400 }, { 200, 200 } }, 0 } };
    CGPoint inMiddle = { 396, 596 };   // (back's BR at 400,600, under the middle window)
    Expect("Apple's pick: a finger on the middle window over the back one's corner resizes the back one", Pick(three, 3, inMiddle, 0, NULL) == 2);
    Expect("ours: it is the middle window's touch", Pick(three, 3, inMiddle, 1, NULL) == -1);
    CGPoint midBR = { 596, 796 };
    Expect("ours: the middle window's own corner resizes it", Pick(three, 3, midBR, 1, &corner) == 1 && corner == kBR);
    // ---- Stage Manager's own occluded mark keeps working
    Win marked[2] = { { "front", { { 100, 100 }, { 500, 500 } }, 0 }, { "back", { { 500, 500 }, { 200, 200 } }, 1 } };
    CGPoint backBR = { 695, 695 };
    Expect("a window Stage Manager marks occluded is passed over, ours or not", Pick(marked, 2, backBR, 0, NULL) == -1 && Pick(marked, 2, backBR, 1, NULL) == -1);
    // ---- the rule itself
    CGRect r[2] = { { { 0, 0 }, { 100, 100 } }, CGRectNull };
    Expect("covered: inside a window in front", MSBDSMCoveredAt(CGPointMake(50, 50), r, 2));
    Expect("not covered: outside every window in front (a null area is no window)", !MSBDSMCoveredAt(CGPointMake(150, 50), r, 2));
    Expect("not covered: no window in front", !MSBDSMCoveredAt(CGPointMake(50, 50), r, 0));
    Expect("covered: the window in front's top-left point is its own", MSBDSMCoveredAt(CGPointMake(0, 0), r, 1));
    Expect("not covered: its far edge is not (half-open, as CGRectContainsPoint)", !MSBDSMCoveredAt(CGPointMake(100, 50), r, 1));
    // ---- a launch's "in front"
    long long t1[2] = { 178, 177 }, t2[2] = { 178, 178 }, t3[1] = { 5 }, t4[3] = { 10, 30, 20 };
    Expect("in front: the newest window", MSBDSMNewestAlone(t1, 2, 0));
    Expect("not in front: an older window", !MSBDSMNewestAlone(t1, 2, 1));
    Expect("a tie (16.3.1 can leave one): neither window is in front", !MSBDSMNewestAlone(t2, 2, 0) && !MSBDSMNewestAlone(t2, 2, 1));
    Expect("a lone window is in front", MSBDSMNewestAlone(t3, 1, 0));
    Expect("three windows: only the newest", MSBDSMNewestAlone(t4, 3, 1) && !MSBDSMNewestAlone(t4, 3, 0) && !MSBDSMNewestAlone(t4, 3, 2));
    Expect("not in the stage (index out of range) or no times: not in front", !MSBDSMNewestAlone(t1, 2, -1) && !MSBDSMNewestAlone(t1, 2, 2) && !MSBDSMNewestAlone(NULL, 0, 0));
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
