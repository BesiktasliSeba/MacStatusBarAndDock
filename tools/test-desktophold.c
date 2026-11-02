// test-desktophold.c -- Mac test of statusbar/DesktopHold.h (1.7.8): a finger held on the desktop -- when its menu opens (the 1.7.7 fix-round
// review's m2: a finger wobbling in place got no menu), and whose a touch is, decided once (review N1: the Dock's swipe down and the desktop's
// rectangle both acted on one finger). Run by test-desktophold.sh.
#include <stdio.h>
#include "../statusbar/DesktopHold.h"
static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
int main(void) {
    const double rest = 0.1;   // (Desktop.h kDMDesktopRestTime)
    // ---- the hold's menu ----
    Int("a finger held still 0.45 s (at rest 0.3 s, 1 pt from where it went down): the menu", MSBDDesktopHoldStep(0.45, 0.3, 1.0, 0, rest), MSBDHoldMenu);
    Int("a finger moving at 0.45 s, 6 pt out (on its way into a drag, 1.7.7 fix round): no menu yet, looked at again", MSBDDesktopHoldStep(0.45, 0.02, 6.0, 0, rest), MSBDHoldWait);
    Int("  ... it comes to rest at 0.6 s: the menu", MSBDDesktopHoldStep(0.6, 0.12, 6.0, 0, rest), MSBDHoldMenu);
    Int("  ... it goes on past 10 pt: no menu (a drag's -- the move itself starts it)", MSBDDesktopHoldStep(0.6, 0.01, 10.5, 0, rest), MSBDHoldNone);
    Int("the review's m2: wobbling more than 4 pt every 0.1 s, within 10 pt -- at 0.95 s still waiting", MSBDDesktopHoldStep(0.95, 0.03, 8.0, 0, rest), MSBDHoldWait);
    Int("  ... at 1 s a hold all the same: the menu (it got none before, and no jiggle mode)", MSBDDesktopHoldStep(1.0, 0.03, 8.0, 0, rest), MSBDHoldMenu);
    Int("  ... 2.5 s, still wobbling in place: the menu", MSBDDesktopHoldStep(2.5, 0.0, 9.9, 0, rest), MSBDHoldMenu);
    Int("a click held (pointer, 0.75 s), moving 2 pt: waits -- a pointer has no wobble to forgive", MSBDDesktopHoldStep(0.75, 0.02, 2.0, 1, rest), MSBDHoldWait);
    Int("  ... a click that moved 5 pt: a drag's (4 pt for a pointer)", MSBDDesktopHoldStep(0.8, 0.02, 5.0, 1, rest), MSBDHoldNone);
    Int("  ... a click still moving at the 3 s cap: no further looks", MSBDDesktopHoldStep(3.0, 0.02, 2.0, 1, rest), MSBDHoldNone);
    Int("  ... a click at rest: the menu", MSBDDesktopHoldStep(0.9, 0.2, 2.0, 1, rest), MSBDHoldMenu);
    // ---- whose the touch is ----
    MSBDTouchOwner o = MSBDTouchUndecided;
    Int("N1: the Dock's pan begins 0.33 s after the touch-down (held short of 0.35 s): not the desktop's -- the swipe down may fire", MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.33, 0.35), 0);
    Int("  ... still undecided after that answer (a later ask, held long enough, may still find it the desktop's)", o, MSBDTouchUndecided);
    MSBDDesktopTouchGiveAway(&o);
    Int("  ... the swipe down fired: the touch is given away", o, MSBDTouchGivenAway);
    Int("  ... asked again at 0.5 s (the old rule said yes there: the rectangle under the App Library): not the desktop's", MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.5, 0.35), 0);
    o = MSBDTouchUndecided;
    Int("held 0.36 s when the pan begins: the desktop's (the swipe down is refused)", MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.36, 0.35), 1);
    Int("  ... and it stays the desktop's", o, MSBDTouchDesktop);
    Int("  ... asked again where the time rule alone would say no (its icon gone: 0.35 s now, held 0.32 s): still the desktop's", MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.32, 0.35), 1);
    MSBDDesktopTouchGiveAway(&o);
    Int("  ... a give-away after that changes nothing (the Dock never fires then: it asked first)", o, MSBDTouchDesktop);
    o = MSBDTouchUndecided;
    Int("on an icon: 0.3 s is enough", MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.31, 0.3), 1);
    o = MSBDTouchUndecided;
    Int("a pointer's press: the desktop's at once", MSBDDesktopTouchOursAnswer(&o, 0, 0, 1, 0.01, 0.35), 1);
    o = MSBDTouchUndecided;
    Int("dragging already, or the hold's menu open: the desktop's", MSBDDesktopTouchOursAnswer(&o, 1, 0, 0, 0.1, 0.35) && (o = MSBDTouchUndecided, MSBDDesktopTouchOursAnswer(&o, 0, 1, 0, 0.1, 0.35)), 1);
    printf("%s: %d/%d\n", fails ? "test-desktophold FAILED" : "test-desktophold: all pass", checks - fails, checks);
    return fails ? 1 : 0;
}
