// PrewarmBlockTweak (dasd) -- an app the user QUIT (our red light, our Force Quit, or the App Switcher's swipe-up) is not prewarmed again until the
// user opens it themselves.
//
// Why here. iOS 15+ prewarms apps: dasd (the Duet Activity Scheduler) picks apps and launches them suspended with ActivePrewarm=1 in their
// environment, out of the App Switcher, every ~30 min (:12 and :42). SpringBoard never sees that request, so it cannot refuse one. dasd asks
// -[_APRSPrewarmInterface prewarmLaunchAppFromBundleID:] for each one. This part, loaded only into dasd, refuses that one call for the apps on the
// user's quit set, and leaves every other launch dasd makes untouched (this method is only ever the prewarm path -- a notification, a VoIP/CallKit
// call, a location launch, Background App Refresh and a normal open all go through FrontBoard, not through here).
//
// The quit set. SpringBoard keeps it (the apps the user quit, cleared when the user opens one again) in our own preferences, writes it to a file of
// its own for this part and then tells the world it changed; this part reads that file (common/PrewarmQuitSet.h), never through cfprefsd -- which
// answers a sandboxed process only for the domains its sandbox allows: on palera1n (iPad 2, 16.7.7) dasd read an empty set that way and refused
// nothing, 29 Oct. The read is cached and done again only when SpringBoard says the set changed or the file is not the one read last, so a prewarm
// costs one stat and one set lookup.
//
// On and off. The quit set's file is the switch: there, its apps are refused; gone (Use Stock Status Bar, a SpringBoard without our status bar
// part, the package removed -- common/PrewarmQuitSet.h), nothing is. So this part decides from the first prewarm on, also when dasd starts before
// SpringBoard's status bar part runs (right after an install launchd starts dasd again with the new SpringBoard): until 1.7.1 it waited for
// SpringBoard to publish an "on" state at its start, and the prewarms dasd asked for before that went through (M1, 30 Oct: an app the user had
// quit "allowed (block off)" right after an install; with 1.7.1 that same first prewarm was refused). In debug builds the file
// /tmp/msb-noprewarmblock switches it off as well.
//
// Loaded. Once armed it writes its start stamp (dasd's pid and start time, its build ID: common/PrewarmPartID.h), so an install that does not change
// this part leaves dasd running -- a dasd started again costs the M1 10 to 26 minutes of CPU (1.7.2 item 8). The postinst restarts dasd only
// when the stamp is not the running dasd's or names another build.
//
// Safety. dasd is not SpringBoard: a crash here only restarts dasd, it does not take the interface down. Still, so a fault here can never loop, this
// part counts its own starts: three starts within 60 s (a crash loop) and it switches itself off for good (a flag the next install clears), doing
// nothing but logging -- the same "a crash switches the part off" the SpringBoard crash guard gives the other parts. Every private call it makes is
// checked once; if the class or the method is not what it expects, it does nothing.
//
// Debug builds: each prewarm asked for, whether it was refused, and the set, in the diagnostic domain com.besiktasliseba.macstatusbar.prewarm.diag
// and, while /var/tmp/msb-prewarmblock-debug exists, in /var/tmp/msb-prewarmblock.log (below).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#include <os/lock.h>
#include <substrate.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <time.h>
#include <unistd.h>
#include "../common/PrewarmPartID.h"   // (the build ID and the start stamp -- Mac test tools/test-prewarmpartid.sh)

#define kPrewarmDomain   CFSTR("com.besiktasliseba.macstatusbar.prewarm")
#define kQuitSetKey      CFSTR("quitSet")
#define kPrewarmChanged  "com.besiktasliseba.macstatusbar.prewarm.changed"   // posted by SpringBoard when the set changes

#define kStartsFile   "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmBlockStarts.txt"
#define kDisabledFile "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmBlockOff.txt"

static BOOL InDasd(void) {
    static BOOL v; static dispatch_once_t once;
    dispatch_once(&once, ^{ v = strcmp(getprogname(), "dasd") == 0; });
    return v;
}

#if DEBUG
// (Debug builds write a running diagnostic through cfprefsd -- read it from the Mac with `plutil -p` -- where cfprefsd takes it from dasd (Dopamine;
//  on palera1n it does not, as with the quit set), and with /var/tmp/msb-prewarmblock-debug present also the file log /var/tmp/msb-prewarmblock.log,
//  which dasd's sandbox allows on palera1n (iPad 2, 16.7.7, 30 Oct).)
#define kPrewarmDiagDomain CFSTR("com.besiktasliseba.macstatusbar.prewarm.diag")
static void DiagWrite(NSString *key, NSString *value) {
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFStringRef)value, kPrewarmDiagDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kPrewarmDiagDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
// (one line at a time, under a lock: the prewarm calls come on dasd's launch queues, two at once -- its boot and opportunistic closure builds run
//  together right after it starts -- and the list changed by one while the other joined it threw in -componentsJoinedByString:, aborting dasd:
//  two of three starts on the A12Z, 18.5, 29 Oct, and its third start switched the prewarm block off)
static os_unfair_lock gDebugLock = OS_UNFAIR_LOCK_INIT;
static void DebugWrite(NSString *line) {
    static NSMutableArray *gLog = nil; static unsigned long gN = 0;   // (under gDebugLock)
    os_unfair_lock_lock(&gDebugLock);
    if (!gLog) gLog = [NSMutableArray array];
    [gLog addObject:[NSString stringWithFormat:@"%lu %@", ++gN, line]];
    while (gLog.count > 40) [gLog removeObjectAtIndex:0];
    DiagWrite(@"log", [gLog componentsJoinedByString:@"\n"]);
    if (access("/var/tmp/msb-prewarmblock-debug", F_OK) == 0) { FILE *f = fopen("/var/tmp/msb-prewarmblock.log", "a"); if (f) { fprintf(f, "%.3f %s\n", (double)time(NULL), line.UTF8String); fclose(f); } }
    os_unfair_lock_unlock(&gDebugLock);
}
#define Debug(...) DebugWrite(__VA_ARGS__)
static BOOL DebugKillSwitch(void) { return access("/tmp/msb-noprewarmblock", F_OK) == 0; }
#else
#define Debug(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
static BOOL DebugKillSwitch(void) { return NO; }
#endif

// ---- the quit set, read from its file (cached; read again when SpringBoard says it changed, or the file changed) --------------
// dasd may ask for two prewarms at once on two queues (the direct launch and the closure build), so the cache is read, refreshed and replaced only
// under one lock: without it one thread could message the set the other had just replaced and released (external logic test C2, 25 Oct).
#include "../common/PrewarmQuitSet.h"   // (the file, its reading and its stamp -- Mac test tools/test-prewarmquitset.sh)
static os_unfair_lock gQuitLock = OS_UNFAIR_LOCK_INIT;
static NSSet<NSString *> *gQuitSet = nil;   // (under gQuitLock)
static BOOL gQuitSetStale = YES;            // (under gQuitLock)
static MSBDPrewarmFileStamp gQuitFileStamp;   // (under gQuitLock: the file as it was when it was read)
static void MarkQuitSetStale(void) { os_unfair_lock_lock(&gQuitLock); gQuitSetStale = YES; os_unfair_lock_unlock(&gQuitLock); }
// Whether the quit set holds this app (*kept: its file is there, so SpringBoard keeps a set -- the block is on); the set is read again first when
// it changed (one small file read, under the lock: a change is rare).
static BOOL QuitSetContains(NSString *bundleID, BOOL *kept) {
    NSString *refreshed = nil;
    os_unfair_lock_lock(&gQuitLock);
    struct stat st;
    MSBDPrewarmFileStamp now = MSBDPrewarmStampOf(stat(kMSBDPrewarmQuitSetFile, &st) == 0 ? &st : NULL);
    *kept = now.present;
    if (gQuitSetStale || MSBDPrewarmStampChanged(gQuitFileStamp, now)) {
        gQuitSetStale = NO;
        gQuitFileStamp = now;
        NSSet<NSString *> *set = MSBDPrewarmQuitSetFromPlist(now.present ? [NSData dataWithContentsOfFile:@kMSBDPrewarmQuitSetFile] : nil);
        gQuitSet = set;
        refreshed = [NSString stringWithFormat:@"%lu app(s) %@", (unsigned long)set.count, [[set allObjects] componentsJoinedByString:@" "]];
    }
    BOOL hit = [gQuitSet containsObject:bundleID];
    os_unfair_lock_unlock(&gQuitLock);
    if (refreshed) Debug([NSString stringWithFormat:@"[set] refreshed: %@", refreshed]);   // (logged outside the lock)
    return hit;
}
#if DEBUG
// (debug, once at the start: the set from its file, and what cfprefsd and dasd's sandbox say about SpringBoard's domain of the same set -- which
//  way a jailbreak goes; 0 = allowed, 1 = refused by the sandbox)
extern int sandbox_check(pid_t pid, const char *operation, int type, ...);
static void DebugReadsAtStart(void) {
    NSSet *file = MSBDPrewarmQuitSetFromPlist([NSData dataWithContentsOfFile:@kMSBDPrewarmQuitSetFile]);
    CFPreferencesAppSynchronize(kPrewarmDomain);
    CFPropertyListRef v = CFPreferencesCopyValue(kQuitSetKey, kPrewarmDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    long viaPrefs = v && CFGetTypeID(v) == CFArrayGetTypeID() ? (long)CFArrayGetCount((CFArrayRef)v) : -1;
    if (v) CFRelease(v);
    const int noReport = 0x40000000, preferenceDomain = 6, path = 1;   // (SANDBOX_CHECK_NO_REPORT, SANDBOX_FILTER_PREFERENCE_DOMAIN, SANDBOX_FILTER_PATH)
    int domainRead = sandbox_check(getpid(), "user-preference-read", preferenceDomain | noReport, "com.besiktasliseba.macstatusbar.prewarm");
    int fileRead = sandbox_check(getpid(), "file-read-data", path | noReport, kMSBDPrewarmQuitSetFile);
    Debug([NSString stringWithFormat:@"[init] quit set: %lu app(s) in its file, %@ through cfprefsd (sandbox, asked: the domain %d, the file %d)",
           (unsigned long)file.count, viaPrefs < 0 ? @"none" : [NSString stringWithFormat:@"%ld", viaPrefs], domainRead, fileRead]);
}
#endif

// ---- the two hooked calls ------------------------------------------------------------------------------------
// dasd asks _APRSPrewarmInterface for a prewarm launch two ways: prewarmLaunchAppFromBundleID: (the direct launch) and closureBuildLaunchAppFromBundleID:
// (it builds a closure that launches the app later, used for the boot/opportunistic prewarms). Both are refused for the quit set -- a quit app that
// went only through the closure path would otherwise still come back (seen on the M1). Both return an object (the assertion / the closure); refusing
// is returning nil, so dasd builds nothing and launches nothing for that app. Both are @24@0:8@16 (id return, one id arg). The hook is installed by
// the constructor only once the class and the methods' shape are confirmed (and never in a crash loop); until then gArmed is off and both pass through.
static BOOL gArmed = NO;
static BOOL DMPrewarmRefuses(NSString *bundleID, const char *where) {
    if (!gArmed || ![bundleID isKindOfClass:[NSString class]] || ![(NSString *)bundleID length]) return NO;
    if (DebugKillSwitch()) { Debug([NSString stringWithFormat:@"[%s] %@ allowed (block off: the debug switch)", where, bundleID]); return NO; }
    BOOL kept = NO;
    if (QuitSetContains(bundleID, &kept)) {
        Debug([NSString stringWithFormat:@"[%s] %@ REFUSED (the user quit it; not prewarmed until they open it)", where, bundleID]);
        return YES;
    }
    Debug([NSString stringWithFormat:kept ? @"[%s] %@ allowed" : @"[%s] %@ allowed (block off: no quit set kept -- its file is not there)", where, bundleID]);
    return NO;
}
static id (*o_PrewarmLaunch)(id, SEL, id);
static id (*o_ClosureBuild)(id, SEL, id);
static id DMPrewarmLaunch(id self, SEL _cmd, id bundleID) { return DMPrewarmRefuses(bundleID, "prewarm") ? nil : o_PrewarmLaunch(self, _cmd, bundleID); }
static id DMClosureBuild(id self, SEL _cmd, id bundleID) { return DMPrewarmRefuses(bundleID, "closure") ? nil : o_ClosureBuild(self, _cmd, bundleID); }
#include "PrewarmShape.h"   // (DMPrewarmShapeOK: an object return and one object argument, checked for EACH method -- Mac test tools/test-prewarmshape.sh)

// ---- the start stamp: this dasd has this build of the part (common/PrewarmPartID.h) ----
// The build ID is in the binary after its marker (the helper reads it from the file installed: prewarmblock/Makefile makes it). Written once armed,
// through a new file renamed over the old one, so the postinst never reads half a line. No stamp (a write refused, a sysctl refused) only means the
// next install restarts dasd, as every install did before.
#ifndef MSBD_DASD_PART_ID
#error "MSBD_DASD_PART_ID comes from prewarmblock/Makefile (tools/prewarm-part-id.sh)"
#endif
__attribute__((used)) static const char kPartMark[] = kMSBDPrewarmPartMarker MSBD_DASD_PART_ID;
_Static_assert(sizeof(MSBD_DASD_PART_ID) - 1 == kMSBDPrewarmPartIDLen, "the build ID is 16 hex digits");
static void WriteLoadedStamp(void) {
    struct kinfo_proc kp; size_t len = sizeof kp; int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    memset(&kp, 0, sizeof kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len < sizeof kp || kp.kp_proc.p_pid != getpid()) { Debug(@"[stamp] dasd's start time not readable: no stamp (the next install restarts dasd)"); return; }
    char line[96];
    MSBDPrewarmStampFormat(line, sizeof line, (long)getpid(), (long long)kp.kp_proc.p_starttime.tv_sec, (long)kp.kp_proc.p_starttime.tv_usec, kPartMark + sizeof(kMSBDPrewarmPartMarker) - 1);
    FILE *f = fopen(kMSBDPrewarmLoadedFile ".new", "w");
    BOOL ok = f && fputs(line, f) >= 0;
    if (f) ok = fclose(f) == 0 && ok;
    ok = ok && rename(kMSBDPrewarmLoadedFile ".new", kMSBDPrewarmLoadedFile) == 0;
    int err = errno;
    if (!ok) unlink(kMSBDPrewarmLoadedFile ".new");
    if (ok) Debug([NSString stringWithFormat:@"[stamp] written: %@", [@(line) stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]]);
    else Debug([NSString stringWithFormat:@"[stamp] could not be written (%s): the next install restarts dasd", strerror(err)]);
    (void)err;
}

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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ForgetThisStart(); });   // (the main queue, as the change notification)
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
    WriteLoadedStamp();
    static int token = 0;
    notify_register_dispatch(kPrewarmChanged, &token, dispatch_get_main_queue(), ^(int t) { MarkQuitSetStale(); });
    MarkQuitSetStale();
    Debug([NSString stringWithFormat:@"[init] prewarm block armed (signature \"%s\")", enc]);
#if DEBUG
    dispatch_async(dispatch_get_main_queue(), ^{ DebugReadsAtStart(); });
#endif
}
