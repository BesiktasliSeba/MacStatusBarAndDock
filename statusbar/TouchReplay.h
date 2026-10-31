// TouchReplay.h -- where a touch whose first reports came at (0, 0) began (StatusBar.x, the touch fix's replay), plain C so the Mac test
// (tools/test-touchreplay.c) runs this very rule.
//  - iPad 2 (16.7.7): the first touch after each SpringBoard start comes with its DOWN -- and sometimes the next report -- at the touch screen's
//    own (0, 0). The fix keeps that touch from SpringBoard and sends it again from its real points. A pull from the top edge had moved ~55 pt by
//    its first real report (1.7.4 k01: sent again from there it began 56 pt below the edge, and no pull started).
//  - So the start is worked out from the first two real points: the finger's speed between them, carried back to the DOWN's time. At most 80 pt
//    back (a report gap is tens of ms), and never past the screen's edges (half a point inside: a pull from the edge begins at the edge).
#ifndef MSBD_TOUCH_REPLAY_H
#define MSBD_TOUCH_REPLAY_H
#include <math.h>

typedef struct { double x, y; } MSBDTRPoint;
// p1 at t1, p2 at t2: the first two real points (screen points, seconds); down: the DOWN's time; w, h: the screen's size.
static inline MSBDTRPoint MSBDTouchReplayStart(MSBDTRPoint p1, double t1, MSBDTRPoint p2, double t2, double down, double w, double h) {
    double dt = t2 - t1, back = t1 - down;
    double dx = 0, dy = 0;
    if (dt > 0.0005 && back > 0) { dx = (p2.x - p1.x) / dt * back; dy = (p2.y - p1.y) / dt * back; }
    double len = sqrt(dx * dx + dy * dy);
    if (len > 80.0) { dx *= 80.0 / len; dy *= 80.0 / len; }
    MSBDTRPoint p0 = { p1.x - dx, p1.y - dy };
    if (p0.x < 0.5) p0.x = 0.5; if (p0.x > w - 0.5) p0.x = w - 0.5;
    if (p0.y < 0.5) p0.y = 0.5; if (p0.y > h - 0.5) p0.y = h - 0.5;
    return p0;
}

#endif
