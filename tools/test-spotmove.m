// test-spotmove.m -- Mac test of how search-143's Settings items are taken out of Apple's Spotlight sections (spotlight/MacSpotlightMove.h), with
// stand-ins for Apple's SFResultSection (results, setResults:, copy) and SFSearchResult (identifier, applicationBundleIdentifier).
#import <Foundation/Foundation.h>
#import "../spotlight/MacSpotlightMove.h"

@interface FakeResult : NSObject
@property (copy) NSString *identifier, *applicationBundleIdentifier;
@property int topHit;
@end
@implementation FakeResult
@end
@interface FakeSection : NSObject <NSCopying>
@property (copy) NSString *title, *identifier, *bundleIdentifier;
@property (strong) NSArray *results;
@end
@implementation FakeSection
- (id)copyWithZone:(NSZone *)z { FakeSection *c = [FakeSection new]; c.title = self.title; c.identifier = self.identifier; c.bundleIdentifier = self.bundleIdentifier; c.results = self.results; return c; }
@end
static FakeResult *R(NSString *ident, NSString *app) { FakeResult *r = [FakeResult new]; r.identifier = ident; r.applicationBundleIdentifier = app; return r; }
static FakeSection *S(NSString *t, NSArray *rs) { FakeSection *s = [FakeSection new]; s.title = t; s.results = rs; return s; }
static int gFail = 0, gN = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static NSString *Titles(NSArray *secs) { NSMutableArray *a = [NSMutableArray array]; for (FakeSection *s in secs) [a addObject:[NSString stringWithFormat:@"%@(%lu)", s.title, (unsigned long)s.results.count]]; return [a componentsJoinedByString:@" "]; }
static NSString *Ids(NSArray *rs) { NSMutableArray *a = [NSMutableArray array]; for (FakeResult *r in rs) [a addObject:r.identifier]; return [a componentsJoinedByString:@" "]; }
int main(void) {
    @autoreleasepool {
        FakeResult *t1 = R(@"msbd-tweaksetting:statusbar/0", @"com.apple.Preferences"), *t2 = R(@"msbd-tweaksetting:dock/2", @"com.apple.Preferences");
        FakeResult *t1top = R(@"msbd-tweaksetting:statusbar/0", @"com.apple.Preferences");   // (the same item as the Top Hit: another object)
        FakeResult *wifi = R(@"prefs:root=WIFI", @"com.apple.Preferences"), *app = R(@"com.apple.mobiletimer", @"com.apple.mobiletimer");
        FakeResult *fake = R(@"msbd-tweaksetting:x", @"com.example.other");   // (the prefix from another app: not ours to move)
        FakeSection *top = S(@"Top Hit", @[t1top]), *settings = S(@"Settings", @[wifi, t1, t2]), *apps = S(@"Apps", @[app, fake]);
        NSArray *settingsBefore = settings.results;
        NSMutableArray *secs = [NSMutableArray arrayWithObjects:top, settings, apps, nil];
        NSArray *moved = MSPTakeTweakSettings(secs);
        Expect([Titles(secs) isEqualToString:@"Settings(1) Apps(2)"], [@"sections after: " stringByAppendingString:Titles(secs)]);   // (Top Hit left empty: gone)
        Expect([Ids(moved) isEqualToString:@"msbd-tweaksetting:statusbar/0 msbd-tweaksetting:dock/2"], [@"moved: " stringByAppendingString:Ids(moved)]);
        Expect(moved.firstObject == t1top, @"the Top Hit's object kept (its first place)");
        Expect(settings.results == settingsBefore && settings.results.count == 3, @"Apple's own section object is not changed (a copy is)");
        Expect(secs[0] != settings && [[secs[0] results] isEqualToArray:@[wifi]], @"Settings copy keeps Apple's other row");
        Expect(secs[1] == apps, @"a section without our items is left as it was (the same object)");
        NSMutableArray *none = [NSMutableArray arrayWithObjects:S(@"Apps", @[app]), nil];
        Expect(MSPTakeTweakSettings(none).count == 0 && none.count == 1, @"nothing of ours: nothing moved");
        NSMutableArray *odd = [NSMutableArray arrayWithObjects:@"not a section", S(@"Settings", @[t2]), nil];
        Expect(MSPTakeTweakSettings(odd).count == 1 && odd.count == 1, @"something that is not a section is left alone");
        // (1.7.0) where our sections go among Apple's: MSPPlaceOurs
        FakeSection *aTop = S(@"Top Hit", @[app]), *aWeb = S(@"Web", @[wifi]), *aSet = S(@"Settings", @[wifi]);
        FakeSection *act = S(@"Actions", @[app]), *win = S(@"Windows", @[app]), *tw = S(@"Tweak Settings", @[t1]);
        NSArray *apple = @[aTop, aWeb, aSet];
        NSString *got = Titles(MSPPlaceOurs(apple, NSNotFound, NSNotFound, act, YES, win, tw));
        Expect([got isEqualToString:@"Actions(1) Top Hit(1) Web(1) Settings(1) Windows(1) Tweak Settings(1)"], [@"named action: Actions first: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(apple, NSNotFound, NSNotFound, act, NO, win, tw));
        Expect([got isEqualToString:@"Top Hit(1) Web(1) Settings(1) Actions(1) Windows(1) Tweak Settings(1)"], [@"found by a keyword only: after Apple's, as before: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(apple, NSNotFound, NSNotFound, nil, YES, win, nil));
        Expect([got isEqualToString:@"Top Hit(1) Web(1) Settings(1) Windows(1)"], [@"no Actions: Windows after Apple's: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(apple, NSNotFound, NSNotFound, act, YES, nil, nil));
        Expect([got isEqualToString:@"Actions(1) Top Hit(1) Web(1) Settings(1)"], [@"Actions alone first: " stringByAppendingString:got]);
        NSArray *kept = @[aTop, aWeb, tw];   // (a Tweak Settings section made for an earlier pass, kept where it is: ours go before it)
        got = Titles(MSPPlaceOurs(kept, 2, NSNotFound, act, YES, win, nil));
        Expect([got isEqualToString:@"Actions(1) Top Hit(1) Web(1) Windows(1) Tweak Settings(1)"], [@"kept Tweak Settings, named action: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(kept, 2, NSNotFound, act, NO, win, nil));
        Expect([got isEqualToString:@"Top Hit(1) Web(1) Actions(1) Windows(1) Tweak Settings(1)"], [@"kept Tweak Settings, keyword: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(@[], NSNotFound, NSNotFound, act, YES, win, tw));
        Expect([got isEqualToString:@"Actions(1) Windows(1) Tweak Settings(1)"], [@"no Apple results: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(apple, NSNotFound, NSNotFound, nil, NO, nil, nil));
        Expect([got isEqualToString:@"Top Hit(1) Web(1) Settings(1)"] && [MSPPlaceOurs(apple, NSNotFound, NSNotFound, nil, NO, nil, nil)[0] isEqual:aTop], [@"nothing of ours: Apple's as they are: " stringByAppendingString:got]);
        // Apple's Top Hit keeps the first place (its highlight and Return): the named Actions come right after it
        got = Titles(MSPPlaceOurs(apple, NSNotFound, 0, act, YES, win, tw));
        Expect([got isEqualToString:@"Top Hit(1) Actions(1) Web(1) Settings(1) Windows(1) Tweak Settings(1)"], [@"a Top Hit: Actions after it: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(@[aWeb, aTop, aSet], NSNotFound, 1, act, YES, nil, nil));
        Expect([got isEqualToString:@"Web(1) Top Hit(1) Actions(1) Settings(1)"], [@"a Top Hit second: Actions after it: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(apple, NSNotFound, 0, act, NO, win, nil));
        Expect([got isEqualToString:@"Top Hit(1) Web(1) Settings(1) Actions(1) Windows(1)"], [@"a Top Hit, keyword only: after Apple's as before: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(kept, 2, 0, act, YES, win, nil));
        Expect([got isEqualToString:@"Top Hit(1) Actions(1) Web(1) Windows(1) Tweak Settings(1)"], [@"a Top Hit and a kept Tweak Settings: " stringByAppendingString:got]);
        got = Titles(MSPPlaceOurs(kept, 2, 2, act, YES, nil, nil));   // (a "Top Hit" at the kept Tweak Settings' place is not one of Apple's: first)
        Expect([got isEqualToString:@"Actions(1) Top Hit(1) Web(1) Tweak Settings(1)"], [@"no Top Hit among Apple's: Actions first: " stringByAppendingString:got]);
        // finding Apple's Top Hit: SearchUI's tophits section (15.6.1: its bundle identifier; the identifier is looked at too)
        FakeSection *th = S(@"Top Hits", @[app]); th.bundleIdentifier = @"com.apple.spotlight.tophits"; th.identifier = @"996297F1-C338-4459-8676-8A677A7C4C35";
        FakeSection *th2 = S(@"Top Hits", @[app]); th2.identifier = @"com.apple.spotlight.tophits";
        Expect(MSPTopHitAt(@[aWeb, th, aSet]) == 1, @"Top Hit found by its bundle identifier");
        Expect(MSPTopHitAt(@[th2, aSet]) == 0, @"Top Hit found by its identifier");
        Expect(MSPTopHitAt(@[aWeb, aSet]) == NSNotFound && MSPTopHitAt(@[]) == NSNotFound && MSPTopHitAt(@[@"not a section"]) == NSNotFound, @"no Top Hit: none");
        // Apple flags results -topHit in other sections too (15.6.1 "settings": Settings' and Files' first results): no Top Hit by a flag
        FakeResult *flagged = R(@"prefs:root=General", @"com.apple.Preferences"); flagged.topHit = 1;
        FakeSection *prefs = S(@"Settings", @[flagged, wifi]); prefs.bundleIdentifier = @"com.apple.Preferences";
        Expect(MSPTopHitAt(@[aWeb, prefs]) == NSNotFound, @"a section whose first result is flagged is not the Top Hit");
        FakeSection *sugg = S(@"Suggestions", @[wifi]); sugg.bundleIdentifier = @"com.apple.searchd.suggestions";
        Expect(MSPTopHitAt(@[sugg, prefs, th]) == 2, @"the tophits section wherever it is");
        if (gFail) { printf("test-spotmove: %d of %d FAILED\n", gFail, gN); return 1; }
        printf("test-spotmove: %d/%d passed\n", gN, gN);
        return 0;
    }
}
