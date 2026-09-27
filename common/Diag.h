// Diag.h -- diagnostics for untested iPadOS versions (2026-09-27): on iPadOS 17 and newer with "Enable Anyway" on, a few small text records of what our
// parts found on this iOS -- which hooked methods do not exist here (common/HookList.h) and the Dock's layout facts -- so Report a Problem can include
// them even when nothing crashed (things that silently do nothing, like the Dock's App Library icon on 18). Names and numbers only: no app names, no
// content, nothing personal. Kept on the device (only the latest state, a few KB each); sent only if the user submits a report. 15/16: never written.
#pragma once
#import <Foundation/Foundation.h>
#include "VersionGate.h"
#include <unistd.h>

#define MSBD_DIAG_PATH(name) [NSString stringWithFormat:@"/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-Diag-%@.txt", (name)]
#define MSBD_DIAG_NAMES @[@"Hooks", @"Dock"]

static inline BOOL MSBDDiagEnabled(void) {
    static int on = -1;
    if (on < 0) on = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17 && MSBDUntestedOptIn();
#if DEBUG
    if (!on && access("/tmp/msb-diag-test", F_OK) == 0) on = 1;   // (debug builds: try the diagnostics on 15/16)
#endif
    return on;
}
// Replaces the record `name` (only when the text changed; at most 3000 characters).
static inline void MSBDDiagWrite(NSString *name, NSString *text) {
    if (!MSBDDiagEnabled() || !name.length || !text) return;
    static NSMutableDictionary<NSString *, NSString *> *last;
    if (!last) last = [NSMutableDictionary dictionary];
    if ([last[name] isEqualToString:text]) return;
    last[name] = [text copy];
    NSString *t = text.length > 3000 ? [[text substringToIndex:3000] stringByAppendingString:@"\n(cut)"] : text;
    [t writeToFile:MSBD_DIAG_PATH(name) atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
// For Report a Problem: the records, each cut to `maxChars` (nil when there are none: 15/16, or nothing written yet).
static inline NSString *MSBDDiagText(NSUInteger maxChars) {
    BOOL test = NO;
#if DEBUG
    test = [[NSFileManager defaultManager] fileExistsAtPath:MSBD_DIAG_PATH(@"Hooks")];   // (debug builds on 15/16: the records a test left)
#endif
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 17 && !test) return nil;
    NSMutableString *s = [NSMutableString string];
    for (NSString *n in MSBD_DIAG_NAMES) {
        NSString *t = [NSString stringWithContentsOfFile:MSBD_DIAG_PATH(n) encoding:NSUTF8StringEncoding error:nil];
        if (!t.length) continue;
        if (t.length > maxChars) t = [[t substringToIndex:maxChars] stringByAppendingString:@"…"];
        [s appendFormat:@"- %@:\n```\n%@\n```\n", n, t];
    }
    return s.length ? [@"\n**Diagnostics** (untested iPadOS; names and numbers only)\n" stringByAppendingString:s] : nil;
}
