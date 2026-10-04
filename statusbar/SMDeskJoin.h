// SMDeskJoin.h -- the Stage Manager engine's one-desktop rule for transitions SpringBoard builds itself (4 Oct 2026). Plain Foundation (no
// SpringBoard API): included by StatusBar.x and by the Mac test tools/test-smdeskjoin.m.
// Stage Manager shows ONE stage per display, and activating an app means showing the stage that holds it. The engine already folds plain launches
// (an app with no layout roles) into the desktop (DMSMJoinDesktop) and adds Dock / Home Screen taps to it; but a transition SpringBoard builds
// with the roles already set -- the App Switcher's card of a minimized or left-out window, Cmd-Tab, Stage Manager's own drag and drop from the
// Dock, the strip -- showed that other stage ALONE: the desktop's windows vanished into a hidden stage, and the next launches joined the new one.
// Here, from what such a transition asks for and what the desktop has, whether to leave it as SpringBoard built it, or which windows the rewritten
// transition names: the desktop's windows (newest first, room left for the new ones: a stage holds 4) and the new ones.
#pragma once
#import <Foundation/Foundation.h>

// What the transition is besides its roles (any of these: left as SpringBoard built it).
enum {
    DMSMJoinOurs        = 1 << 0,   // our own request (its plan was written by us)
    DMSMJoinNotMain     = 1 << 1,   // on another display (the TV keeps Stage Manager's rules there)
    DMSMJoinToHome      = 1 << 2,   // to the Home Screen
    DMSMJoinToSwitcher  = 1 << 3,   // to the App Switcher
    DMSMJoinRemoval     = 1 << 4,   // a window is being closed in it
    DMSMJoinFloatCentre = 1 << 5,   // a floating (role 3) or centre (role 4) window: not a stage of windows
    DMSMJoinNonApp      = 1 << 6,   // a role holds something that is not an app's window (kept / emptied / the Home Screen)
    DMSMJoinOtherDesk   = 1 << 7,   // a window asked for lives on another Mac Switcher desktop (1.4): showing its stage is that desktop's switch
};
static const long long kDMSMJoinRoles[] = {1, 2, 5, 6};   // (the roles a window of a stage takes, first free first -- kSMNewWindowRoles)

// desktop: the desktop's windows, @{@"b": bundle, @"r": role, @"t": last interaction time}; asked: what the transition names, @{@"b": bundle,
// @"r": role}. Returns nil (leave it; *why says why), or the plan: @[bundle, role, isNew] for each window -- the kept desktop windows first
// (their own role when it is one of the four window roles, else a free one), then the new windows (free roles; the caller puts them in front).
static NSArray<NSArray *> *DMSMDeskJoinPlan(NSArray<NSDictionary *> *desktop, NSArray<NSDictionary *> *asked, int flags, NSString **why) {
    #define DMSM_LEAVE(text) do { if (why) *why = (text); return nil; } while (0)
    if (flags & DMSMJoinOurs) DMSM_LEAVE(@"our own request");
    if (flags & DMSMJoinNotMain) DMSM_LEAVE(@"another display");
    if (flags & DMSMJoinToHome) DMSM_LEAVE(@"to the Home Screen");
    if (flags & DMSMJoinToSwitcher) DMSM_LEAVE(@"to the App Switcher");
    if (flags & DMSMJoinRemoval) DMSM_LEAVE(@"a window is being closed");
    if (flags & DMSMJoinFloatCentre) DMSM_LEAVE(@"a floating or centre window");
    if (flags & DMSMJoinNonApp) DMSM_LEAVE(@"a role kept, emptied or not an app");
    if (flags & DMSMJoinOtherDesk) DMSM_LEAVE(@"a window of another desktop (that desktop's switch)");
    if (!asked.count) DMSM_LEAVE(@"no window asked for");
    if (!desktop.count) DMSM_LEAVE(@"no desktop to keep");
    NSMutableOrderedSet<NSString *> *deskB = [NSMutableOrderedSet orderedSet], *askedB = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *w in desktop) { NSString *b = w[@"b"]; if (![b isKindOfClass:[NSString class]] || !b.length) DMSM_LEAVE(@"a desktop window without an app"); [deskB addObject:b]; }
    for (NSDictionary *w in asked) { NSString *b = w[@"b"]; if (![b isKindOfClass:[NSString class]] || !b.length) DMSM_LEAVE(@"an asked window without an app"); [askedB addObject:b]; }
    NSMutableArray<NSString *> *fresh = [NSMutableArray array];   // (asked, not on the desktop: in the order SpringBoard named them)
    for (NSString *b in askedB) if (![deskB containsObject:b]) [fresh addObject:b];
    BOOL leavesOut = NO;
    for (NSString *b in deskB) if (![askedB containsObject:b]) { leavesOut = YES; break; }
    if (!fresh.count) DMSM_LEAVE(@"only the desktop's own windows");      // (the desktop itself, or some of its windows: SpringBoard's own arrangement)
    if (!leavesOut) DMSM_LEAVE(@"it keeps every desktop window");        // (a window added to the desktop by Stage Manager itself)
    if (fresh.count >= 4) DMSM_LEAVE(@"a whole other stage of four");   // (nothing of the desktop could stay: Stage Manager's stage, as it is)
    // The desktop's windows newest first, as many as leave room for the new ones (a stage holds four windows: the oldest are left out, as when a
    // fifth app opens -- DMSMJoinDesktop).
    NSArray<NSDictionary *> *byTime = [desktop sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long ta = [a[@"t"] longLongValue], tb = [b[@"t"] longLongValue];
        return ta > tb ? NSOrderedAscending : (ta < tb ? NSOrderedDescending : NSOrderedSame);
    }];
    NSUInteger room = 4 - fresh.count;
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    NSMutableSet<NSString *> *keptB = [NSMutableSet set];
    for (NSDictionary *w in byTime) { if (kept.count >= room) break; if ([keptB containsObject:w[@"b"]]) continue; [kept addObject:w]; [keptB addObject:w[@"b"]]; }
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    NSMutableArray<NSArray *> *plan = [NSMutableArray array];
    NSMutableArray<NSString *> *needRole = [NSMutableArray array];
    for (NSDictionary *w in kept) {
        long long r = [w[@"r"] longLongValue];
        BOOL windowRole = NO;
        for (size_t i = 0; i < sizeof(kDMSMJoinRoles) / sizeof(kDMSMJoinRoles[0]); i++) if (kDMSMJoinRoles[i] == r) windowRole = YES;
        if (windowRole && ![used containsObject:@(r)]) { [used addObject:@(r)]; [plan addObject:@[w[@"b"], @(r), @NO]]; }
        else [needRole addObject:w[@"b"]];
    }
    long long (^freeRole)(void) = ^long long {
        for (size_t i = 0; i < sizeof(kDMSMJoinRoles) / sizeof(kDMSMJoinRoles[0]); i++) if (![used containsObject:@(kDMSMJoinRoles[i])]) { [used addObject:@(kDMSMJoinRoles[i])]; return kDMSMJoinRoles[i]; }
        return 0;
    };
    for (NSString *b in needRole) { long long r = freeRole(); if (!r) DMSM_LEAVE(@"no free role"); [plan addObject:@[b, @(r), @NO]]; }
    for (NSString *b in fresh) { long long r = freeRole(); if (!r) DMSM_LEAVE(@"no free role"); [plan addObject:@[b, @(r), @YES]]; }
    if (why) *why = [NSString stringWithFormat:@"%lu desktop window(s) kept%@, %lu joining", (unsigned long)kept.count, kept.count < desktop.count ? @" (the oldest left out)" : @"", (unsigned long)fresh.count];
    return plan;
    #undef DMSM_LEAVE
}
