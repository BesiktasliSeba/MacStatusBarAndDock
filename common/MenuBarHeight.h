// MenuBarHeight.h -- our menu bar's height on the iPad's own screen (StatusBar.x DMMenuBarHeight), plain C so the Mac test
// (tools/test-menubarheight.sh) runs this very rule.
//  - Our menu bar is iOS's status bar with our items in it, so its height is iOS's: the bar's visual provider's +height -- 24 pt on Face ID iPads
//    (_UIStatusBarVisualProvider_RoundedPad), 20 pt on Home-button iPads (_UIStatusBarVisualProvider_Pad; read on 15.6.1 and 16.7.7). Our window
//    geometry took 24 everywhere, so on Home-button iPads (the iPad 2, the 17.5 iPad) windows and tiles started 3-4 pt below the 20 pt bar, the
//    wallpaper showing between (1.7.1 item 14, found by the Larger Menu Bar research).
//  - The height is the provider's when a bar copy on the iPad's screen has one, else that copy's own laid-out height; a value outside 16..40 pt is
//    no bar height. Until one is known (SpringBoard's start, before its first bar): 24, the geometry as it was -- and on Face ID iPads it is 24.
#ifndef MSBD_MENU_BAR_HEIGHT_H
#define MSBD_MENU_BAR_HEIGHT_H
#include <math.h>

#define kMSBDMenuBarDefault 24.0   // (before a bar is known; Face ID iPads' bar)

static inline int MSBDMenuBarPlausible(double h) { return h >= 16.0 && h <= 40.0; }
// providerHeight: the visual provider's +height (0 when it could not be read); viewHeight: the bar copy's own height (0: none). 0: not known yet.
static inline double MSBDMenuBarHeightOf(double providerHeight, double viewHeight) {
    if (MSBDMenuBarPlausible(providerHeight)) return providerHeight;
    if (MSBDMenuBarPlausible(viewHeight)) return viewHeight;
    return 0.0;
}
// The height our items in one bar copy are laid out in (StatusBar.x DMBarCopyHeight; 1.8.7, Reddit: an iPad 6 on 15.7 showed a huge Apple logo while
// taking a screenshot with the corner swipe). iOS lays a bar's items out from its top in its visual provider's +height, and a copy's own height is
// that -- except where SpringBoard gives a copy a taller frame: the corner swipe's screenshot puts up a placeholder of the screenshot editor's chrome
// with a status bar the size of the whole screen (SBInteractiveScreenshotGestureRootViewController's _chromePlaceholderStatusBar, 1194 x 834 on the
// M1 in landscape), and our logo was sized and centred on that: its ink is the height less 9 pt at Small -- 825 pt there, 759 on an iPad 6 in
// landscape --, and at every size it sat at mid-screen, while iOS's own items stayed at the top. So: a copy taller than any bar (over 40 pt, the
// most a bar is: MSBDMenuBarPlausible) takes its provider's height when that is a bar's height, else the bar height known from the iPad's own bar
// (known, 0: not known). Every bar-sized copy keeps its own height, as before, even where it differs from its provider's: a TV's bar on a Face ID
// iPad is 24 pt over _UIStatusBarVisualProvider_ExternalPad's +height 20 at Small, and its logo and touch areas are the 24 pt bar's.
static inline double MSBDMenuBarCopyHeight(double providerHeight, double viewHeight, double known) {
    if (!(viewHeight > 40.0)) return viewHeight;   // (a bar's own height, or none yet: as before)
    if (MSBDMenuBarPlausible(providerHeight)) return providerHeight;
    if (MSBDMenuBarPlausible(known)) return known;
    return viewHeight;
}
// The geometry from the bar's height: the top windows and tiles may reach -- right under the bar (24 on a 24 pt bar), since 1.7.2: one point into the
// bar before (23), where a window over the bar covered the foot of its text (KT 31 Oct, M1: the "g" of "Settings" under a filled window); Stage
// Manager's stage always started at the bar's height --, the "center" layout's and MilkyWay4's default top (36: 12 pt under the bar), a touch on
// the screen above this is on the bar (26), and auto-hide's "the window was at the top" band (23.5 +- 2 when it hides; under 22 when it comes back,
// the window goes to the top).
static inline double MSBDMenuBarTopLimit(double bar) { return bar; }
static inline double MSBDMenuBarCenterTop(double bar) { return bar + 12.0; }
static inline double MSBDMenuBarTouchBand(double bar) { return bar + 2.0; }
static inline double MSBDMenuBarWasTop(double bar) { return bar - 0.5; }
static inline double MSBDMenuBarUnderTop(double bar) { return bar - 2.0; }

// 1.7.2 item 9: a window placed before 1.7.1 on a Home-button iPad kept the 24 pt bar's top (the window's top edge, our title bar's: 24 with Stage
// Manager, 23 with the other engines) and showed a 4 pt band of wallpaper under the 20 pt bar until it was moved. Re-fitted once (StatusBar.x
// DMSMRefitOldTopTick, DMRestoreStep): a window whose top is at the old top (within half a point) goes up to the new one; one that reached the
// desktop's bottom (areaBottom; NAN: not known -- saved in the other screen shape) keeps its bottom and grows by the difference (a full-height
// window, a left or right tile), any other keeps its size. y / height: the whole window, title bar included. Returns 1 when it moves.
static inline int MSBDMenuBarRefitTop(double *y, double *height, double oldTop, double newTop, double areaBottom) {
    if (!y || !height || !isfinite(*y) || !isfinite(*height) || !(*height > 0) || !isfinite(oldTop) || !isfinite(newTop)) return 0;
    if (!(newTop < oldTop - 0.25) || fabs(*y - oldTop) > 0.5) return 0;
    double bottom = *y + *height;
    if (isfinite(areaBottom) && fabs(bottom - areaBottom) <= 0.5) *height = bottom - newTop;
    *y = newTop;
    return 1;
}

#endif
