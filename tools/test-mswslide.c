// test-mswslide.c -- the Spaces slide's arithmetic (statusbar/MSWSlideMath.h): the spring's speed is its position's derivative (a redirect starts the
// next spring with it: no jump in the motion), the critically damped spring never overshoots unless it starts towards its end faster than omega
// times the distance (MacSwitcher.h stiffens it before that), the settling and slow-tail times, and the slot a taken slide goes to at the lift.
#include <stdio.h>
#include <math.h>
#include "../statusbar/MSWSlideMath.h"
static int pass = 0, fail = 0;
#define CHECK(cond, ...) do { if (cond) pass++; else { fail++; printf("FAIL  "); printf(__VA_ARGS__); printf("\n"); } } while (0)
int main(void) {
    const double e0s[] = {-3582, -2388, -1194, -902, -500, -1, 0, 1, 300, 916, 1194, 2388};
    const double u0s[] = {-6000, -4176, -900, -54, 0, 48, 900, 2475, 4227, 6000};
    const double ws[] = {20.0, 27.5, 42.0};
    // 1. start values and the speed as the position's derivative (central difference), everywhere on the way
    for (unsigned a = 0; a < sizeof e0s / sizeof *e0s; a++) for (unsigned b = 0; b < sizeof u0s / sizeof *u0s; b++) for (unsigned c = 0; c < 3; c++) {
        double e0 = e0s[a], u0 = u0s[b], w = ws[c];
        CHECK(fabs(DMMSWSpringE(e0, u0, w, 0) - e0) < 1e-9, "E(0) = %.3f, want %.3f", DMMSWSpringE(e0, u0, w, 0), e0);
        CHECK(fabs(DMMSWSpringU(e0, u0, w, 0) - u0) < 1e-9, "U(0) = %.3f, want %.3f", DMMSWSpringU(e0, u0, w, 0), u0);
        for (double t = 0.001; t < 1.2; t += 0.01) {
            double h = 1e-6, num = (DMMSWSpringE(e0, u0, w, t + h) - DMMSWSpringE(e0, u0, w, t - h)) / (2 * h), u = DMMSWSpringU(e0, u0, w, t);
            CHECK(fabs(num - u) <= 1e-3 * fmax(1.0, fabs(u)), "e0 %.0f u0 %.0f w %.1f t %.3f: dE/dt %.4f vs U %.4f", e0, u0, w, t, num, u);
        }
    }
    // 2. no overshoot while it starts towards its end no faster than omega x the distance (critically damped); past that it does (the code stiffens)
    for (unsigned a = 0; a < sizeof e0s / sizeof *e0s; a++) for (unsigned c = 0; c < 3; c++) {
        double e0 = e0s[a], w = ws[c];
        if (fabs(e0) < 2) continue;
        double toward = -e0 / fabs(e0);   // (the direction towards the end, as a sign of de/dt)
        for (double f = 0; f <= 1.0; f += 0.25) {
            double u0 = toward * f * w * fabs(e0);
            int crossed = 0;
            for (double t = 0; t < 2.0; t += 0.001) if (DMMSWSpringE(e0, u0, w, t) * e0 < -1e-6) { crossed = 1; break; }
            CHECK(!crossed, "e0 %.0f w %.1f start %.2f x omega x distance: overshot", e0, w, f);
        }
        double u0 = toward * 1.6 * w * fabs(e0);
        int crossed = 0;
        for (double t = 0; t < 2.0; t += 0.001) if (DMMSWSpringE(e0, u0, w, t) * e0 < -1e-6) { crossed = 1; break; }
        CHECK(crossed, "e0 %.0f w %.1f start 1.6 x omega x distance: should overshoot (why the code stiffens the spring)", e0, w);
    }
    // 3. settling time: within 1 pt from then on; the slow tail within 3% (2 pt at least) from then on and before the settling time
    for (unsigned a = 0; a < sizeof e0s / sizeof *e0s; a++) for (unsigned b = 0; b < sizeof u0s / sizeof *u0s; b++) for (unsigned c = 0; c < 3; c++) {
        double e0 = e0s[a], u0 = u0s[b], w = ws[c], T = DMMSWSpringTime(e0, u0, w), Q = DMMSWSpringQuiet(e0, u0, w), lim = fmax(2.0, fabs(e0) * 0.03);
        int late = 0, qlate = 0;
        for (double t = T; t < 2.5; t += 0.001) if (fabs(DMMSWSpringE(e0, u0, w, t)) >= 1.0) { late = 1; break; }
        for (double t = Q + 0.002; t < 2.5; t += 0.001) if (fabs(DMMSWSpringE(e0, u0, w, t)) >= lim) { qlate = 1; break; }
        CHECK(!late, "e0 %.0f u0 %.0f w %.1f: still >= 1 pt after the settling time %.3f s", e0, u0, w, T);
        CHECK(!qlate, "e0 %.0f u0 %.0f w %.1f: still past the slow tail's limit after %.3f s", e0, u0, w, Q);
        CHECK(Q <= T, "e0 %.0f u0 %.0f w %.1f: slow tail %.3f after settling %.3f", e0, u0, w, Q, T);
    }
    CHECK(fabs(DMMSWSpringTime(-1194, 0, 20.0) - 0.474) < 0.01, "from rest over a screen (omega 20): %.3f s, the measured slides took 474 ms", DMMSWSpringTime(-1194, 0, 20.0));
    // 4. a redirect: the next spring starts with the speed this one has -- no jump (the motion's speed is continuous)
    {
        double e0 = 1194 - 0, u0 = 0, w = 20.0, t = 0.137, x = 1194 + DMMSWSpringE(-1194, 0, w, t) - 1194, u = DMMSWSpringU(-1194, 0, w, t);
        double target2 = -2388, e1 = (x - 1194) - target2;   // (the same slide, now aimed one more screen on)
        CHECK(fabs(DMMSWSpringU(e1, u, w, 0) - u) < 1e-9, "redirect: speed %.1f -> %.1f", u, DMMSWSpringU(e1, u, w, 0));
        (void)e0; (void)u0;
    }
    // 5. where a taken slide goes (W 1194; slots -2..3: six desktops, the left one the third)
    struct { double o, v; long want; const char *what; } g[] = {
        {0, 0, 0, "at rest on its own desktop: stays"},
        {-500, 0, 0, "less than half a screen, no flick: back"},
        {-700, 0, 1, "more than half a screen: the next"},
        {-300, -2475, 1, "a flick left from 25%: the next on the right"},
        {-1250, -2475, 2, "a flick left just past the next: the one after"},
        {-1100, -2475, 1, "a flick left nearly at the next: that one"},
        {300, 2475, -1, "a flick right from -25%: the one on the left"},
        {-1194, 2475, 0, "on the next, a flick right: back to its own"},
        {-1100, 449, 1, "449 pt/s is no flick: the nearest"},
        {-4800, -3000, 3, "past the last desktop: the last"},
        {2600, 3000, -2, "past the first desktop: the first"},
        {-597.0, 0, 1, "exactly half a screen: rounds on"},
    };
    for (unsigned i = 0; i < sizeof g / sizeof *g; i++) { long k = DMMSWGrabSlot(g[i].o, 1194, g[i].v, -2, 3); CHECK(k == g[i].want, "%s: slot %ld, want %ld", g[i].what, k, g[i].want); }
    printf("test-mswslide: %d passed, %d failed\n", pass, fail);
    return fail ? 1 : 0;
}
