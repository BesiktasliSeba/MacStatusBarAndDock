// OwnPageState.h -- the state our Settings pages leave rows out by (common/OwnPageRows.h MSBDOwnPages), read the way the pages read it: the
// readers below are the pages' own (statusbar/macstatusbarprefs/MSBRootListController.m and dock/dockmagnificationprefs/DMRootListController.m
// call them), and MSBDOwnPagesNow gathers them for the Settings search and Spotlight's Tweak Settings (common/TweakSpotlight.h MTSShownRows:
// Settings, and SpringBoard's donation). Foundation and the shared checks only.
#pragma once
#import <Foundation/Foundation.h>
#include <os/lock.h>
#import "OwnPageRows.h"
#import "LineSwitch.h"              // (MSBDLineEnabled: MacStatusBar's and MacDock's switches)
#import "DesktopCheck.h"            // (MSBDDesktopVerdict, MSBDFocusLockVerdict)
#import "EngineBuilds.h"            // (MSBDEngineFileTested, MSBDDefaultEngine)
#import "StageManagerAvailable.h"   // (MSBDStageManagerEngineUsable)

#define kMSBDOwnBarDomain CFSTR("com.besiktasliseba.macstatusbar")
// "Status Bar Style: Stock" as stored (stockStatusBar, a boolean; off unless set): the stockHides groups go, on every page of ours.
static inline BOOL MSBDStockBarStored(void) {
    CFPreferencesAppSynchronize(kMSBDOwnBarDomain);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("stockStatusBar"), kMSBDOwnBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return on;
}
// Finder as stored (finderEnabled, on unless set; a boolean or a number, as SpringBoard reads it).
static inline BOOL MSBDFinderStored(void) {
    CFPreferencesAppSynchronize(kMSBDOwnBarDomain);
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("finderEnabled"), kMSBDOwnBarDomain);
    BOOL on = !v || (CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : (CFGetTypeID(v) == CFNumberGetTypeID() ? [(__bridge NSNumber *)v boolValue] : YES));
    if (v) CFRelease(v);
    return on;
}
// BigSurCenter installed (its library in either tweak folder): Control Center's size only resizes its own drop-down panel.
static inline BOOL MSBDBigSurCenterInstalled(void) {
    for (NSString *dir in @[@"/var/jb/usr/lib/TweakInject", @"/var/jb/Library/MobileSubstrate/DynamicLibraries"])
        if ([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"BigSurCenter.dylib"]]) return YES;
    return NO;
}
// iPadOS 18+ where SpringBoard's typed keyboard focus lock failed its check on this build (StatusBar.x DMFocusLock18OK): no Mac Switcher, no
// Wi-Fi Menu, no desktop. And the desktop's own check (17+, DesktopCheck.h).
static inline BOOL MSBDFocusLock18Failed(void) { return [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 18 && MSBDFocusLockVerdict() == 0; }
static inline BOOL MSBDDesktopRowsFailed(void) {
    return [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17 && (MSBDFocusLock18Failed() || MSBDDesktopVerdict(NULL) == 0);
}

// ---- the window engine the Window Engine row shows (moved here from MSBRootListController.m, 1.7.9; the page calls these) ----
// "Installed" = its library is in TweakInject, as .dylib or as iCleaner's .disabled (Choicy's deny list does not make an engine uninstalled).
// 0 = not installed, 1 = installed but not a tested build, 2 = installed and tested (Stage Manager: 2 where it can run, else 0; any other name 2).
static inline NSString *MSBDEngineLibraryPath(NSString *lib) {   // (its .dylib, or iCleaner's .disabled)
    NSString *dir = @"/var/jb/usr/lib/TweakInject";
    NSString *path = [[dir stringByAppendingPathComponent:lib] stringByAppendingPathExtension:@"dylib"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) path = [[dir stringByAppendingPathComponent:lib] stringByAppendingPathExtension:@"disabled"];
    return path;
}
#if DEBUG
// (debug: /tmp/msb-engine-notinstalled names engines to show as not installed -- the GET button --, "<engine>-untested" as an untested build, and
//  "stagemanager" as an iPad without Stage Manager: its row greyed and the why under the Native group, 1.5.2)
static inline NSString *MSBDEnginePretend(void) { return [NSString stringWithContentsOfFile:@"/tmp/msb-engine-notinstalled" encoding:NSUTF8StringEncoding error:nil]; }
#endif
static inline int MSBDEngineState(NSString *engine) {
#if DEBUG
    if ([engine isEqualToString:@"stagemanager"] && [MSBDEnginePretend() containsString:@"stagemanager"]) return 0;
#endif
    if ([engine isEqualToString:@"stagemanager"]) return MSBDStageManagerEngineUsable() ? 2 : 0;
    NSDictionary *mainLib = @{@"aerial": @"Aerial", @"milkyway": @"MilkyWay4", @"zetsu": @"Zetsu"};
    NSString *lib = mainLib[engine];
    if (!lib) return 2;
#if DEBUG
    NSString *pretend = MSBDEnginePretend();   // (debug: test the GET button)
    if ([pretend containsString:[engine stringByAppendingString:@"-untested"]]) return 1;   // (debug: test the "(untested version)" label)
    if ([pretend containsString:engine]) return 0;
#endif
    NSString *path = MSBDEngineLibraryPath(lib);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return 0;
    return MSBDEngineFileTested(lib, path) ? 2 : 1;
}
// The engine the Window Engine row shows as picked: the stored one when this iPadOS offers it and it is installed (an untested build too: it is
// the one that loads, on its own); else the same single rule as SpringBoard and the helper (EngineBuilds.h: Aerial of any build, else MilkyWay4,
// else Zetsu); "none" with no engine at all.
static inline NSString *MSBDEngineShown(id value, NSArray *offered) {
    if ([value isKindOfClass:[NSString class]] && [offered containsObject:value] && MSBDEngineState(value) >= 1) return value;
    NSString *fallback = MSBDDefaultEngine(^BOOL(NSString *e) { return MSBDEngineState(e) != 0; }, ^NSString *(NSString *lib) { return MSBDEngineLibraryPath(lib); });
    return fallback ?: @"none";
}
// The same without the row (the row is on the Windows & Multitasking page): the stored value or the row's default, and the row's values
// (Windows.plist) less what the page takes out on this iPadOS (Stage Manager before 16, MilkyWay4 on 16+).
static inline NSString *MSBDEngineShownWithoutRow(void) {
    CFPreferencesAppSynchronize(kMSBDOwnBarDomain);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("windowEngine"), kMSBDOwnBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *stored = v && CFGetTypeID(v) == CFStringGetTypeID() ? [(__bridge NSString *)v copy] : @"aerial";
    if (v) CFRelease(v);
    NSMutableArray *offered = [@[@"aerial", @"milkyway", @"zetsu", @"stagemanager"] mutableCopy];
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) [offered removeObject:@"stagemanager"];
    else [offered removeObject:@"milkyway"];
    return MSBDEngineShown(stored, offered);
}

// ---- all of it, for the search ----
// Our Battery Use group on Battery Health: what our Settings part decided when Apple's battery pages loaded in this process (TweakSearch.x sets
// this to BatteryHealth.x's and BatteryUse.x's answer; NULL elsewhere, or not known yet: the group counts as there, as on every tested iPadOS).
static BOOL (*gMSBDOwnBatteryUseOff)(void) = NULL;
// The state now, read at most once a second (the search asks it at every hand-over of results, on the query's queue).
static inline MSBDOwnPages MSBDOwnPagesNow(void) {
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    static MSBDOwnPages last;
    static CFAbsoluteTime at = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_lock(&lock);
    BOOL fresh = at > 0 && now - at < 1.0 && now >= at;
    MSBDOwnPages s = last;
    os_unfair_lock_unlock(&lock);
    if (fresh) return s;
    s.stockBar = MSBDStockBarStored();
    s.barLine = MSBDLineEnabled(@"MacStatusBar");
    s.dockLine = MSBDLineEnabled(@"MacDock");
    s.finder = MSBDFinderStored();
    s.bigSurCenter = MSBDBigSurCenterInstalled();
    s.focus18Failed = MSBDFocusLock18Failed();
    s.desktopFailed = MSBDDesktopRowsFailed();
    NSString *engine = MSBDEngineShownWithoutRow();
    s.engineWorks = ![engine isEqualToString:@"none"] && MSBDEngineState(engine) == 2;
    s.stageManagerEngine = [engine isEqualToString:@"stagemanager"];
    s.milkyWayEngine = [engine isEqualToString:@"milkyway"];
    s.batteryUseOff = gMSBDOwnBatteryUseOff ? gMSBDOwnBatteryUseOff() : NO;
    os_unfair_lock_lock(&lock);
    last = s; at = now;
    os_unfair_lock_unlock(&lock);
    return s;
}
