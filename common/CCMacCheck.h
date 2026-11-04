// CCMacCheck.h -- can our own Control Center (Control Center Style: Mac, 1.8.0) run on this iPadOS build? SpringBoard's start-up self-check
// (statusbar/CCPanel.h DMCCPCheckAPI on 15-17; statusbar/CC18Shape.h DMCC18CheckAPI on 18, where our Control Center is Apple's own 18 grid
// re-shaped into the Mac panel: every class, method, type encoding and instance variable each hooks, calls or reads) leaves its verdict in our
// preferences, as the Stage Manager engine's does (StageManagerAvailable.h): Settings greys Mac out with the reason where it did not pass (the
// Style page), Report a Problem can quote it. Before 15 and after 18 (an iPadOS whose Control Center was never read): never.
#pragma once
#import <Foundation/Foundation.h>
#include <unistd.h>
#include "StageManagerAvailable.h"   // (MSBDOSBuild: this iPadOS build, the record's key)

#define MSBD_CC_CHECK_KEY CFSTR("controlCenterMacCheck")   // (com.besiktasliseba.macstatusbar: {build, os, ok, reason, details, optional})

// The record for THIS iPadOS build, nil when SpringBoard has not checked this build (keys: build, os, ok, reason, details = the rows that failed,
// optional = the optional rows that are missing: their parts left out, the panel still runs).
static inline NSDictionary *MSBDCCMacCheckRecord(void) {
    CFStringRef domain = CFSTR("com.besiktasliseba.macstatusbar");
    CFStringRef user = getuid() == 0 ? CFSTR("mobile") : kCFPreferencesCurrentUser;   // (the root helper reads mobile's preferences)
    CFPreferencesSynchronize(domain, user, kCFPreferencesAnyHost);
    id v = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_CC_CHECK_KEY, domain, user, kCFPreferencesAnyHost);
    if (![v isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = v;
    NSString *build = MSBDOSBuild();
    if (!build.length || ![d[@"build"] isKindOfClass:[NSString class]] || ![d[@"build"] isEqualToString:build]) return nil;
    return d;
}
// 1 = our Control Center can run on this iPadOS build, 0 = it cannot (*reason: why, for Settings' footer), -1 = not checked here yet (a first
// start of this build, or SpringBoard ran without the Mac status bar).
static inline int MSBDCCMacVerdict(NSString **reason) {
    NSInteger major = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    if (major < 15 || major > 18) { if (reason) *reason = major > 18 ? [NSString stringWithFormat:@"Not supported on iPadOS %ld yet.", (long)major] : @"Needs iPadOS 15 or later."; return 0; }
    NSDictionary *d = MSBDCCMacCheckRecord();
    if (!d) return -1;
    if ([d[@"ok"] boolValue]) return 1;
    if (reason) *reason = [d[@"reason"] isKindOfClass:[NSString class]] ? d[@"reason"] : nil;
    return 0;
}
