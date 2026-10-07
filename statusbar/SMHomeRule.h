// SMHomeRule.h -- the Stage Manager engine's Home rule: the windows stay on screen when you go Home, as with Aerial and Zetsu (sm-free, 4 Oct 2026).
// Plain Foundation (no SpringBoard API): included by StatusBar.x (early: the desktop choice of the joins and the restore uses DMSMStageIsDesktop;
// and through SMHome.h) and by the Mac test tools/test-smhomerule.m.
// SpringBoard's Home (16.7.7 disassembled): the Home button, Cmd-H (-[SpringBoard _handleGotoHomeScreenShortcut:] runs the button's single-press
// actions), a pointer click on the Home bar, the end of a Home gesture, Home from the App Switcher all make one kind of workspace transition: its
// application context names the Home Screen entity as the activating entity and no window roles (SBWorkspaceActivateSpringBoardWithResult, label
// "ActivateSpringBoard"; the switcher's -_configureRequest:forSwitcherTransitionRequest:withEventLabel: for unlocked environment mode 1). The layout
// state built from it is the Home Screen's (environment mode 1), which shows no stage: every window of the desktop went with it. With the Home
// Screen behind the windows (SMDesktop.h) the windows are already "on the Home Screen"; so the transition is rewritten as it is finalized into the
// desktop's windows in their roles (application mode, the newest window in front) -- only a full-screen window leaves, as a full-screen app does
// with Aerial (it goes to the background; its window comes back with the app). A desktop of a full-screen window alone, an empty desktop, a
// transition our own code asked for as a real Home (the desktop's last window, 1.4's empty desktop), and anything not leaving the desktop: Home as
// SpringBoard built it.
#pragma once
#import <Foundation/Foundation.h>
#include <math.h>

// What the transition is besides "the Home Screen" (any of these: left as SpringBoard built it).
enum {
    DMSMHomeOurs          = 1 << 0,   // our own request / plan
    DMSMHomeRealHome      = 1 << 1,   // our own code asked for a real Home just now (DMSMGoHomeForReal)
    DMSMHomeNotMain       = 1 << 2,   // on another display (the TV)
    DMSMHomeBackground    = 1 << 3,   // a background activation (nothing shown)
    DMSMHomeLocked        = 1 << 4,   // the UI is locked (Lock Screen flows)
    DMSMHomeRemoval       = 1 << 5,   // a window is being closed in it (an app that ended)
    DMSMHomeNotHome       = 1 << 6,   // the activating entity is not the Home Screen
    DMSMHomeRolesSet      = 1 << 7,   // a window role holds an app (not a plain Home)
    DMSMHomeSwitcherDesk  = 1 << 8,   // (not a refusal) the App Switcher on screen was opened from the desktop
};
// desk: the windows of the stage on screen that the transition leaves, @{@"id": the window's identifier (its scene: two windows of one app are two
// entries), @"r": role, @"t": last interaction time, @"p": sizing policy (2 = full screen)}. roles: SpringBoard's window roles in their order
// (1, 2, 5, 6, 7, 8, 9 on 16.7.7). requestedEnv: the context's requested unlocked environment mode (0 none, 1 Home, 2 switcher, 3 application);
// prevEnv: the layout state it starts from (1 Home, 2 App Switcher, 3 application, 0 unknown); prevShowsDesk: that layout state shows `desk`.
// Returns nil (leave it; *why says why) or @{@"keep": @[@[id, @(role)], ...] (each window that stays, in its role), @"empty": @[roles to empty],
// @"front": id (the window in front: keyboard focus), @"away": @[ids] (full-screen windows that leave), @"atHome": @YES when nothing leaves -- the
// person was on the Home Screen already, behind the windows (the Home Screen's own Home press applies: close a folder, the App Library...)}.
// (noinline: its own range in the release crash map, tools/test-crashstep.sh)
__attribute__((noinline)) static NSDictionary *DMSMHomePlan(NSArray<NSDictionary *> *desk, const long long *roles, size_t nRoles, int flags, long long requestedEnv,
                                  long long prevEnv, BOOL prevShowsDesk, NSString **why) {
    #define DMSM_HOME_LEAVE(text) do { if (why) *why = (text); return nil; } while (0)
    if (flags & DMSMHomeOurs) DMSM_HOME_LEAVE(@"our own request");
    if (flags & DMSMHomeRealHome) DMSM_HOME_LEAVE(@"a real Home asked for by our own code");
    if (flags & DMSMHomeNotMain) DMSM_HOME_LEAVE(@"another display");
    if (flags & DMSMHomeBackground) DMSM_HOME_LEAVE(@"a background activation");
    if (flags & DMSMHomeLocked) DMSM_HOME_LEAVE(@"the UI is locked");
    if (flags & DMSMHomeRemoval) DMSM_HOME_LEAVE(@"a window is being closed");
    if (flags & DMSMHomeNotHome) DMSM_HOME_LEAVE(@"not the Home Screen");
    if (flags & DMSMHomeRolesSet) DMSM_HOME_LEAVE(@"a window role is set");
    if (requestedEnv != 0 && requestedEnv != 1) DMSM_HOME_LEAVE(([NSString stringWithFormat:@"asks for environment %lld", requestedEnv]));
    if (prevEnv == 3) { if (!prevShowsDesk) DMSM_HOME_LEAVE(@"the stage on screen is not the desktop"); }
    else if (prevEnv == 2) { if (!(flags & DMSMHomeSwitcherDesk)) DMSM_HOME_LEAVE(@"the App Switcher was not opened from the desktop"); }
    else DMSM_HOME_LEAVE(prevEnv == 1 ? @"already on the Home Screen" : @"where it starts is not known");
    if (!roles || nRoles < 2) DMSM_HOME_LEAVE(@"no window roles");
    if (!desk.count) DMSM_HOME_LEAVE(@"no windows on the desktop");
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    NSMutableArray<NSString *> *away = [NSMutableArray array];
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (NSDictionary *w in desk) {
        NSString *ident = w[@"id"];
        if (![ident isKindOfClass:[NSString class]] || !ident.length) DMSM_HOME_LEAVE(@"a window without an identifier");
        if ([ids containsObject:ident]) DMSM_HOME_LEAVE(@"a window listed twice");
        [ids addObject:ident];
        if (![w[@"r"] isKindOfClass:[NSNumber class]] || ![w[@"t"] isKindOfClass:[NSNumber class]] || ![w[@"p"] isKindOfClass:[NSNumber class]]) DMSM_HOME_LEAVE(@"a window not read whole");
        if ([w[@"p"] longLongValue] == 2) [away addObject:ident]; else [kept addObject:w];
    }
    if (!kept.count) DMSM_HOME_LEAVE(@"only a full-screen window: it goes Home as Apple has it");
    if (kept.count > nRoles) DMSM_HOME_LEAVE(@"more windows than window roles");
    // The roles: nothing leaves -- each window keeps its own role (the same layout as on screen: no window moves); a full-screen window leaves --
    // the rest closes up in role order, as SpringBoard's own Minimize does (a stage always has its primary window).
    NSArray<NSDictionary *> *byRole = [kept sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        long long ra = [a[@"r"] longLongValue], rb = [b[@"r"] longLongValue];
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];
    BOOL own = away.count == 0;
    if (own) {   // (only when every window holds a window role of its own, once each, the primary among them)
        NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
        BOOL primary = NO;
        for (NSDictionary *w in byRole) {
            long long r = [w[@"r"] longLongValue];
            BOOL isRole = NO;
            for (size_t i = 0; i < nRoles; i++) if (roles[i] == r) isRole = YES;
            if (!isRole || [seen containsObject:@(r)]) { own = NO; break; }
            [seen addObject:@(r)];
            if (r == roles[0]) primary = YES;
        }
        if (!primary) own = NO;
    }
    NSMutableArray<NSArray *> *keep = [NSMutableArray array];
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    for (NSUInteger i = 0; i < byRole.count; i++) {
        long long r = own ? [byRole[i][@"r"] longLongValue] : roles[i];
        [keep addObject:@[byRole[i][@"id"], @(r)]];
        [used addObject:@(r)];
    }
    NSMutableArray<NSNumber *> *empty = [NSMutableArray array];
    for (size_t i = 0; i < nRoles; i++) if (![used containsObject:@(roles[i])]) [empty addObject:@(roles[i])];
    NSDictionary *front = nil;   // (the newest interaction; a tie goes to the lower role)
    for (NSDictionary *w in byRole) if (!front || [w[@"t"] longLongValue] > [front[@"t"] longLongValue]) front = w;
    if (why) *why = [NSString stringWithFormat:@"%lu window(s) stay%@%@", (unsigned long)keep.count,
                     away.count ? [NSString stringWithFormat:@", %lu full-screen window(s) go to the background", (unsigned long)away.count] : @"",
                     own ? @" in their own roles" : @" (roles closed up)"];
    return @{@"keep": keep, @"empty": empty, @"front": front[@"id"], @"away": away, @"atHome": @(away.count == 0)};
    #undef DMSM_HOME_LEAVE
}

// The App Switcher's bookkeeping after SpringBoard finalized a transition (SMHome.h DMSMHomeNoteResult), decided by where SpringBoard WENT (the
// context's resulting layout state), not by what it asked for: an App Switcher opened by the Home gesture is followed by SpringBoard's own
// transitions inside it ("SBSwitcherControllerEventLabelFollowupRotation-N", no environment asked for), which read as "the switcher was left" and
// forgot the desktop -- Home from that switcher then dropped the windows (1.3.8 logic test H-1). resultEnv / prevEnv: 1 Home, 2 App Switcher,
// 3 application, 0 not known. Returns 1 = remember the stage it left (the App Switcher opened from the desktop: application mode with a window that is
// not full screen), 0 = keep what is remembered (still in the App Switcher; or where it went is not known), -1 = forget.
// label: the transition request's event label. The transition SpringBoard starts as a switcher gesture begins ("SBFluidSwitcherGesture",
// -[SBFluidSwitcherGestureManager _startFluidSwitcherTransactionForGestureRecognizer:]) is provisional -- its layout state is the gesture's own, not a
// destination: a swipe up INSIDE the App Switcher made one ("3 from 2") 30 ms in, the desktop was forgotten, and the Home it ended in (whose previous
// layout state is still the App Switcher) dropped the windows (1.3.9 device pass). Kept: the gesture's final transition decides.
static int DMSMSwitcherNote(long long resultEnv, long long prevEnv, BOOL prevHasWindow, NSString *label) {
    if ([label isKindOfClass:[NSString class]] && [label isEqualToString:@"SBFluidSwitcherGesture"]) return 0;
    if (resultEnv == 2) {
        if (prevEnv == 2) return 0;
        return (prevEnv == 3 && prevHasWindow) ? 1 : -1;
    }
    return resultEnv == 0 ? 0 : -1;
}

// The Home gesture keeps the desktop still (SMHome.h B2, Reduce Motion off): the gesture runs over a desktop of windows (overDesk), the index it asks
// about is the stage it took -- the one under the finger (selectedIndex) -- and that stage is the desktop (takenIsDesk); not once the finger has
// held still in the App Switcher's range for 0.3 s (holdFrames: SpringBoard's own count, at fps frames a second), and not on a sideways swipe along
// the bottom edge (|x| > |y| of the gesture's translation: switching to a neighbouring stage moves the stage sideways with the finger as Apple has
// it -- 1.3.9 logic test L-2).
static BOOL DMSMHGKeepStill(BOOL overDesk, BOOL selectedIndex, BOOL takenIsDesk, long long holdFrames, long long fps, double tx, double ty) {
    if (!overDesk || !selectedIndex || !takenIsDesk) return NO;
    if (fabs(tx) > fabs(ty)) return NO;
    return holdFrames <= (long long)(0.3 * (double)(fps > 0 ? fps : 60));
}

// Is a recent stage "the desktop" that a launch joins, SpringBoard's own stage request merges with, or the restore brings back after a respring?
// shown: its windows that are not minimized; anyWindow: one of them is not full screen; onScreen: it is the stage on screen now; holdsAsked: it
// holds the app being opened / a window asked for. A stage of full-screen windows only that is not on screen is an app in full screen sent to the
// background (a Home from it, Apple's or ours), not a desktop: it came back full screen behind the next app opened and after every respring
// (1.3.8 logic test H-3). On screen it is joined over (native full screen that other windows come over); asked for, it is shown as it is.
static BOOL DMSMStageIsDesktop(NSUInteger shown, BOOL anyWindow, BOOL onScreen, BOOL holdsAsked) {
    return shown > 0 && (anyWindow || onScreen || holdsAsked);
}
