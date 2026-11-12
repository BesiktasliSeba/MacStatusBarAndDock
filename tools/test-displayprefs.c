// test-displayprefs.c -- Mac test of the per-display settings' rule (common/DisplayPrefs.h; plans/design-1.8.7-displays.md sections 2-3): where a
// display's value comes from, the override's type, the display default (Show Trash in Dock ON), flat keys and their 127-character limit (the crash
// guard's sscanf width), the display key from the S1 readings (A12Z 18.5 + Samsung 4K TV: three UIScreens, one hardwareIdentifier; the iPad has
// none; the iPad 2's TV by its CADisplay uniqueId), placeholders and bad characters as no id, and upper case.
// Run: tools/test-displayprefs.sh (which also builds copies of the rule with one thing broken: each must fail this test).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "../common/DisplayPrefs.h"

static int fails = 0;
static void Expect(const char *what, long got, long want) {
    printf("%s  %-100s got %ld, want %ld\n", got == want ? "PASS" : "FAIL", what, got, want);
    if (got != want) fails++;
}
static void ExpectStr(const char *what, const char *got, const char *want) {
    int ok = got && want && strcmp(got, want) == 0;
    printf("%s  %-100s got \"%s\", want \"%s\"\n", ok ? "PASS" : "FAIL", what, got ? got : "(null)", want ? want : "(null)");
    if (!ok) fails++;
}
#define A12Z_TV "4C2D0372-0000-0000-0120-0103808E5078"
#define IPAD2_TV "14803875-6ED1-428A-B223-8B1C4562A66C"

int main(void) {
    // ---- the rule: isMain, layerOn, hasOverride, typeOK, rowHasDisplayDefault -------------------------------------------------------------------
    int bad = 0;
    for (int l = 0; l < 2; l++) for (int o = 0; o < 2; o++) for (int t = 0; t < 2; t++) for (int d = 0; d < 2; d++)
        bad += MSBDDispResolve(1, l, o, t, d) != kMSBDDispFromIPad;
    Expect("the iPad's own screen takes the iPad's value whatever is stored (16 cases)", bad, 0);
    Expect("a display, layer on, an override of the right type: the override", MSBDDispResolve(0, 1, 1, 1, 0), kMSBDDispFromOverride);
    Expect("  ... also on a row with a display default (Show Trash set off for the TV sticks)", MSBDDispResolve(0, 1, 1, 1, 1), kMSBDDispFromOverride);
    Expect("a display, no override: the iPad's value (the same as the iPad until changed)", MSBDDispResolve(0, 1, 0, 0, 0), kMSBDDispFromIPad);
    Expect("a display, no override, a row with a display default: the display default (the TV's Trash ON)", MSBDDispResolve(0, 1, 0, 0, 1), kMSBDDispFromDefault);
    Expect("an override of the wrong type counts as absent: the iPad's value", MSBDDispResolve(0, 1, 1, 0, 0), kMSBDDispFromIPad);
    Expect("  ... or the display default where the row has one", MSBDDispResolve(0, 1, 1, 0, 1), kMSBDDispFromDefault);
    Expect("the layer switched off: an override is dormant, the iPad's value", MSBDDispResolve(0, 0, 1, 1, 0), kMSBDDispFromIPad);
    Expect("  ... and the display default stands (the TV's Trash ON, as 1.8.6)", MSBDDispResolve(0, 0, 1, 1, 1), kMSBDDispFromDefault);
    Expect("  ... with no override too", MSBDDispResolve(0, 0, 0, 0, 1), kMSBDDispFromDefault);
    Expect("  ... and no row default: the iPad's", MSBDDispResolve(0, 0, 0, 0, 0), kMSBDDispFromIPad);

    // ---- the display defaults: only Show Trash in Dock, ON ----------------------------------------------------------------------------------------
    int v = -1;
    Expect("Show Trash in Dock (dock) has a display default", MSBDDispDisplayDefault("dock", "showTrash", &v), 1);
    Expect("  ... and it is ON", v, 1);
    Expect("Dock auto-hide has none (follows the iPad until changed)", MSBDDispDisplayDefault("dock", "autoHideDock", NULL), 0);
    Expect("Menu Bar Size has none", MSBDDispDisplayDefault("msb", "menuBarSize", NULL), 0);
    Expect("showTrash in another part is not that row", MSBDDispDisplayDefault("msb", "showTrash", NULL), 0);

    // ---- the override's type ----------------------------------------------------------------------------------------------------------------------
    Expect("a switch takes a boolean", MSBDDispTypeOK(kMSBDDispWantBool, kMSBDDispVBool, 0, 0, 0, 0), 1);
    Expect("  ... or the number 1 / 0 (defaults write -int)", MSBDDispTypeOK(kMSBDDispWantBool, kMSBDDispVNumber, 1, 0, 0, 0) && MSBDDispTypeOK(kMSBDDispWantBool, kMSBDDispVNumber, 0, 0, 0, 0), 1);
    Expect("  ... not the number 2 (never clamped)", MSBDDispTypeOK(kMSBDDispWantBool, kMSBDDispVNumber, 2, 0, 0, 0), 0);
    Expect("  ... not a text", MSBDDispTypeOK(kMSBDDispWantBool, kMSBDDispVOther, 0, 0, 0, 0), 0);
    Expect("  ... nothing stored is no override", MSBDDispTypeOK(kMSBDDispWantBool, kMSBDDispVNone, 0, 0, 0, 0), 0);
    Expect("a number takes a number in its range (Dock size 48 in 16-128)", MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, 48, 1, 16, 128), 1);
    Expect("  ... its ends too", MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, 16, 1, 16, 128) && MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, 128, 1, 16, 128), 1);
    Expect("  ... out of range counts as absent, never clamped (200)", MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, 200, 1, 16, 128), 0);
    Expect("  ... below range (-1)", MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, -1, 1, 16, 128), 0);
    Expect("  ... not a NaN or an infinity", MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, NAN, 0, 0, 0) || MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, INFINITY, 0, 0, 0), 0);
    Expect("  ... not a boolean", MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVBool, 1, 0, 0, 0), 0);
    Expect("  ... any number when the row has no range", MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, 1e6, 0, 0, 0), 1);
    Expect("a value row takes any plist value (Mac Deck's layouts)", MSBDDispTypeOK(kMSBDDispWantValue, kMSBDDispVOther, 0, 0, 0, 0) && MSBDDispTypeOK(kMSBDDispWantValue, kMSBDDispVBool, 0, 0, 0, 0), 1);
    Expect("  ... but nothing stored is still none", MSBDDispTypeOK(kMSBDDispWantValue, kMSBDDispVNone, 0, 0, 0, 0), 0);

    // ---- the display key from the readings (S1) ----------------------------------------------------------------------------------------------------
    char k1[96], k2[96], k3[96], k[96];
    Expect("A12Z: the TV's AirPlay[2-3] screen has its own key", MSBDDispKeyFrom(0, A12Z_TV, A12Z_TV, k1, sizeof k1), kMSBDDispKeyId);
    ExpectStr("  ... u-<hardwareIdentifier>", k1, "u-" A12Z_TV);
    MSBDDispKeyFrom(0, A12Z_TV, A12Z_TV, k2, sizeof k2);   // (its shell UI screen, 2560 x 1440 @2 on 5120 x 2880)
    MSBDDispKeyFrom(0, A12Z_TV, A12Z_TV, k3, sizeof k3);   // (its noninteractive screen, 3840 x 2160 @1)
    Expect("  ... the same key from all three of the TV's screens", !strcmp(k1, k2) && !strcmp(k2, k3), 1);
    Expect("  ... from the hardwareIdentifier alone (any process, no CADisplay match)", MSBDDispKeyFrom(0, A12Z_TV, NULL, k, sizeof k) == kMSBDDispKeyId && !strcmp(k, k1), 1);
    Expect("A12Z: the iPad's screen (no hardwareIdentifier, CADisplay uniqueId nil) has no key", MSBDDispKeyFrom(1, NULL, NULL, k, sizeof k), kMSBDDispKeyMain);
    ExpectStr("  ... and writes none", k, "");
    Expect("  ... the iPad's screen has no key even if an id were read", MSBDDispKeyFrom(1, A12Z_TV, A12Z_TV, k, sizeof k) == kMSBDDispKeyMain && !k[0], 1);
    Expect("iPad 2 16.7.7: the TV by the CADisplay uniqueId when the configuration has no hardwareIdentifier", MSBDDispKeyFrom(0, NULL, IPAD2_TV, k, sizeof k), kMSBDDispKeyId);
    ExpectStr("  ... u-<uniqueId>", k, "u-" IPAD2_TV);
    Expect("the hardwareIdentifier comes first when both are there and differ", MSBDDispKeyFrom(0, A12Z_TV, IPAD2_TV, k, sizeof k) == kMSBDDispKeyId && !strcmp(k, "u-" A12Z_TV), 1);
    MSBDDispKeyFrom(0, "4c2d0372-0000-0000-0120-0103808e5078", NULL, k, sizeof k);
    ExpectStr("a lower-case id gives the upper-case key (one display, one key)", k, "u-" A12Z_TV);
    const char *none[] = { "", "(null)", "(nil)", "<none>", "null", "NULL", "nil", "none", "unknown", "00000000-0000-0000-0000-000000000000", "AB CD", "AB/CD", "AB\tCD", "\xc3\xa9t\xc3\xa9" };
    int anyBad = 0;
    for (size_t i = 0; i < sizeof(none) / sizeof(none[0]); i++) {
        int r = MSBDDispKeyFrom(0, none[i], NULL, k, sizeof k);
        if (r != kMSBDDispKeyAny || strcmp(k, "any")) { anyBad++; printf("      no id read as an id: \"%s\" -> %s\n", none[i], k); }
    }
    Expect("an empty id, a placeholder ((null), nil, none, all zeros) or bad characters (space, '/', tab, non-ASCII) is no id: \"any\"", anyBad, 0);
    Expect("nothing readable at all (non-strings read as none): \"any\"", MSBDDispKeyFrom(0, NULL, NULL, k, sizeof k) == kMSBDDispKeyAny && !strcmp(k, "any"), 1);
    Expect("a placeholder hardwareIdentifier with a usable CADisplay uniqueId: the uniqueId", MSBDDispKeyFrom(0, "(null)", IPAD2_TV, k, sizeof k) == kMSBDDispKeyId && !strcmp(k, "u-" IPAD2_TV), 1);
    char id64[65], id65[66];
    memset(id64, 'A', 64); id64[64] = 0; memset(id65, 'A', 65); id65[65] = 0;
    Expect("a 64-character id is one", MSBDDispKeyFrom(0, id64, NULL, k, sizeof k), kMSBDDispKeyId);
    Expect("a 65-character id is not (any)", MSBDDispKeyFrom(0, id65, NULL, k, sizeof k), kMSBDDispKeyAny);
    Expect("the key valid as stored: u-<upper id> and any", MSBDDispKeyValid("u-" A12Z_TV) && MSBDDispKeyValid("any"), 1);
    Expect("  ... not lower case, a bare u-, a placeholder or another word", MSBDDispKeyValid("u-4c2d") || MSBDDispKeyValid("u-") || MSBDDispKeyValid("u-(NULL)") || MSBDDispKeyValid("main") || MSBDDispKeyValid(NULL), 0);

    // ---- flat keys ----------------------------------------------------------------------------------------------------------------------------------
    char f[160];
    Expect("a flat key: <display>/<part>/<key>", (long)MSBDDispFlatKey(f, sizeof f, "u-" A12Z_TV, "dock", "autoHideDock"), (long)strlen("u-" A12Z_TV "/dock/autoHideDock"));
    ExpectStr("  ... spelled so", f, "u-" A12Z_TV "/dock/autoHideDock");
    Expect("  ... for any display", MSBDDispFlatKey(f, sizeof f, "any", "msb", "menuBarSize") > 0 && !strcmp(f, "any/msb/menuBarSize"), 1);
    Expect("  ... the display-only part (disp)", MSBDDispFlatKey(f, sizeof f, "any", "disp", "dimIPad") > 0, 1);
    char d64[80], key55[60], key56[60];
    snprintf(d64, sizeof d64, "u-%s", id64);
    memset(key55, 'k', 55); key55[55] = 0; memset(key56, 'k', 56); key56[56] = 0;
    Expect("127 characters is the longest flat key (the guard's sscanf %127s)", (long)MSBDDispFlatKey(f, sizeof f, d64, "dock", key55), 127);
    Expect("  ... 128 is refused (it would be cut and another key switched off)", (long)MSBDDispFlatKey(f, sizeof f, d64, "dock", key56), 0);
    Expect("  ... and leaves nothing behind", f[0], 0);
    Expect("  ... a buffer too small is refused, not cut", (long)MSBDDispFlatKey(f, 20, "u-" A12Z_TV, "dock", "autoHideDock"), 0);
    Expect("refused: an unknown part", (long)MSBDDispFlatKey(f, sizeof f, "any", "springboard", "x"), 0);
    Expect("refused: a key with '/', a space, a newline or nothing", (long)(MSBDDispFlatKey(f, sizeof f, "any", "msb", "a/b") + MSBDDispFlatKey(f, sizeof f, "any", "msb", "a b") + MSBDDispFlatKey(f, sizeof f, "any", "msb", "a\nb") + MSBDDispFlatKey(f, sizeof f, "any", "msb", "")), 0);
    Expect("refused: a display key not as stored (lower case, the iPad, none)", (long)(MSBDDispFlatKey(f, sizeof f, "u-4c2d", "msb", "x") + MSBDDispFlatKey(f, sizeof f, "main", "msb", "x") + MSBDDispFlatKey(f, sizeof f, NULL, "msb", "x")), 0);
    char dd[128], pp[128], kk[128];
    Expect("a flat key taken apart", MSBDDispFlatSplit("u-" A12Z_TV "/msb/windowSize", dd, sizeof dd, pp, sizeof pp, kk, sizeof kk), 1);
    Expect("  ... display, part, key", !strcmp(dd, "u-" A12Z_TV) && !strcmp(pp, "msb") && !strcmp(kk, "windowSize"), 1);
    Expect("the registry's own keys are no overrides (<display>/info, connected, displaySettings)",
           MSBDDispFlatSplit("u-" A12Z_TV "/info", NULL, 0, NULL, 0, NULL, 0) || MSBDDispFlatSplit("connected", NULL, 0, NULL, 0, NULL, 0) || MSBDDispFlatSplit(MSBD_DISP_MASTER_KEY, NULL, 0, NULL, 0, NULL, 0), 0);
    Expect("*/msb/macBanners: this display's, any display's", MSBDDispFlatIs("u-" A12Z_TV "/msb/macBanners", "msb", "macBanners") && MSBDDispFlatIs("any/msb/macBanners", "msb", "macBanners"), 1);
    Expect("  ... not the same key in another part, not another key, not a longer key", MSBDDispFlatIs("u-" A12Z_TV "/dock/macBanners", "msb", "macBanners") || MSBDDispFlatIs("any/msb/autoHideStatusBar", "msb", "macBanners") || MSBDDispFlatIs("any/msb/macBannersX", "msb", "macBanners"), 0);
    Expect("  ... not a key with a fourth part", MSBDDispFlatIs("any/msb/macBanners/x", "msb", "macBanners"), 0);
    Expect("KT's domains are the parts msb and dock", !strcmp(MSBDDispPartOfDomain("com.besiktasliseba.macstatusbar") ?: "", "msb") && !strcmp(MSBDDispPartOfDomain("com.besiktasliseba.dockmagnification") ?: "", "dock"), 1);
    Expect("  ... no other domain has a part (the displays domain itself, Force Quit's, another's)", MSBDDispPartOfDomain(MSBD_DISP_DOMAIN) || MSBDDispPartOfDomain("com.besiktasliseba.forcequitmenu") || MSBDDispPartOfDomain(NULL), 0);
    ExpectStr("the domain and its notification", MSBD_DISP_NOTIFY, "com.besiktasliseba.macstatusbar.displays/prefsChanged");

    // ---- the registry: at most 8 displays remembered, the one seen longest ago and not connected forgotten (commit 3) ---------------------------
    MSBDDispSeen eight[8], nine[9];
    char names[9][16];
    for (int i = 0; i < 9; i++) { snprintf(names[i], sizeof names[i], "u-D%d", i); nine[i].key = names[i]; nine[i].lastSeen = 1000 + 10 * i; nine[i].connected = 0; nine[i].hasOwn = 0; }
    memcpy(eight, nine, sizeof eight);
    Expect("8 displays remembered: none forgotten", MSBDDispForgetPick(eight, 8, MSBD_DISP_REMEMBER_MAX), -1);
    nine[8].lastSeen = 5000; nine[8].connected = 1;   // (the 9th, connected now)
    Expect("a 9th connects: the one seen longest ago goes (D0)", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 0);
    nine[3].lastSeen = 1;
    Expect("  ... by when it was last seen, not by its place in the list (D3)", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 3);
    nine[3].connected = 1;
    Expect("  ... never one connected now (D0 instead of the connected D3)", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 0);
    nine[3].connected = 0; nine[3].lastSeen = 1000;
    Expect("  ... the first in the list when two were seen as long ago", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 0);
    for (int i = 0; i < 9; i++) nine[i].connected = 1;
    Expect("  ... none when every one is connected", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), -1);
    for (int i = 0; i < 9; i++) { nine[i].connected = 0; nine[i].lastSeen = 1000 + 10 * i; }
    nine[8].connected = 1; nine[8].lastSeen = 5000;
    int n = 9, gone = 0, kept8 = 1;
    for (int p; (p = MSBDDispForgetPick(nine, n, MSBD_DISP_REMEMBER_MAX)) >= 0; n--) { gone++; memmove(&nine[p], &nine[p + 1], sizeof(nine[0]) * (size_t)(n - p - 1)); }
    for (int i = 0; i < n; i++) if (!strcmp(nine[i].key, "u-D0")) kept8 = 0;
    Expect("forgetting until 8 are left: one display forgotten, D0, the new one kept", gone == 1 && n == 8 && kept8 && !strcmp(nine[7].key, "u-D8"), 1);
    // (review of 1.8.7: a display with something of the user's own -- a setting of its own, a More Space record, Mac Switcher desktops of its own --
    //  goes only when every one not connected has something; over the Lightning AV adapter each replug is a new id, so the TV the user set up was
    //  the oldest after 8 replugs and went with its settings and desktops while 7 plain copies of it stayed)
    #define RESET9() for (int i = 0; i < 9; i++) { nine[i].key = names[i]; nine[i].lastSeen = 1000 + 10 * i; nine[i].connected = 0; nine[i].hasOwn = 0; } nine[8].connected = 1; nine[8].lastSeen = 5000
    RESET9();
    nine[0].hasOwn = 1;   // (the customized TV, seen longest ago; D1-D7 plain copies, D8 the one connected now)
    Expect("1 customized (seen longest ago) and 8 plain: a plain one goes (D1), not the customized D0", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 1);
    nine[1].hasOwn = 1; nine[2].hasOwn = 1;
    Expect("  ... the plain one seen longest ago of the plain ones (D3), the customized D0-D2 kept", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 3);
    RESET9();
    for (int i = 0; i < 9; i++) nine[i].hasOwn = 1;
    Expect("9 customized: the one seen longest ago goes (D0)", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 0);
    nine[0].connected = 1;
    Expect("  ... never one connected now (D1 instead of the connected D0)", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 1);
    RESET9();
    for (int i = 0; i < 8; i++) nine[i].hasOwn = 1;
    nine[8].hasOwn = 0;   // (the only plain one is connected: not a candidate)
    Expect("  ... the only plain one connected: the customized one seen longest ago goes (D0)", MSBDDispForgetPick(nine, 9, MSBD_DISP_REMEMBER_MAX), 0);
    RESET9();
    nine[0].hasOwn = 1;
    n = 9; gone = 0; kept8 = 1;
    int keptOwn = 0;
    for (int p; (p = MSBDDispForgetPick(nine, n, MSBD_DISP_REMEMBER_MAX)) >= 0; n--) { gone++; memmove(&nine[p], &nine[p + 1], sizeof(nine[0]) * (size_t)(n - p - 1)); }
    for (int i = 0; i < n; i++) { if (!strcmp(nine[i].key, "u-D1")) kept8 = 0; if (!strcmp(nine[i].key, "u-D0")) keptOwn = 1; }
    Expect("forgetting until 8 are left with the customized D0 seen longest ago: one forgotten, the plain D1; D0 and the connected D8 kept", gone == 1 && n == 8 && kept8 && keptOwn && !strcmp(nine[7].key, "u-D8"), 1);
    // (7 more replugs, each a new id seen later: the customized D0 stays through all of them, only plain copies go)
    for (int r = 0; r < 7; r++) {
        static char more[7][16];
        snprintf(more[r], sizeof more[r], "u-R%d", r);
        nine[n - 1].connected = 0;   // (the TV unplugged: seen until now)
        nine[n].key = more[r]; nine[n].lastSeen = 6000 + 10 * r; nine[n].connected = 1; nine[n].hasOwn = 0; n++;
        int p = MSBDDispForgetPick(nine, n, MSBD_DISP_REMEMBER_MAX);
        if (p < 0 || nine[p].hasOwn) { keptOwn = 0; break; }
        memmove(&nine[p], &nine[p + 1], sizeof(nine[0]) * (size_t)(n - p - 1)); n--;
    }
    keptOwn = keptOwn && !strcmp(nine[0].key, "u-D0") && n == 8;
    Expect("  ... and through 7 more replugs (each a new id): only plain copies forgotten, D0 kept", keptOwn, 1);
    #undef RESET9
    Expect("the limit is 8", MSBD_DISP_REMEMBER_MAX, 8);
    // ---- the route, from the matched CADisplay's deviceName only (S1: the wired TV is external-0; FBS calls it AirPlay[2-3]) ------------------------
    ExpectStr("external-0 (USB-C HDMI, the A12Z's TV): direct", MSBDDispRouteOf("external-0") ?: "(none)", "direct");
    ExpectStr("wireless0 (AirPlay, and the iPad 2's Lightning Digital AV Adapter): encoded", MSBDDispRouteOf("wireless0") ?: "(none)", "encoded");
    Expect("the iPad's panel (primary), an FBS name (AirPlay[2-3]), a bare external- or nothing: no route written",
           MSBDDispRouteOf("primary") || MSBDDispRouteOf("AirPlay[2-3]") || MSBDDispRouteOf("external-") || MSBDDispRouteOf(NULL), 0);

    // ---- the crash guard's note of a switch turned on for a display (commit 4): the guard's own RecentlyOn format -----------------------------------
    const char *R = getenv("RECENT");
    if (!R) { printf("FAIL  RECENT not set (run tools/test-displayprefs.sh)\n"); return 1; }
    long now = 1800000000;
    unlink(R);
    FILE *rf = fopen(R, "w");   // (Settings' own lines for the iPad's switches: one 5 min old, one 11 min old)
    fprintf(rf, "%ld com.besiktasliseba.dockmagnification autoHideDock Automatically Hide and Show the Dock\n%ld com.besiktasliseba.macstatusbar macSwitcher Mac Switcher\n", now - 300, now - 660);
    fclose(rf);
    char fl[160], fl2[160], line[600], dom[128], key[128];
    MSBDDispFlatKey(fl, sizeof fl, "u-" A12Z_TV, "dock", "autoHideDock");
    MSBDDispFlatKey(fl2, sizeof fl2, "any", "msb", "autoHideStatusBar");
    Expect("a switch turned on for the TV: noted", MSBDDispNoteRecent(R, now, fl, "Automatically Hide and Show the Dock", 1), 1);
    int lines = 0, mine = 0, ipad = 0, old = 0; long at = 0; char title[200] = "";
    #define READR() do { lines = mine = ipad = old = 0; FILE *g = fopen(R, "r"); while (g && fgets(line, sizeof line, g)) { int o = 0; lines++; \
        if (sscanf(line, "%ld %127s %127s %n", &at, dom, key, &o) >= 3) { if (!strcmp(dom, MSBD_DISP_DOMAIN) && !strcmp(key, fl)) { mine++; snprintf(title, sizeof title, "%s", line + o); title[strcspn(title, "\n")] = 0; } \
        if (!strcmp(dom, "com.besiktasliseba.dockmagnification")) ipad++; if (!strcmp(dom, "com.besiktasliseba.macstatusbar")) old++; } } if (g) fclose(g); } while (0)
    READR();
    Expect("  ... one line in the guard's format: <time> <the displays domain> <its flat key> <row title>", mine == 1 && at == now, 1);
    ExpectStr("  ... with the row's title", title, "Automatically Hide and Show the Dock");
    Expect("  ... Settings' line for the iPad's switch from 5 min ago kept", ipad, 1);
    Expect("  ... a line older than 10 min gone", old, 0);
    MSBDDispNoteRecent(R, now + 30, fl, "Automatically Hide and Show the Dock", 1);
    READR();
    Expect("turned on again: still one line for it, at the new time", mine == 1 && at == now + 30, 1);
    MSBDDispNoteRecent(R, now + 40, fl2, "Automatically Hide and Show the Menu Bar", 1);
    READR();
    Expect("another display's switch: a line of its own (3 in all)", lines, 3);
    Expect("turned off: its line goes", MSBDDispNoteRecent(R, now + 50, fl, "x", 0), 1);
    READR();
    Expect("  ... the others stay", mine == 0 && lines == 2, 1);
    char k127[160], k128[160], d64b[80], kk55[60], kk56[60];
    snprintf(d64b, sizeof d64b, "u-%s", id64); memset(kk55, 'k', 55); kk55[55] = 0; memset(kk56, 'k', 56); kk56[56] = 0;
    MSBDDispFlatKey(k127, sizeof k127, d64b, "dock", kk55);
    snprintf(k128, sizeof k128, "%s/dock/%s", d64b, kk56);
    Expect("a 127-character flat key is noted", MSBDDispNoteRecent(R, now + 60, k127, "Long", 1), 1);
    Expect("a 128-character one is refused (the guard would read a cut key and set another)", MSBDDispNoteRecent(R, now + 60, k128, "Longer", 1), 0);
    Expect("a key of the registry (<display>/info) is refused", MSBDDispNoteRecent(R, now + 60, "u-" A12Z_TV "/info", "x", 1), 0);
    READR();
    Expect("  ... the list as before those two (3 lines)", lines, 3);
    MSBDDispNoteRecent(R, now + 70, fl, "Two\nLines\tand a tab", 1);
    READR();
    ExpectStr("a title on one line (a newline and a tab become spaces)", title, "Two Lines and a tab");
    char longTitle[200]; memset(longTitle, 'x', 79); strcpy(longTitle + 79, "\xc3\xa9t\xc3\xa9 and more");   // (79 bytes, then a 2-byte character)
    MSBDDispNoteRecent(R, now + 80, fl, longTitle, 1);
    READR();
    Expect("a long title: at most 80 bytes, never inside a character (79 here)", (long)strlen(title), 79);
    memset(longTitle, 'y', 120); longTitle[120] = 0;
    MSBDDispNoteRecent(R, now + 90, fl, longTitle, 1);
    READR();
    Expect("  ... 80 bytes of a plain one", (long)strlen(title), 80);
    MSBDDispNoteRecent(R, now + 100, fl, "", 1);
    READR();
    Expect("no title: the line still reads (time, domain, key)", mine, 1);
    MSBDDispNoteRecent(R, now + 9999, fl, "x", 0);
    Expect("the last line gone: no list left", access(R, F_OK), -1);

    printf(fails ? "SOME FAILED (%d)\n" : "ALL PASSED\n", fails);
    return fails ? 1 : 0;
}
