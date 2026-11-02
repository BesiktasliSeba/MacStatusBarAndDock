// test-batteryuse.m: where macsettings/BatteryUse.x puts the Battery Use group in the Battery Health page's list (MSBUInsertIndex, taken out by
// test-batteryuse.sh), against stand-in specifiers: after our Charging group's rows when the Charge Limit's job adds one, else after the Cycle
// Count row, else at the end; and the group only once (MSBUHasGroup).
#import <Foundation/Foundation.h>
#include <stdio.h>
@interface PSSpecifier : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) long long cellType;
@end
@implementation PSSpecifier
@end
enum { kMSBUCellGroup = 0, kMSBUCellSwitch = 6, kMSBUCellTitleValue = 4 };
#include "insert.inc"
static PSSpecifier *S(NSString *ident, long long type) { PSSpecifier *s = [PSSpecifier new]; s.identifier = ident; s.cellType = type; return s; }
static int fails = 0;
static void check(const char *what, BOOL ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    @autoreleasepool {
        // Apple's page (17/18 path): header group, Maximum Capacity group + row, our Cycle Count group + row, (Charging group + rows), the rest
        NSArray *base = @[S(@"ABOUT", 0), S(@"CAPACITY_GROUP", 0), S(@"MAX_CAPACITY", 4), S(@"MSBD_CYCLE_COUNT_GROUP", 0), S(@"MSBD_CYCLE_COUNT", 4)];
        NSMutableArray *withCharging = [base mutableCopy];
        [withCharging addObjectsFromArray:@[S(@"MSBD_CHARGING_GROUP", 0), S(@"MSBD_CHARGE_LIMIT", 2), S(@"MSBD_CHARGE_FULL_NOW", 13), S(@"APPLE_LAST", 0), S(@"X", 4)]];
        check("with the Charging group: right after its rows (Charge Limit, Charge to Full Now), before Apple's next group",
              MSBUInsertIndex(withCharging) == 8);
        NSMutableArray *chargeOnlyLimit = [base mutableCopy];
        [chargeOnlyLimit addObjectsFromArray:@[S(@"MSBD_CHARGING_GROUP", 0), S(@"MSBD_CHARGE_LIMIT", 2)]];
        check("  ... the Charging group last on the page: at the end, after its row", MSBUInsertIndex(chargeOnlyLimit) == 7);
        NSMutableArray *noCharging = [base mutableCopy]; [noCharging addObjectsFromArray:@[S(@"APPLE_LAST", 0)]];
        check("no Charging group (no job): after the Cycle Count row", MSBUInsertIndex(noCharging) == 5);
        NSArray *bare = @[S(@"ABOUT", 0), S(@"CAPACITY_GROUP", 0), S(@"MAX_CAPACITY", 4)];
        check("neither (no cycle count figure): at the end", MSBUInsertIndex(bare) == 3);
        check("an empty list: index 0", MSBUInsertIndex(@[]) == 0);
        NSMutableArray *already = [noCharging mutableCopy]; [already addObject:S(@"MSBD_BATTERY_USE_GROUP", 0)];
        check("the group in the list already: found (not put in twice)", MSBUHasGroup(already) && !MSBUHasGroup(noCharging));
    }
    if (fails) { printf("test-batteryuse (compiled): FAILED\n"); return 1; }
    printf("test-batteryuse (compiled): all checks pass\n"); return 0;
}
