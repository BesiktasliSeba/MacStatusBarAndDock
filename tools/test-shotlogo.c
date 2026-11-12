// test-shotlogo.c -- Mac test of the height our items in a status bar copy are laid out in (common/MenuBarHeight.h MSBDMenuBarCopyHeight, used by
// StatusBar.x DMBarCopyHeight; 1.8.7, Reddit: an iPad 6 on 15.7 showed a huge Apple logo with the corner-swipe screenshot). SpringBoard's placeholder
// of the screenshot editor's chrome has a status bar the size of the whole screen; our logo took that height: its ink 825 pt on the M1 at Small, mid-screen.
#include <stdio.h>
#include "../common/MenuBarSize.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, double got, double want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %.2f, want %.2f)\n", what, got, want); } else printf("PASS  %s\n", what); }
int main(void) {
    // every ordinary bar: its own height, as before (the provider's height is its own)
    Expect("Face ID iPad's bar: 24 (provider 24, the copy 24)", MSBDMenuBarCopyHeight(24.0, 24.0, 24.0), 24.0);
    Expect("Home-button iPad's bar: 20 (provider 20, the copy 20; iPad 6, iPad 2)", MSBDMenuBarCopyHeight(20.0, 20.0, 20.0), 20.0);
    Expect("Medium: 30 (the size's provider height, the copy 30)", MSBDMenuBarCopyHeight(30.0, 30.0, 30.0), 30.0);
    Expect("Large: 37", MSBDMenuBarCopyHeight(37.0, 37.0, 37.0), 37.0);
    Expect("a TV's bar at Small: 24 (ExternalPad)", MSBDMenuBarCopyHeight(24.0, 24.0, 20.0), 24.0);
    Expect("a TV's bar on a Face ID iPad at Small: 24, over _ExternalPad's +height 20 (provider 20, the copy 24)", MSBDMenuBarCopyHeight(20.0, 24.0, 24.0), 24.0);
    Expect("  ... the known bar a Home-button iPad's 20: still 24", MSBDMenuBarCopyHeight(20.0, 24.0, 20.0), 24.0);
    Expect("a TV's bar at Large over a smaller provider (37 over 20): its own 37", MSBDMenuBarCopyHeight(20.0, 37.0, 24.0), 37.0);
    Expect("a copy 40 tall (the most a bar is): its own", MSBDMenuBarCopyHeight(24.0, 40.0, 24.0), 40.0);
    Expect("a copy 41 tall (taller than any bar): the provider's 24", MSBDMenuBarCopyHeight(24.0, 41.0, 24.0), 24.0);
    Expect("a copy being made (0 tall): 0 as before (the layout waits)", MSBDMenuBarCopyHeight(24.0, 0.0, 24.0), 0.0);
    Expect("a copy squashed by an animation (10 tall): its own 10, as before", MSBDMenuBarCopyHeight(24.0, 10.0, 24.0), 10.0);
    Expect("half a point over the provider's: its own, as before", MSBDMenuBarCopyHeight(24.0, 24.5, 24.0), 24.5);
    Expect("no provider read, a bar-sized copy: its own", MSBDMenuBarCopyHeight(0.0, 24.0, 20.0), 24.0);
    // the corner-swipe screenshot's placeholder status bar: the whole screen
    Expect("placeholder bar on the M1 (1194 x 834 landscape, provider 24): 24", MSBDMenuBarCopyHeight(24.0, 834.0, 24.0), 24.0);
    Expect("  ... M1 portrait (1194 tall): 24", MSBDMenuBarCopyHeight(24.0, 1194.0, 24.0), 24.0);
    Expect("  ... M1 at Medium (provider 30): 30", MSBDMenuBarCopyHeight(30.0, 834.0, 30.0), 30.0);
    Expect("placeholder bar on an iPad 6 (15.7, Home button: provider 20), landscape 768 tall: 20", MSBDMenuBarCopyHeight(20.0, 768.0, 20.0), 20.0);
    Expect("  ... portrait 1024 tall: 20", MSBDMenuBarCopyHeight(20.0, 1024.0, 20.0), 20.0);
    Expect("  ... no provider read: the iPad's own bar height known (20)", MSBDMenuBarCopyHeight(0.0, 768.0, 20.0), 20.0);
    Expect("  ... a provider value no bar has (100): the known 24", MSBDMenuBarCopyHeight(100.0, 834.0, 24.0), 24.0);
    Expect("  ... nothing known at all: its own (as before; nothing better to go by)", MSBDMenuBarCopyHeight(0.0, 834.0, 0.0), 834.0);
    // the Apple logo's ink from it (MSBDMenuBarLogoInk): a bar's, never the screen's
    Expect("logo ink, M1 placeholder at Small: 15 pt (825 before)", MSBDMenuBarLogoInk(MSBDMenuBarSmall, MSBDMenuBarCopyHeight(24.0, 834.0, 24.0), 12.0), 15.0);
    Expect("logo ink, iPad 6 placeholder at Small, landscape: 11 pt (759 before)", MSBDMenuBarLogoInk(MSBDMenuBarSmall, MSBDMenuBarCopyHeight(20.0, 768.0, 20.0), 12.0), 11.0);
    Expect("logo ink, iPad 6 placeholder at Small, portrait: 11 pt (1015 before)", MSBDMenuBarLogoInk(MSBDMenuBarSmall, MSBDMenuBarCopyHeight(20.0, 1024.0, 20.0), 12.0), 11.0);
    Expect("logo ink, M1 placeholder at Medium: 1.25 x 13.5 pt text (as the bar's)", MSBDMenuBarLogoInk(MSBDMenuBarMedium, MSBDMenuBarCopyHeight(30.0, 834.0, 30.0), 13.5), MSBDMenuBarLogoInk(MSBDMenuBarMedium, 30.0, 13.5));
    Expect("logo ink, the iPad's own bar at Small: 15 pt, as before", MSBDMenuBarLogoInk(MSBDMenuBarSmall, MSBDMenuBarCopyHeight(24.0, 24.0, 24.0), 12.0), 15.0);
    // the logo's middle: the bar's middle, at the top of the screen (the copy's middle before: 417 on the M1)
    Expect("logo centred on 12 (the M1 placeholder bar's middle, not 417)", MSBDMenuBarCopyHeight(24.0, 834.0, 24.0) / 2.0, 12.0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
