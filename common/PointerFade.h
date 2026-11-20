// PointerFade.h -- the pointer's fade, said by the process that draws the pointer to SpringBoard (1.8.8, D48: Magnify Traffic Lights' hold under a
// resting pointer ends when the pointer fades, statusbar/LightMagnify.h). iPadOS hides the pointer itself: a resting one after its idle time (Pointer
// Control's Automatically Hide Pointer; about 8 s after the last move on the test iPads, the p05 rows), and for a touch on the screen or typing.
// pointeruid draws the pointer, and the state of each of its updates carries that hide (pointerAutoHidden: the flag the Mac pointer fades by,
// statusbar/macpointer/MacPointer.x). SpringBoard only sees UIKit cancel its hovers then, as it does for a layout under a resting pointer, so it cannot
// tell a fade from the others by itself. MacPointer runs in pointeruid on every iPad with the tweak (whatever the Pointer Style, also while it stands
// down for another pointer tweak) and says it here when it changes on the iPad's own display (another display has its own state; the hold is the
// iPad's only); SpringBoard reads it. Macros only, no function (nothing of it needs a crash map rule), so both use the very same name and values.
#pragma once
#define kMSBDPointerFadeNote "com.besiktasliseba.macpointer.faded"   // posted at each change; its state: one of the three below
#define MSBDPointerFadeUnsaid 0ULL   // nothing said: MacPointer not in pointeruid (switched off for it), or pointeruid not started since the boot
#define MSBDPointerFadeHidden 1ULL   // iPadOS hid the pointer: it faded (idle, a touch, typing)
#define MSBDPointerFadeShown  2ULL   // the pointer shows
#define MSBDPointerFadeOf(autoHidden) ((autoHidden) ? MSBDPointerFadeHidden : MSBDPointerFadeShown)   // pointeruid's flag as said
