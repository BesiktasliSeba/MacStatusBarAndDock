#!/bin/bash
# Mac test of the desktop's keys and menus (statusbar/Desktop.h, 1.7.2 items 14 and 15), as built. 14: while the desktop has the keys (an icon
# clicked or selected, a selection drawn, an icon's menu) and an app is in front, SpringBoard holds the keyboard focus -- Space on a selected icon
# reached the app behind (KT: it paused the music); the focus goes back on a touch elsewhere, another app in front, a cleared selection, the
# desktop going away. 15: a pointer's secondary click opens our own menu in the menu window over the windows (UIKit's lived in the Home Screen's
# window under them, so every window faded while it was up); a finger's hold: ours too (KT's choice), with Edit Home Screen on the empty desktop
# (the Home Screen's own hold there started jiggle mode). 1.7.7 item 6b: a click held still opens it from our own hold check, as a finger's hold
# does -- never at UIKit's first ask, 0.16 s into a click, which opened it under a click that went on into a selection rectangle. 1.7.7 fix round:
# a finger held on the desktop long enough to be its own is never also the Dock's swipe down (the App Library opened under the rectangle), and the
# hold's menu never opens under a finger already on its way.
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
check "the pointer's secondary click: our menu in the menu window (DMMenuHost), never UIKit's for that press" \
  "fn '- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)i configurationForMenuAtLocation:(CGPoint)loc {' | awk '/if \\(_trackSecondary && _trackPointer && _track && CACurrentMediaTime\\(\\) - _trackAt < 1.0\\)/{a=1} a&&/DMFinderShowMenuIn\\(host, menu, sp\\)/{b=1} a&&b&&/return nil;/{print \"ok\"; exit}' | grep -q ok"
check "  ... once per press, and only while the press is still one: a press gone on into a drag meanwhile gets no menu (1.7.7 item 6b)" \
  "grep -q 'if (_ownMenuAt == _trackAt) return nil;' $D && grep -q 'if (!s || s->_trackAt != press || s->_trackMode || s->_lifted || s->_band) {' $D"
check "a click held still: our menu from our own hold check, as a finger's, never at UIKit's first ask for the press (1.7.7 item 6b)" \
  "fn '- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)i configurationForMenuAtLocation:(CGPoint)loc {' | grep -q 'if (_track && !_trackSecondary && DMDesktopFingerOwnMenu()) return nil;' && grep -q 'if (DMDesktopFingerOwnMenu() && !_trackSecondary) {   // (a finger, or a click, held still' $D && ! grep -q 'pointerHold' $D"
check "  ... held still as a drag tells it: within 4 pt for a pointer, 10 pt for a finger" \
  "fn '- (void)dm_holdCheck:(UITouch *)t since:(CFTimeInterval)at {' | grep -q '> (_trackPointer ? 4.0 : 10.0)) return;'"
check "  ... the secondary button read where the press begins" \
  "grep -q '_trackSecondary = pointer && (DMDesktopButtons(e) & UIEventButtonMaskSecondary) != 0;' $D"
check "a finger's hold: our menu (KT's choice; one constant, the debug file only flips it in debug builds)" \
  "grep -q '^static const BOOL kDMDesktopFingerOwnMenu = YES;' $D && fn 'static BOOL DMDesktopFingerOwnMenu(void) {' | awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /access\\(\"\\/tmp\\/msb-desktop-fingermenu\"/{print d; exit}' | grep -qx 1"
check "  ... ours: the press's other gestures let go when it opens; a move after it closes the menu -- out of sight at once (1.7.7 fix round) -- and drags" \
  "fn '- (void)dm_holdCheck:(UITouch *)t since:(CFTimeInterval)at {' | grep -q 'o.enabled = NO; o.enabled = YES;' && grep -q 'if (_holdMenu) { _holdMenu = NO; gOverlay.alpha = 0.0; DMCloseOverlay(); }' $D"
check "the empty desktop's menu: Edit Home Screen, only where the icon manager's switch is there with the checked type (v20@0:8B16)" \
  "fn '- (UIMenu *)dm_menuFor:(DMDesktopItemView *)v at:(CGPoint)sp {' | grep -q 'if (DMDesktopHomeEditor()) \\[end addObject:A(@\"Edit Home Screen\"' && fn 'static id DMDesktopHomeEditor(void) {' | grep -q 'strcmp(method_getTypeEncoding(m) ?: \"\", \"v20@0:8B16\")'"
check "1.7.4 item 19: no keys for the desktop while a text field of SpringBoard's types (Cmd-A in the App Library's search selected every icon)" \
  "grep -q '&& !_editing && !DMSBTextFieldTyping(_renameField); }' $D"
check "  ... that is the key window's first responder, a text input, other than the desktop's own rename field" \
  "fn 'static BOOL DMSBTextFieldTyping(UIResponder *except) {' | grep -q 'w.isKeyWindow' && fn 'static BOOL DMSBTextFieldTyping(UIResponder *except) {' | grep -q 'fr != except && \\[fr isKindOfClass:\\[UIResponder class\\]\\] && \\[fr isFirstResponder\\] && \\[fr conformsToProtocol:@protocol(UITextInput)\\]'"
K=../dock/Dock.x
check "1.7.7 fix round: the search view's gestures (the Dock's swipe down, Spotlight's pull) never begin with a touch the desktop has taken" \
  "awk '/^- \\(BOOL\\)gestureRecognizerShouldBegin:/{g=NR} g&&!a&&/if \\(DMDesktopTakesTouch\\(gesture\\)\\) [{]/{a=NR} a&&!b&&NR>a&&/return NO;/{b=NR} b&&!c&&/DMSwipeIsDownward\\(\\(UIPanGestureRecognizer/{c=NR} a&&!c&&/^%end/{e=NR} END{exit !(a && b && c && !e)}' $K && grep -B3 'if (DMDesktopTakesTouch(gesture)) {' $K | grep -q '^%hook SBSearchScrollView' && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDesktopTouchIsOurs\")' $K"
check "  ... the desktop answers for the touch it follows (the gesture among its recognizers), by the very hold rule its own drag and rectangle use" \
  "grep -q '^__attribute__((visibility(\"default\"))) BOOL MSBDDesktopTouchIsOurs(UIGestureRecognizer \\*g) { return gDesktop && g && \\[gDesktop dm_touchIsOursFor:g\\]; }' $D && fn '- (BOOL)dm_touchIsOursFor:(UIGestureRecognizer *)g {' | grep -q 'if (!t || !\\[t.gestureRecognizers containsObject:g\\]) return NO;' && fn '- (BOOL)dm_touchIsOursFor:(UIGestureRecognizer *)g {' | grep -q 'return CACurrentMediaTime() - _trackAt >= DMDesktopHoldToTake(_trackView != nil);' && grep -q 'held < DMDesktopHoldToTake(_trackView != nil) && !_menuOpen' $D && ! grep -q '_trackView ? 0.3 : 0.35' $D"
check "  ... the hold's menu never under a finger on its way: at rest (4 pt, 0.1 s) before it opens, the press taken meanwhile (no jiggle mode), looked at again while it moves" \
  "fn '- (void)dm_holdCheck:(UITouch *)t since:(CFTimeInterval)at {' | awk '/if \\(CACurrentMediaTime\\(\\) - _trackRestAt < kDMDesktopRestTime\\)/{a=NR} a&&!g&&/o.enabled = NO; o.enabled = YES;/{g=NR} /\\[ws dm_holdCheck:wt since:at\\]/{b=NR} /DMFinderShowMenuIn\\(host, menu, _trackDown\\)/{c=NR} END{exit !(a && g > a && b > g && c > b)}' && grep -q '^static const double kDMDesktopRestRadius = 4.0, kDMDesktopRestTime = 0.1;' $D && grep -q 'if (hypot(sp.x - _trackRest.x, sp.y - _trackRest.y) > kDMDesktopRestRadius) { _trackRest = sp; _trackRestAt = CACurrentMediaTime(); }' $D && grep -q '_trackRest = sp; _trackRestAt = _trackAt;' $D"
[ $fails = 0 ] && echo "test-desktopkeys: all checks pass" || { echo "test-desktopkeys: checks FAILED"; exit 1; }
