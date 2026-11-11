// test-chargeleftover.m -- a hold or adapter cut of the Charge Limit's that no job holds any more is cleared when it is in the way (tools/
// chargejob-sim.h runs the job). powerd kept three "Charge Limit (on hold)" holds on the M1 after their jobs were gone (5-7 Nov, listed under
// dead pids, one as dasd's); with the job removed, the M1 did not charge at 80 % on the adapter (regression-1.8.2-m1.md F3): a raise-and-let-go
// of ours does not lower a kind someone else still holds, and nobody but the owner process can let go of an assertion. Only a powerd restart
// drops it, as the Sleep Guard does for a dead process's keep-awake one.
// The job clears one only as the Sleep Guard clears a stuck keep-awake (common/SleepGuard.h): the screen off, no live keep-awake assertion of
// another process (the restart drops those too), and only one that visibly blocks what the job does with the cable in.
// --reset (the prerm) looks again after it started powerd over, and raises and lets go until the new powerd takes it.
// A running job is told when --reset starts powerd over (it raises its own anew), and launchctl is not waited for past 15 s.
// Scenarios (one per run): f3-reset, f3-slowpowerd, f3-kickfails, job-allow, job-hold, transient, limits, byhand, byhand-leftover, hang, unplugged,
// screenon, liveawake, a12z, sleepguard.
#include "chargejob-sim.h"

static void LeaveLeftover(int pid, const char *proc, const char *type, const char *name) {   // a job that powerd did not let go of at its end
    SimProcStart(pid, "msbdcharge");
    SimStaleRecord(pid, proc);
    SimAddAssertion(pid, type, name);
    SimKill(pid);
}
static void ScheduleWakes(void) {   // an alarm ahead, another one ahead, one already past
    IOPMSchedulePowerEvent((__bridge CFDateRef)[NSDate dateWithTimeIntervalSince1970:gSimNow + 3600], CFSTR("com.apple.alarm"), CFSTR("wake"));
    IOPMSchedulePowerEvent((__bridge CFDateRef)[NSDate dateWithTimeIntervalSince1970:gSimNow + 7200], CFSTR("com.apple.dasd"), CFSTR("wakepoweron"));
    IOPMSchedulePowerEvent((__bridge CFDateRef)[NSDate dateWithTimeIntervalSince1970:gSimNow - 60], CFSTR("com.apple.old"), CFSTR("wake"));
}
static int WakesBack(void) {
    int alarm = 0, dasd = 0, old = 0;
    for (NSDictionary *e in gSimWakes) {
        if ([e[@"scheduledby"] isEqual:@"com.apple.alarm"]) alarm++;
        if ([e[@"scheduledby"] isEqual:@"com.apple.dasd"]) dasd++;
        if ([e[@"scheduledby"] isEqual:@"com.apple.old"]) old++;
    }
    return alarm == 1 && dasd == 1 && old == 0;
}

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "f3-reset")) {   // the M1 of F3: a dead job's hold with powerd, the package removed (its prerm: --stop, unload, --reset)
            SimM1(); SimSettings(80, 1); B.soc = 80; SimSetGate();
            LeaveLeftover(97622, "dasd", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            ScheduleWakes();
            SimMinutes(4);
            Expect("a dead job's hold with powerd: the M1 does not charge at 80 % (F3)", !SimCharging());
            SimCommand(601, "--stop");
            SimCommand(602, "--reset");
            SimMinutes(3);
            Expect("after the prerm's --reset: no hold of the Charge Limit's left with powerd", SimOursHeld() == 0);
            Expect("  ... the battery charges again", B.allowCharge && SimCharging());
            Expect("  ... powerd started over once", gSimPowerdRestarts == 1);
            Expect("  ... the wakes still ahead scheduled again, the past one not", WakesBack());
        } else if (!strcmp(s, "f3-slowpowerd")) {   // the same at removal, but the new powerd answers only 6 s after its start (--reset waited 3 s)
            SimM1(); SimSettings(80, 1); B.soc = 80; SimSetGate(); gSimPowerdSlow = 6;
            LeaveLeftover(97622, "dasd", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            ScheduleWakes();
            SimCommand(601, "--stop");
            SimCommand(602, "--reset");
            SimMinutes(3);
            Expect("powerd slow to answer after --reset started it over: the hold let go all the same, the battery charges (no F3)",
                   B.allowCharge && SimCharging() && SimOursHeld() == 0 && gSimPowerdRestarts == 1);
            Expect("  ... the wakes still ahead scheduled again once it answers, the past one not", WakesBack());
        } else if (!strcmp(s, "f3-kickfails")) {   // the same at removal, but launchctl's first kickstart of powerd fails
            SimM1(); SimSettings(80, 1); B.soc = 80; SimSetGate(); gSimKickstartFails = 1;
            LeaveLeftover(97622, "dasd", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimCommand(601, "--stop");
            SimCommand(602, "--reset");
            SimMinutes(3);
            Expect("the first powerd restart failed: --reset looks again, starts it over once more; the hold gone, the battery charges (no F3)",
                   gSimPowerdRestarts == 1 && SimOursHeld() == 0 && B.allowCharge && SimCharging());
        } else if (!strcmp(s, "job-allow")) {   // the job running, charging allowed (60 % under an 80 % limit): the leftover hold is in the way
            SimM1(); SimSettings(80, 1); B.soc = 60; SimScreenOff(1);
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            Expect("the job allows charging at 60 %, but the leftover hold keeps the battery from it", SimPublishedState() == kMSBDChargeStateCharging && !SimCharging());
            Expect("  ... not cleared at once (a job that just ended is let go of within moments)", gSimPowerdRestarts == 0);
            SimMinutes(2);
            Expect("seen for a minute and in the way: cleared (powerd started over), the battery charges", gSimPowerdRestarts == 1 && SimLeftovers() == 0 && SimCharging());
            SimMinutes(10);
            Expect("  ... once: nothing more to clear", gSimPowerdRestarts == 1);
        } else if (!strcmp(s, "job-hold")) {   // the job holds at 80 % itself: the leftover hold is not in the way until charging is allowed again
            SimM1(); SimSettings(80, 1); B.soc = 80; SimScreenOff(1);
            LeaveLeftover(19464, "backboardd", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            SimMinutes(5);
            Expect("on hold at 80 % with a leftover hold beside ours: powerd not started over", SimHeldBy(500, "ChargeInhibit") && gSimPowerdRestarts == 0);
            B.soc = 74.6; SimMinutes(2);
            Expect("down to 75 % (charging again by the band): the leftover cleared, the battery charges", gSimPowerdRestarts == 1 && SimCharging() && !SimHeldBy(19464, "ChargeInhibit"));
        } else if (!strcmp(s, "transient")) {   // an install: the old job's hold still listed for 20 s while the new job starts
            SimM1(); SimSettings(80, 1); B.soc = 60; SimScreenOff(1);
            SimProcStart(400, "msbdcharge"); SimAddAssertion(400, "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            SimAdvance(20); SimKill(400);   // (powerd sees the old job's end: let go)
            SimMinutes(5);
            Expect("an old job's hold that goes within moments is not cleared (no powerd restart), the battery charges", gSimPowerdRestarts == 0 && SimCharging());
        } else if (!strcmp(s, "limits")) {   // leftovers again and again: at most once in 30 minutes
            SimM1(); SimSettings(80, 1); B.soc = 60; SimScreenOff(1);
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            SimMinutes(2);
            LeaveLeftover(71136, "msbdcharge", "DisableInflow", "MacStatusBar&Dock Charge Limit (coming down to the limit)");
            SimMinutes(10);
            Expect("a second leftover 2 minutes after a clear: not cleared again within 30 minutes", gSimPowerdRestarts == 1);
            SimMinutes(25);
            Expect("  ... cleared once the 30 minutes are over: the adapter back", gSimPowerdRestarts == 2 && B.allowInflow && SimLeftovers() == 0);
        } else if (!strcmp(s, "byhand")) {   // msbdcharge --reset run by hand while the job holds: the job's hold is no leftover
            SimM1(); SimSettings(80, 1); B.soc = 80; SimScreenOff(1);
            SimStartJob(500);
            SimCommand(602, "--reset");
            SimMinutes(2);
            Expect("--reset by hand while the job holds at 80 %: powerd not started over, the job's hold kept", gSimPowerdRestarts == 0 && SimHeldBy(500, "ChargeInhibit"));
            SimProcStart(700, "msbdcharge"); { int was = gSimPid; gSimPid = 700; SimAddAssertion(700, "ChargeInhibit", "MacStatusBar&Dock Charge Limit (reset)"); gSimPid = was; }
            B.soc = 74; SimMinutes(3);
            Expect("  ... nor by the job for a live helper's raise-and-let-go (msbdcharge --reset still running)", gSimPowerdRestarts == 0);
        } else if (!strcmp(s, "byhand-leftover")) {   // msbdcharge --reset by hand while the job holds, a dead job's hold beside it: powerd started over
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimCommand(602, "--reset");
            Expect("--reset by hand clears a dead job's hold while the job holds: the job told powerd started over, its hold with the new powerd at once, still held",
                   gSimPowerdRestarts == 1 && SimLeftovers() == 0 && SimHeldBy(500, "ChargeInhibit") && !SimCharging());
        } else if (!strcmp(s, "hang")) {   // launchctl hangs when the job starts powerd over for a leftover: the job's only thread must not hang with it
            SimM1(); SimSettings(80, 1); B.soc = 60; SimScreenOff(1); gSimLaunchctlHangs = 3600;
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            double t0 = gSimNow;
            SimMinutes(2);
            Expect("launchctl hangs: the job stops waiting for it within seconds (not frozen for the hour it hangs), and says so",
                   gSimNow - t0 < 300 && SimLogHas("launchctl did not finish within 15 s"));
        } else if (!strcmp(s, "unplugged")) {   // the first upgrade onto this build (the old prerm) left the M1's hold; off the cable it blocks nothing
            SimM1(); SimSettings(80, 1); B.soc = 70; B.cable = 0; SimScreenOff(1);
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            SimMinutes(30);
            Expect("a leftover hold off the cable (it blocks nothing there): powerd not started over", gSimPowerdRestarts == 0);
            B.cable = 1; SimPowerSourceChanged();
            SimMinutes(2);
            Expect("  ... plugged in, charging kept off by it: cleared, the battery charges", gSimPowerdRestarts == 1 && SimLeftovers() == 0 && SimCharging());
        } else if (!strcmp(s, "screenon")) {   // the leftover in the way while iPad is in use: cleared only once the screen is off, as the Sleep Guard does
            SimM1(); SimSettings(80, 1); B.soc = 60; SimScreenOff(0);
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            SimMinutes(20);
            Expect("a leftover hold keeping charging off with the screen on: powerd not started over, and the job says why",
                   gSimPowerdRestarts == 0 && SimLogHas("keeps charging off: not cleared yet (the screen is on)"));
            SimScreenOff(1); SimMinutes(2);
            Expect("  ... the screen off: cleared, the battery charges", gSimPowerdRestarts == 1 && SimLeftovers() == 0 && SimCharging());
        } else if (!strcmp(s, "liveawake")) {   // a download keeps iPad awake: a powerd restart would drop that and let iPad idle-sleep under it
            SimM1(); SimSettings(80, 1); B.soc = 60; SimScreenOff(1);
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimProcStart(900, "nsurlsessiond");
            uint32_t dl = SimAddAssertion(900, "PreventUserIdleSystemSleep", "com.apple.nsurlsessiond.download");
            SimStartJob(500);
            SimMinutes(20);
            Expect("a leftover hold in the way while another app's keep-awake is live: powerd not started over, the download's kept, said why",
                   gSimPowerdRestarts == 0 && SimHeldBy(900, "PreventUserIdleSystemSleep") &&
                   SimLogHas("not cleared yet (something else keeps the iPad awake: PreventUserIdleSystemSleep \"com.apple.nsurlsessiond.download\" (nsurlsessiond 900))"));
            { int was = gSimPid; gSimPid = 900; IOPMAssertionRelease(dl); gSimPid = was; }
            SimMinutes(2);
            Expect("  ... the download done: cleared, the battery charges", gSimPowerdRestarts == 1 && SimLeftovers() == 0 && SimCharging());
        } else if (!strcmp(s, "a12z")) {   // the A12Z's charger ignores the hold on 18.5: a leftover hold blocks nothing there
            SimA12Z(); SimSettings(80, 1); B.soc = 60; SimScreenOff(1);
            LeaveLeftover(71135, "msbdcharge", "ChargeInhibit", "MacStatusBar&Dock Charge Limit (on hold)");
            SimStartJob(500);
            SimMinutes(90);
            Expect("the A12Z charging through a leftover hold for 90 minutes: powerd never started over", gSimPowerdRestarts == 0 && SimLeftovers() == 1);
        } else if (!strcmp(s, "sleepguard")) {   // the Sleep Guard starts powerd over while the job holds: ours raised anew at once
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            SimPowerdRestart();
            notify_post("com.besiktasliseba.sleepguard.powerd-restarted");
            Expect("after the Sleep Guard's powerd restart the job's hold is with the new powerd at once (its death would let go of it again)", SimHeldBy(500, "ChargeInhibit"));
        } else { printf("unknown scenario %s\n", s); return 2; }
    }
    return SimDone();
}
