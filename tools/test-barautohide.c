// test-barautohide.c -- Mac test of Automatically Hide and Show the Menu Bar per display (common/BarAutoHide.h, 1.8.7 row 14; StatusBar.x's TV
// machine runs these very rules): two displays' states are independent, a new bar copy takes its own display's state, the Stage Manager top is the
// same with the bar hidden, and the iPad's pointer zone is not read while the pointer is on a TV's bar or strip.
#include <stdio.h>
#include <string.h>
#include "../common/BarAutoHide.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, double got, double want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %.2f, want %.2f)\n", what, got, want); } else printf("PASS  %s\n", what); }
int main(void) {
    MSBDBarAHState ipad, tv;
    memset(&ipad, 0, sizeof ipad); memset(&tv, 0, sizeof tv);
    Expect("the switch: setting on, a pointer, not locked: on", MSBDBarAHActive(1, 1, 0), 1);
    Expect("  ... no pointer attached: off", MSBDBarAHActive(1, 0, 0), 0);
    Expect("  ... the Lock Screen: off", MSBDBarAHActive(1, 1, 1), 0);
    Expect("  ... the setting off: off", MSBDBarAHActive(0, 1, 0), 0);
    // the TV on only (the iPad's off): the TV hides, the iPad's never
    MSBDBarAHSetOn(&tv, 1, 10.0);
    Expect("TV on: not hidden at once (the pointer's exit is now)", MSBDBarAHShouldHide(&tv, 0, 10.5), 0);
    Expect("TV on: hides 0.7 s after (the pointer not on it, shown long enough)", MSBDBarAHShouldHide(&tv, 0, 11.0), 1);
    tv.hidden = 1;
    Expect("  ... the iPad's, switched off, never hides", MSBDBarAHShouldHide(&ipad, 0, 11.0), 0);
    Expect("  ... its copy goes up by its height (37 pt bar)", MSBDBarAHCopyOffset(&tv, 37.0), -37.0);
    Expect("  ... the iPad's copy stays", MSBDBarAHCopyOffset(&ipad, 37.0), 0.0);
    Expect("a new TV copy comes up hidden like the TV's others (at least 24 up)", MSBDBarAHCopyOffset(&tv, 10.0), -24.0);
    Expect("a new iPad copy comes up shown while only the TV's is hidden", MSBDBarAHCopyOffset(&ipad, 24.0), 0.0);
    Expect("the strip reached: the TV's shows (it was hidden)", MSBDBarAHReveal(&tv, 12.0), 1);
    Expect("  ... the TV's shown", tv.hidden, 0);
    Expect("  ... the iPad's not touched", ipad.hidden, 0);
    MSBDBarAHPointer(&tv, 1, 12.1);
    Expect("the pointer on the TV's bar: it stays", MSBDBarAHShouldHide(&tv, 0, 20.0), 0);
    MSBDBarAHPointer(&tv, 0, 20.0);
    Expect("  ... left it: not before 0.7 s", MSBDBarAHShouldHide(&tv, 0, 20.5), 0);
    Expect("  ... then it hides", MSBDBarAHShouldHide(&tv, 0, 20.8), 1);
    Expect("a menu open from the TV's bar holds it shown", MSBDBarAHShouldHide(&tv, 1, 30.0), 0);
    Expect("shown at least 1 s after it was brought, even with the pointer gone", (MSBDBarAHReveal(&tv, 40.0), MSBDBarAHShouldHide(&tv, 0, 40.9)), 0);
    tv.hidden = 1;
    Expect("the TV's switched off while hidden: shown (returns 1)", MSBDBarAHSetOn(&tv, 0, 50.0), 1);
    Expect("  ... shown", tv.hidden, 0);
    Expect("  ... off: never hides", MSBDBarAHShouldHide(&tv, 0, 60.0), 0);
    Expect("  ... off: the strip brings nothing", MSBDBarAHReveal(&tv, 61.0), 0);
    // and the other way round: the iPad on only, the TV's off
    memset(&ipad, 0, sizeof ipad); memset(&tv, 0, sizeof tv);
    MSBDBarAHSetOn(&ipad, 1, 100.0);
    Expect("the iPad on only: the iPad's hides", MSBDBarAHShouldHide(&ipad, 0, 101.0), 1);
    ipad.hidden = 1;
    Expect("  ... the TV's never hides", MSBDBarAHShouldHide(&tv, 0, 101.0), 0);
    Expect("  ... a TV copy stays shown", MSBDBarAHCopyOffset(&tv, 24.0), 0.0);
    Expect("  ... an iPad copy goes up", MSBDBarAHCopyOffset(&ipad, 24.0), -24.0);
    // both on: each by its own pointer
    memset(&ipad, 0, sizeof ipad); memset(&tv, 0, sizeof tv);
    MSBDBarAHSetOn(&ipad, 1, 200.0); MSBDBarAHSetOn(&tv, 1, 200.0);
    MSBDBarAHPointer(&tv, 1, 200.1);
    Expect("both on, the pointer on the TV's bar: the iPad's hides", MSBDBarAHShouldHide(&ipad, 0, 201.0), 1);
    Expect("  ... the TV's stays", MSBDBarAHShouldHide(&tv, 0, 201.0), 0);
    // windows: as the iPad's Stage Manager engine -- the top keeps the bar's room
    Expect("Stage Manager top with the TV's 37 pt bar shown: 37 + 24", MSBDBarAHStageTop(37.0, 24.0, 0), 61.0);
    Expect("  ... hidden: the same (no window moves)", MSBDBarAHStageTop(37.0, 24.0, 1), 61.0);
    // the iPad's pointer zone while the pointer is on a TV's bar or strip
    Expect("the iPad's zone: the pointer on the TV's top (global position reads as the iPad's top edge, 1): below the bar (3)", (double)MSBDBarAHIPadZone(1, 1), 3);
    Expect("  ... over the bar (2): below the bar (3)", (double)MSBDBarAHIPadZone(2, 1), 3);
    Expect("  ... not known (0) stays not known", (double)MSBDBarAHIPadZone(0, 1), 0);
    Expect("  ... the pointer not on a TV's bar: as read", (double)MSBDBarAHIPadZone(1, 0), 1);
    // a hover that ends with the pointer still well inside the bar: iPadOS hid the idle pointer (A12Z, d07), not a leave
    Expect("hover ended, the pointer last seen inside the 37 pt bar (x 1200, y 0): may be a fade", MSBDBarAHEndIsFade(1200, 0, 2560, 37), 1);
    Expect("  ... last seen at y 20: may be a fade", MSBDBarAHEndIsFade(1200, 20, 2560, 37), 1);
    Expect("  ... last seen near its bottom edge (y 33): a leave", MSBDBarAHEndIsFade(1200, 33, 2560, 37), 0);
    Expect("  ... last seen below it (y 40): a leave", MSBDBarAHEndIsFade(1200, 40, 2560, 37), 0);
    Expect("  ... last seen at a side (x 2557): a leave", MSBDBarAHEndIsFade(2557, 10, 2560, 37), 0);
    Expect("  ... UIKit's end place {0, 0}: a leave (never used: the last place seen is)", MSBDBarAHEndIsFade(0, 0, 2560, 37), 0);
    Expect("  ... no bar size: a leave", MSBDBarAHEndIsFade(10, 10, 0, 0), 0);
    Expect("after a fade: moved 1 pt (a jitter): still there", MSBDBarAHMovedAfterFade(1, 1), 0);
    Expect("after a fade: moved 3 pt: it left", MSBDBarAHMovedAfterFade(3, 0), 1);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
