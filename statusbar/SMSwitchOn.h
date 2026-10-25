// SMSwitchOn.h -- when the Stage Manager engine switches Stage Manager on, and which way (24 Oct 2026). Included by StatusBar.x before
// DMStageManagerWatch. Plain Foundation (no SpringBoard calls): Mac test tools/test-smswitchon.sh.
// Found on the A12Z (iPad8,11, iPadOS 18.5, native Stage Manager, TrollPad 1.3 installed): after a respring onto the Lock Screen, Apple's Stage
// Manager introduction ("Turn on Stage Manager / Not Now") came up OVER the Lock Screen and blocked its swipe up. Two causes:
//  1. the first switch-on ran 12 s after SpringBoard's start whatever the screen showed, the Lock Screen included;
//  2. TrollPad (its SpringBoard part, loaded on every iPad it is installed on, Stage Manager models too) maps every SBChamois* key SpringBoard
//     reads or writes through NSUserDefaults to a TPSBChamois* copy. That iPad had Stage Manager on before TrollPad came (Apple's
//     SBChamoisWindowingEnabled and SBChamoisWindowingEverEnabled 1), but SpringBoard read TrollPad's empty copies: "never on", so our engine
//     took Apple's first-time path and its introduction.
// 1.5.1: and only after the user said yes (see Consent, below).
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

// ---- Consent (1.5.1, Havoc repository rule 2.5): Apple's Stage Manager setting is the user's ---------------------------------------------------
// The engine switches Stage Manager on only after a yes: our one-time question ("MacStatusBar&Dock would like to turn on Stage Manager to show apps as
// Mac windows. You can change this later in Window Engine." Turn On / Not Now), or Turn On Stage Manager in Settings > Status Bar. Apple's introduction,
// when it follows the yes on an iPad where Stage Manager was never on, asks again: declining it is a no too. A no is never undone by us -- nothing is
// written, and Settings shows that Stage Manager is off and how to turn it on. Once on, Stage Manager is the user's: switched off by them, it stays
// off (until 1.5.0 the engine switched it back on, and wrote it 45 s after a declined introduction). An iPad where it is on already when the engine
// starts is never asked (existing users). Stored as smConsentOn (absent: unasked); the same values for smHoldConsent (DMSMHoldStepFor, below).
typedef NS_ENUM(int, DMSMConsent) {
    DMSMConsentUnasked = 0,   // no answer stored
    DMSMConsentYes = 1,       // yes, not switched on yet: switched on once
    DMSMConsentDone = 2,      // on (by us after a yes, or it already was): the user's from now on
    DMSMConsentNo = 3,        // Not Now, Apple's introduction declined, or switched off by the user
};
static inline int DMSMConsentFrom(id stored) {   // a stored value (a number, or a string a Settings writer left) -> DMSMConsent; anything else: unasked
    if (!([stored isKindOfClass:[NSNumber class]] || [stored isKindOfClass:[NSString class]])) return DMSMConsentUnasked;
    int v = [stored intValue];
    return v >= DMSMConsentYes && v <= DMSMConsentNo ? v : DMSMConsentUnasked;
}

typedef NS_ENUM(int, DMSMOnStep) {
    DMSMOnNothing = 0,     // Stage Manager is on: nothing to do (the consent becomes "done": the user's from now on)
    DMSMOnWait = 1,        // not yet: SpringBoard still starting, the Lock Screen or the Cover Sheet up, or Apple's introduction may be up
    DMSMOnFirstTime = 2,   // Apple's first-time path: its "ever enabled" mark, then its introduction, whose Continue switches it on (after our yes)
    DMSMOnWrite = 3,       // the setting written directly (after our yes, where Stage Manager was on before)
    DMSMOnAsk = 4,         // our one-time question (nothing asked yet)
    DMSMOnDeclined = 5,    // Apple's introduction followed the yes and Stage Manager is still off 45 s later: declined -- a no, nothing written
    DMSMOnUserOff = 6,     // it was on and is off now: switched off by the user -- recorded as a no, nothing written
    DMSMOnLeftOff = 7,     // a no: nothing written; Settings shows that Stage Manager is off and how to turn it on
    DMSMOnGiveBack = 8,    // the user's own "on", held off while another engine ran (stageManagerUserOn): given back -- switched on, the key cleared,
                           // the consent done; never a question, never a no (logic test B2)
};
// on: Stage Manager is on now (SpringBoard's own reading -- with TrollPad loaded, its copy of the key, which is the one SpringBoard acts on).
// consent: DMSMConsent. age: seconds since SpringBoard started. unlocked: the screen is on and unlocked, with no Cover Sheet (Lock Screen /
// Notification Center). everSB: SpringBoard's own "was Stage Manager ever on" (1 / 0; -1 when it can't be asked or set). everKey: DMSMEverKeyIn of the
// stored keys (nil: none says so). askedAgo: seconds since Apple's first-time path was taken in this SpringBoard (negative: not taken).
// intro: Apple's introduction since then -- 0 never seen on screen, 1 seen and gone, 2 on screen now; -1 it cannot be seen on this iPadOS (the
// pieces the check uses are missing: the rule before the check, still off 45 s later = declined -- 1.5.1 re-check N3). userOnSaved: the user's own "on" is kept (stageManagerUserOn: we held it off while
// another engine ran).
// Who switched it off decides what the consent says: wherever WE switch it off (windowing off, the tweak off or removed, another engine, a start whose
// self-check fails), a done consent goes back to yes (StatusBar.x, sshtoggled), so the next engine period switches it on again with no question;
// only the user's own switch-off leaves "done" with Stage Manager off, which is read as their no (logic test B2).
static inline DMSMOnStep DMSMSwitchOnStep(BOOL on, int consent, double age, BOOL unlocked, int everSB, NSString *everKey, double askedAgo, int intro, BOOL userOnSaved) {
    if (on) return DMSMOnNothing;
    if (age < 12.0 || !unlocked) return consent == DMSMConsentNo && !userOnSaved ? DMSMOnLeftOff : DMSMOnWait;   // (never in SpringBoard's first seconds,
                                                      //  never on the Lock Screen: neither the question nor a switch; nor reading "off" as the user's
                                                      //  switch-off before SpringBoard's own reading has settled)
    if (userOnSaved) return DMSMOnGiveBack;           // (the user's own earlier "on": theirs, given back -- before any question or no)
    if (consent == DMSMConsentNo) return DMSMOnLeftOff;
    if (consent == DMSMConsentDone) return DMSMOnUserOff;
    if (consent != DMSMConsentYes) return DMSMOnAsk;
    if (askedAgo >= 0.0) {   // (Apple's first-time path was taken: its introduction may be up)
        if (askedAgo < 45.0 || intro == 2) return DMSMOnWait;   // (and while it is on screen: the user is still reading it)
        return intro == 0 ? DMSMOnWrite : DMSMOnDeclined;   // (never seen -- SpringBoard showed no introduction -- the user's yes to our question
                                                           //  stands: written, logic test W1. Seen and closed with Stage Manager still off, or not
                                                           //  seeable here: declined, never a blind write -- N3)
    }
    if (everSB == 0 && !everKey.length) return DMSMOnFirstTime;
    return DMSMOnWrite;
}

// ---- Keeping Stage Manager off while another engine runs (1.5.1): the same consent, once ----------------------------------------------------------
// Two window systems fight over the same apps, so Stage Manager is kept off while Aerial, Zetsu or MilkyWay4 runs (and comes back on as the user had
// it when windowing goes off). Picking that engine in Settings is the yes: its confirmation says so (picked: the stored Window Engine pick is an engine
// other than Stage Manager -- also every pick made before 1.5.1, documented then). An engine nobody picked (the default one, e.g. on iPadOS 18) asks once
// ("Turn Off" / "Not Now"). A no leaves Stage Manager as the user has it.
typedef NS_ENUM(int, DMSMHoldStep) {
    DMSMHoldNothing = 0,   // Stage Manager off, or no window engine of ours running: nothing to keep
    DMSMHoldOff = 1,       // switched off (the user's wish remembered: back on when windowing goes off)
    DMSMHoldAsk = 2,       // our one-time question
    DMSMHoldLeave = 3,     // a no: left on
    DMSMHoldWait = 4,      // not yet (SpringBoard starting, locked): asked later
};
static inline DMSMHoldStep DMSMHoldStepFor(BOOL engineRuns, BOOL on, int holdConsent, BOOL picked, double age, BOOL unlocked) {
    if (!engineRuns || !on) return DMSMHoldNothing;
    if (holdConsent == DMSMConsentNo) return DMSMHoldLeave;
    if (holdConsent == DMSMConsentYes || holdConsent == DMSMConsentDone || picked) return DMSMHoldOff;
    if (age < 12.0 || !unlocked) return DMSMHoldWait;
    return DMSMHoldAsk;
}
