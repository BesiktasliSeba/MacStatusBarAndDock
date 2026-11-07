// WindowAPI.h -- the window API, V1 (1.8.3 item 1): KeyPilot's bridge in this tweak, with the names, arguments and return codes its author gave it
// (wanghuangjie, KeyPilot integrations/MSBDKeyPilotBridge.inc, 4b2b247; the rules and codes: WindowAPIRule.h). Exported from MacStatusBarCore.dylib
// with default visibility (KeyPilot finds them with dlopen(RTLD_NOLOAD) / dlsym; the Makefile checks they are exported); called in SpringBoard on the
// main thread. Included at the end of StatusBar.x, where the engine's helpers are: the window goes where the Window menu puts it, by the same calls.
// What his bridge checked, against the code today: the layouts are the Window menu's (DMWindowLayout: the desktop beside a side Dock, the layouts
// kept as the Dock or the screen turns, Stage Manager's per-window layout); our own window in front (Finder) is laid out as the Window menu does it;
// Home is the user's Home with Home Minimizes Windows (every window minimized, each back with its own app, on every engine -- his bridge sent Stage
// Manager's windows away with the stage instead, and the next app opened brought them all back).
#pragma once
#include "WindowAPIRule.h"
#include "../common/ChoicePage.h"   // (KeyPilot's app and the Settings row's OPEN: kMSBDKeyPilotApp, kMSBDKeyPilotOpenNote)

// ---- what SpringBoard is doing ----
// Why a layout or Home must wait now (nil: it can go): what makes the Window menu unreachable, SpringBoard busy with a transition of its own, and
// whatever of ours is about to place the windows itself -- a layout asked then would be undone, or land in the frame of the shape before (review
// 1.8.3 F6): a Mac Switcher desktop sliding in, the windows coming back after a respring, a turn of the screen being applied (the other engines'
// layout notes held until the turn has placed the windows; Stage Manager settling after a turn or a transition of its own), a switcher gesture's
// transaction. (The workspace's transaction is Stage Manager's busy state as well, DMSMWorkspaceBusy.) The window keys wait the same way.
// passing (may be NULL): YES for a state that ends by itself in a moment -- a transition, a desktop sliding in, the windows coming back, a turn
// being applied -- (a title bar's double tap waits for it: TitleBarRule.h MSBDTitleTapWhen); NO for the rest.
static NSString *DMWindowAPIBusyWhyPassing(BOOL *passing) {
    if (passing) *passing = NO;
    if (DMSMHomeUILocked()) return @"locked";
    if (MSBDGuidedAccessActive()) return @"a Guided Access session";
    if (DMCoverSheetShown()) return @"the Lock Screen or Notification Center";
    if (DMSwitcherVisible()) return @"the App Switcher";
    if (gMSWOpen) return @"the Mac Switcher";
    if (DMControlCenterActive()) return @"Control Center";
    if (gOverlay) return @"a menu or question of ours";
    if (passing) *passing = YES;
    if (!DMWorkspaceIdle()) return @"a workspace transition";
    if (gMSWSwitching) return @"a Mac Switcher desktop sliding in";
    if (gRestoringWindowsFlag()) return @"the windows coming back after a respring";
    if (DMSMEngine()) {
        if (DMSMGestureLive()) return @"a switcher gesture";
        if (DMSMTurnSettling()) return @"Stage Manager settling after a turn or a transition";
    } else if (DMLayoutNotesHeld()) return @"a turn of the screen being applied";
    if (passing) *passing = NO;
    return nil;
}
static NSString *DMWindowAPIBusyWhy(void) { return DMWindowAPIBusyWhyPassing(NULL); }

static void DMWinPrevNoteNative(DMNativeWindow *w);   // (WindowKeys.h: Return to Previous Size's record, the window's frame before a tile -- while wanted)
static void DMTitleRecordNativeTo(DMNativeWindow *w, CGRect to);   // (WindowKeys.h: the title bar's frame from before follows every placement of ours, P4-1)
// Our own windows (Finder, TextEdit): one of the Window menu's layouts, in the desktop above the Dock, kept for a turn (DMNativeRelayoutForTurn) --
// the Window menu's rows, the window API and the window keys.
static void DMNativeLayout(DMNativeWindow *w, NSString *name) {
    CGRect f = DMLayoutFrameInArea(name, DMNativeDesktop(), [UIScreen mainScreen].bounds.size);
    if (!w || CGRectIsNull(f) || CGRectIsEmpty(f)) return;
    if (MSBDWinIsTileName(name.UTF8String)) DMWinPrevNoteNative(w);
    DMTitleRecordNativeTo(w, f);   // (to Fill from elsewhere: the frame now is the way back; anywhere else: none)
    w.restoreFrame = CGRectNull;
    w.layoutName = [name isEqualToString:@"center"] ? nil : name;   // (kept for a turn: DMNativeRelayoutForTurn)
    MSBAnimate(0.2, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ w.frame = f; }, nil);
}

// ---- the front window at a layout: the Window menu's own ways ----
static void DMLayoutFrontWindow(NSString *name, NSString *why) {
    DMNativeWindow *nw = DMNativeActiveApp();
    DMLog([NSString stringWithFormat:@"[winapi] %@: %@ for %@", why, name, nw ? (nw.title ?: @"our window") : ([DMActiveApp() bundleIdentifier] ?: @"no app")]);
    if (nw) { DMNativeLayout(nw, name); return; }
    DMWindowLayout(name);
}

// ---- Home: the user's Home with Home Minimizes Windows, on every engine ----
static void DMWindowAPIHome(NSString *why) {
    DM_FEATURE_MARK("window-api-home");
    if (DMSMEngine()) {
        // (Stage Manager: as its Home rule does for Home Minimizes Windows -- every window of the desktop on screen marked minimized, so each comes back
        //  with its own app and the others stay away, and the Home that takes the stage away is a real one of ours, which the rule leaves as it is)
        for (DMNativeWindow *nw in [gNativeWindows copy]) if (!nw.hidden && nw.superview) [nw minimize];
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        if (DMFrontApp()) for (id it in DMSMStageItemsMap(DMSMFrontStage())) { NSString *k = DMSMItemKey(it); if (k.length) { DMSMSetMinimized(k, YES); [names addObject:DMSMKeyText(k)]; } }
        DMLog([NSString stringWithFormat:@"[winapi] %@: Home, %@ minimized", why, names.count ? [names componentsJoinedByString:@", "] : @"no window"]);
        DMSMGoHomeForReal(why);
        dispatch_async(dispatch_get_main_queue(), ^{ DMSMHomeAfterKeep(NO); });   // (our open menu and the Downloads panel close, as at every Home)
        return;
    }
    // (Aerial, Zetsu, MilkyWay4, no engine: every window minimized -- ours too --, then SpringBoard's Home: a full-screen app goes to the background)
    DMLog([NSString stringWithFormat:@"[winapi] %@: Home, %lu window(s) minimized", why, (unsigned long)(DMVisibleWindowCount() + DMNativeVisibleWindowCount())]);
    DMMinimizeAllWindows();
    DMMinimize();
}

// ---- V1, as KeyPilot calls it (KPWindowController.m: dlopen(RTLD_NOLOAD) + dlsym, on SpringBoard's main queue) ----
// Debug builds log each call and its answer ([winapi]).
__attribute__((visibility("default"), used)) int MSBDKeyPilotLayoutV1(const char *layout) {
    MSBDWinAPIFacts f = { .mainThread = [NSThread isMainThread] };
    NSString *busy = nil;
    if (f.mainThread && MSBDWinAPILayoutIndex(layout) >= 0) {
        busy = DMWindowAPIBusyWhy();
        f.busy = busy != nil;
        f.nativeFront = DMNativeActiveApp() != nil;
        f.engine = DMActiveEngine() != DMEngineNone || DMSMEngine();
        NSString *bundle = [DMActiveApp() bundleIdentifier];
        f.activeApp = bundle.length > 0;
        f.fullScreenOnly = f.activeApp && DMAppNeedsFullScreen(bundle);
    }
    int status = MSBDWinAPILayoutStatus(layout, f);
    if (!f.mainThread) return status;   // (nothing of SpringBoard's is read off its main thread, not even to log)
    if (status != kMSBDWinAPIDispatched) {
        DMLog([NSString stringWithFormat:@"[winapi] layout %s asked for: %d%@", layout ?: "(null)", status, busy ? [NSString stringWithFormat:@" (%@)", busy] : @""]);
        return status;
    }
    DM_FEATURE_MARK("window-api-layout");
    DMLayoutFrontWindow(@(layout), @"the window API");
    return status;
}
static BOOL DMWindowAPIEnvironmentRead(long long *env);   // (below)
// Home once, whenever it is asked for (review 1.8.3 F10): KeyPilot's Cmd-H and iPadOS's own Cmd-H can both run, a press can be handed over twice.
// A second call within a second of the last, or while the last still waits, is the same Home: nothing more. SpringBoard in a transition of its own
// (iPadOS's Cmd-H Home among them) or our own Home press: it waits for its end, 0.1 s at a time for at most 2 s (WindowAPIRule.h MSBDWinAPIHomeStep),
// then the windows go and the Home comes -- at Home already, the windows only, no second Home (a Home press there would turn the Home Screen to its
// first page). Still busy after 2 s: nothing. The answer stays 0, as KeyPilot reads it.
static CFTimeInterval gWinAPIHomeAt = -100;
static BOOL gWinAPIHomeWaiting = NO;
static void DMWindowAPIMinimizeAll(NSString *why) {   // (at Home already: the windows still shown over the Home Screen go, ours too -- Minimize All Windows)
    DMLog([NSString stringWithFormat:@"[winapi] %@: at Home already -- %lu window(s) minimized, no second Home", why, (unsigned long)(DMVisibleWindowCount() + DMNativeVisibleWindowCount())]);
    DMMinimizeAllWindows();
}
static void DMWindowAPIHomeWhenFree(NSString *why, int tries) {
    BOOL locked = DMSMHomeUILocked() || MSBDGuidedAccessActive();   // (again at every step: the iPad may have locked while this waited, P2-6)
    BOOL busy = !locked && (!DMWorkspaceIdle() || DMHomeFromKeys() || DMHomeIsOurs() || (DMSMEngine() && DMSMGestureLive()));
    long long env = 0;
    BOOL atHome = !locked && !busy && DMWindowAPIEnvironmentRead(&env) && env == kMSBDWinEnvHome;
    int step = MSBDWinAPIHomeStep(locked, busy, atHome, tries);
    gWinAPIHomeWaiting = step == kMSBDWinHomeWait;
    if (step == kMSBDWinHomeWait) {
        if (!tries) DMLog([NSString stringWithFormat:@"[winapi] %@: SpringBoard is in a transition or a Home of its own: waiting for its end", why]);
        NSString *w = [why copy];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMWindowAPIHomeWhenFree(w, tries + 1); });
        return;
    }
    if (step == kMSBDWinHomeLockedNow) { DMLog([NSString stringWithFormat:@"[winapi] %@: the iPad is locked or in Guided Access now -- no Home", why]); return; }
    gWinAPIHomeAt = CACurrentMediaTime();
    if (step == kMSBDWinHomeMinimizeOnly) DMWindowAPIMinimizeAll(why);
    else if (step == kMSBDWinHomeFull) DMWindowAPIHome(why);
    else DMLog([NSString stringWithFormat:@"[winapi] %@: SpringBoard stayed busy for 2 s -- no Home", why]);
}
__attribute__((visibility("default"), used)) int MSBDKeyPilotHomeV1(void) {
    BOOL main = [NSThread isMainThread];
    int status = MSBDWinAPIHomeStatus(main, main && (DMSMHomeUILocked() || MSBDGuidedAccessActive()));
    if (!main) return status;
    if (status != kMSBDWinAPIDispatched) { DMLog([NSString stringWithFormat:@"[winapi] Home asked for: %d (locked)", status]); return status; }
    CFTimeInterval now = CACurrentMediaTime();
    if (gWinAPIHomeWaiting || MSBDWinAPIHomeAgain(now - gWinAPIHomeAt)) { DMLog([NSString stringWithFormat:@"[winapi] Home asked for again (%.2f s after the last%@): the same Home", now - gWinAPIHomeAt, gWinAPIHomeWaiting ? @", still waiting" : @""]); return status; }
    gWinAPIHomeAt = now;
    DMWindowAPIHomeWhenFree(@"the window API's Home", 0);
    return status;
}
// Where SpringBoard is, in its own word on every engine: the iPad's switcher's current unlocked environment mode (-_currentUnlockedEnvironmentMode:
// 15's one SBMainSwitcherViewController; 16-18 the iPad scene's switcher controller), else its layout state's, as Stage Manager's Home rule reads it.
// (His bridge read the layout state only, through the switcher coordinator that 15 does not have: on 15.6.1 every read was -1, also at Home.)
static BOOL DMWindowAPIEnvironmentRead(long long *env) {
    id sw = objc_getClass("SBMainSwitcherControllerCoordinator") ? DMSMHomeSwitcherController() : DMSwitcherController();
    SEL mode = NSSelectorFromString(@"_currentUnlockedEnvironmentMode");
    Method m = sw ? class_getInstanceMethod(object_getClass(sw), mode) : NULL;
    if (m && [DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(long long), NULL)]) { *env = ((long long (*)(id, SEL))objc_msgSend)(sw, mode); return YES; }
    id stage = nil;
    return DMSMHomeStateOf(DMSMHomeCurrentState(), env, &stage);
}
__attribute__((visibility("default"), used)) int MSBDKeyPilotHomeEnvironmentV1(void) {
    BOOL main = [NSThread isMainThread];
    if (!main) return MSBDWinAPIEnvironment(NO, NO, NO, 0);
    BOOL locked = DMSMHomeUILocked();
    long long env = 0;
    BOOL read = !locked && DMWindowAPIEnvironmentRead(&env);
    return MSBDWinAPIEnvironment(YES, locked, read, env);
}

// ---- KeyPilot's OPEN in Settings (Keyboard > Custom Shortcuts): when Settings cannot open its app itself, SpringBoard does -- the way every app of
// the Dock and our menus is opened (DMOpenApp; review 1.8.3 F4). Watched from the start. ----
static void DMKeyPilotOpenWatch(void) {
    static int token = 0;
    if (token) return;
    notify_register_dispatch(kMSBDKeyPilotOpenNote, &token, dispatch_get_main_queue(), ^(int t) {
        NSString *app = kMSBDKeyPilotApp;
#if DEBUG
        NSString *test = [[NSString stringWithContentsOfFile:@"/tmp/msb-kp-testapp" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (test.length) app = test;   // (the device check's stand-in, KeyboardSettings.x MSKPTestApp)
#endif
        if (!DMAppForBundle(app)) { DMLog([NSString stringWithFormat:@"[keypilot] asked to open %@, which is not installed: nothing opened", app]); return; }   // (review 1.8.3 P2-8: any process can post the note)
        DMLog([NSString stringWithFormat:@"[keypilot] Settings could not open %@ itself: opened from SpringBoard", app]);
        DMOpenApp(app);
    });
}

#if DEBUG
// The window API called as KeyPilot calls it (debug only; KPWindowController.m): MacStatusBarCore opened by its path with RTLD_NOLOAD (an image
// already loaded, never loaded anew), each function found by dlsym -- also through RTLD_DEFAULT, as its layout path asks first --, the answers
// logged ([kpapi]). kpapi_<layout> (any word: kpapi_nonsense is 2), kpapi_null (a NULL name), kpapi_hometwice (two back to back), kpapi_home (and the environment 1.5 s later, as its
// client reads it), kpapi_env, kpapi_offmain_<layout> (each of the three called off the main thread: 1, 1, -1), kpapi_syms (found or not).
static void DMWindowAPITestCall(NSString *what) {
    void *h = dlopen("/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib", RTLD_LAZY | RTLD_NOLOAD);
    int (*layout)(const char *) = h ? (int (*)(const char *))dlsym(h, "MSBDKeyPilotLayoutV1") : NULL;
    int (*home)(void) = h ? (int (*)(void))dlsym(h, "MSBDKeyPilotHomeV1") : NULL;
    int (*env)(void) = h ? (int (*)(void))dlsym(h, "MSBDKeyPilotHomeEnvironmentV1") : NULL;
    void *anyLayout = dlsym(RTLD_DEFAULT, "MSBDKeyPilotLayoutV1"), *anyHome = dlsym(RTLD_DEFAULT, "MSBDKeyPilotHomeV1"), *anyEnv = dlsym(RTLD_DEFAULT, "MSBDKeyPilotHomeEnvironmentV1");
    if ([what isEqualToString:@"syms"] || !layout || !home || !env) {
        Dl_info info = {0};
        if (layout) dladdr((void *)layout, &info);
        DMLog([NSString stringWithFormat:@"[kpapi] NOLOAD handle %@; by it: layout %p home %p environment %p; RTLD_DEFAULT: %p %p %p (%@); in %s", h ? @"found" : @"MISSING",
               layout, home, env, anyLayout, anyHome, anyEnv, (anyLayout == (void *)layout && anyHome == (void *)home && anyEnv == (void *)env) ? @"the same" : @"NOT the same", info.dli_fname ?: "?"]);
    }
    if (!layout || !home || !env) { if (h) dlclose(h); return; }
    if ([what isEqualToString:@"home"]) {
        int r = home();
        DMLog([NSString stringWithFormat:@"[kpapi] MSBDKeyPilotHomeV1() = %d", r]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DMLog([NSString stringWithFormat:@"[kpapi] 1.5 s later MSBDKeyPilotHomeEnvironmentV1() = %d (1 Home, 2 Switcher, 3 App)", env()]);
        });
    } else if ([what isEqualToString:@"hometwice"]) {   // (Home asked for twice back to back, as KeyPilot's Cmd-H and iPadOS's can come: one Home)
        int a = home(), b = home();
        DMLog([NSString stringWithFormat:@"[kpapi] MSBDKeyPilotHomeV1() twice: %d, %d", a, b]);
    } else if ([what isEqualToString:@"env"]) {
        DMLog([NSString stringWithFormat:@"[kpapi] MSBDKeyPilotHomeEnvironmentV1() = %d", env()]);
    } else if ([what hasPrefix:@"offmain_"]) {
        NSString *name = [what substringFromIndex:8];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            int a = layout(name.UTF8String), b = home(), c = env();
            dispatch_async(dispatch_get_main_queue(), ^{ DMLog([NSString stringWithFormat:@"[kpapi] off the main thread: layout(%@) = %d, home() = %d, environment() = %d", name, a, b, c]); });
        });
    } else if ([what isEqualToString:@"null"]) {
        DMLog([NSString stringWithFormat:@"[kpapi] MSBDKeyPilotLayoutV1(NULL) = %d", layout(NULL)]);
    } else if (![what isEqualToString:@"syms"]) {
        int r = layout(what.UTF8String);
        DMLog([NSString stringWithFormat:@"[kpapi] MSBDKeyPilotLayoutV1(\"%@\") = %d", what, r]);
    }
    dlclose(h);
}
#endif
