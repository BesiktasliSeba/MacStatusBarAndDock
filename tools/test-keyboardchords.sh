#!/bin/bash
# Mac test of the keyboard features' one table (1.8.7, KT 11 Nov: conflicts made clear and resolved; common/KeyboardChords.h, test-keyboardchords.c),
# then the sites: Window Tiling's rows and the Mac Switcher's Control-arrows leave to your own shortcuts the keys they take (presses handed on,
# key commands left out); SpringBoard reads yours (Custom Shortcuts' taken, KeyPilot's while installed) and tells the key tweaks in every app; the
# key left of 1, Tab and Shift + =/- left to yours, Globe left alone by Tab and the screen keys; the volume and backlight taps waiting for their
# release while a shortcut of yours starts with them; Settings says which feature has the keys (the Keyboard page's footers, the recorder) in
# public text with no em dash. Last, copies of the table with one thing broken must fail the C test.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tkc" test-keyboardchords.c
"$W/tkc"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
KC=../common/KeyboardChords.h; K=../statusbar/WindowKeys.h; M=../statusbar/MacSwitcher.h; C=../statusbar/CustomShortcuts.h; S=../statusbar/StatusBar.x
V=../volumeglobe/VolumeGlobe.x; B=../brightnesskey/BrightnessKey.x; G=../graveescape/GraveEscape.x; TM=../tabmute/TabMute.x
KB=../macsettings/KeyboardSettings.x; P=../macsettings/CustomShortcuts.x; G18=../macsettings/AppleGroups18.x
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
check "SpringBoard keeps yours in one place, read where the shortcuts are read (the switch on and KeyPilot out for ours; KeyPilot's while installed), and again when KeyPilot's change" \
  "grep -q '^static MSBDKCYoursSet gKCYours;' $S && grep -q '#include \"../common/KeyboardChords.h\"' $S \
   && fn 'static void DMKCYoursLoad(void) {' $C && grep -q 'MSBDKCYoursFromRules(&gKCYours, gCSRules, gCSSwitch && !gCSKeyPilot, DMKCKeyPilotRules(), gCSKeyPilot);' \$W/fn \
   && grep -q 'DMWindowKeysYoursChanged();' \$W/fn && grep -q 'DMMSWKeysRefresh();' \$W/fn \
   && fn 'static void DMCSLoad(void) {' $C && grep -q '    DMKCYoursLoad();' \$W/fn \
   && grep -q 'notify_register_dispatch(kMSBDKCKeyPilotReload, &kpReload, dispatch_get_main_queue(), ^(int t) { DMCSLoad(); });' $C \
   && grep -q '#define kMSBDKCKeyPilotReload \"com.whj.keypilot/reload\"' $C"
check "  ... published for the key tweaks only when it is not what SpringBoard means (a forged one put back), on its post and as the app in front changes" \
  "fn 'static void DMKCYoursPublish(void) {' $C && grep -q 'if (DMCSStateGet(&token, kMSBDKCYoursState) == want) return;' \$W/fn && grep -q 'notify_post(kMSBDKCYoursState);' \$W/fn \
   && grep -q 'notify_register_dispatch(kMSBDKCYoursState, &yours, dispatch_get_main_queue(), ^(int t) { DMKCYoursPublish(); });' $C \
   && fn 'static void DMCSFrontChanged(void) {' $C && grep -q 'DMKCYoursPublish();' \$W/fn"
check "  ... a KeyPilot rule run is no volume or backlight tap (its run names heard, read only)" \
  "fn 'static void DMKCYoursLoad(void) {' $C && grep -q 'snprintf(name, sizeof name, \"com.whj.keypilot/execute/%u\", i);' \$W/fn && grep -q 'notify_post(kMSBDModTapUsedNote);' \$W/fn"
check "Window Tiling: a press one of yours takes is handed on; the rows yours land on left out of the key commands and never run from one; told again when yours change" \
  "fn 'static void DMWinKeysPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $K \
   && grep -q 'if (row >= 0 && MSBDKCYoursTakes(&gKCYours, (long)k.keyCode, (unsigned long long)k.modifierFlags)) {' \$W/fn \
   && awk '/if \\(row >= 0 && MSBDKCYoursTakes/{a=NR} /if \\(row < 0\\) \\{ if \\(!others\\)/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && fn 'static NSArray *DMWinKeysKeyCommands(id self, SEL _cmd) {' $K && grep -q 'if (!MSBDKCYoursTakesWinRow(&gKCYours, (int)i)) \[all addObject:gWinKeyCmds\[i\]\];' \$W/fn && ! grep -q 'addObjectsFromArray:gWinKeyCmds' \$W/fn \
   && fn 'static void DMWinKeyCommandFired(id self, SEL _cmd, id sender) {' $K && grep -q '!MSBDKCYoursTakesWinRow(&gKCYours, (int)i)) DMWinKeyRun((size_t)i);' \$W/fn \
   && fn 'static void DMWindowKeysYoursChanged(void) {' $K && grep -q 'gWinKeysRegistered = -1;' \$W/fn"
check "review 1.8.7: while Settings records a shortcut Window Tiling's rows are its own: no key command of ours, none run, a press handed on; backboardd told at the start and the end (also from the tick)" \
  "grep -q '^static BOOL DMCSRecording(void);' $K && fn 'static NSArray *DMWinKeysKeyCommands(id self, SEL _cmd) {' $K && grep -q '    if (DMCSRecording()) return orig;' \$W/fn \
   && fn 'static void DMWinKeyCommandFired(id self, SEL _cmd, id sender) {' $K && awk '/if \\(DMCSRecording\\(\\)\\) return;/{a=NR} /DMWinKeyRun\\(\\(size_t\\)i\\)/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && fn 'static void DMWinKeysPressesBegan(id self, SEL _cmd, NSSet<UIPress \*> \*presses, UIPressesEvent \*event) {' $K && grep -q 'if (row >= 0 && DMCSRecording()) row = -1;' \$W/fn \
   && awk '/if \\(row >= 0 && DMCSRecording\\(\\)\\) row = -1;/{a=NR} /if \\(!DMWinKeyRun\\(\\(size_t\\)row\\)\\)/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && fn 'static void DMWindowKeysPublish(void) {' $K && grep -q 'int told = now && DMCSRecording() ? 2 : now;' \$W/fn && grep -q 'if (told != registered && DMWindowKeysRegister(told)) gWinKeysRegistered = told;' \$W/fn \
   && grep -q '    DMWindowKeysPublish();   // (Window Tiling Keys offered or not' $S"
check "  ... the Mac Switcher's Control-arrows the same (key commands out, none run, the recording in what backboardd was told), and Custom Shortcuts' recording post tells both" \
  "grep -q '^static BOOL DMCSRecording(void);' $M && fn 'static NSArray *DMMSWKeyCommands(id self, SEL _cmd) {' $M && grep -q 'if (!want || DMCSRecording()) return orig;' \$W/fn \
   && fn 'static void DMMSWControlKey(id self, SEL _cmd, id sender) {' $M && grep -q 'if (!DMMSWGesturesOn() || DMCSRecording()) return;' \$W/fn \
   && fn 'static void DMMSWKeysRefresh(void) {' $M && grep -q '(DMCSRecording() ? 1 << 8 : 0);' \$W/fn \
   && grep -q 'notify_register_dispatch(kMSBDCSRecordingNote, &rec, dispatch_get_main_queue(), ^(int t) { DMCSPublish(); DMWindowKeysYoursChanged(); DMMSWKeysRefresh(); DMCSRecordingCheck(); });' $C"
check "the Mac Switcher: a Control-arrow one of yours takes left out of the key commands and never run; the registration made again when yours change" \
  "fn 'static NSArray *DMMSWKeyCommands(id self, SEL _cmd) {' $M && grep -q 'if (!DMMSWKeyYours(0)) \[all addObject:gMSWKeyCmds\[0\]\];' \$W/fn && grep -q 'if (!DMMSWKeyYours(2)) \[all addObject:gMSWKeyCmds\[2\]\];' \$W/fn \
   && fn 'static void DMMSWControlKey(id self, SEL _cmd, id sender) {' $M && grep -q 'if (DMMSWKeyYours(side < 0 ? 0 : side > 0 ? 1 : 2)) return;' \$W/fn \
   && fn 'static void DMMSWKeysRefresh(void) {' $M && grep -q 'int want = DMMSWKeysWanted() | (DMMSWKeysYoursBits() << 4) | (DMCSRecording() ? 1 << 8 : 0);' \$W/fn \
   && fn 'static BOOL DMMSWKeyYours(NSUInteger i) {' $M && grep -q 'MSBDKCYoursTakes(&gKCYours, usages\[i\], kMSBDModControl)' \$W/fn"
check "the volume and backlight taps wait for their release while the window keys are offered OR a shortcut of yours starts with them" \
  "grep -q 'gDefer = gOffered || gYoursWait;' $V && grep -q '(st & kMSBDKCYoursVolumeWaits)' $V \
   && grep -q 'notify_register_dispatch(kMSBDKCYoursState, &yoursToken, dispatch_get_main_queue(), ^(int t) { ReadYours(t); })' $V \
   && grep -q 'gDeferChords = gKeysOffered || gYoursWait;' $B && grep -q '(st & kMSBDKCYoursBacklightWaits)' $B \
   && grep -q 'notify_register_dispatch(kMSBDKCYoursState, &yoursToken, dispatch_get_main_queue(), ^(int t) { ReadYoursWait(t); })' $B"
check "the screen keys leave Globe alone (1.8.7) and Shift + =/- when it is one of yours" \
  "grep -q '!(flags & (CONTROL_FLAG | OPTION_FLAG | COMMAND_FLAG | GLOBE_FLAG)) && !ScreenKeysOff()' $B && grep -q '&& !MSBDKCScreenKeyYours(YoursState(), code)) {' $B && grep -q '#define GLOBE_FLAG   0x800000' $B"
check "Tab mute leaves Globe-Tab alone (1.8.7) and a bare Tab that is one of yours" \
  "grep -q '#define kBlockingModifiers 0x9E0000' $TM && grep -q '&& !FullKeyboardAccessOn() && !TabIsYours()) {' $TM && grep -q 'return notify_get_state(token, &st) == NOTIFY_STATUS_OK && (st & kMSBDKCYoursTab);' $TM"
check "the key left of 1 stays itself where one of yours takes it; in Settings, while recording, with Control, Option or Globe (so one can be recorded)" \
  "fn 'static BOOL isRemapped(long long origKeyCode, long long origFlags) {' $G && grep -q 'if (MSBDKCTopLeftYours(gYours, (long)origKeyCode, (unsigned long long)origFlags)) return NO;' \$W/fn \
   && grep -q 'if (gRecording && MSBDKCTopLeftRecordable((unsigned long long)origFlags)) return NO;' \$W/fn \
   && grep -q 'isEqualToString:@\"com.apple.Preferences\"\]' $G && grep -q 'notify_register_dispatch(kMSBDCSRecordingNote, &recToken' $G"
check "Settings: the recorder takes a built-in one's keys and says which feature it replaces (no refusal left); the edit page says it too" \
  "! grep -q 'is a Window Tiling Shortcut. Choose other keys.' $P && ! grep -q 'switches desktops in the Mac Switcher. Choose other keys.' $P \
   && grep -q '_message = MSKeysBuiltinNote(usage, _rule\[@\"key\"\], mods);' $P && grep -q ': MSKeysBuiltinNote(\[_rule\[@\"keyCode\"\] longValue\]' $P \
   && fn 'NSString *MSKeysBuiltinNote(long usage, NSString *key, unsigned long long mods) {' $KB && grep -q 'Your shortcut takes its place.' \$W/fn \
   && grep -q 'Your shortcut keeps the key as it is.' \$W/fn && grep -q 'which then act only when pressed and let go alone.' \$W/fn"
check "  ... the Keyboard page's three groups say which feature has shared keys (Mac keys, Window Tiling, Custom Shortcuts), built again when a switch changes that" \
  "grep -q 'text = MSKCAppend(text, MSKCFooterLines(0));' $KB && grep -q 'R for its size before. Add Shift to arrange it with the window behind it, or Option-Shift for three windows.\", MSKCFooterLines(1)));' $KB \
   && grep -q ': @\"Make your own keyboard shortcuts for apps, URLs, window layouts and Home.\", MSKCFooterLines(2)));' $KB \
   && grep -q \"Window Tiling's Globe-Control keys start with the %@ keys, so those act only when pressed and let go alone.\" $KB && ! grep -q 'Globe-Control shortcuts belong to' $KB && grep -q 'A shortcut of yours wins over a built-in one with the same keys, which is then off for those keys.' $KB \
   && grep -q 'NSString \*now = MSKCSignature();' $KB && grep -q '\[me reloadSpecifiers\];' $KB \
   && grep -q '@\"com.besiktasliseba.tabmutetweak/prefsChanged\", @\"com.besiktasliseba.customshortcuts/prefsChanged\",' $G18"
check "review 1.8.7: Window Tiling's footer says the volume / backlight keys wait only while its keys can act, as the taps read it (SpringBoard's offered state, a live SpringBoard's), and follows that state" \
  "fn 'static BOOL MSKCWindowKeysOffered(void) {' $KB && grep -q 'notify_register_check(kMSBDWindowKeysOfferedNote, &t)' \$W/fn && grep -q 'return ok && (st & 1ULL) && pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);' \$W/fn \
   && grep -q 'if ((volume || backlight) && MSKCWindowKeysOffered())' $KB && grep -q '@kMSBDWindowKeysOfferedNote\]) {' $KB \
   && grep -q '@\"com.besiktasliseba.macstatusbar.windowkeys.offered\"\]) {' $G18 && grep -q '#define kMSBDWindowKeysOfferedNote \"com.besiktasliseba.macstatusbar.windowkeys.offered\"' ../common/ModifierTap.h"
check "  ... the recorder tells the volume and backlight taps that the chord it took is no tap (the key never reached SpringBoard: kb01 on the M1 stepped the volume)" \
  "fn '- (void)pressesBegan:(NSSet<UIPress \*> \*)presses withEvent:(UIPressesEvent \*)event {' $P && grep -q '        notify_post(kMSBDModTapUsedNote);' \$W/fn \
   && awk '/if \\(why == kMSBDCSNoKey\\) continue;/{a=NR} /notify_post\\(kMSBDModTapUsedNote\\);/{b=NR} /if \\(why == kMSBDCSEscape\\)/{c=NR} END{exit !(a && b > a && c > b)}' \$W/fn \
   && grep -q '#import \"../common/ModifierTap.h\"' $P"
check "  ... what Settings shows as yours is SpringBoard's (the same builder, the same switch and KeyPilot test)" \
  "fn 'void MSCSYoursNow(MSBDKCYoursSet *y) {' $P && grep -q 'MSBDKCYoursFromRules(y, MSCSRules(), MSCSSwitchOn() && !kp, kp ? MSCSKeyPilotRules() : @\[\], kp);' \$W/fn"
check "public text: no em dash in the Keyboard pages, the recorder or the table" \
  "! grep -q \$'\\xe2\\x80\\x94' $KB && ! grep -q \$'\\xe2\\x80\\x94' $P && ! grep -q \$'\\xe2\\x80\\x94' $KC"
# Made to fail: the table with one thing broken (KeyPilot's match keeping Globe, ours dropping it, a tap claimed by its held key alone, the key left
# of 1 with Command, Window Tiling's rows by the key's place, KeyPilot's state without its Globe twin, the screen keys taking Globe, Escape yours, the
# taps never told) must fail the C test, so the test above really checks each of them.
mutant() {
  local MD="$W/m-$1"; mkdir -p "$MD/common" "$MD/tools"; ln -s "$(cd ../statusbar && pwd)" "$MD/statusbar"; cp test-keyboardchords.c "$MD/tools/"; cp ../common/CustomShortcutsRule.h "$MD/common/"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' \
    $KC "$MD/common/KeyboardChords.h" "$2" "$3" || return 1
  clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$MD/t" "$MD/tools/test-keyboardchords.c" || return 1
  ! "$MD/t" > "$MD/out"
}
check "made to fail: KeyPilot's rules matched with Globe (its match drops it)" "mutant kpglobe '((m | (flags & kMSBDKCCapsLock)) & ~kMSBDModGlobe) == y->mods[i] : m == y->mods[i];' '(m | (flags & kMSBDKCCapsLock)) == y->mods[i] : m == y->mods[i];'"
check "made to fail: ours matched without Globe (Globe is part of our match)" "mutant ourglobe '& ~kMSBDModGlobe) == y->mods[i] : m == y->mods[i];' '& ~kMSBDModGlobe) == y->mods[i] : (m & ~kMSBDModGlobe) == y->mods[i];'"
check "made to fail: a tap claimed by its held modifier alone (Globe-J would wait the volume)" "mutant tap 'return key && (m & (c->mods | key)) == (c->mods | key);' 'return key && (m & c->mods) == c->mods;'"
check "made to fail: the key left of 1 told as yours with Command (it is never Escape then)" "mutant cmd 'if (m & kMSBDModCommand) return -1;' '(void)0;'"
check "made to fail: Window Tiling's rows found by the key's place, not the letter typed (Dvorak)" "mutant place 'MSBDWinKeyRowFor(MSBDWinKeyFor(y->usage[i], y->key[i]), y->mods[i]' 'MSBDWinKeyRowFor(MSBDWinKeyForHIDUsage(y->usage[i]), y->mods[i]'"
check "made to fail: KeyPilot's rules told without their Globe twin" "mutant twin 'int globes = y->keyPilot[i] ? 2 : 1;' 'int globes = 1;'"
check "made to fail: the screen keys and Tab taking Globe (1.8.7 leaves it)" "mutant keyglobe 'case kMSBDKCKindKey: return usage == c->usage && m == c->mods;' 'case kMSBDKCKindKey: return usage == c->usage && (m & ~kMSBDModGlobe) == c->mods;'"
check "made to fail: Escape yours" "mutant esc 'kMSBDCSHIDEscape, 0, kMSBDKCBuiltin,' 'kMSBDCSHIDEscape, 0, kMSBDKCYours,'"
check "made to fail: KeyPilot's Caps Lock dropped (a rule recorded with it on would take the keys all the time)" "mutant kpcaps 'kMSBDModCommand | kMSBDKCCapsLock)) : MSBDCSMods(mods);' 'kMSBDModCommand)) : MSBDCSMods(mods);'"
check "made to fail: a press's Caps Lock left out of KeyPilot's match" "mutant kppress '((m | (flags & kMSBDKCCapsLock)) & ~kMSBDModGlobe) == y->mods[i]' '(m & ~kMSBDModGlobe) == (y->mods[i] & ~kMSBDKCCapsLock)'"
check "made to fail: a KeyPilot rule recorded with Caps Lock on counted before any press" "mutant kpstatic 'return y && i < y->n && !(y->keyPilot[i] && (y->mods[i] & kMSBDKCCapsLock));' 'return y && i < y->n;'"
check "made to fail: the taps never told to wait for yours" "mutant taps 'if (taps & (1u << kMSBDKCVolume)) st |= kMSBDKCYoursVolumeWaits;' '(void)taps;'"
[ $fails = 0 ] && echo "test-keyboardchords: site checks pass" || { echo "test-keyboardchords: site checks FAILED"; exit 1; }
