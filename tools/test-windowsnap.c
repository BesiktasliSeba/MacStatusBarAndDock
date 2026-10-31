// test-windowsnap.c -- Mac test of window snapping (statusbar/WindowSnap.h, 1.7.3 item 3), the code every engine runs when a move or a resize by
// hand ends. Desktops as on the iPads: the A12Z in landscape (1366 x 1024, menu bar 24, Dock line 941.47 -- its Stage Manager windows' bottom),
// the M1 in landscape (1194 x 834, Dock line 761.8), Menu Bar Size Large (bar 37). Stage Manager's own numbers measured on 18.5: a move snaps within
// 45 pt, a resized side within 10 (9 snapped, 10 did not); ours puts neighbours 6 pt apart (the layouts' gap; Stage Manager's is 10).
#include <stdio.h>
#include "../statusbar/WindowSnap.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.01; }
static void Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    if (near(got.origin.x, want.origin.x) && near(got.origin.y, want.origin.y) && near(got.size.width, want.size.width) && near(got.size.height, want.size.height)) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%.2f, %.2f, %.2f, %.2f}, want {%.2f, %.2f, %.2f, %.2f})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
}
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
#define MOVE(f, o, n, a) MSBDSnapFrame((f), MSBDSnapMove, (o), (n), (a), kMSBDSnapGap, kMSBDSnapMoveDistance, MIN, &why)
#define SIZE(f, how, o, n, a) MSBDSnapFrame((f), (how), (o), (n), (a), kMSBDSnapGap, kMSBDSnapResizeDistance, MIN, &why)
int main(void) {
    const CGSize MIN = CGSizeMake(320, 324);   // (WindowMinSize.h: the smallest window, title bar included)
    const CGRect a12z = CGRectMake(0, 24, 1366, 941.47 - 24);   // (under the 24 pt bar, down to the Dock line)
    const CGRect m1 = CGRectMake(0, 24, 1194, 761.8 - 24);
    MSBDSnapWhy why;
    // ---- moves (let go: within 45 pt) ----
    Frame("a lone window let go 30 pt from the left edge goes to the edge (Stage Manager's edgePadding 45)", MOVE(CGRectMake(30, 200, 600, 500), NULL, 0, a12z), CGRectMake(0, 200, 600, 500));
    Int("  ... it snapped to the desktop's edge", why.x, MSBDSnapToArea);
    Frame("  ... 46 pt away: left where it is", MOVE(CGRectMake(46, 200, 600, 500), NULL, 0, a12z), CGRectMake(46, 200, 600, 500));
    Frame("  ... exactly 45 pt away: snaps", MOVE(CGRectMake(45, 200, 600, 500), NULL, 0, a12z), CGRectMake(0, 200, 600, 500));
    Frame("a window let go 20 pt under the menu bar goes up to it (24)", MOVE(CGRectMake(300, 44, 600, 500), NULL, 0, a12z), CGRectMake(300, 24, 600, 500));
    Frame("a window let go 30 pt above the Dock line comes down onto it", MOVE(CGRectMake(300, 411.47, 600, 500), NULL, 0, a12z), CGRectMake(300, 441.47, 600, 500));
    const CGRect left = CGRectMake(0, 24, 680, 917.47);   // (the A12Z's left half: Settings, 31 Oct)
    Frame("next to a window: let go 40 pt right of the left half, it goes 6 pt from it (686)", MOVE(CGRectMake(726, 100, 500, 600), &left, 1, a12z), CGRectMake(686, 100, 500, 600));
    Int("  ... snapped next to a window", why.x, MSBDSnapToNext);
    Frame("  ... let go overlapping it by 30, the same place", MOVE(CGRectMake(650, 100, 500, 600), &left, 1, a12z), CGRectMake(686, 100, 500, 600));
    Frame("  ... a tie (the screen's right edge 40 pt off as well): the desktop's edge first", MOVE(CGRectMake(726, 100, 600, 600), &left, 1, a12z), CGRectMake(766, 100, 600, 600));
    Frame("the same side lined up: a window under the left half's left side (12 pt off) goes to it -- and to its top", MOVE(CGRectMake(12, 40, 500, 400), &left, 1, a12z), CGRectMake(0, 24, 500, 400));
    const CGRect top = CGRectMake(300, 24, 600, 400);   // (a window at the top; another let go under it)
    Frame("under a window: let go 20 pt below it, it goes 6 pt under it (430), its left side to the other's (300)", MOVE(CGRectMake(320, 444, 600, 300), &top, 1, a12z), CGRectMake(300, 430, 600, 300));
    Int("  ... y next to a window", why.y, MSBDSnapToNext);
    Int("  ... x lined up", why.x, MSBDSnapToAligned);
    const CGRect far = CGRectMake(0, 600, 300, 300);   // (low on the screen, nowhere level with a window at the top)
    Frame("a window not level with this one does not pull a side (its right side 20 pt away, 300 pt lower)", MOVE(CGRectMake(320, 30, 400, 200), &far, 1, a12z), CGRectMake(320, 24, 400, 200));
    Frame("the nearer place wins: the desktop's edge 10 pt off before a window's 24 pt off", MOVE(CGRectMake(10, 200, 400, 300), (CGRect[]){CGRectMake(440, 200, 300, 300)}, 1, a12z), CGRectMake(0, 200, 400, 300));
    // never into the menu bar, never further under the Dock, never further off the screen
    const CGRect bogus = CGRectMake(600, 0, 400, 200);   // (a frame reaching into the bar: no window has one, but a lined-up top must not follow it)
    Frame("never into the menu bar: a top lined up with a window that reaches into the bar is refused -- the bar's line instead", MOVE(CGRectMake(560, 14 + 24, 300, 300), &bogus, 1, a12z), CGRectMake(600, 24, 300, 300));
    const CGRect inBar = CGRectMake(560, 5, 400, 300);   // (a window whose top is in the bar -- 5: our clamps never leave one there, but a snap must never follow it)
    Frame("never into the menu bar: let go with its top at 10 (in the bar), a window's top 5 pt away at 5 is refused -- down to the bar's line (24)", MOVE(CGRectMake(560, 10, 300, 300), &inBar, 1, a12z), CGRectMake(560, 24, 300, 300));
    Frame("  ... a dragged-up top at 18: not to a window's top 3 pt away at 15 (in the bar), to the bar's line (24)", SIZE(CGRectMake(560, 18, 300, 400), MSBDSnapTop, (CGRect[]){CGRectMake(560, 15, 400, 300)}, 1, a12z), CGRectMake(560, 24, 300, 394));
    Frame("  ... a dragged-up top at 10 is not pulled down to a window's top in the bar (15): left for the user to bring out", SIZE(CGRectMake(560, 10, 300, 400), MSBDSnapTop, (CGRect[]){CGRectMake(560, 15, 400, 300)}, 1, a12z), CGRectMake(560, 10, 300, 400));
    const CGRect under = CGRectMake(560, 500, 400, 470);   // (a window the user put down behind the Dock: its bottom 970, under the 941.47 line)
    Frame("never further under the Dock: a bottom lined up with a window behind the Dock is refused, the Dock line instead", MOVE(CGRectMake(250, 450, 400, 500), &under, 1, a12z), CGRectMake(250, 441.47, 400, 500));
    Frame("a window already 18.5 pt under the Dock line: up onto it, never further down", MOVE(CGRectMake(250, 480, 400, 480), NULL, 0, a12z), CGRectMake(250, 461.47, 400, 480));
    Frame("never further off the screen: a window let go half off the right edge comes back no further than the edge rule allows (to the edge, 40 pt in)", MOVE(CGRectMake(806, 300, 600, 300), NULL, 0, a12z), CGRectMake(766, 300, 600, 300));
    Frame("  ... 60 pt off: left where it is", MOVE(CGRectMake(826, 300, 600, 300), NULL, 0, a12z), CGRectMake(826, 300, 600, 300));
    // ---- resizes (the dragged side within 10 pt) ----
    Frame("Stage Manager 18.5's own case: the right side 5 pt short of 6 pt from the neighbour (675 -> 680)", SIZE(CGRectMake(0, 24, 675, 917.47), MSBDSnapRight | MSBDSnapBottom, (CGRect[]){CGRectMake(686, 24, 680, 917.47)}, 1, a12z), CGRectMake(0, 24, 680, 917.47));
    Int("  ... the right side next to a window", why.x, MSBDSnapToNext);
    Int("  ... the bottom on the Dock line already: lined up there (nothing moved)", why.y, MSBDSnapToArea);
    Frame("  ... 10 pt short of the place (670): left there (18.5: 10 did not snap)", SIZE(CGRectMake(0, 24, 669.9, 917.47), MSBDSnapRight, (CGRect[]){CGRectMake(686, 24, 680, 917.47)}, 1, a12z), CGRectMake(0, 24, 669.9, 917.47));
    Frame("a resized side is not pulled 30 pt (a move's distance only for moves)", SIZE(CGRectMake(0, 24, 650, 600), MSBDSnapRight, (CGRect[]){CGRectMake(686, 24, 680, 917.47)}, 1, a12z), CGRectMake(0, 24, 650, 600));
    Frame("a bottom 8 pt above the Dock line goes down onto it", SIZE(CGRectMake(100, 100, 500, 833.47), MSBDSnapBottom, NULL, 0, a12z), CGRectMake(100, 100, 500, 841.47));
    Frame("the left corner: the left side 7 pt right of a window's left side lines up with it", SIZE(CGRectMake(307, 400, 500, 300), MSBDSnapLeft | MSBDSnapBottom, (CGRect[]){CGRectMake(300, 24, 600, 366)}, 1, a12z), CGRectMake(300, 400, 507, 300));
    Frame("  ... the same window 76 pt higher is not level with it for a resize (reach: the gap and 10): left", SIZE(CGRectMake(307, 400, 500, 300), MSBDSnapLeft | MSBDSnapBottom, (CGRect[]){CGRectMake(300, 24, 600, 300)}, 1, a12z), CGRectMake(307, 400, 500, 300));
    Frame("only the dragged sides move: the top and the other side stay", SIZE(CGRectMake(4, 30, 600, 500), MSBDSnapRight | MSBDSnapBottom, NULL, 0, a12z), CGRectMake(4, 30, 600, 500));
    Frame("never smaller than a window may be: a side that would snap to 5 pt under the minimum stays", SIZE(CGRectMake(300, 100, 325, 400), MSBDSnapLeft, (CGRect[]){CGRectMake(0, 100, 299 - 6 + 10, 400)}, 1, a12z), CGRectMake(300, 100, 325, 400));
    Frame("a dragged-up top 8 pt under the bar goes to the bar's line, never into it", SIZE(CGRectMake(100, 32, 500, 500), MSBDSnapTop, NULL, 0, a12z), CGRectMake(100, 24, 500, 508));
    // ---- the M1 (Aerial / Zetsu / MilkyWay4 desktops) and Menu Bar Size Large ----
    const CGRect m1half = CGRectMake(0, 24, 594, 737.8);
    Frame("M1: a window let go 25 pt right of the left half goes 6 pt from it (600)", MOVE(CGRectMake(619, 200, 500, 400), &m1half, 1, m1), CGRectMake(600, 200, 500, 400));
    const CGRect large = CGRectMake(0, 37, 1194, 761.8 - 37);
    Frame("Menu Bar Size Large: the top goes to the 37 pt bar's line, not 24", MOVE(CGRectMake(300, 60, 500, 400), NULL, 0, large), CGRectMake(300, 37, 500, 400));
    Frame("  ... a window let go at 24 (in the large bar) is taken down to 37 -- never left in the bar by a snap", MOVE(CGRectMake(300, 24, 500, 400), NULL, 0, large), CGRectMake(300, 37, 500, 400));
    // ---- 16's resize step: the window being resized, found by its held sides (SMResizeAnchor.h DMSMRASnapEnd) ----
    const CGRect startCard = CGRectMake(100, 120, 500, 400);
    Int("the window whose held sides are where the drag began is the one being resized (its right side dragged 60 pt)", MSBDSnapHeldSidesMatch(CGRectMake(100, 120, 560, 400), startCard, MSBDSnapRight), 1);
    Int("  ... a bottom-left corner: the right side and the top held", MSBDSnapHeldSidesMatch(CGRectMake(40, 120, 560, 470), startCard, MSBDSnapLeft | MSBDSnapBottom), 1);
    Int("  ... a held side 1.5 pt off: another window", MSBDSnapHeldSidesMatch(CGRectMake(100, 121.5, 560, 400), startCard, MSBDSnapRight), 0);
    Int("  ... a window only level with it (its left side elsewhere): not it", MSBDSnapHeldSidesMatch(CGRectMake(686, 120, 500, 400), startCard, MSBDSnapRight), 0);
    Int("  ... the same frame in another screen's points (a TV's window at its own place): not it", MSBDSnapHeldSidesMatch(CGRectMake(1100, 300, 500, 400), startCard, MSBDSnapLeft | MSBDSnapTop), 0);
    // ---- nothing to do ----
    Frame("far from every edge and window: as it was", MOVE(CGRectMake(400, 300, 400, 300), &left, 1, a12z), CGRectMake(400, 300, 400, 300));
    Int("  ... nothing snapped", why.x + why.y, 0);
    Frame("no area known: as it was", MOVE(CGRectMake(10, 30, 400, 300), NULL, 0, CGRectNull), CGRectMake(10, 30, 400, 300));
    Frame("an empty window frame: as it was", MOVE(CGRectMake(10, 30, 0, 0), NULL, 0, a12z), CGRectMake(10, 30, 0, 0));
    printf("test-windowsnap: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
