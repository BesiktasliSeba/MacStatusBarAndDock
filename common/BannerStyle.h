// BannerStyle.h -- Banner Style (Settings > Status Bar > Notifications, 1.8.0 item 2, KT 2 Nov: the Mac-Style Banners switch becomes a choice like
// Window Engine): which notification banners show -- Mac (ours, StatusBar.x's Mac-style notification banners), iPadOS (Apple's own) or Destra (a
// third-party tweak's: MacOSNotifications.dylib) --, and only the chosen one loads (common/ExclusiveChoice.h keeps Destra out of SpringBoard while
// Mac or iPadOS is the style). One rule for every side, as Control Center Style's (common/CCStyle.h): SpringBoard (whether ours show,
// statusbar/BannerStyleSB.h), Settings (the row, its page, the group's footer, MSBRootListController.m) and the root helper (whether Destra loads,
// macsettings/sshtoggled). Plain C with CoreFoundation (Mac test tools/test-bannerstyle.sh); the readers of the state on the iPad are
// common/BannerStyleNow.h.
//  - Stored (bannerStyle, com.besiktasliseba.macstatusbar): the text "mac", "stock" or "destra", written by a tap on the Style page, and "stock"
//    by the crash guard when our banners crashed SpringBoard (step 1b: tools/crashmap-rules.txt "macBanners", its off text); the default is never
//    written. False (or 0) is iPadOS's too: step 1 writes it for the switches turned on just before a crash, where Mac counts as the style's "on"
//    (and step 1b wrote it before 1.8.4). Anything else counts as never set.
//  - The rule. A stored style that can be had is the style: Mac and iPadOS always; Destra while it is installed (the pick wins over a switch-off
//    of the user's own in Choicy: the pick lets it in again). Never set, or Destra stored but gone: ours for everyone (KT 3 Nov ~14:15) -- Mac,
//    also where Destra is installed and showed its banners before 1.8.0 (it is kept out then, as with any Mac or iPadOS pick), unless the old
//    Mac-Style Banners switch (macBanners) was turned off: that was the user's own choice, so iPadOS. (It was Destra where it showed the banners
//    before, KT 2 Nov's "keep what they have".)
//  - Installed: Destra's library in TweakInject as .dylib or as iCleaner Pro's .disabled. Its row is always on the page (KT 3 Nov ~14:15), greyed
//    "Not Installed" and not picked while it isn't: its developer's page is gone (Destra was sold on Packix, archived in August 2022 without its
//    paid packages; no other listing of the developer's), so there is no GET to offer.
//  - In SpringBoard, Destra loaded and switched on in its own settings is the style in force whatever is chosen: ours steps aside (both at once
//    squeezed every banner) until the respring that stops it loading. Chosen but not loaded yet, or loaded but switched off in its own settings:
//    iPadOS's. SpringBoard publishes the style in force and whether Destra is loaded, for Settings' notes (kMSBDBannerStyleState).
#ifndef MSBD_BANNER_STYLE_H
#define MSBD_BANNER_STYLE_H
#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>

#define kMSBDBannerStyleKey  "bannerStyle"                                // (com.besiktasliseba.macstatusbar: "mac", "stock", "destra")
#define kMSBDBannerLegacyKey "macBanners"                                 // (the Mac-Style Banners switch before 1.8.0: on unless set)
#define kMSBDBannerStyleState "com.besiktasliseba.macstatusbar.bannerstyle" // (notify state, SpringBoard: the style in force and Destra loaded)
enum { kMSBDBannerNone = 0, kMSBDBannerMac = 1, kMSBDBannerStock = 2, kMSBDBannerDestra = 3 };

// The stored value as every side reads it (NULL: none): the style, or kMSBDBannerNone for never set.
static inline int MSBDBannerStyleFromStored(CFTypeRef v) {
    if (!v) return kMSBDBannerNone;
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        if (CFStringCompare((CFStringRef)v, CFSTR("mac"), 0) == kCFCompareEqualTo) return kMSBDBannerMac;
        if (CFStringCompare((CFStringRef)v, CFSTR("stock"), 0) == kCFCompareEqualTo) return kMSBDBannerStock;
        if (CFStringCompare((CFStringRef)v, CFSTR("destra"), 0) == kCFCompareEqualTo) return kMSBDBannerDestra;
        return kMSBDBannerNone;
    }
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)v) ? kMSBDBannerNone : kMSBDBannerStock;   // (false: the crash guard's)
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        double d = 1.0;
        CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d);
        return d == 0.0 ? kMSBDBannerStock : kMSBDBannerNone;
    }
    return kMSBDBannerNone;
}
// The old switch (macBanners) as it was read before 1.8.0: a boolean (or a number) -- off is iPadOS's, on is Mac; anything else counts as never set.
static inline int MSBDBannerLegacyFromStored(CFTypeRef v) {
    if (!v) return kMSBDBannerNone;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)v) ? kMSBDBannerMac : kMSBDBannerStock;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        double d = 1.0;
        CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &d);
        return d == 0.0 ? kMSBDBannerStock : kMSBDBannerMac;
    }
    return kMSBDBannerNone;
}
// The value a style is stored as (the row's values in Root.plist), NULL for none.
static inline const char *MSBDBannerStyleValue(int style) {
    return style == kMSBDBannerMac ? "mac" : style == kMSBDBannerStock ? "stock" : style == kMSBDBannerDestra ? "destra" : NULL;
}
// ... and its name in Settings and in our alerts.
static inline const char *MSBDBannerStyleName(int style) {
    return style == kMSBDBannerMac ? "Mac" : style == kMSBDBannerStock ? "iPadOS" : style == kMSBDBannerDestra ? "Destra" : "None";
}
// The style: the rule above. legacy: the old switch (MSBDBannerLegacyFromStored); destraInstalled: its library is there. (Destra's own switch and
// a switch-off of the user's own decide nothing here: never set is ours, Destra installed or not.)
static inline int MSBDBannerStyleChosen(int stored, int legacy, int destraInstalled) {
    if (stored == kMSBDBannerMac || stored == kMSBDBannerStock) return stored;
    if (stored == kMSBDBannerDestra && destraInstalled) return kMSBDBannerDestra;
    return legacy == kMSBDBannerStock ? kMSBDBannerStock : kMSBDBannerMac;   // (never set, or Destra stored but gone: ours, iPadOS's if turned off)
}
// Destra may load with this style (ExclusiveChoice.h keeps it out of SpringBoard otherwise).
static inline int MSBDBannerLoadsDestra(int chosen) { return chosen == kMSBDBannerDestra; }
// The style in force in SpringBoard: Destra while it is loaded and switched on in its own settings, whatever is chosen; Destra chosen but not
// loaded (or loaded and switched off in its own settings): iPadOS's.
static inline int MSBDBannerInForce(int chosen, int destraLoaded, int destraOwnOn) {
    if (destraLoaded && destraOwnOn) return kMSBDBannerDestra;
    return chosen == kMSBDBannerDestra ? kMSBDBannerStock : chosen;
}
// SpringBoard's word for Settings (kMSBDBannerStyleState): the style in force, and Destra loaded. 0: no SpringBoard of ours has said anything.
static inline uint64_t MSBDBannerStateMake(int inForce, int destraLoaded) { return 0x100u | (destraLoaded ? 0x10u : 0u) | (uint64_t)(inForce & 0xf); }
static inline int MSBDBannerStateInForce(uint64_t s) { return (s & 0x100u) ? (int)(s & 0xfu) : kMSBDBannerNone; }
static inline int MSBDBannerStateDestraLoaded(uint64_t s) { return (s & 0x100u) && (s & 0x10u); }
// What a respring still has to do for the chosen style, from SpringBoard's word (Settings' note under the Notifications group): 1 Destra is still
// loaded although another style is chosen, 2 Destra is chosen and installed but not loaded yet, 0 nothing (or nothing said); 3 Destra is still
// loaded although another style is chosen and no respring can change it: neither Choicy nor iCleaner Pro is there to keep it out (keeper 0) --
// a never-set style meets this with no pick (and so no alert) of the user's.
static inline int MSBDBannerRespringNote(int chosen, int destraInstalled, int keeper, uint64_t state) {
    if (!(state & 0x100u)) return 0;
    int loaded = MSBDBannerStateDestraLoaded(state);
    if (loaded && chosen != kMSBDBannerDestra) return keeper ? 1 : 3;
    if (!loaded && chosen == kMSBDBannerDestra && destraInstalled) return 2;
    return 0;
}
// The Style page's Destra row: 2 it can be picked (installed), 0 greyed "Not Installed" (no GET: no page of its developer's to send anyone to).
static inline int MSBDBannerDestraRowState(int installed) { return installed ? 2 : 0; }
#endif
