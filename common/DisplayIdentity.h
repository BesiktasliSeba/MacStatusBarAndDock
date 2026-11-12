// DisplayIdentity.h -- which display a UIScreen is, as a per-display settings key (MacStatusBar&Dock 1.8.7; plans/design-1.8.7-displays.md
// section 2). Header-only ObjC; every process derives the key itself (SpringBoard's status bar and Dock parts, Settings has no screens), so no
// process waits on another to have written a registry. The rule is plain C (DisplayPrefs.h MSBDDispKeyFrom, tools/test-displayprefs.c).
//
// The readings (S1, A12Z 18.5 + Samsung 4K TV over USB-C HDMI, 11 Nov): UIKit lists three UIScreens for the one TV (AirPlay[2-3], its shell UI
// screen, its noninteractive screen), and the display configuration (-[UIScreen displayConfiguration], FBSDisplayConfiguration) of each has the same
// hardwareIdentifier, equal to the CADisplay uniqueId and to SpringBoard's own SBSConnectedDisplayInfo identifier: the key comes from it directly.
// The iPad's configuration has no hardwareIdentifier (and its CADisplay no uniqueId): the iPad's screen has no key. For a configuration with no
// hardwareIdentifier the CADisplay with the same deviceName (else the only one with the same name) gives its uniqueId. Names say nothing about the
// route (FBS calls the wired TV "AirPlay[2-3]"); five idle "Wireless" CADisplays with no uniqueId are always listed.
// Every private call: the object answers it, takes no argument and returns an object (or a BOOL), in @try.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "DisplayPrefs.h"

// A no-argument getter that returns an object, only when the object has it in that shape (nil otherwise).
static inline id MSBDDispGet(id o, const char *name) {
    if (!o || !name) return nil;
    SEL s = sel_registerName(name);
    @try {
        if (![o respondsToSelector:s]) return nil;
        Method m = object_isClass(o) ? class_getClassMethod((Class)o, s) : class_getInstanceMethod(object_getClass(o), s);
        const char *t = m ? method_getTypeEncoding(m) : NULL;
        if (!m || method_getNumberOfArguments(m) != 2 || !t || t[0] != '@') return nil;
        return ((id (*)(id, SEL))objc_msgSend)(o, s);
    } @catch (NSException *e) { return nil; }
}
// A no-argument BOOL getter: 1 / 0, or -1 when the object has no such getter.
static inline int MSBDDispGetBool(id o, const char *name) {
    if (!o || !name) return -1;
    SEL s = sel_registerName(name);
    @try {
        if (![o respondsToSelector:s]) return -1;
        Method m = class_getInstanceMethod(object_getClass(o), s);
        const char *t = m ? method_getTypeEncoding(m) : NULL;
        if (!m || method_getNumberOfArguments(m) != 2 || !t || (t[0] != 'B' && t[0] != 'c')) return -1;
        return ((BOOL (*)(id, SEL))objc_msgSend)(o, s) ? 1 : 0;
    } @catch (NSException *e) { return -1; }
}
// A real string (a non-string, nil or empty is none: the rule then reads it as no id).
static inline NSString *MSBDDispStr(id v) { return [v isKindOfClass:[NSString class]] && [(NSString *)v length] ? (NSString *)v : nil; }
static inline NSArray *MSBDDispCADisplays(void) {
    id all = MSBDDispGet(objc_getClass("CADisplay"), "displays");
    return [all isKindOfClass:[NSArray class]] ? all : @[];
}
static inline id MSBDDispConfigOfScreen(UIScreen *s) { return s ? MSBDDispGet(s, "displayConfiguration") : nil; }
// The CADisplay a display configuration stands for: the one whose uniqueId is its hardwareIdentifier, else the one with its deviceName, else the
// only one with its name (two with that name: none, never a guess).
static inline id MSBDDispCADisplayOfConfig(id cfg) {
    if (!cfg) return nil;
    NSString *hw = MSBDDispStr(MSBDDispGet(cfg, "hardwareIdentifier")), *dn = MSBDDispStr(MSBDDispGet(cfg, "deviceName")), *nm = MSBDDispStr(MSBDDispGet(cfg, "name"));
    NSArray *all = MSBDDispCADisplays();
    if (hw) for (id d in all) { NSString *u = MSBDDispStr(MSBDDispGet(d, "uniqueId")); if (u && [u caseInsensitiveCompare:hw] == NSOrderedSame) return d; }
    if (dn) for (id d in all) if ([MSBDDispStr(MSBDDispGet(d, "deviceName")) isEqualToString:dn]) return d;
    id byName = nil; int n = 0;
    if (nm) for (id d in all) if ([MSBDDispStr(MSBDDispGet(d, "name")) isEqualToString:nm]) { byName = d; n++; }
    return n == 1 ? byName : nil;
}
// Is this screen the iPad's own: the main screen, or a configuration that says it is not external (or names the iPad's panel, "primary").
static inline BOOL MSBDDispScreenIsMain(UIScreen *s, id cfg) {
    if (!s || s == [UIScreen mainScreen]) return YES;
    int ext = MSBDDispGetBool(cfg, "isExternal");
    if (ext == 0) return YES;
    return ext < 0 && [MSBDDispStr(MSBDDispGet(cfg, "deviceName")) isEqualToString:@"primary"];
}
// The key of a screen: nil for the iPad's own (and for nil), "u-<id>" or "any".
static inline NSString *MSBDDispKeyOfScreen(UIScreen *s) {
    if (!s || s == [UIScreen mainScreen]) return nil;
    id cfg = MSBDDispConfigOfScreen(s);
    if (MSBDDispScreenIsMain(s, cfg)) return nil;
    NSString *hw = MSBDDispStr(MSBDDispGet(cfg, "hardwareIdentifier"));
    NSString *u = MSBDDispIdUsable(hw.UTF8String) ? nil : MSBDDispStr(MSBDDispGet(MSBDDispCADisplayOfConfig(cfg), "uniqueId"));   // (only for a nil or unusable one)
    char key[96];
    int kind = MSBDDispKeyFrom(0, hw.UTF8String, u.UTF8String, key, sizeof key);
    return kind == kMSBDDispKeyMain ? nil : [NSString stringWithUTF8String:key];
}
