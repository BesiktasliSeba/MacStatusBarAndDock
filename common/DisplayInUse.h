// DisplayInUse.h -- which display is in use while another display is up, with the Stage Manager engine (MacStatusBar&Dock 1.8.8.2, B81).
// Plain C: the Mac test (tools/test-displayinuse.sh) runs these very rules, and StatusBar.x's DMBarFrontInUse... functions keep this state.
// KT's rule: as on a Mac with two displays, the app you last touched or clicked is the active one, on either display.
// Until 1.8.8.1.1 the active window was the front window of SpringBoard's most recent stage, on any display. That order changes only with a
// workspace transition, so (iPadOS 18.5 with a TV):
//  - a click or a tap on a window that was already in front on its display, or on its Dock icon, made no transition: SpringBoard gave that app
//    the keyboard, but the other display's stage stayed the most recent and its app the active one (the iPad's window lights grey);
//  - an action from a display's own menu bar on that display's window while the other display was in use (its traffic lights, the App menu's
//    Minimize) is a transition there: that display's stage came first and its app became the active one -- a minimized window's app too.
// Now the display in use is a state of its own:
//  - the user's touch, click or bring-forward of a window on a display (a tap, a click, its title bar, its Dock icon, Command-Tab, the Mac
//    Switcher, Spotlight, the Window menu) makes that display the one in use;
//  - SpringBoard's most recent stage becoming another one (on another display, or another window in front of it: a launch, an app opened any other
//    way) makes its display the one in use once that stage is shown there (a stage that came first only because the one before it was taken out,
//    or a minimized window's, is not an activation), unless the display in use is held then:
//  - held after a user's touch (a transition asked before it and landing after it does not take the display back) and after an action from the
//    other display's bar on its own window (the transition that action asks is not the user's activation of that display); an app's icon tapped
//    lets go of a hold (the transition it asks is the user's, on whichever display its window comes).
// Displays: 0 the iPad, 1 the other display (iPadOS drives one other display at a time). With the iPad alone the state is never asked about.
#ifndef MSBD_DISPLAY_IN_USE_H
#define MSBD_DISPLAY_IN_USE_H

#define kMSBDInUseTouchHold 0.6   // a user's touch holds its display this long against a transition asked before it
#define kMSBDInUseBarHold 2.0     // an action from the other display's bar holds the display in use this long against the transition it asks

typedef struct { int known, inUse; unsigned long long firstSig; double holdUntil; } MSBDInUseState;

// SpringBoard's most recent stage, read now: sig says what it is (its display, its front window and whether it is shown on that display; 0 no
// stage), d its display, shown: it is shown there. Returns 1 when the display in use changed. The first reading takes the most recent stage's
// display, as 1.8.8.1 did. A new one that is not shown is noted only: when it comes on screen (its window brought back, a launch's transition
// done) it is a new one again, and counts then.
static inline int MSBDInUseFirst(MSBDInUseState *s, unsigned long long sig, int d, int shown, double now) {
    if (!s) return 0;
    if (!s->known) {
        s->known = 1; s->firstSig = sig;
        if (!sig || s->inUse == d) return 0;
        s->inUse = d;
        return 1;
    }
    if (sig == s->firstSig) return 0;
    s->firstSig = sig;
    if (!sig || !shown || d == s->inUse || now < s->holdUntil) return 0;
    s->inUse = d;
    return 1;
}
// A reading the hold keeps from taking the display in use (MSBDInUseFirst answers 0 for it, asked first): a new most recent stage shown on the other
// display while held. Its transition may have given that stage's app the keys: they go back to the active window (StatusBar.x, review 1.8.8.2).
static inline int MSBDInUseHeld(const MSBDInUseState *s, unsigned long long sig, int d, int shown, double now) {
    return s && s->known && sig && sig != s->firstSig && shown && d != s->inUse && now < s->holdUntil;
}
// The user's touch, click or bring-forward on display d (sig: the most recent stage at that moment, the one later changes are told from).
// Returns 1 when the display in use changed.
static inline int MSBDInUseUser(MSBDInUseState *s, int d, unsigned long long sig, double now) {
    if (!s) return 0;
    int changed = !s->known || s->inUse != d;
    s->known = 1; s->inUse = d; s->firstSig = sig;
    s->holdUntil = now + kMSBDInUseTouchHold;
    return changed;
}
// An action from display d's own bar on its own window: held while that display is not the one in use (the transition it asks is ours).
static inline void MSBDInUseBarAction(MSBDInUseState *s, int d, double now) {
    if (!s || !s->known || s->inUse == d) return;
    if (s->holdUntil < now + kMSBDInUseBarHold) s->holdUntil = now + kMSBDInUseBarHold;
}
// An app's icon tapped: the transition it asks is the user's, wherever its window comes -- no hold.
static inline void MSBDInUseFollow(MSBDInUseState *s) { if (s) s->holdUntil = 0; }
// The other display went (or another one came): the next reading starts afresh.
static inline void MSBDInUseForget(MSBDInUseState *s) { if (s) { s->known = 0; s->inUse = 0; s->firstSig = 0; s->holdUntil = 0; } }

#define kMSBDInUseWayRecent 0   // 1.8.8.1's rule: the most recent stage (the iPad's: the stage it shows)
#define kMSBDInUseWayIPad   1   // the iPad in use while another display's stage is the most recent: the stage the iPad shows (none at its Home Screen)
#define kMSBDInUseWayOther  2   // the other display in use: the stage it shows (none at its empty desktop)

// Which stage the active window is in. otherUp: the state is about another display that is up; inUse: the display in use; firstOn: the most
// recent stage's display (0 also with no stage).
static inline int MSBDInUseWay(int otherUp, int inUse, int firstOn) {
    if (!otherUp) return kMSBDInUseWayRecent;
    if (inUse == 0) return firstOn == 0 ? kMSBDInUseWayRecent : kMSBDInUseWayIPad;
    return kMSBDInUseWayOther;
}

// B86: the stage a display's switcher names is gone -- shown nowhere -- when it is its settled layout state's (not a transition's, which may name
// a stage on its way in), it is no longer one of Stage Manager's stages, and none of its windows is drawn on that display. Our engine takes the TV
// desktop's last window out of the model (its stage deleted, as the App Switcher closes one window): iPadOS's layout state for the TV kept naming
// that stage until its next transition, and the TV's bar named the quit app for minutes.
static inline int MSBDShownStageGone(int settled, int inModel, int drawnThere) { return settled && !inModel && !drawnThere; }

#endif
