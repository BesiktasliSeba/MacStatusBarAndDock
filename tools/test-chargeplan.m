// test-chargeplan.m -- the Charge Limit's job (1.8.6): one job at a time, and a charge setting changed in Settings planned again at once.
// (1) An unknown word on the command line printed nothing and ran a second job beside launchd's (A12Z load test, 10 Nov: it moved the adapter cut
// for ~70 s): now usage and exit 2, nothing touched; and a second job finds the first one's lock and ends without touching anything.
// (2) Run on Power Adapter switched off at 98 % with an 80 % limit stayed on hold, silently, until a restart (17.5 load test, 10 Nov): the one cut
// start per 30 minutes had been used; a change made in Settings now starts a cut at once. tools/chargejob-sim.h runs the job.
// (3) 1.8.8.1 BATTWHY (KT 15 Nov: the A12Z sat at "not charging" on a 7 W adapter, the footer said "Charging to 80%."): the job publishes why
// iPad is not charging on the adapter with its state (common/ChargeWhy.h), after 3 minutes for what only the current says, at once for what the
// battery states (a hold not ours, full); never for its own hold.
// (4) The review of (3): a hold of the job's own that ends is still its own while its bit lingers and the battery waits after it (Charge to Full
// Now after a hold said "Charging is on hold.", then "Not charging."); a weak adapter is said only once the battery has given 100 mA for 3 minutes.
// (5) The review of the line: where the hold does not take with the adapter ("can't pause charging"), the battery full at 100 % with an 80 % limit
// keeps that line after its reason, in the footer and the menu (it said "Fully charged." alone, the only word on why it is above the limit gone).
// Scenarios (one per run): args, help, second, roaoff, roaon, roaoffsoc, weak, weakpmu, weakours, otherhold, holdend, holdendsoc, holdendpmu,
// holdendweak, spike, full, cantholdfull.
#include "chargejob-sim.h"
#include "../common/BatteryMenu.h"   // (the menu's lines from the job's word: cantholdfull)
static int Why(void) { return MSBDChargeWordWhy(SimWord()); }
static NSString *Footer(void) { char t[600]; MSBDChargeFooterText(SimWord(), 80, 1, 0, t, sizeof t); return @(t); }
static void Look(double seconds) { SimAdvance(seconds); SimPowerSourceChanged(); }   // (time goes on, then a power source note: the job looks)
static int SimLogCount(const char *s) {
    NSString *log = [NSString stringWithContentsOfFile:@kLogFile encoding:NSUTF8StringEncoding error:nil] ?: @"";
    return (int)[log componentsSeparatedByString:@(s)].count - 1;
}

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
        } else if (!strcmp(s, "weak")) {   // KT's case: the A12Z (18.5, iPadOS's charge limit) on its 7 W adapter at 45 %, the battery powering part of it
            SimA12ZSoc(); B.watts = 7; B.soc = 45; gSimWeakMA = 800; SimSettings(80, 1);
            SimStartJob(700);
            Expect("KT's A12Z on its 7 W adapter at 45 %, an 80 % limit: the job lets it charge, it does not (reasons 0x0, -800 mA), no reason yet",
                   SimPublishedState() == kMSBDChargeStateCharging && !SimCharging() && Why() == kMSBDWhyNone);
            Look(179);
            Expect("  ... 179 s on: still none (the footer as before: \"Charging to 80%.\")", Why() == kMSBDWhyNone && [Footer() hasPrefix:@"Charging to 80%.\n\n"]);
            Look(1);
            Expect("  ... at 180 s: the power adapter too weak, its 7 W in the word, the state as it was (charging allowed)",
                   Why() == kMSBDWhyTooWeak && MSBDChargeWordWatts(SimWord()) == 7 && SimPublishedState() == kMSBDChargeStateCharging && MSBDChargeWordLimit(SimWord()) == 80);
            Expect("  ... Settings' footer: \"Not charging: the power adapter (7 W) gives less power than iPad is using.\" in place of \"Charging to 80%.\"",
                   [Footer() hasPrefix:@"Not charging: the power adapter (7 W) gives less power than iPad is using.\n\nWhile iPad is plugged in, charging stops at 80%"]);
            Expect("  ... the job's log says it once, with what it read", SimLogCount("not charging on the adapter: the power adapter is too weak (battery 4") == 1
                   && SimLogHas("-800 mA, adapter 7 W, reasons 0x0 / 0,"));
            SimMinutes(5);
            Expect("  ... 5 minutes on: still said, not logged again", Why() == kMSBDWhyTooWeak && SimLogCount("not charging on the adapter: the power adapter is too weak") == 1);
            gSimWeakMA = 0; B.watts = 17; Look(1);
            Expect("  ... on the 17 W charger: charging, the reason gone at the next look", SimCharging() && Why() == kMSBDWhyNone && [Footer() hasPrefix:@"Charging to 80%.\n\n"]);
        } else if (!strcmp(s, "weakpmu")) {   // the iPad 2 (16.7.7, PMU charger: no ChargerInhibitReason) on its 10 W brick, a load it cannot carry
            SimIPad2(); B.soc = 60; gSimWeakMA = 300; SimSettings(80, 1);
            SimStartJob(700);
            Look(120);
            Expect("the iPad 2 on its 10 W brick, not charging at 60 % (-300 mA), 2 minutes: none yet", Why() == kMSBDWhyNone);
            Look(60);
            Expect("  ... 3 minutes: the power adapter too weak (10 W)", Why() == kMSBDWhyTooWeak && MSBDChargeWordWatts(SimWord()) == 10);
        } else if (!strcmp(s, "weakours")) {   // the same 7 W adapter at the 80 % limit: the job's own hold
            SimA12ZSoc(); B.watts = 7; B.soc = 80; gSimWeakMA = 800; SimSettings(80, 1);
            SimStartJob(700);
            SimMinutes(6);
            Expect("the A12Z at its 80 % limit on the 7 W adapter: on hold (ours), no reason in 6 minutes, the footer's own line",
                   SimPublishedState() == kMSBDChargeStateOnHold && !SimCharging() && Why() == kMSBDWhyNone && [Footer() hasPrefix:@"Charging on hold. iPad is using the power adapter.\n\n"]);
        } else if (!strcmp(s, "otherhold")) {   // the M1 (15.6.1, SMC: holds obeyed) at 60 %, charging held by another process's ChargeInhibit
            SimM1(); B.soc = 60; SimSettings(80, 1);
            SimProcStart(900, "otherapp"); SimAddAssertion(900, "ChargeInhibit", "another app's charge hold");
            SimStartJob(700);
            Expect("the M1 at 60 %, an 80 % limit, charging held by another process (reasons 0x4000): the job lets it charge, \"on hold\" at once",
                   SimPublishedState() == kMSBDChargeStateCharging && !SimCharging() && Why() == kMSBDWhyOnHold && MSBDChargeWordWatts(SimWord()) == 0);
            Expect("  ... the footer: \"Charging is on hold.\"; the self-check's log line says why", [Footer() hasPrefix:@"Charging is on hold.\n\n"]
                   && SimLogHas("though allowed (adapter 17 W, 0 mA, reasons 0x4000; why: on hold (not ours)): hold raised and let go"));
            for (int i = 0; i < gSAN; i++) if (gSA[i].pid == 900) { SimRemoveAt(i); break; }
            Look(1);
            Expect("  ... the other hold let go: charging, no reason", SimCharging() && Why() == kMSBDWhyNone);
        } else if (!strcmp(s, "holdend") || !strcmp(s, "holdendsoc") || !strcmp(s, "holdendpmu")) {   // (1.8.8.1 review) the job's own hold ends
            // Charge to Full Now at the 80 % limit after 5 minutes on hold (the M1: ChargeInhibit; the A12Z: iPadOS's charge limit; the iPad 2: PMU),
            // the battery as the iPads showed it: the hold's bit read 20 s more, charging again 120 s after the hold ends (PostChargeWaitSeconds)
            int soc = !strcmp(s, "holdendsoc"), pmu = !strcmp(s, "holdendpmu");
            if (soc) SimA12ZSoc(); else if (pmu) SimIPad2(); else SimM1();
            uint64_t bit = soc ? 1ULL << 24 : pmu ? 0x8000 : 0x4000;
            B.soc = 80; SimSettings(80, 1); gSimHoldBitLinger = 20; gSimPostHoldWait = 120;
            SimStartJob(700);
            SimMinutes(5);
            Expect("at the 80 % limit for 5 minutes: on hold (ours), not charging, no reason", SimPublishedState() == kMSBDChargeStateOnHold && !SimCharging() && Why() == kMSBDWhyNone);
            notify_post(MSBD_CHARGE_FULL_NOW);
            #define REASONS() [Dict(SimBatteryProps()[@"ChargerData"])[@"NotChargingReason"] unsignedLongLongValue]
            Expect("  ... Charge to Full Now, the hold's bit still read (0x4000 / 0x1000000 / 0x8000): no reason (none \"not ours\" or \"by iPadOS\"), the footer \"Charging to 100% until iPad is unplugged.\"",
                   SimPublishedState() == kMSBDChargeStateToFull && (REASONS() & bit) && Why() == kMSBDWhyNone && [Footer() hasPrefix:@"Charging to 100% until iPad is unplugged.\n\n"]);
            Look(10);
            Expect("  ... 10 s on, the bit still there: none", (REASONS() & bit) && !SimCharging() && Why() == kMSBDWhyNone);
            Look(100);
            Expect("  ... 110 s on, the bit gone, the battery still in its 120 s wait (0 mA, reasons 0x0): none, not \"Not charging.\" (the 3 minutes count from the hold's end)",
                   REASONS() == 0 && !SimCharging() && Why() == kMSBDWhyNone && [Footer() hasPrefix:@"Charging to 100% until iPad is unplugged.\n\n"]);
            Look(15);
            Expect("  ... 125 s on: charging, none", SimCharging() && Why() == kMSBDWhyNone && SimPublishedState() == kMSBDChargeStateToFull);
        } else if (!strcmp(s, "holdendweak")) {   // the same on KT's 7 W adapter: once the hold ends the battery gives 800 mA
            SimA12ZSoc(); B.watts = 7; B.soc = 80; gSimWeakMA = 800; SimSettings(80, 1); gSimHoldBitLinger = 20; gSimPostHoldWait = 120;
            SimStartJob(700);
            SimMinutes(5);
            notify_post(MSBD_CHARGE_FULL_NOW);
            Look(1);
            Expect("KT's A12Z on 7 W, Charge to Full Now after 5 minutes on hold: a second later the bit 0x1000000 and -800 mA, no reason (the hold was ours, the drain just began)",
                   (REASONS() & (1ULL << 24)) && SimAmperage() == -800 && Why() == kMSBDWhyNone);
            Look(177);
            Expect("  ... 178 s after the hold's end: still none", Why() == kMSBDWhyNone);
            Look(4);
            Expect("  ... 3 minutes after it, the battery giving 800 mA all along: the power adapter too weak (7 W)", Why() == kMSBDWhyTooWeak && MSBDChargeWordWatts(SimWord()) == 7);
        } else if (!strcmp(s, "spike")) {   // (1.8.8.1 review) the M1 on its 17 W adapter, not charging for a cause no bit shows (-50 mA), a load spike
            SimM1(); B.soc = 60; gSimWeakMA = 50; SimSettings(80, 1);
            SimStartJob(700);
            Look(200);
            Expect("the M1 at 60 %, not charging for 200 s at -50 mA, reasons 0x0: \"Not charging.\", no reason guessed", Why() == kMSBDWhyNotCharging && [Footer() hasPrefix:@"Not charging.\n\n"]);
            gSimWeakMA = 1500; Look(1);
            Expect("  ... a load spike at the next look (-1500 mA): still \"Not charging.\" (one reading is not a weak adapter)", Why() == kMSBDWhyNotCharging);
            gSimWeakMA = 50; Look(5);
            Expect("  ... the spike over: the same", Why() == kMSBDWhyNotCharging);
            gSimWeakMA = 1500; Look(1); Look(60); Look(60); Look(59);
            Expect("  ... the battery giving 1500 mA again, for 179 s: still \"Not charging.\"", Why() == kMSBDWhyNotCharging);
            Look(1);
            Expect("  ... for 3 minutes: the power adapter too weak (17 W)", Why() == kMSBDWhyTooWeak && MSBDChargeWordWatts(SimWord()) == 17);
        } else if (!strcmp(s, "full")) {   // Charge to Full Now on the 17.5 (PMU, 10 W brick) at 99 %
            SimIPad17(0); B.soc = 99; SimSettings(80, 1);
            SimStartJob(700);
            notify_post(MSBD_CHARGE_FULL_NOW);
            Expect("the 17.5 at 99 %, Charge to Full Now: charging to 100 %, no reason", SimPublishedState() == kMSBDChargeStateToFull && SimCharging() && Why() == kMSBDWhyNone);
            SimMinutes(10);
            Expect("  ... at 100 %, no charge going in: fully charged, at once (the footer: \"Fully charged.\")",
                   (int)(B.soc + 0.5) == 100 && !SimCharging() && SimPublishedState() == kMSBDChargeStateToFull && Why() == kMSBDWhyFull && [Footer() hasPrefix:@"Fully charged.\n\n"]);
        } else if (!strcmp(s, "cantholdfull")) {   // (1.8.8.1, review of the line) the M1 at its 80 % limit on an adapter its hold does not take with
            SimM1(); B.holdObeyed = 0; B.soc = 78; SimSettings(80, 1);
            SimStartJob(700);
            SimMinutes(15);
            Expect("the M1 at an 80 % limit, the hold not taking with this adapter: given up, \"can't pause charging\", iPadOS charging, no reason",
                   SimPublishedState() == kMSBDChargeStateCantHold && SimCharging() && Why() == kMSBDWhyNone && [Footer() hasPrefix:@MSBD_CHARGE_CANT_PAUSE_TEXT "\n\n"]);
            SimMinutes(60);
            Expect("  ... at 100 % (no charge going in), still can't pause: fully charged, and the footer still says why it is above 80 %: "
                   "\"Fully charged. iPad can't pause charging with this power adapter, ...\" (it said \"Fully charged.\" alone)",
                   (int)(B.soc + 0.5) == 100 && !SimCharging() && SimPublishedState() == kMSBDChargeStateCantHold && Why() == kMSBDWhyFull
                   && [Footer() hasPrefix:@"Fully charged. " MSBD_CHARGE_CANT_PAUSE_TEXT "\n\nWhile iPad is plugged in, charging stops at 80%"]);
            char l1[96], l2[96];
            int n1 = MSBDBattMenuLine(SimWord(), 100, Why(), 0, l1, sizeof l1), n2 = MSBDBattMenuLineAfter(SimWord(), 100, Why(), 0, l2, sizeof l2);
            Expect("  ... the menu's lines from the same word: \"Fully Charged\", then \"Charging Can't Be Paused\"",
                   n1 && n2 && !strcmp(l1, "Fully Charged") && !strcmp(l2, "Charging Can't Be Paused"));
        }
    }
    return SimDone();
}
