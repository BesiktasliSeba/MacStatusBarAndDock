// Mac test of the windows past Fit to Window's four tiles and of a turn with a tiled window minimized, one rule on every engine (1.8.0 engine
// parity, KT 3 Nov: a behaviour that differs between engines is a bug): statusbar/FitPlan.h MSBDFitWhenOneOpens (Aerial, Zetsu, MilkyWay4's
// DMCascadeStage and DMMSWFitBringHere, the Stage Manager engine through SMFitPlan.h DMSMFitTakingPart) and MSBDFitTileStaysAtTurn
// (DMRelayoutForOrientation). Run by test-fitloose.sh, which also checks the sites as built.
//  1. the rule: a window that opens joins while fewer than four others take part, with every regular window there, the new one first; else it
//     is a regular window itself.
//  2. Stage Manager's look (DMSMFitTakingPart): the device story (five windows, one of four tiles closed: the fifth stays where it is), a sixth
//     window, room again, several windows at once, a set nothing is known of (Fit switched on), windows out of sight.
//  3. both engines played as built, event by event (Aerial's join and closure watcher; Stage Manager's launch, Close and look), over a sweep of
//     random opens, closes and No Fit windows: the same tiles and the same regular windows after every event. The rules before 1.8.0 copied as
//     references differ (Stage Manager pulled the fifth window in; Aerial counted a No Fit window among the four).
//  4. a turn: a minimized tiled window keeps its tile; gone, closing or No Fit, it does not.
#import <Foundation/Foundation.h>
#include "../statusbar/SMFitPlan.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static NSString *D(NSDictionary *d) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in [d.allKeys sortedArrayUsingSelector:@selector(compare:)]) [a addObject:[NSString stringWithFormat:@"%@ %@", k, d[k]]];
    return a.count ? [a componentsJoinedByString:@", "] : @"none";
}
static NSString *S(id<NSFastEnumeration> c) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *k in c) [a addObject:k];
    [a sortUsingSelector:@selector(compare:)];
    return a.count ? [a componentsJoinedByString:@", "] : @"none";
}

// ---- the engines as built, played on one desktop ----
// A desktop: its windows in the order they opened (the newest last: z-order back to front with Aerial, and the order of their last use with
// Stage Manager, as no window is brought forward here), the No Fit ones.
typedef struct { __unsafe_unretained NSMutableArray<NSString *> *open; __unsafe_unretained NSMutableSet<NSString *> *free; } Desk;
static NSArray<NSString *> *NewestFirst(NSArray<NSString *> *open) { return [[open reverseObjectEnumerator] allObjects]; }

// Aerial, Zetsu, MilkyWay4 (StatusBar.x as built): gFitGroup, gFitSlots; a regular window is an open window outside the group, not No Fit.
@interface AerialModel : NSObject
@property NSMutableArray<NSString *> *group; @property NSMutableDictionary<NSString *, NSString *> *slots; @property BOOL old;
@end
@implementation AerialModel
- (instancetype)init { if ((self = [super init])) { _group = [NSMutableArray array]; _slots = [NSMutableDictionary dictionary]; } return self; }
- (void)open:(NSString *)me desk:(Desk)d {   // (DMCascadeStage, Fit on; the side question unanswered: its default, DMSetSideChoiceGroup)
    if ([d.free containsObject:me]) return;   // (opened free: No Fit)
    [self.group removeObject:me];
    NSMutableArray *others = [NSMutableArray array];   // (the windows on screen, back to front)
    for (NSString *w in d.open) if (![w isEqualToString:me]) [others addObject:w];
    NSMutableArray *loose = [NSMutableArray array];
    for (NSString *w in NewestFirst(others)) if (![self.group containsObject:w] && ![d.free containsObject:w]) [loose addObject:w];
    NSArray *joined = MSBDFitWhenOneOpens(me, self.group, loose);
    if (self.old) joined = others.count >= 4 ? nil : MSBDFitWhenOneOpens(me, self.group, [[loose reverseObjectEnumerator] allObjects]);   // (before 1.8.0)
    if (!joined) return;
    self.group = [joined mutableCopy]; [self.group removeObject:me];
    for (NSString *w in loose) [self.slots removeObjectForKey:w];
    if (self.group.count == 2) {   // (two windows in the halves and a third: the question, no side chosen)
        NSString *l = nil, *r = nil;
        for (NSString *w in self.group) { if ([self.slots[w] isEqualToString:@"left"]) l = w; else if ([self.slots[w] isEqualToString:@"right"]) r = w; }
        if (l && r) { self.group = [@[me, l, r] mutableCopy]; self.slots = [MSBDFitPlanKeepingPlaces(self.group, @{l: @"left", r: @"right"}) mutableCopy]; return; }
    }
    [self.group insertObject:me atIndex:0];
    if (self.group.count >= 2) {   // (DMAssignTilesKeepingPlaces(me))
        NSMutableDictionary *was = [self.slots mutableCopy]; [was removeObjectForKey:me];
        self.slots = [MSBDFitPlanKeepingPlaces(self.group, was) mutableCopy];
    }
}
- (void)close:(NSString *)w desk:(Desk)d {   // (DMWatchFitClosures)
    if (![self.group containsObject:w]) { [self.slots removeObjectForKey:w]; return; }
    [self.group removeObject:w]; [self.slots removeObjectForKey:w];
    if (!self.group.count) return;
    NSMutableDictionary *was = [self.slots mutableCopy];
    self.slots = [MSBDFitPlanKeepingPlaces(self.group, was) mutableCopy];
}
- (NSDictionary *)tiles:(Desk)d {   // (the tiled windows on screen: a group of one with no tile is no tile)
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    for (NSString *w in self.group) if (self.slots[w] && [d.open containsObject:w] && (self.group.count >= 2 || [self.slots[w] isEqualToString:@"fill"])) t[w] = self.slots[w];
    return t;
}
@end

// Our Stage Manager engine (StatusBar.x as built): gSMFitSlots, gSMFitLoose; the launch's open-in-tile (DMSMAddToStage), Stage Manager's own Close
// (DMSMPlacesInClose) with Fit forgetting a closed window (DMSMFitForgetClosed), and Fit's look (DMSMFitTick).
@interface SMModel : NSObject
@property NSMutableDictionary<NSString *, NSString *> *slots; @property NSMutableSet<NSString *> *loose; @property BOOL old;
@end
@implementation SMModel
- (instancetype)init { if ((self = [super init])) { _slots = [NSMutableDictionary dictionary]; _loose = [NSMutableSet set]; } return self; }
- (NSArray *)bundles:(Desk)d { NSMutableArray *b = [NSMutableArray array]; for (NSString *w in NewestFirst(d.open)) if (![d.free containsObject:w]) [b addObject:w]; return b; }
- (void)look:(Desk)d {
    NSArray *bundles = [self bundles:d];
    if (!self.old) { NSSet *after = nil; bundles = DMSMFitTakingPart(bundles, self.slots, self.loose, &after); self.loose = [after mutableCopy]; }
    if (bundles.count < 2) {   // (one window: it fills only when its arrangement says so; the others of the arrangement closed: it is the one left)
        NSString *one = bundles.firstObject;
        if (one && self.slots[one] && self.slots.count >= 2) {
            BOOL othersGone = YES;
            for (NSString *k in self.slots) if (![k isEqualToString:one] && [d.open containsObject:k]) othersGone = NO;
            if (othersGone) self.slots = [MSBDFitPlanKeepingPlaces(@[one], nil) mutableCopy];
        }
        return;
    }
    if (bundles.count == 3 && self.slots.count == 2) {   // (the third window's question, no side chosen)
        NSString *n = nil, *l = nil, *r = nil;
        for (NSString *b in bundles) { NSString *s = self.slots[b]; if (!s) n = b; else if ([s isEqualToString:@"left"]) l = b; else if ([s isEqualToString:@"right"]) r = b; }
        if (n && l && r) self.slots = [@{l: @"left", r: @"right"} mutableCopy];
    }
    int how = DMSMFitDefault;
    NSDictionary *plan = DMSMFitPlanDecide(self.slots, bundles, MSBDFitDefaultTiles(MIN((NSUInteger)4, bundles.count)), &how);
    if (how == DMSMFitDefault) self.slots = [plan mutableCopy];
}
- (void)open:(NSString *)me desk:(Desk)d {
    if ([d.free containsObject:me]) { [self look:d]; return; }
    NSMutableArray *keys = [NSMutableArray arrayWithObject:me];   // (DMSMAddToStage: it and the stage's windows, newest first)
    for (NSString *w in NewestFirst(d.open)) if (![w isEqualToString:me] && ![d.free containsObject:w]) [keys addObject:w];
    NSMutableArray *stageNow = [keys mutableCopy]; [stageNow removeObject:me];
    if (stageNow.count == 2) {   // (two in the halves: asked before the launch, no side chosen -- the two tiles kept as places)
        NSString *l = nil, *r = nil;
        for (NSString *w in stageNow) { if ([self.slots[w] isEqualToString:@"left"]) l = w; else if ([self.slots[w] isEqualToString:@"right"]) r = w; }
        if (l && r && self.slots.count == 2) self.slots = [@{l: @"left", r: @"right"} mutableCopy];
    }
    NSArray *part = self.old ? keys : DMSMFitTakingPart(keys, self.slots, self.loose, NULL);
    int how = DMSMFitDefault;
    NSDictionary *plan = [part containsObject:me] && part.count >= 2 && part.count <= 4 ? DMSMFitPlanDecide(self.slots, part, MSBDFitDefaultTiles(part.count), &how) : nil;
    if (plan[me] && plan.count == part.count && how != DMSMFitFourKept) { self.slots = [plan mutableCopy]; for (NSString *k in plan) [self.loose removeObject:k]; }
    [self look:d];
}
- (void)close:(NSString *)w desk:(Desk)d {
    BOOL tiled = self.slots[w] != nil;
    if (tiled) {   // (Stage Manager's own Close: the tiled windows left close up in its transition; Fit's forget the same, DMSMFitLeftAfterClose)
        NSMutableDictionary *times = [NSMutableDictionary dictionary];
        NSUInteger i = 0; for (NSString *k in d.open) times[k] = @(++i);
        NSArray *left = DMSMFitLeftAfterClose(self.slots, [NSSet setWithObject:w], times);
        self.slots = left.count ? [MSBDFitPlanKeepingPlaces(left, self.slots) mutableCopy] : [NSMutableDictionary dictionary];
    }
    [self.loose removeObject:w];
    [self look:d];
}
- (NSDictionary *)tiles:(Desk)d {
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    for (NSString *w in self.slots) if ([d.open containsObject:w] && ![d.free containsObject:w]) t[w] = self.slots[w];
    if (t.count == 1 && ![t.allValues.firstObject isEqualToString:@"fill"]) return @{};   // (a lone window keeps a half only while another tiled one is out of sight: none here)
    return t;
}
@end

static unsigned gSeed = 12345;
static unsigned Rnd(unsigned n) { gSeed = gSeed * 1103515245u + 12345u; return (gSeed >> 16) % n; }

int main(void) {
    @autoreleasepool {
        // 1. the rule
        CHECK([MSBDFitWhenOneOpens(@"n", @[], @[]) isEqualToArray:@[@"n"]], "nothing else on the desktop: it alone (Fit tiles from the second)");
        CHECK([MSBDFitWhenOneOpens(@"n", @[@"a", @"b"], @[]) isEqualToArray:(@[@"n", @"a", @"b"])], "two tiled: it joins, first");
        CHECK([MSBDFitWhenOneOpens(@"n", @[@"a", @"b", @"c"], @[]) isEqualToArray:(@[@"n", @"a", @"b", @"c"])], "three tiled: it joins, the fourth");
        CHECK(MSBDFitWhenOneOpens(@"n", @[@"a", @"b", @"c", @"d"], @[]) == nil, "four tiled: a regular window over them");
        CHECK(MSBDFitWhenOneOpens(@"n", @[@"a", @"b", @"c"], @[@"e"]) == nil, "three tiled and a regular window: four take part, a regular window too");
        CHECK([MSBDFitWhenOneOpens(@"n", @[@"a", @"b"], @[@"e"]) isEqualToArray:(@[@"n", @"e", @"a", @"b"])], "two tiled and a regular window: both join, the new one first, the regular one next");
        CHECK([MSBDFitWhenOneOpens(@"n", @[@"a"], @[@"f", @"e"]) isEqualToArray:(@[@"n", @"f", @"e", @"a"])], "the regular windows newest first");
        CHECK([MSBDFitWhenOneOpens(@"n", @[], @[@"e", @"f", @"g"]) isEqualToArray:(@[@"n", @"e", @"f", @"g"])], "three regular windows, none tiled: all join");
        CHECK(MSBDFitWhenOneOpens(@"n", @[], @[@"e", @"f", @"g", @"h"]) == nil, "four regular windows: it is a regular one too");
        CHECK([MSBDFitWhenOneOpens(@"n", @[@"a", @"a", @"n", @""], @[(NSString *)[NSNull null], @"a"]) isEqualToArray:(@[@"n", @"a"])], "each window once; no empty one, no non-string, not the new one again");
        CHECK(MSBDFitWhenOneOpens(nil, @[@"a"], nil) == nil && MSBDFitWhenOneOpens(@"", @[], @[]) == nil, "no window: nothing");
        NSDictionary *p = MSBDFitPlanKeepingPlaces(MSBDFitWhenOneOpens(@"n", @[@"a", @"b"], @[@"e"]), @{@"a": @"left", @"b": @"right"});
        CHECK([p isEqualToDictionary:(@{@"n": @"topleft", @"e": @"topright", @"a": @"bottomleft", @"b": @"bottomright"})], "  ... the halves' windows keep their sides below, the new one and the regular one on top (%s)", D(p).UTF8String);

        // 2. Stage Manager's look
        NSDictionary *quarters = @{@"a": @"topleft", @"b": @"topright", @"c": @"bottomleft", @"d": @"bottomright"};
        NSSet *after = nil;
        NSArray *part = DMSMFitTakingPart(@[@"e", @"d", @"c", @"b", @"a"], quarters, [NSSet set], &after);
        CHECK([[NSSet setWithArray:part] isEqualToSet:[NSSet setWithArray:quarters.allKeys]] && [after isEqualToSet:[NSSet setWithObject:@"e"]], "a fifth window: a regular one over the four (%s; regular %s)", S(part).UTF8String, S(after).UTF8String);
        NSDictionary *closedUp = MSBDFitPlanKeepingPlaces(@[@"a", @"b", @"c"], quarters);   // (the bottom-right quarter closed)
        part = DMSMFitTakingPart(@[@"e", @"c", @"b", @"a"], closedUp, after, &after);
        CHECK([[NSSet setWithArray:part] isEqualToSet:([NSSet setWithArray:@[@"a", @"b", @"c"]])] && [after containsObject:@"e"], "the device story: one of four tiles closed -- the fifth stays where it is, the three close up (%s)", S(part).UTF8String);
        int how = -1;
        NSDictionary *plan = DMSMFitPlanDecide(closedUp, part, MSBDFitDefaultTiles(part.count), &how);
        CHECK(how == DMSMFitKept && [plan isEqualToDictionary:closedUp], "  ... their arrangement is kept as closed up (%s)", D(plan).UTF8String);
        NSDictionary *oldPlan = DMSMFitPlanDecide(closedUp, @[@"e", @"c", @"b", @"a"], MSBDFitDefaultTiles(4), &how);
        CHECK(oldPlan[@"e"] && [oldPlan[@"e"] isEqualToString:@"topleft"], "  (before 1.8.0 every window took part: the fifth took the first tile -- %s)", D(oldPlan).UTF8String);
        part = DMSMFitTakingPart(@[@"g", @"e", @"c", @"b", @"a"], closedUp, after, &after);
        CHECK(part.count == 3 && ![part containsObject:@"g"] && [after isEqualToSet:([NSSet setWithArray:@[@"e", @"g"]])], "a sixth window then: four take part (three tiled, one regular), it is a regular one too (regular %s)", S(after).UTF8String);
        NSDictionary *halves = MSBDFitPlanKeepingPlaces(@[@"a", @"b"], closedUp);   // (another tile closed)
        part = DMSMFitTakingPart(@[@"g", @"e", @"b", @"a"], halves, after, &after);
        CHECK(part.count == 2 && [after isEqualToSet:([NSSet setWithArray:@[@"e", @"g"]])], "a tile closed again: the two regular windows stay where they are");
        part = DMSMFitTakingPart(@[@"h", @"g", @"e", @"b", @"a"], halves, after, &after);
        CHECK(part.count == 2 && [after containsObject:@"h"], "a window opens with four taking part (two tiled, two regular): regular");
        NSDictionary *fill = MSBDFitPlanKeepingPlaces(@[@"a"], halves);
        part = DMSMFitTakingPart(@[@"h", @"g", @"e", @"a"], fill, after, &after);
        CHECK(part.count == 1 && after.count == 3, "one tiled (it fills) and three regular windows: they stay");
        part = DMSMFitTakingPart(@[@"i", @"g", @"e", @"a"], fill, [NSSet setWithArray:@[@"g", @"e"]], &after);
        CHECK([part isEqualToArray:(@[@"i", @"g", @"e", @"a"])] && after.count == 0, "room again (one tiled, two regular, a new one): all join, the new one first, the regular ones newest first (%s)", [part componentsJoinedByString:@" "].UTF8String);
        part = DMSMFitTakingPart(@[@"n2", @"n1", @"b", @"a"], halves, [NSSet set], &after);
        CHECK([part isEqualToArray:(@[@"n2", @"n1", @"b", @"a"])] && !after.count, "two new windows at once, two tiled: both join (as they opened, one after the other)");
        part = DMSMFitTakingPart(@[@"n2", @"n1", @"c", @"b", @"a"], closedUp, [NSSet set], &after);
        CHECK(part.count == 4 && [part containsObject:@"n1"] && ![part containsObject:@"n2"] && [after isEqualToSet:[NSSet setWithObject:@"n2"]], "two new windows at once, three tiled: the first one joins, the second is a regular window (before 1.8.0 the oldest tile went)");
        part = DMSMFitTakingPart(@[@"f", @"e", @"d", @"c", @"b", @"a"], nil, [NSSet set], &after);
        CHECK([part isEqualToArray:(@[@"f", @"e", @"d", @"c"])] && [after isEqualToSet:([NSSet setWithArray:@[@"b", @"a"]])], "a set nothing is known of (Fit switched on): the newest four, the rest regular windows (as DMTileOpenWindows)");
        part = DMSMFitTakingPart(@[@"a"], nil, [NSSet set], &after);
        CHECK([part isEqualToArray:@[@"a"]] && !after.count, "the first window: alone, not a regular window");
        part = DMSMFitTakingPart(@[@"b", @"a"], nil, [NSSet set], &after);
        CHECK([part isEqualToArray:(@[@"b", @"a"])], "  ... the second: both tiled");
        part = DMSMFitTakingPart(@[@"c", @"b"], halves, [NSSet setWithArray:@[@"x", @"e"]], &after);
        CHECK([after containsObject:@"x"] && [after containsObject:@"e"], "regular windows out of sight (minimized, another desktop) stay regular");
        part = DMSMFitTakingPart(@[@"a", @"b"], halves, [NSSet setWithObject:@"a"], &after);
        CHECK(part.count == 2 && ![after containsObject:@"a"], "a window with a tile is tiled, whatever else was noted of it");
        part = DMSMFitTakingPart(@[@"n", @"e", @"b", @"a"], halves, [NSSet setWithObject:@"e"], &after);
        plan = DMSMFitPlanDecide(halves, part, MSBDFitDefaultTiles(part.count), &how);
        CHECK([plan isEqualToDictionary:(@{@"n": @"topleft", @"e": @"topright", @"a": @"bottomleft", @"b": @"bottomright"})] && !after.count, "the halves, a regular window and a new one: the same plan as the other engines' (%s)", D(plan).UTF8String);

        // 3. both engines played as built
        for (int old = 0; old < 2; old++) {
            int differ = 0, events = 0, runs = old ? 300 : 3000, looseSeen = 0;
            NSString *firstDiff = nil;
            for (int run = 0; run < runs; run++) {
                NSMutableArray *open = [NSMutableArray array]; NSMutableSet *free = [NSMutableSet set];
                Desk d = { open, free };
                AerialModel *a = [AerialModel new]; SMModel *s = [SMModel new];
                a.old = old; s.old = old;
                int next = 0;
                NSMutableString *story = [NSMutableString string];
                for (int e = 0; e < 18; e++) {
                    BOOL opens = open.count < 2 || (open.count < 8 && Rnd(3) != 0);
                    if (opens) {
                        NSString *w = [NSString stringWithFormat:@"w%d", next++];
                        if (open.count >= 2 && Rnd(9) == 0) [free addObject:w];   // (now and then a No Fit window)
                        [open addObject:w];
                        [a open:w desk:d]; [s open:w desk:d];
                        [story appendFormat:@" +%@%@", w, [free containsObject:w] ? @"(No Fit)" : @""];
                    } else {
                        NSString *w = open[Rnd((unsigned)open.count)];
                        [open removeObject:w]; [free removeObject:w];
                        [a close:w desk:d]; [s close:w desk:d];
                        [story appendFormat:@" -%@", w];
                    }
                    events++;
                    NSDictionary *ta = [a tiles:d], *ts = [s tiles:d];
                    NSUInteger regular = 0; for (NSString *w in open) if (!ta[w] && ![free containsObject:w]) regular++;
                    if (regular && ta.count >= 2) looseSeen++;
                    if (![ta isEqualToDictionary:ts]) { differ++; if (!firstDiff) firstDiff = [NSString stringWithFormat:@"%@: Aerial %@ / Stage Manager %@", story, D(ta), D(ts)]; break; }
                }
            }
            printf("  %s: %d runs, %d events, %d with regular windows over the tiles, %d run(s) where the engines differ\n", old ? "before 1.8.0" : "as built", runs, events, looseSeen, differ);
            if (!old) {
                CHECK(differ == 0, "the engines as built: the same tiles after every event, %d runs, %d events (%d with regular windows over the tiles)%s%s", runs, events, looseSeen, firstDiff ? " -- first difference:" : "", firstDiff ? firstDiff.UTF8String : "");
                CHECK(looseSeen > 1000, "  ... the sweep has regular windows over the tiles (%d)", looseSeen);
            } else CHECK(differ > 0, "the rules before 1.8.0 (reference): they differ (%d of %d runs; first: %s)", differ, runs, firstDiff ? firstDiff.UTF8String : "none");
        }
        {   // the device story played on both engines, and on the old ones
            for (int old = 0; old < 2; old++) {
                NSMutableArray *open = [NSMutableArray array]; NSMutableSet *free = [NSMutableSet set];
                Desk d = { open, free };
                AerialModel *a = [AerialModel new]; SMModel *s = [SMModel new]; a.old = old; s.old = old;
                for (NSString *w in @[@"clock", @"tips", @"maps", @"cal", @"settings"]) { [open addObject:w]; [a open:w desk:d]; [s open:w desk:d]; }
                NSDictionary *fourA = [a tiles:d], *fourS = [s tiles:d];
                CHECK(fourA.count == 4 && !fourA[@"settings"] && [fourA isEqualToDictionary:fourS], "%s: five windows, four tiled, the fifth over them, on both engines (%s)", old ? "before 1.8.0" : "now", D(fourS).UTF8String);
                NSString *gone = @"maps";
                [open removeObject:gone]; [a close:gone desk:d]; [s close:gone desk:d];
                NSDictionary *ta = [a tiles:d], *ts = [s tiles:d];
                if (!old) CHECK([ta isEqualToDictionary:ts] && ta.count == 3 && !ts[@"settings"], "now: a tile closed -- the fifth stays where it is on both engines (Aerial %s / Stage Manager %s)", D(ta).UTF8String, D(ts).UTF8String);
                else CHECK(ts[@"settings"] && !ta[@"settings"], "before 1.8.0: Stage Manager pulled the fifth into the tiles, Aerial left it (Aerial %s / Stage Manager %s)", D(ta).UTF8String, D(ts).UTF8String);
            }
        }

        // 4. a turn
        CHECK(MSBDFitTileStaysAtTurn(YES, NO, NO, YES, NO), "a turn: a tiled window on screen keeps its tile");
        CHECK(MSBDFitTileStaysAtTurn(YES, NO, NO, NO, YES), "  ... a minimized one too (it comes back in its tile)");
        CHECK(!MSBDFitTileStaysAtTurn(NO, NO, NO, NO, NO), "  ... a window that has gone does not");
        CHECK(!MSBDFitTileStaysAtTurn(YES, YES, NO, YES, NO) && !MSBDFitTileStaysAtTurn(YES, YES, NO, NO, YES), "  ... nor one on its way out (closing, to full screen)");
        CHECK(!MSBDFitTileStaysAtTurn(YES, NO, YES, YES, NO) && !MSBDFitTileStaysAtTurn(YES, NO, YES, NO, YES), "  ... nor a No Fit one");
        CHECK(!MSBDFitTileStaysAtTurn(YES, NO, NO, NO, NO), "  ... nor one hidden but not minimized (a window still starting)");
        {   // the windows left after the turn with one of three minimized: the arrangement as it was (no close-up), as the Stage Manager engine's look
            NSDictionary *three = @{@"a": @"left", @"b": @"topright", @"m": @"bottomright"};
            NSMutableArray *group = [NSMutableArray array];
            for (NSString *w in @[@"a", @"b", @"m"]) if (MSBDFitTileStaysAtTurn(YES, NO, NO, ![w isEqualToString:@"m"], [w isEqualToString:@"m"])) [group addObject:w];
            CHECK(group.count == three.count, "the turn keeps the group whole: no close-up (%lu of 3)", (unsigned long)group.count);
            NSMutableArray *oldGroup = [NSMutableArray array];   // (before 1.8.0: the windows taking part, the minimized one out)
            for (NSString *w in @[@"a", @"b"]) [oldGroup addObject:w];
            NSDictionary *oldPlan2 = MSBDFitPlanKeepingPlaces(oldGroup, three);
            CHECK([oldPlan2 isEqualToDictionary:(@{@"a": @"left", @"b": @"right"})], "  (before 1.8.0 the two on screen closed up -- %s -- and the minimized one came back over them)", D(oldPlan2).UTF8String);
        }
        printf("test-fitloose: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
