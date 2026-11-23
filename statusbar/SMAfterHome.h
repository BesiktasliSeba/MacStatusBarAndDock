// SMAfterHome.h -- the red light on a desktop's last window: its stage leaves the App Switcher once the Home transition that takes the window off
// the screen is over (1.5.2: the black "ghost" cards in the App Switcher on iPadOS 17 and 18). Included by StatusBar.x after SMGestureHook.h
// (DMSMHomeStateOf, SMHome.h, is above it); DMSMWindowAction (StatusBar.x) calls DMSMAfterOurHome, declared before it.
//   SpringBoard ends every layout transition in -[SBMainSwitcherControllerCoordinator layoutStateTransitionCoordinator:
//   transitionDidEndWithTransitionContext:], which puts the stage the transition left back at the front of the App Switcher's list
//   (-_addAppLayoutToFront:removeAppLayout: -> -[SBAppSwitcherModel addToFront:]; traced on 17.5.1 and 18.5 with swtrace_, 26 Oct). The desktop's
//   last window goes to the Home Screen first and its stage was taken out 0.6 s later (-deleteAppLayoutForDisplayItem:, the same model removal the
//   App Switcher's swipe-up runs, which also quits the app as a user quit). When the Home transition ended after that -- 0.75 s after the request
//   on the A12Z's 18.5, 0.41 s on a quiet 17.5 iPad and later when it is busy -- its end put the stage back: the app just quit, its pictures
//   dropped with the quit, a black card in the App Switcher; after a respring that stage even came back as the desktop and started the app again.
//   Now the removal waits for the end of THE Home transition we asked for, and runs on the next turn of the main queue, after SpringBoard's own
//   bookkeeping -- as the App Switcher's swipe-up runs, with no transition in flight. That Home is known by its number (SMHome.h: each real Home of
//   ours numbers the transition context it builds, DMSMRealHomeGenOf): any other transition that ends meanwhile -- the App Switcher opening or
//   closing, a Mac Switcher desktop switch, already running when the red light was clicked -- is not it, whatever its end state shows (code review
//   CR1: the first transition whose end state did not show the window, or whose end state could not be read, ran the removal; SpringBoard's later
//   Home end put the stage back -- the ghost card again). Our Home's end seen but its end state not readable here: 0.6 s after it, not at once.
//   SpringBoard's own Home press standing in for our Home (SMHome.h's fallback, unnumbered): a transition to the Home Screen that ends within 3 s,
//   its end state read as the Home Screen. Where no end can be told (the end method missing or of another signature, the context not readable)
//   the removal keeps its 0.6 s wait; one that has waited 4 s runs anyway. A window on screen again when its removal runs after the Home was seen
//   is one the user opened again: left open (DMSMAfterHomeEnded).
#pragma once

static NSMutableArray<NSArray *> *gSMAfterHome;   // (removals waiting: @[what, the window's display item, block, our Home's number (0: the press), when])
static BOOL gSMAfterHomeHooked = NO;
static const CFTimeInterval kSMAfterHomeMaxWait = 4.0;   // (also covers a Home that waits for a switcher gesture's end first, SMGestureHold.h: 3 s at most)

static BOOL gSMAfterHomeEnded = NO;   // (while a removal runs: it runs because the Home transition was seen to end -- not the 4 s / 0.6 s wait)
static BOOL DMSMAfterHomeEnded(void) { return gSMAfterHomeEnded; }
static void DMSMAfterHomeRun(NSArray *w, NSString *why, BOOL ended) {
    dispatch_async(dispatch_get_main_queue(), ^{   // (never inside SpringBoard's own call: the next turn of the main queue)
        DMLog([NSString stringWithFormat:@"[smengine] %@: %@", w[0], why]);
        gSMAfterHomeEnded = ended;
        @try { ((dispatch_block_t)w[2])(); }
        @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smengine] %@ failed: %@", w[0], e.reason]); }
        gSMAfterHomeEnded = NO;
    });
}
// The TV desktop's last window (1.8.8.2, B86): the TV's own empty desktop is asked for FIRST, while the window's stage is still Stage Manager's and
// on screen there (StatusBar.x DMSMTVEmptyFirst), and the stage leaves the model once that transition is over -- as the iPad's last window goes Home
// first. B86's first version took the stage out first and asked after: SpringBoard began the TV's transition from a layout state naming a stage no
// longer in its switcher's model and raised inside it ("Trying to add an icon overlay but the item container for this app layout doesn't exist");
// the transition it had begun never finished, and every later transition -- every app launch, anywhere -- waited behind it until a SpringBoard
// restart (iPadOS 18.5, twice). The end that counts: one on that display of our request (its event label) or one that ended at its empty desktop;
// none seen in 4 s: the removal runs once the stage is off screen, never while it is on screen (DMSMAfterTVEmptyCap). Meanwhile the app's own
// switcher clean-up after a force quit waits with it
// (DMSMAfterTVEmptyHolds): no stage of the app leaves the model while that transition may still have to begin.
static NSMutableArray<NSArray *> *gSMAfterTVEmpty;   // (@[what, the display's identity, the window's display item, block(ended), when, blocks held])
static NSString *const kSMTVEmptyLabel = @"MSBDDisplayEmptyDesktop";   // (MacSwitcherSM.h DMMSWSMRequestEmpty's event label)
#ifndef MSBD_TV_EMPTY_LONGEST
#define MSBD_TV_EMPTY_LONGEST 30.0   // (tools/test-tvemptyfirst builds with a shorter one)
#endif
static const CFTimeInterval kSMAfterTVEmptyLongest = MSBD_TV_EMPTY_LONGEST;
static id DMMSWSMStateStage(id identity);   // (MacSwitcherSM.h: the stage another display's settled layout state names, nil at its empty desktop)
static id DMSMShownMainStage(void);         // (StatusBar.x: the stage the iPad shows)
// (review 1.8.8.2) The window's stage still on screen: the TV's state still names it or its window is still there (the TV's transition to its empty
// desktop has not begun yet -- queued behind another -- or is still running), or the iPad shows it (the TV unplugged meanwhile: SpringBoard moved
// its stage there). A stage on screen is never taken out: a state naming a stage the model no longer has is the very state SpringBoard raised in,
// inside a transition it then never finished. NO: no stage holds the window, or none of that.
static BOOL DMSMTVStageStillShown(id identity, id item) {
    id st = nil;
    for (id al in DMSMRecentStages()) if (DMSMStageItemsMap(al)[item]) { st = al; break; }
    if (!st) return NO;
    id named = DMMSWSMStateStage(identity), ipad = DMSMShownMainStage();
    return (named && (named == st || [named isEqual:st])) || DMSMStageShownOnDisplay(st, identity) || (ipad && (ipad == st || [ipad isEqual:st]));
}
static void DMSMAfterTVEmptyRun(NSArray *w, NSString *why, BOOL ended) {
    if ([gSMAfterTVEmpty indexOfObjectIdenticalTo:w] == NSNotFound) return;
    [gSMAfterTVEmpty removeObjectIdenticalTo:w];
    dispatch_async(dispatch_get_main_queue(), ^{   // (never inside SpringBoard's own call: the next turn of the main queue)
        DMLog([NSString stringWithFormat:@"[smengine] %@: %@", w[0], why]);
        @try { ((void (^)(BOOL))w[3])(ended); }
        @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smengine] %@ failed: %@", w[0], e.reason]); }
        // (the app's held switcher clean-up deletes its stages: not while one is on screen again -- opened again meanwhile)
        if ([(NSArray *)w[5] count] && DMSMTVStageStillShown(w[1], w[2])) {
            DMLog([NSString stringWithFormat:@"[smengine] %@: its stage is on screen again: the app's switcher clean-up is not run", w[0]]);
            return;
        }
        for (dispatch_block_t b in (NSArray *)w[5]) {
            @try { b(); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smengine] %@: a held clean-up failed: %@", w[0], e.reason]); }
        }
    });
}
// (review 1.8.8.2) No end seen in 4 s: the removal runs only once the window's stage is off screen (the TV's transition over, its end not seen here);
// while it is still on screen that transition may still be to come or running -- read again every second, the end still awaited; after 30 s still on
// screen: left in the model with nothing run (the app was ended all the same; SpringBoard's own clean-up of it then begins from a state it knows).
static void DMSMAfterTVEmptyCap(NSArray *w) {
    if ([gSMAfterTVEmpty indexOfObjectIdenticalTo:w] == NSNotFound) return;
    double waited = CACurrentMediaTime() - [w[4] doubleValue];
    if (DMSMTVStageStillShown(w[1], w[2])) {
        if (waited < kSMAfterTVEmptyLongest) {
            if (waited < kSMAfterHomeMaxWait + 0.5) DMLog([NSString stringWithFormat:@"[smengine] %@: no end of the TV's empty desktop seen in 4 s and its stage is still on screen: not taken out, it waits on", w[0]]);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMSMAfterTVEmptyCap(w); });
            return;
        }
        [gSMAfterTVEmpty removeObjectIdenticalTo:w];
        DMLog([NSString stringWithFormat:@"[smengine] %@: still on screen after %.0f s: left in the model, nothing run", w[0], waited]);
        return;
    }
    DMSMAfterTVEmptyRun(w, gSMAfterHomeHooked ? @"no end of the TV's empty desktop seen, its stage off screen: now" : @"its stage off screen (the end of SpringBoard's transitions is not seen here): now", NO);
}
// A transition on another display ended: the TV's empty desktop we asked for there, or one that ended at its empty desktop.
static void DMSMAfterTVEmptyEnded(id did, id ac, BOOL toRead, long long env) {
    if (!gSMAfterTVEmpty.count) return;
    SEL rq = NSSelectorFromString(@"request"), lb = NSSelectorFromString(@"eventLabel");
    id req = [ac respondsToSelector:rq] && DMSMSigOK(ac, rq, DMSMSigObj(), "request") ? ((id (*)(id, SEL))objc_msgSend)(ac, rq) : nil;
    id label = [req respondsToSelector:lb] && DMSMSigOK(req, lb, DMSMSigObj(), "eventLabel") ? ((id (*)(id, SEL))objc_msgSend)(req, lb) : nil;
    BOOL ours = [label isKindOfClass:[NSString class]] && [label isEqualToString:kSMTVEmptyLabel];
    for (NSArray *w in [gSMAfterTVEmpty copy]) {
        if (![w[1] isEqual:did]) continue;
        if (!ours && !(toRead && env == 1)) {
            DMLog([NSString stringWithFormat:@"[smengine] %@: a transition ended there that is not its empty desktop (its end state %@): it waits on", w[0], toRead ? [NSString stringWithFormat:@"environment %lld", env] : @"not readable"]);
            continue;
        }
        DMSMAfterTVEmptyRun(w, ours ? @"the TV's empty desktop we asked for is there" : @"that display is at its empty desktop", YES);
    }
}
// The TV desktop's last window: block(ended) once that display's empty desktop transition is over (ended YES), or with no end seen in 4 s once its
// stage is off screen (NO; above).
static void DMSMAfterTVEmpty(NSString *what, id identity, id item, void (^block)(BOOL ended)) {
    if (!block || !identity || !item) return;
    if (!gSMAfterTVEmpty) gSMAfterTVEmpty = [NSMutableArray array];
    NSArray *w = @[what ?: @"a TV window's removal", identity, item, [block copy], @(CACurrentMediaTime()), [NSMutableArray array]];
    [gSMAfterTVEmpty addObject:w];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSMAfterHomeMaxWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMSMAfterTVEmptyCap(w); });
}
// An app's switcher clean-up (DMForceQuitBundle) while the TV's empty desktop for its window there is still to come: held, and run right after
// that window's removal. NO: nothing waits for that app (run it now).
static BOOL DMSMAfterTVEmptyHolds(NSString *bundle, dispatch_block_t block) {
    if (!bundle.length || !block) return NO;
    for (NSArray *w in gSMAfterTVEmpty) {
        if (![DMSMItemBundle(w[2]) isEqualToString:bundle]) continue;
        [(NSMutableArray *)w[5] addObject:[block copy]];
        DMLog([NSString stringWithFormat:@"[smengine] %@: the app's switcher clean-up waits for it", w[0]]);
        return YES;
    }
    return NO;
}
static void (*o_SMTransitionDidEnd)(id, SEL, id, id);
static void DMSMTransitionDidEnd(id self, SEL _cmd, id coordinator, id ctx) {
    o_SMTransitionDidEnd(self, _cmd, coordinator, ctx);   // (SpringBoard first: its end puts the stage it left at the front of the list)
    if (!gSMAfterHome.count && !gSMAfterTVEmpty.count) return;
    SEL toSel = NSSelectorFromString(@"toLayoutState"), appCtx = NSSelectorFromString(@"applicationTransitionContext");
    id to = ctx && [ctx respondsToSelector:toSel] && DMSMSigOK(ctx, toSel, DMSMSigObj(), "toLayoutState") ? ((id (*)(id, SEL))objc_msgSend)(ctx, toSel) : nil;
    id ac = ctx && [ctx respondsToSelector:appCtx] && DMSMSigOK(ctx, appCtx, DMSMSigObj(), "applicationTransitionContext") ? ((id (*)(id, SEL))objc_msgSend)(ctx, appCtx) : nil;
    if (!ac) return;   // (which transition this is can't be told: not ours -- the removal waits, at most 4 s)
    // (another display's transition -- the TV's -- is not the iPad's Home: left waiting; it may be the TV's empty desktop, above)
    if ([ac respondsToSelector:NSSelectorFromString(@"displayIdentity")]) {
        id did = DMCall(ac, @"displayIdentity");
        if (!DMSMIsMainIdentity(did)) {
            long long tenv = 0; id tstage = nil;
            BOOL tRead = to && DMSMHomeStateOf(to, &tenv, &tstage);
            DMSMAfterTVEmptyEnded(did, ac, tRead, tenv);
            return;
        }
    }
    if (!gSMAfterHome.count) return;
    NSUInteger gen = DMSMRealHomeGenOf(ac);   // (our real Home's number on this transition's context; 0: not a Home of ours)
    long long env = 0; id stage = nil;
    BOOL toRead = to && DMSMHomeStateOf(to, &env, &stage);
    for (NSArray *w in [gSMAfterHome copy]) {
        NSUInteger want = [w[3] unsignedIntegerValue];
        BOOL ours = want ? (gen && gen >= want)   // (that Home -- or a later Home of ours, which ended after it)
                         : (toRead && env == 1 && CACurrentMediaTime() - [w[4] doubleValue] < 3.0 && DMSMEntityFlag(DMCall(ac, @"activatingEntity"), @"isHomeScreenEntity"));   // (the press)
        if (!ours) {   // (another transition ends -- the App Switcher, a desktop switch --: the removal waits on)
            DMLog([NSString stringWithFormat:@"[smengine] %@: a transition ended that is not the Home we asked for (%@, its end state %@): it waits on", w[0],
                   gen ? [NSString stringWithFormat:@"our Home #%lu", (unsigned long)gen] : @"not ours", toRead ? [NSString stringWithFormat:@"environment %lld", env] : @"not readable"]);
            continue;
        }
        [gSMAfterHome removeObjectIdenticalTo:w];
        if (!toRead) {   // (our Home is over, but where it ended can't be read here: a little later, not at once)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                DMSMAfterHomeRun(w, @"the Home transition we asked for is over (its end state not readable here: 0.6 s after it)", YES);
            });
            continue;
        }
        DMSMAfterHomeRun(w, [NSString stringWithFormat:@"the Home transition we asked for is over (%@)", want ? [NSString stringWithFormat:@"our Home #%lu", (unsigned long)gen] : @"SpringBoard's Home press"], YES);
    }
}
// The desktop's last window, closed (DMSMWindowAction): its removal once the Home transition we asked for is over (above).
static void DMSMAfterOurHome(NSString *what, id item, dispatch_block_t block) {
    if (!block) return;
    if (!gSMAfterHomeHooked || !item) {   // (its end is not seen here: the wait it always had)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
        return;
    }
    DM_FEATURE_MARK("sm-close-after-home");
    if (!gSMAfterHome) gSMAfterHome = [NSMutableArray array];
    // (the Home asked for just before -- SMHome.h DMSMGoHomeForReal: its number, or 0 when SpringBoard's own Home press stood in)
    NSUInteger want = gSMRealHomeAskedGen;
#if DEBUG
    if (want && DMTestFlag("/tmp/msb-afterhome-otherhome")) want++;   // (test: wait for a Home that never comes -- every end is "not ours", then the 4 s)
#endif
    NSArray *w = @[what ?: @"a window's removal", item, [block copy], @(want), @(CACurrentMediaTime())];
    [gSMAfterHome addObject:w];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSMAfterHomeMaxWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([gSMAfterHome indexOfObjectIdenticalTo:w] == NSNotFound) return;
        [gSMAfterHome removeObjectIdenticalTo:w];
        DMSMAfterHomeRun(w, @"no end of the Home transition seen in 4 s: now", NO);
    });
}
static void DMSMAfterHomeInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = objc_getClass("SBMainSwitcherControllerCoordinator");
    SEL s = sel_registerName("layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:");
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(void), @encode(id), @encode(id), NULL)]) {
        DMLog(@"[smengine] the end of SpringBoard's layout transitions is not as expected here: the desktop's last window leaves the App Switcher 0.6 s after the Home Screen is asked for");
        return;
    }
    MSHookMessageEx(c, s, (IMP)DMSMTransitionDidEnd, (IMP *)&o_SMTransitionDidEnd);
    gSMAfterHomeHooked = o_SMTransitionDidEnd != NULL;
    DMLog(gSMAfterHomeHooked ? @"[smengine] the desktop's last window leaves the App Switcher once the Home transition is over" : @"[smengine] the layout transition's end hook did not go in: 0.6 s after the Home Screen is asked for");
}
