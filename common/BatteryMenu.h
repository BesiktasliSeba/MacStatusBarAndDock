// BatteryMenu.h -- the battery menu and the Control Center icon in the menu bar (MacStatusBar&Dock 1.7.9 items 1-2; the menu itself:
// statusbar/BatteryMenu.h): where the two items go in the bar and what the menu says about the Charge Limit's job, in plain C
// (tools/test-batterymenu.sh).
//
// Settings > Status Bar > Battery Menu (MSBD_BATT_MENU_KEY, on unless switched off -- updaters too): the battery in the menu bar opens our battery
// menu, and a Control Center icon (two switches, as on a Mac) left of the clock opens Control Center. Off: the battery is iPadOS's own again (a
// click on it opens Control Center, as before) and there is no icon. The pull from the top-right edge opens Control Center either way.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
// The Charge Limit's job (common/ChargeLimit.h, chargehelper/) is not in every build: where it is, the menu has its rows while the job is installed,
// from the state the job publishes; where it is not, the menu has none (and nothing of them is compiled).
#if __has_include("ChargeLimit.h")
#include "ChargeLimit.h"
#define MSBD_BATT_CHARGE 1
#define MSBD_BATT_CHARGE_JOB "/var/jb/usr/libexec/msbdcharge"   // (installed: the rows show, as the Battery Health page's Charging group does)
#else
#define MSBD_BATT_CHARGE 0
#endif

#define MSBD_BATT_MENU_KEY "batteryMenu"   // (com.besiktasliseba.macstatusbar)

// The switch as stored: a boolean, else on (never set: new installs and updaters alike).
static inline int MSBDBattMenuOn(int isBool, int value) { return isBool ? value != 0 : 1; }

// ---- the menu bar's right end, in leading coordinates (x from the leading edge: the left in English; the bar turns it for a right-to-left
// language). From the trailing end: the clock, the Control Center icon, the Spotlight icon, then the status icons -- a Mac's order (Spotlight,
// Control Center, Siri, the clock). Each icon sits `gap` before the next one; its touch area reaches `slop` past its glyph on each side, but the
// Spotlight icon's and the Control Center icon's meet halfway between the two glyphs. Without the Control Center icon, the Spotlight icon's place
// and touch area are as before 1.7.9. iconsEnd: where the icons left of them (the status icons, kClockIconsGap before it) have to end.
typedef struct { double ccLead, ccBtnLead, ccBtnTrail, spotLead, spotBtnLead, spotBtnTrail, iconsEnd; } MSBDBattRightSide;
static inline MSBDBattRightSide MSBDBattRightSideLayout(double clockEdge, int cc, double ccW, int spot, double spotW, double gap, double slop) {
    MSBDBattRightSide r = { 0, 0, 0, 0, 0, 0, 0 };
    double x = clockEdge;
    if (cc) {
        r.ccLead = x - gap - ccW;
        r.ccBtnLead = r.ccLead - slop; r.ccBtnTrail = r.ccLead + ccW + slop;
        x = r.ccLead;
    }
    if (spot) {
        r.spotLead = x - gap - spotW;
        r.spotBtnLead = r.spotLead - slop; r.spotBtnTrail = r.spotLead + spotW + slop;
        if (cc) {
            double mid = (r.spotLead + spotW + r.ccLead) / 2.0;
            if (r.spotBtnTrail > mid) r.spotBtnTrail = mid;
            if (r.ccBtnLead < mid) r.ccBtnLead = mid;
        }
        x = r.spotLead;
    }
    r.iconsEnd = x;
    return r;
}

// ---- the battery's touch area (Battery Menu on): the battery item's views (its glyph and its percentage) from lead to trail, `pad` more on
// each side, but never before `floor` -- where the touch area of our icon just before the status icons ends (the Wi-Fi icon's ends 2 pt, x the
// bar's size, before the first status icon). An empty item (lead > trail): no area (0).
static inline int MSBDBattButtonSpan(double lead, double trail, double pad, double floor, double *outLead, double *outTrail) {
    if (!(lead <= trail)) return 0;
    double a = lead - pad, b = trail + pad;
    if (a < floor) a = floor;
    if (a >= b) return 0;
    *outLead = a; *outTrail = b;
    return 1;
}

#if MSBD_BATT_CHARGE
// ---- what the menu says about the Charge Limit's job (its state word, MSBD_CHARGE_STATE: the job publishes it; Settings' footer reads the same) --
// The line under the power source while the job does something now (on power, a limit on, the job running), in a Mac menu's words: "Charging On
// Hold at 80%" -- a hold above the band at the limit (coming down switched off, plugged in at 90 %) holds the battery where it is, so it is
// "Charging On Hold" without a number then --, "Charging to 80%", "Using Battery Until 80%" (the adapter cut: iPad runs from its battery), and the
// full charges. soc: the battery's level now. 0: no line.
static inline int MSBDBattChargeLine(uint64_t word, int soc, char *buf, size_t n) {
    int at = MSBDChargeWordLimit(word);
    if (!((word >> 17) & 1) || !MSBDChargeWordPlugged(word) || !MSBDChargeLimitOn(at)) return 0;
    switch (MSBDChargeWordState(word)) {
        case kMSBDChargeStateOnHold:
            if (soc > at + 2) snprintf(buf, n, "Charging On Hold");
            else snprintf(buf, n, "Charging On Hold at %d%%", at);
            return 1;
        case kMSBDChargeStateCharging: snprintf(buf, n, "Charging to %d%%", at); return 1;
        case kMSBDChargeStateComingDown: snprintf(buf, n, "Using Battery Until %d%%", at); return 1;
        case kMSBDChargeStateToFull: snprintf(buf, n, "Charging to 100%%"); return 1;
        case kMSBDChargeStateMonthlyFull: snprintf(buf, n, "Monthly Charge to 100%%"); return 1;
        case kMSBDChargeStateCantHold: snprintf(buf, n, "Charging Can't Be Paused"); return 1;   // (the hold lets charge in with this adapter: as always)
        default: return 0;
    }
}
// ---- the battery glyph in the bar (1.8.6): on the power adapter but not charging -- Charge Limit holding the battery or using it down to the limit,
// Run on Power Adapter -- the battery shows a plug where iOS draws its charging bolt, as a Mac's menu bar battery does; charging shows the bolt (iOS's
// own); unplugged, no job, or a job that only charges as usual: iOS's battery as it is.
#define MSBD_BATT_HOLD_PIECE "batteryHoldPlug"   // (no Settings row: the crash guard turns it off as a piece, its target in tools/crashmap-rules.txt, until Turn Back On)
static inline int MSBDBattHoldPlug(uint64_t word) {
    if (!((word >> 17) & 1) || !MSBDChargeWordPlugged(word) || !MSBDChargeLimitOn(MSBDChargeWordLimit(word))) return 0;
    int s = MSBDChargeWordState(word);
    return s == kMSBDChargeStateOnHold || s == kMSBDChargeStateComingDown;
}
// The plug's place in a battery view w x h: centred on the body (the pin takes the view's last MSBD_BATT_PLUG_BODY_SHARE), its height a share of the
// view's, 1.5 times as wide as high (cord, plug body, two prongs towards the pin); `halo`: the gap cut around it through the fill, as around iOS's bolt.
#define MSBD_BATT_PLUG_BODY_SHARE 0.905
#define MSBD_BATT_PLUG_HEIGHT_SHARE 0.62
#define MSBD_BATT_PLUG_HALO_SHARE 0.1
typedef struct { double x, y, w, h, halo; } MSBDBattPlugBox;
static inline MSBDBattPlugBox MSBDBattPlugPlace(double w, double h) {
    MSBDBattPlugBox b = { 0, 0, 0, 0, 0 };
    if (!(w > 0 && h > 0)) return b;
    b.h = h * MSBD_BATT_PLUG_HEIGHT_SHARE; b.w = b.h * 1.5;
    double body = w * MSBD_BATT_PLUG_BODY_SHARE;
    if (b.w > body * 0.8) { b.w = body * 0.8; b.h = b.w / 1.5; }   // (a narrow battery: the plug never reaches its outline)
    b.x = (body - b.w) / 2.0; b.y = (h - b.h) / 2.0;
    b.halo = h * MSBD_BATT_PLUG_HALO_SHARE; if (b.halo < 0.75) b.halo = 0.75;
    return b;
}
// The Charge Limit row's value: the limit as set ("Off", "80%"), or "Not Running" while one is set but the job is not running (no state word, a
// start loop, or the tweak not meant to run -- Settings' footer: "Charge Limit is not running right now.").
static inline void MSBDBattChargeLimitValue(uint64_t word, int limitPref, char *buf, size_t n) {
    int limit = MSBDChargeLimitFromPref(limitPref);
    if (!MSBDChargeLimitOn(limit)) { snprintf(buf, n, "Off"); return; }
    if (!((word >> 17) & 1) || MSBDChargeWordState(word) == kMSBDChargeStateStopped) { snprintf(buf, n, "Not Running"); return; }
    snprintf(buf, n, "%d%%", limit);
}
#endif
