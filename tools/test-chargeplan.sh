#!/bin/bash
# Mac test: the Charge Limit's job (1.8.6): one job at a time (an unknown argument refused, a second job ends without touching anything) and a
# charge setting changed in Settings planned again at once (Run on Power Adapter off above the limit comes down without waiting out the cut's
# 30 minutes). 1.8.8.1 BATTWHY: why iPad is not charging on the adapter, published with the state (KT's 7 W A12Z, a PMU brick, the job's own
# hold, another process's hold, full; can't pause charging kept after full). The job runs on a simulated iPad (chargejob-sim.h); plus the wiring.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$W/state\"" -DkLogFile="\"$W/msbdcharge.log\"" \
  -framework Foundation -o "$W/t" test-chargeplan.m
fails=0
for s in args help second roaoff roaon roaoffsoc weak weakpmu weakours otherhold holdend holdendsoc holdendpmu holdendweak spike full cantholdfull; do
  echo "-- $s"
  rm -rf "$W/state" "$W/msbdcharge.log"
  "$W/t" $s || fails=1
done
M=../chargehelper/main.m
check() { if "${@:2}"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the job's lock is an exclusive, non-blocking flock on a file in its state folder, kept for its life" bash -c "grep -q 'flock(f, LOCK_EX | LOCK_NB)' $M && grep -q 'kStateDir \"/chargelimit.lock\"' $M"
check "  ... taken before ResetCharging, the job's first lever (and by --reset before its own)" bash -c "awk '/^int main\\(/,0' $M | grep -E 'if \\(!JobLockTake\\(\\)\\)|ResetCharging\\(nil, NO, NO\\)' | head -1 | grep -q 'JobLockTake' && awk '/^int main\\(/,0' $M | grep -E 'jobRuns = !JobLockTake\\(\\)|ResetCharging\\(@\"--reset\"' | head -1 | grep -q 'JobLockTake'"
check "an unknown argument: usage, exit 2" grep -q 'return help ? 0 : 2;' "$M"
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$M"; }   # one function of main.m, from its first line to its closing brace
why() {   # (1.8.8.1) the reason by the tested rule only, from the look's reading, published with the state; its own hold and cut never get one
  local e='static void Evaluate(NSString *why) {'
  fn "$e" | grep -qF 'int whyNot = MSBDBattWhyDecide(wi);' && fn "$e" | grep -qF 'Publish(MSBDChargeStateWord(st, holdAt, plugged) | MSBDChargeWhyBits(whyNot, wi.watts));' &&
  fn "$e" | grep -qF 'MSBDBattWhyOurs(&gWhyClock, now, st == kMSBDChargeStateOnHold || st == kMSBDChargeStateComingDown);' &&
  fn "$e" | grep -qF 'MSBDBattWhyIn wi = WhyIn(b, onAdapterNow);' && fn "$e" | grep -qF 'MSBDBattWhyTimes(&gWhyClock, now, &wi);' &&
  fn "$e" | grep -qF 'MSBDBattWhyTick(&gWhyClock, now, onAdapterNow && wi.charging == 0 && !MSBDBattWhyCharging(wi), wi.ampKnown ? wi.amp <= MSBD_WHY_DRAIN_MA : -1);' &&
  fn "$e" | awk '/MSBDBattWhyOurs\(/{a=NR} /MSBDBattWhyTick\(/{b=NR} /MSBDBattWhyTimes\(/{c=NR} /MSBDBattWhyDecide\(wi\)/{d=NR} END{exit !(a && b > a && c > b && d > c)}' &&
  fn "$e" | grep -qF 'int onAdapterNow = plugged && !ourCut && !CutShown(b);' && [ "$(grep -c 'MSBDBattWhyDecide(' "$M")" = 1 ] &&
  [ "$(grep -c 'Publish(MSBDChargeStateWord(' "$M")" = 1 ] && fn 'int main(' | grep -qF 'MSBDBattWhyName(MSBDChargeWordWhy(w))'
}
check "why iPad is not charging: decided by common/ChargeWhy.h from the look's own reading and its clock (the job's hold ending, how long), published with the state (the one state publish), said by --status" why
check "no em dash in the reason's files" bash -c "! grep -q \$'\\xe2\\x80\\x94' ../common/ChargeWhy.h test-chargeplan.m"
[ $fails = 0 ] && echo "test-chargeplan: all scenarios pass" || { echo "test-chargeplan: FAILED"; exit 1; }
