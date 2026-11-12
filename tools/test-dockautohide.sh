#!/bin/bash
# Mac test of Settings > Dock > Automatically Hide and Show the Dock (1.8.4 item 4): the rules in plain C (common/DockAutoHide.h, test-dockautohide.c):
# the switch as stored, the Stage Manager engine's two-way sync with Apple's own "Dock" tick (SBChamoisHideDock), the room it leaves for windows; and the
# wiring: Settings (the switch, off by default), the Dock part (dock/DockAutoHide.m: the Home Screen's own Dock assertion), the status bar part
# (statusbar/StatusBar.x: the room for windows, Stage Manager's in-app answer and stage area, the tick's sync) and the crash guard.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -std=c11 -O1 -Wall -Werror -o "$W/tah" test-dockautohide.c && "$W/tah" || fails=1
A=../dock/DockAutoHide.m; D=../dock/Dock.x; S=../statusbar/StatusBar.x; P=../dock/dockmagnificationprefs/Resources/Root.plist
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
check "Settings > Dock: Automatically Hide and Show the Dock (autoHideDock, off by default), in its own group just before Animate Opening Applications" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; ids=[x.get('id') for x in it]; i=ids.index('AUTO_HIDE_DOCK'); s=it[i]
sys.exit(0 if s['key']=='autoHideDock' and s['default'] is False and s['cell']=='PSSwitchCell' and s['label']=='Automatically Hide and Show the Dock' and s['defaults']=='com.besiktasliseba.dockmagnification' and s['PostNotification']=='com.besiktasliseba.dockmagnification/prefsChanged' and it[i-1].get('id')=='AUTO_HIDE_DOCK_GROUP' and 'swipe up from the bottom' in it[i-1].get('footerText','') and ids[i+1]=='ANIMATE_OPENING_GROUP' else 1)\""
check "the Dock part reads it as stored, with the Dock part on only" \
  "fn $D 'static void DMLoadPrefs(' | grep -q 'DMDockAutoHideSetOn(MSBDAutoHideOn(MSBDAutoHideStored(isBool, isBool && CFBooleanGetValue(ah))) && tweakOn);'"
check "DockAutoHide.m is built into the Dock part" "grep -q '^DockMagnification_FILES = .* DockAutoHide.m' ../dock/Makefile"
check "the Home Screen's own assertion only (level 0, reason homescreen), its two getters hooked only in their 18.5 shapes, and only once the switch is on" \
  "fn $A 'static BOOL DMAutoHideIsHomeScreen(' | grep -q 'isEqualToString:@\"homescreen\"' && fn $A 'static BOOL DMAutoHideInstall(' | grep -q '\"d16@0:8\")' \
   && fn $A 'static BOOL DMAutoHideInstall(' | grep -q '\"B16@0:8\")' && fn $A 'void DMDockAutoHideSetOn(' | grep -q 'if (on && !DMAutoHideInstall()) return;'"
check "  ... answered by the rules (away with the gesture possible) while the switch is on, iPadOS's own answer else" \
  "fn $A 'static double DMAutoHideProgress(' | grep -q 'MSBDAutoHideHomeHides(gDockAutoHide, gDockAutoHideEditing) && DMAutoHideIsHomeScreen(self) ? MSBDAutoHideHomeProgress(1, p) : p;' \
   && fn $A 'static BOOL DMAutoHideGesture(' | grep -q 'MSBDAutoHideHomeHides(gDockAutoHide, gDockAutoHideEditing) && DMAutoHideIsHomeScreen(self) ? (BOOL)MSBDAutoHideHomeGesture(1, g) : g;'"
check "M2 (review 1.8.4 Pass 4): while the Home Screen is edited the Dock shows (the Dock's controller told of editing passes it on), and goes away again after" \
  "fn $D 'static void DMDockSetEditing(' | grep -q '    DMDockAutoHideSetEditing(editing);' \
   && fn $A 'void DMDockAutoHideSetEditing(' | grep -q 'if (\\[UIApplication sharedApplication\\]) DMAutoHideApplyNow(!editing);' \
   && fn $A 'void DMDockAutoHideSetOn(' | grep -q 'DMAutoHideApplyNow(MSBDAutoHideHomeHides(on, gDockAutoHideEditing));'"
check "nothing of ours created: no assertion allocated or initialised anywhere in the Dock's auto-hide" \
  "! grep -q 'initWithFloatingDockController' $A && ! grep -q 'alloc\\]' $A"
check "a change of the switch applies now where the Home Screen's assertion decides: SpringBoard's own clear and evaluate (the active one derived anew, as its remove does; not mode 2, which only re-reads it), else its dismiss and present" \
  "fn $A 'static void DMAutoHideApplyNow(' | grep -q 'if (!DMAutoHideHomeScreenDecides(ctrl, gesture)) continue;' \
   && fn $A 'static void DMAutoHideApplyNow(' | grep -q 'sel_registerName(\"_evaluateAssertions:interactive:withCompletion:\"), 1, NO, ^{});' \
   && ! fn $A 'static void DMAutoHideApplyNow(' | grep -q '_updateFloatingDockBehaviorAssertionsInteractive' \
   && fn $A 'static void DMAutoHideApplyNow(' | grep -q 'if (gesture) ((void (\\*)(id, SEL))objc_msgSend)(ctrl, sel_registerName(\"_clearGestureAssertion\"));'"
check "L1 (review 1.8.4 Pass 4): every completion handed to SpringBoard is an empty block, never nil (one called unchecked is a crash)" \
  "fn $A 'static void DMAutoHideApplyNow(' | grep -q 'withCompletion:\"), 1, NO, ^{});' && ! grep -q 'NO, nil);' $A && ! grep -q 'YES, nil);' $A"
check "  ... on every Dock's controller: each Dock window's own and the iPad's from SpringBoard's icon controller (iPadOS 15: no window answers it)" \
  "fn $A 'static void DMAutoHideApplyNow(' | grep -q 'for (id ctrl in DMDockAutoHideControllers()) {' \
   && fn $A 'NSArray *DMDockAutoHideControllers(' | grep -q 'DMAutoHideShape(ic, \"floatingDockController\", \"@16@0:8\")' \
   && fn $A 'NSArray *DMDockAutoHideControllers(' | grep -q 'if (\[main isKindOfClass:dc\] && !\[out containsObject:main\]) \[out addObject:main\];'"
check "H1 (review 1.8.4 Pass 4): the switch read before SpringBoard is up (the constructor, at a respring) applies nothing then: the hooks answer the first layout" \
  "fn $A 'void DMDockAutoHideSetOn(' | grep -q 'if (\\[UIApplication sharedApplication\\]) DMAutoHideApplyNow(MSBDAutoHideHomeHides(on, gDockAutoHideEditing));'"
check "  ... and SpringBoard's icon controller is never made by us: +sharedInstanceIfExists where it is there, else +sharedInstance only once SpringBoard is up with its Dock's window" \
  "fn $A 'static id DMAutoHideIconController(' | grep -q 'class_getClassMethod(icc, sel_registerName(\"sharedInstanceIfExists\"));' \
   && fn $A 'static id DMAutoHideIconController(' | grep -q 'if (!dockWindowSeen || !\\[UIApplication sharedApplication\\]) return nil;' \
   && fn $A 'NSArray *DMDockAutoHideControllers(' | grep -q 'id ic = DMAutoHideIconController(windowSeen);' \
   && [ \$(grep -c 'sel_registerName(\"sharedInstance\")' $A) = 1 ] && fn $A 'static id DMAutoHideIconController(' | grep -q 'sel_registerName(\"sharedInstance\")'"
check "  ... the decider read as SpringBoard derives it (the highest assertion, the gesture one left out), the levels' C array only in its own shape" \
  "fn $A 'static BOOL DMAutoHideHomeScreenDecides(' | grep -q 'int levels = MSBDAutoHideLevelsOf(iv ? ivar_getTypeEncoding(iv) : NULL);' \
   && fn $A 'static BOOL DMAutoHideHomeScreenDecides(' | grep -q 'if (levels > 0) {' \
   && fn $A 'static BOOL DMAutoHideHomeScreenDecides(' | grep -q 'if (!a || a == gesture) continue;'"
check "L2 (review 1.8.4 Pass 4): the levels' C array is read only in exactly its shape (DockAutoHide.h MSBDAutoHideLevelsOf), in the Dock part and its debug copy; no sscanf of it left" \
  "grep -q 'int levels = MSBDAutoHideLevelsOf(t);' $D && ! grep -q 'sscanf' $A && ! grep -q 'sscanf(t, ' $D"
check "the status bar part asks the Dock part's own answer (one truth: the switch with the part on and its hooks in place)" \
  "grep -q '^__attribute__((visibility(\"default\"))) BOOL MSBDDockAutoHides(void) { return gDockAutoHide; }' $A && fn $S 'static BOOL DMDockAutoHideLive(' | grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDockAutoHides\")'"
check "L3 (review 1.8.4 Pass 4): hooks that could not be made (the Dock part says -1): the switch stored on is no change of the Dock for the windows, and Stage Manager's tick is not written" \
  "grep -q '^__attribute__((visibility(\"default\"))) int MSBDDockAutoHideHooks(void) { return gDockAutoHideHooks; }' $A \
   && fn $A 'static BOOL DMAutoHideInstall(' | grep -q 'if (!ok) { gDockAutoHideHooks = -1;' \
   && fn $S 'static int DMDockAutoHideHooks(' | grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDockAutoHideHooks\")' \
   && fn $S 'static int DMDockAutoHideStoredOn(' | grep -q 'return MSBDAutoHideOn(ours) && partOn && loaded && MSBDAutoHideCanAct(DMDockAutoHideHooks());' \
   && fn $S 'static void DMDockAutoHideSyncSM(' | grep -q 'if (!MSBDAutoHideCanAct(DMDockAutoHideHooks())) {'"
check "the room for windows down to the screen's edge while it hides: the desktop at the bottom, the side's desktop, Stage Manager's stage area (1.8.7: by the pass's display)" \
  "fn $S 'static CGRect DMUsableArea(' | grep -q 'if (DMDockAutoHides()) {' && fn $S 'static CGRect DMDockSideDesktopOf(' | grep -q 'if (DMDockAutoHides()) {' \
   && fn $S 'static CGRect DMSMOurStageArea(' | grep -q 'MSBDAutoHideRoomEdge(DMDockAutoHidesOnSize(b.size), line, CGRectGetMaxY(b))'"
check "  ... and Stage Manager's own bottom limit for a window (17 / 18) is the screen's edge then, as with the Dock at a side (Fill came out 30 pt short)" \
  "fn $S 'static id DMSMBottomInsets17(' | grep -q 'DMSMFree() && (DMDockSideNow(\[UIScreen mainScreen\].bounds.size) || hides) ? @\[@0.0\] : v;' \
   && fn $S 'static id DMSMBottomInsets17(' | grep -q 'BOOL hides = DMSMCfgBounds(cfg, &b) ? DMDockAutoHidesOnSize(b.size) : DMDockAutoHides();' \
   && fn $S 'static void DMSMHookBottomInsets17(' | grep -q 'gDMDockPosition != MSBDDockRight && gDMDockAutoHideTaken <= 0 && !DMDockAutoHideAnyTakenOn())) return;'"
check "Stage Manager engine: the Dock hidden in a stage too (the switcher's in-app answer), also where Apple's tick can't follow" \
  "awk '/^- \\(BOOL\\)shouldConfigureInAppDockHiddenAssertion \\{/,/^}/' $S | grep -q 'BOOL r = keyboard || full || MSBDAutoHideInAppPref(otherDisplay, prefers, autoHide, displayHides);'"
check "the tick's sync: only with the Stage Manager engine, through SpringBoard's own getter and setter, by the rules, written once per switch value" \
  "fn $S 'static void DMDockAutoHideSyncSM(' | grep -q 'if (gDMAutoHideSyncing || !DMSMEngine()) return;' \
   && fn $S 'static void DMDockAutoHideSyncSM(' | grep -q 'int step = MSBDAutoHideSync(ours, apple, synced), after = apple;' \
   && fn $S 'static void DMDockAutoHideSyncSM(' | grep -q 'if (MSBDAutoHideWritesApple(step, ours, gDMAutoHideAppleRefused)) {' \
   && fn $S 'static void DMDockAutoHideSyncSM(' | grep -q 'int value = MSBDAutoHideSyncedValue(ours, apple, step, after);' \
   && ! grep -q 'SBChamoisHideDock' $S"
check "M1 (KT 7 Nov, review 1.8.4 Pass 4): Apple's tick is written as the rules say for our switch (never set: off, so shown), never read into a switch never set" \
  "fn $S 'static void DMDockAutoHideSyncSM(' | grep -q 'objc_msgSend)(sd, set, (BOOL)MSBDAutoHideTickFor(ours));' && ! fn $S 'static void DMDockAutoHideSyncSM(' | grep -q 'objc_msgSend)(sd, set, ours > 0);'"
check "  ... run once Stage Manager is up as the engine, at each change of the Dock's settings, and at each change of Apple's tick" \
  "grep -q '        DMDockAutoHideSMTick(on);' $S && fn $S 'static void DMWatchDockChanges(' | grep -q 'DMDockAutoHideSyncSM(@\"the Dock' \
   && fn $S 'static void DMDockAutoHideSMTick(' | grep -q '@\\[@\"chamoisHideDock\"\\], dispatch_get_main_queue(), ^{ DMDockAutoHideSyncSM('"
check "a change of the switch: the layouts read against the room as it was (the Dock part may take the notification first), the new answer taken after" \
  "fn $S 'static void DMDockChangedRelayout(' | grep -q 'BOOL ahChanged = gDMDockAutoHideTaken >= 0 && ahWant != gDMDockAutoHideTaken;' \
   && fn $S 'static void DMDockChangedRelayout(' | grep -q 'if (ahChanged) { BOOL loaded = NO, v = DMDockAutoHideLive(&loaded); if (loaded) gDMDockAutoHideTaken = v; if (v) DMSMHookBottomInsets17(); }' \
   && fn $S 'static BOOL DMDockAutoHides(' | grep -q 'return gDMDockAutoHideTaken > 0;'"
check "  ... then every window in a layout into the same layout of the new desktop, on every engine; Stage Manager with none: its stage laid out again" \
  "fn $S 'static void DMDockChangedRelayout(' | grep -q 'if (moved || ahChanged) DMDockPositionMoved(layouts);' \
   && fn $S 'static void DMDockChangedRelayout(' | grep -q 'if (DMSMEngine()) { if (layouts.count) DMSMApplyLayouts(layouts); else if (ahChanged) DMDockAutoHideSMPass(); }' \
   && fn $S 'static void DMDockAutoHideSMPass(' | grep -q 'if (front.length && DMSMRequestWindow(front, nil, -1))' && fn $S 'static void DMDockAutoHideSMPass(' | grep -q 'DMSMSpotlightHolds() || DMGARefuses('"
check "a crash in the Dock's auto-hide (DockAutoHide.m) turns only Automatically Hide and Show the Dock off, not the whole Dock" \
  "grep -q '^target autoHideDock pref com.besiktasliseba.dockmagnification autoHideDock 0 0 Automatically Hide and Show the Dock|' crashmap-rules.txt && grep -q '^file DockMagnification ^DockAutoHide\\\\.m\$ autoHideDock\$' crashmap-rules.txt"
check "F2 (regression 1.8.4, A12Z Stage Manager): the Dock's room the windows are placed for is saved with them -- the window state and Stage Manager's state file (the answer pending since the start, else the one taken now) -- and read back at the start" \
  "fn $S 'static void DMSaveWindowState(void) {' | grep -qF '{ int room = DMDockRoomSaved(); if (room >= 0) saving[@\"dockAutoHide\"] = @(room); }' \
   && fn $S 'static void DMSMStateWrite(void) {' | grep -qF '{ int room = DMDockRoomSaved(); if (room >= 0) st[@\"dockAutoHide\"] = @(room); }' \
   && grep -qF 'static int DMDockRoomSaved(void) { return MSBDRoomToSave(gDMWindowsRoomPending, DMDockRoomNow()); }' $S \
   && grep -qF 'static BOOL DMDockRoomChangedSinceSave(void) { return MSBDRoomAtStart(gDMWindowsRoomPending, DMDockRoomNow()) == MSBDRoomChanged; }' $S \
   && fn $S 'static int DMDockRoomNow(void) {' | grep -qF 'return MSBDRoomNowFrom(loaded, loaded && DMDockAutoHides(), DMDockPartSwitchedOn(), DMProcessAge());' \
   && fn $S 'static BOOL DMDockPartSwitchedOn(void) {' | grep -qF 'CFPreferencesCopyValue(CFSTR(\"tweakEnabled\"), dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' \
   && fn $S 'static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) {' | grep -qF 'if (DMSMEngine() && gDMWindowsRoomPending < 0 && [room isKindOfClass:[NSNumber class]]) gDMWindowsRoomPending = [room boolValue] ? 1 : 0;' \
   && fn $S 'static void DMRestoreWindows(int attempt) {' | grep -qF 'gDMWindowsRoomPending = [room isKindOfClass:[NSNumber class]] ? ([room boolValue] ? 1 : 0) : -1;'"
check "  ... Stage Manager: while the room differs from the saved one no note is taken among the notes (the ones of windows placed since are kept apart: test-roomwaitnotes); once the desktop is back the windows follow it as at a change in Settings (each into its layout from before the respring, any other kept out of the Dock, the stages not on screen too), then the answer is written -- the step reads the saved room first and waits while the Dock part does not answer (M1), the start tick acts with the Stage Manager engine only (H1); their behaviour: test-layoutnote.m, test-dockautohide.c" \
  "fn $S 'static void DMSMTurnNote(void) {' | awk '/\(void\)DMSMTurnLayouts\(\);/{a=NR} /if \(DMDockRoomChangedSinceSave\(\)\) \{ DMSMRoomWaitNote\(frames\); return; \}/{b=NR} /NSDictionary<NSString \*, NSString \*> \*layouts = DMSMLayoutsFor\(frames\);/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $S 'static void DMDockRoomAfterStartSMTry(int tries) {' | grep -qF 'if (layouts.count) DMSMApplyLayouts(layouts); else DMDockAutoHideSMPass();' \
   && fn $S 'static void DMDockRoomAfterStartSMTry(int tries) {' | grep -qF 'DMDockPositionMoved(layouts);' \
   && fn $S 'static void DMDockRoomAfterStartSMTry(int tries) {' | awk '/if \(!DMSMEngine\(\)\) return;/{a=NR} /\(void\)DMSMTurnLayouts\(\);/{b=NR} /int at = MSBDRoomAtStart\(gDMWindowsRoomPending, DMDockRoomNow\(\)\);/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $S 'static void DMDockRoomAfterStartSMTry(int tries) {' | grep -qF 'if (at == MSBDRoomUnknown) return;' \
   && fn ../statusbar/SMHome.h 'static void DMSMRestoreDesktopTick(void) {' | awk 'NR == 2 && /^    DMSMRoomTick\(\);$/{a=1} /gSMRestoreDone = YES;$/{b=NR} /\^\{ DMDockRoomAfterStartSM\(\); \}\);/{c=NR} END{exit !(a && b && c > b)}' \
   && fn ../statusbar/SMHome.h 'static void DMSMRoomTick(void) {' | grep -qF 'int a = MSBDRoomTick(gDMWindowsRoomPending, DMSMEngine(), DMSMFree(), gSMHomeOn && gSMHomeStart > 0,'"
check "  ... Aerial, Zetsu, MilkyWay4: the restore brings each window saved in a layout back in that layout of the desktop as it is, then the rest follows the room; a change in Settings ends a pending one and writes the answer" \
  "fn $S 'static void DMRestoreStep(NSArray *wins, NSUInteger i, NSDictionary *state, int waited) {' | grep -qF 'CGRect lf = lay ? DMLayoutFrame(lay) : CGRectNull;' \
   && fn $S 'static void DMFinishRestore(NSDictionary *state) {' | awk '/if \(DMDockRoomChangedSinceSave\(\)\) \{/{a=NR} /DMDockPositionMoved\(nil\);/{b=NR} /gDMWindowsRoomPending = -1;/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $S 'static void DMDockChangedRelayout(NSString *why) {' | grep -qF 'if (ahChanged) gDMWindowsRoomPending = -1;' \
   && fn $S 'static void DMDockChangedRelayout(NSString *why) {' | grep -qF 'if (ahChanged && DMSMEngine()) DMSMStateWrite();'"
# ---- 1.8.7: per display (plans/design-1.8.7-displays.md section 5: through Stage Manager, not the Home Screen's assertion) ----
check "1.8.7: the Dock part answers per screen (MSBDDockAutoHidesOn): the iPad's own screen the switch as before, another display its own setting from the iPad's answer, the Dock part on" \
  "grep -q '^__attribute__((visibility(\"default\"))) BOOL MSBDDockAutoHidesOn(UIScreen \*s) {' $A && fn $A '__attribute__((visibility(\"default\"))) BOOL MSBDDockAutoHidesOn(' | grep -q 'if (!s || s == \[UIScreen mainScreen\]) return gDockAutoHide;' \
   && fn $A '__attribute__((visibility(\"default\"))) BOOL MSBDDockAutoHidesOn(' | grep -q 'return DMDispDockBool(s, kMSBDAutoHideKey, gDockAutoHide);' \
   && grep -qF 'BOOL DMDispDockBool(UIScreen *s, const char *key, BOOL ipad) { return gTweakOn && DMDispBool(s, \"dock\", key, ipad); }' $D"
check "  ... the status bar part asks it for that screen, taken per display as the iPad's (first ask, then at a change), forgotten when a display comes or goes" \
  "fn $S 'static BOOL DMDockAutoHideLiveOn(' | grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDockAutoHidesOn\")' && fn $S 'static BOOL DMDockAutoHidesOn(' | grep -q 'if (!k) return DMDockAutoHides();' \
   && fn $S 'static BOOL DMDockAutoHidesOn(' | grep -q 'gDMDockAutoHideTakenOn\[k\] = @(v);' && grep -q 'usingBlock:^(NSNotification \*note) { DMDockAutoHideForgetDisplays(); }\];' $S"
check "  ... Stage Manager's in-app answer by its own stage's display (S5), the TV's desktop and Apple's bottom limit by their display" \
  "awk '/^- \\(BOOL\\)shouldConfigureInAppDockHiddenAssertion \\{/,/^}/' $S | grep -q 'BOOL displayHides = otherDisplay ? DMDockAutoHidesForIdentity(ownDisplay) : autoHide;' \
   && fn $S 'static CGRect DMSMUsableAreaForIdentity(id identity, CGSize \*screenOut) {' | grep -q 'CGFloat bottom = MSBDAutoHideRoomEdge(DMDockAutoHidesOn(sc), size.height - dh - 2.0, size.height);' \
   && fn $S 'static UIScreen \*DMSMScreenOfSize(CGSize size) {' | grep -q 'connectedScenes'"
check "  ... a display's change (its own, or the iPad's it follows): its windows in a layout read against the old room, the answer taken, then into the same layouts (or its stage laid out again); at the displays domain's note and the Dock's" \
  "fn $S 'static void DMDockAutoHideDisplaysFollow(' | grep -q 'NSDictionary \*layouts = DMSMEngine() ? DMSMLayoutsOnScreen(s, &stage) : @{};' \
   && fn $S 'static void DMDockAutoHideDisplaysFollow(' | grep -q 'gDMDockAutoHideTakenOn\[c\[0\]\] = @(v);' && fn $S 'static void DMDockAutoHideDisplaysFollow(' | grep -q 'if (layouts.count) DMSMApplyLayoutsIn(layouts, stage);' \
   && fn $S 'static void DMDockAutoHideDisplaysFollow(' | grep -q 'DMSMSpotlightHolds() || DMGARefuses(' && fn $S 'static void DMDockChangedRelayout(' | grep -q 'DMDockAutoHideDisplaysFollow(ahWant, why);' \
   && grep -q 'notify_register_dispatch(MSBD_DISP_NOTIFY, &dtoken, dispatch_get_main_queue(), ^(int t) { DMDispReload(); DMDockAutoHideDisplaysFollow(DMDockAutoHideStoredOn(), @\"a display' $S \
   && fn $S 'static BOOL DMDockAutoHideWantOn(' | grep -q 'return loaded && DMDockPartSwitchedOn() && DMDispBool(s, \"dock\", kMSBDAutoHideKey, ipadWant != 0);'"
check "  ... the Home Screen's assertion stays the iPad's (a TV's Dock hides through Stage Manager only)" "! grep -q 'DMDispDockBool\|MSBDDockAutoHidesOn' <(fn $A 'static double DMAutoHideProgress(') && ! fn $A 'static BOOL DMAutoHideGesture(' | grep -q 'MSBDDockAutoHidesOn'"
mutant() {   # <name> <old> <new>: common/DockAutoHide.h with one rule broken must fail the C test
  local M="$W/m-$1"; mkdir -p "$M/common" "$M/tools"; cp test-dockautohide.c "$M/tools/"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' ../common/DockAutoHide.h "$M/common/DockAutoHide.h" "$2" "$3" || return 1
  clang -std=c11 -O1 -Wall -o "$M/t" "$M/tools/test-dockautohide.c" 2>/dev/null || return 1
  ! "$M/t" > /dev/null
}
check "made to fail: a TV's Dock by the iPad's switch only (its own setting ignored)" "mutant tvown '    return displayHides || (applePrefers && !ipadHides);' '    return applePrefers || ipadHides;'"
check "made to fail: Apple's tick taken on a TV even where it is only the iPad's switch (a TV switched off would still hide)" "mutant tvtick '    return displayHides || (applePrefers && !ipadHides);' '    return displayHides || applePrefers;'"
check "made to fail: the iPad's stage taking a display's answer" "mutant ipad '    if (!otherDisplay) return applePrefers || ipadHides;' '    if (!otherDisplay) return displayHides;'"
check "a release-build feature marker when it goes on" "fn $A 'void DMDockAutoHideSetOn(' | grep -q 'DM_FEATURE_MARK(\"dock-auto-hide\");'"
check "no em dash in the rules, the code, the test or the Settings text" "! grep -q \$'\\xe2\\x80\\x94' ../common/DockAutoHide.h test-dockautohide.c test-dockautohide.sh $A $P"
[ $fails = 0 ] && echo "test-dockautohide: all checks pass" || { echo "test-dockautohide: checks FAILED"; exit 1; }
