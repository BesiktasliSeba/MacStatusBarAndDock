// test-dockbounce.c: Animate Opening Applications, the plain C (common/DockBounce.h, 1.8.4 item 2): the switch as stored (off unless switched on),
// which taps bounce, how high, when a bounce ends (never in the air, never before its first bounce is over), and where "up" goes on the screen for the
// Dock at the bottom and at either side (common/DockSide.h's turn).
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "../common/DockSide.h"
#include "../common/DockBounce.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static int near(double a, double b) { return fabs(a - b) < 0.001; }
int main(void) {
    check("Animate Opening Applications never set (a new install, an update): on (KT 7 Nov)", MSBDAnimateOpeningOn(0, 0) == 1 && MSBDAnimateOpeningOn(0, 1) == 1);
    check("  ... switched on: on; switched off: off", MSBDAnimateOpeningOn(1, 1) == 1 && MSBDAnimateOpeningOn(1, 0) == 0);
    check("the key: animateOpening", !strcmp(kMSBDAnimateOpeningKey, "animateOpening"));
    check("a tap bounces: switch on, an app icon whose app is not running, no Reduce Motion, not editing", MSBDBounceWanted(1, 0, 1, 0, 0) == 1);
    check("  ... not: switch off / Reduce Motion / not an app's icon / the app already running / the Home Screen being edited",
          !MSBDBounceWanted(0, 0, 1, 0, 0) && !MSBDBounceWanted(1, 1, 1, 0, 0) && !MSBDBounceWanted(1, 0, 0, 0, 0) && !MSBDBounceWanted(1, 0, 1, 1, 0) && !MSBDBounceWanted(1, 0, 1, 0, 1));
    check("how high: 0.42 of the picture (60 pt -> 25.2), at least 12, at most 40", near(MSBDBounceHeight(60), 25.2) && near(MSBDBounceHeight(10), 12) && near(MSBDBounceHeight(200), 40) && near(MSBDBounceHeight(NAN), 12));
    double P = MSBD_BOUNCE_PERIOD, C = MSBD_BOUNCE_CAP, N = MSBD_BOUNCE_NO_LAUNCH;
    check("goes on while the app opens (launched, its window not shown, under the cap)", MSBDBounceEndsAt(100, 103, 0, 1, 0, P, C, N) == 0.0);
    check("the window shows 0.2 s in: it still makes its first bounce (ends at 100 + one period)", near(MSBDBounceEndsAt(100, 100.2, 1, 1, 0, P, C, N), 100 + P));
    check("the window shows 1.0 s in: it finishes the second bounce (100 + 2 periods), never stops in the air", near(MSBDBounceEndsAt(100, 101.0, 1, 1, 0, P, C, N), 100 + 2 * P));
    check("  ... exactly at a bounce's end: lands there", near(MSBDBounceEndsAt(100, 100 + 3 * P, 1, 1, 0, P, C, N), 100 + 3 * P));
    check("no app process 2.5 s after the tap (it opened nothing): lands at the end of that bounce", near(MSBDBounceEndsAt(100, 102.6, 0, 0, 0, P, C, N), 100 + ceil(2.6 / P) * P));
    check("  ... a process started: goes on past 2.5 s", MSBDBounceEndsAt(100, 102.6, 0, 1, 0, P, C, N) == 0.0);
    check("L4 (review 1.8.4 Pass 4): its app started and went again before its window showed (it crashed while opening): lands at the end of that bounce, not at the cap",
          near(MSBDBounceEndsAt(100, 101.0, 0, 1, 1, P, C, N), 100 + 2 * P) && near(MSBDBounceEndsAt(100, 104.0, 0, 1, 1, P, C, N), 100 + ceil(4.0 / P) * P));
    check("  ... gone at once: it still makes its first bounce", near(MSBDBounceEndsAt(100, 100.3, 0, 1, 1, P, C, N), 100 + P));
    check("a launch that never shows a window: lands after the cap (10 s)", MSBDBounceEndsAt(100, 110.0, 0, 1, 0, P, C, N) >= 110.0 && MSBDBounceEndsAt(100, 109.9, 0, 1, 0, P, C, N) == 0.0);
    int cyc = 1;
    for (double t = 0.01; t < 12; t += 0.13) { double e = MSBDBounceEndsAt(0, t, 1, 1, 0, P, C, N); double k = e / P; if (fabs(k - round(k)) > 1e-6 || e < t - 1e-9 || e < P - 1e-9) cyc = 0; }
    check("  ... whenever it is asked: always at the end of a whole bounce, never before now, never before the first bounce ends", cyc);
    CGPoint b = MSBDBounceScreenDirection(MSBDDockSideHostTransform(MSBDDockBottom)), l = MSBDBounceScreenDirection(MSBDDockSideHostTransform(MSBDDockLeft)), r = MSBDBounceScreenDirection(MSBDDockSideHostTransform(MSBDDockRight));
    check("up on the screen: the bottom Dock's icons bounce up, a left Dock's to the right, a right Dock's to the left (away from the edge)",
          near(b.x, 0) && near(b.y, -1) && near(l.x, 1) && near(l.y, 0) && near(r.x, -1) && near(r.y, 0));
    return fails;
}
