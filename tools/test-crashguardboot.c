// test-crashguardboot.c -- the crash guard's start and a mark left from before this boot (1.8.7.5, audit L105 of 1.8.7.2), for
// tools/test-crashguardboot.sh. The real MSBDCrashGuardStart (common/CrashGuard.h) runs in this process on a mark the scenario writes; its two
// timers (the 8 s look, the 60 s clear) are taken by the stand-in below and only listed, never run.
// Run: test-crashguardboot <scenario>: oldsame (a mark of this pid from before the boot), now (a mark of this pid written in this boot: the
// second loader), oldother (a mark of another pid from before the boot), early (a mark of another pid from this boot: an early start).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/time.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <dispatch/dispatch.h>
typedef struct { int64_t at; int onMain; dispatch_function_t fn; } BootTimer;
static BootTimer gTimers[8];
static int gTimerCount;
static void BootAfter(dispatch_time_t when, dispatch_queue_t q, void *ctx, dispatch_function_t fn) {
    if (gTimerCount < 8) gTimers[gTimerCount++] = (BootTimer){ (int64_t)when, q == dispatch_get_main_queue(), fn };
}
#define dispatch_time(when, delta) ((dispatch_time_t)(int64_t)(delta))   // (the timers' delay, as the guard asks for it)
#define dispatch_after_f(when, queue, ctx, fn) BootAfter((when), (queue), (ctx), (fn))
#ifndef MSBD_TEST_GUARD_H   // (another copy of the guard: the code before the fix, or a made-to-fail copy)
#define MSBD_TEST_GUARD_H "../common/CrashGuard.h"
#endif
#include MSBD_TEST_GUARD_H
static int fails = 0;
static void Expect(const char *what, long got, long want) { printf("%s  %-92s got %ld, want %ld\n", got == want ? "PASS" : "FAIL", what, got, want); if (got != want) fails++; }
static long BootTime(void) { struct timeval b = {0, 0}; size_t n = sizeof b; return sysctlbyname("kern.boottime", &b, &n, NULL, 0) == 0 ? (long)b.tv_sec : 0; }
static void WriteMark(int pid, long t0, int stage, long ta, long mtime) {
    FILE *f = fopen(MSBD_GUARD_FILE, "w");
    if (!f) { perror("mark"); exit(2); }
    fprintf(f, "%d %ld %d %ld %d\n", pid, t0, stage, ta, 0);
    fclose(f);
    struct timeval tv[2] = { { mtime, 0 }, { mtime, 0 } };
    if (utimes(MSBD_GUARD_FILE, tv) != 0) { perror("utimes"); exit(2); }
}
static long MarkMtime(void) { struct stat st; return stat(MSBD_GUARD_FILE, &st) == 0 ? (long)st.st_mtime : -1; }
static int HasTimer(int64_t seconds, int onMain, dispatch_function_t fn) {
    for (int i = 0; i < gTimerCount; i++) if (gTimers[i].at == seconds * (int64_t)NSEC_PER_SEC && gTimers[i].onMain == onMain && gTimers[i].fn == fn) return 1;
    return 0;
}
int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s oldsame|now|oldother|early\n", argv[0]); return 2; }
    const char *sc = argv[1];
    long boot = BootTime(), now = (long)time(NULL);
    if (boot <= 0 || boot > now) { fprintf(stderr, "no boot time\n"); return 2; }
    long before = boot - 3600, t0old = boot - 3700, t0this = now - 20;
    MSBDGuardState m;
    if (!strcmp(sc, "oldsame")) {   // (L105: SpringBoard's pid came round again after a reboot)
        WriteMark(getpid(), t0old, 1, t0old + 30, before);
        Expect("before: the mark is from before this boot and holds this pid", MSBDGuardMarkBeforeBoot() && MSBDGuardRead(&m) && m.pid == getpid(), 1);
        MSBDCrashGuardStart();
        Expect("a mark of this pid from before the boot: a new row, a fresh mark (this pid, its row starting now)", MSBDGuardRead(&m) && m.pid == getpid() && m.t0 >= now && m.t0 <= (long)time(NULL), 1);
        Expect("  ... stage 0, nothing done in it (the old row's stage 1 is gone), no simulated crash", m.stage == 0 && m.ta == 0 && m.fakes == 0, 1);
        Expect("  ... written in this boot (the next loader of this SpringBoard sees its own mark)", MarkMtime() >= boot && !MSBDGuardMarkBeforeBoot(), 1);
        Expect("  ... the 60 s clear is set on the main queue", HasTimer(60, 1, MSBDGuardStable), 1);
        Expect("  ... no 8 s look (a new row: nothing to look at)", HasTimer(8, 0, MSBDGuardLook), 0);
        Expect("  ... nothing else", gTimerCount, 1);
        // The second loader in the same SpringBoard: it reads the mark the first one just wrote and returns.
        gTimerCount = 0;
        long t0 = m.t0, mt = MarkMtime();
        MSBDCrashGuardStart();
        Expect("  then the second loader of this SpringBoard: returns (the mark as the first left it, no timer)", MSBDGuardRead(&m) && m.pid == getpid() && m.t0 == t0 && m.stage == 0 && MarkMtime() == mt && gTimerCount == 0, 1);
    } else if (!strcmp(sc, "now")) {   // (the second loader: the first one wrote this mark a moment ago)
        WriteMark(getpid(), t0this, 0, 0, now - 5);
        MSBDCrashGuardStart();
        Expect("a mark of this pid written in this boot (the second loader): returns", MSBDGuardRead(&m) && m.pid == getpid() && m.t0 == t0this && m.stage == 0, 1);
        Expect("  ... nothing written (the mark's time unchanged)", MarkMtime(), now - 5);
        Expect("  ... no timer set", gTimerCount, 0);
    } else if (!strcmp(sc, "oldother")) {   // (as before the fix)
        WriteMark(1, t0old, 1, t0old + 30, before);
        MSBDCrashGuardStart();
        Expect("a mark of another pid from before the boot: a new row, a fresh mark (this pid, t0 now, stage 0)", MSBDGuardRead(&m) && m.pid == getpid() && m.t0 >= now && m.stage == 0 && m.ta == 0, 1);
        Expect("  ... the 60 s clear only", HasTimer(60, 1, MSBDGuardStable) && gTimerCount == 1, 1);
    } else if (!strcmp(sc, "early")) {   // (as before the fix: an early start of this boot's row)
        WriteMark(1, t0this, 0, 0, now - 5);
        MSBDCrashGuardStart();
        Expect("a mark of another pid from this boot: an early start of that row (t0 kept, this pid)", MSBDGuardRead(&m) && m.pid == getpid() && m.t0 == t0this && m.stage == 0, 1);
        Expect("  ... no crash reports: nothing done, the 8 s look and the 60 s clear set", HasTimer(8, 0, MSBDGuardLook) && HasTimer(60, 1, MSBDGuardStable) && gTimerCount == 2, 1);
    } else if (!strncmp(sc, "class", 5)) {   // (review of 1.8.7.7) a cause naming a class judged at this start: asked again at 8 s (MSBDGuardClassLook)
#ifdef MSBD_GUARD_CLASS_LATER
        MSBDGuardClassNote("SpringBoard-2026-11-16-170131.ips", "NSInvalidArgumentException: -[OtherTweakLateListener x:]: unrecognized selector\twhere\t1 OtherTweakLate.dylib");
        MSBDGuardClassNote("SpringBoard-2026-11-16-170200.ips", "EXC_CRASH (SIGABRT)\twhere\t0 ");   // (no class named: not noted)
        Expect("  (one report noted)", MSBDGuardClassNoted(), 1);
        if (!strcmp(sc, "classearly")) {   // an early start that did not act: its 8 s look asks (no timer of its own)
            WriteMark(1, t0this, 0, 0, now - 5);
            MSBDCrashGuardStart();
            Expect("class noted, an early start that did not act: the 8 s look (it asks) and the 60 s clear, nothing more", HasTimer(8, 0, MSBDGuardLook) && HasTimer(60, 1, MSBDGuardStable) && gTimerCount == 2, 1);
        } else if (!strcmp(sc, "classsafe")) {   // a start that left the tweak off (stage 2): no 8 s look, the class asked by a timer of its own
            WriteMark(1, t0this, 2, now - 10, now - 5);
            MSBDCrashGuardStart();
            Expect("class noted, the tweak off: only the 8 s class look, on a background queue", HasTimer(8, 0, MSBDGuardClassLookAt) && gTimerCount == 1, 1);
        } else {   // a start with no 8 s look (as one that acted): the class look and the 60 s clear
            WriteMark(1, t0old, 1, t0old + 30, before);
            MSBDCrashGuardStart();
            Expect("class noted, no 8 s look: the 8 s class look and the 60 s clear", HasTimer(8, 0, MSBDGuardClassLookAt) && HasTimer(60, 1, MSBDGuardStable) && gTimerCount == 2, 1);
        }
#else
        Expect("a cause naming a class asked again at 8 s (review of 1.8.7.7)", 0, 1);
#endif
    } else { fprintf(stderr, "unknown scenario %s\n", sc); return 2; }
    return fails ? 1 : 0;
}
