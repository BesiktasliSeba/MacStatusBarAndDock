// MenuBarSize.h -- Settings > Status Bar > Menu Bar Size (1.7.3; KT 31 Oct: Small / Medium / Large instead of one Larger Menu Bar switch,
// plans/larger-menu-bar.md), plain C so the Mac test (tools/test-menubarheight.sh) runs these very numbers.
//  - Small: today's bar exactly -- iOS's own height (24 pt on Face ID iPads, 20 pt on Home-button iPads) and text (12 pt). The default. Nothing of
//    1.7.3 runs then: StatusBar.x puts no hook on iOS's bar and every number below is the one before.
//  - Medium: a 30 pt bar, text and icons x 1.125 (13.5 pt text), menu rows 33 pt.
//  - Large: a 37 pt bar (a notch MacBook's menu bar), text and icons x 1.25 (15 pt text), menu rows 36 pt.
//  Medium and Large are the same on every iPad, Face ID or Home button. The windows' title bars stay 24 pt at every size, and a TV keeps the normal bar.
//  The root of it is iOS's own bar made taller in SpringBoard (StatusBar.x DMBarSizeInit: the bar's visual provider's height, text and icon scale):
//  SpringBoard sizes every copy of the bar from it and hands the height to every app, whose content then starts under it. iOS works a bar's height
//  out once and gives it to an app when its scene starts, so a new size applies from the next SpringBoard start (Settings offers the respring).
#ifndef MSBD_MENU_BAR_SIZE_H
#define MSBD_MENU_BAR_SIZE_H
#include <math.h>
#include "MenuBarHeight.h"

#define kMSBDMenuBarSizeKey "menuBarSize"   // (com.besiktasliseba.macstatusbar: 0 Small, 1 Medium, 2 Large -- a number, so the crash guard can set it
                                             //  back to "off", as it does a switch: false, read as Small)
enum { MSBDMenuBarSmall = 0, MSBDMenuBarMedium = 1, MSBDMenuBarLarge = 2 };

// The stored value: 1 Medium, 2 Large; anything else -- never set, false (the crash guard's off), another number or type -- Small.
static inline int MSBDMenuBarSizeFrom(int isNumber, double value) {
    if (!isNumber || !isfinite(value)) return MSBDMenuBarSmall;
    return value == 1.0 ? MSBDMenuBarMedium : value == 2.0 ? MSBDMenuBarLarge : MSBDMenuBarSmall;
}

// iOS's bar on the iPad's own screen. Its height: the size's (Small: iOS's own, `stock`); its text and icons: x the scale; its text's baseline (from
// the bar's top): the middle of the text's capitals on the middle of the bar -- SF Pro's capitals are 0.7046 of the point size, and this rule gives
// iOS's own 16 for its 24 pt bar and 14 for its 20 pt one (+[_UIStatusBarVisualProvider_RoundedPad / _Pad baselineOffset], 12 pt text, 15.6.1).
#define kMSBDMenuBarStockText 12.0   // (iOS's status bar text on the iPad: -[_UIStatusBarVisualProvider_Pad normalFont], 12 pt Medium)
#define kMSBDCapHalf 0.3523
static inline double MSBDMenuBarSizeHeight(int size, double stock) { return size == MSBDMenuBarLarge ? 37.0 : size == MSBDMenuBarMedium ? 30.0 : stock; }
static inline double MSBDMenuBarSizeScale(int size) { return size == MSBDMenuBarLarge ? 1.25 : size == MSBDMenuBarMedium ? 1.125 : 1.0; }
static inline double MSBDMenuBarBaselineFor(double height, double textPt) { return round(height / 2.0 + kMSBDCapHalf * textPt); }
static inline double MSBDMenuBarSizeBaseline(int size, double stock) {
    if (size == MSBDMenuBarSmall) return stock;
    return MSBDMenuBarBaselineFor(MSBDMenuBarSizeHeight(size, 0.0), kMSBDMenuBarStockText * MSBDMenuBarSizeScale(size));
}

// The Apple logo's ink (its drawn height): the bar's height less 4.5 pt above and below -- 15 pt on a 24 pt bar, 11 on a 20 pt one --, which on a 37 pt
// bar would be 28 pt; at Medium and Large it is 1.25 x the text instead (as on a 24 pt bar: 15 = 1.25 x 12), never more than the bar's rule gives.
#define kMSBDLogoBarMargin 4.5
static inline double MSBDMenuBarLogoInk(int size, double barHeight, double textPt) {
    double fill = barHeight - 2.0 * kMSBDLogoBarMargin;
    return size == MSBDMenuBarSmall ? fill : fmin(fill, 1.25 * textPt);
}

// iOS's battery in the bar (StatusBar.x DMBarSizeBatteryInit): drawn from a fixed size category, not the icon scale the bar's other icons take, so its
// measures -- body, pin, outline, corners and the charging bolt's scale -- are the category's x this: the size's scale for a battery of a bar that took
// the size (sizedBar), 1 for any other (a TV's bar, a battery outside the bar) and at Small. The iPad's category (icon size 14): a 24 x 12 pt body, a
// 1.5 x 4.5 pin, a 1 pt outline (26.5 x 12 with its pin; 15.6.1 to 18.5) -> 30 x 15, 1.875 x 5.625, 1.25 (33.125 x 15) at Large; 27 x 13.5, 1.6875 x
// 5.0625, 1.125 (29.8125 x 13.5) at Medium.
static inline double MSBDMenuBarBatteryScale(int size, int sizedBar) { return sizedBar ? MSBDMenuBarSizeScale(size) : 1.0; }

// The places that took a fixed 24 pt bar before 1.7.3 -- the Mac-style banners' top, the keyboard button's pill, the Stage Manager note pill, the
// Wi-Fi menu's room under the bar, auto-hide's "touching the top" band: 24 at Small, as before (a Home-button iPad's 20 pt bar included, so Small is
// today's look), the bar's own height at Medium and Large.
static inline double MSBDMenuBarFixedSite(int size, double bar) { return size == MSBDMenuBarSmall ? kMSBDMenuBarDefault : bar; }

// Our menus (StatusBar.x DMRow / DMMakePanel, the Wi-Fi menu's rows): taller rows and larger text for fingers -- rows 30 / 33 / 36 pt, text 14 / 15 /
// 16 pt. Other heights in a menu scale with its rows (whole points), widths and other text with its text (half points).
static inline double MSBDMenuRowHeight(int size) { return size == MSBDMenuBarLarge ? 36.0 : size == MSBDMenuBarMedium ? 33.0 : 30.0; }
static inline double MSBDMenuTextSize(int size) { return size == MSBDMenuBarLarge ? 16.0 : size == MSBDMenuBarMedium ? 15.0 : 14.0; }
static inline double MSBDMenuRowScaled(int size, double small) { return size == MSBDMenuBarSmall ? small : round(small * MSBDMenuRowHeight(size) / 30.0); }
static inline double MSBDMenuTextScaled(int size, double small) { return size == MSBDMenuBarSmall ? small : round(2.0 * small * MSBDMenuTextSize(size) / 14.0) / 2.0; }
// A menu hanging from the bar that is taller than the room under it (StatusBar.x DMMakeBarMenuPanel: from the menu's top to the screen's bottom less a
// margin) gets shorter rows -- whole points, never shorter than Small's 30 --, so every row stays on the screen: the Window menu at Large on the iPad
// 2's 768 pt landscape screen (19 rows of 36 pt, 5 separators of 13 pt, 12 pt of pads: 761 pt from y 39) ran 32 pt past its bottom, its last row out
// of reach (1.7.3 device pass). rows: its plain rows; other: everything else in it (separators, rows with heights of their own, the pads). A menu that
// fits keeps rowH; at Small nothing changes (30 already).
static inline double MSBDMenuRowFit(double rowH, int rows, double other, double room) {
    if (rows <= 0 || !(room > 0) || rows * rowH + other <= room) return rowH;
    double smallest = fmin(rowH, MSBDMenuRowHeight(MSBDMenuBarSmall));
    return fmax(fmin(floor((room - other) / rows), rowH), smallest);
}

// BigSurCenter's Control Center panel rests 20 pt below the screen's top (StatusBar.x DMScalePanelView), right under iOS's own bar; under the taller
// bar of Medium and Large its top sat inside the bar, over its lower 10 / 17 pt (iPad 2, 1.7.3 device pass). It is drawn lower by as much as the bar
// grew (the size's height less iOS's own: `stock`, 0 when not known), so it keeps today's place against the bar. Small: 0, as before.
static inline double MSBDCCPanelShift(int size, double bar, double stock) {
    if (size == MSBDMenuBarSmall || !(stock > 0) || !(bar > stock)) return 0.0;
    return bar - stock;
}

// Windows placed under a bar of another size (Menu Bar Size changed since: StatusBar.x DMRestoreStep for Aerial / Zetsu / MilkyWay4, DMSMRefitOldTopTick
// for Stage Manager). y / height: the whole window, our title bar included; oldTop: the top under the bar they were placed with (NAN: not known --
// placed before 1.7.3, under the Small bar); newTop: the top under the bar now; areaBottom: the desktop's bottom (NAN: not known); minHeight: the
// smallest a window may be (0: none). Returns 1 when it moves.
//  - a taller bar: a window it would cover -- its top above the new top by more than half a point -- goes down under it and keeps its bottom: a
//    full-height window or a tile gets shorter by the difference, so the tiles keep their gaps and nothing goes past the desktop's bottom. One that
//    would end up shorter than a window may be keeps its height instead (moved down; the engine keeps it on the desktop);
//  - a shorter bar: a window at the old top goes up under the new one (MSBDMenuBarRefitTop: the bottom kept when it reached the desktop's, else the
//    size), so no band of wallpaper stays between the bar and the window. A window placed lower is the user's place: left.
static inline int MSBDMenuBarRefitSize(double *y, double *height, double oldTop, double newTop, double areaBottom, double minHeight) {
    if (!y || !height || !isfinite(*y) || !isfinite(*height) || !(*height > 0) || !isfinite(newTop)) return 0;
    if (isfinite(oldTop) && newTop < oldTop - 0.25) return MSBDMenuBarRefitTop(y, height, oldTop, newTop, areaBottom);
    if (!(*y < newTop - 0.5)) return 0;
    double bottom = *y + *height;
    if (bottom - newTop >= minHeight) *height = bottom - newTop;
    *y = newTop;
    return 1;
}
// A scene that does not reach its screen's top edge -- a window (Stage Manager's, another engine's), Slide Over -- is not under the bar: it keeps iOS's
// own status bar height, from which an app takes its top safe area (in a window too); a scene under the bar (full screen, Split View) takes the size's
// (StatusBar.x DMBarSizeSceneIsWindow). Told in the scene's own coordinate space, FrontBoardServices' -[FBSSceneSettings bounds]: the frame's size
// turned to the scene's orientation (3 / 4, landscape: width and height swapped; read on 15.6.1, 16.7.7 and 18.5). A scene under the bar spans the
// screen's whole height there -- full screen, a Split View half --, a window is shorter. The frame's origin is not used: iOS's own frames have it in the
// display's portrait space, but an Aerial window's on 15 has the window's place on the screen with the size in portrait terms (M1, landscape: App
// Store's {{406, 249.8}, {512, 788}}), which the portrait-space reading (R1 / R2's top gap) took for a scene on the top edge, ~25 times a start.
// sceneH: the scene's height in its own space; dw, dh: the display's bounds (portrait); orientation: the scene's (1 portrait, 2 upside down, 3 / 4
// landscape). The shortfall: how much less than the screen's height the scene is.
static inline double MSBDSceneShortfall(double sceneH, double dw, double dh, long orientation) {
    return ((orientation == 3 || orientation == 4) ? dw : dh) - sceneH;
}
static inline int MSBDSceneIsWindow(double shortfall) { return isfinite(shortfall) && shortfall > 0.5; }

// The Lock Screen's Control Center grabber (iPadOS 18) sits at a fixed top per device, 2 pt under iOS's own bar: it goes down by what the size added to
// the bar (`bar` the bar now, `stock` iOS's own height of it); nothing at Small or while either is not known.
static inline double MSBDMenuBarGrabberShift(int size, double bar, double stock) {
    if (size == MSBDMenuBarSmall || !(bar > 0) || !(stock > 0)) return 0.0;
    return bar > stock ? bar - stock : 0.0;
}

// Whether windows placed under the bar `placedBar` (NAN: not known -- saved before 1.7.3) are re-fitted to the bar now (`bar`, at `size`): when the bar's
// height changed since; not known, only at Medium and Large (before 1.7.3 every window was placed under the Small bar, so at Small nothing changed).
static inline int MSBDMenuBarRefitWanted(double placedBar, double bar, int size) {
    if (!(bar > 0)) return 0;
    return isfinite(placedBar) ? fabs(placedBar - bar) > 0.25 : size != MSBDMenuBarSmall;
}

#endif
