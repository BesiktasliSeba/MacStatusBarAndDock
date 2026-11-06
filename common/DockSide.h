// DockSide.h -- Settings > Dock > Position (1.8.2, KT 5 Nov; plans/release-1.8.2.md): the Dock on the screen's left or right in landscape; portrait keeps
// it at the bottom. Bottom is the default and nothing here runs for it. Plain C on CoreGraphics, so the Mac test (tools/test-dockside.c) runs this
// very code; dock/Dock.x and statusbar/StatusBar.x use it.
//  - The Dock itself: Apple's, laid out as ever at the "bottom" of the one view that holds it, and that view turned so its bottom is the screen's side
//    (MSBDDockSideHostTransform; Dock.x says how).
//  - The desktop: one area for every engine and layout (StatusBar.x DMUsableArea): no Dock at the bottom, the side strip the Dock takes kept out.
//  - A window dropped under the Dock is pulled out at the drop on every engine, as Stage Manager's own area does (MSBDDockSideKeepOut).
//  - The pointer: the Dock comes out over a full-screen app when the pointer reaches its side (MSBDDockPointerStep; Dock.x says why from its place).
#ifndef MSBD_DOCK_SIDE_H
#define MSBD_DOCK_SIDE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

#define kMSBDDockPositionKey "dockPosition"   // (com.besiktasliseba.dockmagnification: "left" or "right"; anything else, or never set: the bottom)
enum { MSBDDockBottom = 0, MSBDDockLeft = 1, MSBDDockRight = 2 };

// The stored position.
static inline int MSBDDockPositionFromString(const char *s) {
    if (!s) return MSBDDockBottom;
    if (!strcmp(s, "left")) return MSBDDockLeft;
    if (!strcmp(s, "right")) return MSBDDockRight;
    return MSBDDockBottom;
}
// The side the Dock stands on for a screen of this size: Left and Right in landscape only, the bottom (0) in portrait.
static inline int MSBDDockSideFor(int position, double width, double height) {
    if (position != MSBDDockLeft && position != MSBDDockRight) return MSBDDockBottom;
    return width > height ? position : MSBDDockBottom;
}
// A Position change moved the Dock on a screen of this size: the side it stands on there changed. In portrait it stays at the bottom whatever is chosen, so a
// change made there moves no window (code review 1.8.2, 5); a turn to landscape later fits them to the side, as a turn does.
static inline bool MSBDDockSideMoved(int oldPosition, int newPosition, double width, double height) {
    return MSBDDockSideFor(oldPosition, width, height) != MSBDDockSideFor(newPosition, width, height);
}

// ---- the Dock's one view, turned ----
// In its local space the view holds the Dock at its bottom, its local x along the Dock. Left: a rotation; the view's bottom is the screen's left edge and
// its x runs down the screen. Right: a mirrored rotation, so its x still runs down the screen (Finder on top, the end group at the bottom on both sides)
// and its bottom is the screen's right edge. About the view's centre, the screen's centre. The bottom: the identity.
static inline CGAffineTransform MSBDDockSideHostTransform(int side) {
    if (side == MSBDDockLeft) return CGAffineTransformMake(0, 1, -1, 0, 0, 0);
    if (side == MSBDDockRight) return CGAffineTransformMake(0, 1, 1, 0, 0, 0);
    return CGAffineTransformIdentity;
}
// The other way, for what stands upright in the turned view: each icon's content (the same matrix for the mirror, the reverse rotation for Left).
static inline CGAffineTransform MSBDDockSideIconTransform(int side) {
    if (side == MSBDDockLeft) return CGAffineTransformMake(0, -1, 1, 0, 0, 0);
    if (side == MSBDDockRight) return CGAffineTransformMake(0, 1, 1, 0, 0, 0);
    return CGAffineTransformIdentity;
}
// That turn is ours alone. The icon's layer value may be another tweak's (Atria lays its icon scale there, 0.819 on KT's M1), so the turn goes on top of what is
// under it, which is kept, and given back exactly when the turn goes; an icon never turned is never written. Before, once a side had been used, every icon's
// layout wrote the identity there and Atria's Home Screen icons showed 1.22 times too big until Atria laid them out again (1.8.2 engines check, M1).
// turned: we turned it (our record is there); still: our turn is still what it has (else its owner set another value since); side: the side it is to have.
// Nothing: write nothing. Apply: set what is under it, then the turn. GiveBack: set the kept value; the record goes. Forget: the record goes, nothing written.
enum { MSBDIconTurnNothing = 0, MSBDIconTurnApply = 1, MSBDIconTurnGiveBack = 2, MSBDIconTurnForget = 3 };
static inline int MSBDDockSideIconTurnStep(bool turned, bool still, int side) {
    if (side == MSBDDockLeft || side == MSBDDockRight) return MSBDIconTurnApply;
    if (!turned) return MSBDIconTurnNothing;
    return still ? MSBDIconTurnGiveBack : MSBDIconTurnForget;
}
// What lies under a turn applied: the kept value while our turn is still there (never a turn on a turn), else what the layer has now (its owner's newest).
static inline bool MSBDDockSideIconTurnUnderKept(bool turned, bool still) { return turned && still; }

// ---- how long the Dock may be: kept off the menu bar ----
#define kMSBDDockSideEndMargin 6.0   // (between the Dock's ends and the menu bar / the screen's bottom edge)
// The length the Dock may take along the screen's height, the bar's height kept free.
static inline double MSBDDockSideLength(double screenHeight, double bar) { return screenHeight - fmax(0.0, bar) - 2.0 * kMSBDDockSideEndMargin; }
// Where the platter starts along its local x (down the screen): in the middle of the room under the bar.
static inline double MSBDDockSidePlatterX(double screenHeight, double bar, double platterLength) {
    double b = fmax(0.0, bar);
    return b + (screenHeight - b - platterLength) / 2.0;
}

// ---- the strip and the desktop ----
#define kMSBDDockSideGap 2.0   // (between the desktop and the Dock: what the bottom line keeps, DMUsableArea's gapToDock)
// How far the Dock reaches into the screen from its side, read from the platter as drawn on the screen; -1 when that is no Dock lying at this side
// (a Dock away, or still the other shape's: too long or short, or not on the screen; or standing at the other side, nearer the other edge). At a
// Position change from one side to the other the Dock part moves the Dock in its own answer to the change, and ours reads the windows' layouts against
// the old side; nothing orders the two answers. Where the Dock part's came first, the Dock already at the right was taken for a 1019.7 pt Left strip,
// the old desktop 200 pt wide past the screen's right edge, and no window was in a layout: Stage Manager's left half stayed at x 57 at Right (regression
// 1.8.2.1 F1, iPad 2 16.7.7, 4 of 4; the 17.5.1 read the Dock before it moved).
static inline double MSBDDockSideStripOf(CGRect platter, CGSize screen, int side) {
    if ((side != MSBDDockLeft && side != MSBDDockRight) || CGRectIsNull(platter) || CGRectIsEmpty(platter)) return -1.0;
    if (platter.size.height <= platter.size.width || platter.size.width > screen.width * 0.25) return -1.0;
    double toLeft = CGRectGetMinX(platter), toRight = screen.width - CGRectGetMaxX(platter);   // (how far it stands from each side edge)
    if (side == MSBDDockRight ? !(toRight < toLeft) : !(toLeft < toRight)) return -1.0;
    if (side == MSBDDockRight) { double s = screen.width - CGRectGetMinX(platter); return s > 0.5 && CGRectGetMaxX(platter) <= screen.width + 0.5 ? s : -1.0; }
    double s = CGRectGetMaxX(platter);
    return s > 0.5 && CGRectGetMinX(platter) >= -0.5 ? s : -1.0;
}
// The strip as the Dock's thickness changes by itself (1.8.2.2, 17.5 F3 / A12Z F5): its recents growing or going, Apple's App Library icon switched, a Handoff tile.
// Before, the desktop kept the thickest strip seen until our own next Position or Dock setting: a thinned Dock left 17.6 pt of the desktop unused (17.5, the recents
// 4 -> 10), and a Dock thickened that way had windows under it until their next move (A12Z: a Fill window 1.2 pt under it after Show App Library in Dock went off).
// Now the strip is the Dock's real thickness, taken once it is seen again unchanged 0.3 s later; meanwhile the thicker of the two counts, so no window is placed under
// the Dock. While the Dock is away (over a full-screen app, at the other side for a moment, not laid out yet) the last thickness taken stands: the only memory left.
// settled: the thickness taken (<= 0: none since the Dock last changed by our own setting or position); cand, candAt: a new thickness seen and when.
// placed: with none taken, the strip the windows were last placed against (the caller's: SpringBoard's figure while the Dock was away at a Position change), <= 0
// for none. The first thickness taken then is a change from it, followed as any other (code review 1.8.2.2, second pass 4: windows placed against the figure
// while a full-screen app hid the Dock stayed short of it or under it once the Dock was measured).
typedef struct { double settled, cand, candAt, placed; } MSBDDockStripState;
enum { MSBDStripSame = 0, MSBDStripFirst = 1, MSBDStripCandidate = 2, MSBDStripChanged = 3 };
#define kMSBDDockStripSettle 0.3   // (seen again unchanged this much later)
#define kMSBDDockStripSame 0.25    // (within this: the same thickness)
// One look. measured: the strip as drawn now (<= 0: no Dock lying at this side). Returns the strip to use. *event: MSBDStripChanged when a new thickness was just
// taken over another one (the windows follow it; *was: the one before), MSBDStripFirst when the first was taken, MSBDStripCandidate when a different one is first
// seen (the windows' layouts are the old desktop's until it is taken), else MSBDStripSame. fallback: with nothing taken and no Dock to measure.
static inline double MSBDDockSideStripStep(MSBDDockStripState *st, double measured, double now, double fallback, int *event, double *was) {
    if (event) *event = MSBDStripSame;
    if (!st) return measured > 0 ? measured : fallback;
    if (!(measured > 0) || !isfinite(measured)) return st->settled > 0 ? st->settled : fallback;
    bool sameAsCand = fabs(st->cand - measured) <= kMSBDDockStripSame;
    if (st->settled > 0 && fabs(measured - st->settled) <= kMSBDDockStripSame) { st->cand = -1.0; return st->settled; }
    double base = st->settled > 0 ? st->settled : (st->placed > 0 && fabs(measured - st->placed) > kMSBDDockStripSame ? st->placed : 0.0);   // (what the windows stand against)
    if (sameAsCand && now - st->candAt >= kMSBDDockStripSettle - 1e-9) {
        st->settled = measured; st->cand = -1.0; st->placed = 0.0;
        if (event) *event = base > 0 ? MSBDStripChanged : MSBDStripFirst;
        if (was) *was = base;
        return measured;
    }
    if (!sameAsCand) { st->cand = measured; st->candAt = now; if (event && base > 0) *event = MSBDStripCandidate; }
    return base > 0 ? fmax(measured, base) : measured;
}
// The zoom of an app going Home into its side Dock icon on 15-17 (dock/Dock.x, the switcher's match-move response; code review 1.8.2.2, second pass 1 and 7). The
// switcher starts a match-move of the zoom to the icon's own layer (active) and ends it (not active). Into a Dock at a side it is left out -- that layer is inside
// the turned Dock -- and so is the end of one left out. The apps left out are kept as a set, and a new start always begins its app's cycle anew: a zoom cut short
// (the app tapped again mid-zoom) may never send its end, and its record must not swallow a later end of that app, at a side or at the bottom.
// active: a start; recorded: this app is in the set; intoSideDock: the zoom goes into the Dock (MSBDZoomLocationIsDock), the Dock stands at a side, on the main
// screen's switcher. Returns 1 to leave the response out (0: SpringBoard's own). *setOp: +1 add the app to the set, -1 take it out, 0 nothing.
static inline int MSBDZoomLeaveOut(bool active, bool recorded, bool intoSideDock, int *setOp) {
    if (setOp) *setOp = 0;
    if (!active) { if (recorded && setOp) *setOp = -1; return recorded ? 1 : 0; }   // (an end: only the one of an app left out)
    if (intoSideDock) { if (!recorded && setOp) *setOp = 1; return 1; }
    if (recorded && setOp) *setOp = -1;   // (a start that is SpringBoard's own: a record left from a zoom cut short goes)
    return 0;
}
// Whether the switcher's icon location for the zoom is a Dock's (SBIconLocationFloatingDock, SBIconLocationFloatingDockSuggestions: its recents), not the Home
// Screen's pages, a folder or the App Library.
static inline bool MSBDZoomLocationIsDock(const char *location) { return location && strstr(location, "Dock") != NULL; }
// The desktop of a screen with the Dock at a side: from `top` down to the screen's bottom edge, the strip and the gap kept out at the Dock's side.
static inline CGRect MSBDDockSideDesktop(CGSize screen, int side, double strip, double top) {
    double keep = fmax(0.0, strip) + kMSBDDockSideGap;
    return CGRectMake(side == MSBDDockLeft ? keep : 0.0, top, fmax(200.0, screen.width - keep), fmax(200.0, screen.height - top));
}

// ---- the Home Screen ----
// With the Dock at a side the Home Screen keeps out of it (KT 5 Nov): the room the Dock takes from its side comes out of the free space beside the icons, in the
// share each side has. Each page's icon list is moved, its size kept, so whatever lays the icons out inside it (iPadOS, Atria, any layout tweak) keeps its shape:
// a layout along an edge stays along it (KT's two Atria columns at the left move over by the Dock when it is at the left, and stay put when it is at the right),
// a centred one stays centred between the Dock and the other edge. Only icons that don't fit beside the Dock at their size are laid out again in the room left
// (the list as wide as that room: the layout fits itself in it). The rows stay where they are at the bottom (the Home Screen asks the Dock's height as at the bottom).
#define kMSBDDockSideHomeKeep 6.0   // (the least free space a moved layout keeps at each side; with less it is laid out in the room instead)
// page: the list's frame as iPadOS gives it; room: how far the Dock reaches into the screen from its side, at rest (its gap and its platter: a magnified Dock grows
// over the icons for a moment, as on a Mac); freeLeft, freeRight: the layout's free space left and right of its icons on the screen (its insets as they face it).
static inline CGRect MSBDDockSideHomeListFrame(CGRect page, int side, double room, double freeLeft, double freeRight) {
    if ((side != MSBDDockLeft && side != MSBDDockRight) || !(room > 0.0) || !isfinite(room) || CGRectIsNull(page) || CGRectIsEmpty(page)) return page;
    double fl = isfinite(freeLeft) ? fmax(0.0, freeLeft) : 0.0, fr = isfinite(freeRight) ? fmax(0.0, freeRight) : 0.0, free = fl + fr;
    if (free - room < 2.0 * kMSBDDockSideHomeKeep) {   // (no room beside the Dock for the icons at their size)
        CGRect f = page;
        f.size.width = fmax(1.0, f.size.width - room);
        if (side == MSBDDockLeft) f.origin.x += room;
        return f;
    }
    return CGRectOffset(page, side == MSBDDockLeft ? room * fr / free : -room * fl / free, 0);
}
// The layout's free space on the screen's left and right from its insets: as they are, or swapped where the list lays out right to left, mirrored.
static inline void MSBDDockSideHomeFree(double insetLeft, double insetRight, bool rightToLeft, double *freeLeft, double *freeRight) {
    if (freeLeft) *freeLeft = rightToLeft ? insetRight : insetLeft;
    if (freeRight) *freeRight = rightToLeft ? insetLeft : insetRight;
}
// Does a frame on the screen reach under the Dock at rest (the safety check after a Home Screen layout)?
static inline bool MSBDDockSideHomeUnder(CGRect r, double screenWidth, int side, double room) {
    if ((side != MSBDDockLeft && side != MSBDDockRight) || !(room > 0.0) || CGRectIsNull(r) || CGRectIsEmpty(r)) return false;
    return side == MSBDDockLeft ? CGRectGetMinX(r) < room - 0.25 : CGRectGetMaxX(r) > screenWidth - room + 0.25;
}

// ---- the clock's Today panel, hung from the menu bar ----
// A panel stays open while it is used, as a window does, so with the Dock at a side it keeps out of the Dock as it keeps above a Dock at the bottom: its edge on
// the Dock's side 10 pt inside the desktop (StatusBar.x DMUsableArea, which ends 2 pt short of the Dock), as its bottom stays 10 pt above the desktop's end there.
// Everywhere else it keeps 6 pt from the screen's edges, as ever: the bottom and portrait are as before. (Menus are not held to this: they cross a side Dock
// for a moment, as a Mac's menus cross its Dock.)
#define kMSBDPanelScreenMargin 6.0
#define kMSBDPanelDockMargin 10.0
typedef struct { double lo, hi; } MSBDPanelSpan;
// The span across the screen what hangs from the menu bar may use, `margin` from the screen's edges. area: the desktop (only its edge on the Dock's side counts).
static inline MSBDPanelSpan MSBDDockSideSpanWithin(double screenWidth, int side, CGRect area, double margin) {
    MSBDPanelSpan s = { margin, screenWidth - margin };
    if (CGRectIsNull(area) || CGRectIsEmpty(area)) return s;
    if (side == MSBDDockLeft) s.lo = fmax(s.lo, CGRectGetMinX(area) + kMSBDPanelDockMargin);
    if (side == MSBDDockRight) s.hi = fmin(s.hi, CGRectGetMaxX(area) - kMSBDPanelDockMargin);
    return s;
}
// The span a panel may use (6 pt from the screen's edges).
static inline MSBDPanelSpan MSBDDockSidePanelSpan(double screenWidth, int side, CGRect area) { return MSBDDockSideSpanWithin(screenWidth, side, area, kMSBDPanelScreenMargin); }
// Where a panel of this width hangs from its title (anchor: the title's left and right ends): its right edge 4 pt past the title's right end, or with a
// right-to-left bar (the clock at the bar's left end) its left edge 4 pt before the title's left end; inside the span, its leading edge winning.
static inline double MSBDPanelHungX(double anchorMinX, double anchorMaxX, double width, MSBDPanelSpan s, bool rtl) {
    double x = rtl ? fmin(anchorMinX - 4.0, s.hi - width) : fmin(anchorMaxX + 4.0, s.hi) - width;
    return fmax(s.lo, x);
}

// ---- the Mac-style notification banners ----
// A banner stays up a while, as the Today panel does (they are the Notification Center's), so with the Dock at a side it keeps out of the Dock the same way: its
// edge on the Dock's side 10 pt inside the desktop. Everywhere else 10 pt from the screen's edge, as ever: the bottom and portrait are as before. (Before, a
// banner lay over the top of a Right Dock.) Its x for a banner `width` wide at most (*w: the width it gets) at the screen's right end, or with a right-to-left
// layout at its left end.
#define kMSBDBannerScreenMargin 10.0
static inline double MSBDBannerX(double screenWidth, int side, CGRect area, double width, bool rtl, double *w) {
    MSBDPanelSpan s = MSBDDockSideSpanWithin(screenWidth, side, area, kMSBDBannerScreenMargin);
    double bw = fmax(0.0, fmin(width, s.hi - s.lo));
    if (w) *w = bw;
    return rtl ? s.lo : s.hi - bw;
}

// ---- Fit to Window's question ----
// Its title over the seam between its two panels, which stand in the desktop beside the Dock (1.8.2.2, M1 F2 / A12Z F7): centred on the screen it stood 26 to 34 pt
// off the seam, over one panel. The title's x for one `width` wide over `seam`, kept `margin` inside the screen (nonsense: centred on the screen, as before).
static inline double MSBDDockSideTitleX(double seam, double width, double screenWidth, double margin) {
    if (!isfinite(seam) || !isfinite(width) || !isfinite(screenWidth) || !isfinite(margin)) return (screenWidth - width) / 2.0;
    return fmax(margin, fmin(seam - width / 2.0, screenWidth - margin - width));
}

// ---- a window let go ----
enum { MSBDDockKeepMove = 0, MSBDDockKeepLeft = 1, MSBDDockKeepRight = 2, MSBDDockKeepBottom = 8 };   // (the first three as WindowSnap.h's sides)
// Where a window let go ends when the Dock is at a side: inside the desktop. how: 0 a move: the same size, moved in (too big: as big as the desktop, its
// left and top edges win, the lights stay reachable); else a resize's dragged sides: those stop at the desktop's edge and the window keeps its other
// sides, then the same rule for what is still outside.
static inline CGRect MSBDDockSideKeepOut(CGRect f, CGRect area, unsigned how) {
    if (CGRectIsNull(f) || CGRectIsEmpty(f) || CGRectIsNull(area) || CGRectIsEmpty(area)) return f;
    double x0 = CGRectGetMinX(f), x1 = CGRectGetMaxX(f), y0 = CGRectGetMinY(f), y1 = CGRectGetMaxY(f);
    if (how & MSBDDockKeepLeft) x0 = fmax(x0, CGRectGetMinX(area));
    if (how & MSBDDockKeepRight) x1 = fmin(x1, CGRectGetMaxX(area));
    if (how & MSBDDockKeepBottom) y1 = fmin(y1, CGRectGetMaxY(area));
    double w = fmin(x1 - x0, area.size.width), h = fmin(y1 - y0, area.size.height);
    double x = fmax(CGRectGetMinX(area), fmin(x0, CGRectGetMaxX(area) - w));
    double y = fmax(CGRectGetMinY(area), fmin(y0, CGRectGetMaxY(area) - h));
    return CGRectMake(x, y, w, h);
}

// ---- touches ----
// A Dock icon's view is bigger than its picture when the Dock is small (76 pt views 37 pt apart on the iPad 2's side Dock), and a neighbour's view lies over
// the middle of the icon. An icon's touch area along the Dock (its local x) is its share of the row: half a step to either side of its middle.
static inline bool MSBDDockIconTakesTouch(CGPoint p, CGRect bounds, double step) {
    if (!(step > 0)) return true;
    return fabs(p.x - CGRectGetMidX(bounds)) <= step / 2.0 + 0.25;
}

// ---- the running dot ----
// An icon's content stands upright in its view, so in the view's space the dot goes to the screen's edge side of the picture (right or left of its
// middle), as far from the middle as it is below it with the Dock at the bottom. belowTop: its top with the Dock at the bottom.
static inline CGRect MSBDDockSideDotFrame(int side, double width, double height, double belowTop, double d) {
    double off = belowTop + d / 2.0 - height / 2.0, cx = width / 2.0 + (side == MSBDDockRight ? off : -off);
    return CGRectMake(cx - d / 2.0, (height - d) / 2.0, d, d);
}

// ---- the pointer ----
// backboardd's pointer position (the display's native portrait points) on the screen as the user sees it. orientation: UIInterfaceOrientation.
static inline CGPoint MSBDDockPointerOnScreen(CGPoint n, long orientation, CGSize native) {
    switch (orientation) {
        case 3: return CGPointMake(n.y, native.width - n.x);
        case 4: return CGPointMake(native.height - n.y, n.x);
        case 2: return CGPointMake(native.width - n.x, native.height - n.y);
        default: return n;
    }
}
#define kMSBDDockPointerEdge 1.5        // (the pointer is at the side: this close to the screen's edge; it stops at the edge itself)
#define kMSBDDockPointerAwayShare 1.5   // (it has left: more than this many Dock heights from the edge, Apple's own rule at the bottom)
#define kMSBDDockPointerTopGuard 44.0   // (the top corner is Control Center's and Notification Center's)
enum { MSBDDockPointerNothing = 0, MSBDDockPointerComeOut = 1, MSBDDockPointerGoAway = 2 };
typedef struct { bool atEdge; bool byPointer; double outAt; } MSBDDockPointerState;
// One look at the pointer. presented: the Dock is out. mayCome: Apple's own conditions for the pointer's reveal hold (no Lock Screen, Control Center, Siri,
// floating switcher...). stay: something holds the Dock out (a menu, the Downloads panel). The Dock comes out when the pointer ARRIVES at the side (not
// when it was left there and an app came up) and goes when it has left, only if it was the pointer that brought it (a finger's swipe stays Apple's).
// sameApp: the full-screen app the pointer brought it out over is still the one in front (asked while it is the pointer's Dock). Another one in front -- the
// Home Screen (Cmd-H), an app opened from the Dock as a window, the desktop -- and the Dock is no longer the pointer's: SpringBoard keeps it out there, and
// the pointer leaving never sends it away from the Home Screen (code review 1.8.2, 2; Apple's own hover dismissal is tied to its full-screen app too).
static inline int MSBDDockPointerStep(MSBDDockPointerState *st, int side, CGPoint p, CGSize screen, bool presented, bool mayCome, bool stay, double dockHeight, double now, bool sameApp) {
    if (!st) return MSBDDockPointerNothing;
    bool known = (side == MSBDDockLeft || side == MSBDDockRight) && isfinite(p.x) && isfinite(p.y);
    bool at = known && p.y >= kMSBDDockPointerTopGuard && (side == MSBDDockRight ? p.x >= screen.width - kMSBDDockPointerEdge : p.x <= kMSBDDockPointerEdge);
    bool arrived = at && !st->atEdge;
    st->atEdge = at;
    if (!known) { st->byPointer = false; return MSBDDockPointerNothing; }
    if (!presented) {
        if (st->byPointer && now - st->outAt > 1.0) st->byPointer = false;   // (it went some other way; a moment's grace while it comes out)
        if (arrived && mayCome) { st->byPointer = true; st->outAt = now; return MSBDDockPointerComeOut; }
        return MSBDDockPointerNothing;
    }
    if (st->byPointer && !sameApp) st->byPointer = false;
    if (!st->byPointer || stay) return MSBDDockPointerNothing;
    double away = kMSBDDockPointerAwayShare * fmax(dockHeight, 1.0);
    if (side == MSBDDockRight ? p.x < screen.width - away : p.x > away) { st->byPointer = false; return MSBDDockPointerGoAway; }
    return MSBDDockPointerNothing;
}
// The next look, in seconds: often near the Dock's side, seldom elsewhere, seldom while the Dock is simply there.
static inline double MSBDDockPointerInterval(int side, CGPoint p, CGSize screen, bool presented, bool byPointer) {
    if (presented && !byPointer) return 0.5;
    double dist = side == MSBDDockRight ? screen.width - p.x : p.x;
    return isfinite(dist) && dist < 200.0 ? 0.05 : 0.25;
}
#endif
