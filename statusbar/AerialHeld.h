// AerialHeld.h -- Aerial 5's own settings while it is our engine (StatusBar.x DMAerial5SwallowPrefs): the values held, and which values in
// Aerial's preferences are the user's own. Plain Foundation: StatusBar.x passes what it read on the iPad; the Mac test (tools/test-aerialheld.sh)
// passes made-up preferences.
//  - Held: Aerial's own default for each setting, except what our integration needs otherwise: its window menu's Minimize off and its bottom
//    handle in Resize Mode (both lead to Aerial's round chip otherwise), "Use New Rotation Method" on for iOS 16 / off for iOS 15 (the other value
//    draws the windows sideways), and its four rows in an app icon's Haptic Touch menu off: "Enable/Disable Flex Resize" and "Enable/Disable
//    Keyboard Avoidance" change per-app state that is neutralised anyway; "Open in Aerial" and "Remove Stage State" do nothing while we wrap Aerial,
//    since our windowing opens and places the windows (1.8.1 item 4, KT). Off in Aerial's own settings, Aerial adds none of them to any menu: the
//    Mac look and iPadOS's own. They come back with the user's own settings, when Aerial stops being our engine (windowing off, another engine,
//    Mac Status Bar switched off or removed).
//  - The user's own: a value in Aerial's preferences that is not the one held was set in Aerial's own Settings page since the user's copy was
//    made, so it goes into the copy (and the held one back into Aerial's preferences). A value an earlier build held there is ours, not the
//    user's, until this build has brought the copy up to date once: 1.8.0 and earlier held Open in Aerial and Remove Stage State on (Aerial's
//    default), so on the first pass after an update their "on" is not the user's (a user who had them off keeps off in the copy).
//  - Down to an earlier build and back up (code review 1.8.1, 6): an earlier build sees our "off" for those two rows in Aerial's preferences and records it as the user's, then holds them
//    on; back here that "on" was recorded as the user's, as the mark was still there, so a user who had them off got them on. The down leg cannot be fixed in builds already out. The
//    mark keeps this build's copy of those keys, which no earlier build touches: both rows on in Aerial's preferences at once mean an earlier build ran (from Aerial's own Settings page one
//    changes at a time, and a pass 0.3 s later holds it off again): not the user's, and the copy gets back what the mark kept, for those who had them on and those who had them off.
#pragma once
#import <Foundation/Foundation.h>

// (ios16: iPadOS 16 or later; sideHalves: this Aerial build has 5.1's left and right halves in its Split Stage menu)
static NSDictionary<NSString *, id> *MSBDA5HeldPrefs(BOOL ios16, BOOL sideHalves) {
    NSMutableDictionary *w = [@{ @"useNewDesign": @YES, @"useNewRotationMethod": @(ios16), @"ccToggleAutoStage": @YES,
              @"minusHandleDefaultSwipeMode": @1, @"switcherGestureType": @0,
              @"contextMenu_showOpenApp": @YES, @"contextMenu_showMaximize": @YES, @"contextMenu_showMinimize": @NO, @"contextMenu_showSplitStage": @YES,
              @"contextMenu_showTrimMode": @YES, @"contextMenu_showLockStage": @YES, @"contextMenu_showClose": @YES,
              @"splitMenu_showUpperHalf": @YES, @"splitMenu_showLowerHalf": @YES, @"splitMenu_showUpperThird": @YES, @"splitMenu_showMiddleThird": @YES, @"splitMenu_showLowerThird": @YES,
              @"shortcut_openInAerial": @NO, @"shortcut_flexResize": @NO, @"shortcut_keyboardAvoidance": @NO, @"shortcut_removeState": @NO } mutableCopy];
    if (sideHalves) { w[@"splitMenu_showLeftHalf"] = @YES; w[@"splitMenu_showRightHalf"] = @YES; }
    return w;
}
// The values earlier builds held for the keys held differently now (see above).
static NSDictionary<NSString *, id> *MSBDA5EarlierHeld(void) { return @{ @"shortcut_openInAerial": @YES, @"shortcut_removeState": @YES }; }
// The name of the mark kept in the user's copy's folder once this build has brought the copy up to date (from then on an "on" there is the user's): a property list of the copy's values
// of the keys earlier builds held differently (MSBDA5MarkValues). A beta's mark is an empty file: nothing to give back then.
#define MSBD_A5_COPY_MARK @"HeldShortcutsOff"

static NSDictionary *MSBDA5MarkValues(NSDictionary *user) {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSString *k in MSBDA5EarlierHeld()) if (user[k]) m[k] = user[k];
    return m;
}
// Aerial's preferences now (`cur`) hold what only an earlier build holds: every one of those keys at its earlier value, at once.
static BOOL MSBDA5EarlierBuildRan(NSDictionary *cur) {
    NSDictionary *earlier = MSBDA5EarlierHeld();
    for (NSString *k in earlier) if (![cur[k] isEqual:earlier[k]]) return NO;
    return YES;
}
// Back from an earlier build: the copy's values of those keys as the mark kept them (a key the mark does not have was not in the copy: Aerial's default). No mark's values (nil): left as they are.
static void MSBDA5UserBackFromMark(NSMutableDictionary *user, NSDictionary *mark) {
    if (![mark isKindOfClass:[NSDictionary class]]) return;
    for (NSString *k in MSBDA5EarlierHeld()) { if (mark[k]) user[k] = mark[k]; else [user removeObjectForKey:k]; }
}
// Per-app state Aerial mirrors into its preferences (its Settings switches; Aerial itself ignores them): never the user's to keep.
static BOOL MSBDA5IsPerAppKey(NSString *k) { return [k hasPrefix:@"flexResizeDisabled_"] || [k hasPrefix:@"keyboardAvoidanceEnabled_"]; }

// The user's copy brought up to date with Aerial's preferences now (`cur`): returns the keys recorded as the user's new values. olderCopy: the copy
// was last brought up to date by an earlier build (no mark yet), so a value it held is still ours. Aerial's own other keys that are gone from its
// preferences are dropped from the copy too (mirrored).
static NSArray<NSString *> *MSBDA5RecordUser(NSMutableDictionary *user, NSDictionary *cur, NSDictionary *wanted, BOOL olderCopy) {
    NSMutableArray *recorded = [NSMutableArray array];
    NSDictionary *earlier = olderCopy ? MSBDA5EarlierHeld() : @{};
    for (NSString *k in cur) {
        id v = cur[k], w = wanted[k];
        if (w && [v isEqual:w]) continue;   // still ours
        if (w && earlier[k] && [v isEqual:earlier[k]]) continue;   // held there by an earlier build: ours too
        if (![user[k] isEqual:v]) { user[k] = v; [recorded addObject:k]; }   // changed in Aerial's own Settings since: that is the user's value now
    }
    for (NSString *k in [user allKeys]) if (!wanted[k] && !MSBDA5IsPerAppKey(k) && !cur[k]) [user removeObjectForKey:k];   // Aerial's own other keys: mirrored
    return recorded;
}
