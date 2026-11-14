#!/bin/bash
# test-crashguardhang.sh: the crash guard and a SpringBoard that hangs (1.8.7.3, audit M1 of 1.8.7.2). The guard's mark says "this SpringBoard
# has not run 60 s yet"; its clear ran on a background queue, so a SpringBoard whose main thread got stuck 6 to 60 s after its start (a deadlock,
# a layout loop) had its mark cleared at 60 s anyway. The watchdog kills it about a minute into the hang, after that: every start of a hang loop
# then looked like a first one and the guard never acted (only a reboot out of the jailbreak helped). The clear now runs on the main queue
# (a stuck main thread never clears the mark) and the 8 s look stays on a background queue (it acts while the main thread is stuck).
# Real starts of the guard (common/CrashGuard.h MSBDCrashGuardStart) in test-crashguardhang.c, each on its own clock (the guard's two timers fired
# by the program in time order, by the queue the guard names: nothing waits on the wall clock, so a busy Mac cannot change the outcome), with the
# real report judge (MacCrashBlame built for the Mac) and the watchdog fixture as the system's report of each kill. CRASHGUARD_H=<file>: another copy of the guard
# (e.g. the code before the fix: it must fail). Without it, made-to-fail copies follow: each takes one part of the fix out and must fail.
# The guard writes com.besiktasliseba.macstatusbaranddock (its note and the safe mode): refused if the Mac has that domain, removed at the end;
# do not run it at the same time as test-crashstep.sh, which uses that domain too.
cd "$(dirname "$0")" || exit 1
GATE=com.besiktasliseba.macstatusbaranddock DISP=com.besiktasliseba.test-crashguardhang.displays
if defaults read $GATE >/dev/null 2>&1; then echo "the Mac has settings in $GATE: not touching them"; exit 1; fi
W=$(mktemp -d); R="$W/reports"; FIX="$PWD/crash-fixtures/watchdog-stuck-main.ips"
cleanup() {
  for d in $GATE $DISP; do defaults delete $d >/dev/null 2>&1 || true; defaults read $d >/dev/null 2>&1 || rm -f ~/Library/Preferences/$d.plist; done
  rm -rf "$W"
}
trap cleanup EXIT
G0=${CRASHGUARD_H:-../common/CrashGuard.h}
clang -fobjc-arc -dynamiclib -framework Foundation -o "$W/MacCrashBlame.dylib" ../loader/CrashBlameHelper.m || exit 1
build() {   # $1 the guard's header (as the test includes it), $2 the program
  clang -Wall -Wno-unused-function -framework CoreFoundation -iquote ../common -DMSBD_TEST_GUARD_H="\"$1\"" \
    -DMSBD_GUARD_FILE="\"$W/guard.txt\"" -DMSBD_GUARD_REPORTS="\"$R\"" -DMSBD_GUARD_VERDICTS="\"$W/verdicts.txt\"" \
    -DMSBD_GUARD_RECORD="\"$W/record.txt\"" -DMSBD_GUARD_RECENT="\"$W/recent.txt\"" -DMSBD_GUARD_NOTICE_LIB="\"$W/missing-notice.dylib\"" \
    -DMSBD_GUARD_BLAME_LIB="\"$W/MacCrashBlame.dylib\"" -DMSBD_STEP_FILE="\"$W/step.txt\"" -DMSBD_CRASHMAP="\"$W/missing-crashmap.txt\"" \
    -DMSBD_DISP_DOMAIN="\"$DISP\"" -DMSBD_DISP_MSB_DOMAIN="\"$DISP.msb\"" -DMSBD_DISP_DOCK_DOMAIN="\"$DISP.dock\"" \
    -o "$2" test-crashguardhang.c
}
fresh() { rm -rf "$R" "$W"/guard.txt* "$W"/verdicts.txt* "$W"/record.txt* "$W"/recent.txt "$W"/step.txt*; mkdir -p "$R"; defaults delete $GATE >/dev/null 2>&1 || true; }
start() {   # $1 program, $2 alive, $3 stuck, $4 kill | alive: one SpringBoard start; PID and MARK from its line (the mark when the stuck time ended)
  local line; line=$( ("$1" start "$2" "$3" "$4") 2>/dev/null )
  PID=$(echo "$line" | sed -n 's/^pid \([0-9]*\) mark [01]$/\1/p'); MARK=$(echo "$line" | sed -n 's/^pid [0-9]* mark \([01]\)$/\1/p')
}
report() {   # the system's report of a kill, named by the time now: the watchdog fixture, or "half" (still being written: cannot be read yet)
  local d i=1 f; d=$(date +%Y-%m-%d-%H%M%S); f="$R/SpringBoard-$d.ips"
  while [ -e "$f" ]; do i=$((i + 1)); f="$R/SpringBoard-$d-$i.ips"; done
  if [ "$1" = half ]; then printf '{"bug_type":"409"}\n{"threads": [' > "$f"; else cp "$FIX" "$f"; fi
}
markpid() { cut -d' ' -f1 "$W/guard.txt" 2>/dev/null; }
scenarios() {   # $1 program, $2 quiet; the number of failed checks
  local T=$1 q=$2 n=0 p1
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  # A. the entry: a hang loop that starts after a few seconds
  fresh
  start "$T" 10 90 kill; p1=$PID
  c "a start stuck from 10 s and killed at 100 s: its mark stays (the 60 s clear never ran)" "[ \"\$MARK\" = 1 ] && [ -n \"$p1\" ] && [ \"\$(markpid)\" = \"$p1\" ]"
  report
  start "$T" 10 90 kill
  c "  ... the next start is an early one: one crash so far, nothing done; stuck and killed the same way, its mark stays" \
    "[ \"\$MARK\" = 1 ] && [ -n \"\$PID\" ] && [ \"\$(markpid)\" = \"\$PID\" ] && [ ! -e '$W/record.txt' ] && ! defaults read $GATE crashGuardAction"
  report
  start "$T" 10 0 90
  c "  ... the third start acts on the two watchdog kills (the hang loop stops): its record names them, the note is set, the mark is gone" \
    "grep -qx 'action 2' '$W/record.txt' && grep -q '^blamed watchdog:' '$W/record.txt' && [ \"\$(defaults read $GATE crashGuardAction)\" = 2 ] && [ ! -e '$W/guard.txt' ]"
  # B. the 8 s look still acts while the main thread is stuck (a report finished only after the start)
  fresh
  echo "1 $(( $(date +%s) - 5 )) 0 0 0" > "$W/guard.txt"   # (the mark of an earlier start that ended early; pid 1 is never this one)
  report; report half
  start "$T" 0 150 kill
  c "a start stuck from the first moment, one report still being written: the 8 s look counts it and acts with the main thread stuck" \
    "grep -qx 'action 2' '$W/record.txt' && [ \"\$(defaults read $GATE crashGuardAction)\" = 2 ] && [ ! -e '$W/guard.txt' ]"
  # C. a healthy start
  fresh
  start "$T" 0 0 90
  c "a healthy start: its mark is written at the start and goes at 60 s" "[ \"\$MARK\" = 1 ] && [ ! -e '$W/guard.txt' ]"
  # D. a slow moment that ends by itself
  fresh
  start "$T" 10 90 30
  c "stuck from 10 to 100 s, then running again: the mark stays while it is stuck and goes once the main thread runs" "[ \"\$MARK\" = 1 ] && [ ! -e '$W/guard.txt' ]"
  return $n
}

build "$G0" "$W/t" || exit 1
scenarios "$W/t"; rc=$?
if [ -z "$CRASHGUARD_H" ]; then
  mtf() {   # $1 name, $2 a sed script that takes one part of the fix out of the guard
    mkdir -p "$W/mtf"; sed -e "$2" "$G0" > "$W/mtf/CrashGuard.h"
    if cmp -s "$W/mtf/CrashGuard.h" "$G0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if ! build "$W/mtf/CrashGuard.h" "$W/tm"; then echo "FAIL  made-to-fail ($1): did not build"; rc=1; return; fi
    if scenarios "$W/tm" quiet; then echo "FAIL  made-to-fail ($1): the checks still pass"; rc=1; else echo "PASS  made-to-fail ($1): caught"; fi
  }
  mtf "the 60 s clear back on a background queue (the code before the fix)" 's/dispatch_get_main_queue(), NULL, MSBDGuardStable)/dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), NULL, MSBDGuardStable)/'
  mtf "the 8 s look on the main queue too" 's/dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), NULL, MSBDGuardLook)/dispatch_get_main_queue(), NULL, MSBDGuardLook)/'
  mtf "no 60 s clear at all" '/NULL, MSBDGuardStable);$/d'
fi
[ $rc = 0 ] && echo "test-crashguardhang: all pass" || echo "test-crashguardhang: FAILED"
exit $rc
