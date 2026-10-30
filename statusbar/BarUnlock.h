// BarUnlock.h -- when the status bar takes its locked look (StatusBar.x DMBarLockedNow / DMCoverSheetCoversBarOf), plain C so the Mac test
// (tools/test-barunlock.c) runs this very rule.
//  - Locked look (the Apple menu and the status icons only: no traffic lights, no menu titles): the UI is locked, or the Cover Sheet (the Lock
//    Screen, or Notification Center pulled down) is over the bar.
//  - The Cover Sheet is over the bar while it shows and is NOT on its way out (SpringBoard's -isVisibleAndNotDisappearing). 1.7.1 item 11 (KT, M1:
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

#endif
