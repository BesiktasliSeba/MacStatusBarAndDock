// test-nativehooks.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the native windows' hooks without Finder (1.8.7.4, audit M12 of 1.8.7.2).
// The touch and key hooks every native window needs (StatusBar.x's DMNativeHooks group, the scroll routing, Stage Manager's gesture filter) were
// installed by Finder's switch alone, but Activity Monitor and Display Settings are native windows that open with Finder off. Finder off at the
// start: Activity Monitor took SpringBoard's keyboard lock and nothing gave it back (typing in the app tapped next went nowhere), and Command-W,
// Command-M and Esc did nothing. Now the hooks go in the first time any native window comes on screen (-[DMNativeWindow show]), as before with
// Finder on; not while the crash guard has Finder off for a crash in that code (its note up, its record naming Finder's switch); and Finder
// switched off closes only Finder's own windows (its folders, Quick Look, TextEdit), none coming forward.
// Runs the real -[DMNativeWindow show], -close, DMNativeSetActive, DMNativeGuardTookFinder and DMNativeMayOpen (statusbar/NativeWindow.h),
// DMNativeSysGesturesInit, DMNativeHooksInit, DMNativeIsFinders and DMFinderApplyPref (statusbar/StatusBar.x; %init(<group>) made KInit(@"<group>")),
// DMActivityMonitorOpen (statusbar/ActivityMonitor.h), DMDispSettingsOpenIPad (statusbar/DisplaySettings.h) and MSBDGuardRecordNames
// (common/CrashGuard.h), cut out by test-nativehooks.sh into nh-methods.inc and nh-real.inc; the code before the fix lacks some of them. One
// scenario per process (the real code's install-once statics): `t <scenario>`, `t list`. SpringBoard's side is the stand-ins below; the keyboard
// lock's stand-in counts every lock taken while the hooks that give it back are not in (the M12 rule).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// ---- what the real code logs, and its debug-only and start-up switches
static NSMutableArray<NSString *> *gKLog;
static void KLog(NSString *s) { [gKLog addObject:s ?: @""]; }
#define DMLog(...) KLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name)
#define DMCtorSkip(step) 0

// ---- the hooks: a group's %init, the scroll routing, Finder's Dock icon
static NSCountedSet<NSString *> *gKInits;
static int gKScrollRouting, gKFinderDock;
static void KInit(NSString *group) { [gKInits addObject:group]; KLog([@"init " stringByAppendingString:group]); }
static void DMScrollRoutingInit(void) { gKScrollRouting++; }
static void DMFinderDockInit(void) { gKFinderDock++; }
@interface SBFluidSwitcherGestureManager : NSObject @end   // (SpringBoard's Stage Manager gestures: the class the filter's group needs)
@implementation SBFluidSwitcherGestureManager
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t { return YES; }
@end

// ---- Finder's switch and what follows it
static BOOL gKFinderPref;
static BOOL DMFinderPrefOn(void) { return gKFinderPref; }
static BOOL gFinderOn = NO;
static void DMDesktopApplyPref(void) {}
static void DMFinderSortChanged(void) {}
static void DMDockTrashApplyPref(void) {}

// ---- the crash guard: its note (crashGuardAction) and its record
#define MSBD_GATE_DOMAIN "com.besiktasliseba.test-nativehooks"
static const char *gKRecord = "/nonexistent/nh-record";
#define MSBD_GUARD_RECORD gKRecord
static int gKAction;
static int MSBDStepGuardAction(void) { return gKAction; }
static NSMutableArray<NSString *> *gKRecords;   // (removed at the end)
static void KRecord(NSString *text) {
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"nh-record-%d-%lu.txt", getpid(), (unsigned long)gKRecords.count]];
    [text writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [gKRecords addObject:p];
    gKRecord = strdup(p.fileSystemRepresentation);
}

// ---- the native windows (NativeWindow.h): the stand-ins around the real -show and -close
@interface DMNativeWindow : UIView
@property (nonatomic, copy) NSString *title, *appName;
@property (nonatomic, assign) CGSize minSize;
@property (nonatomic, assign) BOOL dm_wasMinimized;
@property (nonatomic, copy) void (^onClose)(DMNativeWindow *w);
@property (nonatomic, copy) void (^onActiveChanged)(DMNativeWindow *w, BOOL active);
@property (nonatomic, strong, readonly) UIView *contentView;
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame;
- (CGAffineTransform)dm_transformToRect:(CGRect)r;
- (void)show; - (void)close;
@end
static NSMutableArray<DMNativeWindow *> *gNativeWindows;   // front last
static DMNativeWindow *gNativeActive;
static NSString *gNativeFrontAtActivation;
static CFTimeInterval gNativeActivatedAt;
static UIWindow *gNativeLayer;   // (none: the layer's own calls go to nil)
static UIView *gNativeKeys;
static const CGFloat kNWTitleH = 30.0;
static UIView *gKHost;
static UIView *DMNativeHost(void) { return gKHost; }
static void DMNativeUpdateRotation(void) {}
static CGRect DMNativeClamp(CGRect f, CGSize minSize) { return f; }
static CGRect DMNativeDockTarget(void) { return CGRectNull; }
static UIView *gNativeRotator;   // (none here: a window back from the Recent Windows Strip grows out of the Dock target as before)
static CGRect DMRStripNativeFlight(DMNativeWindow *w, BOOL into) { return CGRectNull; }   // (the Recent Windows Strip, 1.8.8.4: switched off here)
static BOOL MSBReduceMotion(void) { return YES; }
static void MSBAnimate(NSTimeInterval d, NSTimeInterval delay, CGFloat damping, UIViewAnimationOptions o, void (^a)(void), void (^c)(BOOL)) { if (a) a(); if (c) c(YES); }
static CGRect DMNativeDesktop(void) { return CGRectMake(0, 24, 1180, 760); }
// SpringBoard's keyboard lock (NativeWindow.h DMNativeFocus): the active native window holds it, none gives it back. The M12 rule: it is never
// taken while the hooks that give it back (a touch in an app, the window's keys) are not in.
static BOOL gKLock;
static int gKLockWithoutHooks;
static void DMNativeFocus(BOOL take) {
    if (take && !gKLock && ![gKInits countForObject:@"DMNativeHooks"]) { gKLockWithoutHooks++; KLog(@"keyboard lock WITHOUT the native windows' hooks"); }
    if (take != gKLock) KLog(take ? @"keyboard lock" : @"keyboard given back");
    gKLock = take;
}
static void DMNativeTakeKeys(DMNativeWindow *w) { DMNativeFocus(YES); }   // (the real one's first line; the rest is the layer's first responder)
static void DMHomeFolderMovedOn(NSString *why) {}
static void DMDesktopYieldKeys(void) {}
static id DMActiveApp(void) { return nil; }
static void DMNativeApplyLevel(void) {}
static void DMNativeMenuBarChanged(void) {}
static void DMLightGroupsRefresh(void) {}
static void DMAMCmdTabAppsForward(void) {}
static void DMNativeHooksInit(void);
static void DMNativeSysGesturesInit(void);
static void DMNativeSetActive(DMNativeWindow *w);
static BOOL DMNativeIsFinders(DMNativeWindow *w);
static BOOL DMNativeMayOpen(NSString *what);
static BOOL DMNativeGuardTookFinder(void);
@implementation DMNativeWindow { UIView *_content; }
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _title = [title copy];
        _content = [[UIView alloc] initWithFrame:CGRectMake(0, kNWTitleH, frame.size.width, MAX(0.0, frame.size.height - kNWTitleH))];
        [self addSubview:_content];
    }
    return self;
}
- (UIView *)contentView { return _content; }
- (CGAffineTransform)dm_transformToRect:(CGRect)r { return CGAffineTransformIdentity; }
#include "nh-methods.inc"
@end
@interface DMFinderWindow : DMNativeWindow @end
@implementation DMFinderWindow @end
@interface DMQuickLookWindow : DMNativeWindow @end
@implementation DMQuickLookWindow @end
@interface DMTextWindow : DMNativeWindow @end
@implementation DMTextWindow @end
@interface DMActivityMonitorWindow : DMNativeWindow @end
@implementation DMActivityMonitorWindow
- (instancetype)initWithFrame:(CGRect)f { return [super initWithTitle:@"Activity Monitor" frame:f]; }
@end
@interface DMDispSettingsView : UIView
@property (nonatomic, copy) NSString *display;
- (instancetype)initWithDisplay:(NSString *)display;
- (CGFloat)dm_contentHeightForWidth:(CGFloat)width;
@end
@implementation DMDispSettingsView
- (instancetype)initWithDisplay:(NSString *)display { if ((self = [super initWithFrame:CGRectZero])) _display = [display copy]; return self; }
- (CGFloat)dm_contentHeightForWidth:(CGFloat)width { return 420.0; }
@end
@interface DMDispSettingsWindow : DMNativeWindow
@property (nonatomic, strong) DMDispSettingsView *settings;
@end
@implementation DMDispSettingsWindow @end
static DMDispSettingsWindow *gDMDispSettingsWindow;

#include "nh-real.inc"

// ---- the checks
static int gKFails;
static void check(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (!ok) gKFails++; }
static NSUInteger KHooks(void) { return [gKInits countForObject:@"DMNativeHooks"]; }
static BOOL KAllHooksOnce(void) { return KHooks() == 1 && gKScrollRouting == 1 && [gKInits countForObject:@"DMNativeSysGestures"] == 1; }
static BOOL KNoHooks(void) { return KHooks() == 0 && gKScrollRouting == 0 && [gKInits countForObject:@"DMNativeSysGestures"] == 0; }
static DMNativeWindow *KFind(Class c) { for (DMNativeWindow *w in gNativeWindows) if ([w isKindOfClass:c]) return w; return nil; }
static BOOL KLogged(NSString *part) { for (NSString *l in gKLog) if ([l containsString:part]) return YES; return NO; }
static void KFinder(BOOL on) { gKFinderPref = on; DMFinderApplyPref(); }
static DMNativeWindow *KOpen(Class c, NSString *title) { DMNativeWindow *w = [[c alloc] initWithTitle:title frame:CGRectMake(100, 100, 700, 450)]; [w show]; return w; }
#define AM [DMActivityMonitorWindow class]
#define DS [DMDispSettingsWindow class]
static NSString *const kFinderStep1b = @"time 1800000000\naction 4\ntested 1\nios 16.7.7\nbuild 1.8.7.3\nverdict 1\nblamed MacStatusBarCore\n"
    "feature com.besiktasliseba.macstatusbar finderEnabled 0 Finder|Finder\nframe MacStatusBarCore DMNativeTouchBegan + 120\n";

static void S_finderOffActivityMonitor(void) {
    KFinder(NO);
    check(KNoHooks() && gKFinderDock == 0, @"Finder off at the start: no native-window hooks and no Finder Dock icon yet (none until a native window opens, as before)");
    DMActivityMonitorOpen();
    DMNativeWindow *am = KFind(AM);
    check(am && gNativeActive == am && gKLock, @"Activity Monitor opens with Finder off, active, with the keyboard");
    check(KAllHooksOnce(), @"as it opens, the native windows' touch, key and scroll hooks and Stage Manager's gesture filter go in (before: Finder's switch only)");
    check(gKLockWithoutHooks == 0, @"the keyboard lock is never taken without the hooks that give it back (a tap in an app, Command-W, Esc)");
    check(gKFinderDock == 0 && !gFinderOn, @"Finder stays off: its Dock icon is not set up (Finder's own, not the native windows')");
    DMActivityMonitorOpen();
    check(KAllHooksOnce() && gNativeWindows.count == 1, @"opened again: the one window comes forward, nothing installed twice");
}
static void S_finderOffDisplaySettings(void) {
    KFinder(NO);
    DMDispSettingsOpenIPad(@"tv-1");
    DMNativeWindow *ds = KFind(DS);
    check(ds && gNativeActive == ds && gKLock, @"Display Settings opens on the iPad with Finder off, active, with the keyboard");
    check(KAllHooksOnce() && gKLockWithoutHooks == 0, @"with the native windows' hooks: Esc and Command-W reach it, a tap in an app gives the keyboard back");
}
static void S_finderOnAtStart(void) {
    KFinder(YES);
    check(KAllHooksOnce() && gNativeWindows.count == 0, @"Finder on at the start: the hooks at once, before any window (the desktop uses them), as before");
    check(gKFinderDock == 1 && gFinderOn, @"and Finder's Dock icon, as before");
    KOpen([DMFinderWindow class], @"Documents"); DMActivityMonitorOpen(); DMDispSettingsOpenIPad(@"tv-1");
    check(KAllHooksOnce() && gKFinderDock == 1 && gNativeWindows.count == 3, @"Finder, Activity Monitor and Display Settings opened after: nothing installed twice");
    check(gKLockWithoutHooks == 0, @"no keyboard lock without the hooks");
}
static void S_activityMonitorThenFinderOn(void) {
    KFinder(NO); DMActivityMonitorOpen();
    KFinder(YES);
    check(KAllHooksOnce() && gKFinderDock == 1 && gFinderOn, @"Finder switched on after Activity Monitor put the hooks in: Finder's Dock icon set up, the hooks not again");
    check(KFind(AM) != nil, @"Activity Monitor stays open");
}
static void S_finderOnOffOn(void) {
    KFinder(YES); KFinder(NO); KFinder(YES);
    check(KAllHooksOnce() && gKFinderDock == 1 && gFinderOn, @"Finder on, off, on: the hooks and its Dock icon once (as before)");
}
static void S_guardTookFinder(void) {
    gKAction = 4; KRecord(kFinderStep1b);
    KFinder(NO);
    DMActivityMonitorOpen(); DMDispSettingsOpenIPad(@"tv-1");
    check(gNativeWindows.count == 0 && !gNativeActive && !gKLock, @"the crash guard turned Finder off for a crash in the native windows' code (step 1b, note up): Activity Monitor and Display Settings do not open");
    check(KNoHooks(), @"and the code it took off stays off (a crash there again would find Finder's switch off and take the whole status bar)");
    check(KLogged(@"Activity Monitor not opened") && KLogged(@"Display Settings not opened"), @"the log says why");
    KFinder(YES);
    DMActivityMonitorOpen();
    check(KFind(AM) && KAllHooksOnce() && gKLockWithoutHooks == 0, @"Finder switched back on: Activity Monitor opens again, with the hooks (Finder's switch puts them in, as before)");
}
static void S_guardStep1(void) {
    gKAction = 1; KRecord(@"time 1800000000\naction 1\ntested 1\nios 15.6.1\nbuild 1.8.7.3\nverdict 1\nblamed MacStatusBarCore\nswitch com.besiktasliseba.macstatusbar finderEnabled Finder\n");
    KFinder(NO);
    DMActivityMonitorOpen();
    check(!KFind(AM) && KNoHooks() && !gKLock, @"the guard's step 1 turned Finder off (switched on just before the crashes): Activity Monitor does not open either");
}
static void S_guardNoteCleared(void) {
    gKAction = 0; KRecord(kFinderStep1b);
    KFinder(NO);
    DMActivityMonitorOpen();
    check(KFind(AM) && KAllHooksOnce() && gKLockWithoutHooks == 0, @"the guard's note cleared (Turn Back On, a change on the pages), its record left: Activity Monitor opens, with the hooks");
}
static void S_guardOtherSwitch(void) {
    gKAction = 4; KRecord(@"time 1800000000\naction 4\ntested 1\nios 18.5\nbuild 1.8.7.3\nverdict 1\nblamed MacStatusBarCore\n"
                          "feature com.besiktasliseba.macstatusbar batteryMenu 0 Battery Menu|the battery menu\npart DockMagnification the Dock|the Dock\n");
    KFinder(NO);
    DMActivityMonitorOpen();
    check(KFind(AM) && KAllHooksOnce(), @"the guard turned something else off (the battery menu, the Dock): Activity Monitor opens, with the hooks");
}
static void S_guardNoteLive(void) {
    gKAction = 4; KRecord(kFinderStep1b);
    KFinder(NO);
    DMDispSettingsOpenIPad(@"tv-1");
    BOOL refused = !KFind(DS);
    gKAction = 0;
    DMDispSettingsOpenIPad(@"tv-1");
    check(refused && KFind(DS) && KAllHooksOnce(), @"the note is read at each open: refused while it is up, opens once it is cleared (no respring)");
}
static void S_finderOffAtRunTime(void) {
    KFinder(YES);
    KOpen([DMFinderWindow class], @"Documents"); KOpen([DMQuickLookWindow class], @"photo.jpg"); KOpen([DMTextWindow class], @"notes.txt");
    DMActivityMonitorOpen(); DMDispSettingsOpenIPad(@"tv-1");
    DMNativeSetActive(nil);   // (the user went on to Settings: the native windows inactive, the keyboard back with the app)
    BOOL pre = gNativeWindows.count == 5 && !gNativeActive && !gKLock;
    KFinder(NO);
    check(pre && !KFind([DMFinderWindow class]) && !KFind([DMQuickLookWindow class]) && !KFind([DMTextWindow class]), @"Finder switched off: its windows close (a folder, Quick Look, TextEdit)");
    check(KFind(AM) && KFind(DS) && gDMDispSettingsWindow == (id)KFind(DS), @"Activity Monitor and Display Settings stay open (before: every native window closed with Finder)");
    check(!gNativeActive && !gKLock, @"and none comes forward: no native window active, the keyboard stays with the app Finder was switched off in");
}
static void S_finderOffActivityMonitorActive(void) {
    KFinder(YES);
    KOpen([DMFinderWindow class], @"Documents"); DMActivityMonitorOpen();
    KFinder(NO);
    check(!KFind([DMFinderWindow class]) && KFind(AM) && gNativeActive == KFind(AM) && gKLock, @"Finder switched off with Activity Monitor active: Finder's window closes, Activity Monitor stays active with the keyboard");
    check(gKLockWithoutHooks == 0, @"its hooks still in");
}
static void S_finderOffFinderActive(void) {
    KFinder(YES);
    DMActivityMonitorOpen(); KOpen([DMFinderWindow class], @"Documents");
    KFinder(NO);
    check(!KFind([DMFinderWindow class]) && KFind(AM) && !gNativeActive && !gKLock, @"Finder switched off while its window was active: it closes, Activity Monitor behind it stays but does not come forward, the keyboard goes back to the apps");
}
static void S_finderOffOnlyFinder(void) {
    KFinder(YES);
    KOpen([DMFinderWindow class], @"Documents"); KOpen([DMFinderWindow class], @"Downloads");
    DMNativeSetActive(nil);
    KFinder(NO);
    check(gNativeWindows.count == 0 && !gNativeActive && !gKLock, @"Finder switched off with only Finder's windows: all close, none active, the keyboard with the apps (as before)");
}
static void S_reader(void) {
#ifdef NH_NO_READER
    check(NO, @"the guard's record reader (CrashGuard.h MSBDGuardRecordNames) is not there");
#else
    const char *d = "com.besiktasliseba.macstatusbar", *k = "finderEnabled";
    KRecord(kFinderStep1b); check(MSBDGuardRecordNames(gKRecord, d, k) == 1, @"reader: a step 1b \"feature\" line names Finder's switch");
    KRecord(@"time 1\naction 1\nswitch com.besiktasliseba.macstatusbar finderEnabled Finder\n"); check(MSBDGuardRecordNames(gKRecord, d, k) == 1, @"reader: a step 1 \"switch\" line does too");
    KRecord(@"time 1\naction 1\nswitch com.besiktasliseba.macstatusbar finderEnabled Finder\r\n"); check(MSBDGuardRecordNames(gKRecord, d, k) == 1, @"reader: also with a Windows line end");
    KRecord(@"time 1\naction 4\nfeature com.besiktasliseba.macstatusbar finderEnabled 0 Finder|Finder"); check(MSBDGuardRecordNames(gKRecord, d, k) == 1, @"reader: also as the last line with no line end");
    KRecord(@"time 1\naction 4\nfeature com.besiktasliseba.dockmagnification finderEnabled 0 x|y\n"); check(MSBDGuardRecordNames(gKRecord, d, k) == 0, @"reader: the same key of another domain is not Finder's switch");
    KRecord(@"time 1\naction 4\nfeature com.besiktasliseba.macstatusbar finderEnabledOnTV 0 x|y\nfeature com.besiktasliseba.macstatusbar finder 0 x|y\n"); check(MSBDGuardRecordNames(gKRecord, d, k) == 0, @"reader: a longer or shorter key is not it");
    KRecord(@"time 1\naction 4\nframe feature com.besiktasliseba.macstatusbar finderEnabled 0\npart MacStatusBarCore the status bar|the Mac status bar\n"); check(MSBDGuardRecordNames(gKRecord, d, k) == 0, @"reader: only \"switch\" and \"feature\" lines count (a frame line naming it, a part line: no)");
    NSString *longFrame = [@"frame " stringByAppendingString:[@"" stringByPaddingToLength:505 withString:@"x" startingAtIndex:0]];
    KRecord([NSString stringWithFormat:@"time 1\naction 4\n%@ feature com.besiktasliseba.macstatusbar finderEnabled 0 Finder|Finder\n", longFrame]);
    check(MSBDGuardRecordNames(gKRecord, d, k) == 0, @"reader: the rest of a line longer than its buffer is not read as a line of its own");
    KRecord([NSString stringWithFormat:@"time 1\naction 4\n%@\nfeature com.besiktasliseba.macstatusbar finderEnabled 0 Finder|Finder\n", longFrame]);
    check(MSBDGuardRecordNames(gKRecord, d, k) == 1, @"reader: a line after a long one is read");
    check(MSBDGuardRecordNames("/nonexistent/nh-record", d, k) == 0 && MSBDGuardRecordNames(NULL, d, k) == 0, @"reader: no record, no");
#endif
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gKLog = [NSMutableArray array]; gKInits = [NSCountedSet set]; gNativeWindows = [NSMutableArray array]; gKRecords = [NSMutableArray array];
        gKHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1180, 820)];
        NSDictionary<NSString *, void (^)(void)> *all = @{
            @"finder-off-activity-monitor": ^{ S_finderOffActivityMonitor(); }, @"finder-off-display-settings": ^{ S_finderOffDisplaySettings(); },
            @"finder-on-at-start": ^{ S_finderOnAtStart(); }, @"activity-monitor-then-finder-on": ^{ S_activityMonitorThenFinderOn(); },
            @"finder-on-off-on": ^{ S_finderOnOffOn(); }, @"guard-took-finder": ^{ S_guardTookFinder(); }, @"guard-step1": ^{ S_guardStep1(); },
            @"guard-note-cleared": ^{ S_guardNoteCleared(); }, @"guard-other-switch": ^{ S_guardOtherSwitch(); }, @"guard-note-live": ^{ S_guardNoteLive(); },
            @"finder-off-at-run-time": ^{ S_finderOffAtRunTime(); }, @"finder-off-activity-monitor-active": ^{ S_finderOffActivityMonitorActive(); },
            @"finder-off-finder-active": ^{ S_finderOffFinderActive(); }, @"finder-off-only-finder": ^{ S_finderOffOnlyFinder(); }, @"reader": ^{ S_reader(); },
        };
        NSString *s = argc > 1 ? @(argv[1]) : @"";
        if ([s isEqualToString:@"list"]) { for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) printf("%s\n", k.UTF8String); return 0; }
        void (^run)(void) = all[s];
        if (!run) { printf("FAIL  no scenario \"%s\"\n", s.UTF8String); return 1; }
        run();
        for (NSString *p in gKRecords) unlink(p.fileSystemRepresentation);
        return gKFails;
    }
}
