// test-smlayout17.m -- Mac test of the Stage Manager engine's version-aware self-check and its iPadOS 17 wrappers (statusbar/SMEngineAPI.h).
// There is no iPadOS 17 device: this checks, off the device,
//  1. that the signatures we check the iPadOS 17 layout engine with (DMSM_SIG ...17) equal the type encodings the 17.0.3 runtime headers describe
//     (the encodings written out here by hand from MTACS/iOS-17-Runtime-Headers, the types as the runtime prints them);
//  2. the table choice: iPadOS 16 -> only the rows of the 16 layout engine and the shared ones, 17 -> the 17 rows instead; a table whose classes
//     are missing fails (the engine stays off);
//  3. the 17 rows pass against stand-in classes with the headers' signatures, and a changed signature fails;
//  4. the checked wrappers (items, position, size, flags, configuration), including refusals of nonsense values;
//  5. the corner radius row: the 18.2 name (stageCornerRadii) is taken where the old one is missing;
//  6. DMSMClampCenter (windows kept inside the stage area, top/left winning);
//  7. (ios17-sm2) iPadOS 17's "position is system managed" flag: the rows, the wrappers, and DMSMAttrWith handing every window over as placed by
//     the user on the 17 table only (16: unchanged);
//  8. (ios17-sm2) the layout-role check against SpringBoard's exported SBLayoutRoleIsValid / role constants (stand-ins exported by this test);
//  9. (ios17-sm2) one layout pass: DMSM17PassBegin / DMSM17PassEnd around a stand-in of 17.6.1's own -_performAutoLayoutWithSpace:... (written
//     from the decompile: container clamp with the screen edge padding, (0,0) windows centred, a lone system-managed window centred, a
//     full-screen-sized one centred), checking where every window ends up.
// Compiled with BOOL = bool, as on arm64 iOS. Run: tools/test-smlayout17.sh
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
// ---- what StatusBar.x defines before including SMEngineAPI.h (stand-ins) ----
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
#define MSB_DOMAIN CFSTR("com.besiktasliseba.test-smlayout17")
static id DMCall(id obj, NSString *name) { SEL s = NSSelectorFromString(name); return obj && [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil; }
typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long type; } DMSMAttributedSize;
// (UIKit's NSValue additions, which SMEngineAPI.h uses on the device; macOS has the NSPoint/NSSize ones)
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
static int gDiagSoon = 0;
static void DMSM17DiagSoon(void) { gDiagSoon++; }

// ---- stand-ins with the iPadOS 17.0.3 headers' signatures ----
@interface SBSwitcherChamoisLayoutAttributes : NSObject
@property (nonatomic) BOOL prefersDockHidden, prefersStripHidden;
@end
@implementation SBSwitcherChamoisLayoutAttributes
- (double)stageCornerRadii { return 12; }   // (the 18.2 name only: the old stageCornerRaddii is missing here)
@end
@interface SBContinuousExposeAutoLayoutConfiguration : NSObject
@property (nonatomic) CGRect containerBounds;
@property (nonatomic) double dockHeightWithBottomEdgePadding;
@property (nonatomic, strong) id chamoisLayoutAttributes;
@end
@implementation SBContinuousExposeAutoLayoutConfiguration
@end
@interface SBContinuousExposeAutoLayoutItem : NSObject
@property (nonatomic) CGPoint position;
@property (nonatomic) CGSize size;
@property (getter=isInDefaultPosition, nonatomic) BOOL inDefaultPosition;
@end
@implementation SBContinuousExposeAutoLayoutItem
@end
@interface SBContinuousExposeAutoLayoutSpace : NSObject
@property (nonatomic, strong) NSArray *items;
@end
@implementation SBContinuousExposeAutoLayoutSpace
@end
@interface SBContinuousExposeAutoLayoutController : NSObject
@end
@implementation SBContinuousExposeAutoLayoutController
- (CGRect)stageAreaForSpace:(id)s configuration:(id)c { return CGRectZero; }
- (id)spaceByPerformingAutoLayoutWithSpace:(id)s previousSpace:(id)p configuration:(id)c options:(unsigned long long)o { return s; }
- (CGRect)_performAutoLayoutWithSpace:(id)s configuration:(id)c stageInset:(UIEdgeInsets)i { return CGRectZero; }
- (void)_compactSpacingBetweenItemsInSpace:(id)s configuration:(id)c {}
- (void)dodgeFullyOccludedWindowsToNearestVisibleEdgeForSpace:(id)s configuration:(id)c {}
- (void)snapPositionToNearestEdgesIfNecessaryForSpace:(id)s stageArea:(CGRect)a configuration:(id)c {}
@end
// (a controller whose snap method takes another argument type than the headers: must fail)
@interface SBChangedController : NSObject
@end
@implementation SBChangedController
- (void)snapPositionToNearestEdgesIfNecessaryForSpace:(id)s stageArea:(CGPoint)a configuration:(id)c {}
@end
// (a window's attributes with the 17.0.3 signatures: each attributesByModifying... returns a changed copy)
@interface SBDisplayItemLayoutAttributes : NSObject <NSCopying>
@property (nonatomic) DMSMAttributedSize sz;
@property (nonatomic) CGPoint center;
@property (nonatomic) long long policy, time;
@property (nonatomic) BOOL managed;
@end
@implementation SBDisplayItemLayoutAttributes
- (id)copyWithZone:(NSZone *)z { SBDisplayItemLayoutAttributes *a = [SBDisplayItemLayoutAttributes new]; a.sz = _sz; a.center = _center; a.policy = _policy; a.time = _time; a.managed = _managed; return a; }
- (id)attributesByModifyingAttributedSize:(DMSMAttributedSize)s { SBDisplayItemLayoutAttributes *a = [self copy]; a.sz = s; return a; }
- (id)attributesByModifyingNormalizedCenter:(CGPoint)c { SBDisplayItemLayoutAttributes *a = [self copy]; a.center = c; return a; }
- (id)attributesByModifyingSizingPolicy:(long long)p { SBDisplayItemLayoutAttributes *a = [self copy]; a.policy = p; return a; }
- (id)attributesByModifyingLastInteractionTime:(long long)t { SBDisplayItemLayoutAttributes *a = [self copy]; a.time = t; return a; }
- (BOOL)isPositionSystemManaged { return _managed; }
- (id)attributesByModifyingPositionIsSystemManaged:(BOOL)m { SBDisplayItemLayoutAttributes *a = [self copy]; a.managed = m; return a; }
@end
// (SpringBoard's exported layout-role function and constants, as the 17.6.1 decompile uses them; the role check finds these through dlsym)
static int gTestRefuseRole = 0;
__attribute__((visibility("default"), used)) BOOL SBLayoutRoleIsValid(long long r) { return r >= 1 && r <= 12 && r != gTestRefuseRole; }
__attribute__((visibility("default"), used)) const long long SBLayoutRolePrimary = 1;
__attribute__((visibility("default"), used)) const long long SBLayoutRoleSide = 2;
__attribute__((visibility("default"), used)) const long long SBLayoutRoleCenter = 4;
__attribute__((visibility("default"), used)) const long long SBLayoutRoleAdditionalSideRangeMin = 5;
__attribute__((visibility("default"), used)) const long long SBLayoutRoleAdditionalSideRangeMax = 12;

// ---- 17.6.1's own layout pass, written from the decompile (SBContinuousExposeAutoLayoutController.m, -_performAutoLayoutWithSpace:configuration:
// stageInset:, 17.6.1 21G101): every window's centre kept inside the container inset by the screen edge padding; a window with no place yet ((0,0)
// before that) centred (container mid x, stage area mid y); ONE window: centred when "in its default position" (system managed), or when it is as big
// as the container; otherwise snapping and dodging (with our engine those two are hooked to do nothing, so they are left out here). Returns the stage
// area (the one -stageAreaForSpace: gives: with our engine, ours).
static CGRect ApplePass176(SBContinuousExposeAutoLayoutSpace *space, CGRect container, double padding, CGRect stageArea) {
    NSArray<SBContinuousExposeAutoLayoutItem *> *items = space.items;
    if (!items.count) return container;
    NSMutableArray<NSValue *> *copy = [NSMutableArray array];
    for (SBContinuousExposeAutoLayoutItem *it in items) [copy addObject:[NSValue valueWithPoint:NSPointFromCGPoint(it.position)]];
    CGRect in = CGRectInset(container, padding, padding);
    for (SBContinuousExposeAutoLayoutItem *it in items) {
        CGPoint p = it.position; CGSize z = it.size;
        if (p.x < CGRectGetMinX(in) + z.width * 0.5) p.x = CGRectGetMinX(in) + z.width * 0.5;
        if (p.x >= CGRectGetMaxX(in) - z.width * 0.5) p.x = CGRectGetMaxX(in) - z.width * 0.5;
        if (p.y < CGRectGetMinY(in) + z.height * 0.5) p.y = CGRectGetMinY(in) + z.height * 0.5;
        if (p.y >= CGRectGetMaxY(in) - z.height * 0.5) p.y = CGRectGetMaxY(in) - z.height * 0.5;
        it.position = p;
    }
    for (NSUInteger i = 0; i < items.count; i++) {
        CGPoint was = NSPointToCGPoint(copy[i].pointValue);
        if (was.x == 0 && was.y == 0) items[i].position = CGPointMake(container.origin.x + container.size.width * 0.5, CGRectGetMidY(stageArea));
    }
    if (items.count == 1) {
        SBContinuousExposeAutoLayoutItem *it = items.firstObject;
        if (it.inDefaultPosition) { it.position = CGPointMake(container.size.width * 0.5, CGRectGetMidY(stageArea)); return stageArea; }
        if (it.size.width == container.size.width && it.size.height == container.size.height) { it.position = CGPointMake(container.size.width * 0.5, container.size.height * 0.5); return stageArea; }
    }
    return stageArea;   // (snap + dodge: hooked to do nothing by our engine)
}
static SBContinuousExposeAutoLayoutItem *Item(CGFloat x, CGFloat y, CGFloat w, CGFloat h, BOOL def) {
    SBContinuousExposeAutoLayoutItem *it = [SBContinuousExposeAutoLayoutItem new]; it.position = CGPointMake(x, y); it.size = CGSizeMake(w, h); it.inDefaultPosition = def; return it;
}
static NSString *P(CGPoint p) { return [NSString stringWithFormat:@"{%.1f, %.1f}", p.x, p.y]; }
static CGPoint Pos(SBContinuousExposeAutoLayoutSpace *s, NSUInteger i) { return ((SBContinuousExposeAutoLayoutItem *)s.items[i]).position; }
static BOOL Def(SBContinuousExposeAutoLayoutSpace *s, NSUInteger i) { return ((SBContinuousExposeAutoLayoutItem *)s.items[i]).inDefaultPosition; }

static int fails = 0, total = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    total++; if (!ok) fails++;
    printf("%s  %-66s %s\n", ok ? "PASS" : "FAIL", what.UTF8String, got.UTF8String ?: "");
}
static BOOL Has(NSArray<NSString *> *bad, NSString *part) { for (NSString *l in bad) if ([l containsString:part]) return YES; return NO; }
static NSUInteger Rows(int gen, int which) { NSUInteger n = 0; for (size_t i = 0; i < kSMNeedsCount; i++) if (kSMNeeds[i].layout == which && DMSMRowActive(&kSMNeeds[i], gen)) n++; return n; }

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        gLog = [NSMutableArray array];
        // 1. our signatures = the 17.0.3 headers' types, as the runtime encodes them
        struct { NSString *(*ours)(void); const char *apple; const char *what; } sigs[] = {
            {DMSMSigStageArea17, "{CGRect={CGPoint=dd}{CGSize=dd}}32@0:8@16@24", "stageAreaForSpace:configuration:"},
            {DMSMSigAutoLayout17, "@48@0:8@16@24@32Q40", "spaceByPerformingAutoLayoutWithSpace:previousSpace:configuration:options:"},
            {DMSMSigPerform17, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8@16@24{UIEdgeInsets=dddd}32", "_performAutoLayoutWithSpace:configuration:stageInset:"},
            {DMSMSigVoidObjObj, "v32@0:8@16@24", "_compactSpacing... / dodgeFullyOccluded..."},
            {DMSMSigSnap17, "v64@0:8@16{CGRect={CGPoint=dd}{CGSize=dd}}24@56", "snapPositionToNearestEdgesIfNecessaryForSpace:stageArea:configuration:"},
            {DMSMSigRect, "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8", "configuration containerBounds"},
            {DMSMSigDouble, "d16@0:8", "dockHeightWithBottomEdgePadding"},
            {DMSMSigObj, "@16@0:8", "chamoisLayoutAttributes / items"},
            {DMSMSigCenter, "{CGPoint=dd}16@0:8", "item position"},
            {DMSMSigVoidPoint, "v32@0:8{CGPoint=dd}16", "item setPosition:"},
            {DMSMSigCGSize, "{CGSize=dd}16@0:8", "item size"},
            {DMSMSigBool, "B16@0:8", "item isInDefaultPosition"},
            {DMSMSigVoidBool, "v20@0:8B16", "item setInDefaultPosition:"},
            {DMSMSigBool, "B16@0:8", "attributes isPositionSystemManaged"},
            {DMSMSigWithBool, "@20@0:8B16", "attributes attributesByModifyingPositionIsSystemManaged:"},
        };
        for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
            NSString *a = DMSMNormEncoding(sigs[i].apple), *o = sigs[i].ours();
            Check([NSString stringWithFormat:@"17.0.3 signature: %s", sigs[i].what], [a isEqualToString:o], [NSString stringWithFormat:@"%@ / %@", a, o]);
        }
        // 2. the table choice
        Check(@"layout16: 16 rows in (12 of 16.1+, 12 of 16.0: its pass, the calculator, the bounding box), 17 rows out", Rows(16, 16) == 24 && Rows(16, 17) == 0, [NSString stringWithFormat:@"%lu / %lu", (unsigned long)Rows(16, 16), (unsigned long)Rows(16, 17)]);
        Check(@"layout17: 17 rows in, 16 rows out", Rows(17, 17) == 17 && Rows(17, 16) == 0, [NSString stringWithFormat:@"%lu / %lu", (unsigned long)Rows(17, 17), (unsigned long)Rows(17, 16)]);
        Check(@"shared rows in both tables", Rows(16, 0) == Rows(17, 0) && Rows(16, 0) > 50, [NSString stringWithFormat:@"%lu", (unsigned long)Rows(16, 0)]);
        Check(@"this Mac (macOS major >= 17 counts as 17) picks by version", DMSMLayoutGenFor(nil) == ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17 ? 17 : 16), @"");
        Check(@"simulate layout16 / layout17", DMSMLayoutGenFor(@"layout16") == 16 && DMSMLayoutGenFor(@"layout17") == 17, @"");
        NSUInteger n16 = 0, n17 = 0;
        NSArray *bad16 = DMSMCheckAPI(@"layout16", &n16), *bad17 = DMSMCheckAPI(@"layout17", &n17);
        Check(@"16 table here: the 16 layout classes reported missing", Has(bad16, @"class SBChamoisOverlappingController missing") && Has(bad16, @"class SBMutableChamoisOverlappingModel missing"), @"");
        Check(@"16 table: no 17 class asked for", !Has(bad16, @"SBContinuousExposeAutoLayout"), @"");
        Check(@"17 table: no 16 layout class asked for", !Has(bad17, @"SBChamoisOverlapping") && !Has(bad17, @"SBMutableChamoisOverlapping"), @"");
        // 3. every 17 row passes against the stand-ins
        NSMutableArray *bad17rows = [NSMutableArray array];
        for (NSString *l in bad17) if ([l containsString:@"SBContinuousExposeAutoLayout"]) [bad17rows addObject:l];
        Check(@"17 rows: all present with the headers' signatures", bad17rows.count == 0, [bad17rows componentsJoinedByString:@"; "]);
        Check(@"corner radius row: 18.2 name accepted", !Has(bad17, @"stageCornerRad"), @"");
        Check(@"17 table: the system-managed flag rows present with the headers' signatures", !Has(bad17, @"PositionSystemManaged") && !Has(bad17, @"isPositionSystemManaged"), @"");
        Check(@"16 table: no system-managed flag row", !Has(bad16, @"PositionSystemManaged"), @"");
        Check(@"17 table: roles check ran and passed", gSMRolesNote && [gSMRolesNote hasPrefix:@"ok"] && !Has(bad17, @"layout roles") && !Has(bad17, @"SBLayoutRole"), gSMRolesNote ?: @"(none)");
        gSMLayoutGen = 17;
        const char *corner = DMSMCornerRadiusSelector();
        Check(@"corner radius selector resolved to stageCornerRadii", corner && !strcmp(corner, "stageCornerRadii"), corner ? @(corner) : @"(none)");
        // a changed signature is caught (the same check code, pointed at a class with the snap method's stageArea as CGPoint)
        Method m = class_getInstanceMethod([SBChangedController class], @selector(snapPositionToNearestEdgesIfNecessaryForSpace:stageArea:configuration:));
        Check(@"a changed snap signature does not match", ![DMSMSigOfMethod(m) isEqualToString:DMSMSigSnap17()], DMSMSigOfMethod(m));
        // hooked rows of the 17 table: the IMPs list has one per hooked row, and all found
        NSArray *imps = DMSMHookedIMPs();
        NSUInteger nulls = 0; for (NSValue *v in imps) if (!v.pointerValue) nulls++;
        Check(@"17 hooked rows: 6 layout hooks found (+ shared ones missing here)", Rows(17, 17) == 17 && imps.count > 6, [NSString stringWithFormat:@"%lu IMPs, %lu not here", (unsigned long)imps.count, (unsigned long)nulls]);
        // 4. wrappers
        SBSwitcherChamoisLayoutAttributes *ca = [SBSwitcherChamoisLayoutAttributes new]; ca.prefersDockHidden = YES;
        SBContinuousExposeAutoLayoutConfiguration *cfg = [SBContinuousExposeAutoLayoutConfiguration new];
        cfg.containerBounds = CGRectMake(0, 0, 1194, 834); cfg.dockHeightWithBottomEdgePadding = 117.4; cfg.chamoisLayoutAttributes = ca;
        CGRect b; double d;
#if !defined(__x86_64__)   // (a CGRect result needs objc_msgSend_stret on an Intel Mac; iOS arm64, where the wrapper runs, has none)
        Check(@"configuration bounds", DMSMCfgBounds(cfg, &b) && CGRectEqualToRect(b, cfg.containerBounds), NSStringFromCGRect(b));
#else
        (void)b;
        printf("SKIP  configuration bounds (CGRect result: arm64 only)\n");
#endif
        Check(@"configuration Dock height", DMSMCfgDock(cfg, &d) && d == 117.4, [NSString stringWithFormat:@"%g", d]);
        Check(@"configuration prefersDockHidden / prefersStripHidden", DMSMCfgChamoisFlag(cfg, @"prefersDockHidden") && !DMSMCfgChamoisFlag(cfg, @"prefersStripHidden"), @"");
        Check(@"a flag that is not there reads NO", !DMSMCfgChamoisFlag(cfg, @"noSuchFlag"), @"");
#if !defined(__x86_64__)
        cfg.containerBounds = CGRectMake(0, 0, NAN, 834);
        Check(@"a nonsense container is refused", !DMSMCfgBounds(cfg, &b), @"");
#endif
        cfg.dockHeightWithBottomEdgePadding = -5;
        Check(@"a negative Dock height is refused", !DMSMCfgDock(cfg, &d), @"");
        Check(@"not a configuration: refused", !DMSMCfgBounds(@"x", &b) && !DMSMCfgDock(nil, &d) && !DMSMCfgBounds([SBContinuousExposeAutoLayoutSpace new], &b), @"");
        SBContinuousExposeAutoLayoutItem *it = [SBContinuousExposeAutoLayoutItem new]; it.position = CGPointMake(300, 400); it.size = CGSizeMake(500, 400); it.inDefaultPosition = YES;
        SBContinuousExposeAutoLayoutSpace *sp = [SBContinuousExposeAutoLayoutSpace new]; sp.items = @[it];
        NSArray *items = DMSMSpaceItems(sp);
        Check(@"space items", items.count == 1 && items[0] == it, @"");
        sp.items = @[it, @"not an item"];
        Check(@"a space with a foreign object: refused", DMSMSpaceItems(sp) == nil, @"");
        CGPoint p; CGSize z; BOOL def = NO;
        Check(@"item position / size / default flag", DMSMItemPosition(it, &p) && DMSMItemSize(it, &z) && DMSMItemInDefaultPosition(it, &def) && p.x == 300 && z.height == 400 && def, @"");
        Check(@"item setPosition: / setInDefaultPosition:", DMSMItemSetPosition(it, CGPointMake(10, 20)) && it.position.y == 20 && DMSMItemSetInDefaultPosition(it, NO) && !it.inDefaultPosition, @"");
        Check(@"a position that is not a number is refused", !DMSMItemSetPosition(it, CGPointMake(INFINITY, 0)) && it.position.x == 10, @"");
        it.size = CGSizeMake(0, 0);
        Check(@"an empty size is refused", !DMSMItemSize(it, &z), @"");
        Check(@"a refusal on the 17 table asks for the diagnostics record", gDiagSoon > 0, [NSString stringWithFormat:@"%d", gDiagSoon]);
        // 6. clamp
        CGRect area = CGRectMake(0, 44, 1194, 671);
        CGPoint c = DMSMClampCenter(CGPointMake(597, 400), CGSizeMake(1194, 500), area);
        Check(@"full-width window stays centred (no padding shift)", c.x == 597 && c.y == 400, NSStringFromCGPoint(c));
        c = DMSMClampCenter(CGPointMake(100, 30), CGSizeMake(400, 300), area);
        Check(@"window moved into the area (left and top)", c.x == 200 && c.y == 194, NSStringFromCGPoint(c));
        c = DMSMClampCenter(CGPointMake(597, 500), CGSizeMake(600, 800), area);
        Check(@"taller than the area: its top at the area's top", c.y == 444, NSStringFromCGPoint(c));
        c = DMSMClampCenter(CGPointMake(1100, 700), CGSizeMake(400, 300), area);
        Check(@"window moved into the area (right and bottom)", c.x == 994 && c.y == 565, NSStringFromCGPoint(c));
        // 7. the system-managed flag: wrappers and DMSMAttrWith (17 table: placed by the user; 16: unchanged)
        SBDisplayItemLayoutAttributes *at = [SBDisplayItemLayoutAttributes new]; at.managed = YES;
        BOOL man = NO;
        Check(@"isPositionSystemManaged read", DMSMAttrSystemManaged(at, &man) && man, @"");
        SBDisplayItemLayoutAttributes *u = DMSMAttrWithSystemManaged(at, NO);
        Check(@"attributesByModifyingPositionIsSystemManaged: gives a changed copy", u && u != at && !u.managed && at.managed, @"");
        DMSMAttributedSize sz = { CGSizeMake(0.5, 0.6), CGRectMake(0, 0, 1194, 834), 0 };
        gSMLayoutGen = 16;
        SBDisplayItemLayoutAttributes *w16 = DMSMAttrWith(at, sz, CGPointMake(0.4, 0.5), 0, 7);
        Check(@"16 table: DMSMAttrWith leaves the flag as it was", w16 && w16.managed && w16.time == 7 && w16.center.x == 0.4, @"");
        gSMLayoutGen = 17;
        unsigned placedBefore = gSMPlacedByUser;
        SBDisplayItemLayoutAttributes *w17 = DMSMAttrWith(at, sz, CGPointMake(0.4, 0.5), 0, 7);
        Check(@"17 table: DMSMAttrWith hands the window over as placed by the user", w17 && !w17.managed && w17.time == 7 && w17.sz.normalizedSize.width == 0.5 && gSMPlacedByUser == placedBefore + 1, @"");
        Check(@"17 table: already the user's -> the same object, not counted", DMSMAttrPlacedByUser(w17) == w17 && gSMPlacedByUser == placedBefore + 1, @"");
        Check(@"17 table: nil stays nil", DMSMAttrPlacedByUser(nil) == nil, @"");
        Check(@"not attributes: handed back unchanged (never fatal)", DMSMAttrPlacedByUser(@"x") == (id)@"x" || [DMSMAttrPlacedByUser(@"x") isEqual:@"x"], @"");
        // 8. the layout-role check (17 table): SpringBoard's own answer, through dlsym
        NSMutableArray *rb = [NSMutableArray array];
        DMSMCheckRoles17(rb, nil);
        Check(@"roles: exported stand-ins found, 1/2/5/6 valid, constants as ours", rb.count == 0 && [gSMRolesNote containsString:@"roles 1,2,5,6 valid"] && [gSMRolesNote containsString:@"additional 5..12"], gSMRolesNote ?: @"(none)");
        gTestRefuseRole = 5; [rb removeAllObjects];
        DMSMCheckRoles17(rb, nil);
        Check(@"roles: SpringBoard refusing role 5 fails the check", rb.count == 1 && [rb[0] containsString:@"layout roles 5"] && [gSMRolesNote hasPrefix:@"DIFFERENT"], [rb componentsJoinedByString:@"; "]);
        gTestRefuseRole = 0; [rb removeAllObjects];
        DMSMCheckRoles17(rb, @"roles");
        Check(@"roles: debug simulate 'roles' refuses role 6", rb.count == 1 && [rb[0] containsString:@"layout roles 6"], [rb componentsJoinedByString:@"; "]);
        // 9. one layout pass around 17.6.1's own (stand-in): container 1194 x 834, screen edge padding 48 (17.6.1's for this size), our stage area
        //    under the menu bar + title bar (48) and above the Dock (834 - 117 - 2)
        CGRect cont = CGRectMake(0, 0, 1194, 834), ours = CGRectMake(0, 48, 1194, 834 - 117 - 2 - 48);
        double pad = 48;
        {   // a lone system-managed window: Apple alone centres it
            SBContinuousExposeAutoLayoutSpace *s1 = [SBContinuousExposeAutoLayoutSpace new]; s1.items = @[Item(300, 400, 500, 400, YES)];
            ApplePass176(s1, cont, pad, ours);
            Check(@"pass: Apple alone centres a lone system-managed window", fabs(Pos(s1, 0).x - 597) < 0.5 && fabs(Pos(s1, 0).y - CGRectGetMidY(ours)) < 0.5, P(Pos(s1, 0)));
            SBContinuousExposeAutoLayoutSpace *s2 = [SBContinuousExposeAutoLayoutSpace new]; s2.items = @[Item(300, 400, 500, 400, YES)];
            DMSM17Pass ps = DMSM17PassBegin(s2, YES, cont);
            BOOL hidden = ps.loneHidden && !Def(s2, 0);
            CGRect a = ApplePass176(s2, cont, pad, ours);
            int mv = DMSM17PassEnd(&ps, a);
            Check(@"pass: our begin/end keep a lone system-managed window where it is", hidden && fabs(Pos(s2, 0).x - 300) < 0.5 && fabs(Pos(s2, 0).y - 400) < 0.5 && mv == 0, [NSString stringWithFormat:@"%@ moved %d", P(Pos(s2, 0)), mv]);
            Check(@"pass: its flag is back as it was afterwards", Def(s2, 0) && !ps.loneHidden, @"");
        }
        {   // a lone window placed by the user (DMSMAttrPlacedByUser): Apple alone already keeps it -- the cause fixed, not the effect
            SBContinuousExposeAutoLayoutSpace *s3 = [SBContinuousExposeAutoLayoutSpace new]; s3.items = @[Item(300, 400, 500, 400, NO)];
            ApplePass176(s3, cont, pad, ours);
            Check(@"pass: Apple alone keeps a lone window placed by the user", fabs(Pos(s3, 0).x - 300) < 0.5 && fabs(Pos(s3, 0).y - 400) < 0.5, P(Pos(s3, 0)));
        }
        {   // close to the left/top edges: Apple's padding pushes it in; ours keeps it at the screen edge, below the menu bar
            SBContinuousExposeAutoLayoutSpace *s4 = [SBContinuousExposeAutoLayoutSpace new]; s4.items = @[Item(260, 230, 500, 400, NO), Item(900, 400, 400, 300, NO)];
            DMSM17Pass ps = DMSM17PassBegin(s4, YES, cont);
            CGRect a = ApplePass176(s4, cont, pad, ours);
            CGPoint applesOwn = Pos(s4, 0);
            int mv = DMSM17PassEnd(&ps, a);
            Check(@"pass: Apple's padding moved the edge window in", fabs(applesOwn.x - 298) < 0.5 && fabs(applesOwn.y - 248) < 0.5, P(applesOwn));
            Check(@"pass: ours puts it back at the screen's left edge (top kept under the bar)", fabs(Pos(s4, 0).x - 260) < 0.5 && fabs(Pos(s4, 0).y - 248) < 0.5 && mv == 1, [NSString stringWithFormat:@"%@ moved %d", P(Pos(s4, 0)), mv]);
            Check(@"pass: the other window untouched", fabs(Pos(s4, 1).x - 900) < 0.5 && fabs(Pos(s4, 1).y - 400) < 0.5, P(Pos(s4, 1)));
        }
        {   // our full screen inside the stage beside a window with no place yet
            SBContinuousExposeAutoLayoutSpace *s5 = [SBContinuousExposeAutoLayoutSpace new]; s5.items = @[Item(597, 417, 1194, 834, NO), Item(0, 0, 500, 400, NO)];
            SBContinuousExposeAutoLayoutSpace *s5a = [SBContinuousExposeAutoLayoutSpace new]; s5a.items = @[Item(597, 417, 1194, 834, NO), Item(300, 300, 500, 400, NO)];
            ApplePass176(s5a, cont, pad, ours);
            Check(@"pass: Apple alone moves a full-screen window that is not alone (padding clamp)", fabs(Pos(s5a, 0).x - 549) < 0.5 && fabs(Pos(s5a, 0).y - 369) < 0.5, P(Pos(s5a, 0)));
            DMSM17Pass ps = DMSM17PassBegin(s5, YES, cont);
            CGRect a = ApplePass176(s5, cont, pad, ours);
            DMSM17PassEnd(&ps, a);
            Check(@"pass: our full screen beside a window ends centred on the screen (Apple's clamp moved it 48 pt)", fabs(Pos(s5, 0).x - 597) < 0.5 && fabs(Pos(s5, 0).y - 417) < 0.5, P(Pos(s5, 0)));
            Check(@"pass: a window with no place yet stays Apple's (centred in the stage area)", fabs(Pos(s5, 1).x - 597) < 0.5 && fabs(Pos(s5, 1).y - CGRectGetMidY(ours)) < 0.5, P(Pos(s5, 1)));
        }
        {   // a lone full-screen window that is system managed: Apple's default-position branch comes first and centres it in the STAGE AREA (y =
            //  its middle, 381.5 under our area) -- ours puts it back on the screen's centre; its flag is not touched
            SBContinuousExposeAutoLayoutSpace *s9 = [SBContinuousExposeAutoLayoutSpace new]; s9.items = @[Item(597, 417, 1194, 834, YES)];
            DMSM17Pass ps = DMSM17PassBegin(s9, YES, cont);
            BOOL untouched = !ps.loneHidden && Def(s9, 0);
            CGRect a = ApplePass176(s9, cont, pad, ours);
            CGPoint applesOwn = Pos(s9, 0);
            int mv = DMSM17PassEnd(&ps, a);
            Check(@"pass: Apple alone puts a lone system-managed full-screen window at the stage area's middle", fabs(applesOwn.y - CGRectGetMidY(ours)) < 0.5, P(applesOwn));
            Check(@"pass: ours puts it back on the screen's centre, flag untouched", untouched && Def(s9, 0) && fabs(Pos(s9, 0).x - 597) < 0.5 && fabs(Pos(s9, 0).y - 417) < 0.5 && mv == 1, [NSString stringWithFormat:@"%@ moved %d", P(Pos(s9, 0)), mv]);
        }
        {   // taller than our stage area: its top at the area's top (title bar reachable)
            SBContinuousExposeAutoLayoutSpace *s6 = [SBContinuousExposeAutoLayoutSpace new]; s6.items = @[Item(597, 500, 600, 800, NO), Item(200, 300, 300, 300, NO)];
            DMSM17Pass ps = DMSM17PassBegin(s6, YES, cont);
            CGRect a = ApplePass176(s6, cont, pad, ours);
            DMSM17PassEnd(&ps, a);
            Check(@"pass: a window taller than the area keeps its top at the area's top", fabs(Pos(s6, 0).y - (48 + 400)) < 0.5, P(Pos(s6, 0)));
        }
        {   // no container known (the configuration unreadable): nothing remembered, Apple's result stays; a nonsense area moves nothing
            SBContinuousExposeAutoLayoutSpace *s7 = [SBContinuousExposeAutoLayoutSpace new]; s7.items = @[Item(260, 230, 500, 400, YES)];
            DMSM17Pass ps = DMSM17PassBegin(s7, NO, CGRectZero);
            Check(@"pass: no container -> nothing remembered, flag not touched", !ps.loneHidden && Def(s7, 0), @"");
            SBContinuousExposeAutoLayoutSpace *s8 = [SBContinuousExposeAutoLayoutSpace new]; s8.items = @[Item(300, 400, 500, 400, YES)];
            DMSM17Pass p8 = DMSM17PassBegin(s8, YES, cont);
            int mv = DMSM17PassEnd(&p8, CGRectMake(0, 0, NAN, 10));
            Check(@"pass: a nonsense area moves nothing, the flag still comes back", mv == -1 && Def(s8, 0), [NSString stringWithFormat:@"%d", mv]);
        }
        // 10. the size grid (gridWidths / gridHeights): every whole point up to the screen; 17+ heights from 300 (17.6.1's list starts at 480)
        NSArray *appleH = @[@480, @530, @600, @700, @786], *appleW = @[@320, @414, @600, @1146], *trollH = @[@150, @170, @190, @786];
        gSMLayoutGen = 16;
        NSArray *g16 = DMSMFineGrid(appleH, 834, 1);
        Check(@"grid 16: heights from Apple's 480, every point to the screen", [g16.firstObject doubleValue] == 480 && [g16.lastObject doubleValue] == 834 && g16.count == 355, [NSString stringWithFormat:@"%@..%@ (%lu)", g16.firstObject, g16.lastObject, (unsigned long)g16.count]);
        gSMLayoutGen = 17;
        NSArray *g17 = DMSMFineGrid(appleH, 834, 1);
        Check(@"grid 17: heights from 300", [g17.firstObject doubleValue] == 300 && [g17.lastObject doubleValue] == 834 && g17.count == 535, [NSString stringWithFormat:@"%@..%@ (%lu)", g17.firstObject, g17.lastObject, (unsigned long)g17.count]);
        Check(@"grid 17: Apple's smallest height recorded for the diagnostics", gSMAppleGridLo[1] == 480, [NSString stringWithFormat:@"%g", gSMAppleGridLo[1]]);
        NSArray *gw17 = DMSMFineGrid(appleW, 1194, 0);
        Check(@"grid 17: widths keep Apple's minimum (320)", [gw17.firstObject doubleValue] == 320 && [gw17.lastObject doubleValue] == 1194, [NSString stringWithFormat:@"%@..%@", gw17.firstObject, gw17.lastObject]);
        NSArray *t17 = DMSMFineGrid(trollH, 834, 1);
        Check(@"grid 17: TrollPad's list (from 150) keeps its own start", [t17.firstObject doubleValue] == 150, [NSString stringWithFormat:@"%@", t17.firstObject]);
        NSArray *odd = @[@"480", @600];
        Check(@"grid: a list that is not all numbers is Apple's as it is", DMSMFineGrid(odd, 834, 1) == odd, @"");
        Check(@"grid: a screen too small for the floor keeps Apple's list start", [DMSMFineGrid(@[@200, @250], 280, 1).firstObject doubleValue] == 200, @"");
        // 11. the diagnostics' hook list leaves out the engine's hooks for the other iPadOS
        gSMLayoutGen = 17;
        Check(@"diag 17: iPadOS 16's layout hooks are not 'missing'", DMSMHookNotForThisOS("SBChamoisOverlappingController", "_horizontallyCenterModel:stageArea:") && DMSMHookNotForThisOS("SBMutableChamoisOverlappingModel", "setCenter:forItem:"), @"");
        Check(@"diag 17: the 17 layout hooks stay in the list", !DMSMHookNotForThisOS("SBContinuousExposeAutoLayoutController", "stageAreaForSpace:configuration:"), @"");
        Check(@"diag: the corner radius name that is not here is left out, the other kept", DMSMHookNotForThisOS("SBSwitcherChamoisLayoutAttributes", "stageCornerRaddii") && !DMSMHookNotForThisOS("SBSwitcherChamoisLayoutAttributes", "stageCornerRadii"), @"");
        Check(@"diag: an ordinary hook stays", !DMSMHookNotForThisOS("SBIconView", "_handleTap"), @"");
        printf("%d of %d passed\n", total - fails, total);
    }
    return fails ? 1 : 0;
}
