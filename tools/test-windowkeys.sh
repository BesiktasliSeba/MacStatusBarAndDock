#!/bin/bash
# Mac test of Window Tiling Keys (1.8.3 item 3: macOS 15's fixed tiling shortcuts, the Globe key as Fn; statusbar/WindowKeysRule.h, test-windowkeys.c),
# then the sites in the code as built: the keys read from SpringBoard's own presses while the switch is on and an engine runs, iPadOS's own
# handling of the same keys left out then; each key running the Window menu's ways (WindowAPI.h) unless SpringBoard is busy; Return to Previous
# Size's record taken where a layout tiles a window; the Settings row on the Keyboard page (our page and Apple's on 18).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/twk" test-windowkeys.c
"$W/twk"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
K=../statusbar/WindowKeys.h; A=../statusbar/WindowAPI.h; S=../statusbar/StatusBar.x; KB=../macsettings/KeyboardSettings.x; G=../macsettings/AppleGroups18.x
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
check "Globe-Control-R puts the record back inside today's desktop on every path -- our own windows, Stage Manager, the engines --: one made before a turn stood partly off the screen (audit 1.8.3 M5)" \
  "fn 'static void DMWindowBackFromTile(NSString *why) {' $K \
   && grep -q 'CGRect f = MSBDWinPrevBackFrame(rec.CGRectValue, DMLayoutFrameInArea(@\"fill\", DMNativeDesktop(), \\[UIScreen mainScreen\\].bounds.size), nw.minSize);' \$W/fn \
   && grep -q 'CGRect f = MSBDWinPrevBackFrame(rec.CGRectValue, DMSMLayoutFrameIn(@\"fill\", u, scr), CGSizeZero);' \$W/fn \
   && grep -q 'BOOL ok = DMSMApplyPlacesIn(@{key: \\[NSValue valueWithCGRect:f\\]}, stage);' \$W/fn && grep -q 'DMTitleRecordSMTo(key, stage, f);' \$W/fn \
   && grep -q 'CGRect f = MSBDWinPrevBackFrame(rec.CGRectValue, DMLayoutFrame(@\"fill\"), DMEngineWindowMin());' \$W/fn \
   && ! grep -q 'CGRect f = rec.CGRectValue;' \$W/fn && ! grep -q 'DMSMApplyPlacesIn(@{key: rec}, stage)' \$W/fn"
check "the keys from SpringBoard's own presses (the Globe chords iPadOS hands to SpringBoard; none of them is one of its key commands), each row matched by its key -- the arrows' place, the letter the layout types -- and the exact modifiers" \
  "fn 'static void DMWindowKeysInstall(void) {' $K && grep -q 'MSHookMessageEx(sb, @selector(pressesBegan:withEvent:), (IMP)DMWinKeysPressesBegan, (IMP \*)&o_WinKeysPressesBegan);' \$W/fn \
   && fn 'static void DMWinKeysPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $K \
   && grep -q 'int row = k ? MSBDWinKeyRowFor(MSBDWinKeyFor((long)k.keyCode, k.charactersIgnoringModifiers.UTF8String), (unsigned long long)k.modifierFlags) : -1;' \$W/fn \
   && grep -q 'if (p.timestamp == lastTime && (long)k.keyCode == lastCode) continue;' \$W/fn && ! grep -q 'p == lastPress' \$W/fn"
check "  ... with an app in front backboardd hands SpringBoard only the keys its key commands name (15.6.1: Globe-Control-F went to the app): our fifteen in SpringBoard's own list while offered, registered again at each change; a key command that runs runs the same row, once" \
  "fn 'static NSArray *DMWinKeysKeyCommands(id self, SEL _cmd) {' $K && grep -q 'if (gWinKeyCmds.count != kMSBDWinKeyRowCount || !DMWinKeysWanted()) return orig;' \$W/fn && grep -q '\[all addObjectsFromArray:gWinKeyCmds\];' \$W/fn \
   && fn 'static void DMWindowKeysInstall(void) {' $K && grep -q 'MSHookMessageEx(sb, @selector(keyCommands), (IMP)DMWinKeysKeyCommands, (IMP \*)&o_WinKeysKeyCommands);' \$W/fn \
   && grep -q 'UIKeyCommand \*c = \[UIKeyCommand keyCommandWithInput:DMWinKeyInput(kMSBDWinKeyRows\[i\].key) modifierFlags:(UIKeyModifierFlags)kMSBDWinKeyRows\[i\].mods action:sel\];' \$W/fn \
   && fn 'static void DMWindowKeysPublish(void) {' $K && grep -q 'if (now != registered && DMWindowKeysRegister(now)) registered = now;' \$W/fn \
   && fn 'static BOOL DMWindowKeysRegister(BOOL offered) {' $K && grep -q '_updateSerializableKeyCommandsForResponder:' \$W/fn \
   && fn 'static BOOL DMWinKeyRun(size_t i) {' $K && grep -q 'if (i == lastRow && at - lastAt < 0.15) return YES;' \$W/fn"
check "  ... ours never handed on; presses that came with one of ours and are none of ours handed on without it (review 1.8.3 F1); none of ours: the set as it came" \
  "fn 'static void DMWinKeysPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $K \
   && grep -q 'if (row < 0) { if (!others) others = \[NSMutableSet set\]; \[others addObject:p\]; continue; }' \$W/fn \
   && grep -q 'if (others.count == presses.count) { o_WinKeysPressesBegan(self, _cmd, presses, event); return; }' \$W/fn \
   && grep -q 'if (others.count) o_WinKeysPressesBegan(self, _cmd, others, event);' \$W/fn && ! grep -q 'if (ours) return;' \$W/fn"
check "  ... taken only with the switch on and an engine of ours running -- or one of our own windows in front, with no engine too, as the Window menu and the window API lay it out (review 1.8.3 P2-9) -- (each press asks); one of ours is not handed on (iPadOS's own same keys -- 15's Split View -- do not run under it)" \
  "grep -q 'static BOOL DMWinKeysWanted(void) { return gWindowKeysOn && (DMActiveEngine() != DMEngineNone || DMSMEngine() || DMNativeActiveApp() != nil); }' $K && grep -q 'if (presses.count && DMWinKeysWanted()) {' $K \
   && fn 'static BOOL DMWinKeyRun(size_t i) {' $K && grep -q 'if (!DMNativeActiveApp() && !(DMActiveEngine() != DMEngineNone || DMSMEngine())) return NO;' \$W/fn"
check "audit 1.8.3 L2: a key that can't act now (the switch off, SpringBoard busy, no engine and none of our windows) is handed on, not swallowed; one that acted (or the same key again) is not" \
  "fn 'static BOOL DMWinKeyRun(size_t i) {' $K && grep -q 'if (i >= kMSBDWinKeyRowCount || !gWindowKeysOn) return NO;' \$W/fn && grep -q 'not now (%@): the key goes on\", title, busy\]); return NO; }' \$W/fn \
   && awk '/^static BOOL DMWinKeyRun\(size_t i\) \{/{f=1} f&&/^}/{print prev; exit} f{prev=\$0}' $K | grep -q 'return YES;' \
   && fn 'static void DMWinKeysPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $K \
   && grep -q 'if (!DMWinKeyRun((size_t)row)) { if (!others) others = \[NSMutableSet set\]; \[others addObject:p\]; }' \$W/fn"
check "audit 1.8.3 L3: on Stage Manager an app's key (the front window another app's) is its newest window before the open frames and the records are read -- Return to Previous Size, Center, the arrangements and the record a layout takes" \
  "fn 'static void DMWinPrevNoteSM(NSString \*key, id stage) {' $K && awk '/key = DMSMWindowKeyOf\(key\);/{a=NR} /DMSMOpenWindowFrames\(\)\[key\]/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && [ \"\$(grep -c 'if (!\[DMSMKeyBundle(key) isEqualToString:bundleID\]) key = bundleID;' $K)\" = \"\$(grep -A1 'if (!\[DMSMKeyBundle(key) isEqualToString:bundleID\]) key = bundleID;' $K | grep -c 'key = DMSMWindowKeyOf(key);')\" ] \
   && grep -A1 'if (!\[DMSMKeyBundle(frontKey) isEqualToString:front\]) frontKey = front;' $K | grep -q 'frontKey = DMSMWindowKeyOf(frontKey);'"
check "audit 1.8.3 L4: the arrangements' windows behind are other apps' only on every engine -- Stage Manager leaves out every window of the front app, as Aerial, Zetsu and MilkyWay4 do" \
  "fn 'static void DMArrangeWindows(const char \*const \*slots, int count, NSString \*why) {' $K && grep -q 'if (k && \[onScreen containsObject:k\] && !\[DMSMKeyBundle(k) isEqualToString:front\] && !DMSMAttrsFullScreen(map\[it\])) \[items addObject:it\];' \$W/fn \
   && grep -q '|| !b.length || \[b isEqualToString:front\]) continue;' \$W/fn && ! grep -q '!DMSMKeyCovers(frontKey, k)' \$W/fn"
check "a key: the volume and backlight chords told (no tap), nothing while SpringBoard is busy, then the row's action -- the Window menu's layout, an arrangement, the way back" \
  "fn 'static BOOL DMWinKeyRun(size_t i) {' $K && grep -q 'notify_post(kMSBDModTapUsedNote);' \$W/fn && grep -q 'NSString \*busy = DMWindowAPIBusyWhy();' \$W/fn \
   && grep -q 'case kMSBDWinKeyActLayout: DMLayoutFrontWindow(@(a.slots\[0\]), title); break;' \$W/fn && grep -q 'case kMSBDWinKeyActArrange: DMArrangeWindows(a.slots, a.count, title); break;' \$W/fn \
   && grep -q 'case kMSBDWinKeyActPrevious: DMWindowBackFromTile(title); break;' \$W/fn && grep -q 'case kMSBDWinKeyActCenter: DMCenterFrontWindow(title); break;' \$W/fn"
check "Globe-Control-C centres the window at its own size (macOS 15's Center), on every engine and our own windows; the Window menu's Center is its middle place as before" \
  "fn 'static void DMCenterFrontWindow(NSString *why) {' $K && [ \$(grep -c 'MSBDWinCenterKeepingSize(' \$W/fn) = 3 ] && grep -q 'BOOL ok = DMSMApplyPlacesIn(@{key: \[NSValue valueWithCGRect:f\]}, stage);' \$W/fn \
   && grep -q 'DMAerialMoveStage(v, f, nil);' \$W/fn && grep -q 'DMSMAttrsFullScreen(attrs)' \$W/fn \
   && grep -q '\[items addObject:R(e\[0\], nil, ^{ DMNativeLayout(w, name); })\];' $S"
check "Return to Previous Size's records only while something can go back with them -- the window keys' Globe-Control-R (a title bar's Fill has its own frame from before: regression F2): with the keys off nothing is read or kept (review 1.8.3 F7)" \
  "grep -q 'static BOOL DMWinPrevWanted(void) { return gWindowKeysOn; }' $K && fn 'static void DMWinPrevNoteActive(NSString *bundleID, NSString *smKey) {' $K && grep -q 'if (!bundleID.length || !DMWinPrevWanted()) return;' \$W/fn \
   && fn 'static void DMWinPrevNoteSM(NSString *key, id stage) {' $K && grep -q 'if (!DMWinPrevWanted()) return;' \$W/fn && grep -q 'DMWinPrevPruneSM();' \$W/fn \
   && fn 'static void DMWinPrevNoteView(UIView *v, BOOL tiledNow, CGRect now) {' $K && grep -q 'if (!DMWinPrevWanted()) return;' \$W/fn \
   && fn 'static void DMWindowKeysApply(void) {' $K && grep -q 'if (!DMWinPrevWanted()) gSMWinPrev = nil;' \$W/fn"
check "  ... Stage Manager's map holds open windows only: a closed window's record goes when the next is taken (an app's key while any window of it is there)" \
  "fn 'static void DMSMRecordsPrune(NSMutableDictionary *map) {' $K && grep -q 'for (NSString \*w in present) if (DMSMKeyCovers(k, w)) { open = YES; break; }' \$W/fn && grep -q 'if (!open) \[map removeObjectForKey:k\];' \$W/fn \
   && grep -q 'static void DMWinPrevPruneSM(void) { DMSMRecordsPrune(gSMWinPrev); }' $K"
check "the keys offered or not, told to the volume and backlight chords when it changes (the switch read, the engine settling: each tick)" \
  "fn 'static void DMWindowKeysPublish(void) {' $K && grep -q 'int now = DMWinKeysWanted() ? 1 : 0;' \$W/fn && grep -q 'notify_set_state(token, MSBDWindowKeysOfferedState(now, getpid()));' \$W/fn \
   && grep -q 'notify_post(kMSBDWindowKeysOfferedNote);' \$W/fn && grep -q '    DMWindowKeysPublish();   // (Window Tiling Keys offered or not' $S"
check "Return to Previous Size: the record taken where a layout of the Window menu's tiles a window (not the green light's way back), and for our own windows" \
  "fn 'static void DMWindowLayout(NSString *name) {' $S && grep -q 'if (!gPreferRememberedFrame && MSBDWinIsTileName(name.UTF8String)) {' \$W/fn \
   && fn 'static void DMNativeLayout(DMNativeWindow *w, NSString *name) {' $A && grep -q 'if (MSBDWinIsTileName(name.UTF8String)) DMWinPrevNoteNative(w);' \$W/fn"
check "  ... going back: only while the window is still in a tile (the rule), on every engine with its own move" \
  "fn 'static void DMWindowBackFromTile(NSString *why) {' $K && [ \$(grep -c 'MSBDWinPrevOnReturn(' \$W/fn) = 3 ] && grep -q 'DMSMApplyPlacesIn(@{key: \\[NSValue valueWithCGRect:f\\]}, stage);' \$W/fn && grep -q 'DMAerialMoveStage(v, f, nil);' \$W/fn"
check "the arrangements: Stage Manager's windows in one request, the others' the front window by the Window menu's way, the next windows newest first, out of Fit's tiles" \
  "fn 'static void DMArrangeWindows(const char *const *slots, int count, NSString *why) {' $K && grep -q 'BOOL ok = DMSMApplyLayoutsIn(plan, stage);' \$W/fn \
   && grep -q 'for (UIView \*s in \[DMAerialStages() reverseObjectEnumerator\]) {' \$W/fn && grep -q 'DMFitGroupForget(DMStageBundle(s));' \$W/fn && grep -q 'gMoveKeepsOrder = YES;' \$W/fn"
check "Stage Manager: a window placed by the user leaves its Fit to Window tile and is a regular window over the tiles (it joins them again with the next window that opens), as DMFitGroupForget with the other engines -- never No Fit for good (review 1.8.3 P2-1); an app's key: only the window moved -- the Window menu's layouts (the window API's), Return to Previous Size, Center, the arrangements, a title bar's Fill / Zoom and back" \
  "fn 'static void DMSMFitLetGo(NSString *key) {' $S && grep -q 'if (!key.length || !DMFitEnabled()) return;' \$W/fn && grep -q 'key = DMSMWindowKeyOf(key);' \$W/fn && grep -q '\[gSMFitSlots removeObjectForKey:k\]' \$W/fn \
   && grep -q '\[gSMFitLoose addObject:key\];' \$W/fn && ! grep -q 'gSMFreeWindows addObject' \$W/fn && ! grep -q 'DMSMKeyCovers(key, k)' \$W/fn \
   && fn 'static NSString *DMSMWindowKeyOf(NSString *key) {' $S && grep -q 'id it = DMSMItemFor(DMSMStageOf(key), key, nil);' \$W/fn \
   && fn 'static void DMWindowLayout(NSString *name) {' $S && grep -q 'if (ok) DMSMFitLetGo(smKey);' \$W/fn \
   && fn 'static void DMWindowBackFromTile(NSString *why) {' $K && grep -q 'if (ok) DMSMFitLetGo(key);' \$W/fn \
   && fn 'static void DMCenterFrontWindow(NSString *why) {' $K && grep -q 'if (ok) DMSMFitLetGo(key);' \$W/fn \
   && fn 'static void DMArrangeWindows(const char *const *slots, int count, NSString *why) {' $K && grep -q 'if (ok) for (NSString \*k in plan) DMSMFitLetGo(k);' \$W/fn \
   && fn 'static void DMTitleTapSMWindow(NSString *key, NSString *why) {' ../statusbar/TitleBarTap.h && [ \$(grep -c 'if (ok) DMSMFitLetGo(key);' \$W/fn) = 3 ]"   # (Fill, Zoom -- its own place since 1.8.4.1 item 1 -- and back)
check "the switch: Settings > Keyboard, off by default, posted to SpringBoard and read with the other preferences" \
  "grep -q 'PSSpecifier \*keys = MSKeySwitch(target, @\"Window Tiling Shortcuts\", @kMSBDWindowKeysDomain, @kMSBDWindowKeysKey);' $KB \
   && grep -q 'CFPropertyListRef kr = CFPreferencesCopyValue(CFSTR(kMSBDWindowKeysKey), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
   && grep -q '\[s setProperty:@NO forKey:@\"default\"\];' $KB"
check "  ... at the end of our Keyboard page (after Apple's rows); on 18 with Mac Keys at the top of Apple's page" \
  "grep -q '\[s addObjectsFromArray:MSKeysShortcutSpecifiers(self)\];' $KB && awk '/if \(hw.count\) \[s addObjectsFromArray:hw\];/{a=NR} /\[s addObjectsFromArray:MSKeysShortcutSpecifiers\(self\)\];/{b=NR} END{exit !(a && b > a)}' $KB \
   && grep -q 'MSKeysGroupSpecifiers(prefs, @\"Mac Keys\", apple, prefs) arrayByAddingObjectsFromArray:MSKeysShortcutSpecifiers(prefs)' $G"
exit $fails
