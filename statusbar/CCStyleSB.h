// CCStyleSB.h -- Control Center Style in SpringBoard (1.8.0 item 3; common/CCStyle.h, CCStyleNow.h): the style chosen and the style in force
// (BigSurCenter while its classes are loaded, whatever is chosen), published for Settings (kMSBDCCStyleState: the Control Center group's note,
// "BigSurCenter stays loaded until you respring" / "loads after a respring"), and at the start whether the root helper has a switch to make --
// BigSurCenter loaded although another style is chosen, or chosen and installed but not loaded --: then the start's respring question waits for
// the helper's word and is asked only when the helper really changed what loads (DMCheckEngineWarnings, as for the engines). Our own Control Center
// (CCPanel.h) asks the same: DMCCStyleChosenNow, DMCCStyleInForceNow. Read at the start and at each change of our settings, never per opening.
// Included once by StatusBar.x, after the BigSurCenter helpers.
#pragma once
#include "../common/CCStyleNow.h"

static int gDMCCStyleChosen = kMSBDCCStyleNone;   // (the rule's style at the last look: the start, then each change of the stored style)
static int gDMCCStyleStored = -1;                 // (the stored style it was worked out from)
static uint64_t gDMCCStylePublished = 0;
// BigSurCenter's classes are loaded in this SpringBoard (its panel's controller, as the BigSurCenter helpers above find it).
static BOOL DMCCStyleBSCLoaded(void) { return objc_getClass("SCMainViewController") != Nil; }
// The style looked at again, and SpringBoard's word for Settings set (only when it changed).
static void DMCCStyleLook(NSString *why) {
    BOOL installed = NO; int verdict = 0;
    gDMCCStyleStored = MSBDCCStyleStoredFor(kCFPreferencesCurrentUser);
    int chosen = MSBDCCStyleNowFor(kCFPreferencesCurrentUser, NO, &installed, &verdict);
    BOOL loaded = DMCCStyleBSCLoaded();
    int inForce = MSBDCCStyleInForce(chosen, loaded);
    uint64_t state = MSBDCCStyleStateMake(inForce, loaded);
    BOOL changed = chosen != gDMCCStyleChosen || state != gDMCCStylePublished;
    gDMCCStyleChosen = chosen;
    if (state != gDMCCStylePublished) {
        static int token = 0;
        if (!token && notify_register_check(kMSBDCCStyleState, &token) != NOTIFY_STATUS_OK) token = 0;
        if (token && notify_set_state(token, state) == NOTIFY_STATUS_OK) gDMCCStylePublished = state;
    }
    if (changed) DMLog([NSString stringWithFormat:@"[ccstyle] %@: chosen %s, in force %s (stored %s; BigSurCenter installed %d, loaded %d; our Control Center's check %d)", why,
        MSBDCCStyleName(chosen), MSBDCCStyleName(inForce), MSBDCCStyleValue(gDMCCStyleStored) ?: "never set", installed, loaded, verdict]);
}
// The chosen style now: worked out again when the stored one changed since (one preference read), as our settings' notification may come to a
// caller before the look below.
static int DMCCStyleChosenNow(void) {
    if (!gDMCCStyleChosen || MSBDCCStyleStoredFor(kCFPreferencesCurrentUser) != gDMCCStyleStored) DMCCStyleLook(@"asked");
    return gDMCCStyleChosen;
}
__attribute__((unused)) static int DMCCStyleInForceNow(void) { return MSBDCCStyleInForce(DMCCStyleChosenNow(), DMCCStyleBSCLoaded()); }   // (our own Control Center, CCPanel.h)
// At the start: a switch for the root helper to make (BigSurCenter loaded though another style is chosen, or chosen and installed but not loaded).
static BOOL DMCCStyleSwitchDue(void) {
    if (MSBDCCStyleLoadsBigSurCenter(DMCCStyleChosenNow())) return !DMCCStyleBSCLoaded() && MSBDCCBigSurCenterInstalled(NO);
    return DMCCStyleBSCLoaded();
}
// The respring question's words for it, once the helper has made the switch (how: "Choicy" or "iCleaner Pro").
static NSString *DMCCStyleSwitchText(NSString *how) {
    int chosen = DMCCStyleChosenNow();
    if (MSBDCCStyleLoadsBigSurCenter(chosen)) return [NSString stringWithFormat:@"BigSurCenter is your Control Center Style, so it is now switched on in %@ and loads after a respring.", how];
    return [NSString stringWithFormat:@"Your Control Center Style is %s, so BigSurCenter is now switched off in %@ and stops loading after a respring.", MSBDCCStyleName(chosen), how];
}
// Our settings changed: looked at again when the stored style did (one preference read; a burst of changes -- a slider being dragged -- is one look,
// 0.3 s after its first). What else the rule reads changes only with a respring that makes it real.
static void DMCCStylePrefsChanged(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) {
    static BOOL pending = NO;
    if (pending) return;
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pending = NO;
        if (MSBDCCStyleStoredFor(kCFPreferencesCurrentUser) != gDMCCStyleStored) DMCCStyleLook(@"our settings changed");
    });
}
// %ctor, with either status bar style: followed from the start, and looked at again once SpringBoard is up (and by the tick, DMTickBody), so
// Settings never reads an earlier SpringBoard's word.
static void DMCCStyleInit(void) {
    DM_FEATURE_MARK("cc-style");
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DMCCStylePrefsChanged, CFSTR("com.besiktasliseba.macstatusbar/prefsChanged"), NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
    DMCCStyleLook(@"start");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMCCStyleLook(@"SpringBoard up"); });
}
