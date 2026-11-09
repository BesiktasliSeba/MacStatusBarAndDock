// test-ownpagerows.m -- Mac test of common/OwnPageRows.h (1.7.9, KT: the Settings search lists only what our pages show): the index of our real
// pages (the Status Bar, Windows & Multitasking and Desktop pages' plists, the Dock page's) and, for each state the pages leave rows out in, which
// rows the search still lists -- as the pages' own code leaves them out (MSBRootListController.m -specifiers and its page notes,
// LineSwitch.h -msbd_hideRowsWhenLineOff, DMRootListController.m). test-ownpagerows <status bar Resources> <dock Resources>.
#import <Foundation/Foundation.h>
#import "../common/TweakIndex.h"
#import "../common/OwnPageRows.h"

static int gFail = 0, gN = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } }
static NSArray<MTIEntry *> *gAll;
static MTIEntry *Row(NSString *pane, NSString *title) {
    for (MTIEntry *e in gAll) if ([e.paneTitle isEqualToString:pane] && [e.title isEqualToString:title]) return e;
    return nil;
}
// Whether the row is listed in state s (and that it is in the index at all: a missing row is a failure of its own).
static BOOL Listed(MSBDOwnPages s, NSString *pane, NSString *title) {
    MTIEntry *e = Row(pane, title);
    if (!e) { gN++; gFail++; printf("  FAIL no row \"%s\" on %s in the index\n", title.UTF8String, pane.UTF8String); return NO; }
    return [MSBDOwnRowsShown(gAll, s) containsObject:e];
}
static void Shows(MSBDOwnPages s, NSString *state, NSString *pane, NSArray<NSString *> *listed, NSArray<NSString *> *left) {
    for (NSString *t in listed) Expect(Listed(s, pane, t), [NSString stringWithFormat:@"%@: %@ > %@ listed", state, pane, t]);
    for (NSString *t in left) Expect(!Listed(s, pane, t), [NSString stringWithFormat:@"%@: %@ > %@ left out", state, pane, t]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "usage: test-ownpagerows <status bar Resources> <dock Resources>\n"); return 2; }
        NSString *sb = @(argv[1]), *dock = @(argv[2]);
        MTIConfig *c = [MTIConfig new];
        c.plDirs = @[]; c.bundleDirs = @[]; c.supportDir = @"/nonexistent"; c.languages = @[@"en-US"]; c.cfVersion = 1953.1; c.maxPerPane = 400; c.maxTotal = 6000;
        c.own = @[@{@"id": @"MAC_STATUS_BAR", @"title": @"Status Bar", @"bundle": sb},
                  @{@"id": @"MAC_DESKTOP", @"title": @"Desktop", @"bundle": sb, @"plist": @"Desktop"},
                  @{@"id": @"MAC_WINDOWS", @"title": @"Windows & Multitasking", @"bundle": sb, @"plist": @"Windows"},
                  @{@"id": @"DOCK_MAGNIFICATION", @"title": @"Dock", @"bundle": dock}];
        c.extras = @[@{@"id": @"SSH_TOGGLE", @"title": @"SSH"}];
        c.ownRows = @[@{@"pane": @"BATTERY_USAGE", @"paneTitle": @"Battery", @"page": @"BATTERY_HEALTH", @"pageTitle": @"Battery Health", @"row": @"MSBD_SLEEP_GUARD",
                        @"title": @"Sleep Guard", @"group": @"Battery Use", @"link": @"BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP"}];
        gAll = MTIBuild(c);
        NSString *B = @"Status Bar", *W = @"Windows & Multitasking", *D = @"Desktop", *K = @"Dock";

        // what the index records of each row: its group, the group's stockHides, its key, whether it is below the page's line switch
        MTIEntry *e = Row(B, @"Show Seconds");
        Expect(e.stockHides && !e.groupID && [e.key isEqualToString:@"showSeconds"] && e.belowLine, @"index: Show Seconds -- a stockHides group, its key, below MacStatusBar's switch");
        e = Row(B, @"MacStatusBar");
        Expect(e && !e.belowLine && [e.path.lastObject isEqualToString:@"MSBD_LINE"], @"index: the line switch itself is not below it");
        e = Row(B, @"Report a Problem…");
        Expect([e.groupID isEqualToString:@"REPORT_GROUP"] && e.stockHides, @"index: Report a Problem in REPORT_GROUP (stockHides)");
        e = Row(W, @"Windows Behind Full-Screen Apps");
        Expect([e.groupID isEqualToString:@"WINDOWS_GROUP"] && e.stockHides && !e.belowLine, @"index: Windows & Multitasking has no line switch; WINDOWS_GROUP recorded");
        e = Row(W, @"Window Size");   // (1.8.0 item 4: a picker in the Windows group, by its key and id; the search finds it as "Window Size" and by its group)
        Expect([e.groupID isEqualToString:@"WINDOWS_GROUP"] && [e.key isEqualToString:kMSBDWindowSizeRowKey] && !e.opensPage && [e.path.lastObject isEqualToString:@"WINDOW_SIZE"]
               && [e.uid isEqualToString:@"msbd-tweaksetting:root=MAC_WINDOWS#WINDOW_SIZE"] && [e.tokens containsString:@" window "] && [e.tokens containsString:@" size "] && [e.keywords containsObject:@"Windows"],
               [NSString stringWithFormat:@"index: Window Size in the Windows group, a picker by its key (WINDOW_SIZE: %@, tokens %@)", e.uid, e.tokens]);
        e = Row(W, @"Double-Tap a Title Bar to");   // (1.8.3 item 8: a picker in the Windows group, by its key and id)
        Expect([e.groupID isEqualToString:@"WINDOWS_GROUP"] && [e.key isEqualToString:@"titleBarDoubleTap"] && !e.opensPage && [e.path.lastObject isEqualToString:@"TITLE_BAR_DOUBLE_TAP"],
               [NSString stringWithFormat:@"index: Double-Tap a Title Bar to in the Windows group, a picker by its key (TITLE_BAR_DOUBLE_TAP: %@)", e.uid]);
        e = Row(K, @"Magnify Icons"); MTIEntry *dl = Row(K, @"Mac-Style Dock");
        Expect(e.belowLine && dl && !dl.belowLine && !e.stockHides, @"index: the Dock page's rows below its Mac-Style Dock switch, the switch itself not");
        Expect(Row(D, @"Icon Size") && [Row(D, @"Icon Size").key isEqualToString:@"desktopIconSize"], @"index: the desktop's Icon Size slider, by its key");

        MSBDOwnPages base = {0};
        base.barLine = base.dockLine = base.finder = base.engineWorks = YES;   // (Aerial, everything on, no BigSurCenter, 15 / 16)
        base.ccStyle = kMSBDCCStyleStock;   // (Control Center Style: iPadOS's -- Hide Grabber, no size slider)
        base.laTimersListed = YES;          // (Live Activities' timers proven on this iPadOS: the Activities page has its Timers row)
        base.laAppsListed = YES;            // (... and other apps' activities: its Apps row)
        Shows(base, @"as installed", B, @[@"MacStatusBar", @"Show Seconds", @"Wi-Fi Menu", @"Battery Menu", @"Control Center Style", @"Hide Grabber", @"Report a Problem…", @"Banner Style"], @[@"Control Center"]);
        Shows(base, @"as installed", W, @[@"Window Size", @"Double-Tap a Title Bar to", @"New Windows Open at Fill", @"Windows Behind Full-Screen Apps", @"Tint Resize Handles", @"Home Minimizes Windows", @"Mac Switcher", @"Keep Tailspin Off", @"Prewarm Apps"],
              @[@"Resize Handles", @"Resize Apps to Fit Windows"]);
        Shows(base, @"as installed", D, @[@"Show Desktop Icons", @"Hide Desktop Icon Names", @"Icon Size", @"App Icon Corner Radius", @"Match Home Screen Icons"], @[]);
        Shows(base, @"as installed", K, @[@"Mac-Style Dock", @"Magnify Icons", @"Show Finder in Dock", @"Show Trash in Dock"], @[]);
        Expect(Listed(base, @"Battery", @"Sleep Guard") && Listed(base, @"SSH", @"SSH"), @"as installed: Sleep Guard and our main-list rows listed");
        Expect(MSBDOwnRowsShown(gAll, base).count == gAll.count - 3, [NSString stringWithFormat:@"as installed: only the three rows the pages leave out go (%lu of %lu listed)",
                                                                    (unsigned long)MSBDOwnRowsShown(gAll, base).count, (unsigned long)gAll.count]);

        MSBDOwnPages s = base; s.ccStyle = kMSBDCCStyleBigSurCenter;   // (1.8.0: the rows go with the Control Center Style)
        Shows(s, @"BigSurCenter", B, @[@"Control Center Style", @"Control Center"], @[@"Hide Grabber"]);
        s.stockBar = YES;
        Shows(s, @"BigSurCenter + stock status bar", B, @[@"Control Center Style"], @[@"Control Center", @"Hide Grabber"]);
        s = base; s.ccStyle = kMSBDCCStyleMac;   // (1.8.0, KT 3 Nov: the size slider sizes ours too)
        Shows(s, @"Mac Control Center", B, @[@"Control Center Style", @"Control Center"], @[@"Hide Grabber"]);
        Expect(MSBDCCSizeRowGreyed(kMSBDCCStyleMac, 18) && !MSBDCCSizeRowGreyed(kMSBDCCStyleMac, 17) && !MSBDCCSizeRowGreyed(kMSBDCCStyleBigSurCenter, 18) && !MSBDCCSizeRowGreyed(kMSBDCCStyleStock, 18),
               @"Control Center Size greyed only with ours on iPadOS 18 (not sized there yet), never with BigSurCenter");
        Expect(MSBDCCSizeRowShown(kMSBDCCStyleMac, NO) && !MSBDCCSizeRowShown(kMSBDCCStyleMac, YES) && MSBDCCSizeRowShown(kMSBDCCStyleBigSurCenter, NO) && !MSBDCCSizeRowShown(kMSBDCCStyleStock, NO) && !MSBDCCSizeRowShown(kMSBDCCStyleNone, NO),
               @"  ... shown with BigSurCenter or ours on our status bar, never with iPadOS's");
        s = base; s.ccStyle = kMSBDCCStyleNone;   // (not known: both as before the style -- Hide Grabber shown, no size slider)
        Shows(s, @"Control Center Style not known", B, @[@"Hide Grabber"], @[@"Control Center"]);
        e = Row(B, @"Control Center Style");
        Expect([e.groupID isEqualToString:@"CC_GROUP"] && [e.key isEqualToString:@"controlCenterStyle"] && !e.opensPage && [e.path.lastObject isEqualToString:@"CC_STYLE"],
               @"index: Control Center Style in the Control Center group, a picker by its key (CC_STYLE)");
        Expect([Row(B, @"Hide Grabber").path.lastObject isEqualToString:@"CC_GRABBER"], @"index: Hide Grabber by its id (CC_GRABBER)");

        s = base; s.stockBar = YES;   // (the stockHides groups go; Report a Problem stays in a group of its own)
        Shows(s, @"stock status bar", B, @[@"MacStatusBar", @"Status Bar Style", @"Banner Style", @"Finder", @"Hide Grabber", @"Report a Problem…", @"Hide Status Bar on Lock Screen"],
              @[@"Show Seconds", @"Show Spotlight Search", @"Tweak Settings", @"Menu Bar Size", @"Apps", @"Show in App Library", @"Wi-Fi Menu", @"Battery Menu", @"Mix Audio Between Apps"]);
        Shows(s, @"stock status bar", W, @[@"Keep Tailspin Off"], @[@"Enable Windowing", @"Window Engine", @"Window Size", @"Double-Tap a Title Bar to", @"Home Minimizes Windows", @"Mac Switcher", @"Prewarm Apps", @"Tint Resize Handles"]);
        // (1.8.4: the Activities page opens from a group the stock status bar hides: its rows go with it -- the index gives a page's rows the
        //  stockHides of the group its link is in)
        Shows(s, @"stock status bar", B, @[], @[@"Live Activities in Menu Bar", @"Activities", @"Now Playing", @"Timers", @"Calls"]);
        Expect(Row(B, @"Calls").stockHides && [Row(B, @"Calls").groupID isEqualToString:@"LIVE_ACTIVITIES_KINDS"],
               @"index: the Activities page's rows carry the stockHides of the group their page opens from (their own group's id kept)");
        Shows(s, @"stock status bar", D, @[@"Show Desktop Icons", @"Icon Size"], @[]);
        Shows(s, @"stock status bar", K, @[@"Magnify Icons"], @[]);

        s = base; s.barLine = NO;   // (MacStatusBar off: its switch; Windows & Multitasking's note and Keep Tailspin Off; the Desktop page's note)
        Shows(s, @"MacStatusBar off", B, @[@"MacStatusBar"], @[@"Status Bar Style", @"Show Seconds", @"Finder", @"Report a Problem…", @"Hide Status Bar on Lock Screen"]);
        Shows(s, @"MacStatusBar off", W, @[@"Keep Tailspin Off"], @[@"Enable Windowing", @"Window Size", @"Double-Tap a Title Bar to", @"Home Minimizes Windows", @"Mac Switcher", @"Prewarm Apps"]);
        Shows(s, @"MacStatusBar off", D, @[], @[@"Show Desktop Icons", @"Hide Desktop Icon Names", @"Icon Size", @"App Icon Corner Radius"]);
        Shows(s, @"MacStatusBar off", K, @[@"Mac-Style Dock", @"Magnify Icons"], @[]);
        Expect(Listed(s, W, W) && Listed(s, D, D), @"MacStatusBar off: the pages themselves still listed (each opens, with its note)");

        s = base; s.dockLine = NO;
        Shows(s, @"Mac-Style Dock off", K, @[@"Mac-Style Dock"], @[@"Magnify Icons", @"Number of Recent Apps", @"Show Finder in Dock", @"Show Downloads in Dock", @"Show Trash in Dock"]);
        Shows(s, @"Mac-Style Dock off", B, @[@"Show Seconds"], @[]);

        s = base; s.finder = NO;
        Shows(s, @"Finder off", K, @[@"Magnify Icons", @"Show Trash in Dock"], @[@"Show Finder in Dock"]);
        Shows(s, @"Finder off", B, @[@"Finder"], @[]);
        Shows(s, @"Finder off", D, @[@"Show Desktop Icons"], @[]);   // (greyed on the page, not left out)

        s = base; s.desktopFailed = YES;   // (17+: the desktop's check failed)
        Shows(s, @"desktop check failed", D, @[], @[@"Show Desktop Icons", @"Hide Desktop Icon Names", @"Icon Size", @"App Icon Corner Radius", @"Match Home Screen Icons"]);
        Shows(s, @"desktop check failed", W, @[@"Mac Switcher"], @[]);
        s.focus18Failed = YES;             // (18 without SpringBoard's typed keyboard focus lock: no Mac Switcher, no Wi-Fi Menu either)
        Shows(s, @"18 without the focus lock", W, @[@"Home Minimizes Windows"], @[@"Mac Switcher", @"Go to the App's Desktop"]);
        Shows(s, @"18 without the focus lock", B, @[@"Battery Menu"], @[@"Wi-Fi Menu"]);

        s = base; s.stageManagerEngine = YES;   // (Stage Manager as the engine: the Windows group keeps the rows of Stage Manager's own windows -- the resize
                                                //  handles', Window Size and Double-Tap a Title Bar to: GitHub #11, it was left out of the page and the search)
        Shows(s, @"Stage Manager engine", W, @[@"Window Size", @"Double-Tap a Title Bar to", @"Resize Handles", @"Tint Resize Handles", @"Home Minimizes Windows", @"New Windows Open at Fill"],
              @[@"Windows Behind Full-Screen Apps", @"Resize Apps to Fit Windows"]);
        Expect(MSBDStageManagerKeepsRow(@"titleBarDoubleTap") && MSBDStageManagerKeepsRow(@"windowSize") && MSBDStageManagerKeepsRow(@"resizeHandleStyle")
               && MSBDStageManagerKeepsRow(@"tintResizeHandles") && !MSBDStageManagerKeepsRow(@"windowsBehindApps") && !MSBDStageManagerKeepsRow(nil),
               @"Stage Manager keeps the Windows group's rows its own windows use (Window Size, Double-Tap a Title Bar to, the handles'), not Windows Behind Full-Screen Apps (the other engines' window layer's)");
        {   // (every row of the real Windows group decided on purpose for Stage Manager: a row added there later fails here until it is)
            NSArray<MTIEntry *> *shown = MSBDOwnRowsShown(gAll, s);
            NSMutableArray<NSString *> *kept = [NSMutableArray array], *left = [NSMutableArray array];
            for (MTIEntry *r in gAll) if (r.ours && r.depth >= 2 && [r.paneTitle isEqualToString:W] && [r.groupID isEqualToString:@"WINDOWS_GROUP"]) [[shown containsObject:r] ? kept : left addObject:r.title];
            Expect([kept isEqualToArray:@[@"Window Size", @"Double-Tap a Title Bar to", @"Resize Handles", @"Tint Resize Handles"]] && [left isEqualToArray:@[@"Windows Behind Full-Screen Apps"]],
                   [NSString stringWithFormat:@"Stage Manager engine: each row of the Windows group kept or left out on purpose (kept %@; left out %@)", [kept componentsJoinedByString:@", "], [left componentsJoinedByString:@", "]]);
        }
        s = base; s.engineWorks = NO;           // (no tested engine installed, or it runs on its own: the Windows group goes but for Double-Tap a Title Bar to,
                                                //  which our own windows -- Finder, TextEdit -- use without an engine too; 1.8.3.1)
        Shows(s, @"no working engine", W, @[@"Window Engine", @"Double-Tap a Title Bar to", @"Home Minimizes Windows"], @[@"Window Size", @"Windows Behind Full-Screen Apps", @"Tint Resize Handles", @"Resize Handles"]);
        Shows(s, @"no working engine", W, @[], @[@"New Windows Open at Fill"]);   // (every window it sizes is an engine's: nothing to fill -- audit 1.8.3 M4)
        {   // (every row of the real Windows group decided on purpose with no working engine)
            NSArray<MTIEntry *> *shown = MSBDOwnRowsShown(gAll, s);
            NSMutableArray<NSString *> *kept = [NSMutableArray array], *left = [NSMutableArray array];
            for (MTIEntry *r in gAll) if (r.ours && r.depth >= 2 && [r.paneTitle isEqualToString:W] && [r.groupID isEqualToString:@"WINDOWS_GROUP"]) [[shown containsObject:r] ? kept : left addObject:r.title];
            Expect([kept isEqualToArray:@[@"Double-Tap a Title Bar to"]] && [left isEqualToArray:@[@"Window Size", @"Windows Behind Full-Screen Apps", @"Resize Handles", @"Tint Resize Handles"]],
                   [NSString stringWithFormat:@"no working engine: each row of the Windows group kept or left out on purpose (kept %@; left out %@)", [kept componentsJoinedByString:@", "], [left componentsJoinedByString:@", "]]);
        }
        s.stageManagerEngine = YES;             // (Stage Manager shown but not working: the same, our own windows' row stays)
        Shows(s, @"Stage Manager, not working", W, @[@"Double-Tap a Title Bar to"], @[@"Window Size", @"Windows Behind Full-Screen Apps", @"Tint Resize Handles", @"New Windows Open at Fill"]);
        s = base; s.milkyWayEngine = YES;       // (MilkyWay4, 15 only)
        Shows(s, @"MilkyWay4", W, @[@"Window Size", @"Double-Tap a Title Bar to", @"Resize Apps to Fit Windows", @"Windows Behind Full-Screen Apps"], @[@"Resize Handles"]);

        s = base; s.laTimersListed = NO;   // (1.8.4, review P2-L3: this iPadOS not in Live Activities' timers list -- every version but the device pass's)
        e = Row(B, @"Timers");
        Expect(e && e.depth == 3 && [e.path.firstObject isEqualToString:@"LIVE_ACTIVITIES_PAGE"] && [e.key isEqualToString:kMSBDLATimersRowKey], @"index: the Activities page's Timers, by its key, on its page");
        Shows(s, @"timers not listed", B, @[@"Live Activities in Menu Bar", @"Activities", @"Now Playing", @"Calls"], @[@"Timers"]);
        Expect(MSBDOwnRowsShown(gAll, s).count == MSBDOwnRowsShown(gAll, base).count - 1, @"timers not listed: only the Timers row goes");
        Shows(base, @"timers listed", B, @[@"Timers"], @[]);
        // (KT's yes, 7 Nov: the builds the device pass proved show the Timers row, every other one leaves it out -- the list the page and the search read)
        s = base; s.laTimersListed = MSBDLATimersListed(17, 5, 1) != 0;
        Shows(s, @"17.5.1 (proved on the 17.5)", B, @[@"Timers", @"Now Playing", @"Calls"], @[]);
        s = base; s.laTimersListed = MSBDLATimersListed(18, 5, 0) != 0;
        Shows(s, @"18.5 (proved on the A12Z)", B, @[@"Timers", @"Now Playing", @"Calls"], @[]);
        s = base; s.laTimersListed = MSBDLATimersListed(16, 7, 7) != 0;
        Shows(s, @"16.7.7 (not listed: no +isActiveTimer:)", B, @[@"Now Playing", @"Calls"], @[@"Timers"]);
        s = base; s.laTimersListed = MSBDLATimersListed(17, 6, 1) != 0;
        Shows(s, @"17.6.1 (not tested)", B, @[@"Now Playing", @"Calls"], @[@"Timers"]);
        s = base; s.laTimersListed = MSBDLATimersListed(18, 5, 1) != 0;
        Shows(s, @"18.5.1 (not tested)", B, @[@"Now Playing", @"Calls"], @[@"Timers"]);
        MTIEntry *appsRow = nil;   // (the Activities page's Apps -- the Status Bar page has another row called Apps, the Go menu's)
        for (MTIEntry *x in gAll) if ([x.paneTitle isEqualToString:B] && [x.title isEqualToString:@"Apps"] && [x.path.firstObject isEqualToString:@"LIVE_ACTIVITIES_PAGE"]) appsRow = x;
        Expect(appsRow && [appsRow.key isEqualToString:kMSBDLAAppsRowKey], @"index: the Activities page's Apps, by its key, on its page");
        s = base; s.laAppsListed = NO;    // (other apps' activities not listed: every version until the device pass; 15/16 always)
        Expect(appsRow && ![MSBDOwnRowsShown(gAll, s) containsObject:appsRow] && [MSBDOwnRowsShown(gAll, base) containsObject:appsRow], @"apps not listed: the Activities page's Apps left out (listed: shown)");
        Expect(MSBDOwnRowsShown(gAll, s).count == MSBDOwnRowsShown(gAll, base).count - 1, @"apps not listed: only that row goes (the Go menu's Apps stays)");

        s = base; s.batteryUseOff = YES;
        Expect(!Listed(s, @"Battery", @"Sleep Guard") && Listed(s, B, @"Battery Menu"), @"our Battery Use group not on Battery Health: Sleep Guard left out, nothing else");

        // other tweaks' rows are never touched, whatever the state (a row of another tweak with the same page and group names)
        MTIEntry *other = [MTIEntry new];
        other.paneID = @"MAC_WINDOWS"; other.paneTitle = @"Other"; other.title = @"Other Row"; other.depth = 2; other.path = @[@"X"]; other.groupID = @"WINDOWS_GROUP"; other.stockHides = YES; other.ours = NO;
        MSBDOwnPages worst = {0};
        NSArray *alone = @[other];
        Expect(MSBDOwnRowsShown(alone, worst) == alone, @"another tweak's row: as it is (and a list with nothing left out is handed back itself)");
        Expect(!MSBDOwnRowHidden(worst, @"HOME_SCREEN_DOCK", @"WINDOWS_GROUP", YES, @"showSeconds", @"FINDER", YES), @"a row on a page that is not ours: never left out by the rule");
        printf("test-ownpagerows: %d/%d passed (%lu rows of our pages)\n", gN - gFail, gN, (unsigned long)gAll.count);
    }
    return gFail ? 1 : 0;
}
