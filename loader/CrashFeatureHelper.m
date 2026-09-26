// CrashFeatureHelper.m -- the second question MacCrashBlame.dylib answers for the crash guard (common/CrashStep.h, step 1b): which feature or part
// of ours did this crash come from, and what turns it off? (common/CrashFeature.h)
#import "../common/CrashFeature.h"

// Returns 1 and puts "pref <image> <domain> <key> <value>" or "part <image> - - -" into `action`; 0 and the reason otherwise. `detail` gets where
// the crash was found (image + offset, which stack, map or fallback), for the log.
__attribute__((visibility("default"))) int MSBDCrashFeature(const char *report, const char *mapPath, char *action, size_t an, char *detail, size_t dn) {
    @autoreleasepool {
        NSString *a = @"unreadable", *d = @"";
        int ok = 0;
        NSString *path = report ? [NSString stringWithUTF8String:report] : nil;
        NSDictionary *attrs = path ? [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] : nil;
        if (attrs && [attrs fileSize] > 0 && [attrs fileSize] <= MSBD_BLAME_MAX_BYTES) {
            NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:nil];
            NSString *map = mapPath ? [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:mapPath] encoding:NSUTF8StringEncoding error:nil] : nil;
            ok = MSBDFeatureForReport(data, map, &a, &d);
        }
        if (action && an) strlcpy(action, a.UTF8String ?: "", an);
        if (detail && dn) strlcpy(detail, d.UTF8String ?: "", dn);
        return ok;
    }
}
