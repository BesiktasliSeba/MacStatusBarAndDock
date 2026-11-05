// TapRule.h -- which finger touch in a window that is not in front brings it forward: a tap, on every engine (1.8.1, GitHub #10 after 1.7.9.2).
// Plain C, so the Mac test (tools/test-taprule.c) runs this very code; appbridge/AppBridge.x (every app: its tap brings an Aerial or Zetsu window
// forward, StatusBar.x DMRaiseStageForBundle) and StatusBar.x (the Stage Manager engine, DMSMActivateOnTouch) share it.
// Why: a slide in a window behind another one brought it forward with the Stage Manager engine only (its own rule, at the finger's lift), so a
// scroll in a big window sent the small window in front of it away; with Aerial and Zetsu a slide or a scroll leaves the windows where they are
// and only a tap brings one forward, as Stage Manager's own tap-to-front does and as a scroll on a Mac leaves a window behind.
//  - A tap: the finger lifted less than kMSBDTapSlop points from where it went down, less than kMSBDTapMaxSeconds after (a long press is not one).
//  - A touch on the menu bar is never a window's (MSBDSMTouchOutcome): with a window in full screen the menu bar is that window's own status bar
//    strip, inside its card, and a tap on it was taken for a tap on the full-screen window.
//  - A tap on a full-screen window that windows of its stage are in front of leaves them there and makes it the active window where it is, as a tap
//    on a full-screen app behind windows does with Aerial and Zetsu (the menu bar's app, the keyboard): StatusBar.x DMSMFullScreenActivate.
#ifndef MSBD_TAP_RULE_H
#define MSBD_TAP_RULE_H
#include <stdbool.h>

#define kMSBDTapSlop 12.0
#define kMSBDTapMaxSeconds 0.8

// moved: how far the finger is from where it went down (points); seconds: since it went down.
static inline bool MSBDTapLike(double moved, double seconds) {
    return moved >= 0.0 && moved < kMSBDTapSlop && seconds >= 0.0 && seconds < kMSBDTapMaxSeconds;
}
// The Stage Manager engine's touch in a window that is not the active one, at the finger's lift: nothing unless it was a tap that did not start on
// the menu bar; then that window comes forward -- unless it is the stage's full-screen window with windows in front of it: active where it is.
enum { kMSBDSMTouchNothing = 0, kMSBDSMTouchForward = 1, kMSBDSMTouchActiveInPlace = 2 };
static inline int MSBDSMTouchOutcome(bool startedOnMenuBar, bool fullScreenUnderWindows, double moved, double seconds) {
    if (startedOnMenuBar || !MSBDTapLike(moved, seconds)) return kMSBDSMTouchNothing;
    return fullScreenUnderWindows ? kMSBDSMTouchActiveInPlace : kMSBDSMTouchForward;
}
#endif
