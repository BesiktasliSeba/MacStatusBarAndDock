// RecentStripRule.h: the recent windows strip's rules (1.8.8.2 F29, KT 20 Nov: "it can be like on macos"). Plain Foundation and C, no UIKit:
// SpringBoard's part is statusbar/RecentStrip.h, the Settings rows common/OwnPageRows.h, the Mac test tools/test-recentstrip.sh.
//  - the order: the recent windows' apps, most recent first, the one in front never in it; a pick swaps (the window picked comes forward and the one
//    that was in front takes its slot), any other change of the front puts the window that left it at the top;
//  - when the strip shows (on its own on the desktop, or brought out over the windows) and when it steps aside;
//  - its place on the screen: the side, the band, the cards, how many fit;
//  - the pointer at the edge and its leaving, a window over the cards, a card's picture size and when a picture is due.
#pragma once
#import <Foundation/Foundation.h>
#include <math.h>

// Where it runs: iPadOS 15 (the window pictures without SpringBoard waiting are read and verified there only: statusbar/MacSwitcher.h
// DMMSWAsyncPicturesOK). The Settings row and the strip follow this one rule.
static inline BOOL MSBDRecentStripOS(long major) { return major == 15; }
#define kMSBDRStripMax        6        // at most this many cards (a small cap, as Stage Manager's)
#define kMSBDRStripEdgeGap    14.0     // a card's distance from the screen's edge
#define kMSBDRStripCardGap    18.0     // between two cards
#define kMSBDRStripEnds       24.0     // the cards' run keeps this far from the top and the bottom of the desktop
#define kMSBDRStripCoverSlack 4.0      // a window that overlaps the cards' part by this much or less does not cover it
#define kMSBDRStripEdgeAt     2.0      // the pointer this close to the strip's screen edge is at the edge
#define kMSBDRStripLeaveBy    40.0     // the pointer this far past the band has left it
#define kMSBDRStripPicLife    30.0     // a picture of a window on screen is taken again as the strip comes when older than this (s)
#define kMSBDRStripMinPicLife 10.0     // a minimize takes no new picture of a window pictured this recently (s)

// ---- the order ----
// order: the recent windows' apps, most recent first (never the one in front). present: the apps with a window on this desktop now, minimized
// ones too, from the front one back as they lie (apps new to the list join its end in that order). was / now: the app in front at the last look
// and now (nil: none). picked:
// the app a pick asked for (nil: none). The steps: apps gone leave; apps new to the list go at its end; then, if the front changed, the new front
// leaves the list and the one that was in front goes into its slot when it was the pick, or to the top.
static inline void MSBDRStripOrderStep(NSMutableArray<NSString *> *order, NSString *was, NSString *now, NSString *picked, NSArray<NSString *> *present) {
    if (!order) return;
    NSSet<NSString *> *here = [NSSet setWithArray:present ?: @[]];
    for (NSInteger i = (NSInteger)order.count - 1; i >= 0; i--) if (![here containsObject:order[(NSUInteger)i]]) [order removeObjectAtIndex:(NSUInteger)i];
    for (NSString *b in present) if (![order containsObject:b] && ![b isEqualToString:now ?: @""]) [order addObject:b];
    if ([now ?: @"" isEqualToString:was ?: @""]) { if (now.length) [order removeObject:now]; return; }
    NSUInteger slot = now.length ? [order indexOfObject:now] : NSNotFound;
    if (now.length) [order removeObject:now];
    if (!was.length || ![here containsObject:was]) return;   // (the window that was in front went: nothing takes a slot)
    [order removeObject:was];
    BOOL swap = now.length && picked.length && [picked isEqualToString:now] && slot != NSNotFound && slot <= order.count;
    [order insertObject:was atIndex:swap ? slot : 0];
}
// The cards: the first ones of the order, at most fit (and kMSBDRStripMax).
static inline NSArray<NSString *> *MSBDRStripItems(NSArray<NSString *> *order, NSUInteger fit) {
    NSUInteger n = MIN(MIN(order.count, fit), (NSUInteger)kMSBDRStripMax);
    return n ? [order subarrayWithRange:NSMakeRange(0, n)] : @[];
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
    int revealed;      // the pointer at the edge, or Window > Show Recent Windows, brought it out
} MSBDRStripState;
typedef NS_ENUM(int, MSBDRStripShow) { MSBDRStripHidden = 0, MSBDRStripOnDesktop = 1, MSBDRStripOverWindows = 2 };
static inline MSBDRStripShow MSBDRStripShowFor(MSBDRStripState s) {
    if (!s.on || s.items <= 0 || !s.calm || !s.windowsFront) return MSBDRStripHidden;
    if (s.revealed) return MSBDRStripOverWindows;
    if (!s.windowShown || s.covered) return MSBDRStripHidden;   // (stepped aside: the pointer at the edge or the Window menu bring it)
    return MSBDRStripOnDesktop;
}
// A reveal may begin: the strip has something to show and has stepped aside (not shown on its own now).
static inline BOOL MSBDRStripMayReveal(MSBDRStripState s) {
    if (!s.on || s.items <= 0 || !s.calm || !s.windowsFront) return NO;
    s.revealed = 0;
    return MSBDRStripShowFor(s) == MSBDRStripHidden;
}

// ---- the place ----
typedef struct { double x, y, w, h; } MSBDRRect;
static inline double MSBDRMaxX(MSBDRRect r) { return r.x + r.w; }
static inline double MSBDRMaxY(MSBDRRect r) { return r.y + r.h; }
// The side: the left edge, or the right one with the Dock at Left (as macOS moves its strip when the Dock is on the left).
static inline BOOL MSBDRStripOnRight(BOOL dockAtLeft) { return dockAtLeft; }
// A card's box: its width from the screen's short side (80 to 118 pt), its height 78 % of that.
static inline double MSBDRStripCardW(double sw, double sh) { double w = round(MIN(sw, sh) * 0.115); return w < 80.0 ? 80.0 : (w > 118.0 ? 118.0 : w); }
static inline double MSBDRStripCardH(double sw, double sh) { return round(MSBDRStripCardW(sw, sh) * 0.78); }
// How many cards fit the desktop's height (usable: the desktop below the menu bar and above the Dock), at most kMSBDRStripMax.
static inline int MSBDRStripFit(double sw, double sh, MSBDRRect usable) {
    double ch = MSBDRStripCardH(sw, sh), room = usable.h - 2.0 * kMSBDRStripEnds + kMSBDRStripCardGap;
    int n = room > 0 ? (int)floor(room / (ch + kMSBDRStripCardGap)) : 0;
    return n < 0 ? 0 : (n > kMSBDRStripMax ? kMSBDRStripMax : n);
}
// The layout of n cards (n <= MSBDRStripFit): aspect[i] the window's width over its height (0: not known, a 4:3 card). band: the strip's part of the
// screen (its side's edge to 14 pt past the cards, the desktop's height); cards[i]: the picture's place, the window's shape fitted into its box,
// the boxes centred in the desktop's height. Returns how many were laid out.
static inline int MSBDRStripLayout(double sw, double sh, MSBDRRect usable, BOOL right, int n, const double *aspect, MSBDRRect *band, MSBDRRect *cards) {
    double cw = MSBDRStripCardW(sw, sh), ch = MSBDRStripCardH(sw, sh);
    int fit = MSBDRStripFit(sw, sh, usable);
    if (n > fit) n = fit;
    if (n < 0) n = 0;
    double bx = right ? MSBDRMaxX(usable) - 2.0 * kMSBDRStripEdgeGap - cw : usable.x;
    if (band) *band = (MSBDRRect){ bx, usable.y, cw + 2.0 * kMSBDRStripEdgeGap, usable.h };
    double total = n * ch + (n > 1 ? (n - 1) * kMSBDRStripCardGap : 0.0), top = usable.y + floor((usable.h - total) / 2.0);
    for (int i = 0; i < n; i++) {
        double a = aspect && aspect[i] > 0.0 ? aspect[i] : 4.0 / 3.0;
        if (a < 0.3) a = 0.3;
        if (a > 3.0) a = 3.0;
        double w = cw, h = round(cw / a);
        if (h > ch) { h = ch; w = round(ch * a); }
        double x = bx + kMSBDRStripEdgeGap + floor((cw - w) / 2.0), y = top + i * (ch + kMSBDRStripCardGap) + floor((ch - h) / 2.0);
        if (cards) cards[i] = (MSBDRRect){ x, y, w, h };
    }
    return n;
}
// The cards' part of the edge: the band across the cards' run (with the corner icons' 10 pt below the last one).
static inline MSBDRRect MSBDRStripCardsSpan(MSBDRRect band, const MSBDRRect *cards, int n) {
    if (n <= 0 || !cards) return (MSBDRRect){ band.x, band.y, band.w, 0 };
    double top = cards[0].y, bottom = MSBDRMaxY(cards[0]);
    for (int i = 1; i < n; i++) { top = MIN(top, cards[i].y); bottom = MAX(bottom, MSBDRMaxY(cards[i])); }
    return (MSBDRRect){ band.x, top - 8.0, band.w, bottom - top + 18.0 };
}
// A window (its frame on the screen) covers the cards' part when it overlaps it by more than the slack each way.
static inline BOOL MSBDRStripCovers(MSBDRRect span, MSBDRRect win) {
    if (span.h <= 0 || win.w <= 0 || win.h <= 0) return NO;
    double ox = MIN(MSBDRMaxX(span), MSBDRMaxX(win)) - MAX(span.x, win.x), oy = MIN(MSBDRMaxY(span), MSBDRMaxY(win)) - MAX(span.y, win.y);
    return ox > kMSBDRStripCoverSlack && oy > kMSBDRStripCoverSlack;
}

// ---- the pointer ----
// x: the pointer across the screen as it is turned now (sw its width). At the strip's edge; past the band by kMSBDRStripLeaveBy (it has left it).
static inline BOOL MSBDRStripPointerAtEdge(double x, double sw, BOOL right) { return right ? x >= sw - kMSBDRStripEdgeAt : x <= kMSBDRStripEdgeAt; }
static inline BOOL MSBDRStripPointerLeft(double x, MSBDRRect band, BOOL right) { return right ? x < band.x - kMSBDRStripLeaveBy : x > MSBDRMaxX(band) + kMSBDRStripLeaveBy; }

// ---- the pictures ----
// The scale a window's picture is asked at (of its points, at the screen's scale): its size fitted into the card's box, never above 1.
static inline double MSBDRStripPicScale(double winW, double winH, double boxW, double boxH) {
    if (winW < 1.0 || winH < 1.0) return 0.0;
    double k = MIN(boxW / winW, boxH / winH);
    return k > 1.0 ? 1.0 : (k < 0.02 ? 0.02 : k);
}
// A picture is due as the strip comes: none yet, or one of a window on screen older than kMSBDRStripPicLife (a minimized window keeps the one it has).
static inline BOOL MSBDRStripPicDue(BOOL has, double age, BOOL onScreen) { return !has || (onScreen && age > kMSBDRStripPicLife); }
// A minimize takes a picture first of a window with none, or of the one in front unless its picture is under kMSBDRStripMinPicLife seconds old: a
// window behind keeps the one it got as it left the front (Minimize All and Home minimize every window at once: one picture, not one each).
static inline BOOL MSBDRStripPicAtMinimize(BOOL has, double age, BOOL front) { return !has || (front && age > kMSBDRStripMinPicLife); }
