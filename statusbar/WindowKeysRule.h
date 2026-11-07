// WindowKeysRule.h -- Window Tiling Keys (Settings > Keyboard, 1.8.3 item 3): macOS's own fixed tiling shortcuts on an iPad keyboard, its Globe key
// for the Mac's Fn. Plain C, so the Mac test (tools/test-windowkeys.c) runs this very map; statusbar/WindowKeys.h gives the keys to SpringBoard.
// The set is macOS Sequoia 15's, from Apple's own page (Mac User Guide, "Tile app windows on Mac", 15.0; the same on every later macOS since):
//   Move & Resize: Fn-Control-F Fill, Fn-Control-C Center (the window at its own size in the middle of the desktop), Fn-Control-Left / Right /
//     Up / Down Arrow the left / right / top / bottom half, Fn-Control-R Return to Previous Size (the size before the window was tiled). The
//     quarters have none ("n/a"). (The Window menu's Center and the window API's "center" stay the middle place at its size, as before.)
//   Arrange: Fn-Control-Shift-Left Arrow Left & Right (the front window left, the window behind it right), -Right Right & Left, -Up Top & Bottom,
//     -Down Bottom & Top; Fn-Control-Option-Shift-Left Arrow Left & Quarters (the front window left, the next two in the right quarters, top
//     first), -Right Right & Quarters, -Up Top & Quarters, -Down Bottom & Quarters. Quarters (four windows) has none.
//   Full-screen tiles: none.
// No custom shortcuts: binding your own keys (and launching apps, opening URLs) is KeyPilot's, through the window API (WindowAPIRule.h). Cmd-H stays
// iPadOS's Home (a Mac's Hide).
// Clashes, checked: iPadOS 15 has Globe-Control-Left / Right Arrow itself (an app to one side in Split View): while these keys are on, ours stand
// in their place, as a Mac's. Every other Globe shortcut of iPadOS (Globe-H Home, -A the Dock, Shift-Globe-A the App Library, -C Control Center,
// -N Notification Center, -Q Quick Note, -F full screen, -M the shortcuts or menu bar, -E / -D emoji and dictation, -Up / -Down / -Left / -Right
// the App Switcher, the windows, the apps, Option-Globe-Left / Right Slide Over) is another key or another set of modifiers: ours all hold Control
// with Globe. Our own keys: the Mac Switcher's Control-arrows have no Globe; the volume (Globe + Option / Control) and backlight (Shift + Option /
// Control) chords share modifiers with these and wait for their key's release while these keys are on (common/ModifierTap.h).
#ifndef MSBD_WINDOW_KEYS_RULE_H
#define MSBD_WINDOW_KEYS_RULE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include "WindowMinSize.h"   // (MSBDWindowMinFit: Return to Previous Size's frame inside today's desktop)

// The keys (a press's key: MSBDWinKeyFor -- the arrows by their place, F, C and R by the letter the layout types).
enum { kMSBDWinKeyLeft = 0, kMSBDWinKeyRight, kMSBDWinKeyUp, kMSBDWinKeyDown, kMSBDWinKeyF, kMSBDWinKeyC, kMSBDWinKeyR, kMSBDWinKeyCount };
// The modifier flags as UIKit gives them (UIKeyModifierFlags; Globe: the bit UIKit sets while the Globe key is held, as VolumeGlobe reads it).
#define kMSBDModShift   (1ULL << 17)
#define kMSBDModControl (1ULL << 18)
#define kMSBDModOption  (1ULL << 19)
#define kMSBDModCommand (1ULL << 20)
#define kMSBDModGlobe   (1ULL << 23)
#define kMSBDModMask    (kMSBDModShift | kMSBDModControl | kMSBDModOption | kMSBDModCommand | kMSBDModGlobe)   // (Caps Lock and the keypad bit left out)

enum { kMSBDWinKeyActNone = 0, kMSBDWinKeyActLayout, kMSBDWinKeyActArrange, kMSBDWinKeyActPrevious, kMSBDWinKeyActCenter };
typedef struct {
    int kind;
    int count;                // windows it places: 1 a layout or Center, 2 or 3 an arrangement, 0 otherwise
    const char *slots[3];     // the front window's layout first, then the window behind it, then the next (the Window menu's names)
    const char *title;        // as Apple's Window menu names it
} MSBDWinKeyAction;

// The shortcuts, one per row: the key, its modifiers, its action.
typedef struct { int key; unsigned long long mods; MSBDWinKeyAction act; } MSBDWinKeyRow;
#define kMSBDWinGC (kMSBDModGlobe | kMSBDModControl)
static const MSBDWinKeyRow kMSBDWinKeyRows[] = {
    { kMSBDWinKeyF,     kMSBDWinGC, { kMSBDWinKeyActLayout, 1, { "fill" }, "Fill" } },
    { kMSBDWinKeyC,     kMSBDWinGC, { kMSBDWinKeyActCenter, 1, { 0 }, "Center" } },   // (at its own size: MSBDWinCenterKeepingSize)
    { kMSBDWinKeyLeft,  kMSBDWinGC, { kMSBDWinKeyActLayout, 1, { "left" }, "Left" } },
    { kMSBDWinKeyRight, kMSBDWinGC, { kMSBDWinKeyActLayout, 1, { "right" }, "Right" } },
    { kMSBDWinKeyUp,    kMSBDWinGC, { kMSBDWinKeyActLayout, 1, { "top" }, "Top" } },
    { kMSBDWinKeyDown,  kMSBDWinGC, { kMSBDWinKeyActLayout, 1, { "bottom" }, "Bottom" } },
    { kMSBDWinKeyR,     kMSBDWinGC, { kMSBDWinKeyActPrevious, 0, { 0 }, "Return to Previous Size" } },
    { kMSBDWinKeyLeft,  kMSBDWinGC | kMSBDModShift, { kMSBDWinKeyActArrange, 2, { "left", "right" }, "Left & Right" } },
    { kMSBDWinKeyRight, kMSBDWinGC | kMSBDModShift, { kMSBDWinKeyActArrange, 2, { "right", "left" }, "Right & Left" } },
    { kMSBDWinKeyUp,    kMSBDWinGC | kMSBDModShift, { kMSBDWinKeyActArrange, 2, { "top", "bottom" }, "Top & Bottom" } },
    { kMSBDWinKeyDown,  kMSBDWinGC | kMSBDModShift, { kMSBDWinKeyActArrange, 2, { "bottom", "top" }, "Bottom & Top" } },
    { kMSBDWinKeyLeft,  kMSBDWinGC | kMSBDModShift | kMSBDModOption, { kMSBDWinKeyActArrange, 3, { "left", "topright", "bottomright" }, "Left & Quarters" } },
    { kMSBDWinKeyRight, kMSBDWinGC | kMSBDModShift | kMSBDModOption, { kMSBDWinKeyActArrange, 3, { "right", "topleft", "bottomleft" }, "Right & Quarters" } },
    { kMSBDWinKeyUp,    kMSBDWinGC | kMSBDModShift | kMSBDModOption, { kMSBDWinKeyActArrange, 3, { "top", "bottomleft", "bottomright" }, "Top & Quarters" } },
    { kMSBDWinKeyDown,  kMSBDWinGC | kMSBDModShift | kMSBDModOption, { kMSBDWinKeyActArrange, 3, { "bottom", "topleft", "topright" }, "Bottom & Quarters" } },
};
#define kMSBDWinKeyRowCount (sizeof(kMSBDWinKeyRows) / sizeof(kMSBDWinKeyRows[0]))

// The key at a place, from its HID usage (keyboard page: UIKey.keyCode): the arrows, and F, C, R where a US (QWERTY) layout has them; -1 for any other.
static inline int MSBDWinKeyForHIDUsage(long usage) {
    switch (usage) {
        case 0x50: return kMSBDWinKeyLeft;
        case 0x4F: return kMSBDWinKeyRight;
        case 0x52: return kMSBDWinKeyUp;
        case 0x51: return kMSBDWinKeyDown;
        case 0x09: return kMSBDWinKeyF;
        case 0x06: return kMSBDWinKeyC;
        case 0x15: return kMSBDWinKeyR;
        default: return -1;
    }
}
// The key a press is, as macOS reads its shortcuts: the arrows by their place (the same keys on every layout); F, C and R by the letter the keyboard
// layout types on the key (chars: UIKey.charactersIgnoringModifiers, UTF-8) -- Dvorak's F is where QWERTY has Y, Colemak's R where it has S;
// AZERTY and QWERTZ have the three where QWERTY does. A key that types another ASCII character is none of them (Dvorak's U, where QWERTY has F).
// A layout that types no ASCII letter there (Russian, Greek, Arabic, ...), or no character read: the key's place, its QWERTY letter, as macOS
// falls back to a Latin layout for its shortcuts.
static inline int MSBDWinKeyFor(long usage, const char *chars) {
    int at = MSBDWinKeyForHIDUsage(usage);
    if (at >= kMSBDWinKeyLeft && at <= kMSBDWinKeyDown) return at;
    if (chars && chars[0] && !chars[1] && (unsigned char)chars[0] < 0x80) {   // (one ASCII character: what this layout types there)
        switch (chars[0]) {
            case 'f': case 'F': return kMSBDWinKeyF;
            case 'c': case 'C': return kMSBDWinKeyC;
            case 'r': case 'R': return kMSBDWinKeyR;
            default: return -1;
        }
    }
    return at;
}
// The row of a key with these modifiers (as pressed: other bits are ignored, the modifiers must be exactly a row's), or -1.
static inline int MSBDWinKeyRowFor(int key, unsigned long long flags) {
    unsigned long long m = flags & kMSBDModMask;
    for (size_t i = 0; i < kMSBDWinKeyRowCount; i++) if (kMSBDWinKeyRows[i].key == key && kMSBDWinKeyRows[i].mods == m) return (int)i;
    return -1;
}
// ... its action, or none.
static inline MSBDWinKeyAction MSBDWinKeyActionFor(int key, unsigned long long flags) {
    int i = MSBDWinKeyRowFor(key, flags);
    if (i >= 0) return kMSBDWinKeyRows[i].act;
    MSBDWinKeyAction none = { kMSBDWinKeyActNone, 0, { 0 }, 0 };
    return none;
}
// ---- Center (Globe-Control-C), as macOS 15's: the window keeps its size, in the middle of the desktop (desk: the Fill layout's frame, in the
// engine's frames); one bigger than the desktop is as big as it there. Whole points. No tile: no Return to Previous Size record. ----
static inline CGRect MSBDWinCenterKeepingSize(CGRect window, CGRect desk) {
    if (CGRectIsNull(window) || CGRectIsNull(desk) || CGRectIsEmpty(window) || CGRectIsEmpty(desk)) return CGRectNull;
    CGFloat w = fmin(window.size.width, desk.size.width), h = fmin(window.size.height, desk.size.height);
    return CGRectMake(round(desk.origin.x + (desk.size.width - w) / 2.0), round(desk.origin.y + (desk.size.height - h) / 2.0), w, h);
}
// ---- Return to Previous Size (Globe-Control-R): a window's frame before it was tiled ----
// The tiles: Fill, the halves and the quarters (Center, Small and Large are sizes, as a Mac's Center keeps the window untiled). A frame is in a tile
// when each of its sides is within 16 pt of the tile's, as the Window menu's tick reads it (StatusBar.x DMSlotNameForFrame).
#define kMSBDWinTileCount 9
static const char *const kMSBDWinTiles[kMSBDWinTileCount] = { "fill", "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright" };
static inline bool MSBDWinIsTileName(const char *name) {
    if (!name) return false;
    for (int i = 0; i < kMSBDWinTileCount; i++) if (!strcmp(name, kMSBDWinTiles[i])) return true;
    return false;
}
static inline bool MSBDWinNear(CGRect a, CGRect b) {
    if (CGRectIsNull(a) || CGRectIsNull(b)) return false;
    return fabs(a.origin.x - b.origin.x) < 16.0 && fabs(a.origin.y - b.origin.y) < 16.0 && fabs(a.size.width - b.size.width) < 16.0 && fabs(a.size.height - b.size.height) < 16.0;
}
// A layout tiles a window: the frame it has now is taken when it is in no tile (a record left from before, of a window moved out of its tile by
// hand since, is replaced); a window in a tile already keeps the record it has (tiled left, then right: back to its size before the first).
static inline bool MSBDWinPrevTake(bool tiledNow) { return !tiledNow; }
// Globe-Control-R: back to the record while the window is still in a tile (the record then goes); moved out of its tile by hand since, the record
// only goes; none: nothing.
enum { kMSBDWinPrevNothing = 0, kMSBDWinPrevBack, kMSBDWinPrevDrop };
static inline int MSBDWinPrevOnReturn(bool tiledNow, bool hasRecord) {
    if (!hasRecord) return kMSBDWinPrevNothing;
    return tiledNow ? kMSBDWinPrevBack : kMSBDWinPrevDrop;
}
// Where Globe-Control-R puts the window: its record, inside today's desktop (fill: the Fill frame now; min: the smallest a window may be). A
// record made before a turn (portrait {0,500 700x600} on a landscape screen 834 pt tall) or before the Dock moved to a side was applied as it
// was and stood partly off the screen; it is pulled inside now, at its own size where that fits (audit 1.8.3 M5). Inside already: exactly it.
static inline CGRect MSBDWinPrevBackFrame(CGRect rec, CGRect fill, CGSize min) { return MSBDWindowMinFit(rec, fill, min); }


#endif
