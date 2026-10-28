// Mac test of statusbar/DesktopRename.h (the code Desktop.h's rename runs). Levels as measured on the iPad 2 (16.7.7, 1.6.0 winlist): the Home
// Screen's window -2, Stage Manager's switcher window 5, the Dock 25, the status bar window 999, the engines' window layer 1033 (kMilkyWayFrontLevel),
// our native layer 6 / 1034 while Finder is active (-1.5 while not), our menu window 1040, the Cover Sheet 1050, Aerial's keyboard window 1052.
// UIKit puts the text effects window one level and the keyboard's window two levels above the window being typed in. Run by test-deskrename.sh.
#include <stdio.h>
#include "../statusbar/DesktopRename.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static const CGFloat kMenu = 1040.0, kDock = 25.0;
// every keyboard window above all of these and under the menu window
static int keyboardClear(CGFloat host, const CGFloat *levels, int n) {
    for (int k = 1; k <= 2; k++) {
        CGFloat kb = host + k;
        if (kb >= kMenu) return 0;
        for (int i = 0; i < n; i++) if (levels[i] < kMenu && kb <= levels[i]) return 0;
    }
    return 1;
}
static int same(CGRect a, CGRect b) { return CGRectEqualToRect(a, b); }

int main(void) {
    // Stage Manager: the switcher window 5, the Dock 25, Finder's layer behind (-1.5): above the Dock
    CGFloat sm[] = { 5.0, kDock, -1.5 };
    CGFloat smHost = MSBDRenameHostLevel(sm, 3, kMenu);
    CHECK(smHost == 26.0, "Stage Manager: just above the Dock (%.1f)", smHost);
    CHECK(keyboardClear(smHost, sm, 3), "Stage Manager: both keyboard windows above the windows and the Dock, under the menu window");
    // the old way: typed in the Home Screen's window, the keyboard at -1 / 0 -- under the windows and the Dock
    CHECK(!keyboardClear(-2.0, sm, 3), "the Home Screen's window (-2): the keyboard under them (the bug)");
    // Stage Manager with Finder active (its layer just above the apps, 6)
    CGFloat smFinder[] = { 5.0, kDock, 6.0 };
    CHECK(MSBDRenameHostLevel(smFinder, 3, kMenu) == 26.0, "Stage Manager, Finder active: still just above the Dock");
    // Aerial / MilkyWay / Zetsu in front: the window layer 1033 over the Dock
    CGFloat aerial[] = { 5.0, kDock, 1033.0 };
    CGFloat aHost = MSBDRenameHostLevel(aerial, 3, kMenu);
    CHECK(aHost == 1034.0, "Aerial: just above the window layer (%.1f)", aHost);
    CHECK(keyboardClear(aHost, aerial, 3), "Aerial: the keyboard above the windows, under the menu window");
    // Aerial with Finder active over it (1034)
    CGFloat aerialFinder[] = { 5.0, kDock, 1033.0, 1034.0 };
    CGFloat afHost = MSBDRenameHostLevel(aerialFinder, 4, kMenu);
    CHECK(afHost == 1035.0 && keyboardClear(afHost, aerialFinder, 4), "Aerial + Finder active: above both (%.1f)", afHost);
    // Zetsu: one window per app, at its own level (here two)
    CGFloat zetsu[] = { 5.0, kDock, 1033.0, 1033.0 };
    CHECK(MSBDRenameHostLevel(zetsu, 4, kMenu) == 1034.0, "Zetsu: above its windows");
    // windows behind a full-screen app (the layer at -0.5): the Dock is the highest
    CGFloat behind[] = { 5.0, kDock, -0.5 };
    CHECK(MSBDRenameHostLevel(behind, 3, kMenu) == 26.0, "windows behind: just above the Dock");
    // what is at or above the menu window does not count: our menu window, the Cover Sheet, Aerial's keyboard window
    CGFloat high[] = { 5.0, kDock, 1033.0, 1040.0, 1050.0, 1052.0 };
    CHECK(MSBDRenameHostLevel(high, 6, kMenu) == 1034.0, "the menu window, the Cover Sheet and an app's keyboard window are not counted");
    // never so high that the keyboard reaches the menu window
    CGFloat top[] = { 1038.5 };
    CGFloat tHost = MSBDRenameHostLevel(top, 1, kMenu);
    CHECK(tHost == 1037.0 && tHost + 2.0 < kMenu, "capped under the menu window (%.1f)", tHost);
    // nothing to be above (no Dock): just above the Home Screen
    CHECK(MSBDRenameHostLevel(NULL, 0, kMenu) == -1.0, "nothing else: just above the Home Screen");
    // the field: under its icon, or just above a keyboard that would cover it (iPad 2 landscape: the docked keyboard {0, 360, 1024, 408})
    CGRect kb = CGRectMake(0, 360, 1024, 408);
    CGRect low = CGRectMake(442, 520, 140, 19), high2 = CGRectMake(442, 120, 140, 19);
    CHECK(same(MSBDRenameFieldFrame(low, kb), CGRectMake(442, 333, 140, 19)), "a name low on the desktop goes 8 points above the keyboard");
    CHECK(same(MSBDRenameFieldFrame(high2, kb), high2), "a name above the keyboard stays under its icon");
    CHECK(same(MSBDRenameFieldFrame(CGRectMake(442, 335, 140, 19), kb), CGRectMake(442, 333, 140, 19)), "less than 8 points above it: moved up too");
    CHECK(same(MSBDRenameFieldFrame(low, CGRectZero), low), "no keyboard (a hardware keyboard's bar is not one): under its icon");
    printf("test-deskrename: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
