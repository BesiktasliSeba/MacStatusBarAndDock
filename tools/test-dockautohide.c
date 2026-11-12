// test-dockautohide.c -- Mac test of common/DockAutoHide.h (Settings > Dock > Automatically Hide and Show the Dock, 1.8.4 item 4): the switch as
// stored, the Stage Manager engine's two-way sync with Apple's own "Dock" tick, and the room it leaves. Run by tools/test-dockautohide.sh.
#include <stdio.h>
#include "../common/DockAutoHide.h"
static int fails = 0, checks = 0;
static void check(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
int main(void) {
    // the switch as stored
    check("never set: -1; a boolean: its value", MSBDAutoHideStored(0, 0) == -1 && MSBDAutoHideStored(1, 1) == 1 && MSBDAutoHideStored(1, 0) == 0);
    check("  ... another engine: off unless set on (Apple's tick not asked)", !MSBDAutoHideOn(-1) && !MSBDAutoHideOn(0) && MSBDAutoHideOn(1));
    // the Stage Manager engine, our switch never set (an update, a new install): off for everyone, Apple's tick never read into it (KT 7 Nov, review Pass 4 M1)
    {
        int st = MSBDAutoHideSync(-1, 1, -1);
        check("M1: never set, Apple's tick hiding the Dock: our switch stays off (not taken from the tick), Apple's tick written as shown",
              st == MSBDAutoHideSetApple && st != MSBDAutoHideSetOurs && !MSBDAutoHideOn(-1) && MSBDAutoHideWritesApple(st, -1, -1) && MSBDAutoHideTickFor(-1) == 0);
        int synced = MSBDAutoHideSyncedValue(-1, 1, st, 0), refused = MSBDAutoHideRefused(-1, 0);
        check("  ... done once: the tick read back shown, the next step (Apple's observer, the next SpringBoard) writes nothing",
              synced == 0 && refused == -1 && MSBDAutoHideSync(-1, 0, synced) == MSBDAutoHideKeep);
        synced = MSBDAutoHideSyncedValue(-1, 1, st, 1); refused = MSBDAutoHideRefused(-1, 1);
        check("  ... a tick that does not take it (reads back hide): not written again in this SpringBoard, nor in the next, our switch still off",
              MSBDAutoHideSync(-1, 1, synced) == MSBDAutoHideKeep && !MSBDAutoHideWritesApple(MSBDAutoHideSetApple, -1, refused));
        check("M1: never set, Apple's tick showing the Dock: nothing written, our switch off, the first run marked done",
              MSBDAutoHideSync(-1, 0, -1) == MSBDAutoHideKeep && MSBDAutoHideSyncedValue(-1, 0, MSBDAutoHideKeep, 0) == 0 && MSBDAutoHideSync(-1, 0, 0) == MSBDAutoHideKeep);
        check("  ... after that first run, Apple's tick moved (Control Center, Settings): our switch follows it, as when set",
              MSBDAutoHideSync(-1, 1, 0) == MSBDAutoHideSetOurs && MSBDAutoHideSync(-1, 0, 1) == MSBDAutoHideSetOurs);
        check("M1: the switch turned on: Apple's tick written hide; turned off: written shown (both ways, as before)",
              MSBDAutoHideSync(1, 0, 0) == MSBDAutoHideSetApple && MSBDAutoHideTickFor(1) == 1 && MSBDAutoHideSync(0, 1, 1) == MSBDAutoHideSetApple && MSBDAutoHideTickFor(0) == 0);
    }
    // equal: nothing written
    check("both the same: nothing written, whatever was synced", MSBDAutoHideSync(1, 1, 0) == MSBDAutoHideKeep && MSBDAutoHideSync(0, 0, 1) == MSBDAutoHideKeep && MSBDAutoHideSync(1, 1, -1) == MSBDAutoHideKeep);
    // one moved
    check("our switch turned on since the last sync: Apple's tick follows (the one write of it)", MSBDAutoHideSync(1, 0, 0) == MSBDAutoHideSetApple && MSBDAutoHideSyncedValue(1, 0, MSBDAutoHideSetApple, 1) == 1);
    check("  ... turned off: Apple's tick follows", MSBDAutoHideSync(0, 1, 1) == MSBDAutoHideSetApple && MSBDAutoHideSyncedValue(0, 1, MSBDAutoHideSetApple, 0) == 0);
    check("Apple's tick changed since (Control Center, Settings): our switch follows, Apple's is not written", MSBDAutoHideSync(0, 1, 0) == MSBDAutoHideSetOurs && MSBDAutoHideSync(1, 0, 1) == MSBDAutoHideSetOurs
          && MSBDAutoHideSyncedValue(0, 1, MSBDAutoHideSetOurs, 0) == 1 && MSBDAutoHideSyncedValue(1, 0, MSBDAutoHideSetOurs, 1) == 0);
    check("our switch set on another engine, Stage Manager never synced: our switch said so, Apple's tick follows", MSBDAutoHideSync(1, 0, -1) == MSBDAutoHideSetApple && MSBDAutoHideSync(0, 1, -1) == MSBDAutoHideSetApple);
    // a respring in between keeps the synced value: the same answers (a run of steps settles at once)
    int ours = 1, apple = 0, synced = 0, step = MSBDAutoHideSync(ours, apple, synced);
    if (step == MSBDAutoHideSetApple) { int was = apple; apple = ours; synced = MSBDAutoHideSyncedValue(ours, was, step, apple); } else if (step == MSBDAutoHideSetOurs) { ours = apple; synced = MSBDAutoHideSyncedValue(ours, apple, step, 0); }
    check("after a step both hold the synced value, and the next step keeps", ours == synced && apple == synced && MSBDAutoHideSync(ours, apple, synced) == MSBDAutoHideKeep);
    // Apple's tick that does not take the write (TrollPad: a write of it becomes "shown", its read is TrollPad's own copy)
    {
        int o = 1, a = 0, sy = 0, refused = -1, st = MSBDAutoHideSync(o, a, sy), writes = MSBDAutoHideWritesApple(st, o, refused), after = 0;   // (written: it reads back shown)
        refused = MSBDAutoHideRefused(o, after); sy = MSBDAutoHideSyncedValue(o, a, st, after);
        check("a tick that does not take our switch's on: written once, stored as it reads (shown), our switch stays on", st == MSBDAutoHideSetApple && writes && refused == 1 && sy == 0 && o == 1);
        st = MSBDAutoHideSync(o, a, sy);
        check("  ... Apple's change observer asks again: not written again for the same switch, our switch never taken off", st == MSBDAutoHideSetApple && !MSBDAutoHideWritesApple(st, o, refused) && st != MSBDAutoHideSetOurs);
        check("  ... the next SpringBoard (nothing refused yet): one try again, still not taken for a change of Apple's", MSBDAutoHideSync(1, 0, sy) == MSBDAutoHideSetApple && MSBDAutoHideWritesApple(MSBDAutoHideSetApple, 1, -1));
        check("  ... the user turns ours off: both shown, nothing written", MSBDAutoHideSync(0, 0, sy) == MSBDAutoHideKeep && !MSBDAutoHideWritesApple(MSBDAutoHideKeep, 0, refused));
        check("  ... our switch on again after it was off: written again (another value than the refused one is tried)", MSBDAutoHideWritesApple(MSBDAutoHideSetApple, 0, 1) && MSBDAutoHideWritesApple(MSBDAutoHideSetApple, 1, 0));
        check("a write that takes: nothing refused", MSBDAutoHideRefused(1, 1) == -1 && MSBDAutoHideRefused(0, 0) == -1 && MSBDAutoHideRefused(0, 1) == 0);
    }
    // the Home Screen's own assertion
    check("the Home Screen's Dock assertion while on: away (0) with the gesture possible, whatever iPadOS said", MSBDAutoHideHomeProgress(1, 1.0) == 0.0 && MSBDAutoHideHomeGesture(1, 0) == 1);
    check("  ... off: exactly iPadOS's answers", MSBDAutoHideHomeProgress(0, 1.0) == 1.0 && MSBDAutoHideHomeProgress(0, 0.25) == 0.25 && MSBDAutoHideHomeGesture(0, 0) == 0 && MSBDAutoHideHomeGesture(0, 1) == 1);
    // the Dock part's hooks (review 1.8.4 Pass 4 L3)
    check("L3: hooks that could not be made here (-1): our switch can't act; not tried yet (0) or in place (1): it can",
          !MSBDAutoHideCanAct(-1) && MSBDAutoHideCanAct(0) && MSBDAutoHideCanAct(1));
    // the controller's assertions by level: read only in exactly their shape (review 1.8.4 Pass 4 L2)
    check("L2: the levels' C array read only as exactly [<n>@\"NSPointerArray\"]: 18.5's 13, and 1 and 64",
          MSBDAutoHideLevelsOf("[13@\"NSPointerArray\"]") == 13 && MSBDAutoHideLevelsOf("[1@\"NSPointerArray\"]") == 1 && MSBDAutoHideLevelsOf("[64@\"NSPointerArray\"]") == 64);
    check("  ... any other shape: 0, not read (void pointers, another class, more after it, unclosed, no count, 0, over 64, a huge count, a space, nothing)",
          !MSBDAutoHideLevelsOf("[13^v]") && !MSBDAutoHideLevelsOf("[13@\"NSMutableArray\"]") && !MSBDAutoHideLevelsOf("[13@\"NSPointerArray\"]x")
          && !MSBDAutoHideLevelsOf("[13@\"NSPointerArray\"") && !MSBDAutoHideLevelsOf("[@\"NSPointerArray\"]") && !MSBDAutoHideLevelsOf("[0@\"NSPointerArray\"]")
          && !MSBDAutoHideLevelsOf("[65@\"NSPointerArray\"]") && !MSBDAutoHideLevelsOf("[99999999999999999999@\"NSPointerArray\"]")
          && !MSBDAutoHideLevelsOf("[ 13@\"NSPointerArray\"]") && !MSBDAutoHideLevelsOf("[13@]") && !MSBDAutoHideLevelsOf("") && !MSBDAutoHideLevelsOf(NULL)
          && !MSBDAutoHideLevelsOf("@\"NSPointerArray\""));
    // Edit Home Screen (review 1.8.4 Pass 4 M2)
    check("M2: the Home Screen's Dock hides with the switch on, but not while the Home Screen is edited (an app can be put in it); off: never",
          MSBDAutoHideHomeHides(1, 0) && !MSBDAutoHideHomeHides(1, 1) && !MSBDAutoHideHomeHides(0, 0) && !MSBDAutoHideHomeHides(0, 1));
    // the room
    check("the room for windows: down to the screen's edge while the Dock hides itself, above the Dock else", MSBDAutoHideRoomEdge(1, 930.0, 1024.0) == 1024.0 && MSBDAutoHideRoomEdge(0, 930.0, 1024.0) == 930.0);
    // the room the windows are placed for, saved with them (regression 1.8.4 F2; the review of the fixes, H1 and M1)
    check("F2: placed with the Dock hiding itself, the crash guard turned it off at the start: changed; the same answer: the same; nothing saved: none",
          MSBDRoomAtStart(1, 0) == MSBDRoomChanged && MSBDRoomAtStart(0, 1) == MSBDRoomChanged && MSBDRoomAtStart(1, 1) == MSBDRoomSame
          && MSBDRoomAtStart(0, 0) == MSBDRoomSame && MSBDRoomAtStart(-1, 0) == MSBDRoomNone && MSBDRoomAtStart(-1, -1) == MSBDRoomNone);
    check("M1: the Dock part's answer not known yet (not loaded): unknown, never taken for the same answer (decided once it answers)",
          MSBDRoomAtStart(1, -1) == MSBDRoomUnknown && MSBDRoomAtStart(0, -1) == MSBDRoomUnknown);
    check("  ... written with the windows: the saved answer while pending (also while not known: the key is never dropped), else the one taken now",
          MSBDRoomToSave(1, -1) == 1 && MSBDRoomToSave(1, 0) == 1 && MSBDRoomToSave(0, 1) == 0 && MSBDRoomToSave(-1, 1) == 1 && MSBDRoomToSave(-1, 0) == 0
          && MSBDRoomToSave(-1, -1) == -1);
    check("Low 1: the answer for the room: the Dock part's own while loaded; switched off in Settings, or not loaded once SpringBoard has started: the shown Dock's (0)",
          MSBDRoomNowFrom(1, 1, 1, 30.0) == 1 && MSBDRoomNowFrom(1, 0, 1, 30.0) == 0 && MSBDRoomNowFrom(1, 1, 0, 30.0) == 0 && MSBDRoomNowFrom(0, 0, 0, 2.0) == 0
          && MSBDRoomNowFrom(0, 0, 1, 30.0) == 0 && MSBDRoomNowFrom(0, 0, 1, MSBD_DOCK_PART_LOAD_WAIT + 0.1) == 0);
    check("  ... not known only in SpringBoard's first seconds, before the Dock part could be there; so a room saved as 1 is followed (changed), never kept for good",
          MSBDRoomNowFrom(0, 0, 1, 2.0) == -1 && MSBDRoomAtStart(1, MSBDRoomNowFrom(0, 0, 1, 2.0)) == MSBDRoomUnknown
          && MSBDRoomAtStart(1, MSBDRoomNowFrom(0, 0, 1, 30.0)) == MSBDRoomChanged && MSBDRoomAtStart(1, MSBDRoomNowFrom(1, 1, 0, 30.0)) == MSBDRoomChanged);
    check("H1: Stage Manager's start tick never touches a room pending for another engine's restore (Aerial on an iPad that can run Stage Manager)",
          MSBDRoomTick(1, 0, 0, 0, 1) == MSBDRoomTickKeep && MSBDRoomTick(0, 0, 0, 1, 1) == MSBDRoomTickKeep && MSBDRoomTick(1, 0, 1, 0, 1) == MSBDRoomTickKeep);
    check("  ... the Stage Manager engine: its own placing drops it; ours waits for the desktop's own step, else follows once the start has settled",
          MSBDRoomTick(1, 1, 0, 1, 1) == MSBDRoomTickDrop && MSBDRoomTick(1, 1, 1, 1, 1) == MSBDRoomTickKeep && MSBDRoomTick(1, 1, 1, 0, 0) == MSBDRoomTickKeep
          && MSBDRoomTick(1, 1, 1, 0, 1) == MSBDRoomTickFollow && MSBDRoomTick(-1, 1, 1, 0, 1) == MSBDRoomTickKeep);
    // 1.8.7 per display: the in-app Dock answer's preference part for one stage's display (MSBDAutoHideInAppPref: other display, Apple's preference, the iPad's
    // switch, that display's own answer)
    check("1.8.7: the iPad's own stage as in 1.8.4: Apple's preference or our switch",
          !MSBDAutoHideInAppPref(0, 0, 0, 0) && MSBDAutoHideInAppPref(0, 1, 0, 0) && MSBDAutoHideInAppPref(0, 0, 1, 0) && MSBDAutoHideInAppPref(0, 1, 1, 1));
    check("  ... a TV with no setting of its own (its answer the iPad's): as the iPad's, the tick synced with the switch either way",
          MSBDAutoHideInAppPref(1, 1, 1, 1) && !MSBDAutoHideInAppPref(1, 0, 0, 0));
    check("  ... the TV switched on for itself, the iPad's off: the TV's Dock hides", MSBDAutoHideInAppPref(1, 0, 0, 1));
    check("  ... the TV switched off for itself, the iPad's on (Apple's tick follows the iPad's switch): the TV keeps its Dock", !MSBDAutoHideInAppPref(1, 1, 1, 0));
    check("  ... a tick our switch could not take (hides with the iPad's switch off): it still hides the TV's, as the iPad's", MSBDAutoHideInAppPref(1, 1, 0, 0));
    check("  ... the room of each display by its own answer: the TV's to its bottom edge while it hides, the iPad's above its Dock",
          MSBDAutoHideRoomEdge(MSBDAutoHideInAppPref(1, 0, 0, 1), 1312.8, 1440.0) == 1440.0 && MSBDAutoHideRoomEdge(0, 930.0, 1024.0) == 930.0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
