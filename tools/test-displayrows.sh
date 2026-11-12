#!/bin/bash
# Mac test of the per-display settings' rows, the Display menu and the Display Settings window (1.8.7 commit 11; plans/design-1.8.7-displays.md
# sections 4 and 6): the table in plain C (common/DisplayRows.h, test-displayrows.c), then the sites -- the window builds its rows from the table and
# writes through the one writer, the Display menu's title and rows, the window's two hosts, the crash map -- and last made-to-fail copies of the
# table's rules, each of which must fail the C test.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tdr" test-displayrows.c
"$W/tdr"
fails=0
check() { if (eval "$2"); then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
R=../common/DisplayRows.h; ST=../common/DisplayRowStore.h; D=../statusbar/DisplaySettings.h; S=../statusbar/StatusBar.x; M=crashmap-rules.txt
EM=$(printf '\342\200\224'); EN=$(printf '\342\200\223')   # (the em and en dash, spelled by their bytes so this file has neither)
check "DisplayRows.h is plain C (Settings, SpringBoard and the Mac test share it): no ObjC, no CoreFoundation" \
  "! grep -E '^#(import|include) <(UIKit|Foundation|CoreFoundation)' $R && ! grep -q '@interface\|@\"\|NSString\|CFString' $R"
check "the store: Foundation only, no screens and no private calls (Settings has none), the iPad's keys read only" \
  "! grep -q 'UIKit\|UIScreen\|objc_msgSend\|MSBDDispGet' $ST && ! grep -n 'CFPreferencesSet' $ST | grep -v ', dom, kCFPreferencesCurrentUser' | grep -q . \
   && [ \$(grep -c 'CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);' $ST) = 5 ] && fn 'static inline id MSBDDispRowIPadValue(const MSBDDispRow *r) {' $ST && ! grep -q 'CFPreferencesSet' \$W/fn"
check "  ... a display's value by the rule (MSBDDispResolve, the override of the row's form, the display default), as SpringBoard's getters" \
  "fn 'static inline id MSBDDispRowShownValue(NSDictionary *all, NSString *display, const MSBDDispRow *r, int *from) {' $ST \
   && grep -q 'f = MSBDDispResolve(display == nil, MSBDDispStoreLayerOn(all), all\[MSBDDispRowFlat(display, r) ?: @\"\"\] != nil, ov != nil, hasDef);' \$W/fn \
   && grep -q 'id ov = MSBDDispRowForm(r, all\[MSBDDispRowFlat(display, r) ?: @\"\"\]);' \$W/fn \
   && fn 'static inline id MSBDDispRowForm(const MSBDDispRow *r, id v) {' $ST && grep -q 'MSBDDispTypeOK(kMSBDDispWantBool' \$W/fn && grep -q 'MSBDDispTypeOK(kMSBDDispWantNumber, kMSBDDispVNumber, num, 1, r->lo, r->hi)' \$W/fn"
check "  ... Use iPad Settings deletes that display's rows' overrides only (its info and More Space's records stay); Forget every key of a display not connected" \
  "fn 'static inline int MSBDDispStoreUseIPad(NSString *display) {' $ST && grep -q 'NSArray \*gone = MSBDDispStoreOwnKeys(all, display);' \$W/fn \
   && fn 'static inline const MSBDDispRow *MSBDDispStoreRowOfKey(NSString *k, NSString *display) {' $ST && grep -q 'strcmp(d, display.UTF8String) != 0) return NULL;' \$W/fn \
   && grep -q 'return r && r->kind != kMSBDRowScale ? r : NULL;' \$W/fn \
   && fn 'static inline int MSBDDispStoreForget(NSString *display) {' $ST && grep -q 'if (\[MSBDDispStoreConnected(all) containsObject:display\]) return -1;' \$W/fn \
   && grep -q 'NSString \*prefix = \[display stringByAppendingString:@\"/\"\];' \$W/fn"
# ---- the window: rows from the table, changes through the one writer
check "the window's rows: the table's, shown and greyed by its rules (MSBDDispRowShown, MSBDDispRowEnabled), no row of its own" \
  "fn '- (void)dm_reload {' $D && grep -q 'if (!MSBDDispRowShown(r, &ctx)) continue;' \$W/fn && grep -q 'BOOL enabled = MSBDDispRowEnabled(r, &ctx, connected, layerOn);' \$W/fn \
   && grep -q 'for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {' \$W/fn && ! grep -q '\"Menu Bar Size\"\|\"Dock Size\"\|\"Show Trash in Dock\"\|\"Window Size\"' $D"
check "  ... a change: the override through DMDispWrite (the switch's old state for the crash guard), a reset deletes it, Use iPad Settings the store's" \
  "fn '- (BOOL)dm_setRow:(NSString *)rowId value:(id)value {' $D && grep -q 'BOOL ok = DMDispWrite(_display, r->part, r->key, stored, was, @(r->title));' \$W/fn && grep -q 'MSBDDispRowForm(r, value)' \$W/fn \
   && fn '- (BOOL)dm_resetRow:(NSString *)rowId {' $D && grep -q 'DMDispWrite(_display, r->part, r->key, nil, was, @(r->title));' \$W/fn \
   && fn '- (void)dm_useIPadConfirmed {' $D && grep -q 'int n = MSBDDispStoreUseIPad(_display);' \$W/fn && ! grep -q 'CFPreferencesSet' $D"
check "  ... a dot and a reset arrow only on a row changed for this display; the Trash's reset says Default: On" \
  "fn '- (UIView *)dm_row:(const MSBDDispRow *)r all:(NSDictionary *)all enabled:(BOOL)enabled {' $D && grep -q 'BOOL changed = from == kMSBDDispFromOverride;' \$W/fn \
   && grep -q 'dot.hidden = !changed;' \$W/fn && grep -q 'reset.hidden = !changed;' \$W/fn && grep -q 'NSString \*back = hasDef ? @MSBD_DISP_TEXT_DEFAULT_ON' \$W/fn"
check "  ... it follows the displays domain and the iPad's own settings live (Settings' page and the window follow each other)" \
  "fn '- (void)dm_follow:(BOOL)on {' $D && grep -q 'MSBD_DISP_NOTIFY, \"com.besiktasliseba.macstatusbar/prefsChanged\", \"com.besiktasliseba.dockmagnification/prefsChanged\"' \$W/fn \
   && grep -q '\[weakSelf dm_reload\];' \$W/fn"
check "  ... the window and Settings' page agree: Use iPad Settings offered by the same test (the rows' changes only), the same words on top (a display gone: not the mirror's), the same \"has our Dock\"" \
  "fn '- (void)dm_reload {' $D && grep -q 'BOOL anyOwn = MSBDDispStoreHasOwn(all, _display);' \$W/fn && grep -q 'NSString \*top = @(MSBDDispTopText(layerOn, connected, ctx.extended));' \$W/fn \
   && grep -q 'BOOL anyOwn = MSBDDispStoreHasOwn(all, _display);' ../statusbar/macstatusbarprefs/MSBRootListController.m && grep -q 'NSString \*topText = @(MSBDDispTopText(layerOn, connected, ctx.extended));' ../statusbar/macstatusbarprefs/MSBRootListController.m \
   && ! grep -q 'anyOwn = YES' $D ../statusbar/macstatusbarprefs/MSBRootListController.m && ! grep -q 'MSBD_DISP_TEXT_MIRROR : !connected' $D ../statusbar/macstatusbarprefs/MSBRootListController.m \
   && fn 'static MSBDDispCtx DMDispCtxFor(NSString *display) {' $D && grep -q 'c.ourDock = MSBDDispStoreOurDock(dockLoaded);' \$W/fn && grep -q 'c.ourDock = MSBDDispStoreOurDock(own.dockLine);' ../statusbar/macstatusbarprefs/MSBRootListController.m"
# (review: every control's action holds the view weakly -- the cycle view -> stack -> row -> control -> action -> block -> view kept every closed
#  Display Settings view alive, rebuilding on every post; its notes are taken only while it is in a window)
actionself() { python3 -I - "$1" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
bad, n = [], 0
for m in re.finditer(r'actionWithHandler:\^', s):
    i = s.index('{', m.end()); depth = 0; j = i
    while True:
        if s[j] == '{': depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0: break
        j += 1
    n += 1
    if re.search(r'\bself\b', s[i:j + 1]): bad.append(s.count('\n', 0, m.start()) + 1)
sys.exit(1 if bad or n < 9 else 0)
PY
}
check "  ... no control's action holds the view (no self in an actionWithHandler: block); its notes taken when it goes into a window, let go when it leaves" \
  "actionself $D && fn '- (void)dm_follow:(BOOL)on {' $D && grep -q 'notify_cancel(_tokens\[i\]); _tokens\[i\] = 0;' \$W/fn \
   && grep -q '^- (void)didMoveToWindow { \[super didMoveToWindow\]; \[self dm_follow:self.window != nil\]; }' $D && grep -q '^- (void)dealloc { \[self dm_follow:NO\]; }' $D \
   && fn '- (instancetype)initWithDisplay:(NSString *)display {' $D && ! grep -q 'notify_register' \$W/fn"
cp $D "$W/ds-self.h"; python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); a="[ws dm_resetRow:rowId]"; assert s.count(a)==1; open(p,"w").write(s.replace(a,"[self dm_resetRow:rowId]"))' "$W/ds-self.h"
check "made to fail: a control's action holding the view (the reset arrow's)" "! actionself $W/ds-self.h"
check "  ... Use iPad Settings asks first (Cancel / Use iPad Settings), then deletes" \
  "fn '- (void)dm_reload {' $D && grep -q 'if (_askingUseIPad) {' \$W/fn && grep -q '@MSBD_DISP_TEXT_USE_IPAD_ASK' \$W/fn && grep -q 'dm_useIPadConfirmed\]; }\] forControlEvents' \$W/fn"
check "  ... its hosts: on the iPad a native window (Display Settings; Esc and Command-W close it), on the TV a panel in the TV's own scene just under our menus" \
  "grep -q '@interface DMDispSettingsWindow : DMNativeWindow' $D && grep -q 'w.appName = @\"Display Settings\";' $D && grep -q 'key.keyCode == UIKeyboardHIDUsageKeyboardEscape || (cmd && \[key.charactersIgnoringModifiers isEqualToString:@\"w\"\])' $D \
   && fn 'static void DMDispSettingsOpenTV(NSString *display) {' $D && grep -q 'UIWindow \*w = DMSceneLayer(screen, @\"dispsettings\", kMenuWindowLevel - 1,' \$W/fn \
   && grep -q 'UIScreen \*screen = DMDispDesktopScreen(display, DMDispScreens());' \$W/fn && grep -q 'DMDispPanelWatchTouches();' \$W/fn && grep -q 'DMDispPanelKeys(YES, @\"opened\");' \$W/fn"
check "  ... the TV panel closes by its red light, Esc (SpringBoard's key handling, after an open menu) and the escape gesture, and with its display" \
  "grep -q 'DMDispPanelClose(@\"the red light\");' $D && grep -q 'if (!gOverlay && DMDispPanelEscape(presses)) return;' $S \
   && awk '/if \(gOverlay\) for \(UIPress \*p in presses\) if \(p.key.keyCode == UIKeyboardHIDUsageKeyboardEscape\)/{a=NR} /if \(!gOverlay && DMDispPanelEscape\(presses\)\) return;/{b=NR} END{exit !(a && b > a)}' $S \
   && grep -q 'DMDispPanelClose(@\"its display went away\");' $D && fn 'static BOOL DMDispPanelAXEscape(UIWindow \*self, SEL _cmd) {' $D && grep -q 'DMDispPanelClose' \$W/fn"
# (review: the TV's panel held SpringBoard's keys for as long as it was open -- no typing in any app on the TV or the iPad, and Esc in any app closed
#  it -- and kept them while the screen was off, over the Lock Screen's passcode)
fno() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }   # (a function's text to stdout)
panelkeys() {   # <DisplaySettings.h> <StatusBar.x>
  fno 'static void DMDispPanelKeys(BOOL take, NSString *why) {' "$1" | grep -qF 'if (take && !gDMDispPanelLock && gDMDispPanelWindow && DMHardwareKeyboardAttached()) gDMDispPanelLock = DMSpringBoardFocusLock(gDMDispPanelWindow,' \
    && fno 'static void DMDispPanelKeys(BOOL take, NSString *why) {' "$1" | grep -qF 'if (!take && gDMDispPanelLock) { id l = gDMDispPanelLock; gDMDispPanelLock = nil; MSBDFocusUnlock(l); }' \
    && fno '__attribute__((noinline)) static void DMDispPanelTouch(UIEvent *event) {' "$1" | grep -qF 'DMDispPanelKeys(inside, inside ? @"a click in it" : @"a click elsewhere");' \
    && fno '__attribute__((noinline)) static void DMDispPanelTouch(UIEvent *event) {' "$1" | grep -qF 'if (t.phase != UITouchPhaseBegan || t.type == UITouchTypeIndirect) continue;' \
    && fno '__attribute__((noinline)) static void DMDispPanelSendEvent(id self, SEL _cmd, UIEvent *event) {' "$1" | grep -qF 'o_DMDispPanelSendEvent(self, _cmd, event);' \
    && fno 'static BOOL DMDispPanelEscape(NSSet<UIPress *> *presses) {' "$1" | grep -qF 'if (!gDMDispPanel || !gDMDispPanelKeys) return NO;' \
    && [ "$(grep -c 'DMSpringBoardFocusLock(' "$1")" = 1 ] \
    && fno 'static void DMCloseOverlaysForScreenOff(void) {' "$2" | grep -qF 'DMDispPanelClose(@"the screen went off");' \
    && grep -qF 'sym MacStatusBarCore ^_*(DMDisp(KeyOfScreen|DesktopScreen|PanelSendEvent)$|MSBDDisp[A-Z]) transparent' $M
}
check "  ... the TV panel holds the keys only while it is the key target (opened, clicked last); a click elsewhere gives them back; Esc is its own only then; the screen going off closes it" "panelkeys $D $S"
cp $S "$W/sb-off.x"; python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); a="    DMDispPanelClose(@\"the screen went off\");"; assert s.count(a)==1; open(p,"w").write(s.replace(a,""))' "$W/sb-off.x"
cp $D "$W/ds-esc.h"; python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); a="if (!gDMDispPanel || !gDMDispPanelKeys) return NO;"; assert s.count(a)==1; open(p,"w").write(s.replace(a,"if (!gDMDispPanel) return NO;"))' "$W/ds-esc.h"
check "made to fail: the TV panel left open with the keys when the screen goes off" "! panelkeys $D $W/sb-off.x"
check "made to fail: Esc in any app closing the TV panel" "! panelkeys $W/ds-esc.h $S"
check "  ... it edits the display the menu came from: a TV bar's own, else the one connected (SpringBoard's desktop on it first)" \
  "fn '__attribute__((noinline)) static NSString *DMDispMenuDisplayOf(UIView *v) {' $D && grep -q 'UIScreen \*ext = v ? DMExternalScreenOf(v) : nil;' \$W/fn \
   && grep -q 'if (DMSceneLayerSceneOf(DMDispDesktopScreen(d, screens))) return d;' \$W/fn"
# ---- the Display menu
check "the Display title: right of Window, before Audio, only while a display is connected (and never with the stock bar)" \
  "grep -q 'static BOOL DMDispMenuWanted(void) { return !gStockBar && DMDispScreens().count > 1; }' $D \
   && awk '/CGFloat winRight = DMLayoutTitle\(fg, rtl, kWinLabelKey/{a=NR} /CGFloat dispRight = DMLayoutTitle\(fg, rtl, kDispLabelKey, kDispButtonKey, kDispPillKey, @\"Display\"/{b=NR} /CGFloat audioRight = DMLayoutTitle/{c=NR} END{exit !(a && b > a && c > b)}' $S \
   && grep -q 'if (DMDispMenuWanted()) amReserve += MAX(DMAMTitleWidth(@\"Display\", timeFont), kTitleMinShown) + amGap;' $S \
   && grep -q 'else if (b == objc_getAssociatedObject(fg, kDispButtonKey)) DMDispMenuOpen(b);' $S"
check "  ... in every list of the bar's titles (hidden together, hovers, the menu check, colours): wherever Window's is, Display's is" \
  "[ \$(grep -c 'kWinButtonKey, kAudioButtonKey' $S) = 0 ] && [ \$(grep -c 'kWinButtonKey, kDispButtonKey, kAudioButtonKey' $S) -ge 7 ] \
   && [ \$(grep -c 'objc_getAssociatedObject(fg, kWinButtonKey)).hidden = YES;' $S) = \$(grep -c 'objc_getAssociatedObject(fg, kDispButtonKey)).hidden = YES;' $S) ] \
   && grep -q 'kWinLabelKey, kDispLabelKey, kAudioLabelKey, kDateProxyKey' $S && grep -q '\"go\", \"window\", \"display\", \"audio\",' $S"
check "  ... its rows: name and mode, its own desktop or a mirror (read only), Display Settings... only on 16+ with Display Settings on" \
  "fn '__attribute__((noinline)) static void DMDispMenuOpen(UIButton *btn) {' $D && grep -q 'initWithTitle:line enabled:NO' \$W/fn \
   && grep -q 'initWithTitle:(extended ? @\"Extended Display\" : @\"Mirroring the iPad\") enabled:NO' \$W/fn \
   && grep -q 'if (os >= 16 && display) {' \$W/fn && grep -q 'initWithTitle:@\"Display Settings…\" enabled:extended handler:DMCloseThen(^{ DMDispSettingsOpen(display, onTV); })' \$W/fn \
   && grep -q 'NSDictionary \*info = MSBDDispStoreInfo(MSBDDispStoreAll(), display);' \$W/fn"
menuplain() {   # <DisplaySettings.h>: with Display Settings off the menu reads no key, registry, mode or CADisplay (review: the guard's step then holds)
  fno '__attribute__((noinline)) static void DMDispMenuOpen(UIButton *btn) {' "$1" > "$W/mo" \
    && awk '/if \(!gDMDispLayerOn\) \{ DMDispMenuOpenPlain\(btn, os, onTV\); return; \}/{a=NR} /DMDispMenuDisplayOf\(btn\)/{b=NR} /MSBDDispStore/{if (!c) c=NR} END{exit !(a && b > a && c > a)}' "$W/mo" \
    && fno 'static void DMDispMenuOpenPlain(UIButton *btn, int os, BOOL onTV) {' "$1" > "$W/mp" && grep -qF '@"External Display"' "$W/mp" \
    && ! grep -q 'DMDispKeyOf\|DMDispMenuDisplayOf\|DMDispModeText\|DMDispIsDesktop\|DMDispDesktopScreen\|DMDispScreens\|MSBDDisp\|CADisplay\|DMSceneLayer\|gDMDisp' "$W/mp"
}
check "  ... with Display Settings off: only External Display and Extended / Mirroring from public calls (no display key, registry, mode or CADisplay read)" "menuplain $D"
cp $D "$W/ds-plain.h"; python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); a="    if (!gDMDispLayerOn) { DMDispMenuOpenPlain(btn, os, onTV); return; }   // (the switch off: no key, registry or mode read)\n"; assert s.count(a)==1; open(p,"w").write(s.replace(a,""))' "$W/ds-plain.h"
cp $D "$W/ds-plain2.h"; python3 -I -c 'import sys; p=sys.argv[1]; s=open(p).read(); a="    NSArray *items = @[ [[DMRow alloc] initWithTitle:@\"External Display\""; assert s.count(a)==1; open(p,"w").write(s.replace(a,"    (void)DMDispMenuDisplayOf(btn);\n"+a))' "$W/ds-plain2.h"
check "made to fail: the menu reading the display with Display Settings off (no gate)" "! menuplain $W/ds-plain.h"
check "made to fail: the switched-off menu deriving the display's key" "! menuplain $W/ds-plain2.h"
check "the title comes and goes with a display; started with the layer" \
  "fn 'static void DMDispSettingsInit(void) {' $D && grep -q 'UIScreenDidConnectNotification, UIScreenDidDisconnectNotification' \$W/fn && grep -q 'if (!DMCtorSkip(\"dispsettings\")) DMDispSettingsInit();' $S \
   && grep -q '#include \"DisplaySettings.h\"' $S"
check "public text in the window and the menu: no em dash, no --" \
  "! grep -n '@\"[^\"]*\($EM\|$EN\| -- \)[^\"]*\"' $D | grep -q . && ! grep -q '$EM\|$EN' $R $ST"
# ---- the crash map
check "crash map: the rows, the store and the window are Display Settings' (file rule), their functions by name (DMDisp...)" \
  "grep -q '^file MacStatusBarCore ^(DisplayPrefs|DisplayIdentity|DisplayRows|DisplayRowStore|DisplaySettings)\\\\.h\$ displaySettings' $M && grep -q '^sym MacStatusBarCore ^_\*DMDisp\[A-Z\] displaySettings' $M \
   && ! grep -E '^(static|__attribute__).*\b(DM[A-Za-z]+)\(' $D | grep -v 'DMDisp[A-Z]' | grep -q ."
# every row's key: a switch row's key is in the crash map (the guard can set it off, and step 1b clears the displays' overrides of it), or the row is a value
# whose code is another feature's (its blame goes there): Dock Size, Magnification's amount and Window Size (values), Magnification (the Dock's layout,
# the Dock part's), New Windows Open at Fill (the Stage Manager engine's window placement); display-only rows (disp) have no iPad key.
python3 -I - "$R" "$M" > "$W/keys" <<'PY'
import re,sys
rows=re.findall(r'\{ "([A-Z_]+)", "[^"]*", (?:"[^"]*"|NULL), (kMSBDRow[A-Za-z]+), "(msb|dock|disp)", "([A-Za-z]+)",[^}]*?, (1[89][07]),', open(sys.argv[1]).read())
dom={'msb':'com.besiktasliseba.macstatusbar','dock':'com.besiktasliseba.dockmagnification'}
targets=set((m.group(1),m.group(2)) for m in re.finditer(r'^target \S+ pref (\S+) (\S+) ', open(sys.argv[2]).read(), re.M))
values={'DOCK_SIZE','MAGNIFICATION_AMOUNT','WINDOW_SIZE','MAGNIFICATION','NEW_WINDOWS_FILL'}
for rid,kind,part,key,slot in rows:
    if slot != '187': continue   # (a later release's rows are hidden: checked when they ship)
    ok = part=='disp' or (dom[part],key) in targets or rid in values
    print(rid, part, key, 'ok' if ok else 'MISSING')
PY
check "  ... every row's key is in the crash map, a value of another feature's, or display-only ($(wc -l < "$W/keys" | tr -d ' ') rows)" "[ \$(wc -l < \$W/keys) = 10 ] && ! grep -q MISSING \$W/keys"
# Made to fail: the table's rules with one thing broken must fail the C test.
mutant() {
  local M2="$W/m-$1"; mkdir -p "$M2/common" "$M2/tools"; cp test-displayrows.c "$M2/tools/"; cp ../common/DisplayPrefs.h "$M2/common/"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' \
    $R "$M2/common/DisplayRows.h" "$2" "$3" || return 1
  clang -O2 -Wall -Wno-unused-function -o "$M2/t" "$M2/tools/test-displayrows.c" 2>/dev/null || return 1
  ! "$M2/t" > "$M2/out"
}
check "made to fail: a later release's rows shown" "mutant release '    if (!r || !c || r->slot > c->release) return false;' '    if (!r || !c) return false;'"
check "made to fail: the Dock rows shown with the Dock part off" "mutant dock '    if ((r->needs & kMSBDRowNeedsDock) && !c->ourDock) return false;' ''"
check "made to fail: the window rows shown with another engine" "mutant sm '    if ((r->needs & kMSBDRowNeedsSM) && !c->smEngine) return false;' ''"
check "made to fail: a display not connected editable" "mutant connected 'c->extended && connected && layerOn;' 'c->extended && layerOn;'"
check "made to fail: iPadOS 15 (mirroring) editable" "mutant os15 'return MSBDDispRowShown(r, c) && c->osMajor >= r->minOS && c->extended && connected && layerOn;' 'return MSBDDispRowShown(r, c) && connected && layerOn;'"
check "made to fail: an em dash let through" "mutant emdash 'strstr(t, \"\\xE2\\x80\\x94\") || ' ''"
check "made to fail: Home Minimizes Windows listed for a TV" "mutant home '    { \"NEW_WINDOWS_FILL\", \"New Windows Open at Fill\", NULL,' '    { \"HOME_MIN\", \"Home Minimizes Windows\", NULL, kMSBDRowSwitch, \"msb\", \"homeMinimizesWindows\", 0, 16, 0, 190, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { \"NEW_WINDOWS_FILL\", \"New Windows Open at Fill\", NULL,'"
check "made to fail: a choice's number out of range taken (clamped)" "mutant clamp 'v != floor(v) || v < 0 || v >= r->choices) return -1;' 'v != floor(v)) return -1; if (v >= r->choices) v = r->choices - 1; if (v < 0) v = 0;'"
check "made to fail: the mirror's words for a display gone" "mutant topnone 'return !layerOn ? MSBD_DISP_TEXT_OFF : !connected ? MSBD_DISP_TEXT_NONE : !extended ? MSBD_DISP_TEXT_MIRROR : MSBD_DISP_TEXT_TOP;' 'return !layerOn ? MSBD_DISP_TEXT_OFF : !extended ? MSBD_DISP_TEXT_MIRROR : !connected ? MSBD_DISP_TEXT_NONE : MSBD_DISP_TEXT_TOP;'"
check "made to fail: a slider's value left off its range" "mutant slider '    if (v < r->lo) v = r->lo;' ''"
check "made to fail: the Trash's footer without its display default" "mutant trash 'On for displays unless you switch it off here, even when it is off on the iPad.' 'Shows the Trash.'"
[ $fails = 0 ] && echo "test-displayrows: wiring checks pass" || { echo "test-displayrows: wiring checks FAILED"; exit 1; }
