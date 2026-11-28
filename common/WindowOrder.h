// WindowOrder.h -- the order the windows end in when some come to the front, as on a Mac (1.8.4.1 item 6, KT 8 Nov ~00:30: on the M1 with Aerial,
// a small window in front of a big one; the big one clicked came forward, as on a Mac, and then the small one could not be brought back with the
// pointer or the keys). Plain C, so the Mac test (tools/test-windoworder.c) runs these very rules; statusbar/WindowFront.h does them in
// SpringBoard on every engine (Aerial, Zetsu, MilkyWay4, Stage Manager).
// macOS's, the ones matched (Mac User Guide, "Work with app windows"; macOS 15):
//  - clicking an app's Dock icon, or Command-Tab to it (the Mac Switcher's pick here too), brings its windows above the others;
//  - Window > Bring All to Front brings all of the front app's windows above the other apps' windows;
//  - the Window menu's list of windows (the front app's) picks one: it comes to the front.
// A window brought forward keeps the windows' order otherwise: the others stay as they were, among themselves.
#ifndef MSBD_WINDOW_ORDER_H
#define MSBD_WINDOW_ORDER_H
#include <stdbool.h>

// Windows back to front, each with its app (any number: an index); app's windows above every other app's, each keeping its place among its own:
// out gets the new order, back to front, as indices into the input (n entries). An app with no window there: the order as it was.
static inline int MSBDOrderAppToFront(const int *apps, int n, int app, int *out) {
    int k = 0;
    if (!apps || !out || n <= 0) return 0;
    for (int i = 0; i < n; i++) if (apps[i] != app) out[k++] = i;
    for (int i = 0; i < n; i++) if (apps[i] == app) out[k++] = i;
    return k;
}
// One window brought to the front (the list's pick, a click, a tap): it above every other window, the others as they were.
static inline int MSBDOrderOneToFront(int n, int w, int *out) {
    int k = 0;
    if (!out || n <= 0) return 0;
    for (int i = 0; i < n; i++) if (i != w) out[k++] = i;
    if (w >= 0 && w < n) out[k++] = w;
    return k;
}
// The raise asked of an engine's own code did not take (Aerial 5's own -_bringStageToFrontIfNeeded answers by its own record of the front window, which
// a click or a move of ours need not have changed): the window is put in front by its place among its window layer's views, as the other engines' are.
// frontNow: the window is the front one on its screen after the engine's own step; shown: it shows (not minimized, hidden or on its way out).
static inline bool MSBDRaiseNeedsOrder(bool frontNow, bool shown) { return shown && !frontNow; }

// ---- Keep Covered Windows in Front (Settings > Windows & Multitasking, 1.8.4.1 item 7, KT 8 Nov ~00:40; off unless switched on) ----
// When a window comes forward -- a tap, a click, a key, our menus, the window API, the engine's own --, every window it would cover completely stays
// above it, in its own order: a small window is never lost behind a big one (smaller by a strip that can be clicked: one of its size, or nearly, is
// not covered -- MSBDFrameCoveredBy). Not "Windows Behind Full-Screen Apps" (full-screen apps only). A window
// moved so that it is no longer inside the other one is an ordinary window again (asked afresh each time, from the frames as they are). Minimized and
// hidden windows, other desktops (the Mac Switcher), Mission Control's spread and Fit to Window's tiles (side by side, never one inside another) are
// untouched. The window that came forward stays the active one -- the menu bar's app, the window keys' window --, as on a Mac a click makes that window
// the key one, until another window is brought forward.
#include <CoreGraphics/CoreGraphics.h>
#define kMSBDKeepCoveredKey "keepCoveredInFront"   // (com.besiktasliseba.macstatusbar: a boolean; never set -- the default -- is off)
// inner lies inside outer: each side within it, or past it by less than a point (frames are fractional; a window placed edge to edge with the other's
// side counts as inside). Empty or null frames: never.
static inline bool MSBDFrameInside(CGRect inner, CGRect outer) {
    if (CGRectIsNull(inner) || CGRectIsNull(outer) || CGRectIsEmpty(inner) || CGRectIsEmpty(outer)) return false;
    return inner.origin.x >= outer.origin.x - 1.0 && inner.origin.y >= outer.origin.y - 1.0
        && CGRectGetMaxX(inner) <= CGRectGetMaxX(outer) + 1.0 && CGRectGetMaxY(inner) <= CGRectGetMaxY(outer) + 1.0;
}
// What a window must show of itself past a window inside it, on one side at least, for that one to count as covered by it: a strip that can be clicked
// or tapped -- the 16 pt within which the window keys take two frames for one place (statusbar/WindowKeysRule.h MSBDWinNear).
#define kMSBDKeepCoveredMargin 16.0
// inner is covered by outer: inside it, and outer larger than it by more than that margin on at least one side (review 1.8.4.1 H1). Two windows with one
// frame -- two at Fill, a new window opened at Fill over another --, or nearly one, are never covered either way: kept above, either would bury the other
// for good. The one brought forward comes in front, as without the switch; the other comes back as any window does (its Dock icon, Command-Tab).
static inline bool MSBDFrameCoveredBy(CGRect inner, CGRect outer) {
    if (!MSBDFrameInside(inner, outer)) return false;
    return inner.origin.x - outer.origin.x > kMSBDKeepCoveredMargin || inner.origin.y - outer.origin.y > kMSBDKeepCoveredMargin
        || CGRectGetMaxX(outer) - CGRectGetMaxX(inner) > kMSBDKeepCoveredMargin || CGRectGetMaxY(outer) - CGRectGetMaxY(inner) > kMSBDKeepCoveredMargin;
}
// Windows back to front (frames in one space; shown: it takes part -- on screen, not minimized or going), w the one that came forward: out gets the new
// order, back to front -- the others as they were, then w, then the windows w covers completely (MSBDFrameCoveredBy), as they were among themselves.
// *kept: how many are above w for it (0: nothing to do but w in front). A w that does not show: the order as it was, nothing kept.
static inline int MSBDOrderKeepCovered(const CGRect *frames, const bool *shown, int n, int w, int *out, int *kept) {
    int k = 0, above = 0;
    if (kept) *kept = 0;
    if (!frames || !shown || !out || n <= 0) return 0;
    if (w < 0 || w >= n || !shown[w]) { for (int i = 0; i < n; i++) out[k++] = i; return k; }
    for (int i = 0; i < n; i++) if (i != w && !(shown[i] && MSBDFrameCoveredBy(frames[i], frames[w]))) out[k++] = i;
    out[k++] = w;
    for (int i = 0; i < n; i++) if (i != w && shown[i] && MSBDFrameCoveredBy(frames[i], frames[w])) { out[k++] = i; above++; }
    if (kept) *kept = above;
    return k;
}
// Which window is the active one (the menu bar's app): the top window, unless every window above the one that came forward is one it kept above it --
// then that one. keptUnder: the window that came forward and kept others (-1: none); keptAbove[i]: window i is one of them, counted only while it is still
// covered by keptUnder (frames as for MSBDOrderKeepCovered; NULL: not looked at) -- one moved or resized out of it since, or left outside by its move or
// resize, is an ordinary window again (review 1.8.4.1 M1). Windows back to front, as shown; the top one that shows is the active one otherwise. -1: none.
static inline int MSBDActiveWithKept(const bool *shown, const bool *keptAbove, const CGRect *frames, int n, int keptUnder) {
    int top = -1;
    for (int i = 0; i < n; i++) if (shown && shown[i]) top = i;
    if (top < 0 || keptUnder < 0 || keptUnder >= n || !shown[keptUnder] || !keptAbove) return top;
    for (int i = keptUnder + 1; i < n; i++)   // (another window came over it since, or a kept one is no longer inside it: the top one's)
        if (shown[i] && (!keptAbove[i] || (frames && !MSBDFrameCoveredBy(frames[i], frames[keptUnder])))) return top;
    return keptUnder;
}

// 1.8.9.1 (B127): Window > Bring All to Front when a big window is in front and smaller windows are completely covered behind it:
//  - All shown windows of `app` come above other apps' windows, keeping their relative order EXCEPT that any window of `app` completely covered
//    (MSBDFrameCoveredBy) by a larger window of `app` above it rises above that larger window (keeping relative order among siblings, and handling
//    nested sizes like Big > Medium > Small -> [Big, Medium, Small] back-to-front so every window of the app is visible in front).
//  - When `app` has only one shown window and it is already the frontmost shown window (every single-window-per-app engine -- Aerial, Zetsu,
//    MilkyWay4 -- and single-window Stage Manager), lift any shown smaller windows completely covered by that front window above it in their
//    relative order so Bring All to Front un-buries covered smaller windows there too.
static inline int MSBDOrderBringAllToFront(const int *apps, const CGRect *frames, const bool *shown, int n, int app, int *out) {
    if (!apps || !out || n <= 0) return 0;
    if (!frames || !shown) return MSBDOrderAppToFront(apps, n, app, out);
    int appIdx[64], otherIdx[64], m = 0, o = 0, topShown = -1;
    if (n > 64) n = 64;
    for (int i = 0; i < n; i++) {
        if (shown[i]) topShown = i;
        if (shown[i] && apps[i] == app) appIdx[m++] = i;
        else otherIdx[o++] = i;
    }
    if (m == 0) { for (int i = 0; i < n; i++) out[i] = i; return n; }
    // Single-window front app already in front of every shown window: un-bury smaller shown windows covered by it.
    if (m == 1 && appIdx[0] == topShown) return MSBDOrderKeepCovered(frames, shown, n, appIdx[0], out, (int *)0);
    // Multi-window (or not yet at front): within `app`'s shown windows, lift any window buried under a covering window of `app` above that window,
    // preserving relative order among siblings. MSBDFrameCoveredBy is a strict partial order (acyclic), so at most m passes settle it.
    for (int pass = 0; pass < m; pass++) {
        bool changed = false;
        for (int q = m - 1; q >= 0; q--) {
            int moved[64], kept[64], mc = 0, kc = 0;
            for (int p = 0; p < q; p++) {
                if (MSBDFrameCoveredBy(frames[appIdx[p]], frames[appIdx[q]])) moved[mc++] = appIdx[p];
                else kept[kc++] = appIdx[p];
            }
            if (!mc) continue;
            int next[64], t = 0;
            for (int j = 0; j < kc; j++) next[t++] = kept[j];
            next[t++] = appIdx[q];
            for (int j = 0; j < mc; j++) next[t++] = moved[j];
            for (int j = q + 1; j < m; j++) next[t++] = appIdx[j];
            for (int j = 0; j < m; j++) appIdx[j] = next[j];
            changed = true;
            break;
        }
        if (!changed) break;
    }
    int k = 0;
    for (int i = 0; i < o; i++) out[k++] = otherIdx[i];
    for (int i = 0; i < m; i++) out[k++] = appIdx[i];
    return k;
}

#endif
