// BatteryInside.h -- the battery percentage inside the battery icon (Settings > Status Bar, 1.8.4.2, KT 8 Nov; off by default): our number on top of iPadOS's battery view
// on every iPadOS, and these rules. Plain C: tools/test-batteryinside.c runs this code (and tools/test-battinsideink.sh with the bar's own code on UIKit's battery).
#ifndef MSBD_BATTERY_INSIDE_H
#define MSBD_BATTERY_INSIDE_H
#include <stdio.h>
#include <math.h>

#define kMSBDBatteryInsideKey "batteryPercentInside"   // (com.besiktasliseba.macstatusbar: a boolean; never set -- the default -- is off)

static inline int MSBDBattInsidePercent(double level) {   // (level 0..1)
    if (level != level || level < 0) level = 0;
    if (level > 1) level = 1;
    return (int)(level * 100.0 + 0.5);
}
static inline void MSBDBattInsideText(double level, char *buf, size_t n) { snprintf(buf, n, "%d", MSBDBattInsidePercent(level)); }
// One switch (1.8.7.4 round 2, KT 14 Nov: "currently I have to toggle it on first and then turn off the battery percentage in the battery
// settings"): in a bar of ours, with the switch on, our number takes the place of iPadOS's own number beside the icon (Settings > Battery >
// Battery Percentage, or the one Low Power Mode shows), which is left out of that bar (BatteryMenu.h DMBattInsideCanEnable) -- where the battery
// item can be asked (`canLeaveOut`: the item as read). Any other bar (Control Center's, a bar left to iOS) keeps iPadOS's number as it is.
static inline int MSBDBattInsideOwnLeftOut(int on, int canLeaveOut, int ourBar) { return on && canLeaveOut && ourBar; }
// Shown: the switch on, and iPadOS's own number not beside the icon unless it is left out of this bar (one number, never two). Our number on top
// of the view also gives way to the charging bolt, which sits where it would go.
static inline int MSBDBattInsideShows(int on, int iosOwnShown, int ownLeftOut, int ourOverlay, int boltShown) {
    if (!on || (iosOwnShown && !ownLeftOut)) return 0;
    return !(ourOverlay && boltShown);
}
// The number's two colours, split at the fill's edge (1.8.7.4 round 2, KT 14 Nov: "after lower than like 70% the number start to become
// illegible"). One colour for all of it (the opposite of the icon's from 55 %, the icon's below) left part of the number on the side of the
// fill's edge it can't be read on: from 55 to 75 % its last digit over the empty part in the bar's own colour, below 55 % its first digit over
// the fill in the fill's colour. Now two-tone, as iPadOS draws its own number in the icon: over the empty part, where the bar shows through,
// in the icon's own shade (white on a dark bar, black on a light one, as the bar's other icons); over the fill, black or white, whichever reads
// better on the fill's colour as iPadOS draws it (the icon's, its red at a low level, green while charging, yellow in Low Power Mode) by the
// WCAG contrast ratio, a fill not fully opaque taken over the bar.
static inline double MSBDBattInsideChannel(double c) {   // (an sRGB channel, 0..1, made linear)
    if (c != c || c < 0) c = 0;
    if (c > 1) c = 1;
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
static inline double MSBDBattInsideLuminance(double r, double g, double b) {   // (WCAG's relative luminance, 0 black .. 1 white)
    return 0.2126 * MSBDBattInsideChannel(r) + 0.7152 * MSBDBattInsideChannel(g) + 0.0722 * MSBDBattInsideChannel(b);
}
static inline double MSBDBattInsideContrast(double la, double lb) {   // (WCAG's contrast ratio of two luminances, 1 .. 21)
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}
static inline int MSBDBattInsideDarkReads(double l) { return MSBDBattInsideContrast(l, 0) >= MSBDBattInsideContrast(l, 1); }   // (black, not white, on it)
typedef struct { int fillDark, emptyDark; } MSBDBattInsideInks;   // (the number over the fill and over the rest: 1 black, 0 white)
static inline MSBDBattInsideInks MSBDBattInsideInksFor(double iconR, double iconG, double iconB, double fillR, double fillG, double fillB, double fillA) {
    MSBDBattInsideInks k;
    int iconLight = MSBDBattInsideDarkReads(MSBDBattInsideLuminance(iconR, iconG, iconB));   // (the icon's shade: white or black, the nearer)
    k.emptyDark = !iconLight;
    if (fillA != fillA || fillA < 0) fillA = 0;
    if (fillA > 1) fillA = 1;
    double bar = iconLight ? 0.0 : 1.0;   // (under the fill: the bar, the opposite of the icon)
    double rgb[3] = { fillR, fillG, fillB };
    for (int i = 0; i < 3; i++) { double c = rgb[i] != rgb[i] || rgb[i] < 0 ? 0 : rgb[i] > 1 ? 1 : rgb[i]; rgb[i] = fillA * c + (1 - fillA) * bar; }
    k.fillDark = MSBDBattInsideDarkReads(MSBDBattInsideLuminance(rgb[0], rgb[1], rgb[2]));
    return k;
}
// The part of the number over the fill: the fill's rect as the battery view draws it (its own fill layer: from the body's inner left edge, the
// inner width x the level), in the number's coordinates, within the number's bounds (w x h), its corners' radius kept within it; none (w = 0)
// without a fill. Its edge is the split. Where the battery's fill can't be read: the number in one colour, the fill's from 55 % (where the fill
// reaches the number's middle), the rest's below, as before the split.
typedef struct { double x, y, w, h, r; } MSBDBattInsideBox;
static inline MSBDBattInsideBox MSBDBattInsideFillPart(MSBDBattInsideBox fill, double w, double h) {
    MSBDBattInsideBox p = { 0, 0, 0, 0, 0 };
    if (!(w > 0 && h > 0 && fill.w > 0 && fill.h > 0)) return p;
    double x0 = fill.x > 0 ? fill.x : 0, y0 = fill.y > 0 ? fill.y : 0, x1 = fill.x + fill.w, y1 = fill.y + fill.h;
    if (x1 > w) x1 = w;
    if (y1 > h) y1 = h;
    if (!(x1 > x0 && y1 > y0)) return p;   // (outside the number, or not a number)
    p.x = x0; p.y = y0; p.w = x1 - x0; p.h = y1 - y0;
    p.r = fill.r > 0 ? fill.r : 0;
    if (p.r > p.w / 2) p.r = p.w / 2;
    if (p.r > p.h / 2) p.r = p.h / 2;
    return p;
}
static inline int MSBDBattInsideOneInk(double level, MSBDBattInsideInks k) { return level >= 0.55 ? k.fillDark : k.emptyDark; }
#define MSBD_BATT_INSIDE_BODY_SHARE 0.905   // (the body's share of the view's width: the pin takes the rest)
#define MSBD_BATT_INSIDE_FONT_SHARE 0.72    // (the number's size against the body's height)
#endif
