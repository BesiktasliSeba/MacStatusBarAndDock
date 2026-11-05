// test-overlayclose.c -- Mac test of when Spotlight closes an open menu, dialog or question of ours (statusbar/OverlayClose.h, StatusBar.x's
// tick): a Spotlight that comes up over it, never the one a pick in it opened Fit's side question from while that one goes away (1.8.1 item 11: the
// question for an app picked in Spotlight closed 0.45 s later, the default arrangement without a choice). Run by test-overlayclose.sh.
#include <stdio.h>
#include "../statusbar/OverlayClose.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
// The tick as StatusBar.x runs it for Spotlight alone (0.2 s apart; two ticks in a row close): the tick at which the overlay closes, -1 never.
static int ClosesAt(int openedOver, const int *shown, int n) {
    int from = openedOver, run = 0;
    for (int i = 0; i < n; i++) {
        from = MSBDSpotlightStillFromOpen(shown[i], from);
        if (MSBDSpotlightCameUp(shown[i], from)) { if (++run >= 2) return i; } else run = 0;
    }
    return -1;
}
int main(void) {
    Expect("the Spotlight a pick opened the question from, on its way out: not one coming up", MSBDSpotlightCameUp(1, 1) == 0);
    Expect("Spotlight brought up over an open menu: it came up", MSBDSpotlightCameUp(1, 0) == 1);
    Expect("no Spotlight: nothing came up", MSBDSpotlightCameUp(0, 0) == 0 && MSBDSpotlightCameUp(0, 1) == 0);
    Expect("that Spotlight gone: forgotten", MSBDSpotlightStillFromOpen(0, 1) == 0 && MSBDSpotlightStillFromOpen(1, 1) == 1 && MSBDSpotlightStillFromOpen(1, 0) == 0);
    int dismissal[] = { 1, 1, 1, 0, 0, 0, 0, 0, 0, 0 };   // (the question asked during Spotlight's 0.45 s dismissal, M1 15.6.1)
    Expect("the side question asked while Spotlight goes away stays up (it waits for the answer)", ClosesAt(1, dismissal, 10) == -1);
    int later[] = { 1, 1, 0, 0, 0, 1, 1, 1, 0, 0 };   // (that Spotlight goes; the user brings Spotlight up again over the question)
    Expect("  ... a Spotlight brought up later over it still closes it, on the second tick", ClosesAt(1, later, 10) == 6);
    int over[] = { 0, 0, 1, 1, 1, 0 };   // (a menu open, then Spotlight comes up: as before 1.8.1)
    Expect("a menu open when Spotlight comes up: closed on the second tick, as before", ClosesAt(0, over, 6) == 3);
    int menu[] = { 1, 1, 1, 1 };   // (a menu of the bar opened over Spotlight notes nothing: as before 1.8.1)
    Expect("a menu of the bar opened while Spotlight is up: closed on the second tick, as before", ClosesAt(0, menu, 4) == 1);
    int blip[] = { 0, 1, 0, 1, 0, 0 };   // (a passing reading: never two ticks in a row)
    Expect("a passing reading does not close it", ClosesAt(0, blip, 6) == -1);
    // Notification Center (code review 1.8.1, 1): the side question for what was tapped there while unlocked comes while the Cover Sheet goes away
    Expect("the Cover Sheet a tap in Notification Center opened the question from, on its way out: not one coming up", MSBDCoverSheetCameUp(1, 1) == 0);
    Expect("Notification Center pulled down over an open menu or question: it came up", MSBDCoverSheetCameUp(1, 0) == 1);
    Expect("  ... none: nothing came up", MSBDCoverSheetCameUp(0, 0) == 0 && MSBDCoverSheetCameUp(0, 1) == 0);
    Expect("  ... that Cover Sheet gone: forgotten, one pulled down later closes it", MSBDCoverSheetStillFromOpen(0, 1) == 0 && MSBDCoverSheetStillFromOpen(1, 1) == 1 && MSBDCoverSheetStillFromOpen(1, 0) == 0);
    printf("overlayclose: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
