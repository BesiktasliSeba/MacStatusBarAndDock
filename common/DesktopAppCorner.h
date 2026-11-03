// DesktopAppCorner.h -- the corners of the desktop's app icons (1.7.9 item 4, KT 2 Nov): Settings > Desktop > App Icon Corner Radius,
// desktopAppIconCorner in com.besiktasliseba.macstatusbar, a fraction of the icon's side (0 a square, 0.5 a circle), so Icon Size keeps the look.
// Only the desktop's app icons (its .app items, which open the installed app: 1.7.6) take it; folders, files, Finder's windows and the Home
// Screen keep theirs.
// Never set = the shape the Home Screen's app icons have now: an icon theme engine's mask when one shapes them (SnowBoard's corner radius,
// FrostBoard's icon shape on 18), else iPadOS's own -- and the desktop follows it as it changes. Once the slider is moved the value is the user's
// own: a later change of the theme, its mask or the Home Screen's icons leaves it as it is (KT 2 Nov), until Match Home Screen Icons removes it
// (nothing stored: following again).
// SpringBoard publishes the Home Screen's shape it measured (notify state) so that Settings' slider starts there.
// Plain C: Settings (statusbar/macstatusbarprefs) and SpringBoard (statusbar/DesktopCorner.h) share it; tools/test-desktopcorner.sh.
#ifndef MSBD_DESKTOP_APP_CORNER_H
#define MSBD_DESKTOP_APP_CORNER_H
#include <math.h>
#include <stdlib.h>
#include <CoreGraphics/CoreGraphics.h>

#define MSBD_DESKTOP_CORNER_KEY "desktopAppIconCorner"
#define MSBD_DESKTOP_CORNER_MAX 0.5     // (a circle)
#define MSBD_DESKTOP_CORNER_STEP 0.01   // (1 % of the side: 0.6 to 1 pt at the usual sizes, one notification per step while the slider is dragged)
#define MSBD_DESKTOP_CORNER_IPADOS 0.225   // (iPadOS's own app icon corner for its side -- 13.5 of 60 pt: what the slider shows before SpringBoard said)
#define MSBD_DESKTOP_THEMECORNER_STATE "com.besiktasliseba.macstatusbar.desktop.themecorner"   // (notify state: the Home Screen's shape, below)

// A stored or dragged value as the corner it stands for: inside 0 to 0.5, on a 1 % step. -1 for no number at all (NaN, infinite).
static inline double MSBDDesktopCornerSnap(double v) {
    if (!isfinite(v)) return -1.0;
    double s = round(v / MSBD_DESKTOP_CORNER_STEP) * MSBD_DESKTOP_CORNER_STEP;
    return fmin(MSBD_DESKTOP_CORNER_MAX, fmax(0.0, s));
}
// The corner in force for the desktop's app icons: the stored one (snapped) once the slider was moved, else -1 -- the Home Screen's own shape (the
// app icon exactly as the Home Screen shows it, its theme included, as before 1.7.9).
static inline double MSBDDesktopCornerInForce(int stored, double storedValue) { return stored ? MSBDDesktopCornerSnap(storedValue) : -1.0; }
// The radius in points for an icon side: never beyond half the side.
static inline double MSBDDesktopCornerRadius(double fraction, double side) {
    if (!(side > 0.0) || !isfinite(fraction)) return 0.0;
    return fmin(MSBD_DESKTOP_CORNER_MAX, fmax(0.0, fraction)) * side;
}

// The Home Screen's shape as published (SpringBoard -> Settings): its corner as a fraction in ten-thousandths, plus one (0 = not known yet), and
// whether the shape is no rounded square at all (an icon theme's own shape: then the fraction is the nearest rounded square).
#define MSBD_DESKTOP_THEMECORNER_CUSTOM (1ULL << 32)
static inline unsigned long long MSBDDesktopThemeCornerState(double fraction, int custom) {
    if (!isfinite(fraction) || fraction < 0.0) return 0ULL;
    unsigned long long s = (unsigned long long)llround(fmin(MSBD_DESKTOP_CORNER_MAX, fraction) * 10000.0) + 1ULL;
    return s | (custom ? MSBD_DESKTOP_THEMECORNER_CUSTOM : 0ULL);
}
static inline double MSBDDesktopThemeCornerFromState(unsigned long long state, int *custom) {
    unsigned long long v = state & 0xFFFFFFFFULL;
    if (custom) *custom = (state & MSBD_DESKTOP_THEMECORNER_CUSTOM) != 0;
    if (!v || v > 5001ULL) { if (custom) *custom = 0; return -1.0; }
    return (double)(v - 1ULL) / 10000.0;
}
// What Settings' slider shows: the stored corner (snapped) once moved; else the Home Screen's as SpringBoard published it; else iPadOS's own.
static inline double MSBDDesktopCornerShown(int stored, double storedValue, unsigned long long themeState) {
    if (stored) { double s = MSBDDesktopCornerSnap(storedValue); if (s >= 0.0) return s; }
    double t = MSBDDesktopThemeCornerFromState(themeState, NULL);
    return t >= 0.0 ? t : MSBD_DESKTOP_CORNER_IPADOS;
}

// ---- the shape: one drawing for the desktop's corners and for reading a theme's ----------------------------------------------------------------
// A square with smoothed corners -- each corner a circular arc between two curves that ease into the edges (the corner smoothing of Figma's
// "squircle" construction), so the curve flows into the sides as iPadOS's app icons do. At 0.7 smoothing it is within 0.2 px of iPadOS's own
// corner (UIBezierPath's continuous rounded rectangle, measured at 240 px); where the smoothed corner no longer fits in half the side the smoothing
// gives way, so a corner of half the side is an exact circle. Every step of the slider rounds a little more, without a jump. Not UIBezierPath's
// rounded rectangle, which turns into a circle at once past a third of the side, nor Core Animation's continuous corner, which pinches at the
// sides' middles near a circle (both seen on 15.6.1, desk_cornerstrip): KT's SnowBoard corner lies there (0.39 of the side).
#define MSBD_DESKTOP_CORNER_SMOOTHING 0.7
// One corner: c the shape's corner, u the incoming side's direction (towards c), v the outgoing side's (away from c), r the radius, half the
// side the room each corner has. The curve starts on the incoming side and ends on the outgoing one, as far from c as the smoothing needs.
static inline void MSBDCornerAdd(CGMutablePathRef p, double cx, double cy, double ux, double uy, double vx, double vy, double r, double half, int first) {
    double xi = MSBD_DESKTOP_CORNER_SMOOTHING, ext = (1.0 + xi) * r;
    if (ext > half) { xi = fmax(0.0, half / r - 1.0); ext = half; }   // (no room for the smoothing: less of it -- none at half the side)
    double arc = 90.0 * (1.0 - xi), arcLen = sin(arc * M_PI / 360.0) * r * M_SQRT2;
    double alpha = (90.0 - arc) / 2.0, p34 = r * tan(alpha * M_PI / 360.0);
    double beta = 45.0 * xi, c = p34 * cos(beta * M_PI / 180.0), d = c * tan(beta * M_PI / 180.0);
    double b = (ext - arcLen - c - d) / 3.0, a = 2.0 * b;
    double sx = cx - ux * ext, sy = cy - uy * ext;   // (where the corner's curve starts: x along u, y along v from here)
#define MSBD_CORNER_PT(X, Y) CGPointMake(sx + ux * (X) + vx * (Y), sy + uy * (X) + vy * (Y))
    CGPoint s = MSBD_CORNER_PT(0, 0), c1 = MSBD_CORNER_PT(a, 0), c2 = MSBD_CORNER_PT(a + b, 0), e1 = MSBD_CORNER_PT(a + b + c, d);
    if (first) CGPathMoveToPoint(p, NULL, s.x, s.y); else CGPathAddLineToPoint(p, NULL, s.x, s.y);
    CGPathAddCurveToPoint(p, NULL, c1.x, c1.y, c2.x, c2.y, e1.x, e1.y);
    double ox = cx - ux * r + vx * r, oy = cy - uy * r + vy * r;   // (the arc's centre)
    CGPoint e2 = MSBD_CORNER_PT(a + b + c + arcLen, d + arcLen);
    if (arcLen > 1e-9) CGPathAddArc(p, NULL, ox, oy, r, atan2(e1.y - oy, e1.x - ox), atan2(e2.y - oy, e2.x - ox), ux * vy - uy * vx < 0);
    CGPoint k1 = MSBD_CORNER_PT(ext, d + arcLen + c), k2 = MSBD_CORNER_PT(ext, d + arcLen + b + c), e3 = MSBD_CORNER_PT(ext, ext);
    CGPathAddCurveToPoint(p, NULL, k1.x, k1.y, k2.x, k2.y, e3.x, e3.y);
#undef MSBD_CORNER_PT
}
// The shape in the square (0, 0, side, side) for a corner (a fraction of the side). The caller releases it.
static inline CGPathRef MSBDDesktopCornerPathCreate(double side, double fraction) {
    CGMutablePathRef p = CGPathCreateMutable();
    double r = MSBDDesktopCornerRadius(fraction, side), s = side;
    if (!(s > 0.0)) return p;
    if (r < 1e-6) { CGPathAddRect(p, NULL, CGRectMake(0, 0, s, s)); return p; }
    MSBDCornerAdd(p, s, 0, 1, 0, 0, 1, r, s / 2.0, 1);    // (round the square: the top side into the corner at (s, 0), down the next side...)
    MSBDCornerAdd(p, s, s, 0, 1, -1, 0, r, s / 2.0, 0);
    MSBDCornerAdd(p, 0, s, -1, 0, 0, -1, r, s / 2.0, 0);
    MSBDCornerAdd(p, 0, 0, 0, -1, 1, 0, r, s / 2.0, 0);
    CGPathCloseSubpath(p);
    return p;
}

// ---- the Home Screen's shape, read from a picture ----------------------------------------------------------------------------------------------
// An icon theme engine's mask is read from what it makes of an opaque square (SpringBoard's own app icon chain, statusbar/DesktopCorner.h): its
// alpha (n x n, one byte a pixel) against rounded squares drawn the way the desktop draws its own corners (the callback: same path, same
// rasteriser). The best corner is found coarse to fine; how far the best one still is from the picture is the mean distance of their outlines in
// pixels (the summed alpha difference over the outline's length). A picture that no rounded square matches within MSBD_DESKTOP_CORNER_CUSTOM_PX
// is a shape of the theme's own (a squircle of another kind, a star, a shape inset from the square's edges).
typedef void (*MSBDCornerDraw)(void *ctx, double fraction, int n, unsigned char *alpha);   // (fills an n x n alpha bitmap, 0 = transparent)
#define MSBD_DESKTOP_CORNER_CUSTOM_PX 0.75
static inline double MSBDCornerOutlineGap(const unsigned char *a, const unsigned char *b, int n) {
    if (!a || !b || n <= 0) return 1e9;
    unsigned long long sum = 0;
    for (long i = 0, all = (long)n * n; i < all; i++) sum += (unsigned long long)abs((int)a[i] - (int)b[i]);
    return (double)sum / 255.0 / (4.0 * n);
}
// The fraction (0 to 0.5) of the rounded square nearest the picture; *gap: its outline distance in pixels (see above). scratch: n x n bytes.
static inline double MSBDCornerFit(const unsigned char *alpha, int n, MSBDCornerDraw draw, void *ctx, unsigned char *scratch, double *gap) {
    double best = 0.0, bestGap = 1e9;
    if (gap) *gap = 1e9;
    if (!alpha || !draw || !scratch || n < 8) return -1.0;
    for (int i = 0; i <= 50; i++) {   // (coarse: every 1 %)
        double f = i * 0.01;
        draw(ctx, f, n, scratch);
        double g = MSBDCornerOutlineGap(alpha, scratch, n);
        if (g < bestGap) { bestGap = g; best = f; }
    }
    double lo = fmax(0.0, best - 0.01), hi = fmin(MSBD_DESKTOP_CORNER_MAX, best + 0.01);
    for (double f = lo; f <= hi + 1e-9; f += 0.0005) {   // (fine: every 0.05 % around it)
        draw(ctx, f, n, scratch);
        double g = MSBDCornerOutlineGap(alpha, scratch, n);
        if (g < bestGap) { bestGap = g; best = f; }
    }
    if (gap) *gap = bestGap;
    return best;
}
static inline int MSBDCornerIsCustom(double gap) { return !(gap <= MSBD_DESKTOP_CORNER_CUSTOM_PX); }
// Where no app icon of our own can be read (iPadOS 18: the icon theme path is off there, and an engine there shapes the pictures SpringBoard asks
// IconServices for -- FrostBoard: its Icon Shape --, not an icon of ours), the Home Screen's own app icons are read instead, each one's mask as
// above: the shape most of them show is the median reading. Within MSBD_DESKTOP_CORNER_OWN of SpringBoard's own corner and a rounded square, it
// is iPadOS's own mask (18.5 without an engine: 0.224, 0.02 px from our shape, where SpringBoard says 0.225) and no engine shapes the icons.
#define MSBD_DESKTOP_CORNER_OWN 0.01
typedef struct { double fraction, gap; } MSBDCornerReading;
static inline int MSBDCornerReadingCmp(const void *a, const void *b) {
    double x = ((const MSBDCornerReading *)a)->fraction, y = ((const MSBDCornerReading *)b)->fraction;
    return x < y ? -1 : x > y;
}
// The median of n readings (sorted in place: the middle one, the rounder of the two middle ones for an even count); fraction -1 for none.
static inline MSBDCornerReading MSBDCornerMedian(MSBDCornerReading *r, int n) {
    MSBDCornerReading none = { -1.0, 1e9 };
    if (!r || n <= 0) return none;
    qsort(r, (size_t)n, sizeof r[0], MSBDCornerReadingCmp);
    return r[n / 2];
}
static inline int MSBDCornerIsSpringBoards(MSBDCornerReading r, double springBoardCorner) {
    return r.fraction >= 0.0 && !MSBDCornerIsCustom(r.gap) && fabs(r.fraction - springBoardCorner) <= MSBD_DESKTOP_CORNER_OWN;
}

// ---- a theme picture's painted frame (KT 2 Nov: trim it) -----------------------------------------------------------------------------------------
// Some themes paint their icon as a rounded tile inside the square with a band around it that the engine's own mask cuts away (KT's iOSX on
// SnowBoard: a band of 16 of 256 px around a tile whose corner is about 0.23 of it; the art often runs on under the band, darker). Our corner
// over the whole picture showed that band: a square border when squarer, its edges inside the circle. The tile is found in the picture itself,
// by what makes a band a band -- one width all round -- not by the strongest edge (the art inside has stronger ones: Tips' bulb; the band's own
// edge can be faint, 3 of 255 at the top of Tips): on every side, at seven places along the middle fifth (the tile's straight edge), the colour
// steps within the outer 16 % of the side; the band's width is the depth where nearly all seven have a step standing out from its neighbours
// (six of seven, one pixel either way), the same on all four sides within 1.2 % of the side, between 1.5 and 14 %. One side may be faint where the
// art runs through the band unchanged (Notes' yellow top: two of seven), if what it shows is at the others' depth. The tile's corner: along each
// diagonal, the strongest step where a corner of 0.08 to 0.4 of the tile would cross it; the four must agree (a circle -- Apple's Clock face,
// Settings' gear -- is no tile: its corner reads 0.5). A full-bleed picture (an app's own icon) has no such band. The picture: w x w, four bytes a
// pixel (premultiplied: a transparent band counts too), any channel order.
typedef struct { int found; double x0, y0, x1, y1, fraction; } MSBDPaintedTile;   // (the tile's box in fractions of the side; its corner, of the tile)
static inline double MSBDTileStep(const unsigned char *px, int w, int stride, double x, double y, double dx, double dy, double nx, double ny, int i) {
    // the colour step between pixels i-1..i and i+1..i+2 along (dx, dy) from (x, y), each the mean of three pixels across the line (nx, ny)
    double a[4] = { 0, 0, 0, 0 }, b[4] = { 0, 0, 0, 0 };
    for (int k = -1; k <= 1; k++) for (int j = 0; j < 2; j++) {
        int ax = (int)lround(x + dx * (i - j) + nx * k), ay = (int)lround(y + dy * (i - j) + ny * k);
        int bx = (int)lround(x + dx * (i + 1 + j) + nx * k), by = (int)lround(y + dy * (i + 1 + j) + ny * k);
        if (ax < 0 || ay < 0 || bx < 0 || by < 0 || ax >= w || ay >= w || bx >= w || by >= w) return 0.0;
        for (int c = 0; c < 4; c++) { a[c] += px[(long)ay * stride + ax * 4 + c]; b[c] += px[(long)by * stride + bx * 4 + c]; }
    }
    double s = 0; for (int c = 0; c < 4; c++) { double d = (a[c] - b[c]) / 6.0; s += d * d; }
    return sqrt(s);
}
// A step at i that stands out: at least 1.5, and 1 more than the steps two and three pixels away on both sides (an edge, not a gradient).
static inline int MSBDTilePeak(const double *s, int n, int i) {
    if (i < 3 || i + 3 >= n || s[i] < 1.5) return 0;
    double around = fmax(fmax(s[i - 3], s[i - 2]), fmax(s[i + 2], s[i + 3]));
    return s[i] >= around + 1.0;
}
static inline int MSBDTileCmp(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return x < y ? -1 : x > y; }
#define MSBD_TILE_DEPTH_MAX 200
static inline MSBDPaintedTile MSBDPaintedTileFind(const unsigned char *px, int w, int stride) {
    MSBDPaintedTile t = { 0, 0, 0, 1, 1, 0 };
    int depth = (int)(w * 0.16);
    if (!px || w < 64 || stride < w * 4 || depth + 4 > MSBD_TILE_DEPTH_MAX) return t;
    int lo = (int)ceil(w * 0.015), hi = (int)floor(w * 0.14);
    double inset[4];   // (top, right, bottom, left: the band's width in pixels)
    double steps[4][7][MSBD_TILE_DEPTH_MAX];
    int faint = -1;
    for (int side = 0; side < 4; side++) {
        double (*s)[MSBD_TILE_DEPTH_MAX] = steps[side];
        for (int k = 0; k < 7; k++) {
            double along = w * (0.5 + (k - 3) * 0.1 / 3.0);   // (seven places in the middle fifth of the side)
            for (int i = 0; i < depth; i++) switch (side) {
                case 0: s[k][i] = i ? MSBDTileStep(px, w, stride, along, 0, 0, 1, 1, 0, i) : 0; break;
                case 1: s[k][i] = i ? MSBDTileStep(px, w, stride, w - 1, along, -1, 0, 0, 1, i) : 0; break;
                case 2: s[k][i] = i ? MSBDTileStep(px, w, stride, along, w - 1, 0, -1, 1, 0, i) : 0; break;
                default: s[k][i] = i ? MSBDTileStep(px, w, stride, 0, along, 1, 0, 0, 1, i) : 0; break;
            }
        }
        int bestD = -1, bestN = 0;
        for (int d = lo - 1; d <= hi - 1; d++) {   // (a step between pixels d and d + 1: a band d + 1 wide)
            int n = 0;
            for (int k = 0; k < 7; k++) if (MSBDTilePeak(s[k], depth, d - 1) || MSBDTilePeak(s[k], depth, d) || MSBDTilePeak(s[k], depth, d + 1)) n++;
            if (n > bestN) { bestN = n; bestD = d; }
        }
        if (bestN < 6) {   // (no band all along this side: at most one such side, checked against the others below)
            if (faint >= 0) return t;
            faint = side; inset[side] = 0;
            continue;
        }
        double at[7]; int m = 0;   // (each place's own step near it: the band's width to the pixel)
        for (int k = 0; k < 7; k++) {
            int j = -1; double v = 0;
            for (int q = bestD - 1; q <= bestD + 1; q++) if (MSBDTilePeak(s[k], depth, q) && s[k][q] > v) { v = s[k][q]; j = q; }
            if (j >= 0) at[m++] = j + 1.0;
        }
        qsort(at, m, sizeof at[0], MSBDTileCmp);
        inset[side] = at[m / 2];
    }
    if (faint >= 0) {   // (the faint side: two of its seven places at the others' depth, one pixel either way -- then the band is that wide there too)
        double o[3]; int m = 0;
        for (int side = 0; side < 4; side++) if (side != faint) o[m++] = inset[side];
        qsort(o, 3, sizeof o[0], MSBDTileCmp);
        int d = (int)lround(o[1]) - 1, n = 0;
        for (int k = 0; k < 7; k++) for (int q = d - 1; q <= d + 1; q++) if (MSBDTilePeak(steps[faint][k], depth, q)) { n++; break; }
        if (n < 2) return t;
        inset[faint] = o[1];
    }
    double minI = fmin(fmin(inset[0], inset[1]), fmin(inset[2], inset[3])), maxI = fmax(fmax(inset[0], inset[1]), fmax(inset[2], inset[3]));
    if (maxI - minI > w * 0.012) return t;   // (a band of one width all round)
    double x0 = inset[3], y0 = inset[0], x1 = w - inset[1], y1 = w - inset[2], side = ((x1 - x0) + (y1 - y0)) / 2.0, f[4];
    int nf = 0;
    for (int c = 0; c < 4; c++) {   // (the corners: where a tile's corner of 0.08 to 0.4 would cross each diagonal, the strongest step -- not
                                    //  the two by a faint side: the art runs through there too and its own edges are stronger)
        if (faint >= 0 && (c == faint || c == (faint + 1) % 4)) continue;   // (corner c lies between sides c and c - 1: top-left is top and left)
        double sx = (c == 1 || c == 2) ? w - 1 : 0, sy = (c >= 2) ? w - 1 : 0, dx = sx > 0 ? -1 : 1, dy = sy > 0 ? -1 : 1;
        double band = ((dx > 0 ? x0 : w - x1) + (dy > 0 ? y0 : w - y1)) / 2.0, k = side * (1.0 - M_SQRT1_2);
        int from = (int)floor(band + 0.08 * k) - 2, to = (int)ceil(band + 0.40 * k) + 2;
        double best = 0; int at = -1;
        for (int i = from > 1 ? from : 1; i <= to && i + 2 < w; i++) { double v = MSBDTileStep(px, w, stride, sx, sy, dx, dy, dx, -dy, i); if (v > best) { best = v; at = i; } }
        if (at < 0 || best < 1.5) return t;
        f[nf++] = (at + 1.0 - band) / k;   // (our shape's corner crosses its diagonal r (1 - 1/sqrt 2) in from the box's corner)
    }
    qsort(f, nf, sizeof f[0], MSBDTileCmp);
    double fc = nf == 4 ? (f[1] + f[2]) / 2.0 : (f[0] + f[1]) / 2.0;
    if (f[nf - 1] - f[0] > 0.06 || fc < 0.08 || fc > 0.40) return t;   // (the corners disagree, or the tile is a square or a circle)
    t.found = 1; t.x0 = x0 / w; t.y0 = y0 / w; t.x1 = x1 / w; t.y1 = y1 / w; t.fraction = fc;
    return t;
}
// Does the picture before the mask show what the Home Screen shows? SnowBoard themes the live icons (Clock, Calendar) apart from their app icon's
// own pictures, so SpringBoard's unmasked one is Apple's there (KT's M1: Apple's black Clock, 64 px, where the Home Screen shows the theme's light
// face). Both n x n, four bytes a pixel (premultiplied, the same channel order); where the Home Screen's is opaque, the mean colour difference
// (0 to 1). Under MSBD_DESKTOP_PICTURE_SAME: the same picture.
#define MSBD_DESKTOP_PICTURE_SAME 0.12
static inline double MSBDPictureDifference(const unsigned char *unmasked, const unsigned char *home, int n) {
    if (!unmasked || !home || n <= 0) return 1.0;
    double sum = 0; long count = 0;
    for (long i = 0, all = (long)n * n; i < all; i++) {
        if (home[i * 4 + 3] < 250) continue;
        for (int c = 0; c < 3; c++) sum += fabs((double)unmasked[i * 4 + c] - (double)home[i * 4 + c]) / 255.0;
        count++;
    }
    return count ? sum / (3.0 * count) : 1.0;
}
// The shape's extent from its centre in n directions from 0 to 45 degrees (it is the same in the other seven eighths), for a side of 1.
typedef struct { double h[46]; } MSBDCornerSupport;
typedef struct { CGPoint *p; int n, cap; } MSBDPathPoints;
static inline void MSBDPathPointsAdd(MSBDPathPoints *pp, CGPoint q) { if (pp->n < pp->cap) pp->p[pp->n++] = q; }
static inline void MSBDPathPointsApply(void *info, const CGPathElement *e) {
    MSBDPathPoints *pp = (MSBDPathPoints *)info;
    CGPoint last = pp->n ? pp->p[pp->n - 1] : CGPointZero;
    switch (e->type) {
        case kCGPathElementMoveToPoint: case kCGPathElementAddLineToPoint: MSBDPathPointsAdd(pp, e->points[0]); break;
        case kCGPathElementAddQuadCurveToPoint:
            for (int i = 1; i <= 24; i++) { double t = i / 24.0, u = 1 - t;
                MSBDPathPointsAdd(pp, CGPointMake(u * u * last.x + 2 * u * t * e->points[0].x + t * t * e->points[1].x, u * u * last.y + 2 * u * t * e->points[0].y + t * t * e->points[1].y)); }
            break;
        case kCGPathElementAddCurveToPoint:
            for (int i = 1; i <= 24; i++) { double t = i / 24.0, u = 1 - t;
                MSBDPathPointsAdd(pp, CGPointMake(u * u * u * last.x + 3 * u * u * t * e->points[0].x + 3 * u * t * t * e->points[1].x + t * t * t * e->points[2].x,
                                                  u * u * u * last.y + 3 * u * u * t * e->points[0].y + 3 * u * t * t * e->points[1].y + t * t * t * e->points[2].y)); }
            break;
        default: break;
    }
}
static inline MSBDCornerSupport MSBDCornerSupportOf(double fraction) {
    MSBDCornerSupport s;
    CGPoint pts[1200];
    MSBDPathPoints pp = { pts, 0, 1200 };
    CGPathRef path = MSBDDesktopCornerPathCreate(1.0, fraction);
    CGPathApply(path, &pp, MSBDPathPointsApply);
    CGPathRelease(path);
    for (int k = 0; k <= 45; k++) {
        double a = k * M_PI / 180.0, cx = cos(a), cy = sin(a), best = 0;
        for (int i = 0; i < pp.n; i++) best = fmax(best, (pts[i].x - 0.5) * cx + (pts[i].y - 0.5) * cy);
        s.h[k] = best;
    }
    return s;
}
// How much of the tile our square may show at a corner and still stay inside the tile's own shape (a fraction of the tile's side, 1 at most):
// two convex shapes with one centre, one inside the other in every direction. Equal to or rounder than the tile's corner: the whole tile.
static inline double MSBDTileWindow(double tileFraction, double corner) {
    MSBDCornerSupport a = MSBDCornerSupportOf(corner), b = MSBDCornerSupportOf(tileFraction);
    double s = 1.0;
    for (int k = 0; k <= 45; k++) if (a.h[k] > 1e-9) s = fmin(s, b.h[k] / a.h[k]);
    return s;
}
#endif
