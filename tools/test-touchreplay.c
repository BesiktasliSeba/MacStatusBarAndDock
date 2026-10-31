// test-touchreplay.c -- Mac test of where the touch fix sends a held-back first touch again from (statusbar/TouchReplay.h): the iPad 2's pull of
// 1.7.4 k01 (its DOWN and first move at (0, 0), real points from 56.5 pt down) begins at the top edge; a tap begins where it is; the start never
// leaves the screen and is never more than 80 pt back.
#include <stdio.h>
#include <math.h>
#include "../statusbar/TouchReplay.h"
static int fails = 0, checks = 0;
static void Near(const char *what, MSBDTRPoint got, double x, double y) {
    checks++;
    if (fabs(got.x - x) > 0.6 || fabs(got.y - y) > 0.6) { fails++; printf("FAIL  %s (got %.1f, %.1f, want %.1f, %.1f)\n", what, got.x, got.y, x, y); }
    else printf("PASS  %s (%.1f, %.1f)\n", what, got.x, got.y);
}
int main(void) {
    MSBDTRPoint a = { 400, 56.5 }, b = { 400, 112 };
    // k01: DOWN at 0.000 (at (0, 0)), real reports at 0.049 (y 56.5) and 0.093 (y 112); the swipe began at y 1
    Near("the top-edge pull of k01 begins at the top edge", MSBDTouchReplayStart(a, 0.049, b, 0.093, 0.0, 1024, 768), 400, 0.5);
    // t-swipe's own pace: 16 ms reports of 27.7 pt, the first two at (0, 0): the start comes out at y 1, where the finger landed
    MSBDTRPoint c = { 400, 56.4 }, d = { 400, 84.1 };
    Near("a pull with 16 ms reports begins where the finger landed (y 1)", MSBDTouchReplayStart(c, 0.032, d, 0.048, 0.0, 1024, 768), 400, 1.0);
    MSBDTRPoint e = { 300, 400 }, f = { 300, 400 };
    Near("a still finger (a tap, a hold) begins where it is", MSBDTouchReplayStart(e, 0.030, f, 0.046, 0.0, 1024, 768), 300, 400);
    MSBDTRPoint g = { 500, 300 }, h = { 900, 300 };
    Near("a fast fling is carried back at most 80 pt", MSBDTouchReplayStart(g, 0.050, h, 0.058, 0.0, 1024, 768), 420, 300);
    MSBDTRPoint i = { 20, 700 }, j = { 60, 660 };
    // (80 pt back along the motion: (20 - 56.6, 700 + 56.6) -> x held at the left edge, y 756.6 inside the bottom one)
    Near("never past the screen's edges (a swipe in from the left edge near the bottom)", MSBDTouchReplayStart(i, 0.040, j, 0.056, 0.0, 1024, 768), 0.5, 756.6);
    MSBDTRPoint k = { 600, 760 }, l = { 600, 700 };
    Near("a swipe up from the bottom edge begins at the bottom edge", MSBDTouchReplayStart(k, 0.033, l, 0.049, 0.0, 1024, 768), 600, 767.5);
    Near("no time between the two reports: begins at the first", MSBDTouchReplayStart(a, 0.049, b, 0.049, 0.0, 1024, 768), 400, 56.5);
    Near("a DOWN after the first report (clock skew): begins at the first", MSBDTouchReplayStart(a, 0.049, b, 0.093, 0.060, 1024, 768), 400, 56.5);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
