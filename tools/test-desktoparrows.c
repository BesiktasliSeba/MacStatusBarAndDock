// Mac test of common/DesktopArrows.h: which icon an arrow key moves to on the free-placed desktop.
#include <stdio.h>
#include "../common/DesktopArrows.h"
static int fails;
static void t(const char *what, long got, long want) { int ok = got == want; printf("%s  %s (%ld)\n", ok ? "PASS" : "FAIL", what, got); if (!ok) fails = 1; }
int main(void) {
    //  a column at the right (x 900): 0 at y 100, 1 at 200, 2 at 300; a second column (x 800): 3 at y 100, 4 at y 310; far left: 5 at (100, 205)
    double x[] = { 900, 900, 900, 800, 800, 100 }, y[] = { 100, 200, 300, 100, 310, 205 };
    double W = 100, H = 100;
    t("Down: the next in the column", MSBDDesktopArrowTarget(MSBD_STEP_DOWN, x, y, 6, 0, W, H), 1);
    t("Up: the previous in the column", MSBDDesktopArrowTarget(MSBD_STEP_UP, x, y, 6, 2, W, H), 1);
    t("Up at the top: nothing", MSBDDesktopArrowTarget(MSBD_STEP_UP, x, y, 6, 0, W, H), -1);
    t("Left: the same row", MSBDDesktopArrowTarget(MSBD_STEP_LEFT, x, y, 6, 0, W, H), 3);
    t("Left: a row nearly the same counts as the same", MSBDDesktopArrowTarget(MSBD_STEP_LEFT, x, y, 6, 2, W, H), 4);
    t("Right at the right edge: nothing", MSBDDesktopArrowTarget(MSBD_STEP_RIGHT, x, y, 6, 1, W, H), -1);
    t("Left from the middle row: an icon one step off to the side beats a far one straight ahead", MSBDDesktopArrowTarget(MSBD_STEP_LEFT, x, y, 6, 1, W, H), 3);
    t("Right from the far left icon: its own row first, however far", MSBDDesktopArrowTarget(MSBD_STEP_RIGHT, x, y, 6, 5, W, H), 1);
    {   double x2[] = { 500, 400, 300 }, y2[] = { 300, 200, 300 };
        t("Left: straight ahead two steps away beats a diagonal one step away", MSBDDesktopArrowTarget(MSBD_STEP_LEFT, x2, y2, 3, 0, W, H), 2); }
    t("nothing selected, Down: the first icon, top right", MSBDDesktopArrowTarget(MSBD_STEP_DOWN, x, y, 6, -1, W, H), 0);
    t("nothing selected, Up: the last in reading order", MSBDDesktopArrowTarget(MSBD_STEP_UP, x, y, 6, -1, W, H), 4);
    t("no icons", MSBDDesktopArrowTarget(MSBD_STEP_DOWN, x, y, 0, -1, W, H), -1);
    t("a swipe is not an arrow", MSBDDesktopArrowTarget(MSBD_STEP_SWIPE_NEXT, x, y, 6, 0, W, H), -1);
    long o[6]; MSBDDesktopReadingOrder(x, y, 6, H, o);
    long want[] = { 0, 3, 1, 5, 2, 4 };
    for (int i = 0; i < 6; i++) t("reading order: top row first, from the right", o[i], want[i]);
    return fails;
}
