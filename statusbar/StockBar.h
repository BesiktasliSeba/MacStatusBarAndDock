// StockBar.h -- "Use Stock Status Bar" (Settings > Status Bar, off by default). Included by StatusBar.x just before its %ctor (plain code, no Logos).
// On, after a respring, SpringBoard keeps iPadOS's own status bar and our window work is off. StatusBar.x's %ctor then runs only DMStockBarStart:
//  - not installed: every ungrouped hook of StatusBar.x (the status bar and its menus, clock Today View, Spotlight / keyboard buttons, background,
//    traffic lights, Control Center from the bar, multitasking dots, our scene hooks) and every engine / windowing group;
//  - not started: DMTick, the 0.2 s window watcher, the startup display link, the menu window, window restore, engine hooks and styling, windowed
//    launch, the Aerial 5.0 frame watcher, the switcher timer, Control Center prewarm, auto-hide, the status bar over games;
//  - the engine gets its own settings back (the give-back used when MacStatusBar is switched off) and runs on its own. Engine exclusivity (only the
//    picked engine loads) stays: it is about stability, not our look. Stage Manager comes back if the user had it on (as with windowing off);
//  - audio: mixing is published as off and Loader.c does not load MixAudio into apps, so one app plays at a time and no per-app level applies.
// What stays here: skip Lock Screen after respring, Mac banners, Haptic Touch menus and their crash guards, the Mac pointer bridge, Block Pointer
// Pull-Down, the welcome alert,
// Control Center's RAM/CPU and uptime tiles (while it shows; not the panel scale).
// Everything else that stays (Dock, MacSettings, Home Screen, keyboard, Force Quit / App Size / Folder rows) is a payload of its own.
// Switched on during a full run: the engines get their settings back at once (DMStockPendingChanged), so the respring comes up clean.

#define MSBD_STOCK_STATE "com.besiktasliseba.macstatusbar.stock"   // (notify state, 1 = stock status bar; read by Loader.c)

static void DMStockPublish(void) {
    static int token = 0;   // (kept registered: the state lives as long as this SpringBoard)
    if (!token) notify_register_check(MSBD_STOCK_STATE, &token);
    if (token) notify_set_state(token, gStockBar ? 1 : 0);
    if (!gStockBar) DMLog(@"[stock] Use Stock Status Bar: off (the Mac status bar runs)");
}

static void DMStockGiveBackEngines(NSString *why) {
    gA5PrefsState = 2;
    DMAerial5GiveBackPrefs(why);
    DMEnginePrefsGiveBack(@"Zetsu", why);
    DMEnginePrefsGiveBack(@"MilkyWay", why);
}
static void DMStockPendingChanged(void) {
    if (gStockBar) return;
    if (DMStockBarPending()) {
        DMStockGiveBackEngines(@"Use Stock Status Bar switched on");
        DMLog(@"[stock] switched on: the engine has its own settings again; the stock status bar comes with the respring");
    } else DMLog(@"[stock] switched off again before a respring: the engine's settings are held again");
}

// Stage Manager: what DMStageManagerWatch does once no engine of ours runs (the user's wish, kept while it was held off, comes back).
static void DMStockGiveBackStageManager(void) {
    CFPropertyListRef saved = CFPreferencesCopyValue(CFSTR("stageManagerUserOn"), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!saved) return;
    CFRelease(saved);
    id sd = DMSwitcherDefaults();
    SEL set = NSSelectorFromString(@"setChamoisWindowingEnabled:");
    if (![sd respondsToSelector:set]) return;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(sd, set, YES);
    CFPreferencesSetValue(CFSTR("stageManagerUserOn"), NULL, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    DMLog(@"[stock] Stage Manager is back on, as the user had it");
}

// The one light timer (0.5 s, stops with the screen): the skip-Lock-Screen fallback and Lock Screen clock settle (DMWatchLock) while that setting is
// on, and the welcome alert while it is pending. With neither it stops for good.
static NSTimer *gStockLightTimer;
static void DMStockLightTick(void) {
    BOOL lock = DMSkipLockWanted();
    if (lock) DMWatchLock();
    if (gWelcomeState != 2) DMCheckWelcome();
    if (!lock && gWelcomeState == 2) { [gStockLightTimer invalidate]; gStockLightTimer = nil; DMLog(@"[stock] light timer stopped: nothing left to watch"); }
}

static void DMStockBarStart(void) {
    DMStockGiveBackEngines(@"stock status bar");   // (now: Zetsu and MilkyWay4 load after us, Aerial 5.0 reads its settings when it sets up its window)
    {   // audio: iPadOS's own rule (MixAudio is not loaded into apps either, see Loader.c)
        static int mixToken = 0;
        if (!mixToken) notify_register_check("com.besiktasliseba.mixaudio.disabled", &mixToken);
        if (mixToken) { notify_set_state(mixToken, 1); notify_post("com.besiktasliseba.mixaudio.disabled"); }
    }
    if (!DMTestFlag("/tmp/msb-noorientnotes")) [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];   // (the Mac pointer's turn)
    DMScreenPowerWatch();
    DMBannersInit();
    {   // Block Pointer Pull-Down (Settings > Pointer): the one hook and its one setting, followed live
        CFPreferencesAppSynchronize(MSB_DOMAIN);
        DMReadBlockPointerPull();
        DMPointerPullInit();
        int t = 0;
        notify_register_dispatch("com.besiktasliseba.macstatusbar/prefsChanged", &t, dispatch_get_main_queue(), ^(int tok) { CFPreferencesAppSynchronize(MSB_DOMAIN); DMReadBlockPointerPull(); });
    }
    DMContextMenusInit();   // (without the status bar over games)
    DMStockCCTilesInit();   // (Control Center's RAM/CPU and uptime tiles, only while it shows)
    { int t = 0; if (notify_register_check("com.besiktasliseba.macstatusbar.alive", &t) == NOTIFY_STATUS_OK) notify_set_state(t, (uint64_t)getpid()); }   // heartbeat (sshtoggled)
    // The Dock's "Downloads From…" sends its Settings link here whenever the heartbeat above names this SpringBoard (Downloads.m). In stock mode the
    // window engine runs on its own, so the link is simply opened: iOS brings Settings up full screen and shows the page (no engine code involved).
    { int t = 0; notify_register_dispatch("com.besiktasliseba.macstatusbaranddock.opendownloadsfrom", &t, dispatch_get_main_queue(), ^(int tok) {
        DMOpenURL(@"prefs:root=DOCK_MAGNIFICATION&path=DOWNLOADS", @"[stock] Downloads From: Settings link opened"); }); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMPointerBridgeStart(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ notify_post("com.besiktasliseba.msb.engines.apply"); });   // (exclusivity, as at every start)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMStockGiveBackStageManager(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{   // (when the full run's watcher starts too)
        gStockLightTimer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { DMStockLightTick(); }];
        gStockLightTimer.tolerance = 0.1;
        [[NSRunLoop mainRunLoop] addTimer:gStockLightTimer forMode:NSRunLoopCommonModes];
        DMGateTimer(gStockLightTimer);
        DMStockLightTick();
    });
#if DEBUG
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{   // (test builds: the triggers still work)
        NSTimer *t = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { DMCheckTrigger(); }];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    });
#endif
    DMLog([NSString stringWithFormat:@"[stock] Use Stock Status Bar: ON. Running: skip-lock hook (%@), Mac banners, Haptic Touch menus + crash guards, pointer bridge (0.25 s), "
           "screen power watch, light timer (0.5 s, from 8 s; %@). Not running: status bar hooks, DMTick, window watcher, startup display link, menu window, "
           "window restore, engine hooks/styling/prefs hold, windowed launch, A5 frame watcher, switcher timer, CC prewarm, auto-hide, bar over games, audio mixing.",
           DMSkipLockWanted() ? @"setting on" : @"setting off", DMSkipLockWanted() ? @"lock watch + welcome" : @"welcome check only, then stops"]);
}
