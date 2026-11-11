// test-customshortcuts.c -- Mac test of Custom Shortcuts' rules (1.8.5 item 2, common/CustomShortcutsRule.h): which keys may be a shortcut (a
// modifier needed, this tweak's own keys refused, Globe part of the match, Caps Lock not), the actions run (KeyPilot's spelling, no shell), the
// window layouts by KeyPilot's names and aliases, each one the window API's; and (1.8.6) the match in the app with the keyboard: a rule packed into
// its Darwin state and back for all 64 slots, the count and generation, the wanted rule, the match (Caps Lock and the keypad bit left out, Globe
// in), and the key-down, its repeats and its key-up kept from the app as a pair; a shortcut key whose key-up went elsewhere is no repeat of a plain
// press of it, and is forgotten when the app loses the keyboard (review 1.8.6, L). 1.8.6 i05: what SpringBoard publishes is always what it means,
// a list one shorter and the switch off included (the last rule turned off kept its keys from every app), and the app keeps a key only when
// SpringBoard will run it (the apps' wanted state carries SpringBoard's keyboard: with none, every key goes to the app). Review 1.8.6: SpringBoard's
// run gate drops only what no hand presses (MSBDCSRunOnceNow, MSBDCSFromAppTake): a second press of a shortcut, or another one, at a press's pace
// runs, each key the app keeps; a held key, a key come two ways, and a flood of forged posts are still bounded.
#include <stdio.h>
#include "../common/CustomShortcutsRule.h"
#include "../statusbar/WindowAPIRule.h"
static int fails = 0;
#define T(name, cond) do { if (cond) printf("PASS  %s\n", name); else { printf("FAIL  %s\n", name); fails++; } } while (0)
#define CMD kMSBDModCommand
#define CTL kMSBDModControl
#define OPT kMSBDModOption
#define SHF kMSBDModShift
#define GLB kMSBDModGlobe
#define CAPS (1ULL << 16)
#define KPAD (1ULL << 21)
static int asked = 0, answer = 1, redirect = -1;
static int Confirm(long usage, unsigned long long flags, int rule) { asked++; if (!answer) return -1; return redirect >= 0 ? redirect : rule; }
// SpringBoard's publish (statusbar/CustomShortcuts.h DMCSPublishStates, the same steps) on a stand-in for the Darwin states, and the app's read.
static uint64_t gStore[kMSBDCSMaxRules], gStoreRS, gWrote;
static unsigned gLastCount;
static bool gPublished;
static uint64_t StoreSlot(unsigned i, void *ctx) { (void)ctx; return gStore[i]; }
static int Publish(const uint64_t *rules, unsigned n) {   // (1: written and posted; 0: the live states were already what is meant)
    uint64_t packed[kMSBDCSMaxRules] = {0};
    for (unsigned i = 0; i < n; i++) packed[i] = rules[i];
    if (MSBDCSPublishedSame(gPublished, gStoreRS, gWrote, n, packed, StoreSlot, NULL)) return 0;
    unsigned w = MSBDCSSlotsToWrite(n, gLastCount, gStoreRS);
    for (unsigned i = 0; i < w; i++) gStore[i] = packed[i];
    gStoreRS = MSBDCSRulesNext(gStoreRS, n);
    gWrote = gStoreRS; gLastCount = n; gPublished = true;
    return 1;
}
static unsigned AppRead(uint64_t *out) {   // (appbridge/AppBridge.x MABCSRead: the count, then the slots below it)
    unsigned n = MSBDCSRulesCount(gStoreRS);
    for (unsigned i = 0; i < kMSBDCSMaxRules; i++) out[i] = i < n ? gStore[i] : 0;
    return n;
}
static int SameAsMeant(const uint64_t *rules, unsigned n) {   // (what the app reads is the rules meant, and every slot past them 0)
    uint64_t a[kMSBDCSMaxRules]; if (AppRead(a) != n) return 0;
    for (unsigned i = 0; i < kMSBDCSMaxRules; i++) if (a[i] != (i < n ? rules[i] : 0) || gStore[i] != (i < n ? rules[i] : 0)) return 0;
    return 1;
}
static uint64_t gWantedState;   // (the apps' wanted state as SpringBoard published it: MSBDCSAppsWanted)
static int ConfirmWanted(long usage, unsigned long long flags, int rule) { return gWantedState == 1 ? rule : -1; }   // (MABCSConfirm's wanted part)
// SpringBoard's run gate (statusbar/CustomShortcuts.h, the same steps): DMCSRunOnce by the way a key came, DMCSRunFromApp the bucket first.
static MSBDCSRunOnceState gOnce;
static MSBDCSFromAppBucket gBucket;
static int gRan[kMSBDCSMaxRules], gRanAll, gKept;
static void SBReset(void) { memset(&gOnce, 0, sizeof gOnce); memset(&gBucket, 0, sizeof gBucket); memset(gRan, 0, sizeof gRan); gRanAll = 0; gKept = 0; }
static void SBArrive(unsigned i, int way, double ms) { if (i < kMSBDCSMaxRules && MSBDCSRunOnceNow(&gOnce, i, way, ms)) { gRan[i]++; gRanAll++; } }   // (DMCSRunOnce)
static void SBFromApp(unsigned i, double ms) { if (MSBDCSFromAppTake(&gBucket, ms)) SBArrive(i, kMSBDCSWayApp, ms); }                                  // (DMCSRunFromApp)
static MSBDCSKeyHeld gAppKeys;
static int AppKey(const uint64_t *rules, unsigned n, long usage, int down, unsigned long long m, double ms) {   // (the bridge's MABCSTakesKey: a run posted)
    int rr = -1, a = MSBDCSKeyAct(&gAppKeys, rules, n, usage, down, m, ms, ConfirmWanted, &rr);
    if (a == MSBDCSKeyRun) { gKept++; SBFromApp((unsigned)rr, ms); }
    return a;
}
static void AppTap(const uint64_t *rules, unsigned n, long usage, unsigned long long m, double ms) { AppKey(rules, n, usage, 1, m, ms); AppKey(rules, n, usage, 0, m, ms + 70); }
int main(void) {
    T("Command-K is a shortcut", MSBDCSCheck(0x0E, "k", CMD) == kMSBDCSOK);
    T("Option-Control-1, Globe-Option-Space are shortcuts", MSBDCSCheck(0x1E, "1", OPT | CTL) == kMSBDCSOK && MSBDCSCheck(kMSBDCSHIDSpace, " ", GLB | OPT) == kMSBDCSOK);
    T("K alone, Shift-K: typing, refused", MSBDCSCheck(0x0E, "k", 0) == kMSBDCSNeedsModifier && MSBDCSCheck(0x0E, "k", SHF) == kMSBDCSNeedsModifier);
    T("Tab alone, the top-left key alone: typing (our Tab mute, our Escape key), refused", MSBDCSCheck(kMSBDCSHIDTab, "\t", 0) == kMSBDCSNeedsModifier && MSBDCSCheck(0x35, "`", 0) == kMSBDCSNeedsModifier);
    T("Shift-= (our screen brightness) refused: Shift alone is typing", MSBDCSCheck(0x2E, "=", SHF) == kMSBDCSNeedsModifier);
    T("a modifier key on its own is no key yet; the Globe key on its own neither (usage 3 with the Globe flag, as it reaches an app)", MSBDCSCheck(0xE3, "", CMD) == kMSBDCSNoKey && MSBDCSCheck(0xE0, "", CTL) == kMSBDCSNoKey
      && MSBDCSCheck(0x03, "", GLB) == kMSBDCSNoKey && MSBDCSCheck(0x03, "", GLB | CTL) == kMSBDCSNoKey);
    T("Escape, with any modifier, refused (it stops the recording)", MSBDCSCheck(kMSBDCSHIDEscape, "\x1b", CMD) == kMSBDCSEscape);
    T("Window Tiling Shortcuts refused: Globe-Control-Left, -F (by the letter typed), -Shift-Up, -Option-Shift-Down", MSBDCSCheck(kMSBDCSHIDLeft, "", GLB | CTL) == kMSBDCSWindowTiling
      && MSBDCSCheck(0x09, "f", GLB | CTL) == kMSBDCSWindowTiling && MSBDCSCheck(kMSBDCSHIDUp, "", GLB | CTL | SHF) == kMSBDCSWindowTiling
      && MSBDCSCheck(kMSBDCSHIDDown, "", GLB | CTL | OPT | SHF) == kMSBDCSWindowTiling);
    T("  ... on another layout, Globe-Control and the key that types F is the tiling key (AZERTY's F is where QWERTY's F is; Dvorak's U types u: not ours)", MSBDCSCheck(0x18, "f", GLB | CTL) == kMSBDCSWindowTiling && MSBDCSCheck(0x09, "u", GLB | CTL) == kMSBDCSOK);
    T("  ... Globe-Control-Option-Left (no Shift) is not one of them", MSBDCSCheck(kMSBDCSHIDLeft, "", GLB | CTL | OPT) == kMSBDCSOK);
    T("the Mac Switcher's Control-Left / -Right / -Up refused; Control-Down is free", MSBDCSCheck(kMSBDCSHIDLeft, "", CTL) == kMSBDCSMacSwitcher && MSBDCSCheck(kMSBDCSHIDRight, "", CTL) == kMSBDCSMacSwitcher
      && MSBDCSCheck(kMSBDCSHIDUp, "", CTL) == kMSBDCSMacSwitcher && MSBDCSCheck(kMSBDCSHIDDown, "", CTL) == kMSBDCSOK);
    T("Globe is part of the match (KeyPilot's mask dropped it): Control-K and Globe-Control-K are two shortcuts", !MSBDCSSame(0x0E, CTL, 0x0E, GLB | CTL) && MSBDCSSame(0x0E, CTL, 0x0E, CTL));
    T("Caps Lock is not: a shortcut still matches with Caps Lock on", MSBDCSSame(0x0E, CMD, 0x0E, CMD | CAPS) && MSBDCSMods(CMD | CAPS) == CMD);
    T("actions: app:, open:, url: with a scheme, window:, system:home", MSBDCSActionKind("app:com.apple.calculator") == kMSBDCSActApp && MSBDCSActionKind("open:com.apple.calculator") == kMSBDCSActApp
      && MSBDCSActionKind("url:https://www.apple.com") == kMSBDCSActURL && MSBDCSActionKind("url:prefs:root=General") == kMSBDCSActURL
      && MSBDCSActionKind("window:left-half") == kMSBDCSActWindow && MSBDCSActionKind("system:home") == kMSBDCSActHome && MSBDCSActionKind("  SYSTEM:HOME") == kMSBDCSActHome);
    T("  ... none: an empty app, a URL without a scheme, an unknown layout, a bare word (KeyPilot's app guess)", MSBDCSActionKind("app:") == kMSBDCSActNone && MSBDCSActionKind("url:apple.com") == kMSBDCSActNone
      && MSBDCSActionKind("window:sideways") == kMSBDCSActNone && MSBDCSActionKind("com.apple.calculator") == kMSBDCSActNone && MSBDCSActionKind(NULL) == kMSBDCSActNone);
    T("  ... shell: and sh: are shell actions, never run", MSBDCSActionKind("shell:killall SpringBoard") == kMSBDCSActShell && MSBDCSActionKind("sh: ls") == kMSBDCSActShell);
    T("values: the bundle ID, the URL, the layout in the window API's spelling", !strcmp(MSBDCSActionValue("app: com.apple.calculator"), "com.apple.calculator")
      && !strcmp(MSBDCSActionValue("url:https://www.apple.com"), "https://www.apple.com") && !strcmp(MSBDCSActionValue("window:top-left"), "topleft") && MSBDCSActionValue("system:home") == NULL);
    T("KeyPilot's layout names and aliases: left-half, Top Left, bottom_right, maximize, fill-screen, topright", !strcmp(MSBDCSLayoutName("left-half"), "left") && !strcmp(MSBDCSLayoutName("Top Left"), "topleft")
      && !strcmp(MSBDCSLayoutName("bottom_right"), "bottomright") && !strcmp(MSBDCSLayoutName("maximize"), "fill") && !strcmp(MSBDCSLayoutName("fill-screen"), "fill") && !strcmp(MSBDCSLayoutName("topright"), "topright"));
    int ok = 1;
    for (int i = 0; i < kMSBDCSLayoutCount; i++) ok &= MSBDWinAPILayoutIndex(kMSBDCSLayouts[i]) >= 0 && MSBDCSLayoutTitle(kMSBDCSLayouts[i]) != NULL && !strcmp(MSBDCSLayoutName(kMSBDCSLayouts[i]), kMSBDCSLayouts[i]);
    T("the twelve layouts offered are the window API's twelve, each with its Window menu name", ok && kMSBDCSLayoutCount == kMSBDWinAPILayoutCount);
    T("at most 64 shortcuts (KeyPilot's limit)", kMSBDCSMaxRules == 64);

    // ---- 1.8.6: the rules as the apps get them ----
    ok = 1;
    uint64_t rules[kMSBDCSMaxRules];
    const unsigned long long modSets[] = { OPT, CMD, CTL | OPT, GLB | OPT, OPT | SHF, CTL | OPT | CMD | SHF | GLB, CMD | SHF, GLB };
    for (unsigned i = 0; i < kMSBDCSMaxRules; i++) {   // (64 distinct rules: letters, digits, arrows, F-keys, keypad keys)
        long u = i < 26 ? kMSBDCSHIDA + i : i < 36 ? kMSBDCSHID1 + (i - 26) : i < 40 ? kMSBDCSHIDRight + (i - 36) : i < 52 ? 0x3A + (i - 40) : 0x54 + (i - 52);
        unsigned long long m = modSets[i % 8];
        uint64_t p = MSBDCSPack(u, m | (i & 1 ? CAPS : 0) | (i & 2 ? KPAD : 0), true);
        rules[i] = p;
        ok &= p != 0 && MSBDCSPackedUsage(p) == u && MSBDCSPackedMods(p) == m && MSBDCSPackedOn(p);
    }
    T("all 64 slots: a rule packed and read back is its key and its modifiers, on; Caps Lock and the keypad bit not kept", ok);
    ok = 1;
    for (unsigned i = 0; i < kMSBDCSMaxRules; i++) ok &= MSBDCSMatch(rules, kMSBDCSMaxRules, MSBDCSPackedUsage(rules[i]), MSBDCSPackedMods(rules[i])) == (int)i;
    T("  ... each of the 64 found again by its own keys, at its own index (the index the app posts is SpringBoard's rule)", ok);
    T("  ... no rule: usage 0, a negative usage, one past 16 bits", MSBDCSPack(0, CMD, true) == 0 && MSBDCSPack(-4, CMD, true) == 0 && MSBDCSPack(0x10000, CMD, true) == 0);
    T("  ... a rule switched off is kept but never matches", !MSBDCSPackedOn(MSBDCSPack(0x0E, CMD, false)) && MSBDCSPackedUsage(MSBDCSPack(0x0E, CMD, false)) == 0x0E);
    T("  ... a state with bits we never write (someone else's) is no rule; 0 is none", !MSBDCSPackedOn(MSBDCSPack(0x0E, CMD, true) | (1ULL << 40)) && !MSBDCSPackedOn(0)
      && !MSBDCSPackedOn(MSBDCSPack(0x0E, CMD, true) | (1ULL << 16)));
    uint64_t rs0 = MSBDCSRulesNext(0, 5), rs1 = MSBDCSRulesNext(rs0, 5);
    T("the rules' state: the count and a generation, the first publish generation 1 (never 0), each publish the next", MSBDCSRulesCount(rs0) == 5 && MSBDCSRulesGen(rs0) == 1
      && rs0 != 0 && MSBDCSRulesGen(rs1) == 2 && rs1 != rs0 && MSBDCSRulesNext(0, 0) != 0 && MSBDCSRulesCount(MSBDCSRulesNext(0, 0)) == 0);
    T("  ... the count at most 64 (a bigger number read as 64), the generation starting again at 1 at its end", MSBDCSRulesCount(MSBDCSRulesNext(0, 200)) == 64
      && MSBDCSRulesCount(0xFF) == 64 && MSBDCSRulesGen(MSBDCSRulesNext(((1ULL << 56) - 1) << 8, 3)) == 1);
    T("wanted: the switch on, KeyPilot not installed, a rule, not recording; any one missing: not wanted", MSBDCSWantedNow(true, false, 1, false)
      && !MSBDCSWantedNow(false, false, 1, false) && !MSBDCSWantedNow(true, true, 1, false) && !MSBDCSWantedNow(true, false, 0, false) && !MSBDCSWantedNow(true, false, 1, true));
    char name[96];
    snprintf(name, sizeof name, kMSBDCSRunFmt, 0u); ok = !strcmp(name, "com.besiktasliseba.customshortcuts.run.0");
    snprintf(name, sizeof name, kMSBDCSRunFmt, 63u); ok &= !strcmp(name, "com.besiktasliseba.customshortcuts.run.63");
    snprintf(name, sizeof name, kMSBDCSRuleStateFmt, 63u); ok &= !strcmp(name, "com.besiktasliseba.customshortcuts.rule.63");
    T("the names: run.0 to run.63 (one per rule), rule.0 to rule.63", ok);

    // ---- the match ----
    uint64_t r[4] = { MSBDCSPack(0x0D, OPT, true), MSBDCSPack(0x0E, OPT | CMD, true), MSBDCSPack(kMSBDCSHIDLeft, CTL | OPT, true), MSBDCSPack(0x0D, GLB | OPT, true) };
    T("Option-J (Option only: never routed to SpringBoard's key commands) is rule 0", MSBDCSMatch(r, 4, 0x0D, OPT) == 0);
    T("  ... with Caps Lock on, and with the keypad bit, still rule 0", MSBDCSMatch(r, 4, 0x0D, OPT | CAPS) == 0 && MSBDCSMatch(r, 4, 0x0D, OPT | KPAD) == 0);
    T("  ... Globe-Option-J is rule 3, not rule 0 (Globe is part of the match)", MSBDCSMatch(r, 4, 0x0D, GLB | OPT) == 3);
    T("  ... Option-Shift-J, Command-J, J, Shift-J: none", MSBDCSMatch(r, 4, 0x0D, OPT | SHF) < 0 && MSBDCSMatch(r, 4, 0x0D, CMD) < 0 && MSBDCSMatch(r, 4, 0x0D, 0) < 0
      && MSBDCSMatch(r, 4, 0x0D, SHF) < 0);
    T("Option-Command-K is rule 1, Control-Option-Left rule 2", MSBDCSMatch(r, 4, 0x0E, OPT | CMD) == 1 && MSBDCSMatch(r, 4, kMSBDCSHIDLeft, CTL | OPT) == 2);
    T("only the published count counts: rule 3 with a count of 3 is none", MSBDCSMatch(r, 3, 0x0D, GLB | OPT) < 0);
    T("plain typing is never a shortcut, even for a state that would say so (no Control, Option, Command or Globe)", MSBDCSMatch((uint64_t[]){ MSBDCSPack(0x0D, SHF, true) }, 1, 0x0D, SHF) < 0
      && !MSBDCSChord(SHF | CAPS) && MSBDCSChord(GLB));

    // ---- the key-down, its repeats and its key-up as a pair ----
    MSBDCSKeyHeld h; memset(&h, 0, sizeof h);
    int run = -2; double t = 1000.0;
    asked = 0; answer = 1; redirect = -1;
    T("Option-J down: run rule 0, kept from the app", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t, Confirm, &run) == MSBDCSKeyRun && run == 0 && asked == 1);
    T("  ... its repeats: kept, not run again, nothing asked", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 500, Confirm, &run) == MSBDCSKeyTake && run == -1
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 600, Confirm, &run) == MSBDCSKeyTake && asked == 1);
    T("  ... held 2 s with repeats every 0.1 s: still one run", ({ int k = 1; for (int i = 7; i <= 26; i++) k &= MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + i * 100, Confirm, &run) == MSBDCSKeyTake; k; }) && asked == 1);
    T("  ... its key-up after Option was let go first: kept too (the app never saw it go down)", MSBDCSKeyAct(&h, r, 4, 0x0D, 0, 0, t + 2700, Confirm, &run) == MSBDCSKeyTake);
    T("  ... then J is free: typing J goes to the app, its key-up too", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, 0, t + 3000, Confirm, &run) == MSBDCSKeyPass
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, 0, t + 3050, Confirm, &run) == MSBDCSKeyPass && asked == 1);
    T("  ... a second Option-J press runs again", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 3200, Confirm, &run) == MSBDCSKeyRun && run == 0
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 3300, Confirm, &run) == MSBDCSKeyTake);
    T("J held for typing, Option pressed while it repeats: the repeats stay the app's (no shortcut from a held key), its key-up too",
      MSBDCSKeyAct(&h, r, 4, 0x0D, 1, 0, t + 4000, Confirm, &run) == MSBDCSKeyPass && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 4500, Confirm, &run) == MSBDCSKeyPass
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 4600, Confirm, &run) == MSBDCSKeyPass && run == -1);
    asked = 0; answer = 0;
    T("not taken now (the switch off, KeyPilot, or Settings recording): Option-J goes to the app, its repeat and key-up too, asked once",
      MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 5000, Confirm, &run) == MSBDCSKeyPass && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 5500, Confirm, &run) == MSBDCSKeyPass
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 5600, Confirm, &run) == MSBDCSKeyPass && asked == 1 && run == -1);
    asked = 0; answer = 1; redirect = 2;
    T("the rules changed since they were read: the rule confirm finds in the new ones is run", MSBDCSKeyAct(&h, r, 4, 0x0E, 1, OPT | CMD, t + 6000, Confirm, &run) == MSBDCSKeyRun && run == 2);
    redirect = kMSBDCSMaxRules;
    MSBDCSKeyAct(&h, r, 4, 0x0E, 0, OPT | CMD, t + 6050, Confirm, &run);
    T("  ... an index past the last rule is never run (the key goes to the app, its key-up too)", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 6100, Confirm, &run) == MSBDCSKeyPass
      && run == -1 && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 6200, Confirm, &run) == MSBDCSKeyPass);
    redirect = -1; asked = 0;
    T("typing (no Control, Option, Command or Globe) asks nothing: a whole word", ({ int k = 1; for (long u = 0x04; u < 0x0C; u++) { k &= MSBDCSKeyAct(&h, r, 4, u, 1, u & 1 ? SHF : 0, t + 7000 + u, Confirm, &run) == MSBDCSKeyPass;
      k &= MSBDCSKeyAct(&h, r, 4, u, 0, 0, t + 7001 + u, Confirm, &run) == MSBDCSKeyPass; } k; }) && asked == 0);
    T("a key-up nobody saw go down: the app's", MSBDCSKeyAct(&h, r, 4, 0x10, 0, OPT, t + 8000, Confirm, &run) == MSBDCSKeyPass);
    T("Option-J down, its key-up gone to the app the shortcut opened: within 2.5 s another down is a repeat (kept)", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 9000, Confirm, &run) == MSBDCSKeyRun
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 10000, Confirm, &run) == MSBDCSKeyTake);
    T("  ... back in this app 2.6 s after the last of it, Option-J runs again (no key stuck as held)", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 12600, Confirm, &run) == MSBDCSKeyRun && run == 0);
    MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 12700, Confirm, &run);
    T("  ... an app key whose key-up went elsewhere: Option-J pressed 2.6 s later is a shortcut, not that key's repeat", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, 0, t + 13000, Confirm, &run) == MSBDCSKeyPass
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 15700, Confirm, &run) == MSBDCSKeyRun);
    MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 15800, Confirm, &run);
    T("keys past 255 and usage 0 go on untouched", MSBDCSKeyAct(&h, r, 4, 0x100, 1, OPT, t + 16000, Confirm, &run) == MSBDCSKeyPass && MSBDCSKeyAct(&h, r, 4, 0, 1, OPT, t + 16000, Confirm, &run) == MSBDCSKeyPass);
    uint64_t none[1] = { 0 };
    T("no rules published (the switch off): nothing taken", MSBDCSKeyAct(&h, none, 0, 0x0D, 1, OPT, t + 17000, Confirm, &run) == MSBDCSKeyPass
      && MSBDCSKeyAct(&h, none, 0, 0x0D, 0, OPT, t + 17100, Confirm, &run) == MSBDCSKeyPass);
    // (review 1.8.6, L: a shortcut key whose key-up went to another app kept the same plain key typed back here within 2.5 s)
    asked = 0;
    T("Option-J down, its key-up gone elsewhere: J typed with no modifier 1 s later is the app's, nothing asked, its key-up too",
      MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 20000, Confirm, &run) == MSBDCSKeyRun && asked == 1
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, 0, t + 21000, Confirm, &run) == MSBDCSKeyPass && run == -1 && asked == 1
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, 0, t + 21050, Confirm, &run) == MSBDCSKeyPass);
    T("  ... and Shift-J 1 s later too (Shift is no part of the chord's check)", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 22000, Confirm, &run) == MSBDCSKeyRun
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, SHF, t + 23000, Confirm, &run) == MSBDCSKeyPass && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, SHF, t + 23050, Confirm, &run) == MSBDCSKeyPass);
    T("Option-J held, Option let go while J repeats: the repeats and the key-up stay the shortcut's", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 24000, Confirm, &run) == MSBDCSKeyRun
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 24500, Confirm, &run) == MSBDCSKeyTake
      && ({ int k = 1; for (int i = 6; i <= 25; i++) k &= MSBDCSKeyAct(&h, r, 4, 0x0D, 1, 0, t + 24000 + i * 100, Confirm, &run) == MSBDCSKeyTake; k; })
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, 0, t + 26600, Confirm, &run) == MSBDCSKeyTake);
    T("  ... Option let go before the first repeat (it comes after the delay): still the shortcut's", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 27000, Confirm, &run) == MSBDCSKeyRun
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, 0, t + 27600, Confirm, &run) == MSBDCSKeyTake && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, 0, t + 27700, Confirm, &run) == MSBDCSKeyTake);
    T("  ... Option still down, the key held: a repeat at any pace inside 2.5 s", MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 28000, Confirm, &run) == MSBDCSKeyRun
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT | CAPS, t + 30000, Confirm, &run) == MSBDCSKeyTake && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 30100, Confirm, &run) == MSBDCSKeyTake);
    asked = 0;
    T("the keyboard went to another app (MSBDCSKeyForget): Option-J pressed again 0.3 s later runs again, not kept as a repeat",
      MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 31000, Confirm, &run) == MSBDCSKeyRun && (MSBDCSKeyForget(&h), 1)
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 31300, Confirm, &run) == MSBDCSKeyRun && run == 0 && asked == 2
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 31400, Confirm, &run) == MSBDCSKeyTake);
    T("  ... a plain J at once after it is the app's, and a key-up whose key-down was forgotten is the app's",
      MSBDCSKeyAct(&h, r, 4, 0x0D, 1, OPT, t + 32000, Confirm, &run) == MSBDCSKeyRun && (MSBDCSKeyForget(&h), 1)
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, OPT, t + 32100, Confirm, &run) == MSBDCSKeyPass
      && MSBDCSKeyAct(&h, r, 4, 0x0D, 1, 0, t + 32200, Confirm, &run) == MSBDCSKeyPass && MSBDCSKeyAct(&h, r, 4, 0x0D, 0, 0, t + 32300, Confirm, &run) == MSBDCSKeyPass);
    T("  ... MSBDCSKeyForget leaves nothing held, no app key and no time", ({ MSBDCSKeyAct(&h, r, 4, 0x0E, 1, OPT | CMD, t + 33000, Confirm, &run);
      MSBDCSKeyAct(&h, r, 4, 0x10, 1, 0, t + 33000, Confirm, &run); MSBDCSKeyForget(&h); int k = 1;
      for (int i = 0; i < 4; i++) k &= !h.held[i] && !h.app[i]; for (int i = 0; i < 256; i++) k &= h.at[i] == 0 && h.mods[i] == 0; k; }));
    T("nothing held at the end (every key-down taken got its key-up)", !h.held[0] && !h.held[1] && !h.held[2] && !h.held[3]);

    // ---- what SpringBoard publishes is what it means (1.8.6 i05, M1 and A12Z: the last rule turned off or deleted kept its keys from every app) ----
    uint64_t ab[kMSBDCSMaxRules];
    uint64_t three[3] = { MSBDCSPack(0x0D, OPT, true), MSBDCSPack(0x0E, OPT | CMD, true), MSBDCSPack(0x10, OPT, true) };
    T("three rules published: the app reads three, Option-M (the last) is rule 2", Publish(three, 3) == 1 && SameAsMeant(three, 3)
      && MSBDCSMatch(ab, AppRead(ab), 0x10, OPT) == 2);
    T("  ... published again unchanged: nothing written, nothing posted (SpringBoard's own post comes back: no loop)", Publish(three, 3) == 0 && Publish(three, 3) == 0);
    uint64_t gen = MSBDCSRulesGen(gStoreRS);
    T("the last rule turned off or deleted (two left, both unchanged): published again, the count 2, its slot cleared, its key the app's again",
      Publish(three, 2) == 1 && SameAsMeant(three, 2) && MSBDCSRulesGen(gStoreRS) == gen + 1 && MSBDCSMatch(ab, AppRead(ab), 0x10, OPT) < 0 && gStore[2] == 0);
    T("  ... then stable at two", Publish(three, 2) == 0);
    uint64_t ac[2] = { three[0], three[2] };
    T("a rule in the middle turned off: the next one moves down, published again", Publish(ac, 2) == 1 && SameAsMeant(ac, 2) && MSBDCSMatch(ab, AppRead(ab), 0x0E, OPT | CMD) < 0
      && MSBDCSMatch(ab, AppRead(ab), 0x10, OPT) == 1);
    T("deleted down to one, then the switch off (no rules for the apps): each published, the count 0 at the end, every slot 0",
      Publish(ac, 1) == 1 && SameAsMeant(ac, 1) && Publish(ac, 0) == 1 && SameAsMeant(ac, 0) && Publish(ac, 0) == 0);
    T("  ... switched on again: the rules back", Publish(three, 3) == 1 && SameAsMeant(three, 3));
    gStoreRS = (gStoreRS & ~0xFFULL) | 4;   // (a forger: the generation ours, the count one more)
    T("a count some other process wrote, the generation kept: written again", Publish(three, 3) == 1 && SameAsMeant(three, 3));
    gStore[1] = MSBDCSPack(0x04, CMD, true);
    T("  ... a slot below the count some other process wrote: written again", Publish(three, 3) == 1 && SameAsMeant(three, 3));
    gStore[5] = MSBDCSPack(0x04, CMD, true);
    T("  ... a slot past the count: no rule to the apps (they read the count's slots only), nothing to post", Publish(three, 3) == 0 && MSBDCSMatch(ab, AppRead(ab), 0x04, CMD) < 0);
    gStore[5] = 0;
    gStoreRS &= ~0xFFULL;   // (a forger: the count 0, the generation ours)
    T("  ... a count 0 some other process wrote as the last rule goes: written again, the slot SpringBoard wrote before cleared too", Publish(three, 2) == 1 && SameAsMeant(three, 2)
      && Publish(three, 3) == 1);
    memset(gStore, 0, sizeof gStore); for (unsigned i = 0; i < 5; i++) gStore[i] = MSBDCSPack(0x04 + i, OPT, true);
    gStoreRS = MSBDCSRulesNext(gStoreRS, 5); gen = MSBDCSRulesGen(gStoreRS); gPublished = false; gLastCount = 0; gWrote = 0;   // (a respring: five published before it)
    T("after a respring, two rules meant and five published before it: the count 2, slots 2 to 4 cleared, the generation going on",
      Publish(three, 2) == 1 && SameAsMeant(three, 2) && MSBDCSRulesGen(gStoreRS) == gen + 1);
    T("the slots a publish writes: those meant, the count written last, the count published; at most 64", MSBDCSSlotsToWrite(2, 3, MSBDCSRulesNext(0, 3)) == 3
      && MSBDCSSlotsToWrite(2, 0, MSBDCSRulesNext(0, 5)) == 5 && MSBDCSSlotsToWrite(4, 1, MSBDCSRulesNext(0, 0)) == 4 && MSBDCSSlotsToWrite(64, 70, (5ULL << 8) | 0xFF) == 64);
    T("never published: never the same (a first publish always writes)", !MSBDCSPublishedSame(false, 0, 0, 0, ab, StoreSlot, NULL));

    // ---- the app keeps a key only when SpringBoard will run it (1.8.6 i05, iPad 2 and 17.5: no keyboard, the key kept and nothing run) ----
    T("the apps' wanted state: taken and a hardware keyboard, both", MSBDCSAppsWanted(true, true) && !MSBDCSAppsWanted(true, false) && !MSBDCSAppsWanted(false, true)
      && !MSBDCSAppsWanted(false, false));
    { int agree = 1, kept = 0, ran = 0;
      for (int c = 0; c < 32; c++) {   // (every switch, KeyPilot, rules, recording and keyboard: the app's choice and SpringBoard's run gate, DMCSRunFromApp)
          bool sw = c & 1, kp = c & 2, rec = c & 8, kb = c & 16; unsigned cnt = c & 4 ? 3 : 0;
          gWantedState = MSBDCSAppsWanted(MSBDCSWantedNow(sw, kp, cnt, rec), kb) ? 1 : 0;   // (published: DMCSPublishStates)
          bool sbRuns = MSBDCSAppsWanted(MSBDCSWantedNow(sw, kp, cnt, rec), kb);            // (asked again at the run: DMCSRunFromApp)
          MSBDCSKeyHeld hk; memset(&hk, 0, sizeof hk); int rr = -1;
          int a = MSBDCSKeyAct(&hk, three, 3, 0x0D, 1, OPT, 1000, ConfirmWanted, &rr);
          agree &= (a == MSBDCSKeyRun) == sbRuns;
          if (a == MSBDCSKeyRun) kept++;
          if (sbRuns) ran++;
          if (a == MSBDCSKeyPass) agree &= MSBDCSKeyAct(&hk, three, 3, 0x0D, 1, OPT, 1500, ConfirmWanted, &rr) == MSBDCSKeyPass
                                         && MSBDCSKeyAct(&hk, three, 3, 0x0D, 0, OPT, 1600, ConfirmWanted, &rr) == MSBDCSKeyPass;
      }
      T("every state: the app keeps Option-J exactly when SpringBoard runs it; otherwise its down, repeat and up all go to the app", agree && kept == 1 && ran == 1); }
    gWantedState = MSBDCSAppsWanted(MSBDCSWantedNow(true, false, 3, false), false) ? 1 : 0;
    { MSBDCSKeyHeld hk; memset(&hk, 0, sizeof hk); int rr = -1;
      T("no hardware keyboard (keys injected on the iPad 2): Option-J goes to the app untouched, its key-up too, no run posted",
        MSBDCSKeyAct(&hk, three, 3, 0x0D, 1, OPT, 1000, ConfirmWanted, &rr) == MSBDCSKeyPass && rr == -1 && MSBDCSKeyAct(&hk, three, 3, 0x0D, 0, OPT, 1100, ConfirmWanted, &rr) == MSBDCSKeyPass);
      gWantedState = MSBDCSAppsWanted(MSBDCSWantedNow(true, false, 3, false), true) ? 1 : 0;
      T("  ... a keyboard attached (republished): Option-J runs rule 0 and is kept", MSBDCSKeyAct(&hk, three, 3, 0x0D, 1, OPT, 2000, ConfirmWanted, &rr) == MSBDCSKeyRun && rr == 0
        && MSBDCSKeyAct(&hk, three, 3, 0x0D, 0, OPT, 2100, ConfirmWanted, &rr) == MSBDCSKeyTake); }

    // ---- SpringBoard runs every press the app keeps (review 1.8.6, L: its time windows dropped presses the app had kept) ----
    gWantedState = 1; memset(&gAppKeys, 0, sizeof gAppKeys);
    uint64_t dig[3] = { MSBDCSPack(0x0D, OPT, true), MSBDCSPack(kMSBDCSHID1, OPT, true), MSBDCSPack(kMSBDCSHID1 + 1, OPT, true) };   // (Option-J, Option-1, Option-2)
    SBReset(); AppTap(dig, 3, 0x0D, OPT, 1000); AppTap(dig, 3, 0x0D, OPT, 1300);
    T("an app in front, Option held, J tapped twice 0.3 s apart: two presses, the app keeps both and SpringBoard runs both", gKept == 2 && gRan[0] == 2 && gRanAll == 2);
    SBReset(); AppTap(dig, 3, 0x0D, OPT, 5000); AppTap(dig, 3, 0x0D, OPT, 5150);
    T("  ... 0.15 s apart: both run", gKept == 2 && gRan[0] == 2);
    SBReset(); AppTap(dig, 3, kMSBDCSHID1, OPT, 9000); AppTap(dig, 3, kMSBDCSHID1 + 1, OPT, 9200);
    T("Option-1 then Option-2 0.2 s apart: both kept, both run", gKept == 2 && gRan[1] == 1 && gRan[2] == 1 && gRanAll == 2);
    SBReset(); AppTap(dig, 3, kMSBDCSHID1, OPT, 12000); AppTap(dig, 3, kMSBDCSHID1 + 1, OPT, 12050);
    T("  ... 0.05 s apart (a fast chord): both run", gRanAll == 2);
    SBReset(); for (int k = 0; k < 40; k++) AppTap(dig, 3, k % 3 == 0 ? 0x0D : kMSBDCSHID1 + (k % 3) - 1, OPT, 20000 + k * 150.0);
    T("forty presses 0.15 s apart, the same and other shortcuts: forty kept, forty run", gKept == 40 && gRanAll == 40);
    SBReset(); for (int k = 0; k < 4; k++) AppTap(dig, 3, kMSBDCSHID1 + (k & 1), OPT, 30000 + k * 40.0);
    T("four presses 0.04 s apart: all four run", gKept == 4 && gRanAll == 4);
    SBReset(); AppKey(dig, 3, 0x0D, 1, OPT, 40000);
    for (int k = 5; k <= 25; k++) AppKey(dig, 3, 0x0D, 1, OPT, 40000 + k * 100.0);
    AppKey(dig, 3, 0x0D, 0, OPT, 42600);
    T("Option-J held 2.5 s: one post, one run (the app keeps the repeats)", gKept == 1 && gRan[0] == 1);
    { SBReset(); int k = 0; for (double ms = 50000; ms < 51000; ms += 1, k++) SBFromApp((unsigned)(k & 1), ms);
      int flood = gRanAll;
      T("a forged flood, run.0 and run.1 in turn each 1 ms for 1 s: at most 4 at once, then one each 0.15 s (at most 11)", flood >= 4 && flood <= 11);
      SBReset(); k = 0; gBucket = (MSBDCSFromAppBucket){ true, kMSBDCSFromAppBurst, 0 };
      for (double ms = 3600000; ms < 3601000; ms += 1, k++) SBFromApp((unsigned)(k & 1), ms);
      T("  ... after an hour with no post: the same bound (the bucket holds 4 at most)", gRanAll >= 4 && gRanAll <= 11);
      int before = gRanAll; SBFromApp(5, 3601150);
      T("  ... a press 0.15 s after the flood ends runs (refused posts took nothing)", gRanAll == before + 1 && gRan[5] == 1); }

    // ---- SpringBoard's own way and a key come two ways: still once per key ----
    SBReset();
    for (int k = 0; k <= 20; k++) SBArrive(0, kMSBDCSWaySpringBoard, 60000 + k * 100.0);
    T("SpringBoard's own way: a key held 2 s, its repeats every 0.1 s: one run", gRan[0] == 1);
    SBArrive(0, kMSBDCSWaySpringBoard, 62300);
    T("  ... the same key again 0.3 s after the last repeat: none (the Home Screen's check, review 1.8.5-k M2); 0.6 s after: runs", gRan[0] == 1
      && (SBArrive(0, kMSBDCSWaySpringBoard, 62900), gRan[0] == 2));
    SBArrive(1, kMSBDCSWaySpringBoard, 63000);
    T("  ... another shortcut at once: runs", gRan[1] == 1);
    SBReset();
    SBFromApp(0, 70000); SBArrive(0, kMSBDCSWaySpringBoard, 70005);
    for (int k = 4; k <= 9; k++) SBArrive(0, kMSBDCSWaySpringBoard, 70000 + k * 100.0);
    T("a Command chord come two ways, the app's post first, then the key command and its repeats: one run", gRan[0] == 1);
    SBFromApp(0, 71200); SBArrive(0, kMSBDCSWaySpringBoard, 71205);
    T("  ... the second press 0.3 s after the last repeat, both ways again: runs once more", gRan[0] == 2);
    SBReset();
    SBArrive(0, kMSBDCSWaySpringBoard, 80000); SBFromApp(0, 80005);
    for (int k = 4; k <= 9; k++) SBArrive(0, kMSBDCSWaySpringBoard, 80000 + k * 100.0);
    T("  ... the key command first, then the app's post, then the repeats: one run", gRan[0] == 1);
    SBArrive(0, kMSBDCSWaySpringBoard, 81200); SBFromApp(0, 81205);
    T("  ... and its second press 0.3 s later: runs once more", gRan[0] == 2);
    SBFromApp(0, 81600); SBArrive(0, kMSBDCSWaySpringBoard, 81610);
    T("  ... a third, the app's post first: once more", gRan[0] == 3);
    SBReset(); SBFromApp(0, 90000); SBArrive(1, kMSBDCSWaySpringBoard, 90010);
    T("two different shortcuts, one each way, at once: both run", gRan[0] == 1 && gRan[1] == 1);
    T("a way that is neither, a missing state: nothing runs", !MSBDCSRunOnceNow(&gOnce, 0, 2, 99000) && !MSBDCSRunOnceNow(NULL, 0, kMSBDCSWayApp, 99000)
      && !MSBDCSFromAppTake(NULL, 99000));
    return fails ? 1 : 0;
}
