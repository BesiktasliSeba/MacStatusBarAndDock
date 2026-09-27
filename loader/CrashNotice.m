// CrashNotice.m -- MacCrashNotice.dylib, in /var/jb/usr/lib/MacStatusBarAndDock: the crash guard's one-time notice on the Home Screen
// (MacStatusBar&Dock, 2026-09-26). Users may never open our Settings, so after the guard acted (common/CrashGuard.h) the same plain explanation as
// the pages' footer (common/CrashExplain.h) comes up once as a stock alert: "OK", "Open Settings" (our Status Bar page, full screen, like the
// welcome alert's "Take Me There") and, when the tweak is off (safe mode, or "Enable Anyway" switched off on an untested iPadOS version) or on an
// untested version, "Report a Problem" (the pre-filled GitHub page).
// When the guard turned the tweak off, none of our SpringBoard parts load, so this is its own small part, which SpringBoard's loader loads only
// while an unshown guard record exists (MSBDGuardNoticeLoad; else it is never opened -- no cost). Why it is safe to load even then:
//  - no hooks at all (no %hook, no swizzling, not linked to a hooking library): SpringBoard's own code runs unchanged;
//  - it only reads SpringBoard's state through respondsToSelector-checked getters (lock, cover sheet, front app, App Switcher, App Library) and the
//    window list, and makes one window of its own at alert level with a stock UIAlertController, the way the welcome alert does;
//  - it waits for the Home Screen with a 1 s check that stops after 5 minutes (started again at each unlock), and stops for good once shown;
//  - it is marked as shown the moment it appears ("shown" in the record), and the loader stops loading it after 3 SpringBoard starts that ran
//    10 s without it being shown ("ran" lines, added here) or 6 loads in all, so even a crash in here could not come back again and again (and
//    ElleKit's Safe Mode stays as the last net).
// Gated like the welcome alert: unlocked, on the Home Screen with nothing else up, never over the Lock Screen (put away on lock, which counts as
// shown). While our status bar runs (the guard only turned switches off), its own checks are asked too (menus and alerts of ours).
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import "../common/CrashExplain.h"
#import "../common/AlertQueue.h"   // (our alerts one at a time: the notice waits for another alert of ours)

@interface UIWindow (MSBDNoticePrivate)
+ (NSArray<UIWindow *> *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end
static UIWindow *gNoticeWindow;
static BOOL gNoticeDone = NO;
static int gNoticePolls = 0, gNoticeLockToken = 0;
static NSDictionary *gNoticeRecord;

static void NoticeLog(NSString *line) {
#if DEBUG
    FILE *f = fopen("/tmp/msbd-crashnotice.log", "a");
    if (f) { fprintf(f, "%ld [notice] %s\n", (long)time(NULL), line.UTF8String); fclose(f); }
#else
    (void)line;
#endif
}
static id NoticeCall(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return obj && [obj respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}
static BOOL NoticeBool(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return obj && [obj respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
}
static double NoticeProcessAge(void) {
    struct kinfo_proc kp; size_t len = sizeof kp; int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0) return 1e9;
    struct timeval now; gettimeofday(&now, NULL);
    return (now.tv_sec - kp.kp_proc.p_starttime.tv_sec) + (now.tv_usec - kp.kp_proc.p_starttime.tv_usec) / 1e6;
}
static id NoticeShared(const char *cls) {   // (iPadOS 17+: +sharedInstanceIfExists, as SpringBoard asks; issue #1. 15/16: +sharedInstance)
    Class c = objc_getClass(cls);
    if (c && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17) {
        id v = NoticeCall((id)c, @"sharedInstanceIfExists");
        if (v || [c respondsToSelector:NSSelectorFromString(@"sharedInstanceIfExists")]) return v;
    }
    return NoticeCall((id)c, @"sharedInstance");
}
static BOOL NoticeLocked(void) {
    if (NoticeBool(NoticeShared("SBLockScreenManager"), @"isUILocked")) return YES;
    id backlight = NoticeShared("SBBacklightController");
    return [backlight respondsToSelector:NSSelectorFromString(@"screenIsOn")] && !NoticeBool(backlight, @"screenIsOn");
}
static BOOL NoticeCoverSheet(void) {
    id cs = NoticeShared("SBCoverSheetPresentationManager");
    return NoticeBool(cs, @"isPresented") || NoticeBool(cs, @"isVisible");
}
// Why not now (nil: the Home Screen is showing, unlocked, nothing else up).
static NSString *NoticeBlocker(void) {
    if (NoticeProcessAge() < 10.0) return @"SpringBoard starting";
    if (NoticeLocked()) return @"locked or screen off";
    if (NoticeCoverSheet()) return @"Notification Center / Lock Screen";
    if (MSBDAlertBusy(nil)) return @"another alert of ours";
    if (NoticeCall([UIApplication sharedApplication], @"_accessibilityFrontMostApplication")) return @"an app in front";
    Class sw = objc_getClass("SBMainSwitcherViewController");
    id switcher = sw ? NoticeCall(sw, @"sharedInstance") : NoticeCall(objc_getClass("SBMainSwitcherControllerCoordinator"), @"sharedInstanceIfExists");
    if (NoticeBool(switcher, @"isAnySwitcherVisible") || NoticeBool(switcher, @"isMainSwitcherVisible")) return @"App Switcher";
    id icons = NoticeCall(NoticeCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
    for (NSString *name in @[@"isOverlayLibraryViewVisible", @"isLibraryViewControllerVisible", @"isMainDisplayLibraryViewVisible"]) if (NoticeBool(icons, name)) return @"App Library";
    NSArray<UIWindow *> *windows = [UIWindow respondsToSelector:@selector(allWindowsIncludingInternalWindows:onlyVisibleWindows:)] ? [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO] : @[];
    for (UIWindow *w in windows) {   // (looked at, never created: Control Center, Spotlight)
        if (w.hidden || w.alpha < 0.01) continue;
        NSString *cls = NSStringFromClass([w class]);
        if ([cls isEqualToString:@"SBControlCenterWindow"]) return @"Control Center";
        if ([cls isEqualToString:@"SBTransientOverlayWindow"] && [NSStringFromClass([w.rootViewController class]) isEqualToString:@"SBSpotlightTransientOverlayViewController"]) return @"Spotlight";
    }
    // (our status bar, when it runs: its menus, alerts and the welcome alert -- StatusBar.x)
    BOOL (*busy)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "MSBDHomeScreenBusy");
    if (busy && busy()) return @"a menu or alert of ours";
    return nil;
}
static void NoticeMarkShown(void) {
    FILE *f = fopen(MSBD_GUARD_RECORD, "a");
    if (f) { fprintf(f, "shown %ld\n", (long)time(NULL)); fclose(f); }
}
static void NoticeClose(NSString *how, BOOL putAway) {
    if (!gNoticeWindow) return;
    UIViewController *root = gNoticeWindow.rootViewController;
    if (putAway && root.presentedViewController) [root dismissViewControllerAnimated:NO completion:nil];
    gNoticeWindow.hidden = YES; gNoticeWindow = nil;
    if (gNoticeLockToken) { notify_cancel(gNoticeLockToken); gNoticeLockToken = 0; }
    NoticeLog([NSString stringWithFormat:@"closed: %@", how]);
}
static void NoticeOpenSettings(void) {
    void (*open)(void) = (void (*)(void))dlsym(RTLD_DEFAULT, "MSBDOpenStatusBarPage");   // (our status bar runs: it opens Settings full screen)
    if (open) { open(); return; }
    static int token = 0;   // (Settings opens our page, once, if the request is recent: StatusBarSettingsRow.x; the token is kept, so the state stays)
    if (token || notify_register_check("com.besiktasliseba.macstatusbaranddock.openstatusbarpage", &token) == NOTIFY_STATUS_OK) {
        notify_set_state(token, (uint64_t)time(NULL));
        notify_post("com.besiktasliseba.macstatusbaranddock.openstatusbarpage");
    }
    id app = [UIApplication sharedApplication];
    SEL launch = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    if ([app respondsToSelector:launch]) ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(app, launch, @"com.apple.Preferences", NO);
    else [app openURL:[NSURL URLWithString:@"prefs:"] options:@{} completionHandler:nil];
}
static void NoticeShow(void) {
    int action = MSBDExplainAction();
    BOOL untested = !MSBDVersionTested();
    NSString *message = MSBDGuardExplanation(action, untested, YES);
    gNoticeDone = YES;
    NoticeMarkShown();   // (as it appears: whatever happens next, it is never shown again)
    if (!message) { NoticeLog(@"not shown: the guard's note was already cleared in Settings"); return; }
    UIWindow *w = MSBDMakeAlertWindow(UIWindowLevelAlert + 10.0);   // (marked: other alerts of ours wait for it)
    gNoticeWindow = w;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:MSBDGuardAlertTitle(action) message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { NoticeClose(@"OK", NO); }]];
    UIAlertAction *open = [UIAlertAction actionWithTitle:@"Open Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { NoticeClose(@"Open Settings", NO); NoticeOpenSettings(); }];
    [a addAction:open];
    if (action != 1 || untested) {
        [a addAction:[UIAlertAction actionWithTitle:@"Report a Problem" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NoticeClose(@"Report a Problem", NO);
            CFPropertyListRef e = CFPreferencesCopyValue(CFSTR("windowEngine"), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            NSString *engine = e && CFGetTypeID(e) == CFStringGetTypeID() ? [(__bridge NSString *)e copy] : nil;
            if (e) CFRelease(e);
            NSURL *url = MSBDReportProblemURL(engine);
            NoticeLog([NSString stringWithFormat:@"report: %@", url.absoluteString]);
#if DEBUG
            if (access("/tmp/msb-report-dryrun", F_OK) == 0) { NoticeLog(@"report: dry run, not opened"); return; }   // (as MSBDOpenReport)
#endif
            if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }]];
    }
    a.preferredAction = open;
    [w.rootViewController presentViewController:a animated:YES completion:nil];
    // Put away on lock (counts as shown): the lock state changes, or (checked each second) the Lock Screen / Notification Center comes over it.
    notify_register_dispatch("com.apple.springboard.lockstate", &gNoticeLockToken, dispatch_get_main_queue(), ^(int t) {
        uint64_t locked = 0; notify_get_state(t, &locked);
        if (locked) NoticeClose(@"locked (counts as shown)", YES);
    });
    NoticeLog([NSString stringWithFormat:@"shown: action %d%@", action, untested ? @" (untested iPadOS)" : @""]);
}
static void NoticeWatchShown(void) {
    if (!gNoticeWindow) return;
    if (NoticeLocked() || NoticeCoverSheet()) { NoticeClose(@"Lock Screen / Notification Center (counts as shown)", YES); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ NoticeWatchShown(); });
}
// The wait for the Home Screen: once a second, for at most 5 minutes (then again after the next unlock).
static void NoticePoll(void) {
    if (gNoticeDone) return;
    NSString *blocker = NoticeBlocker();
    if (!blocker) { NoticeShow(); NoticeWatchShown(); return; }
    static NSString *logged;
    if (![blocker isEqualToString:logged]) { logged = blocker; NoticeLog([@"waiting: " stringByAppendingString:blocker]); }
    // After 5 minutes the check slows down to every 30 s (an unlock makes it fast again). It never simply stops: with "Skip Lock Screen After
    // Respring" the raw lock state stays 1 until the next real lock, so an unlock may never be announced.
    if (++gNoticePolls == 300) NoticeLog(@"waited 5 min: looking every 30 s now");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (gNoticePolls >= 300 ? 30 : 1) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ NoticePoll(); });
}

__attribute__((constructor)) static void MSBDCrashNoticeInit(void) {
    @autoreleasepool {
        gNoticeRecord = MSBDCrashRecord();
        if (!gNoticeRecord || [gNoticeRecord[@"shown"] boolValue]) return;
        NoticeLog([NSString stringWithFormat:@"loaded: record of action %@", gNoticeRecord[@"action"]]);
        dispatch_async(dispatch_get_main_queue(), ^{
            static int unlockToken;
            notify_register_dispatch("com.apple.springboard.lockstate", &unlockToken, dispatch_get_main_queue(), ^(int t) {
                uint64_t locked = 1; notify_get_state(t, &locked);
                if (gNoticeDone) { notify_cancel(t); return; }
                if (!locked && gNoticePolls >= 300) gNoticePolls = 0;   // (the slow check goes back to once a second at its next look)
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ NoticePoll(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{   // (a real start: it counts)
                if (gNoticeDone) return;
                FILE *f = fopen(MSBD_GUARD_RECORD, "a");
                if (f) { fprintf(f, "ran %ld\n", (long)time(NULL)); fclose(f); }
            });
        });
    }
}
