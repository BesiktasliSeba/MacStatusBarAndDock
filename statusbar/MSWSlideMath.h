// MSWSlideMath.h -- the Mac Switcher's Spaces slide arithmetic (MacSwitcher.h), plain C so that tools/test-mswslide.sh checks it on the Mac.
// The slide is a critically damped spring: e(t) = (e0 + (u0 + w e0) t) e^-wt -- e the strip's distance from its end (offset minus target), u0 its
// speed along x then (de/dt at 0), w omega. A redirect starts the next spring where this one is, at the speed it has there (DMMSWSpringU), so the
// motion has no jump; a taken slide goes, at the lift, to the slot DMMSWGrabSlot names.
#ifndef MSWSLIDEMATH_H
#define MSWSLIDEMATH_H
#include <math.h>
static inline double DMMSWSpringE(double e0, double u0, double w, double t) { return (e0 + (u0 + w * e0) * t) * exp(-w * t); }
static inline double DMMSWSpringU(double e0, double u0, double w, double t) { return (u0 - w * (u0 + w * e0) * t) * exp(-w * t); }
// How long until it stays within 1 pt of its end (Core Animation's own settling time runs on for ~0.2 s of invisible motion; the reveal waited for it).
static inline double DMMSWSpringTime(double e0, double v0, double w) {
    double last = 0;
    for (double t = 0; t < 2.0; t += 0.002) if (fabs(DMMSWSpringE(e0, v0, w, t)) >= 1.0) last = t;
    return fmax(0.06, last + 0.004);
}
// From when on it stays within 3% of its way (at least 2 pt): the slow tail, where a windows change costs the eye a few points at most.
static inline double DMMSWSpringQuiet(double e0, double v0, double w) {
    double last = 0, lim = fmax(2.0, fabs(e0) * 0.03);
    for (double t = 0; t < 2.0; t += 0.002) if (fabs(DMMSWSpringE(e0, v0, w, t)) >= lim) last = t;
    return last;
}
// Where a slide the fingers took goes at the lift: o its offset, W a screen's width (one slot), v the fingers' speed along x; slots lo..hi hold the
// desktops (slot k = k screens from the left desktop, offset -k W). The nearest slot, or -- a flick of 450 pt/s or more -- the next one that way
// from where it is; never past the outer desktops.
static inline long DMMSWGrabSlot(double o, double W, double v, long lo, long hi) {
    double p = -o / (W > 1.0 ? W : 1.0);
    long k = v <= -450.0 ? (long)floor(p) + 1 : v >= 450.0 ? (long)ceil(p) - 1 : lround(p);
    return k < lo ? lo : (k > hi ? hi : k);
}
#endif
