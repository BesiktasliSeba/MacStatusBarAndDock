// test-crashguard.c -- Mac test of the crash guard's report counting (common/CrashGuard.h: MSBDGuardCrashes, the verdict file, the helper call).
// Run: tools/test-crashguard.sh (builds MacCrashBlame for the Mac, then this with the guard's paths pointed at a temp folder).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include "../common/CrashGuard.h"
static int fails = 0;
static void Expect(const char *what, int got, int want) { printf("%s  %-60s got %d, want %d\n", got == want ? "PASS" : "FAIL", what, got, want); if (got != want) fails++; }
static long At(int h, int m) { struct tm tm = {0}; tm.tm_year = 126; tm.tm_mon = 8; tm.tm_mday = 26; tm.tm_hour = h; tm.tm_min = m; tm.tm_isdst = -1; return (long)mktime(&tm); }
static int Count(const char *path, const char *prefix) { FILE *f = fopen(path, "r"); int n = 0; char l[512]; if (!f) return 0; while (fgets(l, sizeof(l), f)) if (strncmp(l, prefix, strlen(prefix)) == 0) n++; fclose(f); return n; }
static int Lines(const char *path) { FILE *f = fopen(path, "r"); int n = 0, c; if (!f) return 0; while ((c = fgetc(f)) != EOF) if (c == '\n') n++; fclose(f); return n; }
int main(void) {
    // Reports (set up by the script): 10:00 ours, 10:01 another tweak's, 10:02 Apple-only with our class in the reason, 10:03 garbage (old file),
    // plus a cpu_resource report that is never looked at.
#ifndef EXPECT_NO_HELPER
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
    MSBDGuardNoteCrash(&gMSBDFakeCrash, now + 30 * 86400, kMSBDVerdictOurs, MSBD_GUARD_REPORTS "/../ours.ips", "MacStatusBarCore.dylib_(faulting_thread)");   // (as the test report does)
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
#else
    Expect("helper missing: every report counts (the old behaviour)", MSBDGuardCrashes(0), 4);
    Expect("helper missing: no verdicts kept (judged once it is there)", Lines(MSBD_GUARD_VERDICTS), 0);
#endif
    return fails ? 1 : 0;
}
