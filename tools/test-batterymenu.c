// test-batterymenu.c: the battery menu's and the Control Center icon's plain C (common/BatteryMenu.h): the switch as stored, the bar's right end
// (the Control Center icon left of the clock, the Spotlight icon left of it, their touch areas meeting halfway; without the icon the Spotlight
// icon exactly where 1.7.8 put it), the battery's touch area, and -- where the Charge Limit's job is part of the build -- the menu's job line
// and the Charge Limit row's value from the job's state word. Numbers from the iPad 2 (16.7.7, landscape, Small, 2 Nov).
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "../common/BatteryMenu.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static int near(double a, double b) { return fabs(a - b) < 0.001; }
// 1.8.8.1 BATTWHY: KT's A12Z (18.5, AppleSmartBattery) on its 7 W adapter while tests ran, 15 Nov -- 45 %, cable 1, connected 1, charging 0,
// reasons 0x0 / 0x0 (the job's --status) -- with the battery giving 800 mA (the test's current) and 3 minutes not charging, all of them at that current.
static MSBDBattWhyIn KT(void) {
    MSBDBattWhyIn in = { .onAdapter = 1, .charging = 0, .ampKnown = 1, .amp = -800, .full = 0, .soc = 45, .ext = 1, .raw = 1, .watts = 7, .ncrKnown = 1, .ncr = 0,
                         .inhibit = 0, .tempKnown = 1, .tempCC = 2510, .pmu = 0, .obc = 0, .ourHold = 0, .notChargingFor = 180, .drainingFor = 180 };
    return in;
}
static char gL[96];
static const char *WhyLine(MSBDBattWhyIn in) { return MSBDBattWhyLine(MSBDBattWhyDecide(in), in.watts, gL, sizeof gL) ? gL : ""; }
int main(void) {
    // ---- the switch: MSBDBattMenuOn(stored as a boolean, its value)
    check("Battery Menu never set (a new install, an update): on", MSBDBattMenuOn(0, 0) == 1);
    check("  ... switched off: off; switched on: on", MSBDBattMenuOn(1, 0) == 0 && MSBDBattMenuOn(1, 1) == 1);

    // ---- the right end: MSBDBattRightSideLayout(clockEdge, cc, ccW, spot, spotW, gap, slop) -- the iPad 2's bar: the clock from 897.5, both
    // glyphs 16 pt wide, gap 12, slop 10 (Small)
    MSBDBattRightSide r = MSBDBattRightSideLayout(897.5, 0, 16, 1, 16, 12, 10);
    check("no Control Center icon: the Spotlight icon 12 pt before the clock, its touch area 10 pt past it each side (1.7.8's place)",
          near(r.spotLead, 869.5) && near(r.spotBtnLead, 859.5) && near(r.spotBtnTrail, 895.5) && near(r.iconsEnd, 869.5));
    r = MSBDBattRightSideLayout(897.5, 1, 16, 1, 16, 12, 10);
    check("with it (seen on the iPad 2): the icon 12 pt before the clock (869.5), Spotlight 12 pt before that (841.5), the status icons end there",
          near(r.ccLead, 869.5) && near(r.spotLead, 841.5) && near(r.iconsEnd, 841.5));
    check("  ... the two touch areas meet halfway between the glyphs (863.5): Spotlight 831.5-863.5, Control Center 863.5-895.5",
          near(r.spotBtnLead, 831.5) && near(r.spotBtnTrail, 863.5) && near(r.ccBtnLead, 863.5) && near(r.ccBtnTrail, 895.5));
    r = MSBDBattRightSideLayout(897.5, 1, 16, 0, 16, 12, 10);
    check("the icon without Spotlight (Show Spotlight Search off): 12 pt before the clock, its whole slop, the status icons end at it",
          near(r.ccLead, 869.5) && near(r.ccBtnLead, 859.5) && near(r.ccBtnTrail, 895.5) && near(r.iconsEnd, 869.5));
    r = MSBDBattRightSideLayout(897.5, 0, 16, 0, 16, 12, 10);
    check("neither: the status icons end at the clock", near(r.iconsEnd, 897.5));
    r = MSBDBattRightSideLayout(1000, 1, 20, 1, 20, 15, 12.5);
    check("Large (gaps and slop x 1.25, larger glyphs): icon 965, Spotlight 930, touch areas meeting at 957.5",
          near(r.ccLead, 965) && near(r.spotLead, 930) && near(r.spotBtnTrail, 957.5) && near(r.ccBtnLead, 957.5) && near(r.iconsEnd, 930));
    int apart = 1;
    for (double gap = 0; gap <= 30; gap += 1.5) for (double slop = 0; slop <= 20; slop += 2.5) {
        MSBDBattRightSide q = MSBDBattRightSideLayout(900, 1, 18, 1, 15, gap, slop);
        if (q.spotBtnTrail > q.ccBtnLead + 1e-9 || q.ccBtnLead < q.spotLead + 15 - 1e-9 || q.spotBtnTrail > q.ccLead + 1e-9) apart = 0;
    }
    check("  ... whatever the gap and slop: the touch areas never overlap, and neither reaches over the other glyph", apart);

    // ---- the battery's touch area: MSBDBattButtonSpan(lead, trail, pad, floor) -- the iPad 2: "82%" 772-799, the battery 801-827.5, the status
    // icons from 739.5 (our Wi-Fi icon's touch area ends 2 pt before them)
    double a = 0, b = 0;
    check("the percentage and the glyph, 4 pt past each side: 768-831.5 (seen on the iPad 2)",
          MSBDBattButtonSpan(772, 827.5, 4, 737.5, &a, &b) && near(a, 768) && near(b, 831.5));
    check("the battery first of the status icons: not into our Wi-Fi icon's touch area (from 737.5)",
          MSBDBattButtonSpan(739.5, 790, 4, 737.5, &a, &b) && near(a, 737.5) && near(b, 794));
    check("no battery views (lead past trail): no touch area", !MSBDBattButtonSpan(1, 0, 4, 0, &a, &b));
    check("  ... nothing left after the floor: none", !MSBDBattButtonSpan(700, 701, 0, 702, &a, &b));

    // ---- why iPad is not charging on the adapter (1.8.8.1 BATTWHY, common/ChargeWhy.h MSBDBattWhyDecide: the menu's and the job's one rule)
    MSBDBattWhyIn in = KT();
    #define WHY(x) MSBDBattWhyDecide(x)
    check("KT's case (A12Z, 7 W, 45 %, reasons 0x0 / 0x0, -800 mA), 3 minutes not charging: \"Not Charging: Power Adapter Too Weak (7 W)\"",
          WHY(in) == kMSBDWhyTooWeak && !strcmp(WhyLine(in), "Not Charging: Power Adapter Too Weak (7 W)"));
    in.notChargingFor = 179;
    check("  ... at 179 s: nothing yet (the charger starting, the battery's own 120 s wait after a hold or a cut)", WHY(in) == kMSBDWhyNone && !*WhyLine(in));
    in = KT(); in.notChargingFor = -1;
    check("  ... how long not known (a respring, before the first power note): nothing", WHY(in) == kMSBDWhyNone);
    in = KT(); in.amp = 0;
    check("KT's case at 0 mA (the adapter just covers iPad, or a hold no bit shows): plain \"Not Charging\", no reason guessed", WHY(in) == kMSBDWhyNotCharging && !strcmp(WhyLine(in), "Not Charging"));
    in = KT(); in.amp = -100; int edge = WHY(in) == kMSBDWhyTooWeak; in.amp = -99;
    check("  ... the -100 mA edge: at -100 too weak, at -99 \"Not Charging\"", edge && WHY(in) == kMSBDWhyNotCharging);
    in = KT(); in.soc = 94; edge = WHY(in) == kMSBDWhyTooWeak; in.soc = 95;
    check("  ... the 95 % edge: at 94 too weak, at 95 \"Not Charging\" (iPadOS itself stops near full)", edge && WHY(in) == kMSBDWhyNotCharging);
    in = KT(); in.watts = 0;
    check("  ... no watts read: \"Not Charging: Power Adapter Too Weak\"", !strcmp(WhyLine(in), "Not Charging: Power Adapter Too Weak"));
    in = KT(); in.amp = -1500; in.notChargingFor = 40;
    check("a short dip (40 s at -1500 mA): nothing", WHY(in) == kMSBDWhyNone);
    // (1.8.8.1 review) Amperage is the current of the moment (InstantAmperage's value on all four iPads): too weak only once it has lasted 3 minutes
    in = KT(); in.amp = -1500; in.drainingFor = 0; edge = WHY(in) == kMSBDWhyNotCharging; in.drainingFor = -1; edge = edge && WHY(in) == kMSBDWhyNotCharging;
    check("a load spike after 3 minutes not charging for a cause no bit shows (one reading at -1500 mA): \"Not Charging\", not too weak", edge);
    in = KT(); in.drainingFor = 179; edge = WHY(in) == kMSBDWhyNotCharging; in.drainingFor = 180;
    check("  ... the battery giving 100 mA or more for 179 s: \"Not Charging\"; for 180 s: too weak", edge && WHY(in) == kMSBDWhyTooWeak);
    in = KT(); in.charging = 1;
    check("charging (IsCharging 1): nothing; charge going in with IsCharging 0 (over 100 mA): nothing", WHY(in) == kMSBDWhyNone && (in = KT(), in.amp = 500, WHY(in) == kMSBDWhyNone));
    in = KT(); in.onAdapter = 0;
    check("off the adapter (unplugged, or the job's cut: SpringBoard's -isOnAC is NO): nothing", WHY(in) == kMSBDWhyNone);
    in = KT(); in.charging = -1;
    check("not known to be not charging (IsCharging missing): nothing", WHY(in) == kMSBDWhyNone);
    in = KT(); in.ourHold = 1; in.ncr = MSBD_NCR_INHIBIT; edge = WHY(in) == kMSBDWhyNone; in.ncr = MSBD_NCR_IPADOS; in.amp = 0;
    check("the job's own hold or cut (its word: on hold, coming down), whatever the bits (0x4000; iPadOS's limit, our policy on the A12Z): nothing, its own line", edge && WHY(in) == kMSBDWhyNone);
    in = KT(); in.full = 1; in.soc = 100; in.amp = 0; in.notChargingFor = 0;
    check("full (FullyCharged 1 at 100 %): \"Fully Charged\" at once", WHY(in) == kMSBDWhyFull && !strcmp(WhyLine(in), "Fully Charged"));
    in.full = -1; edge = WHY(in) == kMSBDWhyFull; in.full = 1; in.soc = 80; in.notChargingFor = 180;
    check("  ... the bar at 100 % with FullyCharged unknown: full; FullyCharged 1 at 80 % (iPadOS's own limit?): not said full", edge && WHY(in) == kMSBDWhyNotCharging);
    in = KT(); in.ncr = MSBD_NCR_IPADOS; in.amp = 0; in.notChargingFor = 0;
    check("iPadOS 18's own charge limit (reasons 0x1000000, the A12Z): \"Charging On Hold by iPadOS\" at once, no level", WHY(in) == kMSBDWhyHeldByIPadOS && !strcmp(WhyLine(in), "Charging On Hold by iPadOS"));
    in.ncr = 0; in.obc = 1;
    check("  ... iPadOS's Optimized Battery Charging engaged (IOPS): the same", WHY(in) == kMSBDWhyHeldByIPadOS);
    in = KT(); in.ncr = MSBD_NCR_INHIBIT; in.amp = 0; in.notChargingFor = 0; edge = WHY(in) == kMSBDWhyOnHold && !strcmp(WhyLine(in), "Charging On Hold");
    in.pmu = 1; in.ncr = MSBD_NCR_PREDICTIVE;
    check("a hold not the job's: powerd's ChargeInhibit (0x4000, the M1), PredictiveChargingInhibit (0x8000, the PMU iPads): \"Charging On Hold\" at once", edge && WHY(in) == kMSBDWhyOnHold);
    in = KT(); in.notChargingFor = 0; in.amp = 0; in.ncr = 1ULL << 2; in.tempCC = 3700; edge = WHY(in) == kMSBDWhyTooWarm && !strcmp(WhyLine(in), "Not Charging: Battery Too Warm");
    in.ncr = 1ULL << 4; edge = edge && WHY(in) == kMSBDWhyTooWarm; in.ncr = 1ULL << 8; in.tempCC = 4200; edge = edge && WHY(in) == kMSBDWhyTooWarm;
    check("too warm (SMC bit 2, 4 or 8, the battery at 37.00 C or more: where the PMU iPads' own charger holds for heat): \"Not Charging: Battery Too Warm\" at once", edge);
    in.ncr = 1ULL << 2; in.tempCC = 3699; edge = WHY(in) == kMSBDWhyNone; in.notChargingFor = 180; edge = edge && WHY(in) == kMSBDWhyNotCharging;
    in.tempKnown = 0; in.tempCC = 0; in.notChargingFor = 0; edge = edge && WHY(in) == kMSBDWhyNone;
    check("  ... the bit with the battery at 36.99 C, or no Temperature read: not said (nothing, then \"Not Charging\" after 3 minutes)", edge);
    in = KT(); in.notChargingFor = 0; in.amp = 0; in.tempCC = 3000; edge = 1;
    for (int bit = 2; bit <= 8; bit += (bit == 4 ? 4 : 2)) { in.ncr = 1ULL << bit; if (WHY(in) != kMSBDWhyNone) edge = 0; }
    in.pmu = 1; in.inhibit = -1; in.ncr = MSBD_NCR_PMU_WARM; in.tempCC = 3058; edge = edge && WHY(in) == kMSBDWhyNone;
    check("  ... (review) a working iPad's temperature (30.00 C; the M1's 30.58 C as it ran down in use) with a warm bit or the PMU value: never \"Too Warm\"", edge);
    in = KT(); in.notChargingFor = 0; in.amp = 0; in.ncr = 1ULL << 1; in.tempCC = 1000; edge = WHY(in) == kMSBDWhyTooCold && !strcmp(WhyLine(in), "Not Charging: Battery Too Cold");
    in.ncr = 1ULL << 3; in.tempCC = -500; edge = edge && WHY(in) == kMSBDWhyTooCold; in.tempCC = 1001; edge = edge && WHY(in) == kMSBDWhyNone;
    check("too cold (SMC bit 1 or 3, 10.00 C or less, below 0 too): \"Not Charging: Battery Too Cold\"; at 10.01 C not said", edge);
    in = KT(); in.pmu = 1; in.inhibit = -1; in.notChargingFor = 0; in.amp = 0; in.ncr = MSBD_NCR_PMU_WARM; in.tempCC = 3800; edge = WHY(in) == kMSBDWhyTooWarm;
    in.ncr = MSBD_NCR_PMU_COLD; in.tempCC = 500; edge = edge && WHY(in) == kMSBDWhyTooCold;
    in.ncr = 1ULL << 2; in.tempCC = 3800; in.notChargingFor = 180; edge = edge && WHY(in) == kMSBDWhyNotCharging;
    in.pmu = 0; in.ncr = MSBD_NCR_PMU_WARM; edge = edge && WHY(in) == kMSBDWhyNotCharging;
    check("the PMU iPads' temperature values (0x100000001 too hot, 0x100000000 too cold); an SMC bit on a PMU charger, a PMU value on an SMC battery: not a temperature", edge);
    in = KT(); in.notChargingFor = 0; in.amp = 0; in.full = 1; in.soc = 100; in.ncr = (1ULL << 2) | MSBD_NCR_IPADOS; in.tempCC = 3800; edge = WHY(in) == kMSBDWhyFull;
    in.full = 0; in.soc = 60; edge = edge && WHY(in) == kMSBDWhyTooWarm; in.tempCC = 2500; edge = edge && WHY(in) == kMSBDWhyHeldByIPadOS;
    in.ncr = MSBD_NCR_IPADOS | MSBD_NCR_INHIBIT; edge = edge && WHY(in) == kMSBDWhyHeldByIPadOS;
    check("the order: ours, then full, then temperature, then iPadOS's hold, then another hold", edge);
    unsigned long long unnamed[] = { 1ULL << 5, 1ULL << 11, 1ULL << 13, 1ULL << 20, 1ULL << 22, 0xffULL << 56, 1ULL << 0 };
    int allPlain = 1;
    for (unsigned i = 0; i < sizeof unnamed / sizeof unnamed[0]; i++) {
        in = KT(); in.ncr = unnamed[i]; if (WHY(in) != kMSBDWhyNotCharging) allPlain = 0;
        in.notChargingFor = 100; if (WHY(in) != kMSBDWhyNone) allPlain = 0;
    }
    check("bits we do not name (5 charge timer, 11, 13, 20, 22, the fault byte, bit 0 without FullyCharged): never a reason -- nothing, then \"Not Charging\"", allPlain);
    int missing = 1;
    for (int m = 0; m < 7; m++) {
        in = KT();
        if (m == 0) in.ncrKnown = 0; if (m == 1) in.ampKnown = 0; if (m == 2) in.ext = -1; if (m == 3) in.raw = 0;
        if (m == 4) in.full = -1; if (m == 5) in.soc = -1; if (m == 6) in.inhibit = 0x10001;
        if (WHY(in) != kMSBDWhyNotCharging) { missing = 0; printf("      (reading %d)\n", m); }
    }
    in = KT(); in.inhibit = -1; in.pmu = 1;
    check("a reading missing (reasons, current, connected, the raw cable, FullyCharged, the level) or an inhibit reason: \"Not Charging\", never too weak", missing);
    check("  ... ChargerInhibitReason absent (the PMU iPads have none): too weak as on the SMC iPads", WHY(in) == kMSBDWhyTooWeak);
    MSBDBattWhyIn sb = { .onAdapter = 1, .charging = 0, .full = -1, .soc = 45, .ext = -1, .raw = -1, .inhibit = -1, .obc = -1, .notChargingFor = 200 };
    edge = WHY(sb) == kMSBDWhyNotCharging; sb.notChargingFor = 100; edge = edge && WHY(sb) == kMSBDWhyNone; sb.soc = 100; edge = edge && WHY(sb) == kMSBDWhyFull;
    check("the battery service not readable in SpringBoard (SBUIController's flags only): \"Not Charging\" after 3 minutes, full at 100 %, never a reason", edge);
    in = KT(); edge = MSBDBattWhyFirst(in) == -1; in.full = 1; in.soc = 100; edge = edge && MSBDBattWhyFirst(in) == kMSBDWhyFull; in = KT(); in.charging = 1;
    check("MSBDBattWhyFirst: undecided (-1, where the menu reads the IOPS flag) only when the battery's own statements say nothing", edge && MSBDBattWhyFirst(in) == kMSBDWhyNone);
    // ---- how long, as the menu and the job keep it (1.8.8.1 review, common/ChargeWhy.h MSBDBattWhyClock): the job's hold ending, the drain lasting
    check("the 3 minutes after the job's own hold ends: from its end (0 s) to 179.9 s, not at 180 s, not before it, none without one",
          MSBDBattWhyOursEnded(1000, 1000) && MSBDBattWhyOursEnded(1000, 1179.9) && !MSBDBattWhyOursEnded(1000, 1180) && !MSBDBattWhyOursEnded(1000, 999)
          && !MSBDBattWhyOursEnded(0, 100));
    MSBDBattWhyClock c = { 0 };
    MSBDBattWhyIn ct = KT();
    MSBDBattWhyOurs(&c, 1000, 1); MSBDBattWhyTick(&c, 1000, 1, 1); MSBDBattWhyTimes(&c, 1000, &ct);
    edge = ct.ourHold && ct.notChargingFor == 0 && ct.drainingFor < 0 && WHY(ct) == kMSBDWhyNone;
    MSBDBattWhyTick(&c, 1300, 1, 1); MSBDBattWhyTimes(&c, 1300, &ct); ct.ncr = MSBD_NCR_IPADOS;
    edge = edge && ct.ourHold && ct.notChargingFor == 300 && ct.drainingFor < 0 && WHY(ct) == kMSBDWhyNone;
    check("KT's A12Z on 7 W, the job holding at 80 % for 5 minutes (iPadOS's limit, our policy): ours, no reason; not charging counted, the drain not", edge);
    MSBDBattWhyOurs(&c, 1300, 0); MSBDBattWhyTick(&c, 1300, 1, 0); MSBDBattWhyTimes(&c, 1300, &ct);
    edge = ct.ourHold && WHY(ct) == kMSBDWhyNone;
    MSBDBattWhyTick(&c, 1310, 1, 1); MSBDBattWhyTimes(&c, 1310, &ct);
    edge = edge && ct.ourHold && WHY(ct) == kMSBDWhyNone;
    check("  ... Charge to Full Now: the hold's bit 0x1000000 still read, at once and 10 s on: no reason (\"Charging On Hold by iPadOS\" for our own hold)", edge);
    ct.ncr = 0; ct.amp = 0; MSBDBattWhyTick(&c, 1420, 1, 0); MSBDBattWhyTick(&c, 1479, 1, 0); MSBDBattWhyTimes(&c, 1479, &ct);   // (0 mA: the battery waits its 120 s)
    edge = ct.ourHold && ct.notChargingFor == 479 && ct.drainingFor < 0 && WHY(ct) == kMSBDWhyNone;
    ct.amp = -800; MSBDBattWhyTick(&c, 1480, 1, 1); MSBDBattWhyTimes(&c, 1480, &ct);
    edge = edge && !ct.ourHold && ct.drainingFor == 0 && WHY(ct) == kMSBDWhyNotCharging;
    check("  ... 179 s after its end, the bit gone, 0 mA: still none (the battery's own 120 s wait); at 180 s, 800 mA out again just now: \"Not Charging\"", edge);
    MSBDBattWhyTick(&c, 1659, 1, 1); MSBDBattWhyTimes(&c, 1659, &ct); edge = WHY(ct) == kMSBDWhyNotCharging;
    MSBDBattWhyTick(&c, 1660, 1, 1); MSBDBattWhyTimes(&c, 1660, &ct); edge = edge && ct.drainingFor == 180 && WHY(ct) == kMSBDWhyTooWeak;
    check("  ... the battery giving 800 mA for 3 minutes: too weak (7 W), not a second before", edge && !strcmp(WhyLine(ct), "Not Charging: Power Adapter Too Weak (7 W)"));
    MSBDBattWhyTick(&c, 1661, 1, -1); MSBDBattWhyTimes(&c, 1661, &ct); edge = ct.drainingFor < 0 && ct.notChargingFor == 661;
    MSBDBattWhyTick(&c, 1662, 0, 1); MSBDBattWhyTimes(&c, 1662, &ct); edge = edge && ct.notChargingFor < 0 && ct.drainingFor < 0;
    MSBDBattWhyTick(&c, 1663, 1, 1); MSBDBattWhyTimes(&c, 1663, &ct); edge = edge && ct.notChargingFor == 0 && ct.drainingFor == 0;
    check("  ... the current not read: the drain starts over; charging (or off the adapter): both start over at the next reading", edge);
    MSBDBattWhyClock c2 = { 0 }; MSBDBattWhyOurs(&c2, 50, 0); MSBDBattWhyTimes(&c2, 50, &ct);
    check("no job (word 0) or never its hold: never ours", !ct.ourHold && !c2.oursEndedAt);
    int lines = 1;
    for (int r = kMSBDWhyNotCharging; r <= kMSBDWhyFull; r++) { if (!MSBDBattWhyLine(r, 255, gL, sizeof gL) || strlen(gL) > 48) lines = 0; }
    check("every reason has a short line (48 characters at most, 255 W too); none has none", lines && !MSBDBattWhyLine(kMSBDWhyNone, 7, gL, sizeof gL));
    char ml[96];
    check("the menu's line without the job (word 0): the reason, or none", MSBDBattMenuLine(0, 45, kMSBDWhyTooWeak, 7, ml, sizeof ml) && !strcmp(ml, "Not Charging: Power Adapter Too Weak (7 W)")
          && MSBDBattMenuLine(0, 60, kMSBDWhyOnHold, 0, ml, sizeof ml) && !strcmp(ml, "Charging On Hold") && !MSBDBattMenuLine(0, 45, kMSBDWhyNone, 7, ml, sizeof ml) && !MSBDBattOurHold(0)
          && !MSBDBattMenuLineAfter(0, 100, kMSBDWhyFull, 0, ml, sizeof ml));

#if MSBD_BATT_CHARGE
    // ---- the job's line: MSBDBattChargeLine(word, soc) -- words as the job publishes them (MSBDChargeStateWord(state, limit, plugged))
    char t[96];
    #define LINE(w, soc) (MSBDBattChargeLine((w), (soc), t, sizeof t) ? t : "")
    uint64_t hold = MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1);
    check("on hold at the limit (the 72 h test: 82 %, limit 80): \"Charging On Hold at 80%\"", !strcmp(LINE(hold, 82), "Charging On Hold at 80%"));
    check("  ... still held 5 % under it after a hold (77 %): the same", !strcmp(LINE(hold, 77), "Charging On Hold at 80%"));
    check("  ... held above the band (coming down off, plugged in at 87 %): \"Charging On Hold\", no number (it holds where it is)",
          !strcmp(LINE(hold, 87), "Charging On Hold") && !strcmp(LINE(hold, 83), "Charging On Hold"));
    check("charging toward the limit: \"Charging to 85%\"", !strcmp(LINE(MSBDChargeStateWord(kMSBDChargeStateCharging, 85, 1), 60), "Charging to 85%"));
    check("the adapter cut (iPad on its battery while plugged in): \"Using Battery Until 80%\"",
          !strcmp(LINE(MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1), 93), "Using Battery Until 80%"));
    check("Charge to Full Now / the monthly full charge: \"Charging to 100%\" / \"Monthly Charge to 100%\"",
          !strcmp(LINE(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1), 90), "Charging to 100%")
          && !strcmp(LINE(MSBDChargeStateWord(kMSBDChargeStateMonthlyFull, 80, 1), 99), "Monthly Charge to 100%"));
    check("the hold does not take with this adapter (the job gave it up, iPadOS charges as always): \"Charging Can't Be Paused\"",
          !strcmp(LINE(MSBDChargeStateWord(kMSBDChargeStateCantHold, 80, 1), 84), "Charging Can't Be Paused"));
    // ---- 1.8.8.1: the line with a reason (MSBDBattMenuLine): the job's lines that say iPadOS charges give way to it; its own hold and cut do not
    #define MLINE(w, soc, why, watts) (MSBDBattMenuLine((w), (soc), (why), (watts), t, sizeof t) ? t : "")
    uint64_t to80 = MSBDChargeStateWord(kMSBDChargeStateCharging, 80, 1);
    check("KT's case with the job running: \"Charging to 80%\" for the first 3 minutes (as before), then \"Not Charging: Power Adapter Too Weak (7 W)\" in its place",
          !strcmp(MLINE(to80, 45, kMSBDWhyNone, 7), "Charging to 80%") && !strcmp(MLINE(to80, 45, kMSBDWhyTooWeak, 7), "Not Charging: Power Adapter Too Weak (7 W)"));
    check("  ... \"Charging to 100%\" / \"Monthly Charge to 100%\" once full: \"Fully Charged\"; \"Charging Can't Be Paused\" not charging: \"Not Charging\"",
          !strcmp(MLINE(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1), 100, kMSBDWhyFull, 0), "Fully Charged") && !strcmp(MLINE(MSBDChargeStateWord(kMSBDChargeStateMonthlyFull, 80, 1), 100, kMSBDWhyFull, 0), "Fully Charged")
          && !strcmp(MLINE(MSBDChargeStateWord(kMSBDChargeStateCantHold, 80, 1), 84, kMSBDWhyNotCharging, 0), "Not Charging"));
    // (1.8.8.1, review of the line) "Charging Can't Be Paused" is the only word on why the battery is above the limit: once the battery stops it
    // follows the reason, it is not dropped (it was, at 100 % with an 80 % limit: "Fully Charged" alone)
    #define ALINE(w, soc, why, watts) (MSBDBattMenuLineAfter((w), (soc), (why), (watts), t, sizeof t) ? t : "")
    uint64_t cant = MSBDChargeStateWord(kMSBDChargeStateCantHold, 80, 1);
    check("  ... \"Charging Can't Be Paused\" once the battery stops: the reason, then that line after it (100 % with an 80 % limit: \"Fully Charged\", "
          "\"Charging Can't Be Paused\"; 97 %: \"Not Charging\", the same; on 7 W: too weak, the same)",
          !strcmp(MLINE(cant, 100, kMSBDWhyFull, 0), "Fully Charged") && !strcmp(ALINE(cant, 100, kMSBDWhyFull, 0), "Charging Can't Be Paused")
          && !strcmp(MLINE(cant, 97, kMSBDWhyNotCharging, 0), "Not Charging") && !strcmp(ALINE(cant, 97, kMSBDWhyNotCharging, 0), "Charging Can't Be Paused")
          && !strcmp(ALINE(cant, 84, kMSBDWhyTooWeak, 7), "Charging Can't Be Paused"));
    check("  ... charging (no reason): \"Charging Can't Be Paused\" alone, nothing after it; no line after any other job line, the job's word off the cable, or no job",
          !strcmp(MLINE(cant, 84, kMSBDWhyNone, 0), "Charging Can't Be Paused") && !MSBDBattMenuLineAfter(cant, 84, kMSBDWhyNone, 0, t, sizeof t)
          && !MSBDBattMenuLineAfter(to80, 45, kMSBDWhyTooWeak, 7, t, sizeof t) && !MSBDBattMenuLineAfter(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1), 100, kMSBDWhyFull, 0, t, sizeof t)
          && !MSBDBattMenuLineAfter(MSBDChargeStateWord(kMSBDChargeStateMonthlyFull, 80, 1), 100, kMSBDWhyFull, 0, t, sizeof t)
          && !MSBDBattMenuLineAfter(hold, 82, kMSBDWhyOnHold, 0, t, sizeof t) && !MSBDBattMenuLineAfter(MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1), 93, kMSBDWhyTooWeak, 7, t, sizeof t)
          && !MSBDBattMenuLineAfter(MSBDChargeStateWord(kMSBDChargeStateCantHold, 80, 0), 100, kMSBDWhyFull, 0, t, sizeof t) && !MSBDBattMenuLineAfter(0, 100, kMSBDWhyFull, 0, t, sizeof t));
    check("  ... the job's own hold and cut keep their lines: \"Charging On Hold at 80%\", \"Using Battery Until 80%\"",
          !strcmp(MLINE(hold, 82, kMSBDWhyOnHold, 0), "Charging On Hold at 80%") && !strcmp(MLINE(MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1), 93, kMSBDWhyTooWeak, 7), "Using Battery Until 80%"));
    check("  ... the job installed but its limit off or off the cable (no job line): the reason alone", !strcmp(MLINE(MSBDChargeStateWord(kMSBDChargeStateOff, kMSBDChargeLimitOff, 1), 60, kMSBDWhyOnHold, 0), "Charging On Hold"));
    MSBDBattWhyIn ours = KT(); ours.ourHold = MSBDBattOurHold(hold); ours.ncr = MSBD_NCR_INHIBIT; ours.amp = 0;
    check("the job's hold read from its word (MSBDBattOurHold: on hold, coming down; not charging, full, or no job): no reason decided under it",
          ours.ourHold && WHY(ours) == kMSBDWhyNone && MSBDBattOurHold(MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1)) && !MSBDBattOurHold(to80)
          && !MSBDBattOurHold(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1)) && !MSBDBattOurHold(0));
    check("no line: off the cable, the limit off, the job not running (no word), paused (Stopped), nothing to do (Off)",
          !MSBDBattChargeLine(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 0), 80, t, sizeof t)
          && !MSBDBattChargeLine(MSBDChargeStateWord(kMSBDChargeStateOff, kMSBDChargeLimitOff, 1), 80, t, sizeof t)
          && !MSBDBattChargeLine(0, 80, t, sizeof t)
          && !MSBDBattChargeLine(MSBDChargeStateWord(kMSBDChargeStateStopped, 80, 1), 80, t, sizeof t)
          && !MSBDBattChargeLine(MSBDChargeStateWord(kMSBDChargeStateOff, 80, 1), 80, t, sizeof t));
    // ---- the Charge Limit row: MSBDBattChargeLimitValue(word, limitPref)
    char v[32];
    MSBDBattChargeLimitValue(hold, 80, v, sizeof v);
    check("the row says the limit as set: \"80%\"", !strcmp(v, "80%"));
    MSBDBattChargeLimitValue(MSBDChargeStateWord(kMSBDChargeStateOff, 95, 0), 95, v, sizeof v);
    check("  ... \"95%\" off the cable too (the job runs, holds nothing)", !strcmp(v, "95%"));
    MSBDBattChargeLimitValue(MSBDChargeStateWord(kMSBDChargeStateOff, kMSBDChargeLimitOff, 1), kMSBDChargeLimitOff, v, sizeof v);
    char v2[32]; MSBDBattChargeLimitValue(0, 77, v2, sizeof v2);
    check("  ... \"Off\": switched off (100), or a value Settings never writes (77)", !strcmp(v, "Off") && !strcmp(v2, "Off"));
    MSBDBattChargeLimitValue(0, 80, v, sizeof v);
    MSBDBattChargeLimitValue(MSBDChargeStateWord(kMSBDChargeStateStopped, 80, 1), 80, v2, sizeof v2);
    check("  ... \"Not Running\": a limit set but no job running (no word), or paused (Stopped)", !strcmp(v, "Not Running") && !strcmp(v2, "Not Running"));
    check("Charge to Full Now offered while the job holds below full on the cable, not while it charges to full",
          MSBDChargeOffersFullNow(hold, 80) && !MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1), 80)
          && !MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 0), 80));
    // ---- the battery glyph (1.8.6): a plug while on the adapter and not charging, iOS's bolt while charging, iOS's battery otherwise
    check("the plug: Charge Limit on hold at 80 % on the adapter", MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1)));
    check("  ... using the battery down to the limit while plugged in (the adapter cut), and Run on Power Adapter (its hold at the plug-in level, 55)",
          MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1)) && MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateOnHold, 55, 1)));
    check("  ... not while charging (to the limit, to full, the monthly full charge, or a hold this adapter ignores): iOS's bolt",
          !MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateCharging, 80, 1)) && !MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1))
          && !MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateMonthlyFull, 80, 1)) && !MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateCantHold, 80, 1)));
    check("  ... not unplugged, with no job (word 0), with the limit off, or paused: iOS's battery as it is",
          !MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 0)) && !MSBDBattHoldPlug(0)
          && !MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateOnHold, kMSBDChargeLimitOff, 1)) && !MSBDBattHoldPlug(MSBDChargeStateWord(kMSBDChargeStateStopped, 80, 1)));
    MSBDBattPlugBox pb = MSBDBattPlugPlace(26.5, 12);   // (the iPad 2's bar battery at Small, 16.7.7)
    check("the plug in the iPad 2's battery (26.5 x 12): 7.44 pt high, 1.5 times as wide, centred on the body (not the pin), a 1.2 pt gap around it",
          near(pb.h, 7.44) && near(pb.w, 11.16) && near(pb.x + pb.w / 2, 26.5 * 0.905 / 2) && near(pb.y + pb.h / 2, 6) && near(pb.halo, 1.2));
    MSBDBattPlugBox tiny = MSBDBattPlugPlace(10, 12), none = MSBDBattPlugPlace(0, 12);
    check("  ... a narrow battery: the plug at most 80 % of the body's width, still 1.5 to 1; an empty view: no plug",
          near(tiny.w, 10 * 0.905 * 0.8) && near(tiny.w, tiny.h * 1.5) && none.w == 0 && none.h == 0);
    MSBDBattPlugBox big = MSBDBattPlugPlace(26.5 * 1.35, 12 * 1.35);
    check("  ... at a larger Menu Bar Size it grows with the battery", near(big.h, pb.h * 1.35) && near(big.x, pb.x * 1.35));
    printf("(with the Charge Limit's job: its line and row checked)\n");
#else
    printf("(no Charge Limit job in this tree: its line and row are not compiled)\n");
#endif
    return fails;
}
