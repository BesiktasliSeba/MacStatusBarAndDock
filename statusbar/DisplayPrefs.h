// DisplayPrefs.h (statusbar) -- the per-display settings layer in SpringBoard's status bar part (MacStatusBar&Dock 1.8.7 commit 3;
// plans/design-1.8.7-displays.md sections 3 and 5). Included by StatusBar.x. The rule is plain C (common/DisplayPrefs.h, tools/test-displayprefs.c),
// the display key common/DisplayIdentity.h's.
//  - The registry, in the displays domain only (KT's domains are never written here): "<display>/info" = {name, route, px, points, scale, firstSeen,
//    lastSeen} and "connected", written when a display connects or disconnects (and once a moment after SpringBoard starts, when the screens are
//    what they are: a display unplugged while SpringBoard was not running is no longer "connected"). At most 8 displays are remembered:
//    a 9th forgets one not connected, a display with nothing of the user's own before one with its own settings or desktops (DMDispHasOwn).
//  - The getters (DMDispBool / DMDispNum / DMDispValue, and ...ForIdentity for a stage's display): the iPad's own screen, or none, returns the iPad's
//    value it was given with no lookup, so the iPad's path keeps its globals untouched; a display resolves by the rule from one cache per display,
//    rebuilt on connect, disconnect, the displays domain's prefsChanged and the iPad's own. Readers ask with their screen (commit 5 on; the list of
//    reader sites: tools/test-displayreaders.sh).
//  - The master switch displaySettings (absent or true: on). Off: every override is dormant (kept), the display defaults stand, and the code the
//    crash guard's displaySettings target names does not run: no registry, no names asked, and the getters answer by the rule with no display key
//    derived (the main screen or not is all the rule needs then). Read first at the start (DMDispInit) and with every post of the domain.
//  - The crash map (tools/crashmap-rules.txt): the getters and the registry are Display Settings' (a frame of theirs); the display key's derivation
//    (DMDispKeyOfScreen, DMDispDesktopScreen, DisplayIdentity.h's private calls) is passed over, so the feature that asked for a key decides (Menu
//    Bar Size, the TV's auto-hide, the Dock's): kept out of line for that (noinline), with the getters, so each is a frame of its own.
//  - The crash guard (commit 4): a change for one display goes through DMDispWrite, which notes a switch turned on in the guard's RecentlyOn list by
//    its flat key (step 1 then sets that override off) and posts the domain's prefsChanged; step 1b clears every display's override of a switch it
//    sets (CrashStep.h). Its callers: the Display Settings window (commit 11, DisplaySettings.h); Settings writes through the same writer.
#pragma once
#include "../common/DisplayPrefs.h"
#include "../common/DisplayIdentity.h"
#include "../common/CrashGuard.h"   // (MSBD_GUARD_RECENT: the crash guard's list of switches turned on)
#include "../common/DisplayRowStore.h"   // (1.8.7 commit 11: the one writer of a display's change, with Settings' Displays page)

static BOOL gDMDispLayerOn = YES;   // (the master switch, read with the cache)
static NSDictionary<NSString *, NSDictionary<NSString *, id> *> *gDMDispCache;   // display key -> {flat key -> value}: every remembered display's overrides
static NSArray<NSString *> *gDMDispConnected;   // the display keys connected now, as SpringBoard last wrote them
static NSMapTable<UIScreen *, NSString *> *gDMDispScreenKeys;   // (each screen's key, "" for the iPad's; cleared on every connect / disconnect)
static NSMutableSet<NSString *> *gDMDispTypeLogged;   // (an override of the wrong type is logged once per key)

// ---- which display ------------------------------------------------------------------------------------------------------------------------------
__attribute__((noinline)) static NSString *DMDispKeyOfScreen(UIScreen *s) {
    if (!s || s == [UIScreen mainScreen]) return nil;
    if (!gDMDispScreenKeys) gDMDispScreenKeys = [NSMapTable weakToStrongObjectsMapTable];
    NSString *k = [gDMDispScreenKeys objectForKey:s];
    if (!k) { k = MSBDDispKeyOfScreen(s) ?: @""; [gDMDispScreenKeys setObject:k forKey:s]; }
    return k.length ? k : nil;
}
__attribute__((unused)) static NSString *DMDispKeyOfView(UIView *v) {
    UIWindow *w = [v isKindOfClass:[UIWindow class]] ? (UIWindow *)v : v.window;
    UIScreen *s = nil;
    @try { s = w.windowScene.screen ?: w.screen; } @catch (NSException *e) { return nil; }
    return DMDispKeyOfScreen(s);
}
// A stage's display (SBAppLayout -preferredDisplayIdentity, an FBSDisplayIdentity): the screen whose configuration has that identity. The iPad's
// identity, or none, has no key.
static NSArray<UIScreen *> *DMDispScreens(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray *all = [UIScreen screens];
#pragma clang diagnostic pop
    return [all isKindOfClass:[NSArray class]] ? all : @[];
}
__attribute__((unused)) static NSString *DMDispKeyOfIdentity(id identity) {
    if (!identity) return nil;
    for (UIScreen *s in DMDispScreens()) {
        id ident = MSBDDispGet(MSBDDispConfigOfScreen(s), "identity");
        if (ident && [ident isEqual:identity]) return DMDispKeyOfScreen(s);
    }
    return nil;
}

// ---- the cache and the getters ------------------------------------------------------------------------------------------------------------------
// The displays domain read again: the master switch and every display's overrides (only flat keys of an override's shape; at most 8 displays are
// remembered). Every one, not only those in `connected`: a display is asked for the moment it connects, before the registry has it (0.6 s), and
// right after SpringBoard starts (2 s).
__attribute__((noinline)) static void DMDispReload(void) {
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *all = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (![all isKindOfClass:[NSDictionary class]]) all = @{};
    id master = all[@MSBD_DISP_MASTER_KEY];
    gDMDispLayerOn = ![master isKindOfClass:[NSNumber class]] || [master boolValue];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    for (NSString *flat in all) {
        char display[128];
        if (![flat isKindOfClass:[NSString class]] || !MSBDDispFlatSplit(flat.UTF8String, display, sizeof display, NULL, 0, NULL, 0)) continue;
        NSString *d = @(display);
        NSMutableDictionary *mine = cache[d];
        if (!mine) cache[d] = mine = [NSMutableDictionary dictionary];
        mine[flat] = all[flat];
    }
    gDMDispCache = cache;
}
static int DMDispKindOf(id v, double *num) {
    *num = 0;
    if (!v) return kMSBDDispVNone;
    if (CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID()) { *num = [v boolValue]; return kMSBDDispVBool; }
    if ([v isKindOfClass:[NSNumber class]]) { *num = [v doubleValue]; return kMSBDDispVNumber; }
    return kMSBDDispVOther;
}
// The value for one display (nil key: the iPad's): *from says where it comes from (kMSBDDispFrom...), *def the display default; the override
// itself is returned when it is the answer.
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
// The master switch off: every override dormant, so another display reads its row's display default, else the iPad's value it was given -- with no
// display key derived and no lookup (the rule needs only "not the iPad's screen" then: MSBDDispResolve with layerOn 0). YES with *from and *def set.
static BOOL DMDispOffAnswer(const char *part, const char *key, int *from, int *def) {
    if (gDMDispLayerOn) return NO;
    *def = 0;
    *from = MSBDDispResolve(0, 0, 0, 0, MSBDDispDisplayDefault(part, key, def));
    return YES;
}
__attribute__((noinline)) static BOOL DMDispBoolForKey(NSString *display, const char *part, const char *key, BOOL ipad) {
    if (!display) return ipad;
    int from, def; id v = DMDispResolveFor(display, part, key, kMSBDDispWantBool, 0, 0, 0, &from, &def);
    return from == kMSBDDispFromOverride ? [v boolValue] : from == kMSBDDispFromDefault ? (def != 0) : ipad;
}
__attribute__((noinline)) static double DMDispNumForKey(NSString *display, const char *part, const char *key, double ipad, double lo, double hi) {   // (lo > hi: no range)
    if (!display) return ipad;
    int from, def; id v = DMDispResolveFor(display, part, key, kMSBDDispWantNumber, lo <= hi, lo, hi, &from, &def);
    return from == kMSBDDispFromOverride ? [v doubleValue] : from == kMSBDDispFromDefault ? (double)def : ipad;
}
__attribute__((noinline)) static id DMDispValueForKey(NSString *display, const char *part, const char *key, id ipad) {
    if (!display) return ipad;
    int from, def; id v = DMDispResolveFor(display, part, key, kMSBDDispWantValue, 0, 0, 0, &from, &def);
    return from == kMSBDDispFromOverride ? v : from == kMSBDDispFromDefault ? @(def) : ipad;
}
// The getters by screen and by a stage's display identity. The iPad's own screen (or none) returns `ipad` at once: no key, no lookup. The master
// switch off: the rule's answer for another display with no key (DMDispOffAnswer); by identity, a row with no display default needs not even "the
// iPad's or not" (the iPad's value either way), a row with one looks the identity up as before.
__attribute__((unused, noinline)) static BOOL DMDispBool(UIScreen *s, const char *part, const char *key, BOOL ipad) {
    if (!s || s == [UIScreen mainScreen]) return ipad;
    int from, def; if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (def != 0) : ipad;
    return DMDispBoolForKey(DMDispKeyOfScreen(s), part, key, ipad);
}
__attribute__((unused, noinline)) static double DMDispNum(UIScreen *s, const char *part, const char *key, double ipad, double lo, double hi) {
    if (!s || s == [UIScreen mainScreen]) return ipad;
    int from, def; if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (double)def : ipad;
    return DMDispNumForKey(DMDispKeyOfScreen(s), part, key, ipad, lo, hi);
}
__attribute__((unused, noinline)) static id DMDispValue(UIScreen *s, const char *part, const char *key, id ipad) {
    if (!s || s == [UIScreen mainScreen]) return ipad;
    int from, def; if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? @(def) : ipad;
    return DMDispValueForKey(DMDispKeyOfScreen(s), part, key, ipad);
}
__attribute__((unused, noinline)) static BOOL DMDispBoolForIdentity(id identity, const char *part, const char *key, BOOL ipad) {
    if (!identity || (!gDMDispLayerOn && !MSBDDispDisplayDefault(part, key, NULL))) return ipad;
    return DMDispBoolForKey(DMDispKeyOfIdentity(identity), part, key, ipad);
}
__attribute__((unused, noinline)) static double DMDispNumForIdentity(id identity, const char *part, const char *key, double ipad, double lo, double hi) {
    if (!identity || (!gDMDispLayerOn && !MSBDDispDisplayDefault(part, key, NULL))) return ipad;
    return DMDispNumForKey(DMDispKeyOfIdentity(identity), part, key, ipad, lo, hi);
}
__attribute__((unused, noinline)) static id DMDispValueForIdentity(id identity, const char *part, const char *key, id ipad) {
    if (!identity || (!gDMDispLayerOn && !MSBDDispDisplayDefault(part, key, NULL))) return ipad;
    return DMDispValueForKey(DMDispKeyOfIdentity(identity), part, key, ipad);
}

// ---- changes for one display, and the crash guard ------------------------------------------------------------------------------------------------
// A change made for one display: the override written (also when it equals the iPad's value: from then it sticks), or deleted for nil (the row's
// reset); a switch turned on noted for the crash guard (`wasOn`: what the display showed before; its RecentlyOn line by the flat key); the domain's
// prefsChanged posted, so both parts and Settings read it again. The writer is the one Settings' Displays page writes through too
// (common/DisplayRowStore.h MSBDDispStoreWrite): the window and Settings write the same keys. Returns NO for a key the layer refuses
// (DisplayPrefs.h MSBDDispFlatKey).
__attribute__((unused)) static BOOL DMDispWrite(NSString *display, const char *part, const char *key, id value, BOOL wasOn, NSString *title) {
    NSString *fk = MSBDDispStoreWrite(display, part, key, value, wasOn, title);
    if (!fk) { DMLog([NSString stringWithFormat:@"[dispprefs] refused: %@ %s %s", display, part, key]); return NO; }
    DMDispReload();
    DMLog([NSString stringWithFormat:@"[dispprefs] %@ = %@", fk, value ?: @"(the iPad's again)"]);
    return YES;
}

// ---- the registry -------------------------------------------------------------------------------------------------------------------------------
// An unsigned getter (CADisplayMode -width / -height), only in that shape; 0 when it is not there.
static unsigned long DMDispGetUnsigned(id o, const char *name) {
    if (!o) return 0;
    SEL s = sel_registerName(name);
    @try {
        if (![o respondsToSelector:s]) return 0;
        Method m = class_getInstanceMethod(object_getClass(o), s);
        const char *t = m ? method_getTypeEncoding(m) : NULL;
        if (!m || method_getNumberOfArguments(m) != 2 || !t || (t[0] != 'Q' && t[0] != 'q' && t[0] != 'I' && t[0] != 'L')) return 0;
        return t[0] == 'I' ? ((unsigned (*)(id, SEL))objc_msgSend)(o, s) : ((unsigned long (*)(id, SEL))objc_msgSend)(o, s);
    } @catch (NSException *e) { return 0; }
}
// The screen that stands for a display: the one SpringBoard's own window scene on it uses (the shell UI screen, where the bar, the Dock and the
// windows are: S1, never the first non-main screen, which has no scene), else the first with that key.
__attribute__((noinline)) static UIScreen *DMDispDesktopScreen(NSString *display, NSArray<UIScreen *> *screens) {
    UIScreen *first = nil;
    for (UIScreen *s in screens) if ([DMDispKeyOfScreen(s) isEqualToString:display] && !first) first = s;
    @try {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes)
            if ([sc isKindOfClass:[UIWindowScene class]] && [DMDispKeyOfScreen(((UIWindowScene *)sc).screen) isEqualToString:display]) return ((UIWindowScene *)sc).screen;
    } @catch (NSException *e) {}
    return first;
}
// What is known of a connected display now (name: the EDID product name, else the configuration's; SpringBoard's own name follows,
// DMDispAskNames). Only what was read is written.
static NSMutableDictionary *DMDispInfoNow(NSString *display, NSArray<UIScreen *> *screens) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    UIScreen *s = DMDispDesktopScreen(display, screens);
    if (!s) return info;
    id cfg = MSBDDispConfigOfScreen(s), cad = MSBDDispCADisplayOfConfig(cfg);
    NSString *name = MSBDDispStr(MSBDDispGet(cad, "productName")) ?: MSBDDispStr(MSBDDispGet(cfg, "name"));
    if (name) info[@"name"] = name;
    const char *route = MSBDDispRouteOf(MSBDDispStr(MSBDDispGet(cad, "deviceName")).UTF8String);
    if (route) info[@"route"] = @(route);
    id mode = MSBDDispGet(cad, "currentMode");
    unsigned long pw = DMDispGetUnsigned(mode, "width"), ph = DMDispGetUnsigned(mode, "height");
    if (pw && ph) info[@"px"] = [NSString stringWithFormat:@"%lux%lu", pw, ph];
    CGRect b = s.bounds;
    if (b.size.width > 0 && b.size.height > 0) info[@"points"] = [NSString stringWithFormat:@"%.0fx%.0f", b.size.width, b.size.height];
    if (s.scale > 0) info[@"scale"] = @(s.scale);
    // (1.8.7 commit 11: SpringBoard has a window scene of its own on it -- a desktop of its own, not a mirror of the iPad: Settings has no screens to
    //  tell, and greys a mirror's rows with the mirror's footer)
    BOOL desktop = NO;
    @try {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes)
            if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen == s) desktop = YES;
    } @catch (NSException *e) {}
    info[@"desktop"] = @(desktop);
    return info;
}
static id gDMDispNameClient;   // (SpringBoard's own client of its external display service, kept while an answer is pending)
// SpringBoard's own name of each connected display (SBSConnectedDisplayInfo -displayName, matched by its identifier = the key's id: S1), written
// into the display's info when it differs. Apple's client, as Settings uses it; the call shape-checked (16.7.7 and 18.5 answered it, 10 / 11 Nov).
static void DMDispAskNames(void) {
    Class K = objc_getClass("SBSExternalDisplayService");
    SEL g = sel_registerName("getConnectedDisplayInfoWithCompletionHandler:");
    if (!gDMDispConnected.count || !K) return;
    if (!gDMDispNameClient) { @try { gDMDispNameClient = [K new]; } @catch (NSException *e) { return; } }
    Method m = gDMDispNameClient ? class_getInstanceMethod(object_getClass(gDMDispNameClient), g) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v24@0:8@?16") != 0) { DMLog(@"[dispprefs] no SBSExternalDisplayService -getConnectedDisplayInfoWithCompletionHandler: as expected: names from the display itself"); return; }
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(gDMDispNameClient, g, ^(NSArray *infos, id err) {
            NSArray *list = [infos isKindOfClass:[NSArray class]] ? [infos copy] : @[];
            dispatch_async(dispatch_get_main_queue(), ^{
                CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
                BOOL wrote = NO;
                for (id i in list) {
                    NSString *ident = MSBDDispStr(MSBDDispGet(i, "identifier")), *name = MSBDDispStr(MSBDDispGet(i, "displayName"));
                    char key[96];
                    if (!ident || !name || MSBDDispKeyFrom(0, ident.UTF8String, NULL, key, sizeof key) != kMSBDDispKeyId || ![gDMDispConnected containsObject:@(key)]) continue;
                    NSString *ik = [@(key) stringByAppendingString:@MSBD_DISP_INFO_SUFFIX];
                    NSDictionary *old = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)ik, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
                    if (![old isKindOfClass:[NSDictionary class]] || [old[@"name"] isEqual:name]) continue;
                    NSMutableDictionary *info = [old mutableCopy];
                    info[@"name"] = name;
                    CFPreferencesSetValue((__bridge CFStringRef)ik, (__bridge CFPropertyListRef)info, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                    wrote = YES;
                    DMLog([NSString stringWithFormat:@"[dispprefs] %@ is called %@ (SpringBoard's name)", @(key), name]);
                }
                if (wrote) { CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); notify_post(MSBD_DISP_NOTIFY); }
                gDMDispNameClient = nil;
            });
        });
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[dispprefs] asking the displays' names: %@", e.reason]); gDMDispNameClient = nil; }
}
// The displays whose Mac Switcher desktops are their own (common/DisplayPrefs.h MSBDDispMSWBusy: two or more desktops, or a window record on one),
// as the Mac Switcher's file has them (MSWDisplays.h: version 2's "displays" {key: {desktops}}, the window records "windows" {window: desktop id}).
// The file, not the Mac Switcher's models: with the Mac Switcher off those are not loaded, and the other displays' desktops stay in the file all
// the same. Read only when the registry is over its limit (review of 1.8.7: a display forgotten here loses its desktops too, DMMSWForgetGone).
static NSSet<NSString *> *DMDispMSWOwn(void) {
    NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@MSBD_MSW_STATE_FILE]];
    NSDictionary *ds = [st[@"displays"] isKindOfClass:[NSDictionary class]] ? st[@"displays"] : nil, *win = [st[@"windows"] isKindOfClass:[NSDictionary class]] ? st[@"windows"] : nil;
    NSMutableSet<NSString *> *out = [NSMutableSet set];
    for (NSString *k in ds) {
        NSArray *list = [k isKindOfClass:[NSString class]] && [ds[k] isKindOfClass:[NSDictionary class]] && [ds[k][@"desktops"] isKindOfClass:[NSArray class]] ? ds[k][@"desktops"] : nil;
        NSMutableSet<NSNumber *> *desks = [NSMutableSet set];
        for (id n in list) if ([n isKindOfClass:[NSNumber class]]) [desks addObject:n];
        int records = 0;
        for (id w in win) if ([win[w] isKindOfClass:[NSNumber class]] && [desks containsObject:win[w]]) records++;
        if (MSBDDispMSWBusy((int)desks.count, records)) [out addObject:k];
    }
    return out;
}
// Whether a remembered display holds something of the user's own (MSBDDispSeen's hasOwn: the 8-display limit forgets the plain ones first): a
// setting of its own (DisplayRowStore.h MSBDDispStoreHasOwn, what Use iPad Settings is offered for), a More Space record (disp/scalePending, the
// crash revert's) or Mac Switcher desktops of its own (`mswOwn`, DMDispMSWOwn).
static BOOL DMDispHasOwn(NSDictionary *all, NSString *display, NSSet<NSString *> *mswOwn) {
    char flat[MSBD_DISP_FLAT_MAX + 1];
    if (MSBDDispStoreHasOwn(all, display) || [mswOwn containsObject:display]) return YES;
    return MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, "disp", MSBD_DISP_SCALE_PENDING_KEY) && all[@(flat)] != nil;
}
// The registry brought up to date with the screens now (on connect, on disconnect, once after the start): each connected display's info (its
// first and last time seen), the ones gone since seen until now, "connected", the 8-display limit (the plain ones first); then the cache.
__attribute__((noinline)) static void DMDispRegistryUpdate(NSString *why) {
    [gDMDispScreenKeys removeAllObjects];
    if (!gDMDispLayerOn) {   // (the master switch gates it: DMDispInit; "connected" is let go, as nothing keeps it now)
        gDMDispConnected = @[];
        BOOL dropped = MSBDDispStoreDropConnected();
        DMLog([NSString stringWithFormat:@"[dispprefs] %@: Display Settings is off, the registry is not written%@", why, dropped ? @" (its connected list let go)" : @""]);
        return;
    }
    NSArray<UIScreen *> *screens = DMDispScreens();
    NSMutableArray<NSString *> *now = [NSMutableArray array];
    for (UIScreen *s in screens) { NSString *k = DMDispKeyOfScreen(s); if (k && ![now containsObject:k]) [now addObject:k]; }
    [now sortUsingSelector:@selector(compare:)];
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *all = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (![all isKindOfClass:[NSDictionary class]]) all = @{};
    NSArray *was = [all[@MSBD_DISP_CONNECTED_KEY] isKindOfClass:[NSArray class]] ? all[@MSBD_DISP_CONNECTED_KEY] : @[];
    NSMutableDictionary *write = [NSMutableDictionary dictionary];
    NSMutableArray *remove = [NSMutableArray array];
    long t = (long)time(NULL);
    NSMutableDictionary<NSString *, NSDictionary *> *infos = [NSMutableDictionary dictionary];   // (every remembered display's info, as it will be)
    for (NSString *k in all) {
        if (![k isKindOfClass:[NSString class]] || ![k hasSuffix:@MSBD_DISP_INFO_SUFFIX]) continue;
        NSString *d = [k substringToIndex:k.length - strlen(MSBD_DISP_INFO_SUFFIX)];
        if (MSBDDispKeyValid(d.UTF8String) && [all[k] isKindOfClass:[NSDictionary class]]) infos[d] = all[k];
    }
    for (NSString *d in now) {
        NSDictionary *old = infos[d];
        NSMutableDictionary *info = DMDispInfoNow(d, screens);
        if ([old[@"name"] isKindOfClass:[NSString class]]) info[@"name"] = old[@"name"];   // (SpringBoard's own name, once known, stays)
        for (NSString *f in @[@"scales", @"scaleNow", @"scaleNames", @"overscan"]) if (old[f]) info[f] = old[f];   // (More Space's reading, MoreSpace.h: read again after a connect)
        info[@"firstSeen"] = [old[@"firstSeen"] isKindOfClass:[NSNumber class]] ? old[@"firstSeen"] : @(t);
        info[@"lastSeen"] = @(t);
        infos[d] = info; write[[d stringByAppendingString:@MSBD_DISP_INFO_SUFFIX]] = info;
        if (!old) DMLog([NSString stringWithFormat:@"[dispprefs] a new display: %@ (%@)", d, info]);
    }
    for (NSString *d in was) {   // (gone since: seen until now)
        if (![d isKindOfClass:[NSString class]] || [now containsObject:d] || !infos[d]) continue;
        NSMutableDictionary *info = [infos[d] mutableCopy];
        info[@"lastSeen"] = @(t);
        infos[d] = info; write[[d stringByAppendingString:@MSBD_DISP_INFO_SUFFIX]] = info;
    }
    if (![was isEqualToArray:now]) write[@MSBD_DISP_CONNECTED_KEY] = now;
    // (at most 8 remembered: one not connected goes, with every key of it -- the one seen longest ago of those with nothing of the user's own; one
    //  with something only when every one has, MSBDDispForgetPick)
    NSMutableArray<NSString *> *remembered = [[infos allKeys] mutableCopy];
    [remembered sortUsingSelector:@selector(compare:)];
    NSSet<NSString *> *mswOwn = (int)remembered.count > MSBD_DISP_REMEMBER_MAX ? DMDispMSWOwn() : nil;
    while ((int)remembered.count > MSBD_DISP_REMEMBER_MAX) {
        int n = (int)remembered.count;
        MSBDDispSeen *list = calloc((size_t)n, sizeof(MSBDDispSeen));
        if (!list) break;
        for (int i = 0; i < n; i++) {
            id ls = infos[remembered[i]][@"lastSeen"];
            list[i].key = remembered[i].UTF8String; list[i].lastSeen = [ls isKindOfClass:[NSNumber class]] ? [ls longValue] : 0; list[i].connected = [now containsObject:remembered[i]];
            list[i].hasOwn = DMDispHasOwn(all, remembered[i], mswOwn);
        }
        int pick = MSBDDispForgetPick(list, n, MSBD_DISP_REMEMBER_MAX);
        BOOL own = pick >= 0 && list[pick].hasOwn;
        free(list);
        if (pick < 0) break;
        NSString *gone = remembered[pick], *prefix = [gone stringByAppendingString:@"/"];
        int keys = 0;
        for (NSString *k in all) if ([k isKindOfClass:[NSString class]] && [k hasPrefix:prefix]) { [remove addObject:k]; keys++; }
        [write removeObjectForKey:[gone stringByAppendingString:@MSBD_DISP_INFO_SUFFIX]];
        [remembered removeObjectAtIndex:(NSUInteger)pick];
        DMLog([NSString stringWithFormat:@"[dispprefs] more than %d displays remembered: %@ (seen longest ago%@) forgotten with its %d key(s)", MSBD_DISP_REMEMBER_MAX, gone,
               own ? @"; every one not connected has settings or desktops of its own" : @", nothing of its own", keys]);
    }
    if (write.count || remove.count) {
        CFPreferencesSetMultiple((__bridge CFDictionaryRef)write, remove.count ? (__bridge CFArrayRef)remove : NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        notify_post(MSBD_DISP_NOTIFY);   // (Settings' Displays group follows; this part reads it again below)
    }
    BOOL changed = ![gDMDispConnected isEqualToArray:now];
    gDMDispConnected = [now copy];
    DMDispReload();
    if (changed || write.count) DMLog([NSString stringWithFormat:@"[dispprefs] %@: connected %@; %lu written, %lu removed", why, now.count ? [now componentsJoinedByString:@", "] : @"none", (unsigned long)write.count, (unsigned long)remove.count]);
    if (changed && now.count) DMDispAskNames();
}
// Connect and disconnect come as several notes (the TV's three screens one by one): one update 0.6 s after the last.
static void DMDispScheduleUpdate(NSString *why) {
    static unsigned gen = 0;
    unsigned mine = ++gen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (mine == gen) DMDispRegistryUpdate(why); });
}
// SpringBoard's status bar part, at its start (Mac Status Bar on, the Mac status bar in use). The master switch is read first: off (the crash guard's
// step for Display Settings, or the user), the registry, its names and its screen reads do not run -- only the domain's posts are listened to, and
// the switch turned on again starts them (a registry update then, as at the start).
static void DMDispInit(void) {
    DM_FEATURE_MARK("display-prefs");
    DMDispReload();
    if (!gDMDispLayerOn) DMLog([NSString stringWithFormat:@"[dispprefs] Display Settings is off: no registry, every display takes the iPad's settings (and its display defaults)%@",
                                MSBDDispStoreDropConnected() ? @"; the connected list let go" : @""]);   // (nothing keeps it while off: Settings shows every display not connected)
    [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { if (gDMDispLayerOn) DMDispScheduleUpdate(@"a display connected"); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenDidDisconnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { if (gDMDispLayerOn) DMDispScheduleUpdate(@"a display disconnected"); }];
    // (a display's own window scene comes and goes after its screen -- Stage Manager on or off: its desktop or a mirror, the registry's "desktop")
    for (NSString *name in @[UISceneWillConnectNotification, UISceneDidDisconnectNotification])
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
            UIScene *sc = [n.object isKindOfClass:[UIWindowScene class]] ? n.object : nil;
            UIScreen *scr = nil; @try { scr = ((UIWindowScene *)sc).screen; } @catch (NSException *e) {}
            if (gDMDispLayerOn && sc && scr != [UIScreen mainScreen]) DMDispScheduleUpdate(@"a display's scene came or went");
        }];
    static int tokens[3];
    const char *names[3] = { MSBD_DISP_NOTIFY, "com.besiktasliseba.macstatusbar/prefsChanged", "com.besiktasliseba.dockmagnification/prefsChanged" };
    for (int i = 0; i < 3; i++) notify_register_dispatch(names[i], &tokens[i], dispatch_get_main_queue(), ^(int tok) {
        BOOL was = gDMDispLayerOn;
        DMDispReload();
        if (!was && gDMDispLayerOn) DMDispScheduleUpdate(@"Display Settings switched on");
        if (was && !gDMDispLayerOn) DMDispRegistryUpdate(@"Display Settings switched off");   // (its connected list let go: nothing keeps it now)
    });
    if (gDMDispLayerOn) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gDMDispLayerOn) DMDispRegistryUpdate(@"SpringBoard started"); });
}
