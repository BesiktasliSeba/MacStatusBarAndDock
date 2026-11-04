// Mac test of how long the Stage Manager engine's gesture hold waits for a window's live resize that SpringBoard never completes (1.8.0 item 7):
// statusbar/SMGestureCap.h, which SMGestureHold.h asks for every transaction it counts. Run by test-smgesturecap.sh, which also checks the hold as
// built: the cap only for a live resize, the finger read from the transaction's own recognizer, the writes let go by the half-second look.
#include <stdio.h>
#include "../statusbar/SMGestureCap.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

// One transaction played look by look (every 0.5 s, as the hold's own look): the finger down until liftAt, up after (a second gesture from
// downAgain to upAgain, < 0: none), SpringBoard completing it at doneAt (< 0: never). Returns when the hold let go (-1: never within 400 s).
static double PlayHold(int liveResize, double liftAt, double downAgain, double upAgain, double doneAt) {
    double up = 0;
    for (double t = 0; t <= 400.0; t += 0.5) {
        int down = t < liftAt || (downAgain >= 0 && t >= downAgain && t < upAgain);
        int complete = doneAt >= 0 && t >= doneAt;
        up = MSBDGestureUpSince(down, up, t);
        if (!MSBDGestureTxHolds(complete, liveResize, down, up, t)) return t;
    }
    return -1;
}

int main(void) {
    CHECK(kMSBDGestureLiftedCap >= 2.0 && kMSBDGestureLiftedCap <= 5.0, "the cap: a few seconds (%.1f s)", kMSBDGestureLiftedCap);
    // the finger
    CHECK(MSBDGestureUpSince(1, 12.0, 20.0) == 0, "the finger down: no time up (a new gesture starts it again)");
    CHECK(MSBDGestureUpSince(0, 0, 20.0) == 20.0, "the finger first seen up: from now");
    CHECK(MSBDGestureUpSince(0, 12.0, 20.0) == 12.0, "  ... and from then on, the first time it was seen up");
    // the rule
    CHECK(!MSBDGestureTxHolds(1, 0, 1, 0, 0) && !MSBDGestureTxHolds(1, 1, 0, 1, 2), "completed by SpringBoard: it holds nothing (as before)");
    CHECK(MSBDGestureTxHolds(0, 1, 1, 0, 500.0), "a live resize with the finger down holds its stage however long (the window held by its corner)");
    CHECK(MSBDGestureTxHolds(0, 1, 0, 10.0, 10.0 + kMSBDGestureLiftedCap - 0.01), "  ... the finger up: it holds until the cap");
    CHECK(!MSBDGestureTxHolds(0, 1, 0, 10.0, 10.0 + kMSBDGestureLiftedCap), "  ... and lets go at the cap, though SpringBoard has not completed it");
    CHECK(MSBDGestureTxHolds(0, 0, 0, 10.0, 400.0), "any other gesture's transaction (the Home gesture's: issue #7): held until SpringBoard completes it, whatever the finger");
    CHECK(MSBDGestureTxHolds(0, 1, 0, 0, 400.0), "a live resize whose finger was never seen up: held");
    // played look by look
    double t = PlayHold(1, 1.2, -1, -1, 2.1);
    CHECK(t == 2.5, "a resize completed 0.9 s after the lift: let go when SpringBoard completes it, not by the cap (%.1f)", t);
    t = PlayHold(1, 1.2, -1, -1, -1);
    CHECK(t >= 1.2 + kMSBDGestureLiftedCap && t <= 1.2 + kMSBDGestureLiftedCap + 0.5 + 0.01, "the 18.5 story -- a resize never completed: let go %.1f s after the lift (was: 350 s, until a display cycle)", t - 1.2);
    t = PlayHold(1, 1.0, 2.5, 6.0, -1);
    CHECK(t >= 6.0 + kMSBDGestureLiftedCap && t <= 6.0 + kMSBDGestureLiftedCap + 0.5 + 0.01, "a second gesture in the same transaction: the cap starts again from its own lift (%.1f)", t);
    t = PlayHold(1, 120.0, -1, -1, -1);
    CHECK(t >= 120.0 + kMSBDGestureLiftedCap, "the finger held on the corner two minutes: held all that time (%.1f)", t);
    t = PlayHold(0, 1.0, -1, -1, -1);
    CHECK(t < 0, "a Home gesture's transaction never completed: still held (the issue #7 crash rule stands)");
    // the finger read from the transaction's own recognizer (1.8.0 review 5): no recognizer to read -- none, or one without -state (a pointer or
    // trackpad corner drag may come with none) -- counts as down, never as up, so the cap never lets go in the middle of a drag
    CHECK(MSBDGestureFingerDown(1, 1) && MSBDGestureFingerDown(1, 2), "its recognizer began or changed: the finger is down");
    CHECK(!MSBDGestureFingerDown(1, 0) && !MSBDGestureFingerDown(1, 3) && !MSBDGestureFingerDown(1, 4) && !MSBDGestureFingerDown(1, 5), "  ... possible, ended, cancelled, failed: up");
    CHECK(MSBDGestureFingerDown(0, 0) && MSBDGestureFingerDown(0, 3), "no recognizer to read: down (whatever state was not read)");
    double up = 0, letGo = -1;
    for (double s = 0; s <= 60.0 && letGo < 0; s += 0.5) {   // (a 40 s corner drag with no recognizer, SpringBoard completing it at 41 s)
        int down = MSBDGestureFingerDown(0, 0);
        up = MSBDGestureUpSince(down, up, s);
        if (!MSBDGestureTxHolds(s >= 41.0, 1, down, up, s)) letGo = s;
    }
    CHECK(letGo == 41.0, "a live resize with no recognizer held 40 s: held until SpringBoard completed it, never let go mid-drag by the cap (%.1f)", letGo);
    printf("test-smgesturecap: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
