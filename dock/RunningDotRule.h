// RunningDotRule.h: which running app gets the Dock's running dot (KT, 1.7.8.1; dock/RunningIndicator.m). Plain C, so tools/test-runningdot.c runs
// the same rule.
//
// iPadOS starts apps the user has not opened: dasd's prewarm (ActivePrewarm=1 in the process's environment; 17.5, 2 Nov: Calendar at 11:57 with no
// one at the iPad), a background launch asked of FrontBoard (18.5, 1-2 Nov: calaccessd opens Calendar suspended with UIFetchContentInBackgroundAction
// after each iCloud calendar sync, every ~36 min -- "Bootstrapping app<com.apple.mobilecal> with intent background"), Background App Refresh, a push,
// a location event. SpringBoard lists all of them in -runningApplications, and the dot showed under the app's icon although nothing of it had been
// on screen (KT, A12Z: "the calendar keeps launching in background and i see an open app indicator underneath"). iPadOS's own Dock has no dots, so
// what a dot says is ours: as on a Mac, an app the user has open -- not a process iPadOS keeps in the background.
//
// The rule. A running app has its dot when its process has been on screen (SpringBoard's process state says foreground) since that process started,
// or when the user has a window of it that is not on screen now (on another Mac Switcher desktop, or minimized -- also one our restore brings back
// minimized after a respring, invisible from its first frame: their apps kept their dot before, and a window there is open). The process is told
// apart by its pid: a process iPadOS starts again in the background after the one the user had open ended (a respring, memory) starts without a
// dot. Apps with a window on screen and our own apps (Activity Monitor) are not decided here -- RunningIndicator.m adds them as before, running or
// not. Without SpringBoard's process state in the known shape, every running app has its dot (as before 1.7.8.1).
#pragma once

// The pid to remember as "seen on screen" for an app after this look: its process's pid while that process is on screen now or was seen before;
// 0 (nothing remembered) when it is not running, or it is another process than the one seen.
static inline int MSBDDotSeenPid(int running, int pid, int onScreenNow, int seenPid) {
    if (!running || pid <= 0) return 0;
    if (onScreenNow) return pid;
    return seenPid == pid ? pid : 0;
}
// Whether a running app has the dot. stateKnown: SpringBoard's process state was read (pid, foreground) -- without it, every running app has it.
// seenPid: what MSBDDotSeenPid gave for this look. windowAway: a window of it on another desktop, or minimized.
static inline int MSBDDotShown(int running, int stateKnown, int pid, int seenPid, int windowAway) {
    if (!running) return 0;
    if (!stateKnown) return 1;
    if (pid > 0 && seenPid == pid) return 1;
    return windowAway ? 1 : 0;
}
