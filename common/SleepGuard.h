// SleepGuard.h -- the Sleep Guard's rules (battery drain F1, MacStatusBar&Dock 1.7.8). Plain C: tools/test-sleepguard.sh.
//
// iPadOS 16-18: every SpringBoard takes a "SystemIsActive" power assertion when it starts (BacklightServices.backlightActiveOn.startup) and
// gives it back only at the display's first sleep or wake. A SpringBoard that dies before that -- a respring with the screen kept on, a crash
// -- leaves it with powerd, owned by a process that is gone, and the iPad never idle-sleeps again until powerd or the iPad restarts (iPad 2
// 16.7.7: no sleep for 3 days, 111 mA with the screen off instead of ~40 mA; 17.5: 68-110 mA instead of 28; plans/battery-drain.md, 1 Nov).
// The guard (sshtoggled, root) looks while the screen is off: an assertion that keeps the iPad awake and whose owner process is gone, still
// there a minute later, is cleared by starting powerd over -- which drops EVERY assertion, live ones too (a backup or download through
// nsurlsessiond, an AirDrop, audio): so only when the dead one is the only thing keeping the iPad awake (powerd's own and the Charge Limit
// job's, which re-asserts at once, left out), never while the screen is on, at most once in 30 minutes and 6 times a day.
// Settings > Battery > Battery Health shows "iPad Can't Sleep" only when one is stuck and the guard could not clear it.
#pragma once
#include <string.h>

#define MSBD_SG_DOMAIN   "com.besiktasliseba.macstatusbar"
#define MSBD_SG_KEY      "sleepGuard"                          // (missing = on)
#define MSBD_SG_CHANGED  "com.besiktasliseba.sleepguard.changed"   // (Settings: the switch changed; the helper looks again)
#define MSBD_SG_STATEDIR "/var/jb/var/lib/sshtoggled-engines"
#define MSBD_SG_STATE    MSBD_SG_STATEDIR "/sleepguard.plist"  // (written by the helper, read by Settings and by the helper's next start)
#define MSBD_SG_LOG      "/var/jb/var/log/msbd-sleepguard.log"
#define MSBD_SG_CHARGEJOB "msbdcharge"                         // (the Charge Limit's job: re-raises its own after a powerd restart)

enum { kMSBDSGConfirmSeconds = 60, kMSBDSGMinGapSeconds = 1800, kMSBDSGMaxPerDay = 6, kMSBDSGLiveRetrySeconds = 300 };

// The kinds of assertion that keep an iPad from idle sleep (powerd's names, IOPMCopyAssertionsByProcess's AssertType).
static inline int MSBDSGKeepsAwake(const char *type) {
    static const char *const awake[] = { "SystemIsActive", "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion", NULL };
    if (!type) return 0;
    for (int i = 0; awake[i]; i++) if (!strcmp(type, awake[i])) return 1;
    return 0;
}
// Is the assertion's owner gone? powerd keys it by the pid that made it, and pids are reused: the process now at that pid is not the owner if it
// has another name (one name a prefix of the other is the same process: the kernel keeps 16 bytes of one, 32 of the other), or started after
// the assertion was made. pid <= 0 (the kernel's, powerd's own bookkeeping): never gone. procExists: kill(pid, 0) succeeded (or EPERM).
// procName / assertProcName: NULL or "" = unknown, not compared. procStart / assertStart / now: Unix seconds, the wall clock (0 = unknown, not
// compared). procAwake: how long the process has run on the clock that stops in sleep (mach_absolute_time; < 0 = unknown). The wall clock can be
// set back (Date & Time, a network time fix): then every later assertion of an older process would look older than the process. So the start
// times are compared only when the clock shows no sign of that: neither time in the future, and the process's wall-clock age not less than
// its awake time (it can only be more: the awake clock stops in sleep).
static inline int MSBDSGOwnerGone(int pid, int procExists, const char *procName, const char *assertProcName,
                                  double procStart, double procAwake, double assertStart, double now) {
    if (pid <= 0) return 0;
    if (!procExists) return 1;
    if (procName && assertProcName && *procName && *assertProcName) {
        size_t a = strlen(procName), b = strlen(assertProcName), n = a < b ? a : b;
        if (strncmp(procName, assertProcName, n) != 0) return 1;   // (another program at that pid)
    }
    int clockSane = procStart > 0 && assertStart > 0 && now > 0 && procStart <= now + 2 && assertStart <= now + 2
                    && (procAwake < 0 || now - procStart + 2 >= procAwake);
    if (clockSane && procStart > assertStart + 2) return 1;   // (started after the assertion was made: a reused pid)
    return 0;
}
// Stuck: it keeps the iPad awake, it is on, and the process that owns it is gone.
static inline int MSBDSGStuck(const char *type, long level, int ownerGone) { return MSBDSGKeepsAwake(type) && level > 0 && ownerGone; }
// A live assertion that keeps the iPad awake and that a powerd restart would cut off: anything of a live owner, but powerd's own and the
// Charge Limit job's (it raises its own again within a second of a powerd restart: a30ec74).
static inline int MSBDSGLiveOther(const char *type, long level, int ownerGone, int ownerIsPowerd, const char *ownerProcName) {
    if (!MSBDSGKeepsAwake(type) || level <= 0 || ownerGone || ownerIsPowerd) return 0;
    if (ownerProcName && !strcmp(ownerProcName, MSBD_SG_CHARGEJOB)) return 0;
    return 1;
}

typedef enum { kMSBDSGNothing = 0, kMSBDSGWait, kMSBDSGClear, kMSBDSGBlocked } MSBDSGAction;
// What to do now. stuckSince: when the guard first saw stuck assertions (0: none now). liveOthers: live keep-awake assertions a restart would
// cut off (MSBDSGLiveOther). lastClear: the last clear (0: never). clearsToday: clears in the last 24 h; oldestClear: the first of them (0:
// none). *why gets a short reason (the log, Settings' footer); *lookAgainIn the seconds after which a look can decide otherwise with the
// screen still off (0: nothing to wait for -- the next screen-off, or the switch, brings the next look).
// Blocked = stuck, and the guard will not clear it for a reason that does not pass by itself soon (switched off, the limits); Wait = it may
// clear soon (the minute's confirmation, the screen on, something else keeping the iPad awake).
static inline MSBDSGAction MSBDSGDecide(double stuckSince, double now, int screenOff, int liveOthers, int guardOn,
                                        double lastClear, int clearsToday, double oldestClear, const char **why, double *lookAgainIn) {
    const char *w = ""; double again = 0;
    MSBDSGAction a;
    if (stuckSince <= 0) { a = kMSBDSGNothing; w = "nothing stuck"; }
    else if (!guardOn) { a = kMSBDSGBlocked; w = "Sleep Guard is off"; }
    else if (now - stuckSince < kMSBDSGConfirmSeconds) { a = kMSBDSGWait; w = "seen less than a minute ago"; again = stuckSince + kMSBDSGConfirmSeconds + 2 - now; }
    else if (!screenOff) { a = kMSBDSGWait; w = "the screen is on"; }
    else if (liveOthers > 0) { a = kMSBDSGWait; w = "something else keeps the iPad awake"; again = kMSBDSGLiveRetrySeconds; }
    else if (lastClear > 0 && now - lastClear < kMSBDSGMinGapSeconds) {
        a = kMSBDSGBlocked; w = "cleared less than 30 minutes ago"; again = lastClear + kMSBDSGMinGapSeconds + 2 - now;
    }
    else if (clearsToday >= kMSBDSGMaxPerDay) {
        a = kMSBDSGBlocked; w = "cleared 6 times today"; again = oldestClear > 0 ? oldestClear + 86400 + 2 - now : 0;
    }
    else { a = kMSBDSGClear; w = "clearing"; }
    if (again < 0) again = 0;
    if (why) *why = w;
    if (lookAgainIn) *lookAgainIn = again;
    return a;
}
// Settings' "iPad Can't Sleep" row: shown only while something is stuck and the guard will not or could not clear it.
static inline int MSBDSGShowCantSleep(int stuck, MSBDSGAction lastAction, int lastClearFailed) {
    return stuck && (lastAction == kMSBDSGBlocked || lastClearFailed);
}
