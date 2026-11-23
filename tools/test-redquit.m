// test-redquit.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the red light with the Stage Manager engine (1.8.7.6, REDDOT; KT 15 Nov, A12Z
// 18.5: "the red traffic light sometimes leaves a dot under the app, giving it the impression its still running. In contrast regular force quit
// clears it immediately, and on the m1 the red button also works immediately").
// The red light quits the app on every engine (Aerial, Zetsu, MilkyWay4: DMForceQuitBundle) and Force Quit ends it at once; with the Stage Manager
// engine it ran the window's own Close only, and SpringBoard ended the app when no stage held it any more: an app with a window minimized, on
// another desktop or in a stage not shown ran on with its Dock dot (the A12Z's c11: Files with a minimized window, its dot at 1, 5 and 15 s), and
// one that ended, ended 0.8-1.25 s after the press. Now: the app's last window on screen -> the app quits the Force Quit way; with another window of
// it on screen only that window closes (1.3.6 H-1, M-2), as before.
// Runs the real DMSMRedLight (when the tree has it), DMLightAction, -[DMSMTitleBar dm_light:], DMForceQuitBundle, DMForceQuit,
// DMSMForceQuitWindows and DMSMItemFor (statusbar/StatusBar.x), cut out by test-redquit.sh into rq-real.inc, with the real statusbar/SMWindowKey.h
// and the Dock's dot rule (dock/RunningDotRule.h). SpringBoard's side is the stand-ins below: the stages (most recent first), the stage the iPad
// shows, the TV's, a window's own Close (only on a stage on screen), SpringBoard's own end of an app once no stage holds it (1.25 s later, as the
// A12Z's c3/c5), its switcher clean-up (deletes the app's stages and ends it), the terminate request (ends it), the processes and their pids.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../statusbar/SMWindowKey.h"
#include "../dock/RunningDotRule.h"

// ---- what the real code logs and marks
static NSMutableArray<NSString *> *gRQLog, *gRQMarks;
static void RQLog(NSString *s) { [gRQLog addObject:s ?: @""]; }
#define DMLog(...) RQLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name) [gRQMarks addObject:@name]

// ---- SpringBoard's side
@interface RQItem : NSObject <NSCopying>   // (a window: SBDisplayItem -- its app, its scene)
@property (nonatomic, copy) NSString *key;
@end
@implementation RQItem
- (id)copyWithZone:(NSZone *)z { return self; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[RQItem class]] && [((RQItem *)o).key isEqualToString:self.key]; }
- (NSUInteger)hash { return self.key.hash; }
- (NSString *)bundleIdentifier { return DMSMKeyBundle(self.key); }
- (NSString *)description { return self.key; }
@end
@interface RQStage : NSObject   // (a stage: SBAppLayout)
@property (nonatomic, strong) NSMutableDictionary *items;   // RQItem -> @{@"t": last interaction}
@property (nonatomic, copy) NSString *identity;   // nil: the iPad's; @"tv": the TV's
@property (nonatomic, assign) BOOL onTV;   // a TV stage whose windows are on the TV now
@end
@implementation RQStage
- (NSDictionary *)itemsToLayoutAttributesMap { return [self.items copy]; }
- (NSArray *)allItems { return [self.items allKeys]; }
@end
static NSMutableArray<RQStage *> *gRQStages;   // the switcher's recent stages, most recent first
static RQStage *gRQShown;   // the stage the iPad shows (nil: the Home Screen, or not readable)
static NSMutableDictionary<NSString *, NSNumber *> *gRQRunning, *gRQSeen;   // bundle -> pid running; bundle -> pid seen on screen
static NSMutableArray<NSDictionary *> *gRQEnded;   // @{@"b", @"why", @"at"}
static NSMutableArray<NSString *> *gRQClosed, *gRQTerminated, *gRQDeleted, *gRQPrewarm, *gRQTakenOut, *gRQForgot, *gRQMSWForgot, *gRQOther, *gRQAerialClosed;
static NSMutableSet<NSString *> *gRQMinimized;   // the minimized marks (window keys)
static NSMutableDictionary<NSString *, NSNumber *> *gRQDesk;   // the Mac Switcher's desktop records (window key -> desktop)
static CFTimeInterval gRQT0;
static BOOL gRQSM, gRQPerWindow;
static int gRQGen;   // (a scenario's own: SpringBoard's late end of an app never reaches the next scenario)
static BOOL gRQWholeLayout;   // (SpringBoard's clean-up deletes each layout holding the app whole and quits every app in it: iPadOS's own stages, Split View)
static NSString *gRQFrontBundle, *gRQFrontKey;

static BOOL RQShown(RQStage *s) { return s && (s == gRQShown || (s.identity && s.onTV)); }
static BOOL RQHeld(NSString *b) { for (RQStage *s in gRQStages) for (RQItem *it in s.items) if ([it.bundleIdentifier isEqualToString:b]) return YES; return NO; }
static BOOL RQOnScreen(NSString *b) { for (RQStage *s in gRQStages) if (RQShown(s)) for (RQItem *it in s.items) if ([it.bundleIdentifier isEqualToString:b]) return YES; return NO; }
static void RQEnd(NSString *b, NSString *why) {
    if (!gRQRunning[b]) return;
    [gRQRunning removeObjectForKey:b];
    [gRQEnded addObject:@{@"b": b, @"why": why, @"at": @(CACurrentMediaTime() - gRQT0)}];
}
static void RQDropEmpty(void) {
    for (RQStage *s in [gRQStages copy]) if (!s.items.count) { [gRQStages removeObjectIdenticalTo:s]; if (s == gRQShown) gRQShown = nil; }
}
static void RQSpringBoardAfterRemoval(NSString *b) {   // (SpringBoard ends an app once no stage holds it: about 1.25 s after the window's Close)
    if (RQHeld(b)) return;
    int gen = gRQGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gen == gRQGen && !RQHeld(b)) RQEnd(b, @"SpringBoard: no stage holds it"); });
}
void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reasonID, bool report, NSString *description) {
    [gRQTerminated addObject:[NSString stringWithFormat:@"%@ (reason %d)", bundleID ?: @"(nil)", reasonID]];
    RQEnd(bundleID, @"our terminate request");
}
@interface RQSwitcher : NSObject
- (void)_deleteAppLayoutsMatchingBundleIdentifier:(NSString *)bundleID;
@end
@implementation RQSwitcher
- (void)_deleteAppLayoutsMatchingBundleIdentifier:(NSString *)bundleID {   // (every stage holding a window of the app goes, and the app ends)
    [gRQDeleted addObject:bundleID ?: @"(nil)"];
    if (gRQWholeLayout) for (RQStage *s in [gRQStages copy]) {
        BOOL has = NO; for (RQItem *it in s.items) if ([it.bundleIdentifier isEqualToString:bundleID]) has = YES;
        if (!has) continue;
        for (RQItem *it in [s.items allKeys]) RQEnd(it.bundleIdentifier, @"SpringBoard: its layout deleted");
        [s.items removeAllObjects];
    }
    for (RQStage *s in [gRQStages copy]) for (RQItem *it in [s.items allKeys]) if ([it.bundleIdentifier isEqualToString:bundleID]) [s.items removeObjectForKey:it];
    RQDropEmpty();
    RQEnd(bundleID, @"SpringBoard's switcher clean-up");
}
@end
@interface SBMainSwitcherControllerCoordinator : NSObject
+ (instancetype)sharedInstance;
- (NSArray *)recentAppLayouts;
@end
@implementation SBMainSwitcherControllerCoordinator
+ (instancetype)sharedInstance { static SBMainSwitcherControllerCoordinator *s; if (!s) s = [self new]; return s; }
- (NSArray *)recentAppLayouts { return [gRQStages copy]; }
@end
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
static RQSwitcher *gRQSwitcher;
static id DMSwitcherController(void) { return gRQSwitcher; }
static id DMCall(id obj, NSString *name) {   // (StatusBar.x's)
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;   // (StatusBar.x's)
static DMEngine gRQEngine;
static DMEngine DMActiveEngine(void) { return gRQEngine; }
static BOOL DMSMEngine(void) { return gRQSM; }
static BOOL DMGARefuses(NSString *what) { return NO; }
static BOOL DMWaitForContextMenu(NSString *key, dispatch_block_t again) { return NO; }
static BOOL DMSMStripHoldsBack(NSString *what, dispatch_block_t act) { return NO; }
static void DMPrewarmQuitAdd(NSString *bundleID) { [gRQPrewarm addObject:bundleID ?: @"(nil)"]; }
static BOOL DMSMAfterTVEmptyHolds(NSString *bundle, dispatch_block_t block) { return NO; }   // (1.8.8.2, B86: nothing waits for a TV's empty desktop here)
static NSString *gRQAerialBundle; static UIView *gRQAerialStage;
static UIView *DMStageForBundle(NSString *bundleID) { return gRQAerialBundle && [bundleID isEqualToString:gRQAerialBundle] ? gRQAerialStage : nil; }
static BOOL DMMSWBundleAway(NSString *b) { return NO; }
static NSArray<UIWindow *> *DMZetsuAllWindows(void) { return @[]; }
static NSString *DMZetsuWindowBundle(UIWindow *w) { return nil; }
static void DMZetsuClose(UIWindow *w) {}
static NSArray<UIView *> *DMAerialStagesAll(void) { return @[]; }
static NSString *DMStageBundle(UIView *stage) { return nil; }
@interface AXWindowView : UIView
- (void)closeButtonAction:(id)sender;
@end
@implementation AXWindowView
- (void)closeButtonAction:(id)sender {}
@end
static double DMAerialCloseForQuit(NSString *bundleID) { [gRQAerialClosed addObject:bundleID ?: @"(nil)"]; return 0.2; }
static void DMMSWForgetApp(NSString *b) {   // (the Mac Switcher's records of the app's windows, every desktop's)
    [gRQMSWForgot addObject:b ?: @"(nil)"];
    for (NSString *k in [gRQDesk allKeys]) if ([DMSMKeyBundle(k) isEqualToString:b]) [gRQDesk removeObjectForKey:k];
}
static NSMutableDictionary<NSString *, NSNumber *> *gAppQuitAt;   // (StatusBar.x's, just above DMForceQuitBundle)
// (the stages, as SMEngineAPI.h reads them)
static NSArray *DMSMRecentStages(void) { return [gRQStages copy]; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[RQStage class]] ? [((RQStage *)stage).items copy] : nil; }
static NSString *DMSMItemBundle(id item) { return [item isKindOfClass:[RQItem class]] ? [item bundleIdentifier] : nil; }
static NSString *DMSMItemKey(id item) { return [item isKindOfClass:[RQItem class]] ? (gRQPerWindow ? ((RQItem *)item).key : DMSMKeyBundle(((RQItem *)item).key)) : nil; }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { NSNumber *t = attrs[@"t"]; return t ? t.longLongValue : dflt; }
static id DMSMStageDisplayIdentity(id stage) { return ((RQStage *)stage).identity; }
static BOOL DMSMIsMainIdentity(id identity) { return !identity; }
static BOOL DMSMStageShownOnDisplay(id al, id identity) { return [al isKindOfClass:[RQStage class]] && [((RQStage *)al).identity isEqual:identity] && ((RQStage *)al).onTV; }
static id DMSMIPadStageShown(void) { return gRQShown; }
static NSString *DMSMFrontWindowKey(void) { return gRQFrontKey; }
static int DMSMTakeOutOfHiddenStages(NSString *bundle) {   // (its windows out of every iPad stage not on screen that keeps other windows)
    int n = 0;
    for (RQStage *s in gRQStages) {
        if (s.identity || s == gRQShown || s.items.count < 2) continue;
        BOOL took = NO;
        for (RQItem *it in [s.items allKeys]) if ([it.bundleIdentifier isEqualToString:bundle] && s.items.count >= 2) { [s.items removeObjectForKey:it]; [gRQTakenOut addObject:it.key]; took = YES; }
        if (took) n++;
    }
    return n;
}
static void DMSMForgetApp(NSString *bundle) { [gRQForgot addObject:bundle ?: @"(nil)"]; DMSMKeySetRemove(gRQMinimized, DMSMKeyBundle(bundle)); }
// A window's own Close (DMSMWindowAction "close"): the window the key names in the most recent stage holding it (DMSMStageOf); it works only on a
// stage on screen ("not available" otherwise), takes the window out of its stage, and SpringBoard ends the app if no stage holds it any more.
static id DMSMItemFor(id stage, NSString *key, id *attrsOut);
static BOOL DMSMWindowAction(NSString *key, NSString *name) {
    RQStage *st = nil; RQItem *it = nil;
    for (RQStage *s in gRQStages) { it = DMSMItemFor(s, key, nil); if (it) { st = s; break; } }
    if ([name isEqualToString:@"removeFromSet"]) { [gRQOther addObject:[@"minimize " stringByAppendingString:key ?: @"?"]]; return it != nil; }
    if (![name isEqualToString:@"close"] || !it || !RQShown(st)) return NO;
    [gRQClosed addObject:it.key];
    [st.items removeObjectForKey:it];
    RQDropEmpty();
    RQSpringBoardAfterRemoval(it.bundleIdentifier);
    return YES;
}
static BOOL DMSMToggleZoom(NSString *bundle) { [gRQOther addObject:[@"zoom " stringByAppendingString:bundle ?: @"?"]]; return YES; }
// (the menu bar's lights: DMLightAction)
static SBApplication *DMActiveApp(void) { if (!gRQFrontBundle) return nil; SBApplication *a = [SBApplication new]; a.bundleIdentifier = gRQFrontBundle; return a; }
static SBApplication *DMFrontApp(void) { return DMActiveApp(); }
static void DMMinimize(void) { [gRQOther addObject:@"minimize (no engine)"]; }
static BOOL DMAppNeedsFullScreen(NSString *bundleID) { return NO; }
static BOOL gPreferRememberedFrame = NO;
static void DMWindowLayout(NSString *name) { [gRQOther addObject:[@"layout " stringByAppendingString:name]]; }
static void DMSendToWindow(NSString *bundleID) { [gRQOther addObject:[@"to window " stringByAppendingString:bundleID]]; }
static void DMForceQuitBundle(NSString *bundleID);
static double DMSMForceQuitWindows(NSString *bundleID, BOOL *windowed);
@interface DMSMTitleBar : UIView
@property (nonatomic, copy) NSString *bundle;
@property (nonatomic, copy) NSString *key;
- (void)dm_light:(UIButton *)b;
@end

#include "rq-real.inc"   // (the real DMSMForceQuitWindows, DMForceQuitBundle, DMForceQuit, DMSMItemFor, DMSMRedLight, DMLightAction, and the class's -dm_light:)

// ---- the checks
static int gFails;
static void ok(BOOL c, NSString *what) { printf("%s  %s\n", c ? "PASS" : "FAIL", what.UTF8String); if (!c) gFails++; }
static NSString *J(id o) { return [o isKindOfClass:[NSArray class]] ? [(NSArray *)o componentsJoinedByString:@", "] : ([o description] ?: @"-"); }
static void reset(BOOL sm, BOOL perWindow) {
    gRQGen++;
    gRQLog = [NSMutableArray array]; gRQMarks = [NSMutableArray array];
    gRQStages = [NSMutableArray array]; gRQShown = nil; gRQRunning = [NSMutableDictionary dictionary]; gRQSeen = [NSMutableDictionary dictionary];
    gRQEnded = [NSMutableArray array]; gRQClosed = [NSMutableArray array]; gRQTerminated = [NSMutableArray array]; gRQDeleted = [NSMutableArray array];
    gRQPrewarm = [NSMutableArray array]; gRQTakenOut = [NSMutableArray array]; gRQForgot = [NSMutableArray array]; gRQMSWForgot = [NSMutableArray array];
    gRQOther = [NSMutableArray array]; gRQAerialClosed = [NSMutableArray array];
    gRQMinimized = [NSMutableSet set]; gRQDesk = [NSMutableDictionary dictionary];
    gRQSM = sm; gRQPerWindow = perWindow; gRQEngine = DMEngineNone; gRQFrontBundle = nil; gRQFrontKey = nil; gRQWholeLayout = NO;
    gRQAerialBundle = nil; gRQAerialStage = nil; gRQSwitcher = [RQSwitcher new]; gAppQuitAt = nil;
}
static int gRQPid = 4000;
static RQStage *stage(NSString *identity, NSArray<NSString *> *keys) {   // (added as the least recent so far; its windows' apps running, seen on screen)
    RQStage *s = [RQStage new]; s.items = [NSMutableDictionary dictionary]; s.identity = identity;
    long long t = 1000 - (long long)gRQStages.count * 100;
    for (NSString *k in keys) {
        RQItem *it = [RQItem new]; it.key = k; s.items[it] = @{@"t": @(t--)};
        NSString *b = DMSMKeyBundle(k);
        if (!gRQRunning[b]) { gRQRunning[b] = @(++gRQPid); gRQSeen[b] = gRQRunning[b]; }
    }
    [gRQStages addObject:s];
    return s;
}
// The Dock's dot for an app now, by its real rule: running and seen on screen with this pid, or a window away (minimized, another desktop); or a
// window of it on screen (MSBDAppsWithWindows: its card).
static BOOL dot(NSString *b) {
    int running = gRQRunning[b] != nil, pid = [gRQRunning[b] intValue];
    int seen = MSBDDotSeenPid(running, pid, RQOnScreen(b), [gRQSeen[b] intValue]);
    BOOL away = DMSMKeySetHas(gRQMinimized, b);
    for (NSString *k in gRQDesk) if ([DMSMKeyBundle(k) isEqualToString:b]) away = YES;
    return MSBDDotShown(running, 1, pid, seen, away) || RQOnScreen(b);
}
static void runFor(double s) { CFTimeInterval end = CACurrentMediaTime() + s; while (CACurrentMediaTime() < end) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false); }
static void redOnBar(NSString *key) {   // (the window's title-bar red light, pressed)
    DMSMTitleBar *bar = [[DMSMTitleBar alloc] initWithFrame:CGRectMake(0, 0, 300, 28)];
    bar.key = key; bar.bundle = DMSMKeyBundle(key);
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.tag = 0;
    gRQT0 = CACurrentMediaTime();
    [bar dm_light:b];
}
static NSDictionary *ended(NSString *b) { for (NSDictionary *e in gRQEnded) if ([e[@"b"] isEqualToString:b]) return e; return nil; }
static NSString *endText(NSString *b) { NSDictionary *e = ended(b); return e ? [NSString stringWithFormat:@"%@ at %.2f s", e[@"why"], [e[@"at"] doubleValue]] : @"still running"; }
// The app ended as Force Quit ends it, about 0.45 s after the press (Force Quit's own wait for the window's Close): SpringBoard's switcher clean-up or
// our terminate request, both asked then -- not SpringBoard's own end 1.25 s after the Close, or never.
static BOOL byUs(NSDictionary *e) { return [e[@"why"] isEqualToString:@"our terminate request"] || [e[@"why"] isEqualToString:@"SpringBoard's switcher clean-up"]; }
static BOOL quitAsForceQuit(NSString *b) {
    NSDictionary *e = ended(b);
    return e && byUs(e) && [e[@"at"] doubleValue] > 0.35 && [e[@"at"] doubleValue] < 0.7
        && [gRQTerminated containsObject:[b stringByAppendingString:@" (reason 1)"]];
}
static BOOL logHas(NSString *part) { for (NSString *l in gRQLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }

static NSString *const kFiles = @"com.apple.DocumentsApp", *const kClock = @"com.apple.mobiletimer", *const kSettings = @"com.apple.Preferences";
static NSString *const kCalc = @"com.apple.calculator", *const kSafari = @"com.apple.mobilesafari", *const kMaps = @"com.apple.Maps", *const kNotes = @"com.apple.mobilenotes";
static NSString *const kFilesA = @"com.apple.DocumentsApp|sceneID:com.apple.DocumentsApp-0D1C2B3A-4F5E-4A6B-8C7D-AAAA7EA9892E";
static NSString *const kFilesB = @"com.apple.DocumentsApp|sceneID:com.apple.DocumentsApp-9E8F7A6B-5C4D-4E3F-9A2B-BBBB14FA6601";
static NSString *const kClockW = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default";
static NSString *const kSettingsW = @"com.apple.Preferences|sceneID:com.apple.Preferences-default";
static NSString *const kCalcW = @"com.apple.calculator|sceneID:com.apple.calculator-default";
static NSString *const kSafA = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-6F1C2D3E-0A1B-4C5D-8E9F-AAAAAAAAAAAA";
static NSString *const kSafT = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-9B8A7C6D-1E2F-4A3B-9C8D-BBBBBBBBBBBB";
static NSString *const kMapsA = @"com.apple.Maps|sceneID:com.apple.Maps-default";
static NSString *const kMapsB = @"com.apple.Maps|sceneID:com.apple.Maps-2C3D4E5F-6A7B-4C8D-9E0F-CCCCCCCCCCCC";
static NSString *const kNotesW = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default";

int main(void) { @autoreleasepool {
    // 0. iPadOS 18.5, Enable Windowing off, iPadOS's own Stage Manager: Clock and Settings in one stage; Force Quit Clock (the Apple menu, Spotlight)
    reset(NO, NO);
    gRQWholeLayout = YES;
    gRQShown = stage(nil, @[kClockW, kSettingsW]);
    gRQT0 = CACurrentMediaTime();
    DMForceQuitBundle(kClock);
    runFor(1.2);
    printf("-- windowing off, iPadOS's own Stage Manager: Force Quit Clock, Settings in its stage\n");
    ok(ended(kClock) != nil, [NSString stringWithFormat:@"windowing off: Clock quits (got: %@)", endText(kClock)]);
    ok(gRQRunning[kSettings] && !ended(kSettings), [NSString stringWithFormat:@"windowing off: Settings, its stage's other window, runs on: the stage is not deleted (Settings: %@)", endText(kSettings)]);
    ok(logHas(@"its stage holds other windows -- left alone"), @"windowing off: ... the log says why");

    // 1. The A12Z's c11: Files with two windows, one minimized (its own stage, not on screen), the other alone on the desktop; its red light.
    reset(YES, YES);
    gRQShown = stage(nil, @[kFilesA]); stage(nil, @[kFilesB]); stage(nil, @[kSettingsW]);
    [gRQMinimized addObject:kFilesB];
    redOnBar(kFilesA);
    runFor(1.2);
    printf("-- Stage Manager: Files's red light on its desktop's last window, its other window minimized (the A12Z's c11)\n");
    ok(quitAsForceQuit(kFiles), [NSString stringWithFormat:@"Files quits as with Force Quit, about 0.45 s after the press: SpringBoard's switcher clean-up and our terminate request, not SpringBoard's own end, which never comes (got: %@)", endText(kFiles)]);
    ok(!dot(kFiles), @"  ... and the Dock has no dot under Files 1.2 s after the press");
    ok([gRQClosed.firstObject isEqualToString:kFilesA], [NSString stringWithFormat:@"  ... the window pressed closes with its own Close first (closed: %@)", J(gRQClosed)]);
    ok(!RQHeld(kFiles) && !DMSMKeySetHas(gRQMinimized, kFiles), @"  ... no stage holds Files any more and its minimized mark is gone");
    ok([gRQPrewarm isEqualToArray:@[kFiles]] && gAppQuitAt[kFiles] && [gRQMSWForgot containsObject:kFiles] && [gRQForgot containsObject:kFiles],
       [NSString stringWithFormat:@"  ... its quit records as Force Quit's: the prewarm quit set, the quit time, the desktop records (prewarm: %@)", J(gRQPrewarm)]);
    ok(gRQRunning[kSettings] && !ended(kSettings), @"  ... Settings, in another stage, runs on");
    ok(logHas(@"[smengine] red light on com.apple.DocumentsApp/7EA9892E: the app's last window on screen -- the app quits (as Force Quit)"), @"  ... the log says why the app quits");

    // 2. The A12Z's c3/c5: Clock's window shares the desktop with other apps' windows; its red light.
    reset(YES, YES);
    gRQShown = stage(nil, @[kClockW, kSettingsW, kCalcW]);
    redOnBar(kClockW);
    runFor(1.2);
    printf("-- Stage Manager: Clock's red light, its only window sharing the desktop with Settings and Calculator (c3, c5)\n");
    ok(quitAsForceQuit(kClock), [NSString stringWithFormat:@"Clock quits as with Force Quit, about 0.45 s after the press, not 1.25 s after its Close (got: %@)", endText(kClock)]);
    ok(!dot(kClock), @"  ... no dot under Clock 1.2 s after the press");
    ok([gRQClosed isEqualToArray:@[kClockW]] && gRQShown.items.count == 2 && gRQRunning[kSettings] && gRQRunning[kCalc],
       [NSString stringWithFormat:@"  ... only Clock's window closes; Settings and Calculator stay on the desktop, running (closed: %@)", J(gRQClosed)]);

    // 3. The A12Z's c9/c10: Settings, the desktop's last window, its red light.
    reset(YES, YES);
    gRQShown = stage(nil, @[kSettingsW]); stage(nil, @[kCalcW]);
    redOnBar(kSettingsW);
    runFor(1.2);
    printf("-- Stage Manager: Settings's red light, the desktop's last window (c9, c10)\n");
    ok(quitAsForceQuit(kSettings) && !dot(kSettings), [NSString stringWithFormat:@"Settings quits as with Force Quit and has no dot 1.2 s after the press (got: %@)", endText(kSettings)]);
    ok(gRQRunning[kCalc] != nil, @"  ... Calculator, in a stage not on screen, runs on");

    // 4. Unchanged (c6a, the 17.5's Q8): two windows of Files on the desktop, the red light on the front one.
    reset(YES, YES);
    gRQShown = stage(nil, @[kFilesA, kFilesB, kSettingsW]);
    redOnBar(kFilesA);
    runFor(1.2);
    printf("-- unchanged: Files with two windows on the desktop, the red light on one (c6a, Q8)\n");
    ok([gRQClosed isEqualToArray:@[kFilesA]] && !ended(kFiles) && !gRQTerminated.count && !gRQPrewarm.count && !gRQForgot.count,
       [NSString stringWithFormat:@"only that window closes: Files runs on, no quit records (closed: %@; %@)", J(gRQClosed), endText(kFiles)]);
    ok(dot(kFiles) && RQOnScreen(kFiles), @"  ... its other window stays on the desktop, with Files's dot");
    ok(logHas(@"1 other window(s) of the app on screen -- only this window closes"), @"  ... the log says why only the window closes");

    // 5. The menu bar's red light: (a) the front window is Files's last on screen, its other minimized; (b) two windows of Files on the desktop.
    reset(YES, YES);
    gRQShown = stage(nil, @[kFilesA, kCalcW]); stage(nil, @[kFilesB]);
    [gRQMinimized addObject:kFilesB];
    gRQFrontBundle = kFiles; gRQFrontKey = kFilesA;
    gRQT0 = CACurrentMediaTime(); DMLightAction(0);
    runFor(1.2);
    printf("-- Stage Manager: the menu bar's red light, Files in front, its other window minimized\n");
    ok(quitAsForceQuit(kFiles) && !dot(kFiles) && gRQRunning[kCalc], [NSString stringWithFormat:@"Files quits as with Force Quit, no dot; Calculator runs on (got: %@)", endText(kFiles)]);
    reset(YES, YES);
    gRQShown = stage(nil, @[kFilesA, kFilesB]);
    gRQFrontBundle = kFiles; gRQFrontKey = kFilesA;
    gRQT0 = CACurrentMediaTime(); DMLightAction(0);
    runFor(1.2);
    printf("-- unchanged: the menu bar's red light, Files in front with two windows on the desktop\n");
    ok([gRQClosed isEqualToArray:@[kFilesA]] && !ended(kFiles) && !gRQTerminated.count, [NSString stringWithFormat:@"only the front window closes, Files runs on (closed: %@)", J(gRQClosed)]);

    // 6. The TV: Safari has a window on the iPad's desktop and one on the TV's (shown there). Red on the iPad's: only it closes. Then red on the TV's.
    reset(YES, YES);
    gRQShown = stage(nil, @[kSafA, kCalcW]); RQStage *tv = stage(@"tv", @[kSafT]); tv.onTV = YES;
    redOnBar(kSafA);
    runFor(1.2);
    printf("-- Stage Manager: Safari with a window on the iPad's desktop and one on the TV's\n");
    ok([gRQClosed isEqualToArray:@[kSafA]] && !ended(kSafari) && !gRQTerminated.count,
       [NSString stringWithFormat:@"red on the iPad's window: only it closes (its other window is on the TV's screen); Safari runs on (closed: %@)", J(gRQClosed)]);
    redOnBar(kSafT);
    runFor(1.2);
    ok(quitAsForceQuit(kSafari) && !dot(kSafari), [NSString stringWithFormat:@"  ... then red on the TV's window, its last on screen: Safari quits as with Force Quit, no dot (got: %@)", endText(kSafari)]);

    // 7. Another desktop: Maps's window here, alone of its app; another Maps window on Desktop 2 (a stage not on screen, with Notes's window).
    reset(YES, YES);
    gRQShown = stage(nil, @[kMapsA, kCalcW]); stage(nil, @[kMapsB, kNotesW]);
    gRQDesk[kMapsA] = @1; gRQDesk[kCalcW] = @1; gRQDesk[kMapsB] = @2; gRQDesk[kNotesW] = @2;
    redOnBar(kMapsA);
    runFor(1.2);
    printf("-- Stage Manager: Maps's red light here, its other window on Desktop 2\n");
    ok(quitAsForceQuit(kMaps) && !dot(kMaps), [NSString stringWithFormat:@"Maps quits as with Force Quit, every window of it, no dot (got: %@)", endText(kMaps)]);
    ok([gRQTakenOut isEqualToArray:@[kMapsB]] && !gRQDesk[kMapsB] && gRQDesk[kNotesW] && gRQRunning[kNotes],
       [NSString stringWithFormat:@"  ... its window on Desktop 2 leaves that stage and its record goes; Notes's stays there, running (taken out: %@)", J(gRQTakenOut)]);

    // 8. Windows by app (the optional check rows missing: every window's key is its app's): two Safari windows on the desktop, red on one.
    reset(YES, NO);
    gRQShown = stage(nil, @[kSafA, kSafT, kCalcW]);
    redOnBar(kSafari);
    runFor(1.2);
    printf("-- unchanged: windows told apart by app, two Safari windows on the desktop, red on one\n");
    ok(gRQClosed.count == 1 && !ended(kSafari) && !gRQTerminated.count, [NSString stringWithFormat:@"only one window closes, Safari runs on (the windows told apart by their items; closed: %@)", J(gRQClosed)]);

    // 9. The stage on the iPad's screen can't be read: the window's own Close, as before.
    reset(YES, YES);
    stage(nil, @[kClockW]); gRQShown = nil;
    redOnBar(kClockW);
    runFor(0.8);
    printf("-- the stage on screen not readable\n");
    ok(!gRQTerminated.count && !gRQPrewarm.count && logHas(@"not in a stage on screen -- its own Close"), @"red: its own Close as before, nothing quit by us");

    // 10. Unchanged: the other engines (Aerial): the menu bar's red light is Force Quit.
    reset(NO, NO); gRQEngine = DMEngineAerial;
    gRQAerialBundle = kMaps; gRQAerialStage = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 600, 500)];
    gRQRunning[kMaps] = @4999; gRQFrontBundle = kMaps;
    gRQT0 = CACurrentMediaTime(); DMLightAction(0);
    runFor(0.9);
    printf("-- unchanged: Aerial, the menu bar's red light\n");
    ok([gRQAerialClosed isEqualToArray:@[kMaps]] && ended(kMaps) && byUs(ended(kMaps)) && [gRQTerminated containsObject:[kMaps stringByAppendingString:@" (reason 1)"]] && [ended(kMaps)[@"at"] doubleValue] < 0.35,
       [NSString stringWithFormat:@"Maps's window closes with Aerial's close, then Maps ends at once (got: %@)", endText(kMaps)]);

    // 11. Unchanged: yellow and green.
    reset(YES, YES);
    gRQShown = stage(nil, @[kClockW]);
    DMSMTitleBar *bar = [DMSMTitleBar new]; bar.key = kClockW; bar.bundle = kClock;
    UIButton *y = [UIButton buttonWithType:UIButtonTypeCustom]; y.tag = 1; [bar dm_light:y];
    UIButton *g = [UIButton buttonWithType:UIButtonTypeCustom]; g.tag = 2; [bar dm_light:g];
    gRQFrontBundle = kClock; gRQFrontKey = kClockW; DMLightAction(1); DMLightAction(2);
    runFor(0.3);
    printf("-- unchanged: yellow and green\n");
    ok([gRQOther isEqualToArray:@[[@"minimize " stringByAppendingString:kClockW], [@"zoom " stringByAppendingString:kClockW], [@"minimize " stringByAppendingString:kClockW], [@"zoom " stringByAppendingString:kClockW]]]
       && !gRQClosed.count && !gRQTerminated.count, [NSString stringWithFormat:@"yellow minimizes, green zooms, nothing closes or quits (got: %@)", J(gRQOther)]);
    return gFails;
}}
