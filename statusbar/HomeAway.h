// HomeAway.h -- Home Minimizes Windows (1.7.9), plain C so that tools/test-homeaway.sh checks it on the Mac: which of the user's Homes minimize the
// windows. StatusBar.x feeds it each Home a person makes that SpringBoard reports to us -- a Home gesture's lift that activates Home (MacSwitcher.h
// DMMSWActivateWith: the bottom edge, four fingers, the trackpad) and a Home button press (MacSwitcherButton.h; Cmd-H runs the same press, and is
// told apart: a Home from the keyboard is SpringBoard's own, as before the switch -- KT, 1.7.9).
// SpringBoard is often at the Home Screen already with Aerial, Zetsu or MilkyWay4 windows on it (they float over the Home Screen), so a Home makes
// no workspace transition there and these two are what is left to see. The Stage Manager engine's windows go with SpringBoard's own Home
// transition (SMHomeRule.h DMSMHomeHide); only our own windows (Finder, TextEdit) are left for this rule there.
#ifndef HOMEAWAY_H
#define HOMEAWAY_H
enum { DMHomeAwayNone = 0, DMHomeAwayAll = 1, DMHomeAwayOurs = 2 };
// on: the switch; ours: the Home is our own simulated press (DMMinimize) or one made while it runs; keys: it came from the keyboard (Cmd-H:
// SpringBoard's Home shortcut, StatusBar.x DMHomeFromKeys); covered: the Lock Screen, the Cover Sheet or Control Center is up (the Home closes
// that, not the desktop); guided: a Guided Access session; sm: the Stage Manager engine runs; engineWindows / ourWindows: the engine's windows on
// screen now (not minimized, not on another desktop) and our own.
static inline int DMHomeAwayWhat(int on, int ours, int keys, int covered, int guided, int sm, unsigned engineWindows, unsigned ourWindows) {
    if (!on || ours || keys || covered || guided) return DMHomeAwayNone;
    if (sm) return ourWindows ? DMHomeAwayOurs : DMHomeAwayNone;
    return engineWindows + ourWindows ? DMHomeAwayAll : DMHomeAwayNone;
}
// One Home per gesture: SpringBoard activates the lift's destination once per root modifier that holds the gesture (two on 15.6.1, at the same
// moment). 1 = this one counts (it is *last's new time); 0 = the same lift again.
static inline int DMHomeAwayOnce(double now, double *last) {
    if (now - *last < 0.5) return 0;
    *last = now;
    return 1;
}
#endif
