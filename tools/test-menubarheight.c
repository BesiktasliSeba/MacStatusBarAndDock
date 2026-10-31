// test-menubarheight.c -- Mac test of our menu bar's height and the window geometry taken from it (common/MenuBarHeight.h, used by StatusBar.x
// DMMenuBarHeight and its sites; 1.7.1 item 14): iOS's provider height first (24 Face ID, 20 Home button), else the bar's own height, else not known
// (24 used); Face ID iPads keep every number they had; a Home-button iPad's windows start right under its 20 pt bar.
// 1.7.3: Menu Bar Size (common/MenuBarSize.h): Small is every number as before; Medium and Large, the bar, its text, our items and menus, the
// geometry under the taller bar, and the windows placed under a bar of another size.
#include <stdio.h>
#include "../common/MenuBarSize.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, double got, double want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %.2f, want %.2f)\n", what, got, want); } else printf("PASS  %s\n", what); }
int main(void) {
    Expect("Face ID iPad: iOS's provider says 24 (_UIStatusBarVisualProvider_RoundedPad)", MSBDMenuBarHeightOf(24.0, 24.0), 24.0);
    Expect("Home-button iPad: iOS's provider says 20 (_UIStatusBarVisualProvider_Pad; iPad 2, 16.7.7)", MSBDMenuBarHeightOf(20.0, 20.0), 20.0);
    Expect("  ... the provider first, whatever the copy measures", MSBDMenuBarHeightOf(20.0, 24.0), 20.0);
    Expect("no provider to read: the copy's own height", MSBDMenuBarHeightOf(0.0, 20.0), 20.0);
    Expect("a provider value that is no bar height (100): the copy's", MSBDMenuBarHeightOf(100.0, 24.0), 24.0);
    Expect("  ... too small (12): the copy's", MSBDMenuBarHeightOf(12.0, 20.0), 20.0);
    Expect("a copy not laid out yet (0 tall), no provider: not known", MSBDMenuBarHeightOf(0.0, 0.0), 0.0);
    Expect("  ... a copy squashed by an animation (6 tall): not known", MSBDMenuBarHeightOf(0.0, 6.0), 0.0);
    Expect("not known: 24, the geometry as it was", kMSBDMenuBarDefault, 24.0);
    // a 24 pt bar: every number as before 1.7.1 item 14, but the top: right under the bar since 1.7.2
    Expect("24 pt bar: windows and tiles reach 24 -- right under the bar, none of it covered (DMTopLimit; 23 before 1.7.2)", MSBDMenuBarTopLimit(24.0), 24.0);
    Expect("24 pt bar: the center layout's top is 36 (as before)", MSBDMenuBarCenterTop(24.0), 36.0);
    Expect("24 pt bar: a touch above 26 is on the bar (NativeWindow.h, as before)", MSBDMenuBarTouchBand(24.0), 26.0);
    Expect("24 pt bar: auto-hide's top band 23.5 (as before)", MSBDMenuBarWasTop(24.0), 23.5);
    Expect("24 pt bar: auto-hide puts a window above 22 back at the top (as before)", MSBDMenuBarUnderTop(24.0), 22.0);
    // a 20 pt bar (Home-button iPads): the same distances from the bar
    Expect("20 pt bar: windows and tiles reach 20 -- right under the bar (19 before 1.7.2)", MSBDMenuBarTopLimit(20.0), 20.0);
    Expect("20 pt bar: the center layout 12 pt under the bar (32)", MSBDMenuBarCenterTop(20.0), 32.0);
    Expect("20 pt bar: a touch above 22 is on the bar (a window's title bar starts right under it)", MSBDMenuBarTouchBand(20.0), 22.0);
    Expect("20 pt bar: auto-hide's top band 19.5", MSBDMenuBarWasTop(20.0), 19.5);
    Expect("20 pt bar: auto-hide puts a window above 18 back at the top", MSBDMenuBarUnderTop(20.0), 18.0);
    // 1.7.2 item 9: windows placed with the old 24 pt top on a Home-button iPad, re-fitted once
    double y, h;
    y = 24.0; h = 1268.37; Expect("refit: Stage Manager, full height at the old top (KT's Clock): moves up to 20", (MSBDMenuBarRefitTop(&y, &h, 24.0, 20.0, 1292.37), y), 20.0);
    Expect("  ... and keeps its bottom: 4 pt taller", h, 1272.37);
    y = 24.0; h = 600.0; Expect("refit: Stage Manager, at the old top, not full height: moves up", (MSBDMenuBarRefitTop(&y, &h, 24.0, 20.0, 1292.37), y), 20.0);
    Expect("  ... and keeps its size", h, 600.0);
    y = 24.3; h = 600.0; Expect("refit: within half a point of the old top counts", MSBDMenuBarRefitTop(&y, &h, 24.0, 20.0, 1292.37), 1.0);
    y = 25.0; h = 600.0; Expect("refit: a window 1 pt lower is the user's place: left", MSBDMenuBarRefitTop(&y, &h, 24.0, 20.0, 1292.37), 0.0);
    Expect("  ... untouched", y, 25.0);
    y = 20.0; h = 600.0; Expect("refit: a window already at the new top: left", MSBDMenuBarRefitTop(&y, &h, 24.0, 20.0, 1292.37), 0.0);
    y = 24.0; h = 600.0; Expect("refit: a Face ID iPad (24 pt bar, nothing moved): left", MSBDMenuBarRefitTop(&y, &h, 24.0, 24.0, 1292.37), 0.0);
    y = 23.0; h = 649.0; Expect("refit: other engines, full height at 23 (the old top limit): moves up to 19", (MSBDMenuBarRefitTop(&y, &h, 23.0, 19.0, 672.0), y), 19.0);
    Expect("  ... and keeps its bottom", h, 653.0);
    y = 23.0; h = 649.0; Expect("refit: the desktop's bottom not known (saved in the other shape): moves up only", (MSBDMenuBarRefitTop(&y, &h, 23.0, 19.0, NAN), h), 649.0);
    Expect("  ... to the new top", y, 19.0);
    y = NAN; h = 600.0; Expect("refit: not a number: left", MSBDMenuBarRefitTop(&y, &h, 24.0, 20.0, 1292.37), 0.0);

    // ---- 1.7.3 Menu Bar Size (common/MenuBarSize.h) ----
    // the stored value: Settings writes 0 / 1 / 2; the crash guard writes false (not a number); anything else is Small
    Expect("stored 0: Small", MSBDMenuBarSizeFrom(1, 0.0), MSBDMenuBarSmall);
    Expect("stored 1: Medium", MSBDMenuBarSizeFrom(1, 1.0), MSBDMenuBarMedium);
    Expect("stored 2: Large", MSBDMenuBarSizeFrom(1, 2.0), MSBDMenuBarLarge);
    Expect("never set / the crash guard's false (not a number): Small", MSBDMenuBarSizeFrom(0, 2.0), MSBDMenuBarSmall);
    Expect("another number (3, -1, 1.5, NAN): Small", MSBDMenuBarSizeFrom(1, 3.0) + MSBDMenuBarSizeFrom(1, -1.0) + MSBDMenuBarSizeFrom(1, 1.5) + MSBDMenuBarSizeFrom(1, NAN), MSBDMenuBarSmall);
    // Small: iOS's own bar, every number as before (nothing hooked)
    Expect("Small, Face ID iPad: iOS's 24 pt", MSBDMenuBarSizeHeight(MSBDMenuBarSmall, 24.0), 24.0);
    Expect("Small, Home-button iPad: iOS's 20 pt", MSBDMenuBarSizeHeight(MSBDMenuBarSmall, 20.0), 20.0);
    Expect("Small: text and icons x 1", MSBDMenuBarSizeScale(MSBDMenuBarSmall), 1.0);
    Expect("Small: iOS's baseline as it is (16)", MSBDMenuBarSizeBaseline(MSBDMenuBarSmall, 16.0), 16.0);
    Expect("Small: the logo's ink fills a 24 pt bar less 4.5 pt each side (15, as before)", MSBDMenuBarLogoInk(MSBDMenuBarSmall, 24.0, 12.0), 15.0);
    Expect("Small: ... 11 on a Home-button iPad's 20 pt bar (as before)", MSBDMenuBarLogoInk(MSBDMenuBarSmall, 20.0, 12.0), 11.0);
    Expect("Small: the fixed sites keep 24 on a Face ID iPad", MSBDMenuBarFixedSite(MSBDMenuBarSmall, 24.0), 24.0);
    Expect("Small: ... and on a Home-button iPad's 20 pt bar (the banners' and pills' places as before)", MSBDMenuBarFixedSite(MSBDMenuBarSmall, 20.0), 24.0);
    Expect("Small: menu rows 30 pt", MSBDMenuRowHeight(MSBDMenuBarSmall), 30.0);
    Expect("Small: menu text 14 pt", MSBDMenuTextSize(MSBDMenuBarSmall), 14.0);
    Expect("Small: a separator 11 pt, a panel 230 pt, a heading 24 pt (as before)", MSBDMenuRowScaled(MSBDMenuBarSmall, 11.0) + MSBDMenuTextScaled(MSBDMenuBarSmall, 230.0) + MSBDMenuRowScaled(MSBDMenuBarSmall, 24.0), 265.0);
    Expect("Small: the hint's 13 pt as before", MSBDMenuTextScaled(MSBDMenuBarSmall, 13.0), 13.0);
    // the baseline rule reproduces iOS's own numbers (+[_UIStatusBarVisualProvider_RoundedPad / _Pad baselineOffset], 15.6.1)
    Expect("the baseline rule: 24 pt bar, 12 pt text -> 16 (iOS's RoundedPad)", MSBDMenuBarBaselineFor(24.0, 12.0), 16.0);
    Expect("the baseline rule: 20 pt bar, 12 pt text -> 14 (iOS's Pad)", MSBDMenuBarBaselineFor(20.0, 12.0), 14.0);
    // Medium: 30 pt, 13.5 pt text, rows 33
    Expect("Medium: a 30 pt bar on a Face ID iPad", MSBDMenuBarSizeHeight(MSBDMenuBarMedium, 24.0), 30.0);
    Expect("Medium: ... and on a Home-button iPad (the same on every iPad)", MSBDMenuBarSizeHeight(MSBDMenuBarMedium, 20.0), 30.0);
    Expect("Medium: text and icons x 1.125 (12 -> 13.5 pt)", kMSBDMenuBarStockText * MSBDMenuBarSizeScale(MSBDMenuBarMedium), 13.5);
    Expect("Medium: the baseline 20 (the capitals' middle on the bar's middle)", MSBDMenuBarSizeBaseline(MSBDMenuBarMedium, 16.0), 20.0);
    Expect("Medium: the logo's ink 1.25 x 13.5 = 16.875 (not the 21 the bar would give)", MSBDMenuBarLogoInk(MSBDMenuBarMedium, 30.0, 13.5), 16.875);
    Expect("Medium: menu rows 33, text 15", MSBDMenuRowHeight(MSBDMenuBarMedium) + MSBDMenuTextSize(MSBDMenuBarMedium), 48.0);
    Expect("Medium: a separator 12, a Wi-Fi heading 26, its switch row 37", MSBDMenuRowScaled(MSBDMenuBarMedium, 11.0) * 10000 + MSBDMenuRowScaled(MSBDMenuBarMedium, 24.0) * 100 + MSBDMenuRowScaled(MSBDMenuBarMedium, 34.0), 122637.0);
    Expect("Medium: a panel 246.5 wide, the hint 14", MSBDMenuTextScaled(MSBDMenuBarMedium, 230.0) + MSBDMenuTextScaled(MSBDMenuBarMedium, 13.0), 260.5);
    Expect("Medium: the fixed sites take the bar (30)", MSBDMenuBarFixedSite(MSBDMenuBarMedium, 30.0), 30.0);
    // Large: 37 pt, 15 pt text, rows 36 (KT's decisions, 30 Oct)
    Expect("Large: a 37 pt bar on a Face ID iPad", MSBDMenuBarSizeHeight(MSBDMenuBarLarge, 24.0), 37.0);
    Expect("Large: ... and on a Home-button iPad", MSBDMenuBarSizeHeight(MSBDMenuBarLarge, 20.0), 37.0);
    Expect("Large: text and icons x 1.25 (12 -> 15 pt)", kMSBDMenuBarStockText * MSBDMenuBarSizeScale(MSBDMenuBarLarge), 15.0);
    Expect("Large: the baseline 24", MSBDMenuBarSizeBaseline(MSBDMenuBarLarge, 16.0), 24.0);
    Expect("Large: the logo's ink 18.75 (1.25 x 15; the bar's rule would give 28)", MSBDMenuBarLogoInk(MSBDMenuBarLarge, 37.0, 15.0), 18.75);
    Expect("Large: ... never more than the bar's rule (a bar copy squeezed to 24 pt: 15)", MSBDMenuBarLogoInk(MSBDMenuBarLarge, 24.0, 15.0), 15.0);
    Expect("Large: menu rows 36, text 16", MSBDMenuRowHeight(MSBDMenuBarLarge) * 100 + MSBDMenuTextSize(MSBDMenuBarLarge), 3616.0);
    Expect("Large: a separator 13, a Wi-Fi heading 29, its switch row 41", MSBDMenuRowScaled(MSBDMenuBarLarge, 11.0) * 10000 + MSBDMenuRowScaled(MSBDMenuBarLarge, 24.0) * 100 + MSBDMenuRowScaled(MSBDMenuBarLarge, 34.0), 132941.0);
    Expect("Large: a panel 263 wide (230 x 16 / 14 = 262.9), the hint 15", MSBDMenuTextScaled(MSBDMenuBarLarge, 230.0) * 100 + MSBDMenuTextScaled(MSBDMenuBarLarge, 13.0), 26315.0);
    // the geometry under the taller bar (MenuBarHeight.h, from the bar's height as DMMenuBarHeight reads it -- iOS's provider, now the size's)
    Expect("Large: windows and tiles reach 37, right under the bar", MSBDMenuBarTopLimit(MSBDMenuBarSizeHeight(MSBDMenuBarLarge, 24.0)), 37.0);
    Expect("Large: the center layout 12 pt under the bar (49)", MSBDMenuBarCenterTop(37.0), 49.0);
    Expect("Large: a touch above 39 is on the bar", MSBDMenuBarTouchBand(37.0), 39.0);
    Expect("Large: auto-hide's top band 36.5, a window above 35 back at the top", MSBDMenuBarWasTop(37.0) * 100 + MSBDMenuBarUnderTop(37.0), 3685.0);
    Expect("Large: 37 is a bar height (16..40), so DMMenuBarHeight takes the provider's 37", MSBDMenuBarHeightOf(37.0, 37.0), 37.0);
    Expect("Medium: 30 likewise", MSBDMenuBarHeightOf(30.0, 30.0), 30.0);
    // 1.7.2 item 9's re-fit is only for bars shorter than 24 (StatusBar.x DMRefitTopWanted): a taller bar is no "old 24 pt top"
    y = 24.0; h = 600.0; Expect("item 9's rule never moves a window down: 24 -> 37 is not a re-fit", MSBDMenuBarRefitTop(&y, &h, 24.0, 37.0, 1000.0), 0.0);
    // windows placed under a bar of another size (MSBDMenuBarRefitSize: Aerial / Zetsu / MilkyWay4's saved windows, Stage Manager's stages)
    // a taller bar: Small 24 -> Large 37 on the A12Z (landscape desktop 24..945.7: the Dock's top 947.7 less 2)
    y = 24.0; h = 921.7; Expect("Small -> Large: a full-height window goes under the 37 pt bar", (MSBDMenuBarRefitSize(&y, &h, 24.0, 37.0, 945.7, 324.0), y), 37.0);
    Expect("  ... and keeps its bottom (13 pt shorter)", y + h, 945.7);
    y = 24.0; h = 454.0; Expect("Small -> Large: a top tile (24..478) goes under the bar", (MSBDMenuBarRefitSize(&y, &h, 24.0, 37.0, 945.7, 324.0), y), 37.0);
    Expect("  ... keeping its bottom: the 6 pt gap to the bottom tile stays", y + h, 478.0);
    y = 30.0; h = 500.0; Expect("Small -> Large: a window at 30, partly under the new bar, goes down to 37", (MSBDMenuBarRefitSize(&y, &h, 24.0, 37.0, 945.7, 324.0), y), 37.0);
    Expect("  ... keeping its bottom", y + h, 530.0);
    y = 36.6; h = 500.0; Expect("Small -> Large: within half a point of the new top: left", MSBDMenuBarRefitSize(&y, &h, 24.0, 37.0, 945.7, 324.0), 0.0);
    y = 120.0; h = 500.0; Expect("Small -> Large: a window lower down: left", MSBDMenuBarRefitSize(&y, &h, 24.0, 37.0, 945.7, 324.0), 0.0);
    y = 24.0; h = 330.0; Expect("Small -> Large: a window that would get shorter than a window may be (317 < 324) moves down", (MSBDMenuBarRefitSize(&y, &h, 24.0, 37.0, 945.7, 324.0), y), 37.0);
    Expect("  ... keeping its height", h, 330.0);
    y = 24.0; h = 600.0; Expect("saved before 1.7.3 (the old bar not known), now Large: moved under the bar all the same", (MSBDMenuBarRefitSize(&y, &h, NAN, 37.0, NAN, 324.0), y), 37.0);
    y = 20.0; h = 600.0; Expect("a Home-button iPad, Small 20 -> Medium 30", (MSBDMenuBarRefitSize(&y, &h, 20.0, 30.0, 1100.0, 324.0), y), 30.0);
    // a shorter bar: Large 37 -> Small 24: the windows at the old top go up (no band of wallpaper), the user's own places stay
    y = 37.0; h = 908.7; Expect("Large -> Small: a full-height window at 37 goes up to 24", (MSBDMenuBarRefitSize(&y, &h, 37.0, 24.0, 945.7, 324.0), y), 24.0);
    Expect("  ... keeping its bottom (13 pt taller)", y + h, 945.7);
    y = 37.0; h = 500.0; Expect("Large -> Small: a window at the old top, not full height: up to 24", (MSBDMenuBarRefitSize(&y, &h, 37.0, 24.0, 945.7, 324.0), y), 24.0);
    Expect("  ... keeping its size", h, 500.0);
    y = 60.0; h = 500.0; Expect("Large -> Small: a window lower down is the user's place: left", MSBDMenuBarRefitSize(&y, &h, 37.0, 24.0, 945.7, 324.0), 0.0);
    y = 37.0; h = 500.0; Expect("Large -> Medium: 37 -> 30", (MSBDMenuBarRefitSize(&y, &h, 37.0, 30.0, 945.7, 324.0), y), 30.0);
    y = 37.0; h = 600.0; Expect("Large -> Small on a Home-button iPad: 37 -> 20", (MSBDMenuBarRefitSize(&y, &h, 37.0, 20.0, 1100.0, 324.0), y), 20.0);
    y = 24.0; h = 600.0; Expect("the same bar (24 -> 24): left", MSBDMenuBarRefitSize(&y, &h, 24.0, 24.0, 945.7, 324.0), 0.0);
    y = NAN; h = 600.0; Expect("not a number: left", MSBDMenuBarRefitSize(&y, &h, 24.0, 37.0, 945.7, 324.0), 0.0);
    // when the windows are re-fitted at all (StatusBar.x: DMRestoreWindows, DMSMRefitOldTopTick)
    Expect("re-fit wanted: placed under 24, the bar 37 now", MSBDMenuBarRefitWanted(24.0, 37.0, MSBDMenuBarLarge), 1.0);
    Expect("re-fit wanted: placed under 37, the bar 24 now (back to Small)", MSBDMenuBarRefitWanted(37.0, 24.0, MSBDMenuBarSmall), 1.0);
    Expect("no re-fit: the same bar", MSBDMenuBarRefitWanted(37.0, 37.0, MSBDMenuBarLarge), 0.0);
    Expect("no re-fit: saved before 1.7.3, still Small (every window was placed under the Small bar)", MSBDMenuBarRefitWanted(NAN, 24.0, MSBDMenuBarSmall), 0.0);
    Expect("re-fit wanted: saved before 1.7.3, now Medium", MSBDMenuBarRefitWanted(NAN, 30.0, MSBDMenuBarMedium), 1.0);
    Expect("no re-fit: the bar not known yet", MSBDMenuBarRefitWanted(24.0, 0.0, MSBDMenuBarLarge), 0.0);
    // a scene under the bar takes the size's status bar height, a window keeps iOS's own: told in the scene's own coordinate space (its settings'
    // -bounds: the frame's size turned to its orientation, as FrontBoardServices does on 15.6.1, 16.7.7 and 18.5), against the display's height there
#define OWN_H(fw, fh, o) (((o) == 3 || (o) == 4) ? (fw) : (fh))
    Expect("landscape right (3): Stage Manager's right-half window {{82.5, 686}, {880.5, 680}} (A12Z, Large) is 680 x 880.5 in its own space: 143.5 pt short",
           MSBDSceneShortfall(OWN_H(880.5, 680.0, 3), 1024, 1366, 3), 143.5);
    Expect("  ... a window: iOS's own height", MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(880.5, 680.0, 3), 1024, 1366, 3)), 1.0);
    Expect("landscape right (3): full screen is under the bar", MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(1024, 1366, 3), 1024, 1366, 3)), 0.0);
    Expect("landscape right (3): a Split View half (the full height, half the width) is under the bar", MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(1024, 683, 3), 1024, 1366, 3)), 0.0);
    Expect("landscape left (4): a window 61 pt down (963 of 1024 tall)", MSBDSceneShortfall(OWN_H(963.0, 1366, 4), 1024, 1366, 4), 61.0);
    Expect("landscape left (4): full screen is under the bar", MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(1024, 1366, 4), 1024, 1366, 4)), 0.0);
    Expect("portrait (1): a window 61 pt down (1305 of 1366 tall)", MSBDSceneShortfall(OWN_H(1024, 1305, 1), 1024, 1366, 1), 61.0);
    Expect("portrait (1): full screen is under the bar", MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(1024, 1366, 1), 1024, 1366, 1)), 0.0);
    Expect("upside down (2): a window 1305 of 1366 tall", MSBDSceneShortfall(OWN_H(1024, 1305, 2), 1024, 1366, 2), 61.0);
    // iPadOS 15, Aerial (M1, 834 x 1194 pt display, landscape 3): its windows' frames have the window's place on the screen with the size in portrait
    // terms; the top gap read in the display's portrait space took these for scenes on the top edge (the bar's height, ~25 times a start)
    Expect("15 Aerial: App Store's {{406, 249.8}, {512, 788}} (788 x 512 on the screen) is a window (the portrait-space top gap read -84)",
           MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(512.0, 788.0, 3), 834, 1194, 3)), 1.0);
    Expect("15 Aerial: Clock's {{600, 48}, {713.8, 594}} (594 x 713.8, at the screen's right edge) is a window (the top gap read -479.8)",
           MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(713.825, 594.0, 3), 834, 1194, 3)), 1.0);
    Expect("15 Aerial: Settings' {{0, 61}, {700.8, 594}} at Large is a window", MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(700.825, 594.0, 3), 834, 1194, 3)), 1.0);
    Expect("15: a full-screen app's {{0, 0}, {834, 1194}} in landscape is under the bar", MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(834.0, 1194.0, 3), 834, 1194, 3)), 0.0);
    Expect("16 Aerial (iPad 2, 768 x 1024): a window scene kept at portrait (1) with its frame as on the screen, 594 x 700, is a window",
           MSBDSceneIsWindow(MSBDSceneShortfall(OWN_H(594.0, 700.0, 1), 768, 1024, 1)), 1.0);
    Expect("half a point short still counts as under the bar", MSBDSceneIsWindow(0.4), 0.0);
    Expect("not a number: not a window (the size's height, as before the fix)", MSBDSceneIsWindow(NAN), 0.0);
#undef OWN_H
    // iOS's battery (MSBDMenuBarBatteryScale, StatusBar.x DMBarSizeBatteryInit): the iPad's size category 14 -- a 24 x 12 pt body, a 1.5 x 4.5 pin,
    // a 1 pt outline, 26.5 x 12 with its pin (+[STUIStatusBarBatteryView _batterySizeForIconSize:14] & co., read on 16.7.7, 17.5.1 and 18.5)
    {
        const double bw = 24.0, bh = 12.0, pw = 1.5, ph = 4.5, lw = 1.0, outer = 3.25;
        double k = MSBDMenuBarBatteryScale(MSBDMenuBarLarge, 1);
        Expect("battery at Large in a bar that took the size: x 1.25", k, 1.25);
        Expect("  ... its body 30 pt wide", bw * k, 30.0);
        Expect("  ... and 15 pt tall (the bar's 37 pt: 11 pt above and below)", bh * k, 15.0);
        Expect("  ... with its pin and outline 33.125 pt wide (iOS's 26.5)", bw * k + lw * k + pw * k, 33.125);
        Expect("  ... the pin 5.625 pt tall", ph * k, 5.625);
        Expect("  ... the outline 1.25 pt (Apple's own expanded bar draws 1.25 too)", lw * k, 1.25);
        Expect("  ... the outer corners 4.0625 pt", outer * k, 4.0625);
        k = MSBDMenuBarBatteryScale(MSBDMenuBarMedium, 1);
        Expect("battery at Medium: x 1.125, 27 x 13.5 pt", bw * k * 100.0 + bh * k, 2713.5);
        Expect("  ... 29.8125 pt with its pin", bw * k + lw * k + pw * k, 29.8125);
        Expect("battery at Small: as it is (26.5 x 12)", (bw + lw + pw) * MSBDMenuBarBatteryScale(MSBDMenuBarSmall, 1), 26.5);
        Expect("battery of a bar that did not take the size (a TV's): as it is", MSBDMenuBarBatteryScale(MSBDMenuBarLarge, 0), 1.0);
        Expect("battery at Large, its scale the same as the bar's other icons and text (x 1.25)", MSBDMenuBarBatteryScale(MSBDMenuBarLarge, 1), MSBDMenuBarSizeScale(MSBDMenuBarLarge));
    }
    // the Lock Screen's Control Center grabber (18): down by what the size added to the bar
    Expect("grabber at Small: where iOS puts it", MSBDMenuBarGrabberShift(MSBDMenuBarSmall, 24.0, 24.0), 0.0);
    Expect("grabber at Large on a Face ID iPad: 13 pt lower (iOS's 26 -> 39, 2 pt under the 37 pt bar)", MSBDMenuBarGrabberShift(MSBDMenuBarLarge, 37.0, 24.0), 13.0);
    Expect("grabber at Medium on a Face ID iPad: 6 pt lower", MSBDMenuBarGrabberShift(MSBDMenuBarMedium, 30.0, 24.0), 6.0);
    Expect("grabber at Large on a Home-button iPad (20 pt bar): 17 pt lower", MSBDMenuBarGrabberShift(MSBDMenuBarLarge, 37.0, 20.0), 17.0);
    Expect("grabber: the bar or iOS's own height not known yet: left", MSBDMenuBarGrabberShift(MSBDMenuBarLarge, 37.0, 0.0), 0.0);
    // a bar menu taller than the room under the bar (MSBDMenuRowFit, StatusBar.x DMMakeBarMenuPanel; 1.7.3 device pass, iPad 2 landscape)
    // the Window menu: 19 rows, 5 separators, 12 pt of pads; its top 2 pt under the title, the room to 6 pt above the screen's bottom
    Expect("Large, iPad 2 landscape: the Window menu (19 x 36 + 5 x 13 + 12 = 761 pt from 39, room 723) gets 34 pt rows", MSBDMenuRowFit(36.0, 19, 5 * 13.0 + 12.0, 768.0 - 39.0 - 6.0), 34.0);
    Expect("  ... and then fits", 19 * MSBDMenuRowFit(36.0, 19, 77.0, 723.0) + 77.0 <= 723.0, 1.0);
    Expect("Large, iPad 2 portrait (1024 pt): 36 pt rows (it fits)", MSBDMenuRowFit(36.0, 19, 77.0, 1024.0 - 39.0 - 6.0), 36.0);
    Expect("Large, the M1 landscape (834 pt): 36 pt rows (761 pt from 39 ends at 800)", MSBDMenuRowFit(36.0, 19, 77.0, 834.0 - 39.0 - 6.0), 36.0);
    Expect("Medium, iPad 2 landscape: 33 pt rows (19 x 33 + 5 x 12 + 12 = 699 from 32: fits)", MSBDMenuRowFit(33.0, 19, 5 * 12.0 + 12.0, 768.0 - 32.0 - 6.0), 33.0);
    Expect("Small: 30 pt rows whatever the room (as before)", MSBDMenuRowFit(30.0, 40, 100.0, 500.0), 30.0);
    Expect("Large, a room so small even 30 pt rows do not fit: never below Small's 30", MSBDMenuRowFit(36.0, 30, 100.0, 700.0), 30.0);
    Expect("a menu of separators only: as it is", MSBDMenuRowFit(36.0, 0, 100.0, 50.0), 36.0);
    Expect("no room known: as it is", MSBDMenuRowFit(36.0, 19, 77.0, 0.0), 36.0);
    // BigSurCenter's Control Center panel under the taller bar (MSBDCCPanelShift, StatusBar.x DMScalePanelView)
    Expect("Large on a Home-button iPad: the panel 17 pt lower (37 - 20), its top at 37", 20.0 + MSBDCCPanelShift(MSBDMenuBarLarge, 37.0, 20.0), 37.0);
    Expect("Medium on a Home-button iPad: 10 pt lower", MSBDCCPanelShift(MSBDMenuBarMedium, 30.0, 20.0), 10.0);
    Expect("Large on a Face ID iPad: 13 pt lower (37 - 24: today's place against the bar)", MSBDCCPanelShift(MSBDMenuBarLarge, 37.0, 24.0), 13.0);
    Expect("Small: where it was", MSBDCCPanelShift(MSBDMenuBarSmall, 20.0, 20.0), 0.0);
    Expect("iOS's own height not known: where it was", MSBDCCPanelShift(MSBDMenuBarLarge, 37.0, 0.0), 0.0);
    // Stage Manager under a taller bar, re-fitted inside the start's request (StatusBar.x DMSMAttrsFitScreen) -- the 17.5 portrait halves
    y = 20.0; h = 633.0; Expect("Small -> Large, 17.5 portrait: the top half (20..653) goes under the 37 pt bar", (MSBDMenuBarRefitSize(&y, &h, 20.0, 37.0, 1292.37, 324.0), y), 37.0);
    Expect("  ... keeping its bottom: 6 pt above the bottom half at 659 (moved down 17 pt it covered 11 pt of it)", y + h, 653.0);
    y = 659.0; h = 633.37; Expect("  ... the bottom half is left where it is", MSBDMenuBarRefitSize(&y, &h, 20.0, 37.0, 1292.37, 324.0), 0.0);
    y = 30.0; h = 1210.0; Expect("Medium -> Small, 17.5: a window at Medium's top (30) goes up to 20", (MSBDMenuBarRefitSize(&y, &h, 30.0, 20.0, 1292.37, 324.0), y), 20.0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
