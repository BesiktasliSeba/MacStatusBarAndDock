// PrewarmBlockTweak (dasd) -- an app the user QUIT (our red light, our Force Quit, or the App Switcher's swipe-up) is not prewarmed again until the
// user opens it themselves.
//
// Why here. iOS 15+ prewarms apps: dasd (the Duet Activity Scheduler) picks apps and launches them suspended with ActivePrewarm=1 in their
// environment, out of the App Switcher, every ~30 min (:12 and :42). SpringBoard never sees that request, so it cannot refuse one. dasd asks
// -[_APRSPrewarmInterface prewarmLaunchAppFromBundleID:] for each one. This part, loaded only into dasd, refuses that one call for the apps on the
// user's quit set, and leaves every other launch dasd makes untouched (this method is only ever the prewarm path -- a notification, a VoIP/CallKit
// call, a location launch, Background App Refresh and a normal open all go through FrontBoard, not through here).
//
// The quit set. SpringBoard keeps it (the apps the user quit, cleared when the user opens one again) in our own preferences and tells the world when
// it changes; this part reads it through cfprefsd, the same broker SpringBoard wrote it with, so no file is touched directly and dasd's sandbox is
// never in the way. The read is cached and refreshed only when SpringBoard says the set changed, so a prewarm costs one set lookup, nothing more.
//
// Kill switch. SpringBoard publishes an "on" state; off (or, in debug builds, the file /tmp/msb-noprewarmblock) and this part never refuses anything.
//
// Safety. dasd is not SpringBoard: a crash here only restarts dasd, it does not take the interface down. Still, so a fault here can never loop, this
// part counts its own starts: three starts within 60 s (a crash loop) and it switches itself off for good (a flag the next install clears), doing
// nothing but logging -- the same "a crash switches the part off" the SpringBoard crash guard gives the other parts. Every private call it makes is
// checked once; if the class or the method is not what it expects, it does nothing.
//
// Debug: `touch /tmp/macstatusbar-debug` makes dasd write /tmp/msb-prewarmblock.log (each prewarm asked for, whether it was refused, the set).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#include <os/lock.h>
#include <substrate.h>
#include <sys/stat.h>
#include <time.h>

#define kPrewarmDomain   CFSTR("com.besiktasliseba.macstatusbar.prewarm")
#define kQuitSetKey      CFSTR("quitSet")
#define kPrewarmChanged  "com.besiktasliseba.macstatusbar.prewarm.changed"   // posted by SpringBoard when the set changes
#define kPrewarmEnabled  "com.besiktasliseba.macstatusbar.prewarm.enabled"   // state: 1 = block on (SpringBoard publishes it; unset/0 = off)

#define kStartsFile   "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmBlockStarts.txt"
#define kDisabledFile "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmBlockOff.txt"

static BOOL InDasd(void) {
    static BOOL v; static dispatch_once_t once;
    dispatch_once(&once, ^{ v = strcmp(getprogname(), "dasd") == 0; });
    return v;
}

#if DEBUG
// (dasd's sandbox may block /tmp and /var/tmp; the one channel known to work is cfprefsd, which the quit-set read already uses. Debug builds write a
//  running diagnostic there -- read it from the Mac with `plutil -p`. A file log is also attempted, for when the sandbox does allow it.)
#define kPrewarmDiagDomain CFSTR("com.besiktasliseba.macstatusbar.prewarm.diag")
static void DiagWrite(NSString *key, NSString *value) {
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFStringRef)value, kPrewarmDiagDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kPrewarmDiagDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static void DebugWrite(NSString *line) {
    static NSMutableArray *gLog = nil; static unsigned long gN = 0;
    if (!gLog) gLog = [NSMutableArray array];
    [gLog addObject:[NSString stringWithFormat:@"%lu %@", ++gN, line]];
    while (gLog.count > 40) [gLog removeObjectAtIndex:0];
    DiagWrite(@"log", [gLog componentsJoinedByString:@"\n"]);
    if (access("/var/tmp/msb-prewarmblock-debug", F_OK) == 0) { FILE *f = fopen("/var/tmp/msb-prewarmblock.log", "a"); if (f) { fprintf(f, "%.3f %s\n", (double)time(NULL), line.UTF8String); fclose(f); } }
}
#define Debug(...) DebugWrite(__VA_ARGS__)
static BOOL DebugKillSwitch(void) { return access("/tmp/msb-noprewarmblock", F_OK) == 0; }
#else
#define Debug(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
static BOOL DebugKillSwitch(void) { return NO; }
#endif

// ---- the quit set, read through cfprefsd (cached; refreshed when SpringBoard says it changed) --------------
// dasd may ask for two prewarms at once on two queues (the direct launch and the closure build), so the cache is read, refreshed and replaced only
// under one lock: without it one thread could message the set the other had just replaced and released (external logic test C2, 25 Oct).
static os_unfair_lock gQuitLock = OS_UNFAIR_LOCK_INIT;
static NSSet<NSString *> *gQuitSet = nil;   // (under gQuitLock)
static BOOL gQuitSetStale = YES;            // (under gQuitLock)
static void MarkQuitSetStale(void) { os_unfair_lock_lock(&gQuitLock); gQuitSetStale = YES; os_unfair_lock_unlock(&gQuitLock); }
// Whether the quit set holds this app; the set is read again first when it changed (one cfprefsd read, under the lock: a change is rare).
static BOOL QuitSetContains(NSString *bundleID) {
    NSString *refreshed = nil;
    os_unfair_lock_lock(&gQuitLock);
    if (gQuitSetStale) {
        gQuitSetStale = NO;
        CFPreferencesAppSynchronize(kPrewarmDomain);
        CFPropertyListRef v = CFPreferencesCopyValue(kQuitSetKey, kPrewarmDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        NSMutableSet *set = [NSMutableSet set];
        if (v) {
            if (CFGetTypeID(v) == CFArrayGetTypeID()) for (id b in (__bridge NSArray *)v) if ([b isKindOfClass:[NSString class]] && [b length]) [set addObject:b];
            CFRelease(v);
        }
        gQuitSet = [set copy];
        refreshed = [NSString stringWithFormat:@"%lu app(s) %@", (unsigned long)set.count, [[set allObjects] componentsJoinedByString:@" "]];
    }
    BOOL hit = [gQuitSet containsObject:bundleID];
    os_unfair_lock_unlock(&gQuitLock);
    if (refreshed) Debug([NSString stringWithFormat:@"[set] refreshed: %@", refreshed]);   // (logged outside the lock)
    return hit;
}

static BOOL BlockOn(void) {   // the master switch SpringBoard publishes (off for a new install until SpringBoard turns it on)
    static int token = 0;
    if (token == 0) notify_register_check(kPrewarmEnabled, &token);
    uint64_t state = 0;
    return token != 0 && notify_get_state(token, &state) == NOTIFY_STATUS_OK && state == 1;
}

// ---- the two hooked calls ------------------------------------------------------------------------------------
// dasd asks _APRSPrewarmInterface for a prewarm launch two ways: prewarmLaunchAppFromBundleID: (the direct launch) and closureBuildLaunchAppFromBundleID:
// (it builds a closure that launches the app later, used for the boot/opportunistic prewarms). Both are refused for the quit set -- a quit app that
// went only through the closure path would otherwise still come back (seen on the M1). Both return an object (the assertion / the closure); refusing
// is returning nil, so dasd builds nothing and launches nothing for that app. Both are @24@0:8@16 (id return, one id arg). The hook is installed by
// the constructor only once the class and the methods' shape are confirmed (and never in a crash loop); until then gArmed is off and both pass through.
static BOOL gArmed = NO;
static BOOL DMPrewarmRefuses(NSString *bundleID, const char *where) {
    if (!gArmed || ![bundleID isKindOfClass:[NSString class]] || ![(NSString *)bundleID length]) return NO;
    if (DebugKillSwitch() || !BlockOn()) { Debug([NSString stringWithFormat:@"[%s] %@ allowed (block off)", where, bundleID]); return NO; }
    if (QuitSetContains(bundleID)) {
        Debug([NSString stringWithFormat:@"[%s] %@ REFUSED (the user quit it; not prewarmed until they open it)", where, bundleID]);
        return YES;
    }
    Debug([NSString stringWithFormat:@"[%s] %@ allowed", where, bundleID]);
    return NO;
}
static id (*o_PrewarmLaunch)(id, SEL, id);
static id (*o_ClosureBuild)(id, SEL, id);
static id DMPrewarmLaunch(id self, SEL _cmd, id bundleID) { return DMPrewarmRefuses(bundleID, "prewarm") ? nil : o_PrewarmLaunch(self, _cmd, bundleID); }
static id DMClosureBuild(id self, SEL _cmd, id bundleID) { return DMPrewarmRefuses(bundleID, "closure") ? nil : o_ClosureBuild(self, _cmd, bundleID); }
#include "PrewarmShape.h"   // (DMPrewarmShapeOK: an object return and one object argument, checked for EACH method -- Mac test tools/test-prewarmshape.sh)

// ---- self crash-guard: three starts within 60 s that die young switch this part off for good (the next install clears it) ----
// A start that lives 30 s was not a crash: it leaves the count again, so launchd's on-demand restarts, a jetsam kill or two quick installs never add up
// to the switch-off -- only starts that die young do (external logic test W4, 25 Oct).
static time_t gThisStart = 0;
static void ForgetThisStart(void) {
    if (!gThisStart) return;
    time_t starts[8]; int n = 0;
    FILE *f = fopen(kStartsFile, "r");
    if (f) { long t; while (n < 8 && fscanf(f, "%ld", &t) == 1) if ((time_t)t != gThisStart) starts[n++] = (time_t)t; fclose(f); }
    f = fopen(kStartsFile, "w");
    if (f) { for (int i = 0; i < n; i++) fprintf(f, "%ld\n", (long)starts[i]); fclose(f); }
    Debug(@"[guard] this start lived 30 s: not counted any more");
}
static BOOL SelfDisabledByCrashLoop(void) {
    if (access(kDisabledFile, F_OK) == 0) { Debug(@"[guard] already switched off after an earlier crash loop"); return YES; }
    time_t now = time(NULL);
    time_t starts[8]; int n = 0;
    FILE *f = fopen(kStartsFile, "r");
    if (f) { long t; while (n < 8 && fscanf(f, "%ld", &t) == 1) if (now - (time_t)t < 60) starts[n++] = (time_t)t; fclose(f); }
    if (n >= 8) n = 7;
    starts[n++] = now;
    gThisStart = now;
    f = fopen(kStartsFile, "w");
    if (f) { for (int i = 0; i < n; i++) fprintf(f, "%ld\n", (long)starts[i]); fclose(f); }
    if (n >= 3) {   // three starts within a minute: a crash loop -- switch off
        FILE *d = fopen(kDisabledFile, "w");
        if (d) { fprintf(d, "switched off after %d starts within 60 s at %ld\n", n, (long)now); fclose(d); }
        Debug([NSString stringWithFormat:@"[guard] %d starts within 60 s: switching the prewarm block off", n]);
        return YES;
    }
    return NO;
}

%ctor {
    if (!InDasd()) return;
    if (SelfDisabledByCrashLoop()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ForgetThisStart(); });   // (the main queue, as the change notification: the debug log is not shared across threads)
    Class c = objc_getClass("_APRSPrewarmInterface");
    SEL sel = @selector(prewarmLaunchAppFromBundleID:), closureSel = @selector(closureBuildLaunchAppFromBundleID:);
    Method m = c ? class_getInstanceMethod(c, sel) : NULL, mc = c ? class_getInstanceMethod(c, closureSel) : NULL;
    if (!m) { Debug(@"[init] _APRSPrewarmInterface prewarmLaunchAppFromBundleID: not found: doing nothing"); return; }
    const char *enc = method_getTypeEncoding(m);
    if (!DMPrewarmShapeOK(m)) { Debug([NSString stringWithFormat:@"[init] unexpected signature \"%s\": doing nothing", enc ?: "(nil)"]); return; }
    MSHookMessageEx(c, sel, (IMP)DMPrewarmLaunch, (IMP *)&o_PrewarmLaunch);
    if (DMPrewarmShapeOK(mc)) MSHookMessageEx(c, closureSel, (IMP)DMClosureBuild, (IMP *)&o_ClosureBuild);
    else Debug([NSString stringWithFormat:@"[init] closureBuildLaunchAppFromBundleID: %s: not hooked (only the direct prewarm is refused)", mc ? "unexpected signature" : "not found"]);
    gArmed = YES;
    static int token = 0;
    notify_register_dispatch(kPrewarmChanged, &token, dispatch_get_main_queue(), ^(int t) { MarkQuitSetStale(); });
    MarkQuitSetStale();
    Debug([NSString stringWithFormat:@"[init] prewarm block armed (signature \"%s\")", enc]);
}
