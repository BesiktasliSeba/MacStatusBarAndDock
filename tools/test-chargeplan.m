// test-chargeplan.m -- the Charge Limit's job (1.8.6): one job at a time, and a charge setting changed in Settings planned again at once.
// (1) An unknown word on the command line printed nothing and ran a second job beside launchd's (A12Z load test, 10 Nov: it moved the adapter cut
// for ~70 s): now usage and exit 2, nothing touched; and a second job finds the first one's lock and ends without touching anything.
// (2) Run on Power Adapter switched off at 98 % with an 80 % limit stayed on hold, silently, until a restart (17.5 load test, 10 Nov): the one cut
// start per 30 minutes had been used; a change made in Settings now starts a cut at once. tools/chargejob-sim.h runs the job.
// Scenarios (one per run): args, help, second, roaoff, roaon, roaoffsoc.
#include "chargejob-sim.h"

static int RunAs(int pid, int argc, const char *a1) {
    SimProcStart(pid, "msbdcharge");
    int was = gSimPid; gSimPid = pid;
    char *argv[] = { "msbdcharge", (char *)a1, NULL };
    int rc = msbdcharge_main(argc, argv);
    gSimPid = was;
    return rc;
}
static int HeldByPid(int pid) { int n = 0; for (int i = 0; i < gSAN; i++) if (gSA[i].pid == pid) n++; return n; }
static void Settings(int limit, int comeDown, int roa) {
    SimSettings(limit, comeDown);
    if (roa) gSimPrefs[@MSBD_CHARGE_ADAPTER_KEY] = @YES;
    notify_post(MSBD_CHARGE_PREFS_CHANGED);
}

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "args")) {   // an unknown word, with a limit set and the iPad on its charger above the limit
            SimIPad17(0); SimSettings(80, 1); B.soc = 90; SimSetGate();
            int rc = RunAs(720, 2, "--bogus");
            Expect("msbdcharge --bogus: exit 2, no job started, nothing raised, the battery still charging", rc == 2 && !SimLogHas("started") &&
                   SimOursHeld() == 0 && SimCharging());
        } else if (!strcmp(s, "help")) {
            SimIPad17(0); SimSettings(80, 1); B.soc = 90; SimSetGate();
            int rc = RunAs(720, 2, "--help");
            Expect("msbdcharge --help: exit 0, nothing started or raised", rc == 0 && !SimLogHas("started") && SimOursHeld() == 0);
        } else if (!strcmp(s, "second")) {   // launchd's job runs (coming down); a second one is started by hand
            SimIPad17(0); SimSettings(80, 1); B.soc = 90;
            SimStartJob(700);
            int held = SimOursHeld();
            Expect("the job runs: coming down to 80 %", SimPublishedState() == kMSBDChargeStateComingDown && held > 0);
            int rc = RunAs(701, 1, NULL);
            Expect("  ... a second job: exit 3, says so, raises and lets go of nothing", rc == 3 && SimLogHas("another Charge Limit job is running") &&
                   SimOursHeld() == held && HeldByPid(701) == 0 && SimPublishedState() == kMSBDChargeStateComingDown);
            SimKill(700);
            rc = RunAs(702, 1, NULL);
            Expect("  ... once the first is gone, the next one starts (the lock ended with it)", rc == 0 && HeldByPid(702) > 0);
        } else if (!strcmp(s, "roaoff") || !strcmp(s, "roaoffsoc")) {   // the 17.5's case (and the A12Z's, iPadOS's own charge limit)
            int soc = !strcmp(s, "roaoffsoc");
            if (soc) SimA12ZSoc(); else SimIPad17(0);
            SimSettings(80, 1); gSimPrefs[@MSBD_CHARGE_ADAPTER_KEY] = @YES; B.soc = 98;
            SimStartJob(700);
            Expect("an 80 % limit and Run on Power Adapter at 98 %: coming down to the limit (a cut starts)", SimPublishedState() == kMSBDChargeStateComingDown);
            SimMinutes(2);
            Settings(0, 1, 1);
            Expect("  ... the limit off, Run on Power Adapter alone: held where it is", SimPublishedState() == kMSBDChargeStateOnHold && !SimCharging());
            SimMinutes(3);
            Settings(80, 1, 0);
            Expect("  ... Run on Power Adapter off with the 80 % limit, 5 minutes after the cut began: coming down again at once, and said so",
                   SimPublishedState() == kMSBDChargeStateComingDown && SimLogHas("a charge setting changed") && !SimCharging());
            if (soc) Expect("  ... (iPadOS's charge limit) no policy of ours holds the battery up meanwhile", SimSocLive() == 0 || SimSocLevel() <= 80);
        } else if (!strcmp(s, "roaon")) {   // the reverse: on hold at the 80 % limit, then Run on Power Adapter on
            SimIPad17(0); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            Expect("an 80 % limit at 80 %: on hold", SimPublishedState() == kMSBDChargeStateOnHold);
            Settings(80, 1, 1);
            Expect("  ... Run on Power Adapter on: still held at 80 % (never above the limit), not charging, no cut, said so",
                   SimPublishedState() == kMSBDChargeStateOnHold && !SimCharging() && SimLogHas("a charge setting changed"));
            SimMinutes(10);
            Expect("  ... 10 minutes later: still on hold at 80 %", SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) == 80);
        }
    }
    return SimDone();
}
