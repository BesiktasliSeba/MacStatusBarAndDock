// DesktopPlace.h -- where the desktop's icons go (Desktop.h), plain C on CoreGraphics so the Mac test (tools/test-desktopplace.m) runs this very
// code. One layout pass is one DMPlacer, made once from the page's occupied rects (app icons, widgets, the page dots); every icon it places is
// taken into it at once.
//  - Free spots are known, not searched for: every 4 pt of the area holds whether an icon centred there would be free (inside the area, over
//    nothing taken), marked once per taken rect. "Is there room at all" is a counter.
//  - New icons: the grid a Mac fills (from the top right, down a column, then the column to its left), handed out by a cursor that never goes
//    back (a spot taken stays taken within a pass); when the grid is full, the free spot nearest the top right (a gap between app icons).
//  - An icon with a place (saved, dropped): exactly there if free, else the nearest free spot to it.
//  - No room left: nothing is searched any more; every further icon is stacked on the last free spot handed out in the pass -- a pile on free
//    ground, never under an app icon: its top icon can be pressed or dragged away (the next one shows), all of them selected with the rectangle
//    or Command-A. With no free spot on the whole page the pile is on the grid spot the Home Screen's own icons cover least. Icons in the pile
//    keep their place (a new one gets none): they come out as soon as there is room.
// (Before: an icon that found no room searched every 8 pt ring up to the area's longer side against every rect -- 200 files on a full page took
//  13M rect tests, over 1 s on SpringBoard's main thread, at every layout -- and was then left under the app icons, out of reach.)
#ifndef MSBD_DESKTOP_PLACE_H
#define MSBD_DESKTOP_PLACE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define kDMPlaceStep 4.0
typedef struct {
    CGRect area; CGFloat cw, ch;                  // the free area, an icon's cell
    CGRect *rects; int nRects, capRects;          // everything taken so far
    CGFloat fx0, fy0; int fcols, frows;           // the 4 pt raster of icon centres: free[] 1 where an icon there would be free
    unsigned char *free; long freeLeft;
    CGFloat gx0, gy0, gdx, gdy; int gcols, grows; // the grid: x = gx0 - i * gdx (columns from the right), y = gy0 + j * gdy
    unsigned char *cellTaken; int cursor;
    long *corner, cornerN, cornerAt;              // (the raster by distance from the top right spot, for new icons once the grid is full)
    CGPoint last; int hasLast;
    CGPoint pile; int hasPile;
    long tests;                                   // (rect tests and raster cells looked at, for the Mac test)
    int mirror;                                   // (right-to-left: everything mirrored in the area, DMPlacerInitDir)
} DMPlacer;
// Right-to-left languages (1.3.3): a Mac in Hebrew or Arabic fills its desktop from the top LEFT. The placer itself works as always; the public
// calls turn x around the area's middle on the way in and back on the way out, so the grid, the nearest-spot search and the pile are mirrored.
static inline CGFloat DMPlacerFlipX(const DMPlacer *p, CGFloat x) { return CGRectGetMinX(p->area) + CGRectGetMaxX(p->area) - x; }
static inline CGRect DMPlacerFlipRect(const DMPlacer *p, CGRect r) { r = CGRectStandardize(r); r.origin.x = CGRectGetMinX(p->area) + CGRectGetMaxX(p->area) - CGRectGetMaxX(r); return r; }
static inline CGPoint DMPlacerFlipPoint(const DMPlacer *p, CGPoint c) { return p->mirror ? CGPointMake(DMPlacerFlipX(p, c.x), c.y) : c; }

static CGRect DMPlacerCellRect(const DMPlacer *p, CGPoint c) { return CGRectMake(c.x - p->cw / 2.0, c.y - p->ch / 2.0, p->cw, p->ch); }
static CGPoint DMPlacerCell(const DMPlacer *p, int idx) { int i = idx / p->grows, j = idx % p->grows; return CGPointMake(p->gx0 - i * p->gdx, p->gy0 + j * p->gdy); }
static CGPoint DMPlacerRasterPoint(const DMPlacer *p, long k) { return CGPointMake(p->fx0 + (CGFloat)(k % p->fcols) * kDMPlaceStep, p->fy0 + (CGFloat)(k / p->fcols) * kDMPlaceStep); }
// (an icon centred at c over r: their open interiors meet -- CGRectIntersectsRect's own rule, edges touching don't count)
static inline int DMPlacerOver(const DMPlacer *p, CGFloat cx, CGFloat cy, CGRect r) {
    return cx - p->cw / 2.0 < CGRectGetMaxX(r) && cx + p->cw / 2.0 > CGRectGetMinX(r) && cy - p->ch / 2.0 < CGRectGetMaxY(r) && cy + p->ch / 2.0 > CGRectGetMinY(r);
}
// Something covers r now: kept, and the raster centres and grid spots it touches are no longer free. (Raw: in the placer's own coordinates.)
static void DMPlacerTakeRaw(DMPlacer *p, CGRect r) {
    r = CGRectStandardize(r);
    if (CGRectIsNull(r) || r.size.width <= 0 || r.size.height <= 0 || !CGRectIntersectsRect(r, p->area)) return;   // (outside the area: no spot there)
    if (p->nRects == p->capRects) { p->capRects = p->capRects ? p->capRects * 2 : 64; p->rects = realloc(p->rects, sizeof(CGRect) * (size_t)p->capRects); }
    p->rects[p->nRects++] = r;
    int c0 = MAX(0, (int)floor((CGRectGetMinX(r) - p->cw / 2.0 - p->fx0) / kDMPlaceStep)), c1 = MIN(p->fcols - 1, (int)ceil((CGRectGetMaxX(r) + p->cw / 2.0 - p->fx0) / kDMPlaceStep));
    int r0 = MAX(0, (int)floor((CGRectGetMinY(r) - p->ch / 2.0 - p->fy0) / kDMPlaceStep)), r1 = MIN(p->frows - 1, (int)ceil((CGRectGetMaxY(r) + p->ch / 2.0 - p->fy0) / kDMPlaceStep));
    for (int y = r0; y <= r1; y++) for (int x = c0; x <= c1; x++) {
        long k = (long)y * p->fcols + x;
        if (p->free[k] && DMPlacerOver(p, p->fx0 + x * kDMPlaceStep, p->fy0 + y * kDMPlaceStep, r)) { p->free[k] = 0; p->freeLeft--; }
    }
    int i0 = MAX(0, (int)floor((p->gx0 - p->cw / 2.0 - CGRectGetMaxX(r)) / p->gdx)), i1 = MIN(p->gcols - 1, (int)ceil((p->gx0 + p->cw / 2.0 - CGRectGetMinX(r)) / p->gdx));
    int j0 = MAX(0, (int)floor((CGRectGetMinY(r) - p->ch / 2.0 - p->gy0) / p->gdy)), j1 = MIN(p->grows - 1, (int)ceil((CGRectGetMaxY(r) + p->ch / 2.0 - p->gy0) / p->gdy));
    for (int i = i0; i <= i1; i++) for (int j = j0; j <= j1; j++)
        if (DMPlacerOver(p, p->gx0 - i * p->gdx, p->gy0 + j * p->gdy, r)) p->cellTaken[i * p->grows + j] = 1;
}
static void DMPlacerTake(DMPlacer *p, CGRect r) { DMPlacerTakeRaw(p, p->mirror && !CGRectIsNull(r) ? DMPlacerFlipRect(p, r) : r); }
static void DMPlacerInitDir(DMPlacer *p, CGRect area, CGFloat cw, CGFloat ch, const CGRect *occupied, int n, int mirror) {
    memset(p, 0, sizeof *p);
    p->mirror = mirror;
    p->area = area; p->cw = cw; p->ch = ch;
    // the raster: every centre whose icon lies inside the area (exactly as CGRectContainsRect sees it)
    p->fx0 = CGRectGetMinX(area) + cw / 2.0; p->fy0 = CGRectGetMinY(area) + ch / 2.0;
    p->fcols = area.size.width >= cw ? MIN(4096, (int)floor((area.size.width - cw) / kDMPlaceStep) + 1) : 0;
    p->frows = area.size.height >= ch ? MIN(4096, (int)floor((area.size.height - ch) / kDMPlaceStep) + 1) : 0;
    long nr = (long)p->fcols * p->frows;
    p->free = malloc((size_t)MAX(1, nr)); memset(p->free, 1, (size_t)MAX(1, nr)); p->freeLeft = nr;
    for (long k = 0; k < nr; k++) {   // (inside by construction; only the last column and row are checked, against rounding)
        if (k % p->fcols != p->fcols - 1 && k / p->fcols != p->frows - 1) continue;
        if (!CGRectContainsRect(area, DMPlacerCellRect(p, DMPlacerRasterPoint(p, k)))) { p->free[k] = 0; p->freeLeft--; }
    }
    // the grid a Mac fills (the spacing it had before); spots sticking out of the area by the half point allowed here are never free
    p->gdx = cw + 8.0; p->gdy = ch + 6.0;
    p->gx0 = CGRectGetMaxX(area) - cw / 2.0; p->gy0 = CGRectGetMinY(area) + ch / 2.0;
    for (CGFloat x = p->gx0; x >= CGRectGetMinX(area) + cw / 2.0 - 0.5 && p->gcols < 512; x -= p->gdx) p->gcols++;
    for (CGFloat y = p->gy0; y <= CGRectGetMaxY(area) - ch / 2.0 + 0.5 && p->grows < 512; y += p->gdy) p->grows++;
    p->cellTaken = calloc((size_t)MAX(1, p->gcols * p->grows), 1);
    for (int k = 0; k < p->gcols * p->grows; k++) if (!CGRectContainsRect(area, DMPlacerCellRect(p, DMPlacerCell(p, k)))) p->cellTaken[k] = 1;
    for (int k = 0; k < n; k++) DMPlacerTake(p, occupied[k]);
}
__attribute__((unused)) static void DMPlacerInit(DMPlacer *p, CGRect area, CGFloat cw, CGFloat ch, const CGRect *occupied, int n) { DMPlacerInitDir(p, area, cw, ch, occupied, n, 0); }
static void DMPlacerFree(DMPlacer *p) { free(p->rects); free(p->free); free(p->cellTaken); free(p->corner); memset(p, 0, sizeof *p); }
// Is an icon centred at c free: inside the area, over nothing taken?
static int DMPlacerFreeAt(DMPlacer *p, CGPoint c) {
    if (!CGRectContainsRect(p->area, DMPlacerCellRect(p, c))) return 0;
    for (int k = 0; k < p->nRects; k++) { p->tests++; if (DMPlacerOver(p, c.x, c.y, p->rects[k])) return 0; }
    return 1;
}
// The free centre nearest to c on the raster (squares of growing size around it, until no nearer one can be left): 0 when there is none.
static int DMPlacerNearest(DMPlacer *p, CGPoint c, CGPoint *out) {
    if (p->freeLeft <= 0) return 0;
    int cx = (int)lround((c.x - p->fx0) / kDMPlaceStep), cy = (int)lround((c.y - p->fy0) / kDMPlaceStep);
    cx = MAX(0, MIN(p->fcols - 1, cx)); cy = MAX(0, MIN(p->frows - 1, cy));
    CGPoint mid = DMPlacerRasterPoint(p, (long)cy * p->fcols + cx);
    CGFloat off = hypot(mid.x - c.x, mid.y - c.y);   // (c can lie outside the raster: a ring's points are at least ring * 4 pt - off away)
    long best = -1; CGFloat bestD = CGFLOAT_MAX;
    int maxRing = MAX(MAX(cx, p->fcols - 1 - cx), MAX(cy, p->frows - 1 - cy));
    for (int ring = 0; ring <= maxRing; ring++) {
        if (best >= 0 && ring * kDMPlaceStep - off > bestD) break;   // (everything farther out is farther than the one found)
        for (int y = cy - ring; y <= cy + ring; y++) {
            if (y < 0 || y >= p->frows) continue;
            int edge = y == cy - ring || y == cy + ring;
            for (int x = cx - ring; x <= cx + ring; x += edge ? 1 : 2 * ring) {
                if (x >= 0 && x < p->fcols) {
                    long k = (long)y * p->fcols + x; p->tests++;
                    if (p->free[k]) { CGPoint q = DMPlacerRasterPoint(p, k); CGFloat d = hypot(q.x - c.x, q.y - c.y); if (d < bestD) { bestD = d; best = k; } }
                }
            }
        }
    }
    if (best < 0) return 0;
    *out = DMPlacerRasterPoint(p, best);
    return 1;
}
// The pile's spot (no room): the last free spot handed out; else the grid spot least covered by what is there.
static CGPoint DMPlacerPile(DMPlacer *p) {
    if (p->hasLast) return p->last;
    if (p->hasPile) return p->pile;
    CGFloat least = CGFLOAT_MAX; CGPoint at = CGPointMake(CGRectGetMidX(p->area), CGRectGetMidY(p->area));
    for (int k = 0; k < p->gcols * p->grows; k++) {
        CGPoint q = DMPlacerCell(p, k); CGRect r = DMPlacerCellRect(p, q);
        if (!CGRectContainsRect(CGRectInset(p->area, -0.5, -0.5), r)) continue;
        CGFloat cover = 0;
        for (int m = 0; m < p->nRects; m++) { CGRect x = CGRectIntersection(p->rects[m], r); if (!CGRectIsNull(x)) cover += x.size.width * x.size.height; }
        if (cover < least) { least = cover; at = q; }
    }
    p->pile = at; p->hasPile = 1;
    return at;
}
static CGPoint DMPlacerPut(DMPlacer *p, CGPoint c) { DMPlacerTakeRaw(p, DMPlacerCellRect(p, c)); p->last = c; p->hasLast = 1; return c; }
// An icon wanted at c (its saved place, a drop): there if free, else the nearest free spot. *fits = 0: no room, the pile's spot (not taken).
static CGPoint DMPlacerPlaceNearRaw(DMPlacer *p, CGPoint c, int *fits) {
    if (fits) *fits = 1;
    CGRect a = p->area;
    CGPoint cc = CGPointMake(MAX(CGRectGetMinX(a) + p->cw / 2.0, MIN(c.x, CGRectGetMaxX(a) - p->cw / 2.0)), MAX(CGRectGetMinY(a) + p->ch / 2.0, MIN(c.y, CGRectGetMaxY(a) - p->ch / 2.0)));
    if (DMPlacerFreeAt(p, cc)) return DMPlacerPut(p, cc);
    CGPoint q;
    if (DMPlacerNearest(p, c, &q)) return DMPlacerPut(p, q);
    if (fits) *fits = 0;
    return DMPlacerPile(p);
}
static CGPoint DMPlacerPlaceNear(DMPlacer *p, CGPoint c, int *fits) { return DMPlacerFlipPoint(p, DMPlacerPlaceNearRaw(p, DMPlacerFlipPoint(p, c), fits)); }
// A new icon: the next free grid spot, as a Mac fills its desktop; then the free spot nearest the top right (top left, mirrored). *fits = 0: no
// room (the pile's spot).
static CGPoint DMPlacerPlaceNextRaw(DMPlacer *p, int *fits) {
    while (p->cursor < p->gcols * p->grows && p->cellTaken[p->cursor]) p->cursor++;
    if (p->cursor < p->gcols * p->grows) { if (fits) *fits = 1; return DMPlacerPut(p, DMPlacerCell(p, p->cursor)); }
    // (the grid is full: the gaps, nearest the top right first -- the raster sorted once by that distance, in 4 pt steps, and a cursor that never
    //  goes back; within a step the nearest one)
    CGPoint tr = CGPointMake(p->gx0, p->gy0);
    if (p->freeLeft > 0 && !p->corner) {
        long nr = (long)p->fcols * p->frows; int nb = (int)(hypot(p->area.size.width, p->area.size.height) / kDMPlaceStep) + 2;
        long *count = calloc((size_t)nb + 1, sizeof(long)); p->corner = malloc(sizeof(long) * (size_t)MAX(1, nr)); p->cornerN = nr;
        for (long k = 0; k < nr; k++) { CGPoint q = DMPlacerRasterPoint(p, k); count[MIN(nb - 1, (int)(hypot(q.x - tr.x, q.y - tr.y) / kDMPlaceStep)) + 1]++; }
        for (int b = 1; b <= nb; b++) count[b] += count[b - 1];
        for (long k = 0; k < nr; k++) { CGPoint q = DMPlacerRasterPoint(p, k); p->corner[count[MIN(nb - 1, (int)(hypot(q.x - tr.x, q.y - tr.y) / kDMPlaceStep))]++] = k; }
        free(count);
    }
    while (p->freeLeft > 0 && p->cornerAt < p->cornerN && !p->free[p->corner[p->cornerAt]]) { p->cornerAt++; p->tests++; }
    if (p->freeLeft > 0 && p->cornerAt < p->cornerN) {
        long best = p->corner[p->cornerAt]; CGPoint q = DMPlacerRasterPoint(p, best);
        CGFloat bestD = hypot(q.x - tr.x, q.y - tr.y); int step = (int)(bestD / kDMPlaceStep);
        for (long i = p->cornerAt + 1; i < p->cornerN; i++) {
            CGPoint r = DMPlacerRasterPoint(p, p->corner[i]); CGFloat d = hypot(r.x - tr.x, r.y - tr.y);
            if ((int)(d / kDMPlaceStep) != step) break;
            if (p->free[p->corner[i]] && d < bestD) { bestD = d; best = p->corner[i]; q = r; }
        }
        if (fits) *fits = 1;
        return DMPlacerPut(p, q);
    }
    if (fits) *fits = 0;
    return DMPlacerPile(p);
}
static CGPoint DMPlacerPlaceNext(DMPlacer *p, int *fits) { return DMPlacerFlipPoint(p, DMPlacerPlaceNextRaw(p, fits)); }
#endif
