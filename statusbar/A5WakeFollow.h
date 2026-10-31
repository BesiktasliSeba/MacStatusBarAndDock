// A5WakeFollow.h -- the steps after Aerial 5 minimized a window to its round icon ("chip") and we hid it (StatusBar.x DMAerial5CatchChip ->
// DMA5FollowStep), plain C so the Mac test (tools/test-a5wake.c) runs this very rule.
// 1.7.4 item 3e (M1 15.6.1, Aerial 5.1): after a wake Aerial has every window minimized as the unlock comes; they came back 1.64 s after it, all
// of it fixed waits of ours -- Aerial's restore asked at 0.6 s, the frame checked at 1.4 s, the window shown at 1.6 s. Each step now follows
// Aerial itself, display frame by display frame:
//  1. Aerial's minimize animation has run out (its end sets the chip's frame: a restore asked before it left the window at the chip's size)
//     -> Aerial's own restore is asked.
//  2. Aerial's restore has run out (the window no longer minimized, nothing of Aerial's animating on it) -> its frame is checked (put back where
//     it was put, if Aerial left it elsewhere).
//  3. A window that comes back by itself (open before the lock) is shown: at once -- or, as before, 0.2 s after the check when it had to put the
//     frame back (the app gets its size first) or Aerial was not seen to finish (the check at its limit, or the window still minimized).
// "Run out": two display frames in a row with no animation of Aerial's on the window. Each step keeps its old fixed wait as its upper limit (0.6 s,
// then 0.8 s, then 0.2 s, each from the step before: a display frame or two over the old 1.6 s at the very most, when Aerial is never seen to finish).
#ifndef MSBD_A5_WAKE_FOLLOW_H
#define MSBD_A5_WAKE_FOLLOW_H

enum { MSBDA5FollowShrinking = 0, MSBDA5FollowRestoring = 1, MSBDA5FollowChecked = 2 };          // where the window is
enum { MSBDA5Wait = 0, MSBDA5Restore = 1, MSBDA5Check = 2, MSBDA5Show = 3, MSBDA5End = 4 };      // what to do now
#define MSBD_A5_QUIET_FRAMES 2              // display frames in a row without Aerial's animations: it has run out
#define MSBD_A5_SHRINK_LIMIT 0.6            // the old fixed times, now the upper limits: Aerial's restore 0.6 s after the catch,
#define MSBD_A5_RESTORE_LIMIT 0.8           //   the frame check 0.8 s after that (1.4 s),
#define MSBD_A5_SETTLE 0.2                  //   the window back 0.2 s after that (1.6 s) -- now only after a check that needs it (settle)

// phase: where the window is; inPhase: seconds since that phase began; quiet: display frames in a row with none of Aerial's animations on the
// window; chip: Aerial still has it minimized; back: it comes back by itself; settle: the check put the frame back or Aerial was not seen to finish.
static inline int MSBDA5FollowNext(int phase, double inPhase, int quiet, int chip, int back, int settle) {
    inPhase += 1e-6;   // (display frame times: 1.4 - 0.6 is a hair under 0.8)
    switch (phase) {
        case MSBDA5FollowShrinking: return (quiet >= MSBD_A5_QUIET_FRAMES || inPhase >= MSBD_A5_SHRINK_LIMIT) ? MSBDA5Restore : MSBDA5Wait;
        case MSBDA5FollowRestoring: return ((!chip && quiet >= MSBD_A5_QUIET_FRAMES) || inPhase >= MSBD_A5_RESTORE_LIMIT) ? MSBDA5Check : MSBDA5Wait;
        case MSBDA5FollowChecked:
            if (!back) return MSBDA5End;   // (not one to bring back now: one caught while locked comes back with the unlock, one Aerial
                                           //  minimized while open stays minimized our way, back from its Dock icon)
            return (!settle || inPhase >= MSBD_A5_SETTLE) ? MSBDA5Show : MSBDA5Wait;
        default: return MSBDA5End;
    }
}

#endif
