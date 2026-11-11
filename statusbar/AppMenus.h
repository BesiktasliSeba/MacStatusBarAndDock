// statusbar/AppMenus.h -- the app's own menus in the menu bar (1.8.5 item 3), SpringBoard's side. Included by StatusBar.x after Finder.h.
//
// With an app in front, the bar shows that app's own menus as on a Mac: File before our Edit, then Format, View, History, Bookmarks, Tabs and
// Actions -- each only when the app really has commands for it -- before our Go and Window. The app says what it has (appbridge/AppMenus.h: its
// main menu and its responders' key commands, only those that can act now, sorted by common/AppMenuRules.h); its Edit commands that our Edit menu
// doesn't have already are added under ours. A row picked is sent back to the app, which performs that command as its own shortcut would, so the
// menus work without a hardware keyboard. Every engine (the app in front is the bar's app, windowed or full screen); our Finder window keeps its
// own File, Edit and View.
//
// When the app is asked: when it comes to the front (DMAMFrontSeen, from the bar's layout), after a row of it is picked, and again when one
// of its titles is opened (the menu then shows the fresh answer, or the last one if the app is slow to answer, after 0.3 s). The titles fit in
// the room our own titles leave: ours (Go, Window, Audio) are laid out first, and an app title that doesn't fit whole is left out, last ones first
// (DMAMFitTitles) -- the bar never gets more crowded than the room it has.
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
        notify_register_dispatch(touched, &tapToken, dispatch_get_main_queue(), ^(int t) { if (gAMOn && [[DMActiveApp() bundleIdentifier] isEqualToString:b]) DMAMAskSoon(b, 1.0); });
        // (... and a shortcut from a keyboard, Return, another of its windows made key: MacAppBridge's "menuschanged", the same way)
        char changed[96]; snprintf(changed, sizeof changed, "com.besiktasliseba.appbridge.menuschanged.%08x", h);
        int changedToken = 0;
        notify_register_dispatch(changed, &changedToken, dispatch_get_main_queue(), ^(int t) { if (gAMOn && [[DMActiveApp() bundleIdentifier] isEqualToString:b]) DMAMAskSoon(b, 1.0); });
    }
    char name[96]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.menus.%08x", h);
    notify_post(name);
}
// Asked again a moment from now (a tap in the app, a row picked, a thin answer), once nothing else has asked for that in the meantime, and only
// while it is still the app in front (review M5: before, the titles stayed as the first answer had them while the app stayed in front).
static void DMAMAskSoon(NSString *bundle, double delay) {
    static NSUInteger seq = 0;
    NSUInteger mine = ++seq;
    NSString *b = [bundle copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (mine != seq || !gAMOn || ![[DMActiveApp() bundleIdentifier] isEqualToString:b]) return;
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
static void DMAMFrontSeen(SBApplication *app) {
    static NSString *last;
    NSString *bundle = [app bundleIdentifier];
    if (!bundle.length) { last = nil; return; }
    if (![bundle isEqualToString:last]) { last = [bundle copy]; DMAMAsk(bundle, YES); return; }
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
    NSString *bundle = [DMActiveApp() bundleIdentifier];
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
// whose ask and pick handlers do nothing with it off; off, what the apps answered is forgotten.
static void DMAMApplyPref(BOOL on) {
    static int token = 0; static uint64_t published = 0;   // (the token is kept: notifyd forgets a name's state once nobody holds it)
    if (!token && notify_register_check(kDMAMSwitchName, &token) != NOTIFY_STATUS_OK) token = 0;
    uint64_t want = on ? 1 : 2;
    if (token && want != published) { notify_set_state(token, want); published = want; }
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
