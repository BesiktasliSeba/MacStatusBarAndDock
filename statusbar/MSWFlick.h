// MSWFlick.h -- Swipe Up to Quit in the Mac Switcher's view (1.8.6, KT 10 Nov): when a gesture on a window's thumbnail quits its app, as the App
// Switcher's swipe-up does, and when it stays today's move to another desktop. Plain C (tools/test-mswflick.sh).
//
// A finger: the App Switcher's quit is a flick with no hold; the Mac Switcher's move is a press, maybe a pause, then a deliberate drag. So a quit is
// a finger that went up quickly from the moment it touched -- no hold before it moved, a short gesture, fast and mostly upward at the lift, gone up
// far enough -- and was not let go over the desktops in the strip: a drag that ends on a desktop always moves the window there, however fast, and
// one let go a little off it (its name, a gap, the strip's end where "+" stands) is never a quit (MSBDMSWFlickOverStrip).
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
    int overDesk;      // let go over the desktops in the strip: a desktop, "+", or round them (MSBDMSWFlickOverStrip)
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
// "+", right of the last desktop's reach, keeps its own). Everywhere in it is over the desktops for a flick too (MSBDMSWFlickOverStrip): never a quit.
#define kMSBDMSWDropReach      6.0
// 1: a window let go at (x, y) goes to the desktop whose tile is minX..maxX, minY..maxY.
static inline int MSBDMSWDropOnDesk(double x, double y, double minX, double minY, double maxX, double maxY) {
    if (x < minX - kMSBDMSWDropReach || x > maxX + kMSBDMSWDropReach || y < minY - kMSBDMSWDropReach) return 0;
    double bottom = MSBDMSWNamesMaxY(maxY);
    if (bottom < maxY + kMSBDMSWDropReach) bottom = maxY + kMSBDMSWDropReach;
    return y <= bottom;
}

// 1: a flick let go at (x, y) is over the desktops in the strip, so never a quit: from half a gap left of the first desktop to the strip's right end
// (the desktops, their names, the gaps between them, "+" or its place when the most desktops are open), from the top down to the bottom of the names
// (namesMaxY, MSBDMSWNamesMaxY). Not the whole strip: left of the first desktop and below the names a top-row thumbnail flicked up still quits.
static inline int MSBDMSWFlickOverStrip(double x, double y, double firstMinX, double namesMaxY, double gap) {
    return x >= firstMinX - gap / 2.0 && y <= namesMaxY;
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
