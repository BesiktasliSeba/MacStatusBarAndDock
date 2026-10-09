// test-tweaksearch.m -- Mac test of macsettings/TweakSearchCheck.h (the check behind TweakSearch.x: tweak settings in the Settings search and in
// Spotlight) against Apple's own classes of real iPadOS builds: tools/setsearch-fixtures/<build>.txt (the sidebar list and the results controller,
// from each build's dyld shared cache) and tools/tweaksearch-fixtures/app-<build>.txt (the Settings app's own controller, from its binary).
// test-tweaksearch <fixture> <app fixture or -> [pass | drop <class> <selector> | retype <class> <selector> <shape> | nobase <class> | noclass <class>]
// One build and one change per process (the classes are made at run time under Apple's names; UIKit's base classes are stand-ins found by name).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../macsettings/TweakSearchCheck.h"

static int gFail = 0;
static void Expect(BOOL ok, NSString *what) { if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static id Dummy(id self, SEL _cmd) { return nil; }

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 4) { fprintf(stderr, "usage: test-tweaksearch <fixture> <app fixture|-> pass|drop|retype|nobase|noclass ...\n"); return 2; }
        NSMutableString *text = [NSMutableString string];
        for (int i = 1; i <= 2; i++) {
            if (!strcmp(argv[i], "-")) continue;
            NSString *f = [NSString stringWithContentsOfFile:@(argv[i]) encoding:NSUTF8StringEncoding error:nil];
            if (!f.length) { fprintf(stderr, "no fixture %s\n", argv[i]); return 2; }
            [text appendFormat:@"%@\n", f];
        }
        BOOL haveApp = strcmp(argv[2], "-") != 0;
        NSString *mode = @(argv[3]);
        NSString *cls1 = argc > 4 ? @(argv[4]) : nil, *sel1 = argc > 5 ? @(argv[5]) : nil, *shape1 = argc > 6 ? @(argv[6]) : nil;
        NSMutableDictionary<NSString *, NSString *> *superOf = [@{@"UIViewController": @"NSObject", @"PSViewController": @"UIViewController", @"UIApplication": @"UIResponder", @"UIResponder": @"NSObject"} mutableCopy];
        NSMutableArray<NSArray *> *rows = [NSMutableArray array];
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (!line.length || [line hasPrefix:@"#"]) continue;
            NSArray *f = [line componentsSeparatedByString:@" "];
            if (f.count != 4) continue;
            superOf[f[0]] = f[1];
            [rows addObject:f];
        }
        if ([mode isEqualToString:@"nobase"]) superOf[cls1] = @"NSObject";
        NSMutableSet<NSString *> *chain = [NSMutableSet set];
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
                BOOL hit = [chain containsObject:r[0]] && [r[2] isEqualToString:sel1];
                if ([mode isEqualToString:@"drop"] && hit) continue;
                NSString *types = [mode isEqualToString:@"retype"] && hit ? shape1 : r[3];
                class_addMethod(c, sel_registerName([r[2] UTF8String]), (IMP)Dummy, types.UTF8String);
            }
            objc_registerClassPair(c);
            made[name] = c;
            return c;
        };
        make = makeRef;
        Class list = make(@"PSUIPrefsListController"), results = make(@"SUIKSearchResultsCollectionViewController"), app = haveApp ? make(@"PreferencesAppController") : Nil;
        if ([mode isEqualToString:@"noclass"]) {
            if ([cls1 isEqualToString:@"PSUIPrefsListController"]) list = Nil;
            if ([cls1 isEqualToString:@"SUIKSearchResultsCollectionViewController"]) results = Nil;
            if ([cls1 isEqualToString:@"PreferencesAppController"]) app = Nil;
        }
        NSMutableArray *whyResults = [NSMutableArray array], *whyOpening = [NSMutableArray array];
        MTSCheckResults(list, results, whyResults);
        MTSCheckOpening(app, whyOpening);
        BOOL appCase = [cls1 isEqualToString:@"PreferencesAppController"];
        NSMutableArray *why = appCase ? whyOpening : whyResults;
        NSString *found = [why componentsJoinedByString:@"; "];
        if ([mode isEqualToString:@"pass"]) {
            Expect(whyResults.count == 0, [@"the results check refused: " stringByAppendingString:[whyResults componentsJoinedByString:@"; "]]);
            if (haveApp) Expect(whyOpening.count == 0, [@"the opening check refused: " stringByAppendingString:[whyOpening componentsJoinedByString:@"; "]]);
            else Expect(whyOpening.count > 0, @"no app fixture, yet the opening check passed");
        } else {
            NSString *needle = [mode isEqualToString:@"nobase"] || [mode isEqualToString:@"noclass"] ? cls1 : [NSString stringWithFormat:@"%@]", sel1];
            Expect(why.count > 0, [NSString stringWithFormat:@"%@ %@ %@: the check passed", mode, cls1, sel1 ?: @""]);
            Expect([found containsString:needle], [NSString stringWithFormat:@"%@ %@ %@: not named (%@)", mode, cls1, sel1 ?: @"", found]);
            NSMutableArray *other = appCase ? whyResults : whyOpening;   // (the other part is not touched by this change)
            if (appCase || haveApp) Expect(other.count == 0, [NSString stringWithFormat:@"%@ %@ %@: the other check refused too (%@)", mode, cls1, sel1 ?: @"", [other componentsJoinedByString:@"; "]]);
        }
        printf("%s %s %s %s: %s\n", argv[1], mode.UTF8String, cls1.UTF8String ?: "", sel1.UTF8String ?: "", gFail ? "FAIL" : "ok");
        return gFail ? 1 : 0;
    }
}
