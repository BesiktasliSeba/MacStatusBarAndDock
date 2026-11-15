#!/bin/bash
# test-chargelapse.sh: a hold that works is never given up for one lapse, and a give-up remembered for an adapter tries again by itself (1.8.7.5,
# GitHub issue #13: Run on Power Adapter, and Charge Limit with it, stopped working until switched off and on) -- see test-chargelapse.m. The job
# (chargehelper/main.m with common/ChargeLimit.h; CL_MAIN / CL_H: other copies, e.g. the code before the fix) runs on a simulated iPad
# (chargejob-sim.h), one scenario per process; then made-to-fail copies: each breaks one part of the fix and must fail a scenario.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${CL_MAIN:-../chargehelper/main.m}; H0=${CL_H:-../common/ChargeLimit.h}
COMMON=$(cd ../common && pwd)
SCEN="slowtake-blip lapse-sleep lapse-pmu lapse-soc lapse-slowretake lapse-gauge raised-then-asleep lapses-bound replug-remembers limit-blip remembered-takes remembered-restart remembered-below remembered-fails remembered-full status ignored-asleep retried-asleep lapse-nightly remembered-top remembered-near-top full-then-drift"

build() {   # $1 main.m, $2 ChargeLimit.h, $3 dir: the test built on those copies of the job (the other common headers as they are)
  local d=$3 f
  mkdir -p "$d/tools" "$d/chargehelper" "$d/common" && cp chargejob-sim.h test-chargelapse.m "$d/tools/" && cp "$1" "$d/chargehelper/main.m" || return 1
  for f in "$COMMON"/*; do ln -s "$f" "$d/common/"; done
  rm "$d/common/ChargeLimit.h" && cp "$2" "$d/common/ChargeLimit.h" || return 1
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$d/state\"" -DkLogFile="\"$d/msbdcharge.log\"" \
        -framework Foundation -o "$d/t" "$d/tools/test-chargelapse.m" 2>"$d/cc.txt" || { cat "$d/cc.txt"; return 1; }
}
FAILED=""
run() {   # $1 dir, $2 quiet: the scenarios that fail, in FAILED
  local d=$1 q=$2 s
  FAILED=""
  for s in $SCEN; do
    rm -rf "$d/state" "$d/msbdcharge.log" "$d/msbdcharge.log.status"
    if [ $s = remembered-restart ]; then   # (two processes, as a job started again is: the state file kept between them)
      if [ -n "$q" ]; then { "$d/t" $s-first && "$d/t" $s-next; } >/dev/null 2>&1 || FAILED="$FAILED $s"
      else echo "-- $s"; { "$d/t" $s-first && "$d/t" $s-next; } || FAILED="$FAILED $s"; fi
    elif [ -n "$q" ]; then "$d/t" $s >/dev/null 2>&1 || FAILED="$FAILED $s"
    else echo "-- $s"; "$d/t" $s || FAILED="$FAILED $s"; fi
  done
}

fails=0
build "$M0" "$H0" "$W/real" || { echo "FAIL  the job did not build"; echo "test-chargelapse: FAILED"; exit 1; }
run "$W/real"
n=$(echo $SCEN | wc -w | tr -d ' '); f=$(echo $FAILED | wc -w | tr -d ' ')
if [ -n "$FAILED" ]; then echo "FAIL  $f of $n scenarios fail:$FAILED"; fails=1; else echo "PASS  all $n scenarios"; fi
[ -n "$CL_MAIN$CL_H" ] && { [ $fails = 0 ] && echo "test-chargelapse: all pass ($M0, $H0)" || echo "test-chargelapse: FAILED ($M0, $H0)"; exit $fails; }

# ---- made-to-fail copies: each must fail at least one scenario
mutate() {   # $1 name, $2 main.m or ChargeLimit.h, then (old, new) pairs: each old text once in the file; the copy built and run: it must fail
  local name=$1 which=$2 d="$W/m-$1"; shift 2
  mkdir -p "$d"
  local src=../chargehelper/main.m; [ "$which" = ChargeLimit.h ] && src=../common/ChargeLimit.h
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); a=sys.argv[3:]
for i in range(0, len(a), 2):
    o=a[i].encode().decode("unicode_escape"); n=a[i+1].encode().decode("unicode_escape")
    if s.count(o) != 1: sys.exit(3)
    s=s.replace(o, n)
open(sys.argv[2], "w").write(s)' "$src" "$d/$which" "$@" || { echo "FAIL  made-to-fail copy $name: its text is not in $which once"; fails=1; return; }
  local m=../chargehelper/main.m h=../common/ChargeLimit.h
  if [ "$which" = ChargeLimit.h ]; then h="$d/$which"; else m="$d/$which"; fi
  build "$m" "$h" "$d/b" >/dev/null || { echo "FAIL  made-to-fail copy $name did not build"; fails=1; return; }
  run "$d/b" quiet
  if [ -n "$FAILED" ]; then echo "PASS  made-to-fail copy caught: $name (fails:$FAILED)"; else echo "FAIL  made-to-fail copy not caught: $name"; fails=1; fi
}
mutate stage1-level-shortcut ChargeLimit.h '    if (!chargingIn) return kMSBDLeverFine;\n    if (!raisedAgain)' '    if (!chargingIn) return kMSBDLeverFine;\n    if (chargingIn > 0 && risenBy >= 3) return kMSBDLeverIgnored;\n    if (!raisedAgain)'
mutate level-from-hold-start main.m '        if (!gLeverUp[k]) gLeverUp[k] = now;' '        if (!gLeverUp[k]) { gLeverUp[k] = now; gLeverSoc[k] = soc; }' \
  'else if (!gLeverIn[k]) { gLeverIn[k] = now; gLeverSoc[k] = soc; }' 'else if (!gLeverIn[k]) gLeverIn[k] = now;'
mutate raised-again-kept-after-take main.m '        if (!chargeIn) gLeverIn[k] = gLeverAgain[k] = 0;' '        if (!chargeIn) gLeverIn[k] = 0;'
mutate no-gap-rule main.m '        if (gLeverLook[k] > 0 && now - gLeverLook[k] > MSBD_CHARGE_LEVER_GAP' '        if (0 && gLeverLook[k] > 0 && now - gLeverLook[k] > MSBD_CHARGE_LEVER_GAP'
mutate no-raise-bound ChargeLimit.h 'raises >= MSBD_CHARGE_LEVER_RAISES ? kMSBDLeverIgnored : kMSBDLeverRaiseAgain' 'kMSBDLeverRaiseAgain'
mutate raises-kept-across-plug-ins main.m 'if (!plugged) { gHoldTook = gHoldRetried = NO; memset(gLeverRaiseAt, 0, sizeof gLeverRaiseAt); }' 'if (!plugged) { gHoldTook = gHoldRetried = NO; }'
mutate remembered-after-it-took main.m 'BOOL remember = !k && chargeIn > 0 && !gHoldTook;' 'BOOL remember = !k && chargeIn > 0;'
mutate took-kept-across-plug-ins main.m 'if (!plugged) { gHoldTook = gHoldRetried = NO;' 'if (!plugged) { gHoldRetried = NO;'
mutate remembered-skipped-as-before main.m '        gHoldRetried = YES;\n        Log(@"the hold did not take with this adapter' '        gHoldIgnored = YES;\n        Log(@"the hold did not take with this adapter'
mutate retry-not-passed main.m 'now - gLeverUp[0] < 120)), gHoldRetried,' 'now - gLeverUp[0] < 120)), 0,'
mutate retry-cuts ChargeLimit.h 'in.holdRetried = 0; in.cutIgnored = 1;' 'in.holdRetried = 0;'
mutate retry-kept-awake ChargeLimit.h 'MSBDChargeOut r = MSBDChargeDecide(in); r.keepAwake = 0;' 'MSBDChargeOut r = MSBDChargeDecide(in);'
mutate check-not-kept-awake main.m '        gPrev == kMSBDChargeHold && chargeIn != 0 };' '        0 };'
mutate check-awake-dropped ChargeLimit.h 'if (r.action == kMSBDChargeHold) r.keepAwake = 1; return r;' 'return r;'
mutate raises-for-the-plug-in ChargeLimit.h 'now - at[i] < MSBD_CHARGE_LEVER_WINDOW' '1'
mutate trial-at-the-top ChargeLimit.h 'if (r.action == kMSBDChargeHold && in.soc >= 95 &&' 'if (0 &&'
mutate trial-top-cuts-its-check ChargeLimit.h '!(in.prev == kMSBDChargeHold && in.holdOnTrial)' '1'
mutate takes-when-full ChargeLimit.h 'return chargingIn == 0 && upFor >= 120 && !full && soc >= 0 && soc < 95;' 'return chargingIn == 0 && upFor >= 120;'

[ $fails = 0 ] && echo "test-chargelapse: all pass" || { echo "test-chargelapse: FAILED"; exit 1; }
