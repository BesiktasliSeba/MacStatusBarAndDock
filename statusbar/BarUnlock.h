// BarUnlock.h -- when the status bar takes its locked look (StatusBar.x DMBarLockedNow / DMCoverSheetCoversBarOf), plain C so the Mac test
// (tools/test-barunlock.c) runs this very rule.
//  - Locked look (the Apple menu and the status icons only: no traffic lights, no menu titles): the UI is locked, or the Cover Sheet (the Lock
//    Screen, or Notification Center pulled down) is over the bar.
//  - The Cover Sheet is over the bar while it shows and is NOT on its way out (SpringBoard's -isVisibleAndNotDisappearing), and not while a pull of
//    Notification Center has not committed yet (1.7.4: a pull let go flashed the bar's items). 1.7.1 item 11 (KT, M1:
//    our items came back late after an unlock): it counted while -isPresented or -isVisible, which stay YES until the dismissal has finished -- 2 s
//    after a wake on the M1, the Home Screen showing from 0.5 s. A SpringBoard without -isVisibleAndNotDisappearing: as before.
#ifndef MSBD_BAR_UNLOCK_H
#define MSBD_BAR_UNLOCK_H

// visibleNotLeaving: -isVisibleAndNotDisappearing (1 / 0, -1 when SpringBoard has no such call); presented, visible: -isPresented, -isVisible.
static inline int MSBDCoverSheetCoversBar(int visibleNotLeaving, int presented, int visible) {
    if (visibleNotLeaving >= 0) return visibleNotLeaving ? 1 : 0;
    return (presented || visible) ? 1 : 0;
}
static inline int MSBDBarLockedLook(int uiLocked, int coverOverBar) { return (uiLocked || coverOverBar) ? 1 : 0; }
// A Notification Center pull that has not committed (pulling: the user's present gesture began, no commit yet): the Cover Sheet is not over the bar
// yet, whatever it says -- the bar keeps its look until the pull commits, so a pull let go changes nothing (1.7.4 item 3a: it flashed).
static inline int MSBDCoverSheetCoversBarPulled(int covers, int pulling) { return (covers && !pulling) ? 1 : 0; }
// The user back after the screen was off: the windows' follow-ups -- the windows Zetsu collapsed on lock opened again (0.4 s later, as at a
// reported unlock: the Cover Sheet is still on its way up), every window's app woken -- start as the Cover Sheet starts to leave, when the screen
// has been off since the user was last back and the UI is unlocked by then. 1.7.4 (engine parity): they waited for the 0.25 s watcher to see
// the unlock, which it does not when the lock came and went while it was parked with the screen off (the M1: 5 of 7 wakes measured), and then
// for the Cover Sheet to be gone, which -isVisible says only at the end of the M1's 2 s dismissal (1.7.1 item 11's cause): Zetsu's windows were
// back 2.8 s after the unlock, Aerial's 0.9 s. Still locked as it starts to leave (a passcode to come): the watcher's reported unlock runs them.
static inline int MSBDBackCueAtCoverLeave(int offSinceBack, int screenOff, int uiLocked) { return (offSinceBack && !screenOff && !uiLocked) ? 1 : 0; }

#endif
