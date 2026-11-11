#!/bin/bash
# Mac test: the Charge Limit's hold and adapter cut are checked against the battery (charge still going in after they went up), and one that does
# not take is given up for the rest of the plug-in -- iPadOS's own charging, no cut in the hold's place, no stay-awake, a state that says so --
# while the iPads whose chargers keep them hold as before. The job runs on a simulated iPad (chargejob-sim.h) with each iPad's chargers as read.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -framework Foundation -o "$W/t" test-chargeverify.m
# (a second build of the job, for newbuild: another executable, the same state folder)
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -DSIM_BUILD=2 -framework Foundation -o "$W/t2" test-chargeverify.m
fails=0
for s in a12z pd17 m1 brick17 replug remember otherprefs gauge noamp noreadings; do
  echo "-- $s"
  rm -rf "$W/state" "$W/msbdcharge.log"
  "$W/t" $s || fails=1
done
echo "-- newbuild: started again, the same build"
rm -rf "$W/state" "$W/msbdcharge.log"
{ "$W/t" newbuild-first && "$W/t" newbuild-next remembered; } || fails=1
echo "-- newbuild: started again, another build of the job"
rm -rf "$W/state" "$W/msbdcharge.log"
{ "$W/t" newbuild-first && "$W/t2" newbuild-next tried; } || fails=1
[ $fails = 0 ] && echo "test-chargeverify: all scenarios pass" || { echo "test-chargeverify: FAILED"; exit 1; }
