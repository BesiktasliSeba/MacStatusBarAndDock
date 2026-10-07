// Mac test of the Stage Manager engine's one-desktop rule for transitions SpringBoard builds itself (statusbar/SMDeskJoin.h, the code StatusBar.x
// runs in -[SBWorkspaceApplicationSceneTransitionContext finalize]): the App Switcher's card of a minimized window joins the desktop instead of
// showing alone, the desktop's own windows and Stage Manager's own arrangements (a window closed, minimized, added) pass untouched, a full desktop
// leaves the oldest out, and a random sweep: a rewritten plan always keeps the newest desktop windows, names every new window once, uses each
// window role at most once, never more windows than the stage's window roles, and planning the result again leaves it alone. Run by
// test-smdeskjoin.sh -- twice: with the engine's four window roles (1, 2, 5, 6: no role table from SpringBoard) and with 16.7.7's seven
// (1, 2, 5-9, SMRoles.h, sm-nolimit). Entries without a window key ("w") are compared by app: the fallback, exactly as before M-2. SuiteWindows:
// entries with window keys (SMWindowKey.h, M-2) -- a second window of an app on the desktop is a window of its own: it joins instead of showing
// alone, two windows of one app both stay; one entry without a key turns the decision back to "by app"; a sweep over multi-window apps.
#import <Foundation/Foundation.h>
#include "../statusbar/SMDeskJoin.h"
static BOOL SB1677(long long r) { unsigned long long x8 = (unsigned long long)(r - 1); unsigned int w9 = 1u << ((unsigned int)r & 31); return ((w9 & 0xfffffc19u) == 0) && x8 < 10; }

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
        if (!DMSMIsWindowRole(r) || [seen containsObject:@(r)]) return NO;
        [seen addObject:@(r)];
    }
    return YES;
}

static void Suite(void) {
    @autoreleasepool {
        NSString *why = nil;
        const NSUInteger cap = DMSMWindowCap();
        printf("-- %zu window roles: %s\n", DMSMWindowCap(), DMSMRolesText().UTF8String);
        NSArray *desk3 = @[W(@"com.apple.mobiletimer", 1, 10), W(@"com.apple.Preferences", 2, 12), W(@"com.apple.Maps", 5, 11)];

        // 1. The App Switcher's card of a minimized window (its own hidden stage, role 1): it joins the desktop, in a free role, and every desktop
        //    window stays in its role.
        NSArray *p = DMSMDeskJoinPlan(desk3, @[A(@"com.apple.Notes", 1)], 0, &why);
        CHECK(p != nil, "minimized window's card joins (%s)", why.UTF8String);
        CHECK([Bundles(p, YES) isEqualToArray:@[@"com.apple.Notes"]], "Notes is the new window");
        CHECK(Bundles(p, NO).count == 3, "three desktop windows kept: %lu", (unsigned long)Bundles(p, NO).count);
        CHECK(RoleOf(p, @"com.apple.mobiletimer") == 1 && RoleOf(p, @"com.apple.Preferences") == 2 && RoleOf(p, @"com.apple.Maps") == 5, "desktop windows keep their roles");
        CHECK(RoleOf(p, @"com.apple.Notes") == 6 && RolesValid(p), "Notes takes the free role 6 (%lld)", RoleOf(p, @"com.apple.Notes"));

        // 2. A full desktop (every window role taken): the oldest is left out for the new one, as with an app opened on a full desktop. Books
        //    (t 9) is the oldest and holds the last role; the rest are newer.
        NSMutableArray *deskFull = [desk3 mutableCopy];
        for (size_t i = 3; i < cap - 1; i++) [deskFull addObject:W([NSString stringWithFormat:@"app%zu", i], gDMSMRoles[i], 20 + (long long)i)];
        [deskFull addObject:W(@"com.apple.iBooks", gDMSMRoles[cap - 1], 9)];
        p = DMSMDeskJoinPlan(deskFull, @[A(@"com.apple.Notes", 1)], 0, &why);
        CHECK(p.count == cap && RolesValid(p), "full desktop: %lu windows (%lu)", (unsigned long)cap, (unsigned long)p.count);
        CHECK(RoleOf(p, @"com.apple.iBooks") == -1, "the oldest (Books, t 9) left out");
        CHECK(RoleOf(p, @"com.apple.Notes") == gDMSMRoles[cap - 1], "Notes takes Books' role %lld (%lld)", gDMSMRoles[cap - 1], RoleOf(p, @"com.apple.Notes"));
        CHECK([why containsString:@"left out"], "said: %s", why.UTF8String);
        CHECK([DMSMDeskJoinLeftOut(deskFull, p) isEqualToArray:@[@"com.apple.iBooks"]], "left out (the Mac Switcher's full-desktop decision): Books only (%s)", [[DMSMDeskJoinLeftOut(deskFull, p) componentsJoinedByString:@","] UTF8String]);
        //    One window short of full: nothing left out (with seven roles this is the old "fifth window" case: it simply joins).
        NSArray *deskAlmost = [deskFull subarrayWithRange:NSMakeRange(0, cap - 1)];
        p = DMSMDeskJoinPlan(deskAlmost, @[A(@"com.apple.Notes", 1)], 0, &why);
        CHECK(p.count == cap && RolesValid(p) && ![why containsString:@"left out"], "one short of full: all %lu kept, Notes joins (%s)", (unsigned long)(cap - 1), why.UTF8String);
        CHECK(DMSMDeskJoinLeftOut(deskAlmost, p).count == 0, "one short of full: nothing left out");

        // 3. A stale stage of two windows (from before the engine) picked in the App Switcher: both join; with four roles two desktop windows are
        //    kept (the newest), with seven all three.
        p = DMSMDeskJoinPlan(desk3, @[A(@"com.apple.Notes", 1), A(@"com.apple.reminders", 2)], 0, &why);
        CHECK(p.count == MIN(cap, (NSUInteger)5) && RolesValid(p), "two new: %lu windows (%lu)", (unsigned long)MIN(cap, (NSUInteger)5), (unsigned long)p.count);
        CHECK(RoleOf(p, @"com.apple.Preferences") > 0 && RoleOf(p, @"com.apple.Maps") > 0 && (cap > 4 ? RoleOf(p, @"com.apple.mobiletimer") > 0 : RoleOf(p, @"com.apple.mobiletimer") == -1), "the newest desktop windows kept (Settings t12, Maps t11%s)", cap > 4 ? ", Clock t10" : "");

        // 4. Passes untouched: the desktop itself (its card, Cmd-Tab to one of its windows), a window closed or minimized (fewer of its own
        //    windows), Stage Manager adding a window (all desktop windows kept), and every flag.
        CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.mobiletimer", 1), A(@"com.apple.Preferences", 2), A(@"com.apple.Maps", 5)], 0, &why) && [why containsString:@"desktop's own"], "the desktop itself: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.mobiletimer", 1), A(@"com.apple.Preferences", 2)], 0, &why) && [why containsString:@"desktop's own"], "one window minimized away: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.mobiletimer", 1), A(@"com.apple.Preferences", 2), A(@"com.apple.Maps", 5), A(@"com.apple.Notes", 6)], 0, &why) && [why containsString:@"keeps every"], "a window added by Stage Manager: %s", why.UTF8String);
        int flags[] = {DMSMJoinOurs, DMSMJoinNotMain, DMSMJoinToHome, DMSMJoinToSwitcher, DMSMJoinRemoval, DMSMJoinFloatCentre, DMSMJoinNonApp, DMSMJoinOtherDesk};
        for (size_t i = 0; i < sizeof(flags) / sizeof(flags[0]); i++) CHECK(!DMSMDeskJoinPlan(desk3, @[A(@"com.apple.Notes", 1)], flags[i], &why), "flag %d leaves it (%s)", flags[i], why.UTF8String);
        //    A Mac Switcher desktop switch is our own request (flag), and a whole other full stage can't keep anything of the desktop.
        NSMutableArray *other = [NSMutableArray array];
        for (size_t i = 0; i < cap; i++) [other addObject:A([NSString stringWithFormat:@"o%zu", i], gDMSMRoles[i])];
        CHECK(!DMSMDeskJoinPlan(desk3, other, 0, &why) && [why containsString:@"full stage"], "a stage of %lu new windows: %s", (unsigned long)cap, why.UTF8String);
        if (cap > 4) {   // (four new windows on a desktop of seven roles: they join, the newest desktop windows kept with them)
            p = DMSMDeskJoinPlan(desk3, @[A(@"a", 1), A(@"b", 2), A(@"c", 5), A(@"d", 6)], 0, &why);
            CHECK(p.count == MIN(cap, (NSUInteger)7) && RolesValid(p), "four new windows with %lu roles: they join (%lu, %s)", (unsigned long)cap, (unsigned long)p.count, why.UTF8String);
        }
        CHECK(!DMSMDeskJoinPlan(@[], @[A(@"com.apple.Notes", 1)], 0, &why) && [why containsString:@"no desktop"], "no desktop: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk3, @[], 0, &why), "nothing asked");

        // 5. A desktop window in the centre role (4) or two windows claiming one role: kept, moved to free window roles.
        p = DMSMDeskJoinPlan(@[W(@"x", 1, 5), W(@"y", 4, 6)], @[A(@"z", 1)], 0, &why);
        CHECK(p.count == 3 && RolesValid(p) && RoleOf(p, @"x") == 1 && RoleOf(p, @"y") == 2 && RoleOf(p, @"z") == 5, "centre-role window re-roled: x %lld y %lld z %lld", RoleOf(p, @"x"), RoleOf(p, @"y"), RoleOf(p, @"z"));
        p = DMSMDeskJoinPlan(@[W(@"x", 2, 5), W(@"y", 2, 6)], @[A(@"z", 1)], 0, &why);
        CHECK(p.count == 3 && RolesValid(p), "a role claimed twice: roles stay unique");
        //    One app with two windows on the desktop (two scenes, one bundle) known by app only (no window keys -- the fallback): kept once.
        p = DMSMDeskJoinPlan(@[W(@"x", 1, 5), W(@"x", 2, 7), W(@"y", 5, 6)], @[A(@"z", 1)], 0, &why);
        CHECK(p.count == 3 && RolesValid(p) && RoleOf(p, @"x") == 2, "by app: two windows of one app kept once (its newest, role 2): %lld", RoleOf(p, @"x"));

        // 6. Random sweep.
        srandom(42);
        NSArray *apps = @[@"a", @"b", @"c", @"d", @"e", @"f", @"g", @"h", @"i", @"j", @"k", @"l"];
        int rewritten = 0;
        for (int n = 0; n < 20000; n++) {
            NSMutableArray *desk = [NSMutableArray array], *ask = [NSMutableArray array];
            NSMutableArray *pool = [apps mutableCopy];
            int nd = (int)(random() % (cap + 1)), na = 1 + (int)(random() % cap);
            long long roles[] = {1, 2, 4, 5, 6, 7, 8, 9};
            int nroles = cap > 4 ? 8 : 5;
            for (int i = 0; i < nd && pool.count; i++) { NSUInteger k = (NSUInteger)random() % pool.count; [desk addObject:W(pool[k], roles[random() % nroles], random() % 100)]; [pool removeObjectAtIndex:k]; }
            NSMutableArray *askPool = [apps mutableCopy];
            for (int i = 0; i < na && askPool.count; i++) { NSUInteger k = (NSUInteger)random() % askPool.count; [ask addObject:A(askPool[k], gDMSMRoles[i % cap])]; [askPool removeObjectAtIndex:k]; }
            NSArray *plan = DMSMDeskJoinPlan(desk, ask, 0, &why);
            // the rule rewrites exactly when it should (1.3.5 logic test L4: a rule that rewrote too little went unnoticed): a desktop, 1-3 new windows,
            // and at least one desktop window left out by SpringBoard's request
            {
                NSMutableSet *dB = [NSMutableSet set], *aB = [NSMutableSet set];
                for (NSDictionary *w in desk) [dB addObject:w[@"b"]];
                for (NSDictionary *a in ask) [aB addObject:a[@"b"]];
                NSMutableSet *newB = [aB mutableCopy]; [newB minusSet:dB];
                NSMutableSet *leftOut = [dB mutableCopy]; [leftOut minusSet:aB];
                BOOL applies = dB.count > 0 && newB.count >= 1 && newB.count <= cap - 1 && leftOut.count > 0;
                CHECK((plan != nil) == applies, "sweep %d: rewritten exactly when the rule applies (plan %d, applies %d: %s)", n, plan != nil, applies, why.UTF8String);
            }
            if (!plan) continue;
            rewritten++;
            NSMutableSet *deskB = [NSMutableSet set]; for (NSDictionary *w in desk) [deskB addObject:w[@"b"]];
            NSMutableSet *fresh = [NSMutableSet set]; for (NSDictionary *a in ask) if (![deskB containsObject:a[@"b"]]) [fresh addObject:a[@"b"]];
            CHECK(plan.count <= cap && RolesValid(plan), "sweep %d: at most %lu windows, roles unique (%lu)", n, (unsigned long)cap, (unsigned long)plan.count);
            CHECK([[NSSet setWithArray:Bundles(plan, YES)] isEqualToSet:fresh], "sweep %d: every new window once", n);
            NSArray *keptB = Bundles(plan, NO);
            CHECK(keptB.count == MIN(deskB.count, cap - fresh.count), "sweep %d: as many desktop windows as fit (%lu)", n, (unsigned long)keptB.count);
            // what a full desktop gives up (the Mac Switcher decides about it first, MacSwitcherSM.h DMMSWSMAtCap): exactly the desktop windows the
            // plan does not keep, and none at all while the desktop has room for the new windows
            NSArray *lo = DMSMDeskJoinLeftOut(desk, plan);
            NSMutableSet *loWant = [deskB mutableCopy]; [loWant minusSet:[NSSet setWithArray:keptB]];
            CHECK([[NSSet setWithArray:lo] isEqualToSet:loWant] && lo.count == loWant.count, "sweep %d: left out = the desktop windows not kept", n);
            CHECK(lo.count == (deskB.count + fresh.count > cap ? deskB.count + fresh.count - cap : 0), "sweep %d: left out only past the cap (%lu of %lu + %lu, cap %lu)", n, (unsigned long)lo.count, (unsigned long)deskB.count, (unsigned long)fresh.count, (unsigned long)cap);
            long long minKept = LLONG_MAX, maxDropped = LLONG_MIN;
            for (NSDictionary *w in desk) { long long t = [w[@"t"] longLongValue]; if ([keptB containsObject:w[@"b"]]) minKept = MIN(minKept, t); else maxDropped = MAX(maxDropped, t); }
            CHECK(maxDropped == LLONG_MIN || maxDropped <= minKept, "sweep %d: the newest are kept (dropped %lld, kept from %lld)", n, maxDropped, minKept);
            // planning the result again (now the desktop) asks nothing more: SpringBoard's re-ask of the same stage passes
            NSMutableArray *after = [NSMutableArray array], *again = [NSMutableArray array];
            for (NSArray *q in plan) { [after addObject:W(q[0], [q[1] longLongValue], [q[2] boolValue] ? 1000 : 1)]; [again addObject:A(q[0], [q[1] longLongValue])]; }
            CHECK(!DMSMDeskJoinPlan(after, again, 0, &why), "sweep %d: the joined desktop passes untouched", n);
        }
        CHECK(rewritten > 1000, "the sweep rewrote enough cases: %d", rewritten);
    }
}

// ---- M-2: windows with their own keys ----------------------------------------------------------------------------------------------------------
static NSDictionary *WK(NSString *b, NSString *u, long long r, long long t) { return @{@"w": DMSMKeyMake(b, u), @"b": b, @"r": @(r), @"t": @(t)}; }
static NSDictionary *AK(NSString *b, NSString *u, long long r) { return @{@"w": DMSMKeyMake(b, u), @"b": b, @"r": @(r)}; }
static NSArray *KeysOf(NSArray<NSArray *> *plan, BOOL isNew) { NSMutableArray *o = [NSMutableArray array]; for (NSArray *p in plan) if ([p[2] boolValue] == isNew) [o addObject:p[0]]; return o; }
static void SuiteWindows(void) {
    @autoreleasepool {
        NSString *why = nil;
        const NSUInteger cap = DMSMWindowCap();
        printf("-- windows with keys, %zu window roles\n", DMSMWindowCap());
        NSString *ff = @"com.apple.freeform", *clk = @"com.apple.mobiletimer", *set = @"com.apple.Preferences";
        NSString *A1 = @"sceneID:com.apple.freeform-A", *B1 = @"sceneID:com.apple.freeform-B";
        NSString *kA = DMSMKeyMake(ff, A1), *kB = DMSMKeyMake(ff, B1), *kC = DMSMKeyMake(clk, @"sceneID:com.apple.mobiletimer-default"), *kS = DMSMKeyMake(set, @"sceneID:com.apple.Preferences-default");
        NSArray *desk = @[WK(clk, @"sceneID:com.apple.mobiletimer-default", 1, 10), WK(ff, A1, 2, 12), WK(set, @"sceneID:com.apple.Preferences-default", 5, 11)];

        // 1. A second Freeform window, shown by SpringBoard as a stage of its own (its "+" / an app asking for a new window): it joins the desktop.
        NSArray *p = DMSMDeskJoinPlan(desk, @[AK(ff, B1, 1)], 0, &why);
        CHECK(p != nil, "a second window of a desktop app joins (%s)", why.UTF8String);
        CHECK([KeysOf(p, YES) isEqualToArray:@[kB]], "Freeform B is the new window");
        CHECK(KeysOf(p, NO).count == 3 && RoleOf(p, kC) == 1 && RoleOf(p, kA) == 2 && RoleOf(p, kS) == 5, "the desktop's three windows keep their roles (Freeform A among them)");
        CHECK(RoleOf(p, kB) == 6 && RolesValid(p), "Freeform B takes the free role 6 (%lld)", RoleOf(p, kB));
        CHECK(![why containsString:@"by app"], "decided by window: %s", why.UTF8String);
        //    ... what the same transition did by app (the M-2 bug, still the fallback where windows can't be told apart): left alone.
        CHECK(!DMSMDeskJoinPlan(@[W(clk, 1, 10), W(ff, 2, 12), W(set, 5, 11)], @[A(ff, 1)], 0, &why) && [why containsString:@"desktop's own"], "by app: 'only the desktop's own windows' (%s)", why.UTF8String);
        //    One entry without its own key turns the whole decision back to "by app" (a window by scene and the same window by app would be two).
        NSMutableArray *mixed = [desk mutableCopy]; mixed[2] = W(set, 5, 11);
        CHECK(!DMSMDeskJoinPlan(mixed, @[AK(ff, B1, 1)], 0, &why) && [why containsString:@"desktop's own"], "one window without a key: by app (%s)", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk, @[@{@"w": ff, @"b": ff, @"r": @1}], 0, &why) && [why containsString:@"desktop's own"], "an asked app key: by app (%s)", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk, @[@{@"w": DMSMKeyMake(clk, B1), @"b": ff, @"r": @1}], 0, &why), "a key of another app than its bundle: by app (%s)", why.UTF8String);

        // 2. Two windows of one app on the desktop: both stay, each in its role, when another stage joins.
        NSArray *desk2 = @[WK(ff, A1, 1, 20), WK(ff, B1, 2, 21), WK(clk, @"sceneID:com.apple.mobiletimer-default", 5, 19)];
        p = DMSMDeskJoinPlan(desk2, @[AK(@"com.apple.weather", @"sceneID:com.apple.weather-default", 1)], 0, &why);
        CHECK(p.count == 4 && RolesValid(p) && RoleOf(p, kA) == 1 && RoleOf(p, kB) == 2 && RoleOf(p, kC) == 5, "both Freeform windows kept in their roles (A %lld, B %lld)", RoleOf(p, kA), RoleOf(p, kB));

        // 2b. A FULL desktop holding two windows of one app (1.4, the Mac Switcher's full-desktop decision reads DMSMDeskJoinLeftOut): the left-out
        //     list names the oldest WINDOW by its key -- not the app, whose newer window stays; a plan made by app keeps every window of that app.
        {
            NSMutableArray *full = [NSMutableArray arrayWithObjects:WK(ff, A1, gDMSMRoles[0], 5), WK(ff, B1, gDMSMRoles[1], 30), nil];   // (A the oldest)
            for (size_t i = 2; i < cap; i++) [full addObject:WK([NSString stringWithFormat:@"app%zu", i], [NSString stringWithFormat:@"sceneID:app%zu-default", i], gDMSMRoles[i], 20 + (long long)i)];
            NSArray *pf = DMSMDeskJoinPlan(full, @[AK(@"com.apple.weather", @"sceneID:com.apple.weather-default", 1)], 0, &why);
            NSArray *lo = DMSMDeskJoinLeftOut(full, pf);
            CHECK(pf.count == cap && RolesValid(pf) && RoleOf(pf, kA) == -1 && RoleOf(pf, kB) > 0, "full desktop with two Freeform windows: the older one (A) left out, B kept (%s)", why.UTF8String);
            CHECK([lo isEqualToArray:@[kA]], "left out: Freeform A by its window key, not the app (%s)", [[lo componentsJoinedByString:@","] UTF8String]);
            NSMutableArray *byApp = [NSMutableArray array]; for (NSDictionary *w in full) [byApp addObject:W(w[@"b"], [w[@"r"] longLongValue], [w[@"t"] longLongValue])];
            NSArray *pa = DMSMDeskJoinPlan(byApp, @[A(@"com.apple.weather", 1)], 0, &why);
            CHECK(pa && DMSMDeskJoinLeftOut(byApp, pa).count == 0 && RoleOf(pa, ff) > 0, "by app (no keys): the app counts once -- nothing of Freeform left out (%s)", why.UTF8String);
            CHECK(DMSMDeskJoinLeftOut(full, @[]).count == full.count && [DMSMDeskJoinLeftOut(full, @[]).firstObject isEqualToString:kA], "an empty plan: every window, by key, in the desktop's order");
            //  Desktop windows WITH keys, asked by app (an entity without a scene identifier): the plan compares apps, so it names Freeform once and
            //  keeps both its windows -- the left-out list must not name them (1.4 logic test: a mutant dropping the app check survived here).
            NSArray *pm = DMSMDeskJoinPlan(full, @[@{@"w": @"com.apple.weather", @"b": @"com.apple.weather", @"r": @1}], 0, &why);
            CHECK(pm && [why containsString:@"by app"], "keys on the desktop, an app key asked: the plan compares apps (%s)", why.UTF8String);
            CHECK(pm && DMSMDeskJoinLeftOut(full, pm).count == 0, "... and leaves no window out: Freeform counted once, both its windows kept (%s)", [[DMSMDeskJoinLeftOut(full, pm) componentsJoinedByString:@","] UTF8String]);
        }

        // 3. Passes untouched: the desktop itself (both windows of the app), one of its two windows minimized away, Stage Manager adding B to it.
        CHECK(!DMSMDeskJoinPlan(desk2, @[AK(ff, A1, 1), AK(ff, B1, 2), AK(clk, @"sceneID:com.apple.mobiletimer-default", 5)], 0, &why) && [why containsString:@"desktop's own"], "the desktop itself: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk2, @[AK(ff, A1, 1), AK(clk, @"sceneID:com.apple.mobiletimer-default", 2)], 0, &why) && [why containsString:@"desktop's own"], "Freeform B minimized away: %s", why.UTF8String);
        CHECK(!DMSMDeskJoinPlan(desk, @[AK(clk, @"sceneID:com.apple.mobiletimer-default", 1), AK(ff, A1, 2), AK(set, @"sceneID:com.apple.Preferences-default", 5), AK(ff, B1, 6)], 0, &why) && [why containsString:@"keeps every"], "B added by Stage Manager itself: %s", why.UTF8String);
        //    The App Switcher's card of Freeform A while only B is on the desktop (A minimized): A joins, B stays.
        NSArray *deskB = @[WK(ff, B1, 1, 30), WK(clk, @"sceneID:com.apple.mobiletimer-default", 2, 29)];
        p = DMSMDeskJoinPlan(deskB, @[AK(ff, A1, 1)], 0, &why);
        CHECK(p.count == 3 && RoleOf(p, kB) == 1 && RoleOf(p, kC) == 2 && RoleOf(p, kA) == 5 && [KeysOf(p, YES) isEqualToArray:@[kA]], "A's card: A joins next to B (A %lld)", RoleOf(p, kA));

        // 4. A full desktop of one app's windows: the oldest window is left out for the new one, never a window counted twice.
        NSMutableArray *full = [NSMutableArray array];
        for (size_t i = 0; i < cap; i++) [full addObject:WK(ff, [NSString stringWithFormat:@"sceneID:com.apple.freeform-%zu", i], gDMSMRoles[i], 100 + (long long)i)];
        p = DMSMDeskJoinPlan(full, @[AK(ff, @"sceneID:com.apple.freeform-new", 1)], 0, &why);
        CHECK(p.count == cap && RolesValid(p) && RoleOf(p, DMSMKeyMake(ff, @"sceneID:com.apple.freeform-0")) == -1 && RoleOf(p, DMSMKeyMake(ff, @"sceneID:com.apple.freeform-new")) == gDMSMRoles[0], "a full desktop of Freeform windows: the oldest out, the new one in its role (%s)", why.UTF8String);

        // 5. Random sweep over apps with several windows: rewritten exactly when the rule applies (by window), every window at most once, each
        //    new window once, the newest kept, roles unique, at most `cap`; planning the result again leaves it alone.
        srandom(4242);
        NSArray *apps = @[ff, clk, set, @"com.apple.Maps", @"com.apple.weather"];
        int rewritten = 0, twoOfOne = 0;
        for (int n = 0; n < 20000; n++) {
            NSMutableArray *pool = [NSMutableArray array];   // (windows: an app and one of three scenes of it)
            for (NSString *a in apps) for (int s = 0; s < 3; s++) [pool addObject:@[a, [NSString stringWithFormat:@"sceneID:%@-%d", a, s]]];
            NSMutableArray *dk = [NSMutableArray array], *ask = [NSMutableArray array];
            NSMutableArray *dpool = [pool mutableCopy], *apool = [pool mutableCopy];
            int nd = (int)(random() % (cap + 1)), na = 1 + (int)(random() % cap);
            long long roles[] = {1, 2, 4, 5, 6, 7, 8, 9};
            int nroles = cap > 4 ? 8 : 5;
            for (int i = 0; i < nd && dpool.count; i++) { NSUInteger k = (NSUInteger)random() % dpool.count; NSArray *w = dpool[k]; [dk addObject:WK(w[0], w[1], roles[random() % nroles], random() % 100)]; [dpool removeObjectAtIndex:k]; }
            for (int i = 0; i < na && apool.count; i++) { NSUInteger k = (NSUInteger)random() % apool.count; NSArray *w = apool[k]; [ask addObject:AK(w[0], w[1], gDMSMRoles[i % cap])]; [apool removeObjectAtIndex:k]; }
            NSMutableSet *dK = [NSMutableSet set], *aK = [NSMutableSet set], *dApps = [NSMutableSet set];
            BOOL two = NO;
            for (NSDictionary *w in dk) { [dK addObject:w[@"w"]]; if ([dApps containsObject:w[@"b"]]) two = YES; [dApps addObject:w[@"b"]]; }
            for (NSDictionary *a in ask) [aK addObject:a[@"w"]];
            NSMutableSet *newK = [aK mutableCopy]; [newK minusSet:dK];
            NSMutableSet *leftOut = [dK mutableCopy]; [leftOut minusSet:aK];
            BOOL applies = dK.count > 0 && newK.count >= 1 && newK.count <= cap - 1 && leftOut.count > 0;
            NSArray *plan = DMSMDeskJoinPlan(dk, ask, 0, &why);
            CHECK((plan != nil) == applies, "windows sweep %d: rewritten exactly when the rule applies (plan %d, applies %d: %s)", n, plan != nil, applies, why.UTF8String);
            if (!plan) continue;
            rewritten++; if (two) twoOfOne++;
            CHECK(plan.count <= cap && RolesValid(plan), "windows sweep %d: at most %lu windows, roles unique", n, (unsigned long)cap);
            NSMutableSet *seen = [NSMutableSet set];
            for (NSArray *q in plan) { CHECK(![seen containsObject:q[0]] && !DMSMKeyIsApp(q[0]), "windows sweep %d: each window once, by its key", n); [seen addObject:q[0]]; }
            CHECK([[NSSet setWithArray:KeysOf(plan, YES)] isEqualToSet:newK], "windows sweep %d: every new window once", n);
            NSArray *kept = KeysOf(plan, NO);
            CHECK(kept.count == MIN(dK.count, cap - newK.count), "windows sweep %d: as many desktop windows as fit (%lu)", n, (unsigned long)kept.count);
            long long minKept = LLONG_MAX, maxDropped = LLONG_MIN;
            for (NSDictionary *w in dk) { long long t = [w[@"t"] longLongValue]; if ([kept containsObject:w[@"w"]]) minKept = MIN(minKept, t); else maxDropped = MAX(maxDropped, t); }
            CHECK(maxDropped == LLONG_MIN || maxDropped <= minKept, "windows sweep %d: the newest are kept", n);
            NSMutableArray *after = [NSMutableArray array], *again = [NSMutableArray array];
            for (NSArray *q in plan) { [after addObject:@{@"w": q[0], @"b": DMSMKeyBundle(q[0]), @"r": q[1], @"t": @([q[2] boolValue] ? 1000 : 1)}]; [again addObject:@{@"w": q[0], @"b": DMSMKeyBundle(q[0]), @"r": q[1]}]; }
            CHECK(!DMSMDeskJoinPlan(after, again, 0, &why), "windows sweep %d: the joined desktop passes untouched", n);
        }
        CHECK(rewritten > 1000 && twoOfOne > 200, "the windows sweep rewrote enough cases: %d (%d with two windows of one app on the desktop)", rewritten, twoOfOne);
    }
}

int main(void) {
    @autoreleasepool {
        Suite();   // (the engine's four: no role table from SpringBoard)
        SuiteWindows();
        CHECK(DMSMRolesSetFrom(SB1677, 1, 2, 5, 25, 10, NULL) && DMSMWindowCap() == 7, "16.7.7's seven window roles set");
        Suite();   // (16.7.7: seven windows per desktop)
        SuiteWindows();
        printf("test-smdeskjoin: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
