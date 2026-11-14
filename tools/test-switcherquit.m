// test-switcherquit.m -- Mac test (Mac Catalyst: UIKit on the Mac) of an app quit with iPadOS's own App Switcher and the Mac Switcher's desktops
// (1.8.7.3, audit M9 of 1.8.7.2). Aerial, Zetsu or MilkyWay4 with two desktops, Clock's window on Desktop 2: the user swipes Clock's card up in the
// App Switcher and Clock is quit, but its desktop record stayed, so when Desktop 2 came the Mac Switcher took the record without its window for an
// app iPadOS had closed and opened Clock again at its old place, undoing the quit. Only our own Force Quit forgot the records (DMMSWForgetApp);
// SpringBoard's swipe-up reached only the prewarm quit set, through the reason-1 kill hook every user quit passes.
// MilkyWay4 keeps the window of a killed app, so with the record forgotten only the 4 s quitting mark kept Clock's grey window away; when MilkyWay's
// dead-window check could not run by then (the iPad locked right after the swipe), the tick (DMMSWApply) took it for a new window of the desktop on
// screen and showed it there empty (review of the M9 fix): the quit now closes that window, as our Force Quit does (DMMSWMWCloseQuitAway).
// Runs the real DMPrewarmQuitAdd and DMPrewarmQuitAddFromKill (statusbar/StatusBar.x), DMMSWFitWithout, DMMSWForgetApp, DMMSWMWAppGone,
// DMMSWMWCloseGone, DMMSWMWCloseQuitAway (when the file has it), DMMSWRelaunchAt, DMMSWRelaunchClosed and DMMSWApply (statusbar/MacSwitcher.h),
// cut out of the sources by test-switcherquit.sh into sq-real.inc, with the real statusbar/SMWindowKey.h, statusbar/FitPlan.h and
// statusbar/MSWEngineRecords.h. SpringBoard's and the engines' side (the process the kill names, the engine's windows, the launches) is the
// stand-ins below, which record what they are asked.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../statusbar/SMWindowKey.h"
#include "../statusbar/FitPlan.h"
#include "../statusbar/MSWEngineRecords.h"

// ---- what the real code logs
static NSMutableArray<NSString *> *gSQLog;
static void SQLog(NSString *s) { @synchronized (gSQLog) { [gSQLog addObject:s ?: @""]; } }
#define DMLog(...) SQLog(__VA_ARGS__)

// ---- StatusBar.x's side
static id DMCall(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
@interface SQProcess : NSObject   // (FBApplicationProcess: the process a kill names)
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SQProcess
@end
#define MSB_PREWARM_CAP 128
static NSMutableArray<NSString *> *gPrewarmQuitSet;
static int gSQPublishes;
static void DMPrewarmQuitPublish(void) { gSQPublishes++; }
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;   // (StatusBar.x's)
static DMEngine gSQEngine;
static DMEngine DMActiveEngine(void) { return gSQEngine; }
static const void *kMSWAwayKey = &kMSWAwayKey;
static const void *kFitSizeKey = &kFitSizeKey;
static const void *kSQBundleKey = &kSQBundleKey;
static NSMutableArray<UIView *> *gSQStages;   // the engine's windows, every desktop's (DMAerialStagesAll)
static NSArray<UIView *> *DMAerialStagesAll(void) { return [gSQStages copy]; }
static NSString *DMStageBundle(UIView *stage) { return objc_getAssociatedObject(stage, kSQBundleKey); }
static BOOL DMMSWMinimizedByUs(UIView *st) { return NO; }
static id DMStageScene(UIView *stage, NSString *bundle) { return nil; }   // (MilkyWay4's grey window of an app that is gone: no scene)
static BOOL DMSceneAlive(id scene) { return NO; }
static NSMutableSet<NSString *> *gSQRunning;
static NSSet<NSString *> *DMLiveRunningBundleIDs(void) { return [gSQRunning copy]; }
static NSMutableArray<NSString *> *gSQLaunched, *gSQClosed;   // what was opened (how), which windows closed
static const void *kStageClosingKey = &kStageClosingKey;
@interface AXWindowView : UIView   // (MilkyWay4's window)
- (void)closeButtonAction:(id)sender;
@end
@implementation AXWindowView
// (marked closing first, as StatusBar.x's hook of it does; MilkyWay keeps a closed window in its layer for its animation, then takes it out)
- (void)closeButtonAction:(id)sender {
    objc_setAssociatedObject(self, kStageClosingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gSQClosed addObject:DMStageBundle(self) ?: @"(none)"];
    __weak UIView *me = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ UIView *v = me; if (v) [gSQStages removeObjectIdenticalTo:v]; });
}
@end
static NSMutableDictionary<NSString *, NSValue *> *gLastWindowFrames;
static void DMZetsuLaunch(NSString *b) { [gSQLaunched addObject:[@"zetsu " stringByAppendingString:b]]; }
static void DMLaunchAsWindow(NSString *b) { [gSQLaunched addObject:[@"window " stringByAppendingString:b]]; }
static void DMLaunchIntoTile(NSString *b, CGRect f) { [gSQLaunched addObject:[NSString stringWithFormat:@"tile %@ %@", b, NSStringFromCGRect(f)]]; }
static void DMOpenApp(NSString *b) { [gSQLaunched addObject:[@"open " stringByAppendingString:b]]; }

// ---- MacSwitcher.h's side
static NSMutableDictionary<NSString *, NSNumber *> *gMSWWinDesk, *gMSWQuitting, *gMSWRelaunching;
static NSMutableDictionary<NSString *, NSString *> *gMSWWinFrame, *gMSWFullScreen;
static NSMutableDictionary<NSString *, UIView *> *gMSWWinShots;
static NSMutableDictionary<NSString *, NSDictionary *> *gMSWFit;
static NSInteger gSQCur;
static NSInteger DMMSWCurId(void) { return gSQCur; }
static void DMMSWAfter(double seconds, dispatch_block_t b) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }
static int gSQSaves, gSQOffMain;   // records saved; record work seen off the main thread
static NSMutableArray<NSString *> *gSQKeptForget;   // the kept copy told (DMMSWKeptForget: the Mac Switcher off -- its own test is test-mswkept)
static void DMMSWSave(void) { gSQSaves++; if (![NSThread isMainThread]) gSQOffMain++; }
static void DMMSWKeptForget(NSString *b) { [gSQKeptForget addObject:b ?: @"(nil)"]; if (![NSThread isMainThread]) gSQOffMain++; }
static void DMMSWForgetApp(NSString *b);
// (DMMSWApply's side: the tick that puts every window where its record says. One display, the iPad's desktops; no Stage Manager engine; the
//  window state saved, no restore running; no native window)
static BOOL gWindowSaveOn = YES, gRestoringWindows = NO;
static BOOL gMSWKeysCopied, gMSWDesksDirty, gMSWSwInChange;
static NSUInteger gMSWAwayCount;
static NSMutableArray<NSNumber *> *gMSWDesks;   // (MacSwitcher.h's is the model in use's: the desktops' ids in strip order)
static NSMutableDictionary<NSString *, NSNumber *> *gMSWAsideDesk;
static NSMutableDictionary<NSString *, UIView *> *gMSWFreshPics;
static NSMutableDictionary<NSString *, id> *gMSWNoFocus;
static NSString *gMSWDropHold;
@interface DMNativeWindow : UIView
@property (nonatomic, copy) NSString *title;
@end
@implementation DMNativeWindow
@end
static NSMutableArray<DMNativeWindow *> *gNativeWindows, *gMSWAwayNatives;
static __weak DMNativeWindow *gMSWDropHoldNative;
static DMNativeWindow *gNativeActive;
static UIWindow *gNativeLayer;
static const void *kMSWNativeDeskKey = &kMSWNativeDeskKey;
static const void *kZetsuLockPillKey = &kZetsuLockPillKey;
static BOOL DMMSWForMain(void) { return YES; }
static BOOL DMSMEngine(void) { return NO; }
static void DMMSWSMApply(void) {}
static BOOL DMMSWAppKeysOnly(void) { return DMActiveEngine() != DMEngineNone; }
static NSString *DMWindowStatePath(void) { return @"/nonexistent/sq-windows.plist"; }
static void DMMSWRecordsBeforeRestore(NSArray<NSString *> *savedApps) {}
static void DMMSWFoldWindowKeys(void) {}
static BOOL DMMSWMulti(void) { return gMSWDesks.count > 1; }
static BOOL DMTestFlag(const char *path) { return NO; }
static BOOL DMMSWAsyncPicsOn(void) { return YES; }
static void DMMSWSpanBegin(void) {}
static void DMMSWSpanEnd(NSString *what) {}
static void DMMSWFocusAway(NSString *b, BOOL away) {}
static BOOL DMMSWZetsuReduced(UIView *w) { return NO; }
static void DMMSWZetsuReopen(UIWindow *w) {}
static void DMNativeSetActive(DMNativeWindow *w) {}
static UIView *DMNativeHost(void) { return nil; }
static void DMNativeApplyLevel(void) {}

#include "sq-real.inc"   // (the real DMPrewarmQuitAdd, DMPrewarmQuitAddFromKill, DMMSWFitWithout, DMMSWForgetApp, DMMSWMWAppGone, DMMSWMWCloseGone,
                         //  DMMSWMWCloseQuitAway, DMMSWRelaunchAt, DMMSWRelaunchClosed, DMMSWApply)

// ---- the checks
static int gFails;
static void ok(BOOL c, NSString *what) { printf("%s  %s\n", c ? "PASS" : "FAIL", what.UTF8String); if (!c) gFails++; }
static NSString *J(id o) { return [o isKindOfClass:[NSArray class]] ? [(NSArray *)o componentsJoinedByString:@", "] : [o description] ?: @"(none)"; }
static NSString *const kClock = @"com.apple.mobiletimer", *const kNotes = @"com.apple.mobilenotes", *const kMaps = @"com.apple.Maps";
static NSString *const kClockFrame = @"{{120, 140}, {640, 520}}";
static void reset(DMEngine engine) {
    gSQLog = [NSMutableArray array]; gPrewarmQuitSet = [NSMutableArray array]; gSQPublishes = 0; gSQEngine = engine;
    gSQStages = [NSMutableArray array]; gSQRunning = [NSMutableSet set]; gSQLaunched = [NSMutableArray array]; gSQClosed = [NSMutableArray array];
    gLastWindowFrames = nil; gSQSaves = gSQOffMain = 0; gSQKeptForget = [NSMutableArray array];
    gMSWWinDesk = [NSMutableDictionary dictionary]; gMSWQuitting = nil; gMSWRelaunching = nil;
    gMSWWinFrame = [NSMutableDictionary dictionary]; gMSWFullScreen = [NSMutableDictionary dictionary];
    gMSWWinShots = [NSMutableDictionary dictionary]; gMSWFit = [NSMutableDictionary dictionary];
    gSQCur = 1; gMSWDesks = [@[@1, @2] mutableCopy]; gMSWAsideDesk = [NSMutableDictionary dictionary]; gMSWAwayCount = 0; gMSWDesksDirty = NO;
    // Notes's window on Desktop 1 (on screen); Clock's and Maps's on Desktop 2, tiled there by Fit to Window, Clock in the left half
    gMSWWinDesk[kNotes] = @1; gMSWWinDesk[kClock] = @2; gMSWWinDesk[kMaps] = @2;
    gMSWWinFrame[kClock] = kClockFrame; gMSWWinFrame[kMaps] = @"{{683, 140}, {683, 520}}";
    gMSWWinShots[kClock] = [UIView new]; gMSWWinShots[kMaps] = [UIView new];
    gMSWFit[@"2"] = @{@"group": @[kClock, kMaps], @"slots": @{kClock: @"left", kMaps: @"right"}, @"free": @[], @"fitOn": @YES};
}
static UIView *stage(Class c, NSString *b, BOOL away) {
    UIView *v = [[c alloc] initWithFrame:CGRectMake(0, 0, 640, 520)];
    objc_setAssociatedObject(v, kSQBundleKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (away) { objc_setAssociatedObject(v, kMSWAwayKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); v.hidden = YES; }
    [gSQStages addObject:v];
    return v;
}
static SQProcess *proc(NSString *b) { SQProcess *p = [SQProcess new]; p.bundleIdentifier = b; return p; }
static void runFor(double s) { CFTimeInterval end = CACurrentMediaTime() + s; while (CACurrentMediaTime() < end) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false); }
static NSUInteger logCount(NSString *line) { NSUInteger n = 0; for (NSString *l in gSQLog) if ([l isEqualToString:line]) n++; return n; }
static NSString *const kForgotClock = @"[macswitcher] com.apple.mobiletimer force quit: its desktop record is forgotten";

int main(void) { @autoreleasepool {
    // 1. Aerial, Desktop 1 on screen. The App Switcher's swipe-up quits Clock: SpringBoard's kill with reason 1 ("killed from app switcher") passes
    //    the hook on the main thread; Aerial then takes Clock's window away. Then the user switches to Desktop 2.
    reset(DMEngineAerial);
    stage([UIView class], kNotes, NO); stage([UIView class], kMaps, YES);
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    printf("-- Aerial: Clock's window on Desktop 2, Clock quit with the App Switcher's swipe-up while Desktop 1 is on screen\n");
    ok([gPrewarmQuitSet isEqualToArray:@[kClock]] && gSQPublishes == 1,
       [NSString stringWithFormat:@"unchanged: Clock goes on the prewarm quit set (set: %@)", J(gPrewarmQuitSet)]);
    ok(!gMSWWinDesk[kClock] && !gMSWWinFrame[kClock] && !gMSWWinShots[kClock] && [gMSWWinDesk[kNotes] isEqual:@1] && [gMSWWinDesk[kMaps] isEqual:@2] && gMSWWinFrame[kMaps] && gMSWWinShots[kMaps],
       [NSString stringWithFormat:@"Clock's desktop record, place and picture are forgotten; Notes's and Maps's stay (records: %@)", J([gMSWWinDesk.allKeys sortedArrayUsingSelector:@selector(compare:)])]);
    NSDictionary *fit2 = gMSWFit[@"2"];
    ok([fit2[@"group"] isEqual:@[kMaps]] && !fit2[@"slots"][kClock] && fit2[@"slots"][kMaps],
       [NSString stringWithFormat:@"Desktop 2's Fit to Window arrangement no longer has Clock; Maps keeps a tile (group: %@)", J(fit2[@"group"])]);
    ok(gMSWQuitting[kClock] != nil && gSQSaves == 1 && logCount(kForgotClock) == 1,
       [NSString stringWithFormat:@"as after our Force Quit: the quitting mark (a dying window still in the engine's layer stays away), the records saved once, the log line (saves: %d)", gSQSaves]);
    gSQCur = 2;   // (Desktop 2 comes: Clock has no window, Aerial took it away with its app)
    DMMSWRelaunchClosed();
    runFor(0.6);
    ok(gSQLaunched.count == 0, [NSString stringWithFormat:@"Desktop 2 comes: Clock is not opened again (opened: %@)", J(gSQLaunched)]);

    // 2. Unchanged: a kill for another reason (iPadOS ending the app, a crash, a relaunch) is no user quit: the record stays and the app opens again
    //    at its place when its desktop comes
    reset(DMEngineAerial);
    stage([UIView class], kNotes, NO); stage([UIView class], kMaps, YES);
    DMPrewarmQuitAddFromKill(proc(kClock), 0); DMPrewarmQuitAddFromKill(proc(kClock), 2); DMPrewarmQuitAddFromKill(proc(kClock), 5);
    runFor(0.1);
    printf("-- unchanged: Clock ended for another reason than the user's quit (0, 2, 5)\n");
    ok(gPrewarmQuitSet.count == 0 && [gMSWWinDesk[kClock] isEqual:@2] && [gMSWWinFrame[kClock] isEqual:kClockFrame] && [gMSWFit[@"2"][@"group"] isEqual:(@[kClock, kMaps])] && !gMSWQuitting && gSQSaves == 0,
       [NSString stringWithFormat:@"nothing is recorded or forgotten: not on the quit set, Clock's record, place and tile stay (records: %@)", J([gMSWWinDesk.allKeys sortedArrayUsingSelector:@selector(compare:)])]);
    gSQCur = 2;
    DMMSWRelaunchClosed();
    ok([gSQLaunched isEqualToArray:@[[NSString stringWithFormat:@"tile %@ %@", kClock, NSStringFromCGRect(CGRectFromString(kClockFrame))]]],
       [NSString stringWithFormat:@"Desktop 2 comes: Clock opens again as a window at its place, as before (opened: %@)", J(gSQLaunched)]);

    // 3. FrontBoard's own queue: the kill hook may run there; the records are only ever changed on the main thread
    reset(DMEngineAerial);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ DMPrewarmQuitAddFromKill(proc(kClock), 1); dispatch_semaphore_signal(done); });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    BOOL before = [gMSWWinDesk[kClock] isEqual:@2];
    runFor(0.2);
    printf("-- the kill on FrontBoard's queue (not the main thread)\n");
    ok(before && !gMSWWinDesk[kClock] && gSQSaves == 1 && gSQOffMain == 0 && [gPrewarmQuitSet isEqualToArray:@[kClock]],
       [NSString stringWithFormat:@"Clock's record is forgotten on the main thread, once it runs (kept until then: %@; saves: %d; off the main thread: %d)", before ? @"yes" : @"no", gSQSaves, gSQOffMain]);

    // 4. Clock was already on the quit set (quit before, never opened by the user since): DMPrewarmQuitAdd returns early, the forget still runs
    reset(DMEngineAerial);
    [gPrewarmQuitSet addObjectsFromArray:@[kClock, kNotes]];
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    printf("-- Clock already on the prewarm quit set\n");
    ok([gPrewarmQuitSet isEqualToArray:(@[kNotes, kClock])] && gSQPublishes == 0 && !gMSWWinDesk[kClock] && gSQSaves == 1,
       [NSString stringWithFormat:@"the set only moves Clock last (not published again), and Clock's desktop record is still forgotten (set: %@; records: %@)", J(gPrewarmQuitSet), J([gMSWWinDesk.allKeys sortedArrayUsingSelector:@selector(compare:)])]);

    // 5. Zetsu: the same quit, Zetsu takes its window away; Desktop 2 comes
    reset(DMEngineZetsu);
    stage([UIView class], kNotes, NO); stage([UIView class], kMaps, YES);
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    gSQCur = 2;
    DMMSWRelaunchClosed();
    runFor(0.1);
    printf("-- Zetsu: the same\n");
    ok(!gMSWWinDesk[kClock] && gSQLaunched.count == 0 && !gLastWindowFrames[kClock],
       [NSString stringWithFormat:@"Clock's record is forgotten and Desktop 2 does not open it again with Zetsu's launch (opened: %@)", J(gSQLaunched)]);

    // 6. MilkyWay4: MilkyWay keeps the window of a killed app, so Clock's grey window is still away on Desktop 2 after the quit. The quit closes it,
    //    with MilkyWay's own close, as our Force Quit does -- once the kill is through, not inside it. Then Desktop 2 comes.
    reset(DMEngineMilkyWay);
    stage([AXWindowView class], kNotes, NO); stage([AXWindowView class], kMaps, YES); stage([AXWindowView class], kClock, YES);
    [gSQRunning addObjectsFromArray:@[kNotes, kMaps]];
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    NSArray *closedInKill = [gSQClosed copy];
    runFor(0.1);
    printf("-- MilkyWay4: the same, Clock's grey window away on Desktop 2\n");
    ok(closedInKill.count == 0, [NSString stringWithFormat:@"MilkyWay's close is not run inside FrontBoard's kill (closed during it: %@)", J(closedInKill)]);
    ok([gSQClosed isEqualToArray:@[kClock]] && logCount(@"[macswitcher] com.apple.mobiletimer quit: its MilkyWay window on another desktop closes (no record keeps it away now)") == 1,
       [NSString stringWithFormat:@"right after it, Clock's grey window on Desktop 2 closes, once, as after our Force Quit; Notes's and Maps's stay (closed: %@)", J(gSQClosed)]);
    gSQCur = 2;
    DMMSWRelaunchClosed();
    runFor(0.6);
    ok(!gMSWWinDesk[kClock] && gSQLaunched.count == 0 && [gSQClosed isEqualToArray:@[kClock]],
       [NSString stringWithFormat:@"Desktop 2 comes: Clock is not opened again, nothing more closed (opened: %@; closed: %@)", J(gSQLaunched), J(gSQClosed)]);

    // 6b. MilkyWay4, the case of the review: the iPad locked right after the swipe, so MilkyWay's dead-window check (unlocked only) has not closed
    //     Clock's window when the 4 s quitting mark runs out; the tick then runs with Desktop 1 on screen
    reset(DMEngineMilkyWay);
    UIView *notesW1 = stage([AXWindowView class], kNotes, NO), *mapsW2 = stage([AXWindowView class], kMaps, YES);
    stage([AXWindowView class], kClock, YES);
    [gSQRunning addObjectsFromArray:@[kNotes, kMaps]];
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    runFor(0.1);
    DMMSWApply();   // (a tick within the 4 s)
    runFor(0.4);
    gMSWQuitting[kClock] = @(CACurrentMediaTime() - 0.01);   // (the 4 s have run out)
    DMMSWApply();
    printf("-- MilkyWay4: the tick after the quitting mark ran out, Desktop 1 on screen, MilkyWay's dead-window check not run (locked)\n");
    BOOL clockShown = NO; for (UIView *st in gSQStages) if ([DMStageBundle(st) isEqualToString:kClock] && (!st.hidden || ![objc_getAssociatedObject(st, kMSWAwayKey) boolValue])) clockShown = YES;
    ok(!clockShown && !gMSWWinDesk[kClock] && logCount(@"[macswitcher] com.apple.mobiletimer's window is back (its desktop is current)") == 0,
       [NSString stringWithFormat:@"no empty grey Clock window comes onto Desktop 1, and Clock gets no record there (record: %@; windows of Clock left: %lu)",
        gMSWWinDesk[kClock] ?: @"none", (unsigned long)[[gSQStages filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIView *v, id b) { return [DMStageBundle(v) isEqualToString:kClock]; }]] count]]);
    ok(!notesW1.hidden && [gMSWWinDesk[kNotes] isEqual:@1] && mapsW2.hidden && [objc_getAssociatedObject(mapsW2, kMSWAwayKey) boolValue] && [gMSWWinDesk[kMaps] isEqual:@2],
       @"unchanged: Notes's window stays on Desktop 1, Maps's stays away on Desktop 2");

    // 6c. MilkyWay4, unchanged: Clock's window on the desktop on screen is left to MilkyWay's dead-window check (about a second, as before), and a
    //     kill for another reason closes nothing
    reset(DMEngineMilkyWay);
    gMSWWinDesk[kClock] = @1;
    stage([AXWindowView class], kClock, NO); stage([AXWindowView class], kMaps, YES);
    DMPrewarmQuitAddFromKill(proc(kMaps), 0); DMPrewarmQuitAddFromKill(proc(kMaps), 5);
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    runFor(0.1);
    printf("-- MilkyWay4, unchanged: Clock's window on the desktop on screen; Maps (away) ended for another reason\n");
    ok(gSQClosed.count == 0 && !gMSWWinDesk[kClock] && [gMSWWinDesk[kMaps] isEqual:@2],
       [NSString stringWithFormat:@"nothing is closed by the quit or the other kills (closed: %@); Clock's record forgotten, Maps's kept", J(gSQClosed)]);

    // 6d. MilkyWay4: our own Force Quit closes Clock's away window itself (DMForceQuitBundle: forget, then MilkyWay's close), and its kill passes
    //     the hook while MilkyWay still animates that window out
    reset(DMEngineMilkyWay);
    UIView *clockW = stage([AXWindowView class], kClock, YES);
    DMMSWForgetApp(kClock);
    [(AXWindowView *)clockW closeButtonAction:nil];
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    runFor(0.1);
    printf("-- MilkyWay4: our own Force Quit, then its kill through the hook\n");
    ok([gSQClosed isEqualToArray:@[kClock]], [NSString stringWithFormat:@"the window is closed once, not a second time by the hook (closed: %@)", J(gSQClosed)]);

    // 7. Clock was full screen on Desktop 2 when the user left it (that desktop opens it full screen again when it comes): quit with the App Switcher
    reset(DMEngineAerial);
    [gMSWWinDesk removeObjectForKey:kClock]; [gMSWWinFrame removeObjectForKey:kClock]; [gMSWWinShots removeObjectForKey:kClock];
    gMSWFullScreen[@"2"] = kClock;
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    printf("-- Clock full screen on Desktop 2, quit with the App Switcher's swipe-up\n");
    ok(gMSWFullScreen.count == 0 && gSQSaves == 1, [NSString stringWithFormat:@"Desktop 2's full-screen record of Clock is forgotten: the desktop does not open it again (full-screen records left: %lu)", (unsigned long)gMSWFullScreen.count]);

    // 8. The Stage Manager engine, windows told apart (each record by its window's key): the App Switcher closes Safari's last window and quits it
    reset(DMEngineNone);
    NSString *safA = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-6F1C2D3E-0A1B-4C5D-8E9F-AAAAAAAAAAAA";
    NSString *safB = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-9B8A7C6D-1E2F-4A3B-9C8D-BBBBBBBBBBBB";
    NSString *notesW = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default";
    gMSWWinDesk = [@{safA: @2, safB: @1, notesW: @1} mutableCopy]; gMSWWinFrame = [NSMutableDictionary dictionary]; gMSWFit = [NSMutableDictionary dictionary];
    DMPrewarmQuitAddFromKill(proc(@"com.apple.mobilesafari"), 1);
    printf("-- Stage Manager engine: Safari quit with the App Switcher\n");
    ok(gMSWWinDesk.count == 1 && gMSWWinDesk[notesW], [NSString stringWithFormat:@"every Safari window's record goes, as after our Force Quit; Notes's stays (records: %@)", J(gMSWWinDesk.allKeys)]);

    // 9. The Mac Switcher off: the desktops it keeps for when it is on again are told too, as after our Force Quit
    reset(DMEngineAerial);
    gMSWWinDesk = [NSMutableDictionary dictionary]; gMSWWinFrame = [NSMutableDictionary dictionary]; gMSWWinShots = [NSMutableDictionary dictionary]; gMSWFit = [NSMutableDictionary dictionary];
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    printf("-- the Mac Switcher off\n");
    ok([gSQKeptForget isEqualToArray:@[kClock]] && gSQSaves == 0,
       [NSString stringWithFormat:@"Clock goes out of the kept desktops (DMMSWKeptForget asked for: %@); nothing live to save", J(gSQKeptForget)]);

    // 10. Unchanged: our own Force Quit forgets first (DMForceQuitBundle, before it closes the window); its kill passes the hook afterwards
    reset(DMEngineAerial);
    DMMSWForgetApp(kClock);
    DMPrewarmQuitAddFromKill(proc(kClock), 1);
    printf("-- our own Force Quit, then its kill through the hook\n");
    ok(!gMSWWinDesk[kClock] && gSQSaves == 1 && logCount(kForgotClock) == 1 && [gPrewarmQuitSet isEqualToArray:@[kClock]] && [gMSWFit[@"2"][@"group"] isEqual:@[kMaps]],
       [NSString stringWithFormat:@"the second forget finds nothing: saved once, logged once, Clock once on the quit set (saves: %d)", gSQSaves]);
    return gFails;
}}
