// SMLimit.h -- more than four windows on a Stage Manager desktop (sm-nolimit, 4 Oct 2026). Included by StatusBar.x after SMDesktop.h (every DMSM
// helper it uses is defined above that point; StatusBar.x's calls into it are declared before their use).
// Apple's 4 is a setting: -[SBSwitcherChamoisSettings maximumNumberOfAppsOnStage] (its ivar, 4 from setDefaultValues; TrollPad's TweakSB.x
// answers 5 and never asks the original). -[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:] drops the oldest
// windows past it from every new layout state (16.7.7 disassembled; the 17.6.1 decompile the same), and Stage Manager's own drags and drops
// refuse a full stage by it. While our engine runs it is answered with the number of window roles SpringBoard has (SMRoles.h, filled here from
// SpringBoard's own exported role functions: 7 on 16.7.7) -- SpringBoard's own ceiling, past which a stage can't hold a window at all; otherwise
// (another engine, Stage Manager off, the engine not picked) with whatever answered before. Optional: a missing row, another signature or role
// functions that do not answer as expected leave Apple's limit and the engine's table at 1, 2, 5, 6 (four windows, as in 1.3.5), logged once.
// Order of hooks: TrollPadSB.dylib loads after us and replaces the same getter without calling the one before it, so ours is put on top again
// once every tweak has loaded (the main queue after %ctor) and whenever the watcher finds another implementation there (a few times at most:
// another tweak doing the same would trade places with us forever). A hook put on top of ours that does call its original comes back into
// ours: that inner call answers with the implementation from before our first hook, so nothing loops.
#pragma once
#include "SMRoles.h"
#include "SMRoleRepair.h"

static NSString *gSMLimitOff = @"not set up";               // (nil: answered with the window roles' count while our engine runs; else why not)
static unsigned long long (*o_SMMaxApps)(id, SEL);          // (the implementation before our latest hook: Apple's, or another tweak's)
static unsigned long long (*o_SMMaxAppsFirst)(id, SEL);     // (the one before our first hook: what a re-entered call answers with)
static __thread int tSMLimitDepth;
static int gSMLimitRehooks = 0;
static NSString *gSMLimitUnder = nil;                       // (where the implementation under ours lives: SpringBoard, TrollPadSB, ...)
static unsigned long long gSMLimitLastApple = 0, gSMLimitLastAnswer = 0;
static unsigned long long DMSMMaxAppsOnStage(id self, SEL _cmd) {
    if (tSMLimitDepth) return o_SMMaxAppsFirst ? o_SMMaxAppsFirst(self, _cmd) : 4;   // (re-entered through a hook put on top of ours)
    tSMLimitDepth++;
    unsigned long long apple = o_SMMaxApps ? o_SMMaxApps(self, _cmd) : 4, r = apple;
    if (!gSMLimitOff && [NSThread isMainThread] && DMSMEngine()) { unsigned long long cap = (unsigned long long)DMSMWindowCap(); if (cap > r) r = cap; }
    tSMLimitDepth--;
    if ((r != gSMLimitLastAnswer || apple != gSMLimitLastApple) && [NSThread isMainThread]) {   // (one line per change, not per question)
        gSMLimitLastAnswer = r; gSMLimitLastApple = apple;
        if (r > apple) DM_FEATURE_MARK("sm-window-limit-lifted");
        DMLog([NSString stringWithFormat:@"[smlimit] Stage Manager's window limit asked: %llu%@", r, r != apple ? [NSString stringWithFormat:@" (the window roles SpringBoard has; %@ answered %llu)", gSMLimitUnder ?: @"Apple", apple] : @" (not our engine now: as answered under ours)"]);
    }
    return r;
}
// The image an implementation lives in, for the log ("SpringBoard", "TrollPadSB", ...).
static NSString *DMSMLimitImageOf(IMP imp) {
    Dl_info info;
    void *p = (void *)imp;
#if __has_feature(ptrauth_calls)
    p = ptrauth_strip(p, ptrauth_key_function_pointer);
#endif
    if (!p || !dladdr(p, &info) || !info.dli_fname) return @"?";
    NSString *n = [@(info.dli_fname) lastPathComponent];
    return [n stringByDeletingPathExtension];
}
// Ours on top of the getter (again). YES when ours is the one answering afterwards.
static BOOL DMSMLimitHookNow(NSString *why) {
    Class c = objc_getClass("SBSwitcherChamoisSettings");
    SEL s = sel_registerName("maximumNumberOfAppsOnStage");
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) return NO;
    IMP now = method_getImplementation(m);
    if (now == (IMP)DMSMMaxAppsOnStage) return YES;
    IMP before = NULL;
    MSHookMessageEx(c, s, (IMP)DMSMMaxAppsOnStage, &before);
    Method after = class_getInstanceMethod(c, s);
    if (!before || before == (IMP)DMSMMaxAppsOnStage || !after || method_getImplementation(after) != (IMP)DMSMMaxAppsOnStage) {
        DMLog([NSString stringWithFormat:@"[smlimit] could not answer Stage Manager's window limit (%@): the hook did not take", why]);
        return NO;
    }
    if (!o_SMMaxAppsFirst) o_SMMaxAppsFirst = (unsigned long long (*)(id, SEL))before;
    o_SMMaxApps = (unsigned long long (*)(id, SEL))before;
    gSMLimitUnder = DMSMLimitImageOf(before);
    DMLog([NSString stringWithFormat:@"[smlimit] Stage Manager's window limit answered by us (%@; under ours: %@)", why, gSMLimitUnder]);
    return YES;
}
// The table from SpringBoard's own role functions, the row checked, ours on the getter. Once, from the start-up self-check (engine checked).
static void *DMSMSBSymbol(const char *name) {
    static void *h = NULL;
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard", RTLD_NOLOAD | RTLD_LAZY);
    void *p = h ? dlsym(h, name) : NULL;
    return p ?: dlsym(RTLD_DEFAULT, name);
}
static long long DMSMSBConstant(const char *name) { const long long *p = (const long long *)DMSMSBSymbol(name); return p ? *p : -1; }
static void DMSMLimitInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-limit4")) {   // (debug A/B: the engine as 1.3.5 -- four windows, Apple's limit answered as it is)
        DMSMRolesReset();
        gSMLimitOff = @"debug /tmp/msb-sm-limit4";
        DMLog(@"[smlimit] four windows per desktop (debug /tmp/msb-sm-limit4): Apple's limit as it is, roles 1, 2, 5, 6");
        return;
    }
#endif
    NSString *why = nil;
    DMSMRoleTestFn split = (DMSMRoleTestFn)DMSMSBSymbol("SBLayoutRoleIsValidForSplitView");
    BOOL roles = DMSMRolesSetFrom(split, DMSMSBConstant("SBLayoutRolePrimary"), DMSMSBConstant("SBLayoutRoleSide"), DMSMSBConstant("SBLayoutRoleAdditionalSideRangeMin"),
                                  DMSMSBConstant("SBLayoutRoleAdditionalSideRangeMax"), DMSMSBConstant("SBLayoutRoleMax"), &why);
    // (the row: the getter is there with the signature we answer with -- an unsigned 64-bit count, Q16@0:8)
    Class c = objc_getClass("SBSwitcherChamoisSettings");
    Method m = c ? class_getInstanceMethod(c, sel_registerName("maximumNumberOfAppsOnStage")) : NULL;
    NSString *row = !m ? @"-[SBSwitcherChamoisSettings maximumNumberOfAppsOnStage] missing"
                  : (![DMSMSigOfMethod(m) isEqualToString:DMSMSigULL()] ? [NSString stringWithFormat:@"-[SBSwitcherChamoisSettings maximumNumberOfAppsOnStage] is %@, we answer %@", DMSMSigOfMethod(m), DMSMSigULL()] : nil);
    if (!roles || row) {
        if (row) DMSMRolesReset();   // (Apple's limit can't be answered: the engine keeps its four, as in 1.3.5)
        gSMLimitOff = row ?: [@"SpringBoard's role functions: " stringByAppendingString:why ?: @"?"];
        DMLog([NSString stringWithFormat:@"[smlimit] four windows per desktop here (as in 1.3.5): %@", gSMLimitOff]);
        return;
    }
    if (!DMSMLimitHookNow(@"at start")) { DMSMRolesReset(); gSMLimitOff = @"the hook did not take"; return; }
    gSMLimitOff = nil;
    DM_FEATURE_MARK("sm-window-roles");
    DMLog([NSString stringWithFormat:@"[smlimit] %zu windows per desktop: SpringBoard's window roles %@ (Apple's setting: 4)", DMSMWindowCap(), DMSMRolesText()]);
    // (every tweak loaded by the time the main queue runs: TrollPad's replacement, installed after ours, is put under ours again)
    dispatch_async(dispatch_get_main_queue(), ^{ DMSMLimitHookNow(@"after every tweak loaded"); });
}
// The watcher, while our engine runs (every 2 s at most): ours still the one answering? Put back on top a few times, then left (logged).
static void DMSMLimitTick(void) {
    static CFTimeInterval last = 0;
    if (gSMLimitOff) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 2.0) return;
    last = now;
    Class c = objc_getClass("SBSwitcherChamoisSettings");
    Method m = c ? class_getInstanceMethod(c, sel_registerName("maximumNumberOfAppsOnStage")) : NULL;
    if (!m || method_getImplementation(m) == (IMP)DMSMMaxAppsOnStage) return;
    if (gSMLimitRehooks >= 3) {   // (left to it -- and the engine back to its four, which every answer we know of allows: Apple 4, TrollPad 5)
        NSString *who = DMSMLimitImageOf(method_getImplementation(m));
        DMSMRolesReset();
        gSMLimitOff = [NSString stringWithFormat:@"%@ keeps answering the limit itself", who];
        DMLog([NSString stringWithFormat:@"[smlimit] another implementation keeps answering Stage Manager's window limit (%@): left to it, four windows per desktop", who]);
        return;
    }
    gSMLimitRehooks++;
    DMSMLimitHookNow([NSString stringWithFormat:@"%@ had put its own over ours", DMSMLimitImageOf(method_getImplementation(m))]);
}
#if DEBUG
// smlimit: the table, Apple's setting as asked now, the stage on screen's windows and roles (read-only).
static void DMSMLimitDebug(void) {
    @try {
        NSMutableString *o = [NSMutableString stringWithFormat:@"[smlimit] roles %@ (%@), %zu windows per desktop; %@", DMSMRolesText(), gDMSMRolesFromSB ? @"SpringBoard's" : @"the engine's four",
                              DMSMWindowCap(), gSMLimitOff ? [@"off: " stringByAppendingString:gSMLimitOff] : @"answered by us"];
        Class c = objc_getClass("SBSwitcherChamoisSettings");
        Method m = c ? class_getInstanceMethod(c, sel_registerName("maximumNumberOfAppsOnStage")) : NULL;
        if (m) [o appendFormat:@"; getter in %@%@, under ours %@, put back %d time(s)", DMSMLimitImageOf(method_getImplementation(m)), method_getImplementation(m) == (IMP)DMSMMaxAppsOnStage ? @" (ours)" : @"", gSMLimitUnder ?: @"-", gSMLimitRehooks];
        id root = DMCall(objc_getClass("SBAppSwitcherDomain"), @"rootSettings");
        id cs = [root respondsToSelector:NSSelectorFromString(@"chamoisSettings")] ? DMCall(root, @"chamoisSettings") : nil;
        if (cs && m && [DMSMSigOfMethod(m) isEqualToString:DMSMSigULL()]) [o appendFormat:@"; asked now: %llu", ((unsigned long long (*)(id, SEL))objc_msgSend)(cs, sel_registerName("maximumNumberOfAppsOnStage"))];
        id stage = DMSMFrontStage();
        NSDictionary *map = DMSMStageItemsMap(stage);
        NSMutableArray *w = [NSMutableArray array];
        for (id it in map) [w addObject:[NSString stringWithFormat:@"%@ %lld", DMSMItemBundle(it) ?: @"?", DMSMRoleOr(stage, it, -1)]];
        [o appendFormat:@"; stage on screen: %lu window(s) [%@]; engine %d", (unsigned long)map.count, [w componentsJoinedByString:@", "], DMSMEngine()];
        DMLog(o);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smlimit] failed: %@", e.reason]); }
}
#endif

// ---- Minimize keeps the other windows, one window per role (SMRoleRepair.h has the why and the rule; Mac test tools/test-smrolerepair.sh) ----
// Called from the finalize hook (StatusBar.x, %group SMEngine) for every transition context while our engine runs, after the desktop join and
// before SpringBoard builds the layout state from it. The previous windows are read from the context's previous layout state (its provider's
// current one, as -layoutState reads it; -finalize clears and recomputes both) -- not from -previousEntityForLayoutRole:, which SpringBoard fills
// only while it builds the layout state (-[SBLayoutStateManager layoutStateForApplicationTransitionContext:]). Read with the same checks as
// everything else; a refused read leaves the context as SpringBoard built it.
static NSString *gSMRemovingId = nil;   // (the window our own Minimize takes out, until the context that does it comes: DMSMNoteRemoving)
static long long gSMRemovingRole = 0;
static CFTimeInterval gSMRemovingAt = 0;
// DMSMWindowAction, right before it runs a window's own Minimize: which window (its scene identifier, as SpringBoard's layout elements name it),
// in which role of its stage (the context comes at once, or once the workspace's queue gets to it -- taken by the first context that shows it,
// or dropped after 2 s).
static void DMSMNoteRemoving(NSString *bundle, id stage) {
    gSMRemovingId = nil; gSMRemovingRole = 0;
    if (!bundle.length || !DMSMEngine()) return;
    for (id it in DMSMStageItemsMap(stage)) {
        if (![DMSMItemBundle(it) isEqualToString:bundle]) continue;
        id u = DMCall(it, @"uniqueIdentifier");
        if (![u isKindOfClass:[NSString class]] || ![u length]) return;
        gSMRemovingRole = DMSMRoleOr(stage, it, 0);
        if (gSMRemovingRole <= 0) return;
        gSMRemovingId = [u copy];
        gSMRemovingAt = CACurrentMediaTime();
        return;
    }
}
// The window a layout state has in a role (its element's identifier), nil when none; NO when it could not be read.
static BOOL DMSMStateWindowInRole(id state, long long role, NSString **out) {
    *out = nil;
    SEL ew = NSSelectorFromString(@"elementWithRole:");
    if (![state respondsToSelector:ew] || !DMSMSigOK(state, ew, DMSMSigObjLong(), "elementWithRole:")) return NO;
    id el = ((id (*)(id, SEL, long long))objc_msgSend)(state, ew, role);
    if (!el) return YES;
    SEL ui = NSSelectorFromString(@"uniqueIdentifier");
    if (![el respondsToSelector:ui] || !DMSMSigOK(el, ui, DMSMSigObj(), "uniqueIdentifier")) return NO;
    id u = ((id (*)(id, SEL))objc_msgSend)(el, ui);
    if ([u isKindOfClass:[NSString class]] && [u length]) *out = u;
    return YES;
}
// A workspace entity's identifier: the key SpringBoard's layout elements and their traits participants are matched by.
static NSString *DMSMEntityIdent(id e) {
    SEL sel = NSSelectorFromString(@"uniqueIdentifier");
    if (![e respondsToSelector:sel] || !DMSMSigOK(e, sel, DMSMSigObj(), "uniqueIdentifier")) return nil;
    id u = ((id (*)(id, SEL))objc_msgSend)(e, sel);
    return [u isKindOfClass:[NSString class]] && [u length] ? u : nil;
}
// SpringBoard's own entities: empty (+[SBWorkspaceEntity entity] on SBEmptyWorkspaceEntity -- what a vacated role resolves to) and "the previous
// window of role r" (+[SBPreviousWorkspaceEntity entityWithPreviousLayoutRole:] -- what Minimize writes for every window it moves).
static id DMSMEmptyEntityNew(void) {
    Class c = objc_getClass("SBEmptyWorkspaceEntity");
    SEL s = NSSelectorFromString(@"entity");
    Method m = c ? class_getClassMethod(c, s) : NULL;
    if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMSigObj()]) return nil;
    id e = nil;
    @try { e = ((id (*)(id, SEL))objc_msgSend)(c, s); } @catch (NSException *x) { e = nil; }
    return DMSMEntityFlag(e, @"isEmptyWorkspaceEntity") ? e : nil;
}
static id DMSMPreviousEntityNew(long long role) {
    Class c = objc_getClass("SBPreviousWorkspaceEntity");
    SEL s = NSSelectorFromString(@"entityWithPreviousLayoutRole:");
    Method m = c ? class_getClassMethod(c, s) : NULL;
    if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMSigWithLong()]) return nil;
    id e = nil;
    @try { e = ((id (*)(id, SEL, long long))objc_msgSend)(c, s, role); } @catch (NSException *x) { e = nil; }
    SEL pr = NSSelectorFromString(@"previousLayoutRole");
    if (!DMSMEntityFlag(e, @"isPreviousWorkspaceEntity") || ![e respondsToSelector:pr] || !DMSMSigOK(e, pr, DMSMSigTime(), "previousLayoutRole")) return nil;
    return ((long long (*)(id, SEL))objc_msgSend)(e, pr) == role ? e : nil;
}
__attribute__((noinline)) static void DMSMRepairRoles(id ctx) {   // (noinline: its own range in the release crash map, test-crashstep)
    if (!ctx || !DMSMEngine()) return;
    BOOL removing = gSMRemovingId && CACurrentMediaTime() - gSMRemovingAt < 2.0;
    if (gSMRemovingId && !removing) { gSMRemovingId = nil; gSMRemovingRole = 0; }
    {   // (a background activation: SpringBoard builds it from the layout state as it is and reads no role -- nothing to put right, and the
        //  Minimize note stays for the context that does take the window out)
        SEL bg = NSSelectorFromString(@"isBackground");
        if ([ctx respondsToSelector:bg] && DMSMSigOK(ctx, bg, DMSMSigBool(), "isBackground") && ((BOOL (*)(id, SEL))objc_msgSend)(ctx, bg)) return;
    }
    SEL pls = NSSelectorFromString(@"previousLayoutState");
    if (![ctx respondsToSelector:pls] || !DMSMSigOK(ctx, pls, DMSMSigObj(), "previousLayoutState")) return;
    id state = ((id (*)(id, SEL))objc_msgSend)(ctx, pls);
    if (!state) return;   // (no layout state before this one: nothing on screen to keep)
    NSMutableArray<NSDictionary *> *slots = [NSMutableArray array];
    SEL prevRoleSel = NSSelectorFromString(@"previousLayoutRole");
    size_t nRoles = 0;
    const long long *list = DMSMRepairRoleList(&nRoles);   // (SpringBoard's own window roles: also after the engine's table fell back to four)
    long long top = 0;
    for (size_t i = 0; i < nRoles; i++) if (list[i] > top) top = list[i];
    for (size_t i = 0; i < nRoles; i++) {
        long long r = list[i];
        BOOL ok = NO;
        id e = DMSMCtxEntityForRole(ctx, r, &ok);
        NSString *was = nil;
        if (!ok || !DMSMStateWindowInRole(state, r, &was)) return;   // (refused: DMSMAPIFail said why; left as SpringBoard built it)
        NSMutableDictionary *s = [NSMutableDictionary dictionaryWithObject:@(r) forKey:@"r"];
        if (!e) s[@"k"] = @(DMSMSlotUnset);
        else if (DMSMEntityFlag(e, @"isPreviousWorkspaceEntity")) {
            if (![e respondsToSelector:prevRoleSel] || !DMSMSigOK(e, prevRoleSel, DMSMSigTime(), "previousLayoutRole")) return;
            long long to = ((long long (*)(id, SEL))objc_msgSend)(e, prevRoleSel);
            s[@"k"] = @(DMSMSlotPrev);
            s[@"to"] = @(to >= 1 && to <= MAX(top, 9LL) ? to : 0);   // (SBLayoutRoleUndefined -- "as it was" -- or anything else: no role named)
        } else if (DMSMIsEntity(e)) {
            NSString *ident = DMSMEntityIdent(e);
            if (!ident) return;
            s[@"k"] = @(DMSMSlotApp); s[@"id"] = ident;
        } else if (DMSMEntityFlag(e, @"isEmptyWorkspaceEntity")) s[@"k"] = @(DMSMSlotEmpty);
        else s[@"k"] = @(DMSMSlotOther);
        if (was) s[@"was"] = was;
        [slots addObject:s];
    }
    NSString *why = nil;
    NSDictionary<NSString *, NSArray<NSNumber *> *> *plan = DMSMRoleRepairPlan(slots, nRoles > 2 ? list[2] : 5, removing ? gSMRemovingRole : 0, removing ? gSMRemovingId : nil, &why);
    NSArray<NSNumber *> *keep = plan[@"keep"], *empty = plan[@"empty"];
    if (removing) {   // (taken by this context when it is the one that takes the window out: it names its role, or the repair empties it)
        NSDictionary *mine = nil;
        for (NSDictionary *s in slots) if ([s[@"r"] longLongValue] == gSMRemovingRole) mine = s;
        if (!mine || [mine[@"k"] intValue] != DMSMSlotUnset || [empty containsObject:@(gSMRemovingRole)]) { gSMRemovingId = nil; gSMRemovingRole = 0; }
    }
    if (!keep.count && !empty.count) {
        if (why) DMLog([NSString stringWithFormat:@"[smroles] left as SpringBoard built it: %@", why]);
        return;
    }
    if (!DMSMCtxCanWrite(ctx)) return;
    SEL setE = NSSelectorFromString(@"setEntity:forLayoutRole:");
    NSMutableArray<NSString *> *done = [NSMutableArray array];
    for (NSNumber *r in keep) {
        id e = DMSMPreviousEntityNew(r.longLongValue);
        if (!e) { DMSMAPIFail(@"Minimize keeps the other windows", [NSString stringWithFormat:@"no previous-window entity for role %@: left", r]); continue; }
        @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, e, r.longLongValue); [done addObject:[NSString stringWithFormat:@"%@ kept", r]]; }
        @catch (NSException *x) { DMSMAPIFail(@"Minimize keeps the other windows", [NSString stringWithFormat:@"role %@: %@", r, x.reason ?: @"exception"]); }
    }
    for (NSNumber *r in empty) {   // (a new empty entity for each role, as SpringBoard makes them: -setEntity:forLayoutRole: gives the entity its role)
        id none = DMSMEmptyEntityNew();
        if (!none) { DMSMAPIFail(@"one window, one role", @"SpringBoard's empty entity is not there: left"); break; }
        @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, none, r.longLongValue); [done addObject:[NSString stringWithFormat:@"%@ emptied", r]]; }
        @catch (NSException *x) { DMSMAPIFail(@"one window, one role", [NSString stringWithFormat:@"emptying role %@ failed: %@", r, x.reason ?: @"exception"]); }
    }
    if (!done.count) return;
    if (keep.count) DM_FEATURE_MARK("sm-minimize-keeps-windows");
    if (empty.count) DM_FEATURE_MARK("sm-one-role-per-window");
    DMLog([NSString stringWithFormat:@"[smroles] roles put right before SpringBoard reads the transition: %@ (%@)", [done componentsJoinedByString:@", "], why ?: @"?"]);
}
#if DEBUG
// Debug only: the inputs of the check that aborted (-[SBSwitcherController _orientationsForLayoutStateElements:withAssociatedParticipants:]),
// logged when they do not match -- the elements (role and identifier) and the participants' identifiers -- before Apple's own check runs.
static id (*o_SMOrientCheck)(id, SEL, id, id);
static id DMSMOrientCheck(id self, SEL _cmd, id elements, id participants) {
    @try {
        NSUInteger ne = [elements respondsToSelector:@selector(count)] ? [elements count] : 0, np = [participants respondsToSelector:@selector(count)] ? [participants count] : 0;
        if (ne != np) {
            NSMutableArray *els = [NSMutableArray array];
            for (id el in elements) [els addObject:[NSString stringWithFormat:@"%@ %@", DMCall(el, @"uniqueIdentifier") ?: @"?", [el respondsToSelector:NSSelectorFromString(@"layoutRole")] ? @(((long long (*)(id, SEL))objc_msgSend)(el, NSSelectorFromString(@"layoutRole"))) : @"?"]];
            NSArray *keys = [participants isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)participants allKeys] : @[];
            DMLog([NSString stringWithFormat:@"[smroles] OUT OF SYNC: %lu elements [%@], %lu participants [%@]", (unsigned long)ne, [els componentsJoinedByString:@", "], (unsigned long)np, [keys componentsJoinedByString:@", "]]);
        }
    } @catch (NSException *e) {}
    return o_SMOrientCheck(self, _cmd, elements, participants);
}
static void DMSMHookOrientCheckDebug(void) {
    Class c = objc_getClass("SBSwitcherController");
    SEL s = NSSelectorFromString(@"_orientationsForLayoutStateElements:withAssociatedParticipants:");
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMSigObjObjObj()]) { DMLog(@"[smroles] debug: the orientation check is not as expected here (not watched)"); return; }
    MSHookMessageEx(c, s, (IMP)DMSMOrientCheck, (IMP *)&o_SMOrientCheck);
    DMLog(@"[smroles] debug: the layout state's elements and participants are watched (logged when they do not match)");
}
#endif
