#!/bin/bash
# Mac test of MilkyWay4's "Launch As Window" row (statusbar/MilkyWayRow.h, test-milkywayrow.m): the rule, then, as built, that StatusBar.x asks it on the list both
# menu styles are built from, only while MilkyWay4 is our engine.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-milkywayrow.m
"$W/t"
X=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
# the hook's lines, in the group installed 3 s after SpringBoard starts
B=$(awk '/^%group ZetsuIconItems/{on=1} on{print} on&&/^%end/{e++; if(e==2) exit}' "$X")
hook=$(printf '%s\n' "$B" | awk '/^- \(NSArray \*\)effectiveApplicationShortcutItems/{on=1} on{print} on&&/^}/{exit}')
check "the row goes through the hook of -effectiveApplicationShortcutItems, in the icon menu group" "[ -n \"\$hook\" ]"
check "... only while MilkyWay4 is our engine" "printf '%s\n' \"\$hook\" | sed -n '2,3p' | grep -qF 'if (DMActiveEngine() != DMEngineMilkyWay) return items;'"
check "... by the icon view's place" "printf '%s\n' \"\$hook\" | grep -qF 'id location = DMCall(self, @\"location\");' && printf '%s\n' \"\$hook\" | grep -qF 'DMMilkyRowOpensWindowAt(location)'"
check "... and the row is taken out where it doesn't open one" "printf '%s\n' \"\$hook\" | grep -qF '? items : DMMilkyRowsWithoutLaunch(items);' && printf '%s\n' \"\$hook\" | grep -qF 'return kept;'"
check "our own launch into a MilkyWay window still sends the same type (DMLaunchAsWindow: never through the menu's list)" "grep -qF '[item setType:@\"jp.yuri.milkyway3.launchinwindow\"];' $X"
check "a crash in the row's rule is the windowing's (the sym rule for DMMilky..., and the group's)" "grep -qF '|DMMilky|' crashmap-rules.txt && [ \"\$(grep -c '^static' ../statusbar/MilkyWayRow.h)\" = \"\$(grep -c '^static [A-Za-z]* \*\?DMMilky' ../statusbar/MilkyWayRow.h)\" ]"
[ "$fails" = 0 ] && echo "test-milkywayrow wiring: passed" || { echo "test-milkywayrow wiring: FAILED"; exit 1; }
