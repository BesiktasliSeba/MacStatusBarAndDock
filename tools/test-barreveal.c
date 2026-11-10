// test-barreveal.c: the rules of the menu bar over a full-screen app that hides it (common/BarReveal.h, 1.8.4.3 item 12).
#include <stdio.h>
#include "../common/BarReveal.h"
static int fails = 0, n = 0;
#define T(name, cond) do { n++; if (cond) printf("PASS  %s\n", name); else { printf("FAIL  %s\n", name); fails++; } } while (0)
int main(void) {
    // the pointer's zones on a 24 pt bar
    T("pointer pushed against the top edge (it stops about 5 pt short)", MSBDRevealZone(5.0, 24) == 1);
    T("pointer over the bar", MSBDRevealZone(18.0, 24) == 2);
    T("pointer below the bar", MSBDRevealZone(40.0, 24) == 3);
    T("pointer place unknown", MSBDRevealZone(-1, 24) == 0);
    // swipes
    T("a swipe down from the very top edge", MSBDRevealSwipe(3, 4, 60, 0.25));
    T("a swipe that begins lower down is the app's", !MSBDRevealSwipe(40, 0, 80, 0.25));
    T("too short", !MSBDRevealSwipe(2, 0, 20, 0.2));
    T("too slow (a drag that happens to start at the top)", !MSBDRevealSwipe(2, 0, 80, 1.5));
    T("more sideways than down", !MSBDRevealSwipe(2, 90, 40, 0.3));
    // ends: pointer
    T("pointer: stays while over the bar", !MSBDRevealEnds(kMSBDRevealByPointer, 10, 5, 2, 0, false, 0, false));
    T("pointer: stays at least a second", !MSBDRevealEnds(kMSBDRevealByPointer, 5.5, 5, 3, 4, false, 0, false));
    T("pointer: goes once it has been below the bar a moment", MSBDRevealEnds(kMSBDRevealByPointer, 10, 5, 3, 9.0, false, 0, false));
    T("pointer: not straight after it left", !MSBDRevealEnds(kMSBDRevealByPointer, 10, 5, 3, 9.6, false, 0, false));
    T("pointer: a menu open keeps it", !MSBDRevealEnds(kMSBDRevealByPointer, 20, 5, 3, 9.0, true, 0, false));
    // ends: touch
    T("touch: stays a few seconds", !MSBDRevealEnds(kMSBDRevealByTouch, 7, 5, 0, 0, false, 0, false));
    T("touch: goes after a few seconds unused", MSBDRevealEnds(kMSBDRevealByTouch, 9.5, 5, 0, 0, false, 0, false));
    T("touch: using the bar keeps it longer", !MSBDRevealEnds(kMSBDRevealByTouch, 9.5, 5, 0, 0, false, 8, false));
    T("touch: the app touched below the bar: back to it", MSBDRevealEnds(kMSBDRevealByTouch, 6.5, 5, 0, 0, false, 0, true));
    T("touch: a menu open keeps it even after a touch below", !MSBDRevealEnds(kMSBDRevealByTouch, 6.5, 5, 0, 0, true, 0, true));
    printf("%d checks, %d failed\n", n, fails);
    return fails ? 1 : 0;
}
