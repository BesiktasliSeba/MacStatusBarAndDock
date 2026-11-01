#!/bin/bash
# Mac test of the Ethernet row's rule (common/InputDevices.h, test-ethernetrow.m; 1.7.5 item 3), then the wiring as built: the watcher's answer,
# the same pointer / keyboard readers as our Pointer and Keyboard rows, the sidebar asked again when a device comes or goes.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/ter" test-ethernetrow.m
"$W/ter"
E=../macsettings/EthernetFix.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
check "the watcher: Apple's own answer first, then the rule with the pointer and keyboard as our rows read them" \
  "grep -q 'BOOL adapter = %orig;' $E && grep -q 'BOOL pointer = MSBDPointerAttached(), keyboard = MSBDKeyboardAttached();' $E && grep -q 'BOOL listed = MSBDEthernetListed(adapter, pointer, keyboard);' $E && grep -q '    return listed;' $E"
check "our Pointer and Keyboard rows show exactly when those readers say attached (one source)" \
  "grep -q '^BOOL MSPointerDeviceAttached(void) { return MSBDPointerAttached(); }' ../macsettings/PointerSettings.x && grep -q '^BOOL MSKeyboardAttached(void) { return MSBDKeyboardAttached(); }' ../macsettings/KeyboardSettings.x && grep -q 'if (MSPointerDeviceAttached()) \[specs insertObject:MSPointerRowSpecifier(self) atIndex:next++\];' ../macsettings/MacSettings.x && grep -q 'if (MSKeyboardAttached()) \[specs insertObject:MSKeyboardRowSpecifier(self) atIndex:next\];' ../macsettings/MacSettings.x"
check "  ... and on 18 in General's group the same way" \
  "grep -q 'if (MSPointerDeviceAttached()) \[rows addObject:MSPointerRowSpecifier(target)\];' ../macsettings/MacSettings.x && grep -q 'if (MSKeyboardAttached()) \[rows addObject:MSKeyboardRowSpecifier(target)\];' ../macsettings/MacSettings.x"
check "a device attached or detached: 15-17's sidebar asks again through its own -updateEthernet (type-checked), after our rows followed" \
  "fn 'static void EthernetAskAgain(void) {' $E | grep -q 'strcmp(t, \"v16@0:8\") != 0' && fn 'static void EthernetAskAgain(void) {' $E | grep -q 'objc_msgSend)(l, @selector(updateEthernet));' && fn 'static void EthernetFollowDevices(void) {' $E | grep -q 'MSBD_POINTER_CHANGED' && fn 'static void EthernetFollowDevices(void) {' $E | grep -q 'MSBD_KEYBOARD_CHANGED'"
check "  ... 18 (no UIKit sidebar list) only: Preferences' own change notification (the SwiftUI sidebar follows it; Apple's Ethernet pages on 15-17 never get it)" \
  "fn 'static void EthernetAskAgain(void) {' $E | grep -q 'objc_getClass(\"PSUIPrefsListController\") ? NULL : (NSString \*const \*)dlsym(RTLD_DEFAULT, \"PSEthernetChangedNotification\")' && fn 'static void EthernetAskAgain(void) {' $E | grep -q 'postNotificationName:\*note object:watcher'"
check "our rows catch up with a device change made before the sidebar was watched (one reload when it appears), so they and Ethernet never disagree" \
  "fn 'void MSPointerWatchSidebar(PSListController *sidebar) {' ../macsettings/PointerSettings.x | grep -q 'if (sidebar && shown != MSPointerDeviceAttached()) dispatch_async' && fn 'void MSKeyboardWatchSidebar(PSListController *sidebar) {' ../macsettings/KeyboardSettings.x | grep -q 'if (sidebar && shown != MSKeyboardAttached()) dispatch_async'"
check "  ... wired when the watcher is hooked; Lynx's own Ethernet option still wins (ours not added then)" \
  "grep -q '        EthernetFollowDevices();' $E && grep -q 'if (MSBDOtherTweakDoing(kMSBDDupEthernetSection, NO)) MLog' $E"
[ $fails = 0 ] && echo "test-ethernetrow: wiring checks pass" || { echo "test-ethernetrow: wiring checks FAILED"; exit 1; }
