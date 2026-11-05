#!/bin/bash
# Mac test of Aerial 5's own settings held while it is our engine (statusbar/AerialHeld.h, test-aerialheld.m): its icon-menu rows off, the user's copy.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-aerialheld.m
"$W/t"
# ... as built (StatusBar.x, code review 1.8.1, 6): an earlier build seen only on a marked copy, its "on" not recorded, what the mark kept given back before the copy is written; the mark keeps the copy's values
X=../statusbar/StatusBar.x; fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
FN=$(awk 'index($0, "static void DMAerial5SwallowPrefs(NSString *why) {") == 1 {f=1} f {print} f && /^}/ {exit}' "$X")
check "the pass: an earlier build seen on a marked copy only, not the user's, the copy back from the mark, then written" \
  "echo \"\$FN\" | awk '/earlierRan = haveBackup && marked && MSBDA5EarlierBuildRan\\(cur\\);/{a=1} a&&/MSBDA5RecordUser\\(user, cur, wanted, !marked \\|\\| earlierRan\\)/{b=1} b&&/if \\(earlierRan\\) \\{ MSBDA5UserBackFromMark\\(user, \\[NSDictionary dictionaryWithContentsOfFile:mark\\]\\);/{c=1} c&&/\\[user writeToFile:backupPrefs atomically:YES\\]/{print \"ok\"; exit}' | grep -q ok"
check "  ... the mark keeps the copy's values of those keys, written when they change, after the copy" \
  "echo \"\$FN\" | awk '/\\[user writeToFile:backupPrefs atomically:YES\\]/{a=1} a&&/NSDictionary \\*markNow = MSBDA5MarkValues\\(user\\);/{b=1} b&&/if \\(!marked \\|\\| !\\[\\[NSDictionary dictionaryWithContentsOfFile:mark\\] isEqualToDictionary:markNow\\]\\) \\[markNow writeToFile:mark atomically:YES\\];/{print \"ok\"; exit}' | grep -q ok"
exit $fails
