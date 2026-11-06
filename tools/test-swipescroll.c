// test-swipescroll.c: a trackpad's two-finger scroll down over the Home Screen beside a window of ours is not the swipe down that opens the App
// Library (dock/SwipeDownRule.h, KT 1.8.2), as UIKit moves the Home Screen search view's pan (UIKitCore 17.6.1, read): a finger's pan holds its
// touches (-numberOfTouches: one at least while it moves, two for two fingers); a scroll's pan holds none -- -_scrollingChangedWithEvent: moves it
// by the scroll's deltas, for a trackpad's two-finger scroll and a mouse wheel alike, and never adds a touch.
#include <stdio.h>
#include "../dock/SwipeDownRule.h"

static int fails = 0;
static void expect(int ok, const char *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails++; }

typedef struct { const char *what; unsigned long touches; int askable; int scroll; int window; int library; } Case;

int main(void) {
    // (askable: UIKit's own scroll event can be asked of the pan, -_activeEventOfType: 10; scroll: one is there)
    expect(DMPanIsPointerScroll(0, 1, 1), "a pan UIKit's scroll event drives is a pointer's scroll (a trackpad's two fingers, a mouse wheel)");
    expect(!DMPanIsPointerScroll(1, 1, 0) && !DMPanIsPointerScroll(2, 1, 0) && !DMPanIsPointerScroll(5, 1, 0), "  ... one finger, two fingers, a whole hand: never a pointer's scroll");
    expect(!DMPanIsPointerScroll(0, 1, 0), "  ... a finger's pan asked after the finger lifted (its begin waited for another recognizer): no touch left, no scroll event, a finger's (code review 1.8.2, 13)");
    expect(DMPanIsPointerScroll(0, 0, 0) && !DMPanIsPointerScroll(1, 0, 0), "  ... where the scroll event can't be asked: a pan with no touch, as before");
    const Case cases[] = {
        { "a two-finger scroll down beside a window of ours: no App Library (KT, 1.8.2)",                         0, 1, 1, 1, 0 },
        { "  ... where the scroll event can't be asked, by its touches: the same",                                0, 0, 0, 1, 0 },
        { "a two-finger scroll down with no window of ours on screen: the App Library, as before",                0, 1, 1, 0, 1 },
        { "a finger's swipe down beside a window of ours: the App Library, as before",                            1, 1, 0, 1, 1 },
        { "a quick flick beside a window, its pan asked after the finger lifted: the App Library (review, 13)",   0, 1, 0, 1, 1 },
        { "a finger's swipe down with no window: the App Library, as before",                                     1, 1, 0, 0, 1 },
        { "two fingers on the screen beside a window (a touch pan, not a scroll): as before",                     2, 1, 0, 1, 1 },
        { "two fingers on the screen with no window: as before",                                                  2, 1, 0, 0, 1 },
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++)
        expect(DMSwipeDownTakesPan(cases[i].touches, cases[i].askable, cases[i].scroll, cases[i].window) == cases[i].library, cases[i].what);
    // (any window flag that is not 0 is a window: the rule reads it as a C truth value, as Dock.x hands it a BOOL)
    expect(!DMSwipeDownTakesPan(0, 1, 1, 2) && DMSwipeDownTakesPan(0, 1, 1, 0), "  ... the window's flag as a truth value");
    printf(fails ? "test-swipescroll.c: %d FAILED\n" : "test-swipescroll.c: all pass\n", fails);
    return fails ? 1 : 0;
}
