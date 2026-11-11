#!/bin/bash
# Mac test: the Charge Limit's job (1.8.6): one job at a time (an unknown argument refused, a second job ends without touching anything) and a
# charge setting changed in Settings planned again at once (Run on Power Adapter off above the limit comes down without waiting out the cut's
# 30 minutes). The job runs on a simulated iPad (chargejob-sim.h); plus the wiring.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -framework Foundation -o "$W/t" test-chargeplan.m
fails=0
for s in args help second roaoff roaon roaoffsoc; do
  echo "-- $s"
  rm -rf "$W/state" "$W/msbdcharge.log"
  "$W/t" $s || fails=1
done
M=../chargehelper/main.m
check() { if "${@:2}"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the job's lock is an exclusive, non-blocking flock on a file in its state folder, kept for its life" bash -c "grep -q 'flock(f, LOCK_EX | LOCK_NB)' $M && grep -q 'kStateDir \"/chargelimit.lock\"' $M"
check "  ... taken before ResetCharging, the job's first lever (and by --reset before its own)" bash -c "awk '/^int main\\(/,0' $M | grep -E 'if \\(!JobLockTake\\(\\)\\)|ResetCharging\\(nil, NO, NO\\)' | head -1 | grep -q 'JobLockTake' && awk '/^int main\\(/,0' $M | grep -E 'jobRuns = !JobLockTake\\(\\)|ResetCharging\\(@\"--reset\"' | head -1 | grep -q 'JobLockTake'"
check "an unknown argument: usage, exit 2" grep -q 'return help ? 0 : 2;' "$M"
[ $fails = 0 ] && echo "test-chargeplan: all scenarios pass" || { echo "test-chargeplan: FAILED"; exit 1; }
