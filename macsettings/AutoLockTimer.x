// AutoLockTimer.x -- the SpringBoard side of the longer Auto-Lock times (AutoLock.x adds 30 minutes, 1 hour and 2 hours to Settings > Display &
// Brightness > Auto-Lock). Part of MacSettingsBadge, the Settings part that SpringBoard loads.
//
// SpringBoard turns the chosen time (ManagedConfiguration's maxInactivity) into its idle timer in -[SBIdleTimerDescriptorFactory
// updateIdleTimerSettingsForAutoLockTimeout:]. A time up to its maximum (3600 s on 15.6.1 and 16.7.7) becomes the timer's total interval; a longer one
// is taken for Never (Never is stored as 2147483647): the total and warn intervals both become "never" (15.6.1's own log: "is gt MAX_TOTAL_INTERVAL;
// setting totalInterval and warnInterval to <never>"). So 2 hours was Never: the iPad did not go to sleep on its own at all (1.7.2 item 18: left awake
// all night after a video in a window -- the video and the window were not the cause). After SpringBoard's own step, a "never" that came from a time
// up to our longest is given the time back as the total interval, with the warn interval the step had before -- what the step does for an hour. Never
// itself, and anything longer than our longest, stays never; every later step runs as before (Low Power Mode, Telephony, the sanity checks, and
// Apple's Home Screen rule that halves the time while Face ID / Touch ID is set up: 2 hours is 1 hour on the Home Screen, as 2 minutes is 1 minute).
// Published as a notify state (this SpringBoard's pid): AutoLock.x offers the longer times only while a SpringBoard keeps them.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <unistd.h>
#import "AutoLockLongest.h"
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif

static BOOL MSALTSig(Class c, SEL s, const char *enc) { Method m = c ? class_getInstanceMethod(c, s) : NULL; return m && !strcmp(method_getTypeEncoding(m), enc); }
static double MSALTInterval(id desc, SEL s) { return ((double (*)(id, SEL))objc_msgSend)(desc, s); }
// The Auto-Lock time SpringBoard read in the same step: its state monitor's autoLockTimeout, an NSNumber of seconds (NAN = none)
static double MSALTTimeout(id factory) {
    Ivar iv = class_getInstanceVariable(object_getClass(factory), "_stateMonitor");
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    id mon = t && t[0] == '@' ? object_getIvar(factory, iv) : nil;
    if (!mon) { Class mc = objc_getClass("SBIdleTimerGlobalStateMonitor"); if ([mc respondsToSelector:@selector(sharedInstance)]) mon = ((id (*)(id, SEL))objc_msgSend)((id)mc, @selector(sharedInstance)); }
    SEL s = NSSelectorFromString(@"autoLockTimeout");
    id v = MSALTSig([mon class], s, "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(mon, s) : nil;
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : NAN;
}

%group MSAutoLockTimer
%hook SBIdleTimerDescriptorFactory
- (BOOL)updateIdleTimerSettingsForAutoLockTimeout:(id)desc {
    double warnBefore = MSALTInterval(desc, @selector(warnInterval));
    BOOL r = %orig;
    if (MSTestFlag("/tmp/ms-autolocktimer-off")) return r;   // (debug: SpringBoard's own behaviour, for comparison)
    double t = MSALTTimeout(self), total = MSALTInterval(desc, @selector(totalInterval));
    if (MSAutoLockKeepsTime(t, total)) {   // (our time, made "never" by the step: DBL_MAX)
        ((void (*)(id, SEL, double))objc_msgSend)(desc, @selector(setTotalInterval:), t);
        ((void (*)(id, SEL, double))objc_msgSend)(desc, @selector(setWarnInterval:), warnBefore);
#if DEBUG
        if (MSTestFlag("/tmp/macsettings-debug")) { FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fprintf(f, "autolock: SpringBoard's never for %.0f s -> total %.0f s, warn %g s\n", t, t, warnBefore); fclose(f); } }
#endif
    }
    return r;
}
%end
%end

%ctor {
    Class f = objc_getClass("SBIdleTimerDescriptorFactory"), d = objc_getClass("SBIdleTimerDescriptor");
    BOOL ok = MSALTSig(f, NSSelectorFromString(@"updateIdleTimerSettingsForAutoLockTimeout:"), "B24@0:8@16")
           && MSALTSig(d, @selector(totalInterval), "d16@0:8") && MSALTSig(d, @selector(warnInterval), "d16@0:8")
           && MSALTSig(d, NSSelectorFromString(@"setTotalInterval:"), "v24@0:8d16") && MSALTSig(d, NSSelectorFromString(@"setWarnInterval:"), "v24@0:8d16");
    int token = 0;
    if (notify_register_check(MS_AUTOLOCK_LONG_STATE, &token) != NOTIFY_STATUS_OK) token = 0;
    if (!ok) { if (token) notify_set_state(token, 0); return; }   // (not as on 15-18: the longer times are not offered)
    %init(MSAutoLockTimer);
    if (token) notify_set_state(token, (uint64_t)getpid());   // (kept registered: the state lives as long as this SpringBoard)
}
