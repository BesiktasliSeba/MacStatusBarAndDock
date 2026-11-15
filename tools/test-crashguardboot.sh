#!/bin/bash
# test-crashguardboot.sh: the crash guard's start and a mark from before this boot (1.8.7.5, audit L105 of 1.8.7.2). The guard's start
# (common/CrashGuard.h MSBDCrashGuardStart) returned at once when the mark held its own pid ("both loaders run in SpringBoard: the first one did
# it") before it asked whether the mark was from before this boot. SpringBoard's pid can come round again after a reboot, and then that start did
# nothing: no row, no 8 s look, no 60 s clear, the stale mark kept (a crash loop in that boot then had one start less in its row). The boot check
# now comes first: a mark from before this boot is a new row whatever pid it holds; the second loader of the same SpringBoard still returns, as
# it reads the mark the first one wrote in this boot.
# Real starts of the guard in test-crashguardboot.c, one process per scenario, with an empty report folder and no helper (nothing is judged and
# no preference is written: the scenarios never act). The Mac's own kern.boottime is the boot. CRASHGUARD_H=<file>: another copy of the guard
# (e.g. the code before the fix: it must fail). Without it, made-to-fail copies follow: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
G0=${CRASHGUARD_H:-../common/CrashGuard.h}
build() {   # $1 the guard's header (as the test includes it), $2 the program
  clang -Wall -Wno-unused-function -iquote ../common -DMSBD_TEST_GUARD_H="\"$1\"" \
    -DMSBD_GUARD_FILE="\"$W/guard.txt\"" -DMSBD_GUARD_REPORTS="\"$W/reports\"" -DMSBD_GUARD_VERDICTS="\"$W/verdicts.txt\"" \
    -DMSBD_GUARD_RECORD="\"$W/record.txt\"" -DMSBD_GUARD_RECENT="\"$W/recent.txt\"" -DMSBD_GUARD_NOTICE_LIB="\"$W/missing-notice.dylib\"" \
    -DMSBD_GUARD_BLAME_LIB="\"$W/missing-blame.dylib\"" -DMSBD_STEP_FILE="\"$W/step.txt\"" -DMSBD_CRASHMAP="\"$W/missing-crashmap.txt\"" \
    -DMSBD_DISP_DOMAIN="\"com.besiktasliseba.test-crashguardboot.displays\"" \
    -o "$2" test-crashguardboot.c
}
scenarios() {   # $1 program, $2 quiet; returns the number of failed scenarios
  local n=0 sc out
  for sc in oldsame now oldother early; do
    rm -rf "$W/reports" "$W"/guard.txt* "$W"/verdicts.txt "$W"/record.txt "$W"/step.txt; mkdir -p "$W/reports"
    out=$("$1" "$sc" 2>&1) || n=$((n + 1))
    [ -n "$2" ] || echo "$out"
    [ -e "$W/record.txt" ] && { [ -n "$2" ] || echo "FAIL  $sc: the guard wrote a record (it must not act here)"; n=$((n + 1)); }
  done
  return $n
}
build "$G0" "$W/t" || exit 1
scenarios "$W/t"; rc=$?
if [ -z "$CRASHGUARD_H" ]; then
  mtf() {   # $1 name, $2.. sed arguments that take one part of the fix out of the guard
    local name=$1; shift
    mkdir -p "$W/mtf"; sed "$@" "$G0" > "$W/mtf/CrashGuard.h"
    if cmp -s "$W/mtf/CrashGuard.h" "$G0"; then echo "FAIL  made-to-fail ($name): the copy did not change"; rc=1; return; fi
    if ! build "$W/mtf/CrashGuard.h" "$W/tm"; then echo "FAIL  made-to-fail ($name): did not build"; rc=1; return; fi
    if scenarios "$W/tm" quiet; then echo "FAIL  made-to-fail ($name): the checks still pass"; rc=1; else echo "PASS  made-to-fail ($name): caught"; fi
  }
  mtf "the same-pid return before the boot check (the code before the fix)" -e '/mark from before this boot: a new row/{h;d;}' -e '/s\.pid == getpid()) return;/G'
  mtf "no boot check" -e '/mark from before this boot: a new row/d'
  mtf "no same-pid return (the second loader would look again)" -e '/s\.pid == getpid()) return;/d'
fi
[ $rc = 0 ] && echo "test-crashguardboot: all pass" || echo "test-crashguardboot: FAILED"
exit $rc
