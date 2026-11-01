#!/bin/bash
# Mac test of Prewarm Apps' default (common/PrewarmDefault.h, test-prewarmdefault.c; 1.7.7, KT): never set, off on a 2 GB iPad and on with more.
# The rule itself, its debug-build RAM override, and below, in the code as built: SpringBoard (the quit set's file for dasd) and Settings (the
# switch) both go by that one rule, and neither writes the default.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreFoundation -o "$W/tpd" test-prewarmdefault.c
"$W/tpd"
clang -O2 -Wall -Wno-unused-function -DDEBUG=1 "-DFAKE_RAM_FILE=\"$W/fakeram\"" -framework CoreFoundation -o "$W/tpdd" test-prewarmdefault.c
"$W/tpdd" "$W/fakeram"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
SB=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/MSBRootListController.m
check "SpringBoard: Prewarm Apps by the rule (a boolean stored, else the RAM's default), read with the other settings" \
  "awk '/^static void DMLoadPrefs\\(void\\) \\{/{f=1} f&&/CFSTR\\(\"prewarmApps\"\\)/{k=1} k&&/int stored = MSBDPrewarmAppsStored\\(pw\\);/{s=1} s&&/DMPrewarmAppsSet\\(MSBDPrewarmAppsOn\\(stored, MSBDPrewarmRAM\\(\\)\\) != 0\\);/{print \"ok\"; exit}' $SB | grep -q ok"
check "Settings: the switch shows the same rule (its own read of the value, not the plist's default)" \
  "awk '/^- \\(id\\)readPreferenceValue:/,/^}/' $P | grep -q 'isEqual:@\"prewarmApps\"\\]) return @(MSBPrewarmAppsInForce());' && awk '/^static BOOL MSBPrewarmAppsInForce\\(void\\) \\{/,/^}/' $P | grep -q 'int stored = MSBDPrewarmAppsStored(v);' && awk '/^static BOOL MSBPrewarmAppsInForce\\(void\\) \\{/,/^}/' $P | grep -q 'return MSBDPrewarmAppsOn(stored, MSBDPrewarmRAM()) != 0;'"
check "neither writes the default: no prewarmApps written by SpringBoard or the page's code (only a tap on the switch stores one)" \
  "! grep -n 'CFPreferencesSet[A-Za-z]*Value(CFSTR(\"prewarmApps\")' $SB $P ../macsettings/sshtoggled/main.m"
[ $fails = 0 ] && echo "test-prewarmdefault: wiring checks pass" || { echo "test-prewarmdefault: wiring checks FAILED"; exit 1; }
