// Mac test of the Mac pointer's external-display math (statusbar/macpointer/MPDisplayGeometry.h): which display a pointer view is on, and the
// pointer's turn there. Run by test-mpgeometry.sh.
#include <stdio.h>
#include "../statusbar/macpointer/MPDisplayGeometry.h"
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
static int deg(double r) { return (int)lround(r * 180.0 / M_PI); }
static int normdeg(int d) { d %= 360; if (d < 0) d += 360; return d; }
// the pointer's net turn on the display = its own turn + every turn between its layer and the display
static int net(int inWindow, int windowToDisplay, double own) { return normdeg(deg(own) + (inWindow + windowToDisplay) * 90); }
int main(void) {
    bool v;
    // quarter turns from vectors (y down: +x -> +y is a clockwise quarter)
    CHECK(MPQuarterTurns(100, 0, &v) == 0 && v, "x axis");
    CHECK(MPQuarterTurns(0, 100, &v) == 1, "down = +1");
    CHECK(MPQuarterTurns(0, -100, &v) == -1, "up = -1");
    CHECK(MPNormTurns(MPQuarterTurns(-100, 0, &v)) == 2, "back = 2");
    CHECK(MPQuarterTurns(0.2, 0.1, &v) == 0 && !v, "too short");
    CHECK(MPQuarterTurns(99, 8, &v) == 0, "small tilt rounds to 0");
    CHECK(MPNormTurns(3) == -1 && MPNormTurns(-3) == 1 && MPNormTurns(4) == 0 && MPNormTurns(-2) == 2, "fold");
    // which display, iPad 2 (834 x 1194 pt, 1668 x 2388 px) + TV (960 x 540 pt, 1920 x 1080 px), in every iPad orientation of pointeruid's main screen
    double ipW = 834, ipH = 1194, ipNW = 1668, ipNH = 2388, tvW = 960, tvH = 540, tvNW = 1920, tvNH = 1080;
    for (int land = 0; land < 2; land++) {
        double mW = land ? ipH : ipW, mH = land ? ipW : ipH;   // pointeruid's main screen bounds, portrait- or landscape-shaped
        // the iPad's own pointer window (full screen, either way round): never another display
        CHECK(MPOtherDisplayReason(true, true, true, ipNW, ipNH, ipNW, ipNH, ipW, ipH, mW, mH) == 0, "iPad window, main %d", land);
        CHECK(MPOtherDisplayReason(true, true, true, ipNW, ipNH, ipNW, ipNH, ipH, ipW, mW, mH) == 0, "iPad window turned, main %d", land);
        CHECK(MPOtherDisplayReason(false, false, false, 0, 0, 0, 0, 0, 0, mW, mH) == 0, "no window = iPad");
        CHECK(MPOtherDisplayReason(true, false, false, 0, 0, 0, 0, 0, 0, mW, mH) == 0, "no sizes = iPad");
        // the TV: its own screen object
        CHECK(MPOtherDisplayReason(true, true, false, tvNW, tvNH, ipNW, ipNH, tvW, tvH, mW, mH) == 1, "TV screen object, main %d", land);
        // the TV when pointeruid hands out the main screen object but the window is the TV's size (the old rule missed this in landscape)
        CHECK(MPOtherDisplayReason(true, true, true, ipNW, ipNH, ipNW, ipNH, tvW, tvH, mW, mH) == 3, "TV by window size, main %d", land);
        CHECK(MPOtherDisplayReason(true, false, false, 0, 0, 0, 0, tvW, tvH, mW, mH) == 3, "TV by window size, no screen, main %d", land);
        // a TV screen object equal by pointer compare but a different pixel size (defensive)
        CHECK(MPOtherDisplayReason(true, true, true, tvNW, tvNH, ipNW, ipNH, ipW, ipH, mW, mH) == 2, "TV by pixel size");
    }
    // window to display: a layer turn wins, otherwise the screen's interface turn; never both
    CHECK(MPWindowToDisplayTurns(0, 0) == 0, "none");
    CHECK(MPWindowToDisplayTurns(1, 1) == 1, "same turn once, not twice");
    CHECK(MPWindowToDisplayTurns(0, -1) == -1, "screen only");
    CHECK(MPWindowToDisplayTurns(4, 1) == 1, "full turn counts as none");
    // the pointer on another display ends upright (net 0) for every combination of turns between it and the display
    for (int iw = -1; iw <= 2; iw++) for (int wl = -1; wl <= 2; wl++) for (int sc = -1; sc <= 2; sc++) {
        double own = MPOtherDisplayAngle(iw, wl, sc);
        CHECK(net(iw, MPWindowToDisplayTurns(wl, sc), own) == 0, "upright: in window %d, layers %d, screen %d -> own %d", iw, wl, sc, deg(own));
    }
    // the old X1 behaviour is kept where it was right: only a turn inside the window -> the same angle as before (-round(turn))
    for (int iw = -1; iw <= 2; iw++) CHECK(normdeg(deg(MPOtherDisplayAngle(iw, 0, 0))) == normdeg(-iw * 90), "X1 unchanged for in-window %d", iw);
    printf(fails ? "mpgeometry: %d FAIL\n" : "mpgeometry: all passed\n", fails);
    return fails != 0;
}
