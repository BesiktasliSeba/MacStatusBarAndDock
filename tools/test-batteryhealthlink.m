// test-batteryhealthlink.m: the link to Settings' Battery Health page at one of our groups (common/BatteryHealthLink.h, 1.7.9): the link the battery
// menu opens, the Battery page's path as Settings' own link handling needs it (the page's row by its identifier here: BATTERY_HEALTH_TITLE on 18.5),
// and where the page scrolls to show the group at its top.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <math.h>
#include "../common/BatteryHealthLink.h"
static int fails = 0;
static void check(const char *what, BOOL ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
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
    }
    if (fails) { printf("test-batteryhealthlink (compiled): FAILED\n"); return 1; }
    printf("test-batteryhealthlink (compiled): all checks pass\n"); return 0;
}
