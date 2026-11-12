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
static int StrIs(const char *domain, const char *key, const char *want) {   // (the value stored is the text `want`)
    CFPropertyListRef v = Get(domain, key); char buf[128] = "";
    int is = v && CFGetTypeID(v) == CFStringGetTypeID() && CFStringGetCString(v, buf, sizeof buf, kCFStringEncodingUTF8) && !strcmp(buf, want);
    if (v) CFRelease(v);
    return is;
}
static int FileHas(const char *path, const char *text) {
    FILE *f = fopen(path, "r"); char buf[2000]; size_t n = f ? fread(buf, 1, sizeof(buf) - 1, f) : 0; if (f) fclose(f); buf[n] = 0;
    return f && strstr(buf, text) != NULL;
}
#define TD "com.besiktasliseba.test-crashstep"
#define TDD "com.besiktasliseba.test-crashstep.displays"   // (= MSBD_DISP_DOMAIN here, and TD is its part msb: tools/test-crashstep.sh)
static void SetBool(const char *domain, const char *key, int on) {
    CFStringRef d = CFStringCreateWithCString(NULL, domain, kCFStringEncodingUTF8), k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFPreferencesSetValue(k, on ? kCFBooleanTrue : kCFBooleanFalse, d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(d, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(d); CFRelease(k);
}
int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "skip") == 0) return MSBDCrashSkipped(argv[2]) ? 10 : 20;   // (a loader's view, in a fresh process)
    const char *scenario = argc > 1 ? argv[1] : "";
    MSBDGuardState s = { .pid = 1, .stage = 0, .fakes = 0, .t0 = At(10, 0) + 10, .ta = 0 };
    if (!strcmp(scenario, "banners")) {   // reports: 10:00 + 10:01 banners crashes; later 10:05 a menu crash
        // (1.8.7: per-display overrides of the crashing switch on two displays and "any", and other keys that must stay)
        SetBool(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/msb/macBanners", 1); SetBool(TDD, "u-14803875-6ED1-428A-B223-8B1C4562A66C/msb/macBanners", 0);
        SetBool(TDD, "any/msb/macBanners", 1); SetBool(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/msb/autoHideStatusBar", 1);
        SetBool(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/dock/macBanners", 1); SetBool(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/info", 1);
        SetBool(TDD, "displaySettings", 1); SetBool(TDD, "any/msb/macBannersX", 1);
        Expect("two banners crashes: the guard acts", MSBDGuardEvaluate(&s), 1);
        Expect("  as step 1b (action 4)", Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY), 4);
        Expect("  Mac-Style Banners switched off", Num(TD, "macBanners"), 0);
        Expect("  safe mode not on", Num(MSBD_GATE_DOMAIN, MSBD_SAFE_KEY), -1);
        Expect("  guard stage: waiting for more crashes (1)", s.stage, 1);
        Expect("  record: action 4", FileHas(MSBD_GUARD_RECORD, "action 4\n"), 1);
        Expect("  record: the switch and its words", FileHas(MSBD_GUARD_RECORD, "feature " TD " macBanners 0 Mac-Style Banners|the Mac-style banners\n"), 1);
        Expect("  record: no part line", FileHas(MSBD_GUARD_RECORD, "\npart "), 0);
        Expect("  record: our frames are listed", FileHas(MSBD_GUARD_RECORD, "\nframe "), 1);
        Expect("  1.8.7: every display's override of Mac-Style Banners cleared (the TV's, the iPad 2's TV's, any display's)",
               Num(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/msb/macBanners") == -1 && Num(TDD, "u-14803875-6ED1-428A-B223-8B1C4562A66C/msb/macBanners") == -1 && Num(TDD, "any/msb/macBanners") == -1, 1);
        Expect("  ... another key of that display kept (its auto-hide)", Num(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/msb/autoHideStatusBar"), 1);
        Expect("  ... the same name in another part kept (dock/macBanners)", Num(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/dock/macBanners"), 1);
        Expect("  ... the registry, the master switch and a longer key kept", Num(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/info") == 1 && Num(TDD, "displaySettings") == 1 && Num(TDD, "any/msb/macBannersX") == 1, 1);
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
        Expect("  record: the Dock part", FileHas(MSBD_GUARD_RECORD, "part DockMagnification the Dock|the Dock\n"), 1);
        Expect("  record: the MixAudio part", FileHas(MSBD_GUARD_RECORD, "part MixAudio its part MixAudio|MixAudio\n"), 1);
        Expect("  record: no switch line", FileHas(MSBD_GUARD_RECORD, "\nfeature "), 0);
        Expect("  skip list names MixAudio", FileHas(MSBD_STEP_FILE, "skip MixAudio"), 1);
        Expect("  skip list names DockMagnification", FileHas(MSBD_STEP_FILE, "skip DockMagnification"), 1);
        // A later row whose step 1b only sets a switch: the parts skipped before stay skipped AND stay in the record (audit 3, finding 6).
        MSBDGuardState s2 = { .pid = 2, .stage = 0, .fakes = 0, .t0 = At(10, 20) + 10, .ta = 0 };
        system("cp \"$FIX/step1b-core-banners.ips\" \"$REPORTS/SpringBoard-2026-09-26-102000.ips\"; cp \"$FIX/step1b-core-banners.ips\" \"$REPORTS/SpringBoard-2026-09-26-102100.ips\"");
        Expect("a later row (banners crashes): step 1b again", MSBDGuardEvaluate(&s2) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  record: the banners switch", FileHas(MSBD_GUARD_RECORD, "feature " TD " macBanners 0 "), 1);
        Expect("  record: still names the Dock part (its Turn Back On)", FileHas(MSBD_GUARD_RECORD, "part DockMagnification the Dock|the Dock\n"), 1);
        Expect("  record: still names the MixAudio part", FileHas(MSBD_GUARD_RECORD, "part MixAudio its part MixAudio|MixAudio\n"), 1);
        Expect("  skip list keeps both parts", FileHas(MSBD_STEP_FILE, "skip DockMagnification the Dock|the Dock\n") && FileHas(MSBD_STEP_FILE, "skip MixAudio its part MixAudio|MixAudio\n"), 1);
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
    } else if (!strcmp(scenario, "cclookup")) {   // reports: 10:00 + 10:01 traps under the shared Control Center lookups, in our Control Center's code
        CFPreferencesSetValue(CFSTR("controlCenterStyle"), CFSTR("mac"), CFSTR(TD), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);   // (ours: picked)
        CFPreferencesSynchronize(CFSTR(TD), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Expect("two crashes under the Control Center lookups: step 1b", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  Control Center Style back to iPadOS's: \"stock\" stored, its off text (Settings shows iPadOS)", StrIs(TD, "controlCenterStyle", "stock"), 1);
        Expect("  Stock status bar NOT switched on", Num(TD, "stockStatusBar"), -1);
        Expect("  record: Control Center Style and its words", FileHas(MSBD_GUARD_RECORD, "feature " TD " controlCenterStyle 0 Control Center Style|our Control Center\n"), 1);
        Expect("  record: no part line", FileHas(MSBD_GUARD_RECORD, "\npart "), 0);
        Expect("  safe mode not on", Num(MSBD_GATE_DOMAIN, MSBD_SAFE_KEY), -1);
    } else if (!strcmp(scenario, "dockstyle")) {   // reports: 10:00 + 10:01 crashes in Dock Style's code, with Glass Shelf chosen
        CFPreferencesSetValue(CFSTR("dockStyle"), CFSTR("glass"), CFSTR(TD), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(CFSTR(TD), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Expect("two crashes in Dock Style's code: step 1b", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  Dock Style back to Default: \"default\" stored, as Settings stores it (never false: the row would show no choice)", StrIs(TD, "dockStyle", "default"), 1);
        Expect("  record: Dock Style and its words", FileHas(MSBD_GUARD_RECORD, "feature " TD " dockStyle 0 Dock Style|the older Dock style\n"), 1);
        Expect("  record: no part line", FileHas(MSBD_GUARD_RECORD, "\npart "), 0);
    } else if (!strcmp(scenario, "one")) {   // reports: 10:00 one banners crash only
        Expect("a single crash: nothing yet (two are needed)", MSBDGuardEvaluate(&s), 0);
        Expect("  banners untouched", Num(TD, "macBanners"), -1);
    } else if (!strcmp(scenario, "dispon")) {   // reports: 10:00 + 10:01 banners crashes, Mac-Style Banners off on the iPad and on for the TV only (1.8.7 review)
        const char *tv = "u-4C2D0372-0000-0000-0120-0103808E5078/msb/macBanners";
        SetBool(TD, "macBanners", 0); SetBool(TDD, tv, 1); SetBool(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/info", 1);
        Expect("two banners crashes with the switch on for the TV only: step 1b", MSBDGuardEvaluate(&s) ? Num(MSBD_GATE_DOMAIN, MSBD_GUARD_ACTION_KEY) : 0, 4);
        Expect("  the switch, not the part's fallback: record names Mac-Style Banners", FileHas(MSBD_GUARD_RECORD, "feature " TD " macBanners 0 Mac-Style Banners|the Mac-style banners\n"), 1);
        Expect("  ... Stock status bar NOT switched on", Num(TD, "stockStatusBar"), -1);
        Expect("  ... the TV's own cleared (the TV follows the iPad's off)", Num(TDD, tv), -1);
        Expect("  ... the iPad's still off", Num(TD, "macBanners"), 0);
        Expect("  ... the registry kept", Num(TDD, "u-4C2D0372-0000-0000-0120-0103808E5078/info"), 1);
    } else if (!strcmp(scenario, "dispdefault")) {   // step 1b's per-display part for a row whose display default is on (Show Trash in Dock), 1.8.7 review
        const char *a = "u-4C2D0372-0000-0000-0120-0103808E5078", *b = "u-14803875-6ED1-428A-B223-8B1C4562A66C";
        char k[200];
        snprintf(k, sizeof k, "%s/info", a); SetBool(TDD, k, 1);
        snprintf(k, sizeof k, "%s/info", b); SetBool(TDD, k, 1);
        snprintf(k, sizeof k, "%s/dock/showTrash", b); SetBool(TDD, k, 1);
        SetBool(TDD, "any/dock/showTrash", 1);
        snprintf(k, sizeof k, "%s/dock/showFinder", a); SetBool(TDD, k, 1);
        snprintf(k, sizeof k, "%s/msb/showTrash", a); SetBool(TDD, k, 1);
        Expect("Show Trash in Dock set off by step 1b: every display's changed", MSBDGuardDispClear(MSBD_DISP_DOCK_DOMAIN, "showTrash", 0) >= 3, 1);
        snprintf(k, sizeof k, "%s/dock/showTrash", a);
        Expect("  a remembered display with no own (its Trash on by its default): its own written off", Num(TDD, k), 0);
        snprintf(k, sizeof k, "%s/dock/showTrash", b);
        Expect("  a display's own on: set off (not cleared: its default is on)", Num(TDD, k), 0);
        Expect("  any display's own: set off", Num(TDD, "any/dock/showTrash"), 0);
        snprintf(k, sizeof k, "%s/dock/showFinder", a);
        Expect("  another key kept", Num(TDD, k), 1);
        snprintf(k, sizeof k, "%s/msb/showTrash", a);
        Expect("  the same name in another part kept", Num(TDD, k), 1);
        snprintf(k, sizeof k, "%s/info", a);
        Expect("  the registry kept", Num(TDD, k), 1);
        Expect("a row with no display default (Show Downloads): its overrides cleared, no display given one", (SetBool(TDD, "any/dock/showDownloads", 1), MSBDGuardDispClear(MSBD_DISP_DOCK_DOMAIN, "showDownloads", 0)), 1);
        snprintf(k, sizeof k, "%s/dock/showDownloads", a);
        Expect("  ... cleared, none written", Num(TDD, "any/dock/showDownloads") == -1 && Num(TDD, k) == -1, 1);
    } else { fprintf(stderr, "unknown scenario\n"); return 2; }
    return fails ? 1 : 0;
}
