// test-smlayout17.m -- Mac test of the Stage Manager engine's version-aware self-check and its iPadOS 17 wrappers (statusbar/SMEngineAPI.h).
// There is no iPadOS 17 device: this checks, off the device,
//  1. that the signatures we check the iPadOS 17 layout engine with (DMSM_SIG ...17) equal the type encodings the 17.0.3 runtime headers describe
//     (the encodings written out here by hand from MTACS/iOS-17-Runtime-Headers, the types as the runtime prints them);
//  2. the table choice: iPadOS 16 -> only the rows of the 16 layout engine and the shared ones, 17 -> the 17 rows instead; a table whose classes
//     are missing fails (the engine stays off);
//  3. the 17 rows pass against stand-in classes with the headers' signatures, and a changed signature fails;
//  4. the checked wrappers (items, position, size, flags, configuration), including refusals of nonsense values;
//  5. the corner radius row: the 18.2 name (stageCornerRadii) is taken where the old one is missing;
//  6. DMSMClampCenter (windows kept inside the stage area, top/left winning).
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
        };
        for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
            NSString *a = DMSMNormEncoding(sigs[i].apple), *o = sigs[i].ours();
            Check([NSString stringWithFormat:@"17.0.3 signature: %s", sigs[i].what], [a isEqualToString:o], [NSString stringWithFormat:@"%@ / %@", a, o]);
        }
        // 2. the table choice
        Check(@"layout16: 16 rows in (12 of 16.1+, 12 of 16.0: its pass, the calculator, the bounding box), 17 rows out", Rows(16, 16) == 24 && Rows(16, 17) == 0, [NSString stringWithFormat:@"%lu / %lu", (unsigned long)Rows(16, 16), (unsigned long)Rows(16, 17)]);
        Check(@"layout17: 17 rows in, 16 rows out", Rows(17, 17) == 15 && Rows(17, 16) == 0, [NSString stringWithFormat:@"%lu / %lu", (unsigned long)Rows(17, 17), (unsigned long)Rows(17, 16)]);
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
        gSMLayoutGen = 17;
        const char *corner = DMSMCornerRadiusSelector();
        Check(@"corner radius selector resolved to stageCornerRadii", corner && !strcmp(corner, "stageCornerRadii"), corner ? @(corner) : @"(none)");
        // a changed signature is caught (the same check code, pointed at a class with the snap method's stageArea as CGPoint)
        Method m = class_getInstanceMethod([SBChangedController class], @selector(snapPositionToNearestEdgesIfNecessaryForSpace:stageArea:configuration:));
        Check(@"a changed snap signature does not match", ![DMSMSigOfMethod(m) isEqualToString:DMSMSigSnap17()], DMSMSigOfMethod(m));
        // hooked rows of the 17 table: the IMPs list has one per hooked row, and all found
        NSArray *imps = DMSMHookedIMPs();
        NSUInteger nulls = 0; for (NSValue *v in imps) if (!v.pointerValue) nulls++;
        Check(@"17 hooked rows: 6 layout hooks found (+ shared ones missing here)", Rows(17, 17) == 15 && imps.count > 6, [NSString stringWithFormat:@"%lu IMPs, %lu not here", (unsigned long)imps.count, (unsigned long)nulls]);
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
        printf("%d of %d passed\n", total - fails, total);
    }
    return fails ? 1 : 0;
}
