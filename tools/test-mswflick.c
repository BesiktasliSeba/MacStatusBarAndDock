// test-mswflick.c: Swipe Up to Quit's rule (statusbar/MSWFlick.h): which finger gestures on a thumbnail quit the app, which stay the drag, and
// when the trackpad's two-finger swipe quits; and where a window dragged onto the strip lands (a desktop's tile and its name: MSBDMSWDropOnDesk).
#include <stdio.h>
#include "../statusbar/MSWFlick.h"
static int fails = 0, n = 0;
static void check(const char *what, int got, int want) { n++; if (got != want) { fails++; printf("FAIL  %s: got %d, want %d\n", what, got, want); } else printf("PASS  %s\n", what); }
static MSBDMSWFlick F(double held, double dur, double vx, double vy, double dx, double dy, int desk, int ptr) {
    MSBDMSWFlick f = { held, dur, vx, vy, dx, dy, desk, ptr }; return f;
}
int main(void) {
    check("a quick flick straight up quits", MSBDMSWFlickQuits(F(0.05, 0.22, 40, -1800, 10, -220, 0, 0)), 1);
    check("a flick a little to the side quits", MSBDMSWFlickQuits(F(0.08, 0.30, 900, -1500, 120, -200, 0, 0)), 1);
    check("a hold first, then the same flick: the drag", MSBDMSWFlickQuits(F(0.40, 0.70, 0, -1800, 0, -220, 0, 0)), 0);
    check("held just past the limit: the drag", MSBDMSWFlickQuits(F(0.26, 0.50, 0, -1800, 0, -220, 0, 0)), 0);
    check("a fast flick ending on a desktop: the move", MSBDMSWFlickQuits(F(0.05, 0.25, 0, -2400, 0, -500, 1, 0)), 0);
    check("a slow drag up let go in empty space: back to its place", MSBDMSWFlickQuits(F(0.10, 0.90, 0, -300, 0, -260, 0, 0)), 0);
    check("fast but too long a gesture: the drag", MSBDMSWFlickQuits(F(0.05, 0.80, 0, -1500, 0, -400, 0, 0)), 0);
    check("fast up but hardly moved: nothing", MSBDMSWFlickQuits(F(0.05, 0.15, 0, -1200, 0, -30, 0, 0)), 0);
    check("a flick mostly sideways: the drag", MSBDMSWFlickQuits(F(0.05, 0.25, 1600, -1000, 250, -120, 0, 0)), 0);
    check("a flick down: the drag", MSBDMSWFlickQuits(F(0.05, 0.25, 0, 1800, 0, 220, 0, 0)), 0);
    check("the pointer's click-drag flicked up: never a quit", MSBDMSWFlickQuits(F(0.05, 0.25, 0, -1800, 0, -220, 0, 1)), 0);
    check("no touch-down time (held unknown): the drag", MSBDMSWFlickQuits(F(-1, 0.25, 0, -1800, 0, -220, 0, 0)), 0);
    // the strip of a 1024 pt wide view: Desktop 1 at x 300-400, y 12-76, its name to y 97, desktops 30 pt apart
    check("let go on Desktop 2's name: over the desktops", MSBDMSWFlickOverStrip(480, 88, 300, 97, 30), 1);
    check("let go in the gap between two desktops: over the desktops", MSBDMSWFlickOverStrip(415, 40, 300, 97, 30), 1);
    check("let go at the strip's right end (no \"+\" with the most desktops): over the desktops", MSBDMSWFlickOverStrip(1000, 40, 300, 97, 30), 1);
    check("let go half a gap left of Desktop 1: over the desktops", MSBDMSWFlickOverStrip(286, 40, 300, 97, 30), 1);
    check("let go far left of Desktop 1: not over them", MSBDMSWFlickOverStrip(200, 40, 300, 97, 30), 0);
    check("let go below the names: not over them", MSBDMSWFlickOverStrip(350, 130, 300, 97, 30), 0);
    check("a fast flick let go on a desktop's name: the drag (back to its place), never a quit",
          MSBDMSWFlickQuits(F(0.05, 0.25, 0, -2400, 0, -500, MSBDMSWFlickOverStrip(480, 88, 300, 97, 30), 0)), 0);
    // a window dragged onto the strip (row 4c): Desktop 1's tile at x 300-400, y 12-76; Desktop 2's at x 430-530
    check("the names end 3 + 18 pt under the tile", MSBDMSWNamesMaxY(76) == 97, 1);
    check("drop on the tile: that desktop", MSBDMSWDropOnDesk(350, 40, 300, 12, 400, 76), 1);
    check("drop on the desktop's name under its tile: that desktop (was: back to its place)", MSBDMSWDropOnDesk(350, 88, 300, 12, 400, 76), 1);
    check("drop on the name's last line: that desktop", MSBDMSWDropOnDesk(350, 97, 300, 12, 400, 76), 1);
    check("drop below the names: no desktop", MSBDMSWDropOnDesk(350, 99, 300, 12, 400, 76), 0);
    check("drop on the name's left end, within 6 pt of the tile: that desktop", MSBDMSWDropOnDesk(295, 88, 300, 12, 400, 76), 1);
    check("drop on the name's far end, past 6 pt of the tile: no desktop", MSBDMSWDropOnDesk(408, 88, 300, 12, 400, 76), 0);
    check("drop 6 pt right of the tile: that desktop (as before)", MSBDMSWDropOnDesk(406, 40, 300, 12, 400, 76), 1);
    check("drop 6 pt above the tile: that desktop (as before)", MSBDMSWDropOnDesk(350, 6, 300, 12, 400, 76), 1);
    check("drop 7 pt above the tile: no desktop (as before)", MSBDMSWDropOnDesk(350, 5, 300, 12, 400, 76), 0);
    check("drop in the gap between two desktops: no desktop (as before)", MSBDMSWDropOnDesk(415, 40, 300, 12, 400, 76) || MSBDMSWDropOnDesk(415, 40, 430, 12, 530, 76), 0);
    check("drop under the gap, between two names: no desktop", MSBDMSWDropOnDesk(415, 88, 300, 12, 400, 76) || MSBDMSWDropOnDesk(415, 88, 430, 12, 530, 76), 0);
    check("drop on Desktop 2's name: Desktop 2, not Desktop 1", MSBDMSWDropOnDesk(480, 88, 430, 12, 530, 76) && !MSBDMSWDropOnDesk(480, 88, 300, 12, 400, 76), 1);
    check("a small tile (names taller than the reach): its name still counts", MSBDMSWDropOnDesk(20, 50, 10, 12, 40, 30), 1);
    {   // flick and drop agree: every point a window is dropped on a desktop at is over the desktops for a flick (never a quit there)
        int agree = 1;
        for (double x = 250; x <= 600; x += 0.5) for (double y = 0; y <= 120; y += 0.5) {
            int drop = MSBDMSWDropOnDesk(x, y, 300, 12, 400, 76) || MSBDMSWDropOnDesk(x, y, 430, 12, 530, 76);
            if (drop && !MSBDMSWFlickOverStrip(x, y, 300, MSBDMSWNamesMaxY(76), kMSBDMSWStripGap)) agree = 0;
        }
        check("every drop point on a desktop or its name is over the desktops for a flick", agree, 1);
    }
    check("trackpad: carried up past 30% of a 300 pt thumbnail quits", MSBDMSWScrollQuits(5, -100, -50, 300), 1);
    check("trackpad: carried up 70 pt of a 300 pt thumbnail springs back", MSBDMSWScrollQuits(0, -70, -100, 300), 0);
    check("trackpad: small thumbnail needs at least 80 pt", MSBDMSWScrollQuits(0, -60, -100, 100), 0);
    check("trackpad: a quick two-finger flick up quits", MSBDMSWScrollQuits(0, -40, -900, 300), 1);
    check("trackpad: a flick that barely moved springs back", MSBDMSWScrollQuits(0, -10, -1200, 300), 0);
    check("trackpad: mostly sideways springs back", MSBDMSWScrollQuits(200, -120, -400, 300), 0);
    check("trackpad: down springs back", MSBDMSWScrollQuits(0, 150, 600, 300), 0);
    printf("test-mswflick: %d pass, %d fail\n", n - fails, fails);
    return fails ? 1 : 0;
}
