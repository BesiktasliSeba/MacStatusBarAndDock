#!/bin/bash
# Mac test: the Charge Limit's hold on iPadOS 18 (1.8.6). Where powerd offers its own SOC-limit service (the A12Z on 18.5: its battery driver
# ignores powerd's ChargeInhibit) the hold is a policy there, removed at every let-go and at every start (it outlives the job: its token is kept);
# elsewhere the hold is as before. The job runs on a simulated iPad (chargejob-sim.h); plus the wiring: the entitlement and the job's calls.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -framework Foundation -o "$W/t" test-chargesoc.m
fails=0
for s in hold blip adapter off crash stop reset powerd powerdlost powerdslow retry resetslow stale startkept resetrun resetrunpmu m1; do
  echo "-- $s"
  rm -rf "$W/state" "$W/msbdcharge.log"
  "$W/t" $s || fails=1
done
M=../chargehelper/main.m
check() { if "${@:2}"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the job is entitled to powerd's SOC-limit service" grep -q 'com.apple.private.iokit.soc-limit' ../chargehelper/entitlements.plist
check "it asks powerd's own service (com.apple.iokit.powerdxpc, chargeSocLimit)" grep -q '"com.apple.iokit.powerdxpc"' "$M"
check "  ... the policy never drains the battery and never charges to full on its own" grep -q 'X.setBool(in, "chargeSocLimitDrain", false); X.setBool(in, "chargeSocLimitNoChargeToFull", true);' "$M"
check "  ... only a dictionary reply with returnCode 0 counts" grep -q 'X.type(r) != X.typeDict || X.getUInt(r, "returnCode") != 0' "$M"
check "the hold lets go of the policy (HoldOff), and so do --stop, SIGTERM and the idle end" bash -c "grep -A2 '^static void HoldOff(void) {' $M | grep -q SocHoldOff && grep -A4 '^static void LetGoForStop' $M | grep -q SocHoldOff && grep -A4 '^static void Terminate' $M | grep -q SocHoldOff && grep -q 'gPCIOn || gSocToken ||' $M"
check "every start and --reset removes the policies kept by an earlier run" bash -c "awk '/^static void ResetCharging/,/^}/' $M | grep -q 'SocRemoveKept(st, nil, 0)'"
check "the job does not end while a kept policy is left to remove" grep -q 'gPCIOn || gSocToken || gSocLeft ||' "$M"
[ $fails = 0 ] && echo "test-chargesoc: all scenarios pass" || { echo "test-chargesoc: FAILED"; exit 1; }
