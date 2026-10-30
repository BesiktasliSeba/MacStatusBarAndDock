#!/bin/bash
# Mac test (wiring) of Esc and the Dock's Downloads panel (1.7.0): while the panel is open SpringBoard holds the keyboard focus (a hardware keyboard),
# so Esc reaches SpringBoard's key handling also while an app's window had the keys (M1 15.6.1: Esc went to the app and the panel stayed), and
# gives it back whichever way the panel closes; SpringBoard's always-installed Esc hook asks the panel first, not only Finder's hook group.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../dock/Downloads.m; S=../statusbar/StatusBar.x
check "the panel takes the keys as it opens" "grep -q '\[self holdKeys:YES\];' $D && awk '/^- \(void\)presentItems:/,/^- \(void\)debugTapFolder:/' $D | grep -q 'holdKeys:YES'"
check "and gives them back as it closes (every close ends in -dismissAnimated:)" "awk '/^- \(void\)dismissAnimated:/,/^- \(void\)toggleFromIcon:/' $D | grep -q 'holdKeys:NO'"
check "only with a hardware keyboard, through the shared focus lock (15-18)" "grep -q 'DMDLHardwareKeyboard()' $D && grep -q 'MSBDFocusLock(self.panel.window.windowScene' $D && grep -q 'MSBDFocusUnlock(lock)' $D && grep -q 'common/FocusLock.h' $D"
check "the panel's Esc is exported for SpringBoard's key handling" "grep -q 'BOOL MSBDDownloadsPanelEscape(void)' $D"
check "with text in the search field that Esc clears it first (as the field's own Esc)" "awk '/BOOL MSBDDownloadsPanelEscape\\(void\\)/,/^}/' $D | grep -q 'if (p.searchField.text.length) { \\[p searchEscape\\]; return YES; }'"
check "SpringBoard's always-installed Esc hook asks the panel first" "awk '/^static void DMOverlayPressesBegan/,/^}/' $S | head -5 | grep -q 'DMDownloadsPanelTakesEsc(presses)'"
check "and the native windows' key hook still does (Finder on)" "awk '/^%group DMNativeHooks/,/^%end/' $S | grep -q 'if (DMDownloadsPanelTakesEsc(presses)) return;'"
[ $fails = 0 ] && echo "test-downloadsesc: all wiring checks pass" || { echo "test-downloadsesc: wiring checks FAILED"; exit 1; }
