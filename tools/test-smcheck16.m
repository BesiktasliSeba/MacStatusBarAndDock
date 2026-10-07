// test-smcheck16.m -- Mac test of the Stage Manager engine's start-up self-check (statusbar/SMEngineAPI.h) against the API tables of real
// iPadOS 16 builds, and of what Settings and Report a Problem say about it (common/StageManagerAvailable.h). sm-163 / sm-160, 4 Oct 2026.
// Why: the check is the only thing between an iPadOS build and the engine. On 16.2-16.3 it failed on one method the engine only needs when another
// engine takes over (-[SBAppLayout appLayoutByRemovingItemInLayoutRole:], new in 16.4), so the Window Engine row was greyed there (a tester on
// 16.3.1). On 16.0 and 16.1 whole jobs are done by other methods (sm-160): the window's size and centre are plain values, and 16.0 has its own layout
// pass and size grid -- the check now finds those ways as variants and the engine uses them. The fixtures (tools/smcheck-fixtures/<build>.txt,
// tools/make-smcheck-fixture.py) are those builds' classes, methods and type encodings as their dyld_shared_cache has them. This builds them as
// runtime classes and runs the REAL check code on them, one build per process (the check caches classes), then checks:
//  1. the verdict: core rows that fail (engine off), optional rows missing, features left with no alternative, and which way (variant) the check
//     chose for each job -- 16.2+ always the first, tested one;
//  2. iPadOS 16.0 / 16.1's "sized" window model: Apple's reading of a size and centre (fraction up to 1 on 16.0, up to 10 on 16.1, else points)
//     played by stand-ins with that behaviour; the check's probe must find it, and the engine's wrappers must hand over and read back each window;
//  3. the cut-back choice when another engine takes over: 16.4+ removes windows one by one, exactly as 1.3.1 did (the 1.3.1 loop is kept below as
//     the reference: same result, same calls), 16.0-16.3 take Apple's leaf stage; the debug simulation "optional" takes the leaf on any build;
//  4. the Settings footer and the Report a Problem line for that state (exact text, no em dash, the failed rows or other ways named, the cap), and
//     whether Settings offers Stage Manager as "(Untested)" with its note: on iPadOS 16.0 only -- 16.1's own way is offered normally (owner, 4 Oct).
// Run: tools/test-smcheck16.sh (every fixture with its expected verdict).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
// ---- what StatusBar.x defines before including SMEngineAPI.h (stand-ins, as in test-smlayout17.m) ----
typedef struct UIEdgeInsets { CGFloat top, left, bottom, right; } UIEdgeInsets;
static CGRect gScreen = {{0, 0}, {1024, 768}};   // (the screen the "sized" wrappers measure in: landscape 9.7")
@interface UIScreen : NSObject
+ (NSArray *)screens;
+ (instancetype)mainScreen;
- (CGRect)bounds;
@end
@implementation UIScreen
+ (NSArray *)screens { return @[]; }
+ (instancetype)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; }
- (CGRect)bounds { return gScreen; }
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
// (UIKit's NSValue additions, which SMEngineAPI.h uses on the device -- the iPadOS 17 layout pass, DMSM17PassBegin/End; macOS has the NSPoint/NSSize
//  ones. The same stand-in as test-smlayout17.m.)
@interface NSValue (DMTestCG)
+ (NSValue *)valueWithCGPoint:(CGPoint)p;
+ (NSValue *)valueWithCGSize:(CGSize)z;
- (CGPoint)CGPointValue;
- (CGSize)CGSizeValue;
@end
@implementation NSValue (DMTestCG)
+ (NSValue *)valueWithCGPoint:(CGPoint)p { return [NSValue valueWithPoint:NSPointFromCGPoint(p)]; }
+ (NSValue *)valueWithCGSize:(CGSize)z { return [NSValue valueWithSize:NSSizeFromCGSize(z)]; }
- (CGPoint)CGPointValue { return NSPointToCGPoint(self.pointValue); }
- (CGSize)CGSizeValue { return NSSizeToCGSize(self.sizeValue); }
@end
#include "../common/StageManagerAvailable.h"
#include "../statusbar/SMEngineAPI.h"
static void DMSM17DiagSoon(void) {}

static int gFails = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    if (!ok) gFails++;
    printf("%s  %-78s %s\n", ok ? "PASS" : "FAIL", what.UTF8String, ok ? "" : (got.UTF8String ?: ""));
}
static BOOL Near(double a, double b) { return isfinite(a) && fabs(a - b) < 0.01; }

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
static BOOL LoadFixture(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return NO;
    NSMutableDictionary *supers = [NSMutableDictionary dictionary];
    gIvars = [NSMutableDictionary dictionary];
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
    }
    return YES;
}

// ---- iPadOS 16.0 / 16.1's "sized" window model, played by stand-ins with Apple's behaviour (decompiled from 20A371 / 20B82): a plain size and
// centre; -sizeInBounds: / -centerInBounds: give a value back as a fraction of the bounds while both parts are at most the edge (1 on 16.0, 10 on
// 16.1), else as points; -attributesByModifyingSize: / Center: a copy with that value ----
static char kSizeKey, kCenterKey;
static double gEdge = 0;
static id AttrsInitIMP(id self, SEL _cmd) { return self; }
static CGSize Stored(id self, const void *key) { NSValue *v = objc_getAssociatedObject(self, key); return v ? v.sizeValue : CGSizeZero; }
static id CopyWith(id self, const void *key, CGSize v) {
    id n = [[object_getClass(self) alloc] init];
    objc_setAssociatedObject(n, &kSizeKey, [NSValue valueWithSize:Stored(self, &kSizeKey)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(n, &kCenterKey, [NSValue valueWithSize:Stored(self, &kCenterKey)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(n, key, [NSValue valueWithSize:v], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return n;
}
static CGSize InBounds(CGSize v, CGRect b) { return v.width <= gEdge && v.height <= gEdge ? CGSizeMake(v.width * b.size.width, v.height * b.size.height) : v; }
static id WithSizeIMP(id self, SEL _cmd, CGSize s) { return CopyWith(self, &kSizeKey, s); }
static id WithCenterIMP(id self, SEL _cmd, CGPoint c) { return CopyWith(self, &kCenterKey, CGSizeMake(c.x, c.y)); }
static CGSize SizeInBoundsIMP(id self, SEL _cmd, CGRect b) { return InBounds(Stored(self, &kSizeKey), b); }
static CGPoint CenterInBoundsIMP(id self, SEL _cmd, CGRect b) { CGSize v = InBounds(Stored(self, &kCenterKey), b); return CGPointMake(v.width, v.height); }
static long long ZeroLongIMP(id self, SEL _cmd) { return 0; }
static id SelfLongIMP(id self, SEL _cmd, long long v) { return self; }
static void MakeAttributesFunctional(double edge) {
    gEdge = edge;
    Class c = objc_getClass("SBDisplayItemLayoutAttributes");
    struct { const char *sel; IMP imp; } fns[] = {{"init", (IMP)AttrsInitIMP}, {"attributesByModifyingSize:", (IMP)WithSizeIMP}, {"attributesByModifyingCenter:", (IMP)WithCenterIMP},
                                                   {"sizeInBounds:", (IMP)SizeInBoundsIMP}, {"centerInBounds:", (IMP)CenterInBoundsIMP},
                                                   {"lastInteractionTime", (IMP)ZeroLongIMP}, {"sizingPolicy", (IMP)ZeroLongIMP},
                                                   {"attributesByModifyingSizingPolicy:", (IMP)SelfLongIMP}, {"attributesByModifyingLastInteractionTime:", (IMP)SelfLongIMP}};
    for (size_t i = 0; i < sizeof(fns) / sizeof(fns[0]); i++) {
        Method m = c ? class_getInstanceMethod(c, sel_registerName(fns[i].sel)) : NULL;
        if (m) method_setImplementation(m, fns[i].imp);   // (only what the build has)
    }
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
// iPadOS 16.0's group shift after its layout pass, as its calculator's block computes it (decoded from 20A371 / 20A5349b, -[SBDisplayItemLayout
// AttributesCalculator _appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...]_block_invoke_3): left-to-right min(0, max(stage x, container
// centre - group width / 2) - group x), right-to-left max(0, min(stage max x, container centre + group width / 2) - group max x).
static CGFloat AppleShift160(BOOL rtl, CGRect stage, CGRect container, CGRect group) {
    if (rtl) return MAX(0.0, MIN(CGRectGetMaxX(stage), CGRectGetMidX(container) + group.size.width / 2) - CGRectGetMaxX(group));
    return MIN(0.0, MAX(stage.origin.x, CGRectGetMidX(container) - group.size.width / 2) - group.origin.x);
}
// The calculator's order, played through the engine's helpers as SMLayout160's hooks call them: the calculator runs (Enter), its layout pass
// (Begin ... a centre set during the pass ... End), then the block moves the bounding box and each centre by the shift, then the calculator returns
// (Exit), then a later centre (a drag) comes. Returns the x each call ends up with: pass, box, centre, after.
typedef struct { CGFloat pass, box, centre, after; } Calc160Run;
static Calc160Run PlayCalculator160(BOOL inCalculator, BOOL freePlacement, BOOL rtl, CGRect group) {
    CGRect stage = CGRectMake(0, 24, 1194, 700), container = CGRectMake(0, 0, 1194, 834);
    CGFloat shift = AppleShift160(rtl, stage, container, group), cx = CGRectGetMidX(group);
    Calc160Run r;
    if (inCalculator) DMSMCalc160Enter();
    DMSMPass160Begin();
    r.pass = DMSMShift160X(freePlacement, cx + 7, cx);   // (a centre the pass itself sets: never held)
    DMSMPass160End();
    r.box = DMSMShift160X(freePlacement, group.origin.x + shift, group.origin.x);
    r.centre = DMSMShift160X(freePlacement, cx + shift, cx);
    if (inCalculator) DMSMCalc160Exit();
    r.after = DMSMShift160X(freePlacement, cx + 30, cx);   // (a drag afterwards: never held)
    return r;
}
static NSString *Join(id a) { return [a isKindOfClass:[NSArray class]] ? [a componentsJoinedByString:@" | "] : [a description]; }
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
        // args: fixture, expected core failures ("a|b", "" = none), optional rows missing, features off, cut ("remove"/"leaf"), iPadOS version shown,
        // the other ways the check must choose ("group: variant|..."; "" = the tested ones), the stand-ins' fraction edge (0 = no "sized" model),
        // how Settings offers the engine ("untested": "Stage Manager (Untested)" + its note; "normal": as on 16.2+; "off": not offered)
        // and the "verified" count: the rows of the ways in use found here (1.3.4 re-check F4: asserted per build, 16.0 and 16.1 included)
        if (argc < 11) { fprintf(stderr, "usage: %s fixture core optional off cut os paths edge offered verified\n", argv[0]); return 2; }
        NSString *fixture = @(argv[1]), *wantCore = @(argv[2]), *wantOpt = @(argv[3]), *wantOff = @(argv[4]), *wantCut = @(argv[5]), *os = @(argv[6]), *wantPaths = @(argv[7]);
        double edge = atof(argv[8]);
        NSString *wantOffered = @(argv[9]);
        NSUInteger wantVerified = (NSUInteger)atoi(argv[10]);
        if (!LoadFixture(fixture)) { printf("FAIL  cannot read %s\n", argv[1]); return 1; }
        printf("== %s\n", gTitle.UTF8String);
        if (edge > 0) MakeAttributesFunctional(edge);   // (the "sized" builds: Apple's reading of a value, for the check's probe and the wrappers)
        // 1. the verdict, from the same code SpringBoard runs (DMSMCheckAPILive: core problems, optional rows, variants, each row's answer)
        NSUInteger checked = 0;
        gSMLayoutGen = 16;
        NSArray *bad = DMSMCheckAPILive(nil, &checked);
        Check(@"core rows that fail (the engine stays off when any does)", [[NSSet setWithArray:bad] isEqualToSet:SetOf(wantCore)], Join(bad));
        Check(@"optional rows not here", [Stripped(gSMCheckOptional) isEqualToSet:SetOf(wantOpt)], Join(gSMCheckOptional));
        Check(@"features left with none of their alternatives", [[NSSet setWithArray:gSMFeaturesOff ?: @[]] isEqualToSet:SetOf(wantOff)], Join(gSMFeaturesOff));
        NSArray *paths = DMSMOtherWays(gSMVariants);
        Check(wantPaths.length ? @"the check chose this iPadOS's own ways (never run on a device)" : @"the check chose the tested way for every job", [[NSSet setWithArray:paths] isEqualToSet:SetOf(wantPaths)], Join(paths));
        BOOL engineOn = bad.count == 0;
        BOOL rowsOK = YES;   // (every row in use -- of the chosen ways -- there with our signature, when the engine is on)
        for (size_t i = 0; i < kSMNeedsCount; i++) if (DMSMRowInUse(&kSMNeeds[i], 16) && kSMNeeds[i].need == DMSMNeedCore && !kSMNeeds[i].ivar && engineOn && !gSMRowPassed[i]) rowsOK = NO;
        Check(engineOn ? @"engine ON: every row in use there with our signature" : @"engine OFF on this build", engineOn ? rowsOK : wantCore.length > 0, [NSString stringWithFormat:@"%lu compared", (unsigned long)checked]);
        // the "verified" count: the rows of the ways in use only -- 16.2 and later keep 1.3.3's 76, minus the optional rows not there (1.3.4 logic test L1:
        // the first 1.3.4 builds counted rows of the other ways too, 78 and 81 on 16.7.7)
        Check([NSString stringWithFormat:@"verified count: %lu (the rows of the ways in use found here)", (unsigned long)wantVerified], checked == wantVerified, [NSString stringWithFormat:@"%lu", (unsigned long)checked]);
        if (!paths.count) Check(@"16.2 and later: 108 rows (77 + sm-free's 17 Home rows + 1.3.8's 8 logic-test rows + 1.3.9's 6 Home-gesture rows) minus the optional rows not here", checked == 108 - gSMCheckOptional.count, [NSString stringWithFormat:@"%lu", (unsigned long)checked]);
        if (edge > 0) Check([NSString stringWithFormat:@"16.0/16.1 window model: Apple's fraction edge found (%.0f)", edge], DMSMSizedModel() && Near(gSMSizedThreshold, edge), [NSString stringWithFormat:@"sized %d edge %.1f", DMSMSizedModel(), gSMSizedThreshold]);
        else Check(@"the tested window model (attributed size) is used", !DMSMSizedModel(), @"");
        // hooks: only the chosen ways' rows are counted for "the hooks went in" (a hook of the other way is never installed)
        NSUInteger hookedInUse = 0, hookedOther = 0;
        for (size_t i = 0; i < kSMNeedsCount; i++) if (kSMNeeds[i].hooked && DMSMRowActive(&kSMNeeds[i], 16)) { if (DMSMRowInUse(&kSMNeeds[i], 16)) hookedInUse++; else hookedOther++; }
        Check(@"hook bookkeeping counts only the chosen ways (9 of 16.1's or 16.0's layout rows left out)", DMSMHookedIMPs().count == hookedInUse && hookedOther >= 10, [NSString stringWithFormat:@"%lu IMPs, %lu in use, %lu other", (unsigned long)DMSMHookedIMPs().count, (unsigned long)hookedInUse, (unsigned long)hookedOther]);
        // 2. the "sized" model through the engine's wrappers: what is handed over, what Apple's layout then reads in the screen, what comes back
        if (edge > 0) {
            id a = DMSMAttrNew();
            DMSMAttributedSize s = {CGSizeMake(0.5, 0.6), gScreen, 0}, back = {{0, 0}, {{0, 0}, {0, 0}}, 0};
            id w = DMSMAttrWithSize(a, s);
            CGSize inScreen = ((CGSize (*)(id, SEL, CGRect))objc_msgSend)(w, sel_registerName("sizeInBounds:"), gScreen);
            Check(@"a window of half the width: Apple's layout reads 512 x 460.8", Near(inScreen.width, 512) && Near(inScreen.height, 460.8), NSStringFromCGSize(inScreen));
            Check(@"... and the engine reads 0.5 x 0.6 of the screen back", DMSMAttrAttributedSize(w, &back) && Near(back.normalizedSize.width, 0.5) && Near(back.normalizedSize.height, 0.6) && CGRectEqualToRect(back.referenceBounds, gScreen), DMSMSizeText(back));
            DMSMAttributedSize wide = {CGSizeMake(1.2, 0.5), gScreen, 0};
            id w2 = DMSMAttrWithSize(a, wide);
            CGSize raw2 = Stored(w2, &kSizeKey), in2 = ((CGSize (*)(id, SEL, CGRect))objc_msgSend)(w2, sel_registerName("sizeInBounds:"), gScreen);
            Check(@"wider than the screen: handed over in points, read so (1228.8 wide)", Near(raw2.width, 1228.8) && Near(in2.width, 1228.8) && Near(in2.height, 384), [NSString stringWithFormat:@"stored %@ read %@", NSStringFromCGSize(raw2), NSStringFromCGSize(in2)]);
            Check(@"... and back as 1.2 x 0.5", DMSMAttrAttributedSize(w2, &back) && Near(back.normalizedSize.width, 1.2) && Near(back.normalizedSize.height, 0.5), DMSMSizeText(back));
            DMSMAttributedSize other = {CGSizeMake(0.6, 0.72), CGRectMake(0, 0, 768, 1024), 0};   // (a size kept from portrait: 460.8 x 737.28 points)
            id w3 = DMSMAttrWithSize(a, other);
            CGSize in3 = ((CGSize (*)(id, SEL, CGRect))objc_msgSend)(w3, sel_registerName("sizeInBounds:"), gScreen);
            Check(@"a size of another reference keeps its points (460.8 x 737.28)", Near(in3.width, 460.8) && Near(in3.height, 737.28), NSStringFromCGSize(in3));
            DMSMAttributedSize full = {CGSizeMake(1, 1), CGRectZero, 3};
            CGSize in4 = ((CGSize (*)(id, SEL, CGRect))objc_msgSend)(DMSMAttrWithSize(a, full), sel_registerName("sizeInBounds:"), gScreen);
            Check(@"full width and height (type 3): the whole screen", Near(in4.width, 1024) && Near(in4.height, 768), NSStringFromCGSize(in4));
            CGPoint cb = CGPointZero;
            id c1 = DMSMAttrWithCenter(a, CGPointMake(-0.2, 0.5));
            CGPoint p1 = ((CGPoint (*)(id, SEL, CGRect))objc_msgSend)(c1, sel_registerName("centerInBounds:"), gScreen);
            Check(@"a centre left of the screen (-0.2): read at x -204.8", Near(p1.x, -204.8) && Near(p1.y, 384) && DMSMAttrCenter(c1, &cb) && Near(cb.x, -0.2) && Near(cb.y, 0.5), [NSString stringWithFormat:@"%@ back %@", NSStringFromCGPoint(p1), NSStringFromCGPoint(cb)]);
            id c2 = DMSMAttrWithCenter(a, CGPointMake(1.3, 0.5));
            CGPoint p2 = ((CGPoint (*)(id, SEL, CGRect))objc_msgSend)(c2, sel_registerName("centerInBounds:"), gScreen);
            Check(@"a centre right of the screen (1.3): in points, read at x 1331.2", Near(p2.x, 1331.2) && Near(p2.y, 384) && DMSMAttrCenter(c2, &cb) && Near(cb.x, 1.3) && Near(cb.y, 0.5), [NSString stringWithFormat:@"%@ back %@", NSStringFromCGPoint(p2), NSStringFromCGPoint(cb)]);
            id d = DMSMAttrNew();
            Check(@"a new window (no size yet) reads as 0 x 0: the engine's default size applies", DMSMAttrAttributedSize(d, &back) && back.normalizedSize.width == 0 && back.normalizedSize.height == 0, DMSMSizeText(back));
            // a stored value with one part within the fraction edge and one beyond it is points in both parts (Apple's rule: a fraction only while BOTH
            // parts are small enough) -- 1.3.4 logic test L2a: a width-only test read it as a fraction
            id mixed = CopyWith(a, &kSizeKey, CGSizeMake(edge * 0.5, 300));
            Check(@"a stored size with one part beyond the fraction edge reads as points in both parts", DMSMAttrAttributedSize(mixed, &back) && Near(back.normalizedSize.width * gScreen.size.width, edge * 0.5) && Near(back.normalizedSize.height * gScreen.size.height, 300), DMSMSizeText(back));
            DMSMAttributedSize junk = {CGSizeMake(NAN, 0.5), gScreen, 0};
            Check(@"a size that is not a number is refused, nothing handed over", DMSMAttrWithSize(a, junk) == nil, @"");
        }
        // the 1.3.1 verdict on this build, from the same rows: the two that were core then (the removing method; -containerBounds, which every
        // build with the ivar also has as a method -- the ivar is what the code reads) counted as core again, and no other ways
        BOOL removing = DMSMRowPassed("SBAppLayout", "appLayoutByRemovingItemInLayoutRole:");
        BOOL v131 = engineOn && removing && DMSMRowPassed("SBSwitcherChamoisLayoutAttributes", "_containerBounds") && paths.count == 0;
        printf("      1.3.1 verdict here: %s; now: %s\n", v131 ? "engine on" : "engine OFF", engineOn ? (DMSMWaysUntested(gSMVariants) ? "engine on (untested way)" : paths.count ? "engine on (another way, offered normally)" : "engine on") : "engine OFF");
        // 3. the cut-back when another engine takes over
        MakeStagesFunctional();
        if (edge > 0) MakeAttributesFunctional(edge);   // (the stages' attributes come from the same class)
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
            Check(@"simulated changed core rows (selector / encoding) still fail", DMSMCheckAPI(@"selector", NULL).count == 1 && DMSMCheckAPI(@"encoding", NULL).count == 1, @"");
        }
        // 3b. iPadOS 16.0's group shift after its layout pass (1.3.4 logic test): where the check chose 16.0's own pass, the calculator and the
        //     bounding box setter are hooked rows of it (so the hooks-went-in check covers them); our engine keeps every window's x through the shift
        BOOL pass160 = DMSMVariantIs("auto layout", "16.0");
        BOOL rowsIn = YES;
        for (size_t i = 0; i < kSMNeedsCount; i++) {
            BOOL calc = !strcmp(kSMNeeds[i].sel, "_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:draggingItem:overlappingModelBeforeDragging:bounds:prefersStripHidden:prefersDockHidden:");
            BOOL box = !strcmp(kSMNeeds[i].cls, "SBChamoisOverlappingModel") && !strcmp(kSMNeeds[i].sel, "setBoundingBox:");
            if ((calc || box) && (!kSMNeeds[i].hooked || DMSMRowInUse(&kSMNeeds[i], 16) != pass160 || (pass160 && !gSMRowPassed[i]))) rowsIn = NO;
        }
        Check(pass160 ? @"16.0's pass: the calculator and -setBoundingBox: are hooked rows in use, there with our signature" : @"16.0's group-shift rows are not in use here",
              rowsIn, @"");
        if (pass160) {
            CGRect lone = CGRectMake(600, 100, 500, 500), left = CGRectMake(100, 100, 500, 500), pair = CGRectMake(0, 100, 1194, 500);
            Check(@"Apple's 16.0 shift: a lone window right of the centred place moves left (253 pt), one left of it and a full-width pair do not",
                  Near(AppleShift160(NO, CGRectMake(0, 24, 1194, 700), CGRectMake(0, 0, 1194, 834), lone), -253) && Near(AppleShift160(NO, CGRectMake(0, 24, 1194, 700), CGRectMake(0, 0, 1194, 834), left), 0) &&
                  Near(AppleShift160(NO, CGRectMake(0, 24, 1194, 700), CGRectMake(0, 0, 1194, 834), pair), 0), @"");
            Calc160Run a = PlayCalculator160(YES, YES, NO, lone);
            Check(@"our engine: the lone window and the bounding box keep their x through the shift (850 / 600)", Near(a.centre, 850) && Near(a.box, 600), [NSString stringWithFormat:@"centre %.1f box %.1f", a.centre, a.box]);
            Check(@"... a centre set by the pass itself and a drag afterwards are not held", Near(a.pass, 857) && Near(a.after, 880), [NSString stringWithFormat:@"pass %.1f after %.1f", a.pass, a.after]);
            Calc160Run b = PlayCalculator160(YES, NO, NO, lone);
            Check(@"Apple's own placement (not our engine): the shift goes through (597 / 347)", Near(b.centre, 597) && Near(b.box, 347), [NSString stringWithFormat:@"centre %.1f box %.1f", b.centre, b.box]);
            Calc160Run c = PlayCalculator160(NO, YES, NO, lone);
            Check(@"a layout pass outside the calculator: nothing held afterwards", Near(c.centre, 597) && Near(c.box, 347), [NSString stringWithFormat:@"centre %.1f box %.1f", c.centre, c.box]);
            CGRect rtlLone = CGRectMake(94, 100, 500, 500);
            Calc160Run d = PlayCalculator160(YES, YES, YES, rtlLone);
            Check(@"right-to-left: Apple's shift pushes right (253 pt), our engine keeps x", Near(AppleShift160(YES, CGRectMake(0, 24, 1194, 700), CGRectMake(0, 0, 1194, 834), rtlLone), 253) && Near(d.centre, 344) && Near(d.box, 94),
                  [NSString stringWithFormat:@"centre %.1f box %.1f", d.centre, d.box]);
            DMSMCalc160Enter(); DMSMCalc160Exit(); DMSMCalc160Exit();   // (an unbalanced exit never goes below zero)
            Check(@"the calculator's depth never goes below zero", gSMCalc160Depth == 0 && !gSMPostPass160, @"");
        }
        // 3c. Stage Manager switched back off after being the engine (the 11:58 abort, iPad 2 4 Oct): never while SpringBoard's switch-off would make a
        //     transition that drops windows (an app in front, a stage of more than one window); the same on every build, checked once
        if ([os isEqualToString:@"16.7.7"]) {
            Check(@"switch-off: first seen / 5 s after the engine change -> wait (start-up)", DMSMEngineOffStep(-1, NO, YES, NO, 0) == DMSMOffWait && DMSMEngineOffStep(5, NO, YES, NO, 0) == DMSMOffWait, @"");
            Check(@"switch-off: 10 s on, no app in front (Home Screen) -> now", DMSMEngineOffStep(10.1, NO, YES, NO, 0) == DMSMOffNow, @"");
            Check(@"switch-off: an app in front with one window -> now", DMSMEngineOffStep(30, NO, YES, YES, 1) == DMSMOffNow, @"");
            Check(@"switch-off: three windows in front (the 11:58 abort) -> wait; two windows -> wait", DMSMEngineOffStep(10.04, NO, YES, YES, 3) == DMSMOffWait && DMSMEngineOffStep(60, NO, YES, YES, 2) == DMSMOffWait, @"");
            Check(@"switch-off: Stage Manager already off -> only forget it was ours", DMSMEngineOffStep(12, NO, NO, YES, 3) == DMSMOffForget, @"");
            Check(@"switch-off: Mac Status Bar off / removed -> no 10 s wait, still never with windows to drop",
                  DMSMEngineOffStep(-1, YES, YES, NO, 0) == DMSMOffNow && DMSMEngineOffStep(-1, YES, YES, YES, 3) == DMSMOffWait && DMSMEngineOffStep(-1, YES, NO, YES, 3) == DMSMOffForget, @"");
            // the 11:58 sequence played second by second: engine set to Aerial at 0 s with three Fit windows in front, Home at 25 s
            int firstNow = -1;
            for (int t = 0; t <= 40 && firstNow < 0; t++) if (DMSMEngineOffStep(t, NO, YES, t < 25, t < 25 ? 3 : 0) == DMSMOffNow) firstNow = t;
            Check(@"the 11:58 sequence: Stage Manager goes off at the Home Screen (25 s), not at 10 s with the three windows", firstNow == 25, [NSString stringWithFormat:@"%d", firstNow]);
        }
        // 3d. SpringBoard's own switch handler with our ownership (the 1.3.4 re-check's race, F1): the handler runs as a later main-queue block, and the
        //     watcher's tick can come in between -- reading the setting off (our engine then counts as off) and dropping its ownership key. Played in both
        //     orders: the switch-off with three windows in front must wait either way; Apple's own Stage Manager (never ours) runs as Apple's.
        if ([os isEqualToString:@"16.7.7"]) {
            Check(@"handler: a switch-off with three windows in front, ours -> wait", DMSMHandlerStep(YES, YES, NO, YES, YES, 3) == DMSMHandlerWait, @"");
            Check(@"handler: at the Home Screen / one window / not ours / state unreadable -> run", DMSMHandlerStep(YES, YES, NO, YES, NO, 0) == DMSMHandlerRun && DMSMHandlerStep(YES, YES, NO, YES, YES, 1) == DMSMHandlerRun &&
                  DMSMHandlerStep(YES, NO, NO, YES, YES, 3) == DMSMHandlerRun && DMSMHandlerStep(NO, YES, NO, YES, YES, 3) == DMSMHandlerRun, @"");
            Check(@"handler: the setting back as SpringBoard shows it -> nothing to switch; a switch-on -> run", DMSMHandlerStep(YES, YES, YES, YES, YES, 3) == DMSMHandlerSkip &&
                  DMSMHandlerStep(YES, YES, NO, NO, NO, 0) == DMSMHandlerSkip && DMSMHandlerStep(YES, YES, YES, NO, YES, 3) == DMSMHandlerRun, @"");
            // the two orders, from one SpringBoard start: our engine ran (the watcher noted it), then an outside writer switches Stage Manager off
            for (int order = 0; order < 2; order++) {
                gSMOwnsStageUI = NO;
                BOOL engineNow = YES, keyPresent = YES;
                DMSMOwnsStageUIWith(engineNow, keyPresent);   // (a tick while our engine ran: noted)
                // the write: the setting reads off from now on
                if (order == 1) { engineNow = NO; keyPresent = NO; }   // (the watcher's tick first: the engine reads as off, the key is dropped)
                int step = DMSMHandlerStep(YES, DMSMOwnsStageUIWith(engineNow, keyPresent), NO, YES, YES, 3);
                Check(order == 0 ? @"race: SpringBoard's handler first -> wait" : @"race: the watcher's tick first (engine off, key gone) -> still wait", step == DMSMHandlerWait, [NSString stringWithFormat:@"%d", step]);
            }
            // a SpringBoard where our engine never ran and no key is there: Apple's own Stage Manager, left as Apple has it
            gSMOwnsStageUI = NO;
            Check(@"never ours (no engine, no key) -> Apple's handler runs", DMSMHandlerStep(YES, DMSMOwnsStageUIWith(NO, NO), NO, YES, YES, 3) == DMSMHandlerRun, @"");
            // a SpringBoard started after an engine change: only the key says Stage Manager was on for our engine; the watcher drops it -> still ours
            gSMOwnsStageUI = NO;
            DMSMOwnsStageUIWith(NO, YES);
            Check(@"after a respring with the key: ownership kept when the key goes", DMSMHandlerStep(YES, DMSMOwnsStageUIWith(NO, NO), NO, YES, YES, 3) == DMSMHandlerWait, @"");
            gSMOwnsStageUI = NO;
        }
        // 4. what Settings and Report a Problem say about this build
        NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:@{@"build": @"TEST", @"ok": @(engineOn)}];
        if (bad.count) record[@"details"] = bad;
        if (gSMCheckOptional.count) record[@"optional"] = gSMCheckOptional;
        DMSMRecordWays(record, gSMVariants);   // (the ways part of the record exactly as DMSMPublishVerdict writes it)
        BOOL untested = MSBDStageManagerUntestedIn(record, NULL);   // (what the Window Engine list asks: "Stage Manager (Untested)" when YES)
        NSString *offered = !engineOn ? @"off" : untested ? @"untested" : @"normal";
        Check([NSString stringWithFormat:@"Settings offers Stage Manager: %@%@", wantOffered, [wantOffered isEqualToString:@"untested"] ? @" (\"Stage Manager (Untested)\" + note, 16.0 only)" : [wantOffered isEqualToString:@"normal"] ? @" (no untested label or note)" : @""],
              [offered isEqualToString:wantOffered] && [record[@"untested"] boolValue] == [wantOffered isEqualToString:@"untested"], [NSString stringWithFormat:@"%@, record untested %@", offered, record[@"untested"]]);
        NSString *footer = MSBDStageManagerFooterFor(0, engineOn ? 1 : 0, record, os);
        NSString *line = MSBDStageManagerReportLineFor(0, @"native", engineOn ? 1 : 0, record, os, @"TEST", 900);
        if (engineOn && !untested) Check(@"Settings: no footer, the row can be picked", footer == nil, footer);
        else if (engineOn) Check(@"Settings footer: untested on this version", [footer isEqualToString:[NSString stringWithFormat:@"Stage Manager hasn't been tested on iPadOS %@ yet. If you try it, Report a Problem helps.", os]], footer);
        else Check(@"Settings footer names the version", [footer isEqualToString:[NSString stringWithFormat:@"Stage Manager isn't supported on iPadOS %@ yet.", os]], footer);
        BOOL named = YES;
        for (NSString *l in bad) named = named && [line containsString:l];
        for (NSString *l in gSMCheckOptional) named = named && [line containsString:l];
        for (NSString *l in paths) named = named && [line containsString:l];
        NSString *want = engineOn ? (untested ? @"- Stage Manager engine check: passed, untested way (" : @"- Stage Manager engine check: passed (") : @"- Stage Manager engine check: failed (";
        Check(@"Report a Problem line: verdict, every failed / missing row and every other way by name", named && [line hasPrefix:want] && (untested || ![line containsString:@"untested"]), line);
        NSString *shortLine = MSBDStageManagerReportLineFor(0, @"native", engineOn ? 1 : 0, record, os, @"TEST", 80);
        Check(@"Report a Problem line stays short when the link is too long", shortLine.length < 340 && (bad.count < 2 || [shortLine containsString:@"..."]), shortLine);
        Check(@"no em dash in what users read", ![footer ?: @"" containsString:@"—"] && ![line containsString:@"—"], @"");
        printf("      Report a Problem: %s", line.UTF8String);
        if (footer) printf("      Settings footer: %s\n", footer.UTF8String);
        // a record of a check that FAILED never makes the row "(Untested)", whatever else it holds (1.3.4 logic test L2b)
        NSDictionary *failedUntested = @{@"build": @"TEST", @"ok": @NO, @"untested": @YES, @"paths": @[@"auto layout: 16.0"], @"details": @[@"-[X y] missing"]};
        Check(@"a failed check's record with an untested key: not untested, the 'isn't supported' footer", !MSBDStageManagerUntestedIn(failedUntested, NULL) &&
              [MSBDStageManagerFooterFor(0, 0, failedUntested, os) isEqualToString:[NSString stringWithFormat:@"Stage Manager isn't supported on iPadOS %@ yet.", os]], MSBDStageManagerFooterFor(0, 0, failedUntested, os));
        // the other reasons (same for every build): no Stage Manager on this iPad, not checked yet
        Check(@"footer: an iPad without Stage Manager", [MSBDStageManagerWhyText(2, -1, os) isEqualToString:@"This iPad doesn't have Stage Manager (TrollPad can add it)."], MSBDStageManagerWhyText(2, -1, os));
        Check(@"footer: not checked on this build yet", [MSBDStageManagerWhyText(0, -1, os) isEqualToString:@"Respring once to check Stage Manager on this iPadOS version."], MSBDStageManagerWhyText(0, -1, os));
        NSString *noSM = MSBDStageManagerReportLineFor(2, @"Stage Manager model no, TrollPad no, MobileGestalt no", -1, nil, os, @"TEST", 900);
        Check(@"report: an iPad without Stage Manager says which sources were asked", [noSM isEqualToString:@"- Stage Manager: not on this iPad (Stage Manager model no, TrollPad no, MobileGestalt no)\n"], noSM);
        NSString *unchecked = MSBDStageManagerReportLineFor(0, @"TrollPad", -1, nil, os, @"TEST", 900);
        Check(@"report: not checked yet", [unchecked hasPrefix:@"- Stage Manager engine check: not run yet ("] && [unchecked containsString:@"TrollPad"], unchecked);
        printf("%s %s\n", gFails ? "FAILED" : "ok", gTitle.UTF8String);
        return gFails ? 1 : 0;
    }
}
