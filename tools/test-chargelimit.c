// test-chargelimit.c -- Mac test of the Charge Limit's decisions (common/ChargeLimit.h, used by chargehelper/main.m): what the helper does at each
// battery level on and off power, the hold band (stop at the limit, charge again 5 % under it), coming down from above it, the full charges,
// the floor, the self-checks, the start loop, the cable and adapter-cut readings, and the state word the bar and Settings read.
#include <stdio.h>
#include <string.h>
#include "../common/ChargeLimit.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int got, int want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } else printf("PASS  %s\n", what); }
static MSBDChargeOut D(int limit, int soc, int plugged, int toFull, int prev) {
    MSBDChargeIn in = { limit, soc, plugged, toFull, prev, 1, 1, 1 };   // (coming down on: the cases below that need it off say so)
    return MSBDChargeDecide(in);
}
int main(void) {
    MSBDChargeOut o;
    Expect("stored 80 / 85 / 90 / 95 are limits", MSBDChargeLimitFromPref(80) + MSBDChargeLimitFromPref(85) + MSBDChargeLimitFromPref(90) + MSBDChargeLimitFromPref(95), 350);
    Expect("stored 100 is off", MSBDChargeLimitFromPref(100), kMSBDChargeLimitOff);
    Expect("missing (0) is off", MSBDChargeLimitFromPref(0), kMSBDChargeLimitOff);
    Expect("anything else (70, 81) is off: no hidden limits", MSBDChargeLimitFromPref(70) == kMSBDChargeLimitOff && MSBDChargeLimitFromPref(81) == kMSBDChargeLimitOff, 1);
    Expect("debug test limit 1-99 taken, 0 / 100 not", MSBDChargeTestLimit(57) == 57 && MSBDChargeTestLimit(0) == 0 && MSBDChargeTestLimit(100) == 0, 1);
    o = D(kMSBDChargeLimitOff, 100, 1, 0, kMSBDChargeAllow); Expect("limit off, on power at 100 %: iPadOS's own charging", o.action, kMSBDChargeAllow);
    Expect("  ... state off, not kept awake", o.state == kMSBDChargeStateOff && !o.keepAwake, 1);
    o = D(80, 95, 0, 0, kMSBDChargeHold); Expect("off the cable: nothing held (even right after a hold)", o.action, kMSBDChargeAllow);
    Expect("  ... state off", o.state, kMSBDChargeStateOff);
    o = D(80, 60, 1, 0, kMSBDChargeAllow); Expect("on power, 60 % under an 80 % limit: charging", o.action, kMSBDChargeAllow);
    Expect("  ... kept awake (or it would charge on past the limit in sleep)", o.keepAwake, 1);
    Expect("  ... state charging", o.state, kMSBDChargeStateCharging);
    o = D(80, 80, 1, 0, kMSBDChargeAllow); Expect("reaches 80 %: hold", o.action, kMSBDChargeHold);
    Expect("  ... on hold, not kept awake (the hold stays in sleep)", o.state == kMSBDChargeStateOnHold && !o.keepAwake, 1);
    o = D(80, 79, 1, 0, kMSBDChargeHold); Expect("held, drifts to 79: still held", o.action, kMSBDChargeHold);
    o = D(80, 76, 1, 0, kMSBDChargeHold); Expect("held, 76: still held", o.action, kMSBDChargeHold);
    o = D(80, 75, 1, 0, kMSBDChargeHold); Expect("held, 75 (5 % under): charging again", o.action, kMSBDChargeAllow);
    Expect("  ... kept awake again", o.keepAwake, 1);
    o = D(80, 77, 1, 0, kMSBDChargeAllow); Expect("charging, 77: goes on charging up to the limit (no stop inside the band)", o.action, kMSBDChargeAllow);
    o = D(80, 81, 1, 0, kMSBDChargeHold); Expect("held, the gauge settles to 81: still held, not cut", o.action, kMSBDChargeHold);
    o = D(80, 82, 1, 0, kMSBDChargeHold); Expect("held, 82: still held", o.action, kMSBDChargeHold);
    o = D(80, 83, 1, 0, kMSBDChargeHold); Expect("held, 83: coming down", o.action, kMSBDChargeDown);
    o = D(80, 81, 1, 0, kMSBDChargeAllow); Expect("charging, the level passes the limit between two readings (81): held there, not cut", o.action, kMSBDChargeHold);
    o = D(80, 82, 1, 0, kMSBDChargeAllow); Expect("plugged in at 82 % with an 80 % limit: held there (the end of a cut lights the Lock Screen)", o.action, kMSBDChargeHold);
    o = D(80, 83, 1, 0, kMSBDChargeAllow); Expect("plugged in at 83 %: coming down", o.action, kMSBDChargeDown);
    o = D(80, 100, 1, 0, kMSBDChargeAllow); Expect("plugged in at 100 % with an 80 % limit: coming down (adapter cut)", o.action, kMSBDChargeDown);
    Expect("  ... state coming down, kept awake (asleep it would take days)", o.state == kMSBDChargeStateComingDown && o.keepAwake, 1);
    o = D(80, 81, 1, 0, kMSBDChargeDown); Expect("coming down, 81: still coming down", o.action, kMSBDChargeDown);
    o = D(80, 80, 1, 0, kMSBDChargeDown); Expect("coming down, reaches 80: hold", o.action, kMSBDChargeHold);
    o = D(80, 78, 1, 0, kMSBDChargeDown); Expect("coming down, overshoots to 78: hold (inside the band)", o.action, kMSBDChargeHold);
    o = D(80, 74, 1, 0, kMSBDChargeDown); Expect("coming down, the gauge jumps to 74: charging", o.action, kMSBDChargeAllow);
    o = D(95, 96, 1, 0, kMSBDChargeAllow); Expect("95 % limit, at 96: held there", o.action, kMSBDChargeHold);
    o = D(95, 98, 1, 0, kMSBDChargeAllow); Expect("95 % limit, at 98: coming down", o.action, kMSBDChargeDown);
    o = D(80, 82, 1, 0, kMSBDChargeDown); Expect("coming down, 82: still coming down (no stop short of the limit once cut)", o.action, kMSBDChargeDown);
    o = D(80, 90, 1, 1, kMSBDChargeHold); Expect("Charge to Full Now: charging past the limit", o.action, kMSBDChargeAllow);
    Expect("  ... state charging to full, not kept awake (no limit to catch)", o.state == kMSBDChargeStateToFull && !o.keepAwake, 1);
    o = D(80, 100, 1, 1, kMSBDChargeAllow); Expect("Charge to Full Now at 100 %: left to iPadOS", o.action, kMSBDChargeAllow);
    o = D(80, 19, 1, 0, kMSBDChargeHold); Expect("19 %: never held (the floor)", o.action, kMSBDChargeAllow);
    Expect("  ... kept awake (charging toward the limit all the same)", o.keepAwake, 1);
    o = D(10, 15, 1, 0, kMSBDChargeHold); Expect("a test limit of 10, at 15: the floor wins, charging", o.action, kMSBDChargeAllow);
    MSBDChargeIn stopped = { 80, 100, 1, 0, kMSBDChargeHold, 0, 1, 1 };
    o = MSBDChargeDecide(stopped); Expect("tweak not meant to run (safe mode, untested iPadOS) or a start loop: nothing held", o.action, kMSBDChargeAllow);
    Expect("  ... state stopped", o.state, kMSBDChargeStateStopped);
    double day = 86400;
    Expect("full charge due 30 days after the last full", MSBDChargeCalibrationDue(31 * day, 1 * day, 0, 1), 1);
    Expect("  ... not after 29 days", MSBDChargeCalibrationDue(30 * day, 1.5 * day, 0, 1), 0);
    Expect("  ... never seen full: counted from the first start (a new install does not begin with one)", MSBDChargeCalibrationDue(10 * day, 0, 1 * day, 1), 0);
    Expect("  ... nor with the limit off", MSBDChargeCalibrationDue(100 * day, 1 * day, 0, 0), 0);
    Expect("full charge done after an hour at full", MSBDChargeCalibrationDone(1000, 1000 + 3600), 1);
    Expect("  ... not after 59 minutes", MSBDChargeCalibrationDone(1000, 1000 + 3540), 0);
    Expect("self-check: allowed, plugged, not charging at 60 % for 3 min: pulse", MSBDChargeNeedsPulse(kMSBDChargeAllow, 1, 0, 0, 60, 180, 9999), 1);
    Expect("  ... not before the battery's 120 s settle and more (170 s)", MSBDChargeNeedsPulse(kMSBDChargeAllow, 1, 0, 0, 60, 170, 9999), 0);
    Expect("  ... not at 96 % (iPadOS itself stops near full)", MSBDChargeNeedsPulse(kMSBDChargeAllow, 1, 0, 0, 96, 999, 9999), 0);
    Expect("  ... not when full", MSBDChargeNeedsPulse(kMSBDChargeAllow, 1, 0, 1, 60, 999, 9999), 0);
    Expect("  ... not while holding", MSBDChargeNeedsPulse(kMSBDChargeHold, 1, 0, 0, 60, 999, 9999), 0);
    Expect("  ... not twice in 10 minutes", MSBDChargeNeedsPulse(kMSBDChargeAllow, 1, 0, 0, 60, 999, 300), 0);
    // the hold and the cut checked against the battery (MSBDChargeLeverCheck: charge in, for how long, raised again, since when, level risen by)
    Expect("lever: charge going in for 2 minutes: raised again", MSBDChargeLeverCheck(1, 120, 0, 0, 1), kMSBDLeverRaiseAgain);
    Expect("  ... for 100 s (the battery settling): wait", MSBDChargeLeverCheck(1, 100, 0, 0, 0), kMSBDLeverFine);
    Expect("  ... raised again and still in 2 minutes later: it does not take here", MSBDChargeLeverCheck(1, 300, 1, 120, 2), kMSBDLeverIgnored);
    Expect("  ... raised again, 1 minute later: wait", MSBDChargeLeverCheck(1, 200, 1, 60, 2), kMSBDLeverFine);
    Expect("  ... the level 3 % above where it went up: it does not take, at once", MSBDChargeLeverCheck(1, 30, 0, 0, 3), kMSBDLeverIgnored);
    Expect("  ... no charge in (a trickle or a load the adapter cannot carry): it takes", MSBDChargeLeverCheck(0, 0, 1, 500, 0), kMSBDLeverFine);
    Expect("  ... the level 3 % up with no charge in (a gauge correction during a long hold): it takes", MSBDChargeLeverCheck(0, 0, 0, 0, 3), kMSBDLeverFine);
    Expect("  ... no current reading (unknown) for 2 minutes: not \"it takes\", raised again", MSBDChargeLeverCheck(-1, 120, 0, 0, 0), kMSBDLeverRaiseAgain);
    Expect("  ... unknown, raised again 2 minutes before: given up (iPadOS's own charging)", MSBDChargeLeverCheck(-1, 300, 1, 120, 0), kMSBDLeverIgnored);
    Expect("  ... unknown, the level 3 % up after 30 s: no verdict from the level alone", MSBDChargeLeverCheck(-1, 30, 0, 0, 3), kMSBDLeverFine);
    Expect("can't-pause state's number in the state word (the bar and Settings read it)", kMSBDChargeStateCantHold, 7);
    Expect("a hold that did not take, remembered: the same adapter on the same build 6 days on", MSBDChargeHoldKnownIgnored("22F76|e0024005|", 1000, "22F76|e0024005|", 1000 + 6 * day), 1);
    Expect("  ... not after 7 days", MSBDChargeHoldKnownIgnored("22F76|e0024005|", 1000, "22F76|e0024005|", 1000 + 7 * day), 0);
    Expect("  ... not with another adapter, nor on another build", MSBDChargeHoldKnownIgnored("22F76|e0024005|", 1000, "22F76|e0004003|usb brick", 2000) ||
           MSBDChargeHoldKnownIgnored("22F76|e0024005|", 1000, "22G86|e0024005|", 2000), 0);
    Expect("  ... nor with the clock set back before it", MSBDChargeHoldKnownIgnored("22F76|e0024005|", 5000, "22F76|e0024005|", 4000), 0);
    MSBDChargeIn ig = { 80, 82, 1, 0, kMSBDChargeHold, 1, 1, 1, 1, 0, 0 };
    o = MSBDChargeDecide(ig); Expect("hold given up for the plug-in: nothing held, nothing cut, not kept awake, state can't pause", o.action == kMSBDChargeAllow && !o.keepAwake && o.state == kMSBDChargeStateCantHold, 1);
    ig.soc = 100; o = MSBDChargeDecide(ig); Expect("  ... at 100 % too: no cut (it would only come back at the band's top)", o.action, kMSBDChargeAllow);
    ig.toFull = 1; o = MSBDChargeDecide(ig); Expect("  ... Charge to Full Now still says charging to full", o.state, kMSBDChargeStateToFull);
    MSBDChargeIn trial = { 80, 85, 1, 0, kMSBDChargeHold, 1, 1, 1, 0, 0, 1 };
    o = MSBDChargeDecide(trial); Expect("hold on trial (charge still going in), level 85: held, no cut while the check decides", o.action, kMSBDChargeHold);
    trial.holdOnTrial = 0; o = MSBDChargeDecide(trial); Expect("  ... a hold that took, the gauge at 85: coming down as before", o.action, kMSBDChargeDown);
    MSBDChargeIn cutIg = { 80, 95, 1, 0, kMSBDChargeDown, 1, 1, 1, 0, 1, 0 };
    o = MSBDChargeDecide(cutIg); Expect("cut given up during a cut at 95 %: the cut ends, held where it is", o.action == kMSBDChargeHold && o.state == kMSBDChargeStateOnHold, 1);
    cutIg.prev = kMSBDChargeAllow; cutIg.soc = 100; o = MSBDChargeDecide(cutIg); Expect("  ... plugged in at 100 %: held, no cut", o.action, kMSBDChargeHold);
    double starts[6] = { 1000, 1100, 1200, 1300, 1400, 0 };
    Expect("5 starts in 10 minutes: a start loop", MSBDChargeStartLoop(starts, 6, 1500), 1);
    Expect("  ... 5 starts over 20 minutes: not", MSBDChargeStartLoop(starts, 6, 1000 + 1200), 0);
    // the battery service as read on the iPads, 1 Nov (ct178): a cut shows on PMU iPads as the cable in but not connected, on SMC iPads in the
    // charger data only
    Expect("cut shown: PMU (17.5 / iPad 2: raw 1, connected 0, reason 0x80)", MSBDChargeCutShown(1, 0, 0x80, -1), 1);
    Expect("cut shown: SMC (A12Z: raw 0, connected 0, reasons 0x40000000000001 / 0x10001)", MSBDChargeCutShown(0, 0, 0x40000000000001ULL, 0x10001), 1);
    Expect("  ... SMC, inhibit reason only", MSBDChargeCutShown(0, 0, 0, 0x10001), 1);
    Expect("no cut: A12Z full on power (raw 1, connected 1, 0x1 / 0)", MSBDChargeCutShown(1, 1, 0x1, 0), 0);
    Expect("no cut: unplugged (raw 0, connected 0, no reasons)", MSBDChargeCutShown(0, 0, 0, 0), 0);
    Expect("no cut: M1 on hold (ChargeInhibit: reason 0x4001)", MSBDChargeCutShown(1, 1, 0x4001, 0), 0);
    Expect("no cut: no inhibit reason key (-1)", MSBDChargeCutShown(0, 0, 0, -1), 0);
    MSBDChargeAdapter a12z = { 13, 0xe0024005LL, 0, 0 }, a12zOut = { 0, 0xe0024005LL, 0, 0 };
    MSBDChargeAdapter m1 = { 17, (long long)0xFFFFFFFFE0024005ULL, 0, 4242 }, m1Keyboard = { 3, 0, 0, 777 };
    Expect("cable read as in: raw 1", MSBDChargePlugged(1, 0, a12z, a12zOut), 1);
    Expect("cable during our cut (SMC reads raw 0): the same adapter -> in", MSBDChargePlugged(0, 1, a12z, a12z), 1);
    Expect("  ... A12Z unplugged during the cut (0 W) -> out", MSBDChargePlugged(0, 1, a12z, a12zOut), 0);
    Expect("  ... M1 unplugged during the cut (its keyboard's 3 W) -> out", MSBDChargePlugged(0, 1, m1, m1Keyboard), 0);
    Expect("raw 0 and no cut of ours -> out (an adapter reading alone is not the cable: M1 keyboard)", MSBDChargePlugged(0, 0, m1, m1), 0);
    Expect("our cut but no adapter figure when it went up -> in until the limit (no way to tell)", MSBDChargePlugged(0, 1, a12zOut, a12zOut), 1);
    MSBDChargeAdapter a12z9 = { 9, 0xe0024005LL, 0, 0 }, other = { 13, 0xe0004003LL, 0, 0 };
    Expect("  ... the adapter renegotiating (13 -> 9 W) during the cut: still in", MSBDChargePlugged(0, 1, a12z, a12z9), 1);
    Expect("  ... another kind of adapter (unplugged, another plugged in): out", MSBDChargePlugged(0, 1, a12z, other), 0);
    MSBDChargeIn noCut = { 80, 100, 1, 0, kMSBDChargeAllow, 1, 0, 1 };
    o = MSBDChargeDecide(noCut); Expect("at 100 % with a new cut not allowed now: held there instead", o.action == kMSBDChargeHold && o.state == kMSBDChargeStateOnHold, 1);
    noCut.prev = kMSBDChargeDown; noCut.soc = 90;
    o = MSBDChargeDecide(noCut); Expect("  ... an ongoing cut goes on to the limit all the same", o.action, kMSBDChargeDown);
    // coming down switched off: above the limit on power, held where it is
    Expect("coming down is on unless switched off", kMSBDChargeComeDownDefault, 1);
    MSBDChargeIn hold = { 80, 100, 1, 0, kMSBDChargeAllow, 1, 1, 0 };
    o = MSBDChargeDecide(hold); Expect("coming down off, plugged in at 100 %: held there", o.action == kMSBDChargeHold && o.state == kMSBDChargeStateOnHold, 1);
    Expect("  ... not kept awake (the hold stays in sleep)", o.keepAwake, 0);
    hold.prev = kMSBDChargeDown; hold.soc = 90;
    o = MSBDChargeDecide(hold); Expect("  ... switched off during a cut at 90 %: the cut ends, held there", o.action, kMSBDChargeHold);
    hold.prev = kMSBDChargeHold; hold.soc = 95;
    o = MSBDChargeDecide(hold); Expect("  ... held at 95 %, stays held", o.action, kMSBDChargeHold);
    hold.prev = kMSBDChargeAllow; hold.soc = 60;
    o = MSBDChargeDecide(hold); Expect("  ... under the limit: charging to it as always", o.action == kMSBDChargeAllow && o.keepAwake, 1);
    hold.soc = 80;
    o = MSBDChargeDecide(hold); Expect("  ... at the limit: hold", o.action, kMSBDChargeHold);
    hold.plugged = 0; hold.soc = 100;
    o = MSBDChargeDecide(hold); Expect("  ... off the cable: nothing held", o.action, kMSBDChargeAllow);
    Expect("cut allowed: never cut before", MSBDChargeCutAllowed(5000, 0, 0), 1);
    Expect("  ... not 20 minutes after the last start", MSBDChargeCutAllowed(1000 + 1200, 1000, 0), 0);
    Expect("  ... again after 30 minutes", MSBDChargeCutAllowed(1000 + 1800, 1000, 0), 1);
    Expect("  ... not after a misread cable in this plug-in", MSBDChargeCutAllowed(99999, 1000, 1), 0);
    uint64_t w = MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1);
    Expect("state word: state", MSBDChargeWordState(w), kMSBDChargeStateOnHold);
    Expect("state word: limit", MSBDChargeWordLimit(w), 80);
    Expect("state word: on power", MSBDChargeWordPlugged(w), 1);
    Expect("no helper running (word 0): off, limit off", MSBDChargeWordState(0) == kMSBDChargeStateOff && MSBDChargeWordLimit(0) == kMSBDChargeLimitOff, 1);
    Expect("state word: the monthly full charge's own state", MSBDChargeWordState(MSBDChargeStateWord(kMSBDChargeStateMonthlyFull, 80, 1)), kMSBDChargeStateMonthlyFull);
    // the Charging group's footer and its Charge to Full Now row (Settings > Battery > Battery Health)
    char t[600];
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1), 80, 1, 0, t, sizeof t);
    Expect("footer: on hold says so, then what the limit does", strstr(t, "Charging on hold. iPad is using the power adapter.") == t && strstr(t, "stops at 80% to reduce battery wear and starts again at 75%") != NULL, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateCharging, 85, 1), 85, 1, 0, t, sizeof t);
    Expect("footer: charging to the limit", strstr(t, "Charging to 85%.") == t, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1), 80, 1, 0, t, sizeof t);
    Expect("footer: coming down", strstr(t, "Using the battery until it is down to 80%, then charging on hold.") == t, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1), 80, 1, 0, t, sizeof t);
    Expect("footer: Charge to Full Now", strstr(t, "Charging to 100% until iPad is unplugged.") == t, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateMonthlyFull, 90, 1), 90, 1, 0, t, sizeof t);
    Expect("footer: the monthly full charge", strstr(t, "Monthly full charge: charging to 100%, then back to 90%.") == t, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateOff, 80, 0), 80, 1, 0, t, sizeof t);
    Expect("footer: off the cable, no status line", strncmp(t, "While iPad is plugged in", 24) == 0, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateStopped, 80, 1), 80, 1, 0, t, sizeof t);
    Expect("footer: the tweak off -> paused", strstr(t, "Charge Limit is paused while MacStatusBar&Dock is off.") == t, 1);
    MSBDChargeFooterText(0, 80, 1, 0, t, sizeof t);
    Expect("footer: a limit set but no helper running -> said", strstr(t, "Charge Limit is not running right now.") == t, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateOff, 100, 1), 100, 1, 0, t, sizeof t);
    Expect("footer: the limit off -> what it would do, nothing else", strncmp(t, "Stops charging at the level you choose", 38) == 0, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1), 90, 1, 0, t, sizeof t);
    Expect("footer: just changed 80 -> 90: the status from the helper (80), the rule from the setting (90)", strstr(t, "Charging on hold.") == t && strstr(t, "stops at 90%") != NULL, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1), 80, 0, 0, t, sizeof t);
    Expect("footer: coming down off -> held where it is, no monthly full charge", strstr(t, "Plugged in above 80%, iPad keeps its charge where it is.") != NULL && strstr(t, "once a month") == NULL, 1);
    Expect("Charge to Full Now offered: on hold on power", MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1), 80), 1);
    Expect("  ... coming down", MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateComingDown, 80, 1), 80), 1);
    Expect("  ... not while already charging to full", MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateToFull, 80, 1), 80), 0);
    Expect("  ... not off the cable", MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateOff, 80, 0), 80), 0);
    Expect("  ... not with the limit off", MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateOff, 100, 1), 100), 0);
    Expect("  ... not with no helper running", MSBDChargeOffersFullNow(0, 80), 0);
    Expect("  ... not while charging can't be paused (it charges as usual anyway)", MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateCantHold, 80, 1), 80), 0);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateCantHold, 80, 1), 80, 1, 0, t, sizeof t);
    Expect("footer: can't pause charging with this adapter, said first", strstr(t, "iPad can't pause charging with this power adapter, so it charges as usual until it is unplugged.") == t, 1);
    // Run on Power Adapter: the level each plug-in holds (MSBDChargeAdapterLimit(limit, on, level at plug-in))
    Expect("Run on Power Adapter off: the Charge Limit as it is", MSBDChargeAdapterLimit(80, 0, 55), 80);
    Expect("  ... on, no limit, plugged in at 55 %: 55", MSBDChargeAdapterLimit(kMSBDChargeLimitOff, 1, 55), 55);
    Expect("  ... on, an 80 % limit, plugged in at 95 %: the limit (coming down to it first)", MSBDChargeAdapterLimit(80, 1, 95), 80);
    Expect("  ... on, an 80 % limit, plugged in at 60 %: 60", MSBDChargeAdapterLimit(80, 1, 60), 60);
    Expect("  ... plugged in at 12 %: 20 (never held under 20 %)", MSBDChargeAdapterLimit(kMSBDChargeLimitOff, 1, 12), 20);
    Expect("  ... plugged in full: 99 (held full, no top-ups; 100 would be no limit at all)", MSBDChargeAdapterLimit(kMSBDChargeLimitOff, 1, 100), 99);
    Expect("  ... no level yet (-1): the limit as it is", MSBDChargeAdapterLimit(80, 1, -1), 80);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateOnHold, 55, 1), 100, 1, 1, t, sizeof t);
    Expect("footer, Run on Power Adapter on and no limit: on hold now, then what it does", strstr(t, "Charging on hold. iPad is using the power adapter.") == t &&
           strstr(t, "it runs on the power adapter and its battery keeps the charge it had. Below 20%, iPad charges to 20% first.") != NULL, 1);
    MSBDChargeFooterText(MSBDChargeStateWord(kMSBDChargeStateOnHold, 80, 1), 80, 1, 1, t, sizeof t);
    Expect("  ... with an 80 % limit: up to 80%", strstr(t, "keeps the charge it had, up to 80%.") != NULL, 1);
    Expect("Charge to Full Now offered with Run on Power Adapter on and no limit (the state word's level)", MSBDChargeOffersFullNow(MSBDChargeStateWord(kMSBDChargeStateOnHold, 55, 1), 100), 1);
    // a hold or cut an earlier job left with powerd: in the way only when it visibly blocks (MSBDChargeLeftoverInTheWay(hold, cut, action, cable,
    // adapter described, not charging, full, level, cut showing))
    Expect("leftover hold: charging allowed at 60 %, the cable in, the battery not charging: in the way", MSBDChargeLeftoverInTheWay(1, 0, kMSBDChargeAllow, 1, 1, 1, 0, 60, 0), 1);
    Expect("  ... off the cable: blocks nothing", MSBDChargeLeftoverInTheWay(1, 0, kMSBDChargeAllow, 0, 0, 1, 0, 60, 0), 0);
    Expect("  ... charging all the same (the A12Z on 18.5 ignores the hold): blocks nothing", MSBDChargeLeftoverInTheWay(1, 0, kMSBDChargeAllow, 1, 1, 0, 0, 60, 0), 0);
    Expect("  ... the job holds there itself: not in the way", MSBDChargeLeftoverInTheWay(1, 0, kMSBDChargeHold, 1, 1, 1, 0, 80, 0), 0);
    Expect("  ... full, or at 96 % (iPadOS's own stop near full): not in the way", MSBDChargeLeftoverInTheWay(1, 0, kMSBDChargeAllow, 1, 1, 1, 1, 100, 0) ||
           MSBDChargeLeftoverInTheWay(1, 0, kMSBDChargeAllow, 1, 1, 1, 0, 96, 0), 0);
    Expect("leftover cut showing on an SMC iPad (the cable reads as out, the adapter still described), the job not cutting: in the way",
           MSBDChargeLeftoverInTheWay(0, 1, kMSBDChargeAllow, 0, 1, 1, 0, 60, 1), 1);
    Expect("  ... not showing in the battery: blocks nothing", MSBDChargeLeftoverInTheWay(0, 1, kMSBDChargeAllow, 0, 1, 1, 0, 60, 0), 0);
    Expect("  ... no adapter described (unplugged): blocks nothing", MSBDChargeLeftoverInTheWay(0, 1, kMSBDChargeAllow, 0, 0, 1, 0, 60, 1), 0);
    Expect("  ... the job cuts itself: not in the way", MSBDChargeLeftoverInTheWay(0, 1, kMSBDChargeDown, 0, 1, 1, 0, 90, 1), 0);
    // SpringBoard after our cut ends (statusbar/ChargeQuiet.x): quiet for 20 s with the same adapter, as always with another one
    Expect("cut end: 3 s later, the same adapter -> chime and wake skipped", MSBDChargeQuietAfterCut(3, a12z, a12z), 1);
    Expect("  ... the adapter renegotiating (13 -> 9 W): still ours, skipped", MSBDChargeQuietAfterCut(3, a12z, a12z9), 1);
    Expect("  ... another adapter plugged in meanwhile: as always", MSBDChargeQuietAfterCut(3, a12z, other), 0);
    Expect("  ... 25 s later: as always", MSBDChargeQuietAfterCut(25, a12z, a12z), 0);
    Expect("  ... no adapter figure now (0 W): ours, skipped", MSBDChargeQuietAfterCut(5, a12z, a12zOut), 1);
    Expect("  ... a clock going backwards: as always", MSBDChargeQuietAfterCut(-1, a12z, a12z), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
