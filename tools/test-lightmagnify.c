// test-lightmagnify.c: Magnify Traffic Lights' layout and pick rule (common/LightMagnify.h): the pill grows to the right and down from the lights'
// top-left, stays inside its box, the light under the finger is the biggest, a lift picks the light it is on and nothing off the pill.
#include <stdio.h>
#include "../common/LightMagnify.h"
static int fails = 0, n = 0;
static void check(const char *what, int ok) { n++; if (!ok) { fails++; printf("FAIL  %s\n", what); } else printf("PASS  %s\n", what); }
int main(void) {
    // A window's lights: 12 pt dots, the first one's top-left at (8, 8), the window 600 x 400.
    MSBDLightMag L = MSBDLightMagLayout(3, 8, 8, 12, 14, 1, 0, 0, 600, 400);
    check("every light grows at least 1.5 times", L.size[0] >= 18 && L.size[1] >= 18 && L.size[2] >= 18);
    check("the light under the finger (red) is the biggest", L.size[0] > L.size[1] && L.size[1] > L.size[2]);
    check("the biggest is at most twice its size", L.size[0] <= 24.0001);
    check("the pill starts at or right of the window's left edge", L.pillX >= 0);
    check("the pill starts at or below the window's top edge", L.pillY >= 0);
    check("lights in order, not overlapping", L.cx[0] + L.size[0] / 2 <= L.cx[1] - L.size[1] / 2 && L.cx[1] + L.size[1] / 2 <= L.cx[2] - L.size[2] / 2);
    check("all lights inside the pill", L.cx[0] - L.size[0] / 2 >= L.pillX && L.cx[2] + L.size[2] / 2 <= L.pillX + L.pillW);
    check("a lift on red picks red", MSBDLightMagPick(L, L.cx[0], L.cy) == 0);
    check("a lift on yellow picks yellow", MSBDLightMagPick(L, L.cx[1], L.cy) == 1);
    check("a lift on green picks green", MSBDLightMagPick(L, L.cx[2], L.cy) == 2);
    check("a lift between yellow and green picks the nearer", MSBDLightMagPick(L, L.cx[1] + L.size[1] / 2 + 1, L.cy) == 1);
    check("a lift far below the pill picks nothing", MSBDLightMagPick(L, L.cx[1], L.pillY + L.pillH + 40) == -1);
    check("a lift far right of the pill picks nothing", MSBDLightMagPick(L, L.pillX + L.pillW + 40, L.cy) == -1);
    check("a lift just off the pill (slop) still picks", MSBDLightMagPick(L, L.cx[2], L.pillY + L.pillH + 5) == 2);
    // The finger slid onto green: green is now the biggest.
    MSBDLightMag G = MSBDLightMagLayout(3, 8, 8, 12, L.cx[2], 1, 0, 0, 600, 400);
    check("sliding to green makes green the biggest", G.size[2] > G.size[1] && G.size[2] > G.size[0]);
    // Lights tight in the corner: the first dot at (1, 1): the pill is shifted inside, never past the edges.
    MSBDLightMag C = MSBDLightMagLayout(3, 1, 1, 12, 7, 1, 0, 0, 600, 400);
    check("in the corner: the pill stays inside (left)", C.pillX >= -0.0001);
    check("in the corner: the pill stays inside (top)", C.pillY >= -0.0001);
    // A low box (a 24 pt menu bar): the pill is made smaller to fit, never smaller than the lights already are.
    MSBDLightMag B = MSBDLightMagLayout(3, 8, 6, 12, 14, 1, 0, 0, 1000, 24);
    check("a low bar: the pill fits its height", B.pillH <= 24.0001);
    check("a low bar: no light smaller than its own size", B.size[0] >= 12 - 0.0001 && B.size[1] >= 12 - 0.0001 && B.size[2] >= 12 - 0.0001);
    check("a low bar: inside the bar", B.pillY >= -0.0001 && B.pillY + B.pillH <= 24.0001);
    // A window close to the screen's right edge, small: the pill is shifted left into the box.
    MSBDLightMag R = MSBDLightMagLayout(3, 8, 8, 12, 14, 1, 0, 0, 70, 400);
    check("a narrow box: the pill stays within its right edge", R.pillX + R.pillW <= 70.0001 && R.pillX >= -0.0001);
    // Two lights (green hidden).
    MSBDLightMag T = MSBDLightMagLayout(2, 8, 8, 12, 14, 1, 0, 0, 600, 400);
    check("two lights: green is never picked", MSBDLightMagPick(T, T.pillX + T.pillW, T.cy) == 1 && T.n == 2);
    // No finger yet (the pill as it opens): all the same size.
    MSBDLightMag O = MSBDLightMagLayout(3, 8, 8, 12, 0, 0, 0, 0, 600, 400);
    check("no finger: the lights are even", fabs(O.size[0] - O.size[2]) < 0.0001);
    // Relative pick (m05): a finger held on green where green is now (its own place, x 8 + 2 * 20 + 6 = 54) and lifted without moving picks green.
    { double fx = 54.0; double vx = MSBDLightMagVirtualX(3, 2, 8, 8, 12, fx, 0, 0, 600, 400);
      MSBDLightMag V = MSBDLightMagLayout(3, 8, 8, 12, vx, 1, 0, 0, 600, 400);
      check("held on green: green is drawn the biggest", V.size[2] > V.size[1] && V.size[2] > V.size[0]);
      check("held on green and lifted: green", MSBDLightMagPick(V, vx, V.cy) == 2);
      double off = vx - fx;   // a slide 35 pt to the left from there
      MSBDLightMag W = MSBDLightMagLayout(3, 8, 8, 12, fx - 35 + off, 1, 0, 0, 600, 400);
      check("held on green, slid one light left: yellow", MSBDLightMagPick(W, fx - 35 + off, W.cy) == 1);
      MSBDLightMag Z = MSBDLightMagLayout(3, 8, 8, 12, fx - 70 + off, 1, 0, 0, 600, 400);
      check("held on green, slid two lights left: red", MSBDLightMagPick(Z, fx - 70 + off, Z.cy) == 0); }
    { double vx = MSBDLightMagVirtualX(3, 0, 8, 8, 12, 14, 0, 0, 600, 400);
      MSBDLightMag V = MSBDLightMagLayout(3, 8, 8, 12, vx, 1, 0, 0, 600, 400);
      check("held on red and lifted: red", MSBDLightMagPick(V, vx, V.cy) == 0 && V.size[0] > V.size[1]); }
    printf("test-lightmagnify: %d pass, %d fail\n", n - fails, fails);
    return fails ? 1 : 0;
}
