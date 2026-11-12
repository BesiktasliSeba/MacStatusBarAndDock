// test-smgesturedisplay.c -- Mac test of the display a switcher gesture belongs to (1.8.7, iPad 2 16.7.7 d41 07:46:54, SpringBoard crash and Safe Mode):
// the Stage Manager engine's desktop is taken by a gesture with no stage under the finger only when that gesture is the iPad's own. A push at the TV's
// bottom edge with no TV stage under the pointer gave the TV's gesture transaction the iPad's stage; SpringBoard looked it up in the TV switcher's list
// and -[NSArray subarrayWithRange:] threw {NSNotFound, 1}. The rule as built: DMSMGestureTakesOnIPad cut out of statusbar/SMGestureHook.h
// (test-smgesturedisplay.sh, smgesturedisplay-gen.h). Each read: 1 the iPad's, 0 another display's, -1 not read here.
#include <stdio.h>
typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#include "smgesturedisplay-gen.h"
static int fails = 0, checks = 0;
static void Expect(int ok, const char *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    // ---- the iPad alone: as before ----
    Expect(DMSMGestureTakesOnIPad(-1, -1, -1, NO), "the iPad alone, nothing read: the desktop is taken, as before 1.8.7 (the bottom-edge swipe from a desktop of windows)");
    Expect(DMSMGestureTakesOnIPad(1, 1, 1, NO), "  ... every read says the iPad's: taken");
    Expect(DMSMGestureTakesOnIPad(-1, -1, 1, NO), "  ... only the recognizer's screen read, the iPad's: taken");
    // ---- with a TV ----
    Expect(!DMSMGestureTakesOnIPad(0, 0, 0, YES), "d41 07:46:54: the TV's push (its switcher, its request's display, its recognizer's screen): SpringBoard's own pick, the iPad's stage not given");
    Expect(!DMSMGestureTakesOnIPad(0, -1, -1, YES), "  ... only the transaction's switcher read, the TV's: not taken");
    Expect(!DMSMGestureTakesOnIPad(-1, 0, -1, YES), "  ... only the request's display read, the TV's: not taken");
    Expect(!DMSMGestureTakesOnIPad(-1, -1, 0, YES), "  ... only the recognizer's screen read, the TV's: not taken");
    Expect(!DMSMGestureTakesOnIPad(1, -1, 0, YES), "  ... reads that disagree (the iPad's switcher, the TV's screen): not taken -- never the iPad's stage for a gesture that may be another display's");
    Expect(!DMSMGestureTakesOnIPad(1, 0, 1, YES), "  ... the request's display the TV's, the others the iPad's: not taken");
    Expect(!DMSMGestureTakesOnIPad(-1, -1, -1, YES), "  ... nothing read with a TV there: not taken (SpringBoard's own pick; the desktop is not taken until the TV goes)");
    Expect(DMSMGestureTakesOnIPad(1, 1, 1, YES), "the iPad's own gesture with a TV there (its switcher, its display, its screen): taken");
    Expect(DMSMGestureTakesOnIPad(1, -1, -1, YES), "  ... only its switcher read, the iPad's: taken");
    Expect(DMSMGestureTakesOnIPad(-1, 1, -1, YES), "  ... only its request's display read, the iPad's: taken");
    Expect(!DMSMGestureTakesOnIPad(0, -1, -1, NO), "a read that says another display wins even when no other scene was seen (a display that just went)");
    printf("%s: %d checks, %d failed\n", fails ? "test-smgesturedisplay rule FAILED" : "test-smgesturedisplay rule: all pass", checks, fails);
    return fails ? 1 : 0;
}
