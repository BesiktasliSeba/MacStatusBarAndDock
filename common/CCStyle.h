// CCStyle.h -- Control Center Style (Settings > Status Bar > Control Center, 1.8.0 item 3, KT 2 Nov; plans/control-center-1.8.0.md section 3):
// which Control Center opens -- Mac (our own, inside Apple's: statusbar/CCPanel.h), iPadOS (Apple's own) or BigSurCenter (a third-party one) --,
// and only the chosen one loads (common/ExclusiveChoice.h keeps BigSurCenter out of SpringBoard while Mac or iPadOS is the style). One rule for
// every side, so they can never disagree: SpringBoard (the style it shows, statusbar/CCStyleSB.h), Settings (the row, its page and the rows that
// go with a style, MSBRootListController.m), the root helper (whether BigSurCenter loads, macsettings/sshtoggled) and the Settings search
// (common/OwnPageState.h). Plain C with CoreFoundation (Mac test tools/test-ccstyle.sh); the readers of the state on the iPad are
// common/CCStyleNow.h.
//  - Stored (controlCenterStyle, com.besiktasliseba.macstatusbar): the text "mac", "stock" or "bigsurcenter", written by a tap on the Style page,
//    and "stock" by the crash guard when our Control Center crashed SpringBoard (step 1b: tools/crashmap-rules.txt "controlcenter", its off
//    text); the default is never written. False (or 0) is iPadOS's too: step 1 writes it for the switches turned on just before a crash, where
//    Mac counts as the style's "on" (and step 1b wrote it before 1.8.4). Anything else counts as never set.
//  - The rule. A stored style that can be had is the style: iPadOS always; BigSurCenter while it is installed; Mac where it runs, else iPadOS
//    (a Mac chosen where ours can't run is Apple's Control Center, never BigSurCenter: the user chose against that one). Never set, or
//    BigSurCenter stored but gone: BigSurCenter where it is installed and the user has not switched it off in Choicy or iCleaner Pro
//    themselves (updaters who have it keep it, KT 2 Nov), else iPadOS: Mac only when the user picks it, so everyone keeps the Control Center
//    they have (KT 3 Nov ~13:00; it was Mac where it runs for new users and updaters without BigSurCenter before).
//  - Mac runs on iPadOS 15-18 where SpringBoard's start-up check of everything our Control Center uses passed on this build (the panel's own
//    verdict, CCMacCheck.h; on 18 the check of Apple's 18 grid re-shaped into the Mac panel, statusbar/CC18Shape.h): not on later majors (their
//    Control Center never read: the row greyed, "Not Supported Yet"); not checked on this build yet (an iPadOS update before its first
//    respring): "Respring to Check", as the Stage Manager engine. And only with the Mac status bar: with Status
//    Bar Style Stock (stockStatusBar) SpringBoard never starts our Control Center (it runs on our status bar's path only, 1.8.0), so the rule
//    gives iPadOS's there and the row is greyed "Needs Mac Status Bar".
//  - Installed: BigSurCenter's library in TweakInject as .dylib or as iCleaner Pro's .disabled (Choicy's list does not make it uninstalled), as
//    the window engines are (OwnPageState.h MSBDEngineState). Its GET row (not installed) only where it runs: iPadOS 15 and 16 -- its developer's
//    page offers it for iOS 13.0-16.3.1, so on 17 and later it is listed only when it is there, as MilkyWay4 is left out on 16.
//  - In SpringBoard, BigSurCenter's classes loaded make it the style in force whatever is chosen: ours never goes in next to it (CCPanel.h), and
//    until the respring that stops it loading it is what Control Center shows. Chosen but not loaded yet (the respring that loads it still to
//    come): iPadOS's. SpringBoard publishes both for Settings' notes (kMSBDCCStyleState).
#ifndef MSBD_CC_STYLE_H
#define MSBD_CC_STYLE_H
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

#define kMSBDCCStyleKey   "controlCenterStyle"                         // (com.besiktasliseba.macstatusbar: "mac", "stock", "bigsurcenter")
#define kMSBDCCStyleState "com.besiktasliseba.macstatusbar.ccstyle"    // (notify state, SpringBoard: the style in force and BigSurCenter loaded)
enum { kMSBDCCStyleNone = 0, kMSBDCCStyleMac = 1, kMSBDCCStyleStock = 2, kMSBDCCStyleBigSurCenter = 3 };

// The stored value as every side reads it (NULL: none): the style, or kMSBDCCStyleNone for never set.
static inline int MSBDCCStyleFromStored(CFTypeRef v) {
    if (!v) return kMSBDCCStyleNone;
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        if (CFStringCompare((CFStringRef)v, CFSTR("mac"), 0) == kCFCompareEqualTo) return kMSBDCCStyleMac;
        if (CFStringCompare((CFStringRef)v, CFSTR("stock"), 0) == kCFCompareEqualTo) return kMSBDCCStyleStock;
        if (CFStringCompare((CFStringRef)v, CFSTR("bigsurcenter"), 0) == kCFCompareEqualTo) return kMSBDCCStyleBigSurCenter;
        return kMSBDCCStyleNone;
    }
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)v) ? kMSBDCCStyleNone : kMSBDCCStyleStock;   // (false: the crash guard's)
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        double d = 1.0;
        CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d);
        return d == 0.0 ? kMSBDCCStyleStock : kMSBDCCStyleNone;
    }
    return kMSBDCCStyleNone;
}
// The value a style is stored as (the row's values in Root.plist), NULL for none.
static inline const char *MSBDCCStyleValue(int style) {
    return style == kMSBDCCStyleMac ? "mac" : style == kMSBDCCStyleStock ? "stock" : style == kMSBDCCStyleBigSurCenter ? "bigsurcenter" : NULL;
}
// ... and its name in Settings and in our alerts.
static inline const char *MSBDCCStyleName(int style) {
    return style == kMSBDCCStyleMac ? "Mac" : style == kMSBDCCStyleStock ? "iPadOS" : style == kMSBDCCStyleBigSurCenter ? "BigSurCenter" : "None";
}
// Our own Control Center runs here: iPadOS 15-18, the panel's check passed on this build (verdict 1; 0 failed or no check, -1 not checked yet) and
// the Mac status bar is the style (stockBar: Status Bar Style Stock, as stored).
static inline int MSBDCCMacRuns(int osMajor, int verdict, int stockBar) { return !stockBar && osMajor >= 15 && osMajor <= 18 && verdict == 1; }
// The style: the rule above. bscInstalled: BigSurCenter's library is there; bscUserOff: the user switched it off themselves (not us).
static inline int MSBDCCStyleChosen(int stored, int bscInstalled, int bscUserOff, int macRuns) {
    if (stored == kMSBDCCStyleStock) return kMSBDCCStyleStock;
    if (stored == kMSBDCCStyleMac) return macRuns ? kMSBDCCStyleMac : kMSBDCCStyleStock;
    if (stored == kMSBDCCStyleBigSurCenter && bscInstalled) return kMSBDCCStyleBigSurCenter;
    if (bscInstalled && !bscUserOff) return kMSBDCCStyleBigSurCenter;   // (never set, or BigSurCenter stored but gone: the default)
    return kMSBDCCStyleStock;   // (... else iPadOS's: Mac only when picked)
}
// BigSurCenter may load with this style (ExclusiveChoice.h keeps it out of SpringBoard otherwise).
static inline int MSBDCCStyleLoadsBigSurCenter(int chosen) { return chosen == kMSBDCCStyleBigSurCenter; }
// The style in force in SpringBoard: BigSurCenter while its classes are loaded, whatever is chosen; chosen but not loaded: iPadOS's.
static inline int MSBDCCStyleInForce(int chosen, int bscLoaded) {
    if (bscLoaded) return kMSBDCCStyleBigSurCenter;
    return chosen == kMSBDCCStyleBigSurCenter ? kMSBDCCStyleStock : chosen;
}
// SpringBoard's word for Settings (kMSBDCCStyleState): the style in force, and BigSurCenter loaded. 0: no SpringBoard of ours has said anything.
static inline uint64_t MSBDCCStyleStateMake(int inForce, int bscLoaded) { return 0x100u | (bscLoaded ? 0x10u : 0u) | (uint64_t)(inForce & 0xf); }
static inline int MSBDCCStyleStateInForce(uint64_t s) { return (s & 0x100u) ? (int)(s & 0xfu) : kMSBDCCStyleNone; }
static inline int MSBDCCStyleStateBSCLoaded(uint64_t s) { return (s & 0x100u) && (s & 0x10u); }
// What a respring still has to do for the chosen style, from SpringBoard's word (Settings' note under the Control Center group): 1 BigSurCenter is
// still loaded although another style is chosen, 2 BigSurCenter is chosen and installed but not loaded yet, 0 nothing (or nothing said).
static inline int MSBDCCStyleRespringNote(int chosen, int bscInstalled, uint64_t state) {
    if (!(state & 0x100u)) return 0;
    int loaded = MSBDCCStyleStateBSCLoaded(state);
    if (loaded && chosen != kMSBDCCStyleBigSurCenter) return 1;
    if (!loaded && chosen == kMSBDCCStyleBigSurCenter && bscInstalled) return 2;
    return 0;
}
// The Style page's Mac row: 0 it can be picked, 1 greyed "Not Supported Yet" (an iPadOS after 18, a check that failed, a build without our
// Control Center), 2 greyed "Respring to Check" (not checked on this build yet), 3 greyed "Needs Mac Status Bar" (Status Bar Style Stock: whatever
// the check said, the panel never starts then). built: this build has our Control Center (CCMacCheck.h).
static inline int MSBDCCMacRowState(int osMajor, int verdict, int built, int stockBar) {
    if (osMajor < 15 || osMajor > 18 || !built) return 1;
    if (stockBar) return 3;
    return verdict == 1 ? 0 : verdict == -1 ? 2 : 1;
}
// ... and its BigSurCenter row: 2 it can be picked (installed), 0 greyed with GET (not installed, iPadOS 15-16), -1 left out (not installed on 17+).
static inline int MSBDCCBigSurCenterRowState(int osMajor, int installed) {
    if (installed) return 2;
    return osMajor >= 15 && osMajor <= 16 ? 0 : -1;
}
#endif
