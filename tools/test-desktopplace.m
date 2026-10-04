// Mac test of the desktop's icon placement (statusbar/DesktopPlace.h, the code Desktop.h runs) on both iPad sizes in both orientations, with a
// modelled Home Screen page 1 (an app icon grid, the page dots, the menu bar, the Dock): where icons go, that they never leave the free area or
// cover an app icon, that turning keeps them inside, that the old search's answers are kept while there is room, and what a layout pass costs
// with a full page 1 and 40 or 200 files (it must stay a few ms). Run by test-desktopplace.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/DesktopPlace.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static CGFloat cw, ch;

// ---- the search before (Desktop.h up to 1.3 b4cf10b), for comparison while there is room ----
static long oldTests;
static BOOL oldFree(CGRect r, NSArray<NSValue *> *taken, CGRect area) {
    oldTests++;
    if (!CGRectContainsRect(area, r)) return NO;
    for (NSValue *t in taken) if (CGRectIntersectsRect(t.rectValue, r)) return NO;
    return YES;
}
static CGPoint oldNear(CGPoint c, NSArray<NSValue *> *taken, CGRect area, BOOL *found) {
    CGPoint cc = CGPointMake(MAX(CGRectGetMinX(area) + cw / 2.0, MIN(c.x, CGRectGetMaxX(area) - cw / 2.0)), MAX(CGRectGetMinY(area) + ch / 2.0, MIN(c.y, CGRectGetMaxY(area) - ch / 2.0)));
    *found = YES;
    if (oldFree(CGRectMake(cc.x - cw / 2.0, cc.y - ch / 2.0, cw, ch), taken, area)) return cc;
    CGFloat maxR = MAX(area.size.width, area.size.height);
    for (CGFloat rad = 8.0; rad <= maxR; rad += 8.0) {
        CGPoint best = CGPointZero; CGFloat bestD = CGFLOAT_MAX;
        NSInteger steps = MAX(8, (NSInteger)(rad * 2.0 * M_PI / 8.0));
        for (NSInteger i = 0; i < steps; i++) {
            CGFloat a = 2.0 * M_PI * i / steps;
            CGPoint p = CGPointMake(cc.x + rad * cos(a), cc.y + rad * sin(a));
            CGFloat dd = hypot(p.x - c.x, p.y - c.y);
            if (dd < bestD && oldFree(CGRectMake(p.x - cw / 2.0, p.y - ch / 2.0, cw, ch), taken, area)) { best = p; bestD = dd; }
        }
        if (bestD < CGFLOAT_MAX) return best;
    }
    *found = NO;
    return cc;
}
static CGPoint oldNext(NSArray<NSValue *> *taken, CGRect area, BOOL *found) {
    CGFloat gx = cw + 8.0, gy = ch + 6.0;
    *found = YES;
    for (CGFloat x = CGRectGetMaxX(area) - cw / 2.0; x >= CGRectGetMinX(area) + cw / 2.0 - 0.5; x -= gx)
        for (CGFloat y = CGRectGetMinY(area) + ch / 2.0; y <= CGRectGetMaxY(area) - ch / 2.0 + 0.5; y += gy)
            if (oldFree(CGRectMake(x - cw / 2.0, y - ch / 2.0, cw, ch), taken, area)) return CGPointMake(x, y);
    return oldNear(CGPointMake(CGRectGetMaxX(area) - cw / 2.0, CGRectGetMinY(area) + ch / 2.0), taken, area, found);
}

// ---- a modelled page 1 ----
typedef struct { const char *name; CGFloat w, h; int cols, rows; } Screen;
static NSMutableArray<NSValue *> *occupied(Screen s, int apps, CGRect *areaOut) {
    BOOL portrait = s.w < s.h;
    CGFloat dockTop = portrait ? s.h - 96.0 : s.h - 84.0;
    CGRect desktop = CGRectMake(0, 26.0, s.w, dockTop - 26.0);   // (DMNativeDesktop: below the menu bar, above the Dock)
    *areaOut = CGRectIntersection(CGRectInset(desktop, 6.0, 4.0), CGRectMake(0, 0, s.w, s.h));   // (-dm_area)
    NSMutableArray *a = [NSMutableArray array];
    CGFloat iconW = 84.0, iconH = 100.0, mx = portrait ? 70.0 : 110.0, my = 50.0;
    CGFloat stepX = (s.w - 2 * mx - iconW) / (s.cols - 1), stepY = (dockTop - 60.0 - my - iconH) / (s.rows - 1);
    for (int i = 0; i < apps && i < s.cols * s.rows; i++) {
        int r = i / s.cols, c = i % s.cols;
        [a addObject:[NSValue valueWithRect:CGRectInset(CGRectMake(mx + c * stepX, my + r * stepY, iconW, iconH), -4.0, -4.0)]];
    }
    [a addObject:[NSValue valueWithRect:CGRectInset(CGRectMake(s.w / 2.0 - 68.0, dockTop - 46.0, 136.5, 40.0), -4.0, -4.0)]];   // (the page dots)
    return a;
}
static void placerFor(DMPlacer *p, NSArray<NSValue *> *occ, CGRect area) {
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].rectValue;
    DMPlacerInit(p, area, cw, ch, r, (int)occ.count);
    free(r);
}
static CGRect cell(CGPoint c) { return CGRectMake(c.x - cw / 2.0, c.y - ch / 2.0, cw, ch); }
static BOOL overAny(CGRect r, NSArray<NSValue *> *occ) { for (NSValue *v in occ) if (CGRectIntersectsRect(v.rectValue, r)) return YES; return NO; }
static NSArray *fractionFor(CGPoint c, CGRect a) { return @[@(MAX(0.0, MIN(1.0, (c.x - a.origin.x) / MAX(1.0, a.size.width)))), @(MAX(0.0, MIN(1.0, (c.y - a.origin.y) / MAX(1.0, a.size.height))))]; }
static CGPoint pointFor(NSArray *f, CGRect a) { return CGPointMake(a.origin.x + [f[0] doubleValue] * a.size.width, a.origin.y + [f[1] doubleValue] * a.size.height); }

// One layout pass as Desktop.h -layoutSubviews runs it: icons with a saved place first (name order), then the new ones (next free spot). Places
// are saved for icons that found room; piled icons keep theirs (none for a new one). Returns the pass's time in ms.
static double layoutPass(NSArray<NSString *> *names, NSMutableDictionary *places, NSArray<NSValue *> *occ, CGRect area, NSMutableDictionary *centres, int *piled, long *tests) {
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    DMPlacer p; placerFor(&p, occ, area);
    NSMutableArray *placed = [NSMutableArray array], *fresh = [NSMutableArray array];
    for (NSString *n in names) [places[n] ? placed : fresh addObject:n];
    *piled = 0;
    for (NSString *n in [placed arrayByAddingObjectsFromArray:fresh]) {
        int fits = 1; NSArray *f = places[n];
        CGPoint c = f ? DMPlacerPlaceNear(&p, pointFor(f, area), &fits) : DMPlacerPlaceNext(&p, &fits);
        if (!fits) (*piled)++;
        else if (!f) places[n] = fractionFor(c, area);
        centres[n] = [NSValue valueWithPoint:c];
    }
    *tests = p.tests;
    DMPlacerFree(&p);
    return (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
}

int main(void) { @autoreleasepool {
    cw = MAX(64.0 + 30.0, 84.0); ch = 2.0 + 64.0 + 4.0 + 15.0 + 2.0 + 4.0;   // (side 64: an iPad's app icon, -dm_measure)
    Screen screens[] = { {"1194x834 landscape", 1194, 834, 6, 4}, {"834x1194 portrait", 834, 1194, 4, 6}, {"1024x768 landscape", 1024, 768, 6, 4}, {"768x1024 portrait", 768, 1024, 4, 6} };
    double worst40 = 0, worst200 = 0;
    // the raster's overlap rule is CGRectIntersectsRect's (edges touching don't count)
    {
        DMPlacer p; DMPlacerInit(&p, CGRectMake(0, 0, 400, 400), cw, ch, NULL, 0);
        int differ = 0; srandom(7);
        for (int k = 0; k < 200000; k++) {
            CGFloat x = random() % 400, y = random() % 400; CGRect r = CGRectMake(random() % 400, random() % 400, 1 + random() % 120, 1 + random() % 120);
            if (k % 3 == 0) r.origin.x = x + cw / 2.0;   // (touching edges, often)
            if (DMPlacerOver(&p, x, y, r) != (int)CGRectIntersectsRect(cell(CGPointMake(x, y)), r)) differ++;
        }
        DMPlacerFree(&p);
        CHECK(differ == 0, "the overlap rule differs from CGRectIntersectsRect %d times", differ);
    }
    for (int si = 0; si < 4; si++) {
        Screen s = screens[si];
        for (int apps = 0; apps <= s.cols * s.rows; apps += s.cols * s.rows / 2) {
            CGRect area; NSMutableArray *occ = occupied(s, apps, &area);
            // -- new files, one after the other: the same spots as the old search while it found room; never over an app icon or outside the area
            DMPlacer p; placerFor(&p, occ, area);
            NSMutableArray *oldTaken = [occ mutableCopy];
            int same = 0, fitted = 0, oldFitted = 0, overApp = 0, outside = 0, bands = 0, n = 40;
            NSMutableArray *icons = [NSMutableArray array];
            for (int k = 0; k < n; k++) {
                int fits = 0; CGPoint c = DMPlacerPlaceNext(&p, &fits);
                BOOL ofound = NO; CGPoint o = oldNext(oldTaken, area, &ofound);
                if (ofound) { [oldTaken addObject:[NSValue valueWithRect:cell(o)]]; oldFitted++; }
                if (fits) { fitted++; if (ofound && hypot(c.x - o.x, c.y - o.y) < 0.01) same++; }
                CGRect r = cell(c);
                if (overAny(r, occ)) overApp++;
                if (!CGRectContainsRect(CGRectInset(area, -0.5, -0.5), r)) outside++;
                if (CGRectGetMinY(r) < 26.0 || CGRectGetMaxY(r) > CGRectGetMaxY(area) + 0.5) bands++;
                [icons addObject:[NSValue valueWithPoint:c]];
            }
            DMPlacerFree(&p);
            BOOL anyRoom = fitted > 0;
            printf("%-20s apps %2d: %2d/%d new icons on free spots (the old search: %d), %d in the pile, %d as the old search placed them\n", s.name, apps, fitted, n, oldFitted, n - fitted, same);
            CHECK(outside == 0, "%s apps %d: %d icons outside the free area", s.name, apps, outside);
            CHECK(bands == 0, "%s apps %d: an icon under the menu bar or the Dock", s.name, apps);
            CHECK(!anyRoom || overApp == 0, "%s apps %d: %d icons over an app icon although there was room", s.name, apps, overApp);
            CHECK(fitted >= oldFitted || apps == s.cols * s.rows, "%s apps %d: fewer icons on free spots (%d) than before (%d)", s.name, apps, fitted, oldFitted);
            // (while the grid has room the order is the old one exactly: top right, down the column, then the column to its left)
            if (apps == 0) CHECK(same == fitted, "%s apps 0: %d of %d new icons not where the old search put them", s.name, fitted - same, fitted);
            // -- turning: the fractions mapped onto the turned page stay inside its area
            Screen o = { "turned", s.h, s.w, s.rows, s.cols }; CGRect area2; NSMutableArray *occ2 = occupied(o, apps, &area2);
            DMPlacer p2; placerFor(&p2, occ2, area2);
            int bad = 0, under = 0, fit2 = 0;
            for (NSValue *v in icons) {
                int fits = 0; CGPoint c2 = DMPlacerPlaceNear(&p2, pointFor(fractionFor(v.pointValue, area), area2), &fits);
                if (!CGRectContainsRect(CGRectInset(area2, -0.5, -0.5), cell(c2))) bad++;
                if (fits) fit2++;
                if (overAny(cell(c2), occ2)) under++;
            }
            DMPlacerFree(&p2);
            CHECK(bad == 0, "%s apps %d: %d icons outside the area after turning", s.name, apps, bad);
            CHECK(fit2 == 0 || under == 0, "%s apps %d: %d icons over an app icon after turning", s.name, apps, under);
        }
        // -- the nearest free spot to a wanted point (a drop), with room: never farther than the old search's answer, and free
        {
            CGRect area; NSMutableArray *occ = occupied(s, s.cols * s.rows / 2, &area);
            int worse = 0, notFree = 0, k = 0;
            for (CGFloat x = area.origin.x; x < CGRectGetMaxX(area); x += 37.0) for (CGFloat y = area.origin.y; y < CGRectGetMaxY(area); y += 41.0, k++) {
                DMPlacer p; placerFor(&p, occ, area);
                int fits = 0; CGPoint c = DMPlacerPlaceNear(&p, CGPointMake(x, y), &fits);
                DMPlacerFree(&p);
                BOOL of = NO; CGPoint o = oldNear(CGPointMake(x, y), occ, area, &of);
                if (fits && (overAny(cell(c), occ) || !CGRectContainsRect(area, cell(c)))) notFree++;
                if (of && hypot(c.x - x, c.y - y) > hypot(o.x - x, o.y - y) + 3.0) worse++;   // (the 4 pt raster: within 3 pt of the old answer's distance, or nearer)
            }
            CHECK(notFree == 0, "%s: %d drops on a spot that isn't free", s.name, notFree);
            CHECK(worse == 0, "%s: %d of %d drops farther from the point than the old search put them", s.name, worse, k);
        }
        // -- the cost: full page 1, 40 and 200 files, a first pass (all new) and the next pass (every icon has a place)
        for (int files = 40; files <= 200; files += 160) {
            CGRect area; NSMutableArray *occ = occupied(s, s.cols * s.rows, &area);
            NSMutableArray *names = [NSMutableArray array]; for (int k = 0; k < files; k++) [names addObject:[NSString stringWithFormat:@"file %03d.txt", k]];
            NSMutableDictionary *places = [NSMutableDictionary dictionary], *centres = [NSMutableDictionary dictionary];
            int piled = 0; long tests = 0;
            double first = layoutPass(names, places, occ, area, centres, &piled, &tests), next = 0;
            int piledFirst = piled; long testsFirst = tests;
            for (int rep = 0; rep < 5; rep++) next = MAX(next, layoutPass(names, places, occ, area, centres, &piled, &tests));
            double ms = MAX(first, next);
            if (files == 40) worst40 = MAX(worst40, ms); else worst200 = MAX(worst200, ms);
            // (the pile: on free ground when the page had any room; every icon on free ground is free of app icons)
            int over = 0; for (NSString *n in names) if (overAny(cell([centres[n] pointValue]), occ)) over++;
            BOOL room = piledFirst < files;
            printf("%-20s full page, %3d files: %3d on free spots, %3d in the pile; first pass %ld rect tests %.2f ms, next passes %ld tests %.2f ms\n",
                   s.name, files, files - piledFirst, piledFirst, testsFirst, first, tests, next);
            CHECK(!room || over == 0, "%s full page %d files: %d icons over an app icon", s.name, files, over);
            CHECK(ms < 5.0, "%s full page %d files: a layout pass took %.2f ms", s.name, files, ms);
        }
    }
    // right-to-left (1.3.3): a mirrored placer gives the mirror image of an unmirrored one fed the mirrored page -- new icons from the top left,
    // nearest spots and the pile mirrored too -- on every screen, with app icons on one side only and with a full page
    for (int si = 0; si < 4; si++) for (int apps = 0; apps <= 24; apps += 12) {
        Screen s = screens[si]; CGRect area; NSMutableArray<NSValue *> *occ = occupied(s, apps, &area);
        CGFloat flip = CGRectGetMinX(area) + CGRectGetMaxX(area);
        NSMutableArray<NSValue *> *mocc = [NSMutableArray array];
        for (NSValue *v in occ) { CGRect r = v.rectValue; r.origin.x = flip - CGRectGetMaxX(r); [mocc addObject:[NSValue valueWithRect:r]]; }
        CGRect *ra = malloc(sizeof(CGRect) * MAX(1, occ.count)), *rb = malloc(sizeof(CGRect) * MAX(1, occ.count));
        for (NSUInteger k = 0; k < occ.count; k++) { ra[k] = occ[k].rectValue; rb[k] = mocc[k].rectValue; }
        DMPlacer a, b; DMPlacerInitDir(&a, area, cw, ch, ra, (int)occ.count, 1); DMPlacerInit(&b, area, cw, ch, rb, (int)occ.count);
        int same = 1, firstLeft = 1;
        for (int k = 0; k < 60; k++) {
            int fa = 1, fb = 1;
            CGPoint pa = DMPlacerPlaceNext(&a, &fa), pb = DMPlacerPlaceNext(&b, &fb);
            if (fa != fb || fabs(pa.x - (flip - pb.x)) > 0.01 || fabs(pa.y - pb.y) > 0.01) same = 0;
            if (k == 0 && apps == 0) firstLeft = pa.x < CGRectGetMidX(area);
        }
        CGPoint want = CGPointMake(CGRectGetMinX(area) + 0.3 * area.size.width, CGRectGetMinY(area) + 0.4 * area.size.height);
        int fa = 1, fb = 1;
        CGPoint na = DMPlacerPlaceNear(&a, want, &fa), nb = DMPlacerPlaceNear(&b, CGPointMake(flip - want.x, want.y), &fb);
        if (fa != fb || fabs(na.x - (flip - nb.x)) > 0.01 || fabs(na.y - nb.y) > 0.01) same = 0;
        CHECK(same, "%s, %d apps: the mirrored placer is not the mirror image", s.name, apps);
        CHECK(firstLeft, "%s, empty page: the first new icon is not at the left (right-to-left)", s.name);
        DMPlacerFree(&a); DMPlacerFree(&b); free(ra); free(rb);
    }
    // the old search on the worst case, for the record
    {
        Screen s = screens[0]; CGRect area; NSMutableArray *taken = occupied(s, 24, &area);
        oldTests = 0; CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent(); BOOL f;
        for (int k = 0; k < 200; k++) { CGPoint c = oldNext(taken, area, &f); [taken addObject:[NSValue valueWithRect:cell(c)]]; }
        printf("INFO: the old search, 200 files on a full page 1 (1194x834): %ld rect tests, %.0f ms\n", oldTests, (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
    }
    printf("worst layout pass: %.2f ms with 40 files, %.2f ms with 200 files (full page 1)\n", worst40, worst200);
    printf("test-desktopplace: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
