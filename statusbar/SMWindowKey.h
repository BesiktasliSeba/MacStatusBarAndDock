// SMWindowKey.h -- the Stage Manager engine knows each window by its own scene, not by its app (M-2, sm-multiwin, 6 Oct 2026). Plain Foundation:
// StatusBar.x, SMDeskJoin.h and the Mac test tools/test-smwindowkey.m run this very code.
// A Stage Manager window is one scene of its app: an SBDisplayItem whose -uniqueIdentifier ("sceneID:<bundle>-<suffix>") is also the workspace
// entity's -uniqueIdentifier (-[SBApplicationSceneEntity _initWithSceneHandle:] takes the scene handle's identifier), the layout state element's,
// and the end of the window card's name ("card:<bundle>:<uniqueIdentifier>", -[SBFluidSwitcherItemContainer _updateAccessibilityIdentifier]; all
// 16.7.7 disassembled). An app can have several windows (iPadOS multi-window: Safari's "Open in New Window", a note dragged out, App Expose's
// "+"). The engine knew windows by their app: a second window of an app on the desktop counted as "already there" and could not join it, every
// request named the app's default scene for each of its windows (one scene in two roles), and the traffic lights, Minimize, full screen, Fit and
// the title bar acted on "the" window of the app -- whichever came first.
// A window's KEY: "<bundle>|<uniqueIdentifier>" (a bundle identifier never holds a "|"). An APP key -- the bundle alone -- stands for the app's
// windows, as before: what callers that know only the app hand in (the menu bar's lights and the Window menu act on the app's newest window),
// an app asked for before its window exists (Fit's question before a launch), settings saved by an older version, and every key where the windows
// can't be told apart (the optional check rows SBDisplayItem -uniqueIdentifier / -_entityForDisplayItem:displayIdentity: missing): then the
// engine works by app, exactly as before. An app with one window: its window key does what its app key did.
#pragma once
#import <Foundation/Foundation.h>

static NSString *DMSMKeyMake(NSString *bundle, NSString *uid) {
    if (![bundle isKindOfClass:[NSString class]] || !bundle.length || [bundle rangeOfString:@"|"].location != NSNotFound) return nil;
    if (![uid isKindOfClass:[NSString class]] || !uid.length) return bundle;
    return [NSString stringWithFormat:@"%@|%@", bundle, uid];
}
static NSString *DMSMKeyBundle(NSString *key) {
    if (![key isKindOfClass:[NSString class]] || !key.length) return nil;
    NSRange r = [key rangeOfString:@"|"];
    return r.location == NSNotFound ? key : [key substringToIndex:r.location];
}
static NSString *DMSMKeyUid(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) return nil;
    NSRange r = [key rangeOfString:@"|"];
    return r.location == NSNotFound || r.location + 1 >= key.length ? nil : [key substringFromIndex:r.location + 1];
}
static BOOL DMSMKeyIsApp(NSString *key) { return [key isKindOfClass:[NSString class]] && key.length && [key rangeOfString:@"|"].location == NSNotFound; }
// The window a card shows, from its name "card:<bundle>:<uniqueIdentifier>" (the identifier has colons of its own: everything after the bundle's).
// perWindow NO: its app key.
static NSString *DMSMKeyFromCardName(NSString *name, BOOL perWindow) {
    if (![name isKindOfClass:[NSString class]] || ![name hasPrefix:@"card:"]) return nil;
    NSString *rest = [name substringFromIndex:5];
    NSRange c = [rest rangeOfString:@":"];
    NSString *bundle = c.location == NSNotFound ? rest : [rest substringToIndex:c.location];
    NSString *uid = c.location == NSNotFound ? nil : [rest substringFromIndex:c.location + 1];
    return DMSMKeyMake(bundle, perWindow ? uid : nil);
}
// A key as the log shows it: the app, and for a window the end of its scene's identifier ("com.apple.freeform/3E2F1A90", ".../default").
static NSString *DMSMKeyText(NSString *key) {
    NSString *b = DMSMKeyBundle(key), *u = DMSMKeyUid(key);
    if (!b) return @"?";
    if (!u) return b;
    NSRange dash = [u rangeOfString:@"-" options:NSBackwardsSearch];
    NSString *tail = dash.location != NSNotFound && dash.location + 1 < u.length ? [u substringFromIndex:dash.location + 1] : u;
    if (tail.length > 8) tail = [tail substringFromIndex:tail.length - 8];
    return [NSString stringWithFormat:@"%@/%@", b, tail];
}
// Does a key stand for this window? The window's own key, or its app's key.
static BOOL DMSMKeyCovers(NSString *key, NSString *window) {
    if (![key isKindOfClass:[NSString class]] || ![window isKindOfClass:[NSString class]] || !key.length || !window.length) return NO;
    if ([key isEqualToString:window]) return YES;
    return DMSMKeyIsApp(key) && [key isEqualToString:DMSMKeyBundle(window)];
}
// Does a set of asked keys stand for this window (the desktop choice's "holds what is asked for", StatusBar.x DMSMDesktopFor)? One of them is the
// window's own key or its app's key, or the window's key is an app key covering one of them (windows told apart by app).
static BOOL DMSMKeysHold(NSSet<NSString *> *asked, NSString *window) {
    if (![window isKindOfClass:[NSString class]] || !window.length) return NO;
    for (NSString *w in asked) if (DMSMKeyCovers(w, window) || DMSMKeyCovers(window, w)) return YES;
    return NO;
}
// The window keys of a saved set (the minimized windows) that name no window any more: not among `present` (every window of every recent stage).
// App keys stay: an older version's entry for the app's windows, which goes when one of them is opened. (A window's scene ends with its stage: an
// app quit from the App Switcher, or force quit another way, left its minimized window's key in the saved set for good -- 1.3.9 logic test L-3.)
static NSSet<NSString *> *DMSMKeysGone(NSSet<NSString *> *set, NSSet<NSString *> *present) {
    NSMutableSet<NSString *> *gone = [NSMutableSet set];
    for (NSString *k in set) if ([k isKindOfClass:[NSString class]] && k.length && !DMSMKeyIsApp(k) && ![present containsObject:k]) [gone addObject:k];
    return gone;
}
// Which of `windows` (@{@"k": window key, @"t": last interaction time}) a key names: that very window; else, where one of the two is an app key, the
// newest window of that app (the app's front window: where a Mac's menu commands go). A window key of a window that is not there names none -- never
// another window of its app. NSNotFound: none.
static NSUInteger DMSMKeyPick(NSArray<NSDictionary *> *windows, NSString *key) {
    if (![key isKindOfClass:[NSString class]] || !key.length) return NSNotFound;
    NSUInteger best = NSNotFound; long long bestT = LLONG_MIN;
    for (NSUInteger i = 0; i < windows.count; i++) {
        NSString *k = windows[i][@"k"];
        if (![k isKindOfClass:[NSString class]]) continue;
        if ([k isEqualToString:key]) return i;
        if (!DMSMKeyCovers(key, k) && !DMSMKeyCovers(k, key)) continue;
        long long t = [windows[i][@"t"] longLongValue];
        if (best == NSNotFound || t > bestT) { best = i; bestT = t; }
    }
    return best;
}
// A set of keys says something about a window (minimized, behind the Dock, left out of Fit): its own key is there, or its app's key (an entry for
// the app's windows: saved by an older version, or made where windows could not be told apart). An app key asked: any window of that app.
static BOOL DMSMKeySetHas(NSSet<NSString *> *set, NSString *key) {
    if (![key isKindOfClass:[NSString class]] || !key.length || !set.count) return NO;
    if ([set containsObject:key]) return YES;
    if (!DMSMKeyIsApp(key)) return [set containsObject:DMSMKeyBundle(key)];
    for (NSString *k in set) if ([DMSMKeyBundle(k) isEqualToString:key]) return YES;
    return NO;
}
// Takes back what the set says about a window: its own key and its app's key (the window is the app's: an app-wide entry no longer holds for it).
// An app key: every entry of the app. YES when something was taken out.
static BOOL DMSMKeySetRemove(NSMutableSet<NSString *> *set, NSString *key) {
    if (![key isKindOfClass:[NSString class]] || !key.length || !set.count) return NO;
    BOOL changed = NO;
    if (DMSMKeyIsApp(key)) {
        for (NSString *k in [set allObjects]) if ([DMSMKeyBundle(k) isEqualToString:key]) { [set removeObject:k]; changed = YES; }
        return changed;
    }
    if ([set containsObject:key]) { [set removeObject:key]; changed = YES; }
    NSString *b = DMSMKeyBundle(key);
    if (b && [set containsObject:b]) { [set removeObject:b]; changed = YES; }
    return changed;
}
// The entry a keyed dictionary has for a window (gSMPreZoom: a window's place before full screen): its own key's, else its app key's; for an app
// key, the entry of one of the app's windows (the first by key, for a stable answer). Returns the key it is stored under, nil when none.
static NSString *DMSMKeyLookup(NSDictionary *dict, NSString *key) {
    if (![key isKindOfClass:[NSString class]] || !key.length || !dict.count) return nil;
    if (dict[key]) return key;
    if (!DMSMKeyIsApp(key)) { NSString *b = DMSMKeyBundle(key); return b && dict[b] ? b : nil; }
    NSString *found = nil;
    for (NSString *k in dict) if ([DMSMKeyBundle(k) isEqualToString:key] && (!found || [k compare:found] == NSOrderedAscending)) found = k;
    return found;
}
// An arrangement made before its windows were known (Fit's question before a launch: "Where should X go?" -- X has no window yet) names the app:
// once windows are there, each app key that is no window's own key goes to that app's newest window (windows: newest first) that has no entry of
// its own. slots: key -> anything. Returns the same object when nothing changed.
static NSDictionary *DMSMKeysAdopt(NSDictionary *slots, NSArray<NSString *> *windows) {
    if (!slots.count || !windows.count) return slots;
    NSMutableDictionary *out = nil;
    for (NSString *k in [slots.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (!DMSMKeyIsApp(k) || [windows containsObject:k]) continue;   // (a window's own key -- or the app's key IS the window's: windows by app)
        NSDictionary *now = out ?: slots;
        for (NSString *w in windows) {
            if (DMSMKeyIsApp(w) || ![DMSMKeyBundle(w) isEqualToString:k] || now[w]) continue;
            if (!out) out = [slots mutableCopy];
            out[w] = out[k];
            [out removeObjectForKey:k];
            break;
        }
    }
    return out ?: slots;
}
// The same for a set of keys (Fit's No Fit chosen before a launch). Returns the same object when nothing changed.
static NSSet<NSString *> *DMSMKeySetAdopt(NSSet<NSString *> *set, NSArray<NSString *> *windows) {
    if (!set.count || !windows.count) return set;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in set) d[k] = @YES;
    NSDictionary *a = DMSMKeysAdopt(d, windows);
    return a == d ? set : [NSSet setWithArray:a.allKeys];
}
