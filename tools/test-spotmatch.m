// test-spotmatch.m -- Mac test of which of our Spotlight rows the typed text matches, and their order (spotlight/MacSpotlightMatch.h).
#import <Foundation/Foundation.h>
#import "../spotlight/MacSpotlightMatch.h"

static int gFail = 0, gN = 0;
static NSArray *gRows;
// (1.7.0) whether the text names an action: then the Actions come before Apple's results (MSPNamesOne)
static void Lead(NSString *q, BOOL want) {
    gN++;
    BOOL got = MSPNamesOne(q, gRows, MSPMatches(q, gRows, @"a", 8));
    if (got != want) { gFail++; printf("  FAIL \"%s\": names an action %d, want %d\n", q.UTF8String, got, want); }
}
static void Expect(NSString *q, NSString *group, NSArray<NSString *> *want) {
    gN++;
    NSMutableArray *got = [NSMutableArray array];
    for (NSNumber *i in MSPMatches(q, gRows, group, 8)) [got addObject:gRows[i.unsignedIntegerValue][@"t"]];
    if (![got isEqualToArray:want]) { gFail++; printf("  FAIL \"%s\" (%s): got [%s], want [%s]\n", q.UTF8String, group.UTF8String,
        [got componentsJoinedByString:@" | "].UTF8String, [want componentsJoinedByString:@" | "].UTF8String); }
}
int main(void) {
    @autoreleasepool {
        gRows = @[
            @{@"g": @"a", @"t": @"Show Desktop", @"k": @"show desktop hide windows"},
            @{@"g": @"a", @"t": @"Desktop 1", @"k": @"desktop 1 space 1"},
            @{@"g": @"a", @"t": @"Desktop 2", @"k": @"desktop 2 space 2"},
            @{@"g": @"a", @"t": @"Downloads", @"k": @"downloads download"},
            @{@"g": @"a", @"t": @"New Finder Window", @"k": @"new finder window"},
            @{@"g": @"a", @"t": @"Lock Screen", @"k": @"lock screen"},
            @{@"g": @"a", @"t": @"Force Quit Clock…", @"m": @"Force Quit", @"k": @"force quit"},
            @{@"g": @"a", @"t": @"Activity Monitor", @"k": @"activity monitor processes cpu memory ram"},
            @{@"g": @"w", @"t": @"Clock", @"k": @"Clock"},
            @{@"g": @"w", @"t": @"Tips", @"k": @"Tips"},
            @{@"g": @"w", @"t": @"Çalar Saat", @"k": @"Çalar Saat"},
            @{@"g": @"w", @"t": @"Downloads", @"k": @"Downloads Finder"},
            @{@"g": @"w", @"t": @"Documents", @"k": @"Documents Finder"},
        ];
        Expect(@"d", @"a", @[]);                                                    // one letter: nothing of ours
        Expect(@"", @"a", @[]);
        Expect(@"desktop", @"a", @[@"Desktop 1", @"Desktop 2", @"Show Desktop"]);   // titles starting with it first
        Expect(@"Desktop", @"a", @[@"Desktop 1", @"Desktop 2", @"Show Desktop"]);
        Expect(@"desk 2", @"a", @[@"Desktop 2"]);
        Expect(@"desktop 3", @"a", @[]);
        Expect(@"space 2", @"a", @[@"Desktop 2"]);                                  // a keyword
        Expect(@"show", @"a", @[@"Show Desktop"]);
        Expect(@"hide", @"a", @[@"Show Desktop"]);
        Expect(@"downloads", @"a", @[@"Downloads"]);
        Expect(@"download", @"a", @[@"Downloads"]);
        Expect(@"downloads", @"w", @[@"Downloads"]);                               // a Finder window of that name
        Expect(@"new fi", @"a", @[@"New Finder Window"]);
        Expect(@"finder", @"a", @[@"New Finder Window"]);
        Expect(@"finder", @"w", @[@"Downloads", @"Documents"]);                     // Finder's windows by their app: SpringBoard's order kept
        Expect(@"lock", @"a", @[@"Lock Screen"]);
        Expect(@"LOCK ", @"a", @[@"Lock Screen"]);                                  // case, a space at the end
        Expect(@"screen", @"a", @[@"Lock Screen"]);
        Expect(@"force", @"a", @[@"Force Quit Clock…"]);
        Expect(@"quit", @"a", @[@"Force Quit Clock…"]);
        Expect(@"clock", @"a", @[]);                                                // the app's name finds its window, not Force Quit
        Expect(@"clock", @"w", @[@"Clock"]);
        Expect(@"clocks", @"w", @[]);
        Expect(@"tips", @"w", @[@"Tips"]);
        Expect(@"ti", @"w", @[@"Tips"]);
        Expect(@"calar", @"w", @[@"Çalar Saat"]);                                   // accents
        Expect(@"saat", @"w", @[@"Çalar Saat"]);
        Expect(@"new-finder", @"a", @[@"New Finder Window"]);                       // punctuation between words
        Expect(@"window", @"a", @[@"New Finder Window", @"Show Desktop"]);       // (Show Desktop by its keyword "hide windows", after)
        Expect(@"window", @"w", @[]);                                               // no row is found by "window" alone
        Expect(@"activ", @"a", @[@"Activity Monitor"]);
        Expect(@"cpu", @"a", @[@"Activity Monitor"]);                               // a keyword
        // the Actions first only when the text names one (its title, or the words it is found by instead, by their starts)
        Lead(@"activ", YES); Lead(@"Activity", YES); Lead(@"monitor", YES);         // the title / a word of it
        Lead(@"cpu", NO); Lead(@"memory", NO); Lead(@"ram", NO);                    // only an extra word: Apple's results first
        Lead(@"lock", YES); Lead(@"screen", YES); Lead(@"desk 2", YES); Lead(@"new fi", YES);
        Lead(@"space 2", NO); Lead(@"hide", NO);                                     // (keywords of Desktop 2 / Show Desktop)
        Lead(@"window", YES);                                                        // (New Finder Window by its title; Show Desktop's keyword does not matter)
        Lead(@"force", YES); Lead(@"quit", YES);                                     // ("m": the words it is found by)
        Lead(@"clock", NO);                                                          // (no action: the window's name, Force Quit Clock… is not found by it)
        Lead(@"settings", NO); Lead(@"a", NO); Lead(@"", NO);                        // (nothing matched)
        if (gFail) { printf("test-spotmatch: %d of %d FAILED\n", gFail, gN); return 1; }
        printf("test-spotmatch: %d/%d passed\n", gN, gN);
        return 0;
    }
}
