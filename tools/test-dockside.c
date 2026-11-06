// test-dockside.c -- Mac test of common/DockSide.h (Settings > Dock > Position, 1.8.2): the side from the stored position and the screen's shape, the turned
// Dock's view, its length under the menu bar, the strip, the desktop, a window let go under the Dock, an icon's touch share, the running dot, the pointer's look.
// Numbers as read on the A12Z (18.5, landscape 1366 x 1024) and the iPad 2 (16.7.7, landscape 1024 x 768). Run by test-dockside.sh.
#include <stdio.h>
#include "../common/DockSide.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.01; }
static void Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    if (near(got.origin.x, want.origin.x) && near(got.origin.y, want.origin.y) && near(got.size.width, want.size.width) && near(got.size.height, want.size.height)) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%.2f, %.2f, %.2f, %.2f}, want {%.2f, %.2f, %.2f, %.2f})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
}
static void Num(const char *what, double got, double want) { checks++; if (near(got, want)) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %.3f, want %.3f)\n", what, got, want); } }
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
static void Pt(const char *what, CGPoint got, CGPoint want) { checks++; if (near(got.x, want.x) && near(got.y, want.y)) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got {%.2f, %.2f}, want {%.2f, %.2f})\n", what, got.x, got.y, want.x, want.y); } }
int main(void) {
    CGSize a12z = CGSizeMake(1366, 1024), ipad2 = CGSizeMake(1024, 768);
    // ---- the stored position, and the side for a screen ----
    Int("position: never set is the bottom", MSBDDockPositionFromString(NULL), MSBDDockBottom);
    Int("  ... \"bottom\" too", MSBDDockPositionFromString("bottom"), MSBDDockBottom);
    Int("  ... and anything unknown", MSBDDockPositionFromString("LEFT"), MSBDDockBottom);
    Int("  ... \"left\"", MSBDDockPositionFromString("left"), MSBDDockLeft);
    Int("  ... \"right\"", MSBDDockPositionFromString("right"), MSBDDockRight);
    Int("Left in landscape: the left", MSBDDockSideFor(MSBDDockLeft, 1366, 1024), MSBDDockLeft);
    Int("Right in landscape: the right", MSBDDockSideFor(MSBDDockRight, 1366, 1024), MSBDDockRight);
    Int("Left in portrait: the bottom", MSBDDockSideFor(MSBDDockLeft, 1024, 1366), MSBDDockBottom);
    Int("Right in portrait: the bottom", MSBDDockSideFor(MSBDDockRight, 1024, 1366), MSBDDockBottom);
    Int("the bottom in landscape: the bottom", MSBDDockSideFor(MSBDDockBottom, 1366, 1024), MSBDDockBottom);
    Int("a nonsense position: the bottom", MSBDDockSideFor(7, 1366, 1024), MSBDDockBottom);
    // ---- the Dock's view, turned about the screen's centre: its bottom on the screen's side, its x down the screen on both sides ----
    CGPoint bottomMiddle = CGPointMake(0, 683), start = CGPointMake(-512, 683);   // (the view as wide as the short side, from its centre)
    Pt("Left: the view's bottom is the screen's left edge", CGPointApplyAffineTransform(bottomMiddle, MSBDDockSideHostTransform(MSBDDockLeft)), CGPointMake(-683, 0));
    Pt("  ... its x runs down the screen (Finder on top)", CGPointApplyAffineTransform(start, MSBDDockSideHostTransform(MSBDDockLeft)), CGPointMake(-683, -512));
    Pt("Right: the view's bottom is the screen's right edge", CGPointApplyAffineTransform(bottomMiddle, MSBDDockSideHostTransform(MSBDDockRight)), CGPointMake(683, 0));
    Pt("  ... its x runs down the screen too (Finder on top, mirrored, not the other way round)", CGPointApplyAffineTransform(start, MSBDDockSideHostTransform(MSBDDockRight)), CGPointMake(683, -512));
    Int("the bottom: no turn", CGAffineTransformIsIdentity(MSBDDockSideHostTransform(MSBDDockBottom)), 1);
    Int("an icon's content stands upright at the left (the view's turn undone)", CGAffineTransformIsIdentity(CGAffineTransformConcat(MSBDDockSideIconTransform(MSBDDockLeft), MSBDDockSideHostTransform(MSBDDockLeft))), 1);
    Int("  ... and at the right", CGAffineTransformIsIdentity(CGAffineTransformConcat(MSBDDockSideIconTransform(MSBDDockRight), MSBDDockSideHostTransform(MSBDDockRight))), 1);
    Int("  ... the bottom: nothing to undo", CGAffineTransformIsIdentity(MSBDDockSideIconTransform(MSBDDockBottom)), 1);
    // ---- an icon's turn is ours alone (the 1.8.2 engines check, M1: Atria's icon scale, 0.819, lies in the same layer value) ----
    Int("an icon never turned, the Dock at the bottom: nothing written (Atria's Home Screen scale stays)", MSBDDockSideIconTurnStep(false, false, MSBDDockBottom), MSBDIconTurnNothing);
    Int("  ... at a side, a Home Screen icon (not the side Dock's: asked with no side): nothing written", MSBDDockSideIconTurnStep(false, false, 0), MSBDIconTurnNothing);
    Int("a side Dock icon: turned on top of what it has (Atria's Dock scale kept under the turn)", MSBDDockSideIconTurnStep(false, false, MSBDDockRight), MSBDIconTurnApply);
    Int("  ... what lies under the turn: what it has now", MSBDDockSideIconTurnUnderKept(false, false), 0);
    Int("  ... turned again (a layout, the other side): on the kept value, never a turn on a turn", MSBDDockSideIconTurnUnderKept(true, true), 1);
    Int("  ... its owner set another value since (Atria laid it out again): the turn on that one", MSBDDockSideIconTurnUnderKept(true, false), 0);
    Int("back at the bottom, our turn still there: what was under it given back exactly", MSBDDockSideIconTurnStep(true, true, MSBDDockBottom), MSBDIconTurnGiveBack);
    Int("  ... its owner set another since: theirs stays, nothing written, our record goes", MSBDDockSideIconTurnStep(true, false, MSBDDockBottom), MSBDIconTurnForget);
    Int("  ... an icon we turned that left the side Dock (dragged out): given back the same way", MSBDDockSideIconTurnStep(true, true, 0), MSBDIconTurnGiveBack);
    Int("  ... the left side too", MSBDDockSideIconTurnStep(false, false, MSBDDockLeft), MSBDIconTurnApply);
    // ---- its length: kept off the menu bar ----
    Num("the A12Z, a 24 pt bar: 1024 - 24 - 12 for the Dock", MSBDDockSideLength(1024, 24), 988);
    Num("the iPad 2, a 20 pt bar: 768 - 20 - 12", MSBDDockSideLength(768, 20), 736);
    Num("no bar: the height less the two margins", MSBDDockSideLength(768, 0), 756);
    Num("  ... a nonsense negative bar counts as none", MSBDDockSideLength(768, -3), 756);
    Num("a Dock in the middle of the room under the bar", MSBDDockSidePlatterX(1024, 24, 600), 24 + 200);
    Num("  ... as long as the room can take: the margin", MSBDDockSidePlatterX(1024, 24, 988), 24 + 6);
    // ---- the strip, read from the platter as drawn ----
    Num("Right: from the platter's inner edge to the screen's", MSBDDockSideStripOf(CGRectMake(1266, 100, 94, 800), a12z, MSBDDockRight), 100);
    Num("Left: to the platter's inner edge", MSBDDockSideStripOf(CGRectMake(6, 100, 94, 800), a12z, MSBDDockLeft), 100);
    Num("a Dock away, off the screen at the right: no strip", MSBDDockSideStripOf(CGRectMake(1400, 100, 94, 800), a12z, MSBDDockRight), -1);
    Num("  ... at the left", MSBDDockSideStripOf(CGRectMake(-100, 100, 94, 800), a12z, MSBDDockLeft), -1);
    Num("the other shape's platter (wide, the bottom's): no strip", MSBDDockSideStripOf(CGRectMake(200, 930, 900, 94), a12z, MSBDDockRight), -1);
    Num("  ... a nonsense thick one: none", MSBDDockSideStripOf(CGRectMake(700, 0, 640, 1000), a12z, MSBDDockRight), -1);
    Num("an empty rect: none", MSBDDockSideStripOf(CGRectZero, a12z, MSBDDockRight), -1);
    Num("the bottom: none", MSBDDockSideStripOf(CGRectMake(6, 100, 94, 800), a12z, MSBDDockBottom), -1);
    // (regression 1.8.2.1 F1, the iPad 2's Dock as drawn: 50.2 pt thick, KT's Gap to Screen Edge 4.3 pt; Left x 4.3..54.5, Right x 969.5..1019.7)
    CGRect ipad2AtLeft = CGRectMake(4.3, 29.5, 50.2, 729), ipad2AtRight = CGRectMake(969.5, 29.5, 50.2, 729);
    Num("the iPad 2's Dock at the left: its strip", MSBDDockSideStripOf(ipad2AtLeft, ipad2, MSBDDockLeft), 54.5);
    Num("  ... at the right", MSBDDockSideStripOf(ipad2AtRight, ipad2, MSBDDockRight), 54.5);
    Num("Left -> Right, the Left strip read with the Dock already at the right (the Dock part moved it first): none, not a 1019.7 pt strip", MSBDDockSideStripOf(ipad2AtRight, ipad2, MSBDDockLeft), -1);
    Num("  ... Right -> Left the same", MSBDDockSideStripOf(ipad2AtLeft, ipad2, MSBDDockRight), -1);
    Num("  ... the A12Z's Dock at the right read for the left: none", MSBDDockSideStripOf(CGRectMake(1266, 100, 94, 800), a12z, MSBDDockLeft), -1);
    Num("  ... a Dock exactly in the middle is at no side: none", MSBDDockSideStripOf(CGRectMake(486.9, 29.5, 50.2, 729), ipad2, MSBDDockLeft), -1);
    Num("the largest Gap to Screen Edge (40 pt): still the left's", MSBDDockSideStripOf(CGRectMake(40, 29.5, 50.2, 729), ipad2, MSBDDockLeft), 90.2);
    Num("  ... and the right's", MSBDDockSideStripOf(CGRectMake(933.8, 29.5, 50.2, 729), ipad2, MSBDDockRight), 90.2);
    Frame("  ... so the old desktop at that read is the strip as last seen at the left (the iPad 2's {56.48, 20, 967.52, 748}), not 200 pt past the right edge",
        MSBDDockSideDesktop(ipad2, MSBDDockLeft, 54.5, 20), CGRectMake(56.5, 20, 967.5, 748));
    // ---- the desktop ----
    Frame("the Dock at the right: to the screen's bottom edge, the strip and the gap kept out at the right", MSBDDockSideDesktop(a12z, MSBDDockRight, 100, 24), CGRectMake(0, 24, 1264, 1000));
    Frame("the Dock at the left: the same at the left", MSBDDockSideDesktop(a12z, MSBDDockLeft, 100, 24), CGRectMake(102, 24, 1264, 1000));
    Frame("the iPad 2's right side", MSBDDockSideDesktop(ipad2, MSBDDockRight, 70, 20), CGRectMake(0, 20, 952, 748));
    Frame("a nonsense negative strip: only the gap", MSBDDockSideDesktop(ipad2, MSBDDockLeft, -5, 20), CGRectMake(2, 20, 1022, 748));
    // ---- a window let go ----
    CGRect right = MSBDDockSideDesktop(a12z, MSBDDockRight, 100, 24), left = MSBDDockSideDesktop(a12z, MSBDDockLeft, 100, 24);
    Frame("inside the desktop: where it is", MSBDDockSideKeepOut(CGRectMake(100, 100, 600, 400), right, MSBDDockKeepMove), CGRectMake(100, 100, 600, 400));
    Frame("moved under the Dock at the right: pulled out, its size kept", MSBDDockSideKeepOut(CGRectMake(1000, 100, 600, 400), right, MSBDDockKeepMove), CGRectMake(664, 100, 600, 400));
    Frame("moved under the Dock at the left: the same", MSBDDockSideKeepOut(CGRectMake(40, 100, 600, 400), left, MSBDDockKeepMove), CGRectMake(102, 100, 600, 400));
    Frame("past the bottom edge: back up", MSBDDockSideKeepOut(CGRectMake(100, 800, 600, 400), right, MSBDDockKeepMove), CGRectMake(100, 624, 600, 400));
    Frame("above the top limit: back down", MSBDDockSideKeepOut(CGRectMake(100, -30, 600, 400), right, MSBDDockKeepMove), CGRectMake(100, 24, 600, 400));
    Frame("a window bigger than the desktop: as big as it, the lights reachable", MSBDDockSideKeepOut(CGRectMake(-50, -50, 2000, 2000), left, MSBDDockKeepMove), left);
    Frame("its right side resized under the Dock: that side stops, its left stays", MSBDDockSideKeepOut(CGRectMake(800, 100, 560, 400), right, MSBDDockKeepRight), CGRectMake(800, 100, 464, 400));
    Frame("its left side resized under the Dock at the left: that side stops, its right stays", MSBDDockSideKeepOut(CGRectMake(40, 100, 560, 400), left, MSBDDockKeepLeft), CGRectMake(102, 100, 498, 400));
    Frame("its bottom side past the screen: stops at the bottom, its top stays", MSBDDockSideKeepOut(CGRectMake(100, 700, 600, 500), right, MSBDDockKeepBottom), CGRectMake(100, 700, 600, 324));
    Frame("a corner: both", MSBDDockSideKeepOut(CGRectMake(800, 700, 560, 500), right, MSBDDockKeepRight | MSBDDockKeepBottom), CGRectMake(800, 700, 464, 324));
    Int("a null window: as it was", CGRectIsNull(MSBDDockSideKeepOut(CGRectNull, right, MSBDDockKeepMove)), 1);
    // ---- an icon's touch share ----
    CGRect iconView = CGRectMake(0, 0, 76, 76);   // (the iPad 2's side Dock: views of 76 pt, 37 pt apart)
    Int("a touch on the middle of the icon: its own", MSBDDockIconTakesTouch(CGPointMake(38, 38), iconView, 37), 1);
    Int("  ... at the edge of its share", MSBDDockIconTakesTouch(CGPointMake(38 + 18.5, 38), iconView, 37), 1);
    Int("  ... past it: its neighbour's", MSBDDockIconTakesTouch(CGPointMake(38 + 20, 38), iconView, 37), 0);
    Int("  ... on the other side", MSBDDockIconTakesTouch(CGPointMake(38 - 20, 38), iconView, 37), 0);
    Int("  ... only along the Dock: across it the whole view", MSBDDockIconTakesTouch(CGPointMake(38, 2), iconView, 37), 1);
    Int("no step measured yet: the whole view", MSBDDockIconTakesTouch(CGPointMake(70, 38), iconView, 0), 1);
    // ---- the running dot ----
    Frame("the right: beside the picture on the screen's edge side, level with its middle", MSBDDockSideDotFrame(MSBDDockRight, 60, 60, 62, 4), CGRectMake(62, 28, 4, 4));
    Frame("the left: the same on the other side", MSBDDockSideDotFrame(MSBDDockLeft, 60, 60, 62, 4), CGRectMake(-6, 28, 4, 4));
    // ---- the pointer on the screen ----
    CGSize nat = CGSizeMake(1024, 1366);
    Pt("landscape, Home at the right (3): native (0, 0)", MSBDDockPointerOnScreen(CGPointMake(0, 0), 3, nat), CGPointMake(0, 1024));
    Pt("  ... native (1024, 1366): the top right", MSBDDockPointerOnScreen(CGPointMake(1024, 1366), 3, nat), CGPointMake(1366, 0));
    Pt("landscape, Home at the left (4): native (0, 0)", MSBDDockPointerOnScreen(CGPointMake(0, 0), 4, nat), CGPointMake(1366, 0));
    Pt("  ... native (1024, 1366)", MSBDDockPointerOnScreen(CGPointMake(1024, 1366), 4, nat), CGPointMake(0, 1024));
    Pt("upside down (2)", MSBDDockPointerOnScreen(CGPointMake(10, 20), 2, nat), CGPointMake(1014, 1346));
    Pt("portrait (1): as it is", MSBDDockPointerOnScreen(CGPointMake(10, 20), 1, nat), CGPointMake(10, 20));
    // ---- the pointer's look ----
    MSBDDockPointerState st = {0};
    CGPoint at = CGPointMake(1366, 500), near_ = CGPointMake(1300, 500), far_ = CGPointMake(600, 500);
    Int("far from the side, the Dock away: nothing", MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, false, true, false, 80, 0, true), MSBDDockPointerNothing);
    Int("arrives at the side: the Dock comes out", MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, false, true, false, 80, 1, true), MSBDDockPointerComeOut);
    Int("  ... held there: not asked twice", MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, false, true, false, 80, 1.1, true), MSBDDockPointerNothing);
    Int("  ... out, the pointer still there: stays", MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, true, true, false, 80, 1.2, true), MSBDDockPointerNothing);
    Int("  ... on the Dock (within 1.5 of its height): stays", MSBDDockPointerStep(&st, MSBDDockRight, near_, a12z, true, true, false, 80, 1.3, true), MSBDDockPointerNothing);
    Int("  ... a menu holds it, the pointer far: stays", MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, true, 80, 1.4, true), MSBDDockPointerNothing);
    Int("  ... the pointer has left: it goes", MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, false, 80, 1.5, true), MSBDDockPointerGoAway);
    Int("  ... once", MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, false, 80, 1.6, true), MSBDDockPointerNothing);
    memset(&st, 0, sizeof st);
    Int("Apple's conditions say no (Lock Screen, Control Center...): it doesn't come", MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, false, false, false, 80, 2, true), MSBDDockPointerNothing);
    Int("  ... and an app coming up with the pointer left there doesn't bring it", MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, false, true, false, 80, 2.1, true), MSBDDockPointerNothing);
    memset(&st, 0, sizeof st);
    Int("a Dock brought by a finger's swipe: the pointer far doesn't send it away", MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, false, 80, 3, true), MSBDDockPointerNothing);
    memset(&st, 0, sizeof st);
    Int("the top corner is Control Center's: no Dock", MSBDDockPointerStep(&st, MSBDDockRight, CGPointMake(1366, 20), a12z, false, true, false, 80, 4, true), MSBDDockPointerNothing);
    memset(&st, 0, sizeof st);
    Int("the left side, for a Dock on the left: it comes", MSBDDockPointerStep(&st, MSBDDockLeft, CGPointMake(0, 500), a12z, false, true, false, 80, 5, true), MSBDDockPointerComeOut);
    Int("  ... and goes when the pointer has left to the right", MSBDDockPointerStep(&st, MSBDDockLeft, CGPointMake(300, 500), a12z, true, true, false, 80, 5.2, true), MSBDDockPointerGoAway);
    memset(&st, 0, sizeof st);
    Int("the other side's edge: nothing", MSBDDockPointerStep(&st, MSBDDockLeft, at, a12z, false, true, false, 80, 6, true), MSBDDockPointerNothing);
    memset(&st, 0, sizeof st);
    Int("the Dock at the bottom: nothing, never", MSBDDockPointerStep(&st, MSBDDockBottom, at, a12z, false, true, false, 80, 7, true), MSBDDockPointerNothing);
    MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, false, true, false, 80, 8, true);
    Int("  ... a position with no number (no pointer): nothing", MSBDDockPointerStep(&st, MSBDDockRight, CGPointMake(NAN, NAN), a12z, false, true, false, 80, 8.1, true), MSBDDockPointerNothing);
    Int("no state: nothing", MSBDDockPointerStep(NULL, MSBDDockRight, at, a12z, false, true, false, 80, 9, true), MSBDDockPointerNothing);
    // ---- the pointer's Dock, over the app it came out over (code review 1.8.2, 2) ----
    memset(&st, 0, sizeof st);
    Int("out over a full-screen app by the pointer", MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, false, true, false, 80, 10, true), MSBDDockPointerComeOut);
    Int("  ... Cmd-H, or an app opened as a window: another one in front, the Dock stays out (the Home Screen's, the desktop's)", MSBDDockPointerStep(&st, MSBDDockRight, near_, a12z, true, true, false, 80, 10.2, false), MSBDDockPointerNothing);
    Int("  ... no longer the pointer's", st.byPointer, 0);
    Int("  ... the pointer far then: it stays, never sent away from the Home Screen or the desktop", MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, false, 80, 10.4, true), MSBDDockPointerNothing);
    memset(&st, 0, sizeof st);
    MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, false, true, false, 80, 11, true);
    Int("the same app still in front: the pointer far sends it away, as before", MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, false, 80, 11.3, true), MSBDDockPointerGoAway);
    memset(&st, 0, sizeof st);
    MSBDDockPointerStep(&st, MSBDDockRight, at, a12z, false, true, false, 80, 12, true);
    Int("  ... another app in front while a menu holds the Dock: still not the pointer's once the menu goes", (MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, true, 80, 12.2, false), MSBDDockPointerStep(&st, MSBDDockRight, far_, a12z, true, true, false, 80, 12.4, true)), MSBDDockPointerNothing);
    // ---- a Position change, for the screen as it is (code review 1.8.2, 5) ----
    Int("portrait, Bottom to Left: nothing moves (the Dock stays at the bottom there)", MSBDDockSideMoved(MSBDDockBottom, MSBDDockLeft, 1024, 1366), 0);
    Int("  ... Left to Right in portrait: nothing", MSBDDockSideMoved(MSBDDockLeft, MSBDDockRight, 1024, 1366), 0);
    Int("  ... Right to Bottom in portrait: nothing", MSBDDockSideMoved(MSBDDockRight, MSBDDockBottom, 834, 1194), 0);
    Int("landscape, Bottom to Left: moved", MSBDDockSideMoved(MSBDDockBottom, MSBDDockLeft, 1366, 1024), 1);
    Int("  ... Left to Right: moved", MSBDDockSideMoved(MSBDDockLeft, MSBDDockRight, 1366, 1024), 1);
    Int("  ... Right to Bottom: moved", MSBDDockSideMoved(MSBDDockRight, MSBDDockBottom, 1194, 834), 1);
    Int("  ... the same position: nothing", MSBDDockSideMoved(MSBDDockLeft, MSBDDockLeft, 1366, 1024), 0);
    Num("near the side: looked at often", MSBDDockPointerInterval(MSBDDockRight, near_, a12z, false, false), 0.05);
    Num("far from it: seldom", MSBDDockPointerInterval(MSBDDockRight, far_, a12z, false, false), 0.25);
    Num("a Dock simply there, not brought by the pointer: seldom", MSBDDockPointerInterval(MSBDDockRight, near_, a12z, true, false), 0.5);
    // ---- the Home Screen: the Dock's room out of the free space beside the icons, the layout's shape kept (M1 15.6.1 with Atria, iPad 2 16.7.7, read 5 Nov) ----
    CGRect m1Page = CGRectMake(0, 0, 1194, 834), m1Page2 = CGRectMake(1194, 0, 1194, 834), ipad2Page = CGRectMake(0, 0, 1024, 768);
    // (KT's M1, page 1: two Atria columns along the left edge, pictures from x 56.5, insets left 56.5 right 982.5; the Dock at the left reaches 52.1 pt in)
    CGRect kt = MSBDDockSideHomeListFrame(m1Page, MSBDDockLeft, 52.1, 56.5, 982.5);
    Frame("M1, Atria's two columns, Dock at the left: the list moves over, as wide as before (nothing squeezed or laid out again)", kt, CGRectMake(52.1 * 982.5 / 1039.0, 0, 1194, 834));
    Num("  ... the left column's pictures clear of the Dock, their margin from its edge nearly the screen's (56.5 at the bottom)", CGRectGetMinX(kt) + 56.5 - 52.1, 56.5 - 52.1 * 56.5 / 1039.0);
    CGRect ktR = MSBDDockSideHomeListFrame(m1Page, MSBDDockRight, 52.1, 56.5, 982.5);
    Num("  ... the Dock at the right: the columns stay along the left edge (2.8 pt of their 56.5 go)", CGRectGetMinX(ktR), -52.1 * 56.5 / 1039.0);
    Num("  ... same width", ktR.size.width, 1194);
    Frame("  ... page 2 the same from its own place in the scroll view (insets left 139.7, right 157), the largest gap's Dock (70.1)",
        MSBDDockSideHomeListFrame(m1Page2, MSBDDockLeft, 70.1, 139.7, 157.0), CGRectMake(1194 + 70.1 * 157.0 / 296.7, 0, 1194, 834));
    // (the iPad 2's own grid, insets 124 both sides; the Dock 54.5 pt in: the grid stays centred between the Dock and the other edge)
    Frame("iPad 2, iPadOS's own grid, Dock at the left: half the room each side, centred beside the Dock", MSBDDockSideHomeListFrame(ipad2Page, MSBDDockLeft, 54.5, 124, 124), CGRectMake(27.25, 0, 1024, 768));
    Frame("  ... at the right", MSBDDockSideHomeListFrame(ipad2Page, MSBDDockRight, 54.5, 124, 124), CGRectMake(-27.25, 0, 1024, 768));
    // (icons that don't fit beside the Dock at their size: the list takes the room beside it and the layout fits itself in)
    Frame("a full-width layout (free 10 + 10): the list is the room beside a Dock at the left", MSBDDockSideHomeListFrame(ipad2Page, MSBDDockLeft, 54.5, 10, 10), CGRectMake(54.5, 0, 969.5, 768));
    Frame("  ... at the right", MSBDDockSideHomeListFrame(ipad2Page, MSBDDockRight, 54.5, 10, 10), CGRectMake(0, 0, 969.5, 768));
    Frame("  ... just room for 6 pt each side: still moved, not laid out again", MSBDDockSideHomeListFrame(ipad2Page, MSBDDockLeft, 54.5, 33.25, 33.25), CGRectMake(27.25, 0, 1024, 768));
    Frame("the bottom: the frame as iPadOS gives it", MSBDDockSideHomeListFrame(m1Page, MSBDDockBottom, 52.1, 56.5, 982.5), m1Page);
    Frame("  ... no room known yet: as iPadOS gives it", MSBDDockSideHomeListFrame(m1Page, MSBDDockLeft, 0, 56.5, 982.5), m1Page);
    double fl = 0, fr = 0;
    MSBDDockSideHomeFree(56.5, 982.5, false, &fl, &fr); Num("the free space: the insets as they are, left to right", fl * 10000 + fr, 56.5 * 10000 + 982.5);
    MSBDDockSideHomeFree(56.5, 982.5, true, &fl, &fr); Num("  ... right to left, the layout mirrored: swapped", fl * 10000 + fr, 982.5 * 10000 + 56.5);
    Int("the check: an icon at x 56.5 with the Dock 70.1 pt in at the left is under it", MSBDDockSideHomeUnder(CGRectMake(56.5, 62.5, 60, 60), 1194, MSBDDockLeft, 70.1), 1);
    Int("  ... moved 70.1 pt it is clear", MSBDDockSideHomeUnder(CGRectMake(126.6, 62.5, 60, 60), 1194, MSBDDockLeft, 70.1), 0);
    Int("  ... at the right: an icon ending at 1150 is under a Dock 52.1 pt in", MSBDDockSideHomeUnder(CGRectMake(1090, 62.5, 60, 60), 1194, MSBDDockRight, 52.1), 1);
    Int("  ... one ending at 1141.9 touches its edge only: clear", MSBDDockSideHomeUnder(CGRectMake(1081.9, 62.5, 60, 60), 1194, MSBDDockRight, 52.1), 0);
    Int("  ... the bottom: never", MSBDDockSideHomeUnder(CGRectMake(0, 0, 60, 60), 1194, MSBDDockBottom, 52.1), 0);
    // ---- the clock's Today panel (A12Z 18.5, 5 Nov: 380 pt wide; the Right Dock's platter from x 1300.2, so the desktop ends at 1298.2; the Left one's to 65.8) ----
    CGRect clockR = CGRectMake(1240, 0, 120, 37), clockRTL = CGRectMake(8, 0, 120, 37);
    CGRect deskRight = CGRectMake(0, 37, 1298.2, 987), deskLeft = CGRectMake(67.8, 37, 1298.2, 987), deskBottom = CGRectMake(0, 37, 1366, 905);
    MSBDPanelSpan sb = MSBDDockSidePanelSpan(1366, MSBDDockBottom, deskBottom), sr = MSBDDockSidePanelSpan(1366, MSBDDockRight, deskRight), sl = MSBDDockSidePanelSpan(1366, MSBDDockLeft, deskLeft);
    Num("the bottom: the panel hangs from the clock's right end, 6 pt from the screen's edge (as before: x 980)", MSBDPanelHungX(CGRectGetMinX(clockR), CGRectGetMaxX(clockR), 380, sb, false), 980);
    Num("  ... a short clock further in: its right edge 4 pt past the clock's end", MSBDPanelHungX(1240, 1300, 380, sb, false), 924);
    Num("  ... right to left: from the clock at the bar's left end, 6 pt from the screen's edge", MSBDPanelHungX(CGRectGetMinX(clockRTL), CGRectGetMaxX(clockRTL), 380, sb, true), 6);
    Num("Dock at the right: the panel's right edge 10 pt inside the desktop, 12 pt clear of the Dock", MSBDPanelHungX(CGRectGetMinX(clockR), CGRectGetMaxX(clockR), 380, sr, false) + 380, 1288.2);
    Num("  ... right to left the panel is at the left: as at the bottom", MSBDPanelHungX(CGRectGetMinX(clockRTL), CGRectGetMaxX(clockRTL), 380, sr, true), 6);
    Num("Dock at the left: the panel at the right, as at the bottom", MSBDPanelHungX(CGRectGetMinX(clockR), CGRectGetMaxX(clockR), 380, sl, false), 980);
    Num("  ... right to left (the clock at the left end, by the Dock): its left edge 10 pt inside the desktop", MSBDPanelHungX(CGRectGetMinX(clockRTL), CGRectGetMaxX(clockRTL), 380, sl, true), 77.8);
    Num("the iPad 2 (1024 wide), Dock at the right reaching 54.5 pt in: the panel's right edge at 957.5", MSBDPanelHungX(900, 1018, 380, MSBDDockSidePanelSpan(1024, MSBDDockRight, CGRectMake(0, 20, 967.5, 748)), false) + 380, 957.5);
    Num("a desktop not known (empty): the screen's margins", MSBDPanelHungX(CGRectGetMinX(clockR), CGRectGetMaxX(clockR), 380, MSBDDockSidePanelSpan(1366, MSBDDockRight, CGRectZero), false), 980);
    // ---- the Mac-style notification banners (the same desktops; 360 pt wide, 10 pt from the screen's edge: a Right Dock's top lay under them) ----
    double bw = 0;
    Num("the bottom: a banner at the top right, 10 pt from the screen's edge (as before: x 996)", MSBDBannerX(1366, MSBDDockBottom, deskBottom, 360, false, &bw), 996);
    Num("  ... 360 pt wide", bw, 360);
    Num("  ... right to left: at the top left, 10 pt in", MSBDBannerX(1366, MSBDDockBottom, deskBottom, 360, true, &bw), 10);
    Num("the Dock at the right: its right edge 10 pt inside the desktop, 12 pt clear of the Dock (as the Today panel's)", MSBDBannerX(1366, MSBDDockRight, deskRight, 360, false, &bw) + bw, 1288.2);
    Num("  ... still 360 pt wide", bw, 360);
    Num("  ... right to left the banner is at the left: as at the bottom", MSBDBannerX(1366, MSBDDockRight, deskRight, 360, true, &bw), 10);
    Num("the Dock at the left: the banner at the right, as at the bottom", MSBDBannerX(1366, MSBDDockLeft, deskLeft, 360, false, &bw), 996);
    Num("  ... right to left, by the Dock: its left edge 10 pt inside the desktop", MSBDBannerX(1366, MSBDDockLeft, deskLeft, 360, true, &bw), 77.8);
    Num("the iPad 2, Dock at the right reaching 54.5 pt in: its right edge at 957.5", MSBDBannerX(1024, MSBDDockRight, CGRectMake(0, 20, 967.5, 748), 360, false, &bw) + bw, 957.5);
    Num("portrait (the Dock at the bottom there whatever is chosen): as before", MSBDBannerX(1024, MSBDDockBottom, CGRectNull, 360, false, &bw), 654);
    Num("a narrow screen: as wide as the room less the margins, as before", (MSBDBannerX(300, MSBDDockBottom, CGRectNull, 360, false, &bw), bw), 280);
    Num("a desktop not known (empty): the screen's margin", MSBDBannerX(1366, MSBDDockRight, CGRectZero, 360, false, &bw), 996);
    printf("%s: %d/%d checks pass\n", fails ? "test-dockside FAILED" : "test-dockside", checks - fails, checks);
    return fails ? 1 : 0;
}
