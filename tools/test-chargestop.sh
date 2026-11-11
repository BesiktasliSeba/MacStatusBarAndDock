#!/bin/bash
# Mac test: the Charge Limit's job lets go of its hold and adapter cut before the package stops it (msbdcharge --stop in the prerm, before the
# launchctl unload), so nothing it held can stay with powerd after its death (the M1's dead-owner "Charge Limit (on hold)" holds, 5-7 Nov).
# The job itself runs on a simulated iPad (chargejob-sim.h); the prerm's charge steps are taken from layout/DEBIAN/prerm, in its order.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -framework Foundation -o "$W/t" test-chargestop.m
steps=$(awk '!/^[[:space:]]*#/ { if (/msbdcharge --stop/) print "stop"; else if (/launchctl unload .*chargelimit/) print "kill"; else if (/msbdcharge --reset/) print "reset" }' ../layout/DEBIAN/prerm | tr '\n' ' ')
echo "prerm's charge steps: $steps"
psteps=$(awk '/^elif/ {exit} !/^[[:space:]]*#/ { if (/msbdcharge --stop/) print "stop"; else if (/unload .*chargelimit/) print "kill"; else if (/load .*chargelimit/) print "start" }' \
  ../layout/DEBIAN/postinst | tr '\n' ' ')
echo "postinst's charge steps (configure): $psteps"
fails=0
for s in "prerm-smc $steps" "prerm-cut $steps" "prerm-pmu $steps" "postinst-smc $psteps" stop-direct stop-nojob; do
  echo "-- $s"
  rm -rf "$W/state" "$W/msbdcharge.log"
  "$W/t" $s || fails=1
done
[ $fails = 0 ] && echo "test-chargestop: all scenarios pass" || { echo "test-chargestop: FAILED"; exit 1; }
