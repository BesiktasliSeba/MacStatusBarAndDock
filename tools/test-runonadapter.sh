#!/bin/bash
# Mac test: Run on Power Adapter (KT, 6 Nov): while plugged in the Charge Limit's job holds the battery where it was when the cable went in, with
# the limit's own hold and checks; never above the Charge Limit, never under 20 %, given up where the hold does not take, off unless switched on.
# The job runs on a simulated iPad (chargejob-sim.h); then the setting's row in the Charging group.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -framework Foundation -o "$W/t" test-runonadapter.m
fails=0
for s in hold55 load limit low replug a12z off switchon monthly pmu; do
  echo "-- $s"
  rm -rf "$W/state" "$W/msbdcharge.log"
  "$W/t" $s || fails=1
done
# the row: a switch in the Charging group, stored in our domain (missing = off), the job told at once (the settings notification)
row() {
  local f=../macsettings/BatteryHealth.x
  grep -q 'preferenceSpecifierNamed:@"Run on Power Adapter"' $f && grep -q '\[adapter setProperty:@MSBD_CHARGE_ADAPTER_KEY forKey:@"key"\];' $f &&
  grep -q '\[adapter setProperty:@NO forKey:@"default"\];' $f && grep -q '\[adapter setProperty:@MSBD_CHARGE_PREFS_CHANGED forKey:@"PostNotification"\];' $f &&
  grep -q 'kMSBHCellSwitch' $f
}
if row; then echo "PASS  the row: a switch in the Charging group, off unless set, the job told at once"; else echo "FAIL  the row: a switch in the Charging group, off unless set, the job told at once"; fails=1; fi
[ $fails = 0 ] && echo "test-runonadapter: all scenarios pass" || { echo "test-runonadapter: FAILED"; exit 1; }
