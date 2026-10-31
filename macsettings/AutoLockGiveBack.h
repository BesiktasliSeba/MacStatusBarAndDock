// AutoLockGiveBack.h -- SpringBoard's side of "2 hours left behind" (1.7.3, item 9; the rule: AutoLockLongest.h MSAutoLockDecide). Included by the two
// SpringBoard parts: MacSettingsBadge (AutoLockTimer.x, the part that keeps 2 hours: it gives it back) and the Dock (MacDock line, Dock.x: it runs
// while MacStatusBar is switched off, so it lowers 2 hours when the keeping part is not in this SpringBoard).
// The stored time is ManagedConfiguration's maxInactivity, changed only the way Settings' Auto-Lock list changes it: -[MCProfileConnection
// setValue:forSetting:] in SpringBoard, which may (Settings' own call; SpringBoard holds ManagedConfiguration's entitlement) -- profiled checks
// the value, writes its files and tells everyone. A maintainer script has no safe way of its own (root without that entitlement; profiled's files
// are its own), so removal and switch-off go through here: the root helper writes its marker and posts MS_AUTOLOCK_CHECK, while our code still runs.
// Off the main thread (the setter waits for profiled); one look at a time.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
#include <notify.h>
#include <os/lock.h>
#import "AutoLockLongest.h"

static inline id MSALGBConnection(SEL *get, SEL *set) {   // (ManagedConfiguration as on 15-18: the shared connection and both methods as typed, or nil)
    Class mc = objc_getClass("MCProfileConnection");
    SEL shared = NSSelectorFromString(@"sharedConnection"), g = NSSelectorFromString(@"effectiveValueForSetting:"), s = NSSelectorFromString(@"setValue:forSetting:");
    Method mg = mc ? class_getInstanceMethod(mc, g) : NULL, ms = mc ? class_getInstanceMethod(mc, s) : NULL;
    if (!mc || ![mc respondsToSelector:shared] || !mg || !ms || strcmp(method_getTypeEncoding(mg), "@24@0:8@16") || strcmp(method_getTypeEncoding(ms), "v32@0:8@16@24")) return nil;
    *get = g; *set = s;
    return ((id (*)(id, SEL))objc_msgSend)((id)mc, shared);
}
static inline double MSALGBRecord(void) {
    CFPreferencesSynchronize(CFSTR(MS_AUTOLOCK_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MS_AUTOLOCK_RECORD), CFSTR(MS_AUTOLOCK_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    double r = v && CFGetTypeID(v) == CFNumberGetTypeID() ? [(__bridge NSNumber *)v doubleValue] : (v ? -1.0 : 0.0);   // (-1: something else there -- forgotten)
    if (v) CFRelease(v);
    return r;
}
static inline void MSALGBSetRecord(double seconds) {
    CFPreferencesSetValue(CFSTR(MS_AUTOLOCK_RECORD), seconds > 0 ? (__bridge CFNumberRef)@(seconds) : NULL, CFSTR(MS_AUTOLOCK_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR(MS_AUTOLOCK_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
// The root helper's marker: switched off (its text: in what), or "removal". Only a regular file of root's counts (mobile can't make one there).
static inline BOOL MSALGBLeaving(BOOL *removing) {
    struct stat st;
    *removing = NO;
    if (lstat(MS_AUTOLOCK_OFF_MARKER, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0) return NO;
    NSString *how = [NSString stringWithContentsOfFile:@MS_AUTOLOCK_OFF_MARKER encoding:NSUTF8StringEncoding error:nil];
    *removing = [how hasPrefix:@"removal"];
    return YES;
}
// One look: kept = this SpringBoard keeps our longer times. `log`: where a change is told (the part's own log), may be nil.
static inline void MSAutoLockSettle(BOOL kept, NSString *why, void (^log)(NSString *line)) {
    static dispatch_queue_t q; static dispatch_once_t once; static BOOL pending; static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    dispatch_once(&once, ^{ q = dispatch_queue_create("msbd.autolock.settle", DISPATCH_QUEUE_SERIAL); });
    os_unfair_lock_lock(&lock);
    BOOL already = pending; pending = YES;
    os_unfair_lock_unlock(&lock);
    if (already) return;   // (a burst of posts: one look -- the one waiting reads the state as it is when it runs)
    dispatch_async(q, ^{
        os_unfair_lock_lock(&lock); pending = NO; os_unfair_lock_unlock(&lock);
        @autoreleasepool {
            SEL get = NULL, set = NULL;
            id conn = MSALGBConnection(&get, &set);
            if (!conn) { if (log) log([NSString stringWithFormat:@"[autolock] %@: ManagedConfiguration not as expected -- the stored Auto-Lock is left as it is", why]); return; }
            BOOL removing = NO, leaving = MSALGBLeaving(&removing);
            id v = ((id (*)(id, SEL, id))objc_msgSend)(conn, get, @"maxInactivity");
            double stored = [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : NAN, record = MSALGBRecord();
            MSAutoLockStep step = MSAutoLockDecide(stored, kept, leaving, removing, record);
            if (step == MSAutoLockStay) return;
            if (step == MSAutoLockLower || step == MSAutoLockLowerAndRecord) {
                if (step == MSAutoLockLowerAndRecord) MSALGBSetRecord(stored);   // (first: a crash in between never loses the user's 2 hours)
                ((void (*)(id, SEL, id, id))objc_msgSend)(conn, set, @((NSInteger)MS_AUTOLOCK_STOCK_LONGEST), @"maxInactivity");
                if (step == MSAutoLockLower && record != 0) MSALGBSetRecord(0);
            } else if (step == MSAutoLockGiveBack) {
                ((void (*)(id, SEL, id, id))objc_msgSend)(conn, set, @((NSInteger)record), @"maxInactivity");
                MSALGBSetRecord(0);
            } else MSALGBSetRecord(0);
            id after = ((id (*)(id, SEL, id))objc_msgSend)(conn, get, @"maxInactivity");
            if (log) log([NSString stringWithFormat:@"[autolock] %@: stored %.0f s, %@, %@%@ -> %@ (now %@ s)", why, stored, kept ? @"kept here" : @"NOT kept here",
                          leaving ? (removing ? @"being removed" : @"switched off") : @"on", record != 0 ? [NSString stringWithFormat:@", lowered from %.0f before", record] : @"",
                          step == MSAutoLockLower ? @"lowered to 1 hour" : step == MSAutoLockLowerAndRecord ? @"lowered to 1 hour, to give back later" :
                          step == MSAutoLockGiveBack ? @"given back" : @"record forgotten (another time picked, or removed)", after]);
        }
    });
}
// The Dock's SpringBoard part (Dock.x's %ctor): it runs while MacStatusBar is switched off -- exactly when the part that keeps 2 hours is not in this
// SpringBoard (its pid in MS_AUTOLOCK_LONG_STATE is another process's, or 0). Then, and only then, it looks: 2 hours lowered to 1 hour. With the
// keeping part here, that part looks itself.
static inline BOOL MSALGBKeptHere(void) {
    int token = 0; uint64_t pid = 0;
    if (notify_register_check(MS_AUTOLOCK_LONG_STATE, &token) != NOTIFY_STATUS_OK) return NO;
    notify_get_state(token, &pid);
    notify_cancel(token);
    return pid == (uint64_t)getpid();
}
static inline void MSAutoLockWatchFromDock(void (^log)(NSString *line)) {
    static int token = 0;
    if (token) return;
    void (^look)(NSString *) = ^(NSString *why) { if (!MSALGBKeptHere()) MSAutoLockSettle(NO, why, log); };
    notify_register_dispatch(MS_AUTOLOCK_CHECK, &token, dispatch_get_main_queue(), ^(int t) { look(@"the Dock's part, asked"); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ look(@"the Dock's part, start"); });   // (after the other part's start)
}
