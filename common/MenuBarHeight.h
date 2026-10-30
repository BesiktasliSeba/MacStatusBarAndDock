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

#define kMSBDMenuBarDefault 24.0   // (before a bar is known; Face ID iPads' bar)

static inline int MSBDMenuBarPlausible(double h) { return h >= 16.0 && h <= 40.0; }
// providerHeight: the visual provider's +height (0 when it could not be read); viewHeight: the bar copy's own height (0: none). 0: not known yet.
static inline double MSBDMenuBarHeightOf(double providerHeight, double viewHeight) {
    if (MSBDMenuBarPlausible(providerHeight)) return providerHeight;
    if (MSBDMenuBarPlausible(viewHeight)) return viewHeight;
    return 0.0;
}
// The geometry from the bar's height (each is the number it was with the 24 pt bar): the top windows and tiles may reach -- one point into the bar,
// as before (23) --, the "center" layout's and MilkyWay4's default top (36: 12 pt under the bar), a touch on the screen above this is on the bar
// (26), and auto-hide's "the window was at the top" band (23.5 +- 2 when it hides; under 22 when it comes back, the window goes to 23).
static inline double MSBDMenuBarTopLimit(double bar) { return bar - 1.0; }
static inline double MSBDMenuBarCenterTop(double bar) { return bar + 12.0; }
static inline double MSBDMenuBarTouchBand(double bar) { return bar + 2.0; }
static inline double MSBDMenuBarWasTop(double bar) { return bar - 0.5; }
static inline double MSBDMenuBarUnderTop(double bar) { return bar - 2.0; }

#endif
