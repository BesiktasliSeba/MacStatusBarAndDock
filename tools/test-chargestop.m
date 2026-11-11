// test-chargestop.m -- the Charge Limit's job lets go of its hold and adapter cut before the package stops it (tools/chargejob-sim.h runs the job).
// The M1 kept three "Charge Limit (on hold)" holds with powerd after the job that raised them was gone (5-7 Nov), listed under dead pids with
// other programs' names (dasd, backboardd: a pid powerd still had a record of, from a process before ours), and with the job removed charging
// stayed off until a reboot (regression-1.8.2-m1.md F3). Each appeared across an install, whose prerm stops the job with Dopamine's launchctl
// unload: no SIGTERM the job sees, so whatever it held was left to powerd to let go at its death -- which powerd does not do for such a pid.
// The postinst unloads and loads the job too (a dpkg --configure run again has no prerm before it): it asks the job to let go first as well.
// Scenarios (one per run): prerm-smc / prerm-cut / prerm-pmu <the prerm's charge steps in order: stop, kill, reset>; postinst-smc <the postinst's:
// stop, kill, start>; stop-direct; stop-nojob.
#include "chargejob-sim.h"

static void RunPrerm(int argc, char **argv) {   // the steps as the prerm has them (test-chargestop.sh reads them from layout/DEBIAN/prerm)
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "stop")) SimCommand(601, "--stop");
        else if (!strcmp(argv[i], "kill")) SimKill(gSimJobPid);   // (launchctl unload: the job ends, no SIGTERM it sees)
        else if (!strcmp(argv[i], "reset")) SimCommand(602, "--reset");
    }
}

static void RunPostinst(int argc, char **argv) {   // the postinst's charge steps when it configures (test-chargestop.sh reads them from layout/DEBIAN/postinst)
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "stop")) SimCommand(601, "--stop");
        else if (!strcmp(argv[i], "kill")) SimKill(gSimJobPid);   // (launchctl unload: the job ends, no SIGTERM it sees)
        // ("start", launchctl load: a new job, a new process -- not run here: the check is what the old one left behind)
    }
}

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "postinst-smc")) {   // dpkg --configure run again (no prerm before it): the postinst unloads the job holding on a stale record
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStaleRecord(540, "dasd");
            SimStartJob(540);
            Expect("the job holds at 80 % (listed under dasd's name)", SimHeldBy(540, "ChargeInhibit"));
            RunPostinst(argc, argv);
            Expect("after the postinst's own stop and unload: no hold of the old job left with powerd, the battery allowed to charge",
                   SimOursHeld() == 0 && B.allowCharge);
            return SimDone();
        }
        if (!strcmp(s, "prerm-smc")) {   // the M1 on hold at 80 %, its job on a pid powerd knew as dasd's
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStaleRecord(500, "dasd");
            SimStartJob(500);
            Expect("the job holds at 80 % with powerd's ChargeInhibit (listed under dasd's name: the pid's earlier process)", SimHeldBy(500, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateOnHold);
            RunPrerm(argc, argv);
            SimMinutes(3);
            Expect("after the prerm: no hold or cut of the Charge Limit's left with powerd", SimOursHeld() == 0);
            Expect("  ... the battery charges again, iPadOS's own charging", B.allowCharge && SimCharging());
            Expect("  ... the published state says no job", SimWord() == 0);
        } else if (!strcmp(s, "prerm-cut")) {   // coming down from 95 %: the adapter cut and the stay-awake up when the package stops the job
            SimM1(); SimSettings(80, 1); B.soc = 95;
            SimStaleRecord(510, "backboardd");
            SimStartJob(510);
            Expect("the job comes down from 95 % with the adapter cut and keeps the iPad awake", SimHeldBy(510, "DisableInflow") && SimHeldBy(510, "PreventUserIdleSystemSleep"));
            [gSimPosts removeAllObjects];
            RunPrerm(argc, argv);
            SimMinutes(3);
            Expect("after the prerm: no hold, cut or stay-awake of the Charge Limit's left with powerd", SimOursHeld() == 0);
            Expect("  ... the adapter powers the iPad again and the battery charges", B.allowInflow && SimCharging());
            Expect("  ... SpringBoard was told the cut ends (no chime, no Lock Screen for it)", [gSimPosts containsObject:@MSBD_CHARGE_CUT_ENDING]);
        } else if (!strcmp(s, "prerm-pmu")) {   // the iPad 2 holding with PredictiveChargingInhibit (a key that does not end with the job)
            SimIPad2(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(520);
            Expect("the job holds the iPad 2 at 80 % with PredictiveChargingInhibit", B.pci && SimPublishedState() == kMSBDChargeStateOnHold);
            RunPrerm(argc, argv);
            SimMinutes(3);
            Expect("after the prerm: the inhibit key cleared, nothing of ours with powerd, charging again", !B.pci && SimOursHeld() == 0 && SimCharging());
        } else if (!strcmp(s, "stop-direct")) {
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(530);
            Expect("on hold at 80 %", SimHeldBy(530, "ChargeInhibit"));
            SimCommand(600, "--stop");
            Expect("msbdcharge --stop: the job let go of its hold at once", SimOursHeld() == 0 && B.allowCharge);
            Expect("  ... and published no job (what --stop waits for)", !((SimWord() >> 17) & 1));
            SimPowerSourceChanged(); SimMinutes(1);
            Expect("  ... a power change a minute later raises nothing (it is about to be stopped)", SimOursHeld() == 0);
            SimMinutes(2);
            Expect("  ... not stopped after 2 minutes (the package step failed): back at work, on hold again", SimHeldBy(530, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateOnHold);
        } else if (!strcmp(s, "stop-nojob")) {   // the prerm on an iPad whose job is not running: --stop neither waits long nor raises anything
            SimM1(); SimSettings(80, 1); B.soc = 80; SimSetGate();
            double t0 = gSimNow;
            SimCommand(600, "--stop");
            Expect("msbdcharge --stop with no job: nothing raised, nothing published, back within 3 s", SimOursHeld() == 0 && SimWord() == 0 && gSimNow - t0 <= 3.5);
        } else { printf("unknown scenario %s\n", s); return 2; }
    }
    return SimDone();
}
