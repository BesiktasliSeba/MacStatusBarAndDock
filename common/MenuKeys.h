// MenuKeys.h -- the hardware keyboard while one of the menu bar's menus is open (1.7.9, KT: a selected Settings row flickered as the pointer moved
// between our menus, A12Z 18.5). Plain C, so the Mac test (tools/test-menukeys.c) runs this very code; StatusBar.x (SpringBoard) and
// appbridge/AppBridge.x (every app) share it.
// Why: SpringBoard holding the keyboard focus for a menu takes it from the app in front, and iPadOS then turns that app's keyboard focus off -- its
// scene stops being the target of the keyboard's event deferring environment (UIKit's _UIFocusActiveSceneObserver_KeyboardEventDeferring) -- so its
// focused item (the selected sidebar row) drops to the unfocused look while a menu is open, and every switch from one menu to the next gave the focus
// back and took it again. On a Mac the menu bar does not make its app inactive. So when the app holding the keys runs our MacAppBridge, the menus
// leave the focus with it, and the bridge gives the open menu the keys that would reach the app: Esc closes the menu, the rest do nothing (what the
// focus lock did). Shortcuts that act before the app (iPadOS's system ones, ours in -sendEvent:) are not touched.
//  - The bridge says it is there: the state of MSBD_BRIDGE_KEYS_FMT (with the bundle's FNV-1a hash) is the process's pid.
//  - SpringBoard says a menu has the keys: the state of MSBD_MENU_KEYS_STATE is a lease -- the time in ms (CFAbsoluteTime x 1000), renewed every
//    kMSBDMenuKeysRenewMs, 0 when the menu goes. A lease older than kMSBDMenuKeysStaleMs counts as none, so a SpringBoard that went away mid-menu
//    leaves no app without its keys.
//  - The app's Esc: MSBD_MENU_ESC; SpringBoard closes the menu.
#ifndef MSBD_MENU_KEYS_H
#define MSBD_MENU_KEYS_H
#include <stdint.h>

#define MSBD_MENU_KEYS_STATE "com.besiktasliseba.macstatusbar.menukeys"
#define MSBD_MENU_ESC "com.besiktasliseba.macstatusbar.menu.esc"
#define MSBD_BRIDGE_KEYS_FMT "com.besiktasliseba.appbridge.keys.%08x"
#define kMSBDMenuKeysRenewMs 1000.0
#define kMSBDMenuKeysStaleMs 2500.0

// The lease stamp for now (ms), never 0 (0 = no menu).
static inline uint64_t MSBDMenuKeysStamp(double nowMs) { return nowMs >= 1.0 ? (uint64_t)nowMs : 1; }
// Whether a lease read now still holds: set, not older than kMSBDMenuKeysStaleMs, not from the future (a clock set back) by more than a second.
static inline int MSBDMenuKeysFresh(uint64_t stamp, double nowMs) {
    if (!stamp) return 0;
    double age = nowMs - (double)stamp;
    return age >= -1000.0 && age <= kMSBDMenuKeysStaleMs;
}

// The keys an open menu takes: the Keyboard page's typing, editing, navigation and F1-F12 keys (HID 0x04-0x65, as UIKit's -_keyCode gives them).
// Never the modifiers (0xE0-0xE7: they only change what other keys mean, and their state must stay right in the app) or anything past 0x65 (volume,
// media, F13-F24, the keypad's extra keys: the system's, or nothing).
#define kMSBDKeyEsc 0x29
static inline int MSBDMenuKeyTakeable(int code) { return code >= 0x04 && code <= 0x65; }
// Who has each key that is down: held, the keys whose press the menu took (their repeats and release go with it); app, the keys whose press the
// app got (their repeats and release stay the app's, a menu open or not: the app saw the key go down, so it sees it come up).
typedef struct { uint64_t held[2]; uint64_t app[2]; } MSBDMenuKeyHeld;
static inline int MSBDMenuKeyBit(const uint64_t set[2], int code) { return code >= 0 && code < 128 && ((set[code >> 6] >> (code & 63)) & 1); }
static inline void MSBDMenuKeySetBit(uint64_t set[2], int code, int on) {
    if (code < 0 || code >= 128) return;
    uint64_t bit = (uint64_t)1 << (code & 63);
    if (on) set[code >> 6] |= bit; else set[code >> 6] &= ~bit;
}
static inline int MSBDMenuKeyIsHeld(const MSBDMenuKeyHeld *h, int code) { return MSBDMenuKeyBit(h->held, code); }
static inline void MSBDMenuKeySetHeld(MSBDMenuKeyHeld *h, int code, int on) { MSBDMenuKeySetBit(h->held, code, on); }
static inline int MSBDMenuKeyIsApps(const MSBDMenuKeyHeld *h, int code) { return MSBDMenuKeyBit(h->app, code); }
enum { MSBDMenuKeyPass = 0, MSBDMenuKeyTake = 1, MSBDMenuKeyClose = 2 };
#define kMSBDKeyModsShortcut ((1LL << 18) | (1LL << 19) | (1LL << 20))   // Control, Option, Command (UIKeyModifierFlags)
// What the app does with a key event: pass it on (MSBDMenuKeyPass), keep it from the app (MSBDMenuKeyTake), or keep it and close the menu
// (MSBDMenuKeyClose: Esc alone). menuHasKeys is asked only when the answer matters (a press of a takeable key no one has yet), so a plain typing
// app pays nothing more. A key goes on as it started: the repeats and release of a press the menu took are taken too, even once the menu is gone;
// those of a press the app got are the app's, even while a menu has the keys (a key held from before the menu opened: its repeats during the menu
// were taken and marked the menu's, so its release was taken too and the app never saw it come up -- code review).
static inline int MSBDMenuKeyAct(MSBDMenuKeyHeld *h, int code, int isDown, long long modifiers, int (*menuHasKeys)(void)) {
    if (!MSBDMenuKeyTakeable(code)) return MSBDMenuKeyPass;
    if (MSBDMenuKeyIsHeld(h, code)) {
        if (!isDown) MSBDMenuKeySetHeld(h, code, 0);
        return MSBDMenuKeyTake;
    }
    if (MSBDMenuKeyIsApps(h, code)) {
        if (!isDown) MSBDMenuKeySetBit(h->app, code, 0);
        return MSBDMenuKeyPass;
    }
    if (!isDown) return MSBDMenuKeyPass;   // (a release nobody saw go down: the app's, as before)
    if (!menuHasKeys || !menuHasKeys()) { MSBDMenuKeySetBit(h->app, code, 1); return MSBDMenuKeyPass; }
    MSBDMenuKeySetHeld(h, code, 1);
    return code == kMSBDKeyEsc && !(modifiers & kMSBDKeyModsShortcut) ? MSBDMenuKeyClose : MSBDMenuKeyTake;
}

#endif
