// test-crashguard.c -- Mac test of the crash guard's report counting (common/CrashGuard.h: MSBDGuardCrashes, the verdict file, the helper call).
// Run: tools/test-crashguard.sh (builds MacCrashBlame for the Mac, then this with the guard's paths pointed at a temp folder).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#ifndef MSBD_TEST_GUARD_H   // (1.8.7.7: another copy of the guard -- the code before the fix, whose new checks must fail)
#define MSBD_TEST_GUARD_H "../common/CrashGuard.h"
#endif
#include MSBD_TEST_GUARD_H
#ifndef MSBD_GUARD_WEAK_CRASHES   // (the code before 1.8.7.7: no cause in its verdicts, no weak crashes)
static inline void MSBDGuardNoteCrash6(MSBDGuardCrash *c, long t, int v, const char *path, const char *blamed, const char *cause) { (void)cause; MSBDGuardNoteCrash(c, t, v, path, blamed); }
#define MSBDGuardNoteCrash MSBDGuardNoteCrash6
#endif
static int fails = 0;
static void Expect(const char *what, int got, int want) { printf("%s  %-60s got %d, want %d\n", got == want ? "PASS" : "FAIL", what, got, want); if (got != want) fails++; }
static long At(int h, int m) { struct tm tm = {0}; tm.tm_year = 126; tm.tm_mon = 8; tm.tm_mday = 26; tm.tm_hour = h; tm.tm_min = m; tm.tm_isdst = -1; return (long)mktime(&tm); }
static int Count(const char *path, const char *prefix) { FILE *f = fopen(path, "r"); int n = 0; char l[512]; if (!f) return 0; while (fgets(l, sizeof(l), f)) if (strncmp(l, prefix, strlen(prefix)) == 0) n++; fclose(f); return n; }
static int ValidUTF8(const char *path) {   // (1.8.7.7: the whole file is well-formed UTF-8 -- checked here: iconv fails in a clean environment)
    FILE *f = fopen(path, "rb"); if (!f) return 0;
    unsigned char b[8192]; size_t n = fread(b, 1, sizeof b, f); fclose(f);
    for (size_t i = 0; i < n; ) {
        unsigned char c = b[i]; size_t k = c < 0x80 ? 0 : (c & 0xE0) == 0xC0 ? 1 : (c & 0xF0) == 0xE0 ? 2 : (c & 0xF8) == 0xF0 ? 3 : 9;
        if (k == 9 || (k == 1 && c < 0xC2) || i + k >= n + (k == 0)) return 0;
        for (size_t j = 1; j <= k; j++) if ((b[i + j] & 0xC0) != 0x80) return 0;
        i += k + 1;
    }
    return 1;
}
static int Lines(const char *path) { FILE *f = fopen(path, "r"); int n = 0, c; if (!f) return 0; while ((c = fgetc(f)) != EOF) if (c == '\n') n++; fclose(f); return n; }
// 1.8.7.5 (review of round 2): reports of 10:06:00 and 10:06:05 naming SpringBoard 501 (the one before a start at 10:06:00) and one of 10:06:00
// naming 502 (that start's own), copies of the "ours" fixture with a "pid" in the body, as the system's reports have.
static void PidReports(int place) {
    const char *names[3] = { "100600", "100600-2", "100605" }; int pids[3] = { 501, 502, 501 };
    for (int i = 0; i < 3; i++) {
        char cmd[1200];
        if (place) snprintf(cmd, sizeof cmd, "sed '2s/^{$/{ \"pid\": %d,/' crash-fixtures/ours-in-faulting-thread.ips > " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-%s.ips", pids[i], names[i]);
        else snprintf(cmd, sizeof cmd, "rm -f " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-%s.ips", names[i]);
        system(cmd);
    }
}
int main(void) {
    // Reports (set up by the script): 10:00 ours, 10:01 another tweak's, 10:02 Apple-only with our class in the reason, 10:03 garbage (old file),
    // plus a cpu_resource report that is never looked at.
#ifndef EXPECT_NO_HELPER
    if (getenv("CRASHGUARD_REAL_ONLY")) goto real;   // (the code before 1.8.7.7: only the checks of the real reports)
    Expect("all reports: ours + Apple/our class + unreadable (other tweak's not)", MSBDGuardCrashes(0), 3);
    Expect("verdict file: one line per judged report", Lines(MSBD_GUARD_VERDICTS), 4);
    system("cp " MSBD_GUARD_REPORTS "/../ours.ips " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-100100.ips");   // (the verdict is kept: not judged again)
    Expect("second look uses the kept verdicts", MSBDGuardCrashes(0), 3);
    Expect("verdict file unchanged", Lines(MSBD_GUARD_VERDICTS), 4);
    Expect("only crashes since 10:01:30", MSBDGuardCrashes(At(10, 1) + 30), 2);
    Expect("only crashes since 10:00:30 (other tweak's not counted)", MSBDGuardCrashes(At(10, 0) + 30), 2);
    // The guard's record (2026-09-26): the crash it tells about is ours (preferred over later Apple-only / unreadable ones).
    memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash));
    MSBDGuardCrashes(0);
    Expect("record's crash: ours", gMSBDLastCrash.verdict, kMSBDVerdictOurs);
    Expect("record's crash: the latest of ours (10:02, our class in the text)", strstr(gMSBDLastCrash.path, "100200") != NULL, 1);
    long now = (long)time(NULL); char buf[1536];
    FILE *rf = fopen(MSBD_GUARD_RECENT, "w");
    fprintf(rf, "%ld com.besiktasliseba.test-msbd bannersOn Mac-Style Banners\n%ld com.besiktasliseba.test-msbd oldLine\n%ld com.besiktasliseba.test-msbd tooOld Old One\n%ld com.other.domain key Not Ours\n", now, now, now - 600, now);
    fclose(rf);
    Expect("step 1: two switches turned off (recent, ours)", MSBDGuardSwitchOffRecent(now - 120, buf, sizeof(buf)), 2);
    Expect("record lines name the row title", strstr(buf, "switch com.besiktasliseba.test-msbd bannersOn Mac-Style Banners\n") != NULL, 1);
    Expect("an old line without a title still works", strstr(buf, "switch com.besiktasliseba.test-msbd oldLine \n") != NULL, 1);
    MSBDGuardWriteRecord(1, 1, buf);
    char rec0[4096] = ""; FILE *f0 = fopen(MSBD_GUARD_RECORD, "r"); size_t n0 = f0 ? fread(rec0, 1, sizeof(rec0) - 1, f0) : 0; if (f0) fclose(f0); rec0[n0] = 0;
    Expect("record: blamed our class in the crash text, no frames", strstr(rec0, "blamed DMWeakScene_(crash_text)") && !strstr(rec0, "frame "), 1);
    MSBDGuardNoteCrash(&gMSBDFakeCrash, now + 30 * 86400, kMSBDVerdictOurs, MSBD_GUARD_REPORTS "/../ours.ips", "MacStatusBarCore.dylib_(faulting_thread)", "");   // (as the test report does)
    MSBDGuardWriteRecord(1, 1, buf);
    char rec[4096] = ""; FILE *f = fopen(MSBD_GUARD_RECORD, "r"); size_t n = f ? fread(rec, 1, sizeof(rec) - 1, f) : 0; if (f) fclose(f); rec[n] = 0;
    printf("   record:\n%s", rec);
    Expect("record: action 1", strstr(rec, "\naction 1\n") != NULL, 1);
    Expect("record: blamed our part", strstr(rec, "blamed MacStatusBarCore.dylib_(faulting_thread)") != NULL, 1);
    Expect("record: our frames only (2)", strstr(rec, "frame MacStatusBarCore.dylib + 0x4d2\nframe MacStatusBarCore.dylib + 0x4d2\n") != NULL && !strstr(rec, "UIKit"), 1);
    Expect("record: build version", strstr(rec, "\nbuild ") != NULL, 1);
    // The notice part is loaded for at most 3 starts that ran 10 s ("ran", written by the notice) or 6 loads in all, and never once shown.
    for (int i = 0; i < 8; i++) MSBDGuardNoticeLoad();
    Expect("notice: an early crash loop loads it at most 6 times", Count(MSBD_GUARD_RECORD, "load "), 6);
    MSBDGuardWriteRecord(1, 1, buf);
    for (int i = 0; i < 2; i++) { MSBDGuardNoticeLoad(); MSBDGuardNoticeLoad(); f = fopen(MSBD_GUARD_RECORD, "a"); fputs("ran 1\n", f); fclose(f); }   // (two sbreloads, each two starts)
    MSBDGuardNoticeLoad();
    Expect("notice: double starts do not use up the budget (5 loads)", Count(MSBD_GUARD_RECORD, "load "), 5);
    f = fopen(MSBD_GUARD_RECORD, "a"); fputs("ran 1\n", f); fclose(f);
    MSBDGuardNoticeLoad();
    Expect("notice: after 3 starts that ran, no more", Count(MSBD_GUARD_RECORD, "load "), 5);
    MSBDGuardWriteRecord(2, 1, NULL);
    MSBDGuardNoticeLoad();
    Expect("a new record: loaded again", Count(MSBD_GUARD_RECORD, "load "), 1);
    f = fopen(MSBD_GUARD_RECORD, "a"); fputs("shown 1\n", f); fclose(f);
    MSBDGuardNoticeLoad();
    Expect("shown: not loaded again", Count(MSBD_GUARD_RECORD, "load "), 1);
    Expect("action 2 record: no switch lines", Count(MSBD_GUARD_RECORD, "switch "), 0);
    // A new report that cannot be read yet (still being written): pending at SpringBoard's start, counted at the 8 s look (audit 3, finding 5).
    FILE *hw = fopen(MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-100500.ips", "w"); fputs("{\"bug_type\":\"309\"}\n{\"threads\": [", hw); fclose(hw);
    gMSBDGuardAtStart = 1; gMSBDGuardPending = 0;
    Expect("at start: the half-written report is pending, not counted", MSBDGuardCrashes(At(10, 4)), 0);
    Expect("at start: one report pending", gMSBDGuardPending, 1);
    gMSBDGuardAtStart = 0;
    Expect("8 s look: the unreadable report counts, as before", MSBDGuardCrashes(At(10, 4)), 1);
    unlink(MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-100500.ips");
    // A mark from before this boot is not a row of early starts (audit 3, finding 2).
    f = fopen(MSBD_GUARD_FILE, "w"); fputs("1 0 0 0 0\n", f); fclose(f);
    Expect("a mark written now: from this boot", MSBDGuardMarkBeforeBoot(), 0);
    system("touch -t 202001011200 " MSBD_GUARD_FILE);
    Expect("a mark from 2020: before this boot", MSBDGuardMarkBeforeBoot(), 1);
    unlink(MSBD_GUARD_FILE);
    Expect("no mark: nothing to say", MSBDGuardMarkBeforeBoot(), 0);
    // 1.8.7: a switch turned on for one display, noted by its flat key (common/DisplayPrefs.h MSBDDispNoteRecent, the format of the guard's own
    // list): step 1 turns that override off in the displays domain and posts it, with no change to the guard. The flat key at its longest (127)
    // comes through the guard's sscanf whole; a 128-character one is never written (it would come through cut and set another key).
    {
        char id62[63], key[60], flat[160], flat128[200], rec2[1536], want[400];
        memset(id62, 'A', 62); id62[62] = 0; memset(key, 'k', 57); key[57] = 0;   // ("u-" 62 + "/dock/" + 57 = 127)
        char display[80]; snprintf(display, sizeof display, "u-%s", id62);
        Expect("the longest flat key (127)", (long)MSBDDispFlatKey(flat, sizeof flat, display, "dock", key), 127);
        snprintf(flat128, sizeof flat128, "%sk", flat);
        unlink(MSBD_GUARD_RECENT);
        Expect("noted for the guard", MSBDDispNoteRecent(MSBD_GUARD_RECENT, now, flat, "Automatically Hide and Show the Dock", 1), 1);
        Expect("a 128-character key is not noted", MSBDDispNoteRecent(MSBD_GUARD_RECENT, now, flat128, "Too Long", 1), 0);
        Expect("step 1: the display's switch turned off", MSBDGuardSwitchOffRecent(now - 120, rec2, sizeof(rec2)), 1);
        snprintf(want, sizeof want, "switch %s %s Automatically Hide and Show the Dock\n", MSBD_DISP_DOMAIN, flat);
        Expect("  ... its record line names the domain and the whole flat key, with the row title", strstr(rec2, want) != NULL, 1);
        CFStringRef k = CFStringCreateWithCString(NULL, flat, kCFStringEncodingUTF8), d = CFStringCreateWithCString(NULL, MSBD_DISP_DOMAIN, kCFStringEncodingUTF8);
        CFPreferencesSynchronize(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef v = CFPreferencesCopyValue(k, d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Expect("  ... false written into that override (the display takes off, the iPad untouched)", v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v), 1);
        if (v) CFRelease(v);
        CFArrayRef keys = CFPreferencesCopyKeyList(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Expect("  ... and nothing else in the displays domain (no cut key)", keys ? (long)CFArrayGetCount(keys) : 0, 1);
        if (keys) CFRelease(keys);
        CFRelease(k); CFRelease(d);
        Expect("  ... the list used up", access(MSBD_GUARD_RECENT, F_OK), -1);
    }
    // 1.8.7.5 (review of round 2): a report's SpringBoard (MacCrashBlame MSBDCrashPid), and a count from a start leaves out the crash of the
    // SpringBoard before it, whatever second its report names; the new SpringBoard's own crash in that second counts.
    Expect("a report's pid: the body's (a watchdog report, before its reshaping)", MSBDGuardReportPid("crash-fixtures/watchdog-stuck-main.ips"), 4707);
    Expect("  a report naming none: -1", MSBDGuardReportPid("crash-fixtures/ours-in-faulting-thread.ips"), -1);
    Expect("  an unreadable one: -1", MSBDGuardReportPid(MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-100300.ips"), -1);
    Expect("  a missing one: -1", MSBDGuardReportPid(MSBD_GUARD_REPORTS "/SpringBoard-none.ips"), -1);
    PidReports(1);
    Expect("from 10:06:00 after SpringBoard 501: only 502's crash (501's of that second and its late one not)", MSBDGuardCrashesFrom(At(10, 6), 501), 1);
    Expect("  no SpringBoard before (prev 0): all three", MSBDGuardCrashesFrom(At(10, 6), 0), 3);
    Expect("  MSBDGuardCrashes (the Aerial 5.0 probation): all three, as before", MSBDGuardCrashes(At(10, 6)), 3);
    memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash));
    MSBDGuardCrashesFrom(At(10, 6), 501);
    Expect("  the record's crash: 502's, never one left out", strstr(gMSBDLastCrash.path, "100600-2") != NULL, 1);
    PidReports(0);
real:
    // 1.8.7.7 (GitHub #14): the REAL reports (tools/crash-fixtures/real-*, trimmed). Issue #14's two popover aborts and its Do Not Disturb crash
    // (only Apple code on their stacks, other tweaks loaded) are WEAK, the wallpaper tweak's crash another tweak's, the 17.5's Notification Center
    // crash (ours, through our hooks) STRONG. The verdict file keeps what crashed: the cause (our death record's reason for that SpringBoard, else
    // what the report says), where, and the other tweaks loaded (renamed OtherTweakA.. in the fixtures).
    system("rm -f " MSBD_GUARD_REPORTS "/*.ips " MSBD_GUARD_VERDICTS);
    system("cp crash-fixtures/real-issue14-popover-1.ips " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-110000.ips; cp crash-fixtures/real-issue14-popover-2.ips " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-110030.ips;"
           "cp crash-fixtures/real-issue14-wallpaper-tweak.ips " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-110100.ips; cp crash-fixtures/real-175-nc-pull-ours.ips " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-110130.ips");
    {   // our death record: a line for popover 1's SpringBoard (pid 24198, launched 16:17:06 +0800, captured 16:30:49 +0800 on 16 Nov 2026), one of another pid
        FILE *cf = fopen(MSBD_CAUSE_FILE, "w");
        fprintf(cf, "24198\t1794817849\tmain\tNSGenericException\tUIPopoverPresentationController (<UIPopoverPresentationController: 0x10a1b2c00>) should have a non-nil sourceView or barButtonItem set before the presentation occurs.\tNSException\n");
        fprintf(cf, "999\t1794817849\tmain\tNSGenericException\tnot this SpringBoard\tNSException\n");
        fclose(cf);
    }
#ifdef MSBD_GUARD_WEAK_CRASHES
    {
        int S = -1, W = -1, O = -1;
        MSBDGuardTallyFrom(At(11, 0), 0, &S, &W, &O);
        Expect("real: #14 popovers weak (2), the wallpaper tweak's other (1), the 17.5 NC crash strong (1)", S * 100 + W * 10 + O, 121);
        Expect("real: MSBDGuardCrashes (the Aerial probation) counts strong and weak, as before", MSBDGuardCrashes(At(11, 0)), 3);
#ifdef MSBD_GUARD_TALLY_KEEP
        {   // (review of 1.8.7.7: the loop breaker counts the crashes since the newest other tweak's crash of the row, here the wallpaper tweak's at 11:01)
            int s2 = -1, w2 = -1, o2 = -1, sa = -1, wa = -1;
            MSBDGuardTallyRow(At(11, 0), 0, &s2, &w2, &o2, &sa, &wa);
            Expect("real: since the newest other tweak's crash: the 17.5 NC crash only (strong 1, weak 0)", s2 * 10000 + w2 * 1000 + o2 * 100 + sa * 10 + wa, 12110);
            MSBDGuardTallyRow(At(11, 1) + 1, 0, &s2, &w2, &o2, &sa, &wa);
            Expect("  ... with no other tweak's crash in the count: all of them (strong 1)", o2 * 100 + sa * 10 + wa, 10);
        }
#else
        Expect("real: the count since the newest other tweak's crash (review of 1.8.7.7)", 0, 1);
#endif
        char vf[8000] = ""; FILE *f2 = fopen(MSBD_GUARD_VERDICTS, "r"); size_t n2 = f2 ? fread(vf, 1, sizeof(vf) - 1, f2) : 0; if (f2) fclose(f2); vf[n2] = 0;
        printf("   verdicts:\n%s", vf);
        Expect("verdict file: popover 1 not pinned, 3 other tweaks", strstr(vf, "SpringBoard-2026-09-26-110000.ips 4 Apple_code_only;_3_other_tweaks_loaded\t") != NULL, 1);
        Expect("  ... its cause: the death record's reason (pid and time matched)", strstr(vf, "\tNSGenericException: UIPopoverPresentationController (<UIPopoverPresentationController: 0x10a1b2c00>) should have a non-nil sourceView") != NULL, 1);
        Expect("  ... where: the popover's presentation, and the other tweaks by name", strstr(vf, "\t-[UIPopoverPresentationController presentationTransitionWillBegin] (UIKitCore)\t3 OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib\n") != NULL, 1);
        Expect("  ... popover 2 (no death record line): the exception's kind", strstr(vf, "110030.ips 4 Apple_code_only;_3_other_tweaks_loaded\tEXC_CRASH (SIGABRT): uncaught exception, its reason not in the report\t") != NULL, 1);
        Expect("  ... the wallpaper tweak's crash: another tweak's", strstr(vf, "110100.ips 3 /var/jb/usr/lib/TweakInject/OtherTweakA.dylib_(faulting_thread)\tEXC_CRASH (SIGSEGV)\t-[_MTLCommandBuffer waitUntilCompleted] (Metal)") != NULL, 1);
        Expect("  ... the 17.5 NC crash: ours", strstr(vf, "110130.ips 1 MacStatusBarCore.dylib_(exception_backtrace)\t") != NULL, 1);
        // the record tells what crashed (the crash it names: ours first, then strong before weak)
        memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash)); memset(&gMSBDFakeCrash, 0, sizeof(gMSBDFakeCrash));
        system("rm -f " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-110130.ips");
        MSBDGuardTallyFrom(At(11, 0), 0, NULL, NULL, NULL);
        gMSBDGuardRowWeak = 2; gMSBDGuardRowLoop = 1;
        MSBDGuardWriteRecord(2, 1, NULL);
        gMSBDGuardRowWeak = 0; gMSBDGuardRowLoop = 0;
        char rec3[4096] = ""; FILE *f3 = fopen(MSBD_GUARD_RECORD, "r"); size_t n3 = f3 ? fread(rec3, 1, sizeof(rec3) - 1, f3) : 0; if (f3) fclose(f3); rec3[n3] = 0;
        printf("   record:\n%s", rec3);
        Expect("record: the latest crash (popover 2): verdict 4, its cause, where, the other tweaks", strstr(rec3, "\nverdict 4\n") && strstr(rec3, "\ncause EXC_CRASH (SIGABRT): uncaught exception") && strstr(rec3, "\nwhere -[UIPopoverPresentationController presentationTransitionWillBegin] (UIKitCore)\n")
                                                                       && strstr(rec3, "\nothers 3 OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib\n"), 1);
        Expect("record: unknown 2, loop 1, no frames (none of ours)", strstr(rec3, "\nunknown 2\n") && strstr(rec3, "\nloop 1\n") && !strstr(rec3, "\nframe "), 1);
        // a cause cut to the files' room ends on a whole character (Settings reads the files as UTF-8): popover 2's SpringBoard (pid 24305) with a
        // reason of 400 three-byte characters in our death record, judged anew
        {
            const char *in[] = {"abc", "ab\xc3", "ab\xc3\xa7", "ab\xe2\x82", "ab\xe2\x82\xac", "\xf0\x9f\x98", "\xf0\x9f\x98\x80", "a\x80"};
            size_t want[] = {3, 2, 4, 2, 5, 0, 4, 1}, ok = 1;
            for (int i = 0; i < 8; i++) { char b8[16]; strlcpy(b8, in[i], sizeof b8); MSBDGuardUTF8Whole(b8); ok &= strlen(b8) == want[i]; }
            Expect("UTF-8: a last character left incomplete is taken off, whole ones kept", (int)ok, 1);
            FILE *cf = fopen(MSBD_CAUSE_FILE, "w");
            fprintf(cf, "24305\t1794817881\tmain\tNSInternalInconsistencyException\t");
            for (int i = 0; i < 400; i++) fputs("\xe2\x82\xac", cf);
            fprintf(cf, "\tNSException\n"); fclose(cf);
            system("rm -f " MSBD_GUARD_VERDICTS);
            MSBDGuardTallyFrom(At(11, 0), 0, NULL, NULL, NULL);
            Expect("  the verdict file with a long non-ASCII cause: valid UTF-8", ValidUTF8(MSBD_GUARD_VERDICTS), 1);
            char vl[2000] = ""; FILE *f4 = fopen(MSBD_GUARD_VERDICTS, "r"); int whole = 0, lines = 0;
            while (f4 && fgets(vl, sizeof vl, f4)) { lines++; whole += strchr(vl, '\n') != NULL && strlen(vl) < MSBD_GUARD_LINE_MAX; }
            if (f4) fclose(f4);
            Expect("  ... every line whole within a read of MSBD_GUARD_LINE_MAX (3 reports)", lines * 10 + whole, 33);
            memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash));
            MSBDGuardTallyFrom(At(11, 0), 0, NULL, NULL, NULL);
            MSBDGuardWriteRecord(2, 1, NULL);
            Expect("  the record with that cause: valid UTF-8, its cause line there", ValidUTF8(MSBD_GUARD_RECORD) && Count(MSBD_GUARD_RECORD, "cause NSInternalInconsistencyException: \xe2\x82\xac") == 1, 1);
        }
        // (review of 1.8.7.7) a long reason must not cut the other tweaks -- the suspects -- or where off the line: #14's crash 4 (the Do Not Disturb
        // listener's, 7 other tweaks loaded; its SpringBoard pid 24393, captured 17:01:31 +0800) with a 419-byte reason in our death record (its
        // longest), then with 400 three-byte characters (a 17/18 report's own reason has no byte limit)
        system("rm -f " MSBD_GUARD_REPORTS "/*.ips; cp crash-fixtures/real-issue14-dnd-listener.ips " MSBD_GUARD_REPORTS "/SpringBoard-2026-09-26-120000.ips");
        for (int pass = 0; pass < 2; pass++) {
            const char *pre = "-[OtherTweakListener stateService:didReceiveDoNotDisturbStateUpdate:]: unrecognized selector sent to instance 0x283a1c0c0 ";
            FILE *cf = fopen(MSBD_CAUSE_FILE, "w");
            fprintf(cf, "24393\t1794819691\tother\tNSInvalidArgumentException\t%s", pre);
            for (size_t i = 0; pass ? i < 400 : i < 419 - strlen(pre); i++) fputs(pass ? "\xe2\x82\xac" : "x", cf);
            fprintf(cf, "\tNSException\n"); fclose(cf);
            system("rm -f " MSBD_GUARD_VERDICTS);
            memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash)); memset(&gMSBDFakeCrash, 0, sizeof(gMSBDFakeCrash));
            int s4 = 0, w4 = 0;
            MSBDGuardTallyFrom(At(12, 0), 0, &s4, &w4, NULL);
            char vl[4096] = ""; FILE *f5 = fopen(MSBD_GUARD_VERDICTS, "r"); size_t n5 = f5 ? fread(vl, 1, sizeof(vl) - 1, f5) : 0; if (f5) fclose(f5); vl[n5] = 0;
            const char *all7 = "\t7 OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib, OtherTweakD.dylib, OtherTweakE.dylib, OtherTweakF.dylib, OtherTweakG.dylib\n";
            Expect(pass ? "long non-ASCII reason: the verdict line keeps where and all 7 other tweaks" : "419-byte reason: the verdict line keeps where and all 7 other tweaks",
                   w4 == 1 && strstr(vl, "\tNSInvalidArgumentException: -[OtherTweakListener") && strstr(vl, "\t__67-[DNDStateService remoteService:didReceiveDoNotDisturbStateUpdate:]_block_invoke_2 (DoNotDisturb)\t7 ") && strstr(vl, all7), 1);
            Expect("  ... the line valid UTF-8 and within a read of MSBD_GUARD_LINE_MAX", ValidUTF8(MSBD_GUARD_VERDICTS) && strlen(vl) < MSBD_GUARD_LINE_MAX && Lines(MSBD_GUARD_VERDICTS) == 1, 1);
            MSBDGuardWriteRecord(2, 1, NULL);
            char rec5[4096] = ""; FILE *f6 = fopen(MSBD_GUARD_RECORD, "r"); size_t n6 = f6 ? fread(rec5, 1, sizeof(rec5) - 1, f6) : 0; if (f6) fclose(f6); rec5[n6] = 0;
            Expect("  ... the record: where and the 7 other tweaks", strstr(rec5, "\nwhere __67-[DNDStateService remoteService:didReceiveDoNotDisturbStateUpdate:]_block_invoke_2 (DoNotDisturb)\n") &&
                   strstr(rec5, "\nothers 7 OtherTweakA.dylib, OtherTweakB.dylib, OtherTweakC.dylib, OtherTweakD.dylib, OtherTweakE.dylib, OtherTweakF.dylib, OtherTweakG.dylib\n") != NULL, 1);
            int longest = 0; char rl[2048]; FILE *f7 = fopen(MSBD_GUARD_RECORD, "r");
            while (f7 && fgets(rl, sizeof rl, f7)) if ((int)strlen(rl) > longest) longest = (int)strlen(rl);
            if (f7) fclose(f7);
            Expect("  ... every record line under 512 bytes (the loader reads it in lines of 512)", longest < 512, 1);
        }
        // (review of 1.8.7.7) the class a cause names, looked up again once every tweak has loaded: crash 4's reason names a class of a tweak that
        // loads after ours (alphabetically), not there when the start judges. 8 s later it is: the verdict and the record name its library.
        {
            FILE *cf = fopen(MSBD_CAUSE_FILE, "w");
            fprintf(cf, "24393\t1794819691\tother\tNSInvalidArgumentException\t-[OtherTweakLateListener stateService:didReceiveDoNotDisturbStateUpdate:]: unrecognized selector sent to instance 0x283a1c0c0\tNSException\n");
            fclose(cf);
            system("rm -f " MSBD_GUARD_VERDICTS " " MSBD_GUARD_RECORD);
            memset(&gMSBDLastCrash, 0, sizeof(gMSBDLastCrash)); memset(&gMSBDFakeCrash, 0, sizeof(gMSBDFakeCrash));
            gMSBDGuardAtStart = 1;
            MSBDGuardTallyFrom(At(12, 0), 0, NULL, NULL, NULL);   // (the start: the class not loaded yet)
            gMSBDGuardAtStart = 0;
            MSBDGuardWriteRecord(1, 1, NULL);
            char v6[4096] = ""; FILE *f8 = fopen(MSBD_GUARD_VERDICTS, "r"); size_t n8 = f8 ? fread(v6, 1, sizeof(v6) - 1, f8) : 0; if (f8) fclose(f8); v6[n8] = 0;
            Expect("class later: at the start the cause names the class, no library yet", strstr(v6, "\tNSInvalidArgumentException: -[OtherTweakLateListener stateService:") && !strstr(v6, "that class is in"), 1);
            void *late = dlopen(MSBD_TEST_LATE_LIB, RTLD_NOW);   // (the later tweak loads)
            Expect("  (the later tweak's library loaded)", late != NULL, 1);
            MSBDGuardLook(NULL);   // (the 8 s look, 8 s after the start: no mark of this process here, so only the class asked again)
            char blamed6[256] = "", cause6[MSBD_GUARD_LINE_MAX] = "";
            int v = -1;
            {   // (the report's last verdict line, as every reader takes it)
                char l6[MSBD_GUARD_LINE_MAX], nm[256], b6[256]; int rv; FILE *f9 = fopen(MSBD_GUARD_VERDICTS, "r");
                while (f9 && fgets(l6, sizeof l6, f9)) if (sscanf(l6, "%255s %d %255s", nm, &rv, b6) == 3 && !strcmp(nm, "SpringBoard-2026-09-26-120000.ips")) { v = rv; strlcpy(blamed6, b6, sizeof blamed6); char *tb = strchr(l6, '\t'); strlcpy(cause6, tb ? tb + 1 : "", sizeof cause6); }
                if (f9) fclose(f9);
            }
            Expect("  at 8 s: the verdict line again, its cause naming the library (verdict 4 kept)", v == 4 && strstr(cause6, "unrecognized selector sent to instance 0x283a1c0c0 (that class is in OtherTweakLate.dylib)\t") != NULL, 1);
            Expect("  ... where and the other tweaks kept", strstr(cause6, "\t__67-[DNDStateService remoteService:didReceiveDoNotDisturbStateUpdate:]_block_invoke_2 (DoNotDisturb)\t7 OtherTweakA.dylib") != NULL && strstr(blamed6, "7_other_tweaks") != NULL, 1);
            char r6[4096] = ""; FILE *f10 = fopen(MSBD_GUARD_RECORD, "r"); size_t n10 = f10 ? fread(r6, 1, sizeof(r6) - 1, f10) : 0; if (f10) fclose(f10); r6[n10] = 0;
            const char *lastCause = r6; for (const char *q = strstr(r6, "\ncause "); q; q = strstr(q + 1, "\ncause ")) lastCause = q;
            Expect("  ... the record's last cause line names it too", Count(MSBD_GUARD_RECORD, "cause ") == 2 && strstr(lastCause, "\ncause NSInvalidArgumentException: -[OtherTweakLateListener") == lastCause && strstr(lastCause, "(that class is in OtherTweakLate.dylib)\n") != NULL, 1);
            int before = Lines(MSBD_GUARD_VERDICTS);
            MSBDGuardLook(NULL);
            Expect("  ... asked once: a second look adds nothing", Lines(MSBD_GUARD_VERDICTS) == before && Count(MSBD_GUARD_RECORD, "cause ") == 2, 1);
#ifdef MSBD_GUARD_CLASS_LATER
            int (*again)(const char *, char *, size_t) = (int (*)(const char *, char *, size_t))MSBDGuardHelper("MSBDCrashCauseClass");
            char out[MSBD_GUARD_CAUSE_MAX] = "x";
            Expect("  ... an Apple class (NSNull): nothing added", again && again("NSInvalidArgumentException: -[NSNull length]: unrecognized selector sent to instance 0x1", out, sizeof out) == 0 && !out[0], 1);
            Expect("  ... a class not loaded anywhere: nothing added", again && again("NSInvalidArgumentException: -[NoSuchClassAnywhere x]: unrecognized selector", out, sizeof out) == 0, 1);
            Expect("  ... a cause that names a library already: nothing added", again && again("X: -[OtherTweakLateListener y]: unrecognized selector (that class is in OtherTweakLate.dylib)", out, sizeof out) == 0, 1);
            Expect("  ... the class's library kept at the end of a long cause", again && again("NSInvalidArgumentException: -[OtherTweakLateListener stateService:didReceiveDoNotDisturbStateUpdate:]: unrecognized selector sent to instance 0x283a1c0c0 "
                   "padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding",
                   out, sizeof out) == 1 && strlen(out) <= 420 && strstr(out, "… (that class is in OtherTweakLate.dylib)") != NULL, 1);
#endif
        }
        // the mark: 8 fields (the weak simulated crashes last); a 7-field mark (1.8.7.6) reads with none; an older build reads the 8-field one
        MSBDGuardState m = { .pid = 7, .t0 = 100, .stage = 1, .ta = 200, .fakes = 1, .next = 1, .prev = 6, .wfakes = 2 }, r = {0};
        MSBDGuardWrite(&m);
        Expect("mark: written and read back with its weak fakes", MSBDGuardRead(&r) && r.wfakes == 2 && r.fakes == 1 && r.prev == 6 && r.next == 1, 1);
        int a1, a3, a5, a6, a7; long a2, a4; FILE *mf = fopen(MSBD_GUARD_FILE, "r");
        int old = fscanf(mf, "%d %ld %d %ld %d %d %d", &a1, &a2, &a3, &a4, &a5, &a6, &a7); fclose(mf);
        Expect("  ... the reader of 1.8.7.6 takes its seven fields from it", old == 7 && a1 == 7 && a7 == 6, 1);
        mf = fopen(MSBD_GUARD_FILE, "w"); fputs("7 100 1 200 1 1 6\n", mf); fclose(mf);
        Expect("  ... a 7-field mark: no weak fakes", MSBDGuardRead(&r) && r.wfakes == 0 && r.prev == 6, 1);
        unlink(MSBD_GUARD_FILE);
    }
#else
    Expect("real: #14's popover aborts and DND crash weak, not counted as ours (no weak crashes in this code)", MSBDGuardCrashesFrom(At(11, 0), 0), 1);
#endif
    unlink(MSBD_CAUSE_FILE);
#else
    Expect("helper missing: every report counts (the old behaviour)", MSBDGuardCrashes(0), 4);
    Expect("helper missing: no verdicts kept (judged once it is there)", Lines(MSBD_GUARD_VERDICTS), 0);
    PidReports(1);
    Expect("helper missing: no report's SpringBoard can be told, so all count (as before)", MSBDGuardCrashesFrom(At(10, 6), 501), 3);
    PidReports(0);
#endif
    return fails ? 1 : 0;
}
