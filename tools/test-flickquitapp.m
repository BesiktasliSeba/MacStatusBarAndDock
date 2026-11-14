// test-flickquitapp.m -- Mac test (Mac Catalyst: UIKit on the Mac) of Swipe Up to Quit with the Stage Manager engine (1.8.7.3, audit M8 of
// 1.8.7.2): a window flicked up in the Mac Switcher quits its app, every window of it, as on the other engines. A Stage Manager thumbnail names
// its window by its KEY ("<bundle>|<scene>", MacSwitcherSM.h); the flick handed that key to Force Quit, so only the flicked window closed, the app
// kept running (the terminate request and SpringBoard's switcher clean-up named no app), its other thumbnail stayed, and the quit records (the
// prewarm quit set, the quit time, the desktop records) were filed under the key.
// Runs the real DMMSWFlickQuit and DMMSWForgetApp (statusbar/MacSwitcher.h), DMForceQuitBundle and DMSMForceQuitWindows (statusbar/StatusBar.x),
// cut out of the sources by test-flickquitapp.sh into fq-real.inc, with the real statusbar/SMWindowKey.h. SpringBoard's side (the stage on screen,
// a window's own Close, the terminate request, the switcher's clean-up) is the stand-ins below, which record what they are asked.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../statusbar/SMWindowKey.h"

// ---- what the real code logs and marks
static NSMutableArray<NSString *> *gFQLog, *gFQMarks;
static void FQLog(NSString *s) { [gFQLog addObject:s ?: @""]; }
#define DMLog(...) FQLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name) [gFQMarks addObject:@name]

// ---- SpringBoard's side, recorded
static NSMutableArray<NSString *> *gFQTerminated, *gFQDeleted, *gFQClosed, *gFQPrewarm, *gFQAerialClosed, *gFQKeptForget;
static NSMutableDictionary<NSString *, NSDictionary *> *gFQStage;   // the iPad's stage on screen: its windows, each by its scene's key -> @{@"t": last interaction}
static BOOL gFQSM, gFQPerWindow;   // the Stage Manager engine; windows told apart (16.x: per-window keys) or by app
static NSString *gFQAerialBundle; static UIView *gFQAerialStage;   // (the other engines: the app's window)
void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reasonID, bool report, NSString *description) {
    [gFQTerminated addObject:[NSString stringWithFormat:@"%@ (reason %d)", bundleID ?: @"(nil)", reasonID]];
}
@interface FQSwitcher : NSObject
- (void)_deleteAppLayoutsMatchingBundleIdentifier:(NSString *)bundleID;
@end
@implementation FQSwitcher
- (void)_deleteAppLayoutsMatchingBundleIdentifier:(NSString *)bundleID { [gFQDeleted addObject:bundleID ?: @"(nil)"]; }
@end
static FQSwitcher *gFQSwitcher;
static id DMSwitcherController(void) { return gFQSwitcher; }
static id DMCall(id obj, NSString *name) {   // (StatusBar.x's)
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;   // (StatusBar.x's)
static DMEngine gFQEngine;
static DMEngine DMActiveEngine(void) { return gFQEngine; }
static BOOL DMSMEngine(void) { return gFQSM; }
static BOOL DMGARefuses(NSString *what) { return NO; }
static BOOL DMWaitForContextMenu(NSString *key, dispatch_block_t again) { return NO; }
static BOOL DMSMStripHoldsBack(NSString *what, dispatch_block_t act) { return NO; }
static void DMPrewarmQuitAdd(NSString *bundleID) { [gFQPrewarm addObject:bundleID ?: @"(nil)"]; }
static UIView *DMStageForBundle(NSString *bundleID) { return gFQAerialBundle && [bundleID isEqualToString:gFQAerialBundle] ? gFQAerialStage : nil; }
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
static double DMAerialCloseForQuit(NSString *bundleID) { [gFQAerialClosed addObject:bundleID ?: @"(nil)"]; return 0.2; }
// (the Stage Manager engine: the stage on screen is gFQStage; an item stands as its window's key, its app the key's bundle)
static id DMSMIPadStageShown(void) { return gFQStage; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage copy]; }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { NSNumber *t = attrs[@"t"]; return t ? t.longLongValue : dflt; }
static NSString *DMSMItemBundle(id item) { return DMSMKeyBundle(item); }
static NSString *DMSMItemKey(id item) { return gFQPerWindow ? item : DMSMKeyBundle(item); }
static int DMSMTakeOutOfHiddenStages(NSString *bundle) { return 0; }
static void DMSMForgetApp(NSString *bundle) {}
// A window's own Close (DMSMWindowAction): the window that key names on the stage on screen -- that very window; an app key: the app's newest
// (SMWindowKey.h DMSMKeyPick, as the engine picks) -- closes and leaves the stage.
static BOOL DMSMWindowAction(NSString *key, NSString *name) {
    NSMutableArray<NSDictionary *> *w = [NSMutableArray array];
    for (NSString *it in gFQStage) [w addObject:@{@"k": DMSMItemKey(it), @"t": gFQStage[it][@"t"], @"item": it}];
    NSUInteger i = DMSMKeyPick(w, key);
    if (![name isEqualToString:@"close"] || i == NSNotFound) return NO;
    [gFQClosed addObject:w[i][@"item"]];
    [gFQStage removeObjectForKey:w[i][@"item"]];
    return YES;
}

// ---- the Mac Switcher's side (MacSwitcher.h's tile and records)
typedef NS_ENUM(NSInteger, DMMSWKind) { DMMSWKindStage = 1, DMMSWKindNative = 2, DMMSWKindFullScreen = 3 };
@interface DMMSWTile : UIView
@property (nonatomic, assign) DMMSWKind kind;
@property (nonatomic, copy) NSString *bundle;
@property (nonatomic, strong) UIView *inner;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, copy) NSString *title;
@end
@implementation DMMSWTile
@end
static UIView *gMSWRoot;
static NSMutableArray<DMMSWTile *> *gMSWTiles;
static NSMutableDictionary<NSString *, NSNumber *> *gMSWWinDesk, *gMSWQuitting;
static NSMutableDictionary<NSString *, NSString *> *gMSWWinFrame, *gMSWFullScreen;
static NSMutableDictionary<NSString *, UIView *> *gMSWWinShots;
static NSMutableDictionary<NSString *, NSDictionary *> *gMSWFit;
static int gFQLayOuts, gFQSaves;
static BOOL MSBReduceMotion(void) { return NO; }
static void DMMSWLayOutTiles(void) { gFQLayOuts++; }
static void DMMSWKeptForget(NSString *b) { [gFQKeptForget addObject:b ?: @"(nil)"]; }
static NSDictionary *DMMSWFitWithout(NSDictionary *fit, NSString *b) { return nil; }
static void DMMSWSave(void) { gFQSaves++; }
static NSMutableDictionary<NSString *, NSNumber *> *gAppQuitAt;   // (StatusBar.x's, just above DMForceQuitBundle)
static void DMForceQuitBundle(NSString *bundleID);
static void DMMSWForgetApp(NSString *b);
static double DMSMForceQuitWindows(NSString *bundleID, BOOL *windowed);

#include "fq-real.inc"   // (the real DMMSWForgetApp, DMSMForceQuitWindows, DMForceQuitBundle, DMMSWFlickQuit)

// ---- the checks
static int gFails;
static void ok(BOOL c, NSString *what) { printf("%s  %s\n", c ? "PASS" : "FAIL", what.UTF8String); if (!c) gFails++; }
static NSString *J(id o) { return [o isKindOfClass:[NSArray class]] ? [(NSArray *)o componentsJoinedByString:@", "] : [o description]; }
static void reset(BOOL sm, BOOL perWindow, DMEngine engine) {
    gFQLog = [NSMutableArray array]; gFQMarks = [NSMutableArray array];
    gFQTerminated = [NSMutableArray array]; gFQDeleted = [NSMutableArray array]; gFQClosed = [NSMutableArray array];
    gFQPrewarm = [NSMutableArray array]; gFQAerialClosed = [NSMutableArray array]; gFQKeptForget = [NSMutableArray array];
    gFQStage = [NSMutableDictionary dictionary]; gFQSM = sm; gFQPerWindow = perWindow; gFQEngine = engine;
    gFQAerialBundle = nil; gFQAerialStage = nil; gFQSwitcher = [FQSwitcher new];
    gMSWRoot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    gMSWTiles = [NSMutableArray array];
    gMSWWinDesk = [NSMutableDictionary dictionary]; gMSWQuitting = nil; gMSWWinFrame = [NSMutableDictionary dictionary];
    gMSWFullScreen = [NSMutableDictionary dictionary]; gMSWWinShots = [NSMutableDictionary dictionary]; gMSWFit = [NSMutableDictionary dictionary];
    gAppQuitAt = nil; gFQLayOuts = gFQSaves = 0;
}
static DMMSWTile *tile(DMMSWKind kind, NSString *key, CGFloat x) {
    DMMSWTile *t = [[DMMSWTile alloc] initWithFrame:CGRectMake(x, 300, 300, 220)];
    t.kind = kind; t.bundle = key; t.title = key ? DMSMKeyBundle(key) : @"Finder";
    t.inner = [[UIView alloc] initWithFrame:t.bounds]; [t addSubview:t.inner];
    t.label = [[UILabel alloc] initWithFrame:CGRectMake(x, 530, 300, 20)];
    [gMSWRoot addSubview:t]; [gMSWRoot addSubview:t.label]; [gMSWTiles addObject:t];
    return t;
}
static void runFor(double s) {   // (the main queue: the windows' Closes a moment apart, the kill, the clean-up again 0.6 s later, the fly-off's end)
    CFTimeInterval end = CACurrentMediaTime() + s;
    while (CACurrentMediaTime() < end) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
}
static NSArray<NSString *> *tilesLeft(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (DMMSWTile *t in gMSWTiles) [a addObject:t.kind == DMMSWKindNative ? @"(Finder)" : t.bundle];
    return a;
}
static BOOL allAre(NSArray<NSString *> *a, NSString *v) { if (!a.count) return NO; for (NSString *s in a) if (![s isEqualToString:v]) return NO; return YES; }

static NSString *const kSafari = @"com.apple.mobilesafari", *const kNotes = @"com.apple.mobilenotes";
static NSString *const kSafA = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-6F1C2D3E-0A1B-4C5D-8E9F-AAAAAAAAAAAA";
static NSString *const kSafB = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-9B8A7C6D-1E2F-4A3B-9C8D-BBBBBBBBBBBB";
static NSString *const kSafC = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-1A2B3C4D-5E6F-4071-8293-CCCCCCCCCCCC";
static NSString *const kNotesW = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default";

int main(void) { @autoreleasepool {
    // 1. Stage Manager engine, windows told apart (16.x): Safari has two windows on the desktop on screen and one on Desktop 2; Notes one; a Finder
    //    window over them. The user flicks Safari's front window up.
    reset(YES, YES, DMEngineNone);
    gFQStage[kSafA] = @{@"t": @300}; gFQStage[kNotesW] = @{@"t": @200}; gFQStage[kSafB] = @{@"t": @100};
    tile(DMMSWKindStage, kSafB, 40); tile(DMMSWKindStage, kNotesW, 380); DMMSWTile *a = tile(DMMSWKindStage, kSafA, 720); tile(DMMSWKindNative, nil, 1060);
    gMSWWinDesk[kSafA] = @1; gMSWWinDesk[kSafB] = @1; gMSWWinDesk[kNotesW] = @1; gMSWWinDesk[kSafC] = @2;
    gMSWWinFrame[kSafC] = @"{{100, 120}, {700, 600}}";
    DMMSWFlickQuit(a, @"a flick (test)");
    runFor(1.8);
    printf("-- Stage Manager engine, Safari with two windows here and one on Desktop 2: its front window flicked up\n");
    ok([gFQTerminated isEqualToArray:@[@"com.apple.mobilesafari (reason 1)"]],
       [NSString stringWithFormat:@"the app ends: the one terminate request names com.apple.mobilesafari, as the App Switcher's swipe-up (got: %@)", J(gFQTerminated)]);
    ok([gFQClosed isEqualToArray:@[kSafA, kSafB]],
       [NSString stringWithFormat:@"both of Safari's windows on the desktop close with their own Close, the flicked one first; Notes's stays (closed: %@)", J(gFQClosed)]);
    ok([tilesLeft() isEqualToArray:@[kNotesW, @"(Finder)"]] && !a.superview,
       [NSString stringWithFormat:@"Safari's other thumbnail leaves the view with the flicked one; Notes's and Finder's stay (left: %@)", J(tilesLeft())]);
    ok(gMSWWinDesk.count == 1 && gMSWWinDesk[kNotesW] && !gMSWWinFrame[kSafC],
       [NSString stringWithFormat:@"every Safari window's desktop record goes, Desktop 2's too; Notes's is kept (left: %@)", J(gMSWWinDesk.allKeys)]);
    ok([gFQPrewarm isEqualToArray:@[kSafari]] && gAppQuitAt[kSafari] && gAppQuitAt.count == 1 && gMSWQuitting[kSafari] && gMSWQuitting.count == 1,
       [NSString stringWithFormat:@"the prewarm quit set, the quit time and the quitting mark are the app's, not its window's (prewarm: %@; quit time: %@)", J(gFQPrewarm), J(gAppQuitAt.allKeys)]);
    ok(gFQDeleted.count == 2 && allAre(gFQDeleted, kSafari),
       [NSString stringWithFormat:@"SpringBoard's switcher clean-up is asked for the app, at once and 0.6 s later (got: %@)", J(gFQDeleted)]);
    ok([gFQLog containsObject:@"[macswitcher] swipe up to quit: com.apple.mobilesafari (a flick (test)), its 1 other window(s) in the view too"],
       @"the log names the app and its other window in the view");

    // 2. Any other caller handing Force Quit a window's key (none does today; Force Quit takes it as the window's app from now on)
    reset(YES, YES, DMEngineNone);
    gFQStage[kSafA] = @{@"t": @300}; gFQStage[kNotesW] = @{@"t": @200};
    gMSWWinDesk[kSafA] = @1; gMSWWinDesk[kNotesW] = @1;
    DMForceQuitBundle(kNotesW);
    runFor(1.3);
    printf("-- Stage Manager engine: Force Quit asked with a window's key (Notes's)\n");
    ok([gFQTerminated isEqualToArray:@[@"com.apple.mobilenotes (reason 1)"]] && [gFQClosed isEqualToArray:@[kNotesW]] && allAre(gFQDeleted, kNotes),
       [NSString stringWithFormat:@"Force Quit quits the key's app: its window closes, the terminate request and the clean-up name the app (terminated: %@; closed: %@; clean-up: %@)", J(gFQTerminated), J(gFQClosed), J(gFQDeleted)]);
    ok([gFQPrewarm isEqualToArray:@[kNotes]] && gAppQuitAt[kNotes] && gAppQuitAt.count == 1 && gMSWWinDesk.count == 1 && gMSWWinDesk[kSafA],
       [NSString stringWithFormat:@"  ... its records are the app's: the prewarm quit set and the quit time; Notes's desktop record goes, Safari's stays (prewarm: %@; records left: %@)", J(gFQPrewarm), J(gMSWWinDesk.allKeys)]);
    ok([gFQLog containsObject:@"[action] force quit com.apple.mobilenotes (windowed)"], @"  ... and the log names the app");

    // 3. Unchanged: Stage Manager with windows by app (the optional check rows missing: every key is an app key)
    reset(YES, NO, DMEngineNone);
    gFQStage[kSafA] = @{@"t": @300}; gFQStage[kNotesW] = @{@"t": @200};
    tile(DMMSWKindStage, kNotes, 40); DMMSWTile *s3 = tile(DMMSWKindStage, kSafari, 380);
    gMSWWinDesk[kSafari] = @1; gMSWWinDesk[kNotes] = @1;
    DMMSWFlickQuit(s3, @"a flick (test)");
    runFor(1.3);
    printf("-- unchanged: Stage Manager engine with windows by app, Safari flicked up\n");
    ok([gFQTerminated isEqualToArray:@[@"com.apple.mobilesafari (reason 1)"]] && [gFQClosed isEqualToArray:@[kSafA]] && [tilesLeft() isEqualToArray:@[kNotes]]
       && gMSWWinDesk.count == 1 && gMSWWinDesk[kNotes] && [gFQPrewarm isEqualToArray:@[kSafari]],
       [NSString stringWithFormat:@"Safari ends, its window closes, Notes's thumbnail and record stay (terminated: %@; closed: %@; left: %@)", J(gFQTerminated), J(gFQClosed), J(tilesLeft())]);

    // 4. Unchanged: the other engines (Aerial here): a thumbnail is its app
    reset(NO, NO, DMEngineAerial);
    gFQAerialBundle = @"com.apple.Maps"; gFQAerialStage = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 600, 500)];
    tile(DMMSWKindStage, kNotes, 40); DMMSWTile *m = tile(DMMSWKindStage, @"com.apple.Maps", 380);
    gMSWWinDesk[@"com.apple.Maps"] = @1; gMSWWinDesk[kNotes] = @2;
    DMMSWFlickQuit(m, @"a flick (test)");
    runFor(1.2);
    printf("-- unchanged: Aerial, Maps flicked up\n");
    ok([gFQTerminated isEqualToArray:@[@"com.apple.Maps (reason 1)"]] && [gFQAerialClosed isEqualToArray:@[@"com.apple.Maps"]] && [tilesLeft() isEqualToArray:@[kNotes]]
       && gMSWWinDesk.count == 1 && gMSWWinDesk[kNotes] && [gFQPrewarm isEqualToArray:@[@"com.apple.Maps"]] && allAre(gFQDeleted, @"com.apple.Maps"),
       [NSString stringWithFormat:@"Maps's window closes with Aerial's close, then Maps ends; Notes's thumbnail and record stay (terminated: %@; left: %@)", J(gFQTerminated), J(tilesLeft())]);
    return gFails;
}}
