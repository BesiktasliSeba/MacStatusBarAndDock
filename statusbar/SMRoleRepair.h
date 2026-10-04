// SMRoleRepair.h -- Minimize keeps every other window where it is, and no window is ever in two roles of one layout state (1.3.6, 4 Oct 2026).
// Plain C on Foundation (no SpringBoard API): SMLimit.h DMSMRepairRoles reads a transition context into this shape and writes the answer back;
// the Mac test tools/test-smrolerepair.m runs this very code.
// Stage Manager's own Minimize ("removeFromSet": -[SBMedusaDecoratedDeviceApplicationSceneViewController _topAffordanceViewController:
// handleActionType:transitionSource:], its modifyApplicationContext block; 16.7.7 disassembled, confirmed on the iPad 2) writes, for each valid
// role r: below the window it takes out "as it was" (+[SBPreviousWorkspaceEntity entity], no role named); its own role nothing; above it the
// window of r moved down one role (an SBPreviousWorkspaceEntity naming r, written into the role before). Two flaws, both in how
// -[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:] then reads it:
//  1. "as it was" keeps its window only in the primary and side roles. In an additional side role (5 and up) it resolves to SpringBoard's empty
//     entity (that block asks with no same-role fallback): every window in roles 5 .. below the minimized one LEFT the desktop too, into the
//     minimized window's new stage (iPad 2, four windows, Weather in role 6 minimized: Tips of role 5 went with it -- also in 1.3.5).
//  2. The highest valid role (9) is only ever a source, never written; a role left unset keeps its previous window. Always empty with Apple's
//     four windows; with seven, the window of role 9 stayed there AND was moved into role 8 -- two layout elements with one identifier, the
//     traits participants (keyed by it) one fewer, and -[SBSwitcherController _orientationsForLayoutStateElements:withAssociatedParticipants:]
//     aborted "out of sync" (every Minimize on a seven-window desktop). Minimizing the window of role 9 itself wrote nothing: it stayed.
// The repair, before SpringBoard reads the context (additional side roles only -- the primary and side roles resolve as Apple means them):
//  R1 "as it was" in an additional side role that has a window: rewritten as the previous window of that same role (what it means) -- unless
//     the context names that window in another role: then it moves there (the window shelf's swap, -[SBSwitcherShelfViewController
//     _performSwitcherTransitionRequest:]: the picked window into the shelf's role, "as it was" into every other role; keeping a picked window
//     that was already on the stage would put it in two roles -- 1.3.6 logic test M-1).
//  R2 a window then in two roles: the role that only kept it (left unset) is emptied, the role that names it (the move) keeps it.
//  R3 the window our own Minimize takes out, still kept in its own unset role: emptied -- only in a context that writes window roles itself, as
//     Minimize always does (a plain or a background activation coming while the note is still fresh writes none: left alone, logic test L-1).
#pragma once
#import <Foundation/Foundation.h>

// What a transition context has in one role, as SpringBoard will read it.
enum {
    DMSMSlotUnset = 0,   // nothing written: SpringBoard keeps the role's previous window ("was")
    DMSMSlotPrev  = 1,   // an SBPreviousWorkspaceEntity: the previous window of role "to"; to 0 = "as it was" (no role named)
    DMSMSlotApp   = 2,   // an app's window ("id")
    DMSMSlotEmpty = 3,   // SpringBoard's empty entity: nothing in that role
    DMSMSlotOther = 4,   // anything else (the Home Screen, ...): no window of a stage
};
// slots: one per window role, @{@"r": role, @"k": kind, @"to": role a DMSMSlotPrev names (0: none), @"id": the window's identifier (DMSMSlotApp),
// @"was": identifier of the window the previous layout state has in that role (absent: none)}. addMin: the first additional side role (5).
// removingRole / removingId: the window our own Minimize takes out (0 / nil: none). Returns @{@"keep": roles to write as the previous window of
// that same role (R1), @"empty": roles to empty (R2, R3)} (ascending; both empty: nothing to do); *why says what was found (nil when nothing).
// (noinline: its own range in the crash map of release builds too -- tools/test-crashstep.sh checks it maps to Windowing)
__attribute__((noinline)) static NSDictionary<NSString *, NSArray<NSNumber *> *> *DMSMRoleRepairPlan(NSArray<NSDictionary *> *slots, long long addMin, long long removingRole, NSString *removingId, NSString **why) {
    NSMutableDictionary<NSNumber *, NSDictionary *> *byRole = [NSMutableDictionary dictionary];
    for (NSDictionary *s in slots) { long long r = [s[@"r"] longLongValue]; if (r > 0) byRole[@(r)] = s; }
    NSArray<NSNumber *> *roles = [byRole.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *notes = [NSMutableArray array];
    // R1: "as it was" where SpringBoard would drop the window -- named as the previous window of that role, unless the context names that window
    // in another role (an app entity, or a previous entity of its role written elsewhere): it moves there
    NSMutableDictionary<NSString *, NSNumber *> *namedIn = [NSMutableDictionary dictionary];   // (window -> a role whose context names it)
    for (NSNumber *role in roles) {
        NSDictionary *s = byRole[role];
        int k = [s[@"k"] intValue]; long long to = [s[@"to"] longLongValue];
        NSString *w = k == DMSMSlotApp ? s[@"id"] : (k == DMSMSlotPrev && to > 0 ? byRole[@(to)][@"was"] : nil);
        if ([w isKindOfClass:[NSString class]] && w.length && !namedIn[w]) namedIn[w] = role;
    }
    NSMutableSet<NSNumber *> *keep = [NSMutableSet set];
    for (NSNumber *role in roles) {
        NSDictionary *s = byRole[role];
        if ([s[@"k"] intValue] != DMSMSlotPrev || [s[@"to"] longLongValue] > 0 || role.longLongValue < addMin || ![s[@"was"] length]) continue;
        NSNumber *other = namedIn[s[@"was"]];
        if (other && ![other isEqual:role]) { [notes addObject:[NSString stringWithFormat:@"%@ moves to role %@: not kept in role %@", s[@"was"], other, role]]; continue; }
        [keep addObject:role];
        [notes addObject:[NSString stringWithFormat:@"%@ kept in role %@", s[@"was"], role]];
    }
    // The window each role holds once SpringBoard reads the context (R1 applied), and whether the context names it or only keeps it (unset).
    NSMutableDictionary<NSNumber *, NSString *> *holds = [NSMutableDictionary dictionary];
    NSMutableSet<NSNumber *> *implicitRoles = [NSMutableSet set];
    for (NSNumber *role in roles) {
        NSDictionary *s = byRole[role];
        NSString *w = nil;
        switch ([s[@"k"] intValue]) {
            case DMSMSlotUnset: w = s[@"was"]; if (w) [implicitRoles addObject:role]; break;
            case DMSMSlotPrev: {
                long long to = [s[@"to"] longLongValue];
                if (to > 0) w = byRole[@(to)][@"was"];
                else if (role.longLongValue < addMin || [keep containsObject:role]) w = s[@"was"];   // (primary / side: SpringBoard's own same-role answer)
                break;
            }
            case DMSMSlotApp: w = s[@"id"]; break;
            default: break;
        }
        if ([w isKindOfClass:[NSString class]] && w.length) holds[role] = w;
    }
    // R2: one window in two roles
    NSMutableSet<NSNumber *> *empty = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *rolesOf = [NSMutableDictionary dictionary];
    for (NSNumber *role in roles) {
        NSString *w = holds[role];
        if (!w) continue;
        if (!rolesOf[w]) rolesOf[w] = [NSMutableArray array];
        [rolesOf[w] addObject:role];
    }
    for (NSString *w in [rolesOf.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray<NSNumber *> *rs = rolesOf[w];
        if (rs.count < 2) continue;
        NSMutableArray<NSNumber *> *named = [NSMutableArray array], *kept = [NSMutableArray array];
        for (NSNumber *r in rs) [[implicitRoles containsObject:r] ? kept : named addObject:r];
        NSMutableArray<NSNumber *> *giveUp = [NSMutableArray array];
        if (named.count) [giveUp addObjectsFromArray:kept];
        else if (kept.count > 1) [giveUp addObjectsFromArray:[kept subarrayWithRange:NSMakeRange(1, kept.count - 1)]];   // (cannot happen: a previous layout state never held one window twice)
        BOOL done = NO;
        for (NSNumber *r in giveUp) {
            if (r.longLongValue < addMin) { [notes addObject:[NSString stringWithFormat:@"%@ in roles %@: role %@ is not an additional side, left", w, [rs componentsJoinedByString:@"+"], r]]; continue; }
            [empty addObject:r]; done = YES;
        }
        if (done) [notes addObject:[NSString stringWithFormat:@"%@ in roles %@", w, [rs componentsJoinedByString:@"+"]]];
        else if (!giveUp.count) [notes addObject:[NSString stringWithFormat:@"%@ named in roles %@ by the context itself: left", w, [rs componentsJoinedByString:@"+"]]];
    }
    // R3: the window our Minimize takes out, still kept in its own role (the context left it unset: the role the shift never writes) -- in a
    // context that writes window roles itself (Apple's Minimize always does)
    BOOL writesRoles = NO;
    for (NSNumber *role in roles) if ([byRole[role][@"k"] intValue] != DMSMSlotUnset) writesRoles = YES;
    if (removingRole > 0 && removingId.length && writesRoles) {
        NSDictionary *s = byRole[@(removingRole)];
        if (s && [s[@"k"] intValue] == DMSMSlotUnset && [s[@"was"] isEqual:removingId]) {
            if (removingRole >= addMin) { [empty addObject:@(removingRole)]; [notes addObject:[NSString stringWithFormat:@"%@ (minimized) still in role %lld", removingId, removingRole]]; }
            else [notes addObject:[NSString stringWithFormat:@"%@ (minimized) still in role %lld: not an additional side, left", removingId, removingRole]];
        }
    }
    [keep minusSet:empty];   // (never both)
    if (why) *why = notes.count ? [notes componentsJoinedByString:@"; "] : nil;
    return @{@"keep": [keep.allObjects sortedArrayUsingSelector:@selector(compare:)], @"empty": [empty.allObjects sortedArrayUsingSelector:@selector(compare:)]};
}
