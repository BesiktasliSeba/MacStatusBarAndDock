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
#include <math.h>
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
// On iPadOS 16.7.7 Stage Manager in landscape (1024 x 768), ~10-20 ms after an app's real landscape keyboard notification
// ({360, 0, 408, 1024} -> {0, 360, 1024, 408}, docked 1), an unrotated portrait scene in SpringBoard (768 x 1024) posts a companion
// notification with f = {0, 616, 768, 408} (or bar {0, 969, 768, 55}): f.size.width == screen.height and CGRectGetMaxY(f) == screen.width,
// which converts to {616, 0, 408, 768} off the right/bottom of the 1024 x 768 screen and clobbered gSMKeyboardShown back to 0.
static inline bool MSBDKeyboardNoteForeignScene(CGRect f, CGRect g, CGSize screen) {
    if (CGRectIsNull(f) || CGRectIsEmpty(f) || fabs(screen.width - screen.height) < 2.0) return false;
    if (MSBDKeyboardNoteDocked(f, g, screen)) return false;
    return fabs(f.origin.x) <= 2.0 && fabs(f.size.width - screen.height) <= 2.0
        && f.size.height >= 20.0 && fabs(CGRectGetMaxY(f) - screen.width) <= 2.0;
}
// The announced frame that lies on the screen (screen points), CGRectZero when neither does or it has no area (the keyboard going or gone).
static inline CGRect MSBDKeyboardNoteOnScreen(CGRect f, CGRect g, CGSize screen) {
    CGRect inside = CGRectInset(CGRectMake(0, 0, screen.width, screen.height), -1.0, -1.0);
    CGRect r = CGRectContainsRect(inside, f) ? f : (CGRectContainsRect(inside, g) ? g : CGRectZero);
    return CGRectIsEmpty(r) ? CGRectZero : r;
}
// The keyboard the Downloads panel stands above (dock/Downloads.m; 1.8.2.2, code review 4): the part of it on the screen (screen points), CGRectZero for none.
// f: the announced frame read in the interface's space, g: read in the fixed space and turned into the interface's (as above). Which space a frame came in shows by
// what it is in the right one, never by the iPadOS alone (18.5 announces its full keyboard in the fixed space and the hardware keyboard's bar in the interface's):
//  - a docked keyboard or a hardware keyboard's bar lies across the screen's width and reaches its bottom edge, maybe announced taller than it is shown (a frame
//    reaching below the screen: only its part on the screen counts -- its top is where the panel ends). A frame read in the wrong space is turned a quarter: it
//    lies along a side edge, partly off the screen;
//  - otherwise a floating, undocked or split keyboard, wholly on the screen, never taller than it is wide: a small one can lie on the screen read either way (a
//    320 x 250 floating keyboard is 250 x 320 read in the wrong one), so the reading that is wider than tall counts; when both are (turned a half: portrait upside
//    down), the fixed space, the one SpringBoard is told the frame in (15-17, and 18 for its full keyboard).
// MSBDKeyboardNoteOnScreen (the Dock's floor, above) took the first reading that lay wholly on the screen: a small keyboard in the fixed space was read in the
// interface's, and a keyboard announced taller than shown was no keyboard.
static inline CGRect MSBDKeyboardPanelFrame(CGRect f, CGRect g, CGSize screen) {
    if (!(screen.width > 0.0) || !(screen.height > 0.0)) return CGRectZero;
    CGRect scr = CGRectMake(0, 0, screen.width, screen.height), inside = CGRectInset(scr, -1.0, -1.0);
    CGRect r[2] = { g, f };   // (the fixed space first wherever both readings say the same)
    for (int i = 0; i < 2; i++) {   // (across the bottom)
        if (CGRectIsNull(r[i]) || CGRectIsEmpty(r[i])) continue;
        CGRect on = CGRectIntersection(r[i], scr);
        if (!CGRectIsNull(on) && !CGRectIsEmpty(on) && on.size.width >= screen.width - 1.0 && CGRectGetMaxY(on) >= screen.height - 1.0) return on;
    }
    for (int pass = 0; pass < 2; pass++)   // (wholly on the screen: wider than tall first)
        for (int i = 0; i < 2; i++) {
            if (CGRectIsNull(r[i]) || CGRectIsEmpty(r[i]) || !CGRectContainsRect(inside, r[i])) continue;
            if (pass == 0 && !(r[i].size.width > r[i].size.height)) continue;
            return CGRectIntersection(r[i], scr);
        }
    return CGRectZero;
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
// The Keyboard Button's tidy pill (StatusBar.x DMPlaceKeyboardPillIn, iPadOS 15): the hardware keyboard's pill window is scaled into the status bar
// only while that window holds the pill alone. It is also where another process's keyboard is drawn (Spotlight's search: SBMedusaHostedKeyboardWindow),
// which SpringBoard's own keyboard hosts do not show: ownH is what they show, remoteH UIKit's record of the keyboard on the screen whichever process
// shows it (_UIRemoteKeyboards' current state). A full keyboard there (over 100 pt: no bar or pill is that tall) is no pill: the window stays as it
// is (M1 15.6.1, 28 Oct, 1.7.0: Show Keyboard in Spotlight, then the keyboard shrank into the status bar). The height the pill's decision reads:
static inline double MSBDKeyboardPillMeasure(double ownH, double remoteH) {
    return remoteH > 100.0 && remoteH > ownH ? remoteH : ownH;
}
// Stage Manager's in-app Dock hides for a software keyboard only while a real docked on-screen keyboard is up (smDockedShown, converted from the
// fixed space on iPadOS 16/17/18 alike), the Dock itself does not hold that keyboard, and the Dock sits along the bottom edge where the full-width
// keyboard covers it (another display's Dock is always at the bottom). With the Dock on the left or right edge on the iPad's screen (dockSide != 0),
// typing in Notes or any app leaves the Dock on screen unless Automatically Hide and Show the Dock is on (1.8.9.1).
static inline bool MSBDKeyboardSMHidesDock(bool appleKeyboard, bool smDockedShown, bool dockOwnsKeyboard, int dockSide, bool otherDisplay) {
    if (!appleKeyboard || !smDockedShown || dockOwnsKeyboard) return false;
    return otherDisplay || dockSide == 0;
}
// SBFloatingDockWindow's level while SpringBoard's own docked keyboard is up for one of our fields (Desktop.h DMKeyboardDockDecide):
//  - Bottom Dock (dockSide == 0): -3.0 (under SBHomeScreenWindow at -2.0, since the full-width bottom keyboard covers the whole bottom Dock).
//  - Left or Right Dock (dockSide != 0): never under SBHomeScreenWindow (-2.0), or the whole side Dock disappears behind the Home Screen wallpaper
//    while typing (1.8.9.1). With an active native window (Finder / TextEdit: gNativeLayer at 6.0 on Stage Manager, keyboard at 7.0 / 8.0), step
//    just below gNativeLayer (5.5: above SBHomeScreenWindow -2.0 and SBMainSwitcherWindow 5.0, under the keyboard at 7.0 / 8.0); where gNativeLayer
//    and its keyboard are already above 25.0 (Zetsu 1003/1004, Aerial/MilkyWay4 1034/1035) or for desktop typing (1035/1036), keep 25.0 (with the
//    1034 floor stepped aside) so the side Dock stays visible and the keyboard covers only its lower end.
static inline double MSBDKeyboardOwnDockLevel(int dockSide, bool nativeFocus, double nativeLevel) {
    if (dockSide == 0) return -3.0;
    if (nativeFocus && nativeLevel > -1.0 && nativeLevel < 25.0) return nativeLevel - 0.5;
    return 25.0;
}
// On iPadOS 16-18 Stage Manager, an app's docked software keyboard is hosted in SBMedusaHostedKeyboardWindow at level 20.0 (16.7.7) or
// UIRemoteKeyboardWindow, while SBFloatingDockWindow sits at 25.0. When the Dock is on the Left or Right edge (dockSide != 0) and stays
// visible while typing, lower SBFloatingDockWindow to 5.5 (above SBHomeScreenWindow -2.0 and SBMainSwitcherWindow 5.0, under MSBNativeLayer
// 6.0 and every keyboard window at 7.0 / 8.0 / 20.0) so the keyboard draws and receives touches cleanly over the lower end of the side Dock.
#define kMSBDKeyboardSMDockLevel 5.5
static inline bool MSBDKeyboardSMDockUnder(bool smFree, bool smDockedShown, bool dockOwnsKeyboard, int dockSide) {
    return smFree && smDockedShown && !dockOwnsKeyboard && dockSide != 0;
}
#endif
