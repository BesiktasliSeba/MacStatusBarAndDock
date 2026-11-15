#!/bin/bash
# test-menubarsizeguard.sh: Menu Bar Size and the crash guard's step 1 (1.8.7.5, audit L62 of 1.8.7.2). Picking a larger Menu Bar Size was not
# noted for the guard (only switch cells are, and the size row is a list): a crash right after picking Large with only Apple code on the stack went
# to safe mode instead of setting the size back. Now the size branch notes a larger size as the size's "on" (step 1 writes false, read as Small)
# and back to Small takes the note out. The real code cut out of MSBRootListController.m, StatusBar.x and LineSwitch.h (menubarsizeguard-cut.py,
# crashstep-pagescut.py; Mac Status Bar's domain made a test one), the real CrashGuard.h step 1, a scratch RecentlyOn list.
# Review of 1.8.7.5: a size pick that ends the crash guard's note takes its footer and Report a Problem off the page at once, as a switch does
# (LineSwitch.h -msbd_guardNoteMaybeGone, cut out by menubarsizeguard-cut.py, on a stand-in page).
# CRASHSTEP_PREFS_M=<file>: another MSBRootListController.m (e.g. the code before the fix: it must fail). Without it, made-to-fail copies follow.
# Reads and, for its last checks, writes the crash guard's note (com.besiktasliseba.macstatusbaranddock; refused if the Mac has one, taken away at
# the end): run it while holding the mac-tests lock.
cd "$(dirname "$0")" || exit 1
TDOM=com.besiktasliseba.test-menubarsizeguard GATE=com.besiktasliseba.macstatusbaranddock
W=$(mktemp -d)
GATE_HAD=; defaults read $GATE >/dev/null 2>&1 && GATE_HAD=1
cleanup() {
  defaults delete $TDOM >/dev/null 2>&1 || true; defaults read $TDOM >/dev/null 2>&1 || rm -f ~/Library/Preferences/$TDOM.plist
  if [ -n "$GATE_HAD" ]; then defaults delete $GATE crashGuardAction >/dev/null 2>&1 || true
  else defaults delete $GATE >/dev/null 2>&1 || true; defaults read $GATE >/dev/null 2>&1 || rm -f ~/Library/Preferences/$GATE.plist; fi
  rm -rf "$W"
}
trap cleanup EXIT
PM0=${CRASHSTEP_PREFS_M:-$PWD/../statusbar/macstatusbarprefs/MSBRootListController.m}
run() {   # $1 controller, $2 quiet: builds and runs the test on it
  local d=$W/b; rm -rf "$d"; mkdir -p "$d"; defaults delete $TDOM >/dev/null 2>&1 || true
  python3 -I crashstep-pagescut.py ../common/LineSwitch.h "$1" "$d/pages-cut.h" "$d/picker-cut.h" || { echo "FAIL  LineSwitch.h's lines not found"; return 1; }
  python3 -I menubarsizeguard-cut.py "$1" ../statusbar/StatusBar.x $TDOM "$d/stored.h" "$d/branch.h" "$d/sb.h" ../common/LineSwitch.h "$d/refresh.h" || { echo "FAIL  the size's lines not found"; return 1; }
  clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -iquote ../common -DMSBD_TEST_LINESWITCH_CUT="\"$d/pages-cut.h\"" \
    -DMSBD_TEST_SIZE_STORED="\"$d/stored.h\"" -DMSBD_TEST_SIZE_BRANCH="\"$d/branch.h\"" -DMSBD_TEST_SB_STORED="\"$d/sb.h\"" -DMSBD_TEST_PAGE_REFRESH="\"$d/refresh.h\"" \
    -DMSBD_GUARD_RECENT="\"$d/recent.txt\"" -DMSBD_GUARD_RECORD="\"$d/record.txt\"" -o "$d/t" test-menubarsizeguard.m || { echo "FAIL  did not build"; return 1; }
  if [ -n "$2" ]; then "$d/t" >/dev/null 2>&1; else "$d/t"; fi
}
run "$PM0"; rc=$?
# (the switches' own way to the same refresh: msbd_noteSwitch calls it, as it did these lines before)
if [ "$(/usr/bin/grep -c '\[self msbd_guardNoteMaybeGone\];' ../common/LineSwitch.h)" = 1 ] && /usr/bin/grep -B3 '^	\[self msbd_guardNoteMaybeGone\]; \\$' ../common/LineSwitch.h | /usr/bin/grep -q 'MSBDNoteSwitch(\[specifier propertyForKey:@"defaults"\]'; then
  echo "PASS  site: a switch cell's note (msbd_noteSwitch) takes the same refresh"
else echo "FAIL  site: a switch cell's note (msbd_noteSwitch) takes the same refresh"; rc=1; fi
if [ -z "$CRASHSTEP_PREFS_M" ]; then
  mtf() {   # $1 name, $2 sed expression on the controller
    sed -e "$2" "$PM0" > "$W/mtf.m"
    if cmp -s "$W/mtf.m" "$PM0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if run "$W/mtf.m" quiet; then echo "FAIL  made-to-fail ($1): the checks still pass"; rc=1; else echo "PASS  made-to-fail ($1): caught"; fi
  }
  mtf "nothing noted (the code before the fix)" '/if (size > before) MSBDNoteSwitch(/d'
  mtf "noted only from Small (Medium -> Large not again)" 's/if (size > before) MSBDNoteSwitch(/if (before == MSBDMenuBarSmall \&\& size > before) MSBDNoteSwitch(/'
  mtf "back to Small keeps the note" '/else if (size == MSBDMenuBarSmall) MSBDNoteSwitch(/d'
  mtf "a smaller size takes the note out" 's/else if (size == MSBDMenuBarSmall) MSBDNoteSwitch(/else MSBDNoteSwitch(/'
  mtf "the size branch leaves the page as it was (the code before the review)" '/\[self msbd_guardNoteMaybeGone\];   \/\/ (a note that ended so/d'
fi
[ $rc = 0 ] && echo "test-menubarsizeguard: all pass" || echo "test-menubarsizeguard: FAILED"
exit $rc
