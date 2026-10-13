// SMGestureHook.h -- SpringBoard's side of SMGestureHold.h: the gesture transaction's begin and end, and the stage it holds from its begin.
// Included by StatusBar.x with SMHome.h (the Stage Manager engine's start installs it: DMSMGestureHoldInstall).
#pragma once
// The stage on the iPad's screen when the gesture began (application mode only: from the Home Screen or the App Switcher nothing is taken).
static id DMSMGestureStageOnScreen(void) {
    id coord = DMSMCoordinator();
    UIWindowScene *scene = MSBDMainWindowScene();
    SEL forScene = NSSelectorFromString(@"switcherControllerForWindowScene:");
    id sc = scene && [coord respondsToSelector:forScene] ? ((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, scene) : nil;
    id state = DMCall(DMCall(DMCall(sc, @"contentViewController"), @"layoutContext"), @"layoutState");
    SEL env = NSSelectorFromString(@"unlockedEnvironmentMode");
    if (!state || ![state respondsToSelector:env] || ((long long (*)(id, SEL))objc_msgSend)(state, env) != 3) return nil;
    id s = DMCall(state, @"appLayout");
    return DMSMIsStage(s) ? s : DMSMFrontStageOnDisplay(DMSMIdentityOfScreen([UIScreen mainScreen]));
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
            //  user elsewhere, and a join run after it brought the app back over the Home Screen the new gesture went to: review of r5)
            if (gSMAfterGesture.count) { DMLog([NSString stringWithFormat:@"[smgesture] a new switcher gesture: %lu write(s) from the one before left", (unsigned long)gSMAfterGesture.count]); gSMAfterGesture = nil; }
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
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smgesture] end: %@", e.reason]); }
}
static BOOL DMSMGTVoidMethod(Class c, SEL s) {   // (no arguments, no result: what our hooks are written for)
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m || method_getNumberOfArguments(m) != 2) return NO;
    char r[8] = {0};
    method_getReturnType(m, r, sizeof r);
    return r[0] == 'v';
}
// From the Stage Manager engine's start (StatusBar.x, with %init(SMEngine)): the engine only, never on iPadOS 15 or with another engine.
static void DMSMGestureHoldInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
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
