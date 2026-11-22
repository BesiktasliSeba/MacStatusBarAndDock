// BarFront.h -- which front each copy of the menu bar shows: every display's menu bar is its own (MacStatusBar&Dock 1.8.8.2, B69, KT 21 Nov 2026).
// Plain C: the Mac test (tools/test-barfront.sh) runs this very rule, and StatusBar.x's DMBarFrontOf asks it for every copy it lays out.
// Until 1.8.8.1 every copy of the bar (the iPad's, the TV's, a full-screen card's strip) was laid out from one global answer: the active app (the
// most recently used window on ANY display) and one lights decision (the iPad's full-screen window). So the TV's bar named the app opened on the
// iPad and showed its traffic lights (KT, A12Z with the TV, 21 Nov: "when the agent opens an app on the ipad, ... the app name also appears on tv
// status bar, as well as its traffic lights"), and a TV window's full-screen lights were on no bar. KT's rule: each display's bar is independent,
// at full strength: it follows its own display's front window (that app's name and menus; Finder when there is no window on it), and a window's
// lights are only ever on its own display's bar. The one active app (the keyboard, the coloured window lights, Command-Tab) stays as it was.
// With the iPad alone nothing changes: every state gives 1.8.8's answer.
#ifndef MSBD_BAR_FRONT_H
#define MSBD_BAR_FRONT_H

#define kMSBDBarFrontActive 0   // the active window, as 1.8.8 named it (that display is the one in use)
#define kMSBDBarFrontShown  1   // the front window of the stage that display shows
#define kMSBDBarFrontNone   2   // no window on that display: Finder (its Home Screen, its empty desktop, its App Switcher with no stage)
#define kMSBDBarFrontRecent 3   // its switcher can't be read: the most recent stage still drawn on that display (the iPad's: DMSMIPadStageShown)

#define kMSBDBarEnvHome 1       // (SpringBoard's environment modes: 1 the Home Screen or a display's empty desktop, 2 the App Switcher, 3 application)

// tvUp: a copy of ours is on another display now (an extended display, a TV); onTV: this copy is on it. activeHere: the active window is on this
// copy's display (Stage Manager engine: the display of the most recent stage, the iPad when there is none). homeRule: the iPad's own Home Screen
// names Finder while another display is up (the Stage Manager engine: its windows are cards in the switcher; the other engines' windows are views
// over the Home Screen, so the iPad in use keeps 1.8.8's answer there). read: this display's own switcher was read, env its environment; shows: it
// shows a stage then; activeInShown: the active window is one of that stage's windows.
static inline int MSBDBarFrontWay(int tvUp, int onTV, int activeHere, int homeRule, int read, long long env, int shows, int activeInShown) {
    if (!onTV && !tvUp) return kMSBDBarFrontActive;                                   // the iPad alone: 1.8.8's answer, whatever else
    if (!onTV && activeHere) return (homeRule && read && env == kMSBDBarEnvHome) ? kMSBDBarFrontNone : kMSBDBarFrontActive;
    if (!read) return activeHere ? kMSBDBarFrontActive : kMSBDBarFrontRecent;
    if (!shows) return kMSBDBarFrontNone;
    return activeInShown ? kMSBDBarFrontActive : kMSBDBarFrontShown;
}
// Whether a copy shows the traffic lights for its front (with Show Window Buttons on, unlocked, an app named). ownLights: the lights it shows act
// on its own front (the Stage Manager engine, where every request names a window, on any display; the other engines' lights act on the active app,
// so only the copy whose front is the active one shows them, and a TV's never: their windows are the iPad's). window: that front is a window with
// its own title bar and lights (not the full-screen window of its stage).
static inline int MSBDBarLightsFor(int way, int onTV, int ownLights, int window) {
    if (window) return 0;
    if (ownLights) return 1;
    return way == kMSBDBarFrontActive && !onTV;
}

#endif
