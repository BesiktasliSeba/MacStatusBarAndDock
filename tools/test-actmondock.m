// Mac test of Activity Monitor in the Dock and in the App Library's search (common/ActMonDock.h, 1.7.3 items 5 and 13): the layout SpringBoard
// writes never names our icon (every list, a drag's stand-in in a page's turned order, nothing else touched), where it goes back into the Dock at
// start, how the record is read back, the search's rules (when the list is given its last result again; when a result may be made anew), and its
// running entry (1.7.7 item 1b: where it shows while its window is open, the recents it is shown from, its menu row).
#import <Foundation/Foundation.h>
#include "../common/ActMonDock.h"

static int fails = 0, checks = 0;
static void ok(NSString *what, BOOL cond) { checks++; if (!cond) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static void eqi(NSString *what, long got, long want) { checks++; if (got != want) { fails++; printf("FAIL %s: got %ld, want %ld\n", what.UTF8String, got, want); } }
#define AM @"com.besiktasliseba.macstatusbar.activitymonitor"

// A layout shaped like IconState.plist (made-up apps): the Dock, two pages (a folder and a widget on the second), the App Library's list, the turned
// orders, the folder's own lists.
static NSDictionary *Layout(NSArray *dock, NSArray *page1, NSArray *folderApps, NSArray *ignored, NSArray *rotated1) {
    NSDictionary *folder = @{@"listType": @"folder", @"displayName": @"Utilities", @"iconLists": @[folderApps], @"uniqueIdentifier": @"F-1"};
    NSDictionary *widget = @{@"iconType": @"custom", @"elements": @[@{@"containerBundleIdentifier": @"com.example.weather", @"gridSizeClass": @"small"}], @"gridSize": @"small"};
    return @{@"buttonBar": dock, @"iconLists": @[page1, @[folder, widget, @"com.example.notes"]], @"ignored": ignored,
             @"listUniqueIdentifiers": @[@"P-1", @"P-2"], @"listMetadata": @{@"P-1": @{@"rotatedOrder": rotated1}},
             @"uniqueIdentifier": @"U-1", @"displayName": @"Home", @"widgetVersion": @3};
}

int main(void) {
    @autoreleasepool {
        // ---- the layout without our icon ----
        NSDictionary *clean = Layout(@[@"com.example.mail", @"com.example.safari"], @[@"com.example.clock"], @[@"com.example.calc"], @[@"com.example.game"], @[@"com.example.clock"]);
        NSUInteger n = 99; n = 0;
        ok(@"a layout that names nothing of ours comes back as the very same object", MSBDLayoutWithout(clean, AM, &n) == clean && n == 0);
        NSDictionary *inDock = Layout(@[@"com.example.mail", AM, @"com.example.safari"], @[@"com.example.clock"], @[@"com.example.calc"], @[@"com.example.game"], @[@"com.example.clock"]);
        n = 0; NSDictionary *out = MSBDLayoutWithout(inDock, AM, &n);
        ok(@"in the Dock: taken out of buttonBar, the others in their order", [out[@"buttonBar"] isEqual:(@[@"com.example.mail", @"com.example.safari"])]);
        eqi(@"in the Dock: one taken out", (long)n, 1);
        ok(@"in the Dock: everything else as it was", [out isEqual:clean]);
        NSDictionary *everywhere = Layout(@[AM, @"com.example.mail", @"com.example.safari", AM], @[AM, @"com.example.clock"], @[@"com.example.calc", AM], @[AM, @"com.example.game"],
                                          @[@"com.example.clock", [@"Placeholder: Grabbed " stringByAppendingString:AM]]);
        n = 0; out = MSBDLayoutWithout(everywhere, AM, &n);
        ok(@"everywhere (Dock twice, a page, a folder, the App Library's list, a drag's stand-in in a turned order): all taken out", [out isEqual:clean]);
        eqi(@"everywhere: six taken out", (long)n, 6);
        NSData *written = [NSPropertyListSerialization dataWithPropertyList:out format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        NSData *xml = [NSPropertyListSerialization dataWithPropertyList:out format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
        ok(@"the written layout (binary and XML) never names it", written.length && xml.length
           && [[[NSString alloc] initWithData:xml encoding:NSUTF8StringEncoding] rangeOfString:AM].location == NSNotFound);
        // what is not ours stays: other apps' stand-ins, a longer identifier that starts with ours, look-alikes, non-list values
        NSArray *others = @[@"Placeholder: Grabbed com.example.mail", [AM stringByAppendingString:@"2"], [@"x" stringByAppendingString:AM], @"Activity Monitor", @42];
        NSDictionary *withOthers = @{@"buttonBar": others, @"displayName": AM, @"uniqueIdentifier": AM};
        n = 0; out = MSBDLayoutWithout(withOthers, AM, &n);
        ok(@"other entries -- another app's stand-in, a longer or a prefixed identifier, a name, a number -- and values outside lists stay", out == withOthers && n == 0);
        // the shapes SpringBoard hands over: mutable containers, nested deeper than a folder
        NSMutableDictionary *mut = [NSMutableDictionary dictionaryWithDictionary:@{@"buttonBar": [NSMutableArray arrayWithObjects:@"com.example.mail", AM, nil],
                                                                                   @"deep": @[@[@[@{@"iconLists": @[@[AM]]}]]]}];
        n = 0; out = MSBDLayoutWithout(mut, AM, &n);
        ok(@"mutable containers and deep nesting: taken out (2), the input left as it was", n == 2 && [out[@"buttonBar"] isEqual:(@[@"com.example.mail"])]
           && [out[@"deep"] isEqual:(@[@[@[@{@"iconLists": @[@[]]}]]])] && [mut[@"buttonBar"] count] == 2);
        ok(@"no identifier given: nothing changes", MSBDLayoutWithout(everywhere, nil, NULL) == everywhere && MSBDLayoutWithout(everywhere, @"", NULL) == everywhere);
        ok(@"not a layout at all: comes back as it was", [MSBDLayoutWithout(@"text", AM, NULL) isEqual:@"text"] && MSBDLayoutWithout(nil, AM, NULL) == nil);
        ok(@"a NULL count is fine", [MSBDLayoutWithout(inDock, AM, NULL) isEqual:clean]);
        ok(@"the stand-in rule: exact, or after a space", MSBDLayoutEntryNames(AM, AM) && MSBDLayoutEntryNames([@"Placeholder: Grabbed " stringByAppendingString:AM], AM)
           && !MSBDLayoutEntryNames([@"Placeholder:" stringByAppendingString:AM], AM) && !MSBDLayoutEntryNames([AM stringByAppendingString:@" "], AM));

        // ---- its place at start ----
        eqi(@"no record: not put back", MSBDActMonDockPlace(-1, 11, 14), -1);
        eqi(@"its place, the Dock as it was", MSBDActMonDockPlace(3, 11, 14), 3);
        eqi(@"its place was the end", MSBDActMonDockPlace(11, 11, 14), 11);
        eqi(@"fewer icons now: the Dock's end", MSBDActMonDockPlace(11, 5, 14), 5);
        eqi(@"an empty Dock: the first place", MSBDActMonDockPlace(4, 0, 14), 0);
        eqi(@"a full Dock: not put back", MSBDActMonDockPlace(2, 14, 14), -1);
        eqi(@"fuller than its room (another tweak's): not put back", MSBDActMonDockPlace(2, 15, 14), -1);
        // ---- the record ----
        eqi(@"record 3", MSBDActMonDockRecord(@3), 3);
        eqi(@"record 0", MSBDActMonDockRecord(@0), 0);
        eqi(@"record 64 (the highest)", MSBDActMonDockRecord(@64), 64);
        eqi(@"record absent", MSBDActMonDockRecord(nil), -1);
        eqi(@"record negative", MSBDActMonDockRecord(@(-1)), -1);
        eqi(@"record too high", MSBDActMonDockRecord(@65), -1);
        eqi(@"record not whole", MSBDActMonDockRecord(@2.5), -1);
        eqi(@"record NaN", MSBDActMonDockRecord(@(NAN)), -1);
        eqi(@"record a string", MSBDActMonDockRecord(@"3"), -1);
        eqi(@"record a dictionary", MSBDActMonDockRecord(@{@"place": @3}), -1);

        // ---- the search's rules (item 13) ----
        ok(@"nothing found for \"actx\" (unchanged after \"act\"), ours shown: given to the list (ours out)", MSBDALGiveAnswer(YES, nil, @"actx", NO, YES));
        ok(@"nothing found, the field matches again (\"act\" after \"actx\"), ours not shown: given (ours in)", MSBDALGiveAnswer(YES, nil, @"act", YES, NO));
        ok(@"the apps of \"Act\" (unchanged after \"Ac\"), field \"Act\", ours missing: given (ours in)", MSBDALGiveAnswer(NO, @"Act", @"Act", YES, NO));
        ok(@"the same apps for \"Actx\", ours shown: given (ours out)", MSBDALGiveAnswer(NO, @"Actx", @"Actx", NO, YES));
        ok(@"spaces around the text: the same text", MSBDALGiveAnswer(NO, @"Act ", @" Act", YES, NO));
        ok(@"shown as the field says: never given", !MSBDALGiveAnswer(YES, nil, @"act", YES, YES) && !MSBDALGiveAnswer(NO, @"actx", @"actx", NO, NO));
        ok(@"an answer for an older text (\"a\" while the field says \"act\"): never given again (the list would take \"a\" as its text)", !MSBDALGiveAnswer(NO, @"a", @"act", YES, NO));
        ok(@"nothing found while the field is empty (never the empty search's answer): never given", !MSBDALGiveAnswer(YES, nil, @"", YES, NO) && !MSBDALGiveAnswer(YES, nil, @"  ", NO, YES));
        ok(@"the empty search's own A-Z answer, ours missing: given (its letter's section, the engine's own result)", MSBDALGiveAnswer(NO, @"", @"", YES, NO));
        ok(@"no texts at all: never given", !MSBDALGiveAnswer(NO, nil, nil, YES, NO) && !MSBDALGiveAnswer(NO, @"act", nil, YES, NO));
        ok(@"made anew only when both texts are there", MSBDALMayMakeAnew(@"Ac", @"Act"));
        ok(@"never for the empty search, whichever text is empty", !MSBDALMayMakeAnew(@"", @"act") && !MSBDALMayMakeAnew(@"act", @"") && !MSBDALMayMakeAnew(@" ", @" ")
           && !MSBDALMayMakeAnew(nil, @"act") && !MSBDALMayMakeAnew(@"act", (NSString *)[NSNull null]));
        // the race of 31 Oct, as rules: keys 25 ms apart -- the engine's answer for "Ac" reaches the list when its text is "Act" (the same apps for
        // "Act": never sent). Ours follows the list's text, so the late answer gets ours; the next text that no longer matches takes it out again.
        ok(@"late answer for \"Ac\" while the list shows \"Act\": made anew with ours", MSBDALMayMakeAnew(@"Ac", @"Act"));
        ok(@"then \"Actx\": nothing found (a change: the list hears it), ours out by the field's text", MSBDALMayMakeAnew(@"Actx", @"Actx") && !MSBDALGiveAnswer(YES, nil, @"Actx", NO, NO));

        // ---- its running entry (1.7.7 item 1b) ----
        eqi(@"window open, not kept, the Dock shows recents: in the recents", MSBDActMonRunningSpot(YES, NO, YES, YES), MSBDActMonSpotRecents);
        eqi(@"window open, not kept, no recents shown: after the Dock's apps", MSBDActMonRunningSpot(YES, NO, YES, NO), MSBDActMonSpotDockEnd);
        eqi(@"kept: never a running entry (the kept icon is its Dock icon)", MSBDActMonRunningSpot(YES, YES, YES, YES), MSBDActMonSpotNone);
        eqi(@"kept, no recents: none", MSBDActMonRunningSpot(YES, YES, YES, NO), MSBDActMonSpotNone);
        eqi(@"no window: none (it leaves with the window)", MSBDActMonRunningSpot(YES, NO, NO, YES), MSBDActMonSpotNone);
        eqi(@"no window, no recents: none", MSBDActMonRunningSpot(YES, NO, NO, NO), MSBDActMonSpotNone);
        eqi(@"Show in App Library off (no icon): none", MSBDActMonRunningSpot(NO, NO, YES, YES), MSBDActMonSpotNone);
        eqi(@"off, no recents: none", MSBDActMonRunningSpot(NO, NO, YES, NO), MSBDActMonSpotNone);
        // the recents the Dock's list is made from, with ours first (display items stood for by strings)
        NSMutableOrderedSet *recents = [NSMutableOrderedSet orderedSetWithArray:@[@"com.example.clock", @"com.example.maps", @"com.example.notes"]];
        NSMutableOrderedSet *with = MSBDActMonRecentsWithOurs(recents, AM);
        ok(@"ours first, the recents after it in their order", [with.array isEqual:(@[AM, @"com.example.clock", @"com.example.maps", @"com.example.notes"])]);
        ok(@"a copy: the recents SpringBoard keeps (and saves) are not touched", recents.count == 3 && ![recents containsObject:AM] && with != recents);
        ok(@"ours there already: nil (never twice)", MSBDActMonRecentsWithOurs(with, AM) == nil);
        ok(@"no recents yet: ours alone", [MSBDActMonRecentsWithOurs([NSOrderedSet orderedSet], AM).array isEqual:(@[AM])]);
        ok(@"not an ordered set (an array, nil): nil", MSBDActMonRecentsWithOurs(@[@"com.example.clock"], AM) == nil && MSBDActMonRecentsWithOurs(nil, AM) == nil);
        ok(@"no item of ours: nil", MSBDActMonRecentsWithOurs(recents, nil) == nil);
        // SpringBoard's own list from them (as read on 18.5, -_updateCurrentDisplayItemsAfterContinuityChange:notifyDelegate:): the recents, a suggested app
        // last, culled to the room (max) from the recents' end -- the suggestion and ours (first) are never culled.
        NSArray *(^shown)(NSOrderedSet *, NSString *, NSUInteger) = ^NSArray *(NSOrderedSet *r, NSString *sug, NSUInteger max) {
            NSMutableOrderedSet *items = [r mutableCopy];
            if (sug) { [items removeObject:sug]; [items addObject:sug]; }
            if (items.count > max) [items removeObjectsInRange:NSMakeRange(max - (sug ? 1 : 0), items.count - max)];
            return items.array;
        };
        NSOrderedSet *four = [NSOrderedSet orderedSetWithArray:@[@"r0", @"r1", @"r2", @"r3"]];
        ok(@"4 recents, 5 places (KT's A12Z: Recent Apps 4 + the suggestion's place), no suggestion: ours + the 4 (the suggestion's place)",
           [shown(MSBDActMonRecentsWithOurs(four, AM), nil, 5) isEqual:(@[AM, @"r0", @"r1", @"r2", @"r3"])]);
        ok(@"4 recents and a suggestion, 5 places: ours + 3 + the suggestion (the oldest recent waits, as for any app just opened)",
           [shown(MSBDActMonRecentsWithOurs(four, AM), @"handoff", 5) isEqual:(@[AM, @"r0", @"r1", @"r2", @"handoff"])]);
        ok(@"stock room of 3: ours + the 2 newest", [shown(MSBDActMonRecentsWithOurs(four, AM), nil, 3) isEqual:(@[AM, @"r0", @"r1"])]);
        ok(@"without ours the list is SpringBoard's as before", [shown(four, @"handoff", 5) isEqual:(@[@"r0", @"r1", @"r2", @"r3", @"handoff"])]);
        // its menu's Dock row
        eqi(@"kept: Remove from Dock (in the Dock and in the App Library)", MSBDActMonMenuRow(YES, NO), MSBDActMonRowRemove);
        eqi(@"kept wins over a running entry's own icon", MSBDActMonMenuRow(YES, YES), MSBDActMonRowRemove);
        eqi(@"the running entry's own icon: Keep in Dock", MSBDActMonMenuRow(NO, YES), MSBDActMonRowKeep);
        eqi(@"the App Library (not kept): Add to Dock", MSBDActMonMenuRow(NO, NO), MSBDActMonRowAdd);
        // no longer kept while the window is open
        ok(@"unkept, window open, no recents shown: stays in its place (a Mac's Dock)", MSBDActMonUnkeptStaysInPlace(YES, YES, NO));
        ok(@"unkept, window open, recents shown: leaves the Dock's list for the recents", !MSBDActMonUnkeptStaysInPlace(YES, YES, YES));
        ok(@"unkept, no window: leaves", !MSBDActMonUnkeptStaysInPlace(YES, NO, NO) && !MSBDActMonUnkeptStaysInPlace(YES, NO, YES));
        ok(@"unkept with Show in App Library off: leaves", !MSBDActMonUnkeptStaysInPlace(NO, YES, NO));
    }
    printf("test-actmondock: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
