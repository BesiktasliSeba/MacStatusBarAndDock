// test-lightmagnify.c: Magnify Traffic Lights' layout and pick rule (common/LightMagnify.h): the pill grows to the right and down from the lights'
// top-left, stays inside its box, the light under the finger is the biggest, a lift picks the light it is on and nothing off the pill.
// 1.8.8 (KT 19 Nov, "Lets also make Traffic light magnification apply to cursor too but less"): the pointer's rule after the finger's checks, P1-P14
// (the lights grown where they are: the one under the pointer 1.4x, its neighbours a little, each kept inside its own button and its window, only
// while the pointer is inside a light's own button), then T1-T15 (the pointer's state: a hover's end, a click in either order with UIKit's cancel,
// a finger, -apply's look, UIKit's idle cancel held while the pointer rests, a move off the lights with nothing on them answered at once, SpringBoard's
// touches mattering only to a set with something of the pointer's on it, and D48: the hold ends when the pointer fades, as pointeruid says).
// MSBD_LIGHTMAG_H: another copy of the rule (the made-to-fail copies).
#include <stdio.h>
#include <string.h>
#ifdef MSBD_LIGHTMAG_H
#include MSBD_LIGHTMAG_H
#else
#include "../common/LightMagnify.h"
#endif
static int fails = 0, n = 0;
static void check(const char *what, int ok) { n++; if (!ok) { fails++; printf("FAIL  %s\n", what); } else printf("PASS  %s\n", what); }
// A Stage Manager title bar: 20 pt buttons at x 8-68, y 2-22 of the 24 pt bar, 12 pt dots at their centres (18, 38, 58; y 12), in a 600 x 400
// window whose top is the bar's (the box 1.5 pt in: kMSBDLightPtrMargin).
static MSBDLightRow smRow(void) {
    MSBDLightRow r; memset(&r, 0, sizeof r); r.n = 3;
    for (int i = 0; i < 3; i++) {
        r.cx[i] = 18 + 20 * i; r.cy[i] = 12; r.size[i] = 12; r.usable[i] = 1;
        r.cellMinX[i] = 8 + 20 * i; r.cellMaxX[i] = 28 + 20 * i; r.cellMinY[i] = 2; r.cellMaxY[i] = 22;
    }
    r.boxMinX = 1.5; r.boxMinY = 1.5; r.boxMaxX = 598.5; r.boxMaxY = 398.5;
    return r;
}
static int biggest(const double *s, int k) { int b = 0; for (int i = 1; i < k; i++) if (s[i] > s[b]) b = i; return b; }
static int allOne(const double *s, int k) { for (int i = 0; i < k; i++) if (fabs(s[i] - 1.0) > 1e-12) return 0; return 1; }
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

    // ---- the pointer (1.8.8): one light's size (MSBDLightPtrScale: the pointer's x, the light's centre and size, the pitch, its room in its button
    //      and in its window) and a row of them (MSBDLightPtrScales)
    double red = MSBDLightPtrScale(18, 18, 12, 20, 10, 10.5), yel = MSBDLightPtrScale(18, 38, 12, 20, 10, 10.5), grn = MSBDLightPtrScale(18, 58, 12, 20, 10, 10.5);
    check("P1 the pointer on red (a Stage Manager bar): red 1.40", fabs(red - 1.40) < 1e-9);
    check("P2 less than the finger: below its smallest light (1.5x), and 40 % of its growth under it", red < kMSBDLightMagGrow
          && fabs((red - 1.0) / (kMSBDLightMagGrow + kMSBDLightMagSwell - 1.0) - 0.40) < 1e-9);
    check("P3 a neighbour a little (1.10-1.20), the far one under 1.02 and never below 1; red > yellow > green", yel >= 1.10 && yel <= 1.20 && grn < 1.02 && grn >= 1.0 && red > yel && yel > grn);
    check("P4 the pointer half way between two lights: they are the same size", fabs(MSBDLightPtrScale(28, 18, 12, 20, 10, 10.5) - MSBDLightPtrScale(28, 38, 12, 20, 10, 10.5)) < 1e-9);
    { MSBDLightRow r = smRow(); double s[kMSBDLightMagMaxDots]; int seen = 1, under = 1, apart = 1, steps = 0;
      for (double x = 8.5; x <= 67.5 + 1e-9; x += 0.5) {
          int u = MSBDLightPtrScales(&r, x, 12, s), want = (int)floor((x - 8.0) / 20.0);
          steps++;
          if (u != want) under = 0;
          if (fabs(x - 28.0) > 0.25 && fabs(x - 48.0) > 0.25 && biggest(s, 3) != want) seen = 0;
          for (int i = 0; i < 2; i++) if (r.size[i] * s[i] / 2.0 + r.size[i + 1] * s[i + 1] / 2.0 >= 20.0 - 4.0) apart = 0;
      }
      check("P5 the pointer swept along the row (x 8.5-67.5, 0.5 pt steps): the biggest is the button a click hits, at every step", seen && under && steps == 119);
      check("P6 ... and two neighbours never touch (at least 4 pt apart)", apart); }
    { MSBDLightRow r = smRow(); double s[kMSBDLightMagMaxDots];
      int ring = MSBDLightPtrScales(&r, 38, 1, s) < 0 && allOne(s, 3);              // (y 0-2: SpringBoard's top resize band over a Stage Manager window)
      ring = ring && MSBDLightPtrScales(&r, 38, 23, s) < 0 && allOne(s, 3);         // (under the buttons: the bar's tap and drag)
      ring = ring && MSBDLightPtrScales(&r, 7, 12, s) < 0 && allOne(s, 3) && MSBDLightPtrScales(&r, 69, 12, s) < 0 && allOne(s, 3);
      check("P5b only inside a light's own button: the ring round them (the symbols' hover band, the top resize band, the bar's tap and drag) grows nothing", ring);
      // MilkyWay4's own buttons where they are not at its default: 16 pt wide, 24 pt apart (x 4, 28, 52), a 28 pt bar, dots centred
      MSBDLightRow m = r; for (int i = 0; i < 3; i++) { m.cellMinX[i] = 4 + 24 * i; m.cellMaxX[i] = 20 + 24 * i; m.cellMinY[i] = 0; m.cellMaxY[i] = 28; m.cx[i] = 12 + 24 * i; m.cy[i] = 14; }
      int gap = MSBDLightPtrScales(&m, 22, 14, s) < 0 && allOne(s, 3);
      int on = MSBDLightPtrScales(&m, 36, 14, s) == 1 && biggest(s, 3) == 1 && s[1] <= 16.0 / 12.0 + 1e-9;
      check("P5b ... MilkyWay4's own 16 pt buttons: nothing in the gap between two, yellow the biggest on it and no bigger than its button", gap && on); }
    { double s = MSBDLightPtrScale(36, 36, 12, 24, 8, 100);
      check("P7 the cap of its own button: MilkyWay4's 16 pt button (room 8) gives at most 1.3334, drawn at most 16 pt", s <= 1.3334 && 12 * s <= 16 + 1e-9 && s > 1.3); }
    check("P8 the cap of its window: a dot 0.5 pt under the window's top (room 6.5 - 1.5) stays 1.0, never past the edge; at room 7.5 - 1.5 exactly 1.0",
          fabs(MSBDLightPtrScale(18, 18, 12, 20, 10, 6.5 - kMSBDLightPtrMargin) - 1.0) < 1e-12 && fabs(MSBDLightPtrScale(18, 18, 12, 20, 10, 7.5 - kMSBDLightPtrMargin) - 1.0) < 1e-12);
    check("P9 never below its own size: rooms 3 and -2 give 1.0", MSBDLightPtrScale(18, 18, 12, 20, 3, 10) == 1.0 && MSBDLightPtrScale(18, 18, 12, 20, 10, -2) == 1.0);
    { double s = MSBDLightPtrScale(40, 40, 15, 25, 12.5, 100);
      check("P10 the bar's lights at Large (15 pt dots, 25 pt cells): 1.40, inside its cell", fabs(s - 1.40) < 1e-9 && s <= 25.0 / 15.0); }
    { MSBDLightRow r = smRow(); double s[kMSBDLightMagMaxDots];
      for (int i = 0; i < 3; i++) { r.cx[i] = 58 - 20 * i; r.cellMinX[i] = 48 - 20 * i; r.cellMaxX[i] = 68 - 20 * i; }   // (right to left: red at the right)
      check("P11 right to left (red at the right, the pointer on it): red is the biggest", MSBDLightPtrScales(&r, 58, 12, s) == 0 && biggest(s, 3) == 0 && fabs(s[0] - 1.40) < 1e-9); }
    { int far = fabs(MSBDLightPtrScale(118, 18, 12, 20, 10, 10.5) - 1.0) < 1e-6;
      int odd = MSBDLightPtrScale(NAN, 18, 12, 20, 10, 10.5) == 1.0 && MSBDLightPtrScale(18, 18, 0, 20, 10, 10.5) == 1.0 && MSBDLightPtrScale(18, 18, 12, 0, 10, 10.5) == 1.0
                && MSBDLightPtrScale(18, NAN, 12, 20, 10, 10.5) == 1.0 && MSBDLightPtrScale(18, 18, 12, 20, NAN, 10.5) == 1.0;
      check("P12 100 pt away: 1.0; a place that is not a number, size 0 or pitch 0: 1.0", far && odd); }
    check("P13 the finger's own numbers unchanged (1.5x every light, 2.0x under it)", kMSBDLightMagGrow == 1.50 && kMSBDLightMagSwell == 0.50);
    { MSBDLightRow r = smRow(); double s[kMSBDLightMagMaxDots];
      r.usable[2] = 0;   // (the bar's green greyed for an app that can only run full screen, or a button not enabled)
      int off = MSBDLightPtrScales(&r, 58, 12, s) < 0 && allOne(s, 3);
      int kept = MSBDLightPtrScales(&r, 38, 12, s) == 1 && s[2] == 1.0 && s[1] > s[0] && s[0] > 1.0;
      MSBDLightRow two = smRow(); two.n = 2;   // (green hidden: two lights; the pitch from their centres)
      int pair = MSBDLightPtrScales(&two, 38, 12, s) == 1 && fabs(s[1] - 1.40) < 1e-9 && s[0] > 1.10;
      MSBDLightRow one = smRow(); one.n = 1;   // (one light shown: the pitch from its size, 20 / 12 of it)
      int single = MSBDLightPtrScales(&one, 18, 12, s) == 0 && fabs(s[0] - 1.40) < 1e-9;
      check("P14 a greyed or not enabled light never grows, and the pointer on it grows none; two lights, or one, still grow", off && kept && pair && single); }

    // ---- the pointer's state (MSBDLightPtr): what a hover's end, a click's touch down and up, a touch anywhere, a look while held and -apply do
    { MSBDLightPtr s; double t = 100.0;
      memset(&s, 0, sizeof s); s.grown = 1;   // (the TV: no hold there)
      int a = MSBDLightPtrHoverOff(&s, 4, 0, 1, 0, 0, t, 0) == MSBDLightPtrRest && !s.grown && s.restAt == t;
      MSBDLightPtrMark(&s, 1, t + 0.010);
      int b = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.020) == MSBDLightPtrRegrow && s.grown;
      int c = MSBDLightPtrClickUp(&s, 0) == MSBDLightPtrRest && !s.grown;
      check("T1 UIKit's cancel before the click's touch (the TV): back to rest, then the pointer's touch down 20 ms later puts the sizes back; its end with no hover: rest", a && b && c); }
    { MSBDLightPtr s; double t = 100.0;
      memset(&s, 0, sizeof s); s.grown = 1;   // (the iPad's own screen: the cancel with no touch before it is held)
      int a = MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 0, t, 0) == MSBDLightPtrHold && s.held && s.grown;
      int b = MSBDLightPtrTouchBegan(&s, t + 0.005) == MSBDLightPtrUnhold && !s.held && !s.grown && s.restAt == t + 0.005;
      MSBDLightPtrMark(&s, 1, t + 0.006);
      int c = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.007) == MSBDLightPtrRegrow && s.grown;
      check("T2 ... on the iPad: the cancel is held, the click's touch ends the hold, its touch down puts the sizes back", a && b && c); }
    { MSBDLightPtr s; double t = 100.0;
      memset(&s, 0, sizeof s); s.grown = 1;
      int a = MSBDLightPtrTouchBegan(&s, t) == MSBDLightPtrNothing;
      MSBDLightPtrMark(&s, 1, t);
      int b = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.001) == MSBDLightPtrNothing && s.grown;
      int c = MSBDLightPtrHoverOff(&s, 4, 1, 1, 1, 0, t + 0.010, t) == MSBDLightPtrKeep && s.grown && !s.held;
      int d = MSBDLightPtrClickUp(&s, 0) == MSBDLightPtrRest && !s.grown;
      check("T3 the click's touch before UIKit's cancel: the sizes stay through the click (held for a click), back to rest at its end", a && b && c && d); }
    { MSBDLightPtr s; double t = 100.0;
      memset(&s, 0, sizeof s); s.grown = 1;   // (a finger on the lights: SpringBoard sees its touch, then UIKit's cancel)
      MSBDLightPtrTouchBegan(&s, t);
      int a = MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 0, t + 0.010, t) == MSBDLightPtrRest && !s.held;
      MSBDLightPtrMark(&s, 0, t + 0.012);
      int b = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.013) == MSBDLightPtrNothing && !s.grown;
      memset(&s, 0, sizeof s); s.grown = 1;   // (the other order: the cancel first, held, then the finger)
      int c = MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 0, t, 0) == MSBDLightPtrHold && MSBDLightPtrTouchBegan(&s, t + 0.010) == MSBDLightPtrUnhold;
      MSBDLightPtrMark(&s, 0, t + 0.011);
      int d = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.012) == MSBDLightPtrNothing && !s.grown;
      check("T4 a finger after the pointer, either order: the lights go back to rest and its touch down puts nothing back (the finger's pill opens from rest)", a && b && c && d); }
    { MSBDLightPtr s; double t = 100.0;
      memset(&s, 0, sizeof s); s.grown = 1;
      MSBDLightPtrHoverOff(&s, 4, 0, 1, 0, 0, t, 0);
      MSBDLightPtrMark(&s, 1, t + 0.30);
      int a = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.30) == MSBDLightPtrNothing;
      memset(&s, 0, sizeof s); s.grown = 1;
      MSBDLightPtrHoverOff(&s, 4, 0, 1, 0, 0, t, 0);
      MSBDLightPtrMark(&s, 1, t + 0.01);
      int b = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.20) == MSBDLightPtrNothing;   // (a touch down 0.19 s after the press saw the touch: not that touch)
      memset(&s, 0, sizeof s); s.grown = 1;
      MSBDLightPtrHoverOff(&s, 4, 0, 1, 0, 0, t, 0);
      MSBDLightPtrMark(&s, 1, t + 0.01);
      int c = MSBDLightPtrClickDown(&s, 0, 0, 1, t + 0.02) == MSBDLightPtrNothing && MSBDLightPtrClickDown(&s, 1, 0, 0, t + 0.02) == MSBDLightPtrNothing;
      check("T5 no sizes back: a click 0.3 s after the hover's end, a touch down that is not the marked touch, switched off, or the press not idle", a && b && c); }
    { MSBDLightPtr s; double t = 100.0;
      memset(&s, 0, sizeof s); s.grown = 1;
      MSBDLightPtrMark(&s, 1, t);
      MSBDLightPtrHoverOff(&s, 4, 1, 1, 1, 0, t + 0.01, t);   // (held for the click)
      int a = MSBDLightPtrClickUp(&s, 0) == MSBDLightPtrRest && !s.grown && s.restAt == 0;   // (dragged off the light: TouchDragExit)
      int b = MSBDLightPtrClickDown(&s, 1, 0, 1, t + 0.05) == MSBDLightPtrNothing && !s.grown;   // (back on it: TouchDragEnter)
      check("T6 press, drag off the light and back: back to rest at the drag off, nothing put back on the way back", a && b); }
    { MSBDLightPtr s; memset(&s, 0, sizeof s); s.grown = 1;
      check("T7 a click's end while the pointer hovers again: the sizes stay (the hover follows)", MSBDLightPtrClickUp(&s, 1) == MSBDLightPtrNothing && s.grown); }
    { MSBDLightPtr s; int ok = 1;
      memset(&s, 0, sizeof s); s.grown = 1; ok = ok && MSBDLightPtrCheck(&s, 0, 1, 1, 1, 1) == MSBDLightPtrNothing && s.grown;   // (a live hover on a light)
      memset(&s, 0, sizeof s); s.grown = 1; ok = ok && MSBDLightPtrCheck(&s, 1, 0, 1, 1, 0) == MSBDLightPtrNothing && s.grown;   // (a click in progress)
      check("T8 -apply during a live hover or a click: nothing changes (MilkyWay4's layout passes, a front change)", ok);
      int st = 1;
      memset(&s, 0, sizeof s); s.grown = 1; st = st && MSBDLightPtrCheck(&s, 0, 1, 1, 1, 0) == MSBDLightPtrRestNow && !s.grown;   // (the window moved under a still pointer)
      memset(&s, 0, sizeof s); s.grown = 1; st = st && MSBDLightPtrCheck(&s, 0, 1, 0, 1, 1) == MSBDLightPtrRestNow;   // (hidden: an ancestor, the window)
      memset(&s, 0, sizeof s); s.grown = 1; st = st && MSBDLightPtrCheck(&s, 0, 1, 1, 0, 1) == MSBDLightPtrRestNow;   // (switched off, Guided Access)
      memset(&s, 0, sizeof s); s.grown = 1; st = st && MSBDLightPtrCheck(&s, 0, 0, 1, 1, 1) == MSBDLightPtrRestNow;   // (no hover and no hold)
      memset(&s, 0, sizeof s); s.grown = 1; s.held = 1; st = st && MSBDLightPtrCheck(&s, 0, 0, 1, 1, 1) == MSBDLightPtrNothing && s.held;   // (held: UIKit's hover cancelled)
      memset(&s, 0, sizeof s); s.grown = 1; s.held = 1; st = st && MSBDLightPtrCheck(&s, 0, 0, 0, 1, 1) == MSBDLightPtrRestNow && !s.held && !s.grown;
      memset(&s, 0, sizeof s); st = st && MSBDLightPtrCheck(&s, 0, 0, 0, 0, 0) == MSBDLightPtrNothing;   // (at rest: nothing to do)
      check("T9 -apply's look: a grown set whose pointer is no longer on one of its buttons, hidden, switched off, or with no hover or hold goes back at once", st); }
    { MSBDLightPtr s; double t = 100.0; int ok = 1;
      memset(&s, 0, sizeof s); s.grown = 1; ok = ok && MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 1, t, 0) == MSBDLightPtrRest && !s.held;   // (the finger's pill is out)
      MSBDLightPtrMark(&s, 1, t + 0.01); ok = ok && MSBDLightPtrClickDown(&s, 1, 1, 1, t + 0.02) == MSBDLightPtrNothing;
      check("T10 the finger's pill out: no hold, nothing put back", ok); }
    { MSBDLightPtr s; double t = 100.0; int ok = 1;
      memset(&s, 0, sizeof s); s.grown = 1; ok = ok && MSBDLightPtrHoverOff(&s, 3, 0, 1, 1, 0, t, 0) == MSBDLightPtrRest && !s.held && s.restAt == t;   // (Ended: the pointer left)
      memset(&s, 0, sizeof s); s.grown = 1; ok = ok && MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 0, t, t - 0.5) == MSBDLightPtrRest && !s.held;   // (a touch 0.5 s before)
      memset(&s, 0, sizeof s); s.grown = 1; ok = ok && MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 0, t, t - 1.5) == MSBDLightPtrHold && s.held;    // (the idle cancel: no touch for 1.5 s)
      memset(&s, 0, sizeof s); ok = ok && MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 0, t, 0) == MSBDLightPtrHold && s.held;   // (the symbols only, the pointer beside the buttons)
      memset(&s, 0, sizeof s); ok = ok && MSBDLightPtrHoverOff(&s, 4, 0, 0, 1, 0, t, 0) == MSBDLightPtrNothing && !s.held;   // (nothing shown: nothing to hold)
      memset(&s, 0, sizeof s); s.grown = 1; ok = ok && MSBDLightPtrHoverOff(&s, 2, 0, 1, 1, 0, t, 0) == MSBDLightPtrRest && s.restAt == 0;   // (moved off the buttons, still hovering)
      memset(&s, 0, sizeof s); s.grown = 1; s.held = 1; ok = ok && MSBDLightPtrHoverOff(&s, 1, 0, 1, 1, 0, t, 0) == MSBDLightPtrRest && !s.held;   // (UIKit has it again, off the band)
      check("T11 UIKit's end held (common/DockHover.h's rule) only for a cancel with no touch in the second before, on the iPad, with something shown", ok); }
    { MSBDLightPtr s; double t = 100.0; int ok = 1;
      memset(&s, 0, sizeof s); s.grown = 1; s.held = 1;
      ok = ok && MSBDLightPtrHoldLook(&s, MSBDHoverHoldKeep, t) == MSBDLightPtrKeep && s.held && s.grown;
      ok = ok && MSBDLightPtrHoldLook(&s, MSBDHoverHoldUIKit, t) == MSBDLightPtrNothing && !s.held && s.grown;
      s.held = 1; ok = ok && MSBDLightPtrHoldLook(&s, MSBDHoverHoldEnd, t) == MSBDLightPtrUnhold && !s.held && !s.grown && s.restAt == t;
      s.held = 1; ok = ok && MSBDLightPtrHoverOver(&s) && !s.held && !MSBDLightPtrHoverOver(&s);
      ok = ok && MSBDLightPtrTouchBegan(&s, t) == MSBDLightPtrNothing;
      check("T12 a look while held: kept while backboardd has the pointer over the lights, UIKit's again when its hover begins, else ended (back to rest)", ok); }
    { int ok = 1, idle = 0;   // (the review of 1.8.8's pointer, finding 3: a move over the title bar round the lights is answered at once, with no work)
      const long states[] = {0, 1, 2, 3, 4, 5};
      const double touches[] = {0, 99.5, 98.0};   // (none yet, a touch 0.5 s before, 2 s before)
      for (int grown = 0; grown < 2; grown++) for (int held = 0; held < 2; held++) for (int shown = 0; shown < 2; shown++)
      for (int si = 0; si < 6; si++) for (int clicking = 0; clicking < 2; clicking++) for (int own = 0; own < 2; own++) for (int pill = 0; pill < 2; pill++)
      for (int ti = 0; ti < 3; ti++) {
          MSBDLightPtr s; memset(&s, 0, sizeof s);
          s.grown = grown; s.held = held; s.restAt = 90.0; s.markAt = 95.0; s.markPointer = 1;
          if (!MSBDLightPtrIdle(&s, 0, shown)) continue;
          idle++;
          int a = MSBDLightPtrHoverOff(&s, states[si], clicking, shown || s.grown, own, pill, 100.0, touches[ti]);
          if (a != MSBDLightPtrNothing || s.grown != grown || s.held != held || s.restAt != 90.0 || s.markAt != 95.0 || s.markPointer != 1) ok = 0;
      }
      MSBDLightPtr s; memset(&s, 0, sizeof s);
      int gate = MSBDLightPtrIdle(&s, 0, 0) && !MSBDLightPtrIdle(&s, 1, 0) && !MSBDLightPtrIdle(&s, 0, 1);
      s.grown = 1; gate = gate && !MSBDLightPtrIdle(&s, 0, 0);
      s.grown = 0; s.held = 1; gate = gate && !MSBDLightPtrIdle(&s, 0, 0);
      check("T13 a report off the lights with nothing of the pointer's on them is answered at once: HoverOff would answer Nothing and change nothing (every state, click, screen, pill, touch)",
            ok && gate && idle == 6 * 2 * 2 * 2 * 3); }
    { int ok = 1, cases = 0, holds = 0, unholds = 0;   // (the re-review of 1.8.8's pointer, finding 1: the sendEvent: pass-through notes touches only while it matters)
      const long states[] = {0, 1, 2, 3, 4, 5};
      const double touches[] = {0, 99.5, 98.0};   // (none yet, a touch 0.5 s before, 2 s before)
      for (int grown = 0; grown < 2; grown++) for (int held = 0; held < 2; held++) for (int shown = 0; shown < 2; shown++) {
          MSBDLightPtr s; memset(&s, 0, sizeof s);
          s.grown = grown; s.held = held;
          if (MSBDLightPtrWantsTouches(&s, shown) != !MSBDLightPtrIdle(&s, 0, shown)) ok = 0;   // (the off path's Idle the other way round)
          int want = MSBDLightPtrWantsTouches(&s, shown);
          int u = MSBDLightPtrTouchBegan(&s, 100.0);   // (a touch: Unhold only on a set that wants touches, and then nothing of the pointer's is left)
          if (u == MSBDLightPtrUnhold) { unholds++; if (!want || MSBDLightPtrWantsTouches(&s, 0)) ok = 0; }
          else if (s.grown != grown || s.held != held) ok = 0;
          for (int si = 0; si < 6; si++) for (int clicking = 0; clicking < 2; clicking++) for (int own = 0; own < 2; own++) for (int pill = 0; pill < 2; pill++) {
              int a[3];
              for (int ti = 0; ti < 3; ti++) {
                  memset(&s, 0, sizeof s);
                  s.grown = grown; s.held = held; s.restAt = 90.0; s.markAt = 95.0; s.markPointer = 1;
                  a[ti] = MSBDLightPtrHoverOff(&s, states[si], clicking, shown || grown, own, pill, 100.0, touches[ti]);
                  cases++;
                  if (a[ti] == MSBDLightPtrHold) { holds++; if (!want) ok = 0; }
                  // (the hover off the lights, ptrOver NO: held or kept for a click still wants touches; a rest or nothing leaves nothing -- the gate goes off)
                  if ((a[ti] == MSBDLightPtrHold || a[ti] == MSBDLightPtrKeep) != (MSBDLightPtrWantsTouches(&s, 0) != 0)) ok = 0;
              }
              if (!want && (a[0] != a[1] || a[1] != a[2])) ok = 0;   // (no set wanting touches: a touch's time changes no answer)
          }
      }
      MSBDLightPtr s; memset(&s, 0, sizeof s); s.grown = 1; s.held = 1;
      int end = MSBDLightPtrHoldLook(&s, MSBDHoverHoldEnd, 100.0) == MSBDLightPtrUnhold && !MSBDLightPtrWantsTouches(&s, 0);   // (a hold's look ends it: nothing left)
      memset(&s, 0, sizeof s); s.grown = 1; s.held = 1;
      int stale = MSBDLightPtrCheck(&s, 0, 0, 0, 1, 1) == MSBDLightPtrRestNow && !MSBDLightPtrWantsTouches(&s, 0);   // (-apply's look rests it: nothing left)
      check("T14 SpringBoard's touches matter only to a set with something of the pointer's on it (shown, grown or held): only there Hold and Unhold, elsewhere a touch's time changes nothing; off the lights after a rest, an end or a hold's end nothing is left",
            ok && end && stale && cases == 8 * 6 * 2 * 2 * 2 * 3 && holds > 0 && unholds == 4); }
    { int ok = 1, ends = 0;   // (D48, 1.8.8: the resting pointer's hold ends when iPadOS hides the pointer -- pointeruid's word, common/PointerFade.h)
      const unsigned long long fades[] = {MSBDPointerFadeUnsaid, MSBDPointerFadeHidden, MSBDPointerFadeShown, 3ULL};
      for (int grown = 0; grown < 2; grown++) for (int held = 0; held < 2; held++) for (int hov = 0; hov < 2; hov++) for (int fi = 0; fi < 4; fi++) {
          MSBDLightPtr s; memset(&s, 0, sizeof s);
          s.grown = grown; s.held = held; s.restAt = 90.0; s.markAt = 95.0; s.markPointer = 1;
          int a = MSBDLightPtrFade(&s, hov, fades[fi], 100.0);
          if (held && !hov && fades[fi] == MSBDPointerFadeHidden) {   // (ended as a look ends it: back to rest, the time noted, nothing of the pointer's left)
              ends++;
              if (a != MSBDLightPtrUnhold || s.held || s.grown || s.restAt != (grown ? 100.0 : 90.0) || s.markAt != 95.0 || MSBDLightPtrWantsTouches(&s, 0)) ok = 0;
          } else if (a != MSBDLightPtrNothing || s.grown != grown || s.held != held || s.restAt != 90.0 || s.markAt != 95.0) ok = 0;
      }
      // the iPad 2's R7 (p05): grown under the resting pointer, UIKit's idle cancel 8 s after the last move held; pointeruid says it shows (or nothing,
      // MacPointer not there): held as before; UIKit's hover began again before the word came: UIKit's; it faded: back to rest, once; then a move is UIKit's
      MSBDLightPtr s; memset(&s, 0, sizeof s); s.grown = 1;
      int seq = MSBDLightPtrHoverOff(&s, 4, 0, 1, 1, 0, 100.0, 0) == MSBDLightPtrHold && s.held && s.grown
             && MSBDLightPtrFade(&s, 0, MSBDPointerFadeShown, 100.1) == MSBDLightPtrNothing && s.held && s.grown
             && MSBDLightPtrFade(&s, 0, MSBDPointerFadeUnsaid, 100.2) == MSBDLightPtrNothing && s.held && s.grown
             && MSBDLightPtrFade(&s, 1, MSBDPointerFadeHidden, 100.3) == MSBDLightPtrNothing && s.held && s.grown
             && MSBDLightPtrFade(&s, 0, MSBDPointerFadeHidden, 100.4) == MSBDLightPtrUnhold && !s.held && !s.grown && s.restAt == 100.4
             && MSBDLightPtrFade(&s, 0, MSBDPointerFadeHidden, 100.5) == MSBDLightPtrNothing && s.restAt == 100.4
             && MSBDLightPtrTouchBegan(&s, 100.6) == MSBDLightPtrNothing && MSBDLightPtrHoverOver(&s) == 0 && !s.held;
      int said = MSBDPointerFadeOf(1) == MSBDPointerFadeHidden && MSBDPointerFadeOf(0) == MSBDPointerFadeShown && MSBDPointerFadeUnsaid == 0ULL
              && MSBDPointerFadeHidden != MSBDPointerFadeShown && MSBDPointerFadeShown != MSBDPointerFadeUnsaid && MSBDPointerFadeHidden != MSBDPointerFadeUnsaid;
      check("T15 a hold ends when the pointer fades (pointeruid's word: hidden), as a look that ends it, unless UIKit's hover began again; shown or nothing said: held as before (D48)",
            ok && ends == 2 && seq && said); }
    printf("test-lightmagnify: %d pass, %d fail\n", n - fails, fails);
    return fails ? 1 : 0;
}
