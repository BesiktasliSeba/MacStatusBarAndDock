// test-shotmode.m -- Mac test of common/ShotMode.h (the debug-only screenshot mode, release-1.8.4.md item 5). Built twice by test-shotmode.sh, as a
// debug and as a release build, with MSBD_SHOT_FLAG a file the script makes ("flag" on the command line) and removes.
#import <Foundation/Foundation.h>
#include "../common/ShotMode.h"
static int fails = 0, checks = 0;
static void check(const char *what, BOOL ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
static BOOL plain(void) {
    return !MSBDShotMode() && [MSBDShotSerial(@"F9FXK2ABCD12") isEqualToString:@"F9FXK2ABCD12"] && [MSBDShotWiFiName(@"ExampleISP-5G-1234") isEqualToString:@"ExampleISP-5G-1234"]
        && [MSBDShotBTName(@"Alex's AirPods") isEqualToString:@"Alex's AirPods"];
}
int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL flag = argc > 1 && !strcmp(argv[1], "flag");
#if DEBUG
        if (!flag) check("debug build, no flag file: every value as it is", plain());
        else {
            check("debug build, the flag file there: About This iPad's serial number is a placeholder", MSBDShotMode() && [MSBDShotSerial(@"F9FXK2ABCD12") isEqualToString:@"XXXXXXXXXXXX"]);
            check("  ... Wi-Fi networks go by neutral names, the same for the same network all along",
                  [MSBDShotWiFiName(@"ExampleISP-5G-1234") isEqualToString:@"Home"] && [MSBDShotWiFiName(@"Neighbour") isEqualToString:@"Studio"]
                  && [MSBDShotWiFiName(@"ExampleISP-5G-1234") isEqualToString:@"Home"] && MSBDShotWiFiName(@"") != nil && [MSBDShotWiFiName(@"") length] == 0);
            check("  ... a Bluetooth device keeps the product word its name carries, else a numbered name",
                  [MSBDShotBTName(@"Alex's AirPods Pro") isEqualToString:@"AirPods Pro"] && [MSBDShotBTName(@"Alex Magic Keyboard") isEqualToString:@"Magic Keyboard"]
                  && [MSBDShotBTName(@"Living Room") hasPrefix:@"Bluetooth Device "] && [MSBDShotBTName(@"Living Room") isEqualToString:MSBDShotBTName(@"Living Room")]);
            check("  ... nothing of the real names is left", ![MSBDShotBTName(@"Alex's AirPods Pro") containsString:@"Alex"] && ![MSBDShotWiFiName(@"ExampleISP-5G-1234") containsString:@"ISP"]);
        }
#else
        check(flag ? "release build, even with the flag file there: every value as it is (no screenshot mode in a release)" : "release build: every value as it is", plain());
#endif
        printf("%d checks, %d failed\n", checks, fails);
        return fails ? 1 : 0;
    }
}
