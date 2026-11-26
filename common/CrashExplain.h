// CrashExplain.h -- the crash guard explains itself (MacStatusBar&Dock, 2026-09-26). Foundation only: used by the Status Bar and Dock pages
// (LineSwitch.h) and by the one-time notice in SpringBoard (loader/CrashNotice.m).
//  - the plain words for what the guard did and why, from its record (CrashGuard.h, MSBD_GUARD_RECORD): the pages' footer and the notice;
//  - the Report a Problem text (a GitHub new-issue link): the usual lines, plus a short crash summary while a guard record is under 7 days old
//    (which part of ours was on the crashing stack, the versions, what the guard did, the top frames of OUR image only), plus, on an untested
//    iPadOS version, the exact version, "Enable Anyway" and the names of our switches that are on. Nothing leaves the device unless the user
//    submits the issue on GitHub;
//  - the quiet note on the Status Bar page when the last SpringBoard crash (24 h) was another tweak's: its package's name from dpkg's lists; and
//    (1.8.7.7, GitHub #14) when it could not be pinned on us or anyone (only Apple code on its stacks, other tweaks loaded): its cause;
//  - (1.8.7.7) what crashed -- the cause (the exception's reason our death record kept, common/CrashCause.h, or what the report says), where, the
//    other tweaks loaded -- in the record's words, the notice's "Cause:" line and Report a Problem, which also lists the SpringBoard crashes of the
//    last 24 h with their causes, also when the guard did nothing (review of 1.8.7.7: and those it never judged, crashes on their own, that our
//    death record names). Paths in a reason become "<path>"; other tweaks are named by library only.
// Cost: none unless a guard record or a verdict of another tweak's crash exists (a failed open of a small file).
#pragma once
#include "Diag.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#include "CrashGuard.h"
#include "StageManagerAvailable.h"
#include "DpkgState.h"
#include "CauseHide.h"   // (MSBDCauseHideText: a cause never carries the user's own text, 1.8.8.1)
#include "CrashBlame.h"   // (1.8.7.7: MSBDCauseTrim, the death record kept short)
#include "MacPointerStatus.h"   // (1.8.8.2, GitHub #17: the Mac pointer's state in Report a Problem)
#include <sys/stat.h>

#ifndef MSBD_DPKG_DIR   // (overridable for the Mac test, tools/test-crashexplain.m)
#define MSBD_DPKG_DIR "/var/jb/var/lib/dpkg"
#endif
#ifndef MSBD_PREF_BUNDLES   // (overridable for the Mac test)
#define MSBD_PREF_BUNDLES "/var/jb/Library/PreferenceBundles"
#endif
#ifndef MSBD_TWEAKNAME_CACHE   // (overridable for the Mac test) "<blamed>\t<name>": the last looked-up name of another tweak
#define MSBD_TWEAKNAME_CACHE "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashTweakName.txt"
#endif
#define MSBD_REPORT_URL @"https://github.com/BesiktasliSeba/MacStatusBarAndDock/issues/new"
#define MSBD_EXPLAIN_CAUSES 1   // (1.8.7.7: what crashed, in words -- the Mac test runs on the code before it too, tools/test-crashexplain.sh)
#define MSBD_EXPLAIN_DOMAIN CFSTR("com.besiktasliseba.macstatusbaranddock")

// ---- The guard's record ------------------------------------------------------------------------------------------------------------------------
// Keys: time, action, tested, verdict (NSNumber); ios, build, blamed (NSString); switches (array of @[domain, key, title]); frames (NSString array);
// shown (the notice was shown), loads (times the notice was loaded). 1.8.7.7: cause, where (NSString), others (NSString "<n> <names>"), unknown
// (NSNumber: crashes not pinned on anyone in the row), loop (the loop breaker acted). nil if there is none.
// (1.8.7.7: a file of the guard's read as UTF-8, else byte for byte -- a record or verdict cut inside a character must not hide all of it)
static inline NSString *MSBDGuardFileText(const char *path) {
    NSData *d = [NSData dataWithContentsOfFile:@(path)];
    if (!d.length) return nil;
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
}
static inline NSDictionary *MSBDCrashRecord(void) {
    NSString *text = MSBDGuardFileText(MSBD_GUARD_RECORD);
    if (!text.length) return nil;
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    NSMutableArray *switches = [NSMutableArray array], *frames = [NSMutableArray array], *features = [NSMutableArray array], *parts = [NSMutableArray array];
    int loads = 0;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange sp = [line rangeOfString:@" "];
        NSString *name = sp.location == NSNotFound ? line : [line substringToIndex:sp.location];
        NSString *value = sp.location == NSNotFound ? @"" : [line substringFromIndex:sp.location + 1];
        if ([name isEqualToString:@"time"] || [name isEqualToString:@"action"] || [name isEqualToString:@"tested"] || [name isEqualToString:@"verdict"]) r[name] = @([value longLongValue]);
        else if ([name isEqualToString:@"ios"] || [name isEqualToString:@"build"] || [name isEqualToString:@"blamed"]) r[name] = value;
        else if ([name isEqualToString:@"cause"] || [name isEqualToString:@"where"] || [name isEqualToString:@"others"]) { if (value.length) r[name] = value; }
        else if ([name isEqualToString:@"unknown"]) r[name] = @([value intValue]);
        else if ([name isEqualToString:@"loop"]) r[@"loop"] = @([value intValue] != 0);
        else if ([name isEqualToString:@"frame"] && value.length) [frames addObject:value];
        else if ([name isEqualToString:@"shown"]) r[@"shown"] = @YES;
        else if ([name isEqualToString:@"load"]) loads++;
        else if ([name isEqualToString:@"again"]) r[@"again"] = @YES;
        else if ([name isEqualToString:@"feature"] || [name isEqualToString:@"part"]) {   // (step 1b, CrashStep.h: "... <title>|<where>")
            NSArray *p = [value componentsSeparatedByString:@" "];
            NSUInteger fixed = [name isEqualToString:@"feature"] ? 3 : 1;
            if (p.count < fixed) continue;
            NSArray *words = [[[p subarrayWithRange:NSMakeRange(fixed, p.count - fixed)] componentsJoinedByString:@" "] componentsSeparatedByString:@"|"];
            NSString *a = words.count > 0 ? words[0] : @"", *b = words.count > 1 ? words[1] : a;
            if ([name isEqualToString:@"feature"]) [features addObject:@[p[0], p[1], @([p[2] intValue]), a, b]];   // domain, key, value, row title, where
            else [parts addObject:@[p[0], a.length ? a : p[0], b.length ? b : p[0]]];                             // image, where, what
        }
        else if ([name isEqualToString:@"switch"]) {
            NSArray *p = [value componentsSeparatedByString:@" "];
            if (p.count < 2) continue;
            NSString *title = p.count > 2 ? [[p subarrayWithRange:NSMakeRange(2, p.count - 2)] componentsJoinedByString:@" "] : @"";
            [switches addObject:@[p[0], p[1], title]];
        }
    }
    if (!r[@"time"] || !r[@"action"]) return nil;
    r[@"switches"] = switches; r[@"frames"] = frames; r[@"loads"] = @(loads); r[@"features"] = features; r[@"parts"] = parts;
    return r;
}
static inline int MSBDExplainAction(void) {   // crashGuardAction (0 = nothing to say)
    CFPreferencesSynchronize(MSBD_EXPLAIN_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_GUARD_ACTION_KEY), MSBD_EXPLAIN_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    int action = v && CFGetTypeID(v) == CFNumberGetTypeID() ? [(__bridge NSNumber *)v intValue] : 0;
    if (v) CFRelease(v);
    return action;
}

// “A”, “A” and “B”, “A”, “B” and “C”.
static inline NSString *MSBDQuotedList(NSArray<NSString *> *names) {
    NSMutableArray *q = [NSMutableArray array];
    for (NSString *n in names) [q addObject:[NSString stringWithFormat:@"“%@”", n]];
    if (q.count < 2) return q.firstObject ?: @"";
    return [NSString stringWithFormat:@"%@ and %@", [[q subarrayWithRange:NSMakeRange(0, q.count - 1)] componentsJoinedByString:@", "], q.lastObject];
}
// Menu Bar Size (a domain and key of the record: a step 1 "switch" line, noted since 1.8.7.5, audit L62; a step 1b "feature" line): no switch, a
// size -- the guard set it back to Small (false, read as Small: common/MenuBarSize.h), and its words say so, not "turned on ... turned off" (the
// review of 1.8.7.5).
static inline BOOL MSBDGuardIsMenuBarSize(NSArray *line) { return line.count > 1 && [line[0] isEqual:@MSBD_DISP_MSB_DOMAIN] && [line[1] isEqual:@kMSBDMenuBarSizeKey]; }
static inline BOOL MSBDGuardSetSizeBack(NSDictionary *record, int action) {
    if ([record[@"action"] intValue] != action) return NO;
    for (NSArray *s in record[action == 4 ? @"features" : @"switches"]) if (MSBDGuardIsMenuBarSize(s)) return YES;
    return NO;
}
// The row titles of the switches the guard turned off (its record, when it matches `action`); Menu Bar Size is not one (MSBDGuardSetSizeBack).
static inline NSArray<NSString *> *MSBDGuardSwitchTitles(NSDictionary *record, int action) {
    NSMutableArray *titles = [NSMutableArray array];
    if ([record[@"action"] intValue] != action) return titles;
    for (NSArray *s in record[@"switches"]) {
        NSString *t = s[2];
        if (t.length && !MSBDGuardIsMenuBarSize(s) && ![titles containsObject:t]) [titles addObject:t];
    }
    return titles;
}
// A switch noted without a title (the inverted Home Screen rows, "Show Page Dots" / "Show App Names": their titles say the opposite of the stored key):
// the guard undid a change there, which "turned on ... turned off" would describe the wrong way round.
static inline BOOL MSBDGuardUntitledSwitch(NSDictionary *record, int action) {
    if ([record[@"action"] intValue] != action) return NO;
    for (NSArray *s in record[@"switches"]) if (![s[2] length]) return YES;
    return NO;
}

// Step 1b (action 4, CrashStep.h): what went off, from the record: its sentence ("SpringBoard crashed twice in the Dock, so the Dock was turned off
// for now."), whether a part is no longer loaded (then "Turn Back On" brings it back), whether only Stock status bar mode was switched on.
static inline BOOL MSBDStepIsStockBar(NSArray *feature) { return [feature[1] isEqualToString:@"stockStatusBar"] && [feature[2] intValue] == 1; }
// (our own Control Center, 1.8.0: Control Center Style set back to iPadOS's -- the guard stores "stock", its off text (false before 1.8.4: read the same))
static inline BOOL MSBDStepIsStockCC(NSArray *feature) { return [feature[1] isEqualToString:@"controlCenterStyle"] && [feature[2] intValue] == 0; }
static inline NSString *MSBDStepSentence(NSDictionary *record) {
    NSMutableArray *wheres = [NSMutableArray array], *clauses = [NSMutableArray array];
    for (NSArray *f in record[@"features"]) {
        if (![wheres containsObject:f[4]]) [wheres addObject:f[4]];
        [clauses addObject:MSBDStepIsStockBar(f) ? @"the stock status bar is used for now" : MSBDStepIsStockCC(f) ? @"iPadOS's Control Center is used for now"
            : MSBDGuardIsMenuBarSize(f) ? @"Menu Bar Size was set back to Small"
            : [NSString stringWithFormat:@"“%@” was turned %@", f[3], [f[2] intValue] ? @"on" : @"off"]];
    }
    for (NSArray *p in record[@"parts"]) {
        if (![wheres containsObject:p[1]]) [wheres addObject:p[1]];
        [clauses addObject:[NSString stringWithFormat:@"%@ was turned off for now", p[2]]];
    }
    if (!clauses.count) return @"SpringBoard crashed twice, so the part of MacStatusBar&Dock that crashed was turned off.";
    NSString *(^and)(NSArray *) = ^NSString *(NSArray *a) {
        if (a.count < 2) return a.firstObject ?: @"";
        return [NSString stringWithFormat:@"%@ and %@", [[a subarrayWithRange:NSMakeRange(0, a.count - 1)] componentsJoinedByString:@", "], a.lastObject];
    };
    return [NSString stringWithFormat:@"SpringBoard crashed %@ in %@, so %@.", [record[@"again"] boolValue] ? @"again" : @"twice", and(wheres), and(clauses)];
}
// A part is no longer loaded: the record's "part" lines, whatever the action (1.8.7.5, audit L104 of 1.8.7.2: step 1's record names the parts an
// earlier step 1b left unloaded). MSBDGuardPartsOffFor: so for the guard's note `action` now (its record is that note's).
static inline BOOL MSBDStepPartsOff(NSDictionary *record) { return [record[@"parts"] count] > 0; }
static inline BOOL MSBDGuardPartsOffFor(int action) { NSDictionary *r = MSBDCrashRecord(); return action && [r[@"action"] intValue] == action && MSBDStepPartsOff(r); }
// What those parts are, in the record's words, each once: "the Dock", "audio mixing".
static inline NSArray<NSString *> *MSBDStepPartsWhat(NSDictionary *record) {
    NSMutableArray *whats = [NSMutableArray array];
    for (NSArray *p in record[@"parts"]) if (![whats containsObject:p[2]]) [whats addObject:p[2]];
    return whats;
}
static inline BOOL MSBDStepOnlyStockBar(NSDictionary *record) {
    if ([record[@"parts"] count] || ![record[@"features"] count]) return NO;
    for (NSArray *f in record[@"features"]) if (!MSBDStepIsStockBar(f)) return NO;
    return YES;
}

// What the guard did and why, in plain words. forAlert: the notice's text (its buttons differ from the page's rows); else the pages' footer.
// untested: an iPadOS version other than 15/16 ("Enable Anyway" is what the guard switched off). nil if the guard did nothing.
static inline NSString *MSBDGuardExplanation(int action, BOOL untested, BOOL forAlert) {
    if (action < 1 || action > 4) return nil;
    if (action == 4) {
        NSDictionary *r = MSBDCrashRecord();
        if ([r[@"action"] intValue] != 4) r = nil;
        NSString *what = r ? MSBDStepSentence(r) : @"SpringBoard crashed twice, so the part of MacStatusBar&Dock that crashed was turned off.";
        NSString *next;
        if (MSBDStepPartsOff(r)) next = untested ? (forAlert ? @" To try again, turn Enable Anyway off and on in Settings." : @" Turn Enable Anyway off and on to try again, or tap Report a Problem.")
                                                 : (forAlert ? @" To try again, tap Turn Back On in Settings." : @" Tap Turn Back On to try again, or Report a Problem.");
        else if (MSBDStepOnlyStockBar(r)) next = forAlert ? @" To try again, set Status Bar Style back to Mac in Settings." : @" Set Status Bar Style back to Mac to try again, or tap Report a Problem.";
        else next = forAlert ? @" You can switch it back in Settings; if this keeps happening, tap Report a Problem." : @" You can switch it back here; if this keeps happening, tap Report a Problem.";
        return [what stringByAppendingString:next];
    }
    if (action == 1) {
        NSDictionary *r = MSBDCrashRecord();
        NSArray *titles = MSBDGuardSwitchTitles(r, 1);
        BOOL size = MSBDGuardSetSizeBack(r, 1);   // (a larger Menu Bar Size picked: set back to Small, said so)
        NSString *what = MSBDGuardUntitledSwitch(r, 1) ? @"The settings you changed last were undone after SpringBoard crashed twice."
            : titles.count && size
            ? [NSString stringWithFormat:@"SpringBoard crashed twice after %@ %@ turned on and a larger Menu Bar Size was picked, so %@ %@ turned off and Menu Bar Size was set back to Small.",
               MSBDQuotedList(titles), titles.count > 1 ? @"were" : @"was", MSBDQuotedList(titles), titles.count > 1 ? @"were" : @"was"]
            : size ? @"SpringBoard crashed twice after a larger Menu Bar Size was picked, so it was set back to Small."
            : titles.count
            ? [NSString stringWithFormat:@"SpringBoard crashed twice after %@ %@ turned on, so %@ turned off.", MSBDQuotedList(titles), titles.count > 1 ? @"were" : @"was", titles.count > 1 ? @"they were" : @"it was"]
            : @"The features you turned on last were turned off after SpringBoard crashed twice.";
        // (1.8.7.5, audit L104: a part an earlier step 1b stopped loading stays off under this note: said, with step 1b's way back)
        if ([r[@"action"] intValue] == 1 && MSBDStepPartsOff(r)) {
            NSArray *whats = MSBDStepPartsWhat(r);
            NSString *list = whats.count < 2 ? whats.firstObject : [NSString stringWithFormat:@"%@ and %@", [[whats subarrayWithRange:NSMakeRange(0, whats.count - 1)] componentsJoinedByString:@", "], whats.lastObject];
            what = [what stringByAppendingFormat:@" After an earlier crash, %@ %@ still turned off.", list, whats.count > 1 ? @"are" : @"is"];
            return [what stringByAppendingString:untested ? (forAlert ? @" To try again, turn Enable Anyway off and on in Settings." : @" Turn Enable Anyway off and on to try again, or tap Report a Problem.")
                                                          : (forAlert ? @" To try again, tap Turn Back On in Settings." : @" Tap Turn Back On to try again, or Report a Problem.")];
        }
        return [what stringByAppendingString:forAlert ? @" If this keeps happening, tap Report a Problem in Settings." : @" If this keeps happening, tap Report a Problem."];
    }
    // (1.8.7.7, #14: the loop breaker -- SpringBoard kept crashing, nothing pinned on anyone: said so, and what tells whose it was)
    NSDictionary *loopRecord = MSBDCrashRecord();
    if ([loopRecord[@"action"] intValue] == action && [loopRecord[@"loop"] boolValue]) {
        NSString *what = @"SpringBoard kept crashing and the crashes could not be pinned on MacStatusBar&Dock or another tweak, so MacStatusBar&Dock was turned off to stop the loop. If SpringBoard still crashes with it off, it was not MacStatusBar&Dock: ";
        if (untested) return [what stringByAppendingString:forAlert ? @"turn on Enable Anyway in Settings." : @"turn on Enable Anyway."];
        return [what stringByAppendingString:forAlert ? @"tap Turn Back On in Settings." : @"tap Turn Back On."];
    }
    NSString *what = action == 3 ? @"MacStatusBar&Dock was turned off because SpringBoard kept crashing." : @"MacStatusBar&Dock was turned off after SpringBoard crashed twice.";
    if (untested) return [what stringByAppendingString:forAlert ? @" To try again, turn on Enable Anyway in Settings." : @" Turn on Enable Anyway to try again, or tap Report a Problem."];
    return [what stringByAppendingString:forAlert ? @" To try again, tap Turn Back On in Settings." : @" Tap Turn Back On to try again, or Report a Problem."];
}
static inline NSString *MSBDGuardAlertTitle(int action) {
    if (action == 4) {
        NSDictionary *r = MSBDCrashRecord();
        if (MSBDStepOnlyStockBar(r)) return @"Stock Status Bar in Use";
        if ([r[@"features"] count] + [r[@"parts"] count] == 1 && MSBDGuardSetSizeBack(r, 4)) return @"Menu Bar Size Set Back";
        return [r[@"features"] count] + [r[@"parts"] count] > 1 ? @"Features Turned Off" : @"Feature Turned Off";
    }
    if (action != 1) return @"MacStatusBar&Dock Turned Off";
    if (MSBDGuardUntitledSwitch(MSBDCrashRecord(), 1)) return @"Settings Undone";
    NSDictionary *r = MSBDCrashRecord();   // (a part still off from an earlier crash counts too: L104; Menu Bar Size set back is one thing too)
    NSUInteger things = MSBDGuardSwitchTitles(r, 1).count + ([r[@"action"] intValue] == 1 ? [r[@"parts"] count] : 0);
    if (MSBDGuardSetSizeBack(r, 1)) return things ? @"Features Turned Off" : @"Menu Bar Size Set Back";
    return things > 1 ? @"Features Turned Off" : @"Feature Turned Off";
}

static inline NSString *MSBDReportSanitize(NSString *text, NSUInteger max);
// The notice's last line (1.8.7.7, #14): "Cause: <the cause>" (at most 120 characters), when the guard's record names one; else nil.
static inline NSString *MSBDGuardNoticeCause(void) {
    NSString *c = MSBDReportSanitize(MSBDCrashRecord()[@"cause"], 120);
    return c.length ? [@"Cause: " stringByAppendingString:c] : nil;
}

// ---- Report a Problem --------------------------------------------------------------------------------------------------------------------------
static inline NSString *MSBDExplainOSVersion(void) {   // (kern.osproductversion, e.g. 16.5.1)
    char v[32] = {0}; size_t n = sizeof(v);
    if (sysctlbyname("kern.osproductversion", v, &n, NULL, 0) != 0 || !v[0]) return @"unknown";
#if DEBUG
    if (MSBDOSMajor() && MSBDOSMajor() != atoi(v)) return [NSString stringWithFormat:@"%s (test build acting as %d)", v, MSBDOSMajor()];   // (/tmp/msb-fakeversion)
#endif
    return @(v);
}
static inline NSString *MSBDExplainMachine(void) {   // (hw.machine, e.g. iPad13,4)
    char m[64] = {0}; size_t n = sizeof(m);
    if (sysctlbyname("hw.machine", m, &n, NULL, 0) != 0 || !m[0]) return @"unknown";
    return @(m);
}
// (MSBDPackageFieldIn: DpkgState.h)
// dpkg's status file (1-3 MB with a few thousand packages) is read only when it changed: its modification time and size are the key (S-2, 4 Oct:
// the Apple menu asks for our installed version every time it opens, and SpringBoard's main thread read and split the whole file each time).
// The answers are kept per package and field until the file changes; any thread may ask.
#ifndef MSBD_DPKG_STATUS
#define MSBD_DPKG_STATUS MSBD_DPKG_DIR "/status"
#endif
typedef struct { long long sec, nsec, size; } MSBDFileStamp;
static inline BOOL MSBDFileStampOf(const char *path, MSBDFileStamp *out) {
    struct stat st;
    *out = (MSBDFileStamp){0, 0, -1};
    if (stat(path, &st) != 0) return NO;
    *out = (MSBDFileStamp){(long long)st.st_mtimespec.tv_sec, (long long)st.st_mtimespec.tv_nsec, (long long)st.st_size};
    return YES;
}
static NSMutableDictionary *gMSBDDpkgAnswers;   // "<package>\n<field>" -> value or NSNull, for the file as stamped below
static MSBDFileStamp gMSBDDpkgStamp = {0, 0, -2};
static int gMSBDDpkgReads;                      // (how often the file was really read: the Mac test counts it)
static inline NSString *MSBDPackageFieldCached(NSString *package, NSString *field, BOOL readIfNeeded, BOOL *known) {
    static NSObject *lock; static dispatch_once_t once; dispatch_once(&once, ^{ lock = [NSObject new]; });
    if (known) *known = NO;
    if (!package.length || !field.length) { if (known) *known = YES; return nil; }
    MSBDFileStamp now; MSBDFileStampOf(MSBD_DPKG_STATUS, &now);
    NSString *key = [NSString stringWithFormat:@"%@\n%@", package, field];
    @synchronized (lock) {
        if (memcmp(&now, &gMSBDDpkgStamp, sizeof now) != 0) { gMSBDDpkgAnswers = [NSMutableDictionary dictionary]; gMSBDDpkgStamp = now; }
        id hit = gMSBDDpkgAnswers[key];
        if (hit) { if (known) *known = YES; return hit == [NSNull null] ? nil : hit; }
    }
    if (!readIfNeeded) return nil;
    NSString *status = [NSString stringWithContentsOfFile:@MSBD_DPKG_STATUS encoding:NSUTF8StringEncoding error:nil];   // (outside the lock)
    NSString *value = MSBDPackageFieldIn(status, package, field);
    @synchronized (lock) {
        gMSBDDpkgReads++;
        MSBDFileStamp after; MSBDFileStampOf(MSBD_DPKG_STATUS, &after);
        if (memcmp(&after, &now, sizeof now) == 0 && memcmp(&now, &gMSBDDpkgStamp, sizeof now) == 0) gMSBDDpkgAnswers[key] = value ?: (id)[NSNull null];   // (not if it changed meanwhile)
    }
    if (known) *known = YES;
    return value;
}
static inline NSString *MSBDPackageField(NSString *package, NSString *field) { return MSBDPackageFieldCached(package, field, YES, NULL); }   // from dpkg's status file (readable by everyone)
static inline NSString *MSBDPackageVersion(NSString *package) { return MSBDPackageField(package, @"Version"); }
// For the main thread: the answer if it is known for the file as it is now; otherwise the last answer given (or nil), and the file is read on a
// background queue for the next time. A package's version only changes when dpkg rewrites the file, and installing ours restarts SpringBoard.
static inline NSString *MSBDPackageVersionNoWait(NSString *package) {
    static NSMutableDictionary *lastGiven; static dispatch_once_t once; dispatch_once(&once, ^{ lastGiven = [NSMutableDictionary dictionary]; });
    BOOL known = NO;
    NSString *v = MSBDPackageFieldCached(package, @"Version", NO, &known);
    @synchronized (lastGiven) {
        if (known) { if (v) lastGiven[package] = v; else [lastGiven removeObjectForKey:package]; return v; }
        v = lastGiven[package];
    }
    static NSMutableSet *reading; static dispatch_once_t once2; dispatch_once(&once2, ^{ reading = [NSMutableSet set]; });
    NSString *pkg = [package copy];
    @synchronized (reading) { if ([reading containsObject:pkg]) return v; [reading addObject:pkg]; }   // (one read at a time per package)
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *read = MSBDPackageVersion(pkg);
        @synchronized (lastGiven) { if (read) lastGiven[pkg] = read; else [lastGiven removeObjectForKey:pkg]; }
        @synchronized (reading) { [reading removeObject:pkg]; }
    });
    return v;
}
// The package whose file list has this file: the exact path first (rootless paths are normalized to /var/jb/...), else a file of that name.
static inline NSString *MSBDPackageOwning(NSString *path) {
    if (!path.length) return nil;
    NSString *norm = path;
    NSRange pr = [path rangeOfString:@"/procursus/"];
    if (pr.location != NSNotFound) norm = [@"/var/jb/" stringByAppendingString:[path substringFromIndex:NSMaxRange(pr)]];
    else if ([path hasPrefix:@"/private/var/jb/"]) norm = [path substringFromIndex:8];
    NSString *file = path.lastPathComponent, *byName = nil;
    NSString *dir = @MSBD_DPKG_DIR "/info";
    for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        if (![f hasSuffix:@".list"]) continue;
        NSString *list = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:f] encoding:NSUTF8StringEncoding error:nil];
        if (![list containsString:[@"/" stringByAppendingString:file]]) continue;
        for (NSString *line in [list componentsSeparatedByString:@"\n"]) {
            if ([line isEqualToString:norm] || (path.length && [line isEqualToString:path])) return [f stringByDeletingPathExtension];
            if (!byName && [line.lastPathComponent isEqualToString:file] && [line hasPrefix:@"/"]) byName = [f stringByDeletingPathExtension];
        }
    }
    return byName;
}
static inline NSString *MSBDPackageNameOwning(NSString *path) {   // the Name shown in Sileo; the package id; else nil
    NSString *pkg = MSBDPackageOwning(path);
    if (!pkg) return nil;
    return MSBDPackageField(pkg, @"Name") ?: pkg;
}

// Our part from the guard's word for what it blamed ("MacStatusBarCore.dylib_(faulting_thread)", "MSBRootListController_(crash_text)").
static inline NSString *MSBDCrashPartName(NSDictionary *record) {
    int verdict = [record[@"verdict"] intValue];
    NSString *blamed = record[@"blamed"] ?: @"";
    if (verdict == -1) return @"none (a simulated crash)";
    // (a watchdog report: SpringBoard did not crash but stopped answering, and the system restarted it -- its stuck main thread is what was judged)
    BOOL watchdog = [blamed hasPrefix:@"watchdog"];
    // (1.8.7.7, #14: only Apple code on the stacks does not clear us -- 36 of our hooks tail-called before, our code can act without a frame -- nor
    //  anyone else: "not known", and whether other tweaks were loaded)
    if (verdict == kMSBDVerdictApple) return watchdog ? @"not known: SpringBoard was stuck in Apple code and the system restarted it" : @"not known: only Apple code on the crashing stack";
    if (verdict == kMSBDVerdictUnpinned) return watchdog ? @"not known: SpringBoard was stuck in Apple code and the system restarted it, other tweaks loaded" : @"not known: only Apple code on the crashing stack, other tweaks loaded";
    if (verdict != kMSBDVerdictOurs) {   // (the words for what the report did not tell -- "could not be read" was shown for all of them before)
        if (watchdog) return @"not known: SpringBoard was stuck and the system restarted it (the report shows no stacks)";
        if ([blamed hasPrefix:@"no_crash_stacks"] || [blamed hasPrefix:@"no_named_images"]) return @"not known (the crash report has no crash details)";
        if ([blamed hasPrefix:@"too_large"]) return @"not known (the crash report was empty or too large)";
        return @"not known (the crash report could not be read)";
    }
    if (watchdog) blamed = [blamed substringFromIndex:MIN(blamed.length, (NSUInteger)9)];   // ("watchdog:" + what was on the stuck main thread)
    NSRange r = [blamed rangeOfString:@"_(" options:NSBackwardsSearch];
    NSString *name = r.location == NSNotFound ? blamed : [blamed substringToIndex:r.location];
    BOOL text = [blamed hasSuffix:@"_(crash_text)"];
    if ([name hasSuffix:@".dylib"]) name = [name substringToIndex:name.length - 6];
    if (text) return [NSString stringWithFormat:@"%@ (named in the crash message)", name];
    if ([name isEqualToString:@"MacStatusBar"] || [name isEqualToString:@"MacDock"]) return [name stringByAppendingString:@" (loader)"];
    if ([name containsString:@"Settings"]) return [name stringByAppendingString:@" (a Settings part)"];
    return name.length ? name : @"ours";
}
static inline NSString *MSBDGuardActionWords(NSDictionary *record) {
    int action = [record[@"action"] intValue];
    if (action == 1) {
        NSArray *titles = MSBDGuardSwitchTitles(record, 1);
        BOOL size = MSBDGuardSetSizeBack(record, 1);
        NSMutableString *words = [(titles.count ? [NSString stringWithFormat:@"turned off %@%@", MSBDQuotedList(titles), size ? @", set Menu Bar Size back to Small" : @""]
                                   : size ? @"set Menu Bar Size back to Small" : @"turned off the switches turned on last") mutableCopy];
        for (NSArray *p in record[@"parts"]) [words appendFormat:@", still not loading %@ (%@)", p[2], p[0]];   // (from an earlier step 1b: L104)
        if ([record[@"loop"] boolValue]) [words appendString:@" (SpringBoard kept crashing, nothing pinned on anyone)"];
        return words;
    }
    if (action == 4) {   // (step 1b: "turned off “Mac-Style Banners”", "switched to the stock status bar", "stopped loading the Dock (DockMagnification)")
        NSMutableArray *done = [NSMutableArray array];
        for (NSArray *f in record[@"features"])
            [done addObject:MSBDStepIsStockBar(f) ? @"switched to the stock status bar" : MSBDStepIsStockCC(f) ? @"switched to iPadOS's Control Center"
                : MSBDGuardIsMenuBarSize(f) ? @"set Menu Bar Size back to Small"
                : [NSString stringWithFormat:@"turned %@ “%@”", [f[2] intValue] ? @"on" : @"off", f[3]]];
        for (NSArray *p in record[@"parts"]) [done addObject:[NSString stringWithFormat:@"stopped loading %@ (%@)", p[2], p[0]]];
        return [NSString stringWithFormat:@"%@ (only what crashed)", done.count ? [done componentsJoinedByString:@", "] : @"turned off what crashed"];
    }
    NSString *off = [record[@"tested"] intValue] ? @"turned MacStatusBar&Dock off (safe mode)" : @"switched Enable Anyway off";
    if ([record[@"loop"] boolValue]) return [off stringByAppendingString:@" to stop a crash loop nothing could be pinned on"];   // (1.8.7.7: the loop breaker)
    return action == 3 ? [off stringByAppendingString:@" after more crashes"] : off;
}
// A crash's words for Report a Problem (1.8.7.7, #14): one line, paths of the user's files ("/var/mobile/...", "/private/var/mobile/...", app
// folders, file:// links) as "<path>", at most `max` characters. 1.8.8.1: first, no quoted text of a view and no sticky note's details (CauseHide.h:
// a record written by an older build too).
static inline NSString *MSBDReportSanitize(NSString *text, NSUInteger max) {
    if (![text isKindOfClass:[NSString class]] || !text.length) return @"";
    text = MSBDCauseHideText(text);
    NSString *t = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"]] componentsJoinedByString:@" "];
    static NSRegularExpression *paths; static dispatch_once_t once;
    dispatch_once(&once, ^{ paths = [NSRegularExpression regularExpressionWithPattern:@"(file://[^\\s'\"]*|(/private)?/var/(mobile|containers|jb/var/mobile)(/[^\\s'\",;)]*)?)" options:NSRegularExpressionCaseInsensitive error:nil]; });
    t = [paths stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@"<path>"];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (t.length > max) t = [[t substringToIndex:[t rangeOfComposedCharacterSequenceAtIndex:max > 0 ? max - 1 : 0].location] stringByAppendingString:@"…"];
    return t;
}
// "<n> <name>, <name>, ..." (the record's "others", a verdict's): "<n> (<names>)", the names cut at `max` characters; nil when none.
static inline NSString *MSBDReportOthers(NSString *others, NSUInteger max) {
    if (![others isKindOfClass:[NSString class]]) return nil;
    NSRange sp = [others rangeOfString:@" "];
    int n = [others intValue];
    if (n <= 0) return nil;
    NSString *names = sp.location == NSNotFound ? @"" : MSBDReportSanitize([others substringFromIndex:sp.location + 1], max);
    return names.length ? [NSString stringWithFormat:@"%d (%@)", n, names] : [NSString stringWithFormat:@"%d", n];
}
// The crash summary, while a guard record is under 7 days old (nil otherwise). maxFrames: how many of our frames to list.
static inline NSString *MSBDReportCrashSummary(NSUInteger maxFrames) {
    NSDictionary *r = MSBDCrashRecord();
    long age = (long)time(NULL) - [r[@"time"] longValue];
    if (!r || age < 0 || age > 7 * 86400) return nil;
    NSMutableString *s = [NSMutableString stringWithString:@"\n**Crash summary** (from Automatic Crash Recovery)\n"];
    NSString *when = age < 3600 ? @"less than an hour ago" : age < 86400 ? [NSString stringWithFormat:@"%ld h ago", age / 3600] : [NSString stringWithFormat:@"%ld day%@ ago", age / 86400, age / 86400 == 1 ? @"" : @"s"];
    [s appendFormat:@"- Guard: %@, %@\n", MSBDGuardActionWords(r), when];
    [s appendFormat:@"- Our part involved: %@\n", MSBDCrashPartName(r)];
    // (1.8.7.7, #14: what crashed -- the reason, where, the other tweaks loaded; a short form when the link must shrink)
    NSUInteger room = maxFrames >= 5 ? 200 : maxFrames >= 3 ? 120 : 60;
    NSString *cause = MSBDReportSanitize(r[@"cause"], room), *where = MSBDReportSanitize(r[@"where"], room), *others = MSBDReportOthers(r[@"others"], room);
    if (cause.length) [s appendFormat:@"- Cause: %@\n", cause];
    if (where.length) [s appendFormat:@"- Where: %@\n", where];
    if (others.length) [s appendFormat:@"- Other tweaks loaded: %@\n", others];
    [s appendFormat:@"- At the time: iPadOS %@%@, %@, build %@\n", r[@"ios"] ?: @"?", [r[@"tested"] intValue] ? @"" : @" (untested)", MSBDExplainMachine(), r[@"build"] ?: @"?"];
    NSArray *frames = r[@"frames"];
    if (frames.count && maxFrames) {
        [s appendString:@"- Top frames (ours only):\n```\n"];
        for (NSUInteger i = 0; i < frames.count && i < maxFrames; i++) [s appendFormat:@"%@\n", frames[i]];
        [s appendString:@"```\n"];
    }
    return s;
}
// The SpringBoard crashes the guard judged (its verdict file, 1.8.7.7): newest first, each report once (its last line), those under `maxAge` s
// old. Each: stamp (yyyy-MM-dd-HHmmss, from the report's name), age, verdict, blamed (one word), cause, where, others ("<n> <names>").
static inline NSArray<NSDictionary *> *MSBDJudgedCrashes(NSTimeInterval maxAge) {
    NSString *text = MSBDGuardFileText(MSBD_GUARD_VERDICTS);
    if (!text.length) return @[];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; df.dateFormat = @"yyyy-MM-dd-HHmmss";
    NSMutableDictionary<NSString *, NSDictionary *> *byReport = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray *tabs = [line componentsSeparatedByString:@"\t"];
        NSArray *p = [tabs[0] componentsSeparatedByString:@" "];
        if (p.count < 3 || ![p[0] hasPrefix:@"SpringBoard-"] || [p[0] length] < 29) continue;
        NSString *stamp = [p[0] substringWithRange:NSMakeRange(12, 17)];
        NSDate *when = [df dateFromString:stamp];
        NSTimeInterval age = when ? -[when timeIntervalSinceNow] : 1e9;
        if (age < -300 || age > maxAge) continue;
        byReport[p[0]] = @{@"stamp": stamp, @"age": @(age), @"verdict": @([p[1] intValue]), @"blamed": [[p subarrayWithRange:NSMakeRange(2, p.count - 2)] componentsJoinedByString:@" "],
                           @"cause": tabs.count > 1 ? tabs[1] : @"", @"where": tabs.count > 2 ? tabs[2] : @"", @"others": tabs.count > 3 ? tabs[3] : @""};
    }
    return [byReport.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"stamp"] compare:a[@"stamp"]]; }];
}
// What a judged crash was, in a few words (Report a Problem's list): never a path.
static inline NSString *MSBDJudgedCrashWords(NSDictionary *c) {
    int v = [c[@"verdict"] intValue];
    NSString *blamed = c[@"blamed"] ?: @"";
    BOOL stuck = [blamed hasPrefix:@"watchdog:"];
    if (stuck) blamed = [blamed substringFromIndex:9];
    NSString *words;
    if (v == kMSBDVerdictOurs) words = @"MacStatusBar&Dock";
    else if (v == kMSBDVerdictOther) {
        NSRange r = [blamed rangeOfString:@"_(" options:NSBackwardsSearch];
        NSString *lib = (r.location == NSNotFound ? blamed : [blamed substringToIndex:r.location]).lastPathComponent;
        words = [NSString stringWithFormat:@"another tweak (%@)", lib.length ? lib : @"?"];
    } else if (v == kMSBDVerdictUnpinned) words = @"not pinned (only Apple code on the stack, other tweaks loaded)";
    else if (v == kMSBDVerdictApple) words = @"not pinned (only Apple code on the stack)";
    else if (v == -1) words = @"not judged (not in a row of crashes)";   // (review of 1.8.7.7: only our death record names it, MSBDUnjudgedDeaths)
    else words = @"not known (the report could not be read)";
    return stuck ? [@"stuck: " stringByAppendingString:words] : words;
}
// Our death record's crashes of the last `maxAge` s that the guard never judged (review of 1.8.7.7): it judges only the crashes of a row of early
// starts, so a crash on its own -- SpringBoard had run a minute, and the next start did not crash early -- has no verdict, and on 15/16 our death
// record (common/CrashCause.h) is the only place its reason exists (#14's crash 4). Read only, as Settings reads the guard's other files. The last
// line of each SpringBoard (pid); a line from 10 s before to 60 s after a judged report's time is that report's and is left out. Each: stamp
// (yyyy-MM-dd-HHmmss, local, as a report's name), age, verdict -1, cause ("<name>: <reason>").
static inline NSArray<NSDictionary *> *MSBDUnjudgedDeaths(NSTimeInterval maxAge, NSArray<NSDictionary *> *judged) {
    NSString *text = MSBDGuardFileText(MSBD_CAUSE_FILE);
    if (!text.length) return @[];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; df.dateFormat = @"yyyy-MM-dd-HHmmss";
    NSMutableArray<NSNumber *> *judgedAt = [NSMutableArray array];
    for (NSDictionary *c in judged) { NSDate *d = [c[@"stamp"] isKindOfClass:[NSString class]] ? [df dateFromString:c[@"stamp"]] : nil; if (d) [judgedAt addObject:@((long)d.timeIntervalSince1970)]; }
    NSMutableDictionary<NSNumber *, NSDictionary *> *byPid = [NSMutableDictionary dictionary];
    long now = (long)time(NULL);
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *f = [line componentsSeparatedByString:@"\t"];
        if (f.count < 6) continue;
        long pid = (long)[f[0] longLongValue], t = (long)[f[1] longLongValue];
        if (pid <= 0 || t <= 0 || now - t < -300 || now - t > maxAge) continue;
        NSString *name = [f[3] isEqualToString:@"-"] ? @"" : f[3], *reason = [f[4] isEqualToString:@"-"] ? @"" : f[4];
        NSString *cause = name.length && reason.length ? [NSString stringWithFormat:@"%@: %@", name, reason] : name.length ? name : reason;
        byPid[@(pid)] = @{@"t": @(t), @"cause": cause ?: @""};
    }
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *d in byPid.allValues) {
        long t = [d[@"t"] longValue];
        BOOL covered = NO;
        for (NSNumber *j in judgedAt) covered |= j.longValue >= t - 10 && j.longValue <= t + 60;
        if (covered) continue;
        [out addObject:@{@"stamp": [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]], @"age": @(now - t), @"verdict": @(-1), @"blamed": @"", @"cause": d[@"cause"], @"where": @"", @"others": @""}];
    }
    return out;
}
// Report a Problem's list of the SpringBoard crashes of the last 24 h (1.8.7.7, #14), also when the guard did nothing: time, whose, cause. nil if none.
// (Review of 1.8.7.7: with the crashes the guard never judged that our death record names, MSBDUnjudgedDeaths.)
static inline NSString *MSBDReportRecentCrashes(NSUInteger maxItems, NSUInteger causeChars) {
    NSArray<NSDictionary *> *judged = MSBDJudgedCrashes(86400);
    NSArray<NSDictionary *> *list = [[judged arrayByAddingObjectsFromArray:MSBDUnjudgedDeaths(86400, judged)] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"stamp"] compare:a[@"stamp"]]; }];
    if (!list.count || !maxItems) return nil;
    NSMutableString *s = [NSMutableString stringWithString:@"\n**Recent SpringBoard crashes** (24 h)\n"];
    for (NSUInteger i = 0; i < list.count && i < maxItems; i++) {
        NSDictionary *c = list[i];
        NSString *st = c[@"stamp"], *cause = MSBDReportSanitize(c[@"cause"], causeChars);
        NSString *when = st.length == 17 ? [NSString stringWithFormat:@"%@-%@ %@:%@:%@", [st substringWithRange:NSMakeRange(5, 2)], [st substringWithRange:NSMakeRange(8, 2)],
                                            [st substringWithRange:NSMakeRange(11, 2)], [st substringWithRange:NSMakeRange(13, 2)], [st substringWithRange:NSMakeRange(15, 2)]] : st;
        [s appendFormat:@"- %@: %@%@\n", when, MSBDJudgedCrashWords(c), cause.length ? [@" -- " stringByAppendingString:cause] : @""];
    }
    if (list.count > maxItems) [s appendFormat:@"- and %lu more\n", (unsigned long)(list.count - maxItems)];
    return s;
}
// Our switches on the Status Bar, Desktop, Windows & Multitasking and Dock pages that are on (their row titles), read from the pages' own lists.
static inline NSArray<NSString *> *MSBDSwitchesOn(void) {
    NSMutableArray *on = [NSMutableArray array];
    for (NSString *page in @[@"MacStatusBarPrefs/Windows", @"MacStatusBarPrefs/Desktop", @"MacStatusBarPrefs/Root", @"DockMagnificationPrefs/Root", @"MacStatusBarPrefs/MacLockScreen"]) {   // (the window switches first: the list is cut at its length)
        NSArray *bp = [page componentsSeparatedByString:@"/"];
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%s/%@.bundle/%@.plist", MSBD_PREF_BUNDLES, bp[0], bp[1]]];
        for (NSDictionary *item in [plist[@"items"] isKindOfClass:[NSArray class]] ? plist[@"items"] : @[]) {
            if (![item isKindOfClass:[NSDictionary class]] || ![item[@"cell"] isEqual:@"PSSwitchCell"]) continue;
            NSString *domain = item[@"defaults"], *key = item[@"key"], *label = item[@"label"];
            if (![domain isKindOfClass:[NSString class]] || ![key isKindOfClass:[NSString class]] || ![label isKindOfClass:[NSString class]]) continue;
            CFPropertyListRef v = CFPreferencesCopyValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            id stored = (__bridge id)v;
            BOOL value = [stored respondsToSelector:@selector(boolValue)] ? [stored boolValue] : [item[@"default"] respondsToSelector:@selector(boolValue)] && [item[@"default"] boolValue];
            if (v) CFRelease(v);
            if ([item[@"msbInvert"] boolValue]) value = !value;
            if (value && ![on containsObject:label]) [on addObject:label];
        }
    }
    return on;
}
// Mac Lock Screen (1.8.9, F49; design 3.4 5): on or not, and the parts SpringBoard left to another modification -- part labels only, never a
// name (macsettings/MacLockScreen.x writes the state file; common/MacLockCoexist.h MLPartKey has the labels). nil while it is off.
static inline NSString *MSBDMacLockReportLine(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), CFSTR("com.besiktasliseba.maclockscreen"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    if (!on) return nil;
    NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-LockParts.plist"];
    NSDictionary *h = [st isKindOfClass:[NSDictionary class]] && [st[@"handled"] isKindOfClass:[NSDictionary class]] ? st[@"handled"] : nil;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in @[@"clock", @"background", @"cards", @"user", @"pair"]) if ([h[k] respondsToSelector:@selector(boolValue)] && [h[k] boolValue]) [parts addObject:k];
    return [NSString stringWithFormat:@"- Mac Lock Screen: on%@\n", parts.count ? [@"; left to another tweak: " stringByAppendingString:[parts componentsJoinedByString:@", "]] : @""];
}
// For testers on an untested iPadOS version: the exact version, "Enable Anyway", and our switches that are on (names only, at most `maxChars`).
static inline NSString *MSBDReportTesterInfo(NSUInteger maxChars) {
    if (MSBDVersionTested()) return nil;
    NSString *names = [MSBDSwitchesOn() componentsJoinedByString:@", "];
    if (names.length > maxChars) names = [[names substringToIndex:maxChars] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"- Untested iPadOS %@, Enable Anyway: %@\n- Switches on: %@\n", MSBDExplainOSVersion(), MSBDUntestedOptIn() ? @"On" : @"Off", names.length ? names : @"none"];
}
// The Report a Problem link: a new GitHub issue, its text filled in with what helps and nothing personal. engine: the window engine's key.
static inline NSURL *MSBDReportProblemURL(NSString *engine) {
    NSDictionary *names = @{@"aerial": @"Aerial", @"milkyway": @"MilkyWay4", @"zetsu": @"Zetsu"};
    NSString *name = names[engine] ?: engine ?: @"none";
    NSString *enginePkg = names[engine] ? MSBDPackageOwning([NSString stringWithFormat:@"/var/jb/Library/MobileSubstrate/DynamicLibraries/%@.dylib", name]) : nil;
    NSString *engineVersion = enginePkg ? MSBDPackageVersion(enginePkg) : nil;
    // (1.8.8.2, GitHub #17: the Mac pointer's state as MacPointer in pointeruid and SpringBoard said it, in a few words: drawing, standing aside for
    //  another pointer with the file name of the library that changes the pointer, not running, parts of this iPadOS's pointer not found;
    //  common/MacPointerStatus.h)
    NSString *pointer = MSBDMPReportWords(MSBDMPStyleMac(), MSBDMPReadState(MSBD_MP_STATUS), MSBDMPReadState(MSBD_MP_PROCESS), MSBDMPOtherName());
    NSString *base = [NSString stringWithFormat:@"**What happened** (which app, and what it did):\n\n\n**Steps to reproduce:**\n1. \n\n---\n- Device: %@\n- iPadOS: %@\n- Window engine: %@ %@\n- MacStatusBar&Dock: %@\n- Mac pointer: %@\n",
        MSBDExplainMachine(), MSBDExplainOSVersion(), name, engineVersion ?: ([engine isEqualToString:@"stagemanager"] ? [NSString stringWithFormat:@"(build %@)", MSBDOSBuild() ?: @"?"] : @"(version unknown)"),
        MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock") ?: @"(unknown)", pointer];
    // GitHub's new-issue link must stay a few KB: the longest parts shrink until it fits.
    NSURL *url = nil;
    NSUInteger frames[] = {5, 3, 3, 0}, chars[] = {900, 600, 300, 80};   // (a middle step: the diagnostics no longer drop straight to 300, logic test 1.2.2)
    NSUInteger recent[] = {5, 3, 2, 0}, recentChars[] = {200, 120, 60, 0};   // (1.8.7.7: the crashes of the last 24 h)
    for (int i = 0; i < 4; i++) {
        NSMutableString *body = [base mutableCopy];
        // (Stage Manager on every iPadOS 16+ iPad, whatever the engine: whether this iPad has it and, if so, the engine's check on this build with the
        //  exact rows that failed -- a report then says why the Window Engine list greys it; issue #2 asked for the verdict, a 16.3.1 report for the why)
        NSString *sm = MSBDStageManagerReportLine(chars[i]);
        if (sm) [body appendString:sm];
        NSString *macLock = MSBDMacLockReportLine();
        if (macLock) [body appendString:macLock];
        NSString *tester = MSBDReportTesterInfo(chars[i]);
        if (tester) [body appendString:tester];
        NSString *summary = MSBDReportCrashSummary(frames[i]);
        if (summary) [body appendString:summary];
        NSString *crashes = MSBDReportRecentCrashes(recent[i], recentChars[i]);
        if (crashes) [body appendString:crashes];
        NSString *diag = MSBDDiagText(chars[i]);   // (untested iPadOS only: what our parts found on this iOS, common/Diag.h)
        if (diag) [body appendString:diag];
        NSURLComponents *c = [NSURLComponents componentsWithString:MSBD_REPORT_URL];
        c.queryItems = @[[NSURLQueryItem queryItemWithName:@"body" value:body]];
        // (NSURLComponents leaves "+" as it is, and GitHub reads a "+" in the query as a space: "1.0.0-50+debug", "MacStatusBarCore.dylib + 0x4d2")
        c.percentEncodedQuery = [c.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
        url = c.URL;
        if (url.absoluteString.length <= 6000) break;
    }
    return url;
}

// ---- The note about the last SpringBoard crash ---------------------------------------------------------------------------------------------------
// The latest SpringBoard crash the guard judged (its verdict file); if it is under 24 h old and was another tweak's, that tweak's name.
static inline NSString *MSBDOtherTweakCrashName(BOOL *stuck) {
    if (stuck) *stuck = NO;
    NSDictionary *latest = MSBDJudgedCrashes(86400).firstObject;
    if ([latest[@"verdict"] intValue] != kMSBDVerdictOther) return nil;
    NSString *blamed = latest[@"blamed"];
    if (stuck) *stuck = [blamed hasPrefix:@"watchdog:"];   // (SpringBoard stuck in that tweak's code, restarted by the system -- not a crash)
    if ([blamed hasPrefix:@"watchdog:"]) blamed = [blamed substringFromIndex:9];
    NSRange r = [blamed rangeOfString:@"_(" options:NSBackwardsSearch];
    NSString *path = r.location == NSNotFound ? blamed : [blamed substringToIndex:r.location];
    if (!path.length) return nil;
    // (looked up once per crash: the name is kept with what was blamed)
    NSString *cached = [NSString stringWithContentsOfFile:@MSBD_TWEAKNAME_CACHE encoding:NSUTF8StringEncoding error:nil];
    NSArray *c = [cached componentsSeparatedByString:@"\t"];
    if (c.count == 2 && [c[0] isEqualToString:path]) return [c[1] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *name = MSBDPackageNameOwning(path);
    if (!name.length) { name = path.lastPathComponent; if ([name hasSuffix:@".dylib"]) name = [name substringToIndex:name.length - 6]; }
    name = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    [[NSString stringWithFormat:@"%@\t%@\n", path, name] writeToFile:@MSBD_TWEAKNAME_CACHE atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return name;
}
// The quiet line at the bottom of the Status Bar page, for the last SpringBoard crash (24 h): another tweak's (its name), or (1.8.7.7, #14) one that
// could not be pinned on us or anyone -- only Apple code on its stacks, other tweaks loaded -- with its cause. nil: nothing to say.
static inline NSString *MSBDOtherTweakCrashNote(void) {
    MSBDCauseTrim();   // (the death record kept short: Settings' turn, CrashBlame.h)
    BOOL stuck = NO;
    NSString *name = MSBDOtherTweakCrashName(&stuck);
    if (name.length) return stuck ? [NSString stringWithFormat:@"SpringBoard last got stuck in “%@” and was restarted by the system.", name] : [NSString stringWithFormat:@"The last SpringBoard crash came from “%@”.", name];
    NSDictionary *latest = MSBDJudgedCrashes(86400).firstObject;
    if ([latest[@"verdict"] intValue] != kMSBDVerdictUnpinned) return nil;
    NSString *cause = MSBDReportSanitize(latest[@"cause"], 200);
    while ([cause hasSuffix:@"."]) cause = [cause substringToIndex:cause.length - 1];   // (the sentence ends with its own full stop)
    NSString *stop = [cause hasSuffix:@"…"] ? @"" : @".";
    if ([latest[@"blamed"] hasPrefix:@"watchdog:"]) return cause.length ? [NSString stringWithFormat:@"SpringBoard last got stuck and the system restarted it; that could not be pinned on MacStatusBar&Dock or another tweak: %@%@", cause, stop]
                                                                         : @"SpringBoard last got stuck and the system restarted it; that could not be pinned on MacStatusBar&Dock or another tweak.";
    return cause.length ? [NSString stringWithFormat:@"The last SpringBoard crash could not be pinned on MacStatusBar&Dock or another tweak: %@%@", cause, stop]
                        : @"The last SpringBoard crash could not be pinned on MacStatusBar&Dock or another tweak.";
}
