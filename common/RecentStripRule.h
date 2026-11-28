// RecentStripRule.h: the Recent Windows Strip's rules (1.8.8.2 F29, KT 20 Nov: "it can be like on macos"; reworked for 1.8.8.4, KT 24 Nov:
// "lets fix the side strip on os15"). Plain Foundation and C, no UIKit: SpringBoard's part is
// statusbar/RecentStrip.h, the Settings rows common/OwnPageRows.h, the Home Screen's room common/DockSide.h, the Mac test tools/test-recentstrip.sh.
//  - the list: the windows of the desktop that are off it (minimized, sent to the strip, swapped out), most recent first, by an entry time each
//    window carries; a pick swaps (the picked window comes back, the one in front takes its slot), a Shift pick or a pick from anywhere else only
//    brings back;
//  - when the strip shows (on its own on the desktop or the Home Screen, brought out over the windows, a drop target for a window drag) and when it
//    steps aside;
//  - its place on the screen: the side, the band, the cards, how many fit, a slot opened for a window coming in;
//  - a window drag over it, a card dragged out (its size on the way, the window's frame where it is let go), a press (tap, menu or drag);
//  - the pointer at the edge and its leaving, the finger's handle, a reveal's end, a card's picture and when one is taken, the motion's numbers.
#pragma once
#import <Foundation/Foundation.h>
#include <math.h>

// Where it runs: iPadOS 15 (the window pictures without SpringBoard waiting are read and verified there only: statusbar/MacSwitcher.h
// DMMSWAsyncPicturesOK). The Settings row and the strip follow this one rule.
static inline BOOL MSBDRecentStripOS(long major) { return major == 15; }
#define kMSBDRStripMax        6        // at most this many cards (a small cap, as Stage Manager's)
#define kMSBDRStripEdgeGap    12.0     // a card's distance from the screen's edge (and from the band's inner edge)
#define kMSBDRStripCardGap    16.0     // between two cards
#define kMSBDRStripEnds       24.0     // the cards' run keeps this far from the top and the bottom of the desktop
#define kMSBDRStripCoverSlack 4.0      // a window that overlaps the cards' part by this much or less does not cover it
#define kMSBDRStripEdgeAt     2.0      // the pointer this close to the strip's screen edge is at the edge
#define kMSBDRStripLeaveBy    40.0     // the pointer this far past the band has left it
#define kMSBDRStripPointerOut 0.4      // ... for this long (s): a pointer reveal ends
#define kMSBDRStripIdleEnd    6.0      // a reveal by the Window menu or the handle ends untouched after this long (s), never while VoiceOver or Switch Control run
#define kMSBDRStripDropBy     24.0     // a window drag this close to the band (or in it) is over the drop zone
#define kMSBDRStripPickGap    0.45     // one pick at a time: a second pick this soon after one is not taken (a double tap never swaps back)
#define kMSBDRStripSettle     0.40     // a card that came in takes no pick until its flight has landed and settled (s)
#define kMSBDRStripBurstStep  0.03     // Minimize All and Home: each window's flight this much after the one before (s)
#define kMSBDRStripHold       0.45     // a finger held still this long on a card: its menu on release, a drag if it moves on (the desktop's hold time)
#define kMSBDRStripFingerSlop 10.0     // a finger moved this far is a drag
#define kMSBDRStripPointerSlop 4.0     // a pointer moved this far with the button down is a drag
#define kMSBDRStripGrowFrom   40.0     // a card dragged this far past the band starts to grow toward its window
#define kMSBDRStripGrowOver   160.0    // ... and has its size there this much further
#define kMSBDRStripGrowMax    2.6      // ... at most this many times its own size (its picture stays sharp; the window grows out of it where it is let go)
#define kMSBDRStripFlick      0.15     // a card thrown out of the band lands where its speed takes it in this long (s)
#define kMSBDRStripSpringLoad 0.6      // a dragged item held over a card this long brings its window back (s)
#define kMSBDRStripMinPicLife 10.0     // a burst (Minimize All, Home) takes no new picture of the window in front pictured this recently (s)
#define kMSBDRStripFlightShow 1.2      // a window flown into a strip that had stepped aside: the strip stays out this long after it landed (s)
#define kMSBDRStripGoneWait   1.0      // a waiting window whose window went: its card is decided this long after, once the app's end is noted (s)
#define kMSBDRStripPicKeepMore 3       // pictures kept beyond the cards shown (the next ones up when a card leaves)
#define kMSBDRStripHandleW    4.0      // the finger's handle at the edge while the strip has stepped aside: its size
#define kMSBDRStripHandleH    44.0
#define kMSBDRStripHandleTouchW 20.0   // ... its touch area: this wide at the very edge, the handle's height and this much above and below
#define kMSBDRStripHandleTouchPad 22.0
// The motion (every change a spring through MSBAnimate; Reduce Motion: cross-fades)
#define kMSBDRStripShowTime   0.42     // show (the desktop free, a reveal): a slide in from the edge, this long, this damping
#define kMSBDRStripShowDamp   0.86
#define kMSBDRStripStagger    0.025    // ... the cards this far apart, top to bottom, at most kMSBDRStripStaggerMax in all
#define kMSBDRStripStaggerMax 0.125
#define kMSBDRStripAsideTime  0.22     // step aside: a slide out, ease in, no stagger
#define kMSBDRStripMoveTime   0.42     // cards making room or closing a gap, a reorder: position springs
#define kMSBDRStripMoveDamp   0.86
#define kMSBDRStripInsertDamp 0.80     // a card coming in with no flight (scale 0.85 to 1 and a fade), 40 ms apart
#define kMSBDRStripInsertStep 0.04
#define kMSBDRStripSettleScale 1.03    // a card where a flight landed: from this scale to 1
#define kMSBDRStripHoverScale 1.05     // the pointer over a card: it lifts (scale, up, a larger shadow, a tilt toward the desktop)
#define kMSBDRStripHoverLift  2.0
#define kMSBDRStripShadow     7.0
#define kMSBDRStripHoverShadow 12.0
#define kMSBDRStripHoverTilt  5.0      // degrees
#define kMSBDRStripHoverTime  0.30
#define kMSBDRStripHoverDamp  0.80
#define kMSBDRStripPressScale 0.96     // a finger or a click down on a card
#define kMSBDRStripPressIn    0.18     // ... reached this fast
#define kMSBDRStripHoldScale  1.04     // a finger held still kMSBDRStripHold: the card rises a little (ready: its menu on release, a drag if it moves on)
#define kMSBDRStripHoldRise   0.20     // ... over this long
#define kMSBDRStripLiftScale  1.06     // a card dragged: lifted
#define kMSBDRStripLiftShadow 14.0
#define kMSBDRStripPlaceFade  0.32     // a dragged card turning into its window where it was let go

// ---- the list (KT's choice: the windows off the desktop) ----
// Which windows wait in the strip: the ones our minimize hid (Aerial 5's round chip after a lock and Zetsu's own title bar pill stay on the desktop
// as their engine draws them), not one on its way out (closing, going full screen) and not one of another Mac Switcher desktop.
static inline BOOL MSBDRStripIsOff(BOOL hiddenByUs, BOOL closing, BOOL goingFull, BOOL away) { return hiddenByUs && !closing && !goingFull && !away; }
// Why a window is in the strip: the user minimized it (the yellow light, Command-M, the app menu, Minimize All, Home, Move to Strip, Aerial's chip),
// it was swapped out by a pick, dragged onto the strip, or found there (minimized before the switch went on, or brought back minimized by a
// respring with no time saved).
typedef NS_ENUM(int, MSBDRStripWhy) { MSBDRStripWhyNone = 0, MSBDRStripWhyMinimized = 1, MSBDRStripWhySwapped = 2, MSBDRStripWhyDragged = 3, MSBDRStripWhySeeded = 4 };
#define kMSBDRStripSeedAt (-1.0e9)   // a found window's time: older than any real one
// A window's entry time as it goes in. now: the clock (seconds since 2001, so a respring keeps it); picked: the picked card's own time (a swap:
// the window that leaves takes the slot the card leaves); seed: a found window's place in the stage order, the front one 0.
static inline double MSBDRStripEntryAt(int why, double now, double picked, int seed) {
    if (why == MSBDRStripWhySwapped && isfinite(picked)) return picked;
    if (why == MSBDRStripWhySeeded) return kMSBDRStripSeedAt - (seed > 0 ? seed : 0);
    return now;
}
// The list: off (the keys of the windows off this desktop, in the stage order from the front back) sorted by their entry times, most recent first;
// a key with no time, or equal times, keep the stage order (no time: after every one with a time).
static inline NSArray<NSString *> *MSBDRStripList(NSArray<NSString *> *off, NSDictionary<NSString *, NSNumber *> *at) {
    if (!off.count) return @[];
    NSMutableArray<NSString *> *keys = [NSMutableArray arrayWithCapacity:off.count];
    for (NSString *k in off) if (k.length && ![keys containsObject:k]) [keys addObject:k];
    return [keys sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSNumber *ta = at[a], *tb = at[b];
        if (!ta && !tb) return NSOrderedSame;
        if (!ta) return NSOrderedDescending;
        if (!tb) return NSOrderedAscending;
        double x = ta.doubleValue, y = tb.doubleValue;
        return x > y ? NSOrderedAscending : (x < y ? NSOrderedDescending : NSOrderedSame);
    }];
}
// The slot a window takes going in at time t (0 = the top): the number of the others with a later time (the same time: it goes first).
static inline NSUInteger MSBDRStripSlotOf(NSArray<NSString *> *list, NSDictionary<NSString *, NSNumber *> *at, NSString *key, double t) {
    NSUInteger n = 0;
    for (NSString *k in list) {
        if ([k isEqualToString:key ?: @""]) continue;
        NSNumber *tk = at[k];
        if (tk && tk.doubleValue > t) n++;
    }
    return n;
}
// The cards shown: the first of the list, as many as fit (and kMSBDRStripMax); the rest wait in the list and move up as cards leave.
static inline NSArray<NSString *> *MSBDRStripShown(NSArray<NSString *> *list, NSUInteger fit) {
    NSUInteger n = MIN(MIN(list.count, fit), (NSUInteger)kMSBDRStripMax);
    return n ? [list subarrayWithRange:NSMakeRange(0, n)] : @[];
}
// Where a flight into slot `slot` lands with `fit` cards shown: that slot, or past the cap the last one (faded: *faded YES).
static inline int MSBDRStripFlightSlot(NSUInteger slot, int fit, BOOL *faded) {
    int last = fit > 0 ? fit - 1 : 0;
    BOOL past = (int)slot > last;
    if (faded) *faded = past;
    return past ? last : (int)slot;
}
// Minimize All and Home: the i-th window's flight starts this long after the first (the one in front last, so it lands on top).
static inline double MSBDRStripBurstDelay(int i) { return i > 0 ? i * kMSBDRStripBurstStep : 0.0; }
// ... and its entry time, set for every window of the burst before the first flight (so each flight's slot is its slot in the final list): the
// loop's order is back to front, so the one in front, last, is the newest.
static inline double MSBDRStripBurstAt(double now, int i) { return now + (i > 0 ? i : 0) * 0.001; }
// An entry read back from the windows' state file (a respring): a finite time and a known reason, else none (the window is seeded when found).
static inline BOOL MSBDRStripSavedEntry(id at, id why, double *outAt, int *outWhy) {
    if (![at isKindOfClass:[NSNumber class]] || ![why isKindOfClass:[NSNumber class]]) return NO;
    double t = [(NSNumber *)at doubleValue]; int w = [(NSNumber *)why intValue];
    if (!isfinite(t) || w < MSBDRStripWhyMinimized || w > MSBDRStripWhySeeded) return NO;
    if (outAt) *outAt = t;
    if (outWhy) *outWhy = w;
    return YES;
}
// A minimize flies into the strip when the switch is on and the strip can show (nothing over the windows, the windows in front); else into the
// app's Dock icon, as before. A restore grows out of the window's card when that card is on the screen (the strip shown, the card landed); else
// out of the Dock icon.
static inline BOOL MSBDRStripFliesIn(BOOL on, BOOL calm, BOOL windowsFront) { return on && calm && windowsFront; }
static inline BOOL MSBDRStripGrowsOut(BOOL cardOnScreen, BOOL stripShown, BOOL landing) { return cardOnScreen && stripShown && !landing; }
// A pick: does the window in front go into the strip (a swap, as Stage Manager)? onCard: a tap or click on a card (the Dock icon, Command-Tab, the App
// Switcher, Spotlight, a notification only bring back); shift: Shift held (the Mac's Shift-click: bring back only); front: a window is in
// front (none on the Home Screen: bring back only); frontJoins: that window can wait in the strip; frontIsPicked: it is the picked one itself.
static inline BOOL MSBDRStripPickSwaps(BOOL onCard, BOOL shift, BOOL front, BOOL frontJoins, BOOL frontIsPicked) {
    return onCard && !shift && front && frontJoins && !frontIsPicked;
}
// A pick is taken: the card has settled since it came in, and no other pick was taken just before (a double tap, rapid taps).
static inline BOOL MSBDRStripPickTakes(double now, double settledAt, double lastPickAt) {
    return now >= settledAt && now - lastPickAt >= kMSBDRStripPickGap;
}
// The switch turned off with cards: a window that went in by a swap or a drag comes back to the desktop; one the user minimized stays.
static inline BOOL MSBDRStripBackAtOff(int why) { return why == MSBDRStripWhySwapped || why == MSBDRStripWhyDragged; }
// A waiting window whose window went away: its card stays (picture kept; a pick opens the app again as a window at its place) when iPadOS
// ended the app (memory, a time-out); it goes when the user closed the window or quit the app, or the app crashed.
static inline BOOL MSBDRStripKeepsGone(BOOL closedOrQuitByUser, BOOL crashed) { return !closedOrQuitByUser && !crashed; }
// ... decided kMSBDRStripGoneWait after the window went (SpringBoard notes the app's end a moment after the window goes: the notes from an earlier
// end are not this one's), then kept until the user's quit or a crash is noted for its app, or the app has a window again. since: how long ago the
// window went; quitting: the user's quit was asked just now (a kill for it, before its end: never an earlier end's); quitByUser, crashed: the
// app's last end as noted. 0: wait, 1: keep, 2: let go.
typedef NS_ENUM(int, MSBDRStripGone) { MSBDRStripGoneWait = 0, MSBDRStripGoneKeep = 1, MSBDRStripGoneDrop = 2 };
static inline MSBDRStripGone MSBDRStripGoneStep(double since, BOOL quitting, BOOL quitByUser, BOOL crashed, BOOL windowBack) {
    if (windowBack || quitting) return MSBDRStripGoneDrop;
    if (since < kMSBDRStripGoneWait) return MSBDRStripGoneWait;
    return MSBDRStripKeepsGone(quitByUser, crashed) ? MSBDRStripGoneKeep : MSBDRStripGoneDrop;
}

// ---- when it shows ----
typedef struct {
    int on;            // the switch on, an engine of the strip's in use, this iPadOS (MSBDRecentStripOS)
    int items;         // how many cards it has
    int calm;          // nothing of the system's or ours over the windows (the screen on and unlocked, no App Switcher, no Mac Switcher session,
                       //  the windows not faded, no Spotlight or Notification Center, no Dock icon menu, no on-screen keyboard, no Guided Access)
    int windowsFront;  // the windows are in front (not behind a full-screen app)
    int windowShown;   // a window of the engine is on screen (not every one minimized)
    int covered;       // a window, or the full-screen app behind the windows, lies over the cards' part of the edge
    int revealed;      // the pointer at the edge, Window > Show Recent Windows or the handle brought it out
    int homeBand;      // the Home Screen keeps the strip's band free: with every window minimized it shows there, its home
    int dropTarget;    // a window drag is over the drop zone: out over the windows to take it, cards or none
} MSBDRStripState;
typedef NS_ENUM(int, MSBDRStripShow) { MSBDRStripHidden = 0, MSBDRStripOnDesktop = 1, MSBDRStripOverWindows = 2 };
static inline MSBDRStripShow MSBDRStripShowFor(MSBDRStripState s) {
    if (!s.on || !s.calm || !s.windowsFront) return MSBDRStripHidden;
    if (s.dropTarget) return MSBDRStripOverWindows;             // (a window can go into an empty strip too)
    if (s.items <= 0) return MSBDRStripHidden;
    if (s.revealed) return MSBDRStripOverWindows;
    if (s.covered) return MSBDRStripHidden;                     // (stepped aside: the pointer at the edge, the Window menu, the handle bring it)
    if (!s.windowShown && !s.homeBand) return MSBDRStripHidden; // (the Home Screen with no band: its icons stay free)
    return MSBDRStripOnDesktop;
}
// A reveal may begin: the strip has something to show and has stepped aside (not shown on its own now, not a drop target).
static inline BOOL MSBDRStripMayReveal(MSBDRStripState s) {
    if (!s.on || s.items <= 0 || !s.calm || !s.windowsFront) return NO;
    s.revealed = 0;   // (a drop target is shown already: nothing to bring)
    return MSBDRStripShowFor(s) == MSBDRStripHidden;
}
// The kinds of reveal, and when one ends by itself: the pointer's once it has left the band for kMSBDRStripPointerOut; the Window menu's and the
// handle's after kMSBDRStripIdleEnd untouched (never while VoiceOver or Switch Control run: they take their time); a flight's (a window flown into
// a strip that had stepped aside) kMSBDRStripFlightShow after the landing or the last touch; a drop target's with its drag.
typedef NS_ENUM(int, MSBDRStripReveal) { MSBDRStripRevealNone = 0, MSBDRStripRevealPointer = 1, MSBDRStripRevealMenu = 2, MSBDRStripRevealHandle = 3, MSBDRStripRevealFlight = 4 };
static inline BOOL MSBDRStripRevealEnds(int kind, double untouchedFor, double pointerOutFor, BOOL assistive) {
    if (kind == MSBDRStripRevealPointer) return pointerOutFor > kMSBDRStripPointerOut;
    if (kind == MSBDRStripRevealFlight) return untouchedFor > kMSBDRStripFlightShow;
    if (kind == MSBDRStripRevealMenu || kind == MSBDRStripRevealHandle) return !assistive && untouchedFor > kMSBDRStripIdleEnd;
    return NO;
}
// ... and whether one needs the step while nothing else changes (it can end by time now): the pointer's once the pointer has left the band (not
// while it is held in it), a flight's always, the Window menu's and the handle's unless VoiceOver or Switch Control run. Any other end is an event
// the step's signature sees (the pointer moving out or going, a pick, a tap outside, Escape, something over the windows): nothing at rest.
static inline BOOL MSBDRStripRevealTimed(int kind, BOOL pointerOut, BOOL assistive) {
    if (kind == MSBDRStripRevealPointer) return pointerOut;
    if (kind == MSBDRStripRevealFlight) return YES;
    if (kind == MSBDRStripRevealMenu || kind == MSBDRStripRevealHandle) return !assistive;
    return NO;
}

// ---- the place ----
typedef struct { double x, y, w, h; } MSBDRRect;
static inline double MSBDRMaxX(MSBDRRect r) { return r.x + r.w; }
static inline double MSBDRMaxY(MSBDRRect r) { return r.y + r.h; }
// The side: the left edge, or the right one with the Dock at Left (as macOS moves its strip when the Dock is on the left).
static inline BOOL MSBDRStripOnRight(BOOL dockAtLeft) { return dockAtLeft; }
// A card's box: its width from the screen's short side (9.5 %, 72 to 104 pt: smaller than 1.8.8.2's), its height 78 % of that.
static inline double MSBDRStripCardW(double sw, double sh) { double w = round(MIN(sw, sh) * 0.095); return w < 72.0 ? 72.0 : (w > 104.0 ? 104.0 : w); }
static inline double MSBDRStripCardH(double sw, double sh) { return round(MSBDRStripCardW(sw, sh) * 0.78); }
// The band: the strip's part of the screen, its side's edge of the desktop to an edge gap past the cards, the desktop's height (96 to 128 pt wide).
static inline double MSBDRStripBandW(double sw, double sh) { return MSBDRStripCardW(sw, sh) + 2.0 * kMSBDRStripEdgeGap; }
static inline MSBDRRect MSBDRStripBand(double sw, double sh, MSBDRRect usable, BOOL right) {
    double bw = MSBDRStripBandW(sw, sh);
    return (MSBDRRect){ right ? MSBDRMaxX(usable) - bw : usable.x, usable.y, bw, usable.h };
}
// How many cards fit the desktop's height (usable: the desktop below the menu bar and above the Dock), at most kMSBDRStripMax.
static inline int MSBDRStripFit(double sw, double sh, MSBDRRect usable) {
    double ch = MSBDRStripCardH(sw, sh), room = usable.h - 2.0 * kMSBDRStripEnds + kMSBDRStripCardGap;
    int n = room > 0 ? (int)floor(room / (ch + kMSBDRStripCardGap)) : 0;
    return n < 0 ? 0 : (n > kMSBDRStripMax ? kMSBDRStripMax : n);
}
// The layout of n cards with a slot open at `gap` (-1: none; a window coming in, a drag's drop target): aspect[i] the i-th card's window's width
// over its height (0: not known, a 4:3 card). band: the strip's part of the screen; cards[i]: the i-th card's picture, its window's shape fitted
// into its box, the boxes (the gap's too) centred in the desktop's height; *gapRect: the open slot's box. With the gap, as many cards as fit beside
// it. Returns how many cards were laid out.
static inline int MSBDRStripLayoutGap(double sw, double sh, MSBDRRect usable, BOOL right, int n, const double *aspect, int gap, MSBDRRect *band, MSBDRRect *cards, MSBDRRect *gapRect) {
    double cw = MSBDRStripCardW(sw, sh), ch = MSBDRStripCardH(sw, sh);
    int fit = MSBDRStripFit(sw, sh, usable);
    if (n < 0) n = 0;
    if (gap > n) gap = n;
    int boxes = n + (gap >= 0 ? 1 : 0);
    if (boxes > fit) boxes = fit;
    if (gap >= boxes) gap = boxes - 1;   // (no room left for the slot below the cards: the last place)
    int laid = gap >= 0 ? boxes - 1 : boxes;
    if (laid < 0) laid = 0;
    MSBDRRect b = MSBDRStripBand(sw, sh, usable, right);
    if (band) *band = b;
    double total = boxes * ch + (boxes > 1 ? (boxes - 1) * kMSBDRStripCardGap : 0.0), top = usable.y + floor((usable.h - total) / 2.0);
    for (int box = 0, i = 0; box < boxes; box++) {
        double y0 = top + box * (ch + kMSBDRStripCardGap);
        if (box == gap) { if (gapRect) *gapRect = (MSBDRRect){ b.x + kMSBDRStripEdgeGap, y0, cw, ch }; continue; }
        double a = aspect && aspect[i] > 0.0 ? aspect[i] : 4.0 / 3.0;
        if (a < 0.3) a = 0.3;
        if (a > 3.0) a = 3.0;
        double w = cw, h = round(cw / a);
        if (h > ch) { h = ch; w = round(ch * a); }
        if (cards) cards[i] = (MSBDRRect){ b.x + kMSBDRStripEdgeGap + floor((cw - w) / 2.0), y0 + floor((ch - h) / 2.0), w, h };
        i++;
    }
    if (gap < 0 && gapRect) *gapRect = (MSBDRRect){ b.x + kMSBDRStripEdgeGap, 0, 0, 0 };
    return laid;
}
static inline int MSBDRStripLayout(double sw, double sh, MSBDRRect usable, BOOL right, int n, const double *aspect, MSBDRRect *band, MSBDRRect *cards) {
    return MSBDRStripLayoutGap(sw, sh, usable, right, n, aspect, -1, band, cards, NULL);
}
// The cards' part of the edge: the band across the cards' run (with the corner icons' 10 pt below the last one).
static inline MSBDRRect MSBDRStripCardsSpan(MSBDRRect band, const MSBDRRect *cards, int n) {
    if (n <= 0 || !cards) return (MSBDRRect){ band.x, band.y, band.w, 0 };
    double top = cards[0].y, bottom = MSBDRMaxY(cards[0]);
    for (int i = 1; i < n; i++) { top = MIN(top, cards[i].y); bottom = MAX(bottom, MSBDRMaxY(cards[i])); }
    return (MSBDRRect){ band.x, top - 8.0, band.w, bottom - top + 18.0 };
}
// A window (its drawn frame on the screen) covers the cards' part when it overlaps it by more than the slack each way.
static inline BOOL MSBDRStripCovers(MSBDRRect span, MSBDRRect win) {
    if (span.h <= 0 || win.w <= 0 || win.h <= 0) return NO;
    double ox = MIN(MSBDRMaxX(span), MSBDRMaxX(win)) - MAX(span.x, win.x), oy = MIN(MSBDRMaxY(span), MSBDRMaxY(win)) - MAX(span.y, win.y);
    return ox > kMSBDRStripCoverSlack && oy > kMSBDRStripCoverSlack;
}
// The Home Screen's room for it (while the switch is on): the band's width, on its side; nothing on another screen than the iPad's.
static inline double MSBDRStripHomeRoom(BOOL on, double sw, double sh) { return on ? MSBDRStripBandW(sw, sh) : 0.0; }
// The band's step each tick (RecentStrip.h DMRStripHomeBandStep): idle while the strip is off and no band was handed on (nothing read and
// nothing handed: the tick's off path on every iPadOS, so a side Dock's Home Screen is never laid out again for it); else the room is handed
// on once per change, a new side only while there is a band.
static inline BOOL MSBDRStripBandIdle(BOOL on, double handed) { return !on && !(handed > 0.0); }
static inline BOOL MSBDRStripBandHandsOn(double room, double handed, BOOL right, BOOL handedRight) {
    return !(fabs(room - handed) < 0.25) || (room > 0.0 && right != handedRight);
}
// iPadOS's Today View on the Home Screen (slid in, or kept on page 1) lies at the left: the strip keeps off it there (not with the strip at the right).
static inline BOOL MSBDRStripTodayKeepsOff(BOOL todayShown, BOOL stripRight) { return todayShown && !stripRight; }
// The desktop files' and sticky notes' area with the band kept free (area: theirs without it; band: the strip's on the same screen). Their saved
// places stay shares of the area without it, so nothing is rewritten: an item that would lie in the band is shown beside it.
static inline MSBDRRect MSBDRStripAreaBeside(MSBDRRect area, MSBDRRect band, BOOL right) {
    if (band.w <= 0 || area.w <= 0) return area;
    MSBDRRect r = area;
    if (right) { double end = MIN(MSBDRMaxX(area), band.x); r.w = end - r.x; }
    else { double start = MAX(area.x, MSBDRMaxX(band)); r.w = MSBDRMaxX(area) - start; r.x = start; }
    if (r.w < 100.0) return area;   // (no sensible room beside it: as it was)
    return r;
}

// ---- a window dragged over it, and a card dragged out ----
// The drop zone: the band and kMSBDRStripDropBy past it, the desktop's height (x, y: the touch on the screen).
static inline BOOL MSBDRStripInDropZone(double x, double y, MSBDRRect band, BOOL right) {
    if (band.w <= 0 || band.h <= 0) return NO;
    if (y < band.y - kMSBDRStripDropBy || y > MSBDRMaxY(band) + kMSBDRStripDropBy) return NO;
    return right ? x >= band.x - kMSBDRStripDropBy : x <= MSBDRMaxX(band) + kMSBDRStripDropBy;
}
// A window let go over the drop zone goes into the strip (from where it was let go, into the slot open at the top; it comes back where it was
// before the drag): the strip can show (nothing over the windows, the windows in front) and the window can wait there (an engine's window of this
// desktop, not closing or going full screen). Any other drop is the drop it always was (its snap, Behind the Dock, the title bar's record).
static inline BOOL MSBDRStripDropTakes(BOOL inZone, BOOL canShow, BOOL windowJoins) { return inZone && canShow && windowJoins; }
// How far a touch is past the band, away from its edge (<= 0: inside it).
static inline double MSBDRStripPastBand(double x, MSBDRRect band, BOOL right) { return right ? band.x - x : x - MSBDRMaxX(band); }
// A card's press (a finger or a pointer's primary button): held: how long it is down; moved: how far it went from where it went down; up: let go.
typedef NS_ENUM(int, MSBDRStripPress) { MSBDRStripPressUndecided = 0, MSBDRStripPressTap = 1, MSBDRStripPressMenu = 2, MSBDRStripPressDrag = 3 };
static inline MSBDRStripPress MSBDRStripPressFor(double held, double moved, BOOL up, BOOL pointer) {
    if (moved >= (pointer ? kMSBDRStripPointerSlop : kMSBDRStripFingerSlop)) return MSBDRStripPressDrag;   // (a hold then a move too)
    if (!up) return MSBDRStripPressUndecided;
    return !pointer && held >= kMSBDRStripHold ? MSBDRStripPressMenu : MSBDRStripPressTap;   // (a finger's hold and release: the menu)
}
// A dragged card's size: the card's until kMSBDRStripGrowFrom past the band, then growing over kMSBDRStripGrowOver toward its window's size, held to
// the desktop (a window larger than the screen: the desktop's size, its shape kept) and to kMSBDRStripGrowMax times the card (its picture is a
// card's: the window itself grows out of it where it is let go). cw, ch: the card's picture; ww, wh: the window's.
static inline void MSBDRStripProxySize(double cw, double ch, double ww, double wh, MSBDRRect desk, double past, double *w, double *h) {
    double k = 1.0;
    if (ww > 0 && wh > 0 && desk.w > 0 && desk.h > 0) k = MIN(1.0, MIN(desk.w / ww, desk.h / wh));
    double tw = ww > 0 ? ww * k : cw, th = wh > 0 ? wh * k : ch;
    if (cw > 0 && ch > 0 && tw > 0 && th > 0) { double m = MIN(1.0, MIN(kMSBDRStripGrowMax * cw / tw, kMSBDRStripGrowMax * ch / th)); tw *= m; th *= m; }
    double t = (past - kMSBDRStripGrowFrom) / kMSBDRStripGrowOver;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    t = t * t * (3.0 - 2.0 * t);   // (smooth at both ends)
    if (w) *w = cw + (tw - cw) * t;
    if (h) *h = ch + (th - ch) * t;
}
// The window's frame where a card is let go: the grab point (gx, gy: its share of the card, 0 to 1) under the drop point (px, py; a point under the
// Dock or off the desktop is taken to the desktop's nearest point), the window at its size held to the desktop, then kept as our windows are kept
// (DMNativeClamp): the title bar under the menu bar and at least 40 pt above the desktop's end, at least 80 pt of it across the screen.
static inline MSBDRRect MSBDRStripDropFrame(double ww, double wh, double gx, double gy, double px, double py, MSBDRRect desk) {
    double k = 1.0;
    if (ww > 0 && wh > 0 && desk.w > 0 && desk.h > 0) k = MIN(1.0, MIN(desk.w / ww, desk.h / wh));
    double w = ww * k, h = wh * k;
    gx = gx < 0 ? 0 : (gx > 1 ? 1 : gx); gy = gy < 0 ? 0 : (gy > 1 ? 1 : gy);
    px = MAX(desk.x, MIN(px, MSBDRMaxX(desk))); py = MAX(desk.y, MIN(py, MSBDRMaxY(desk)));
    MSBDRRect f = { px - gx * w, py - gy * h, w, h };
    f.y = MAX(desk.y, MIN(f.y, MSBDRMaxY(desk) - 40.0));
    f.x = MAX(desk.x - f.w + 80.0, MIN(f.x, MSBDRMaxX(desk) - 80.0));
    return f;
}
// A card thrown (let go while moving): it lands where its speed takes it in kMSBDRStripFlick (vx, vy: points per second).
static inline void MSBDRStripFlickTo(double px, double py, double vx, double vy, double *ox, double *oy) {
    if (ox) *ox = px + (isfinite(vx) ? vx : 0.0) * kMSBDRStripFlick;
    if (oy) *oy = py + (isfinite(vy) ? vy : 0.0) * kMSBDRStripFlick;
}
// A card let go back inside the band (or its drag cancelled): it goes back to its slot, nothing is placed. Order is recency: no reorder by drag.
static inline BOOL MSBDRStripDropsBack(double x, MSBDRRect band, BOOL right) { return MSBDRStripPastBand(x, band, right) <= 0.0; }

// ---- the pointer and the finger ----
// x: the pointer across the screen as it is turned now (sw its width). At the strip's edge; past the band by kMSBDRStripLeaveBy (it has left it).
static inline BOOL MSBDRStripPointerAtEdge(double x, double sw, BOOL right) { return right ? x >= sw - kMSBDRStripEdgeAt : x <= kMSBDRStripEdgeAt; }
static inline BOOL MSBDRStripPointerLeft(double x, MSBDRRect band, BOOL right) { return right ? x < band.x - kMSBDRStripLeaveBy : x > MSBDRMaxX(band) + kMSBDRStripLeaveBy; }
// The finger's handle: drawn only while the strip has stepped aside with cards and no trackpad or mouse is attached (the pointer has the edge).
static inline BOOL MSBDRStripHandleShown(BOOL asideWithCards, BOOL pointerAttached) { return asideWithCards && !pointerAttached; }
// Its place: at the strip's screen edge, centred on the cards' part; its touch area: kMSBDRStripHandleTouchW wide at the edge, the handle's height
// and kMSBDRStripHandleTouchPad above and below, nothing more (an app's own edge swipe elsewhere on a window at the edge stays the app's).
static inline MSBDRRect MSBDRStripHandleRect(double sw, MSBDRRect span, BOOL right) {
    double cy = span.y + span.h / 2.0;
    return (MSBDRRect){ right ? sw - 2.0 - kMSBDRStripHandleW : 2.0, cy - kMSBDRStripHandleH / 2.0, kMSBDRStripHandleW, kMSBDRStripHandleH };
}
static inline MSBDRRect MSBDRStripHandleTouch(double sw, MSBDRRect span, BOOL right) {
    MSBDRRect h = MSBDRStripHandleRect(sw, span, right);
    return (MSBDRRect){ right ? sw - kMSBDRStripHandleTouchW : 0.0, h.y - kMSBDRStripHandleTouchPad, kMSBDRStripHandleTouchW, h.h + 2.0 * kMSBDRStripHandleTouchPad };
}
static inline BOOL MSBDRStripInRect(MSBDRRect r, double x, double y) { return r.w > 0 && r.h > 0 && x >= r.x && x <= MSBDRMaxX(r) && y >= r.y && y <= MSBDRMaxY(r); }
// The keys on a reveal by the Window menu: Up and Down move the selection (held at the ends), -1 = none yet (Down: the top card, Up: the last).
static inline int MSBDRStripKeyStep(int sel, int n, int dir) {
    if (n <= 0) return -1;
    if (sel < 0) return dir > 0 ? 0 : n - 1;
    int s = sel + (dir > 0 ? 1 : -1);
    return s < 0 ? 0 : (s >= n ? n - 1 : s);
}

// ---- nothing at rest ----
// The step's look is skipped while nothing it reads changed: a signature of the windows and the rest (MSBDRStripSigMix, FNV-1a over 64-bit
// words), and no time-bound work waiting (a reveal's end, a card being decided, a picture due, a pick or a relaunch on its way).
static inline uint64_t MSBDRStripSigMix(uint64_t h, uint64_t v) {
    for (int i = 0; i < 8; i++) { h ^= (v >> (i * 8)) & 0xff; h *= 1099511628211ull; }
    return h;
}
static inline BOOL MSBDRStripTickWorks(BOOL changed, BOOL timed) { return changed || timed; }
static inline BOOL MSBDRStripTickNeeded(BOOL on, BOOL active) { return on || active; }

// ---- the motion ----
// The i-th card's delay as the strip slides in (top to bottom, at most kMSBDRStripStaggerMax).
static inline double MSBDRStripStaggerAt(int i) { double d = i > 0 ? i * kMSBDRStripStagger : 0.0; return d > kMSBDRStripStaggerMax ? kMSBDRStripStaggerMax : d; }

// ---- the pictures ----
// The scale a window's picture is asked at (of its points, at the screen's scale): its size fitted into the card's box, never above 1.
static inline double MSBDRStripPicScale(double winW, double winH, double boxW, double boxH) {
    if (winW < 1.0 || winH < 1.0) return 0.0;
    double k = MIN(boxW / winW, boxH / winH);
    return k > 1.0 ? 1.0 : (k < 0.02 ? 0.02 : k);
}
// A window going into the strip is pictured right before (what you saw when you sent it): one minimize, a swap or a drag in always; in a burst
// (Minimize All, Home) only the one in front and any with no picture yet (one render, not one per window). has / age: its picture now.
static inline BOOL MSBDRStripPicAtEntry(BOOL has, double age, BOOL burst, BOOL front) {
    if (!has) return YES;
    if (!burst) return age > 0.5;   // (one taken this very moment is kept)
    return front && age > kMSBDRStripMinPicLife;
}
// A picture is kept for the cards shown and kMSBDRStripPicKeepMore more down the list (index: its place in the list).
static inline BOOL MSBDRStripPicKept(NSUInteger index, NSUInteger shown) { return index < shown + kMSBDRStripPicKeepMore; }

// ---- our own windows: one card per app (groups) ----
// A group's stack: up to 3 pictures, each kMSBDRStripStackStep lower and 4 % smaller than the one in front of it; a count over 3.
#define kMSBDRStripStackMax 3
#define kMSBDRStripStackStep 6.0
static inline int MSBDRStripStackShown(int windows) { return windows < 1 ? 0 : (windows > kMSBDRStripStackMax ? kMSBDRStripStackMax : windows); }
static inline BOOL MSBDRStripStackBadge(int windows) { return windows > kMSBDRStripStackMax; }
static inline MSBDRRect MSBDRStripStackRect(MSBDRRect front, int depth) {
    double k = pow(0.96, depth), w = front.w * k, h = front.h * k;
    return (MSBDRRect){ front.x + (front.w - w) / 2.0, front.y + (front.h - h) + depth * kMSBDRStripStackStep, w, h };
}
// The pictures the strip keeps for its cards (the step's trim, a memory warning): those of the list's first upTo cards. A card of our own windows
// stands for its app (its key in the list) while its pictures are its windows' (groupPics[key]: their picture keys, most recent first): it keeps
// the ones its stack shows. (The review of 1.8.8.4: the trim looked each picture up in the list by its own key, so as soon as more than 6
// pictures were held, every one of our own windows' pictures went and their cards fell back to the icon.)
static inline NSSet<NSString *> *MSBDRStripPicsFor(NSArray<NSString *> *list, NSUInteger upTo, NSDictionary<NSString *, NSArray<NSString *> *> *groupPics) {
    NSMutableSet<NSString *> *keep = [NSMutableSet set];
    for (NSUInteger i = 0; i < list.count && i < upTo; i++) {
        NSArray<NSString *> *g = groupPics[list[i]];
        if (!g) { [keep addObject:list[i]]; continue; }
        for (NSUInteger j = 0; j < g.count && j < (NSUInteger)kMSBDRStripStackMax; j++) [keep addObject:g[j]];
    }
    return keep;
}
