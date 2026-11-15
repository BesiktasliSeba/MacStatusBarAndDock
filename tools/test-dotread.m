// test-dotread.m -- the Dock's running dots read the running apps once per step of the main run loop, not once per icon (1.8.7.4, audit O5 of
// 1.8.7.2). Each Dock icon's layout (Dock.x's SBIconView layout hook: DMUpdateRunningIndicator) read the running set for itself: SpringBoard's
// running apps with their process states, MacStatusBar's windows away and on screen and our own apps -- 12-15 reads of the same answer when the Dock
// laid out its icons together (an app switch, a recents change, edit mode), twice per icon with a side Dock. Now the first layout of a step reads it,
// the others use that read, and it is forgotten at the run loop's next activity (before the commit lays out, after a sleep, before the next pass
// over timers and sources); the 0.75 s poll (and a Dock Style change) always reads anew.
// The real code is dock/RunningIndicator.m from its first declaration to its end (dotread-real.inc, cut by test-dotread.sh), run on the Mac (Mac
// Catalyst: UIKit's real views and the real main run loop). Stand-ins: SpringBoard's running apps and their process states (each read counted),
// MacStatusBar's window sets (found with dlsym as on the iPad; each ask counted), the Dock's window, platter and icon views, a Home Screen icon, the
// settings and Lynx, and the commit's layout pass (a run-loop observer before the run loop waits, at Core Animation's commit order 2000000, laying
// out the icons marked for layout).
//   t <scenario>          one scenario (exit code: its failed checks); t list: the scenarios
//   t trace <seed> <n>    n random worlds, one line per look at the dots (for the .sh to compare with the code before the fix)
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#include <dlfcn.h>
#include "../common/DockSide.h"
#include "../dock/RunningDotRule.h"

// ---- the real file's other headers, as far as it uses them
#define DMLog(...) do { (void)(__VA_ARGS__); } while (0)
typedef NS_ENUM(int, MSBDDuplicate) { kMSBDDupDockIndicators = 6 };
static NSString *gTLynx;   // Lynx 2 drawing its own Dock indicators (OtherTweaks.h): ours step aside
static NSString *MSBDOtherTweakDoing(MSBDDuplicate what, BOOL inProcess) { return what == kMSBDDupDockIndicators ? gTLynx : nil; }
static id gTSwitch;   // Settings > Dock > Running indicators ("enabled" in com.besiktasliseba.dockrunningindicator; nil: never set)
static CFPropertyListRef TCopyValue(CFStringRef key, CFStringRef domain) {
    BOOL ours = [(__bridge NSString *)domain isEqualToString:@"com.besiktasliseba.dockrunningindicator"] && [(__bridge NSString *)key isEqualToString:@"enabled"];
    return ours && gTSwitch ? CFBridgingRetain(gTSwitch) : NULL;
}
#define CFPreferencesCopyValue(k, d, u, h) TCopyValue((k), (d))
#define CFPreferencesAppSynchronize(d) ((void)(d))
// Dock.x's turn of a side Dock's icons and DockStyle.m's dot: the bottom Dock, the Default style
int MSBDDockSideIconTurnSide(UIView *icon) { return 0; }
void DMDockStyleDot(UIView *dot, UIView *iconView, CGFloat d) {}

// ---- SpringBoard: the running applications and their process states
@interface TState : NSObject
@property (nonatomic) int pid;
@property (nonatomic) bool foreground;
- (bool)isForeground;
@end
@implementation TState
- (bool)isForeground { return _foreground; }
@end
@interface TApp : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, strong) TState *state;   // (nil: SpringBoard gives no process state)
- (id)processState;
@end
@implementation TApp
- (id)processState { return _state; }
@end
static NSMutableArray<TApp *> *gTApps;
static int gTReads, gTAsks;   // reads of the running apps (-runningApplications: one per read of the set); MacStatusBar's sets asked
@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (NSArray *)runningApplications;
@end
@implementation SBApplicationController
+ (instancetype)sharedInstance { static SBApplicationController *s; if (!s) s = [SBApplicationController new]; return s; }
- (NSArray *)runningApplications { gTReads++; return [gTApps copy]; }
@end
// MacStatusBar's sets (StatusBar.x, ActMonDock.h; the real code finds them with dlsym)
static NSSet<NSString *> *gTAway, *gTShown, *gTOwn;
__attribute__((visibility("default"))) NSSet<NSString *> *MSBDAppsWithWindowsAway(void) { gTAsks++; return gTAway; }
__attribute__((visibility("default"))) NSSet<NSString *> *MSBDAppsWithWindows(void) { gTAsks++; return gTShown; }
__attribute__((visibility("default"))) NSSet<NSString *> *MSBDOwnAppsRunning(void) { gTAsks++; return gTOwn; }

// ---- the Dock's views (by their class names, as the real code finds them)
@interface SBFloatingDockWindow : UIView
@end
@implementation SBFloatingDockWindow
@end
@interface SBFloatingDockPlatterView : UIView
@end
@implementation SBFloatingDockPlatterView
@end
@interface TAppIcon : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation TAppIcon
@end
@interface TFolderIcon : NSObject   // (a folder in the Dock: no app)
@end
@implementation TFolderIcon
@end
@interface SBIconView : UIView
@property (nonatomic, strong) id icon;
@end
@implementation SBIconView
@end

#include "dotread-real.inc"   // (the real dock/RunningIndicator.m, from @interface UIWindow (DMPrivate) to its end)

static NSArray *gTWindows;   // what +[UIWindow allWindowsIncludingInternalWindows:onlyVisibleWindows:] gives: the Dock's window, a Home Screen page's
static NSArray *TAllWindows(id self, SEL _cmd, BOOL internal, BOOL visible) { return gTWindows; }

// ---- the world: a Dock of 12 apps, a folder and Activity Monitor; an app's icon on a Home Screen page
static SBFloatingDockWindow *gTDockWindow;
static NSMutableArray<SBIconView *> *gTIcons;
static SBIconView *gTHome;
static NSMutableOrderedSet<SBIconView *> *gTMarked;   // icons marked for layout (the commit lays them out)
static NSMutableSet<SBIconView *> *gTTurned;          // icons whose layout first places the dot for a side turn applied anew (Dock.x DMDockSideDotFollows)
static int gTCommits, gTActivities;
#define kTActMon @"com.besiktasliseba.macstatusbar.activitymonitor"
static NSString *TB(int i) { return [NSString stringWithFormat:@"com.example.app%d", i]; }
static int gTNextPid = 100;
static TApp *TFind(NSString *b) { for (TApp *a in gTApps) if ([a.bundleIdentifier isEqualToString:b]) return a; return nil; }
static TApp *TLaunch(NSString *b, bool fg) {   // (a new process: a new pid)
    TApp *a = TFind(b);
    if (!a) { a = [TApp new]; a.bundleIdentifier = b; [gTApps addObject:a]; }
    a.state = [TState new]; a.state.pid = gTNextPid++; a.state.foreground = fg;
    return a;
}
static void TQuit(NSString *b) { TApp *a = TFind(b); if (a) [gTApps removeObject:a]; }
static void TFront(NSString *b, bool fg) { TState *s = TFind(b).state; if (!s) return; TState *n = [TState new]; n.pid = s.pid; n.foreground = fg; TFind(b).state = n; }

static void TWorld(void) {
    gTDockWindow = [[SBFloatingDockWindow alloc] initWithFrame:CGRectMake(0, 900, 1366, 124)];
    SBFloatingDockPlatterView *platter = [[SBFloatingDockPlatterView alloc] initWithFrame:CGRectMake(60, 10, 1246, 100)];
    [gTDockWindow addSubview:platter];
    UIView *list = [[UIView alloc] initWithFrame:platter.bounds];   // (the Dock's icon list view)
    [platter addSubview:list];
    gTIcons = [NSMutableArray array];
    for (int i = 0; i < 14; i++) {
        SBIconView *v = [[SBIconView alloc] initWithFrame:CGRectMake(10 + i * 86, 12, 76, 76)];
        if (i < 12) { TAppIcon *ic = [TAppIcon new]; ic.bundleIdentifier = TB(i); v.icon = ic; }
        else if (i == 12) v.icon = [TFolderIcon new];
        else { TAppIcon *ic = [TAppIcon new]; ic.bundleIdentifier = kTActMon; v.icon = ic; }
        [list addSubview:v]; [gTIcons addObject:v];
    }
    UIView *page = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 900)];
    gTHome = [[SBIconView alloc] initWithFrame:CGRectMake(100, 100, 76, 76)];
    TAppIcon *hi = [TAppIcon new]; hi.bundleIdentifier = TB(0); gTHome.icon = hi;
    [page addSubview:gTHome];
    gTWindows = @[gTDockWindow, page];
    gTMarked = [NSMutableOrderedSet orderedSet]; gTTurned = [NSMutableSet set];
    gTApps = [NSMutableArray array]; gTAway = gTShown = gTOwn = nil;
    gTSwitch = nil; gTLynx = nil; gRIWanted = -1; [gRISeenPid removeAllObjects];
    gTReads = gTAsks = gTCommits = 0;
}
// app0 on screen; app1 started in the background (never on screen); app2 in the background with a window on another desktop; app3 without a
// process state; app4 not running, its window back on screen (the Stage Manager restore); app6 on screen; Activity Monitor's window open.
static void TBasicApps(void) {
    TLaunch(TB(0), true); TLaunch(TB(1), false); TLaunch(TB(2), false); TLaunch(TB(3), false).state = nil; TLaunch(TB(6), true);
    gTAway = [NSSet setWithObject:TB(2)]; gTShown = [NSSet setWithObject:TB(4)]; gTOwn = [NSSet setWithObject:kTActMon];
}
static BOOL TShown(UIView *v) { UIView *d = DMRunningDotOf(v); return d && !d.hidden; }
static NSString *TDot(UIView *v) {
    UIView *d = DMRunningDotOf(v);
    if (!d) return @"-";
    if (d.hidden) return @"h";
    return [NSString stringWithFormat:@"%.2f,%.2f,%.2f", d.frame.origin.x, d.frame.origin.y, d.frame.size.width];
}
static NSString *TDots(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (SBIconView *v in gTIcons) [a addObject:TDot(v)];
    [a addObject:TDot(gTHome)];
    return [a componentsJoinedByString:@" "];
}
static NSString *TSeen(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *b in [gRISeenPid.allKeys sortedArrayUsingSelector:@selector(compare:)]) [a addObject:[NSString stringWithFormat:@"%@=%@", [b substringFromIndex:12], gRISeenPid[b]]];
    return a.count ? [a componentsJoinedByString:@","] : @"none";
}
static void TLayout(SBIconView *v) {   // Dock.x's SBIconView layout hook
    if ([gTTurned containsObject:v]) DMUpdateRunningIndicator(v);   // (the turn's dot, when a side turn is applied anew)
    DMUpdateRunningIndicator(v);
}
static void TMarkAll(void) { for (SBIconView *v in gTIcons) [gTMarked addObject:v]; [gTMarked addObject:gTHome]; }

// ---- the run loop: the commit's layout pass, and steps each in a later turn of the run loop
static void TInstall(void) {
    CFRunLoopObserverRef commit = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopBeforeWaiting | kCFRunLoopExit, true, 2000000,
        ^(CFRunLoopObserverRef o, CFRunLoopActivity a) {
            if (!gTMarked.count) return;
            gTCommits++;
            NSArray *list = [gTMarked.array copy]; [gTMarked removeAllObjects];   // (-array is a live view of the set: a copy)
            for (SBIconView *v in list) TLayout(v);
        });
    CFRunLoopAddObserver(CFRunLoopGetMain(), commit, kCFRunLoopCommonModes); CFRelease(commit);
    CFRunLoopObserverRef count = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAllActivities, true, 0,
        ^(CFRunLoopObserverRef o, CFRunLoopActivity a) { gTActivities++; });
    CFRunLoopAddObserver(CFRunLoopGetMain(), count, kCFRunLoopCommonModes); CFRelease(count);
}
typedef void (^TBody)(void);
static NSArray<TBody> *gTSteps;
static NSUInteger gTStep;
static CFStringRef gTAddMode;   // where the steps' timers and observers go (the common modes, or a mode of the test's own)
// A step: a timer due at once; its body runs in the timer, or puts its part elsewhere in the run loop and calls TDone() there.
static void TFire(void) {
    CFRunLoopTimerRef t = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), 0, 0, 0, ^(CFRunLoopTimerRef tm) {
        NSUInteger i = gTStep++;
        if (i >= gTSteps.count) { CFRunLoopStop(CFRunLoopGetMain()); return; }
        gTSteps[i]();
    });
    CFRunLoopAddTimer(CFRunLoopGetMain(), t, gTAddMode); CFRelease(t);
}
// The step is done: the next one is added at the run loop's next activity (so it runs in a later step of the run loop, as a later event does).
static void TDone(void) {
    CFRunLoopObserverRef o = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAllActivities, false, 0, ^(CFRunLoopObserverRef ob, CFRunLoopActivity a) { TFire(); });
    CFRunLoopAddObserver(CFRunLoopGetMain(), o, gTAddMode); CFRelease(o);
}
static void TRunIn(CFStringRef runMode, CFStringRef addMode, NSArray<TBody> *steps) {
    gTSteps = steps; gTStep = 0; gTAddMode = addMode;
    TFire();
    CFRunLoopRunInMode(runMode, 30, false);
    if (gTStep <= steps.count) printf("FAIL  the run loop ended before its last step (%lu of %lu)\n", (unsigned long)gTStep, (unsigned long)steps.count);
}
static void TRun(NSArray<TBody> *steps) { TRunIn(kCFRunLoopDefaultMode, kCFRunLoopCommonModes, steps); }
// The places of a run-loop step a body can run in, besides a timer: a block of the run loop's own (run right after the run loop's next
// "before sources" activity, so the next activity is "before waiting": the commit), a version 0 source (an event of UIKit's), the main queue.
static void TInBlock(TBody body) {   // (a block added from a timer runs right after it; that block adds the body, which runs in the next turn's blocks)
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, ^{ CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, body); });
}
static TBody gTSourceBody;
static CFRunLoopSourceRef gTSource;
static void TSourcePerform(void *info) { TBody b = gTSourceBody; gTSourceBody = nil; if (b) b(); }
static void TInSource(TBody body) {
    if (!gTSource) {
        CFRunLoopSourceContext c = {0}; c.perform = TSourcePerform;
        gTSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &c);
        CFRunLoopAddSource(CFRunLoopGetMain(), gTSource, kCFRunLoopCommonModes);
    }
    gTSourceBody = body; CFRunLoopSourceSignal(gTSource); CFRunLoopWakeUp(CFRunLoopGetMain());
}

// ---- the scenarios
static int gFails;
static void ok(BOOL c, NSString *what) { printf("%s  %s\n", c ? "PASS" : "FAIL", what.UTF8String); if (!c) gFails++; }
static NSString *TWhich(BOOL (^want)(int i)) {   // the Dock icons whose dot differs from what is wanted ("" when none)
    NSMutableArray *bad = [NSMutableArray array];
    for (int i = 0; i < 14; i++) if (TShown(gTIcons[i]) != want(i)) [bad addObject:@(i)];
    return [bad componentsJoinedByString:@","];
}
static BOOL TBasicWant(int i) { return i == 0 || i == 2 || i == 3 || i == 4 || i == 6 || i == 13; }

static void S_docklayout(void) {
    TWorld(); TBasicApps();
    __block int reads = -1, asks = -1, commits = -1;
    TRun(@[^{ TMarkAll(); TDone(); }, ^{ reads = gTReads; asks = gTAsks; commits = gTCommits; TDone(); }]);
    ok(commits == 1 && reads == 1, [NSString stringWithFormat:@"the Dock lays out its 14 icons in one commit: the running apps read once (%d; before: once per Dock icon, 14)", reads]);
    ok(asks == 3, [NSString stringWithFormat:@"  ... MacStatusBar's windows away, windows shown and own apps asked once each (%d asks; before: 42)", asks]);
    NSString *bad = TWhich(^BOOL(int i) { return TBasicWant(i); });
    ok(!bad.length, [NSString stringWithFormat:@"  ... every Dock icon's dot as the rule says (on screen, a window away, no process state, a window shown, Activity Monitor; not an app started in the background, not running, the folder)%@", bad.length ? [@": wrong at " stringByAppendingString:bad] : @""]);
    ok(!TShown(gTHome) && DMRunningDotOf(gTHome) == nil, @"  ... the Home Screen icon of a running app has no dot and was not read for (as before)");
}
static void S_sidedock(void) {
    TWorld(); TBasicApps();
    for (SBIconView *v in gTIcons) [gTTurned addObject:v];
    __block int reads = -1;
    TRun(@[^{ TMarkAll(); TDone(); }, ^{ reads = gTReads; TDone(); }]);
    ok(reads == 1, [NSString stringWithFormat:@"a side Dock's layout (each icon's dot placed for the turn, then the layout's): one read (%d; before: 28)", reads]);
    NSString *bad = TWhich(^BOOL(int i) { return TBasicWant(i); });
    ok(!bad.length, [NSString stringWithFormat:@"  ... every dot as the rule says%@", bad.length ? [@": wrong at " stringByAppendingString:bad] : @""]);
}
static void S_nextstep(void) {
    TWorld(); TBasicApps();
    __block int reads1 = -1, reads2 = -1;
    TRun(@[^{ TMarkAll(); TDone(); },
           ^{ reads1 = gTReads; TQuit(TB(0)); TLaunch(TB(7), true); TMarkAll(); TDone(); },
           ^{ reads2 = gTReads; TDone(); }]);
    ok(reads1 == 1 && reads2 == 2, [NSString stringWithFormat:@"the next Dock layout (after app0 quit and app7 opened) reads again: %d then %d", reads1, reads2]);
    ok(!TShown(gTIcons[0]) && TShown(gTIcons[7]), @"  ... app0's dot gone, app7's shown");
}
static void S_aftersleep(void) {
    TWorld(); TBasicApps();
    __block int before = -1, after = -1; __block BOOL shownAfter = YES;
    TRun(@[^{ TMarkAll(); TDone(); },   // (the commit reads, before the run loop waits)
           ^{ before = gTReads; TQuit(TB(0)); TLayout(gTIcons[0]); after = gTReads; shownAfter = TShown(gTIcons[0]); TDone(); }]);
    ok(after == before + 1 && !shownAfter, [NSString stringWithFormat:@"after the run loop slept, an event's own layout reads again: app0 quit, its dot gone (reads %d -> %d)", before, after]);
}
static void S_sourceevent(void) {
    TWorld(); TBasicApps();
    __block int before = -1, mid = -1, after = -1; __block BOOL shownAfter = YES;
    TRun(@[^{ TLayout(gTIcons[6]); before = gTReads;   // (a layout in a timer's event: read)
              TInSource(^{ mid = gTReads; TQuit(TB(0)); TLayout(gTIcons[0]); after = gTReads; shownAfter = TShown(gTIcons[0]); TDone(); }); },
           ^{ TDone(); }]);
    ok(before == 1 && mid == 1 && after == 2 && !shownAfter, [NSString stringWithFormat:@"a layout in the next event in the same turn (a version 0 source after a timer) reads again: app0 quit, its dot gone (reads %d, %d -> %d)", before, mid, after]);
}
static void S_commitafter(void) {
    TWorld(); TBasicApps();
    __block BOOL shownMid = NO; __block int r = -1, rEnd = -1;
    TRun(@[^{ TInBlock(^{ r = gTReads; TLayout(gTIcons[0]); shownMid = TShown(gTIcons[0]); TQuit(TB(0)); [gTMarked addObject:gTIcons[0]]; TDone(); }); },
           ^{ rEnd = gTReads; TDone(); }]);
    ok(shownMid && rEnd == r + 2 && !TShown(gTIcons[0]), [NSString stringWithFormat:@"a layout just before the run loop waits, then a change: the commit reads again before it lays out (app0's dot gone; reads %d -> %d)", r, rEnd]);
}
static void S_poll(void) {
    TWorld(); TBasicApps();
    __block int r0 = -1, r1 = -1, r2 = -1, r3 = -1; __block BOOL afterPoll = YES, afterLayout = YES;
    TRun(@[^{ TMarkAll(); TDone(); },
           ^{ r0 = gTReads; TLayout(gTIcons[0]); r1 = gTReads; TQuit(TB(0));
              RIResyncDock(); r2 = gTReads; afterPoll = TShown(gTIcons[0]);   // (the 0.75 s poll's pass)
              TLayout(gTIcons[0]); r3 = gTReads; afterLayout = TShown(gTIcons[0]); TDone(); }]);
    ok(r1 == r0 + 1 && r2 == r1 + 1 && !afterPoll, [NSString stringWithFormat:@"the poll reads anew in a step that has read already: app0 quit, its dot gone (reads %d -> %d -> %d)", r0, r1, r2]);
    ok(r3 == r2 && !afterLayout, [NSString stringWithFormat:@"  ... a layout after it in the step uses the poll's read, not the older one (reads %d -> %d; app0 %@)", r2, r3, afterLayout ? @"shown" : @"no dot"]);
}
static void S_switchoff(void) {
    TWorld(); TBasicApps();
    gTSwitch = @NO; gRIWanted = -1;
    __block int r1 = -1, r2 = -1, r3 = -1; __block NSString *on = nil;
    TRun(@[^{ TMarkAll(); TDone(); },
           ^{ r1 = gTReads; gTSwitch = nil; gTLynx = @"Lynx"; gRIWanted = -1; TMarkAll(); TDone(); },
           ^{ r2 = gTReads; gTLynx = nil; gTSwitch = @YES; gRIWanted = -1; RIResyncDock(); r3 = gTReads;   // (Settings' notice: the switch read again, one pass)
              on = TWhich(^BOOL(int i) { return TBasicWant(i); }); TDone(); }]);
    ok(r1 == 0 && r2 == 0, [NSString stringWithFormat:@"the switch off, or Lynx drawing its own dots: no read, no dot (reads %d, %d; as before)", r1, r2]);
    ok(r3 == 1 && !on.length, [NSString stringWithFormat:@"  ... switched on again: one pass, every dot as the rule says%@", on.length ? [@": wrong at " stringByAppendingString:on] : @""]);
}
static void S_home(void) {
    TWorld(); TBasicApps();
    __block int r = -1;
    TRun(@[^{ TLayout(gTHome); TLayout(gTHome); r = gTReads; TDone(); }]);
    ok(r == 0 && DMRunningDotOf(gTHome) == nil, @"a Home Screen icon's layout: no read, no dot (as before)");
}
static void S_ownmode(void) {
    TWorld(); TBasicApps();
    __block int r1 = -1, r2 = -1; __block BOOL shown1 = NO, shown2 = YES;
    CFStringRef mode = CFSTR("TestModeOfItsOwn");
    CFRunLoopSourceContext c = {0}; c.perform = TSourcePerform;   // (a source never signalled: a mode with none would end the run at once)
    CFRunLoopSourceRef idle = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &c);
    CFRunLoopAddSource(CFRunLoopGetMain(), idle, mode); CFRelease(idle);
    TRunIn(mode, mode, @[^{ TLayout(gTIcons[0]); r1 = gTReads; shown1 = TShown(gTIcons[0]); TDone(); },
                         ^{ TQuit(TB(0)); TLayout(gTIcons[0]); r2 = gTReads; shown2 = TShown(gTIcons[0]); TDone(); }]);
    ok(r1 == 1 && shown1 && r2 == 2 && !shown2, [NSString stringWithFormat:@"the run loop in a mode of its own (not a common one): the next event's layout reads again, app0's dot gone (reads %d -> %d)", r1, r2]);
}
static void S_seen(void) {
    TWorld(); TBasicApps();
    __block BOOL bg = YES, fg = NO, back = NO, again = YES;
    TRun(@[^{ TLaunch(TB(8), false); TMarkAll(); TDone(); },
           ^{ bg = TShown(gTIcons[8]); TFront(TB(8), true); TMarkAll(); TDone(); },
           ^{ fg = TShown(gTIcons[8]); TFront(TB(8), false); TMarkAll(); TDone(); },
           ^{ back = TShown(gTIcons[8]); TLaunch(TB(8), false); TMarkAll(); TDone(); },
           ^{ again = TShown(gTIcons[8]); TDone(); }]);
    ok(!bg && fg && back && !again, [NSString stringWithFormat:@"an app started in the background: no dot; on screen: dot; back in the background: dot kept; a new process in the background: none (as before: %d %d %d %d)", bg, fg, back, again]);
}
// The one difference, by the design the audit chose: two events in one step of the run loop (two main-queue blocks drained together, no activity
// between): the later one's own layout uses the step's read. A change it makes is shown by the commit when it marks the icon for layout (as a
// change does), else by the next poll.
static void S_samestep(void) {
    TWorld(); TBasicApps();
    __block int a1 = -1, a2 = -2, r1 = -1, r2 = -1; __block BOOL second = NO, polled = YES;
    TRun(@[^{ dispatch_async(dispatch_get_main_queue(), ^{ a1 = gTActivities; TLayout(gTIcons[0]); r1 = gTReads; });
              dispatch_async(dispatch_get_main_queue(), ^{ a2 = gTActivities; TQuit(TB(0)); TLayout(gTIcons[0]); r2 = gTReads; second = TShown(gTIcons[0]); TDone(); }); },
           ^{ RIResyncDock(); polled = TShown(gTIcons[0]); TDone(); }]);
    ok(a1 == a2, [NSString stringWithFormat:@"(premise) two main-queue blocks drained together: no run-loop activity between them (%d, %d)", a1, a2]);
    ok(r2 == r1 && second, [NSString stringWithFormat:@"by design: the second block's own layout in the same step uses the step's read (app0's dot still shown; reads %d -> %d)", r1, r2]);
    ok(!polled, @"  ... the next poll shows the change (app0's dot gone)");
}

// ---- random worlds, one line per look at the dots (the .sh compares them with the code before the fix)
static uint64_t gTRng;
static uint32_t TR(uint32_t n) { gTRng ^= gTRng << 13; gTRng ^= gTRng >> 7; gTRng ^= gTRng << 17; return n ? (uint32_t)(gTRng % n) : 0; }
static int gTW;
static NSSet *TRandomSet(int pct) { if (TR(100) < 20) return nil; NSMutableSet *s = [NSMutableSet set]; for (int i = 0; i < 12; i++) if (TR(100) < (uint32_t)pct) [s addObject:TB(i)]; return s; }
static void TLook(NSUInteger step, const char *tag) {
    printf("L w%d s%lu %s | %s | seen %s\n", gTW, (unsigned long)step, tag, TDots().UTF8String, TSeen().UTF8String);
}
static void TChange(void) {   // (0-3 changes: SpringBoard's apps, MacStatusBar's windows)
    for (uint32_t k = TR(4); k > 0; k--) {
        NSString *b = TB((int)TR(12));
        switch (TR(9)) {
            case 0: TLaunch(b, false); break;                                  // started in the background (or again: a new process)
            case 1: TLaunch(b, true); break;                                   // opened
            case 2: TQuit(b); break;
            case 3: TFront(b, true); break;
            case 4: TFront(b, false); break;
            case 5: if (TFind(b)) TFind(b).state = nil; break;                 // no process state
            case 6: gTAway = TRandomSet(15); break;
            case 7: gTShown = TRandomSet(10); break;
            default: gTOwn = TR(2) ? [NSSet setWithObject:kTActMon] : nil; break;
        }
    }
}
static TBody TRandomStep(NSUInteger i) {
    uint32_t kind = TR(100);
    if (kind < 12) return ^{ TLook(i, "start"); RIResyncDock(); TLook(i, "poll"); TDone(); };   // the 0.75 s poll
    if (kind < 16) {   // Settings' switch or Lynx changed: the notice reads the switch again and makes one pass
        uint32_t what = TR(4);
        return ^{ TLook(i, "start");
                  if (what == 0) gTSwitch = @NO; else if (what == 1) gTSwitch = @YES; else if (what == 2) gTSwitch = nil; else gTLynx = gTLynx ? nil : @"Lynx";
                  gRIWanted = -1; RIResyncDock(); TLook(i, "prefs"); TDone(); };
    }
    // an event: changes, then layouts of its own (some twice: a side turn), then icons marked for the commit
    uint32_t where = TR(4), nSync = TR(5), nMark = TR(16);
    NSMutableArray *sync = [NSMutableArray array], *mark = [NSMutableArray array];
    for (uint32_t k = 0; k < nSync; k++) [sync addObject:TR(8) ? gTIcons[TR(14)] : gTHome];
    for (uint32_t k = 0; k < nMark; k++) [mark addObject:TR(10) ? gTIcons[TR(14)] : gTHome];
    NSMutableSet *turned = [NSMutableSet set]; for (SBIconView *v in gTIcons) if (TR(100) < 25) [turned addObject:v];
    uint64_t changeSeed = gTRng;   // (the changes drawn when the body runs, from this seed: the same on both codes)
    gTRng ^= 0x9E3779B97F4A7C15ull; TR(1);
    TBody body = ^{
        TLook(i, "start");
        uint64_t keep = gTRng; gTRng = changeSeed; TChange(); gTRng = keep;
        [gTTurned setSet:turned];
        for (SBIconView *v in sync) TLayout(v);
        TLook(i, "event");
        for (SBIconView *v in mark) [gTMarked addObject:v];
        TDone();
    };
    switch (where) {
        case 0: return body;                                                   // in the timer
        case 1: return ^{ TInBlock(body); };                                   // in the run loop's blocks, just before it waits
        case 2: return ^{ TInSource(body); };                                  // a version 0 source
        default: return ^{ dispatch_async(dispatch_get_main_queue(), body); }; // the main queue
    }
}
static int TTrace(uint64_t seed, int worlds) {
    for (gTW = 0; gTW < worlds; gTW++) {
        gTRng = seed * 1000003ull + (uint64_t)gTW * 7919ull + 1;
        TWorld();
        for (int k = 0; k < 6; k++) { NSString *b = TB((int)TR(12)); TLaunch(b, TR(2)); }
        gTAway = TRandomSet(15); gTShown = TRandomSet(10); gTOwn = TR(2) ? [NSSet setWithObject:kTActMon] : nil;
        int nSteps = 30 + (int)TR(21);
        NSMutableArray *steps = [NSMutableArray array];
        for (int s = 0; s < nSteps; s++) [steps addObject:TRandomStep((NSUInteger)s)];
        [steps addObject:^{ TLook((NSUInteger)nSteps, "end"); TDone(); }];
        TRun(steps);
        printf("R w%d reads %d asks %d commits %d steps %d\n", gTW, gTReads, gTAsks, gTCommits, nSteps);
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        SEL all = @selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:);
        Method m = class_getClassMethod([UIWindow class], all);
        if (m) method_setImplementation(m, (IMP)TAllWindows); else class_addMethod(object_getClass([UIWindow class]), all, (IMP)TAllWindows, "@@:cc");
        if (!dlsym(RTLD_DEFAULT, "MSBDAppsWithWindowsAway") || !dlsym(RTLD_DEFAULT, "MSBDAppsWithWindows") || !dlsym(RTLD_DEFAULT, "MSBDOwnAppsRunning")) {
            printf("FAIL  the stand-ins for MacStatusBar's sets are not found with dlsym\n"); return 1;
        }
        TInstall();
        NSDictionary<NSString *, NSValue *> *scen = @{
            @"docklayout": [NSValue valueWithPointer:S_docklayout], @"sidedock": [NSValue valueWithPointer:S_sidedock],
            @"nextstep": [NSValue valueWithPointer:S_nextstep], @"aftersleep": [NSValue valueWithPointer:S_aftersleep],
            @"sourceevent": [NSValue valueWithPointer:S_sourceevent], @"commitafter": [NSValue valueWithPointer:S_commitafter],
            @"poll": [NSValue valueWithPointer:S_poll], @"switchoff": [NSValue valueWithPointer:S_switchoff], @"home": [NSValue valueWithPointer:S_home],
            @"ownmode": [NSValue valueWithPointer:S_ownmode], @"seen": [NSValue valueWithPointer:S_seen], @"samestep": [NSValue valueWithPointer:S_samestep],
        };
        NSArray *order = @[@"docklayout", @"sidedock", @"nextstep", @"aftersleep", @"sourceevent", @"commitafter", @"poll", @"switchoff", @"home",
                           @"ownmode", @"seen", @"samestep"];
        if (argc >= 2 && !strcmp(argv[1], "list")) { for (NSString *s in order) printf("%s\n", s.UTF8String); return 0; }
        if (argc >= 4 && !strcmp(argv[1], "trace")) return TTrace(strtoull(argv[2], NULL, 10), atoi(argv[3]));
        if (argc < 2 || !scen[@(argv[1])]) { printf("usage: t list | t <scenario> | t trace <seed> <n>\n"); return 2; }
        ((void (*)(void))[(NSValue *)scen[@(argv[1])] pointerValue])();
        return gFails;
    }
}
