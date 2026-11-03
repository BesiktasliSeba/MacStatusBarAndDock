// test-mswhold.c -- the Mac Switcher's hold (statusbar/MSWHoldRule.h) on finger paths made as the 1.7.8 device matrix made them: a minimum-jerk
// stroke up from the bottom edge, played to a fraction f of its profile (0.5 = lifted at full speed, 1.0 = come to a stop), then a hold of H ms
// (with or without a resting finger's tremor or a slow drift), then the lift. Touches every 1/120 s, and only when the finger moved (UIKit sends
// a still finger nothing), plus the lift's own touch. A Home swipe -- a flick, one that slows down before the lift, a slow drag -- never holds;
// a stop held kMSWRestNeeded up the screen always does, tremor or not. Then the lift's answer (DMMSWPauseSaysHome): Home only for a lift
// without a hold while the end is handled; an end with the finger still down (no new touch: Reduce Motion's end at the pause) or an ask outside
// the end keeps SpringBoard's rule; the first answer of a gesture stands for every later ask. And (1.7.9) the rest asked at every touch while
// the finger is down (DMMSWPauseResting), as Reduce Motion's end in the middle of a move asks it: never for a swipe still moving, a steady drag
// or a rest low down; from a trembling hold's touches once it has lasted kMSWRestNeeded; never again once the finger moves on.
#include <stdio.h>
#include <math.h>
#include "../statusbar/MSWHoldRule.h"
static int pass = 0, fail = 0;
#define CHECK(cond, ...) do { if (cond) pass++; else { fail++; printf("FAIL  "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static double mj(double t) { return 10 * t * t * t - 15 * t * t * t * t + 6 * t * t * t * t * t; }
static unsigned rnd = 12345;
static double noise(void) { rnd = rnd * 1103515245u + 12345u; return ((rnd >> 8) & 0xFFFF) / 65535.0 * 2.0 - 1.0; }   // (-1..1, repeatable)
// One gesture: up L pt in T ms to the fraction f of the profile; then H ms resting with tremor amplitude a (pt) and drift d (pt/s, up); a second
// stroke up L2 pt in T2 ms lifted at full speed when L2 > 0. Returns whether it held; *rest = the rest at the lift.
static int run(double L, double T, double f, double H, double a, double d, double L2, double T2, double *rest) {
    const double dt = 1.0 / 120.0;
    DMMSWPause h; double t = 0, x = 0, y = 0, lx = 0, ly = 0;
    DMMSWPauseBegin(&h, 0, 0, 0);
    int n = (int)lround(T / 1000.0 / dt); if (n < 2) n = 2;
    for (int i = 1; i <= n; i++) { t += dt; y = -L * mj(f * i / n) / mj(f); if (fabs(y - ly) > 1e-9) { DMMSWPauseMove(&h, x, y, t); lx = x; ly = y; } }
    double y0 = y;
    int m = (int)lround(H / 1000.0 / dt);
    for (int i = 1; i <= m; i++) {
        t += dt;
        x = a * noise(); y = y0 - d * i * dt + a * noise();
        if (fabs(x - lx) > 1e-9 || fabs(y - ly) > 1e-9) { DMMSWPauseMove(&h, x, y, t); lx = x; ly = y; }
    }
    if (L2 > 0) {
        double y1 = y; int k = (int)lround(T2 / 1000.0 / dt); if (k < 2) k = 2;
        for (int i = 1; i <= k; i++) { t += dt; y = y1 - L2 * mj(0.55 * i / k) / mj(0.55); DMMSWPauseMove(&h, x, y, t); }
    }
    t += dt; DMMSWPauseEnd(&h, x, y, t);   // (the lift's touch, where the finger was)
    return DMMSWPauseHeld(&h, rest);
}
// Reduce Motion's end in the middle of a move (1.7.9): the same kind of gesture, asked at every touch while the finger is down whether it rests
// (DMMSWPauseResting) -- SpringBoard's modifier may end the gesture at any of them. A stroke up L pt in T ms to the fraction f; then H ms with
// tremor amplitude a (pt; a still finger, a = 0, sends no touch, so nothing is asked); then a stroke on (L2 pt in T2 ms, lifted at full speed)
// when L2 > 0. Or, with v > 0, a steady drag at v pt/s for H ms instead. Returns the first touch's time (ms from the start) at which it
// rested, or -1; *moving = 1 when it rested at a touch of a stroke lifted while moving (f < 1), of the drag, or of the stroke on once it was
// kMSWRestSlop away from where it rested.
static double restingAt(double L, double T, double f, double H, double a, double L2, double T2, double v, int on, int *moving) {
    const double dt = 1.0 / 120.0;
    DMMSWPause h; double t = 0, x = 0, y = 0, lx = 0, ly = 0, first = -1;
    DMMSWPauseBegin(&h, 0, 0, 0); h.on = on;
    *moving = 0;
#define ASK(mv) do { if (DMMSWPauseResting(&h)) { if (first < 0) first = t * 1000.0; if (mv) *moving = 1; } } while (0)
    if (v > 0) {
        int m = (int)lround(H / 1000.0 / dt);
        for (int i = 1; i <= m; i++) { t += dt; y = -v * t; DMMSWPauseMove(&h, x, y, t); ASK(1); }
        return first;
    }
    int n = (int)lround(T / 1000.0 / dt); if (n < 2) n = 2;
    for (int i = 1; i <= n; i++) { t += dt; y = -L * mj(f * i / n) / mj(f); if (fabs(y - ly) > 1e-9) { DMMSWPauseMove(&h, x, y, t); ly = y; ASK(f < 1.0); } }
    double y0 = y;
    int m = (int)lround(H / 1000.0 / dt);
    for (int i = 1; i <= m; i++) {
        t += dt;
        if (a <= 0) continue;
        x = a * noise(); y = y0 + a * noise();
        if (fabs(x - lx) > 1e-9 || fabs(y - ly) > 1e-9) { DMMSWPauseMove(&h, x, y, t); lx = x; ly = y; ASK(0); }
    }
    if (L2 > 0) {
        double y1 = y; int k = (int)lround(T2 / 1000.0 / dt); if (k < 2) k = 2;
        for (int i = 1; i <= k; i++) { t += dt; y = y1 - L2 * mj(0.55 * i / k) / mj(0.55); DMMSWPauseMove(&h, x, y, t); ASK(fabs(y - y0) > kMSWRestSlop); }
    }
#undef ASK
    return first;
}
// The same gesture to its end, then SpringBoard's asks: the lift's answer (1 = Home) while the end is handled. lift = 0: SpringBoard ends the
// gesture itself in the middle of the last update (Reduce Motion at its pause), so the end carries that update's touch, nothing newer.
static int answer(double L, double T, double f, double H, int lift, int asks, int *same) {
    const double dt = 1.0 / 120.0;
    DMMSWPause h; double t = 0, x = 0, y = 0, ly = 0;
    DMMSWPauseBegin(&h, 0, 0, 0);
    int n = (int)lround(T / 1000.0 / dt); if (n < 2) n = 2;
    for (int i = 1; i <= n; i++) { t += dt; y = -L * mj(f * i / n) / mj(f); if (fabs(y - ly) > 1e-9) { DMMSWPauseMove(&h, x, y, t); ly = y; } }
    t += H / 1000.0;   // (a still finger: no touches while it rests)
    if (lift) t += dt;
    DMMSWPauseEnd(&h, x, y, t);
    h.ending = 1;
    int a = DMMSWPauseSaysHome(&h, NULL);
    *same = 1;
    for (int k = 1; k < asks; k++) {   // (more asks in the same end, from a second modifier or again: one more touch would change nothing)
        DMMSWPauseMove(&h, x, y - 30, t + 0.3);
        if (DMMSWPauseSaysHome(&h, NULL) != a) *same = 0;
    }
    h.ending = 0;
    return a;
}
int main(void) {
    double r;
    // 1. Home swipes: flicks and swipes lifted while moving, fast or slow -- never a hold
    const double Ls[] = {150, 250, 300, 400, 550}, Ts[] = {100, 150, 250, 350, 600, 900};
    const double fs[] = {0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 0.97};
    for (unsigned a = 0; a < 5; a++) for (unsigned b = 0; b < 6; b++) for (unsigned c = 0; c < 8; c++) {
        int held = run(Ls[a], Ts[b], fs[c], 0, 0, 0, 0, 0, &r);
        CHECK(!held, "Home swipe %.0f pt / %.0f ms lifted at f %.2f: held (rest %.0f ms)", Ls[a], Ts[b], fs[c], r * 1000);
    }
    // 2. a stroke that comes to a stop and lifts at once, or holds under 0.1 s: no hold (the slowing tail inside the slop is under 0.1 s)
    for (unsigned a = 0; a < 5; a++) for (double T = 200; T <= 450; T += 50) for (double H = 0; H <= 60; H += 20) {
        int held = run(Ls[a], T, 1.0, H, 0, 0, 0, 0, &r);
        CHECK(!held, "stop %.0f pt / %.0f ms, hold %.0f ms: held (rest %.0f ms)", Ls[a], T, H, r * 1000);
    }
    // 3. a stop held kMSWRestNeeded or more: a hold, still finger; a trembling one (+-2 pt) from 0.2 s (its first tremor may still leave the slop
    //    around where the slowing stroke last moved it, and the rest starts again there); drifting slowly (30 pt/s)
    for (unsigned a = 0; a < 5; a++) for (double T = 200; T <= 600; T += 100) for (double H = 150; H <= 900; H += 50) {
        CHECK(run(Ls[a], T, 1.0, H, 0, 0, 0, 0, &r), "stop %.0f pt / %.0f ms, hold %.0f ms: no hold (rest %.0f ms)", Ls[a], T, H, r * 1000);
        if (H >= 200) CHECK(run(Ls[a], T, 1.0, H, 2.0, 0, 0, 0, &r), "stop %.0f pt / %.0f ms, hold %.0f ms with tremor: no hold (rest %.0f ms)", Ls[a], T, H, r * 1000);
        if (H >= 300) CHECK(run(Ls[a], T, 1.0, H, 0, 30, 0, 0, &r), "stop %.0f pt / %.0f ms, hold %.0f ms drifting 30 pt/s: no hold", Ls[a], T, H);
    }
    // 4. slow drags lifted while moving (60..600 pt/s, steady): no hold -- the fingers never stay inside the slop for the hold's time
    for (double v = 60; v <= 600; v += 30) {
        int held = run(0, 0, 1.0, 400.0 / v * 1000.0, 0, v, 0, 0, &r);
        CHECK(!held, "slow drag at %.0f pt/s: held (rest %.0f ms)", v, r * 1000);
    }
    // 5. a rest low down (under kMSWRestMinTravel) then a fast stroke on: no hold
    CHECK(!run(30, 120, 1.0, 400, 0, 0, 300, 150, &r), "a rest 30 pt up, then a flick on: held");
    // 6. a hold up the screen, then a flick on: the gesture held (SpringBoard's own destination then says Home, so it goes Home -- not this rule's)
    CHECK(run(300, 350, 1.0, 300, 0, 0, 300, 150, &r), "a hold 300 pt up, then a flick on: no hold seen");
    // 7. a hold, then a slow move on before the lift: the hold counts
    CHECK(run(300, 350, 1.0, 250, 0, 0, 0, 0, &r) && run(300, 350, 1.0, 250, 0, 0, 60, 300, &r), "a hold then a slow move on: no hold seen");
    // 8. the lift's answer: a lift without a hold -> Home; a lift after a hold -> SpringBoard's (the Mac Switcher); asked several times, the same
    int same;
    for (unsigned a = 0; a < 5; a++) for (double T = 200; T <= 450; T += 50) {
        CHECK(answer(Ls[a], T, 0.97, 0, 1, 1, &same) == 1, "lift of a slowing swipe %.0f pt / %.0f ms: not Home", Ls[a], T);
        CHECK(answer(Ls[a], T, 1.0, 0, 1, 1, &same) == 1, "lift right at a stop %.0f pt / %.0f ms: not Home", Ls[a], T);
        CHECK(answer(Ls[a], T, 1.0, 400, 1, 3, &same) == 0 && same, "lift after a hold of 400 ms %.0f pt / %.0f ms: Home, or the answer changed", Ls[a], T);
        CHECK(answer(Ls[a], T, 0.97, 0, 1, 3, &same) == 1 && same, "three asks at one lift %.0f pt / %.0f ms: answers differ", Ls[a], T);
    }
    // 9. no lift: SpringBoard ends the gesture with the finger still down (Reduce Motion at its pause) -- its rule stands, at once or after a hold
    for (unsigned a = 0; a < 5; a++) for (double H = 0; H <= 600; H += 150)
        CHECK(answer(Ls[a], 300, 1.0, H, 0, 2, &same) == 0, "an end without a new touch (%.0f pt, rest %.0f ms): answered Home", Ls[a], H);
    {   // 10. an ask outside the end answers SpringBoard's and decides nothing; at the lift that follows the rule answers; a new gesture starts over
        DMMSWPause h; DMMSWPauseBegin(&h, 0, 0, 0);
        DMMSWPauseMove(&h, 0, -300, 0.30);
        CHECK(DMMSWPauseSaysHome(&h, NULL) == 0 && !h.decided, "an ask before the end: answered or decided");
        DMMSWPauseEnd(&h, 0, -300, 0.31); h.ending = 1;
        CHECK(DMMSWPauseSaysHome(&h, NULL) == 1, "the lift after an ask outside the end: not Home");
        h.ending = 0;
        CHECK(DMMSWPauseSaysHome(&h, NULL) == 1, "an ask after the end that answered Home: answered otherwise");
        DMMSWPause late; DMMSWPauseBegin(&late, 0, 0, 0);   // (a lift whose end asked nothing; an ask once its end is over decides nothing)
        DMMSWPauseMove(&late, 0, -300, 0.30); DMMSWPauseEnd(&late, 0, -300, 0.31);
        CHECK(late.lifted && DMMSWPauseSaysHome(&late, NULL) == 0 && !late.decided, "an ask outside the end, after the lift: answered or decided");
        DMMSWPauseBegin(&h, 0, 0, 1.0);
        CHECK(!h.decided && !h.lifted && !h.ending, "a new gesture keeps the last one's answer");
        DMMSWPause off = h; off.on = 0; off.ending = 1; off.lifted = 1;
        CHECK(DMMSWPauseSaysHome(&off, NULL) == 0, "a gesture not watched (no fingers): answered Home");
    }
    // 11. Reduce Motion's end with the fingers still down (1.7.9): SpringBoard may end the gesture at a move only while they rest there
    {
        int mv; double at;
        for (unsigned a = 0; a < 5; a++) for (unsigned b = 0; b < 6; b++) for (unsigned c = 0; c < 8; c++) {   // Home swipes lifted while moving
            at = restingAt(Ls[a], Ts[b], fs[c], 0, 0, 0, 0, 0, 1, &mv);
            CHECK(at < 0, "Home swipe %.0f pt / %.0f ms lifted at f %.2f: rested at +%.0f ms", Ls[a], Ts[b], fs[c], at);
        }
        for (double v = 60; v <= 1500; v += 30) {   // steady drags, however slow or fast: never at rest (the 1.7.8 regression: 300-600 pt/s)
            at = restingAt(0, 0, 1.0, 400.0 / v * 1000.0, 0, 0, 0, v, 1, &mv);
            CHECK(at < 0, "steady drag at %.0f pt/s: rested at +%.0f ms", v, at);
        }
        for (unsigned a = 0; a < 5; a++) for (double T = 200; T <= 450; T += 50) {
            const double amp[] = {0.2, 0.4, 2.0};
            for (unsigned k = 0; k < 3; k++) {
                at = restingAt(Ls[a], T, 1.0, 60, amp[k], 0, 0, 0, 1, &mv);   // a stop held 60 ms, trembling: not yet (as at a lift, section 2)
                CHECK(at < 0, "stop %.0f pt / %.0f ms, 60 ms trembling %.1f pt: rested at +%.0f ms", Ls[a], T, amp[k], at);
                for (double H = 250; H <= 800; H += 150) {   // a hold, trembling: at rest from a touch in it, not before the stop
                    at = restingAt(Ls[a], T, 1.0, H, amp[k], 0, 0, 0, 1, &mv);
                    CHECK(at >= T + 40 && at <= T + 260, "stop %.0f pt / %.0f ms, hold %.0f ms trembling %.1f pt: rested at +%.0f ms", Ls[a], T, H, amp[k], at);
                }
            }
            at = restingAt(Ls[a], T, 1.0, 600, 0, 0, 0, 0, 1, &mv);   // a still finger sends no move to end it at: its lift decides (section 8)
            CHECK(at < 0, "stop %.0f pt / %.0f ms, still: asked at +%.0f ms with no touch", Ls[a], T, at);
        }
        at = restingAt(30, 120, 1.0, 400, 0.4, 0, 0, 0, 1, &mv);   // a rest low down
        CHECK(at < 0, "a rest 30 pt up: rested at +%.0f ms", at);
        at = restingAt(300, 350, 1.0, 300, 0.4, 300, 150, 0, 1, &mv);   // a hold, then a flick on: the hold rests, the flick does not
        CHECK(at >= 0 && !mv, "a hold, then a flick on: rested %.0f, while moving on %d", at, mv);
        at = restingAt(300, 350, 1.0, 300, 0, 300, 150, 0, 1, &mv);   // a still hold, then a flick on: at the flick's first touch (the hold it ends)
        CHECK(at >= 650 && at <= 670 && !mv, "a still hold, then a flick on: rested at +%.0f ms, while moving on %d", at, mv);
        at = restingAt(300, 350, 1.0, 400, 0.4, 0, 0, 0, 0, &mv);   // a gesture not watched
        CHECK(at < 0, "a gesture not watched (no fingers): rested at +%.0f ms", at);
        DMMSWPause st; DMMSWPauseBegin(&st, 0, 0, 0);   // (and one no longer watched: the next gesture, not ours, keeps this one's rest)
        DMMSWPauseMove(&st, 0, -300, 0.30); DMMSWPauseMove(&st, 0.3, -300.2, 0.62);
        CHECK(DMMSWPauseResting(&st), "a watched rest of 320 ms, 300 pt up: not at rest");
        st.on = 0;
        CHECK(!DMMSWPauseResting(&st), "the rest of a gesture no longer watched: at rest");
    }
    printf("test-mswhold: %d passed, %d failed\n", pass, fail);
    return fail ? 1 : 0;
}
