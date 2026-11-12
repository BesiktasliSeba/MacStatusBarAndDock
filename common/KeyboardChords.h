// KeyboardChords.h -- every chord the tweak's keyboard features own, in one table, and who has a chord two of them claim (1.8.7, KT 11 Nov:
// "make it clear in the keyboard settings that they conflict with each other so one gets turned off"). Plain C (an Objective-C part at the end),
// so the Mac test (tools/test-keyboardchords.c) runs this very table; SpringBoard (statusbar/WindowKeys.h, MacSwitcher.h, CustomShortcuts.h),
// the key tweaks in every app (graveescape, tabmute, brightnesskey, volumeglobe) and Settings (macsettings/KeyboardSettings.x, CustomShortcuts.x)
// ask it.
//
// The features and their chords (Settings > Keyboard; read from each one's code):
//   Window Tiling Shortcuts   Globe-Control with an arrow, F, C or R; with Shift; with Option-Shift (statusbar/WindowKeysRule.h, 15 rows; F, C
//                             and R by the letter the layout types). SpringBoard: its presses and key commands.
//   Mac Switcher              Control-Left, Control-Right (more than one desktop), Control-Up (statusbar/MacSwitcher.h). SpringBoard's key commands.
//   Volume                    Globe + Option up, Globe + Control down: a tap of the modifier (volumeglobe/VolumeGlobe.x). SpringBoard's presses.
//   Backlight                 Shift + Option up, Shift + Control down: a tap (brightnesskey/BrightnessKey.x). SpringBoard's key events.
//   Screen brightness         Shift + = and Shift + -, Shift alone (brightnesskey/BrightnessKey.x). The app with the keyboard.
//   Top-Left Key as Escape    the key left of 1 (HID 0x35; 0x64 on Apple's ISO keyboards; none on JIS) is Escape, with any modifiers but Command
//                             (graveescape/GraveEscape.x: UIKit's key getters in every process).
//   Tab Key Toggles Mute      a bare Tab (tabmute/TabMute.x). The app with the keyboard.
//   Menu keys                 while one of our menus is open, the typing keys of the app in front go to the menu (common/MenuKeys.h).
//   Escape                    closes our menus and panels, ends typing on the desktop, stops a recording (any modifiers; never a shortcut).
//   Custom Shortcuts          your own (common/CustomShortcutsRule.h): Command, Option, Control or Globe and a key, Globe part of the match.
//   KeyPilot, while installed its own rules (com.whj.keypilot "Rules"): its match drops Globe, so a rule on Control-F also takes Globe-Control-F,
//                             and keeps Caps Lock (KPRelevantModifierFlags), so a rule recorded with Caps Lock on runs only with it on;
//                             Custom Shortcuts wait while it is installed (CustomShortcutsRule.h MSBDCSWantedNow).
//
// Who has a chord two of them claim:
//   - Your own shortcut (Custom Shortcuts, or KeyPilot's) wins over a built-in one on the same keys: the built-in one is off for those keys while
//     the shortcut is there (Window Tiling's row, the Mac Switcher's Control-arrow, the key left of 1 staying itself, Tab not muting, Shift + =/-
//     not changing the brightness). As macOS gives an app's own shortcut the keys over a system one.
//   - A tap (volume, backlight) and a shortcut that starts with the same keys (Window Tiling's Globe-Control and Shift-Control rows, or one of
//     yours): both work. The tap then acts at its key's release and not at all when another key went down meanwhile or a shortcut ran
//     (common/ModifierTap.h), as a Mac tells a modifier's tap from a shortcut. Never both on one press.
//   - Escape is never a shortcut (the recorder refuses it: it stops the recording). The key left of 1 turned into Escape is Escape's.
//   - An open menu takes typing keys; a shortcut (Control, Option, Command or Globe) runs first, a menu open or not (appbridge/AppBridge.x).
//     Window Tiling Shortcuts wait while a menu is open (WindowAPI.h's busy check).
//   - Between built-ins nothing else overlaps: Window Tiling's chords all hold Globe and Control, the Mac Switcher's Control alone, the screen
//     keys and Tab none of Control, Option, Command or Globe (1.8.7: Globe added to what they leave alone, so Globe-Tab and Globe-Shift-= are free
//     for a shortcut), the key left of 1 is no other feature's key (test-keyboardchords.c checks every chord).
#ifndef MSBD_KEYBOARD_CHORDS_H
#define MSBD_KEYBOARD_CHORDS_H
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "CustomShortcutsRule.h"   // (the modifier flags, MSBDCSMods, Window Tiling's rows through WindowKeysRule.h)

enum {
    kMSBDKCNone = 0,
    kMSBDKCWindowTiling,
    kMSBDKCMacSwitcher,
    kMSBDKCVolume,
    kMSBDKCBacklight,
    kMSBDKCScreen,
    kMSBDKCTopLeftEscape,
    kMSBDKCTabMute,
    kMSBDKCMenuKeys,
    kMSBDKCEscape,
    kMSBDKCCustom,
    kMSBDKCKeyPilot,
    kMSBDKCFeatureCount
};
// How a chord is told (the table's kind).
enum {
    kMSBDKCKindKey = 0,   // a key (HID usage) with exactly these modifiers (Caps Lock and the keypad bit aside)
    kMSBDKCKindWinRows,   // Window Tiling's rows (WindowKeysRule.h kMSBDWinKeyRows: F, C and R by the letter the layout types)
    kMSBDKCKindTap,       // a modifier key (usage) pressed while `mods` are held: a shortcut holding both starts with it
    kMSBDKCKindKeyAny,    // a key with any modifiers but `mods`
    kMSBDKCKindTyping,    // the typing keys (HID 0x04-0x65), any modifiers, while one of our menus is open
};
// Against your own shortcut on the same keys.
enum {
    kMSBDKCYours = 0,     // yours wins: the built-in one is off for those keys while yours is there
    kMSBDKCTapWaits,      // both: the tap acts at its release, never inside a shortcut
    kMSBDKCBuiltin,       // the built-in one: no shortcut is recorded on it
};
typedef struct { int feature; int kind; long usage; unsigned long long mods; int vsYours; const char *what; } MSBDKCChord;
#define kMSBDKCTopLeftANSI 0x35   // (the key left of 1: ANSI keyboards and other makers' ISO ones)
#define kMSBDKCTopLeftISO  0x64   // (Apple's ISO keyboards; there 0x35 is the key left of Z)
static const MSBDKCChord kMSBDKCChords[] = {
    { kMSBDKCWindowTiling, kMSBDKCKindWinRows, -1, 0, kMSBDKCYours, "Globe-Control with an arrow, F, C or R; with Shift; with Option-Shift" },
    { kMSBDKCMacSwitcher, kMSBDKCKindKey, kMSBDCSHIDLeft, kMSBDModControl, kMSBDKCYours, "Control-Left: the desktop on the left" },
    { kMSBDKCMacSwitcher, kMSBDKCKindKey, kMSBDCSHIDRight, kMSBDModControl, kMSBDKCYours, "Control-Right: the desktop on the right" },
    { kMSBDKCMacSwitcher, kMSBDKCKindKey, kMSBDCSHIDUp, kMSBDModControl, kMSBDKCYours, "Control-Up: the Mac Switcher" },
    { kMSBDKCVolume, kMSBDKCKindTap, 226, kMSBDModGlobe, kMSBDKCTapWaits, "Globe + Option: volume up" },
    { kMSBDKCVolume, kMSBDKCKindTap, 224, kMSBDModGlobe, kMSBDKCTapWaits, "Globe + Control: volume down" },
    { kMSBDKCBacklight, kMSBDKCKindTap, 226, kMSBDModShift, kMSBDKCTapWaits, "Shift + Option: backlight up" },
    { kMSBDKCBacklight, kMSBDKCKindTap, 224, kMSBDModShift, kMSBDKCTapWaits, "Shift + Control: backlight down" },
    { kMSBDKCScreen, kMSBDKCKindKey, 0x2E, kMSBDModShift, kMSBDKCYours, "Shift + =: screen brighter" },
    { kMSBDKCScreen, kMSBDKCKindKey, 0x2D, kMSBDModShift, kMSBDKCYours, "Shift + -: screen dimmer" },
    { kMSBDKCTopLeftEscape, kMSBDKCKindKeyAny, kMSBDKCTopLeftANSI, kMSBDModCommand, kMSBDKCYours, "the key left of 1 as Escape, but with Command" },
    { kMSBDKCTopLeftEscape, kMSBDKCKindKeyAny, kMSBDKCTopLeftISO, kMSBDModCommand, kMSBDKCYours, "the key left of 1 as Escape, but with Command" },
    { kMSBDKCTabMute, kMSBDKCKindKey, kMSBDCSHIDTab, 0, kMSBDKCYours, "Tab: mute" },
    { kMSBDKCMenuKeys, kMSBDKCKindTyping, -1, 0, kMSBDKCYours, "typing keys while one of our menus is open" },
    { kMSBDKCEscape, kMSBDKCKindKeyAny, kMSBDCSHIDEscape, 0, kMSBDKCBuiltin, "Esc: closes menus and panels, stops a recording" },
};
#define kMSBDKCChordCount (sizeof(kMSBDKCChords) / sizeof(kMSBDKCChords[0]))

// Whether table row i claims the key chord (usage with flags; chars: what the key types, for Window Tiling's F, C and R). topLeft: the usage of
// the key left of 1 on this keyboard (kMSBDKCTopLeftANSI, kMSBDKCTopLeftISO; 0: none, a JIS keyboard). Taps claim the chords that start with them;
// the menu keys' typing is not a chord (only while a menu is open: never asked here).
static inline bool MSBDKCRowClaims(size_t i, long usage, const char *chars, unsigned long long flags, long topLeft) {
    if (i >= kMSBDKCChordCount || usage <= 0) return false;
    const MSBDKCChord *c = &kMSBDKCChords[i];
    unsigned long long m = MSBDCSMods(flags);
    switch (c->kind) {
        case kMSBDKCKindKey: return usage == c->usage && m == c->mods;
        case kMSBDKCKindWinRows: return MSBDWinKeyRowFor(MSBDWinKeyFor(usage, chars), m) >= 0;
        case kMSBDKCKindTap: {   // (the tap's key's own flag: Option or Control)
            unsigned long long key = c->usage == 226 ? kMSBDModOption : c->usage == 224 ? kMSBDModControl : 0;
            return key && (m & (c->mods | key)) == (c->mods | key);
        }
        case kMSBDKCKindKeyAny:
            if (c->feature == kMSBDKCTopLeftEscape && (c->usage != topLeft || !topLeft)) return false;
            return usage == c->usage && !(m & c->mods);
        default: return false;
    }
}
// The built-in shortcut on a chord, or kMSBDKCNone: a key one (Key, WinRows, KeyAny; Escape among them); *row: Window Tiling's row, or -1.
static inline int MSBDKCKeyOwner(long usage, const char *chars, unsigned long long flags, long topLeft, int *row) {
    if (row) *row = -1;
    for (size_t i = 0; i < kMSBDKCChordCount; i++) {
        if (kMSBDKCChords[i].kind == kMSBDKCKindTap || !MSBDKCRowClaims(i, usage, chars, flags, topLeft)) continue;
        if (row && kMSBDKCChords[i].kind == kMSBDKCKindWinRows) *row = MSBDWinKeyRowFor(MSBDWinKeyFor(usage, chars), MSBDCSMods(flags));
        return kMSBDKCChords[i].feature;
    }
    return kMSBDKCNone;
}
// The taps a chord starts with: a bit per feature (1 << kMSBDKCVolume, 1 << kMSBDKCBacklight).
static inline unsigned MSBDKCTapsIn(unsigned long long flags) {
    unsigned out = 0;
    for (size_t i = 0; i < kMSBDKCChordCount; i++)
        if (kMSBDKCChords[i].kind == kMSBDKCKindTap && MSBDKCRowClaims(i, 0x0D, "", flags, 0)) out |= 1u << kMSBDKCChords[i].feature;   // (any key: J)
    return out;
}
// Who has a chord a built-in feature and your own shortcut both claim (the table's rule).
static inline int MSBDKCAgainstYours(int feature) {
    for (size_t i = 0; i < kMSBDKCChordCount; i++) if (kMSBDKCChords[i].feature == feature) return kMSBDKCChords[i].vsYours;
    return kMSBDKCYours;
}

// ---- Your own shortcuts: Custom Shortcuts' rules taken now (the switch on, KeyPilot not installed) and KeyPilot's while it is installed ----
// A Custom Shortcuts rule takes its key with exactly its modifiers (MSBDCSSame; Caps Lock aside); a KeyPilot rule with its modifiers and Globe or
// not, and Caps Lock exactly as it was recorded (KeyPilot's own match: KPRelevantModifierFlags keeps Caps Lock and drops Globe; the keypad bit it
// also keeps comes with the arrows both in its rules and in the presses). A press asks with its own Caps Lock (MSBDKCYoursTakes); what is decided
// before any press (Window Tiling's key commands, the Mac Switcher's, the key tweaks' state) is for Caps Lock off, the usual case: a KeyPilot rule
// recorded with Caps Lock on does not take a built-in one's keys then (review 1.8.7: it took Fill, or Control-Up, all the time for a rule that
// runs only with Caps Lock on; and a Caps Lock press of a rule without it ran nothing).
#define kMSBDKCCapsLock (1ULL << 16)   // (UIKeyModifierAlphaShift)
#define kMSBDKCYoursMax (2 * kMSBDCSMaxRules)
typedef struct {
    unsigned n;
    long usage[kMSBDKCYoursMax];
    unsigned long long mods[kMSBDKCYoursMax];
    bool keyPilot[kMSBDKCYoursMax];
    char key[kMSBDKCYoursMax][8];   // (what the key types, UTF-8: Window Tiling's F, C and R by the layout's letter)
} MSBDKCYoursSet;
static inline void MSBDKCYoursClear(MSBDKCYoursSet *y) { if (y) y->n = 0; }
static inline bool MSBDKCYoursAdd(MSBDKCYoursSet *y, long usage, const char *key, unsigned long long mods, bool keyPilot) {
    if (!y || y->n >= kMSBDKCYoursMax || usage <= 0 || usage > 0xFFFF) return false;
    unsigned i = y->n++;
    y->usage[i] = usage;
    y->mods[i] = keyPilot ? (mods & (kMSBDModShift | kMSBDModControl | kMSBDModOption | kMSBDModCommand | kMSBDKCCapsLock)) : MSBDCSMods(mods);
    y->keyPilot[i] = keyPilot;
    size_t l = key ? strlen(key) : 0;
    if (l >= sizeof y->key[i]) l = 0;   // (longer than one character: none, the key's place)
    memcpy(y->key[i], key ? key : "", l);
    y->key[i][l] = 0;
    return true;
}
// Whether rule i takes a press (usage, flags: the press's own, Caps Lock in them).
static inline bool MSBDKCYoursRuleTakes(const MSBDKCYoursSet *y, unsigned i, long usage, unsigned long long flags) {
    if (!y || i >= y->n || usage != y->usage[i]) return false;
    unsigned long long m = MSBDCSMods(flags);
    return y->keyPilot[i] ? ((m | (flags & kMSBDKCCapsLock)) & ~kMSBDModGlobe) == y->mods[i] : m == y->mods[i];
}
// Whether rule i counts before any press (Caps Lock off): every one of ours; KeyPilot's recorded without Caps Lock.
static inline bool MSBDKCYoursRuleStatic(const MSBDKCYoursSet *y, unsigned i) {
    return y && i < y->n && !(y->keyPilot[i] && (y->mods[i] & kMSBDKCCapsLock));
}
static inline bool MSBDKCYoursTakes(const MSBDKCYoursSet *y, long usage, unsigned long long flags) {
    for (unsigned i = 0; y && i < y->n; i++) if (MSBDKCYoursRuleTakes(y, i, usage, flags)) return true;
    return false;
}
// Whether one of yours lands on Window Tiling's row (its key command is left out then): its key, by the letter it types, with its modifiers (a
// KeyPilot rule with Globe added, as it takes the chord with Globe too; one recorded with Caps Lock on does not: MSBDKCYoursRuleStatic).
static inline bool MSBDKCYoursTakesWinRow(const MSBDKCYoursSet *y, int row) {
    for (unsigned i = 0; y && row >= 0 && i < y->n; i++)
        if (MSBDKCYoursRuleStatic(y, i) && MSBDWinKeyRowFor(MSBDWinKeyFor(y->usage[i], y->key[i]), y->mods[i] | (y->keyPilot[i] ? kMSBDModGlobe : 0)) == row) return true;
    return false;
}
// The taps yours start with (MSBDKCTapsIn; a KeyPilot rule with Globe or not, and with Caps Lock too: a tap that waits for its release is never
// lost, and one that did not would act inside that rule's chord with Caps Lock on).
static inline unsigned MSBDKCYoursTaps(const MSBDKCYoursSet *y) {
    unsigned out = 0;
    for (unsigned i = 0; y && i < y->n; i++) out |= MSBDKCTapsIn(y->mods[i] | (y->keyPilot[i] ? kMSBDModGlobe : 0));
    return out;
}

// ---- What the key tweaks in every app are told (a Darwin state SpringBoard writes; any process reads it) ----
// The apps can't read our preferences or KeyPilot's, so SpringBoard publishes which of the key tweaks' chords one of yours takes:
//   bits 0-15   the key 0x35 with these modifiers (MSBDKCTopLeftIndex) stays itself (Top-Left Key as Escape leaves it)
//   bits 16-31  the same for the key 0x64
//   bit 32      a bare Tab is yours (Tab mute leaves it)          bit 33, 34  Shift + =, Shift + - are yours (the screen keys leave them)
//   bit 35      a shortcut of yours starts with Globe + Option or Globe + Control: the volume taps wait for their release
//   bit 36      ... with Shift + Option or Shift + Control: the backlight taps wait
// 0: nothing of theirs is yours (no shortcuts, the switch off, or never published).
#define kMSBDKCYoursState "com.besiktasliseba.keyboard.yours"
#define kMSBDKCYoursTab          (1ULL << 32)
#define kMSBDKCYoursScreenUp     (1ULL << 33)
#define kMSBDKCYoursScreenDown   (1ULL << 34)
#define kMSBDKCYoursVolumeWaits  (1ULL << 35)
#define kMSBDKCYoursBacklightWaits (1ULL << 36)
// The top-left key's modifiers as a bit index: Shift 1, Control 2, Option 4, Globe 8; with Command -1 (never Escape).
static inline int MSBDKCTopLeftIndex(unsigned long long flags) {
    unsigned long long m = MSBDCSMods(flags);
    if (m & kMSBDModCommand) return -1;
    return (m & kMSBDModShift ? 1 : 0) | (m & kMSBDModControl ? 2 : 0) | (m & kMSBDModOption ? 4 : 0) | (m & kMSBDModGlobe ? 8 : 0);
}
static inline uint64_t MSBDKCYoursState(const MSBDKCYoursSet *y) {
    uint64_t st = 0;
    for (unsigned i = 0; y && i < y->n; i++) {
        if (!MSBDKCYoursRuleStatic(y, i)) continue;   // (a KeyPilot rule recorded with Caps Lock on: the key tweaks keep their keys)
        long u = y->usage[i];
        int globes = y->keyPilot[i] ? 2 : 1;   // (KeyPilot's: with Globe and without)
        for (int g = 0; g < globes; g++) {
            unsigned long long m = y->mods[i] | (g ? kMSBDModGlobe : 0);
            int t = MSBDKCTopLeftIndex(m);
            if (t >= 0 && u == kMSBDKCTopLeftANSI) st |= 1ULL << t;
            if (t >= 0 && u == kMSBDKCTopLeftISO) st |= 1ULL << (16 + t);
            if (u == kMSBDCSHIDTab && m == 0) st |= kMSBDKCYoursTab;
            if (u == 0x2E && m == kMSBDModShift) st |= kMSBDKCYoursScreenUp;
            if (u == 0x2D && m == kMSBDModShift) st |= kMSBDKCYoursScreenDown;
        }
    }
    unsigned taps = MSBDKCYoursTaps(y);
    if (taps & (1u << kMSBDKCVolume)) st |= kMSBDKCYoursVolumeWaits;
    if (taps & (1u << kMSBDKCBacklight)) st |= kMSBDKCYoursBacklightWaits;
    return st;
}
// Read by each key tweak (st: the state as read): the key left of 1 stays itself; a bare Tab, Shift + = / - are yours.
static inline bool MSBDKCTopLeftYours(uint64_t st, long usage, unsigned long long flags) {
    int t = MSBDKCTopLeftIndex(flags);
    if (t < 0) return false;
    if (usage == kMSBDKCTopLeftANSI) return (st >> t) & 1;
    if (usage == kMSBDKCTopLeftISO) return (st >> (16 + t)) & 1;
    return false;
}
static inline bool MSBDKCScreenKeyYours(uint64_t st, long usage) {
    return usage == 0x2E ? (st & kMSBDKCYoursScreenUp) != 0 : usage == 0x2D ? (st & kMSBDKCYoursScreenDown) != 0 : false;
}
// Settings' recording, in Settings only: the key left of 1 with Control, Option or Globe stays itself, so a shortcut on it can be recorded while
// Top-Left Key as Escape is on (then it is yours: the bits above). Bare or with Shift it is still Escape, which stops the recording.
static inline bool MSBDKCTopLeftRecordable(unsigned long long flags) {
    unsigned long long m = MSBDCSMods(flags);
    return !(m & kMSBDModCommand) && (m & (kMSBDModControl | kMSBDModOption | kMSBDModGlobe)) != 0;
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>
// Yours from the rules as stored: Custom Shortcuts' usable ones (MSBDCSRuleUsable) when they are taken (customOn: the switch on and KeyPilot not
// installed), KeyPilot's on, with a key code and an action, while it is installed.
static inline void MSBDKCYoursFromRules(MSBDKCYoursSet *y, NSArray *custom, BOOL customOn, NSArray *keyPilot, BOOL keyPilotOn) {
    MSBDKCYoursClear(y);
    if (customOn)
        for (NSDictionary *r in [custom isKindOfClass:[NSArray class]] ? custom : @[]) {
            if (!MSBDCSRuleUsable(r)) continue;
            NSString *k = [r[@"key"] isKindOfClass:[NSString class]] ? r[@"key"] : @"";
            MSBDKCYoursAdd(y, [r[@"keyCode"] longValue], k.UTF8String, [r[@"modifiers"] unsignedLongLongValue], false);
        }
    if (keyPilotOn)
        for (NSDictionary *r in [keyPilot isKindOfClass:[NSArray class]] ? keyPilot : @[]) {
            if (![r isKindOfClass:[NSDictionary class]] || ![r[@"keyCode"] isKindOfClass:[NSNumber class]] || ![r[@"modifiers"] isKindOfClass:[NSNumber class]]) continue;
            if (![r[@"enabled"] respondsToSelector:@selector(boolValue)] || ![r[@"enabled"] boolValue] || ![r[@"action"] isKindOfClass:[NSString class]] || ![r[@"action"] length]) continue;
            NSString *k = [r[@"key"] isKindOfClass:[NSString class]] ? r[@"key"] : @"";
            MSBDKCYoursAdd(y, [r[@"keyCode"] longValue], k.lowercaseString.UTF8String, [r[@"modifiers"] unsignedLongLongValue], true);
        }
}
#endif
#endif
