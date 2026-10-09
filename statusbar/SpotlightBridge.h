// SpotlightBridge.h -- included into StatusBar.x just before its %ctor (plain code, no Logos). SpringBoard's half of our sections in Apple's
// Spotlight (1.4.3, S-3 #2 "Actions" and #3 "Windows"); spotlight/MacSpotlight.x is the other half, inside the Spotlight app.
//
// Our menu bar's magnifier opens Apple's own Spotlight (DMOpenSpotlight). Its results are made and drawn by the Spotlight app (com.apple.Spotlight,
// a separate, sandboxed process: SpringBoard only hosts its scene, SPUIRemoteSearchViewController), so what we add is added there, and this side
// only says what there is and does what was picked:
//  - the switches go there as notify state (DM_SPOT_STATE: 1 Actions, 2 Windows, 4 Tweak Settings -- search-143's items, which MacSpotlight moves
//    below Apple's results), the way the App Store gets its Updates tab switch (AppBridge.x): any app may read notify state;
//  - what can be listed goes there as a small file in the jailbreak's own root (DMSpotPath): the app reads the jailbreak's root (it loads our parts
//    from there) but none of SpringBoard's files. Written when the Spotlight app asks (DM_SPOT_REQUEST, as Spotlight comes up), only while
//    Actions or Windows is on, and removed when both go off. It holds names only: our actions, and the open windows' titles, apps and desktops;
//  - a pick comes back as notify state (DM_SPOT_PICK: the list's generation << 32 | the row's place), is taken only while Spotlight is up and
//    only for a list just written, and runs here once Spotlight has gone (DMSpotRunAfterSpotlight).
// Every action is one we already have, so every engine does what it does elsewhere: Desktop N is the Mac Switcher's switch (Stage Manager's too,
// DMMSWSwitchTo), a window comes forward the way opening its app or the Mac Switcher's pick brings it (DMSurfaceWindowForApp, DMSMBringToFront,
// -[DMNativeWindow show]), Show Desktop is Minimize All Windows (every engine) plus Finder's windows and a full-screen app going Home.
// Settings > Status Bar > Spotlight: Actions in Spotlight (spotlightActions), Windows in Spotlight (spotlightWindows), both off unless switched on.

#define DM_SPOT_STATE   "com.besiktasliseba.macstatusbar.spotlight.state"
#define DM_SPOT_REQUEST "com.besiktasliseba.macstatusbar.spotlight.request"
#define DM_SPOT_READY   "com.besiktasliseba.macstatusbar.spotlight.ready"
#define DM_SPOT_PICK    "com.besiktasliseba.macstatusbar.spotlight.pick"
#define DM_SPOT_REPORT  "com.besiktasliseba.macstatusbar.spotlight.report"   // (debug builds of MacSpotlight: what happened there, for our log)

static BOOL gSpotActions = NO, gSpotWindows = NO, gSpotTweaks = NO;
static BOOL gSpotGuardTripped = NO;   // (the Spotlight app went away twice while showing our list: nothing of ours until the next respring)
static NSArray<NSDictionary *> *gSpotItems;      // the list last written: each row's file fields plus "run" (a block, kept here only)
static uint64_t gSpotGen = 0;
static CFTimeInterval gSpotWrittenAt = 0;
static CFTimeInterval gSpotAskedAt = 0;   // (the Spotlight app last came up with a switch of ours on: it asks then, whichever switch it is)

static NSString *DMSpotDir(void) { return @"/var/jb/var/mobile/Library/Caches/com.besiktasliseba.macstatusbar"; }
static NSString *DMSpotPath(void) { return [DMSpotDir() stringByAppendingPathComponent:@"Spotlight.plist"]; }

static void DMSpotPublishState(void) {
    static int token = 0;
    if (!token && notify_register_check(DM_SPOT_STATE, &token) != NOTIFY_STATUS_OK) token = 0;
    uint64_t st = gSpotGuardTripped ? 0 : (gSpotActions ? 1 : 0) | (gSpotWindows ? 2 : 0) | (gSpotTweaks ? 4 : 0);
    if (token) notify_set_state(token, st);
    notify_post(DM_SPOT_STATE);
    if (!gSpotActions && !gSpotWindows) {   // (nothing of ours to list: no list is left behind, nor its folder)
        gSpotItems = nil;
        if ([[NSFileManager defaultManager] removeItemAtPath:DMSpotPath() error:nil]) DMLog(@"[spotlight] list removed (Actions and Windows are off)");
        rmdir(DMSpotDir().fileSystemRepresentation);   // (only when empty)
    }
}
// (DMLoadPrefs, on every settings change: the three switches, each off unless switched on)
static void DMSpotReadPrefs(void) {
    BOOL (^pref)(CFStringRef) = ^BOOL(CFStringRef key) {
        CFPropertyListRef v = CFPreferencesCopyValue(key, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
        if (v) CFRelease(v);
        return on;
    };
    BOOL a = pref(CFSTR("spotlightActions")), w = pref(CFSTR("spotlightWindows")), t = pref(CFSTR("spotlightTweakSettings"));
    if (DMStockBarSwitch()) a = w = t = NO;   // ("Use Stock Status Bar" hides the group: all of it off at once, before the respring the stock bar needs)
    static BOOL told = NO;
    if (told && a == gSpotActions && w == gSpotWindows && t == gSpotTweaks) return;
    told = YES;
    gSpotActions = a; gSpotWindows = w; gSpotTweaks = t;
    DMLog([NSString stringWithFormat:@"[spotlight] Actions %@, Windows %@ (Tweak Settings %@)", a ? @"on" : @"off", w ? @"on" : @"off", t ? @"on" : @"off"]);
    DMSpotPublishState();
}

// ---- the actions ----
static UIView *DMSpotHost(void) {   // (where a question or a panel opens: the menu window, as the Apple menu's own)
    if (!gMenuWindow && !DMCtorSkip("menuwin")) DMCreateMenuWindow();
    return gMenuWindow ? DMMenuHost() : nil;
}
// Show Desktop: every window out of the way, so the desktop shows -- the windows go down to the Dock as Minimize All Windows does on every engine,
// Finder's windows too, and a full-screen app goes Home. The Dock (or opening an app) brings each one back.
static void DMSpotShowDesktop(void) {
    DM_FEATURE_MARK("spotlight-show-desktop");
    NSUInteger natives = 0;
    DMMinimizeAllWindows();
    for (DMNativeWindow *w in [gNativeWindows copy]) if (!w.hidden && w.superview) { [w minimize]; natives++; }
    BOOL fullScreen = DMFrontApp() && DMFullScreenAppInFront();
    if (fullScreen) DMMinimize();
    DMLog([NSString stringWithFormat:@"[spotlight] Show Desktop: windows minimized, %lu Finder windows, full-screen app %@", (unsigned long)natives, fullScreen ? @"sent Home" : @"none"]);
}
// The Downloads folder Finder shows (its sidebar's: iCloud Drive's, where Safari saves), else On My iPad's own; nil when there is neither.
static NSString *DMSpotDownloadsFolder(void) {
    NSMutableArray *candidates = [NSMutableArray arrayWithObject:@"/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Downloads"];
    NSString *mine = DMFinderOnMyIPad();
    if (mine) [candidates addObject:[mine stringByAppendingPathComponent:@"Downloads"]];
    for (NSString *p in candidates) { BOOL dir = NO; if ([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir] && dir) return p; }
    return nil;
}
static void DMSpotOpenFolder(NSString *path) {   // (a Finder window already showing it comes forward; else a new one)
    for (DMNativeWindow *w in [gNativeWindows reverseObjectEnumerator])
        if ([w isKindOfClass:[DMFinderWindow class]] && [((DMFinderWindow *)w).path isEqualToString:path]) { [w show]; return; }
    DMFinderOpen(path, YES);
}
static void DMSpotForceQuit(NSString *bundle, NSString *name) {   // (asks first; no app named or it has gone: the Force Quit Applications panel)
    UIView *host = DMSpotHost();
    if (!host) return;
    BOOL running = NO;
    for (SBApplication *a in DMUserRunningApps()) if ([[a bundleIdentifier] isEqualToString:bundle]) running = YES;
    if (!bundle.length || !running) { DMShowForceQuitList(host); return; }
    DMShowConfirm(host, [NSString stringWithFormat:@"Force quit %@?", name], [NSString stringWithFormat:@"Anything you have not saved in %@ will be lost.", name],
                  @"Force Quit", YES, ^{ DMForceQuitBundle(bundle); });
}
static NSDictionary *DMSpotRow(NSString *group, NSString *title, NSString *detail, NSString *keys, NSString *symbol, NSString *bundle, dispatch_block_t run) {
    NSMutableDictionary *r = [NSMutableDictionary dictionaryWithDictionary:@{@"g": group, @"t": title ?: @"", @"d": detail ?: @"", @"k": keys ?: @""}];
    if (symbol) r[@"s"] = symbol;
    if (bundle) r[@"b"] = bundle;
    if (run) r[@"run"] = [run copy];
    return r;
}
static NSArray<NSDictionary *> *DMSpotActionRows(void) {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableDictionary *show = [DMSpotRow(@"a", @"Show Desktop", @"Puts every window aside", @"show desktop hide windows", @"menubar.dock.rectangle", nil, ^{ DMSpotShowDesktop(); }) mutableCopy];
    show[@"clear"] = @YES;
    [rows addObject:show];
    if (DMMSWMulti()) {   // (the Mac Switcher's desktops, two or more: each by its id, so a desktop removed meanwhile is never mistaken for another)
        for (NSUInteger i = 0; i < gMSWDesks.count; i++) {
            NSNumber *did = gMSWDesks[i];
            BOOL cur = i == gMSWCur;
            NSMutableDictionary *desk = [DMSpotRow(@"a", DMMSWDeskName(i), cur ? @"The current desktop" : @"Mac Switcher", [NSString stringWithFormat:@"desktop %lu space %lu", (unsigned long)i + 1, (unsigned long)i + 1],
                                      @"rectangle.on.rectangle", nil, ^{
                NSUInteger at = [gMSWDesks indexOfObject:did];
                if (at == NSNotFound || at == gMSWCur) return;
                DMMSWSwitchTo(at, @"Spotlight", nil);
            }) mutableCopy];
            desk[@"clear"] = @YES;
            [rows addObject:desk];
        }
    }
    if (gFinderOn) {
        NSString *dl = DMSpotDownloadsFolder();
        if (dl) [rows addObject:DMSpotRow(@"a", @"Downloads", @"Opens the Downloads folder in Finder", @"downloads download", @"arrow.down.circle", nil, ^{ DMSpotOpenFolder(dl); })];
        [rows addObject:DMSpotRow(@"a", @"New Finder Window", @"Finder", @"new finder window", @"folder", nil, ^{ DMFinderOpen(nil, YES); })];
    }
    [rows addObject:DMSpotRow(@"a", @"Lock Screen", @"Locks this iPad", @"lock screen", @"lock", nil, ^{ DMLock(); })];
    SBApplication *front = DMForceQuitTargetApp();   // (the app the menu bar names, as the Apple menu's Force Quit row)
    NSString *fb = [front bundleIdentifier], *fn = [front displayName] ?: fb;
    BOOL listed = NO;   // (an app the Force Quit Applications panel lists: no background service, no app hidden with AppHider)
    for (SBApplication *a in DMUserRunningApps()) if (fb.length && [[a bundleIdentifier] isEqualToString:fb]) listed = YES;
    if (listed) {
        NSMutableDictionary *fq = [DMSpotRow(@"a", [NSString stringWithFormat:@"Force Quit %@…", fn], @"Asks before quitting it", @"force quit", @"xmark.octagon", nil, ^{ DMSpotForceQuit(fb, fn); }) mutableCopy];
        fq[@"m"] = @"Force Quit";   // (found by "force quit", not by the app's name: that finds its window)
        [rows addObject:fq];
    }
    else [rows addObject:DMSpotRow(@"a", @"Force Quit Applications…", @"Choose an app to force quit", @"force quit", @"xmark.octagon", nil, ^{ DMSpotForceQuit(nil, nil); })];
    return rows;
}

// ---- the windows: every engine's windows and Finder's, on this desktop and the others, minimized ones too ----
static NSString *DMSpotWhere(NSInteger did, BOOL minimized) {   // ("Desktop 2", "Minimized", "Desktop 2 · Minimized"; "Window" with one desktop)
    NSMutableArray *p = [NSMutableArray array];
    if (DMMSWMulti()) { NSUInteger i = [gMSWDesks indexOfObject:@(did)]; [p addObject:DMMSWDeskName(i == NSNotFound ? gMSWCur : i)]; }
    if (minimized) [p addObject:@"Minimized"];
    return p.count ? [p componentsJoinedByString:@" · "] : @"Window";
}
// (a window of another desktop: that desktop first, then the window -- the Mac Switcher's switch, which every engine has)
static void DMSpotOnDesktopThen(NSInteger did, dispatch_block_t then) {
    NSUInteger at = DMMSWMulti() ? [gMSWDesks indexOfObject:@(did)] : NSNotFound;
    if (at == NSNotFound || at == gMSWCur) { then(); return; }
    DMMSWSwitchTo(at, @"Spotlight", then);
}
static NSArray<NSDictionary *> *DMSpotWindowRows(void) {
    NSMutableArray *rows = [NSMutableArray array], *others = [NSMutableArray array];
    NSInteger cur = DMMSWCurId();
    // (an app hidden with AppHider is never named here, as Finder and Force Quit Applications leave it out: its window is simply not listed)
    NSMutableSet *seen = [NSMutableSet setWithSet:DMFinderHiddenApps() ?: [NSSet set]];
    if (DMSMEngine()) {   // Stage Manager: each window by its own key (two windows of one app are two rows, M-2)
        NSMutableArray<NSArray *> *wins = [NSMutableArray array];   // @[key, desktop id, minimized]
        for (NSString *k in DMSMWindowKeys()) [wins addObject:@[k, @(cur), @NO]];
        if (DMMSWMulti()) for (NSNumber *d in gMSWDesks) if (d.integerValue != cur) for (NSArray *w in DMMSWSMDeskWindows(d.integerValue)) [wins addObject:@[w[3], d, @NO]];
        for (NSString *k in [[DMSMMinimizedSet() allObjects] sortedArrayUsingSelector:@selector(compare:)]) [wins addObject:@[k, DMMSWSMRecordOf(k) ?: @(cur), @YES]];
        for (NSArray *w in wins) {
            NSString *k = w[0], *b = DMSMKeyBundle(k);
            if (!b.length || [seen containsObject:k] || [seen containsObject:b]) continue;   // (b in it: an app hidden with AppHider)
            [seen addObject:k];
            NSInteger did = [w[1] integerValue]; BOOL mini = [w[2] boolValue];
            NSString *name = DMMSWAppName(b);
            [(did == cur ? rows : others) addObject:DMSpotRow(@"w", name, DMSpotWhere(did, mini), name, nil, b, ^{
                if (mini) { DMOpenApp(b); return; }   // (a minimized window: opening its app brings it back, as from the Dock)
                DMSpotOnDesktopThen(did, ^{ DMSMBringToFront(k); });
            })];
        }
    } else if (DMActiveEngine() != DMEngineNone) {   // Aerial, Zetsu, MilkyWay4: one window per app, each engine's own (DMAerialStagesAll)
        for (UIView *st in DMAerialStagesAll()) {
            NSString *b = DMStageBundle(st);
            if (!b.length || [seen containsObject:b] || [objc_getAssociatedObject(st, kStageClosingKey) boolValue]) continue;
            [seen addObject:b];
            BOOL mini = DMStageMinimized(st) || [objc_getAssociatedObject(st, kStageHiddenKey) boolValue];
            NSInteger did = (DMMSWMulti() && gMSWWinDesk[b]) ? gMSWWinDesk[b].integerValue : cur;
            NSString *name = DMMSWAppName(b);
            [(did == cur ? rows : others) addObject:DMSpotRow(@"w", name, DMSpotWhere(did, mini), name, nil, b, ^{ if (!DMSurfaceWindowForApp(b)) DMOpenApp(b); })];
        }
        if (DMMSWMulti()) for (NSString *b in [[gMSWWinDesk allKeys] sortedArrayUsingSelector:@selector(compare:)]) {   // (closed by iPadOS while away: it comes back with its desktop)
            if ([seen containsObject:b] || gMSWWinDesk[b].integerValue == cur || DMMSWElsewhereIndex(b) == NSNotFound) continue;
            [seen addObject:b];
            NSString *name = DMMSWAppName(b);
            [others addObject:DMSpotRow(@"w", name, DMSpotWhere(gMSWWinDesk[b].integerValue, NO), name, nil, b, ^{ if (!DMSurfaceWindowForApp(b)) DMOpenApp(b); })];
        }
    }
    // Finder's (native) windows: this desktop's, then the others'
    for (DMNativeWindow *w in [gNativeWindows copy]) {
        BOOL mini = w.hidden && w.dm_wasMinimized;
        if ((w.hidden && !mini) || !w.title.length) continue;
        __weak DMNativeWindow *ww = w;
        NSString *app = w.appName ?: @"Finder";
        [rows addObject:DMSpotRow(@"w", w.title, [NSString stringWithFormat:@"%@ · %@", app, DMSpotWhere(cur, mini)], [NSString stringWithFormat:@"%@ %@", w.title, app], @"folder", nil, ^{
            DMNativeWindow *x = ww; if (x && [gNativeWindows containsObject:x]) [x show];
        })];
    }
    for (DMNativeWindow *w in [gMSWAwayNatives copy]) {
        NSNumber *did = objc_getAssociatedObject(w, kMSWNativeDeskKey);
        if (!w.title.length || ![did isKindOfClass:[NSNumber class]]) continue;
        __weak DMNativeWindow *ww = w;
        NSString *app = w.appName ?: @"Finder";
        NSInteger d = did.integerValue;
        [others addObject:DMSpotRow(@"w", w.title, [NSString stringWithFormat:@"%@ · %@", app, DMSpotWhere(d, NO)], [NSString stringWithFormat:@"%@ %@", w.title, app], @"folder", nil, ^{
            DMSpotOnDesktopThen(d, ^{ DMNativeWindow *x = ww; if (x && [gNativeWindows containsObject:x]) [x show]; });
        })];
    }
    for (NSUInteger i = 0; i < others.count; i++) { NSMutableDictionary *o = [others[i] mutableCopy]; o[@"clear"] = @YES; others[i] = o; }   // (their desktop switches first)
    [rows addObjectsFromArray:others];
    return rows.count > 60 ? [rows subarrayWithRange:NSMakeRange(0, 60)] : rows;
}

// ---- the list for the Spotlight app ----
// Locked (Spotlight from the Lock Screen or the Cover Sheet): an empty list -- no window names and no actions before the iPad is unlocked.
static BOOL DMSpotLocked(void) {
    id csm = DMSBManager("SBCoverSheetPresentationManager");
    SEL vis = NSSelectorFromString(@"isVisible");
    return DMLockUp(DMSBManager("SBLockScreenManager")) || ([csm respondsToSelector:vis] && ((BOOL (*)(id, SEL))objc_msgSend)(csm, vis));
}
// outside: Spotlight hosted elsewhere than its own window (the Today view, the Lock Screen's): an empty list, so no rows of ours show there.
static void DMSpotWriteList(NSString *why, BOOL outside) {
    if ((!gSpotActions && !gSpotWindows) || gSpotGuardTripped) return;
    NSMutableArray *rows = [NSMutableArray array];
    BOOL locked = DMSpotLocked(), none = locked || outside;
    @try {
        if (gSpotActions && !none) [rows addObjectsFromArray:DMSpotActionRows()];
        if (gSpotWindows && !none) [rows addObjectsFromArray:DMSpotWindowRows()];
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[spotlight] list not made: %@", e]); return; }
    if (locked) why = [why stringByAppendingString:@", locked: nothing listed"];
    else if (outside) why = [why stringByAppendingString:@", not in Spotlight's own window (the Today view): nothing listed"];
    gSpotGen = (gSpotGen + 1) & 0x7FFFFFFF;
    if (!gSpotGen) gSpotGen = 1;
    NSMutableArray *file = [NSMutableArray array];
    for (NSDictionary *r in rows) { NSMutableDictionary *f = [r mutableCopy]; [f removeObjectForKey:@"run"]; [f removeObjectForKey:@"clear"]; [file addObject:f]; }
    NSError *e = nil;
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:@{@"gen": @(gSpotGen), @"rows": file, @"outside": @(none)} format:NSPropertyListBinaryFormat_v1_0 options:0 error:&e];
    // (mobile's own, 0600 in a 0700 folder: SpringBoard and the Spotlight app both run as mobile; removed again once Spotlight has read it)
    [[NSFileManager defaultManager] createDirectoryAtPath:DMSpotDir() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    if (!d || ![d writeToFile:DMSpotPath() options:NSDataWritingAtomic error:&e]) { DMLog([NSString stringWithFormat:@"[spotlight] list not written: %@", e.localizedDescription]); return; }
    chmod(DMSpotDir().fileSystemRepresentation, 0700); chmod(DMSpotPath().fileSystemRepresentation, 0600);   // (also a folder an older build made)
    gSpotItems = rows;
    gSpotWrittenAt = CACurrentMediaTime();
    uint64_t written = gSpotGen;   // (the app reads the list the moment it hears it is ready; the names do not stay on disk after that)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (written == gSpotGen && [[NSFileManager defaultManager] removeItemAtPath:DMSpotPath() error:nil]) DMLog(@"[spotlight] list file removed (read by Spotlight)");
    });
    static int ready = 0;
    if (!ready && notify_register_check(DM_SPOT_READY, &ready) != NOTIFY_STATUS_OK) ready = 0;
    if (ready) notify_set_state(ready, gSpotGen);
    notify_post(DM_SPOT_READY);
    NSUInteger windows = 0; for (NSDictionary *r in rows) if ([r[@"g"] isEqualToString:@"w"]) windows++;
    DMLog([NSString stringWithFormat:@"[spotlight] list %llu written (%@): %lu actions, %lu windows", (unsigned long long)gSpotGen, why, (unsigned long)(rows.count - windows), (unsigned long)windows]);
}
static void DMSpotWrite(NSString *why) { DMSpotWriteList(why, NO); }
// Spotlight is put away first; the action runs as it goes (0.12 s: Spotlight's fade has begun, the way an app Apple's results open comes up), or,
// for a row that changes the whole screen ("clear": a desktop switch, Show Desktop, a window on another desktop), once Spotlight is gone -- the
// switch's slide takes a picture of the screen, and Spotlight must not be in it -- at most 1.5 s.
static void DMSpotRunAfterSpotlight(dispatch_block_t run, BOOL clear, int tries) {
    static CFTimeInterval t0;
    if (tries == 0) {
        t0 = CACurrentMediaTime();
        id sb = [UIApplication sharedApplication];
        SEL s = NSSelectorFromString(@"_toggleSearch");
        if (DMSpotlightShown() && [sb respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(sb, s);
    }
    BOOL wait = clear ? (DMSpotlightShown() && tries < 38) : tries < 3;
    if (wait) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.04 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMSpotRunAfterSpotlight(run, clear, tries + 1); });
        return;
    }
    DMLog([NSString stringWithFormat:@"[spotlight] the action runs %.0f ms after the pick (Spotlight %@)", (CACurrentMediaTime() - t0) * 1000.0, DMSpotlightShown() ? @"still going" : @"gone"]);
    run();
}
static void DMSpotPicked(uint64_t st) {
    uint64_t gen = st >> 32, row = st & 0xFFFFFFFFull;
    NSDictionary *r = (gen == gSpotGen && row < gSpotItems.count) ? gSpotItems[(NSUInteger)row] : nil;
    // (taken only from Spotlight on the screen, for the list written last and lately: anything else posting this name gets nothing)
    if (!r || !DMSpotlightShown() || DMSpotLocked() || CACurrentMediaTime() - gSpotWrittenAt > 600.0) {
        DMLog([NSString stringWithFormat:@"[spotlight] pick %llu:%llu refused (%@)", gen, row, !r ? @"no such row in the last list" : !DMSpotlightShown() ? @"Spotlight is not up" : DMSpotLocked() ? @"locked" : @"the list is old"]);
        return;
    }
    DM_FEATURE_MARK("spotlight-pick");
    DMLog([NSString stringWithFormat:@"[spotlight] picked %@ row %llu: %@ (%@)", [r[@"g"] isEqualToString:@"w"] ? @"window" : @"action", row, r[@"t"], r[@"d"]]);
    dispatch_block_t run = r[@"run"];
    if (run) DMSpotRunAfterSpotlight(run, [r[@"clear"] boolValue], 0);
}
// ---- the guard: the Spotlight app gone twice while our code was in it ----
// SpringBoard hears when the Spotlight app's scene dies while it is on the screen (SpotlightUI: -[SPUIRemoteSearchViewController
// didInvalidateSceneWhenForeground], the search view's own, in 15.6.1 and 16.7.7). With any of our three switches on, MacSpotlight's hooks are in
// that app (Actions and Windows, and the move of Tweak Settings below Apple's results, which runs for every search). Twice within ten minutes:
// all three are switched off for good (Settings shows them off; Tweak Settings' rows leave Spotlight too), and nothing of ours reaches the
// Spotlight app until the next respring (the state it reads goes to 0, so it hooks nothing more), as the crash guard does for SpringBoard.
static void (*o_SpotSceneDied)(id, SEL);
static void DMSpotSceneDied(id self, SEL _cmd) {
    o_SpotSceneDied(self, _cmd);
    static CFTimeInterval first = 0;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL ours = !gSpotGuardTripped && (gSpotActions || gSpotWindows || gSpotTweaks);
    DMLog([NSString stringWithFormat:@"[spotlight] the Spotlight app went away while it was on the screen%@", ours ? [NSString stringWithFormat:@" (our code in it; it came up %.0f s ago)", gSpotAskedAt > 0 ? now - gSpotAskedAt : -1.0] : @""]);
    if (!ours) return;
    if (!first || now - first > 600.0) { first = now; return; }
    first = 0;
    gSpotGuardTripped = YES;
    for (NSString *k in @[@"spotlightActions", @"spotlightWindows", @"spotlightTweakSettings"])
        CFPreferencesSetValue((__bridge CFStringRef)k, kCFBooleanFalse, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    gSpotActions = gSpotWindows = gSpotTweaks = NO;
    DMSpotPublishState();
    notify_post("com.besiktasliseba.macstatusbar/prefsChanged");   // (Tweak Settings' donation is taken back: SpotlightFiles.x, Settings)
    DMLog(@"[spotlight] the Spotlight app went away twice in ten minutes with our code in it: Actions, Windows and Tweak Settings switched off, Spotlight left as Apple's until the next respring");
}
// The Spotlight app asks for the list as it comes up (any switch of ours on). Locked: the empty list at once. Our rows only in Spotlight's own
// window (SpringBoard puts it up first: up to a second for it to show); the Today view and anything else posting the name get the empty list.
static void DMSpotAsked(int tries) {
    if (gSpotGuardTripped || (!gSpotActions && !gSpotWindows && !gSpotTweaks)) return;
    if (!tries) gSpotAskedAt = CACurrentMediaTime();
    if (DMSpotLocked()) { DMSpotWriteList(@"Spotlight asked", NO); return; }
    BOOL shown = DMSpotlightShown();
    if (!shown && tries < 10) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMSpotAsked(tries + 1); }); return; }
    DMSpotWriteList(@"Spotlight asked", !shown);
}
static void DMSpotGuardInit(void) {
    Class c = objc_getClass("SPUIRemoteSearchViewController");
    SEL sel = NSSelectorFromString(@"didInvalidateSceneWhenForeground");
    if (!DMMSWHasMethod(c, @"didInvalidateSceneWhenForeground", @"v@:")) { DMLog(@"[spotlight] guard: SpotlightUI's scene-gone call not found (not watched)"); return; }
    MSHookMessageEx(c, sel, (IMP)DMSpotSceneDied, (IMP *)&o_SpotSceneDied);
}
// (%ctor, full runs only: a stock status bar or the switched-off tweak leave the state at 0 -- DMSpotPublishOff -- so Spotlight is untouched)
static void DMSpotInit(void) {
    DMSpotGuardInit();
    static int request = 0, pick = 0;
    if (!request) notify_register_dispatch(DM_SPOT_REQUEST, &request, dispatch_get_main_queue(), ^(int t) { DMSpotAsked(0); });
    if (!pick) notify_register_dispatch(DM_SPOT_PICK, &pick, dispatch_get_main_queue(), ^(int t) { uint64_t st = 0; notify_get_state(t, &st); DMSpotPicked(st); });
#if DEBUG
    static int report = 0;   // (MacSpotlight's debug reports: one number each, see MSPReport there)
    if (!report) notify_register_dispatch(DM_SPOT_REPORT, &report, dispatch_get_main_queue(), ^(int t) {
        uint64_t st = 0; notify_get_state(t, &st);
        DMLog([NSString stringWithFormat:@"[spotlight] Spotlight app reports: kind %llu, value %llu (0x%llx)", st >> 32, st & 0xFFFFFFFFull, st & 0xFFFFFFFFull]);
    });
#endif
}
static void DMSpotPublishOff(void) {   // (a run in which this file does nothing: no switch on for the Spotlight app)
    gSpotActions = gSpotWindows = gSpotTweaks = NO;
    DMSpotPublishState();
}
