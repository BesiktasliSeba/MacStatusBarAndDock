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
// Adapt to Trackpad & Mouse (1.8.8.1, KT 19 Nov: "When ipad is on magic keyboard/mouse the home minimizes windows option should be auto toggled
// off, and auto toggled on when using ipad by hand, so it should adapt automatically the same way menu bars work adaptively"): whether Home
// Minimizes Windows applies to this Home. on: its switch; adapt: Adapt to Trackpad & Mouse, under it; pointer: a trackpad or mouse is connected
// at this Home (SpringBoard's pointer manager, the answer the Haptic Touch menus adapt to: the Magic Keyboard for iPad's trackpad, a mouse, a
// Magic Trackpad; a keyboard alone is use by hand, as for the menus). With a trackpad or mouse Home leaves the windows, as on a Mac; by hand it
// minimizes them. Neither switch is ever written for it: what Home does follows the input, the switches stay as the user set them. Every place
// that read the switch for a Home's decision takes this instead (StatusBar.x DMHomeAdaptMinimizes); the pointer is read only with both on.
static inline int DMHomeAwayOn(int on, int adapt, int pointer) { return on && !(adapt && pointer); }
// One Home per gesture: SpringBoard activates the lift's destination once per root modifier that holds the gesture (two on 15.6.1, at the same
// moment). 1 = this one counts (it is *last's new time); 0 = the same lift again.
static inline int DMHomeAwayOnce(double now, double *last) {
    if (now - *last < 0.5) return 0;
    *last = now;
    return 1;
}
#endif
