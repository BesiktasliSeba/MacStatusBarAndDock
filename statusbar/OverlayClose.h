// OverlayClose.h -- when Spotlight closes an open menu, dialog or question of ours (StatusBar.x's tick: "came up while a menu or question was
// open"), like a Mac's menus when Mission Control opens. Plain C, so the Mac test (tools/test-overlayclose.sh) runs this very rule.
// The tick reads "came up" as "is showing", two ticks in a row. An app picked in Spotlight that becomes Fit to Window's third window gets its side
// question at once, while that Spotlight is still going away (it reads as shown for its dismissal, ~0.45 s: two ticks), so the question closed by
// itself 0.45 s later -- the default arrangement, without a choice (1.8.1 item 11: Aerial, iPad 2 and M1). The side question notes a Spotlight
// already showing when it opened (DMShowSidePrompt) and that one does not close it: it stays up and waits for the answer, as from every other way
// of opening an app. Once that Spotlight has gone, a Spotlight brought up later closes it as before. Every other overlay notes nothing: a menu of the
// bar opened over Spotlight still goes, as before 1.8.1.
#ifndef MSBD_OVERLAY_CLOSE_H
#define MSBD_OVERLAY_CLOSE_H

// shownNow: Spotlight is showing; shownWhenOpened: the side question noted it showing when it opened (and it has not gone since).
static inline int MSBDSpotlightCameUp(int shownNow, int shownWhenOpened) { return shownNow && !shownWhenOpened; }
// What the overlay keeps of that note on a tick: only for as long as that Spotlight stays.
static inline int MSBDSpotlightStillFromOpen(int shownNow, int shownWhenOpened) { return shownNow && shownWhenOpened; }
// The same for Notification Center (code review 1.8.1, 1): what was tapped there while unlocked goes to its window, the question for a third window comes while the Cover Sheet goes away (it
// reads as shown for its dismissal), and only a Cover Sheet pulled down later closes the question.
static inline int MSBDCoverSheetCameUp(int shownNow, int shownWhenOpened) { return MSBDSpotlightCameUp(shownNow, shownWhenOpened); }
static inline int MSBDCoverSheetStillFromOpen(int shownNow, int shownWhenOpened) { return MSBDSpotlightStillFromOpen(shownNow, shownWhenOpened); }

#endif
