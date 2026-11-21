// test-batteryhealthlink.m: the link to Settings' Battery Health page at one of our groups (common/BatteryHealthLink.h, 1.7.9): the link the battery
// menu opens, the Battery page's path as Settings' own link handling needs it (the page's row by its identifier here: BATTERY_HEALTH_TITLE on 18.5),
// and where the page scrolls to show the group at its top.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <math.h>
#include "../common/BatteryHealthLink.h"
static int fails = 0;
static void check(const char *what, BOOL ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
#ifdef BHL_MENU_OPEN   // (the battery menu's own DMBattOpenSettings, cut out of statusbar/BatteryMenu.h by test-batteryhealthlink.sh; DMOpenURL: what it opens)
static NSString *gOpened;
static void DMOpenURL(NSString *url, NSString *why) { gOpened = url; }
#include "bhl-open.inc"
// The path Settings' Battery page gets from a link (prefs:root=BATTERY_USAGE&path=<path>): nil when the link is not for the Battery page.
static NSString *BatteryPath(NSString *url) {
    NSArray<NSString *> *p = [url componentsSeparatedByString:@"&path="];
    return p.count == 2 && [p[0] isEqualToString:@"prefs:root=BATTERY_USAGE"] ? p[1] : nil;
}
#endif
int main(void) {
    @autoreleasepool {
        // ---- the link
        check("Charge Limit's row: prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP",
              [MSBDBatteryHealthLink(@MSBD_BH_CHARGING_GROUP) isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP"]);
        check("Sleep Guard's row: .../BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP",
              [MSBDBatteryHealthLink(@MSBD_BH_BATTERY_USE_GROUP) isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP"]);
        check("  ... no group: the page itself", [MSBDBatteryHealthLink(nil) isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH"]);

        // ---- the Battery page's path, for Settings' own handling: the page's row by its identifier here
        NSString *g = @"x";
        check("BATTERY_HEALTH/MSBD_CHARGING_GROUP on 18.5 (row BATTERY_HEALTH_TITLE): BATTERY_HEALTH_TITLE/MSBD_CHARGING_GROUP, the group kept",
              [MSBDBatteryHealthPathForRow(@"BATTERY_HEALTH/MSBD_CHARGING_GROUP", @"BATTERY_HEALTH_TITLE", &g) isEqualToString:@"BATTERY_HEALTH_TITLE/MSBD_CHARGING_GROUP"]
              && [g isEqualToString:@"MSBD_CHARGING_GROUP"]);
        check("  ... BATTERY_HEALTH alone (Apple's iPhone link): the row, no group",
              [MSBDBatteryHealthPathForRow(@"BATTERY_HEALTH", @"BATTERY_HEALTH_TITLE", &g) isEqualToString:@"BATTERY_HEALTH_TITLE"] && g == nil);
        check("  ... the row's own identifier: taken the same (the group remembered)",
              [MSBDBatteryHealthPathForRow(@"BATTERY_HEALTH_TITLE/MSBD_BATTERY_USE_GROUP", @"BATTERY_HEALTH_TITLE", &g) isEqualToString:@"BATTERY_HEALTH_TITLE/MSBD_BATTERY_USE_GROUP"]
              && [g isEqualToString:@"MSBD_BATTERY_USE_GROUP"]);
        check("  ... another version's identifier for the row (BATTERY_HEALTH itself): BATTERY_HEALTH stays",
              [MSBDBatteryHealthPathForRow(@"BATTERY_HEALTH/MSBD_CHARGING_GROUP", @"BATTERY_HEALTH", &g) isEqualToString:@"BATTERY_HEALTH/MSBD_CHARGING_GROUP"]);
        check("  ... another row of the page, a name that merely starts the same, an empty path: left as it came (nil)",
              !MSBDBatteryHealthPathForRow(@"LOW_POWER_MODE_IDENTIFIER", @"BATTERY_HEALTH_TITLE", &g) && !MSBDBatteryHealthPathForRow(@"BATTERY_HEALTHX/A", @"BATTERY_HEALTH_TITLE", &g)
              && !MSBDBatteryHealthPathForRow(@"", @"BATTERY_HEALTH_TITLE", &g) && !MSBDBatteryHealthPathForRow(nil, @"BATTERY_HEALTH_TITLE", &g) && g == nil);
        check("  ... no Battery Health row on the page (rowID nil): left as it came",
              !MSBDBatteryHealthPathForRow(@"BATTERY_HEALTH/MSBD_CHARGING_GROUP", nil, &g) && !MSBDBatteryHealthPathForRow(@"BATTERY_HEALTH", @"", &g));

        // ---- the link as Shuffle hands it on in Settings (15-17): misrouted into one of its groups, our link a second path; the link as it was sent
        check("Shuffle's System Apps route with our whole link as a second path: our link as sent (prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP)",
              [MSBDBatteryHealthLinkAsSent(@"prefs:root=System%20Apps&path=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP") isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP"]);
        check("  ... Sleep Guard's group, from any group of Shuffle's",
              [MSBDBatteryHealthLinkAsSent(@"prefs:root=Tweaks&path=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP") isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP"]);
        check("  ... the page alone too", [MSBDBatteryHealthLinkAsSent(@"prefs:root=System%20Apps&path=BATTERY_USAGE&path=BATTERY_HEALTH") isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH"]);
        check("  ... our link as it was sent (one path), a group's own route of it (one path), or Battery alone: left as it is (nil)",
              !MSBDBatteryHealthLinkAsSent(@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP") && !MSBDBatteryHealthLinkAsSent(@"prefs:root=System%20Apps&path=BATTERY_USAGE/BATTERY_HEALTH/MSBD_CHARGING_GROUP")
              && !MSBDBatteryHealthLinkAsSent(@"prefs:root=BATTERY_USAGE") && !MSBDBatteryHealthLinkAsSent(nil));
        check("  ... another page's two paths, or a name that merely starts the same: left as it is",
              !MSBDBatteryHealthLinkAsSent(@"prefs:root=Tweaks&path=Lynx&path=LOCKSCREEN") && !MSBDBatteryHealthLinkAsSent(@"prefs:root=System%20Apps&path=BATTERY_USAGE&path=BATTERY_HEALTHX")
              && !MSBDBatteryHealthLinkAsSent(@"prefs:root=System%20Apps&path=BATTERY_USAGE&path=BATTERY_HEALTH&path=X") && !MSBDBatteryHealthLinkAsSent(@"prefs:root=System%20Apps&path=GENERAL&path=BATTERY_HEALTH"));
        check("  ... the link as sent is the battery menu's own link", [MSBDBatteryHealthLinkAsSent(@"prefs:root=System%20Apps&path=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP") isEqualToString:MSBDBatteryHealthLink(@MSBD_BH_CHARGING_GROUP)]);

        // ---- the scroll: the group's top under the top inset, within what the table scrolls (numbers as a Settings window's page: inset 0 / 20)
        check("a group lower on a long page: its top at the top (500 - inset 64 = 436)", fabs(MSBDScrollOffsetForGroup(500, 64, 20, 2000, 700) - 436) < 0.001);
        check("  ... near the page's end: stops at the end (2000 + 20 - 700 = 1320)", fabs(MSBDScrollOffsetForGroup(1900, 64, 20, 2000, 700) - 1320) < 0.001);
        check("  ... a page that fits: stays at its top (-inset)", fabs(MSBDScrollOffsetForGroup(400, 64, 20, 500, 700) + 64) < 0.001);
        check("  ... the first group: the top", fabs(MSBDScrollOffsetForGroup(0, 64, 20, 2000, 700) + 64) < 0.001);

#ifdef BHL_MENU_OPEN
        // ---- 1.8.8.1 BATTSETTINGS (KT 15 Nov: "clicking battery settings in the menu should launch into the battery health settings directly"): the
        // menu's real DMBattOpenSettings. It opened prefs:root=BATTERY_USAGE, Settings > Battery.
        DMBattOpenSettings(nil, @"battery settings");
        NSString *top = gOpened;
        check("Battery Settings…: prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH, the top of Battery Health (& Charging), not Settings > Battery",
              [top isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH"] && [top isEqualToString:MSBDBatteryHealthLink(nil)]);
        DMBattOpenSettings(@MSBD_BH_CHARGING_GROUP, @"battery settings (charge limit)");
        BOOL charging = [gOpened isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_CHARGING_GROUP"];
        DMBattOpenSettings(@MSBD_BH_BATTERY_USE_GROUP, @"battery settings (sleep guard)");
        check("  ... Charge Limit and Sleep Guard as before: the same page at their groups", charging && [gOpened isEqualToString:@"prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP"]);
        // per iPadOS, as Settings gets the link on our four iPads (one link: the page is Battery Health on 15, Battery Health & Charging on 16-18, the same
        // class with Apple's title; on 18 iPadOS's own charging options are on it too): Shuffle's copy taken back where Shuffle is (15.6.1 on the M1,
        // 17.5.1), then the Battery page's row by its identifier, whichever it is (BATTERY_HEALTH_TITLE read on 18.5; BATTERY_HEALTH, Apple's iPhone
        // name), with no group: the page's top, nothing scrolled (MSBHLAwait runs only with a group).
        struct { const char *os; BOOL shuffle; } v[] = { { "15.6.1 (M1, Shuffle)", YES }, { "16.7.7 (iPad 2)", NO }, { "17.5.1 (Shuffle)", YES }, { "18.5 (A12Z)", NO } };
        for (unsigned i = 0; i < sizeof v / sizeof v[0]; i++) {
            NSString *got = v[i].shuffle ? MSBDBatteryHealthLinkAsSent([top stringByReplacingOccurrencesOfString:@"prefs:root=" withString:@"prefs:root=System%20Apps&path="]) : top;
            NSString *path = BatteryPath(got), *group = @"x", *group2 = @"x";
            NSString *row = MSBDBatteryHealthPathForRow(path, @"BATTERY_HEALTH_TITLE", &group), *row2 = MSBDBatteryHealthPathForRow(path, @"BATTERY_HEALTH", &group2);
            char what[200];
            snprintf(what, sizeof what, "  ... iPadOS %s: %sthe Battery page's Battery Health row, at its top (no group)", v[i].os, v[i].shuffle ? "Shuffle's copy taken back, then " : "");
            check(what, [got isEqualToString:top] && [path isEqualToString:@"BATTERY_HEALTH"] && [row isEqualToString:@"BATTERY_HEALTH_TITLE"] && [row2 isEqualToString:@"BATTERY_HEALTH"] && !group && !group2);
        }
        check("  ... no Battery Health row in Settings (our page not built): the link goes on as it came, Settings stays on Battery (as before)",
              !MSBDBatteryHealthPathForRow(BatteryPath(top), nil, NULL));
#endif
    }
    if (fails) { printf("test-batteryhealthlink (compiled): FAILED\n"); return 1; }
    printf("test-batteryhealthlink (compiled): all checks pass\n"); return 0;
}
