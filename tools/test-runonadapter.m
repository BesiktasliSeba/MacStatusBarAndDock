// test-runonadapter.m -- Run on Power Adapter (KT, 6 Nov: "run fully on the charger, without relying on the battery"; plans/battery-charging.md):
// while plugged in, the battery is held where it was when the cable went in -- the adapter powers iPad -- with the Charge Limit's own hold and
// checks, never above the limit when one is set, never under 20 %, off unless switched on (tools/chargejob-sim.h runs the job).
// Scenarios (one per run): hold55, load, limit, low, replug, a12z, off, switchon, monthly, pmu.
#include "chargejob-sim.h"

#define kAdapterKey @"chargeRunOnAdapter"   // (common/ChargeLimit.h MSBD_CHARGE_ADAPTER_KEY)
static int gAwakeOnHold, gMinSoc = 101, gMaxSoc;
static void Watch(int minutes) {
    for (int i = 0; i < minutes; i++) {
        SimMinutes(1);
        int soc = (int)(B.soc + 0.5);
        if (soc < gMinSoc) gMinSoc = soc;
        if (soc > gMaxSoc) gMaxSoc = soc;
        if (SimPublishedState() == kMSBDChargeStateOnHold && SimHeldBy(gSimJobPid, "PreventUserIdleSystemSleep")) gAwakeOnHold++;
    }
}
static void RunOnAdapter(BOOL on) { gSimPrefs[kAdapterKey] = @(on); notify_post(MSBD_CHARGE_PREFS_CHANGED); }

int main(int argc, char **argv) {
    const char *s = argc > 1 ? argv[1] : "";
    @autoreleasepool {
        if (!strcmp(s, "hold55")) {   // the M1 plugged in at 55 %, no Charge Limit
            SimM1(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 55;
            SimStartJob(500);
            Watch(180);
            Expect("plugged in at 55 %: held there for 3 hours (powerd's ChargeInhibit), the adapter powering iPad", SimHeldBy(500, "ChargeInhibit") &&
                   SimPublishedState() == kMSBDChargeStateOnHold && gMinSoc == 55 && gMaxSoc == 55 && SimAmperage() == 0);
            Expect("  ... the state word's level is 55 (\"Charging On Hold at 55%\" in the menu)", MSBDChargeWordLimit(SimWord()) == 55);
            Expect("  ... not kept awake while on hold, no cut", gAwakeOnHold == 0 && !SimHeldBy(500, "DisableInflow"));
        } else if (!strcmp(s, "load")) {   // more load than the adapter carries: the battery helps out, charged back at 5 % under the level
            SimM1(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 55;
            SimStartJob(500);
            Watch(5);
            gSimShortMA = 900;   // (under the hold the battery gives what the adapter cannot)
            for (int i = 0; i < 400 && SimPublishedState() != kMSBDChargeStateCharging; i++) Watch(1);
            Expect("drawn down under the hold by a load the adapter cannot carry: charging again at 50 % (5 % under), the hold not given up",
                   SimPublishedState() == kMSBDChargeStateCharging && gMinSoc >= 49 && !SimLogHas("does not take"));
            gSimShortMA = 0;
            Watch(30);
            Expect("  ... charged back to 55 % and held there again", SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) >= 55 && (int)(B.soc + 0.5) <= 56);
        } else if (!strcmp(s, "limit")) {   // with an 80 % Charge Limit, plugged in at 95 %: the limit's coming down first, then held at 80
            SimM1(); SimSettings(80, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 95; B.loadMA = 1500;
            SimStartJob(500);
            Expect("above the Charge Limit: coming down to it (the limit's own rule)", SimHeldBy(500, "DisableInflow"));
            Watch(120);
            Expect("  ... then held at 80 %, not at the 95 % it was plugged in at", SimHeldBy(500, "ChargeInhibit") && SimPublishedState() == kMSBDChargeStateOnHold &&
                   (int)(B.soc + 0.5) == 80);
        } else if (!strcmp(s, "low")) {   // plugged in at 12 %: never held that low
            SimM1(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 12;
            SimStartJob(500);
            Expect("at 12 %: charging (never held under 20 %)", SimPublishedState() == kMSBDChargeStateCharging && SimCharging());
            Watch(60);
            Expect("  ... held at 20 %", SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) >= 20 && (int)(B.soc + 0.5) <= 21);
        } else if (!strcmp(s, "replug")) {   // each plug-in holds its own level
            SimM1(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 55;
            SimStartJob(500);
            Watch(10);
            B.cable = 0; SimPowerSourceChanged(); B.loadMA = 1500; Watch(60);
            Expect("unplugged: nothing held", SimOursHeld() == 0 && SimPublishedState() == kMSBDChargeStateOff);
            int at = (int)(B.soc + 0.5);
            B.cable = 1; B.loadMA = 150; SimPowerSourceChanged(); Watch(30);
            Expect("plugged in again lower: held at the new level", SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) == at && at < 55);
        } else if (!strcmp(s, "a12z")) {   // the A12Z, whose charger does not keep the hold on 18.5: given up, iPadOS's own charging
            SimA12Z(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 60;
            SimStartJob(500);
            Watch(30);
            Expect("on the A12Z the hold lets charge in: given up (\"can't pause charging\"), nothing held, no cut", SimPublishedState() == 7 && SimOursHeld() == 0);
        } else if (!strcmp(s, "off")) {   // off unless switched on: no Charge Limit, no Run on Power Adapter, nothing held
            SimM1(); SimSettings(0, 1); B.soc = 55;
            SimStartJob(500);
            Watch(30);
            Expect("Run on Power Adapter not set: iPadOS's own charging, nothing held", SimOursHeld() == 0 && SimCharging() && SimPublishedState() == kMSBDChargeStateOff);
        } else if (!strcmp(s, "switchon")) {   // switched on while charging at 70 %: held where it is then
            SimM1(); SimSettings(0, 1); B.soc = 70;
            SimStartJob(500);
            Watch(2);
            Expect("nothing set at the start: the job ended at once, nothing held", SimOursHeld() == 0 && SimPublishedState() == 0);
            RunOnAdapter(YES);
            SimStartJob(501);   // (the root helper starts the job when the setting is made: sshtoggled ChargeJobKick)
            int at = (int)(B.soc + 0.5);
            Watch(30);
            Expect("switched on while charging: held at the level it had then", SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) == at);
            RunOnAdapter(NO);
            Watch(5);
            Expect("  ... switched off: nothing held, charging, and the job ended by itself", SimOursHeld() == 0 && SimCharging() && gSimJobEnded);
        } else if (!strcmp(s, "monthly")) {   // an 80 % Charge Limit, plugged in at 60 % for a month: the monthly full charge, then back down to the limit
            SimM1(); SimSettings(80, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 60; B.loadMA = 1500;
            SimStartJob(500);
            Watch(10);
            Expect("held at 60 % (where it was plugged in, under the 80 % limit)", SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) == 60);
            gSimNow += 31 * 86400;   // (a month on the adapter, held: the battery as it was)
            Watch(1);
            Expect("a month later: the monthly full charge, and the state word says it comes back to 80 % (Settings: \"then back to 80%\")",
                   SimPublishedState() == kMSBDChargeStateMonthlyFull && MSBDChargeWordLimit(SimWord()) == 80);
            gMaxSoc = 0; Watch(300);
            Expect("  ... charged to 100 %, then down to the 80 % limit and held there (the footer's \"up to 80%\")", gMaxSoc == 100 &&
                   SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) >= 79 && (int)(B.soc + 0.5) <= 80 && MSBDChargeWordLimit(SimWord()) == 80);
        } else if (!strcmp(s, "pmu")) {   // the iPad 2: its hold is the inhibit key, which the prerm's --stop clears
            SimIPad2(); SimSettings(0, 1); gSimPrefs[kAdapterKey] = @YES; B.soc = 60;
            SimStartJob(500);
            Watch(60);
            Expect("the iPad 2 held at 60 % with PredictiveChargingInhibit", B.pci && SimPublishedState() == kMSBDChargeStateOnHold && (int)(B.soc + 0.5) == 60);
            SimCommand(601, "--stop"); SimKill(500); SimCommand(602, "--reset");
            Expect("  ... the package stops the job: the key cleared, charging", !B.pci && SimCharging());
        } else { printf("unknown scenario %s\n", s); return 2; }
    }
    return SimDone();
}
