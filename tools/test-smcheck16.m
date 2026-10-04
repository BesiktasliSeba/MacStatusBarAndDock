// test-smcheck16.m -- Mac test of the Stage Manager engine's start-up self-check (statusbar/SMEngineAPI.h) against the API tables of real
// iPadOS 16 builds, and of what Settings and Report a Problem say about it (common/StageManagerAvailable.h). sm-163, 4 Oct 2026.
// Why: the check is the only thing between an iPadOS build and the engine; on 16.2-16.3 it failed on one method the engine only needs when another
// engine takes over (-[SBAppLayout appLayoutByRemovingItemInLayoutRole:], new in 16.4), so the Window Engine row was greyed there (a tester on
// 16.3.1). The fixtures (tools/smcheck-fixtures/<build>.txt, tools/make-smcheck-fixture.py) are those builds' classes, methods and type encodings
// as their dyld_shared_cache has them. This builds them as runtime classes and runs the REAL check code on them, one build per process (the check
// caches classes), then checks:
//  1. the verdict: which core rows fail (engine off), which optional rows are missing, which features are left without any alternative;
//  2. the cut-back choice when another engine takes over: 16.4+ removes windows one by one, exactly as 1.3.1 did (the 1.3.1 loop is kept below
//     as the reference: same result, same calls), 16.2-16.3 take Apple's leaf stage; the debug simulation "optional" takes the leaf on any build;
//  3. the Settings footer and the Report a Problem line for that state (exact text, no em dash, the failed rows named, the length cap).
// Run: tools/test-smcheck16.sh (every fixture with its expected verdict).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
// ---- what StatusBar.x defines before including SMEngineAPI.h (stand-ins, as in test-smlayout17.m) ----
typedef struct UIEdgeInsets { CGFloat top, left, bottom, right; } UIEdgeInsets;
@interface UIScreen : NSObject
+ (NSArray *)screens;
@end
@implementation UIScreen
+ (NSArray *)screens { return @[]; }
@end
#define NSStringFromCGRect(r) NSStringFromRect(NSRectFromCGRect(r))
#define NSStringFromCGPoint(p) NSStringFromPoint(NSPointFromCGPoint(p))
#define NSStringFromCGSize(s) NSStringFromSize(NSSizeFromCGSize(s))
static NSMutableArray<NSString *> *gLog;
#define DMLog(...) [gLog addObject:(__VA_ARGS__)]
#define DMTestFlag(path) 0
#define MSB_DOMAIN CFSTR("com.besiktasliseba.test-smcheck16")
static id DMCall(id obj, NSString *name) { SEL s = NSSelectorFromString(name); return obj && [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil; }
typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long type; } DMSMAttributedSize;
#include "../common/StageManagerAvailable.h"
#include "../statusbar/SMEngineAPI.h"
static void DMSM17DiagSoon(void) {}

static int gFails = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    if (!ok) gFails++;
    printf("%s  %-74s %s\n", ok ? "PASS" : "FAIL", what.UTF8String, ok ? "" : (got.UTF8String ?: ""));
}

// ---- the fixture as runtime classes ----
static id FixtureIMP(id self, SEL _cmd) { return nil; }   // (never called by the check: it only looks at names and encodings)
static NSDictionary<NSString *, NSString *> *gSupers;
static NSMutableDictionary<NSString *, NSMutableArray *> *gIvars;
static Class MakeClass(NSString *name) {
    Class c = objc_getClass(name.UTF8String);
    if (c) return c;
    NSString *sup = gSupers[name] ?: @"NSObject";
    Class s = MakeClass(sup);
    c = objc_allocateClassPair(s, name.UTF8String, 0);
    for (NSArray *iv in gIvars[name]) {
        NSUInteger size = 0, align = 0;
        NSGetSizeAndAlignment([iv[1] UTF8String], &size, &align);
        uint8_t lg = 0; while ((1u << lg) < align) lg++;
        class_addIvar(c, [iv[0] UTF8String], size, lg, [iv[1] UTF8String]);
    }
    objc_registerClassPair(c);
    return c;
}
static NSString *gTitle;
static NSMutableSet<NSString *> *gDefined;   // ("Class -sel" lines the fixture has)
static BOOL LoadFixture(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return NO;
    NSMutableDictionary *supers = [NSMutableDictionary dictionary];
    gIvars = [NSMutableDictionary dictionary]; gDefined = [NSMutableSet set];
    NSMutableArray *methods = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"# "] && !gTitle) { gTitle = [line substringFromIndex:2]; continue; }
        NSArray *f = [line componentsSeparatedByString:@"\t"];
        if ([f[0] isEqualToString:@"class"] && f.count == 3) supers[f[1]] = f[2];
        else if ([f[0] isEqualToString:@"method"] && f.count == 5) [methods addObject:f];
        else if ([f[0] isEqualToString:@"ivar"] && f.count == 4) { if (!gIvars[f[1]]) gIvars[f[1]] = [NSMutableArray array]; [gIvars[f[1]] addObject:@[f[2], f[3]]]; }
    }
    gSupers = supers;
    for (NSString *c in supers) MakeClass(c);
    for (NSArray *f in methods) {
        Class c = MakeClass(f[1]);
        Class target = [f[2] isEqualToString:@"+"] ? object_getClass(c) : c;
        class_addMethod(target, sel_registerName([f[3] UTF8String]), (IMP)FixtureIMP, [f[4] UTF8String]);
        [gDefined addObject:[NSString stringWithFormat:@"%@ %@%@", f[1], f[2], f[3]]];
    }
    return YES;
}

// ---- stand-in stages for the cut-back test: an SBAppLayout of the fixture's class, its windows in Apple's order (item 0 role 1, item 1 role 2,
// item n >= 2 role n + 3: -[SBAppLayout layoutRoleForItem:], 16.3.1 and 17.6.1), each with attributes of the fixture's attributes class ----
static char kItemsKey, kAttrsKey;
static int gRemoveCalls = 0, gLeafCalls = 0;
static NSMutableArray<NSNumber *> *gRemovedRoles;
static id NewStage(NSArray *items) {
    id s = [[objc_getClass("SBAppLayout") alloc] init];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (id it in items) map[it] = [[objc_getClass("SBDisplayItemLayoutAttributes") alloc] init];
    objc_setAssociatedObject(s, &kItemsKey, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(s, &kAttrsKey, map, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return s;
}
static NSArray *StageItems(id s) { return objc_getAssociatedObject(s, &kItemsKey); }
static long long RoleAt(NSUInteger i) { return i == 0 ? 1 : i == 1 ? 2 : (long long)i + 3; }
static id StageMapIMP(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kAttrsKey); }
static long long StageRoleIMP(id self, SEL _cmd, id item) { NSUInteger i = [StageItems(self) indexOfObject:item]; return i == NSNotFound ? 0 : RoleAt(i); }
static id StageRemoveIMP(id self, SEL _cmd, long long role) {
    gRemoveCalls++; [gRemovedRoles addObject:@(role)];
    NSMutableArray *items = [StageItems(self) mutableCopy];
    for (NSUInteger i = 0; i < items.count; i++) if (RoleAt(i) == role) { [items removeObjectAtIndex:i]; break; }
    return NewStage(items);
}
static id StageLeafIMP(id self, SEL _cmd, long long role) {
    gLeafCalls++;
    NSArray *items = StageItems(self);
    for (NSUInteger i = 0; i < items.count; i++) if (RoleAt(i) == role) return items.count == 1 && role == 1 ? self : NewStage(@[items[i]]);
    return nil;
}
static id AttrsInitIMP(id self, SEL _cmd) { return self; }
static void MakeStagesFunctional(void) {
    Method init = class_getInstanceMethod(objc_getClass("SBDisplayItemLayoutAttributes"), @selector(init));   // (the fixture's -init is a stand-in that returns nil)
    if (init) method_setImplementation(init, (IMP)AttrsInitIMP);
    Class c = objc_getClass("SBAppLayout");
    struct { const char *sel; IMP imp; } fns[] = {{"itemsToLayoutAttributesMap", (IMP)StageMapIMP}, {"layoutRoleForItem:", (IMP)StageRoleIMP},
                                                   {"appLayoutByRemovingItemInLayoutRole:", (IMP)StageRemoveIMP}, {"leafAppLayoutForRole:", (IMP)StageLeafIMP}};
    for (size_t i = 0; i < sizeof(fns) / sizeof(fns[0]); i++) {
        Method m = c ? class_getInstanceMethod(c, sel_registerName(fns[i].sel)) : NULL;
        if (m) method_setImplementation(m, fns[i].imp);   // (only what the build has: a missing method stays missing)
    }
}
// The 1.3.1 cut-back (StatusBar.x DMSMFlattenStages before sm-163, the per-stage part, verbatim): the reference on 16.4+.
static id CutBack131(id al) {
    NSDictionary *map = DMSMStageItemsMap(al);
    if (map.count < 2) return nil;
    id single = al;
    for (int guard = 0; guard < 8; guard++) {
        NSDictionary *left = DMSMStageItemsMap(single);
        if (left.count < 2) break;
        long drop = 0;
        for (id item in left) { long role = (long)DMSMRoleOr(single, item, 0); if (role > 1) { drop = role; break; } }
        if (!drop) break;
        id next = DMSMStageWithoutRole(single, drop);
        if (!next || next == single) break;
        single = next;
    }
    return single;
}
static NSString *Join(NSArray *a) { return [a componentsJoinedByString:@" | "]; }
static NSSet *SetOf(NSString *s) {
    NSMutableSet *m = [NSMutableSet set];
    for (NSString *x in [s componentsSeparatedByString:@"|"]) { NSString *t = [x stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if (t.length) [m addObject:t]; }
    return m;
}
static NSSet *Stripped(NSArray *lines) {   // ("<problem> (<feature>)" -> "<problem>")
    NSMutableSet *m = [NSMutableSet set];
    for (NSString *l in lines) { NSRange r = [l rangeOfString:@" ("]; [m addObject:r.location == NSNotFound ? l : [l substringToIndex:r.location]]; }
    return m;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        gLog = [NSMutableArray array]; gRemovedRoles = [NSMutableArray array];
        // args: fixture, expected core failures ("a|b", "" = none), expected optional rows missing, expected features off, cut ("remove"/"leaf"),
        // the iPadOS version shown
        if (argc < 7) { fprintf(stderr, "usage: %s fixture core optional off cut os\n", argv[0]); return 2; }
        NSString *fixture = @(argv[1]), *wantCore = @(argv[2]), *wantOpt = @(argv[3]), *wantOff = @(argv[4]), *wantCut = @(argv[5]), *os = @(argv[6]);
        if (!LoadFixture(fixture)) { printf("FAIL  cannot read %s\n", argv[1]); return 1; }
        printf("== %s\n", gTitle.UTF8String);
        // 1. the verdict, from the same code SpringBoard runs (DMSMCheckAPILive: core problems, optional rows, features off, each row's answer)
        NSUInteger checked = 0;
        gSMLayoutGen = 16;
        NSArray *bad = DMSMCheckAPILive(nil, &checked);
        Check(@"core rows that fail (the engine stays off when any does)", [[NSSet setWithArray:bad] isEqualToSet:SetOf(wantCore)], Join(bad));
        Check(@"optional rows not here", [Stripped(gSMCheckOptional) isEqualToSet:SetOf(wantOpt)], Join(gSMCheckOptional));
        Check(@"features left with none of their alternatives", [[NSSet setWithArray:gSMFeaturesOff ?: @[]] isEqualToSet:SetOf(wantOff)], Join(gSMFeaturesOff));
        BOOL engineOn = bad.count == 0;
        Check(engineOn ? @"engine ON: every core row there with our signature (76 rows, less the optional ones missing)" : @"engine OFF on this build", engineOn ? checked == 76 - gSMCheckOptional.count : wantCore.length > 0,
              [NSString stringWithFormat:@"%lu compared", (unsigned long)checked]);
        // (every core row's class and method is in the fixture when the engine is on: the fixture is complete for what the check asks)
        BOOL rowsAgree = YES;
        for (size_t i = 0; i < kSMNeedsCount; i++) if (DMSMRowActive(&kSMNeeds[i], 16) && kSMNeeds[i].need == DMSMNeedCore && !kSMNeeds[i].ivar) {
            if (gSMRowPassed[i] != ([bad indexOfObjectPassingTest:^BOOL(NSString *l, NSUInteger k, BOOL *stop) { return [l containsString:[NSString stringWithFormat:@"%s %s]", kSMNeeds[i].cls, kSMNeeds[i].sel]] || [l containsString:[NSString stringWithFormat:@"class %s missing", kSMNeeds[i].cls]]; }] == NSNotFound)) rowsAgree = NO;
        }
        Check(@"per-row answers (DMSMRowPassed) agree with the core list", rowsAgree, @"");
        // the 1.3.1 verdict on this build, from the same rows: the two that were core then (the removing method; -containerBounds, which every
        // build with the ivar also has as a method -- the ivar is what the code reads) counted as core again
        BOOL removing = DMSMRowPassed("SBAppLayout", "appLayoutByRemovingItemInLayoutRole:");
        BOOL v131 = engineOn && removing && DMSMRowPassed("SBSwitcherChamoisLayoutAttributes", "_containerBounds");
        printf("      1.3.1 verdict here: %s; sm-163: %s\n", v131 ? "engine on" : "engine OFF (greyed: Not Supported Yet)", engineOn ? "engine on" : "engine OFF");
        // 2. the cut-back when another engine takes over
        MakeStagesFunctional();
        BOOL unsupported = NO;
        gRemoveCalls = gLeafCalls = 0; [gRemovedRoles removeAllObjects];
        id cut = DMSMStageCutToPrimary(NewStage(@[@"A", @"B", @"C"]), &unsupported);
        NSArray *left = cut ? StageItems(cut) : nil;
        NSString *path = gRemoveCalls ? @"remove" : gLeafCalls ? @"leaf" : @"none";
        Check([NSString stringWithFormat:@"cut-back of a 3-window stage: %@ path, primary window alone", wantCut], [path isEqualToString:wantCut] && [left isEqualToArray:@[@"A"]] && !unsupported,
              [NSString stringWithFormat:@"path %@, left %@, unsupported %d", path, left, unsupported]);
        Check(@"a single-window stage is left as it is", DMSMStageCutToPrimary(NewStage(@[@"A"]), &unsupported) == nil && !unsupported, @"");
        if ([wantCut isEqualToString:@"remove"]) {   // (16.4+: identical to 1.3.1 -- the same result through the same removals)
            int calls = gRemoveCalls; NSArray *roles = [gRemovedRoles copy];
            NSArray *items[] = {@[@"A", @"B"], @[@"A", @"B", @"C"], @[@"A", @"B", @"C", @"D"]};
            BOOL same = YES;
            for (int k = 0; k < 3; k++) {
                gRemoveCalls = 0; [gRemovedRoles removeAllObjects];
                id oldCut = CutBack131(NewStage(items[k])); NSArray *oldLeft = StageItems(oldCut); int oldCalls = gRemoveCalls; NSArray *oldRoles = [gRemovedRoles copy];
                gRemoveCalls = 0; [gRemovedRoles removeAllObjects];
                id newCut = DMSMStageCutToPrimary(NewStage(items[k]), NULL); NSArray *newLeft = StageItems(newCut);
                same = same && [oldLeft isEqualToArray:newLeft] && oldCalls == gRemoveCalls && [oldRoles isEqualToArray:gRemovedRoles] && gLeafCalls == 0;
            }
            Check(@"16.4+: the cut-back is the 1.3.1 loop exactly (2-4 windows: result, calls, roles)", same && calls == 2, [NSString stringWithFormat:@"first run %d calls, roles %@", calls, roles]);
            // the debug simulation of 16.2-16.3 (/tmp/msb-sm-simulate-missing "optional") on this build: engine stays on, the leaf is taken
            NSArray *simBad = DMSMCheckAPILive(@"optional", NULL);
            gRemoveCalls = gLeafCalls = 0;
            id simCut = DMSMStageCutToPrimary(NewStage(@[@"A", @"B", @"C"]), NULL);
            Check(@"simulated 16.2-16.3 here: engine on, removing listed as optional, leaf taken", simBad.count == 0 && gSMCheckOptional.count == 1 && gLeafCalls == 1 && gRemoveCalls == 0 && [StageItems(simCut) isEqualToArray:@[@"A"]],
                  [NSString stringWithFormat:@"core %@, optional %@, leaf %d remove %d", Join(simBad), Join(gSMCheckOptional), gLeafCalls, gRemoveCalls]);
            DMSMCheckAPILive(nil, NULL);   // (back to the build's own answers)
            // the existing simulations still keep the engine off
            Check(@"simulated changed core rows (selector / encoding) still fail", DMSMCheckAPI(@"selector", NULL).count == 1 && DMSMCheckAPI(@"encoding", NULL).count == 1, @"");
        }
        // 3. what Settings and Report a Problem say about this build
        NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:@{@"build": @"TEST", @"ok": @(engineOn)}];
        if (bad.count) record[@"details"] = bad;
        if (gSMCheckOptional.count) record[@"optional"] = gSMCheckOptional;
        NSString *footer = MSBDStageManagerWhyText(0, engineOn ? 1 : 0, os);
        NSString *line = MSBDStageManagerReportLineFor(0, @"native", engineOn ? 1 : 0, record, os, @"TEST", 900);
        if (engineOn) Check(@"Settings: no footer, the row can be picked", footer == nil, footer);
        else Check(@"Settings footer names the version", [footer isEqualToString:[NSString stringWithFormat:@"Stage Manager isn't supported on iPadOS %@ yet.", os]], footer);
        BOOL named = YES;
        for (NSString *l in bad) named = named && [line containsString:l];
        for (NSString *l in gSMCheckOptional) named = named && [line containsString:l];
        Check(@"Report a Problem line: verdict and every failed / missing row by name", named && [line hasPrefix:engineOn ? @"- Stage Manager engine check: passed" : @"- Stage Manager engine check: failed"], line);
        NSString *shortLine = MSBDStageManagerReportLineFor(0, @"native", engineOn ? 1 : 0, record, os, @"TEST", 80);
        Check(@"Report a Problem line stays short when the link is too long", shortLine.length < 300 && (bad.count < 2 || [shortLine containsString:@"..."]), shortLine);
        Check(@"no em dash in what users read", ![footer ?: @"" containsString:@"—"] && ![line containsString:@"—"], @"");
        printf("      Report a Problem: %s", line.UTF8String);
        if (footer) printf("      Settings footer: %s\n", footer.UTF8String);
        // the other reasons (same for every build): no Stage Manager on this iPad, iPadOS 16.0, not checked yet
        Check(@"footer: an iPad without Stage Manager", [MSBDStageManagerWhyText(2, -1, os) isEqualToString:@"This iPad doesn't have Stage Manager (TrollPad can add it)."], MSBDStageManagerWhyText(2, -1, os));
        Check(@"footer: iPadOS 16.0", [MSBDStageManagerWhyText(1, -1, @"16.0") isEqualToString:@"Stage Manager needs iPadOS 16.1 or later."], MSBDStageManagerWhyText(1, -1, @"16.0"));
        Check(@"footer: not checked on this build yet", [MSBDStageManagerWhyText(0, -1, os) isEqualToString:@"Respring once to check Stage Manager on this iPadOS version."], MSBDStageManagerWhyText(0, -1, os));
        NSString *noSM = MSBDStageManagerReportLineFor(2, @"Stage Manager model no, TrollPad no, MobileGestalt no", -1, nil, os, @"TEST", 900);
        Check(@"report: an iPad without Stage Manager says which sources were asked", [noSM isEqualToString:@"- Stage Manager: not on this iPad (Stage Manager model no, TrollPad no, MobileGestalt no)\n"], noSM);
        NSString *unchecked = MSBDStageManagerReportLineFor(0, @"TrollPad", -1, nil, os, @"TEST", 900);
        Check(@"report: not checked yet", [unchecked hasPrefix:@"- Stage Manager engine check: not run yet ("] && [unchecked containsString:@"TrollPad"], unchecked);
        printf("%s %s\n", gFails ? "FAILED" : "ok", gTitle.UTF8String);
        return gFails ? 1 : 0;
    }
}
