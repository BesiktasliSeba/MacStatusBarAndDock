// StageManagerAvailable.h -- whether this iPad can run Apple's Stage Manager, i.e. whether the Stage Manager window engine can be offered (2026-09-29).
// One test for Settings (the engine picker), the root helper (Stage Manager as the default engine on a first install) and SpringBoard (the one-time
// "Stage Manager is now a window engine" notice). Objective-C (Foundation).
#pragma once
#import <Foundation/Foundation.h>
#include <sys/sysctl.h>
#include <stdio.h>
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
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) return NO;
    return MSBDStageManagerTrollPad() || MSBDStageManagerHardware();
}
