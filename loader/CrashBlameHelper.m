// CrashBlameHelper.m -- MacCrashBlame.dylib, in /var/jb/usr/lib/MacStatusBarAndDock (never loaded as a part). The crash guard (common/CrashGuard.h,
// plain C in the loaders) opens it only when it has to judge a SpringBoard crash report, and asks: was it ours? (common/CrashBlame.h)
#import "../common/CrashBlame.h"
#ifndef MSBD_CRASHMAP   // (= CrashStep.h; overridable for the Mac test)
#define MSBD_CRASHMAP "/var/jb/usr/lib/MacStatusBarAndDock/CrashMap.txt"
#endif

// Returns the verdict (kMSBDBlame...); `blamed` (n bytes) gets a short description of what was blamed. The crash map names our pass-through hooks.
__attribute__((visibility("default"))) int MSBDCrashBlame(const char *path, char *blamed, size_t n) {
    @autoreleasepool {
        NSString *what = @"unreadable";
        int verdict = kMSBDBlameUnknown;
        NSString *p = path ? [NSString stringWithUTF8String:path] : nil;
        NSDictionary *attrs = p ? [[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil] : nil;
        if (attrs && [attrs fileSize] > 0 && [attrs fileSize] <= MSBD_BLAME_MAX_BYTES) {
            NSString *map = [NSString stringWithContentsOfFile:@MSBD_CRASHMAP encoding:NSUTF8StringEncoding error:nil];
            verdict = MSBDBlameReportBodyMap(MSBDBlameBodyFromData([NSData dataWithContentsOfFile:p options:NSDataReadingUncached error:nil]), map, &what);
        } else if (attrs) what = @"too large or empty";
        if (blamed && n) strlcpy(blamed, what.UTF8String ?: "", n);
        return verdict;
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
