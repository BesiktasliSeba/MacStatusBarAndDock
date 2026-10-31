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

// ---- 2 hours left behind (1.7.3, item 9) ----
// Stock SpringBoard takes a stored Auto-Lock over 1 hour for Never: our 2 hours, kept by AutoLockTimer.x, would leave the iPad awake for good once
// nothing of ours keeps it -- the tweak removed, or our SpringBoard part gone (MacStatusBar switched off in Choicy / iCleaner Pro, the part held
// back by the crash guard). So whenever a SpringBoard runs our code but not the keeping (or is about to stop running it), a stored 2 hours goes
// down to 1 hour, the longest time stock SpringBoard keeps, through ManagedConfiguration as Settings' list stores it (AutoLockGiveBack.h); and it
// is given back when a SpringBoard keeps it again, if the user has not picked another time meanwhile. Removal gives nothing back later.
#define MS_AUTOLOCK_STOCK_LONGEST 3600.0   // (1 hour: stock SpringBoard's longest kept time, MAX_TOTAL_INTERVAL on 15-18)
#define MS_AUTOLOCK_CHECK "com.besiktasliseba.macsettings.autolock.check"   // (the root helper: removed, switched off or on -- look again; carries nothing)
#define MS_AUTOLOCK_OFF_MARKER "/var/jb/var/lib/sshtoggled-engines/msb-off-restored"   // (root's: MacStatusBar switched off; "removal" while being removed)
#define MS_AUTOLOCK_DOMAIN "com.besiktasliseba.macsettings"
#define MS_AUTOLOCK_RECORD "autoLockLoweredFrom"   // (the time we lowered to 1 hour, to give back; in MS_AUTOLOCK_DOMAIN)
typedef enum { MSAutoLockStay = 0, MSAutoLockLower, MSAutoLockLowerAndRecord, MSAutoLockGiveBack, MSAutoLockForget } MSAutoLockStep;
// stored: ManagedConfiguration's maxInactivity (s; NAN unknown); kept: this SpringBoard keeps our longer times (its hook is in); leaving: the
// root helper's off marker is there (switched off, or being removed: removing); record: the time we lowered earlier (0: none).
static inline MSAutoLockStep MSAutoLockDecide(double stored, BOOL kept, BOOL leaving, BOOL removing, double record) {
    BOOL ours = isfinite(stored) && stored > MS_AUTOLOCK_STOCK_LONGEST && stored <= MS_AUTOLOCK_LONGEST;   // (2 hours: Never for stock SpringBoard)
    BOOL recorded = isfinite(record) && record > MS_AUTOLOCK_STOCK_LONGEST && record <= MS_AUTOLOCK_LONGEST;
    if (leaving || !kept) {
        if (ours) return removing ? MSAutoLockLower : MSAutoLockLowerAndRecord;
        return removing && record != 0 ? MSAutoLockForget : MSAutoLockStay;   // (removed: nothing is given back later)
    }
    if (record == 0) return MSAutoLockStay;
    return recorded && stored == MS_AUTOLOCK_STOCK_LONGEST ? MSAutoLockGiveBack : MSAutoLockForget;   // (another time picked meanwhile: the user's stays)
}

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
