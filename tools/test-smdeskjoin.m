// Mac test of the Stage Manager engine's one-desktop rule for transitions SpringBoard builds itself (statusbar/SMDeskJoin.h, the code StatusBar.x
// runs in -[SBWorkspaceApplicationSceneTransitionContext finalize]): the App Switcher's card of a minimized window joins the desktop instead of
// showing alone, the desktop's own windows and Stage Manager's own arrangements (a window closed, minimized, added) pass untouched, the 4-window
// rule leaves the oldest out, and a random sweep: a rewritten plan always keeps the newest desktop windows, names every new window once, uses each
// window role at most once, never more than four windows, and planning the result again leaves it alone. Run by test-smdeskjoin.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/SMDeskJoin.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSDictionary *W(NSString *b, long long r, long long t) { return @{@"b": b, @"r": @(r), @"t": @(t)}; }
static NSDictionary *A(NSString *b, long long r) { return @{@"b": b, @"r": @(r)}; }
static NSArray *Bundles(NSArray<NSArray *> *plan, BOOL isNew) { NSMutableArray *o = [NSMutableArray array]; for (NSArray *p in plan) if ([p[2] boolValue] == isNew) [o addObject:p[0]]; return o; }
static long long RoleOf(NSArray<NSArray *> *plan, NSString *b) { for (NSArray *p in plan) if ([p[0] isEqualToString:b]) return [p[1] longLongValue]; return -1; }
static BOOL RolesValid(NSArray<NSArray *> *plan) {
    NSMutableSet *seen = [NSMutableSet set];
    for (NSArray *p in plan) {
        long long r = [p[1] longLongValue];
        if (!(r == 1 || r == 2 || r == 5 || r == 6) || [seen containsObject:@(r)]) return NO;
        [seen addObject:@(r)];
    }
    return YES;
}

int main(void) {
    @autoreleasepool {
        NSString *why = nil;
        NSArray *desk3 = @[W(@"com.apple.mobiletimer", 1, 10), W(@"com.apple.Preferences", 2, 12), W(@"com.apple.Maps", 5, 11)];

        // 1. The App Switcher's card of a minimized window (its own hidden stage, role 1): it joins the desktop, in a free role, and every desktop
        //    window stays in its role.
        NSArray *p = DMSMDeskJoinPlan(desk3, @[A(@"com.apple.Notes", 1)], 0, &why);
        CHECK(p != nil, "minimized window's card joins (%s)", why.UTF8String);
        CHECK([Bundles(p, YES) isEqualToArray:@[@"com.apple.Notes"]], "Notes is the new window");
        CHECK(Bundles(p, NO).count == 3, "three desktop windows kept: %lu", (unsigned long)Bundles(p, NO).count);
        CHECK(RoleOf(p, @"com.apple.mobiletimer") == 1 && RoleOf(p, @"com.apple.Preferences") == 2 && RoleOf(p, @"com.apple.Maps") == 5, "desktop windows keep their roles");
        CHECK(RoleOf(p, @"com.apple.Notes") == 6 && RolesValid(p), "Notes takes the free role 6 (%lld)", RoleOf(p, @"com.apple.Notes"));

        // 2. A full desktop (four windows): the oldest is left out for the new one, as with a fifth app.
        NSArray *desk4 = [desk3 arrayByAddingObject:W(@"com.apple.iBooks", 6, 9)];
        p = DMSMDeskJoinPlan(desk4, @[A(@"com.apple.Notes", 1)], 0, &why);
        CHECK(p.count == 4 && RolesValid(p), "full desktop: four windows (%lu)", (unsigned long)p.count);
        CHECK(RoleOf(p, @"com.apple.iBooks") == -1, "the oldest (Books, t 9) left out");
        CHECK(RoleOf(p, @"com.apple.Notes") == 6, "Notes takes Books' role 6 (%lld)", RoleOf(p, @"com.apple.Notes"));
        CHECK([why containsString:@"left out"], "said: %s", why.UTF8String);

        // 3. A stale stage of two windows (from before the engine) picked in the App Switcher: both join, two desktop windows kept (newest).
        p = DMSMDeskJoinPlan(desk3, @[A(@"com.apple.Notes", 1), A(@"com.apple.reminders", 2)], 0, &why);
        CHECK(p.count == 4 && RolesValid(p), "two new: four windows (%lu)", (unsigned long)p.count);
        CHECK(RoleOf(p, @"com.apple.Preferences") > 0 && RoleOf(p, @"com.apple.Maps") > 0 && RoleOf(p, @"com.apple.mobiletimer") == -1, "the two newest desktop windows kept (Settings t12, Maps t11)");

        // 4. Passes untouched: the desktop itself (its card, Cmd-Tab to one of its windows), a window closed or minimized (fewer of its own
        //    windows), Stage Manager adding a window (all desktop windows kept), and every flag.
        CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.mobiletimer", 1), A(@"com.apple.Preferences", 2), A(@"com.apple.Maps", 5)], 0, &why) && [why containsString:@"desktop's own"], "the desktop itself: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.mobiletimer", 1), A(@"com.apple.Preferences", 2)], 0, &why) && [why containsString:@"desktop's own"], "one window minimized away: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.mobiletimer", 1), A(@"com.apple.Preferences", 2), A(@"com.apple.Maps", 5), A(@"com.apple.Notes", 6)], 0, &why) && [why containsString:@"keeps every"], "a window added by Stage Manager: %s", why.UTF8String);
        int flags[] = {DMSMJoinOurs, DMSMJoinNotMain, DMSMJoinToHome, DMSMJoinToSwitcher, DMSMJoinRemoval, DMSMJoinFloatCentre, DMSMJoinNonApp, DMSMJoinOtherDesk};
        for (size_t i = 0; i < sizeof(flags) / sizeof(flags[0]); i++) CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.Notes", 1)], flags[i], &why), "flag %d leaves it (%s)", flags[i], why.UTF8String);
        //    A Mac Switcher desktop switch is our own request (flag), and a whole other stage of four can't keep anything of the desktop.
        CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"a", 1), A(@"b", 2), A(@"c", 5), A(@"d", 6)], 0, &why) && [why containsString:@"four"], "a stage of four new windows: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(@[], @[A(@"com.apple.Notes", 1)], 0, &why) && [why containsString:@"no desktop"], "no desktop: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk3, @[], 0, &why), "nothing asked");

        // 5. A desktop window in the centre role (4) or two windows claiming one role: kept, moved to free window roles.
        p = DMSMDeskJoinPlan(@[W(@"x", 1, 5), W(@"y", 4, 6)], @[A(@"z", 1)], 0, &why);
        CHECK(p.count == 3 && RolesValid(p) && RoleOf(p, @"x") == 1 && RoleOf(p, @"y") == 2 && RoleOf(p, @"z") == 5, "centre-role window re-roled: x %lld y %lld z %lld", RoleOf(p, @"x"), RoleOf(p, @"y"), RoleOf(p, @"z"));
        p = DMSMDeskJoinPlan(@[W(@"x", 2, 5), W(@"y", 2, 6)], @[A(@"z", 1)], 0, &why);
        CHECK(p.count == 3 && RolesValid(p), "a role claimed twice: roles stay unique");
        //    One app with two windows on the desktop (two scenes, one bundle): kept once (the engine knows windows by app).
        p = DMSMDeskJoinPlan(@[W(@"x", 1, 5), W(@"x", 2, 7), W(@"y", 5, 6)], @[A(@"z", 1)], 0, &why);
        CHECK(p.count == 3 && RolesValid(p) && RoleOf(p, @"x") == 2, "two windows of one app kept once (its newest, role 2): %lld", RoleOf(p, @"x"));

        // 6. Random sweep.
        srandom(42);
        NSArray *apps = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h"];
        int rewritten = 0;
        for (int n = 0; n < 20000; n++) {
            NSMutableArray *desk = [NSMutableArray array], *ask = [NSMutableArray array];
            NSMutableArray *pool = [apps mutableCopy];
            int nd = (int)(random() % 5), na = 1 + (int)(random() % 4);
            long long roles[] = {1, 2, 4, 5, 6};
            for (int i = 0; i < nd && pool.count; i++) { NSUInteger k = (NSUInteger)random() % pool.count; [desk addObject:W(pool[k], roles[random() % 5], random() % 100)]; [pool removeObjectAtIndex:k]; }
            NSMutableArray *askPool = [apps mutableCopy];
            for (int i = 0; i < na && askPool.count; i++) { NSUInteger k = (NSUInteger)random() % askPool.count; [ask addObject:A(askPool[k], kDMSMJoinRoles[i % 4])]; [askPool removeObjectAtIndex:k]; }
            NSArray *plan = DMSMDeskJoinPlan(desk, ask, 0, &why);
            // the rule rewrites exactly when it should (1.3.5 logic test L4: a rule that rewrote too little went unnoticed): a desktop, 1-3 new windows,
            // and at least one desktop window left out by SpringBoard's request
            {
                NSMutableSet *dB = [NSMutableSet set], *aB = [NSMutableSet set];
                for (NSDictionary *w in desk) [dB addObject:w[@"b"]];
                for (NSDictionary *a in ask) [aB addObject:a[@"b"]];
                NSMutableSet *newB = [aB mutableCopy]; [newB minusSet:dB];
                NSMutableSet *leftOut = [dB mutableCopy]; [leftOut minusSet:aB];
                BOOL applies = dB.count > 0 && newB.count >= 1 && newB.count <= 3 && leftOut.count > 0;
                CHECK((plan != nil) == applies, "sweep %d: rewritten exactly when the rule applies (plan %d, applies %d: %s)", n, plan != nil, applies, why.UTF8String);
            }
            if (!plan) continue;
            rewritten++;
            NSMutableSet *deskB = [NSMutableSet set]; for (NSDictionary *w in desk) [deskB addObject:w[@"b"]];
            NSMutableSet *fresh = [NSMutableSet set]; for (NSDictionary *a in ask) if (![deskB containsObject:a[@"b"]]) [fresh addObject:a[@"b"]];
            CHECK(plan.count <= 4 && RolesValid(plan), "sweep %d: at most four windows, roles unique (%lu)", n, (unsigned long)plan.count);
            CHECK([[NSSet setWithArray:Bundles(plan, YES)] isEqualToSet:fresh], "sweep %d: every new window once", n);
            NSArray *keptB = Bundles(plan, NO);
            CHECK(keptB.count == MIN(deskB.count, 4 - fresh.count), "sweep %d: as many desktop windows as fit (%lu)", n, (unsigned long)keptB.count);
            long long minKept = LLONG_MAX, maxDropped = LLONG_MIN;
            for (NSDictionary *w in desk) { long long t = [w[@"t"] longLongValue]; if ([keptB containsObject:w[@"b"]]) minKept = MIN(minKept, t); else maxDropped = MAX(maxDropped, t); }
            CHECK(maxDropped == LLONG_MIN || maxDropped <= minKept, "sweep %d: the newest are kept (dropped %lld, kept from %lld)", n, maxDropped, minKept);
            // planning the result again (now the desktop) asks nothing more: SpringBoard's re-ask of the same stage passes
            NSMutableArray *after = [NSMutableArray array], *again = [NSMutableArray array];
            for (NSArray *q in plan) { [after addObject:W(q[0], [q[1] longLongValue], [q[2] boolValue] ? 1000 : 1)]; [again addObject:A(q[0], [q[1] longLongValue])]; }
            CHECK(!DMSMDeskJoinPlan(after, again, 0, &why), "sweep %d: the joined desktop passes untouched", n);
        }
        CHECK(rewritten > 1000, "the sweep rewrote enough cases: %d", rewritten);
        printf("test-smdeskjoin: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
