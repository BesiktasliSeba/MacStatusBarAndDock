// test-crashguardlook.c -- one SpringBoard start, for tools/test-crashguardlook.sh (1.8.7.5, audit L103 of 1.8.7.2): the crash guard's start
// (common/CrashGuard.h MSBDCrashGuardStart) in this process, its 8 s look and 60 s clear on this start's own clock, crash reports landing at given
// moments of it, and the SpringBoard's end (a crash) at a given moment. The wall clock the guard reads (time()) is this start's too: it starts at
// the time given, so the reports' times (in their names), the row's t0 and the guard's ta are placed exactly, and nothing waits on the real clock.
// Run: test-crashguardlook <wall at the start> <end s> [<at s>:<report's wall time>:<fixture>[:<pid>|:self]]...
//   end s: the SpringBoard crashes then (nothing after it runs; 0 = never, the start runs 70 s). Each report is copied into the guard's report folder
//   at its moment, named by its wall time (the crash it tells about; a second report of the same second gets "-2" after the time). With a pid
//   (self: this start's own), the copy's body names that SpringBoard ("pid", as the system's reports do; the fixtures have none). Prints
//   "pid <pid> skipped <0|1>" after the start: DockMagnification on step 1b's skip list as the loaders see it (MSBDCrashSkipped, CrashStep.h).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdbool.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <pthread.h>
#include <notify.h>
static int64_t gNow;   // this start's clock: ns since the guard's start
static long gWall;     // the wall time at the start
static time_t SBTime(time_t *t) { time_t v = (time_t)(gWall + gNow / 1000000000); if (t) *t = v; return v; }
#define time(t) SBTime(t)   // (the guard's wall clock: this start's; after the system headers, which declare the real one)
typedef struct { int64_t at; dispatch_function_t fn; void *ctx; } SBTimer;
static SBTimer gTimers[16];
static int gTimerCount, gTimerCalls;
static void SBAfter(dispatch_time_t when, dispatch_queue_t q, void *ctx, dispatch_function_t fn) {
    gTimerCalls++;
    if (gTimerCount < 16) gTimers[gTimerCount++] = (SBTimer){ (int64_t)when, fn, ctx };
}
#define dispatch_time(when, delta) ((dispatch_time_t)(gNow + (int64_t)(delta)))   // (the guard's timers: on this start's clock)
#define dispatch_after_f(when, queue, ctx, fn) SBAfter((when), (queue), (ctx), (fn))
#ifndef MSBD_TEST_GUARD_H   // (another copy of the guard: the code before the fix, or a made-to-fail copy)
#define MSBD_TEST_GUARD_H "../common/CrashGuard.h"
#endif
#include MSBD_TEST_GUARD_H
typedef struct { int64_t at; long wall; char fixture[1024]; int pid, done; } SBReport;
static SBReport gReports[8];
static int gReportCount;
static void PlaceReport(SBReport *r) {
    char stamp[64], path[1200]; struct tm tm; time_t w = (time_t)r->wall;
    localtime_r(&w, &tm);
    strftime(stamp, sizeof stamp, "SpringBoard-%Y-%m-%d-%H%M%S", &tm);
    snprintf(path, sizeof path, "%s/%s.ips", MSBD_GUARD_REPORTS, stamp);
    if (access(path, F_OK) == 0) snprintf(path, sizeof path, "%s/%s-2.ips", MSBD_GUARD_REPORTS, stamp);   // (two crashes in one second)
    static char data[1 << 20];
    FILE *in = fopen(r->fixture, "rb"), *out = NULL;
    size_t n = in ? fread(data, 1, sizeof data - 1, in) : 0;
    if (in) fclose(in);
    data[n] = 0;
    char *body = memchr(data, '\n', n), *brace = body ? strchr(body, '{') : NULL;
    if (!n || (r->pid && !brace) || !(out = fopen(path, "wb"))) { fprintf(stderr, "could not place %s\n", r->fixture); exit(2); }
    if (r->pid) {   // (the body's first key: the crashed SpringBoard's pid)
        fwrite(data, 1, (size_t)(brace + 1 - data), out);
        fprintf(out, "\n  \"pid\": %d,", r->pid);
        fwrite(brace + 1, 1, n - (size_t)(brace + 1 - data), out);
    } else fwrite(data, 1, n, out);
    fclose(out);
    r->done = 1;
}
// The time up to `until`: every timer and report due by then, in time order (a report before a timer at the same moment).
static void Pass(int64_t until) {
    for (;;) {
        int t = -1, r = -1; int64_t at = 0;
        for (int i = 0; i < gReportCount; i++) if (!gReports[i].done && gReports[i].at <= until && (r < 0 || gReports[i].at < gReports[r].at)) r = i;
        for (int i = 0; i < gTimerCount; i++) if (gTimers[i].fn && gTimers[i].at <= until && (t < 0 || gTimers[i].at < gTimers[t].at)) t = i;
        if (r < 0 && t < 0) break;
        if (r >= 0 && (t < 0 || gReports[r].at <= gTimers[t].at)) { gNow = gReports[r].at; PlaceReport(&gReports[r]); continue; }
        at = gTimers[t].at; gNow = at;
        dispatch_function_t fn = gTimers[t].fn; gTimers[t].fn = NULL;
        fn(gTimers[t].ctx);
    }
    gNow = until;
}
int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <wall> <end s> [<at s>:<wall>:<fixture>]...\n", argv[0]); return 2; }
    gWall = atol(argv[1]);
    double end = atof(argv[2]);
    for (int i = 3; i < argc && gReportCount < 8; i++) {
        char *a = argv[i], *c1 = strchr(a, ':'), *c2 = c1 ? strchr(c1 + 1, ':') : NULL, *c3 = c2 ? strchr(c2 + 1, ':') : NULL;
        if (!c2) { fprintf(stderr, "bad report %s\n", a); return 2; }
        SBReport *r = &gReports[gReportCount++];
        *r = (SBReport){ (int64_t)(atof(a) * 1e9), atol(c1 + 1), "", 0, 0 };
        snprintf(r->fixture, sizeof r->fixture, "%.*s", c3 ? (int)(c3 - c2 - 1) : (int)strlen(c2 + 1), c2 + 1);
        if (c3) r->pid = strcmp(c3 + 1, "self") == 0 ? getpid() : atoi(c3 + 1);
    }
    MSBDCrashGuardStart();
    if (gTimerCalls != gTimerCount) { fprintf(stderr, "more timers than the stand-in keeps\n"); return 2; }
    printf("pid %d skipped %d\n", getpid(), MSBDCrashSkipped("DockMagnification")); fflush(stdout);   // (the loaders, right after the guard)
    Pass(end > 0 ? (int64_t)(end * 1e9) : (int64_t)70e9);
    return 0;   // (a crash at `end`: nothing after it runs -- the 60 s clear is later, or never came)
}
