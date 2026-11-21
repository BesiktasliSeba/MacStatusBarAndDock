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
// Only with Settings > Status Bar > Show Apps' Own Menus on (on unless switched off, 1.8.6). The app can't read our preferences (sandbox): SpringBoard
// publishes the switch as the notify state of "com.besiktasliseba.appbridge.appmenus" (1 on, 2 off; 0, never published, is on), as it does for
// Esc Ends Typing. Off, an ask or a pick does nothing at all: no snapshot, no file, no answer.
#include "../common/AppMenuRules.h"

// (SpringBoard posts the name each time it publishes it, so the state is read again only after a post: notify_check looks at notifyd's shared
//  memory, where notify_get_state is a round trip to notifyd -- ~70 us, which every look made, at most once a second per answered app in front
//  while it is busy: the B12 review fixes' review, note 3)
static BOOL MABMenusOn(void) {
    static int token = 0; static uint64_t state = 0;
    int moved = 1;   // (the first read, and whenever the check cannot tell)
    if (!token) { if (notify_register_check("com.besiktasliseba.appbridge.appmenus", &token) != NOTIFY_STATUS_OK) token = 0; }
    else if (notify_check(token, &moved) != NOTIFY_STATUS_OK) moved = 1;
    if (token && moved) notify_get_state(token, &state);
    return state != 2;   // (only a published off is off: the switch's default is on)
}

// What the app offers may have changed without a tap (SpringBoard's "touched"): a shortcut from a hardware keyboard (⌘T, ⌘W), Return in a field (a
// page loading), another of its windows made key, one of its windows closed or brought forward from the bar. SpringBoard asks again once these have stopped for
// 1 s, while the app is in front, as for a tap ("com.besiktasliseba.appbridge.menuschanged.<hash>"; only with the switch on; A12Z 18.5, 10 Nov: after
// ⌘T on a keyboard the bar kept View over the empty tab). Also when what it offers moved with nothing at all (B12's thin first answer: MABMenusLook).
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

// The key commands of every responder from start up to the app, as UIKit reads them for a key; *chain: which responders those were (B12, below).
static NSArray<UIKeyCommand *> *MABMenuKeyCommandsFrom(UIResponder *start, uint64_t *chain) {
    NSMutableArray<UIKeyCommand *> *out = [NSMutableArray array];
    uint64_t h = 1469598103934665603ull;
    int depth = 0;   // (at most 64 responders: a nextResponder loop of an app's own must not hang it at every switch -- review L8)
    for (UIResponder *x = start; x && depth < 64; x = x.nextResponder, depth++) {
        h = (h ^ (uint64_t)(uintptr_t)(__bridge void *)x) * 1099511628211ull;
        NSArray *kc = nil;
        @try { kc = x.keyCommands; } @catch (id e) { kc = nil; }
        for (UIKeyCommand *c in kc) if ([c isKindOfClass:[UIKeyCommand class]]) [out addObject:c];
    }
    if (chain) *chain = h;
    return out;
}

// B12, a thin first answer (M1 15.6.1, iPad 2 16.7.7, A12Z 18.5, 20 Nov): what the app offers can grow after it has answered, and nothing says so.
// Its responders' key commands are getters UIKit reads only when it needs them (a key, the Cmd overlay), and a change of them posts nothing; where
// its commands start moves as its views come. Maps answers File, Edit, View about 1 s after it opens; its home card's Bookmarks and Actions come
// with its library, 1-30 s later, and the bar kept the three until a tap. So once it has answered, the app looks again after its own activity (its
// main run loop about to wait: at most once a second, and once more a second after the last of it, so an idle app is not woken again) at what the
// bar's titles rest on besides its main menu: where its commands start, the responders from there up, their key commands (an action, a key and
// modifiers each: not the titles, which an app changes with its state, Play and Pause, in the same menu). Nothing else of the app is asked (no
// canPerformAction:, no validation, no pasteboard) and no file is written. When that differs from its answer's, it says "menuschanged" and
// SpringBoard asks it again 1 s later, as after a shortcut. Its main menu: the app's own word that it changed, UIKit's
// _UIMenuSystemShouldRebuildNotification (by its exported name, where there is one). Not a timer guessing when the app is ready: a check of what
// it offers, and an ask only when that really moved. An app whose looks keep finding a move its next answer doesn't show (a carousel moving its
// responders), or whose word no answer follows (not the bar's app: a window of another app is; or one of our menus or panels is open over it), is
// looked at less often, every 2, 4, then 8 s, until an answer differs or something else asks it (a switch, a tap: B12 review, findings 1 and 5),
// or an answer comes after a word no answer followed (someone listens again: brought forward with no tap, our menu closed).
// With Show Apps' Own Menus off since its answer, the next look stops them before it reads anything (finding 2).
typedef struct { uintptr_t start; uint64_t chain, cmds; uint32_t count, gen; } MABMenuPrint;
static uint32_t gMABMenuGen;   // (the times the app asked UIKit to rebuild its main menu)
static MABMenuPrint MABMenuPrintOf(UIResponder *start, NSArray<UIKeyCommand *> *kcs, uint64_t chain) {
    MABMenuPrint p = { (uintptr_t)(__bridge void *)start, chain, 0, 0, gMABMenuGen };
    for (UIKeyCommand *c in kcs) {
        if (!c.action || !(c.title.length || c.discoverabilityTitle.length)) continue;   // (never a row: as the snapshot)
        uint64_t h = 1469598103934665603ull;
        h = (h ^ (uint64_t)(uintptr_t)sel_getName(c.action)) * 1099511628211ull;
        h = (h ^ (uint64_t)c.input.hash) * 1099511628211ull;
        h = (h ^ (uint64_t)c.modifierFlags) * 1099511628211ull;
        p.cmds += h; p.count++;   // (a sum: the same commands in another order are the same)
    }
    return p;
}
static BOOL MABMenuPrintSame(MABMenuPrint a, MABMenuPrint b) {
    return a.start == b.start && a.chain == b.chain && a.cmds == b.cmds && a.count == b.count && a.gen == b.gen;
}
static MABMenuPrint gMABAnswerPrint, gMABSaidPrint;   // (the last answer's; the last one "menuschanged" was said for)
static BOOL gMABLooking;              // (an answer is out; off once the switch is seen off, until the next answer)
static uint64_t gMABAnswerSig;        // (what the last answer said: its menus, rows and their states)
static CFTimeInterval gMABLookSaidAt; // (when a look last said "menuschanged")
static CFTimeInterval gMABAnsweredAt; // (when the last answer was written)
static int gMABLookIdle;              // (looks in a row whose word showed nothing new: 0-3; a look every 1 << it seconds)
static BOOL gMABLookUnheard;          // (a look counted a word as one no answer followed: the next answer, whoever asked it, puts the looks back)
static void MABMenusLook(void) {
    if (!MABMenusOn()) {   // (switched off since its answer: no looking, not even a walk, until the next answer, which needs it on)
        gMABLooking = NO;
#if DEBUG
        MABLog([NSString stringWithFormat:@"appmenus: Show Apps' Own Menus off since its answer: no more looks (at %.3f)", [[NSDate date] timeIntervalSince1970]]);
#endif
        return;
    }
    UIWindow *win = MABMenuKeyWindow();
    if (!win || win.windowScene.activationState != UISceneActivationStateForegroundActive) return;   // (no window of it in front)
    uint64_t chain = 0;
    UIResponder *start = MABMenuStart(win);
    MABMenuPrint p = MABMenuPrintOf(start, MABMenuKeyCommandsFrom(start, &chain), chain);
    if (MABMenuPrintSame(p, gMABAnswerPrint) || MABMenuPrintSame(p, gMABSaidPrint)) return;
    // (its last word has no answer yet. SpringBoard asks 1 s after a word, and a busy app answers it late: younger than 2.5 s, that answer can
    //  still come and will show this move too, so nothing is said now (one word out at a time, so an answer is the last word's); older, none will
    //  come -- it is not the bar's app, or one of our menus or panels is open over it -- and that counts as an answer that showed nothing: the
    //  next looks wait 2, 4, then 8 s. Before, a window beside the bar's app whose commands kept moving said it every second, without end: B12
    //  review, finding 1)
    if (gMABLookSaidAt > gMABAnsweredAt) {
        if (CACurrentMediaTime() - gMABLookSaidAt < 2.5) return;
        if (gMABLookIdle < 3) gMABLookIdle++;
        gMABLookUnheard = YES;
    }
#if DEBUG
    MABLog([NSString stringWithFormat:@"appmenus: what it offers moved since its answer (start %@ %@, responders %@, %u key commands, were %u, main menu rebuilt %u times since): menuschanged at %.3f; looks every %d s, %@",
            NSStringFromClass([start class]), p.start == gMABAnswerPrint.start ? @"same" : @"moved", p.chain == gMABAnswerPrint.chain ? @"same" : @"moved",
            p.count, gMABAnswerPrint.count, p.gen - gMABAnswerPrint.gen, [[NSDate date] timeIntervalSince1970], 1 << gMABLookIdle,
            !gMABLookSaidAt ? @"its first word" : gMABLookSaidAt > gMABAnsweredAt ? @"its last word had no answer" : @"its last word was answered"]);
#endif
    gMABSaidPrint = p; gMABLookSaidAt = CACurrentMediaTime();
    MABMenusChanged();
}
// Installed with the first answer (once per process; an app SpringBoard never asks has none): the look as the app's main run loop is about to wait,
// after UIKit's layout of that turn; a timer that only wakes the run loop for the one look due after the last activity (a look never arms it).
static void MABMenusWatch(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    static CFRunLoopTimerRef wake; static CFTimeInterval last; static BOOL armed;
    wake = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent() + 1e9, 1e9, 0, 0, ^(CFRunLoopTimerRef t) { armed = NO; });
    CFRunLoopObserverRef obs = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, YES, 2147483000, ^(CFRunLoopObserverRef o, CFRunLoopActivity a) {
        if (!gMABLooking || [UIApplication sharedApplication].applicationState == UIApplicationStateBackground) return;
        CFTimeInterval now = CACurrentMediaTime(), due = last + (double)(1 << gMABLookIdle);
        if (now >= due) {
            last = now;
            if (armed) { armed = NO; CFRunLoopTimerSetNextFireDate(wake, CFAbsoluteTimeGetCurrent() + 1e9); }
            @autoreleasepool { MABMenusLook(); }
        } else if (!armed) { armed = YES; CFRunLoopTimerSetNextFireDate(wake, CFAbsoluteTimeGetCurrent() + (due - now)); }
    });
    if (!wake || !obs) return;
    CFRunLoopTimerSetTolerance(wake, 0.1);
    CFRunLoopAddTimer(CFRunLoopGetMain(), wake, kCFRunLoopDefaultMode);
    CFRunLoopAddObserver(CFRunLoopGetMain(), obs, kCFRunLoopDefaultMode);
    NSString * __unsafe_unretained *rebuild = (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, "_UIMenuSystemShouldRebuildNotification");
    id sys = [UIMenuSystem mainSystem];
    if (rebuild && *rebuild && sys)
        [[NSNotificationCenter defaultCenter] addObserverForName:*rebuild object:sys queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { gMABMenuGen++; }];
}
// An answer written (MABMenuSnapshot): what it rests on, for the looks, which start with the first.
static void MABMenusAnswered(UIResponder *start, NSArray<UIKeyCommand *> *kcs, uint64_t chain, NSArray<NSDictionary *> *ordered) {
    uint64_t sig = 1469598103934665603ull;
    for (NSDictionary *m in ordered) {
        sig = (sig ^ (uint64_t)[m[@"t"] hash]) * 1099511628211ull;
        for (NSDictionary *r in m[@"r"])
            sig = (sig ^ (((uint64_t)[r[@"x"] unsignedIntValue] << 3) | (r[@"s"] ? 4 : 0) | ([r[@"e"] boolValue] ? 2 : 0) | ([r[@"k"] boolValue] ? 1 : 0))) * 1099511628211ull;
    }
    // (the answer to a look's word -- that word still unanswered and at most 3 s old -- saying what the last one said: the looks wait longer.
    //  Any other answer puts them back to once a second: one that differs, or one something else asked for, a switch, a tap, the app brought
    //  forward, a row picked. Before, only a different answer did, so a later growth could wait up to 8 s more: B12 review, finding 5. And the
    //  first answer after a word no answer followed, whoever asked it: someone listens again -- the app brought forward with no tap (Cmd-Tab, its
    //  Dock icon, the App Switcher, the bar's app closed beside it) or one of our menus closed over it, within 3 s of its last word. Before, that
    //  answer counted as the word's and the looks stayed at 8 s, so its card's titles came ~8 s late, not ~2 s: review fixes review, finding 1)
    CFTimeInterval now = CACurrentMediaTime();
    BOOL lookAsked = !gMABLookUnheard && gMABLookSaidAt > gMABAnsweredAt && now - gMABLookSaidAt < 3.0;
    if (sig != gMABAnswerSig || !lookAsked) gMABLookIdle = 0;
    else if (gMABLookIdle < 3) gMABLookIdle++;   // (a look's "menuschanged" that changed nothing)
    gMABAnsweredAt = now; gMABLookUnheard = NO;
    gMABAnswerSig = sig;
    gMABAnswerPrint = MABMenuPrintOf(start, kcs, chain);
    gMABLooking = YES;
    MABMenusWatch();
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
    NSUInteger fromMenu = found.count;
    group += 1000;   // (the responders' own key commands: after the main menu's, as their own group)
    uint64_t chain = 0;
    NSArray<UIKeyCommand *> *keyCmds = MABMenuKeyCommandsFrom(start, &chain);
    for (UIKeyCommand *c in keyCmds) {
        MABMenuFound *f = [MABMenuFound new];
        f.cmd = c; f.topID = nil; f.group = group;
        [found addObject:f];
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
    {   // (B12 thin first answer, p08: where the commands found came from, what has keyboard focus, and when, to set against the looks' lines)
        id focused = nil;
        @try { focused = win ? [UIFocusSystem focusSystemForEnvironment:win].focusedItem : nil; } @catch (id e) { focused = nil; }
        MABLog([NSString stringWithFormat:@"appmenus: snapshot: of them %lu from the main menu, %lu key commands; focused %@; at %.3f",
                (unsigned long)fromMenu, (unsigned long)keyCmds.count, focused ? NSStringFromClass([focused class]) : @"nothing", [[NSDate date] timeIntervalSince1970]]);
    }
    if (MSTestFlag("/tmp/macstatusbar-debug")) for (NSDictionary *m in ordered) for (NSDictionary *r in m[@"r"]) if (!r[@"s"])
        MABLog([NSString stringWithFormat:@"appmenus:   %@ > %08x %@%@%@", m[@"t"], [r[@"x"] unsignedIntValue], r[@"h"] ?: @"", [r[@"e"] boolValue] ? @"" : @" (disabled)", r[@"k"] ? @" (on)" : @""]);   // (a row's key, not its title: names in Open Recent, mailboxes -- review L9)
#else
    (void)kept; (void)noTarget; (void)hidden; (void)destructive; (void)fromMenu;
#endif
    if (wrote) MABMenusAnswered(start, keyCmds, chain, ordered);   // (B12: what it rests on, for the looks)
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
#if DEBUG
    {   // (B12 thin first answer, p08: UIKit's word that a main menu is to be rebuilt or revalidated, and keyboard focus moving: logged only, to the ms)
        NSMutableArray<NSNotificationName> *names = [NSMutableArray arrayWithObject:UIFocusDidUpdateNotification];
        const char *syms[] = { "_UIMenuSystemShouldRebuildNotification", "_UIMenuSystemShouldRevalidateNotification" };
        for (int i = 0; i < 2; i++) { NSString * __unsafe_unretained *p = (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, syms[i]); if (p && *p) [names addObject:*p]; }
        for (NSNotificationName nn in names)
            [[NSNotificationCenter defaultCenter] addObserverForName:nn object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
                id next = [n.name isEqualToString:UIFocusDidUpdateNotification] ? [n.userInfo[UIFocusUpdateContextKey] nextFocusedItem] : n.object;
                MABLog([NSString stringWithFormat:@"appmenus: heard %@ (%@) at %.3f", n.name, next ? NSStringFromClass([next class]) : @"nil", [[NSDate date] timeIntervalSince1970]]);
            }];
    }
#endif
    // (B12: it can answer from now on, and says so. An ask posted before the handlers above were registered was lost -- a Darwin notification is
    //  not kept for a name nobody listens to --, and SpringBoard asks when the app comes to the front, 0.1-0.3 s after a cold launch, while this runs
    //  only once UIApplicationMain does (Reynard ~1.1 s, after Gecko's start; its scene already active, so no menuschanged either): the titles
    //  waited for the next minute's layout of the bar. SpringBoard asks again at once while it is the app in front. Once per process, after both
    //  handlers (an ask SpringBoard sends for this reaches them), only with the switch on)
    if (MABMenusOn()) {
        char here[96]; snprintf(here, sizeof here, "com.besiktasliseba.appbridge.menushere.%08x", hash);
        notify_post(here);
    }
}
