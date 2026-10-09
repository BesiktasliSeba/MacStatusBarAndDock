// test-setsearch.m -- Mac test of the Settings sidebar search field's check (macsettings/SidebarSearchCheck.h) against Apple's own classes of
// real iPadOS builds (tools/setsearch-fixtures/<build>.txt, from each build's dyld shared cache: tools/make-setsearch-fixture.py).
// test-setsearch <fixture> [pass | drop <class> <selector> | retype <class> <selector> <shape> | nobase <class> | noclass <class>]
//   pass      the check finds everything (exit 0) -- the field would be offered on that build
//   drop      that method taken out of the fixture: the check must refuse, naming it
//   retype    that method with another type shape: the check must refuse, naming it
//   nobase    that class made without its UIKit base: the check must refuse
//   noclass   that class not there at all: the check must refuse
// One build and one change per process: the classes are made at run time under Apple's names (UIKit's base classes too: a Foundation-only
// process has none of its own), and the check looks its bases up by name.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../macsettings/SidebarSearchCheck.h"

static int gFail = 0;
static void Expect(BOOL ok, NSString *what) { if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static id Dummy(id self, SEL _cmd) { return nil; }

static void TestShapes(void) {   // (the shape rules themselves, on Apple-style encodings)
    Expect([MSSShape("v24@0:8@16") isEqualToString:@"v@:@"], @"shape v24@0:8@16");
    Expect([MSSShape("@16@0:8") isEqualToString:@"@@:"], @"shape @16@0:8");
    Expect([MSSShape("v20@0:8B16") isEqualToString:@"v@:B"], @"shape v20@0:8B16");
    Expect([MSSShape("B16@0:8") isEqualToString:@"B@:"], @"shape B16@0:8");
    Expect([MSSShape("v32@0:8@16@24") isEqualToString:@"v@:@@"], @"shape v32@0:8@16@24");
    Expect([MSSShape("@\"NSString\"16@0:8") isEqualToString:@"@@:"], @"shape with a quoted class name");
    Expect([MSSShape("v32@0:8@?16@?24") isEqualToString:@"v@:@@"], @"shape with blocks");
    Expect([MSSShape("{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8") isEqualToString:@"{{dd}{dd}}@:"], @"shape with a named struct");
    Expect([MSSShape("rv16@0:8") isEqualToString:@"v@:"], @"shape with a qualifier");
    Expect([MSSExpect(@encode(void), @encode(id), NULL) isEqualToString:@"v@:@"], @"expect (void)(id)");
    Expect([MSSExpect(@encode(void), @encode(BOOL), NULL) isEqualToString:@"v@:B"], @"expect (void)(BOOL) -- BOOL as on arm64");
    Expect([MSSExpect(@encode(id), NULL) isEqualToString:@"@@:"], @"expect (id)");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: test-setsearch <fixture> pass|drop|retype|nobase ...\n"); return 2; }
        NSString *fixture = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:nil];
        if (!fixture.length) { fprintf(stderr, "no fixture %s\n", argv[1]); return 2; }
        NSString *mode = @(argv[2]);
        NSString *cls1 = argc > 3 ? @(argv[3]) : nil, *sel1 = argc > 4 ? @(argv[4]) : nil, *shape1 = argc > 5 ? @(argv[5]) : nil;
        TestShapes();
        // the class tree: UIKit's stand-ins first, then Apple's classes in the fixture under their superclasses
        NSMutableDictionary<NSString *, NSString *> *superOf = [@{@"UIViewController": @"NSObject", @"PSViewController": @"UIViewController"} mutableCopy];
        NSMutableArray<NSArray *> *rows = [NSMutableArray array];
        for (NSString *line in [fixture componentsSeparatedByString:@"\n"]) {
            if (!line.length || [line hasPrefix:@"#"]) continue;
            NSArray *f = [line componentsSeparatedByString:@" "];
            if (f.count != 4) continue;
            superOf[f[0]] = f[1];
            [rows addObject:f];
        }
        if ([mode isEqualToString:@"nobase"]) superOf[cls1] = @"NSObject";
        // drop / retype act on the class and every class above it (an inherited copy would stand in for the method otherwise)
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
        Class list = make(@"PSUIPrefsListController"), apple = make(@"PSKeyboardNavigationSearchController"), results = make(@"SUIKSearchResultsCollectionViewController");
        if ([mode isEqualToString:@"noclass"]) {   // (that class not in this iPadOS at all)
            if ([cls1 isEqualToString:@"PSUIPrefsListController"]) list = Nil;
            if ([cls1 isEqualToString:@"PSKeyboardNavigationSearchController"]) apple = Nil;
            if ([cls1 isEqualToString:@"SUIKSearchResultsCollectionViewController"]) results = Nil;
        }
        NSMutableArray *why = [NSMutableArray array];
        MSSCheckClasses(list, apple, results, why);
        NSString *found = [why componentsJoinedByString:@"; "];
        if ([mode isEqualToString:@"pass"]) {
            Expect(why.count == 0, [@"the check refused: " stringByAppendingString:found ?: @""]);
        } else {
            NSString *needle = [mode isEqualToString:@"nobase"] || [mode isEqualToString:@"noclass"] ? cls1 : [NSString stringWithFormat:@"%@]", sel1];
            Expect(why.count > 0, [NSString stringWithFormat:@"%@ %@ %@: the check passed", mode, cls1, sel1 ?: @""]);
            Expect([found containsString:needle], [NSString stringWithFormat:@"%@ %@ %@: not named (%@)", mode, cls1, sel1 ?: @"", found]);
        }
        printf("%s %s %s %s: %s%s\n", argv[1], mode.UTF8String, cls1.UTF8String ?: "", sel1.UTF8String ?: "", gFail ? "FAIL" : "ok", why.count && ![mode isEqualToString:@"pass"] ? [[@" -- " stringByAppendingString:found] UTF8String] : "");
        return gFail ? 1 : 0;
    }
}
