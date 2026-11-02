// test-runningdot.c: which running app has the Dock's running dot (dock/RunningDotRule.h, KT 1.7.8.1), run against the launches iPadOS made on the
// test iPads (2 Nov 2026, their own logs): 18.5 A12Z -- calaccessd opens Calendar suspended after each iCloud calendar sync, every ~36 min,
// "Bootstrapping app<com.apple.mobilecal> with intent background", SpringBoard's process state "taskState: Running; visibility: Background";
// 17.5 -- dasd prewarms Calendar ("Executing launch request ... (DAS Prewarm launch)", ActivePrewarm => 1). Each look is one read of the running
// apps (RunningIndicator.m: the 0.75 s poll while the screen is on, and each Dock icon's layout). Run by test-runningdot.sh.
#include <stdio.h>
#include "../dock/RunningDotRule.h"

static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }

typedef struct { int seen; } App;   // (what RunningIndicator.m remembers for one app: gRISeenPid)
// One look at a running app, as RIRunningBundleIDs does it: the pid remembered, then whether it has the dot.
static int Look(App *a, int running, int known, int pid, int onScreen, int away) {
    a->seen = known ? MSBDDotSeenPid(running, pid, onScreen, a->seen) : 0;
    if (!running) a->seen = 0;   // (an app no longer running is forgotten)
    return MSBDDotShown(running, known, pid, a->seen, away);
}

int main(void) {
    // ---- the A12Z's Calendar, 2 Nov: KT never opened it ----
    App cal = {0};
    Int("calaccessd's background launch (pid 80747, visibility Background): no dot", Look(&cal, 1, 1, 80747, 0, 0), 0);
    Int("  ... 36 min later its next request reaches the same process, still in the background: no dot", Look(&cal, 1, 1, 80747, 0, 0), 0);
    Int("  ... KT swipes it away in the App Switcher (not running): no dot, nothing remembered", Look(&cal, 0, 1, 0, 0, 0) == 0 && cal.seen == 0, 1);
    Int("  ... the next sync starts it again in the background (another pid): no dot", Look(&cal, 1, 1, 81234, 0, 0), 0);
    // ---- the user opens it ----
    Int("KT opens Calendar (that process on screen): the dot", Look(&cal, 1, 1, 81234, 1, 0), 1);
    Int("  ... KT goes Home (the process in the background, suspended): the dot stays", Look(&cal, 1, 1, 81234, 0, 0), 1);
    Int("  ... calaccessd asks for it again while it runs (same process): the dot stays", Look(&cal, 1, 1, 81234, 0, 0), 1);
    Int("  ... a respring ends it, and the sync starts it again in the background: no dot", Look(&cal, 0, 1, 0, 0, 0) + Look(&cal, 1, 1, 82000, 0, 0), 0);
    Int("  ... memory ends the opened process and another starts at once in the background, never seen: no dot (the pid tells them apart)",
        (Look(&cal, 1, 1, 82000, 1, 0), Look(&cal, 1, 1, 82999, 0, 0)), 0);
    // ---- the 17.5's prewarm ----
    App pre = {0};
    Int("dasd's prewarm of Calendar (ActivePrewarm=1, never on screen): no dot", Look(&pre, 1, 1, 34586, 0, 0), 0);
    Int("  ... the user opens the prewarmed process (the same pid comes on screen): the dot", Look(&pre, 1, 1, 34586, 1, 0), 1);
    // ---- what keeps its dot as before ----
    App away = {0};
    Int("a running app with a window on another desktop or minimized, its process started again in the background: the dot", Look(&away, 1, 1, 500, 0, 1), 1);
    Int("  ... the same app not running: no dot here (RunningIndicator.m adds on-screen windows and our own apps itself)", Look(&away, 0, 1, 0, 0, 1), 0);
    App unknown = {0};
    Int("SpringBoard's process state not in the known shape: every running app has the dot, as before 1.7.8.1", Look(&unknown, 1, 0, 0, 0, 0), 1);
    Int("  ... and nothing is remembered for it", unknown.seen, 0);
    App nopid = {0};
    Int("a state with no pid yet (0), not on screen: no dot", Look(&nopid, 1, 1, 0, 0, 0), 0);
    Int("  ... and on screen with no pid: still nothing remembered (a pid is what is remembered)", (Look(&nopid, 1, 1, 0, 1, 0), nopid.seen), 0);
    // ---- the rule's two functions on their own ----
    Int("MSBDDotSeenPid: not running -> 0", MSBDDotSeenPid(0, 7, 1, 7), 0);
    Int("MSBDDotSeenPid: on screen now -> its pid", MSBDDotSeenPid(1, 7, 1, 0), 7);
    Int("MSBDDotSeenPid: the pid seen before, off screen now -> kept", MSBDDotSeenPid(1, 7, 0, 7), 7);
    Int("MSBDDotSeenPid: another pid than the one seen, off screen -> 0", MSBDDotSeenPid(1, 8, 0, 7), 0);
    Int("MSBDDotShown: not running -> no dot, even with a window away", MSBDDotShown(0, 1, 7, 7, 1), 0);
    printf("%s: %d/%d\n", fails ? "test-runningdot FAILED" : "test-runningdot: all pass", checks - fails, checks);
    return fails ? 1 : 0;
}
