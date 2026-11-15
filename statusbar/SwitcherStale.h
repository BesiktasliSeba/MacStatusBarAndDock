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
//  - And it went away because the user quit it (or it crashed, as before: KT decides about crashes). "Not running" alone is no proof of a quit:
//    iPadOS ends apps in the background for memory (a 3-4 GB iPad ends Safari behind a game), at a background time-out, for an update or at the
//    watchdog, and keeps their cards: the user opens the app again from its card. The clean-up took those cards 15 to 30 s later, with Aerial,
//    Zetsu, MilkyWay4 and no engine (audit M3 of 1.8.7.2). Now only the card of an app on `quit` goes: the apps whose last end was the user's
//    quit (a kill for the user's quit -- the App Switcher's swipe-up, our Force Quit and red light -- then its end; not the prewarm quit set,
//    which an app stays on while it runs again without coming in front, review of the M3 fix) or a crash (MSBDExitContextIsCrash, below).
#ifndef MSBD_SWITCHER_STALE_H
#define MSBD_SWITCHER_STALE_H
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <signal.h>

static const double kMSBDStaleCardGrace = 4.0;
// shown: the apps that have a card; running: the apps running now; inFront: the apps that were in front since SpringBoard started; quit: the apps
// whose last end was the user's quit or a crash (nil: none); front: the app in front now (nil: none); since: per app, when its card was first seen stale (kept
// here: started, kept, or dropped once the card is not stale, gone, or taken); now: seconds on one clock. Returns the apps whose cards go now,
// sorted.
static inline NSArray<NSString *> *MSBDStaleCards(NSSet<NSString *> *shown, NSSet<NSString *> *running, NSSet<NSString *> *inFront, NSSet<NSString *> *quit,
                                                  NSString *front, NSMutableDictionary<NSString *, NSNumber *> *since, double now) {
    NSMutableArray<NSString *> *stale = [NSMutableArray array];
    for (NSString *b in shown) {
        BOOL gone = [inFront containsObject:b] && [quit containsObject:b] && ![running containsObject:b] && ![b isEqualToString:front];
        if (!gone) { [since removeObjectForKey:b]; continue; }   // (running, in front, ended by iPadOS, or never in front since the start: not stale)
        NSNumber *first = since[b];
        if (!first) { since[b] = @(now); continue; }   // (first seen stale: the grace starts, nothing goes yet)
        if (now - first.doubleValue >= kMSBDStaleCardGrace) [stale addObject:b];
    }
    for (NSString *b in [since.allKeys copy]) if (![shown containsObject:b]) [since removeObjectForKey:b];   // (no card any more: nothing to follow)
    for (NSString *b in stale) [since removeObjectForKey:b];
    return [stale sortedArrayUsingSelector:@selector(compare:)];
}

// How an app ended, from SpringBoard's exit callback (-[SBApplication _didExitWithContext:], an FBProcessExitContext): its RunningBoard exit status
// (underlyingContext.status), which carries the kernel's exit reason as its namespace (domain) and code. A crash is a fault signal: the SIGNAL
// namespace with SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGBUS, SIGSEGV or SIGSYS, the same as RunningBoard's own -isCrash (tools/test-switcherstale.sh
// runs both on every namespace on the Mac, and FrontBoard's crash bit agrees). Not a crash: an end for memory (JETSAM), a kill (SIGKILL, SIGTERM),
// the watchdog, a time-out, a quit, the app's own exit, and an exit whose status cannot be read.
static const unsigned kMSBDExitDomainSignal = 2;   // (OS_REASON_SIGNAL, xnu's sys/reason.h)
static inline BOOL MSBDExitStatusIsCrash(unsigned domain, unsigned long long code) {
    if (domain != kMSBDExitDomainSignal) return NO;
    switch (code) {
        case SIGILL: case SIGTRAP: case SIGABRT: case SIGFPE: case SIGBUS: case SIGSEGV: case SIGSYS: return YES;
        default: return NO;
    }
}
static inline BOOL MSBDExitContextIsCrash(id context) {
    SEL under = NSSelectorFromString(@"underlyingContext"), status = NSSelectorFromString(@"status");
    SEL domain = NSSelectorFromString(@"domain"), code = NSSelectorFromString(@"code");
    id rbs = [context respondsToSelector:under] ? ((id (*)(id, SEL))objc_msgSend)(context, under) : nil;
    id st = [rbs respondsToSelector:status] ? ((id (*)(id, SEL))objc_msgSend)(rbs, status) : nil;
    if (![st respondsToSelector:domain] || ![st respondsToSelector:code]) return NO;
    return MSBDExitStatusIsCrash(((unsigned (*)(id, SEL))objc_msgSend)(st, domain), ((unsigned long long (*)(id, SEL))objc_msgSend)(st, code));
}

#endif
