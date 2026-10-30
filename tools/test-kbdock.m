// Mac test of statusbar/KeyboardDock.h (the code Desktop.h's keyboard watch runs). Frames are the ones iPadOS announced to SpringBoard on the
// A12Z (iPadOS 18.5, landscape 1366 x 1024; 1.6.0 logs) and the iPad 2 (16, landscape: {360, 0, 408, 1024} in the fixed space); g is what UIKit
// turns f into (the fixed portrait space to the interface's), given as logged. Run by test-kbdock.sh.
#include <stdio.h>
#include "../statusbar/KeyboardDock.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static bool same(CGRect a, CGRect b) { return CGRectEqualToRect(a, b); }

int main(void) {
    CGSize land = CGSizeMake(1366, 1024), port = CGSizeMake(1024, 1366), ipad2 = CGSizeMake(1024, 768);
    // A12Z 18.5, landscape: the full keyboard (fixed space) and its interface frame
    CGRect fullF = CGRectMake(0, 0, 498, 1366), fullG = CGRectMake(0, 526, 1366, 498);
    CHECK(MSBDKeyboardNoteDocked(fullF, fullG, land), "full keyboard (fixed + interface) is docked");
    CHECK(same(MSBDKeyboardNoteOnScreen(fullF, fullG, land), fullG), "full keyboard: the interface frame is the one on the screen");
    // the hardware keyboard's bar (interface space) and the converted one that lies off the screen
    CGRect barF = CGRectMake(0, 952.5, 1366, 71.5), barG = CGRectMake(952.5, -342, 71.5, 1366);
    CHECK(!MSBDKeyboardNoteDocked(barF, barG, land), "the bar is not docked");
    CHECK(same(MSBDKeyboardNoteOnScreen(barF, barG, land), barF), "the bar's frame on the screen is f");
    // 18's "Show Keyboard": a 3 pt keyboard first
    CGRect threeF = CGRectMake(0, 1021, 1366, 3), threeG = CGRectMake(1021, -342, 3, 1366);
    CHECK(!MSBDKeyboardNoteDocked(threeF, threeG, land), "the 3 pt keyboard is not docked");
    CHECK(same(MSBDKeyboardNoteOnScreen(threeF, threeG, land), threeF), "the 3 pt keyboard is on the screen (as f)");
    // Esc ending a search: a frame change to below the screen, then the zero frame
    CGRect goingF = CGRectMake(0, 1024, 1366, 440), goingG = CGRectMake(1024, -342, 440, 1366);
    CHECK(!MSBDKeyboardNoteDocked(goingF, goingG, land), "a keyboard going below the screen is not docked (it counted for 3 ms in d5)");
    CHECK(same(MSBDKeyboardNoteOnScreen(goingF, goingG, land), CGRectZero), "a keyboard going below the screen has no frame on it");
    CGRect goneF = CGRectMake(0, 1024, 0, 0), goneG = CGRectMake(1024, 1024, 0, 0);
    CHECK(!MSBDKeyboardNoteDocked(goneF, goneG, land), "the zero frame is not docked");
    CHECK(same(MSBDKeyboardNoteOnScreen(goneF, goneG, land), CGRectZero), "the zero frame has no frame on the screen");
    // a keyboard half way down (animating): docked only while more than 150 pt of it shows
    CHECK(MSBDKeyboardRectDocked(CGRectMake(0, 800, 1366, 440), land), "224 pt of a keyboard on the screen: docked");
    CHECK(!MSBDKeyboardRectDocked(CGRectMake(0, 900, 1366, 440), land), "124 pt of a keyboard on the screen: not docked");
    // floating keyboard (not the whole width) and a split one: never docked
    CHECK(!MSBDKeyboardRectDocked(CGRectMake(400, 600, 320, 260), land), "a floating keyboard is not docked");
    CHECK(!MSBDKeyboardRectDocked(CGRectMake(0, 700, 683, 324), land), "half a split keyboard is not docked");
    // portrait (A12Z): a docked keyboard of 360 pt
    CHECK(MSBDKeyboardNoteDocked(CGRectMake(0, 1006, 1024, 360), CGRectMake(0, 1006, 1024, 360), port), "portrait docked keyboard");
    // iPad 2 (16), landscape: the fixed-space frame {360, 0, 408, 1024} (Desktop.h's note) turns into {0, 360, 1024, 408}
    CHECK(MSBDKeyboardNoteDocked(CGRectMake(360, 0, 408, 1024), CGRectMake(0, 360, 1024, 408), ipad2), "iPad 2 landscape keyboard (fixed space) is docked");
    CHECK(same(MSBDKeyboardNoteOnScreen(CGRectMake(360, 0, 408, 1024), CGRectMake(0, 360, 1024, 408), ipad2), CGRectMake(0, 360, 1024, 408)), "iPad 2: the interface frame is on the screen");
    // the decision
    CHECK(!MSBDKeyboardDockUnder(false, true, true, true, 0.0), "not our field: the Dock stays");
    CHECK(MSBDKeyboardDockUnder(true, true, true, false, 9.0), "the drawn keyboard is docked: under (no notification said so: 18's Show Keyboard)");
    CHECK(MSBDKeyboardDockUnder(true, false, true, true, 0.2), "announced docked a moment ago, not drawn yet: under");
    CHECK(!MSBDKeyboardDockUnder(true, false, true, true, 3.0), "announced docked long ago, the drawn keyboard is the bar now: back (shrunk without a notification)");
    CHECK(MSBDKeyboardDockUnder(true, false, false, true, 3.0), "announced docked, nothing drawn where we look: the announcement decides");
    CHECK(!MSBDKeyboardDockUnder(true, false, true, false, 0.2), "announced the bar: back");
    // the Dock's floor and our own field's input bar (M1 15.6.1, 1.6.0: levels measured with winlist)
    CHECK(MSBDOwnBarUnderDockFloor(true, 69, 1004, kMSBDDockFloorLevel), "Zetsu: Finder's search bar in keyboard windows at 1004 / 1005: the floor steps aside");
    CHECK(MSBDOwnBarUnderDockFloor(true, 71.5, 7, kMSBDDockFloorLevel), "an 18 bar (71.5 pt) under the floor: steps aside");
    CHECK(!MSBDOwnBarUnderDockFloor(true, 69, 1035, kMSBDDockFloorLevel), "Aerial / MilkyWay4: Finder's keyboard windows at 1035, above the floor: nothing changes");
    CHECK(!MSBDOwnBarUnderDockFloor(true, 69, 1036, kMSBDDockFloorLevel), "a name typed on the desktop over a raised Dock (rename window 1035): nothing changes");
    CHECK(!MSBDOwnBarUnderDockFloor(true, 69, 1034, kMSBDDockFloorLevel), "keyboard windows at the floor's own level: not under it");
    CHECK(!MSBDOwnBarUnderDockFloor(true, 3, 1004, kMSBDDockFloorLevel), "18's 3 pt placeholder is no bar");
    CHECK(!MSBDOwnBarUnderDockFloor(true, 0, -1000, kMSBDDockFloorLevel), "no bar drawn: nothing changes");
    CHECK(!MSBDOwnBarUnderDockFloor(true, 428, 1004, kMSBDDockFloorLevel), "a full keyboard is the on-screen keyboard's rule, not this one");
    CHECK(!MSBDOwnBarUnderDockFloor(false, 69, 1004, kMSBDDockFloorLevel), "no hardware keyboard: no input bar");
    // the tidy pill's measure (M1 15.6.1, 1.7.0): Spotlight's full keyboard is drawn in SpringBoard's hosted keyboard window, unseen by its own hosts
    CHECK(MSBDKeyboardPillMeasure(0, 0) == 0, "no keyboard anywhere: the pill is alone");
    CHECK(MSBDKeyboardPillMeasure(0, 398) == 398, "Spotlight's full keyboard (another process): counted, the window is not tidied");
    CHECK(MSBDKeyboardPillMeasure(0, 55) == 0, "another process's input bar or pill only: still the pill alone");
    CHECK(MSBDKeyboardPillMeasure(69, 0) == 69, "SpringBoard's own field's bar: as before");
    CHECK(MSBDKeyboardPillMeasure(420, 398) == 420, "both: the taller one");
    printf("test-kbdock: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
