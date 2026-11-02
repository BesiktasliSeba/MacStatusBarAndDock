// test-batteryhealth.c -- Mac test of the figures our Battery Health page shows (common/BatteryHealthFigures.h, used by macsettings/BatteryHealth.x):
// Maximum Capacity from the battery service on the four iPads (read 1 Nov 2026), the edge cases, and Apple's own answers kept where it has them.
#include <stdio.h>
#include "../common/BatteryHealthFigures.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int got, int want) { checks++; if (got != want) { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } else printf("PASS  %s\n", what); }
int main(void) {
    Expect("M1 (NominalChargeCapacity 7044 / DesignCapacity 7596): 93 %", MSBDBatteryHealthPercent(7044, 6942, 7596), 93);
    Expect("iPad 2 (6476 / 7161 = 90.4 %): 91 %, rounded up as Apple's page does", MSBDBatteryHealthPercent(6476, 6079, 7161), 91);
    Expect("17.5 (9589 / 10762 = 89.1 %): 90 %, what Apple's page showed for it on 17.5.1", MSBDBatteryHealthPercent(9589, 9318, 10762), 90);
    Expect("A12Z (8444 / 9633): 88 %", MSBDBatteryHealthPercent(8444, 8254, 9633), 88);
    Expect("no NominalChargeCapacity: AppleRawMaxCapacity (6942 / 7596 = 91.4 %): 92 %", MSBDBatteryHealthPercent(0, 6942, 7596), 92);
    Expect("rounded up: 7555 / 7596 = 99.46 % -> 100", MSBDBatteryHealthPercent(7555, 0, 7596), 100);
    Expect("just under a whole percent: 6684 / 7596 = 87.99 % -> 88", MSBDBatteryHealthPercent(6684, 0, 7596), 88);
    Expect("exactly 88 % stays 88 (not 89)", MSBDBatteryHealthPercent(8800, 0, 10000), 88);
    Expect("a new battery above its design capacity: never above 100", MSBDBatteryHealthPercent(8043, 8043, 7596), 100);
    Expect("no design capacity: no figure", MSBDBatteryHealthPercent(7044, 6942, 0), -1);
    Expect("no full-charge capacity at all: no figure", MSBDBatteryHealthPercent(0, 0, 7596), -1);
    Expect("negative readings (-1 = not read): no figure", MSBDBatteryHealthPercent(-1, -1, 7596), -1);
    Expect("an absurd ratio (a wrong design capacity, 3x): no figure", MSBDBatteryHealthPercent(9000, 9000, 3000), -1);
    Expect("Apple's service state when it has one (2) stays", MSBDBatteryHealthServiceState(2, 93), 2);
    Expect("Apple's 0 stays", MSBDBatteryHealthServiceState(0, 93), 0);
    Expect("iPad: Apple has none (-1), we have a figure: normal (0)", MSBDBatteryHealthServiceState(-1, 93), 0);
    Expect("iPad: neither has a figure: Apple's -1 (\"unable to determine\") stays", MSBDBatteryHealthServiceState(-1, -1), -1);
    Expect("battery check: Apple's 1 stays", MSBDBatteryGenuineStatus(1, 93), 1);
    Expect("battery check: Apple's 2 (unverified battery) stays", MSBDBatteryGenuineStatus(2, 93), 2);
    Expect("battery check: iPad, never answered (0), we have a figure: 1 (no spinner forever)", MSBDBatteryGenuineStatus(0, 93), 1);
    Expect("battery check: never answered and no figure: 0 stays", MSBDBatteryGenuineStatus(0, -1), 0);
    Expect("management state: Apple's own (the M1's 4) stays", MSBDBatteryManagementState(4, 93), 4);
    Expect("management state: iPad's 0 (= \"no battery data\", a spinner) with a figure: 2, the normal state", MSBDBatteryManagementState(0, 93), 2);
    Expect("management state: 0 and no figure: 0 stays", MSBDBatteryManagementState(0, -1), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
