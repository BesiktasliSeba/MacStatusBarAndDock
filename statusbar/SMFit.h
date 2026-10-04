// SMFit.h -- where a Stage Manager window may go on its screen (the Stage Manager engine in StatusBar.x), plain C on CoreGraphics so the Mac test
// (tools/test-smfit.m) runs this very code.
//  - A window's size as Stage Manager reads it (SBDisplayItemAttributedSize): a fraction of the reference rectangle kept WITH the attributes, not of
//    the screen as it is now. Attributes made in portrait keep portrait's reference after a turn (and a full-screen window's attributes can carry
//    the other shape's), so "0.6 x 0.72" is 461 x 737 pt in landscape -- taller than the desktop. Sizes are compared and fitted in points.
//  - A window fits the desktop when all of it is inside the card area (under the menu bar and our title bar, above the Dock): no bigger than the
//    area, then moved inside. When a window is bigger than an area anyway, its top and left edges win: the title bar and the traffic lights stay on
//    the screen and the window reaches down behind the Dock (as on a Mac, and as the iPadOS 17 pass does, DMSMClampCenter). Stage Manager's own step
//    kept the BOTTOM inside instead and pushed the top under the menu bar (iPad 2, 3 Oct: Settings back from full screen, its top 40 pt above the
//    screen, no title bar, no traffic lights).
#ifndef MSBD_SM_FIT_H
#define MSBD_SM_FIT_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

// The size in points of an attributed size on a screen of `screen`: type 0 = fractions of the reference rectangle (the screen itself when none is
// kept), 3 = the whole screen. Any other type is a size Stage Manager works out itself (its grid caps those): zero = not ours to fit.
static inline CGSize DMSMFitSizeInPoints(CGSize normalized, CGRect reference, long long type, CGSize screen) {
    if (!(screen.width > 0) || !(screen.height > 0)) return CGSizeZero;
    if (type == 3) return screen;
    if (type != 0 || !(normalized.width > 0) || !(normalized.height > 0) || !isfinite(normalized.width) || !isfinite(normalized.height)) return CGSizeZero;
    CGSize ref = (reference.size.width > 0 && reference.size.height > 0 && isfinite(reference.size.width) && isfinite(reference.size.height)) ? reference.size : screen;
    return CGSizeMake(normalized.width * ref.width, normalized.height * ref.height);
}

// A window's center clamped into `area` for its size: the right/bottom limits first, then the left/top ones, so when the window is bigger than the
// area its left and top edges are the ones on the area's edges.
static inline CGPoint DMSMFitClampTopLeft(CGPoint c, CGSize s, CGRect area) {
    CGFloat x = c.x, y = c.y;
    x = fmin(x, CGRectGetMaxX(area) - s.width / 2.0);  x = fmax(x, CGRectGetMinX(area) + s.width / 2.0);
    y = fmin(y, CGRectGetMaxY(area) - s.height / 2.0); y = fmax(y, CGRectGetMinY(area) + s.height / 2.0);
    return CGPointMake(x, y);
}

// A window of *size (points) around *center (points) fitted into `desk`: no wider or taller than desk, then moved so all of it is inside. Returns 1
// when the size or the center changed by half a point or more (0: it fitted already; also when desk is too small to hold a window -- never seen --
// or anything is not a number: nothing is changed then).
static inline int DMSMFitInDesk(CGSize *size, CGPoint *center, CGRect desk) {
    if (!size || !center || !(desk.size.width >= 50.0) || !(desk.size.height >= 50.0) || !isfinite(desk.origin.x) || !isfinite(desk.origin.y)
        || !isfinite(size->width) || !isfinite(size->height) || !isfinite(center->x) || !isfinite(center->y) || !(size->width > 0) || !(size->height > 0)) return 0;
    CGSize s = CGSizeMake(fmin(size->width, desk.size.width), fmin(size->height, desk.size.height));
    CGPoint c = DMSMFitClampTopLeft(*center, s, desk);
    int changed = fabs(s.width - size->width) >= 0.5 || fabs(s.height - size->height) >= 0.5 || fabs(c.x - center->x) >= 0.5 || fabs(c.y - center->y) >= 0.5;
    *size = s; *center = c;
    return changed;
}

// Where a window cascaded from the front window goes (1.3.5 logic test M1): the cascade steps on from the front window's centre fromPt by `step`
// points -- down and right, then up and left where that runs out of room (the bottom-right corner) -- until the window, fitted into `desk`, has its
// centre at least 8 pt from every window's centre in `taken` (points; the front window's included). Before, only the front window was looked at, and a
// window added while another one sat at the cascade spot landed exactly on it (iPad 2, 4 Oct: App Store on Settings, same centre and size).
// *size / *center: in = the first cascade step, fitted; out = the place chosen (unchanged when no step is clear). Returns the step taken: 0 the first
// one, k > 1 the k-th down-right step, -k the k-th up-left step, 99 none clear.
static inline int DMSMCascadeClear(CGPoint fromPt, CGSize step, CGRect desk, const CGPoint *taken, int nTaken, CGSize *size, CGPoint *center) {
    if (!size || !center) return 99;
    for (int k = 0, dir = 1; ; ) {
        CGSize s2 = *size; CGPoint c2 = *center;
        if (k > 0) { c2 = CGPointMake(fromPt.x + dir * k * step.width, fromPt.y + dir * k * step.height); DMSMFitInDesk(&s2, &c2, desk); }
        int clear = 1;
        for (int i = 0; i < nTaken && clear; i++) if (fabs(c2.x - taken[i].x) < 8.0 && fabs(c2.y - taken[i].y) < 8.0) clear = 0;
        if (clear) { *size = s2; *center = c2; return k == 0 ? 0 : dir * k; }
        if (k == 0) { k = 2; dir = 1; }            // (the first step is k = 1 down-right: the one handed in)
        else if (dir == 1 && k < 8) k++;
        else if (dir == 1) { dir = -1; k = 1; }    // (no room down and right: up and left)
        else if (k < 8) k++;
        else return 99;
    }
}

// After Stage Manager has kept a window inside its stage area (-_constrainModelVertically:/Horizontally:toStageArea:, iPadOS 16): where its center
// goes so its top edge (vertical) or left edge (horizontal) is not outside the area -- a window bigger than the area starts at the area's top / left
// edge. A full-screen-sized window (as big as the container) is left as it is: Apple's whole screen. Returns 1 when the center has to move.
static inline int DMSMFitEdgesWin(CGPoint *center, CGSize s, CGRect area, CGSize container, int vertical) {
    if (!center || !isfinite(center->x) || !isfinite(center->y) || !isfinite(s.width) || !isfinite(s.height) || !(s.width > 0) || !(s.height > 0)) return 0;
    if (!(area.size.width >= 50.0) || !(area.size.height >= 50.0) || !isfinite(area.origin.x) || !isfinite(area.origin.y)) return 0;
    if (container.width > 0 && container.height > 0 && s.width >= container.width - 1.0 && s.height >= container.height - 1.0) return 0;
    if (vertical) {
        if (center->y - s.height / 2.0 >= CGRectGetMinY(area) - 0.5) return 0;
        center->y = CGRectGetMinY(area) + s.height / 2.0;
    } else {
        if (center->x - s.width / 2.0 >= CGRectGetMinX(area) - 0.5) return 0;
        center->x = CGRectGetMinX(area) + s.width / 2.0;
    }
    return 1;
}

#endif
