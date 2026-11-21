// ChargeWhy.h -- why iPad is not charging while it is on the power adapter (1.8.8.1 BATTWHY; KT 15 Nov, after the A12Z sat at "not charging" on
// a 7 W adapter: "In these cases, the battery drop down menu should say why its not charging"). One rule, in plain C, for the battery menu
// (statusbar/BatteryMenu.h, from SpringBoard's own reads of the battery service) and for the Charge Limit's job (chargehelper/main.m, which
// publishes the reason with its state for Settings' footer: common/ChargeLimit.h MSBDChargeFooterText). Mac-tested (tools/test-batterymenu.c,
// tools/test-chargelimit.c, tools/test-chargeplan.m).
//
// A reason is named only when the readings say it for sure. A reading that is missing is unknown, never a reason; anything not known for sure is
// plain "Not Charging". The battery service's NotChargingReason (ChargerData), as read on our four iPads and as Battman's decode names its bits
// (Lessica/Battman, Battman/battery_utils/not_charging_reason.h, its "SMC (CHNC)" layout; the labels agree with every bit we have seen):
//   bit 0 fully charged; bit 7 no power in (unplugged, 0x80); bit 14 powerd's ChargeInhibit (0x4000, the M1 under a hold); bit 15 predictive
//   charging, PredictiveChargingInhibit (0x8000, the PMU iPads under a hold); bit 24 iPadOS 18's own charge limit (0x1000000, the A12Z with a
//   policy at 92 % and 97 %, gone within 20 s of the policy: not in Battman's decode); bit 54 the adapter cut (inflow off).
//   Temperature (Battman's decode only, never seen here, so they count only when the battery's own Temperature agrees): bits 1 and 3 too cold,
//   2 and 4 too hot, 8 high charge with high temperature. PMU chargers (AppleARMPMUCharger) may use Battman's older "NonSMC" layout, where
//   temperature is a value: 0x100000000 too cold, 0x100000001 too hot (bits 7 and 15 read the same in both layouts, and both were seen).
//   Not named on purpose: 5 (charge timer), 11 (kiosk mode on SMC, "POSM mode" on PMU), 13, 20, 22 and the fault byte 56-63.
// KT's case (A12Z, 18.5, 7 W, 15 Nov): cable 1, connected 1, charging 0, reasons 0x0 / 0x0 -- nothing in the bits; the battery current says it:
// at or below -100 mA the battery powers part of iPad, so the adapter gives less than iPad uses.
#pragma once
#include <stdint.h>
#include <stdio.h>

#define MSBD_NCR_FULL        (1ULL << 0)
#define MSBD_NCR_COLD        ((1ULL << 1) | (1ULL << 3))
#define MSBD_NCR_WARM        ((1ULL << 2) | (1ULL << 4) | (1ULL << 8))
#define MSBD_NCR_NO_POWER    (1ULL << 7)
#define MSBD_NCR_INHIBIT     (1ULL << 14)   // (powerd's ChargeInhibit)
#define MSBD_NCR_PREDICTIVE  (1ULL << 15)   // (PredictiveChargingInhibit)
#define MSBD_NCR_IPADOS      (1ULL << 24)   // (iPadOS 18's own charge limit)
#define MSBD_NCR_INFLOW_OFF  (1ULL << 54)   // (the adapter cut)
#define MSBD_NCR_PMU_COLD    0x100000000ULL
#define MSBD_NCR_PMU_WARM    0x100000001ULL

// The reasons (the job publishes them in its state word, bits 18-21: MSBDChargeWhyBits). None: nothing to say -- off the adapter, charging, the
// Charge Limit's own hold or cut (its own line says it), or not yet known (the menu's and the footer's lines as before).
enum { kMSBDWhyNone = 0, kMSBDWhyNotCharging = 1, kMSBDWhyTooWeak = 2, kMSBDWhyTooWarm = 3, kMSBDWhyTooCold = 4, kMSBDWhyHeldByIPadOS = 5,
       kMSBDWhyOnHold = 6, kMSBDWhyFull = 7 };

// Not charging for 3 minutes on the adapter before "Not Charging" or a too weak adapter is said: the charger starting after a plug-in, the battery's
// own 120 s wait after a hold or a cut ends (PostChargeWaitSeconds 120; the job's own self-check waits as long). A too weak adapter also needs the
// battery to have given 100 mA or more for those 3 minutes (Amperage is the current of the moment on all four iPads, the same as InstantAmperage:
// one reading in a load spike is not a weak adapter). What the battery states itself (full, temperature, a hold) shows at once -- except in the
// 3 minutes after a hold or cut of the job's own ends (MSBDBattWhyOursEnded).
#define MSBD_WHY_WAIT 180.0
#define MSBD_WHY_DRAIN_MA (-100)    // (at or below: the battery powers part of iPad; the job's 100 mA band for "no charge going in", mirrored)
// "Too warm" only at a temperature where heat limits charging: 37.00 C, the lowest heat limit these iPads name themselves (the PMU iPads' charger
// node in their device tree: penalty-box-temp-uth 0x0e74 = 37.00 C, -lth 36.00 C, with the level at 80 % / 75 %; switched off there). 30 C is a
// working iPad's (the M1's battery recorded 30.58 C as it ran down in use), so a bit we have never seen cannot name the reason by itself.
#define MSBD_WHY_WARM_CC 3700       // (Temperature, hundredths of a degree C: at least 37.00 C for "too warm")
#define MSBD_WHY_COLD_CC 1000       // (at most 10.00 C for "too cold")

typedef struct {
    int onAdapter;            // 1: the power adapter powers iPad now (SpringBoard's -isOnAC; the job: the cable in and no adapter cut); 0: not
    int charging;             // IsCharging: 1, 0, -1 unknown
    int ampKnown, amp;        // Amperage, mA (+ into the battery)
    int full;                 // FullyCharged: 1, 0, -1 unknown
    int soc;                  // the level, 0-100 (the bar's, CurrentCapacity); -1 unknown
    int ext, raw;             // ExternalConnected, AppleRawExternalConnected: 1, 0, -1 unknown
    int watts;                // AdapterDetails' Watts (0: none or unknown)
    int ncrKnown;             // NotChargingReason read
    uint64_t ncr;
    long long inhibit;        // ChargerInhibitReason (-1: absent, as on the PMU iPads)
    int tempKnown, tempCC;    // Temperature, hundredths of a degree C
    int pmu;                  // the charger: 1 AppleARMPMUCharger (A9X, A10X), 0 AppleSmartBattery
    int obc;                  // IOPS "Optimized Battery Charging Engaged": 1, 0, -1 not read (false on all four iPads: PowerUI's unsupported manager)
    int ourHold;              // the Charge Limit's job holds or cuts now (its word: on hold, coming down), or did under 3 minutes ago
    double notChargingFor;    // s on the adapter without charging; < 0 unknown (after a respring, until the first power note)
    double drainingFor;       // s of that with the battery giving 100 mA or more and no hold of the job's; < 0 not now, or unknown
} MSBDBattWhyIn;
// Charging: IsCharging 1, or charge going in (over 100 mA). Not known to be not charging (IsCharging unknown): nothing to say.
static inline int MSBDBattWhyCharging(MSBDBattWhyIn in) { return in.charging == 1 || (in.ampKnown && in.amp > 100); }
// The cases the battery states itself, taken first and shown at once: -1 when none applies (the rest of MSBDBattWhyDecide decides; the menu reads
// the IOPS flag only then).
static inline int MSBDBattWhyFirst(MSBDBattWhyIn in) {
    if (in.onAdapter != 1 || MSBDBattWhyCharging(in) || in.charging != 0) return kMSBDWhyNone;   // 0. off the adapter, charging, or not known
    if (in.ourHold) return kMSBDWhyNone;                                                        // 1. ours (or just ended): its own line
    if ((in.full == 1 && in.soc >= 95) || in.soc >= 100) return kMSBDWhyFull;                  // 2. full
    if (in.ncrKnown && in.tempKnown) {                                                          // 3. temperature: the bit and the reading agree
        int warm = in.pmu ? in.ncr == MSBD_NCR_PMU_WARM : (in.ncr & MSBD_NCR_WARM) != 0;
        int cold = in.pmu ? in.ncr == MSBD_NCR_PMU_COLD : (in.ncr & MSBD_NCR_COLD) != 0;
        if (warm && in.tempCC >= MSBD_WHY_WARM_CC) return kMSBDWhyTooWarm;
        if (cold && in.tempCC <= MSBD_WHY_COLD_CC) return kMSBDWhyTooCold;
    }
    return -1;
}
// The first case that applies wins.
static inline int MSBDBattWhyDecide(MSBDBattWhyIn in) {
    int first = MSBDBattWhyFirst(in);
    if (first >= 0) return first;
    if ((in.ncrKnown && (in.ncr & MSBD_NCR_IPADOS)) || in.obc == 1) return kMSBDWhyHeldByIPadOS;      // 4. iPadOS's own hold (its level: powerd's)
    if (in.ncrKnown && (in.ncr & (MSBD_NCR_INHIBIT | MSBD_NCR_PREDICTIVE))) return kMSBDWhyOnHold;  // 5. a hold that is not ours
    if (!(in.notChargingFor >= MSBD_WHY_WAIT)) return kMSBDWhyNone;                                // 6. under 3 minutes, or not known
    if (in.ext == 1 && in.raw == 1 && in.ncrKnown && in.ncr == 0 && in.inhibit <= 0 && in.full == 0 && in.soc >= 0 && in.soc < 95
        && in.ampKnown && in.amp <= MSBD_WHY_DRAIN_MA && in.drainingFor >= MSBD_WHY_WAIT) return kMSBDWhyTooWeak;   // 7. the battery powers part of iPad
    return kMSBDWhyNotCharging;                                                                   // 8. anything else
}
// ---- how long, kept the same way by the menu (SpringBoard's clock, CACurrentMediaTime) and by the job (its own), from the reads each makes (1.8.8.1,
// review of BATTWHY): since when the battery has not charged on the adapter, since when it has given 100 mA or more then with no hold of the
// job's, and when the job's own hold or cut last ended. 0: not now, or not seen since a start.
typedef struct { double notChargingSince, drainingSince, oursEndedAt; int ours; } MSBDBattWhyClock;
// The job's own hold or cut ended under 3 minutes ago (endedAt on the caller's clock; 0: none seen): what the battery says is still the job's --
// its hold's bit is read for up to 20 s more (the A12Z's bit 24 after its policy), and the battery charges again only after its own 120 s wait
// (PostChargeWaitSeconds) -- so no reason is decided, the job's own line stays (it said "Charging is on hold." and then "Not charging." right after
// Charge to Full Now).
static inline int MSBDBattWhyOursEnded(double endedAt, double now) { return endedAt > 0 && now >= endedAt && now - endedAt < MSBD_WHY_WAIT; }
// The job's own hold or cut now (the menu: MSBDBattOurHold of its word, when the menu reads it and at the job's note; the job: its state).
static inline void MSBDBattWhyOurs(MSBDBattWhyClock *c, double now, int ours) {
    if (c->ours && !ours) c->oursEndedAt = now;
    c->ours = ours != 0;
}
// A read of the battery: notCharging 1 on the adapter and not charging (anything else: charging, off the adapter, or not known); draining 1 the
// battery giving 100 mA or more (0 not, -1 not read). Under the job's own hold the drain is not counted (its line is said, not a reason).
static inline void MSBDBattWhyTick(MSBDBattWhyClock *c, double now, int notCharging, int draining) {
    if (notCharging != 1) c->notChargingSince = 0;
    else if (c->notChargingSince <= 0) c->notChargingSince = now;
    if (notCharging != 1 || draining != 1 || c->ours) c->drainingSince = 0;
    else if (c->drainingSince <= 0) c->drainingSince = now;
}
// What the clock says, into what the rule decides from.
static inline void MSBDBattWhyTimes(const MSBDBattWhyClock *c, double now, MSBDBattWhyIn *in) {
    in->ourHold = c->ours || MSBDBattWhyOursEnded(c->oursEndedAt, now);
    in->notChargingFor = c->notChargingSince > 0 ? now - c->notChargingSince : -1;
    in->drainingFor = c->drainingSince > 0 ? now - c->drainingSince : -1;
}

// The menu's line, a Mac menu's words ("Not Charging: Power Adapter Too Weak (7 W)"); watts 0: left out. 0: no line (none).
static inline int MSBDBattWhyLine(int why, int watts, char *buf, size_t n) {
    switch (why) {
        case kMSBDWhyNotCharging: snprintf(buf, n, "Not Charging"); return 1;
        case kMSBDWhyTooWeak:
            if (watts > 0) snprintf(buf, n, "Not Charging: Power Adapter Too Weak (%d W)", watts);
            else snprintf(buf, n, "Not Charging: Power Adapter Too Weak");
            return 1;
        case kMSBDWhyTooWarm: snprintf(buf, n, "Not Charging: Battery Too Warm"); return 1;
        case kMSBDWhyTooCold: snprintf(buf, n, "Not Charging: Battery Too Cold"); return 1;
        case kMSBDWhyHeldByIPadOS: snprintf(buf, n, "Charging On Hold by iPadOS"); return 1;
        case kMSBDWhyOnHold: snprintf(buf, n, "Charging On Hold"); return 1;
        case kMSBDWhyFull: snprintf(buf, n, "Fully Charged"); return 1;
        default: return 0;
    }
}
// Settings' footer (the Charging group on Battery Health), as a sentence. 0: none.
static inline int MSBDBattWhyFooter(int why, int watts, char *buf, size_t n) {
    switch (why) {
        case kMSBDWhyNotCharging: snprintf(buf, n, "Not charging."); return 1;
        case kMSBDWhyTooWeak:
            if (watts > 0) snprintf(buf, n, "Not charging: the power adapter (%d W) gives less power than iPad is using.", watts);
            else snprintf(buf, n, "Not charging: the power adapter gives less power than iPad is using.");
            return 1;
        case kMSBDWhyTooWarm: snprintf(buf, n, "Not charging: the battery is too warm."); return 1;
        case kMSBDWhyTooCold: snprintf(buf, n, "Not charging: the battery is too cold."); return 1;
        case kMSBDWhyHeldByIPadOS: snprintf(buf, n, "Charging is on hold by iPadOS."); return 1;
        case kMSBDWhyOnHold: snprintf(buf, n, "Charging is on hold."); return 1;
        case kMSBDWhyFull: snprintf(buf, n, "Fully charged."); return 1;
        default: return 0;
    }
}
// (the job's log and its --status)
static inline const char *MSBDBattWhyName(int why) {
    static const char *const names[] = { "none", "not charging, no reason known for sure", "the power adapter is too weak", "the battery is too warm",
                                         "the battery is too cold", "on hold by iPadOS", "on hold (not ours)", "fully charged" };
    return why >= 0 && why <= kMSBDWhyFull ? names[why] : "?";
}

// ---- in the Charge Limit job's state word (common/ChargeLimit.h; bit 17: the job is running): bits 18-21 the reason, bits 24-31 the adapter's
// watts for a too weak adapter (0 unknown, 255 at most; only with that reason, so the word changes only when what is shown does). Readers before
// 1.8.8.1 mask what they read (state 0-7, limit 8-15, on power 16, running 17), so nothing changes for them.
static inline uint64_t MSBDChargeWhyBits(int why, int watts) {
    if (why <= kMSBDWhyNone || why > kMSBDWhyFull) return 0;
    uint64_t w = (uint64_t)why << 18;
    if (why == kMSBDWhyTooWeak && watts > 0) w |= (uint64_t)(watts > 255 ? 255 : watts) << 24;
    return w;
}
static inline int MSBDChargeWordWhy(uint64_t w) { return (w >> 17) & 1 ? (int)((w >> 18) & 0xf) : kMSBDWhyNone; }
static inline int MSBDChargeWordWatts(uint64_t w) { return (w >> 17) & 1 ? (int)((w >> 24) & 0xff) : 0; }
