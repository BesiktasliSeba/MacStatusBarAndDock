// test-scrollturn.c -- Mac test of the trackpad's scroll in our turned containers (common/ScrollTurn.h, 1.7.9; KT on the A12Z: the Today panel
// scrolled sideways with the Magic Keyboard's trackpad). UIKit's two steps are modelled on its own code (UIKitCore 17.5.1, the same in 18.5):
//  - the device -> screen-fixed turn of the delta, -[UIScrollEvent _convertDeltaFromHIDDeviceSpaceToSceneReferenceSpaceIfNeeded:]: a switch on
//    the window's interface orientation, then both signs flipped unless the event's options have 0x20;
//  - the screen-fixed -> window turn of a point, -[UIWindow _convertPointFromSceneReferenceSpace:] (for an upright window in that orientation);
// and the container's turn is UIKit's point conversion into a view turned by CGAffineTransformMakeRotation(angle).
#include <stdio.h>
#include <math.h>
#include "../common/ScrollTurn.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
typedef struct { double x, y; } V;
static int Same(V a, V b) { return fabs(a.x - b.x) < 1e-9 && fabs(a.y - b.y) < 1e-9; }
// UIKit: the delta from the device's space into the screen's fixed space, by the window's orientation o (17.5.1 jump table at 0x18adff744).
static V UIKitDeviceToFixed(int o, V d, int optionsHave0x20) {
    V r;
    switch (o) {
        case 1: r = (V){ -d.x, -d.y }; break;
        case 2: r = (V){ d.x, d.y }; break;
        case 3: r = (V){ d.y, -d.x }; break;
        case 4: r = (V){ -d.y, d.x }; break;
        default: r = (V){ d.x, d.y }; break;
    }
    if (!optionsHave0x20) { r.x = -r.x; r.y = -r.y; }
    return r;
}
// UIKit: a point from the screen's fixed space into a window upright in orientation o (the rotation part; for a delta the origin terms cancel).
static V UIKitFixedToUprightWindow(int o, V p) {
    if (o == 3) return (V){ p.y, -p.x };
    if (o == 4) return (V){ -p.y, p.x };
    if (o == 2) return (V){ -p.x, -p.y };
    return p;
}
// UIKit's point conversion from a window into a subview turned by `angle` around its centre (the inverse turn; the centre terms cancel).
static V IntoTurned(double angle, V p) { double c = cos(-angle), s = sin(-angle); return (V){ c * p.x - s * p.y, s * p.x + c * p.y }; }
// What a list in one of our containers gets: the window is portrait (its space is the screen's fixed space), the container turned by `angle`.
static V InOurContainer(int orientationUIKitUses, double angle, V d, int flag) { return IntoTurned(angle, UIKitDeviceToFixed(orientationUIKitUses, d, flag)); }
int main(void) {
    Expect("the mapping: not turned -> 0 (UIKit left alone)", MSBDScrollTurnOrientation(0.0) == 0 && MSBDScrollTurnOrientation(-0.0) == 0 && MSBDScrollTurnOrientation(2 * M_PI) == 0);
    Expect("  ... +90 deg (the window's x-axis runs up the screen) -> 3, -90 deg -> 4", MSBDScrollTurnOrientation(M_PI_2) == 3 && MSBDScrollTurnOrientation(-M_PI_2) == 4);
    Expect("  ... 180 deg either way -> 2", MSBDScrollTurnOrientation(M_PI) == 2 && MSBDScrollTurnOrientation(-M_PI) == 2);
    Expect("  ... the same quarter turns past a whole turn (270 deg = -90, -270 deg = +90)", MSBDScrollTurnOrientation(3 * M_PI_2) == 4 && MSBDScrollTurnOrientation(-3 * M_PI_2) == 3);
    Expect("  ... nonsense (not a quarter turn, NaN, infinity) -> 0", MSBDScrollTurnOrientation(0.3) == 0 && MSBDScrollTurnOrientation(NAN) == 0 && MSBDScrollTurnOrientation(INFINITY) == 0);

    // The model of UIKit is right: in an ordinary window, upright in its orientation, a scroll comes out as the user moved (flipped as the device asks).
    V up = { 0, -10 }, right = { 10, 0 }, slant = { 3, -7 };
    for (int o = 1; o <= 4; o++) {
        char what[160];
        V dl = UIKitFixedToUprightWindow(o, UIKitDeviceToFixed(o, slant, 0)), dlf = UIKitFixedToUprightWindow(o, UIKitDeviceToFixed(o, slant, 1));
        snprintf(what, sizeof what, "UIKit's model, an ordinary window upright in orientation %d: the scroll as on the trackpad (and flipped with 0x20)", o);
        Expect(what, Same(dl, slant) && Same(dlf, (V){ -slant.x, -slant.y }));
    }

    // Our window (portrait) with its container turned for the screen: KT's case, landscape.
    const double turns[3] = { M_PI_2, -M_PI_2, M_PI };
    const char *names[3] = { "landscape, home button right (+90 deg)", "landscape, home button left (-90 deg)", "upside down (180 deg)" };
    for (int i = 0; i < 3; i++) {
        double a = turns[i]; char what[220];
        V oldUp = InOurContainer(1, a, up, 0), oldRight = InOurContainer(1, a, right, 0);
        snprintf(what, sizeof what, "before (UIKit takes the window's portrait), %s: %s", names[i], i < 2 ? "an up scroll is sideways, a sideways one moves up or down" : "the scroll runs the wrong way");
        Expect(what, i < 2 ? (fabs(oldUp.y) < 1e-9 && fabs(fabs(oldUp.x) - 10) < 1e-9 && fabs(oldRight.x) < 1e-9 && fabs(fabs(oldRight.y) - 10) < 1e-9)
                           : (Same(oldUp, (V){ -up.x, -up.y }) && Same(oldRight, (V){ -right.x, -right.y })));
        int o = MSBDScrollTurnOrientation(a);
        snprintf(what, sizeof what, "now (UIKit takes orientation %d, the container's), %s: up is up, sideways is sideways, a slant is the same slant", o, names[i]);
        Expect(what, Same(InOurContainer(o, a, up, 0), up) && Same(InOurContainer(o, a, right, 0), right) && Same(InOurContainer(o, a, slant, 0), slant));
        snprintf(what, sizeof what, "  ... and exactly as an ordinary upright window has it, also with the device's flip (0x20), %s", names[i]);
        Expect(what, Same(InOurContainer(o, a, slant, 1), UIKitFixedToUprightWindow(o, UIKitDeviceToFixed(o, slant, 1))));
    }
    Expect("portrait (the container not turned): the window's own orientation stays, as it was right", MSBDScrollTurnOrientation(0.0) == 0 && Same(InOurContainer(1, 0.0, slant, 0), slant));
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
