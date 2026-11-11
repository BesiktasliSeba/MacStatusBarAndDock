// CustomShortcuts.h -- Custom Shortcuts (Settings > Keyboard, 1.8.5 item 2, off unless switched on): your own keyboard shortcuts, run in SpringBoard.
// Each opens an app, opens a URL, lays out the front window or goes Home. The rules (format, actions, clashes): common/CustomShortcutsRule.h. Based
// on KeyPilot by wanghuangjie (MIT; its notice there and in third_party/KeyPilot/LICENSE).
// Included at the end of StatusBar.x, after WindowAPI.h and WindowKeys.h, whose ways it uses: the window API's layouts and Home (the same calls
// KeyPilot makes), the way every app of the Dock and our menus is opened (DMOpenApp) and every link (DMOpenURL).
// How the keys come, three ways (the same key come two ways runs once: DMCSRunOnce, MSBDCSRunOnceNow):
//  - the app with the keyboard matches them itself (1.8.6, as KeyPilot does): MacAppBridge's key hook, in every UIKit app, reads the rules
//    SpringBoard publishes as Darwin states (DMCSPublishStates) and posts a rule's run name (DMCSRunFromApp); common/CustomShortcutsRule.h "In the
//    app with the keyboard". This is the way with an app in front: SpringBoard gets no keys then (1.8.5 had only the two below, and the shortcuts
//    worked on the Home Screen only: the KeyPilot author's report).
//  - SpringBoard's own presses (-[SpringBoard pressesBegan:withEvent:]): the Home Screen and our menus.
//  - one key command per shortcut in SpringBoard's own list, registered with backboardd again at each change (as Window Tiling Keys', WindowKeys.h):
//    the apps without our bridge (Sileo, Filza and the other recovery apps: loader/Loader.c). backboardd routes only chords with Command, Control or
//    Globe whose key UIKit names (DMCSKeyInput) to SpringBoard, so there only those work (Settings' page says so).
// Not run: with the switch off, while KeyPilot is installed (it runs its own; both would run each key), while Settings records a shortcut
// (kMSBDCSRecordingNote), or for a rule that is off.
#pragma once
#include "../common/CustomShortcutsRule.h"
#include "../common/InputDevices.h"   // (MSBD_KEYBOARD_CHANGED only: GraphicsServices' post when a hardware keyboard comes or goes)

static NSArray<NSDictionary *> *gCSRules;      // (the usable rules, as read: MSBDCSRuleUsable)
static BOOL gCSSwitch;                          // (the switch)
static BOOL gCSKeyPilot;                        // (KeyPilot installed, read with the rules: its install resprings SpringBoard)
static NSArray<UIKeyCommand *> *gCSKeyCmds;     // (one per usable rule, gCSRules' order)
static unsigned gCSRunNames;                    // (the apps' run names registered: rules 0 to gCSRunNames - 1)
static void (*o_CSPressesBegan)(id, SEL, NSSet *, UIPressesEvent *);
static NSArray *(*o_CSKeyCommands)(id, SEL);

// KeyPilot installed: its app registered, or its tweak in place (its package brings both).
static BOOL DMCSKeyPilotInstalled(void) {
#if DEBUG
    if (DMTestFlag("/tmp/msb-kp-testapp")) return YES;   // (the device check's stand-in, as Settings' KeyboardSettings.x MSKPTestApp: KeyPilot is never installed for a test)
#endif
    if (DMAppForBundle(kMSBDKeyPilotApp)) return YES;
    // (by access(), as every file this tweak looks for in SpringBoard: NSFileManager answered NO for the stand-in there, M1 15.6.1, k03)
    static const char *const libs[] = { "/var/jb/Library/MobileSubstrate/DynamicLibraries/KeyPilotHook.dylib", "/var/jb/usr/lib/TweakInject/KeyPilotHook.dylib" };
    for (size_t i = 0; i < sizeof(libs) / sizeof(libs[0]); i++) if (access(libs[i], F_OK) == 0) return YES;
    return NO;
}
static BOOL DMCSRecording(void) {
    static int token = 0;
    if (!token && notify_register_check(kMSBDCSRecordingNote, &token) != NOTIFY_STATUS_OK) { token = 0; return NO; }
    uint64_t st = 0;
    return notify_get_state(token, &st) == NOTIFY_STATUS_OK && st != 0;
}
// Whether the shortcuts are taken now (each press asks; the key commands and the apps' wanted state follow at each change, DMCSPublish).
static BOOL DMCSWanted(void) { return MSBDCSWantedNow(gCSSwitch, gCSKeyPilot, (unsigned)gCSRules.count, DMCSRecording()); }
// A hardware keyboard, as the run of a key an app posts needs one (DMCSRunFromApp): GraphicsServices' answer (DMHardwareKeyboardAttached; debug
// hwkb_0 pretends none). Debug builds: /tmp/msb-fakekb, the flag Settings' rows already take as a keyboard attached (common/InputDevices.h),
// answers yes here too, so the test iPads with no keyboard (keys_force injects keys without one) run the apps' path end to end.
static BOOL DMCSKeyboard(void) {
#if DEBUG
    if (DMTestFlag("/tmp/msb-fakekb")) return YES;
#endif
    return DMHardwareKeyboardAttached();
}
// Whether SpringBoard runs a key an app posts now, and so the apps' wanted state (MSBDCSAppsWanted): both from this one answer, so an app keeps a
// key from itself only when SpringBoard will run it (1.8.6 i05: with no keyboard the app kept Option-J, SpringBoard refused it, the key was lost).
static BOOL DMCSAppsTaken(void) { return MSBDCSAppsWanted(DMCSWanted(), DMCSKeyboard()); }

// A rule's key as a key command's input (UIKit's names for the arrows; the character otherwise), or nil.
static NSString *DMCSKeyInput(NSDictionary *r) {
    long u = [r[@"keyCode"] longValue];
    switch (u) {
        case kMSBDCSHIDUp: return UIKeyInputUpArrow;
        case kMSBDCSHIDDown: return UIKeyInputDownArrow;
        case kMSBDCSHIDLeft: return UIKeyInputLeftArrow;
        case kMSBDCSHIDRight: return UIKeyInputRightArrow;
        case kMSBDCSHIDReturn: return @"\r";
        case kMSBDCSHIDTab: return @"\t";
        case kMSBDCSHIDSpace: return @" ";
        case kMSBDCSHIDDelete: return @"\b";
        default: break;
    }
    NSString *k = [r[@"key"] isKindOfClass:[NSString class]] ? r[@"key"] : @"";
    if (k.length == 1) return k.lowercaseString;
    if (u >= kMSBDCSHIDA && u <= kMSBDCSHIDZ) return [NSString stringWithFormat:@"%c", (char)('a' + u - kMSBDCSHIDA)];
    if (u >= kMSBDCSHID1 && u < kMSBDCSHID0) return [NSString stringWithFormat:@"%c", (char)('1' + u - kMSBDCSHID1)];
    if (u == kMSBDCSHID0) return @"0";
    return nil;
}

// A rule's action. SpringBoard's main thread.
static void DMCSRun(NSDictionary *r, NSUInteger i) {
    NSString *act = r[@"action"];
    const char *v = MSBDCSActionValue(act.UTF8String);
    notify_post(kMSBDModTapUsedNote);   // (a chord held for it is no volume or backlight tap, as a window key's: common/ModifierTap.h)
    DM_FEATURE_MARK("custom-shortcuts");
    switch (MSBDCSActionKind(act.UTF8String)) {
        case kMSBDCSActApp: {
            NSString *b = v ? @(v) : @"";
            if (!DMAppForBundle(b)) { DMLog([NSString stringWithFormat:@"[shortcuts] %lu: %@ is not installed: nothing opened", (unsigned long)i, b]); return; }
            DMLog([NSString stringWithFormat:@"[shortcuts] %lu: open %@", (unsigned long)i, b]);
            DMOpenApp(b);
            break;
        }
        case kMSBDCSActURL: {
            NSString *u = v ? @(v) : @"";
            if (![NSURL URLWithString:u]) { DMLog([NSString stringWithFormat:@"[shortcuts] %lu: not a URL: nothing opened", (unsigned long)i]); return; }
            DMOpenURL(u, @"custom shortcut");
            break;
        }
        case kMSBDCSActWindow: {
            int st = MSBDKeyPilotLayoutV1(v);
            DMLog([NSString stringWithFormat:@"[shortcuts] %lu: layout %s: %d", (unsigned long)i, v ?: "", st]);
            break;
        }
        case kMSBDCSActHome: {
            int st = MSBDKeyPilotHomeV1();
            DMLog([NSString stringWithFormat:@"[shortcuts] %lu: Home: %d", (unsigned long)i, st]);
            break;
        }
        default: break;
    }
}
// The rule a press is, or -1: its key (the HID usage, wherever the layout puts it, as KeyPilot matches) and its modifiers, Globe among them.
static NSInteger DMCSRuleFor(UIKey *k) {
    if (!k) return -1;
    unsigned long long m = MSBDCSMods((unsigned long long)k.modifierFlags);
    long u = (long)k.keyCode;
    for (NSUInteger i = 0; i < gCSRules.count; i++)
        if (MSBDCSSame([gCSRules[i][@"keyCode"] longValue], [gCSRules[i][@"modifiers"] unsignedLongLongValue], u, m)) return (NSInteger)i;
    return -1;
}
// Once per key, by the way it came (common/CustomShortcutsRule.h MSBDCSRunOnceNow): SpringBoard's own way (its presses and key commands), the same
// rule within 0.5 s of its last arrival is the same key (a press and a key command, a press handed over twice, or the key held: its repeats come
// every ~0.1 s and each moves the time on, so a held URL shortcut opens one tab, not one per repeat; review 1.8.5-k M2); the same rule come the
// other way with it is that key again; an app's post is once per press (the app keeps the repeats), so a second press there runs again at any
// pace (review 1.8.6, L: the app kept a second Option-J 0.3 s after the first and nothing ran).
static BOOL DMCSRunOnce(NSUInteger i, int way) {
    static MSBDCSRunOnceState once;
    if (i >= kMSBDCSMaxRules || !MSBDCSRunOnceNow(&once, (unsigned)i, way, CACurrentMediaTime() * 1000.0)) return YES;
    if (i < gCSRules.count) DMCSRun(gCSRules[i], i);
    return YES;
}
// A press that is one of the shortcuts runs it and is not handed on; the presses that came with it and are none of them are (WindowKeys.h's way).
static void DMCSPressesBegan(id self, SEL _cmd, NSSet<UIPress *> *presses, UIPressesEvent *event) {
    if (presses.count && DMCSWanted()) {
        static NSTimeInterval lastTime = -1;
        static long lastCode = -1;
        NSMutableSet<UIPress *> *others = nil;
        for (UIPress *p in presses) {
            NSInteger i = DMCSRuleFor(p.key);
            if (i < 0) { if (!others) others = [NSMutableSet set]; [others addObject:p]; continue; }
            if (p.timestamp == lastTime && (long)p.key.keyCode == lastCode) continue;   // (the same press handed over again)
            lastTime = p.timestamp; lastCode = (long)p.key.keyCode;
            if (!DMCSRunOnce((NSUInteger)i, kMSBDCSWaySpringBoard)) { if (!others) others = [NSMutableSet set]; [others addObject:p]; }
        }
        if (others.count == presses.count) { o_CSPressesBegan(self, _cmd, presses, event); return; }
        if (others.count) o_CSPressesBegan(self, _cmd, others, event);
        return;
    }
    o_CSPressesBegan(self, _cmd, presses, event);
}
static NSArray *DMCSKeyCommands(id self, SEL _cmd) {
    NSArray *orig = o_CSKeyCommands(self, _cmd);
    if (!gCSKeyCmds.count || !DMCSWanted()) return orig;
    NSMutableArray *all = [NSMutableArray arrayWithArray:[orig isKindOfClass:[NSArray class]] ? orig : @[]];
    [all addObjectsFromArray:gCSKeyCmds];
    return all;
}
// A key command of ours ran (dm_cshort<n>:): its rule.
static void DMCSKeyCommandFired(id self, SEL _cmd, id sender) {
    NSString *s = NSStringFromSelector(_cmd);
    if (s.length < 10 || !DMCSWanted()) return;
    NSInteger i = [[s substringWithRange:NSMakeRange(9, s.length - 10)] integerValue];   // ("dm_cshort" n ":")
    if (i >= 0 && i < (NSInteger)gCSRules.count) DMCSRunOnce((NSUInteger)i, kMSBDCSWaySpringBoard);
}
// Once, the first time there is a shortcut to take: SpringBoard's presses and key commands hooked.
static BOOL DMCSInstall(void) {
    static int done = 0;   // (1 hooked, -1 can't be here)
    if (done) return done > 0;
    Class sb = objc_getClass("SpringBoard");
    if (!DMMSWHasMethod(sb, @"pressesBegan:withEvent:", @"v@:@@") || !DMMSWHasMethod(sb, @"keyCommands", @"@@:")) {
        DMLog(@"[shortcuts] SpringBoard's key handling differs here: no Custom Shortcuts");
        done = -1;
        return NO;
    }
    MSHookMessageEx(sb, @selector(pressesBegan:withEvent:), (IMP)DMCSPressesBegan, (IMP *)&o_CSPressesBegan);
    MSHookMessageEx(sb, @selector(keyCommands), (IMP)DMCSKeyCommands, (IMP *)&o_CSKeyCommands);
    done = 1;
    return YES;
}
// Our key commands, made again for the rules as read (selectors dm_cshort<n>: added to SpringBoard as needed, kMSBDCSMaxRules at most).
static void DMCSMakeKeyCommands(void) {
    Class sb = objc_getClass("SpringBoard");
    SEL prio = NSSelectorFromString(@"setWantsPriorityOverSystemBehavior:");   // (iPadOS 15+: before a text field's own handling)
    NSMutableArray *cmds = [NSMutableArray array];
    for (NSUInteger i = 0; i < gCSRules.count; i++) {
        NSString *in = DMCSKeyInput(gCSRules[i]);
        if (!in) continue;   // (a key with no input UIKit names: taken while SpringBoard has the keyboard only)
        SEL sel = NSSelectorFromString([NSString stringWithFormat:@"dm_cshort%lu:", (unsigned long)i]);
        class_addMethod(sb, sel, (IMP)DMCSKeyCommandFired, "v@:@");   // (already there: kept)
        UIKeyCommand *c = [UIKeyCommand keyCommandWithInput:in modifierFlags:(UIKeyModifierFlags)MSBDCSMods([gCSRules[i][@"modifiers"] unsignedLongLongValue]) action:sel];   // (the match's modifiers: no Caps Lock or keypad bit)
        if (!c) continue;
        if ([c respondsToSelector:prio]) ((void (*)(id, SEL, BOOL))objc_msgSend)(c, prio, YES);
        [cmds addObject:c];
    }
    gCSKeyCmds = cmds;
}
// backboardd takes SpringBoard's key commands only when UIKit registers them (WindowKeys.h DMWindowKeysRegister): again at each change.
// What changed is the key commands themselves (each one's input and modifiers): -[NSArray hash] is only the count, so new keys for a shortcut,
// with as many shortcuts as before, were never registered (review 1.8.5-k M1).
static NSString *DMCSKeySignature(void) {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%d|", DMCSWanted() ? 1 : 0];
    for (UIKeyCommand *c in gCSKeyCmds) [s appendFormat:@"%@/%llx/%@;", c.input, (unsigned long long)c.modifierFlags, NSStringFromSelector(c.action)];
    return s;
}
// The apps' way (1.8.6, CustomShortcutsRule.h "In the app with the keyboard"): the rules as Darwin states, rule n in kMSBDCSRuleStateFmt n (gCSRules'
// order, so the index an app posts is SpringBoard's rule), then the count with the next generation in kMSBDCSRulesState, posted once all are set
// (the apps read them again then), and the wanted state (switch, KeyPilot, recording) whenever it changes. With the switch off or KeyPilot in, the
// count is 0, so an app reads no rule at all. The wanted state is the apps' (DMCSAppsTaken: taken, and a hardware keyboard for SpringBoard to run
// what they post), again whenever one comes or goes (DMCSKeyboardTick). The run names are registered as rules come (DMCSRunFromApp).
static void DMCSRunFromApp(unsigned i);
static uint64_t DMCSStateGet(int *token, const char *name) {
    if (!*token && notify_register_check(name, token) != NOTIFY_STATUS_OK) { *token = 0; return 0; }
    uint64_t st = 0;
    notify_get_state(*token, &st);
    return st;
}
static void DMCSStateSet(int *token, const char *name, uint64_t st) {
    if (!*token && notify_register_check(name, token) != NOTIFY_STATUS_OK) { *token = 0; return; }
    notify_set_state(*token, st);
}
// Any app can set these states (Darwin notify can't tell who wrote one; review 1.8.6, L: forged rules took copy and paste from every app and told
// the forger when they were pressed). SpringBoard compares what is published now, the live states, with what it means them to be, and writes
// again and posts on any difference: at each change, on each post of the rules' or the wanted state (its own posts match, so no loop), and when
// an app comes to the front (an app reads them at its start; DMCSFrontChanged). A forger can write again, but never keeps the states.
// The difference counts the count too (MSBDCSPublishedSame: 1.8.6 i05, the last rule turned off or deleted stayed published with its old count,
// its keys kept from every app and nothing run, until a respring), and the slots past a smaller count are cleared (MSBDCSSlotsToWrite).
static int gCSRuleTokens[kMSBDCSMaxRules], gCSRulesToken, gCSWantedToken;
static uint64_t DMCSLiveSlot(unsigned i, void *ctx) {   // (the slot the apps read for rule i)
    char name[96]; snprintf(name, sizeof name, kMSBDCSRuleStateFmt, i);
    return DMCSStateGet(&gCSRuleTokens[i], name);
}
static void DMCSPublishStates(void) {
    static uint64_t lastRS = 0;   // (the rules' state SpringBoard wrote last: the count and its generation)
    static unsigned lastCount = 0;
    static BOOL published = NO;
    unsigned n = gCSSwitch && !gCSKeyPilot ? (unsigned)MIN(gCSRules.count, (NSUInteger)kMSBDCSMaxRules) : 0;
    uint64_t packed[kMSBDCSMaxRules] = {0};
    for (unsigned i = 0; i < n; i++) packed[i] = MSBDCSPackRule(gCSRules[i]);
    uint64_t live = DMCSStateGet(&gCSRulesToken, kMSBDCSRulesState);
    if (!MSBDCSPublishedSame(published, live, lastRS, n, packed, DMCSLiveSlot, NULL)) {
        unsigned w = MSBDCSSlotsToWrite(n, lastCount, live);
        for (unsigned i = 0; i < w; i++) {   // (the slots now, and the ones an app read before cleared)
            char name[96]; snprintf(name, sizeof name, kMSBDCSRuleStateFmt, i);
            DMCSStateSet(&gCSRuleTokens[i], name, packed[i]);
        }
        uint64_t rs = MSBDCSRulesNext(live, n);   // (the generation goes on from the one published, a respring too)
        DMCSStateSet(&gCSRulesToken, kMSBDCSRulesState, rs);
        static int forgedLogs = 0;   // (the first few only: a forger writing again and again would fill the log)
        if (published && live != lastRS && forgedLogs < 3) { forgedLogs++; DMLog(@"[shortcuts] the rules' state was not ours: written again"); }
        lastRS = rs; lastCount = n; published = YES;
        for (; gCSRunNames < n; gCSRunNames++) {
            unsigned i = gCSRunNames;
            char name[96]; snprintf(name, sizeof name, kMSBDCSRunFmt, i);
            int token = 0;
            notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) { DMCSRunFromApp(i); });
        }
        notify_post(kMSBDCSRulesState);
        DMLog([NSString stringWithFormat:@"[shortcuts] published for the apps: %u rules, generation %llu", n, (unsigned long long)MSBDCSRulesGen(rs)]);
    }
    uint64_t wanted = DMCSAppsTaken() ? 1 : 0;   // (the apps': SpringBoard's run gate in it, DMCSRunFromApp)
    if (DMCSStateGet(&gCSWantedToken, kMSBDCSWantedState) != wanted) {   // (the live state: a change, or one some other process wrote)
        DMCSStateSet(&gCSWantedToken, kMSBDCSWantedState, wanted);
        notify_post(kMSBDCSWantedState);
    }
}
// An app with the keyboard matched rule i (kMSBDCSRunFmt i). Run as a press of ours: only while taken, once per key (DMCSRunOnce: the same key
// come by a key command too runs once). Any process may post the names, so only with a hardware keyboard attached (a real key-down needs one)
// and at a press's pace (common/CustomShortcutsRule.h MSBDCSFromAppTake: 4 at once, then one each 0.15 s): a loop posting run.0 and run.1 in turn
// ran the user's shortcuts hundreds of times a second on SpringBoard's main thread (review 1.8.6, L), and a limit of one post each 0.25 s, every
// post moving it on, dropped Option-1 then Option-2 0.2 s apart, the app keeping both (review 1.8.6, L). Taken and the keyboard are one answer,
// DMCSAppsTaken, the one the apps read as the wanted state; the bucket and the once-per-key check drop only what no hand presses: an app keeps a
// key only when this runs it.
static void DMCSRunFromApp(unsigned i) {
    if (!DMCSAppsTaken() || i >= gCSRules.count) return;
    static MSBDCSFromAppBucket bucket;
    if (!MSBDCSFromAppTake(&bucket, CACurrentMediaTime() * 1000.0)) return;   // (no log: a flood would fill it)
    DMLog([NSString stringWithFormat:@"[shortcuts] %u: from the app with the keyboard", i]);
    DMCSRunOnce(i, kMSBDCSWayApp);
}
static void DMCSPublish(void) {
    static NSString *last = nil;
    static int tries = 0;
    DMCSPublishStates();
    NSString *sig = DMCSKeySignature();
    if ([sig isEqualToString:last]) return;
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) {   // (SpringBoard's application not up yet: tried again in a second, up to a minute; 1.8.5 waited for the next change)
        static BOOL pending = NO;
        if (pending) return;
        if (tries >= 60) { DMLog(@"[shortcuts] SpringBoard's application never came: the key commands not registered"); return; }
        pending = YES; tries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC), dispatch_get_main_queue(), ^{ pending = NO; DMCSPublish(); });
        return;
    }
    tries = 0;
    last = sig;
    int now = DMCSWanted() ? 1 : 0;
    if (DMMSWHasMethod(object_getClass(app), @"_updateSerializableKeyCommandsForResponder:", @"v@:@")) {
        @try { ((void (*)(id, SEL, id))objc_msgSend)(app, NSSelectorFromString(@"_updateSerializableKeyCommandsForResponder:"), nil); }
        @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[shortcuts] the key commands' registration refused: %@", e.reason]); }
    } else DMLog(@"[shortcuts] -_updateSerializableKeyCommandsForResponder: differs here: the key commands not registered (the apps' own check still takes the shortcuts)");
    DMLog([NSString stringWithFormat:@"[shortcuts] %@ (%lu shortcuts, %lu key commands)", now ? @"taken" : @"not taken", (unsigned long)gCSRules.count, (unsigned long)gCSKeyCmds.count]);
}
// The switch and the rules read (at start, at each change; Settings posts kMSBDCSChanged).
static void DMCSLoad(void) {
    CFPreferencesAppSynchronize(CFSTR(kMSBDCSDomain));
    CFPropertyListRef sw = CFPreferencesCopyValue(CFSTR(kMSBDCSEnabled), CFSTR(kMSBDCSDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    gCSSwitch = sw && CFGetTypeID(sw) == CFBooleanGetTypeID() && CFBooleanGetValue(sw);
    if (sw) CFRelease(sw);
    NSArray *rules = CFBridgingRelease(CFPreferencesCopyValue(CFSTR(kMSBDCSRules), CFSTR(kMSBDCSDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    NSMutableArray *usable = [NSMutableArray array];
    for (NSDictionary *r in [rules isKindOfClass:[NSArray class]] ? rules : @[]) {
        if (usable.count >= kMSBDCSMaxRules) break;
        if (MSBDCSRuleUsable(r)) [usable addObject:[r copy]];
    }
    gCSRules = usable;
    gCSKeyPilot = DMCSKeyPilotInstalled();
    if (gCSSwitch && gCSKeyPilot) DMLog(@"[shortcuts] KeyPilot is installed: its own shortcuts run, not ours");
    if (gCSSwitch && usable.count && DMCSInstall()) DMCSMakeKeyCommands();
    else gCSKeyCmds = nil;
    DMCSPublish();
}
// A recording belongs to Settings in front. Settings closed or left while recording (Home, a swipe up, killed in the background) left the state
// at 1 and every shortcut waiting, in SpringBoard and in the apps, until Settings recorded again (review 1.8.6, L; Settings' page also stops it
// when it leaves the front). SpringBoard owns the state too: Settings not in front, still not half a second later, ends the recording.
static BOOL gCSStarted;
static BOOL DMCSSettingsInFront(void) {
    return [[DMActiveApp() bundleIdentifier] isEqualToString:@"com.apple.Preferences"] || [[DMFrontApp() bundleIdentifier] isEqualToString:@"com.apple.Preferences"];
}
static void DMCSRecordingCheck(void) {
    if (!DMCSRecording() || DMCSSettingsInFront()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!DMCSRecording() || DMCSSettingsInFront()) return;
        static int token = 0;
        DMCSStateSet(&token, kMSBDCSRecordingNote, 0);
        DMLog(@"[shortcuts] recording with Settings not in front: ended");
        notify_post(kMSBDCSRecordingNote);   // (DMCSPublish: the key commands and the wanted state back)
    });
}
static void DMCSFrontChanged(void) {   // (the 0.2 s tick: the app in front changed)
    if (!gCSStarted) return;
    DMCSPublishStates();   // (an app that just started read the states: forged ones are put back and posted, so it reads them again)
    DMCSRecordingCheck();
}
// A hardware keyboard came or went: the apps' wanted state follows (DMCSAppsTaken), so with none they pass every key on. GraphicsServices posts
// MSBD_KEYBOARD_CHANGED then, but that post was never seen on these iPads (Settings' rows follow it unproven), so the 0.2 s tick compares too:
// one in-process read, a publish only when it changed.
static void DMCSKeyboardTick(void) {
    static int last = -1;
    if (!gCSStarted) return;
    int now = DMCSKeyboard() ? 1 : 0;
    if (now == last) return;
    last = now;
    DMCSPublishStates();
}
static void DMCustomShortcutsStart(void) {
    static int token = 0, rec = 0, rules = 0, wanted = 0, keyboard = 0;
    if (token) return;
    notify_register_dispatch(kMSBDCSChanged, &token, dispatch_get_main_queue(), ^(int t) { DMCSLoad(); });
    notify_register_dispatch(kMSBDCSRecordingNote, &rec, dispatch_get_main_queue(), ^(int t) { DMCSPublish(); DMCSRecordingCheck(); });   // (recording: our key commands out, then back)
    notify_register_dispatch(kMSBDCSRulesState, &rules, dispatch_get_main_queue(), ^(int t) { DMCSPublishStates(); });     // (a post of the apps' states: still ours?)
    notify_register_dispatch(kMSBDCSWantedState, &wanted, dispatch_get_main_queue(), ^(int t) { DMCSPublishStates(); });
    notify_register_dispatch(MSBD_KEYBOARD_CHANGED, &keyboard, dispatch_get_main_queue(), ^(int t) { DMCSKeyboardTick(); });   // (a keyboard came or went)
    gCSStarted = YES;
    DMCSLoad();
}

#if DEBUG
// cshort: the switch, KeyPilot, recording, the rules as read, our key commands and the states published for the apps (read only). cshort_<n>: rule n run as if its key was pressed.
static void DMCustomShortcutsDebug(NSString *cmd) {
    if ([cmd isEqualToString:@"cshort"]) {
        NSMutableString *o = [NSMutableString stringWithFormat:@"[shortcuts] switch %d, KeyPilot %d, recording %d, taken %d, keyboard %d (apps' runs %d), hooked %d, %lu rules, %lu key commands:",
                              gCSSwitch, gCSKeyPilot, DMCSRecording(), DMCSWanted(), DMCSKeyboard(), DMCSAppsTaken(), o_CSPressesBegan != NULL, (unsigned long)gCSRules.count, (unsigned long)gCSKeyCmds.count];
        for (NSUInteger i = 0; i < gCSRules.count; i++) {
            NSDictionary *r = gCSRules[i];
            [o appendFormat:@"\n  %lu: key 0x%lx mods 0x%llx (%@) -> %@", (unsigned long)i, [r[@"keyCode"] longValue], [r[@"modifiers"] unsignedLongLongValue],
                            MSBDCSShortcutText([r[@"keyCode"] longValue], r[@"key"], [r[@"modifiers"] unsignedLongLongValue]), r[@"action"]];
        }
        for (UIKeyCommand *c in gCSKeyCmds) [o appendFormat:@"\n  key command %@ mod 0x%llx -> %@", c.input, (unsigned long long)c.modifierFlags, NSStringFromSelector(c.action)];
        uint64_t rs = DMCSStateGet(&gCSRulesToken, kMSBDCSRulesState), w = DMCSStateGet(&gCSWantedToken, kMSBDCSWantedState);   // (as the apps read them)
        [o appendFormat:@"\n  published: wanted %llu, %u rules, generation %llu, %u run names", (unsigned long long)w, MSBDCSRulesCount(rs), (unsigned long long)MSBDCSRulesGen(rs), gCSRunNames];
        for (unsigned i = 0; i < MSBDCSRulesCount(rs); i++) {
            char name[96]; snprintf(name, sizeof name, kMSBDCSRuleStateFmt, i);
            uint64_t p = DMCSStateGet(&gCSRuleTokens[i], name);
            [o appendFormat:@"\n  state %u: 0x%llx (key 0x%lx mods 0x%llx on %d)", i, (unsigned long long)p, MSBDCSPackedUsage(p), MSBDCSPackedMods(p), MSBDCSPackedOn(p)];
        }
        DMLog(o);
    } else if ([cmd hasPrefix:@"cshort_"]) {
        NSInteger i = [[cmd substringFromIndex:7] integerValue];
        if (i >= 0 && i < (NSInteger)gCSRules.count) DMCSRunOnce((NSUInteger)i, kMSBDCSWaySpringBoard);
    }
}
#endif
