// Mac test of the rules for moving a sticky note (1.8.8.2 B78): common/StickyNotes.h's MSBDStickyPressTypes, MSBDStickyTapMoved, MSBDStickyBarRect / MSBDStickyOnBar,
// MSBDStickyHoldToMove, with DesktopHold.h's MSBDDesktopTouchOursAnswer (the Dock's swipe down asks it) and Desktop.h's hold times, cut out by
// test-stickymove.sh as written.
#import <Foundation/Foundation.h>
#include "common/StickyNotes.h"
#include "DesktopHold.h"
#include "holdtotake.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)

int main(void) { @autoreleasepool {
    // ---- one decider: a press types only when it never went past its drag distance, no menu of ours is up, let go before the menu's time ----
    {
        struct { int moved, menu; double held, menuTime; BOOL want; const char *what; } c[] = {
            {0, 0, 0.08, kDMDesktopHoldMenuPointer, YES, "a still click: types"}, {0, 0, 0.12, kDMDesktopHoldMenu, YES, "a still finger tap: types"},
            {1, 0, 0.08, kDMDesktopHoldMenuPointer, NO, "a pointer drag of 6 pt (past 4): never types, however short"}, {1, 0, 0.20, kDMDesktopHoldMenu, NO, "a finger flick past 10 pt that snapped back: no typing"},
            {0, 1, 0.10, kDMDesktopHoldMenu, NO, "a menu of ours up: the hold's lift, not a tap"}, {0, 0, 0.80, kDMDesktopHoldMenuPointer, NO, "a click held 0.8 s (its menu at 0.75 s): no typing"},
            {0, 0, 0.50, kDMDesktopHoldMenu, NO, "a finger held 0.5 s (its menu at 0.45 s): no typing"}, {0, 0, 0.70, kDMDesktopHoldMenuPointer, YES, "a click held 0.7 s, short of its menu: types"},
        };
        for (size_t i = 0; i < sizeof c / sizeof c[0]; i++) CHECK(MSBDStickyPressTypes(c[i].moved, c[i].menu, c[i].held, c[i].menuTime) == c[i].want, "%s", c[i].what);
        CHECK(kDMDesktopHoldMenu == 0.45 && kDMDesktopHoldMenuPointer == 0.75, "the menus' times the rule is given: a finger 0.45 s, a click 0.75 s (Desktop.h)");
    }
    // ---- which press a tap ends, and whether it moved (MSBDStickyTapMoved) ----
    // UIKit's order, as on the device: the tap's shouldReceiveTouch: (the touch kept, where it went down) BEFORE SpringBoard's -sendEvent: (where
    // -dm_event: follows the press: its touch kept, _trackMoved set past the drag distance, its last point); at the lift -dm_event: first, then the
    // tap's action. A drag within UIKit's own tap allowance still ends in a tap: these are the presses the tap then judges.
    {
        typedef struct { const void *tapTouch, *pressTouch; double downX, lastX, liftX; int trackMoved; } Press;
        Press (^run)(const void *touch, double lim, int nMoves, const double *xs, int followed) = ^Press(const void *touch, double lim, int nMoves, const double *xs, int followed) {
            Press p = { touch, NULL, 100, 100, 100, 0 };          // (shouldReceiveTouch: first: the tap's touch and where it went down)
            if (followed) { p.pressTouch = touch; p.trackMoved = 0; }   // (-dm_event:'s touch-down: the press's touch kept, its note cleared)
            for (int i = 0; i < nMoves; i++) { if (followed) { p.lastX = xs[i]; if (fabs(xs[i] - p.downX) > lim) p.trackMoved = 1; } p.liftX = xs[i]; }
            return p;
        };
        BOOL (^moved)(Press, double) = ^BOOL(Press p, double lim) { return MSBDStickyTapMoved(p.tapTouch && p.tapTouch == p.pressTouch, p.trackMoved, fabs(p.lastX - p.downX), fabs(p.liftX - p.downX), lim); };
        int a = 0, b = 0;
        double d6[] = { 102, 104, 106 }, d12[] = { 104, 108, 112 }, d20[] = { 105, 110, 115, 120 }, d40[] = { 110, 120, 130, 140 }, still[] = { 100.5, 101 }, back[] = { 106, 112, 106, 101 };
        CHECK(moved(run(&a, 4.0, 3, d6, 1), 4.0) && moved(run(&a, 4.0, 3, d12, 1), 4.0) && moved(run(&a, 4.0, 4, d20, 1), 4.0) && moved(run(&a, 4.0, 4, d40, 1), 4.0),
              "pointer drags of 6, 12, 20 and 40 pt that UIKit still ends in a tap: moved, never typed (the device's V2 typed in each)");
        CHECK(!moved(run(&a, 4.0, 2, still, 1), 4.0), "a still click (1 pt): not moved, it types where clicked");
        double flick[] = { 108, 118, 125 }; CHECK(moved(run(&b, 10.0, 3, flick, 1), 10.0), "a finger's 25 pt flick in 80 ms, given to the page and snapped back, then a tap: moved, never typed (the device's N2)");
        CHECK(moved(run(&a, 4.0, 4, back, 1), 4.0), "a press that went 12 pt out and came back to 1 pt: moved (it went past its distance once: B78's rule)");
        CHECK(moved(run(&a, 4.0, 3, d20, 0), 4.0), "a press -dm_event: did not follow (another press still held it): the tap's own touch's travel decides, 20 pt: moved");
        CHECK(!moved(run(&a, 4.0, 2, still, 0), 4.0), "  ... and a still one of those: types");
        Press other = run(&a, 4.0, 3, d40, 1); other.tapTouch = &b; other.liftX = 101;
        CHECK(!moved(other, 4.0), "the followed press was another touch (the tap's own touch still): that press's note is not the tap's");
        CHECK(!MSBDStickyTapMoved(0, 0, NAN, NAN, 4.0) && MSBDStickyTapMoved(1, 0, NAN, 30, 10) && !MSBDStickyTapMoved(0, 1, 100, 2, 4), "NaN travels count as none; a press's note counts only for its own tap");
        // (the test build's two witnesses saw none of these: the press was matched by _trackAt at shouldReceiveTouch:, before -dm_event: had it, so
        //  never; and the travel was from the tap's own location, which is where it went down: 0)
    }
    // ---- the top bar ----
    {
        CGRect note = CGRectMake(300, 200, 220, 180), bar = MSBDStickyBarRect(note);
        CHECK(CGRectEqualToRect(bar, CGRectMake(300, 200, 220, MSBD_NOTE_BAR)) && MSBD_NOTE_BAR == 22.0, "the bar: the note's top 22 pt, its whole width");
        CHECK(MSBDStickyOnBar(note, CGPointMake(301, 201)) && MSBDStickyOnBar(note, CGPointMake(519, 221)) && !MSBDStickyOnBar(note, CGPointMake(400, 223)) && !MSBDStickyOnBar(note, CGPointMake(400, 199)) && !MSBDStickyOnBar(note, CGPointMake(521, 210)),
              "a point on the bar is on it; under it, above the note or beside it is not");
        CGRect small = CGRectMake(0, 0, MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H);
        const CGFloat grip = 22.0, in = 6.0;   // (DesktopNotes.h: kDMNoteGrip, its middle 6 pt in from the bottom corners)
        CGRect gl = CGRectMake(-grip / 2 + in, small.size.height - grip / 2 - in, grip, grip), gr = CGRectMake(small.size.width - grip / 2 - in, small.size.height - grip / 2 - in, grip, grip);
        CHECK(!CGRectIntersectsRect(MSBDStickyBarRect(small), gl) && !CGRectIntersectsRect(MSBDStickyBarRect(small), gr), "the smallest note (120 x 80): the bar never meets a resize grip's touch area");
        CHECK(MSBDStickyBarRect(CGRectMake(0, 0, 50, 10)).size.height == 10, "a note shorter than the bar (never shown so): the bar is the note");
    }
    // ---- the hold to move, and whose the touch is ----
    {
        CHECK(MSBDStickyHoldToMove(1) == 0.0 && MSBDStickyHoldToMove(0) == 0.2 && MSBD_NOTE_HOLD_TO_MOVE == 0.2, "a note's hold to move: none on its bar, 0.2 s on its paper");
        CHECK(MSBDStickyHoldToMove(0) < DMDesktopHoldToTake(YES) && DMDesktopHoldToTake(YES) == 0.3 && DMDesktopHoldToTake(NO) == 0.35, "  ... under the icons' 0.3 s and the empty desktop's 0.35 s, which stay as they are");
        MSBDTouchOwner o = MSBDTouchUndecided;
        CHECK(MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.0, MSBDStickyHoldToMove(1)) == 1 && o == MSBDTouchDesktop, "the Dock's swipe down (or Spotlight's pull) from a bar: the note's at once");
        o = MSBDTouchUndecided;
        CHECK(MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.1, MSBDStickyHoldToMove(0)) == 0 && o == MSBDTouchUndecided, "  ... from the paper 0.1 s in: not the note's yet (a quick swipe is the Home Screen's)");
        CHECK(MSBDDesktopTouchOursAnswer(&o, 0, 0, 0, 0.2, MSBDStickyHoldToMove(0)) == 1 && o == MSBDTouchDesktop, "  ... and 0.2 s in: the note's");
        o = MSBDTouchUndecided; MSBDDesktopTouchGiveAway(&o);
        CHECK(MSBDDesktopTouchOursAnswer(&o, 1, 0, 0, 5.0, MSBDStickyHoldToMove(1)) == 0, "a touch the swipe down took stays its own, a bar's too");
    }
    printf("test-stickymove: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
