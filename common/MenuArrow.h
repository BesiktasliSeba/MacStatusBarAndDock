// MenuArrow.h -- the Mac's arrow (callout tail) on menus that open from a point (1.7.5 item 5, KT 31 Oct: photo of a Dock app's menu on macOS).
// Plain C on CoreGraphics, so the Mac test (tools/test-menuarrow.c) runs this very code. StatusBar.x uses it for the menus of the Dock's icons
// (UIKit's context menus in the Dock's window: apps, folders, Finder, the Trash), dock/Downloads.m for the Downloads stack's panel.
// What it copies (macOS 14 / 15): a Dock item's menu, and a stack's list, opens centred over the item, with an arrow in the middle of the edge that
// faces the item and its tip just short of it. Near the side of the screen the menu is pushed in and the arrow stays over the item, sliding along
// the edge, never into the rounded corners. A menu that opens below its source has the arrow on its top edge, pointing up. Menus that do not open
// from a point have none, as on a Mac: the menu bar's (they hang from the bar), the desktop's and the Home Screen's icon menus, menus in windows.
#ifndef MSBD_MENU_ARROW_H
#define MSBD_MENU_ARROW_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <math.h>

#define kMSBDArrowWidth 20.0        // along the menu's edge, the shoulders included
#define kMSBDArrowHeight 9.0        // from the edge to the tip
#define kMSBDArrowTipGap 3.0        // from the tip to the item
#define kMSBDArrowTipRadius 2.5     // the tip, rounded
#define kMSBDArrowShoulder 3.0      // where the arrow leaves the edge: a rounded shoulder this wide on each side, so the edge flows into it
#define kMSBDArrowMinMenuHeight 44.0   // a menu squeezed shorter than this to make room for the arrow keeps its own place and has no arrow

enum { MSBDArrowNone = 0, MSBDArrowDown = 1, MSBDArrowUp = 2, MSBDArrowRight = 3, MSBDArrowLeft = 4 };   // on the menu's bottom edge pointing down / on its top edge pointing up / on its right edge pointing right / on its left edge pointing left (the Dock at a screen side, 1.8.2)

// Where a menu goes for its source (both in the same space): centred over the source's middle and kept inside bounds sideways; the edge facing the
// source (the bottom when the menu opened above it, as UIKit put it: menu.midY above source.midY) arrowH + tipGap from the source, the menu's
// height kept, or shortened by what it would cross bounds by (it scrolls), down to kMSBDArrowMinMenuHeight. *dir: MSBDArrowDown / MSBDArrowUp,
// or MSBDArrowNone with the menu returned unchanged (no source, no room, nonsense numbers).
static inline CGRect MSBDArrowMenuFrame(CGRect menu, CGRect source, CGRect bounds, CGFloat arrowH, CGFloat tipGap, int *dir) {
    if (dir) *dir = MSBDArrowNone;
    if (CGRectIsNull(menu) || CGRectIsEmpty(menu) || CGRectIsNull(source) || CGRectIsNull(bounds) || CGRectIsEmpty(bounds)) return menu;
    if (!isfinite(menu.origin.x + menu.origin.y + menu.size.width + menu.size.height + source.origin.x + source.origin.y + source.size.width + source.size.height)) return menu;
    bool above = CGRectGetMidY(menu) <= CGRectGetMidY(source);
    CGFloat w = menu.size.width, h = menu.size.height, x, y;
    x = CGRectGetMidX(source) - w / 2.0;
    x = fmax(CGRectGetMinX(bounds), fmin(x, CGRectGetMaxX(bounds) - w));   // (pushed in at the sides; wider than bounds: its left edge)
    if (above) {
        CGFloat bottom = CGRectGetMinY(source) - tipGap - arrowH;
        y = bottom - h;
        if (y < CGRectGetMinY(bounds)) { y = CGRectGetMinY(bounds); h = bottom - y; }
    } else {
        y = CGRectGetMaxY(source) + tipGap + arrowH;
        if (y + h > CGRectGetMaxY(bounds)) h = CGRectGetMaxY(bounds) - y;
    }
    if (h < kMSBDArrowMinMenuHeight - 0.001) return menu;   // (no room: as it was, without an arrow)
    if (dir) *dir = above ? MSBDArrowDown : MSBDArrowUp;
    return CGRectMake(round(x * 2.0) / 2.0, round(y * 2.0) / 2.0, w, round(h * 2.0) / 2.0);
}

// The same with the Dock at the screen's side (1.8.2, common/DockSide.h), as a Mac's side Dock: the menu beside its source, on the side the screen has room
// (dockAtRight: to its left, the arrow on the menu's right edge pointing right; else to its right, the arrow on its left edge), level with the source's
// middle and kept inside bounds up and down (taller than bounds: its top at theirs, shortened, it scrolls). The menu's facing edge arrowH + tipGap from the
// source. *dir: MSBDArrowRight / MSBDArrowLeft, or MSBDArrowNone with the menu returned unchanged.
static inline CGRect MSBDArrowSideMenuFrame(CGRect menu, CGRect source, CGRect bounds, CGFloat arrowH, CGFloat tipGap, bool dockAtRight, int *dir) {
    if (dir) *dir = MSBDArrowNone;
    if (CGRectIsNull(menu) || CGRectIsEmpty(menu) || CGRectIsNull(source) || CGRectIsNull(bounds) || CGRectIsEmpty(bounds)) return menu;
    if (!isfinite(menu.origin.x + menu.origin.y + menu.size.width + menu.size.height + source.origin.x + source.origin.y + source.size.width + source.size.height)) return menu;
    CGFloat w = menu.size.width, h = fmin(menu.size.height, bounds.size.height);
    CGFloat x = dockAtRight ? CGRectGetMinX(source) - tipGap - arrowH - w : CGRectGetMaxX(source) + tipGap + arrowH;
    if (h < kMSBDArrowMinMenuHeight - 0.001 || x < CGRectGetMinX(bounds) - 0.5 || x + w > CGRectGetMaxX(bounds) + 0.5) return menu;   // (no room: as it was, without an arrow)
    CGFloat y = fmax(CGRectGetMinY(bounds), fmin(CGRectGetMidY(source) - h / 2.0, CGRectGetMaxY(bounds) - h));
    if (dir) *dir = dockAtRight ? MSBDArrowRight : MSBDArrowLeft;
    return CGRectMake(round(x * 2.0) / 2.0, round(y * 2.0) / 2.0, w, round(h * 2.0) / 2.0);
}

// The same, with the arrow reaching the source's middle at the Dock's two ends (1.8.2.2, iPad 2 F2): kept inside bounds, a menu or panel level with an icon near
// the top or the bottom of a side Dock left the icon's middle closer to its end than the arrow may come (corner + arrowW / 2: never into the rounded corner), and
// the arrow missed the icon by 5.4 pt (the Downloads panel, 12 pt over the screen's bottom with its 18 pt corner). Then the menu moves along the side just as far as
// its arrow needs, never past reach (the screen's own limits: under the bar, the Dock's end margin over the bottom edge). Where even reach leaves no room the arrow
// stays off the corner as before.
static inline CGRect MSBDArrowSideMenuFrameReaching(CGRect menu, CGRect source, CGRect bounds, CGRect reach, CGFloat arrowH, CGFloat tipGap, CGFloat corner, CGFloat arrowW, bool dockAtRight, int *dir) {
    int d = MSBDArrowNone;
    CGRect f = MSBDArrowSideMenuFrame(menu, source, bounds, arrowH, tipGap, dockAtRight, &d);
    if (dir) *dir = d;
    if (d == MSBDArrowNone || CGRectIsNull(reach) || CGRectIsEmpty(reach) || !isfinite(reach.origin.y + reach.size.height + corner + arrowW)) return f;
    CGFloat mid = CGRectGetMidY(source), lo = corner + arrowW / 2.0, h = f.size.height, y = f.origin.y;
    if (h < 2.0 * lo) return f;
    if (mid - y < lo) y = fmax(CGRectGetMinY(reach), floor((mid - lo) * 2.0) / 2.0);   // (an icon near the top: the menu up, under the bar at most)
    else if (y + h - mid < lo) y = fmin(CGRectGetMaxY(reach) - h, ceil((mid + lo - h) * 2.0) / 2.0);   // (near the bottom: down, to the Dock's end margin at most)
    else return f;
    if (y < CGRectGetMinY(reach) - 0.001 || y + h > CGRectGetMaxY(reach) + 0.001) return f;   // (taller than reach: as it was)
    f.origin.y = y;
    return f;
}

// The lifted picture of a Dock menu with the Dock at a side (1.8.2.2, M1 F1 / A12Z F1). An icon-sized one stays centred on its icon, the menu beside the Dock. One
// that centred on the icon would leave the screen or reach the menu's place -- an app's widget or document preview, Sileo's 437 and 497 pt -- stands as the Bottom
// Dock's does turned to the side: as near the Dock's side as bounds allow, level with the icon and kept inside bounds along the side; the menu goes beside the
// picture then (its source the picture, as at the bottom). Before, every picture was centred on its icon: Sileo's ran 190 pt off the screen, under the bar and over
// its own menu. lifted: the picture as UIKit sized it; home: the icon's middle; inner: the Dock's inner edge (where the side menu's source ends); bounds: the menus'
// room; screenW: the screen's width. *onIcon: 1 when it stays on the icon, 0 when it moved beside the Dock. The picture's frame (lifted unchanged for nonsense).
static inline CGRect MSBDArrowSidePreviewFrame(CGRect lifted, CGPoint home, CGFloat inner, CGRect bounds, CGFloat screenW, CGFloat arrowH, CGFloat tipGap, bool dockAtRight, int *onIcon) {
    if (onIcon) *onIcon = 1;
    if (CGRectIsNull(lifted) || CGRectIsEmpty(lifted) || CGRectIsNull(bounds) || CGRectIsEmpty(bounds)) return lifted;
    if (!isfinite(lifted.size.width + lifted.size.height + home.x + home.y + inner + screenW + bounds.origin.x + bounds.origin.y + bounds.size.width + bounds.size.height)) return lifted;
    CGFloat w = lifted.size.width, h = lifted.size.height;
    CGRect c = CGRectMake(home.x - w / 2.0, home.y - h / 2.0, w, h);   // (centred on the icon)
    CGFloat menuAt = dockAtRight ? inner - tipGap - arrowH : inner + tipGap + arrowH;   // (where the menu beside the Dock begins)
    bool fits = CGRectGetMinX(c) >= -0.5 && CGRectGetMaxX(c) <= screenW + 0.5 && (dockAtRight ? CGRectGetMinX(c) >= menuAt - 0.5 : CGRectGetMaxX(c) <= menuAt + 0.5);
    if (fits) return c;
    if (onIcon) *onIcon = 0;
    CGFloat x = dockAtRight ? CGRectGetMaxX(bounds) - w : CGRectGetMinX(bounds);
    if (w > bounds.size.width) x = CGRectGetMinX(bounds);
    CGFloat y = h > bounds.size.height ? CGRectGetMinY(bounds) : fmax(CGRectGetMinY(bounds), fmin(home.y - h / 2.0, CGRectGetMaxY(bounds) - h));
    return CGRectMake(round(x * 2.0) / 2.0, round(y * 2.0) / 2.0, w, h);
}

// The item order of a Dock menu beside a side Dock (1.8.2.2, iPad 2 F1): UIKit orders a menu from the edge it attached the menu to, the first item next to its source
// -- bottom-up above the source, top-down below it -- and chose above or below by the room it saw, so beside a side Dock the order flipped at the Dock's middle (the
// upper icons' menus top-down, the lower ones' bottom-up, Force Quit first). A Mac's side Dock menus all read top-down: every side menu takes the attachment UIKit
// gives a menu below its source. attachment: UIKit's (a rectangle edge, top 1 or bottom 4, for the edge it chose for this menu); above: UIKit placed this menu above
// its source. Returns the attachment a menu below has -- the one given when UIKit placed it below already, the other of the two when above --, 0 for any other value
// (nothing to change).
static inline unsigned long long MSBDCtxAttachmentBelow(unsigned long long attachment, bool above) {
    if (attachment != 1 && attachment != 4) return 0;
    if (!above) return attachment;
    return attachment == 1 ? 4 : 1;
}

// The arrow's middle along the menu's edge, from the menu's left edge: under the source's middle, but at least corner + width / 2 in from each end
// (never into the rounded corners); a menu too narrow for that: its middle.
static inline CGFloat MSBDArrowOffset(CGRect menu, CGFloat sourceMidX, CGFloat corner, CGFloat arrowW) {
    CGFloat lo = corner + arrowW / 2.0, hi = menu.size.width - corner - arrowW / 2.0, x = sourceMidX - CGRectGetMinX(menu);
    if (!isfinite(x) || hi < lo) return menu.size.width / 2.0;
    return fmax(lo, fmin(x, hi));
}

// The same along a side edge, from the menu's top edge: level with the source's middle (the Dock at a screen side).
static inline CGFloat MSBDArrowOffsetY(CGRect menu, CGFloat sourceMidY, CGFloat corner, CGFloat arrowW) {
    CGFloat lo = corner + arrowW / 2.0, hi = menu.size.height - corner - arrowW / 2.0, y = sourceMidY - CGRectGetMinY(menu);
    if (!isfinite(y) || hi < lo) return menu.size.height / 2.0;
    return fmax(lo, fmin(y, hi));
}

// A panel with a side arrow laid out again at another height, its bottom at `bottom` (the Downloads stack's panel beside a side Dock: a search grows it upwards,
// the on-screen keyboard lifts it): the arrow stays level with its source -- its middle at the source's middle, never into the rounded corners
// (MSBDArrowOffsetY against the new frame) --, and the point the panel pops up from and goes back into stays at the source's level (its anchor along the
// height, kept inside the panel). Kept at its share of the old height, the arrow left the stack as the panel grew (code review 1.8.2, 7). panel: its frame
// before (its x and width are kept). Returns the new frame; *anchorY: the anchor's share of the new height; *arrowMidY: the arrow's middle.
static inline CGRect MSBDArrowSidePanelRelayout(CGRect panel, CGFloat height, CGFloat bottom, CGFloat sourceMidY, CGFloat corner, CGFloat arrowW, CGFloat *anchorY, CGFloat *arrowMidY) {
    CGRect f = CGRectMake(panel.origin.x, bottom - height, panel.size.width, height);
    if (anchorY) *anchorY = height > 0.0 && isfinite(sourceMidY) ? fmax(0.0, fmin(1.0, (sourceMidY - CGRectGetMinY(f)) / height)) : 1.0;
    if (arrowMidY) *arrowMidY = CGRectGetMinY(f) + MSBDArrowOffsetY(f, sourceMidY, corner, arrowW);
    return f;
}

// The arrow's outline in its own view, which is arrowW wide and arrowH + overlap tall and sits on the menu's edge with `overlap` points over the menu
// (they cover the edge's own outline there, so menu and arrow read as one shape): down -- the band at the top, the tip at the bottom middle; up --
// mirrored. The sides leave the edge with rounded shoulders and meet in a rounded tip. Returns a new path (the caller releases it); stroke: only
// the two sides and the tip (for a border drawn like the menu's; the band's edges are inside the menu's own).
// (right and left: the same arrow turned, in a view arrowH + overlap wide and arrowW tall, the band on the menu's side)
static inline CGPathRef MSBDArrowPathCreate(CGFloat arrowW, CGFloat arrowH, CGFloat overlap, int dir, bool strokeOnly) {
    if (dir == MSBDArrowRight || dir == MSBDArrowLeft) {
        CGPathRef down = MSBDArrowPathCreate(arrowW, arrowH, overlap, MSBDArrowDown, strokeOnly);
        CGAffineTransform t = dir == MSBDArrowRight ? CGAffineTransformMake(0, 1, 1, 0, 0, 0) : CGAffineTransformMake(0, 1, -1, 0, fmax(0.0, overlap) + arrowH, 0);
        CGPathRef turned = CGPathCreateCopyByTransformingPath(down, &t);
        CGPathRelease(down);
        return turned;
    }
    CGMutablePathRef p = CGPathCreateMutable();
    if (!(arrowW > 0) || !(arrowH > 0) || (dir != MSBDArrowDown && dir != MSBDArrowUp)) return p;
    CGFloat s = fmin(kMSBDArrowShoulder, arrowW / 4.0), o = fmax(0.0, overlap), r = kMSBDArrowTipRadius;
    // (drawn pointing down from the edge at y = o; flipped for up. The sides meet below the tip by what its rounding takes off -- r / sin(half the
    //  tip's angle) - r --, so the rounded tip itself reaches arrowH)
    CGFloat edge = o, H = o + arrowH, d = arrowH;
    for (int i = 0; i < 12; i++) { CGFloat half = atan((arrowW / 2.0 - s) / d); d = arrowH + r / sin(half) - r; }
    #define MSBD_AY(v) (dir == MSBDArrowDown ? (v) : H - (v))
    CGPoint tip = CGPointMake(arrowW / 2.0, MSBD_AY(o + d));
    if (!strokeOnly) { CGPathMoveToPoint(p, NULL, 0, MSBD_AY(0)); CGPathAddLineToPoint(p, NULL, 0, MSBD_AY(edge)); }
    else CGPathMoveToPoint(p, NULL, 0, MSBD_AY(edge));
    CGPathAddArcToPoint(p, NULL, s, MSBD_AY(edge), tip.x, tip.y, s);                        // (the left shoulder)
    CGPathAddArcToPoint(p, NULL, tip.x, tip.y, arrowW - s, MSBD_AY(edge), r);                   // (the tip)
    CGPathAddArcToPoint(p, NULL, arrowW - s, MSBD_AY(edge), arrowW, MSBD_AY(edge), s);        // (the right shoulder)
    CGPathAddLineToPoint(p, NULL, arrowW, MSBD_AY(edge));
    if (!strokeOnly) { CGPathAddLineToPoint(p, NULL, arrowW, MSBD_AY(0)); CGPathCloseSubpath(p); }
    #undef MSBD_AY
    return p;
}
#endif
