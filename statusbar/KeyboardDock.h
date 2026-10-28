// KeyboardDock.h -- when the Dock goes under SpringBoard's own on-screen keyboard (our fields: Finder, TextEdit, the desktop's rename), plain C
// on CoreGraphics so the Mac test (tools/test-kbdock.m) runs this very code; Desktop.h's keyboard watch calls it.
//  - A keyboard frame from a notification comes in the screen's fixed (portrait) space or in the interface's, depending on the iPadOS and the
//    kind of change: both are given (f, and g = f turned into the interface's space by UIKit) and the one that lies on the screen counts.
//  - Docked: the part on the screen spans the whole width, reaches the bottom edge and is taller than 150 pt (a hardware keyboard's bar is
//    about 70 pt; iPadOS 18 also announces a 3 pt keyboard). A frame that ends below the screen is the keyboard going (Esc ending a search
//    announced {0, 1024, 1366, 440} on 18.5): not docked.
//  - The decision: our field must hold the keyboard. For 1.5 s after a notification its answer counts, or the keyboard drawn in SpringBoard's
//    keyboard windows; after that the drawn keyboard alone where one is drawn (iPadOS 18 grows "Show Keyboard" to the full keyboard, and
//    shrinks it to the bar again, without saying so), the last answer where none is drawn (an iPadOS that draws it elsewhere).
#ifndef MSBD_KEYBOARD_DOCK_H
#define MSBD_KEYBOARD_DOCK_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

#define kMSBDKeyboardDockedMinH 150.0
#define kMSBDKeyboardNoteFresh 1.5

static inline bool MSBDKeyboardRectDocked(CGRect r, CGSize screen) {
    CGRect on = CGRectIntersection(r, CGRectMake(0, 0, screen.width, screen.height));
    return !CGRectIsNull(on) && on.size.width >= screen.width - 1.0 && CGRectGetMaxY(on) >= screen.height - 1.0 && on.size.height > kMSBDKeyboardDockedMinH;
}
static inline bool MSBDKeyboardNoteDocked(CGRect f, CGRect g, CGSize screen) {
    return MSBDKeyboardRectDocked(f, screen) || MSBDKeyboardRectDocked(g, screen);
}
// The announced frame that lies on the screen (screen points), CGRectZero when neither does or it has no area (the keyboard going or gone).
static inline CGRect MSBDKeyboardNoteOnScreen(CGRect f, CGRect g, CGSize screen) {
    CGRect inside = CGRectInset(CGRectMake(0, 0, screen.width, screen.height), -1.0, -1.0);
    CGRect r = CGRectContainsRect(inside, f) ? f : (CGRectContainsRect(inside, g) ? g : CGRectZero);
    return CGRectIsEmpty(r) ? CGRectZero : r;
}
static inline bool MSBDKeyboardDockUnder(bool ownField, bool drawnDocked, bool sawDrawnKeyboard, bool notedDocked, double secondsSinceNote) {
    if (!ownField) return false;
    if (drawnDocked) return true;
    return notedDocked && (secondsSinceNote < kMSBDKeyboardNoteFresh || !sawDrawnKeyboard);
}
// The Dock's floor (dock/Dock.x kDockMinWindowLevel, 1034: the Dock above an engine window that overlaps it) never sits over a keyboard. It
// already stepped aside for the on-screen keyboard (more than 100 pt, the status bar's tick: layering audit #1). A hardware keyboard's input bar
// (15: 69 pt, 18: 71.5 pt; 18's 3 pt placeholder is no bar) did not count, so where SpringBoard's own keyboard windows lie under the floor --
// Finder's fields with Zetsu: native layer 1003, keyboard windows 1004 / 1005 -- a window over the Dock raised it over the bar and its keyboard
// button (M1 15.6.1, 1.6.0). The floor now steps aside for that bar too; where those windows are above the floor (Aerial and MilkyWay4: 1035,
// a name typed on the desktop over a raised Dock) nothing changes. barH: the bar SpringBoard's own keyboard windows draw (screen points),
// barLevel: the highest level of a keyboard window drawing it.
#define kMSBDDockFloorLevel 1034.0
#define kMSBDInputBarMinH 20.0
static inline bool MSBDOwnBarUnderDockFloor(bool hardwareKeyboard, double barH, double barLevel, double floorLevel) {
    return hardwareKeyboard && barH >= kMSBDInputBarMinH && barH < 100.0 && barLevel < floorLevel - 0.25;
}
#endif
