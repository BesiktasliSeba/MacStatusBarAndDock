// HomeFolderRule.h -- whether a Home Screen folder is what the user is looking at, so the windows step aside for it (1.7.9, the Finder menu's
// folders; code review). Plain C, so the Mac test (tools/test-homefolder.c) runs this very code; StatusBar.x keeps the state.
// Why: a folder opens in the Home Screen's own window, under every window, so the windows fade out while one is open (DMSyncWindowFade, the native
// windows, the Stage Manager engine's stages). But -[SBHIconManager hasOpenFolder] alone is not "on screen": iPadOS keeps a folder open behind
// the app launched from it, and the Home Screen shows it open again when it comes back. With the windows faded for as long as it said YES, the app
// just launched from the folder faded with every other window and took no touches, and a Finder window opened then never showed (17.5.1, Stage
// Manager engine, 2 Nov). Like a Home Screen icon's menu (gHomeMenuOpen, set and cleared by the menu itself), a folder counts from its own opening:
//  - from the first look that finds it open after one that did not, when the Home Screen was not covered then (a full-screen app in front:
//    opened behind it from the Finder menu, nothing of it to see);
//  - until it closes, or until an app or a window comes to the front: another app than the one in front when it opened (a launch, Command-Tab,
//    a link), and, told by its own hooks, an app icon tapped (also the app already in front) or one of our native windows made active.
// A folder left open behind an app is no reason for the windows to step aside, also when the Home Screen shows it again: it counts again only once
// it has closed and opened again.
#ifndef MSBD_HOME_FOLDER_RULE_H
#define MSBD_HOME_FOLDER_RULE_H
#include <stdint.h>

typedef struct {
    int wasOpen;            // the folder was open at the last look
    int showing;            // the windows step aside for it
    uint64_t frontAtOpen;   // the app in front when it opened (MSBDHomeFolderFrontID; 0: none)
} MSBDHomeFolderState;

// The app in front as a number: FNV-1a of its bundle identifier, never 0 for one (0: no app).
static inline uint64_t MSBDHomeFolderFrontID(const char *bundle) {
    if (!bundle || !*bundle) return 0;
    uint64_t h = 1469598103934665603ULL;
    for (const unsigned char *p = (const unsigned char *)bundle; *p; p++) { h ^= *p; h *= 1099511628211ULL; }
    return h ? h : 1;
}
// One look: open = the folder is open now (hasOpenFolder), front = the app in front now, homeCovered = a full-screen app covers the Home Screen.
// Returns whether the windows step aside for the folder.
static inline int MSBDHomeFolderStep(MSBDHomeFolderState *s, int open, uint64_t front, int homeCovered) {
    if (!open) { s->wasOpen = 0; s->showing = 0; s->frontAtOpen = 0; return 0; }
    if (!s->wasOpen) { s->wasOpen = 1; s->showing = !homeCovered; s->frontAtOpen = front; return s->showing; }   // (it opened since the last look)
    if (s->showing && front && front != s->frontAtOpen) s->showing = 0;   // (another app came to the front; none in front, as on the way, is no change)
    return s->showing;
}
// An app or a window came to the front by the user's hand (an app icon tapped, a native window made active): the folder, left open behind it,
// no longer counts. open: the folder is open now -- one the looks have not seen yet does not count when they first do.
static inline void MSBDHomeFolderMovedOn(MSBDHomeFolderState *s, int open) {
    s->showing = 0;
    s->wasOpen = open ? 1 : 0;
    if (!open) s->frontAtOpen = 0;
}
#endif
