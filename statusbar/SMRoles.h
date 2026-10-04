// SMRoles.h -- which layout roles a Stage Manager window can take, so how many windows one desktop holds (sm-nolimit, 4 Oct 2026). Plain C on
// Foundation (no SpringBoard API): StatusBar.x (SMLimit.h hands it SpringBoard's own answers at start), SMDeskJoin.h and the Mac test
// tools/test-smroles.m run this very code.
// A Stage Manager window is an item of its stage (SBAppLayout) in a LAYOUT ROLE. SpringBoard's role space (16.7.7 disassembled, the same in the
// 17.6.1 decompile; every name below is exported by SpringBoard.framework on all 16.x builds read and in the 17.0-18.6 tbds):
// SBLayoutRoleMin 1 .. SBLayoutRoleMax 10; Primary 1, Side 2, Floating 3 (Slide Over), Centre 4, additional sides from 5. A stage is built from
// a role dictionary by enumerating the valid roles (1..9), a transition's roles are read the same way, and SBLayoutRoleIsValidForSplitView --
// the roles a window of a stage may hold -- says 1, 2, 5, 6, 7, 8, 9. So a stage holds at most 7 windows: SpringBoard's own role space, not a
// setting. Apple's "4 windows" is a setting on top (SBSwitcherChamoisSettings maximumNumberOfAppsOnStage, answered by SMLimit.h), and the engine
// used to have its own copy of it (roles 1, 2, 5, 6). Here: the table the engine uses everywhere instead -- the window roles in the order new
// windows take them (first free first), from SpringBoard's own functions when they answer as expected, else the four the engine ran with.
#pragma once
#import <Foundation/Foundation.h>

#define DMSM_ROLES_MAX 16
static long long gDMSMRoles[DMSM_ROLES_MAX] = {1, 2, 5, 6};
static size_t gDMSMRoleCount = 4;
static BOOL gDMSMRolesFromSB = NO;   // (the table came from SpringBoard's own role functions; NO: the four of 1.3.5)

// SpringBoard's own window roles as read at start (count 0: not read, or not as expected). Kept when the engine's table falls back to four later
// (SMLimit.h DMSMLimitTick: another tweak keeps answering Apple's limit) -- a desktop of seven may still be on screen then, and the role repair
// (SMLimit.h DMSMRepairRoles) scans these (1.3.6 logic test L-6).
static long long gDMSMSBRoles[DMSM_ROLES_MAX];
static size_t gDMSMSBRoleCount = 0;
// How many windows a desktop holds: one per window role.
static size_t DMSMWindowCap(void) { return gDMSMRoleCount; }
static BOOL DMSMIsWindowRole(long long r) { for (size_t i = 0; i < gDMSMRoleCount; i++) if (gDMSMRoles[i] == r) return YES; return NO; }
// The highest window role: a transition's roles are read 1..this (the floating and centre roles 3 and 4 among them: they tell what it is).
static long long DMSMRoleTop(void) { long long m = 0; for (size_t i = 0; i < gDMSMRoleCount; i++) if (gDMSMRoles[i] > m) m = gDMSMRoles[i]; return m; }
// The first window role not in `used` (NSNumber roles), 0 when every one is taken; it is added to `used` when that is mutable.
static long long DMSMFirstFreeRole(NSSet<NSNumber *> *used) {
    for (size_t i = 0; i < gDMSMRoleCount; i++) {
        if ([used containsObject:@(gDMSMRoles[i])]) continue;
        if ([used isKindOfClass:[NSMutableSet class]]) [(NSMutableSet *)used addObject:@(gDMSMRoles[i])];
        return gDMSMRoles[i];
    }
    return 0;
}
static NSSet<NSNumber *> *DMSMWindowRoleSet(void) {
    NSMutableSet *s = [NSMutableSet set];
    for (size_t i = 0; i < gDMSMRoleCount; i++) [s addObject:@(gDMSMRoles[i])];
    return s;
}
static NSString *DMSMRolesText(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (size_t i = 0; i < gDMSMRoleCount; i++) [a addObject:[NSString stringWithFormat:@"%lld", gDMSMRoles[i]]];
    return [a componentsJoinedByString:@", "];
}
static void DMSMRolesReset(void) {
    static const long long four[] = {1, 2, 5, 6};
    for (size_t i = 0; i < 4; i++) gDMSMRoles[i] = four[i];
    gDMSMRoleCount = 4; gDMSMRolesFromSB = NO;
}

// SpringBoard's answers, as the start-up code reads them: SBLayoutRoleIsValidForSplitView (a function: role -> BOOL; NULL = not found) and the
// exported constants Primary, Side, AdditionalSideRangeMin, AdditionalSideRangeMax, SBLayoutRoleMax (-1 = not found).
typedef BOOL (*DMSMRoleTestFn)(long long role);
// The window roles: Primary, Side, then the additional sides from RangeMin up while SpringBoard says a window may hold them (never past RangeMax
// or SBLayoutRoleMax). Refused (0, *why says why) unless it looks like what the engine was built and tested on -- primary 1, side 2, the floating
// and centre roles 3 and 4 no window roles, the table starting 1, 2, 5, 6 -- and holds 4 to DMSM_ROLES_MAX roles. out: room for DMSM_ROLES_MAX.
// (noinline: its own range in the crash map of release builds too -- tools/test-crashstep.sh checks it maps to Windowing)
__attribute__((noinline)) static size_t DMSMRolesDerive(DMSMRoleTestFn splitViewValid, long long primary, long long side, long long addMin, long long addMax, long long roleMax,
                              long long *out, NSString **why) {
    #define DMSM_ROLES_NO(text) do { if (why) *why = (text); return 0; } while (0)
    if (!splitViewValid) DMSM_ROLES_NO(@"SBLayoutRoleIsValidForSplitView not found");
    if (primary != 1 || side != 2) DMSM_ROLES_NO(([NSString stringWithFormat:@"primary %lld, side %lld (the engine reads 1 and 2)", primary, side]));
    if (addMin != 5) DMSM_ROLES_NO(([NSString stringWithFormat:@"additional sides from %lld (the engine was built on 5)", addMin]));
    if (addMax < addMin + 1 || roleMax < addMin + 1) DMSM_ROLES_NO(([NSString stringWithFormat:@"additional sides up to %lld, roles up to %lld", addMax, roleMax]));
    if (!splitViewValid(primary) || !splitViewValid(side)) DMSM_ROLES_NO(@"primary or side not a window role");
    if (splitViewValid(3) || splitViewValid(4)) DMSM_ROLES_NO(@"the floating or centre role counted as a window role");
    size_t n = 0;
    out[n++] = primary; out[n++] = side;
    long long top = addMax < roleMax ? addMax : roleMax;
    for (long long r = addMin; r <= top && r <= 64 && n < DMSM_ROLES_MAX; r++) {
        if (!splitViewValid(r)) break;   // (contiguous from RangeMin, as SpringBoard numbers them: index n >= 2 -> role n + 3)
        out[n++] = r;
    }
    if (n < 4 || out[2] != 5 || out[3] != 6) DMSM_ROLES_NO(([NSString stringWithFormat:@"only %zu window roles", n]));
    if (why) *why = nil;
    return n;
    #undef DMSM_ROLES_NO
}
// The roles the role repair reads: SpringBoard's own when they were read, else the engine's table (both start 1, 2, 5).
static const long long *DMSMRepairRoleList(size_t *n) {
    if (gDMSMSBRoleCount >= 4) { *n = gDMSMSBRoleCount; return gDMSMSBRoles; }
    *n = gDMSMRoleCount; return gDMSMRoles;
}
// The table from SpringBoard's answers (YES), or the four of 1.3.5 kept (NO, *why says why).
static BOOL DMSMRolesSetFrom(DMSMRoleTestFn splitViewValid, long long primary, long long side, long long addMin, long long addMax, long long roleMax, NSString **why) {
    long long tmp[DMSM_ROLES_MAX];
    size_t n = DMSMRolesDerive(splitViewValid, primary, side, addMin, addMax, roleMax, tmp, why);
    if (!n) { DMSMRolesReset(); return NO; }
    for (size_t i = 0; i < n; i++) { gDMSMRoles[i] = tmp[i]; gDMSMSBRoles[i] = tmp[i]; }
    gDMSMRoleCount = n; gDMSMSBRoleCount = n; gDMSMRolesFromSB = YES;
    return YES;
}
