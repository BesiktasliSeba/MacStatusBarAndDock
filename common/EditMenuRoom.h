// common/EditMenuRoom.h: the keyboard's room under UIKit's edit menu (1.8.8.2): plain C, the rule statusbar/EditMenuRoom.h runs in SpringBoard.
// Mac test tools/test-editmenuroom.sh.
//
// UIKit gives an edit menu (Cut, Copy, Paste) its container's bounds less these insets: the container's safe area, and at the bottom the keyboard
// with 6 points to spare (-[_UIEditMenuPresentation _preferredContentInsetsForContainerView] on iPadOS 16; -[_UIEditMenuContentPresentation
// _preferredContentInsetsForContainerViewWithConfiguration:] on iPadOS 18, the same formula):
//     bottom = MAX(safe area bottom, MAX(0, maxY(container bounds) minus minY(keyboard)) + 6)
// The keyboard's frame it takes is in the window scene's space, not the container's. SpringBoard's scene stays in the screen's fixed portrait space
// while its interface is turned, so in landscape the keyboard's top read 0 and the bottom inset was the whole screen plus 6: no room, and the menu
// was pinned above the top edge, under the menu bar. statusbar/EditMenuRoom.h takes the keyboard the last step into the container when the two
// spaces differ on the iPad's own screen and UIKit's answer is its formula on that frame (MSBDEditMenuIsUIKits), and asks this for the bottom inset.
#ifndef MSBD_EDIT_MENU_ROOM_H
#define MSBD_EDIT_MENU_ROOM_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

// UIKit's bottom inset: the keyboard's overlap of the container (none when it is not over it, or unreadable) and 6 points, or the safe area if larger.
static inline double MSBDEditMenuBottom(double safeBottom, double containerMaxY, double keyboardMinY) {
    double overlap = fmax(containerMaxY - keyboardMinY, 0.0);   // (fmax: a NaN reads as 0, as UIKit's fmaxnm does)
    double want = overlap + 6.0;
    return safeBottom < want ? want : safeBottom;               // (UIKit keeps the safe area when the comparison fails, a NaN included)
}

// Do the scene's space and the container's space agree? A rect converted from the scene's space into the container comes back where it was (half a
// point either way). The rect is uneven and at the origin, so a quarter turn, a half turn (upside down) and a shift all move it.
static inline CGRect MSBDEditMenuProbe(void) { return CGRectMake(0.0, 0.0, 10.0, 20.0); }
static inline int MSBDEditMenuSpacesAgree(CGRect probe, CGRect back) {
    return fabs(back.origin.x - probe.origin.x) <= 0.5 && fabs(back.origin.y - probe.origin.y) <= 0.5
        && fabs(back.size.width - probe.size.width) <= 0.5 && fabs(back.size.height - probe.size.height) <= 0.5;
}

// A keyboard frame worth taking into the container: every part a finite number. UIKit's CGRectZero (its answer for an undocked keyboard) is not
// taken either: UIKit reads it as a keyboard at the top, and its own answer for it is kept.
static inline int MSBDEditMenuKeyboardUsable(CGRect kb) {
    if (!isfinite(kb.origin.x) || !isfinite(kb.origin.y) || !isfinite(kb.size.width) || !isfinite(kb.size.height)) return 0;
    return !(kb.origin.x == 0.0 && kb.origin.y == 0.0 && kb.size.width == 0.0 && kb.size.height == 0.0);
}

// Is UIKit's bottom inset its own keyboard formula on the frame it read (that frame in the scene's space: the fault)? Only then is the keyboard's
// part worked out again. An answer UIKit made another way is kept as it is: a guard or a formula of an iPadOS this fix was not read on (17), or
// another tweak's hook of the method that changed it. (A hundredth of a point either way; a NaN is never UIKit's formula here.)
static inline int MSBDEditMenuIsUIKits(double uikitBottom, double safeBottom, double containerMaxY, double keyboardMinY) {
    return fabs(uikitBottom - MSBDEditMenuBottom(safeBottom, containerMaxY, keyboardMinY)) <= 0.01;
}

// Why UIKit's own answer is kept (the first of UIKit's own conditions, and ours, that does not hold), or MSBDEditMenuRedo: the keyboard's part is
// worked out again in the container's space.
typedef enum {
    MSBDEditMenuRedo = 0,
    MSBDEditMenuNoContainer,       // no container, window or window scene: nothing to convert with
    MSBDEditMenuSpacesSame,        // the scene's space is the container's: UIKit's keyboard frame is already right
    MSBDEditMenuOtherDisplay,      // the container is not on the iPad's own screen (the TV): the keyboard is not over it, and that screen never turns
    MSBDEditMenuRemoteKeyboard,    // the container is in the remote keyboard window: UIKit uses the safe area only
    MSBDEditMenuIgnoresKeyboard,   // the menu's configuration ignores the keyboard (iPadOS 18): the safe area only
    MSBDEditMenuKeyboardOff,       // no keyboard on screen: the safe area only
    MSBDEditMenuOtherBranch,       // not a text effects window: UIKit's other branch, which converts into the view itself
    MSBDEditMenuKeyboardUnusable,  // the keyboard's frame is UIKit's CGRectZero or not a number
    MSBDEditMenuNotUIKits,         // UIKit's bottom inset is not its keyboard formula on the frame it read: made another way, kept
    MSBDEditMenuKept               // (the debug switch keeps UIKit's answer)
} MSBDEditMenuCase;
static inline const char *MSBDEditMenuCaseText(MSBDEditMenuCase c) {
    switch (c) {
        case MSBDEditMenuRedo: return "the keyboard taken into the container's space";
        case MSBDEditMenuNoContainer: return "UIKit's own: no container, window or scene";
        case MSBDEditMenuSpacesSame: return "UIKit's own: the scene's space is the container's";
        case MSBDEditMenuOtherDisplay: return "UIKit's own: another display (the keyboard is on the iPad's own)";
        case MSBDEditMenuRemoteKeyboard: return "UIKit's own: the remote keyboard window";
        case MSBDEditMenuIgnoresKeyboard: return "UIKit's own: the menu ignores the keyboard";
        case MSBDEditMenuKeyboardOff: return "UIKit's own: no keyboard on screen";
        case MSBDEditMenuOtherBranch: return "UIKit's own: not a text effects window (its other branch)";
        case MSBDEditMenuKeyboardUnusable: return "UIKit's own: the keyboard's frame is zero or not a number";
        case MSBDEditMenuNotUIKits: return "UIKit's own: its bottom inset is not its keyboard formula on that frame";
        case MSBDEditMenuKept: return "UIKit's own: the debug switch";
    }
    return "?";
}
#endif
