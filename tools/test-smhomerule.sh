#!/bin/bash
# Mac test of the Stage Manager engine's Home rule (statusbar/SMHomeRule.h, test-smhomerule.m): Home keeps the desktop's windows, a full-screen
# window goes to the background, everything else is left as SpringBoard built it; a random sweep of the plan's invariants (4 and 7 window roles).
# 1.8.7.5 (audit L43 of 1.8.7.2): the Home Screen's own press after Home, for the kept windows and with Home Minimizes Windows (SMHome.h's hide
# branch, cut out of the real file): there for a folder the person was looking at behind the windows only (its review: no first page with nothing
# open). SMHOMERULE_H=<file> / SMHOME_H=<file>: other copies (e.g. the code before a fix: it must fail); without either, made-to-fail copies follow.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
RULE0=${SMHOMERULE_H:-$PWD/../statusbar/SMHomeRule.h}; HOME0=${SMHOME_H:-$PWD/../statusbar/SMHome.h}
run() {   # $1 rule header, $2 SMHome.h, $3 quiet, $4 a sed expression for the cut hide branch (made-to-fail); the test's exit status
  local d=$W/b; rm -rf "$d"; mkdir -p "$d"
  awk '/^    if \(plan\[@"hide"\]\) \{/{f=1} f{print} f&&/^    \}$/{exit}' "$2" > "$d/hide-cut.h"
  [ -s "$d/hide-cut.h" ] || { echo "FAIL  SMHome.h's hide branch not found"; return 1; }
  [ -z "$4" ] || sed -i '' -e "$4" "$d/hide-cut.h"
  local has=-DSMH_PRESS_RULE=0
  /usr/bin/grep -q '^static BOOL DMSMHomePressesAtHome(NSDictionary \*plan, long long prevEnv) ' "$1" && has=-DSMH_PRESS_RULE=2
  /usr/bin/grep -q '^static BOOL DMSMHomePressesAtHome(NSDictionary \*plan, long long prevEnv, BOOL folderShown) ' "$1" && has=-DSMH_PRESS_RULE=3
  if [ -n "$3" ]; then
    clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -DSMH_RULE_H="\"$1\"" -DSMH_HIDE_CUT="\"$d/hide-cut.h\"" $has -o "$d/thr" test-smhomerule.m >/dev/null 2>&1 || return 2
    "$d/thr" >/dev/null 2>&1
  else
    clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -DSMH_RULE_H="\"$1\"" -DSMH_HIDE_CUT="\"$d/hide-cut.h\"" $has -o "$d/thr" test-smhomerule.m || return 1
    "$d/thr"
  fi
}
rc=0
run "$RULE0" "$HOME0" || rc=1
# the keep branch takes the same rule (its press as before)
if /usr/bin/grep -q 'BOOL pressAtHome = DMSMHomePressesAtHome(plan, prevEnv, gHomeFolder.showing);   // (SMHomeRule.h: the same rule as for the windows that go)' "$HOME0" \
   && [ "$(/usr/bin/grep -c 'BOOL pressAtHome = DMSMHomePressesAtHome(plan, prevEnv, gHomeFolder.showing);' "$HOME0")" = 2 ]; then echo "PASS  site: both branches of SMHome.h take DMSMHomePressesAtHome"
else echo "FAIL  site: both branches of SMHome.h take DMSMHomePressesAtHome"; rc=1; fi
if [ -z "$SMHOMERULE_H$SMHOME_H" ]; then
  mtf() {   # $1 name, $2 rule sed ("" none), $3 hide-branch sed ("" none)
    cp "$RULE0" "$W/rule.h"; [ -z "$2" ] || sed -i '' -e "$2" "$W/rule.h"
    if [ -n "$2" ] && cmp -s "$W/rule.h" "$RULE0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    local r=0; run "$W/rule.h" "$HOME0" quiet "$3" || r=$?
    if [ $r = 0 ]; then echo "FAIL  made-to-fail ($1): the checks still pass"; rc=1; elif [ $r = 2 ]; then echo "FAIL  made-to-fail ($1): did not build"; rc=1; else echo "PASS  made-to-fail ($1): caught"; fi
  }
  mtf "the hide plan without atHome (the code before the fix)" 's/return @{@"hide": all, @"atHome": @(away.count == 0)};/return @{@"hide": all};/' ""
  mtf "the hide plan at Home with a full-screen window too" 's/return @{@"hide": all, @"atHome": @(away.count == 0)};/return @{@"hide": all, @"atHome": @YES};/' ""
  mtf "the rule without 'from the desktop on screen'" 's/if (!\[plan\[@"atHome"\] boolValue\] || prevEnv != 3) return NO;/if (![plan[@"atHome"] boolValue]) return NO;/' ""
  mtf "the hide plan pressing with nothing open (the code before the review)" 's/return plan\[@"hide"\] ? folderShown : YES;/return YES;/' ""
  mtf "the hide branch still without the press" "" 's/DMSMHomeAfterKeep(press);/DMSMHomeAfterKeep(NO);/'
  mtf "the hide branch pressing always" "" 's/DMSMHomeAfterKeep(press);/DMSMHomeAfterKeep(YES);/'
  mtf "the hide branch not asking for the folder looked at" "" 's/DMSMHomePressesAtHome(plan, prevEnv, gHomeFolder.showing)/DMSMHomePressesAtHome(plan, prevEnv, YES)/'
  mtf "the press not checked for the folder still open" "" 's/BOOL press = pressAtHome \&\& DMHomeFolderOpenNow();/BOOL press = pressAtHome;/'
fi
exit $rc
