// CCStyleNow.h -- Control Center Style on the iPad (1.8.0): what common/CCStyle.h's rule is given, read the same way by Settings, SpringBoard and
// the Settings search (as mobile) and the root helper (as root, for mobile): the stored style, BigSurCenter's library and whether the user switched
// it off themselves (common/ExclusiveChoice.h), our own Control Center's verdict on this build and Status Bar Style. Foundation.
//  - The verdict is the panel's (common/CCMacCheck.h, written by SpringBoard's start-up check, statusbar/CCPanel.h; built in since 1.8.0's base):
//    Mac runs where that check passed on this iPadOS build (15-18; 18's is CC18Shape.h's); after 18 it answers "not supported" (the Mac row
//    greyed, "Not Supported Yet").
//  - Debug builds: /tmp/msb-engine-notinstalled naming "bigsurcenter" shows BigSurCenter as not installed on our Settings pages (its GET row, the
//    style that would be without it) -- the engines' own GET test, OwnPageState.h. Only what the pages show: Settings' exclusivity, SpringBoard and
//    the helper read the real files (MSBDCCStyleNow's display NO).
#pragma once
#import <Foundation/Foundation.h>
#include "CCStyle.h"
#import "ExclusiveChoice.h"
#import "CCMacCheck.h"   // (our own Control Center's start-up check on this build: MSBDCCMacVerdict)
#define MSBD_CC_MAC_BUILT 1   // (this build has our own Control Center: the Style page's Mac row follows its verdict, common/ChoicePage.h)

#define kMSBDCCStyleDomain CFSTR("com.besiktasliseba.macstatusbar")
// Our own Control Center's verdict on this iPadOS build: 1 it runs, 0 it can't (*reason: why, may be nil), -1 not checked on this build yet.
static inline int MSBDCCMacVerdictNow(NSString **reason) { return MSBDCCMacVerdict(reason); }
// The stored style, read for `user` (kCFPreferencesCurrentUser; the root helper: CFSTR("mobile")).
static inline int MSBDCCStyleStoredFor(CFStringRef user) {
    CFPreferencesSynchronize(kMSBDCCStyleDomain, user, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDCCStyleKey), kMSBDCCStyleDomain, user, kCFPreferencesAnyHost);
    int stored = MSBDCCStyleFromStored(v);
    if (v) CFRelease(v);
    return stored;
}
// Status Bar Style as stored for `user` (stockStatusBar: on only as a boolean true, as SpringBoard's start reads it): with Stock our Control Center
// does not run (CCStyle.h MSBDCCMacRuns).
static inline BOOL MSBDCCStockBarStoredFor(CFStringRef user) {
    CFPreferencesSynchronize(kMSBDCCStyleDomain, user, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("stockStatusBar"), kMSBDCCStyleDomain, user, kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)v);
    if (v) CFRelease(v);
    return on;
}
#if DEBUG
static inline BOOL MSBDCCStylePretendNoBSC(void) {
    NSString *p = [NSString stringWithContentsOfFile:@"/tmp/msb-engine-notinstalled" encoding:NSUTF8StringEncoding error:nil];
    return [p containsString:@"bigsurcenter"];
}
#endif
// BigSurCenter installed (its library there, or iCleaner Pro's .disabled of it). display: as our Settings pages show it (the debug pretend).
static inline BOOL MSBDCCBigSurCenterInstalled(BOOL display) {
#if DEBUG
    if (display && MSBDCCStylePretendNoBSC()) return NO;
#else
    (void)display;
#endif
    return MSBDExInstalled(@"BigSurCenter");
}
// The style the rule gives now, for `user`; *installed: BigSurCenter installed; *verdict: our Control Center's verdict (either may be NULL).
static inline int MSBDCCStyleNowFor(CFStringRef user, BOOL display, BOOL *installed, int *verdict) {
    BOOL bsc = MSBDCCBigSurCenterInstalled(display);
    BOOL userOff = bsc && MSBDExUserOffNow(@"BigSurCenter");
    int v = MSBDCCMacVerdictNow(NULL);
    if (installed) *installed = bsc;
    if (verdict) *verdict = v;
    return MSBDCCStyleChosen(MSBDCCStyleStoredFor(user), bsc, userOff, MSBDCCMacRuns((int)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion, v, MSBDCCStockBarStoredFor(user)));
}
static inline int MSBDCCStyleNow(BOOL display) { return MSBDCCStyleNowFor(kCFPreferencesCurrentUser, display, NULL, NULL); }
