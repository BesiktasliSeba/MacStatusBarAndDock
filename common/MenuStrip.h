// MenuStrip.h -- Scroll Menus That Don't Fit (1.8.8.2; the owner, 21 Nov: "And going forward maybe we can make them scrollable in portrait with a
// toggle in settings"). Plain C, so the Mac test (tools/test-menustrip.sh) runs these very numbers; statusbar/MenuStrip.h lays the bar out with them.
// Every x is in leading coordinates (from the bar's leading edge: the left in English, the right in a right-to-left language).
//  - The strip: the menu titles between the app's name and our Go -- File, Edit and the app's own menus (View, History, Bookmarks, Tabs...) -- when
//    the bar has no room for all of them, so the rule of the bar's two ends (common/BarEnds.h) would leave the app's last menus out. With the
//    switch on, nothing is left out: the strip shows whole titles from its first one, and the others are a swipe, a scroll or a click away.
//  - Pinned: the Apple logo, the traffic lights and the app's name before it; our Go, Window, Display and Audio at a fixed place after it (where
//    the room kept for them starts, so they never move while the strip scrolls); the right end.
//  - A chevron at a cut edge says there are more menus that way; a click or tap on it shows the next ones (a page). The first title shown may be
//    cut short only when it alone is wider than the room.
//  - A finger swipe or a trackpad's two-finger scroll moves the strip with the fingers, a whole title at a time (the nearest title's start to where
//    the fingers took it); each notch of a mouse wheel moves it one title.
#ifndef MSBD_MENU_STRIP_H
#define MSBD_MENU_STRIP_H

#define kMSBDStripMax 12   // (the titles a strip can hold: File, Edit and the app's own seven, with room to spare)

typedef struct {
    int n;                      // the strip's titles, in the bar's order
    double w[kMSBDStripMax];    // each one's width (as the layout measures it)
    double gap;                 // between two items (a title gap, x the Menu Bar Size's scale)
    double chev;                // a chevron's width
    double minShown;            // the least room a title is shown in (cut short)
    double start, end;          // the strip's room: its first item starts at start, its last item ends by end
} MSBDStripIn;

typedef struct {
    int first, count;           // the first title shown, and how many show
    int prev, next;             // a chevron before them (more before), after them (more after)
    double prevX, nextX;        // where the chevrons start
    double x[kMSBDStripMax];    // where each shown title starts (x[i] for title first + i)
    double lastW;               // the last shown title's width (cut short when it alone is wider than the room)
} MSBDStripOut;

// Room enough for a strip: both chevrons and a title shown at its least. Less: the bar stays as the two ends' rule lays it out.
static inline int MSBDStripRoomOK(const MSBDStripIn *s) {
    return s->n >= 2 && s->n <= kMSBDStripMax && s->end - s->start >= 2.0 * (s->chev + s->gap) + s->minShown;
}
// Whether titles from..n-1 fit whole in from x to end.
static inline int MSBDStripFitsFrom(const MSBDStripIn *s, int from, double x) {
    for (int i = from; i < s->n; i++) {
        if (i > from) x += s->gap;
        x += s->w[i];
        if (x > s->end + 1e-6) return 0;
    }
    return 1;
}
// Every title fits (then there is no strip: the bar as before).
static inline int MSBDStripAllFit(const MSBDStripIn *s) { return MSBDStripFitsFrom(s, 0, s->start); }
// The last first title: the smallest first after which every title to the end fits with the chevron before them; 0 when all fit.
static inline int MSBDStripLastFirst(const MSBDStripIn *s) {
    if (s->n <= 0 || MSBDStripAllFit(s)) return 0;
    int last = s->n - 1;
    for (int f = s->n - 1; f >= 1; f--) {
        if (MSBDStripFitsFrom(s, f, s->start + s->chev + s->gap)) last = f;
        else break;
    }
    return last;
}
// The strip shown from first (kept between 0 and the last first).
static inline MSBDStripOut MSBDStripAt(const MSBDStripIn *s, int first) {
    MSBDStripOut o;
    for (int i = 0; i < kMSBDStripMax; i++) o.x[i] = 0.0;
    o.count = 0; o.prev = o.next = 0; o.prevX = o.nextX = 0.0; o.lastW = 0.0;
    int lastFirst = MSBDStripLastFirst(s);
    if (first > lastFirst) first = lastFirst;
    if (first < 0) first = 0;
    o.first = first;
    if (s->n <= 0) return o;
    double x = s->start;
    if (first > 0) { o.prev = 1; o.prevX = x; x += s->chev + s->gap; }
    if (MSBDStripFitsFrom(s, first, x)) {   // (the rest fits: no chevron after them)
        for (int i = first; i < s->n; i++) { o.x[o.count] = x; o.lastW = s->w[i]; o.count++; x += s->w[i] + s->gap; }
        return o;
    }
    double limit = s->end - s->gap - s->chev;   // (more after them: room for the chevron after the last one)
    for (int i = first; i < s->n; i++) {
        if (x + s->w[i] > limit + 1e-6) break;
        o.x[o.count] = x; o.lastW = s->w[i]; o.count++; x += s->w[i] + s->gap;
    }
    if (o.count == 0 && limit - x >= s->minShown - 1e-6) {   // (the first one alone is wider than the room: shown cut short)
        o.x[0] = x; o.lastW = limit - x; o.count = 1; x = limit + s->gap;
    }
    if (o.count > 0) { o.next = first + o.count < s->n; o.nextX = x; }
    return o;
}
// The next page: the first title not shown now becomes the first (kept by the last first); the one before: the earliest first that still
// shows the title before the first shown now.
static inline int MSBDStripPageNext(const MSBDStripIn *s, int first) {
    MSBDStripOut o = MSBDStripAt(s, first);
    int f = o.first + (o.count > 0 ? o.count : 1), last = MSBDStripLastFirst(s);
    return f > last ? last : f;
}
static inline int MSBDStripPagePrev(const MSBDStripIn *s, int first) {
    MSBDStripOut o = MSBDStripAt(s, first);
    if (o.first <= 0) return 0;
    int want = o.first - 1, best = want;
    for (int f = want; f >= 0; f--) {
        MSBDStripOut p = MSBDStripAt(s, f);
        if (p.first == f && p.count > 0 && f + p.count - 1 >= want) best = f;
    }
    return best;
}
// One title on: dir > 0 the next, dir < 0 the one before (a wheel's notch).
static inline int MSBDStripStep(const MSBDStripIn *s, int first, int dir) {
    int f = MSBDStripAt(s, first).first + (dir > 0 ? 1 : dir < 0 ? -1 : 0), last = MSBDStripLastFirst(s);
    return f < 0 ? 0 : f > last ? last : f;
}
// Where title i starts with nothing before it (the strip's own run: each title and a gap after it): the swipe's measure.
static inline double MSBDStripOffsetOf(const MSBDStripIn *s, int i) {
    double o = 0.0;
    for (int j = 0; j < i && j < s->n; j++) o += s->w[j] + s->gap;
    return o;
}
// A swipe or a two-finger scroll: it began with first shown and has moved by moved points along the strip (leading coordinates: minus is toward
// the leading edge -- the titles follow the fingers, so the later titles come in); the first title is the one whose start lies nearest to where
// the fingers took the strip, from 0 to the last first.
static inline int MSBDStripFirstAfterMove(const MSBDStripIn *s, int first, double moved) {
    int last = MSBDStripLastFirst(s);
    if (first > last) first = last;
    if (first < 0) first = 0;
    double want = MSBDStripOffsetOf(s, first) - moved, maxO = MSBDStripOffsetOf(s, last);
    if (want < 0.0) want = 0.0;
    if (want > maxO) want = maxO;
    int best = 0; double bestD = 1e18;
    for (int i = 0; i <= last; i++) {
        double d = MSBDStripOffsetOf(s, i) - want;
        if (d < 0) d = -d;
        if (d < bestD - 1e-9) { bestD = d; best = i; }
    }
    return best;
}
// The first that shows title i, starting from first: first itself when i shows; else the nearest first that does (i before: i itself, kept by
// the last first; i after: the smallest first past the shown ones that reaches it). -1: i is not a title of the strip.
static inline int MSBDStripReveal(const MSBDStripIn *s, int first, int i) {
    if (i < 0 || i >= s->n) return -1;
    MSBDStripOut o = MSBDStripAt(s, first);
    if (i >= o.first && i < o.first + o.count) return o.first;
    int last = MSBDStripLastFirst(s);
    if (i < o.first) return i > last ? last : i;
    for (int f = o.first + 1; f <= last; f++) { MSBDStripOut p = MSBDStripAt(s, f); if (i < f + p.count) return f; }
    return last;
}

#endif
