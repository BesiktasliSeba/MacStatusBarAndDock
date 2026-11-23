// AirPodsMenu.h -- the AirPods menu's rules, in plain C (MacStatusBar&Dock 1.8.8.1; the menu itself: statusbar/AirPodsMenu.h; Mac test:
// tools/test-airpodsmenu.sh with test-airpodsmenu.c).
//
// Settings > Status Bar > AirPods Menu (MSBD_AIRPODS_MENU_KEY, on unless switched off, updaters too): a click or a finger tap on iPadOS's own
// AirPods item in the status bar (its Bluetooth item while it shows headphones: their glyph, alone or with their level) opens a Mac-style menu
// under it: the headphones' name,
// their battery as BatteryCenter gives it (Left and Right as one level when it merges them, apart when it splits them, and the Case), Noise
// Control with only the modes they offer while they are the audio output, Disconnect, and Bluetooth Settings…. Everything here is the rules the
// menu follows, with no Apple call: where its button goes in the bar, which battery records belong to which headphones, the cells, the modes,
// the route device, the rows and what VoiceOver reads.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>

#define MSBD_AIRPODS_MENU_KEY "airpodsMenu"   // (com.besiktasliseba.macstatusbar)

// The switch as stored: a boolean, else on (never set: new installs and updaters alike, as Battery Menu).
static inline int MSBDAirPodsMenuOn(int isBool, int value) { return isBool ? value != 0 : 1; }

// ---- when there is a button: whenever iPadOS shows its Bluetooth item for headphones (1.8.8.1.1) ----
// The item has two display items: the glyph and the headphones' level beside it. iPadOS shows the glyph for connected headphones (the bar data's
// Bluetooth state 2), with the level only where SpringBoard has it drawn: on 18.5 (_updateBluetoothHeadphonesItem) only for headphones that are
// not Apple's, so AirPods show the glyph ALONE there (their level is in the Batteries widget; 1.8.8.1 asked for the level, so AirPods on 17/18 got
// no button). In some regions iPadOS also shows the item as a plain Bluetooth indicator (its other states): no headphones, no button. So: a button
// while any of the item's views shows and either its level shows (only headphones have one) or the bar's data says headphones; where the data
// cannot be read (another shape), the shown item is taken as the headphones'.
#define MSBD_AP_BT_HEADPHONES 2
static inline int MSBDAirPodsItemIsHeadphones(int viewsShown, int levelShown, int stateRead, long long state) {
    return viewsShown > 0 && (levelShown || !stateRead || state == MSBD_AP_BT_HEADPHONES);
}

// ---- the button's place (leading coordinates: x from the leading edge, the bar turns it for a right-to-left language) ----
// lead..trail: iPadOS's AirPods item's shown views (its glyph, and its headset battery when it shows), `pad` more on each side. It never starts
// before `floor` (where our Wi-Fi icon's touch area ends, as for the battery's button) or the middle of the gap to the shown view before it (prev), and never
// ends past the middle of the gap to the shown view after it (next). The battery's own button (batt, while Battery Menu is on) is never
// overlapped: the AirPods button stops where it starts, on whichever side it is. An empty item, or no room left: no area (0).
typedef struct { int has; double lead, trail; } MSBDAPSide;
static inline int MSBDAirPodsButtonSpan(double lead, double trail, double pad, double floor, MSBDAPSide prev, MSBDAPSide next, MSBDAPSide batt,
                                        double *outLead, double *outTrail) {
    if (!(lead <= trail)) return 0;
    double a = lead - pad, b = trail + pad;
    if (prev.has) { double mid = (prev.trail + lead) / 2.0; if (a < mid) a = mid; }
    if (next.has) { double mid = (trail + next.lead) / 2.0; if (b > mid) b = mid; }
    if (batt.has && batt.lead < batt.trail) {
        if ((batt.lead + batt.trail) / 2.0 >= (lead + trail) / 2.0) { if (b > batt.lead) b = batt.lead; }
        else if (a < batt.trail) a = batt.trail;
    }
    if (a < floor) a = floor;
    if (a >= b) return 0;
    *outLead = a; *outTrail = b;
    return 1;
}

// ---- what the menu knows: the headphones (BluetoothManager), the battery records (BatteryCenter) and the audio route (MediaRemote) ----
#define MSBD_AP_NAME 128
#define MSBD_AP_MAX_HEADSETS 4
#define MSBD_AP_MAX_PARTS 16
#define MSBD_AP_MAX_ROUTE 8
#define MSBD_AP_MAX_ROWS 64
// A connected Bluetooth device the menu lists (MSBDAirPodsListsDevice). name: its real name (matching only); shown: what the menu shows
// (screenshot mode's name in a debug build); level: its one battery level from Bluetooth (-1 unknown: none reported; BatteryCenter's records
// give the strip either way); connected: 0 for one the open menu listed that has gone since (Not Connected, Connect).
typedef struct { char name[MSBD_AP_NAME]; char shown[MSBD_AP_NAME]; char address[24]; long long productId; int level; int connected; } MSBDAPHeadset;
// Which connected devices the menu lists: headphones by iPadOS's own rule (BluetoothDevice -type 16 or 20, the types SpringBoard 18.5's
// _updateBluetoothHeadphonesItem shows the headphones glyph for), with or without a battery level, and, as in 1.8.8.1, any device that reports
// a battery level (supportsBatteryLevel). typeRead 0: the type could not be asked here (only the level counts then).
#define MSBD_AP_BT_TYPE_HEADSET 16
#define MSBD_AP_BT_TYPE_HEADPHONES 20
static inline int MSBDAirPodsIsHeadphonesType(int typeRead, int type) { return typeRead && (type == MSBD_AP_BT_TYPE_HEADSET || type == MSBD_AP_BT_TYPE_HEADPHONES); }
static inline int MSBDAirPodsListsDevice(int connected, int reportsLevel, int typeRead, int type) {
    return connected && (reportsLevel || MSBDAirPodsIsHeadphonesType(typeRead, type));
}
// ---- our own headphones icon where iPadOS draws no item (1.8.8.2) ----
// iPadOS 15.6.1 draws no Bluetooth item at all for real AirPods (its bar data says Bluetooth state 1), so the button over iPadOS's item had
// nothing to sit on there (16 not proven either way). So while the AirPods Menu is on, a bar that can read iPadOS's Bluetooth item (its class
// answers: itemReadable) and finds none of its views shown, with headphones connected, draws a headphones icon of its own where the status
// icons start, the AirPods button over it. Never two icons: any shown view of iPadOS's item (headphones, or a plain Bluetooth indicator) means
// none of ours, and an item that cannot be read means none either. Headphones: iPadOS's own type rule above; where the type cannot be asked,
// Apple's audio devices (AirPods, Beats). A device listed only for its battery level (a keyboard) is not headphones.
static inline int MSBDAirPodsCountsAsHeadphones(int typeRead, int type, int appleAudio) {
    return typeRead ? MSBDAirPodsIsHeadphonesType(typeRead, type) : appleAudio != 0;
}
// Never where iPadOS shows its own item for them (the review of 1.8.8.2):
//  - SystemStatusUI's bar (iPadOS 17/18, barDrawsHeadphones): SpringBoard draws its own headphones glyph there for every connected headphones
//    of the types above (18.5's -[SBStatusBarStateAggregator _updateBluetoothHeadphonesItem]; real AirPods on 18.5), so ours would only show
//    in the moment before iPadOS's own item comes (at a connection, after a respring), then make way for it: none of ours there;
//  - 15/16 (UIKit's bar): our icon waits MSBD_AP_OWN_SETTLE seconds after the headphones come (connectedFor: since the count last rose from
//    none, at a connection or at the first count after a respring), so that iPadOS's own item, which follows the same connection through
//    SpringBoard's bar data, shows first where iPadOS draws one. A named wait: no event says that iPadOS chose to draw no item.
#define MSBD_AP_OWN_SETTLE 2.0
static inline int MSBDAirPodsOwnIcon(int menuOn, int barDrawsHeadphones, int itemReadable, int itemViewsShown, int headphones, double connectedFor) {
    return menuOn && !barDrawsHeadphones && itemReadable && itemViewsShown == 0 && headphones > 0 && connectedFor >= MSBD_AP_OWN_SETTLE;
}
// One BatteryCenter record (a BCBatteryDevice, copied): parts is a bitmask -- 1 Left, 2 Right, 4 Case, 0 a single battery. BatteryCenter merges
// both buds into one record (parts 3, the lower level, the group's name) when they are close and charge alike, and keeps them apart otherwise.
typedef struct { unsigned long long parts; int percent; int charging; int internal; long long productId; char groupName[MSBD_AP_NAME]; char matchId[MSBD_AP_NAME]; } MSBDAPPart;
// One output device of the system route: deviceType (2 is Bluetooth), its uid, the known listening modes it offers (bits of the mode indexes
// below) and the current one (a mode index, -1 none or unknown).
typedef struct { unsigned type; char uid[96]; unsigned modes; int current; } MSBDAPRouteDev;
typedef struct {
    int headsetPart, partsPart, noisePart;   // (each part's calls are there with their types on this iPadOS)
    int nheadsets; MSBDAPHeadset headsets[MSBD_AP_MAX_HEADSETS];
    int nparts; MSBDAPPart parts[MSBD_AP_MAX_PARTS];
    int nroute; MSBDAPRouteDev route[MSBD_AP_MAX_ROUTE];
    int noiseError;   // (the last noise change failed: its line shows)
} MSBDAPState;

// ---- the modes, in Control Center's order (Off, Transparency, Adaptive, Noise Cancellation); matched by their string values only ----
enum { kMSBDAPModeOff = 0, kMSBDAPModeTransparency, kMSBDAPModeAdaptive, kMSBDAPModeNoiseCancellation, kMSBDAPModes };
static const char *const kMSBDAPModeStrings[kMSBDAPModes] = {
    "AVOutputDeviceBluetoothListeningModeNormal", "AVOutputDeviceBluetoothListeningModeAudioTransparency",
    "AVOutputDeviceBluetoothListeningModeAutomatic", "AVOutputDeviceBluetoothListeningModeActiveNoiseCancellation" };
static const char *const kMSBDAPModeTitles[kMSBDAPModes] = { "Off", "Transparency", "Adaptive", "Noise Cancellation" };
static inline int MSBDAirPodsModeIndex(const char *s) {   // (-1: a mode this menu does not know: left out)
    for (int i = 0; s && i < kMSBDAPModes; i++) if (!strcmp(s, kMSBDAPModeStrings[i])) return i;
    return -1;
}
// The modes offered (bits), in the order above; *tick: the place of the current one in that list, -1 when it is not offered.
static inline int MSBDAirPodsModeList(unsigned mask, int current, int out[kMSBDAPModes], int *tick) {
    int n = 0; *tick = -1;
    for (int i = 0; i < kMSBDAPModes; i++) if (mask & (1u << i)) { if (i == current) *tick = n; out[n++] = i; }
    return n;
}

// ---- the route device: an address is 17 characters ("aa:bb:cc:dd:ee:ff"); a route uid carries it in its first 17, any case (CC's uids: the
// address and a suffix) ----
static inline int MSBDAirPodsLooksLikeAddress(const char *s) {
    if (!s || strlen(s) < 17) return 0;
    for (int i = 0; i < 17; i++) {
        char c = s[i];
        if (i % 3 == 2) { if (c != ':' && c != '-') return 0; }
        else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return 0;
    }
    return 1;
}
static inline int MSBDAirPodsUIDMatches(const char *uid, const char *address) {
    return uid && address && strlen(address) == 17 && strlen(uid) >= 17 && !strncasecmp(uid, address, 17);
}
// The output device for these headphones: deviceType 2 with their address in its uid; else, with exactly one set of headphones known and exactly
// one deviceType-2 device that is not visibly another device's address, that one; else none (-1: no Noise Control).
static inline int MSBDAirPodsRoutePick(const MSBDAPRouteDev *r, int n, const char *address, int headsets) {
    if (address && address[0]) for (int i = 0; i < n; i++) if (r[i].type == 2 && MSBDAirPodsUIDMatches(r[i].uid, address)) return i;
    if (headsets != 1) return -1;
    int found = -1, count = 0;
    for (int i = 0; i < n; i++) if (r[i].type == 2) { count++; found = i; }
    if (count != 1) return -1;
    if (address && address[0] && MSBDAirPodsLooksLikeAddress(r[found].uid)) return -1;   // (another Bluetooth device's: not these headphones)
    return found;
}

// ---- which battery records are these headphones' (never by address: BatteryCenter's group id is not the Bluetooth address) ----
//  1. the bud or single records whose groupName is the headphones' Bluetooth name (the real one, never screenshot mode's): if they share exactly
//     one matchIdentifier, that is the group;
//  2. else the records with their product id: if they share exactly one matchIdentifier, that is the group;
//  3. else none (no records, or ambiguous): the heading shows the one level from Bluetooth.
// The group is every record with that matchIdentifier (the buds and the Case, whose own name differs); with an empty one, only the matched ones.
// Internal batteries (the iPad's own) never count.
static inline int MSBDAPOneMatchID(const MSBDAPPart *p, const int *cand, int nc) {   // (the one matchIdentifier the candidates share, or -1)
    if (nc <= 0) return -1;
    for (int i = 1; i < nc; i++) if (strcmp(p[cand[i]].matchId, p[cand[0]].matchId)) return -1;
    return cand[0];
}
static inline int MSBDAPGroupOf(const MSBDAPPart *p, int np, const int *cand, int nc, int *idx, int max) {
    int one = MSBDAPOneMatchID(p, cand, nc), n = 0;
    if (one < 0) return 0;
    if (!p[one].matchId[0]) { for (int i = 0; i < nc && n < max; i++) idx[n++] = cand[i]; return n; }
    for (int i = 0; i < np && n < max; i++) if (!p[i].internal && !strcmp(p[i].matchId, p[one].matchId)) idx[n++] = i;
    return n;
}
static inline int MSBDAirPodsGroupFor(const MSBDAPHeadset *h, const MSBDAPPart *p, int np, int *idx, int max) {
    int cand[MSBD_AP_MAX_PARTS], nc = 0, n;
    if (np > MSBD_AP_MAX_PARTS) np = MSBD_AP_MAX_PARTS;
    if (h && h->name[0]) {
        for (int i = 0; i < np; i++) {
            unsigned long long bits = p[i].parts & 7ULL;
            if (p[i].internal || !((bits & 3ULL) || !bits) || strcmp(p[i].groupName, h->name)) continue;
            cand[nc++] = i;
        }
        if ((n = MSBDAPGroupOf(p, np, cand, nc, idx, max)) > 0) return n;
    }
    nc = 0;
    if (h && h->productId) {
        for (int i = 0; i < np; i++) if (!p[i].internal && p[i].productId == h->productId) cand[nc++] = i;
        if ((n = MSBDAPGroupOf(p, np, cand, nc, idx, max)) > 0) return n;
    }
    return 0;
}
// With no headphones known (the Bluetooth part off here): the records' one group, only when there is exactly one.
static inline int MSBDAirPodsOnlyGroup(const MSBDAPPart *p, int np, int *idx, int max) {
    int cand[MSBD_AP_MAX_PARTS], nc = 0;
    if (np > MSBD_AP_MAX_PARTS) np = MSBD_AP_MAX_PARTS;
    for (int i = 0; i < np; i++) if (!p[i].internal) cand[nc++] = i;
    return MSBDAPGroupOf(p, np, cand, nc, idx, max);
}

// ---- the strip's cells, from the parts bits: 1 and 2 together one cell (merged), 1 Left, 2 Right, 4 the Case; 0 the heading's level. Other bits
// are ignored. Order: merged or Left then Right, then the Case. ----
enum { kMSBDAPCellBoth = 1, kMSBDAPCellLeft, kMSBDAPCellRight, kMSBDAPCellCase };
typedef struct { int kind, percent, charging; } MSBDAPCell;
static inline int MSBDAirPodsCells(const MSBDAPPart *p, const int *idx, int n, MSBDAPCell cells[4], int *single) {
    int have[5] = { 0, 0, 0, 0, 0 }, pct[5] = { 0, 0, 0, 0, 0 }, chg[5] = { 0, 0, 0, 0, 0 }, nc = 0;
    *single = -1;
    for (int i = 0; i < n; i++) {
        const MSBDAPPart *r = &p[idx[i]];
        unsigned long long bits = r->parts & 7ULL;
        int k = (bits & 3ULL) == 3ULL ? kMSBDAPCellBoth : (bits & 1ULL) ? kMSBDAPCellLeft : (bits & 2ULL) ? kMSBDAPCellRight : (bits & 4ULL) ? kMSBDAPCellCase : 0;
        if (!k) { if (*single < 0) *single = r->percent; continue; }
        if (have[k]) continue;
        have[k] = 1; pct[k] = r->percent; chg[k] = r->charging;
    }
    if (have[kMSBDAPCellBoth]) have[kMSBDAPCellLeft] = have[kMSBDAPCellRight] = 0;   // (merged and apart at once: the merged one)
    for (int k = kMSBDAPCellBoth; k <= kMSBDAPCellCase; k++) if (have[k]) { cells[nc].kind = k; cells[nc].percent = pct[k]; cells[nc].charging = chg[k]; nc++; }
    return nc;
}
static inline int MSBDAirPodsHasBud(const MSBDAPCell *c, int n) {
    for (int i = 0; i < n; i++) if (c[i].kind != kMSBDAPCellCase) return 1;
    return 0;
}

// ---- words: a level ("80%", "--" when unknown: below 0 or over 100), each glyph's SF Symbols in order with the word that stands in where none
// is there (+[UIImage systemImageNamed:] gives nil for a missing name: the word shows, never a crash) ----
static inline void MSBDAirPodsPercentText(int p, char *buf, size_t n) {
    if (p < 0 || p > 100) snprintf(buf, n, "--"); else snprintf(buf, n, "%d%%", p);
}
static const char *const kMSBDAPGlyphBoth[] = { "airpods", NULL };
static const char *const kMSBDAPGlyphLeft[] = { "airpod.left", NULL };
static const char *const kMSBDAPGlyphRight[] = { "airpod.right", NULL };
static const char *const kMSBDAPGlyphCase[] = { "airpods.chargingcase", "airpodspro.chargingcase.wireless", NULL };
static const char *const kMSBDAPGlyphCharging[] = { "bolt.fill", NULL };
#define MSBD_AP_GLYPH_CHARGING 9
static inline const char *const *MSBDAirPodsGlyphs(int kind, const char **word) {
    switch (kind) {
        case kMSBDAPCellBoth: *word = "L R"; return kMSBDAPGlyphBoth;
        case kMSBDAPCellLeft: *word = "L"; return kMSBDAPGlyphLeft;
        case kMSBDAPCellRight: *word = "R"; return kMSBDAPGlyphRight;
        case kMSBDAPCellCase: *word = "Case"; return kMSBDAPGlyphCase;
        case MSBD_AP_GLYPH_CHARGING: *word = "charging"; return kMSBDAPGlyphCharging;
        default: *word = ""; return NULL;
    }
}

// ---- the menu's blocks: one per set of headphones (heading, strip, Noise Control under the ones that are the audio output, Disconnect) ----
typedef struct {
    int headset;             // (index into the state's headsets; -1: none known -- the Bluetooth part off, or none listed)
    int connected, canConnect;
    int level;               // (the heading's level, shown when there is no bud cell: a single battery, the Case alone, no records)
    int ncells; MSBDAPCell cells[4];
    int route;               // (index into the state's route devices; -1: no Noise Control)
    int nmodes; int modes[kMSBDAPModes]; int tick;
    int noiseError;
} MSBDAPBlock;
static inline void MSBDAPBlockNoise(const MSBDAPState *st, MSBDAPBlock *b, const char *address, int headsets) {
    b->route = -1; b->nmodes = 0; b->tick = -1; b->noiseError = 0;
    if (!st->noisePart || !b->connected) return;
    int r = MSBDAirPodsRoutePick(st->route, st->nroute < MSBD_AP_MAX_ROUTE ? st->nroute : MSBD_AP_MAX_ROUTE, address, headsets);
    if (r < 0) return;
    b->nmodes = MSBDAirPodsModeList(st->route[r].modes, st->route[r].current, b->modes, &b->tick);
    if (!b->nmodes) return;
    b->route = r;
    b->noiseError = st->noiseError;
}
static inline int MSBDAirPodsBlocks(const MSBDAPState *st, MSBDAPBlock *out, int max) {
    int idx[MSBD_AP_MAX_PARTS], np = st->nparts < MSBD_AP_MAX_PARTS ? st->nparts : MSBD_AP_MAX_PARTS, n = 0, single;
    int nh = st->headsetPart ? (st->nheadsets < MSBD_AP_MAX_HEADSETS ? st->nheadsets : MSBD_AP_MAX_HEADSETS) : 0;
    if (max <= 0) return 0;
    if (!nh) {   // (whatever part works: the one group BatteryCenter has, the one Bluetooth output)
        MSBDAPBlock *b = &out[n++];
        memset(b, 0, sizeof *b);
        b->headset = -1; b->connected = 1; b->level = -1;
        int g = st->partsPart ? MSBDAirPodsOnlyGroup(st->parts, np, idx, MSBD_AP_MAX_PARTS) : 0;
        b->ncells = g ? MSBDAirPodsCells(st->parts, idx, g, b->cells, &single) : 0;
        if (g && single >= 0) b->level = single;
        MSBDAPBlockNoise(st, b, NULL, 1);
        return n;
    }
    for (int i = 0; i < nh && n < max; i++) {
        const MSBDAPHeadset *h = &st->headsets[i];
        MSBDAPBlock *b = &out[n++];
        memset(b, 0, sizeof *b);
        b->headset = i; b->connected = h->connected != 0; b->canConnect = 1; b->level = h->level;
        int g = b->connected && st->partsPart ? MSBDAirPodsGroupFor(h, st->parts, np, idx, MSBD_AP_MAX_PARTS) : 0;
        b->ncells = g ? MSBDAirPodsCells(st->parts, idx, g, b->cells, &single) : 0;
        if (g && single >= 0) b->level = single;
        MSBDAPBlockNoise(st, b, h->address, nh);
    }
    return n;
}

// ---- the rows, in macOS's order ----
enum { kMSBDAPRowHeading = 1, kMSBDAPRowStrip, kMSBDAPRowSection, kMSBDAPRowMode, kMSBDAPRowInfo, kMSBDAPRowConnect, kMSBDAPRowDisconnect,
       kMSBDAPRowSettings, kMSBDAPRowSeparator };
typedef struct { int kind, block, mode, checked, ncells; MSBDAPCell cells[4]; char text[MSBD_AP_NAME]; char value[8]; } MSBDAPRow;
#define MSBD_AP_HEADING "Headphones"
#define MSBD_AP_NOISE_TITLE "Noise Control"
#define MSBD_AP_NOISE_ERROR "Couldn't Change Noise Control"
#define MSBD_AP_NOT_CONNECTED "Not Connected"
#define MSBD_AP_SETTINGS "Bluetooth Settings\xe2\x80\xa6"   // ("Bluetooth Settings" and an ellipsis, as our other menus' Settings rows)
static inline MSBDAPRow *MSBDAPAddRow(MSBDAPRow *rows, int *n, int max, int kind, int block, const char *text) {
    if (*n >= max) return NULL;
    MSBDAPRow *r = &rows[(*n)++];
    memset(r, 0, sizeof *r);
    r->kind = kind; r->block = block; r->mode = -1;
    if (text) snprintf(r->text, sizeof r->text, "%s", text);
    return r;
}
static inline const char *MSBDAirPodsBlockName(const MSBDAPState *st, const MSBDAPBlock *b) {
    return b->headset >= 0 && b->headset < st->nheadsets && st->headsets[b->headset].shown[0] ? st->headsets[b->headset].shown : MSBD_AP_HEADING;
}
// Per block: the heading (its level at the right when there is no bud cell); while connected the strip, Noise Control (a heading, the modes with
// the tick, the error line) and Disconnect; once gone, a grey Not Connected line and Connect. Blocks apart by a separator; Bluetooth Settings…
// once, at the end. Never empty.
static inline int MSBDAirPodsMenuRows(const MSBDAPState *st, const MSBDAPBlock *blocks, int nb, MSBDAPRow *rows, int max) {
    int n = 0;
    MSBDAPRow *r;
    for (int i = 0; i < nb; i++) {
        const MSBDAPBlock *b = &blocks[i];
        if (i) MSBDAPAddRow(rows, &n, max, kMSBDAPRowSeparator, i, NULL);
        if ((r = MSBDAPAddRow(rows, &n, max, kMSBDAPRowHeading, i, MSBDAirPodsBlockName(st, b))) && b->connected && !MSBDAirPodsHasBud(b->cells, b->ncells))
            MSBDAirPodsPercentText(b->level, r->value, sizeof r->value);
        if (!b->connected) {
            MSBDAPAddRow(rows, &n, max, kMSBDAPRowInfo, i, MSBD_AP_NOT_CONNECTED);
            if (b->canConnect) { MSBDAPAddRow(rows, &n, max, kMSBDAPRowSeparator, i, NULL); MSBDAPAddRow(rows, &n, max, kMSBDAPRowConnect, i, "Connect"); }
            continue;
        }
        if (b->ncells && (r = MSBDAPAddRow(rows, &n, max, kMSBDAPRowStrip, i, NULL))) { r->ncells = b->ncells; memcpy(r->cells, b->cells, sizeof r->cells); }
        if (b->nmodes) {
            MSBDAPAddRow(rows, &n, max, kMSBDAPRowSeparator, i, NULL);
            MSBDAPAddRow(rows, &n, max, kMSBDAPRowSection, i, MSBD_AP_NOISE_TITLE);
            for (int m = 0; m < b->nmodes; m++) if ((r = MSBDAPAddRow(rows, &n, max, kMSBDAPRowMode, i, kMSBDAPModeTitles[b->modes[m]]))) { r->mode = b->modes[m]; r->checked = m == b->tick; }
            if (b->noiseError) MSBDAPAddRow(rows, &n, max, kMSBDAPRowInfo, i, MSBD_AP_NOISE_ERROR);
        }
        if (b->canConnect) { MSBDAPAddRow(rows, &n, max, kMSBDAPRowSeparator, i, NULL); MSBDAPAddRow(rows, &n, max, kMSBDAPRowDisconnect, i, "Disconnect"); }
    }
    MSBDAPAddRow(rows, &n, max, kMSBDAPRowSeparator, nb, NULL);
    MSBDAPAddRow(rows, &n, max, kMSBDAPRowSettings, -1, MSBD_AP_SETTINGS);
    return n;
}
// The open menu is rebuilt only when this changes: every field a row shows, and nothing else (FNV-1a over the rows).
static inline uint64_t MSBDAirPodsSignature(const MSBDAPRow *rows, int n) {
    uint64_t h = 1469598103934665603ULL;
#define MSBD_AP_MIX(v) do { uint64_t x_ = (uint64_t)(int64_t)(v); for (int s_ = 0; s_ < 64; s_ += 8) { h ^= (x_ >> s_) & 0xff; h *= 1099511628211ULL; } } while (0)
    for (int i = 0; i < n; i++) {
        const MSBDAPRow *r = &rows[i];
        MSBD_AP_MIX(r->kind); MSBD_AP_MIX(r->block); MSBD_AP_MIX(r->mode); MSBD_AP_MIX(r->checked); MSBD_AP_MIX(r->ncells);
        for (int c = 0; c < r->ncells && c < 4; c++) { MSBD_AP_MIX(r->cells[c].kind); MSBD_AP_MIX(r->cells[c].percent); MSBD_AP_MIX(r->cells[c].charging); }
        for (const char *p = r->text; *p; p++) { h ^= (uint8_t)*p; h *= 1099511628211ULL; }
        MSBD_AP_MIX(0x1f);
        for (const char *p = r->value; *p; p++) { h ^= (uint8_t)*p; h *= 1099511628211ULL; }
        MSBD_AP_MIX(0x1e);
    }
#undef MSBD_AP_MIX
    return h;
}

// ---- what VoiceOver reads: the strip ("Left and Right 75 percent, Case 40 percent, charging") and the bar button's value (each set of
// headphones: its name, then its strip or its level) ----
static inline void MSBDAPAppend(char *buf, size_t n, const char *s) { size_t l = strlen(buf); if (l + 1 < n) snprintf(buf + l, n - l, "%s", s); }
static inline void MSBDAirPodsCellsAXText(const MSBDAPCell *c, int nc, char *buf, size_t n) {
    static const char *const names[] = { "", "Left and Right", "Left", "Right", "Case" };
    if (n) buf[0] = 0;
    for (int i = 0; i < nc; i++) {
        char one[64];
        if (c[i].kind < kMSBDAPCellBoth || c[i].kind > kMSBDAPCellCase) continue;
        if (c[i].percent < 0 || c[i].percent > 100) snprintf(one, sizeof one, "%s%s level unknown", buf[0] ? ", " : "", names[c[i].kind]);
        else snprintf(one, sizeof one, "%s%s %d percent", buf[0] ? ", " : "", names[c[i].kind], c[i].percent);
        MSBDAPAppend(buf, n, one);
        if (c[i].charging) MSBDAPAppend(buf, n, ", charging");
    }
}
static inline void MSBDAirPodsAXText(const MSBDAPState *st, const MSBDAPBlock *b, int nb, char *buf, size_t n) {
    if (n) buf[0] = 0;
    for (int i = 0; i < nb; i++) {
        char one[256];
        if (i) MSBDAPAppend(buf, n, ". ");
        MSBDAPAppend(buf, n, MSBDAirPodsBlockName(st, &b[i]));
        if (!b[i].connected) { MSBDAPAppend(buf, n, ", not connected"); continue; }
        if (MSBDAirPodsHasBud(b[i].cells, b[i].ncells)) { MSBDAirPodsCellsAXText(b[i].cells, b[i].ncells, one, sizeof one); MSBDAPAppend(buf, n, ", "); MSBDAPAppend(buf, n, one); continue; }
        if (b[i].level < 0 || b[i].level > 100) MSBDAPAppend(buf, n, ", level unknown");
        else { snprintf(one, sizeof one, ", %d percent", b[i].level); MSBDAPAppend(buf, n, one); }
        if (b[i].ncells) { MSBDAirPodsCellsAXText(b[i].cells, b[i].ncells, one, sizeof one); MSBDAPAppend(buf, n, ", "); MSBDAPAppend(buf, n, one); }
    }
}
