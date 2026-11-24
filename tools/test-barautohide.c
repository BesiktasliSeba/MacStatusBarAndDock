// test-barautohide.c -- Mac test of Automatically Hide and Show the Menu Bar per display (common/BarAutoHide.h, 1.8.7 row 14; StatusBar.x's TV
// machine runs these very rules): two displays' states are independent, a new bar copy takes its own display's state, the Stage Manager top of a TV is
// the same with its bar hidden, and the iPad's pointer zone is not read while the pointer is on a TV's bar or strip. 1.8.8.4: the iPad's own screen's
// one window top for every engine while the bar hides itself (the top, our Stage Manager engine's stage top and a pass's, the retop, the title slide).
#include <stdio.h>
#include <string.h>
#include <math.h>
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
    // ---- 1.8.8.4: the iPad's own screen, one window top for every engine while the bar hides itself (engine parity, item 5) ----
    Expect("window top: under the 24 pt bar while it shows", MSBDBarAHWindowTop(24.0, 0), 24.0);
    Expect("  ... the screen's top edge while it hides itself (as on a Mac)", MSBDBarAHWindowTop(24.0, 1), 0.0);
    Expect("  ... a Home-button iPad's 20 pt bar: 20, and 0", MSBDBarAHWindowTop(20.0, 0) + 100.0 * MSBDBarAHWindowTop(20.0, 1), 20.0);
    Expect("our Stage Manager engine's stage top: iOS's 24 raised to our 24 pt bar, our 24 pt title bar under it: 48", MSBDBarAHSMStageTop(24.0, 24.0, 24.0, 0), 48.0);
    Expect("  ... while the bar hides itself: the title bar at the top edge, the window under it at 24", MSBDBarAHSMStageTop(24.0, 24.0, 24.0, 1), 24.0);
    Expect("  ... a Home-button iPad (iOS's 20, our bar 20): 44, and 24 while it hides", MSBDBarAHSMStageTop(20.0, 20.0, 24.0, 0) + 100.0 * MSBDBarAHSMStageTop(20.0, 20.0, 24.0, 1), 2444.0);
    Expect("  ... Menu Bar Size Large (our 37 over iOS's 24): 61, and 24 while it hides", MSBDBarAHSMStageTop(24.0, 37.0, 24.0, 0) + 100.0 * MSBDBarAHSMStageTop(24.0, 37.0, 24.0, 1), 2461.0);
    Expect("our answer: either top is ours (48 and 24), Apple's own 60 is not", MSBDBarAHIsOurTop(48.0, 24.0, 24.0, 24.0, 1) * 100 + MSBDBarAHIsOurTop(24.0, 24.0, 24.0, 24.0, 1) * 10 + MSBDBarAHIsOurTop(60.0, 24.0, 24.0, 24.0, 1), 110.0);
    Expect("  ... 24 is ours only once the lowered answer was given (it is also iOS's own status bar height): before, 48 alone", MSBDBarAHIsOurTop(48.0, 24.0, 24.0, 24.0, 0) * 10 + MSBDBarAHIsOurTop(24.0, 24.0, 24.0, 24.0, 0), 10.0);
    Expect("  ... a pass at 24 with the bar never hidden by our engine: as it is (no number changes with auto-hide never on)", MSBDBarAHPassTop(24.0, 24.0, 24.0, 24.0, 0, 0, 0, 1, 24.0), 24.0);
    Expect("the iPad's pass carrying 48 while the bar hides itself (attributes made before the switch): 24", MSBDBarAHPassTop(48.0, 24.0, 24.0, 24.0, 1, 1, 0, 1, 24.0), 24.0);
    Expect("  ... carrying 24 with the bar shown again: 48", MSBDBarAHPassTop(24.0, 24.0, 24.0, 24.0, 0, 1, 0, 1, 24.0), 48.0);
    Expect("  ... carrying the top for now: as it is", MSBDBarAHPassTop(24.0, 24.0, 24.0, 24.0, 1, 1, 0, 1, 24.0), 24.0);
    Expect("  ... a top of Apple's own (60): as it is", MSBDBarAHPassTop(60.0, 24.0, 24.0, 24.0, 1, 1, 0, 1, 24.0), 60.0);
    Expect("a TV's pass carrying the iPad's lowered 24 (the iPad's bar hiding), its bar the iPad's size: the room as before, 48", MSBDBarAHPassTop(24.0, 24.0, 24.0, 24.0, 1, 1, 1, 1, 24.0), 48.0);
    Expect("  ... carrying 48 with the iPad's bar shown: 48 (as before 1.8.8.4)", MSBDBarAHPassTop(48.0, 24.0, 24.0, 24.0, 0, 1, 1, 1, 24.0), 48.0);
    Expect("  ... its 37 pt bar (another size), the iPad's bar hiding: 37 + 24", MSBDBarAHPassTop(24.0, 24.0, 24.0, 24.0, 1, 1, 1, 0, 37.0), 61.0);
    Expect("  ... its 37 pt bar, the iPad's shown: 61 (as 1.8.7 R6)", MSBDBarAHPassTop(48.0, 24.0, 24.0, 24.0, 0, 1, 1, 0, 37.0), 61.0);
    Expect("  ... a Home-button iPad's 20 pt bar, the TV's 24 at its size: the iPad's room 44, the bar hiding or not", MSBDBarAHPassTop(24.0, 20.0, 20.0, 24.0, 1, 1, 1, 1, 24.0) + 100.0 * MSBDBarAHPassTop(44.0, 20.0, 20.0, 24.0, 0, 1, 1, 1, 24.0), 4444.0);
    Expect("  ... a top of Apple's own on the TV: as it is", MSBDBarAHPassTop(90.0, 24.0, 24.0, 24.0, 1, 1, 1, 0, 37.0), 90.0);
    Expect("  ... no number: as it is (not ours)", MSBDBarAHIsOurTop(NAN, 24.0, 24.0, 24.0, 1), 0.0);
    {   // the retop: one rule for every engine (StatusBar.x DMAutoHideRetopAll and DMAutoHideSMRetop)
        double y, h; int r;
        y = 24; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0);
        Expect("retop, the room given: a window at the bar's line (24) goes up to 0, its size kept", r * 10000 + y * 1000 + h, 10400.0);
        y = 22; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... 22 (within 2 of 23.5): up to 0", r * 10 + y, 10.0);
        y = 26; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... 26 (2.5 off the line): stays", r * 10000 + y * 100 + h, 3000.0);
        y = 200; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... lower on the screen: stays", r, 0.0);
        y = 24; h = 881; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... a full-height one (24..905, Fill): to 0..905, its bottom kept", r * 10000 + y * 1000 + h, 10905.0);
        y = 24; h = 879; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... ending 2 pt short of the bottom (full height within 3): to 0..905", y * 1000 + h, 905.0);
        y = 24; h = 1100; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... one behind the Dock (24..1124): to 0..1100, its height kept (as DMAutoHideRetopAll since 1.7.x)", y * 10000 + h, 1100.0);
        y = 40; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 1); Expect("  ... turned, it was at the top, now at 40: back up to 0", r * 10 + y, 10.0);
        y = 70; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 1); Expect("  ... turned, now at 70: stays", r, 0.0);
        y = 0; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... at the top edge already: stays", r, 0.0);
        y = 0; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 0, 0); Expect("retop, the room taken back: a window at 0 goes under the bar, its size kept", r * 100000 + y * 1000 + h, 124400.0);
        y = 21; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 0, 0); Expect("  ... at 21 (in the bar's room): under it, 24", r * 100 + y, 124.0);
        y = 23; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 0, 0); Expect("  ... at 23 (above 22: already about under it): stays", r, 0.0);
        y = 0; h = 905; r = MSBDBarAHRetop(&y, &h, 905, 24, 0, 0); Expect("  ... a full-height one (0..905): 24..905, its bottom kept", y * 1000 + h, 24881.0);
        y = 0; h = 1124; r = MSBDBarAHRetop(&y, &h, 905, 24, 0, 0); Expect("  ... behind the Dock (0..1124): 24..1124, its bottom kept", y * 10000 + h, 241100.0);
        y = 24; h = 1100;   // (the window behind the Dock, on and off: 24 pt shorter, as on Aerial, Zetsu and MilkyWay4 since 1.7.x -- a question for KT, not changed here)
        MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); MSBDBarAHRetop(&y, &h, 905, 24, 0, 0);
        Expect("  ... behind the Dock, one on / off cycle: 24..1100 (its bottom 24 pt up, as the other engines' rule has it)", y * 10000 + h, 241076.0);
        y = 20; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 20, 1, 0); Expect("  ... a Home-button iPad's 20 pt bar: its line 19.5, up to 0", r * 10 + y, 10.0);
        y = 0; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 20, 0, 0); Expect("  ... and back under it at 20", y, 20.0);
        y = NAN; h = 400; r = MSBDBarAHRetop(&y, &h, 905, 24, 1, 0); Expect("  ... no number: nothing", r, 0.0);
        Expect("  ... no place to write to: nothing", MSBDBarAHRetop(NULL, &h, 905, 24, 1, 0), 0.0);
    }
    // the title bar's slide while the bar shows (every engine's: the window stays, only its title bar slides)
    Expect("slide: a window at the top edge (0), the 24 pt bar shown: its title bar 24 down", MSBDBarAHTitleSlide(0, 24, 23, 1), 24.0);
    Expect("  ... at 10: 14 down (what the bar covers of it)", MSBDBarAHTitleSlide(10, 24, 23, 1), 14.0);
    Expect("  ... at 23 (not touching the bar): none", MSBDBarAHTitleSlide(23, 24, 23, 1), 0.0);
    Expect("  ... at 24, under the bar: none", MSBDBarAHTitleSlide(24, 24, 23, 1), 0.0);
    Expect("  ... the bar hidden: none", MSBDBarAHTitleSlide(0, 24, 23, 0), 0.0);
    Expect("  ... a window above the screen's top (-5): the bar's height", MSBDBarAHTitleSlide(-5, 24, 23, 1), 24.0);
    Expect("  ... the Large bar (37, touching 36): 37", MSBDBarAHTitleSlide(0, 37, 36, 1), 37.0);
    Expect("  ... no number: none", MSBDBarAHTitleSlide(NAN, 24, 23, 1), 0.0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
