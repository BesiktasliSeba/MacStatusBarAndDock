// A5LockCatch.h -- what a round-icon catch makes of a window (StatusBar.x DMAerial5CatchChip): Aerial 5 minimized it to its round icon ("chip"),
// we hid it at once; this says whether it comes back by itself (after the unlock, or once Aerial is done) or stays as it was. Plain C, so the Mac
// test (tools/test-a5lockcatch.c) runs this very rule.
// 1.7.9 regression G-4b (M1 15.6.1, Aerial 5.1): Aerial 5 minimizes EVERY one of its windows as the screen locks -- the ones on screen, and the
// ones we keep hidden too: minimized our way (the yellow light, Home Minimizes Windows, Minimize All, the Window menu) or on another Mac Switcher
// desktop. The lock's catch took every window it found for one that had been on screen, so a lock and an unlock brought the user's minimized
// windows back (Home Minimizes Windows, on for everyone in 1.7.9, made that the common case). Now a window hidden by us before Aerial's minimize
// stays as it was: only Aerial's own state is put back behind our hide (its own restore, the frame checked), so it opens at its frame later.
#ifndef MSBD_A5_LOCK_CATCH_H
#define MSBD_A5_LOCK_CATCH_H

enum {
    MSBDA5CatchHide  = 0,        // into our minimize, back from its Dock icon (Aerial's own minimize of an open window: its menu, a swipe)
    MSBDA5CatchLock  = 1 << 0,   // hidden for the lock: back after the unlock (DMAerial5RestoreAfterLock)
    MSBDA5CatchBack  = 1 << 1,   // back by itself as soon as Aerial is done (just after the unlock, on its way back, or shown meanwhile)
    MSBDA5CatchAgain = 1 << 2,   //   ... the second time it is back after the unlock: the last time (never a minimize-and-back loop)
    MSBDA5CatchKeep  = 1 << 3,   // hidden by us already: stays as it was (minimized our way, or on its desktop), Aerial's state put back behind
};
#define MSBD_A5_JUST_UNLOCKED 0.5   // a window caught this soon after the unlock was open before the lock (Aerial minimizes them once more then)
#define MSBD_A5_AGAIN_WITHIN 1.0    // ... and one caught this soon after the unlock's follow showed it back is on its way back too

// hiddenOurs: it was in our minimized state already (kStageHiddenKey) -- or still is, from an earlier catch; away: on another Mac Switcher desktop
// (kMSWAwayKey); lockHidden: the lock's catch hid it and the unlock has not brought it back yet (kA5LockHiddenKey); follow: an earlier catch is
// still being undone (0 none, 1 one that stays hidden, 2 one that comes back); locked: the UI is locked (-isUILocked); sinceUnlock: seconds since the
// screen was last unlocked, sinceShownBack: since the unlock's follow showed it back (each -1: never).
static inline int MSBDA5CatchRole(int hiddenOurs, int away, int lockHidden, int follow, int locked, double sinceUnlock, double sinceShownBack) {
    int comingBack = lockHidden || follow == 2;   // (the lock's, on its way back: Aerial minimized it once more meanwhile)
    if (!comingBack && (hiddenOurs || away)) return MSBDA5CatchKeep;
    if (locked) return MSBDA5CatchLock | (follow == 2 ? MSBDA5CatchBack : 0);
    int justUnlocked = sinceUnlock >= 0 && sinceUnlock < MSBD_A5_JUST_UNLOCKED;
    int again = !justUnlocked && sinceShownBack >= 0 && sinceShownBack < MSBD_A5_AGAIN_WITHIN;
    // (follow 1 and no longer hidden by us: shown while Aerial's minimize was being undone -- its desktop came back: it stays shown, once Aerial is done)
    int back = justUnlocked || comingBack || again || (follow == 1 && !hiddenOurs);
    return back ? (MSBDA5CatchBack | (again ? MSBDA5CatchAgain : 0)) : MSBDA5CatchHide;
}

#endif
