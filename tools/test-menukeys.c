// test-menukeys.c -- Mac test of the menu bar's menus and the hardware keyboard (common/MenuKeys.h, 1.7.9): SpringBoard's lease (a menu has the keys)
// holds while renewed and lapses when SpringBoard stops renewing it, and the app's MacAppBridge gives an open menu exactly the keys that would reach
// the app -- Esc alone closes it, a taken press keeps its repeats and release, the modifiers and the system's keys stay the app's, a key pressed
// before the menu opened keeps its repeats and lets go normally -- asking for the lease only when the answer matters.
#include <stdio.h>
#include "../common/MenuKeys.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, long long got, long long want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %lld, want %lld)\n", what, got, want); } else printf("PASS  %s\n", what); }
static int asked = 0;
static int MenuOpen(void) { asked++; return 1; }
static int MenuShut(void) { asked++; return 0; }
#define kCmd (1LL << 20)
#define kCtrl (1LL << 18)
#define kAlt (1LL << 19)
#define kShift (1LL << 17)
int main(void) {
    // the lease
    double now = 815000000000.0;   // (CFAbsoluteTime x 1000, November 2026)
    Expect("no lease (0): no menu has the keys", MSBDMenuKeysFresh(0, now), 0);
    Expect("a lease just given holds", MSBDMenuKeysFresh(MSBDMenuKeysStamp(now), now), 1);
    Expect("a lease renewed every second holds in between (1.0 s old)", MSBDMenuKeysFresh((uint64_t)(now - kMSBDMenuKeysRenewMs), now), 1);
    Expect("  ... and with a late renewal (2.4 s old)", MSBDMenuKeysFresh((uint64_t)(now - 2400.0), now), 1);
    Expect("a lease nobody renewed for 2.6 s (SpringBoard went away mid-menu): lapsed, the app keeps its keys", MSBDMenuKeysFresh((uint64_t)(now - 2600.0), now), 0);
    Expect("an hour-old lease: lapsed", MSBDMenuKeysFresh((uint64_t)(now - 3600000.0), now), 0);
    Expect("a lease 0.5 s in the future (the clock set back a little): holds", MSBDMenuKeysFresh((uint64_t)(now + 500.0), now), 1);
    Expect("a lease 1.5 s in the future: not trusted", MSBDMenuKeysFresh((uint64_t)(now + 1500.0), now), 0);
    Expect("the stamp is never 0 (0 = no menu)", (long long)MSBDMenuKeysStamp(0.4), 1);
    Expect("the stamp is the time in ms", (long long)MSBDMenuKeysStamp(12345.7), 12345);
    Expect("the renewal comes well inside the lapse time", kMSBDMenuKeysRenewMs * 2.0 <= kMSBDMenuKeysStaleMs, 1);

    // the keys
    MSBDMenuKeyHeld h = {{0, 0}, {0, 0}};
    asked = 0;
    Expect("Esc pressed while a menu has the keys: closes the menu (and the app does not get it)", MSBDMenuKeyAct(&h, 0x29, 1, 0, MenuOpen), MSBDMenuKeyClose);
    Expect("  ... the lease was asked once", asked, 1);
    asked = 0;
    Expect("  ... its repeat is the menu's too, without asking again", MSBDMenuKeyAct(&h, 0x29, 1, 0, MenuShut), MSBDMenuKeyTake);
    Expect("  ... and its release, even with the menu gone", MSBDMenuKeyAct(&h, 0x29, 0, 0, MenuShut), MSBDMenuKeyTake);
    Expect("  ... nothing asked for the repeat and the release", asked, 0);
    Expect("  ... after that release Esc is free again: with no menu it is the app's", MSBDMenuKeyAct(&h, 0x29, 1, 0, MenuShut), MSBDMenuKeyPass);
    Expect("  ... (and that release is the app's)", MSBDMenuKeyAct(&h, 0x29, 0, 0, MenuShut), MSBDMenuKeyPass);
    Expect("Esc with Command: taken, not a close (a shortcut, not the menu's Esc)", MSBDMenuKeyAct(&h, 0x29, 1, kCmd, MenuOpen), MSBDMenuKeyTake);
    MSBDMenuKeyAct(&h, 0x29, 0, kCmd, MenuOpen);
    Expect("Esc with Control: taken, not a close", MSBDMenuKeyAct(&h, 0x29, 1, kCtrl, MenuOpen), MSBDMenuKeyTake);
    MSBDMenuKeyAct(&h, 0x29, 0, kCtrl, MenuOpen);
    Expect("Esc with Option: taken, not a close", MSBDMenuKeyAct(&h, 0x29, 1, kAlt, MenuOpen), MSBDMenuKeyTake);
    MSBDMenuKeyAct(&h, 0x29, 0, kAlt, MenuOpen);
    Expect("Esc with Shift: still the menu's Esc (closes)", MSBDMenuKeyAct(&h, 0x29, 1, kShift, MenuOpen), MSBDMenuKeyClose);
    MSBDMenuKeyAct(&h, 0x29, 0, kShift, MenuOpen);
    struct { int code; const char *name; } taken[] = { {0x04, "a"}, {0x1D, "z"}, {0x1E, "1"}, {0x28, "Return"}, {0x2A, "Delete"}, {0x2B, "Tab"}, {0x2C, "Space"},
        {0x35, "grave"}, {0x3A, "F1"}, {0x45, "F12"}, {0x4F, "Right Arrow"}, {0x50, "Left Arrow"}, {0x51, "Down Arrow"}, {0x52, "Up Arrow"}, {0x58, "keypad Enter"},
        {0x64, "the ISO key"}, {0x65, "Application"} };
    for (unsigned i = 0; i < sizeof taken / sizeof taken[0]; i++) {
        char what[128]; snprintf(what, sizeof what, "%s pressed while a menu has the keys: the menu's, the app does not see it (as with the focus lock)", taken[i].name);
        Expect(what, MSBDMenuKeyAct(&h, taken[i].code, 1, 0, MenuOpen), MSBDMenuKeyTake);
        snprintf(what, sizeof what, "  ... its release too");
        Expect(what, MSBDMenuKeyAct(&h, taken[i].code, 0, 0, MenuShut), MSBDMenuKeyTake);
    }
    asked = 0;
    int mods[] = { 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7 };
    int passed = 1;
    for (unsigned i = 0; i < 8; i++) passed &= MSBDMenuKeyAct(&h, mods[i], 1, 0, MenuOpen) == MSBDMenuKeyPass && MSBDMenuKeyAct(&h, mods[i], 0, 0, MenuOpen) == MSBDMenuKeyPass;
    Expect("the modifiers (Control, Shift, Option, Command, both sides) stay the app's, pressed and released", passed, 1);
    Expect("  ... and the lease is not asked for them", asked, 0);
    int sys[] = { 0x66, 0x7F, 0x80, 0x81, 0x68, 0x73 };
    passed = 1;
    for (unsigned i = 0; i < 6; i++) passed &= MSBDMenuKeyAct(&h, sys[i], 1, 0, MenuOpen) == MSBDMenuKeyPass;
    Expect("Power, Mute, Volume Up / Down, F13, F24 (past 0x65): not the menu's", passed, 1);
    Expect("  ... nothing asked", asked, 0);
    Expect("0x03 (no key) and negative codes: passed on", MSBDMenuKeyAct(&h, 0x03, 1, 0, MenuOpen) == MSBDMenuKeyPass && MSBDMenuKeyAct(&h, -1, 1, 0, MenuOpen) == MSBDMenuKeyPass, 1);
    Expect("a release of a key pressed before the menu opened: the app's (it lets go normally)", MSBDMenuKeyAct(&h, 0x07, 0, 0, MenuOpen), MSBDMenuKeyPass);
    Expect("  ... nothing asked for a release", asked, 0);
    asked = 0;
    Expect("a key pressed with no menu: the app's", MSBDMenuKeyAct(&h, 0x07, 1, 0, MenuShut), MSBDMenuKeyPass);
    Expect("  ... the lease was asked once", asked, 1);
    Expect("  ... and its release is the app's", MSBDMenuKeyAct(&h, 0x07, 0, 0, MenuOpen), MSBDMenuKeyPass);
    Expect("no lease reader at all: everything is the app's", MSBDMenuKeyAct(&h, 0x29, 1, 0, NULL), MSBDMenuKeyPass);
    MSBDMenuKeyAct(&h, 0x29, 0, 0, NULL);
    // a key held from before the menu opened (code review): the app saw it go down, so it sees its repeats and its release, menu or not
    MSBDMenuKeyHeld k = {{0, 0}, {0, 0}};
    asked = 0;
    Expect("Left Arrow pressed in a text field, no menu: the app's", MSBDMenuKeyAct(&k, 0x50, 1, 0, MenuShut), MSBDMenuKeyPass);
    Expect("  ... the lease asked once", asked, 1);
    asked = 0;
    Expect("  ... still held, a menu opens: its repeat is the app's, not the menu's", MSBDMenuKeyAct(&k, 0x50, 1, 0, MenuOpen), MSBDMenuKeyPass);
    Expect("  ... and the next repeats", MSBDMenuKeyAct(&k, 0x50, 1, 0, MenuOpen) == MSBDMenuKeyPass && MSBDMenuKeyAct(&k, 0x50, 1, 0, MenuOpen) == MSBDMenuKeyPass, 1);
    Expect("  ... let go with the menu open: the release is the app's (the app sees the key come up)", MSBDMenuKeyAct(&k, 0x50, 0, 0, MenuOpen), MSBDMenuKeyPass);
    Expect("  ... nothing asked for its repeats and release", asked, 0);
    Expect("  ... pressed again with the menu still open: now the menu's", MSBDMenuKeyAct(&k, 0x50, 1, 0, MenuOpen), MSBDMenuKeyTake);
    Expect("  ... and that press's release too", MSBDMenuKeyAct(&k, 0x50, 0, 0, MenuShut), MSBDMenuKeyTake);
    Expect("Delete pressed before the menu, released during it (no repeat): the app's", MSBDMenuKeyAct(&k, 0x2A, 1, 0, MenuShut) == MSBDMenuKeyPass && MSBDMenuKeyAct(&k, 0x2A, 0, 0, MenuOpen) == MSBDMenuKeyPass, 1);
    Expect("two keys at once: x held from before the menu goes on in the app, Down pressed during it is the menu's",
           MSBDMenuKeyAct(&k, 0x1B, 1, 0, MenuShut) == MSBDMenuKeyPass && MSBDMenuKeyAct(&k, 0x51, 1, 0, MenuOpen) == MSBDMenuKeyTake
           && MSBDMenuKeyAct(&k, 0x1B, 1, 0, MenuOpen) == MSBDMenuKeyPass && MSBDMenuKeyAct(&k, 0x51, 1, 0, MenuOpen) == MSBDMenuKeyTake
           && MSBDMenuKeyAct(&k, 0x1B, 0, 0, MenuOpen) == MSBDMenuKeyPass && MSBDMenuKeyAct(&k, 0x51, 0, 0, MenuOpen) == MSBDMenuKeyTake, 1);
    Expect("Esc held from before the menu: its repeat does not close the menu (the app's)", MSBDMenuKeyAct(&k, 0x29, 1, 0, MenuShut) == MSBDMenuKeyPass && MSBDMenuKeyAct(&k, 0x29, 1, 0, MenuOpen) == MSBDMenuKeyPass, 1);
    Expect("  ... its release the app's; Esc pressed again: closes the menu", MSBDMenuKeyAct(&k, 0x29, 0, 0, MenuOpen) == MSBDMenuKeyPass && MSBDMenuKeyAct(&k, 0x29, 1, 0, MenuOpen) == MSBDMenuKeyClose, 1);
    MSBDMenuKeyAct(&k, 0x29, 0, 0, MenuOpen);
    Expect("after every release, nobody has a key (both sets empty)", k.held[0] == 0 && k.held[1] == 0 && k.app[0] == 0 && k.app[1] == 0, 1);
    Expect("Command-C while a menu has the keys: the menu's (the app does not copy behind the open menu, as with the lock)", MSBDMenuKeyAct(&h, 0x06, 1, kCmd, MenuOpen), MSBDMenuKeyTake);
    Expect("  ... its release too", MSBDMenuKeyAct(&h, 0x06, 0, kCmd, MenuShut), MSBDMenuKeyTake);
    MSBDMenuKeyHeld h2 = {{0, 0}, {0, 0}};
    MSBDMenuKeySetHeld(&h2, 0x29, 1); MSBDMenuKeySetHeld(&h2, 0x65, 1); MSBDMenuKeySetHeld(&h2, 0x40, 1);
    Expect("the held set keeps keys in both words (0x29, 0x40, 0x65)", MSBDMenuKeyIsHeld(&h2, 0x29) && MSBDMenuKeyIsHeld(&h2, 0x40) && MSBDMenuKeyIsHeld(&h2, 0x65) && !MSBDMenuKeyIsHeld(&h2, 0x28) && !MSBDMenuKeyIsHeld(&h2, 0x66), 1);
    MSBDMenuKeySetHeld(&h2, 0x29, 0); MSBDMenuKeySetHeld(&h2, 200, 1); MSBDMenuKeySetHeld(&h2, -5, 1);
    Expect("  ... lets one go without touching the others, and ignores codes outside 0-127", !MSBDMenuKeyIsHeld(&h2, 0x29) && MSBDMenuKeyIsHeld(&h2, 0x40) && !MSBDMenuKeyIsHeld(&h2, 200) && !MSBDMenuKeyIsHeld(&h2, -5), 1);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
