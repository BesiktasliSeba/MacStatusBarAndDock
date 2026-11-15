// test-chargeprefsd.m -- the Charge Limit's job follows the settings after cfprefsd starts over (1.8.7.4, audit M2 of 1.8.7.2; tools/chargejob-sim.h
// runs the job). The job runs as root and read mobile's settings from its own CoreFoundation copy, which is never refreshed once cfprefsd has
// started over (killall cfprefsd: many package scripts run it; 1.3.3 saw it in sshtoggled on the iPad 2): a Charge Limit switched off or changed
// in Settings, Run on Power Adapter switched off, coming down switched off, or the safe mode, was ignored until a reboot -- the iPad still stopped
// at the old limit and the job never ended. The job now notes the cfprefsd processes its copy belongs to, and once they changed reads the settings
// through a fresh process of its own (msbdcharge --settings), keeping its hold, its cut and its stay-awake as they are.
// Review of the fix: a cfprefsd that only appears (mobile's own, started after the job) is no restart, so no process is started for it; one the
// job's own read starts is noted after that read; and when none could be listed before the job's first read, the copy counts as old from the start.
// Scenarios (one per run): off, change, adapter, comedown, silent, silentfirst, down, later, hang, hangfirst, gate, unchanged, boot, bootrestart,
// nolist, duringfirst, agent, agentread, agentnolist.
#include "chargejob-sim.h"

static uint32_t HoldID(int pid) { for (int i = 0; i < gSAN; i++) if (gSA[i].pid == pid && !strcmp(gSA[i].type, "ChargeInhibit")) return gSA[i].id; return 0; }
static uint32_t CutID(int pid) { for (int i = 0; i < gSAN; i++) if (gSA[i].pid == pid && !strcmp(gSA[i].type, "DisableInflow")) return gSA[i].id; return 0; }
static int gChargedMeanwhile;   // the battery was let charge at some look (the hold blinked off)
static void Looks(int minutes) { for (int i = 0; i < minutes; i++) { SimMinutes(1); if (B.allowCharge) gChargedMeanwhile = 1; } }
static int PostsOf(const char *name) { int n = 0; for (NSString *p in gSimPosts) if ([p isEqualToString:@(name)]) n++; return n; }
static int Soc(void) { return (int)(B.soc + 0.5); }

// The M1 on hold at 80 % (its charger keeps powerd's hold), cfprefsd started over under it; the hold kept through it and the looks after.
static void HoldingThenRestart(int down) {
    SimM1(); SimSettings(80, 1); B.soc = 80;
    SimStartJob(500);
    uint32_t hold = HoldID(500);
    Expect("on hold at 80 % before cfprefsd starts over", hold && SimPublishedState() == kMSBDChargeStateOnHold);
    SimPrefsdRestart(down);
    Looks(3);
    Expect("  ... after the restart the job keeps its hold as it was (the same assertion, never let go, no charge let in meanwhile)",
           HoldID(500) == hold && !gChargedMeanwhile && SimPublishedState() == kMSBDChargeStateOnHold);
}

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "off")) {   // the audit's case: the limit switched off in Settings after the restart
            HoldingThenRestart(0);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("Charge Limit set to Off after the restart: the hold is let go at once, the battery charges", SimOursHeld() == 0 && B.allowCharge && SimCharging());
            Expect("  ... and the job ends (nothing set), saying no job", gSimJobEnded && SimWord() == 0);
            Expect("  ... the job said it reads the settings by a fresh process", SimLogHas("cfprefsd started over since the job began"));
        } else if (!strcmp(s, "change")) {   // the limit raised to 90 % after the restart
            HoldingThenRestart(0);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @90, 1);
            Expect("Charge Limit set to 90 % after the restart: charging to 90 % at once", B.allowCharge && SimCharging() &&
                   SimPublishedState() == kMSBDChargeStateCharging && MSBDChargeWordLimit(SimWord()) == 90);
            Looks(30);
            Expect("  ... then on hold at 90 %", SimPublishedState() == kMSBDChargeStateOnHold && MSBDChargeWordLimit(SimWord()) == 90 && Soc() >= 89 && Soc() <= 91 &&
                   HoldID(500));
        } else if (!strcmp(s, "adapter")) {   // Run on Power Adapter (no limit) switched off after the restart
            SimM1(); SimSettings(0, 1); gSimPrefs[@MSBD_CHARGE_ADAPTER_KEY] = @YES; B.soc = 55;
            SimStartJob(500);
            Expect("Run on Power Adapter holds the battery at 55 %", HoldID(500) && SimPublishedState() == kMSBDChargeStateOnHold);
            SimPrefsdRestart(0);
            Looks(2);
            SimSettingsWrite(@MSBD_CHARGE_ADAPTER_KEY, @NO, 1);
            Expect("Run on Power Adapter switched off after the restart: nothing held, the battery charges, the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "comedown")) {   // coming down from 95 % (the adapter cut), switched off after the restart
            SimM1(); SimSettings(80, 1); B.soc = 95;
            SimStartJob(500);
            uint32_t cut = CutID(500);
            Expect("plugged in at 95 % with an 80 % limit: coming down (the adapter cut)", cut && SimPublishedState() == kMSBDChargeStateComingDown);
            SimPrefsdRestart(0);
            [gSimPosts removeAllObjects];
            SimMinutes(2);
            Expect("  ... after the restart the cut stays as it was (the same assertion, SpringBoard never told it ends)", CutID(500) == cut && !PostsOf(MSBD_CHARGE_CUT_ENDING));
            SimSettingsWrite(@MSBD_CHARGE_COMEDOWN_KEY, @NO, 1);
            Expect("coming down switched off after the restart: the cut ends, held where it is", !CutID(500) && HoldID(500) && SimPublishedState() == kMSBDChargeStateOnHold &&
                   PostsOf(MSBD_CHARGE_CUT_ENDING) == 1);
        } else if (!strcmp(s, "silent")) {   // a change made with no settings notification (defaults write): seen at the job's next look
            HoldingThenRestart(0);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 0);
            SimMinutes(1);
            Expect("Charge Limit removed with no notification after the restart: let go at the next look, and the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "down")) {   // killall cfprefsd, and none running until the next read
            HoldingThenRestart(1);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("cfprefsd not running for a while after the kill: the limit switched off then is still followed at once", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "later")) {   // a change long after the restart: every look reads the settings anew
            HoldingThenRestart(0);
            int reads = gSimSettingsReads;
            Looks(20);
            Expect("each look after the restart reads the settings by a fresh process", gSimSettingsReads - reads >= 20);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("Charge Limit set to Off 20 minutes after the restart: let go at once, the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "hang")) {   // a fresh process that hangs: killed; the last settings one gave are kept, not the job's old copy
            HoldingThenRestart(0);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @90, 1);
            Expect("Charge Limit set to 90 % after the restart: charging to 90 %", SimCharging() && MSBDChargeWordLimit(SimWord()) == 90);
            double t0 = gSimNow;
            gSimSettingsHangs = 1;
            SimMinutes(1);
            Expect("  ... a fresh process that hangs is ended within 5 s", gSimSettingsKills == 1 && gSimNow - t0 <= 60 + 6);
            Expect("  ... and the last settings read stay (still charging to 90 %, not back on hold at the old 80 %)", SimCharging() &&
                   MSBDChargeWordLimit(SimWord()) == 90 && SimLogHas("the last ones it read are used"));
            SimMinutes(1);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... the next look reads them again; Off then is followed (nothing held, the job ends)", SimLogHas("read by a fresh process again") && SimOursHeld() == 0 &&
                   gSimJobEnded);
        } else if (!strcmp(s, "hangfirst")) {   // the first fresh processes hang: the job's own copy for that look, then the fresh one
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            SimPrefsdRestart(0);
            gSimSettingsHangs = 2;   // (the change's look, then its end check: no fresh answer yet since the restart)
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("the first fresh process hangs: that look goes by the job's own copy (still on hold), and says so", HoldID(500) && SimLogHas("this process's own copy is used"));
            SimMinutes(1);
            Expect("  ... the next look's fresh process answers: Off is followed, the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "gate")) {   // SpringBoard has not said whether the tweak runs: its own switches, read after the restart
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            int t = 0; notify_register_check(MSBD_GATE_STATE, &t); notify_set_state(t, 0);   // (SpringBoard's decision not published)
            SimMinutes(1);
            Expect("SpringBoard's decision not published, no safe mode: on hold at 80 %", HoldID(500) && SimPublishedState() == kMSBDChargeStateOnHold);
            uint32_t hold = HoldID(500);
            SimPrefsdRestart(0);
            SimMinutes(1);
            Expect("  ... after the restart, the switches read by a fresh process (no safe mode): still on hold at 80 % (the same assertion)",
                   HoldID(500) == hold && SimPublishedState() == kMSBDChargeStateOnHold && gSimSettingsReads > 0);
            SimSettingsWrite(@MSBD_SAFE_KEY, @YES, 0);   // (the crash guard's safe mode, written as mobile)
            SimMinutes(1);
            Expect("the safe mode set after the restart: the job lets go (paused while the tweak is off)", SimOursHeld() == 0 && SimPublishedState() == kMSBDChargeStateStopped);
        } else if (!strcmp(s, "unchanged")) {   // no restart: read by the job itself as before, no process started for it
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            SimMinutes(5);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @90, 1);
            Expect("no cfprefsd restart: Charge Limit set to 90 % is followed at once", SimCharging() && MSBDChargeWordLimit(SimWord()) == 90);
            SimMinutes(5);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... and Off: let go, the job ends", SimOursHeld() == 0 && gSimJobEnded);
            Expect("  ... read by the job itself all along: no fresh process started, nothing said about cfprefsd", gSimSettingsReads == 0 && !SimLogHas("cfprefsd"));
        } else if (!strcmp(s, "boot")) {   // cfprefsd not running when the job starts: what its copy belongs to cannot be noted before its first read
            gSimPrefsdDown = 1;
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            Expect("no cfprefsd before the job's first read: on hold at 80 %, the settings read by a fresh process from the start (and it says so)",
                   HoldID(500) && SimPublishedState() == kMSBDChargeStateOnHold && gSimSettingsReads > 0 && SimLogHas("no cfprefsd could be listed before the job's first read (none running)"));
            SimMinutes(5);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... Off is followed: let go, the job ends", SimOursHeld() == 0 && gSimJobEnded);
        } else if (!strcmp(s, "bootrestart")) {   // the review's case: none before the first read, killall before the job's next look at cfprefsd
            gSimPrefsdDown = 1; gSimPrefsdRestartAtList = 2;   // (the code before the fix took the one listed there for the copy's own; the fix makes no such look)
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            Expect("no cfprefsd at the job's start, its first read starts one, killall at the job's next look at cfprefsd: on hold at 80 %",
                   HoldID(500) && SimPublishedState() == kMSBDChargeStateOnHold);
            SimMinutes(3);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... Charge Limit set to Off: let go at once, the job ends (the restart was not taken for the copy's own cfprefsd)", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "nolist")) {   // the process list could not be read before the job's first read, killall at its next look at cfprefsd
            gSimPrefsdListFailAt = 1; gSimPrefsdRestartAtList = 2;
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            Expect("no process list before the job's first read: on hold at 80 %, read by a fresh process from the start (and it says so)",
                   HoldID(500) && gSimSettingsReads > 0 && SimLogHas("no cfprefsd could be listed before the job's first read (no process list)"));
            SimMinutes(3);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... Charge Limit set to Off: let go at once, the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "duringfirst")) {   // killall during the job's first read (listed before it, gone after it)
            gSimPrefsdRestartAtList = 2;
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            Expect("cfprefsd started over during the job's first read: on hold at 80 %, read by a fresh process from then on", HoldID(500) && gSimSettingsReads > 0 &&
                   SimLogHas("cfprefsd started over since the job began"));
            SimMinutes(2);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... Charge Limit set to Off: let go at once, the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "silentfirst")) {   // killall and a change with no notification, both before the job's next look: that look follows it
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            SimMinutes(2);
            SimPrefsdRestart(0);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 0);
            SimMinutes(1);
            Expect("cfprefsd started over and the limit removed (no notification) since the last look: the next look lets go, the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "agent")) {   // the review's case: mobile's own cfprefsd starts after the job (at boot): no restart, nothing started for it
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            uint32_t hold = HoldID(500);
            SimAgentStart();
            Looks(20);
            Expect("mobile's cfprefsd started after the job: on hold at 80 % as before, read by the job itself (no fresh process, nothing said about cfprefsd)",
                   HoldID(500) == hold && !gChargedMeanwhile && gSimSettingsReads == 0 && !SimLogHas("cfprefsd"));
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @90, 1);
            Expect("  ... Charge Limit set to 90 %: followed at once, still no fresh process", SimCharging() && MSBDChargeWordLimit(SimWord()) == 90 && gSimSettingsReads == 0);
            SimPrefsdRestart(0);   // (killall cfprefsd: both start over)
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... then killall cfprefsd and Off: let go at once, the job ends", SimOursHeld() == 0 && gSimJobEnded && SimLogHas("cfprefsd started over since the job began"));
        } else if (!strcmp(s, "agentread")) {   // the job's reads go to mobile's own cfprefsd, which its first read starts; then it alone starts over
            gSimAgentServes = 1;
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            Looks(3);
            Expect("mobile's cfprefsd started by the job's first read: on hold at 80 %, read by the job itself (no restart)", HoldID(500) && gSimAgentPid && gSimSettingsReads == 0);
            SimAgentRestart();
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... it alone starts over, then Off: let go at once, the job ends (it was noted after the read that started it)", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "agentnolist")) {   // as agentread, but no process list after the read that started it
            gSimAgentServes = 1; gSimPrefsdListFailAt = 2;   // (the job's 2nd list: the one after its first read)
            gSimAgentRestartAtList = 3;   // (mobile's own starts over before the job's next look at cfprefsd: the fix makes none)
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(500);
            Expect("no process list after the read that started mobile's cfprefsd: on hold at 80 %, read by a fresh process from then on (and it says so)",
                   HoldID(500) && gSimSettingsReads > 0 && SimLogHas("no process list after a read of the job's"));
            SimMinutes(2);
            SimSettingsWrite(@MSBD_CHARGE_LIMIT_KEY, @(kMSBDChargeLimitOff), 1);
            Expect("  ... Off: let go at once, the job ends", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else { printf("unknown scenario %s\n", s); return 2; }
        return SimDone();
    }
}
