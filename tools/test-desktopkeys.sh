#!/bin/bash
# Mac test of the desktop's keys and menus (statusbar/Desktop.h, 1.7.2 items 14 and 15), as built. 14: while the desktop has the keys (an icon
# clicked or selected, a selection drawn, an icon's menu) and an app is in front, SpringBoard holds the keyboard focus -- Space on a selected icon
# reached the app behind (KT: it paused the music); the focus goes back on a touch elsewhere, another app in front, a cleared selection, the
# desktop going away. 15: a pointer's secondary click opens our own menu in the menu window over the windows (UIKit's lived in the Home Screen's
# window under them, so every window faded while it was up); a finger's hold: ours too (KT's choice), with Edit Home Screen on the empty desktop
# (the Home Screen's own hold there started jiggle mode).
set -e
cd "$(dirname "$0")"
D=../statusbar/Desktop.h
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$D"; }
check "the keys flag is only ever set through -dm_setHasKeys: (which takes or gives the focus with it)" \
  "! grep -n '_hasKeys = YES\\|_hasKeys = NO' $D && grep -q '^- (void)dm_setHasKeys:(BOOL)has { _hasKeys = has; DMDesktopKeysFocus(has); }' $D"
check "  ... set where the desktop takes the keys: an icon's tap, the selection rectangle, an icon's menu, a drag" \
  "[ \$(grep -c '\\[self dm_setHasKeys:YES\\]' $D) -ge 5 ]"
check "the focus is taken only with an app in front and a hardware keyboard, once" \
  "fn 'static void DMDesktopKeysFocus(BOOL take) {' | grep -q 'if (gDesktopKeysLock || !front.length || !DMHardwareKeyboardAttached()) return;'"
check "  ... through the shared focus lock (common/FocusLock.h), not the one a rename takes (our on-screen keyboard goes with that one)" \
  "fn 'static void DMDesktopKeysFocus(BOOL take) {' | grep -q 'gDesktopKeysLock = MSBDFocusLock(' && fn 'static void DMDesktopKeysFocus(BOOL take) {' | grep -q 'MSBDFocusUnlock(l)'"
check "given back: a touch elsewhere" \
  "fn '- (void)dm_touchBegan:(UITouch *)t {' | grep -q '\\[self dm_setHasKeys:NO\\];'"
check "given back: another app in front (the tick compares with the app in front when it was taken)" \
  "fn '- (void)dm_tick {' | grep -q 'gDesktopKeysLock && !\\[\\[DMActiveApp() bundleIdentifier\\] ?: @\"\" isEqualToString:gDesktopKeysFront\\]'"
check "given back: nothing selected any more (Esc, a deselecting click, a rectangle over nothing)" \
  "fn '- (void)dm_showSelection {' | grep -q 'if (!_sel.count && gDesktopKeysLock && !_band && !_renameField) \\[self dm_setHasKeys:NO\\];' && fn '- (void)dm_bandEnd {' | grep -q 'dm_setHasKeys:NO'"
check "given back: the desktop taken off its page" \
  "fn '- (void)dm_detach {' | grep -q '\\[self dm_setHasKeys:NO\\];'"
check "the pointer's secondary click, or its click held still: our menu in the menu window (DMMenuHost), never UIKit's for that press" \
  "fn '- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)i configurationForMenuAtLocation:(CGPoint)loc {' | awk '/if \\(\\(_trackSecondary \\|\\| pointerHold\\) && _trackPointer && _track/{a=1} a&&/DMFinderShowMenuIn\\(host, menu, sp\\)/{b=1} a&&b&&/return nil;/{print \"ok\"; exit}' | grep -q ok"
check "  ... a click held still: only with our menu chosen, once per press, its other gestures let go while it is still held, a move closes it" \
  "grep -q 'BOOL pointerHold = _trackPointer && _track && !_trackSecondary && DMDesktopFingerOwnMenu();' $D && grep -q 'if (_ownMenuAt == _trackAt) return nil;' $D && grep -q 'if (pointerHold) _holdMenu = YES;' $D && grep -q 'if (pointerHold && tt && tt.phase != UITouchPhaseEnded && tt.phase != UITouchPhaseCancelled)' $D"
check "  ... the secondary button read where the press begins" \
  "grep -q '_trackSecondary = pointer && (DMDesktopButtons(e) & UIEventButtonMaskSecondary) != 0;' $D"
check "a finger's hold: our menu (KT's choice; one constant, the debug file only flips it in debug builds)" \
  "grep -q '^static const BOOL kDMDesktopFingerOwnMenu = YES;' $D && fn 'static BOOL DMDesktopFingerOwnMenu(void) {' | awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /access\\(\"\\/tmp\\/msb-desktop-fingermenu\"/{print d; exit}' | grep -qx 1"
check "  ... ours: the press's other gestures let go when it opens; a move after it closes the menu and drags" \
  "fn '- (void)dm_holdCheck:(UITouch *)t since:(CFTimeInterval)at {' | grep -q 'o.enabled = NO; o.enabled = YES;' && grep -q 'if (_holdMenu) { _holdMenu = NO; DMCloseOverlay(); }' $D"
check "the empty desktop's menu: Edit Home Screen, only where the icon manager's switch is there with the checked type (v20@0:8B16)" \
  "fn '- (UIMenu *)dm_menuFor:(DMDesktopItemView *)v at:(CGPoint)sp {' | grep -q 'if (DMDesktopHomeEditor()) \\[end addObject:A(@\"Edit Home Screen\"' && fn 'static id DMDesktopHomeEditor(void) {' | grep -q 'strcmp(method_getTypeEncoding(m) ?: \"\", \"v20@0:8B16\")'"
[ $fails = 0 ] && echo "test-desktopkeys: all checks pass" || { echo "test-desktopkeys: checks FAILED"; exit 1; }
