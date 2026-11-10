// appbridge/AppMenus.h -- the app's own menus in the menu bar (1.8.5 item 3), the app's side. Included by AppBridge.x (every app).
//
// SpringBoard asks ("com.besiktasliseba.appbridge.menus.<hash>", hash = FNV-1a of the bundle id as everywhere in MacAppBridge); the app looks at
// what it really offers right now and writes it to tmp/msb-menus.plist in its own container (SpringBoard reads it there, as Finder's drops do the
// other way), then posts "com.besiktasliseba.appbridge.menusready.<hash>". A row picked in the bar comes back as
// "com.besiktasliseba.appbridge.menuact.<hash>" with the row in the name's notify state (its key and this process's nonce: AppMenuRules.h
// MSBDAppMenuActState), and the app performs the command with that key it offers now, the way its own shortcut would.
//
// What the app offers: its main menu (UIKit's main menu system, the menus the app builds with UIMenuBuilder -- iPadOS 15 on; Safari's commands are
// only there, its responders list no key commands) and every key command of its responders, from the one typing (or the key window's root view
// controller) up to the app. Only commands that can act are kept: a command whose action no responder of the chain takes is left out; one that
// validates as disabled (-validateCommand:) is kept greyed, as a Mac menu shows it; hidden ones are left out. Which menu each goes in:
// common/AppMenuRules.h. Nothing is changed in the app: the menu is read, a picked command is sent as its own shortcut sends it.
//
// Only with Settings > Status Bar > Show Apps' Own Menus on (off unless switched on). The app can't read our preferences (sandbox): SpringBoard
// publishes the switch as the notify state of "com.besiktasliseba.appbridge.appmenus" (1 on, 2 off; 0, never published, is off), as it does for
// Esc Ends Typing. Off, an ask or a pick does nothing at all: no snapshot, no file, no answer.
#include "../common/AppMenuRules.h"

static BOOL MABMenusOn(void) {
    static int token = 0; uint64_t state = 0;
    if (!token && notify_register_check("com.besiktasliseba.appbridge.appmenus", &token) != NOTIFY_STATUS_OK) token = 0;
    if (token) notify_get_state(token, &state);
    return state == 1;
}

// What the app offers may have changed without a tap (SpringBoard's "touched"): a shortcut from a hardware keyboard (⌘T, ⌘W), Return in a field (a
// page loading), another of its windows made key, one of its windows closed or brought forward from the bar. SpringBoard asks again once these have stopped for
// 1 s, while the app is in front, as for a tap ("com.besiktasliseba.appbridge.menuschanged.<hash>"; only with the switch on; A12Z 18.5, 10 Nov: after
// ⌘T on a keyboard the bar kept View over the empty tab).
static void MABMenusChanged(void) {
    static char name[96]; static CFTimeInterval last = 0;
    if (!MABMenusOn()) return;
    if (!name[0]) {
        NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
        if (!bundle.length) return;
        uint32_t hash = 2166136261u; for (const char *c = bundle.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
        snprintf(name, sizeof name, "com.besiktasliseba.appbridge.menuschanged.%08x", hash);
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.25) return;
    last = now;
    notify_post(name);
}

static NSMutableDictionary<NSNumber *, UICommand *> *gMABMenuCmds;   // (main thread: the last snapshot's commands, by their row's key)
static uint32_t MABMenuNonce(void) {   // (this process's, in every answer: SpringBoard sends it back with a row)
    static uint32_t n = 0;
    while (!n) n = arc4random();
    return n;
}

// The window the app's shortcuts reach now (review 1.8.5 M2: never the first of connectedScenes, a set -- with two windows of the app in front the
// menus could describe one and act in the other): the key window of the scene keyboard events go to, as a hardware keyboard's shortcut would;
// else of the only scene in front; else the app's key window (UIKit's last one made key).
static UIWindow *MABMenuKeyWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL kbTarget = NSSelectorFromString(@"_isTargetOfKeyboardEventDeferringEnvironment");
    UIWindowScene *only = nil; NSUInteger active = 0;
    for (UIScene *sc in app.connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]] || sc.activationState != UISceneActivationStateForegroundActive) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;
        active++; only = ws;
        BOOL target = NO;
        @try { target = [ws respondsToSelector:kbTarget] && ((BOOL (*)(id, SEL))objc_msgSend)(ws, kbTarget); } @catch (id e) { target = NO; }
        if (target) for (UIWindow *w in ws.windows) if (w.isKeyWindow) return w;
    }
    if (active == 1) for (UIWindow *w in only.windows) if (w.isKeyWindow) return w;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return app.keyWindow;
#pragma clang diagnostic pop
}
static __weak UIWindowScene *gMABMenuScene;   // (the scene the last snapshot was of: a row is looked up again in a new one if another is in front now)
// Where the app's commands start: the first responder of the key window (what the app's shortcuts reach); with none, where UIKit itself starts a
// main-menu command in that window (its deepest action responder, then its responder for key events: a new Safari window with nothing focused has no
// first responder, and its root view controller's chain never reaches the BrowserController that takes ⌘T, so every command looked dead -- iPad 2,
// 16.7.7, 10 Nov); else its root view controller.
static UIResponder *MABMenuStart(UIWindow *key) {
    if (!key) return [UIApplication sharedApplication];
    SEL fr = NSSelectorFromString(@"firstResponder");
    UIResponder *r = [key respondsToSelector:fr] ? ((id (*)(id, SEL))objc_msgSend)(key, fr) : nil;
    if ([r isKindOfClass:[UIResponder class]]) return r;
    for (NSString *name in @[@"_deepestActionResponder", @"_responderForKeyEvents"]) {
        SEL s = NSSelectorFromString(name);
        @try { r = [key respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(key, s) : nil; } @catch (id e) { r = nil; }
        if ([r isKindOfClass:[UIResponder class]] && r != (UIResponder *)key) return r;
    }
    UIViewController *vc = key.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc ?: (UIResponder *)key;
}
// The root of the app's main menu as UIKit built it (nil where there is none).
static UIMenu *MABMenuRoot(void) {
    id sys = [UIMenuSystem mainSystem];
    SEL root = NSSelectorFromString(@"_rootMenu"), rebuild = NSSelectorFromString(@"_automaticallyRebuildIfNeeded");
    if (![sys respondsToSelector:root]) return nil;
    @try {
        if ([sys respondsToSelector:rebuild]) ((void (*)(id, SEL))objc_msgSend)(sys, rebuild);
        id m = ((id (*)(id, SEL))objc_msgSend)(sys, root);
        return [m isKindOfClass:[UIMenu class]] ? m : nil;
    } @catch (id e) { return nil; }
}

// One command found: kept with where it was (its top menu's identifier, for AppMenuRules) and the group it was in (a separator between groups).
@interface MABMenuFound : NSObject
@property (nonatomic, strong) UICommand *cmd;
@property (nonatomic, copy) NSString *topID;
@property (nonatomic, assign) NSInteger group;
@end
@implementation MABMenuFound
@end

static void MABMenuWalk(UIMenu *m, NSString *topID, NSInteger *group, NSMutableArray<MABMenuFound *> *out, int depth) {
    if (!m || depth > 8 || out.count > 400) return;
    BOOL inlineGroup = (m.options & UIMenuOptionsDisplayInline) != 0;
    if (depth > 1) (*group)++;   // (each sub-group of a top menu: its own block, set off by a separator, as the app laid it out)
    for (UIMenuElement *e in m.children) {
        if ([e isKindOfClass:[UIMenu class]]) {
            UIMenu *sub = (UIMenu *)e;
            MABMenuWalk(sub, depth == 0 ? sub.identifier : topID, group, out, depth + 1);
            if (depth == 0) (*group)++;
        } else if ([e isKindOfClass:[UICommand class]]) {
            MABMenuFound *f = [MABMenuFound new];
            f.cmd = (UICommand *)e; f.topID = topID; f.group = *group;
            [out addObject:f];
        }
    }
    if (inlineGroup || depth > 1) (*group)++;
}

// Builds the snapshot and writes it (YES: written); the commands are kept, by key, for the rows picked from it.
static BOOL MABMenuSnapshot(void) {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    UIWindow *win = MABMenuKeyWindow();
    UIResponder *start = MABMenuStart(win);
    NSMutableArray<MABMenuFound *> *found = [NSMutableArray array];
    NSInteger group = 0;
    UIMenu *root = MABMenuRoot();
    if (root) MABMenuWalk(root, nil, &group, found, 0);
    group += 1000;   // (the responders' own key commands: after the main menu's, as their own group)
    int depth = 0;   // (at most 64 responders: a nextResponder loop of an app's own must not hang it at every switch -- review L8)
    for (UIResponder *x = start; x && depth < 64; x = x.nextResponder, depth++) {
        NSArray *kc = nil;
        @try { kc = x.keyCommands; } @catch (id e) { kc = nil; }
        for (UIKeyCommand *c in kc) {
            if (![c isKindOfClass:[UIKeyCommand class]]) continue;
            MABMenuFound *f = [MABMenuFound new];
            f.cmd = c; f.topID = nil; f.group = group;
            [found addObject:f];
        }
    }
    NSMutableDictionary<NSString *, NSMutableArray *> *menus = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *lastGroup = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableDictionary<NSNumber *, UICommand *> *cmds = [NSMutableDictionary dictionary];
    int kept = 0, noTarget = 0, hidden = 0, destructive = 0;
    for (MABMenuFound *f in found) {
        UICommand *c = f.cmd;
        SEL action = c.action;
        if (!action) continue;   // (a UIAction: its handler is the app's, there is no action to send -- left out)
        UIKeyCommand *kc = [c isKindOfClass:[UIKeyCommand class]] ? (UIKeyCommand *)c : nil;
        NSString *title = c.title.length ? c.title : (kc.discoverabilityTitle.length ? kc.discoverabilityTitle : c.discoverabilityTitle);
        if (!title.length) continue;   // (a shortcut with no name: the app keeps it to itself, the overlay doesn't list it either)
        // (our Edit menu's own -- Undo, Redo, Cut, Copy, Paste, Select All, Find --, by the title and key they have before they are checked: left out
        //  before the app is asked anything about them. An app's canPerformAction for paste: may read the pasteboard: "Allow Paste?" at a switch -- L5)
        NSString *hint = kc ? MSBDAppMenuHint(kc.input, (long)kc.modifierFlags) : nil;
        if ([MSBDAppMenuFor(bundle, f.topID, NSStringFromSelector(action), title) isEqualToString:kMSBDAppMenuEdit]
            && (MSBDAppMenuOursHas(title) || MSBDAppMenuOursHasHint(hint))) continue;
        id target = nil;
        @try { target = [start targetForAction:action withSender:c]; } @catch (id e) { target = nil; }
        if (!target) { noTarget++; continue; }   // (nothing would act on it now)
        @try { if ([target respondsToSelector:@selector(validateCommand:)]) [target validateCommand:c]; } @catch (id e) {}
        if (c.attributes & UIMenuElementAttributesHidden) { hidden++; continue; }
        title = c.title.length ? c.title : title;
        // (review M4: a destructive command -- the app marks it so, or its title starts Delete, Clear, Erase or Remove -- only as a shortcut of the
        //  app's: our row performs it exactly as that key command does (its action, from the responder typing, the command as sender), so the app's
        //  own confirmation shows if it has one. One with no key, which the app offers only in its menu, could skip what its touch screen asks
        //  first: left out)
        if (((c.attributes & UIMenuElementAttributesDestructive) || MSBDAppMenuDestructive(title)) && !kc.input.length) { destructive++; continue; }
        NSString *dup = [NSString stringWithFormat:@"%@|%@|%@|%ld", title, NSStringFromSelector(action), kc.input ?: @"", (long)kc.modifierFlags];
        if ([seen containsObject:dup]) continue;
        [seen addObject:dup];
        NSNumber *key = @(MSBDAppMenuKey(dup));
        if (cmds[key]) continue;   // (two commands with one key -- never seen, 32 bits --: only the first, so a key names one command)
        NSString *menu = MSBDAppMenuFor(bundle, f.topID, NSStringFromSelector(action), title);
        if (!menu.length) continue;   // (the app-name and Help menus' commands: ours has those, or nothing does here)
        if ([menu isEqualToString:kMSBDAppMenuEdit] && (MSBDAppMenuOursHas(title) || MSBDAppMenuOursHasHint(hint))) continue;   // (already in our Edit menu)
        NSMutableArray *rows = menus[menu];
        if (!rows) { rows = [NSMutableArray array]; menus[menu] = rows; }
        if (rows.count >= kMSBDAppMenuMaxItems) continue;
        if (rows.count && lastGroup[menu] && lastGroup[menu].integerValue != f.group) [rows addObject:@{@"s": @YES}];
        lastGroup[menu] = @(f.group);
        NSMutableDictionary *row = [@{@"t": title, @"x": key, @"e": @(!(c.attributes & UIMenuElementAttributesDisabled))} mutableCopy];
        if (hint.length) row[@"h"] = hint;
        if (c.state == UIMenuElementStateOn) row[@"k"] = @YES;
        [rows addObject:row];
        cmds[key] = c;
        kept++;
    }
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSString *name in MSBDAppMenuOrder()) {
        NSMutableArray *rows = menus[name];
        while ([rows.lastObject objectForKey:@"s"]) [rows removeLastObject];
        if (rows.count) [ordered addObject:@{@"t": name, @"r": rows}];
    }
    gMABMenuCmds = cmds;
    gMABMenuScene = win.windowScene;
    // (n: this process's nonce, sent back with a picked row; p: its pid, so SpringBoard knows an answer from a process that has gone)
    // (partial: no window of the app in front yet -- it is still coming forward --, so SpringBoard asks again a moment later: review M5)
    BOOL partial = !win || win.windowScene.activationState != UISceneActivationStateForegroundActive;
    NSDictionary *snap = @{@"n": @(MABMenuNonce()), @"p": @(getpid()), @"b": bundle ?: @"", @"m": ordered, @"partial": @(partial), @"at": @([[NSDate date] timeIntervalSince1970])};
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"msb-menus.plist"];
    BOOL wrote = [snap writeToFile:path atomically:YES];
#if DEBUG
    MABLog([NSString stringWithFormat:@"appmenus: snapshot: %d kept, %d without a target, %d hidden, %d destructive with no key, %lu found (main menu %@), start %@, menus %@, written %d",
            kept, noTarget, hidden, destructive, (unsigned long)found.count, root ? @"yes" : @"none", NSStringFromClass([start class]),
            [[ordered valueForKey:@"t"] componentsJoinedByString:@","], wrote]);
    if (MSTestFlag("/tmp/macstatusbar-debug")) for (NSDictionary *m in ordered) for (NSDictionary *r in m[@"r"]) if (!r[@"s"])
        MABLog([NSString stringWithFormat:@"appmenus:   %@ > %08x %@%@%@", m[@"t"], [r[@"x"] unsignedIntValue], r[@"h"] ?: @"", [r[@"e"] boolValue] ? @"" : @" (disabled)", r[@"k"] ? @" (on)" : @""]);   // (a row's key, not its title: names in Open Recent, mailboxes -- review L9)
#else
    (void)kept; (void)noTarget; (void)hidden; (void)destructive;
#endif
    return wrote;
}

// A row picked in the bar: the command with its key that the app offers now -- the last snapshot's, else a new one's (a row shown from an older
// snapshot works: the key is what the command is, not where it was) --, sent as the app's own shortcut sends it (to the responder that takes its
// action, the command as sender). Refused: a row of another process (the nonce: the app relaunched, or not SpringBoard), or a command the app
// doesn't offer now.
static void MABMenuPerform(uint64_t state) {
    if (!MABMenusOn()) return;   // (switched off since the row was shown)
    uint32_t key = MSBDAppMenuActKey(state), nonce = MSBDAppMenuActNonce(state);
    BOOL ours = nonce == MABMenuNonce();
    UIWindow *win = MABMenuKeyWindow();
    UICommand *c = ours && win.windowScene == gMABMenuScene ? gMABMenuCmds[@(key)] : nil;   // (another window in front now, or its scene gone: a new snapshot of it)
    if (!c && ours) { MABMenuSnapshot(); c = gMABMenuCmds[@(key)]; }
    if (!c) {
#if DEBUG
        MABLog([NSString stringWithFormat:@"appmenus: row %08x refused (%@)", key, ours ? @"not offered now" : @"not this process's"]);
#endif
        return;
    }
    UIResponder *start = MABMenuStart(win);
    id target = nil;
    @try { target = [start targetForAction:c.action withSender:c]; } @catch (id e) { target = nil; }
    BOOL sent = NO;
    if (target) @try { sent = [[UIApplication sharedApplication] sendAction:c.action to:target from:c forEvent:nil]; } @catch (id e) { sent = NO; }
#if DEBUG
    MABLog([NSString stringWithFormat:@"appmenus: row %08x (%@) sent to %@: %d", key, NSStringFromSelector(c.action), target ? NSStringFromClass([target class]) : @"nobody", sent]);   // (not its title, L9)
#else
    (void)sent;
#endif
    DM_FEATURE_MARK("app-own-menus");
}

static void MABRegisterMenus(void) {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier;
    if (!bundle.length || [bundle isEqualToString:@"com.apple.springboard"]) return;
    uint32_t hash = 2166136261u; for (const char *c = bundle.UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
    static int tokenAsk = 0, tokenAct = 0;
    static char ready[96];
    snprintf(ready, sizeof ready, "com.besiktasliseba.appbridge.menusready.%08x", hash);
    char name[96];
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.menus.%08x", hash);
    notify_register_dispatch(name, &tokenAsk, dispatch_get_main_queue(), ^(int t) {
        if (!MABMenusOn()) return;   // (Show Apps' Own Menus off: no snapshot work at all)
        static CFTimeInterval last = 0;   // (asked again within 0.1 s -- two layouts of the bar --: the snapshot just made is still the answer)
        static BOOL wrote = NO;
        CFTimeInterval now = CACurrentMediaTime();
        if (now - last > 0.1) wrote = MABMenuSnapshot();
        last = now;
        if (wrote) notify_post(ready);   // (not written: no answer -- SpringBoard would read an older one, maybe another process's)
    });
    snprintf(name, sizeof name, "com.besiktasliseba.appbridge.menuact.%08x", hash);
    notify_register_dispatch(name, &tokenAct, dispatch_get_main_queue(), ^(int t) {
        uint64_t st = 0;
        if (notify_get_state(t, &st) == NOTIFY_STATUS_OK) MABMenuPerform(st);
    });
    // (another of its windows key, or one of its windows closed, sent away or brought back: each scene keeps its own key window, so closing one of
    //  two Safari windows from the bar made no window key -- its scene went to the background and disconnected; A12Z 18.5, m05)
    for (NSNotificationName nn in @[UIWindowDidBecomeKeyNotification, UISceneDidActivateNotification, UISceneDidEnterBackgroundNotification, UISceneDidDisconnectNotification])
        [[NSNotificationCenter defaultCenter] addObserverForName:nn object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { MABMenusChanged(); }];
}
