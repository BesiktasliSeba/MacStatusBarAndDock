// DesktopHold.h -- a finger (or a click) held on the desktop (Desktop.h -dm_holdCheck:, -dm_touchIsOursFor:, 1.7.8): two rules, plain C, run by the
// Mac test tools/test-desktophold.c.
#pragma once

// ---- 1. the hold's menu (1.7.7 fix-round review m2) ----
// A finger held still opens our menu (0.45 s; a click 0.75 s). One that is moving at that moment, short of a drag's distance, is on its way into a
// drag or the selection rectangle: no menu yet, looked at again until it comes to rest (within 4 pt for 0.1 s). A finger that kept wobbling --
// more than 4 pt within every 0.1 s -- while staying within the 10 pt a drag needs never came to rest: its other gestures had already let go (the
// press was ours), so it got neither our menu nor iPadOS's own hold. Held that long without leaving the 10 pt, it is a hold: the menu opens anyway
// at kMSBDDesktopHoldAnyway, as UIKit's own long press fires for any finger that stays within its 10 pt (a slow drag leaves them long before).
#define kMSBDDesktopHoldAnyway 1.0     // (seconds from the touch-down)
#define kMSBDDesktopHoldCheckCap 3.0   // (no further looks after this: the finger lifted or dragged long before)
typedef enum { MSBDHoldWait = 0, MSBDHoldMenu = 1, MSBDHoldNone = 2 } MSBDHoldStep;
// held: seconds since the touch-down; restFor: seconds since it last came to rest (moved more than 4 pt); fromDown: its distance from where it
// went down; pointer: a click (a drag's distance is 4 pt there, a finger's 10).
static inline MSBDHoldStep MSBDDesktopHoldStep(double held, double restFor, double fromDown, int pointer, double restTime) {
    if (fromDown > (pointer ? 4.0 : 10.0)) return MSBDHoldNone;   // (moved: a drag's, as the move itself tells)
    if (restFor >= restTime) return MSBDHoldMenu;                 // (at rest)
    if (!pointer && held >= kMSBDDesktopHoldAnyway) return MSBDHoldMenu;   // (a finger wobbling in place this long: a hold)
    return held < kMSBDDesktopHoldCheckCap ? MSBDHoldWait : MSBDHoldNone;
}

// ---- 2. whose touch it is: the desktop's, or a Home Screen gesture's (1.7.7 fix-round review N1) ----
// Decided once per touch. The Dock's swipe down (dock/Dock.x) asks when its pan begins; the desktop takes a move once the finger has been held
// long enough (0.35 s; on an icon 0.3 s) and moved 10 pt. Asked separately, the two could both say yes to one finger: a pan beginning just before
// the hold time opened the App Library, and the same finger's move a moment later drew the rectangle under it. So the first answer sticks:
// once the desktop has said "ours" it stays ours, and once the swipe down has fired the Dock tells the desktop (MSBDDesktopTouchGivenAway), which
// lets that touch go -- no rectangle, drag or menu from it.
typedef enum { MSBDTouchUndecided = 0, MSBDTouchDesktop = 1, MSBDTouchGivenAway = 2 } MSBDTouchOwner;
// The answer to a Home Screen gesture that asks to begin, and what the desktop notes for the touch (*owner). takeAfter: how long the finger must
// have been held for a move to be the desktop's (DMDesktopHoldToTake); a pointer's press is the desktop's at once.
static inline int MSBDDesktopTouchOursAnswer(MSBDTouchOwner *owner, int dragging, int holdMenu, int pointer, double held, double takeAfter) {
    if (*owner == MSBDTouchGivenAway) return 0;
    if (*owner == MSBDTouchDesktop) return 1;
    if (dragging || holdMenu || pointer || held >= takeAfter) { *owner = MSBDTouchDesktop; return 1; }
    return 0;   // (not decided yet: a later ask, once held long enough, can still find it ours)
}
// The swipe down fired for this touch: the desktop lets it go -- unless it was the desktop's already (then the Dock never fires: it asked first).
static inline void MSBDDesktopTouchGiveAway(MSBDTouchOwner *owner) { if (*owner == MSBDTouchUndecided) *owner = MSBDTouchGivenAway; }
