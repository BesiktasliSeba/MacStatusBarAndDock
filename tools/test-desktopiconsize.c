// Mac test of the desktop icons' size (common/DesktopIconSize.h; 1.7.5 item 4): the slider's steps and range, the side in force (never set = the
// Home Screen's size exactly as before), the cell that follows the icon (the pre-1.7.5 formula at the old sizes), the Home Screen's side as
// published for Settings, and what Settings' slider shows.
#include <stdio.h>
#include <math.h>
#include "../common/DesktopIconSize.h"
#include <sys/param.h>   // (MIN / MAX, which DesktopPlace.h takes from Foundation in SpringBoard)
#include "../statusbar/DesktopPlace.h"
static int fails = 0, checks = 0;
static void Check(int ok, const char *what) { checks++; if (!ok) { fails++; printf("FAIL %s\n", what); } }
static int Near(double a, double b) { return fabs(a - b) < 1e-9; }
int main(void) {
    // the slider's values: 40 to 96 in 4 pt steps, as macOS's View Options (16 to 512 by 4)
    Check(Near(MSBDDesktopIconSnap(40), 40) && Near(MSBDDesktopIconSnap(96), 96), "the ends stay");
    Check(Near(MSBDDesktopIconSnap(61.9), 60) && Near(MSBDDesktopIconSnap(62.1), 64) && Near(MSBDDesktopIconSnap(63.99), 64), "to the nearest 4 pt step");
    Check(Near(MSBDDesktopIconSnap(10), 40) && Near(MSBDDesktopIconSnap(-5), 40) && Near(MSBDDesktopIconSnap(500), 96), "clamped to the range");
    Check(Near(MSBDDesktopIconSnap(NAN), 0) && Near(MSBDDesktopIconSnap(INFINITY), 0), "no number: 0 (nothing stored is used)");
    int steps = 0; double last = -1;
    for (double v = 30; v <= 110; v += 0.25) { double s = MSBDDesktopIconSnap(v); if (!Near(s, last)) { steps++; last = s; } }
    Check(steps == 15, "15 sizes across the slider (40, 44, ..., 96)");
    // the side in force
    Check(Near(MSBDDesktopIconSide(0, 0, 83.5, 64), 83.5), "never set: the Home Screen's measured side as it is (not snapped: as before 1.7.5)");
    Check(Near(MSBDDesktopIconSide(0, 0, 0, 76), 76) && Near(MSBDDesktopIconSide(0, 0, 0, 0), 64), "never set, nothing measured: the last side, else 64 (as before)");
    Check(Near(MSBDDesktopIconSide(1, 52, 83.5, 64), 52) && Near(MSBDDesktopIconSide(1, 53.5, 83.5, 64), 52), "set: the stored size, snapped, whatever the Home Screen's");
    Check(Near(MSBDDesktopIconSide(1, NAN, 76, 64), 76), "a stored value that is no number: as never set");
    Check(Near(MSBDDesktopIconSide(0, 0, 18, 70), 70), "a measured picture smaller than an icon (20 pt or less) is not the Home Screen's size");
    // the cell: exactly the pre-1.7.5 formula (cell = max(side + 30, 84) x side + name + 12), so a never-set desktop looks as it did
    double w = 0, h = 0;
    MSBDDesktopIconCell(64, 14.3203125, &w, &h); Check(Near(w, 94) && Near(h, 2 + 64 + 4 + 15 + 2 + 4), "64 pt: 94 x 91");
    MSBDDesktopIconCell(40, 14.3203125, &w, &h); Check(Near(w, 84) && Near(h, 67), "40 pt: never narrower than 84 (a name stays readable)");
    MSBDDesktopIconCell(96, 14.3203125, &w, &h); Check(Near(w, 126) && Near(h, 123), "96 pt: the cell grows with the icon");
    double prevW = 0, prevH = 0; int grows = 1;
    for (double s = 40; s <= 96; s += 4) { MSBDDesktopIconCell(s, 14.3, &w, &h); if (w < prevW || h <= prevH) grows = 0; prevW = w; prevH = h; }
    Check(grows, "a larger icon never gets a smaller cell: grid spacing and the name's width follow");
    // the grid a Mac fills follows the cell (DesktopPlace.h: gaps of 8 and 6 on top); fewer spots for larger icons on the same free area
    CGRect area = CGRectMake(6, 28, 1356, 900);
    int prevSpots = 1 << 30, fewer = 1;
    for (double s = 40; s <= 96; s += 4) {
        MSBDDesktopIconCell(s, 14.3, &w, &h);
        DMPlacer pl; DMPlacerInit(&pl, area, w, h, NULL, 0);
        int spots = pl.gcols * pl.grows;
        if (spots > prevSpots || !Near(pl.gdx, w + 8.0) || !Near(pl.gdy, h + 6.0)) fewer = 0;
        prevSpots = spots;
        DMPlacerFree(&pl);
    }
    Check(fewer, "the grid's spacing is the cell plus 8 / 6 at every size, and larger icons give fewer spots");
    // places kept: an icon placed at its stored centre stays there at a smaller size, and one that no longer fits goes to the nearest free spot
    {
        MSBDDesktopIconCell(64, 14.3, &w, &h);
        CGRect app = CGRectMake(600, 300, 80, 80);   // (an app icon of page 1)
        DMPlacer pl; DMPlacerInit(&pl, area, w, h, &app, 1);
        int fits = 0; CGPoint want = CGPointMake(556, 340);   // (40 pt: 514-598, clear of the app icon; 64 pt: 509-603, over it)
        CGPoint at64 = DMPlacerPlaceNear(&pl, want, &fits);
        DMPlacerFree(&pl);
        MSBDDesktopIconCell(40, 14.3, &w, &h);
        DMPlacerInit(&pl, area, w, h, &app, 1);
        CGPoint at40 = DMPlacerPlaceNear(&pl, want, &fits);
        DMPlacerFree(&pl);
        Check(fits && Near(at40.x, want.x) && Near(at40.y, want.y), "40 pt: the icon is exactly at its place again (next to the app icon)");
        Check(!(Near(at64.x, want.x) && Near(at64.y, want.y)) && at64.x < want.x, "64 pt: over the app icon there, so it stands aside (its place is kept)");
    }
    // the Home Screen's side as published (quarter points) and what the slider shows
    Check(MSBDDesktopHomeSideState(83.5) == 334 && Near(MSBDDesktopHomeSideFromState(334), 83.5), "83.5 pt published and read back");
    Check(MSBDDesktopHomeSideState(0) == 0 && MSBDDesktopHomeSideState(10) == 0 && Near(MSBDDesktopHomeSideFromState(0), 0), "nothing measured: 0 (unknown)");
    Check(Near(MSBDDesktopIconShown(0, 0, 304), 76), "never set: the slider shows the Home Screen's 76");
    Check(Near(MSBDDesktopIconShown(0, 0, 0), 64), "never set, nothing published: 64");
    Check(Near(MSBDDesktopIconShown(1, 47, 304), 48), "set: the stored step");
    Check(Near(MSBDDesktopIconShown(0, 0, 4 * 120), 96), "a Home Screen size beyond the slider: shown at its end");
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
