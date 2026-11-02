// test-sleepguard.c: the Sleep Guard's rules (common/SleepGuard.h): whose assertion is stuck (owner gone, pids reused), what else keeps the
// iPad awake, when the guard clears and when it looks again, and when Settings says "iPad Can't Sleep". Cases from the 1 Nov leaks (iPad 2 /
// 17.5: SystemIsActive BacklightServices.backlightActiveOn.startup owned by dead SpringBoard pids, pid 137 after a pid wrap) and the live sets
// seen (Spotify's audio, runningboardd's Bluetooth SystemIsActive, the Charge Limit job's, apsd's push assertions).
#include <stdio.h>
#include "../common/SleepGuard.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    // ---- whose assertion: MSBDSGOwnerGone(pid, exists, name now, assertion's Process Name, started, awake, made, now)
    double T = 1793000000;   // (2 Nov 2026)
    check("owner process gone (no process at the pid): gone", MSBDSGOwnerGone(13383, 0, "", "SpringBoard", 0, -1, T - 600, T));
    check("pid <= 0 (the kernel's, powerd's bookkeeping): never gone", !MSBDSGOwnerGone(0, 0, "", "", 0, -1, T, T) && !MSBDSGOwnerGone(-1, 0, "", "", 0, -1, T, T));
    check("the live owner, started before its assertion: not gone",
          !MSBDSGOwnerGone(12538, 1, "SpringBoard", "SpringBoard", T - 3600, 3000, T - 1800, T));
    check("pid reused by another program (iPad 2's pid 137 after a wrap: another daemon there now): gone",
          MSBDSGOwnerGone(137, 1, "mobileassetd", "SpringBoard", T - 60, 50, T - 86400, T));
    check("pid reused by the same program, started after the assertion was made: gone",
          MSBDSGOwnerGone(137, 1, "SpringBoard", "SpringBoard", T - 60, 50, T - 86400, T));
    check("  ... started within 2 s of it (one start, the clock's rounding): not gone",
          !MSBDSGOwnerGone(12538, 1, "SpringBoard", "SpringBoard", T - 600, 500, T - 601, T));
    check("another program at the pid, its start time unknown or the clock set back (times not compared): gone by the name alone",
          MSBDSGOwnerGone(137, 1, "mobileassetd", "SpringBoard", 0, -1, T - 86400, T)
          && MSBDSGOwnerGone(137, 1, "mobileassetd", "SpringBoard", T + 3600, -1, T - 600, T));
    check("names cut to 16 bytes on one side, 32 on the other (the same process): not gone",
          !MSBDSGOwnerGone(900, 1, "com.apple.WebKit", "com.apple.WebKit.WebContent", T - 600, 500, T - 300, T)
          && !MSBDSGOwnerGone(900, 1, "com.apple.WebKit.WebContent", "com.apple.WebKit", T - 600, 500, T - 300, T));
    check("a name unknown on either side: only the times decide",
          !MSBDSGOwnerGone(900, 1, "", "msbdcharge", T - 600, 500, T - 300, T) && !MSBDSGOwnerGone(900, 1, "msbdcharge", "", T - 600, 500, T - 300, T)
          && MSBDSGOwnerGone(900, 1, "", "", T - 60, 50, T - 300, T));
    check("start time unknown (the process's info not read): not gone by time",
          !MSBDSGOwnerGone(900, 1, "msbdcharge", "msbdcharge", 0, -1, T - 300, T) && !MSBDSGOwnerGone(900, 1, "msbdcharge", "msbdcharge", T - 60, 50, 0, T));
    // The wall clock set back (Date & Time by hand, a network time fix): a live process's later assertion "made before it started"
    check("clock set back a day, a live process's later assertion (process started \"in the future\"): not gone",
          !MSBDSGOwnerGone(1537, 1, "audiomxd", "audiomxd", T + 86400 - 7200, 7200, T - 600, T));
    check("  ... the same with the awake time unknown (the start \"in the future\" alone tells)",
          !MSBDSGOwnerGone(1537, 1, "audiomxd", "audiomxd", T + 86400 - 7200, -1, T - 600, T));
    check("  ... both \"in the future\" (set back after both), the awake time unknown: not gone",
          !MSBDSGOwnerGone(1537, 1, "audiomxd", "audiomxd", T + 4000, -1, T + 3600, T + 10));
    check("  ... set back 30 min, now past the process's start again (its wall age 5 min, awake 35 min): not gone",
          !MSBDSGOwnerGone(7167, 1, "msbdcharge", "msbdcharge", T - 300, 2100, T - 900, T));
    check("  ... a real reuse with the awake clock agreeing (wall age 60 s >= awake 50 s): gone",
          MSBDSGOwnerGone(7167, 1, "msbdcharge", "msbdcharge", T - 60, 50, T - 900, T));
    check("  ... the awake time unknown: the wall clock alone", MSBDSGOwnerGone(7167, 1, "msbdcharge", "msbdcharge", T - 60, -1, T - 900, T));
    // ---- stuck: MSBDSGStuck(type, level, ownerGone)
    check("a gone SpringBoard's SystemIsActive (BacklightServices.backlightActiveOn.startup) at 255: stuck", MSBDSGStuck("SystemIsActive", 255, 1));
    check("the same held by a live SpringBoard: not stuck", !MSBDSGStuck("SystemIsActive", 255, 0));
    check("a gone owner's PreventUserIdleSystemSleep / PreventSystemSleep / NoIdleSleepAssertion: stuck",
          MSBDSGStuck("PreventUserIdleSystemSleep", 255, 1) && MSBDSGStuck("PreventSystemSleep", 255, 1) && MSBDSGStuck("NoIdleSleepAssertion", 255, 1));
    check("a gone owner's assertion at level 0 (released): not stuck", !MSBDSGStuck("SystemIsActive", 0, 1));
    check("a gone owner's charge or push assertion (ChargeInhibit, DisableInflow, ApplePushServiceTask) does not keep the iPad awake: not ours to clear",
          !MSBDSGStuck("ChargeInhibit", 255, 1) && !MSBDSGStuck("DisableInflow", 255, 1) && !MSBDSGStuck("ApplePushServiceTask", 255, 1));
    check("unknown type, NULL: not stuck", !MSBDSGStuck(NULL, 255, 1) && !MSBDSGStuck("BackgroundTask", 255, 1));
    // ---- what else keeps the iPad awake: MSBDSGLiveOther(type, level, ownerGone, ownerIsPowerd, Process Name)
    check("Spotify playing (audiomxd's NoIdleSleepAssertion ...isplaying, live): keeps it awake, a restart would cut it off",
          MSBDSGLiveOther("NoIdleSleepAssertion", 255, 0, 0, "audiomxd"));
    check("a download / backup (nsurlsessiond's PreventUserIdleSystemSleep), runningboardd's SystemIsActive for an app: counted",
          MSBDSGLiveOther("PreventUserIdleSystemSleep", 255, 0, 0, "nsurlsessiond") && MSBDSGLiveOther("SystemIsActive", 255, 0, 0, "runningboardd"));
    check("powerd's own: not counted (it makes them again)", !MSBDSGLiveOther("PreventUserIdleSystemSleep", 255, 0, 1, "powerd"));
    check("the Charge Limit job's (msbdcharge, raises its own again within a second): not counted",
          !MSBDSGLiveOther("PreventUserIdleSystemSleep", 255, 0, 0, "msbdcharge"));
    check("a gone owner's (that is the stuck one), level 0, or a kind that does not keep the iPad awake: not counted",
          !MSBDSGLiveOther("SystemIsActive", 255, 1, 0, "SpringBoard") && !MSBDSGLiveOther("SystemIsActive", 0, 0, 0, "SpringBoard")
          && !MSBDSGLiveOther("DisableInflow", 255, 0, 0, "x") && !MSBDSGLiveOther(NULL, 255, 0, 0, "x"));
    check("the kernel's (pid 0, no name): counted (a restart does not end it, it keeps the iPad awake anyway)", MSBDSGLiveOther("PreventSystemSleep", 255, 0, 0, NULL));
    // ---- the decision: MSBDSGDecide(stuckSince, now, screenOff, liveOthers, guardOn, lastClear, clearsToday, oldestClear, &why, &again)
    const char *why = NULL; double now = 100000, again = -1;
    check("nothing stuck: nothing, no look planned", MSBDSGDecide(0, now, 1, 0, 1, 0, 0, 0, &why, &again) == kMSBDSGNothing && again == 0);
    check("stuck 30 s, screen off: wait, a look again when the minute is over (32 s)",
          MSBDSGDecide(now - 30, now, 1, 0, 1, 0, 0, 0, &why, &again) == kMSBDSGWait && again == 32);
    check("stuck 61 s, screen off, nothing else keeping it awake, never cleared: clear",
          MSBDSGDecide(now - 61, now, 1, 0, 1, 0, 0, 0, &why, &again) == kMSBDSGClear && !strcmp(why, "clearing"));
    check("  ... the screen on: wait, no look planned (never cleared while the iPad is in use; the next screen-off looks)",
          MSBDSGDecide(now - 600, now, 0, 0, 1, 0, 0, 0, &why, &again) == kMSBDSGWait && !strcmp(why, "the screen is on") && again == 0);
    check("  ... something else keeps it awake (audio, a download): wait, a look again in 5 min",
          MSBDSGDecide(now - 600, now, 1, 1, 1, 0, 0, 0, &why, &again) == kMSBDSGWait && !strcmp(why, "something else keeps the iPad awake") && again == 300);
    check("  ... Sleep Guard off: blocked (Settings shows it), no look planned",
          MSBDSGDecide(now - 600, now, 1, 0, 0, 0, 0, 0, &why, &again) == kMSBDSGBlocked && !strcmp(why, "Sleep Guard is off") && again == 0);
    check("  ... cleared 10 min ago: blocked (30 min between clears), a look again when the 30 min are over (1202 s)",
          MSBDSGDecide(now - 600, now, 1, 0, 1, now - 600, 1, now - 600, &why, &again) == kMSBDSGBlocked && again == 1202);
    check("  ... cleared 31 min ago: clear", MSBDSGDecide(now - 600, now, 1, 0, 1, now - 1860, 1, now - 1860, &why, &again) == kMSBDSGClear);
    check("  ... 6 clears today, the first 20 h ago: blocked, a look again when it is a day old (4 h 2 s)",
          MSBDSGDecide(now - 600, now, 1, 0, 1, now - 7200, 6, now - 72000, &why, &again) == kMSBDSGBlocked && !strcmp(why, "cleared 6 times today")
          && again == 14402);
    check("  ... 5 clears today, the last 2 h ago: clear", MSBDSGDecide(now - 600, now, 1, 0, 1, now - 7200, 5, now - 72000, &why, &again) == kMSBDSGClear);
    check("  ... something else awake AND cleared 10 min ago: wait for the live one first (5 min)",
          MSBDSGDecide(now - 600, now, 1, 2, 1, now - 600, 1, now - 600, &why, &again) == kMSBDSGWait && again == 300);
    check("NULL out-parameters are fine", MSBDSGDecide(now - 61, now, 1, 0, 1, 0, 0, 0, NULL, NULL) == kMSBDSGClear);
    // ---- Settings' row
    check("\"iPad Can't Sleep\": stuck and blocked", MSBDSGShowCantSleep(1, kMSBDSGBlocked, 0));
    check("  ... stuck and the last clear failed", MSBDSGShowCantSleep(1, kMSBDSGClear, 1));
    check("  ... not while it only waits (the screen on, something else awake, the minute), not when nothing is stuck",
          !MSBDSGShowCantSleep(1, kMSBDSGWait, 0) && !MSBDSGShowCantSleep(0, kMSBDSGBlocked, 1) && !MSBDSGShowCantSleep(1, kMSBDSGClear, 0));
    if (fails) { printf("test-sleepguard (compiled): FAILED\n"); return 1; }
    printf("test-sleepguard (compiled): all checks pass\n"); return 0;
}
