// test-gripsfollow.m -- Mac test (Mac Catalyst: UIKit on the Mac) of every engine's resize grips following their colour's inputs at once (1.8.7.5,
// review of audit track f, finding 3: engine parity of audit L41 of 1.8.7.2). A window's grips take their colour from Tint Resize Handles, light
// or dark, and the tint its app reports (MacAppBridge: a notify state, no post). Each engine set that colour only in a pass of its own: Zetsu's
// every tick, Aerial 5's theme tick (light or dark at once, the rest within a second), Aerial 3's and MilkyWay4's at their window's next layout,
// the Stage Manager engine's at its card's layout (an app's tint coming in late waited for it). Now the 0.2 s watcher's DMWindowedGripsFollow gives
// every shown grip of every engine the colour its own pass gives it, when it has another.
// Runs the real DMWindowedGripsFollow, DMWindowedGripsOf, DMResizeGripColorFor (its notify state read on this Mac's notifyd), DMResizeGripColor,
// DMMakeResizeGrip and the grips' keys, cut out of statusbar/StatusBar.x by test-gripsfollow.sh into gf-real.inc; each engine's windows are built
// as its own pass leaves them (the same keys, the same views), on stand-in classes of the engines' names.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <notify.h>

#define DM_FEATURE_MARK(name) do { } while (0)
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
UIColor *DMIconAccent(NSString *bundleID) { return nil; }   // (no icon colour: the app's reported tint or the neutral grip)
// ---- the engines' windows (stand-ins of their names) and a grip that counts its colour writes
@interface AerialStage : UIView
@end
@implementation AerialStage
@end
@interface ZetsuWindow : UIView
@end
@implementation ZetsuWindow
@end
@interface AXWindowView : UIView
@property (nonatomic, strong) UIView *sizeChanger;
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation AXWindowView
@end
static int gKWrites;
@interface KGrip : UIView
@end
@implementation KGrip
- (void)setBackgroundColor:(UIColor *)c { gKWrites++; [super setBackgroundColor:c]; }
@end

#include "gf-lines.inc"   // (the engines' names, the grips' keys, Tint Resize Handles, the Stage Manager engine's cards)

// ---- what the code asks: the engine, the windows, their apps, the screen's style
static DMEngine gKEngine = DMEngineAerial; static BOOL gKSM = NO, gKWork = YES;
static UIUserInterfaceStyle gKStyle = UIUserInterfaceStyleLight;
static NSArray<UIView *> *gKWindows;
static char kKBundleKey;
static DMEngine DMActiveEngine(void) { return gKEngine; }
static BOOL DMSMEngine(void) { return gKSM; }
static BOOL DMWindowWorkNeeded(void) { return gKWork; }
static UIUserInterfaceStyle DMSystemInterfaceStyle(void) { return gKStyle; }
static NSArray<UIView *> *DMAerialStagesAll(void) { return gKWindows; }
static NSString *DMStageBundle(UIView *w) { return [w isKindOfClass:[AXWindowView class]] ? ((AXWindowView *)w).bundleIdentifier : objc_getAssociatedObject(w, &kKBundleKey); }
static NSString *DMSMCardBundle(UIView *card) { return objc_getAssociatedObject(card, &kKBundleKey); }

#include "gf-real.inc"   // (DMMakeResizeGrip, DMResizeGripColor, DMResizeGripColorFor, DMWindowedGripsOf, DMWindowedGripsFollow)

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the app's tint as MacAppBridge reports it (the same notify name DMResizeGripColorFor reads)
static void Tint(NSString *bundle, CGFloat r, CGFloat g, CGFloat b) {   // (r < 0: none reported)
    uint32_t hash = 2166136261u;
    for (const char *c = bundle.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
    char name[80]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.tint.%08x", hash);
    int t = 0; notify_register_check(name, &t);
    uint64_t st = r < 0 ? 0 : ((1ULL << 32) | ((uint64_t)lround(r * 255) << 24) | ((uint64_t)lround(g * 255) << 16) | ((uint64_t)lround(b * 255) << 8) | 255);
    notify_set_state(t, st);
}
static NSString *const kA3 = @"com.example.gripsfollow.aerial3", *const kA5 = @"com.example.gripsfollow.aerial5", *const kZ = @"com.example.gripsfollow.zetsu";
static NSString *const kMW = @"com.example.gripsfollow.milkyway", *const kSMA = @"com.example.gripsfollow.stagemanager";
static UIWindow *gWin;
static UIView *Grip(void) { KGrip *g = [[KGrip alloc] initWithFrame:CGRectMake(0, 0, kResizeGripLength, kResizeGripThickness)]; g.userInteractionEnabled = NO; return g; }
// Each engine's window as its own pass leaves it, its grips in the colour that pass gave them (light, the inputs as they are now)
static UIView *Aerial3(NSString *bundle) {   // (DMStyleStage: two grips on the stage)
    AerialStage *s = [[AerialStage alloc] initWithFrame:CGRectMake(100, 100, 500, 400)]; [gWin addSubview:s];
    objc_setAssociatedObject(s, &kKBundleKey, bundle, OBJC_ASSOCIATION_COPY_NONATOMIC);
    for (int i = 0; i < 2; i++) { UIView *g = Grip(); [s addSubview:g]; objc_setAssociatedObject(s, i == 0 ? kStageGripBLKey : kStageGripBRKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC); g.backgroundColor = DMResizeGripColorFor(bundle, NO); }
    return s;
}
static UIView *Boxed(Class cls, NSString *bundle, const void *lk, const void *rk) {   // (Aerial 5 DMAerial5Theme / Zetsu DMZetsuMacShape: the grip in a box)
    UIView *w = [[cls alloc] initWithFrame:CGRectMake(100, 100, 500, 400)]; [gWin addSubview:w];
    objc_setAssociatedObject(w, &kKBundleKey, bundle, OBJC_ASSOCIATION_COPY_NONATOMIC);
    for (int i = 0; i < 2; i++) {
        UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)], *g = Grip(); [box addSubview:g]; [w addSubview:box];
        objc_setAssociatedObject(w, i == 0 ? lk : rk, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC); g.backgroundColor = DMResizeGripColorFor(bundle, NO);
    }
    return w;
}
static UIView *Aerial5(NSString *bundle) { return Boxed([AerialStage class], bundle, kA5GripBLKey, kA5GripBRKey); }
static UIView *Zetsu(NSString *bundle) { return Boxed([ZetsuWindow class], bundle, kZetsuGripLKey, kZetsuGripRKey); }
static UIView *MilkyWay(NSString *bundle) {   // (DMRestyleWindowButtons: one grip on its size changer)
    AXWindowView *w = [[AXWindowView alloc] initWithFrame:CGRectMake(100, 100, 500, 400)]; w.bundleIdentifier = bundle; [gWin addSubview:w];
    w.sizeChanger = [[UIView alloc] initWithFrame:CGRectMake(468, 368, 32, 32)]; [w addSubview:w.sizeChanger];
    UIView *g = Grip(); [w.sizeChanger addSubview:g]; objc_setAssociatedObject(w.sizeChanger, kMWGripKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC); g.backgroundColor = DMResizeGripColorFor(bundle, NO);
    return w;
}
static UIView *Card(NSString *bundle) {   // (our Stage Manager engine, DMSMPlaceGrips: two grips on the card, in gSMCards)
    UIView *c = [[UIView alloc] initWithFrame:CGRectMake(100, 100, 500, 400)]; [gWin addSubview:c];
    objc_setAssociatedObject(c, &kKBundleKey, bundle, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (!gSMCards) gSMCards = [NSHashTable weakObjectsHashTable];
    [gSMCards addObject:c];
    for (int i = 0; i < 2; i++) { UIView *g = Grip(); [c addSubview:g]; objc_setAssociatedObject(c, i == 0 ? &kSMGripLKey : &kSMGripRKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC); g.backgroundColor = DMResizeGripColorFor(bundle, NO); }
    return c;
}
static NSArray<UIView *> *GripsOf(UIView *w) {   // (the test's own reading of where each engine keeps them)
    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        UIView *g = objc_getAssociatedObject(w, i == 0 ? kStageGripBLKey : kStageGripBRKey); if (g) [out addObject:g];
        const void *boxes[2] = { i == 0 ? kA5GripBLKey : kA5GripBRKey, i == 0 ? kZetsuGripLKey : kZetsuGripRKey };
        for (int j = 0; j < 2; j++) { UIView *bx = objc_getAssociatedObject(w, boxes[j]); if (bx.subviews.firstObject) [out addObject:bx.subviews.firstObject]; }
        g = objc_getAssociatedObject(w, i == 0 ? &kSMGripLKey : &kSMGripRKey); if (g) [out addObject:g];
    }
    if ([w isKindOfClass:[AXWindowView class]]) { UIView *g = objc_getAssociatedObject(((AXWindowView *)w).sizeChanger, kMWGripKey); if (g) [out addObject:g]; }
    return out;
}
static BOOL Colour(UIView *w, UIColor *c) { NSArray *gs = GripsOf(w); if (!gs.count) return NO; for (UIView *g in gs) if (![g.backgroundColor isEqual:c]) return NO; return YES; }
static void Reset(DMEngine e, BOOL sm) {
    gKLog = [NSMutableArray array]; gKEngine = e; gKSM = sm; gKWork = YES; gKStyle = UIUserInterfaceStyleLight; gTintGrips = NO; gKWrites = 0;
    gWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)]; gWin.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    gSMCards = [NSHashTable weakObjectsHashTable];
    for (NSString *b in @[kA3, kA5, kZ, kMW, kSMA]) Tint(b, -1, 0, 0);
}
static void Tick(void) { DMWindowedGripsFollow(); }
static void Dark(void) {   // (Dark Mode: the screen's style, and the windows' traits brought up to date as UIKit does before its next pass)
    gKStyle = UIUserInterfaceStyleDark; gWin.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if ([gWin respondsToSelector:@selector(updateTraitsIfNeeded)]) [gWin performSelector:@selector(updateTraitsIfNeeded)];
    [gWin layoutIfNeeded];
}
// One engine's window through the four changes, each followed by one tick of the watcher
static void Engine(NSString *name, DMEngine e, BOOL sm, NSString *bundle, UIView *(^make)(NSString *)) {
    Reset(e, sm);
    UIView *w = make(bundle);
    gKWindows = sm ? @[] : @[w];
    Tick();   // (the inputs as they were: nothing to do)
    int before = gKWrites;
    Tint(bundle, 0.1, 0.3, 0.9);   // (the app's tint reported, Tint Resize Handles still off)
    Tick();
    Check(Colour(w, DMResizeGripColor(NO)) && gKWrites == before, [NSString stringWithFormat:@"%@: nothing changed for the grips (Tint Resize Handles off): no colour written", name]);
    gTintGrips = YES;   // (Settings > Tint Resize Handles on)
    Tick();
    UIColor *blue = [UIColor colorWithRed:lround(0.1 * 255) / 255.0 green:lround(0.3 * 255) / 255.0 blue:lround(0.9 * 255) / 255.0 alpha:0.55];
    Check(Colour(w, blue), [NSString stringWithFormat:@"%@: Tint Resize Handles switched on: the open window's grips take the app's tint at the next tick", name]);
    Dark();
    Tick();
    UIColor *blueDark = [UIColor colorWithRed:lround(0.1 * 255) / 255.0 green:lround(0.3 * 255) / 255.0 blue:lround(0.9 * 255) / 255.0 alpha:0.62];
    Check(Colour(w, blueDark), [NSString stringWithFormat:@"%@: Dark Mode: the grips take the dark shade at the next tick", name]);
    Tint(bundle, 0.2, 0.8, 0.3);   // (the app's tint coming in late, or changed: MacAppBridge's next report)
    Tick();
    UIColor *green = [UIColor colorWithRed:lround(0.2 * 255) / 255.0 green:lround(0.8 * 255) / 255.0 blue:lround(0.3 * 255) / 255.0 alpha:0.62];
    Check(Colour(w, green), [NSString stringWithFormat:@"%@: the app's tint coming in late: the grips follow it at the next tick", name]);
    gTintGrips = NO;
    Tick();
    Check(Colour(w, DMResizeGripColor(YES)), [NSString stringWithFormat:@"%@: Tint Resize Handles off: the neutral grips at the next tick", name]);
    before = gKWrites;
    Tick(); Tick();
    Check(gKWrites == before, [NSString stringWithFormat:@"%@: inputs unchanged: no colour written at the next ticks", name]);
}

int main(void) {
    @autoreleasepool {
        printf("-- each engine: Tint Resize Handles, Dark Mode, the app's tint coming in late, Tint off -- one watcher tick each\n");
        Engine(@"Aerial 3.0", DMEngineAerial, NO, kA3, ^UIView *(NSString *b) { return Aerial3(b); });
        Engine(@"Aerial 5", DMEngineAerial, NO, kA5, ^UIView *(NSString *b) { return Aerial5(b); });
        Engine(@"Zetsu", DMEngineZetsu, NO, kZ, ^UIView *(NSString *b) { return Zetsu(b); });
        Engine(@"MilkyWay4", DMEngineMilkyWay, NO, kMW, ^UIView *(NSString *b) { return MilkyWay(b); });
        Engine(@"Stage Manager engine", DMEngineNone, YES, kSMA, ^UIView *(NSString *b) { return Card(b); });

        printf("-- the rest\n");
        // several windows of different apps: each its own app's tint
        Reset(DMEngineAerial, NO);
        UIView *a = Aerial3(kA3), *b = Aerial3(kA5);
        gKWindows = @[a, b];
        Tint(kA3, 0.9, 0.2, 0.1); Tint(kA5, 0.1, 0.3, 0.9);
        gTintGrips = YES;
        Tick();
        Check([GripsOf(a).firstObject.backgroundColor isEqual:DMResizeGripColorFor(kA3, NO)] && [GripsOf(b).firstObject.backgroundColor isEqual:DMResizeGripColorFor(kA5, NO)]
              && ![GripsOf(a).firstObject.backgroundColor isEqual:GripsOf(b).firstObject.backgroundColor], @"two windows of two apps: each takes its own app's tint");
        Check(gKLog.count == 1 && [gKLog.firstObject containsString:@"2 window(s): resize grips in the colour"], @"... the log says how many windows took a new colour (once)");
        // hidden grips are left as their pass left them (shown again by that pass, in the colour it gives then)
        Reset(DMEngineAerial, NO);
        UIView *h3 = Aerial3(kA3), *h5 = Aerial5(kA5);
        gKWindows = @[h3, h5];
        for (UIView *g in GripsOf(h3)) g.hidden = YES;   // (Aerial 3.0: its handle hidden -- a locked window)
        for (int i = 0; i < 2; i++) ((UIView *)objc_getAssociatedObject(h5, i == 0 ? kA5GripBLKey : kA5GripBRKey)).hidden = YES;   // (Aerial 5: its box hidden)
        gTintGrips = YES; Tint(kA3, 0.9, 0.2, 0.1); Tint(kA5, 0.9, 0.2, 0.1); gKWrites = 0;
        Tick();
        Check(gKWrites == 0 && Colour(h3, DMResizeGripColor(NO)) && Colour(h5, DMResizeGripColor(NO)), @"hidden grips, or grips in a hidden box: not touched");
        Reset(DMEngineMilkyWay, NO);
        UIView *hm = MilkyWay(kMW);
        gKWindows = @[hm];
        GripsOf(hm).firstObject.hidden = YES;   // (MilkyWay4: its size changer hidden, the grip with it)
        gTintGrips = YES; Tint(kMW, 0.9, 0.2, 0.1); gKWrites = 0;
        Tick();
        Check(gKWrites == 0, @"MilkyWay4: a hidden grip is not touched");
        Reset(DMEngineNone, YES);
        UIView *hc = Card(kSMA);
        for (UIView *g in GripsOf(hc)) g.hidden = YES;   // (Stage Manager's own handles, or a card in the App Switcher)
        gTintGrips = YES; Tint(kSMA, 0.9, 0.2, 0.1); gKWrites = 0;
        Tick();
        Check(gKWrites == 0, @"Stage Manager engine: grips hidden for Stage Manager's own handles or the App Switcher: not touched");
        // the Stage Manager engine's grips by the card's own style, as DMSMPlaceGrips (the screen's style may say otherwise)
        Reset(DMEngineNone, YES);
        UIView *cd = Card(kSMA);
        gTintGrips = YES; Tint(kSMA, 0.9, 0.2, 0.1);
        gKStyle = UIUserInterfaceStyleDark;   // (the screen dark, the card's window held light)
        Tick();
        Check(Colour(cd, DMResizeGripColorFor(kSMA, NO)), @"Stage Manager engine: the card's own light or dark decides, as DMSMPlaceGrips (no taking turns with it)");
        // no engine of ours, or no window work: nothing
        Reset(DMEngineNone, NO);
        UIView *n0 = Aerial3(kA3);
        gKWindows = @[n0];
        gTintGrips = YES; Tint(kA3, 0.9, 0.2, 0.1); gKWrites = 0;
        Tick();
        Check(gKWrites == 0, @"no engine of ours: nothing touched");
        Reset(DMEngineAerial, NO);
        UIView *n1 = Aerial3(kA3);
        gKWindows = @[n1]; gKWork = NO;
        gTintGrips = YES; Tint(kA3, 0.9, 0.2, 0.1); gKWrites = 0;
        Tick();
        Check(gKWrites == 0, @"no window work (no window for 3 s): nothing looked at");
        for (NSString *bb in @[kA3, kA5, kZ, kMW, kSMA]) Tint(bb, -1, 0, 0);
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
