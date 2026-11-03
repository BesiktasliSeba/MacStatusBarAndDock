// test-a5lockcatch.c -- Mac test of what a round-icon catch makes of a window (statusbar/A5LockCatch.h, used by StatusBar.x DMAerial5CatchChip):
// 1.7.9 regression G-4b (M1 15.6.1, Aerial 5.1), Aerial 5 minimizing every window as the screen locks. The windows the user had minimized (the
// yellow light, Home Minimizes Windows, Minimize All) or that are on another desktop stay as they were; the windows that were on screen come back
// after the unlock as before. The rule's own answers, then the lock as the device shows it, window by window, against the rule of 1.7.8.2 (which
// brought every minimized window back).
#include <stdio.h>
#include "../statusbar/A5LockCatch.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }

// The catch as it was up to 1.7.9 (DMAerial5CatchChip): locked -> the lock's; just after the unlock, on its way back, or once more after it was
// shown back -> back; else ours. Whether the window was hidden already was never asked.
static int OldRole(int follow, int locked, double sinceUnlock, double sinceShownBack) {
    if (locked) return MSBDA5CatchLock | (follow == 2 ? MSBDA5CatchBack : 0);
    int justUnlocked = sinceUnlock >= 0 && sinceUnlock < 0.5, again = !justUnlocked && sinceShownBack >= 0 && sinceShownBack < 1.0;
    return (justUnlocked || follow == 2 || again) ? (MSBDA5CatchBack | (again ? MSBDA5CatchAgain : 0)) : MSBDA5CatchHide;
}
static int ComesBack(int role) { return (role & (MSBDA5CatchLock | MSBDA5CatchBack)) != 0; }

typedef struct { const char *name; int hiddenOurs, away; } Win;   // a window as the lock finds it
// One lock: Aerial minimizes every window (on screen and hidden alike), caught either while locking (the screen still on: "screen locking") or at
// the first frames after the unlock ("just after the unlock", Aerial's minimize came while the screen was off). Returns how many of them come back,
// and which, in *back (bit i = window i).
static int Lock(const Win *w, int n, int whileLocking, int oldRule, unsigned *back) {
    int count = 0; *back = 0;
    for (int i = 0; i < n; i++) {
        int locked = whileLocking; double sinceUnlock = whileLocking ? 120.0 : 0.02;
        int role = oldRule ? OldRole(0, locked, sinceUnlock, -1) : MSBDA5CatchRole(w[i].hiddenOurs, w[i].away, 0, 0, locked, sinceUnlock, -1);
        if (ComesBack(role)) { count++; *back |= 1u << i; }
    }
    return count;
}

int main(void) {
    // ---- the rule's own answers
    Expect("open window, caught while locking: the lock's (back after the unlock)", MSBDA5CatchRole(0, 0, 0, 0, 1, 60, -1) == MSBDA5CatchLock);
    Expect("open window, caught just after the unlock (Aerial minimized it while the screen was off): back as soon as Aerial is done",
           MSBDA5CatchRole(0, 0, 0, 0, 0, 0.02, -1) == MSBDA5CatchBack);
    Expect("open window minimized by Aerial itself, not around an unlock (its menu, a swipe): hidden into our minimize",
           MSBDA5CatchRole(0, 0, 0, 0, 0, 30, -1) == MSBDA5CatchHide);
    Expect("open window caught again 0.3 s after the unlock's follow showed it back: back once more, the last time",
           MSBDA5CatchRole(0, 0, 0, 0, 0, 2.0, 0.3) == (MSBDA5CatchBack | MSBDA5CatchAgain));
    Expect("  ... 1.5 s after it was shown back: Aerial's own minimize, hidden", MSBDA5CatchRole(0, 0, 0, 0, 0, 3.0, 1.5) == MSBDA5CatchHide);
    Expect("G-4b: minimized by the user (yellow light / Home), caught while locking: stays minimized (not the lock's)",
           MSBDA5CatchRole(1, 0, 0, 0, 1, 60, -1) == MSBDA5CatchKeep);
    Expect("G-4b: minimized by the user, caught just after the unlock: stays minimized (not back)", MSBDA5CatchRole(1, 0, 0, 0, 0, 0.02, -1) == MSBDA5CatchKeep);
    Expect("  ... caught on a tick a while after the unlock (every window hidden: no per-frame watch): stays minimized",
           MSBDA5CatchRole(1, 0, 0, 0, 0, 5.0, -1) == MSBDA5CatchKeep);
    Expect("on another Mac Switcher desktop, caught while locking: stays on its desktop (not ours, not the lock's)", MSBDA5CatchRole(0, 1, 0, 0, 1, 60, -1) == MSBDA5CatchKeep);
    Expect("  ... caught just after the unlock: stays on its desktop", MSBDA5CatchRole(0, 1, 0, 0, 0, 0.02, -1) == MSBDA5CatchKeep);
    Expect("minimized by the user AND on another desktop: stays as it was", MSBDA5CatchRole(1, 1, 0, 0, 1, 60, -1) == MSBDA5CatchKeep);
    Expect("the lock's own window (caught while locking, hidden since), Aerial minimizing it once more while still locked: still the lock's",
           MSBDA5CatchRole(1, 0, 1, 0, 1, 60, -1) == MSBDA5CatchLock);
    Expect("  ... once more after the unlock, before the unlock brought it back: back as soon as Aerial is done",
           ComesBack(MSBDA5CatchRole(1, 0, 1, 0, 0, 0.1, -1)) && !(MSBDA5CatchRole(1, 0, 1, 0, 0, 0.1, -1) & MSBDA5CatchKeep));
    Expect("  ... and a second after the unlock still (its way back was asked): back", ComesBack(MSBDA5CatchRole(1, 0, 1, 0, 0, 1.2, -1)));
    Expect("a window on its way back after the unlock (its follow brings it back), caught once more: back", MSBDA5CatchRole(1, 0, 0, 2, 0, 0.3, -1) == MSBDA5CatchBack);
    Expect("  ... while locked: the lock's and back (as before)", MSBDA5CatchRole(1, 0, 0, 2, 1, 60, -1) == (MSBDA5CatchLock | MSBDA5CatchBack));
    Expect("its desktop came back while Aerial's minimize was being undone (no longer hidden by us): it stays shown, once Aerial is done",
           MSBDA5CatchRole(0, 0, 0, 1, 0, 30, -1) == MSBDA5CatchBack);
    Expect("one we keep hidden whose undo is under way (follow 1), caught once more: stays as it was", MSBDA5CatchRole(1, 0, 0, 1, 0, 30, -1) == MSBDA5CatchKeep);
    for (int locked = 0; locked < 2; locked++) for (int f = 0; f < 3; f++) for (int u = 0; u < 4; u++) {   // (Keep never comes with Lock or Back)
        double su[] = { -1, 0.02, 0.7, 30 };
        for (int h = 0; h < 2; h++) for (int a = 0; a < 2; a++) for (int l = 0; l < 2; l++) {
            int r = MSBDA5CatchRole(h, a, l, f, locked, su[u], -1);
            if ((r & MSBDA5CatchKeep) && ComesBack(r)) { Expect("sweep: Keep never comes with Lock or Back", 0); goto swept; }
            if (!h && !a && !l && f == 0 && r != OldRole(0, locked, su[u], -1)) { Expect("sweep: an open window's answer is the one of 1.7.8.2", 0); goto swept; }
        }
    }
    Expect("sweep: Keep never comes with a way back; an open window's answer is unchanged from 1.7.8.2 (96 cases)", 1);
swept:;

    // ---- the lock as the device shows it (regression G-4b rows, M1 z03 / RC)
    Win oneShown[] = { { "Clock (on screen)", 0, 0 }, { "Tips (Home swipe)", 1, 0 }, { "App Store (Home swipe)", 1, 0 }, { "Settings (yellow light)", 1, 0 } };
    unsigned back = 0; int n;
    n = Lock(oneShown, 4, 1, 1, &back);
    Expect("before (1.7.8.2 rule): one shown, three minimized, caught while locking: all four come back (the bug, z03 3/3)", n == 4);
    n = Lock(oneShown, 4, 0, 1, &back);
    Expect("before: the same caught just after the unlock: all four come back", n == 4);
    n = Lock(oneShown, 4, 1, 0, &back);
    Expect("after: caught while locking: only the window that was on screen comes back", n == 1 && back == 1u);
    n = Lock(oneShown, 4, 0, 0, &back);
    Expect("after: caught just after the unlock: only the window that was on screen comes back", n == 1 && back == 1u);
    Win allMin[] = { { "Tips", 1, 0 }, { "App Store", 1, 0 }, { "Clock", 1, 0 }, { "Settings", 1, 0 } };
    n = Lock(allMin, 4, 1, 0, &back); int n2 = Lock(allMin, 4, 0, 0, &back);
    Expect("after: every window minimized at the lock: none comes back, either way it is caught", n == 0 && n2 == 0);
    Win allOpen[] = { { "Tips", 0, 0 }, { "App Store", 0, 0 }, { "Clock", 0, 0 } };
    n = Lock(allOpen, 3, 1, 0, &back); n2 = Lock(allOpen, 3, 0, 0, &back);
    Expect("after: every window on screen at the lock: all three come back, either way it is caught (as before)", n == 3 && n2 == 3);
    Win desks[] = { { "Tips (here, on screen)", 0, 0 }, { "Clock (Desktop 2)", 0, 1 }, { "Notes (Desktop 2, minimized)", 1, 1 } };
    n = Lock(desks, 3, 1, 0, &back);
    Expect("after: a window on another desktop stays there (shown when its desktop comes), not brought onto this one", n == 1 && back == 1u);

    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
