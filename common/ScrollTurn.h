// ScrollTurn.h -- the orientation UIKit turns a trackpad's or mouse's scroll by, for our two windows whose content is turned inside them (1.7.9,
// KT on the A12Z: in the Today panel the Magic Keyboard's trackpad scrolled sideways, a horizontal two-finger scroll moved the list up and down).
// Plain C, so the Mac test (tools/test-scrollturn.c) runs this very code; StatusBar.x feeds it.
// Why: on iPadOS 16 and later the menu window keeps its portrait shape while the screen is turned (on 16 the native windows' layer too; on 18.5
// it turns itself), and what we show in them lies in a container turned back by the same angle (DMMenuHost's rotator, NativeWindow.h's). A
// scroll's delta comes in the device's own space (up on the trackpad is up for the user), and from 17 UIKit turns it into the screen's fixed space
// by the interface orientation of the window the scroll was sent to (-[UIScrollEvent _convertDeltaFromHIDDeviceSpaceToSceneReferenceSpaceIfNeeded:],
// in SpringBoard by -_overriddenInterfaceOrientation; 16.7.7 asks the window scene instead). For these windows that is portrait, so in landscape
// the delta was not turned, and the container's turn then made it sideways in every list in them: the Today panel, About, Force Quit, and Finder,
// Activity Monitor and TextEdit where their layer is portrait. A finger was right all along: a touch comes as a point, and every container's turn
// is in UIKit's point conversion. So UIKit is told, for that turn of the delta only, the orientation the content is shown in.
#ifndef MSBD_SCROLL_TURN_H
#define MSBD_SCROLL_TURN_H
#include <math.h>

// The interface orientation a container turned by `angle` (radians, as CGAffineTransformMakeRotation takes it: the menus' and the native
// windows' container, turned to undo how its portrait window lies on the screen) is shown in: 3 (landscape, home button right: the window's
// x-axis runs up the screen, the container turned by +90 deg), 4 (by -90 deg), 2 (upside down, 180 deg). 0: not turned (or not a quarter turn),
// the window's own orientation is right and UIKit is left alone.
static inline int MSBDScrollTurnOrientation(double angle) {
    if (!isfinite(angle)) return 0;
    long q = lround(angle / M_PI_2);
    if (fabs(angle - q * M_PI_2) > 0.01) return 0;
    q %= 4; if (q < 0) q += 4;
    return q == 1 ? 3 : (q == 2 ? 2 : (q == 3 ? 4 : 0));
}
#endif
