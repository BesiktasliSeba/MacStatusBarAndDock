// Mac test of common/BatteryInside.h.
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "../common/BatteryInside.h"
static int fails;
static void t(const char *what, int got, int want) { int ok = got == want; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    t("0 %", MSBDBattInsidePercent(0), 0); t("100 %", MSBDBattInsidePercent(1), 100); t("rounded", MSBDBattInsidePercent(0.456), 46);
    t("out of range and unknown stay in range", MSBDBattInsidePercent(-1) + MSBDBattInsidePercent(2) + MSBDBattInsidePercent(NAN), 100);
    char b[8]; MSBDBattInsideText(0.07, b, sizeof b); t("the text has no percent sign, as iPadOS's", strcmp(b, "7"), 0);
    // one switch (KT 14 Nov): in a bar of ours iPadOS's own number beside the icon is left out while the switch is on, and ours shows whatever
    // iPadOS's Battery Percentage says; any other bar keeps iPadOS's number, and ours there only where it is not beside the icon
    t("left out: the switch on, the item as read, a bar of ours", MSBDBattInsideOwnLeftOut(1, 1, 1), 1);
    t("not left out: the switch off", MSBDBattInsideOwnLeftOut(0, 1, 1), 0);
    t("not left out: a bar not ours (Control Center's)", MSBDBattInsideOwnLeftOut(1, 1, 0), 0);
    t("not left out: the battery item not as read", MSBDBattInsideOwnLeftOut(1, 0, 1), 0);
    t("off: no number", MSBDBattInsideShows(0, 0, 0, 0, 0), 0);
    t("off in our bar, iPadOS's own on: no number (iPadOS's stays)", MSBDBattInsideShows(0, 1, MSBDBattInsideOwnLeftOut(0, 1, 1), 0, 0), 0);
    t("on: the number", MSBDBattInsideShows(1, 0, 0, 0, 0), 1);
    t("on in our bar, iPadOS's Battery Percentage on: the number (one switch)", MSBDBattInsideShows(1, 1, MSBDBattInsideOwnLeftOut(1, 1, 1), 0, 0), 1);
    t("on in our bar, iPadOS's Battery Percentage off: the number", MSBDBattInsideShows(1, 0, MSBDBattInsideOwnLeftOut(1, 1, 1), 0, 0), 1);
    t("on in a bar not ours, iPadOS's own beside it: not two numbers", MSBDBattInsideShows(1, 1, MSBDBattInsideOwnLeftOut(1, 1, 0), 0, 0), 0);
    t("on in our bar, the item not as read, iPadOS's own beside it: not two numbers", MSBDBattInsideShows(1, 1, MSBDBattInsideOwnLeftOut(1, 0, 1), 0, 0), 0);
    t("iPadOS's own drawing keeps the number while charging", MSBDBattInsideShows(1, 0, 0, 0, 1), 1);
    t("our number gives way to the charging bolt", MSBDBattInsideShows(1, 0, 0, 1, 1), 0);
    t("our number gives way to the charging bolt in our bar too", MSBDBattInsideShows(1, 1, 1, 1, 1), 0);
    // the number's two colours (KT 14 Nov): over the rest the icon's own shade, over the fill whichever of black and white reads better on it
    MSBDBattInsideInks k = MSBDBattInsideInksFor(1, 1, 1, 1, 1, 1, 1);
    t("dark bar (white icon), white fill: black over the fill", k.fillDark, 1); t("dark bar: white over the rest, as the icon", k.emptyDark, 0);
    k = MSBDBattInsideInksFor(0, 0, 0, 0, 0, 0, 1);
    t("light bar (black icon), black fill: white over the fill", k.fillDark, 0); t("light bar: black over the rest, as the icon", k.emptyDark, 1);
    // iPadOS's coloured fills (as read from UIKit's battery on this Mac: green while charging, yellow in Low Power Mode, red at a low level; the
    // dark appearance's red too), on either bar: black reads better on each (WCAG), and reads (ratio >= 3)
    const double fills[][3] = { { 0.156863, 0.803922, 0.254902 }, { 1, 0.8, 0 }, { 1, 0.231373, 0.188235 }, { 1, 0.270588, 0.227451 } };
    const char *names[] = { "green", "yellow", "red", "dark red" };
    for (int i = 0; i < 4; i++) for (int icon = 0; icon < 2; icon++) {
        k = MSBDBattInsideInksFor(icon, icon, icon, fills[i][0], fills[i][1], fills[i][2], 1);
        double l = MSBDBattInsideLuminance(fills[i][0], fills[i][1], fills[i][2]), ink = k.fillDark ? 0 : 1, other = k.fillDark ? 1 : 0;
        char what[128]; snprintf(what, sizeof what, "%s fill on a %s bar: black over it, ratio >= 3 and above white's", names[i], icon ? "dark" : "light");
        t(what, k.fillDark && MSBDBattInsideContrast(l, ink) >= 3 && MSBDBattInsideContrast(l, ink) > MSBDBattInsideContrast(l, other), 1);
        t("  and the icon's shade over the rest", k.emptyDark, !icon);
    }
    // every grey fill: the ink chosen is the better of the two and reads (the worst case, mid grey, still >= 4.5)
    int allRead = 1;
    for (int g = 0; g <= 255; g++) for (int icon = 0; icon < 2; icon++) {
        double c = g / 255.0, l = MSBDBattInsideLuminance(c, c, c);
        k = MSBDBattInsideInksFor(icon, icon, icon, c, c, c, 1);
        double mine = MSBDBattInsideContrast(l, k.fillDark ? 0 : 1), theirs = MSBDBattInsideContrast(l, k.fillDark ? 1 : 0);
        if (mine < theirs || mine < 4.5) allRead = 0;
    }
    t("every grey fill, either bar: the better ink, ratio >= 4.5", allRead, 1);
    t("a clear fill is the bar: white over it on a dark bar", MSBDBattInsideInksFor(1, 1, 1, 1, 1, 1, 0).fillDark, 0);
    t("a clear fill is the bar: black over it on a light bar", MSBDBattInsideInksFor(0, 0, 0, 0, 0, 0, 0).fillDark, 1);
    t("a grey icon (0.6) is a light one", MSBDBattInsideInksFor(0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 1).emptyDark, 0);
    t("out of range: an unknown alpha is a clear fill, the bar under it (a blue icon: a light bar, black)", MSBDBattInsideInksFor(NAN, -1, 2, 5, 5, 5, NAN).fillDark, 1);
    t("out of range: unknown fill channels are black, an alpha above 1 opaque (white over it)", MSBDBattInsideInksFor(9, 9, 9, NAN, NAN, NAN, 2).fillDark, 0);
    t("contrast: black on white is 21", (int)(MSBDBattInsideContrast(0, 1) * 100 + 0.5), 2100);
    // the split: the fill's rect as the battery draws it (inner left 2 pt, inner width 19.5 pt x the level, read from UIKit's battery on this Mac),
    // in the number's own coordinates (23.08 x 11.5): its right edge is inner left + inner width x level at every level
    const int levels[] = { 5, 20, 35, 50, 55, 65, 75, 90, 100 };
    int splitOK = 1;
    for (int i = 0; i < 9; i++) {
        double w = 19.5 * levels[i] / 100.0;
        MSBDBattInsideBox p = MSBDBattInsideFillPart((MSBDBattInsideBox){ 2, 2, w, 7.5, 1.5 }, 23.08, 11.5);
        if (fabs(p.x - 2) > 1e-9 || fabs(p.x + p.w - (2 + w)) > 1e-9 || fabs(p.y - 2) > 1e-9 || fabs(p.h - 7.5) > 1e-9) splitOK = 0;
        if (p.r > p.w / 2 + 1e-12 || p.r > p.h / 2 + 1e-12 || p.r < 0) splitOK = 0;
        printf("      split at %3d %%: %.3f pt (the fill %.3f .. %.3f), corners %.3f\n", levels[i], p.x + p.w, 2.0, 2 + w, p.r);
    }
    t("the split is the fill's edge at 5 .. 100 %, corners within the part", splitOK, 1);
    MSBDBattInsideBox p = MSBDBattInsideFillPart((MSBDBattInsideBox){ 2, 2, 1, 6.5, 1.5 }, 23.08, 11.5);
    t("a 1 pt fill (5 %): its corners at most half its width", (int)(p.r * 1000 + 0.5), 500);
    p = MSBDBattInsideFillPart((MSBDBattInsideBox){ 22.5, 2, 1, 7.5, 0.5 }, 23.08, 11.5);   // (right to left: the fill from the right)
    t("right to left: the fill at the right, kept within the number", (int)((p.x + p.w) * 100 + 0.5) * 1000 + (int)(p.x * 100 + 0.5), 2308 * 1000 + 2250);
    p = MSBDBattInsideFillPart((MSBDBattInsideBox){ -3, -1, 40, 20, 1.5 }, 23.08, 11.5);
    t("a fill past the number: the whole number", p.x == 0 && p.y == 0 && fabs(p.w - 23.08) < 1e-9 && p.h == 11.5, 1);
    t("no fill (0 %): no part over it", MSBDBattInsideFillPart((MSBDBattInsideBox){ 2, 2, 0, 7.5, 1.5 }, 23.08, 11.5).w == 0, 1);
    t("a fill outside the number: none", MSBDBattInsideFillPart((MSBDBattInsideBox){ 30, 2, 5, 7.5, 1.5 }, 23.08, 11.5).w == 0, 1);
    t("an unknown fill or number: none", MSBDBattInsideFillPart((MSBDBattInsideBox){ NAN, 2, 5, 7.5, 1.5 }, 23.08, 11.5).w == 0
      && MSBDBattInsideFillPart((MSBDBattInsideBox){ 2, 2, NAN, 7.5, 1.5 }, 23.08, 11.5).w == 0 && MSBDBattInsideFillPart((MSBDBattInsideBox){ 2, 2, 5, 7.5, 1.5 }, NAN, 11.5).w == 0
      && MSBDBattInsideFillPart((MSBDBattInsideBox){ 2, 2, 5, 7.5, 1.5 }, 0, 11.5).w == 0, 1);
    // where the battery's fill can't be read: one colour, as before the split
    k = MSBDBattInsideInksFor(1, 1, 1, 1, 1, 1, 1);
    t("no fill to read, 90 %: the fill's ink", MSBDBattInsideOneInk(0.9, k), k.fillDark); t("no fill to read, 20 %: the rest's ink", MSBDBattInsideOneInk(0.2, k), k.emptyDark);
    return fails;
}
