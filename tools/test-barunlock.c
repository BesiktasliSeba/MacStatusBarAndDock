// test-barunlock.c -- Mac test of the status bar's locked look (statusbar/BarUnlock.h, used by StatusBar.x DMBarLockedNow): the M1's wake of 30 Oct
// (1.7.1 item 11, the Cover Sheet's flags sampled every 0.25 s) gives the unlocked look from the first sample, not 2 s later; the Lock Screen and
// Notification Center keep the locked look; a SpringBoard without -isVisibleAndNotDisappearing as before; a Notification Center pull keeps the bar's
// look until it commits (1.7.4 item 3a); after a wake the windows' follow-ups (Zetsu's pills, the apps woken) start as the Cover Sheet starts to
// leave (1.7.4, engine parity).
#include <stdio.h>
#include "../statusbar/BarUnlock.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int got, int want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } else printf("PASS  %s\n", what); }
int main(void) {
    // the M1 wake (wake at 0): 0.5-1.75 s isUILocked 0, isPresented 0, isVisible 1, isVisibleAndNotDisappearing 0; from 2.05 s isVisible 0
    for (int i = 0; i < 6; i++) Expect("M1 wake, 0.5-1.75 s (the Home Screen showing, the dismissal still running): unlocked look", MSBDBarLockedLook(0, MSBDCoverSheetCoversBar(0, 0, 1)), 0);
    Expect("M1 wake, 2.05 s (the dismissal over): unlocked look", MSBDBarLockedLook(0, MSBDCoverSheetCoversBar(0, 0, 0)), 0);
    Expect("  ... before 1.7.1 the same moments gave the locked look (presented || visible)", MSBDBarLockedLook(0, MSBDCoverSheetCoversBar(-1, 0, 1)), 1);
    Expect("the Lock Screen (UI locked, the Cover Sheet shown): locked look", MSBDBarLockedLook(1, MSBDCoverSheetCoversBar(1, 1, 1)), 1);
    Expect("the Lock Screen while its dismissal starts but the UI is still locked (a passcode to come): locked look", MSBDBarLockedLook(1, MSBDCoverSheetCoversBar(0, 1, 1)), 1);
    Expect("Notification Center pulled down while unlocked: locked look", MSBDBarLockedLook(0, MSBDCoverSheetCoversBar(1, 1, 1)), 1);
    Expect("  ... pushed up (its dismissal running): unlocked look at once", MSBDBarLockedLook(0, MSBDCoverSheetCoversBar(0, 1, 1)), 0);
    Expect("Notification Center coming down (shown, not leaving): locked look", MSBDBarLockedLook(0, MSBDCoverSheetCoversBar(1, 0, 1)), 1);
    Expect("nothing over the bar: unlocked look", MSBDBarLockedLook(0, MSBDCoverSheetCoversBar(0, 0, 0)), 0);
    Expect("a SpringBoard without -isVisibleAndNotDisappearing: presented counts (as before)", MSBDCoverSheetCoversBar(-1, 1, 0), 1);
    Expect("  ... visible counts (as before)", MSBDCoverSheetCoversBar(-1, 0, 1), 1);
    Expect("  ... neither: not over the bar", MSBDCoverSheetCoversBar(-1, 0, 0), 0);
    // 1.7.4 item 3a: a Notification Center pull keeps the bar's look until it commits (a pull let go flashed the items: hidden, faded back in)
    Expect("a pull of Notification Center under way (shown, not leaving, not committed): the unlocked look stays", MSBDBarLockedLook(0, MSBDCoverSheetCoversBarPulled(MSBDCoverSheetCoversBar(1, 0, 1), 1)), 0);
    Expect("  ... before 1.7.4 the locked look came as the pull began", MSBDBarLockedLook(0, MSBDCoverSheetCoversBarPulled(MSBDCoverSheetCoversBar(1, 0, 1), 0)), 1);
    Expect("  ... the pull let go (going back, no commit to presented): still the unlocked look -- no fade", MSBDBarLockedLook(0, MSBDCoverSheetCoversBarPulled(MSBDCoverSheetCoversBar(0, 0, 1), 1)), 0);
    Expect("  ... the pull committed (Notification Center down): locked look", MSBDBarLockedLook(0, MSBDCoverSheetCoversBarPulled(MSBDCoverSheetCoversBar(1, 1, 1), 0)), 1);
    Expect("the Lock Screen keeps the locked look whatever the pull state (UI locked)", MSBDBarLockedLook(1, MSBDCoverSheetCoversBarPulled(MSBDCoverSheetCoversBar(1, 1, 1), 1)), 1);
    Expect("nothing over the bar, no pull: unlocked look", MSBDBarLockedLook(0, MSBDCoverSheetCoversBarPulled(MSBDCoverSheetCoversBar(0, 0, 0), 0)), 0);
    // the screen's own bar goes off, Stage Manager engine: a full-screen window's strip decides again (A12Z 18.5: a Notification Center pull let go left no menu bar)
    Expect("the screen's bar goes off (1.00 -> 0.00, about 0.17 s after the Cover Sheet starts to leave): the strip decides again", MSBDScreenBarWentOff(1.0, 0.0), 1);
    Expect("  ... 0.45 -> 0.00, in the pull's first frames: too", MSBDScreenBarWentOff(0.45, 0.0), 1);
    Expect("  ... still shown (1.00 -> 0.45): no", MSBDScreenBarWentOff(1.0, 0.45), 0);
    Expect("  ... coming on (0.00 -> 1.00): no, the strip's own layout hides it then", MSBDScreenBarWentOff(0.0, 1.0), 0);
    Expect("  ... off and off: no", MSBDScreenBarWentOff(0.0, 0.0), 0);
    // a copy of ours laid out without a clock (17.5.1: a pull let go left the time over the battery until the next minute)
    Expect("closed up, not locked, its time label back: laid out again", MSBDClosedUpBarLaidOutAgain(1, 1, 0), 1);
    Expect("  ... no time label yet: not yet", MSBDClosedUpBarLaidOutAgain(1, 0, 0), 0);
    Expect("  ... locked: the locked look stays", MSBDClosedUpBarLaidOutAgain(1, 1, 1), 0);
    Expect("  ... not closed up: nothing", MSBDClosedUpBarLaidOutAgain(0, 1, 0), 0);
    // the time's width in our layout (A12Z 18.5, seconds on: laid out by iOS's 40 pt the group stood 26 pt too far right)
    Expect("a label just arrived, 40 pt laid out, our text 66 pt: 66", MSBDTimeLabelWidth(40.0, 66.0) == 66.0, 1);
    Expect("  ... laid out to its text: 66", MSBDTimeLabelWidth(66.0, 66.0) == 66.0, 1);
    Expect("  ... laid out wider than its text: as laid out", MSBDTimeLabelWidth(70.0, 66.0) == 70.0, 1);
    // 1.7.4 (engine parity): the windows' follow-ups after a wake as the Cover Sheet starts to leave (the M1's wake: Zetsu's windows back 2.8 s
    // after the unlock, waiting for the Cover Sheet to be gone; Aerial's 0.9 s)
    Expect("the M1's wake: the screen was off, unlocked as the Cover Sheet starts to leave: the follow-ups run now", MSBDBackCueAtCoverLeave(1, 0, 0), 1);
    Expect("Notification Center pushed up, no screen-off since the user was last back: nothing to follow up", MSBDBackCueAtCoverLeave(0, 0, 0), 0);
    Expect("a Lock Screen with a passcode still to come (UI locked as it starts to leave): the watcher's reported unlock runs them", MSBDBackCueAtCoverLeave(1, 0, 1), 0);
    Expect("the screen off again meanwhile: nothing now", MSBDBackCueAtCoverLeave(1, 1, 0), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
