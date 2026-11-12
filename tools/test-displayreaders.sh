#!/bin/bash
# Mac test of the per-display settings' readers (1.8.7 from commit 5; plans/design-1.8.7-displays.md section 5): each reader asks with its own
# Dock's screen (or its stage's display), the iPad's own screen gets the iPad's value at once, and no other code calls the getters. The rule itself is
# test-displayprefs's. Each check is a function of the files it reads, so a copy of a source with one reader broken runs the same check: those
# made-to-fail copies, last, must each fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if (eval "$2"); then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
D=../dock/Dock.x; DP=../dock/DisplayPrefs.h; T=../statusbar/DockTrash.h; L=../statusbar/DisplayPrefs.h; S=../statusbar/StatusBar.x; P=../common/DisplayPrefs.h; WF=../statusbar/WiFiMenu.h; SL=../statusbar/SceneLayer.h

# ---- commit 5: the Dock part's own layer ----------------------------------------------------------------------------------------------------------
c_dock_getters() {   # <dock/DisplayPrefs.h>: the iPad's own screen (or none) returns the iPad's value at once, no key, no lookup
  for g in 'static BOOL DMDispBool(UIScreen *s,' 'static double DMDispNum(UIScreen *s,'; do
    grep -A1 -F "__attribute__((unused, noinline)) $g" "$1" | tail -1 | grep -q 'if (!s || s == \[UIScreen mainScreen\]) return ipad;' || return 1
  done
  fn 'static id DMDispResolveFor(' "$1" > "$W/r" && grep -q 'BOOL typeOK = MSBDDispTypeOK(want, got, num, hasRange, lo, hi);' "$W/r" \
    && grep -q 'int hasDef = MSBDDispDisplayDefault(part, key, def);' "$W/r" && grep -q '\*from = MSBDDispResolve(0, gDMDispLayerOn, ov != nil, typeOK, hasDef);' "$W/r"
}
c_dock_cache() {   # <dock/DisplayPrefs.h> <Dock.x>: the Dock's own cache (part dock, every display, the master switch), its own key, read with its settings
  fn '__attribute__((noinline)) static void DMDispReload(void) {' "$1" > "$W/c" && grep -q 'gDMDispLayerOn = !\[master isKindOfClass:\[NSNumber class\]\] || \[master boolValue\];' "$W/c" \
    && grep -q 'strcmp(part, "dock") != 0) continue;' "$W/c" && ! grep -q 'connected\|MSBD_DISP_CONNECTED_KEY' "$1" && ! grep -q 'CFPreferencesSet' "$1" \
    && grep -q 'k = MSBDDispKeyOfScreen(s) ?: @"";' "$1" && grep -q '#include "../common/DisplayIdentity.h"' "$1" \
    && fn 'static void DMLoadPrefs(void) {' "$2" | grep -q '    DMDispReload();   // (1.8.7' \
    && grep -q 'DMDockDisplaysChanged, CFSTR(MSBD_DISP_NOTIFY), NULL,' "$2" && c_dock_note "$1" "$2" && grep -q '    DMDispInit();   // (1.8.7' "$2" && grep -q '#include "DisplayPrefs.h"' "$2"
}
c_dock_note() {   # <dock/DisplayPrefs.h> <Dock.x>: the displays domain's note (also the registry's, at every connect / disconnect) relays the Dock out only when a Dock override or the master switch changed
  fn 'static BOOL DMDispReloadChanged(void) {' "$1" > "$W/rc" && grep -qF 'NSDictionary *was = gDMDispCache; BOOL wasOn = gDMDispLayerOn;' "$W/rc" \
    && grep -qF 'return wasOn != gDMDispLayerOn || !(was == gDMDispCache || [was isEqualToDictionary:gDMDispCache]);' "$W/rc" \
    && fn 'static void DMDockDisplaysChanged(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) {' "$2" > "$W/dn" \
    && awk '/if \(!DMDispReloadChanged\(\)\) return;/{a=NR} /DMPrefsChanged\(c, o, n, obj, info\);/{b=NR} END{exit !(a && b > a)}' "$W/dn" \
    && [ "$(grep -c 'CFSTR(MSBD_DISP_NOTIFY)' "$2")" = 1 ]
}
c_dock_note_one() { c_dock_note $DP "$1"; }
c_dock_note_dp() { c_dock_note "$1" $D; }
c_dock_rows() {   # <Dock.x>: each Dock row by its key in the dock part, its range as the iPad's reading has it, with the Dock part on only
  grep -qF 'static CGFloat DMDockIconSizeOn(UIScreen *s) { return gTweakOn ? DMDispNum(s, "dock", "dockIconSize", gIconSize, 0.4, 1.5) : gIconSize; }' "$1" \
    && grep -qF 'static BOOL DMDockMagOn(UIScreen *s) { return gTweakOn && DMDispBool(s, "dock", "enabled", gEnabled); }' "$1" \
    && grep -qF 'static CGFloat DMDockMagOf(UIScreen *s) { return DMDispNum(s, "dock", "magnification", gMagnification, 1.0, 3.0); }' "$1"
}
c_dock_size() {   # <Dock.x>: the Dock's layout asks with its own screen (size, the magnification's room), no iPad global left there
  fn '- (void)getMetrics:(DMDockMetrics *)m forBounds:(CGRect)bounds {' "$1" > "$W/g" \
    && awk '/UIScreen \*dockScreen = \(\(UIView \*\)self\).window.windowScene.screen \?: \[UIScreen mainScreen\];/{a=NR} /CGFloat iconSize = DMDockIconSizeOn\(dockScreen\);/{b=NR} /CGFloat f = iconSize;/{c=NR} END{exit !(a && b > a && c > b)}' "$W/g" \
    && grep -qF 'CGFloat headroom = DMDockMagOn(dockScreen) ? MAX(0.0, DMDockMagOf(dockScreen) - 1.0) *' "$W/g" && ! grep -v 'R(bounds), R(m->userList)' "$W/g" | grep -qE '\b(gIconSize|gMagnification|gEnabled)\b'   # (the diagnostics record keeps the iPad's settings)
}
c_dock_lift() {   # <Dock.x>: the room kept above the platter for the magnified icons, by that Dock's screen
  fn 'static BOOL DMDockNeedsFloat(UIView *dockWindow) {' "$1" > "$W/l" \
    && grep -qF 'CGFloat lift = DMDockMagOn(dockScreen) ? MAX(12.0, (side ? dock.size.width : dock.size.height) * (MAX(DMDockMagOf(dockScreen), 1.0) - 1.0) + 6.0) : 4.0;' "$W/l" \
    && ! grep -qE '\b(gMagnification|gEnabled)\b' "$W/l"
}
c_dock_hover() {   # <Dock.x>: the magnification under the pointer is its Dock's display's, taken at the hover's start and at a settings change
  grep -qF 'static CGFloat DMScale(CGFloat offset) { return 1.0 + (gHoverMag - 1.0) * DMBell(offset) * gInfluence; }' "$1" \
    && fn 'static void DMDockHoverTake(UIView *platter) {' "$1" | grep -qF 'gHoverMagOn = DMDockMagOn(s); gHoverMag = DMDockMagOf(s); gHoverTaken = platter;' \
    && fn 'static void DMDockHoverTake(UIView *platter) {' "$1" | grep -qF 'UIScreen *s = platter.window ? DMDockScreenOf(platter.window) : nil;' \
    && grep -qF 'if (!gHovering || gHoverTaken != self) DMDockHoverTake(self);' "$1" && fn 'static void DMPrefsChanged(' "$1" | grep -qF 'if (gHoverTaken) DMDockHoverTake(gHoverTaken);' \
    && grep -qF 'BOOL want = gHoverMagOn && gHovering;' "$1" && fn 'static void DMDockHoverTouchBegan(void) {' "$1" | grep -qF 'if (gHovering && gHoverMagOn && gLinkPlatter) {' \
    && fn 'static BOOL DMDockHoverHold(UIView *platter, UIGestureRecognizer *g) {' "$1" | grep -qF 'gHovering && gHoverMagOn,' \
    && ! awk '/^- \(void\)dm_tick:/,/^}/' "$1" | grep -qE '\b(gEnabled|gMagnification)\b'
}
c_dock_trash() {   # <Dock.x>: a Dock's Trash by its own screen's Show Trash in Dock (the iPad's switch for the iPad), only while Finder runs
  fn 'static BOOL DMDockShowsTrash(UIView *dockView) {' "$1" > "$W/t" && grep -qF 'if (!gTrashFinderRuns) return NO;' "$W/t" \
    && grep -qF 'return DMDispBool(w ? DMDockScreenOf(w) : nil, "dock", "showTrash", gShowTrash);' "$W/t" && ! grep -q 'DMDockOnMainScreen' "$W/t"
}
c_finder_trash() {   # <DockTrash.h>: Finder serves the bin while the iPad's or any connected display's Dock shows it; a display's change applies at once
  fn 'static BOOL DMDockTrashExternalDisplay(void) {' "$1" > "$W/f" && grep -qF 'BOOL ipad = DMDockTrashPrefOn();' "$W/f" \
    && grep -qF 'for (UIScreen *s in DMDispScreens()) if (s != [UIScreen mainScreen] && DMDispBool(s, "dock", "showTrash", ipad)) return YES;' "$W/f" \
    && grep -qF 'notify_register_dispatch(MSBD_DISP_NOTIFY, &t4, dispatch_get_main_queue(), ^(int t) { DMDispReload(); DMDockTrashApplyPref(); });' "$1" \
    && grep -qF 'BOOL on = gFinderOn && (DMDockTrashPrefOn() || DMDockTrashExternalDisplay());' "$1"
}
check "the Dock part's getters: the iPad's own screen (or none) returns the iPad's value at once; a display by the shared rule" "c_dock_getters $DP"
check "the Dock part's own cache (every display's dock overrides, the master switch) and its own display key (no registry: Mac Status Bar may be off), read with the Dock's settings and the displays domain's note" "c_dock_cache $DP $D"
check "the Dock rows: Size (dockIconSize 0.4-1.5), Magnification (enabled), its amount (magnification 1-3), with the Dock part on only" "c_dock_rows $D"
check "the Dock's layout asks with its own screen: its size and the magnification's room at its ends; no iPad global left in it" "c_dock_size $D"
check "the room above the platter for the magnified icons, by that Dock's screen" "c_dock_lift $D"
check "the magnification under the pointer: the hovered Dock's display's, taken at the hover's start and again at a settings change; the link reads only that" "c_dock_hover $D"
check "Show Trash in Dock by the Dock's own screen (the iPad's switch for the iPad's Dock, a TV's own: ON by default), while Finder runs" \
  "c_dock_trash $D && grep -qF 'if (part && key && strcmp(part, \"dock\") == 0 && strcmp(key, \"showTrash\") == 0) { if (value) *value = 1; return 1; }' $P"
check "Finder's side: the bin served while the iPad's or any connected display's Dock shows it; a display's own change taken at once" "c_finder_trash $T"
check "the status bar part's cache holds every remembered display (a display is asked for before the registry lists it: at connect, after the start)" \
  "fn '__attribute__((noinline)) static void DMDispReload(void) {' $L > \$W/sl && grep -qF 'if (!mine) cache[d] = mine = [NSMutableDictionary dictionary];' \$W/sl && ! grep -q 'gDMDispConnected' \$W/sl"
check "a crash in the Dock part's layer sets Display Settings off, not the Dock (its functions by name, its two headers)" \
  "grep -q '^sym DockMagnification \^_\*DMDisp\[A-Z\] displaySettings\$' crashmap-rules.txt && grep -q '^file DockMagnification \^(DisplayPrefs|DisplayIdentity)\\\\.h\$ displaySettings\$' crashmap-rules.txt"
# (commit 6, found on the A12Z with d04: a change of the iPad's own Dock read and placed the working stage, the TV's when the front window was there)
c_ipad_scope() {   # <StatusBar.x>: the iPad's Dock changes act on the iPad's own stage (gSMIPadDesktopScope), each display's on its own (DMDockAutoHideDisplaysFollow)
  fn 'static id DMSMWorkingStage(void) {' "$1" | grep -qF 'if (gSMIPadDesktopScope > 0) return DMSMFrontStageOnDisplay(DMSMIdentityOfScreen([UIScreen mainScreen]));' \
    && fn 'static void DMDockChangedRelayout(NSString *why) {' "$1" > "$W/dc" && [ "$(grep -c 'gSMIPadDesktopScope++;' "$W/dc")" = 2 ] && [ "$(grep -c 'gSMIPadDesktopScope--;' "$W/dc")" = 2 ] \
    && fn 'static void DMDockPositionMoved(NSDictionary<NSString *, NSString *> *layouts) {' "$1" | awk '/gSMIPadDesktopScope\+\+;/{a=NR} /DMSMOpenWindowFrames\(\);/{b=NR} /DMSMFitHiddenStages\(/{c=NR} /gSMIPadDesktopScope--;/{d=NR} END{exit !(a && b > a && c > b && d > c)}' \
    && fn 'static void DMDockSideThicknessChanged(double was, double now, int side) {' "$1" | grep -q 'gSMIPadDesktopScope--;' \
    && fn 'static void DMDockRoomAfterStartSMTry(int tries) {' "$1" | grep -q 'gSMIPadDesktopScope++;' \
    && fn 'static void DMDockAutoHideSMPass(void) {' "$1" | grep -qF 'NSString *front = gSMIPadDesktopScope > 0 ? DMSMNewestKeyIn(DMSMShownMainStage()) : DMSMFrontWindowKey();'
}
check "the iPad's own Dock changes (a setting, its apps, its side's thickness, the room at the start) read and place the iPad's own stage, never a TV's in front" "c_ipad_scope $S"
# ---- commit 7: window defaults on the TV (Stage Manager engine) ---------------------------------------------------------------------------------
c_win_rows() {   # <StatusBar.x>: Window Size and New Windows Open at Fill by the display a window opens on; the iPad's own (or none) the iPad's at once
  fn 'static int DMWindowSizeChoiceFor(id identity) {' "$1" > "$W/ws" && grep -qF 'if (DMSMIsMainIdentity(identity)) return gWindowSizeChoice;' "$W/ws" \
    && grep -qF 'id v = DMDispValueForIdentity(identity, "msb", kMSBDWindowSizeKey, nil);' "$W/ws" \
    && grep -qF 'return [v isKindOfClass:[NSString class]] ? MSBDWindowSizeFromStored((__bridge CFTypeRef)v) : gWindowSizeChoice;' "$W/ws" \
    && fn 'static BOOL DMNewWindowsFillFor(id identity) {' "$1" > "$W/nf" && grep -qF 'if (DMSMIsMainIdentity(identity)) return gNewWindowsFill;' "$W/nf" \
    && grep -qF 'return DMDispBoolForIdentity(identity, "msb", kMSBDNewWindowsFillKey, gNewWindowsFill);' "$W/nf"
}
c_win_join() {   # <StatusBar.x>: a window joining a stage with no size of its own opens by that stage's display's settings (SB:41293, 41310 of becbdeba)
  fn 'static id DMSMJoinAttributesOn(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage, id identity) {' "$1" > "$W/j" \
    && grep -qF 'id onDisplay = stage ? DMSMStageDisplayIdentity(stage) : identity;' "$W/j" && grep -qF 'BOOL atFill = MSBDNewWindowAtFill(DMNewWindowsFillFor(onDisplay), false, false);' "$W/j" \
    && grep -qF 'CGRect opening = atFill ? DMSMLayoutFrameIn(@"fill", u, scr) : DMSMNewWindowFrameIn(u, scr, onDisplay);' "$W/j" \
    && grep -qF 'MSBDWindowSizeName(DMWindowSizeChoiceFor(onDisplay))' "$W/j" && ! grep -qE '\b(gNewWindowsFill|gWindowSizeChoice)\b' "$W/j"
}
c_win_frame() {   # <StatusBar.x>: Window Size's window and No Fit's place by their display (SB:42265-42276 of becbdeba)
  fn 'static CGRect DMSMNewWindowFrameIn(CGRect u, CGSize scr, id identity) {' "$1" > "$W/nw" && grep -qF 'int choice = DMWindowSizeChoiceFor(identity);' "$W/nw" \
    && grep -qF 'return MSBDWindowSizeFrameIn(choice, u, scr, DMCenterTopFor(scr), least);' "$W/nw" && ! grep -qE '\bgWindowSizeChoice\b' "$W/nw" \
    && fn 'static id DMSMNoFitPlace(id stage) {' "$1" > "$W/nofit" && grep -qF 'id identity = DMSMStageDisplayIdentity(stage);' "$W/nofit" \
    && grep -qF 'CGRect f = DMWindowSizeChoiceFor(identity) != MSBDWindowSizeDefault ? DMSMNewWindowFrameIn(u, scr, identity) :' "$W/nofit"
}
c_win_ipad() {   # <StatusBar.x>: Aerial, Zetsu, MilkyWay4 and Fit's question before a launch stay the iPad's (their windows never reach the TV)
  fn 'static CGRect DMOpeningWindowFrame(void) {' "$1" | grep -qF 'if (!MSBDNewWindowAtFill(gNewWindowsFill, false, false)) return DMNewWindowFrame();' \
    && fn 'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {' "$1" | grep -qF 'MSBDNewWindowAtFill(gNewWindowsFill, DMSMOpensAtOwnSize(bundle), NO)'
}
c_follow() {   # <StatusBar.x>: a display's Dock answer and its windows' layouts applied later only to that display as it is then (review: unplug in between)
  fn 'static UIScreen *DMDockAutoHideScreenStill(NSArray *c) {' "$1" | grep -qF 'return now && now == c[1] ? now : nil;' \
    && fn 'static void DMDockAutoHideDisplaysFollow(int ipadWant, NSString *why) {' "$1" > "$W/fo" \
    && [ "$(grep -c 'UIScreen \*s = DMDockAutoHideScreenStill(c);' "$W/fo")" = 2 ] && grep -qF 'BOOL loaded = NO, v = DMDockAutoHideLiveOn(s, &loaded);' "$W/fo" \
    && awk '/UIScreen \*s = DMDockAutoHideScreenStill\(c\);/{n++} n==1 && /if \(!s\) \{/{a=NR} /gDMDockAutoHideTakenOn\[c\[0\]\] = @\(v\);/{b=NR} END{exit !(a && b > a)}' "$W/fo" \
    && grep -qF 'id stage = keys.count ? DMSMStageOf(keys.firstObject) : nil;' "$W/fo" && grep -qF 'NSArray<NSString *> *keys = s ? DMSMWindowKeysOn(s) : nil;' "$W/fo" \
    && awk '/if \(!stage \|\| !identity \|\| !\[DMSMStageDisplayIdentity\(stage\) isEqual:identity\]\) \{/{a=NR} /if \(layouts.count\) DMSMApplyLayoutsIn\(layouts, stage\);/{b=NR} END{exit !(a && b > a)}' "$W/fo" \
    && ! grep -qF 'id stage = c[2]' "$W/fo" && ! grep -qF 'DMDockAutoHideLiveOn(c[1]' "$W/fo"
}
check "a display's Dock that changes: its answer taken and its windows laid out later only on that display as it is then (gone or a new screen: skipped; its stage read again, on its own display)" "c_follow $S"
check "Window Size and New Windows Open at Fill by the display a window opens on (Stage Manager): the iPad's own at once, a TV's own from the iPad's, Window Size's type as stored" "c_win_rows $S"
check "  ... a window joining a stage with no size of its own: Fill or Window Size's window by that stage's display" "c_win_join $S"
check "  ... Window Size's window and No Fit's place by their display" "c_win_frame $S"
check "  ... Aerial's, Zetsu's, MilkyWay4's sites and Fit's question before a launch stay the iPad's" "c_win_ipad $S"
# ---- the master switch gates what the crash guard's Display Settings target names (review of 1.8.7) ----------------------------------------------
c_gate_getters() {   # <a DisplayPrefs.h>: switched off, every by-screen getter answers by the rule before a display key is derived (MSBDDispResolve with layerOn 0)
  fn 'static BOOL DMDispOffAnswer(const char *part, const char *key, int *from, int *def) {' "$1" > "$W/oa" && grep -qF 'if (gDMDispLayerOn) return NO;' "$W/oa" \
    && grep -qF '*from = MSBDDispResolve(0, 0, 0, 0, MSBDDispDisplayDefault(part, key, def));' "$W/oa" || return 1
  for g in 'static BOOL DMDispBool(UIScreen *s,' 'static double DMDispNum(UIScreen *s,' 'static id DMDispValue(UIScreen *s,'; do
    grep -qF "__attribute__((unused, noinline)) $g" "$1" || { [ "$g" = 'static id DMDispValue(UIScreen *s,' ] && continue; return 1; }
    fn "__attribute__((unused, noinline)) $g" "$1" | awk '/if \(DMDispOffAnswer\(part, key, &from, &def\)\) return from == kMSBDDispFromDefault \?/{a=NR} /DMDispKeyOfScreen\(s\)/{b=NR} END{exit !(a && b > a)}' || return 1
  done
  grep -qF '__attribute__((noinline)) static NSString *DMDispKeyOfScreen(UIScreen *s) {' "$1"
}
c_gate_identity() {   # <statusbar/DisplayPrefs.h>: by identity, switched off, a row with no display default answers the iPad's value with no lookup
  for g in DMDispBoolForIdentity DMDispNumForIdentity DMDispValueForIdentity; do
    grep -A1 -F "static" "$1" | grep -A1 -F " $g(" | tail -1 | grep -qF 'if (!identity || (!gDMDispLayerOn && !MSBDDispDisplayDefault(part, key, NULL))) return ipad;' || return 1
  done
}
c_gate_registry() {   # <statusbar/DisplayPrefs.h>: switched off, the registry (its screens, names, writes) does not run; switched on again it starts
  fn '__attribute__((noinline)) static void DMDispRegistryUpdate(NSString *why) {' "$1" > "$W/ru" \
    && awk '/if \(!gDMDispLayerOn\) \{   \/\/ \(the master switch gates it/{a=NR} /^        return;$/{if (a && !r) r=NR} /NSArray<UIScreen \*> \*screens = DMDispScreens\(\);/{b=NR} END{exit !(a && r > a && b > r)}' "$W/ru" \
    && ! sed -n '/if (!gDMDispLayerOn) {   \/\/ (the master switch gates it/,/^        return;$/p' "$W/ru" | grep -q 'DMDispScreens\|DMDispKeyOf\|DMDispAskNames\|CFPreferencesSet' \
    && fn 'static void DMDispInit(void) {' "$1" > "$W/di" && awk '/^    DMDispReload\(\);$/{a=NR} /addObserverForName:UIScreenDidConnectNotification/{b=NR} END{exit !(a && b > a)}' "$W/di" \
    && [ "$(grep -c 'usingBlock:^(NSNotification \*n) { if (gDMDispLayerOn) DMDispScheduleUpdate(' "$W/di")" = 2 ] \
    && grep -qF 'if (!was && gDMDispLayerOn) DMDispScheduleUpdate(@"Display Settings switched on");' "$W/di" \
    && grep -qF 'if (gDMDispLayerOn) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gDMDispLayerOn) DMDispRegistryUpdate(@"SpringBoard started"); });' "$W/di" \
    && [ "$(grep -c 'DMDispAskNames()' "$1")" = 1 ] && fn '__attribute__((noinline)) static void DMDispRegistryUpdate(NSString *why) {' "$1" | grep -qF 'if (changed && now.count) DMDispAskNames();'
}
check "Display Settings off: the status bar part's getters answer by the rule before any display key is derived (the key's derivation out of line, its own frame)" "c_gate_getters $L"
check "  ... the Dock part's the same" "c_gate_getters $DP"
check "  ... by a stage's display: a row with no display default takes the iPad's value with no lookup" "c_gate_identity $L"
check "  ... the registry, its names and its screen reads do not run; read first at the start, started when switched on again" "c_gate_registry $L"
# ---- commit 8: Menu Bar Size per display ---------------------------------------------------------------------------------------------------------
c_bar_provider() {   # <StatusBar.x>: a TV's provider and a TV's bar copy by the TV's own size, the iPad's by the iPad's; the TV's bar height by its size
  fn 'static int DMBarSizeOfClass(Class c) {' "$1" | grep -qF 'return MSBDMenuBarSizeOfProvider(1, ext, gDMBarSize, ext ? DMTVBarSizeNow() : gDMBarSize);' \
    && fn 'static int DMBarCopySize(UIView *fg) {' "$1" | grep -qF 'return DMExternalScreenOf(fg) ? DMTVBarSizeNow() : gDMBarSize;' \
    && grep -qF 'static CGFloat DMTVBarHeight(void) { return MSBDMenuBarSizeHeight(DMTVBarSizeNow(), 24.0); }' "$1"
}
c_bar_tvsize() {   # <StatusBar.x>: the TV's size taken at its connect from its own override (else the iPad's in force) and held until it goes
  fn 'static int DMTVBarSizeNow(void) {' "$1" > "$W/tv" && grep -qF 'if (gDMTVBarSize >= 0) return gDMTVBarSize;' "$W/tv" \
    && grep -qF 'double n = DMDispNumForKey(key, "msb", kMSBDMenuBarSizeKey, -1.0, 0.0, 2.0);' "$W/tv" && grep -qF 'BOOL hasOwn = n >= 0.0;' "$W/tv" \
    && grep -qF 'int own = MSBDMenuBarSizeFrom(hasOwn, n);' "$W/tv" && grep -qF 'gDMTVBarSize = MSBDMenuBarTVSizeAtConnect(1, hasOwn, own, gDMBarSize);' "$W/tv" && ! grep -q 'DMDispValueForKey' "$W/tv"
}
c_menu_size() {   # <StatusBar.x>: a menu at the size of the bar it hangs from: taken at the title's tap and from the host; rows and text by it
  fn 'static BOOL DMTitleTapWithMenuOpen(UIButton *btn) {' "$1" | grep -qF '    DMMenuSizeTake(btn);' \
    && fn 'static UIControl *DMMakeOverlayFor(UIView *host, CGFloat dimAlpha, BOOL menu) {' "$1" | grep -qF '    DMMenuSizeTakeHost(host);' \
    && grep -qF 'static CGFloat DMMenuRowH(void) { return MSBDMenuRowHeight(DMMenuSize()); }' "$1" && grep -qF 'static CGFloat DMMenuTextPt(void) { return MSBDMenuTextSize(DMMenuSize()); }' "$1"
}
c_wifi_room() {   # <WiFiMenu.h>: the Wi-Fi menu's room under the bar on the screen the menu is on, at its bar's size
  grep -qF 'CGFloat room = DMMenuScreenHeight() - (MSBDMenuBarFixedSite(DMMenuSize(), DMMenuBarHeightHere()) + 16.0)' "$1" && ! grep -q 'gDMBarSize' "$1"
}
c_stage_top() {   # <StatusBar.x>: Stage Manager's stage area of a TV's pass starts under the TV's own bar (R6)
  fn 'static CGRect DMSMOurStageArea(CGRect r, CGRect b, double dock, BOOL strip, BOOL dh) {' "$1" | grep -qF 'r = DMSMStageTopByDisplay(r, b);' \
    && fn 'static CGRect DMSMStageTopByDisplay(CGRect r, CGRect b) {' "$1" > "$W/st" && grep -qF 'MAX(gSMStatusBarOrigH, DMTVBarHeight())' "$W/st" \
    && awk '/if \(DMTVBarSizeNow\(\) == gDMBarSize\) return r;/{a=NR} /CGFloat top = /{b=NR} END{exit !(a && b > a)}' "$W/st"
}
check "Menu Bar Size: a TV's provider and a TV's bar copy by the TV's own size, the iPad's by the iPad's; the TV's bar height by its size" "c_bar_provider $S"
check "  ... the TV's size taken at its connect from its own override (msb menuBarSize; the iPad's in force until changed) and held until it goes" "c_bar_tvsize $S"
check "  ... our menus at the size of the bar they hang from (taken at the title's tap, before the rows; and from the host)" "c_menu_size $S"
c_tv_window() {   # <StatusBar.x>: a TV's bar at the TV's own height (R6): the height its scene's status bar manager answers (UIKit asks the iPad's provider, with no screen), asked as the TV's for a manager on another display
  fn 'static BOOL DMBarSizeManagerOnOtherDisplay(id mgr) {' "$1" > "$W/tw" && grep -qF 'id ws = DMBarSizeObjectOf(mgr, "windowScene");' "$W/tw" && grep -qF 'return s && main && s != main;' "$W/tw" \
    && fn 'static int DMBarSizeOfClass(Class c) {' "$1" | grep -qF ', gDMBarAskExternal > 0);' \
    && awk '/^- \(double\)defaultStatusBarHeight(InOrientation:\(long long\)o)? \{$/{f=1; a=b=c=d=0} f&&/if \(!DMBarSizeManagerOnOtherDisplay\(self\)\) return %orig;/{a=NR} f&&/    gDMBarAskExternal\+\+;/{b=NR} f&&/        h = %orig;/{c=NR} f&&/        gDMBarAskExternal--;/{d=NR} f&&/^}/{f=0; if (a&&b&&c&&d&&a<b&&b<c&&c<d) n++} END{exit !(n == 2)}' "$1" \
    && grep -qF '%init(MenuBarSizeManager, UIStatusBarManager = sbmc);' "$1" && ! grep -q 'MenuBarSizeTVWindow' "$1" \
    && fn '- (void)_layoutStatusBar {' "$1" | grep -qF 'BOOL tv = gDMBarHooksIn && DMExternalScreenOf(v) != nil;' && grep -qF '%init(MenuBarSizeSceneBar, SBDeviceApplicationSceneViewController = svc);' "$1"
}
check "  ... the Wi-Fi menu's room on the screen the menu is on, at its bar's size" "c_wifi_room $WF"
check "  ... a TV's bar at the TV's own height: the height its scene's status bar manager answers, asked as the TV's (R6, read on d14)" "c_tv_window $S"
check "  ... Stage Manager's stage top of a TV's pass under the TV's own bar (R6)" "c_stage_top $S"
# ---- commit 9: the per-scene layer helper ---------------------------------------------------------------------------------------------------------
c_layer() {   # <SceneLayer.h>: one window per scene and role, in SpringBoard's window scene on another display (looked up by its screen, never the iPad's), let go when its display or scene goes
  [ "$(grep -c 'initWithWindowScene:' "$1")" = 1 ] && fn 'static UIWindow *DMSceneLayerInScene(' "$1" > "$W/sl" \
    && grep -qF 'if (!scr || scr == [UIScreen mainScreen]) return nil;' "$W/sl" && grep -qF 'for (UIWindow *w in list) if (w.windowScene == scene) return w;' "$W/sl" \
    && grep -qF 'for (NSString *n in @[UIScreenDidDisconnectNotification, UISceneDidDisconnectNotification])' "$W/sl" \
    && awk '/^    static BOOL observing = NO;$/{a=NR} /^    if \(!observing\) \{$/{b=NR} /^        observing = YES;$/{c=NR} /for \(NSString \*n in @\[UIScreenDidDisconnectNotification, UISceneDidDisconnectNotification\]\)/{d=NR} END{exit !(a && b == a + 1 && c > b && d > c)}' "$W/sl" \
    && ! grep -q 'gDMSceneLayers' "$W/sl" \
    && grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{ DMSceneLayersRelease(nil, why); });' "$W/sl" \
    && fn 'static UIWindowScene *DMSceneLayerSceneOf(UIScreen *screen) {' "$1" | grep -qF "if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen == screen) return (UIWindowScene *)sc;" \
    && fn 'static void DMSceneLayersRelease(id what, NSString *why) {' "$1" | grep -qF 'if (before) before(gone);'
}
c_one_maker() {   # <StatusBar.x>: the external display's menu window is the helper's menu role (its class, level, hit test kept); no other maker of windows in a scene but the iPad's own shield
  [ "$(grep -c 'initWithWindowScene:' "$1")" = 1 ] && grep 'initWithWindowScene:' "$1" | grep -q 'shield = scene ? \[\[UIWindow alloc\] initWithWindowScene:scene\]' \
    && grep -qF 'UIWindowScene *scene = MSBDMainWindowScene();   // (on the iPad' "$1" && ! grep -q 'objc_allocateClassPair(\[UIWindow class\], "MSBExtMenuWindow"' "$1" \
    && fn 'static UIWindow *DMExtMenuWindowFor(UIView *fg) {' "$1" | grep -qF 'return DMSceneLayerInScene(scene, @"menu", kMenuWindowLevel, (DMSceneLayerKind){ "MSBExtMenuWindow", (IMP)DMMenuWindowHitTest, (IMP)DMMenuWindowAXEscape, "extmenu" },' \
    && grep -qF '#include "SceneLayer.h"' "$1"
}
check "the per-scene layer helper: one window per scene and role in another display's scene (by its scene's screen, S1), let go when the display or scene goes (its disconnect observers registered once by their own flag, whoever made the role's list)" "c_layer $SL"
check "  ... the external display's menu window is its menu role (class, level, hit test, escape kept); the only other window in a scene is the iPad's own shield" "c_one_maker $S"
check "  ... no other part of the status bar makes a window in a scene" "[ -z \"\$(grep -l 'initWithWindowScene:' ../statusbar/*.h | grep -v '/SceneLayer.h\$')\" ]"
# The getters' callers: only the reader sites listed here (each converted reader asks with its screen or its stage's display).
check "no other code calls the getters: the layers, the Dock's readers (Dock.x), Finder's bin (DockTrash.h), the Dock's auto-hide on a display (StatusBar.x DMDockAutoHideWantOn, commit 6), the TV's window defaults (commit 7), the TV's Menu Bar Size (commit 8), the TV's menu bar auto-hide (commit 10)" \
  "grep -rnE --include='*.x' --include='*.h' --include='*.m' --include='*.xm' '\bDMDisp(Bool|Num|Value)(ForIdentity|ForKey)?\(' .. | cut -d: -f1 | sort -u > \$W/callers \
   && printf '%s\n' ../dock/Dock.x ../dock/DisplayPrefs.h ../statusbar/DisplayPrefs.h ../statusbar/DockTrash.h ../statusbar/StatusBar.x | sort > \$W/allowed && diff \$W/allowed \$W/callers \
   && grep -nE '\bDMDisp(Bool|Num|Value)(ForIdentity|ForKey)?\(' $S | grep -v '^[0-9]*:static BOOL DMDispBool(UIScreen \*s, const char \*part, const char \*key, BOOL ipad);' > \$W/sb; [ \$(wc -l < \$W/sb) = 5 ] \
   && grep -q 'DMDispBool(s, \"dock\", kMSBDAutoHideKey, ipadWant != 0)' \$W/sb && grep -q 'DMDispValueForIdentity(identity, \"msb\", kMSBDWindowSizeKey, nil)' \$W/sb && grep -q 'DMDispBoolForIdentity(identity, \"msb\", kMSBDNewWindowsFillKey, gNewWindowsFill)' \$W/sb && grep -q 'DMDispNumForKey(key, \"msb\", kMSBDMenuBarSizeKey, -1.0, 0.0, 2.0)' \$W/sb && grep -q 'DMDispBool(tv, \"msb\", \"autoHideStatusBar\", DMAutoHidePref())' \$W/sb"

# ---- made to fail: one reader broken in a copy, its check must fail ------------------------------------------------------------------------------
mutant() {   # <name> <file> <old> <new> <check function>
  local M="$W/m-$1"; mkdir -p "$M"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' "$2" "$M/f" "$3" "$4" || return 1
  ! $5 "$M/f" 2>/dev/null
}
check "made to fail: the Dock's answer taken for a display that went in between" "mutant followgone $S '            UIScreen *s = DMDockAutoHideScreenStill(c);
            if (!s) {' '            UIScreen *s = c[1];
            if (!s) {' c_follow"
check "made to fail: the windows placed in the stage read 1.2 s before" "mutant followstage $S '                id stage = keys.count ? DMSMStageOf(keys.firstObject) : nil;   // (the stage it shows now, read as at the start)' '                id stage = c[2];' c_follow"
check "made to fail: a stage of another display taken" "mutant followident $S '                if (!stage || !identity || ![DMSMStageDisplayIdentity(stage) isEqual:identity]) {' '                if (!stage) {' c_follow"
check "made to fail: the Dock laid out again at every note of the displays domain (the registry's at each connect / disconnect)" "mutant docknote $D '    if (!DMDispReloadChanged()) return;
' '' c_dock_note_one"
check "made to fail: the Dock's comparison ignoring the master switch" "mutant docknoteon $DP 'return wasOn != gDMDispLayerOn || !(was' 'return !(was' c_dock_note_dp"
check "made to fail: the status bar part's getter deriving a key with Display Settings off" "mutant gatebool $L '    int from, def; if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (def != 0) : ipad;
    return DMDispBoolForKey(' '    return DMDispBoolForKey(' c_gate_getters"
check "made to fail: the Dock part's size getter deriving a key with Display Settings off" "mutant gatenum $DP '    if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (double)def : ipad;
' '' c_gate_getters"
check "made to fail: the off answer ignoring the display default (the TV's Trash would follow the iPad's off)" "mutant gatedef $L '*from = MSBDDispResolve(0, 0, 0, 0, MSBDDispDisplayDefault(part, key, def));' '*from = kMSBDDispFromIPad;' c_gate_getters"
check "made to fail: a stage's display looked up with Display Settings off" "mutant gateident $L '    if (!identity || (!gDMDispLayerOn && !MSBDDispDisplayDefault(part, key, NULL))) return ipad;
    return DMDispNumForKey(' '    if (!identity) return ipad;
    return DMDispNumForKey(' c_gate_identity"
check "made to fail: the registry written with Display Settings off" "mutant gatereg $L '    if (!gDMDispLayerOn) {   // (the master switch gates it' '    if (0) {   // (the master switch gates it' c_gate_registry"
check "made to fail: a connect updating the registry with Display Settings off" "mutant gateconn $L 'usingBlock:^(NSNotification *n) { if (gDMDispLayerOn) DMDispScheduleUpdate(@\"a display connected\"); }' 'usingBlock:^(NSNotification *n) { DMDispScheduleUpdate(@\"a display connected\"); }' c_gate_registry"
check "made to fail: the switch turned on again not starting the registry" "mutant gateon $L '        if (!was && gDMDispLayerOn) DMDispScheduleUpdate(@\"Display Settings switched on\");
' '' c_gate_registry"
check "made to fail: the Dock's size read from the iPad's setting (a TV's Size ignored)" "mutant size $D 'CGFloat f = iconSize;' 'CGFloat f = gIconSize;' c_dock_size"
check "made to fail: the Dock's size asked for no screen (every Dock the iPad's)" "mutant sizescreen $D 'CGFloat iconSize = DMDockIconSizeOn(dockScreen);' 'CGFloat iconSize = DMDockIconSizeOn(nil);' c_dock_size"
check "made to fail: the magnification's room by the iPad's amount" "mutant headroom $D 'MAX(0.0, DMDockMagOf(dockScreen) - 1.0)' 'MAX(0.0, gMagnification - 1.0)' c_dock_size"
check "made to fail: the lift by the iPad's magnification" "mutant lift $D '(MAX(DMDockMagOf(dockScreen), 1.0) - 1.0)' '(MAX(gMagnification, 1.0) - 1.0)' c_dock_lift"
check "made to fail: the hover's scale by the iPad's amount" "mutant hover $D 'return 1.0 + (gHoverMag - 1.0) * DMBell(offset) * gInfluence;' 'return 1.0 + (gMagnification - 1.0) * DMBell(offset) * gInfluence;' c_dock_hover"
check "made to fail: the hover's switch by the iPad's" "mutant hoveron $D 'BOOL want = gHoverMagOn && gHovering;' 'BOOL want = gEnabled && gHovering;' c_dock_hover"
check "made to fail: the Trash by the iPad's switch on every Dock" "mutant trash $D 'return DMDispBool(w ? DMDockScreenOf(w) : nil, \"dock\", \"showTrash\", gShowTrash);' 'return gShowTrash;' c_dock_trash"
check "made to fail: a Dock row read from another part" "mutant part $D 'DMDispNum(s, \"dock\", \"dockIconSize\"' 'DMDispNum(s, \"msb\", \"dockIconSize\"' c_dock_rows"
check "made to fail: the Dock's getter looking the iPad's screen up" "mutant main $DP '    if (!s || s == [UIScreen mainScreen]) return ipad;
    int from, def;
    if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (def != 0) : ipad;' '    int from, def;
    if (DMDispOffAnswer(part, key, &from, &def)) return from == kMSBDDispFromDefault ? (def != 0) : ipad;' c_dock_getters"
c_dock_cache_one() { c_dock_cache "$1" $D; }
check "made to fail: the Dock's cache taking another part's keys" "mutant cachepart $DP ' || strcmp(part, \"dock\") != 0) continue;' ') continue;' c_dock_cache_one"
check "made to fail: Finder's bin only for the iPad's switch" "mutant finder $T '    for (UIScreen *s in DMDispScreens()) if (s != [UIScreen mainScreen] && DMDispBool(s, \"dock\", \"showTrash\", ipad)) return YES;' '    (void)ipad;' c_finder_trash"
check "made to fail: a window joining a TV stage at Fill by the iPad's setting" "mutant joinfill $S 'BOOL atFill = MSBDNewWindowAtFill(DMNewWindowsFillFor(onDisplay), false, false);' 'BOOL atFill = MSBDNewWindowAtFill(gNewWindowsFill, false, false);' c_win_join"
check "made to fail: the joining window's size asked for no display (the iPad's)" "mutant joinsize $S 'DMSMNewWindowFrameIn(u, scr, onDisplay);' 'DMSMNewWindowFrameIn(u, scr, nil);' c_win_join"
check "made to fail: Window Size's window by the iPad's choice" "mutant frame $S 'int choice = DMWindowSizeChoiceFor(identity);' 'int choice = gWindowSizeChoice;' c_win_frame"
check "made to fail: the iPad's own display looked up (no pass-through)" "mutant winmain $S '    if (DMSMIsMainIdentity(identity)) return gWindowSizeChoice;
' '' c_win_rows"
check "made to fail: a Window Size of the wrong type taken as Default (it reads as not set: the iPad's)" "mutant wintype $S ' : gWindowSizeChoice;
}
static BOOL DMNewWindowsFillFor' ' : MSBDWindowSizeDefault;
}
static BOOL DMNewWindowsFillFor' c_win_rows"
check "made to fail: the iPad's pass asking a stage the iPad does not show" "mutant hiddenpass $S 'DMSMNewestKeyIn(DMSMShownMainStage())' 'DMSMNewestKeyIn(DMSMWorkingStage())' c_ipad_scope"
check "made to fail: the working stage ignoring the iPad's scope (a TV window put into the iPad's desktop)" "mutant scope $S '    if (gSMIPadDesktopScope > 0) return DMSMFrontStageOnDisplay(DMSMIdentityOfScreen([UIScreen mainScreen]));   // (the iPad'\''s desktop changed: its own stage, or none)
' '' c_ipad_scope"
check "made to fail: a TV's provider by the iPad's size" "mutant tvprov $S 'ext ? DMTVBarSizeNow() : gDMBarSize);' 'ext ? gDMBarSize : gDMBarSize);' c_bar_provider"
check "made to fail: our items on a TV's bar copy by the iPad's size" "mutant copysize $S '    return DMExternalScreenOf(fg) ? DMTVBarSizeNow() : gDMBarSize;' '    return gDMBarSize;' c_bar_provider"
check "made to fail: the TV's size not held until it goes (read anew at every ask)" "mutant tvheld $S '    if (gDMTVBarSize >= 0) return gDMTVBarSize;
' '' c_bar_tvsize"
check "made to fail: the TV's size from no display (the iPad's)" "mutant tvkey $S 'double n = DMDispNumForKey(key, \"msb\", kMSBDMenuBarSizeKey, -1.0, 0.0, 2.0);' 'double n = DMDispNumForKey(nil, \"msb\", kMSBDMenuBarSizeKey, -1.0, 0.0, 2.0);' c_bar_tvsize"
check "made to fail: a TV's size of any type taken (a text or a switch read as Small, not the iPad's)" "mutant tvtype $S 'double n = DMDispNumForKey(key, \"msb\", kMSBDMenuBarSizeKey, -1.0, 0.0, 2.0);
    BOOL hasOwn = n >= 0.0;' 'id v = DMDispValueForKey(key, \"msb\", kMSBDMenuBarSizeKey, nil); double n = [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0.0;
    BOOL hasOwn = v != nil;' c_bar_tvsize"
check "made to fail: a menu's size not taken at its title's tap (its rows made at the last menu's size)" "mutant menutake $S '    DMMenuSizeTake(btn);
' '' c_menu_size"
check "made to fail: the menu rows by the iPad's size" "mutant menurow $S 'static CGFloat DMMenuRowH(void) { return MSBDMenuRowHeight(DMMenuSize()); }' 'static CGFloat DMMenuRowH(void) { return MSBDMenuRowHeight(gDMBarSize); }' c_menu_size"
check "made to fail: the Wi-Fi menu's room by the iPad's screen" "mutant wifiroom $WF 'CGFloat room = DMMenuScreenHeight() - ' 'CGFloat room = [UIScreen mainScreen].bounds.size.height - ' c_wifi_room"
check "made to fail: the TV's manager's question answered at the iPad's size (the provider's class alone)" "mutant tvask $S ', gDMBarAskExternal > 0);' ', 0);' c_tv_window"
check "made to fail: the bar over a full-screen app on a TV laid out at the iPad's size" "mutant tvfsbar $S '    BOOL tv = gDMBarHooksIn && DMExternalScreenOf(v) != nil;' '    BOOL tv = NO;' c_tv_window"
check "made to fail: every manager's question taken as the TV's (the iPad's own included)" "mutant tvaskall $S '    return s && main && s != main;' '    return s && main;' c_tv_window"
check "made to fail: a TV's stage top left at the iPad's bar" "mutant stagetop $S 'r = DMSMStageTopByDisplay(r, b);' 'r = r;' c_stage_top"
check "made to fail: a TV's stage top moved with the TV at the iPad's own size (the Home-button iPads' 4 pt)" "mutant stagetopsame $S '    if (DMTVBarSizeNow() == gDMBarSize) return r;' '    if (0) return r;' c_stage_top"
check "made to fail: the ask not counted around iOS's answer in one of the two (left as the iPad's)" "mutant tvaskone $S '- (double)defaultStatusBarHeightInOrientation:(long long)o {
    if (!DMBarSizeManagerOnOtherDisplay(self)) return %orig;
    double h = 0;
    gDMBarAskExternal++;' '- (double)defaultStatusBarHeightInOrientation:(long long)o {
    if (!DMBarSizeManagerOnOtherDisplay(self)) return %orig;
    double h = 0;' c_tv_window"
check "made to fail: the menu window made by its own code, not the helper" "mutant ownmaker $S '    return DMSceneLayerInScene(scene, @\"menu\"' '    (void)[[UIWindow alloc] initWithWindowScene:scene];
    return DMSceneLayerInScene(scene, @\"menu\"' c_one_maker"
check "made to fail: a layer made on the iPad's own screen" "mutant layermain $SL '    if (!scr || scr == [UIScreen mainScreen]) return nil;
' '' c_layer"
check "made to fail: a layer's scene taken as any connected scene (the first non-main screen has none: S1)" "mutant layerscene $SL '((UIWindowScene *)sc).screen == screen) return' '((UIWindowScene *)sc).screen != nil) return' c_layer"
check "made to fail: the disconnect observers registered only while no role's list exists (every owner makes its list first: never registered)" "mutant layerobs $SL '    if (!observing) {' '    if (!gDMSceneLayers) {' c_layer"
check "made to fail: the disconnect observers' flag never set (registered again at every ask)" "mutant layerobsset $SL '        observing = YES;
' '' c_layer"
check "made to fail: a gone scene's layer kept after UIKit lets it go (no second release)" "mutant layerlater $SL '                dispatch_async(dispatch_get_main_queue(), ^{ DMSceneLayersRelease(nil, why); });   // (again once UIKit has let the scene go)
' '' c_layer"
c_barhtrace() {   # <DisplaySpike.h>: the debug +height trace touches its set of callers on the main queue only, and reads its flag file once (review)
  fn 'static void DMDSBarHTrace(Class c, double stock, double answer) {' "$1" > "$W/bt" \
    && awk '/dispatch_async\(dispatch_get_main_queue\(\), \^\{   \/\/ \(the set is touched here only\)/{a=NR} /gDMDSBarHSeen/{n++; if (!f) f=NR} END{exit !(a && n == 3 && f > a)}' "$W/bt" \
    && grep -qF 'dispatch_once(&once, ^{ gDMDSBarHFlag = DMTestFlagNow("/tmp/msb-barhtrace") ? 1 : 0; });' "$W/bt" && [ "$(grep -c 'DMTestFlagNow' "$W/bt")" = 1 ]
}
check "debug only: the +height trace changes its set of callers on the main queue only (a +height asked on another thread hands them over), its flag file read once" "c_barhtrace ../statusbar/DisplaySpike.h"
check "made to fail: the trace's set changed on the asking thread" "mutant barhset ../statusbar/DisplaySpike.h '    NSString *key = [sig copy];
    dispatch_async(dispatch_get_main_queue(), ^{   // (the set is touched here only)
        if (!gDMDSBarHSeen) gDMDSBarHSeen = [NSMutableSet set];
        if ([gDMDSBarHSeen containsObject:key] || gDMDSBarHSeen.count >= 80) return;
        [gDMDSBarHSeen addObject:key];' '    NSString *key = [sig copy];
    if (!gDMDSBarHSeen) gDMDSBarHSeen = [NSMutableSet set];
    if ([gDMDSBarHSeen containsObject:key] || gDMDSBarHSeen.count >= 80) return;
    [gDMDSBarHSeen addObject:key];
    dispatch_async(dispatch_get_main_queue(), ^{   // (the set is touched here only)' c_barhtrace"
[ $fails = 0 ] && echo "test-displayreaders: all checks pass" || { echo "test-displayreaders: checks FAILED"; exit 1; }
