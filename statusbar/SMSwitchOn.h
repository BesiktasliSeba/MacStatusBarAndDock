// SMSwitchOn.h -- when the Stage Manager engine switches Stage Manager on, and which way (24 Oct 2026). Included by StatusBar.x before
// DMStageManagerWatch. Plain Foundation (no SpringBoard calls): Mac test tools/test-smswitchon.sh.
// Found on the A12Z (iPad8,11, iPadOS 18.5, native Stage Manager, TrollPad 1.3 installed): after a respring onto the Lock Screen, Apple's Stage
// Manager introduction ("Turn on Stage Manager / Not Now") came up OVER the Lock Screen and blocked its swipe up. Two causes:
//  1. the first switch-on ran 12 s after SpringBoard's start whatever the screen showed, the Lock Screen included;
//  2. TrollPad (its SpringBoard part, loaded on every iPad it is installed on, Stage Manager models too) maps every SBChamois* key SpringBoard
//     reads or writes through NSUserDefaults to a TPSBChamois* copy. That iPad had Stage Manager on before TrollPad came (Apple's
//     SBChamoisWindowingEnabled and SBChamoisWindowingEverEnabled 1), but SpringBoard read TrollPad's empty copies: "never on", so our engine
//     took Apple's first-time path and its introduction.
// Now Stage Manager is switched on for the engine only on an unlocked screen with no Cover Sheet, and Apple's first-time path is taken only when
// no key says Stage Manager was ever on: neither SpringBoard's own reading nor the stored keys themselves, Apple's and TrollPad's (read directly
// with CFPreferences, which TrollPad does not map).
#pragma once
#import <Foundation/Foundation.h>

// The stored keys that say Stage Manager was on (or ever on) on this iPad, in the order they are looked at.
static inline NSArray<NSString *> *DMSMEverKeys(void) {
    return @[@"SBChamoisWindowingEverEnabled", @"SBChamoisWindowingEnabled", @"TPSBChamoisWindowingEverEnabled", @"TPSBChamoisWindowingEnabled"];
}
// The first of those keys that is set to yes in com.apple.springboard's stored values (a key -> value dictionary), nil when none is.
static inline NSString *DMSMEverKeyIn(NSDictionary *stored) {
    if (![stored isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *k in DMSMEverKeys()) {
        id v = stored[k];
        if (([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]]) && [v boolValue]) return k;
    }
    return nil;
}

typedef NS_ENUM(int, DMSMOnStep) {
    DMSMOnNothing = 0,     // Stage Manager is on: nothing to do
    DMSMOnWait = 1,        // not yet: SpringBoard still starting, the Lock Screen or the Cover Sheet up, or Apple's introduction may be up
    DMSMOnFirstTime = 2,   // Apple's first-time path: its "ever enabled" mark, then its introduction, whose Continue switches it on
    DMSMOnWrite = 3,       // the setting written directly
};
// on: Stage Manager is on now (SpringBoard's own reading -- with TrollPad loaded, its copy of the key, which is the one SpringBoard acts on).
// age: seconds since SpringBoard started. unlocked: the screen is on and unlocked, with no Cover Sheet (Lock Screen / Notification Center).
// everSB: SpringBoard's own "was Stage Manager ever on" (1 / 0; -1 when it can't be asked or set). everKey: DMSMEverKeyIn of the stored keys
// (nil: none says so). askedAgo: seconds since the first-time path was taken in this SpringBoard (negative: not taken).
static inline DMSMOnStep DMSMSwitchOnStep(BOOL on, double age, BOOL unlocked, int everSB, NSString *everKey, double askedAgo) {
    if (on) return DMSMOnNothing;
    if (age < 12.0 || !unlocked) return DMSMOnWait;   // (never in SpringBoard's first seconds, never on the Lock Screen)
    if (askedAgo >= 0.0) return askedAgo < 45.0 ? DMSMOnWait : DMSMOnWrite;   // (Apple's introduction may be up; declined or gone: written)
    if (everSB == 0 && !everKey.length) return DMSMOnFirstTime;
    return DMSMOnWrite;
}
