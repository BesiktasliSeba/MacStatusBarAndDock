// test-spotcheck.m -- Mac test of our Spotlight sections' check (spotlight/MacSpotlightCheck.h) against Apple's own classes of real iPadOS builds
// (tools/spotcheck-fixtures/<build>.txt, from each build's dyld shared cache: tools/make-spotcheck-fixture.py).
// test-spotcheck <fixture> [pass <15|16> | drop <class> <+|-selector> | retype <class> <+|-selector> <shape> | nobase <class> | noclass <class>]
//   pass      the check finds everything and picks that tap path (exit 0) -- the sections would be offered on that build
//   drop      that method taken out of the fixture (from the class and every class above it): the check must refuse, naming it
//   retype    that method with another type shape: the check must refuse, naming it
//   nobase    that class made without the base the check asks for (SearchUIResultsViewController, SFText, SFImage, SearchUICommand): refused
//   noclass   that class not there at all: the check must refuse
// One build and one change per process: the classes are made at run time under Apple's names (UIViewController too: a Foundation-only process
// has none of its own), and the check looks its bases up by name.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../spotlight/MacSpotlightCheck.h"

static int gFail = 0;
static void Expect(BOOL ok, NSString *what) { if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static id Dummy(id self, SEL _cmd) { return nil; }

static void TestShapes(void) {   // (the shape rules themselves, on Apple-style encodings)
    Expect([MSPShape("v28@0:8@16B24") isEqualToString:@"v@:@B"], @"shape v28@0:8@16B24");
    Expect([MSPShape("@32@0:8@16@24") isEqualToString:@"@@:@@"], @"shape @32@0:8@16@24");
    Expect([MSPShape("v24@0:8Q16") isEqualToString:@"v@:Q"], @"shape v24@0:8Q16");
    Expect([MSPShape("@24@0:8^{_NSZone=}16") isEqualToString:@"@@:^{}"], @"shape with a zone pointer");
    Expect([MSPShape("v24@0:8@?16") isEqualToString:@"v@:@"], @"shape with a block");
    Expect([MSPExpect(@encode(id), @encode(struct _NSZone *), NULL) isEqualToString:@"@@:^{}"], @"expect (id)(struct _NSZone *)");
    Expect([MSPExpect(@encode(void), @encode(unsigned long long), NULL) isEqualToString:@"v@:Q"], @"expect (void)(unsigned long long)");
    Expect([MSPExpect(@encode(void), @encode(id), @encode(BOOL), NULL) isEqualToString:@"v@:@B"], @"expect (void)(id, BOOL) -- BOOL as on arm64");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: test-spotcheck <fixture> pass|drop|retype|nobase|noclass ...\n"); return 2; }
        NSString *fixture = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:nil];
        if (!fixture.length) { fprintf(stderr, "no fixture %s\n", argv[1]); return 2; }
        NSString *mode = @(argv[2]);
        NSString *cls1 = argc > 3 ? @(argv[3]) : nil, *sel1 = argc > 4 ? @(argv[4]) : nil, *shape1 = argc > 5 ? @(argv[5]) : nil;
        TestShapes();
        NSMutableDictionary<NSString *, NSString *> *superOf = [@{@"UIViewController": @"NSObject"} mutableCopy];
        NSMutableArray<NSArray *> *rows = [NSMutableArray array];
        for (NSString *line in [fixture componentsSeparatedByString:@"\n"]) {
            if (!line.length || [line hasPrefix:@"#"]) continue;
            NSArray *f = [line componentsSeparatedByString:@" "];
            if (f.count != 4) continue;
            superOf[f[0]] = f[1];
            [rows addObject:f];
        }
        if ([mode isEqualToString:@"nobase"]) superOf[cls1] = @"NSObject";
        NSMutableSet<NSString *> *chain = [NSMutableSet set];   // (drop / retype: the class and every class above it, or an inherited copy stands in)
        for (NSString *k = cls1; k && ![k isEqualToString:@"NSObject"]; k = superOf[k]) [chain addObject:k];
        NSMutableDictionary<NSString *, Class> *made = [NSMutableDictionary dictionary];
        __block Class (^make)(NSString *) = nil;
        Class (^makeRef)(NSString *) = ^Class(NSString *name) {
            if ([name isEqualToString:@"NSObject"]) return [NSObject class];
            if (made[name]) return made[name];
            Class sup = make(superOf[name] ?: @"NSObject");
            Class c = objc_allocateClassPair(sup, name.UTF8String, 0);
            if (!c) { fprintf(stderr, "cannot make %s\n", name.UTF8String); exit(2); }
            for (NSArray *r in rows) {
                if (![r[0] isEqualToString:name]) continue;
                NSString *s = r[2];
                BOOL hit = [chain containsObject:r[0]] && [s isEqualToString:sel1];
                if ([mode isEqualToString:@"drop"] && hit) continue;
                NSString *types = [mode isEqualToString:@"retype"] && hit ? shape1 : r[3];
                Class target = [s hasPrefix:@"+"] ? object_getClass(c) : c;
                class_addMethod(target, sel_registerName([[s substringFromIndex:1] UTF8String]), (IMP)Dummy, types.UTF8String);
            }
            objc_registerClassPair(c);
            made[name] = c;
            return c;
        };
        make = makeRef;
        NSArray *names = @[@"SPUIResultsViewController", @"SearchUIRowModel", @"SFSearchResult", @"SFResultSection", @"SFText", @"SFRichText", @"SFSymbolImage",
                           @"SFAppIconImage", @"SearchUICommandHandler", @"SearchUICollectionViewController", @"SearchUICollectionModel", @"SearchUICommand",
                           @"SearchUITapCommand"];
        Class c[13];
        for (NSUInteger i = 0; i < names.count; i++) {
            BOOL inFixture = superOf[names[i]] != nil;   // (15 has no SearchUICommandHandler, 16 no SearchUICommand / SearchUITapCommand)
            c[i] = inFixture && !([mode isEqualToString:@"noclass"] && [cls1 isEqualToString:names[i]]) ? make(names[i]) : Nil;
        }
        NSMutableArray *why = [NSMutableArray array];
        MSPTapKind tap = MSPCheckClasses(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12], why);
        NSString *found = [why componentsJoinedByString:@"; "];
        if ([mode isEqualToString:@"pass"]) {
            Expect(why.count == 0, [@"the check refused: " stringByAppendingString:found ?: @""]);
            Expect(tap == (MSPTapKind)[cls1 integerValue], [NSString stringWithFormat:@"tap path %ld, expected %@", (long)tap, cls1]);
        } else {
            NSString *needle = [mode isEqualToString:@"nobase"] || [mode isEqualToString:@"noclass"] ? cls1 : [NSString stringWithFormat:@"%@]", [sel1 substringFromIndex:1]];
            Expect(why.count > 0 && tap == MSPTapNone, [NSString stringWithFormat:@"%@ %@ %@: the check passed", mode, cls1, sel1 ?: @""]);
            BOOL named = [found containsString:needle] || ([mode isEqualToString:@"noclass"] && [found containsString:@"no tap path"])
                      || ([mode isEqualToString:@"drop"] && [found containsString:@"no tap path"]);   // (the factory gone: no tap path at all is named)
            Expect(named, [NSString stringWithFormat:@"%@ %@ %@: not named (%@)", mode, cls1, sel1 ?: @"", found]);
        }
        printf("%s %s %s %s: %s%s\n", argv[1], mode.UTF8String, cls1.UTF8String ?: "", sel1.UTF8String ?: "", gFail ? "FAIL" : "ok",
               why.count && ![mode isEqualToString:@"pass"] ? [[@" -- " stringByAppendingString:found] UTF8String] : "");
        return gFail ? 1 : 0;
    }
}
