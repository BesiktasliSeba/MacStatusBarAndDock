// MPDisplayGeometry.h: the plain math behind the Mac pointer on another display (external display / TV), kept free of UIKit so the Mac can test
// it (tools/test-mpgeometry.sh). Used by MacPointer.x.
#pragma once
#include <math.h>
#include <stdbool.h>

// A turn measured as a vector (where the x axis ended up), rounded to quarter turns and folded into -1, 0, 1, 2 (x 90 degrees, clockwise on screen).
// *valid is false for a vector too short to tell (then 0).
static inline int MPNormTurns(int q) { q %= 4; if (q < 0) q += 4; return q == 3 ? -1 : q; }
static inline int MPQuarterTurns(double dx, double dy, bool *valid) {
    bool ok = hypot(dx, dy) >= 1.0;
    if (valid) *valid = ok;
    return ok ? MPNormTurns((int)lround(atan2(dy, dx) / M_PI_2)) : 0;
}
// The same size, either way round (a turned screen reports its size turned).
static inline bool MPSameSizeAnyWay(double aw, double ah, double bw, double bh) {
    return (fabs(aw - bw) < 1.5 && fabs(ah - bh) < 1.5) || (fabs(aw - bh) < 1.5 && fabs(ah - bw) < 1.5);
}
// Is the pointer view on another display? Reasons: 0 = no (the iPad), 1 = its window's screen is not the main screen, 2 = its screen's pixel size
// (nativeBounds, never turned) is not the main screen's, 3 = its window is not the main screen's size either way round (for a pointeruid that
// does not tell its screens apart). No window or no sizes = the iPad. None of these depends on the iPad's orientation.
static inline int MPOtherDisplayReason(bool haveWindow, bool haveScreen, bool screenIsMain, double sNW, double sNH, double mNW, double mNH,
                                       double wW, double wH, double mW, double mH) {
    if (!haveWindow) return 0;
    if (haveScreen && !screenIsMain) return 1;
    if (haveScreen && sNW >= 1.0 && sNH >= 1.0 && mNW >= 1.0 && mNH >= 1.0 && !MPSameSizeAnyWay(sNW, sNH, mNW, mNH)) return 2;
    if (wW >= 1.0 && wH >= 1.0 && mW >= 1.0 && mH >= 1.0 && !MPSameSizeAnyWay(wW, wH, mW, mH)) return 3;
    return 0;
}
// The turn from the window to the display: UIKit turns a window for its screen's interface orientation either with a layer turn at or above the
// window's layer (then the screen's interface turn is that same turn, not a second one) or outside the process (then only the screen's interface
// turn shows it). So: the layer turn when there is one, otherwise the screen's.
static inline int MPWindowToDisplayTurns(int windowLayerTurns, int screenTurns) { return MPNormTurns(windowLayerTurns) ? windowLayerTurns : screenTurns; }
// On another display the Mac pointer must end up upright in that display's own fixed space: every turn between the pointer's layer and the
// display (inside the window, then window to display) is undone. Returns the pointer's own turn in radians.
static inline double MPOtherDisplayAngle(int inWindowTurns, int windowLayerTurns, int screenTurns) {
    return -MPNormTurns(inWindowTurns + MPWindowToDisplayTurns(windowLayerTurns, screenTurns)) * M_PI_2;
}
