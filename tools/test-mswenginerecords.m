// Mac test of the Mac Switcher's window records across an engine change (statusbar/MSWEngineRecords.h): Stage Manager -> Zetsu -> Stage Manager keeps every
// window's record, so its windows come back on their desktops (A12Z, re-check of 1.8.1: the current desktop was empty, its windows off the screen in their
// stages, published 1.8.0.1 the same); the apps get a copy once per stay; Zetsu -> Stage Manager -> Zetsu brings its windows' records back from aside, only
// for the windows it saved. Run by test-mswenginerecords.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/MSWEngineRecords.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static NSString *K(NSString *b, NSString *s) { return [NSString stringWithFormat:@"%@|sceneID:%@-%@", b, b, s]; }
#define SPOTIFY @"com.spotify.client"
#define CLOCK @"com.apple.mobiletimer"
#define TIPS @"com.apple.tips"
#define SETTINGS @"com.apple.Preferences"

// One tick of an engine of windows by app, its rule for closed windows included: what MacSwitcher.h DMMSWApply does with the records.
static void OtherEngineTick(NSMutableDictionary *windows, NSMutableDictionary *frames, BOOL *copied, NSInteger cur, NSSet *alive) {
    if (!*copied && MSWRecordsCopyToApps(windows, frames)) *copied = YES;
    for (NSString *k in windows.allKeys) if (MSWRecordClosedHere(k, [windows[k] integerValue], cur, alive)) { [windows removeObjectForKey:k]; [frames removeObjectForKey:k]; }
}
// Stage Manager's tick: the first of a start puts the file's app records aside, then adoption by the stages' windows, then the check of the records whose window is in no
// stage (MacSwitcherSM.h DMMSWSMApply).
static void SMTickNext(NSMutableDictionary *windows, NSMutableDictionary *frames, NSMutableDictionary *aside, NSMutableDictionary *asideFrames, NSArray *stageKeys, BOOL first) {
    if (first) MSWRecordsPutAside(windows, frames, aside, asideFrames);
    NSMutableSet *alive = [NSMutableSet setWithArray:stageKeys], *aliveApps = [NSMutableSet set];
    for (NSString *k in stageKeys) [aliveApps addObject:DMSMKeyBundle(k)];
    for (NSString *k in stageKeys) if (!windows[k] && windows[DMSMKeyBundle(k)]) windows[k] = windows[DMSMKeyBundle(k)];
    for (NSString *k in windows.allKeys) {
        if ([alive containsObject:k]) continue;
        MSWSMRecordFateOf(k, YES, aliveApps);
        [windows removeObjectForKey:k]; [frames removeObjectForKey:k];
    }
}
static void SMTick(NSMutableDictionary *windows, NSMutableDictionary *frames, NSMutableDictionary *aside, NSMutableDictionary *asideFrames, NSArray *stageKeys) {
    SMTickNext(windows, frames, aside, asideFrames, stageKeys, YES);
}

int main(void) {
    @autoreleasepool {
        NSString *spot = K(SPOTIFY, @"default"), *clock = K(CLOCK, @"default"), *tips = K(TIPS, @"default"), *clock2 = K(CLOCK, @"ABC");
        // ---- the report: one window on the current desktop, Stage Manager -> Zetsu -> Stage Manager ----
        NSMutableDictionary *w = [@{spot: @1} mutableCopy], *f = [NSMutableDictionary dictionary];
        BOOL copied = NO;
        OtherEngineTick(w, f, &copied, 1, [NSSet set]);
        CHECK(copied, "the stay on Zetsu noted");
        CHECK([w[spot] isEqual:@1], "KT's window keeps its record on Zetsu, on the current desktop");
        CHECK(!w[SPOTIFY], "its app's copy on the current desktop is forgotten: no Zetsu window (as before)");
        for (int i = 0; i < 3; i++) OtherEngineTick(w, f, &copied, 1, [NSSet set]);
        CHECK(w.count == 1 && [w[spot] isEqual:@1] && !w[SPOTIFY], "later ticks and starts change nothing, and the copy is not made again: %s", w.description.UTF8String);
        NSMutableDictionary *aside = [NSMutableDictionary dictionary], *af = [NSMutableDictionary dictionary];
        SMTick(w, f, aside, af, @[spot]);
        CHECK([w isEqual:@{spot: @1}] && !aside.count, "back on Stage Manager: the record as it was, nothing put aside: %s", w.description.UTF8String);

        // ---- the test apps' run: current Desktop 2 with two windows, KT's on Desktop 1 ----
        w = [@{spot: @1, clock: @2, tips: @2} mutableCopy]; f = [@{spot: @"{{150, 49}, {1065, 819}}"} mutableCopy]; copied = NO;
        OtherEngineTick(w, f, &copied, 2, [NSSet set]);
        CHECK([w[spot] isEqual:@1] && [w[clock] isEqual:@2] && [w[tips] isEqual:@2], "every window keeps its record");
        CHECK([w[SPOTIFY] isEqual:@1] && [f[SPOTIFY] isEqual:f[spot]], "another desktop's window: its app's copy stays, with its frame (it opens as a window when that desktop comes, as before)");
        CHECK(!w[CLOCK] && !w[TIPS], "the current desktop's: their apps' copies are forgotten at once, as before");
        aside = [NSMutableDictionary dictionary]; af = [NSMutableDictionary dictionary];
        SMTick(w, f, aside, af, @[spot, clock]);   // (a stage of two is cut back to its primary when Stage Manager goes off: Tips has no stage)
        CHECK([w[spot] isEqual:@1] && [w[clock] isEqual:@2], "Stage Manager again: the windows in stages on their desktops");
        CHECK(!w[tips], "a window in no stage any more is forgotten");
        CHECK(!w[SPOTIFY], "the app's copy leaves the records: its window has its own");
        CHECK([aside isEqual:@{SPOTIFY: @1}], "the app's copy is put aside: a window record never is: %s", aside.description.UTF8String);

        // ---- a Zetsu window of an app with a Stage Manager window: each engine its own ----
        w = [@{clock: @1} mutableCopy]; f = [NSMutableDictionary dictionary]; copied = NO;
        OtherEngineTick(w, f, &copied, 1, [NSSet setWithObject:CLOCK]);
        CHECK([w[CLOCK] isEqual:@1], "its app's copy stays with a window here");
        w[CLOCK] = @2;   // (moved to Desktop 2 on Zetsu)
        OtherEngineTick(w, f, &copied, 1, [NSSet setWithObject:CLOCK]);
        CHECK([w[clock] isEqual:@1] && [w[CLOCK] isEqual:@2], "moved on Zetsu: its Stage Manager window's record does not follow");
        aside = [NSMutableDictionary dictionary]; af = [NSMutableDictionary dictionary];
        SMTick(w, f, aside, af, @[clock]);
        CHECK([w isEqual:@{clock: @1}], "back: the Stage Manager window on its own desktop");
        CHECK([aside isEqual:@{CLOCK: @2}], "... and the Zetsu window's record aside for Zetsu, on its own desktop");

        // ---- two windows of one app on two desktops ----
        NSMutableDictionary *two = [@{clock: @1, clock2: @2} mutableCopy], *twoF = [NSMutableDictionary dictionary];
        CHECK(MSWRecordsCopyToApps(two, twoF) == 2, "two window records");
        NSString *first = [clock compare:clock2] == NSOrderedAscending ? clock : clock2;
        CHECK([two[CLOCK] isEqual:two[first]], "the app's copy: the first by key, the same on every run");
        CHECK([two[clock] isEqual:@1] && [two[clock2] isEqual:@2], "each window keeps its own desktop");
        CHECK(MSWRecordsCopyToApps(two, twoF) == 2 && [two[CLOCK] isEqual:two[first]], "a record the app has stays");
        NSMutableDictionary *none = [@{CLOCK: @2} mutableCopy];
        CHECK(MSWRecordsCopyToApps(none, twoF) == 0, "only apps' records: nothing to do");

        // ---- the rule for closed windows ----
        NSSet *here = [NSSet setWithObject:TIPS];
        CHECK(MSWRecordClosedHere(CLOCK, 1, 1, here), "an app with no window here, current desktop: closed");
        CHECK(!MSWRecordClosedHere(TIPS, 1, 1, here), "an app with a window here: no");
        CHECK(!MSWRecordClosedHere(CLOCK, 2, 1, here), "another desktop's: no (it comes back with its desktop)");
        CHECK(!MSWRecordClosedHere(clock, 1, 1, here), "a Stage Manager window's key: never");

        // ---- Stage Manager's check ----
        NSSet *apps = [NSSet setWithObject:CLOCK];
        CHECK(MSWSMRecordFateOf(CLOCK, YES, apps) == MSWSMRecordTaken, "an app's record, the app with a window in a stage: it goes");
        CHECK(MSWSMRecordFateOf(TIPS, YES, apps) == MSWSMRecordClosed, "... with no window in a stage: forgotten");
        CHECK(MSWSMRecordFateOf(tips, YES, apps) == MSWSMRecordClosed, "a window's record: closed");
        CHECK(MSWSMRecordFateOf(TIPS, NO, apps) == MSWSMRecordClosed, "windows known by app: an app's record with no window: closed");
        CHECK(MSWSMRecordFateOf(clock, NO, apps) == MSWSMRecordToApp, "windows known by app: a window's record goes to its app's");
        CHECK(MSWSMRecordFateOf(tips, NO, apps) == MSWSMRecordClosed, "... with no window of the app: closed");

        // ---- Zetsu -> Stage Manager -> Zetsu ----
        w = [@{CLOCK: @2, TIPS: @1} mutableCopy]; f = [@{CLOCK: @"{{1, 2}, {3, 4}}"} mutableCopy];
        aside = [NSMutableDictionary dictionary]; af = [NSMutableDictionary dictionary];
        SMTick(w, f, aside, af, @[]);
        CHECK((!w.count && [aside isEqual:(@{CLOCK: @2, TIPS: @1})] && [af[CLOCK] isEqual:@"{{1, 2}, {3, 4}}"]), "Stage Manager: Zetsu's windows are put aside, not forgotten: %s", aside.description.UTF8String);
        NSUInteger n = MSWRecordsFromAside(w, f, aside, af, @[CLOCK, TIPS, SETTINGS], @[@1, @2]);
        CHECK(n == 2 && [w[CLOCK] isEqual:@2] && [w[TIPS] isEqual:@1] && [f[CLOCK] isEqual:@"{{1, 2}, {3, 4}}"] && !w[SETTINGS], "back on Zetsu: its saved windows on their desktops");
        w = [@{TIPS: @2} mutableCopy]; f = [NSMutableDictionary dictionary];
        n = MSWRecordsFromAside(w, f, aside, af, @[TIPS], @[@1, @2]);
        CHECK(n == 0 && [w[TIPS] isEqual:@2], "a record the app has by now stays");
        w = [NSMutableDictionary dictionary];
        n = MSWRecordsFromAside(w, f, aside, af, @[CLOCK], @[@1]);
        CHECK(n == 0 && !w.count, "a desktop that is gone: it joins the current one, as a new window");
        n = MSWRecordsFromAside(w, f, aside, af, @[], @[@1, @2]);
        CHECK(n == 0 && !w.count, "a window not in the saved state: it does not come back with a record");

        // ---- Stage Manager's own launch records (code review 1.8.1.1, finding 1) ----
        // A: Zetsu's Clock on Desktop 3, then Stage Manager; Clock has no scene yet and is opened on Desktop 1
        w = [@{CLOCK: @3} mutableCopy]; f = [@{CLOCK: @"{{1, 2}, {3, 4}}"} mutableCopy];
        aside = [NSMutableDictionary dictionary]; af = [NSMutableDictionary dictionary];
        SMTickNext(w, f, aside, af, @[], YES);
        CHECK((!w.count && [aside isEqual:@{CLOCK: @3}]), "A: the first tick: Zetsu's window aside, on its desktop");
        w[CLOCK] = @1;   // (DMMSWSMJoin: a launch by app, before its scene)
        SMTickNext(w, f, aside, af, @[], NO);
        CHECK((!w.count && [aside isEqual:@{CLOCK: @3}]), "A: its launch's record before the scene comes: forgotten when no window comes, nothing aside: %s", aside.description.UTF8String);
        w[CLOCK] = @1;
        SMTickNext(w, f, aside, af, @[clock], NO);
        CHECK(([w isEqual:@{clock: @1}] && [aside isEqual:@{CLOCK: @3}]), "A: the scene comes: its own record on Desktop 1, Zetsu's still 3");
        w = [NSMutableDictionary dictionary]; f = [NSMutableDictionary dictionary];
        n = MSWRecordsFromAside(w, f, aside, af, @[CLOCK], @[@1, @2, @3]);
        CHECK(n == 1 && [w[CLOCK] isEqual:@3], "A: back on Zetsu: Clock on Desktop 3");
        // B: a launch on Stage Manager, the window then moved; nothing of it aside for a later Zetsu
        w = [NSMutableDictionary dictionary]; f = [NSMutableDictionary dictionary]; aside = [NSMutableDictionary dictionary]; af = [NSMutableDictionary dictionary];
        SMTickNext(w, f, aside, af, @[], YES);
        w[CLOCK] = @1;
        SMTickNext(w, f, aside, af, @[clock], NO);
        w[clock] = @2;
        CHECK((!aside.count && [w isEqual:@{clock: @2}]), "B: launched and moved: its own record only, nothing aside: %s", aside.description.UTF8String);
        // C: never changing engine
        w = [@{clock: @1, spot: @2} mutableCopy]; f = [NSMutableDictionary dictionary]; aside = [NSMutableDictionary dictionary]; af = [NSMutableDictionary dictionary];
        SMTickNext(w, f, aside, af, @[clock, spot], YES);
        w[TIPS] = @1;
        SMTickNext(w, f, aside, af, @[clock, spot, tips], NO);
        CHECK(!aside.count, "C: never changing engine: nothing aside, whatever is launched: %s", aside.description.UTF8String);
        // an entry already aside stays: no such engine has run since
        aside = [@{CLOCK: @3} mutableCopy]; af = [NSMutableDictionary dictionary];
        NSDictionary *fileNow = @{CLOCK: @1, TIPS: @2};
        CHECK(MSWRecordsPutAside(fileNow, @{}, aside, af) == 1 && [aside[CLOCK] isEqual:@3] && [aside[TIPS] isEqual:@2], "an entry already aside stays, a new one comes");
        CHECK(MSWRecordsPutAside(@{clock: @1}, @{}, aside, af) == 0, "a window's record is never put aside");

        // ---- a window of the engine that runs (a desktop's window set, the Dock's running dot; code review 1.8.1.1, finding 3) ----
        CHECK(!MSWRecordIsWindowHere(clock, YES), "on Zetsu a Stage Manager window's record is no window here");
        CHECK(MSWRecordIsWindowHere(CLOCK, YES), "on Zetsu an app's record is");
        CHECK(MSWRecordIsWindowHere(clock, NO) && MSWRecordIsWindowHere(CLOCK, NO), "on Stage Manager, or with no such engine, both count");

        // ---- the records right before a restore (code review 1.8.1.1, finding 2): what was aside first, then the apps' copies ----
        w = [@{clock: @2, tips: @3} mutableCopy]; f = [NSMutableDictionary dictionary]; aside = [@{TIPS: @1} mutableCopy]; af = [NSMutableDictionary dictionary];
        MSWRecordsFromAside(w, f, aside, af, @[CLOCK, TIPS], @[@1, @2, @3]);
        MSWRecordsCopyToApps(w, f);
        CHECK([w[CLOCK] isEqual:@2], "a saved window with nothing aside: its window key's desktop, before its window is made (first change after an update)");
        CHECK([w[TIPS] isEqual:@1], "a saved window with a record aside: that one, its Stage Manager window's stays apart: %s", w.description.UTF8String);
        CHECK([w[clock] isEqual:@2] && [w[tips] isEqual:@3], "the window keys as they were");

        // ---- what is aside, read from the desktops file or the kept copy (code review 1.8.1.1, finding 4) ----
        NSMutableDictionary *ra = [NSMutableDictionary dictionary], *rf = [NSMutableDictionary dictionary];
        MSWAsideRead(@{@"asideWindows": @{CLOCK: @2}, @"asideFrames": @{CLOCK: @"{{1, 2}, {3, 4}}"}}, ra, rf);
        CHECK([ra isEqual:@{CLOCK: @2}] && [rf[CLOCK] isEqual:@"{{1, 2}, {3, 4}}"], "kept while the Mac Switcher was off: back as it was");
        ra = [NSMutableDictionary dictionary]; rf = [NSMutableDictionary dictionary];
        MSWAsideRead(@{@"asideWindows": @"no", @"asideFrames": @[]}, ra, rf);
        MSWAsideRead(@{@"asideWindows": @{@"x": @"not a number", @"y": @{}}, @"asideFrames": @{@"x": @1}}, ra, rf);
        MSWAsideRead(@{}, ra, rf);
        CHECK(!ra.count && !rf.count, "bad input, or none: nothing");
        NSMutableDictionary *wa = [NSMutableDictionary dictionary], *fa = [NSMutableDictionary dictionary];
        MSWAsideRead(@{@"asideWindows": @{CLOCK: @2, TIPS: @5}}, ra, rf);
        CHECK(MSWRecordsFromAside(wa, fa, ra, rf, @[CLOCK, TIPS], @[@1, @2]) == 1 && [wa isEqual:@{CLOCK: @2}], "after the off and on, Zetsu's restore: Clock on its desktop, a desktop that is gone left out");

        // ---- as built ----
        NSString *header = [NSString stringWithContentsOfFile:@"../statusbar/MacSwitcher.h" encoding:NSUTF8StringEncoding error:nil];
        NSRange fold = [header rangeOfString:@"static void DMMSWFoldWindowKeys(void) {"];
        CHECK(fold.location != NSNotFound, "as built: DMMSWFoldWindowKeys is there");
        NSString *body = fold.location == NSNotFound ? @"" : [header substringWithRange:NSMakeRange(fold.location, MIN((NSUInteger)500, header.length - fold.location))];
        CHECK([body rangeOfString:@"MSWRecordsCopyToApps(gMSWWinDesk, gMSWWinFrame)"].location != NSNotFound && [body rangeOfString:@"removeObjectForKey"].location == NSNotFound, "as built: the fold copies, it takes no record away");
        NSString *smh = [NSString stringWithContentsOfFile:@"../statusbar/MacSwitcherSM.h" encoding:NSUTF8StringEncoding error:nil];
        NSRange once = [smh rangeOfString:@"static BOOL asideDone = NO;"], putAside = [smh rangeOfString:@"MSWRecordsPutAside(gMSWWinDesk, gMSWWinFrame, gMSWAsideDesk, gMSWAsideFrame)"];
        CHECK(once.location != NSNotFound && putAside.location != NSNotFound && putAside.location > once.location && putAside.location - once.location < 200, "as built: the file's app records go aside once per start");
        CHECK([smh rangeOfString:@"gMSWAsideDesk[k] ="].location == NSNotFound, "as built: the tick's check puts nothing aside");
        NSRange keep = [header rangeOfString:@"static void DMMSWKeepForLater(void) {"], back = [header rangeOfString:@"static void DMMSWBringBack(void) {"];
        NSString *keepBody = keep.location == NSNotFound || back.location == NSNotFound || back.location < keep.location ? @"" : [header substringWithRange:NSMakeRange(keep.location, back.location - keep.location)];
        NSString *backBody = back.location == NSNotFound ? @"" : [header substringWithRange:NSMakeRange(back.location, MIN((NSUInteger)6000, header.length - back.location))];
        CHECK([keepBody rangeOfString:@"st[@\"asideWindows\"] = [gMSWAsideDesk copy]"].location != NSNotFound, "as built: what is aside is kept with the desktops at the off");
        CHECK([backBody rangeOfString:@"MSWAsideRead(st, gMSWAsideDesk, gMSWAsideFrame)"].location != NSNotFound, "as built: and back at the on");
        NSRange before = [header rangeOfString:@"void DMMSWRecordsBeforeRestore(NSArray<NSString *> *savedApps) {"];
        NSString *beforeBody = before.location == NSNotFound ? @"" : [header substringWithRange:NSMakeRange(before.location, MIN((NSUInteger)800, header.length - before.location))];
        NSRange fromAside = [beforeBody rangeOfString:@"MSWRecordsFromAside("], copies = [beforeBody rangeOfString:@"DMMSWFoldWindowKeys();"];
        CHECK(fromAside.location != NSNotFound && copies.location != NSNotFound && fromAside.location < copies.location, "as built: before a restore, what was aside, then the copies");
        NSString *sbx = [NSString stringWithContentsOfFile:@"../statusbar/StatusBar.x" encoding:NSUTF8StringEncoding error:nil];
        CHECK([sbx rangeOfString:@"gMSWWinDesk[k].integerValue != cur && MSWRecordIsWindowHere(k, appsOnly)) [out addObject:b]"].location != NSNotFound, "as built: the Dock's dots of windows away leave a Stage Manager window's record out on such an engine");
        CHECK([sbx rangeOfString:@"DMMSWRecordsBeforeRestore(savedApps);"].location != NSNotFound && [sbx rangeOfString:@"DMMSWRecordsBeforeRestore(nil);"].location != NSNotFound, "as built: DMRestoreWindows asks for them");
    }
    printf("%d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
