// SMPastEdge.h -- with our Stage Manager engine a window can be moved partly past the screen's left, right and bottom edges, as Aerial's (StatusBar.x
// DMA5DragFollow, 1.8.8.3), Zetsu's and MilkyWay4's windows can (1.8.8.3, GitHub #19: "like Aerial and Zetsu").
// Plain C on CoreGraphics, so the Mac tests (tools/test-smpastedge.sh, test-smlayout17.sh) run this very code; StatusBar.x calls it from the title
// bar's drag (-[DMSMTitleBar dm_pan:]), from our requests (DMSMAttrsFitScreen), from Stage Manager's layout passes (iPadOS 16: around the stage-area
// constraint; 17 and 18: DMSM17PassEnd, SMEngineAPI.h) and from a resize by hand (SMResizeAnchor.h).
//  - How far: as with the other engines (StatusBar.x DMZetsuBarPan, MilkyWay4's -dragged:). The window follows the finger or the pointer, so the point
//    of the title bar they hold stays on the screen; its top never goes above the desktop's top (under the menu bar), as every engine holds it; nothing
//    else holds it: left, right and down it goes as far as the finger takes it, its title bar behind the Dock too.
//  - With the Dock at a side of the screen nothing stays past an edge: every engine keeps a window let go out of a side Dock and inside the desktop
//    (DockSide.h MSBDDockSideKeepOut); the drag holds the top only, as with the Dock at the bottom.
//  - Which windows: only one the user let go past an edge, at the very place it was let go, and as a resize by hand then changes it (StatusBar.x keeps
//    a record of its centre and size in points on a screen of that size). Every other place -- a new window, a layout, Fill, a turn, a window Stage
//    Manager brings back by itself -- is fitted inside the desktop as before.
#ifndef MSBD_SM_PAST_EDGE_H
#define MSBD_SM_PAST_EDGE_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline int DMSMPastEdgeFiniteRect(CGRect r) {
    return isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) && isfinite(r.size.height) && r.size.width > 0 && r.size.height > 0;
}

// The whole window w (our title bar on top, the card under it) moved, its size kept, so that its top is no higher than the desktop's top (desk: under
// the menu bar), as every engine keeps a title bar. Left, right and down it is never held. Anything not a number, or no desktop: w as it is.
static inline CGRect DMSMPastEdgeKeep(CGRect w, CGRect desk) {
    if (!DMSMPastEdgeFiniteRect(w) || !DMSMPastEdgeFiniteRect(desk)) return w;
    return CGRectMake(w.origin.x, fmax(w.origin.y, CGRectGetMinY(desk)), w.size.width, w.size.height);
}

// The same rule for a card (Stage Manager's window: its centre c and size s, our title bar of height bar on top of it): the centre it keeps to.
static inline CGPoint DMSMPastEdgeCardCenter(CGPoint c, CGSize s, CGRect desk, CGFloat bar) {
    if (!isfinite(c.x) || !isfinite(c.y) || !isfinite(bar) || !(s.width > 0) || !(s.height > 0)) return c;
    CGRect w = CGRectMake(c.x - s.width / 2.0, c.y - s.height / 2.0 - bar, s.width, s.height + bar);
    CGRect k = DMSMPastEdgeKeep(w, desk);
    return CGPointMake(c.x + (k.origin.x - w.origin.x), c.y + (k.origin.y - w.origin.y));
}

// The whole window w reaches past the screen's left, right or bottom edge (screen: its bounds) by more than half a point. The top is never past.
static inline int DMSMPastEdgeOut(CGRect w, CGRect screen) {
    if (!DMSMPastEdgeFiniteRect(w) || !DMSMPastEdgeFiniteRect(screen)) return 0;
    return CGRectGetMinX(w) < CGRectGetMinX(screen) - 0.5 || CGRectGetMaxX(w) > CGRectGetMaxX(screen) + 0.5 || CGRectGetMaxY(w) > CGRectGetMaxY(screen) + 0.5;
}

// A window at a recorded place: its centre and size within a point of the record's, on a screen of the record's size.
static inline int DMSMPastEdgeSame(CGPoint c, CGSize s, CGSize scr, CGPoint rc, CGSize rs, CGSize rscr) {
    return fabs(scr.width - rscr.width) < 0.5 && fabs(scr.height - rscr.height) < 0.5 && fabs(c.x - rc.x) < 1.0 && fabs(c.y - rc.y) < 1.0
        && fabs(s.width - rs.width) < 1.0 && fabs(s.height - rs.height) < 1.0;
}

// A record made on the iPad's screen in its other shape (the iPad turned since): a screen of `rscr` is `main` turned (and not square). Such a record is
// dropped: a turn fits every window into the new desktop, on every engine, and turning back does not send it past the edge again.
static inline int DMSMPastEdgeTurnedAway(CGSize rscr, CGSize main) {
    return fabs(rscr.width - rscr.height) >= 0.5 && fabs(rscr.width - main.height) < 0.5 && fabs(rscr.height - main.width) < 0.5;
}

// ---- a resize by hand of a window past an edge: it stays where it is, as Aerial's, Zetsu's and MilkyWay4's resizes leave a window ----
// The sides a resize drags (SMResizeAnchorMath.h MSBDResizeSidesOf: a corner two, a side one).
enum { kDMSMPastEdgeLeft = 1, kDMSMPastEdgeRight = 2, kDMSMPastEdgeTop = 4, kDMSMPastEdgeBottom = 8 };
// The card as a resize by hand began (start: as drawn, in the screen's points) is the recorded window's (its centre rc and size rs): every side within
// 3 pt (a card can be drawn a point off the size Stage Manager lays it out at).
static inline int DMSMPastEdgeSameCard(CGRect start, CGPoint rc, CGSize rs) {
    if (!DMSMPastEdgeFiniteRect(start) || !isfinite(rc.x) || !isfinite(rc.y) || !(rs.width > 0) || !(rs.height > 0)) return 0;
    return fabs(CGRectGetMinX(start) - (rc.x - rs.width / 2.0)) < 3.0 && fabs(CGRectGetMaxX(start) - (rc.x + rs.width / 2.0)) < 3.0
        && fabs(CGRectGetMinY(start) - (rc.y - rs.height / 2.0)) < 3.0 && fabs(CGRectGetMaxY(start) - (rc.y + rs.height / 2.0)) < 3.0;
}
// The card now (its centre c and size s) is that window resized: every side the resize does not drag still where it was at `from` (the record's card as
// the resize began), within a point; the dragged sides wherever the finger has them. A resize holds at least one side of each axis: anything else
// (no side, or both sides of an axis dragged) is not one.
static inline int DMSMPastEdgeResized(CGPoint c, CGSize s, CGRect from, unsigned dragged) {
    if (!isfinite(c.x) || !isfinite(c.y) || !(s.width > 0) || !(s.height > 0) || !DMSMPastEdgeFiniteRect(from) || !dragged) return 0;
    if ((dragged & (kDMSMPastEdgeLeft | kDMSMPastEdgeRight)) == (kDMSMPastEdgeLeft | kDMSMPastEdgeRight)
        || (dragged & (kDMSMPastEdgeTop | kDMSMPastEdgeBottom)) == (kDMSMPastEdgeTop | kDMSMPastEdgeBottom)) return 0;
    CGFloat x0 = c.x - s.width / 2.0, x1 = c.x + s.width / 2.0, y0 = c.y - s.height / 2.0, y1 = c.y + s.height / 2.0;
    return ((dragged & kDMSMPastEdgeLeft) || fabs(x0 - CGRectGetMinX(from)) < 1.0) && ((dragged & kDMSMPastEdgeRight) || fabs(x1 - CGRectGetMaxX(from)) < 1.0)
        && ((dragged & kDMSMPastEdgeTop) || fabs(y0 - CGRectGetMinY(from)) < 1.0) && ((dragged & kDMSMPastEdgeBottom) || fabs(y1 - CGRectGetMaxY(from)) < 1.0);
}

#endif
