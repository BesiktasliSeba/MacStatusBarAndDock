// CrashBlameHelper.m -- MacCrashBlame.dylib, in /var/jb/usr/lib/MacStatusBarAndDock (never loaded as a part). The crash guard (common/CrashGuard.h,
// plain C in the loaders) opens it only when it has to judge a SpringBoard crash report, and asks: was it ours? (common/CrashBlame.h)
#import "../common/CrashBlame.h"
// (1.8.7.7) A text for a C buffer of n bytes: cut at a whole character, never inside one (the guard's files are read as UTF-8 by Settings).
static void MSBDHelperCopy(char *out, size_t n, NSString *s) {
    if (!out || !n) return;
    s = s ?: @"";
    while (s.length && [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= n) s = [s substringToIndex:[s rangeOfComposedCharacterSequenceAtIndex:s.length - 1].location];
    strlcpy(out, s.UTF8String ?: "", n);
}
#ifndef MSBD_CRASHMAP   // (= CrashStep.h; overridable for the Mac test)
#define MSBD_CRASHMAP "/var/jb/usr/lib/MacStatusBarAndDock/CrashMap.txt"
#endif

// Returns the verdict (kMSBDBlame...: 4, UNPINNED, since 1.8.7.7); `blamed` (n bytes) gets a short description of what was blamed. The crash map
// names our pass-through hooks. 1.8.7.7 (GitHub #14): the exception's reason our death record kept for that SpringBoard (common/CrashCause.h) is
// read for our names too, and an Apple-only crash is UNPINNED when the report shows another tweak, or (only when it shows none) another tweak is
// installed for SpringBoard (CrashBlame.h MSBDBlameOthersInstalled). `cause` (cn bytes; NULL: not wanted) gets "<cause>\t<where>\t<n> <names>"
// (CrashBlame.h MSBDBlameCauseText, MSBDBlameWhere; the other tweaks the report shows, else those the verdict found installed).
__attribute__((visibility("default"))) int MSBDCrashJudge(const char *path, char *blamed, size_t n, char *cause, size_t cn) {
    @autoreleasepool {
        NSString *what = @"unreadable", *line = @"\t\t0";
        int verdict = kMSBDBlameUnknown;
        NSString *p = path ? [NSString stringWithUTF8String:path] : nil;
        NSDictionary *attrs = p ? [[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil] : nil;
        if (attrs && [attrs fileSize] > 0 && [attrs fileSize] <= MSBD_BLAME_MAX_BYTES) {
            NSString *map = [NSString stringWithContentsOfFile:@MSBD_CRASHMAP encoding:NSUTF8StringEncoding error:nil];
            NSDictionary *body = MSBDBlameBodyFromData([NSData dataWithContentsOfFile:p options:NSDataReadingUncached error:nil]);
            MSBDCauseTrim();
            NSArray<NSString *> *death = MSBDCauseLineFor(body), *others = nil;
            verdict = MSBDBlameReportBodyFull(body, map, death.count >= 6 ? death[4] : nil, ^NSArray<NSString *> *{ return MSBDBlameOthersInstalled(); }, &what, &others);
            if (!others.count) others = MSBDBlameOthersInReport(body);
            if (body) line = [NSString stringWithFormat:@"%@\t%@\t%lu %@", MSBDBlameCauseText(body, death), MSBDBlameWhere(body), (unsigned long)others.count, MSBDCauseOneLine([others componentsJoinedByString:@", "], MSBD_OTHERS_BYTES)];
        } else if (attrs) what = @"too large or empty";
        MSBDHelperCopy(blamed, n, what);
        MSBDHelperCopy(cause, cn, line);
        return verdict;
    }
}
__attribute__((visibility("default"))) int MSBDCrashBlame(const char *path, char *blamed, size_t n) { return MSBDCrashJudge(path, blamed, n, NULL, 0); }
// (Review of 1.8.7.7) A cause (the first part of MSBDCrashJudge's line) again, 8 s after SpringBoard's start, when every tweak has loaded: 1, and
// `out` (n bytes) the cause with " (that class is in <library>)", if the class it names is now found in another tweak's library or ours (at the
// start a tweak that loads after ours was not there yet: CrashGuard.h MSBDGuardClassLook); else 0.
__attribute__((visibility("default"))) int MSBDCrashCauseClass(const char *cause, char *out, size_t n) {
    @autoreleasepool {
        if (out && n) out[0] = 0;
        NSString *c = cause ? [NSString stringWithUTF8String:cause] : nil;
        if (!c.length || !out || !n || [c containsString:@"(that class is in "]) return 0;
        NSString *lib = MSBDCauseClassLibrary(c);
        if (!lib.length) return 0;
        MSBDHelperCopy(out, n, MSBDCauseWithLibrary(c, lib));
        return 1;
    }
}

// Only when the crash guard acted: the top frames (at most 5) of our images on that report's crashing stack, one per line (CrashBlame.h,
// MSBDBlameOurFrames: our image, symbol and offset only). Returns how many.
__attribute__((visibility("default"))) int MSBDCrashFrames(const char *path, char *out, size_t n) {
    @autoreleasepool {
        if (out && n) out[0] = 0;
        if (!path || !out || !n) return 0;
        NSString *p = [NSString stringWithUTF8String:path] ?: @"";
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil];
        if (!attrs || [attrs fileSize] == 0 || [attrs fileSize] > MSBD_BLAME_MAX_BYTES) return 0;
        NSArray<NSString *> *frames = MSBDBlameOurFrames(MSBDBlameBodyFromData([NSData dataWithContentsOfFile:p options:NSDataReadingUncached error:nil]), 5);
        NSMutableArray *clean = [NSMutableArray array];
        for (NSString *f in frames) [clean addObject:[[f componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "]];
        strlcpy(out, [clean componentsJoinedByString:@"\n"].UTF8String ?: "", n);
        return (int)clean.count;
    }
}

// The crash guard (CrashGuard.h MSBDGuardReportPid, 1.8.7.5): the pid of the SpringBoard a report tells about, its body's "pid" (a watchdog report
// has it too, before its stackshot is reshaped); -1 if the report cannot be read or names none.
__attribute__((visibility("default"))) int MSBDCrashPid(const char *path) {
    @autoreleasepool {
        NSString *p = path ? [NSString stringWithUTF8String:path] : nil;
        NSDictionary *attrs = p ? [[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil] : nil;
        if (!attrs || [attrs fileSize] == 0 || [attrs fileSize] > MSBD_BLAME_MAX_BYTES) return -1;
        id pid = MSBDBlameBodyFromDataRaw([NSData dataWithContentsOfFile:p options:NSDataReadingUncached error:nil])[@"pid"];
        return [pid isKindOfClass:[NSNumber class]] && [pid intValue] > 0 ? [pid intValue] : -1;
    }
}

// Test builds' "crashothers" trigger (1.8.7.7, StatusBar.x, device row D2): the tweaks installed for SpringBoard as the verdict sees them
// (CrashBlame.h MSBDBlameOthersInstalled), comma-separated in `out`; returns how many.
__attribute__((visibility("default"))) int MSBDCrashOthers(char *out, size_t n) {
    @autoreleasepool {
        NSArray<NSString *> *o = MSBDBlameOthersInstalled();
        if (out && n) strlcpy(out, [o componentsJoinedByString:@", "].UTF8String ?: "", n);
        return (int)o.count;
    }
}
