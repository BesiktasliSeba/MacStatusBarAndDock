// test-chargeverify.m -- the Charge Limit's hold and adapter cut are checked against the battery, and one that does not take is given up for the
// plug-in: nothing held, nothing cut, no stay-awake, iPadOS's own charging, said so (tools/chargejob-sim.h runs the job).
// The A12Z (18.5): powerd held our ChargeInhibit, yet 2.2-2.9 A went in with not-charging reasons 0 at every hold of the 72-hour run; the job
// went on to the cut at 83 % and back to the hold at 80 % for two days, the iPad kept awake in 173 of 187 readings (run72-a12z.log). The 17.5 on
// a 19 W adapter (6 Nov): 93 % at the job's "coming down", 100 % half an hour later (regression-1.8.2.2-ipad17.md N3); on its 5-10 W brick both
// held (run72-ipad17.log).
// Charge going in is an Amperage reading over 100 mA or IsCharging 1; a level 3 % up counts only with it (a gauge correction is no charge), and a
// missing Amperage reading is never "it takes".
// A hold remembered as not taking is remembered for that build of the job too (newbuild-first, then newbuild-next in a second process).
// Scenarios (one per run): a12z, pd17, m1, brick17, replug, remember, otherprefs, gauge, noamp, noreadings, newbuild-first, newbuild-next.
#include "chargejob-sim.h"
#ifndef SIM_BUILD
#define SIM_BUILD 1   // (test-chargeverify.sh also builds this test with SIM_BUILD 2: another build of the job, another executable UUID)
#endif

enum { kTestCantHold = 7 };   // the state word's "can't pause charging" (common/ChargeLimit.h kMSBDChargeStateCantHold, pinned in test-chargelimit.c)
static int gCutSeen, gAwakeAfter, gMaxSoc, gMaxHeldSoc;
static void Watch(int minutes, int fromMinute) {   // the job's minutes, with what it held each minute
    for (int i = 0; i < minutes; i++) {
        SimMinutes(1);
        if (SimHeldBy(gSimJobPid, "DisableInflow")) gCutSeen++;
        if (i >= fromMinute && SimHeldBy(gSimJobPid, "PreventUserIdleSystemSleep")) gAwakeAfter++;
        int soc = (int)(B.soc + 0.5);
        if (soc > gMaxSoc) gMaxSoc = soc;
        if (SimPublishedState() == kMSBDChargeStateOnHold && soc > gMaxHeldSoc) gMaxHeldSoc = soc;   // (the level while the job said "on hold")
    }
}

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "a12z")) {   // charging to 80 % on the A12Z, whose charger does not keep powerd's hold
            SimA12Z(); SimSettings(80, 1); B.soc = 78.6;
            SimStartJob(500);
            Watch(60, 15);
            Expect("the A12Z's hold that lets 2.5 A in is given up: state \"can't pause charging\"", SimPublishedState() == kTestCantHold);
            Expect("  ... no cut started in its place (the sawtooth of the long run)", gCutSeen == 0);
            Expect("  ... no hold, cut or stay-awake of ours left with powerd; not kept awake after the first 15 minutes", SimOursHeld() == 0 && gAwakeAfter == 0);
            Expect("  ... given up by 83 % (3 % above where the hold went up), and said why", gMaxHeldSoc <= 83 && SimLogHas("does not take"));
            Expect("  ... the battery charges as it would without the job", SimCharging() || B.soc >= 99.5);
        } else if (!strcmp(s, "pd17")) {   // the 17.5 plugged in at 93 % on the 19 W adapter: neither the cut nor the inhibit key takes
            SimIPad17(1); SimSettings(80, 1); B.soc = 93;
            SimStartJob(500);
            Expect("plugged in at 93 % with an 80 % limit: coming down (the cut)", SimHeldBy(500, "DisableInflow"));
            Watch(30, 15);
            Expect("the cut that lets charge in is given up, then the inhibit key that does too: state \"can't pause charging\"", SimPublishedState() == kTestCantHold);
            Expect("  ... nothing left: no cut, no stay-awake, the inhibit key cleared", SimOursHeld() == 0 && !B.pci && gAwakeAfter == 0);
            Expect("  ... the job says why", SimLogHas("does not take"));
        } else if (!strcmp(s, "m1")) {   // the M1: its charger keeps the hold
            SimM1(); SimSettings(80, 1); B.soc = 79;
            SimStartJob(500);
            Watch(90, 30);
            Expect("the M1 charges to 80 % and holds there for an hour and more (the hold takes: nothing given up)", SimHeldBy(500, "ChargeInhibit") &&
                   SimPublishedState() == kMSBDChargeStateOnHold && SimAmperage() == 0 && gMaxSoc <= 81 && !SimLogHas("does not take"));
        } else if (!strcmp(s, "brick17")) {   // the 17.5 on its brick: the cut and the inhibit key take
            SimIPad17(0); SimSettings(80, 1); B.soc = 93; B.loadMA = 1500;
            SimStartJob(500);
            Watch(120, 200);
            Expect("on its brick the 17.5 comes down from 93 % to 80 % and holds with the inhibit key (nothing given up)", B.pci && SimPublishedState() == kMSBDChargeStateOnHold &&
                   (int)(B.soc + 0.5) <= 80 && (int)(B.soc + 0.5) >= 75 && !SimLogHas("does not take"));
        } else if (!strcmp(s, "replug")) {   // given up for that plug-in and that adapter: another adapter is tried again
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            Watch(30, 100);
            Expect("given up on the A12Z", SimPublishedState() == kTestCantHold);
            B.cable = 0; SimPowerSourceChanged(); SimMinutes(1);
            Expect("unplugged: nothing held, state off", SimOursHeld() == 0 && SimPublishedState() == kMSBDChargeStateOff);
            B.soc = 80.2; B.family = (long long)0xFFFFFFFFE0004003ULL; B.desc = "usb brick"; B.cable = 1; SimPowerSourceChanged();
            Expect("plugged in again at 80 % with another adapter: the hold is tried again", SimHeldBy(500, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateOnHold);
        } else if (!strcmp(s, "remember")) {   // the A12Z's day: given up, charged to 100 %, used, plugged in again at 90 %
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            Watch(60, 100);
            Expect("given up on the A12Z at the first plug-in", SimPublishedState() == kTestCantHold);
            B.cable = 0; SimPowerSourceChanged(); B.loadMA = 1500; Watch(240, 1000);
            B.soc = 90; B.loadMA = 120; B.cable = 1; SimPowerSourceChanged();
            gCutSeen = 0; gAwakeAfter = 0;
            Watch(120, 0);
            Expect("plugged in again at 90 % with the same adapter: no cut and no stay-awake for a hold known not to take (remembered for 7 days)",
                   gCutSeen == 0 && gAwakeAfter == 0 && SimPublishedState() == kTestCantHold);
            gSimNow += 8 * 86400; B.cable = 0; SimPowerSourceChanged(); B.soc = 79.6; B.cable = 1; SimPowerSourceChanged(); SimMinutes(1);
            Expect("  ... 8 days later the hold is tried again", SimHeldBy(500, "ChargeInhibit"));
        } else if (!strcmp(s, "otherprefs")) {   // the memory and the tweak's other settings: about 50 rows of Status Bar, Windows and Live Activities
                                                 // post the same note as the charge rows (MSBD_CHARGE_PREFS_CHANGED, the tweak-wide name)
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            Watch(60, 100);
            Expect("given up on the A12Z at the first plug-in", SimPublishedState() == kTestCantHold);
            B.cable = 0; SimPowerSourceChanged(); B.loadMA = 1500; Watch(60, 1000);
            gSimPrefs[@"showSeconds"] = @YES; notify_post(MSBD_CHARGE_PREFS_CHANGED);   // (a Status Bar row)
            B.soc = 90; B.loadMA = 120; B.cable = 1; SimPowerSourceChanged();
            gCutSeen = 0; gAwakeAfter = 0;
            Watch(60, 0);
            Expect("a Status Bar setting changed, then plugged in again at 90 %: still remembered (no cut, no stay-awake)",
                   gCutSeen == 0 && gAwakeAfter == 0 && SimPublishedState() == kTestCantHold);
            gSimPrefs[@MSBD_CHARGE_LIMIT_KEY] = @85; notify_post(MSBD_CHARGE_PREFS_CHANGED);   // (the Charge Limit row)
            Expect("  ... the Charge Limit changed to 85 %: the hold is tried again (coming down to it), and said why", SimHeldBy(500, "DisableInflow") &&
                   SimPublishedState() == kMSBDChargeStateComingDown && SimLogHas("a charge setting changed: the hold will be tried again"));
        } else if (!strcmp(s, "gauge")) {   // Run on Power Adapter on the M1, held for hours; then the gauge corrects itself 3 % up, no charge going in
            SimM1(); SimSettings(0, 1); gSimPrefs[@MSBD_CHARGE_ADAPTER_KEY] = @YES; B.soc = 55;
            SimStartJob(500);
            Watch(120, 1000);
            Expect("held at 55 % with Run on Power Adapter", SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) == 55);
            B.soc = 58;
            Watch(30, 1000);
            Expect("  ... the gauge 3 % up with no charge going in: the hold kept (not \"does not take\", nothing remembered)",
                   SimPublishedState() == kMSBDChargeStateOnHold && SimHeldBy(500, "ChargeInhibit") && SimAmperage() == 0 && !SimLogHas("does not take"));
        } else if (!strcmp(s, "noamp")) {   // the A12Z with no Amperage reading: IsCharging 1 is charge going in, the hold does not "take"
            SimA12Z(); SimSettings(80, 1); B.soc = 78.6; gSimNoAmperage = 1;
            SimStartJob(500);
            Watch(120, 30);
            Expect("no Amperage reading, IsCharging 1 under the hold: given up (\"can't pause charging\"), no cut, not kept awake (no sawtooth)",
                   SimPublishedState() == kTestCantHold && gCutSeen == 0 && gAwakeAfter == 0 && SimLogHas("the hold does not take here"));
        } else if (!strcmp(s, "noreadings")) {   // the M1 with neither Amperage nor IsCharging read: whether the hold takes cannot be told
            SimM1(); SimSettings(80, 1); B.soc = 79.6; gSimNoAmperage = gSimNoIsCharging = 1;
            SimStartJob(500);
            Watch(30, 100);
            Expect("no Amperage or IsCharging reading: the hold not taken to work, given up for the plug-in (iPadOS charges as always), said why",
                   SimPublishedState() == kTestCantHold && SimOursHeld() == 0 && SimLogHas("the hold cannot be checked here"));
            B.cable = 0; SimPowerSourceChanged(); B.soc = 79.6; B.cable = 1; SimPowerSourceChanged();
            Expect("  ... not remembered for the adapter: tried again at the next plug-in", SimHeldBy(500, "ChargeInhibit"));
        } else if (!strcmp(s, "newbuild-first")) {   // the A12Z's hold given up and remembered under one build of the job ...
            printf("(the job's build %d)\n", SIM_BUILD);
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            Watch(30, 100);
            Expect("given up on the A12Z (remembered for the adapter)", SimPublishedState() == kTestCantHold);
        } else if (!strcmp(s, "newbuild-next")) {   // ... then, 3 hours on, the job started again (the same build, or a new one) and plugged in again
            int tried = argc > 2 && !strcmp(argv[2], "tried");
            printf("(the job's build %d)\n", SIM_BUILD);
            gSimNow += 3 * 3600;
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            if (tried) Expect("another build of the job: the hold is tried again (a later build may hold where the last one could not)", SimHeldBy(500, "ChargeInhibit"));
            else Expect("the same build: still remembered, nothing held", !SimHeldBy(500, "ChargeInhibit") && SimPublishedState() == kTestCantHold);
        } else { printf("unknown scenario %s\n", s); return 2; }
    }
    return SimDone();
}
