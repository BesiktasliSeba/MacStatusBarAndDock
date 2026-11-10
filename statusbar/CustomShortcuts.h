// CustomShortcuts.h -- Custom Shortcuts (Settings > Keyboard, 1.8.5 item 2, off unless switched on): your own keyboard shortcuts, run in SpringBoard.
// Each opens an app, opens a URL, lays out the front window or goes Home. The rules (format, actions, clashes): common/CustomShortcutsRule.h. Based
// on KeyPilot by wanghuangjie (MIT; its notice there and in third_party/KeyPilot/LICENSE).
// Included at the end of StatusBar.x, after WindowAPI.h and WindowKeys.h, whose ways it uses: the window API's layouts and Home (the same calls
// KeyPilot makes), the way every app of the Dock and our menus is opened (DMOpenApp) and every link (DMOpenURL).
// How the keys come (as Window Tiling Keys', WindowKeys.h): SpringBoard's own presses (-[SpringBoard pressesBegan:withEvent:]), and, so that
// backboardd hands SpringBoard a shortcut while an app is in front, one key command per shortcut in SpringBoard's own list, registered again at each
// change. No key hook in the apps (KeyPilot's way: a hook of -[UIApplication sendEvent:] in every app).
// Not run: with the switch off, while KeyPilot is installed (it runs its own; both would run each key), while Settings records a shortcut
// (kMSBDCSRecordingNote), or for a rule that is off.
#pragma once
#include "../common/CustomShortcutsRule.h"

static NSArray<NSDictionary *> *gCSRules;      // (the usable rules, as read: MSBDCSRuleUsable)
static BOOL gCSSwitch;                          // (the switch)
static BOOL gCSKeyPilot;                        // (KeyPilot installed, read with the rules: its install resprings SpringBoard)
static NSArray<UIKeyCommand *> *gCSKeyCmds;     // (one per usable rule, gCSRules' order)
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
// Whether the shortcuts are taken now (each press asks; the key commands follow at each change, DMCSPublish).
static BOOL DMCSWanted(void) { return gCSSwitch && !gCSKeyPilot && gCSRules.count && !DMCSRecording(); }

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
// Once per key: the same rule asked again within 0.5 s of the last time it came is the same key (a press and a key command, a press handed over
// twice, or the key held: its repeats come every ~0.1 s and each moves the time on, so a held URL shortcut opens one tab, not one per repeat;
// review 1.8.5-k M2). A second press after a short pause runs again.
static BOOL DMCSRunOnce(NSUInteger i) {
    static NSUInteger lastRule = NSNotFound;
    static CFTimeInterval lastAt = -100;
    CFTimeInterval at = CACurrentMediaTime();
    BOOL same = i == lastRule && at - lastAt < 0.5;
    lastRule = i; lastAt = at;
    if (same) return YES;
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
            if (!DMCSRunOnce((NSUInteger)i)) { if (!others) others = [NSMutableSet set]; [others addObject:p]; }
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
    if (i >= 0 && i < (NSInteger)gCSRules.count) DMCSRunOnce((NSUInteger)i);
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
        UIKeyCommand *c = [UIKeyCommand keyCommandWithInput:in modifierFlags:(UIKeyModifierFlags)[gCSRules[i][@"modifiers"] unsignedLongLongValue] action:sel];
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
static void DMCSPublish(void) {
    static NSString *last = nil;
    NSString *sig = DMCSKeySignature();
    if ([sig isEqualToString:last]) return;
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;   // (SpringBoard's application not up yet: registered at the next change or read)
    last = sig;
    int now = DMCSWanted() ? 1 : 0;
    if (DMMSWHasMethod(object_getClass(app), @"_updateSerializableKeyCommandsForResponder:", @"v@:@")) {
        @try { ((void (*)(id, SEL, id))objc_msgSend)(app, NSSelectorFromString(@"_updateSerializableKeyCommandsForResponder:"), nil); }
        @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[shortcuts] the key commands' registration refused: %@", e.reason]); }
    }
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
static void DMCustomShortcutsStart(void) {
    static int token = 0, rec = 0;
    if (token) return;
    notify_register_dispatch(kMSBDCSChanged, &token, dispatch_get_main_queue(), ^(int t) { DMCSLoad(); });
    notify_register_dispatch(kMSBDCSRecordingNote, &rec, dispatch_get_main_queue(), ^(int t) { DMCSPublish(); });   // (recording: our key commands out, then back)
    DMCSLoad();
}

#if DEBUG
// cshort: the switch, KeyPilot, recording, the rules as read and our key commands (read only). cshort_<n>: rule n run as if its key was pressed.
static void DMCustomShortcutsDebug(NSString *cmd) {
    if ([cmd isEqualToString:@"cshort"]) {
        NSMutableString *o = [NSMutableString stringWithFormat:@"[shortcuts] switch %d, KeyPilot %d, recording %d, taken %d, hooked %d, %lu rules, %lu key commands:",
                              gCSSwitch, gCSKeyPilot, DMCSRecording(), DMCSWanted(), o_CSPressesBegan != NULL, (unsigned long)gCSRules.count, (unsigned long)gCSKeyCmds.count];
        for (NSUInteger i = 0; i < gCSRules.count; i++) {
            NSDictionary *r = gCSRules[i];
            [o appendFormat:@"\n  %lu: key 0x%lx mods 0x%llx (%@) -> %@", (unsigned long)i, [r[@"keyCode"] longValue], [r[@"modifiers"] unsignedLongLongValue],
                            MSBDCSShortcutText([r[@"keyCode"] longValue], r[@"key"], [r[@"modifiers"] unsignedLongLongValue]), r[@"action"]];
        }
        for (UIKeyCommand *c in gCSKeyCmds) [o appendFormat:@"\n  key command %@ mod 0x%llx -> %@", c.input, (unsigned long long)c.modifierFlags, NSStringFromSelector(c.action)];
        DMLog(o);
    } else if ([cmd hasPrefix:@"cshort_"]) {
        NSInteger i = [[cmd substringFromIndex:7] integerValue];
        if (i >= 0 && i < (NSInteger)gCSRules.count) DMCSRunOnce((NSUInteger)i);
    }
}
#endif
