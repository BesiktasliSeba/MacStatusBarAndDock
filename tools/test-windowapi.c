// test-windowapi.c -- Mac test of statusbar/WindowAPIRule.h (1.8.3 item 1): the window API V1 that KeyPilot calls (wanghuangjie's bridge, his names and
// codes): the twelve layouts, the order of the layout's checks and its codes, Home's codes, the environment's values. Run by test-windowapi.sh.
#include <stdio.h>
#include "../statusbar/WindowAPIRule.h"
static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
int main(void) {
    // ---- the codes are KeyPilot's: its client prints its own words for 0..6 (KPWindowController.m), so they never change ----
    Int("0 dispatched", kMSBDWinAPIDispatched, 0);
    Int("1 wrong thread", kMSBDWinAPIWrongThread, 1);
    Int("2 unknown layout", kMSBDWinAPIUnknownLayout, 2);
    Int("3 no engine", kMSBDWinAPINoEngine, 3);
    Int("4 no active app", kMSBDWinAPINoActiveApp, 4);
    Int("5 full-screen-only app", kMSBDWinAPIFullScreenOnly, 5);
    Int("6 locked or busy", kMSBDWinAPIBusy, 6);
    Int("environment: 1 Home", kMSBDWinEnvHome, 1);
    Int("  ... 2 App Switcher", kMSBDWinEnvSwitcher, 2);
    Int("  ... 3 app", kMSBDWinEnvApp, 3);
    Int("  ... -1 unknown", kMSBDWinEnvUnknown, -1);
    Int("  ... -2 locked", kMSBDWinEnvLocked, -2);
    // ---- the twelve layouts: his allowlist exactly, the Window menu's names ----
    const char *his[] = { "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright", "fill", "center", "small", "large" };
    int known = 0;
    for (int i = 0; i < 12; i++) if (MSBDWinAPILayoutIndex(his[i]) >= 0) known++;
    Int("every name of his allowlist is known", known, 12);
    Int("  ... and no other", kMSBDWinAPILayoutCount, 12);
    Int("\"medium\" (a Window menu frame KeyPilot does not name): unknown", MSBDWinAPILayoutIndex("medium"), -1);
    Int("\"Left\" (another case): unknown", MSBDWinAPILayoutIndex("Left"), -1);
    Int("\"left-half\" (KeyPilot's action name, not the argument): unknown", MSBDWinAPILayoutIndex("left-half"), -1);
    Int("\"\": unknown", MSBDWinAPILayoutIndex(""), -1);
    Int("NULL: unknown", MSBDWinAPILayoutIndex(NULL), -1);
    Int("\"left \" (a trailing space): unknown", MSBDWinAPILayoutIndex("left "), -1);
    // ---- the layout's checks, in his order ----
    MSBDWinAPIFacts ok = { .mainThread = true, .busy = false, .nativeFront = false, .engine = true, .activeApp = true, .fullScreenOnly = false };
    Int("a known layout, an engine, an app: dispatched", MSBDWinAPILayoutStatus("left", ok), 0);
    MSBDWinAPIFacts f = ok; f.mainThread = false; f.busy = true; f.engine = false;
    Int("off the main thread: 1 before anything else", MSBDWinAPILayoutStatus("nonsense", f), 1);
    f = ok; f.busy = true; f.engine = false;
    Int("an unknown layout: 2 before locked", MSBDWinAPILayoutStatus("nonsense", f), 2);
    Int("locked or busy: 6 before no engine", MSBDWinAPILayoutStatus("fill", f), 6);
    f = ok; f.engine = false; f.activeApp = false;
    Int("no engine: 3 before no app", MSBDWinAPILayoutStatus("fill", f), 3);
    f = ok; f.activeApp = false; f.fullScreenOnly = true;
    Int("no active app: 4", MSBDWinAPILayoutStatus("center", f), 4);
    f = ok; f.fullScreenOnly = true;
    Int("an app that only runs full screen: 5", MSBDWinAPILayoutStatus("small", f), 5);
    f = ok; f.nativeFront = true; f.engine = false; f.activeApp = false;
    Int("our own window in front (Finder): laid out, with no engine too", MSBDWinAPILayoutStatus("large", f), 0);
    f.busy = true;
    Int("  ... but not while busy", MSBDWinAPILayoutStatus("large", f), 6);
    // ---- Home: 0 / 1 / 6 ----
    Int("Home: dispatched", MSBDWinAPIHomeStatus(true, false), 0);
    Int("Home off the main thread: 1", MSBDWinAPIHomeStatus(false, true), 1);
    Int("Home locked: 6", MSBDWinAPIHomeStatus(true, true), 6);
    // ---- Home once (review 1.8.3 F10: KeyPilot's Cmd-H and iPadOS's own Cmd-H can both run; a press handed over twice) ----
    Int("a second Home 0.3 s after the last: the same Home", MSBDWinAPIHomeAgain(0.3), 1);
    Int("  ... 1.2 s after: a Home of its own", MSBDWinAPIHomeAgain(1.2), 0);
    Int("  ... the first one (none before): its own", MSBDWinAPIHomeAgain(-1.0), 0);
    Int("SpringBoard in a transition of its own (iPadOS's Cmd-H Home): wait", MSBDWinAPIHomeStep(false, true, false, 0), kMSBDWinHomeWait);
    Int("  ... still busy after 2 s (20 tries): nothing, no Home into it", MSBDWinAPIHomeStep(false, true, false, kMSBDWinHomeMaxTries), kMSBDWinHomeGiveUp);
    Int("  ... its end at Home: the windows only, no second Home", MSBDWinAPIHomeStep(false, false, true, 3), kMSBDWinHomeMinimizeOnly);
    Int("free, an app in front: the windows and Home", MSBDWinAPIHomeStep(false, false, false, 0), kMSBDWinHomeFull);
    Int("  ... at Home with windows over it: the windows only", MSBDWinAPIHomeStep(false, false, true, 0), kMSBDWinHomeMinimizeOnly);
    Int("locked (or Guided Access) after waiting for a transition: nothing, no windows minimized, no Home on the Lock Screen (review 1.8.3 P2-6)", MSBDWinAPIHomeStep(true, false, false, 5), kMSBDWinHomeLockedNow);
    Int("  ... at any step, also the first and at Home", MSBDWinAPIHomeStep(true, true, true, 0) == kMSBDWinHomeLockedNow && MSBDWinAPIHomeStep(true, false, true, 0) == kMSBDWinHomeLockedNow, 1);
    // ---- the environment ----
    Int("environment: the Home Screen", MSBDWinAPIEnvironment(true, false, true, 1), 1);
    Int("  ... the App Switcher", MSBDWinAPIEnvironment(true, false, true, 2), 2);
    Int("  ... an app", MSBDWinAPIEnvironment(true, false, true, 3), 3);
    Int("  ... off the main thread: -1", MSBDWinAPIEnvironment(false, false, true, 1), -1);
    Int("  ... locked: -2 (before the read)", MSBDWinAPIEnvironment(true, true, true, 1), -2);
    Int("  ... not readable: -1", MSBDWinAPIEnvironment(true, false, false, 1), -1);
    Int("  ... a value SpringBoard never gives: -1", MSBDWinAPIEnvironment(true, false, true, 0), -1);
    Int("  ... nor another one", MSBDWinAPIEnvironment(true, false, true, 4), -1);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
