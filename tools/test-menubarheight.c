// test-menubarheight.c -- Mac test of our menu bar's height and the window geometry taken from it (common/MenuBarHeight.h, used by StatusBar.x
// DMMenuBarHeight and its sites; 1.7.1 item 14): iOS's provider height first (24 Face ID, 20 Home button), else the bar's own height, else not known
// (24 used); Face ID iPads keep every number they had; a Home-button iPad's windows start right under its 20 pt bar.
#include <stdio.h>
#include "../common/MenuBarHeight.h"
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
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
