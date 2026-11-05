// test-taprule.c -- Mac test of which finger touch brings a window forward (common/TapRule.h, used by appbridge/AppBridge.x for Aerial and Zetsu and
// by StatusBar.x DMSMActivateOnTouch for the Stage Manager engine): 1.8.1, GitHub #10 after 1.7.9.2.
//  - a tap: the finger lifted less than 12 pt from where it went down, less than 0.8 s after (MacAppBridge's rule since 1.0, the same numbers);
//  - the Stage Manager engine brings a window forward only for such a tap, never for a slide or a scroll in it, and never for a touch that went down
//    on the menu bar (with a window in full screen the menu bar is that window's own status bar strip, inside its card); a tap on a full-screen
//    window that windows are in front of makes it the active one where it is (Aerial and Zetsu keep the windows over a full-screen app).
#include <stdio.h>
#include <math.h>
#include "../common/TapRule.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }

int main(void) {
    // ---- a tap
    Expect("a tap: no move, at once", MSBDTapLike(0.0, 0.0));
    Expect("a tap: a finger's small wobble (5 pt in 0.15 s)", MSBDTapLike(5.0, 0.15));
    Expect("a tap: just under the slop and the time (11.9 pt, 0.79 s)", MSBDTapLike(11.9, 0.79));
    Expect("no tap: 12 pt away (the slop is exclusive)", !MSBDTapLike(12.0, 0.1));
    Expect("no tap: 0.8 s down (a long press)", !MSBDTapLike(1.0, 0.8));
    Expect("no tap: a slide (80 pt in 0.3 s, the reporter's slide on the big window)", !MSBDTapLike(80.0, 0.3));
    Expect("no tap: a scroll (300 pt in 0.4 s)", !MSBDTapLike(300.0, 0.4));
    Expect("no tap: a long press without a move (1.2 s)", !MSBDTapLike(0.0, 1.2));
    Expect("no tap: nonsense in (a negative distance or time, NaN)", !MSBDTapLike(-1.0, 0.1) && !MSBDTapLike(1.0, -0.1) && !MSBDTapLike(NAN, 0.1) && !MSBDTapLike(1.0, NAN));
    // ---- the Stage Manager engine's touch in a window that is not the active one, at the lift
    Expect("Stage Manager: a tap in a window behind brings it forward", MSBDSMTouchOutcome(false, false, 3.0, 0.12) == kMSBDSMTouchForward);
    Expect("Stage Manager: a slide in a window behind leaves it there (as Aerial and Zetsu)", MSBDSMTouchOutcome(false, false, 80.0, 0.3) == kMSBDSMTouchNothing);
    Expect("Stage Manager: a long press in it leaves it there (as MacAppBridge's tap)", MSBDSMTouchOutcome(false, false, 0.0, 1.0) == kMSBDSMTouchNothing);
    Expect("Stage Manager: a tap on the menu bar (a full-screen window's strip) is never that window's", MSBDSMTouchOutcome(true, false, 0.0, 0.1) == kMSBDSMTouchNothing);
    Expect("Stage Manager: nor a slide along the menu bar", MSBDSMTouchOutcome(true, false, 80.0, 0.3) == kMSBDSMTouchNothing && MSBDSMTouchOutcome(true, true, 0.0, 0.1) == kMSBDSMTouchNothing);
    Expect("Stage Manager: a tap on a full-screen window with windows in front of it: active where it is, the windows stay in front (as Aerial and Zetsu)",
           MSBDSMTouchOutcome(false, true, 2.0, 0.1) == kMSBDSMTouchActiveInPlace);
    Expect("Stage Manager: a slide on it: nothing at all (as with Aerial and Zetsu)", MSBDSMTouchOutcome(false, true, 80.0, 0.3) == kMSBDSMTouchNothing);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
