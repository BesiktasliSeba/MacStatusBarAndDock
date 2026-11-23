// test-displayinuse.m -- Mac test of the display in use with another display up (1.8.8.2, B81; KT: "as on a Mac with two displays: the app you last
// touched or clicked is the active one"): which window is the active one after each step of the device rows, by the REAL code, cut out of
// statusbar/StatusBar.x by tools/test-displayinuse.sh: DMSMFrontWindowKeyNow and DMSMNewestKeyNow, DMSMInUseStageNow, the DMBarFrontInUse...
// functions (the state, the user's touch, the hold of an action from the other display's bar, the keys asked back), DMSMNewestKeyIn, with
// common/DisplayInUse.h and statusbar/SMWindowKey.h as they are. SpringBoard is a world model: the recent stages (each on its display, its windows
// with their interaction times), what each display's switcher shows, SpringBoard's front app and keyboard focus, the screens, a clock. Built with
// HAS_INUSE 0 (the code before the fix: only DMSMFrontWindowKeyNow and DMSMNewestKeyIn found) the hooks do nothing, as there. Plain Foundation.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#if HAS_INUSE
#include "../common/DisplayInUse.h"
#endif
#include "../statusbar/SMWindowKey.h"

@interface UIWindow : NSObject
@property (nonatomic) BOOL hidden;
@end
@implementation UIWindow
@end
@interface UIView : NSObject
@property (nonatomic, strong) UIWindow *window;
- (void)setNeedsLayout;
@end
@implementation UIView
- (void)setNeedsLayout {}
@end
@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
@end
static UIScreen *gMain, *gTVScreen;
@implementation UIScreen
+ (UIScreen *)mainScreen { return gMain; }
@end
// a stage: its display and its windows (window key -> @{@"t": interaction time})
@interface TStage : NSObject
@property (nonatomic, copy) NSString *ident;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *items;
@end
@implementation TStage
@end
#define DM_FEATURE_MARK(name) do { } while (0)
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s ?: @""]; }

// ---- the world ----
static double gNow = 100.0;
static double CACurrentMediaTime(void) { return gNow; }
static BOOL gSM = YES, gTVUp = YES, gSkipped = NO, gHW = YES;
static NSString *gFrontApp;               // (SpringBoard's -_accessibilityFrontMostApplication: any display's)
static NSString *gKeysTo;                 // (SpringBoard's keyboard focus: an app)
static NSMutableArray<TStage *> *gRecent; // (the recent stages, most recent first)
static BOOL gIPadRead = YES, gTVRead = YES; static long long gIPadEnv = 3, gTVEnv = 3; static TStage *gIPadShown, *gTVShown;
static NSMutableArray<NSString *> *gFocusAsked;   // (the scenes the keys were asked for)
static NSHashTable *gCopies;
static NSString *gSMFullActive = nil, *gSMFullActiveOver = nil;

static TStage *St(NSString *ident, NSDictionary *items) { TStage *s = [TStage new]; s.ident = ident; s.items = [items mutableCopy]; return s; }
static NSDictionary *W(long t) { return @{@"t": @(t)}; }
static NSArray *DMSMRecentStages(void) { return gRecent; }
static id DMSMStageDisplayIdentity(id stage) { return ((TStage *)stage).ident; }
static BOOL DMSMIsMainIdentity(id identity) { return !identity || [identity isEqual:@"ipad"]; }
static id DMSMIdentityOfScreen(UIScreen *s) { return s == gMain ? @"ipad" : (s == gTVScreen ? @"tv" : nil); }
static NSArray<UIScreen *> *DMDispScreens(void) { return gTVUp ? @[gMain, gTVScreen] : @[gMain]; }
static NSDictionary *DMSMStageItemsMap(id stage) { return ((TStage *)stage).items; }
static NSString *DMSMItemKey(id item) { return item; }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { NSNumber *t = ((NSDictionary *)attrs)[@"t"]; return t ? t.longLongValue : dflt; }
static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {
    NSDictionary *m = DMSMStageItemsMap(stage);
    if (m[key]) { if (attrsOut) *attrsOut = m[key]; return key; }
    if (DMSMKeyIsApp(key)) for (NSString *k in m) if ([DMSMKeyBundle(k) isEqualToString:key]) { if (attrsOut) *attrsOut = m[k]; return k; }
    return nil;
}
static id DMSMShownMainStage(void) { return gIPadRead && gIPadEnv == 3 && [gRecent containsObject:gIPadShown] ? gIPadShown : nil; }
static id DMSMFrontStageOnDisplay(id identity) {
    if (DMSMIsMainIdentity(identity)) { id shown = DMSMShownMainStage(); if (shown) return shown; }
    for (TStage *s in gRecent) if (DMSMIsMainIdentity(identity) ? DMSMIsMainIdentity(s.ident) : [s.ident isEqual:identity]) return s;
    return nil;
}
static id DMSMFrontStage(void) { return DMSMFrontStageOnDisplay(@"ipad") ?: gRecent.firstObject; }
static BOOL DMSMStageShownOnDisplay(id al, id identity) { return al && al == gTVShown && gTVEnv == 3 && [identity isEqual:@"tv"]; }
static id DMSMIPadStageShown(void) { return gIPadRead ? DMSMShownMainStage() : (gFrontApp ? DMSMFrontStage() : nil); }
static id DMSMStageOf(NSString *key) { for (TStage *s in gRecent) if (DMSMItemFor(s, key, nil)) return s; return DMSMFrontStage(); }
static NSString *DMFrontApp(void) { return gFrontApp; }
static BOOL DMSMEngine(void) { return gSM; }
static BOOL DMBarFrontSkipped(void) { return gSkipped; }
static BOOL DMBarFrontSwitcherOn(UIScreen *screen, long long *env, id *stage) {
    if (screen == gMain) { *env = gIPadRead ? gIPadEnv : 0; *stage = gIPadRead && gIPadEnv == 3 ? gIPadShown : nil; return gIPadRead; }
    *env = gTVRead ? gTVEnv : 0; *stage = gTVRead && gTVEnv == 3 ? gTVShown : nil; return gTVRead;
}
static void DMSnapForgetSMFront(void) {}
static void DMSMRefreshBars(void) {}
static NSString *DMSMFullScreenUnderWindows(void) { return nil; }
static void DMSMFullScreenActiveEnd(void) { gSMFullActive = nil; }
static NSString *DMSMFrontWindowKey(void);
static BOOL DMHardwareKeyboardAttached(void) { return gHW; }
static int DMBarFrontKeysTo(NSString *bundle) { return bundle.length && [gKeysTo isEqualToString:bundle] ? 1 : 0; }
static id DMCall(id o, NSString *sel) { (void)o; (void)sel; return nil; }
static id DMKeyboardFocusController(void) { return @"kfc"; }
static id DMKBSceneForApp(NSString *app) { return app.length ? [@"scene:" stringByAppendingString:app] : nil; }
static int gAskedTotal = 0;   // (every ask, across the scenarios: the iPad alone's sweep asks none)
static int gRefuse = 0;   // (asks SpringBoard takes but the keys stay -- or go straight back: the other display's app takes them again, seen on iPadOS 18.5)
static BOOL DMKBUserFocusRequest(id kfc, id scene, NSString *why) { (void)kfc; (void)why; if (!scene) return NO; gAskedTotal++; [gFocusAsked addObject:scene]; if (gRefuse > 0) { gRefuse--; return YES; } gKeysTo = [[scene description] substringFromIndex:6]; return YES; }
static NSString *DMBarFrontKeysHolder(void) { return gKeysTo; }   // (the keys' app; @"": SpringBoard holds them itself -- a menu's lock, Spotlight)
static id gOverlay;   // (one of our menus or dialogs open)
// (the real code's later steps -- the keys asked back 0.5 s on -- run only in the scenario that scheduled them: Reset starts a new generation, and a
//  step left from an earlier one does nothing; every step scheduled is counted, the iPad alone's sweep schedules none)
static int gGen = 0, gAfterScheduled = 0;
static void TDispatchAfter(dispatch_time_t when, dispatch_queue_t q, dispatch_block_t b) { int g = gGen; gAfterScheduled++; dispatch_after(when, q, ^{ if (g == gGen) b(); }); }
#define dispatch_after TDispatchAfter

// ---- the real code ----
#include "newestkeyin.inc"
#if HAS_INUSE
static MSBDInUseState gDMInUse;
static id gDMInUseOther;
static void DMBarFrontInUseKeysBack(NSString *acted, int left);
static void DMBarFrontInUseKeysStep(NSString *acted, int left, int asks);
#include "inuse.inc"
#include "stagenow.inc"
#else
static id DMSMInUseStageNow(void) { return nil; }
static void DMBarFrontInUseUser(id identity, NSString *why) { (void)identity; (void)why; }
static void DMBarFrontInUseFollow(void) {}
static void DMBarFrontInUseBarAction(NSString *key) { (void)key; }
static id DMBarFrontInUseIdentity(void) { TStage *f = gRecent.firstObject; return f ? f.ident : nil; }   // (1.8.8.1: the most recent stage's display)
#endif
#include "newestnow.inc"
#include "frontkey.inc"
static NSString *DMSMFrontWindowKey(void) { return DMSMFrontWindowKeyNow(); }

// 1.8.8.1.1's DMSMFrontWindowKeyNow, verbatim (no full-screen window made active behind the windows): the iPad alone must answer as it
static NSString *Old(void) {
    id stage = [DMSMRecentStages() firstObject];
    if (!stage || DMSMIsMainIdentity(DMSMStageDisplayIdentity(stage))) { id shown = DMSMShownMainStage(); if (shown) stage = shown; }   // (the stage on screen, not the one a quick switch left first: DMSMShownMainStage)
    if (DMSMIsMainIdentity(DMSMStageDisplayIdentity(stage)) && !DMFrontApp()) return nil;   // (the iPad's Home Screen, no TV stage in use)
    NSDictionary *map = DMSMStageItemsMap(stage);
    id best = nil; long newest = LONG_MIN;
    for (id item in map) {
        long t = DMSMAttrTimeOr(map[item], 0);
        if (t > newest) { newest = t; best = item; }
    }
    return best ? DMSMItemKey(best) : nil;
}

static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
#define SET @"com.apple.Preferences|sceneID:com.apple.Preferences-default"
#define CALC @"com.apple.calculator|sceneID:com.apple.calculator-default"
#define TIPS @"com.apple.tips|sceneID:com.apple.tips-default"
#define CLOCK @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default"
static NSString *Name(NSString *k) { return k ? (DMSMKeyBundle(k) ?: k) : @"none"; }
static void ExpectActive(NSString *want, NSString *what) {
    NSString *got = DMSMFrontWindowKeyNow();
    BOOL ok = want ? [got isEqualToString:want] : got == nil;
    Expect(ok, [NSString stringWithFormat:@"%@ -- active %@ (want %@)", what, Name(got), Name(want)]);
}
static void Reset(void) {
    gSM = YES; gTVUp = YES; gSkipped = NO; gHW = YES; gFrontApp = nil; gKeysTo = nil; gNow += 100.0;
    gRecent = [NSMutableArray array]; gIPadRead = gTVRead = YES; gIPadEnv = gTVEnv = 3; gIPadShown = gTVShown = nil;
    gFocusAsked = [NSMutableArray array]; gSMFullActive = nil; gGen++; gRefuse = 0; gOverlay = nil;
#if HAS_INUSE
    MSBDInUseForget(&gDMInUse); gDMInUseOther = nil;
#endif
}
static void Tick(double secs) { gNow += secs; (void)DMSMFrontWindowKeyNow(); }   // (the 0.25 s tick reads the front window)
static void RunLoop(double secs) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:secs]]; }
// SpringBoard: a stage comes first (a transition), shown on its display
static void SBFirst(TStage *s, BOOL shown) {
    [gRecent removeObject:s]; [gRecent insertObject:s atIndex:0];
    if (!shown) return;
    if ([s.ident isEqual:@"tv"]) { gTVShown = s; gTVEnv = 3; } else { gIPadShown = s; gIPadEnv = 3; }
}

int main(void) {
    @autoreleasepool {
        gLog = [NSMutableArray array]; gCopies = [NSHashTable weakObjectsHashTable];
        gMain = [UIScreen new]; gTVScreen = [UIScreen new];

        // ---- T3: Tips moved to the TV (its stage the most recent), then a click on the iPad's Settings window, in front of the iPad's stage ----
        Reset();
        TStage *ipad = St(@"ipad", @{SET: W(5)}), *tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = @"com.apple.tips"; gKeysTo = @"com.apple.tips";
        ExpectActive(TIPS, @"T3: Tips moved to the TV, its stage the most recent");
        gFrontApp = gKeysTo = @"com.apple.Preferences";   // (SpringBoard: the click gave Settings the keys, no transition)
        DMBarFrontInUseUser(@"ipad", @"a click in a window there");
        ExpectActive(SET, @"T3: a click on the iPad's Settings window (in front there, no transition): Settings active");
        Tick(0.25); Tick(1.0);
        ExpectActive(SET, @"T3: ... and it stays so (SpringBoard's order unchanged)");
        id inUse = DMBarFrontInUseIdentity();
        Expect(DMSMIsMainIdentity(inUse), [NSString stringWithFormat:@"T3: the bars' display in use is the iPad (%@)", inUse ?: @"ipad"]);
        { TStage *tv2 = St(@"tv", @{TIPS: W(6)}); NSUInteger i = [gRecent indexOfObject:tv]; gRecent[i] = tv2; gTVShown = tv2; tv = tv2; }   // (SpringBoard replaces the TV's stage, the same windows)
        Tick(0.25);
        ExpectActive(SET, @"T3: the TV's stage replaced by a copy (a layout pass): still Settings");
        DMBarFrontInUseUser(@"tv", @"a click in a window there");
        ExpectActive(TIPS, @"T3: then a click on the TV's Tips window: Tips active");

        // ---- T4: Calculator opened on the iPad (iPad first); Tips full screen on the TV; the TV bar's green takes it back to a window ----
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv;
        Tick(0.25);
        ipad.items[CALC] = W(9); SBFirst(ipad, YES); gFrontApp = gKeysTo = @"com.apple.calculator";   // (a launch on the iPad)
        Tick(0.25);
        ExpectActive(CALC, @"T4: Calculator opened on the iPad: active");
        DMBarFrontInUseBarAction(TIPS);   // (the TV bar's green: DMBarFrontLightTap)
        { TStage *tv2 = St(@"tv", @{TIPS: W(10)}); [gRecent removeObject:tv]; [gRecent insertObject:tv2 atIndex:0]; gTVShown = tv2; tv = tv2; }   // (its zoom back: a transition on the TV)
        gNow += 0.3; gFrontApp = gKeysTo = @"com.apple.tips";   // (SpringBoard gave Tips the keys with that transition)
        ExpectActive(CALC, @"T4: the TV bar's green (zoom back, a transition there): Calculator still active");
        Tick(0.25); Tick(1.0); Tick(1.0); Tick(1.0);
        ExpectActive(CALC, @"T4: ... 3 s later too (the hold over, SpringBoard's order as the transition left it)");
        RunLoop(1.8);
        Expect(gFocusAsked.count == 1 && [gFocusAsked.firstObject isEqual:@"scene:com.apple.calculator"], [NSString stringWithFormat:@"T4: the keys Tips took with that transition asked back for Calculator, once (%@)", [gFocusAsked componentsJoinedByString:@","]]);
        DMBarFrontInUseUser(@"ipad", @"a click in a window there"); RunLoop(0.1);
        ExpectActive(CALC, @"T4: a tap on the iPad's window or Dock icon: the iPad's app (as before)");

        // ---- T6: Settings active on the iPad, Tips a window on the TV; the TV bar's App menu > Minimize ----
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gKeysTo = @"com.apple.Preferences"; gHW = YES;
        Tick(0.25);
        DMBarFrontInUseUser(@"ipad", @"a click in a window there");
        Tick(1.0);
        ExpectActive(SET, @"T6: Settings active on the iPad");
        DMBarFrontInUseBarAction(TIPS);   // (DMBarFrontMinimize)
        SBFirst(tv, NO); gTVShown = nil; gTVEnv = 1;   // (Tips minimized: its hidden stage the most recent, the TV at its empty desktop)
        gNow += 0.4; ExpectActive(SET, @"T6: Minimize from the TV bar's App menu: Settings still active");
        Tick(1.0); Tick(1.0); Tick(1.0);
        ExpectActive(SET, @"T6: ... and after the hold (a minimized window's stage first is not an activation)");
        RunLoop(1.8);
        Expect(gFocusAsked.count == 0, @"T6: the keys stayed with Settings: nothing asked");
        DMBarFrontInUseFollow(); SBFirst(tv, YES); Tick(0.25);   // (Tips's icon on the TV's Dock: its window back on the TV)
        ExpectActive(TIPS, @"T6: Tips brought back from the TV's Dock: Tips active");

        // ---- T7b: Tips opened cold on the TV, then a finger tap on the iPad's Settings window ----
        Reset();
        ipad = St(@"ipad", @{SET: W(5)});
        gRecent = [@[ipad] mutableCopy]; gIPadShown = ipad;
        Tick(0.25);
        DMBarFrontInUseFollow(); tv = St(@"tv", @{TIPS: W(7)}); SBFirst(tv, YES); Tick(0.25);
        ExpectActive(TIPS, @"T7b: Tips opened cold on the TV: active");
        gNow += 1.1; DMBarFrontInUseUser(@"ipad", @"a window brought forward");   // (the tap's lift: DMSMBringToFront, Settings in front already)
        ExpectActive(SET, @"T7b: a finger tap on the iPad's Settings window 1.1 s later: Settings active");
        Tick(0.25); Tick(1.0);
        ExpectActive(SET, @"T7b: ... and it stays so");
        // (the same with the launch's transition landing 0.3 s after the tap)
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(3)});
        gRecent = [@[ipad, tv] mutableCopy]; gIPadShown = ipad; gTVEnv = 1;
        Tick(0.25);
        DMBarFrontInUseFollow(); DMBarFrontInUseUser(@"ipad", @"a window brought forward");
        gNow += 0.3; tv.items[TIPS] = W(8); SBFirst(tv, YES); Tick(0.1);
        ExpectActive(SET, @"T7b: a TV launch landing 0.3 s after the tap on Settings does not take it back");

        // ---- T5 / B86: the TV's last window closed (its stage taken out) while the iPad is in use; an older TV stage comes first, hidden ----
        Reset();
        TStage *old = St(@"tv", @{CLOCK: W(2)});
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad, old] mutableCopy]; gIPadShown = ipad; gTVShown = tv;
        Tick(0.25);
        DMBarFrontInUseUser(@"ipad", @"a click in a window there"); Tick(1.0);
        [gRecent removeObject:tv]; [gRecent removeObject:old]; [gRecent insertObject:old atIndex:0]; gTVShown = nil; gTVEnv = 1;
        Tick(0.25); Tick(1.0);
        ExpectActive(SET, @"T5: the TV's last window closed by its own red light: Settings still active (a hidden TV stage first is not an activation)");
        // the TV in use, its window minimized by its own title bar: the minimized window is not the active one
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv;
        Tick(0.25);
        ExpectActive(TIPS, @"the TV in use: Tips");
        gTVShown = nil; gTVEnv = 1; Tick(0.25);
        ExpectActive(nil, @"the TV in use at its empty desktop (Tips minimized there): no active window (Finder), not the minimized Tips");
        gTVRead = NO; gTVShown = tv; Tick(0.25);
        ExpectActive(TIPS, @"  ... the TV's switcher unread: its most recent stage, as 1.8.8.1");

        // ---- the keys go with the active window (review 1.8.8.2): a window made active without a touch in it, and a transition the hold kept ----
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = gKeysTo = @"com.apple.tips";
        Tick(0.25);
        ExpectActive(TIPS, @"R2 keys: the TV in use, Tips active, the keys with Tips");
        DMBarFrontInUseUser(@"ipad", @"its app's icon tapped there");   // (Settings' Dock icon on the iPad, Settings in front there: no transition, SpringBoard leaves the keys)
        ExpectActive(SET, @"R2 keys: Settings' Dock icon on the iPad: Settings active");
        RunLoop(1.8);
        Expect(gFocusAsked.count == 1 && [gFocusAsked.firstObject isEqual:@"scene:com.apple.Preferences"] && [gKeysTo isEqualToString:@"com.apple.Preferences"],
               [NSString stringWithFormat:@"R2 keys: the keys that stayed with Tips asked for Settings, once (%@): the typing goes to the active window", [gFocusAsked componentsJoinedByString:@","]]);
        gHW = NO; gKeysTo = @"com.apple.Preferences";
        DMBarFrontInUseUser(@"tv", @"a window brought forward"); RunLoop(1.8);   // (Tips from the Window menu, no hardware keyboard: nothing asked)
        ExpectActive(TIPS, @"R2 keys: Tips from the Window menu: Tips active");
        Expect(gFocusAsked.count == 1, @"R2 keys: ... without a hardware keyboard nothing is asked (the on-screen keyboard stays as iPadOS has it)");
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = gKeysTo = @"com.apple.tips";
        Tick(0.25);
        gFrontApp = gKeysTo = @"com.apple.Preferences";   // (a click in Settings' window: SpringBoard gave it the keys)
        DMBarFrontInUseUser(@"ipad", @"a click in a window there"); RunLoop(1.8);
        Expect(gFocusAsked.count == 0, @"R1 keys: a click in the iPad's window (SpringBoard moved the keys with it): nothing asked");
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(3)});
        gRecent = [@[ipad, tv] mutableCopy]; gIPadShown = ipad; gTVEnv = 1; gKeysTo = @"com.apple.Preferences";
        Tick(0.25);
        DMBarFrontInUseFollow(); gNow += 0.2; DMBarFrontInUseUser(@"ipad", @"a click in a window there");   // (Tips's icon on the TV's Dock, then a click in Settings)
        gNow += 0.3; tv.items[TIPS] = W(8); SBFirst(tv, YES); gKeysTo = @"com.apple.tips"; Tick(0.1);   // (the launch lands: SpringBoard gives Tips the keys)
        ExpectActive(SET, @"R7 keys: a TV launch landing 0.3 s after a click on Settings: Settings stays active");
        RunLoop(1.8);
        Expect(gFocusAsked.count == 1 && [gFocusAsked.firstObject isEqual:@"scene:com.apple.Preferences"],
               [NSString stringWithFormat:@"R7 keys: the keys that launch gave Tips asked back for Settings, once (%@)", [gFocusAsked componentsJoinedByString:@","]]);
        Tick(1.0); RunLoop(1.8);
        Expect(gFocusAsked.count == 1, @"R7 keys: ... and not again (the same stage read again is no new one)");

        // ---- the keys follow every way of making a window active (iPadOS 18.5: they stayed with the TV's app) ----
        // a click in Settings' window (or on its title bar) while Tips on the TV had them: SpringBoard did not move them, and they did not
        // come with one ask (Tips took them again): read again, asked again
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = gKeysTo = @"com.apple.tips";
        Tick(0.25);
        gRefuse = 1;
        DMBarFrontInUseUser(@"ipad", @"a click in a window there");
        RunLoop(2.2);
        Expect([gKeysTo isEqualToString:@"com.apple.Preferences"], [NSString stringWithFormat:@"click: a click in Settings' window while Tips had the keys, the first ask not taken: the keys with Settings in the end (%@; asked %@)", gKeysTo, [gFocusAsked componentsJoinedByString:@","]]);
        Expect(gFocusAsked.count == 2, [NSString stringWithFormat:@"click: ... asked twice: once, then again when they were read still with Tips (%lu)", (unsigned long)gFocusAsked.count]);
        // ... an app that takes them back every time: 3 asks at most, then said
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = gKeysTo = @"com.apple.tips";
        Tick(0.25);
        gRefuse = 99; [gLog removeAllObjects];
        DMBarFrontInUseUser(@"ipad", @"a click in a window there");
        RunLoop(3.2);
        BOOL said = NO; for (NSString *l in gLog) if ([l containsString:@"the keys stayed with com.apple.tips after 3 asks"]) said = YES;
        Expect(gFocusAsked.count == 3 && said, [NSString stringWithFormat:@"click: an app that takes the keys back every time: 3 asks, then the log says so (%lu asks)", (unsigned long)gFocusAsked.count]);
        // the Window menu: Settings picked from the iPad bar's Window menu while Tips on the TV had the keys: the transition it asks makes SpringBoard's
        // order name the iPad first (the state reads that before the activation is told), and while the menu is open SpringBoard holds the keys
        // itself (the menu's lock); on its close they go back to Tips
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = gKeysTo = @"com.apple.tips";
        Tick(0.25);
        ExpectActive(TIPS, @"Window menu: the TV in use, Tips active with the keys");
        gOverlay = @"menu"; gKeysTo = @"";   // (the Window menu open: its lock)
        ipad.items[SET] = W(11); SBFirst(ipad, YES); Tick(0.1);   // (DMBarFrontActivate's transition: the iPad's stage first, read by the tick)
        DMBarFrontInUseUser(@"ipad", @"a window made active from its display's menu bar");
        ExpectActive(SET, @"Window menu: Settings made active from the iPad bar's Window menu");
        RunLoop(1.6);
        Expect(gFocusAsked.count == 0, @"Window menu: nothing asked while the menu holds the keys");
        gOverlay = nil; gKeysTo = @"com.apple.tips";   // (the menu closes after 1.6 s: SpringBoard gives the keys back where they were)
        RunLoop(1.2);
        Expect([gKeysTo isEqualToString:@"com.apple.Preferences"] && gFocusAsked.count == 1, [NSString stringWithFormat:@"Window menu: once the menu closed, the keys asked for Settings (%@, %lu asks)", gKeysTo, (unsigned long)gFocusAsked.count]);
        // ... a menu that leaves the keys with the app while open (its bridge reads them): not moved while the menu is open
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = gKeysTo = @"com.apple.tips";
        Tick(0.25);
        gOverlay = @"menu";
        ipad.items[SET] = W(11); SBFirst(ipad, YES); Tick(0.1);
        DMBarFrontInUseUser(@"ipad", @"a window made active from its display's menu bar");
        RunLoop(1.6);
        Expect(gFocusAsked.count == 0, @"Window menu: the menu's keys left with Tips while it is open: nothing asked meanwhile (Esc still closes it)");
        gOverlay = nil; RunLoop(1.2);
        Expect([gKeysTo isEqualToString:@"com.apple.Preferences"], @"Window menu: ... asked for Settings once it closed");
        // SpringBoard keeping the keys itself all along (Spotlight open over it): never asked
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = @"com.apple.tips"; gKeysTo = @"";
        Tick(0.25);
        DMBarFrontInUseUser(@"ipad", @"a window brought forward");
        RunLoop(2.0);
        Expect(gFocusAsked.count == 0, @"SpringBoard holds the keys itself (Spotlight): they are never asked away from it");

        // ---- the TV unplugged while it is in use ----
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gFrontApp = @"com.apple.Preferences";
        Tick(0.25);
        gTVUp = NO; [gRecent removeObject:tv]; gTVShown = nil; Tick(0.25);
        ExpectActive(SET, @"the TV unplugged while in use: the iPad's front window");
        gTVUp = YES; tv = St(@"tv", @{TIPS: W(9)}); SBFirst(tv, YES); Tick(0.25);
        ExpectActive(TIPS, @"  ... plugged back, a window opened there: that one");

        // ---- the crash guard's piece off: 1.8.8.1's rule ----
        Reset();
        ipad = St(@"ipad", @{SET: W(5)}); tv = St(@"tv", @{TIPS: W(6)});
        gRecent = [@[tv, ipad] mutableCopy]; gIPadShown = ipad; gTVShown = tv; gSkipped = YES;
        DMBarFrontInUseUser(@"ipad", @"a click in a window there");
        Expect([DMSMFrontWindowKeyNow() isEqualToString:Old() ?: @""], @"the piece off (barPerDisplay): 1.8.8.1's answer after a click on the iPad");

        // ---- the iPad alone: 1.8.8.1.1's answer in every state ----
        {
            int same = 1, n = 0, asked0 = gAskedTotal, steps = 0;
            for (int s = 0; s < 5; s++) for (int shown = 0; shown < 3; shown++) for (int read = 0; read < 2; read++) for (int env = 1; env <= 3; env++)
            for (int front = 0; front < 2; front++) for (int touch = 0; touch < 3; touch++) for (int pre = 0; pre < 2; pre++) {
                Reset();
                TStage *a = St(@"ipad", @{SET: W(5), CALC: W(4)}), *b = St(@"ipad", @{CLOCK: W(7)}), *gone = St(@"tv", @{TIPS: W(9)});
                if (pre) {   // (a TV was up and in use until now: its state left from then, and the TV's stage still in SpringBoard's list -- s 4)
                    gRecent = [@[gone, a] mutableCopy]; gTVShown = gone; Tick(0.25);
                    DMBarFrontInUseUser(@"ipad", @"a click in a window there"); DMBarFrontInUseBarAction(TIPS);   // (the iPad in use, held 2 s)
                }
                gTVUp = NO; gTVShown = nil;
                gRecent = s == 0 ? [NSMutableArray array] : s == 1 ? [@[a] mutableCopy] : s == 2 ? [@[a, b] mutableCopy] : s == 3 ? [@[b, a] mutableCopy] : [@[gone, a, b] mutableCopy];
                gGen++; int after0 = gAfterScheduled;   // (from here the iPad alone: what the TV's part scheduled before never runs)
                gIPadShown = shown == 0 ? nil : shown == 1 ? a : b; gIPadRead = read; gIPadEnv = env; gFrontApp = front ? @"com.apple.Preferences" : nil;
                if (touch == 1) DMBarFrontInUseUser(@"ipad", @"a click"); else if (touch == 2) { DMBarFrontInUseBarAction(SET); DMBarFrontInUseFollow(); }
                NSString *now = DMSMFrontWindowKeyNow(), *was = Old();
                n++; steps += gAfterScheduled - after0;
                if (!(now == was || [now isEqualToString:was])) { same = 0; printf("  differs: stages %d shown %d read %d env %d front %d touch %d pre %d: %s / %s\n", s, shown, read, env, front, touch, pre, Name(now).UTF8String, Name(was).UTF8String); }
            }
            Expect(same, [NSString stringWithFormat:@"the iPad alone: 1.8.8.1.1's active window in all %d states (with the new hooks called; also a TV stage left in SpringBoard's list and a TV's state from before it went)", n]);
            Expect(steps == 0 && gAskedTotal == asked0, [NSString stringWithFormat:@"the iPad alone: nothing scheduled, the keys never asked for (%d steps, %d asks)", steps, gAskedTotal - asked0]);
        }
        printf("%s  scenarios: %d of %d\n", fails ? "FAIL" : "PASS", checks - fails, checks);
        return fails ? 1 : 0;
    }
}
