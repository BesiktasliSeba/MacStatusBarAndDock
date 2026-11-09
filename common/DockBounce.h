// DockBounce.h -- Settings > Dock > Animate Opening Applications (MacStatusBar&Dock 1.8.4 item 2, as macOS's own option): a Dock icon bounces while
// its app opens and stops once the app's window shows. The rules in plain C on CoreGraphics, shared by the Dock (dock/Bounce.m) and the Mac test
// (tools/test-dockbounce.sh).
//  - Only an app that is not running yet bounces (a running app's window comes at once, as on a Mac); never with Reduce Motion, never while the
//    Home Screen is being edited, never a folder or one of our own Dock items (Finder, Downloads, the Trash).
//  - Each bounce goes up and comes down (MSBDBounceHeight, MSBD_BOUNCE_PERIOD); the icon finishes the bounce it is in when the window shows, so it
//    always makes at least one; it stops anyway after MSBD_BOUNCE_CAP, or when no app process has started by MSBD_BOUNCE_NO_LAUNCH.
//  - Up is the Dock's own up: at a side the Dock's view is turned (common/DockSide.h MSBDDockSideHostTransform), so the icon bounces away from the
//    screen's edge there too.
#ifndef MSBD_DOCK_BOUNCE_H
#define MSBD_DOCK_BOUNCE_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

#define kMSBDAnimateOpeningKey "animateOpening"   // (com.besiktasliseba.dockmagnification) on unless switched off (KT 7 Nov: on for everyone, as on a Mac)
#define MSBD_BOUNCE_PERIOD 0.62      // seconds: one bounce, up and down (macOS's is about this)
#define MSBD_BOUNCE_CAP 10.0         // seconds: a launch that never shows a window stops bouncing here
#define MSBD_BOUNCE_NO_LAUNCH 2.5    // seconds: no process of the app by then -- the tap opened nothing -- stops it

// The switch as stored: a boolean, else on (never set: on, updaters and new installs alike -- KT 7 Nov, as on a Mac; never while Reduce Motion is on:
// MSBDBounceWanted).
static inline int MSBDAnimateOpeningOn(int isBool, int value) { return isBool ? value != 0 : 1; }
// Does this tap bounce its icon?
static inline int MSBDBounceWanted(int settingOn, int reduceMotion, int appIcon, int appRunning, int editing) {
    return settingOn && !reduceMotion && appIcon && !appRunning && !editing;
}
// How high (points, in the Dock's own space): a share of the icon's picture, as a Mac's, kept between 12 and 40 pt.
static inline double MSBDBounceHeight(double pictureHeight) {
    double h = pictureHeight * 0.42;
    if (!(h > 12.0)) h = 12.0;
    if (h > 40.0) h = 40.0;
    return h;
}
// When it ends: started at `start`, the time now `now`; `shown` -- the app's window has shown; `launched` -- an app process has started; `gone` -- that
// process has gone again before its window showed (it crashed or quit while opening: a Mac's bounce stops then too, review 1.8.4 Pass 4 L4). 0: it goes
// on; else the time it ends, always at the end of a bounce (so it never stops in the air) and never before the first bounce has ended.
static inline double MSBDBounceEndsAt(double start, double now, int shown, int launched, int gone, double period, double cap, double noLaunch) {
    double age = now - start;
    if (!(period > 0.0)) return now;
    if (!(shown || gone || age >= cap || (!launched && age >= noLaunch))) return 0.0;
    double cycles = ceil(age / period - 1e-9);
    if (cycles < 1.0) cycles = 1.0;
    return start + cycles * period;
}
// Where "up" goes on the screen for the Dock at `side` (the turned view's up, (0, -1), through its turn): the bottom Dock up, a left Dock right,
// a right Dock left -- always away from the edge the Dock stands on.
static inline CGPoint MSBDBounceScreenDirection(CGAffineTransform hostTurn) {
    CGPoint up = { 0.0, -1.0 };
    return CGPointMake(hostTurn.a * up.x + hostTurn.c * up.y, hostTurn.b * up.x + hostTurn.d * up.y);
}
#endif
