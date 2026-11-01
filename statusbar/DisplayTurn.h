// DisplayTurn.h -- the screen's interface orientation against the display's own space, in one place: a window's scene frame as its app reads it
// (1.7.7 item 2, StatusBar.x DMWindowFrameForApp / DMWindowFrameOnScreen) and the turn a still of the display needs (1.7.7 item 3, DMScreenStillView).
// Plain C on CoreGraphics, so the Mac test (tools/test-displayturn.c) runs this very code.
//  - The display's own space is portrait: w x h with w the short side (the M1: 834 x 1194). Interface orientation 1 is that space as it is, 2 turned
//    half round, 3 and 4 the two landscapes. On the screen (the interface's space) a point (x, y) of a landscape 3 screen is the display's (w - y, x),
//    of a landscape 4 screen (y, h - x), of 2 (w - x, h - y) -- iOS's fixed coordinate space (UIScreen fixedCoordinateSpace).
//  - A window's frame in a landscape scene's settings has its size turned to the scene (width = the window's height on the screen). Aerial 5 on
//    iPadOS 15 gives the window's place on the SCREEN with it; iOS's own apps read the frame in the display's space. MSBDFrameForApp turns it there
//    (landscapes only: the only ones it is used for), MSBDFrameOnScreen turns it back.
//  - A still: the render server draws the display as its panel lies (portrait up on the iPad 2, 16.7.7; landscape, interface orientation 3 up, on
//    the M1, 15.6.1). The picture turns by the interface's own turn from portrait, less the panel's; a quarter turn swaps its sides.
#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

// The screen's terms -> the display's (landscape 3 and 4; any other orientation as it is). w, h: the display's short and long sides.
static inline CGRect MSBDFrameForApp(CGRect f, long o, CGFloat w, CGFloat h) {
    if (o == 3) return CGRectMake(w - f.origin.y - f.size.width, f.origin.x, f.size.width, f.size.height);
    if (o == 4) return CGRectMake(f.origin.y, h - f.origin.x - f.size.height, f.size.width, f.size.height);
    return f;
}
// The display's terms -> the screen's (MSBDFrameForApp turned back).
static inline CGRect MSBDFrameOnScreen(CGRect f, long o, CGFloat w, CGFloat h) {
    if (o == 3) return CGRectMake(f.origin.y, w - f.origin.x - f.size.width, f.size.width, f.size.height);
    if (o == 4) return CGRectMake(h - f.origin.y - f.size.height, f.origin.x, f.size.width, f.size.height);
    return f;
}
// The turn a still of the display needs on a screen in interface orientation o (radians, UIKit's: positive is clockwise on the screen), for a
// panel of nativeW x nativeH points as the render server draws it.
static inline double MSBDStillAngle(long o, CGFloat nativeW, CGFloat nativeH) {
    double ui = o == 3 ? M_PI_2 : o == 4 ? -M_PI_2 : o == 2 ? M_PI : 0.0;
    return (nativeW > nativeH ? M_PI_2 : 0.0) - ui;
}
// A quarter turn (either way): the picture's sides swap.
static inline int MSBDStillQuarter(double angle) { return fabs(fabs(remainder(angle, M_PI)) - M_PI_2) < 0.01; }
