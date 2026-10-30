// SMResizeAnchorMath.h -- the geometry of a Stage Manager window resized by a corner or side with the opposite corner kept (1.7.0, SMResizeAnchor.h),
// plain C on CoreGraphics so the Mac test (tools/test-smresizeanchor.m) runs this very code against a model of iPadOS 16.7.7's own resize step.
//  - Stage Manager's edge numbers (-[SBItemResizeGestureSwitcherModifier selectedEdge], read from the edge masks in 16.7.7's and 17.5.1's code):
//    1 top, 2 bottom, 3 left, 4 right, 5 top left, 6 top right, 7 bottom left, 8 bottom right.
//  - Its anchors (_resizeAnchor): 0 = no side held. 17.5.1 holds the window's own sides: 1 its left (a right-side edge dragged), 2 its right (a
//    left-side edge), from a table (3..8 -> 2 1 2 1 2 1). 16.7.7 holds the stage area's side instead (1 its left, 2 its right), and only for a
//    window within 22 pt of that side with two or more on the stage; otherwise its widths and heights grow and shrink around the window's centre.
#ifndef MSBD_SM_RESIZE_ANCHOR_MATH_H
#define MSBD_SM_RESIZE_ANCHOR_MATH_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <math.h>

typedef struct { bool left, right, top, bottom; } MSBDResizeSides;
static inline MSBDResizeSides MSBDResizeSidesOf(unsigned long long edge) {
    MSBDResizeSides s = { edge == 3 || edge == 5 || edge == 7, edge == 4 || edge == 6 || edge == 8,
                          edge == 1 || edge == 5 || edge == 6, edge == 2 || edge == 7 || edge == 8 };
    return s;
}
// 17.5.1's anchor for an edge: the opposite side held (a side with no width part: 0).
static inline unsigned long long MSBDResizeAnchorFor(unsigned long long edge) {
    MSBDResizeSides s = MSBDResizeSidesOf(edge);
    return s.left ? 2 : s.right ? 1 : 0;
}
// iPadOS 16's step for one of our windows (SMResizeAnchor.h): Apple's own held-side arithmetic, with the window's frame as the drag began as the area
// it is held to. The step reads what is set here, for that one call:
//  - _resizeAnchor = 17's anchor for the edge: the width is the finger to the held side, the centre that side plus half the size;
//  - the area for resizing = the window's frame (the width's sides; the height's too where the height is dragged);
//  - for a dragged height, the frame's centre moved half a window past its far side: the step mirrors the finger about that centre, the mirrored side
//    is then always beyond the area's far side, so the step holds it there -- the window's own far side -- with the height the finger to it.
//  A bottom side dragged on a window as tall as the container less twice the screen-edge padding takes the step's own path for full-height windows
//  (it centres those in the space above the Dock): that height is left to Apple (vertical false).
typedef struct { unsigned long long anchor; CGRect frame; CGFloat areaX, areaW, areaY, areaH; bool vertical; } MSBDResizeFake16;
static inline MSBDResizeFake16 MSBDResizeFake16For(unsigned long long edge, CGRect start, CGFloat containerH, CGFloat padding) {
    MSBDResizeSides s = MSBDResizeSidesOf(edge);
    MSBDResizeFake16 f = { MSBDResizeAnchorFor(edge), start, start.origin.x, start.size.width, start.origin.y, start.size.height, false };
    f.vertical = s.top || (s.bottom && isfinite(containerH) && isfinite(padding) && start.size.height < containerH - 2.0 * padding);
    if (f.vertical) f.frame.origin.y = s.top ? start.origin.y + start.size.height : start.origin.y - start.size.height;
    return f;
}
// Where the dragged sides were from the finger as it touched down (down): kept for the whole drag, as 17.5.1's edge adjustment (with our catch-up)
// and Aerial's corner offset keep it -- 16's step puts the side at the finger itself, so it jumped onto the finger at the first step (by the grab, a
// few points; the pointer's top band at our title bar's outer edge, ~25). Only an axis the edge drags, and a touch-down near the side (60 pt).
static inline CGPoint MSBDResizeGrabOffset(unsigned long long edge, CGRect start, CGPoint down) {
    MSBDResizeSides s = MSBDResizeSidesOf(edge);
    CGPoint o = CGPointMake(0, 0);
    if (s.left || s.right) o.x = (s.left ? start.origin.x : start.origin.x + start.size.width) - down.x;
    if (s.top || s.bottom) o.y = (s.top ? start.origin.y : start.origin.y + start.size.height) - down.y;
    if (!isfinite(o.x) || fabs(o.x) > 60.0) o.x = 0;
    if (!isfinite(o.y) || fabs(o.y) > 60.0) o.y = 0;
    return o;
}
// The window's centre for a size, its opposite sides where they were as the drag began (start); a side not dragged keeps Apple's centre (apple).
static inline CGPoint MSBDResizeCenterKeeping(unsigned long long edge, CGRect start, CGSize size, CGPoint apple, bool vertical) {
    MSBDResizeSides s = MSBDResizeSidesOf(edge);
    CGPoint c = apple;
    if (s.left) c.x = start.origin.x + start.size.width - size.width / 2.0;
    else if (s.right) c.x = start.origin.x + size.width / 2.0;
    if (vertical && s.top) c.y = start.origin.y + start.size.height - size.height / 2.0;
    else if (vertical && s.bottom) c.y = start.origin.y + size.height / 2.0;
    return c;
}
#endif
