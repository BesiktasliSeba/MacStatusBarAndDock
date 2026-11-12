// DockAutoHide.h -- Settings > Dock > Automatically Hide and Show the Dock (MacStatusBar&Dock 1.8.4 item 4, KT's yes 7 Nov): off by default, as
// on macOS. On, the Dock hides and comes back with a swipe up from the bottom edge or the pointer reaching it, the same on every engine. The rules
// in plain C (dock/Dock.x and statusbar/StatusBar.x run them; tools/test-dockautohide.c tests them).
//
// Stage Manager has a "Dock" tick of its own (Apple's "hide the Dock": SBChamoisHideDock in com.apple.springboard, read by its layout through
// prefersDockHidden). With the Stage Manager engine our switch is the one place for it (it replaces Apple's option) and Apple's tick is kept matching
// it, so Stage Manager's stage area (the room for windows above the Dock) is the one our Dock leaves:
//  - our switch never set (an update, a new install): off, as for everyone -- Apple's tick is never read into it (KT 7 Nov, review 1.8.4 Pass 4 M1:
//    a user with Stage Manager's Dock hidden got ours on at the update, the Dock hidden on the Home Screen too; GitHub #11). If Apple's tick hides the
//    Dock then, it is set to shown, once (the first run), so the stage area leaves room for the Dock we show; shown already: nothing is written;
//  - our switch moved: Apple's tick follows -- after that first run, the one case Apple's tick is written;
//  - Apple's tick moved (Control Center's Stage Manager module, Settings): our switch follows;
//  - our switch set while another engine ran, and Stage Manager never synced with it: our switch said so, Apple's tick follows.
// Apple's tick as it read at the last sync is kept (autoHideDockSynced) to tell which one moved, across resprings and engine changes. With the other
// engines Apple's tick is not read or written: our switch alone, never set = off. The Dock hiding itself does not wait for Apple's tick on any engine
// (the Stage Manager engine's in-app answer and stage area read our switch too): where the tick can't be written, the switch still works.
#ifndef MSBD_DOCK_AUTO_HIDE_H
#define MSBD_DOCK_AUTO_HIDE_H
#include <string.h>

#define kMSBDAutoHideKey "autoHideDock"              // (com.besiktasliseba.dockmagnification) off unless switched on
#define kMSBDAutoHideSyncedKey "autoHideDockSynced"  // (the same domain: Apple's tick as it read at the last sync)
#define kMSBDAppleHideDockKey "SBChamoisHideDock"    // (com.apple.springboard: Stage Manager's own "Dock" tick, true = hide the Dock)

enum { MSBDAutoHideKeep = 0, MSBDAutoHideSetApple = 1, MSBDAutoHideSetOurs = 2 };

// The switch as stored: -1 never set, else 0 / 1 (a stored value that is no boolean counts as never set).
static inline int MSBDAutoHideStored(int isBool, int value) { return isBool ? value != 0 : -1; }

// Our engines but Stage Manager: our switch alone.
static inline int MSBDAutoHideOn(int ours) { return ours > 0; }

// The Stage Manager engine's sync step. ours: our switch (-1 never set: off); apple: Apple's tick says hide (0 / 1); synced: Apple's tick as it read
// after the last step (what both had, but for a tick that does not take a write: below; -1 none yet: the first run). The answer: keep, set Apple's
// tick to ours (MSBDAutoHideTickFor), or set ours to Apple's tick.
static inline int MSBDAutoHideSync(int ours, int apple, int synced) {
    if (ours < 0) {                                                   // (never set: off -- KT 7 Nov, review 1.8.4 Pass 4 M1)
        if (synced < 0) return apple ? MSBDAutoHideSetApple : MSBDAutoHideKeep;   // (the first run: a hiding tick set to shown, once; never read into ours)
        return apple != (synced != 0) ? MSBDAutoHideSetOurs : MSBDAutoHideKeep;   // (Apple's tick moved since -- Control Center, Settings: ours follows)
    }
    if (ours == (apple != 0)) return MSBDAutoHideKeep;
    if (synced >= 0 && ours == (synced != 0)) return MSBDAutoHideSetOurs;   // (Apple's tick moved since the last sync)
    return MSBDAutoHideSetApple;                                      // (our switch moved, or Stage Manager never synced with it)
}
// The value stored as synced after a step: Apple's tick as it reads after the step. Mostly both hold it. A tick that does not take what is written
// stays as it reads -- TrollPad keeps Stage Manager's Dock shown: it turns a write of the tick into "shown" and reads its own copy (TrollPadSB,
// 18.5) --, so the next step writes it again instead of taking it for a change of Apple's, and our switch stays as the user set it. Kept, it is
// Apple's tick as it reads (with ours set, the same as ours; never set, the first run is marked done whatever the tick says).
// appleAfter: Apple's tick read again after a write of it (SetApple), else unused.
static inline int MSBDAutoHideSyncedValue(int ours, int apple, int step, int appleAfter) {
    (void)ours;
    return step == MSBDAutoHideSetApple ? appleAfter != 0 : apple != 0;
}
// What a write of Apple's tick says (1 hide): our switch's value -- never set is off, so shown.
static inline int MSBDAutoHideTickFor(int ours) { return ours > 0; }
// Whether a step writes Apple's tick now. refused: the value of our switch a write of Apple's tick did not take in this SpringBoard (-1 none): that
// value is not written again until our switch changes -- one try per SpringBoard, never a loop with Apple's change observer.
static inline int MSBDAutoHideWritesApple(int step, int ours, int refused) {
    return step == MSBDAutoHideSetApple && !(refused >= 0 && (ours > 0) == (refused != 0));
}
// What `refused` becomes after a write of Apple's tick: -1 when it took our switch's value, else that value.
static inline int MSBDAutoHideRefused(int ours, int appleAfter) { return (appleAfter != 0) == (ours > 0) ? -1 : ours > 0; }

// The Home Screen's own Dock assertion (level 0, reason "homescreen") while the switch is on: away, with the gesture possible -- as an app's in-app
// assertion -- so SpringBoard's own swipe and pointer bring the Dock and put it away again; off: as iPadOS has it (out, no gesture).
static inline double MSBDAutoHideHomeProgress(int on, double apple) { return on ? 0.0 : apple; }
static inline int MSBDAutoHideHomeGesture(int on, int apple) { return on ? 1 : apple != 0; }
// Whether the Home Screen's Dock hides now: the switch on and the Home Screen not being edited. While it is edited the Dock shows, as with the switch off,
// so apps can be put in it and its items arranged; it goes away again when editing ends (review 1.8.4 Pass 4 M2, iPad 2 16.7.7: with the Dock away a
// swipe up ends editing, as iPadOS has it, and a drag held at the bottom edge does not bring the Dock: no app could be put in it).
static inline int MSBDAutoHideHomeHides(int on, int editing) { return on && !editing; }

// Whether our switch can act in this SpringBoard, by the Dock part's hooks (DockAutoHide.m MSBDDockAutoHideHooks): -1, not as expected here (the Dock
// left as iPadOS has it), cannot -- the switch stored on is then no change of the Dock for the windows, and no reason to write Stage Manager's tick
// (review 1.8.4 Pass 4 L3: every change of the Dock's settings re-placed the windows); 0 (not tried yet: the first "on" tries them) and 1 (in place) can.
static inline int MSBDAutoHideCanAct(int hooks) { return hooks >= 0; }

// The Dock controller's assertions by level, as its ivar's type encoding gives them: exactly "[<n>@\"NSPointerArray\"]", a C array of n pointer arrays
// ([13@"NSPointerArray"] on 18.5). The number of levels (1 to 64), or 0 for any other shape: then the array is not read at all (review 1.8.4 Pass 4 L2:
// sscanf stopped after the count and took "[13^v]" too, whose entries would have been sent messages as objects).
static inline int MSBDAutoHideLevelsOf(const char *encoding) {
    int n = 0, i = 1;
    if (!encoding || encoding[0] != '[') return 0;
    for (; encoding[i] >= '0' && encoding[i] <= '9'; i++) if ((n = n * 10 + (encoding[i] - '0')) > 64) return 0;
    return i > 1 && n > 0 && !strcmp(encoding + i, "@\"NSPointerArray\"]") ? n : 0;
}

// Fill and the usable area (the room for windows): while the Dock hides itself it leaves none -- the room goes down to the screen's edge (the
// bottom, or the Dock's side), as a zoomed window on a Mac with the Dock hidden.
static inline double MSBDAutoHideRoomEdge(int autoHide, double dockEdge, double screenEdge) { return autoHide ? screenEdge : dockEdge; }

// ---- per display (1.8.7, plans/design-1.8.7-displays.md section 5): the in-app Dock answer for one stage's display ------------------------------------
// With the Stage Manager engine each display's stage has its own switcher modifier, which asks whether its Dock goes away in an app (S5 reading, A12Z 18.5: the
// TV's Dock hid with the iPad's shown, and the other way). Its preference part: on the iPad's own stage Apple's "hide Dock" preference (Stage Manager's tick)
// or our switch, as in 1.8.4. On another display's stage that display's own switch (the iPad's answer until changed for it), and Apple's preference only
// where it hides beyond the iPad's switch it is kept equal to (MSBDAutoHideSync): the tick follows the iPad, so a TV switched off for itself keeps its Dock
// while the iPad's hides; a tick our switch could not take still hides it, as on the iPad.
static inline int MSBDAutoHideInAppPref(int otherDisplay, int applePrefers, int ipadHides, int displayHides) {
    if (!otherDisplay) return applePrefers || ipadHides;
    return displayHides || (applePrefers && !ipadHides);
}

// ---- the room the windows are placed for (regression 1.8.4 F2; the review of the fixes, H1 and M1) ----
// The answer the room for windows stands on (1: the Dock hides itself) is saved with the windows (the window state, Stage Manager's state file) and
// compared at the start with the one taken then. Switched while SpringBoard was not running -- the crash guard's step at a start turns the switch off
// --, the windows follow the room as it is, as at a change in Settings. saved: the answer saved with them (-1: none, a state from before 1.8.4); now:
// the answer taken now (-1: not known yet, MSBDRoomNowFrom).
// The answer taken now, for the room: the Dock part's own while it is loaded. Switched off in Settings (its own switch), or not loaded once SpringBoard
// has started -- its line off in Choicy or iCleaner Pro, or turned off by the crash guard's step --, iPadOS's own Dock shows: the room is the shown
// Dock's (0), and the windows follow it. Only in SpringBoard's first seconds, before the Dock part could be there, is it not known (-1). (The re-review
// of the fixes, Low 1: switched off, it counted as not known for good, so Fill windows kept the freed room under the stock Dock and the old answer was
// written back.)
#define MSBD_DOCK_PART_LOAD_WAIT 8.0
static inline int MSBDRoomNowFrom(int loaded, int hides, int partOn, double processAge) {
    if (!partOn) return 0;
    if (loaded) return hides != 0;
    return processAge > MSBD_DOCK_PART_LOAD_WAIT ? 0 : -1;
}
enum { MSBDRoomNone = 0, MSBDRoomUnknown = 1, MSBDRoomSame = 2, MSBDRoomChanged = 3 };
static inline int MSBDRoomAtStart(int saved, int now) {
    if (saved < 0) return MSBDRoomNone;
    if (now < 0) return MSBDRoomUnknown;   // (kept: decided once the Dock part answers, never taken for "the same")
    return (saved != 0) == (now != 0) ? MSBDRoomSame : MSBDRoomChanged;
}
// The answer written with the windows: the saved one while it is pending (not decided yet, or the windows not placed for the room as it is yet), else
// the one taken now; -1: neither (the key left out). A key read at the start is so never dropped while the Dock part's answer is not known (M1).
static inline int MSBDRoomToSave(int pending, int now) { return pending >= 0 ? pending : now; }
// Stage Manager's start tick (SMHome.h) and a pending room. The tick runs on any iPad that can run Stage Manager, whichever engine is picked: with
// another engine its own restore has the room, and the tick never touches it (H1: it dropped the room Aerial's restore had just read). Stage Manager's
// own placing (ours off): no layouts of ours to follow, dropped. Ours: the desktop's own step brings the windows back and the room follows then
// (homeStep: StatusBar.x DMDockRoomAfterStartSM); where that step does not run, once the start has settled and the screen can be reached.
enum { MSBDRoomTickKeep = 0, MSBDRoomTickDrop = 1, MSBDRoomTickFollow = 2 };
static inline int MSBDRoomTick(int pending, int smEngine, int smFree, int homeStep, int settled) {
    if (pending < 0 || !smEngine) return MSBDRoomTickKeep;
    if (!smFree) return MSBDRoomTickDrop;
    if (homeStep) return MSBDRoomTickKeep;
    return settled ? MSBDRoomTickFollow : MSBDRoomTickKeep;
}

#endif
