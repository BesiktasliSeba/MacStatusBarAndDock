// SettingsRoot.h -- where our Settings pages are, for links into them from outside Settings (SpringBoard, the Dock, search results).
// 15-17: Settings' root list is a PSListController (PSUIPrefsListController) holding our Status Bar and Dock rows, MAC_STATUS_BAR and
// DOCK_MAGNIFICATION, so a link is prefs:root=MAC_STATUS_BAR[&path=...]. iPadOS 18: the root list is SwiftUI (no PSUIPrefsListController); our
// rows are in General under PreferenceLoader's identifiers (common/General18Group.h), as PreferenceLoader's own entries are when ours are not,
// so the same link is prefs:root=General&path=MSBD_PL_MacStatusBarPrefs[/...]. Settings records which root it has, per iPadOS build, at its start
// (StatusBarSettingsRow.x); links follow the record. Not recorded on this build yet (Settings not started since): on iPadOS 18+, where
// SpringBoard has PreferencesUI loaded (18.5 does), that framework without PSUIPrefsListController tells the same; else links as on 15-17.
// Foundation only.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <unistd.h>
#include "StageManagerAvailable.h"   // (MSBDOSBuild)

#define MSBD_SETTINGSROOT_CHECK_KEY CFSTR("settingsRootCheck")
// Settings: which root list it has on this iPadOS build (written only when it differs from the record).
static inline void MSBDSettingsRootRecord(BOOL swiftUI) {
    CFStringRef domain = CFSTR("com.besiktasliseba.macstatusbar");
    NSString *build = MSBDOSBuild();
    if (!build.length) return;
    CFPreferencesAppSynchronize(domain);
    id v = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_SETTINGSROOT_CHECK_KEY, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if ([v isKindOfClass:[NSDictionary class]] && [((NSDictionary *)v)[@"build"] isEqual:build] && [((NSDictionary *)v)[@"swiftUI"] boolValue] == swiftUI) return;
    CFPreferencesSetValue(MSBD_SETTINGSROOT_CHECK_KEY, (__bridge CFPropertyListRef)@{@"build": build, @"swiftUI": @(swiftUI)}, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
// 1 = SwiftUI root (iPadOS 18) on this build, 0 = the PSListController root, -1 = not recorded on this build.
static inline int MSBDSettingsRootVerdict(void) {
    CFStringRef domain = CFSTR("com.besiktasliseba.macstatusbar");
    CFStringRef user = getuid() == 0 ? CFSTR("mobile") : kCFPreferencesCurrentUser;
    CFPreferencesSynchronize(domain, user, kCFPreferencesAnyHost);
    id v = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_SETTINGSROOT_CHECK_KEY, domain, user, kCFPreferencesAnyHost);
    if (![v isKindOfClass:[NSDictionary class]]) return -1;
    NSDictionary *d = v;
    NSString *build = MSBDOSBuild();
    if (!build.length || ![d[@"build"] isKindOfClass:[NSString class]] || ![d[@"build"] isEqualToString:build]) return -1;
    return [d[@"swiftUI"] boolValue] ? 1 : 0;
}
// 1.6.0: the window rows moved from the Status Bar page to the Windows & Multitasking page (its own row, MAC_WINDOWS, right after Status Bar: the
// sidebar on 15-17, our group in General on 18). A link to one of them on the Status Bar page -- the Window Engine picker (path WINDOW_ENGINE) or a
// row after "#" (an older search result) -- goes to that page, on every iPadOS version. The rows by Settings' identifiers (a row's "id", else its
// label: -[PSSpecifier identifier]).
static inline NSArray<NSString *> *MSBDWindowsPageRowIDs(void) {
    return @[@"WINDOW_ENGINE", @"Windowing", @"Enable Windowing", @"ENGINE_GROUP", @"Window Engine", @"MSB_SM_TURN_ON", @"WINDOWS_GROUP",
             @"Windows Behind Full-Screen Apps", @"Resize Handles", @"Tint Resize Handles", @"RESIZE_GROUP", @"Resize Apps to Fit Windows", @"Traffic Lights",
             @"Turn Off Traffic Lights", @"Multitasking", @"Hide Multitasking Dots", @"Mac Switcher"];
}
static inline NSString *MSBDSettingsLinkMoved(NSString *link) {
    NSString *pre = @"prefs:root=MAC_STATUS_BAR";
    if (![link isKindOfClass:[NSString class]] || ![link hasPrefix:pre]) return link;
    NSString *tail = [link substringFromIndex:pre.length], *name = nil;
    if ([tail hasPrefix:@"&path="]) name = [tail substringFromIndex:6];
    else if ([tail hasPrefix:@"#"]) name = [tail substringFromIndex:1];
    else if ([tail hasPrefix:@"%23"]) name = [tail substringFromIndex:3];
    if (!name.length) return link;   // (the page itself, or another page whose name merely starts the same)
    NSUInteger cut = name.length;
    for (NSString *mark in @[@"/", @"#", @"%23", @"&"]) { NSRange r = [name rangeOfString:mark]; if (r.location != NSNotFound) cut = MIN(cut, r.location); }
    name = [name substringToIndex:cut];
    if (![MSBDWindowsPageRowIDs() containsObject:name.stringByRemovingPercentEncoding ?: name]) return link;
    return [@"prefs:root=MAC_WINDOWS" stringByAppendingString:tail];
}
// A link into one of our pages as the SwiftUI root needs it: prefs:root=MAC_STATUS_BAR[&path=X][#Y] -> prefs:root=General&path=
// MSBD_PL_MacStatusBarPrefs[/X][#Y] (DOCK_MAGNIFICATION likewise); our Keyboard and Pointer pages, the sidebar's MAC_KEYBOARD and MAC_POINTER rows on
// 15-17, are rows of the same identifiers in our group at the top of General there (macsettings/MacSettings.x): prefs:root=MAC_KEYBOARD[...] ->
// prefs:root=General&path=MAC_KEYBOARD[...]; Windows & Multitasking (MAC_WINDOWS) likewise. Any other link, or one with something else after the
// page, as it is. (The moved window rows first, on every version: MSBDSettingsLinkMoved.)
static inline NSString *MSBDSettingsLinkForRoot(NSString *link, BOOL swiftUI) {
    link = MSBDSettingsLinkMoved(link);
    if (!swiftUI || ![link isKindOfClass:[NSString class]] || ![link hasPrefix:@"prefs:root="]) return link;
    NSString *rest = [link substringFromIndex:11], *page = nil, *pl = nil;
    for (NSArray<NSString *> *m in @[@[@"MAC_STATUS_BAR", @"MSBD_PL_MacStatusBarPrefs"], @[@"DOCK_MAGNIFICATION", @"MSBD_PL_DockMagnificationPrefs"],
                                     @[@"MAC_KEYBOARD", @"MAC_KEYBOARD"], @[@"MAC_POINTER", @"MAC_POINTER"], @[@"MAC_WINDOWS", @"MAC_WINDOWS"]])
        if ([rest hasPrefix:m[0]]) { page = m[0]; pl = m[1]; }
    if (!pl) return link;
    NSString *tail = [rest substringFromIndex:page.length], *frag = @"", *path = nil;
    NSRange h = [tail rangeOfString:@"#"];
    if (h.location == NSNotFound) h = [tail rangeOfString:@"%23"];   // (a row after the page, encoded or not)
    if (h.location != NSNotFound) { frag = [tail substringFromIndex:h.location]; tail = [tail substringToIndex:h.location]; }
    if ([tail hasPrefix:@"&path="]) path = [tail substringFromIndex:6];
    else if (tail.length) return link;   // (another page whose name merely starts the same, or something we do not know)
    return [NSString stringWithFormat:@"prefs:root=General&path=%@%@%@", pl, path.length ? [@"/" stringByAppendingString:path] : @"", frag];
}
// Settings' root list is SwiftUI here: as Settings recorded it on this build; not recorded, iPadOS 18+ with PreferencesUI loaded in this process (one
// of its classes there) and no PSUIPrefsListController in it.
static inline BOOL MSBDSettingsRootSwiftUI(void) {
    int v = MSBDSettingsRootVerdict();
    if (v >= 0) return v == 1;
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 18 || !objc_getClass("PUILocationServicesListController")) return NO;
    return objc_getClass("PSUIPrefsListController") == Nil;
}
static inline NSString *MSBDSettingsLink(NSString *link) { return MSBDSettingsLinkForRoot(link, MSBDSettingsRootSwiftUI()); }
// SpringBoard opening Settings on a page of ours for the user -- the welcome alert's Take Me There, the crash notice's and the other notices' Open
// Settings, Choose Engine, Edit Go Menu… (statusbar/StatusBar.x, DMOpenStatusBarSettings) -- follows Open Apps as Windows like every other launch, on
// every iPadOS version and engine (KT, 28 Oct 2026): Settings as a window when it is on (its window comes forward when it has one), full screen when
// it is off. iPadOS 18 (SwiftUI root): Settings' own link to the page (MSBDPageLink). 15-17: the page request (our row in Settings' main list), which
// Settings reads when it becomes active; asked before Settings is opened, except on Stage Manager full screen, where it is asked once the window is
// full screen so that the page is laid out at that size. (Until 1.6.0~rc3 the 15-17 request always opened Settings full screen; only the link way
// followed Open Apps as Windows, since 26 Sep.)
typedef NS_ENUM(int, MSBDPageOpen) {
    MSBDPageOpenLinkAsWindow = 0,     // (18) Settings launched by the link as a window, then the link again once it is in front
    MSBDPageOpenLinkFullScreen,       // (18) Settings full screen, then the link
    MSBDPageOpenAskAsWindow,          // (15-17) the request, then Settings as a window
    MSBDPageOpenAskFullScreen,        // (15-17) the request, then Settings full screen (a window of it goes full screen as its green does it)
    MSBDPageOpenFullScreenThenAsk,    // (15-17, Stage Manager) Settings full screen in its stage, then the request
};
static inline MSBDPageOpen MSBDPageOpenFor(BOOL swiftUIRoot, BOOL windowed, BOOL smEngine) {
    if (swiftUIRoot) return windowed ? MSBDPageOpenLinkAsWindow : MSBDPageOpenLinkFullScreen;
    if (windowed) return MSBDPageOpenAskAsWindow;
    return smEngine ? MSBDPageOpenFullScreenThenAsk : MSBDPageOpenAskFullScreen;
}
static inline BOOL MSBDPageOpenIsWindow(MSBDPageOpen way) { return way == MSBDPageOpenLinkAsWindow || way == MSBDPageOpenAskAsWindow; }
// The page opener's places as Settings' links (iPadOS 18; MSBDSettingsLink puts them in General): 0 the Status Bar page, 1 its Go Menu > Apps
// picker, 2 the Window Engine picker on the Windows & Multitasking page, 3 that page itself (Enable Windowing).
static inline NSString *MSBDPageLink(uint32_t target) {
    return target == 1 ? @"prefs:root=MAC_STATUS_BAR&path=GO_APPS" : target == 2 ? @"prefs:root=MAC_WINDOWS&path=WINDOW_ENGINE"
         : target == 3 ? @"prefs:root=MAC_WINDOWS" : @"prefs:root=MAC_STATUS_BAR";
}
// Where the window settings are, for notices that name the page (Enable Windowing): Settings > Windows & Multitasking (its row in the sidebar), on
// iPadOS 18 under General (our group there).
static inline NSString *MSBDWindowsSettingsPath(void) {
    return MSBDSettingsRootSwiftUI() ? @"Settings > General > Windows & Multitasking" : @"Settings > Windows & Multitasking";
}
// Where the Window Engine picker is, for notices that name it: on that page.
static inline NSString *MSBDWindowEngineSettingsPath(void) {
    return [MSBDWindowsSettingsPath() stringByAppendingString:@" > Window Engine"];
}
