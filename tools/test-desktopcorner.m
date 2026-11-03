// Mac test of the desktop app icons' corners (common/DesktopAppCorner.h; 1.7.9 item 4): the slider's steps and range, the corner in force (never
// set = the Home Screen's shape; once moved = the user's own, whatever the Home Screen's shape does later), the radius for a side, the Home
// Screen's shape as published for Settings and what the slider shows, the shape itself (MSBDDesktopCornerPathCreate, the very drawing the iPad
// uses: iPadOS's own corner at the usual sizes, an exact circle at the end, no jump between), and the reading of a theme's mask: the nearest
// corner to a picture and whether the picture is a shape of the theme's own; a theme picture's painted frame (a tile inside a band: KT's
// iOSX), found or rightly not (full-bleed art, Apple's Clock face and Settings gear), and how much of the tile a corner may show.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <math.h>
#include "../common/DesktopAppCorner.h"
static int fails = 0, checks = 0;
static void Check(int ok, const char *what) { checks++; if (!ok) { fails++; printf("FAIL %s\n", what); } }
static int Near(double a, double b, double e) { return fabs(a - b) <= e; }

// ---- pictures: an n x n alpha bitmap of a shape ----
static void Fill(CGPathRef p, int n, unsigned char *alpha) {
    memset(alpha, 0, (size_t)n * n);
    CGContextRef c = CGBitmapContextCreate(alpha, n, n, 8, n, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextAddPath(c, p); CGContextFillPath(c); CGContextRelease(c);
}
// The desktop's own shape (the header's path, as DesktopCorner.h fills it), filled; ctx: an inset in pixels (a mask with margins), or NULL.
static void Continuous(void *ctx, double fraction, int n, unsigned char *alpha) {
    double inset = ctx ? *(double *)ctx : 0.0;
    memset(alpha, 0, (size_t)n * n);
    CGContextRef c = CGBitmapContextCreate(alpha, n, n, 8, n, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextTranslateCTM(c, inset, inset);
    CGPathRef p = MSBDDesktopCornerPathCreate(n - 2.0 * inset, fraction);
    CGContextAddPath(c, p); CGContextFillPath(c); CGPathRelease(p); CGContextRelease(c);
}
// iPadOS's own corner: UIBezierPath's continuous rounded rectangle (its curve as PaintCode published it, "Code for iOS 7 rounded rectangles"),
// for radii up to its limit (half the side over 1.52866483).
static void AppleCorner(int n, double fraction, unsigned char *alpha) {
    double r = fmin(fraction * n, n / 2.0 / 1.52866483), W = n, H = n;
    CGMutablePathRef p = CGPathCreateMutable();
#define TR(X, Y) W - (X) * r, (Y) * r
#define BR(X, Y) W - (X) * r, H - (Y) * r
#define BL(X, Y) (X) * r, H - (Y) * r
#define TL(X, Y) (X) * r, (Y) * r
    CGPathMoveToPoint(p, NULL, TL(1.52866483, 0)); CGPathAddLineToPoint(p, NULL, TR(1.52866471, 0));
    CGPathAddCurveToPoint(p, NULL, TR(1.08849323, 0), TR(0.86840689, 0), TR(0.66993427, 0.06549600)); CGPathAddLineToPoint(p, NULL, TR(0.63149399, 0.07491100));
    CGPathAddCurveToPoint(p, NULL, TR(0.37282392, 0.16905899), TR(0.16906013, 0.37282401), TR(0.07491176, 0.63149399));
    CGPathAddCurveToPoint(p, NULL, TR(0.06549569, 0.86840701), TR(0, 1.08849299), TR(0, 1.52866483)); CGPathAddLineToPoint(p, NULL, BR(0, 1.52866471));
    CGPathAddCurveToPoint(p, NULL, BR(0, 1.08849323), BR(0, 0.86840689), BR(0.06549600, 0.66993427)); CGPathAddLineToPoint(p, NULL, BR(0.07491100, 0.63149399));
    CGPathAddCurveToPoint(p, NULL, BR(0.16905899, 0.37282392), BR(0.37282401, 0.16906013), BR(0.63149399, 0.07491176));
    CGPathAddCurveToPoint(p, NULL, BR(0.86840701, 0.06549569), BR(1.08849299, 0), BR(1.52866483, 0)); CGPathAddLineToPoint(p, NULL, BL(1.52866471, 0));
    CGPathAddCurveToPoint(p, NULL, BL(1.08849323, 0), BL(0.86840689, 0), BL(0.66993427, 0.06549600)); CGPathAddLineToPoint(p, NULL, BL(0.63149399, 0.07491100));
    CGPathAddCurveToPoint(p, NULL, BL(0.37282392, 0.16905899), BL(0.16906013, 0.37282401), BL(0.07491176, 0.63149399));
    CGPathAddCurveToPoint(p, NULL, BL(0.06549569, 0.86840701), BL(0, 1.08849299), BL(0, 1.52866483)); CGPathAddLineToPoint(p, NULL, TL(0, 1.52866471));
    CGPathAddCurveToPoint(p, NULL, TL(0, 1.08849323), TL(0, 0.86840689), TL(0.06549600, 0.66993427)); CGPathAddLineToPoint(p, NULL, TL(0.07491100, 0.63149399));
    CGPathAddCurveToPoint(p, NULL, TL(0.16905899, 0.37282392), TL(0.37282401, 0.16906013), TL(0.63149399, 0.07491176));
    CGPathAddCurveToPoint(p, NULL, TL(0.86840701, 0.06549569), TL(1.08849299, 0), TL(1.52866483, 0));
#undef TR
#undef BR
#undef BL
#undef TL
    CGPathCloseSubpath(p);
    Fill(p, n, alpha); CGPathRelease(p);
}
static void CircularArcs(int n, double fraction, unsigned char *alpha) {   // (an older theme's mask: a plain rounded rectangle)
    double r = MSBDDesktopCornerRadius(fraction, n);
    CGPathRef p = CGPathCreateWithRoundedRect(CGRectMake(0, 0, n, n), r, r, NULL);
    Fill(p, n, alpha); CGPathRelease(p);
}
static void Shape(int n, int sides, double inner, unsigned char *alpha) {   // (a regular polygon, or a star when inner > 0, filling the square)
    CGMutablePathRef p = CGPathCreateMutable();
    int pts = inner > 0 ? sides * 2 : sides;
    for (int i = 0; i < pts; i++) {
        double a = M_PI * 2.0 * i / pts - M_PI / 2.0, rad = (inner > 0 && (i & 1)) ? inner : 1.0;
        double x = n / 2.0 + cos(a) * rad * n / 2.0, y = n / 2.0 + sin(a) * rad * n / 2.0;
        if (i == 0) CGPathMoveToPoint(p, NULL, x, y); else CGPathAddLineToPoint(p, NULL, x, y);
    }
    CGPathCloseSubpath(p);
    Fill(p, n, alpha); CGPathRelease(p);
}
static void Superellipse(int n, double e, unsigned char *alpha) {   // (|x|^e + |y|^e = 1: SnowBoard's mask on KT's M1 is one, e 2.7)
    CGMutablePathRef p = CGPathCreateMutable();
    for (int i = 0; i <= 1440; i++) {
        double t = M_PI * 2.0 * i / 1440.0, c = cos(t), s = sin(t);
        double x = copysign(pow(fabs(c), 2.0 / e), c), y = copysign(pow(fabs(s), 2.0 / e), s);
        double px = n / 2.0 + x * n / 2.0, py = n / 2.0 + y * n / 2.0;
        if (i == 0) CGPathMoveToPoint(p, NULL, px, py); else CGPathAddLineToPoint(p, NULL, px, py);
    }
    CGPathCloseSubpath(p);
    Fill(p, n, alpha); CGPathRelease(p);
}
// ---- theme pictures with a painted frame (made here: no theme's own pictures in the tree) ----
enum { TW = 256 };
static unsigned char gPic[TW * TW * 4];
static void PutPx(int x, int y, double r, double g, double b, double a) {   // (premultiplied)
    unsigned char *q = gPic + ((long)y * TW + x) * 4; q[0] = (unsigned char)lround(r * a * 255); q[1] = (unsigned char)lround(g * a * 255); q[2] = (unsigned char)lround(b * a * 255); q[3] = (unsigned char)lround(a * 255);
}
// art: diagonal stripes and a pale disc (the glyph); frame: the art outside a tile (inset `band` px, corner `f`) darkened by `dark` (topDark on the
// upper third); clear: the band transparent instead (a pre-shaped picture). The tile's own alpha comes from the shape filled into a mask.
static int gFaintSide = 0;   // (which third of the picture is darkened only by topDark: 0 the top, 1 the right, 2 the bottom, 3 the left)
static void Themed(int bandL, int bandT, int bandR, int bandB, double f, double dark, double topDark, int clear, int framed) {
    unsigned char tile[TW * TW];
    memset(tile, 0, sizeof tile);
    CGContextRef c = CGBitmapContextCreate(tile, TW, TW, 8, TW, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGPathRef p = MSBDDesktopCornerPathCreate(TW - bandL - bandR, f);
    CGContextTranslateCTM(c, bandL, bandB);   // (Core Graphics' y goes up: the bottom band first)
    CGContextAddPath(c, p); CGContextFillPath(c); CGPathRelease(p); CGContextRelease(c);
    for (int y = 0; y < TW; y++) for (int x = 0; x < TW; x++) {
        int stripe = ((x + y) / 23) % 2;
        double r = stripe ? 0.95 : 0.80, g = stripe ? 0.62 : 0.70, b = stripe ? 0.10 : 0.20;
        double dx = x - TW / 2.0, dy = y - TW / 2.0;
        if (dx * dx + dy * dy < 60 * 60) { r = 0.97; g = 0.97; b = 0.95; }
        int faintThird = gFaintSide == 0 ? y < TW / 3 : gFaintSide == 1 ? x >= TW - TW / 3 : gFaintSide == 2 ? y >= TW - TW / 3 : x < TW / 3;
        double in = tile[(long)y * TW + x] / 255.0, d = faintThird ? topDark : dark;
        if (!framed) { PutPx(x, y, r, g, b, 1); continue; }
        if (clear) { PutPx(x, y, r, g, b, in); continue; }
        double k = in + (1 - in) * (1 - d);   // (the band: the same art, darker)
        PutPx(x, y, r * k, g * k, b * k, 1);
    }
}
static void Disc(double bg, double fg, double R0, double R1) {   // (a disc or a ring on a plain square: Apple's Clock face, Settings' gear)
    for (int y = 0; y < TW; y++) for (int x = 0; x < TW; x++) {
        double dx = x + 0.5 - TW / 2.0, dy = y + 0.5 - TW / 2.0, d = sqrt(dx * dx + dy * dy) / TW, a = (d >= R0 && d <= R1) ? 1 : 0;
        double v = bg * (1 - a) + fg * a; PutPx(x, y, v, v, v, 1);
    }
}
static double Filled(const unsigned char *a, int n) { unsigned long long s = 0; for (int i = 0; i < n * n; i++) s += a[i]; return s / 255.0 / ((double)n * n); }

int main(void) {
  @autoreleasepool {
    // ---- the slider: 0 (a square) to 0.5 (a circle), on 1 % steps ----
    Check(Near(MSBDDesktopCornerSnap(0), 0, 1e-12) && Near(MSBDDesktopCornerSnap(0.5), 0.5, 1e-12), "the ends stay");
    Check(Near(MSBDDesktopCornerSnap(0.2249), 0.22, 1e-9) && Near(MSBDDesktopCornerSnap(0.2251), 0.23, 1e-9) && Near(MSBDDesktopCornerSnap(0.3849), 0.38, 1e-9), "to the nearest 1 % step");
    Check(Near(MSBDDesktopCornerSnap(-0.2), 0, 1e-12) && Near(MSBDDesktopCornerSnap(0.9), 0.5, 1e-12) && Near(MSBDDesktopCornerSnap(7), 0.5, 1e-12), "clamped to the range");
    Check(MSBDDesktopCornerSnap(NAN) < 0 && MSBDDesktopCornerSnap(INFINITY) < 0 && MSBDDesktopCornerSnap(-INFINITY) < 0, "no number: -1 (nothing used)");
    int steps = 0; double last = -1;
    for (double v = -0.1; v <= 0.6; v += 0.0007) { double s = MSBDDesktopCornerSnap(v); if (!Near(s, last, 1e-12)) { steps++; last = s; } }
    Check(steps == 51, "51 corners across the slider (0, 0.01, ..., 0.5)");
    // ---- the corner in force: never set = the Home Screen's shape (-1: the app icon as the Home Screen shows it); set = the user's own ----
    Check(MSBDDesktopCornerInForce(0, 0.3) < 0 && MSBDDesktopCornerInForce(0, 0) < 0, "never set: the Home Screen's shape (-1)");
    Check(Near(MSBDDesktopCornerInForce(1, 0.3), 0.3, 1e-12) && Near(MSBDDesktopCornerInForce(1, 0), 0, 1e-12), "set: the stored corner, a square included");
    Check(Near(MSBDDesktopCornerInForce(1, 0.2251), 0.23, 1e-9) && Near(MSBDDesktopCornerInForce(1, 0.75), 0.5, 1e-12), "set: snapped and clamped as the slider does");
    Check(MSBDDesktopCornerInForce(1, NAN) < 0, "a stored value that is no number: as never set");
    // ---- the radius: a fraction of the side, so Icon Size keeps the look ----
    Check(Near(MSBDDesktopCornerRadius(0.25, 64), 16, 1e-12) && Near(MSBDDesktopCornerRadius(0.25, 96), 24, 1e-12), "a quarter of 64 and of 96 pt: 16 and 24 pt");
    Check(Near(MSBDDesktopCornerRadius(0.3, 40) / 40, MSBDDesktopCornerRadius(0.3, 96) / 96, 1e-12), "the same shape at every Icon Size");
    Check(Near(MSBDDesktopCornerRadius(0.5, 76), 38, 1e-12) && Near(MSBDDesktopCornerRadius(0.8, 76), 38, 1e-12) && Near(MSBDDesktopCornerRadius(-1, 76), 0, 1e-12), "never past a circle, never below a square");
    Check(Near(MSBDDesktopCornerRadius(NAN, 76), 0, 1e-12) && Near(MSBDDesktopCornerRadius(0.3, 0), 0, 1e-12), "no number, no side: no corner");
    // ---- the Home Screen's shape as published, and what Settings' slider shows ----
    int custom = -1;
    Check(Near(MSBDDesktopThemeCornerFromState(MSBDDesktopThemeCornerState(0.3849, 0), &custom), 0.3849, 1e-9) && custom == 0, "a corner published and read back (to 0.01 %)");
    Check(Near(MSBDDesktopThemeCornerFromState(MSBDDesktopThemeCornerState(0.2, 1), &custom), 0.2, 1e-9) && custom == 1, "a theme's own shape: said with its nearest corner");
    Check(Near(MSBDDesktopThemeCornerFromState(MSBDDesktopThemeCornerState(0, 0), &custom), 0, 1e-12) && custom == 0, "a square theme (0) is a corner too, not 'unknown'");
    Check(MSBDDesktopThemeCornerFromState(0, &custom) < 0 && custom == 0, "nothing published: unknown");
    Check(MSBDDesktopThemeCornerState(-0.1, 0) == 0 && MSBDDesktopThemeCornerState(NAN, 1) == 0, "no corner: nothing published");
    Check(Near(MSBDDesktopThemeCornerFromState(MSBDDesktopThemeCornerState(0.8, 0), NULL), 0.5, 1e-12), "past a circle: a circle");
    Check(MSBDDesktopThemeCornerFromState(9999, &custom) < 0 && custom == 0, "a state out of range: unknown");
    unsigned long long theme = MSBDDesktopThemeCornerState(0.3849, 0);
    Check(Near(MSBDDesktopCornerShown(0, 0, theme), 0.3849, 1e-9), "never set: the slider starts at the Home Screen's shape");
    Check(Near(MSBDDesktopCornerShown(0, 0, 0), MSBD_DESKTOP_CORNER_IPADOS, 1e-12), "never set, nothing published yet: iPadOS's own corner");
    Check(Near(MSBDDesktopCornerShown(1, 0.12, theme), 0.12, 1e-12) && Near(MSBDDesktopCornerShown(1, 0.12, MSBDDesktopThemeCornerState(0.45, 0)), 0.12, 1e-12),
          "set: the user's corner, whatever the Home Screen's shape is or becomes (KT 2 Nov)");
    Check(Near(MSBDDesktopCornerShown(1, NAN, theme), 0.3849, 1e-9), "a stored value that is no number: shown as never set");

    // ---- the shape: iPadOS's corner at the usual sizes, a square to an exact circle without a jump (UIBezierPath's rounded rectangle jumps to a
    //      circle past a third of the side, Core Animation's continuous corner pinches at the sides near a circle: both seen on the iPad) ----
    enum { N = 148 };   // (a 74 pt icon at 2x)
    unsigned char pic[N * N], scratch[N * N], ref[N * N];
    double prev = -1, worst = 0; int down = 1;
    for (int k = 0; k <= 50; k++) { Continuous(NULL, k * 0.01, N, pic); double f = Filled(pic, N); if (prev >= 0) { worst = fmax(worst, prev - f); if (f > prev + 1e-9) down = 0; } prev = f; }
    Check(down && worst < 0.01, "each 1 % step rounds a little more: no jump anywhere from the square to the circle");
    Continuous(NULL, 0, N, pic); double sq = Filled(pic, N);
    Continuous(NULL, 0.5, N, pic); Superellipse(N, 2.0, ref);
    Check(Near(sq, 1, 1e-9) && MSBDCornerOutlineGap(pic, ref, N) < 0.05, "0 is the square, 0.5 an exact circle");
    int apple = 1;
    for (double f = 0.1; f <= 0.3; f += 0.05) { Continuous(NULL, f, N, pic); AppleCorner(N, f, ref); if (MSBDCornerOutlineGap(pic, ref, N) > 0.2) { apple = 0; printf("  (corner %.2f: %.3f px from iPadOS's)\n", f, MSBDCornerOutlineGap(pic, ref, N)); } }
    Check(apple, "iPadOS's own corner (UIBezierPath's continuous one) at 0.1 to 0.3 of the side: within 0.2 px at 148 px");
    AppleCorner(N, 0.225, ref); double gapA = 0, fa = MSBDCornerFit(ref, N, Continuous, NULL, scratch, &gapA);
    Check(Near(fa, 0.225, 0.003) && !MSBDCornerIsCustom(gapA), "  ... read back from an app icon of iPadOS (13.5 of 60 pt): 0.225, a rounded square");
    { CGPathRef a = MSBDDesktopCornerPathCreate(60, 0.3), b = MSBDDesktopCornerPathCreate(120, 0.3); CGRect ra = CGPathGetPathBoundingBox(a), rb = CGPathGetPathBoundingBox(b);
      Check(Near(ra.size.width, 60, 1e-6) && Near(rb.size.width, 120, 1e-6) && Near(ra.origin.x, 0, 1e-6) && Near(rb.origin.y, 0, 1e-6), "the shape fills its square exactly, at any side");
      CGPathRelease(a); CGPathRelease(b); }
    { CGPathRef z = MSBDDesktopCornerPathCreate(0, 0.3); Check(CGPathIsEmpty(z), "no side: no shape"); CGPathRelease(z); }

    // ---- reading a theme's mask: the nearest corner and how far it still is ----
    double gap = 0;
    int recovered = 1, close = 1, rounded = 1;
    const double want[] = { 0, 0.05, 0.1, 0.2, 0.225, 0.3, 0.33, 0.385, 0.42, 0.5 };
    for (unsigned i = 0; i < sizeof want / sizeof *want; i++) {
        Continuous(NULL, want[i], N, pic);
        double f = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
        if (!Near(f, want[i], 0.0008)) { recovered = 0; printf("  (corner %.4f read as %.4f)\n", want[i], f); }
        if (gap > 0.1) close = 0;
        if (MSBDCornerIsCustom(gap)) rounded = 0;
    }
    Check(recovered, "the desktop's own corner read back to 0.08 % of the side (a square, iPadOS's 0.225, past a third, a circle)");
    Check(close && rounded, "  ... matched within a tenth of a pixel: a rounded square, not a shape of its own");
    {   // (the outline gap is in pixels: the same shape at another size gives about the same gap)
        unsigned char small[74 * 74], s2[74 * 74];
        Continuous(NULL, 0.3, 74, small); double g1 = 0; MSBDCornerFit(small, 74, Continuous, NULL, s2, &g1);
        Check(g1 < 0.1, "  ... at 74 px too");
    }
    // SnowBoard's mask on KT's M1 (1.5.37, Custom Corner Radius 27): a squircle |x|^2.7 + |y|^2.7 = 1 (read from its picture at 60 to 240 px)
    Superellipse(N, 2.7, pic); double fsb = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
    Check(fsb > 0.37 && fsb < 0.41 && gap < 0.5, "SnowBoard's mask (KT's M1): its corner about 0.39 of the side, under half a pixel away");
    Check(!MSBDCornerIsCustom(gap), "  ... a rounded square, so the slider starts right on it");
    CircularArcs(N, 0.2, pic); double fca = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
    Check(fca > 0.17 && fca < 0.23 && !MSBDCornerIsCustom(gap), "an older theme's plain rounded rectangle (circular corners): its nearest corner, no shape of its own");
    int squircles = 1;
    for (double e = 3.0; e <= 8.0; e += 1.0) { Superellipse(N, e, pic); MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap); if (MSBDCornerIsCustom(gap) || gap > 0.5) squircles = 0; }
    Check(squircles, "squircles of other kinds (|x|^e + |y|^e = 1, e 3 to 8): their nearest corner, no shape of their own");
    // shapes of a theme's own: no corner is near them
    Shape(N, 6, 0, pic); MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
    Check(MSBDCornerIsCustom(gap), "a hexagon: a shape of its own");
    Shape(N, 5, 0.5, pic); MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
    Check(MSBDCornerIsCustom(gap), "a star: a shape of its own");
    Shape(N, 4, 0, pic); MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
    Check(MSBDCornerIsCustom(gap), "a diamond (a square turned 45 degrees): a shape of its own");
    { double inset = 8; Continuous(&inset, 0.225, N, pic); MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap); }
    Check(MSBDCornerIsCustom(gap), "a rounded square inset from the edges (a mask with margins): a shape of its own");
    Superellipse(N, 2.0, pic); double fc = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
    Check(Near(fc, 0.5, 0.002) && gap < 0.05 && !MSBDCornerIsCustom(gap), "a circle: the circle end of the slider");
    memset(pic, 255, sizeof pic); double fs = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &gap);
    Check(Near(fs, 0, 1e-9) && gap < 0.01, "no mask at all (an opaque square): a square, 0");
    Check(MSBDCornerFit(NULL, N, Continuous, NULL, scratch, &gap) < 0 && MSBDCornerFit(pic, 4, Continuous, NULL, scratch, &gap) < 0, "nothing to read: -1");

    // ---- iPadOS 18 (no app icon of our own): the Home Screen's own app icons read, the median taken, iPadOS's own mask told from an engine's ----
    {
        MSBDCornerReading none = MSBDCornerMedian(NULL, 0), one[1] = { { 0.3, 0.2 } };
        Check(none.fraction < 0 && MSBDCornerMedian(one, 0).fraction < 0, "no reading: none (-1)");
        Check(Near(MSBDCornerMedian(one, 1).fraction, 0.3, 1e-12) && Near(one[0].gap, 0.2, 1e-12), "one reading: that one");
        MSBDCornerReading odd[5] = { { 0.5, 0.03 }, { 0.224, 0.02 }, { 0.5, 0.04 }, { 0.5, 0.05 }, { 0.224, 0.02 } };
        MSBDCornerReading m = MSBDCornerMedian(odd, 5);
        Check(Near(m.fraction, 0.5, 1e-12) && m.gap < 0.06, "five icons, three of them circles (two left as iPadOS masks them): the circle, its own gap with it");
        int sorted = 1; double g5 = 0;
        for (int i = 0; i < 5; i++) {
            if (i && odd[i].fraction < odd[i - 1].fraction) sorted = 0;
            if (Near(odd[i].fraction, 0.224, 1e-12) && !Near(odd[i].gap, 0.02, 1e-12)) sorted = 0;
            if (Near(odd[i].fraction, 0.5, 1e-12)) g5 += odd[i].gap;
        }
        Check(sorted && Near(g5, 0.12, 1e-9), "  ... sorted in place, each gap staying with its corner");
        MSBDCornerReading most[5] = { { 0.224, 0.02 }, { 0.5, 0.03 }, { 0.224, 0.02 }, { 0.224, 0.02 }, { 0.5, 0.03 } };
        Check(Near(MSBDCornerMedian(most, 5).fraction, 0.224, 1e-12), "three of five as iPadOS masks them: iPadOS's");
        MSBDCornerReading even[2] = { { 0.5, 0.03 }, { 0.224, 0.02 } };
        Check(Near(MSBDCornerMedian(even, 2).fraction, 0.5, 1e-12), "an even count: the rounder of the two middle readings");
        // iPadOS's own mask as read (18.5 without an engine: 0.224 where SpringBoard says 0.225), an engine's shapes, SpringBoard's corner beside them
        AppleCorner(N, 0.224, ref); MSBDCornerReading own; own.fraction = MSBDCornerFit(ref, N, Continuous, NULL, scratch, &own.gap);
        Check(MSBDCornerIsSpringBoards(own, 0.225), "iPadOS's own mask read from an app icon (0.224 of the side): SpringBoard's corner, no engine");
        Superellipse(N, 2.0, pic); MSBDCornerReading circle; circle.fraction = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &circle.gap);
        Check(!MSBDCornerIsSpringBoards(circle, 0.225) && Near(circle.fraction, 0.5, 0.002) && !MSBDCornerIsCustom(circle.gap), "FrostBoard's circle (KT's A12Z): an engine's shape, the circle end of the slider");
        Superellipse(N, 2.7, pic); MSBDCornerReading sb; sb.fraction = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &sb.gap);
        Check(!MSBDCornerIsSpringBoards(sb, 0.225), "SnowBoard's squircle (0.39 of the side): an engine's shape");
        Shape(N, 5, 0.5, pic); MSBDCornerReading star; star.fraction = MSBDCornerFit(pic, N, Continuous, NULL, scratch, &star.gap);
        MSBDCornerReading starNear = { 0.225, star.gap };
        Check(!MSBDCornerIsSpringBoards(starNear, 0.225), "a shape of a theme's own is never iPadOS's, whatever its nearest corner");
        MSBDCornerReading in = { 0.2349, 0.1 }, out = { 0.2351, 0.1 }, low = { 0.2151, 0.1 }, gone = { -1, 0.1 };
        Check(MSBDCornerIsSpringBoards(in, 0.225) && !MSBDCornerIsSpringBoards(out, 0.225) && MSBDCornerIsSpringBoards(low, 0.225) && !MSBDCornerIsSpringBoards(gone, 0.225),
              "within 1 % of the side of SpringBoard's corner: iPadOS's own; past it, or no reading: not");
    }

    // ---- a theme picture's painted frame: found where a theme painted one (a tile inside a band), never in a full-bleed picture ----
    MSBDPaintedTile tt;
    Themed(16, 16, 16, 16, 0.2, 0.3, 0.3, 0, 1); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
    Check(tt.found && Near(tt.x0, 16.0 / TW, 1.5 / TW) && Near(tt.y0, 16.0 / TW, 1.5 / TW) && Near(tt.x1, 1 - 16.0 / TW, 1.5 / TW) && Near(tt.y1, 1 - 16.0 / TW, 1.5 / TW),
          "a tile in a darker band (KT's iOSX: 16 of 256 px): its box, to a pixel and a half");
    Check(tt.found && Near(tt.fraction, 0.2, 0.03), "  ... and its corner (0.2 of the tile)");
    int faintOK = 1;
    for (gFaintSide = 0; gFaintSide < 4; gFaintSide++) {   // (the corner is read from the two corners away from the faint side, whichever it is)
        Themed(16, 16, 16, 16, 0.2, 0.3, 0.035, 0, 1); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
        if (!(tt.found && Near(tt.x0, 16.0 / TW, 1.5 / TW) && Near(tt.y0, 16.0 / TW, 1.5 / TW) && Near(tt.x1, 1 - 16.0 / TW, 1.5 / TW) && Near(tt.y1, 1 - 16.0 / TW, 1.5 / TW) && Near(tt.fraction, 0.2, 0.03))) {
            faintOK = 0; printf("  (faint side %d: found %d, box %.3f %.3f %.3f %.3f, corner %.3f)\n", gFaintSide, tt.found, tt.x0, tt.y0, tt.x1, tt.y1, tt.fraction); }
    }
    gFaintSide = 0;
    Check(faintOK, "  ... with one band faint, on any side (the art runs through it: Notes' yellow top): the same box and corner");
    Themed(16, 16, 16, 16, 0.22, 0, 0, 1, 1); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
    Check(tt.found && Near(tt.x0, 16.0 / TW, 1.5 / TW) && Near(tt.fraction, 0.22, 0.03), "a pre-shaped tile on a clear canvas: the clear band is a band too");
    Themed(16, 16, 16, 16, 0.2, 0, 0, 0, 0); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
    Check(!tt.found, "the same art full-bleed (an app's own icon): no tile, drawn whole");
    Themed(12, 16, 28, 16, 0.2, 0.3, 0.3, 0, 1); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
    Check(!tt.found, "bands of different widths (12 and 28 px): not a painted frame");
    Disc(0.05, 0.98, 0, 0.45); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
    Check(!tt.found, "a disc on a plain square (Apple's Clock face): a circle is no tile");
    Disc(0.75, 0.30, 0.40, 0.46); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
    Check(!tt.found, "a ring near the edges (Apple's Settings gear): no tile");
    Disc(0.6, 0.6, 0, 0); tt = MSBDPaintedTileFind(gPic, TW, TW * 4);
    Check(!tt.found && !MSBDPaintedTileFind(NULL, TW, TW * 4).found && !MSBDPaintedTileFind(gPic, 32, 32 * 4).found, "a plain square, no picture, a tiny one: none");
    // ---- the picture before the mask against the Home Screen's: the same where an engine's own picture comes back, not for a live icon ----
    {
        enum { PN = 48 }; unsigned char u[PN * PN * 4], hm[PN * PN * 4];
        for (int i = 0; i < PN * PN; i++) { int x = i % PN, y = i / PN; unsigned char v = (unsigned char)(x * 5); u[i * 4] = v; u[i * 4 + 1] = 200; u[i * 4 + 2] = (unsigned char)(y * 5); u[i * 4 + 3] = 255;
            int corner = (x < 6 && y < 6) || (x > 41 && y < 6) || (x < 6 && y > 41) || (x > 41 && y > 41);   // (the Home Screen's picture: masked corners)
            for (int c = 0; c < 4; c++) hm[i * 4 + c] = corner ? 0 : u[i * 4 + c]; }
        Check(MSBDPictureDifference(u, hm, PN) < 0.01, "the theme's picture before its mask and the Home Screen's (masked) one: the same");
        for (int i = 0; i < PN * PN; i++) if (hm[i * 4 + 3]) for (int c = 0; c < 3; c++) hm[i * 4 + c] = (unsigned char)(255 - u[i * 4 + c]);
        Check(MSBDPictureDifference(u, hm, PN) >= MSBD_DESKTOP_PICTURE_SAME, "a live icon's (Apple's Clock against the theme's face): not the same, the Home Screen's is used");
        for (int i = 0; i < PN * PN; i++) hm[i * 4 + 3] = 0;
        Check(MSBDPictureDifference(u, hm, PN) >= 1.0 && MSBDPictureDifference(NULL, hm, PN) >= 1.0, "nothing opaque to compare, or no picture: not the same");
    }
    // ---- the part of the tile our square may show: all of it once as round as the tile, less as it gets squarer, never outside the tile's shape ----
    int whole = 1, rising = 1; double prevW = 0;
    for (int k = 0; k <= 50; k++) {
        double r = k * 0.01, wdw = MSBDTileWindow(0.2, r);
        if (r >= 0.2 && !Near(wdw, 1, 1e-9)) whole = 0;
        if (wdw + 1e-9 < prevW || wdw > 1 + 1e-12) rising = 0;
        prevW = wdw;
    }
    Check(whole && rising, "the tile's corner (0.2) or rounder: the whole tile; squarer: a little less at each step, never more than all of it");
    double w0 = MSBDTileWindow(0.2, 0);
    Check(w0 > 0.85 && w0 < 0.93, "  ... a square shows the middle 0.85 to 0.93 of a tile whose corner is 0.2");
    int inside = 1;
    for (int k = 0; k <= 4; k++) {   // (raster: the square's shape, that much of the tile, against the tile's own shape)
        enum { RN = 240 }; unsigned char tl[RN * RN], mk[RN * RN];
        double r = k * 0.05, ws = RN * MSBDTileWindow(0.2, r), o = (RN - ws) / 2.0;
        Continuous(NULL, 0.2, RN, tl);
        memset(mk, 0, sizeof mk);
        CGContextRef c = CGBitmapContextCreate(mk, RN, RN, 8, RN, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
        CGContextTranslateCTM(c, o, o); CGPathRef p = MSBDDesktopCornerPathCreate(ws, r); CGContextAddPath(c, p); CGContextFillPath(c); CGPathRelease(p); CGContextRelease(c);
        int out = 0; for (int i = 0; i < RN * RN; i++) if (mk[i] > 160 && tl[i] < 96) out++;
        if (out > 0) { inside = 0; printf("  (corner %.2f: %d pixels of the square outside the tile)\n", r, out); }
    }
    Check(inside, "  ... and that part stays inside the tile's shape at every corner (240 px raster)");
    printf("%d checks, %d failed\n", checks, fails);
  }
  return fails ? 1 : 0;
}
