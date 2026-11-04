// SMGestureCap.h -- how long the Stage Manager engine's gesture hold (SMGestureHold.h) waits for a window's live resize that SpringBoard never
// completes (1.8.0 item 7). Plain C: SMGestureHold.h asks it, the Mac test tools/test-smgesturecap.sh runs this very code.
// Seen once on 18.5 (A12Z, 3 Nov): after a corner drag SpringBoard's own SBLiveWindowResizeGestureWorkspaceTransaction stayed "Completed: NO" for
// 350 s -- not interruptible, no life assertions, no milestones pending, its scene update done -- until a display cycle ended it, and all that time
// the hold kept that stage's writes waiting (a Dock tap's bring-to-front would have waited too). The same drag again ended in 912 ms. A live resize
// is the window's own gesture: once its finger has been up for kMSBDGestureLiftedCap, its transaction no longer holds the stage and the writes it
// held run. Every other gesture's transaction (the Home gesture's: the stage it took under the finger must not leave the switcher's list while its
// modifier looks for it -- issue #7) is waited for as before, however long.
#pragma once

static const double kMSBDGestureLiftedCap = 3.0;   // (seconds after the finger lifted: a resize transaction ends well within a second of it)

// The finger of a live resize, from its own recognizer's state: down while it began or changed (UIGestureRecognizerStateBegan 1, Changed 2), up in
// any other state. readable: the transaction has a recognizer that answers -state; none (a pointer or trackpad corner drag may come with none) or
// one without it counts as down -- read as up, the cap let the hold go 3 s after such a resize began, mid-drag (code review 1.8.0, 5).
static inline int MSBDGestureFingerDown(int readable, long long state) { return !readable || state == 1 || state == 2; }

// When the finger was first seen up for a transaction: 0 while it is down (a new gesture in the same transaction starts it again).
static inline double MSBDGestureUpSince(int fingerDown, double upSince, double now) { return fingerDown ? 0 : (upSince > 0 ? upSince : now); }

// The transaction still holds its stage: SpringBoard has not completed it, and it is not a live resize whose finger has been up for the cap. A
// transaction whose finger cannot be read counts as down (never let go early).
static inline int MSBDGestureTxHolds(int complete, int liveResize, int fingerDown, double upSince, double now) {
    if (complete) return 0;
    if (!liveResize || fingerDown || upSince <= 0) return 1;
    return now - upSince < kMSBDGestureLiftedCap;
}
