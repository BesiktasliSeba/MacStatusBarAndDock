// test-lastpage.c: the App Library's trailing page left out while "Swipe Past Last Page Opens App Library" is off (dock/LastPageRule.h, KT
// 1.7.8), run against iPadOS's own page arithmetic as read from SpringBoardHome (15.6.1 M1, 16.7.7 iPad 2, 17.5.1, 18.5 A12Z; 2 Nov 2026):
//   -[SBFolderView minimumPageIndex] = 100; -pageCount = leading + icon pages + trailing count; -maximumPageIndex = 100 + (pageCount - 1, or 0);
//   -lastIconPageIndex = maximumPageIndex - trailing count; -typeForPage: 2 (trailing) when the count is not 0 and the page is past
//   maximumPageIndex - count, else 1 (icon; no leading pages here);
//   the trailing count = 1 while there are icon pages and the App Library's trailing view exists (one App Library page);
//   -[SBRootFolderView trailingCustomViewPageIndex]: 15-17 trailingCustomView ? maximumPageIndex : NSIntegerMax (from the view);
//                                                    18 -firstTrailingCustomPageIndex: count ? maximumPageIndex - count + 1 : NSIntegerMax;
//   entering Edit Home Screen, -[SBRootFolderController _updateFolderRequiredTrailingEmptyListCount]: the folder gets its trailing empty list (one
//   more icon page, empty: where a dragged icon makes a new page), and the current page follows the trailing page --
//     15-17: t = trailingCustomViewPageIndex; (empty list added); if (editing && current == t) current = trailingCustomViewPageIndex;
//     18:    if typeForPage:current == 2: t = current - lastIconPageIndex - 1; (empty list added); current = t - count + maximumPageIndex + 1.
// The device logs of 1.7.8's regression (R-8, before this fix): "will scroll to page 104" (iPad 2, 4 icon pages), 102 (17.5, 2 icon pages).
#include <stdio.h>
#include <limits.h>
#include "../dock/LastPageRule.h"

typedef struct {
    int version;           // 15, 16, 17 or 18
    long long iconPages;   // icon list views (edit mode adds the empty one)
    int trailingView;      // the App Library's overscroll page exists (SBHLibraryOverscrollViewController)
    int switchedOn;        // Swipe Past Last Page Opens App Library
    int countOnly;         // 1: the count left out alone (1.7.8 before the R-8 fix); 0: the count and the index (LastPageRule.h)
    long long current;     // currentPageIndex
} Home;

static const long long kMin = 100;
static unsigned long long iosCount(const Home *h) { return h->iconPages && h->trailingView ? 1 : 0; }
static int leftOut(const Home *h) { return DMLastPageMayLeaveOut(iosCount(h), h->switchedOn); }   // (every trailing page the App Library's here)
static unsigned long long count(const Home *h) { return DMLastPageCount(iosCount(h), leftOut(h)); }
static unsigned long long pageCount(const Home *h) { return (unsigned long long)h->iconPages + count(h); }
static long long maxPage(const Home *h) { unsigned long long n = pageCount(h); return kMin + (n ? (long long)n - 1 : 0); }
static long long lastIconPage(const Home *h) { return maxPage(h) - (long long)count(h); }
static int typeForPage(const Home *h, long long p) { return count(h) && maxPage(h) - (long long)count(h) < p ? 2 : 1; }
static long long iosIndex(const Home *h) {
    if (h->version >= 18) return count(h) ? maxPage(h) - (long long)count(h) + 1 : LLONG_MAX;
    return h->trailingView ? maxPage(h) : LLONG_MAX;
}
static long long trailingIndex(const Home *h) {   // what -trailingCustomViewPageIndex answers through Dock.x's hook (DMTrailingPageIndex)
    long long i = iosIndex(h);
    if (h->countOnly || i == LLONG_MAX) return i;
    return DMLastPageIndex(i, leftOut(h));
}
static int onTrailingPage(const Home *h) { return h->version >= 18 ? typeForPage(h, h->current) == 2 : h->current == trailingIndex(h); }
static void enterEditing(Home *h) {
    if (h->version >= 18) {
        int trailing = typeForPage(h, h->current) == 2;
        long long t = trailing ? h->current - lastIconPage(h) - 1 : LLONG_MAX;
        h->iconPages += 1;
        if (trailing) h->current = count(h) ? t - (long long)count(h) + maxPage(h) + 1 : LLONG_MAX;
    } else {
        long long t = trailingIndex(h);
        h->iconPages += 1;
        if (h->current == t) h->current = trailingIndex(h);
    }
}
static Home home(int version, long long icons, int on, int countOnly) { Home h = {version, icons, 1, on, countOnly, kMin + icons - 1}; return h; }

static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }

int main(void) {
    Home a = home(16, 4, 0, 1), b = home(17, 2, 0, 1), c = home(15, 4, 0, 1);
    enterEditing(&a); enterEditing(&b); enterEditing(&c);
    check("the model reproduces R-8 with the count alone: Edit Home Screen on the last page moves to page 104 (iPad 2, 4 pages), 102 (17.5, 2 pages), 104 (15)",
          a.current == 104 && b.current == 102 && c.current == 104);
    Home d = home(16, 4, 0, 1);
    check("  ... and with the count alone 15-17 take the last icon page for the App Library's (its index 103, on it: yes)",
          trailingIndex(&d) == 103 && lastIconPage(&d) == 103 && onTrailingPage(&d));

    int ok = 1;
    for (int v = 15; v <= 18; v++) for (long long n = 1; n <= 6; n++) {
        Home h = home(v, n, 0, 0); long long last = h.current;
        ok &= trailingIndex(&h) == LLONG_MAX && !onTrailingPage(&h) && pageCount(&h) == (unsigned long long)n && lastIconPage(&h) == last;
        enterEditing(&h);
        ok &= h.current == last && lastIconPage(&h) == last + 1 && pageCount(&h) == (unsigned long long)n + 1 && trailingIndex(&h) == LLONG_MAX;
    }
    check("switched off (count and index): Edit Home Screen on the last page stays there on 15, 16, 17 and 18, 1 to 6 pages", ok);
    check("  ... in edit mode the empty page after it is the last icon page (an icon dropped there makes the new page), and no trailing page after it", ok);

    ok = 1;
    for (int v = 15; v <= 18; v++) for (long long n = 1; n <= 6; n++) {
        Home h = home(v, n, 1, 0); long long last = h.current;
        ok &= trailingIndex(&h) == iosIndex(&h) && trailingIndex(&h) == last + 1 && !onTrailingPage(&h) && pageCount(&h) == (unsigned long long)n + 1;
        enterEditing(&h);
        ok &= h.current == last && lastIconPage(&h) == last + 1 && trailingIndex(&h) == last + 2;
        Home t = home(v, n, 1, 0); t.current = last + 1;   // (on the App Library's page itself)
        ok &= onTrailingPage(&t); enterEditing(&t); ok &= t.current == last + 2 && onTrailingPage(&t);
    }
    check("switched on: iPadOS's own answers (index = the page after the last; edit mode keeps the last page; on the App Library's page it stays on it)", ok);

    ok = 1;
    for (long long n = 1; n <= 6; n++) { Home h = home(18, n, 0, 1); long long last = h.current; ok &= trailingIndex(&h) == LLONG_MAX; enterEditing(&h); ok &= h.current == last; }
    check("18 worked the index out from the count already: the count alone kept the last page there (R-8 seen on 16 and 17 only)", ok);

    Home none = home(16, 4, 0, 0); none.trailingView = 0;
    Home empty = home(16, 0, 0, 0);
    check("no App Library page (no trailing view), or no icon pages yet: iPadOS's own answers, nothing left out",
          !leftOut(&none) && trailingIndex(&none) == LLONG_MAX && count(&none) == 0 && !leftOut(&empty) && trailingIndex(&empty) == iosIndex(&empty));
    check("the rule itself: left out only with a page and the switch off; count 0 and index NSIntegerMax then, else iPadOS's own",
          DMLastPageMayLeaveOut(1, 0) && !DMLastPageMayLeaveOut(1, 1) && !DMLastPageMayLeaveOut(0, 0) && DMLastPageCount(1, 1) == 0 && DMLastPageCount(1, 0) == 1
          && DMLastPageIndex(103, 1) == LLONG_MAX && DMLastPageIndex(104, 0) == 104);
    return fails;
}
