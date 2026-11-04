// Mac test of Fit to Window forgetting the windows that closed with the Stage Manager engine (1.8.0, engine parity: statusbar/SMFitPlan.h
// DMSMFitClosedKeys, DMSMFitLeftAfterClose, DMSMFitMemoryWithout -- StatusBar.x DMSMFitForgetClosed runs this very code). Run by test-smfitclosed.sh,
// which also checks the sites in StatusBar.x.
//  1. which windows closed: in no stage any more. A minimized window (a hidden stage of its own), one on another desktop, one in full screen are
//     there; windows told apart by app; an app asked about before its launch (pending) is not closed until it is no longer pending.
//  2. the windows left close up, each keeping its place (one fills; statusbar/FitPlan.h MSBDFitPlanKeepingPlaces, the rule of every engine --
//     test-fitorder.sh); their order (newest first) only parts two windows that had one tile.
//  3. the arrangements remembered per desktop lose every desktop that held a window that closed.
//  4. the stories: the desktop's last tiled window closes and the app's next window -- the same key -- opens at Window Size's place, not filling;
//     minimized and opened again it keeps its tile; a window closed out of sight closes the others up; No Fit survives a minimize; the memory of a
//     desktop does not hand a closed window's tile to its app's next window.
//  5. a sweep.
#import <Foundation/Foundation.h>
#include "../statusbar/SMFitPlan.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
// The windows left's tiles (FitPlan.h, as StatusBar.x DMSMFitForgetClosed lays them out): one fills the space, the others keep their places.
static NSDictionary<NSString *, NSString *> *AfterLeave(NSArray<NSString *> *left, NSDictionary *slots) { return MSBDFitPlanKeepingPlaces(left, slots); }
// The engine's forget step (StatusBar.x DMSMFitForgetClosed) on an arrangement: the closed windows out, the windows left closed up; nil when none.
static NSDictionary *Forget(NSDictionary *slots, NSSet *present, NSSet *pending, NSDictionary *times, NSSet **closedOut) {
    NSSet *closed = DMSMFitClosedKeys(slots, present, pending);
    if (closedOut) *closedOut = closed;
    BOOL tiled = NO;
    for (NSString *k in slots) if ([closed containsObject:k]) tiled = YES;
    if (!tiled) return slots;
    NSArray *left = DMSMFitLeftAfterClose(slots, closed, times);
    return left.count ? AfterLeave(left, slots) : nil;
}
// The Fit tick's one-window rule (StatusBar.x DMSMFitTick): a desktop's only window fills the space only when its arrangement says so.
static BOOL OneFills(NSDictionary *slots, NSString *one) { return one && slots.count == 1 && [slots[one] isEqualToString:@"fill"]; }
static NSSet *S(NSArray *a) { return [NSSet setWithArray:a]; }

int main(void) {
    @autoreleasepool {
        NSString *clock = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default", *tips = @"com.apple.tips|sceneID:com.apple.tips-default";
        NSString *maps = @"com.apple.Maps|sceneID:com.apple.Maps-default", *prefs = @"com.apple.Preferences|sceneID:com.apple.Preferences-default";
        NSString *notesA = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-6A1B", *notesB = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-9C2D";

        // 1. which windows closed
        CHECK(DMSMFitClosedKeys(@[clock, tips], S(@[clock, tips, prefs]), nil).count == 0, "every window in a stage: none closed");
        CHECK([DMSMFitClosedKeys(@[clock, tips], S(@[tips, prefs]), nil) isEqualToSet:S(@[clock])], "Clock in no stage any more: closed");
        CHECK([DMSMFitClosedKeys(@[clock], [NSSet set], nil) isEqualToSet:S(@[clock])], "no stage at all (the last window closed, nothing else open): closed");
        CHECK(DMSMFitClosedKeys(@[prefs], S(@[prefs, clock]), nil).count == 0, "a minimized window (its own hidden stage) is there: kept");
        CHECK(DMSMFitClosedKeys(@[clock], S(@[@"com.apple.mobiletimer"]), nil).count == 0, "windows told apart by app: the app's key in a stage covers its window");
        CHECK(DMSMFitClosedKeys(@[@"com.apple.mobiletimer"], S(@[clock]), nil).count == 0, "an app key (asked about before its launch) with the app's window there: kept");
        CHECK([DMSMFitClosedKeys(@[@"com.apple.mobiletimer"], S(@[tips]), nil) isEqualToSet:S(@[@"com.apple.mobiletimer"])], "an app key, no window of the app anywhere, not pending: closed");
        CHECK(DMSMFitClosedKeys(@[@"com.apple.mobiletimer"], S(@[tips]), S(@[@"com.apple.mobiletimer"])).count == 0, "an app key still pending (its window is still to come): kept");
        CHECK(DMSMFitClosedKeys(@[clock], [NSSet set], S(@[@"com.apple.mobiletimer"])).count == 0, "a window of an app pending again: kept while pending");
        CHECK([DMSMFitClosedKeys(@[notesA, notesB], S(@[notesB]), nil) isEqualToSet:S(@[notesA])], "two windows of one app: only the one that closed (the other window does not cover it)");
        CHECK(DMSMFitClosedKeys(@[@"", (NSString *)[NSNull null]], [NSSet set], nil).count == 0, "nothing to read: nothing closed");
        CHECK([DMSMFitClosedKeys(@{clock: @"fill"}, [NSSet set], nil) isEqualToSet:S(@[clock])], "an arrangement's keys (a dictionary) read the same way");

        // 2. the windows left, newest first
        NSDictionary *times = @{clock: @30, tips: @20, maps: @10};
        NSArray *left = DMSMFitLeftAfterClose(@{clock: @"left", tips: @"topright", maps: @"bottomright"}, S(@[tips]), times);
        CHECK([left isEqualToArray:(@[clock, maps])], "left after Tips closed: Clock (newest), Maps (%s)", left.description.UTF8String);
        left = DMSMFitLeftAfterClose(@{clock: @"left", tips: @"topright", maps: @"bottomright"}, S(@[clock]), times);
        CHECK([left isEqualToArray:(@[tips, maps])], "left after Clock closed: Tips, Maps");
        CHECK([DMSMFitLeftAfterClose(@{clock: @"fill"}, S(@[clock]), times) count] == 0, "the only window closed: none left");
        left = DMSMFitLeftAfterClose(@{clock: @"a", tips: @"b", @"com.apple.x": @"c", @"com.apple.w": @"d"}, [NSSet set], @{tips: @5, clock: @9});
        CHECK([left isEqualToArray:(@[clock, tips, @"com.apple.w", @"com.apple.x"])], "no time read: after the others, by key (%s)", left.description.UTF8String);
        CHECK([AfterLeave(DMSMFitLeftAfterClose(@{clock: @"left", tips: @"right"}, S(@[tips]), times), @{clock: @"left", tips: @"right"}) isEqualToDictionary:(@{clock: @"fill"})], "one left: it fills the space");
        NSDictionary *three = @{clock: @"left", tips: @"topright", maps: @"bottomright"};
        CHECK([AfterLeave(DMSMFitLeftAfterClose(three, S(@[clock]), times), three) isEqualToDictionary:(@{tips: @"left", maps: @"right"})], "two left of the right side: the halves, the top one on the left");
        CHECK([AfterLeave(DMSMFitLeftAfterClose(three, S(@[tips]), @{maps: @50, clock: @1}), three) isEqualToDictionary:(@{clock: @"left", maps: @"right"})], "Tips closed, Maps used last: Clock keeps the left half (the last use took it before 1.8.0)");

        // 3. the memory per desktop
        NSDictionary *memory = @{DMSMFitDeskKey(@[clock, tips]): @{clock: @"left", tips: @"right"}, DMSMFitDeskKey(@[maps, tips]): @{maps: @"left", tips: @"right"},
                                 DMSMFitDeskKey(@[@"w1", @"w2", @"w3", @"w4", @"w5"]): @{@"w1": @"topleft", @"w2": @"topright", @"w3": @"bottomleft", @"w4": @"bottomright"}};
        NSDictionary *m2 = DMSMFitMemoryWithout(memory, S(@[clock]));
        CHECK(m2.count == 2 && !m2[DMSMFitDeskKey(@[clock, tips])] && m2[DMSMFitDeskKey(@[maps, tips])], "Clock closed: its desktop goes, the others stay");
        m2 = DMSMFitMemoryWithout(memory, S(@[tips]));
        CHECK(m2.count == 1, "Tips closed: both desktops it was in go");
        m2 = DMSMFitMemoryWithout(memory, S(@[@"w5"]));
        CHECK(m2.count == 2 && !m2[DMSMFitDeskKey(@[@"w1", @"w2", @"w3", @"w4", @"w5"])], "a window past four tiles (in the desktop's set, no tile) closed: that desktop goes too");
        CHECK(DMSMFitMemoryWithout(memory, S(@[prefs])) == memory && DMSMFitMemoryWithout(memory, [NSSet set]) == memory && DMSMFitMemoryWithout(nil, S(@[clock])) == nil, "nothing of it closed: the same memory");

        // 4. the stories (the iPad 2's: KT's Settings minimized in its own hidden stage the whole time)
        {   // 4a. the desktop's last tiled window closes; the app's next window (its default scene: the same key) opens at Window Size's place
            NSDictionary *slots = @{clock: @"left", tips: @"right"};
            NSSet *closed = nil;
            slots = Forget(slots, S(@[clock, prefs]), nil, @{clock: @40, prefs: @1}, &closed);   // (Tips closed: Clock is the one left)
            CHECK([closed isEqualToSet:S(@[tips])] && [slots isEqualToDictionary:(@{clock: @"fill"})] && OneFills(slots, clock), "two tiled, Tips closed: Clock fills the space");
            slots = Forget(slots, S(@[prefs]), nil, @{prefs: @1}, &closed);   // (Clock closed too: the Home Screen, only Settings' hidden stage left)
            CHECK([closed isEqualToSet:S(@[clock])] && slots == nil, "then Clock closed: its fill tile forgotten (%s)", slots.description.UTF8String);
            CHECK(!OneFills(slots, clock), "Clock opened again (the same key): it does not fill -- it stays at Window Size's place");
            CHECK(OneFills(@{clock: @"fill"}, clock), "(before: the fill tile kept, its next window filled the desktop)");
            CHECK(!OneFills(Forget(@{clock: @"fill"}, S(@[prefs]), nil, @{}, NULL), clock), "the same when Clock was asked about first where it opens (DMSMJoinDesktop: not in a stage yet)");
        }
        {   // 4b. minimized, then opened again: its tile kept
            NSDictionary *slots = @{clock: @"fill"};
            NSSet *closed = nil;
            NSDictionary *after = Forget(slots, S(@[clock, prefs]), nil, @{clock: @40}, &closed);   // (Clock minimized: its own hidden stage)
            CHECK(closed.count == 0 && after == slots && OneFills(after, clock), "Clock minimized and opened again: its fill tile kept, it fills again");
            NSDictionary *two = @{clock: @"left", tips: @"right"};
            CHECK(Forget(two, S(@[clock, tips, prefs]), nil, @{}, &closed) == two && !closed.count, "two tiled, one minimized: both keep their tiles");
        }
        {   // 4c. a window closed out of sight (minimized, then quit) while two others are on screen: they close up to the halves, each keeping its side
            NSDictionary *three = @{clock: @"left", tips: @"topright", maps: @"bottomright"};
            NSDictionary *after = Forget(three, S(@[clock, tips, prefs]), nil, @{clock: @9, tips: @12}, NULL);
            CHECK([after isEqualToDictionary:(@{clock: @"left", tips: @"right"})], "three tiled, Maps closed out of sight: Clock keeps the left half, Tips grows down (%s; Tips, used last, took the left half before 1.8.0)", after.description.UTF8String);
            after = Forget(@{clock: @"left", tips: @"right"}, S(@[clock, prefs]), nil, @{clock: @9}, NULL);
            CHECK([after isEqualToDictionary:(@{clock: @"fill"})], "two tiled, the minimized one quit: the one left fills");
        }
        {   // 4d. No Fit: kept while minimized (its hidden stage), forgotten once closed
            CHECK(DMSMFitClosedKeys(S(@[maps]), S(@[clock, tips, maps]), nil).count == 0, "a No Fit window minimized: still No Fit");
            CHECK([DMSMFitClosedKeys(S(@[maps]), S(@[clock, tips]), nil) isEqualToSet:S(@[maps])], "a No Fit window closed: forgotten");
        }
        {   // 4e. the memory of a desktop never hands a closed window's tile to its app's next window
            NSDictionary *mem = @{DMSMFitDeskKey(@[tips, clock]): @{tips: @"left", clock: @"right"}};   // (Tips and Clock, Tips the newer then)
            mem = DMSMFitMemoryWithout(mem, S(@[tips]));   // (Tips closed)
            NSArray *desk = @[tips, clock];   // (Tips' next window, the newest, joins Clock -- not by an icon tap: Fit's look decides)
            CHECK(DMSMFitSlotsFor(@{clock: @"fill"}, mem, desk).count == 1, "no arrangement remembered for the closed window's desktop");
            int how = -1;
            NSDictionary *plan = DMSMFitPlanDecide(DMSMFitSlotsFor(@{clock: @"fill"}, mem, desk), desk, @[@"left", @"right"], &how);
            CHECK(how == DMSMFitDefault && [plan isEqualToDictionary:(@{tips: @"left", clock: @"right"})], "Tips' new window: the first tile, Clock the other half, as on the other engines");
            NSDictionary *kept = @{DMSMFitDeskKey(@[clock, tips]): @{clock: @"left", tips: @"right"}};   // (Clock the newer back then)
            NSDictionary *olds = DMSMFitSlotsFor(@{clock: @"fill"}, kept, desk);
            CHECK([olds isEqualToDictionary:(@{clock: @"left", tips: @"right"})], "(before: the closed window's desktop came back from the memory, Tips' new window took the closed one's right half)");
        }
        {   // 4f. Fit's question before a launch: the app key waits for its window, then is that window's
            NSDictionary *asked = @{@"com.apple.Maps": @"topleft", clock: @"bottomleft", tips: @"right"};
            CHECK(Forget(asked, S(@[clock, tips]), S(@[@"com.apple.Maps"]), @{}, NULL) == asked, "asked about before its launch, its window still to come: nothing forgotten");
            CHECK(Forget(asked, S(@[clock, tips, maps]), nil, @{}, NULL) == asked, "its window there (the app's key covers it): nothing forgotten");
            CHECK([Forget(asked, S(@[clock, tips]), nil, @{clock: @2, tips: @1}, NULL) isEqualToDictionary:(@{clock: @"left", tips: @"right"})], "its launch never came (no longer pending): the two left close up");
        }

        // 5. sweep: what closed is exactly what no stage names (by key or app) and is not pending; the windows left are the rest, newest first (the
        //    order that parts two windows of one tile); the memory keeps no desktop of a closed window
        srandom(11);
        NSArray *apps = @[@"a.one", @"b.two", @"c.three", @"d.four"];
        for (int n = 0; n < 20000; n++) {
            NSMutableArray<NSString *> *pool = [NSMutableArray array];
            for (NSString *a in apps) { [pool addObject:a]; for (int u = 0; u < 3; u++) [pool addObject:[NSString stringWithFormat:@"%@|sceneID:%@-%d", a, a, u]]; }
            NSMutableDictionary *slots = [NSMutableDictionary dictionary];
            NSMutableSet *present = [NSMutableSet set], *pending = [NSMutableSet set];
            NSMutableDictionary *tm = [NSMutableDictionary dictionary];
            NSArray *names = @[@"topleft", @"topright", @"bottomleft", @"bottomright"];
            int ns = 1 + (int)(random() % 4);
            for (int i = 0; i < ns; i++) slots[pool[random() % pool.count]] = names[i];
            int np = (int)(random() % 6);
            for (int i = 0; i < np; i++) { NSString *k = pool[random() % pool.count]; [present addObject:k]; if (random() % 2) tm[k] = @(random() % 50); }
            if (random() % 4 == 0) [pending addObject:apps[random() % apps.count]];
            NSSet *closed = DMSMFitClosedKeys(slots, present, pending);
            for (NSString *k in slots) {
                BOOL covered = [present containsObject:k];
                for (NSString *p in present) if (DMSMKeyCovers(k, p) || DMSMKeyCovers(p, k)) covered = YES;
                BOOL pend = [pending containsObject:k] || [pending containsObject:DMSMKeyBundle(k)];
                CHECK([closed containsObject:k] == (!covered && !pend), "sweep %d: %s closed exactly when no stage names it and it is not pending", n, k.UTF8String);
            }
            NSArray *lf = DMSMFitLeftAfterClose(slots, closed, tm);
            CHECK(lf.count + closed.count == slots.count, "sweep %d: the windows left and the closed ones are the arrangement", n);
            for (NSUInteger i = 1; i < lf.count; i++) {
                NSNumber *a = tm[lf[i - 1]], *b = tm[lf[i]];
                CHECK(!(b && !a) && !(a && b && [a longLongValue] < [b longLongValue]), "sweep %d: the windows left newest first", n);
            }
            NSDictionary *mem = @{DMSMFitDeskKey(slots.allKeys): slots, DMSMFitDeskKey(@[@"z.other"]): @{@"z.other": @"fill"}};
            NSDictionary *mw = DMSMFitMemoryWithout(mem, closed);
            CHECK(mw[DMSMFitDeskKey(@[@"z.other"])] != nil && (closed.count ? mw.count == 1 : mw == mem), "sweep %d: only the desktops of closed windows go", n);
        }
        printf("test-smfitclosed: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
