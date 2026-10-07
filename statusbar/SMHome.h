// SMHome.h -- the Stage Manager engine at Home: the windows stay on screen, like Aerial's and Zetsu's (sm-free, 4 Oct 2026). Included by StatusBar.x
// after SMLimit.h (every DMSM helper it uses is defined above that point; the few StatusBar.x calls into it are declared before their use).
//  A. Home keeps the windows (SMHomeRule.h has the why and the rule; Mac test tools/test-smhomerule.sh): the Home Screen transition is rewritten, as
//     it is finalized, into the desktop's windows in their roles; a full-screen window goes to the background. A person already on the Home Screen
//     behind the windows gets the Home Screen's own Home press (SBIconController -handleHomeButtonTap: an open folder, the App Library, jiggle mode,
//     Spotlight or the Today View close; the first page) and the windowed apps put their keyboard away -- as when the Home Screen is tapped (Aerial).
//  B. The Home Screen keeps its look behind the windows during a Home gesture (SpringBoard's gesture blurred it as if an app covered it), and (B2,
//     1.3.9) with Reduce Motion off the windows keep still during the gesture until it becomes the App Switcher -- they shrank with the finger.
//  C. After a respring the desktop comes back by itself.
// Optional rows (kSMNeeds, "windows stay at Home ...", "the Home Screen's own Home press ...", "the Home Screen stays sharp under a Home gesture ...",
// "windows keep still in a Home gesture ..."): a row missing or of another signature leaves that part as Apple has it (logged once, listed in the
// verdict); nothing else depends on them.
#pragma once
#include "SMHomeRule.h"

static BOOL gSMHomeOn = NO;                 // (A: every row there -- the Home rule runs while our engine does)
static BOOL gSMHomeTapOn = NO;              // (the Home Screen's own Home press is there)
static BOOL gSMHomeGestureOn = NO;          // (B: the gesture's blur answers replaced)
static CFTimeInterval gSMRealHomeUntil = 0; // (the fallback of a real Home: SpringBoard's Home press -- every Home transition until then is SpringBoard's)
static NSSet<NSString *> *gSMSwitcherDesk;  // (the App Switcher on screen was opened from the desktop: its windows' identifiers)

// Our own Home that must stay a real Home: the desktop's last window minimized or closed (DMSMWindowAction; Minimize All Windows ends with it),
// 1.4's switch to an empty desktop. Asked for as a Home transition of OUR own: the Home Screen as the activating entity, as SpringBoard's own Home
// press builds it (__SBWorkspaceActivateSpringBoardWithResult: +[SBHomeScreenEntity entity] in -modifyApplicationContext:), with our event label,
// which the Home rule leaves as it is (DMSMHomeOurs; the desktop join does too). It used to be SpringBoard's simulated Home press with a 2 s "real
// Home" flag used up by the first Home transition: one press made TWO Home transitions 20 ms apart while the previous window's Minimize was still
// settling, and the second kept the last window on screen, marked minimized (Minimize All Windows, 1.3.8 logic test H-2); a system alert took the
// press for itself and no Home came at all. The press is left only as the fallback when SpringBoard does not take our request (then every Home in
// the next 2 s is SpringBoard's own).
__attribute__((noinline)) static BOOL DMSMRequestRealHome(NSString *why) {   // (noinline: its own range in the release crash map)
    id home = DMCall(objc_getClass("SBHomeScreenEntity"), @"entity");
    if (!home || !DMSMEntityFlag(home, @"isHomeScreenEntity")) { DMSMAPIFail(@"a real Home", @"no Home Screen entity"); return NO; }
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    SEL sel = NSSelectorFromString(@"requestTransitionWithBuilder:");
    if (!ws || ![ws respondsToSelector:sel] || !DMSMSigOK(ws, sel, DMSMSigRequest(), "requestTransitionWithBuilder:")) return NO;
    __block BOOL built = NO, wrote = NO;
    void (^builder)(id) = ^(id req) {
        built = YES;
        SEL lab = NSSelectorFromString(@"setEventLabel:"), mod = NSSelectorFromString(@"modifyApplicationContext:");
        if (![req respondsToSelector:lab] || !DMSMSigOK(req, lab, DMSMSigVoidObj(), "setEventLabel:")) return;   // (unlabelled it would not be ours: not asked)
        if (![req respondsToSelector:mod] || !DMSMSigOK(req, mod, DMSMSigVoidObj(), "modifyApplicationContext:")) return;
        ((void (*)(id, SEL, id))objc_msgSend)(req, lab, @"MSBDRealHome");
        ((void (*)(id, SEL, id))objc_msgSend)(req, mod, ^(id ctx) {
            SEL setAct = NSSelectorFromString(@"setActivatingEntity:");
            if (![ctx respondsToSelector:setAct] || !DMSMSigOK(ctx, setAct, DMSMSigVoidObj(), "setActivatingEntity:")) return;
            @try { ((void (*)(id, SEL, id))objc_msgSend)(ctx, setAct, home); DMSMCtxMarkOurs(ctx); wrote = YES; } @catch (id e) {}
        });
    };
    @try {
        BOOL taken = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, sel, builder);
        DMLog([NSString stringWithFormat:@"[smhome] a real Home of our own (%@): taken %d, built %d, the Home Screen asked for %d", why ?: @"?", taken, built, wrote]);
        if (!taken) return NO;
        if (!built) return YES;   // (SpringBoard runs the builder later: our request stands -- a press as well would be a second Home)
        if (wrote) DM_FEATURE_MARK("sm-home-real-home");
        return wrote;
    } @catch (NSException *e) { DMSMAPIFail(@"a real Home", e.reason ?: @"exception"); return NO; }
}
static void DMSMGoHomeForReal(NSString *why) {
    DMLog([NSString stringWithFormat:@"[smhome] a real Home asked for (%@): the windows go with it", why ?: @"?"]);
    if (gSMHomeOn && DMSMRequestRealHome(why)) return;
    gSMRealHomeUntil = CACurrentMediaTime() + 2.0;   // (the fallback: SpringBoard's own Home press, every Home transition of the next 2 s left as built)
    DMMinimize();
}

// ---- A. reading the transition and what is on screen (checked) ------------------------------------------------------------------------------------
// A layout state's environment (1 Home, 2 App Switcher, 3 application) and its stage; NO when it could not be read as expected.
static BOOL DMSMHomeStateOf(id state, long long *env, id *stage) {
    *env = 0; *stage = nil;
    if (!state) return NO;
    SEL e = NSSelectorFromString(@"unlockedEnvironmentMode"), a = NSSelectorFromString(@"appLayout");
    if (![state respondsToSelector:e] || !DMSMSigOK(state, e, DMSMSigTime(), "unlockedEnvironmentMode")) return NO;
    *env = ((long long (*)(id, SEL))objc_msgSend)(state, e);
    if ([state respondsToSelector:a] && DMSMSigOK(state, a, DMSMSigObj(), "appLayout")) { id s = ((id (*)(id, SEL))objc_msgSend)(state, a); if (DMSMIsStage(s)) *stage = s; }
    return YES;
}
static id DMSMHomePrevState(id ctx) {
    SEL pls = NSSelectorFromString(@"previousLayoutState");
    if (![ctx respondsToSelector:pls] || !DMSMSigOK(ctx, pls, DMSMSigObj(), "previousLayoutState")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(ctx, pls);
}
static NSString *DMSMHomeItemIdent(id item) {
    SEL u = NSSelectorFromString(@"uniqueIdentifier");
    if (![item respondsToSelector:u] || !DMSMSigOK(item, u, DMSMSigObj(), "uniqueIdentifier")) return nil;
    id s = ((id (*)(id, SEL))objc_msgSend)(item, u);
    return [s isKindOfClass:[NSString class]] && [s length] ? s : nil;
}
// The stage's windows as the rule reads them (@{id, r, t, p}), and each identifier's item; nil when one could not be read whole.
static NSArray<NSDictionary *> *DMSMHomeDeskOf(id stage, NSMutableDictionary<NSString *, id> *byId) {
    NSDictionary *map = DMSMStageItemsMap(stage);
    if (!map) return nil;   // (not read as expected: DMSMStageItemsMap said why)
    NSMutableArray *out = [NSMutableArray array];
    for (id it in map) {
        NSString *ident = DMSMHomeItemIdent(it);
        long long r = 0, t = 0;
        if (!ident || !DMSMStageRoleOfItem(stage, it, &r) || !DMSMAttrLastInteractionTime(map[it], &t)) return nil;
        [out addObject:@{@"id": ident, @"r": @(r), @"t": @(t), @"p": @((long long)DMSMPolicyOf(map[it]))}];
        if (byId) byId[ident] = it;
    }
    return out;
}
// The stage of the desktop the App Switcher was opened from: the most recent stage on the iPad holding exactly those windows (Stage Manager makes a
// new stage object whenever one changes; the windows are what it is).
static id DMSMHomeSwitcherStage(void) {
    if (!gSMSwitcherDesk.count) return nil;
    for (id al in DMSMRecentStages()) {
        if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(al))) continue;
        NSMutableSet *ids = [NSMutableSet set];
        for (id it in DMSMStageItemsMap(al)) { NSString *i = DMSMHomeItemIdent(it); if (i) [ids addObject:i]; }
        if ([ids isEqualToSet:gSMSwitcherDesk]) return al;
    }
    return nil;
}
// The App Switcher's bookkeeping, after SpringBoard has finalized each transition (StatusBar.x's finalize hook, after %orig; the Home rule has read
// it before): where SpringBoard WENT decides -- the context's resulting layout state (-[SBWorkspaceApplicationSceneTransitionContext finalize] works
// it out and keeps it: -layoutState). The App Switcher opened from the desktop (application mode with windows -> the App Switcher): its windows are
// remembered; still in the App Switcher (SpringBoard's own transitions inside it): kept; anywhere else: forgotten (SMHomeRule.h DMSMSwitcherNote).
// By what was ASKED (environment 2 or not) the desktop was forgotten on SpringBoard's follow-up after a switcher gesture ("...FollowupRotation-N",
// no environment asked for): Home from an App Switcher opened by the Home gesture dropped the windows (1.3.8 logic test H-1).
__attribute__((noinline)) static void DMSMHomeNoteResult(id ctx) {   // (noinline: its own range in the release crash map, test-crashstep)
    if (!ctx || !gSMHomeOn || !DMSMFree()) return;
    if (!DMSMIsMainIdentity(DMCall(ctx, @"displayIdentity"))) return;   // (the iPad's own App Switcher only: a transition on the TV changes nothing here)
    SEL ls = NSSelectorFromString(@"layoutState");
    if (![ctx respondsToSelector:ls] || !DMSMSigOK(ctx, ls, DMSMSigObj(), "layoutState")) return;
    long long env = 0, prevEnv = 0; id stage = nil, prevStage = nil;
    if (!DMSMHomeStateOf(((id (*)(id, SEL))objc_msgSend)(ctx, ls), &env, &stage)) return;   // (not readable: as it was)
    if (!DMSMHomeStateOf(DMSMHomePrevState(ctx), &prevEnv, &prevStage)) prevEnv = 0;
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    BOOL window = NO;
    if (env == 2 && prevEnv == 3) {
        NSDictionary *map = DMSMStageItemsMap(prevStage);
        for (id it in map) { NSString *i = DMSMHomeItemIdent(it); if (i) [ids addObject:i]; if (DMSMPolicyOf(map[it]) != 2) window = YES; }
    }
    // (a switcher gesture's own first transition is no destination: its event label -- SMHomeRule.h DMSMSwitcherNote)
    id req = [ctx respondsToSelector:NSSelectorFromString(@"request")] && DMSMSigOK(ctx, NSSelectorFromString(@"request"), DMSMSigObj(), "request") ? DMCall(ctx, @"request") : nil;
    id label = [req respondsToSelector:NSSelectorFromString(@"eventLabel")] ? DMCall(req, @"eventLabel") : nil;
    if (![label isKindOfClass:[NSString class]]) label = nil;
    int note = DMSMSwitcherNote(env, prevEnv, window, label);
#if DEBUG
    BOOL provisional = note == 0 && [label isEqualToString:@"SBFluidSwitcherGesture"];
#endif
#if DEBUG
    if (DMTestFlag("/tmp/macstatusbar-debug") && (note > 0 || (note < 0 && gSMSwitcherDesk.count) || env == 2 || prevEnv == 2)) {
        DMLog([NSString stringWithFormat:@"[smhome] App Switcher bookkeeping: %lld from %lld (%@): %@", env, prevEnv, label ?: @"no label",
               note > 0 ? [NSString stringWithFormat:@"remembers the desktop's %lu window(s)", (unsigned long)ids.count] : (note < 0 ? (gSMSwitcherDesk.count ? @"forgets the desktop" : @"nothing remembered") : (provisional ? @"a gesture's first transition: keeps what it had" : @"keeps what it had"))]);
    }
#endif
    if (note > 0) gSMSwitcherDesk = ids;
    else if (note < 0) gSMSwitcherDesk = nil;
}
static BOOL DMSMHomeUILocked(void) { id m = DMSBManager("SBLockScreenManager"); return m && DMLockUp(m); }

// The Home Screen's own Home press (a person on the Home Screen behind the windows): what SpringBoard does for Home while it is on the Home Screen,
// which it no longer is in its own eyes (the windows keep it in application mode) -- and the windowed apps put their keyboard away.
static void DMSMHomePressAtHome(void) {
    DMSMDeskOutsideTouch();
    if (!gSMHomeTapOn) return;
    id ic = DMCall(objc_getClass("SBIconController"), @"sharedInstance");
    SEL tap = NSSelectorFromString(@"handleHomeButtonTap");
    if (!ic || ![ic respondsToSelector:tap] || !DMSMSigOK(ic, tap, DMSMSigVoid(), "handleHomeButtonTap")) return;
    @try { ((void (*)(id, SEL))objc_msgSend)(ic, tap); DM_FEATURE_MARK("sm-home-press-at-home"); }
    @catch (NSException *e) { DMSMAPIFail(@"handleHomeButtonTap", e.reason ?: @"exception"); }
}
// After every Home the rule kept the windows for: our own open menu, dialog or question closes (the Fit question applies its default, as for any
// close) and so does the Dock's Downloads panel -- Home closes transient things, and SpringBoard's front app (which closed them before: the panel on
// "the front app changed") no longer changes when the windows stay (iPad 2: the Downloads panel stayed open after Home). Then, for a person already
// on the Home Screen, the Home Screen's own press.
static void DMSMHomeAfterKeep(BOOL atHome) {
    if (gOverlay) { DMLog(@"[smhome] Home: our open menu or panel closes, as Home closes the Home Screen's own"); DMCloseOverlay(); }
    notify_post("com.besiktasliseba.dockmagnification/frontAppChanged");   // (the Dock's Downloads panel closes: DockMagnification listens to it)
    if (atHome) DMSMHomePressAtHome();
}

// ---- A. the rule's rewrite ---------------------------------------------------------------------------------------------------------------------
// Called first in the finalize hook (StatusBar.x, %group SMEngine), for every transition context while our engine runs. Cheap unless the transition
// is SpringBoard's Home (its activating entity is the Home Screen).
__attribute__((noinline)) static void DMSMHomeKeepsDesktop(id ctx) {   // (noinline: its own range in the release crash map, test-crashstep)
    if (!ctx || !gSMHomeOn || !DMSMFree()) return;
    // (a Guided Access session: SpringBoard's transitions stay as Guided Access has them, as the desktop join does -- 1.3.8 logic test L-3)
    if (MSBDGuidedAccessActive()) return;
    id act = [ctx respondsToSelector:NSSelectorFromString(@"activatingEntity")] ? DMCall(ctx, @"activatingEntity") : nil;
    if (!DMSMEntityFlag(act, @"isHomeScreenEntity")) return;   // (not SpringBoard's Home: cheap way out for every other transition)
    long long requested = DMSMCtxLong(ctx, @"requestedUnlockedEnvironmentMode", 0);
    long long prevEnv = 0; id prevStage = nil;
    id prev = DMSMHomePrevState(ctx);
    if (!DMSMHomeStateOf(prev, &prevEnv, &prevStage)) prevEnv = 0;
    int flags = 0;
    if (DMSMCtxIsOurs(ctx)) flags |= DMSMHomeOurs;
    if (CACurrentMediaTime() < gSMRealHomeUntil) flags |= DMSMHomeRealHome;   // (the press fallback: every Home of its 2 s -- one press can make two)
    id identity = DMCall(ctx, @"displayIdentity");
    if (!DMSMIsMainIdentity(identity)) flags |= DMSMHomeNotMain;
    SEL bg = NSSelectorFromString(@"isBackground");
    if ([ctx respondsToSelector:bg] && DMSMSigOK(ctx, bg, DMSMSigBool(), "isBackground") && ((BOOL (*)(id, SEL))objc_msgSend)(ctx, bg)) flags |= DMSMHomeBackground;
    if (DMSMHomeUILocked()) flags |= DMSMHomeLocked;
    SEL rem = NSSelectorFromString(@"entitiesWithRemovalContexts");
    id removals = [ctx respondsToSelector:rem] && DMSMSigOK(ctx, rem, DMSMSigObj(), "entitiesWithRemovalContexts") ? ((id (*)(id, SEL))objc_msgSend)(ctx, rem) : nil;
    if ([removals isKindOfClass:[NSArray class]] && [removals count]) flags |= DMSMHomeRemoval;
    size_t nRoles = 0;
    const long long *roles = DMSMRepairRoleList(&nRoles);   // (SpringBoard's own window roles: 1, 2, 5-9 on 16.7.7)
    for (size_t i = 0; i < nRoles; i++) {
        BOOL ok = NO;
        id e = DMSMCtxEntityForRole(ctx, roles[i], &ok);
        if (!ok) return;   // (refused: DMSMAPIFail said why)
        if (DMSMIsEntity(e)) flags |= DMSMHomeRolesSet;
    }
    // The desktop it leaves: the stage on screen (application mode), or the one the App Switcher was opened from.
    id desk = nil;
    if (prevEnv == 3) desk = prevStage;
    else if (prevEnv == 2) { desk = DMSMHomeSwitcherStage(); if (desk) flags |= DMSMHomeSwitcherDesk; }
    NSMutableDictionary<NSString *, id> *byId = [NSMutableDictionary dictionary];
    NSArray<NSDictionary *> *windows = desk ? DMSMHomeDeskOf(desk, byId) : @[];
    BOOL showsDesk = prevEnv == 3 && desk && windows.count;
    id req = [ctx respondsToSelector:NSSelectorFromString(@"request")] && DMSMSigOK(ctx, NSSelectorFromString(@"request"), DMSMSigObj(), "request") ? DMCall(ctx, @"request") : nil;
    id label = [req respondsToSelector:NSSelectorFromString(@"eventLabel")] ? DMCall(req, @"eventLabel") : nil;
    long long source = [req respondsToSelector:NSSelectorFromString(@"source")] ? DMSMCtxLong(req, @"source", -1) : -1;
    NSString *what = [NSString stringWithFormat:@"%@ source %lld, from environment %lld, %lu window(s)", [label isKindOfClass:[NSString class]] ? label : @"no label", source, prevEnv, (unsigned long)windows.count];
    if (!windows) { DMLog([NSString stringWithFormat:@"[smhome] Home (%@): the desktop could not be read -- Home as SpringBoard built it", what]); return; }
    NSString *why = nil;
    NSDictionary *plan = DMSMHomePlan(windows, roles, nRoles, flags, requested, prevEnv, showsDesk, &why);
    if (!plan) {
        DMLog([NSString stringWithFormat:@"[smhome] Home (%@): as SpringBoard built it -- %@", what, why]);
        // (Mac Switcher desktops: a desktop of a full-screen window alone goes Home as Apple has it, and that window goes to the background as a
        //  full-screen window does from a desktop with windows below (marked minimized for the joins, back with its app). The desktop's records still
        //  named it: the next app opened there joined it and brought it back full screen behind the new window, and so did a switch back to that
        //  desktop and the restore after a respring -- the 1.3.8 logic test's H-3 on the Mac Switcher's own path, which joins by its records, not by
        //  StatusBar.x DMSMDesktopFor. As with Aerial's Mac Switcher, Home takes a full-screen app off its desktop.)
        if ([why isEqualToString:kDMSMHomeOnlyFullScreen] && DMMSWMulti()) {
            NSMutableArray<NSString *> *away = [NSMutableArray array];
            for (NSDictionary *w in windows) { NSString *k = DMSMItemKey(byId[w[@"id"]]); if (k.length) { DMSMSetMinimized(k, YES); [away addObject:DMSMKeyText(k)]; } }   // (each window by its key, as below)
            if (away.count) DMLog([NSString stringWithFormat:@"[smhome] Home: %@ to the background (Mac Switcher desktops: no longer one of %@'s windows)", [away componentsJoinedByString:@", "], DMMSWDeskName(gMSWCur)]);
        }
        return;
    }
    // The plan in SpringBoard's terms: each window's own entity (its scene -- two windows of one app are two), its attributes as they are on screen.
    id mainIdentity = identity ?: DMSMIdentityOfScreen([UIScreen mainScreen]);
    NSMutableArray<NSArray *> *rows = [NSMutableArray array];
    id frontEntity = nil;
    for (NSArray *k in plan[@"keep"]) {
        id item = byId[k[0]];
        id e = DMSMEntityForItem(item, mainIdentity);
        id a = DMSMStageItemsMap(desk)[item];
        if (!e || !a) { DMLog([NSString stringWithFormat:@"[smhome] Home (%@): %@ could not be planned -- Home as SpringBoard built it", what, k[0]]); return; }
        [rows addObject:@[e, k[1], a]];
        if ([k[0] isEqualToString:plan[@"front"]]) frontEntity = e;
    }
    NSString *bad = nil;
    if (!frontEntity || !DMSMPlanValid(rows, nil, &bad)) { DMSMAPIFail(@"windows stay at Home", [NSString stringWithFormat:@"plan refused, Home as SpringBoard built it (%@)", bad ?: @"no front window"]); return; }
    // Written as one: the mode (application), the front app (the window in front), the windows in their roles with their attributes (DMSMWritePlan:
    // also marks the context ours and the front window frontmost), every other window role emptied (a role left unset keeps the window it had --
    // the full-screen window that leaves would stay). Any failure puts SpringBoard's Home back as it was.
    SEL setMode = NSSelectorFromString(@"setRequestedUnlockedEnvironmentMode:"), setAct = NSSelectorFromString(@"setActivatingEntity:"), setE = NSSelectorFromString(@"setEntity:forLayoutRole:");
    if (!DMSMCtxCanWrite(ctx) || !DMSMSigOK(ctx, setMode, DMSMSigVoidLong(), "setRequestedUnlockedEnvironmentMode:") || !DMSMSigOK(ctx, setAct, DMSMSigVoidObj(), "setActivatingEntity:")) return;
    NSMutableArray<NSNumber *> *emptied = [NSMutableArray array];
    void (^backToHome)(void) = ^{
        @try { ((void (*)(id, SEL, long long))objc_msgSend)(ctx, setMode, requested); } @catch (id x) {}
        @try { ((void (*)(id, SEL, id))objc_msgSend)(ctx, setAct, act); } @catch (id x) {}
        for (NSNumber *r in emptied) @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, nil, r.longLongValue); } @catch (id x) {}
        SEL fm = NSSelectorFromString(@"_setRequestedFrontmostEntity:");   // (DMSMWritePlan named our front window frontmost: no longer)
        if ([ctx respondsToSelector:fm] && DMSMSigOK(ctx, fm, DMSMSigVoidObj(), "_setRequestedFrontmostEntity:")) @try { ((void (*)(id, SEL, id))objc_msgSend)(ctx, fm, nil); } @catch (id x) {}
        objc_setAssociatedObject(ctx, &kSMOwnCtxKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (nor is the context ours: DMSMWritePlan marked it -- L-2)
    };
    @try {
        ((void (*)(id, SEL, long long))objc_msgSend)(ctx, setMode, 3);
        ((void (*)(id, SEL, id))objc_msgSend)(ctx, setAct, frontEntity);
    } @catch (NSException *x) { backToHome(); DMSMAPIFail(@"windows stay at Home", [NSString stringWithFormat:@"%@: Home as SpringBoard built it", x.reason ?: @"exception"]); return; }
    if (!DMSMWritePlan(ctx, rows, frontEntity)) { backToHome(); DMLog([NSString stringWithFormat:@"[smhome] Home (%@): writing the windows failed -- Home as SpringBoard built it", what]); return; }
    for (NSNumber *r in plan[@"empty"]) {
        id none = DMSMEmptyEntityNew();   // (a new one per role, as SpringBoard makes them)
        BOOL ok = none != nil;
        if (ok) { @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, none, r.longLongValue); [emptied addObject:r]; } @catch (NSException *x) { ok = NO; } }
        if (!ok) {
            for (NSArray *row in rows) @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, nil, [row[1] longLongValue]); } @catch (id y) {}
            backToHome();
            DMSMAPIFail(@"windows stay at Home", [NSString stringWithFormat:@"emptying role %@ failed: Home as SpringBoard built it", r]);
            return;
        }
    }
    NSMutableArray<NSString *> *awayNames = [NSMutableArray array];
    for (NSString *ident in plan[@"away"]) {   // (the full-screen app went to the background: a minimized window to the joins, back with its app)
        NSString *k = DMSMItemKey(byId[ident]);   // (that window: the app's other windows stay windows, M-2)
        if (k.length) { DMSMSetMinimized(k, YES); [awayNames addObject:DMSMKeyText(k)]; }
    }
    DM_FEATURE_MARK("sm-home-keeps-windows");
    BOOL atHome = [plan[@"atHome"] boolValue];
    DMLog([NSString stringWithFormat:@"[smhome] Home (%@): the windows stay over the Home Screen -- %@%@", what, why,
           awayNames.count ? [NSString stringWithFormat:@" (%@ to the background)", [awayNames componentsJoinedByString:@", "]] : @""]);
    BOOL pressAtHome = atHome && prevEnv == 3;
    dispatch_async(dispatch_get_main_queue(), ^{ DMSMHomeAfterKeep(pressAtHome); });
}

// ---- B. the Home Screen keeps its look behind the windows during a Home gesture -----------------------------------------------------------------
// The Home Screen behind the windows blurred heavily at the gesture's start and cleared as the finger rose (iPad 2, Reduce Motion off, mid-gesture
// capture) -- the gesture assumes the Home Screen was covered by an app: blur type 3 from the start (-homeScreenBackdropBlurType) and a blur
// progress taken from the stage floor toward Home's (-homeScreenBackdropBlurProgress); with Reduce Motion on, type 2 on a vertical swipe. Over a
// desktop of windows with the Home Screen behind them (SMDesktop.h), the gesture answers what the floor below it answers (the Home Screen's own,
// sharp look -- as the original methods' own [super ...] calls read it); with a full-screen window in front, from the Home Screen, or anything
// else, Apple's answers.
static long long (*o_SMHGBlurType)(id, SEL), (*o_SMRMBlurType)(id, SEL);
static double (*o_SMHGBlurProgress)(id, SEL);
static Ivar gSMHGStart, gSMRMStart;
static Class gSMHGSuper, gSMRMSuper;
static char kSMHGDeskKey;
// This gesture runs over a desktop of windows with the Home Screen behind them: started in application mode, the iPad's stage on screen has
// windows and none full screen, the Home Screen is shown behind windows (SMDesktop.h's floor answers on). Decided once per gesture.
static BOOL DMSMHGOverDesk(id mod, Ivar start) {
    if (!gSMHomeGestureOn || !DMSMFree() || !gSMDeskHooked || gSMDeskOff) return NO;
    NSNumber *cached = objc_getAssociatedObject(mod, &kSMHGDeskKey);
    if (cached) return cached.boolValue;
    long long env = 0;
    memcpy(&env, (const char *)(__bridge const void *)mod + ivar_getOffset(start), sizeof env);
    BOOL yes = NO;
    if (env == 3) {
        id stage = DMSMFrontStageOnDisplay(DMSMIdentityOfScreen([UIScreen mainScreen]));
        NSDictionary *m = DMSMStageItemsMap(stage);
        yes = m.count > 0;
        for (id it in m) if (DMSMPolicyOf(m[it]) == 2) { yes = NO; break; }
    }
    objc_setAssociatedObject(mod, &kSMHGDeskKey, @(yes), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (yes) DM_FEATURE_MARK("sm-home-gesture-sharp");
    if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smhome] Home gesture (%@, from environment %lld): %@", NSStringFromClass([mod class]), env,
                                                      yes ? @"over the desktop's windows -- the Home Screen behind them keeps its look" : @"Apple's look"]);
    return yes;
}
static long long DMSMHGBlurType(id self, SEL _cmd) {
    if (!DMSMHGOverDesk(self, gSMHGStart)) return o_SMHGBlurType(self, _cmd);
    struct objc_super su = { self, gSMHGSuper };
    return ((long long (*)(struct objc_super *, SEL))objc_msgSendSuper)(&su, _cmd);
}
#if DEBUG
static void DMSMHGProbeKick(id mod);
#endif
static double DMSMHGBlurProgress(id self, SEL _cmd) {
    if (!DMSMHGOverDesk(self, gSMHGStart)) return o_SMHGBlurProgress(self, _cmd);
#if DEBUG
    DMSMHGProbeKick(self);   // (also without B2's hooks: the debug A/B /tmp/msb-sm-applegestureshrink shows Apple's numbers -- logic test L-5)
#endif
    struct objc_super su = { self, gSMHGSuper };
    return ((double (*)(struct objc_super *, SEL))objc_msgSendSuper)(&su, _cmd);
}
static long long DMSMRMBlurType(id self, SEL _cmd) {
    if (!DMSMHGOverDesk(self, gSMRMStart)) return o_SMRMBlurType(self, _cmd);
    struct objc_super su = { self, gSMRMSuper };
    return ((long long (*)(struct objc_super *, SEL))objc_msgSendSuper)(&su, _cmd);
}

// ---- B2. the windows keep still during a Home gesture (Reduce Motion off) until it becomes the App Switcher ---------------------------------------
// With Reduce Motion off, a Home swipe over the desktop shrank the windows with the finger and moved them up; they came back when it ended (the rule
// keeps them). Root cause (16.7.7, measured on the iPad 2 with a probe of the root modifier's answers, 7 Oct): SpringBoard's Home gesture takes the
// stage under the finger as the app going Home (-[SBDeckSwitcherPanGestureWorkspaceTransaction selectedAppLayoutForGestureRecognizer:] -> the item
// container at the touch). When a window of the desktop lies under the finger's path (a window across the bottom middle of the screen), the whole
// stage is that "selected app": -[SBHomeGestureSwitcherModifier scaleForIndex:] answers -_scaleForTranslation: (1.0 -> 0.48 over a slow swipe) and
// -frameForIndex: the rest frame offset by -_frameOffsetForTranslation:, as for an app going Home, and every window scales with its stage. With no
// window under the finger (Fit's tiles leave a gap in the middle), nothing is selected and nothing moves. sm-free answered these two queries already
// but only until the gesture modifier's _inMultitasking, which turns on after about 90 pt of every swipe -- so the windows shrank for the rest of
// it (its fly-in flag and its App Switcher haptic turn on at the same moment, they are no pause either). Now the desktop's stage keeps its rest
// answers -- the floor's, read through the gesture modifier's own super, as the blur answers above -- until the finger has held still in the App
// Switcher's range for 0.3 s: SpringBoard counts those frames itself (-_displayLinkFired: -> _gestureHoldTimer, frames whose average velocity is under
// its fly-in limit while lifting would open the App Switcher). From then on Apple's answers take the desktop into its App Switcher card with
// SpringBoard's own springs. (SpringBoard's -_hasPausedEnoughForFlyIn also counts an "acceleration dip", which every injected swipe on the iPad 2
// tripped mid-way at full speed: not used.) A Home swipe therefore moves no window, fast or slow; a swipe that ends in the App Switcher without a hold
// animates into it as it ends. A sideways swipe along the bottom edge (switching stages: |x| > |y|), a full-screen window in front, Reduce Motion on
// (its own modifier moves nothing), the Home Screen with no windows: Apple's. The rule itself: SMHomeRule.h DMSMHGKeepStill (Mac-tested).
static double (*o_SMHGScale)(id, SEL, unsigned long long);
static CGRect (*o_SMHGFrame)(id, SEL, unsigned long long);
static Ivar gSMHGSelIv, gSMHGHoldIv, gSMHGTransIv;
static SEL gSMHGIsSelected;
static long long DMSMHGHoldFrames(id mod) {   // (SpringBoard's own count of the frames the finger held still in the App Switcher's range)
    long long frames = 0;
    memcpy(&frames, (const char *)(__bridge const void *)mod + ivar_getOffset(gSMHGHoldIv), sizeof frames);
    return frames;
}
static BOOL gSMHomeStillOn = NO;            // (B2: the gesture's two answers replaced)
static char kSMHGStillKey, kSMHGWayKey;
// The gesture's stage keeps still at this index now: the gesture runs over a desktop of windows (DMSMHGOverDesk), the index is the stage the
// gesture took (its selected app layout) and that stage is the desktop on screen, and the finger has not held still for the App Switcher.
__attribute__((noinline)) static BOOL DMSMHGStill(id mod, unsigned long long index) {   // (noinline: its own range in the release crash map)
    if (!gSMHomeStillOn || !DMSMHGOverDesk(mod, gSMHGStart)) return NO;   // (cheap ways out first: every other gesture, every other mode)
    BOOL selected = ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(mod, gSMHGIsSelected, index);
    if (!selected) return NO;
    NSNumber *cached = objc_getAssociatedObject(mod, &kSMHGStillKey);   // (the stage it took is the desktop: once per gesture, it does not change)
    if (!cached) {
        id taken = object_getIvar(mod, gSMHGSelIv);
        id desk = DMSMFrontStageOnDisplay(DMSMIdentityOfScreen([UIScreen mainScreen]));
        BOOL yes = taken && desk && [taken isEqual:desk];
        cached = @(yes);
        objc_setAssociatedObject(mod, &kSMHGStillKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (yes) DM_FEATURE_MARK("sm-home-gesture-still");
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smhome] Home gesture over a window of the desktop: %@", yes ? @"the windows keep still until the App Switcher is asked for" : @"the stage it took is not the desktop -- Apple's movement"]);
    }
    CGPoint t = CGPointZero;
    memcpy(&t, (const char *)(__bridge const void *)mod + ivar_getOffset(gSMHGTransIv), sizeof t);
    // (up or sideways: decided once per gesture, after kDMSMHGWayTravel pt, and kept -- SMHomeRule.h DMSMHGSwipeWay)
    NSNumber *wayWas = objc_getAssociatedObject(mod, &kSMHGWayKey);
    int way = DMSMHGSwipeWay(t.x, t.y, wayWas.intValue);
    if (way && !wayWas) {
        objc_setAssociatedObject(mod, &kSMHGWayKey, @(way), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smhome] Home gesture: %@ (decided at %.0f, %.0f)", way == 2 ? @"sideways along the bottom -- Apple's movement" : @"up -- the windows keep still", t.x, t.y]);
    }
    NSInteger fps = [UIScreen mainScreen].maximumFramesPerSecond;
    return DMSMHGKeepStill(YES, selected, cached.boolValue, DMSMHGHoldFrames(mod), fps, way);   // (the rule: SMHomeRule.h, Mac test test-smhomerule)
}
static double DMSMHGScale(id self, SEL _cmd, unsigned long long index) {
#if DEBUG
    DMSMHGProbeKick(self);
#endif
    if (!DMSMHGStill(self, index)) return o_SMHGScale(self, _cmd, index);
    struct objc_super su = { self, gSMHGSuper };
    return ((double (*)(struct objc_super *, SEL, unsigned long long))objc_msgSendSuper)(&su, _cmd, index);
}
static CGRect DMSMHGFrame(id self, SEL _cmd, unsigned long long index) {
    if (!DMSMHGStill(self, index)) return o_SMHGFrame(self, _cmd, index);
    struct objc_super su = { self, gSMHGSuper };
    return ((CGRect (*)(struct objc_super *, SEL, unsigned long long))objc_msgSendSuper)(&su, _cmd, index);
}
#if DEBUG
// debug /tmp/msb-sm-hgprobe: during a Home gesture over the desktop, every ~120 ms (outside the layout pass), what the switcher's ROOT modifier answers
// for each of its app layouts (what -[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:] reads), the gesture modifier's own and its
// super's answers, whether it took the desktop and the App Switcher's flags, and the desktop's windows' item containers on screen. Read-only.
static __weak id gSMHGProbeMod;
static CFTimeInterval gSMHGProbeLast = 0;
static void DMSMHGProbeRun(void) {
    id mod = gSMHGProbeMod;
    if (!mod) return;
    @try {
        id coord = DMSMCoordinator();
        id scene = MSBDMainWindowScene();
        SEL forScene = NSSelectorFromString(@"switcherControllerForWindowScene:");
        id sc = scene && [coord respondsToSelector:forScene] ? ((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, scene) : nil;
        id vc = DMCall(sc, @"contentViewController");
        id root = [vc respondsToSelector:NSSelectorFromString(@"rootModifier")] ? DMCall(vc, @"rootModifier") : nil;
        if (!root) { DMLog(@"[hgprobe] no root modifier"); return; }
        id als = DMCall(root, @"appLayouts");
        Ivar multiIv = class_getInstanceVariable(object_getClass(mod), "_inMultitasking"), transIv = class_getInstanceVariable(object_getClass(mod), "_translation");
        BOOL multi = NO; CGPoint tr = CGPointZero; long long hold = -1;
        if (multiIv) memcpy(&multi, (const char *)(__bridge const void *)mod + ivar_getOffset(multiIv), sizeof multi);
        if (gSMHGHoldIv) hold = DMSMHGHoldFrames(mod);
        SEL pausedSel = NSSelectorFromString(@"_hasPausedEnoughForFlyIn");
        BOOL paused = [mod respondsToSelector:pausedSel] && ((BOOL (*)(id, SEL))objc_msgSend)(mod, pausedSel);
        if (transIv) memcpy(&tr, (const char *)(__bridge const void *)mod + ivar_getOffset(transIv), sizeof tr);
        id taken = gSMHGSelIv ? object_getIvar(mod, gSMHGSelIv) : nil;
        id desk = DMSMFrontStageOnDisplay(DMSMIdentityOfScreen([UIScreen mainScreen]));
        NSUInteger count = [als isKindOfClass:[NSArray class]] ? [(NSArray *)als count] : 0;
        NSMutableString *o = [NSMutableString stringWithFormat:@"[hgprobe] %lu app layouts, took %@, multitasking %d, Apple's paused-enough %d, hold frames %lld (held %d), translation %@, still on %d",
                              (unsigned long)count, !taken ? @"none" : ([taken isEqual:desk] ? @"the desktop" : @"another stage"), multi, paused, hold,
                              hold > (long long)(0.3 * (double)MAX((NSInteger)1, [UIScreen mainScreen].maximumFramesPerSecond)), NSStringFromCGPoint(tr), gSMHomeStillOn];
        SEL scaleSel = NSSelectorFromString(@"scaleForIndex:"), frameSel = NSSelectorFromString(@"frameForIndex:");
        for (NSUInteger j = 0; j < count && j < 4; j++) {
            id a = ((NSArray *)als)[j];
            double S = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(root, scaleSel, (unsigned long long)j);
            CGRect F = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(root, frameSel, (unsigned long long)j);
            struct objc_super su = { mod, gSMHGSuper };
            double sup = ((double (*)(struct objc_super *, SEL, unsigned long long))objc_msgSendSuper)(&su, scaleSel, (unsigned long long)j);
            [o appendFormat:@" || %lu%@: root scale %.3f frame %@ (the floor's %.3f)", (unsigned long)j, [a isEqual:desk] ? @" (the desktop)" : @"", S, NSStringFromCGRect(F), sup];
            if (![a isEqual:desk]) continue;
            id leaves = DMCall(a, @"leafAppLayouts");
            SEL icSel = NSSelectorFromString(@"_itemContainerForAppLayoutIfExists:");
            for (id leaf in ([leaves isKindOfClass:[NSArray class]] ? leaves : @[])) {
                UIView *cont = [vc respondsToSelector:icSel] ? ((id (*)(id, SEL, id))objc_msgSend)(vc, icSel, leaf) : nil;
                CALayer *pl = cont.layer.presentationLayer;
                [o appendFormat:@" | %@ on screen %.3f %@", DMSMItemBundle([DMCall(leaf, @"allItems") firstObject]) ?: @"?", pl ? pl.transform.m11 : -1, pl ? NSStringFromCGRect(pl.frame) : @"-"];
            }
        }
        DMLog(o);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[hgprobe] failed: %@", e.reason]); }
}
static void DMSMHGProbeKick(id mod) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gSMHGProbeLast < 0.12) return;
    gSMHGProbeLast = now;
    if (!DMTestFlag("/tmp/msb-sm-hgprobe") || !DMSMHGOverDesk(mod, gSMHGStart)) return;
    gSMHGProbeMod = mod;
    dispatch_async(dispatch_get_main_queue(), ^{ DMSMHGProbeRun(); });
}
#endif

// ---- C. after a respring the desktop comes back by itself ----------------------------------------------------------------------------------------
// The other engines' windows come back after a respring (DMRestoreWindows, our own restore). Stage Manager keeps the desktop's stage among its
// recent stages but starts on the Home Screen, and the first app opened brought every window back with it (the desktop join) -- "I open one app
// and it opens others". Now, once per SpringBoard start, when the Home Screen is up after the unlock, the desktop is asked for by itself (its
// windows' apps start, as with the other engines); an app opened later only adds its own window. Not when something was opened first (the join
// took the desktop along), on the Lock Screen, with the screen off, after 20 min, or when the last start ended while a restore was running (a
// crash loop must not repeat itself). debug /tmp/msb-sm-norestore: not restored.
static CFTimeInterval gSMHomeStart = 0;
static BOOL gSMRestoreDone = NO;
static id DMSMHomeCurrentState(void) {   // (the iPad switcher's layout state now)
    id coord = DMSMCoordinator();
    UIWindowScene *scene = MSBDMainWindowScene();
    SEL forScene = NSSelectorFromString(@"switcherControllerForWindowScene:");
    id sc = scene && [coord respondsToSelector:forScene] && DMSMSigOK(coord, forScene, DMSMSigObjObj(), "switcherControllerForWindowScene:") ? ((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, scene) : nil;
    return DMCall(DMCall(DMCall(sc, @"contentViewController"), @"layoutContext"), @"layoutState");
}
static void DMSMRestoreDesktopTick(void) {
    if (gSMRestoreDone || !gSMHomeOn || !DMSMFree() || gSMHomeStart <= 0) return;
    CFTimeInterval age = CACurrentMediaTime() - gSMHomeStart;
    if (age < 6.0) return;
    if (age > 1200.0) { gSMRestoreDone = YES; DMLog(@"[smhome] the desktop was not brought back: no Home Screen within 20 min of the start"); return; }
    if (gDMScreenOff || DMSMHomeUILocked() || DMCoverSheetShown() || gOverlay) return;
    long long env = 0; id shown = nil;
    if (!DMSMHomeStateOf(DMSMHomeCurrentState(), &env, &shown)) return;   // (not readable yet)
    gSMRestoreDone = YES;
    {   // (the saved minimized marks of windows that are gone -- their stage removed, e.g. the app quit from the App Switcher: a window's scene ends
        //  with it -- leave the saved set now that SpringBoard's stages are read; the set only grew, 1.3.9 logic test L-3. SMWindowKey.h DMSMKeysGone)
        NSArray *stages = DMSMRecentStages();
        NSMutableSet<NSString *> *present = [NSMutableSet set];
        for (id al in stages) for (id it in DMSMStageItemsMap(al)) { NSString *k = DMSMItemKey(it); if (k) [present addObject:k]; }
        // (every recent stage counts, the hidden ones too: a window minimized, or one on another Mac Switcher desktop, waits in a hidden stage that
        //  Stage Manager keeps across a respring. No stage read at all -- SpringBoard's model not there yet -- drops nothing.)
        NSSet<NSString *> *gone = stages.count && present.count && DMSMPerWindow() ? DMSMKeysGone(DMSMMinimizedSet(), present) : nil;   // (window keys compare only per window)
        if (gone.count) {
            DMSMMinimizedDrop(gone);
            DMLog([NSString stringWithFormat:@"[smhome] after the start: %lu minimized mark(s) of windows that no longer exist dropped", (unsigned long)gone.count]);
        }
    }
    if (env != 1) { DMLog([NSString stringWithFormat:@"[smhome] after the start: not on the Home Screen (environment %lld) -- the desktop is as it was opened", env]); return; }
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-norestore")) { DMLog(@"[smhome] debug /tmp/msb-sm-norestore: the desktop is not brought back"); return; }
#endif
    // (a release crash-loop guard, allowed in tools/verify-release.sh: written just before the request below, taken away 20 s later -- still there
    //  now, before this start wrote one, means the last start ended while the desktop was being brought back; whatever its age: the next try waits
    //  for the unlock, which can take longer than any fixed time -- 1.3.8 logic test L-5)
    static const char *guard = "/tmp/macstatusbar-smrestore-guard";
    struct stat st;
    if (stat(guard, &st) == 0) { unlink(guard); DMLog(@"[smhome] the desktop is not brought back: the last start ended while it was being brought back"); return; }
    // Mac Switcher desktops: the CURRENT desktop's windows (its records, saved with the desktops), asked for together as a switch asks for them
    // (MacSwitcherSM.h DMMSWSMShowDesk: every stage they are in, at most a full desktop) -- the engine's desktop below is the most recent stage with
    // a window, which can be another desktop's (the one left last before the respring) or only part of the current one (after a remove).
    if (DMMSWMulti()) {
        NSArray<NSArray *> *cw = DMMSWSMDeskWindows(DMMSWCurId());
        if (!cw.count) { DMLog([NSString stringWithFormat:@"[smhome] after the start: %@ has no window to bring back", DMMSWDeskName(gMSWCur)]); return; }
        NSMutableArray<NSString *> *tiled = [NSMutableArray array];
        for (NSArray *w in cw) if (DMSMPolicyOf(w[2]) != 2) [tiled addObject:w[3]];
        FILE *g = fopen(guard, "w"); if (g) fclose(g);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ unlink(guard); });
        NSString *front = DMMSWSMShowDesk(DMMSWCurId(), @"after the start");
        if (front) { DM_FEATURE_MARK("sm-desktop-back-after-respring"); DMSMFitAdoptRestored(tiled); }
        DMLog([NSString stringWithFormat:@"[smhome] after the start: %@'s %lu window(s) %@", DMMSWDeskName(gMSWCur), (unsigned long)cw.count, front ? @"come back by themselves" : @"could not be asked for -- they come back with the first app opened"]);
        return;
    }
    // The desktop: the most recent stage on the iPad with a window that is not minimized, not an app in full screen sent to the background (as the
    // joins have it: StatusBar.x DMSMDesktopFor; minimized windows are known across a respring: DMSMMinimizedSet, one entry per window).
    id desk = DMSMDesktopFor(nil, nil, NULL);
    if (!desk) { DMLog(@"[smhome] after the start: no desktop with windows to bring back"); return; }
    NSDictionary *map = DMSMStageItemsMap(desk);
    NSMutableDictionary<NSString *, id> *byId = [NSMutableDictionary dictionary];
    NSArray<NSDictionary *> *all = DMSMHomeDeskOf(desk, byId);
    if (!all.count) return;
    id identity = DMSMIdentityOfScreen([UIScreen mainScreen]);
    NSMutableArray<NSArray *> *rows = [NSMutableArray array];
    NSMutableSet<NSNumber *> *used = [NSMutableSet set];
    id front = nil; long long newest = -1;
    NSMutableArray<NSString *> *names = [NSMutableArray array], *tiled = [NSMutableArray array];
    for (NSDictionary *w in [all sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"r"] compare:b[@"r"]]; }]) {
        id item = byId[w[@"id"]];
        NSString *b = DMSMItemBundle(item);
        if (DMSMIsMinimized(DMSMItemKey(item))) continue;   // (a minimized window stays minimized -- that window, not its app's others)
        long long r = DMSMFirstFreeRole(used);   // (closed up in role order, as SpringBoard does: a stage always has its primary window)
        id e = DMSMEntityForItem(item, identity);
        if (!r || !e || !map[item]) { DMLog([NSString stringWithFormat:@"[smhome] after the start: %@ could not be planned -- the desktop comes back with the first app opened", b ?: @"a window"]); return; }
        [rows addObject:@[e, @(r), map[item]]];
        NSString *k = DMSMItemKey(item);   // (Fit to Window knows the windows by their keys: two windows of one app are two tiles, M-2)
        if (b) [names addObject:DMSMKeyText(k ?: b)];
        if (k && [w[@"p"] longLongValue] != 2) [tiled addObject:k];
        if ([w[@"t"] longLongValue] > newest) { newest = [w[@"t"] longLongValue]; front = e; }
    }
    if (!rows.count) return;
    FILE *g = fopen(guard, "w"); if (g) fclose(g);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ unlink(guard); });
    BOOL ok = DMSMRequestOn(identity, @"MSBDRestoreDesktop", rows, nil, front);
    if (ok) { DM_FEATURE_MARK("sm-desktop-back-after-respring"); DMSMFitAdoptRestored(tiled); }   // (Fit to Window takes them as they come back)
    DMLog([NSString stringWithFormat:@"[smhome] after the start: the desktop's %lu window(s) %@ (%@)", (unsigned long)rows.count, ok ? @"come back by themselves" : @"could not be asked for -- they come back with the first app opened", [names componentsJoinedByString:@", "]]);
}

// ---- install (once, from the start-up self-check, after the engine's hooks) ----------------------------------------------------------------------
static BOOL DMSMHomeRowsPassed(const char *const *rows, size_t n, NSMutableArray<NSString *> *missing) {
    BOOL all = YES;
    for (size_t i = 0; i + 1 < n; i += 2) if (!DMSMRowPassed(rows[i], rows[i + 1])) { all = NO; [missing addObject:[NSString stringWithFormat:@"%s %s", rows[i], rows[i + 1]]]; }
    return all;
}
static void DMSMHomeInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    static const char *const ruleRows[] = {
        "SBWorkspaceApplicationSceneTransitionContext", "setActivatingEntity:", "SBWorkspaceApplicationSceneTransitionContext", "requestedUnlockedEnvironmentMode",
        "SBWorkspaceApplicationSceneTransitionContext", "setRequestedUnlockedEnvironmentMode:", "SBWorkspaceApplicationSceneTransitionContext", "previousLayoutState",
        "SBMainDisplayLayoutState", "unlockedEnvironmentMode", "SBMainDisplayLayoutState", "appLayout", "SBWorkspaceEntity", "isHomeScreenEntity",
        "SBEmptyWorkspaceEntity", "entity", "SBMainSwitcherControllerCoordinator", "_entityForDisplayItem:displayIdentity:", "SBDisplayItem", "uniqueIdentifier",
        "SBWorkspaceApplicationSceneTransitionContext", "layoutState", "SBHomeScreenEntity", "entity", "SBWorkspaceApplicationSceneTransitionContext", "request",
        "SBWorkspaceTransitionRequest", "eventLabel", "SBWorkspaceTransitionRequest", "setEventLabel:", "SBWorkspaceApplicationSceneTransitionContext", "isBackground",
        "SBWorkspaceApplicationSceneTransitionContext", "entitiesWithRemovalContexts", "SBWorkspaceApplicationSceneTransitionContext", "_setRequestedFrontmostEntity:",
    };
    static const char *const tapRows[] = {"SBIconController", "sharedInstance", "SBIconController", "handleHomeButtonTap"};
    static const char *const gestureRows[] = {
        "SBHomeGestureSwitcherModifier", "homeScreenBackdropBlurType", "SBHomeGestureSwitcherModifier", "homeScreenBackdropBlurProgress", "SBHomeGestureSwitcherModifier", "_startingEnvironmentMode",
        "SBReduceMotionHomeGestureSwitcherModifier", "homeScreenBackdropBlurType", "SBReduceMotionHomeGestureSwitcherModifier", "_startingEnvironmentMode",
    };
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-applehome")) { DMLog(@"[smhome] debug /tmp/msb-sm-applehome: Home as Apple has it (the windows go)"); return; }
#endif
    gSMHomeStart = CACurrentMediaTime();
    gSMHomeOn = DMSMHomeRowsPassed(ruleRows, sizeof ruleRows / sizeof ruleRows[0], missing);
    if (!gSMHomeOn) { DMLog([NSString stringWithFormat:@"[smhome] Home puts the windows away here (Apple's way): not as expected -- %@", [missing componentsJoinedByString:@"; "]]); return; }
    gSMHomeTapOn = DMSMHomeRowsPassed(tapRows, sizeof tapRows / sizeof tapRows[0], missing);
    DMLog([NSString stringWithFormat:@"[smhome] the windows stay on screen at Home%@", gSMHomeTapOn ? @" (and the Home Screen's own Home press applies under them)" : @" (the Home Screen's own Home press is not there: Home does not close its folders)"]);
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-applegesture")) { DMLog(@"[smhome] debug /tmp/msb-sm-applegesture: the Home gesture blurs the Home Screen as Apple has it"); return; }
#endif
    [missing removeAllObjects];
    if (!DMSMHomeRowsPassed(gestureRows, sizeof gestureRows / sizeof gestureRows[0], missing)) {
        DMLog([NSString stringWithFormat:@"[smhome] the Home gesture blurs the Home Screen as Apple has it here: %@", [missing componentsJoinedByString:@"; "]]);
        return;
    }
    Class c = objc_getClass("SBHomeGestureSwitcherModifier"), rm = objc_getClass("SBReduceMotionHomeGestureSwitcherModifier");
    gSMHGStart = class_getInstanceVariable(c, "_startingEnvironmentMode");
    gSMRMStart = class_getInstanceVariable(rm, "_startingEnvironmentMode");
    gSMHGSuper = class_getSuperclass(c); gSMRMSuper = class_getSuperclass(rm);
    if (!gSMHGStart || !gSMRMStart || !gSMHGSuper || !gSMRMSuper) return;   // (checked as rows above; kept as a guard)
    MSHookMessageEx(c, sel_registerName("homeScreenBackdropBlurType"), (IMP)DMSMHGBlurType, (IMP *)&o_SMHGBlurType);
    MSHookMessageEx(c, sel_registerName("homeScreenBackdropBlurProgress"), (IMP)DMSMHGBlurProgress, (IMP *)&o_SMHGBlurProgress);
    MSHookMessageEx(rm, sel_registerName("homeScreenBackdropBlurType"), (IMP)DMSMRMBlurType, (IMP *)&o_SMRMBlurType);
    Method m1 = class_getInstanceMethod(c, sel_registerName("homeScreenBackdropBlurType")), m2 = class_getInstanceMethod(c, sel_registerName("homeScreenBackdropBlurProgress"));
    Method m3 = class_getInstanceMethod(rm, sel_registerName("homeScreenBackdropBlurType"));
    // (all three or none: a half-replaced gesture would blur with one kind and not the other)
    gSMHomeGestureOn = o_SMHGBlurType && o_SMHGBlurProgress && o_SMRMBlurType && m1 && m2 && m3 && method_getImplementation(m1) == (IMP)DMSMHGBlurType
                    && method_getImplementation(m2) == (IMP)DMSMHGBlurProgress && method_getImplementation(m3) == (IMP)DMSMRMBlurType;
    DMLog(gSMHomeGestureOn ? @"[smhome] the Home Screen keeps its look behind the windows during a Home gesture" : @"[smhome] the Home gesture's blur answers could not all be replaced: Apple's look");
    if (!gSMHomeGestureOn) return;   // (B2 reads B's per-gesture decision and super class)
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-applegestureshrink")) { DMLog(@"[smhome] debug /tmp/msb-sm-applegestureshrink: the Home gesture moves the windows as Apple has it"); return; }
#endif
    static const char *const stillRows[] = {
        "SBHomeGestureSwitcherModifier", "frameForIndex:", "SBHomeGestureSwitcherModifier", "scaleForIndex:", "SBHomeGestureSwitcherModifier", "_isSelectedAppLayoutAtIndex:",
        "SBHomeGestureSwitcherModifier", "_selectedAppLayout", "SBHomeGestureSwitcherModifier", "_gestureHoldTimer", "SBHomeGestureSwitcherModifier", "_translation",
    };
    [missing removeAllObjects];
    if (!DMSMHomeRowsPassed(stillRows, sizeof stillRows / sizeof stillRows[0], missing)) {
        DMLog([NSString stringWithFormat:@"[smhome] the Home gesture moves the windows as Apple has it here: %@", [missing componentsJoinedByString:@"; "]]);
        return;
    }
    gSMHGSelIv = class_getInstanceVariable(c, "_selectedAppLayout");
    gSMHGHoldIv = class_getInstanceVariable(c, "_gestureHoldTimer");
    gSMHGTransIv = class_getInstanceVariable(c, "_translation");
    gSMHGIsSelected = sel_registerName("_isSelectedAppLayoutAtIndex:");
    if (!gSMHGSelIv || !gSMHGHoldIv || !gSMHGTransIv) return;   // (checked as rows above; kept as a guard)
    MSHookMessageEx(c, sel_registerName("scaleForIndex:"), (IMP)DMSMHGScale, (IMP *)&o_SMHGScale);
    MSHookMessageEx(c, sel_registerName("frameForIndex:"), (IMP)DMSMHGFrame, (IMP *)&o_SMHGFrame);
    Method ms = class_getInstanceMethod(c, sel_registerName("scaleForIndex:")), mf = class_getInstanceMethod(c, sel_registerName("frameForIndex:"));
    // (both or neither: a half-replaced gesture would keep the size but move the windows, or the other way round)
    gSMHomeStillOn = o_SMHGScale && o_SMHGFrame && ms && mf && method_getImplementation(ms) == (IMP)DMSMHGScale && method_getImplementation(mf) == (IMP)DMSMHGFrame;
    DMLog(gSMHomeStillOn ? @"[smhome] the windows keep still during a Home gesture (until the App Switcher is asked for)" : @"[smhome] the Home gesture's frame and scale answers could not both be replaced: the windows move as Apple has it");
}

#if DEBUG
// debug trigger smhome: what the Home rule would do now (read-only) -- the switcher's layout state, the desktop on screen, the plan.
static void DMSMHomeDebug(void) {
    @try {
        id coord = DMSMCoordinator();
        UIWindowScene *scene = MSBDMainWindowScene();
        SEL forScene = NSSelectorFromString(@"switcherControllerForWindowScene:");
        id sc = scene && [coord respondsToSelector:forScene] ? ((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, scene) : nil;
        id state = DMCall(DMCall(DMCall(sc, @"contentViewController"), @"layoutContext"), @"layoutState");
        long long env = 0; id stage = nil;
        BOOL ok = DMSMHomeStateOf(state, &env, &stage);
        NSMutableDictionary *byId = [NSMutableDictionary dictionary];
        NSArray *w = stage ? DMSMHomeDeskOf(stage, byId) : nil;
        size_t n = 0; const long long *roles = DMSMRepairRoleList(&n);
        NSString *why = nil;
        NSDictionary *plan = DMSMHomePlan(w ?: @[], roles, n, gSMSwitcherDesk.count ? DMSMHomeSwitcherDesk : 0, 1, env, env == 3 && w.count, &why);
        DMLog([NSString stringWithFormat:@"[smhome] now: read %d, environment %lld, stage windows %@; switcher desk %@; rule on %d, tap %d, gesture %d; Home would: %@ %@",
               ok, env, w ?: @"none", gSMSwitcherDesk ?: @"none", gSMHomeOn, gSMHomeTapOn, gSMHomeGestureOn, plan ? @"keep" : @"leave", plan ?: why]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smhome] debug failed: %@", e.reason]); }
}
#endif
