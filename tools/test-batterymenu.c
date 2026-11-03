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
    printf("(with the Charge Limit's job: its line and row checked)\n");
#else
    printf("(no Charge Limit job in this tree: its line and row are not compiled)\n");
#endif
    return fails;
}
