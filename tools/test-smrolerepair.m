// Mac test of SMRoleRepair.h (1.3.6): Minimize keeps every other window and no window is in two roles. The contexts are built here the way
// SpringBoard builds them (16.7.7 disassembled, confirmed on the iPad 2): Stage Manager's Minimize writes, for each valid role r (1..9 without 3
// and 4): below the window taken out "as it was" (+[SBPreviousWorkspaceEntity entity], no role); its own role nothing; above it the window of r
// moved into the role before; the last target never written. SpringBoard reads it (Resolve below): a role left unset keeps its previous window;
// a previous entity naming a role gives that role's previous window; "as it was" keeps its window only in the primary and side roles -- in an
// additional side (5+) it gives nothing (the window leaves the desktop: seen on the iPad 2 with four windows, Tips of role 5 went with the
// minimized Weather of role 6). Run by test-smrolerepair.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/SMRoleRepair.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static const long long kRoles[] = {1, 2, 5, 6, 7, 8, 9};   // (16.7.7's window roles)
static NSString *Win(int i) { return [NSString stringWithFormat:@"sceneID:app%c-default", 'A' + i]; }
static NSMutableDictionary *Was(int n) {   // (the previous layout state: n windows in the first n window roles -- A in 1, B in 2, C in 5, ...)
    NSMutableDictionary *w = [NSMutableDictionary dictionary];
    for (int i = 0; i < n && i < 7; i++) w[@(kRoles[i])] = Win(i);
    return w;
}
static NSMutableDictionary *Slot(long long r, int kind, NSDictionary *was) {
    NSMutableDictionary *s = [NSMutableDictionary dictionaryWithDictionary:@{@"r": @(r), @"k": @(kind)}];
    if (was[@(r)]) s[@"was"] = was[@(r)];
    return s;
}
static NSArray *AppleMinimize(long long mine, NSDictionary *was) {
    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *ctx = [NSMutableDictionary dictionary];
    for (int i = 0; i < 7; i++) ctx[@(kRoles[i])] = Slot(kRoles[i], DMSMSlotUnset, was);
    long long target = mine;
    for (long long r = 1; r <= 9; r++) {
        if (r == 3 || r == 4) continue;
        if (mine > r) { ctx[@(r)][@"k"] = @(DMSMSlotPrev); ctx[@(r)][@"to"] = @0; continue; }   // ("as it was": +entity, no role)
        if (mine == r) continue;
        ctx[@(target)][@"k"] = @(DMSMSlotPrev); ctx[@(target)][@"to"] = @(r);
        target = r;
    }
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < 7; i++) [out addObject:ctx[@(kRoles[i])]];
    return out;
}
// SpringBoard's reading of the context, with the repair applied (keep: written as Prev(own role); empty: SpringBoard's empty entity).
static NSDictionary *Resolve(NSArray *slots, NSDictionary *fix) {
    NSArray *keep = fix[@"keep"] ?: @[], *emptied = fix[@"empty"] ?: @[];
    NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
    for (NSDictionary *s in slots) byRole[s[@"r"]] = s;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSDictionary *s in slots) {
        long long r = [s[@"r"] longLongValue];
        if ([emptied containsObject:@(r)]) continue;
        NSString *w = nil;
        int k = [s[@"k"] intValue];
        if ([keep containsObject:@(r)]) w = s[@"was"];
        else if (k == DMSMSlotUnset) w = s[@"was"];
        else if (k == DMSMSlotPrev) { long long to = [s[@"to"] longLongValue]; if (to > 0) w = byRole[@(to)][@"was"]; else if (r < 5) w = s[@"was"]; }
        else if (k == DMSMSlotApp) w = s[@"id"];
        if (w) out[@(r)] = w;
    }
    return out;
}
static BOOL Distinct(NSDictionary *resolved) { return [NSSet setWithArray:resolved.allValues].count == resolved.count; }
static NSString *J(NSArray *a) { return [a componentsJoinedByString:@","]; }
static NSSet *Windows(int n) { NSMutableSet *s = [NSMutableSet set]; for (int i = 0; i < n; i++) [s addObject:Win(i)]; return s; }

int main(void) {
    @autoreleasepool {
        NSString *why = nil;
        // 1. Every desktop size 1-7, Minimize of every window: Apple's own result (the reading without the repair) is played first -- with 7 windows
        //    it holds a window twice for every Minimize but the one in role 9 (the abort), and every Minimize of a window above role 5 loses the
        //    windows of roles 5 .. below it; with the repair the result is always exactly the other n-1 windows, each once.
        for (int n = 1; n <= 7; n++)
            for (int i = 0; i < n; i++) {
                NSDictionary *was = Was(n);
                NSArray *ctx = AppleMinimize(kRoles[i], was);
                NSDictionary *apple = Resolve(ctx, @{});
                NSMutableSet *want = [Windows(n) mutableCopy]; [want removeObject:Win(i)];
                BOOL dup = !Distinct(apple), lost = ![[NSSet setWithArray:apple.allValues] isEqualToSet:want] && Distinct(apple);
                BOOL expectDup = n == 7 && kRoles[i] != 9;
                BOOL expectLost = !expectDup && (kRoles[i] >= 6 || (n == 7 && kRoles[i] == 9));
                CHECK(dup == expectDup, "%d windows, minimize role %lld: Apple's result %s a window twice -- %s", n, kRoles[i], dup ? "holds" : "does not hold", apple.description.UTF8String);
                CHECK(lost == expectLost, "%d windows, minimize role %lld: Apple's result %s windows (%s)", n, kRoles[i], lost ? "loses or keeps wrong" : "is whole", apple.description.UTF8String);
                NSDictionary *fix = DMSMRoleRepairPlan(ctx, 5, kRoles[i], Win(i), &why);
                NSDictionary *after = Resolve(ctx, fix);
                CHECK(Distinct(after) && [[NSSet setWithArray:after.allValues] isEqualToSet:want], "%d windows, minimize role %lld: the other %d windows once each (got %s; keep [%s] empty [%s]; %s)",
                      n, kRoles[i], n - 1, after.description.UTF8String, J(fix[@"keep"]).UTF8String, J(fix[@"empty"]).UTF8String, why.UTF8String);
                // the roles the repair touches: R1 = the additional sides below the minimized one; R2/R3 = role 9 on a full desktop
                NSMutableArray *wantKeep = [NSMutableArray array];
                for (int j = 2; j < i; j++) [wantKeep addObject:@(kRoles[j])];
                CHECK([fix[@"keep"] isEqualToArray:wantKeep], "%d windows, minimize role %lld: keep [%s] (want [%s])", n, kRoles[i], J(fix[@"keep"]).UTF8String, J(wantKeep).UTF8String);
                NSArray *wantEmpty = n == 7 ? @[@9] : @[];
                CHECK([fix[@"empty"] isEqualToArray:wantEmpty], "%d windows, minimize role %lld: empty [%s] (want [%s])", n, kRoles[i], J(fix[@"empty"]).UTF8String, J(wantEmpty).UTF8String);
                // the moved windows keep their order: each window above the minimized one one role down
                for (int j = i + 1; j < n; j++) CHECK([after[@(kRoles[j - 1])] isEqualToString:Win(j)], "%d windows, minimize role %lld: %s now in role %lld", n, kRoles[i], Win(j).UTF8String, kRoles[j - 1]);
            }
        // 2. Without our note of the minimize (another path, our note expired): R1 and R2 decide alone -- whole except the role-9 window, which
        //    then simply stays (nothing names it twice): Apple's no-op, never a crash.
        {
            NSDictionary *was = Was(7);
            NSArray *ctx = AppleMinimize(9, was);
            NSDictionary *fix = DMSMRoleRepairPlan(ctx, 5, 0, nil, &why);
            NSDictionary *after = Resolve(ctx, fix);
            CHECK(after.count == 7 && Distinct(after) && [fix[@"empty"] count] == 0, "minimize role 9 without the note: all seven stay, no window twice (keep [%s])", J(fix[@"keep"]).UTF8String);
            NSDictionary *f2 = DMSMRoleRepairPlan(ctx, 5, 9, @"sceneID:other-default", NULL);
            CHECK([f2[@"empty"] count] == 0, "a note naming another window: nothing emptied");
            NSDictionary *f3 = DMSMRoleRepairPlan(AppleMinimize(6, was), 5, 0, nil, &why);
            CHECK([J(f3[@"empty"]) isEqualToString:@"9"] && [J(f3[@"keep"]) isEqualToString:@"5"], "minimize role 6 without the note: keep [5], empty [9] (got [%s] [%s])", J(f3[@"keep"]).UTF8String, J(f3[@"empty"]).UTF8String);
        }
        // 3. A plain activation (nothing set), our join's plan (every window named, the new one in the left-out window's role), the Home Screen
        //    (roles emptied), the App Switcher's pick (additional sides emptied): left alone.
        {
            NSDictionary *was = Was(7);
            NSMutableArray *ctx = [NSMutableArray array];
            for (int i = 0; i < 7; i++) [ctx addObject:Slot(kRoles[i], DMSMSlotUnset, was)];
            NSDictionary *f = DMSMRoleRepairPlan(ctx, 5, 0, nil, &why);
            CHECK([f[@"keep"] count] == 0 && [f[@"empty"] count] == 0 && why == nil, "plain activation: nothing");
            NSMutableArray *join = [NSMutableArray array];
            for (int i = 0; i < 7; i++) { NSMutableDictionary *s = Slot(kRoles[i], DMSMSlotApp, was); s[@"id"] = i == 6 ? @"sceneID:appNew-default" : Win(i); [join addObject:s]; }
            f = DMSMRoleRepairPlan(join, 5, 0, nil, &why);
            CHECK([f[@"keep"] count] == 0 && [f[@"empty"] count] == 0 && why == nil, "join plan: nothing");
            NSMutableArray *home = [NSMutableArray array];
            for (int i = 0; i < 7; i++) [home addObject:Slot(kRoles[i], DMSMSlotEmpty, was)];
            f = DMSMRoleRepairPlan(home, 5, 0, nil, &why);
            CHECK([f[@"keep"] count] == 0 && [f[@"empty"] count] == 0, "all roles emptied: nothing");
            NSMutableArray *pick = [NSMutableArray array];
            for (int i = 0; i < 7; i++) [pick addObject:Slot(kRoles[i], i == 0 ? DMSMSlotApp : DMSMSlotEmpty, was)];
            pick[0][@"id"] = @"sceneID:appPicked-default";
            f = DMSMRoleRepairPlan(pick, 5, 0, nil, &why);
            CHECK([f[@"keep"] count] == 0 && [f[@"empty"] count] == 0, "the App Switcher's pick: nothing");
        }
        // 4. "as it was" in an additional side with no window there: nothing to keep (SpringBoard's empty answer is right).
        {
            NSDictionary *was = Was(3);
            NSMutableArray *ctx = [NSMutableArray array];
            for (int i = 0; i < 7; i++) { NSMutableDictionary *s = Slot(kRoles[i], DMSMSlotPrev, was); s[@"to"] = @0; [ctx addObject:s]; }
            NSDictionary *f = DMSMRoleRepairPlan(ctx, 5, 0, nil, &why);
            CHECK([J(f[@"keep"]) isEqualToString:@"5"] && [f[@"empty"] count] == 0, "every role 'as it was', 3 windows: keep [5] only (got [%s])", J(f[@"keep"]).UTF8String);
        }
        // 5. A window named twice by the context itself is SpringBoard's or the writer's business: reported, not touched; a duplicate whose kept
        //    role is primary or side: reported, never emptied ("Primary workspace entity may not be nil").
        {
            NSDictionary *was = Was(3);
            NSMutableArray *ctx = [NSMutableArray array];
            for (int i = 0; i < 7; i++) [ctx addObject:Slot(kRoles[i], DMSMSlotEmpty, was)];
            ctx[2][@"k"] = @(DMSMSlotApp); ctx[2][@"id"] = Win(1);
            ctx[3][@"k"] = @(DMSMSlotApp); ctx[3][@"id"] = Win(1);
            NSDictionary *f = DMSMRoleRepairPlan(ctx, 5, 0, nil, &why);
            CHECK([f[@"empty"] count] == 0 && [why containsString:@"by the context itself"], "a window named twice: reported only (%s)", why.UTF8String);
            NSMutableArray *ctx2 = [NSMutableArray array];
            for (int i = 0; i < 7; i++) [ctx2 addObject:Slot(kRoles[i], DMSMSlotUnset, was)];
            ctx2[2][@"k"] = @(DMSMSlotPrev); ctx2[2][@"to"] = @2;   // (role 5 names B of role 2; role 2 unset keeps it too)
            f = DMSMRoleRepairPlan(ctx2, 5, 0, nil, &why);
            CHECK([f[@"empty"] count] == 0 && [why containsString:@"role 2 is not an additional side"], "kept in the side role: reported only (%s)", why.UTF8String);
            NSMutableArray *ctx3 = [NSMutableArray array];   // ("as it was" in the side role + a move of the same window into 5: named twice)
            for (int i = 0; i < 7; i++) [ctx3 addObject:Slot(kRoles[i], DMSMSlotEmpty, was)];
            ctx3[1][@"k"] = @(DMSMSlotPrev); ctx3[1][@"to"] = @0;
            ctx3[2][@"k"] = @(DMSMSlotPrev); ctx3[2][@"to"] = @2;
            f = DMSMRoleRepairPlan(ctx3, 5, 0, nil, &why);
            CHECK([f[@"empty"] count] == 0 && [why containsString:Win(1)] && [why containsString:@"by the context itself"], "'as it was' (side) + a move of the same window: reported only (%s)", why.UTF8String);
        }
        // 6. The window shelf's swap (-[SBSwitcherShelfViewController _performSwitcherTransitionRequest:]: the picked window into the shelf's
        //    role, "as it was" into every other valid role -- 1.3.6 logic test M-1). Stock: every additional side resolves to empty (all those
        //    windows leave). R1 keeps them -- except a window the context moves into the shelf's role: kept in its old role too, it would be in
        //    two roles (the abort).
        {
            NSDictionary *was = Was(5);   // (A 1, B 2, C 5, D 6, E 7)
            NSMutableArray *shelf = [NSMutableArray array];
            for (int i = 0; i < 7; i++) { NSMutableDictionary *sl = Slot(kRoles[i], DMSMSlotPrev, was); sl[@"to"] = @0; [shelf addObject:sl]; }
            shelf[2][@"k"] = @(DMSMSlotApp); shelf[2][@"id"] = Win(3);   // (the shelf of role 5 picks D -- already on the stage in role 6)
            NSDictionary *f = DMSMRoleRepairPlan(shelf, 5, 0, nil, &why);
            NSDictionary *after = Resolve(shelf, f);
            CHECK(Distinct(after), "shelf picks a window already on the stage: no window twice (got %s; keep [%s] empty [%s]; %s)", after.description.UTF8String, J(f[@"keep"]).UTF8String, J(f[@"empty"]).UTF8String, why.UTF8String);
            CHECK([J(f[@"keep"]) isEqualToString:@"7"] && [after[@5] isEqualToString:Win(3)] && !after[@6] && [after[@7] isEqualToString:Win(4)], "shelf: D in role 5 only, E kept in 7, role 6 left (keep [%s])", J(f[@"keep"]).UTF8String);
            CHECK([why containsString:@"moves to role 5: not kept in role 6"], "shelf: the note says why role 6 is not kept (%s)", why.UTF8String);
            NSMutableArray *moved = [NSMutableArray array];   // (a window moved by a previous entity naming its role, its own role "as it was")
            for (int i = 0; i < 7; i++) { NSMutableDictionary *sl = Slot(kRoles[i], DMSMSlotPrev, was); sl[@"to"] = @0; [moved addObject:sl]; }
            moved[2][@"to"] = @6;   // (role 5 <- the window of role 6; role 6 "as it was")
            NSDictionary *fm = DMSMRoleRepairPlan(moved, 5, 0, nil, &why);
            NSDictionary *am = Resolve(moved, fm);
            CHECK(Distinct(am) && [am[@5] isEqualToString:Win(3)] && !am[@6] && [J(fm[@"keep"]) isEqualToString:@"7"], "a previous entity moving role 6's window to 5: not kept in 6 too (got %s; keep [%s])", am.description.UTF8String, J(fm[@"keep"]).UTF8String);
            shelf[2][@"id"] = @"sceneID:appC-window2";   // (the shelf picks another window of C's app, not on the stage)
            f = DMSMRoleRepairPlan(shelf, 5, 0, nil, &why);
            after = Resolve(shelf, f);
            CHECK(Distinct(after) && [J(f[@"keep"]) isEqualToString:@"6,7"] && after.count == 5, "shelf picks a new window: D and E kept, five windows once each (keep [%s])", J(f[@"keep"]).UTF8String);
        }
        // 7. A stale Minimize note (Apple's context never came) on a context that writes no window role -- a plain or a background activation:
        //    nothing emptied (logic test L-1); the note never empties the primary or side role (logic test L-5).
        {
            NSDictionary *was = Was(5);
            NSMutableArray *plain = [NSMutableArray array];
            for (int i = 0; i < 7; i++) [plain addObject:Slot(kRoles[i], DMSMSlotUnset, was)];
            NSDictionary *f = DMSMRoleRepairPlan(plain, 5, 7, Win(4), &why);
            CHECK([f[@"keep"] count] == 0 && [f[@"empty"] count] == 0, "plain activation with a stale note for role 7: nothing (keep [%s] empty [%s])", J(f[@"keep"]).UTF8String, J(f[@"empty"]).UTF8String);
            NSMutableArray *one = [NSMutableArray array];   // (a context that writes roles, the noted window kept in the primary role)
            for (int i = 0; i < 7; i++) [one addObject:Slot(kRoles[i], i == 0 ? DMSMSlotUnset : DMSMSlotEmpty, was)];
            f = DMSMRoleRepairPlan(one, 5, 1, Win(0), &why);
            CHECK([f[@"empty"] count] == 0 && [why containsString:@"not an additional side"], "a note for role 1: role 1 never emptied (empty [%s]; %s)", J(f[@"empty"]).UTF8String, why.UTF8String);
            f = DMSMRoleRepairPlan(one, 5, 2, Win(1), &why);
            CHECK([f[@"empty"] count] == 0, "a note for role 2 that the context empties itself: nothing more");
        }
        // 8. Mutation guards: the move is never emptied; two duplicates sorted; keep and empty never overlap.
        {
            NSMutableArray *two = [NSMutableArray array];
            NSDictionary *w2 = Was(7);
            for (int i = 0; i < 7; i++) [two addObject:Slot(kRoles[i], DMSMSlotUnset, w2)];
            two[0][@"k"] = @(DMSMSlotPrev); two[0][@"to"] = @9;
            two[1][@"k"] = @(DMSMSlotPrev); two[1][@"to"] = @8;
            NSDictionary *f = DMSMRoleRepairPlan(two, 5, 0, nil, &why);
            CHECK([J(f[@"empty"]) isEqualToString:@"8,9"], "two duplicates: roles 8 and 9 emptied, sorted (got [%s])", J(f[@"empty"]).UTF8String);
            NSDictionary *f2 = DMSMRoleRepairPlan(AppleMinimize(1, w2), 5, 1, Win(0), NULL);
            CHECK(![f2[@"empty"] containsObject:@8] && [f2[@"empty"] containsObject:@9], "the role that names the window (8) is never emptied");
            NSMutableSet *both = [NSMutableSet setWithArray:f2[@"keep"]]; [both intersectSet:[NSSet setWithArray:f2[@"empty"]]];
            CHECK(both.count == 0, "keep and empty never overlap");
        }
        printf("test-smrolerepair: %d passed, %d failed\n", passes, fails);
        return fails ? 1 : 0;
    }
}
