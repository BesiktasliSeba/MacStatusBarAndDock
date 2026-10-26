// SMGestureHook.h -- SpringBoard's side of SMGestureHold.h: the gesture transaction's begin and end, and the stage it holds from its begin.
// Included by StatusBar.x with SMHome.h (the Stage Manager engine's start installs it: DMSMGestureHoldInstall).
#pragma once
// The stage on the iPad's screen when the gesture began (application mode only: from the Home Screen or the App Switcher nothing is taken).
static id DMSMGestureStageOnScreen(void) {   // (SMHome.h's checked reading of the layout state, as DMSMShownMainStage: logic test L5)
    long long env = 0; id s = nil;
    if (!DMSMHomeStateOf(DMSMHomeCurrentState(), &env, &s) || env != 3) return nil;
    return s ?: DMSMFrontStageOnDisplay(DMSMIdentityOfScreen([UIScreen mainScreen]));
}
// SpringBoard's gesture transaction (SBFluidSwitcherGestureWorkspaceTransaction, the base of the Home / deck pan gesture's): its begin and end.
static void (*o_SMGTBegin)(id, SEL), (*o_SMGTDidComplete)(id, SEL);
static void DMSMGTBegin(id self, SEL _cmd) {
    o_SMGTBegin(self, _cmd);
    @try {
        if (!gSMGestureTxs) gSMGestureTxs = [NSHashTable weakObjectsHashTable];
        if (!DMSMGestureLive()) {
            gSMGestureSince = CACurrentMediaTime(); gSMGestureHeld = [NSMutableSet set];
            // (writes still waiting from the gesture before -- its flush not run yet -- belong to where that gesture went: a new gesture takes the
            //  user elsewhere, and a join run after it brought the app back over the Home Screen the new gesture went to: review of r5. The user's
            //  own actions stay: they run at this gesture's end instead -- DMSMAfterGestureUsers, logic test L3)
            if (gSMAfterGesture.count) {
                NSMutableArray *users = [NSMutableArray array];
                for (NSArray *w in gSMAfterGesture) if (DMSMAfterGestureIsUsers(w)) [users addObject:w];
                NSUInteger left = gSMAfterGesture.count - users.count;
                if (left) DMLog([NSString stringWithFormat:@"[smgesture] a new switcher gesture: %lu write(s) from the one before left", (unsigned long)left]);
                if (users.count) DMLog([NSString stringWithFormat:@"[smgesture] a new switcher gesture: the user's own %lu action(s) wait for its end", (unsigned long)users.count]);
                gSMAfterGesture = users.count ? users : nil;
            }
        }
        [gSMGestureTxs addObject:self];
        id st = DMSMGestureStageOnScreen();
        DMSMGestureHold(st);
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smgesture] %@ began: holds %lu window(s)", NSStringFromClass(object_getClass(self)), (unsigned long)gSMGestureHeld.count]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smgesture] begin: %@", e.reason]); }
}
static void DMSMGTDidComplete(id self, SEL _cmd) {
    o_SMGTDidComplete(self, _cmd);
    @try {
        [gSMGestureTxs removeObject:self];
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smgesture] %@ ended after %.0f ms: %lu write(s) waiting", NSStringFromClass(object_getClass(self)), (CACurrentMediaTime() - gSMGestureSince) * 1000.0, (unsigned long)gSMAfterGesture.count]);
        if (!DMSMGestureLive()) { if (gSMAfterGesture.count) DMSMGestureFlushSoon(); else gSMGestureHeld = nil; }
        DMSMBarsSettleSoon(@"a switcher gesture's end");   // (the top bar decided again once everything has settled: StatusBar.x)
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smgesture] end: %@", e.reason]); }
}
static BOOL DMSMGTVoidMethod(Class c, SEL s) {   // (no arguments, no result: what our hooks are written for)
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char r[8] = {0};
    method_getReturnType(m, r, sizeof r);
    return r[0] == 'v';
}
// The previous / next app by a swipe along the bottom edge: SpringBoard's own switch to that app's stage stands since 1.5.2 (SMDesktop.h, nothing
// joins the desktop -- KT: like a Mac, like Aerial and Zetsu). A stage whose windows are all minimized is not one to go to: a minimized window
// lives in the Dock (a Mac's swipe between spaces never brings one back), and Aerial and Zetsu do nothing when the app swiped to is a window. Such a
// swipe stays where it is: the gesture's destination becomes 0 ("stay") at the one place a final destination becomes a transition request -- the
// Mac Switcher's way of taking a side swipe over (MacSwitcher.h DMMSWActivateWith). The stage it would go to: the neighbour of the stage under the
// finger in the switcher's list, 2 (the fingers went right: an older stage) after it, 1 before it.
static id (*o_SMSwipeActivate)(id, SEL, long long), (*o_SMSwipeActivateCE)(id, SEL, long long);
// (fromHome: a gesture that took no stage -- from the Home Screen -- goes to the most recent one with 2, as SpringBoard's own next layout from there;
//  the Stage Manager engine never asks for it: its desktop is the stage taken, DMSMGestureTakes)
static id DMSMSwipeTarget(id modifier, long long dest, BOOL fromHome) {
    if (dest != 1 && dest != 2) return nil;
    SEL list = NSSelectorFromString(@"appLayouts"), sel = NSSelectorFromString(@"_selectedAppLayoutIndex");
    if (![modifier respondsToSelector:list] || ![modifier respondsToSelector:sel] || !DMSMSigOK(modifier, list, DMSMSigObj(), "appLayouts")
        || !DMSMSigOK(modifier, sel, DMSMExpect(@encode(unsigned long long), NULL), "_selectedAppLayoutIndex")) return nil;   // (both checked: logic test L5)
    id layouts = ((id (*)(id, SEL))objc_msgSend)(modifier, list);
    unsigned long long i = ((unsigned long long (*)(id, SEL))objc_msgSend)(modifier, sel);
    if (![layouts isKindOfClass:[NSArray class]]) return nil;
    if (i >= [layouts count]) {
        if (!fromHome || dest != 2 || ![layouts count]) return nil;
        id t = layouts[0];
        return DMSMIsStage(t) ? t : nil;
    }
    long long j = (long long)i + (dest == 2 ? 1 : -1);
    if (j < 0 || j >= (long long)[layouts count]) return nil;
    id t = layouts[(NSUInteger)j];
    return DMSMIsStage(t) ? t : nil;
}
static BOOL DMSMStageOnlyMinimizedWindows(id stage) {   // (every window of it minimized, none full screen: nothing of it is shown anywhere)
    NSDictionary *map = DMSMStageItemsMap(stage);
    if (!map.count) return NO;
    for (id it in map) {
        NSString *k = DMSMItemKey(it);
        if (!k.length || !DMSMIsMinimized(k) || DMSMAttrsFullScreen(map[it])) return NO;
    }
    return YES;
}
static id DMSMSwipeActivateWith(id self, SEL _cmd, long long dest, id (*orig)(id, SEL, long long)) {
    // (the Mac Switcher's own side swipe comes first: with two desktops or more, or while its slide follows the gesture, the swipe is its desktop
    //  switch and SpringBoard stays whatever stage is next -- MacSwitcher.h DMMSWActivateWith, whose hook may wrap this one or be wrapped by it)
    if (gMSWTrackEnding || (DMMSWGesturesOn() && DMMSWMulti())) return orig(self, _cmd, dest);
    @try {
        // Aerial, Zetsu, MilkyWay4: the app swiped to has one of our windows -- SpringBoard would open it full screen, under or over its window, and
        // our window rules took that full-screen scene for the window's: Zetsu on iPadOS 16 turned the full-screen app, and with it the whole screen,
        // to portrait on a landscape-locked iPad (1.4-1.5.1, iPad 2 16.7.7; its Flex frame and iPadOS 16's window orientation 1). Aerial does not let
        // SpringBoard switch to such an app at all, and Aerial and Zetsu on iPadOS 15 showed nothing either: the swipe stays where it is, on every
        // window engine (KT, 26 Oct: as Aerial and Zetsu do when the app swiped to is a window). The window is the app's place, as for a Dock tap.
        if (!DMSMEngine() && DMActiveEngine() != DMEngineNone && !DMTestFlag("/tmp/msb-swipe-nostay")) {
            id target = DMSMSwipeTarget(self, dest, YES);
            NSString *app = nil;
            for (id it in [target respondsToSelector:NSSelectorFromString(@"allItems")] ? DMCall(target, @"allItems") : nil) { app = DMSMItemBundle(it); if (app.length) break; }
#if DEBUG
            if (target && DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[swipe] destination %lld: SpringBoard would open %@%@", dest, app ?: @"?", app.length && DMHasWindowFor(app) ? @" (it has a window)" : @""]);
#endif
            if (app.length && DMHasWindowFor(app)) {
                DM_FEATURE_MARK("window-swipe-stays");
                DMLog([NSString stringWithFormat:@"[swipe] the swipe goes to %@, which has a window: it stays (destination %lld -> 0)", app, dest]);
                return orig(self, _cmd, 0);
            }
            return orig(self, _cmd, dest);
        }
        id target = DMSMFree() ? DMSMSwipeTarget(self, dest, NO) : nil;
#if DEBUG
        if (DMTestFlag("/tmp/msb-swipedebug")) {   // (debug, 17/18 check of 1.5.2 item 3: what the destination check reads)
            SEL ls = NSSelectorFromString(@"appLayouts"), si = NSSelectorFromString(@"_selectedAppLayoutIndex");
            NSArray *l = [self respondsToSelector:ls] ? ((id (*)(id, SEL))objc_msgSend)(self, ls) : nil;
            unsigned long long idx = [self respondsToSelector:si] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(self, si) : ULLONG_MAX;
            NSMutableArray *rows = [NSMutableArray array];
            for (id a in ([l isKindOfClass:[NSArray class]] ? l : @[])) {
                NSMutableArray *k = [NSMutableArray array];
                for (id it in DMSMStageItemsMap(a)) [k addObject:[NSString stringWithFormat:@"%@%@", DMSMKeyText(DMSMItemKey(it)) ?: @"?", DMSMIsMinimized(DMSMItemKey(it)) ? @" (min)" : @""]];
                [rows addObject:[NSString stringWithFormat:@"%@[%@]", NSStringFromClass([a class]), [k componentsJoinedByString:@", "]]];
            }
            DMLog([NSString stringWithFormat:@"[smswipe] check: %@ destination %lld, engine free %d, %lu app layouts, selected index %llu, target %@: %@", NSStringFromClass([self class]), dest, DMSMFree(),
                (unsigned long)rows.count, idx, target ? @"found" : @"none", [rows componentsJoinedByString:@" | "]]);
        }
        if (target && DMTestFlag("/tmp/macstatusbar-debug")) {
            NSMutableArray *names = [NSMutableArray array]; for (id it in DMSMStageItemsMap(target)) [names addObject:DMSMKeyText(DMSMItemKey(it)) ?: @"?"];
            DMLog([NSString stringWithFormat:@"[smswipe] destination %lld: the stage it goes to holds %@%@", dest, [names componentsJoinedByString:@", "], DMSMStageOnlyMinimizedWindows(target) ? @" (minimized windows only)" : @""]);
        }
#endif
        if (target && DMSMStageOnlyMinimizedWindows(target)) {
            DM_FEATURE_MARK("sm-swipe-skips-minimized");
            DMLog([NSString stringWithFormat:@"[smswipe] the swipe goes to a stage of minimized windows only: it stays (destination %lld -> 0)", dest]);
            return orig(self, _cmd, 0);   // (0: stay on the current layout)
        }
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smswipe] destination check: %@", e.reason]); }
    return orig(self, _cmd, dest);
}
static id DMSMSwipeActivate(id self, SEL _cmd, long long dest) { return DMSMSwipeActivateWith(self, _cmd, dest, o_SMSwipeActivate); }
static id DMSMSwipeActivateCE(id self, SEL _cmd, long long dest) { return DMSMSwipeActivateWith(self, _cmd, dest, o_SMSwipeActivateCE); }
// The stage a switcher gesture takes: SpringBoard's own pick is the stage under the finger (-[SBDeckSwitcherPanGestureWorkspaceTransaction
// selectedAppLayoutForGestureRecognizer:], the item container at the touch). The engine's desktop shows the Home Screen around its windows
// (SMDesktop.h's floor) and its windows end above the Dock: with no window near the finger a gesture from the bottom edge took no stage, so a swipe
// along the bottom edge went nowhere -- the previous app never came back from a desktop of windows (1.4-1.5.1, "only the desktop's own windows",
// iPad 2 26 Oct: "selected -"). Then the desktop on screen is the stage it takes, as with a window under the finger: a side swipe goes to the
// stage next to it; a swipe up for Home keeps the windows still (SMHome.h B2) and the Home rule keeps them; a hold takes the desktop's card into
// the App Switcher (the Mac Switcher instead, with it on).
static id (*o_SMGestureTakes)(id, SEL, id);
static id DMSMGestureTakes(id self, SEL _cmd, id recognizer) {
    id taken = o_SMGestureTakes(self, _cmd, recognizer);
    if (taken || !DMSMFree() || !gSMDeskHooked || gSMDeskOff) return taken;
    @try {
        id desk = DMSMShownMainStage();   // (the iPad's stage on screen, in application mode; nil at the Home Screen or in the App Switcher)
        NSDictionary *m = desk ? DMSMStageItemsMap(desk) : nil;
        BOOL windows = NO;
        for (id it in m) {
            if (DMSMAttrsFullScreen(m[it])) return taken;   // (a full-screen window fills the screen: SpringBoard's own pick stands)
            NSString *k = DMSMItemKey(it);
            if (k.length && !DMSMIsMinimized(k)) windows = YES;
        }
        if (!windows) return taken;
        DM_FEATURE_MARK("sm-gesture-takes-desktop");
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smgesture] no stage under the finger: the gesture takes the desktop on screen (%lu window(s) over the Home Screen), as with a window under the finger", (unsigned long)m.count]);
        return desk;
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smgesture] the stage a gesture takes: %@ -- SpringBoard's own pick", e.reason]); }
    return taken;
}
static void DMSMSwipeHookInstall(void) {   // (iPadOS 16's home gesture modifier; 17+'s Stage Manager one where it has the same method)
    static BOOL done = NO;   // (from the Stage Manager engine's start, or with a window engine from the launch hooks: DMTryHookWindowLaunch)
    if (done) return;
    done = YES;
    // (both hooks whatever the engine: this runs at SpringBoard's start, before the engine is picked -- the hooks ask which engine runs each time)
    {
        Class t = objc_getClass("SBDeckSwitcherPanGestureWorkspaceTransaction");
        SEL s = sel_registerName("selectedAppLayoutForGestureRecognizer:");
        Method m = t ? class_getInstanceMethod(t, s) : NULL;
        if (m && [DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(id), @encode(id), NULL)]) MSHookMessageEx(t, s, (IMP)DMSMGestureTakes, (IMP *)&o_SMGestureTakes);
        DMLog([NSString stringWithFormat:@"[smgesture] a gesture over the desktop's windows takes the desktop: %@", o_SMGestureTakes ? @"on" : @"not here (SpringBoard's own pick only)"]);
    }
    SEL a = sel_registerName("_responseForActivatingFinalDestination:");
    NSString *want = DMSMExpect(@encode(id), @encode(long long), NULL);
    Class c = objc_getClass("SBHomeGestureSwitcherModifier"), ce = objc_getClass("SBContinuousExposeHomeGestureSwitcherModifier");
    Method m = c ? class_getInstanceMethod(c, a) : NULL, mce = ce ? class_getInstanceMethod(ce, a) : NULL;
    if (m && [DMSMSigOfMethod(m) isEqualToString:want]) MSHookMessageEx(c, a, (IMP)DMSMSwipeActivate, (IMP *)&o_SMSwipeActivate);
    if (mce && [DMSMSigOfMethod(mce) isEqualToString:want]) MSHookMessageEx(ce, a, (IMP)DMSMSwipeActivateCE, (IMP *)&o_SMSwipeActivateCE);
    DMLog([NSString stringWithFormat:@"[smswipe] a swipe to the previous app: a Stage Manager stage of minimized windows, or an app with a window of another engine, is not one to go to (%@%@)", o_SMSwipeActivate ? @"home gesture" : @"-", o_SMSwipeActivateCE ? @", Stage Manager's home gesture" : @""]);
}
// From the Stage Manager engine's start (StatusBar.x, with %init(SMEngine)): the engine only, never on iPadOS 15 or with another engine.
static void DMSMGestureHoldInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    DMSMSwipeHookInstall();
    Class c = objc_getClass("SBFluidSwitcherGestureWorkspaceTransaction");
    SEL b = sel_registerName("_begin"), d = sel_registerName("_didComplete");
    if (!DMSMGTVoidMethod(c, b) || !DMSMGTVoidMethod(c, d)) {
        DMLog(@"[smgesture] the switcher gesture's transaction is not as expected here: its end is taken as a moment after the gesture's own end");
        return;
    }
    DM_FEATURE_MARK("sm-gesture-hold");
    MSHookMessageEx(c, b, (IMP)DMSMGTBegin, (IMP *)&o_SMGTBegin);
    MSHookMessageEx(c, d, (IMP)DMSMGTDidComplete, (IMP *)&o_SMGTDidComplete);
    gSMGestureHooked = o_SMGTBegin && o_SMGTDidComplete;
    DMLog(gSMGestureHooked ? @"[smgesture] a switcher gesture's stage is left alone until its transition is over" : @"[smgesture] the gesture transaction's hooks did not go in: the moment after the gesture's own end is used");
}
