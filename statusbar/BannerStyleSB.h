// BannerStyleSB.h -- Banner Style in SpringBoard (1.8.0 item 2; common/BannerStyle.h, BannerStyleNow.h): the style chosen and the style in force
// (Destra while it is loaded and was switched on in its own settings when it loaded -- it applies its switch at its load, its page offers the
// respring --, whatever is chosen), published for Settings (kMSBDBannerStyleState: the Notifications group's note, "Destra stays loaded until you
// respring" / "loads after a respring"), and at the start whether the root helper has a switch to make -- Destra loaded although another style is
// chosen, or chosen and installed but not loaded --: then the start's respring question waits for the helper's word and is asked only when the
// helper really changed what loads (DMCheckEngineWarnings, as for the engines and BigSurCenter). Our banners (StatusBar.x's Mac-style notification
// banners) show only while Mac is in force (DMBannersOn), and their hooks go in only while Destra is not the style: with Destra chosen nothing of
// ours touches a banner (a pick of Mac or iPadOS puts them in then, at once).
// A pick that changes what should load while SpringBoard runs asks the root helper at once, so the next respring (Destra's own Respring button too)
// comes up with only the chosen banners and no second question.
// Looked at at the start and at each change of our settings, never per banner. Destra's own settings decide nothing here since a never-set style
// is ours whatever Destra's switch says (KT 3 Nov): the style in force counts its switch as it was when Destra loaded. Included once by
// StatusBar.x, after CCStyleSB.h.
#pragma once
#include "../common/BannerStyleNow.h"

static void DMBannersInit(void);   // (StatusBar.x's Mac-style notification banners: their hooks)
static BOOL DMBannersOn(void);     // (... and whether they show now: the debug trigger bannerstyle_state)
static int gDMBannerChosen = kMSBDBannerNone;            // (the rule's style at the last look: the start, then each change)
static int gDMBannerInForce = kMSBDBannerNone;           // (... and the one in force then: DMBannersOn)
static int gDMBannerDestraOnAtLoad = -1;                 // (Destra's own switch as it was when Destra loaded -- read at the first look that found it loaded)
static int gDMBannerStored = -1, gDMBannerLegacy = -1;   // (the stored style and the old Mac-Style Banners switch it was worked out from)
static uint64_t gDMBannerPublished = 0;
static BOOL gDMBannerHooksAllowed = NO;                  // (DMBannerStyleInit: our banners may be hooked in this SpringBoard -- debug: /tmp/msb-ctorskip "banners")
// Destra's library is loaded in this SpringBoard (a library never unloads: once seen, it stays so).
static BOOL DMBannerDestraLoaded(void) {
    static BOOL seen = NO;
    if (!seen) seen = MSBDTweakPresent("MacOSNotifications", YES);
    return seen;
}
// The style looked at again, SpringBoard's word for Settings set (only when it changed), and our banners hooked once Destra is not the style.
static void DMBannerStyleLook(NSString *why) {
    BOOL installed = NO, ownOn = NO;
    gDMBannerStored = MSBDBannerStyleStoredFor(kCFPreferencesCurrentUser);
    gDMBannerLegacy = MSBDBannerLegacyFor(kCFPreferencesCurrentUser);
    int chosen = MSBDBannerStyleNowFor(kCFPreferencesCurrentUser, NO, &installed, &ownOn);
    BOOL loaded = DMBannerDestraLoaded();
    if (loaded && gDMBannerDestraOnAtLoad < 0) gDMBannerDestraOnAtLoad = ownOn;
    int inForce = MSBDBannerInForce(chosen, loaded, loaded && gDMBannerDestraOnAtLoad == 1);
    uint64_t state = MSBDBannerStateMake(inForce, loaded);
    BOOL changed = chosen != gDMBannerChosen || state != gDMBannerPublished;
    if (gDMBannerChosen != kMSBDBannerNone && installed && MSBDBannerLoadsDestra(chosen) != MSBDBannerLoadsDestra(gDMBannerChosen))
        notify_post("com.besiktasliseba.msb.engines.apply");   // (Destra to load or not from the next start: the helper, now -- sshtoggled ApplyEngines)
    gDMBannerChosen = chosen; gDMBannerInForce = inForce;
    if (state != gDMBannerPublished) {
        static int token = 0;
        if (!token && notify_register_check(kMSBDBannerStyleState, &token) != NOTIFY_STATUS_OK) token = 0;
        if (token && notify_set_state(token, state) == NOTIFY_STATUS_OK) gDMBannerPublished = state;
    }
    if (gDMBannerHooksAllowed && !MSBDBannerLoadsDestra(chosen)) DMBannersInit();   // (once; Mac and iPadOS switch while running: DMBannersOn)
    if (changed) DMLog([NSString stringWithFormat:@"[bannerstyle] %@: chosen %s, in force %s (stored %s, old switch %s; Destra installed %d, its own switch %d, loaded %d)", why,
        MSBDBannerStyleName(chosen), MSBDBannerStyleName(inForce), MSBDBannerStyleValue(gDMBannerStored) ?: "never set",
        gDMBannerLegacy == kMSBDBannerNone ? "never set" : gDMBannerLegacy == kMSBDBannerMac ? "on" : "off", installed, ownOn, loaded]);
}
// The chosen style now, and the one in force (worked out at the start and at each change of our settings or Destra's: DMBannersOn asks for every
// banner).
static int DMBannerStyleChosenNow(void) {
    if (!gDMBannerChosen) DMBannerStyleLook(@"asked");
    return gDMBannerChosen;
}
static int DMBannerStyleInForceNow(void) {
    if (!gDMBannerChosen) DMBannerStyleLook(@"asked");
    return gDMBannerInForce;
}
// At the start: a switch for the root helper to make (Destra loaded though another style is chosen, or chosen and installed but not loaded).
static BOOL DMBannerStyleSwitchDue(void) {
    if (MSBDBannerLoadsDestra(DMBannerStyleChosenNow())) return !DMBannerDestraLoaded() && MSBDDestraInstalled(NO);
    return DMBannerDestraLoaded();
}
// The respring question's words for it, once the helper has made the switch (how: "Choicy" or "iCleaner Pro").
static NSString *DMBannerStyleSwitchText(NSString *how) {
    int chosen = DMBannerStyleChosenNow();
    if (MSBDBannerLoadsDestra(chosen)) return [NSString stringWithFormat:@"Destra is your Banner Style, so it is now switched on in %@ and loads after a respring.", how];
    return [NSString stringWithFormat:@"Your Banner Style is %s, so Destra is now switched off in %@ and stops loading after a respring.", MSBDBannerStyleName(chosen), how];
}
// Our settings changed: looked at again when the stored style or the old switch did (a burst of changes -- a slider being dragged -- is one look,
// 0.3 s after its first).
static void DMBannerStyleChanged(void) {
    static BOOL pending = NO;
    if (pending) return;
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pending = NO;
        if (MSBDBannerStyleStoredFor(kCFPreferencesCurrentUser) != gDMBannerStored || MSBDBannerLegacyFor(kCFPreferencesCurrentUser) != gDMBannerLegacy)
            DMBannerStyleLook(@"our settings changed");
    });
}
static void DMBannerStylePrefsChanged(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) { DMBannerStyleChanged(); }
// %ctor, with either status bar style (StockBar.h too): followed from the start, and looked at again once SpringBoard is up (and by the tick,
// DMTickBody), so Settings never reads an earlier SpringBoard's word. hooks: our banners may go in (not skipped by the debug bisect).
static void DMBannerStyleInit(BOOL hooks) {
    static BOOL done; if (done) return; done = YES;
    DM_FEATURE_MARK("banner-style");
    gDMBannerHooksAllowed = hooks;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, DMBannerStylePrefsChanged, CFSTR("com.besiktasliseba.macstatusbar/prefsChanged"), NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
    DMBannerStyleLook(@"start");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMBannerStyleLook(@"SpringBoard up"); });
}
