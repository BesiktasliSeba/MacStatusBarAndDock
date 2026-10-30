// SwitcherStale.h -- which App Switcher cards the stale-card clean-up takes away (StatusBar.x DMCleanStaleSwitcherCards), plain Foundation so the
// Mac test (tools/test-switcherstale.m) runs this very code.
//  - iPadOS keeps the App Switcher's cards across a respring (SpringBoard saves them, SBRecentAppLayoutsPersister) and opens an app again from its
//    card: a card whose app is not running is the normal state after a respring, and right after the one a window engine switch makes, every card
//    is. Those cards are the user's. The clean-up took every card whose app was not running (4 s after it first saw it so), so 35 s after the
//    switch from Stage Manager to Aerial KT's Weather, App Store and Settings cards were gone (17.5.1, 29 Oct; the same since the clean-up came).
//  - A stale card is one an app left behind by going away while this SpringBoard ran: the user had it in front since SpringBoard started, it is
//    not running now, it is not the app in front, and it stayed so for kMSBDStaleCardGrace s (a launch can show its card before the app is listed
//    as running). The card of an app that was never in front since the start -- one SpringBoard brought back from before, or one whose app only
//    dasd started (a prewarm) -- stays, as iPadOS keeps it.
#ifndef MSBD_SWITCHER_STALE_H
#define MSBD_SWITCHER_STALE_H
#import <Foundation/Foundation.h>

static const double kMSBDStaleCardGrace = 4.0;
// shown: the apps that have a card; running: the apps running now; inFront: the apps that were in front since SpringBoard started; front: the app in
// front now (nil: none); since: per app, when its card was first seen stale (kept here: started, kept, or dropped once the card is not stale, gone,
// or taken); now: seconds on one clock. Returns the apps whose cards go now, sorted.
static inline NSArray<NSString *> *MSBDStaleCards(NSSet<NSString *> *shown, NSSet<NSString *> *running, NSSet<NSString *> *inFront, NSString *front,
                                                  NSMutableDictionary<NSString *, NSNumber *> *since, double now) {
    NSMutableArray<NSString *> *stale = [NSMutableArray array];
    for (NSString *b in shown) {
        BOOL gone = [inFront containsObject:b] && ![running containsObject:b] && ![b isEqualToString:front];
        if (!gone) { [since removeObjectForKey:b]; continue; }   // (running, in front, or never in front since the start: not stale)
        NSNumber *first = since[b];
        if (!first) { since[b] = @(now); continue; }   // (first seen stale: the grace starts, nothing goes yet)
        if (now - first.doubleValue >= kMSBDStaleCardGrace) [stale addObject:b];
    }
    for (NSString *b in [since.allKeys copy]) if (![shown containsObject:b]) [since removeObjectForKey:b];   // (no card any more: nothing to follow)
    for (NSString *b in stale) [since removeObjectForKey:b];
    return [stale sortedArrayUsingSelector:@selector(compare:)];
}

#endif
