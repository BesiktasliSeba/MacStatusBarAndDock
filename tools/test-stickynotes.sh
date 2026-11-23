#!/bin/bash
# Mac test of Sticky Notes on the desktop (1.8.8.1): the rules (common/StickyNotes.h, test-stickynotes.m -- with DMNativeResized cut out of
# statusbar/NativeWindow.h as written), and site checks of the places the notes plug into. Each file a check reads can be given as a copy
# (MSB_<NAME>=<path>, below): that is how made-to-fail copies of the sources are run against it, each of which must fail its check.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
awk '/^static CGRect DMNativeResized\(/{f=1} f{print} f&&/^}/{exit}' ../statusbar/NativeWindow.h > "$W/resized.h"
check "DMNativeResized is in NativeWindow.h as one function (the test builds it from there)" "[ \$(wc -l < '$W/resized.h') -ge 8 ] && grep -q 'return f;' '$W/resized.h'"
clang -O2 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -framework CoreGraphics -o "$W/tsn" test-stickynotes.m
"$W/tsn" || fails=1
N=${MSB_N:-../common/StickyNotes.h}
check "the rules never log or format a note's text (no DMLog, NSLog, printf or format in StickyNotes.h but the ids' and numbers')" \
  "! grep -nE 'DMLog|NSLog|printf|os_log' $N && [ \$(grep -c 'stringWithFormat' $N) -eq 2 ] && grep -q 'stringWithFormat:@\"StickyNotes-unreadable %d.plist\", n' $N && grep -q 'stringWithFormat:@\"1 %@ %.0f %.0f\", MSBDStickyColorName' $N"
# (the files read below: MSB_<NAME>=<copy> points a check at a made-to-fail copy -- the builder's mtf.sh)
SB=${MSB_SB:-../statusbar/StatusBar.x}; TW=${MSB_TW:-../statusbar/TextWindow.h}; MS=${MSB_MS:-../statusbar/MacSwitcher.h}; MSM=${MSB_MSM:-../statusbar/MacSwitcherSM.h}
D=${MSB_D:-../statusbar/Desktop.h}; NW=${MSB_NW:-../statusbar/NativeWindow.h}; SK=${MSB_SK:-../statusbar/SMSpotKeyboard.h}
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
check "the debug key loggers ([keys], [keyrecv], [mswkey]) log a key typed into a text input only as 'a typed key'" \
  "grep -q 'DMLog(DMKeyLogHides(p) ? @\"\\[keys\\] SpringBoard -pressesBegan: a typed key' $SB && grep -q 'DMLog(DMKeyLogHides(p) ? @\"\\[keyrecv\\] SpringBoard got a typed key' $SB && grep -q 'DMLog(DMKeyLogHides(p) ? @\"\\[mswkey\\] SpringBoard press: a typed key' $MS \
   && [ \$(grep -c '\\[keys\\] SpringBoard -pressesBegan: key 0x' $SB) = 1 ] && [ \$(grep -c '\\[keyrecv\\] SpringBoard got key usage' $SB) = 1 ] && [ \$(grep -c '\\[mswkey\\] SpringBoard press: key 0x' $MS) = 1 ]"
check "  ... hidden: neither Command nor Control held (Esc aside) while any text input of a key window has the typing (debug builds only)" \
  "fnf 'static BOOL DMKeyLogHides(UIPress *p) {' $SB | grep -qF 'if ((m & (UIKeyModifierCommand | UIKeyModifierControl)) || p.key.keyCode == UIKeyboardHIDUsageKeyboardEscape) return NO;' \
   && fnf 'static BOOL DMKeyLogHides(UIPress *p) {' $SB | grep -qF 'return DMSBTextInputTypingBut(nil, nil);' && awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /^static BOOL DMKeyLogHides/{print d; exit}' $SB | grep -qx 1"
check "the Command editing keys are one function, TextEdit's and a note's (DMTextViewEditKey), kept out of line" \
  "grep -q '^__attribute__((noinline)) static BOOL DMTextViewEditKey(UITextView \\*text, UIKey \\*key, BOOL editable) {' $TW && grep -q 'if (DMTextViewEditKey(_text, key, _editable)) return YES;' $TW \
   && [ \$(grep -c 'undoManager undo\\]' $TW) = 1 ] && [ \$(grep -c 'paste:nil\\]' $TW) = 1 ] && fnf '__attribute__((noinline)) static BOOL DMTextViewEditKey(' $TW | grep -q 'return cmd || cmdShift;'"
# ---- the desktop's typing window, shared by a name and a note (C2) ----
check "the typing window takes every view of its own (the field, a note and its grips, the edit menu), never itself, its container or a view as big as the screen" \
  "fnf 'static UIView *DMDesktopRenameHitTest(UIWindow *self, SEL _cmd, CGPoint p, UIEvent *e) {' $D | grep -qF 'if (!hit || hit == self || hit == gDesktopRenameRotator || DMViewNearlyScreen(hit)) return nil;' \
   && ! fnf 'static UIView *DMDesktopRenameHitTest(UIWindow *self, SEL _cmd, CGPoint p, UIEvent *e) {' $D | grep -q 'UITextField' && fnf 'static UIView *DMKeyboardWindowHit(UIWindow *w, CGPoint wp) {' $NW | grep -qF 'if (DMViewNearlyScreen(hit)) return nil;' \
   && fnf 'static BOOL DMViewNearlyScreen(UIView *v) {' $NW | grep -qF 'return (b.width >= sw * 0.9 && b.height >= sh * 0.75) || (b.height >= sw * 0.9 && b.width >= sh * 0.75);'"
check "  ... a point is the typing's only while the desktop types, only on the iPad's screen: the window's views, or our own keyboard (DMPointOnOwnKeyboard)" \
  "fnf '__attribute__((noinline)) static BOOL DMDesktopTypingTakes(CGPoint sp, UIScreen *screen) {' $D | grep -qF 'if (!DMDesktopTypingNow() || (screen && screen != [UIScreen mainScreen])) return NO;' \
   && fnf '__attribute__((noinline)) static BOOL DMDesktopTypingTakes(CGPoint sp, UIScreen *screen) {' $D | grep -qF 'return DMDesktopTypingWindowTakes(sp, screen) || DMPointOnOwnKeyboard(sp);' \
   && fnf '__attribute__((noinline)) static BOOL DMDesktopTypingWindowTakes(CGPoint sp, UIScreen *screen) {' $D | grep -qF 'if (!w || w.hidden || w.alpha < 0.01 || (screen && screen != [UIScreen mainScreen]) || !DMDesktopTypingNow()) return NO;'"
check "  ... the native windows: a touch that is the typing's activates nothing (before the window under it is looked for: Feasibility 2a)" \
  "fnf '__attribute__((noinline)) static void DMNativeTouchBegan(UITouch *t) {' $NW | awk '/if \\(DMDesktopTypingTakes\\(p, t.window.screen\\)\\) return;/{a=NR} /DMNativeLayerHitTest\\(/{if(!b)b=NR} /DMNativeSetActive\\(/{if(!c)c=NR} END{exit !(a && b > a && c > a)}' \
   && grep -q '^static BOOL DMDesktopTypingTakes(CGPoint sp, UIScreen \\*screen);' $NW"
check "  ... the desktop: a name being typed ends only for a touch that is not the typing's (the edit menu over it is)" \
  "fnf '- (void)dm_touchBegan:(UITouch *)t {' $D | grep -qF 'if (_renameField && DMDesktopTypingTakes(sp, t.window.screen)) return;' && ! fnf '- (void)dm_touchBegan:(UITouch *)t {' $D | grep -qF 'if (_renameField && DMPointOnOwnKeyboard(sp)) return;'"
check "  ... Stage Manager's window gestures leave the typing's touches (by the window's hit test: the edit menu too), the screen-edge pulls a note's grip" \
  "grep -qF 'BOOL typing = DMDesktopTypingTouch(touch, NULL);' $SB && grep -qF 'DMNativeWindow *w = typing ? nil : DMNativeWindowForTouch(touch, NULL);' $SB && grep -qF 'if ((w || typing) && !DMNativeSystemGestureStays(self, g)) {' $SB \
   && grep -qF 'if ((DMNativeWindowForTouch(touch, &chrome) && chrome) || (DMDesktopTypingTouch(touch, &chrome) && chrome)) {' $SB && ! grep -q 'DMDesktopRenameFieldTouch' $SB $D \
   && fnf '__attribute__((noinline)) static BOOL DMDesktopTypingTouch(UITouch *t, BOOL *onGrip) {' $D | grep -q 'DMDesktopTypingWindowTakes(p, screen)' && ! fnf '__attribute__((noinline)) static BOOL DMDesktopTypingTouch(UITouch *t, BOOL *onGrip) {' $D | grep -q 'DMPointOnOwnKeyboard'"
check "  ... the engines' keyboard gate: no app window takes the keys while the desktop types (both of its lines)" \
  "[ \$(grep -cF 'NSString *active = (DMNativeActiveApp() || DMDesktopTypingNow()) ? nil : [DMActiveApp() bundleIdentifier];' $SB) = 2 ] && ! grep -qF 'NSString *active = DMNativeActiveApp() ? nil : [DMActiveApp() bundleIdentifier];' $SB"
check "  ... Stage Manager's hand-off to the stage's front window is held back while the desktop types and the stage stays (any screen)" \
  "fnf 'static void DMSMSpotFocusNew(id self, SEL _cmd, id from, id to, id windowScene) {' $SK | grep -qF 'BOOL typing = !keep && DMSMEngine() && DMDesktopTypingNow() && DMSMSameStage(from, to);' \
   && fnf 'static void DMSMSpotFocusNew(id self, SEL _cmd, id from, id to, id windowScene) {' $SK | awk '/if \\(typing\\) \\{ DM_FEATURE_MARK\\(\"sm-desktop-typing-keeps-keyboard\"\\); return; \\}/{a=NR} /o_SMSpotFocusNew\\(self, _cmd, from, to, windowScene\\);/{b=NR} END{exit !(a && b > a)}'"
check "  ... the Mac Switcher opening (after its refusals) and every desktop switch end the typing first" \
  "fnf 'static void DMMSWOpenNow(NSString *why) {' $MS | awk '/if \\(!w\\) return;/{a=NR} /DMDesktopTypingEnd\\(@\"the Mac Switcher opens\"\\);/{b=NR} END{exit !(a && b > a)}' \
   && fnf 'static void DMMSWSwitchRun(NSUInteger to, NSString *why, CGFloat v, void (^done)(void)) {' $MS | awk '/DMDesktopTypingEnd\\(@\"a desktop switch\"\\);/{a=NR} /gMSWSwitching = YES;/{b=NR} END{exit !(a && b == a + 1)}' \
   && fnf 'static void DMMSWSMSwitch(NSUInteger to, NSString *why, NSString *launching, CGFloat v, void (^done)(void)) {' $MSM | awk '/DMDesktopTypingEnd\\(@\"a desktop switch\"\\);/{a=NR} /gMSWSwitching = YES;/{b=NR} END{exit !(a && b > a)}'"
check "  ... the desktop's own typing window never counts as another text field typing (its keys stay the desktop's)" \
  "fnf 'static BOOL DMSBTextFieldTyping(UIResponder *except) {' $D | grep -qF 'return DMSBTextInputTypingBut(gDesktopRenameWindow, except);'"
check "  ... the shared typing helpers are the desktop's (DMDesktopTyping*), each out of line: inlined into Finder's or the engines' code a crash would turn those off" \
  "ok=1; for f in 'static BOOL DMDesktopTypingWindowTakes(CGPoint sp, UIScreen \\*screen)' 'static BOOL DMDesktopTypingTakes(CGPoint sp, UIScreen \\*screen)' 'static BOOL DMDesktopTypingTouch(UITouch \\*t, BOOL \\*onGrip)' 'static BOOL DMDesktopTypingNow(void)' 'static void DMDesktopTypingEnd(NSString \\*why)'; do grep -q \"^__attribute__((noinline)) \$f {\" $D || ok=0; done; [ \$ok = 1 ]"
# ---- the notes (C3): the desktop's one-line branches ----
DN=${MSB_DN:-../statusbar/DesktopNotes.h}; FI=${MSB_FI:-../statusbar/Finder.h}; CR=${MSB_CR:-crashmap-rules.txt}; PL=${MSB_PL:-../statusbar/macstatusbarprefs/Resources/Desktop.plist}
RL=${MSB_RL:-../statusbar/macstatusbarprefs/MSBRootListController.m}; PR=${MSB_PR:-../layout/DEBIAN/postrm}
check "DesktopNotes.h is included at the end of Desktop.h, its methods declared as DMDesktop's Notes category before the desktop's code" \
  "[ \"\$(grep -v '^\$' $D | tail -1)\" = '#include \"DesktopNotes.h\"   // (Sticky Notes on the desktop, 1.8.8.1: the -dm_note... methods, their views and store)' ] && grep -q '^@interface DMDesktop (Notes) <UITextViewDelegate>' $D && grep -q '^@implementation DMDesktop (Notes)' $DN"
check "  ... each branch in Desktop.h is a one-line call into a -dm_note... method (a crash there is the notes', not the desktop's)" \
  "grep -qF '    [self dm_noteInit];   // (its sticky notes' $D && fnf '- (void)dm_detach {' $D | grep -qF '[self dm_noteEnd:@\"the desktop was taken off its page\"];' && fnf '- (void)dm_tick {' $D | grep -qF '[self dm_noteTick];' \
   && fnf '- (void)dm_placer:(DMPlacer *)pl area:(CGRect)area {' $D | awk '/DMPlacerInitDir\\(/{a=NR} /\\[self dm_noteTakeInto:pl\\];/{b=NR} END{exit !(a && b > a)}' \
   && grep -A1 -F '[self dm_noteLayoutIn:area];' $D | tail -1 | grep -qF 'DMPlacer pl; [self dm_placer:&pl area:area];' \
   && fnf '- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {' $D | grep -qF 'return [self dm_noteHitAt:p];' && fnf '- (void)dm_tap:(UITapGestureRecognizer *)g {' $D | grep -qF 'if (!v) { [self dm_noteTap:g]; return; }' \
   && fnf '- (void)dm_touchBegan:(UITouch *)t {' $D | awk '/if \\(t.type == UITouchTypeIndirect\\) return;/{a=NR} /\\[self dm_noteTouchBegan:t\\];/{b=NR} /isDescendantOfView:self\\] \\|\\| v == self\\)\\) return;/{c=NR} END{exit !(a && b == a + 1 && c > b)}' \
   && fnf '- (void)dm_holdCheck:(UITouch *)t since:(CFTimeInterval)at {' $D | awk '/if \\(\\[self dm_noteHoldMenuFor:t\\]\\) return;/{a=NR} /DMDesktopItemView \\*v = _trackView;/{b=NR} END{exit !(a && b == a + 1)}' \
   && grep -qF 'if ([self dm_noteOwnsMenu:i]) return [self dm_noteConfigFor:i at:loc];' $D && fnf '- (void)dm_fitRenameField {' $D | sed -n 2p | grep -qF '[self dm_noteFit];' \
   && fnf '- (BOOL)dm_handleKey:(UIKey *)key {' $D | grep -qF 'if ([self dm_noteActive]) return [self dm_noteKey:key];' && grep -qF '(_hasKeys || _renameField || [self dm_noteActive] || (!gNativeActive && !DMActiveApp()))' $D \
   && grep -qF 'else if ([act isEqualToString:@\"note\"]) [self dm_noteDebug:arg ?: @\"state\"];' $D && grep -qF '(unsigned long)occupied, [self dm_noteDiag]];' $D \
   && fnf 'static UIView *DMFocusGuideHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e) {' $D | grep -qF '|| [dk dm_noteAtScreen:sp];'"
check "  ... a desktop made again in this SpringBoard shows the notes read before; page 1 torn down ends a note being typed in; a rename that begins ends a note first; the shared window walk is a symbol of its own (review)" \
  "fnf '- (void)dm_noteInit {' $DN | grep -qF 'if (gNotesRead) dispatch_async(dispatch_get_main_queue(), ^{ [ws dm_noteStoreChanged]; });' \
   && fnf '- (void)dm_tick {' $D | grep -qF 'if (!found) { [self dm_noteTick]; return; }' && ! fnf '- (void)dm_tick {' $D | grep -qxF '        if (!found) return;' \
   && fnf '- (void)dm_beginRename:(NSString *)path {' $D | awk '/DM_FEATURE_MARK\\(\"desktop-rename\"\\);/{a=NR} /\\[self dm_noteEnd:@\"a name is edited\"\\];/{b=NR} /\\[self dm_endRename:YES\\];/{if(!c)c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' \
   && grep -qxF '__attribute__((noinline)) static BOOL DMSBTextInputTypingBut(UIWindow *skip, UIResponder *except);' $SB"
check "  ... New Sticky Note right after New Text File, the row's own rule (none while Show Sticky Notes is off; greyed at 30 notes, an unread or newer store, no typing window)" \
  "fnf '- (UIMenu *)dm_menuFor:(DMDesktopItemView *)v at:(CGPoint)sp {' $D | awk '/A\\(@\"New Text File\"/{a=NR} /UIAction \\*sn = \\[self dm_noteNewRowAt:sp\\]; if \\(sn\\) \\[top addObject:sn\\];/{b=NR} END{exit !(a && b == a + 1)}' \
   && fnf '- (UIAction *)dm_noteNewRowAt:(CGPoint)sp {' $DN | grep -qF 'if (!gDesktopNotesOn) return nil;' && fnf '- (UIAction *)dm_noteNewRowAt:(CGPoint)sp {' $DN | grep -qF 'if (!gNotesRead || !MSBDStickyWritable(gNotesStatus) || gNotes.count >= MSBD_NOTES_MAX || !DMStickyCanType()) a.attributes = UIMenuElementAttributesDisabled;'"
check "  ... a note is followed as an icon: held then moved (or a pointer) it is track mode 3 -- dragged, never Finder's file drag -- and let go at the end, also when the finger was lost" \
  "grep -qF 'BOOL onNote = !onIcon && [self dm_noteTrackBegin:at at:sp];' $D && grep -qF 'if (!onIcon && !onNote && at != _list) continue;' $D && grep -qF 'if (!onIcon && !onNote && ![self dm_shownAt:sp]) continue;' $D \
   && [ \$(grep -cF '[self dm_noteTracked] ? [self dm_noteHoldToMove] : DMDesktopHoldToTake(_trackView != nil)' $D) = 2 ] && [ \$(grep -cF 'DMDesktopHoldToTake(' $D) = 3 ] \
   && fnf '- (void)dm_event:(UIEvent *)e {' $D | awk '/if \\(\\[self dm_noteTracked\\]\\) \\{/{a=NR} /if \\(!\\[self dm_noteLiftAt:sp\\]\\) \\{ _track = nil; continue; \\}/{b=NR} /_trackMode = 3;/{c=NR} /\\} else if \\(v && v.window\\) \\{/{d=NR} END{exit !(a && b == a + 1 && c == b + 1 && d == c + 1)}' \
   && [ \$(grep -cF '[self dm_noteDropAt:' $D) = 2 ] && grep -qF 'else if (_trackMode == 3) [self dm_noteDragTo:sp];' $D"
check "  ... a native window made active ends a note being typed in whether the desktop had the keys or not (the check's item 7); the switch is read with the desktop's" \
  "grep -qF 'static void DMDesktopYieldKeys(void) { [gDesktop dm_noteEnd:@\"a native window was made active\"]; if (gDesktop && [gDesktop dm_ownsKeys]) [gDesktop dm_setHasKeys:NO]; }' $D \
   && fnf 'static void DMDesktopApplyPref(void) {' $D | grep -qF 'BOOL notes = DMStickyPref();' && fnf 'static void DMDesktopApplyPref(void) {' $D | grep -qF '[gDesktop dm_notePrefChanged];' \
   && fnf '- (BOOL)dm_typingNow {' $D | grep -qF 'return _renameField != nil || [self dm_noteActive];' && grep -qF '    [self dm_noteEnd:why];   // (a sticky note: saved)' $D \
   && fnf '__attribute__((noinline)) static BOOL DMDesktopTypingTouch(UITouch *t, BOOL *onGrip) {' $D | grep -qF 'if (onGrip) *onGrip = DMStickyGripAt(p);'"
# ---- the notes: crash guard and privacy ----
check "every C function of DesktopNotes.h is out of line and the notes' own (DMSticky...), none named DMDesktop... or DMNote... (the check's item 1; DMNoteAppExit and the like are not the notes')" \
  "! grep -nE '^static [^=;]*[A-Za-z_][A-Za-z0-9_]*\\([^)]*\\) *(\\{|;)' $DN | grep -vE '^[0-9]+:static (void|BOOL|NSString \\*|NSData \\*|NSMutableDictionary \\*|UIColor \\*|UIFont \\*|dispatch_queue_t) DMSticky[A-Z][A-Za-z]*\\([^)]*\\);' | grep -q . \
   && ! grep -nE '^__attribute__\\(\\(noinline\\)\\) static [^(]* \\**DM' $DN | grep -vE 'static [^(]* \\**DMSticky[A-Z][A-Za-z]*\\(' | grep -q . && [ \$(grep -cE '^__attribute__\\(\\(noinline\\)\\) static ' $DN) -ge 20 ] \
   && ! grep -nE '^static inline [^(]* \\**[A-Za-z]+\\(' $N | grep -vE 'static inline [^(]* \\**MSBDSticky[A-Z][A-Za-z]*\\(' | grep -q ."
check "  ... the views never print a note's text: the text view's and the editor's descriptions give lengths; the idle view keeps it in an ivar, no method named text" \
  "ok=1; for c in DMNoteTextView DMNoteView DMNoteEditor DMNoteBar DMNoteNameField; do awk -v c=\"@implementation \$c\" 'index(\$0, c) == 1 {f=1} f && /^@end/ {exit} f' $DN | grep -q 'description { return \\[NSString stringWithFormat:@\"<%@: %p; %lu characters>\"' || ok=0; done; [ \$ok = 1 ] \
   && ! grep -nE '^- \\(NSString \\*\\)text\\b|@property[^;]*\\*text;|accessibilityIdentifier' $DN && grep -qF '@implementation DMNoteView { NSString *_body, *_name; }' $DN && grep -qF '@implementation DMNoteBar { NSString *_name; }' $DN"
check "  ... no CFPreferences write in the notes' code (the store is its own file), only the switch read" \
  "! grep -nE 'CFPreferencesSet|CFPreferencesSynchronize|CFPreferencesAppSynchronize|NSUserDefaults' $DN && [ \$(grep -c 'CFPreferencesCopyValue' $DN) = 1 ]"
python3 - "$DN" > "$W/lint.txt" 2>&1 <<'EOF' || true
import re, sys
bad = []
for n, l in enumerate(open(sys.argv[1]), 1):
    if 'DMLog(' not in l: continue
    x = l.replace('[t hasPrefix:@"MSB-TEST"] ? [@", text " stringByAppendingString:t] : @""', '')   # (the debug state: test notes' text only)
    x = re.sub(r'@"(\\.|[^"\\])*"', '@""', x)   # (string literals: constant words)
    for safe in ('text.length', '[e[@"text"] length]', 'textView.text.length', '.text.length', '_body.length'):
        x = x.replace(safe, '')
    for pat in (r'\btext\b(?!\s*of)(?=\s*[\],)])', r'e\[@"text"\]', r'_body\b', r'\.text\b', r'textStorage', r',\s*(v|nv|ed|tv|e|x|editor|self\.text)\s*[\])]', r'gNotes\s*[\],)]', r'%@",\s*(v|nv|ed|tv|e)\b'):
        if re.search(pat, x): bad.append('%d: %s' % (n, l.strip()[:160])); break
if bad: print('\n'.join(bad))
sys.exit(1 if bad else 0)
EOF
check "  ... no log line names a note's text, its text view or the store's notes (ids, counts, lengths, frames only): lint of every DMLog line" "[ ! -s '$W/lint.txt' ]"
[ -s "$W/lint.txt" ] && sed 's/^/        /' "$W/lint.txt"
check "  ... axdump prints a note's value as its length (StatusBar.x), the crash cause hides a note's details (CauseHide.h, C1)" \
  "grep -qF 'DMStickyAXDumpValue(v) ?: v.accessibilityValue ?: @\"\"' $SB && fnf '__attribute__((noinline)) static NSString *DMStickyAXDumpValue(UIView *v) {' $DN | grep -c 'characters)\"' | grep -qx 2"
check "the crash guard: Show Sticky Notes is the notes' target; the notes' sym rule before the desktop's, their file rule before Desktop.h's; DMTextViewEditKey passed over" \
  "grep -qx 'target stickyNotes pref com.besiktasliseba.macstatusbar stickyNotes 0 1 Show Sticky Notes|the sticky notes' $CR \
   && awk '/^sym MacStatusBarCore \\^\\(_\\*\\(DMSticky\\|MSBDSticky\\)\\[A-Z\\]/{a=NR} /^sym MacStatusBarCore \\^_\\?DMDesktop\\[A-Z\\] desktopIcons/{b=NR} /^file MacStatusBarCore \\^DesktopNotes\\\\.h\\$ stickyNotes/{c=NR} /^file MacStatusBarCore \\^Desktop\\(Names\\|Corner\\)\\?/{d=NR} /^sym MacStatusBarCore \\^_\\*DMTextViewEditKey\\$ transparent/{e=NR} END{exit !(a && b > a && c && d > c && e && e < b)}' $CR"
python3 - "$CR" > "$W/rules.txt" 2>&1 <<'EOF' || true
import re, sys
rules = []
for raw in open(sys.argv[1]):
    line = re.split(r'\s+#', raw, 1)[0].strip()
    if not line or line.startswith('#'): continue
    f = line.split()
    if f[0] == 'sym' and f[1] == 'MacStatusBarCore': rules.append((re.compile(f[2]), f[3]))
want = {'_DMStickyLoad': 'stickyNotes', '_DMStickyColor': 'stickyNotes', '_MSBDStickyFrameAt': 'stickyNotes', '_DMStickyGripAt': 'stickyNotes', '_DMStickyPutBack': 'stickyNotes',
        '___DMStickyLoad_block_invoke': 'stickyNotes', '_DMNoteAppExit': None, '_DMNoteAppInFront': None, '_DMNoteWindowLayouts': None, '_MSBDNoteSwitch': None, '_DMNoteTopEdgeBarTouch': None,
        '-[DMNoteView drawRect:]': 'stickyNotes', '-[DMNoteTextView description]': 'stickyNotes', '-[DMNoteEditor layoutSubviews]': 'stickyNotes', '-[DMNotesState views]': 'stickyNotes',
        '-[DMDesktop(Notes) dm_noteTap:]': 'stickyNotes', '-[DMNoteBar drawRect:]': 'stickyNotes', '-[DMNoteNameField description]': 'stickyNotes', '-[DMNoteBarView x]': None, '-[DMNotesState textFieldShouldReturn:]': 'stickyNotes', '-[DMNotesPageView hitTest:withEvent:]': 'stickyNotes', '-[DMDesktop(Notes) dm_notePagesTick]': 'stickyNotes', '_DMStickyRootFolder': 'stickyNotes', '_DMTextViewEditKey': 'transparent', '_DMDesktopTypingNow': 'desktopIcons', '_DMDesktopTypingWindowCan': 'desktopIcons',
        '_DMNativeTouchBegan': 'finder', '_DMDesktopTick': 'desktopIcons', '_DMSBTextInputTypingBut': 'transparent'}
bad = []
for name, t in want.items():
    got = next((r[1] for r in rules if r[0].search(name)), None)
    if got != t: bad.append('%s -> %s (wanted %s)' % (name, got, t))
if bad: print('\n'.join(bad))
sys.exit(1 if bad else 0)
EOF
check "  ... the rules give each kind of name its target, as make-crashmap.py reads them (sym rules first, in order)" "[ ! -s '$W/rules.txt' ]"
[ -s "$W/rules.txt" ] && sed 's/^/        /' "$W/rules.txt"
# ---- the notes: typing, keys, ends ----
check "the keys while a note is typed in: Esc ends it; the Command editing keys are the note's (DMTextViewEditKey); Return and the rest go on to the text view" \
  "fnf '- (BOOL)dm_noteKey:(UIKey *)key {' $DN | grep -qF 'if (key.keyCode == UIKeyboardHIDUsageKeyboardEscape && m == 0) { [self dm_noteEnd:@\"Esc\"]; return YES; }' \
   && fnf '- (BOOL)dm_noteKey:(UIKey *)key {' $DN | grep -qF 'return tv.isFirstResponder && DMTextViewEditKey(tv, key, YES);' && ! fnf '- (BOOL)dm_noteKey:(UIKey *)key {' $DN | grep -q 'ReturnOrEnter'"
check "  ... a touch ends it unless it is the typing's (its window's views, the edit menu, our keyboard), our menu's or a context menu's; the hide key never ends it" \
  "fnf '- (void)dm_noteTouchBegan:(UITouch *)t {' $DN | grep -qF 'if (DMDesktopTypingTakes(sp, screen)) return;' && fnf '- (void)dm_noteTouchBegan:(UITouch *)t {' $DN | grep -qF 'if (gOverlay && v && [v isDescendantOfView:gOverlay]) return;' \
   && fnf '- (void)dm_noteTouchBegan:(UITouch *)t {' $DN | grep -qF 'if (DMAnyContextMenuVC(NULL)) return;' && ! fnf '- (void)textViewDidEndEditing:(UITextView *)tv {' $DN | grep -q 'dm_noteEnd'"
check "  ... the tick ends it for jiggle mode or Guided Access, the switch, its page going (1.8.8.2 F36: page 1's or another's), another app in front, another text field typing; the window's level checked again (item 11)" \
  "fnf '- (void)dm_noteTick {' $DN | grep -qF 'if (_editing) why =' && fnf '- (void)dm_noteTick {' $DN | grep -qF 'else if (!DMStickyShown()) why =' && fnf '- (void)dm_noteTick {' $DN | grep -qF 'else if (![self dm_notePageShowing:[self dm_notePageOfLayer:[self dm_noteLayerOfEditor]]]) why = @\"its page no longer shows\";' \
   && fnf '- (void)dm_noteTick {' $DN | grep -qF 'isEqualToString:_notes.editFront ?: @\"\"]) why =' && fnf '- (void)dm_noteTick {' $DN | grep -qF 'else if (DMSBTextInputTypingBut(gDesktopRenameWindow, nil)) why =' \
   && fnf '- (void)dm_noteTick {' $DN | grep -qF 'CGFloat level = DMDesktopRenameLevel();'"
check "  ... the screen going off, a lock and the Cover Sheet coming down end it (StatusBar.x); our Respring writes the notes first" \
  "fnf 'static void DMScreenPowerChanged(BOOL off) {' $SB | grep -qF 'if (off) DMStickyEnd(@\"the screen went off\");' && fnf 'static void DMWatchLock(void) {' $SB | grep -qF 'if (cover) DMStickyEnd(@\"the Cover Sheet came down\");' \
   && fnf 'static void DMWatchLock(void) {' $SB | grep -qF 'if (locked) DMStickyEnd(@\"locked\");' && fnf 'static void DMRespring(void) {' $SB | awk '/DMSaveWindowState\\(\\);/{a=NR} /DMStickyFlush\\(\\);/{b=NR} END{exit !(a && b == a + 1)}'"
check "  ... the text is cut at 10,000 characters as it is typed or pasted; begin and end hand the focus lock and the key window over as the rename does" \
  "fnf '- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {' $DN | grep -qF 'if (keep + text.length <= MSBD_NOTE_TEXT_MAX) return YES;' \
   && fnf '- (void)dm_noteBegin:(DMNoteView *)nv at:(CGPoint)sp {' $DN | grep -qF 'DMDesktopFocus(YES);' && fnf '- (void)dm_noteEnd:(NSString *)why {' $DN | grep -qF 'DMDesktopFocus(NO);' \
   && fnf '- (void)dm_noteBegin:(DMNoteView *)nv at:(CGPoint)sp {' $DN | grep -qF '[self dm_endRename:YES];' && fnf '- (void)dm_noteEnd:(NSString *)why {' $DN | grep -qF 'DMStickyChanged(0);'"
# ---- the notes: store and Trash ----
check "the store is never written before a read worked, never over an unread or newer one; written whole, 0600 and class C, then renamed over; its folder 0700" \
  "fnf '__attribute__((noinline)) static void DMStickyWriteNow(void (^then)(BOOL ok)) {' $DN | grep -qF 'if (!gNotesRead || !MSBDStickyWritable(gNotesStatus)) { if (then) then(NO); return; }' \
   && fnf '__attribute__((noinline)) static void DMStickyChanged(double delay) {' $DN | grep -qF 'if (!gNotesRead || !MSBDStickyWritable(gNotesStatus)) return;' \
   && fnf '__attribute__((noinline)) static BOOL DMStickyWriteFile(NSData *data) {' $DN | grep -qF 'NSFilePosixPermissions: @0600, NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication' \
   && fnf '__attribute__((noinline)) static BOOL DMStickyWriteFile(NSData *data) {' $DN | grep -qF 'rename(tmp.fileSystemRepresentation, path.fileSystemRepresentation) == 0' && grep -qF '@{NSFilePosixPermissions: @0700}' $DN \
   && fnf '__attribute__((noinline)) static NSString *DMStickyFolder(void) {' $DN | grep -qF '[NSHomeDirectory() stringByAppendingPathComponent:@\"Library/Application Support/MacStatusBarAndDock\"]' && ! grep -q '@\"/var/jb' $DN"
check "  ... a store that is not one goes aside (never over another), and one that could not be moved aside is never written" \
  "fnf '__attribute__((noinline)) static void DMStickyLoad(void (^done)(void)) {' $DN | grep -qF 'if (st == MSBDStickyAside && !DMStickyPutAside(path)) st = MSBDStickyUnread;' && fnf '__attribute__((noinline)) static BOOL DMStickyPutAside(NSString *path) {' $DN | grep -qF 'if (lstat(to.fileSystemRepresentation, &st) == 0) continue;'"
check "  ... Move to Trash: <its name>.txt in Finder's Trash (1.8.8.2 F37), 0600 class C, the origin a marker, the look and place attributes; the note leaves only once the file is there" \
  "fnf '__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {' $DN | grep -qF 'NSFilePosixPermissions: @0600, NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication' \
   && fnf '__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {' $DN | grep -qF 'DMFinderSetOrigin(tmp, MSBD_NOTE_TRASH_ORIGIN);' && fnf '__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {' $DN | grep -qF 'DMFinderFreeName(kFinderTrash, fileName, @\"\")' && fnf '__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {' $DN | grep -qF 'NSString *fileName = MSBDStickyTrashFileName(MSBDStickyNameShown(e[@\"name\"], text))' \
   && fnf '__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {' $DN | awk '/if \\(err\\) \\{ DMLog/{a=NR} /\\[gNotes removeObjectIdenticalTo:now\\]/{b=NR} /DMFinderPushUndo\\(@\"notetrash\"/{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... Put Back and Undo make it a note again (refused while Show Sticky Notes is off: item 13; at 30 notes); the Trash file goes only after the store is written" \
  "fnf '__attribute__((noinline)) static void DMStickyPutBack(NSString *path, void (^done)(NSError *e)) {' $DN | sed -n 3p | grep -qF 'if (!gDesktopNotesOn) {' \
   && fnf '__attribute__((noinline)) static void DMStickyPutBack(NSString *path, void (^done)(NSError *e)) {' $DN | awk '/DMStickyWriteNow\\(\\^\\(BOOL ok\\) \\{/{a=NR} /NSError \\*re = DMFinderRemove\\(path\\);/{b=NR} END{exit !(a && b > a)}'"
check "  ... Finder: Put Back of a note's file is not a move; Undo of a note's Move to Trash, and Get Info's From" \
  "grep -qF 'else if ([origin isEqualToString:MSBD_NOTE_TRASH_ORIGIN]) { [notes addObject:src]; continue; }' $FI && grep -qF 'for (NSString *p in notes) DMStickyPutBack(p, ^(NSError *e) { if (e) [ws fail:e what:what]; });' $FI \
   && fnf '- (void)dm_undo {' $FI | awk '/NSString \\*kind = u\\[@\"kind\"\\]; NSArray \\*pairs = u\\[@\"pairs\"\\];/{a=NR} /if \\(\\[kind isEqualToString:@\"notetrash\"\\]\\) \\{ DMStickyUndoTrash\\(pairs, self\\); return; \\}/{b=NR} END{exit !(a && b == a + 1)}' \
   && grep -qF '[origin isEqualToString:MSBD_NOTE_TRASH_ORIGIN] ? @\"the desktop (sticky note)\"' $FI"
# ---- the notes: Settings and the package ----
check "Settings > Desktop: Show Sticky Notes under Hide Desktop Icon Names (stickyNotes, on by default, the desktop's notification), greyed with the desktop's rows, left out with them" \
  "python3 -c \"import plistlib,sys; it=plistlib.load(open('$PL','rb'))['items']; ids=[i.get('id') for i in it]; k=ids.index('DESKTOP_STICKY_NOTES'); r=it[k]; sys.exit(not (ids[k-1]=='DESKTOP_HIDE_NAMES' and r['key']=='stickyNotes' and r['default'] is True and r['cell']=='PSSwitchCell' and r['label']=='Show Sticky Notes' and r['PostNotification']=='com.besiktasliseba.macstatusbar.finder.pref' and r['defaults']=='com.besiktasliseba.macstatusbar' and 'New Sticky Note' in it[ids.index('DESKTOP_GROUP')]['footerText']))\" \
   && grep -qF '![spec.identifier isEqualToString:@\"DESKTOP_STICKY_NOTES\"]) continue;' $RL && grep -qF '@\"desktopIconSize\", @\"stickyNotes\"] containsObject:key]' ../common/OwnPageRows.h && grep -qF '@\"DESKTOP_STICKY_NOTES\", @\"Show Sticky Notes\"];' ../common/SettingsRoot.h"
check "the package: removing it keeps the notes (the user's writing), purge deletes them" \
  "grep -qxF '    [ \"\$1\" = \"purge\" ] && rm -rf \"/var/mobile/Library/Application Support/MacStatusBarAndDock\"' $PR && [ \$(grep -c 'Application Support/MacStatusBarAndDock' $PR) = 1 ]"
[ $fails = 0 ] && echo "test-stickynotes: all checks pass" || { echo "test-stickynotes: checks FAILED"; exit 1; }
