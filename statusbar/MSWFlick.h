// MSWFlick.h -- Swipe Up to Quit in the Mac Switcher's view (1.8.6, KT 10 Nov): when a gesture on a window's thumbnail quits its app, as the App
// Switcher's swipe-up does, and when it stays today's move to another desktop. Plain C (tools/test-mswflick.sh).
//
// A finger: the App Switcher's quit is a flick with no hold; the Mac Switcher's move is a press, maybe a pause, then a deliberate drag. So a quit is
// a finger that went up quickly from the moment it touched -- no hold before it moved, a short gesture, fast and mostly upward at the lift, gone up
// far enough -- and was not let go on a desktop or "+" in the strip: a drag that ends on one always moves the window there, however fast
// (MSBDMSWDropOnDesk, the drop's own target). 1.8.7.2 (KT 14 Nov, A12Z): no wider band round the strip -- it reached from the first desktop to the
// screen's right edge, so on the A12Z, whose windows sit just under the strip, a flick up of the right-hand window always ended in it and never quit.
// The pointer's click-and-drag is never a quit (a pointer moves windows; its quit is the trackpad's two-finger swipe, below).
// The trackpad: as in the App Switcher, two fingers swiped up over a thumbnail carry it up with them, and it goes when let go far enough up or
// flicked up; otherwise it springs back. (A scroll has no hold and no finger-down; only the travel and the speed at the end count. Only a continuous
// scroll, a trackpad's or a Magic Mouse's swipe: a mouse wheel's notches never carry a thumbnail.)
#ifndef MSWFLICK_H
#define MSWFLICK_H

typedef struct {
    double held;       // seconds from the finger's touch-down to its first move past the pan's slop (a hold before the drag when large)
    double duration;   // seconds from the touch-down to the lift
    double vx, vy;     // the speed at the lift, points per second (y grows downward: up is negative)
    double dx, dy;     // the travel from the touch-down to the lift, points
    int overDesk;      // let go on a desktop in the strip (its tile, 6 pt round it, its name) or on "+": the drop's own targets (MSBDMSWDropOnDesk)
    int pointer;       // the pointer's click-and-drag
} MSBDMSWFlick;

#define kMSBDMSWFlickMaxHold      0.25   // a pause longer than this before moving is a hold: the drag's
#define kMSBDMSWFlickMaxDuration  0.60   // a flick is over within this
#define kMSBDMSWFlickMinSpeed     900.0  // points per second upward at the lift
#define kMSBDMSWFlickMinRise      50.0   // points gone up
#define kMSBDMSWFlickMaxSlant     0.70   // sideways speed at most this share of the upward one (about 35 degrees from straight up)

// 1: this finger gesture quits the app; 0: today's drag (its drop or its way back).
static inline int MSBDMSWFlickQuits(MSBDMSWFlick f) {
    if (f.pointer || f.overDesk) return 0;
    if (!(f.held >= 0 && f.held < kMSBDMSWFlickMaxHold)) return 0;
    if (!(f.duration >= 0 && f.duration <= kMSBDMSWFlickMaxDuration)) return 0;
    if (!(f.vy <= -kMSBDMSWFlickMinSpeed)) return 0;
    if (!(f.dy <= -kMSBDMSWFlickMinRise)) return 0;
    double ax = f.vx < 0 ? -f.vx : f.vx;
    if (ax > kMSBDMSWFlickMaxSlant * -f.vy) return 0;
    return 1;
}

// The strip's layout, shared with MacSwitcher.h (DMMSWStripLayout, DMMSWBuildStrip): the gap between two desktops' tiles, a desktop's name's height
// and how far under its tile the name starts. The bottom of the names under a tile whose bottom is at tileMaxY:
#define kMSBDMSWStripGap       30.0
#define kMSBDMSWStripLabelH    18.0
#define kMSBDMSWStripLabelTop  3.0
static inline double MSBDMSWNamesMaxY(double tileMaxY) { return tileMaxY + kMSBDMSWStripLabelTop + kMSBDMSWStripLabelH; }

// A window dragged onto the strip (1.8.6, iPad 2 i04 row 4c: a slow drag let go on a desktop's name went back to its place): a desktop's drop
// target is its tile, kMSBDMSWDropReach round it, and its name under it, as wide as the tile's reach (so two desktops' targets never touch and
// "+", right of the last desktop's reach, keeps its own). A flick let go on one of them is the move too, never a quit.
#define kMSBDMSWDropReach      6.0
// 1: a window let go at (x, y) goes to the desktop whose tile is minX..maxX, minY..maxY.
static inline int MSBDMSWDropOnDesk(double x, double y, double minX, double minY, double maxX, double maxY) {
    if (x < minX - kMSBDMSWDropReach || x > maxX + kMSBDMSWDropReach || y < minY - kMSBDMSWDropReach) return 0;
    double bottom = MSBDMSWNamesMaxY(maxY);
    if (bottom < maxY + kMSBDMSWDropReach) bottom = maxY + kMSBDMSWDropReach;
    return y <= bottom;
}


#define kMSBDMSWScrollMinShare    0.30   // let go after carrying the thumbnail up this share of its height (at least kMSBDMSWScrollMinRise)
#define kMSBDMSWScrollMinRise     80.0
#define kMSBDMSWScrollFlickSpeed  700.0  // or flicked up at this speed after at least kMSBDMSWScrollFlickRise
#define kMSBDMSWScrollFlickRise   24.0

// 1: the trackpad's two-finger swipe, let go with this travel and speed over a thumbnail tileH tall, quits the app; 0: it springs back.
static inline int MSBDMSWScrollQuits(double dx, double dy, double vy, double tileH) {
    double ax = dx < 0 ? -dx : dx;
    if (!(dy < 0) || ax > -dy) return 0;   // (up, and more up than sideways)
    double need = kMSBDMSWScrollMinShare * (tileH > 0 ? tileH : 0);
    if (need < kMSBDMSWScrollMinRise) need = kMSBDMSWScrollMinRise;
    if (-dy >= need) return 1;
    return vy <= -kMSBDMSWScrollFlickSpeed && -dy >= kMSBDMSWScrollFlickRise;
}

#endif
