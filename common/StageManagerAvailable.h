// StageManagerAvailable.h -- whether this iPad can run Apple's Stage Manager, i.e. whether the Stage Manager window engine can be offered (2026-09-29).
// One test for Settings (the engine picker), the root helper (Stage Manager as the default engine on a first install) and SpringBoard (the one-time
// "Stage Manager is now a window engine" notice). Objective-C (Foundation).
#pragma once
#import <Foundation/Foundation.h>
#include <sys/sysctl.h>
#include <stdio.h>
#include <unistd.h>
#include <dlfcn.h>
// iPadOS 16 or later, and either TrollPad (which switches Stage Manager on for older iPads) or a model Apple ships it on.
static inline BOOL MSBDStageManagerTrollPad(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/usr/lib/TweakInject/TrollPadSB.dylib"]
        || [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/Library/MobileSubstrate/DynamicLibraries/TrollPadSB.dylib"];   // (the same folder where one links to the other)
}
// Apple's own answer: SpringBoardFoundation offers Stage Manager where MobileGestalt says DeviceSupportsSingleDisplayEnhancedMultitasking or
// DeviceSupportsEnhancedMultitasking (SBSupportedChamoisFeatures, decompiled from 16.3.1 20D67), so an iPad whose MobileGestalt answers yes has it,
// also where it was switched on another way than TrollPad (an edited MobileGestalt cache). Asked once per process. (TrollPad answers yes only
// inside SpringBoard and loads after us there, hence the file test above.)
static inline BOOL MSBDStageManagerGestalt(void) {
    static int answer = -1;
    if (answer >= 0) return answer == 1;
    void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY | RTLD_NOLOAD);
    if (!mg) mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    bool (*ask)(CFStringRef) = mg ? (bool (*)(CFStringRef))dlsym(mg, "MGGetBoolAnswer") : NULL;
    answer = ask && (ask(CFSTR("DeviceSupportsSingleDisplayEnhancedMultitasking")) || ask(CFSTR("DeviceSupportsEnhancedMultitasking"))) ? 1 : 0;
    return answer == 1;
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
    if (major == 8) return v.majorVersion > 16 || v.minorVersion >= 1;   // (Apple added these in 16.1)
    if (major == 13) return (minor >= 4 && minor <= 11) || minor == 16 || minor == 17;
    if (major == 14) return (minor >= 3 && minor <= 6) || (minor >= 8 && minor <= 11);
    return major >= 15;
}
static inline BOOL MSBDStageManagerAvailable(void) {
    // (iPadOS 16 on an iPad that has Stage Manager. 16.0 -- 20A8372, the M2 iPad Pro and iPad 10 factory build, where Apple keeps Stage Manager off
    //  and users switched it on by restoring a later backup -- was left out from 1.1.6 to sm-160: its API differs (issue #2: 18 rows), and 1.1.3 crashed
    //  there calling -containerBounds, which 16.0 does not have. sm-160: the check finds 16.0's own way for each of those jobs (SMEngineAPI.h variants)
    //  and the engine never calls -containerBounds; whether it can run is the check's answer, as on every other build.)
    NSOperatingSystemVersion ov = [NSProcessInfo processInfo].operatingSystemVersion;
    if (ov.majorVersion < 16) return NO;
    return MSBDStageManagerTrollPad() || MSBDStageManagerHardware() || MSBDStageManagerGestalt();
}
// Why Stage Manager can't be the engine on this iPad at all, before any check: 0 = it can (or iPadOS 15, where it is not offered), 2 = this iPad has
// no Stage Manager (not a model with it, no TrollPad, MobileGestalt says no). (1 was iPadOS 16.0 until sm-160.)
static inline int MSBDStageManagerUnavailableReason(void) {
    NSOperatingSystemVersion ov = [NSProcessInfo processInfo].operatingSystemVersion;
    if (ov.majorVersion < 16) return 0;
    return MSBDStageManagerAvailable() ? 0 : 2;
}
static inline NSString *MSBDOSVersionString(void) {   // (e.g. "16.3.1", "16.4")
    NSOperatingSystemVersion ov = [NSProcessInfo processInfo].operatingSystemVersion;
    return ov.patchVersion ? [NSString stringWithFormat:@"%ld.%ld.%ld", (long)ov.majorVersion, (long)ov.minorVersion, (long)ov.patchVersion]
                           : [NSString stringWithFormat:@"%ld.%ld", (long)ov.majorVersion, (long)ov.minorVersion];
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
// The check's record for THIS iPadOS build (keys build, os, ok, layout, reason, details = the core rows that failed, optional, featuresOff,
// runtime), nil when SpringBoard has not checked this build.
static inline NSDictionary *MSBDStageManagerCheckRecord(void) {
    CFStringRef domain = CFSTR("com.besiktasliseba.macstatusbar");
    CFStringRef user = getuid() == 0 ? CFSTR("mobile") : kCFPreferencesCurrentUser;   // (the root helper reads mobile's preferences)
    CFPreferencesSynchronize(domain, user, kCFPreferencesAnyHost);
    id v = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_SM_CHECK_KEY, domain, user, kCFPreferencesAnyHost);
    if (![v isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *d = v;
    NSString *build = MSBDOSBuild();
    if (!build.length || ![d[@"build"] isKindOfClass:[NSString class]] || ![d[@"build"] isEqualToString:build]) return nil;
    return d;
}
// 1 = the engine's API was verified on this iPadOS build, 0 = it failed here (*reason: why, *os: the iPadOS version), -1 = not checked on this build.
static inline int MSBDStageManagerVerdict(NSString **reason, NSString **os) {
    NSDictionary *d = MSBDStageManagerCheckRecord();
    if (!d) return -1;
    if ([d[@"ok"] boolValue]) return 1;
    if (reason) *reason = [d[@"reason"] isKindOfClass:[NSString class]] ? d[@"reason"] : nil;
    if (os) *os = MSBDOSVersionString();
    return 0;
}
// Stage Manager can be the window engine here: the iPad has it (or TrollPad), and the self-check passed on this iPadOS build.
static inline BOOL MSBDStageManagerEngineUsable(void) {
    return MSBDStageManagerAvailable() && MSBDStageManagerVerdict(NULL, NULL) == 1;
}
// The check passed through another iPadOS's way that Settings offers as untested (iPadOS 16.0: its layout pass and size grid, SMEngineAPI.h variants,
// sm-160; never run on a device): "Stage Manager (Untested)" with a note. iPadOS 16.1's own window model is offered normally (the owner, 4 Oct 2026),
// so its record names the way ("paths") without "untested". *paths: the other ways ("window model: sized", ...). From a given record, so it can be
// tested; MSBDStageManagerUntested reads the real one.
static inline BOOL MSBDStageManagerUntestedIn(NSDictionary *d, NSArray **paths) {
    if (![d isKindOfClass:[NSDictionary class]] || ![d[@"ok"] boolValue] || ![d[@"untested"] boolValue]) return NO;
    if (paths) *paths = [d[@"paths"] isKindOfClass:[NSArray class]] ? d[@"paths"] : nil;
    return YES;
}
static inline BOOL MSBDStageManagerUntested(NSArray **paths) { return MSBDStageManagerUntestedIn(MSBDStageManagerCheckRecord(), paths); }
// ---- why the Window Engine list greys Stage Manager, and what Report a Problem says about it (sm-163, 4 Oct 2026: a Reddit tester on iPadOS 16.3.1
// saw the row greyed with nothing telling him why, and his report would not have said either) ----
// The list's footer: the reason in a few words, nil when Stage Manager can be picked. unavailable: MSBDStageManagerUnavailableReason; verdict:
// MSBDStageManagerVerdict; os: the iPadOS version shown.
// verdict 2 = passed through an untested way (MSBDStageManagerUntested): offered, with this note.
static inline NSString *MSBDStageManagerWhyText(int unavailable, int verdict, NSString *os) {
    if (unavailable == 2) return @"This iPad doesn't have Stage Manager (TrollPad can add it).";
    if (verdict == -1) return @"Respring once to check Stage Manager on this iPadOS version.";
    if (verdict == 0) return [NSString stringWithFormat:@"Stage Manager isn't supported on iPadOS %@ yet.", os.length ? os : @"(this version)"];
    if (verdict == 2) return [NSString stringWithFormat:@"Stage Manager hasn't been tested on iPadOS %@ yet. If you try it, Report a Problem helps.", os.length ? os : @"(this version)"];
    return nil;
}
// The footer for a given state and check record (verdict 1 + an untested way in the record = the untested note), so it can be tested.
static inline NSString *MSBDStageManagerFooterFor(int unavailable, int verdict, NSDictionary *record, NSString *os) {
    if (verdict == 1 && MSBDStageManagerUntestedIn(record, NULL)) verdict = 2;
    return MSBDStageManagerWhyText(unavailable, verdict, os);
}
static inline NSString *MSBDStageManagerFooter(void) {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) return nil;   // (not offered on 15)
    int unavailable = MSBDStageManagerUnavailableReason();
    return MSBDStageManagerFooterFor(unavailable, unavailable ? 1 : MSBDStageManagerVerdict(NULL, NULL), MSBDStageManagerCheckRecord(), MSBDOSVersionString());
}
// A list of the record's lines, joined, at most maxChars (cut with "...").
static inline NSString *MSBDStageManagerJoin(id list, NSUInteger maxChars) {
    if (![list isKindOfClass:[NSArray class]] || ![(NSArray *)list count]) return nil;
    NSMutableArray *a = [NSMutableArray array];
    for (id x in list) if ([x isKindOfClass:[NSString class]]) [a addObject:x];
    NSString *s = [a componentsJoinedByString:@"; "];
    if (maxChars >= 4 && s.length > maxChars) s = [[s substringToIndex:maxChars - 3] stringByAppendingString:@"..."];
    return s;
}
// The Report a Problem line (iPadOS 16 and later): can this iPad run Stage Manager (and why it can), and the engine check on this build with the
// exact rows that failed or are missing. From the given state, so it can be tested (MSBDStageManagerReportLine reads the real one).
static inline NSString *MSBDStageManagerReportLineFor(int unavailable, NSString *source, int verdict, NSDictionary *record, NSString *os, NSString *build, NSUInteger maxChars) {
    if (unavailable == 2) return [NSString stringWithFormat:@"- Stage Manager: not on this iPad (%@)\n", source ?: @"no Stage Manager model, no TrollPad, MobileGestalt no"];
    NSString *where = [NSString stringWithFormat:@"%@ %@, %@", os ?: @"?", build ?: @"?", source ?: @"?"];
    if (verdict == -1) return [NSString stringWithFormat:@"- Stage Manager engine check: not run yet (%@)\n", where];
    NSString *failed = MSBDStageManagerJoin(record[@"details"], maxChars), *optional = MSBDStageManagerJoin(record[@"optional"], maxChars / 2);
    // (iPadOS 16.0 / 16.1: which other ways; "untested" only where Settings offers it so -- 16.0)
    NSString *paths = verdict == 1 ? MSBDStageManagerJoin(record[@"paths"], maxChars / 2) : nil;
    BOOL untested = verdict == 1 && [record[@"untested"] boolValue];
    NSMutableString *line = [NSMutableString stringWithFormat:@"- Stage Manager engine check: %@ (%@)", verdict == 1 ? (untested ? @"passed, untested way" : @"passed") : @"failed", where];
    if (paths) [line appendFormat:@": %@", paths];
    if (verdict != 1) [line appendFormat:@": %@", failed ?: ([record[@"reason"] isKindOfClass:[NSString class]] ? record[@"reason"] : @"no details")];
    if (optional) [line appendFormat:@"; optional, not here: %@", optional];
    [line appendString:@"\n"];
    return line;
}
static inline NSString *MSBDStageManagerReportLine(NSUInteger maxChars) {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) return nil;
    int unavailable = MSBDStageManagerUnavailableReason();
    BOOL tp = MSBDStageManagerTrollPad(), hw = MSBDStageManagerHardware(), mg = MSBDStageManagerGestalt();
    NSString *source = unavailable == 2 ? [NSString stringWithFormat:@"Stage Manager model %@, TrollPad %@, MobileGestalt %@", hw ? @"yes" : @"no", tp ? @"yes" : @"no", mg ? @"yes" : @"no"]
                                        : (hw ? @"native" : tp ? @"TrollPad" : mg ? @"MobileGestalt" : @"?");
    return MSBDStageManagerReportLineFor(unavailable, source, unavailable ? 1 : MSBDStageManagerVerdict(NULL, NULL), MSBDStageManagerCheckRecord(), MSBDOSVersionString(), MSBDOSBuild(), maxChars);
}
