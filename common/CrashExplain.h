// CrashExplain.h -- the crash guard explains itself (MacStatusBar&Dock, 2026-09-26). Foundation only: used by the Status Bar and Dock pages
// (LineSwitch.h) and by the one-time notice in SpringBoard (loader/CrashNotice.m).
//  - the plain words for what the guard did and why, from its record (CrashGuard.h, MSBD_GUARD_RECORD): the pages' footer and the notice;
//  - the Report a Problem text (a GitHub new-issue link): the usual lines, plus a short crash summary while a guard record is under 7 days old
//    (which part of ours was on the crashing stack, the versions, what the guard did, the top frames of OUR image only), plus, on an untested
//    iPadOS version, the exact version, "Enable Anyway" and the names of our switches that are on. Nothing leaves the device unless the user
//    submits the issue on GitHub;
//  - the quiet note on the Status Bar page when the last SpringBoard crash (24 h) was another tweak's: its package's name from dpkg's lists.
// Cost: none unless a guard record or a verdict of another tweak's crash exists (a failed open of a small file).
#pragma once
#include "Diag.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#include "CrashGuard.h"

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
#define MSBD_EXPLAIN_DOMAIN CFSTR("com.besiktasliseba.macstatusbaranddock")

// ---- The guard's record ------------------------------------------------------------------------------------------------------------------------
// Keys: time, action, tested, verdict (NSNumber); ios, build, blamed (NSString); switches (array of @[domain, key, title]); frames (NSString array);
// shown (the notice was shown), loads (times the notice was loaded). nil if there is none.
static inline NSDictionary *MSBDCrashRecord(void) {
    NSString *text = [NSString stringWithContentsOfFile:@MSBD_GUARD_RECORD encoding:NSUTF8StringEncoding error:nil];
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
// The row titles of the switches the guard turned off (its record, when it matches `action`).
static inline NSArray<NSString *> *MSBDGuardSwitchTitles(NSDictionary *record, int action) {
    NSMutableArray *titles = [NSMutableArray array];
    if ([record[@"action"] intValue] != action) return titles;
    for (NSArray *s in record[@"switches"]) {
        NSString *t = s[2];
        if (t.length && ![titles containsObject:t]) [titles addObject:t];
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

// Step 1b (action 4, CrashStep.h): what went off, from the record: its sentence ("SpringBoard crashed twice in the Dock, so MacDock was turned off
// for now."), whether a part is no longer loaded (then "Turn Back On" brings it back), whether only Stock status bar mode was switched on.
static inline BOOL MSBDStepIsStockBar(NSArray *feature) { return [feature[1] isEqualToString:@"stockStatusBar"] && [feature[2] intValue] == 1; }
static inline NSString *MSBDStepSentence(NSDictionary *record) {
    NSMutableArray *wheres = [NSMutableArray array], *clauses = [NSMutableArray array];
    for (NSArray *f in record[@"features"]) {
        if (![wheres containsObject:f[4]]) [wheres addObject:f[4]];
        [clauses addObject:MSBDStepIsStockBar(f) ? @"the stock status bar is used for now"
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
static inline BOOL MSBDStepPartsOff(NSDictionary *record) { return [record[@"action"] intValue] == 4 && [record[@"parts"] count] > 0; }
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
        NSArray *titles = MSBDGuardSwitchTitles(MSBDCrashRecord(), 1);
        NSString *what = MSBDGuardUntitledSwitch(MSBDCrashRecord(), 1) ? @"The settings you changed last were undone after SpringBoard crashed twice."
            : titles.count
            ? [NSString stringWithFormat:@"SpringBoard crashed twice after %@ %@ turned on, so %@ turned off.", MSBDQuotedList(titles), titles.count > 1 ? @"were" : @"was", titles.count > 1 ? @"they were" : @"it was"]
            : @"The features you turned on last were turned off after SpringBoard crashed twice.";
        return [what stringByAppendingString:forAlert ? @" If this keeps happening, tap Report a Problem in Settings." : @" If this keeps happening, tap Report a Problem."];
    }
    NSString *what = action == 3 ? @"MacStatusBar&Dock was turned off because SpringBoard kept crashing." : @"MacStatusBar&Dock was turned off after SpringBoard crashed twice.";
    if (untested) return [what stringByAppendingString:forAlert ? @" To try again, turn on Enable Anyway in Settings." : @" Turn on Enable Anyway to try again, or tap Report a Problem."];
    return [what stringByAppendingString:forAlert ? @" To try again, tap Turn Back On in Settings." : @" Tap Turn Back On to try again, or Report a Problem."];
}
static inline NSString *MSBDGuardAlertTitle(int action) {
    if (action == 4) {
        NSDictionary *r = MSBDCrashRecord();
        if (MSBDStepOnlyStockBar(r)) return @"Stock Status Bar in Use";
        return [r[@"features"] count] + [r[@"parts"] count] > 1 ? @"Features Turned Off" : @"Feature Turned Off";
    }
    if (action != 1) return @"MacStatusBar&Dock Turned Off";
    if (MSBDGuardUntitledSwitch(MSBDCrashRecord(), 1)) return @"Settings Undone";
    return MSBDGuardSwitchTitles(MSBDCrashRecord(), 1).count > 1 ? @"Features Turned Off" : @"Feature Turned Off";
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
static inline NSString *MSBDPackageField(NSString *package, NSString *field) {   // from dpkg's status file (readable by everyone)
    NSString *status = [NSString stringWithContentsOfFile:@MSBD_DPKG_DIR "/status" encoding:NSUTF8StringEncoding error:nil];
    NSString *head = [NSString stringWithFormat:@"Package: %@\n", package], *want = [field stringByAppendingString:@": "];
    for (NSString *block in [status componentsSeparatedByString:@"\n\n"]) {
        NSString *b = [block stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        if (![[b stringByAppendingString:@"\n"] hasPrefix:head]) continue;
        for (NSString *line in [b componentsSeparatedByString:@"\n"]) if ([line hasPrefix:want]) return [line substringFromIndex:want.length];
    }
    return nil;
}
static inline NSString *MSBDPackageVersion(NSString *package) { return MSBDPackageField(package, @"Version"); }
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
    if (verdict == kMSBDVerdictApple) return watchdog ? @"none of ours: SpringBoard was stuck in Apple code and the system restarted it" : @"none of ours on the crashing stack (Apple code only)";
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
        return titles.count ? [NSString stringWithFormat:@"turned off %@", MSBDQuotedList(titles)] : @"turned off the switches turned on last";
    }
    if (action == 4) {   // (step 1b: "turned off “Mac-Style Banners”", "switched to the stock status bar", "stopped loading MacDock (DockMagnification)")
        NSMutableArray *done = [NSMutableArray array];
        for (NSArray *f in record[@"features"])
            [done addObject:MSBDStepIsStockBar(f) ? @"switched to the stock status bar" : [NSString stringWithFormat:@"turned %@ “%@”", [f[2] intValue] ? @"on" : @"off", f[3]]];
        for (NSArray *p in record[@"parts"]) [done addObject:[NSString stringWithFormat:@"stopped loading %@ (%@)", p[2], p[0]]];
        return [NSString stringWithFormat:@"%@ (only what crashed)", done.count ? [done componentsJoinedByString:@", "] : @"turned off what crashed"];
    }
    NSString *off = [record[@"tested"] intValue] ? @"turned MacStatusBar&Dock off (safe mode)" : @"switched Enable Anyway off";
    return action == 3 ? [off stringByAppendingString:@" after more crashes"] : off;
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
    [s appendFormat:@"- At the time: iPadOS %@%@, %@, build %@\n", r[@"ios"] ?: @"?", [r[@"tested"] intValue] ? @"" : @" (untested)", MSBDExplainMachine(), r[@"build"] ?: @"?"];
    NSArray *frames = r[@"frames"];
    if (frames.count && maxFrames) {
        [s appendString:@"- Top frames (ours only):\n```\n"];
        for (NSUInteger i = 0; i < frames.count && i < maxFrames; i++) [s appendFormat:@"%@\n", frames[i]];
        [s appendString:@"```\n"];
    }
    return s;
}
// Our switches on the Status Bar and Dock pages that are on (their row titles), read from the pages' own lists.
static inline NSArray<NSString *> *MSBDSwitchesOn(void) {
    NSMutableArray *on = [NSMutableArray array];
    for (NSString *bundle in @[@"MacStatusBarPrefs", @"DockMagnificationPrefs"]) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%s/%@.bundle/Root.plist", MSBD_PREF_BUNDLES, bundle]];
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
    NSString *base = [NSString stringWithFormat:@"**What happened** (which app, and what it did):\n\n\n**Steps to reproduce:**\n1. \n\n---\n- Device: %@\n- iPadOS: %@\n- Window engine: %@ %@\n- MacStatusBar&Dock: %@\n",
        MSBDExplainMachine(), MSBDExplainOSVersion(), name, engineVersion ?: @"(version unknown)", MSBDPackageVersion(@"com.besiktasliseba.macstatusbaranddock") ?: @"(unknown)"];
    // GitHub's new-issue link must stay a few KB: the longest parts shrink until it fits.
    NSURL *url = nil;
    NSUInteger frames[] = {5, 3, 0}, chars[] = {900, 300, 80};
    for (int i = 0; i < 3; i++) {
        NSMutableString *body = [base mutableCopy];
        NSString *tester = MSBDReportTesterInfo(chars[i]);
        if (tester) [body appendString:tester];
        NSString *summary = MSBDReportCrashSummary(frames[i]);
        if (summary) [body appendString:summary];
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

// ---- The note about another tweak's crash ------------------------------------------------------------------------------------------------------
// The latest SpringBoard crash the guard judged (its verdict file); if it is under 24 h old and was another tweak's, that tweak's name.
static inline NSString *MSBDOtherTweakCrashName(BOOL *stuck) {
    if (stuck) *stuck = NO;
    NSString *text = [NSString stringWithContentsOfFile:@MSBD_GUARD_VERDICTS encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return nil;
    NSString *latest = nil, *latestLine = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray *p = [line componentsSeparatedByString:@" "];
        if (p.count < 3 || ![p[0] hasPrefix:@"SpringBoard-"] || [p[0] length] < 29) continue;
        NSString *stamp = [p[0] substringWithRange:NSMakeRange(12, 17)];   // yyyy-MM-dd-HHmmss
        if (!latest || [stamp compare:latest] != NSOrderedAscending) { latest = stamp; latestLine = line; }
    }
    if (!latestLine) return nil;
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; df.dateFormat = @"yyyy-MM-dd-HHmmss";
    NSDate *when = [df dateFromString:latest];
    NSTimeInterval age = when ? -[when timeIntervalSinceNow] : 1e9;
    NSArray *p = [latestLine componentsSeparatedByString:@" "];
    if (age < -300 || age > 86400 || [p[1] intValue] != kMSBDVerdictOther) return nil;
    NSString *blamed = [[p subarrayWithRange:NSMakeRange(2, p.count - 2)] componentsJoinedByString:@" "];
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
static inline NSString *MSBDOtherTweakCrashNote(void) {
    BOOL stuck = NO;
    NSString *name = MSBDOtherTweakCrashName(&stuck);
    if (!name.length) return nil;
    return stuck ? [NSString stringWithFormat:@"SpringBoard last got stuck in “%@” and was restarted by the system.", name] : [NSString stringWithFormat:@"The last SpringBoard crash came from “%@”.", name];
}
