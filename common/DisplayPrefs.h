// DisplayPrefs.h -- the per-display settings' rule (MacStatusBar&Dock 1.8.7; plans/design-1.8.7-displays.md sections 2 and 3). Plain C, so
// SpringBoard's two parts, Settings, the crash guard's loaders (CrashStep.h) and the Mac test (tools/test-displayprefs.c) share one copy.
//
// Model (KT 10 Nov): every per-display setting is "the same as the iPad until changed": no override follows the iPad live; a change made for one
// display writes an override for that display only, which then sticks (even when it equals the iPad's value). A display is known by a key:
//   u-<id>   the display's own id, upper case: its display configuration's hardwareIdentifier, which on the A12Z's 4K TV equals the CADisplay
//            uniqueId on all three of its UIScreens (S1 reading, 11 Nov) and which SpringBoard keys its own per-display store on
//   any      an external display with no readable id (KT's "any display"): one bucket, as iPadOS drives one external display at a time
//   (none)   the iPad's own screen: it has no key and always takes the iPad's settings, with no lookup
// Overrides live in their own domain (MSBD_DISP_DOMAIN; KT's existing domains are never written by the layer) as flat keys
// "<display>/<part>/<key>": part msb (com.besiktasliseba.macstatusbar), dock (com.besiktasliseba.dockmagnification) or disp (display-only rows).
// The crash guard reads flat keys out of its RecentlyOn lines with sscanf %127s (CrashGuard.h), so a flat key is never longer than 127.
#pragma once
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdbool.h>
#include <math.h>
#include <stdlib.h>
#include <unistd.h>

#ifndef MSBD_DISP_DOMAIN   // (overridable for the Mac tests)
#define MSBD_DISP_DOMAIN "com.besiktasliseba.macstatusbar.displays"
#endif
#define MSBD_DISP_NOTIFY MSBD_DISP_DOMAIN "/prefsChanged"   // (the name the crash guard posts for a domain it changed)
#define MSBD_DISP_MASTER_KEY "displaySettings"   // (absent or true: on; off: every override dormant, kept)
#define MSBD_DISP_ANY "any"
#define MSBD_DISP_FLAT_MAX 127   // (the guard's sscanf width for a key, CrashGuard.h MSBDGuardSwitchOffRecent)
#define MSBD_DISP_ID_MAX 64
#ifndef MSBD_DISP_MSB_DOMAIN   // (overridable for the Mac tests: the domain whose keys are part msb)
#define MSBD_DISP_MSB_DOMAIN "com.besiktasliseba.macstatusbar"
#endif
#ifndef MSBD_DISP_DOCK_DOMAIN
#define MSBD_DISP_DOCK_DOMAIN "com.besiktasliseba.dockmagnification"
#endif

// ---- the display key ----------------------------------------------------------------------------------------------------------------------------
// An id is usable when it is 1-64 characters of letters, digits, '-', '_', '.' or ':', holds something besides '0' and '-' and is no placeholder
// word: "(null)", "(nil)", "<none>" (no brackets allowed), "null", "nil", "none", "unknown", "" are no id. A '/' or a space never gets into a key.
static inline bool MSBDDispIdUsable(const char *id) {
    if (!id || !*id) return false;
    size_t n = strlen(id);
    if (n > MSBD_DISP_ID_MAX) return false;
    bool something = false;
    for (size_t i = 0; i < n; i++) {
        char c = id[i];
        bool ok = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' || c == ':';
        if (!ok) return false;
        if (c != '0' && c != '-') something = true;
    }
    if (!something) return false;
    static const char *const words[] = { "null", "nil", "none", "unknown" };
    for (size_t w = 0; w < sizeof(words) / sizeof(words[0]); w++) if (strcasecmp(id, words[w]) == 0) return false;
    return true;
}
enum { kMSBDDispKeyMain = 0, kMSBDDispKeyId = 1, kMSBDDispKeyAny = 2 };
// The key of one screen from what was read of it: the iPad's own screen has none (kMSBDDispKeyMain, out ""); else the configuration's
// hardwareIdentifier, else the uniqueId of the CADisplay matched to it (the fallback for a nil hardwareIdentifier), else "any".
static inline int MSBDDispKeyFrom(int isMain, const char *hardwareId, const char *caUniqueId, char *out, size_t n) {
    if (!out || n == 0) return kMSBDDispKeyAny;
    out[0] = 0;
    if (isMain) return kMSBDDispKeyMain;
    const char *id = MSBDDispIdUsable(hardwareId) ? hardwareId : MSBDDispIdUsable(caUniqueId) ? caUniqueId : NULL;
    if (!id || strlen(id) + 3 > n) { snprintf(out, n, "%s", MSBD_DISP_ANY); return kMSBDDispKeyAny; }
    size_t k = 0;
    out[k++] = 'u'; out[k++] = '-';
    for (const char *c = id; *c; c++) out[k++] = (*c >= 'a' && *c <= 'z') ? (char)(*c - 'a' + 'A') : *c;
    out[k] = 0;
    return kMSBDDispKeyId;
}
// A display key as stored: "any", or "u-" and a usable id in upper case.
static inline bool MSBDDispKeyValid(const char *display) {
    if (!display) return false;
    if (strcmp(display, MSBD_DISP_ANY) == 0) return true;
    if (strncmp(display, "u-", 2) != 0 || !MSBDDispIdUsable(display + 2)) return false;
    for (const char *c = display + 2; *c; c++) if (*c >= 'a' && *c <= 'z') return false;
    return true;
}

// ---- flat keys ------------------------------------------------------------------------------------------------------------------------------------
static inline bool MSBDDispPartValid(const char *part) {
    return part && (strcmp(part, "msb") == 0 || strcmp(part, "dock") == 0 || strcmp(part, "disp") == 0);
}
static inline bool MSBDDispNameValid(const char *key) {   // (a setting's own key: no '/', no space or control character)
    if (!key || !*key) return false;
    for (const char *c = key; *c; c++) if (*c == '/' || (unsigned char)*c <= ' ' || *c == 0x7f) return false;
    return true;
}
// "<display>/<part>/<key>" into out (n bytes): its length, or 0 when refused (a bad display, part or key, or longer than 127).
static inline size_t MSBDDispFlatKey(char *out, size_t n, const char *display, const char *part, const char *key) {
    if (out && n) out[0] = 0;
    if (!out || !MSBDDispKeyValid(display) || !MSBDDispPartValid(part) || !MSBDDispNameValid(key)) return 0;
    size_t len = strlen(display) + 1 + strlen(part) + 1 + strlen(key);
    if (len > MSBD_DISP_FLAT_MAX || len + 1 > n) return 0;
    snprintf(out, n, "%s/%s/%s", display, part, key);
    return len;
}
// A flat key taken apart (display, part, key; each buffer 128 bytes is enough): true only for an override's shape. The registry's own keys
// ("<display>/info", "connected", the master switch) are not overrides.
static inline bool MSBDDispFlatSplit(const char *flat, char *display, size_t dn, char *part, size_t pn, char *key, size_t kn) {
    if (!flat || strlen(flat) > MSBD_DISP_FLAT_MAX) return false;
    const char *a = strchr(flat, '/'), *b = a ? strchr(a + 1, '/') : NULL;
    if (!a || !b) return false;
    size_t ld = (size_t)(a - flat), lp = (size_t)(b - a - 1), lk = strlen(b + 1);
    char d[128], p[128], k[128];
    if (ld >= sizeof d || lp >= sizeof p || lk >= sizeof k) return false;
    memcpy(d, flat, ld); d[ld] = 0; memcpy(p, a + 1, lp); p[lp] = 0; memcpy(k, b + 1, lk); k[lk] = 0;
    if (!MSBDDispKeyValid(d) || !MSBDDispPartValid(p) || !MSBDDispNameValid(k)) return false;
    if ((display && dn <= ld) || (part && pn <= lp) || (key && kn <= lk)) return false;
    if (display) memcpy(display, d, ld + 1);
    if (part) memcpy(part, p, lp + 1);
    if (key) memcpy(key, k, lk + 1);
    return true;
}
// Is this flat key an override of `key` in `part`, on any display ("*/part/key": the crash guard's step 1b clears these)?
static inline bool MSBDDispFlatIs(const char *flat, const char *part, const char *key) {
    char p[128], k[128];
    return part && key && MSBDDispFlatSplit(flat, NULL, 0, p, sizeof p, k, sizeof k) && strcmp(p, part) == 0 && strcmp(k, key) == 0;
}
// The part of one of KT's domains (msb, dock), or NULL: only these two hold rows a display can override.
static inline const char *MSBDDispPartOfDomain(const char *domain) {
    if (!domain) return NULL;
    if (strcmp(domain, MSBD_DISP_MSB_DOMAIN) == 0) return "msb";
    if (strcmp(domain, MSBD_DISP_DOCK_DOMAIN) == 0) return "dock";
    return NULL;
}

// ---- the rule -------------------------------------------------------------------------------------------------------------------------------------
// The rows whose display default is not the iPad's value: only Show Trash in Dock, ON (KT 10 Nov ~21:20: a display shows the Trash, even when the
// iPad's is off). Returns 1 with *value set, or 0 (the row follows the iPad until changed).
static inline int MSBDDispDisplayDefault(const char *part, const char *key, int *value) {
    if (part && key && strcmp(part, "dock") == 0 && strcmp(key, "showTrash") == 0) { if (value) *value = 1; return 1; }
    return 0;
}
// Where a display's value comes from:
//   value = isMain                ? ipad
//         : !layerOn              ? (rowHasDisplayDefault ? displayDefault : ipad)
//         : hasOverride && typeOK ? override       (a wrong type or out of range counts as absent; never clamped)
//         : rowHasDisplayDefault  ? displayDefault
//         :                         ipad
enum { kMSBDDispFromIPad = 0, kMSBDDispFromOverride = 1, kMSBDDispFromDefault = 2 };
static inline int MSBDDispResolve(int isMain, int layerOn, int hasOverride, int typeOK, int rowHasDisplayDefault) {
    if (isMain) return kMSBDDispFromIPad;
    if (!layerOn) return rowHasDisplayDefault ? kMSBDDispFromDefault : kMSBDDispFromIPad;
    if (hasOverride && typeOK) return kMSBDDispFromOverride;
    return rowHasDisplayDefault ? kMSBDDispFromDefault : kMSBDDispFromIPad;
}
// The override's type against the row's: a switch takes a boolean (or the number 0 / 1, as `defaults write -int` stores it); a number takes a
// number (not a boolean) inside [lo, hi] when the row has a range; a value row (any plist value: Mac Deck's layouts) takes anything stored.
enum { kMSBDDispVNone = 0, kMSBDDispVBool, kMSBDDispVNumber, kMSBDDispVOther };
enum { kMSBDDispWantBool = 1, kMSBDDispWantNumber, kMSBDDispWantValue };
static inline bool MSBDDispTypeOK(int want, int got, double num, int hasRange, double lo, double hi) {
    switch (want) {
        case kMSBDDispWantBool: return got == kMSBDDispVBool || (got == kMSBDDispVNumber && (num == 0.0 || num == 1.0));
        case kMSBDDispWantNumber: return got == kMSBDDispVNumber && isfinite(num) && (!hasRange || (num >= lo && num <= hi));
        case kMSBDDispWantValue: return got != kMSBDDispVNone;
        default: return false;
    }
}

// ---- the registry (SpringBoard's status bar part writes it on connect and disconnect only) --------------------------------------------------------
// "<display>/info" = {name, route, px "WxH", points "WxH", scale, firstSeen, lastSeen}; "connected" = the keys connected now. At most 8 displays
// are remembered: a 9th forgets one that is not connected now, with its keys: the one seen longest ago of those with nothing of the user's own,
// and only when every one has something, the one seen longest ago of all.
#define MSBD_DISP_CONNECTED_KEY "connected"
#define MSBD_DISP_INFO_SUFFIX "/info"
#define MSBD_DISP_REMEMBER_MAX 8
// hasOwn: the display holds something of the user's own -- a setting of its own (an override of a row, DisplayRowStore.h MSBDDispStoreHasOwn), a
// More Space record (disp/scalePending) or Mac Switcher desktops of its own (MSBDDispMSWBusy). Review of 1.8.7: the 9th went by lastSeen alone, so
// over the Lightning AV adapter (a new display id on every connect) the TV the user set up went after 8 replugs, its settings and its desktops with
// it (MacSwitcher.h DMMSWForgetGone), while 7 plain copies of the same TV stayed; 1.8.8's relink would have had nothing left to relink.
typedef struct { const char *key; long lastSeen; int connected; int hasOwn; } MSBDDispSeen;
// Which remembered display to forget so that at most `max` stay: of those not connected, the one seen longest ago with nothing of its own; when
// every one has something, the one seen longest ago (the first in the list on a tie, both ways). -1 when `max` or fewer are remembered, or none
// can go.
static inline int MSBDDispForgetPick(const MSBDDispSeen *list, int n, int max) {
    if (!list || n <= max) return -1;
    int pick = -1;
    for (int pass = 0; pass < 2 && pick < 0; pass++)
        for (int i = 0; i < n; i++) {
            if (list[i].connected || !list[i].key) continue;
            if (pass == 0 && list[i].hasOwn) continue;   // (the plain ones first)
            if (pick < 0 || list[i].lastSeen < list[pick].lastSeen) pick = i;
        }
    return pick;
}
// The Mac Switcher's desktops of one display are its own when it has two or more desktops, or a window record on one of them (one empty desktop is
// what every display gets the first time: nothing of the user's). The registry (statusbar/DisplayPrefs.h DMDispMSWOwn, from the file) and the Mac
// Switcher's own limit (statusbar/MSWDisplays.h MSWDispTrim, from its models) both keep these before plain ones.
static inline bool MSBDDispMSWBusy(int desks, int records) { return desks > 1 || records > 0; }
// The Mac Switcher's desktops file, under the home folder (statusbar/MacSwitcher.h DMMSWStatePath; MSWDisplays.h has its format).
#define MSBD_MSW_STATE_FILE "Library/Preferences/com.besiktasliseba.macstatusbar.desktops.plist"
// The route, metadata only (never part of the key; 1.8.8's pointer defaults): read from the CADisplay whose id is the key, by its deviceName --
// external-* is a direct link (USB-C), wireless* an encoded one (AirPlay, and the Lightning Digital AV Adapter); anything else unknown (NULL, not
// written). Never from FBS names (the wired TV is "AirPlay[2-3]") or from the idle "Wireless" CADisplays every iPad lists.
static inline const char *MSBDDispRouteOf(const char *deviceName) {
    if (!deviceName) return NULL;
    if (strncmp(deviceName, "external-", 9) == 0 && deviceName[9]) return "direct";
    if (strncmp(deviceName, "wireless", 8) == 0) return "encoded";
    return NULL;
}

// ---- the crash guard's note of a switch turned on for a display (commit 4) ----------------------------------------------------------------------
// A switch turned on for one display (the Display Settings window, Settings' Displays page) is noted in the guard's RecentlyOn list as its domain and
// flat key, in the list's own format ("<time> <domain> <key> <row title>", CrashGuard.h MSBDGuardSwitchOffRecent; Settings' LineSwitch.h
// MSBDNoteSwitch writes the iPad's): two crashes within 2 min and the guard's step 1 writes false into that override and posts the displays
// domain, with no change to the guard. Turned off, the line goes; lines older than 10 min go (the guard looks 2 min back). The title: one line, at
// most 80 bytes, never cut inside a character. Written whole and renamed. Returns 1 when the list was written (or removed, left empty).
static inline int MSBDDispNoteRecent(const char *path, long now, const char *flat, const char *title, int on) {
    if (!path || !MSBDDispFlatSplit(flat, NULL, 0, NULL, 0, NULL, 0)) return 0;
    char keep[64][512]; int kept = 0;
    FILE *f = fopen(path, "r");
    if (f) {
        char line[512], domain[128], key[128]; long t;
        while (fgets(line, sizeof line, f)) {
            if (!strchr(line, '\n') || sscanf(line, "%ld %127s %127s", &t, domain, key) < 3) continue;   // (a cut or unreadable line goes)
            if (now - t >= 600 || (strcmp(domain, MSBD_DISP_DOMAIN) == 0 && strcmp(key, flat) == 0)) continue;
            if (kept < 63) memcpy(keep[kept++], line, sizeof line);
        }
        fclose(f);
    }
    if (on) {
        const char *src = title ? title : "";
        char t[81]; size_t n = 0;
        for (const char *c = src; *c && n < 80; c++) t[n++] = (*c == '\n' || *c == '\r' || *c == '\t') ? ' ' : *c;
        while (n > 0 && ((unsigned char)src[n] & 0xC0) == 0x80) n--;   // (cut before a character the 80 bytes would split)
        t[n] = 0;
        snprintf(keep[kept++], sizeof keep[0], "%ld %s %s%s%s\n", now, MSBD_DISP_DOMAIN, flat, n ? " " : "", t);
    }
    if (!kept) { unlink(path); return 1; }
    char tmp[600];
    snprintf(tmp, sizeof tmp, "%s.%d.disp", path, (int)getpid());
    if (!(f = fopen(tmp, "w"))) return 0;
    for (int i = 0; i < kept; i++) fputs(keep[i], f);
    fclose(f);
    return rename(tmp, path) == 0;
}
