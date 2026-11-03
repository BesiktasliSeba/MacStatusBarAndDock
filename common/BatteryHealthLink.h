// BatteryHealthLink.h -- a link straight to Settings > Battery > Battery Health (Battery Health & Charging from 16), the page our Settings part
// opens on iPad (macsettings/BatteryHealth.x), at one of our groups on it (1.7.9, KT 2 Nov: the battery menu's Charge Limit and Sleep Guard rows).
// prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH[/<group>]: BATTERY_HEALTH is the page's name in Apple's own iPhone link; on iPad Settings stayed on
// Battery with it (16.7.7, 18.5), as the page's row there has another identifier (BATTERY_HEALTH_TITLE on 18.5, in a group BATTERY_HEALTH_ID).
// Settings' Battery page takes the link to its row, whatever its identifier is (macsettings/BatteryHealthLink.x), and the Battery Health page shows
// the group asked for at its top. Plain Foundation, Mac-tested (tools/test-batteryhealthlink.sh).
#pragma once
#import <Foundation/Foundation.h>

#define MSBD_BH_PAGE "BATTERY_HEALTH"                  // (the page in the link)
#define MSBD_BH_CHARGING_GROUP "MSBD_CHARGING_GROUP"    // (our groups on it: the Charge Limit's -- BatteryHealth.x, where the job is installed --
#define MSBD_BH_BATTERY_USE_GROUP "MSBD_BATTERY_USE_GROUP"   //  and Sleep Guard's, BatteryUse.x)

// The link: the page, at a group of it (nil: its top).
static inline NSString *MSBDBatteryHealthLink(NSString *group) {
    return [@"prefs:root=BATTERY_USAGE&path=" MSBD_BH_PAGE stringByAppendingString:group.length ? [@"/" stringByAppendingString:group] : @""];
}
// A link's path on the Battery page as Settings' own handling needs it: when its first part names the Battery Health page -- BATTERY_HEALTH, or the
// row's own identifier (rowID: the row whose page is Battery Health, as the page lists it) --, the row's identifier and the rest ("BATTERY_HEALTH_TITLE/
// MSBD_CHARGING_GROUP"); nil for any other path, or when the page has no such row (rowID nil): the link goes on as it came. *group: the rest.
static inline NSString *MSBDBatteryHealthPathForRow(NSString *path, NSString *rowID, NSString **group) {
    if (group) *group = nil;
    if (![path isKindOfClass:[NSString class]] || ![rowID isKindOfClass:[NSString class]] || !rowID.length) return nil;
    NSRange slash = [path rangeOfString:@"/"];
    NSString *first = slash.location == NSNotFound ? path : [path substringToIndex:slash.location];
    NSString *rest = slash.location == NSNotFound ? @"" : [path substringFromIndex:slash.location + 1];
    if (![first isEqualToString:@MSBD_BH_PAGE] && ![first isEqualToString:rowID]) return nil;
    if (group) *group = rest.length ? rest : nil;
    return rest.length ? [NSString stringWithFormat:@"%@/%@", rowID, rest] : rowID;
}
// Our link as Shuffle hands it on in Settings (15-17; KT's 17.5, 2 Nov). Shuffle's rewrite (in the one-argument -[PreferencesAppController
// processURL:]) does not expect a path in the link (macsettings/TweakSearch.x met it with Lynx's pages): it routed ours into one of its groups,
// with our whole link as a path of its own -- prefs:root=System%20Apps&path=BATTERY_USAGE&path=BATTERY_HEALTH/<group> -- and Settings stopped on
// that group's page. Battery is not in that group: it is in the main list there, and "Battery Settings…", the page alone, came through untouched
// and opened Battery. The link as it was sent: prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH[/<group>]; where Battery really is, is then
// Shuffle's own answer for the page alone (TweakSearch.x MTSShuffleRoute, as for the Settings search's results). nil for any other URL (one
// path, or not our link).
static inline NSString *MSBDBatteryHealthLinkAsSent(NSString *url) {
    if (![url isKindOfClass:[NSString class]] || ![url hasPrefix:@"prefs:root="]) return nil;
    NSArray<NSString *> *parts = [url componentsSeparatedByString:@"&path="];
    if (parts.count != 3 || ![parts[1] isEqualToString:@"BATTERY_USAGE"]) return nil;
    if (![parts[2] isEqualToString:@MSBD_BH_PAGE] && ![parts[2] hasPrefix:@MSBD_BH_PAGE "/"]) return nil;
    return [@"prefs:root=BATTERY_USAGE&path=" stringByAppendingString:parts[2]];
}
// Where a table scrolls so that a group starts at the top of what shows (its header under the top inset): the group's top, kept within what the
// table can scroll (a page that fits does not move; one near its end stops at its end).
static inline double MSBDScrollOffsetForGroup(double groupTop, double insetTop, double insetBottom, double contentHeight, double viewHeight) {
    double minY = -insetTop, maxY = contentHeight + insetBottom - viewHeight;
    if (maxY < minY) maxY = minY;
    double y = groupTop - insetTop;
    return y < minY ? minY : (y > maxY ? maxY : y);
}
