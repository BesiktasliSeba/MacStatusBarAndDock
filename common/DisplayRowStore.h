// DisplayRowStore.h -- what a display's rows show and the one writer of a display's changes (MacStatusBar&Dock 1.8.7 commits 11 and 12;
// plans/design-1.8.7-displays.md sections 3 and 6). Foundation and CoreFoundation only: SpringBoard's Display Settings window
// (statusbar/DisplaySettings.h, through statusbar/DisplayPrefs.h DMDispWrite) and Settings' Displays page (MSBDisplaysController.m) read and write
// through it, so both show the same values and write the same keys. No screens and no private calls: the display is known by its key, what SpringBoard
// wrote of it (the registry) and its overrides, all in the displays domain.
//  - The iPad's value of a row: KT's own key in its domain (msb: com.besiktasliseba.macstatusbar, dock: com.besiktasliseba.dockmagnification), read
//    only, as the iPad's Settings shows it (never set: the row's iPad default). Never written here.
//  - What a display shows: its override when it is of the row's type (DisplayPrefs.h MSBDDispTypeOK; a choice's number a whole index, a text choice
//    text), else the row's display default (Show Trash in Dock: on), else the iPad's -- the rule (MSBDDispResolve), as SpringBoard's getters read it.
//  - A change: the override written even when it equals the iPad's (from then it sticks), deleted for a reset; a switch turned on noted in the crash
//    guard's RecentlyOn list by its flat key (a switch's reset or off takes its line out); the displays domain's prefsChanged posted.
//  - Use iPad Settings: every override of that display deleted. Forget This Display: every key of it (its info and its overrides).
#pragma once
#import <Foundation/Foundation.h>
#include <notify.h>
#include <time.h>
#include "DisplayPrefs.h"
#include "DisplayRows.h"
#include "DisplayScale.h"   // (More Space, commit 13: a display's scales as iPadOS lists them)
#include "CrashGuard.h"   // (MSBD_GUARD_RECENT: the crash guard's list of switches turned on)

static inline CFStringRef MSBDDispDomainOfPart(const char *part) {
    if (!part) return NULL;
    if (strcmp(part, "msb") == 0) return CFSTR(MSBD_DISP_MSB_DOMAIN);
    if (strcmp(part, "dock") == 0) return CFSTR(MSBD_DISP_DOCK_DOMAIN);
    return NULL;   // (disp: display-only rows, no iPad key)
}
// The displays domain as it is now (synchronized first: another process may have written it).
static inline NSDictionary *MSBDDispStoreAll(void) {
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *all = CFBridgingRelease(CFPreferencesCopyMultiple(NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    return [all isKindOfClass:[NSDictionary class]] ? all : @{};
}
static inline BOOL MSBDDispStoreLayerOn(NSDictionary *all) { id m = all[@MSBD_DISP_MASTER_KEY]; return ![m isKindOfClass:[NSNumber class]] || [m boolValue]; }
static inline NSArray<NSString *> *MSBDDispStoreConnected(NSDictionary *all) {
    NSMutableArray *out = [NSMutableArray array];
    id c = all[@MSBD_DISP_CONNECTED_KEY];
    if ([c isKindOfClass:[NSArray class]]) for (id k in c) if ([k isKindOfClass:[NSString class]] && MSBDDispKeyValid([k UTF8String])) [out addObject:k];
    return out;
}
static inline NSDictionary *MSBDDispStoreInfo(NSDictionary *all, NSString *display) {
    id i = display ? all[[display stringByAppendingString:@MSBD_DISP_INFO_SUFFIX]] : nil;
    return [i isKindOfClass:[NSDictionary class]] ? i : nil;
}
// Every remembered display (its info is there), the connected ones first, then the one seen most recently.
static inline NSArray<NSString *> *MSBDDispStoreRemembered(NSDictionary *all) {
    NSArray *connected = MSBDDispStoreConnected(all);
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    for (NSString *k in all) {
        if (![k isKindOfClass:[NSString class]] || ![k hasSuffix:@MSBD_DISP_INFO_SUFFIX]) continue;
        NSString *d = [k substringToIndex:k.length - strlen(MSBD_DISP_INFO_SUFFIX)];
        if (MSBDDispKeyValid(d.UTF8String) && [all[k] isKindOfClass:[NSDictionary class]]) [list addObject:d];
    }
    [list sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL ca = [connected containsObject:a], cb = [connected containsObject:b];
        if (ca != cb) return ca ? NSOrderedAscending : NSOrderedDescending;
        long la = [MSBDDispStoreInfo(all, a)[@"lastSeen"] longValue], lb = [MSBDDispStoreInfo(all, b)[@"lastSeen"] longValue];
        return la == lb ? [a compare:b] : la > lb ? NSOrderedAscending : NSOrderedDescending;
    }];
    return list;
}
// The name shown: SpringBoard's (or the display's own) name from the registry, else "External Display"; the mode as "3840 x 2160".
static inline NSString *MSBDDispStoreName(NSDictionary *info) {
    NSString *n = [info[@"name"] isKindOfClass:[NSString class]] ? info[@"name"] : nil;
    return n.length ? n : @"External Display";
}
static inline NSString *MSBDDispStoreMode(NSDictionary *info) {
    NSString *px = [info[@"px"] isKindOfClass:[NSString class]] ? info[@"px"] : nil;
    NSArray *wh = [px componentsSeparatedByString:@"x"];
    return wh.count == 2 && [wh[0] integerValue] > 0 && [wh[1] integerValue] > 0 ? [NSString stringWithFormat:@"%ld x %ld", (long)[wh[0] integerValue], (long)[wh[1] integerValue]] : nil;
}

// ---- a row's values ------------------------------------------------------------------------------------------------------------------------------
static inline BOOL MSBDDispIsBool(id v) { return v && CFGetTypeID((__bridge CFTypeRef)v) == CFBooleanGetTypeID(); }
// A stored value in the row's own form: a switch @YES / @NO, a slider a number, a numeric choice its index, a text choice its text; nil when it is
// not of the row's type (a switch also takes the number 0 / 1, as `defaults write -int` stores it; a number out of range is not taken, never clamped).
static inline id MSBDDispRowForm(const MSBDDispRow *r, id v) {
    if (!r || !v) return nil;
    BOOL isBool = MSBDDispIsBool(v), isNum = !isBool && [v isKindOfClass:[NSNumber class]];
    double num = (isBool || isNum) ? [v doubleValue] : 0;
    switch (r->kind) {
        case kMSBDRowSwitch:
            return MSBDDispTypeOK(kMSBDDispWantBool, isBool ? kMSBDDispVBool : isNum ? kMSBDDispVNumber : kMSBDDispVOther, num, 0, 0, 0) ? @(num != 0) : nil;
        case kMSBDRowSlider:
            return isNum && MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, num, 1, r->lo, r->hi) ? @(num) : nil;
        case kMSBDRowChoice:
            if (r->choiceValues[0]) return [v isKindOfClass:[NSString class]] ? @(r->choiceValues[MSBDDispChoiceIndexText(r, [v UTF8String])]) : nil;
            return isNum && MSBDDispChoiceIndexNum(r, num) >= 0 ? @((int)num) : nil;
        default: return nil;
    }
}
// The iPad's value of a row (KT's key, read only; never set or not of the row's form: the row's iPad default). Menu Bar Size: the crash guard's
// false is not a number, so it reads as the default, Small (as MenuBarSize.h MSBDMenuBarSizeFrom).
static inline id MSBDDispRowIPadValue(const MSBDDispRow *r) {
    if (!r) return nil;
    id def = r->kind == kMSBDRowSwitch ? (id)@(r->ipadDefault != 0)
           : (r->kind == kMSBDRowChoice && r->choiceValues[0]) ? (id)@(r->choiceValues[(int)r->ipadDefault]) : (id)@(r->ipadDefault);
    CFStringRef dom = MSBDDispDomainOfPart(r->part);
    if (!dom) return def;
    id v = CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)@(r->key), dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    return MSBDDispRowForm(r, v) ?: def;
}
static inline NSString *MSBDDispRowFlat(NSString *display, const MSBDDispRow *r) {
    char flat[MSBD_DISP_FLAT_MAX + 1];
    return display && r && MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, r->part, r->key) ? @(flat) : nil;
}
// What the display shows for a row now, by the rule: *from says where it comes from (kMSBDDispFrom...); an override of the wrong form counts as
// not set. The master switch off: every override dormant.
static inline id MSBDDispRowShownValue(NSDictionary *all, NSString *display, const MSBDDispRow *r, int *from) {
    int f = kMSBDDispFromIPad;
    id ov = MSBDDispRowForm(r, all[MSBDDispRowFlat(display, r) ?: @""]);
    int def = 0, hasDef = r ? MSBDDispDisplayDefault(r->part, r->key, &def) : 0;
    f = MSBDDispResolve(display == nil, MSBDDispStoreLayerOn(all), all[MSBDDispRowFlat(display, r) ?: @""] != nil, ov != nil, hasDef);
    if (from) *from = f;
    if (f == kMSBDDispFromOverride) return ov;
    if (f == kMSBDDispFromDefault) return @(def != 0);
    return MSBDDispRowIPadValue(r);
}
// The text shown for a row's display default or the iPad's value beside its reset ("Default: On", "iPad: Large").
static inline NSString *MSBDDispRowValueText(const MSBDDispRow *r, id v) {
    if (!r || !v) return @"";
    switch (r->kind) {
        case kMSBDRowSwitch: return [v boolValue] ? @"On" : @"Off";
        case kMSBDRowSlider: return [NSString stringWithFormat:@"%.2f", [v doubleValue]];
        case kMSBDRowChoice: {
            int i = r->choiceValues[0] ? MSBDDispChoiceIndexText(r, [v isKindOfClass:[NSString class]] ? [v UTF8String] : "") : MSBDDispChoiceIndexNum(r, [v doubleValue]);
            return i >= 0 ? @(r->choiceTitles[i]) : @"";
        }
        default: return @"";
    }
}

// More Space (commit 13): a display's choices from its info ({scale, title} in the scales' order), empty without a choice or with More Space off (its
// own switch, displayScale, or Display Settings off); *now the scale in use. Settings sets one by a request key (MSBD_DISP_SCALE_REQUEST_KEY), as it
// has no display service: SpringBoard sets it (statusbar/MoreSpace.h).
#define MSBD_DISP_SCALE_SWITCH_KEY "displayScale"   // (More Space's own switch, the crash guard's displayScale target)
static inline BOOL MSBDDispStoreSwitchOn(NSDictionary *all, const char *key) { id v = key ? all[@(key)] : nil; return ![v isKindOfClass:[NSNumber class]] || [v boolValue]; }
static inline BOOL MSBDDispStoreScaleOn(NSDictionary *all) { return MSBDDispStoreLayerOn(all) && MSBDDispStoreSwitchOn(all, MSBD_DISP_SCALE_SWITCH_KEY); }
static inline NSArray<NSArray *> *MSBDDispStoreScaleChoices(NSDictionary *all, NSDictionary *info, int *now) {
    unsigned long long mask = [info[@"scales"] isKindOfClass:[NSNumber class]] ? [info[@"scales"] unsignedLongLongValue] : 0;
    if (now) *now = [info[@"scaleNow"] isKindOfClass:[NSNumber class]] ? [info[@"scaleNow"] intValue] : 0;
    if (!MSBDDispScaleRowWanted(mask) || !MSBDDispStoreScaleOn(all)) return @[];
    NSDictionary *names = [info[@"scaleNames"] isKindOfClass:[NSDictionary class]] ? info[@"scaleNames"] : @{};
    int listed[MSBD_DISP_SCALE_MAX];
    int n = MSBDDispScaleListed(mask, listed, MSBD_DISP_SCALE_MAX);
    NSMutableArray *out = [NSMutableArray array];
    for (int k = 0; k < n; k++) {
        id a = names[[NSString stringWithFormat:@"%d", listed[k]]];
        NSString *apple = [a isKindOfClass:[NSString class]] ? a : nil;
        const char *t = MSBDDispScaleTitle(apple.UTF8String);
        [out addObject:@[@(listed[k]), t ? @(t) : (apple ?: [NSString stringWithFormat:@"Scale %d", listed[k]])]];
    }
    return out;
}
static inline BOOL MSBDDispStoreOverscanTip(NSDictionary *info) { id o = info[@"overscan"]; return [o isKindOfClass:[NSString class]] && MSBDDispOverscanTip([o UTF8String]); }

// ---- the writer -------------------------------------------------------------------------------------------------------------------------------
// One change for one display (nil value: the row's reset). `wasOn`: what the display showed before (a switch turned on is noted for the crash guard).
// Returns the flat key written, or nil when the layer refuses the key (DisplayPrefs.h MSBDDispFlatKey).
static inline NSString *MSBDDispStoreWrite(NSString *display, const char *part, const char *key, id value, BOOL wasOn, NSString *title) {
    char flat[MSBD_DISP_FLAT_MAX + 1];
    if (!display || !MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, part, key)) return nil;
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    NSString *fk = @(flat);
    CFPreferencesSetValue((__bridge CFStringRef)fk, (__bridge CFPropertyListRef)value, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL isSwitch = MSBDDispIsBool(value), on = isSwitch && [value boolValue];
    if ((isSwitch || !value) && on != wasOn) MSBDDispNoteRecent(MSBD_GUARD_RECENT, (long)time(NULL), flat, title.UTF8String, on);
    notify_post(MSBD_DISP_NOTIFY);
    return fk;
}
// A display's own settings are its rows' overrides only: the keys whose part and key are a row of the table (DisplayRows.h; shown or not -- the TV's
// Trash with Finder off too), never the Resolution row (Apple's own store) or More Space's records (disp/scalePending, the crash revert's {old, new,
// at}, and disp/scaleRequest, Settings' ask). Use iPad Settings deletes exactly these, and the window and Settings' page enable it by the same test.
static inline const MSBDDispRow *MSBDDispStoreRowOfKey(NSString *k, NSString *display) {
    char d[128], p[128], key[128];
    if (![k isKindOfClass:[NSString class]] || !display.length || !MSBDDispFlatSplit(k.UTF8String, d, sizeof d, p, sizeof p, key, sizeof key) || strcmp(d, display.UTF8String) != 0) return NULL;
    const MSBDDispRow *r = MSBDDispRowFor(p, key);
    return r && r->kind != kMSBDRowScale ? r : NULL;
}
static inline NSArray<NSString *> *MSBDDispStoreOwnKeys(NSDictionary *all, NSString *display) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *k in all) if (MSBDDispStoreRowOfKey(k, display)) [out addObject:k];
    return out;
}
// Use iPad Settings is offered (both hosts, with the master switch on): one of them holds a value of its row's form (what the rule takes: the change a
// host shows with its dot, or a hidden row's).
static inline BOOL MSBDDispStoreHasOwn(NSDictionary *all, NSString *display) {
    for (NSString *k in all) { const MSBDDispRow *r = MSBDDispStoreRowOfKey(k, display); if (r && MSBDDispRowForm(r, all[k])) return YES; }
    return NO;
}
// Every own setting of one display (its info, the registry's keys and More Space's records stay): Use iPad Settings. Each switch's crash guard line goes
// with it.
static inline int MSBDDispStoreUseIPad(NSString *display) {
    if (!MSBDDispKeyValid(display.UTF8String)) return 0;
    NSDictionary *all = MSBDDispStoreAll();
    NSArray *gone = MSBDDispStoreOwnKeys(all, display);
    if (!gone.count) return 0;
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)gone, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    for (NSString *k in gone) if (MSBDDispIsBool(all[k])) MSBDDispNoteRecent(MSBD_GUARD_RECENT, (long)time(NULL), k.UTF8String, NULL, 0);
    notify_post(MSBD_DISP_NOTIFY);
    return (int)gone.count;
}
// Forget This Display (one remembered, not connected): every key of it -- "<display>/info" and its overrides. A connected display is never
// forgotten (SpringBoard would write it again at once). Returns the number of keys deleted, -1 when refused.
static inline int MSBDDispStoreForget(NSString *display) {
    if (!MSBDDispKeyValid(display.UTF8String)) return -1;
    NSDictionary *all = MSBDDispStoreAll();
    if ([MSBDDispStoreConnected(all) containsObject:display]) return -1;
    NSString *prefix = [display stringByAppendingString:@"/"];
    NSMutableArray *gone = [NSMutableArray array];
    for (NSString *k in all) if ([k isKindOfClass:[NSString class]] && [k hasPrefix:prefix]) [gone addObject:k];
    if (!gone.count) return 0;
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)gone, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    for (NSString *k in gone) if (MSBDDispIsBool(all[k])) MSBDDispNoteRecent(MSBD_GUARD_RECENT, (long)time(NULL), k.UTF8String, NULL, 0);
    notify_post(MSBD_DISP_NOTIFY);
    return (int)gone.count;
}
// The two switches of the displays domain, Display Settings (MSBD_DISP_MASTER_KEY) and More Space (MSBD_DISP_SCALE_SWITCH_KEY): the crash guard's
// targets displaySettings and displayScale, so each has its row in Settings > Desktop > Displays, where a guard's step that set it off is switched back
// on (absent or true: on). More Space's row is offered where it means something: while it is off, or once a remembered display lists two scales.
static inline BOOL MSBDDispStoreSetSwitch(const char *key, BOOL on) {
    if (!key || (strcmp(key, MSBD_DISP_MASTER_KEY) != 0 && strcmp(key, MSBD_DISP_SCALE_SWITCH_KEY) != 0)) return NO;
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
    CFPreferencesSetValue((__bridge CFStringRef)@(key), on ? kCFBooleanTrue : kCFBooleanFalse, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post(MSBD_DISP_NOTIFY);
    return YES;
}
static inline BOOL MSBDDispStoreScaleSwitchShown(NSDictionary *all) {
    if (!MSBDDispStoreSwitchOn(all, MSBD_DISP_SCALE_SWITCH_KEY)) return YES;
    for (NSString *d in MSBDDispStoreRemembered(all)) {
        id m = MSBDDispStoreInfo(all, d)[@"scales"];
        if ([m isKindOfClass:[NSNumber class]] && MSBDDispScaleRowWanted([m unsignedLongLongValue])) return YES;
    }
    return NO;
}
// "Has our Dock" (the Dock rows), one definition for the window and Settings' page: the Dock part's line on (in SpringBoard: the MacDock part loaded;
// in Settings: its line switch, LineSwitch.h MSBDLineEnabled) and its own switch not off (com.besiktasliseba.dockmagnification tweakEnabled: only a
// stored false is off, as Dock.x reads it).
static inline BOOL MSBDDispDockSwitchOn(id v) { return !(MSBDDispIsBool(v) && ![v boolValue]); }
static inline BOOL MSBDDispStoreOurDock(BOOL line) {
    if (!line) return NO;
    id v = CFBridgingRelease(CFPreferencesCopyValue(CFSTR("tweakEnabled"), CFSTR(MSBD_DISP_DOCK_DOMAIN), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    return MSBDDispDockSwitchOn(v);
}
// "connected" is true only while SpringBoard's status bar part keeps it (its registry, statusbar/DisplayPrefs.h, the one writer of it). Where that part
// does not run -- Mac Status Bar off, Use Stock Status Bar, Display Settings off at the start or switched off -- the list is let go once, so no display
// gone since stays "Connected" in Settings and every remembered one can be forgotten. One key of the displays domain; nothing else is touched.
// Returns YES when a list was there (and is gone now).
static inline BOOL MSBDDispStoreDropConnected(void) {
    CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN), key = CFSTR(MSBD_DISP_CONNECTED_KEY);
    CFPropertyListRef v = CFPreferencesCopyValue(key, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL there = v && (CFGetTypeID(v) != CFArrayGetTypeID() || CFArrayGetCount((CFArrayRef)v) > 0);
    if (v) CFRelease(v);
    if (!there) return NO;
    CFPreferencesSetValue(key, NULL, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post(MSBD_DISP_NOTIFY);
    return YES;
}
