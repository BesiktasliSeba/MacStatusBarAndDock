// test-barunlock.c -- Mac test of the status bar's locked look (statusbar/BarUnlock.h, used by StatusBar.x DMBarLockedNow): the M1's wake of 30 Oct
// (1.7.1 item 11, the Cover Sheet's flags sampled every 0.25 s) gives the unlocked look from the first sample, not 2 s later; the Lock Screen and
// Notification Center keep the locked look; a SpringBoard without -isVisibleAndNotDisappearing as before.
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
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
