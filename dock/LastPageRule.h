// LastPageRule.h: the App Library's trailing page left out of the Home Screen while "Swipe Past Last Page Opens App Library" is off (KT, 1.7.8;
// dock/Dock.x). Plain C, so tools/test-lastpage.c runs the same rule against iPadOS's page arithmetic.
//
// iPadOS answers two questions about that page, and both have to say the same thing:
//   - how many trailing pages there are: -[SBRootFolderView _trailingCustomPageCount] (15-17) / -trailingCustomPageCount (18);
//   - which page index the trailing page has: -[SBRootFolderView trailingCustomViewPageIndex] (every version; SBRootFolderController's asks it).
// 18 works the index out from the count (-firstTrailingCustomPageIndex: count ? maximumPageIndex - count + 1 : NSIntegerMax), so a count of 0
// already gives NSIntegerMax there. 15-17 work it out from the trailing view instead (trailingCustomView ? maximumPageIndex : NSIntegerMax;
// SpringBoardHome 15.6.1, 16.7.7, 17.5.1). With only the count left out, maximumPageIndex is the last icon page, so 15-17 took the last icon
// page for the App Library's own: entering Edit Home Screen there, -[SBRootFolderController _updateFolderRequiredTrailingEmptyListCount] (if
// editing and currentPageIndex == trailingCustomViewPageIndex: setCurrentPageIndex: the trailing page's index again, once edit mode's empty page
// is added after the last icon page) moved to that empty page (1.7.8 regression R-8: "will scroll to page 104" on the iPad 2's 4 pages).
// So while the page is left out, the index says what iPadOS itself says when there is no trailing page: NSIntegerMax.
#pragma once
#include <limits.h>

// The page may be left out: iPadOS has one (its own count is not 0) and the switch is off. (Dock.x then also needs every trailing page to be
// the App Library's own.)
static inline int DMLastPageMayLeaveOut(unsigned long long iosCount, int switchedOn) { return iosCount != 0 && !switchedOn; }
// What the count answers: 0 while the page is left out, else iPadOS's own count.
static inline unsigned long long DMLastPageCount(unsigned long long iosCount, int leftOut) { return leftOut ? 0 : iosCount; }
// What the index answers: NSIntegerMax ("no trailing page", LLONG_MAX on arm64) while the page is left out, else iPadOS's own index.
static inline long long DMLastPageIndex(long long iosIndex, int leftOut) { return leftOut ? LLONG_MAX : iosIndex; }
