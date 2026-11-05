// SBLaunchRule.h -- whether -[SpringBoard launchApplicationWithIdentifier:suspended:] opens the app as every other launch does with a window engine
// (1.8.0 item 8, GitHub #10: InstaLauncher 2): StatusBar.x DMSBLaunchOpensWindow asks it, the Mac test tools/test-sblaunch.sh runs this very code.
// Plain C. With Aerial, Zetsu or MilkyWay4 the call opened the app full screen, over its window when it had one, where an icon, LaunchServices, a
// link, Spotlight or Command-Tab bring the window forward or open the app as a window (Open Apps as Windows); our Stage Manager engine has its own
// way for it (SMDesktop.h DMSMJoinActivatesWindow). Left as it is: a launch in the background (suspended), our own full-screen launch, one while
// the Lock Screen or the Cover Sheet is up, no window engine, and the window engines' own calls (also through another tweak's hook of the call:
// MSBDSBLaunchEngineCaller) -- Zetsu builds its windows with this very call (Zetsu.dylib 1.6.6: suspended NO from the block that
// builds a window and again from its retry, suspended YES once), MilkyWay4 calls it suspended, Aerial calls it too: a window being built is not one
// to bring forward or to open again.
#pragma once
#include <string.h>

// The caller's image (dladdr's path) is a window engine's own: Aerial, Zetsu, MilkyWay4 (and its MilkyWay3 part). NULL: not known, not one.
static inline int MSBDSBLaunchCallerIsEngine(const char *image) {
    static const char *const engines[] = {"/Aerial.dylib", "/Zetsu.dylib", "/MilkyWay4.dylib", "/MilkyWay3SubModule.dylib"};
    if (!image) return 0;
    const char *name = strrchr(image, '/');
    if (!name) return 0;
    for (size_t i = 0; i < sizeof engines / sizeof engines[0]; i++) if (!strcmp(name, engines[i])) return 1;
    return 0;
}
// The engine making the call, found up its callers (each caller's image from imageOf -- dladdr's path, NULL where none --, the immediate caller
// first): another tweak that hooks this call after ours and calls through puts its own frame between the engine and us, and Zetsu's own call, taken
// for a launcher's, had its window surfaced and the call swallowed (code review 1.8.0, 8). The walk goes on through other tweaks' frames (and frames
// with no image: a hook's trampoline) and stops at iPadOS's own code -- a path under /System/ or /usr/: a tap's UIKit, SpringBoard itself, so an
// engine further up is not the caller -- or ours (our own call), after kMSBDSBLaunchCallerDepth callers at most. Returns its image, or NULL.
#define kMSBDSBLaunchCallerDepth 6
static inline const char *MSBDSBLaunchEngineCaller(void *const *callers, int n, const char *(*imageOf)(const void *), const char *ours) {
    for (int i = 0; i < n && i < kMSBDSBLaunchCallerDepth; i++) {
        const char *image = imageOf(callers[i]);
        if (MSBDSBLaunchCallerIsEngine(image)) return image;
        if (image && (!strncmp(image, "/System/", 8) || !strncmp(image, "/usr/", 5) || (ours && !strcmp(image, ours)))) break;
    }
    return NULL;
}
// The call opens the app as a launch with a window engine does (its window forward, or a new window): not suspended, not our own full-screen
// launch, not while the Lock Screen or the Cover Sheet is up (SpringBoard's own launch asks for the unlock or puts the Cover Sheet away first; ours
// brought the window forward behind it, and the app was not in front after the unlock: code review 1.8.0, 6), a window engine of ours that is not
// the Stage Manager engine, and not the engine's own call (callerImage: MSBDSBLaunchEngineCaller's, or the caller's image).
static inline int MSBDSBLaunchToWindow(int suspended, int ourFullScreen, int locked, int stageManagerEngine, int windowEngine, const char *callerImage) {
    return !suspended && !ourFullScreen && !locked && !stageManagerEngine && windowEngine && !MSBDSBLaunchCallerIsEngine(callerImage);
}
// An open request from outside SpringBoard (SBMainWorkspace's -_handleOpenApplicationRequest:..., StatusBar.x: LaunchServices, links, Spotlight,
// notifications) becomes the window launch when the app has a window or may open as one -- not an AirDrop request (its options carry the file), not
// a launch in the background, not our own full-screen launch, and not while the UI is locked (-isUILocked): there SpringBoard's own open
// asks for the unlock first, where ours brought the window forward behind the Lock Screen and the app was not in front after the unlock -- the
// launch call's gap above, closed there in 1.8.0 (code review 1.8.0, 6; 1.8.1 item 3). That is a first step only: once the Cover Sheet starts to leave SpringBoard makes the same call again
// with the UI unlocked (read on 15.6.1 and 16.7.7, 7 to 12 ms later, -isUILocked NO, -isPresented NO, -isVisible YES), and that one becomes the window launch. Notification Center pulled down on an
// unlocked iPad goes the same two steps (-isUILocked YES there too). With the Cover Sheet in the test, the second call went to SpringBoard as well: an app with no window opened full screen, one with
// a window full screen at its window's size, the rest of the screen black (code review 1.8.1, 1).
static inline int MSBDSBOpenToWindow(int airDrop, int background, int ourFullScreen, int locked, int hasWindow, int windowable) {
    return !airDrop && !background && !ourFullScreen && !locked && (hasWindow || windowable);
}
// Fit's question for a third window holds the app's launch (heldLaunch). The screen going off closes the question and applies the default arrangement; the lock state is read again then, and the
// launch waits for the user to be back rather than start behind the Lock Screen (the gap above) or run SpringBoard's own open, which asks for the unlock of an iPad just locked: screen off now, off
// since the user was last back (the Lock Screen after a wake, with no passcode too), or locked (code review 1.8.1, 8). What it carries waits with it.
static inline int MSBDFitLaunchWaitsForBack(int heldLaunch, int screenOff, int offSinceBack, int locked) {
    return heldLaunch && (screenOff || offSinceBack || locked);
}
// With the Stage Manager engine the request stays SpringBoard's (it joins the desktop, DMSMJoinDesktop), and Fit to Window's question for a third window
// comes before it (StatusBar.x DMSMOpenRequest, 1.8.1, KT: the other engines' order, as the Dock and the App Library): the same requests may be held for
// the answer, with their options, no others. The app: one with an icon that lives in a window, not the desktop's already, none of its windows elsewhere.
static inline int MSBDSMOpenMayAsk(int airDrop, int background, int ourFullScreen, int locked, int hasIcon, int fullScreenOnly, int inDesktop, int elsewhere) {
    return !airDrop && !background && !ourFullScreen && !locked && hasIcon && !fullScreenOnly && !inDesktop && !elsewhere;
}
