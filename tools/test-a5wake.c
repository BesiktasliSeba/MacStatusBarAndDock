// test-a5wake.c -- Mac test of the steps after Aerial 5's round-icon minimize (statusbar/A5WakeFollow.h, used by StatusBar.x DMA5FollowStep):
// 1.7.4 item 3e, the windows back after a wake as soon as Aerial is done, never mid-animation and never later than the old fixed 0.6 / 1.4 / 1.6 s.
// The rule's own answers, then the step loop as DMA5FollowStep runs it (two passes a display frame, 60 frames a second) against model Aerials.
#include <stdio.h>
#include "../statusbar/A5WakeFollow.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }

typedef struct {        // Aerial as the window shows it, in seconds after the catch
    double shrinkEnd;   // its minimize animation runs until then (0: over before the catch -- minimized while the screen was off)
    double gapAt;       // one display frame without animation then (two chained animations), 0: none
    double restoreAnim; // its restore animates this long once asked (-1: something on the window never stops animating)
    double chipOff;     // its minimized flag clears this long after the restore is asked (-1: never)
    int putBack;        // the check finds the frame elsewhere (put back: the app is sent its size)
    int back;           // the window comes back by itself...
    double backFrom;    // ... from then on (a window caught while locked: from the unlock); 0: from the catch
    int fixed;          // the debug switch /tmp/msb-a5-fixedwake: the old fixed times
} Aerial;
typedef struct { double restoreAt, askedAt, checkAt, showAt, endAt; } Times;
static Times Run(Aerial a) {
    Times t = { -1, -1, -1, -1, -1 };
    int phase = MSBDA5FollowShrinking, quiet = 0, settle = 0;
    double phaseAt = 0;
    for (int i = 1; i < 400; i++) {   // (display frames after the catch)
        double now = i / 60.0;
        int back = a.back && now >= a.backFrom;
        int chip = !(t.askedAt >= 0 && a.chipOff >= 0 && now >= t.askedAt + a.chipOff);
        int gap = a.gapAt > 0 && now >= a.gapAt && now < a.gapAt + 1.0 / 60.0;
        int anim = (now < a.shrinkEnd && !gap) || (t.askedAt >= 0 && (a.restoreAnim < 0 || now < t.askedAt + a.restoreAnim));
        quiet = anim ? 0 : quiet + 1;
        for (int pass = 0; pass < 2; pass++) {
            int ranOut = !a.fixed && quiet >= MSBD_A5_QUIET_FRAMES;
            int next = MSBDA5FollowNext(phase, now - phaseAt, a.fixed ? 0 : quiet, chip, back, settle);
            if (next == MSBDA5Restore) { t.restoreAt = now; if (chip) t.askedAt = now; phase = MSBDA5FollowRestoring; phaseAt = now; quiet = 0; break; }
            if (next == MSBDA5Check) { t.checkAt = now; settle = !ranOut || chip || a.putBack; phase = MSBDA5FollowChecked; phaseAt = now; continue; }
            if (next == MSBDA5Show) { t.showAt = now; return t; }
            if (next == MSBDA5End) { t.endAt = now; return t; }
            break;
        }
    }
    return t;
}
static int Near(double got, double want) { return got >= want - 0.001 && got <= want + 2.0 / 60.0 + 0.001; }   // (by the second display frame after)

int main(void) {
    // the rule itself
    Expect("Aerial's minimize still animating: wait", MSBDA5FollowNext(MSBDA5FollowShrinking, 0.1, 0, 1, 1, 0) == MSBDA5Wait);
    Expect("  one quiet frame is not its end yet (a chained animation may come next): wait", MSBDA5FollowNext(MSBDA5FollowShrinking, 0.1, 1, 1, 1, 0) == MSBDA5Wait);
    Expect("  two quiet frames: it has run out -> Aerial's restore", MSBDA5FollowNext(MSBDA5FollowShrinking, 0.1, 2, 1, 1, 0) == MSBDA5Restore);
    Expect("  still animating at 0.6 s (the old fixed time): Aerial's restore all the same", MSBDA5FollowNext(MSBDA5FollowShrinking, 0.6, 0, 1, 1, 0) == MSBDA5Restore);
    Expect("Aerial's restore quiet but the window still minimized: wait", MSBDA5FollowNext(MSBDA5FollowRestoring, 0.2, 5, 1, 1, 0) == MSBDA5Wait);
    Expect("  no longer minimized, still animating: wait", MSBDA5FollowNext(MSBDA5FollowRestoring, 0.2, 0, 0, 1, 0) == MSBDA5Wait);
    Expect("  no longer minimized, two quiet frames: check the frame", MSBDA5FollowNext(MSBDA5FollowRestoring, 0.2, 2, 0, 1, 0) == MSBDA5Check);
    Expect("  0.8 s after the restore (1.4 s, the old fixed time): check whatever it shows", MSBDA5FollowNext(MSBDA5FollowRestoring, 0.8, 0, 1, 1, 0) == MSBDA5Check);
    Expect("checked, a window to bring back, nothing to settle: show it now", MSBDA5FollowNext(MSBDA5FollowChecked, 0.0, 0, 0, 1, 0) == MSBDA5Show);
    Expect("  frame put back (or the check at its limit): 0.1 s later still waits", MSBDA5FollowNext(MSBDA5FollowChecked, 0.1, 0, 0, 1, 1) == MSBDA5Wait);
    Expect("  ... 0.2 s later (1.6 s, the old fixed time): show it", MSBDA5FollowNext(MSBDA5FollowChecked, 0.2, 0, 0, 1, 1) == MSBDA5Show);
    Expect("checked, not one to bring back (Aerial's own minimize of an open window, or caught while locked): the follow ends, it stays hidden", MSBDA5FollowNext(MSBDA5FollowChecked, 0.0, 0, 0, 0, 0) == MSBDA5End);

    // the M1's wake (1.7.4 item 3e): minimized by Aerial while the screen was off -- nothing animating when the unlock comes; its restore animates
    // ~0.5 s (a model; the device pass reads the real one)
    Aerial m1 = { 0, 0, 0.5, 0.0, 0, 1, 0, 0 };
    Times t = Run(m1);
    printf("      M1 model: restore asked %.3f s, checked %.3f s, back %.3f s after the catch\n", t.askedAt, t.checkAt, t.showAt);
    Expect("M1 wake: Aerial's restore asked two frames after the catch (nothing of its minimize left)", Near(t.askedAt, 2.0 / 60.0));
    Expect("  the window back as Aerial's restore has run out, under 0.6 s (was 1.6 s)", t.showAt > 0 && t.showAt <= 0.6);
    Expect("  ... never while Aerial's restore still animates", t.showAt >= t.askedAt + m1.restoreAnim + 1.0 / 60.0);
    m1.fixed = 1; t = Run(m1);
    printf("      M1 model, the old fixed times (debug switch): restore %.3f s, check %.3f s, back %.3f s\n", t.restoreAt, t.checkAt, t.showAt);
    Expect("  the debug switch gives the old times: restore 0.6 s, check 1.4 s, back 1.6 s (to the display frame)", Near(t.restoreAt, 0.6) && Near(t.checkAt, 1.4) && Near(t.showAt, 1.6));

    // caught while Aerial's minimize animates (0.35 s of it left): the restore only once it has run out (a restore before its end left the window at
    // the chip's size: the end sets the chip's frame)
    Aerial mid = { 0.35, 0, 0.5, 0.0, 0, 1, 0, 0 };
    t = Run(mid);
    Expect("caught mid-minimize: Aerial's restore not before its minimize has run out", t.askedAt >= 0.35 + 1.0 / 60.0 && t.askedAt <= 0.35 + 3.0 / 60.0 + 0.001);
    Expect("  back when its restore has run out (under 1 s, was 1.6 s)", t.showAt >= t.askedAt + 0.5 && t.showAt < 1.0);
    Aerial gap = { 0.35, 0.2, 0.5, 0.0, 0, 1, 0, 0 };
    t = Run(gap);
    Expect("  a one-frame pause between two of Aerial's animations is not their end", t.askedAt >= 0.35);

    // the upper limits: never later than the old fixed times
    Aerial endless = { 0, 0, -1, 0.0, 0, 1, 0, 0 };
    t = Run(endless);
    Expect("something on the window never stops animating after the restore: checked 0.8 s after it, back 0.2 s later (the old waits), by 1.6 s",
           Near(t.checkAt, t.restoreAt + 0.8) && Near(t.showAt, t.checkAt + 0.2) && t.showAt <= 1.6 + 2.0 / 60.0);
    Aerial endless2 = { 10.0, 0, 0.5, 0.0, 0, 1, 0, 0 };
    t = Run(endless2);
    Expect("  ... already while minimizing: Aerial's restore at 0.6 s as before", Near(t.restoreAt, 0.6) && t.showAt <= 1.6 + 1.0 / 60.0);
    Aerial stuck = { 0, 0, 0.3, -1, 0, 1, 0, 0 };
    t = Run(stuck);
    Expect("Aerial's restore leaves it minimized: checked 0.8 s after the restore, back 0.2 s later (the old waits), by 1.6 s",
           Near(t.checkAt, t.restoreAt + 0.8) && Near(t.showAt, t.checkAt + 0.2) && t.showAt <= 1.6 + 2.0 / 60.0);
    Aerial moved = { 0, 0, 0.5, 0.0, 1, 1, 0, 0 };
    t = Run(moved);
    Expect("its frame put back after Aerial's restore: back 0.2 s after the check (the app has its size first)", t.checkAt > 0 && Near(t.showAt, t.checkAt + 0.2) && t.showAt < 1.0);

    // windows that do not come back by themselves
    Aerial own = { 0.35, 0, 0.5, 0.0, 0, 0, 0, 0 };
    t = Run(own);
    Expect("minimized by Aerial while open (not around an unlock): restored and checked behind our hide, never shown", t.checkAt > 0 && t.showAt < 0 && t.endAt >= t.checkAt);
    Aerial locked = { 0.35, 0, 0.5, 0.0, 0, 1, 0.45, 0 };
    t = Run(locked);
    Expect("caught on the Lock Screen, unlocked mid-restore: shown once Aerial's restore has run out, not at the unlock", t.showAt >= t.askedAt + 0.5 && t.showAt > 0.45);

    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
