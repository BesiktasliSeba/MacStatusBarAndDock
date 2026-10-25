// common/MacPointerActive.h -- MacStatusBar&Dock 1.5.0: whether our buttons and icons keep iPadOS's pointer effects (the highlight, the pull, an
// icon's lift). With the Mac pointer they don't: iPadOS draws its pointer under a lifted icon and morphs it into a highlight, and the arrow went under
// Dock icons and showed a circle over the traffic lights (17.5.1 / 18.5, 25 Oct). The Mac pointer is the default (Settings > Pointer > Pointer Style).
// The setting alone is not enough (external logic test W5, 25 Oct): when the Mac pointer stands down because another tweak changes pointeruid's
// pointer (statusbar/macpointer/MacPointer.x, MPOtherPointerTweak), the pointer is iPadOS's own, and it keeps its effects. MacPointer says so in a
// Darwin notification state: 1 present and drawing whenever the setting asks for it, 2 standing down; 0 nobody said yet (not loaded so far, or
// pointeruid not started) counts as present, so a button made before pointeruid starts never gets the effects the Mac arrow then shows them with.
// Plain C and CoreFoundation; included by MacStatusBarCore (StatusBar.x) and MacDock (dock/FinderIcon.m, dock/Downloads.m).
#pragma once
#include <notify.h>
#include <objc/objc.h>
#include <CoreFoundation/CoreFoundation.h>
#define kMSBDMacPointerState "com.besiktasliseba.macpointer.active"   // 1 present, 2 standing down (another pointer tweak), 0 not said

static inline BOOL MSBDMacPointerStandsDown(void) {
    static int token = 0;   // (kept: the state lives on while pointeruid restarts, until MacPointer says again)
    if (!token && notify_register_check(kMSBDMacPointerState, &token) != NOTIFY_STATUS_OK) token = 0;
    uint64_t v = 0;
    if (token) notify_get_state(token, &v);
    return v == 2;
}
// iPadOS's pointer effects on our buttons and icons: with Pointer Style "iPadOS", or while the Mac pointer stands down for another pointer tweak.
static inline BOOL MSBDIPadPointerEffects(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("pointerStyle"), CFSTR("com.besiktasliseba.macstatusbar"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL ipad = v && CFGetTypeID(v) == CFStringGetTypeID() && CFStringCompare((CFStringRef)v, CFSTR("ipados"), 0) == kCFCompareEqualTo;
    if (v) CFRelease(v);
    return ipad || MSBDMacPointerStandsDown();
}
