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
        e = Row(K, @"Magnify Icons"); MTIEntry *dl = Row(K, @"MacDock");
        Expect(e.belowLine && dl && !dl.belowLine && !e.stockHides, @"index: the Dock page's rows below MacDock's switch, the switch itself not");
        Expect(Row(D, @"Icon Size") && [Row(D, @"Icon Size").key isEqualToString:@"desktopIconSize"], @"index: the desktop's Icon Size slider, by its key");

        MSBDOwnPages base = {0};
        base.barLine = base.dockLine = base.finder = base.engineWorks = YES;   // (Aerial, everything on, no BigSurCenter, 15 / 16)
        Shows(base, @"as installed", B, @[@"MacStatusBar", @"Show Seconds", @"Wi-Fi Menu", @"Battery Menu", @"Hide Grabber", @"Report a Problem…", @"Mac-Style Banners"], @[@"Control Center"]);
        Shows(base, @"as installed", W, @[@"Windows Behind Full-Screen Apps", @"Tint Resize Handles", @"Home Minimizes Windows", @"Mac Switcher", @"Keep Tailspin Off", @"Prewarm Apps"],
              @[@"Resize Handles", @"Resize Apps to Fit Windows"]);
        Shows(base, @"as installed", D, @[@"Show Desktop Icons", @"Hide Desktop Icon Names", @"Icon Size", @"App Icon Corner Radius", @"Match Home Screen Icons"], @[]);
        Shows(base, @"as installed", K, @[@"MacDock", @"Magnify Icons", @"Show Finder in Dock", @"Show Trash in Dock"], @[]);
        Expect(Listed(base, @"Battery", @"Sleep Guard") && Listed(base, @"SSH", @"SSH"), @"as installed: Sleep Guard and our main-list rows listed");
        Expect(MSBDOwnRowsShown(gAll, base).count == gAll.count - 3, [NSString stringWithFormat:@"as installed: only the three rows the pages leave out go (%lu of %lu listed)",
                                                                    (unsigned long)MSBDOwnRowsShown(gAll, base).count, (unsigned long)gAll.count]);

        MSBDOwnPages s = base; s.bigSurCenter = YES;
        Shows(s, @"BigSurCenter", B, @[@"Control Center"], @[]);
        s.stockBar = YES;
        Shows(s, @"BigSurCenter + stock status bar", B, @[], @[@"Control Center"]);

        s = base; s.stockBar = YES;   // (the stockHides groups go; Report a Problem stays in a group of its own)
        Shows(s, @"stock status bar", B, @[@"MacStatusBar", @"Status Bar Style", @"Mac-Style Banners", @"Finder", @"Hide Grabber", @"Report a Problem…", @"Hide Status Bar on Lock Screen"],
              @[@"Show Seconds", @"Show Spotlight Search", @"Tweak Settings", @"Menu Bar Size", @"Apps", @"Show in App Library", @"Wi-Fi Menu", @"Battery Menu", @"Mix Audio Between Apps"]);
        Shows(s, @"stock status bar", W, @[@"Keep Tailspin Off"], @[@"Enable Windowing", @"Window Engine", @"Home Minimizes Windows", @"Mac Switcher", @"Prewarm Apps", @"Tint Resize Handles"]);
        Shows(s, @"stock status bar", D, @[@"Show Desktop Icons", @"Icon Size"], @[]);
        Shows(s, @"stock status bar", K, @[@"Magnify Icons"], @[]);

        s = base; s.barLine = NO;   // (MacStatusBar off: its switch; Windows & Multitasking's note and Keep Tailspin Off; the Desktop page's note)
        Shows(s, @"MacStatusBar off", B, @[@"MacStatusBar"], @[@"Status Bar Style", @"Show Seconds", @"Finder", @"Report a Problem…", @"Hide Status Bar on Lock Screen"]);
        Shows(s, @"MacStatusBar off", W, @[@"Keep Tailspin Off"], @[@"Enable Windowing", @"Home Minimizes Windows", @"Mac Switcher", @"Prewarm Apps"]);
        Shows(s, @"MacStatusBar off", D, @[], @[@"Show Desktop Icons", @"Hide Desktop Icon Names", @"Icon Size", @"App Icon Corner Radius"]);
        Shows(s, @"MacStatusBar off", K, @[@"MacDock", @"Magnify Icons"], @[]);
        Expect(Listed(s, W, W) && Listed(s, D, D), @"MacStatusBar off: the pages themselves still listed (each opens, with its note)");

        s = base; s.dockLine = NO;
        Shows(s, @"MacDock off", K, @[@"MacDock"], @[@"Magnify Icons", @"Number of Recent Apps", @"Show Finder in Dock", @"Show Downloads in Dock", @"Show Trash in Dock"]);
        Shows(s, @"MacDock off", B, @[@"Show Seconds"], @[]);

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

        s = base; s.stageManagerEngine = YES;   // (Stage Manager as the engine: the Windows group keeps the resize handles' rows)
        Shows(s, @"Stage Manager engine", W, @[@"Resize Handles", @"Tint Resize Handles", @"Home Minimizes Windows"], @[@"Windows Behind Full-Screen Apps", @"Resize Apps to Fit Windows"]);
        s = base; s.engineWorks = NO;           // (no tested engine installed, or it runs on its own)
        Shows(s, @"no working engine", W, @[@"Window Engine", @"Home Minimizes Windows"], @[@"Windows Behind Full-Screen Apps", @"Tint Resize Handles", @"Resize Handles"]);
        s = base; s.milkyWayEngine = YES;       // (MilkyWay4, 15 only)
        Shows(s, @"MilkyWay4", W, @[@"Resize Apps to Fit Windows", @"Windows Behind Full-Screen Apps"], @[@"Resize Handles"]);

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
