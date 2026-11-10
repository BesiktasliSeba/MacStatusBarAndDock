#!/bin/bash
# Mac test of the Command-Tab switcher's selected item (common/CmdTabSelection.h, test-cmdtabselection.c), then the sites: every read of SpringBoard's getter goes through DMCmdTabSelectedItem.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/t" test-cmdtabselection.c
fails=0; "$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; A=../statusbar/ActMonDock.h
check "the getter is called in one place only, after the check" "[ \"\$(cat $S $A | grep -cF '@\"selectedApplicationDisplayItem\"')\" = 1 ] && awk '/^static id DMCmdTabSelectedItem\\(/{f=1} f{print} f&&/^}/{exit}' $S | tail -2 | grep -qF 'return DMCall(vc, @\"selectedApplicationDisplayItem\");' && awk '/^static id DMCmdTabSelectedItem\\(/{f=1} f{print} f&&/^}/{exit}' $S | grep -qF 'if (!MSBDCmdTabSelectionReadable('"
check "Command-Tab's launch, its first pick, Command-Q and the engines' launch read through it" "[ \"\$(grep -cF 'DMCmdTabSelectedItem(' $A)\" = 3 ] && grep -qF 'id item = DMCmdTabSelectedItem(vc);' $S"
[ "$fails" = 0 ] && echo "test-cmdtabselection: all pass" || { echo "test-cmdtabselection: FAILED"; exit 1; }
