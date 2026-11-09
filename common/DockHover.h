// DockHover.h -- the Dock's hover magnification survives a Dock layout or a settings change under a resting pointer (1.8.4.1 spec item 4; with it the
// Launchpad stand-in of Edit Home Screen, review-1.8.4-L1-L4 L-1). Plain C, so the Mac test (tools/test-dockhoverhold.c) runs these very rules;
// dock/Dock.x (dm_hover:, DMDockHoverLook) and dock/EditProxy.m (EPFollow) do them in SpringBoard.
// Found (v184's hover watch, 7 Nov; the M1 6 of 6, side and bottom, the iPad 2 2 of 2): every Dock settings change, and the Dock's own layout when its
// recents change (a Handoff suggestion came), cancels the platter's hover recogniser (state 4) while the pointer rests on the Dock -- UIKit's, after a
// notification PointerUIServices posts once our steps are all done, not a step of ours --, and the magnification eased out until the pointer moved. The
// pointer has not left: UIKit only lost track of it. So a cancel is held: backboardd's place of the pointer (BKSMousePointerService, as the side Dock's
// reveal reads it) is asked, and while it is over the platter the magnification stays there, following it; UIKit's own hover beginning again (the pointer
// moved) takes over, and the pointer elsewhere -- or not known, or no pointing device -- ends it as before. An Ended (state 3) is UIKit's "the pointer
// left the platter": as before.
// A cancel is also what a touch brings (device pass 1.8.4.1, review L4, the 17.5 and the iPad 2): a finger on the screen hides the pointer and a click
// starts a touch, UIKit cancels the hover, and backboardd keeps answering the pointer's last place, so a hold left the Dock magnified under a pointer
// that had gone. And not every cancel without a touch is a layout: the iPad 2 cancels it 0.7 to 1 s after the pointer stops on the Dock, with no layout near
// (z03: only a cancel just after a layout was held, and the magnification dropped a second after every stop). So every cancel is held unless a touch came
// just before it. The two can reach SpringBoard in either order: a touch first, the cancel finds it (MSBDHoverHoldsAfter); the cancel first, the hold
// starts and the touch ends it (UIApplication's sendEvent:, dock/Dock.x DMDockHoverTouchBegan). A touch also eases the magnification out where UIKit cancels nothing
// for it. A touch inside an app is the app's: SpringBoard doesn't see it. The idle cancels (the 17.5 about 2 s after the pointer stops, the iPad 2 at 0.7 to 1 s) need no
// telling apart by name: they come through a PointerUIServices notification with no touch before them, so they are held like a layout's.
#ifndef MSBD_DOCK_HOVER_H
#define MSBD_DOCK_HOVER_H
#include <stdbool.h>
#include <math.h>
#include <CoreGraphics/CoreGraphics.h>

// How long after a touch SpringBoard saw a cancel counts as caused by it, in seconds: long enough for a click that opens an app (its Dock layout and that
// layout's cancel come in the opening's first second).
#define kMSBDHoverHoldTouchWindow 1.0
// A hover recogniser's end that is held: only a cancel (UIGestureRecognizerStateCancelled, 4), only while the magnification shows (hovering), and not
// within the window after a touch; sinceTouch: seconds since the last one SpringBoard saw (negative: none yet).
static inline bool MSBDHoverHoldsAfter(long state, bool hovering, double sinceTouch) {
    if (!hovering || state != 4) return false;
    return sinceTouch < 0.0 || sinceTouch > kMSBDHoverHoldTouchWindow;
}
// What one look at the pointer does while held.
enum { MSBDHoverHoldEnd = 0, MSBDHoverHoldKeep, MSBDHoverHoldUIKit };
// uikitTracking: the recogniser has begun again (Began or Changed: the pointer moved); known: backboardd's place was read in its shape; attached: a trackpad
// or mouse is there; inside: the place is in the platter (MSBDHoverInside).
static inline int MSBDHoverHoldStep(bool uikitTracking, bool known, bool attached, bool inside) {
    if (uikitTracking) return MSBDHoverHoldUIKit;
    if (!known || !attached || !inside) return MSBDHoverHoldEnd;
    return MSBDHoverHoldKeep;
}
// The next look: soon after the cancel, then less often while the pointer rests (each look is one read of backboardd's place, off the main thread).
static inline double MSBDHoverHoldInterval(int looks) { return looks < 4 ? 0.12 : (looks < 12 ? 0.4 : 1.0); }
// The pointer in the platter's own space is in it: its bounds, as UIKit's hover counts them, with half a point either side (the pointer stops on whole
// pixels at a screen edge); a place that is not a number: never.
static inline bool MSBDHoverInside(CGPoint p, CGRect bounds) {
    if (!isfinite(p.x) || !isfinite(p.y) || CGRectIsNull(bounds) || CGRectIsEmpty(bounds)) return false;
    return p.x >= CGRectGetMinX(bounds) - 0.5 && p.x <= CGRectGetMaxX(bounds) + 0.5 && p.y >= CGRectGetMinY(bounds) - 0.5 && p.y <= CGRectGetMaxY(bounds) + 0.5;
}

#endif
