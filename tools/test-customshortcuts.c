// test-customshortcuts.c -- Mac test of Custom Shortcuts' rules (1.8.5 item 2, common/CustomShortcutsRule.h): which keys may be a shortcut (a
// modifier needed, this tweak's own keys refused, Globe part of the match, Caps Lock not), the actions run (KeyPilot's spelling, no shell), the
// window layouts by KeyPilot's names and aliases, each one the window API's.
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
    return fails ? 1 : 0;
}
