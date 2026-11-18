// CrashGuard.h -- the crash guard (MacStatusBar&Dock, 2026-09-25; armed on every iPadOS version since 2026-09-26).
//
// SpringBoard's loader writes a small state file at every start, before any part loads, and removes it once SpringBoard has run 60 s with its main
// thread alive (the removal runs on the main queue: a SpringBoard stuck then keeps it, so the watchdog's kill counts). Found at the next start,
// the previous SpringBoard ended early. That alone is no crash (a respring, Aerial 5.0's own respring after its license check, an
// installer's): only SpringBoard crash reports count (CrashReporter/SpringBoard-<date>.ips, a folder mobile can list; never cpu_resource/wakeups
// reports). Two crashes while SpringBoard never ran a full minute in between (the crash just before the first early start counts too), and:
//  1. the feature switches turned on within 2 min before (the Status Bar and Dock pages note them, see LineSwitch.h) are switched off again;
//  2. with no such switch, or after one more crash: on an untested version "Enable Anyway" is switched off; on 15/16 the safe mode is switched on
//     (crashSafeMode, VersionGate.h). Either way only the Settings rows load, and the pages offer the way back.
// What it did is kept in crashGuardAction, which the pages' footer shows (untested: until "Enable Anyway" is changed; 15/16: until "Turn Back On",
// or for step 1 until a switch on the pages is changed). ElleKit's Safe Mode (after two quick crashes; the loader does not run there) leaves the
// file and the reports alone, so the guard acts at the first start after Safe Mode.
// A crash report can be written a moment after the new SpringBoard started, so the loader looks once more when it is 8 s old.
// Only crashes that point at us count (2026-09-26): each report is judged once by MacCrashBlame.dylib (common/CrashBlame.h, loader/CrashBlameHelper.m;
// Foundation's JSON reader, which the plain-C loader cannot use itself) and the verdict is kept in MSBD_GUARD_VERDICTS. A crash in another tweak's
// library (on the crashing stack, nothing of ours there) is not counted; ours, Apple-only stacks and reports that cannot be read are (as before).
// 1.8.7.7 (GitHub #14, and #9/#10 on 1.6.1): an Apple-only crash while another tweak is loaded (verdict UNPINNED) could be anyone's -- the reporter's
// popover aborts and a Do Not Disturb listener of other tweaks switched MacStatusBar&Dock off. It is a WEAK crash now: S = strong crashes (ours,
// Apple-only with no other tweak, unreadable), W = weak, O = other tweaks' crashes, in the row (MSBDGuardEvaluate):
//  1. S >= 2, or 2. S == 1 and W >= 1: as before (step 1, else 1b, else 2) -- a weak crash can second one of ours, never start an action;
//  3. S == 0, W >= 2 and switches turned on in the 2 min before the row: step 1 only (what was just turned on goes off again), nothing more;
//  4. four or more (strong or weak) since the newest other tweak's crash of the row, if there is one: the loop breaker -- SpringBoard keeps crashing
//     and nothing else is to blame: as before, "loop 1" in the record (review of 1.8.7.7: an other tweak's crash anywhere in the row turned it off
//     for the whole row, so a loop of ours that began right after one never stopped; it only resets the count now -- that tweak may be the loop);
//  5. else nothing: the verdicts and causes are kept for the page's note and Report a Problem.
// After step 1 or 1b one more strong crash, or a row that meets rule 4, goes on to step 2 (action 3). Each judged report also gets its cause (the
// exception's reason our death record kept, common/CrashCause.h, or what the report says), where it crashed and the other tweaks loaded.
// The helper is opened only when a report has to be judged or told from the SpringBoard before a start's count (MSBDGuardFrom), after an early
// start, so a normal start costs nothing more.
// Since 2026-09-26 it explains itself: when it acts it writes a small record (MSBD_GUARD_RECORD: what it did, the switches by their row titles, the
// part of ours that was blamed, iPadOS and build, the top frames of our image only), which the pages' footer and the Report a Problem text use
// (CrashExplain.h), and which the one-time notice on the Home Screen shows (loader/CrashNotice.m, loaded only while the record is unshown).
// Cost per SpringBoard start: one small file write, and 60 s later one read and an unlink (on the main thread); the crash-report folder is only
// listed after an early start. The mark has to be written before a crash can happen, so it cannot wait for a crash report to exist. 1.8.7.7: plus
// our death record's handler installed (CrashCause.h: a few dlsym calls and two function calls; it only runs when SpringBoard dies of an exception).
// Plain C (loader/Loader.c); CoreFoundation is looked up at run time, as in VersionGate.h.
#pragma once
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include "VersionGate.h"

#ifndef MSBD_GUARD_FILE   // (overridable for the Mac test)
#define MSBD_GUARD_FILE "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashGuard.txt"     // written by SpringBoard (mobile)
#endif
#ifndef MSBD_GUARD_RECENT   // (overridable for the Mac test)
#define MSBD_GUARD_RECENT "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-RecentlyOn.txt"   // "<time> <domain> <key> <title>" lines, by Settings
#endif
#define MSBD_GUARD_ACTION_KEY "crashGuardAction"   // 1 switches turned off, 2 turned off after two crashes, 3 after more crashes, 4 step 1b (CrashStep.h)
#ifndef MSBD_GUARD_REPORTS   // (overridable for the Mac test, tools/test-crashguard.c)
#define MSBD_GUARD_REPORTS "/var/mobile/Library/Logs/CrashReporter"
#endif
#ifndef MSBD_GUARD_VERDICTS   // (overridable for the Mac test, tools/test-crashguard.c)
#define MSBD_GUARD_VERDICTS "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashVerdicts2.txt"   // "<report> <verdict> <blamed>\t<cause>\t<where>\t<others>" lines
// (1.8.7.7: a new name -- the old file's Apple-only verdicts were judged without looking for other tweaks, so they are not reused; a build before
// reads its own file, MacStatusBarAndDock-CrashVerdicts.txt, which this one leaves alone)
#endif
#ifndef MSBD_GUARD_RECORD   // (overridable for the Mac test, tools/test-crashguard.c)
#define MSBD_GUARD_RECORD "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashRecord.txt"   // what the guard did and why (see below)
#endif
#ifndef MSBD_BUILD_VERSION   // (the package version, from the Makefile)
#define MSBD_BUILD_VERSION "unknown"
#endif
#ifndef MSBD_GUARD_NOTICE_LIB   // (the one-time notice after the guard acted: loader/CrashNotice.m)
#define MSBD_GUARD_NOTICE_LIB "/var/jb/usr/lib/MacStatusBarAndDock/MacCrashNotice.dylib"
#endif
#ifndef MSBD_GUARD_BLAME_LIB   // (overridable for the Mac test, tools/test-crashguard.c)
#define MSBD_GUARD_BLAME_LIB "/var/jb/usr/lib/MacStatusBarAndDock/MacCrashBlame.dylib"
#endif
enum { kMSBDVerdictUnknown = 0, kMSBDVerdictOurs = 1, kMSBDVerdictApple = 2, kMSBDVerdictOther = 3, kMSBDVerdictUnpinned = 4 };   // (= kMSBDBlame..., CrashBlame.h)
#define MSBD_GUARD_WEAK_CRASHES 1   // (1.8.7.7: strong and weak crashes -- the Mac tests run on the code before it too)
#include "CrashCause.h"   // (1.8.7.7: our death record, installed at the guard's start)

typedef struct { int pid, stage, fakes, next, prev, wfakes; long t0, ta; } MSBDGuardState;   // stage 0 nothing done, 1 switches off (at ta); t0 = first early start
// next (1.8.7.5): the crashes after step 1 or 1b count from the next start, not from ta (what it set at the 8 s look is in force from the next start
// only: a part it stopped loading, a setting SpringBoard reads as it starts -- MSBDGuardSetAtNextStart; audit L103 of 1.8.7.2 and its review)
// prev (1.8.7.5, review of round 2): when ta is a start's time, the SpringBoard that ended just before that start (the mark's pid then; else 0).
// Its crash is before ta whatever second its report's name gives, so it never counts from ta (MSBDGuardFrom).
// wfakes (1.8.7.7, test builds): simulated WEAK crashes (a test report judged UNPINNED); fakes are the strong ones. An older build reads 7 fields.

#if DEBUG
// Test builds only: while /tmp/msb-fakecrash exists, every SpringBoard start counts as coming after a crash (no crash needed), and the file is not
// removed after 60 s. Decisions are logged to /tmp/msbd-crashguard.log.
static inline int MSBDGuardFake(void) { return access("/tmp/msb-fakecrash", F_OK) == 0; }
// /tmp/msb-nocrashguard: the guard does nothing (for tests that crash SpringBoard on purpose).
static inline int MSBDGuardOff(void) { return access("/tmp/msb-nocrashguard", F_OK) == 0; }
// /tmp/msb-fakecrash-report: a crash report (e.g. a copy of tools/crash-fixtures/*.ips). While it exists, every SpringBoard start counts as coming
// after a crash, like /tmp/msb-fakecrash, but that crash only counts if the report points at us (judged fresh each time, never cached); the Aerial
// 5.0 probation sees it as a crash since its mark too. The verdict and the blamed image are logged.
#define MSBD_GUARD_FAKE_REPORT "/tmp/msb-fakecrash-report"
static inline int MSBDGuardFakeReportExists(void) { return access(MSBD_GUARD_FAKE_REPORT, F_OK) == 0; }
#define MSBDGuardLog(...) do { FILE *lf = fopen("/tmp/msbd-crashguard.log", "a"); if (lf) { fprintf(lf, "%ld pid %d: ", (long)time(NULL), getpid()); fprintf(lf, __VA_ARGS__); fputc('\n', lf); fclose(lf); } } while (0)
#else
static inline int MSBDGuardFake(void) { return 0; }
static inline int MSBDGuardOff(void) { return 0; }
static inline int MSBDGuardFakeReportExists(void) { return 0; }
#define MSBDGuardLog(...) do { } while (0)
#endif

static inline int MSBDGuardRead(MSBDGuardState *s) {
    FILE *f = fopen(MSBD_GUARD_FILE, "r");
    if (!f) return 0;
    int n = fscanf(f, "%d %ld %d %ld %d %d %d %d", &s->pid, &s->t0, &s->stage, &s->ta, &s->fakes, &s->next, &s->prev, &s->wfakes), ok = n >= 5;
    fclose(f);
    if (n == 5) s->next = 0;   // (a mark of 1.8.7.4 or before: five fields)
    if (n < 7) s->prev = 0;    // (five or six fields: no start's count kept one)
    if (n < 8) s->wfakes = 0;  // (seven fields: 1.8.7.5 to 1.8.7.6)
    if (!ok) { s->pid = 0; s->t0 = time(NULL); s->stage = 0; s->ta = 0; s->fakes = 0; s->next = 0; s->prev = 0; s->wfakes = 0; }   // (unreadable: a new row of starts)
    return 1;
}
// The mark was last written before this boot (a reboot or a dead battery within 60 s of a start leaves it behind): it is not a row of early
// starts any more. Without this, crashes of the stock SpringBoard while the device was not jailbroken (Apple code only, which counts) were judged
// against that old row at the first jailbroken start and could switch the tweak off. (Dopamine's jailbreak is a userspace reboot: the boot time
// stays, so a crash loop followed by re-jailbreaking is still one row.)
static inline int MSBDGuardMarkBeforeBoot(void) {
    struct stat st; struct timeval boot = {0, 0}; size_t n = sizeof(boot);
    if (stat(MSBD_GUARD_FILE, &st) != 0 || sysctlbyname("kern.boottime", &boot, &n, NULL, 0) != 0 || boot.tv_sec <= 0) return 0;
    return (long)st.st_mtime < (long)boot.tv_sec;
}
static inline void MSBDGuardWrite(const MSBDGuardState *s) {
    FILE *f = fopen(MSBD_GUARD_FILE ".new", "w");
    if (!f) return;
    fprintf(f, "%d %ld %d %ld %d %d %d %d\n", s->pid, s->t0, s->stage, s->ta, s->fakes, s->next, s->prev, s->wfakes);   // (an older build reads the first five to seven)
    fclose(f);
    rename(MSBD_GUARD_FILE ".new", MSBD_GUARD_FILE);
}

// A function of MacCrashBlame.dylib (opened on first use; NULL if it is missing).
static inline void *MSBDGuardHelper(const char *symbol) {
    void *h = dlopen(MSBD_GUARD_BLAME_LIB, RTLD_NOW | RTLD_LOCAL);
    return h ? dlsym(h, symbol) : NULL;
}
// A text cut to a buffer ends on a whole UTF-8 character (1.8.7.7: a cause in another language cut mid-character made the verdict file and the
// record unreadable for Settings, whose readers want UTF-8): a last character left incomplete is taken off.
static inline void MSBDGuardUTF8Whole(char *s) {
    size_t n = strlen(s), k = n, cont = 0;
    while (k > 0 && ((unsigned char)s[k - 1] & 0xC0) == 0x80 && cont < 4) { k--; cont++; }
    if (k == 0) return;
    unsigned char lead = (unsigned char)s[k - 1];
    size_t need = lead >= 0xF0 ? 3 : lead >= 0xE0 ? 2 : lead >= 0xC0 ? 1 : 0;
    if (lead < 0x80) { if (cont) s[k] = 0; return; }   // (stray continuation bytes after an ASCII character)
    if (cont < need) s[k - 1] = 0;
}
// Asks MacCrashBlame.dylib about one report: kMSBDVerdict..., or -1 if the helper is missing (the crash then counts, as before). `cause` (cn bytes;
// NULL: not wanted) gets "<cause>\t<where>\t<n> <other tweaks>" (1.8.7.7, CrashBlameHelper.m MSBDCrashJudge; "" if the helper cannot say).
static inline int MSBDGuardJudgeFull(const char *path, char *blamed, size_t n, char *cause, size_t cn) {
    static int (*judge)(const char *, char *, size_t, char *, size_t);
    static int (*blame)(const char *, char *, size_t);
    if (!judge && !blame) {
        judge = (int (*)(const char *, char *, size_t, char *, size_t))MSBDGuardHelper("MSBDCrashJudge");
        if (!judge) blame = (int (*)(const char *, char *, size_t))MSBDGuardHelper("MSBDCrashBlame");
    }
    snprintf(blamed, n, "(helper not available)");
    if (cause && cn) cause[0] = 0;
    if (!judge && !blame) return -1;
    int v = judge ? judge(path, blamed, n, cause, cn) : blame(path, blamed, n);
    for (char *c = blamed; *c; c++) if (*c == ' ' || *c == '\n' || *c == '\r' || *c == '\t') *c = '_';   // (one word in the verdict file)
    if (cause) for (char *c = cause; *c; c++) if (*c == '\n' || *c == '\r') *c = ' ';   // (one line; its tabs part it)
    MSBDGuardUTF8Whole(blamed);
    if (cause) MSBDGuardUTF8Whole(cause);
    return v >= kMSBDVerdictUnknown && v <= kMSBDVerdictUnpinned ? v : kMSBDVerdictUnknown;
}
static inline int MSBDGuardJudge(const char *path, char *blamed, size_t n) { return MSBDGuardJudgeFull(path, blamed, n, NULL, 0); }
// Strong or weak (1.8.7.7, #14): UNPINNED -- only Apple code on the stacks, another tweak loaded -- is weak; every other counted verdict (ours,
// Apple code alone, unreadable, the helper missing) is strong.
static inline int MSBDGuardWeak(int v) { return v == kMSBDVerdictUnpinned; }
// The helper's cause line (review of 1.8.7.7: 640 bytes cut the other tweaks off the end of a long one): the cause at most 420 bytes, where 200, the
// other tweaks 300 and their count (CrashBlame.h MSBD_CAUSE_BYTES, MSBD_WHERE_BYTES, MSBD_OTHERS_BYTES: bytes, not characters), two tabs.
#define MSBD_GUARD_CAUSE_MAX 1024
#define MSBD_GUARD_LINE_MAX (600 + MSBD_GUARD_CAUSE_MAX)   // (a verdict line: report, verdict, blamed (< 256), then the cause line)
// Kept: the last 40 verdicts plus this one (written whole and renamed; a name per thread, as the 8 s look and the Aerial check may overlap).
// `cause`: the helper's "<cause>\t<where>\t<others>" (NULL or "": none).
static inline void MSBDGuardKeepVerdict(const char *name, int v, const char *blamed, const char *cause) {
    char line[MSBD_GUARD_LINE_MAX], *keep = (char *)calloc(40, MSBD_GUARD_LINE_MAX); int k = 0;
    if (!keep) return;
    FILE *f;
    if ((f = fopen(MSBD_GUARD_VERDICTS, "r"))) {
        while (fgets(line, sizeof(line), f)) if (strchr(line, '\n')) { strlcpy(keep + (k % 40) * MSBD_GUARD_LINE_MAX, line, MSBD_GUARD_LINE_MAX); k++; }
        fclose(f);
    }
    char tmp[300];
    snprintf(tmp, sizeof(tmp), "%s.%d.%lx", MSBD_GUARD_VERDICTS, getpid(), (unsigned long)pthread_mach_thread_np(pthread_self()));
    if ((f = fopen(tmp, "w"))) {
        for (int i = k > 40 ? k - 40 : 0; i < k; i++) fputs(keep + (i % 40) * MSBD_GUARD_LINE_MAX, f);
        snprintf(line, sizeof line - 1, "%s %d %s\t%s", name, v, blamed, cause ? cause : "");   // (with its line break, whole in a read of MSBD_GUARD_LINE_MAX)
        line[strcspn(line, "\r\n")] = 0;
        MSBDGuardUTF8Whole(line);
        fprintf(f, "%s\n", line);
        fclose(f);
        rename(tmp, MSBD_GUARD_VERDICTS);
    }
    free(keep);
}
// The crash the guard's record tells about (only used when it acts): the latest counted crash of a look, one of ours before any other, a strong
// one before a weak one; and, in test builds, the test report's. cause: the helper's cause line for it ("" if none).
typedef struct { long t; int verdict; char path[512], blamed[256], cause[MSBD_GUARD_CAUSE_MAX]; } MSBDGuardCrash;
static MSBDGuardCrash gMSBDLastCrash, gMSBDFakeCrash;
static inline int MSBDGuardCrashRank(int v) { return v == kMSBDVerdictOurs ? 3 : MSBDGuardWeak(v) ? 1 : 2; }
static inline void MSBDGuardNoteCrash(MSBDGuardCrash *c, long t, int v, const char *path, const char *blamed, const char *cause) {
    int better = !c->path[0] || MSBDGuardCrashRank(v) > MSBDGuardCrashRank(c->verdict) || (MSBDGuardCrashRank(v) == MSBDGuardCrashRank(c->verdict) && t >= c->t);
    if (!better) return;
    c->t = t; c->verdict = v;
    strlcpy(c->path, path, sizeof(c->path)); strlcpy(c->blamed, blamed, sizeof(c->blamed)); strlcpy(c->cause, cause ? cause : "", sizeof(c->cause));
    MSBDGuardUTF8Whole(c->blamed); MSBDGuardUTF8Whole(c->cause);
}
// A report that could not be read and is new may still be being written. At SpringBoard's start (gMSBDGuardAtStart) it is "pending": not counted
// then, and the guard does not act on it; the 8 s look decides with the finished report (there, and everywhere else, it counts as before).
static int gMSBDGuardAtStart, gMSBDGuardPending;
static int gMSBDGuardPrevPid;   // (at SpringBoard's start: the SpringBoard before this one, the mark's pid; 0 without a mark: MSBDGuardState.prev)
#define kMSBDGuardPending (-2)
// A report's verdict line in the verdict file (its last one): the verdict, `blamed` (bn bytes) and the cause line after the first tab (`cause`, cn
// bytes); -1 and both "" if there is none.
static inline int MSBDGuardVerdictLine(const char *name, char *blamed, size_t bn, char *cause, size_t cn) {
    char line[MSBD_GUARD_LINE_MAX], rname[256], b[256], found[256] = "", foundCause[MSBD_GUARD_CAUSE_MAX] = ""; int v = -1;
    FILE *f = fopen(MSBD_GUARD_VERDICTS, "r");
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            int rv;
            if (sscanf(line, "%255s %d %255s", rname, &rv, b) == 3 && strcmp(rname, name) == 0) {
                v = rv; strlcpy(found, b, sizeof(found));
                char *tab = strchr(line, '\t');
                strlcpy(foundCause, tab ? tab + 1 : "", sizeof(foundCause)); foundCause[strcspn(foundCause, "\r\n")] = 0; MSBDGuardUTF8Whole(foundCause);
            }
        }
        fclose(f);
    }
    strlcpy(blamed, found, bn); strlcpy(cause, foundCause, cn);
    return v;
}
// The class an "-[Class selector]: ..." cause names can be another tweak's that loads after ours (alphabetically): not there yet when the start judges,
// so the cause went without "(that class is in <library>)" and was kept so (review of 1.8.7.7). Such reports, judged in this process, are noted here
// and asked again 8 s after an early start, when every tweak has loaded (MSBDGuardClassLook): the verdict again with the library, and the record's
// cause line if it is that crash's. A normal start judges nothing, so it notes nothing and asks nothing.
#define MSBD_GUARD_CLASS_LATER 8
static char gMSBDGuardClassLater[MSBD_GUARD_CLASS_LATER][256];
static int gMSBDGuardClassLaterN;
static pthread_mutex_t gMSBDGuardClassLock = PTHREAD_MUTEX_INITIALIZER;
static inline int MSBDGuardClassAsked(const char *causeLine) {   // (its first part names a class, and no library yet)
    char first[MSBD_GUARD_CAUSE_MAX];
    strlcpy(first, causeLine ? causeLine : "", sizeof first); first[strcspn(first, "\t")] = 0;
    return (strstr(first, "-[") || strstr(first, "+[")) && !strstr(first, "(that class is in ");
}
static inline void MSBDGuardClassNote(const char *name, const char *causeLine) {
    if (!MSBDGuardClassAsked(causeLine)) return;
    pthread_mutex_lock(&gMSBDGuardClassLock);
    int known = 0;
    for (int i = 0; i < gMSBDGuardClassLaterN; i++) known |= strcmp(gMSBDGuardClassLater[i], name) == 0;
    if (!known && gMSBDGuardClassLaterN < MSBD_GUARD_CLASS_LATER) strlcpy(gMSBDGuardClassLater[gMSBDGuardClassLaterN++], name, sizeof(gMSBDGuardClassLater[0]));
    pthread_mutex_unlock(&gMSBDGuardClassLock);
}
static inline int MSBDGuardClassNoted(void) { pthread_mutex_lock(&gMSBDGuardClassLock); int n = gMSBDGuardClassLaterN; pthread_mutex_unlock(&gMSBDGuardClassLock); return n; }
// The verdict on one report: from the verdict file, else judged now (and kept, unless it could not be read and the report is new: it may still be
// being written, so it is judged again next time -- kMSBDGuardPending at a start). -1: the helper is missing (counted, strong, as before).
static inline int MSBDGuardVerdictOf(const char *name, const char *path, long mtime, long t) {
    char blamed[256], cause[MSBD_GUARD_CAUSE_MAX];
    int v = MSBDGuardVerdictLine(name, blamed, sizeof(blamed), cause, sizeof(cause));
    if (v < kMSBDVerdictUnknown || v > kMSBDVerdictUnpinned) {
        v = MSBDGuardJudgeFull(path, blamed, sizeof(blamed), cause, sizeof(cause));
        if (v > kMSBDVerdictUnknown || (v == kMSBDVerdictUnknown && (long)time(NULL) - mtime > 20)) {   // (helper missing: nothing kept)
            MSBDGuardKeepVerdict(name, v, blamed, cause);
            MSBDGuardClassNote(name, cause);   // (review of 1.8.7.7: its class's library asked again at 8 s)
        } else if (v == kMSBDVerdictUnknown && gMSBDGuardAtStart) {
            gMSBDGuardPending++;
            MSBDGuardLog("report %s: could not be read yet (new, may still be being written) -- decided at the 8 s look", name);
            return kMSBDGuardPending;
        }
        MSBDGuardLog("report %s: %s (%s) -- %s; %s", name, v == kMSBDVerdictOurs ? "ours" : v == kMSBDVerdictApple ? "Apple code only" : v == kMSBDVerdictOther ? "another tweak's"
                     : v == kMSBDVerdictUnpinned ? "Apple code only, other tweaks loaded" : "could not be judged",
                     blamed, v == kMSBDVerdictOther ? "not counted" : MSBDGuardWeak(v) ? "counted as weak (not pinned)" : "counted", cause);
    }
    if (v != kMSBDVerdictOther) MSBDGuardNoteCrash(&gMSBDLastCrash, t, v, path, blamed, cause);
    return v;
}
// Does one report count against us? 0 no (another tweak's, or pending at a start), 1 strong, 2 weak (1.8.7.7).
static inline int MSBDGuardCounts(const char *name, const char *path, long mtime, long t) {
    int v = MSBDGuardVerdictOf(name, path, mtime, t);
    return v == kMSBDGuardPending || v == kMSBDVerdictOther ? 0 : MSBDGuardWeak(v) ? 2 : 1;
}
#if DEBUG
// The test report (/tmp/msb-fakecrash-report): -1 if there is none, else 0 (another tweak's: not counted), 1 strong or 2 weak (1.8.7.7).
static inline int MSBDGuardFakeReport(void) {
    if (!MSBDGuardFakeReportExists()) return -1;
    char blamed[256], cause[MSBD_GUARD_CAUSE_MAX];
    int v = MSBDGuardJudgeFull(MSBD_GUARD_FAKE_REPORT, blamed, sizeof(blamed), cause, sizeof(cause));
    MSBDGuardLog("test report %s: verdict %d (%s) -- %s; %s", MSBD_GUARD_FAKE_REPORT, v, blamed, v == kMSBDVerdictOther ? "not counted" : MSBDGuardWeak(v) ? "counted as weak" : "counted", cause);
    if (v != kMSBDVerdictOther) MSBDGuardNoteCrash(&gMSBDFakeCrash, (long)time(NULL), v, MSBD_GUARD_FAKE_REPORT, blamed, cause);
    return v == kMSBDVerdictOther ? 0 : MSBDGuardWeak(v) ? 2 : 1;
}
// The test report as the latest SpringBoard crash in the verdict file (the loader only, once per start), so Settings sees it like a real one
// (the note about another tweak's crash).
static inline void MSBDGuardKeepFakeVerdict(void) {
    if (!MSBDGuardFakeReportExists()) return;
    char blamed[256], cause[MSBD_GUARD_CAUSE_MAX], name[64];
    int v = MSBDGuardJudgeFull(MSBD_GUARD_FAKE_REPORT, blamed, sizeof(blamed), cause, sizeof(cause));
    time_t now = time(NULL); struct tm tm; localtime_r(&now, &tm);
    strftime(name, sizeof(name), "SpringBoard-%Y-%m-%d-%H%M%S.test.ips", &tm);
    if (v >= kMSBDVerdictUnknown) MSBDGuardKeepVerdict(name, v, blamed, cause);
}
#else
static inline int MSBDGuardFakeReport(void) { return -1; }
static inline void MSBDGuardKeepFakeVerdict(void) { }
#endif

// The pid of the SpringBoard a report tells about (its body's "pid", read by MacCrashBlame.dylib MSBDCrashPid); -1 if it cannot be told.
static inline int MSBDGuardReportPid(const char *path) {
    static int (*pidOf)(const char *);
    if (!pidOf) pidOf = (int (*)(const char *))MSBDGuardHelper("MSBDCrashPid");
    return pidOf ? pidOf(path) : -1;
}
// Is a report (t: the time in its name, whole seconds) one of the crashes from `since` on? `prev` (MSBDGuardState.prev; 0: none): when `since` is a
// start's time, the SpringBoard that ended just before that start. Its crash is not one, whatever second its report names (1.8.7.5, review of
// round 2): SpringBoard is often back within the second of its crash, so its report names the start's own second (and one named when it was
// written, late, a later second). Only that SpringBoard's reports are told apart, by their pid; a report that cannot be told is one, as before.
static inline int MSBDGuardFrom(const char *name, const char *path, long t, long since, int prev) {
    if (t < since) return 0;
    if (prev > 0 && MSBDGuardReportPid(path) == prev) { MSBDGuardLog("report %s: the crash of SpringBoard %d, which ended before %ld -- not counted from then", name, prev, since); return 0; }
    return 1;
}
// SpringBoard crashes from `since` on (MSBDGuardFrom, `prev` as there), by the time in the report's name (the crash itself, not when the report was
// written): `S` strong and `W` weak crashes that count against us (MSBDGuardCounts), `O` other tweaks' crashes (1.8.7.7: the loop breaker needs
// them); `SA` and `WA` (review of 1.8.7.7): the strong and weak ones after the newest of those other tweaks' crashes (all of them if there is none),
// which the loop breaker counts. Any pointer may be NULL.
#define MSBD_GUARD_TALLY_KEEP 256   // (the times kept to tell what came after the newest other tweak's crash; more counts as after it)
static inline void MSBDGuardTallyRow(long since, int prev, int *S, int *W, int *O, int *SA, int *WA) {
    int s = 0, w = 0, o = 0, n = 0, sa = 0, wa = 0;
    long newestOther = 0, ts[MSBD_GUARD_TALLY_KEEP]; char weak[MSBD_GUARD_TALLY_KEEP];
    DIR *d = opendir(MSBD_GUARD_REPORTS);
    struct dirent *e;
    while (d && (e = readdir(d))) {
        if (strncmp(e->d_name, "SpringBoard-", 12) != 0 || !strstr(e->d_name, ".ips")) continue;   // (not SpringBoard.cpu_resource-... and the like)
        struct tm tm; memset(&tm, 0, sizeof(tm));
        long t = 0;
        char p[512]; struct stat st;
        snprintf(p, sizeof(p), "%s/%s", MSBD_GUARD_REPORTS, e->d_name);
        long mtime = stat(p, &st) == 0 ? (long)st.st_mtime : 0;
        if (sscanf(e->d_name + 12, "%4d-%2d-%2d-%2d%2d%2d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec) == 6) {
            tm.tm_year -= 1900; tm.tm_mon -= 1; tm.tm_isdst = -1;
            t = (long)mktime(&tm);
        } else t = mtime;
        if (!MSBDGuardFrom(e->d_name, p, t, since, prev)) continue;
        int v = MSBDGuardVerdictOf(e->d_name, p, mtime, t);
        if (v == kMSBDGuardPending) continue;
        if (v == kMSBDVerdictOther) { o++; if (o == 1 || t > newestOther) newestOther = t; continue; }
        if (MSBDGuardWeak(v)) w++;
        else s++;
        if (n < MSBD_GUARD_TALLY_KEEP) { ts[n] = t; weak[n] = (char)MSBDGuardWeak(v); n++; }
        else if (MSBDGuardWeak(v)) wa++;   // (past the kept times: counted as after)
        else sa++;
    }
    if (d) closedir(d);
    for (int i = 0; i < n; i++) if (!o || ts[i] > newestOther) { if (weak[i]) wa++; else sa++; }
    if (S) *S = s;
    if (W) *W = w;
    if (O) *O = o;
    if (SA) *SA = sa;
    if (WA) *WA = wa;
}
static inline void MSBDGuardTallyFrom(long since, int prev, int *S, int *W, int *O) { MSBDGuardTallyRow(since, prev, S, W, O, NULL, NULL); }
// SpringBoard crashes from `since` on that count against us, strong or weak (MSBDGuardTallyFrom: S + W; the count before 1.8.7.7 had them all).
static inline int MSBDGuardCrashesFrom(long since, int prev) { int s = 0, w = 0; MSBDGuardTallyFrom(since, prev, &s, &w, NULL); return s + w; }
// Every SpringBoard crash at or after `since` that counts against us, the previous SpringBoard's too (the Aerial 5.0 probation, StatusBar.x: it
// looks for exactly that crash; weak ones too, as before 1.8.7.7).
static inline int MSBDGuardCrashes(long since) { return MSBDGuardCrashesFrom(since, 0); }

// Writes a preference in the current user's domain: a boolean (0/1) or a number.
enum { kMSBDBool, kMSBDNumber };
static inline void MSBDGuardSetPref(const char *domain, const char *key, int kind, int value) {
    void *cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY | RTLD_NOLOAD);
    if (!cf) return;
    const void *(*mk)(const void *, const char *, unsigned int) = (const void *(*)(const void *, const char *, unsigned int))dlsym(cf, "CFStringCreateWithCString");
    const void *(*num)(const void *, long, const void *) = (const void *(*)(const void *, long, const void *))dlsym(cf, "CFNumberCreate");
    void (*set)(const void *, const void *, const void *, const void *, const void *) = (void (*)(const void *, const void *, const void *, const void *, const void *))dlsym(cf, "CFPreferencesSetValue");
    unsigned char (*sync)(const void *, const void *, const void *) = (unsigned char (*)(const void *, const void *, const void *))dlsym(cf, "CFPreferencesSynchronize");
    void (*rel)(const void *) = (void (*)(const void *))dlsym(cf, "CFRelease");
    const void **user = (const void **)dlsym(cf, "kCFPreferencesCurrentUser"), **host = (const void **)dlsym(cf, "kCFPreferencesAnyHost");
    const void **yes = (const void **)dlsym(cf, "kCFBooleanTrue"), **no = (const void **)dlsym(cf, "kCFBooleanFalse");
    if (mk && num && set && sync && rel && user && host && yes && no) {
        const void *k = mk(NULL, key, 0x08000100), *d = mk(NULL, domain, 0x08000100);   // (kCFStringEncodingUTF8)
        const void *v = kind == kMSBDNumber ? num(NULL, 9, &value) : (value ? *yes : *no);   // (kCFNumberIntType)
        if (k && d && v) { set(k, v, d, *user, *host); sync(d, *user, *host); }
        if (kind == kMSBDNumber && v) rel(v);
        if (k) rel(k);
        if (d) rel(d);
    }
    dlclose(cf);
}

// Writes a text in the current user's domain (a list row's choice: the crash guard's step 1b sets Dock Style to "default", a Style to "stock").
static inline void MSBDGuardSetPrefText(const char *domain, const char *key, const char *text) {
    void *cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY | RTLD_NOLOAD);
    if (!cf) return;
    const void *(*mk)(const void *, const char *, unsigned int) = (const void *(*)(const void *, const char *, unsigned int))dlsym(cf, "CFStringCreateWithCString");
    void (*set)(const void *, const void *, const void *, const void *, const void *) = (void (*)(const void *, const void *, const void *, const void *, const void *))dlsym(cf, "CFPreferencesSetValue");
    unsigned char (*sync)(const void *, const void *, const void *) = (unsigned char (*)(const void *, const void *, const void *))dlsym(cf, "CFPreferencesSynchronize");
    void (*rel)(const void *) = (void (*)(const void *))dlsym(cf, "CFRelease");
    const void **user = (const void **)dlsym(cf, "kCFPreferencesCurrentUser"), **host = (const void **)dlsym(cf, "kCFPreferencesAnyHost");
    if (mk && set && sync && rel && user && host) {
        const void *k = mk(NULL, key, 0x08000100), *d = mk(NULL, domain, 0x08000100), *v = mk(NULL, text, 0x08000100);   // (kCFStringEncodingUTF8)
        if (k && d && v) { set(k, v, d, *user, *host); sync(d, *user, *host); }
        if (v) rel(v);
        if (k) rel(k);
        if (d) rel(d);
    }
    dlclose(cf);
}

// What step 1 or 1b sets that is in force from the next SpringBoard start only (1.8.7.5, review of audit L103 and L62 of 1.8.7.2): a part step 1b
// stops loading (CrashStep.h), and a setting SpringBoard reads once, as it starts -- Menu Bar Size (StatusBar.x DMBarSizeInit: iOS's bar takes its
// size then, common/MenuBarSize.h) and the stock status bar (Status Bar Style: StatusBar.x gStockBar, the whole run is one mode). Set at the 8 s
// look, such a change cannot help the SpringBoard that is running, so the crashes after it count from the next start (MSBDGuardEvaluate). Every
// other switch the guard sets applies at once (its prefsChanged).
#include "DisplayPrefs.h"   // (MSBD_DISP_MSB_DOMAIN: Mac Status Bar's domain, a test one in the Mac tests)
#include "MenuBarSize.h"    // (kMSBDMenuBarSizeKey)
static int gMSBDGuardNextStartNow;   // (this evaluation's changes of that kind; MSBDGuardEvaluate clears it)
static inline int MSBDGuardSetAtNextStart(const char *domain, const char *key) {
    return domain && key && strcmp(domain, MSBD_DISP_MSB_DOMAIN) == 0 && (strcmp(key, kMSBDMenuBarSizeKey) == 0 || strcmp(key, "stockStatusBar") == 0);
}
// Step 1: the switches noted as turned on at or after `since` go off again (only our own domains); returns how many. The list is used up either way.
// `record` (n bytes) gets a "switch <domain> <key> <row title>" line for each, for the guard's record.
static inline int MSBDGuardSwitchOffRecent(long since, char *record, size_t rn) {
    FILE *f = fopen(MSBD_GUARD_RECENT, "r");
    int n = 0;
    if (record && rn) record[0] = 0;
    if (f) {
        long t; char line[512], domain[128], key[128], note[300];
        while (fgets(line, sizeof(line), f)) {   // "<time> <domain> <key> <row title>" (the title since 2026-09-26; older lines have none)
            int at = 0;
            if (sscanf(line, "%ld %127s %127s %n", &t, domain, key, &at) < 3) continue;
            if (t < since || strncmp(domain, "com.besiktasliseba.", 19) != 0) continue;
            char *title = at > 0 ? line + at : line + strlen(line);
            title[strcspn(title, "\r\n")] = 0;
            if (record) { size_t l = strlen(record); snprintf(record + l, rn - l, "switch %s %s %s\n", domain, key, title); }
            MSBDGuardSetPref(domain, key, kMSBDBool, 0);
            if (MSBDGuardSetAtNextStart(domain, key)) gMSBDGuardNextStartNow++;   // (Menu Bar Size: from the next start, above)
            snprintf(note, sizeof(note), "%s/prefsChanged", domain);   // (a part that is running applies it at once)
            notify_post(note);
            MSBDGuardLog("switched off %s %s (turned on at %ld)", domain, key, t);
            n++;
        }
        fclose(f);
    }
    unlink(MSBD_GUARD_RECENT);
    return n;
}

#include "CrashStep.h"   // (step 1b: only the feature or part that crashed goes off -- the hook is marked "step 1b" below)

// Looks at the crashes of this row of early starts and acts on them; returns 1 if it did something.
// The guard's record (only when it acts): what it did and why, for the Settings pages' footer and the Report a Problem text (LineSwitch.h,
// CrashExplain.h). "<name> <value>" lines: time, action (as crashGuardAction), tested (0 untested iPadOS), ios, build, verdict (kMSBDVerdict...,
// -1 simulated), blamed (the helper's word for it), then "switch" lines (step 1), step 1b's lines (CrashStep.h; a part still skipped is named in
// step 1's record too) and up to 5 "frame" lines (our image's frames only).
// 1.8.7.7 (#14): what crashed, for that crash -- "cause <text>", "where <frame (image)>", "others <n> <library names>" (CrashBlame.h, the helper's
// cause line) --, "unknown <n>" (weak crashes in the row: not pinned on us or anyone) and "loop 1" (rule 4, the loop breaker, acted). A build
// before reads only the names it knows.
static int gMSBDGuardRowWeak, gMSBDGuardRowLoop;   // (this evaluation's: MSBDGuardEvaluate sets them)
static inline void MSBDGuardWriteRecord(int action, int tested, const char *switches) {
    char ios[32] = "unknown"; size_t n = sizeof(ios);
    if (sysctlbyname("kern.osproductversion", ios, &n, NULL, 0) != 0) strlcpy(ios, "unknown", sizeof(ios));
    MSBDGuardCrash c = gMSBDLastCrash;
    if (gMSBDFakeCrash.path[0] && (!c.path[0] || gMSBDFakeCrash.t >= c.t)) c = gMSBDFakeCrash;
    char frames[1024] = "";
    if (c.path[0] && c.verdict == kMSBDVerdictOurs) {
        int (*get)(const char *, char *, size_t) = (int (*)(const char *, char *, size_t))MSBDGuardHelper("MSBDCrashFrames");
        if (get) get(c.path, frames, sizeof(frames));
    }
    FILE *f = fopen(MSBD_GUARD_RECORD ".new", "w");
    if (!f) return;
#if DEBUG
    const char *kind = " (test build)";
#else
    const char *kind = "";
#endif
    fprintf(f, "time %ld\naction %d\ntested %d\nios %s\nbuild %s%s\nverdict %d\nblamed %s\n", (long)time(NULL), action, tested, ios, MSBD_BUILD_VERSION, kind, c.path[0] ? c.verdict : -1, c.path[0] ? c.blamed : "(simulated)");
    if (c.path[0] && c.cause[0]) {   // ("<cause>\t<where>\t<n> <names>")
        char cause[MSBD_GUARD_CAUSE_MAX]; strlcpy(cause, c.cause, sizeof cause);
        char *where = strchr(cause, '\t'), *others = where ? strchr(where + 1, '\t') : NULL;
        if (where) *where++ = 0;
        if (others) *others++ = 0;
        if (cause[0]) fprintf(f, "cause %s\n", cause);
        if (where && *where) fprintf(f, "where %s\n", where);
        if (others && atoi(others) > 0) fprintf(f, "others %s\n", others);
    }
    if (gMSBDGuardRowWeak > 0) fprintf(f, "unknown %d\n", gMSBDGuardRowWeak);
    if (gMSBDGuardRowLoop) fprintf(f, "loop 1\n");
    if (switches) fputs(switches, f);
    for (char *line = frames, *next; line && *line; line = next) {
        next = strchr(line, '\n');
        if (next) *next++ = 0;
        fprintf(f, "frame %s\n", line);
    }
    fclose(f);
    rename(MSBD_GUARD_RECORD ".new", MSBD_GUARD_RECORD);
}
// The library of a class a cause names, asked again 8 s after an early start (MSBDGuardClassNote above; the helper's MSBDCrashCauseClass, when every
// tweak has loaded): each noted report's verdict line again, the cause now ending "(that class is in <library>)" (readers take a report's last line),
// and, when the guard's record tells that cause, one more "cause" line (its readers take the last one; appended, as the notice appends its lines).
// The list is used up either way.
static inline void MSBDGuardClassLook(void) {
    char names[MSBD_GUARD_CLASS_LATER][256]; int n;
    pthread_mutex_lock(&gMSBDGuardClassLock);
    n = gMSBDGuardClassLaterN; memcpy(names, gMSBDGuardClassLater, sizeof(names)); gMSBDGuardClassLaterN = 0;
    pthread_mutex_unlock(&gMSBDGuardClassLock);
    if (!n) return;
    int (*again)(const char *, char *, size_t) = (int (*)(const char *, char *, size_t))MSBDGuardHelper("MSBDCrashCauseClass");
    if (!again) return;   // (a helper of 1.8.7.7 before this review: nothing to ask)
    for (int i = 0; i < n; i++) {
        char blamed[256], line[MSBD_GUARD_CAUSE_MAX], first[MSBD_GUARD_CAUSE_MAX], now[MSBD_GUARD_CAUSE_MAX], next[MSBD_GUARD_CAUSE_MAX];
        int v = MSBDGuardVerdictLine(names[i], blamed, sizeof(blamed), line, sizeof(line));
        if (v < kMSBDVerdictUnknown || !MSBDGuardClassAsked(line)) continue;
        strlcpy(first, line, sizeof(first)); first[strcspn(first, "\t")] = 0;
        if (again(first, now, sizeof(now)) != 1 || !now[0]) { MSBDGuardLog("report %s: the class its cause names still not found in a tweak's library", names[i]); continue; }
        for (char *c = now; *c; c++) if (*c == '\t' || *c == '\n' || *c == '\r') *c = ' ';
        MSBDGuardUTF8Whole(now);
        const char *rest = strchr(line, '\t');
        snprintf(next, sizeof(next), "%s%s", now, rest ? rest : "");
        MSBDGuardUTF8Whole(next);
        MSBDGuardKeepVerdict(names[i], v, blamed, next);
        MSBDGuardLog("report %s: %s", names[i], now);
        FILE *f = fopen(MSBD_GUARD_RECORD, "r");   // (the record's last "cause" line, whole lines only)
        char rl[MSBD_GUARD_CAUSE_MAX + 16], last[MSBD_GUARD_CAUSE_MAX + 16] = ""; int start = 1, has = 0;
        while (f && fgets(rl, sizeof(rl), f)) {
            int whole = start;
            start = strchr(rl, '\n') != NULL;
            if (whole && start && strncmp(rl, "cause ", 6) == 0) { strlcpy(last, rl + 6, sizeof(last)); last[strcspn(last, "\r\n")] = 0; has = 1; }
        }
        if (f) fclose(f);
        if (has && strcmp(last, first) == 0 && (f = fopen(MSBD_GUARD_RECORD, "a"))) { fprintf(f, "cause %s\n", now); fclose(f); }
    }
}
static inline void MSBDGuardClassLookAt(void *ctx) { (void)ctx; MSBDGuardClassLook(); }
// Does the guard's record (`record`: MSBD_GUARD_RECORD) name this switch: a step 1 "switch <domain> <key> ..." or a step 1b "feature <domain> <key>
// <value> ..." line? For code the crash map counts under a switch that can also run with that switch off (statusbar/NativeWindow.h
// DMNativeGuardTookFinder: Activity Monitor's and Display Settings' native windows, Finder's in the map). Whole lines only (the rest of a long line
// is never read as one); no record: no.
static inline int MSBDGuardRecordNames(const char *record, const char *domain, const char *key) {
    FILE *f = record ? fopen(record, "r") : NULL;
    if (!f) return 0;
    char line[512], kind[16], d[128], k[128];
    int found = 0, start = 1;
    while (!found && fgets(line, sizeof(line), f)) {
        int whole = start;
        start = strchr(line, '\n') != NULL;   // (the next piece starts a line)
        if (whole && sscanf(line, "%15s %127s %127s", kind, d, k) == 3 && (!strcmp(kind, "switch") || !strcmp(kind, "feature")) && !strcmp(d, domain) && !strcmp(k, key)) found = 1;
    }
    fclose(f);
    return found;
}

// The switches noted as turned on at or after `since` (only our own domains), without using the list up (rule 3 asks before it acts).
static inline int MSBDGuardRecentCount(long since) {
    FILE *f = fopen(MSBD_GUARD_RECENT, "r");
    int n = 0; long t; char line[512], domain[128], key[128];
    while (f && fgets(line, sizeof(line), f)) if (sscanf(line, "%ld %127s %127s", &t, domain, key) == 3 && t >= since && strncmp(domain, "com.besiktasliseba.", 19) == 0) n++;
    if (f) fclose(f);
    return n;
}
static inline int MSBDGuardEvaluate(MSBDGuardState *s) {
    int action;
    char switches[1536] = "";
    memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash));
    gMSBDGuardNextStartNow = 0; gMSBDGuardRowWeak = 0; gMSBDGuardRowLoop = 0;
    if (s->stage == 0) {
        // (1.8.7.7, #14: strong S, weak W and other tweaks' O crashes of the row -- the rules at the top of this file)
        int S = 0, W = 0, O = 0, SA = 0, WA = 0;   // (SA, WA: after the newest other tweak's crash of the row, rule 4)
        MSBDGuardTallyRow(s->t0 - 30, 0, &S, &W, &O, &SA, &WA);
        S += s->fakes; W += s->wfakes; SA += s->fakes; WA += s->wfakes;   // (simulated crashes are this start's: after any report)
        int recent = MSBDGuardRecentCount(s->t0 - 120);
        MSBDGuardLog("row of early starts since %ld: %d strong, %d weak (not pinned), %d other tweaks' crash(es) (%d + %d simulated), %d since the newest of those; %d switch(es) turned on just before", s->t0, S, W, O, s->fakes, s->wfakes, SA + WA, recent);
        gMSBDGuardRowWeak = W;
        if (S >= 2 || (S == 1 && W >= 1)) action = MSBDGuardSwitchOffRecent(s->t0 - 120, switches, sizeof(switches)) ? 1 : 2;   // (rules 1 and 2: as before)
        else if (S == 0 && W >= 2 && recent) {   // (rule 3: what was just turned on goes off again, nothing more)
            if (!MSBDGuardSwitchOffRecent(s->t0 - 120, switches, sizeof(switches))) return 0;
            action = 1;
            MSBDGuardLog("crashes not pinned on anyone, right after switches were turned on: only those switches off");
        } else if (SA + WA >= 4) {   // (rule 4: the loop breaker -- the crashes since the newest other tweak's crash of the row, if any)
            gMSBDGuardRowLoop = 1;
            action = MSBDGuardSwitchOffRecent(s->t0 - 120, switches, sizeof(switches)) ? 1 : 2;
            MSBDGuardLog("SpringBoard keeps crashing (%d) and no other tweak's crash among them%s: the loop breaker acts", SA + WA, O ? " (since the newest one)" : "");
        } else {
            if (S + W) MSBDGuardLog("not enough to act on: %s", S ? "one crash of ours or not judged, nothing seconding it" : "the crashes could not be pinned on MacStatusBar&Dock");
            return 0;
        }
    } else {
        int S = 0, W = 0, O = 0;
        MSBDGuardTallyFrom(s->ta, s->prev, &S, &W, &O);
        S += s->fakes; W += s->wfakes;
        MSBDGuardLog("after switching features off at %ld: %d strong, %d weak (not pinned), %d other tweaks' crash(es) (%d + %d simulated)", s->ta, S, W, O, s->fakes, s->wfakes);
        if (S + W < 1) return 0;
        gMSBDGuardRowWeak = W;
        if (S < 1) {   // (only weak crashes since: on only when the row meets the loop breaker, rule 4 -- since its newest other tweak's crash, if any)
            int rS = 0, rW = 0, rO = 0, rSA = 0, rWA = 0;
            MSBDGuardTallyRow(s->t0 - 30, 0, &rS, &rW, &rO, &rSA, &rWA);
            rS += s->fakes; rW += s->wfakes; rSA += s->fakes; rWA += s->wfakes;
            if (rSA + rWA < 4) { MSBDGuardLog("only crashes not pinned on anyone since: no further step (row: %d strong, %d weak, %d other; %d since the newest other)", rS, rW, rO, rSA + rWA); return 0; }
            gMSBDGuardRowLoop = 1; gMSBDGuardRowWeak = rW;
            MSBDGuardLog("SpringBoard keeps crashing (%d in the row) and no other tweak's crash among them%s: the loop breaker acts", rSA + rWA, rO ? " (since the newest one)" : "");
        }
        action = 3;
    }
    // step 1b (CrashStep.h): before the whole tweak goes off, only what the crashes point at (once per row; else on to step 2 as before).
    if (action != 1 && MSBDGuardStepFeature(s->t0, s->stage == 0 ? s->t0 - 30 : s->ta, s->stage == 0 ? 0 : s->prev, s->stage != 0, switches, sizeof(switches))) action = MSBD_GUARD_ACTION_FEATURE;
    // (step 1, 1.8.7.5, audit L104 of 1.8.7.2: a part step 1b stopped loading in an earlier row stays skipped under this note too, so its record
    //  names it: the footer says so and Turn Back On stays; before, the record had the switches only and the part was off with nothing saying so)
    if (action == 1) { MSBDStepList kept; MSBDStepReadList(&kept); MSBDStepRecordKept(&kept, kept.count, NULL, switches, sizeof(switches)); }
    s->stage = action == 1 || action == MSBD_GUARD_ACTION_FEATURE ? 1 : 2;
    s->ta = (long)time(NULL); s->fakes = 0; s->wfakes = 0;
    s->prev = gMSBDGuardAtStart ? gMSBDGuardPrevPid : 0;   // (at a start, the crash just acted on can share its second: MSBDGuardFrom; at the look it is 8 s old)
    // (1.8.7.5, audit L103 of 1.8.7.2: a part step 1b stops loading at the 8 s look stays loaded in this SpringBoard until it ends, so the crashes
    //  after the skip count from the next start: this SpringBoard's own later crash is not held against the skip, which then gets its start. So
    //  does a setting step 1 or 1b sets back that SpringBoard reads as it starts (review: Menu Bar Size, noted for step 1 since L62, and the stock
    //  status bar: MSBDGuardSetAtNextStart). A switch that applies at once (prefsChanged), and anything set at the start (before any part loads),
    //  counts from now, as before.)
    s->next = !gMSBDGuardAtStart && (action == 1 || action == MSBD_GUARD_ACTION_FEATURE) && gMSBDGuardNextStartNow > 0;
    if (s->next) MSBDGuardLog("at the 8 s look: %d change(s) in force from the next start only (a part not loaded, a setting read as SpringBoard starts) -- crashes count from the next start", gMSBDGuardNextStartNow);
    int tested = MSBDVersionTested();
    if (s->stage == 2) MSBDGuardSetPref(MSBD_GATE_DOMAIN, tested ? MSBD_SAFE_KEY : MSBD_GATE_KEY, kMSBDBool, tested ? 1 : 0);
    MSBDGuardWriteRecord(action, tested, switches);   // (before the note the pages read, so they find the record with it)
    MSBDGuardSetPref(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY, kMSBDNumber, action);
    MSBDGuardLog(action == 1 ? "acted: recent switches off" : action == MSBD_GUARD_ACTION_FEATURE ? "acted: the feature/part that crashed off (step 1b)" : (tested ? "acted: safe mode on" : "acted: Enable Anyway off"));
    return 1;
}
static inline void MSBDGuardSave(MSBDGuardState *s) {
    if (s->stage == 2) unlink(MSBD_GUARD_FILE);   // ("Enable Anyway" off / safe mode on: nothing left to guard)
    else MSBDGuardWrite(s);
}

// SpringBoard's loaders (either line), after the guard: the notice part is loaded while the guard's record is unshown and under 7 days old, for at
// most 3 SpringBoard starts that ran 10 s (a "ran" line each, added by the notice) and at most 6 loads in all (a "load" line each, added here: an
// sbreload on the iPad 2 is two starts, so it must not use up the budget, while a notice that crashed early still could not come back again and
// again). The notice adds "shown" when it appears. With no record this is one failed open of a file.
static inline void MSBDGuardNoticeLoad(void) {
    void *h = dlopen(MSBD_GUARD_NOTICE_LIB, RTLD_LAZY | RTLD_NOLOAD);
    if (h) { dlclose(h); return; }   // (the other loader loaded it already)
    FILE *f = fopen(MSBD_GUARD_RECORD, "r");
    if (!f) return;
    char line[512]; int shown = 0, loads = 0, ran = 0; long t = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "shown", 5) == 0) shown = 1;
        else if (strncmp(line, "load ", 5) == 0) loads++;
        else if (strncmp(line, "ran ", 4) == 0) ran++;
        else if (strncmp(line, "time ", 5) == 0) t = atol(line + 5);
    }
    fclose(f);
    long age = (long)time(NULL) - t;
    if (shown || ran >= 3 || loads >= 6 || !t || age < 0 || age > 7 * 86400) return;
    if ((f = fopen(MSBD_GUARD_RECORD, "a"))) { fprintf(f, "load %ld\n", (long)time(NULL)); fclose(f); }
    MSBDGuardLog("loading the notice (load %d)", loads + 1);
    dlopen(MSBD_GUARD_NOTICE_LIB, RTLD_NOW);
}

// 60 s, on the main queue: this SpringBoard is running stably -- the row of early starts is over. Only a main thread that runs then gets here
// (1.8.7.3, audit M1 of 1.8.7.2): a hang that starts 6 to 60 s after a start (a deadlock, a layout loop) is killed by the watchdog about a minute
// later, after the 60 s mark; on a background queue the mark was gone by then and every start of a hang loop looked like a first one. The mark
// now stays, and the watchdog's report counts at the next start like a crash's (CrashBlame.h judges it on the stuck main thread).
static inline void MSBDGuardStable(void *ctx) {
    MSBDGuardState s;
#if DEBUG
    {   // (1.8.7.7, device row D1: is our death record's handler still the one in force, or who replaced it)
        MSBDCauseHandlerFn (*get)(void) = (MSBDCauseHandlerFn (*)(void))dlsym(RTLD_DEFAULT, "NSGetUncaughtExceptionHandler");
        MSBDCauseHandlerFn now = get ? get() : NULL;
        Dl_info di; memset(&di, 0, sizeof di);
        if (now && now != MSBDCauseHandler) dladdr((const void *)now, &di);
        MSBDGuardLog("uncaught handler: %s%s", now == MSBDCauseHandler ? "ours" : now ? "replaced by " : "none", now && now != MSBDCauseHandler ? (di.dli_fname ? di.dli_fname : "(unknown image)") : "");
    }
#endif
    if (MSBDGuardFake() || MSBDGuardFakeReportExists() || !MSBDGuardRead(&s) || s.pid != getpid()) return;
    unlink(MSBD_GUARD_FILE);
    MSBDGuardLog("ran 60 s: cleared");
}
// 8 s: a crash report written late may be there now. Then (review of 1.8.7.7) the class a judged cause names, asked again: every tweak has loaded.
static inline void MSBDGuardLook(void *ctx) {
    MSBDGuardState s;
    if (MSBDGuardRead(&s) && s.pid == getpid() && s.stage != 2 && MSBDGuardEvaluate(&s)) {
        MSBDGuardSave(&s);
        if (s.stage == 1) MSBDGuardNoticeLoad();   // (switches turned off now: say so now; the tweak going off takes a respring, and so does its notice)
    }
    MSBDGuardClassLook();
}

// SpringBoard's loader, before any part loads, whenever the parts are meant to run (MSBDGateWanted). May switch "Enable Anyway" off / safe mode on.
static inline void MSBDCrashGuardStart(void) {
    if (MSBDGuardOff()) return;
    MSBDGuardState s;
    int early = MSBDGuardRead(&s);
    // (the boot first, 1.8.7.5, audit L105 of 1.8.7.2: SpringBoard's pid can come round again after a reboot, and a mark of that pid from before
    //  the boot made this start return at once -- no row, no 8 s look, no 60 s clear. The second loader reads the mark the first wrote now.)
    if (early && MSBDGuardMarkBeforeBoot()) { MSBDGuardLog("mark from before this boot: a new row"); early = 0; }
    if (early && s.pid == getpid()) return;   // (both loaders run in SpringBoard: the first one did it)
    // (1.8.7.7, #14: our death record -- one line naming the exception if this SpringBoard dies of one; once per process, as here; CrashCause.h)
    int causeInstalled = MSBDCauseInstall();
    (void)causeInstalled;
    MSBDGuardLog("uncaught exception handler: %s", causeInstalled ? (gMSBDCausePrev ? "ours, before the one installed earlier" : "ours") : "not installed (Foundation's functions not found)");
    long now = (long)time(NULL);
    int prev = early ? s.pid : 0;   // (the SpringBoard before this one: MSBDGuardState.prev)
    if (!early) { s.t0 = now; s.stage = 0; s.ta = 0; s.fakes = 0; s.next = 0; s.prev = 0; s.wfakes = 0; }
    if (early && s.stage == 1 && s.next) { s.ta = now; s.next = 0; s.prev = prev; MSBDGuardLog("what the last 8 s look set is in force from this start: crashes count from it (not the crash of SpringBoard %d, before it)", prev); }   // (L103, above)
    if (MSBDGuardFake()) { s.fakes++; early = 1; }
    int fake = MSBDGuardFakeReport();   // (test builds: a crash report from a file, counted only if it points at us; 1.8.7.7: weak if not pinned)
    MSBDGuardKeepFakeVerdict();
    if (fake >= 0) { early = 1; if (fake == 1) s.fakes++; else if (fake == 2) s.wfakes++; }
    s.pid = getpid();
    gMSBDGuardAtStart = 1; gMSBDGuardPrevPid = prev; gMSBDGuardPending = 0;
    int acted = early && MSBDGuardEvaluate(&s);   // (a report still being written is left to the 8 s look, which runs whenever this did not act)
    gMSBDGuardAtStart = 0;
    MSBDGuardSave(&s);
    // (review of 1.8.7.7: a cause naming a class judged now is asked again at 8 s, MSBDGuardClassLook -- by the 8 s look when there is one; only after
    //  an early start, as nothing is judged at a normal one)
    int classLater = MSBDGuardClassNoted() > 0;
    if (s.stage == 2) {
        if (classLater) dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), NULL, MSBDGuardClassLookAt);
        return;
    }
    // (the 8 s look on a background queue: it acts with the main thread stuck too; the 60 s clear on the main queue: proof the main thread runs)
    if (early && !acted) dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), NULL, MSBDGuardLook);
    else if (classLater) dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), NULL, MSBDGuardClassLookAt);
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), NULL, MSBDGuardStable);
}
