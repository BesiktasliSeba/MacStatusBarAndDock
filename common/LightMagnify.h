// LightMagnify.h -- Magnify Traffic Lights (1.8.6, KT 10 Nov): the layout and the pick rule of the lights grown under a finger. Plain C, Mac-tested
// (tools/test-lightmagnify.sh); statusbar/LightMagnify.h draws it.
//
// A finger down on a window's red / yellow / green grows the lights into a small frosted pill with their symbols: the light under the finger the
// biggest, its neighbours less (the Dock's swell). The pill grows from the lights' own top-left (the window's corner side) to the right and down,
// never past the box it is kept in (the window or the bar it sits in): it is shifted inside that box, and made smaller if it can't fit at full size.
// A lift on a light picks it; a lift away from the pill picks nothing.
// A trackpad's or mouse's pointer (1.8.8) grows the lights where they are, less than a finger: the one under it 1.4 times its size, its neighbours a
// little, no pill (the rule and its state at the end of this file).
#pragma once
#include <math.h>
#include "DockHover.h"   // (1.8.8: the pointer resting on the lights is held through UIKit's cancel by the Dock's own rules, MSBDHoverHoldsAfter / Step)
#include "PointerFade.h"  // (1.8.8, D48: ... and that hold ends when the pointer fades, as pointeruid says: MSBDLightPtrFade)

#define kMSBDLightMagMaxDots   3
#define kMSBDLightMagGrow      1.50   // every light at least this times its size while the pill is out
#define kMSBDLightMagSwell     0.50   // ... the one under the finger this much more (2.0 times), its neighbours less
#define kMSBDLightMagGapK      0.72   // gap between two lights, times the base size (8.6 pt at 12 pt dots)
#define kMSBDLightMagPadK      0.40   // the pill's padding round the lights, times the base size
#define kMSBDLightMagSlopK     0.90   // how far off the pill a lift still counts as on it, times the base size

typedef struct {
    int n;                                  // lights in the pill (2 when the green one is hidden)
    double cx[kMSBDLightMagMaxDots];        // each light's centre (x), in the box's coordinates
    double size[kMSBDLightMagMaxDots];      // each light's diameter
    double cy;                              // the lights' common centre (y)
    double pillX, pillY, pillW, pillH;      // the pill
    double base;                            // the base size the layout was made with (after a fit)
} MSBDLightMag;

// The swell of one light: 1 for the light under the finger, falling off with the distance in light pitches (a Gaussian, as the Dock's).
static inline double MSBDLightMagSwellAt(double distance, double pitch) {
    if (!(pitch > 0)) return 0;
    double t = distance / pitch;
    return exp(-(t * t));
}

static inline MSBDLightMag MSBDLightMagLayoutRaw(int n, double anchorX, double anchorY, double base, double fingerX, int hasFinger) {
    MSBDLightMag L; L.n = n < 1 ? 1 : (n > kMSBDLightMagMaxDots ? kMSBDLightMagMaxDots : n); L.base = base;
    double gap = base * kMSBDLightMagGapK, pad = base * kMSBDLightMagPadK;
    L.pillX = anchorX - pad; L.pillY = anchorY - pad;
    // (where each light would be at an even size: the finger's distance to it decides its swell)
    double even = base * (kMSBDLightMagGrow + kMSBDLightMagSwell * 0.5), pitch = even + gap, nominal[kMSBDLightMagMaxDots];
    for (int i = 0; i < L.n; i++) nominal[i] = L.pillX + pad + even / 2.0 + i * pitch;
    double cursor = L.pillX + pad, maxS = 0;
    for (int i = 0; i < L.n; i++) {
        double m = kMSBDLightMagGrow + (hasFinger ? kMSBDLightMagSwell * MSBDLightMagSwellAt(fabs(fingerX - nominal[i]), pitch) : kMSBDLightMagSwell * 0.3);
        L.size[i] = base * m;
        L.cx[i] = cursor + L.size[i] / 2.0;
        cursor += L.size[i] + gap;
        if (L.size[i] > maxS) maxS = L.size[i];
    }
    L.pillW = (cursor - gap + pad) - L.pillX;
    L.pillH = maxS + 2.0 * pad;
    L.cy = L.pillY + pad + maxS / 2.0;
    return L;
}

// The layout for n lights whose first one's top-left is (anchorX, anchorY) at base size `base`, the finger at fingerX (hasFinger 0: none yet),
// kept inside the box (minX, minY)-(maxX, maxY). Too big for the box: the whole pill is made smaller (never below the lights' own size: then it is
// only shifted and may be clipped by the box); then it is shifted inside the box.
static inline MSBDLightMag MSBDLightMagLayout(int n, double anchorX, double anchorY, double base, double fingerX, int hasFinger,
                                              double minX, double minY, double maxX, double maxY) {
    MSBDLightMag L = MSBDLightMagLayoutRaw(n, anchorX, anchorY, base, fingerX, hasFinger);
    double availW = maxX - minX, availH = maxY - minY, k = 1.0, pad = base * kMSBDLightMagPadK;
    double smallest = 1.0 / (kMSBDLightMagGrow + kMSBDLightMagSwell);   // (k below this would make the biggest light smaller than it is now)
    // (a smaller pill moves its lights, so the finger's swell changes a little: a few rounds until it fits; the anchor -- the top-left -- stays)
    for (int round = 0; round < 6 && availW > 0 && availH > 0 && (L.pillW > availW + 1e-9 || L.pillH > availH + 1e-9) && k > smallest; round++) {
        k *= fmin(availW / L.pillW, availH / L.pillH) * 0.999;
        if (k < smallest) k = smallest;
        L = MSBDLightMagLayoutRaw(n, anchorX - pad + pad * k, anchorY - pad + pad * k, base * k, fingerX, hasFinger);
    }
    double dx = 0, dy = 0;
    if (L.pillX + L.pillW > maxX) dx = maxX - (L.pillX + L.pillW);
    if (L.pillX + dx < minX) dx = minX - L.pillX;
    if (L.pillY + L.pillH > maxY) dy = maxY - (L.pillY + L.pillH);
    if (L.pillY + dy < minY) dy = minY - L.pillY;
    L.pillX += dx; L.pillY += dy; L.cy += dy;
    for (int i = 0; i < L.n; i++) L.cx[i] += dx;
    return L;
}

// Which light a lift at (px, py) picks: -1 off the pill (with a little slop round it), else the light whose part of the pill it is in (the parts
// split half way between two lights' edges).
static inline int MSBDLightMagPick(MSBDLightMag L, double px, double py) {
    double slop = L.base * kMSBDLightMagSlopK;
    if (px < L.pillX - slop || px > L.pillX + L.pillW + slop || py < L.pillY - slop || py > L.pillY + L.pillH + slop) return -1;
    for (int i = 0; i < L.n - 1; i++) {
        double split = ((L.cx[i] + L.size[i] / 2.0) + (L.cx[i + 1] - L.size[i + 1] / 2.0)) / 2.0;
        if (px < split) return i;
    }
    return L.n - 1;
}

// The pill follows the finger relatively (m05, the M1: a finger held on green and lifted picked yellow, since the grown lights spread to the right):
// at touch down the light under the finger (`first`, by the lights' own places) is drawn the biggest and stands for the finger; a slide moves that
// point by as much as the finger moves. The point for a finger at fingerX: the drawn centre of `first` in the layout made around it (a few rounds).
// Use: offset = MSBDLightMagVirtualX(...) - fingerX at touch down; then the layout and the pick at (finger + offset).
static inline double MSBDLightMagVirtualX(int n, int first, double anchorX, double anchorY, double base, double fingerX,
                                          double minX, double minY, double maxX, double maxY) {
    double vx = fingerX;
    if (first < 0 || first >= n) return vx;
    for (int round = 0; round < 4; round++) {
        MSBDLightMag L = MSBDLightMagLayout(n, anchorX, anchorY, base, vx, 1, minX, minY, maxX, maxY);
        vx = L.cx[first];
    }
    return vx;
}

// ---- the pointer (1.8.8): grown where they are, a little, under a trackpad's or mouse's pointer ----
// KT 19 Nov ("make Traffic light magnification apply to cursor too but less"; design: plans/tl-pointer-magnify.md). No pill: each
// light grows about its own centre, so no button moves or changes its frame, a click is the button's own click as before, and the light drawn
// biggest is the button a click hits. The light under the pointer 1.4 times its size (KT's own number, 10 Nov; below the finger's smallest, 1.5),
// its neighbours by the finger's Gaussian, in light pitches. Only while the pointer is inside a light's own button (visible, enabled): the band
// round them where the symbols already show (the bar's tap and drag, Stage Manager's top resize band, the gaps between MilkyWay4's own buttons)
// grows nothing. Each light stays inside its own button and inside its window (1.5 pt in, the pill's margin), never below its own size.
#define kMSBDLightPtrSwell   0.40   // the light under the pointer 1 + this times its size (the finger: 1.5x every light, 2.0x under it)
#define kMSBDLightPtrMargin  1.5    // pt kept from the window's edge (the pill's margin, statusbar/LightMagnify.h openAt)
#define kMSBDLightPtrCellK   (20.0 / 12.0)   // a light's button against its dot: 20 pt round 12 (kLightCell / kLightDot; the bar's x its scale)
#define kMSBDLightPtrMove    0.005  // a light's size changing by more than this starts a new animation (hover moves come at 120 Hz)
#define kMSBDLightPtrRegrowIn 0.25  // s: a pointer click this soon after the hover's end puts the last sizes back (UIKit's cancel came before the touch)
#define kMSBDLightPtrMarkIn  0.10   // s: the press saw the click's touch at most this long before the button's touch down (the same touch)

// The room from a light's centre to a rect's nearest edge (its button, its window box).
static inline double MSBDLightRoom(double cx, double cy, double minX, double minY, double maxX, double maxY) {
    return fmin(fmin(cx - minX, maxX - cx), fmin(cy - minY, maxY - cy));
}
// One light's size under the pointer, times its own: 1 + kMSBDLightPtrSwell x the Gaussian of its x distance in pitches, capped by its room in its
// button and in its window (cellRoom, boxRoom: MSBDLightRoom), never below 1; anything not a number gives 1.
static inline double MSBDLightPtrScale(double pointerX, double centreX, double size, double pitch, double cellRoom, double boxRoom) {
    if (!(size > 0) || !isfinite(pointerX) || !isfinite(centreX) || !isfinite(cellRoom) || !isfinite(boxRoom)) return 1.0;
    double s = 1.0 + kMSBDLightPtrSwell * MSBDLightMagSwellAt(fabs(pointerX - centreX), pitch);
    double cap = fmin(cellRoom, boxRoom) / (size / 2.0);
    if (!(s <= cap)) s = cap;
    return s >= 1.0 ? s : 1.0;
}
// A set of lights as the pointer sees it, in its container's space: each shown light's centre and size (untransformed), its button, whether it may
// grow (visible, enabled, not greyed); the window box (already kMSBDLightPtrMargin in).
typedef struct {
    int n;
    double cx[kMSBDLightMagMaxDots], cy[kMSBDLightMagMaxDots], size[kMSBDLightMagMaxDots];
    double cellMinX[kMSBDLightMagMaxDots], cellMinY[kMSBDLightMagMaxDots], cellMaxX[kMSBDLightMagMaxDots], cellMaxY[kMSBDLightMagMaxDots];
    int usable[kMSBDLightMagMaxDots];
    double boxMinX, boxMinY, boxMaxX, boxMaxY;
} MSBDLightRow;
// The usable light whose own button holds (px, py), slop pt round it (-1: none). The buttons never overlap; the first found wins.
static inline int MSBDLightPtrButtonAt(const MSBDLightRow *r, double px, double py, double slop) {
    if (!isfinite(px) || !isfinite(py)) return -1;
    for (int i = 0; i < r->n && i < kMSBDLightMagMaxDots; i++)
        if (r->usable[i] && px >= r->cellMinX[i] - slop && px < r->cellMaxX[i] + slop && py >= r->cellMinY[i] - slop && py < r->cellMaxY[i] + slop) return i;
    return -1;
}
// Every light's size with the pointer at (px, py) (out: one per light, 1 = its own): returns the light whose button the pointer is in, or -1 with every
// one at 1. The pitch: the distance between the first two lights' centres (one light: its size x kMSBDLightPtrCellK).
static inline int MSBDLightPtrScales(const MSBDLightRow *r, double px, double py, double *out) {
    int n = r->n < kMSBDLightMagMaxDots ? r->n : kMSBDLightMagMaxDots;
    for (int i = 0; i < n; i++) out[i] = 1.0;
    int under = MSBDLightPtrButtonAt(r, px, py, 0.0);
    if (under < 0) return -1;
    double pitch = n >= 2 ? fabs(r->cx[1] - r->cx[0]) : r->size[0] * kMSBDLightPtrCellK;
    for (int i = 0; i < n; i++) {
        if (!r->usable[i]) { out[i] = 1.0; continue; }
        double cell = MSBDLightRoom(r->cx[i], r->cy[i], r->cellMinX[i], r->cellMinY[i], r->cellMaxX[i], r->cellMaxY[i]);
        double box = MSBDLightRoom(r->cx[i], r->cy[i], r->boxMinX, r->boxMinY, r->boxMaxX, r->boxMaxY);
        out[i] = MSBDLightPtrScale(px, r->cx[i], r->size[i], pitch, cell, box);
    }
    return under;
}

// The pointer's state for one set of lights, and what each event does to it (the views follow the answer: statusbar/LightMagnify.h). Times are
// CACurrentMediaTime()'s; 0 = never.
//  - A click: UIKit cancels the hover when the click's touch starts, and the two reach SpringBoard in either order. The touch first: the button is
//    tracking a pointer's touch when the cancel comes, so the sizes stay for the click. The cancel first: the lights go back, and the click's touch down
//    within kMSBDLightPtrRegrowIn puts the sizes back (kMSBDLightPtrMarkIn: only for the touch the press marked as the pointer's, never a finger's).
//  - A resting pointer (H, the Dock's hold, common/DockHover.h): UIKit also cancels the hover with no touch while the pointer rests (the iPad 2 after
//    0.7 to 1 s, the 17.5 after about 2 s). On the iPad's own screen such a cancel is held while backboardd has the pointer over the lights; a touch
//    anywhere (a finger hides the pointer, a click is the user's) or the pointer gone ends it.
//  - The pointer's fade (D48): over the lights UIKit's cancel with no touch came about 8 s after the last move on every test iPad, as iPadOS hid the
//    pointer, and the hold kept them grown and lit under no pointer until a move or a touch. iPadOS's own hide, as pointeruid says it (PointerFade.h),
//    ends a hold: MSBDLightPtrFade.
//  - -apply's look: a grown set goes back at once when its pointer's last place is no longer on one of its buttons (its window moved under a still
//    pointer), it is hidden, switched off, or nothing hovers or holds it -- never during a click or a live hover.
typedef struct {
    int grown;         // some light of the set above its size, or going there
    int held;          // UIKit's cancel held: backboardd's place keeps the lights
    double restAt;     // when a hover's end (or its hold's) put them back from grown
    double markAt;     // when the press last saw a touch on the set ...
    int markPointer;   // ... and whether it was the pointer's
} MSBDLightPtr;
enum { MSBDLightPtrNothing = 0, MSBDLightPtrRest, MSBDLightPtrRestNow, MSBDLightPtrKeep, MSBDLightPtrHold, MSBDLightPtrRegrow, MSBDLightPtrUnhold };
// The press saw a touch on the set (the pointer's: refused as "not a finger (pointer)").
static inline void MSBDLightPtrMark(MSBDLightPtr *s, int pointer, double now) { s->markAt = now; s->markPointer = pointer != 0; }
// The hover is over the lights again (UIKit's Began or Changed): a hold ends there (1: one did). The sizes are the pointer's (MSBDLightPtrScales).
static inline int MSBDLightPtrHoverOver(MSBDLightPtr *s) { int h = s->held; s->held = 0; return h; }
// A report off the lights with nothing of the pointer's on them (none grown, none held, and the last report not over them: shown), as every move over
// a title bar round them is (Stage Manager's, MilkyWay4's). MSBDLightPtrHoverOff would answer Nothing and change nothing (test T13), so the magnifier
// answers at once and does no work for that move.
static inline int MSBDLightPtrIdle(const MSBDLightPtr *s, int over, int shown) { return !over && !s->grown && !s->held && !shown; }
// SpringBoard's touches matter to a set only while it has something of the pointer's on it: its last report over the lights (shown), a grow or a hold.
// Only there does HoverOff read the touch's time and answer Hold, and TouchBegan answer Unhold (test T14), so the pass-through of -[SpringBoard
// sendEvent:] notes touches only then (statusbar/LightMagnify.h, gLightPtrLive). Off the lights it is MSBDLightPtrIdle the other way round.
static inline int MSBDLightPtrWantsTouches(const MSBDLightPtr *s, int shown) { return shown || s->grown || s->held; }
// The hover is not over them: UIKit's state (1 Began, 2 Changed: off the lights; 3 Ended: the pointer left; 4 Cancelled), a pointer click in progress
// on the set, something shown (the symbols or a grow), the lights on the iPad's own screen, the finger's pill out, now and SpringBoard's last touch.
// Rest: back to their size (animated; a hover's end notes when). Keep: the sizes stay for the click. Hold: UIKit's cancel held.
static inline int MSBDLightPtrHoverOff(MSBDLightPtr *s, long state, int clicking, int shown, int ownScreen, int pillOut, double now, double touchAt) {
    s->held = 0;   // (UIKit reports again: any hold is over)
    if (pillOut) { int g = s->grown; s->grown = 0; return g ? MSBDLightPtrRest : MSBDLightPtrNothing; }
    if (clicking && s->grown) return MSBDLightPtrKeep;
    if (ownScreen && MSBDHoverHoldsAfter(state, shown != 0, touchAt > 0 ? now - touchAt : -1.0)) {
        s->held = 1;
        return MSBDLightPtrHold;
    }
    if (!s->grown) return MSBDLightPtrNothing;
    s->grown = 0;
    if (state == 3 || state == 4) s->restAt = now;
    return MSBDLightPtrRest;
}
// A touch SpringBoard sees, anywhere: a hold ends (Unhold: back to rest, the symbols off; the time noted, so a click's own touch down puts the sizes back).
static inline int MSBDLightPtrTouchBegan(MSBDLightPtr *s, double now) {
    if (!s->held) return MSBDLightPtrNothing;
    s->held = 0;
    if (s->grown) { s->grown = 0; s->restAt = now; }
    return MSBDLightPtrUnhold;
}
// A look while held (step: MSBDHoverHoldStep's answer): Keep, UIKit's again (the hover began: Nothing, the sizes stay with it), or Unhold.
static inline int MSBDLightPtrHoldLook(MSBDLightPtr *s, int step, double now) {
    if (step == MSBDHoverHoldKeep) return MSBDLightPtrKeep;
    if (step == MSBDHoverHoldUIKit) { s->held = 0; return MSBDLightPtrNothing; }
    s->held = 0;
    if (s->grown) { s->grown = 0; s->restAt = now; }
    return MSBDLightPtrUnhold;
}
// iPadOS hid the pointer (D48, 1.8.8; KT's overnight default: "end the hold when the pointer fades, so nothing stays grown with no pointer on screen"):
// pointeruid's word (fade: common/PointerFade.h's state; hidden for idle, a touch or typing) ends a hold as a look that ends it does (Unhold: back to rest,
// the symbols off, the time noted), unless UIKit's hover began again (hovering: the pointer moved and shows; it is UIKit's then, as before). Nothing
// said (MacPointer not in pointeruid) or shown: the hold as before. A hover over the lights after it grows them again (MSBDLightPtrHoverOver, no hold).
static inline int MSBDLightPtrFade(MSBDLightPtr *s, int hovering, unsigned long long fade, double now) {
    if (!s->held || hovering || fade != MSBDPointerFadeHidden) return MSBDLightPtrNothing;
    return MSBDLightPtrHoldLook(s, MSBDHoverHoldEnd, now);
}
// A light's touch down (TouchDown, TouchDragEnter): Regrow puts the sizes of the hover's end back (the cancel came before the click's touch) -- the
// switch on, no pill, the press idle, the hover ended within kMSBDLightPtrRegrowIn, and the touch the press marked as the pointer's.
static inline int MSBDLightPtrClickDown(MSBDLightPtr *s, int on, int pillOut, int pressIdle, double now) {
    int back = on && !pillOut && pressIdle && !s->grown && s->restAt > 0 && now - s->restAt <= kMSBDLightPtrRegrowIn
        && s->markPointer && s->markAt > 0 && now - s->markAt <= kMSBDLightPtrMarkIn;
    if (!back) return MSBDLightPtrNothing;
    s->grown = 1; s->restAt = 0;
    return MSBDLightPtrRegrow;
}
// A light's touch up (TouchUpInside, TouchUpOutside, TouchCancel, TouchDragExit): back to rest unless the hover is back (it follows) or held.
static inline int MSBDLightPtrClickUp(MSBDLightPtr *s, int hovering) {
    if (!s->grown || hovering || s->held) return MSBDLightPtrNothing;
    s->grown = 0; s->restAt = 0;
    return MSBDLightPtrRest;
}
// -apply's look (DMLightGroup -apply: every front change, every MilkyWay4 layout pass, the bar's lights' layout, each lighting): RestNow puts a grown or
// held set back at once (the caller: the symbols off if it was held).
static inline int MSBDLightPtrCheck(MSBDLightPtr *s, int clicking, int hovering, int visible, int on, int onButton) {
    if ((!s->grown && !s->held) || clicking) return MSBDLightPtrNothing;
    int stale = !on || !visible || (!hovering && !s->held) || (s->grown && !onButton);
    if (!stale) return MSBDLightPtrNothing;
    s->grown = 0; s->held = 0;
    return MSBDLightPtrRestNow;
}
