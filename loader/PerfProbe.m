// PerfProbe.m -- DEBUG builds only (never in a release package): the smoothness audit's in-process probe. The loaders open it only while
// /tmp/msb-perfprobe exists, in SpringBoard and in UIKit apps, and it does nothing until a measurement window starts: the Darwin notification
// com.besiktasliseba.perfprobe.window carries the window's number in its state (0 ends it; bit 32 asks for the main-thread profile too).
// While a window runs:
//   - frames: a display link (120 Hz asked for) counts this process's frames; a frame later than 1.5x the interval is a hitch (main-thread late);
//   - stalls: a run-loop observer (last in order, so CA's commit counts as work) marks when the main thread wakes and when it goes back to
//     waiting; a watchdog thread (every 2 ms) calls one wake-up's work longer than 25 ms a stall, and samples the main thread's stack every 2 ms
//     while it lasts (suspended for the read only: no allocation, no locks while it is stopped). No extra wake-ups of the main thread;
//   - profile: the main thread's stack every 2 ms all the window long.
// /tmp/msb-perfprobe may name the processes to measure (getprogname, one per line or space-separated); empty = SpringBoard only.
// At the end the watchdog thread writes one summary (the main thread never touches the file) to /tmp/msb-perf-<process>.log, or to the app's own
// tmp/ when /tmp is not writable (sandboxed apps). Frames in our parts and in other tweaks are named (dladdr); system frames by image + offset.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <dlfcn.h>
#include <notify.h>
#include <stdatomic.h>
#include <unistd.h>

extern pthread_t pthread_main_thread_np(void);   // (libsystem_pthread; not in the SDK headers)
extern int proc_regionfilename(int pid, uint64_t address, void *buffer, uint32_t buffersize);   // (libproc)

#define PP_MAXDEPTH 64
#define PP_MAXSAMPLES 6000      // (2 ms samples: 12 s of profile)
#define PP_MAXSTALLS 48
#define PP_MAXHITCH 400

typedef struct { uint16_t n; uint8_t running; uint8_t inStall; uint32_t t; uintptr_t pc[PP_MAXDEPTH]; } PPSample;
static PPSample *gSamples; static int gNSamples;
typedef struct { double start, dur; int firstSample, nSamples; } PPStall;
static PPStall gStalls[PP_MAXSTALLS]; static int gNStalls;
typedef struct { double t, gap; } PPHitch;
static PPHitch gHitch[PP_MAXHITCH]; static int gNHitch;

static mach_port_t gMainThread;
static _Atomic uint64_t gWindow;          // the running window (0: none); written by the notify queue, read everywhere
static _Atomic int gBusy; static _Atomic uint64_t gBusySince;   // (the run-loop observer: the main thread is working since gBusySince)
static _Atomic int gWatchRunning;            // (a watchdog thread is alive: the next window waits until the last one wrote its summary)
static uint64_t gWinStart; static double gWinStartWall;
static mach_timebase_info_data_t gTB;
static double PPms(uint64_t ticks) { return (double)ticks * gTB.numer / gTB.denom / 1e6; }
// frames (main thread only)
static double gLastTs, gInterval; static int gFrames, gHitches; static double gHitchMs, gMaxGap, gMaxGapAt;
// run-loop wake-ups' work (observer on the main thread): a histogram of how long each wake-up's work took
static int gLat[8]; static double gLatMax;
static uint64_t gMainCPU0;
static CADisplayLink *gLink;

@interface PPFrameCounter : NSObject
@end
@implementation PPFrameCounter
- (void)tick:(CADisplayLink *)l {
    if (!atomic_load(&gWindow)) return;
    double ts = l.timestamp, iv = l.targetTimestamp - l.timestamp;
    if (iv > 0.001 && iv < 0.05) gInterval = iv;
    if (gLastTs > 0 && gInterval > 0) {
        double gap = ts - gLastTs;
        gFrames++;
        if (gap > 1.5 * gInterval) {
            gHitches++; gHitchMs += (gap - gInterval) * 1000.0;
            if (gNHitch < PP_MAXHITCH) { gHitch[gNHitch].t = PPms(mach_absolute_time() - gWinStart); gHitch[gNHitch].gap = gap * 1000.0; gNHitch++; }
        }
        if (gap * 1000.0 > gMaxGap) { gMaxGap = gap * 1000.0; gMaxGapAt = PPms(mach_absolute_time() - gWinStart); }
    }
    gLastTs = ts;
}
@end
static PPFrameCounter *gCounter;

static uint64_t PPThreadCPU(mach_port_t th) {   // user + system, microseconds
    thread_basic_info_data_t bi; mach_msg_type_number_t c = THREAD_BASIC_INFO_COUNT;
    if (thread_info(th, THREAD_BASIC_INFO, (thread_info_t)&bi, &c) != KERN_SUCCESS) return 0;
    return (uint64_t)bi.user_time.seconds * 1000000 + bi.user_time.microseconds + (uint64_t)bi.system_time.seconds * 1000000 + bi.system_time.microseconds;
}
#define PP_STRIP(p) ((uintptr_t)(p) & 0x0000000FFFFFFFFFULL)
// One stack of the main thread into gSamples (nothing but kernel calls and plain reads while it is suspended).
static void PPSampleMain(int inStall) {
    if (gNSamples >= PP_MAXSAMPLES) return;
    PPSample *s = &gSamples[gNSamples];
    s->running = (uint8_t)atomic_load(&gBusy);
    if (thread_suspend(gMainThread) != KERN_SUCCESS) return;
    arm_thread_state64_t st; mach_msg_type_number_t c = ARM_THREAD_STATE64_COUNT; int n = 0;
    if (thread_get_state(gMainThread, ARM_THREAD_STATE64, (thread_state_t)&st, &c) == KERN_SUCCESS) {
        s->pc[n++] = PP_STRIP(arm_thread_state64_get_pc(st));
        uintptr_t lr = PP_STRIP(arm_thread_state64_get_lr(st)); if (lr) s->pc[n++] = lr;
        uintptr_t fp = PP_STRIP(arm_thread_state64_get_fp(st));
        while (fp && n < PP_MAXDEPTH) {
            uintptr_t frame[2]; vm_size_t got = 0;
            if (vm_read_overwrite(mach_task_self(), fp, sizeof(frame), (vm_address_t)frame, &got) != KERN_SUCCESS || got != sizeof(frame)) break;
            uintptr_t ret = PP_STRIP(frame[1]), next = PP_STRIP(frame[0]);
            if (!ret) break;
            if (n != 2 || ret != s->pc[1]) s->pc[n++] = ret;   // (the first frame's return address is lr when the leaf made no frame)
            if (next <= fp) break;
            fp = next;
        }
    }
    thread_resume(gMainThread);
    s->n = (uint16_t)n; s->inStall = (uint8_t)inStall; s->t = (uint32_t)PPms(mach_absolute_time() - gWinStart);
    gNSamples++;
}

static void PPObserve(CFRunLoopObserverRef o, CFRunLoopActivity a, void *ctx) {
    uint64_t now = mach_absolute_time();
    if (a == kCFRunLoopAfterWaiting || a == kCFRunLoopEntry) { atomic_store(&gBusySince, now); atomic_store(&gBusy, 1); return; }
    if (a == kCFRunLoopBeforeWaiting || a == kCFRunLoopExit) {
        if (atomic_load(&gBusy) && atomic_load(&gWindow)) {
            double w = PPms(now - atomic_load(&gBusySince));
            static const double edges[7] = {2, 5, 9, 17, 25, 50, 100}; int k = 0; while (k < 7 && w > edges[k]) k++;
            gLat[k]++; if (w > gLatMax) gLatMax = w;
        }
        atomic_store(&gBusy, 0);
    }
}

// ---- the summary (watchdog thread, after the window) ----
typedef struct { const char *img; const char *sym; uintptr_t off; int kind; } PPSym;   // kind: 0 system, 1 ours, 2 other tweak/jailbreak
static int PPKind(const char *path) {
    if (!path) return 0;
    if (strstr(path, "/MacStatusBarAndDock/") || strstr(path, "/MacStatusBar.dylib") || strstr(path, "/MacDock.dylib")) return 1;
    if (strstr(path, "/var/jb/") || strstr(path, "/private/preboot/") || strstr(path, "ellekit") || strstr(path, "substrate")) return 2;
    return 0;
}
static const char *PPBase(const char *p) { const char *s = p ? strrchr(p, '/') : NULL; return s ? s + 1 : (p ?: "?"); }
static PPSym PPLookup(uintptr_t pc) {
    PPSym r = { "?", NULL, pc, 0 }; Dl_info di;
    if (dladdr((void *)pc, &di) && di.dli_fname) {
        r.img = PPBase(di.dli_fname); r.kind = PPKind(di.dli_fname);
        r.off = pc - (uintptr_t)di.dli_fbase;
        if (di.dli_sname && di.dli_saddr) { r.sym = di.dli_sname; if (r.kind) r.off = pc - (uintptr_t)di.dli_saddr; }
    }
    return r;
}
static void PPFrameName(uintptr_t pc, char *buf, size_t size) {
    PPSym s = PPLookup(pc);
    if (s.kind && s.sym) snprintf(buf, size, "%s%s:%s+%lu", s.kind == 1 ? "*" : "+", s.img, s.sym, (unsigned long)s.off);
    else if (s.sym) snprintf(buf, size, "%s:~%s", s.img, s.sym);
    else snprintf(buf, size, "%s+0x%lx", s.img, (unsigned long)s.off);
}
typedef struct { char name[160]; int n; } PPCount;
static int PPCountCmp(const void *a, const void *b) { return ((PPCount *)b)->n - ((PPCount *)a)->n; }
static void PPAdd(PPCount *t, int *nt, int max, const char *name) {
    for (int i = 0; i < *nt; i++) if (strcmp(t[i].name, name) == 0) { t[i].n++; return; }
    if (*nt < max) { strlcpy(t[*nt].name, name, sizeof(t[*nt].name)); t[*nt].n = 1; (*nt)++; }
}
// the samples [from, from + count): our and other tweaks' functions on the stack (once per sample), leaf images, and the 3 commonest stacks
static void PPWriteSamples(FILE *f, int from, int count, const char *what) {
    static PPCount ours[400], leaf[200], stacks[200]; int no = 0, nl = 0, ns = 0, running = 0, withOurs = 0, withJB = 0;
    for (int i = from; i < from + count; i++) {
        PPSample *s = &gSamples[i]; if (!s->n) continue;
        running += s->running;
        char seen[PP_MAXDEPTH][160]; int nseen = 0, hadOurs = 0, hadJB = 0;
        for (int k = 0; k < s->n; k++) {
            PPSym y = PPLookup(s->pc[k]);
            if (!y.kind) continue;
            char nm[160]; snprintf(nm, sizeof(nm), "%s%s:%s", y.kind == 1 ? "*" : "+", y.img, y.sym ?: "?");
            int dup = 0; for (int j = 0; j < nseen; j++) if (!strcmp(seen[j], nm)) { dup = 1; break; }
            if (dup) continue;
            strlcpy(seen[nseen++], nm, 160); PPAdd(ours, &no, 400, nm);
            if (y.kind == 1) hadOurs = 1; else hadJB = 1;
        }
        withOurs += hadOurs; withJB += hadJB;
        char lf[160]; PPFrameName(s->pc[0], lf, sizeof(lf)); PPSym l0 = PPLookup(s->pc[0]);
        char li[160]; snprintf(li, sizeof(li), "%s%s", s->running ? "" : "(waiting) ", l0.img); PPAdd(leaf, &nl, 200, li);
        char sk[160] = ""; for (int k = 0; k < s->n && k < 6; k++) { char fn[64]; PPSym y = PPLookup(s->pc[k]);
            snprintf(fn, sizeof(fn), "%s%s<", y.kind == 1 ? "*" : "", y.sym && y.kind ? y.sym : y.img); strlcat(sk, fn, sizeof(sk)); }
        PPAdd(stacks, &ns, 200, sk);
    }
    qsort(ours, no, sizeof(PPCount), PPCountCmp); qsort(leaf, nl, sizeof(PPCount), PPCountCmp); qsort(stacks, ns, sizeof(PPCount), PPCountCmp);
    fprintf(f, "  %s: %d samples, running %d; with our code on the stack %d (%.0f%%), with another tweak's %d (%.0f%%)\n", what, count, running,
            withOurs, count ? withOurs * 100.0 / count : 0, withJB, count ? withJB * 100.0 / count : 0);
    for (int i = 0; i < no && i < 25; i++) fprintf(f, "    %4d %5.1f%%  %s\n", ours[i].n, ours[i].n * 100.0 / count, ours[i].name);
    fprintf(f, "    leaf images:"); for (int i = 0; i < nl && i < 10; i++) fprintf(f, " %s %d,", leaf[i].name, leaf[i].n); fprintf(f, "\n");
    for (int i = 0; i < ns && i < 4; i++) fprintf(f, "    stack x%d: %s\n", stacks[i].n, stacks[i].name);
}
static FILE *PPOpenLog(void) {
    char path[1024]; snprintf(path, sizeof(path), "/tmp/msb-perf-%s.log", getprogname());
    FILE *f = fopen(path, "a");
    if (!f) { snprintf(path, sizeof(path), "%s/msb-perf-%s.log", NSTemporaryDirectory().UTF8String, getprogname()); f = fopen(path, "a"); }
    return f;
}
// The samples' raw stacks (addresses), for naming system frames outside the process (the shared cache's ObjC methods are not in dladdr's
// tables): /tmp/msb-perf-<process>.stacks, one line per sample ("S <window> <t ms> <s=stall|p> <r=running|w> addr..."), and each image once
// ("I <base> <path>"; the shared cache sits at the same address in every process of a boot, so another process can name them).
static void PPWriteStacks(uint64_t win) {
    if (!gNSamples) return;
    char path[1024]; snprintf(path, sizeof(path), "/tmp/msb-perf-%s.stacks", getprogname());
    int fresh = access(path, F_OK) != 0;
    FILE *f = fopen(path, "a");
    if (!f) { snprintf(path, sizeof(path), "%s/msb-perf-%s.stacks", NSTemporaryDirectory().UTF8String, getprogname()); fresh = access(path, F_OK) != 0; f = fopen(path, "a"); }
    if (!f) return;
    static uintptr_t seenBase[256]; static int nSeen = 0;
    static uintptr_t named[8192]; static int nNamed = 0;   // (our and other tweaks' frames, named here once: local symbols only this process has)
    if (fresh) { nSeen = 0; nNamed = 0; }   // (a new file -- the last one was taken away: every image and name written again)
    for (int i = 0; i < gNSamples; i++) {
        PPSample *s = &gSamples[i];
        for (int k = 0; k < s->n; k++) {
            Dl_info di;
            if (!dladdr((void *)s->pc[k], &di) || !di.dli_fbase || !di.dli_fname) continue;
            int known = 0; for (int j = 0; j < nSeen; j++) if (seenBase[j] == (uintptr_t)di.dli_fbase) { known = 1; break; }
            if (!known && nSeen < 256) { seenBase[nSeen++] = (uintptr_t)di.dli_fbase; fprintf(f, "I %lx %s\n", (unsigned long)(uintptr_t)di.dli_fbase, di.dli_fname); }
        }
        for (int k = 0; k < s->n && nNamed < 8192; k++) {
            int have = 0; for (int j = 0; j < nNamed; j++) if (named[j] == s->pc[k]) { have = 1; break; }
            if (have) continue;
            Dl_info dd;
            if (!dladdr((void *)s->pc[k], &dd) || !dd.dli_fname) {   // (code in no image dyld knows: whose memory is it -- a file mapped by hand, a tag)
                named[nNamed++] = s->pc[k];
                char file[1024] = ""; proc_regionfilename(getpid(), s->pc[k], file, sizeof(file));
                vm_address_t a = s->pc[k]; vm_size_t sz = 0; vm_region_extended_info_data_t ei; mach_msg_type_number_t c = VM_REGION_EXTENDED_INFO_COUNT; mach_port_t obj = MACH_PORT_NULL;
                kern_return_t kr = vm_region_64(mach_task_self(), &a, &sz, VM_REGION_EXTENDED_INFO, (vm_region_info_t)&ei, &c, &obj);
                fprintf(f, "U %lx region %llx+%llx prot %d tag %u share %u file %s\n", (unsigned long)s->pc[k], kr == KERN_SUCCESS ? (unsigned long long)a : 0ULL,
                        kr == KERN_SUCCESS ? (unsigned long long)sz : 0ULL, kr == KERN_SUCCESS ? ei.protection : -1, kr == KERN_SUCCESS ? ei.user_tag : 0, kr == KERN_SUCCESS ? ei.share_mode : 0, file[0] ? file : "-");
                continue;
            }
            PPSym y = PPLookup(s->pc[k]);
            if (!y.kind) continue;
            named[nNamed++] = s->pc[k];
            fprintf(f, "N %lx %s%s:%s+%lu\n", (unsigned long)s->pc[k], y.kind == 1 ? "*" : "+", y.img, y.sym ?: "?", (unsigned long)y.off);
        }
        fprintf(f, "S %llu %u %c %c", win & 0xffffffffULL, s->t, s->inStall ? 's' : 'p', s->running ? 'r' : 'w');
        for (int k = 0; k < s->n; k++) fprintf(f, " %lx", (unsigned long)s->pc[k]);
        fprintf(f, "\n");
    }
    fclose(f);
}
static void PPWriteSummary(uint64_t win, uint64_t endTicks) {
    FILE *f = PPOpenLog(); if (!f) return;
    double secs = PPms(endTicks - gWinStart) / 1000.0;
    uint64_t cpu = PPThreadCPU(gMainThread) - gMainCPU0;
    fprintf(f, "W%llu %s %d: %.2f s from %.3f; frames %d (interval %.2f ms), hitches %d (%.1f ms over, %.1f ms/s), longest frame %.1f ms at %.0f; "
            "wake-up work ms <=2:%d <=5:%d <=9:%d <=17:%d <=25:%d <=50:%d <=100:%d >100:%d max %.1f; stalls>25ms %d; main thread CPU %.1f ms (%.0f%%)\n",
            win & 0xffffffffULL, getprogname(), getpid(), secs, gWinStartWall, gFrames, gInterval * 1000.0, gHitches, gHitchMs, secs > 0 ? gHitchMs / secs : 0,
            gMaxGap, gMaxGapAt, gLat[0], gLat[1], gLat[2], gLat[3], gLat[4], gLat[5], gLat[6], gLat[7], gLatMax, gNStalls, cpu / 1000.0, secs > 0 ? cpu / (secs * 10000.0) : 0);
    if (gNHitch) { fprintf(f, "  hitches (t ms: gap ms):"); for (int i = 0; i < gNHitch && i < 60; i++) fprintf(f, " %.0f:%.1f", gHitch[i].t, gHitch[i].gap); fprintf(f, "\n"); }
    for (int i = 0; i < gNStalls; i++) {
        fprintf(f, "  stall at %.0f ms, %.1f ms:\n", gStalls[i].start, gStalls[i].dur);
        if (gStalls[i].nSamples) PPWriteSamples(f, gStalls[i].firstSample, gStalls[i].nSamples, "stall samples");
    }
    int profiled = 0; for (int i = 0; i < gNSamples; i++) if (!gSamples[i].inStall) profiled++;
    if (profiled) {   // (profile samples are the ones taken outside stalls, plus the stall ones: all of them)
        PPWriteSamples(f, 0, gNSamples, "profile (all samples)");
    }
    fclose(f);
    PPWriteStacks(win);
}

static void *PPWatch(void *arg) {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
    uint64_t win = 0; int stalling = 0; double stallStart = 0; int stallFirst = 0; uint64_t lastProf = 0, stallSince = 0;
    for (;;) {
        uint64_t w = atomic_load(&gWindow);
        if (w != win) {
            if (win) {   // the window ended (or the next began): its summary
                uint64_t end = mach_absolute_time();
                usleep(30000);
                PPWriteSummary(win, end);
            }
            win = w;
            if (!win) { atomic_store(&gWatchRunning, 0); return NULL; }
            // a new window: counters back to zero (the display link is started on the main thread by PPStart)
            gNSamples = 0; gNStalls = 0; gNHitch = 0; memset(gLat, 0, sizeof(gLat)); gLatMax = 0; stalling = 0;
            gMainCPU0 = PPThreadCPU(gMainThread);
        }
        uint64_t now = mach_absolute_time();
        int busy = atomic_load(&gBusy); uint64_t since = atomic_load(&gBusySince);
        if (stalling && (!busy || since != stallSince)) {   // the long wake-up ended: the stall is over
            if (gNStalls < PP_MAXSTALLS) { gStalls[gNStalls].start = stallStart; gStalls[gNStalls].dur = PPms(now - gWinStart) - stallStart;
                gStalls[gNStalls].firstSample = stallFirst; gStalls[gNStalls].nSamples = gNSamples - stallFirst; gNStalls++; }
            stalling = 0;
        }
        if (!stalling && busy && since > gWinStart && PPms(now - since) > 25.0) {
            stalling = 1; stallSince = since; stallStart = PPms(since - gWinStart); stallFirst = gNSamples;
        }
        if (stalling || ((win >> 32) & 1)) {
            if (PPms(now - lastProf) >= 2.0) { PPSampleMain(stalling); lastProf = now; }
        }
        usleep(2000);
    }
    return NULL;
}

static void PPStart(uint64_t w) {
    uint64_t prev = atomic_load(&gWindow);
    for (int i = 0; !prev && atomic_load(&gWatchRunning) && i < 600; i++) usleep(5000);   // (the last window's summary still being written)
    gWinStart = mach_absolute_time(); gWinStartWall = [[NSDate date] timeIntervalSince1970];
    atomic_store(&gWindow, w);
    if (!prev && !atomic_load(&gWatchRunning)) { atomic_store(&gWatchRunning, 1); pthread_t t; pthread_create(&t, NULL, PPWatch, NULL); pthread_detach(t); }
    dispatch_async(dispatch_get_main_queue(), ^{
        gLastTs = 0; gFrames = 0; gHitches = 0; gHitchMs = 0; gMaxGap = 0; gMaxGapAt = 0; gInterval = 0;
        if (!gLink) {
            if (!gCounter) gCounter = [PPFrameCounter new];
            gLink = [CADisplayLink displayLinkWithTarget:gCounter selector:@selector(tick:)];
            if (@available(iOS 15.0, *)) gLink.preferredFrameRateRange = CAFrameRateRangeMake(120, 120, 120);
            [gLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
    });
}
static void PPStop(void) {
    atomic_store(&gWindow, 0);
    dispatch_async(dispatch_get_main_queue(), ^{ [gLink invalidate]; gLink = nil; });
}

static int PPWanted(void) {
    FILE *f = fopen("/tmp/msb-perfprobe", "r"); if (!f) return 0;
    char buf[1024]; size_t n = fread(buf, 1, sizeof(buf) - 1, f); fclose(f); buf[n] = 0;
    const char *me = getprogname(); int any = 0;
    for (char *tok = strtok(buf, " \t\r\n,"); tok; tok = strtok(NULL, " \t\r\n,")) { any = 1; if (!strcmp(tok, me) || !strcmp(tok, "all")) return 1; }
    return !any && !strcmp(me, "SpringBoard");
}
__attribute__((constructor)) static void PPInit(void) {
    if (!PPWanted()) return;
    mach_timebase_info(&gTB);
    gMainThread = pthread_mach_thread_np(pthread_main_thread_np());
    gSamples = calloc(PP_MAXSAMPLES, sizeof(PPSample));
    if (!gSamples) return;
    CFRunLoopObserverRef o = CFRunLoopObserverCreate(NULL, kCFRunLoopAllActivities, true, LONG_MAX, PPObserve, NULL);
    CFRunLoopAddObserver(CFRunLoopGetMain(), o, kCFRunLoopCommonModes);
    int token = 0;
    dispatch_queue_t q = dispatch_queue_create("com.besiktasliseba.perfprobe", DISPATCH_QUEUE_SERIAL);
    notify_register_dispatch("com.besiktasliseba.perfprobe.window", &token, q, ^(int t) {
        uint64_t state = 0; notify_get_state(t, &state);
        uint64_t cur = atomic_load(&gWindow);
        if (state == cur) return;
        if (!state) PPStop(); else PPStart(state);
    });
}
