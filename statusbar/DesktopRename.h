// DesktopRename.h -- where a name edited on the desktop is typed (1.6.0): plain C, run by the Mac test tools/test-deskrename.sh.
// UIKit puts SpringBoard's keyboard windows just above the window that holds the field being typed in (-[UIKeyboardSceneDelegate
// setWindowLevel:sceneLevel:forResponder:], and again whenever that window's level changes): one level up for the text effects window, two for
// the keyboard's own. Measured on the iPad 2 (16.7.7): the Home Screen's window at -2 gave -1 / 0, our native layer at 6 gave 7 / 8. A name typed
// in the desktop -- the Home Screen's window -- so had its keyboard under every app window and under the Dock. The field is therefore typed in a
// window of its own (Desktop.h, DMDesktopRenameHost), whose level comes from here.
#include <CoreGraphics/CoreGraphics.h>

// The level of the window the name is typed in. levels: the windows the keyboard must not be under -- the Dock, the engines' app windows, our
// native layer while it shows --, in any order. A window at or above our menu window's level does not count (our menus, the Cover Sheet, an app's
// own keyboard window over them). Just above the highest one, and never so high that the two keyboard windows (+1, +2) reach our menu window.
static inline CGFloat MSBDRenameHostLevel(const CGFloat *levels, int count, CGFloat menuLevel) {
    CGFloat top = -2.0;   // (the Home Screen's window: the desktop's own)
    for (int i = 0; i < count; i++) if (levels[i] > top && levels[i] < menuLevel) top = levels[i];
    CGFloat want = top + 1.0, cap = menuLevel - 3.0;
    return want < cap ? want : cap;
}
// The field on the screen: where it belongs (under its icon), or moved up to just above a keyboard that would cover it, 8 points between them.
static inline CGRect MSBDRenameFieldFrame(CGRect home, CGRect keyboard) {
    CGRect f = home;
    if (!CGRectIsEmpty(keyboard) && CGRectGetMaxY(f) > CGRectGetMinY(keyboard) - 8.0) f.origin.y = CGRectGetMinY(keyboard) - 8.0 - f.size.height;
    return f;
}
