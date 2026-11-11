#!/bin/bash
# Mac test: a hold or adapter cut of the Charge Limit's that no job holds any more (powerd kept it after its owner was gone: the M1, 5-7 Nov) is
# cleared when it is in the way -- by the job once it has been seen for a minute and only while it visibly blocks what the job does with the
# cable in, by the Sleep Guard's own rule (the screen off, no live keep-awake assertion of another process, at most once in 30 minutes), by the
# prerm's --reset when the package goes -- with powerd started over and the scheduled wakes put back; and after any powerd restart (the Sleep
# Guard's too) the job's own are with the new powerd at once. The job runs on a simulated iPad (chargejob-sim.h).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -framework Foundation -o "$W/t" test-chargeleftover.m
fails=0
for s in f3-reset f3-slowpowerd f3-kickfails job-allow job-hold transient limits byhand byhand-leftover hang unplugged screenon liveawake a12z sleepguard; do
  echo "-- $s"
  rm -rf "$W/state" "$W/msbdcharge.log"
  "$W/t" $s || fails=1
done
[ $fails = 0 ] && echo "test-chargeleftover: all scenarios pass" || { echo "test-chargeleftover: FAILED"; exit 1; }
