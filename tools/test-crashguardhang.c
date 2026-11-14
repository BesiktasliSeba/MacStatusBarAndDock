// test-crashguardhang.c -- one SpringBoard start, for tools/test-crashguardhang.sh (1.8.7.3, audit M1 of 1.8.7.2): the crash guard's start
// (common/CrashGuard.h MSBDCrashGuardStart) in this process, then a main thread that runs, is stuck, and is killed or runs again.
// The guard's two timers (its 8 s look and its 60 s clear, dispatch_after_f) are taken by the stand-in below with the queue the guard names, and
// fired on this start's own clock, in time order: one on the main queue only while the main thread runs (at its time, or as soon as the thread
// runs again after being stuck), one on another queue at its time, whatever the main thread does -- what libdispatch does with them. Nothing
// waits on the wall clock, so a busy Mac cannot reorder anything: with the time 100 times faster, a stall of half a second ran the 60 s clear
// inside "alive 10 s" and the test failed by itself now and then (review of the M1 fix).
// Run: test-crashguardhang start <alive s> <stuck s> <then: kill | alive s>
//   alive: the main thread runs (the main queue is served, as in SpringBoard); stuck: it is blocked (only other queues run);
//   kill: SIGKILL after the stuck time, as the watchdog does. Prints "pid <pid> mark 0|1" (the guard's mark there?) when the stuck time ends.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <stdint.h>
#include <dispatch/dispatch.h>
static int64_t gNow;   // this start's clock: ns since the guard's start
typedef struct { int64_t at; int onMain; dispatch_function_t fn; void *ctx; } SBTimer;
static SBTimer gTimers[16];
static int gTimerCount, gTimerCalls;
static void SBAfter(dispatch_time_t when, dispatch_queue_t q, void *ctx, dispatch_function_t fn) {
    gTimerCalls++;
    if (gTimerCount < 16) gTimers[gTimerCount++] = (SBTimer){ (int64_t)when, q == dispatch_get_main_queue(), fn, ctx };
}
#define dispatch_time(when, delta) ((dispatch_time_t)(gNow + (int64_t)(delta)))   // (the guard's timers: on this start's clock)
#define dispatch_after_f(when, queue, ctx, fn) SBAfter((when), (queue), (ctx), (fn))
#ifndef MSBD_TEST_GUARD_H   // (another copy of the guard: the code before the fix, or a made-to-fail copy)
#define MSBD_TEST_GUARD_H "../common/CrashGuard.h"
#endif
#include MSBD_TEST_GUARD_H
static int64_t NS(const char *sbSeconds) { return (int64_t)(atof(sbSeconds) * 1e9); }
// The time from `from` to `until`, the main thread running (mainRuns) or stuck: every timer due by `until` fires in time order, a main-queue one
// only while the main thread runs (one due while it was stuck fires at `from`, when it runs again).
static void Pass(int64_t from, int64_t until, int mainRuns) {
    for (;;) {
        int next = -1; int64_t nextAt = 0;
        for (int i = 0; i < gTimerCount; i++) {
            if (!gTimers[i].fn || (gTimers[i].onMain && !mainRuns)) continue;
            int64_t at = gTimers[i].at < from ? from : gTimers[i].at;
            if (at > until) continue;
            if (next < 0 || at < nextAt) { next = i; nextAt = at; }
        }
        if (next < 0) break;
        gNow = nextAt;
        dispatch_function_t fn = gTimers[next].fn; gTimers[next].fn = NULL;
        fn(gTimers[next].ctx);
    }
    gNow = until;
}
int main(int argc, char **argv) {
    if (argc != 5 || strcmp(argv[1], "start") != 0) { fprintf(stderr, "usage: %s start <alive s> <stuck s> <kill | alive s>\n", argv[0]); return 2; }
    MSBDCrashGuardStart();
    if (gTimerCalls != gTimerCount) { fprintf(stderr, "more timers than the stand-in keeps\n"); return 2; }
    int64_t alive = NS(argv[2]), stuck = NS(argv[3]);
    Pass(0, alive, 1);
    Pass(alive, alive + stuck, 0);
    printf("pid %d mark %d\n", getpid(), access(MSBD_GUARD_FILE, F_OK) == 0); fflush(stdout);
    if (strcmp(argv[4], "kill") == 0) raise(SIGKILL);   // (the watchdog: nothing after the stuck time runs)
    Pass(alive + stuck, alive + stuck + NS(argv[4]), 1);
    return 0;
}
