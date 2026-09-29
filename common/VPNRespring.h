// VPNRespring.h -- no respring into a hang (MacStatusBar&Dock, 2026-09-28). Aerial 5.0 makes a network call while SpringBoard starts that waits for
// an answer with no time limit. While a VPN reconnects (it does at every respring when it is on or on demand, and moments after it was turned off)
// that answer never comes: SpringBoard freezes on a black screen, the system kills it every minute, and only a reboot gets out (the M1, twice on
// 28 Sep; the stuck main thread was in Aerial.dylib both times). So a respring warns first when Aerial 5.0 will load after it and a VPN is on,
// connecting, on demand, or was turned off in the last 2 minutes. The warning has a way through (Respring Anyway: a warning, not a block).
// Where: our Apple menu and engine switch ask before (DMRespringChecked), and SpringBoard's restart gate (StatusBar.x, SBRestartManager) holds every
// other restart request -- Control Center toggles, Settings, our Settings pages, sbreload (Sileo) -- and asks there. killall is not seen.
// Aerial 3.0 has no such call. SpringBoard knows the VPN state (DMRefreshVPNState) and publishes it in a notify state.
#pragma once
#import <UIKit/UIKit.h>
#include <notify.h>
#include <time.h>
#import "EngineBuilds.h"

#define MSBD_VPNRISK_NOTE "com.besiktasliseba.vpnrespringrisk"
#define MSBD_VPNRISK_RECENT 120   // (seconds after a VPN went off in which a respring can still hang)
#define MSBD_VPNRISK_TWEAKS "/var/jb/usr/lib/TweakInject"

// SpringBoard: the state now. on = a VPN is connected, connecting or on demand; offAt = when the last one went off (0 = none since the start).
static inline void MSBDVPNRiskPublish(BOOL on, long offAt) {
    static int token = -1;
    if (token < 0 && notify_register_check(MSBD_VPNRISK_NOTE, &token) != NOTIFY_STATUS_OK) { token = -1; return; }
    notify_set_state(token, on ? UINT64_MAX : offAt > 0 ? (uint64_t)(offAt + MSBD_VPNRISK_RECENT) : 0);
}
// 0 no VPN in the way, 1 a VPN is on (or connecting, or on demand), 2 one was turned off moments ago.
static inline int MSBDVPNRisk(void) {
    int token; uint64_t v = 0;
    if (notify_register_check(MSBD_VPNRISK_NOTE, &token) != NOTIFY_STATUS_OK) return 0;
    notify_get_state(token, &v);
    notify_cancel(token);
    if (v == UINT64_MAX) return 1;
    return v > (uint64_t)time(NULL) ? 2 : 0;
}
// Aerial 5.0 loads after a respring: its library (or iCleaner's .disabled copy, which our engine switch gives back) is a 5.0 build, and no other
// installed engine was picked (the picked engine is the only one that loads; nothing picked = Aerial first, as in StatusBar.x's DMActiveEngine).
static inline BOOL MSBDVPNRiskEngineFile(NSString *lib) {
    for (NSString *ext in @[@"dylib", @"disabled"]) {
        NSString *p = [[@MSBD_VPNRISK_TWEAKS stringByAppendingPathComponent:lib] stringByAppendingPathExtension:ext];
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return YES;
    }
    return NO;
}
static inline BOOL MSBDAerial5WillLoad(void) {
    BOOL five = NO;
    for (NSString *ext in @[@"dylib", @"disabled"])
        for (NSString *uuid in MSBDDylibUUIDs([[@MSBD_VPNRISK_TWEAKS stringByAppendingPathComponent:@"Aerial"] stringByAppendingPathExtension:ext]))
            if ([MSBDEngineBuildLabel(@"Aerial", uuid) hasPrefix:@"5."]) five = YES;
    if (!five) return NO;
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("windowEngine"), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *pick = (__bridge_transfer NSString *)v;
    if (![pick isKindOfClass:[NSString class]]) return YES;
    if ([pick isEqualToString:@"off"]) return NO;   // (no windows: the engines are switched off)
    if ([pick isEqualToString:@"stagemanager"] && [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){16, 0, 0}]) return NO;   // (Stage Manager as the engine: no third-party engine loads)
    if ([pick isEqualToString:@"zetsu"]) return !MSBDVPNRiskEngineFile(@"Zetsu");
    if ([pick isEqualToString:@"milkyway"])
        return !(MSBDVPNRiskEngineFile(@"MilkyWay4") && ![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){16, 0, 0}]);
    return YES;
}
// The warning, or nil when a respring is safe. respring: does it; vpnSettings: opens Settings > General > VPN & Device Management.
static inline UIAlertController *MSBDVPNRespringAlert(void (^respring)(void), void (^vpnSettings)(void), void (^cancel)(void)) {
    int risk = MSBDVPNRisk();
    if (!risk || !MSBDAerial5WillLoad()) return nil;
    NSString *msg = risk == 1 ? @"Aerial 5.0 goes online while SpringBoard starts, and with a VPN on it can hang on a black screen."
                              : @"A VPN was just turned off. Aerial 5.0 goes online while SpringBoard starts and can hang on a black screen until the network settles. Wait a minute.";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:risk == 1 ? @"Turn Off the VPN First" : @"Respring in a Minute" message:msg preferredStyle:UIAlertControllerStyleAlert];
    if (risk == 1 && vpnSettings) [a addAction:[UIAlertAction actionWithTitle:@"VPN Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { vpnSettings(); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Respring Anyway" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { respring(); }]];
    UIAlertAction *no = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { if (cancel) cancel(); }];
    [a addAction:no];
    a.preferredAction = no;
    return a;
}
#define MSBD_VPN_SETTINGS_URL @"prefs:root=General&path=ManagedConfigurationList"   // (VPN & Device Management; path=VPN only reaches General on 15)
