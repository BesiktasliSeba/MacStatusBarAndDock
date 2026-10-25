// test-a5resolve.m -- Mac test of the Aerial 5.x role resolver (statusbar/AerialResolve.h) on the method lists of two Aerial builds.
// The lists and the expected names are private (tools/a5resolve-fixtures: method lists of a closed-source tweak, kept out of the public source
// tree): aerial-5.0.txt and aerial-5.1.txt as the debug trigger imgdump_ lists the two classes the resolver reads, in the order of their code, and
// expect-5.0.txt with the role -> name map the resolver found for 5.0 on a device. Both builds must give that map; 5.1 also has real-named methods
// inside the run the rule reads, which the rule must take. Also: the shapes that must still be refused (a scrambled method of another kind in the
// run, a run of five or of three, an extra no-argument BOOL), built from each list with made-up names. Without the fixtures: skipped.
#import <Foundation/Foundation.h>
#import "../statusbar/AerialResolve.h"

static int gFail = 0, gN = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
// One list file -> the two lists the resolver takes (types as DMA5Types makes them).
static void Load(NSString *path, NSMutableArray *stage, NSMutableArray *core) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSString *cls = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"class "]) { cls = [[line substringFromIndex:6] componentsSeparatedByString:@" "][0]; continue; }
        if (line.length < 4 || ![line hasPrefix:@"  "]) continue;
        unichar kind = [line characterAtIndex:2];
        NSArray *parts = [[line substringFromIndex:3] componentsSeparatedByString:@" "];
        if (parts.count < 2) continue;
        NSArray *entry = @[parts[0], DMA5Types([parts[1] UTF8String])];
        if ([cls isEqualToString:@"AerialStage"] && kind == '-') [stage addObject:entry];
        if ([cls isEqualToString:@"AerialCore"] && kind == '+') [core addObject:entry];
    }
}
// The expected map: "role name" per line ('#' lines are notes).
static NSDictionary<NSString *, NSString *> *LoadExpect(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSRange sp = [line rangeOfString:@" "];
        if (sp.location == NSNotFound) continue;
        m[[line substringToIndex:sp.location]] = [line substringFromIndex:sp.location + 1];
    }
    return m;
}
// A made-up scrambled name of the builds' shape (prefix and 15 letters I/l from the bits), never one of a real build's.
static NSString *Fake(unsigned bits, NSString *tail) {
    NSMutableString *s = [NSMutableString stringWithString:@"Aerial_"];
    for (int i = 14; i >= 0; i--) [s appendString:(bits >> i) & 1 ? @"l" : @"I"];
    [s appendString:tail ?: @""];
    return s;
}
static NSDictionary *Resolve(NSArray *stage, NSArray *core, NSMutableArray *missing, BOOL *t) { return DMA5ResolveRoles(stage, core, missing, t); }
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *dir = argc > 1 ? @(argv[1]) : @"a5resolve-fixtures";
        NSDictionary<NSString *, NSString *> *expect = LoadExpect([dir stringByAppendingPathComponent:@"expect-5.0.txt"]);
        if (!expect.count) { printf("test-a5resolve: skipped (no expected map)\n"); return 0; }
        Expect(expect.count >= 10, [NSString stringWithFormat:@"expected map read (%lu roles)", (unsigned long)expect.count]);
        NSString *simulName = @"gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:";
        for (NSString *v in @[@"5.0", @"5.1"]) {
            NSMutableArray *stage = [NSMutableArray array], *core = [NSMutableArray array], *missing = [NSMutableArray array];
            Load([dir stringByAppendingPathComponent:[NSString stringWithFormat:@"aerial-%@.txt", v]], stage, core);
            Expect(stage.count > 60 && core.count > 15, [NSString stringWithFormat:@"%@: list read (%lu stage, %lu core methods)", v, (unsigned long)stage.count, (unsigned long)core.count]);
            BOOL t = NO;
            NSDictionary *m = Resolve(stage, core, missing, &t);
            Expect(m != nil && !missing.count, [NSString stringWithFormat:@"%@: every role resolved (missing: %@)", v, [missing componentsJoinedByString:@", "]]);
            Expect(t, [NSString stringWithFormat:@"%@: minimize takes a transform", v]);
            for (NSString *k in expect) Expect([m[k] isEqualToString:expect[k]], [NSString stringWithFormat:@"%@: role %@ as expected", v, k]);
            Expect(m.count == expect.count, [NSString stringWithFormat:@"%@: %lu roles", v, (unsigned long)m.count]);
            NSInteger simul = DMA5Index(stage, simulName), rm = DMA5Index(stage, @"removeFromSuperview");
            if ([v isEqualToString:@"5.1"]) {
                BOOL realInRun = NO;
                for (NSInteger i = simul + 1; simul >= 0 && i < rm; i++) if (!DMA5Scrambled(stage[i][0])) realInRun = YES;
                Expect(realInRun, @"5.1: a real-named method sits in the run (the case the rule must take)");
                Expect(simul != rm - 5, @"5.1: the old run rule (removeFromSuperview minus 5) does not hold there");
            }
            // shapes that must be refused (built from this build's list, with made-up names)
            NSMutableArray *bad = [stage mutableCopy]; [bad insertObject:@[Fake(0x0000, @":"), @"v@:@"] atIndex:rm];   // a scrambled method of another kind in the run
            NSMutableArray *miss = [NSMutableArray array];
            Expect(!Resolve(bad, core, miss, NULL) && [miss containsObject:@"ensureSceneVisible"], [NSString stringWithFormat:@"%@: a scrambled v@:@ in the run is refused", v]);
            bad = [stage mutableCopy]; [bad insertObject:@[Fake(0x0001, nil), @"v@:"] atIndex:rm]; miss = [NSMutableArray array];   // five in the run
            Expect(!Resolve(bad, core, miss, NULL) && [miss containsObject:@"removeStageSafely"], [NSString stringWithFormat:@"%@: a run of five is refused", v]);
            bad = [stage mutableCopy]; [bad removeObjectAtIndex:rm - 1]; miss = [NSMutableArray array];   // three in the run
            Expect(!Resolve(bad, core, miss, NULL) && [miss containsObject:@"adjustContentScaleToHost"], [NSString stringWithFormat:@"%@: a run of three is refused", v]);
            bad = [stage mutableCopy]; [bad insertObject:@[@"someNewRealMethod:", @"v@:@"] atIndex:rm]; miss = [NSMutableArray array];   // a real-named addition of any kind
            NSDictionary *m2 = Resolve(bad, core, miss, NULL);
            Expect([m2 isEqualToDictionary:m], [NSString stringWithFormat:@"%@: a real-named method added in the run is skipped", v]);
            bad = [stage mutableCopy]; [bad addObject:@[Fake(0x0002, nil), @"B@:"]]; miss = [NSMutableArray array];   // a second no-argument BOOL
            Expect(!Resolve(bad, core, miss, NULL) && [miss containsObject:@"handleResizeBR:"], [NSString stringWithFormat:@"%@: a second B@: is refused", v]);
        }
        printf("test-a5resolve: %d checks, %d failed\n", gN, gFail);
        return gFail ? 1 : 0;
    }
}
