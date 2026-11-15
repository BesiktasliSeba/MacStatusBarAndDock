// MilkyWayRow.h -- MilkyWay4's "Launch As Window" row in an app icon's Haptic Touch menu while it is our engine (StatusBar.x, the hook of
// -effectiveApplicationShortcutItems, the list both menu styles are built from; KT 4 Nov). Plain Foundation: the Mac test (tools/test-milkywayrow.sh)
// runs this very rule.
// MilkyWay4 adds the row (a shortcut item of the type below, so in every language) to every app icon, and acts on it in its hook of
// +[SBIconView activateShortcut:withBundleIdentifier:forIconView:]. Where it opens a window that shows, the Dock and the Home Screen, the row stays
// (for an app with no window yet: DMMilkyRowKept).
// In the App Library it never does (M1, 15.6.1, each tried): its category icons (SBHLibraryCategoryPodIconView) answer that class method themselves,
// so the row never reached MilkyWay4 and the app opened full screen; an expanded category's icons and the search list's (plain SBIconViews) did reach
// it, but the window came up behind the App Library, which stays open with the windows faded away: only the menu bar's title told.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>

#define kDMMilkyLaunchRowType @"jp.yuri.milkyway3.launchinwindow"

// location: the icon view's SBIconLocation... name (full-screen App Library, or opened from the Dock's button: all of them say Library). Not a name
// (nil): the menu is left as MilkyWay4 made it.
static BOOL DMMilkyRowOpensWindowAt(id location) {
    return ![location isKindOfClass:[NSString class]] || ![(NSString *)location containsString:@"Library"];
}
// Is the row kept? Only where it opens a window that shows, and only for an app that has no MilkyWay window yet. hasWindow: the app has one already --
// shown, minimized or on another Mac Switcher desktop (StatusBar.x DMFindMilkyWayWindow, which skips one on its way out). MilkyWay4 acts on the row in
// its own hook and adds a second window on the app's one scene (a stale twin; with the Mac Switcher, a duplicate on this desktop): the one-window rule
// was our launch path's only (DMLaunchAsWindow). The icon itself brings that window back (DMWindowedLaunch -> DMSurfaceWindowForApp: un-minimized,
// its desktop brought), so nothing is lost (1.8.7.5, audit L31 of 1.8.7.2).
static BOOL DMMilkyRowKept(id location, BOOL hasWindow) {
    return !hasWindow && DMMilkyRowOpensWindowAt(location);
}
// The shortcut items without the row (the same array when it isn't there). Items are asked for their type only if they answer it.
static NSArray *DMMilkyRowsWithoutLaunch(NSArray *items) {
    if (![items isKindOfClass:[NSArray class]]) return items;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:items.count];
    SEL type = NSSelectorFromString(@"type");
    for (id item in items) {
        id t = [item respondsToSelector:type] ? ((id (*)(id, SEL))objc_msgSend)(item, type) : nil;
        if (![t isEqual:kDMMilkyLaunchRowType]) [kept addObject:item];
    }
    return kept.count == items.count ? items : kept;
}
