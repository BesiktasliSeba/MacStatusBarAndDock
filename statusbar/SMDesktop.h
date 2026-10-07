// SMDesktop.h -- the Stage Manager engine on the Home Screen, like our other engines (4 Oct 2026, branch sm-desktop). Included by StatusBar.x after
// DMSMHookConstrain16 (every DMSM helper it uses is defined above that point; the few StatusBar.x calls into it are declared before their use).
//  A. The Home Screen behind the windows. With a stage on screen Stage Manager's floor modifier -[SBFullScreenContinuousExposeSwitcherModifier]
//     answers (16.7.7, disassembled): isHomeScreenContentRequired NO, homeScreenAlpha 0, homeScreenDimmingAlpha (from the stage area),
//     homeScreenBackdropBlurType 3, switcherHitTestsAsOpaque YES. -[SBFluidSwitcherViewController _updateStyleWithCompletion:] applies them: the
//     switcher's Home Screen content reason ends, and once the to-app transaction's own reason has ended too SBUIController tears the Home Screen's
//     icon lists down (-tearDownIconListAndBar: our desktop icons and the widgets go with them) -- only the wallpaper the switcher requires is left;
//     the switcher's content view stops passing touches through (-_updateContentViewPassesTouchesThrough), so every touch outside the windows
//     is swallowed. The Home Screen's own floor (_SBHomeScreenFloorSwitcherModifier) answers alpha 1, dimming 0, blur type 1. Our engine, like
//     Aerial / Zetsu / MilkyWay4 (windows over the visible Home Screen): while it runs and the floor's stage is on the iPad's display without a
//     full-screen window, the floor answers as the Home Screen's does -- content required (the switcher's own reason, restored with its own
//     options: no teardown), alpha 1, no dimming, blur type 1, and touches outside the windows go through to the Home Screen and the Dock. A stage
//     with a full-screen window keeps Apple's answers (the Home Screen is covered: torn down as Apple does). Optional rows (kSMDeskRows): a row
//     missing or of another signature leaves the feature off (logged once) and the engine runs as before; nothing else depends on them.
//     With the Home Screen there, the rest is Aerial's: a touch outside the windows makes the windowed apps give up their typing; the App Library
//     and a Home Screen icon menu (both drawn in the Home Screen's window, under the windows) fade the windows away until they close.
//  B. One desktop for SpringBoard's own transitions (SMDeskJoin.h has the rule, Mac test tools/test-smdeskjoin.sh).
#pragma once
#include "SMDeskJoin.h"

// ---- A. the Home Screen behind the windows: the optional rows ------------------------------------------------------------------------------------
// One row per method the feature replaces: the signature our replacement is written for (a method of another signature is never replaced).
typedef struct { const char *cls; const char *sel; NSString *(*sig)(void); } DMSMDeskRow;
static const DMSMDeskRow kSMDeskRows[] = {
    {"SBFullScreenContinuousExposeSwitcherModifier", "isHomeScreenContentRequired", DMSMSigBool},
    {"SBFullScreenContinuousExposeSwitcherModifier", "homeScreenAlpha", DMSMSigDouble},
    {"SBFullScreenContinuousExposeSwitcherModifier", "homeScreenDimmingAlpha", DMSMSigDouble},
    {"SBFullScreenContinuousExposeSwitcherModifier", "homeScreenBackdropBlurType", DMSMSigTime},
    {"SBFullScreenContinuousExposeSwitcherModifier", "switcherHitTestsAsOpaque", DMSMSigBool},
};
static NSString *gSMDeskOff;   // (nil: the Home Screen shows behind the windows; else why not -- the log and the diagnostics say it)
static BOOL gSMDeskHooked = NO;
static Ivar gSMDeskStageIvar;  // (-[SBFullScreenContinuousExposeSwitcherModifier _fullScreenAppLayout]: the floor's stage, an object)
// The floor's stage shows the Home Screen behind its windows: our engine runs, the stage is on the iPad's own display, it has windows, none of
// them full screen. debug /tmp/msb-sm-nohome: Apple's answers (to compare).
static BOOL DMSMDeskHomeBehind(id floor) {
    static int depth = 0;   // (nothing below asks the switcher again; kept as a guard)
    if (depth || !gSMDeskHooked || gSMDeskOff || !DMSMFree() || !gSMDeskStageIvar) return NO;
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-nohome")) return NO;
#endif
    depth++;
    BOOL yes = NO;
    @try {
        id stage = object_getIvar(floor, gSMDeskStageIvar);
        NSDictionary *m = DMSMIsStage(stage) && DMSMIsMainIdentity(DMSMStageDisplayIdentity(stage)) ? DMSMStageItemsMap(stage) : nil;
        if (m.count) {
            yes = YES;
            for (id it in m) if (DMSMPolicyOf(m[it]) == 2) { yes = NO; break; }   // (a full-screen window covers the Home Screen)
        }
    } @catch (NSException *e) { yes = NO; }
    depth--;
    return yes;
}
static BOOL (*o_SMDeskContent)(id, SEL), (*o_SMDeskOpaque)(id, SEL);
static double (*o_SMDeskAlpha)(id, SEL), (*o_SMDeskDim)(id, SEL);
static long long (*o_SMDeskBlur)(id, SEL);
static BOOL gSMDeskLastLogged = NO, gSMDeskLastValid = NO;
static void DMSMDeskNote(BOOL behind) {   // (one log line per change, not per query)
    if (gSMDeskLastValid && gSMDeskLastLogged == behind) return;
    gSMDeskLastValid = YES; gSMDeskLastLogged = behind;
    if (behind) DM_FEATURE_MARK("sm-home-behind-windows");
    DMLog([NSString stringWithFormat:@"[smdesk] stage on screen: %@", behind ? @"the Home Screen shows behind its windows (content kept, touches outside the windows go to the Home Screen)" : @"Apple's own floor (no stage of windows on the iPad, or a full-screen window covers it)"]);
}
// The Home Screen's and the wallpaper's scale: the stage floor does not answer these itself, so its chain gave the in-app values (iPad 2: Home
// Screen 0.9, wallpaper 1.1 -- the Home Screen pushed back as behind a full-screen app, even with Reduce Motion): behind the windows it showed
// shrunk toward the middle, its top icon rows under the windows. With the Home Screen behind the windows: 1.0 / 1.0, as on the Home Screen
// itself; otherwise the chain's own answer (the floor's superclass: SpringBoard's query forwarding, as Apple's own modifiers call super). Given to
// the floor class as its own methods before it is first used (or, where it has them already, its own replaced).
static Class gSMDeskSuper;
static double (*o_SMDeskScale)(id, SEL), (*o_SMDeskWallScale)(id, SEL);
static double DMSMDeskChainDouble(id self, SEL _cmd, double (*orig)(id, SEL)) {
    if (orig) return orig(self, _cmd);
    struct objc_super s = { self, gSMDeskSuper };
    return ((double (*)(struct objc_super *, SEL))objc_msgSendSuper)(&s, _cmd);
}
static double DMSMDeskScale(id self, SEL _cmd) { return DMSMDeskHomeBehind(self) ? 1.0 : DMSMDeskChainDouble(self, _cmd, o_SMDeskScale); }
static double DMSMDeskWallScale(id self, SEL _cmd) { return DMSMDeskHomeBehind(self) ? 1.0 : DMSMDeskChainDouble(self, _cmd, o_SMDeskWallScale); }
static BOOL DMSMDeskContent(id self, SEL _cmd) { BOOL b = DMSMDeskHomeBehind(self); DMSMDeskNote(b); return b ? YES : o_SMDeskContent(self, _cmd); }
static double DMSMDeskAlpha(id self, SEL _cmd) { return DMSMDeskHomeBehind(self) ? 1.0 : o_SMDeskAlpha(self, _cmd); }
static double DMSMDeskDim(id self, SEL _cmd) { return DMSMDeskHomeBehind(self) ? 0.0 : o_SMDeskDim(self, _cmd); }
static long long DMSMDeskBlur(id self, SEL _cmd) { return DMSMDeskHomeBehind(self) ? 1 : o_SMDeskBlur(self, _cmd); }   // (1: the Home Screen's own)
static BOOL DMSMDeskOpaque(id self, SEL _cmd) { return DMSMDeskHomeBehind(self) ? NO : o_SMDeskOpaque(self, _cmd); }
// Checks the rows and the ivar, then replaces the five answers (all or none). Called once from the start-up self-check, after the engine's hooks.
static void DMSMDeskInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = objc_getClass("SBFullScreenContinuousExposeSwitcherModifier");
    NSMutableArray<NSString *> *bad = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(kSMDeskRows) / sizeof(kSMDeskRows[0]); i++) {
        Class rc = objc_getClass(kSMDeskRows[i].cls);
        Method m = rc ? class_getInstanceMethod(rc, sel_registerName(kSMDeskRows[i].sel)) : NULL;
        NSString *have = m ? DMSMSigOfMethod(m) : nil, *want = kSMDeskRows[i].sig();
        if (!m) [bad addObject:[NSString stringWithFormat:@"-[%s %s] missing", kSMDeskRows[i].cls, kSMDeskRows[i].sel]];
        else if (![have isEqualToString:want]) [bad addObject:[NSString stringWithFormat:@"-[%s %s] is %@, we use %@", kSMDeskRows[i].cls, kSMDeskRows[i].sel, have, want]];
    }
    Ivar iv = c ? class_getInstanceVariable(c, "_fullScreenAppLayout") : NULL;
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!t || t[0] != '@') [bad addObject:@"ivar SBFullScreenContinuousExposeSwitcherModifier._fullScreenAppLayout missing or not an object"];
    // (the two scale queries: their signature as the Home Screen's own floor implements them; the stage floor gets them as its own methods)
    for (NSString *q in @[@"homeScreenScale", @"wallpaperScale"]) {
        Method hm = class_getInstanceMethod(objc_getClass("_SBHomeScreenFloorSwitcherModifier"), NSSelectorFromString(q));
        if (!hm || ![DMSMSigOfMethod(hm) isEqualToString:DMSMSigDouble()]) [bad addObject:[NSString stringWithFormat:@"-[_SBHomeScreenFloorSwitcherModifier %@] missing or another signature", q]];
    }
    if (c && !class_getSuperclass(c)) [bad addObject:@"SBFullScreenContinuousExposeSwitcherModifier has no superclass"];
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-simulate-deskrow")) [bad addObject:@"-[SBFullScreenContinuousExposeSwitcherModifier homeScreenAlpha] missing (simulated, debug)"];
#endif
    if (bad.count) {
        gSMDeskOff = [NSString stringWithFormat:@"not on this iPadOS (%@)", [bad componentsJoinedByString:@"; "]];
        // (an optional feature: logged, not a refusal of the engine's -- the verdict's lists are for the rows the engine itself needs)
        DMLog([NSString stringWithFormat:@"[smdesk] the Home Screen stays hidden behind Stage Manager's windows here (Apple's way): %@", gSMDeskOff]);
        return;
    }
    gSMDeskStageIvar = iv;
    MSHookMessageEx(c, sel_registerName("isHomeScreenContentRequired"), (IMP)DMSMDeskContent, (IMP *)&o_SMDeskContent);
    MSHookMessageEx(c, sel_registerName("homeScreenAlpha"), (IMP)DMSMDeskAlpha, (IMP *)&o_SMDeskAlpha);
    MSHookMessageEx(c, sel_registerName("homeScreenDimmingAlpha"), (IMP)DMSMDeskDim, (IMP *)&o_SMDeskDim);
    MSHookMessageEx(c, sel_registerName("homeScreenBackdropBlurType"), (IMP)DMSMDeskBlur, (IMP *)&o_SMDeskBlur);
    MSHookMessageEx(c, sel_registerName("switcherHitTestsAsOpaque"), (IMP)DMSMDeskOpaque, (IMP *)&o_SMDeskOpaque);
    gSMDeskSuper = class_getSuperclass(c);
    BOOL scalesOK = YES;
    for (int i = 0; i < 2; i++) {
        SEL q = sel_registerName(i == 0 ? "homeScreenScale" : "wallpaperScale");
        IMP mine = i == 0 ? (IMP)DMSMDeskScale : (IMP)DMSMDeskWallScale;
        double (**orig)(id, SEL) = i == 0 ? &o_SMDeskScale : &o_SMDeskWallScale;
        BOOL own = NO;   // (the class's own method -- not one it inherits)
        unsigned int n = 0; Method *list = class_copyMethodList(c, &n);
        for (unsigned int k = 0; k < n; k++) if (method_getName(list[k]) == q) own = YES;
        free(list);
        if (own) MSHookMessageEx(c, q, mine, (IMP *)orig);
        else if (!class_addMethod(c, q, mine, "d16@0:8")) scalesOK = NO;
        Method now = class_getInstanceMethod(c, q);
        if (!now || method_getImplementation(now) != mine) scalesOK = NO;
    }
    if (!scalesOK) { gSMDeskOff = @"the scale answers could not be given to the stage floor"; DMLog(@"[smdesk] the Home Screen behind the windows is off: the stage floor's scale answers could not be set"); return; }
    // (all five replaced -- or none counts: a half-replaced floor would show the Home Screen without its touches, or the other way round; until
    //  gSMDeskHooked every replacement answers Apple's own)
    BOOL all = o_SMDeskContent && o_SMDeskAlpha && o_SMDeskDim && o_SMDeskBlur && o_SMDeskOpaque;
    IMP mine[] = {(IMP)DMSMDeskContent, (IMP)DMSMDeskAlpha, (IMP)DMSMDeskDim, (IMP)DMSMDeskBlur, (IMP)DMSMDeskOpaque};
    for (size_t i = 0; all && i < sizeof(kSMDeskRows) / sizeof(kSMDeskRows[0]); i++) {
        Method now = class_getInstanceMethod(c, sel_registerName(kSMDeskRows[i].sel));
        if (!now || method_getImplementation(now) != mine[i]) all = NO;
    }
    if (!all) { gSMDeskOff = @"the hooks did not all go in"; DMLog(@"[smdesk] the Home Screen behind the windows is off: not every answer could be replaced"); return; }
    gSMDeskHooked = YES;
    DMLog(@"[smdesk] the Home Screen shows behind Stage Manager's windows (7 floor answers: 5 replaced, 2 given; iPad's display only)");
}

static UIWindow *DMSMDeskSwitcherWindow(void);
// The engine switched on or off without a respring (Settings > Window Engine and back, Windowing off and on): the floor's answers above change at
// once, but SpringBoard asks for them again only at its next style update (-[SBFluidSwitcherViewController _updateStyleWithCompletion:], run with
// a window's activation). Switched away and back within a few seconds, the Home Screen stayed torn down behind the windows until a window was next
// brought forward (1.3.5 round 2 R3-L2). The watcher notices the change (DMSMDeskWatchEngine) and asks the iPad's switcher for that update once.
static void DMSMDeskRestyle(NSString *why) {
    @try {
        id coord = DMSMCoordinator();
        id scene = MSBDMainWindowScene();
        SEL forScene = NSSelectorFromString(@"switcherControllerForWindowScene:");
        id sc = scene && [coord respondsToSelector:forScene] && DMSMSigOK(coord, forScene, DMSMSigObjObj(), "switcherControllerForWindowScene:") ? ((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, scene) : nil;
        id content = DMCall(sc, @"contentViewController");
        SEL up = NSSelectorFromString(@"_updateStyleWithCompletion:");
        Class fluid = objc_getClass("SBFluidSwitcherViewController");
        if (!content || !fluid || ![content isKindOfClass:fluid] || ![content respondsToSelector:up] || !DMSMSigOK(content, up, DMSMSigVoidObj(), "_updateStyleWithCompletion:")) {
            DMLog([NSString stringWithFormat:@"[smdesk] %@: the switcher's style is left for its next update (its switcher was not found as expected)", why]);
            return;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(content, up, nil);
        DM_FEATURE_MARK("sm-desk-restyle");
        DMLog([NSString stringWithFormat:@"[smdesk] %@: the switcher's style updated now (the Home Screen %@ behind the windows)", why, DMSMFree() ? @"shown" : @"Apple's way"]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smdesk] updating the switcher's style failed: %@", e.reason]); }
}
static void DMSMDeskWatchEngine(void) {   // (every watcher tick: cheap -- one comparison unless the engine changed)
    static int last = -1;
    int now = DMSMFree() ? 1 : 0;
    if (now == last) return;
    BOOL first = last < 0;
    last = now;
    if (first || !gSMDeskHooked || gSMDeskOff) return;   // (at start the switcher asks for itself; without the feature nothing of ours changed)
    dispatch_async(dispatch_get_main_queue(), ^{ DMSMDeskRestyle(now ? @"the Stage Manager engine is back" : @"the Stage Manager engine stopped"); });
}
#if DEBUG
// debug trigger smfloor: what the iPad's switcher answers and does right now -- its root modifier's Home Screen answers (the ones the floor gives
// with a stage on screen), SBUIController's Home Screen content reasons and whether its icon lists are torn down, the content view's pass-through,
// the switcher window's alpha. Read-only; ivars read only where they exist with the expected type.
static id DMSMDeskIvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    return (t && t[0] == '@') ? object_getIvar(o, iv) : nil;
}
static void DMSMDeskDebugFloor(void) {
    @try {
        id coord = DMSMCoordinator();
        id scene = MSBDMainWindowScene();
        SEL forScene = NSSelectorFromString(@"switcherControllerForWindowScene:");
        id sc = scene && [coord respondsToSelector:forScene] ? ((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, scene) : DMCall(coord, @"_activeDisplaySwitcherController");
        id content = DMCall(sc, @"contentViewController");
        id root = [content respondsToSelector:NSSelectorFromString(@"rootModifier")] ? DMCall(content, @"rootModifier") : nil;
        NSMutableString *o = [NSMutableString stringWithFormat:@"[smfloor] switcher %@ root %@", NSStringFromClass([content class]), NSStringFromClass([root class])];
        if (root) {
            BOOL req = ((BOOL (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"isHomeScreenContentRequired"));
            double alpha = ((double (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"homeScreenAlpha"));
            double dim = ((double (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"homeScreenDimmingAlpha"));
            long long blur = ((long long (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"homeScreenBackdropBlurType"));
            BOOL opaque = ((BOOL (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"switcherHitTestsAsOpaque"));
            BOOL wall = ((BOOL (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"isWallpaperRequiredForSwitcher"));
            double hsScale = ((double (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"homeScreenScale"));
            double wpScale = ((double (*)(id, SEL))objc_msgSend)(root, NSSelectorFromString(@"wallpaperScale"));
            [o appendFormat:@"; answers: content required %d, alpha %.2f, scale %.3f, wallpaper scale %.3f, dimming %.2f, blur type %lld, hit-tests opaque %d, wallpaper required %d", req, alpha, hsScale, wpScale, dim, blur, opaque, wall];
        }
        id cv = DMSMDeskIvarObj(content, "_contentView");
        if ([cv respondsToSelector:NSSelectorFromString(@"passesTouchesThrough")]) [o appendFormat:@"; content view passes touches %d", ((BOOL (*)(id, SEL))objc_msgSend)(cv, NSSelectorFromString(@"passesTouchesThrough"))];
        id ui = DMCall(objc_getClass("SBUIController"), @"sharedInstance");
        id reasons = DMSMDeskIvarObj(ui, "_contentRequiringReasons");
        BOOL torn = [ui respondsToSelector:NSSelectorFromString(@"isIconListViewTornDown")] && ((BOOL (*)(id, SEL))objc_msgSend)(ui, NSSelectorFromString(@"isIconListViewTornDown"));
        [o appendFormat:@"; SBUIController content reasons %@ (icon lists torn down %d)", [reasons isKindOfClass:[NSSet class]] ? [[(NSSet *)reasons allObjects] componentsJoinedByString:@","] : @"?", torn];
        UIWindow *w = DMSMDeskSwitcherWindow();
        // (the front app as SpringBoard reports it: what Fit to Window's "a stage is shown" test reads -- 1.3.3's DMSMFitTick guard)
        [o appendFormat:@"; switcher window alpha %.2f hidden %d; front app %@; windows on screen %lu; feature %@", w.alpha, w.hidden, [DMFrontApp() bundleIdentifier] ?: @"none (Home Screen)",
            (unsigned long)DMSMWindowBundles().count, gSMDeskHooked && !gSMDeskOff ? @"on" : (gSMDeskOff ?: @"not installed")];
        DMLog(o);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smfloor] failed: %@", e.reason]); }
}
#endif
// ---- A. Aerial's behaviour on the Home Screen behind the windows ---------------------------------------------------------------------------------
// The switcher window on the iPad's screen (where the window cards are).
static UIWindow *DMSMDeskSwitcherWindow(void) {
    for (UIWindow *w in DMAllWindows()) if ((w.screen ?: [UIScreen mainScreen]) == [UIScreen mainScreen] && [NSStringFromClass([w class]) isEqualToString:@"SBMainSwitcherWindow"]) return w;
    return nil;
}
// A touch outside the windows (on the Home Screen or the Dock): the windowed apps give up their typing, as with Aerial (DMOutsideTouch) -- like
// clicking a Mac's desktop. The keyboard is the app's: it is told to resign through MacAppBridge (one notification per app, by bundle id hash).
static void DMSMDeskOutsideTouch(void) {
    NSArray<NSString *> *bundles = DMSMWindowBundles();
    if (!bundles.count) return;
    for (NSString *b in bundles) {
        uint32_t hash = 2166136261u;
        for (const char *c = b.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
        char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.resign.%08x", hash);
        notify_post(name);
    }
    DMLog([NSString stringWithFormat:@"[smdesk] a touch outside the windows: %lu windowed app(s) told to put their keyboard away (hardware keyboard %d)", (unsigned long)bundles.count, DMHardwareKeyboardAttached()]);
}
// The App Library or a Home Screen icon menu: both live in the Home Screen's window, under the windows -- the windows fade away while one shows
// and come back when it closes (Aerial's DMSyncWindowFade; folders open under the windows on every engine). Only the alpha of the switcher window
// is ours (SpringBoard shows and hides that window with -setHidden:, never its alpha); given back to exactly what it was. That window also draws
// the App Switcher: never faded while it shows, and given back the moment it appears (the switcher's appearance calls DMZetsuSwitcherCheck).
static BOOL gSMDeskFaded = NO;
static BOOL DMSMDeskIsFaded(void) { return gSMDeskFaded; }   // (StatusBar.x routes to DMSMDeskSyncFade while this is on, so a fade never outlives the engine)
static __weak UIWindow *gSMDeskFadedWindow;
static CGFloat gSMDeskAlphaWas = 1.0;
static void DMSMDeskSyncFade(void) {
    BOOL want = gSMDeskHooked && !gSMDeskOff && DMSMEngine() && (DMLibraryVisible() || gHomeMenuOpen) && !DMSwitcherVisible() && DMSMWindowBundles().count > 0;
    if (want == gSMDeskFaded) return;
    UIWindow *w = want ? DMSMDeskSwitcherWindow() : gSMDeskFadedWindow;
    gSMDeskFaded = want;
    if (!w) return;
    if (want) { gSMDeskFadedWindow = w; gSMDeskAlphaWas = w.alpha > 0.01 ? w.alpha : 1.0; }
    CGFloat to = want ? 0.0 : gSMDeskAlphaWas;
    BOOL forSwitcher = !want && DMSwitcherVisible();   // (the App Switcher needs its window now: at once, no fade)
    static BOOL fadedForMenu = NO;   // (for the log: a closing icon menu was called "App Library" -- the menu flag is already down by then)
    if (want) fadedForMenu = gHomeMenuOpen;
    DMLog([NSString stringWithFormat:@"[smdesk] %@ %@: windows %@", forSwitcher ? @"App Switcher" : ((want ? gHomeMenuOpen : fadedForMenu) ? @"Home Screen icon menu" : @"App Library"),
        want ? @"is showing" : (forSwitcher ? @"is coming" : @"is gone"), want ? @"fade away" : @"come back"]);
    if (forSwitcher) { [w.layer removeAnimationForKey:@"opacity"]; w.alpha = to; }   // (only our own fade's animation)
    else [UIView animateWithDuration:want ? 0.16 : 0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState
                          animations:^{ w.alpha = to; } completion:nil];
    if (!want) gSMDeskFadedWindow = nil;
}

// ---- B. one desktop for the transitions SpringBoard builds itself -----------------------------------------------------------------------------------
// (our own plans mark the context they are written into, and our requests carry an "MSBD..." label: DMSMCtxIsOurs, SMEngineAPI.h -- the join
//  in DMSMJoinDesktop leaves those alone before it gets here)
// Whether that window lives on another desktop than the one on screen: MacSwitcherSM.h's records answer it, per window (SMWindowKey.h: two windows
// of one app can be on two desktops) -- a window recorded on another desktop means SpringBoard's stage request IS that desktop's switch, which the
// Mac Switcher follows; it must not be folded into the desktop on screen. (One desktop, or the Mac Switcher off: never.)
static BOOL DMSMDeskOnOtherDesktop(NSString *key) { return DMMSWSMElsewhere(key); }   // (MacSwitcherSM.h: recorded on another desktop)
// A BOOL answer of a workspace entity (-isEmptyWorkspaceEntity, -isHomeScreenEntity...), typed and checked: never through DMCall, which takes the
// result for an object -- YES (0x1) was retained as one and crashed SpringBoard in its start-up transition to the Home Screen, whose roles hold
// empty entities (iPad 2, 4 Oct, 1.3.2-11+debug: EXC_BAD_ACCESS at 0x1 in objc_retain from DMCall, DMSMJoinStageAsked).
static BOOL DMSMEntityFlag(id e, NSString *name) {
    SEL s = NSSelectorFromString(name);
    return e && [e respondsToSelector:s] && DMSMSigOK(e, s, DMSMSigBool(), name.UTF8String) && ((BOOL (*)(id, SEL))objc_msgSend)(e, s);
}
static long long DMSMCtxLong(id ctx, NSString *name, long long dflt) {
    SEL s = NSSelectorFromString(name);
    if (![ctx respondsToSelector:s] || !DMSMSigOK(ctx, s, DMSMSigTime(), name.UTF8String)) return dflt;
    return ((long long (*)(id, SEL))objc_msgSend)(ctx, s);
}
// asked: @[role, entity] of every role the context has set (roles 1 up to the highest window role -- 1-9 on 16.7.7, SMRoles.h -- read by
// DMSMJoinDesktop). Stage Manager is about to show another stage than
// the desktop (DMSMDeskJoinPlan decides): instead the desktop's windows and the new ones, the new ones in front -- as a launch joins it. The plan
// is built and checked first; then SpringBoard's roles are unset (the context becomes a plain activation, whose unset roles Stage Manager keeps "as
// they were" -- emptying them instead drops a window the plan moves to another role, 1.4 finding) and the plan is written. A write that fails
// puts SpringBoard's own roles back.
__attribute__((noinline)) static void DMSMJoinStageAsked(id ctx, NSArray<NSArray *> *asked) {   // (noinline: its own range in the release crash map --
    // inlined into DMSMJoinDesktop after the 1.3.8 RC2 edits, test-crashstep's line for it had no symbol on the release build: logic test N-1)
#if DEBUG
    if (DMTestFlag("/tmp/msb-sm-nojoinasked")) { DMLog(@"[smjoin] roles already set: left as SpringBoard built it (debug /tmp/msb-sm-nojoinasked)"); return; }
#endif
    int flags = 0;
    id identity = DMCall(ctx, @"displayIdentity");
    if (!DMSMIsMainIdentity(identity)) flags |= DMSMJoinNotMain;
    long long env = DMSMCtxLong(ctx, @"requestedUnlockedEnvironmentMode", 0);
    if (env == 1) flags |= DMSMJoinToHome;
    if (env == 2) flags |= DMSMJoinToSwitcher;
    SEL rem = NSSelectorFromString(@"entitiesWithRemovalContexts");
    id removals = [ctx respondsToSelector:rem] && DMSMSigOK(ctx, rem, DMSMSigObj(), "entitiesWithRemovalContexts") ? ((id (*)(id, SEL))objc_msgSend)(ctx, rem) : nil;
    if ([removals isKindOfClass:[NSArray class]] && [removals count]) flags |= DMSMJoinRemoval;
    SEL expose = NSSelectorFromString(@"requestedAppExposeBundleID");
    if ([ctx respondsToSelector:expose] && DMSMSigOK(ctx, expose, DMSMSigObj(), "requestedAppExposeBundleID") && ((id (*)(id, SEL))objc_msgSend)(ctx, expose)) flags |= DMSMJoinNonApp;
    NSMutableArray<NSDictionary *> *askedW = [NSMutableArray array];
    NSMutableDictionary<NSString *, id> *askedEntity = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *seen = [NSMutableArray array];
    for (NSArray *a in asked) {
        long long r = [a[0] longLongValue]; id e = a[1];
        // (roles 3 and 4 -- the floating app and the centre window -- matter only with an app in them: the App Switcher's card sets 3 to "as it
        //  was" and 4 to empty on every pick, iPad 2 4 Oct: "1 com.apple.weather, 2 empty, 3 SBPreviousWorkspaceEntity, 4 empty, 5 empty, 6 empty")
        if (r == 3 || r == 4) {
            if (DMSMIsEntity(e)) { flags |= DMSMJoinFloatCentre; [seen addObject:[NSString stringWithFormat:@"%lld app", r]]; }
            else [seen addObject:[NSString stringWithFormat:@"%lld %@", r, DMSMEntityFlag(e, @"isEmptyWorkspaceEntity") ? @"empty" : NSStringFromClass([e class])]];
            continue;
        }
        if (DMSMIsEntity(e)) {
            NSString *b = DMCall(DMCall(e, @"application"), @"bundleIdentifier");
            if (![b isKindOfClass:[NSString class]] || !b.length) { flags |= DMSMJoinNonApp; continue; }
            NSString *k = DMSMEntityKey(e) ?: b;   // (the window: two windows of one app are two -- M-2)
            [askedW addObject:@{@"w": k, @"b": b, @"r": @(r)}];
            if (DMSMDeskOnOtherDesktop(k)) flags |= DMSMJoinOtherDesk;
            if (!askedEntity[k]) askedEntity[k] = e;
            if (!askedEntity[b]) askedEntity[b] = e;   // (by app, when the decision compares apps: the first of the app's)
            [seen addObject:[NSString stringWithFormat:@"%lld %@", r, DMSMKeyText(k)]];
        } else if (DMSMEntityFlag(e, @"isEmptyWorkspaceEntity")) {
            [seen addObject:[NSString stringWithFormat:@"%lld empty", r]];   // (a role emptied: part of showing that stage alone -- not a window)
        } else { flags |= DMSMJoinNonApp; [seen addObject:[NSString stringWithFormat:@"%lld %@", r, NSStringFromClass([e class])]]; }
    }
    // (cheap answers first, before the desktop's stages are read -- 16 transitions in 0.6 s for one resize gesture, 1.3.5 logic test L2: a switcher
    //  gesture still in progress, which SpringBoard follows with its end, and whatever the flags or the asked windows alone decide)
    id req0 = [ctx respondsToSelector:NSSelectorFromString(@"request")] && DMSMSigOK(ctx, NSSelectorFromString(@"request"), DMSMSigObj(), "request") ? DMCall(ctx, @"request") : nil;
    id label0 = [req0 respondsToSelector:NSSelectorFromString(@"eventLabel")] ? DMCall(req0, @"eventLabel") : nil;
    if ([label0 isKindOfClass:[NSString class]] && [label0 isEqualToString:@"UpdateFluidSwitcherGestureAction"]) return;
    NSString *early = nil;
    if (!DMSMDeskJoinPlan(@[], askedW, flags, &early) && ![early isEqualToString:@"no desktop to keep"]) {
        DMLog([NSString stringWithFormat:@"[smjoin] roles already set (%@; %@): left as SpringBoard built it -- %@", [seen componentsJoinedByString:@", "], [label0 isKindOfClass:[NSString class]] ? label0 : @"no label", early]);
        return;
    }
    // The desktop: with Mac Switcher desktops the CURRENT one's windows (MacSwitcherSM.h DMMSWSMAskedDeskWindows: recorded on it, or in the stage on
    // screen and recorded nowhere yet -- the most recent stage can be another desktop's), else the most recent stage on the iPad with a window that is
    // not minimized, not an app in full screen sent to the background unless that is what is asked for (as DMSMJoinDesktop has it: StatusBar.x
    // DMSMDesktopFor). Each window @[stage, item, attributes, its key] (SMWindowKey.h): after a Mac Switcher remove a desktop's windows are in two
    // stages until it is shown.
    NSMutableSet<NSString *> *askedK = [NSMutableSet set];   // (the windows asked for: their keys -- an app key where windows are told apart by app, M-2)
    for (NSDictionary *w in askedW) [askedK addObject:w[@"w"]];
    NSArray<NSArray *> *mswWins = DMMSWSMAskedDeskWindows();
    NSMutableArray<NSArray *> *wins = [NSMutableArray array];
    id desk = nil;   // (the stage of the desktop's newest window: its screen, and where new windows cascade from)
    if (mswWins) { [wins addObjectsFromArray:mswWins]; desk = mswWins.firstObject[0]; }
    else {
        NSMutableDictionary *map = nil;
        desk = DMSMDesktopFor(DMSMStageShownBefore(ctx), askedK, &map);
        for (id it in map) { NSString *k = DMSMItemKey(it); if (k) [wins addObject:@[desk, it, map[it], k]]; }
    }
    NSMutableArray<NSDictionary *> *deskW = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSArray *> *deskItem = [NSMutableDictionary dictionary];   // (window key -> its window; bundle -> the app's newest, by app)
    for (NSArray *w in wins) {
        NSString *b = DMSMItemBundle(w[1]), *k = w[3];
        long long r = 0, t = 0;
        if (!b.length || !k.length || !DMSMStageRoleOfItem(w[0], w[1], &r) || !DMSMAttrLastInteractionTime(w[2], &t)) return;   // (unreadable: SpringBoard's as built)
        [deskW addObject:@{@"w": k, @"b": b, @"r": @(r), @"t": @(t)}];
        if (![k isEqualToString:b]) deskItem[k] = w;   // (by app -- the key is the bundle -- only the app's newest, below)
        if (!deskItem[b] || t > DMSMAttrTimeOr(deskItem[b][2], 0)) deskItem[b] = w;
    }
    NSString *why = nil;
    NSArray<NSArray *> *decision = DMSMDeskJoinPlan(deskW, askedW, flags, &why);
    // (which of SpringBoard's paths built it, for the log: the request's event label and source -- "DismissSwitcherNoninteractive" is the App
    //  Switcher's card, "FinalFluidSwitcherGestureAction" a switcher gesture's end, read on 16.7.7)
    id req = [ctx respondsToSelector:NSSelectorFromString(@"request")] && DMSMSigOK(ctx, NSSelectorFromString(@"request"), DMSMSigObj(), "request") ? DMCall(ctx, @"request") : nil;
    id label = [req respondsToSelector:NSSelectorFromString(@"eventLabel")] ? DMCall(req, @"eventLabel") : nil;
    long long source = [req respondsToSelector:NSSelectorFromString(@"source")] ? DMSMCtxLong(req, @"source", -1) : -1;
    NSString *askedText = [NSString stringWithFormat:@"%@; %@ source %lld env %lld", [seen componentsJoinedByString:@", "], [label isKindOfClass:[NSString class]] ? label : @"no label", source, env];
    if (!decision) {
        DMLog([NSString stringWithFormat:@"[smjoin] roles already set (%@): left as SpringBoard built it -- %@", askedText, why]);
        if (mswWins && !deskW.count && [why isEqualToString:@"no desktop to keep"]) {   // (the current Mac Switcher desktop is empty: that stage is it now)
            NSMutableOrderedSet<NSString *> *bs = [NSMutableOrderedSet orderedSet];
            for (NSDictionary *a in askedW) [bs addObject:a[@"w"]];   // (each window by its key)
            DMMSWSMAskedOnEmpty(bs.array);
        }
        return;
    }
    // The plan in entities and attributes: the desktop's windows as they are, the new ones in front (newest interaction times) at their own last
    // place (DMSMJoinAttributes: their own window attributes, fitted to the desktop as it is now). The one in front -- with the keyboard focus --
    // is the app SpringBoard is activating, else the first new one; it gets the newest time (Stage Manager orders windows by it).
    BOOL windowed = DMWindowedLaunchOn();
    long long newest = 0; id frontAttrs = nil;
    for (NSArray *w in wins) { long long t = DMSMAttrTimeOr(w[2], 0); if (t >= newest) { newest = t; frontAttrs = w[2]; } }
    NSMutableArray<NSString *> *freshB = [NSMutableArray array];   // (the new windows: their keys -- the bundles when the decision compared apps)
    for (NSArray *d in decision) if ([d[2] boolValue]) [freshB addObject:d[0]];
    id act = [ctx respondsToSelector:NSSelectorFromString(@"activatingEntity")] ? DMCall(ctx, @"activatingEntity") : nil;
    NSString *actB = DMSMIsEntity(act) ? DMCall(DMCall(act, @"application"), @"bundleIdentifier") : nil, *actK = DMSMIsEntity(act) ? DMSMEntityKey(act) : nil;
    NSString *frontB = [actK isKindOfClass:[NSString class]] && [freshB containsObject:actK] ? actK : ([actB isKindOfClass:[NSString class]] && [freshB containsObject:actB] ? actB : freshB.firstObject);
    // (apps opening full screen -- Open Apps as Windows off: one full-screen app at a time, so two new ones at once stay Stage Manager's)
    if (!windowed && freshB.count > 1) { DMLog([NSString stringWithFormat:@"[smjoin] another stage asked for (%@): %lu new windows while apps open full screen -- left as SpringBoard built it", askedText, (unsigned long)freshB.count]); return; }
    // (a full desktop: the plan keeps its newest windows and leaves the oldest out -- with the Mac Switcher on, what it answers for a full desktop
    //  comes first: today the new windows open on a new desktop instead, MacSwitcherSM.h DMMSWSMAtCap)
    NSArray<NSString *> *leftOut = DMSMDeskJoinLeftOut(deskW, decision);
    if (leftOut.count && DMMSWSMAskedFull(ctx, asked, freshB, askedEntity, identity, frontB)) return;
    NSMutableArray<NSArray *> *plan = [NSMutableArray array];
    NSMutableArray<NSString *> *fresh = [NSMutableArray array];
    id frontEntity = nil; long k = 0;
    for (NSArray *d in decision) {
        NSString *b = d[0]; long long r = [d[1] longLongValue]; BOOL isNew = [d[2] boolValue];
        id e = nil, a = nil;
        if (isNew) {
            e = askedEntity[b] ?: DMSMNewEntity(DMSMKeyBundle(b), identity);
            BOOL front = [b isEqualToString:frontB];
            long t = front ? (long)(newest + (long long)freshB.count) : (long)(newest + k);   // (DMSMJoinAttributes puts it at t + 1)
            a = DMSMJoinAttributes(b, frontAttrs, windowed, t, desk);
            if (!front) k++;
            if (front) frontEntity = e;
            [fresh addObject:b];
        } else {
            e = DMSMEntityForStageItem(deskItem[b][0], deskItem[b][1]);   // (that window's own scene, in its own stage)
            a = deskItem[b][2];
        }
        if (!e || !a) { DMLog([NSString stringWithFormat:@"[smjoin] another stage asked for (%@): %@ could not be planned, left as SpringBoard built it", askedText, DMSMKeyText(b)]); return; }
        [plan addObject:@[e, @(r), a]];
    }
    NSArray<NSArray *> *toWrite = DMSMPlanFitted(identity, plan);
    NSString *bad = nil;
    if (!DMSMPlanValid(toWrite, DMSMNewWindowRoles(), &bad)) { DMSMAPIFail(@"joining the desktop (a stage SpringBoard asked for)", [NSString stringWithFormat:@"plan refused, left as SpringBoard built it (%@)", bad]); return; }
    // (SpringBoard's roles unset: the context is now a plain activation -- then ours written; on a failure SpringBoard's put back)
    SEL setE = NSSelectorFromString(@"setEntity:forLayoutRole:");
    if (!DMSMCtxCanWrite(ctx)) return;
    void (^putBack)(void) = ^{ for (NSArray *a in asked) @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, a[1], [a[0] longLongValue]); } @catch (id y) {} };
    @try { for (NSArray *a in asked) ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, nil, [a[0] longLongValue]); }
    @catch (NSException *x) { putBack(); DMSMAPIFail(@"joining the desktop: unsetting SpringBoard's roles", [NSString stringWithFormat:@"%@: its roles put back", x.reason ?: @"exception"]); return; }
    BOOL ok = DMSMWritePlan(ctx, toWrite, frontEntity);
    if (!ok) {
        putBack();
        DMLog([NSString stringWithFormat:@"[smjoin] another stage asked for (%@): writing the desktop failed, SpringBoard's roles put back", askedText]);
        return;
    }
    NSMutableArray<NSString *> *freshText = [NSMutableArray array];
    for (NSString *b in fresh) { DMSMSetMinimized(b, NO); [freshText addObject:DMSMKeyText(b)]; }   // (opened again: no longer a minimized window)
    if (!windowed && desk) for (NSString *b in fresh) DMSMDismissOtherFullScreen(desk, b);   // (full screen: one full-screen app at a time, as a launch)
    DMMSWSMAskedJoined(fresh, leftOut);   // (Mac Switcher: recorded on the current desktop; a full desktop's left-out windows minimized and said)
    DM_FEATURE_MARK("sm-join-asked-stage");
    for (NSString *b in fresh) {   // (a window of an app already on the desktop joined it: M-2's case)
        if (DMSMKeyIsApp(b)) continue;
        for (NSDictionary *w in deskW) if (![w[@"w"] isEqualToString:b] && [w[@"b"] isEqualToString:DMSMKeyBundle(b)]) { DM_FEATURE_MARK("sm-second-window-joins"); break; }
    }
    DMLog([NSString stringWithFormat:@"[smjoin] SpringBoard asked for another stage (%@): it joins the desktop instead -- %@ (%@ in front)", askedText, why, [freshText componentsJoinedByString:@", "]]);
}
