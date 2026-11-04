// Mac test of where Fit to Window's windows go when its set of windows changes, the one rule of every engine (1.8.0 engine parity, KT 3 Nov:
// statusbar/FitPlan.h MSBDFitPlanKeepingPlaces, which StatusBar.x, MacSwitcher.h, MacSwitcherSM.h and SMFitPlan.h's DMSMFitPlanDecide run). Run by
// test-fitorder.sh, which also checks every site that lays tiles out again.
//  1. the tiles: their parts of the desktop, what a window keeps, reading order.
//  2. every close-up of every arrangement Fit makes: each window that stays keeps its place (grows into the space next to it), the table.
//  3. joins: the new window takes the first tile, newest first; the others keep their places.
//  4. the device stories (3 Nov, M1 15.6.1 Aerial 5.1 and iPad 2 16.7.7 Stage Manager, the same windows): the old rules -- the order the windows
//     joined in (Aerial, Zetsu, MilkyWay4) and the order of their last use (Stage Manager) -- copied as references: they differ, as on the
//     devices; the rule gives one plan whatever order the engine hands it.
//  5. Stage Manager's plan (SMFitPlan.h DMSMFitPlanDecide) and the side question's default: the same plans as the other engines'.
//  6. a sweep against a second, plain implementation (every assignment tried): the most kept, one arrangement, each tile once, the engine's
//     order of the windows that had tiles never matters.
#import <Foundation/Foundation.h>
#include "../statusbar/SMFitPlan.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static NSString *D(NSDictionary *d) {   // (a plan as text, sorted: "a left, b right")
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in [d.allKeys sortedArrayUsingSelector:@selector(compare:)]) [a addObject:[NSString stringWithFormat:@"%@ %@", k, d[k]]];
    return [a componentsJoinedByString:@", "];
}
static BOOL Is(NSDictionary *plan, NSDictionary *want) { return [plan isEqualToDictionary:want]; }
// The old rules, as they were before 1.8.0: the windows in the engine's order took the default tiles (StatusBar.x DMFitPlanAfterLeave /
// DMAssignDefaultSlots); one filled.
static NSDictionary *OldDefault(NSArray *order) {
    if (order.count == 1) return @{ order[0]: @"fill" };
    NSArray *names = MSBDFitDefaultTiles(order.count);
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < order.count && i < names.count; i++) p[order[i]] = names[i];
    return p;
}
static NSArray *ByTime(NSDictionary *times) {   // (Stage Manager's order: the last use first)
    return [times keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [b compare:a]; }];
}
static double KeptOf(NSDictionary *plan, NSDictionary *was) {
    double k = 0;
    for (NSString *w in plan) { MSBDFitUnit a, b; if (MSBDFitTileUnit(was[w], &a) && MSBDFitTileUnit(plan[w], &b)) k += MSBDFitKept(a, b); }
    return k;
}
// A second implementation for the sweep: every assignment of the windows to every allowed arrangement, the new ones in the first tiles in order;
// returns the most a plan can keep and whether plan is one of the allowed plans.
static double BestKept(NSArray *windows, NSDictionary *was, NSDictionary *plan, BOOL *allowed) {
    NSUInteger n = MIN((NSUInteger)4, windows.count);
    NSArray *w = [windows subarrayWithRange:NSMakeRange(0, n)];
    NSMutableArray *olds = [NSMutableArray array], *news = [NSMutableArray array];
    for (NSString *x in w) { MSBDFitUnit u; if (MSBDFitTileUnit(was[x], &u)) [olds addObject:x]; else [news addObject:x]; }
    NSMutableArray *arrs = [NSMutableArray arrayWithObject:(n == 1 ? @[@"fill"] : MSBDFitDefaultTiles(n))];
    if (n == 3 && !news.count) [arrs addObject:@[@"topleft", @"bottomleft", @"right"]];
    double best = -1; BOOL found = NO;
    for (NSArray *tiles in arrs) {
        NSArray *rest = [tiles subarrayWithRange:NSMakeRange(news.count, n - news.count)];
        NSMutableArray *perms = [NSMutableArray arrayWithObject:@[]];
        for (NSUInteger i = 0; i < rest.count; i++) {   // (every order of the tiles left)
            NSMutableArray *next = [NSMutableArray array];
            for (NSArray *p in perms) for (NSString *t in rest) if (![p containsObject:t]) [next addObject:[p arrayByAddingObject:t]];
            perms = next;
        }
        for (NSArray *p in perms) {
            NSMutableDictionary *cand = [NSMutableDictionary dictionary];
            for (NSUInteger i = 0; i < news.count; i++) cand[news[i]] = tiles[i];
            for (NSUInteger i = 0; i < olds.count; i++) cand[olds[i]] = p[i];
            double k = KeptOf(cand, was);
            if (k > best) best = k;
            if ([cand isEqualToDictionary:plan]) found = YES;
        }
    }
    if (allowed) *allowed = found;
    return best;
}

int main(void) {
    @autoreleasepool {
        // 1. the tiles
        MSBDFitUnit u, v;
        CHECK(MSBDFitTileUnit(@"left", &u) && u.x == 0 && u.y == 0 && u.w == 0.5 && u.h == 1, "left is the left half");
        CHECK(MSBDFitTileUnit(@"bottomright", &u) && u.x == 0.5 && u.y == 0.5 && u.w == 0.5 && u.h == 0.5, "bottomright is the bottom-right quarter");
        CHECK(MSBDFitTileUnit(@"fill", &u) && u.w == 1 && u.h == 1 && MSBDFitTileUnit(@"top", &v) && v.h == 0.5 && v.w == 1, "fill and top");
        CHECK(!MSBDFitTileUnit(@"center", &u) && !MSBDFitTileUnit(@"small", &u) && !MSBDFitTileUnit(nil, &u) && !MSBDFitTileUnit(@3, &u) && !MSBDFitTileUnit(@"", &u), "no tile: the middle place, a size, nothing, a number, empty");
        MSBDFitTileUnit(@"left", &u); MSBDFitTileUnit(@"topleft", &v);
        CHECK(MSBDFitKept(u, v) == 0.25 && MSBDFitKept(v, u) == 0.25, "a half keeps a quarter in its top quarter");
        MSBDFitTileUnit(@"right", &v);
        CHECK(MSBDFitKept(u, v) == 0, "the left half keeps nothing in the right one");
        MSBDFitTileUnit(@"fill", &v);
        CHECK(MSBDFitKept(u, v) == 0.5, "the left half keeps all of itself in fill");
        MSBDFitTileUnit(@"topright", &u); MSBDFitTileUnit(@"bottomleft", &v);
        CHECK(MSBDFitReadsBefore(u, v) && !MSBDFitReadsBefore(v, u), "reading order: the top row first (top right before bottom left)");
        MSBDFitTileUnit(@"left", &u); MSBDFitTileUnit(@"topright", &v);
        CHECK(MSBDFitReadsBefore(u, v), "reading order: the left half before the top-right quarter (the default tiles' own order)");
        CHECK([MSBDFitDefaultTiles(2) isEqualToArray:(@[@"left", @"right"])] && [MSBDFitDefaultTiles(3) isEqualToArray:(@[@"left", @"topright", @"bottomright"])]
              && [MSBDFitDefaultTiles(4) isEqualToArray:(@[@"topleft", @"topright", @"bottomleft", @"bottomright"])], "the default tiles");

        // 2. every close-up of every arrangement
        NSDictionary *quarters = @{@"a": @"topleft", @"b": @"topright", @"c": @"bottomleft", @"d": @"bottomright"};
        struct { const char *why; NSArray *left; NSDictionary *want; } q[] = {
            {"four, the top-left closed: the bottom-left grows up, the right two keep theirs", @[@"b", @"c", @"d"], @{@"c": @"left", @"b": @"topright", @"d": @"bottomright"}},
            {"four, the top-right closed: the bottom-right grows up, the left two keep theirs (the half on the right)", @[@"a", @"c", @"d"], @{@"a": @"topleft", @"c": @"bottomleft", @"d": @"right"}},
            {"four, the bottom-left closed: the top-left grows down", @[@"a", @"b", @"d"], @{@"a": @"left", @"b": @"topright", @"d": @"bottomright"}},
            {"four, the bottom-right closed: the top-right grows down (the half on the right)", @[@"a", @"b", @"c"], @{@"a": @"topleft", @"c": @"bottomleft", @"b": @"right"}},
            {"four, the top row closed: the bottom two take the halves", @[@"c", @"d"], @{@"c": @"left", @"d": @"right"}},
            {"four, the bottom row closed: the top two take the halves", @[@"a", @"b"], @{@"a": @"left", @"b": @"right"}},
            {"four, the left column closed: the top one of the right column takes the left half", @[@"b", @"d"], @{@"b": @"left", @"d": @"right"}},
            {"four, the right column closed: the top one of the left column keeps the left", @[@"a", @"c"], @{@"a": @"left", @"c": @"right"}},
            {"four, a diagonal closed: each keeps its side", @[@"b", @"c"], @{@"c": @"left", @"b": @"right"}},
            {"four, the other diagonal closed", @[@"a", @"d"], @{@"a": @"left", @"d": @"right"}},
            {"four, three closed: the one left fills", @[@"c"], @{@"c": @"fill"}},
        };
        for (size_t i = 0; i < sizeof q / sizeof q[0]; i++) {
            NSDictionary *p = MSBDFitPlanKeepingPlaces(q[i].left, quarters);
            CHECK(Is(p, q[i].want), "%s: %s (want %s)", q[i].why, D(p).UTF8String, D(q[i].want).UTF8String);
            // (whatever order the engine hands the windows in)
            NSArray *rev = [[q[i].left reverseObjectEnumerator] allObjects];
            CHECK(Is(MSBDFitPlanKeepingPlaces(rev, quarters), q[i].want), "%s, the windows in the other order: the same", q[i].why);
        }
        NSDictionary *three = @{@"a": @"left", @"b": @"topright", @"c": @"bottomright"};
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"b", @"c"], three), (@{@"b": @"left", @"c": @"right"})), "three, the left half closed: the top one takes the left half (reading order)");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"c", @"b"], three), (@{@"b": @"left", @"c": @"right"})), "  ... also when the engine hands the bottom one first (it was used last)");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"c", @"a"], three), (@{@"a": @"left", @"c": @"right"})), "three, the top-right closed: the left keeps the left, the bottom-right grows up");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"a", @"b"], three), (@{@"a": @"left", @"b": @"right"})), "three, the bottom-right closed: the top-right grows down");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"a"], three), (@{@"a": @"fill"})), "three, two closed: fill");
        NSDictionary *halfRight = @{@"a": @"topleft", @"b": @"bottomleft", @"c": @"right"};   // (the side question's "Left")
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"c", @"b"], halfRight), (@{@"b": @"left", @"c": @"right"})), "the half on the right, the top-left closed: the bottom-left grows up");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"a", @"c"], halfRight), (@{@"a": @"left", @"c": @"right"})), "the half on the right, the bottom-left closed: the top-left grows down");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"b", @"a"], halfRight), (@{@"a": @"left", @"b": @"right"})), "the half on the right closed: the top one of the left takes the left half");
        NSDictionary *halves = @{@"a": @"left", @"b": @"right"};
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"b"], halves), (@{@"b": @"fill"})) && Is(MSBDFitPlanKeepingPlaces(@[@"a"], halves), (@{@"a": @"fill"})), "two, one closed: the other fills");
        CHECK(MSBDFitPlanKeepingPlaces(@[], halves).count == 0 && MSBDFitPlanKeepingPlaces(nil, nil).count == 0, "none left: nothing");

        // 3. joins
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"a"], @{@"a": @"fill"}), (@{@"n": @"left", @"a": @"right"})), "one filling, a new one: the new one on the left");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"a"], nil), (@{@"n": @"left", @"a": @"right"})), "  ... the same with nothing kept (a window placed by hand)");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"a", @"b"], halves), (@{@"n": @"left", @"a": @"topright", @"b": @"bottomright"})), "two halves and a third (no side chosen): the left one to the top right, the right one below it");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"b", @"a"], halves), (@{@"n": @"left", @"a": @"topright", @"b": @"bottomright"})), "  ... whichever was used last");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"a", @"b", @"c"], three), (@{@"n": @"topleft", @"a": @"bottomleft", @"b": @"topright", @"c": @"bottomright"})), "three and a fourth: the left half's window keeps its bottom, the right two keep theirs");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"c", @"b", @"a"], three), (@{@"n": @"topleft", @"a": @"bottomleft", @"b": @"topright", @"c": @"bottomright"})), "  ... whatever order");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"a", @"b", @"c"], halfRight), (@{@"n": @"topleft", @"a": @"topright", @"b": @"bottomleft", @"c": @"bottomright"})), "the half on the right and a fourth: the new one takes the top left, the one there the top right");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"m", @"a", @"b"], halves), (@{@"n": @"topleft", @"m": @"topright", @"a": @"bottomleft", @"b": @"bottomright"})), "two new ones at once: the first tiles, in the engine's order; the halves' windows keep their sides below");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"a", @"b"], (@{@"n": @"left", @"a": @"left", @"b": @"right"})), MSBDFitPlanKeepingPlaces(@[@"n", @"a", @"b"], (@{@"n": @"left", @"a": @"left", @"b": @"right"}))), "the same answer twice");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"w1", @"w2", @"w3", @"w4"], nil), (@{@"w1": @"topleft", @"w2": @"topright", @"w3": @"bottomleft", @"w4": @"bottomright"})), "nothing kept (Fit switched on): the default tiles in the engine's order");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"w1", @"w2", @"w3"], nil), (@{@"w1": @"left", @"w2": @"topright", @"w3": @"bottomright"})), "  ... three");
        NSDictionary *five = MSBDFitPlanKeepingPlaces(@[@"w1", @"w2", @"w3", @"w4", @"w5"], nil);
        CHECK(five.count == 4 && !five[@"w5"], "five: the first four only (%s)", D(five).UTF8String);
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"a", @"a", @"b", @"", (NSString *)[NSNull null]], halves), (@{@"a": @"left", @"b": @"right"})), "a window twice, an empty one, not a string: each window once");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"a", @"b"], (@{@"a": @"left", @"b": @"left"})), (@{@"a": @"left", @"b": @"right"})) && Is(MSBDFitPlanKeepingPlaces(@[@"b", @"a"], (@{@"a": @"left", @"b": @"left"})), (@{@"b": @"left", @"a": @"right"})), "two windows with one tile: the engine's order parts them");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"n", @"x", @"y"], (@{@"x": @"top", @"y": @"bottom"})), (@{@"n": @"left", @"x": @"topright", @"y": @"bottomright"})), "one above the other (read back after a respring) and a new one: each keeps its row");
        CHECK(Is(MSBDFitPlanKeepingPlaces(@[@"a", @"b"], (@{@"a": @"center", @"b": @"right"})), (@{@"a": @"left", @"b": @"right"})), "a window without one of Fit's tiles: new, the first tile");

        // 4. the device stories (3 Nov; Notes, Calendar, Maps, Clock -- test apps)
        NSString *notes = @"com.apple.mobilenotes", *cal = @"com.apple.mobilecal", *maps = @"com.apple.Maps", *clock = @"com.apple.mobiletimer";
        {   // S1: Maps, Calendar, Notes (no side chosen): Notes left, Calendar top right, Maps bottom right; Maps used last; Calendar closed
            NSDictionary *slots = @{notes: @"left", cal: @"topright", maps: @"bottomright"};
            NSArray *aerial = @[notes, maps];   // (the order they joined in: [Notes, Calendar, Maps] without Calendar)
            NSArray *sm = ByTime(@{maps: @1160, notes: @1158});   // (the iPad 2's interaction times)
            CHECK(Is(OldDefault(aerial), (@{notes: @"left", maps: @"right"})), "S1 before, Aerial: Notes kept the left half (M1)");
            CHECK(Is(OldDefault(sm), (@{maps: @"left", notes: @"right"})), "S1 before, Stage Manager: Maps took the left half, Notes went right (iPad 2)");
            CHECK(!Is(OldDefault(aerial), OldDefault(sm)), "S1 before: the engines differed");
            CHECK(Is(MSBDFitPlanKeepingPlaces(aerial, slots), (@{notes: @"left", maps: @"right"})) && Is(MSBDFitPlanKeepingPlaces(sm, slots), (@{notes: @"left", maps: @"right"})), "S1 now: Notes keeps the left half, Maps grows up -- on every engine");
        }
        {   // S2 (M1): Notes left, Maps right, Calendar opened with "Right": Calendar top right, Maps bottom right; Calendar closed
            NSDictionary *slots = @{notes: @"left", cal: @"topright", maps: @"bottomright"};
            NSArray *aerial = @[maps, notes];   // ([Calendar, Maps, Notes]: the side question's group, the right side's window second)
            CHECK(Is(OldDefault(aerial), (@{maps: @"left", notes: @"right"})), "S2 before, Aerial: the two swapped sides (M1)");
            CHECK(Is(MSBDFitPlanKeepingPlaces(aerial, slots), (@{notes: @"left", maps: @"right"})), "S2 now: Notes keeps the left half, Maps grows up");
        }
        {   // S3: Maps left, Calendar top right, Notes bottom right; Clock joins
            NSDictionary *slots = @{maps: @"left", cal: @"topright", notes: @"bottomright"};
            NSArray *aerial = @[clock, cal, notes, maps];   // (Calendar joined last, by "Right": [Calendar, Notes, Maps]; Clock in front)
            NSArray *sm = @[clock, cal, maps, notes];       // (last use: Clock, Calendar, Maps, Notes)
            NSDictionary *want = @{clock: @"topleft", maps: @"bottomleft", cal: @"topright", notes: @"bottomright"};
            CHECK(Is(OldDefault(aerial), (@{clock: @"topleft", cal: @"topright", notes: @"bottomleft", maps: @"bottomright"})), "S3 before, Aerial: Notes to the bottom left, Maps to the bottom right (M1)");
            CHECK(Is(OldDefault(sm), (@{clock: @"topleft", cal: @"topright", maps: @"bottomleft", notes: @"bottomright"})), "S3 before, Stage Manager: Maps to the bottom left, Notes to the bottom right (iPad 2)");
            CHECK(Is(MSBDFitPlanKeepingPlaces(aerial, slots), want) && Is(MSBDFitPlanKeepingPlaces(sm, slots), want), "S3 now: Clock top left, Maps keeps the left side's bottom, Calendar and Notes keep theirs -- on every engine");
        }
        {   // S4: four tiled, the top-right quarter (Calendar) closed
            NSDictionary *m1 = @{clock: @"topleft", cal: @"topright", notes: @"bottomleft", maps: @"bottomright"};
            CHECK(Is(OldDefault(@[clock, notes, maps]), (@{clock: @"left", notes: @"topright", maps: @"bottomright"})), "S4 before, Aerial: Notes jumped from the bottom left to the top right (M1)");
            CHECK(Is(MSBDFitPlanKeepingPlaces(@[clock, notes, maps], m1), (@{clock: @"topleft", notes: @"bottomleft", maps: @"right"})), "S4 now: the left two keep theirs, Maps grows up");
            NSDictionary *ipad2 = @{clock: @"topleft", cal: @"topright", maps: @"bottomleft", notes: @"bottomright"};
            CHECK(Is(OldDefault(@[clock, maps, notes]), (@{clock: @"left", maps: @"topright", notes: @"bottomright"})), "S4 before, Stage Manager: Maps jumped from the bottom left to the top right (iPad 2)");
            CHECK(Is(MSBDFitPlanKeepingPlaces(@[clock, maps, notes], ipad2), (@{clock: @"topleft", maps: @"bottomleft", notes: @"right"})), "S4 now: the left two keep theirs, Notes grows up");
        }

        // 5. Stage Manager's plan and the side question's default
        {
            int how = -1;
            NSDictionary *slots = @{maps: @"left", cal: @"topright", notes: @"bottomright"};
            NSDictionary *p = DMSMFitPlanDecide(slots, @[clock, cal, maps, notes], MSBDFitDefaultTiles(4), &how);
            CHECK(how == DMSMFitDefault && Is(p, MSBDFitPlanKeepingPlaces(@[clock, cal, notes, maps], slots)), "DMSMFitPlanDecide: a fourth window, the same plan as Aerial's (%s)", D(p).UTF8String);
            p = DMSMFitPlanDecide(@{notes: @"left", cal: @"topright", maps: @"bottomright"}, @[maps, notes], MSBDFitDefaultTiles(2), &how);
            CHECK(how == DMSMFitDefault && Is(p, (@{notes: @"left", maps: @"right"})), "DMSMFitPlanDecide: S1's set, by last use: Notes keeps the left half");
            p = DMSMFitPlanDecide(@{@"L": @"left", @"R": @"right"}, @[@"N", @"R", @"L"], MSBDFitDefaultTiles(3), &how);
            NSDictionary *aerialDefault = MSBDFitPlanKeepingPlaces(@[@"N", @"L", @"R"], @{@"L": @"left", @"R": @"right"});   // (StatusBar.x DMSetSideChoiceGroup, no side)
            CHECK(how == DMSMFitDefault && Is(p, aerialDefault) && Is(p, (@{@"N": @"left", @"L": @"topright", @"R": @"bottomright"})), "no side chosen (the two tiles kept): the Stage Manager engine's default is the other engines' (%s)", D(p).UTF8String);
            p = DMSMFitPlanDecide(nil, @[@"N", @"R", @"L"], MSBDFitDefaultTiles(3), &how);
            CHECK(Is(p, (@{@"N": @"left", @"R": @"topright", @"L": @"bottomright"})), "(with the two tiles dropped, as before 1.8.0, the last use decided)");
            p = DMSMFitPlanDecide(quarters, @[@"d", @"c", @"b", @"a"], MSBDFitDefaultTiles(4), &how);
            CHECK(how == DMSMFitKept && Is(p, quarters), "DMSMFitPlanDecide: the same four windows: kept");
            p = DMSMFitPlanDecide(quarters, @[@"e", @"a", @"b", @"c", @"d"], MSBDFitDefaultTiles(4), &how);
            CHECK(how == DMSMFitFourKept && Is(p, quarters), "DMSMFitPlanDecide: a fifth: the four kept");
            p = DMSMFitPlanDecide(quarters, @[@"b", @"c", @"d"], MSBDFitDefaultTiles(3), &how);
            CHECK(how == DMSMFitDefault && Is(p, (@{@"c": @"left", @"b": @"topright", @"d": @"bottomright"})), "DMSMFitPlanDecide: a quarter closed: the others keep their places");
            p = DMSMFitPlanDecide(quarters, @[@"b", @"c", @"d"], @[], &how);
            CHECK(p.count == 0, "DMSMFitPlanDecide: no default tiles asked for: nothing");
        }

        // 6. the sweep
        srandom(11);
        NSArray *names = @[@"fill", @"left", @"right", @"top", @"bottom", @"topleft", @"topright", @"bottomleft", @"bottomright", @"center"];
        NSArray *arrangements = @[@[@"fill"], @[@"left", @"right"], @[@"left", @"topright", @"bottomright"], @[@"topleft", @"bottomleft", @"right"], @[@"topleft", @"topright", @"bottomleft", @"bottomright"]];
        int checked = 0;
        for (int n = 0; n < 60000; n++) {
            int nw = 1 + (int)(random() % 5);
            NSMutableArray *ws = [NSMutableArray array];
            for (int i = 0; i < nw; i++) [ws addObject:[NSString stringWithFormat:@"w%d", i]];
            for (int i = nw - 1; i > 0; i--) [ws exchangeObjectAtIndex:i withObjectAtIndex:random() % (i + 1)];
            NSMutableDictionary *was = [NSMutableDictionary dictionary];
            if (random() % 4) {   // (a real arrangement of Fit's, some of its windows still here, some new)
                NSArray *arr = arrangements[random() % arrangements.count];
                NSMutableArray *pool = [ws mutableCopy];
                for (NSString *t in arr) { if (!pool.count) break; if (random() % 5 == 0) continue; NSUInteger k = random() % pool.count; was[pool[k]] = t; [pool removeObjectAtIndex:k]; }
            } else for (NSString *x in ws) if (random() % 2) was[x] = names[random() % names.count];   // (anything, tiles shared)
            NSDictionary *p = MSBDFitPlanKeepingPlaces(ws, was);
            NSUInteger want = MIN((NSUInteger)4, ws.count);
            CHECK(p.count == want, "sweep %d: %lu windows tiled, want %lu", n, (unsigned long)p.count, (unsigned long)want);
            CHECK([[NSSet setWithArray:p.allValues] count] == p.count, "sweep %d: each tile once (%s)", n, D(p).UTF8String);
            BOOL one = NO;
            for (NSArray *arr in arrangements) if ([[NSSet setWithArray:arr] isEqualToSet:[NSSet setWithArray:p.allValues]]) one = YES;
            CHECK(one, "sweep %d: one of Fit's arrangements (%s)", n, D(p).UTF8String);
            for (NSUInteger i = 0; i < want; i++) CHECK(p[ws[i]] != nil, "sweep %d: the first four windows are the tiled ones", n);
            BOOL allowed = NO;
            double best = BestKept(ws, was, p, &allowed);
            CHECK(allowed && fabs(KeptOf(p, was) - best) < 1e-9, "sweep %d: the most the windows can keep (%.2f of %.2f; %s; was %s)", n, KeptOf(p, was), best, D(p).UTF8String, D(was).UTF8String);
            // (the engine's order of the windows that had tiles never matters when their tiles are their own)
            NSMutableArray *tiled = [NSMutableArray array];
            for (NSString *x in [ws subarrayWithRange:NSMakeRange(0, want)]) { MSBDFitUnit tu; if (MSBDFitTileUnit(was[x], &tu)) [tiled addObject:x]; }
            NSMutableSet *own = [NSMutableSet set]; BOOL distinct = YES;
            for (NSString *x in tiled) { if ([own containsObject:was[x]]) distinct = NO; [own addObject:was[x]]; }
            if (distinct && tiled.count >= 2) {
                NSMutableArray *ws2 = [ws mutableCopy];
                NSMutableArray *shuffled = [tiled mutableCopy];
                for (NSInteger i = (NSInteger)shuffled.count - 1; i > 0; i--) [shuffled exchangeObjectAtIndex:i withObjectAtIndex:random() % (i + 1)];
                NSUInteger k = 0;
                for (NSUInteger i = 0; i < want; i++) if ([tiled containsObject:ws2[i]]) ws2[i] = shuffled[k++];
                NSDictionary *p2 = MSBDFitPlanKeepingPlaces(ws2, was);
                CHECK(Is(p2, p), "sweep %d: the engine's order of the tiled windows does not matter (%s vs %s)", n, D(p).UTF8String, D(p2).UTF8String);
                checked++;
            }
        }
        CHECK(checked > 10000, "the order sweep ran (%d)", checked);
        printf("test-fitorder: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
