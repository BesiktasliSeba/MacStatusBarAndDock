// CrashStep.h -- the crash guard's step 1b (MacStatusBar&Dock, 2026-09-26): before the whole tweak goes off, only what crashed goes off.
// Included by CrashGuard.h (its one hook: MSBDGuardEvaluate calls MSBDGuardStepFeature); plain C like the guard, the loaders include it through it.
//
// The guard's order: 1. the switches turned on in the last 2 min go off (CrashGuard.h); 1b. (here) the feature or part the crash reports point at
// goes off; 2. the whole tweak (safe mode) -- when no crash can be pinned on one of our features (only Apple code on the stack, a report that cannot
// be read, one of the two loaders), or when SpringBoard crashes again after 1b. Step 1b runs at most once per row of early starts.
//
// What it can turn off (tools/crashmap-rules.txt; MacCrashBlame.dylib answers, common/CrashFeature.h):
//  - a switch in Settings: e.g. Mac-Style Banners, Automatically Hide the Status Bar, Enable Windowing, Clock Opens Today View, the Force Quit / App
//    Size / Folder menu rows, Downloads / Launchpad / open-app indicators in the Dock; any other crash in the status bar code turns on Stock status
//    bar mode (stockStatusBar);
//  - a part as a whole ("skip"): it is not loaded in SpringBoard any more. Listed in MSBD_STEP_FILE, honoured by the loaders (MSBDCrashSkipped)
//    while the crash guard's note (crashGuardAction) is there; once the note is cleared (Turn Back On, Enable Anyway, a later Settings action) the
//    part loads again and the loader removes the list;
//  - a piece of a part that has no Settings row of its own (the battery icon's plug during a charge hold): on the same list under its target's
//    name, which that piece's code reads (MSBDCrashSkipped), and recorded as a part -- so the pages offer Turn Back On for it too.
// A switch that is already off cannot be the cause: the part goes instead.
// A switch it sets also loses every display's override of it (1.8.7, the per-display settings: MSBDGuardDispClear), so a TV keeps no crashing path.
//
// What it did goes into the guard's record (CrashGuard.h, MSBD_GUARD_RECORD; crashGuardAction = 4), which the footer, the notice and Report a
// Problem put in words (CrashExplain.h):
//   feature <domain> <key> <value> <row title>|<where>   a switch set to <value> (stockStatusBar 1 = the stock status bar is used for now)
//   part <Image> <where>|<what>                          a part no longer loaded in SpringBoard
//   again 1                                              it came after step 1 (SpringBoard crashed again, not twice)
// Cost: nothing on a normal start (the loaders try to open MSBD_STEP_FILE once, which does not exist); the map is read only after crashes that count.
#pragma once
#include "DisplayPrefs.h"   // (1.8.7: a switch set here also loses its per-display overrides, MSBDGuardDispClear)

#define MSBD_GUARD_ACTION_FEATURE 4
#ifndef MSBD_STEP_FILE   // (overridable for the Mac test, tools/test-crashstep.c)
#define MSBD_STEP_FILE "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashStep.txt"   // "row <t0>" + "skip <part>" lines
#endif
#ifndef MSBD_CRASHMAP   // (overridable for the Mac test)
#define MSBD_CRASHMAP "/var/jb/usr/lib/MacStatusBarAndDock/CrashMap.txt"
#endif
#define MSBD_STEP_MAX 4   // (targets per step: two crashes can point at two different features)

// crashGuardAction now (0 = none).
static inline int MSBDStepGuardAction(void) {
    void *cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY | RTLD_NOLOAD);
    if (!cf) return 0;
    const void *(*mk)(const void *, const char *, unsigned int) = (const void *(*)(const void *, const char *, unsigned int))dlsym(cf, "CFStringCreateWithCString");
    const void *(*copy)(const void *, const void *, const void *, const void *) = (const void *(*)(const void *, const void *, const void *, const void *))dlsym(cf, "CFPreferencesCopyValue");
    unsigned char (*getnum)(const void *, long, void *) = (unsigned char (*)(const void *, long, void *))dlsym(cf, "CFNumberGetValue");
    unsigned long (*typeOf)(const void *) = (unsigned long (*)(const void *))dlsym(cf, "CFGetTypeID");
    unsigned long (*numType)(void) = (unsigned long (*)(void))dlsym(cf, "CFNumberGetTypeID");
    void (*rel)(const void *) = (void (*)(const void *))dlsym(cf, "CFRelease");
    const void **user = (const void **)dlsym(cf, "kCFPreferencesCurrentUser"), **host = (const void **)dlsym(cf, "kCFPreferencesAnyHost");
    int action = 0;
    if (mk && copy && getnum && typeOf && numType && rel && user && host) {
        const void *k = mk(NULL, MSBD_GUARD_ACTION_KEY, 0x08000100), *d = mk(NULL, MSBD_GATE_DOMAIN, 0x08000100);
        const void *v = k && d ? copy(k, d, *user, *host) : NULL;
        if (v && typeOf(v) == numType()) getnum(v, 9, &action);   // (kCFNumberIntType)
        if (v) rel(v);
        if (k) rel(k);
        if (d) rel(d);
    }
    dlclose(cf);
    return action;
}

// The loaders (SpringBoard only): is this part on step 1b's skip list? The list is read once per process; while the guard's note is gone it is
// dropped (and removed).
static inline int MSBDCrashSkipped(const char *name) {
    static int state = -1;   // -1 not read, 0 nothing skipped, 1 list below
    static char list[16][64]; static int count = 0;
    if (state < 0) {
        state = 0;
        FILE *f = fopen(MSBD_STEP_FILE, "r");   // (normally missing: this is the whole cost)
        if (f) {
            char line[128], part[64];
            while (fgets(line, sizeof(line), f)) if (count < 16 && sscanf(line, "skip %63s", part) == 1) strlcpy(list[count++], part, sizeof(list[0]));
            fclose(f);
            if (MSBDStepGuardAction() == 0) {   // (the note was cleared: everything loads again, and the file goes)
                if (count) MSBDGuardLog("step 1b: the crash guard's note was cleared, parts load again");
                unlink(MSBD_STEP_FILE);
                count = 0;
            }
            state = count > 0;
        }
    }
    for (int i = 0; i < count; i++) if (strcmp(list[i], name) == 0) { MSBDGuardLog("step 1b: %s not loaded (it crashed SpringBoard)", name); return 1; }
    return 0;
}

// The per-display settings (1.8.7, plans/design-1.8.7-displays.md section 8): when step 1b sets a switch K of one of KT's domains (part P: msb or
// dock, DisplayPrefs.h), every display's override of it ("*/P/K" in the displays domain) goes too, so an override on a TV cannot keep a crashing
// path on; the displays then follow the iPad's key, as it is switched back on. A row whose display default is not the switch's off value (Show Trash
// in Dock: ON on every display) would stay on without an override, so there every remembered display ("<display>/info") gets the off value as its
// own override instead (review of 1.8.7: the TV's Trash, on by its default with the iPad's off, kept the crashing path); its own row in Display
// Settings switches it on again. Other keys and other displays' other keys stay. Returns how many changed.
static inline int MSBDGuardDispClear(const char *domain, const char *key, int value) {
    const char *part = MSBDDispPartOfDomain(domain);
    if (!part || !key) return 0;
    void *cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY | RTLD_NOLOAD);
    if (!cf) return 0;
    const void *(*mk)(const void *, const char *, unsigned int) = (const void *(*)(const void *, const char *, unsigned int))dlsym(cf, "CFStringCreateWithCString");
    const void *(*list)(const void *, const void *, const void *) = (const void *(*)(const void *, const void *, const void *))dlsym(cf, "CFPreferencesCopyKeyList");
    long (*count)(const void *) = (long (*)(const void *))dlsym(cf, "CFArrayGetCount");
    const void *(*at)(const void *, long) = (const void *(*)(const void *, long))dlsym(cf, "CFArrayGetValueAtIndex");
    unsigned char (*cstr)(const void *, char *, long, unsigned int) = (unsigned char (*)(const void *, char *, long, unsigned int))dlsym(cf, "CFStringGetCString");
    unsigned long (*typeOf)(const void *) = (unsigned long (*)(const void *))dlsym(cf, "CFGetTypeID");
    unsigned long (*strType)(void) = (unsigned long (*)(void))dlsym(cf, "CFStringGetTypeID");
    void (*set)(const void *, const void *, const void *, const void *, const void *) = (void (*)(const void *, const void *, const void *, const void *, const void *))dlsym(cf, "CFPreferencesSetValue");
    unsigned char (*sync)(const void *, const void *, const void *) = (unsigned char (*)(const void *, const void *, const void *))dlsym(cf, "CFPreferencesSynchronize");
    void (*rel)(const void *) = (void (*)(const void *))dlsym(cf, "CFRelease");
    const void **user = (const void **)dlsym(cf, "kCFPreferencesCurrentUser"), **host = (const void **)dlsym(cf, "kCFPreferencesAnyHost");
    const void **yes = (const void **)dlsym(cf, "kCFBooleanTrue"), **no = (const void **)dlsym(cf, "kCFBooleanFalse");
    int def = 0, setOff = MSBDDispDisplayDefault(part, key, &def) && (def != 0) != (value != 0);   // (the display default is on: written off, not cleared)
    int n = 0;
    if (mk && list && count && at && cstr && typeOf && strType && set && sync && rel && user && host && (!setOff || (yes && no))) {
        const void *d = mk(NULL, MSBD_DISP_DOMAIN, 0x08000100);   // (kCFStringEncodingUTF8)
        if (d) {
            sync(d, *user, *host);
            const void *keys = list(d, *user, *host);
            const void *offValue = setOff ? (value ? *yes : *no) : NULL;
            for (long i = 0, c = keys ? count(keys) : 0; i < c; i++) {
                const void *k = at(keys, i); char flat[256];
                if (!k || typeOf(k) != strType() || !cstr(k, flat, sizeof flat, 0x08000100)) continue;
                size_t fl = strlen(flat), sl = strlen(MSBD_DISP_INFO_SUFFIX);
                if (setOff && fl > sl && strcmp(flat + fl - sl, MSBD_DISP_INFO_SUFFIX) == 0) {   // (a remembered display: its own override, off)
                    char display[128], own[MSBD_DISP_FLAT_MAX + 1];
                    if (fl - sl >= sizeof display) continue;
                    memcpy(display, flat, fl - sl); display[fl - sl] = 0;
                    if (!MSBDDispFlatKey(own, sizeof own, display, part, key)) continue;
                    const void *ok = mk(NULL, own, 0x08000100);
                    if (!ok) continue;
                    set(ok, offValue, d, *user, *host); rel(ok);
                    MSBDGuardLog("step 1b: the per-display setting %s set %s (its display default is on)", own, value ? "on" : "off");
                    n++;
                    continue;
                }
                if (!MSBDDispFlatIs(flat, part, key)) continue;
                set(k, offValue, d, *user, *host);   // (cleared; a row with a display default: set to the off value)
                if (setOff) MSBDGuardLog("step 1b: the per-display change %s set %s", flat, value ? "on" : "off");
                else MSBDGuardLog("step 1b: the per-display change %s cleared", flat);
                n++;
            }
            if (keys) rel(keys);
            if (n) { sync(d, *user, *host); notify_post(MSBD_DISP_NOTIFY); MSBDGuardLog("step 1b: per-display changes of %s %s (%d)", key, setOff ? "set off" : "cleared", n); }
            rel(d);
        }
    }
    dlclose(cf);
    return n;
}

// Asks MacCrashBlame.dylib what one report points at: 1 with `action` (see CrashFeatureHelper.m), 0 if nothing, -1 if the helper is missing.
static inline int MSBDStepAsk(const char *report, char *action, size_t an, char *detail, size_t dn) {
    static int (*ask)(const char *, const char *, char *, size_t, char *, size_t);
    if (!ask) ask = (int (*)(const char *, const char *, char *, size_t, char *, size_t))MSBDGuardHelper("MSBDCrashFeature");
    snprintf(action, an, "(helper not available)"); if (dn) detail[0] = 0;
    return ask ? ask(report, MSBD_CRASHMAP, action, an, detail, dn) : -1;
}
// Step 1b for the row of early starts that began at `t0`, looking at the crashes since `since` (`again`: after step 1): returns
// MSBD_GUARD_ACTION_FEATURE if it turned something off (and adds its lines to `record`, rn bytes), 0 if it did nothing (already done in this row,
// or no crash could be pinned on a feature): the guard then goes on to step 2.
static inline int MSBDGuardStepFeature(long t0, long since, int again, char *record, size_t rn) {
    char line[400]; long row = 0;
    char keep[16][64], keepTitle[16][300]; int kept = 0;   // (parts skipped before: they stay skipped, and stay in the record, see below)
    FILE *f = fopen(MSBD_STEP_FILE, "r");
    if (f) {
        char part[64]; int at = 0;
        while (fgets(line, sizeof(line), f)) {
            if (sscanf(line, "row %ld", &row) == 1) continue;
            at = 0;
            if (kept < 16 && sscanf(line, "skip %63s %n", part, &at) >= 1) {
                strlcpy(keep[kept], part, sizeof(keep[0]));
                char *t = at > 0 ? line + at : line + strlen(line); t[strcspn(t, "\r\n")] = 0;
                if (*t) strlcpy(keepTitle[kept], t, sizeof(keepTitle[0]));
                else snprintf(keepTitle[kept], sizeof(keepTitle[0]), "its part %s|%s", part, part);   // (a list from before the titles were kept)
                kept++;
            }
        }
        fclose(f);
    }
    int keptBefore = kept, named[16] = {0};   // (named: an earlier part that this row's lines name again)
    if (row == t0) { MSBDGuardLog("step 1b: already done in this row of crashes"); return 0; }
    // The reports: every SpringBoard crash since `since` that counts against us (their verdicts are kept already), newest found first is not needed:
    // all of them are asked, each target turned off once.
    char paths[8][512]; int np = 0;
#if DEBUG
    if (MSBDGuardFakeReportExists()) strlcpy(paths[np++], MSBD_GUARD_FAKE_REPORT, sizeof(paths[0]));
#endif
    DIR *d = opendir(MSBD_GUARD_REPORTS);
    struct dirent *e;
    while (d && np < 8 && (e = readdir(d))) {
        if (strncmp(e->d_name, "SpringBoard-", 12) != 0 || !strstr(e->d_name, ".ips")) continue;
        struct tm tm; memset(&tm, 0, sizeof(tm));
        char p[512]; struct stat st;
        snprintf(p, sizeof(p), "%s/%s", MSBD_GUARD_REPORTS, e->d_name);
        long mtime = stat(p, &st) == 0 ? (long)st.st_mtime : 0, t = mtime;
        if (sscanf(e->d_name + 12, "%4d-%2d-%2d-%2d%2d%2d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec) == 6) {
            tm.tm_year -= 1900; tm.tm_mon -= 1; tm.tm_isdst = -1;
            t = (long)mktime(&tm);
        }
        if (t >= since && MSBDGuardCounts(e->d_name, p, mtime, t)) strlcpy(paths[np++], p, sizeof(paths[0]));
    }
    if (d) closedir(d);
    char actions[MSBD_STEP_MAX][300]; int na = 0;
    for (int i = 0; i < np && na < MSBD_STEP_MAX; i++) {
        char action[300], detail[300];
        int r = MSBDStepAsk(paths[i], action, sizeof(action), detail, sizeof(detail));
        MSBDGuardLog("step 1b: %s: %s%s", paths[i], r > 0 ? "" : "nothing to turn off: ", action);
        if (detail[0]) MSBDGuardLog("step 1b:   %s", detail);
        if (r < 0) return 0;   // (helper missing: step 2, as before)
        if (r == 0) continue;
        int dup = 0;
        for (int j = 0; j < na; j++) dup |= strcmp(actions[j], action) == 0;
        if (!dup) strlcpy(actions[na++], action, sizeof(actions[0]));
    }
    if (!na) return 0;
    for (int i = 0; i < na; i++) {
        char kind[8], image[64], domain[128], key[128]; int value = 0, at = 0;
        if (sscanf(actions[i], "%7s %63s %127s %127s %d %n", kind, image, domain, key, &value, &at) < 5) continue;
        const char *title = at > 0 ? actions[i] + at : "";
        char text[64] = "";   // (a list row's off text, CrashFeature.h: stored instead of the value, so Settings shows a choice -- Dock Style "default")
        int tn = 0;
        if (strncmp(title, "text=", 5) == 0 && sscanf(title + 5, "%63s %n", text, &tn) >= 1) title += 5 + tn;
        size_t l = record ? strlen(record) : 0;
        if (strcmp(kind, "pref") == 0 && strncmp(domain, "com.besiktasliseba.", 19) == 0) {
            if (text[0]) MSBDGuardSetPrefText(domain, key, text);
            else MSBDGuardSetPref(domain, key, kMSBDBool, value);
            char note[300];
            snprintf(note, sizeof(note), "%s/prefsChanged", domain);   // (a part that is running applies it at once)
            notify_post(note);
            MSBDGuardDispClear(domain, key, value);   // (and every display's override of it: the displays follow the iPad's key)
            if (record) snprintf(record + l, rn - l, "feature %s %s %d %s\n", domain, key, value, title);
            if (text[0]) MSBDGuardLog("step 1b: set %s %s to \"%s\" (off)", domain, key, text);
            else MSBDGuardLog("step 1b: switched %s %s %s", domain, key, value ? "on" : "off");
        } else if (strcmp(kind, "part") == 0) {
            int have = -1;
            for (int j = 0; j < kept; j++) if (strcmp(keep[j], image) == 0) have = j;
            if (have < 0 && kept < 16) { have = kept; strlcpy(keep[kept++], image, sizeof(keep[0])); }
            if (have >= 0) { strlcpy(keepTitle[have], title, sizeof(keepTitle[0])); named[have] = 1; }
            if (record) snprintf(record + l, rn - l, "part %s %s\n", image, title);
            MSBDGuardLog("step 1b: %s is not loaded from the next start on", image);
        }
    }
    // A part skipped by an earlier row is still not loaded: the new record names it too, so the pages keep its Turn Back On button and the note
    // (which keeps it skipped) is not cleared by a switch change without the user being told.
    for (int j = 0; j < keptBefore && record; j++) {
        if (named[j]) continue;   // (already in this row's lines)
        size_t l = strlen(record); snprintf(record + l, rn - l, "part %s %s\n", keep[j], keepTitle[j]);
    }
    if (again && record) { size_t l = strlen(record); snprintf(record + l, rn - l, "again 1\n"); }
    if ((f = fopen(MSBD_STEP_FILE ".new", "w"))) {
        fprintf(f, "row %ld\n", t0);
        for (int j = 0; j < kept; j++) fprintf(f, "skip %s %s\n", keep[j], keepTitle[j]);
        fclose(f);
        rename(MSBD_STEP_FILE ".new", MSBD_STEP_FILE);
    }
    return MSBD_GUARD_ACTION_FEATURE;
}
