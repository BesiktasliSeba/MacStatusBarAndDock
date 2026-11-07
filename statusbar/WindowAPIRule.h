// WindowAPIRule.h -- the window API's rules, V1 (1.8.3 item 1): the bridge KeyPilot's author wrote for this tweak (wanghuangjie, KeyPilot
// integrations/MSBDKeyPilotBridge.inc and WINDOW_MANAGEMENT.md, 4b2b247), ported with his names, arguments and return codes, so KeyPilot's
// client works with the stock tweak. Plain C, so the Mac test (tools/test-windowapi.c) runs this very code; statusbar/WindowAPI.h exports the
// functions from MacStatusBarCore.dylib and reads what they ask about in SpringBoard.
//  - int MSBDKeyPilotLayoutV1(const char *layout): one of the twelve layouts below for the front window, the Window menu's own (Fill Screen, Center,
//    the halves, the quarters, Small, Large). 0 dispatched, 1 not on the main thread, 2 not one of the twelve, 6 locked or busy (the Lock Screen or
//    Notification Center, a workspace transition, iPadOS's App Switcher or our Mac Switcher, one of our menus or questions), 3 no window engine,
//    4 no active app, 5 an app that only runs full screen. Checked in that order. Our own window in front (Finder, TextEdit) is laid out as the Window
//    menu lays it out, with or without an engine.
//  - int MSBDKeyPilotHomeV1(void): Home, every window minimized on every engine (Home Minimizes Windows' way, whatever its switch). 0 dispatched,
//    1 not on the main thread, 6 locked or in Guided Access. Once: a second call within a second is the same Home; SpringBoard busy, it waits for
//    the end (MSBDWinAPIHomeStep); at Home already, the windows only.
//  - int MSBDKeyPilotHomeEnvironmentV1(void): where SpringBoard is: 1 the Home Screen, 2 the App Switcher, 3 an app; -1 not on the main thread or not
//    readable, -2 locked. Read only.
// 0 is no proof that a window moved: the engines move windows after the call returns. V1 never changes; a V2 would come next to it.
#ifndef MSBD_WINDOW_API_RULE_H
#define MSBD_WINDOW_API_RULE_H
#include <stdbool.h>
#include <string.h>

enum {
    kMSBDWinAPIDispatched = 0,
    kMSBDWinAPIWrongThread = 1,
    kMSBDWinAPIUnknownLayout = 2,
    kMSBDWinAPINoEngine = 3,
    kMSBDWinAPINoActiveApp = 4,
    kMSBDWinAPIFullScreenOnly = 5,
    kMSBDWinAPIBusy = 6,
};
enum { kMSBDWinEnvHome = 1, kMSBDWinEnvSwitcher = 2, kMSBDWinEnvApp = 3, kMSBDWinEnvUnknown = -1, kMSBDWinEnvLocked = -2 };

// The twelve layouts, as the Window menu names them in the code (its rows' order: StatusBar.x DMOpenWindowMenu).
#define kMSBDWinAPILayoutCount 12
static const char *const kMSBDWinAPILayouts[kMSBDWinAPILayoutCount] = {
    "fill", "center", "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright", "small", "large" };
// Its index, or -1 (NULL, another spelling, another case).
static inline int MSBDWinAPILayoutIndex(const char *name) {
    if (!name) return -1;
    for (int i = 0; i < kMSBDWinAPILayoutCount; i++) if (!strcmp(name, kMSBDWinAPILayouts[i])) return i;
    return -1;
}

// What SpringBoard is doing when the layout is asked for (read on the main thread only).
typedef struct {
    bool mainThread;
    bool busy;            // locked, Notification Center, a workspace transition, a switcher, our menu or question
    bool nativeFront;     // our own window (Finder, TextEdit) is the front window
    bool engine;          // a window engine of ours runs (Aerial, Zetsu, MilkyWay4, Stage Manager)
    bool activeApp;       // an app is active (a window, or full screen)
    bool fullScreenOnly;  // ... one that only runs full screen
} MSBDWinAPIFacts;
static inline int MSBDWinAPILayoutStatus(const char *name, MSBDWinAPIFacts f) {
    if (!f.mainThread) return kMSBDWinAPIWrongThread;
    if (MSBDWinAPILayoutIndex(name) < 0) return kMSBDWinAPIUnknownLayout;
    if (f.busy) return kMSBDWinAPIBusy;
    if (f.nativeFront) return kMSBDWinAPIDispatched;
    if (!f.engine) return kMSBDWinAPINoEngine;
    if (!f.activeApp) return kMSBDWinAPINoActiveApp;
    if (f.fullScreenOnly) return kMSBDWinAPIFullScreenOnly;
    return kMSBDWinAPIDispatched;
}
static inline int MSBDWinAPIHomeStatus(bool mainThread, bool locked) {
    if (!mainThread) return kMSBDWinAPIWrongThread;
    return locked ? kMSBDWinAPIBusy : kMSBDWinAPIDispatched;
}
// Home, once (review 1.8.3 F10): a second Home asked for within a second of the last is the same Home -- KeyPilot's Cmd-H and iPadOS's own can
// come together, a press can be handed over twice. Asked while SpringBoard is busy (a transition of its own, iPadOS's Cmd-H Home, a Home press of
// ours): wait, 0.1 s at a time, at most 2 s, then nothing; free: at Home already the windows only (no second Home), else the windows and Home.
#define kMSBDWinHomeAgainSeconds 1.0
#define kMSBDWinHomeMaxTries 20
enum { kMSBDWinHomeGiveUp = 0, kMSBDWinHomeWait, kMSBDWinHomeMinimizeOnly, kMSBDWinHomeFull, kMSBDWinHomeLockedNow };
static inline bool MSBDWinAPIHomeAgain(double sinceLast) { return sinceLast >= 0.0 && sinceLast < kMSBDWinHomeAgainSeconds; }
// locked: the iPad locked, or a Guided Access session, now -- read again at every step, so a Home that waited does nothing once the iPad has locked
// meanwhile (review 1.8.3 P2-6: KeyPilot's Cmd-H, then the sleep button within 2 s, minimized the windows and pressed Home on the Lock Screen).
// The answer KeyPilot got stays 0.
static inline int MSBDWinAPIHomeStep(bool locked, bool busy, bool atHome, int tries) {
    if (locked) return kMSBDWinHomeLockedNow;
    if (busy) return tries < kMSBDWinHomeMaxTries ? kMSBDWinHomeWait : kMSBDWinHomeGiveUp;
    return atHome ? kMSBDWinHomeMinimizeOnly : kMSBDWinHomeFull;
}
// env: SpringBoard's unlocked environment mode, as read (read: it could be read).
static inline int MSBDWinAPIEnvironment(bool mainThread, bool locked, bool read, long long env) {
    if (!mainThread) return kMSBDWinEnvUnknown;
    if (locked) return kMSBDWinEnvLocked;
    return read && env >= kMSBDWinEnvHome && env <= kMSBDWinEnvApp ? (int)env : kMSBDWinEnvUnknown;
}

#endif
