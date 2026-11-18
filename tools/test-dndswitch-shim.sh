#!/bin/bash
# test-dndswitch-shim.sh: the guard for another tweak's Do Not Disturb listener (common/DndSwitchShim.h, 1.8.7.8, GitHub #14 crash 4; a WORKAROUND).
# A class named DndSwitch (NSObject <SwitchProtocol>) adds itself to DNDStateService as a state listener without the listener's method: an update
# during its read was an unrecognized selector on Do Not Disturb's call-out queue, and SpringBoard aborted. test-dndswitch-shim.m runs the real
# header (SHIM_H: another copy) with stand-ins, one process per scenario: before (the exception), after (none; the method is added to DndSwitch
# alone, with the listener's types, once), own (a DndSwitch with the method keeps its own), inherited (its superclass's answers: nothing added),
# noclass, notadopted (no SwitchProtocol on the class), noprotocol (none in the process): nothing added. Then site checks on StatusBar.x (called
# once from the constructor, handed to the main queue, after the off switch's return and before Stock mode's; no dyld image callback), no hook,
# and the crash map's rule (it runs with either bar style: the part). Then made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H0=${SHIM_H:-../common/DndSwitchShim.h}
X0=../statusbar/StatusBar.x
SCEN="before after own inherited noclass notadopted noprotocol"

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0 c
  c=$(awk '/^%ctor \{/ {f=1} f {print} f && /^\}/ {exit}' "$X")
  if [ "$(grep -c '^#include "../common/DndSwitchShim.h"' "$X")" = 1 ] && [ "$(grep -c 'MSBDDndSwitchShim()' "$X")" = 1 ] \
     && echo "$c" | grep -qF '    if (!DMCtorSkip("dndswitch")) dispatch_async(dispatch_get_main_queue(), ^{ MSBDDndShimResult r = MSBDDndSwitchShim(); DMLog('; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the guard runs once, from the constructor, handed to the main queue (SpringBoard's libraries all loaded by then)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the guard is not called once from the constructor through the main queue"; n=$((n + 1)); fi
  local off shim stock
  off=$(echo "$c" | grep -n '^        if (!enabled) {' | head -1 | cut -d: -f1); shim=$(echo "$c" | grep -n 'MSBDDndSwitchShim()' | head -1 | cut -d: -f1)
  stock=$(echo "$c" | grep -n '^    if (gStockBar) {' | head -1 | cut -d: -f1)
  if [ -n "$off" ] && [ -n "$shim" ] && [ -n "$stock" ] && [ "$off" -lt "$shim" ] && [ "$shim" -lt "$stock" ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: after the off switch's return (fully off: nothing runs), before Stock mode's (either bar style)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the guard's place in the constructor ($off < $shim < $stock)"; n=$((n + 1)); fi
  if ! grep -q '_dyld_register_func_for_add_image' "$H0" && ! echo "$c" | grep 'MSBDDndSwitchShim()' | grep -q dyld; then
    [ -n "$q" ] || echo "PASS  no dyld image callback: the guard never runs inside dyld's loading"
  else [ -n "$q" ] || echo "FAIL  a dyld image callback runs the guard"; n=$((n + 1)); fi
  if ! grep -qE '%hook|MSHookMessageEx|class_replaceMethod|method_setImplementation|method_exchangeImplementations' "$H0" && ! grep -q 'DndSwitch' ../common/HookList.h; then
    [ -n "$q" ] || echo "PASS  no hook: only class_addMethod, nothing in common/HookList.h"
  else [ -n "$q" ] || echo "FAIL  the guard hooks or replaces a method"; n=$((n + 1)); fi
  if grep -qx 'file MacStatusBarCore ^DndSwitchShim\\.h$ part' crashmap-rules.txt; then
    [ -n "$q" ] || echo "PASS  crash map: DndSwitchShim.h is the part's (it runs with either bar style: Stock mode would not stop it)"
  else [ -n "$q" ] || echo "FAIL  crash map: no rule for DndSwitchShim.h"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 DndSwitchShim.h, $2 StatusBar.x, $3 work dir, $4 quiet: the number of failed checks (99: the code could not be built)
  local H=$1 X=$2 d=$3 q=$4 n=0 s sc
  mkdir -p "$d/inc"; cp "$H" "$d/inc/DndSwitchShim.h"
  clang -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d/inc" -framework Foundation -o "$d/t" test-dndswitch-shim.m 2>"$d/cc.txt" \
    || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; n=$((n + 1)); }
  for sc in $SCEN; do
    [ -n "$q" ] || echo "-- $sc"
    if [ -n "$q" ]; then "$d/t" $sc >/dev/null 2>&1; else "$d/t" $sc; fi; s=$?
    [ $s = 0 ] || [ -n "$q" ] || echo "     ($sc: $s failed)"
    n=$((n + s))
  done
  [ -n "$q" ] || echo "-- site checks"
  H0=$H sites "$X" "$q"; s=$?
  return $((n + s))
}

run "$H0" "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-dndswitch-shim: all pass" || echo "test-dndswitch-shim: FAILED ($rc)"
if [ -z "$SHIM_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression, $3 h (DndSwitchShim.h) or x (StatusBar.x)
    local d="$W/m$((++k))" h="$H0" x="$X0" c
    mkdir -p "$d"
    if [ "$3" = x ]; then c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"; x=$c; else c="$d/DndSwitchShim.h"; perl -0pe "$2" "$H0" > "$c"; h=$c; fi
    cmp -s "$c" "$([ "$3" = x ] && echo "$X0" || echo "$H0")" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$h" "$x" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "nothing added (the guard stops before class_addMethod)" 's/    if \(class_respondsToSelector\(c, sel\)\) return MSBDDndShimHasIt;\n/    return MSBDDndShimHasIt;\n/' h
  mtf "a method replaced (class_replaceMethod: their own one goes)" 's/class_addMethod\(c, sel, \(IMP\)MSBDDndSwitchUpdateIgnored, "v32\@0:8\@16\@24"\) \?/(class_replaceMethod(c, sel, (IMP)MSBDDndSwitchUpdateIgnored, "v32\@0:8\@16\@24"), YES) ?/; s/    if \(class_respondsToSelector\(c, sel\)\) return MSBDDndShimHasIt;\n//' h
  mtf "an inherited method shadowed (no respondsToSelector: check)" 's/    if \(class_respondsToSelector\(c, sel\)\) return MSBDDndShimHasIt;\n//' h
  mtf "a DndSwitch without SwitchProtocol given the method (no conformance check)" 's/    if \(!class_conformsToProtocol\(c, p\)\) return MSBDDndShimNotAdopted;\n//' h
  mtf "a missing SwitchProtocol not checked" 's/    if \(!p\) return MSBDDndShimNoProtocol;\n//' h
  mtf "another selector added" 's/sel_registerName\("stateService:didReceiveDoNotDisturbStateUpdate:"\)/sel_registerName("stateService:didReceiveDoNotDisturbStateUpdates:")/' h
  mtf "the wrong types" 's/"v32\@0:8\@16\@24"\) \?/"v\@:\@") ?/' h
  mtf "any class taken (the name not checked)" 's/objc_getClass\("DndSwitch"\)/objc_getClass("OtherSwitch") ?: objc_getClass("DndSwitch")/' h
  mtf "run from the constructor itself, not through the main queue" 's/if \(!DMCtorSkip\("dndswitch"\)\) dispatch_async\(dispatch_get_main_queue\(\), \^\{ (MSBDDndShimResult r = MSBDDndSwitchShim\(\); DMLog\([^\n]*\)); \}\);/if (!DMCtorSkip("dndswitch")) { $1; }/' x
  mtf "only with the Mac status bar (after Stock mode's return)" 's/(\n    \/\/ Another tweak[^\n]*\n(?:    \/\/[^\n]*\n)*    if \(!DMCtorSkip\("dndswitch"\)\)[^\n]*)(\n(?:.*\n)*?    if \(gStockBar\) \{[^\n]*)/$2$1/' x
fi
exit $rc
