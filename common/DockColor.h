// DockColor.h -- Settings > Dock > Dock Background (1.8.8.1 DOCKCOLOR, KT 15 Nov: "lets also add ability to color the dock"): the stored choice, its
// colour and opacity, and which marks go on the coloured Dock (the running dots and the dividers). Plain C on BarBackground.h's blend and
// BatteryInside.h's WCAG maths; shared by the Dock part (dock/DockColor.m), the Dock's Settings page and the Mac test (tools/test-dockcolor.sh).
//  - Automatic (never set, or anything but "color"): the Dock exactly as iPadOS draws it; nothing of ours is drawn or touched.
//  - Color: the colour at its opacity over iPadOS's own Dock glass (KT's decision 2: the blur shows under a see-through colour, 100 % is solid),
//    or with Dock Style Frosted in place of Frosted's tint (decision 1); Glass Shelf keeps its glass. Not linked to the menu bar: never set, the
//    colour is Status Bar Background's at that moment, else #242225 (decision 3), and Settings stores it the first time Color is chosen.
// The marks (critique B2): what is under our colour is iPadOS's material, and it is NOT light in Light Mode and dark in Dark Mode whatever is
// behind -- it follows what is behind in both modes (measured on the iPad 2, 16.7.7, and the A12Z, 18.5, 15 Nov: plans/release-1.8.7.6.md, the two
// "DOCKCOLOR material measured" sections; the two agree within one sRGB step). So the colour at its opacity is blended over the darkest and the
// lightest material measured for the mode, and the marks are dark when black at its worst (over the darkest) reads at least as well as white at
// its worst (over the lightest) -- MSBDBarTextDarkOver's comparison, without its light-colour gate (a dark colour gives light marks the same way).
// One answer, no "in between": when it is the mode's own (dark marks in Light Mode, light in Dark Mode) iPadOS's own marks stay, untouched;
// only an answer that differs puts ours on. At 0 % the answer is always the mode's own.
#ifndef MSBD_DOCK_COLOR_H
#define MSBD_DOCK_COLOR_H
#include "BarBackground.h"
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <stdlib.h>

#define kMSBDDockBackgroundKey "dockBackground"                 // (com.besiktasliseba.dockmagnification) "color"; anything else, or never set: Automatic
#define kMSBDDockBackgroundColorKey "dockBackgroundColor"       // "#RRGGBB"; never set: Status Bar Background's colour (MSBDDockColorStart)
#define kMSBDDockBackgroundOpacityKey "dockBackgroundOpacity"   // 0 .. 1; never set: 0.7 (as the menu bar's)
#define kMSBDDockColorNote "com.besiktasliseba.dockmagnification/colorChanged"   // (the colour well and the slider: the Dock's light path, no reload)
#define kMSBDBarColorDomain "com.besiktasliseba.macstatusbar"   // (Status Bar Background's colour, read for the first time only)
#define kMSBDBarColorKey "backgroundColor"
#define MSBD_DOCK_COLOR_FALLBACK 0x242225                       // (the menu bar's own when nothing is stored)
#define MSBD_DOCK_COLOR_OPACITY 0.7

static inline int MSBDDockBackgroundOn(const char *s) { return s && !strcmp(s, "color"); }
static inline double MSBDDockColorOpacity(int stored, double a) { return stored ? MSBDBarOpacity(a) : MSBD_DOCK_COLOR_OPACITY; }

// "#RRGGBB" or "#RGB" (the # optional, spaces around allowed) to sRGB 0..1. Returns 0, rgb untouched, for anything else.
static inline int MSBDDockColorParse(const char *s, double rgb[3]) {
    if (!s) return 0;
    while (*s == ' ' || *s == '\t') s++;
    if (*s == '#') s++;
    char h[8] = { 0 };
    size_t n = 0;
    while (s[n] && isxdigit((unsigned char)s[n]) && n < 7) { h[n] = s[n]; n++; }
    for (const char *t = s + n; *t; t++) if (*t != ' ' && *t != '\t') return 0;
    if (n != 6 && n != 3) return 0;
    unsigned v[3];
    for (int k = 0; k < 3; k++) {
        char two[3] = { n == 6 ? h[2 * k] : h[k], n == 6 ? h[2 * k + 1] : h[k], 0 };
        v[k] = (unsigned)strtoul(two, NULL, 16);
    }
    for (int k = 0; k < 3; k++) rgb[k] = v[k] / 255.0;
    return 1;
}
static inline void MSBDDockColorFromInt(unsigned rgb24, double rgb[3]) {
    rgb[0] = ((rgb24 >> 16) & 0xff) / 255.0; rgb[1] = ((rgb24 >> 8) & 0xff) / 255.0; rgb[2] = (rgb24 & 0xff) / 255.0;
}
// sRGB 0..1 to "#RRGGBB" (out: 8 bytes), each channel clamped and rounded as Settings' colour well stores it.
static inline void MSBDDockColorFormat(const double rgb[3], char out[8]) {
    int b[3];
    for (int k = 0; k < 3; k++) { double c = rgb[k] != rgb[k] || rgb[k] < 0 ? 0 : rgb[k] > 1 ? 1 : rgb[k]; b[k] = (int)(c * 255.0 + 0.5); }
    snprintf(out, 8, "#%02X%02X%02X", b[0], b[1], b[2]);
}
// The Dock's colour: the one stored for the Dock; never stored (or unreadable), Status Bar Background's as stored now; else #242225. Returns 1 when
// the Dock's own was used (Settings stores the result the first time Color is chosen, so it does not follow the menu bar after that).
static inline int MSBDDockColorStart(const char *dockHex, const char *barHex, double rgb[3]) {
    if (MSBDDockColorParse(dockHex, rgb)) return 1;
    if (!MSBDDockColorParse(barHex, rgb)) MSBDDockColorFromInt(MSBD_DOCK_COLOR_FALLBACK, rgb);
    return 0;
}
// Settings, the first time Color is chosen (the list row, the colour well or the slider while Automatic): the colour to store so the Dock's is its
// own from then on (no live link to the menu bar, decision 3) -- Status Bar Background's as stored now, else #242225. Returns 0 (out untouched)
// when the Dock's own is stored already.
static inline int MSBDDockColorFirstStore(const char *dockHex, const char *barHex, char out[8]) {
    double rgb[3];
    if (MSBDDockColorStart(dockHex, barHex, rgb)) return 0;
    MSBDDockColorFormat(rgb, out);
    return 1;
}

// ---- what is under our colour, measured (sRGB grey 0..255, the darkest and the lightest per mode) ----
// iPadOS's Dock material (Dock Style Default): Light Mode 58 (A12Z; iPad 2 59) to 246, Dark Mode 37 to 210, over a black and a white Desktop
// Picture (luminance Light 0.042-0.923, Dark 0.019-0.646). Frosted's blur alone (UIBlurEffectStyleSystemThinMaterial, under the colour in place of
// Frosted's tint): the A12Z's Frosted rows with that tint taken out (Light 0.97 at 0.38, Dark 0.12 at 0.42, sRGB blend): Light 142 to 245, Dark 31 to
// 126. Not measured yet (device rows): iPadOS 15 and 17, Reduce Transparency's opaque grey, Increase Contrast.
enum { MSBDDockUnderMaterial = 0, MSBDDockUnderFrosted = 1 };
typedef struct { double darkest, lightest; } MSBDDockUnder;
static inline MSBDDockUnder MSBDDockUnderRange(int under, int darkMode) {
    MSBDDockUnder u;
    if (under == MSBDDockUnderFrosted) { u.darkest = darkMode ? 31 : 142; u.lightest = darkMode ? 126 : 245; }
    else { u.darkest = darkMode ? 37 : 58; u.lightest = darkMode ? 210 : 246; }
    u.darkest /= 255.0; u.lightest /= 255.0;
    return u;
}
// The marks for the colour (sRGB 0..1) at opacity a over that range: 1 dark (black at its worst reads at least as well as white at its worst), 0 light.
static inline int MSBDDockMarksDarkOver(double r, double g, double b, double a, int under, int darkMode) {
    a = MSBDBarOpacity(a);
    MSBDDockUnder u = MSBDDockUnderRange(under, darkMode);
    double overDark = MSBDBattInsideLuminance(MSBDBarOver(r, a, u.darkest), MSBDBarOver(g, a, u.darkest), MSBDBarOver(b, a, u.darkest));
    double overLight = MSBDBattInsideLuminance(MSBDBarOver(r, a, u.lightest), MSBDBarOver(g, a, u.lightest), MSBDBarOver(b, a, u.lightest));
    return MSBDBattInsideContrast(overDark, 0) >= MSBDBattInsideContrast(overLight, 1);
}
// What the Dock shows: MSBDDockMarksApple (iPadOS's own marks, nothing of Apple's touched), or ours: MSBDDockMarksLight / MSBDDockMarksDark.
// shown: our colour is drawn on that Dock now (Default or Frosted; not Glass Shelf, not Automatic).
enum { MSBDDockMarksApple = -1, MSBDDockMarksLight = 0, MSBDDockMarksDark = 1 };
static inline int MSBDDockMarks(int shown, double r, double g, double b, double a, int under, int darkMode) {
    if (!shown) return MSBDDockMarksApple;
    int dark = MSBDDockMarksDarkOver(r, g, b, a, under, darkMode);
    return dark == !darkMode ? MSBDDockMarksApple : dark;   // (iPadOS's own: dark in Light Mode, light in Dark Mode)
}
// Our marks' colours (sRGB grey, alpha): the dots as iPadOS's labelColor is in each mode (measured: exactly black / white), the dividers a line of
// black at 0.25 or white at 0.30 (iPadOS's own measured 1.3 to 2.3:1 against its material; ours about the same against the colour).
static inline void MSBDDockMarkDot(int marks, double *grey, double *alpha) { *grey = marks == MSBDDockMarksDark ? 0.0 : 1.0; *alpha = 1.0; }
static inline void MSBDDockMarkLine(int marks, double *grey, double *alpha) { int d = marks == MSBDDockMarksDark; *grey = d ? 0.0 : 1.0; *alpha = d ? 0.25 : 0.30; }
#endif
