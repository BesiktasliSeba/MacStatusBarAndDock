// test-icleanstartover.m -- Mac test of the root helper's start-over during an iCleaner clean (1.8.7.5, audit L80 of 1.8.7.2 and its review).
// sshtoggled starts over as a fresh process (an exec over itself) when cfprefsd restarted, so mobile's settings are read anew. It ran the clean
// itself and knew only that an eject was under way: started over during a clean, the process that was to write the clean's answer was gone (Finder
// ended with "still cleaning", a second tap ran a second clean beside the first, which went on orphaned). Held back for the clean instead, it waited
// for a clean that has no time limit: an eject, an SSH switch or an engine pick made meanwhile was read from the old settings (an eject request not
// seen at all), for good if iCleaner hung. Now the clean runs in a process of its own (sshtoggled --iclean-run), which answers by itself; the
// start-over does not wait for it and tells the fresh process which process runs it (--iclean-running), so a request meanwhile still waits for it.
// Run on the real code cut out of main.m (startover.inc, made by tools/test-icleanstartover.sh: StartOverIfPrefsDaemonRestarted with its state,
// ICleanWriteAnswer, ICleanRun, ICleanWatch, ICleanCarriedOver, ICleanRequest) with the real common/ICleaner.h and DriveEject.h (MSBDRunHelperTimed
// runs a stand-in iCleaner that takes 3 s), and stand-ins for the process list's cfprefsd signature, mobile's preferences (the request), the log and
// the notifications, kept in files so the clean's process and the fresh process see them. The start-over is a real exec of this program (same pid,
// its children kept), which goes on as the fresh helper (--resume ...). Each scenario runs in a process of its own (--scenario N), all at once.
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <spawn.h>
#include <fcntl.h>
#include "../common/ICleaner.h"
#undef kMSBDICleanBinary
#undef kMSBDICleanAnswerFile
#define kMSBDICleanBinary IS_DIR "/iCleaner"
static const char *AnswerPath(void) { return getenv("MSBD_TEST_ANSWER") ?: IS_DIR "/iclean-answer"; }   // (one a scenario: they run at once)
#define kMSBDICleanAnswerFile AnswerPath()
#define ESTATEDIR IS_DIR
extern char **environ;

// ---- stand-ins (files: the scenario's processes share them) ----
static NSString *Env(const char *k) { const char *v = getenv(k); return v ? @(v) : nil; }
static void Append(const char *var, NSString *line) {
    const char *p = getenv(var); if (!p) return;
    int fd = open(p, O_WRONLY | O_APPEND | O_CREAT, 0644); if (fd < 0) return;
    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    write(fd, d.bytes, d.length); close(fd);
}
static NSArray<NSString *> *Lines(const char *var) {
    NSString *f = Env(var) ? [NSString stringWithContentsOfFile:Env(var) encoding:NSUTF8StringEncoding error:nil] : nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *l in [f ?: @"" componentsSeparatedByString:@"\n"]) if (l.length) [out addObject:l];
    return out;
}
static NSMutableDictionary *ReqLoad(void) { return [[NSDictionary dictionaryWithContentsOfFile:Env("MSBD_TEST_REQ")] mutableCopy] ?: [NSMutableDictionary dictionary]; }
static CFPropertyListRef TCopy(CFStringRef k) { id v = ReqLoad()[(__bridge NSString *)k]; return v ? CFBridgingRetain(v) : NULL; }
static void TSet(CFStringRef k, CFPropertyListRef v) { NSMutableDictionary *d = ReqLoad(); d[(__bridge NSString *)k] = (__bridge id)v; [d writeToFile:Env("MSBD_TEST_REQ") atomically:YES]; }
#define CFPreferencesSynchronize(d, u, h) ((void)(d))
#define CFPreferencesCopyValue(k, d, u, h) TCopy(k)
#define CFPreferencesSetValue(k, v, d, u, h) TSet(k, v)
static void TNotify(const char *n) {   // (an answer posted: the answer file as it is then, one line "id | answer" in the scenario's notes)
    if (strcmp(n, kMSBDICleanAnswerName)) return;
    NSString *a = [NSString stringWithContentsOfFile:@(AnswerPath()) encoding:NSUTF8StringEncoding error:nil] ?: @"(no answer file)";
    a = [a stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    Append("MSBD_TEST_NOTES", [a stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);
}
#define notify_post(n) TNotify(n)
static void ELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ELog(NSString *fmt, ...) { va_list ap; va_start(ap, fmt); Append("MSBD_TEST_LOG", [[NSString alloc] initWithFormat:fmt arguments:ap]); va_end(ap); }
static NSString *gSignature = @"101@1000/0";   // (the cfprefsd processes now)
static NSString *PrefsDaemonSignature(void) { return gSignature; }
static int gN = 0, gFail = 0, gPhase = 0;
static void (^gAtExec)(char *const argv[]);   // (the scenario's checks at the start-over; then a real exec, or the end of the scenario)
static int TExecv(const char *path, char *const argv[]) { gAtExec(argv); return -1; }
static void RealExec(char *const argv[]) {   // (the start-over as it is: this process becomes the fresh helper -- same pid, its children kept)
    setenv("MSBD_TEST_SIG", gSignature.UTF8String, 1);
    char b[16];
    snprintf(b, sizeof b, "%d", gPhase + 1); setenv("MSBD_TEST_PHASE", b, 1);
    snprintf(b, sizeof b, "%d", gN); setenv("MSBD_TEST_N", b, 1);
    snprintf(b, sizeof b, "%d", gFail); setenv("MSBD_TEST_FAIL", b, 1);
    fflush(stdout);
    execv(argv[0], argv);
}
#define execv(p, a) TExecv(p, a)
static dispatch_queue_t gICleanQueue;
static BOOL gICleanAgain = NO;
static NSData *ICleanDryRunOutput(void) { return nil; }   // (the real run, of the stand-in iCleaner)
static NSString *ICleanUnusable(void) { return Env("MSBD_TEST_UNUSABLE"); }
static void ICleanRequest(NSString *why);
#include "startover.inc"

// ---- the test ----
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } else printf("  ok   %s\n", what.UTF8String); fflush(stdout); }
static void End(void) { printf("  (%d checks, %d failed)\n", gN, gFail); fflush(stdout); _exit(gFail ? 1 : 0); }
static void Spin(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
static void SpinUntil(BOOL (^done)(void), double limit) { double end = CFAbsoluteTimeGetCurrent() + limit; while (!done() && CFAbsoluteTimeGetCurrent() < end) Spin(0.05); }
static NSString *OK(void) {   // (the answer line of the stand-in's output, as the helper makes it: "ok freed=1.0 MB deleted=3 respring=0")
    NSString *l = MSBDICleanAnswerFromOutput(0, [@"success=true\nfreed=1.0 MB\ndeleted=3\nshouldrespring=false\n" dataUsingEncoding:NSUTF8StringEncoding], NO, 0);
    return [l hasPrefix:@"ok freed=1.0"] && [l hasSuffix:@"MB deleted=3 respring=0"] ? l : @"(not the answer of a clean)";
}
static NSString *RID(int n) { return [NSString stringWithFormat:@"%032x", n]; }
static NSString *AnswerOf(int n) { return [NSString stringWithFormat:@"%@ | %@", RID(n), OK()]; }
static void Ask(int n) { TSet(CFSTR(kMSBDICleanRequestKey), (__bridge CFPropertyListRef)@{@"id": RID(n), @"action": @"clean", @"at": @([[NSDate date] timeIntervalSince1970])}); }
static NSString *Waiting(void) { return ReqLoad()[@kMSBDICleanRequestKey][@"id"]; }
static NSArray<NSString *> *Answers(void) { return Lines("MSBD_TEST_NOTES"); }   // (every answer posted, in order)
static int Count(NSString *what) { int n = 0; for (NSString *l in Lines("MSBD_TEST_RUNS")) if ([l isEqualToString:what]) n++; return n; }
static int Runs(void) { return Count(@"run"); }   // (the stand-in iCleaner's runs in this scenario)
static int Overlaps(void) { return Count(@"overlap"); }   // (a run that started while another ran)
static BOOL CleanFdsNone(void) {   // (each clean's process started with none of the helper's descriptors above 2: one "0" line a clean)
    NSArray *l = Lines("MSBD_TEST_CLEANFDS");
    for (NSString *s in l) if (![s isEqualToString:@"0"]) return NO;
    return l.count > 0;
}
static int OwnPipes(void) { int n = 0; struct stat st; for (int fd = 3; fd < 256; fd++) if (fstat(fd, &st) == 0 && S_ISFIFO(st.st_mode)) n++; return n; }
static BOOL Has(const char *resume, NSString *kind) { return resume && [[@(resume) componentsSeparatedByString:@","] containsObject:kind]; }
static BOOL Carries(char *const a[]) { return a[1] && a[2] && a[3] && !strcmp(a[3], "--iclean-running") && a[4] && atoi(a[4]) > 0; }
static void NoExec(NSString *what) { gAtExec = ^(char *const a[]) { Expect(NO, [NSString stringWithFormat:@"%@ (it started over, resuming \"%s\")", what, a[2] ?: "?"]); End(); }; }

static void Scenario(int n) {
    gPrefsDaemons = gSignature;   // (a helper at its start: the settings of the cfprefsd running now)
    switch (n) {
    case 1: {
        printf("a clean under way (3 s), cfprefsd restarted meanwhile, then an eject asked (EjectRequest asks for the start-over first):\n");
        Ask(1);
        int tp[2]; pipe(tp);   // (a descriptor of the helper's, not close-on-exec: the clean's process must not get it)
        NoExec(@"the clean started before any start-over");
        ICleanRequest(@"Finder");
        close(tp[0]); close(tp[1]);
        Expect(gICleanBusy && !Waiting(), @"the clean started, its request taken away");
        SpinUntil(^BOOL{ return Runs() == 1; }, 3);
        gSignature = @"202@2000/0";   // (killall cfprefsd)
        __block BOOL execd = NO;
        gAtExec = ^(char *const a[]) {
            execd = YES;
            Expect(Runs() == 1 && Answers().count == 0, @"started over at once, while the clean runs");
            Expect(Has(a[2], @"eject") && Carries(a), [NSString stringWithFormat:@"  ... resuming the eject (\"%s\"), the clean's process named for the fresh one", a[2] ?: "?"]);
            Ask(2);   // (a second tap in Finder: read by the fresh process)
            RealExec(a);
            Expect(NO, @"(the exec failed)"); End();
        };
        StartOverIfPrefsDaemonRestarted(kWorkEject);
        Expect(execd, @"started over at once, while the clean runs (it waited for the clean: the eject read meanwhile from this process's old settings)");
        End();
    }
    case 2: {
        printf("a clean that runs long (5 s): cfprefsd restarted, the 10 s check starts over, cfprefsd restarted again:\n");
        setenv("MSBD_TEST_SECS", "5", 1);
        Ask(3);
        NoExec(@"the clean started before any start-over");
        ICleanRequest(@"Finder");
        SpinUntil(^BOOL{ return Runs() == 1; }, 3);
        gSignature = @"303@3000/0";
        __block BOOL execd = NO;
        gAtExec = ^(char *const a[]) {
            execd = YES;
            Expect(Has(a[2], @"none") && Carries(a), [NSString stringWithFormat:@"started over at once (\"%s\"), the clean's process named for the fresh one", a[2] ?: "?"]);
            RealExec(a);
            Expect(NO, @"(the exec failed)"); End();
        };
        StartOverIfPrefsDaemonRestarted(0);   // (the 10 s check)
        Expect(execd, @"the 10 s check started over at once during the clean (it waited for the clean, which has no time limit)");
        End();
    }
    case 3: {
        printf("cfprefsd restarted with no clean under way: the request is read by the fresh process:\n");
        gSignature = @"303@3000/0";
        Ask(4);
        gAtExec = ^(char *const a[]) {
            Expect(a[2] && !strcmp(a[2], "iclean") && !a[3] && [Waiting() isEqual:RID(4)] && !gICleanBusy && Runs() == 0,
                   [NSString stringWithFormat:@"started over first (resuming \"%s\", no clean to name), the request left for the fresh process", a[2] ?: "?"]);
            End();
        };
        ICleanRequest(@"Finder");
        Spin(0.3);
        Expect(NO, @"started over first, the request left for the fresh process (read and run by this process instead)");
        End();
    }
    case 4: {
        printf("no cfprefsd restart (as before):\n");
        NoExec(@"no start-over");
        Ask(5);
        ICleanRequest(@"Finder");
        Spin(0.5);
        StartOverIfPrefsDaemonRestarted(0);
        SpinUntil(^BOOL{ return Answers().count > 0 && !gICleanBusy; }, 8);
        Spin(0.3);
        Expect([Answers() isEqual:@[AnswerOf(5)]] && Runs() == 1, @"the clean runs and answers once, no start-over");
        Ask(6);
        ICleanRequest(@"Finder");
        Ask(7);
        ICleanRequest(@"Finder");   // (a second tap while it runs: the newest request, after it)
        SpinUntil(^BOOL{ return Answers().count > 2 && !gICleanBusy; }, 12);
        Spin(0.3);
        Expect([Answers() isEqual:(@[AnswerOf(5), AnswerOf(6), AnswerOf(7)])] && Runs() == 3 && Overlaps() == 0, @"  ... a request that came meanwhile is answered after it (the newest), one clean at a time");
        End();
    }
    case 5: {
        printf("the fresh process (--resume ...,iclean), no clean under way: the waiting request answered once:\n");
        Ask(8);
        NoExec(@"no start-over");
        ICleanRequest(@"Finder (after starting over)");
        ICleanRequest(@"daemon start");   // (as the helper's start does next)
        SpinUntil(^BOOL{ return Answers().count > 0 && !gICleanBusy && !gICleanAgain; }, 8);
        Spin(0.3);
        Expect([Answers() isEqual:@[AnswerOf(8)]] && Runs() == 1 && !Waiting(), @"one clean, one answer, the request gone, no start-over");
        End();
    }
    case 6: {
        printf("iCleaner Pro not usable (as before):\n");
        setenv("MSBD_TEST_UNUSABLE", "iCleaner Pro isn’t installed", 1);
        NoExec(@"no start-over");
        Ask(9);
        ICleanRequest(@"Finder");
        SpinUntil(^BOOL{ return Answers().count > 0 && !gICleanBusy; }, 5);
        Expect([Answers() isEqual:@[[NSString stringWithFormat:@"%@ | error: iCleaner Pro isn’t installed", RID(9)]]] && Runs() == 0, @"answered with the reason, iCleaner not run");
        End();
    }
    }
}

static void Fresh(int n, int argc, char **argv) {   // (this program again, after the start-over's exec: the fresh helper's start)
    gPrefsDaemons = gSignature;
    printf("  the fresh process (phase %d, \"%s%s%s\"):\n", gPhase, argv[2], argc > 4 ? " " : "", argc > 4 ? argv[3] : "");
    Expect(OwnPipes() == 0, [NSString stringWithFormat:@"  no pipe carried into it (%d)", OwnPipes()]);
    ICleanCarriedOver(argc, argv);
    if (n == 1) {
        Expect(gICleanBusy, @"  ... it knows the clean goes on (its process carried over) and waits for it");
        ICleanRequest(@"Finder");   // (the second tap)
        Spin(0.5);
        Expect(Runs() == 1, @"  ... the second tap waits: no second clean beside the first");
        SpinUntil(^BOOL{ return Answers().count >= 2 && !gICleanBusy; }, 12);
        Spin(0.3);
        Expect([Answers() isEqual:(@[AnswerOf(1), AnswerOf(2)])], [NSString stringWithFormat:@"  ... the first clean answered once, by its own process, then the second tap's (%@)", [Answers() componentsJoinedByString:@"; "]]);
        Expect(Runs() == 2 && Overlaps() == 0, @"  ... two cleans, one after the other");
        Expect(CleanFdsNone(), @"  ... each clean's process had none of the helper's descriptors (0-2 only)");
        End();
    }
    if (n == 2 && gPhase == 1) {
        Expect(gICleanBusy, @"  ... it waits for the clean");
        Spin(0.3);
        gSignature = @"304@3001/0";
        const char *was = argc > 4 ? argv[4] : "";
        __block BOOL execd = NO;
        gAtExec = ^(char *const a[]) {
            execd = YES;
            Expect(Carries(a) && !strcmp(a[4], was), @"  ... cfprefsd restarted again: started over again at once, the same clean's process named again");
            RealExec(a);
            Expect(NO, @"(the exec failed)"); End();
        };
        StartOverIfPrefsDaemonRestarted(0);
        Expect(execd, @"  ... cfprefsd restarted again: started over again at once (it waited for the clean)");
        End();
    }
    if (n == 2) {
        Expect(gICleanBusy, @"  ... the second fresh process waits for the clean too");
        SpinUntil(^BOOL{ return Answers().count > 0 && !gICleanBusy; }, 10);
        Spin(0.3);
        Expect([Answers() isEqual:@[AnswerOf(3)]] && Runs() == 1, @"  ... the clean answered once, by its own process, after two start-overs");
        Expect(!gICleanBusy, @"  ... and the helper is free again once it ends");
        End();
    }
    Expect(NO, @"(a fresh process in a scenario that has none)");
    End();
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc > 3 && !strcmp(argv[1], "--iclean-run")) {   // (the clean's own process, as main.m starts it)
            Append("MSBD_TEST_CLEANFDS", [NSString stringWithFormat:@"%d", OwnPipes()]);
            return ICleanRun(argv[2], argv[3]);
        }
        if (argv[0][0] == '/' && strlen(argv[0]) < sizeof gSelfPath) strcpy(gSelfPath, argv[0]);
        int n = Env("MSBD_TEST_SCENARIO").intValue;
        if (argc > 2 && !strcmp(argv[1], "--resume")) {
            gPhase = Env("MSBD_TEST_PHASE").intValue; gN = Env("MSBD_TEST_N").intValue; gFail = Env("MSBD_TEST_FAIL").intValue;
            if (Env("MSBD_TEST_SIG")) gSignature = Env("MSBD_TEST_SIG");
            gICleanQueue = dispatch_queue_create("msbd.iclean", DISPATCH_QUEUE_SERIAL);
            Fresh(n, argc, argv);
            return 2;
        }
        if (argc == 3 && !strcmp(argv[1], "--scenario")) {
            n = atoi(argv[2]);
            gICleanQueue = dispatch_queue_create("msbd.iclean", DISPATCH_QUEUE_SERIAL);
            const char *vars[] = { "MSBD_TEST_RUNS", "MSBD_TEST_REQ", "MSBD_TEST_NOTES", "MSBD_TEST_LOG", "MSBD_TEST_CLEANFDS", "MSBD_TEST_ANSWER" };
            const char *names[] = { "runs", "req.plist", "notes", "log", "cleanfds", "answer" };
            for (int i = 0; i < 6; i++) {
                NSString *p = [NSString stringWithFormat:@IS_DIR "/%d-%s", n, names[i]];
                unlink(p.fileSystemRepresentation); setenv(vars[i], p.fileSystemRepresentation, 1);
            }
            setenv("MSBD_TEST_SCENARIO", argv[2], 1); setenv("MSBD_TEST_PHASE", "0", 1);
            Scenario(n);
            return 2;
        }
        enum { kScenarios = 6 };
        pid_t pids[kScenarios + 1] = {0};
        for (int s = 1; s <= kScenarios; s++) {   // (one process each, all at once: the exec ends or replaces it)
            char num[4]; snprintf(num, sizeof num, "%d", s);
            char out[PATH_MAX]; snprintf(out, sizeof out, IS_DIR "/%d-out", s);
            char *args[] = { argv[0], "--scenario", num, NULL };
            posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
            posix_spawn_file_actions_addopen(&fa, 1, out, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            posix_spawn_file_actions_adddup2(&fa, 1, 2);
            if (posix_spawn(&pids[s], argv[0], &fa, NULL, args, environ) != 0) pids[s] = 0;
            posix_spawn_file_actions_destroy(&fa);
        }
        int failed = 0;
        for (int s = 1; s <= kScenarios; s++) {
            int st = 0;
            if (pids[s] <= 0) { failed++; printf("(scenario %d did not start)\n", s); continue; }
            while (waitpid(pids[s], &st, 0) < 0 && errno == EINTR) {}
            NSString *o = [NSString stringWithContentsOfFile:[NSString stringWithFormat:@IS_DIR "/%d-out", s] encoding:NSUTF8StringEncoding error:nil];
            printf("%s", (o ?: @"(no output)\n").UTF8String);
            if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) failed++;
        }
        printf("test-icleanstartover (compiled): %d of %d scenarios failed\n", failed, kScenarios);
        return failed ? 1 : 0;
    }
}
