// MSWHoldRule.h -- the hold that opens the Mac Switcher from a swipe up (1.7.8), plain C so that tools/test-mswhold.sh checks it on the Mac.
// MacSwitcher.h feeds it every touch of a finger gesture from the bottom edge: the gesture's translation (y < 0 is up the screen) and the touch's own
// time (seconds). A rest is the fingers staying inside kMSWRestSlop of where they came to rest; it is a hold once it lasts kMSWRestNeeded with
// the fingers kMSWRestMinTravel up the screen. A resting finger that sends no touches (it does not move) rests until its lift's touch.
// The rule answers only at a lift: while SpringBoard handles the gesture's end (ending) and that end brought a touch newer than every update
// (lifted). An end SpringBoard makes itself with the finger still down -- with Reduce Motion it ends the gesture at the pause it reads, in the
// middle of the update that read it, whichever modifier runs it -- brings no new touch, and a decision taken outside the end has none to measure:
// both keep SpringBoard's own rule, as the rest would read ~0 ms there and every hold would go Home.
// Reduce Motion's end with the finger still down is ours to allow (1.7.9): SpringBoard makes it only while the fingers rest at that touch
// (DMMSWPauseResting) -- the same hold the lift asks for -- so a swipe still moving goes on to its lift.
#ifndef MSWHOLDRULE_H
#define MSWHOLDRULE_H
#include <math.h>
#define kMSWRestSlop 8.0          // pt: a resting finger's tremor and drift stay inside this
#define kMSWRestNeeded 0.15       // s: iPadOS's own hold count (0.1 s) starts once its 83 ms average speed has come down
#define kMSWRestMinTravel 50.0    // pt up the screen before a rest counts (SpringBoard's own 12 mm for Home or the App Switcher)
typedef struct {
    double x, y, since, last;     // where the fingers came to rest, since when, the latest touch's time
    int held, on;                 // a hold earlier in the gesture; the gesture is watched
    int ending, lifted;           // SpringBoard is handling the gesture's end now; that end brought a newer touch (the lift's)
    int decided, home;            // the lift's answer, given once per gesture (DMMSWPauseSaysHome)
} DMMSWPause;
static inline void DMMSWPauseBegin(DMMSWPause *h, double x, double y, double t) {
    h->x = x; h->y = y; h->since = h->last = t; h->held = 0; h->on = 1; h->ending = h->lifted = 0; h->decided = h->home = 0;
}
// A touch at (x, y), time t: a move out of the slop ends the rest -- a hold if it was long enough, up the screen -- and starts the next one there.
static inline void DMMSWPauseMove(DMMSWPause *h, double x, double y, double t) {
    if (!h->on) return;
    if (t > h->last) h->last = t;
    if (hypot(x - h->x, y - h->y) <= kMSWRestSlop) return;
    if (t - h->since >= kMSWRestNeeded && -h->y >= kMSWRestMinTravel) h->held = 1;
    h->x = x; h->y = y; h->since = t;
}
// The gesture's end, as SpringBoard starts handling it: its touch (where, when). Lifted when that touch is newer than every update's.
static inline void DMMSWPauseEnd(DMMSWPause *h, double x, double y, double t) {
    if (!h->on) return;
    h->lifted = t > h->last;
    DMMSWPauseMove(h, x, y, t);
}
// 1 = the gesture held, now or earlier; *rest = the rest going on at the latest touch (s).
static inline int DMMSWPauseHeld(const DMMSWPause *h, double *rest) {
    double r = h->last - h->since;
    if (rest) *rest = r;
    return h->held || (r >= kMSWRestNeeded && -h->y >= kMSWRestMinTravel);
}
// SpringBoard is about to end the gesture in the App Switcher with the fingers still down (Reduce Motion, at a pause it reads in the middle of
// a move): 1 = they rest now -- inside kMSWRestSlop for kMSWRestNeeded up the screen at the latest touch, so their speed over that time is
// under kMSWRestSlop / kMSWRestNeeded (~53 pt/s). A hold earlier in the gesture does not count: the fingers have moved on since.
static inline int DMMSWPauseResting(const DMMSWPause *h) {
    return h->on && h->last - h->since >= kMSWRestNeeded && -h->y >= kMSWRestMinTravel;
}
// SpringBoard asks what a swipe it ends in the App Switcher does (one gesture can have two modifiers that ask, and ask more than once):
// 1 = Home -- a lift without a hold; 0 = SpringBoard's destination stands (a hold; not watched; no lift being handled). The first answer at a
// lift stands for every later ask in the same gesture, inside its end or after; an ask with no lift being handled is answered 0 and decides
// nothing.
static inline int DMMSWPauseSaysHome(DMMSWPause *h, double *rest) {
    int held = DMMSWPauseHeld(h, rest);
    if (h->decided) return h->home;
    if (!h->on || !h->ending || !h->lifted) return 0;
    h->decided = 1; h->home = !held;
    return h->home;
}
#endif
