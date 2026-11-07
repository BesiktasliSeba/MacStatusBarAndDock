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
#include "CCStyle.h"   // (the Control Center Style's values: the rows that go with a style, 1.8.0)
// (no TweakIndex.h here: the pages include this, and its helpers are plain static functions; MSBDOwnRowsShown below is there for an includer that
//  has the index already -- common/TweakSpotlight.h, the Mac test)

typedef struct {
    BOOL stockBar;            // "Status Bar Style: Stock" stored: the groups marked stockHides go (Report a Problem stays, in a group of its own)
    BOOL barLine, dockLine;   // MacStatusBar / MacDock switched on (LineSwitch.h MSBDLineEnabled); off: the page shows its line switch only
                              // (Windows & Multitasking: its note and Keep Tailspin Off; Desktop: its note)
    BOOL finder;              // Finder on (finderEnabled, on unless set); off: the Dock page has no Finder group
    int ccStyle;              // the Control Center Style (common/CCStyle.h): BigSurCenter's has the size slider (with our status bar only), iPadOS's the
                              // Hide Grabber switch, Mac neither (1.8.0); 0 not known: both as before the style (no slider, Hide Grabber shown)
    BOOL focus18Failed;       // iPadOS 18 without SpringBoard's typed keyboard focus lock (DesktopCheck.h): no Mac Switcher, Wi-Fi Menu or desktop
    BOOL desktopFailed;       // the desktop's check failed (17+), or the above: no desktop rows
    BOOL engineWorks;         // the engine the Window Engine row shows is installed and tested (2): else the Windows group goes, but for Double-Tap a
                              //  Title Bar to (our own windows use it without an engine too), and New Windows Open at Fill with it
    BOOL stageManagerEngine;  // ... it is Stage Manager: the Windows group keeps only its windows' rows (resize handles, Window Size, Double-Tap a Title
                              //  Bar to), and Resize Handles is offered
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
#define kMSBDNewWindowsFillGroupID @"NEW_WINDOWS_FILL_GROUP" // New Windows Open at Fill: the windows an engine opens (none without one, audit 1.8.3 M4)
#define kMSBDResizeHandlesKey @"resizeHandleStyle" // Resize Handles: ours or Stage Manager's (a choice with Stage Manager only)
#define kMSBDWindowSizeRowKey @"windowSize"      // Window Size (1.8.0 item 4, common/WindowSize.h kMSBDWindowSizeKey): every engine's, Stage Manager's too
#define kMSBDTitleDoubleTapRowKey @"titleBarDoubleTap" // Double-Tap a Title Bar to (1.8.3 item 8, statusbar/TitleBarRule.h kMSBDTitleDoubleTapKey): every
                                                   // engine's, Stage Manager's too
#define kMSBDCCScaleKey     @"controlCenterScale" // Control Center Size: BigSurCenter's panel and ours (1.8.0)
#define kMSBDCCGrabberRowID @"CC_GRABBER"         // Hide Grabber: iPadOS's own Control Center's line (1.8.0: with that style only)
#define kMSBDTailspinGroupID @"TAILSPIN_GROUP"    // Keep Tailspin Off: the root helper applies it whatever the status bar does
#define kMSBDDockFinderRowID @"FINDER"            // the Dock page's Show Finder in Dock (and its group)
#define kMSBDDockFinderGroupID @"FINDER_GROUP"
// Control Center Size (1.8.0, KT 3 Nov): with BigSurCenter (its drop-down panel from our status bar) and with ours (Mac), never with the stock
// status bar (BigSurCenter's panel is not sized there, ours does not run); greyed with ours on iPadOS 18, where our panel is Apple's own 18 grid,
// which is not sized yet (statusbar/CC18Shape.h).
static inline BOOL MSBDCCSizeRowShown(int ccStyle, BOOL stockBar) { return (ccStyle == kMSBDCCStyleBigSurCenter || ccStyle == kMSBDCCStyleMac) && !stockBar; }
static inline BOOL MSBDCCSizeRowGreyed(int ccStyle, long major) { return ccStyle == kMSBDCCStyleMac && major >= 18; }
// The desktop's rows, left out where its check failed (17+): Show Desktop Icons, Hide Desktop Icon Names, Icon Size and App Icon Corner Radius
// with their groups and Match Home Screen Icons (the page keeps DESKTOP_GROUP, whose footer says why). A row by its key or its own identifier.
static inline BOOL MSBDDesktopCheckRow(NSString *key, NSString *ident) {
    return (key && [@[@"desktopIcons", @"desktopHideNames", @"desktopIconSize"] containsObject:key])
        || (ident && [@[@"DESKTOP_SIZE_GROUP", @"DESKTOP_CORNER_GROUP", @"DESKTOP_APP_CORNER", @"DESKTOP_CORNER_MATCH"] containsObject:ident]);
}
// With Stage Manager as the engine the Windows group keeps the rows that are Stage Manager's own windows' too: the resize handles', Window Size and
// Double-Tap a Title Bar to (our title bar on its windows does what the row says, statusbar/TitleBarTap.h; until 1.8.3.1 the row was left out of the
// page and the search, GitHub #11). The group's other row goes: Windows Behind Full-Screen Apps sets the other engines' window layer (StatusBar.x
// DMDesiredWindowLevel); Stage Manager keeps its own order.
static inline BOOL MSBDHandlesRow(NSString *key) { return [key isEqualToString:kMSBDResizeHandlesKey] || [key isEqualToString:@"tintResizeHandles"]; }
static inline BOOL MSBDStageManagerKeepsRow(NSString *key) {
    return MSBDHandlesRow(key) || [key isEqualToString:kMSBDWindowSizeRowKey] || [key isEqualToString:kMSBDTitleDoubleTapRowKey];
}
// With no working engine (none installed, or the one that would run is an untested build) the Windows group goes but for Double-Tap a Title Bar
// to: Finder's and TextEdit's windows are ours and do what it says without an engine too (statusbar/TitleBarTap.h DMTitleTapNative; 1.8.3.1).
static inline BOOL MSBDNoEngineKeepsRow(NSString *key) { return [key isEqualToString:kMSBDTitleDoubleTapRowKey]; }
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
    if ([key isEqualToString:kMSBDCCScaleKey] && !MSBDCCSizeRowShown(s.ccStyle, s.stockBar)) return YES;
    if ([ident isEqualToString:kMSBDCCGrabberRowID] && (s.ccStyle == kMSBDCCStyleMac || s.ccStyle == kMSBDCCStyleBigSurCenter)) return YES;
    if (s.desktopFailed && MSBDDesktopCheckRow(key, ident)) return YES;
    if (s.focus18Failed && ([key isEqualToString:kMSBDMacSwitcherKey] || [group isEqualToString:kMSBDMacSwitcherGroupID] || [group isEqualToString:kMSBDWiFiGroupID])) return YES;
    if ([group isEqualToString:kMSBDWindowsGroupID] && ((!s.engineWorks && !MSBDNoEngineKeepsRow(key)) || (s.stageManagerEngine && !MSBDStageManagerKeepsRow(key)))) return YES;
    if ([group isEqualToString:kMSBDNewWindowsFillGroupID] && !s.engineWorks) return YES;   // (every window it sizes is an engine's: StatusBar.x DMOpeningWindowFrame)
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
