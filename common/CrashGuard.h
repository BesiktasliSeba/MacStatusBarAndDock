// CrashGuard.h -- the crash guard (MacStatusBar&Dock, 2026-09-25; armed on every iPadOS version since 2026-09-26).
//
// SpringBoard's loader writes a small state file at every start, before any part loads, and removes it once SpringBoard has run 60 s. Found at the
// next start, the previous SpringBoard ended early. That alone is no crash (a respring, Aerial 5.0's own respring after its license check, an
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
// The helper is opened only when a report has to be judged (after an early start), so a normal start costs nothing more.
// Since 2026-09-26 it explains itself: when it acts it writes a small record (MSBD_GUARD_RECORD: what it did, the switches by their row titles, the
// part of ours that was blamed, iPadOS and build, the top frames of our image only), which the pages' footer and the Report a Problem text use
// (CrashExplain.h), and which the one-time notice on the Home Screen shows (loader/CrashNotice.m, loaded only while the record is unshown).
// Cost per SpringBoard start: one small file write, and 60 s later one read and an unlink; the crash-report folder is only listed after an early
// start. The mark has to be written before a crash can happen, so it cannot wait for a crash report to exist.
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
#define MSBD_GUARD_VERDICTS "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashVerdicts.txt"   // "<report> <verdict> <blamed>" lines
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
enum { kMSBDVerdictUnknown = 0, kMSBDVerdictOurs = 1, kMSBDVerdictApple = 2, kMSBDVerdictOther = 3 };   // (= kMSBDBlame..., CrashBlame.h)

typedef struct { int pid, stage, fakes; long t0, ta; } MSBDGuardState;   // stage 0 nothing done, 1 switches off (at ta); t0 = first early start

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
    int ok = fscanf(f, "%d %ld %d %ld %d", &s->pid, &s->t0, &s->stage, &s->ta, &s->fakes) == 5;
    fclose(f);
    if (!ok) { s->pid = 0; s->t0 = time(NULL); s->stage = 0; s->ta = 0; s->fakes = 0; }   // (unreadable: a new row of starts)
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
    fprintf(f, "%d %ld %d %ld %d\n", s->pid, s->t0, s->stage, s->ta, s->fakes);
    fclose(f);
    rename(MSBD_GUARD_FILE ".new", MSBD_GUARD_FILE);
}

// A function of MacCrashBlame.dylib (opened on first use; NULL if it is missing).
static inline void *MSBDGuardHelper(const char *symbol) {
    void *h = dlopen(MSBD_GUARD_BLAME_LIB, RTLD_NOW | RTLD_LOCAL);
    return h ? dlsym(h, symbol) : NULL;
}
// Asks MacCrashBlame.dylib about one report: kMSBDVerdict..., or -1 if the helper is missing (the crash then counts, as before).
static inline int MSBDGuardJudge(const char *path, char *blamed, size_t n) {
    static int (*judge)(const char *, char *, size_t);
    if (!judge) judge = (int (*)(const char *, char *, size_t))MSBDGuardHelper("MSBDCrashBlame");
    snprintf(blamed, n, "(helper not available)");
    if (!judge) return -1;
    int v = judge(path, blamed, n);
    for (char *c = blamed; *c; c++) if (*c == ' ' || *c == '\n' || *c == '\r' || *c == '\t') *c = '_';   // (one word in the verdict file)
    return v >= kMSBDVerdictUnknown && v <= kMSBDVerdictOther ? v : kMSBDVerdictUnknown;
}
// Kept: the last 40 verdicts plus this one (written whole and renamed; a name per thread, as the 8 s look and the Aerial check may overlap).
static inline void MSBDGuardKeepVerdict(const char *name, int v, const char *blamed) {
    char line[400], keep[40][400]; int k = 0;
    FILE *f;
    if ((f = fopen(MSBD_GUARD_VERDICTS, "r"))) {
        while (fgets(line, sizeof(line), f)) if (strchr(line, '\n')) { strlcpy(keep[k % 40], line, sizeof(keep[0])); k++; }
        fclose(f);
    }
    char tmp[300];
    snprintf(tmp, sizeof(tmp), "%s.%d.%lx", MSBD_GUARD_VERDICTS, getpid(), (unsigned long)pthread_mach_thread_np(pthread_self()));
    if ((f = fopen(tmp, "w"))) {
        for (int i = k > 40 ? k - 40 : 0; i < k; i++) fputs(keep[i % 40], f);
        fprintf(f, "%s %d %s\n", name, v, blamed);
        fclose(f);
        rename(tmp, MSBD_GUARD_VERDICTS);
    }
}
// The crash the guard's record tells about (only used when it acts): the latest counted crash of a look, one of ours before any other; and, in
// test builds, the test report's.
typedef struct { long t; int verdict; char path[512], blamed[256]; } MSBDGuardCrash;
static MSBDGuardCrash gMSBDLastCrash, gMSBDFakeCrash;
static inline void MSBDGuardNoteCrash(MSBDGuardCrash *c, long t, int v, const char *path, const char *blamed) {
    int better = !c->path[0] || (v == kMSBDVerdictOurs) > (c->verdict == kMSBDVerdictOurs) || ((v == kMSBDVerdictOurs) == (c->verdict == kMSBDVerdictOurs) && t >= c->t);
    if (!better) return;
    c->t = t; c->verdict = v;
    strlcpy(c->path, path, sizeof(c->path)); strlcpy(c->blamed, blamed, sizeof(c->blamed));
}
// A report that could not be read and is new may still be being written. At SpringBoard's start (gMSBDGuardAtStart) it is "pending": not counted
// then, and the guard does not act on it; the 8 s look decides with the finished report (there, and everywhere else, it counts as before).
static int gMSBDGuardAtStart, gMSBDGuardPending;
// The verdict on one report: from the verdict file, else judged now (and kept, unless it could not be read and the report is new: it may still be
// being written, so it is judged again next time). Returns 1 if the crash counts against us.
static inline int MSBDGuardCounts(const char *name, const char *path, long mtime, long t) {
    char line[400], rname[256], blamed[256], found[256] = ""; int v = -1;
    FILE *f = fopen(MSBD_GUARD_VERDICTS, "r");
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            int rv;
            if (sscanf(line, "%255s %d %255s", rname, &rv, blamed) == 3 && strcmp(rname, name) == 0) { v = rv; strlcpy(found, blamed, sizeof(found)); }
        }
        fclose(f);
    }
    strlcpy(blamed, found, sizeof(blamed));
    if (v < kMSBDVerdictUnknown || v > kMSBDVerdictOther) {
        v = MSBDGuardJudge(path, blamed, sizeof(blamed));
        if (v > kMSBDVerdictUnknown || (v == kMSBDVerdictUnknown && (long)time(NULL) - mtime > 20))   // (helper missing: nothing kept)
            MSBDGuardKeepVerdict(name, v, blamed);
        else if (v == kMSBDVerdictUnknown && gMSBDGuardAtStart) {
            gMSBDGuardPending++;
            MSBDGuardLog("report %s: could not be read yet (new, may still be being written) -- decided at the 8 s look", name);
            return 0;
        }
        MSBDGuardLog("report %s: %s (%s) -- %s", name, v == kMSBDVerdictOurs ? "ours" : v == kMSBDVerdictApple ? "Apple code only" : v == kMSBDVerdictOther ? "another tweak's" : "could not be judged",
                     blamed, v == kMSBDVerdictOther ? "not counted" : "counted");
    }
    if (v != kMSBDVerdictOther) MSBDGuardNoteCrash(&gMSBDLastCrash, t, v, path, blamed);
    return v != kMSBDVerdictOther;
}
#if DEBUG
// The test report (/tmp/msb-fakecrash-report): -1 if there is none, else 1 if it counts against us.
static inline int MSBDGuardFakeReport(void) {
    if (!MSBDGuardFakeReportExists()) return -1;
    char blamed[256];
    int v = MSBDGuardJudge(MSBD_GUARD_FAKE_REPORT, blamed, sizeof(blamed));
    MSBDGuardLog("test report %s: verdict %d (%s) -- %s", MSBD_GUARD_FAKE_REPORT, v, blamed, v == kMSBDVerdictOther ? "not counted" : "counted");
    if (v != kMSBDVerdictOther) MSBDGuardNoteCrash(&gMSBDFakeCrash, (long)time(NULL), v, MSBD_GUARD_FAKE_REPORT, blamed);
    return v != kMSBDVerdictOther;
}
// The test report as the latest SpringBoard crash in the verdict file (the loader only, once per start), so Settings sees it like a real one
// (the note about another tweak's crash).
static inline void MSBDGuardKeepFakeVerdict(void) {
    if (!MSBDGuardFakeReportExists()) return;
    char blamed[256], name[64];
    int v = MSBDGuardJudge(MSBD_GUARD_FAKE_REPORT, blamed, sizeof(blamed));
    time_t now = time(NULL); struct tm tm; localtime_r(&now, &tm);
    strftime(name, sizeof(name), "SpringBoard-%Y-%m-%d-%H%M%S.test.ips", &tm);
    if (v >= kMSBDVerdictUnknown) MSBDGuardKeepVerdict(name, v, blamed);
}
#else
static inline int MSBDGuardFakeReport(void) { return -1; }
static inline void MSBDGuardKeepFakeVerdict(void) { }
#endif

// SpringBoard crashes at or after `since` that count against us (MSBDGuardCounts), by the time in the report's name (the crash itself, not when
// the report was written).
static inline int MSBDGuardCrashes(long since) {
    DIR *d = opendir(MSBD_GUARD_REPORTS);
    if (!d) return 0;
    int n = 0; struct dirent *e;
    while ((e = readdir(d))) {
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
        if (t >= since && MSBDGuardCounts(e->d_name, p, mtime, t)) n++;
    }
    closedir(d);
    return n;
}

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
// -1 simulated), blamed (the helper's word for it), then "switch" lines (step 1) and up to 5 "frame" lines (our image's frames only).
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
    if (switches) fputs(switches, f);
    for (char *line = frames, *next; line && *line; line = next) {
        next = strchr(line, '\n');
        if (next) *next++ = 0;
        fprintf(f, "frame %s\n", line);
    }
    fclose(f);
    rename(MSBD_GUARD_RECORD ".new", MSBD_GUARD_RECORD);
}

static inline int MSBDGuardEvaluate(MSBDGuardState *s) {
    int action;
    char switches[1536] = "";
    memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash));
    if (s->stage == 0) {
        int crashes = MSBDGuardCrashes(s->t0 - 30) + s->fakes;
        MSBDGuardLog("row of early starts since %ld: %d crash(es) (%d simulated)", s->t0, crashes, s->fakes);
        if (crashes < 2) return 0;
        action = MSBDGuardSwitchOffRecent(s->t0 - 120, switches, sizeof(switches)) ? 1 : 2;
    } else {
        int crashes = MSBDGuardCrashes(s->ta) + s->fakes;
        MSBDGuardLog("after switching features off at %ld: %d crash(es) (%d simulated)", s->ta, crashes, s->fakes);
        if (crashes < 1) return 0;
        action = 3;
    }
    // step 1b (CrashStep.h): before the whole tweak goes off, only what the crashes point at (once per row; else on to step 2 as before).
    if (action != 1 && MSBDGuardStepFeature(s->t0, s->stage == 0 ? s->t0 - 30 : s->ta, s->stage != 0, switches, sizeof(switches))) action = MSBD_GUARD_ACTION_FEATURE;
    s->stage = action == 1 || action == MSBD_GUARD_ACTION_FEATURE ? 1 : 2;
    s->ta = (long)time(NULL); s->fakes = 0;
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

// 60 s: this SpringBoard is running stably -- the row of early starts is over.
static inline void MSBDGuardStable(void *ctx) {
    MSBDGuardState s;
    if (MSBDGuardFake() || MSBDGuardFakeReportExists() || !MSBDGuardRead(&s) || s.pid != getpid()) return;
    unlink(MSBD_GUARD_FILE);
    MSBDGuardLog("ran 60 s: cleared");
}
// 8 s: a crash report written late may be there now.
static inline void MSBDGuardLook(void *ctx) {
    MSBDGuardState s;
    if (!MSBDGuardRead(&s) || s.pid != getpid() || s.stage == 2) return;
    if (!MSBDGuardEvaluate(&s)) return;
    MSBDGuardSave(&s);
    if (s.stage == 1) MSBDGuardNoticeLoad();   // (switches turned off now: say so now; the tweak going off takes a respring, and so does its notice)
}

// SpringBoard's loader, before any part loads, whenever the parts are meant to run (MSBDGateWanted). May switch "Enable Anyway" off / safe mode on.
static inline void MSBDCrashGuardStart(void) {
    if (MSBDGuardOff()) return;
    MSBDGuardState s;
    int early = MSBDGuardRead(&s);
    if (early && s.pid == getpid()) return;   // (both loaders run in SpringBoard: the first one did it)
    if (early && MSBDGuardMarkBeforeBoot()) { MSBDGuardLog("mark from before this boot: a new row"); early = 0; }
    long now = (long)time(NULL);
    if (!early) { s.t0 = now; s.stage = 0; s.ta = 0; s.fakes = 0; }
    if (MSBDGuardFake()) { s.fakes++; early = 1; }
    int fake = MSBDGuardFakeReport();   // (test builds: a crash report from a file, counted only if it points at us)
    MSBDGuardKeepFakeVerdict();
    if (fake >= 0) { early = 1; s.fakes += fake; }
    s.pid = getpid();
    gMSBDGuardAtStart = 1; gMSBDGuardPending = 0;
    int acted = early && MSBDGuardEvaluate(&s);   // (a report still being written is left to the 8 s look, which runs whenever this did not act)
    gMSBDGuardAtStart = 0;
    MSBDGuardSave(&s);
    if (s.stage == 2) return;
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    if (early && !acted) dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), q, NULL, MSBDGuardLook);
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), q, NULL, MSBDGuardStable);
}
