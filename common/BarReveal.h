// BarReveal.h -- the menu bar over a full-screen app that hides it (a game), shown on a deliberate gesture, as on a Mac (1.8.4.3 item 12, KT 9 Nov:
// on the M1 a game opened full screen with no status bar and no way to leave it). Pushing the pointer against the top edge shows the bar with the
// app's traffic lights; a finger swiping down from the very top edge does it for touch. The bar goes again after use: the pointer has left it, or
// for touch a few seconds after it showed, or at once when the app is touched below the bar. Nothing is taken from the app: the swipe is only
// watched, never held back, so the app's own top-edge gestures stay its own. Plain C: the Mac test (tools/test-barreveal.c) runs these very rules.
#ifndef MSBD_BAR_REVEAL_H
#define MSBD_BAR_REVEAL_H
#include <stdbool.h>

#define kMSBDRevealEdge 6.0          // the pointer within this many points of the top edge: pushed against it (it stops about 5 pt short)
#define kMSBDRevealSwipeStart 12.0   // a finger that begins this close to the top edge
#define kMSBDRevealSwipeMin 30.0     // and comes down at least this far
#define kMSBDRevealSwipeTime 0.8     // within this long (seconds)
#define kMSBDRevealMinShown 1.0      // shown at least this long
#define kMSBDRevealLeaveAfter 0.7    // pointer: it goes this long after the pointer left the bar
#define kMSBDRevealTouchShown 4.0    // touch: it goes this long after it showed or was last used

enum { kMSBDRevealByPointer = 1, kMSBDRevealByTouch = 2 };

// Where the pointer is, by its y in the current orientation: 1 at the top edge, 2 over the bar, 3 below it, 0 unknown.
static inline int MSBDRevealZone(double y, double barHeight) {
    if (!(y >= 0)) return 0;
    if (y <= kMSBDRevealEdge) return 1;
    if (y <= barHeight + 2.0) return 2;
    return 3;
}

// A finger's path from its first point: a swipe down from the very top edge.
static inline bool MSBDRevealSwipe(double startY, double dx, double dy, double dt) {
    if (!(startY >= 0) || startY > kMSBDRevealSwipeStart) return false;
    if (dy < kMSBDRevealSwipeMin || dt < 0 || dt > kMSBDRevealSwipeTime) return false;
    return (dx < 0 ? -dx : dx) < dy;   // (more down than sideways)
}

// Whether a bar shown by `by` goes now. lastUseAt: the last touch on the bar (touch reveals); touchedBelow: the app was touched below the bar.
static inline bool MSBDRevealEnds(int by, double now, double shownAt, int zone, double leftAt, bool menuOpen, double lastUseAt, bool touchedBelow) {
    if (menuOpen) return false;                          // (a menu of the bar is open: it stays, as on a Mac)
    if (now - shownAt < kMSBDRevealMinShown) return false;
    if (touchedBelow) return true;                       // (back to the app)
    if (by == kMSBDRevealByPointer) return (zone == 3 || zone == 0) && now - leftAt >= kMSBDRevealLeaveAfter;
    double from = lastUseAt > shownAt ? lastUseAt : shownAt;
    return now - from >= kMSBDRevealTouchShown;
}
#endif
