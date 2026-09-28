// OtherTweaks.h -- another installed tweak that already does the same thing as one of our features (decision C4, 2026-09-26).
// We never change another tweak's settings. When its own switch for the same thing is on, our part steps aside (so the effect is applied once, by
// one tweak, with no fight over the same view) and our Settings row says which tweak does it. Only settings whose domain, key and default were read
// from the tweak itself are listed: Lynx 2 (com.mtac.lynxtwo, its Settings page and Lynx.dylib), Atria (me.lau.AtriaPrefs, its open source) and
// Single Mute by 82Flex (SingleMute.dylib; com.82flex.singlemuteprefs "IsEnabled", on when missing -- its published Settings page) and Destra
// (MacOSNotifications.dylib, package xyz.cypwn.macosnotifications; com.jaxroth.macosnotifications "enabled", on when missing -- read on the iPad 2,
// where it squeezed our banners into its narrow right-hand strip, 2026-09-28).
// In SpringBoard/Settings a tweak counts as there when its library is loaded (inProcess) or, in Settings, when its library file is installed.
#pragma once
#import <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <sys/stat.h>
#include <os/lock.h>

typedef NS_ENUM(int, MSBDDuplicate) { kMSBDDupIconLabels, kMSBDDupPageDots, kMSBDDupCCGrabber, kMSBDDupLockStatusBar, kMSBDDupEthernetSection, kMSBDDupMuteIcon, kMSBDDupDockIndicators, kMSBDDupBanners };

static BOOL gMSBDOtherInSettings = NO;   // (set while asking about an effect that happens in Settings itself: SpringBoard's own Choicy list does not apply)
static inline BOOL MSBDTweakPresent(const char *lib, BOOL inProcess) {   // lib: "Lynx" -> Lynx.dylib
    char suffix[64]; snprintf(suffix, sizeof(suffix), "/%s.dylib", lib);
    if (inProcess) {
        for (uint32_t i = 0; i < _dyld_image_count(); i++) { const char *n = _dyld_get_image_name(i); if (n && strstr(n, suffix)) return YES; }
        return NO;
    }
    char path[256]; snprintf(path, sizeof(path), "/var/jb/usr/lib/TweakInject%s", suffix);
    struct stat st; if (stat(path, &st) != 0) return NO;   // (iCleaner Pro's switch-off renames it: gone here too)
    // Installed but kept out of SpringBoard by Choicy (its global deny list, or SpringBoard's own configuration when in force): it does not run
    // where the effect is, so it is not "doing it" (the same reading as LineSwitch.h's MSBDLineEnabled).
    NSDictionary *c = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"];
    if (![c isKindOfClass:[NSDictionary class]]) return YES;
    NSString *name = @(lib);
    if ([c[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] && [c[@"globalDeniedTweaks"] containsObject:name]) return NO;
    NSDictionary *sb = [c[@"appSettings"] isKindOfClass:[NSDictionary class]] ? c[@"appSettings"][@"com.apple.springboard"] : nil;
    if (!gMSBDOtherInSettings && [sb isKindOfClass:[NSDictionary class]] && [sb[@"customTweakConfigurationEnabled"] boolValue]) {
        if ([sb[@"tweakInjectionDisabled"] boolValue]) return NO;
        NSInteger mode = [sb[@"allowDenyMode"] isKindOfClass:[NSNumber class]] ? [sb[@"allowDenyMode"] integerValue] : 1;
        NSArray *list = mode == 2 ? sb[@"deniedTweaks"] : sb[@"allowedTweaks"];
        BOOL listed = [list isKindOfClass:[NSArray class]] && [list containsObject:name];
        if ((mode == 2 && listed) || (mode == 1 && !listed)) return NO;
    }
    return YES;
}
static inline BOOL MSBDOtherPref(CFStringRef domain, CFStringRef key, BOOL missing) {
    CFPropertyListRef v = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = missing;
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue(v);
    else if (v && CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); on = n != 0; }
    if (v) CFRelease(v);
    return on;
}
// The name of the tweak doing it, or nil. Cached for 3 s (our hooks ask often; a change in the other tweak needs its own respring anyway).
static inline NSString *MSBDOtherTweakDoing(MSBDDuplicate what, BOOL inProcess) {
    static NSString *cache[16]; static CFAbsoluteTime at[16];   // (room for new entries: one per MSBDDuplicate)
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;   // (label images may be built off the main thread)
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&lock);
    NSString *hit = at[what] && now - at[what] < 3.0 ? cache[what] : nil; BOOL fresh = at[what] && now - at[what] < 3.0;
    os_unfair_lock_unlock(&lock);
    if (fresh) return hit;
    NSString *who = nil;
    CFStringRef lynx = CFSTR("com.mtac.lynxtwo");
    gMSBDOtherInSettings = what == kMSBDDupEthernetSection;   // (Lynx's Ethernet section is drawn by Settings; everything else by SpringBoard)
    BOOL hasLynx = MSBDTweakPresent("Lynx", inProcess);
    if (hasLynx) CFPreferencesAppSynchronize(lynx);
    switch (what) {
        case kMSBDDupIconLabels:
            if (hasLynx && MSBDOtherPref(lynx, CFSTR("hideIconLabels"), NO)) who = @"Lynx";
            else if (MSBDTweakPresent("Atria", inProcess)) { CFPreferencesAppSynchronize(CFSTR("me.lau.AtriaPrefs")); if (MSBDOtherPref(CFSTR("me.lau.AtriaPrefs"), CFSTR("hideLabels"), NO)) who = @"Atria"; }
            break;
        case kMSBDDupPageDots: if (hasLynx && MSBDOtherPref(lynx, CFSTR("hidePageDots"), NO)) who = @"Lynx"; break;
        case kMSBDDupCCGrabber: if (hasLynx && MSBDOtherPref(lynx, CFSTR("hideCCGrabber"), NO)) who = @"Lynx"; break;
        case kMSBDDupLockStatusBar: if (hasLynx && MSBDOtherPref(lynx, CFSTR("hideStatusOnLockScreen"), NO)) who = @"Lynx"; break;
        case kMSBDDupDockIndicators: if (hasLynx && MSBDOtherPref(lynx, CFSTR("showDockIndicators"), NO)) who = @"Lynx"; break;   // (missing: not counted -- only an explicit "on")
        case kMSBDDupEthernetSection: if (hasLynx && MSBDOtherPref(lynx, CFSTR("showSettingsEthernetSection"), YES)) who = @"Lynx"; break;   // (on by default in Lynx)
        case kMSBDDupBanners:   // (Destra's Mac-style banners: it narrows the banner window itself, so both at once squeeze every banner)
            if (MSBDTweakPresent("MacOSNotifications", inProcess)) { CFPreferencesAppSynchronize(CFSTR("com.jaxroth.macosnotifications")); if (MSBDOtherPref(CFSTR("com.jaxroth.macosnotifications"), CFSTR("enabled"), YES)) who = @"Destra"; }
            break;
        case kMSBDDupMuteIcon:   // (its switch applies after a respring, like its library being loaded or not)
            if (MSBDTweakPresent("SingleMute", inProcess)) { CFPreferencesAppSynchronize(CFSTR("com.82flex.singlemuteprefs")); if (MSBDOtherPref(CFSTR("com.82flex.singlemuteprefs"), CFSTR("IsEnabled"), YES)) who = @"Single Mute"; }
            break;
    }
    os_unfair_lock_lock(&lock);
    cache[what] = who; at[what] = now;
    os_unfair_lock_unlock(&lock);
    return who;
}
