// SMFrontRule.h -- which window of a Stage Manager stage a finger's resize corner and an app's launch are for, plain C on CoreGraphics so the Mac test
// (tools/test-smfront.c) runs this very code (1.7.9.2, GitHub #10 follow-up; used by SMResizeEdges.h and StatusBar.x):
//  - a window's corner takes a finger only where no window in front of it covers the spot (MSBDSMCoveredAt): Stage Manager itself picks the window
//    whose corner is nearest the finger, in front or behind, and a covered window's corner took the drag through the window in front of it;
//  - a window is in front of its stage when it is newer than every other window there (MSBDSMNewestAlone): two windows at the same interaction
//    time are not in front of each other (iPadOS 16.3.1 can leave a tie, and the stage then keeps their old order).
#ifndef MSBD_SM_FRONT_RULE_H
#define MSBD_SM_FRONT_RULE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

// p (in the same points as the areas) is covered for a window when one of the n windows in front of it holds it there: each area is that window as
// drawn, its card with our title bar above it. A null area is no window.
static inline bool MSBDSMCoveredAt(CGPoint p, const CGRect *inFront, int n) {
    for (int i = 0; i < n; i++) if (!CGRectIsNull(inFront[i]) && CGRectContainsPoint(inFront[i], p)) return true;
    return false;
}
// The window at index i of the stage's n windows (their interaction times) is in front: newer than every other one, none as new.
static inline bool MSBDSMNewestAlone(const long long *times, int n, int i) {
    if (!times || i < 0 || i >= n) return false;
    for (int j = 0; j < n; j++) if (j != i && times[j] >= times[i]) return false;
    return true;
}
#endif
