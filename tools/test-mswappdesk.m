// Mac test of where an app opens when its windows are on other Mac Switcher desktops (statusbar/MSWAppDesk.h, 1.7.1 item 5): a window on the
// desktop on screen keeps the launch here (Stay); otherwise the newest window the launch names comes here (Bring), or with Go to the App's
// Desktop on its desktop comes (Go). Aerial / Zetsu / MilkyWay4 entries by app (a window, each desktop's full-screen app, a window iPadOS closed
// while away -- ranked by the caller), Stage Manager entries by window (SMWindowKey.h: an app key names the app's windows, a window key that window
// only); bad input; a random sweep of the rules. Run by test-mswappdesk.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/MSWAppDesk.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

#define CLOCK @"com.apple.mobiletimer"
#define TIPS @"com.apple.tips"
#define NOTES @"com.apple.mobilenotes"
static NSString *K(NSString *b, NSString *s) { return [NSString stringWithFormat:@"%@|sceneID:%@-%@", b, b, s]; }
static NSDictionary *W(NSString *k, NSInteger d, long long t) { return @{@"k": k, @"d": @(d), @"t": @(t)}; }
static DMMSWAppDeskWay Decide(NSArray *wins, NSInteger cur, NSString *key, BOOL go, NSUInteger *pick) { return DMMSWAppDeskDecide(wins, cur, key, go, pick); }

int main(void) {
    @autoreleasepool {
        NSUInteger p = 0;
        // ---- Aerial / Zetsu / MilkyWay4: one window per app, by app; the caller ranks a window (3) over a full-screen app (2) over a closed one (1) ----
        // 1. its window on the desktop on screen: Stay, either way
        CHECK(Decide(@[W(CLOCK, 1, 3)], 1, CLOCK, NO, &p) == DMMSWAppDeskStay && p == NSNotFound, "window here: Stay (Bring default)");
        CHECK(Decide(@[W(CLOCK, 1, 3)], 1, CLOCK, YES, &p) == DMMSWAppDeskStay && p == NSNotFound, "window here: Stay (Go)");
        // 2. its window away on Desktop 2 (id 2): Bring it (default) / Go there (the switch)
        CHECK(Decide(@[W(CLOCK, 2, 3)], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 0, "window on 2: Bring");
        CHECK(Decide(@[W(CLOCK, 2, 3)], 1, CLOCK, YES, &p) == DMMSWAppDeskGo && p == 0, "window on 2: Go with the switch");
        // 3. no window anywhere: a plain launch here
        CHECK(Decide(@[], 1, CLOCK, NO, &p) == DMMSWAppDeskStay && p == NSNotFound, "no window: Stay");
        CHECK(Decide(@[W(TIPS, 2, 3)], 1, CLOCK, NO, &p) == DMMSWAppDeskStay && p == NSNotFound, "another app's window only: Stay");
        // 4. a full-screen app left on Desktop 3 only: it comes (Bring) / its desktop comes (Go)
        CHECK(Decide(@[W(CLOCK, 3, 2)], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 0, "full screen on 3: Bring");
        CHECK(Decide(@[W(CLOCK, 3, 2)], 2, CLOCK, YES, &p) == DMMSWAppDeskGo && p == 0, "full screen on 3 from 2: Go");
        // 5. a window away on 2 and a full-screen record on 3: the window (ranked newer) -- the order DMMSWElsewhereIndex always took
        CHECK(Decide(@[W(CLOCK, 2, 3), W(CLOCK, 3, 2)], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 0, "window over full screen: the window");
        CHECK(Decide(@[W(CLOCK, 3, 2), W(CLOCK, 2, 3)], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 1, "window over full screen, listed second: the window");
        // 6. a window here and a stale full-screen record elsewhere: Stay (the window here comes forward; before 1.7.1 the full-screen record's
        //    desktop came)
        CHECK(Decide(@[W(CLOCK, 1, 3), W(CLOCK, 3, 2)], 1, CLOCK, NO, &p) == DMMSWAppDeskStay, "window here + full screen elsewhere: Stay");
        CHECK(Decide(@[W(CLOCK, 3, 2), W(CLOCK, 1, 3)], 1, CLOCK, YES, &p) == DMMSWAppDeskStay, "full screen elsewhere + window here: Stay (Go)");
        // 7. a window iPadOS closed while Desktop 2 was away (its record, no window): Bring / Go
        CHECK(Decide(@[W(CLOCK, 2, 1)], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 0, "closed record on 2: Bring");
        CHECK(Decide(@[W(CLOCK, 2, 1)], 1, CLOCK, YES, &p) == DMMSWAppDeskGo && p == 0, "closed record on 2: Go");
        // 8. the desktop on screen is not Desktop 1 (id 4, a desktop made later): a window on Desktop 1 comes
        CHECK(Decide(@[W(CLOCK, 1, 3)], 4, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 0, "from desktop id 4: Desktop 1's window comes");

        // ---- Stage Manager: windows by key ----
        NSArray *two = @[W(K(CLOCK, @"A"), 2, 10), W(K(CLOCK, @"B"), 3, 20), W(K(TIPS, @"C"), 3, 30)];
        // 9. an app key (a Dock tap): the app's newest window, B on 3 (Tips' newer window is another app's)
        CHECK(Decide(two, 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 1, "SM app key: newest window B (%lu)", (unsigned long)p);
        CHECK(Decide(two, 1, CLOCK, YES, &p) == DMMSWAppDeskGo && p == 1, "SM app key, Go: B's desktop");
        // 10. a window key (SpringBoard named that window): that window, also when it is not the newest
        CHECK(Decide(two, 1, K(CLOCK, @"A"), NO, &p) == DMMSWAppDeskBring && p == 0, "SM window key A: A (%lu)", (unsigned long)p);
        // 11. one of the app's windows on the desktop on screen: Stay for the app key; a window key naming the OTHER window brings that one
        NSArray *here = @[W(K(CLOCK, @"A"), 1, 10), W(K(CLOCK, @"B"), 3, 20)];
        CHECK(Decide(here, 1, CLOCK, NO, &p) == DMMSWAppDeskStay && p == NSNotFound, "SM app key, a window here: Stay");
        CHECK(Decide(here, 1, CLOCK, YES, &p) == DMMSWAppDeskStay, "SM app key, a window here: Stay (Go)");
        CHECK(Decide(here, 1, K(CLOCK, @"B"), NO, &p) == DMMSWAppDeskBring && p == 1, "SM window key B (on 3) while A is here: B comes");
        CHECK(Decide(here, 1, K(CLOCK, @"A"), NO, &p) == DMMSWAppDeskStay, "SM window key A (here): Stay");
        // 12. a window key of a window that is not there: Stay (never another window of its app)
        CHECK(Decide(two, 1, K(CLOCK, @"Z"), NO, &p) == DMMSWAppDeskStay && p == NSNotFound, "SM unknown window key: Stay");
        // 13. records by app (an older build's, or windows told apart by app) and a window key: the app's entry covers the window
        CHECK(Decide(@[W(CLOCK, 2, 5)], 1, K(CLOCK, @"A"), NO, &p) == DMMSWAppDeskBring && p == 0, "SM app record, window key: Bring");
        CHECK(Decide(@[W(CLOCK, 1, 5)], 1, K(CLOCK, @"A"), NO, &p) == DMMSWAppDeskStay, "SM app record here, window key: Stay");
        // 14. equals: the first one listed
        CHECK(Decide(@[W(K(CLOCK, @"A"), 2, 7), W(K(CLOCK, @"B"), 3, 7)], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 0, "SM equal times: the first");
        // 15. windows on three desktops, the newest on the middle one
        CHECK(Decide(@[W(K(NOTES, @"1"), 2, 1), W(K(NOTES, @"2"), 3, 9), W(K(NOTES, @"3"), 4, 4)], 1, NOTES, NO, &p) == DMMSWAppDeskBring && p == 1, "SM three desktops: the newest");

        // ---- bad input ----
        CHECK(Decide(two, 1, nil, NO, &p) == DMMSWAppDeskStay && p == NSNotFound, "nil key");
        CHECK(Decide(two, 1, @"", NO, &p) == DMMSWAppDeskStay, "empty key");
        CHECK(Decide((NSArray *)@{}, 1, CLOCK, NO, &p) == DMMSWAppDeskStay, "not a list");
        CHECK(Decide(nil, 1, CLOCK, NO, &p) == DMMSWAppDeskStay, "nil list");
        CHECK(Decide(@[@"x", @{@"k": CLOCK}, @{@"k": CLOCK, @"d": @"2"}, @{@"k": @5, @"d": @2}, W(CLOCK, 2, 1)], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 4, "malformed entries skipped (%lu)", (unsigned long)p);
        CHECK(Decide(@[@{@"k": CLOCK, @"d": @2}], 1, CLOCK, NO, &p) == DMMSWAppDeskBring && p == 0, "no time: counted as 0");
        CHECK(Decide(@[W(CLOCK, 2, 1)], 1, CLOCK, NO, NULL) == DMMSWAppDeskBring, "no pick pointer");

        // ---- a random sweep: the rules hold for any set ----
        srandom(171);
        NSArray *apps = @[CLOCK, TIPS, NOTES];
        int sweeps = 0;
        for (int n = 0; n < 4000; n++) {
            NSMutableArray *wins = [NSMutableArray array];
            NSUInteger count = (NSUInteger)(random() % 7);
            for (NSUInteger i = 0; i < count; i++) {
                NSString *b = apps[random() % 3];
                NSString *k = random() % 4 == 0 ? b : K(b, [NSString stringWithFormat:@"%ld", random() % 4]);
                [wins addObject:W(k, 1 + random() % 4, random() % 6)];
            }
            NSInteger cur = 1 + random() % 4;
            NSString *b = apps[random() % 3];
            NSString *key = random() % 2 ? b : K(b, [NSString stringWithFormat:@"%ld", random() % 4]);
            BOOL go = random() % 2;
            NSUInteger pk = 7;
            DMMSWAppDeskWay way = Decide(wins, cur, key, go, &pk);
            BOOL anyHere = NO, any = NO; long long maxT = LLONG_MIN; NSUInteger first = NSNotFound;
            for (NSUInteger i = 0; i < wins.count; i++) {
                NSString *k = wins[i][@"k"];
                if (!(DMSMKeyCovers(key, k) || DMSMKeyCovers(k, key))) continue;
                if ([wins[i][@"d"] integerValue] == cur) anyHere = YES;
                any = YES;
                long long t = [wins[i][@"t"] longLongValue];
                if (t > maxT) { maxT = t; first = i; }
            }
            BOOL ok;
            if (anyHere || !any) ok = way == DMMSWAppDeskStay && pk == NSNotFound;
            else ok = way == (go ? DMMSWAppDeskGo : DMMSWAppDeskBring) && pk == first && [wins[pk][@"d"] integerValue] != cur
                      && [DMSMKeyBundle(wins[pk][@"k"]) isEqualToString:b];
            if (!ok) { CHECK(NO, "sweep %d: key %s cur %ld go %d -> way %d pick %lu (%s)", n, key.UTF8String, (long)cur, go, way, (unsigned long)pk, wins.description.UTF8String); break; }
            sweeps++;
        }
        CHECK(sweeps == 4000, "random sweep: %d of 4000", sweeps);
    }
    printf("%s: %d passed, %d failed\n", fails ? "FAIL" : "PASS", passes, fails);
    return fails ? 1 : 0;
}
