// Mac test of the Mac Switcher's desktops per display (statusbar/MSWDisplays.h, 1.8.7 commit 14; plans/design-1.8.7-displays.md section 7): the model,
// the ids of another display's desktops, the desktops file version 2 and what 1.8.6's loader makes of it, the 8 remembered displays and Forget
// This Display. Run by test-mswdisplays.sh (with the sites in the code as built).
#import <Foundation/Foundation.h>
#include "../statusbar/MSWDisplays.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
#define TV @"u-4C2D0372-0000-0000-0120-0103808E5078"
#define TV2 @"u-14803875-6ED1-428A-B223-8B1C4562A66C"
#define CLOCK @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default"
#define TIPS @"com.apple.tips|sceneID:com.apple.tips-default"
#define NOTES @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default"

// 1.8.6's DMMSWLoad and DMMSWSave (becbdeba, MacSwitcher.h:820-845 and 802-818), the parts that decide what is kept: its desktops, its current one,
// the records on them; what it writes back.
static NSDictionary *V1LoadSave(NSDictionary *st) {
    NSMutableArray *desks = [NSMutableArray arrayWithObject:@1]; NSUInteger cur = 0;
    NSMutableDictionary *win = [NSMutableDictionary dictionary], *fr = [NSMutableDictionary dictionary], *fsd = [NSMutableDictionary dictionary];
    NSArray *ids = st[@"desktops"];
    if ([ids isKindOfClass:[NSArray class]]) for (id n in ids) if ([n isKindOfClass:[NSNumber class]] && [n integerValue] > 1 && ![desks containsObject:n] && desks.count < 8) [desks addObject:@([n integerValue])];
    NSNumber *c = st[@"current"];
    NSUInteger i = [c isKindOfClass:[NSNumber class]] ? [desks indexOfObject:@(c.integerValue)] : NSNotFound;
    cur = i == NSNotFound ? 0 : i;
    NSDictionary *w = st[@"windows"], *f = st[@"frames"], *fs = st[@"fullscreen"];
    if ([w isKindOfClass:[NSDictionary class]]) for (id k in w) if ([k isKindOfClass:[NSString class]] && [w[k] isKindOfClass:[NSNumber class]] && [desks containsObject:w[k]]) win[k] = w[k];
    if ([f isKindOfClass:[NSDictionary class]]) for (id k in f) if ([k isKindOfClass:[NSString class]] && [f[k] isKindOfClass:[NSString class]]) fr[k] = f[k];
    if ([fs isKindOfClass:[NSDictionary class]]) for (id k in fs) if ([k isKindOfClass:[NSString class]] && [fs[k] isKindOfClass:[NSString class]] && [desks containsObject:@([k integerValue])]) fsd[k] = fs[k];
    return @{@"desktops": desks, @"current": desks[cur], @"windows": win, @"frames": fr, @"fullscreen": fsd, @"leftSizes": @{}, @"fit": @{}};
}
// This build's DMMSWSave (MacSwitcher.h): version 1's keys from the iPad's model, the records flat, version 2's keys.
static NSMutableDictionary *V2Save(DMMSWModel *main, NSDictionary *displays, NSInteger next, NSDictionary *windows, NSDictionary *fullscreen) {
    NSMutableDictionary *st = [@{@"desktops": [main->desks copy] ?: @[@1], @"current": @(MSWDispCurId(main)), @"windows": windows ?: @{}, @"frames": @{}, @"fullscreen": fullscreen ?: @{},
                                 @"leftSizes": @{}, @"fit": @{}} mutableCopy];
    MSWDispWrite(st, displays, next);
    return st;
}

int main(void) {
    @autoreleasepool {
        // 1. A version 1 file (1.8.6's): the iPad's desktops and current one exactly as 1.8.6 read them; no other display; the next id 1001.
        NSDictionary *v1 = @{@"desktops": @[@1, @2, @3], @"current": @3, @"windows": @{CLOCK: @1, TIPS: @3}, @"frames": @{}, @"fullscreen": @{@"2": @"com.apple.Maps"}};
        DMMSWModel *main = [DMMSWModel new];
        NSMutableDictionary<NSString *, DMMSWModel *> *ds = [NSMutableDictionary dictionary];
        NSInteger next = 0;
        MSWDispRead(v1, 8, main, ds, &next);
        CHECK([main->desks isEqualToArray:(@[@1, @2, @3])] && main->cur == 2 && [main.key isEqualToString:@"main"], "v1: the iPad's desktops %s cur %lu", main->desks.description.UTF8String, (unsigned long)main->cur);
        CHECK(ds.count == 0 && next == 1001, "v1: no other display, next id 1001 (%ld)", (long)next);
        CHECK(MSWDispCurId(main) == 3, "v1: current id 3");
        // the same read as 1.8.6's own (its loader is the reference for the iPad's part)
        NSDictionary *ref = V1LoadSave(v1);
        CHECK([ref[@"desktops"] isEqualToArray:main->desks] && [ref[@"current"] integerValue] == MSWDispCurId(main), "v1: as 1.8.6 read it");
        // 2. Saved again: every version 1 key is there with the same content, plus version 2's.
        NSMutableDictionary *saved = V2Save(main, ds, next, v1[@"windows"], v1[@"fullscreen"]);
        for (NSString *k in @[@"desktops", @"current", @"windows", @"frames", @"fullscreen", @"leftSizes", @"fit"]) CHECK(saved[k] != nil, "save: version 1 key %s kept", k.UTF8String);
        CHECK([saved[@"desktops"] isEqualToArray:v1[@"desktops"]] && [saved[@"current"] isEqual:v1[@"current"]] && [saved[@"windows"] isEqualToDictionary:v1[@"windows"]], "save: the iPad's part equal to version 1's");
        CHECK([saved[@"version"] isEqual:@2] && [saved[@"nextDesk"] isEqual:@1001] && [saved[@"displays"] isEqualToDictionary:@{}], "save: version 2's keys (version %s next %s)", [saved[@"version"] description].UTF8String, [saved[@"nextDesk"] description].UTF8String);
        // 3. Another display: its first desktop 1001, never an iPad id; a second one 1002; the 9th of a display refused.
        DMMSWModel *tv = MSWDispNewModel(TV, MSWDispAllIds(main, ds), &next, 100.0);
        CHECK(tv && [tv->desks isEqualToArray:@[@1001]] && tv->cur == 0 && next == 1002 && [tv.key isEqualToString:TV], "TV: first desktop 1001, next 1002 (%ld)", (long)next);
        ds[TV] = tv;
        CHECK(MSWDispNewDesk(tv, MSWDispAllIds(main, ds), &next, 8) == 1002 && next == 1003, "TV: second desktop 1002");
        while (tv->desks.count < 8) MSWDispNewDesk(tv, MSWDispAllIds(main, ds), &next, 8);
        CHECK(tv->desks.count == 8 && MSWDispNewDesk(tv, MSWDispAllIds(main, ds), &next, 8) == 0, "TV: 8 desktops at most per display");
        CHECK(MSWDispNewModel(@"main", MSWDispAllIds(main, ds), &next, 0) == nil && MSWDispNewModel(@"u-abc", MSWDispAllIds(main, ds), &next, 0) == nil && ({ NSInteger scratch = next; MSWDispNewModel(@"any", MSWDispAllIds(main, ds), &scratch, 0) != nil; }),
              "a model only for a display key: not main, not a lower-case id; any yes");
        // ids: above 1000 and above every id, and never one used before (a removed desktop's id is not given again)
        CHECK(MSWDispNextId([NSSet setWithArray:@[@1, @2, @9]], 0) == 1001, "next id: 1001 above the iPad's");
        CHECK(MSWDispNextId([NSSet setWithArray:@[@1, @1003]], 1001) == 1004, "next id: above the highest");
        CHECK(MSWDispNextId([NSSet setWithArray:@[@1]], 1010) == 1010, "next id: nextDesk only grows (1005-1009 used and removed)");
        [tv->desks removeLastObject];
        NSInteger again = MSWDispNewDesk(tv, MSWDispAllIds(main, ds), &next, 8);
        CHECK(again == 1009 && next == 1010, "a removed desktop's id is not given again (%ld)", (long)again);
        // 4. Owners.
        CHECK(MSWDispOwner(@2, main, ds) == main && MSWDispOwner(@1001, main, ds) == tv && MSWDispOwner(@1008, main, ds) == nil && MSWDispOwner(@77, main, ds) == nil && MSWDispOwner(nil, main, ds) == nil, "owners");
        // 5. Round trip of version 2: written, read back the same.
        tv->cur = 2;
        NSMutableDictionary *v2 = V2Save(main, ds, next, @{CLOCK: @1, TIPS: @1002, NOTES: @1003}, @{@"2": @"com.apple.Maps", @"1003": @"com.apple.mobilesafari"});
        DMMSWModel *main2 = [DMMSWModel new];
        NSMutableDictionary<NSString *, DMMSWModel *> *ds2 = [NSMutableDictionary dictionary];
        NSInteger next2 = 0;
        MSWDispRead(v2, 8, main2, ds2, &next2);
        CHECK([main2->desks isEqualToArray:main->desks] && main2->cur == main->cur, "v2: the iPad's back");
        CHECK(ds2.count == 1 && [ds2[TV]->desks isEqualToArray:tv->desks] && ds2[TV]->cur == 2 && ds2[TV].lastSeen == 100.0 && next2 == next, "v2: the TV's back (next %ld/%ld)", (long)next2, (long)next);
        CHECK(MSWDispDeskKnown(@1002, main2, ds2) && MSWDispDeskKnown(@3, main2, ds2) && !MSWDispDeskKnown(@1010, main2, ds2), "v2: a record's desktop known by any model");
        // 6. 1.8.6's loader on a version 2 file: the iPad's desktops, current one and records on them as written; the TV's records dropped; its save
        //    drops "displays" (a downgrade loses only the TV's desktops).
        NSDictionary *down = V1LoadSave(v2);
        CHECK([down[@"desktops"] isEqualToArray:main->desks] && [down[@"current"] integerValue] == MSWDispCurId(main), "1.8.6 on v2: the iPad's desktops and current");
        CHECK([down[@"windows"] isEqualToDictionary:@{CLOCK: @1}], "1.8.6 on v2: only the iPad's records (%s)", [down[@"windows"] description].UTF8String);
        CHECK([down[@"fullscreen"] isEqualToDictionary:@{@"2": @"com.apple.Maps"}], "1.8.6 on v2: only the iPad's full-screen apps");
        CHECK(!down[@"displays"] && !down[@"version"], "1.8.6's save: no displays");
        // ... and this build reading that back: the iPad's as they were, no TV, ids still above 1000
        MSWDispRead(down, 8, main2, ds2, &next2);
        CHECK(ds2.count == 0 && [main2->desks isEqualToArray:main->desks] && next2 == 1001, "upgrade again: no TV desktops, next 1001");
        // 7. What is read: bad keys, iPad-range ids, an id two displays claim, an empty display, at most 8 displays (the ones used last).
        NSDictionary *bad = @{@"desktops": @[@1, @2], @"current": @2, @"nextDesk": @1003, @"displays": @{
            @"main": @{@"desktops": @[@1004]}, @"u-abc": @{@"desktops": @[@1005]}, @"nonsense": @{@"desktops": @[@1006]},
            TV: @{@"desktops": @[@1001, @2, @1001, @999, @1002], @"current": @1002, @"lastSeen": @50},
            TV2: @{@"desktops": @[@1002, @1003], @"current": @7, @"lastSeen": @60},
            @"any": @{@"desktops": @[]}, @"u-AAAA": @"not a dictionary"}};
        MSWDispRead(bad, 8, main2, ds2, &next2);
        CHECK(ds2.count == 2 && ds2[TV] && ds2[TV2], "read: only valid keys with desktops (%lu)", (unsigned long)ds2.count);
        // (keys in sorted order: TV2's "u-1480..." before the TV's "u-4C2D...")
        CHECK([ds2[TV2]->desks isEqualToArray:(@[@1002, @1003])] && ds2[TV2]->cur == 0, "read: a current id it has not: Desktop 1 (%s cur %lu)", ds2[TV2]->desks.description.UTF8String, (unsigned long)ds2[TV2]->cur);
        CHECK([ds2[TV]->desks isEqualToArray:@[@1001]] && ds2[TV]->cur == 0, "read: ids above 1000, no repeat, none another display has (%s cur %lu)", ds2[TV]->desks.description.UTF8String, (unsigned long)ds2[TV]->cur);
        CHECK(next2 == 1004, "read: next id above every id and nextDesk (%ld)", (long)next2);
        NSMutableDictionary *many = [NSMutableDictionary dictionary];
        for (int k = 0; k < 10; k++) many[[NSString stringWithFormat:@"u-%04d-AAAA", k]] = @{@"desktops": @[@(1001 + k)], @"lastSeen": @(k)};
        MSWDispRead(@{@"displays": many}, 8, main2, ds2, &next2);
        CHECK(ds2.count == 8 && !ds2[@"u-0000-AAAA"] && !ds2[@"u-0001-AAAA"] && ds2[@"u-0009-AAAA"] && next2 == 1011, "read: at most 8 displays, the ones used last (%lu)", (unsigned long)ds2.count);
        // the 9th made now: the one used longest ago goes, never the one in use
        ds2[@"u-0010-AAAA"] = MSWDispNewModel(@"u-0010-AAAA", MSWDispAllIds(main2, ds2), &next2, 1.0);
        NSArray *gone = MSWDispTrim(ds2, @"u-0010-AAAA", 8, nil);
        CHECK(gone.count == 1 && [gone[0] isEqualToString:@"u-0002-AAAA"] && ds2[@"u-0010-AAAA"], "the 9th display: the one used longest ago forgotten (%s), not the new one", [gone.description UTF8String]);
        CHECK(MSWDispTrim(ds2, nil, 8, nil).count == 0, "trim: nothing at 8");
        // (review of 1.8.7: a display with desktops of its own -- two or more, or a window record on one -- goes only when every one has; over the
        //  Lightning AV adapter each replug is a new id, so by age alone the TV set up with its desktops went before 7 plain copies of it)
        NSMutableDictionary<NSString *, DMMSWModel *> *ds3 = [NSMutableDictionary dictionary];
        NSInteger next3 = 1001;
        for (int k = 0; k < 9; k++) ds3[[NSString stringWithFormat:@"u-%04d-BBBB", k]] = MSWDispNewModel([NSString stringWithFormat:@"u-%04d-BBBB", k], MSWDispAllIds(main2, ds3), &next3, 10.0 + k);
        MSWDispNewDesk(ds3[@"u-0000-BBBB"], MSWDispAllIds(main2, ds3), &next3, 8);   // (the oldest: two desktops)
        CHECK(MSWDispBusy(ds3[@"u-0000-BBBB"], nil) && !MSWDispBusy(ds3[@"u-0001-BBBB"], nil) && !MSWDispBusy(nil, nil), "busy: two desktops; one empty desktop is plain");
        gone = MSWDispTrim(ds3, @"u-0008-BBBB", 8, nil);
        CHECK(gone.count == 1 && [gone[0] isEqualToString:@"u-0001-BBBB"] && ds3[@"u-0000-BBBB"], "trim: a display with two desktops (used longest ago) kept, the oldest plain one goes (%s)", gone.description.UTF8String);
        ds3[@"u-0009-BBBB"] = MSWDispNewModel(@"u-0009-BBBB", MSWDispAllIds(main2, ds3), &next3, 30.0);
        NSDictionary *recs = @{CLOCK: ds3[@"u-0002-BBBB"]->desks.firstObject, TIPS: @1, NOTES: @"not an id"};
        CHECK(MSWDispBusy(ds3[@"u-0002-BBBB"], recs) && !MSWDispBusy(ds3[@"u-0003-BBBB"], recs), "busy: one desktop with a window record on it; another model's record or the iPad's is not its own");
        gone = MSWDispTrim(ds3, @"u-0009-BBBB", 8, recs);
        CHECK(gone.count == 1 && [gone[0] isEqualToString:@"u-0003-BBBB"] && ds3[@"u-0002-BBBB"], "trim: a display with a window record kept, the next plain one goes (%s)", gone.description.UTF8String);
        NSMutableDictionary<NSString *, DMMSWModel *> *ds4 = [NSMutableDictionary dictionary];
        for (int k = 0; k < 9; k++) { NSString *key = [NSString stringWithFormat:@"u-%04d-CCCC", k]; ds4[key] = MSWDispNewModel(key, MSWDispAllIds(main2, ds4), &next3, 10.0 + k); MSWDispNewDesk(ds4[key], MSWDispAllIds(main2, ds4), &next3, 8); }
        gone = MSWDispTrim(ds4, @"u-0000-CCCC", 8, nil);
        CHECK(gone.count == 1 && [gone[0] isEqualToString:@"u-0001-CCCC"] && ds4[@"u-0000-CCCC"], "trim: every one with desktops of its own: the one used longest ago goes, never the one in use (%s)", gone.description.UTF8String);
        NSMutableDictionary *many3 = [NSMutableDictionary dictionary];
        for (int k = 0; k < 9; k++) many3[[NSString stringWithFormat:@"u-%04d-DDDD", k]] = @{@"desktops": k == 0 ? @[@(2001), @(2002)] : k == 1 ? @[@(2003)] : @[@(2010 + k)], @"lastSeen": @(k)};
        MSWDispRead(@{@"displays": many3, @"windows": @{CLOCK: @2003}}, 8, main2, ds2, &next2);
        CHECK(ds2.count == 8 && ds2[@"u-0000-DDDD"] && ds2[@"u-0001-DDDD"] && !ds2[@"u-0002-DDDD"], "read: over 8, the file's two desktops and its window record kept, the oldest plain one goes (%lu)", (unsigned long)ds2.count);
        // 8. Forget This Display: its model, its records and its desktops' entries go; the iPad's and the other display's stay.
        MSWDispRead(v2, 8, main2, ds2, &next2);
        DMMSWModel *other = MSWDispNewModel(TV2, MSWDispAllIds(main2, ds2), &next2, 5.0);
        ds2[TV2] = other;
        NSMutableDictionary *win = [@{CLOCK: @1, TIPS: @1002, NOTES: other->desks.firstObject} mutableCopy], *fr = [@{TIPS: @"{{0,0},{10,10}}", CLOCK: @"{{1,1},{5,5}}"} mutableCopy];
        NSMutableDictionary *fsd = [@{@"2": @"com.apple.Maps", @"1003": @"com.apple.mobilesafari"} mutableCopy], *fit = [@{@"1001": @{}, @"1": @{}} mutableCopy];
        NSArray *ids = MSWDispForget(ds2, TV, win, fr, @[fsd, fit]);
        CHECK(ids.count == 8 && [ids containsObject:@1001] && !ds2[TV] && ds2[TV2], "forget: the TV's model (ids %s)", ids.description.UTF8String);
        CHECK([win isEqualToDictionary:(@{CLOCK: @1, NOTES: other->desks.firstObject})] && [fr isEqualToDictionary:@{CLOCK: @"{{1,1},{5,5}}"}], "forget: its records only");
        CHECK([fsd isEqualToDictionary:@{@"2": @"com.apple.Maps"}] && [fit isEqualToDictionary:@{@"1": @{}}], "forget: its desktops' entries only");
        CHECK(MSWDispForget(ds2, TV, win, fr, @[]) == nil && MSWDispForget(ds2, nil, win, fr, @[]) == nil, "forget: a display not remembered: nothing");
        // 10. Part 2 (commit 15): a window that goes to the other display, and an unplug. A display's tick (MacSwitcherSM.h DMMSWSMApply, as Tick() below):
        //     a window in the stage the display shows whose record is not one of its desktops joins its current desktop; a record of its own (or, on
        //     the iPad, of no model) is forgotten when its window is in no stage of that display; another model's record is that model's tick's.
        {
            DMMSWModel *ip = [DMMSWModel new], *tvm = nil;
            NSMutableDictionary<NSString *, DMMSWModel *> *dd = [NSMutableDictionary dictionary];
            NSInteger nx = 0;
            MSWDispRead(@{@"desktops": @[@1, @2], @"current": @2}, 8, ip, dd, &nx);
            tvm = MSWDispNewModel(TV, MSWDispAllIds(ip, dd), &nx, 1.0); dd[TV] = tvm;
            MSWDispNewDesk(tvm, MSWDispAllIds(ip, dd), &nx, 8); tvm->cur = 1;   // (the TV on its Desktop 2, id 1002)
            NSMutableDictionary<NSString *, NSNumber *> *rec = [@{CLOCK: @2, TIPS: @1002, NOTES: @77} mutableCopy];
            // Tick: shown = the windows in the stage the display shows; alive = the windows in any of its stages
            void (^Tick)(DMMSWModel *, NSArray *, NSArray *) = ^(DMMSWModel *m, NSArray *shown, NSArray *alive) {
                for (NSString *k in shown) { NSNumber *d = rec[k]; if (!d || ![m->desks containsObject:d]) rec[k] = @(MSWDispCurId(m)); }
                for (NSString *k in [rec.allKeys copy]) if (MSWDispRecordFate(rec[k], m, ip, dd, [alive containsObject:k]) == MSWDispFateForget) [rec removeObjectForKey:k];
            };
            CHECK(MSWDispRecordFate(@1002, ip, ip, dd, NO) == MSWDispFateNotMine && MSWDispRecordFate(@2, tvm, ip, dd, NO) == MSWDispFateNotMine, "fate: another display's record is not mine (both ways)");
            CHECK(MSWDispRecordFate(@77, ip, ip, dd, NO) == MSWDispFateForget && MSWDispRecordFate(@77, tvm, ip, dd, NO) == MSWDispFateNotMine, "fate: a stale record is the iPad's tick's (as 1.8.6 forgot it)");
            CHECK(MSWDispRecordFate(@2, ip, ip, dd, YES) == MSWDispFateKeep && MSWDispRecordFate(@1002, tvm, ip, dd, NO) == MSWDispFateForget, "fate: its own kept while there, forgotten when gone");
            // the TV's own window stays: the iPad's tick never forgets it, also while it shows nothing of the TV
            Tick(ip, @[CLOCK], @[CLOCK]);
            CHECK([rec[TIPS] isEqual:@1002] && [rec[CLOCK] isEqual:@2] && !rec[NOTES], "the iPad's tick leaves the TV's window alone (and forgets a stale one)");
            Tick(tvm, @[TIPS], @[TIPS]);
            CHECK([rec[TIPS] isEqual:@1002] && [rec[CLOCK] isEqual:@2], "the TV's tick leaves the iPad's window alone");
            // Move to Other Display (Clock, iPad -> TV): either tick first, it ends on the TV's current desktop and the iPad keeps no record of it
            NSDictionary *before = [rec copy];
            Tick(ip, @[], @[]); Tick(tvm, @[TIPS, CLOCK], @[TIPS, CLOCK]);
            CHECK([rec[CLOCK] isEqual:@1002] && [rec[TIPS] isEqual:@1002], "Move to Other Display, the iPad's tick first: Clock on the TV's current desktop (%s)", [rec[CLOCK] description].UTF8String);
            [rec setDictionary:before];
            Tick(tvm, @[TIPS, CLOCK], @[TIPS, CLOCK]); Tick(ip, @[], @[]);
            CHECK([rec[CLOCK] isEqual:@1002], "Move to Other Display, the TV's tick first: the same (%s)", [rec[CLOCK] description].UTF8String);
            // ... the iPad's current desktop unchanged by it
            CHECK(MSWDispCurId(ip) == 2 && MSWDispCurId(tvm) == 1002, "a window to the TV leaves the iPad's current desktop");
            // an unplug: the TV's windows go where Stage Manager puts them (the iPad's stage in front) and join the iPad's current desktop; the TV's model stays
            Tick(ip, @[CLOCK, TIPS], @[CLOCK, TIPS]);
            CHECK([rec[CLOCK] isEqual:@2] && [rec[TIPS] isEqual:@2] && dd[TV] && tvm->desks.count == 2, "unplug: its windows join the iPad's current desktop, its desktops kept");
            // a TV switch: its current desktop moves, the iPad's does not (separate models); the file writes each
            tvm->cur = 0;
            NSMutableDictionary *f = V2Save(ip, dd, nx, rec, @{});
            CHECK([f[@"current"] isEqual:@2] && [f[@"displays"][TV][@"current"] isEqual:@1001], "a TV switch leaves the iPad's current desktop (file: %s / %s)", [f[@"current"] description].UTF8String, [f[@"displays"][TV][@"current"] description].UTF8String);
        }
        // 11. Commit 16: the display the keys act on -- a session's, else the keyboard focus's, else the pointer's last, else the iPad.
        CHECK(!MSWDispKeysOnOther(-1, 1, 10, 10, NO), "keys: no other display -> the iPad");
        CHECK(MSWDispKeysOnOther(1, 0, 0, 10, YES) && !MSWDispKeysOnOther(0, 1, 10, 10, YES), "keys: a session's display first (the TV's view open: the TV, whatever the focus)");
        CHECK(MSWDispKeysOnOther(-1, 1, 0, 10, YES) && !MSWDispKeysOnOther(-1, 0, 10, 10, YES), "keys: then the keyboard focus's display (over the pointer)");
        CHECK(MSWDispKeysOnOther(-1, -1, 10, 10, YES) && !MSWDispKeysOnOther(-1, -1, 9, 10, YES), "keys: then the pointer's last display (its last hover was there)");
        CHECK(!MSWDispKeysOnOther(-1, -1, 0, 0, YES) && !MSWDispKeysOnOther(-1, -1, 0, 5, YES), "keys: else the iPad (no hover, or last on the iPad)");
        // 12. Review: whose desktops Control-Left / Right switch -- the keys' display's with two or more, else (between sessions) the iPad's with two or more, else none.
        CHECK(MSWDispArrowsOn(YES, YES, 2, 1) == 1 && MSWDispArrowsOn(YES, YES, 3, 3) == 1, "arrows: the keys' other display with two desktops: its own");
        CHECK(MSWDispArrowsOn(YES, YES, 1, 2) == 0 && MSWDispArrowsOn(YES, YES, 0, 2) == 0, "arrows: focus or pointer on a TV with one desktop (or none yet), the iPad with two: the iPad's, as 1.8.6");
        CHECK(MSWDispArrowsOn(YES, YES, 1, 1) == -1 && MSWDispArrowsOn(YES, YES, 0, 0) == -1, "arrows: one desktop on both: none (the app's keys)");
        CHECK(MSWDispArrowsOn(NO, YES, 2, 1) == -1 && MSWDispArrowsOn(NO, NO, 2, 1) == -1, "arrows: the keys on the iPad with one desktop, the TV with two: none (the app's keys)");
        CHECK(MSWDispArrowsOn(NO, YES, 0, 2) == 0 && MSWDispArrowsOn(NO, NO, 0, 3) == 0, "arrows: the keys on the iPad with two: the iPad's");
        CHECK(MSWDispArrowsOn(YES, NO, 1, 2) == -1 && MSWDispArrowsOn(YES, NO, 2, 1) == 1, "arrows: a session on the TV: its desktops or none, never the iPad's under it");
        // 9. Bad input.
        MSWDispRead((NSDictionary *)@[@1], 8, main2, ds2, &next2);
        CHECK([main2->desks isEqualToArray:@[@1]] && main2->cur == 0 && ds2.count == 0 && next2 == 1001, "read: not a dictionary -> one desktop");
        MSWDispRead(nil, 8, main2, ds2, &next2);
        CHECK([main2->desks isEqualToArray:@[@1]] && ds2.count == 0, "read: no file -> one desktop");
        CHECK(MSWDispCurId(nil) == 1 && MSWDispCurId(main2) == 1, "current id of the iPad with nothing: 1");
    }
    printf("test-mswdisplays: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
