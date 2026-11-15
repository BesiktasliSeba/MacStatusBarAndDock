// BarBackground.h -- Status Bar Background (Settings > Status Bar): which background our menu bar takes and which text goes on it (1.8.7.5
// WHITEBAR, KT 14 Nov on the 17.5: "if I make the status bar white, the text doesnt go black so it becomes a white bar"). Plain C (CoreGraphics for
// a picture's strip), with BatteryInside.h's WCAG helpers (the same contrast maths as the battery's number): tools/test-barbackground.sh runs it
// with the bar's own code.
// Before, iPadOS picked the text (light or dark, for the wallpaper or the app it thinks is behind the bar) and our background followed it: the
// chosen colour under light text, a light grey under dark text. A light colour under light text was white on white.
// Now the text follows the bar, as on a Mac:
//  - A light colour (black reads better on it than white by WCAG's contrast ratio: from a relative luminance of about 0.18) is always the
//    background, and the bar's text and icons turn black when the bar it makes is light over what is behind it. Drawn at its opacity a, the bar
//    is a x colour + (1 - a) x what is behind (per sRGB channel, as the screen blends), so it is only as light as what shows through lets it be:
//    0.36 white over black is a dark grey, over a light picture nearly white. What is behind is known in two ways (1.8.7.5 round 1, the review of
//    WHITEBAR: one guess for every place, the darkest to a mid grey, put black text on a dark grey bar over a dark app, 3.1:1 where iPadOS's
//    white read 6.7:1):
//     - our Desktop Picture under the bar (the Home Screen, a desktop with windows): iPadOS picks its text for its own wallpaper there, which ours
//       hides, so the picture's own top strip is taken, as decoded (MSBDBarTopStrip: its darkest and lightest part): the text is black when black
//       text at its worst there reads at least as well as white text at its worst (MSBDBarTextDarkOver). KT's High Sierra sky under white at
//       0.36: nearly white, black. A dark picture: a dark grey, iPadOS's text.
//     - anywhere else iPadOS's text is for what is behind (an app's own style, iPadOS's wallpaper): kept, unless the bar is light even over black
//       (MSBDBarTextDarkAnywhere: white from an opacity of about 0.47; at 0.36 over a dark app iPadOS's white text on the dark grey). Over a light
//       app iPadOS's text is black already.
//  - A dark colour: as before (the colour under light text, a light grey under dark text, the text iPadOS's).
#ifndef MSBD_BAR_BACKGROUND_H
#define MSBD_BAR_BACKGROUND_H
#include "BatteryInside.h"
#include <CoreGraphics/CoreGraphics.h>

static inline double MSBDBarOpacity(double a) { return a != a || a < 0 ? 0 : a > 1 ? 1 : a; }
static inline double MSBDBarOver(double c, double a, double behind) {   // (one sRGB channel of the colour at opacity a over what is behind)
    c = c != c || c < 0 ? 0 : c > 1 ? 1 : c;
    return a * c + (1 - a) * behind;
}
// The chosen colour is light: black reads on it at least as well as white (opaque).
static inline int MSBDBarColorIsLight(double r, double g, double b) { return MSBDBattInsideDarkReads(MSBDBattInsideLuminance(r, g, b)); }
// The bar's text and icons are black: a light colour whose bar, at its opacity a, is light over what is behind it, from its darkest to its lightest
// (sRGB colours): black text at its worst (the bar over the darkest) reads at least as well as white text at its worst (over the lightest).
static inline int MSBDBarTextDarkOver(double r, double g, double b, double a, const double darkest[3], const double lightest[3]) {
    a = MSBDBarOpacity(a);
    if (a <= 0 || !MSBDBarColorIsLight(r, g, b)) return 0;
    double overDark = MSBDBattInsideLuminance(MSBDBarOver(r, a, darkest[0]), MSBDBarOver(g, a, darkest[1]), MSBDBarOver(b, a, darkest[2]));
    double overLight = MSBDBattInsideLuminance(MSBDBarOver(r, a, lightest[0]), MSBDBarOver(g, a, lightest[1]), MSBDBarOver(b, a, lightest[2]));
    return MSBDBattInsideContrast(overDark, 0) >= MSBDBattInsideContrast(overLight, 1);
}
// ... light even over black: black text whatever is behind (where iPadOS's text is for what is behind, it is kept otherwise)
static inline int MSBDBarTextDarkAnywhere(double r, double g, double b, double a) {
    static const double black[3] = { 0, 0, 0 };
    return MSBDBarTextDarkOver(r, g, b, a, black, black);
}
// What is under the bar in a picture: its top strip (rows: the bar's height in the picture's pixels), in 32 columns, each averaged over the strip,
// in sRGB: the darkest and the lightest column (by luminance). Returns 0 when it cannot be read.
#define MSBD_BAR_STRIP_COLUMNS 32
static inline int MSBDBarTopStrip(CGImageRef img, double rows, double darkest[3], double lightest[3]) {
    size_t w = img ? CGImageGetWidth(img) : 0, h = img ? CGImageGetHeight(img) : 0;
    if (!w || !h || !(rows >= 1)) return 0;
    CGImageRef top = CGImageCreateWithImageInRect(img, CGRectMake(0, 0, w, rows < h ? rows : h));
    if (!top) return 0;
    enum { kCols = MSBD_BAR_STRIP_COLUMNS, kRows = 4 };
    unsigned char px[kCols * kRows * 4] = { 0 };
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = srgb ? CGBitmapContextCreate(px, kCols, kRows, 8, kCols * 4, srgb, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault) : NULL;
    if (c) {
        CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1); CGContextFillRect(c, CGRectMake(0, 0, kCols, kRows));   // (a transparent part: black, as nothing is lit there)
        CGContextDrawImage(c, CGRectMake(0, 0, kCols, kRows), top);
        CGContextRelease(c);
    }
    if (srgb) CGColorSpaceRelease(srgb);
    CGImageRelease(top);
    if (!c) return 0;
    double lo = 2, hi = -1;
    for (int x = 0; x < kCols; x++) {
        double rgb[3] = { 0, 0, 0 };
        for (int y = 0; y < kRows; y++) for (int k = 0; k < 3; k++) rgb[k] += px[(y * kCols + x) * 4 + k] / 255.0 / kRows;
        double l = MSBDBattInsideLuminance(rgb[0], rgb[1], rgb[2]);
        if (l < lo) { lo = l; for (int k = 0; k < 3; k++) darkest[k] = rgb[k]; }
        if (l > hi) { hi = l; for (int k = 0; k < 3; k++) lightest[k] = rgb[k]; }
    }
    return 1;
}
// The background is the chosen colour (else the light grey): a light colour always, a dark one under light text.
static inline int MSBDBarBackgroundChosen(int colorLight, int textLight) { return colorLight || textLight; }
#endif
