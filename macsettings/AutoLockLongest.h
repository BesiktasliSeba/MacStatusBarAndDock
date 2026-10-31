// AutoLockLongest.h -- shared by the two sides of the longer Auto-Lock times: AutoLock.x (Settings, the list) and AutoLockTimer.x (SpringBoard, the
// idle timer that keeps them).
#pragma once
#import <notify.h>
#import <sys/sysctl.h>
#import <string.h>
#import <math.h>

#define MS_AUTOLOCK_LONGEST 7200.0   // (2 hours: the longest time the list offers)
#define MS_AUTOLOCK_LONG_STATE "com.besiktasliseba.macsettings.autolock.kept"   // (notify state: the pid of the SpringBoard whose idle timer keeps them)

// SpringBoard: after its own step, is this a time of ours that the step made "never"? (t: the Auto-Lock in seconds; total: the timer's total
// interval after the step -- DBL_MAX for never.) Never itself (2147483647) and anything longer than our longest stay never.
static inline BOOL MSAutoLockKeepsTime(double t, double total) { return isfinite(t) && t > 0 && t <= MS_AUTOLOCK_LONGEST && total >= 1e9; }

// Settings: is a running SpringBoard keeping the longer times? (its published pid is a live SpringBoard; the state is read, not kept registered)
static inline BOOL MSAutoLockLongTimesKept(void) {
    int token = 0; uint64_t pid = 0;
    if (notify_register_check(MS_AUTOLOCK_LONG_STATE, &token) != NOTIFY_STATUS_OK) return NO;
    notify_get_state(token, &pid);
    notify_cancel(token);
    if (!pid || pid > INT32_MAX) return NO;
    struct kinfo_proc kp; size_t len = sizeof kp; int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)pid };
    memset(&kp, 0, sizeof kp);
    return sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len == sizeof kp && !strcmp(kp.kp_proc.p_comm, "SpringBoard");
}
