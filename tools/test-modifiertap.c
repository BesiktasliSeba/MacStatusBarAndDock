// test-modifiertap.c -- Mac test of common/ModifierTap.h (1.8.3 item 3): the volume and backlight chords with Window Tiling Keys off (at the press, as
// before) and on (at the release, and never when a shortcut was typed while they were held). Run by test-modifiertap.sh.
#include <stdio.h>
#include "../common/ModifierTap.h"
static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
enum { OPTION = 226, CONTROL = 224, SHIFT = 225, LEFT = 80 };
int main(void) {
    MSBDModTap t = { 0, false };
    Int("keys off: Globe + Control acts as it goes down (as before)", MSBDModTapDown(&t, CONTROL, true, false, false), kMSBDModTapActNow);
    Int("  ... and nothing at its release", MSBDModTapUp(&t, CONTROL), kMSBDModTapNothing);
    t = (MSBDModTap){ 0, false };
    Int("keys on: Globe + Control waits", MSBDModTapDown(&t, CONTROL, true, false, true), kMSBDModTapWait);
    Int("  ... and acts at its release (a tap)", MSBDModTapUp(&t, CONTROL), kMSBDModTapActOnRelease);
    Int("  ... once (the release handed over again: nothing)", MSBDModTapUp(&t, CONTROL), kMSBDModTapNothing);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, CONTROL, true, false, true);
    Int("Globe-Control-Left typed: the arrow is another key", MSBDModTapDown(&t, LEFT, false, false, true), kMSBDModTapNothing);
    Int("  ... so the volume stays at Control's release", MSBDModTapUp(&t, CONTROL), kMSBDModTapNothing);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, CONTROL, true, false, true);
    MSBDModTapUsed(&t);
    Int("a window key ran while Globe + Control was held (told by the window keys): nothing at the release", MSBDModTapUp(&t, CONTROL), kMSBDModTapNothing);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, CONTROL, true, false, true);
    Int("Shift pressed on the way to Globe-Control-Shift-Left: another key", MSBDModTapDown(&t, SHIFT, false, false, true), kMSBDModTapNothing);
    Int("  ... the chord is no tap", MSBDModTapUp(&t, CONTROL), kMSBDModTapNothing);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, OPTION, true, false, true);
    Int("the same press handed over twice (17.5.1): still waiting", MSBDModTapDown(&t, OPTION, true, false, true), kMSBDModTapWait);
    Int("  ... one step at the release", MSBDModTapUp(&t, OPTION), kMSBDModTapActOnRelease);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, OPTION, true, false, true);
    Int("Control while Option is held (both chord keys at once, Option's flag on the press): neither is a tap", MSBDModTapDown(&t, CONTROL, true, true, true), kMSBDModTapNothing);
    Int("  ... Option's release does nothing", MSBDModTapUp(&t, OPTION), kMSBDModTapNothing);
    Int("  ... nor Control's", MSBDModTapUp(&t, CONTROL), kMSBDModTapNothing);
    MSBDModTapDown(&t, OPTION, true, false, true); MSBDModTapUp(&t, OPTION);
    Int("two taps one after the other (Option, then Control): the second waits", MSBDModTapDown(&t, CONTROL, true, false, true), kMSBDModTapWait);
    Int("  ... and acts at its release", MSBDModTapUp(&t, CONTROL), kMSBDModTapActOnRelease);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, CONTROL, true, false, true);
    // (review F3: Control's release never reached SpringBoard; minutes later Control-C in an app -- Control down without Globe, then up)
    Int("a release that never came, then the same key down without its chord (Control-C in an app): nothing", MSBDModTapDown(&t, CONTROL, false, false, true), kMSBDModTapNothing);
    Int("  ... and no volume step at that key's release", MSBDModTapUp(&t, CONTROL), kMSBDModTapNothing);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, OPTION, true, false, true);
    MSBDModTapDown(&t, OPTION, false, false, true);
    Int("Globe let go before Option (Option down again without Globe, the same key): no tap either", MSBDModTapUp(&t, OPTION), kMSBDModTapNothing);
    t = (MSBDModTap){ 0, false };
    Int("another key's release with nothing armed: nothing", MSBDModTapUp(&t, LEFT), kMSBDModTapNothing);
    Int("no state: nothing", MSBDModTapDown(NULL, CONTROL, true, false, true), kMSBDModTapNothing);
    // ---- the keys offered: SpringBoard's state (its pid << 32 | 1), read in SpringBoard ----
    Int("offered by this SpringBoard: the chords wait for their release", MSBDWindowKeysOfferedIn(MSBDWindowKeysOfferedState(true, 4321), 4321), 1);
    Int("  ... not offered (the switch off, or no window engine of ours): at the press, as in 1.8.2.2", MSBDWindowKeysOfferedIn(MSBDWindowKeysOfferedState(false, 4321), 4321), 0);
    Int("  ... a state left by an earlier SpringBoard (another pid): not offered", MSBDWindowKeysOfferedIn(MSBDWindowKeysOfferedState(true, 1234), 4321), 0);
    Int("  ... never set (0): not offered", MSBDWindowKeysOfferedIn(0, 4321), 0);
    t = (MSBDModTap){ 0, false };   // (Globe-Control-Option-Shift-Left, the keys offered: Control waits, then Option, the other chord key, goes down)
    Int("Globe-Control-Option-Shift-Left: Control down, waiting", MSBDModTapDown(&t, CONTROL, true, false, true), kMSBDModTapWait);
    Int("  ... Option down while Control is held: no tap of either -- the chord must not act on it (1.8.3 regression F1)", MSBDModTapDown(&t, OPTION, true, true, true), kMSBDModTapNothing);
    Int("  ... nothing at either release", MSBDModTapUp(&t, OPTION) == kMSBDModTapNothing && MSBDModTapUp(&t, CONTROL) == kMSBDModTapNothing, 1);
    t = (MSBDModTap){ 0, false };
    Int("the keys not offered: the chord acts at its press, every press (1.8.2.2)", MSBDModTapDown(&t, OPTION, true, false, false) == kMSBDModTapActNow && MSBDModTapDown(&t, OPTION, true, false, false) == kMSBDModTapActNow, 1);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, OPTION, true, false, true);
    Int("the other chord key down while one waits, even without its flag on the press: neither is a tap", MSBDModTapDown(&t, CONTROL, true, false, true), kMSBDModTapNothing);
    Int("  ... nothing at either release", MSBDModTapUp(&t, CONTROL) == kMSBDModTapNothing && MSBDModTapUp(&t, OPTION) == kMSBDModTapNothing, 1);
    // ---- 1.8.3 regression F1 on the M1: SpringBoard is handed each press twice there, the keys offered ----
    t = (MSBDModTap){ 0, false };
    Int("M1, Globe-Control-Option: Control down, waiting", MSBDModTapDown(&t, CONTROL, true, false, true), kMSBDModTapWait);
    Int("  ... Control handed over again: still waiting", MSBDModTapDown(&t, CONTROL, true, false, true), kMSBDModTapWait);
    Int("  ... Option down, Control's flag on it: no tap of either", MSBDModTapDown(&t, OPTION, true, true, true), kMSBDModTapNothing);
    Int("  ... Option handed over again, Control's flag still on it: no tap either (it waited again, and the volume went up at Option's release)", MSBDModTapDown(&t, OPTION, true, true, true), kMSBDModTapNothing);
    Int("  ... nothing at Option's release (both deliveries) nor Control's", MSBDModTapUp(&t, OPTION) == kMSBDModTapNothing && MSBDModTapUp(&t, OPTION) == kMSBDModTapNothing
        && MSBDModTapUp(&t, CONTROL) == kMSBDModTapNothing && MSBDModTapUp(&t, CONTROL) == kMSBDModTapNothing, 1);
    t = (MSBDModTap){ 0, false };
    Int("M1, Globe-Option-Control: Option waits (twice), Control with Option's flag (twice) is no tap (the volume went down at Control's release)",
        MSBDModTapDown(&t, OPTION, true, false, true) == kMSBDModTapWait && MSBDModTapDown(&t, OPTION, true, false, true) == kMSBDModTapWait
        && MSBDModTapDown(&t, CONTROL, true, true, true) == kMSBDModTapNothing && MSBDModTapDown(&t, CONTROL, true, true, true) == kMSBDModTapNothing, 1);
    Int("  ... nothing at either release", MSBDModTapUp(&t, CONTROL) == kMSBDModTapNothing && MSBDModTapUp(&t, CONTROL) == kMSBDModTapNothing
        && MSBDModTapUp(&t, OPTION) == kMSBDModTapNothing && MSBDModTapUp(&t, OPTION) == kMSBDModTapNothing, 1);
    t = (MSBDModTap){ 0, false };
    MSBDModTapDown(&t, CONTROL, true, false, true); MSBDModTapDown(&t, OPTION, true, true, true); MSBDModTapUp(&t, OPTION);
    Int("Control still held, Option tapped again: no tap (both chord keys held)", MSBDModTapDown(&t, OPTION, true, true, true), kMSBDModTapNothing);
    Int("  ... nothing at its release", MSBDModTapUp(&t, OPTION), kMSBDModTapNothing);
    MSBDModTapUp(&t, CONTROL);
    Int("both let go, then Globe + Option alone: a tap again", MSBDModTapDown(&t, OPTION, true, false, true) == kMSBDModTapWait && MSBDModTapUp(&t, OPTION) == kMSBDModTapActOnRelease, 1);
    t = (MSBDModTap){ 0, false };
    Int("the keys not offered, Option with Control held: acts at its press, as in 1.8.2.2", MSBDModTapDown(&t, OPTION, true, true, false), kMSBDModTapActNow);
    // ---- the other chord key, from the press's own modifier flags (Globe 0x800000, Option 0x80000, Control 0x40000, Shift 0x20000) ----
    Int("Option's press with Control's flag: the other chord key held", MSBDModTapOtherHeld(OPTION, 0x800000ULL | 0x80000ULL | 0x40000ULL), 1);
    Int("  ... with Globe's and its own flag only: not", MSBDModTapOtherHeld(OPTION, 0x800000ULL | 0x80000ULL), 0);
    Int("Control's press with Option's flag: held", MSBDModTapOtherHeld(CONTROL, 0x800000ULL | 0x40000ULL | 0x80000ULL), 1);
    Int("  ... with Globe's, Shift's and its own flag: not", MSBDModTapOtherHeld(CONTROL, 0x800000ULL | 0x20000ULL | 0x40000ULL), 0);
    Int("Shift (no chord key) with both flags: not", MSBDModTapOtherHeld(SHIFT, 0x80000ULL | 0x40000ULL), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
