// EditProxyRule.h -- the Dock's own items in Edit Home Screen (1.8.3 item 5, KT 6 Nov). Plain C, so the Mac test (tools/test-editproxy.c) runs
// this very rule; dock/EditProxy.m acts on it in SpringBoard.
// While the Home Screen is in edit mode, Finder, Launchpad, Downloads and the Trash act as Apple's Dock icons do:
//  - no tap or double tap opens anything (a double tap on Finder opened a Finder window);
//  - they jiggle with the rest of the Dock;
//  - SnowBoard's theming menu works on them: a per-icon theme or a picture of your own, live and kept after a respring.
// SnowBoard finds the icon by its hook of -[SBIconView touchesBegan:withEvent:]: an icon view that is editing, a touch whose tapCount is 2 --
// its menu for that icon view's -icon, its choice kept by the icon's -applicationBundleID (read from SnowBoard's binary, plans/v183.md item 5).
// Our items are views of our own, so each gets an icon view of SpringBoard's own over it while editing, showing the item's app icon
// (common/IconTheme.h MSBDThemableIcon: its bundle identifier is the identifier a theme names the item by, IconThemeIDs.h).
// Decided by code (the item's 1.8.3 questions):
//  - no remove badge: the items come and go with Settings > Dock's switches; the Home Screen has nothing to remove (and Finder never leaves);
//  - no drag: they have no place in SpringBoard's icon model, so there is nowhere to drag them to.
// Where the icon path is off (iPadOS 18, SpringBoard's classes not as read): no icon view; our views jiggle themselves, and still take no tap.
#ifndef MSBD_EDIT_PROXY_RULE_H
#define MSBD_EDIT_PROXY_RULE_H
#include <stdbool.h>
#include <math.h>

// Our item views, as the edit mode covers them.
enum { kMSBDEditFinder = 0, kMSBDEditLaunchpad, kMSBDEditDownloads, kMSBDEditTrash, kMSBDEditCount };
// The app icon each one shows while editing (the values of IconThemeIDs.h MSBDIconItem: Finder 0, Launchpad 1, classic Launchpad 2, Downloads 3,
// the empty Trash 4, the full one 5): the picture it shows now, so a theme chosen for it is for what is on screen.
static inline int MSBDEditIconItem(int view, bool launchpadClassic, bool trashFull) {
    switch (view) {
        case kMSBDEditFinder: return 0;
        case kMSBDEditLaunchpad: return launchpadClassic ? 2 : 1;
        case kMSBDEditDownloads: return 3;
        case kMSBDEditTrash: return trashFull ? 5 : 4;
        default: return -1;
    }
}
// What a view does while editing, and once it ends: covered by SpringBoard's icon view (it jiggles, SnowBoard's menu), or jiggling itself where
// none can be made; our own taps, double taps and menus wait in both cases.
enum { kMSBDEditNone = 0, kMSBDEditCover, kMSBDEditOwnJiggle };
static inline int MSBDEditHow(bool editing, bool proxyMade) {
    if (!editing) return kMSBDEditNone;
    return proxyMade ? kMSBDEditCover : kMSBDEditOwnJiggle;
}
static inline bool MSBDEditTakesTaps(bool editing) { return !editing; }
// The items' icon views while editing: what SpringBoard would show for an app's Dock icon, minus what the items cannot do.
static inline bool MSBDEditCloseBox(void) { return false; }   // (no remove badge)
static inline bool MSBDEditDrag(void) { return false; }       // (no drag)
// Our own jiggle, where no icon view of SpringBoard's can be made: as SpringBoard's (SBIconView's jitter), a small rotation back and forth,
// 1.5 degrees each way, about 0.27 s a swing, each view starting at another point of it so they do not move as one.
#define kMSBDEditJiggleRadians (1.5 * M_PI / 180.0)
#define kMSBDEditJiggleSeconds 0.27
static inline double MSBDEditJigglePhase(int view) { return view < 0 ? 0.0 : fmod(view * 0.37, 1.0); }

#endif
