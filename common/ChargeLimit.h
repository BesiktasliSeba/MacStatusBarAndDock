// ChargeLimit.h -- MacStatusBar&Dock's Charge Limit (1.7.8 item 5, plans/battery-charging.md): what the root helper chargehelper/ (msbdcharge, launchd
// job com.besiktasliseba.chargelimit) does with the battery while the iPad is on power. Shared by the helper, the Battery Health page's Charging
// group (macsettings/BatteryHealth.x) and the menu bar's battery (statusbar/), and tested on the Mac (tools/test-chargelimit.c). Plain C.
//
// The limit is Settings' "Charge Limit" (80, 85, 90, 95 %; 100 or none = off). On power, below the limit: iPadOS charges as always (the helper keeps
// the iPad from idle sleep meanwhile, or it would charge on past the limit while the helper sleeps). At the limit, or a percent or two over it:
// charging is held there -- the battery idles, the adapter powers the iPad (a hold, not a discharge) -- until the battery is 5 % under it
// (Apple's own band on the iPads that have the limit: stop at 80, resume at 75). Further above the limit on power (it was full when the limit was
// set, or after a full charge): with coming down on (MSBD_CHARGE_COMEDOWN_KEY, on unless switched off), the adapter is cut so the iPad runs from
// its battery down to the limit, kept awake meanwhile (asleep it would take days), then the hold; with it off, held where it is. The end of a cut
// looks like plugging in to iPadOS (A12Z: the Lock Screen lit for ~9 s), so a small overshoot is held, not cut. "Charge to Full Now" lets it
// charge to 100 % until the cable comes out; with coming down on, so does a monthly full charge (Apple's limit charges to 100 % now and then, to
// keep the battery reading accurate), which comes back down after an hour at full. Off the cable, with the limit off, and whenever the tweak is
// not meant to run: nothing held, iPadOS's own charging.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define MSBD_CHARGE_DOMAIN "com.besiktasliseba.macstatusbar"         // (Settings writes it as mobile; the helper reads it as mobile)
#define MSBD_CHARGE_LIMIT_KEY "chargeLimit"                             // 80 / 85 / 90 / 95; 100 or missing = off
#define MSBD_CHARGE_COMEDOWN_KEY "chargeComeDown"                       // YES: above the limit on power, come down to it; NO: held where it is
#define MSBD_CHARGE_ADAPTER_KEY "chargeRunOnAdapter"                    // YES: Run on Power Adapter (MSBDChargeAdapterLimit); missing = off
#define MSBD_CHARGE_PREFS_CHANGED "com.besiktasliseba.macstatusbar/prefsChanged"
#define MSBD_CHARGE_STATE "com.besiktasliseba.chargelimit.state"       // the helper's state for the bar and Settings (notify state word, below)
#define MSBD_CHARGE_FULL_NOW "com.besiktasliseba.chargelimit.fullnow"  // Settings -> helper: Charge to Full Now (until the cable comes out)
#define MSBD_CHARGE_FULL_CANCEL "com.besiktasliseba.chargelimit.fullcancel"   // Settings -> helper: back to the limit
#define MSBD_CHARGE_CUT_ENDING "com.besiktasliseba.chargelimit.cutending"  // helper -> SpringBoard: our adapter cut is let go now (iPadOS will take the
                                                                           // power coming back for a new connection: SpringBoard keeps it quiet)
#define MSBD_CHARGE_STOP "com.besiktasliseba.chargelimit.stop"         // the package -> helper (msbdcharge --stop, the prerm): let go of everything
                                                                       // now, you are about to be stopped (MSBDChargeStopping)
#if DEBUG
#define MSBD_CHARGE_TEST_LIMIT_KEY "chargeTestLimit"                   // debug builds: any limit 1-99, so a hold can be tried at any charge
#endif

enum { kMSBDChargeLimitOff = 100 };
// Coming down to the limit is on unless switched off (each end of a cut looks like plugging in to iPadOS -- the charging chime, the Lock Screen
// lit for ~9 s on the A12Z -- until SpringBoard hides it; accepted for that). Off: above the limit on power, charging is held where the battery
// is, and there is no monthly full charge (nothing would bring it back down).
enum { kMSBDChargeComeDownDefault = 1 };
// What the helper does now: nothing held (iPadOS charges), hold (charging stopped, the adapter powers the iPad), or down (the adapter cut: the
// iPad runs from its battery while plugged in).
enum { kMSBDChargeAllow = 0, kMSBDChargeHold = 1, kMSBDChargeDown = 2 };
// What the bar and Settings show (bits 0-7 of the state word): limit off or not on power; charging to the limit; on hold at the limit; coming
// down to it; charging to full for Charge to Full Now (until unplugged); not running (a start loop or the tweak not meant to run); charging to
// full for the monthly full charge (an hour at full, then back down: the helper's own, MSBDChargeDecide answers ToFull for both); charging can't
// be paused (the hold lets charge in on this iPad with this adapter, MSBDChargeLeverCheck: iPadOS charges as always until the cable comes out).
enum { kMSBDChargeStateOff = 0, kMSBDChargeStateCharging = 1, kMSBDChargeStateOnHold = 2, kMSBDChargeStateComingDown = 3, kMSBDChargeStateToFull = 4,
       kMSBDChargeStateStopped = 5, kMSBDChargeStateMonthlyFull = 6, kMSBDChargeStateCantHold = 7 };

static inline int MSBDChargeLimitOn(int limit) { return limit >= 1 && limit < kMSBDChargeLimitOff; }
// The limit as stored: 80, 85, 90 or 95 (Apple's steps, iOS 18 / macOS 26); anything else is off (a debug build's test limit goes through
// MSBDChargeTestLimit instead).
static inline int MSBDChargeLimitFromPref(int stored) {
    return stored == 80 || stored == 85 || stored == 90 || stored == 95 ? stored : kMSBDChargeLimitOff;
}
static inline int MSBDChargeTestLimit(int stored) { return stored >= 1 && stored <= 99 ? stored : 0; }

// The state word (notify state): bits 0-7 the state, 8-15 the limit (100 = off), bit 16 on power, bit 17 the helper is running.
static inline uint64_t MSBDChargeStateWord(int state, int limit, int plugged) {
    return (uint64_t)(state & 0xff) | ((uint64_t)(limit & 0xff) << 8) | ((uint64_t)(plugged ? 1 : 0) << 16) | (1ULL << 17);
}
static inline int MSBDChargeWordState(uint64_t w) { return (w >> 17) & 1 ? (int)(w & 0xff) : kMSBDChargeStateOff; }
static inline int MSBDChargeWordLimit(uint64_t w) { return (w >> 17) & 1 ? (int)((w >> 8) & 0xff) : kMSBDChargeLimitOff; }
static inline int MSBDChargeWordPlugged(uint64_t w) { return (int)((w >> 16) & 1); }

typedef struct {
    int limit;          // 1-99 on, 100 off (MSBDChargeLimitFromPref / MSBDChargeTestLimit)
    int soc;            // the battery level as iPadOS shows it (CurrentCapacity, 0-100)
    int plugged;        // the cable is in (AppleRawExternalConnected; while our "down" is up the SMC iPads read it as out: see the helper)
    int toFull;         // Charge to Full Now, or the monthly full charge under way
    int prev;           // what the helper did last (kMSBDChargeAllow / Hold / Down)
    int running;        // the tweak is meant to run (iPad, tested iPadOS or Enable Anyway, not the crash guard's safe mode) and no start loop
    int cutAllowed;     // a new adapter cut may start (MSBDChargeCutAllowed); an ongoing one always goes on to the limit
    int comeDown;       // coming down to the limit is on (MSBD_CHARGE_COMEDOWN_KEY); off: held above the limit, a cut under way ends
    int holdIgnored;    // the hold has let charge in during this plug-in (MSBDChargeLeverCheck): nothing held, nothing cut, iPadOS's own charging
    int cutIgnored;     // the cut has let charge in during this plug-in: above the limit held where it is, as with coming down off
    int holdOnTrial;    // the hold is up and charge still goes in (or it has just gone up): no cut for a level passing the band meanwhile, the
                        // check decides first (else a hold that does not take turns into a cut at the band's top and back, again and again)
} MSBDChargeIn;
typedef struct {
    int action;         // kMSBDChargeAllow / Hold / Down
    int keepAwake;      // keep the iPad from idle sleep (charging toward the limit: the helper must see it get there)
    int state;          // kMSBDChargeState...
} MSBDChargeOut;

static inline MSBDChargeOut MSBDChargeDecide(MSBDChargeIn in) {
    MSBDChargeOut o = { kMSBDChargeAllow, 0, kMSBDChargeStateOff };
    if (!in.running) { o.state = kMSBDChargeStateStopped; return o; }
    if (!MSBDChargeLimitOn(in.limit) || !in.plugged) return o;                    // iPadOS's own charging
    if (in.toFull) { o.state = kMSBDChargeStateToFull; return o; }
    if (in.holdIgnored) { o.state = kMSBDChargeStateCantHold; return o; }   // (a cut that ends where nothing holds would only come back, again and again)
    if (in.soc < 20) { o.keepAwake = 1; o.state = kMSBDChargeStateCharging; return o; }   // never hold or cut a nearly empty battery
    int limit = in.limit;
    if (in.soc > limit) {
        // a percent or two over the limit (the gauge settling after a hold, a level that passed the limit between two readings, plugged in at
        // 81 %): held there -- unless already coming down, which goes on down to the limit. A hold on trial stays one, however far over.
        if (in.prev != kMSBDChargeDown && (in.soc <= limit + 2 || (in.prev == kMSBDChargeHold && in.holdOnTrial))) { o.action = kMSBDChargeHold; o.state = kMSBDChargeStateOnHold; return o; }
        // further over: coming down -- or held where it is, with coming down off, a cut that does not take, or when a new cut may not start now
        if (!in.comeDown || in.cutIgnored || (in.prev != kMSBDChargeDown && !in.cutAllowed)) { o.action = kMSBDChargeHold; o.state = kMSBDChargeStateOnHold; return o; }
        o.action = kMSBDChargeDown; o.keepAwake = 1; o.state = kMSBDChargeStateComingDown; return o;
    }
    if (in.soc == limit) { o.action = kMSBDChargeHold; o.state = kMSBDChargeStateOnHold; return o; }
    // under the limit: held on until 5 % under it after a hold or a come-down, else charging toward it (kept awake)
    if ((in.prev == kMSBDChargeHold || in.prev == kMSBDChargeDown) && in.soc > limit - 5) { o.action = kMSBDChargeHold; o.state = kMSBDChargeStateOnHold; return o; }
    o.keepAwake = 1; o.state = kMSBDChargeStateCharging; return o;
}

// Run on Power Adapter (KT, 6 Nov: "run fully on the charger, without relying on the battery"): while plugged in, the battery is held where it was
// when the cable went in (or when the option was switched on) -- the adapter powers iPad, the battery neither charges nor runs it -- with the
// Charge Limit's own hold, band and checks: the level it holds is the limit MSBDChargeDecide works to. Never above the Charge Limit when one is set
// (plugged in above it: the limit's own rules, coming down to it), never under 20 % (charged to 20 % first), and at most 99 % (plugged in full: held
// full, no top-ups). Off: the Charge Limit as it is. A load the adapter cannot carry draws the battery down under the hold, and 5 % under the level
// it charges back to it (as a Mac does). Where the hold does not take, nothing is held (MSBDChargeIn holdIgnored). The monthly full charge (only
// with a Charge Limit set) leaves the battery full: the helper then holds "full" (levelAtPlugIn 100), so it comes back down to the limit after it.
static inline int MSBDChargeAdapterLimit(int limit, int runOnAdapter, int levelAtPlugIn) {
    if (!runOnAdapter || levelAtPlugIn < 0) return limit;
    int at = levelAtPlugIn < 20 ? 20 : levelAtPlugIn > 99 ? 99 : levelAtPlugIn;
    return MSBDChargeLimitOn(limit) && limit < at ? limit : at;
}

// The monthly full charge: due once 30 days have passed since the battery was last seen full on power (lastFull 0 = never seen: counted from the
// helper's first start instead, so a new install does not begin with one), only while a limit is on. Done after an hour at full.
#define MSBD_CHARGE_CALIBRATION_DAYS 30
static inline int MSBDChargeCalibrationDue(double now, double lastFull, double firstStart, int limitOn) {
    double since = lastFull > 0 ? lastFull : firstStart;
    return limitOn && since > 0 && now - since >= MSBD_CHARGE_CALIBRATION_DAYS * 86400.0;
}
static inline int MSBDChargeCalibrationDone(double fullSince, double now) { return fullSince > 0 && now - fullSince >= 3600; }

// The self-checks. Allowed but not charging though well under full, the cable in and the adapter not cut (iPadOS itself charges below 95 %):
// after 3 minutes (the battery's own 120 s settle, and then some), once per 10 minutes -- the helper raises and releases a hold, so powerd writes
// "charging allowed" to the battery again (a hold left behind by a restarted powerd; BattSafePro's fix for the same).
static inline int MSBDChargeNeedsPulse(int action, int plugged, int isCharging, int fullyCharged, int soc, double allowedFor, double sinceLastPulse) {
    return action == kMSBDChargeAllow && plugged && !isCharging && !fullyCharged && soc < 95 && allowedFor >= 180 && sinceLastPulse >= 600;
}
// The hold and the cut checked against the battery. One takes when no charge goes in (Amperage at most 100 mA) once the battery has settled (holds
// took within 20-30 s on the M1 and the iPad 2). Charge still going in 2 minutes after it went up: raised again once (a restarted powerd, a driver
// that missed it); still going in 2 minutes after that, or the level 3 % above where it was when it went up: it does not take here, with this
// adapter -- given up until the cable comes out (MSBDChargeIn holdIgnored / cutIgnored). Seen: the A12Z's hold on 18.5 (2.2-2.9 A in with powerd
// holding our ChargeInhibit, not-charging reasons 0, at every hold of the 72-hour run, which then went on to the cut at 83 % and back for two days,
// the iPad kept awake) and the 17.5 on a 19 W adapter (93 % -> 100 % under our cut, 6 Nov), while both held on their 5-10 W bricks.
enum { kMSBDLeverFine = 0, kMSBDLeverRaiseAgain = 1, kMSBDLeverIgnored = 2 };
// A hold that did not take is remembered for that adapter (its kind and name) on that iPadOS build, by that build of the helper (a later one may
// hold where it could not), for 7 days: the next plug-ins with it give it
// up at once, rather than coming down from above the limit for hours, kept awake, only to find again that it does not hold at the bottom (the
// A12Z is plugged in at 85-95 % most days). A change to a charge setting forgets it (tried again now: the limit, coming down, Run on Power Adapter,
// by their values -- not the tweak's other settings, whose rows post the same note), as does a hold seen to take with that adapter.
#define MSBD_CHARGE_REMEMBER_DAYS 7
static inline int MSBDChargeHoldKnownIgnored(const char *remembered, double rememberedAt, const char *now_key, double now) {
    return remembered && now_key && *remembered && !strcmp(remembered, now_key) && rememberedAt > 0 && now >= rememberedAt &&
           now - rememberedAt < MSBD_CHARGE_REMEMBER_DAYS * 86400.0;
}
// chargingIn: 1 charge going in (an Amperage reading over 100 mA, or IsCharging 1); 0 none (an Amperage reading of at most 100 mA, IsCharging not
// 1): it takes; -1 unknown (no Amperage reading, IsCharging not 1). Unknown is never "it takes": it is timed as charge going in (raised again, then
// given up -- for the plug-in only, the helper remembers no adapter for it), as a hold that cannot be checked means iPadOS's own charging. The
// level 3 % up counts only with charge seen going in: a gauge correction during a long hold (Run on Power Adapter, coming down off) is no charge.
static inline int MSBDChargeLeverCheck(int chargingIn, double chargingFor, int raisedAgain, double sinceRaisedAgain, int risenBy) {
    if (!chargingIn) return kMSBDLeverFine;
    if (chargingIn > 0 && risenBy >= 3) return kMSBDLeverIgnored;
    if (!raisedAgain) return chargingFor >= 120 ? kMSBDLeverRaiseAgain : kMSBDLeverFine;
    return sinceRaisedAgain >= 120 ? kMSBDLeverIgnored : kMSBDLeverFine;
}
// An adapter cut showing in the battery service (one the helper does not hold: left by a powerd that restarted while one of ours was up; the
// driver keeps it, the new powerd does not know it). PMU iPads: the cable in (AppleRawExternalConnected) but ExternalConnected false. SMC iPads
// read the cable as out during a cut; their charger data shows it instead (A12Z, 1 Nov: NotChargingReason bit 54 and ChargerInhibitReason
// 0x10000 for exactly as long as the cut was up).
static inline int MSBDChargeCutShown(int raw, int ext, uint64_t notChargingReason, long long chargerInhibitReason) {
    return (raw == 1 && ext == 0) || (notChargingReason & (1ULL << 54)) || (chargerInhibitReason > 0 && (chargerInhibitReason & 0x10000));
}
// The cable while the helper's own cut is up. PMU iPads still read it (AppleRawExternalConnected). SMC iPads read it as out, but keep the
// adapter's details (AdapterDetails: A12Z 13 W before and during the cut); unplugged they change (A12Z: 0 W; M1 on its keyboard: the
// keyboard's 3 W). So: in while the adapter is the one seen when the cut went up.
typedef struct { long long watts, familyCode, adapterID; unsigned long descriptionHash; } MSBDChargeAdapter;
// (The wattage itself may change -- an adapter renegotiating -- so only "none" counts; the adapter's kind, ID and name must stay.) No adapter
// figure when the cut went up: no way to tell, so in until the limit, as the cut lasts no longer.
static inline int MSBDChargeSameAdapter(MSBDChargeAdapter atCut, MSBDChargeAdapter now) {
    return now.watts > 0 && atCut.familyCode == now.familyCode && atCut.adapterID == now.adapterID && atCut.descriptionHash == now.descriptionHash;
}
static inline int MSBDChargePlugged(int raw, int ourCutUp, MSBDChargeAdapter atCut, MSBDChargeAdapter now) {
    return raw == 1 || (ourCutUp && (atCut.watts <= 0 || MSBDChargeSameAdapter(atCut, now)));
}
// SpringBoard after the job's "cut ending" note (statusbar/ChargeQuiet.x): the charging chime and the screen wake for a power change are skipped
// for 20 s -- the power coming back is our cut's end, not a connection -- unless another adapter is in by then (a real plug-in: as always). The
// same adapter unplugged and plugged in again within those 20 s cannot be told apart, and stays quiet.
#define MSBD_CHARGE_QUIET_SECONDS 20.0
static inline int MSBDChargeQuietAfterCut(double sinceCutEnd, MSBDChargeAdapter atCutEnd, MSBDChargeAdapter now) {
    if (sinceCutEnd < 0 || sinceCutEnd > MSBD_CHARGE_QUIET_SECONDS) return 0;
    return !(atCutEnd.watts > 0 && now.watts > 0 && !MSBDChargeSameAdapter(atCutEnd, now));
}
// When a new cut may start. Every end of a cut lights the Lock Screen, so cuts must never come and go in a loop, whatever the cause: at most one
// start per 30 minutes, and none for the rest of a plug-in once a cut ended as "cable out" but the cable read in again right after (the
// adapter reading was wrong: holding instead is safe). A real unplug (the cable out with no cut of ours up) clears that.
static inline int MSBDChargeCutAllowed(double now, double lastCutStart, int misreadThisPlugIn) {
    return !misreadThisPlugIn && (lastCutStart <= 0 || now - lastCutStart >= 1800);
}

// ---- Settings > Battery > Battery Health: our Charging group (macsettings/BatteryHealth.x), in place of Apple's iPhone-only groups
// The group's footer: what the helper does now (from its state word; only on power, or when it is paused or not running) and what the limit and
// Run on Power Adapter do (from the settings). "Charge to Full Now" is offered while either is on and the helper holds the battery below full on
// power.
static inline void MSBDChargeFooterText(uint64_t word, int limitPref, int comeDown, int runOnAdapter, char *buf, size_t n) {
    int limit = MSBDChargeLimitFromPref(limitPref), on = MSBDChargeLimitOn(limit) || runOnAdapter, running = (int)((word >> 17) & 1);
    int state = MSBDChargeWordState(word), at = MSBDChargeWordLimit(word), plugged = MSBDChargeWordPlugged(word);
    char now[200] = "";
    if (on && !running) snprintf(now, sizeof now, "Charge Limit is not running right now.\n\n");
    else if (on && state == kMSBDChargeStateStopped) snprintf(now, sizeof now, "Charge Limit is paused while MacStatusBar&Dock is off.\n\n");
    else if (on && plugged && MSBDChargeLimitOn(at)) {
        switch (state) {
            case kMSBDChargeStateCharging: snprintf(now, sizeof now, "Charging to %d%%.\n\n", at); break;
            case kMSBDChargeStateOnHold: snprintf(now, sizeof now, "Charging on hold. iPad is using the power adapter.\n\n"); break;   // (at the limit, or above it with coming down off)
            case kMSBDChargeStateComingDown: snprintf(now, sizeof now, "Using the battery until it is down to %d%%, then charging on hold.\n\n", at); break;
            case kMSBDChargeStateToFull: snprintf(now, sizeof now, "Charging to 100%% until iPad is unplugged.\n\n"); break;
            case kMSBDChargeStateMonthlyFull: snprintf(now, sizeof now, "Monthly full charge: charging to 100%%, then back to %d%%.\n\n", at); break;
            case kMSBDChargeStateCantHold: snprintf(now, sizeof now, "iPad can't pause charging with this power adapter, so it charges as usual until it is unplugged.\n\n"); break;
            default: break;
        }
    }
    if (runOnAdapter && MSBDChargeLimitOn(limit) && comeDown) snprintf(buf, n, "%sWhile iPad is plugged in, it runs on the power adapter and its battery keeps the charge "
                                                         "it had, up to %d%%. Below 20%%, iPad charges to 20%% first.", now, limit);
    else if (runOnAdapter) snprintf(buf, n, "%sWhile iPad is plugged in, it runs on the power adapter and its battery keeps the charge it had. Below 20%%, "
                                    "iPad charges to 20%% first.", now);
    else if (on && comeDown) snprintf(buf, n, "%sWhile iPad is plugged in, charging stops at %d%% to reduce battery wear and starts again at %d%%. About once a "
                                      "month iPad charges to 100%% to keep its battery reading accurate.", now, limit, limit - 5);
    else if (on) snprintf(buf, n, "%sWhile iPad is plugged in, charging stops at %d%% to reduce battery wear and starts again at %d%%. Plugged in above "
                          "%d%%, iPad keeps its charge where it is.", now, limit, limit - 5, limit);
    else snprintf(buf, n, "Stops charging at the level you choose while iPad stays plugged in, to reduce battery wear.");
}
// (The level held is the state word's: with Run on Power Adapter on and no limit set, the level it holds.)
static inline int MSBDChargeOffersFullNow(uint64_t word, int limitPref) {
    int state = MSBDChargeWordState(word);
    return (MSBDChargeLimitOn(MSBDChargeLimitFromPref(limitPref)) || MSBDChargeLimitOn(MSBDChargeWordLimit(word))) && ((word >> 17) & 1) && MSBDChargeWordPlugged(word) &&
           (state == kMSBDChargeStateCharging || state == kMSBDChargeStateOnHold || state == kMSBDChargeStateComingDown);
}

// A hold or an adapter cut of the Charge Limit's that no helper holds any more: powerd can keep what a helper held after the helper is gone (the
// M1, 5-7 Nov: three "Charge Limit (on hold)" holds listed under dead pids, one as dasd's, one as backboardd's -- pids powerd still had a record
// of from a process before ours). Ours by the name, held under a pid that is not this helper's. A leftover hold keeps charging off and a
// leftover cut keeps the adapter cut, whatever this helper does: powerd lets go of a kind only when the last one goes (with the job removed the
// M1 did not charge at 80 %, regression-1.8.2-m1.md F3), and nobody but the owner process can let go of an assertion. Only powerd started over
// drops it (as the Sleep Guard does for a dead process's keep-awake one). 0 none, 1 a hold, 2 a cut.
#define MSBD_CHARGE_ASSERT_PREFIX "MacStatusBar&Dock Charge Limit"
static inline int MSBDChargeLeftoverKind(const char *type, const char *name, int pid, int helperPid) {
    if (pid == helperPid || !type || !name || strncmp(name, MSBD_CHARGE_ASSERT_PREFIX, strlen(MSBD_CHARGE_ASSERT_PREFIX))) return 0;
    return !strcmp(type, "ChargeInhibit") ? 1 : !strcmp(type, "DisableInflow") ? 2 : 0;
}
// In the way: it visibly stops what the helper wants now, with the cable in. A leftover hold: charging allowed, the cable in (AppleRawExternal-
// Connected), and the battery saying it does not charge (IsCharging 0, no current going in) though it is not full and under 95 % (iPadOS itself
// charges there) -- not unplugged, and not on an iPad whose charger ignores the hold (the A12Z on 18.5 charges under it). A leftover cut: the
// battery shows the adapter cut (MSBDChargeCutShown) while the helper does not cut, the cable in -- on the SMC iPads, whose cable reads as out
// during a cut, the adapter still described (adapterIn: some watts and its kind; unplugged the A12Z reads 0 W, the M1 on its keyboard no kind).
// Anything else blocks nothing, and is left alone: clearing it takes a powerd restart. The helper then clears it by the Sleep Guard's own rule
// (common/SleepGuard.h MSBDSGDecide): in the way for a minute (an install's old job is let go of within moments), the screen off, no live
// keep-awake assertion of another process (the restart drops those too: a download would go on with iPad asleep), at most once in 30 minutes
// and 6 times a day.
static inline int MSBDChargeLeftoverInTheWay(int hold, int cut, int action, int cableRaw, int adapterIn, int notCharging, int full, int soc, int cutShown) {
    int holdBlocks = hold && cableRaw && action == kMSBDChargeAllow && notCharging && !full && soc >= 0 && soc < 95;
    int cutBlocks = cut && (cableRaw || adapterIn) && action != kMSBDChargeDown && cutShown;
    return holdBlocks || cutBlocks;
}

// Told to stop (msbdcharge --stop: the prerm, right before its launchctl unload, which ends the helper without a SIGTERM it sees): the helper lets
// go of its hold, its cut and its stay-awake at once and raises nothing for 2 minutes, by when the package has stopped it -- what it still held at
// its death could stay with powerd (the M1, 5-7 Nov). Still running after that (the package step failed): back at work.
#define MSBD_CHARGE_STOP_SECONDS 120.0
static inline int MSBDChargeStopping(double stopAsked, double now) { return stopAsked > 0 && now >= stopAsked && now - stopAsked < MSBD_CHARGE_STOP_SECONDS; }

// A start loop: 5 starts within 10 minutes -> the helper stays idle (holds nothing) for the rest of that run.
static inline int MSBDChargeStartLoop(const double *starts, int count, double now) {
    int recent = 0;
    for (int i = 0; i < count; i++) if (starts[i] > 0 && now - starts[i] >= 0 && now - starts[i] <= 600) recent++;
    return recent >= 5;
}
