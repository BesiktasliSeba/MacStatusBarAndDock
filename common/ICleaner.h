// ICleaner.h -- iCleaner in Finder (1.8.5 item 1): the rules Finder (statusbar/ICleanerPanel.h) and the root helper (macsettings/sshtoggled)
// share. Foundation and libc only, so the Mac test (tools/test-icleaner.sh) runs this very code.
//
// What it is: a Finder sidebar row "iCleaner", only while the official iCleaner Pro (com.exile90.icleanerpro) is installed, that opens a panel of
// ours (Clean, Clean and Respring, Respring; the space freed). It uses only iCleaner's public command line, never its interface or artwork:
//   /var/jb/Applications/iCleaner.app/iCleaner -clean -printresults
// iCleaner then cleans with the user's own iCleaner settings (what it removes is the user's choice in iCleaner) and prints, one per line:
//   success=true|false, message=<text> (when it failed), freed=<size as iCleaner writes it>, deleted=<files>, shouldrespring=true|false.
// Read on the iPad 2 (official 7.10.0, 10 Nov): the binary is setuid root (it cleans as root whoever starts it); `-cli` refuses without a
// terminal; no progress is printed, so the panel shows an indeterminate spinner until the answer.
//
// The run goes through the root helper's launchd job, as a drive's eject does (common/DriveEject.h, whose request id, answer file shape and timed
// run this reuses): iPadOS 18 refuses SpringBoard's posix_spawn of anything under /var/jb.
//  - Finder writes the request into our own preferences (kMSBDICleanRequestKey: an id, the action, when) and posts kMSBDICleanRequestName.
//  - The helper takes it away at once (no replay), accepts only what MSBDICleanRequestFrom does, checks that the official package is installed
//    and that the binary is its own (a regular root file, not a link), runs it with exactly the two arguments above, never stopping it, and writes
//    the answer line (MSBDICleanAnswerFromOutput) with the request's id into a root-owned file, then posts kMSBDICleanAnswerName.
//  - The respring is ours (Finder asks SpringBoard's relaunch, as Respring in the Apple menu does), never iCleaner's -respring. With Clean and
//    Respring the result is kept across it and shown once SpringBoard is back (1.8.8.1, at the end of this file).
#pragma once
#import <Foundation/Foundation.h>
#include "DriveEject.h"

#define kMSBDICleanPackage      @"com.exile90.icleanerpro"                       // the official package only
#define kMSBDICleanBinary       "/var/jb/Applications/iCleaner.app/iCleaner"
#define kMSBDICleanRequestKey   "icleanRequest"                                  // @{id: 32 hex digits, action: "clean", at: when}, in kMSBDEjectDomain
#define kMSBDICleanRequestName  "com.besiktasliseba.msbd.iclean.request"
#define kMSBDICleanAnswerName   "com.besiktasliseba.msbd.iclean.answered"
#define kMSBDICleanAnswerFile   "/var/jb/var/lib/sshtoggled-engines/iclean-answer"
static const double kMSBDICleanTimeout = 0.0;     // the helper never stops iCleaner (0: no limit). A clean may be removing packages through dpkg as
                                                  // root: stopped halfway, dpkg could be left half-configured (review 1.8.5-i M1)
static const double kMSBDICleanWait = 620.0;      // Finder stops waiting after this long and says iCleaner is still cleaning (it finishes on its own)
static const double kMSBDICleanRequestAge = 30.0; // a request older than this is never carried out (one left behind by a SpringBoard that went away)
#define kMSBDICleanNoHelperLine @"error: MacStatusBar&Dock’s helper isn’t running. Try again in a moment; if it keeps happening, reinstall MacStatusBar&Dock"
#define kMSBDICleanNoAnswerLine @"error: iCleaner is still cleaning. It finishes on its own; open iCleaner later to see the result"

// The request: exactly an id, the action "clean" and when it was asked (seconds since 1970, the same clock as `now`). YES: good. NO with *rid
// set: the id is good, the rest is not (*why: answered "refused", so Finder isn't left waiting). NO with *rid nil: not a request (ignored).
static inline BOOL MSBDICleanRequestFrom(id plist, NSTimeInterval now, NSString **rid, NSString **why) {
    if (rid) *rid = nil;
    if (why) *why = nil;
    if (![plist isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *d = plist;
    id i = d[@"id"], a = d[@"action"], at = d[@"at"];
    if (!MSBDEjectIsRequestID(i)) return NO;
    if (rid) *rid = i;
    if (d.count != 3 || ![a isKindOfClass:[NSString class]] || ![a isEqualToString:@"clean"] || ![at isKindOfClass:[NSNumber class]]) { if (why) *why = @"that isn't a request Finder makes"; return NO; }
    double age = now - [at doubleValue];
    if (!isfinite(age) || age < -5.0 || age > kMSBDICleanRequestAge) { if (why) *why = @"the request is too old -- try again"; return NO; }
    return YES;
}

// iCleaner's printed results as one answer line:
//   "ok freed=<size> deleted=<n> respring=<0|1>"   (a clean that succeeded; size as iCleaner wrote it, at most 40 characters)
//   "error: <iCleaner's message>"                   (success=false)
//   "error: ..."                                    (it couldn't be started, was stopped at the time limit, or printed nothing we know)
static inline NSString *MSBDICleanAnswerFromOutput(int spawnResult, NSData *output, BOOL timedOut, int status) {
    if (spawnResult < 0) return @"error: iCleaner couldn’t be started (no pipe)";
    if (spawnResult > 0) return [NSString stringWithFormat:@"error: iCleaner couldn’t be started (%d)", spawnResult];
    if (timedOut) return @"error: iCleaner didn’t finish in time and was stopped";
    NSString *out = output ? [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] : nil;
    NSMutableDictionary<NSString *, NSString *> *kv = [NSMutableDictionary dictionary];
    for (NSString *raw in [out componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *l = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSRange eq = [l rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) continue;
        NSString *k = [l substringToIndex:eq.location];
        if (![@[@"success", @"message", @"freed", @"deleted", @"shouldrespring"] containsObject:k] || kv[k]) continue;   // (the first of each)
        kv[k] = [l substringFromIndex:eq.location + 1];
    }
    NSCharacterSet *ctl = [NSCharacterSet controlCharacterSet];
    if ([kv[@"success"] isEqualToString:@"false"]) {
        NSString *m = [[kv[@"message"] componentsSeparatedByCharactersInSet:ctl] componentsJoinedByString:@" "];
        if (m.length > 300) m = [m substringToIndex:300];
        return m.length ? [@"error: " stringByAppendingString:m] : @"error: iCleaner couldn’t clean";
    }
    if (![kv[@"success"] isEqualToString:@"true"]) {
        int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        return [NSString stringWithFormat:@"error: iCleaner gave no result (exit %d)", code];
    }
    NSString *freed = [[kv[@"freed"] componentsSeparatedByCharactersInSet:ctl] componentsJoinedByString:@""] ?: @"";
    freed = [freed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (freed.length > 40 || [freed rangeOfString:@" deleted="].location != NSNotFound) freed = @"";
    long long deleted = kv[@"deleted"].length ? [kv[@"deleted"] longLongValue] : -1;
    if (deleted < -1) deleted = -1;
    BOOL respring = [kv[@"shouldrespring"] isEqualToString:@"true"];
    return [NSString stringWithFormat:@"ok freed=%@ deleted=%lld respring=%d", freed.length ? [freed stringByReplacingOccurrencesOfString:@" " withString:@" "] : @"-", deleted, respring ? 1 : 0];
}

// The answer line read back by Finder: YES for a clean that succeeded (*freed: as iCleaner wrote it, or nil; *deleted: -1 when not said;
// *respring: iCleaner says a respring is needed); NO with *error: the text after "error: " (or the whole line when it isn't one of ours).
static inline BOOL MSBDICleanParseAnswer(NSString *line, NSString **freed, long long *deleted, BOOL *respring, NSString **error) {
    if (freed) *freed = nil;
    if (deleted) *deleted = -1;
    if (respring) *respring = NO;
    if (error) *error = nil;
    if (![line isKindOfClass:[NSString class]]) { if (error) *error = @"no answer"; return NO; }
    if ([line hasPrefix:@"error: "]) { if (error) *error = [line substringFromIndex:7]; return NO; }
    if (![line hasPrefix:@"ok "]) { if (error) *error = line; return NO; }
    for (NSString *part in [[line substringFromIndex:3] componentsSeparatedByString:@" "]) {
        NSRange eq = [part rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *k = [part substringToIndex:eq.location], *v = [part substringFromIndex:eq.location + 1];
        if ([k isEqualToString:@"freed"] && freed) *freed = [v isEqualToString:@"-"] ? nil : [v stringByReplacingOccurrencesOfString:@" " withString:@" "];
        else if ([k isEqualToString:@"deleted"] && deleted) *deleted = [v longLongValue];
        else if ([k isEqualToString:@"respring"] && respring) *respring = [v isEqualToString:@"1"];
    }
    return YES;
}

// The result in a Mac's words, for the panel: "Freed 123.4 MB (5,678 files)." / "Freed 123.4 MB." / "Done.".
static inline NSString *MSBDICleanResultText(NSString *freed, long long deleted) {
    NSString *files = nil;
    if (deleted >= 0) {
        NSNumberFormatter *f = [NSNumberFormatter new]; f.numberStyle = NSNumberFormatterDecimalStyle; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        files = [NSString stringWithFormat:@"%@ %@", [f stringFromNumber:@(deleted)], deleted == 1 ? @"file" : @"files"];
    }
    if (freed.length && files) return [NSString stringWithFormat:@"Freed %@ (%@).", freed, files];
    if (freed.length) return [NSString stringWithFormat:@"Freed %@.", freed];
    if (files) return [NSString stringWithFormat:@"Removed %@.", files];
    return @"Done.";
}

// ---- Clean and Respring: the result after the respring (1.8.8.1) ------------------------------------------------------------------------------
// Clean and Respring resprang as soon as iCleaner answered, so what it freed was never seen. Now the answer line is kept in our own preferences
// (kMSBDICleanAfterKey in kMSBDEjectDomain: the line, when the respring was asked and the pid of the SpringBoard that asked it; nothing else) just
// before our respring is asked, and the SpringBoard that respring starts takes it at its first look: the key is removed then, so no SpringBoard
// ever sees it again. It is shown once, in the panel as after a Clean, when the iPad is unlocked and nothing else is up (statusbar/ICleanerPanel.h).
// A kept line is dropped, never shown, when it is not the result of that respring any more:
//  - kept more than kMSBDICleanAfterKeep ago (10 min): the iPad stayed locked all that while;
//  - read by a SpringBoard that started more than kMSBDICleanAfterStart after the respring was asked: a later start (a crash or a restart after a
//    respring that never came), not the respring's own;
//  - a SpringBoard crash report from the respring on (MSBDICleanCrashSince, looked at as it is about to be shown): SpringBoard went down again in
//    between, so it is not shown as if nothing had happened.
// The SpringBoard that asked looks once more kMSBDICleanAfterLate after asking: still running then, its respring never came, and it shows the result
// itself (with the panel's Respring button when iCleaner says one is needed, as after a Clean).
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#define kMSBDICleanAfterKey "icleanAfterRespring"     // @{line: the answer line, at: when the respring was asked, pid: the SpringBoard that asked}
static const double kMSBDICleanAfterKeep = 600.0;    // shown within 10 min of the respring, or never
static const double kMSBDICleanAfterStart = 90.0;    // the respring's SpringBoard starts within this of the ask; one that starts later is another start
static const double kMSBDICleanAfterLate = 60.0;     // the SpringBoard that asked still runs this long after: the respring never came
typedef NS_ENUM(int, MSBDICleanAfter) {
    kMSBDICleanAfterNone = 0,   // nothing kept
    kMSBDICleanAfterWait,       // kept by this SpringBoard for its respring, which is on its way: left where it is
    kMSBDICleanAfterShow,       // the result of the respring that started this SpringBoard: taken, to be shown (no Respring offered)
    kMSBDICleanAfterShowHere,   // kept by this SpringBoard, whose respring never came: taken, to be shown here
    kMSBDICleanAfterDrop,       // not shown (*why): removed
};

// The record kept just before the respring is asked (nil: nothing to keep).
static inline NSDictionary *MSBDICleanAfterRecord(NSString *line, double now, int pid) {
    if (![line isKindOfClass:[NSString class]] || !line.length || line.length > 400 || !isfinite(now) || pid <= 0) return nil;
    return @{ @"line": line, @"at": @(now), @"pid": @(pid) };
}
// A SpringBoard's look at the kept record `rec` (nil: none): `pid` and `started` (seconds since 1970) are its own, `now` the time. *line: the line
// to show (Show, ShowHere); *at: when the respring was asked; *why: why it is dropped or shown here. Anything but Wait and None removes the record.
static inline MSBDICleanAfter MSBDICleanAfterLook(id rec, int pid, double started, double now, NSString **line, double *at, NSString **why) {
    if (line) *line = nil;
    if (at) *at = 0;
    if (why) *why = nil;
    if (!rec) return kMSBDICleanAfterNone;
    NSDictionary *d = [rec isKindOfClass:[NSDictionary class]] ? rec : nil;
    id l = d[@"line"], t = d[@"at"], p = d[@"pid"];
    if (!d || d.count != 3 || ![l isKindOfClass:[NSString class]] || ![(NSString *)l length] || [(NSString *)l length] > 400
        || ![t isKindOfClass:[NSNumber class]] || !isfinite([t doubleValue]) || ![p isKindOfClass:[NSNumber class]] || [p intValue] <= 0) {
        if (why) *why = @"not a result Finder keeps";
        return kMSBDICleanAfterDrop;
    }
    double when = [t doubleValue], age = now - when;
    if (at) *at = when;
    if (!isfinite(age) || age < -5.0) { if (why) *why = @"kept later than now (the clock went back)"; return kMSBDICleanAfterDrop; }
    if (age > kMSBDICleanAfterKeep) { if (why) *why = @"kept more than 10 minutes ago"; return kMSBDICleanAfterDrop; }
    if ([p intValue] == pid && started <= when + 1.0) {   // (kept by this very SpringBoard: its respring has not come)
        if (age < kMSBDICleanAfterLate) return kMSBDICleanAfterWait;
        if (line) *line = l;
        if (why) *why = [NSString stringWithFormat:@"the respring never came (%.0f s)", age];
        return kMSBDICleanAfterShowHere;
    }
    double after = started - when;
    if (!isfinite(after) || after < -1.0) { if (why) *why = @"this SpringBoard started before the respring was asked"; return kMSBDICleanAfterDrop; }
    if (after > kMSBDICleanAfterStart) { if (why) *why = [NSString stringWithFormat:@"this SpringBoard started %.0f s after the respring was asked: another start, not the respring's", after]; return kMSBDICleanAfterDrop; }
    if (line) *line = l;
    return kMSBDICleanAfterShow;
}
// A result taken or held is still to be shown at `now` (kept at `at`): within kMSBDICleanAfterKeep.
static inline BOOL MSBDICleanAfterDue(double now, double at) {
    double age = now - at;
    return isfinite(age) && age >= -5.0 && age <= kMSBDICleanAfterKeep;
}
// A SpringBoard crash report in `dir` (CrashReporter: SpringBoard-<date>.ips, the crash guard's kind; never SpringBoard.cpu_resource-... and the
// like) for a crash at or after `since` (seconds since 1970), by the time in its name (the crash itself), else by when it was written. *name: the
// first one found (may be NULL).
static inline BOOL MSBDICleanCrashSince(const char *dir, double since, char *name, size_t n) {
    if (name && n) name[0] = 0;
    if (!dir || !isfinite(since)) return NO;
    DIR *dd = opendir(dir);
    if (!dd) return NO;
    BOOL found = NO;
    struct dirent *e;
    while (!found && (e = readdir(dd))) {
        if (strncmp(e->d_name, "SpringBoard-", 12) != 0 || !strstr(e->d_name, ".ips")) continue;
        struct tm tm; memset(&tm, 0, sizeof(tm));
        long t = 0;
        if (sscanf(e->d_name + 12, "%4d-%2d-%2d-%2d%2d%2d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec) == 6) {
            tm.tm_year -= 1900; tm.tm_mon -= 1; tm.tm_isdst = -1;
            t = (long)mktime(&tm);
        } else {
            char p[1024]; struct stat st;
            snprintf(p, sizeof(p), "%s/%s", dir, e->d_name);
            t = stat(p, &st) == 0 ? (long)st.st_mtime : 0;
        }
        if (t >= (long)floor(since)) { found = YES; if (name && n) snprintf(name, n, "%s", e->d_name); }
    }
    closedir(dd);
    return found;
}
