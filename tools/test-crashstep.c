// test-crashstep.c -- Mac test of the crash guard's order with step 1b (common/CrashGuard.h + common/CrashStep.h): recently enabled switches ->
// the feature/part the crash points at -> the whole tweak. Run: tools/test-crashstep.sh (builds MacCrashBlame for the Mac, sets the guard's paths
// to a temp folder, uses tools/crash-fixtures/test-crashmap.txt and the step1b-*.ips fixtures; the guard's record is checked for step 1b's lines).
// Preferences go to the Mac's own
// com.besiktasliseba.macstatusbaranddock and com.besiktasliseba.test-crashstep domains, which the script removes again.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include "../common/CrashGuard.h"
static int fails = 0;
static void Expect(const char *what, long got, long want) { printf("%s  %-66s got %ld, want %ld\n", got == want ? "PASS" : "FAIL", what, got, want); if (got != want) fails++; }
static long At(int h, int m) { struct tm tm = {0}; tm.tm_year = 126; tm.tm_mon = 8; tm.tm_mday = 26; tm.tm_hour = h; tm.tm_min = m; tm.tm_isdst = -1; return (long)mktime(&tm); }
static CFPropertyListRef Get(const char *domain, const char *key) {
    CFStringRef d = CFStringCreateWithCString(NULL, domain, kCFStringEncodingUTF8), k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFPreferencesSynchronize(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(k, d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(d); CFRelease(k);
    return v;
}
static long Num(const char *domain, const char *key) {   // (-1 = not set; booleans 0/1)
    CFPropertyListRef v = Get(domain, key); long n = -1;
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) n = CFBooleanGetValue(v);
    else if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberLongType, &n);
    if (v) CFRelease(v);
    return n;
}
static int FileHas(const char *path, const char *text) {
    FILE *f = fopen(path, "r"); char buf[2000]; size_t n = f ? fread(buf, 1, sizeof(buf) - 1, f) : 0; if (f) fclose(f); buf[n] = 0;
    return f && strstr(buf, text) != NULL;
}
#define TD "com.besiktasliseba.test-crashstep"
int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "skip") == 0) return MSBDCrashSkipped(argv[2]) ? 10 : 20;   // (a loader's view, in a fresh process)
    const char *scenario = argc > 1 ? argv[1] : "";
    MSBDGuardState s = { .pid = 1, .stage = 0, .fakes = 0, .t0 = At(10, 0) + 10, .ta = 0 };
    if (!strcmp(scenario, "banners")) {   // reports: 10:00 + 10:01 banners crashes; later 10:05 a menu crash
        Expect("two banners crashes: the guard acts", MSBDGuardEvaluate(&s), 1);
        Expect("  as step 1b (action 4)", Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY), 4);
        Expect("  Mac-Style Banners switched off", Num(TD, "macBanners"), 0);
        Expect("  safe mode not on", Num(MSBD_GATE_DOMAIN, MSBD_SAFE_KEY), -1);
        Expect("  guard stage: waiting for more crashes (1)", s.stage, 1);
        Expect("  record: action 4", FileHas(MSBD_GUARD_RECORD, "action 4\n"), 1);
        Expect("  record: the switch and its words", FileHas(MSBD_GUARD_RECORD, "feature " TD " macBanners 0 Mac-Style Banners|the Mac-style banners\n"), 1);
        Expect("  record: no part line", FileHas(MSBD_GUARD_RECORD, "\npart "), 0);
        Expect("  record: our frames are listed", FileHas(MSBD_GUARD_RECORD, "\nframe "), 1);
        Expect("  no skip list entries", FileHas(MSBD_STEP_FILE, "skip "), 0);
        Expect("  step 1b is not repeated in the same row", MSBDGuardStepFeature(s.t0, s.t0 - 30, 0, NULL, 0), 0);
        s.ta = At(10, 4);   // (as if 1b acted at 10:04; the script adds a crash at 10:05)
        system("cp \"$FIX/step1b-core-menu.ips\" \"$REPORTS/SpringBoard-2026-09-26-100500.ips\"");
        Expect("one more crash after step 1b: the guard acts again", MSBDGuardEvaluate(&s), 1);
        Expect("  now the whole tweak: action 3", Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY), 3);
        Expect("  safe mode on", Num(MSBD_GATE_DOMAIN, MSBD_SAFE_KEY), 1);
        Expect("  Stock status bar NOT switched on (1b only once per row)", Num(TD, "stockStatusBar"), -1);
    } else if (!strcmp(scenario, "parts")) {   // reports: 10:00 Dock crash, 10:01 MixAudio crash
        Expect("Dock + MixAudio crashes: step 1b", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  record: the Dock part", FileHas(MSBD_GUARD_RECORD, "part DockMagnification the Dock|MacDock\n"), 1);
        Expect("  record: the MixAudio part", FileHas(MSBD_GUARD_RECORD, "part MixAudio its part MixAudio|MixAudio\n"), 1);
        Expect("  record: no switch line", FileHas(MSBD_GUARD_RECORD, "\nfeature "), 0);
        Expect("  skip list names MixAudio", FileHas(MSBD_STEP_FILE, "skip MixAudio"), 1);
        Expect("  skip list names DockMagnification", FileHas(MSBD_STEP_FILE, "skip DockMagnification"), 1);
        // A later row whose step 1b only sets a switch: the parts skipped before stay skipped AND stay in the record (audit 3, finding 6).
        MSBDGuardState s2 = { .pid = 2, .stage = 0, .fakes = 0, .t0 = At(10, 20) + 10, .ta = 0 };
        system("cp \"$FIX/step1b-core-banners.ips\" \"$REPORTS/SpringBoard-2026-09-26-102000.ips\"; cp \"$FIX/step1b-core-banners.ips\" \"$REPORTS/SpringBoard-2026-09-26-102100.ips\"");
        Expect("a later row (banners crashes): step 1b again", MSBDGuardEvaluate(&s2) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  record: the banners switch", FileHas(MSBD_GUARD_RECORD, "feature " TD " macBanners 0 "), 1);
        Expect("  record: still names the Dock part (its Turn Back On)", FileHas(MSBD_GUARD_RECORD, "part DockMagnification the Dock|MacDock\n"), 1);
        Expect("  record: still names the MixAudio part", FileHas(MSBD_GUARD_RECORD, "part MixAudio its part MixAudio|MixAudio\n"), 1);
        Expect("  skip list keeps both parts", FileHas(MSBD_STEP_FILE, "skip DockMagnification the Dock|MacDock\n") && FileHas(MSBD_STEP_FILE, "skip MixAudio its part MixAudio|MixAudio\n"), 1);
    } else if (!strcmp(scenario, "apple")) {   // reports: 10:00 + 10:01 Apple-only
        Expect("two Apple-only crashes: the guard acts", MSBDGuardEvaluate(&s), 1);
        Expect("  straight to the whole tweak (action 2)", Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY), 2);
        Expect("  safe mode on", Num(MSBD_GATE_DOMAIN, MSBD_SAFE_KEY), 1);
        Expect("  no step 1b file", access(MSBD_STEP_FILE, F_OK) == 0, 0);
    } else if (!strcmp(scenario, "mixed")) {   // reports: 10:00 loader crash, 10:01 Downloads crash
        Expect("loader crash + Downloads crash: step 1b for Downloads", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  Show Downloads switched off", Num(TD, "showDownloads"), 0);
        Expect("  record: Downloads, not the loader", FileHas(MSBD_GUARD_RECORD, "feature " TD " showDownloads 0 "), 1);
    } else if (!strcmp(scenario, "recent")) {   // reports: 10:00 + 10:01 banners; a switch turned on at 09:59 (the script writes the list)
        Expect("a switch turned on just before: step 1 first", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 1);
        Expect("  that switch off", Num(TD, "recentSwitch"), 0);
        Expect("  banners untouched by step 1", Num(TD, "macBanners"), -1);
        s.ta = At(10, 4);
        system("cp \"$FIX/step1b-core-banners.ips\" \"$REPORTS/SpringBoard-2026-09-26-100500.ips\"");
        Expect("crash again: now step 1b", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  banners off", Num(TD, "macBanners"), 0);
        Expect("  record says: again", FileHas(MSBD_GUARD_RECORD, "again 1\n"), 1);
        s.ta = At(10, 6);
        system("cp \"$FIX/step1b-core-banners.ips\" \"$REPORTS/SpringBoard-2026-09-26-100700.ips\"");
        Expect("and again: the whole tweak (action 3)", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 3);
        Expect("  safe mode on", Num(MSBD_GATE_DOMAIN, MSBD_SAFE_KEY), 1);
    } else if (!strcmp(scenario, "one")) {   // reports: 10:00 one banners crash only
        Expect("a single crash: nothing yet (two are needed)", MSBDGuardEvaluate(&s), 0);
        Expect("  banners untouched", Num(TD, "macBanners"), -1);
    } else { fprintf(stderr, "unknown scenario\n"); return 2; }
    return fails ? 1 : 0;
}
