// SMGestureHold.h -- a switcher gesture's stage is left alone until the gesture's transition is over (1.4.5, GitHub issue #7). Included by
// SMEngineAPI.h just before the stage writes it gates (DMSMReplaceStage, DMSMRequestPlan); the finalize paths (SMHome.h, SMDesktop.h, SMLimit.h)
// and DMSMWindowAction (StatusBar.x) ask it too. Plain Objective-C (the Mac tests include SMEngineAPI.h); SpringBoard's side -- the gesture
// transaction's hooks -- is SMGestureHook.h.
// SpringBoard's Home gesture takes the stage under the finger as it begins (-[SBHomeGestureSwitcherModifier _selectedAppLayout], Reduce Motion's
// modifier the same) and, until the gesture's workspace transaction is over, finds that stage again with -indexOfObject: in the switcher's list,
// with no not-found check (-appLayoutsToCacheSnapshots -> -appLayoutsToCacheSnapshotsWithVisibleRange:{index, 1}...; 16.7.7 SpringBoard +0x581074
// and +0x20a2b0, disassembled). A stage that left the list meanwhile gives NSNotFound -> -[NSArray subarrayWithRange:] throws -> SIGABRT (iPad 2
// 16.7.7, 13 Oct; 16.1.1 asserts in the same method instead, SBHomeGestureSwitcherModifier.m:1358, issue #7). A stage leaves the list when a stage
// sharing a window with it is put in front (-[SBMainSwitcherControllerCoordinator _addAppLayoutToFront:removeAppLayout:] drops every stage that
// -containsAnyItemFromSet: of the new one -- one window, one stage) or when it is replaced in the model (-replaceAppLayout:withAppLayout:).
// So while a gesture's transaction runs, no write of ours changes a stage it holds: the stage on screen when it began and the stages its own end
// comes from and goes to. Such a write waits for the transaction's end (DMSMAfterGesture) and then runs as it would have; writes that touch no
// held stage (another Mac Switcher desktop's windows) go ahead at once.
#pragma once
#include <QuartzCore/QuartzCore.h>   // (CACurrentMediaTime)

static NSHashTable *gSMGestureTxs;                       // (the gesture transactions running now: SpringBoard's, weak)
static NSMutableSet<NSString *> *gSMGestureHeld;         // (the windows of the stages they hold: their identifiers)
static NSMutableArray<NSArray *> *gSMAfterGesture;       // (the writes waiting for their end: @[what, block, when queued])
static CFTimeInterval gSMGestureSince = 0;
static BOOL gSMGestureHooked = NO;                       // (the transaction's begin and end are seen: else the fallback below)
static CFTimeInterval gSMGestureFallbackUntil = 0;       // (no hooks: a gesture's own end counts as running for a moment -- see DMSMGestureLive)
static const CFTimeInterval kSMAfterGestureMaxWait = 3.0;   // (a write still waiting this long after it was asked for is no longer what the user wants)
static const CFTimeInterval kSMGestureFallbackHold = 1.2;

static void DMSMGestureFlushSoon(void);
static void DMSMGestureFlush(void);
static NSSet<NSString *> *DMSMStageWindowIds(id stage) {
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (id it in DMSMStageItemsMap(stage)) { NSString *u = DMSMItemUid(it); if (u) [ids addObject:u]; }
    return ids;
}
// A gesture's transaction is running now (also: the fallback's moment after a gesture's own end, when the hooks are not there).
static BOOL DMSMGestureLive(void) {
    if (!gSMGestureHooked) return CACurrentMediaTime() < gSMGestureFallbackUntil;
    // (a transaction counts as long as it is there and not complete -- however long the finger stays down: SpringBoard's gesture holds its stage
    //  all that time. One that completed without our end hook, or went away, is dropped; then the writes it held run -- else they waited for the
    //  next gesture: review of r5)
    NSUInteger n = 0, dropped = 0;
    for (id t in gSMGestureTxs.allObjects) {
        SEL done = NSSelectorFromString(@"isComplete");
        if ([t respondsToSelector:done] && ((BOOL (*)(id, SEL))objc_msgSend)(t, done)) { [gSMGestureTxs removeObject:t]; dropped++; continue; }
        n++;
    }
    static NSUInteger lastN = 0;
    BOOL ended = lastN > 0 && n == 0 && (dropped || gSMGestureTxs.count == 0);
    lastN = n;
    if (ended && gSMAfterGesture.count) dispatch_async(dispatch_get_main_queue(), ^{ DMSMGestureFlush(); });
    return n > 0;
}
static void DMSMGestureHold(id stage) {   // (a stage the running gesture holds: its windows)
    if (!DMSMIsStage(stage) || !DMSMGestureLive()) return;
    if (!gSMGestureHeld) gSMGestureHeld = [NSMutableSet set];
    [gSMGestureHeld unionSet:DMSMStageWindowIds(stage)];
}
static BOOL DMSMGestureHoldsAny(NSSet<NSString *> *ids) {
    return ids.count && DMSMGestureLive() && [gSMGestureHeld intersectsSet:ids];
}
static BOOL DMSMGestureHoldsStage(id stage) { return DMSMIsStage(stage) && DMSMGestureHoldsAny(DMSMStageWindowIds(stage)); }
// A transition context that is a switcher gesture's own end ("FinalFluidSwitcherGestureAction", read on 16.7.7), or any context while one runs.
static BOOL DMSMGestureCtx(id ctx) {
    if (DMSMGestureLive()) return YES;
    SEL rq = NSSelectorFromString(@"request"), lb = NSSelectorFromString(@"eventLabel");
    id req = ctx && [ctx respondsToSelector:rq] ? ((id (*)(id, SEL))objc_msgSend)(ctx, rq) : nil;
    id label = req && [req respondsToSelector:lb] ? ((id (*)(id, SEL))objc_msgSend)(req, lb) : nil;
    BOOL final = [label isKindOfClass:[NSString class]] && [label isEqualToString:@"FinalFluidSwitcherGestureAction"];
    if (final && !gSMGestureHooked) gSMGestureFallbackUntil = CACurrentMediaTime() + kSMGestureFallbackHold;
    return final;
}
// The write runs once no gesture's transaction runs: queued in order while one does, else on the next turn of the main queue (never inside the
// SpringBoard call we were asked from -- the 1.4.1 "21:32" lesson).
static void DMSMAfterGesture(NSString *what, dispatch_block_t block) {
    if (!block) return;
    if (!gSMAfterGesture) gSMAfterGesture = [NSMutableArray array];
    [gSMAfterGesture addObject:@[what ?: @"a write", [block copy], @(CACurrentMediaTime())]];
    DMLog([NSString stringWithFormat:@"[smgesture] %@: right after the switcher gesture's transition (it holds that stage)", what ?: @"a write"]);
    DMSMGestureFlushSoon();
}
// The same, once per gesture: SpringBoard finalizes a transition's context more than once (two "roles already set" lines per transition), and
// each would queue the same join or Home again -- the later one replaces the earlier (the iPad 2 asked for the same join twice, r1).
static void DMSMAfterGestureOnce(NSString *what, dispatch_block_t block) {
    for (NSArray *w in [gSMAfterGesture copy]) if ([w[0] isEqualToString:what]) [gSMAfterGesture removeObject:w];
    DMSMAfterGesture(what, block);
}
static void DMSMGestureFlush(void) {
    if (DMSMGestureLive()) {   // (another gesture began meanwhile: its end flushes; without the hooks, the moment after it)
        if (!gSMGestureHooked) DMSMGestureFlushSoon();
        return;
    }
    gSMGestureHeld = nil;
    NSArray<NSArray *> *todo = gSMAfterGesture;
    gSMAfterGesture = nil;
    CFTimeInterval now = CACurrentMediaTime();
    for (NSArray *w in todo) {
        if (now - [w[2] doubleValue] > kSMAfterGestureMaxWait) { DMLog([NSString stringWithFormat:@"[smgesture] %@: asked for %.1f s ago -- left", w[0], now - [w[2] doubleValue]]); continue; }
        @try { ((dispatch_block_t)w[1])(); }
        @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smgesture] %@ after the gesture failed: %@", w[0], e.reason]); }
    }
}
static void DMSMGestureFlushSoon(void) {
    if (!gSMAfterGesture.count) return;
    if (gSMGestureHooked) { if (!DMSMGestureLive()) dispatch_async(dispatch_get_main_queue(), ^{ DMSMGestureFlush(); }); return; }
    CFTimeInterval wait = MAX(0.0, gSMGestureFallbackUntil - CACurrentMediaTime());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((wait + 0.02) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMSMGestureFlush(); });
}
