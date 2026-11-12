// test-keyboardchords.c -- Mac test of the keyboard features' one table (1.8.7, KT 11 Nov; common/KeyboardChords.h): every chord each feature owns,
// no two built-in shortcuts on one chord (every key 0x04-0x65 and the arrows with every set of Shift, Control, Option, Command and Globe, on an
// ANSI and an Apple ISO keyboard), who has a chord a built-in one and yours both claim (yours; a tap waits; Escape is never yours), your own
// shortcuts' claims (Custom Shortcuts' exactly, KeyPilot's with Globe or not, Window Tiling's rows by the letter the layout types), and what the
// key tweaks in every app are told (the key left of 1, Tab, Shift + =/-, the taps waiting). Custom Shortcuts on with no rule: nothing is yours.
// KeyPilot's Caps Lock kept as its match keeps it, and a rule of its recorded with Caps Lock on taking no built-in one's keys before a press.
// Run by test-keyboardchords.sh.
#include <stdio.h>
#include "../common/KeyboardChords.h"
static int fails = 0;
#define T(name, cond) do { if (cond) printf("PASS  %s\n", name); else { printf("FAIL  %s\n", name); fails++; } } while (0)
#define CMD kMSBDModCommand
#define CTL kMSBDModControl
#define OPT kMSBDModOption
#define SHF kMSBDModShift
#define GLB kMSBDModGlobe
#define CAPS (1ULL << 16)
// What a US layout types on a key (for Window Tiling's F, C and R by the letter): letters a-z, else "".
static const char *US(long u) {
    static char b[2];
    if (u >= 0x04 && u <= 0x1D) { b[0] = (char)('a' + (u - 0x04)); b[1] = 0; return b; }
    return "";
}
static unsigned long long Mods(int bits) {
    return (bits & 1 ? SHF : 0) | (bits & 2 ? CTL : 0) | (bits & 4 ? OPT : 0) | (bits & 8 ? CMD : 0) | (bits & 16 ? GLB : 0);
}
int main(void) {
    // ---- the table ----
    int seen[kMSBDKCFeatureCount] = {0};
    for (size_t i = 0; i < kMSBDKCChordCount; i++) seen[kMSBDKCChords[i].feature]++;
    T("the table names every built-in feature: Window Tiling, the Mac Switcher, volume, backlight, the screen keys, the key left of 1, Tab, the menu keys, Escape",
      seen[kMSBDKCWindowTiling] && seen[kMSBDKCMacSwitcher] == 3 && seen[kMSBDKCVolume] == 2 && seen[kMSBDKCBacklight] == 2 && seen[kMSBDKCScreen] == 2
      && seen[kMSBDKCTopLeftEscape] == 2 && seen[kMSBDKCTabMute] == 1 && seen[kMSBDKCMenuKeys] == 1 && seen[kMSBDKCEscape] == 1);
    // ---- one owner per chord among the built-ins ----
    int ok = 1, owned = 0;
    for (int layout = 0; layout < 2; layout++) {
        long tl = layout ? kMSBDKCTopLeftISO : kMSBDKCTopLeftANSI;
        for (long u = 0x04; u <= 0x65; u++)
            for (int b = 0; b < 32; b++) {
                int claims = 0;
                for (size_t i = 0; i < kMSBDKCChordCount; i++)
                    if (kMSBDKCChords[i].kind != kMSBDKCKindTap && MSBDKCRowClaims(i, u, US(u), Mods(b), tl)) claims++;
                if (claims > 1) { ok = 0; printf("  two built-in shortcuts on usage 0x%lx mods 0x%llx (layout %d)\n", u, Mods(b), layout); }
                if (claims) owned++;
            }
    }
    T("no chord is two built-in shortcuts at once (every key, every set of modifiers, ANSI and Apple ISO)", ok && owned > 0);
    int row = -2;
    T("Globe-Control-F is Window Tiling's Fill (row 0), Globe-Control-Option-Shift-Down its Bottom & Quarters (row 14)",
      MSBDKCKeyOwner(0x09, "f", GLB | CTL, kMSBDKCTopLeftANSI, &row) == kMSBDKCWindowTiling && row == 0
      && MSBDKCKeyOwner(kMSBDCSHIDDown, "", GLB | CTL | OPT | SHF, kMSBDKCTopLeftANSI, &row) == kMSBDKCWindowTiling && row == 14);
    T("  ... by the letter typed: Dvorak's F (QWERTY's Y place) is Fill, Dvorak's U (QWERTY's F place) none",
      MSBDKCKeyOwner(0x1C, "f", GLB | CTL, kMSBDKCTopLeftANSI, &row) == kMSBDKCWindowTiling && MSBDKCKeyOwner(0x09, "u", GLB | CTL, kMSBDKCTopLeftANSI, &row) == kMSBDKCNone && row == -1);
    T("Control-Left, -Right, -Up are the Mac Switcher's; Control-Down, Control-Option-Left nobody's",
      MSBDKCKeyOwner(kMSBDCSHIDLeft, "", CTL, 0x35, NULL) == kMSBDKCMacSwitcher && MSBDKCKeyOwner(kMSBDCSHIDRight, "", CTL, 0x35, NULL) == kMSBDKCMacSwitcher
      && MSBDKCKeyOwner(kMSBDCSHIDUp, "", CTL, 0x35, NULL) == kMSBDKCMacSwitcher && MSBDKCKeyOwner(kMSBDCSHIDDown, "", CTL, 0x35, NULL) == kMSBDKCNone
      && MSBDKCKeyOwner(kMSBDCSHIDLeft, "", CTL | OPT, 0x35, NULL) == kMSBDKCNone);
    T("Globe-Control-Left is Window Tiling's, not the Mac Switcher's (Globe tells them apart)", MSBDKCKeyOwner(kMSBDCSHIDLeft, "", GLB | CTL, 0x35, NULL) == kMSBDKCWindowTiling);
    T("Shift + = and Shift + - are the screen keys'; with Globe (1.8.7), Control or Command nobody's",
      MSBDKCKeyOwner(0x2E, "", SHF, 0x35, NULL) == kMSBDKCScreen && MSBDKCKeyOwner(0x2D, "", SHF, 0x35, NULL) == kMSBDKCScreen
      && MSBDKCKeyOwner(0x2E, "", SHF | GLB, 0x35, NULL) == kMSBDKCNone && MSBDKCKeyOwner(0x2E, "", SHF | CTL, 0x35, NULL) == kMSBDKCNone && MSBDKCKeyOwner(0x2E, "", SHF | CMD, 0x35, NULL) == kMSBDKCNone);
    T("a bare Tab is Tab mute's (Caps Lock aside); Globe-Tab (1.8.7), Shift-Tab, Control-Tab nobody's",
      MSBDKCKeyOwner(kMSBDCSHIDTab, "", 0, 0x35, NULL) == kMSBDKCTabMute && MSBDKCKeyOwner(kMSBDCSHIDTab, "", CAPS, 0x35, NULL) == kMSBDKCTabMute
      && MSBDKCKeyOwner(kMSBDCSHIDTab, "", GLB, 0x35, NULL) == kMSBDKCNone && MSBDKCKeyOwner(kMSBDCSHIDTab, "", SHF, 0x35, NULL) == kMSBDKCNone && MSBDKCKeyOwner(kMSBDCSHIDTab, "", CTL, 0x35, NULL) == kMSBDKCNone);
    T("the key left of 1 (0x35 on ANSI) with Option or Globe-Shift is the Escape key's; with Command nobody's",
      MSBDKCKeyOwner(0x35, "`", OPT, kMSBDKCTopLeftANSI, NULL) == kMSBDKCTopLeftEscape && MSBDKCKeyOwner(0x35, "`", GLB | SHF, kMSBDKCTopLeftANSI, NULL) == kMSBDKCTopLeftEscape
      && MSBDKCKeyOwner(0x35, "`", CMD, kMSBDKCTopLeftANSI, NULL) == kMSBDKCNone && MSBDKCKeyOwner(0x35, "`", CMD | OPT, kMSBDKCTopLeftANSI, NULL) == kMSBDKCNone);
    T("  ... on an Apple ISO keyboard the key left of 1 is 0x64 and 0x35 (left of Z) is nobody's; on JIS none is",
      MSBDKCKeyOwner(0x64, "", OPT, kMSBDKCTopLeftISO, NULL) == kMSBDKCTopLeftEscape && MSBDKCKeyOwner(0x35, "<", OPT, kMSBDKCTopLeftISO, NULL) == kMSBDKCNone
      && MSBDKCKeyOwner(0x35, "", OPT, 0, NULL) == kMSBDKCNone && MSBDKCKeyOwner(0x64, "", OPT, kMSBDKCTopLeftANSI, NULL) == kMSBDKCNone);
    T("Escape with any modifiers is Escape's (never yours)", MSBDKCKeyOwner(kMSBDCSHIDEscape, "", 0, 0x35, NULL) == kMSBDKCEscape
      && MSBDKCKeyOwner(kMSBDCSHIDEscape, "", CMD | OPT, 0x35, NULL) == kMSBDKCEscape && MSBDKCAgainstYours(kMSBDKCEscape) == kMSBDKCBuiltin);
    // ---- taps ----
    T("Globe-Option-J and Globe-Control-K start with the volume taps; Shift-Control-K and Shift-Option-1 with the backlight's; Option-J, Control-J with neither",
      MSBDKCTapsIn(GLB | OPT) == (1u << kMSBDKCVolume) && MSBDKCTapsIn(GLB | CTL) == (1u << kMSBDKCVolume) && MSBDKCTapsIn(SHF | CTL) == (1u << kMSBDKCBacklight)
      && MSBDKCTapsIn(SHF | OPT) == (1u << kMSBDKCBacklight) && MSBDKCTapsIn(OPT) == 0 && MSBDKCTapsIn(CTL) == 0 && MSBDKCTapsIn(CMD | SHF) == 0);
    T("  ... Window Tiling's Globe-Control-Shift rows start with both (they wait while it is offered: common/ModifierTap.h)", MSBDKCTapsIn(GLB | CTL | SHF) == ((1u << kMSBDKCVolume) | (1u << kMSBDKCBacklight)));
    T("who has a chord a built-in one and yours both claim: yours over Window Tiling, the Mac Switcher, the screen keys, the key left of 1, Tab, the menus; a tap waits",
      MSBDKCAgainstYours(kMSBDKCWindowTiling) == kMSBDKCYours && MSBDKCAgainstYours(kMSBDKCMacSwitcher) == kMSBDKCYours && MSBDKCAgainstYours(kMSBDKCScreen) == kMSBDKCYours
      && MSBDKCAgainstYours(kMSBDKCTopLeftEscape) == kMSBDKCYours && MSBDKCAgainstYours(kMSBDKCTabMute) == kMSBDKCYours && MSBDKCAgainstYours(kMSBDKCMenuKeys) == kMSBDKCYours
      && MSBDKCAgainstYours(kMSBDKCVolume) == kMSBDKCTapWaits && MSBDKCAgainstYours(kMSBDKCBacklight) == kMSBDKCTapWaits);
    T("a Custom Shortcut on a built-in one's keys may be recorded now (Window Tiling's, the Mac Switcher's: refused in 1.8.5); Escape still can't",
      MSBDCSCheck(0x09, "f", GLB | CTL) == kMSBDCSOK && MSBDCSCheck(kMSBDCSHIDLeft, "", CTL) == kMSBDCSOK && MSBDCSCheck(0x35, "`", OPT) == kMSBDCSOK
      && MSBDCSCheck(kMSBDCSHIDEscape, "", CMD) == kMSBDCSEscape && MSBDCSCheck(kMSBDCSHIDTab, "", 0) == kMSBDCSNeedsModifier);

    // ---- yours ----
    static MSBDKCYoursSet y;
    MSBDKCYoursClear(&y);
    T("Custom Shortcuts on with no rule: nothing is yours, the state 0 (no key changed), not taken", y.n == 0 && MSBDKCYoursState(&y) == 0 && MSBDKCYoursTaps(&y) == 0
      && !MSBDKCYoursTakes(&y, 0x09, GLB | CTL) && !MSBDKCYoursTakesWinRow(&y, 0) && !MSBDCSWantedNow(true, false, 0, false));
    MSBDKCYoursAdd(&y, 0x09, "f", GLB | CTL | CAPS, false);
    T("a Custom Shortcut on Globe-Control-F takes that press (Caps Lock aside) and Window Tiling's Fill row; not Globe-Control-Shift-F, not the Center row",
      MSBDKCYoursTakes(&y, 0x09, GLB | CTL) && MSBDKCYoursTakes(&y, 0x09, GLB | CTL | CAPS) && MSBDKCYoursTakesWinRow(&y, 0)
      && !MSBDKCYoursTakes(&y, 0x09, GLB | CTL | SHF) && !MSBDKCYoursTakesWinRow(&y, 1) && !MSBDKCYoursTakes(&y, 0x09, CTL));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, kMSBDCSHIDLeft, "", CTL, false);
    ok = 1;
    for (int r = 0; r < (int)kMSBDWinKeyRowCount; r++) ok &= !MSBDKCYoursTakesWinRow(&y, r);
    T("a Custom Shortcut on Control-Left takes the Mac Switcher's Control-Left only: no Window Tiling row (Globe is part of its match)", ok
      && MSBDKCYoursTakes(&y, kMSBDCSHIDLeft, CTL) && !MSBDKCYoursTakes(&y, kMSBDCSHIDLeft, GLB | CTL) && !MSBDKCYoursTakes(&y, kMSBDCSHIDRight, CTL));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, kMSBDCSHIDLeft, "", CTL | GLB, true);   // (KeyPilot records no Globe; dropped if given)
    T("a KeyPilot rule on Control-Left takes Control-Left and Globe-Control-Left (its match drops Globe): the Mac Switcher's and Window Tiling's Left",
      MSBDKCYoursTakes(&y, kMSBDCSHIDLeft, CTL) && MSBDKCYoursTakes(&y, kMSBDCSHIDLeft, GLB | CTL) && MSBDKCYoursTakesWinRow(&y, 2)
      && !MSBDKCYoursTakes(&y, kMSBDCSHIDLeft, CTL | SHF) && !MSBDKCYoursTakesWinRow(&y, 7));
    // (review 1.8.7: KeyPilot's match keeps Caps Lock, KPRelevantModifierFlags; ours leaves it aside)
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x09, "f", CTL, true);
    T("a KeyPilot rule on Control-F recorded without Caps Lock: a press with Caps Lock off is its own (Globe or not), with Caps Lock on not (KeyPilot runs nothing then, Fill may); it takes Fill's key command",
      MSBDKCYoursTakes(&y, 0x09, CTL) && MSBDKCYoursTakes(&y, 0x09, GLB | CTL) && !MSBDKCYoursTakes(&y, 0x09, GLB | CTL | CAPS) && !MSBDKCYoursTakes(&y, 0x09, CTL | CAPS)
      && MSBDKCYoursTakesWinRow(&y, 0) && MSBDKCYoursRuleStatic(&y, 0));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x09, "f", CTL | CAPS, true);
    MSBDKCYoursAdd(&y, kMSBDCSHIDUp, "", CTL | CAPS, true);
    MSBDKCYoursAdd(&y, 0x35, "`", OPT | CAPS, true);
    MSBDKCYoursAdd(&y, kMSBDCSHIDTab, "", CAPS, true);
    T("  ... recorded with Caps Lock on: only a press with Caps Lock on is its own; before any press it takes nothing (Fill's and Control-Up's key commands stay, the key left of 1 and Tab the key tweaks'); a tap still waits",
      MSBDKCYoursTakes(&y, 0x09, GLB | CTL | CAPS) && MSBDKCYoursTakes(&y, 0x09, CTL | CAPS) && !MSBDKCYoursTakes(&y, 0x09, GLB | CTL) && !MSBDKCYoursTakes(&y, 0x09, CTL)
      && !MSBDKCYoursTakesWinRow(&y, 0) && !MSBDKCYoursTakes(&y, kMSBDCSHIDUp, CTL) && MSBDKCYoursTakes(&y, kMSBDCSHIDUp, CTL | CAPS) && !MSBDKCYoursRuleStatic(&y, 0)
      && MSBDKCYoursState(&y) == kMSBDKCYoursVolumeWaits);
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x09, "f", GLB | CTL | CAPS, false);
    T("  ... ours leaves Caps Lock aside, in the press and before it", MSBDKCYoursTakes(&y, 0x09, GLB | CTL) && MSBDKCYoursTakes(&y, 0x09, GLB | CTL | CAPS) && MSBDKCYoursRuleStatic(&y, 0) && MSBDKCYoursTakesWinRow(&y, 0));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x1C, "f", GLB | CTL, false);   // (Dvorak: the key at QWERTY's Y types f)
    T("  ... Window Tiling's row by the letter the layout types: a Dvorak Globe-Control-F (usage 0x1C) takes Fill", MSBDKCYoursTakesWinRow(&y, 0) && MSBDKCYoursTakes(&y, 0x1C, GLB | CTL));
    ok = 1;
    MSBDKCYoursClear(&y);
    for (int i = 0; i < kMSBDKCYoursMax; i++) ok &= MSBDKCYoursAdd(&y, 0x04 + (i % 26), "", CMD, i & 1);
    T("128 of yours at most (64 of ours, 64 of KeyPilot's); a 129th refused; no key, a key past 16 bits refused",
      ok && !MSBDKCYoursAdd(&y, 0x04, "", CMD, false) && y.n == kMSBDKCYoursMax);
    MSBDKCYoursClear(&y);
    T("  ... and no key, or one past 16 bits", !MSBDKCYoursAdd(&y, 0, "", CMD, false) && !MSBDKCYoursAdd(&y, 0x10000, "", CMD, false) && y.n == 0);

    // ---- the key tweaks' state ----
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x35, "`", OPT, false);
    uint64_t st = MSBDKCYoursState(&y);
    T("a Custom Shortcut on Option-` (0x35): the key left of 1 stays itself with Option only; not with Option-Shift, Globe-Option, Command; not 0x64",
      st == (1ULL << 4) && MSBDKCTopLeftYours(st, 0x35, OPT) && !MSBDKCTopLeftYours(st, 0x35, OPT | SHF) && !MSBDKCTopLeftYours(st, 0x35, OPT | GLB)
      && !MSBDKCTopLeftYours(st, 0x35, OPT | CMD) && !MSBDKCTopLeftYours(st, 0x64, OPT) && !MSBDKCTopLeftYours(st, 0x35, 0));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x35, "`", OPT, true);
    st = MSBDKCYoursState(&y);
    T("  ... KeyPilot's on Option-`: with Option and with Globe-Option (its match drops Globe; so the volume taps wait too)", st == ((1ULL << 4) | (1ULL << 12) | kMSBDKCYoursVolumeWaits) && MSBDKCTopLeftYours(st, 0x35, OPT | GLB));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x64, "", CTL | SHF, false);
    st = MSBDKCYoursState(&y);
    T("  ... Control-Shift on 0x64 (Apple ISO): its own bits, read for 0x64 (and the backlight taps wait: it starts with Shift + Control)", st == ((1ULL << (16 + 3)) | kMSBDKCYoursBacklightWaits) && MSBDKCTopLeftYours(st, 0x64, CTL | SHF) && !MSBDKCTopLeftYours(st, 0x35, CTL | SHF));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x35, "`", CMD, false);
    T("  ... Command-` is never Escape: nothing to tell", MSBDKCYoursState(&y) == 0);
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, kMSBDCSHIDTab, "", 0, true);
    MSBDKCYoursAdd(&y, 0x2E, "=", SHF, true);
    st = MSBDKCYoursState(&y);
    T("KeyPilot's bare Tab and Shift-=: Tab mute and the screen key leave them; Shift-- still the screen key's",
      (st & kMSBDKCYoursTab) && MSBDKCScreenKeyYours(st, 0x2E) && !MSBDKCScreenKeyYours(st, 0x2D) && !(st & (kMSBDKCYoursVolumeWaits | kMSBDKCYoursBacklightWaits)));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, kMSBDCSHIDTab, "", GLB, false);
    MSBDKCYoursAdd(&y, 0x2E, "=", GLB | SHF, false);
    T("a Custom Shortcut on Globe-Tab or Globe-Shift-=: nothing to tell (Tab mute and the screen keys leave Globe alone)", MSBDKCYoursState(&y) == 0);
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x0D, "j", GLB | OPT, false);
    T("a Custom Shortcut on Globe-Option-J: the volume taps wait, the backlight's not", MSBDKCYoursState(&y) == kMSBDKCYoursVolumeWaits);
    MSBDKCYoursAdd(&y, 0x0E, "k", SHF | CTL, false);
    T("  ... and Shift-Control-K: the backlight's too", MSBDKCYoursState(&y) == (kMSBDKCYoursVolumeWaits | kMSBDKCYoursBacklightWaits));
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x0D, "j", OPT, false);
    MSBDKCYoursAdd(&y, 0x0E, "k", CMD | SHF, false);
    T("  ... Option-J, Command-Shift-K (ours): no tap waits", MSBDKCYoursState(&y) == 0);
    MSBDKCYoursClear(&y);
    MSBDKCYoursAdd(&y, 0x0D, "j", OPT, true);
    T("  ... KeyPilot's Option-J takes Globe-Option-J too: the volume taps wait", MSBDKCYoursState(&y) == kMSBDKCYoursVolumeWaits);
    T("Settings' recording on the key left of 1: with Control, Option or Globe it stays itself; bare, with Shift, or with Command not",
      MSBDKCTopLeftRecordable(OPT) && MSBDKCTopLeftRecordable(CTL | SHF) && MSBDKCTopLeftRecordable(GLB) && !MSBDKCTopLeftRecordable(0)
      && !MSBDKCTopLeftRecordable(SHF) && !MSBDKCTopLeftRecordable(CMD | OPT));
    printf("test-keyboardchords: %d fail\n", fails);
    return fails ? 1 : 0;
}
