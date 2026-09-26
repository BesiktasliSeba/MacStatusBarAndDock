// Reduce Motion (Settings > Accessibility > Motion), shared by the parts that animate.
// With it on, our zooms, flights, slides and springs become short cross-fades (opacity animates on the render server, no per-frame work of
// ours), with at most a tiny scale where a pure fade looks flat, like Apple's own Reduce Motion transitions. Positions that must change
// (a window tiled by Fit or the Window menu) still move, but as one short ease-in-out without a spring. UIAccessibilityIsReduceMotionEnabled
// is read live on every animation (UIKit caches it and updates it on the system's change notification), so a change applies to the next
// animation without a respring. Dock magnification is not affected (its own switch).
#pragma once
#import <UIKit/UIKit.h>

static const NSTimeInterval kMSBRMDuration = 0.22;   // one duration for every reduced transition: short, ease-in-out
static const CGFloat kMSBRMScale = 0.98;             // the "tiny scale" that goes with a fade where a pure fade looks flat

static inline BOOL MSBReduceMotion(void) { return UIAccessibilityIsReduceMotionEnabled(); }

// Runs the animation as it was designed (spring when damping > 0, otherwise the given curve), or with Reduce Motion on as one
// kMSBRMDuration ease-in-out without a spring and without the delay (a stagger makes a cross-fade look slow). The caller chooses the start
// state (a smaller scale or no offset) for the reduced case.
static inline void MSBAnimate(NSTimeInterval duration, NSTimeInterval delay, CGFloat damping, UIViewAnimationOptions options,
                              void (^animations)(void), void (^completion)(BOOL)) {
    if (MSBReduceMotion()) {
        UIViewAnimationOptions keep = options & (UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction);
        [UIView animateWithDuration:kMSBRMDuration delay:0 options:keep | UIViewAnimationOptionCurveEaseInOut animations:animations completion:completion];
        return;
    }
    if (damping > 0.0) [UIView animateWithDuration:duration delay:delay usingSpringWithDamping:damping initialSpringVelocity:0 options:options animations:animations completion:completion];
    else [UIView animateWithDuration:duration delay:delay options:options animations:animations completion:completion];
}
