// Mac test of the Stage Manager engine's Home rule (statusbar/SMHomeRule.h, the code StatusBar.x runs in -[SBWorkspaceApplicationSceneTransitionContext
// finalize] through SMHome.h): Home keeps the desktop's windows on screen, a full-screen window goes to the background, the rest closes up in role
// order, and everything that is not "leaving the desktop for the Home Screen" is left as SpringBoard built it. A random sweep checks the plan's
// invariants: each window role at most once, every role either kept or emptied, exactly the windowed windows kept, the newest in front, a plan
// planned again changes nothing. Run with the engine's four roles (1, 2, 5, 6) and with 16.7.7's seven (1, 2, 5-9). Also the App Switcher's
// bookkeeping (DMSMSwitcherNote) and the desktop choice (DMSMStageIsDesktop) of the 1.3.8 logic test fixes.
#import <Foundation/Foundation.h>
#include "../statusbar/SMHomeRule.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSDictionary *W(NSString *ident, long long r, long long t, long long p) { return @{@"id": ident, @"r": @(r), @"t": @(t), @"p": @(p)}; }
static long long RoleOf(NSDictionary *plan, NSString *ident) { for (NSArray *k in plan[@"keep"]) if ([k[0] isEqualToString:ident]) return [k[1] longLongValue]; return -1; }
static NSSet *KeptIds(NSDictionary *plan) { NSMutableSet *s = [NSMutableSet set]; for (NSArray *k in plan[@"keep"]) [s addObject:k[0]]; return s; }

static BOOL Invariants(NSDictionary *plan, NSArray<NSDictionary *> *desk, const long long *roles, size_t n, NSString **bad) {
    NSMutableSet *used = [NSMutableSet set];
    for (NSArray *k in plan[@"keep"]) {
        long long r = [k[1] longLongValue];
        BOOL isRole = NO; for (size_t i = 0; i < n; i++) if (roles[i] == r) isRole = YES;
        if (!isRole) { *bad = [NSString stringWithFormat:@"role %lld not a window role", r]; return NO; }
        if ([used containsObject:@(r)]) { *bad = [NSString stringWithFormat:@"role %lld twice", r]; return NO; }
        [used addObject:@(r)];
    }
    for (NSNumber *r in plan[@"empty"]) {
        if ([used containsObject:r]) { *bad = [NSString stringWithFormat:@"role %@ kept and emptied", r]; return NO; }
        [used addObject:r];
    }
    if (used.count != n) { *bad = [NSString stringWithFormat:@"%lu roles covered of %zu", (unsigned long)used.count, n]; return NO; }
    BOOL primary = NO; for (NSArray *k in plan[@"keep"]) if ([k[1] longLongValue] == roles[0]) primary = YES;
    if (!primary) { *bad = @"no primary window"; return NO; }
    NSMutableSet *windowed = [NSMutableSet set], *full = [NSMutableSet set];
    long long newest = -1;
    for (NSDictionary *w in desk) {
        if ([w[@"p"] longLongValue] == 2) [full addObject:w[@"id"]];
        else { [windowed addObject:w[@"id"]]; newest = MAX(newest, [w[@"t"] longLongValue]); }
    }
    if (![KeptIds(plan) isEqualToSet:windowed]) { *bad = @"kept windows are not exactly the windowed ones"; return NO; }
    if (![[NSSet setWithArray:plan[@"away"]] isEqualToSet:full]) { *bad = @"away is not exactly the full-screen ones"; return NO; }
    long long frontT = -2; for (NSDictionary *w in desk) if ([w[@"id"] isEqualToString:plan[@"front"]]) frontT = [w[@"t"] longLongValue];
    if (frontT != newest) { *bad = [NSString stringWithFormat:@"front t %lld, newest %lld", frontT, newest]; return NO; }
    if ([plan[@"atHome"] boolValue] != (full.count == 0)) { *bad = @"atHome wrong"; return NO; }
    return YES;
}

static void Suite(const long long *roles, size_t n) {
    @autoreleasepool {
        printf("-- %zu window roles\n", n);
        NSString *why = nil;
        NSArray *desk = @[W(@"sceneID:com.apple.mobiletimer-default", roles[0], 10, 0), W(@"sceneID:com.apple.Preferences-default", roles[1], 12, 0),
                          W(@"sceneID:com.apple.Maps-default", roles[2], 11, 0)];
        // 1. Home from the desktop (application mode, its stage on screen): every window stays in its own role, the rest of the roles emptied, the
        //    newest in front, nothing leaves (the person is on the Home Screen already: its own Home press applies).
        NSDictionary *p = DMSMHomePlan(desk, roles, n, 0, 1, 3, YES, &why);
        CHECK(p != nil, "windows stay (%s)", why.UTF8String);
        CHECK(RoleOf(p, @"sceneID:com.apple.mobiletimer-default") == roles[0] && RoleOf(p, @"sceneID:com.apple.Preferences-default") == roles[1]
              && RoleOf(p, @"sceneID:com.apple.Maps-default") == roles[2], "each keeps its own role");
        CHECK([p[@"empty"] count] == n - 3, "the other %zu roles emptied (%lu)", n - 3, (unsigned long)[p[@"empty"] count]);
        CHECK([p[@"front"] isEqualToString:@"sceneID:com.apple.Preferences-default"], "the newest (Settings, t 12) in front");
        CHECK([p[@"atHome"] boolValue] && [p[@"away"] count] == 0, "nothing leaves, at Home");
        CHECK([why containsString:@"own roles"], "said: %s", why.UTF8String);
        //    requested environment 0 (none) is the same; the Home button's context asks for none.
        CHECK(DMSMHomePlan(desk, roles, n, 0, 0, 3, YES, &why) != nil, "requested environment 0 too");

        // 2. Everything that is not leaving the desktop for the Home Screen: left as SpringBoard built it.
        struct { int f; const char *name; } leave[] = {
            {DMSMHomeOurs, "our own"}, {DMSMHomeRealHome, "real Home"}, {DMSMHomeNotMain, "another display"}, {DMSMHomeBackground, "background"},
            {DMSMHomeLocked, "locked"}, {DMSMHomeRemoval, "removal"}, {DMSMHomeNotHome, "not the Home Screen"}, {DMSMHomeRolesSet, "roles set"},
        };
        for (size_t i = 0; i < sizeof leave / sizeof leave[0]; i++) {
            why = nil;
            CHECK(DMSMHomePlan(desk, roles, n, leave[i].f, 1, 3, YES, &why) == nil && why.length, "%s: left (%s)", leave[i].name, why.UTF8String);
            CHECK(DMSMHomePlan(desk, roles, n, leave[i].f | DMSMHomeSwitcherDesk, 1, 2, NO, &why) == nil, "%s from the switcher: left", leave[i].name);
        }
        CHECK(DMSMHomePlan(desk, roles, n, 0, 2, 3, YES, &why) == nil, "asks for the App Switcher: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(desk, roles, n, 0, 3, 3, YES, &why) == nil, "asks for an app: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(desk, roles, n, 0, 1, 1, NO, &why) == nil && [why containsString:@"already"], "from the Home Screen: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(desk, roles, n, 0, 1, 0, NO, &why) == nil, "start not known: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(desk, roles, n, 0, 1, 3, NO, &why) == nil, "a stage on screen that is not the desktop: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(@[], roles, n, 0, 1, 3, YES, &why) == nil, "empty desktop: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(desk, roles, 1, 0, 1, 3, YES, &why) == nil, "no roles: left");

        // 3. From the App Switcher: back to the desktop only when the switcher was opened from it.
        CHECK(DMSMHomePlan(desk, roles, n, 0, 1, 2, NO, &why) == nil && [why containsString:@"App Switcher"], "switcher not from the desktop: Home (%s)", why.UTF8String);
        p = DMSMHomePlan(desk, roles, n, DMSMHomeSwitcherDesk, 1, 2, NO, &why);
        CHECK(p && [p[@"keep"] count] == 3 && [p[@"atHome"] boolValue], "switcher opened from the desktop: back to its windows (%s)", why.UTF8String);

        // 4. A full-screen window in the primary role with windows behind it (Aerial's rule): it goes to the background, the others stay and close
        //    up in role order -- a stage always has its primary window; not "at Home" (the full-screen app was what showed).
        NSArray *withFull = @[W(@"full", roles[0], 20, 2), W(@"a", roles[1], 5, 0), W(@"b", roles[2], 7, 0)];
        p = DMSMHomePlan(withFull, roles, n, 0, 1, 3, YES, &why);
        CHECK(p != nil, "full screen + windows (%s)", why.UTF8String);
        CHECK([p[@"away"] isEqualToArray:@[@"full"]] && ![p[@"atHome"] boolValue], "the full-screen window leaves, not at Home");
        CHECK(RoleOf(p, @"a") == roles[0] && RoleOf(p, @"b") == roles[1] && RoleOf(p, @"full") == -1, "the rest close up: a %lld, b %lld", RoleOf(p, @"a"), RoleOf(p, @"b"));
        CHECK([p[@"front"] isEqualToString:@"b"], "the newest window left (b) in front");
        CHECK([p[@"empty"] count] == n - 2, "the roles left emptied");
        //    The full-screen window in a later role: the others keep the order of their roles.
        p = DMSMHomePlan(@[W(@"a", roles[0], 5, 0), W(@"full", roles[1], 20, 2), W(@"b", roles[2], 7, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK(p && RoleOf(p, @"a") == roles[0] && RoleOf(p, @"b") == roles[1], "full screen in the side role: a %lld, b %lld", RoleOf(p, @"a"), RoleOf(p, @"b"));
        //    Only a full-screen window: Home as Apple has it.
        CHECK(DMSMHomePlan(@[W(@"full", roles[0], 20, 2)], roles, n, 0, 1, 3, YES, &why) == nil && [why containsString:@"full-screen"], "only full screen: Home (%s)", why.UTF8String);
        //    Two full-screen windows and one window (never ours to make, but read whole): both leave.
        p = DMSMHomePlan(@[W(@"f1", roles[0], 3, 2), W(@"f2", roles[1], 4, 2), W(@"w", roles[2], 1, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK(p && [p[@"away"] count] == 2 && RoleOf(p, @"w") == roles[0], "two full-screen windows leave, the window takes the primary role");

        // 5. Two windows of one app (two scenes -- 1.3.6 logic test M-2: the engine told windows apart by app): both stay.
        p = DMSMHomePlan(@[W(@"sceneID:com.apple.freeform-default", roles[0], 1, 0), W(@"sceneID:com.apple.freeform-1A2B", roles[1], 2, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK(p && [p[@"keep"] count] == 2, "two windows of one app both stay");

        // 6. What can't be read whole: left.
        CHECK(DMSMHomePlan(@[W(@"x", roles[0], 1, 0), W(@"x", roles[1], 2, 0)], roles, n, 0, 1, 3, YES, &why) == nil, "a window listed twice: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(@[@{@"id": @"x", @"r": @(roles[0])}], roles, n, 0, 1, 3, YES, &why) == nil, "a window not read whole: left (%s)", why.UTF8String);
        CHECK(DMSMHomePlan(@[@{@"r": @(roles[0]), @"t": @1, @"p": @0}], roles, n, 0, 1, 3, YES, &why) == nil, "a window without an identifier: left");
        NSMutableArray *tooMany = [NSMutableArray array];
        for (size_t i = 0; i <= n; i++) [tooMany addObject:W([NSString stringWithFormat:@"w%zu", i], roles[i % n], (long long)i, 0)];
        CHECK(DMSMHomePlan(tooMany, roles, n, 0, 1, 3, YES, &why) == nil, "more windows than roles: left (%s)", why.UTF8String);

        // 7. Roles: own roles kept when they are window roles, once each, with the primary (a gap is fine); otherwise closed up.
        p = DMSMHomePlan(@[W(@"a", roles[0], 1, 0), W(@"c", roles[2], 2, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK(p && RoleOf(p, @"a") == roles[0] && RoleOf(p, @"c") == roles[2], "a gap in the roles is kept (no window moves)");
        p = DMSMHomePlan(@[W(@"b", roles[1], 1, 0), W(@"c", roles[2], 2, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK(p && RoleOf(p, @"b") == roles[0] && RoleOf(p, @"c") == roles[1], "no primary: closed up (%lld, %lld)", RoleOf(p, @"b"), RoleOf(p, @"c"));
        p = DMSMHomePlan(@[W(@"a", roles[0], 1, 0), W(@"odd", 3, 2, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK(p && RoleOf(p, @"odd") == roles[1], "a non-window role (3): closed up (%lld)", RoleOf(p, @"odd"));
        p = DMSMHomePlan(@[W(@"a", roles[0], 1, 0), W(@"b", roles[0], 2, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK(p && RoleOf(p, @"a") == roles[0] && RoleOf(p, @"b") == roles[1], "one role twice: closed up");
        //    Front: a tie goes to the lower role.
        p = DMSMHomePlan(@[W(@"a", roles[0], 5, 0), W(@"b", roles[1], 5, 0)], roles, n, 0, 1, 3, YES, &why);
        CHECK([p[@"front"] isEqualToString:@"a"], "a tie in time: the lower role in front");

        // 8. Random sweep.
        srand48(1677 + (long)n);
        int sweeps = 0;
        for (int iter = 0; iter < 20000; iter++) {
            size_t count = 1 + (size_t)(drand48() * n);
            NSMutableArray *rolesLeft = [NSMutableArray array]; for (size_t i = 0; i < n; i++) [rolesLeft addObject:@(roles[i])];
            NSMutableArray *d = [NSMutableArray array];
            BOOL anyWindowed = NO;
            for (size_t i = 0; i < count; i++) {
                long long r;
                if (drand48() < 0.9 && rolesLeft.count) { NSUInteger k = (NSUInteger)(drand48() * rolesLeft.count); r = [rolesLeft[k] longLongValue]; [rolesLeft removeObjectAtIndex:k]; }
                else r = (long long)(drand48() * 12);   // (a stray role now and then)
                long long pol = drand48() < 0.15 ? 2 : (drand48() < 0.5 ? 0 : 1);
                if (pol != 2) anyWindowed = YES;
                [d addObject:W([NSString stringWithFormat:@"w%zu", i], r, (long long)(drand48() * 50), pol)];
            }
            NSDictionary *pl = DMSMHomePlan(d, roles, n, drand48() < 0.5 ? 0 : DMSMHomeSwitcherDesk, drand48() < 0.5 ? 0 : 1, 3, YES, &why);
            if (!anyWindowed) { CHECK(pl == nil, "sweep %d: only full screen must be left", iter); continue; }
            NSString *bad = nil;
            if (!pl) { CHECK(NO, "sweep %d: no plan (%s)", iter, why.UTF8String); continue; }
            BOOL ok = Invariants(pl, d, roles, n, &bad);
            CHECK(ok, "sweep %d: %s", iter, bad.UTF8String);
            if (!ok) continue;
            // planned again (the result as the desktop, nothing full screen any more): the same roles
            NSMutableArray *again = [NSMutableArray array];
            for (NSArray *k in pl[@"keep"]) { long long t = 0; for (NSDictionary *w in d) if ([w[@"id"] isEqualToString:k[0]]) t = [w[@"t"] longLongValue]; [again addObject:W(k[0], [k[1] longLongValue], t, 0)]; }
            NSDictionary *pl2 = DMSMHomePlan(again, roles, n, 0, 1, 3, YES, &why);
            BOOL same = pl2 != nil;
            for (NSArray *k in pl[@"keep"]) if (RoleOf(pl2, k[0]) != [k[1] longLongValue]) same = NO;
            CHECK(same, "sweep %d: planned again, the roles change", iter);
            sweeps++;
        }
        printf("   sweep: %d plans checked\n", sweeps);
    }
}

// The App Switcher's bookkeeping (DMSMSwitcherNote), by where SpringBoard went: every result / start / window combination against a table written
// out by hand, then the sequences seen on the iPad 2 (1.3.8 logic test H-1).
static void SwitcherNote(void) {
    const long long envs[] = {0, 1, 2, 3, 4};
    for (int i = 0; i < 5; i++) for (int j = 0; j < 5; j++) for (int w = 0; w < 2; w++) {
        long long res = envs[i], prev = envs[j];
        int want;
        if (res == 2) want = prev == 2 ? 0 : ((prev == 3 && w) ? 1 : -1);
        else if (res == 0) want = 0;
        else want = -1;
        int got = DMSMSwitcherNote(res, prev, (BOOL)w);
        CHECK(got == want, "switcher note: went to %lld from %lld (window %d): %d, want %d", res, prev, w, got, want);
    }
    // sequences: 1 = remembered desk, applied as SMHome.h DMSMHomeNoteResult does
    struct { const char *name; long long steps[6][2]; int n; BOOL window; BOOL want; } seq[] = {
        {"gesture into the switcher, then its follow-ups (FollowupRotation: no environment asked, still the switcher)", {{2, 3}, {2, 2}, {2, 2}}, 3, YES, YES},
        {"switcher toggle from the desktop", {{2, 3}}, 1, YES, YES},
        {"switcher from the desktop, then a card (application mode)", {{2, 3}, {3, 2}}, 2, YES, NO},
        {"switcher from the desktop, back to the desktop by the Home button inside it", {{2, 3}, {2, 2}, {3, 2}}, 3, YES, NO},
        {"switcher from the Home Screen", {{2, 1}, {2, 2}}, 2, YES, NO},
        {"switcher from a lone full-screen app (no window)", {{2, 3}, {2, 2}}, 2, NO, NO},
        {"switcher from the desktop, a result not readable in between", {{2, 3}, {0, 2}, {2, 2}}, 3, YES, YES},
        {"switcher from the desktop, then the Home Screen (the Home rule read it first), then a new switcher from Home", {{2, 3}, {1, 2}, {2, 1}}, 3, YES, NO},
    };
    for (size_t k = 0; k < sizeof seq / sizeof seq[0]; k++) {
        BOOL desk = NO;
        for (int st = 0; st < seq[k].n; st++) {
            int note = DMSMSwitcherNote(seq[k].steps[st][0], seq[k].steps[st][1], seq[k].window);
            if (note > 0) desk = YES; else if (note < 0) desk = NO;
        }
        CHECK(desk == seq[k].want, "switcher sequence: %s -> desk %d, want %d", seq[k].name, desk, seq[k].want);
    }
}

// The desktop choice (DMSMStageIsDesktop): exhaustive over its inputs, and the cases of 1.3.8 logic test H-3.
// Edges the external tester's mutants found untested (1.3.8 RC1: E1, R1, P2): a negative requested environment, a single window role, a sizing policy
// above full screen's 2 (none exists today: such a window is kept as a window -- the safe side).
static void RuleEdges(void) {
    NSString *why = nil;
    const long long one[] = {1};
    const long long four[] = {1, 2, 5, 6};
    NSArray *desk = @[W(@"a", 1, 1, 0), W(@"b", 2, 2, 0)];
    CHECK(DMSMHomePlan(desk, four, 4, 0, -1, 3, YES, &why) == nil, "E1: requested environment -1 is left (%s)", why.UTF8String);
    CHECK(DMSMHomePlan(@[W(@"a", 1, 1, 0)], one, 1, 0, 1, 3, YES, &why) == nil && [why containsString:@"roles"], "R1: one window role only is left (%s)", why.UTF8String);
    NSDictionary *p = DMSMHomePlan(@[W(@"a", 1, 1, 0), W(@"odd", 2, 2, 3)], four, 4, 0, 1, 3, YES, &why);
    CHECK(p && [p[@"away"] count] == 0 && RoleOf(p, @"odd") == 2, "P2: sizing policy 3 stays a window");
}

static void StageIsDesktop(void) {
    for (int shown = 0; shown < 4; shown++) for (int w = 0; w < 2; w++) for (int on = 0; on < 2; on++) for (int asked = 0; asked < 2; asked++) {
        BOOL want = shown > 0 && (w || on || asked);
        CHECK(DMSMStageIsDesktop((NSUInteger)shown, (BOOL)w, (BOOL)on, (BOOL)asked) == want, "desktop choice: shown %d window %d on screen %d asked %d", shown, w, on, asked);
    }
    CHECK(!DMSMStageIsDesktop(1, NO, NO, NO), "H-3: a lone full-screen app sent Home is not the desktop (the next app opened, the restore)");
    CHECK(DMSMStageIsDesktop(1, NO, YES, NO), "a full-screen app on screen is joined over");
    CHECK(DMSMStageIsDesktop(1, NO, NO, YES), "a full-screen app asked for itself (its Dock icon, its card) is shown as it is");
    CHECK(DMSMStageIsDesktop(3, YES, NO, NO), "a desktop of windows not on screen (the Home Screen in front) is the desktop");
    CHECK(DMSMStageIsDesktop(2, YES, NO, NO), "windows with a full-screen one among them are a desktop");
    CHECK(!DMSMStageIsDesktop(0, YES, YES, YES), "no window that is not minimized: never the desktop");
}

int main(void) {
    const long long four[] = {1, 2, 5, 6};
    const long long seven[] = {1, 2, 5, 6, 7, 8, 9};
    Suite(four, 4);
    Suite(seven, 7);
    SwitcherNote();
    StageIsDesktop();
    RuleEdges();
    printf("test-smhomerule: %d checks, %d failed\n", passes + fails, fails);
    return fails ? 1 : 0;
}
