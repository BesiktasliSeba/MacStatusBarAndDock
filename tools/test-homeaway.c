// test-homeaway.c -- Home Minimizes Windows (statusbar/HomeAway.h, 1.7.9): which of the user's Homes minimize the windows, and one Home per gesture.
// Every combination of the inputs is checked against the rule as the switch's footer says it: with the switch on, a Home the person makes takes
// the windows on screen with it -- every window with Aerial, Zetsu, MilkyWay4 or no engine; only our own windows with the Stage Manager engine (its
// windows go with SpringBoard's Home transition, SMHomeRule.h) --, never our own simulated press, never a Home from the keyboard (Cmd-H: KT 2 Nov,
// the switch is not about the keyboard), never a Home that closes the Lock Screen, the Cover Sheet or Control Center, never during Guided Access,
// and nothing when no window is on screen.
#include <stdio.h>
#include "../statusbar/HomeAway.h"
static int pass = 0, fail = 0;
#define CHECK(cond, ...) do { if (cond) pass++; else { fail++; printf("FAIL  "); printf(__VA_ARGS__); printf("\n"); } } while (0)
int main(void) {
    // 1. the whole table
    const unsigned counts[] = {0, 1, 3};
    for (int on = 0; on < 2; on++) for (int ours = 0; ours < 2; ours++) for (int keys = 0; keys < 2; keys++) for (int covered = 0; covered < 2; covered++)
    for (int guided = 0; guided < 2; guided++) for (int sm = 0; sm < 2; sm++) for (int e = 0; e < 3; e++) for (int o = 0; o < 3; o++) {
        unsigned ew = counts[e], ow = counts[o];
        int want = DMHomeAwayNone;
        if (on && !ours && !keys && !covered && !guided) {
            if (sm) want = ow ? DMHomeAwayOurs : DMHomeAwayNone;
            else want = ew || ow ? DMHomeAwayAll : DMHomeAwayNone;
        }
        int got = DMHomeAwayWhat(on, ours, keys, covered, guided, sm, ew, ow);
        CHECK(got == want, "on %d ours %d keys %d covered %d guided %d sm %d windows %u/%u: %d, want %d", on, ours, keys, covered, guided, sm, ew, ow, got, want);
    }
    // 2. the cases the footer names, said once more by name
    CHECK(DMHomeAwayWhat(1, 0, 0, 0, 0, 0, 3, 0) == DMHomeAwayAll, "Aerial, three windows, a swipe up: every window minimized");
    CHECK(DMHomeAwayWhat(0, 0, 0, 0, 0, 0, 3, 0) == DMHomeAwayNone, "the switch off: the windows stay (the desktop, as before)");
    CHECK(DMHomeAwayWhat(1, 1, 0, 0, 0, 0, 3, 0) == DMHomeAwayNone, "our own press (a full-screen app minimized): the windows stay");
    CHECK(DMHomeAwayWhat(1, 0, 1, 0, 0, 0, 3, 0) == DMHomeAwayNone, "Cmd-H (the keyboard's Home): the windows stay, as before the switch");
    CHECK(DMHomeAwayWhat(1, 0, 1, 0, 0, 1, 0, 1) == DMHomeAwayNone, "  ... with the Stage Manager engine, our Finder window too");
    CHECK(DMHomeAwayWhat(1, 0, 0, 1, 0, 0, 3, 0) == DMHomeAwayNone, "a Home that closes Control Center or the Cover Sheet: the windows stay");
    CHECK(DMHomeAwayWhat(1, 0, 0, 0, 0, 1, 2, 0) == DMHomeAwayNone, "Stage Manager engine: its windows are its Home transition's, nothing here");
    CHECK(DMHomeAwayWhat(1, 0, 0, 0, 0, 1, 0, 1) == DMHomeAwayOurs, "Stage Manager engine with a Finder window: that one minimized here");
    CHECK(DMHomeAwayWhat(1, 0, 0, 0, 0, 0, 0, 0) == DMHomeAwayNone, "no window on screen: nothing (the Home Screen's own Home press)");
    // 3. one Home per gesture: two root modifiers activate the lift at the same moment (15.6.1); the next gesture counts again
    double last = -100;
    CHECK(DMHomeAwayOnce(10.0, &last) == 1 && last == 10.0, "the first activation of a lift counts");
    CHECK(DMHomeAwayOnce(10.0, &last) == 0, "the second modifier's, at the same moment: not again");
    CHECK(DMHomeAwayOnce(10.3, &last) == 0 && last == 10.0, "0.3 s later: still the same lift");
    CHECK(DMHomeAwayOnce(10.6, &last) == 1 && last == 10.6, "the next swipe (0.6 s later) counts");
    CHECK(DMHomeAwayOnce(11.1, &last) == 1, "and the one after it (0.5 s later)");
    printf("test-homeaway: %d passed, %d failed\n", pass, fail);
    return fail ? 1 : 0;
}
