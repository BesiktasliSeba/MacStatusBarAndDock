// test-windowkeys.c -- Mac test of statusbar/WindowKeysRule.h (1.8.3 item 3): macOS 15's fixed tiling shortcuts with the Globe key as Fn, each the
// action Apple's page gives it, nothing else matching, and no clash with iPadOS's own Globe shortcuts or our other keys. Run by test-windowkeys.sh.
#include <stdio.h>
#include <string.h>
#include "../statusbar/WindowKeysRule.h"
static int fails = 0, checks = 0;
static void Yes(const char *what, int ok) { checks++; if (ok) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } }
static int Is(MSBDWinKeyAction a, int kind, int count, const char *s0, const char *s1, const char *s2) {
    if (a.kind != kind || a.count != count) return 0;
    const char *want[3] = { s0, s1, s2 };
    for (int i = 0; i < count; i++) if (!a.slots[i] || !want[i] || strcmp(a.slots[i], want[i])) return 0;
    return 1;
}
#define GC (kMSBDModGlobe | kMSBDModControl)
int main(void) {
    // ---- Move & Resize (Apple: Fn-Control-F / C / arrows / R) ----
    Yes("Globe-Control-F: Fill", Is(MSBDWinKeyActionFor(kMSBDWinKeyF, GC), kMSBDWinKeyActLayout, 1, "fill", 0, 0));
    Yes("Globe-Control-C: Center, as macOS 15's (the window at its own size in the middle: not the Window menu's middle place)", MSBDWinKeyActionFor(kMSBDWinKeyC, GC).kind == kMSBDWinKeyActCenter && MSBDWinKeyActionFor(kMSBDWinKeyC, GC).count == 1);
    Yes("Globe-Control-Left Arrow: the left half", Is(MSBDWinKeyActionFor(kMSBDWinKeyLeft, GC), kMSBDWinKeyActLayout, 1, "left", 0, 0));
    Yes("Globe-Control-Right Arrow: the right half", Is(MSBDWinKeyActionFor(kMSBDWinKeyRight, GC), kMSBDWinKeyActLayout, 1, "right", 0, 0));
    Yes("Globe-Control-Up Arrow: the top half", Is(MSBDWinKeyActionFor(kMSBDWinKeyUp, GC), kMSBDWinKeyActLayout, 1, "top", 0, 0));
    Yes("Globe-Control-Down Arrow: the bottom half", Is(MSBDWinKeyActionFor(kMSBDWinKeyDown, GC), kMSBDWinKeyActLayout, 1, "bottom", 0, 0));
    Yes("Globe-Control-R: Return to Previous Size", MSBDWinKeyActionFor(kMSBDWinKeyR, GC).kind == kMSBDWinKeyActPrevious);
    // ---- Arrange (Apple: Fn-Control-Shift-arrows two windows, Fn-Control-Option-Shift-arrows three) ----
    Yes("Globe-Control-Shift-Left: Left & Right (the front window left, the one behind it right)", Is(MSBDWinKeyActionFor(kMSBDWinKeyLeft, GC | kMSBDModShift), kMSBDWinKeyActArrange, 2, "left", "right", 0));
    Yes("Globe-Control-Shift-Right: Right & Left", Is(MSBDWinKeyActionFor(kMSBDWinKeyRight, GC | kMSBDModShift), kMSBDWinKeyActArrange, 2, "right", "left", 0));
    Yes("Globe-Control-Shift-Up: Top & Bottom", Is(MSBDWinKeyActionFor(kMSBDWinKeyUp, GC | kMSBDModShift), kMSBDWinKeyActArrange, 2, "top", "bottom", 0));
    Yes("Globe-Control-Shift-Down: Bottom & Top", Is(MSBDWinKeyActionFor(kMSBDWinKeyDown, GC | kMSBDModShift), kMSBDWinKeyActArrange, 2, "bottom", "top", 0));
    unsigned long long GCOS = GC | kMSBDModOption | kMSBDModShift;
    Yes("Globe-Control-Option-Shift-Left: Left & Quarters (top right, then bottom right)", Is(MSBDWinKeyActionFor(kMSBDWinKeyLeft, GCOS), kMSBDWinKeyActArrange, 3, "left", "topright", "bottomright"));
    Yes("Globe-Control-Option-Shift-Right: Right & Quarters (top left, then bottom left)", Is(MSBDWinKeyActionFor(kMSBDWinKeyRight, GCOS), kMSBDWinKeyActArrange, 3, "right", "topleft", "bottomleft"));
    Yes("Globe-Control-Option-Shift-Up: Top & Quarters (bottom left, then bottom right)", Is(MSBDWinKeyActionFor(kMSBDWinKeyUp, GCOS), kMSBDWinKeyActArrange, 3, "top", "bottomleft", "bottomright"));
    Yes("Globe-Control-Option-Shift-Down: Bottom & Quarters (top left, then top right)", Is(MSBDWinKeyActionFor(kMSBDWinKeyDown, GCOS), kMSBDWinKeyActArrange, 3, "bottom", "topleft", "topright"));
    Yes("fifteen shortcuts, as Apple lists them (the quarters, Quarters and the full-screen tiles have none)", kMSBDWinKeyRowCount == 15);
    // ---- the keys as pressed: their HID usages (UIKey.keyCode), each row by its exact modifiers ----
    Yes("HID usages: Left 0x50, Right 0x4F, Up 0x52, Down 0x51, F 0x09, C 0x06, R 0x15", MSBDWinKeyForHIDUsage(0x50) == kMSBDWinKeyLeft && MSBDWinKeyForHIDUsage(0x4F) == kMSBDWinKeyRight
        && MSBDWinKeyForHIDUsage(0x52) == kMSBDWinKeyUp && MSBDWinKeyForHIDUsage(0x51) == kMSBDWinKeyDown && MSBDWinKeyForHIDUsage(0x09) == kMSBDWinKeyF
        && MSBDWinKeyForHIDUsage(0x06) == kMSBDWinKeyC && MSBDWinKeyForHIDUsage(0x15) == kMSBDWinKeyR);
    Yes("  ... any other key is none of ours (Tab, A, the Globe key itself, Control)", MSBDWinKeyForHIDUsage(0x2B) < 0 && MSBDWinKeyForHIDUsage(0x04) < 0 && MSBDWinKeyForHIDUsage(0x03) < 0 && MSBDWinKeyForHIDUsage(0xE0) < 0);
    Yes("Globe-Control-Left as SpringBoard got it on 15.6.1 (key 0x50, modifiers 0x840000): the left half's row", MSBDWinKeyRowFor(MSBDWinKeyForHIDUsage(0x50), 0x840000) == 2);
    Yes("  ... with Shift (0x860000): Left & Right", MSBDWinKeyRowFor(MSBDWinKeyForHIDUsage(0x50), 0x860000) == 7);
    Yes("  ... Control-Left alone (0x40000, the Mac Switcher's): no row", MSBDWinKeyRowFor(MSBDWinKeyForHIDUsage(0x50), 0x40000) < 0);
    // ---- nothing else ----
    Yes("Control-Left alone (the Mac Switcher's desktops): not ours", MSBDWinKeyActionFor(kMSBDWinKeyLeft, kMSBDModControl).kind == kMSBDWinKeyActNone);
    Yes("Globe-Left alone (iPadOS: the apps): not ours", MSBDWinKeyActionFor(kMSBDWinKeyLeft, kMSBDModGlobe).kind == kMSBDWinKeyActNone);
    Yes("Option-Globe-Left (iPadOS: Slide Over): not ours", MSBDWinKeyActionFor(kMSBDWinKeyLeft, kMSBDModGlobe | kMSBDModOption).kind == kMSBDWinKeyActNone);
    Yes("Globe-Up (iPadOS: the App Switcher): not ours", MSBDWinKeyActionFor(kMSBDWinKeyUp, kMSBDModGlobe).kind == kMSBDWinKeyActNone);
    Yes("Globe-C (iPadOS: Control Center): not ours", MSBDWinKeyActionFor(kMSBDWinKeyC, kMSBDModGlobe).kind == kMSBDWinKeyActNone);
    Yes("Globe-F (iPadOS: full screen): not ours", MSBDWinKeyActionFor(kMSBDWinKeyF, kMSBDModGlobe).kind == kMSBDWinKeyActNone);
    Yes("Globe-Control-Command-Left (an extra modifier): not ours", MSBDWinKeyActionFor(kMSBDWinKeyLeft, GC | kMSBDModCommand).kind == kMSBDWinKeyActNone);
    Yes("Globe-Control-Option-Left (Option without Shift): not ours", MSBDWinKeyActionFor(kMSBDWinKeyLeft, GC | kMSBDModOption).kind == kMSBDWinKeyActNone);
    Yes("Globe-Control-Shift-F (no arrangement on F): not ours", MSBDWinKeyActionFor(kMSBDWinKeyF, GC | kMSBDModShift).kind == kMSBDWinKeyActNone);
    Yes("Caps Lock and the keypad bit do not count (Globe-Control-Left with them: the left half)", Is(MSBDWinKeyActionFor(kMSBDWinKeyLeft, GC | (1ULL << 16) | (1ULL << 21)), kMSBDWinKeyActLayout, 1, "left", 0, 0));
    // ---- every row holds Globe and Control, none is Command (Cmd-H stays iPadOS's Home), no two rows are the same keys ----
    int allGC = 1, noCmd = 1, unique = 1;
    for (size_t i = 0; i < kMSBDWinKeyRowCount; i++) {
        if ((kMSBDWinKeyRows[i].mods & GC) != GC) allGC = 0;
        if (kMSBDWinKeyRows[i].mods & kMSBDModCommand) noCmd = 0;
        for (size_t j = i + 1; j < kMSBDWinKeyRowCount; j++) if (kMSBDWinKeyRows[i].key == kMSBDWinKeyRows[j].key && kMSBDWinKeyRows[i].mods == kMSBDWinKeyRows[j].mods) unique = 0;
    }
    Yes("every shortcut holds Globe and Control (apart from every iPadOS Globe shortcut and the Mac Switcher's Control-arrows)", allGC);
    Yes("none holds Command", noCmd);
    Yes("no two shortcuts on the same keys", unique);
    // ---- F, C and R by the letter the layout types, as macOS (review 1.8.3 F1); the arrows by their place ----
    Yes("QWERTY: the key at F's place types f -- F", MSBDWinKeyFor(0x09, "f") == kMSBDWinKeyF && MSBDWinKeyFor(0x06, "c") == kMSBDWinKeyC && MSBDWinKeyFor(0x15, "r") == kMSBDWinKeyR);
    Yes("Dvorak: F is where QWERTY has Y (0x1C types f), C where it has I (0x0C), R where it has O (0x12)", MSBDWinKeyFor(0x1C, "f") == kMSBDWinKeyF && MSBDWinKeyFor(0x0C, "c") == kMSBDWinKeyC && MSBDWinKeyFor(0x12, "r") == kMSBDWinKeyR);
    Yes("  ... and QWERTY's F place types u there: none of ours", MSBDWinKeyFor(0x09, "u") < 0 && MSBDWinKeyFor(0x06, "j") < 0 && MSBDWinKeyFor(0x15, "p") < 0);
    Yes("Colemak: R where QWERTY has S (0x16 types r)", MSBDWinKeyFor(0x16, "r") == kMSBDWinKeyR);
    Yes("AZERTY and QWERTZ: F, C and R where QWERTY has them", MSBDWinKeyFor(0x09, "f") == kMSBDWinKeyF && MSBDWinKeyFor(0x06, "c") == kMSBDWinKeyC && MSBDWinKeyFor(0x15, "r") == kMSBDWinKeyR);
    Yes("Caps Lock (F typed): F", MSBDWinKeyFor(0x09, "F") == kMSBDWinKeyF);
    Yes("a layout with no Latin letter there (Russian: \"\xd0\xb0\" at F's place): the QWERTY place, as macOS falls back", MSBDWinKeyFor(0x09, "\xd0\xb0") == kMSBDWinKeyF && MSBDWinKeyFor(0x06, "\xd1\x81") == kMSBDWinKeyC && MSBDWinKeyFor(0x15, "\xd0\xba") == kMSBDWinKeyR);
    Yes("  ... no character read (none, or empty): the place", MSBDWinKeyFor(0x09, 0) == kMSBDWinKeyF && MSBDWinKeyFor(0x15, "") == kMSBDWinKeyR);
    Yes("  ... another place with no Latin letter: none of ours", MSBDWinKeyFor(0x04, "\xd1\x84") < 0);
    Yes("the arrows by their place whatever they type", MSBDWinKeyFor(0x50, "UIKeyInputLeftArrow") == kMSBDWinKeyLeft && MSBDWinKeyFor(0x4F, 0) == kMSBDWinKeyRight && MSBDWinKeyFor(0x52, "x") == kMSBDWinKeyUp && MSBDWinKeyFor(0x51, "") == kMSBDWinKeyDown);
    Yes("Dvorak's Globe-Control-F as pressed (0x1C typing f, 0x840000): Fill's row", MSBDWinKeyRowFor(MSBDWinKeyFor(0x1C, "f"), 0x840000) == 0);
    Yes("  ... its Globe-Control-U (0x09 typing u): no row", MSBDWinKeyRowFor(MSBDWinKeyFor(0x09, "u"), 0x840000) < 0);
    // ---- Center keeps the window's size, in the middle of the desktop (macOS 15's) ----
    CGRect desk = CGRectMake(0, 30, 1180, 730), cen = MSBDWinCenterKeepingSize(CGRectMake(40, 60, 600, 400), desk);
    Yes("Center: 600 x 400 stays 600 x 400, its middle the desktop's", cen.size.width == 600 && cen.size.height == 400 && cen.origin.x == 290 && cen.origin.y == 195);
    cen = MSBDWinCenterKeepingSize(CGRectMake(0, 0, 1400, 900), desk);
    Yes("  ... a window bigger than the desktop: as big as it, there", CGRectEqualToRect(cen, desk));
    cen = MSBDWinCenterKeepingSize(CGRectMake(10, 10, 601, 401), desk);
    Yes("  ... whole points", cen.origin.x == round(cen.origin.x) && cen.origin.y == round(cen.origin.y) && cen.size.width == 601);
    Yes("  ... no window or no desktop: nothing", CGRectIsNull(MSBDWinCenterKeepingSize(CGRectNull, desk)) && CGRectIsNull(MSBDWinCenterKeepingSize(CGRectMake(0, 0, 10, 10), CGRectNull)));
    Yes("  ... and no tile: no Return to Previous Size record for it", !MSBDWinIsTileName("center"));
    // ---- Return to Previous Size: the tiles and the record ----
    Yes("the tiles: Fill, the halves, the quarters", MSBDWinIsTileName("fill") && MSBDWinIsTileName("left") && MSBDWinIsTileName("bottomright") && !MSBDWinIsTileName("small") && !MSBDWinIsTileName("large") && !MSBDWinIsTileName(0));
    Yes("a window in no tile is tiled: its frame now is the record", MSBDWinPrevTake(false));
    Yes("  ... one in a tile already keeps the record it has (left, then right: back to its size before the first)", !MSBDWinPrevTake(true));
    Yes("Globe-Control-R in a tile with a record: back", MSBDWinPrevOnReturn(true, true) == kMSBDWinPrevBack);
    Yes("  ... moved out of its tile by hand since: the record only goes", MSBDWinPrevOnReturn(false, true) == kMSBDWinPrevDrop);
    Yes("  ... no record: nothing", MSBDWinPrevOnReturn(true, false) == kMSBDWinPrevNothing && MSBDWinPrevOnReturn(false, false) == kMSBDWinPrevNothing);
    Yes("in a tile: each side within 16 pt of the tile's", MSBDWinNear(CGRectMake(0, 30, 590, 730), CGRectMake(10, 40, 580, 720)) && !MSBDWinNear(CGRectMake(0, 30, 590, 730), CGRectMake(0, 30, 610, 730)));
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
