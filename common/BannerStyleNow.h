// BannerStyleNow.h -- Banner Style on the iPad (1.8.0 item 2): what common/BannerStyle.h's rule is given, read the same way by Settings and
// SpringBoard (as mobile) and the root helper (as root, for mobile): the stored style, the old Mac-Style Banners switch and Destra's library
// (common/ExclusiveChoice.h); and Destra's own Enabled switch, which the rule no longer asks (never set is ours, KT 3 Nov) but SpringBoard's style
// in force and Settings' notes do. Foundation.
//  - Destra, read from its package on the M1 (xyz.cypwn.macosnotifications 1.1.0, "Destra" by Jax Roth; its own package was
//    com.jaxroth.macosnotifications): MacOSNotifications.dylib, filtered to SpringBoard, and its settings page MacOSNotifications.bundle, whose
//    Enabled switch is "enabled" in com.jaxroth.macosnotifications.plist (on when never set). Its page writes that file itself, past cfprefsd (an
//    XML file where cfprefsd writes a binary one), and Destra reads the file when it loads: so the file is read here too -- cfprefsd's copy kept
//    the old value in every other process (M1, 3 Nov: the file on, CFPreferences off in SpringBoard after a respring, and Destra drew its banners).
//  - Debug builds: /tmp/msb-engine-notinstalled naming "destra" shows Destra as not installed on our Settings pages (its row greyed "Not
//    Installed", the style that would be without it) -- the engines' own test, OwnPageState.h. Only what the pages show: Settings' exclusivity,
//    SpringBoard and the helper read the real files (MSBDBannerStyleNowFor's display NO).
#pragma once
#import <Foundation/Foundation.h>
#include "BannerStyle.h"
#import "ExclusiveChoice.h"

#define kMSBDBannerDomain CFSTR("com.besiktasliseba.macstatusbar")
#define kMSBDDestraLib    @"MacOSNotifications"                 // (its library in TweakInject, the table's name: ExclusiveChoice.h)
#ifndef kMSBDDestraPrefsFile   // (overridable for the Mac test, tools/test-bannerstyle.sh)
#define kMSBDDestraPrefsFile @"/var/jb/var/mobile/Library/Preferences/com.jaxroth.macosnotifications.plist"   // (its own settings: "enabled")
#endif

// One value of ours for `user` (kCFPreferencesCurrentUser; the root helper: CFSTR("mobile")), read afresh; the caller releases it.
static inline CFPropertyListRef MSBDBannerCopyFor(CFStringRef key, CFStringRef domain, CFStringRef user) {
    CFPreferencesSynchronize(domain, user, kCFPreferencesAnyHost);
    return CFPreferencesCopyValue(key, domain, user, kCFPreferencesAnyHost);
}
// The stored style, and the old switch, for `user`.
static inline int MSBDBannerStyleStoredFor(CFStringRef user) {
    CFPropertyListRef v = MSBDBannerCopyFor(CFSTR(kMSBDBannerStyleKey), kMSBDBannerDomain, user);
    int stored = MSBDBannerStyleFromStored(v);
    if (v) CFRelease(v);
    return stored;
}
static inline int MSBDBannerLegacyFor(CFStringRef user) {
    CFPropertyListRef v = MSBDBannerCopyFor(CFSTR(kMSBDBannerLegacyKey), kMSBDBannerDomain, user);
    int legacy = MSBDBannerLegacyFromStored(v);
    if (v) CFRelease(v);
    return legacy;
}
// Destra's own Enabled switch, from its file (above): a boolean or a number, on when never set (its page's default). The file is mobile's, read as
// mobile or as root alike.
static inline BOOL MSBDDestraOwnOn(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kMSBDDestraPrefsFile];
    id v = [d isKindOfClass:[NSDictionary class]] ? d[@"enabled"] : nil;
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : YES;
}
#if DEBUG
static inline BOOL MSBDBannerPretendNoDestra(void) {
    NSString *p = [NSString stringWithContentsOfFile:@"/tmp/msb-engine-notinstalled" encoding:NSUTF8StringEncoding error:nil];
    return [p containsString:@"destra"];
}
#endif
// Destra installed (its library there, or iCleaner Pro's .disabled of it). display: as our Settings pages show it (the debug pretend).
static inline BOOL MSBDDestraInstalled(BOOL display) {
#if DEBUG
    if (display && MSBDBannerPretendNoDestra()) return NO;
#else
    (void)display;
#endif
    return MSBDExInstalled(kMSBDDestraLib);
}
// The style the rule gives now, for `user`; *installed: Destra installed; *ownOn: its own Enabled switch (either may be NULL; its file is read only
// when asked for: SpringBoard's style in force).
static inline int MSBDBannerStyleNowFor(CFStringRef user, BOOL display, BOOL *installed, BOOL *ownOn) {
    BOOL destra = MSBDDestraInstalled(display);
    if (installed) *installed = destra;
    if (ownOn) *ownOn = destra && MSBDDestraOwnOn();
    return MSBDBannerStyleChosen(MSBDBannerStyleStoredFor(user), MSBDBannerLegacyFor(user), destra);
}
static inline int MSBDBannerStyleNow(BOOL display) { return MSBDBannerStyleNowFor(kCFPreferencesCurrentUser, display, NULL, NULL); }
