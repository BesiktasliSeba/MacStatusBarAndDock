#!/bin/bash
# Mac test of Custom Shortcuts (1.8.5 item 2, based on KeyPilot by wanghuangjie; common/CustomShortcutsRule.h, test-customshortcuts.c), then the sites:
# the app with the keyboard matches the shortcuts in MacAppBridge's existing key hook, first there (1.8.6, the KeyPilot author's report), from the
# rules SpringBoard publishes as Darwin states, and SpringBoard runs what it posts; SpringBoard also takes them through its own presses and key
# commands; all only with the switch on, KeyPilot not installed and Settings not recording; each action the window API's, our app opening and our
# links; the Settings pages (recording, clashes refused, the import without shell actions, the credit, where only some chords work);
# KeyPilot's license in the repository and the package; Acknowledgements. Last, copies of the rules with one thing broken must fail the test.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tcs" test-customshortcuts.c
"$W/tcs"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
R=../common/CustomShortcutsRule.h; C=../statusbar/CustomShortcuts.h; B=../appbridge/AppBridge.x; S=../statusbar/StatusBar.x; P=../macsettings/CustomShortcuts.x; KB=../macsettings/KeyboardSettings.x
A=../statusbar/macstatusbarprefs/MSBAcknowledgementsController.m; RL=../statusbar/macstatusbarprefs/MSBRootListController.m
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
check "KeyPilot's license: its MIT text in the repository (third_party/KeyPilot/LICENSE), copied into the package next to our libraries; the notice in the ported rules" \
  "grep -q 'Copyright (c) 2026 wanghuangjie' ../third_party/KeyPilot/LICENSE && grep -q 'Permission is hereby granted, free of charge' ../third_party/KeyPilot/LICENSE \
   && grep -q 'cp -f third_party/KeyPilot/LICENSE \"\$\$P/third_party/KeyPilot/LICENSE\"' ../Makefile \
   && grep -q 'Portions: Copyright (c) 2026 wanghuangjie. MIT License:' $R && grep -q 'The above copyright notice and this permission notice shall be included' $R"
check "SpringBoard: the shortcuts from its own presses and its key commands (as Window Tiling Keys), hooked once there is one to take; no hook of the apps' sendEvent: added" \
  "fn 'static BOOL DMCSInstall(void) {' $C && grep -q 'MSHookMessageEx(sb, @selector(pressesBegan:withEvent:), (IMP)DMCSPressesBegan, (IMP \*)&o_CSPressesBegan);' \$W/fn \
   && grep -q 'MSHookMessageEx(sb, @selector(keyCommands), (IMP)DMCSKeyCommands, (IMP \*)&o_CSKeyCommands);' \$W/fn && ! grep -q 'selector(sendEvent:)\|%hook UIApplication' $C \
   && fn 'static void DMCSLoad(void) {' $C && grep -q 'if (gCSSwitch && usable.count && DMCSInstall()) DMCSMakeKeyCommands();' \$W/fn"
check "  ... taken only with the switch on, KeyPilot not installed, a rule to run and Settings not recording; a press of none of them handed on as it came" \
  "grep -q 'static BOOL DMCSWanted(void) { return MSBDCSWantedNow(gCSSwitch, gCSKeyPilot, (unsigned)gCSRules.count, DMCSRecording()); }' $C \
   && grep -q 'return switchOn && !keyPilot && count > 0 && !recording;' $R \
   && fn 'static void DMCSPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $C && grep -q 'if (presses.count && DMCSWanted()) {' \$W/fn \
   && grep -q 'if (others.count == presses.count) { o_CSPressesBegan(self, _cmd, presses, event); return; }' \$W/fn"
check "  ... matched by the key and the modifiers with Globe (MSBDCSSame on MSBDCSMods), each rule once per key" \
  "fn 'static NSInteger DMCSRuleFor(UIKey \*k) {' $C && grep -q 'unsigned long long m = MSBDCSMods((unsigned long long)k.modifierFlags);' \$W/fn && grep -q 'MSBDCSSame(' \$W/fn \
   && fn 'static BOOL DMCSRunOnce(NSUInteger i, int way) {' $C && grep -q 'static MSBDCSRunOnceState once;' \$W/fn \
   && grep -q 'if (i >= kMSBDCSMaxRules || !MSBDCSRunOnceNow(&once, (unsigned)i, way, CACurrentMediaTime() \* 1000.0)) return YES;' \$W/fn \
   && grep -q '#define kMSBDCSSameKeyMs 500.0' $R && ! grep -q 'lastRule\|lastAt' $C"
check "  ... the actions: an installed app by our own opening (no BigBoss open), a URL by our links, a layout and Home by the window API's V1 (KeyPilot's calls); no shell" \
  "fn 'static void DMCSRun(NSDictionary \*r, NSUInteger i) {' $C && grep -q 'DMOpenApp(b);' \$W/fn && grep -q 'if (!DMAppForBundle(b))' \$W/fn && grep -q 'DMOpenURL(u, @\"custom shortcut\");' \$W/fn \
   && grep -q 'int st = MSBDKeyPilotLayoutV1(v);' \$W/fn && grep -q 'int st = MSBDKeyPilotHomeV1();' \$W/fn && ! grep -q -i 'posix_spawn\|shell' \$W/fn && ! grep -q 'posix_spawn' $C"
check "  ... a chord held for a shortcut is no volume or backlight tap; the rules read at each change of Settings; started a moment after SpringBoard starts" \
  "fn 'static void DMCSRun(NSDictionary \*r, NSUInteger i) {' $C && grep -q 'notify_post(kMSBDModTapUsedNote);' \$W/fn \
   && grep -q 'notify_register_dispatch(kMSBDCSChanged, &token, dispatch_get_main_queue(), ^(int t) { DMCSLoad(); });' $C \
   && grep -q 'DMCustomShortcutsStart(); });   // Custom Shortcuts' $S && grep -q '#include \"CustomShortcuts.h\"' $S"
check "  ... the key commands are registered again whenever they change (their input and modifiers, not the rules' count); SpringBoard keeps only rules that pass the record-time checks" \
  "fn 'static void DMCSPublish(void) {' $C && grep -q 'NSString \*sig = DMCSKeySignature();' \$W/fn && grep -q 'if (\[sig isEqualToString:last\]) return;' \$W/fn && ! grep -q 'gCSRules hash' $C \
   && fn 'static inline BOOL MSBDCSRuleUsable(NSDictionary \*r) {' $R && grep -q '== kMSBDCSOK;' \$W/fn"
check "The app with the keyboard (1.8.6): MacAppBridge's existing key hook asks the shortcuts first, before the menus' keys and Esc, outside SpringBoard; a key of theirs is not passed on" \
  "fn 'static void hMABHandleKeyUIEvent(id self, SEL _cmd, id ev) {' $B && grep -n 'MABCSTakesKey\|MSBDMenuKeyAct\|MABSpotlightEsc\|MABEscEndsTypingNow' \$W/fn | head -1 | grep -q MABCSTakesKey \
   && grep -q 'if (MABCSTakesKey(code, isDown, m)) return;' \$W/fn \
   && [ \$(grep -n '!MABInSpringBoard()' \$W/fn | head -1 | cut -d: -f1) -lt \$(grep -n 'MABCSTakesKey' \$W/fn | head -1 | cut -d: -f1) ]"
check "  ... no new hook in the apps: handleKeyUIEvent: hooked once, as before; nothing of the shortcuts hooks sendEvent:" \
  "[ \$(grep -c 'MSHookMessageEx(\[UIApplication class\], s, (IMP)hMABHandleKeyUIEvent, (IMP \*)&oMABHandleKeyUIEvent);' $B) = 1 ] \
   && awk '/^static uint64_t gMABCSRules/,/^\/\/ Hardware keys reach an app/' $B | sed '\$d' > \$W/cs && [ -s \$W/cs ] && ! grep -q 'MSHook\|sendEvent\|%hook' \$W/cs"
check "  ... the rules read at start, on Settings' change and on SpringBoard's publish; only in a real app with the key hook, not in SpringBoard" \
  "fn 'static void MABCSStart(void) {' $B && grep -q 'notify_register_dispatch(kMSBDCSChanged, &tokChanged, dispatch_get_main_queue(), ^(int t) { MABCSRead(); });' \$W/fn \
   && grep -q 'notify_register_dispatch(kMSBDCSRulesState, &tokRules, dispatch_get_main_queue(), ^(int t) { MABCSRead(); });' \$W/fn && grep -q 'MABCSRead();' \$W/fn \
   && grep -q 'if (oMABHandleKeyUIEvent && !MABInSpringBoard()) MABCSStart();' $B \
   && fn 'static void MABCSRead(void) {' $B && grep -q 'unsigned n = MSBDCSRulesCount(rs);' \$W/fn && grep -q 'snprintf(name, sizeof name, kMSBDCSRuleStateFmt, i);' \$W/fn"
check "  ... a match asks SpringBoard's word then: not recording, the wanted state 1, the rules read again (and matched again) if their generation moved" \
  "fn 'static int MABCSConfirm(long usage, unsigned long long flags, int rule) {' $B && grep -q 'MABCSState(&gMABCSRecToken, kMSBDCSRecordingNote) != 0) return -1;' \$W/fn \
   && grep -q 'MABCSState(&gMABCSWantedToken, kMSBDCSWantedState) != 1) return -1;' \$W/fn && grep -q 'MABCSState(&gMABCSRulesToken, kMSBDCSRulesState) != gMABCSRulesState' \$W/fn \
   && grep -q 'rule = MSBDCSMatch(gMABCSRules, gMABCSCount, usage, flags);' \$W/fn"
check "  ... the shared rule decides (MSBDCSKeyAct: the pair of key-down and key-up), a run posts the rule's own name; with no rules nothing is asked" \
  "fn 'static BOOL MABCSTakesKey(int code, BOOL isDown, long long m) {' $B && grep -q 'int act = MSBDCSKeyAct(&gMABCSHeld, gMABCSRules, gMABCSCount, code, isDown, (unsigned long long)m, CACurrentMediaTime() \* 1000.0, MABCSConfirm, &rule);' \$W/fn \
   && grep -q 'snprintf(name, sizeof name, kMSBDCSRunFmt, (unsigned)rule);' \$W/fn && grep -q 'notify_post(name);' \$W/fn && grep -q 'return act != MSBDCSKeyPass;' \$W/fn \
   && grep -q 'if (!gMABCSCount && !MSBDCSKeyBit(gMABCSHeld.held, code)) return NO;' \$W/fn && grep -q '#include \"../common/CustomShortcutsRule.h\"' $B"
check "SpringBoard publishes the rules for the apps: each rule's state, then the count with the next generation, posted; the wanted state at each change; no rules with the switch off or KeyPilot in" \
  "fn 'static void DMCSPublishStates(void) {' $C && grep -q 'packed\[i\] = MSBDCSPackRule(gCSRules\[i\]);' \$W/fn && grep -q 'snprintf(name, sizeof name, kMSBDCSRuleStateFmt, i);' \$W/fn \
   && grep -q 'uint64_t live = DMCSStateGet(&gCSRulesToken, kMSBDCSRulesState);' \$W/fn && grep -q 'uint64_t rs = MSBDCSRulesNext(live, n);' \$W/fn && grep -q 'notify_post(kMSBDCSRulesState);' \$W/fn \
   && grep -q 'DMCSStateSet(&gCSWantedToken, kMSBDCSWantedState, wanted);' \$W/fn && grep -q 'unsigned n = gCSSwitch && !gCSKeyPilot ? ' \$W/fn \
   && [ \$(grep -n 'DMCSStateSet(&gCSRulesToken' \$W/fn | cut -d: -f1) -gt \$(grep -n 'DMCSStateSet(&gCSRuleTokens' \$W/fn | cut -d: -f1) ] \
   && fn 'static void DMCSPublish(void) {' $C && grep -q 'DMCSPublishStates();' \$W/fn"
check "  ... and runs what an app posts (a run name per rule), only while taken, once per key (DMCSRunOnce: the same key by a key command too runs once)" \
  "fn 'static void DMCSPublishStates(void) {' $C && grep -q 'snprintf(name, sizeof name, kMSBDCSRunFmt, i);' \$W/fn && grep -q '^ *notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) { DMCSRunFromApp(i); });' \$W/fn \
   && fn 'static void DMCSRunFromApp(unsigned i) {' $C && grep -q 'if (!DMCSAppsTaken() || i >= gCSRules.count) return;' \$W/fn && grep -q 'DMCSRunOnce(i, kMSBDCSWayApp);' \$W/fn"
check "  ... the published states checked live, not against SpringBoard's own copies: the rules' state, each slot the apps read and the wanted state, written again on any difference" \
  "fn 'static void DMCSPublishStates(void) {' $C && grep -q 'if (!MSBDCSPublishedSame(published, live, lastRS, n, packed, DMCSLiveSlot, NULL)) {' \$W/fn \
   && grep -q 'if (DMCSStateGet(&gCSWantedToken, kMSBDCSWantedState) != wanted) {' \$W/fn && ! grep -q 'BOOL same' \$W/fn && ! grep -q 'lastPacked\|lastWanted' $C \
   && fn 'static uint64_t DMCSLiveSlot(unsigned i, void \*ctx) {' $C && grep -q 'return DMCSStateGet(&gCSRuleTokens\[i\], name);' \$W/fn"
check "  ... the count counts (1.8.6 i05: the last rule off or deleted stayed published), and a publish clears every slot an app read before (the count written last, the count published)" \
  "fn 'static inline bool MSBDCSPublishedSame(' $R && grep -q 'if (!published || live != written || MSBDCSRulesCount(live) != count) return false;' \$W/fn \
   && fn 'static void DMCSPublishStates(void) {' $C && grep -q 'unsigned w = MSBDCSSlotsToWrite(n, lastCount, live);' \$W/fn && grep -q 'for (unsigned i = 0; i < w; i++) {' \$W/fn \
   && grep -q 'DMCSStateSet(&gCSRuleTokens\[i\], name, packed\[i\]);' \$W/fn && grep -q 'uint64_t packed\[kMSBDCSMaxRules\] = {0};' \$W/fn && grep -q 'lastRS = rs; lastCount = n; published = YES;' \$W/fn"
check "  ... the apps' wanted state is SpringBoard's run gate (1.8.6 i05): one answer, DMCSAppsTaken, published and asked at each run; no keyboard check of its own in the run" \
  "grep -q '^static BOOL DMCSAppsTaken(void) { return MSBDCSAppsWanted(DMCSWanted(), DMCSKeyboard()); }' $C && grep -q 'return taken && keyboard;' $R \
   && fn 'static void DMCSPublishStates(void) {' $C && grep -q 'uint64_t wanted = DMCSAppsTaken() ? 1 : 0;' \$W/fn && ! grep -q 'DMCSWanted()' \$W/fn \
   && fn 'static void DMCSRunFromApp(unsigned i) {' $C && ! grep -q 'DMHardwareKeyboardAttached\|DMCSWanted()' \$W/fn \
   && fn 'static BOOL DMCSKeyboard(void) {' $C && grep -q 'return DMHardwareKeyboardAttached();' \$W/fn \
   && awk '/#if DEBUG/{d=1} d&&/msb-fakekb/{ok=1} /#endif/{d=0} END{exit !ok}' \$W/fn && [ \$(grep -c 'msb-fakekb' $C) = 2 ] \
   && fn 'static int MABCSConfirm(long usage, unsigned long long flags, int rule) {' $B && grep -q 'kMSBDCSWantedState) != 1) return -1;' \$W/fn"
check "  ... republished when a hardware keyboard comes or goes: GraphicsServices' post, and the 0.2 s tick's compare (a publish only on a change)" \
  "fn 'static void DMCSKeyboardTick(void) {' $C && grep -q 'if (!gCSStarted) return;' \$W/fn && grep -q 'if (now == last) return;' \$W/fn && grep -q 'DMCSPublishStates();' \$W/fn \
   && grep -q 'int now = DMCSKeyboard() ? 1 : 0;' \$W/fn \
   && grep -q 'notify_register_dispatch(MSBD_KEYBOARD_CHANGED, &keyboard, dispatch_get_main_queue(), ^(int t) { DMCSKeyboardTick(); });' $C \
   && grep -q '#define MSBD_KEYBOARD_CHANGED \"GSEventHardwareKeyboardAvailabilityChangedNotification\"' ../common/InputDevices.h \
   && grep -q '^    DMCSKeyboardTick();' $S && grep -q '^static void DMCSKeyboardTick(void);' $S \
   && [ \$(grep -n '^    DMCSKeyboardTick();' $S | cut -d: -f1) -gt \$(grep -n '^static void DMTickBody(void) {' $S | cut -d: -f1) ]"
check "  ... checked again on each post of the rules' or the wanted state, and whenever the app in front changes (the 0.2 s tick)" \
  "fn 'static void DMCustomShortcutsStart(void) {' $C && grep -q 'notify_register_dispatch(kMSBDCSRulesState, &rules, dispatch_get_main_queue(), ^(int t) { DMCSPublishStates(); });' \$W/fn \
   && grep -q 'notify_register_dispatch(kMSBDCSWantedState, &wanted, dispatch_get_main_queue(), ^(int t) { DMCSPublishStates(); });' \$W/fn \
   && fn 'static void DMCSFrontChanged(void) {' $C && grep -q 'if (!gCSStarted) return;' \$W/fn && grep -q 'DMCSPublishStates();' \$W/fn \
   && grep -q '^    if (realChanged || frontChanged) DMCSFrontChanged();' $S && grep -q '^static void DMCSFrontChanged(void);' $S"
check "  ... a run posted by an app only with a hardware keyboard attached, at a press's pace (the bucket: 4 at once, one back each 0.15 s), then once per key by the app's way" \
  "fn 'static void DMCSRunFromApp(unsigned i) {' $C && grep -q 'if (!DMCSAppsTaken() || i >= gCSRules.count) return;' \$W/fn && grep -q 'static MSBDCSFromAppBucket bucket;' \$W/fn \
   && grep -q 'if (!MSBDCSFromAppTake(&bucket, CACurrentMediaTime() \* 1000.0)) return;' \$W/fn \
   && [ \$(grep -n 'MSBDCSFromAppTake' \$W/fn | cut -d: -f1) -lt \$(grep -n 'DMCSRunOnce(i, kMSBDCSWayApp);' \$W/fn | cut -d: -f1) ] \
   && [ \$(grep -n 'DMCSAppsTaken()' \$W/fn | cut -d: -f1) -lt \$(grep -n 'MSBDCSFromAppTake' \$W/fn | cut -d: -f1) ] \
   && ! grep -q 'kDMCSFromAppGap\|lastPost' $C && grep -q '#define kMSBDCSFromAppBurst 4.0' $R && grep -q '#define kMSBDCSFromAppEveryMs 150.0' $R"
check "  ... SpringBoard's own presses, key commands and the debug run come SpringBoard's way (a held key runs once there); only the apps' posts the app's way" \
  "[ \$(grep -c 'DMCSRunOnce((NSUInteger)i, kMSBDCSWaySpringBoard)' $C) = 3 ] && [ \$(grep -c 'kMSBDCSWayApp' $C) = 1 ] \
   && fn 'static void DMCSPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $C && grep -q 'DMCSRunOnce((NSUInteger)i, kMSBDCSWaySpringBoard)' \$W/fn \
   && fn 'static void DMCSKeyCommandFired(id self, SEL _cmd, id sender) {' $C && grep -q 'DMCSRunOnce((NSUInteger)i, kMSBDCSWaySpringBoard);' \$W/fn \
   && [ \$(grep -c 'DMCSRunOnce(' $C) = 5 ]"
check "  ... a recording with Settings not in front is ended by SpringBoard (checked again half a second later), on each change of the front app and of the recording" \
  "fn 'static void DMCSRecordingCheck(void) {' $C && [ \$(grep -c 'if (!DMCSRecording() || DMCSSettingsInFront()) return;' \$W/fn) = 2 ] \
   && grep -q 'DMCSStateSet(&token, kMSBDCSRecordingNote, 0);' \$W/fn && grep -q 'notify_post(kMSBDCSRecordingNote);' \$W/fn \
   && fn 'static BOOL DMCSSettingsInFront(void) {' $C && grep -q 'com.apple.Preferences' \$W/fn \
   && fn 'static void DMCSFrontChanged(void) {' $C && grep -q 'DMCSRecordingCheck();' \$W/fn \
   && grep -q 'notify_register_dispatch(kMSBDCSRecordingNote, &rec, dispatch_get_main_queue(), ^(int t) { DMCSPublish(); DMCSRecordingCheck(); });' $C"
check "  ... and Settings' page stops recording when Settings leaves the front (resign active, scene deactivate), not only when the page goes" \
  "fn '- (void)viewDidLoad {' $P && grep -q 'addObserver:self selector:@selector(msLeftFront:) name:UIApplicationWillResignActiveNotification object:nil' \$W/fn \
   && grep -q 'addObserver:self selector:@selector(msLeftFront:) name:UISceneWillDeactivateNotification object:nil' \$W/fn \
   && fn '- (void)msLeftFront:(NSNotification \*)n {' $P && grep -q '\[self msStopRecording\];' \$W/fn"
check "The app forgets the shortcut keys held when it loses the keyboard: resign active, scene deactivate, no key window of its own left" \
  "fn 'static void MABCSStart(void) {' $B && grep -q 'addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:mq usingBlock:^(NSNotification \*n) { MABCSKeyboardGone(); }' \$W/fn \
   && grep -q 'addObserverForName:UISceneWillDeactivateNotification object:nil queue:mq usingBlock:^(NSNotification \*n) { MABCSKeyboardGone(); }' \$W/fn \
   && grep -q 'addObserverForName:UIWindowDidResignKeyNotification' \$W/fn && grep -q 'if (!MABCSAppHasKeyWindow()) MABCSKeyboardGone();' \$W/fn \
   && grep -q '^static void MABCSKeyboardGone(void) { MSBDCSKeyForget(&gMABCSHeld); }' $B"
check "  ... the key commands kept for apps without our bridge, made sturdier: tried again while SpringBoard's application is not up, a skipped registration logged, their flags masked" \
  "fn 'static void DMCSPublish(void) {' $C && grep -q 'dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC), dispatch_get_main_queue(), ^{ pending = NO; DMCSPublish(); });' \$W/fn \
   && grep -q 'if (tries >= 60)' \$W/fn && grep -q '} else DMLog(@\"\[shortcuts\] -_updateSerializableKeyCommandsForResponder: differs here' \$W/fn \
   && grep -q 'modifierFlags:(UIKeyModifierFlags)MSBDCSMods(\[gCSRules\[i\]\[@\"modifiers\"\] unsignedLongLongValue\])' $C"
check "  ... the debug dump shows what the apps read (wanted, count, generation, each rule's state) and SpringBoard's keyboard" \
  "fn 'static void DMCustomShortcutsDebug(NSString \*cmd) {' $C && grep -q 'published: wanted' \$W/fn && grep -q 'kMSBDCSRuleStateFmt' \$W/fn && grep -q 'DMCSKeyboard(), DMCSAppsTaken()' \$W/fn"
check "Settings: recording takes the page's presses while SpringBoard's shortcuts wait; Escape stops; this tweak's own keys and a second use of the same keys refused, in words" \
  "fn '- (void)pressesBegan:(NSSet<UIPress \*> \*)presses withEvent:(UIPressesEvent \*)event {' $P && grep -q 'int why = MSBDCSCheck(usage, chars.UTF8String, mods);' \$W/fn \
   && grep -q 'is a Window Tiling Shortcut' \$W/fn && grep -q 'switches desktops in the Mac Switcher' \$W/fn && grep -q 'is already one of your shortcuts' \$W/fn \
   && fn '- (void)msRecord:(PSSpecifier \*)s {' $P && grep -q 'MSCSSetRecording(YES);' \$W/fn && fn '- (void)msStopRecording {' $P && grep -q 'MSCSSetRecording(NO);' \$W/fn"
check "  ... the switch off by default, its own domain and notification; the import copies KeyPilot's rules without shell commands and says what it left out" \
  "grep -q '\[sw setProperty:@NO forKey:@\"default\"\];' $P && grep -q '\[sw setProperty:@kMSBDCSChanged forKey:@\"PostNotification\"\];' $P \
   && fn '- (void)msImport:(PSSpecifier \*)s {' $P && grep -q 'MSBDCSImport(MSCSKeyPilotRules(), MSCSRules(), &shell, &other);' \$W/fn && grep -q 'shell command' \$W/fn \
   && grep -q 'if (kind == kMSBDCSActShell) { shell++; continue; }' $R"
check "  ... the page says the shortcuts work with any app in front, and that in recovery apps (no bridge) only Command, Control or Globe ones do" \
  "grep -q 'whichever app is in front. In Sileo, Filza and other recovery apps, only shortcuts with Command, Control or Globe work.' $P"
check "  ... the credit on the page; the Keyboard page's row to it, KeyPilot's own row (OPEN) only while it is installed" \
  "grep -q 'Custom Shortcuts is based on KeyPilot by wanghuangjie.' $P && fn 'NSArray \*MSKeysShortcutSpecifiers(id target) {' $KB && grep -q '\[s addObject:MSCustomShortcutsRowSpecifier()\];' \$W/fn \
   && grep -q 'if (!kpInstalled) return s;' \$W/fn"
check "  ... the layouts' page from Settings' own values and titles (plain validValues / validTitles properties crashed its choice page, M1 k02)" \
  "grep -q '\[l setValues:vals titles:tits shortTitles:tits\];' $P && ! grep -q 'forKey:@\"validValues\"' $P"
check "Acknowledgements at the end of the Status Bar page: KeyPilot, its license as the package carries it, its page" \
  "grep -q 'detail:\[MSBAcknowledgementsController class\] cell:PSLinkCell' $RL && grep -q 'based on KeyPilot by wanghuangjie, used under the MIT License' $A \
   && grep -q 'usr/lib/MacStatusBarAndDock/third_party/%@/LICENSE' $A && grep -q 'https://github.com/wanghuangjie/KeyPilot' $A"
# Made to fail: the rules with one thing broken (a shortcut's key-up passed to the app, Caps Lock counted in the match, SpringBoard's word not asked,
# a key-up gone to another app leaving the key held for good, a plain press of a key counted as a shortcut's repeat, the held keys not forgotten;
# 1.8.6 i05: the published count not compared, the slots an app read before not cleared, the keyboard left out of the apps' wanted state;
# review 1.8.6: an app's post counted as its own repeat, the bucket too slow or unbounded or drained by refused posts, a key come two ways not
# paired or paired twice)
# must fail the C test, so the test above really checks each of them.
mutant() {
  local M="$W/m-$1"; mkdir -p "$M/common" "$M/tools"; ln -s "$(cd ../statusbar && pwd)" "$M/statusbar"; cp test-customshortcuts.c "$M/tools/"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' \
    ../common/CustomShortcutsRule.h "$M/common/CustomShortcutsRule.h" "$2" "$3" || return 1
  clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$M/t" "$M/tools/test-customshortcuts.c" || return 1
  ! "$M/t" > "$M/out"
}
check "made to fail: a shortcut's key-up passed to the app" "mutant up 'if (!isDown) { MSBDCSKeySetBit(h->held, usage, 0); return MSBDCSKeyTake; }' 'if (!isDown) { MSBDCSKeySetBit(h->held, usage, 0); return MSBDCSKeyPass; }'"
check "made to fail: Caps Lock and the keypad bit counted in the match" "mutant caps 'MSBDCSSame(MSBDCSPackedUsage(rules[i]), MSBDCSPackedMods(rules[i]), usage, flags)' '(MSBDCSPackedUsage(rules[i]) == usage && MSBDCSPackedMods(rules[i]) == flags)'"
check "made to fail: SpringBoard's word (taken, recording, the rules' generation) not asked" "mutant confirm 'if (i >= 0 && confirm) i = confirm(usage, flags, i);' '(void)confirm;'"
check "made to fail: a key-up gone to another app leaves the key held for good" "mutant lost 'MSBDCSKeySetBit(h->held, usage, 0);   // (its key-up went elsewhere: a new press)' 'return MSBDCSKeyTake;'"
check "made to fail: a shortcut key's down counted as its repeat without its modifiers, at any time inside 2.5 s" "mutant chord '(chordDown || gap <= kMSBDCSRepeatMs)' '(chordDown || gap <= kMSBDCSHeldLostMs)'"
check "made to fail: the modifiers a shortcut's key went down with not kept" "mutant mods 'h->mods[usage] = MSBDCSMods(flags);' '(void)0;'"
check "made to fail: the held keys not forgotten when the app loses the keyboard" "mutant forget 'if (h) memset(h, 0, sizeof *h);' '(void)h;'"
check "made to fail: the published count not compared (the i05 bug: the last rule off kept published)" "mutant count '!published || live != written || MSBDCSRulesCount(live) != count' '!published || live != written'"
check "made to fail: a publish leaves the slots past the count published before (after a respring)" "mutant respring 'unsigned n = count, lc = MSBDCSRulesCount(live);' 'unsigned n = count, lc = 0;'"
check "made to fail: a publish leaves the slots past the count SpringBoard wrote last" "mutant lastcount 'if (lastCount > n) n = lastCount;' '(void)lastCount;'"
check "made to fail: the keyboard left out of the apps' wanted state (the i05 bug: kept by the app, refused by SpringBoard)" "mutant keyboard 'return taken && keyboard;' 'return taken;'"
check "made to fail: an app's post counted as its own repeat (the review's bug: a second Option-J 0.3 s later kept and not run)" "mutant apprepeat 'if (way == kMSBDCSWaySpringBoard && mine->seen && mine->rule == rule' 'if (mine->seen && mine->rule == rule'"
check "made to fail: the bucket refilled at one each 0.25 s (presses 0.15 s apart dropped after the first few)" "mutant slow '#define kMSBDCSFromAppEveryMs 150.0' '#define kMSBDCSFromAppEveryMs 250.0'"
check "made to fail: the bucket with no top (a flood after a long quiet runs hundreds)" "mutant notop 'if (t > kMSBDCSFromAppBurst) t = kMSBDCSFromAppBurst;' '(void)0;'"
check "made to fail: a refused post takes from the bucket (a flood leaves the next real press dropped)" "mutant drain 'if (t < 1.0) return false;' 'if (t < 1.0) { b->tokens = t - 1.0; return false; }'"
check "made to fail: the same key come the other way not taken as that key (a Command chord in an app runs twice)" "mutant twoways 'if (other->seen && !other->paired && other->rule == rule' 'if (0 && other->seen && !other->paired && other->rule == rule'"
check "made to fail: an arrival paired twice (the next press of a Command chord in an app dropped)" "mutant pairedtwice 'other->seen && !other->paired && other->rule' 'other->seen && other->rule'"
[ $fails = 0 ] && echo "test-customshortcuts: wiring checks pass" || { echo "test-customshortcuts: wiring checks FAILED"; exit 1; }
