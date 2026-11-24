// BarAutoHide.h -- Automatically Hide and Show the Menu Bar per display (MacStatusBar&Dock 1.8.7 row 14; plans/design-1.8.7-displays.md section 5).
// Plain C: the Mac test (tools/test-barautohide.c) runs these very rules. The iPad's own machine (StatusBar.x DMStatusBarSetHidden and its tick) stays
// as it was and moves only the iPad's bar copies; another display -- a TV -- has its own state here, on while its own setting (the iPad's until
// changed for it) is on and a pointer is attached:
//  - it hides when the pointer has left that display's bar for a moment and no menu is open from it, and it was shown long enough;
//  - it shows when the pointer reaches that display's top edge: a 6 pt hover strip at the top of its scene (StatusBar.x, in the per-scene layer
//    helper), since a hidden bar takes no hover (S4: hover reaches SpringBoard's windows on the TV, in TV points; backboardd's one global position
//    for both displays cannot tell them apart);
//  - each bar copy takes its own display's state (a new copy comes up hidden only if its own display's bar is hidden);
//  - windows: none moves on the TV. Its stage top keeps its bar's room while its bar hides (Stage Manager's pass for the TV's container, StatusBar.x
//    DMSMStageTopByDisplay, and our usable area for the TV): no other engine has a TV desktop. (On the iPad's own screen every engine -- Aerial,
//    Zetsu, MilkyWay4 and, since 1.8.8.4, our Stage Manager engine -- takes the bar's room while the bar hides itself: the rules at the end.)
//  - the iPad's own pointer zone (from backboardd's global position) is not read while the pointer is on a TV's bar or strip: the same position
//    stands for a place on the iPad too, and the iPad's bar showed from a pointer on the TV's top.
#ifndef MSBD_BAR_AUTO_HIDE_H
#define MSBD_BAR_AUTO_HIDE_H
#include <math.h>
#include "MenuBarHeight.h"   // (the bar's line and band: MSBDMenuBarTopLimit, MSBDMenuBarWasTop, MSBDMenuBarUnderTop)

#define kMSBDBarAHLeaveAfter 0.7   // it hides this long after the pointer left the bar (the iPad's: the same)
#define kMSBDBarAHMinShown 1.0     // shown at least this long after it was brought
#define kMSBDBarAHStripH 6.0       // the top-edge hover strip (the pointer stops about 5 pt short of the edge)
#define kMSBDBarAHMinOffset 24.0   // a hidden copy goes up by its height, at least this much

typedef struct { int on, hidden, pointerIn; double revealedAt, lastExit; } MSBDBarAHState;

// The switch for one display: its setting (resolved for it), a pointer attached, and not on the Lock Screen.
static inline int MSBDBarAHActive(int setting, int pointerAttached, int locked) { return setting && pointerAttached && !locked; }

// Its state follows its switch: turned on or off, the pointer's last exit is now; turned off while hidden, it shows -- returns 1 then (show it).
static inline int MSBDBarAHSetOn(MSBDBarAHState *s, int on, double now) {
    if (!s || (on != 0) == (s->on != 0)) return 0;
    s->on = on != 0;
    s->lastExit = now;
    if (!s->on && s->hidden) { s->hidden = 0; return 1; }
    return 0;
}
// The pointer came onto (inside) or left that display's bar.
static inline void MSBDBarAHPointer(MSBDBarAHState *s, int inside, double now) {
    if (!s || (inside != 0) == (s->pointerIn != 0)) return;
    s->pointerIn = inside != 0;
    if (!inside) s->lastExit = now;
}
// The pointer reached that display's top edge: shown (returns 1 when it was hidden), and kept a moment.
static inline int MSBDBarAHReveal(MSBDBarAHState *s, double now) {
    if (!s || !s->on) return 0;
    s->revealedAt = now;
    if (!s->hidden) return 0;
    s->hidden = 0;
    return 1;
}
// Hide it now? On, shown, the pointer not on it, no menu open from it, the pointer gone a moment and the bar shown long enough.
static inline int MSBDBarAHShouldHide(const MSBDBarAHState *s, int menuOpenHere, double now) {
    return s && s->on && !s->hidden && !s->pointerIn && !menuOpenHere && now - s->lastExit > kMSBDBarAHLeaveAfter && now - s->revealedAt > kMSBDBarAHMinShown;
}
// A bar copy's offset: by its own display's state, up by its height (at least 24) while that bar is hidden.
static inline double MSBDBarAHCopyOffset(const MSBDBarAHState *own, double copyH) {
    if (!own || !own->hidden) return 0.0;
    return -(copyH > kMSBDBarAHMinOffset ? copyH : kMSBDBarAHMinOffset);
}
// iPadOS hides a pointer that has been still for a few seconds, and a hover then ends where the pointer is (A12Z 18.5, d07: the TV's bar hid ~7 s after
// the pointer came to rest on it). UIKit gives a hover's end no place ({0, 0}, d08), so the place is the last one seen on the bar: a hover that ends
// after the pointer was last seen well inside the bar (6 pt or more from its bottom edge and its sides) may be a fade, and only a move tells (below);
// one last seen at an edge has left.
static inline int MSBDBarAHEndIsFade(double x, double y, double w, double h) { return w > 12.0 && h > 6.0 && x >= 6.0 && x <= w - 6.0 && y >= 0.0 && y <= h - 6.0; }
// After a fade the pointer counts as on the bar until it moves (backboardd's global position, any frame: only whether it moved): moved more than 2 pt
// with no hover on the bar since, it has left (it came back off the bar, where the bar's hover never saw it).
static inline int MSBDBarAHMovedAfterFade(double dx, double dy) { return dx * dx + dy * dy > 4.0; }
// Stage Manager's stage top on a TV, with its bar hidden or not: the same (the bar's room is kept, no window moves).
static inline double MSBDBarAHStageTop(double barH, double titleBarH, int barHidden) { (void)barHidden; return barH + titleBarH; }
// The iPad's own pointer zone (backboardd's global position, 1 top edge, 2 over the bar, 3 below, 0 unknown) while the pointer is on a TV's bar or
// strip: below the bar (3) -- it is not on the iPad.
static inline unsigned long long MSBDBarAHIPadZone(unsigned long long zone, int pointerOnOtherDisplayBar) { return pointerOnOtherDisplayBar && zone ? 3 : zone; }

// The iPad's own screen: one window top for every engine while the bar hides itself (1.8.8.4, engine parity).
// As on a Mac with "Automatically hide and show the menu bar": the bar takes no room, so windows reach the screen's top edge -- a title-bar drag, Fill,
// the tiles, a new window. `layout`: the bar may hide itself there (StatusBar.x DMAutoHideLayout: the setting on and a pointer attached).
// The top the windows reach: the screen's top edge while the bar hides itself, else right under the bar (barTop) -- StatusBar.x DMTopLimit.
static inline double MSBDBarAHWindowTop(double barTop, int layout) { return layout ? 0.0 : barTop; }
// Our Stage Manager engine's stage top on the iPad (our answer to -[SBSwitcherChamoisSettings _statusBarHeight]): that window top -- the bar's room
// being iOS's status bar height raised to our bar's (iosH, barH) -- and our title bar (titleH) under it: 48 at Small, 24 while the bar hides itself.
static inline double MSBDBarAHSMStageTop(double iosH, double barH, double titleH, int layout) { return MSBDBarAHWindowTop(fmax(iosH, barH), layout) + titleH; }
// A stage-area pass's top (Apple's, from its bounds' top) on the iPad (tv 0) or a TV (tv 1). Stage Manager has one answer for every display, made with
// the bar's room or without it, and a pass's layout attributes may have been made before the switch: a top that is our answer with the bar's room, or
// the one without it once that was given (lowered: 24 is also iOS's own status bar height, so it is ours only then), is ours, and becomes the iPad's
// by its state now, or a TV's with its own bar's room (the iPad's room when the TV's bar is the iPad's size, as before 1.8.8.4: tvSameSize; else
// iOS's status bar height raised to the TV's bar, tvBarH) -- a TV's top never follows the iPad's bar hiding itself. Any other top is Apple's.
static inline int MSBDBarAHIsOurTop(double top, double iosH, double barH, double titleH, int lowered) {
    return isfinite(top) && (fabs(top - MSBDBarAHSMStageTop(iosH, barH, titleH, 0)) < 0.5 || (lowered && fabs(top - MSBDBarAHSMStageTop(iosH, barH, titleH, 1)) < 0.5));
}
static inline double MSBDBarAHPassTop(double top, double iosH, double barH, double titleH, int layout, int lowered, int tv, int tvSameSize, double tvBarH) {
    if (!MSBDBarAHIsOurTop(top, iosH, barH, titleH, lowered)) return top;
    if (!tv) return MSBDBarAHSMStageTop(iosH, barH, titleH, layout);
    return tvSameSize ? MSBDBarAHSMStageTop(iosH, barH, titleH, 0) : fmax(iosH, tvBarH) + titleH;
}
// A window at the top when the bar's room is given (layout 1) or taken back (0), on every engine (StatusBar.x DMAutoHideRetopAll for Aerial, Zetsu and
// MilkyWay4, DMAutoHideSMRetop for our Stage Manager engine). y and h: the whole window (its title bar included); bottom: where a full-height window
// ends (Fill's bottom); bar: the bar's height; wasTop: it was at the top before a turn (a turn scales its place). Given: a window at the bar's line
// (23.5 +- 2 on a 24 pt bar), or a turned one that was at the top and is still near it, goes up to the top edge; taken back: one in the bar's room
// (above 22) goes under the bar. A full-height window (its bottom within 3 pt of `bottom`, or below it: behind the Dock) grows / shrinks with it:
// given, to at least `bottom` (a window lying further down, behind the Dock, keeps its height, so its bottom moves up by the bar's room); taken back,
// keeping its bottom. Returns 1 when it moves. The rule of StatusBar.x's DMAutoHideRetopAll since 1.7.x, to the number (1.8.8.4: moved here for every
// engine; that a window behind the Dock loses the bar's room at each on / off cycle is a question for KT, not changed in a parity item).
__attribute__((always_inline)) static inline int MSBDBarAHRetop(double *y, double *h, double bottom, double bar, int layout, int wasTop) {   // (inlined: its callers' crash rule)
    if (!y || !h || !isfinite(*y) || !isfinite(*h) || !(*h > 0) || !isfinite(bar)) return 0;
    double y0 = *y, h0 = *h, maxY = y0 + h0;
    int full = isfinite(bottom) && maxY > bottom - 3.0;
    if (layout && (fabs(y0 - MSBDMenuBarWasTop(bar)) < 2.0 || (wasTop && y0 > 0.5 && y0 < 60.0))) { if (full) *h = fmax(bottom, h0); *y = 0.0; }
    else if (!layout && y0 < MSBDMenuBarUnderTop(bar)) { double limit = MSBDMenuBarTopLimit(bar); if (full) *h = fmax(bottom, maxY) - limit; *y = limit; }
    else return 0;
    return fabs(*y - y0) > 0.001 || fabs(*h - h0) > 0.001;
}
// A title bar's slide while the bar shows (every engine's: the window stays, only its title bar slides down with the bar, in lockstep, and back): a
// window whose top (the whole window's, on the screen) is above `touching` (the bar's line less a point) slides by what the shown bar covers of it.
static inline double MSBDBarAHTitleSlide(double top, double barH, double touching, int show) {
    return show && isfinite(top) && top < touching ? fmax(0.0, barH - fmax(0.0, top)) : 0.0;
}

#endif
