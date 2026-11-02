// SleepGuardDaemon.h -- the Sleep Guard in sshtoggled (root; battery drain F1, MacStatusBar&Dock 1.7.8). Rules: common/SleepGuard.h.
// When the screen goes off it looks once at powerd's assertions (IOPMCopyAssertionsByProcess: one call, nothing kept running). Nothing stuck:
// done until the next screen-off. Something stuck (keeps the iPad awake, owner process gone -- by pid, and by start time and name, as pids are
// reused): it looks again a minute later and, still stuck with the screen off and nothing else keeping the iPad awake, clears it -- powerd
// started over (launchctl kickstart -k system/com.apple.powerd: the only way a dead process's assertion goes). That drops EVERY assertion:
// libIOKit hands a live process's async ones to the new powerd (the charge job's stay-awake came back with its first start time), the others
// stay gone unless their owner raises them again (a test process's SystemIsActive did not come back; the charge job re-raises its cut, a30ec74).
// So a live keep-awake assertion (a backup, a download, an AirDrop, audio) makes it wait and look again in 5 minutes; only powerd's own and the
// charge job's are left out. It also loses every scheduled wake (IOPMCopyScheduledPowerEvents: 4 -> 0 on the 17.5, 2 Nov; UserEventAgent's
// alarm wakes did not come back), so the guard copies them first and schedules again the ones still ahead (SGRescheduleWakes). Then it looks
// once more to confirm. When a limit blocks a clear it plans a look for when the limit ends. The clears (for the 30-minute gap and 6 a day) are
// kept in the state file, read back at every start (sshtoggled starts over after a cfprefsd restart, an upgrade, a userspace reboot). Each
// step is logged (MSBD_SG_LOG) and the state written for Settings (MSBD_SG_STATE). Settings asks for a look when its page opens (MSBD_SG_CHECK)
// and when the switch changes (MSBD_SG_CHANGED).
#include "../../common/SleepGuard.h"
#include <dlfcn.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <mach/mach_time.h>

extern int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);
extern int proc_pid_rusage(int pid, int flavor, void *buffer);
#define SG_PROC_PIDTBSDINFO 3
struct sg_proc_bsdinfo {   // (sys/proc_info.h's proc_bsdinfo: the iOS SDK has no header for it)
    uint32_t pbi_flags, pbi_status, pbi_xstatus, pbi_pid, pbi_ppid;
    uid_t pbi_uid; gid_t pbi_gid; uid_t pbi_ruid; gid_t pbi_rgid; uid_t pbi_svuid; gid_t pbi_svgid; uint32_t rfu_1;
    char pbi_comm[16]; char pbi_name[32];
    uint32_t pbi_nfiles, pbi_pgid, pbi_pjobc, e_tdev, e_tpgid; int32_t pbi_nice; uint64_t pbi_start_tvsec, pbi_start_tvusec;
};

#define MSBD_SG_CHECK   "com.besiktasliseba.sleepguard.check"     // (Settings: look now)
#define MSBD_SG_UPDATED "com.besiktasliseba.sleepguard.updated"   // (posted after the state file is written)
#define MSBD_SG_POWERD  "com.besiktasliseba.sleepguard.powerd-restarted"   // (posted after powerd was started over)

static void SGLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void SGLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt); NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    struct stat st;
    if (stat(MSBD_SG_LOG, &st) == 0 && st.st_size > 64 * 1024) rename(MSBD_SG_LOG, MSBD_SG_LOG ".old");
    FILE *f = fopen(MSBD_SG_LOG, "a"); if (!f) return;
    char ts[32]; time_t now = time(NULL); strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", localtime(&now));
    fprintf(f, "%s %s\n", ts, line.UTF8String);
    fclose(f);
}

typedef struct { int stuck, live; NSString *what, *liveWhat; } SGScan;
// How long the process at pid has run on the clock that stops in sleep (seconds; -1 unknown).
static double SGAwakeAge(int pid) {
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    struct rusage_info_v0 ri;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V0, &ri) != 0 || !ri.ri_proc_start_abstime) return -1;
    uint64_t t = mach_absolute_time();
    return t > ri.ri_proc_start_abstime ? (double)(t - ri.ri_proc_start_abstime) * tb.numer / tb.denom / 1e9 : 0;
}
static SGScan SGLook(void) {
    SGScan r = { 0, 0, @"", @"" };
    static int (*byProc)(CFDictionaryRef *);
    if (!byProc) { void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW); byProc = io ? (int (*)(CFDictionaryRef *))dlsym(io, "IOPMCopyAssertionsByProcess") : NULL; }
    CFDictionaryRef all = NULL;
    if (!byProc || byProc(&all) != 0 || !all) { r.what = @"(powerd's list could not be read)"; return r; }
    double now = (double)time(NULL);
    NSMutableArray *names = [NSMutableArray array], *live = [NSMutableArray array];
    for (NSNumber *pidKey in (__bridge NSDictionary *)all) {
        int pid = pidKey.intValue;
        BOOL exists = pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
        struct sg_proc_bsdinfo bi; memset(&bi, 0, sizeof bi);
        BOOL haveInfo = exists && proc_pidinfo(pid, SG_PROC_PIDTBSDINFO, 0, &bi, sizeof bi) == (int)sizeof bi;
        char proc[64] = ""; if (exists) proc_name(pid, proc, sizeof proc);
        double started = haveInfo ? (double)bi.pbi_start_tvsec + bi.pbi_start_tvusec / 1e6 : 0, awake = exists ? SGAwakeAge(pid) : -1;
        for (NSDictionary *a in ((__bridge NSDictionary *)all)[pidKey]) {
            if (![a isKindOfClass:[NSDictionary class]]) continue;
            NSString *type = [a[@"AssertType"] isKindOfClass:[NSString class]] ? a[@"AssertType"] : @"";
            NSString *name = [a[@"AssertName"] isKindOfClass:[NSString class]] ? a[@"AssertName"] : @"";
            NSString *owner = [a[@"Process Name"] isKindOfClass:[NSString class]] ? a[@"Process Name"] : @"";
            double made = [a[@"AssertStartWhen"] isKindOfClass:[NSDate class]] ? [(NSDate *)a[@"AssertStartWhen"] timeIntervalSince1970] : 0;
            BOOL gone = MSBDSGOwnerGone(pid, exists, proc, owner.UTF8String, started, awake, made, now);
#if DEBUG
            // (test switch, debug builds: with the root-owned file below, a live process's assertion named "MSBD test stuck..." counts as one whose
            //  owner is gone -- the whole clear can be run on purpose; a real leak cannot be made: powerd drops a killed process's assertions)
            if ([name hasPrefix:@"MSBD test stuck"] && access(MSBD_SG_STATEDIR "/sg-test", F_OK) == 0) gone = YES;
#endif
            long level = [a[@"AssertLevel"] respondsToSelector:@selector(longValue)] ? [a[@"AssertLevel"] longValue] : 0;
            if (MSBDSGLiveOther(type.UTF8String, level, gone, !strcmp(proc, "powerd") || [owner isEqualToString:@"powerd"], owner.UTF8String)) {
                r.live++; [live addObject:[NSString stringWithFormat:@"%@ \"%@\" (%@ %d)", type, name, owner, pid]];
            }
            if (!MSBDSGStuck(type.UTF8String, level, gone)) continue;
            r.stuck++;
            [names addObject:[NSString stringWithFormat:@"%@ \"%@\" (pid %d, %@ gone)", type, name, pid, owner.length ? owner : @"owner"]];
        }
    }
    CFRelease(all);
    r.what = [names componentsJoinedByString:@"; "];
    r.liveWhat = [live componentsJoinedByString:@"; "];
    return r;
}
static BOOL SGOn(void) {
    CFPreferencesSynchronize(CFSTR(MSBD_SG_DOMAIN), CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_SG_KEY), CFSTR(MSBD_SG_DOMAIN), CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL on = !(v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v));   // (missing = on)
    if (v) CFRelease(v);
    return on;
}
static BOOL gSGScreenOff = NO;
static double gSGStuckSince = 0, gSGLastClear = 0;
static NSMutableArray<NSNumber *> *gSGClears;   // (the clears of the last 24 h, oldest first; kept in the state file)
// The clears older than a day go; a clear "in the future" (the wall clock set back since) counts as made now: the limits stay, for no longer.
static void SGPruneClears(double now) {
    NSMutableArray *keep = [NSMutableArray array];
    for (NSNumber *t in gSGClears) if (now - MIN(t.doubleValue, now) <= 86400) [keep addObject:@(MIN(t.doubleValue, now))];
    gSGClears = keep;
    if (gSGLastClear > now) gSGLastClear = now;
}
static MSBDSGAction gSGLastAction = kMSBDSGNothing;
static BOOL gSGLastClearFailed = NO;
static void SGWriteState(SGScan s, const char *why) {
    mkdir(MSBD_SG_STATEDIR, 0755);
    NSDictionary *d = @{ @"checked": @(time(NULL)), @"stuck": @(s.stuck), @"stuckSince": @(gSGStuckSince), @"what": s.what ?: @"",
                         @"live": @(s.live), @"liveWhat": s.liveWhat ?: @"",
                         @"lastClear": @(gSGLastClear), @"clearsToday": @(gSGClears.count), @"clearTimes": gSGClears ?: @[], @"action": @(gSGLastAction),
                         @"why": @(why ?: ""), @"lastClearFailed": @(gSGLastClearFailed),
                         @"cantSleep": @(MSBDSGShowCantSleep(s.stuck > 0, gSGLastAction, gSGLastClearFailed)) };
    [d writeToFile:@MSBD_SG_STATE atomically:YES];
    chmod(MSBD_SG_STATE, 0644);
    notify_post(MSBD_SG_UPDATED);
}
// The wakes powerd has scheduled, and those to schedule again after a restart: each one still ahead (a few seconds' margin) that is not back
// already (a client that re-armed by itself, PersistentConnection's timers do), with the same time, id and type -- so its owner can still
// cancel it (powerd matches all three). IOPMSchedulePowerEvent works as root, and the wake stays after the caller exits (17.5, 2 Nov).
static NSString *SGWakeKey(NSDictionary *e) {
    return [NSString stringWithFormat:@"%@|%@|%.3f", e[@"scheduledby"], e[@"eventtype"], [(NSDate *)e[@"time"] timeIntervalSinceReferenceDate]];
}
static BOOL SGWakeUsable(id e) {
    return [e isKindOfClass:[NSDictionary class]] && [e[@"time"] isKindOfClass:[NSDate class]] && [e[@"scheduledby"] isKindOfClass:[NSString class]]
        && [e[@"eventtype"] isKindOfClass:[NSString class]];
}
static NSArray<NSDictionary *> *SGWakesToSchedule(NSArray *before, NSArray *now, double t) {
    NSMutableSet *have = [NSMutableSet set];
    for (id e in now) if (SGWakeUsable(e)) [have addObject:SGWakeKey(e)];
    NSMutableArray *out = [NSMutableArray array];
    for (id e in before) {
        if (!SGWakeUsable(e) || [(NSDate *)e[@"time"] timeIntervalSinceReferenceDate] <= t + 2 || [have containsObject:SGWakeKey(e)]) continue;
        [have addObject:SGWakeKey(e)]; [out addObject:e];
    }
    return out;
}
static NSArray *SGCopyWakes(void) {
    static CFArrayRef (*copy)(void);
    if (!copy) { void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW); copy = io ? (CFArrayRef (*)(void))dlsym(io, "IOPMCopyScheduledPowerEvents") : NULL; }
    CFArrayRef a = copy ? copy() : NULL;
    return a ? CFBridgingRelease(a) : @[];
}
// Schedules again those of `before` the new powerd lacks; the count, and the refused ones in *refused.
static int SGRescheduleWakes(NSArray *before, int *refused) {
    static int (*sched)(CFDateRef, CFStringRef, CFStringRef);
    if (!sched) { void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW); sched = io ? (int (*)(CFDateRef, CFStringRef, CFStringRef))dlsym(io, "IOPMSchedulePowerEvent") : NULL; }
    int n = 0, bad = 0;
    for (NSDictionary *e in SGWakesToSchedule(before, SGCopyWakes(), CFAbsoluteTimeGetCurrent())) {
        if (sched && sched((__bridge CFDateRef)e[@"time"], (__bridge CFStringRef)e[@"scheduledby"], (__bridge CFStringRef)e[@"eventtype"]) == 0) n++;
        else bad++;
    }
    if (refused) *refused = bad;
    return n;
}
// powerd started over by launchd: every assertion and scheduled wake it held goes (see the top).
static BOOL SGRestartPowerd(void) {
    const char *lc = access("/var/jb/usr/bin/launchctl", X_OK) == 0 ? "/var/jb/usr/bin/launchctl" : "/bin/launchctl";
    char *argv[] = { (char *)"launchctl", (char *)"kickstart", (char *)"-k", (char *)"system/com.apple.powerd", NULL };
    pid_t pid; int st = -1;
    if (posix_spawn(&pid, lc, NULL, NULL, argv, environ) != 0) return NO;
    waitpid(pid, &st, 0);
    return WIFEXITED(st) && WEXITSTATUS(st) == 0;
}
static void SGCheck(NSString *why);
static unsigned gSGLookGen;   // (only the newest planned look runs: a screen-off and a confirmation planned close together made two looks)
static void SGCheckLater(double seconds, NSString *why) {
    unsigned gen = ++gSGLookGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gen == gSGLookGen) SGCheck(why); });
}
static void SGCheck(NSString *why) {
    @autoreleasepool {
        SGScan s = SGLook();
        double now = (double)time(NULL);
        SGPruneClears(now);
        if (!s.stuck) {
            SGLog(@"look (%@): nothing stuck%@", why, gSGStuckSince > 0 ? @" any more" : @"");
            gSGStuckSince = 0; gSGLastAction = kMSBDSGNothing; gSGLastClearFailed = NO;
            SGWriteState(s, "nothing stuck");
            return;
        }
        if (gSGStuckSince <= 0) { gSGStuckSince = now; SGLog(@"stuck (%@): %@", why, s.what); }
        const char *reason = NULL; double again = 0;
        MSBDSGAction a = MSBDSGDecide(gSGStuckSince, now, gSGScreenOff, s.live, SGOn(), gSGLastClear, (int)gSGClears.count,
                                      gSGClears.count ? gSGClears.firstObject.doubleValue : 0, &reason, &again);
        gSGLastAction = a;
        if (a != kMSBDSGClear) {
            NSString *more = again > 0 && gSGScreenOff ? [NSString stringWithFormat:@"; a look again in %.0f s", again] : @"";
            if (a == kMSBDSGBlocked) SGLog(@"not cleared: %s%@", reason, more);
            else if (gSGScreenOff) SGLog(@"waiting: %s%@%@", reason, s.live ? [@" -- " stringByAppendingString:s.liveWhat] : @"", more);
            if (again > 0 && gSGScreenOff) SGCheckLater(again, @"a look again");   // (the minute, the live one, the gap or the day's limit over)
            SGWriteState(s, reason);
            return;
        }
        SGLog(@"clearing: powerd started over (stuck for %.0f s: %@)", now - gSGStuckSince, s.what);
        gSGLastClear = now; [gSGClears addObject:@(now)];
        SGWriteState(s, "clearing");   // (counted in the state file first: the limits hold even if this helper starts over now)
        NSArray *wakes = SGCopyWakes();   // (the scheduled wakes, which the restart loses)
        BOOL ok = SGRestartPowerd();
        notify_post(MSBD_SG_POWERD);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{   // (powerd up again: the result)
            @autoreleasepool {
                int refused = 0, again = SGRescheduleWakes(wakes, &refused);
                if (refused) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{   // (once more, a little later)
                    int still = 0, late = SGRescheduleWakes(wakes, &still);
                    SGLog(@"scheduled wakes, second try: %d scheduled again, %d refused", late, still);
                });
                SGScan after = SGLook();
                gSGLastClearFailed = !ok || after.stuck > 0;
                SGLog(@"powerd %@; stuck now: %d%@; scheduled wakes: %lu before, %d scheduled again%@", ok ? @"started over" : @"NOT started over (launchctl failed)",
                      after.stuck, after.stuck ? [@" -- " stringByAppendingString:after.what] : @"", (unsigned long)wakes.count, again,
                      refused ? [NSString stringWithFormat:@", %d refused", refused] : @"");
                if (!after.stuck) gSGStuckSince = 0;
                SGWriteState(after, gSGLastClearFailed ? "cleared, but still stuck" : "cleared");
            }
        });
    }
}
static void SGScreenChanged(BOOL off) {
    gSGScreenOff = off;
    if (off) SGCheckLater(5, @"the screen went off");   // (one look; more only when something is stuck)
}
// The clears of the last 24 h from the state file: the limits hold across this helper's restarts (sshtoggled starts over after a cfprefsd
// restart, an upgrade, a userspace reboot). A state file with only lastClear (no clearTimes) counts that one.
static void SGLoadClears(double now) {
    NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:@MSBD_SG_STATE];
    if (![st isKindOfClass:[NSDictionary class]]) st = nil;
    gSGClears = [NSMutableArray array];
    for (id t in [st[@"clearTimes"] isKindOfClass:[NSArray class]] ? st[@"clearTimes"] : @[])
        if ([t isKindOfClass:[NSNumber class]] && [t doubleValue] > 0) [gSGClears addObject:@([t doubleValue])];
    [gSGClears sortUsingSelector:@selector(compare:)];
    gSGLastClear = [st[@"lastClear"] isKindOfClass:[NSNumber class]] ? MAX([st[@"lastClear"] doubleValue], 0) : 0;
    if (gSGLastClear > 0 && (!gSGClears.count || gSGClears.lastObject.doubleValue < gSGLastClear - 1)) [gSGClears addObject:@(gSGLastClear)];
    SGPruneClears(now);
}
static void SGStart(void) {
    double now = (double)time(NULL);
    SGLoadClears(now);
    if (gSGClears.count || gSGLastClear > 0)
        SGLog(@"started: %lu clear(s) in the last 24 h, the last %.0f s ago", (unsigned long)gSGClears.count, gSGLastClear > 0 ? now - gSGLastClear : -1);
    int t1 = 0, t2 = 0;
    notify_register_dispatch(MSBD_SG_CHECK, &t1, dispatch_get_main_queue(), ^(int t) { SGCheck(@"Settings asked"); });
    notify_register_dispatch(MSBD_SG_CHANGED, &t2, dispatch_get_main_queue(), ^(int t) { SGLog(@"Sleep Guard switched %@", SGOn() ? @"on" : @"off"); SGCheck(@"the switch changed"); });
}
