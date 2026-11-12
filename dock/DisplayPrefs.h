// DisplayPrefs.h (dock) -- the per-display settings in the Dock part (MacStatusBar&Dock 1.8.7 commit 5; plans/design-1.8.7-displays.md sections 3
// and 5). Included by Dock.x. The rule is plain C (common/DisplayPrefs.h, tools/test-displayprefs.c), the display key common/DisplayIdentity.h's:
// the Dock part derives each screen's key itself and keeps its own cache, so it works with Mac Status Bar switched off (no registry needed).
//  - The cache: the master switch displaySettings (absent or true: on) and every remembered display's Dock overrides (part dock; at most 8
//    displays), read again with the Dock's own settings (DMLoadPrefs, which the displays domain's prefsChanged also runs: Dock.x's constructor).
//  - The getters (DMDispBool / DMDispNum): the iPad's own screen, or none, returns the iPad's value it is given at once, with no key and no lookup, so
//    the iPad's Dock keeps its globals (gIconSize, gMagnification, gShowTrash...). Readers ask with the Dock's own screen (its window's scene's).
//  - The master switch off: the getters answer by the rule with no display key derived (the crash guard's displaySettings target then switches off
//    the code it names: the key's private calls). The key's derivation (DMDispKeyOfScreen) is passed over in the crash map, so the feature that asked
//    decides; it and the getters stay out of line (noinline), each a frame of its own.
// Nothing here writes: the Dock part only reads the displays domain.
#pragma once
#include "../common/DisplayPrefs.h"
#include "../common/DisplayIdentity.h"

static BOOL gDMDispLayerOn = YES;   // (the master switch, read with the cache)
static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *gDMDispCache;   // display key -> {flat key -> value}: the Dock's overrides
static NSMapTable<UIScreen *, NSString *> *gDMDispScreenKeys;   // (each screen's key, "" for the iPad's; cleared when a display comes or goes)
static NSMutableSet<NSString *> *gDMDispTypeLogged;   // (an override of the wrong type is logged once per key)

// ---- which display ------------------------------------------------------------------------------------------------------------------------------
__attribute__((noinline)) static NSString *DMDispKeyOfScreen(UIScreen *s) {
    if (!s || s == [UIScreen mainScreen]) return nil;
    if (!gDMDispScreenKeys) gDMDispScreenKeys = [NSMapTable weakToStrongObjectsMapTable];
    NSString *k = [gDMDispScreenKeys objectForKey:s];
    if (!k) { k = MSBDDispKeyOfScreen(s) ?: @""; [gDMDispScreenKeys setObject:k forKey:s]; }
    return k.length ? k : nil;
}

// ---- the cache and the getters ------------------------------------------------------------------------------------------------------------------
// The displays domain read again: the master switch and every display's Dock overrides (only flat keys of an override's shape, part dock).
__attribute__((noinline)) static void DMDispReload(void) {
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *all = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (![all isKindOfClass:[NSDictionary class]]) all = @{};
    id master = all[@MSBD_DISP_MASTER_KEY];
    gDMDispLayerOn = ![master isKindOfClass:[NSNumber class]] || [master boolValue];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    for (NSString *flat in all) {
        char display[128], part[128];
        if (![flat isKindOfClass:[NSString class]] || !MSBDDispFlatSplit(flat.UTF8String, display, sizeof display, part, sizeof part, NULL, 0) || strcmp(part, "dock") != 0) continue;
        NSString *d = @(display);
        NSMutableDictionary *mine = cache[d];
        if (!mine) cache[d] = mine = [NSMutableDictionary dictionary];
        mine[flat] = all[flat];
    }
    gDMDispCache = cache;
}
// The same, telling whether anything the Dock part reads changed (its Dock overrides, the master switch): the domain's note is also posted by the status
// bar part's registry at every connect and disconnect and with SpringBoard's names, which change nothing of the Dock's.
static BOOL DMDispReloadChanged(void) {
    NSDictionary *was = gDMDispCache; BOOL wasOn = gDMDispLayerOn;
    DMDispReload();
    return wasOn != gDMDispLayerOn || !(was == gDMDispCache || [was isEqualToDictionary:gDMDispCache]);
}
static int DMDispKindOf(id v, double *num) {
    *num = 0;
    if (!v) return kMSBDDispVNone;
    if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) { *num = [v boolValue]; return kMSBDDispVBool; }
    if ([v isKindOfClass:[NSNumber class]]) { *num = [v doubleValue]; return kMSBDDispVNumber; }
    return kMSBDDispVOther;
}
// The value for one display (nil key: the iPad's): *from says where it comes from (kMSBDDispFrom...), *def the display default.
static id DMDispResolveFor(NSString *display, const char *part, const char *key, int want, int hasRange, double lo, double hi, int *from, int *def) {
    *from = kMSBDDispFromIPad; *def = 0;
    if (!display) return nil;
    char flat[MSBD_DISP_FLAT_MAX + 1];
    id ov = nil;
    NSString *fk = nil;
    if (MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, part, key)) { fk = @(flat); ov = gDMDispCache[display][fk]; }
    double num = 0;
    int got = DMDispKindOf(ov, &num);
    BOOL typeOK = MSBDDispTypeOK(want, got, num, hasRange, lo, hi);
    if (ov && !typeOK && gDMDispLayerOn && fk) {
        if (!gDMDispTypeLogged) gDMDispTypeLogged = [NSMutableSet set];
        if (![gDMDispTypeLogged containsObject:fk]) { [gDMDispTypeLogged addObject:fk]; DMLog([NSString stringWithFormat:@"[dispprefs] %@: %@ is not this row's type or range: read as not set", fk, ov]); }
    }
    int hasDef = MSBDDispDisplayDefault(part, key, def);
    *from = MSBDDispResolve(0, gDMDispLayerOn, ov != nil, typeOK, hasDef);
    return *from == kMSBDDispFromOverride ? ov : nil;
}
// The getters by screen. The iPad's own screen (or none) returns `ipad` at once: no key, no lookup. The master switch off: another display's answer
// by the rule (its row's display default, else the iPad's), no key derived.
static BOOL DMDispOffAnswer(const char *part, const char *key, int *from, int *def) {
    if (gDMDispLayerOn) return NO;
    *def = 0;
    *from = MSBDDispResolve(0, 0, 0, 0, MSBDDispDisplayDefault(part, key, def));
    return YES;
}
__attribute__((unused, noinline)) static BOOL DMDispBool(UIScreen *s, const char *part, const char *key, BOOL ipad) {
    if (!s || s == [UIScreen mainScreen]) return ipad;
    int from, def;
    if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (def != 0) : ipad;
    NSString *display = DMDispKeyOfScreen(s);
    if (!display) return ipad;
    id v = DMDispResolveFor(display, part, key, kMSBDDispWantBool, 0, 0, 0, &from, &def);
    return from == kMSBDDispFromOverride ? [v boolValue] : from == kMSBDDispFromDefault ? (def != 0) : ipad;
}
__attribute__((unused, noinline)) static double DMDispNum(UIScreen *s, const char *part, const char *key, double ipad, double lo, double hi) {   // (lo > hi: no range)
    if (!s || s == [UIScreen mainScreen]) return ipad;
    int from, def;
    if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (double)def : ipad;
    NSString *display = DMDispKeyOfScreen(s);
    if (!display) return ipad;
    id v = DMDispResolveFor(display, part, key, kMSBDDispWantNumber, lo <= hi, lo, hi, &from, &def);
    return from == kMSBDDispFromOverride ? [v doubleValue] : from == kMSBDDispFromDefault ? (double)def : ipad;
}
// The Dock part's start (its constructor, before DMLoadPrefs reads the cache): the screens' keys forgotten when a display comes or goes (UIKit makes
// new screens for it).
static void DMDispInit(void) {
    DM_FEATURE_MARK("display-prefs-dock");
    for (NSString *n in @[UIScreenDidConnectNotification, UIScreenDidDisconnectNotification])
        [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { [gDMDispScreenKeys removeAllObjects]; }];
}
