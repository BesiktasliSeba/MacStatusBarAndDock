// BarAutoHide.h -- Automatically Hide and Show the Menu Bar per display (MacStatusBar&Dock 1.8.7 row 14; plans/design-1.8.7-displays.md section 5).
// Plain C: the Mac test (tools/test-barautohide.c) runs these very rules. The iPad's own machine (StatusBar.x DMStatusBarSetHidden and its tick) stays
// as it was and moves only the iPad's bar copies; another display -- a TV -- has its own state here, on while its own setting (the iPad's until
// changed for it) is on and a pointer is attached:
//  - it hides when the pointer has left that display's bar for a moment and no menu is open from it, and it was shown long enough;
//  - it shows when the pointer reaches that display's top edge: a 6 pt hover strip at the top of its scene (StatusBar.x, in the per-scene layer
//    helper), since a hidden bar takes no hover (S4: hover reaches SpringBoard's windows on the TV, in TV points; backboardd's one global position
//    for both displays cannot tell them apart);
//  - each bar copy takes its own display's state (a new copy comes up hidden only if its own display's bar is hidden);
//  - windows: exactly as the iPad's Stage Manager engine. The stage top keeps the bar's room while the bar hides and no window moves (Stage Manager's
//    _statusBarHeight and our usable area; only Aerial / Zetsu / MilkyWay4 slide windows or title bars, on the iPad). Parity, not a choice.
//  - the iPad's own pointer zone (from backboardd's global position) is not read while the pointer is on a TV's bar or strip: the same position
//    stands for a place on the iPad too, and the iPad's bar showed from a pointer on the TV's top.
#ifndef MSBD_BAR_AUTO_HIDE_H
#define MSBD_BAR_AUTO_HIDE_H

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
// Stage Manager's stage top on that display, with its bar hidden or not: the same (the bar's room is kept, no window moves).
static inline double MSBDBarAHStageTop(double barH, double titleBarH, int barHidden) { (void)barHidden; return barH + titleBarH; }
// The iPad's own pointer zone (backboardd's global position, 1 top edge, 2 over the bar, 3 below, 0 unknown) while the pointer is on a TV's bar or
// strip: below the bar (3) -- it is not on the iPad.
static inline unsigned long long MSBDBarAHIPadZone(unsigned long long zone, int pointerOnOtherDisplayBar) { return pointerOnOtherDisplayBar && zone ? 3 : zone; }

#endif
