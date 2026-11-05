// AerialTurn.h -- Aerial 5's windows keep their turn while it fades them around iPadOS's App Switcher (1.8.1 item 7). Plain C, so the Mac test
// (tools/test-aerialturn.sh) runs this very rule; the hooks are UIKit's -[UIWindow setTransform:] and -setFrame: (StatusBar.x DMA5TurnKeep...), never a
// class of Aerial's (it kills SpringBoard when one is hooked).
// On 16 and later Aerial turns its window layer with a transform for the screen's orientation (DMAerial5CheckWindowTurn; the frame then is the
// native screen's). Its fade as the App Switcher comes (0.9, gone at its end) and goes (0.92 to 1) writes a plain scale over that turn, and its next
// layout pass the frame of a window that has no turn: every window was drawn a quarter turned (iPad 2 16.7.7 in landscape, Aerial 5.1, frame by frame:
// sideways for ~0.2 s on the way back, then Aerial's own turn animated them round at the transition's end).
// While that fade runs and the orientation needs a turn: a plain scale keeps the turn instead (the windows only fade), and a frame other than the
// native screen's is not written. Any other write -- Aerial's own turn, when the iPad turns -- goes through.
// On 15 Aerial's window has no turn (transform the identity, frame the screen's in the interface's shape; M1 15.6.1, Aerial 5.1, a5wintrace_). Its own
// layout pass (a -[UIWindow setFrame:] from Aerial's layoutSubviews) puts a window whose frame is not at the origin back there, its size kept. Under the
// fade's 0.9 the frame reads {{59.7, 41.7}, {1074.6, 750.6}}: written at the origin, the window's middle goes to 0.9 of the screen's. Every window jumped
// (-59.7, -41.7) as the fade began and stayed there: coming back, only the next layout pass of that window put it right (a raise, or something at the
// transition's end, about 0.7 s later: the jump), and with nothing to lay it out, a tap on the front window's card, the windows stayed off.
// While that fade's scale is in force on 15 that frame is not written: the windows fade about the screen's middle, as Aerial means them to. Any other
// frame (a turn's) goes through as before.
#ifndef MSBD_AERIAL_TURN_H
#define MSBD_AERIAL_TURN_H
#include <stdbool.h>
#include <math.h>

// a, b, c, d: the transform's. Aerial's fade writes 0.9, 0.92 and 1 (the turn's own near-zero terms are not this: b and c are 1 and -1).
static inline bool MSBDA5PlainScale(double a, double b, double c, double d) {
    return fabs(b) < 1e-6 && fabs(c) < 1e-6 && fabs(a - d) < 1e-6 && a > 0.5 && a < 1.5;
}
static inline bool MSBDA5SameTransform(double a, double b, double c, double d, double a2, double b2, double c2, double d2) {
    return fabs(a - a2) < 0.01 && fabs(b - b2) < 0.01 && fabs(c - c2) < 0.01 && fabs(d - d2) < 0.01;
}
// The turn of an orientation (1 upright, 3 and 4 landscape, 2 upside down), as Aerial's own (DMAerial5CheckWindowTurn).
static inline void MSBDA5TurnFor(long orientation, double *a, double *b, double *c, double *d) {
    *a = orientation == 2 ? -1 : (orientation == 3 || orientation == 4 ? 0 : 1);
    *b = orientation == 3 ? 1 : (orientation == 4 ? -1 : 0);
    *c = orientation == 3 ? -1 : (orientation == 4 ? 1 : 0);
    *d = *a;
}
static inline bool MSBDA5OrientationTurned(long orientation) { return orientation == 2 || orientation == 3 || orientation == 4; }
// The window's transform write during the fade: 1 keep the turn in its place.
static inline bool MSBDA5KeepsTurn(bool inFade, long orientation, double a, double b, double c, double d) {
    return inFade && MSBDA5OrientationTurned(orientation) && MSBDA5PlainScale(a, b, c, d);
}
// The window's frame write during the fade, on 15: 1 goes through. a, b, c, d: the window's transform now; x, y, w, h: the frame; bw, bh: the window's bounds' size.
// Not through: the scaled frame at the origin, what Aerial's pass writes.
static inline bool MSBDA5FrameGoesNoTurn(bool inFade, double a, double b, double c, double d, double x, double y, double w, double h, double bw, double bh) {
    if (!inFade || !MSBDA5PlainScale(a, b, c, d) || fabs(a - 1.0) < 1e-6) return true;
    return !(fabs(x) < 0.5 && fabs(y) < 0.5 && fabs(w - bw * a) < 0.5 && fabs(h - bh * a) < 0.5);
}
// The window's frame write during the fade, on 16 and later: 1 goes through. w, h: the frame's size (at x, y); sw, sh: the native screen's (portrait).
static inline bool MSBDA5FrameGoes(bool inFade, long orientation, double x, double y, double w, double h, double sw, double sh) {
    if (!inFade || !MSBDA5OrientationTurned(orientation)) return true;
    return fabs(x) < 0.5 && fabs(y) < 0.5 && fabs(w - sw) < 0.5 && fabs(h - sh) < 0.5;
}
#endif
