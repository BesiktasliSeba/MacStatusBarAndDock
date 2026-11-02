#!/bin/bash
# Mac test of the Sleep Guard (battery drain F1): its rules (common/SleepGuard.h, test-sleepguard.c) and the helper's wiring
# (macsettings/sshtoggled/SleepGuardDaemon.h): one look when the screen goes off and nothing more unless something is stuck; the owner gone by
# pid, name and start time (pids are reused); never cleared with the screen on or while something else keeps the iPad awake (a powerd restart
# would cut it off); a look planned for when a wait or a limit ends; the clear is powerd started over by launchd, counted in the state file
# first, the scheduled wakes it loses scheduled again, then a look to confirm; the clears read back at the helper's start; the state written
# for Settings and Settings told.
# Compiled: the rules; the helper's proc_bsdinfo stand-in against the macOS SDK's own (same XNU struct) and a live read of this test's process;
# the helper's own SGPruneClears / SGWriteState / SGLoadClears (taken out of the header) round-tripping the clears through a state file, and
# its SGWakesToSchedule choosing the wakes to schedule again.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/tsg" test-sleepguard.c && "$W/tsg" || fails=1
D=../macsettings/sshtoggled/SleepGuardDaemon.h; M=../macsettings/sshtoggled/main.m

# ---- the helper's proc_bsdinfo stand-in (the iOS SDK has no sys/proc_info.h) against the real one
awk '/^#define SG_PROC_PIDTBSDINFO /' $D > "$W/bsd.inc"
awk '/^struct sg_proc_bsdinfo \{/,/^\};/' $D >> "$W/bsd.inc"
cat > "$W/tbsd.c" <<'EOF'
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include "bsd.inc"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    check("struct sg_proc_bsdinfo: the size and the fields read (pbi_comm, pbi_name, pbi_start_tvsec/usec) where XNU's proc_bsdinfo has them",
          sizeof(struct sg_proc_bsdinfo) == sizeof(struct proc_bsdinfo)
          && offsetof(struct sg_proc_bsdinfo, pbi_comm) == offsetof(struct proc_bsdinfo, pbi_comm)
          && offsetof(struct sg_proc_bsdinfo, pbi_name) == offsetof(struct proc_bsdinfo, pbi_name)
          && offsetof(struct sg_proc_bsdinfo, pbi_start_tvsec) == offsetof(struct proc_bsdinfo, pbi_start_tvsec)
          && offsetof(struct sg_proc_bsdinfo, pbi_start_tvusec) == offsetof(struct proc_bsdinfo, pbi_start_tvusec));
    check("SG_PROC_PIDTBSDINFO = PROC_PIDTBSDINFO", SG_PROC_PIDTBSDINFO == PROC_PIDTBSDINFO);
    struct sg_proc_bsdinfo bi; memset(&bi, 0, sizeof bi);
    int n = proc_pidinfo(getpid(), SG_PROC_PIDTBSDINFO, 0, &bi, sizeof bi);
    time_t now = time(NULL);
    check("read live through it: this test's pid, its name, started within the last minute",
          n == (int)sizeof bi && bi.pbi_pid == (uint32_t)getpid() && !strncmp(bi.pbi_comm, "tbsd", 4)
          && (time_t)bi.pbi_start_tvsec <= now && now - (time_t)bi.pbi_start_tvsec < 60);
    return fails;
}
EOF
clang -O0 -Wall -I"$W" -o "$W/tbsd" "$W/tbsd.c" && "$W/tbsd" || fails=1

# ---- the clears: kept in the state file, read back at the helper's start (the helper's own functions, against a state file here)
awk '/^typedef struct \{ int stuck, live; NSString \*what, \*liveWhat; \} SGScan;/' $D > "$W/sg.inc"
awk '/^static BOOL gSGScreenOff = NO;/,/^static void SGWriteState\(SGScan s, const char \*why\) \{/' $D | sed '$d' >> "$W/sg.inc"
awk '/^static void SGWriteState\(SGScan s, const char \*why\) \{/,/^}/' $D >> "$W/sg.inc"
awk '/^static void SGLoadClears\(double now\) \{/,/^}/' $D >> "$W/sg.inc"
awk '/^static NSString \*SGWakeKey\(NSDictionary \*e\) \{/,/^}/' $D >> "$W/sg.inc"
awk '/^static BOOL SGWakeUsable\(id e\) \{/,/^}/' $D >> "$W/sg.inc"
awk '/^static NSArray<NSDictionary \*> \*SGWakesToSchedule\(NSArray \*before, NSArray \*now, double t\) \{/,/^}/' $D >> "$W/sg.inc"
cat > "$W/tsgstate.m" <<'EOF'
#import <Foundation/Foundation.h>
#include <notify.h>
#include <sys/stat.h>
#include "../common/SleepGuard.h"
#undef MSBD_SG_STATEDIR
#undef MSBD_SG_STATE
#define MSBD_SG_STATEDIR SG_TEST_DIR
#define MSBD_SG_STATE    SG_TEST_DIR "/sleepguard.plist"
#define MSBD_SG_UPDATED  "com.besiktasliseba.sleepguard.test-updated"
#include "sg.inc"
static int fails = 0;
static void check(const char *what, BOOL ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static void put(NSDictionary *d) { [d writeToFile:@MSBD_SG_STATE atomically:YES]; }
int main(void) {
    @autoreleasepool {
        double now = 1793000000;
        put(@{ @"clearTimes": @[@(now - 90000), @(now - 36000), @(now - 3600)], @"lastClear": @(now - 3600), @"clearsToday": @3 });
        SGLoadClears(now);
        check("the state file's clears read back: the two of the last 24 h (one 25 h old dropped), the last one's time",
              gSGClears.count == 2 && gSGClears[0].doubleValue == now - 36000 && gSGLastClear == now - 3600);
        SGScan s = { 1, 0, @"SystemIsActive \"x\" (pid 5, SpringBoard gone)", @"" };
        gSGLastClear = now; [gSGClears addObject:@(now)];
        SGWriteState(s, "clearing");
        gSGClears = nil; gSGLastClear = 0;
        SGLoadClears(now + 60);
        check("a clear written, the helper started over: all three back (the 30-minute gap and the day's count hold)",
              gSGClears.count == 3 && gSGLastClear == now && gSGClears.lastObject.doubleValue == now);
        NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:@MSBD_SG_STATE];
        check("  ... the file has the times and the count", [st[@"clearTimes"] count] == 3 && [st[@"clearsToday"] intValue] == 3 && [st[@"lastClear"] doubleValue] == now);
        SGLoadClears(now + 50400 + 1);   // (the first of them 24 h and 1 s old)
        check("a day later only the clears of the last 24 h count", gSGClears.count == 2);
        put(@{ @"clearTimes": @[@(now + 7200)], @"lastClear": @(now + 7200) });
        SGLoadClears(now);
        check("clears \"in the future\" (the wall clock set back since): counted as made now, not for longer",
              gSGClears.count == 1 && gSGClears[0].doubleValue == now && gSGLastClear == now);
        put(@{ @"lastClear": @(now - 600) });
        SGLoadClears(now);
        check("a state file with only lastClear (no clearTimes): that clear counts", gSGClears.count == 1 && gSGLastClear == now - 600);
        put(@{ @"clearTimes": @"garbage", @"lastClear": @"x" });
        SGLoadClears(now);
        check("a broken state file: no clears", gSGClears.count == 0 && gSGLastClear == 0);
        put(@{ @"clearTimes": @[@"1792999000", @{}, @(now - 600)] });
        SGLoadClears(now);
        check("  ... entries that are not numbers skipped", gSGClears.count == 1 && gSGClears[0].doubleValue == now - 600);
        [[NSFileManager defaultManager] removeItemAtPath:@MSBD_SG_STATE error:nil];
        SGLoadClears(now);
        check("no state file: no clears", gSGClears.count == 0 && gSGLastClear == 0);
        // the scheduled wakes a powerd restart loses (the 17.5's four, 2 Nov), taken again: SGWakesToSchedule(before, after, now)
        double t = 815000000;   // (reference-date seconds)
        NSDictionary *(^W)(NSString *, double) = ^(NSString *by, double at) { return @{ @"scheduledby": by, @"eventtype": @"wake", @"time": [NSDate dateWithTimeIntervalSinceReferenceDate:at], @"appPID": @1445 }; };
        NSArray *before = @[ W(@"com.apple.persistentconnection[locationd,1487,0xad0e8ee80,com.apple.locationd.durianPersistentConnectionMaintenance]", t + 360),
                             W(@"com.apple.persistentconnection[apsd,1535,0xe34895260,com.apple.apsd(push.apple.com)-NonCellular]", t + 1140),
                             W(@"com.apple.alarm.user-invisible-com.apple.ContextStore.com.apple.softwareupdateservicesd.activity.autoScan.1793602705.496093", t + 4800),
                             W(@"com.apple.alarm.user-visible-com.apple.remindd.time-alarm", t + 2400000) ];
        NSArray *all = SGWakesToSchedule(before, @[], t);
        check("all four lost (the new powerd lists none): all four scheduled again", all.count == 4);
        NSArray *some = SGWakesToSchedule(before, @[ before[0] ], t);
        check("  ... one already back (locationd re-armed by itself, the same time): the other three", some.count == 3 && ![some containsObject:before[0]]);
        NSArray *moved = SGWakesToSchedule(before, @[ W(before[0][@"scheduledby"], t + 900) ], t);
        check("  ... a client back with another time: its old one still scheduled (an extra wake, never a missing one)", moved.count == 4);
        NSArray *past = SGWakesToSchedule(@[ W(@"a", t - 5), W(@"b", t + 1), W(@"c", t + 3) ], @[], t);
        check("  ... the ones already due (or within 2 s): not", past.count == 1 && [past[0][@"scheduledby"] isEqual:@"c"]);
        NSArray *odd = SGWakesToSchedule(@[ @{ @"scheduledby": @"x", @"eventtype": @"wake" }, @{ @"time": [NSDate dateWithTimeIntervalSinceReferenceDate:t + 60], @"eventtype": @"wake" },
                                            @"garbage", W(@"ok", t + 60), W(@"ok", t + 60) ], @[ @"garbage" ], t);
        check("  ... entries without a time, an id or a type skipped; one listed twice scheduled once", odd.count == 1 && [odd[0][@"scheduledby"] isEqual:@"ok"]);
    }
    return fails;
}
EOF
mkdir -p "$W/state"
clang -O0 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -I. -DSG_TEST_DIR="\"$W/state\"" -framework Foundation -o "$W/tsgstate" "$W/tsgstate.m" \
  && "$W/tsgstate" || fails=1

check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
CK="awk '/^static void SGCheck\\(NSString \\*why\\) \\{/,/^}/' $D"
check "the screen going off asks for one look 5 s later; the only other planned look is the rules' own" \
  "awk '/^static void SGScreenChanged\\(BOOL off\\) \\{/,/^}/' $D | grep -q 'if (off) SGCheckLater(5, @\"the screen went off\");' && [ \$(grep -c 'SGCheckLater(' $D) = 3 ]"
check "  ... only the newest planned look runs (no two looks for one screen-off and its confirmation)" \
  "awk '/^static void SGCheckLater\\(double seconds, NSString \\*why\\) \\{/,/^}/' $D | grep -q 'if (gen == gSGLookGen) SGCheck(why);'"
check "  ... another look is planned only with the screen off, when the rules give a time (the minute, the live one, the gap, the day's limit)" \
  "$CK | grep -q 'if (again > 0 && gSGScreenOff) SGCheckLater(again, @\"a look again\");'"
check "every look is logged (\"look (...): nothing stuck\" too: the guard's own record that it did not act; waits and blocks with why)" \
  "grep -q 'SGLog(@\"look (%@): nothing stuck%@\", why, gSGStuckSince > 0 ? @\" any more\" : @\"\");' $D && $CK | grep -q 'SGLog(@\"not cleared: %s%@\", reason, more);' && $CK | grep -q 'else if (gSGScreenOff) SGLog(@\"waiting: %s%@%@\", reason, s.live ?'"
check "nothing stuck: the state written, nothing more" \
  "$CK | awk '/if \\(!s.stuck\\) \\{/{a=NR} /SGWriteState\\(s, \"nothing stuck\"\\);/{b=NR} /return;/&&a&&!c{c=NR} END{exit !(a && b > a && c > b)}'"
check "the decision is MSBDSGDecide's: the screen, what else keeps the iPad awake, the switch, the limits (the oldest clear of the day)" \
  "$CK | grep -q 'MSBDSGAction a = MSBDSGDecide(gSGStuckSince, now, gSGScreenOff, s.live, SGOn(), gSGLastClear, (int)gSGClears.count,' && $CK | grep -q 'gSGClears.count ? gSGClears.firstObject.doubleValue : 0, &reason, &again);'"
check "  ... only kMSBDSGClear clears" "$CK | grep -q 'if (a != kMSBDSGClear) {'"
check "the clear: launchd starts powerd over (kickstart -k system/com.apple.powerd), the only call that runs a program" \
  "grep -q '(char \\*)\"kickstart\", (char \\*)\"-k\", (char \\*)\"system/com.apple.powerd\"' $D && [ \$(grep -c 'posix_spawn(' $D) = 1 ]"
check "  ... counted and written to the state file before powerd goes (the limits hold if the helper starts over)" \
  "$CK | awk '/gSGLastClear = now; \\[gSGClears addObject:@\\(now\\)\\];/{a=NR} /SGWriteState\\(s, \"clearing\"\\);/{b=NR} /BOOL ok = SGRestartPowerd\\(\\);/{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... the scheduled wakes copied before powerd goes; 3 s later the ones still ahead and not back scheduled again, then the look" \
  "$CK | awk '/NSArray \\*wakes = SGCopyWakes\\(\\);/{a=NR} /BOOL ok = SGRestartPowerd\\(\\);/{b=NR} /int refused = 0, again = SGRescheduleWakes\\(wakes, &refused\\);/{c=NR} /SGScan after = SGLook\\(\\);/{d=NR} END{exit !(a && b > a && c > b && d > c)}' && awk '/^static int SGRescheduleWakes\\(NSArray \\*before, int \\*refused\\) \\{/,/^}/' $D | grep -q 'for (NSDictionary \\*e in SGWakesToSchedule(before, SGCopyWakes(), CFAbsoluteTimeGetCurrent()))'"
check "  ... refused ones tried once more 5 s later; the counts logged" \
  "$CK | grep -q 'if (refused) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 \\* NSEC_PER_SEC)' && $CK | grep -q 'scheduled wakes: %lu before, %d scheduled again%@'"
check "  ... then a look 3 s later to confirm, logged and written" \
  "$CK | awk '/BOOL ok = SGRestartPowerd\\(\\);/{a=NR} /dispatch_after\\(dispatch_time\\(DISPATCH_TIME_NOW, 3 \\* NSEC_PER_SEC\\)/{b=NR} /SGScan after = SGLook\\(\\);/{c=NR} END{exit !(a && b > a && c > b)}'"
LK="awk '/^static SGScan SGLook\\(void\\) \\{/,/^}/' $D"
check "owner gone = MSBDSGOwnerGone: no process at the pid (kill 0 fails without EPERM), another name, or started after the assertion" \
  "$LK | grep -q 'BOOL exists = pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);' && $LK | grep -q 'proc_pidinfo(pid, SG_PROC_PIDTBSDINFO, 0, &bi, sizeof bi) == (int)sizeof bi;' && $LK | grep -q 'if (exists) proc_name(pid, proc, sizeof proc);' && $LK | grep -q 'double made = \\[a\\[@\"AssertStartWhen\"\\] isKindOfClass:\\[NSDate class\\]\\] ? \\[(NSDate \\*)a\\[@\"AssertStartWhen\"\\] timeIntervalSince1970\\] : 0;' && $LK | grep -q 'BOOL gone = MSBDSGOwnerGone(pid, exists, proc, owner.UTF8String, started, awake, made, now);'"
check "  ... the process's awake time from its start on the clock that stops in sleep (rusage's start, mach_absolute_time)" \
  "awk '/^static double SGAwakeAge\\(int pid\\) \\{/,/^}/' $D | grep -q 'proc_pid_rusage(pid, RUSAGE_INFO_V0, &ri) != 0' && $LK | grep -q 'awake = exists ? SGAwakeAge(pid) : -1;'"
check "stuck = MSBDSGStuck(type, level, gone); something else awake = MSBDSGLiveOther, powerd's own told apart by name" \
  "$LK | grep -q 'if (!MSBDSGStuck(type.UTF8String, level, gone)) continue;' && $LK | grep -q 'if (MSBDSGLiveOther(type.UTF8String, level, gone, !strcmp(proc, \"powerd\") || \\[owner isEqualToString:@\"powerd\"\\], owner.UTF8String)) {' && $LK | grep -q 'r.live++;'"
check "  ... the test switch (an assertion named MSBD test stuck..., a root-owned file) only in debug builds, after the real rule" \
  "$LK | awk '/BOOL gone = MSBDSGOwnerGone/{a=NR} /^#if DEBUG/&&a&&!d{d=NR} /sg-test/{t=NR} /^#endif/&&d&&!e{e=NR} END{exit !(a && d > a && t > d && e > t)}'"
check "the clears kept: the state file has their times; the helper reads them back at its start, before it listens" \
  "awk '/^static void SGWriteState\\(/,/^}/' $D | grep -q '@\"clearTimes\": gSGClears ?: @\\[\\]' && awk '/^static void SGStart\\(void\\) \\{/,/^}/' $D | awk '/SGLoadClears\\(now\\);/{a=NR} /notify_register_dispatch/&&!b{b=NR} END{exit !(a && b > a)}'"
check "  ... and every look drops the ones older than a day first" "$CK | awk 'NR<6' | grep -q 'SGPruneClears(now);'"
check "Settings told after each state written (MSBD_SG_UPDATED); Settings' check and switch notifications heard" \
  "awk '/^static void SGWriteState\\(/,/^}/' $D | grep -q 'notify_post(MSBD_SG_UPDATED);' && grep -q 'notify_register_dispatch(MSBD_SG_CHECK' $D && grep -q 'notify_register_dispatch(MSBD_SG_CHANGED' $D"
check "the helper runs it: SGStart at its start, the screen's changes from its screen watch" \
  "grep -q '^        SGStart();' $M && grep -q 'if ((blank != 0) != gSGScreenOff) SGScreenChanged(blank != 0);' $M"
[ $fails = 0 ] && echo "test-sleepguard: all checks pass" || { echo "test-sleepguard: checks FAILED"; exit 1; }
