// CrashCause.h -- our death record (MacStatusBar&Dock 1.8.7.7, GitHub #14): when SpringBoard dies of an uncaught Objective-C exception, one line
// that names it. iPadOS 15/16 crash reports carry no exception reason at all (the four of #14 had none), so neither we nor the user could tell
// whose crash it was; 17/18 reports sometimes do ("exceptionReason"). The crash guard's helper reads the line back for the report of that
// SpringBoard (common/CrashBlame.h MSBDCauseLineFor: same pid, written between its launch and 10 s after the report's capture): the reason is
// looked at for our names (a reason naming DM.../MSB... classes is ours), and it is the "cause" the record, the notice and Report a Problem show.
//
// Installed by SpringBoard's loader, from the crash guard's start (CrashGuard.h MSBDCrashGuardStart: SpringBoard only, while the parts are meant to
// run, once per process -- the second loader returns at the guard's pid check). Plain C like the loaders: Foundation's and the runtime's functions
// are looked up (dlsym), nothing is linked, so the loaders still load no Foundation or UIKit (tools/test-ctornouikit.sh).
//  - It never replaces another tweak's handler: the one before ours (prev) is always called, and ours hands over with a TAIL CALL
//    (musttail: our frame is gone before prev runs), so if prev aborts no frame of ours is on the crashing stack -- with one there the guard would
//    blame us for another tweak's exception, the very thing this release fixes.
//  - The handler runs inside _objc_terminate on the throwing thread, before abort (not a signal handler: no frames of ours above _sigtramp, no fight
//    with other crash reporters). It asks the exception for its name and reason (each call checked with respondsToSelector first), turns them into
//    one line in a stack buffer and appends it with one open/write/close. Nothing else: no other objects, no locks of ours, no dladdr.
//  - The same exception handed back to us (a handler that calls "the current handler", which is ours now) returns at once: no loop. A different
//    exception later (a handler that kept the process alive) is passed on as before, and written while fewer than 4 lines came from this process.
//  - No record when another tweak installs its own handler later without calling ours: no harm, just no line.
// Line: "<pid>\t<time>\t<main|other>\t<name>\t<reason, at most 420 bytes, tabs and line breaks as spaces>\t<class of the thrown object>\n".
// Cost at SpringBoard's start: the dlsym calls and two function calls. The file is trimmed to its last 16 lines past 8 KB (CrashBlame.h
// MSBDCauseTrim: by the guard's helper when it judges, by Settings when it shows a crash).
#pragma once
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>

#ifndef MSBD_CAUSE_FILE   // (= CrashBlame.h; overridable for the Mac test, tools/test-crashcause.sh)
#define MSBD_CAUSE_FILE "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashCauses.txt"
#endif
#define MSBD_CAUSE_MAX_LINES 4   // (per process)

typedef void (*MSBDCauseHandlerFn)(void *);
static MSBDCauseHandlerFn gMSBDCausePrev;
static void *gMSBDCauseLast;    // (the exception last handed to us)
static int gMSBDCauseLines;     // (lines written by this process)
static void *(*gMSBDCauseMsg)(void *, void *);
static void *(*gMSBDCauseSel)(const char *);
static void *(*gMSBDCauseClassOf)(void *);
static signed char (*gMSBDCauseResponds)(void *, void *);
static const char *(*gMSBDCauseClassName)(void *);

// [[obj sel] UTF8String], or NULL when anything does not answer.
static inline const char *MSBDCauseText(void *obj, const char *sel) {
    void *s = gMSBDCauseSel(sel), *u = gMSBDCauseSel("UTF8String"), *cls = obj ? gMSBDCauseClassOf(obj) : NULL;
    if (!s || !u || !cls || !gMSBDCauseResponds(cls, s)) return NULL;
    void *str = gMSBDCauseMsg(obj, s), *scls = str ? gMSBDCauseClassOf(str) : NULL;
    if (!scls || !gMSBDCauseResponds(scls, u)) return NULL;
    return (const char *)gMSBDCauseMsg(str, u);
}
// One field of the line: tabs and line breaks become spaces, at most n - 1 bytes (never half a UTF-8 character), "-" when empty.
static inline void MSBDCauseField(char *out, size_t n, const char *in) {
    size_t k = 0;
    for (; in && *in && k + 1 < n; in++) out[k++] = (*in == '\n' || *in == '\r' || *in == '\t') ? ' ' : *in;
    if (in && *in) while (k > 0 && ((unsigned char)out[k - 1] & 0xC0) == 0x80) k--;   // (cut inside a character: back to its start...)
    if (in && *in && k > 0 && ((unsigned char)out[k - 1] & 0xC0) == 0xC0) k--;          // (...and that start too)
    out[k] = 0;
    if (!k && n > 1) { out[0] = '-'; out[1] = 0; }
}
static inline void MSBDCauseWrite(void *exc) {
    char name[128], reason[421], cls[128], line[760];
    MSBDCauseField(name, sizeof name, MSBDCauseText(exc, "name"));
    MSBDCauseField(reason, sizeof reason, MSBDCauseText(exc, "reason"));
    void *c = gMSBDCauseClassOf(exc);
    MSBDCauseField(cls, sizeof cls, c ? gMSBDCauseClassName(c) : NULL);
    int len = snprintf(line, sizeof line, "%d\t%ld\t%s\t%s\t%s\t%s\n", getpid(), (long)time(NULL), pthread_main_np() ? "main" : "other", name, reason, cls);
    if (len <= 0) return;
    if ((size_t)len >= sizeof line) { len = (int)sizeof line - 1; line[len - 1] = '\n'; }
    int fd = open(MSBD_CAUSE_FILE, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0644);
    if (fd < 0) return;
    ssize_t w = write(fd, line, (size_t)len);
    (void)w;
    close(fd);
}
// The handler (static inline: emitted only where the guard's start is, the loaders; noinline: one frame, gone at the tail call).
static inline __attribute__((noinline)) void MSBDCauseHandler(void *exc) {
    if (!exc || __atomic_exchange_n(&gMSBDCauseLast, exc, __ATOMIC_SEQ_CST) == exc) return;   // (the same exception handed back: no loop)
    if (__atomic_fetch_add(&gMSBDCauseLines, 1, __ATOMIC_SEQ_CST) < MSBD_CAUSE_MAX_LINES) MSBDCauseWrite(exc);
    MSBDCauseHandlerFn prev = gMSBDCausePrev;
    if (prev && prev != MSBDCauseHandler) __attribute__((musttail)) return prev(exc);   // (our frame is gone before the next handler runs)
}
// SpringBoard's loader, once per process (CrashGuard.h MSBDCrashGuardStart). Returns 1 if ours is the handler now.
static inline int MSBDCauseInstall(void) {
    MSBDCauseHandlerFn (*get)(void) = (MSBDCauseHandlerFn (*)(void))dlsym(RTLD_DEFAULT, "NSGetUncaughtExceptionHandler");
    void (*set)(MSBDCauseHandlerFn) = (void (*)(MSBDCauseHandlerFn))dlsym(RTLD_DEFAULT, "NSSetUncaughtExceptionHandler");
    gMSBDCauseMsg = (void *(*)(void *, void *))dlsym(RTLD_DEFAULT, "objc_msgSend");
    gMSBDCauseSel = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "sel_registerName");
    gMSBDCauseClassOf = (void *(*)(void *))dlsym(RTLD_DEFAULT, "object_getClass");
    gMSBDCauseResponds = (signed char (*)(void *, void *))dlsym(RTLD_DEFAULT, "class_respondsToSelector");
    gMSBDCauseClassName = (const char *(*)(void *))dlsym(RTLD_DEFAULT, "class_getName");
    if (!get || !set || !gMSBDCauseMsg || !gMSBDCauseSel || !gMSBDCauseClassOf || !gMSBDCauseResponds || !gMSBDCauseClassName) return 0;
    MSBDCauseHandlerFn cur = get();
    if (cur == MSBDCauseHandler) return 1;   // (already ours: no second link in the chain)
    gMSBDCausePrev = cur;
    set(MSBDCauseHandler);
    return 1;
}
