// WindowMinSize.h -- the smallest a window of the window engines (Aerial 3.0 / 5.x, Zetsu, MilkyWay4) may be, as Stage Manager's (1.7.0), plain C
// on CoreGraphics so the Mac test (tools/test-winminsize.m) runs this very code; StatusBar.x keeps every way a window gets its size to it. Our Stage
// Manager engine keeps the same: its size lists start there (SMEngineAPI.h DMSMFineGrid: a corner drag stops there) and so do its tiles.
//  - Stage Manager makes no window narrower than 320 pt (-[SBSwitcherChamoisLayoutAttributes minimumWindowWidth]: 320 on 16.7.7, 17.5.1 and 18.5)
//    and no app shorter than its size grid's first height -- in our Stage Manager engine 300 pt on 17+ (SMEngineAPI.h kSM17MinWindowHeight; Apple's
//    own list starts at 480, which made Fit to Window's landscape quarters overlap). The engines' windows get the same: the app at least 320 x 300,
//    the window that and our 24 pt title bar above it (on every engine the app is the window's whole width and its height less the bar). Without
//    it a corner drag took Clock down to 279 x 214 under Aerial 5.1 (M1 15.6.1, 28 Oct: one row of its compact layout left). Never more than the
//    room there is: on a smaller screen or in a smaller area the window gets all of it.
//  - A layout's tile smaller than that keeps its own sides -- a left tile its left edge, a bottom tile its bottom edge -- and grows over its
//    neighbour, as Stage Manager's tiles keep its minimum width (StatusBar.x DMSMLayoutFrameIn) and a Mac window its minimum size when it is tiled.
//    On our iPads every tile is bigger already (the narrowest: the iPad 2's portrait halves, 353 pt; the shortest: its landscape quarters, 331).
//  - A frame fitted into the desktop (a window brought back after a respring, a turn's scaled frame, a remembered place) grows from its top-left
//    corner and is then kept inside the desktop, as before.
//  - A corner drag stops there: the top edge and the side that is not dragged stay, and the window grows for it only as far as the screen's edges.
//  - Aerial (none of its classes may be hooked on 5.x) works every step of a corner drag out as the finger plus an offset of its own, the corner's
//    distance from the finger as the drag began (_cornerOffset): the offset that keeps the step at least the minimum.
#ifndef MSBD_WINDOW_MIN_SIZE_H
#define MSBD_WINDOW_MIN_SIZE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

#define kMSBDWindowMinWidth 320.0       // Stage Manager's minimumWindowWidth: the app's width, which is the window's
#define kMSBDWindowMinAppHeight 300.0   // the app's height: our Stage Manager engine's first grid height on 17+ (kSM17MinWindowHeight)
#define kMSBDWindowBarHeight 24.0       // our title bar above the app, on every engine

// The smallest window, its title bar included (320 x 324).
static inline CGSize MSBDWindowMinSize(void) { return CGSizeMake(kMSBDWindowMinWidth, kMSBDWindowMinAppHeight + kMSBDWindowBarHeight); }

// The sides of a layout's tile that stay where they are when it grows (from its layout's name: left, topright...); a tile that keeps neither side
// of an axis (the centred sizes, a half's other axis) grows around its middle.
enum { MSBDKeepLeft = 1, MSBDKeepRight = 2, MSBDKeepTop = 4, MSBDKeepBottom = 8 };
static inline unsigned MSBDWindowKeepForLayout(const char *name) {   // ("left" / "right" anywhere in it, "top" / "bottom" at its start)
    if (!name) return 0;
    return (strstr(name, "left") ? MSBDKeepLeft : 0) | (strstr(name, "right") ? MSBDKeepRight : 0)
         | (!strncmp(name, "top", 3) ? MSBDKeepTop : 0) | (!strncmp(name, "bottom", 6) ? MSBDKeepBottom : 0);
}
static inline void MSBDWindowMinAxis(CGFloat *lo, CGFloat *len, CGFloat min, CGFloat areaLo, CGFloat areaLen, bool keepLo, bool keepHi) {
    CGFloat want = fmin(min, areaLen);
    if (*len >= want) return;
    CGFloat at = keepLo == keepHi ? round(*lo + (*len - want) / 2.0) : (keepLo ? *lo : *lo + *len - want);
    *lo = fmax(areaLo, fmin(at, areaLo + areaLen - want));
    *len = want;
}
// A layout's tile grown to the minimum m where it is smaller, its kept sides where they are, inside the area the layouts use. A tile that is big
// enough is left exactly as it is. Stage Manager's tiles (StatusBar.x DMSMLayoutFrameIn): m is this minimum, or wider where Stage Manager's own
// smallest width there is wider.
static inline CGRect MSBDWindowMinSlotOf(CGRect slot, unsigned keep, CGRect area, CGSize m) {
    if (CGRectIsNull(slot) || CGRectIsNull(area)) return slot;
    CGFloat x = slot.origin.x, w = slot.size.width, y = slot.origin.y, h = slot.size.height;
    MSBDWindowMinAxis(&x, &w, m.width, area.origin.x, area.size.width, (keep & MSBDKeepLeft) != 0, (keep & MSBDKeepRight) != 0);
    MSBDWindowMinAxis(&y, &h, m.height, area.origin.y, area.size.height, (keep & MSBDKeepTop) != 0, (keep & MSBDKeepBottom) != 0);
    return CGRectMake(x, y, w, h);
}
// The engines' tiles (StatusBar.x DMWindowSlotInArea): the minimum itself.
static inline CGRect MSBDWindowMinSlot(CGRect slot, unsigned keep, CGRect area) { return MSBDWindowMinSlotOf(slot, keep, area, MSBDWindowMinSize()); }
// An engine's frame fitted into the desktop (StatusBar.x DMFitInto): no smaller than min -- it grows from its top-left corner --, no bigger than
// the desktop, and inside it. min: the minimum as the engine's frame (Aerial 5.x's stage is the window grown by its margins).
static inline CGRect MSBDWindowMinFit(CGRect f, CGRect area, CGSize min) {
    if (CGRectIsNull(area)) return f;
    f.size.width = fmin(fmax(f.size.width, min.width), area.size.width);
    f.size.height = fmin(fmax(f.size.height, min.height), area.size.height);
    f.origin.x = fmax(area.origin.x, fmin(f.origin.x, area.origin.x + area.size.width - f.size.width));
    f.origin.y = fmax(area.origin.y, fmin(f.origin.y, area.origin.y + area.size.height - f.size.height));
    return f;
}
// A corner drag's frame -- MilkyWay4's handle (the frame its own step set), Zetsu's grips (MSBDWindowCornerDrag) -- grown to the minimum where it
// is smaller: the top edge and the side that is not dragged stay (keepRight: the left corner is dragged), and it grows only as far as the screen's
// edges. A frame at least the minimum is left as it is.
static inline CGRect MSBDWindowMinCorner(CGRect f, bool keepRight, CGSize min, CGSize screen) {
    CGFloat right = f.origin.x + f.size.width, w = f.size.width, h = f.size.height;
    if (w < min.width) w = fmax(w, fmin(min.width, keepRight ? right : screen.width - f.origin.x));
    if (h < min.height) h = fmax(h, fmin(min.height, screen.height - f.origin.y));
    return CGRectMake(keepRight ? right - w : f.origin.x, f.origin.y, w, h);
}
// MilkyWay4's resize step (StatusBar.x DMMWKeepMinSize): MilkyWay sizes the window from the frame its recogniser began with plus the finger's
// travel. Once the finger is past the window's own top-left corner that size is negative, and the window comes back turned round -- its origin
// moved to where the corner went: dragged far in, the window went up and left, off the screen (M1 15.6.1, 29 Oct: {{-298, -492}, {320, 324}}).
// Its one resize corner is the bottom right, so the top-left corner the drag began with (topLeft) is the one that stays: the step's bottom-right
// corner measured from there, then at least the minimum (MSBDWindowMinCorner). A step that keeps its top-left and is big enough is left as it is.
static inline CGRect MSBDWindowMinCornerFrom(CGRect f, CGPoint topLeft, CGSize min, CGSize screen) {
    if (CGRectIsNull(f)) return f;
    CGFloat right = f.origin.x + f.size.width, bottom = f.origin.y + f.size.height;
    CGRect g = CGRectMake(topLeft.x, topLeft.y, fmax(0.0, right - topLeft.x), fmax(0.0, bottom - topLeft.y));
    return MSBDWindowMinCorner(g, false, min, screen);
}
// Zetsu's grips (StatusBar.x DMZetsuGripBox): the frame from the one the drag began with and the finger's travel d (left: the left corner), its
// moving sides never past the screen's edges, at least the minimum.
static inline CGRect MSBDWindowCornerDrag(CGRect start, CGPoint d, bool left, CGSize min, CGSize screen) {
    CGFloat right = start.origin.x + start.size.width;
    CGFloat w = left ? fmin(start.size.width - d.x, right) : fmin(start.size.width + d.x, screen.width - start.origin.x);
    CGFloat h = fmin(start.size.height + d.y, screen.height - start.origin.y);
    return MSBDWindowMinCorner(CGRectMake(left ? right - w : start.origin.x, start.origin.y, w, h), left, min, screen);
}
// Aerial's corner drag (StatusBar.x DMAerialCornerMin): each step puts the dragged corner at the finger plus Aerial's offset (the corner's distance
// from the finger as the drag began), the drag's other sides where they were then (start). The offset for this step: Aerial's own while the window
// stays at least the minimum, else the one that puts the corner at the minimum -- the corner stops there until the finger comes back to it (as far
// as the screen allows: the window grows for it no further than the screen's edges). min: as Aerial's frame (5.x: the stage). left: the left corner.
static inline CGPoint MSBDWindowMinCornerOffset(CGPoint finger, CGPoint offset, CGRect start, CGSize min, bool left, CGSize screen) {
    CGPoint o = offset;
    CGFloat right = start.origin.x + start.size.width;
    if (left) { CGFloat most = right - fmin(min.width, right); if (finger.x + o.x > most) o.x = most - finger.x; }   // (the left edge: no further right)
    else { CGFloat least = start.origin.x + fmin(min.width, screen.width - start.origin.x); if (finger.x + o.x < least) o.x = least - finger.x; }
    CGFloat bottom = start.origin.y + fmin(min.height, screen.height - start.origin.y);
    if (finger.y + o.y < bottom) o.y = bottom - finger.y;   // (the bottom edge: no further up)
    return o;
}
#endif
