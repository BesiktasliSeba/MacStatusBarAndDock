// SMBarHome.h -- which window title bars leave with their windows going Home (Stage Manager engine; MacStatusBar&Dock 1.8.7, KT 11 Nov).
// Plain C: the Mac test (tools/test-smbarhome.sh) runs this very rule.
// Going Home -- a switcher's environment 1, the Home Screen itself -- the windows of that display zoom into their icons and our title bars fade
// out with them (StatusBar.x DMSMFadeBar, 24 Oct: no line left over the icon). Each display has a switcher of its own (the iPad's main one, a
// TV's own), and each sends its transitions' environment; the last one of any switcher (gEnvMode) is not the environment of every display.
// Read that way, the iPad going Home faded the title bars of the windows on the TV too, and every layout of a TV window kept its bar faded while
// the iPad stayed at its Home Screen: a centered window on the TV had no title bar and no traffic lights (KT, A12Z with the 4K TV, 11 Nov).
// So a title bar leaves only when its own display's switcher goes Home (where its transition is going, from the start, else where it is).
// Where that switcher can't be read: a window on the iPad as before (the last event), a window on another display keeps its bar.
// The App Switcher's reads of the same global follow the same rule (MSBDSMInSwitcher, below).
#ifndef MSBD_SM_BAR_HOME_H
#define MSBD_SM_BAR_HOME_H

#define kMSBDEnvHome 1       // (SpringBoard's environment modes: 1 the Home Screen, 2 the App Switcher, 3 an application -- the desktop)
#define kMSBDEnvSwitcher 2

// Whether a window's (or a screen point's) own display's switcher is at environment `mode`. ownRead: its display's switcher was read (ownEnv its
// environment); lastEventEnv: the last transition event of any switcher; onMain: the window or point is on the iPad's own screen. Not read: the
// iPad's by the last event (as before), another display's never by an event that may be the iPad's.
static inline int MSBDSMOwnEnvIs(int ownRead, long long ownEnv, long long lastEventEnv, int onMain, long long mode) {
    if (ownRead) return ownEnv == mode;
    return onMain && lastEventEnv == mode;
}
// A title bar leaves with its window going Home.
static inline int MSBDSMBarGoesHome(int ownRead, long long ownEnv, long long lastEventEnv, int onMain) {
    return MSBDSMOwnEnvIs(ownRead, ownEnv, lastEventEnv, onMain, kMSBDEnvHome);
}
// The same one global was read as "the App Switcher is up" for every display: a window card scaled in it (DMSMChrome: the card's bar is the
// card's, not interactive, no grips), a touch on the menu bar (DMSMScreenPointOnMenuBar) and on a full-screen window under windows
// (DMSMFullScreenOwnAt) not taken as the bar's / the window's own there. Read as one: with the iPad's App Switcher up, the TV's menu bar and
// full-screen window left their touches to Stage Manager's window gestures (and the TV's App Switcher the iPad's), and a window Stage Manager
// shrinks on one display had a bar that took no taps and no grips while the other display's App Switcher was up. Each now asks its own display's switcher.
static inline int MSBDSMInSwitcher(int ownRead, long long ownEnv, long long lastEventEnv, int onMain) {
    return MSBDSMOwnEnvIs(ownRead, ownEnv, lastEventEnv, onMain, kMSBDEnvSwitcher);
}

#endif
