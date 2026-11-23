// statusbar/AppMenus.h -- the app's own menus in the menu bar (1.8.5 item 3), SpringBoard's side. Included by StatusBar.x after Finder.h.
//
// With an app in front, the bar shows that app's own menus as on a Mac: File before our Edit, then Format, View, History, Bookmarks, Tabs and
// Actions -- each only when the app really has commands for it -- before our Go and Window. The app says what it has (appbridge/AppMenus.h: its
// main menu and its responders' key commands, only those that can act now, sorted by common/AppMenuRules.h); its Edit commands that our Edit menu
// doesn't have already are added under ours. A row picked is sent back to the app, which performs that command as its own shortcut would, so the
// menus work without a hardware keyboard. Every engine (the app in front is the bar's app, windowed or full screen); our Finder window keeps its
// own File, Edit and View.
//
// When the app is asked: when it comes to the front (DMAMFrontSeen, from the bar's layout), when MacAppBridge has just started in the app in front
// (its "menushere": the ask sent at a cold launch comes before it can hear it, B12), after a row of it is picked, a second after a tap in it or
// its "menuschanged" (a shortcut, another window made key, what it offers moving with no tap: B12's thin first answer; never while one of our
// menus, dialogs, questions or panels is open: gOverlay), and again when one of its titles is opened (the menu then shows the fresh answer, or the
// last one if the app is slow to answer, after 0.3 s). The titles fit in the room our own titles leave: ours (Go, Window, Audio) are laid out
// first, and an app title that doesn't fit whole is left out, last ones first (DMAMFitTitles) -- the bar never gets more crowded than the room it
// has. While one of our menus or panels is open, the bar keeps the app's titles it shows and lays out what came meanwhile once it is closed
// (DMAMTitlesToLay: no title moves under it, F-7); so it does while a finger is on one of its titles, until it lifts (F-7b).
//
// Settings > Status Bar > Show Apps' Own Menus, on unless switched off (1.8.6; gAMOn, DMAMApplyPref): off, no app is asked, no title shows, nothing is
// added under our Edit menu's Find, and MacAppBridge makes no snapshot in any app -- the bar is as it was before the feature.
#include <notify.h>
#include <sys/stat.h>

static BOOL gAMOn = YES;                                              // Show Apps' Own Menus (DMAMApplyPref, from DMLoadPrefs; on unless switched off)
#define kDMAMSwitchName "com.besiktasliseba.appbridge.appmenus"        // (published for MacAppBridge in every app: 1 on, 2 off; never published is on)
static NSMutableDictionary<NSString *, NSDictionary *> *gAMSnap;      // bundle -> the app's last answer (tmp/msb-menus.plist in its container)
static NSMutableDictionary<NSString *, NSNumber *> *gAMAskedAt;       // bundle -> when it was last asked (CACurrentMediaTime)
static NSMutableDictionary<NSString *, NSNumber *> *gAMReadyTokens;   // bundle -> its "menusready" registration (kept: one per app)
static NSMutableDictionary<NSString *, NSNumber *> *gAMFailedAt;      // bundle -> when its answer last couldn't be read (asked again after 30 s)
static NSMutableDictionary<NSString *, NSString *> *gAMContainer;     // bundle -> its data container's path (looked up again after a failed read)
static NSString *gAMPendingBundle;                                     // a title was opened: its menu waits for this app's fresh answer
static dispatch_block_t gAMPendingOpen;
// (1.8.8.2, B69: each display's bar names its own display's front, so the app a bar shows the menus of may not be the active one. The app each display's
//  bar last laid out -- 0 the iPad's bars, 1 another display's: DMAMFrontSeenOn --; an app on a bar is "in front" for the asks below, as the active app
//  is, so a bar's app that isn't the active one still gets its menus asked again after its "menushere", its thin first answer or its "menuschanged"
//  (B69 review: B12's late titles again on the other display's bar). The iPad alone: the active app only, as before)
static NSString *gAMBarLast[2];
static BOOL DMAMInFront(NSString *b) {
    if ([[DMActiveApp() bundleIdentifier] isEqualToString:b]) return YES;
    return b.length && DMBarFrontTV() && ([gAMBarLast[0] isEqualToString:b] || [gAMBarLast[1] isEqualToString:b]);
}

static uint32_t DMAMHash(NSString *b) { uint32_t h = 2166136261u; for (const char *c = b.UTF8String; *c; c++) { h ^= (uint8_t)*c; h *= 16777619u; } return h; }
static NSArray<NSString *> *DMAMTitlesIn(NSDictionary *snap) {
    NSMutableArray *t = [NSMutableArray array];
    for (NSDictionary *m in snap[@"m"]) if ([m isKindOfClass:[NSDictionary class]] && [m[@"t"] isKindOfClass:[NSString class]]) [t addObject:m[@"t"]];
    return t;
}
// The app's answer as SpringBoard keeps it (review L1: any app can write its own file and post its own "menusready"): every field of the type it
// must be, only our menus' titles (MSBDAppMenuOrder, each once), at most kMSBDAppMenuMaxItems rows each. nil: not an answer from this app.
static NSDictionary *DMAMClean(NSDictionary *d, NSString *bundle) {
    if (![d isKindOfClass:[NSDictionary class]] || ![d[@"b"] isEqual:bundle] || ![d[@"m"] isKindOfClass:[NSArray class]]
        || ![d[@"n"] isKindOfClass:[NSNumber class]] || ![d[@"p"] isKindOfClass:[NSNumber class]]) return nil;   // (n: the process's nonce, p: its pid)
    NSArray<NSString *> *known = MSBDAppMenuOrder();
    NSMutableArray *menus = [NSMutableArray array];
    NSMutableSet<NSString *> *titles = [NSMutableSet set];
    for (NSDictionary *m in d[@"m"]) {
        if (![m isKindOfClass:[NSDictionary class]] || ![m[@"t"] isKindOfClass:[NSString class]] || ![m[@"r"] isKindOfClass:[NSArray class]]) continue;
        if (![known containsObject:m[@"t"]] || [titles containsObject:m[@"t"]]) continue;
        [titles addObject:m[@"t"]];
        NSMutableArray *rows = [NSMutableArray array];
        NSUInteger n = 0;
        for (NSDictionary *r in m[@"r"]) {
            if (![r isKindOfClass:[NSDictionary class]]) continue;
            if (r[@"s"]) { [rows addObject:@{@"s": @YES}]; continue; }
            if (![r[@"t"] isKindOfClass:[NSString class]] || ![(NSString *)r[@"t"] length] || ![r[@"x"] isKindOfClass:[NSNumber class]]) continue;
            if (n++ >= kMSBDAppMenuMaxItems) break;
            NSMutableDictionary *row = [@{@"t": r[@"t"], @"x": r[@"x"], @"e": @([r[@"e"] isKindOfClass:[NSNumber class]] && [r[@"e"] boolValue])} mutableCopy];
            if ([r[@"h"] isKindOfClass:[NSString class]]) row[@"h"] = r[@"h"];
            if ([r[@"k"] isKindOfClass:[NSNumber class]] && [r[@"k"] boolValue]) row[@"k"] = @YES;
            [rows addObject:row];
        }
        if (n) [menus addObject:@{@"t": m[@"t"], @"r": rows}];
    }
    return @{@"b": bundle, @"m": menus, @"n": d[@"n"], @"p": d[@"p"], @"partial": @([d[@"partial"] isKindOfClass:[NSNumber class]] && [d[@"partial"] boolValue])};
}
static void DMAMAskSoon(NSString *bundle, double delay);   // (below)
static void DMAMRead(NSString *bundle) {
    if (!gAMOn) return;   // (an answer that comes in after the switch went off)
    // (review L4: the container's path is looked up once per app -- LaunchServices, maybe containermanagerd --, and again after a read that fails:
    //  a reinstalled app has a new one. The file is read only up to 256 KB: an answer is 10-40 KB, and this runs on SpringBoard's main thread)
    if (!gAMContainer) gAMContainer = [NSMutableDictionary dictionary];
    NSString *dir = gAMContainer[bundle];
    if (!dir.length) { dir = DMFDContainer(bundle).path; if (dir.length) gAMContainer[bundle] = dir; }
    NSString *path = dir.length ? [dir stringByAppendingPathComponent:@"tmp/msb-menus.plist"] : nil;
    struct stat st;
    BOOL sizeOK = path && stat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 0 && st.st_size <= 256 * 1024;
    NSDictionary *d = sizeOK ? DMAMClean([NSDictionary dictionaryWithContentsOfFile:path], bundle) : nil;
    if (!d) {
        DMLog([NSString stringWithFormat:@"[appmenus] %@: no answer to read (%@)", bundle, !dir.length ? @"no data container" : sizeOK ? @"not its own" : @"no file, or too big"]);
        [gAMContainer removeObjectForKey:bundle];
        if (!gAMFailedAt) gAMFailedAt = [NSMutableDictionary dictionary];
        gAMFailedAt[bundle] = @(CACurrentMediaTime());   // (DMAMFrontSeen asks again only after 30 s, not at every layout)
    } else {
        [gAMFailedAt removeObjectForKey:bundle];
        if (!gAMSnap) gAMSnap = [NSMutableDictionary dictionary];
        BOOL changed = ![DMAMTitlesIn(gAMSnap[bundle]) isEqualToArray:DMAMTitlesIn(d)];
        gAMSnap[bundle] = d;
        if (changed) {
            DMLog([NSString stringWithFormat:@"[appmenus] %@: menus %@", bundle, [DMAMTitlesIn(d) componentsJoinedByString:@", "] ?: @"none"]);
            for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
        }
        // (a thin answer, taken while the app was still coming forward: asked again in 1 s, at most 3 times in a row -- review M5)
        static NSMutableDictionary<NSString *, NSNumber *> *partialTries;
        if (!partialTries) partialTries = [NSMutableDictionary dictionary];
        if ([d[@"partial"] boolValue]) {
            NSUInteger n = partialTries[bundle].unsignedIntegerValue + 1;
            partialTries[bundle] = @(n);
            if (n <= 3) DMAMAskSoon(bundle, 1.0);
        } else [partialTries removeObjectForKey:bundle];
    }
    if (gAMPendingOpen && [gAMPendingBundle isEqualToString:bundle]) { dispatch_block_t b = gAMPendingOpen; gAMPendingOpen = nil; gAMPendingBundle = nil; b(); }
}
// Asks the app what it offers now (force: whatever the time since the last ask).
static void DMAMAsk(NSString *bundle, BOOL force) {
    if (!gAMOn || !bundle.length) return;
    if (!gAMAskedAt) { gAMAskedAt = [NSMutableDictionary dictionary]; gAMReadyTokens = [NSMutableDictionary dictionary]; }
    CFTimeInterval now = CACurrentMediaTime();
    if (!force && gAMAskedAt[bundle] && now - gAMAskedAt[bundle].doubleValue < 2.0) return;
    gAMAskedAt[bundle] = @(now);
    uint32_t h = DMAMHash(bundle);
    if (!gAMReadyTokens[bundle]) {
        char ready[96]; snprintf(ready, sizeof ready, "com.besiktasliseba.appbridge.menusready.%08x", h);
        int token = 0; NSString *b = [bundle copy];
        if (notify_register_dispatch(ready, &token, dispatch_get_main_queue(), ^(int t) { DMAMRead(b); }) == NOTIFY_STATUS_OK) gAMReadyTokens[bundle] = @(token);
        // (a tap in the app -- MacAppBridge posts "touched" for every one --: what it offers may have changed with it, a page loaded, a field focused,
        //  another of its windows forward; asked again once its taps have stopped for 1 s, while it is the app in front -- review M5)
        char touched[96]; snprintf(touched, sizeof touched, "com.besiktasliseba.appbridge.touched.%08x", h);
        int tapToken = 0;
        notify_register_dispatch(touched, &tapToken, dispatch_get_main_queue(), ^(int t) { if (gAMOn && DMAMInFront(b)) DMAMAskSoon(b, 1.0); });
        // (... and a shortcut from a keyboard, Return, another of its windows made key: MacAppBridge's "menuschanged", the same way)
        char changed[96]; snprintf(changed, sizeof changed, "com.besiktasliseba.appbridge.menuschanged.%08x", h);
        int changedToken = 0;
        notify_register_dispatch(changed, &changedToken, dispatch_get_main_queue(), ^(int t) { if (gAMOn && DMAMInFront(b)) DMAMAskSoon(b, 1.0); });
        // (... and MacAppBridge has just registered in it (its "menushere", once per process): an ask sent before that was lost -- at a cold launch
        //  the one sent when it came to the front always is (B12: Reynard, Maps, Clock on the M1, 20 Nov; the titles waited up to a minute) --, so it
        //  is asked again at once, while it is the app in front)
        char here[96]; snprintf(here, sizeof here, "com.besiktasliseba.appbridge.menushere.%08x", h);
        int hereToken = 0;
        notify_register_dispatch(here, &hereToken, dispatch_get_main_queue(), ^(int t) { if (gAMOn && DMAMInFront(b)) DMAMAsk(b, YES); });
    }
    char name[96]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.menus.%08x", h);
    notify_post(name);
}
// Asked again a moment from now (a tap in the app, a row picked, a thin answer), once nothing else has asked for that in the meantime, and only
// while it is still the app in front (review M5: before, the titles stayed as the first answer had them while the app stayed in front). Not while
// one of our menus, dialogs, questions or panels is open (gOverlay; B12: the app says what it offers moved with no tap now, Maps' home card filling
// in): the bar keeps its titles under it anyway (DMAMTitlesToLay, F-7), so what moved meanwhile is asked once, at most a second after it is closed.
static void DMAMAskSoon(NSString *bundle, double delay) {
    static NSUInteger seq = 0;
    NSUInteger mine = ++seq;
    NSString *b = [bundle copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != seq || !gAMOn || !DMAMInFront(b)) return;
        if (gOverlay) { DMAMAskSoon(b, 1.0); return; }
        DMAMAsk(b, YES);
    });
}
static int DMAMPid(SBApplication *app) {   // (the app's process now; 0: none, or not known)
    id ps = [app respondsToSelector:NSSelectorFromString(@"processState")] ? DMCall(app, @"processState") : nil;
    SEL pid = NSSelectorFromString(@"pid");
    return [ps respondsToSelector:pid] ? ((int (*)(id, SEL))objc_msgSend)(ps, pid) : 0;
}
// The bar's layout saw this app in front (nil: none -- the Home Screen, our Finder window --, so the same app coming back is asked again): asked
// when it is a new one in front, else only while no answer from its process is in (at most every 2 s). An answer from a process that has gone
// (the app was relaunched: its titles may differ) is dropped. The layout runs often; the app is not asked again for each one.
// (1.8.8.2, B69 E: each display's bar names its own display's front, so each has its own "last" -- display 0 the iPad's bars, 1 another display's;
//  with one "last", two bars with two apps asked both apps again at every layout)
static void DMAMFrontSeenOn(SBApplication *app, int display) {
    NSString * __strong *last = &gAMBarLast[display ? 1 : 0];
    NSString *bundle = [app bundleIdentifier];
    if (!bundle.length) { *last = nil; return; }
    if (![bundle isEqualToString:*last]) { *last = [bundle copy]; DMAMAsk(bundle, YES); return; }
    int pid = DMAMPid(app);
    if (gAMSnap[bundle] && pid > 0 && [gAMSnap[bundle][@"p"] intValue] != pid) {
        DMLog([NSString stringWithFormat:@"[appmenus] %@: its answer was from a process that has gone", bundle]);
        [gAMSnap removeObjectForKey:bundle];
        for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
    }
    if (gAMSnap[bundle]) return;
    NSNumber *failed = gAMFailedAt[bundle];   // (an answer it couldn't read -- an app with no data container of its own --: not every 2 s, review L4)
    if (failed && CACurrentMediaTime() - failed.doubleValue < 30.0) return;
    DMAMAsk(bundle, NO);
}
// The titles of the app's own menus the bar can show (Edit is ours: its rows go in our Edit menu).
static NSArray<NSString *> *DMAMTitles(NSString *bundle) {
    NSMutableArray *t = [NSMutableArray array];
    for (NSString *s in DMAMTitlesIn(gAMSnap[bundle])) if (![s isEqualToString:kMSBDAppMenuEdit] && t.count < kMSBDAppMenuSlots) [t addObject:s];
    return t;
}
// The titles a copy of the bar lays out for the app in front (bundle; nil: none, or Show Apps' Own Menus off). While one of our menus or panels
// is open on its screen they stay as that copy laid them out last with nothing of ours open, none for an app it hadn't laid out then (F-7, p08's
// rows on the 17.5, 20 Nov: Go opened in the first second of Maps' cold launch; the first answer, asked by Maps' word, laid File and View in under
// it, so Go and its highlight moved ~97 pt right while its menu hung where it was, and the closing tap opened Edit). Every answer still comes in
// (gAMSnap: the next menu's rows, our Edit's extras); only what the bar shows waits, whatever brought it (the app's word, a title's late answer,
// the minute's layout, a move asked for, a process gone, another app in front), until the last of ours is gone (DMAMOverlayGone). A menu on the
// TV holds only the TV's bars, and one on the iPad only the iPad's: the other screen stays in use beside it (DMSMOurMenuOpenOn's rule).
static const void *kAMLaidKey = &kAMLaidKey;   // (per copy: @[bundle, titles] as laid out with nothing of ours open)
static BOOL gAMHeld;                           // (a copy kept its titles under one of ours or a finger: laid out again once it is gone or lifts)
// A copy also keeps them while one of its titles is under a finger (UIKit tracks the touch on its button: the app's name, the app's own titles,
// ours). A layout then moved the button from under the finger, UIKit ended the touch outside it, and the tap opened nothing (F-7b, p08's device
// rows, 20 Nov: a tap on Go 23 ms before Maps' first answer re-laid the bar). The end of every title's touch, lifted inside or outside it or
// taken by a system gesture, lays the bar out again (DMAMTitleTouchEnded, from each title's button: DMLayoutTitle).
static const void *kAMTitleButtonsKey = &kAMTitleButtonsKey;   // (per copy: its titles' buttons, weak, added by DMLayoutTitle as it makes them)
static BOOL DMAMTitleTouched(UIView *fg) {
    for (UIControl *b in (NSHashTable *)objc_getAssociatedObject(fg, kAMTitleButtonsKey)) if (b.tracking) return YES;
    return NO;
}
// (noinline: a function of its own in a release build too, so the crash map has it under the AppMenus.h rule, Show Apps' Own Menus; -Os put it
//  inside the bar's layout, whose crash is Stock status bar mode's)
__attribute__((noinline)) static NSArray<NSString *> *DMAMTitlesToLay(UIView *fg, NSString *bundle) {
    NSArray<NSString *> *want = bundle.length ? DMAMTitles(bundle) : @[];
    NSArray *laid = objc_getAssociatedObject(fg, kAMLaidKey);
    UIScreen *ms = [UIScreen mainScreen];
    BOOL menu = gOverlay && (fg.window.screen ?: ms) == (gOverlay.window.screen ?: ms);   // (one of ours open on its screen)
    if (!menu && !(bundle.length && DMAMTitleTouched(fg))) {
        if (!bundle.length) { if (laid) objc_setAssociatedObject(fg, kAMLaidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        else if (![laid[0] isEqual:bundle] || ![laid[1] isEqual:want]) objc_setAssociatedObject(fg, kAMLaidKey, @[[bundle copy], want], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return want;
    }
    NSArray<NSString *> *held = bundle.length && [laid[0] isEqual:bundle] ? laid[1] : @[];
    if (!gAMHeld && ![held isEqualToArray:want]) {
        gAMHeld = YES;
        DMLog([NSString stringWithFormat:menu ? @"[appmenus] %@: menus %@ wait for our menu or panel to close (the bar keeps %@)"
                                              : @"[appmenus] %@: menus %@ wait for the finger on a title to lift (the bar keeps %@)", bundle,
               want.count ? [want componentsJoinedByString:@", "] : @"none", held.count ? [held componentsJoinedByString:@", "] : @"none"]);
    }
    return held;
}
// The touch on one of the bar's titles ended (any copy's): a copy that kept its titles for it is laid out again, a turn later, once UIKit no longer
// tracks it (its actions run inside that touch's end). What the tap opened is open by then, and keeps them still until it closes.
// (noinline: called from the titles' buttons in StatusBar.x; its own crash-map place, Show Apps' Own Menus, as DMAMTitlesToLay's)
__attribute__((noinline)) static void DMAMTitleTouchEnded(void) {
    if (!gAMHeld) return;   // (nothing waited)
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gAMHeld) return;
        gAMHeld = NO;
        DMLog(@"[appmenus] the finger on a title lifted: the bar is laid out again with the menus that waited");
        for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
    });
}
// One of our menus or panels went (closed, or removed at once for the next one: DMCloseOverlay, DMRemoveOverlayNow): a copy that kept its titles
// under it is laid out again. Removed for the next menu (a switch from one title to another), that layout comes after the next one is open and
// keeps them still; once the last is gone it shows what came meanwhile.
static void DMAMOverlayGone(void) {
    if (!gAMHeld) return;
    gAMHeld = NO;
    DMLog(@"[appmenus] our menu or panel is gone: the bar is laid out again with the menus that waited");
    for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
}
static void DMAMPerform(NSString *bundle, uint32_t nonce, uint32_t key) {
    static NSMutableDictionary<NSString *, NSNumber *> *tokens;   // (kept: notifyd forgets a name's state once nobody holds it)
    if (!tokens) tokens = [NSMutableDictionary dictionary];
    uint32_t h = DMAMHash(bundle);
    char name[96]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.menuact.%08x", h);
    int token = tokens[bundle].intValue;
    if (!tokens[bundle]) { if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return; tokens[bundle] = @(token); }
    notify_set_state(token, MSBDAppMenuActState(key, nonce));
    notify_post(name);
}
// The rows of one of the app's menus, from its last answer; a row picked is performed by the app.
static NSArray *DMAMRows(NSString *bundle, NSString *menu) {
    NSDictionary *snap = gAMSnap[bundle];
    uint32_t nonce = [snap[@"n"] unsignedIntValue];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *m in snap[@"m"]) {
        if (![m isKindOfClass:[NSDictionary class]] || ![m[@"t"] isEqual:menu]) continue;
        for (NSDictionary *r in m[@"r"]) {
            if (![r isKindOfClass:[NSDictionary class]]) continue;
            if (r[@"s"]) { if (items.count && items.lastObject != [NSNull null]) [items addObject:[NSNull null]]; continue; }
            NSString *title = [r[@"t"] isKindOfClass:[NSString class]] ? r[@"t"] : nil;
            if (!title.length) continue;
            uint32_t key = [r[@"x"] unsignedIntValue];   // (what the command is: the app finds it in what it offers when the row is picked)
            NSString *b = [bundle copy];
            DMRow *row = [[DMRow alloc] initWithTitle:title enabled:[r[@"e"] boolValue] handler:DMCloseThen(^{
                DMLog([NSString stringWithFormat:@"[appmenus] %@ > row %08x picked: sent to %@", menu, key, b]);   // (its key, not its title: user content, review L9)
                DMAMPerform(b, nonce, key);
                DMAMAsk(b, YES);   // (what it offers may change with it: Show/Hide, Back)
                DMAMAskSoon(b, 0.8);   // (... and once what it started has settled: a new tab, its address field focused -- review M5)
            })];
            if ([r[@"h"] isKindOfClass:[NSString class]]) row.hint = r[@"h"];
            row.checked = [r[@"k"] boolValue];
            [items addObject:row];
        }
    }
    while (items.lastObject == [NSNull null]) [items removeLastObject];
    return items;
}

// The slots' titles as laid out for this copy (slot i -> the menu's title).
static const void *kAMShownKey = &kAMShownKey;
static void DMAMHideSlots(UIView *fg, NSUInteger from) {
    for (NSUInteger i = from; i < kMSBDAppMenuSlots; i++) {
        ((UIView *)objc_getAssociatedObject(fg, &gAMLabelKeys[i])).hidden = YES;
        ((UIView *)objc_getAssociatedObject(fg, &gAMButtonKeys[i])).hidden = YES;
        ((UIView *)objc_getAssociatedObject(fg, &gAMPillKeys[i])).hidden = YES;
    }
}
static NSInteger DMAMSlotOf(UIButton *b) {
    UIView *fg = b.superview;
    if (!fg) return -1;
    for (NSInteger i = 0; i < kMSBDAppMenuSlots; i++) if (b == objc_getAssociatedObject(fg, &gAMButtonKeys[i])) return i;
    return -1;
}
static void DMOpenAppOwnMenu(UIButton *btn) {
    if (DMTitleTapWithMenuOpen(btn)) return;
    UIView *fg = btn.superview;
    NSInteger slot = DMAMSlotOf(btn);
    NSArray<NSString *> *shown = objc_getAssociatedObject(fg, kAMShownKey);
    if (slot < 0 || slot >= (NSInteger)shown.count) return;
    NSString *menu = shown[slot];
    NSString *barKey = nil; BOOL otherBar = NO;   // (B69: the app of this bar's own display -- its own menus; the iPad alone: the active app, as before)
    SBApplication *barApp = DMExternalScreenOf(btn) || DMBarFrontTV() ? DMBarFrontOfTitle(btn, &barKey, &otherBar) : nil;
    NSString *bundle = [(otherBar ? barApp : DMActiveApp()) bundleIdentifier];
    if (!bundle.length || !gAMOn) return;
    __weak UIView *weakFg = fg;
    dispatch_block_t open = ^{
        UIView *f = weakFg;
        if (!f || gOverlay) return;   // (gone meanwhile, or another menu opened)
        // (the fresh answer may have changed the titles -- History before Tabs now --: laid out first, the menu hangs under the slot that shows its
        //  title now; gone, it doesn't open. Before, it opened under the slot tapped, which the next layout renamed -- review L6)
        [f layoutIfNeeded];
        NSUInteger i = [(NSArray *)objc_getAssociatedObject(f, kAMShownKey) indexOfObject:menu];
        UIButton *b = i < kMSBDAppMenuSlots ? objc_getAssociatedObject(f, &gAMButtonKeys[i]) : nil;   // (NSNotFound: not shown)
        if ((!b || b.hidden) && DMStripReveal(f, menu)) {   // (put past the titles the scrolling strip shows: it moves to show it, 1.8.8.2 MenuStrip.h)
            i = [(NSArray *)objc_getAssociatedObject(f, kAMShownKey) indexOfObject:menu];
            b = i < kMSBDAppMenuSlots ? objc_getAssociatedObject(f, &gAMButtonKeys[i]) : nil;
        }
        if (!b || b.hidden) { DMLog([NSString stringWithFormat:@"[appmenus] %@ menu of %@ not shown any more: not opened", menu, bundle]); return; }
        NSArray *items = DMAMRows(bundle, menu);
        if (!items.count) items = @[[[DMRow alloc] initWithTitle:@"Nothing here right now" enabled:NO handler:nil]];
        DMPresentMenu(b, &gAMLabelKeys[i], &gAMPillKeys[i], items);
        DMLog([NSString stringWithFormat:@"[appmenus] %@ menu of %@ opened (%lu rows)", menu, bundle, (unsigned long)items.count]);
    };
    gAMPendingBundle = [bundle copy]; gAMPendingOpen = [open copy];
    DMAMAsk(bundle, YES);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!gAMPendingOpen || ![gAMPendingBundle isEqualToString:bundle]) return;
        dispatch_block_t b = gAMPendingOpen; gAMPendingOpen = nil; gAMPendingBundle = nil;
        DMLog([NSString stringWithFormat:@"[appmenus] %@ didn't answer in 0.3 s: its last answer is shown", bundle]);
        b();
    });
}
// The app's Edit commands our Edit menu doesn't have, for under ours (none: an empty list).
static NSArray *DMAMEditExtras(NSString *bundle) { return gAMOn && bundle.length ? DMAMRows(bundle, kMSBDAppMenuEdit) : @[]; }

// Show Apps' Own Menus set (DMLoadPrefs: at the start, and after each change in Settings, which lays the bar out again): published for MacAppBridge,
// whose ask and pick handlers do nothing with it off; off, what the apps answered is forgotten. Posted too, at every change (and at SpringBoard's
// start): the apps read the state again only after a post (appbridge/AppMenus.h MABMenusOn).
// (noinline: a function of its own in a release build, so the crash map has it under the AppMenus.h rule, Show Apps' Own Menus; -Os put it inside
//  StatusBar.x's DMLoadPrefs, whose section is Clock Opens Today's)
__attribute__((noinline)) static void DMAMApplyPref(BOOL on) {
    static int token = 0; static uint64_t published = 0;   // (the token is kept: notifyd forgets a name's state once nobody holds it)
    if (!token && notify_register_check(kDMAMSwitchName, &token) != NOTIFY_STATUS_OK) token = 0;
    uint64_t want = on ? 1 : 2;
    if (token && want != published) { notify_set_state(token, want); notify_post(kDMAMSwitchName); published = want; }
    if (on == gAMOn) return;
    gAMOn = on;
    DMLog([NSString stringWithFormat:@"[appmenus] Show Apps' Own Menus %@", on ? @"on" : @"off"]);
    if (!on) { [gAMSnap removeAllObjects]; [gAMAskedAt removeAllObjects]; gAMPendingOpen = nil; gAMPendingBundle = nil; }
}

// The width a title takes in the bar (as DMLayoutTitle lays it out: the regular weight, the bar's font size). Measured once per size and text
// (review L3: the layout runs many times while an app opens or closes -- DMLayoutTitle keeps its sizes for the same reason, S-5).
static CGFloat DMAMTitleWidth(NSString *text, UIFont *baseFont) {
    static NSMutableDictionary<NSString *, NSNumber *> *widths;
    if (!widths) widths = [NSMutableDictionary dictionary];
    NSString *k = [NSString stringWithFormat:@"%.2f|%@", baseFont.pointSize, text ?: @""];
    NSNumber *w = widths[k];
    if (!w) {
        UIFont *f = [UIFont systemFontOfSize:baseFont.pointSize weight:UIFontWeightRegular];
        w = @(ceil([text ?: @"" sizeWithAttributes:@{NSFontAttributeName: f ?: baseFont}].width));
        if (widths.count >= 64) [widths removeAllObjects];   // (our titles and the app menus' few, at three sizes: never near this)
        widths[k] = w;
    }
    return w.doubleValue;
}
