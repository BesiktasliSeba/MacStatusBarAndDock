// KeyboardBehind.h -- which windows may not take the hardware keyboard (StatusBar.x DMKeyboardFocusBehindWindows), plain Foundation so the Mac test
// (tools/test-kbbehind.m) runs this very code.
//  - With a window engine (Aerial, Zetsu, MilkyWay4) every window's app is a foreground scene, and SpringBoard gives the hardware keyboard to
//    whichever of them asks for it last. An app whose text field puts itself back whenever it goes (Amazon's search screen) asks again as soon as
//    another window takes the keyboard, so a click in the other window's field lost the keys to it (KT, M1 15.6.1, 30 Oct: Settings' search typed
//    into Amazon). On a Mac only the active app gets the keys.
//  - So every window whose app is not the active one (the app the menu bar names: the front window's, or the full-screen app a tap reclaimed)
//    is kept from the keyboard; the active app's windows never are. Only while a hardware keyboard is attached: the on-screen keyboard's behaviour
//    without one is left exactly as it was (each app's keyboard comes with a tap in its own field).
#ifndef MSBD_KEYBOARD_BEHIND_H
#define MSBD_KEYBOARD_BEHIND_H
#import <Foundation/Foundation.h>

// windows: the bundle of each window (any order; an app may have several); active: the active app's bundle (nil: none -- the Home Screen, or a
// window of our own such as Finder); hardwareKeyboard: one is attached; engine: a window engine of SpringBoard's windows runs (not Stage Manager,
// whose windows SpringBoard knows itself). Returns the bundles whose windows may not take the keyboard now.
static inline NSSet<NSString *> *MSBDKeyboardBehind(NSArray<NSString *> *windows, NSString *active, BOOL hardwareKeyboard, BOOL engine) {
    NSMutableSet<NSString *> *out = [NSMutableSet set];
    if (!hardwareKeyboard || !engine) return out;
    for (NSString *b in windows) if (b.length && ![b isEqualToString:active]) [out addObject:b];
    return out;
}

#endif
