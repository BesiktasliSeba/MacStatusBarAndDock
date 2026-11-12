// ModifierTap.h -- a modifier chord that is an action of its own (Settings > Keyboard: Globe + Option / Control for the volume, VolumeGlobe; Shift +
// Option / Control for the keyboard backlight, BrightnessKey) next to shortcuts that begin with the same modifiers (Window Tiling Keys, 1.8.3 item 3:
// Globe-Control-arrows, Globe-Control-Shift-arrows, Globe-Control-Option-Shift-arrows). Plain C, so the Mac test (tools/test-modifiertap.c) runs this
// very rule; volumeglobe/VolumeGlobe.x and brightnesskey/BrightnessKey.x follow it in SpringBoard.
//  - With Window Tiling Keys off: the chord acts as its key goes down, as it always has.
//  - On: Globe-Control-Left began with Globe + Control, so it turned the volume down as well (and Shift + Control the backlight). The chord now acts when
//    its key comes up, and not at all when another key went down while it was held or one of the window keys ran (the window keys tell the chords
//    so: kMSBDModTapUsedNote), as a Mac tells a modifier's tap from a shortcut.
// One press may reach SpringBoard twice (17.5.1, VolumeGlobe.x): a second down of the same chord keeps it armed, a second up finds nothing to do.
// Both chord keys held (Globe-Control-Option, the start of Globe-Control-Option-Shift-arrows) is no tap of either, told by the press's own modifier
// flags (the other key's flag set), not by what went before: on the M1 each press comes twice, and the second Option of Globe-Control-Option found
// nothing armed and waited again, so the volume went up at Option's release (1.8.3 regression F1, M1).
// Only taken while the keys are offered: the switch on and a window engine of ours running (kMSBDWindowKeysOfferedNote's state, set by SpringBoard's
// MacStatusBarCore), or while one of your own shortcuts starts with the chord (1.8.7: common/KeyboardChords.h kMSBDKCYoursState), else the chords
// act as their key goes down, as in 1.8.2.2.
#ifndef MSBD_MODIFIER_TAP_H
#define MSBD_MODIFIER_TAP_H
#include <stdbool.h>

#define kMSBDModTapUsedNote "com.besiktasliseba.macstatusbar.windowkeys.used"   // (Darwin: a window key ran -- a chord held for it is no tap)
// Darwin, with a state: SpringBoard offers the window keys now (the switch on and a window engine of ours running) -- the state is SpringBoard's pid
// << 32 | 1, or | 0 when not; posted when it changes. Read in SpringBoard by the chords (a state left by an earlier SpringBoard has another pid: not
// offered).
#define kMSBDWindowKeysOfferedNote "com.besiktasliseba.macstatusbar.windowkeys.offered"
static inline bool MSBDWindowKeysOfferedIn(unsigned long long state, int pid) { return (state & 1ULL) && (long long)(state >> 32) == (long long)pid; }
static inline unsigned long long MSBDWindowKeysOfferedState(bool offered, int pid) { return ((unsigned long long)(unsigned)pid << 32) | (offered ? 1ULL : 0ULL); }
// Window Tiling Keys' switch (Settings > Keyboard): com.besiktasliseba.macstatusbar, a boolean, never set -- the default -- on (1.8.7, new
// installs; an update had off written where it was never set: sshtoggled's defaults v5); its notification.
#define kMSBDWindowKeysKey "windowTilingKeys"
#define kMSBDWindowKeysDomain "com.besiktasliseba.macstatusbar"
#define kMSBDWindowKeysChanged "com.besiktasliseba.macstatusbar/prefsChanged"

enum { kMSBDModTapNothing = 0, kMSBDModTapActNow, kMSBDModTapWait, kMSBDModTapActOnRelease };
typedef struct { int key; bool armed; } MSBDModTap;

// The chords' two keys (left Option and left Control, as key codes) and the modifier flag each sets while held (UIKeyModifierAlternate, Control).
#define kMSBDModTapOptionKey   226
#define kMSBDModTapControlKey  224
#define kMSBDModTapOptionFlag  0x80000ULL
#define kMSBDModTapControlFlag 0x40000ULL
// Whether the other chord key is held as this one goes down: Control's flag on Option's press, Option's on Control's (flags: the press's own).
static inline bool MSBDModTapOtherHeld(int key, unsigned long long flags) {
    if (key == kMSBDModTapOptionKey) return (flags & kMSBDModTapControlFlag) != 0;
    if (key == kMSBDModTapControlKey) return (flags & kMSBDModTapOptionFlag) != 0;
    return false;
}

// The chord's own key went down (`chord`: its other modifier is held -- Option with Globe, Control with Shift; `otherHeld`: the other chord key is
// held too, MSBDModTapOtherHeld); defer: Window Tiling Keys are on.
static inline int MSBDModTapDown(MSBDModTap *t, int key, bool chord, bool otherHeld, bool defer) {
    if (!t) return kMSBDModTapNothing;
    if (!chord) {   // any key down that is not the chord -- another key, or the chord's own key without its modifier: whatever was held is no tap
        t->armed = false;   // (also its own key: a release that never came left it armed, and Control-C minutes later stepped the volume at its release)
        return kMSBDModTapNothing;
    }
    if (!defer) { t->armed = false; return kMSBDModTapActNow; }
    if (otherHeld) {   // (both chord keys held: neither is a tap -- each time this press is handed over, so a second delivery cannot wait again)
        t->armed = false;
        return kMSBDModTapNothing;
    }
    if (t->armed) {   // (the same press handed over again: still waiting; the other chord key while one is held: neither is a tap)
        if (t->key == key) return kMSBDModTapWait;
        t->armed = false;
        return kMSBDModTapNothing;
    }
    t->key = key; t->armed = true;
    return kMSBDModTapWait;
}
// A window key ran while the chord was held: no tap.
static inline void MSBDModTapUsed(MSBDModTap *t) { if (t) t->armed = false; }
// A key came up: the chord's action now when it is the armed key (once).
static inline int MSBDModTapUp(MSBDModTap *t, int key) {
    if (!t || !t->armed || t->key != key) return kMSBDModTapNothing;
    t->armed = false;
    return kMSBDModTapActOnRelease;
}

#endif
