#!/bin/bash
# Mac test of the menu bar's menus and the hardware keyboard (1.7.9, common/MenuKeys.h, test-menukeys.c): the rules (the lease, the keys a menu
# takes) and the wiring -- a menu of the bar leaves the keyboard focus with an app whose MacAppBridge reads the keys (so the app stays active and its
# selected row keeps its look while menus open and switch), everything else keeps SpringBoard's focus lock as before, and the bridge gives the open
# menu the keys before the app's own Esc handling.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tmk" test-menukeys.c
"$W/tmk"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; B=../appbridge/AppBridge.x
check "both menu presenters (the Apple menu, DMPresentMenu) open their overlay as a menu" "[ \$(grep -c 'DMMakeOverlayFor(host, 0.0, YES)' $S) = 2 ]"
check "every other overlay (dialogs, panels) is not a menu: DMMakeOverlay passes NO" "grep -q 'static UIControl \*DMMakeOverlay(UIView \*host, CGFloat dimAlpha) { return DMMakeOverlayFor(host, dimAlpha, NO); }' $S"
check "an overlay takes the focus lock unless it is a menu whose keys stay with the app" "awk '/^static UIControl \*DMMakeOverlayFor/,/^}/' $S | grep -q '!(menu && DMMenuKeysBegin())) DMOverlayFocus(YES, gMenuWindow)'"
check "the keys stay with the app only with a hardware keyboard and a bridge that reads them" "awk '/^static BOOL DMMenuKeysBegin/,/^}/' $S | grep -q 'if (!DMHardwareKeyboardAttached()) return NO;' && awk '/^static BOOL DMMenuKeysBegin/,/^}/' $S | grep -q 'NSString \*app = DMMenuKeysReader();'"
check "  ... and not while VoiceOver, Switch Control or Full Keyboard Access runs (they move through the menu with the keys)" "awk '/^static BOOL DMMenuKeysBegin/,/^}/' $S | grep -q 'if (DMAXRunning()) return NO;'"
check "  ... the bridge of the app holding the keyboard: its published pid is that app's process" "awk '/^static NSString \*DMMenuKeysReader/,/^}/' $S | grep -q 'externalSceneWithFocus' && awk '/^static NSString \*DMMenuKeysReader/,/^}/' $S | grep -q 'return bridgePid == (uint64_t)pid ? bundle : nil;'"
check "the lease is given, renewed while the menu is open, and cleared when it goes" "awk '/^static BOOL DMMenuKeysBegin/,/^}/' $S | grep -q 'timerWithTimeInterval:kMSBDMenuKeysRenewMs' && awk '/^static void DMMenuKeysEnd/,/^}/' $S | grep -q 'DMMenuKeysPublish(0);'"
check "every way a menu goes ends its keys (removed at once for the next menu, closed)" "awk '/^static void DMRemoveOverlayNow/,/^}/' $S | grep -q 'DMMenuKeysEnd();' && awk '/^static void DMCloseOverlay\(void\)/,/^}/' $S | grep -q 'DMMenuKeysEnd();'"
check "SpringBoard closes the menu on the app's Esc only while that menu has the app's keys" "awk '/^static void DMInstallOverlayEsc/,/^}/' $S | grep -q 'notify_register_dispatch(MSBD_MENU_ESC' && awk '/^static void DMInstallOverlayEsc/,/^}/' $S | grep -q 'if (!gMenuKeysInApp || !gOverlay) return;'"
check "SpringBoard's own Esc (it holds the keys) still closes menus" "awk '/^static void DMOverlayPressesBegan/,/^}/' $S | grep -q 'DMOverlayEscape(nil); return;'"
check "the bridge asks the menu rule first, before the app's Esc handling (Spotlight, Esc Ends Typing)" "awk '/^static void hMABHandleKeyUIEvent/,/^}/' $B | grep -n 'MSBDMenuKeyAct\|MABSpotlightEsc\|MABEscEndsTypingNow' | head -1 | grep -q MSBDMenuKeyAct"
check "  ... posts the menu's Esc on a close, and keeps a taken key from the app" "awk '/^static void hMABHandleKeyUIEvent/,/^}/' $B | grep -q 'if (act == MSBDMenuKeyClose) notify_post(MSBD_MENU_ESC);' && awk '/^static void hMABHandleKeyUIEvent/,/^}/' $B | grep -q 'if (act != MSBDMenuKeyPass) return;'"
check "  ... not in SpringBoard (its own key handler)" "awk '/^static void hMABHandleKeyUIEvent/,/^}/' $B | grep -q '!MABInSpringBoard()'"
check "the bridge says it reads the keys only where its key hook is in, and never in SpringBoard" "grep -q 'if (oMABHandleKeyUIEvent) MABPublishMenuKeys();' $B && awk '/^static void MABPublishMenuKeys/,/^}/' $B | grep -q 'com.apple.springboard' && awk '/^static void MABPublishMenuKeys/,/^}/' $B | grep -q 'notify_set_state(token, (uint64_t)getpid());'"
check "SpringBoard and the bridge share the names and rules (common/MenuKeys.h)" "grep -q '#import \"../common/MenuKeys.h\"' $S && grep -q '#include \"../common/MenuKeys.h\"' $B"
[ $fails = 0 ] && echo "test-menukeys: all wiring checks pass" || { echo "test-menukeys: wiring checks FAILED"; exit 1; }
