// test-spotmove.m -- Mac test of how search-143's Settings items are taken out of Apple's Spotlight sections (spotlight/MacSpotlightMove.h), with
// stand-ins for Apple's SFResultSection (results, setResults:, copy) and SFSearchResult (identifier, applicationBundleIdentifier).
#import <Foundation/Foundation.h>
#import "../spotlight/MacSpotlightMove.h"

@interface FakeResult : NSObject
@property (copy) NSString *identifier, *applicationBundleIdentifier;
@end
@implementation FakeResult
@end
@interface FakeSection : NSObject <NSCopying>
@property (copy) NSString *title;
@property (strong) NSArray *results;
@end
@implementation FakeSection
- (id)copyWithZone:(NSZone *)z { FakeSection *c = [FakeSection new]; c.title = self.title; c.results = self.results; return c; }
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
        if (gFail) { printf("test-spotmove: %d of %d FAILED\n", gFail, gN); return 1; }
        printf("test-spotmove: %d/%d passed\n", gN, gN);
        return 0;
    }
}
