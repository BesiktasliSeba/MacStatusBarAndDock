#!/bin/bash
# Mac test of Custom Shortcuts (1.8.5 item 2, based on KeyPilot by wanghuangjie; common/CustomShortcutsRule.h, test-customshortcuts.c), then the sites:
# SpringBoard takes the shortcuts through its own presses and key commands (no hook in the apps), only with the switch on, KeyPilot not installed and
# Settings not recording; each action the window API's, our app opening and our links; the Settings pages (recording, clashes refused, the import
# without shell actions, the credit); KeyPilot's license in the repository and the package; Acknowledgements.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tcs" test-customshortcuts.c
"$W/tcs"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
R=../common/CustomShortcutsRule.h; C=../statusbar/CustomShortcuts.h; S=../statusbar/StatusBar.x; P=../macsettings/CustomShortcuts.x; KB=../macsettings/KeyboardSettings.x
A=../statusbar/macstatusbarprefs/MSBAcknowledgementsController.m; RL=../statusbar/macstatusbarprefs/MSBRootListController.m
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
check "KeyPilot's license: its MIT text in the repository (third_party/KeyPilot/LICENSE), copied into the package next to our libraries; the notice in the ported rules" \
  "grep -q 'Copyright (c) 2026 wanghuangjie' ../third_party/KeyPilot/LICENSE && grep -q 'Permission is hereby granted, free of charge' ../third_party/KeyPilot/LICENSE \
   && grep -q 'cp -f third_party/KeyPilot/LICENSE \"\$\$P/third_party/KeyPilot/LICENSE\"' ../Makefile \
   && grep -q 'Portions: Copyright (c) 2026 wanghuangjie. MIT License:' $R && grep -q 'The above copyright notice and this permission notice shall be included' $R"
check "SpringBoard: the shortcuts from its own presses and its key commands (as Window Tiling Keys), hooked once there is one to take; no hook of the apps' sendEvent:" \
  "fn 'static BOOL DMCSInstall(void) {' $C && grep -q 'MSHookMessageEx(sb, @selector(pressesBegan:withEvent:), (IMP)DMCSPressesBegan, (IMP \*)&o_CSPressesBegan);' \$W/fn \
   && grep -q 'MSHookMessageEx(sb, @selector(keyCommands), (IMP)DMCSKeyCommands, (IMP \*)&o_CSKeyCommands);' \$W/fn && ! grep -q 'selector(sendEvent:)\|%hook UIApplication' $C \
   && fn 'static void DMCSLoad(void) {' $C && grep -q 'if (gCSSwitch && usable.count && DMCSInstall()) DMCSMakeKeyCommands();' \$W/fn"
check "  ... taken only with the switch on, KeyPilot not installed, a rule to run and Settings not recording; a press of none of them handed on as it came" \
  "grep -q 'static BOOL DMCSWanted(void) { return gCSSwitch && !gCSKeyPilot && gCSRules.count && !DMCSRecording(); }' $C \
   && fn 'static void DMCSPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $C && grep -q 'if (presses.count && DMCSWanted()) {' \$W/fn \
   && grep -q 'if (others.count == presses.count) { o_CSPressesBegan(self, _cmd, presses, event); return; }' \$W/fn"
check "  ... matched by the key and the modifiers with Globe (MSBDCSSame on MSBDCSMods), each rule once per key" \
  "fn 'static NSInteger DMCSRuleFor(UIKey \*k) {' $C && grep -q 'unsigned long long m = MSBDCSMods((unsigned long long)k.modifierFlags);' \$W/fn && grep -q 'MSBDCSSame(' \$W/fn \
   && fn 'static BOOL DMCSRunOnce(NSUInteger i) {' $C && grep -q 'BOOL same = i == lastRule \&\& at - lastAt < 0.5;' \$W/fn && grep -q 'if (same) return YES;' \$W/fn"
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
check "Settings: recording takes the page's presses while SpringBoard's shortcuts wait; Escape stops; this tweak's own keys and a second use of the same keys refused, in words" \
  "fn '- (void)pressesBegan:(NSSet<UIPress \*> \*)presses withEvent:(UIPressesEvent \*)event {' $P && grep -q 'int why = MSBDCSCheck(usage, chars.UTF8String, mods);' \$W/fn \
   && grep -q 'is a Window Tiling Shortcut' \$W/fn && grep -q 'switches desktops in the Mac Switcher' \$W/fn && grep -q 'is already one of your shortcuts' \$W/fn \
   && fn '- (void)msRecord:(PSSpecifier \*)s {' $P && grep -q 'MSCSSetRecording(YES);' \$W/fn && fn '- (void)msStopRecording {' $P && grep -q 'MSCSSetRecording(NO);' \$W/fn"
check "  ... the switch off by default, its own domain and notification; the import copies KeyPilot's rules without shell commands and says what it left out" \
  "grep -q '\[sw setProperty:@NO forKey:@\"default\"\];' $P && grep -q '\[sw setProperty:@kMSBDCSChanged forKey:@\"PostNotification\"\];' $P \
   && fn '- (void)msImport:(PSSpecifier \*)s {' $P && grep -q 'MSBDCSImport(MSCSKeyPilotRules(), MSCSRules(), &shell, &other);' \$W/fn && grep -q 'shell command' \$W/fn \
   && grep -q 'if (kind == kMSBDCSActShell) { shell++; continue; }' $R"
check "  ... the credit on the page; the Keyboard page's row to it, KeyPilot's own row (OPEN) only while it is installed" \
  "grep -q 'Custom Shortcuts is based on KeyPilot by wanghuangjie.' $P && fn 'NSArray \*MSKeysShortcutSpecifiers(id target) {' $KB && grep -q '\[s addObject:MSCustomShortcutsRowSpecifier()\];' \$W/fn \
   && grep -q 'if (!kpInstalled) return s;' \$W/fn"
check "  ... the layouts' page from Settings' own values and titles (plain validValues / validTitles properties crashed its choice page, M1 k02)" \
  "grep -q '\[l setValues:vals titles:tits shortTitles:tits\];' $P && ! grep -q 'forKey:@\"validValues\"' $P"
check "Acknowledgements at the end of the Status Bar page: KeyPilot, its license as the package carries it, its page" \
  "grep -q 'detail:\[MSBAcknowledgementsController class\] cell:PSLinkCell' $RL && grep -q 'based on KeyPilot by wanghuangjie, used under the MIT License' $A \
   && grep -q 'usr/lib/MacStatusBarAndDock/third_party/%@/LICENSE' $A && grep -q 'https://github.com/wanghuangjie/KeyPilot' $A"
[ $fails = 0 ] && echo "test-customshortcuts: wiring checks pass" || { echo "test-customshortcuts: wiring checks FAILED"; exit 1; }
