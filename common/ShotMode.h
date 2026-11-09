// ShotMode.h -- screenshots for the Sileo depiction, the README and Havoc (KT 7 Nov, release-1.8.4.md item 5). In debug builds only, with the flag
// file there (touch /tmp/msb-shotmode; gone, it is off), our UI shows nothing personal: About This iPad's serial number is a placeholder, and Wi-Fi
// networks and Bluetooth devices go by neutral names, each the same all along (a product word a device's name carries is kept: "Alex's AirPods" ->
// "AirPods"). Our UI never shows the iPad's own name: About This iPad shows its model, Finder says "On My iPad". Release builds have none of it:
// the helpers give the real value and the flag's path is not compiled in (tools/verify-release.sh counts it as test machinery).
#pragma once
#import <Foundation/Foundation.h>
#include <unistd.h>

#if DEBUG
#ifndef MSBD_SHOT_FLAG
#define MSBD_SHOT_FLAG "/tmp/msb-shotmode"
#endif
static inline BOOL MSBDShotMode(void) { return access(MSBD_SHOT_FLAG, F_OK) == 0; }
// About This iPad's serial number, as shown.
static inline NSString *MSBDShotSerial(NSString *real) { return MSBDShotMode() ? @"XXXXXXXXXXXX" : real; }
// A Wi-Fi network's name, as shown: the first one met (mostly the current network) is "Home", then "Studio", "Office", ..., then "Network N".
static inline NSString *MSBDShotWiFiName(NSString *real) {
    if (!MSBDShotMode() || !real.length) return real;
    static NSMutableDictionary<NSString *, NSString *> *names;
    if (!names) names = [NSMutableDictionary dictionary];
    NSString *n = names[real];
    if (!n) {
        NSArray<NSString *> *pool = @[@"Home", @"Studio", @"Office", @"Library", @"Guest", @"Cafe"];
        n = names.count < pool.count ? pool[names.count] : [NSString stringWithFormat:@"Network %lu", (unsigned long)names.count + 1];
        names[real] = n;
    }
    return n;
}
// A Bluetooth device's name, as shown: the product word it carries, else "Bluetooth Device N" (a second device of the same word gets its number).
static inline NSString *MSBDShotBTName(NSString *real) {
    if (!MSBDShotMode() || !real.length) return real;
    static NSMutableDictionary<NSString *, NSString *> *names;
    if (!names) names = [NSMutableDictionary dictionary];
    NSString *n = names[real];
    if (!n) {
        NSString *word = nil;
        for (NSString *w in @[@"AirPods Pro", @"AirPods Max", @"AirPods", @"Magic Keyboard", @"Magic Mouse", @"Magic Trackpad", @"Apple Pencil",
                              @"Keyboard", @"Mouse", @"Trackpad", @"Headphones", @"Speaker", @"Watch", @"iPhone", @"iPad", @"Mac"])
            if ([real rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) { word = w; break; }
        n = word ?: [NSString stringWithFormat:@"Bluetooth Device %lu", (unsigned long)names.count + 1];
        if ([names.allValues containsObject:n]) n = [NSString stringWithFormat:@"%@ %lu", n, (unsigned long)names.count + 1];
        names[real] = n;
    }
    return n;
}
#else
static inline BOOL MSBDShotMode(void) { return NO; }
static inline NSString *MSBDShotSerial(NSString *real) { return real; }
static inline NSString *MSBDShotWiFiName(NSString *real) { return real; }
static inline NSString *MSBDShotBTName(NSString *real) { return real; }
#endif
