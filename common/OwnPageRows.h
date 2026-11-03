// OwnPageRows.h -- which rows of our own Settings pages are on the page now (1.7.9, KT 2 Nov: the Settings search lists only what the pages show).
// The conditions our pages leave rows out by, and the rows each one takes, in one place:
//  - the pages build their lists with them: statusbar/macstatusbarprefs/MSBRootListController.m -specifiers and its page notes (the Status Bar,
//    Windows & Multitasking and Desktop pages), common/LineSwitch.h -msbd_hideRowsWhenLineOff (the rows below a page's MacStatusBar / MacDock
//    switch while it is off) and dock/dockmagnificationprefs/DMRootListController.m (the Dock page's Finder group);
//  - the Settings search and Spotlight's Tweak Settings leave the same rows out (common/TweakSpotlight.h MTSShownRows), from what
//    common/TweakIndex.h records of each row of a page: its group's identifier and stockHides, its key, whether it is below the line switch.
// The state is read on the iPad by common/OwnPageState.h (MSBDOwnPagesNow), with the readers the pages use; everything here is pure
// (tools/test-ownpagerows.sh runs it over the real plists on the Mac).
#pragma once
#import <Foundation/Foundation.h>
// (no TweakIndex.h here: the pages include this, and its helpers are plain static functions; MSBDOwnRowsShown below is there for an includer that
//  has the index already -- common/TweakSpotlight.h, the Mac test)

typedef struct {
    BOOL stockBar;            // "Status Bar Style: Stock" stored: the groups marked stockHides go (Report a Problem stays, in a group of its own)
    BOOL barLine, dockLine;   // MacStatusBar / MacDock switched on (LineSwitch.h MSBDLineEnabled); off: the page shows its line switch only
                              // (Windows & Multitasking: its note and Keep Tailspin Off; Desktop: its note)
    BOOL finder;              // Finder on (finderEnabled, on unless set); off: the Dock page has no Finder group
    BOOL bigSurCenter;        // BigSurCenter installed: Control Center's size slider resizes its panel (with our status bar only)
    BOOL focus18Failed;       // iPadOS 18 without SpringBoard's typed keyboard focus lock (DesktopCheck.h): no Mac Switcher, Wi-Fi Menu or desktop
    BOOL desktopFailed;       // the desktop's check failed (17+), or the above: no desktop rows
    BOOL engineWorks;         // the engine the Window Engine row shows is installed and tested (2): else no Windows group
    BOOL stageManagerEngine;  // ... it is Stage Manager: the Windows group keeps only the resize handles' rows, and Resize Handles is offered
    BOOL milkyWayEngine;      // ... it is MilkyWay4: Resize Apps to Fit Windows is offered
    BOOL batteryUseOff;       // our Battery Use group (Sleep Guard) is not on Battery Health on this iPad (BatteryHealth.x / BatteryUse.x refused)
} MSBDOwnPages;

// The rows each condition takes, by the identifiers and keys in our plists (the pages and the rule below ask these).
#define kMSBDLineRowID      @"MSBD_LINE"          // a page's MacStatusBar / MacDock switch (LineSwitch.h; TweakIndex.h kMTILineRowID)
#define kMSBDReportRowID    @"REPORT_PROBLEM"     // Report a Problem: with the stock status bar, in a group of its own instead of its group
#define kMSBDWiFiGroupID    @"WIFI_GROUP"         // the Wi-Fi Menu (18: SpringBoard's typed keyboard focus lock for its password sheet)
#define kMSBDMacSwitcherGroupID @"MSW_GROUP"      // the Mac Switcher and Go to the App's Desktop (18: the same lock)
#define kMSBDMacSwitcherKey @"macSwitcher"
#define kMSBDWindowsGroupID @"WINDOWS_GROUP"      // the switches that work through a third-party engine's windows
#define kMSBDResizeGroupID  @"RESIZE_GROUP"       // Resize Apps to Fit Windows (MilkyWay4 only)
#define kMSBDResizeHandlesKey @"resizeHandleStyle" // Resize Handles: ours or Stage Manager's (a choice with Stage Manager only)
#define kMSBDCCScaleKey     @"controlCenterScale" // Control Center's size: BigSurCenter's panel only
#define kMSBDTailspinGroupID @"TAILSPIN_GROUP"    // Keep Tailspin Off: the root helper applies it whatever the status bar does
#define kMSBDDockFinderRowID @"FINDER"            // the Dock page's Show Finder in Dock (and its group)
#define kMSBDDockFinderGroupID @"FINDER_GROUP"
// The desktop's rows, left out where its check failed (17+): Show Desktop Icons, Hide Desktop Icon Names, Icon Size and App Icon Corner Radius
// with their groups and Match Home Screen Icons (the page keeps DESKTOP_GROUP, whose footer says why). A row by its key or its own identifier.
static inline BOOL MSBDDesktopCheckRow(NSString *key, NSString *ident) {
    return (key && [@[@"desktopIcons", @"desktopHideNames", @"desktopIconSize"] containsObject:key])
        || (ident && [@[@"DESKTOP_SIZE_GROUP", @"DESKTOP_CORNER_GROUP", @"DESKTOP_APP_CORNER", @"DESKTOP_CORNER_MATCH"] containsObject:ident]);
}
// With Stage Manager as the engine the Windows group keeps the resize handles' rows: they are Stage Manager's own windows' too.
static inline BOOL MSBDHandlesRow(NSString *key) { return [key isEqualToString:kMSBDResizeHandlesKey] || [key isEqualToString:@"tintResizeHandles"]; }
// MacStatusBar off: the Windows & Multitasking page keeps, under its note, the groups whose setting the root helper applies whatever the bar does.
static inline BOOL MSBDBarOffKeepsGroup(NSString *groupID) { return [groupID isEqualToString:kMSBDTailspinGroupID]; }

// Whether a row of one of our pages is left out in state s. pane: the page (MAC_STATUS_BAR, MAC_WINDOWS, MAC_DESKTOP, DOCK_MAGNIFICATION); group:
// its group's identifier (nil: none); stockHides: that group's flag; key, ident: the row's own (nil: none); belowLine: it comes after the page's
// line switch. Rows of other pages: NO (they show as their page shows them).
static inline BOOL MSBDOwnRowHidden(MSBDOwnPages s, NSString *pane, NSString *group, BOOL stockHides, NSString *key, NSString *ident, BOOL belowLine) {
    if ([pane isEqualToString:@"DOCK_MAGNIFICATION"])
        return (!s.dockLine && belowLine) || (!s.finder && ([ident isEqualToString:kMSBDDockFinderRowID] || [group isEqualToString:kMSBDDockFinderGroupID]));
    BOOL bar = [pane isEqualToString:@"MAC_STATUS_BAR"], windows = [pane isEqualToString:@"MAC_WINDOWS"], desk = [pane isEqualToString:@"MAC_DESKTOP"];
    if (!bar && !windows && !desk) return NO;
    if (!s.barLine) {   // (MacStatusBar off: the Status Bar page keeps its switch; Windows & Multitasking its note and Keep Tailspin Off; Desktop its note)
        if (bar && belowLine) return YES;
        if (windows && !MSBDBarOffKeepsGroup(group)) return YES;
        if (desk) return YES;
    }
    if (s.stockBar && stockHides && ![ident isEqualToString:kMSBDReportRowID]) return YES;
    if ([key isEqualToString:kMSBDCCScaleKey] && (!s.bigSurCenter || s.stockBar)) return YES;
    if (s.desktopFailed && MSBDDesktopCheckRow(key, ident)) return YES;
    if (s.focus18Failed && ([key isEqualToString:kMSBDMacSwitcherKey] || [group isEqualToString:kMSBDMacSwitcherGroupID] || [group isEqualToString:kMSBDWiFiGroupID])) return YES;
    if ([group isEqualToString:kMSBDWindowsGroupID] && (!s.engineWorks || (s.stageManagerEngine && !MSBDHandlesRow(key)))) return YES;
    if ([key isEqualToString:kMSBDResizeHandlesKey] && !s.stageManagerEngine) return YES;
    if ([group isEqualToString:kMSBDResizeGroupID] && !s.milkyWayEngine) return YES;
    return NO;
}
#ifdef kMTIPrefix   // (common/TweakIndex.h included first)
// The index's rows as the pages show them now: our pages' rows by the rule above (the pages themselves stay: each still opens, with its note);
// our Sleep Guard (Battery > Battery Health) only where our Battery Use group is on that page. Other tweaks' rows and our rows of the main list
// as they are.
static inline NSArray<MTIEntry *> *MSBDOwnRowsShown(NSArray<MTIEntry *> *rows, MSBDOwnPages s) {
    NSMutableArray<MTIEntry *> *out = [NSMutableArray arrayWithCapacity:rows.count];
    for (MTIEntry *e in rows) {
        BOOL hidden = e.ours && e.depth >= 2 && (MSBDOwnRowHidden(s, e.paneID, e.groupID, e.stockHides, e.key, e.path.lastObject, e.belowLine)
                                 || (s.batteryUseOff && [e.paneID isEqualToString:@"BATTERY_USAGE"] && [e.path.lastObject isEqualToString:@"MSBD_SLEEP_GUARD"]));
        if (!hidden) [out addObject:e];
    }
    return out.count == rows.count ? rows : out;
}
#endif
