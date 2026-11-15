// test-chargelapse.m -- a hold that works is never given up for one lapse, and a give-up that is remembered for an adapter tries again by itself
// (1.8.7.5, GitHub issue #13: "The 'Run on Power Adapter' sometimes cannot be used. After Resppring, turn off the switch and then turn it back on
// to use it." The reporter's Battery Health footer said "iPad can't pause charging with this power adapter ..." until the off/on).
// What went wrong (1.8.7.4): the check of the hold (MSBDChargeLeverCheck) judged the whole hold, not the charge going in now. Once it had been raised
// again (a slow first take), one later look with charge going in gave it up at once, hours on; and a level 3 % above where the hold went up gave it up
// with no raise-again tried (a lapse while the iPad slept, seen at the wake). The give-up was remembered for the adapter for 7 days and applied at every
// plug-in and job start, the hold never up again, so the only thing that cleared it ("the hold takes with this adapter now") could not happen; only a
// charge setting changed (the off/on) cleared it.
// Now: each stretch of charge going in is checked from its start (raised again first), a take ends it, a gap in the job's looks (the iPad asleep)
// starts the check over; at most 3 raise-agains in a plug-in; only a hold that never took in the plug-in is remembered; and a remembered one is tried
// again when the hold is due -- held where it is (no cut), not kept awake -- and forgotten once it takes. The same for Charge Limit, Run on Power
// Adapter, and every hold kind (one check). tools/chargejob-sim.h runs the job.
// Round 1's review (1.8.7.5): the check must be able to finish with the iPad asleep (every look then comes after a gap, which starts it over: a hold
// that does not take was never given up, and the cut came and went for days) -- the iPad is kept awake while a stretch of charge going in is
// checked; the raise-agains count in 6 hours, not in the whole plug-in (a lapse once a night gave a docked iPad's hold up on the 4th night); and
// a remembered hold is not tried at 95 % and over, where nothing can show it takes (it showed "on hold" at 100 % for the whole plug-in).
// Scenarios (one per run): slowtake-blip, lapse-sleep, lapse-pmu, lapse-soc, lapse-slowretake, lapse-gauge, raised-then-asleep, lapses-bound, replug-remembers,
// limit-blip, remembered-takes, remembered-restart-first then remembered-restart-next (a second process), remembered-below, remembered-fails, remembered-full, status,
// ignored-asleep, retried-asleep, lapse-nightly, remembered-top, remembered-near-top, full-then-drift.
#include "chargejob-sim.h"

#define kAdapterKey @"chargeRunOnAdapter"   // (common/ChargeLimit.h MSBD_CHARGE_ADAPTER_KEY)
static int gCutMin, gAwakeMin;   // minutes with our cut / our stay-awake up
static void Watch(int minutes) {
    for (int i = 0; i < minutes; i++) {
        SimMinutes(1);
        if (SimHeldBy(gSimJobPid, "DisableInflow")) gCutMin++;
        if (SimHeldBy(gSimJobPid, "PreventUserIdleSystemSleep")) gAwakeMin++;
    }
}
static int Soc(void) { return (int)(B.soc + 0.5); }
// Asleep: the job looks only at a wake (one in 10 minutes, a power source change) while it keeps nothing awake, and once a minute while its
// stay-awake is up. Counts the cuts started and the highest level the job called "on hold".
static int gCuts, gMaxOnHold;
static void Asleep(double hours) {
    double t0 = gSimNow; int was = SimHeldBy(gSimJobPid, "DisableInflow");
    while (gSimNow - t0 < hours * 3600) {
        if (SimHeldBy(gSimJobPid, "PreventUserIdleSystemSleep")) Watch(1); else { SimAdvance(600); SimPowerSourceChanged(); }
        int cut = SimHeldBy(gSimJobPid, "DisableInflow");
        if (cut && !was) gCuts++;
        was = cut;
        if (SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) > gMaxOnHold) gMaxOnHold = (int)(B.soc + 0.5);
    }
}
static int LogCount(const char *s) {
    NSString *log = [NSString stringWithContentsOfFile:@kLogFile encoding:NSUTF8StringEncoding error:nil];
    return log ? (int)[log componentsSeparatedByString:@(s)].count - 1 : 0;
}
static NSDictionary *Remembered(void) {   // the state file's remembered give-up (nil: none)
    id r = [NSDictionary dictionaryWithContentsOfFile:@kStateFile][@"holdIgnored"];
    return [r isKindOfClass:[NSDictionary class]] ? r : nil;
}
static double RememberedAt(void) { return [Remembered()[@"at"] doubleValue]; }
static void Unplug(void) { B.cable = 0; SimPowerSourceChanged(); SimMinutes(1); }
static void Plug(void) { B.cable = 1; SimPowerSourceChanged(); }
static BOOL HeldNow(void) { return SimHeldBy(gSimJobPid, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateOnHold && SimAmperage() == 0; }
// The M1 (its charger keeps powerd's hold) with Run on Power Adapter, plugged in at 55 %; holdObeyed 0: the hold does not take (yet)
static void M1Adapter(int holdObeyed) {
    SimM1(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 55; B.holdObeyed = holdObeyed;
    SimStartJob(500);
}
// A first plug-in on which the hold does not take with this adapter: given up and remembered (as 1.8.7.4 did, and still does)
static void GivenUpAndRemembered(void) {
    Watch(8);
    Expect("the hold does not take at the first plug-in: given up, \"can't pause charging\", remembered for the adapter",
           SimPublishedState() == kMSBDChargeStateCantHold && SimLogHas("does not take") && Remembered());
}

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "slowtake-blip")) {   // (a): a slow first take (raised again), held for hours, then one look with charge going in
            M1Adapter(0);
            SimMinutes(2);
            Expect("a slow first take: raised again at 2 minutes", SimLogHas("raised again"));
            B.holdObeyed = 1;
            Watch(180);
            Expect("  ... then held for 3 hours", HeldNow() && Soc() <= 57);
            B.allowCharge = 1; SimMinutes(1); B.allowCharge = 0; Watch(5);   // (one minute when the hold lapsed: charge going in at one look)
            Expect("  ... one look with charge going in, hours after that raise-again: still held, not given up", HeldNow() && !SimLogHas("does not take"));
            Expect("  ... nothing remembered for the adapter", !Remembered());
        } else if (!strcmp(s, "lapse-sleep")) {   // (b): the hold lapses while the iPad sleeps; at the wake the level is 7 % up, charge going in
            M1Adapter(1);
            Watch(120);
            Expect("held at 55 % for 2 hours", HeldNow() && Soc() == 55);
            B.allowCharge = 1; B.chargeMA = 800; SimAdvance(40 * 60);   // (asleep: the job does not look; powerd still lists our hold)
            SimPowerSourceChanged(); Watch(5);
            Expect("woken 7 % up with charge going in: raised again, held again, not given up", Soc() >= 61 && SimLogHas("raised again") && HeldNow() &&
                   !SimLogHas("does not take"));
            Expect("  ... nothing remembered for the adapter", !Remembered());
            Unplug(); Plug();
            Expect("  ... unplugged and plugged in again with the same adapter: held at once", HeldNow());
        } else if (!strcmp(s, "lapse-pmu")) {   // (b) on a PMU iPad (the iPad 2 16.7.7): the hold is Apple's PredictiveChargingInhibit key
            SimIPad2(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 60;
            SimStartJob(500);
            Watch(120);
            Expect("the iPad 2 held at 60 % for 2 hours (the inhibit key)", B.pci && SimPublishedState() == kMSBDChargeStateOnHold && Soc() == 60);
            B.pci = 0; B.chargeMA = 800; SimAdvance(40 * 60);   // (the key cleared while it slept)
            SimPowerSourceChanged(); Watch(5);
            Expect("woken 8 % up with charge going in: the key set again, held, not given up, nothing remembered", Soc() >= 67 && B.pci && SimAmperage() == 0 &&
                   SimPublishedState() == kMSBDChargeStateOnHold && SimLogHas("raised again") && !SimLogHas("does not take") && !Remembered());
        } else if (!strcmp(s, "lapse-soc")) {   // (b) on iPadOS 18 (the A12Z 18.5): the hold is powerd's SOC-limit policy
            SimA12ZSoc(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 60;
            SimStartJob(500);
            Watch(120);
            Expect("the A12Z held at 60 % for 2 hours (iPadOS's own charge limit)", SimSocLive() == 1 && SimPublishedState() == kMSBDChargeStateOnHold && Soc() == 60);
            for (int i = 0; i < gSimSocN; i++) gSimSoc[i].live = 0;   // (powerd lost our policy while it slept)
            B.chargeMA = 800; SimAdvance(40 * 60);
            SimPowerSourceChanged(); Watch(5);
            Expect("woken 6 % up with charge going in: the policy set again, held, not given up, nothing remembered", Soc() >= 65 && SimSocLive() == 1 &&
                   SimAmperage() == 0 && SimPublishedState() == kMSBDChargeStateOnHold && SimLogHas("raised again") && !SimLogHas("does not take") && !Remembered());
        } else if (!strcmp(s, "lapse-slowretake")) {   // (b), and the raise-again itself takes only after a minute
            M1Adapter(1);
            Watch(120);
            B.allowCharge = 1; B.chargeMA = 800; B.holdObeyed = 0; SimAdvance(40 * 60);
            SimPowerSourceChanged(); Watch(3);   // (raised again at 2 minutes; charge still going in a minute later)
            B.holdObeyed = 1; Watch(5);
            Expect("woken 7 % up, the raise-again taking a minute late: held, not given up, nothing remembered", SimLogHas("raised again") && HeldNow() &&
                   !SimLogHas("does not take") && !Remembered());
        } else if (!strcmp(s, "lapse-gauge")) {   // a lapse, and the gauge steps 3 % up meanwhile: the raise-again first, not a give-up
            M1Adapter(1);
            Watch(30);
            B.allowCharge = 1; SimMinutes(1);
            B.soc += 3; Watch(5);
            Expect("a lapse with the gauge 3 % up a minute into it: raised again and held, not given up, nothing remembered", SimLogHas("raised again") &&
                   HeldNow() && !SimLogHas("does not take") && !Remembered());
        } else if (!strcmp(s, "raised-then-asleep")) {   // raised again, then the iPad sleeps (the take not seen), lapses meanwhile, wakes
            M1Adapter(0);
            SimMinutes(2);
            Expect("a slow first take: raised again at 2 minutes", SimLogHas("raised again"));
            B.holdObeyed = 1; SimAdvance(20 * 60);              // (it took; nobody looked)
            B.allowCharge = 1; B.chargeMA = 800; SimAdvance(20 * 60);   // (and lapsed in the sleep)
            SimPowerSourceChanged(); Watch(5);
            Expect("woken with charge going in, 40 minutes after that raise-again: raised again, held, not given up", LogCount("raised again") == 2 &&
                   HeldNow() && !SimLogHas("does not take"));
            Expect("  ... nothing remembered for the adapter", !Remembered());
        } else if (!strcmp(s, "lapses-bound")) {   // the hold takes, then lapses again 3 minutes after each raise-again
            M1Adapter(1);
            Watch(10);
            for (int lapse = 1; lapse <= 4 && SimPublishedState() == kMSBDChargeStateOnHold; lapse++) {
                B.allowCharge = 1;
                for (int i = 0; i < 6 && LogCount("raised again") < lapse && SimPublishedState() == kMSBDChargeStateOnHold; i++) Watch(1);
                Watch(3);
            }
            Expect("raised again 3 times, each taking for a while: the next lapse gives it up for this plug-in", LogCount("raised again") == 3 &&
                   SimPublishedState() == kMSBDChargeStateCantHold && SimLogHas("does not take"));
            Expect("  ... not remembered for the adapter (it took in this plug-in)", !Remembered());
            Unplug(); Plug();
            Expect("  ... unplugged and plugged in again: held at once", HeldNow());
            Watch(5); B.allowCharge = 1; Watch(5);
            Expect("  ... a lapse in that new plug-in: raised again (its own 3), held", LogCount("raised again") == 4 && HeldNow());
        } else if (!strcmp(s, "replug-remembers")) {   // held on one adapter, then plugged in with one where the hold does not take
            M1Adapter(1);
            Watch(10);
            Expect("held on the first adapter (it takes)", HeldNow());
            Unplug(); B.family = (long long)0xFFFFFFFFE0004003ULL; B.desc = "usb brick"; B.holdObeyed = 0; Plug();
            GivenUpAndRemembered();
            Expect("  ... the brick's give-up is remembered for the brick (what the last plug-in saw does not count)", [Remembered()[@"key"] hasSuffix:@"|usb brick"]);
        } else if (!strcmp(s, "limit-blip")) {   // Charge Limit 80 %: the same check (a slow take, then a blip hours on)
            SimM1(); SimSettings(80, 1); B.soc = 79.6; B.holdObeyed = 0;
            SimStartJob(500);
            SimMinutes(2);
            B.holdObeyed = 1; Watch(180);
            B.allowCharge = 1; SimMinutes(1); B.allowCharge = 0; Watch(5);
            Expect("Charge Limit 80 %: a slow first take, then one look with charge going in hours on: held at the limit, not given up, nothing remembered",
                   HeldNow() && Soc() <= 82 && !SimLogHas("does not take") && !Remembered());
        } else if (!strcmp(s, "remembered-takes")) {   // remembered as not taking; the next plug-in with that adapter, where it takes now
            M1Adapter(0);
            GivenUpAndRemembered();
            Unplug(); B.holdObeyed = 1; B.soc = 55; Plug();
            Expect("plugged in again with the remembered adapter: the hold tried again (no skip)", SimHeldBy(500, "ChargeInhibit") &&
                   SimPublishedState() == kMSBDChargeStateOnHold && SimLogHas("it is tried again in this plug-in"));
            Watch(3);
            Expect("  ... it takes: forgotten (\"the hold takes with this adapter now\"), held, nothing left in the state file", HeldNow() &&
                   SimLogHas("the hold takes with this adapter now") && !Remembered());
            Unplug(); Plug();
            Expect("  ... the next plug-in: held at once", HeldNow());
        } else if (!strcmp(s, "remembered-restart-first")) {   // remembered as not taking (the state file kept for the next process) ...
            M1Adapter(0);
            GivenUpAndRemembered();
        } else if (!strcmp(s, "remembered-restart-next")) {   // ... then the job starts again on the cable (an install, a crash): a new process
            gSimNow += 600;
            M1Adapter(1);
            Expect("the job started again on the cable, the give-up remembered: the hold tried again", HeldNow() && Remembered() &&
                   SimLogHas("it is tried again in this plug-in"));
            Watch(3);
            Expect("  ... it takes: forgotten, held", HeldNow() && SimLogHas("the hold takes with this adapter now") && !Remembered());
        } else if (!strcmp(s, "remembered-below")) {   // Charge Limit 80 %, remembered, plugged in at 60 %: charging to the limit, tried there
            SimM1(); SimSettings(80, 1); B.soc = 79.6; B.holdObeyed = 0;
            SimStartJob(500);
            GivenUpAndRemembered();
            Unplug(); B.holdObeyed = 1; B.soc = 60; Plug();
            gAwakeMin = gCutMin = 0;
            Expect("plugged in at 60 % with the remembered adapter: \"charging to 80 %\" (the hold tried at the limit), not \"can't pause\"",
                   SimPublishedState() == kMSBDChargeStateCharging && SimCharging());
            for (int i = 0; i < 90 && !SimHeldBy(500, "ChargeInhibit"); i++) Watch(1);
            Expect("  ... not kept awake on the way (as with the give-up), no cut", gAwakeMin == 0 && gCutMin == 0);
            Watch(3);
            Expect("  ... at 80 % the hold tried: it takes, forgotten, held at the limit", HeldNow() && Soc() >= 80 && Soc() <= 81 && !Remembered() &&
                   SimLogHas("the hold takes with this adapter now"));
        } else if (!strcmp(s, "remembered-fails")) {   // the A12Z on 18.5, Charge Limit 80 %: its charger ignores the hold
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            GivenUpAndRemembered();
            double at1 = RememberedAt();
            Unplug(); B.soc = 70; Plug();
            gAwakeMin = gCutMin = 0;
            Expect("plugged in at 70 % with the remembered adapter: \"charging to 80 %\", not kept awake", SimPublishedState() == kMSBDChargeStateCharging &&
                   !SimHeldBy(500, "PreventUserIdleSystemSleep"));
            for (int i = 0; i < 60 && !SimHeldBy(500, "ChargeInhibit"); i++) Watch(1);
            double up = gSimNow;
            for (int i = 0; i < 6 && SimPublishedState() != kMSBDChargeStateCantHold; i++) Watch(1);
            Expect("  ... at 80 % the hold tried; charge goes in: given up again within 5 minutes, remembered again (a new date)",
                   SimPublishedState() == kMSBDChargeStateCantHold && gSimNow - up <= 300 && RememberedAt() > at1 && SimOursHeld() == 0);
            Watch(30);
            Unplug(); B.soc = 90; Plug();
            double at2 = RememberedAt(), up2 = gSimNow;
            Expect("plugged in at 90 %: the hold tried where the battery is, no cut (coming down is for a hold known to take)",
                   SimHeldBy(500, "ChargeInhibit") && !SimHeldBy(500, "DisableInflow"));
            for (int i = 0; i < 6 && SimPublishedState() != kMSBDChargeStateCantHold; i++) Watch(1);
            Expect("  ... given up again within 5 minutes, remembered again", SimPublishedState() == kMSBDChargeStateCantHold && gSimNow - up2 <= 300 &&
                   RememberedAt() > at2);
            Watch(60);
            Expect("  ... in all this: never cut, kept awake only for the checks (5 minutes at most each)", gCutMin == 0 && gAwakeMin <= 10);
            Unplug(); gSimNow += 8 * 86400; B.soc = 90; Plug();
            Expect("8 days on: as with an adapter never given up (coming down to the limit)", SimHeldBy(500, "DisableInflow") &&
                   SimPublishedState() == kMSBDChargeStateComingDown);
        } else if (!strcmp(s, "remembered-full")) {   // the A12Z, remembered, plugged in full with Run on Power Adapter: nothing goes in anyway
            SimA12Z(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 60;
            SimStartJob(500);
            GivenUpAndRemembered();
            double at1 = RememberedAt();
            Unplug(); B.soc = 100; Plug();
            Watch(10);
            Expect("plugged in full: no charge going in is no sign the hold takes (iPadOS charges nothing then): still remembered",
                   RememberedAt() == at1 && !SimLogHas("the hold takes with this adapter now"));
        } else if (!strcmp(s, "status")) {   // msbdcharge --status says what is remembered for this adapter
            M1Adapter(0);
            GivenUpAndRemembered();
            NSString *out = [NSString stringWithFormat:@"%s.status", kLogFile];
            fflush(stdout); int saved = dup(1), fd = open(out.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644); dup2(fd, 1); close(fd);
            SimCommand(700, "--status");
            fflush(stdout); dup2(saved, 1); close(saved);
            NSString *text = [NSString stringWithContentsOfFile:out encoding:NSUTF8StringEncoding error:nil] ?: @"";
            NSString *key = Remembered()[@"key"];
            printf("%s", text.UTF8String);
            Expect("--status names the remembered give-up, its key, and that it applies to this adapter now",
                   key.length && [text containsString:[NSString stringWithFormat:@"hold remembered as not taking: %@", key]] && [text containsString:@"applies to this adapter"]);
            Unplug(); B.holdObeyed = 1; Plug(); Watch(3);
            fflush(stdout); saved = dup(1); fd = open(out.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644); dup2(fd, 1); close(fd);
            SimCommand(701, "--status");
            fflush(stdout); dup2(saved, 1); close(saved);
            text = [NSString stringWithContentsOfFile:out encoding:NSUTF8StringEncoding error:nil] ?: @"";
            printf("%s", text.UTF8String);
            Expect("  ... once the hold took: \"none\", with this adapter's key", [text containsString:[NSString stringWithFormat:@"hold remembered as not taking: none (this adapter: %@)", key]]);
        } else if (!strcmp(s, "ignored-asleep")) {   // the A12Z (its charger ignores the hold), Charge Limit 80 %, the iPad asleep once the hold is up
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);   // (the hold goes up at this look; then a look in 10 minutes unless the job keeps the iPad awake)
            Asleep(48);
            Expect("a hold that does not take, asleep from when it went up: given up and remembered, \"can't pause\"", SimLogHas("does not take") && Remembered() &&
                   SimPublishedState() == kMSBDChargeStateCantHold);
            Expect("  ... in 48 hours never cut, kept awake 10 minutes at most (the check's)", gCuts == 0 && gCutMin == 0 && gAwakeMin <= 10);
        } else if (!strcmp(s, "retried-asleep")) {   // remembered on the A12Z; plugged in again at 60 %, asleep: the trial's check finishes too
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            GivenUpAndRemembered();
            double at1 = RememberedAt();
            Unplug(); B.soc = 60; Plug();
            gAwakeMin = gCutMin = 0;
            Asleep(24);
            Expect("plugged in again at 60 %, asleep: the hold tried at the limit and given up again (a new date), \"can't pause\"", RememberedAt() > at1 &&
                   SimPublishedState() == kMSBDChargeStateCantHold);
            Expect("  ... never cut, kept awake only for the check, never \"on hold\" at 90 % or more", gCuts == 0 && gCutMin == 0 && gAwakeMin <= 10 && gMaxOnHold < 90);
        } else if (!strcmp(s, "lapse-nightly")) {   // Run on Power Adapter on an iPad left on the cable: held for days, the hold lapsing once a night in sleep
            M1Adapter(1);
            for (int night = 1; night <= 5; night++) {
                Watch(600);   // (10 hours held)
                B.allowCharge = 1; B.chargeMA = 800; SimAdvance(20 * 60);   // (it lapsed while the iPad slept)
                SimPowerSourceChanged(); Watch(6);
            }
            Expect("a lapse a night for 5 nights, each raised again: still held, never given up", HeldNow() && LogCount("raised again") == 5 && !SimLogHas("does not take"));
        } else if (!strcmp(s, "remembered-top")) {   // Charge Limit 80 %, remembered; plugged in again full (a docked iPad) where the hold takes now
            SimM1(); SimSettings(80, 1); B.soc = 79.6; B.holdObeyed = 0;
            SimStartJob(500);
            GivenUpAndRemembered();
            double at1 = RememberedAt();
            Unplug(); B.holdObeyed = 1; B.soc = 100; Plug();
            Watch(30);
            Expect("plugged in again at 100 %: not tried up there (no charge goes in with or without it), \"can't pause\" as remembered, not \"on hold\"",
                   !SimHeldBy(500, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateCantHold && RememberedAt() == at1);
            B.soc = 93.6; B.chargeMA = 300; Watch(4);   // (iPadOS lets a full battery drift down to where it tops it up, slowly)
            Expect("  ... at 94 %: tried, it takes: forgotten", SimLogHas("the hold takes with this adapter now") && !Remembered());
            B.loadMA = 1000;
            for (int i = 0; i < 300 && !(HeldNow() && Soc() <= 80); i++) Watch(1);
            Expect("  ... then down to the limit as always, and held there", HeldNow() && Soc() >= 79 && Soc() <= 80 && SimLogHas("adapter when the cut goes up"));
        } else if (!strcmp(s, "remembered-near-top")) {   // the A12Z, remembered; plugged in again at 94 %: the trial's check finishes past 95 %
            SimA12Z(); SimSettings(80, 1); B.soc = 79.6;
            SimStartJob(500);
            GivenUpAndRemembered();
            double at1 = RememberedAt();
            Unplug(); B.soc = 94; Plug();
            Expect("plugged in again at 94 %: tried, held where it is", SimHeldBy(500, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateOnHold);
            for (int i = 0; i < 6 && SimPublishedState() != kMSBDChargeStateCantHold; i++) Watch(1);
            Expect("  ... charge goes in, the level at 95 % and over meanwhile: given up again within 5 minutes all the same, remembered again",
                   SimPublishedState() == kMSBDChargeStateCantHold && RememberedAt() > at1 && Soc() >= 95);
        } else if (!strcmp(s, "full-then-drift")) {   // the A12Z with Run on Power Adapter, plugged in full: held, nothing going in (full), then charge in
            SimA12Z(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 100;
            SimStartJob(500);
            Watch(10);
            Expect("plugged in full: held full, nothing going in", SimHeldBy(500, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateOnHold && !SimLogHas("does not take"));
            B.soc = 95; Watch(6);   // (the level down to iPadOS's top-up, and charge going in under the hold)
            Expect("  ... charge going in at 95 %: given up, and remembered (a full battery taking nothing was no sign that the hold takes)",
                   SimLogHas("does not take") && Remembered() && SimLogHas("remembered for this adapter"));
        } else { printf("unknown scenario %s\n", s); return 2; }
    }
    return SimDone();
}
