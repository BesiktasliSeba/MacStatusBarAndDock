// test-startupwatch.m -- the start-up watcher on the Lock Screen (1.8.7.4, audit O2 of 1.8.7.2). After a boot or a respring the watcher looks for the
// status bar every frame and lays it out the moment its stock items exist. On the Lock Screen the bar has no clock, so the clock layout's logo never
// came and the watcher laid the copy out again every frame for all of its 12 s (720 layouts at 60 Hz, 1440 at 120 Hz). Now a copy laid out the Lock
// Screen's way with its status icons there is dressed: released, and the watcher stops. Everything else as before: an empty copy, a copy still being
// built while unlocked, the clock layout, nothing found for 12 s, and DMEnsureLogo's once-a-second look that puts the clock in at an unlock even with
// no other layout pass.
// The real code is cut out of statusbar/StatusBar.x by test-startupwatch.sh: DMHoldStatusBarCopy, DMReleaseStatusBarCopy, DMFindForegroundView, the
// fix's DMStartupLockScreenDressed (none before the fix), the watcher (DMStartupWatcher, DMStartStartupWatcher) and DMEnsureLogo (startupwatch-real.inc),
// and the Lock Screen branch of the copy's layout, -dm_layoutLogoBody's no-clock part (startupwatch-noclock.inc). Stand-ins: UIKit's views, the display
// link, the clock layout's marks, the lock state, and dispatch_after / dispatch_async on the test's own clock. iOS's own layout passes are left out
// (none comes by itself here): the copy's alpha after the watcher's frame is what the watcher left.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- the test's clock and main queue ----
static double gNow = 0;
static int gCaller;           // (whose layout: 0 the watcher, 1 the main queue's work (DMEnsureLogo), 2 the copy's own pass)
static NSMutableArray *gQueue;   // @[@(at), block]
static void TAfter(double delay, dispatch_block_t b) { [gQueue addObject:@[@(gNow + delay), [b copy]]]; }
static void TRunDue(void) {
    for (;;) {
        NSUInteger best = NSNotFound; double at = 1e9;
        for (NSUInteger i = 0; i < gQueue.count; i++) { double a = [gQueue[i][0] doubleValue]; if (a <= gNow + 1e-9 && a < at) { at = a; best = i; } }
        if (best == NSNotFound) return;
        dispatch_block_t b = gQueue[best][1]; [gQueue removeObjectAtIndex:best];
        int was = gCaller; gCaller = 1; b(); gCaller = was;   // (the main queue's work: DMEnsureLogo's looks)
    }
}
#define dispatch_time(base, delta) ((dispatch_time_t)(delta))
#define dispatch_after(when, queue, blk) TAfter((double)(when) / 1e9, (blk))
#define dispatch_async(queue, blk) TAfter(0.0, (blk))

// ---- UIKit stand-ins ----
@class UIWindow;
@interface UIView : NSObject
@property (nonatomic) CGFloat alpha;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGRect bounds;
@property (nonatomic, strong) NSMutableArray<UIView *> *subs;
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic, weak) UIView *superview;
- (NSArray<UIView *> *)subviews;
@end
@implementation UIView
- (instancetype)init { if ((self = [super init])) { _alpha = 1.0; _subs = [NSMutableArray array]; } return self; }
- (NSArray<UIView *> *)subviews { return [_subs copy]; }
@end
@interface UIWindow : UIView
@end
@implementation UIWindow
@end
@interface UIStatusBarWindow : UIWindow   // (SpringBoard's status bar window: what the watcher looks for)
@end
@implementation UIStatusBarWindow
@end
@interface _UIStatusBarForegroundView : UIView   // (a status bar copy)
- (void)dm_layoutLogo;
@end
#define CADisplayLink TDisplayLink   // (macOS has a CADisplayLink of its own: the stand-in under another name, the real code's word for it kept)
@interface CADisplayLink : NSObject
@property (nonatomic) CFTimeInterval timestamp;
@property (nonatomic, strong) id target;
@property (nonatomic) SEL sel;
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)sel;
- (void)addToRunLoop:(NSRunLoop *)rl forMode:(NSRunLoopMode)mode;
- (void)invalidate;
@end
static int gLinksMade = 0, gLinksAdded = 0;
@implementation CADisplayLink
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)sel { CADisplayLink *l = [self new]; l.target = target; l.sel = sel; gLinksMade++; return l; }
- (void)addToRunLoop:(NSRunLoop *)rl forMode:(NSRunLoopMode)mode { (void)rl; (void)mode; gLinksAdded++; }
- (void)invalidate { _target = nil; }
@end

// ---- the scenario's world ----
static NSMutableArray<UIWindow *> *gWindows;
static _UIStatusBarForegroundView *gFG;
static UIView *gLeading, *gTimeLabel, *gTrailing;
static BOOL gLocked;          // (DMBarLockedNow: the Lock Screen up, as the layout's own test reads it)
static BOOL gClock;           // (the leading region has its time label)
static int gLayouts;          // (layouts of the copy: the watcher's, DMEnsureLogo's, its own pass's)
static int gLayoutsBy[3];     // (by gCaller)
static NSMutableArray<NSString *> *gLog;

static const void *kLogoKey = &kLogoKey;
static const void *kHoldKey = &kHoldKey;
static const void *kHoldWantAlphaKey = &kHoldWantAlphaKey;
static const void *kHoldGaveUpKey = &kHoldGaveUpKey;
static const void *kNoClockLayoutKey = &kNoClockLayoutKey;
static const void *kBarLaidOutLockedKey = &kBarLaidOutLockedKey;
static const void *kBarLookLockedKey = &kBarLookLockedKey;
static const void *kBarClosedUpKey = &kBarClosedUpKey;
static BOOL gDMHoldOwnAlpha = NO;
static int gSafetyChecks = 0;

static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }
static void DMSBDiagStep(NSString *s) { (void)s; }
static BOOL DMSBIs(NSString *name, const char *uikitName) { return [name isEqualToString:@(uikitName)]; }
static NSArray<UIWindow *> *DMAllWindows(void) { return gWindows; }
static BOOL DMBarCopyPooled(UIView *fg) { (void)fg; return NO; }
static BOOL DMBarCopyIsCCDuplicate(UIView *fg) { (void)fg; return NO; }
static BOOL DMSMEngine(void) { return NO; }
static BOOL DMSMInFullScreenCard(UIView *v) { (void)v; return NO; }
static void DMSMMainBarChanged(UIView *fg) { (void)fg; }
static void DMHoldSafetyCheck(UIView *fg, int checks) { (void)fg; (void)checks; gSafetyChecks++; }   // (its release 2 s later is iOS-side: left out)
static void DMStockVPNRecheck(UIView *fg) { (void)fg; }
static BOOL DMBarLockedNow(void) { return gLocked; }
static UIView *DMLeadingContainer(UIView *fg) { (void)fg; return gLeading; }
static UIView *DMFirstStringView(UIView *container) { return container && gClock ? gTimeLabel : nil; }
static UIView *DMTrailingContainer(UIView *fg) { (void)fg; return gTrailing; }
static void DMHideAppBarItemsOf(UIView *fg) { (void)fg; }
// (the real one closes the status icons up and answers whether it laid the copy out: whenever the copy has a status icons region)
static BOOL DMLayoutWithoutClock(UIView *fg) { return DMTrailingContainer(fg) != nil; }
// (Battery Percentage in Icon's part of the no-clock layout, BatteryMenu.h: the number in the icon -- nothing of the watcher's; test-battinsideone.sh)
static BOOL DMBattInsideBarOurs(UIView *fg) { (void)fg; return NO; }
static void DMBattInsideLockLayout(UIView *fg, BOOL wasOurs) { (void)fg; (void)wasOurs; }

#include "startupwatch-real.inc"

@implementation _UIStatusBarForegroundView
- (void)dm_layoutLogo {
    gLayouts++; gLayoutsBy[gCaller]++;
    UIView *fg = self;
    if (fg.bounds.size.width < 300.0) return;
#include "startupwatch-noclock.inc"
    // the clock layout (the rest of -dm_layoutLogoBody): its marks, as it sets them
    objc_setAssociatedObject(fg, kNoClockLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(fg, kBarClosedUpKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!objc_getAssociatedObject(fg, kLogoKey)) objc_setAssociatedObject(fg, kLogoKey, [UIView new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL locked = DMBarLockedNow();
    objc_setAssociatedObject(fg, kBarLaidOutLockedKey, @(locked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(fg, kBarLookLockedKey, @(locked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

// the copy's own layout pass (the -layoutSubviews hook): held, laid out, released when ours
static void TOwnPass(void) {
    int was = gCaller; gCaller = 2;
    DMHoldStatusBarCopy(gFG);
    [gFG dm_layoutLogo];
    if (objc_getAssociatedObject(gFG, kLogoKey) || objc_getAssociatedObject(gFG, kNoClockLayoutKey)) DMReleaseStatusBarCopy(gFG);
    gCaller = was;
}

// ---- scenarios ----
static int gFails = 0, gChecks = 0;
static void check(BOOL ok, NSString *what) {
    gChecks++;
    if (!ok) gFails++;
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
}
static void setIcons(BOOL on) {   // (iOS's status icons in the trailing region: battery, signal)
    for (UIView *v in gTrailing.subs) v.hidden = !on;
}
static void world(BOOL statusBar, BOOL trailingRegion, BOOL icons) {
    gWindows = [NSMutableArray array]; gQueue = [NSMutableArray array]; gLog = [NSMutableArray array];
    gLayouts = 0; gLayoutsBy[0] = gLayoutsBy[1] = gLayoutsBy[2] = 0; gCaller = 0; gSafetyChecks = 0; gNow = 0;
    gStartupLink = nil; gStartupBegan = 0.0;
    [gWindows addObject:[UIWindow new]];   // (another window first)
    gFG = [_UIStatusBarForegroundView new]; gFG.bounds = (CGRect){{0, 0}, {1024, 24}};
    gLeading = [UIView new]; gTimeLabel = [UIView new]; gTimeLabel.bounds = (CGRect){{0, 0}, {40, 16}};
    gTrailing = trailingRegion ? [UIView new] : nil;
    for (int i = 0; i < 2; i++) { UIView *icon = [UIView new]; icon.bounds = (CGRect){{0, 0}, {20, 12}}; [gTrailing.subs addObject:icon]; }
    setIcons(icons);
    if (statusBar) {
        UIStatusBarWindow *w = [UIStatusBarWindow new];
        UIView *host = [UIView new]; [w.subs addObject:host]; [host.subs addObject:gFG];
        gFG.window = w;
        [gWindows addObject:w];
    }
    TAfter(2.0, ^{ DMEnsureLogo(0); });   // (the constructor's DMEnsureLogo, 2 s after it; the watcher starts at once)
    DMStartStartupWatcher();
}
typedef void (^TEvent)(double t);
// frames from the watcher's start until `until`, at `hz`; `ev` runs before each frame (the world changes), `probe` after it
static void run(double hz, double until, TEvent ev, TEvent probe) {
    for (long i = 0;; i++) {
        double t = i / hz;
        if (t > until + 1e-9) break;
        gNow = t;
        if (ev) ev(t);
        TRunDue();
        if (gStartupLink && gStartupLink.target) {
            gStartupLink.timestamp = t + 100.0;   // (the display link's own clock: not zero at the start)
            gCaller = 0;
            ((void (*)(id, SEL, id))objc_msgSend)(gStartupLink.target, gStartupLink.sel, gStartupLink);
        }
        if (probe) probe(t);
    }
}
static BOOL held(void) { return [objc_getAssociatedObject(gFG, kHoldKey) boolValue]; }
static BOOL logHas(NSString *s) { for (NSString *l in gLog) if ([l containsString:s]) return YES; return NO; }
static NSString *startLine(void) { for (NSString *l in gLog) if ([l hasPrefix:@"[startup]"]) return l; return @"(none)"; }

int main(void) {
    @autoreleasepool {
        // 1. the Lock Screen after a boot or respring, its status icons there (60 Hz)
        {
            gLocked = YES; gClock = NO;
            world(YES, YES, YES);
            __block int afterFirst = -1; __block double shownAfterFirst = -1; __block BOOL heldAfterFirst = YES;
            run(60, 13.0, nil, ^(double t) { if (t == 0) { afterFirst = gStartupLink ? 1 : 0; shownAfterFirst = gFG.alpha; heldAfterFirst = held(); } });
            printf("-- 1. Lock Screen at the start, 60 Hz: the watcher laid the copy out %d time(s); %s\n", gLayoutsBy[0], startLine().UTF8String);
            check(gLayoutsBy[0] == 1, [NSString stringWithFormat:@"Lock Screen, 60 Hz: the watcher lays the copy out once, not every frame for 12 s (%d)", gLayoutsBy[0]]);
            check(afterFirst == 0, @"Lock Screen: the watcher stops at its first frame");
            check(shownAfterFirst == 1.0 && !heldAfterFirst, [NSString stringWithFormat:@"Lock Screen: the copy is shown when the watcher stops, released as its own layout pass releases it (alpha %.2f)", shownAfterFirst]);
            check(logHas(@"[startup] status bar laid out the Lock Screen's way (its clock comes at the unlock); watcher stopped 0.00 s"), @"Lock Screen: the log says the bar was laid out the Lock Screen's way at 0.00 s");
            check([objc_getAssociatedObject(gFG, kBarLookLockedKey) boolValue] && objc_getAssociatedObject(gFG, kNoClockLayoutKey) && !objc_getAssociatedObject(gFG, kLogoKey),
                  @"Lock Screen: the copy keeps the Lock Screen's layout (no clock, no logo)");
            check(gLayoutsBy[1] == 12, [NSString stringWithFormat:@"Lock Screen: DMEnsureLogo still looks once a second from 2 s (%d looks by 13 s)", gLayoutsBy[1]]);
        }
        // 2. the same at 120 Hz (ProMotion)
        {
            gLocked = YES; gClock = NO;
            world(YES, YES, YES);
            run(120, 13.0, nil, nil);
            printf("-- 2. Lock Screen at the start, 120 Hz: the watcher laid the copy out %d time(s)\n", gLayoutsBy[0]);
            check(gLayoutsBy[0] == 1, [NSString stringWithFormat:@"Lock Screen, 120 Hz: the watcher lays the copy out once (%d)", gLayoutsBy[0]]);
            check(gFG.alpha == 1.0 && !held(), @"Lock Screen, 120 Hz: the copy is shown");
        }
        // 3. the Lock Screen, the copy still empty: iOS fills the status icons 1.5 s after the start
        {
            gLocked = YES; gClock = NO;
            world(YES, YES, NO);
            __block BOOL runningAt1 = NO; __block int stopFrameLayouts = -1;
            run(60, 13.0, ^(double t) { if (t >= 1.5 - 1e-9) setIcons(YES); }, ^(double t) {
                if (fabs(t - 1.0) < 1e-6) runningAt1 = gStartupLink != nil;
                if (!gStartupLink && stopFrameLayouts < 0) stopFrameLayouts = gLayoutsBy[0];
            });
            printf("-- 3. Lock Screen, icons at 1.5 s: %d watcher layouts; %s\n", gLayoutsBy[0], startLine().UTF8String);
            check(runningAt1, @"Lock Screen, empty copy: the watcher still watches at 1.0 s (no status icon yet)");
            check(gLayoutsBy[0] == 91, [NSString stringWithFormat:@"Lock Screen, icons at 1.5 s: the watcher stops at the first frame with them (91 layouts: %d)", gLayoutsBy[0]]);
            check(gFG.alpha == 1.0 && !held(), @"Lock Screen, icons at 1.5 s: the copy is shown");
            check(logHas(@"Lock Screen's way (its clock comes at the unlock); watcher stopped 1.50 s"), @"Lock Screen, icons at 1.5 s: the log says 1.50 s");
        }
        // 4. a start onto the Home Screen (unlocked), the clock there at once: as before
        {
            gLocked = NO; gClock = YES;
            world(YES, YES, YES);
            run(60, 13.0, nil, nil);
            printf("-- 4. unlocked start, clock there: %d watcher layout(s); %s\n", gLayoutsBy[0], startLine().UTF8String);
            check(gLayoutsBy[0] == 1 && objc_getAssociatedObject(gFG, kLogoKey) && gFG.alpha == 1.0 && !held(), @"unlocked start: attached at the first frame and shown (as before)");
            check(logHas(@"[startup] status bar attached 0.00 s after the watcher started"), @"unlocked start: the log says attached (as before)");
            check(gLayoutsBy[1] == 1 && logHas(@"[ensure] logo present after 1 attempt(s)"), @"unlocked start: DMEnsureLogo finds the logo at its first look (as before)");
        }
        // 5. unlocked, the copy still being built: its clock comes 0.4 s after the start (as before: held while it waits, then attached)
        {
            gLocked = NO; gClock = NO;
            world(YES, YES, YES);
            __block double alphaAt02 = -1; __block BOOL runningAt02 = NO;
            run(60, 13.0, ^(double t) { if (t >= 0.4 - 1e-9) gClock = YES; }, ^(double t) { if (fabs(t - 0.2) < 1e-6) { alphaAt02 = gFG.alpha; runningAt02 = gStartupLink != nil; } });
            printf("-- 5. unlocked start, clock at 0.4 s: %d watcher layouts; %s\n", gLayoutsBy[0], startLine().UTF8String);
            check(runningAt02 && alphaAt02 == 0.0, @"unlocked, no clock yet: the watcher goes on and keeps the copy held (as before)");
            check(gLayoutsBy[0] == 25 && objc_getAssociatedObject(gFG, kLogoKey) && gFG.alpha == 1.0, [NSString stringWithFormat:@"unlocked, clock at 0.4 s: attached at that frame (25 layouts: %d), shown (as before)", gLayoutsBy[0]]);
            check(logHas(@"[startup] status bar attached 0.40 s"), @"unlocked, clock at 0.4 s: the log says attached at 0.40 s (as before)");
        }
        // 6. iPadOS 17+ start on the Lock Screen: the lock managers made only 2 s after the start (DMBarLockedNow: not locked until then)
        {
            gLocked = NO; gClock = NO;
            world(YES, YES, YES);
            __block double alphaAt1 = -1;
            run(60, 13.0, ^(double t) { gLocked = t >= 2.0 - 1e-9; }, ^(double t) { if (fabs(t - 1.0) < 1e-6) alphaAt1 = gFG.alpha; });
            printf("-- 6. 17+ start, the Lock Screen known at 2 s: %d watcher layouts; %s\n", gLayoutsBy[0], startLine().UTF8String);
            check(alphaAt1 == 0.0, @"17+ start, lock not known yet: the copy is taken for one being built, held (as before)");
            check(gLayoutsBy[0] == 121, [NSString stringWithFormat:@"17+ start: the watcher stops at the first frame that knows the Lock Screen (121 layouts: %d)", gLayoutsBy[0]]);
            check(gFG.alpha == 1.0 && !held(), @"17+ start: the copy is shown once laid out the Lock Screen's way");
        }
        // 7. no status bar at all for 13 s: the watcher gives up after 12 s (as before)
        {
            gLocked = YES; gClock = NO;
            world(NO, YES, YES);
            __block double stoppedAt = -1;
            run(60, 13.0, nil, ^(double t) { if (!gStartupLink && stoppedAt < 0) stoppedAt = t; });
            printf("-- 7. no status bar: stopped at %.3f s; %s\n", stoppedAt, startLine().UTF8String);
            check(gLayouts == 0 && stoppedAt > 12.0 && stoppedAt < 12.02 && logHas(@"[startup] status bar NOT found; watcher stopped 12.0"), @"no status bar: the watcher gives up after 12 s, NOT found (as before)");
        }
        // 8. the Lock Screen, unlocked 5.5 s after the start (the clock comes with it), and no other layout pass at all (the worst case: on the iPad the
        //    unlock lays the bar out itself, iOS's own pass on 15/16, DMBarCoverLeaving / DMRelayoutUnattachedBars and the labels' attach on 17+)
        {
            gLocked = YES; gClock = NO;
            world(YES, YES, YES);
            __block double logoAt = -1;
            run(60, 13.0, ^(double t) { if (t >= 5.5 - 1e-9) { gLocked = NO; gClock = YES; } }, ^(double t) { if (logoAt < 0 && objc_getAssociatedObject(gFG, kLogoKey)) logoAt = t; });
            printf("-- 8. Lock Screen, unlock at 5.5 s, no unlock pass: logo at %.3f s (watcher %d, DMEnsureLogo %d layouts)\n", logoAt, gLayoutsBy[0], gLayoutsBy[1]);
            check(logoAt >= 5.5 - 1e-9 && logoAt <= 6.5 + 1e-9 && gFG.alpha == 1.0 && !held(), [NSString stringWithFormat:@"unlock at 5.5 s with no unlock pass: the clock layout comes within 1 s, shown (%.2f s)", logoAt]);
            check(logHas(@"[ensure] logo present"), @"unlock at 5.5 s: DMEnsureLogo stops once the logo is there");
        }
        // 9. its own pass laid the copy out the Lock Screen's way before the watcher's first frame; then the unlock, and the clock 0.3 s after it (18.5's
        //    gap): unlocked without a clock it keeps the locked look -- not the Lock Screen's layout, so the watcher goes on and attaches the clock
        {
            gLocked = YES; gClock = NO;
            world(YES, YES, YES);
            TOwnPass();
            gLocked = NO;
            __block BOOL runningAt02 = NO;
            run(60, 13.0, ^(double t) { if (t >= 0.3 - 1e-9) gClock = YES; }, ^(double t) { if (fabs(t - 0.2) < 1e-6) runningAt02 = gStartupLink != nil; });
            printf("-- 9. unlocked before the first frame, clock at 0.3 s: %d watcher layouts; %s\n", gLayoutsBy[0], startLine().UTF8String);
            check(runningAt02, @"unlocked, the locked look kept until the clock: the watcher goes on (not the Lock Screen's layout)");
            check(gLayoutsBy[0] == 19 && logHas(@"[startup] status bar attached 0.30 s"), [NSString stringWithFormat:@"unlocked, clock at 0.3 s: attached at that frame (19 layouts: %d, as before)", gLayoutsBy[0]]);
        }
        // 10. the Lock Screen, the copy without its status icons region for 0.5 s: watched on, then dressed
        {
            gLocked = YES; gClock = NO;
            world(YES, NO, YES);
            UIView *region = [UIView new];
            for (int i = 0; i < 2; i++) { UIView *icon = [UIView new]; icon.bounds = (CGRect){{0, 0}, {20, 12}}; [region.subs addObject:icon]; }
            run(60, 13.0, ^(double t) { if (t >= 0.5 - 1e-9) gTrailing = region; }, nil);
            printf("-- 10. Lock Screen, status icons region at 0.5 s: %d watcher layouts; %s\n", gLayoutsBy[0], startLine().UTF8String);
            check(gLayoutsBy[0] == 31 && gFG.alpha == 1.0 && !held(), [NSString stringWithFormat:@"Lock Screen, no status icons region yet: watched on, stopped once it is laid out with it (31 layouts: %d)", gLayoutsBy[0]]);
        }
        // 11. the watcher is made once
        check(gLinksMade == 10 && gLinksAdded == 10, [NSString stringWithFormat:@"one display link per start, added to the run loop (%d / %d for 10 starts)", gLinksMade, gLinksAdded]);
        printf("%d of %d checks pass\n", gChecks - gFails, gChecks);
    }
    return gFails;
}
