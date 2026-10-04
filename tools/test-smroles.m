// Mac test of the Stage Manager engine's window roles and Fit to Window past four windows (sm-nolimit): statusbar/SMRoles.h (the window roles
// from SpringBoard's own role functions, or the engine's four) and statusbar/SMFitPlan.h (four tiles keep their places, later windows are regular
// windows over them). SpringBoard's role functions are played from the 16.7.7 disassembly (SBLayoutRoleIsValidForSplitView: (role - 1) < 10 and
// bit `role` of ~0xfffffc19 -- roles 1, 2, 5-9; constants Primary 1, Side 2, AdditionalSideRangeMin 5, Max 25, SBLayoutRoleMax 10); every
// variation that does not look like that keeps the engine's four. Run by test-smroles.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/SMRoles.h"
#include "../statusbar/SMFitPlan.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

// SBLayoutRoleIsValidForSplitView, 16.7.7 (0x1c5424230): sub x8, x0, #1; lsl w9, #1, w0; tst x9, #0xfffffc19; ccmp x8, #0xa ... -> cc
static BOOL SB1677(long long r) { unsigned long long x8 = (unsigned long long)(r - 1); unsigned int w9 = 1u << ((unsigned int)r & 31); return ((w9 & 0xfffffc19u) == 0) && x8 < 10; }
// variations
static BOOL SBAll(long long r) { return r >= 1 && r <= 30; }                       // (3 and 4 counted as window roles)
static BOOL SBNoSide(long long r) { return r == 1 || (r >= 5 && r <= 9); }          // (side not a window role)
static BOOL SBFive(long long r) { return r == 1 || r == 2 || r == 5; }              // (only one additional side)
static BOOL SBGap(long long r) { return r == 1 || r == 2 || r == 5 || r == 6 || r == 8 || r == 9; }   // (a gap at 7: stop there)
static BOOL SBWide(long long r) { return r == 1 || r == 2 || (r >= 5 && r <= 40); } // (a future iPadOS with more roles: capped by the constants and the table)

static NSString *Table(void) { return DMSMRolesText(); }

int main(void) {
    @autoreleasepool {
        NSString *why = nil;
        // 1. Before anything is set: the engine's four (1.3.5).
        CHECK(DMSMWindowCap() == 4 && [Table() isEqualToString:@"1, 2, 5, 6"] && !gDMSMRolesFromSB, "default table: %s", Table().UTF8String);
        CHECK(DMSMRoleTop() == 6, "default top role 6");

        // 2. 16.7.7 as disassembled: 1, 2, 5, 6, 7, 8, 9 -- seven windows; the top role read from a transition is 9.
        CHECK(DMSMRolesSetFrom(SB1677, 1, 2, 5, 25, 10, &why), "16.7.7 accepted (%s)", why.UTF8String);
        CHECK(DMSMWindowCap() == 7 && [Table() isEqualToString:@"1, 2, 5, 6, 7, 8, 9"] && gDMSMRolesFromSB, "16.7.7 table: %s", Table().UTF8String);
        CHECK(DMSMRoleTop() == 9, "16.7.7 top role 9 (%lld)", DMSMRoleTop());
        CHECK(DMSMIsWindowRole(1) && DMSMIsWindowRole(2) && !DMSMIsWindowRole(3) && !DMSMIsWindowRole(4) && DMSMIsWindowRole(9) && !DMSMIsWindowRole(10), "window roles 1, 2, 5-9 only");
        for (long long r = 0; r <= 12; r++) CHECK(SB1677(r) == (r == 1 || r == 2 || (r >= 5 && r <= 9)), "the played function: role %lld", r);
        // first free, in table order, added to a mutable set
        NSMutableSet *used = [NSMutableSet setWithArray:@[@1, @2, @5]];
        CHECK(DMSMFirstFreeRole(used) == 6 && [used containsObject:@6], "first free after 1, 2, 5: 6");
        CHECK(DMSMFirstFreeRole(used) == 7 && DMSMFirstFreeRole(used) == 8 && DMSMFirstFreeRole(used) == 9, "then 7, 8, 9");
        CHECK(DMSMFirstFreeRole(used) == 0, "then none (the stage is full: seven windows)");
        CHECK(DMSMFirstFreeRole([NSSet setWithArray:@[@1, @5]]) == 2, "an immutable set: the side role 2 first (and nothing added)");
        CHECK([[DMSMWindowRoleSet() allObjects] count] == 7, "the role set has seven roles");

        // 3. Anything that does not look like what the engine was built on: the four kept.
        struct { const char *name; DMSMRoleTestFn fn; long long p, s, amin, amax, rmax; } bad[] = {
            {"no function", NULL, 1, 2, 5, 25, 10},
            {"primary not 1", SB1677, 0, 2, 5, 25, 10},
            {"side not 2", SB1677, 1, 3, 5, 25, 10},
            {"additional sides not from 5", SB1677, 1, 2, 4, 25, 10},
            {"RangeMax too small", SB1677, 1, 2, 5, 5, 10},
            {"RoleMax too small", SB1677, 1, 2, 5, 25, 5},
            {"constants missing (-1)", SB1677, -1, -1, -1, -1, -1},
            {"floating/centre counted as windows", SBAll, 1, 2, 5, 25, 10},
            {"side not a window role", SBNoSide, 1, 2, 5, 25, 10},
            {"only one additional side", SBFive, 1, 2, 5, 25, 10},
        };
        for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
            DMSMRolesSetFrom(SB1677, 1, 2, 5, 25, 10, NULL);   // (from a good table each time: a refusal must go back to the four)
            BOOL ok = DMSMRolesSetFrom(bad[i].fn, bad[i].p, bad[i].s, bad[i].amin, bad[i].amax, bad[i].rmax, &why);
            CHECK(!ok && why.length && DMSMWindowCap() == 4 && [Table() isEqualToString:@"1, 2, 5, 6"] && !gDMSMRolesFromSB, "%s: refused, the four kept (%s; %s)", bad[i].name, why.UTF8String, Table().UTF8String);
        }
        // a gap: the table stops before it (contiguous from 5, as SpringBoard numbers items)
        CHECK(DMSMRolesSetFrom(SBGap, 1, 2, 5, 25, 10, &why) && [Table() isEqualToString:@"1, 2, 5, 6"], "a gap at 7: 1, 2, 5, 6 (%s)", Table().UTF8String);
        // a future iPadOS with more roles: capped by SBLayoutRoleMax / RangeMax and by the table's size
        CHECK(DMSMRolesSetFrom(SBWide, 1, 2, 5, 25, 10, &why) && DMSMWindowCap() == 8 && DMSMRoleTop() == 10, "wide, RoleMax 10: up to role 10 (%s)", Table().UTF8String);
        CHECK(DMSMRolesSetFrom(SBWide, 1, 2, 5, 12, 30, &why) && DMSMWindowCap() == 10 && DMSMRoleTop() == 12, "wide, RangeMax 12: up to role 12 (%s)", Table().UTF8String);
        CHECK(DMSMRolesSetFrom(SBWide, 1, 2, 5, 40, 40, &why) && DMSMWindowCap() == DMSM_ROLES_MAX, "wide, no limit in the constants: the table's %d (%zu)", DMSM_ROLES_MAX, DMSMWindowCap());
        DMSMRolesReset();
        CHECK(DMSMWindowCap() == 4 && !gDMSMRolesFromSB, "reset: the four");

        // 4. Fit to Window past four windows (SMFitPlan.h). defaults(n): the default slot names for MIN(4, n) windows, as DMDefaultSlotNames.
        NSArray *(^defaults)(NSUInteger) = ^NSArray *(NSUInteger n) {
            n = MIN((NSUInteger)4, n);
            return n == 2 ? @[@"left", @"right"] : (n == 3 ? @[@"left", @"topright", @"bottomright"] : (n >= 4 ? @[@"topleft", @"topright", @"bottomleft", @"bottomright"] : @[]));
        };
        int how = -1;
        NSDictionary *four = @{@"a": @"topleft", @"b": @"topright", @"c": @"bottomleft", @"d": @"bottomright"};
        // 4a. the chosen arrangement covering exactly these windows: kept
        NSDictionary *p = DMSMFitPlanDecide(four, @[@"d", @"c", @"b", @"a"], defaults(4), &how);
        CHECK(how == DMSMFitKept && [p isEqualToDictionary:four], "four tiles, the same four windows: kept");
        // 4b. a fifth (newest) and more: the four keep their places, the new ones are not in the plan
        for (int extra = 1; extra <= 3; extra++) {
            NSMutableArray *bs = [NSMutableArray array];
            for (int i = 0; i < extra; i++) [bs addObject:[NSString stringWithFormat:@"new%d", i]];
            [bs addObjectsFromArray:@[@"a", @"b", @"c", @"d"]];
            p = DMSMFitPlanDecide(four, bs, defaults(bs.count), &how);
            CHECK(how == DMSMFitFourKept && [p isEqualToDictionary:four], "%d window(s) past four tiles: the four keep their places (how %d)", extra, how);
            BOOL none = YES; for (int i = 0; i < extra; i++) if (p[bs[i]]) none = NO;
            CHECK(none, "%d window(s) past four tiles: none of them tiled", extra);
        }
        // 4c. one of the four closed with windows past them: the newest four tiled in the default arrangement
        p = DMSMFitPlanDecide(four, @[@"new0", @"new1", @"a", @"b", @"c"], defaults(5), &how);
        CHECK(how == DMSMFitDefault && p.count == 4 && [p[@"new0"] isEqualToString:@"topleft"] && [p[@"new1"] isEqualToString:@"topright"] && [p[@"a"] isEqualToString:@"bottomleft"] && [p[@"b"] isEqualToString:@"bottomright"] && !p[@"c"], "a tile closed: the newest four in the default arrangement");
        // 4d. the arrangements of fewer windows: unchanged rules (three tiles + a fourth = the quarters; nothing chosen = default)
        NSDictionary *three = @{@"a": @"left", @"b": @"topright", @"c": @"bottomright"};
        p = DMSMFitPlanDecide(three, @[@"x", @"a", @"b", @"c"], defaults(4), &how);
        CHECK(how == DMSMFitDefault && p.count == 4 && [p[@"x"] isEqualToString:@"topleft"], "three tiles and a fourth: the quarters, newest first (as before)");
        p = DMSMFitPlanDecide(nil, @[@"x", @"y"], defaults(2), &how);
        CHECK(how == DMSMFitDefault && [p isEqualToDictionary:(@{@"x": @"left", @"y": @"right"})], "nothing chosen, two windows: halves");
        p = DMSMFitPlanDecide(three, @[@"a", @"b", @"c"], defaults(3), &how);
        CHECK(how == DMSMFitKept && [p isEqualToDictionary:three], "three tiles, the same three: kept");
        p = DMSMFitPlanDecide(nil, @[@"1", @"2", @"3", @"4", @"5", @"6", @"7"], defaults(7), &how);
        CHECK(how == DMSMFitDefault && p.count == 4 && !p[@"5"] && !p[@"7"], "seven windows, nothing chosen (Fit switched on): the newest four tiled, the others left");
        // 4e. random sweep: never more than four tiles, slots unique, a kept arrangement never loses a window that is still open
        srandom(7);
        NSArray *names = @[@"topleft", @"topright", @"bottomleft", @"bottomright"];
        for (int n = 0; n < 20000; n++) {
            int nb = 2 + (int)(random() % 6);
            NSMutableArray *bs = [NSMutableArray array];
            for (int i = 0; i < nb; i++) [bs addObject:[NSString stringWithFormat:@"w%d", (int)(random() % 9)]];
            NSOrderedSet *uniq = [NSOrderedSet orderedSetWithArray:bs];
            bs = [[uniq array] mutableCopy];
            if (bs.count < 2) continue;
            NSMutableDictionary *slots = nil;
            if (random() % 3) {
                slots = [NSMutableDictionary dictionary];
                int ns = 2 + (int)(random() % 3);
                for (int i = 0; i < ns; i++) slots[[NSString stringWithFormat:@"w%d", (int)(random() % 9)]] = names[i];
            }
            p = DMSMFitPlanDecide(slots, bs, defaults(bs.count), &how);
            CHECK(p.count <= 4 && [[NSSet setWithArray:p.allValues] count] == p.count, "sweep %d: at most four tiles, each slot once", n);
            if (how == DMSMFitFourKept) {
                BOOL ok = slots.count >= 4 && bs.count > slots.count;
                for (NSString *b in slots) if (![bs containsObject:b]) ok = NO;
                CHECK(ok && [p isEqualToDictionary:slots], "sweep %d: four kept only with four open tiles and more windows", n);
            }
            if (how == DMSMFitDefault) for (NSString *b in p) CHECK([bs indexOfObject:b] < 4, "sweep %d: the default arrangement tiles the newest", n);
        }
        // 7. The arrangement remembered per desktop (SMFitPlan.h DMSMFitSlotsFor, 1.3.6 logic test L-7): a stage of its own on screen in between
        //    replaced the one global arrangement; back on the desktop the default was laid out for the four newest and buried the rest.
        {
            NSDictionary *deskTiles = @{@"a": @"topleft", @"b": @"topright", @"c": @"bottomleft", @"d": @"bottomright"};
            NSArray *desk7 = @[@"g", @"f", @"e", @"d", @"c", @"b", @"a"];
            NSDictionary *memory = @{DMSMFitDeskKey(desk7): deskTiles};
            NSDictionary *other = @{@"x": @"left", @"y": @"right"};   // (another stage's arrangement replaced the current one)
            CHECK(DMSMFitSlotsFor(other, memory, desk7) == deskTiles, "back on the 7-window desktop: its own four tiles again");
            int how = -1; DMSMFitPlanDecide(DMSMFitSlotsFor(other, memory, desk7), desk7, defaults(4), &how);
            CHECK(how == DMSMFitFourKept, "and the four tiles are kept (nothing re-tiled): how %d", how);
            CHECK(DMSMFitSlotsFor(deskTiles, @{}, desk7) == deskTiles, "current slots that still cover the windows: kept as they are");
            CHECK(DMSMFitSlotsFor(other, @{}, desk7) == other, "nothing remembered: the current slots (the default follows)");
            CHECK(DMSMFitSlotsFor(other, memory, @[@"a", @"b", @"c"]) == other, "another set of windows: not this desktop's memory");
            CHECK([DMSMFitDeskKey(@[@"b", @"a"]) isEqualToString:DMSMFitDeskKey(@[@"a", @"b"])], "the key does not depend on the order");
            NSDictionary *two = @{@"x": @"left", @"y": @"right"};
            CHECK(DMSMFitSlotsFor(two, @{DMSMFitDeskKey(@[@"x", @"y"]): @{@"x": @"right", @"y": @"left"}}, @[@"y", @"x"]) == two, "covered by the current slots: the memory is not asked");
        }
        printf("test-smroles: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
