// DesktopCheck.h -- the desktop's iPadOS 17+ check, for Settings (2026-10-03). On an untested iPadOS (17+, "Enable Anyway") SpringBoard checks once
// per start, when the desktop is first wanted, that the Home Screen parts the desktop uses are there (statusbar/Desktop.h, DMDesktopNewOSReady),
// and keeps the verdict for this iPadOS build. Settings offers "Show Desktop Icons" on 17+ unless that check failed on this build. 15/16: never
// written, never read. Objective-C (Foundation).
#pragma once
#import <Foundation/Foundation.h>
#include <unistd.h>
#include "StageManagerAvailable.h"   // (MSBDOSBuild)

#define MSBD_DESKTOP_CHECK_KEY CFSTR("desktopCheck")
// 1 = checked and ready on this iPadOS build, 0 = a part it needs is missing here (*reason: which), -1 = not checked on this build.
static inline int MSBDDesktopVerdict(NSString **reason) {
    CFStringRef domain = CFSTR("com.besiktasliseba.macstatusbar");
    CFStringRef user = getuid() == 0 ? CFSTR("mobile") : kCFPreferencesCurrentUser;
    CFPreferencesSynchronize(domain, user, kCFPreferencesAnyHost);
    id v = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_DESKTOP_CHECK_KEY, domain, user, kCFPreferencesAnyHost);
    if (![v isKindOfClass:[NSDictionary class]]) return -1;
    NSDictionary *d = v;
    NSString *build = MSBDOSBuild();
    if (!build.length || ![d[@"build"] isKindOfClass:[NSString class]] || ![d[@"build"] isEqualToString:build]) return -1;
    if ([d[@"ok"] boolValue]) return 1;
    if (reason) *reason = [d[@"reason"] isKindOfClass:[NSString class]] ? d[@"reason"] : nil;
    return 0;
}
