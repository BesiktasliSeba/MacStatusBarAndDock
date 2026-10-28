// Mac test of the Mac Switcher's desktops kept while it is off (statusbar/MSWKept.h, 1.5.2 item 14): what comes back when it is on again.
// Aerial / Zetsu / MilkyWay4 (records by app) and Stage Manager (records by window, a desktop = a stage): every kept desktop and window comes
// back; a window closed or an app quit meanwhile is left out, and another desktop's full-screen app the user quit (logic test L1) -- a quit by
// the prewarm quit set and the app gone now, never "not running" alone (a respring or memory while off: recheck R1); a window the user made full
// screen with green while off (the kept copy's "madeFullScreen") is no window any more, and running or not decides nothing -- a prewarmed or
// background-launched app keeps its window (R3 as the coordinator decided it, 1.6.0); nothing when what is there
// can't be told yet; a new window goes to Desktop 1 -- with
// Stage Manager to the desktop of the kept windows it joined; the current desktop (Desktop 1, or the stage on screen's); the desktop on screen
// keeps its own full-screen app and Fit arrangement; screen sizes when left; an engine change meanwhile; bad input. Run by test-mswkept.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/MSWKept.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSString *K(NSString *b, NSString *s) { return [NSString stringWithFormat:@"%@|sceneID:%@-%@", b, b, s]; }
#define TIPS @"com.apple.tips"
#define CLOCK @"com.apple.mobiletimer"
#define CALC @"com.apple.calculator"
#define WEATHER @"com.apple.weather"
#define MAPS @"com.apple.Maps"
#define NOTES @"com.apple.mobilenotes"
static NSString *const kScreen = @"{1024, 1366}";

static NSDictionary *BackQuit(NSDictionary *kept, BOOL sm, BOOL told, NSArray *alive, NSArray<NSArray *> *stages, NSUInteger front, NSArray *minimized, NSArray *apps, NSArray *running, NSArray *quit) {
    NSMutableSet *keys = [NSMutableSet set], *byApp = [NSMutableSet set];
    for (NSString *k in alive) { [keys addObject:k]; [byApp addObject:DMSMKeyBundle(k)]; }
    return MSWKeptBringBack(kept, sm, told, keys, byApp, stages ?: @[], front, minimized ?: @[], apps ?: @[], running ? [NSSet setWithArray:running] : nil,
                            quit ? [NSSet setWithArray:quit] : nil, kScreen, 8);
}
static NSDictionary *Back(NSDictionary *kept, BOOL sm, BOOL told, NSArray *alive, NSArray<NSArray *> *stages, NSUInteger front, NSArray *minimized, NSArray *apps) {
    return BackQuit(kept, sm, told, alive, stages, front, minimized, apps, nil, @[]);   // (the quit set read, empty)
}

int main(void) {
    @autoreleasepool {
        // ---- Aerial / Zetsu / MilkyWay4: records by app ----
        NSDictionary *fitA = @{@"group": @[TIPS], @"slots": @{TIPS: @"fill"}, @"free": @[], @"fitOn": @YES}, *fitB = @{@"group": @[CLOCK], @"slots": @{}, @"free": @[], @"fitOn": @YES};
        NSDictionary *fitC = @{@"group": @[], @"slots": @{}, @"free": @[CALC], @"fitOn": @NO};
        NSDictionary *keptW = @{@"desktops": @[@1, @2, @3], @"current": @2, @"windows": @{TIPS: @1, CLOCK: @2, CALC: @3},
                                @"frames": @{CLOCK: @"{{10, 20}, {500, 400}}", CALC: @"{{30, 40}, {300, 500}}"},
                                @"fullscreen": @{@"1": NOTES, @"2": MAPS}, @"leftSizes": @{@"1": @"{1366, 1024}", @"3": @"{1366, 1024}"},
                                @"fit": @{@"1": fitA, @"2": fitB, @"3": fitC}};
        // 1. All there, one new window: every desktop and window back, the new one on Desktop 1, Desktop 1 current.
        NSDictionary *r = Back(keptW, NO, YES, @[TIPS, CLOCK, CALC, WEATHER], nil, NSNotFound, nil, @[TIPS, CLOCK, CALC, WEATHER]);
        CHECK([r[@"desktops"] isEqualToArray:(@[@1, @2, @3])], "W1 desktops %s", [[r[@"desktops"] description] UTF8String]);
        CHECK([r[@"current"] integerValue] == 0, "W1 current %ld", (long)[r[@"current"] integerValue]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CLOCK: @2, CALC: @3, WEATHER: @1})], "W1 windows %s", [[r[@"windows"] description] UTF8String]);
        CHECK([r[@"fresh"] isEqualToDictionary:(@{WEATHER: @1})], "W1 fresh");
        CHECK([r[@"gone"] count] == 0 && [r[@"back"] integerValue] == 3, "W1 gone/back");
        CHECK([r[@"frames"] isEqualToDictionary:(@{CLOCK: @"{{10, 20}, {500, 400}}", CALC: @"{{30, 40}, {300, 500}}"})], "W1 frames");
        // the desktop on screen (Desktop 1) keeps what it shows: not its kept full-screen app nor its kept tiles; the others' come back
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"2": MAPS})], "W1 fullscreen %s", [[r[@"fullscreen"] description] UTF8String]);
        CHECK([r[@"fit"] isEqualToDictionary:(@{@"2": fitB, @"3": fitC})], "W1 fit");
        // every window was on screen while off: the other desktops were left at the screen as it is now
        CHECK([r[@"leftSizes"] isEqualToDictionary:(@{@"2": kScreen, @"3": kScreen})], "W1 leftSizes %s", [[r[@"leftSizes"] description] UTF8String]);

        // 2. Calculator quit meanwhile (on the quit set, no window now): left out, its desktop stays (empty).
        r = BackQuit(keptW, NO, YES, @[TIPS, CLOCK], nil, NSNotFound, nil, @[TIPS, CLOCK], @[TIPS, CLOCK], @[CALC]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CLOCK: @2})], "W2 windows %s", [[r[@"windows"] description] UTF8String]);
        CHECK([r[@"gone"] isEqualToArray:(@[CALC])] && [r[@"back"] integerValue] == 2, "W2 gone %s", [[r[@"gone"] description] UTF8String]);
        CHECK([r[@"desktops"] isEqualToArray:(@[@1, @2, @3])], "W2 desktops (an emptied desktop stays)");
        CHECK(r[@"frames"][CALC] == nil, "W2 the quit app's frame goes");

        // 3. Too soon to tell (just after a start): every kept window back even without a window yet.
        r = Back(keptW, NO, NO, @[], nil, NSNotFound, nil, @[TIPS]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CLOCK: @2, CALC: @3})], "W3 windows %s", [[r[@"windows"] description] UTF8String]);
        CHECK([r[@"gone"] count] == 0 && [r[@"fresh"] count] == 0, "W3 nothing gone, nothing new");

        // 4. Engine change while off (Stage Manager window keys kept, Aerial now): an app's window counts by its app; it is not "new".
        NSDictionary *keptSMtoW = @{@"desktops": @[@1, @2], @"windows": @{K(TIPS, @"A"): @1, K(CLOCK, @"B"): @2}};
        r = Back(keptSMtoW, NO, YES, @[TIPS, CLOCK], nil, NSNotFound, nil, @[TIPS, CLOCK]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{K(TIPS, @"A"): @1, K(CLOCK, @"B"): @2})] && [r[@"fresh"] count] == 0, "W4 windows %s", [[r[@"windows"] description] UTF8String]);

        // 4b. Logic test L1: another desktop's full-screen app the user quit meanwhile -- from iPadOS's App Switcher, which the tweak does not see:
        //     on the quit set, not running -- is left out, so going to that desktop does not launch it again; the desktop on screen's is never taken.
        NSDictionary *keptFS = @{@"desktops": @[@1, @2, @3], @"windows": @{TIPS: @1}, @"fullscreen": @{@"1": NOTES, @"2": MAPS, @"3": WEATHER}};
        r = BackQuit(keptFS, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS], @[MAPS, NOTES]);
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"3": WEATHER})], "W4b fullscreen %s", [[r[@"fullscreen"] description] UTF8String]);
        CHECK([r[@"gone"] isEqualToArray:(@[MAPS])], "W4b gone %s", [[r[@"gone"] description] UTF8String]);
        CHECK([r[@"desktops"] isEqualToArray:(@[@1, @2, @3])], "W4b desktops (the desktop stays)");
        // 4r. Recheck R1: off, a respring, on -- nothing runs after a respring, nothing was quit: every full-screen app stays, its desktop opens it.
        r = BackQuit(keptFS, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[], @[]);
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"2": MAPS, @"3": WEATHER})] && [r[@"gone"] count] == 0, "W4r respring %s", [[r[@"fullscreen"] description] UTF8String]);
        // ... memory pressure (Maps ended by iPadOS, not quit): the same
        r = BackQuit(keptFS, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS, WEATHER], @[]);
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"2": MAPS, @"3": WEATHER})], "W4r2 memory %s", [[r[@"fullscreen"] description] UTF8String]);
        // ... on the quit set but running now (opened again by a way that did not take it off the set): kept
        r = BackQuit(keptFS, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[MAPS], @[MAPS]);
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"2": MAPS, @"3": WEATHER})], "W4r3 quit but running %s", [[r[@"fullscreen"] description] UTF8String]);
        // ... the quit set not known (nil): kept, whatever runs; not told: kept; running not known but on the quit set: out
        r = BackQuit(keptFS, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[], nil);
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"2": MAPS, @"3": WEATHER})] && [r[@"gone"] count] == 0, "W4c quit set unknown %s", [[r[@"fullscreen"] description] UTF8String]);
        r = BackQuit(keptFS, NO, NO, @[], nil, NSNotFound, nil, @[], @[], @[MAPS]);
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"2": MAPS, @"3": WEATHER})] && [r[@"gone"] count] == 0, "W4c2 not told %s", [[r[@"fullscreen"] description] UTF8String]);
        r = BackQuit(keptFS, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], nil, @[MAPS]);
        CHECK([r[@"fullscreen"] isEqualToDictionary:(@{@"3": WEATHER})], "W4d running unknown %s", [[r[@"fullscreen"] description] UTF8String]);
        // ... an app gone both ways (its window record and another desktop's full screen) is named once
        r = BackQuit(@{@"desktops": @[@1, @2, @3], @"windows": @{MAPS: @3}, @"fullscreen": @{@"2": MAPS}}, NO, YES, @[], nil, NSNotFound, nil, @[], @[], @[MAPS]);
        CHECK([r[@"gone"] isEqualToArray:(@[MAPS])] && [r[@"fullscreen"] count] == 0, "W4e gone once %s", [[r[@"gone"] description] UTF8String]);
        // ... Stage Manager alike for an entry (its full-screen app is a window of its stage, an entry is rare)
        r = BackQuit(@{@"desktops": @[@1, @2], @"fullscreen": @{@"2": MAPS}}, YES, YES, @[], @[], NSNotFound, nil, nil, @[], @[MAPS]);
        CHECK([r[@"fullscreen"] count] == 0 && [r[@"gone"] isEqualToArray:(@[MAPS])], "W4f Stage Manager %s", [[r[@"gone"] description] UTF8String]);
        // 4w. Recheck R1 for windows (Aerial / Zetsu / MilkyWay4): an away window whose app iPadOS ended (memory, a respring) has no window now but
        //     was not quit: kept, its desktop opens it again (DMMSWRelaunchClosed); one the user quit (quit set) and gone: out; the set unknown: kept.
        r = BackQuit(keptW, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS], @[]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CLOCK: @2, CALC: @3})] && [r[@"gone"] count] == 0, "W4w not quit %s", [[r[@"windows"] description] UTF8String]);
        r = BackQuit(keptW, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS], @[CLOCK]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CALC: @3})] && [r[@"gone"] isEqualToArray:(@[CLOCK])], "W4w2 quit %s", [[r[@"windows"] description] UTF8String]);
        r = BackQuit(keptW, NO, YES, @[TIPS, CLOCK], nil, NSNotFound, nil, @[TIPS, CLOCK], @[TIPS, CLOCK], @[CLOCK]);
        CHECK([r[@"windows"][CLOCK] isEqual:@2], "W4w3 on the quit set but with a window now: kept");
        r = BackQuit(keptW, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS], nil);
        CHECK([r[@"windows"] count] == 3, "W4w4 the quit set unknown: kept");
        // 4x. Recheck R3, as the coordinator decided it (1.6.0): "made full screen with green while off" is a fact of its own in the kept copy
        //     ("madeFullScreen", MacSwitcher.h DMMSWKeptMadeFullScreen), never inferred from "running without a window". Out: no window now and the
        //     user quit it (the quit set) or made it full screen. Running or not decides nothing.
        NSMutableDictionary *keptWF = [keptW mutableCopy]; keptWF[@"madeFullScreen"] = @[CLOCK];
        // made full screen while off, still running (full screen): out -- not relaunched as a window on its desktop
        r = BackQuit(keptWF, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS, CLOCK], @[]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CALC: @3})] && [r[@"gone"] isEqualToArray:(@[CLOCK])], "W4x made full screen, running: left out %s", [[r[@"windows"] description] UTF8String]);
        // ... and after a respring while off (not running now): the record is in the kept file, still out
        r = BackQuit(keptWF, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS], @[]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CALC: @3})] && [r[@"gone"] isEqualToArray:(@[CLOCK])], "W4x2 made full screen, a respring since: left out %s", [[r[@"windows"] description] UTF8String]);
        // ... the running apps or the quit set not known: the record alone says it
        r = BackQuit(keptWF, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], nil, nil);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CALC: @3})] && [r[@"gone"] isEqualToArray:(@[CLOCK])], "W4x3 made full screen, nothing else known: left out %s", [[r[@"windows"] description] UTF8String]);
        // ... but with a window now (back in a window by a way that left the record): kept, on its desktop
        r = BackQuit(keptWF, NO, YES, @[TIPS, CLOCK], nil, NSNotFound, nil, @[TIPS, CLOCK], @[TIPS, CLOCK], @[]);
        CHECK([r[@"windows"][CLOCK] isEqual:@2] && [r[@"gone"] count] == 0, "W4x4 made full screen, a window now: kept %s", [[r[@"windows"] description] UTF8String]);
        // ... not told (the windows not back yet after a start): kept, as everything else
        r = BackQuit(keptWF, NO, NO, @[], nil, NSNotFound, nil, @[], @[], @[]);
        CHECK([r[@"windows"] count] == 3 && [r[@"gone"] count] == 0, "W4x5 made full screen, not told: kept %s", [[r[@"windows"] description] UTF8String]);
        // prewarmed / background-launched while off (running, no window, neither quit nor made full screen): kept -- its desktop opens it
        r = BackQuit(keptW, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS, CLOCK], @[]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CLOCK: @2, CALC: @3})] && [r[@"gone"] count] == 0, "W4x6 background-launched: kept %s", [[r[@"windows"] description] UTF8String]);
        // ... the running apps not known: the same
        r = BackQuit(keptW, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], nil, @[]);
        CHECK([r[@"windows"] count] == 3 && [r[@"gone"] count] == 0, "W4x7 running not known, nothing recorded: kept %s", [[r[@"windows"] description] UTF8String]);
        // quit (on the quit set) and running again without a window (a background launch after the quit): out, the quit decides
        r = BackQuit(keptW, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS, CLOCK], @[CLOCK]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CALC: @3})] && [r[@"gone"] isEqualToArray:(@[CLOCK])], "W4x8 quit, then running in the background: left out %s", [[r[@"windows"] description] UTF8String]);
        // ... quit, the running apps not known: out (R1's rule, whatever runs)
        r = BackQuit(keptW, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], nil, @[CLOCK]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1, CALC: @3})] && [r[@"gone"] isEqualToArray:(@[CLOCK])], "W4x9 quit, running not known: left out %s", [[r[@"windows"] description] UTF8String]);
        // an app both quit and made full screen is named once
        keptWF[@"madeFullScreen"] = @[CLOCK, CALC];
        r = BackQuit(keptWF, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS], @[CLOCK]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @1})] && [r[@"gone"] count] == 2 && [r[@"gone"] containsObject:CLOCK] && [r[@"gone"] containsObject:CALC], "W4x10 quit and made full screen: each once %s", [[r[@"gone"] description] UTF8String]);
        // a bad record (not a list, or not names): read as none
        keptWF[@"madeFullScreen"] = @"com.apple.mobiletimer";
        r = BackQuit(keptWF, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS, CLOCK], @[]);
        CHECK([r[@"windows"] count] == 3 && [r[@"gone"] count] == 0, "W4x11 bad record (a string): ignored %s", [[r[@"windows"] description] UTF8String]);
        keptWF[@"madeFullScreen"] = @[@42, @"", [NSNull null]];
        r = BackQuit(keptWF, NO, YES, @[TIPS], nil, NSNotFound, nil, @[TIPS], @[TIPS, CLOCK], @[]);
        CHECK([r[@"windows"] count] == 3 && [r[@"gone"] count] == 0, "W4x12 bad record (no names): ignored %s", [[r[@"windows"] description] UTF8String]);
        // Stage Manager does not read the record (its windows are told by its stages)
        NSDictionary *keptSMF = @{@"desktops": @[@1, @2], @"windows": @{K(TIPS, @"A"): @1, K(CLOCK, @"B"): @2}, @"madeFullScreen": @[CLOCK]};
        r = BackQuit(keptSMF, YES, YES, @[K(TIPS, @"A"), K(CLOCK, @"B")], @[@[K(TIPS, @"A")], @[K(CLOCK, @"B")]], 0, nil, nil, @[TIPS, CLOCK], @[]);
        CHECK([r[@"windows"][K(CLOCK, @"B")] isEqual:@2] && [r[@"gone"] count] == 0, "W4x13 Stage Manager: the record is not read %s", [[r[@"windows"] description] UTF8String]);

        // ---- Stage Manager: records by window, a desktop is a stage ----
        NSString *tA = K(TIPS, @"A"), *cB = K(CLOCK, @"B"), *xC = K(CALC, @"C"), *wW = K(WEATHER, @"W"), *mM = K(MAPS, @"M"), *nN = K(NOTES, @"N");
        NSDictionary *smFit1 = @{@"smslots": @{tA: @"fill"}, @"smfree": @[]}, *smFit2 = @{@"smslots": @{}, @"smfree": @[cB]};
        NSDictionary *keptS = @{@"desktops": @[@1, @2, @3], @"current": @1, @"windows": @{tA: @1, cB: @2, xC: @3}, @"frames": @{cB: @"{{1, 2}, {3, 4}}"},
                                @"leftSizes": @{@"2": @"{1366, 1024}", @"3": @"{1024, 1366}"}, @"fit": @{@"1": smFit1, @"2": smFit2}};
        // 5. Desktop 1's stage on screen with a window opened meanwhile (it joined that stage): it is Desktop 1's; Desktop 1 current.
        r = Back(keptS, YES, YES, @[tA, wW, cB, xC], @[@[tA, wW], @[cB], @[xC]], 0, nil, nil);
        CHECK([r[@"windows"] isEqualToDictionary:(@{tA: @1, wW: @1, cB: @2, xC: @3})], "S5 windows %s", [[r[@"windows"] description] UTF8String]);
        CHECK([r[@"current"] integerValue] == 0 && [r[@"fresh"] isEqualToDictionary:(@{wW: @1})], "S5 current/fresh");
        CHECK([r[@"leftSizes"] isEqualToDictionary:(@{@"2": @"{1366, 1024}", @"3": @"{1024, 1366}"})], "S5 leftSizes kept (stages were not on screen)");
        CHECK([r[@"fit"] isEqualToDictionary:(@{@"2": smFit2})], "S5 fit: the desktop on screen keeps its live one");
        CHECK([r[@"frames"] isEqualToDictionary:(@{cB: @"{{1, 2}, {3, 4}}"})], "S5 frames");

        // 6. Desktop 2's stage on screen, a window opened there meanwhile: it is Desktop 2's, and Desktop 2 is current (its kept tiles not taken).
        r = Back(keptS, YES, YES, @[tA, cB, mM, xC], @[@[cB, mM], @[tA], @[xC]], 0, nil, nil);
        CHECK([r[@"current"] integerValue] == 1, "S6 current %ld", (long)[r[@"current"] integerValue]);
        CHECK([r[@"fresh"] isEqualToDictionary:(@{mM: @2})] && [r[@"windows"][mM] isEqual:@2], "S6 fresh %s", [[r[@"fresh"] description] UTF8String]);
        CHECK([r[@"fit"] isEqualToDictionary:(@{@"1": smFit1})], "S6 fit %s", [[r[@"fit"] description] UTF8String]);
        CHECK(r[@"leftSizes"][@"2"] == nil && [r[@"leftSizes"][@"3"] isEqualToString:@"{1024, 1366}"], "S6 leftSizes");

        // 7. Kept windows of two desktops share the stage on screen with a new one: the new one Desktop 1's, Desktop 1 current.
        r = Back(keptS, YES, YES, @[tA, cB, nN, xC], @[@[tA, cB, nN], @[xC]], 0, nil, nil);
        CHECK([r[@"current"] integerValue] == 0 && [r[@"fresh"] isEqualToDictionary:(@{nN: @1})], "S7 current/fresh %s", [[r[@"fresh"] description] UTF8String]);
        CHECK([r[@"windows"][cB] isEqual:@2], "S7 a kept window keeps its desktop (the tick decides about the shared stage)");

        // 8. Calculator's window closed meanwhile: left out; Desktop 3 stays, empty. A stage of new windows only: Desktop 1's.
        r = Back(keptS, YES, YES, @[tA, cB, wW], @[@[cB], @[tA], @[wW]], 1, nil, nil);
        CHECK([r[@"gone"] isEqualToArray:(@[CALC])] && r[@"windows"][xC] == nil, "S8 gone %s", [[r[@"gone"] description] UTF8String]);
        CHECK([r[@"desktops"] isEqualToArray:(@[@1, @2, @3])] && [r[@"current"] integerValue] == 0 && [r[@"windows"][wW] isEqual:@1], "S8 desktops/current/new");

        // 9. A minimized window new since: Desktop 1's; a kept minimized one stays where it was.
        NSDictionary *keptMin = @{@"desktops": @[@1, @2], @"windows": @{tA: @1, cB: @2}};
        r = Back(keptMin, YES, YES, @[tA, cB, mM], @[@[tA]], 0, @[cB, mM], nil);
        CHECK([r[@"windows"] isEqualToDictionary:(@{tA: @1, cB: @2, mM: @1})] && [r[@"fresh"] isEqualToDictionary:(@{mM: @1})], "S9 windows %s", [[r[@"windows"] description] UTF8String]);

        // 10. An older build's record by app: any window of the app keeps it; its window is not "new".
        NSDictionary *keptApp = @{@"desktops": @[@1, @2], @"windows": @{TIPS: @2, cB: @1}};
        r = Back(keptApp, YES, YES, @[tA, cB], @[@[tA], @[cB]], 0, nil, nil);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @2, cB: @1})] && [r[@"fresh"] count] == 0, "S10 windows %s", [[r[@"windows"] description] UTF8String]);
        CHECK([r[@"current"] integerValue] == 1, "S10 current = the app record's desktop (%ld)", (long)[r[@"current"] integerValue]);
        // ... and windows known by app (the engine's DMSMPerWindow off): a kept window key counts by its app's key
        r = Back(@{@"desktops": @[@1, @2], @"windows": @{tA: @2}}, YES, YES, @[TIPS], @[@[TIPS]], 0, nil, nil);
        CHECK([r[@"windows"][tA] isEqual:@2] && [r[@"windows"][TIPS] isEqual:@2] && [r[@"gone"] count] == 0 && [r[@"fresh"] count] == 0, "S10b windows %s fresh %s", [[r[@"windows"] description] UTF8String], [[r[@"fresh"] description] UTF8String]);
        CHECK([r[@"current"] integerValue] == 1, "S10b current %ld", (long)[r[@"current"] integerValue]);

        // 11. Nothing on screen (Home Screen): Desktop 1 current.
        r = Back(keptS, YES, YES, @[tA, cB, xC], @[@[cB], @[tA], @[xC]], NSNotFound, nil, nil);
        CHECK([r[@"current"] integerValue] == 0 && [r[@"fit"] isEqualToDictionary:(@{@"2": smFit2})], "S11 current/fit");

        // ---- bad or empty input ----
        CHECK(Back(nil, NO, YES, @[], nil, NSNotFound, nil, nil) == nil, "B1 no kept copy");
        CHECK(Back(@{@"desktops": @[@1]}, NO, YES, @[], nil, NSNotFound, nil, nil) == nil, "B2 one desktop: nothing comes back");
        r = Back(@{@"desktops": @[@3, @1, @3, @-2, @"x", @9, @2], @"windows": @{TIPS: @9, CLOCK: @"2", CALC: @3, @"": @1}}, NO, YES, @[TIPS, CLOCK, CALC], nil, NSNotFound, nil, @[TIPS, CLOCK, CALC]);
        CHECK([r[@"desktops"] isEqualToArray:(@[@1, @3, @9, @2])], "B3 desktops %s", [[r[@"desktops"] description] UTF8String]);
        CHECK([r[@"windows"] isEqualToDictionary:(@{TIPS: @9, CALC: @3, CLOCK: @1})], "B3 windows %s", [[r[@"windows"] description] UTF8String]);
        NSMutableArray *many = [NSMutableArray array]; for (int i = 1; i <= 12; i++) [many addObject:@(i)];
        r = Back(@{@"desktops": many}, NO, YES, @[], nil, NSNotFound, nil, nil);
        CHECK([r[@"desktops"] count] == 8, "B4 at most 8 desktops (%lu)", (unsigned long)[r[@"desktops"] count]);
        r = Back(@{@"desktops": @[@1, @2], @"windows": @"no", @"frames": @[], @"fit": @3, @"fullscreen": @{@"2": @4}}, NO, YES, @[], nil, NSNotFound, nil, nil);
        CHECK(r && [r[@"windows"] count] == 0 && [r[@"fullscreen"] count] == 0 && [r[@"fit"] count] == 0, "B5 wrong types are skipped");
    }
    printf("test-mswkept: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
