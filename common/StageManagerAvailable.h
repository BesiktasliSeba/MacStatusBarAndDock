// StageManagerAvailable.h -- whether this iPad can run Apple's Stage Manager, i.e. whether the Stage Manager window engine can be offered (2026-09-29).
// One test for Settings (the engine picker), the root helper (Stage Manager as the default engine on a first install) and SpringBoard (the one-time
// "Stage Manager is now a window engine" notice). Objective-C (Foundation).
#pragma once
#import <Foundation/Foundation.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <unistd.h>
// iPadOS 16 or later, and either TrollPad (which switches Stage Manager on for older iPads) or a model Apple ships it on.
static inline BOOL MSBDStageManagerTrollPad(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib/TweakInject/TrollPadSB.dylib"];
}
static inline BOOL MSBDStageManagerHardware(void) {
    // The iPads with Stage Manager (logic test C2: "every iPad13,/iPad14," also offered it on the iPad Air 4, iPad 10 and iPad mini 6, which have
    // none -- picking it there left no windowing at all): iPad Pro 2018/2020 (iPad8,x) from iPadOS 16.1, iPad Pro 2021 (iPad13,4-11), iPad Air 5
    // (iPad13,16-17), iPad Pro 2022 (iPad14,3-6), iPad Air M2 (iPad14,8-11) and later models (iPad15,/16,).
    char m[64] = ""; size_t n = sizeof(m);
    if (sysctlbyname("hw.machine", m, &n, NULL, 0) != 0) return NO;
    int major = 0, minor = 0;
    if (sscanf(m, "iPad%d,%d", &major, &minor) != 2) return NO;
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    if (major == 8) return v.majorVersion > 16 || v.minorVersion >= 1;
    if (major == 13) return (minor >= 4 && minor <= 11) || minor == 16 || minor == 17;
    if (major == 14) return (minor >= 3 && minor <= 6) || (minor >= 8 && minor <= 11);
    return major >= 15;
}
static inline BOOL MSBDStageManagerAvailable(void) {
    // (iPadOS 16.1 or later on every iPad, TrollPad too: 16.0 -- 20A8372, the M2 iPad Pro and iPad 10 factory build -- has Stage Manager switched
    //  off by Apple, and where it was switched on by hand the engine crashed SpringBoard; its API differs from 16.1 on, issue #2)
    NSOperatingSystemVersion ov = [NSProcessInfo processInfo].operatingSystemVersion;
    if (ov.majorVersion < 16 || (ov.majorVersion == 16 && ov.minorVersion < 1)) return NO;
    return MSBDStageManagerTrollPad() || MSBDStageManagerHardware();
}
// ---- the Stage Manager engine's self-check verdict (2026-09-29) ----
// SpringBoard checks, once at every start, that every private class, method and signature the engine uses is there as on the versions it was
// built on (statusbar/SMEngineAPI.h, DMSMSelfCheck), and publishes the result here, for this iPadOS build. The root helper (which engine loads)
// and Settings (the Window Engine list) read it: a failed check means the engine is not offered, and the default engine runs instead -- the
// same as an iPad without Stage Manager. Not checked yet on this build (e.g. right after an iPadOS update): not offered until SpringBoard has looked
// (it checks at every start, with the stock status bar too) -- "not checked" counted as usable until 1.1.6, issue #2.
#define MSBD_SM_CHECK_KEY CFSTR("stageManagerEngineCheck")
static inline NSString *MSBDOSBuild(void) {   // (e.g. "20H330")
    char b[64] = ""; size_t n = sizeof(b);
    if (sysctlbyname("kern.osversion", b, &n, NULL, 0) != 0) return nil;
    return [NSString stringWithUTF8String:b];
}
// 1 = the engine's API was verified on this iPadOS build, 0 = it failed here (*reason: why, *os: the iPadOS version), -1 = not checked on this build.
static inline int MSBDStageManagerVerdict(NSString **reason, NSString **os) {
    CFStringRef domain = CFSTR("com.besiktasliseba.macstatusbar");
    CFStringRef user = getuid() == 0 ? CFSTR("mobile") : kCFPreferencesCurrentUser;   // (the root helper reads mobile's preferences)
    CFPreferencesSynchronize(domain, user, kCFPreferencesAnyHost);
    id v = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_SM_CHECK_KEY, domain, user, kCFPreferencesAnyHost);
    if (![v isKindOfClass:[NSDictionary class]]) return -1;
    NSDictionary *d = v;
    NSString *build = MSBDOSBuild();
    if (!build.length || ![d[@"build"] isKindOfClass:[NSString class]] || ![d[@"build"] isEqualToString:build]) return -1;
    if ([d[@"ok"] boolValue]) return 1;
    if (reason) *reason = [d[@"reason"] isKindOfClass:[NSString class]] ? d[@"reason"] : nil;
    if (os) {
        NSOperatingSystemVersion ov = [NSProcessInfo processInfo].operatingSystemVersion;
        *os = ov.patchVersion ? [NSString stringWithFormat:@"%ld.%ld.%ld", (long)ov.majorVersion, (long)ov.minorVersion, (long)ov.patchVersion]
                              : [NSString stringWithFormat:@"%ld.%ld", (long)ov.majorVersion, (long)ov.minorVersion];
    }
    return 0;
}
// Stage Manager can be the window engine here: the iPad has it (or TrollPad), and the self-check passed on this iPadOS build.
static inline BOOL MSBDStageManagerEngineUsable(void) {
    return MSBDStageManagerAvailable() && MSBDStageManagerVerdict(NULL, NULL) == 1;
}
