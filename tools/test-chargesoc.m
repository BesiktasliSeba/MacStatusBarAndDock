// test-chargesoc.m -- the Charge Limit's hold on iPadOS 18 (1.8.6): where powerd offers its own SOC-limit service (the SMC iPads whose SMC has
// CHLS: the A12Z on 18.5, whose battery driver ignores powerd's ChargeInhibit) the hold is a policy there; elsewhere the hold is as before.
// A policy outlives the job that set it, so its token is kept in the state file and every start and --reset removes the ones kept.
// A token stays kept until its policy is removed or powerd lists none of ours it could be: one powerd did not take is tried again, and the job does
// not end before (a cap left in place would keep charging stopped at its level with the job gone).
// tools/chargejob-sim.h runs the job. Scenarios (one per run): hold, blip, adapter, off, crash, stop, reset, powerd, powerdlost, powerdslow, retry,
// resetslow, stale, startkept, resetrun, resetrunpmu, m1.
#include "chargejob-sim.h"

static NSArray *KeptTokens(void) {
    NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:@kStateFile];
    return [st[@"socTokens"] isKindOfClass:[NSArray class]] ? st[@"socTokens"] : @[];
}

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "hold")) {   // the A12Z at 80 % with an 80 % limit
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            Expect("the A12Z: the hold is iPadOS's own charge limit (said at start)", SimLogHas("the hold is iPadOS's own charge limit"));
            Expect("  ... one policy of ours, at 80 %, its token kept in the state file", SimSocLive() == 1 && SimSocLevel() == 80 && KeptTokens().count == 1);
            Expect("  ... no ChargeInhibit raised, the battery does not charge, published on hold", SimOursHeld() == 0 && !SimCharging() &&
                   SimPublishedState() == kMSBDChargeStateOnHold);
            SimMinutes(30);
            Expect("  ... 30 minutes later: still held at 80 %, the same single policy, not given up", SimSocLive() == 1 && (int)(B.soc + 0.5) == 80 &&
                   SimPublishedState() == kMSBDChargeStateOnHold && !SimLogHas("does not take") && gSimSocSeq == 1);
        } else if (!strcmp(s, "adapter")) {   // Run on Power Adapter at 55 %, then switched off
            SimA12ZSoc(); SimSettings(0, 1); gSimPrefs[@MSBD_CHARGE_ADAPTER_KEY] = @YES; B.soc = 55;
            SimStartJob(700);
            SimMinutes(5);
            Expect("Run on Power Adapter: a policy at the plug-in level (55 %), not charging", SimSocLive() == 1 && SimSocLevel() == 55 && !SimCharging());
            [gSimPrefs removeObjectForKey:@MSBD_CHARGE_ADAPTER_KEY]; notify_post(MSBD_CHARGE_PREFS_CHANGED);
            Expect("  ... switched off: the policy removed, the token dropped, charging again, the job ended", SimSocLive() == 0 && KeptTokens().count == 0 &&
                   SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "off")) {   // on hold, then the Charge Limit switched off
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimSettings(0, 1); notify_post(MSBD_CHARGE_PREFS_CHANGED);
            int ours = -1; SocQueryOurs(&ours);
            Expect("the Charge Limit off: no policy of ours left (powerd's query), charging, the job ended", ours == 0 && SimSocLive() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "crash")) {   // the job killed (kill -9) while its policy is up; launchd starts it again
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimKill(700);
            Expect("killed: its policy outlives it (as powerd keeps it), the token still kept", SimSocLive() == 1 && KeptTokens().count == 1 && !SimCharging());
            SimStartJob(701);
            Expect("  ... the restart removed the earlier run's policy and set its own: one policy, a new token, at 80 %", SimSocLive() == 1 && gSimSocSeq == 2 &&
                   SimSocLevel() == 80 && KeptTokens().count == 1 && [KeptTokens()[0] isEqual:@"TOKEN-2"]);
            Expect("  ... and said so", SimLogHas("iPadOS's charge limit of an earlier run: 1 of 1 removed"));
        } else if (!strcmp(s, "stop")) {   // the package's prerm: --stop, the unload, --reset
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimCommand(710, "--stop");
            Expect("msbdcharge --stop: the policy removed at once, its token dropped", SimSocLive() == 0 && KeptTokens().count == 0 && SimCharging());
            SimKill(700);
            SimCommand(711, "--reset");
            int ours = -1; SocQueryOurs(&ours);
            Expect("  ... after the unload and --reset: none of ours with powerd, charging", ours == 0 && SimCharging());
        } else if (!strcmp(s, "reset")) {   // the job gone without letting go (the unload with no SIGTERM it sees, then the prerm's --reset)
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimKill(700);
            SimCommand(711, "--reset");
            Expect("msbdcharge --reset: the kept policy removed, the state file holds no token, charging", SimSocLive() == 0 && KeptTokens().count == 0 && SimCharging());
        } else if (!strcmp(s, "powerd")) {   // powerd started over (the Sleep Guard) while on hold: its policies archived, ours still there
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimPowerdRestart(); notify_post(MSBD_SG_POWERD);
            Expect("powerd started over: our policy set again on its own token, no second one, the token kept, not charging",
                   SimSocLive() == 1 && SimSocLevel() == 80 && gSimSocSeq == 1 && [KeptTokens() isEqual:@[ @"TOKEN-1" ]] && !SimCharging());
        } else if (!strcmp(s, "powerdlost")) {   // ... a powerd that lost its policies at the restart
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80; gSimSocLostAtRestart = 1;
            SimStartJob(700);
            SimPowerdRestart(); notify_post(MSBD_SG_POWERD);
            Expect("powerd started over without our policy: a new one at 80 %, not charging", SimSocLive() == 1 && SimSocLevel() == 80 && gSimSocSeq == 2 && !SimCharging());
            SimMinutes(1);
            Expect("  ... the old token dropped at the next look (powerd lists no policy of ours but the new one)", [KeptTokens() isEqual:@[ @"TOKEN-2" ]]);
        } else if (!strcmp(s, "powerdslow")) {   // the Sleep Guard tells the job right after its kickstart; the new powerd answers 5 s later
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80; gSimPowerdSlow = 5;
            SimStartJob(700);
            SimPowerdRestart(); notify_post(MSBD_SG_POWERD);
            SimMinutes(5);
            Expect("powerd started over and answering 5 s later: the same single policy at 80 %, no second one, not charging",
                   SimSocLive() == 1 && SimSocLevel() == 80 && gSimSocSeq == 1 && [KeptTokens() isEqual:@[ @"TOKEN-1" ]] && !SimCharging());
            SimSettings(0, 1); notify_post(MSBD_CHARGE_PREFS_CHANGED);
            int ours = -1; SocQueryOurs(&ours);
            Expect("  ... the Charge Limit off: no policy of ours left, charging, the job ended", ours == 0 && SimSocLive() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "retry")) {   // the Charge Limit off while powerd does not answer for 30 s: the removal not taken
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            gSimPowerdUpAt = gSimNow + 30;
            SimSettings(0, 1); notify_post(MSBD_CHARGE_PREFS_CHANGED);
            Expect("the removal not taken: the token kept, the job still running (not ended with the cap in place)", SimSocLive() == 1 && [KeptTokens() isEqual:@[ @"TOKEN-1" ]] &&
                   !gSimJobEnded && SimLogHas("not removed yet"));
            SimMinutes(1);
            Expect("  ... a minute later: removed, the token dropped, charging, and only then the job ended", SimSocLive() == 0 && KeptTokens().count == 0 && SimCharging() &&
                   gSimJobEnded);
        } else if (!strcmp(s, "resetslow")) {   // the prerm's --reset right after a powerd restart that answers 4 s later
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimKill(700);
            gSimPowerdSlow = 4; SimPowerdRestart();
            SimCommand(711, "--reset");
            Expect("--reset: the kept policy removed once powerd answers, the token dropped, charging", SimSocLive() == 0 && KeptTokens().count == 0 && SimCharging() &&
                   SimLogHas("1 of 1 removed"));
        } else if (!strcmp(s, "stale")) {   // a token kept from before a restart of the iPad (its policy gone with that boot session)
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimKill(700); SimSocReboot();
            SimSettings(0, 1);
            SimStartJob(701);
            Expect("the start: the token dropped (powerd lists no policy of ours), nothing kept", KeptTokens().count == 0 && SimLogHas("0 of 1 removed, 1 dropped"));
        } else if (!strcmp(s, "startkept")) {   // nothing set, and the start cannot remove an earlier run's policy yet (powerd not answering for 30 s)
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimKill(700);
            SimSettings(0, 1); gSimPowerdUpAt = gSimNow + 30;
            SimStartJob(701);
            Expect("nothing set but a kept policy not removed: the job runs on (it does not end with the cap in place)", SimSocLive() == 1 && !gSimJobEnded &&
                   KeptTokens().count == 1);
            SimMinutes(1);
            Expect("  ... a minute later: removed, charging, the job ended", SimSocLive() == 0 && KeptTokens().count == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "blip")) {   // Run on Power Adapter at 55 %: the cable read as out for a moment (18.5), then a real unplug
            SimA12ZSoc(); SimSettings(0, 1); gSimPrefs[@MSBD_CHARGE_ADAPTER_KEY] = @YES; B.soc = 55;
            SimStartJob(700);
            B.cable = 0; SimPowerSourceChanged(); SimAdvance(3); B.cable = 1; B.soc = 56; SimPowerSourceChanged();
            Expect("the cable read as out for 3 s: the same policy kept at 55 % (not a new plug-in at 56 %)", SimSocLive() == 1 && SimSocLevel() == 55 && gSimSocSeq == 1);
            B.cable = 0; SimPowerSourceChanged(); SimMinutes(1);
            Expect("  ... really unplugged: the policy removed after 15 s", SimSocLive() == 0 && KeptTokens().count == 0);
        } else if (!strcmp(s, "resetrun")) {   // msbdcharge --reset run by hand while the job holds on the A12Z
            SimA12ZSoc(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            SimCommand(711, "--reset");
            Expect("--reset by hand while the job runs: the job's policy kept (the same one, at 80 %), its token kept, not charging, still published on hold",
                   SimSocLive() == 1 && SimSocLevel() == 80 && gSimSocSeq == 1 && [KeptTokens() isEqual:@[ @"TOKEN-1" ]] && !SimCharging() &&
                   SimPublishedState() == kMSBDChargeStateOnHold && SimLogHas("a job is running: its own hold left to it"));
            SimMinutes(10);
            Expect("  ... 10 minutes later: still held at 80 %, not given up", SimSocLive() == 1 && (int)(B.soc + 0.5) == 80 && !SimLogHas("does not take"));
        } else if (!strcmp(s, "resetrunpmu")) {   // ... on the iPad 2 (PMU: the hold is PredictiveChargingInhibit, which --reset clears when no job runs)
            SimIPad2(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            Expect("the iPad 2 on hold at 80 %: PredictiveChargingInhibit set", B.pci && !SimCharging());
            SimCommand(711, "--reset");
            Expect("--reset by hand while the job runs: the job's key kept, not charging, still published on hold", B.pci && !SimCharging() &&
                   SimPublishedState() == kMSBDChargeStateOnHold);
            SimKill(700);
            SimCommand(712, "--reset");
            Expect("  ... the job gone: --reset clears the key, charging", !B.pci && SimCharging());
        } else if (!strcmp(s, "m1")) {   // the M1 (no CHLS): the hold as before, no policy
            SimM1(); SimSettings(80, 1); B.soc = 80;
            SimStartJob(700);
            Expect("the M1: the hold is powerd's ChargeInhibit, no policy created", SimHeldBy(700, "ChargeInhibit") && gSimSocN == 0 &&
                   SimLogHas("the hold is powerd's ChargeInhibit"));
        } else { printf("unknown scenario %s\n", s); return 2; }
    }
    return SimDone();
}
