// test-barfront.m -- Mac test of each display's own menu bar (1.8.8.2, B69, KT 21 Nov 2026): what every copy of the bar names, whether it shows the
// traffic lights and which window they act on, and the app its menus are about -- by the REAL code, cut out of statusbar/StatusBar.x by
// tools/test-barfront.sh: the bar layout's decision lines (from dm_layoutLogoBody, whatever the build has there: 1.8.8.1's global answer, or the
// per-display one), the App menu's app line (DMOpenAppMenu), and the helpers they call where the build has them (DMBarFrontToday, DMBarFrontStageHas,
// DMBarFrontOn, DMBarFrontsSig, DMBarFrontOfTitle, DMSMFullScreenKeyIn, DMSMNewestKeyIn), with common/BarFront.h and statusbar/SMWindowKey.h as they are.
// SpringBoard is a world model here: the recent stages (each on its display, its windows with their interaction times and full-screen state), what
// each display's own switcher shows, SpringBoard's front app, our native windows, an engine's windows. The model's DMSMFrontWindowKey, DMActiveApp and
// DMWindowsOwnStatusBar follow StatusBar.x's own rules (DMSMFrontWindowKeyNow, DMActiveApp, DMWindowsOwnStatusBar). Plain Foundation: the UIKit
// types the cut code names are stand-ins. The iPad alone must give 1.8.8's answer in every state: 1.8.8's decision lines are kept verbatim below
// (Decide188) and compared over a sweep of states.
#import <Foundation/Foundation.h>
#include "../common/BarFront.h"
#include "../statusbar/SMWindowKey.h"

@interface UIView : NSObject
@end
@implementation UIView
@end
@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
@end
static UIScreen *gMain, *gTVScreen;
@implementation UIScreen
+ (UIScreen *)mainScreen { return gMain; }
@end
@interface UIButton : UIView
@end
@implementation UIButton
@end
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bid;
- (NSString *)bundleIdentifier;
- (NSString *)displayName;
@end
@implementation SBApplication
- (NSString *)bundleIdentifier { return self.bid; }
- (NSString *)displayName { return [[self.bid componentsSeparatedByString:@"."] lastObject]; }
@end
@interface DMNativeWindow : NSObject
@end
@implementation DMNativeWindow
@end
@interface DMLights : NSObject
@property (nonatomic, copy) NSString *barKey;
@end
@implementation DMLights
@end
// a stage: its display and its windows (window key -> @{@"t": interaction time, @"f": full screen})
@interface TStage : NSObject
@property (nonatomic, copy) NSString *ident;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *items;
@end
@implementation TStage
@end
#define DM_FEATURE_MARK(name) do { } while (0)
static void DMLog(NSString *s) { (void)s; }

// ---- the world ----
static BOOL gSM = YES, gTVUp = NO, gSkipped = NO, gLocked = NO, gShowWindowButtons = YES, gNativeOn = NO, gEngineWindows = NO;
static NSString *gEngineApp = nil;        // (the other engines: the app of their top window, on the iPad)
static NSString *gFrontApp = nil;         // (SpringBoard's -_accessibilityFrontMostApplication: any display's)
static NSMutableArray<TStage *> *gRecent; // (the recent stages, most recent first)
static BOOL gIPadRead = YES, gTVRead = YES; static long long gIPadEnv = 3, gTVEnv = 3; static TStage *gIPadShown, *gTVShown;
static TStage *gTVDrawn;                  // (the TV's stage whose windows are drawn on the TV: DMSMStageShownOnDisplay)
static UIView *gIPadCopy, *gTVCopy; static UIButton *gIPadTitle, *gTVTitle;
static DMNativeWindow *gNative;
static NSMutableDictionary<NSString *, SBApplication *> *gApps;

static TStage *St(NSString *ident, NSDictionary *items) { TStage *s = [TStage new]; s.ident = ident; s.items = [items mutableCopy]; return s; }
static NSDictionary *W(long t) { return @{@"t": @(t), @"f": @NO}; }
static NSDictionary *F(long t) { return @{@"t": @(t), @"f": @YES}; }
static SBApplication *DMAppForBundle(NSString *b) {
    if (!b.length) return nil;
    SBApplication *a = gApps[b];
    if (!a) { a = [SBApplication new]; a.bid = b; gApps[b] = a; }
    return a;
}
// SpringBoard's model, read as StatusBar.x reads it
static NSArray *DMSMRecentStages(void) { return gRecent; }
static id DMSMStageDisplayIdentity(id stage) { return ((TStage *)stage).ident; }
static BOOL DMSMIsMainIdentity(id identity) { return !identity || [identity isEqual:@"ipad"]; }
static id DMSMIdentityOfScreen(UIScreen *s) { return s == gMain ? @"ipad" : (s == gTVScreen ? @"tv" : nil); }
static NSDictionary *DMSMStageItemsMap(id stage) { return ((TStage *)stage).items; }
static NSString *DMSMItemKey(id item) { return item; }
static NSString *DMSMItemBundle(id item) { return DMSMKeyBundle(item); }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { NSNumber *t = ((NSDictionary *)attrs)[@"t"]; return t ? t.longLongValue : dflt; }
static BOOL DMSMAttrsFullScreen(id attrs) { return [((NSDictionary *)attrs)[@"f"] boolValue]; }
static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {
    NSDictionary *m = DMSMStageItemsMap(stage);
    if (m[key]) { if (attrsOut) *attrsOut = m[key]; return key; }
    if (DMSMKeyIsApp(key)) for (NSString *k in m) if ([DMSMKeyBundle(k) isEqualToString:key]) { if (attrsOut) *attrsOut = m[k]; return k; }
    return nil;
}
static NSString *Newest(TStage *s) { NSString *b = nil; long long n = LLONG_MIN; for (NSString *k in s.items) { long long t = DMSMAttrTimeOr(s.items[k], 0); if (t > n) { n = t; b = k; } } return b; }
static id DMSMShownMainStage(void) { return gIPadRead && gIPadEnv == 3 ? gIPadShown : nil; }
static id DMSMFrontStageOnDisplay(id identity) {
    if (DMSMIsMainIdentity(identity)) { id shown = DMSMShownMainStage(); if (shown) return shown; }
    for (TStage *s in gRecent) if (DMSMIsMainIdentity(identity) ? DMSMIsMainIdentity(s.ident) : [s.ident isEqual:identity]) return s;
    return nil;
}
static id DMSMFrontStage(void) { return DMSMFrontStageOnDisplay(@"ipad") ?: gRecent.firstObject; }
static BOOL DMSMStageShownOnDisplay(id al, id identity) { return al && al == gTVDrawn && [identity isEqual:@"tv"]; }
static id DMSMIPadStageShown(void) { return gIPadRead ? DMSMShownMainStage() : (gFrontApp ? DMSMFrontStage() : nil); }
static id DMSMStageOf(NSString *key) { for (TStage *s in gRecent) if (DMSMItemFor(s, key, nil)) return s; return DMSMFrontStage(); }
static SBApplication *DMFrontApp(void) { return DMAppForBundle(gFrontApp); }
static BOOL DMSMEngine(void) { return gSM; }
// DMSMFrontWindowKeyNow's rule: the most recent stage on any display (the iPad's shown stage when that one is the iPad's); none at the iPad's Home
// Screen with no front app
static NSString *DMSMFrontWindowKey(void) {
    TStage *stage = gRecent.firstObject;
    if (!stage || DMSMIsMainIdentity(stage.ident)) { id shown = DMSMShownMainStage(); if (shown) stage = shown; }
    if (DMSMIsMainIdentity(stage.ident) && !DMFrontApp()) return nil;
    return stage ? Newest(stage) : nil;
}
// The display in use (1.8.8.2, B81: StatusBar.x's DMBarFrontInUseIdentity, a state of its own -- tools/test-displayinuse.sh): here the model's rule
// above, the most recent stage's display, as DMSMFrontWindowKey has it
static id DMBarFrontInUseIdentity(void) { TStage *f = gRecent.firstObject; return f ? f.ident : nil; }
static NSString *FullIn(TStage *s) { for (NSString *k in s.items) if (DMSMAttrsFullScreen(s.items[k])) return k; return nil; }
static BOOL DMWindowsOwnStatusBar(void) {
    if (gSM) { NSString *f = DMSMFrontWindowKey(), *full = FullIn(DMSMFrontStage()); return DMSMKeyBundle(f).length > 0 && !(f.length && [f isEqualToString:full]); }
    return gEngineWindows;
}
static SBApplication *DMActiveApp(void) {
    if (gSM) { NSString *b = DMSMKeyBundle(DMSMFrontWindowKey()); SBApplication *a = b.length ? DMAppForBundle(b) : nil; return a ?: DMFrontApp(); }
    if (gEngineWindows) return DMAppForBundle(gEngineApp);
    return DMFrontApp();
}
static DMNativeWindow *DMNativeActiveApp(void) { return gNativeOn ? gNative : nil; }
static NSString *DMNativeActiveAppName(void) { return gNativeOn ? @"TextEdit" : nil; }
static UIView *DMA5ComingBackTop(void) { return nil; }
static UIScreen *DMExternalScreenOf(UIView *v) { return gTVUp && (v == gTVCopy || v == gTVTitle) ? gTVScreen : nil; }
static UIScreen *DMBarFrontTV(void) { return gTVUp ? gTVScreen : nil; }   // (StatusBar.x: a copy of ours on another display)
static BOOL DMBarFrontSkipped(void) { return gSkipped; }
static BOOL DMBarFrontSwitcherOn(UIScreen *screen, long long *env, id *stage) {
    if (screen == gMain) { *env = gIPadRead ? gIPadEnv : 0; *stage = gIPadRead ? gIPadShown : nil; return gIPadRead; }
    *env = gTVRead ? gTVEnv : 0; *stage = gTVRead ? gTVShown : nil; return gTVRead;
}

// ---- the real code ----
#if HAS_FULLKEYIN
#include "fullkeyin.inc"
#endif
#include "newestkeyin.inc"
#if HAS_BARFRONT
#include "barfront.inc"
#endif
// The decision of a copy, as the layout has it: its name, whether it shows the lights, the key they act on (nil: the active window's)
static void Decide(UIView *fg, NSString **name, BOOL *lightsOut, NSString **lightsKey) {
    BOOL locked = gLocked;
#include "decide.inc"
#include "wantlights.inc"
    *name = appName; *lightsOut = wantLights; *lightsKey = nil;
#if HAS_BARKEY
    if (wantLights) {
        DMLights *lights = [DMLights new];
#include "barkey.inc"
        *lightsKey = lights.barKey;
    }
#endif
}
// The app the App menu of a title is about
static SBApplication *MenuApp(UIButton *btn) {
#include "appmenu.inc"
    return app;
}
// 1.8.8's decision lines, verbatim (statusbar/StatusBar.x at 1.8.8 and 1.8.8.1): the answer every copy took
static void Decide188(UIView *fg, NSString **name, BOOL *lightsOut) {
    (void)fg;
    BOOL locked = gLocked;
    SBApplication *frontApp = DMNativeActiveApp() ? nil : DMActiveApp();   // whichever app is frontmost, windowed or full screen (a native window: none)
    BOOL activeIsWindow = DMWindowsOwnStatusBar() || (frontApp && !DMFrontApp() && DMA5ComingBackTop());   // (a window on its way back after the unlock: still a window -- no lights in the bar)
    NSString *appName = frontApp ? ([frontApp displayName] ?: [frontApp bundleIdentifier]) : (DMNativeActiveAppName() ?: @"Finder");
    BOOL wantLights = gShowWindowButtons && frontApp != nil && !activeIsWindow && !locked;   // a window has its own buttons
    *name = appName; *lightsOut = wantLights;
}

static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static void Reset(void) {
    gSM = YES; gTVUp = YES; gSkipped = NO; gLocked = NO; gShowWindowButtons = YES; gNativeOn = NO; gEngineWindows = NO; gEngineApp = nil; gFrontApp = nil;
    gRecent = [NSMutableArray array]; gIPadRead = gTVRead = YES; gIPadEnv = gTVEnv = 3; gIPadShown = gTVShown = gTVDrawn = nil;
}
// one copy's answer: "Name" or "Name+L" (lights; "+L:<key>" when they act on a window of their own), the App menu's app as "menu Name"
static NSString *Bar(UIView *fg) {
    NSString *n = nil, *k = nil; BOOL l = NO;
    Decide(fg, &n, &l, &k);
    return l ? (k ? [NSString stringWithFormat:@"%@+L:%@", n, k] : [n stringByAppendingString:@"+L"]) : n;
}
static NSString *Bar188(void) { NSString *n = nil; BOOL l = NO; Decide188(nil, &n, &l); return l ? [n stringByAppendingString:@"+L"] : n; }
static NSString *Menu(UIButton *b) { SBApplication *a = MenuApp(b); return a ? [a displayName] : @"Finder"; }
static void ExpectBars(NSString *ipad, NSString *tv, NSString *what) {
    NSString *gi = Bar(gIPadCopy), *gt = Bar(gTVCopy);
    Expect([gi isEqualToString:ipad] && [gt isEqualToString:tv], [NSString stringWithFormat:@"%@ -- iPad bar %@, TV bar %@ (want %@ / %@)", what, gi, gt, ipad, tv]);
}

#define SET @"com.apple.Preferences|sceneID:com.apple.Preferences-default"
#define TIPS @"com.apple.tips|sceneID:com.apple.tips-default"
#define CLOCK @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default"
#define NOTES_A @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-a"
#define NOTES_B @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-b"

int main(void) {
    @autoreleasepool {
        gMain = [UIScreen new]; gTVScreen = [UIScreen new]; gApps = [NSMutableDictionary dictionary]; gNative = [DMNativeWindow new];
        gIPadCopy = [UIView new]; gTVCopy = [UIView new]; gIPadTitle = [UIButton new]; gTVTitle = [UIButton new];

        // ---- the iPad alone: 1.8.8's answer in every state (a sweep over the engine, what the iPad shows, its front app, our own window, an engine's
        //      windows, locked, Show Window Buttons, the crash piece) -- the name, the lights, the App menu's app
        {
            int n = 0, same = 0; NSString *firstDiff = nil;
            for (int sm = 0; sm < 2; sm++) for (int shown = 0; shown < 4; shown++) for (int front = 0; front < 3; front++) for (int nat = 0; nat < 2; nat++)
            for (int eng = 0; eng < 2; eng++) for (int lk = 0; lk < 2; lk++) for (int swb = 0; swb < 2; swb++) for (int rd = 0; rd < 2; rd++) for (int sk = 0; sk < 2; sk++) {
                Reset(); gTVUp = NO; gSM = sm; gNativeOn = nat; gEngineWindows = !sm && eng; gEngineApp = @"com.apple.mobilenotes"; gLocked = lk; gShowWindowButtons = swb;
                gIPadRead = rd; gSkipped = sk;
                TStage *a = St(@"ipad", @{SET: W(5)}), *b = St(@"ipad", @{CLOCK: F(7)}), *c = St(@"ipad", @{SET: W(9), CLOCK: F(4)});
                gRecent = shown == 0 ? [NSMutableArray arrayWithObjects:a, b, nil] : shown == 1 ? [NSMutableArray arrayWithObjects:b, a, nil] : shown == 2 ? [NSMutableArray arrayWithObjects:c, nil] : [NSMutableArray array];
                gIPadShown = shown == 3 ? nil : gRecent.firstObject; gIPadEnv = shown == 3 ? 1 : (front == 2 ? 1 : 3);   // (front 2: at its Home Screen, the stage behind)
                gFrontApp = front == 0 ? nil : (front == 1 ? DMSMKeyBundle(Newest(gRecent.firstObject)) ?: @"com.apple.Preferences" : @"com.apple.tips");
                NSString *now = Bar(gIPadCopy), *was = Bar188(), *m = Menu(gIPadTitle);
                SBApplication *m188 = DMNativeActiveApp() ? nil : DMActiveApp();
                NSString *wasMenu = m188 ? [m188 displayName] : @"Finder";
                n++;
                if ([now isEqualToString:was] && [m isEqualToString:wasMenu]) same++;
                else if (!firstDiff) firstDiff = [NSString stringWithFormat:@"sm %d shown %d front %d native %d engine %d locked %d buttons %d read %d piece-off %d: %@ / menu %@, 1.8.8 %@ / menu %@", sm, shown, front, nat, eng, lk, swb, rd, sk, now, m, was, wasMenu];
            }
            Expect(same == n, [NSString stringWithFormat:@"the iPad alone: 1.8.8's name, lights and App menu app in all %d states (%d the same)%@", n, same, firstDiff ? [@"; first difference: " stringByAppendingString:firstDiff] : @""]);
#if HAS_BARFRONT
            Reset(); gTVUp = NO; gRecent = [NSMutableArray arrayWithObjects:St(@"ipad", @{SET: W(5)}), nil]; gIPadShown = gRecent.firstObject; gFrontApp = @"com.apple.Preferences";
            Expect([DMBarFrontsSig() isEqualToString:@""], @"the iPad alone: the tick's bars signature is empty (nothing more laid out than before)");
#else
            Expect(NO, @"the iPad alone: the tick's bars signature is empty (no per-display answer in this build)");
#endif
        }

        // ---- two displays, the Stage Manager engine
        TStage *tvOld = St(@"tv", @{TIPS: W(3)});
        // KT's case (21 Nov, A12Z with the TV): an app opened on the iPad as a window, the TV at its empty desktop (its old stage kept for its desktop)
        Reset(); TStage *ip = St(@"ipad", @{SET: W(10)}); gRecent = [NSMutableArray arrayWithObjects:ip, tvOld, nil]; gIPadShown = ip; gFrontApp = @"com.apple.Preferences";
        gTVEnv = 1; gTVShown = nil;
        ExpectBars(@"Preferences", @"Finder", @"KT's case: Settings opened on the iPad as a window, the TV at its empty desktop: the TV's bar says Finder, no lights");
        // ... green on Settings: full screen on the iPad
        ip.items[SET] = F(11);
        ExpectBars(@"Preferences+L", @"Finder", @"  ... Settings full screen on the iPad: its lights on the iPad's bar only (the TV's: Finder, no lights)");
        // ... the opening moment: SpringBoard names the app before its stage is in the model -- 1.8.8 drew its lights on every bar
        Reset(); gRecent = [NSMutableArray arrayWithObjects:tvOld, nil]; gIPadShown = nil; gIPadEnv = 3; gFrontApp = @"com.apple.mobiletimer"; gTVEnv = 1;
        gRecent = [NSMutableArray array];
        ExpectBars(@"mobiletimer+L", @"Finder", @"  ... Clock opening, its stage not in the model yet: the TV's bar neither names it nor draws its lights (the iPad's as 1.8.8)");
        // a window on the TV, the iPad in use
        Reset(); ip = St(@"ipad", @{SET: W(10)}); TStage *tv = St(@"tv", @{TIPS: W(8)}); gRecent = [NSMutableArray arrayWithObjects:ip, tv, nil]; gIPadShown = ip; gTVShown = tv; gFrontApp = @"com.apple.Preferences";
        ExpectBars(@"Preferences", @"tips", @"Tips as a window on the TV, Settings in use on the iPad: each bar its own display's app, no lights");
        Expect([Menu(gTVTitle) isEqualToString:@"tips"] && [Menu(gIPadTitle) isEqualToString:@"Preferences"], [NSString stringWithFormat:@"  ... each bar's App menu is about its own app (TV %@, iPad %@)", Menu(gTVTitle), Menu(gIPadTitle)]);
#if HAS_BARFRONT
        { NSString *k = nil; BOOL other = NO; SBApplication *a = DMBarFrontOfTitle(gTVTitle, &k, &other);
          Expect(other && [k isEqualToString:TIPS] && [[a bundleIdentifier] isEqualToString:@"com.apple.tips"], @"  ... the TV's bar is not the one in use: its window (Tips) is the one its key presses and Window menu make active first");
          k = nil; other = YES; (void)DMBarFrontOfTitle(gIPadTitle, &k, &other);
          Expect(!other && !k, @"  ... the iPad's bar is the one in use: its menus act as before"); }
#else
        Expect(NO, @"  ... the TV's bar is not the one in use: its window is made active first (no per-display answer in this build)");
        Expect(NO, @"  ... the iPad's bar is the one in use (no per-display answer in this build)");
#endif
        // Tips clicked: the TV in use
        tv.items[TIPS] = W(12); [gRecent exchangeObjectAtIndex:0 withObjectAtIndex:1]; gFrontApp = @"com.apple.tips";
        ExpectBars(@"Preferences", @"tips", @"Tips clicked (the TV in use): the iPad's bar keeps its own Settings, the TV's says Tips");
        // Tips full screen on the TV, the iPad in use
        Reset(); ip = St(@"ipad", @{SET: W(10)}); tv = St(@"tv", @{TIPS: F(8)}); gRecent = [NSMutableArray arrayWithObjects:ip, tv, nil]; gIPadShown = ip; gTVShown = tv; gFrontApp = @"com.apple.Preferences";
        ExpectBars(@"Preferences", @"tips+L:" TIPS, @"Tips full screen on the TV, Settings in use: the lights on the TV's bar, acting on Tips' own window (1.8.8: on no bar, audit row 9)");
        // both full screen
        ip.items[SET] = F(11);
        ExpectBars(@"Preferences+L", @"tips+L:" TIPS, @"both full screen, the iPad in use: each bar its own lights -- the iPad's the active window's, the TV's on Tips");
        tv.items[TIPS] = F(13); [gRecent exchangeObjectAtIndex:0 withObjectAtIndex:1]; gFrontApp = @"com.apple.tips";
        ExpectBars(@"Preferences+L:" SET, @"tips+L:" TIPS, @"both full screen, the TV in use: each bar its own lights, each on its own window");
        // an app with windows on both displays
        Reset(); ip = St(@"ipad", @{NOTES_A: W(10)}); tv = St(@"tv", @{NOTES_B: F(6)}); gRecent = [NSMutableArray arrayWithObjects:ip, tv, nil]; gIPadShown = ip; gTVShown = tv; gFrontApp = @"com.apple.mobilenotes";
        ExpectBars(@"mobilenotes", @"mobilenotes+L:" NOTES_B, @"Notes with a window on each display: both bars Notes, the lights on the TV's bar only, on the TV's window");
        // the iPad at its Home Screen while the TV shows an app (SpringBoard's front app is the TV's)
        Reset(); ip = St(@"ipad", @{SET: W(10)}); tv = St(@"tv", @{TIPS: W(8)}); gRecent = [NSMutableArray arrayWithObjects:ip, tv, nil]; gIPadShown = nil; gIPadEnv = 1; gTVShown = tv; gFrontApp = @"com.apple.tips";
        ExpectBars(@"Finder", @"tips", @"the iPad at its Home Screen, Tips on the TV: the iPad's bar says Finder (not the stage it left), the TV's Tips");
        // the TV's App Switcher / empty desktop while the TV is in use
        Reset(); tv = St(@"tv", @{TIPS: W(8)}); ip = St(@"ipad", @{SET: W(5)}); gRecent = [NSMutableArray arrayWithObjects:tv, ip, nil]; gIPadShown = ip; gTVShown = nil; gTVEnv = 1; gFrontApp = @"com.apple.tips";
        ExpectBars(@"Preferences", @"Finder", @"the TV's last window sent to its empty desktop (its stage kept): the TV's bar says Finder, the iPad's its own Settings");
        // the TV's switcher can't be read
        Reset(); ip = St(@"ipad", @{SET: W(10)}); tv = St(@"tv", @{TIPS: W(8)}); gRecent = [NSMutableArray arrayWithObjects:ip, tv, nil]; gIPadShown = ip; gFrontApp = @"com.apple.Preferences";
        gTVRead = NO; gTVDrawn = tv;
        ExpectBars(@"Preferences", @"tips", @"the TV's switcher not readable: its most recent stage still drawn there (Tips)");
        gTVDrawn = nil;
        ExpectBars(@"Preferences", @"Finder", @"  ... none drawn there (after a respring the old stage is only on record): Finder");
        // locked
        Reset(); ip = St(@"ipad", @{SET: F(10)}); tv = St(@"tv", @{TIPS: F(8)}); gRecent = [NSMutableArray arrayWithObjects:ip, tv, nil]; gIPadShown = ip; gTVShown = tv; gFrontApp = @"com.apple.Preferences"; gLocked = YES;
        ExpectBars(@"Preferences", @"tips", @"locked: no lights on either bar (the titles hide by the locked layout, as before)");
        // the crash guard's piece off: 1.8.8's one answer on every bar
        gLocked = NO; gSkipped = YES;
        ExpectBars(@"Preferences+L", @"Preferences+L", @"the crash guard's piece off: every bar 1.8.8's one answer (as before 1.8.8.2)");
        // the TV unplugged: the iPad's bar as 1.8.8
        gSkipped = NO; gTVUp = NO;
        Expect([Bar(gIPadCopy) isEqualToString:Bar188()], @"the TV unplugged: the iPad's bar 1.8.8's answer again");
#if HAS_BARFRONT
        // the tick: a change on the TV alone (Tips closed there) changes the bars' signature with the same active app
        Reset(); ip = St(@"ipad", @{SET: W(10)}); tv = St(@"tv", @{TIPS: W(8)}); gRecent = [NSMutableArray arrayWithObjects:ip, tv, nil]; gIPadShown = ip; gTVShown = tv; gFrontApp = @"com.apple.Preferences";
        NSString *s1 = DMBarFrontsSig(), *a1 = [DMActiveApp() bundleIdentifier];
        [gRecent removeObject:tv]; gTVShown = nil; gTVEnv = 1;
        NSString *s2 = DMBarFrontsSig(), *a2 = [DMActiveApp() bundleIdentifier];
        Expect([a1 isEqualToString:a2] && s1.length && ![s1 isEqualToString:s2], @"the tick: Tips closed on the TV, the same active app: the bars' signature changes (the TV's bar is laid out again)");
#else
        Expect(NO, @"the tick: a change on the TV alone lays the bars out (no per-display answer in this build)");
#endif

        // ---- two displays, the other engines (16 with TrollPad's external display: their windows are views on the iPad)
        Reset(); gSM = NO; gEngineWindows = YES; gEngineApp = @"com.apple.mobilenotes"; tv = St(@"tv", @{TIPS: F(8)}); gRecent = [NSMutableArray arrayWithObjects:tv, nil]; gTVShown = tv;
        gIPadShown = nil; gIPadEnv = 1; gFrontApp = @"com.apple.tips";
        ExpectBars(@"mobilenotes", @"tips", @"Zetsu: a window of it in front on the iPad, Tips on the TV: the iPad's bar the window's app, the TV's Tips, no lights there");
        gEngineWindows = NO; ip = St(@"ipad", @{SET: F(5)}); [gRecent addObject:ip]; gIPadShown = ip; gIPadEnv = 3;
        ExpectBars(@"Preferences", @"tips", @"  ... SpringBoard's front app Tips, the TV's (no window in front): the iPad's bar its own Settings, no lights on either (they would act on Tips)");
        gFrontApp = @"com.apple.Preferences";
        ExpectBars(@"Preferences+L", @"tips", @"  ... Settings the front app: the iPad's bar with its lights, as 1.8.8; the TV's Tips without");
    }
    printf("%s  %d of %d checks\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
