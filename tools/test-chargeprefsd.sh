#!/bin/bash
# test-chargeprefsd.sh: the Charge Limit's job follows the settings after cfprefsd starts over (1.8.7.4, audit M2 of 1.8.7.2) -- see
# test-chargeprefsd.m. The job (chargehelper/main.m; CPD_MAIN: another copy, e.g. the code before the fix) runs on a simulated iPad
# (chargejob-sim.h), one scenario per process; then site checks (every read of mobile's settings in the job goes through one reader; the job
# alone follows cfprefsd's restarts; the real cfprefsd look run on this Mac); then made-to-fail copies: each breaks one part and must fail.
# Review of the fix: a cfprefsd that only appears is no restart (agent); one the job's read starts is noted after it (agentread, agentnolist);
# none listed before the first read counts the copy as old (boot, bootrestart, nolist); the switches' line is checked both ways (gate).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${CPD_MAIN:-../chargehelper/main.m}
COMMON=$(cd ../common && pwd)
SCEN="off change adapter comedown silent silentfirst down later hang hangfirst gate unchanged boot bootrestart nolist duringfirst agent agentread agentnolist"
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

build() {   # $1 main.m, $2 dir: the test built on that copy of the job
  local d=$2
  mkdir -p "$d/tools" "$d/chargehelper" && cp chargejob-sim.h test-chargeprefsd.m "$d/tools/" && cp "$1" "$d/chargehelper/main.m" && ln -s "$COMMON" "$d/common" || return 1
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-deprecated-declarations -DDEBUG=0 -DkStateDir="\"$d/state\"" -DkLogFile="\"$d/msbdcharge.log\"" \
        -framework Foundation -o "$d/t" "$d/tools/test-chargeprefsd.m" 2>"$d/cc.txt" || { cat "$d/cc.txt"; return 1; }
}
FAILED=""
run() {   # $1 dir, $2 quiet: the scenarios that fail, in FAILED
  local d=$1 q=$2 s
  FAILED=""
  for s in $SCEN; do
    rm -rf "$d/state" "$d/msbdcharge.log"
    if [ -n "$q" ]; then "$d/t" $s >/dev/null 2>&1 || FAILED="$FAILED $s"
    else echo "-- $s"; "$d/t" $s || FAILED="$FAILED $s"; fi
  done
}

fails=0
build "$M0" "$W/real" || { echo "FAIL  the job did not build"; echo "test-chargeprefsd: FAILED"; exit 1; }
run "$W/real"
n=$(echo $SCEN | wc -w | tr -d ' '); f=$(echo $FAILED | wc -w | tr -d ' ')
if [ -n "$FAILED" ]; then echo "FAIL  $f of $n scenarios fail:$FAILED"; fails=1; else echo "PASS  all $n scenarios"; fi
[ -n "$CPD_MAIN" ] && { [ $fails = 0 ] && echo "test-chargeprefsd: all pass ($M0)" || echo "test-chargeprefsd: FAILED ($M0)"; exit $fails; }

# ---- site checks on the job as it is
M=../chargehelper/main.m
check() { if "${@:2}"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
HERE='static ChargeSettings SettingsHere(BOOL gate) {'
oneReader() {   # mobile's settings are read in one place (SettingsHere), which only SettingsRead and the --settings line call
  local inside total calls
  inside=$(fn "$M" "$HERE" | grep -c 'CFPreferencesCopyValue(')
  total=$(grep -c 'CFPreferencesCopyValue(' "$M")
  calls=$(grep -n 'SettingsHere(' "$M" | grep -v -F "$HERE")
  [ "$inside" -ge 4 ] && [ "$inside" = "$total" ] && [ "$(echo "$calls" | wc -l | tr -d ' ')" = 3 ] &&
  [ "$(fn "$M" 'static ChargeSettings SettingsRead(BOOL gate) {' | grep -c 'SettingsHere(gate)')" = 2 ] &&
  awk '/strcmp\(argv\[1\], "--settings"\)/ {f=1} f && /ChargeSettings s = SettingsHere\(YES\);/ {ok=1} f && /return 0;/ {exit} END {exit !ok}' "$M"
}
throughRead() {   # the job's looks, its idle end and the gate fallback read through SettingsRead (once per look)
  [ "$(fn "$M" 'static void Evaluate(NSString *why) {' | grep -c 'SettingsRead(')" = 1 ] &&
  fn "$M" 'static BOOL ChargeWanted(void) {' | grep -qF 'ChargeSettings s = SettingsRead(NO);' &&
  fn "$M" 'static BOOL TweakMeantToRun(void) {' | grep -qF 'return SettingsRead(YES).meantToRun;'
}
jobOnly() {   # only the job follows cfprefsd's restarts: marked after it took the job lock, before its first read
  awk '/^int main\(/ {m=1} m && /if \(!JobLockTake\(\)\) \{/ && !l {l=NR} m && /^        gIsJob = YES;/ {j=NR; c++} m && /ResetCharging\(nil, NO, NO\);/ && !r {r=NR}
       END {exit !(l && j > l && r > j && c == 1)}' "$M" && [ "$(grep -c 'gIsJob = YES' "$M")" = 1 ]
}
realLook() {   # the real look at cfprefsd (not the simulator's) run on this Mac: every cfprefsd as pid@start/uid, the same twice
  awk '/^#ifndef MSBD_CHARGE_PREFSD_SIM/ {f=1; next} f && /^#else/ {exit} f {print}' "$M" > "$W/sig.inc"
  grep -q 'static NSString \*PrefsDaemonSignature(void) {' "$W/sig.inc" || return 1
  printf '#import <Foundation/Foundation.h>\n#include <sys/sysctl.h>\n#include "sig.inc"\nint main(void) { @autoreleasepool { NSString *a = PrefsDaemonSignature(), *b = PrefsDaemonSignature(); printf("%%s\\n%%s\\n", a.UTF8String ?: "(nil)", b.UTF8String ?: "(nil)"); } return 0; }\n' > "$W/sig.m"
  clang -fobjc-arc -Wall -framework Foundation -I"$W" -o "$W/sig" "$W/sig.m" 2>"$W/sigcc.txt" || { cat "$W/sigcc.txt"; return 1; }
  local out; out=$("$W/sig")
  echo "      (this Mac: $(echo "$out" | head -1 | tr ',' '\n' | grep -c @) cfprefsd processes)"
  [ "$(echo "$out" | sed -n 1p)" = "$(echo "$out" | sed -n 2p)" ] && echo "$out" | head -1 | grep -Eq '^[0-9]+@[0-9]+/[0-9]+(,[0-9]+@[0-9]+/[0-9]+)*$'
}
check "mobile's settings are read in one place (SettingsHere), called only by SettingsRead and msbdcharge --settings" oneReader
check "the job's looks (once each), its idle end and the tweak's switches read through SettingsRead" throughRead
check "only the job follows cfprefsd's restarts (marked after the job lock, before its first read; the commands are fresh processes)" jobOnly
check "the real look at cfprefsd lists this Mac's cfprefsd processes as pid@start/uid, the same twice" realLook

# ---- made-to-fail copies: each must fail at least one scenario
mutate() {   # $1 name, $2 python replacement (old, new); the copy built and run: it must fail
  local d="$W/m-$1"
  mkdir -p "$d"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); o=sys.argv[3].encode().decode("unicode_escape"); n=sys.argv[4].encode().decode("unicode_escape")
if s.count(o) != 1: sys.exit(3)
open(sys.argv[2], "w").write(s.replace(o, n))' "$M" "$d/main.m" "$2" "$3" || { echo "FAIL  made-to-fail copy $1: its line is not in main.m once"; fails=1; return; }
  build "$d/main.m" "$d/b" >/dev/null || { echo "FAIL  made-to-fail copy $1 did not build"; fails=1; return; }
  run "$d/b" quiet
  if [ -n "$FAILED" ]; then echo "PASS  made-to-fail copy caught: $1 (fails:$FAILED)"; else echo "FAIL  made-to-fail copy not caught: $1"; fails=1; fi
}
mutate never-notices '    if (gPrefsCopyOld || !gIsJob) return gPrefsCopyOld;' '    return NO;'
mutate notices-reads-own-copy '        if (!PrefsGoneAfterRead()) return here;' '        PrefsGoneAfterRead(); return here;'
mutate appearing-is-a-restart '    if (now && [gPrefsDaemons isSubsetOfSet:running])' '    if (now && [gPrefsDaemons isEqualToSet:running])'
mutate appearing-never-noted '{ [gPrefsDaemons unionSet:running]; return NO; }' '{ return NO; }'
mutate no-list-after-read-ignored '    if (now && [gPrefsDaemons isSubsetOfSet:running])' '    if (!now || [gPrefsDaemons isSubsetOfSet:running])'
mutate none-before-first-read-noted-later '    if (before.length) gPrefsDaemons = [PrefsDaemonSet(before) mutableCopy];\n    else PrefsCopyIsOld(' '    gPrefsDaemons = [PrefsDaemonSet(before) mutableCopy];\n    if (0) PrefsCopyIsOld('
mutate first-read-not-listed-before '    if (before.length) gPrefsDaemons = [PrefsDaemonSet(before) mutableCopy];' '    if (before.length) gPrefsDaemons = [NSMutableSet set];'
mutate fresh-line-tweak-off 'ChargeSettings s = SettingsHere(YES);\n            printf("msbdcharge-settings' 'ChargeSettings s = SettingsHere(NO);\n            printf("msbdcharge-settings'
mutate look-on-own-copy '    ChargeSettings cs = SettingsRead(NO);   // (once per look' '    ChargeSettings cs = SettingsHere(NO);   // (once per look'
mutate idle-end-on-own-copy '    ChargeSettings s = SettingsRead(NO);\n    return MSBDChargeLimitOn' '    ChargeSettings s = SettingsHere(NO);\n    return MSBDChargeLimitOn'
mutate gate-on-own-copy '    return SettingsRead(YES).meantToRun;' '    return SettingsHere(YES).meantToRun;'
mutate failure-to-old-copy '    return gFreshGot ? gFresh : SettingsHere(gate);' '    return SettingsHere(gate);'
mutate fresh-line-mixed-up 's.comeDown ? 1 : 0, s.runOnAdapter ? 1 : 0' 's.runOnAdapter ? 1 : 0, s.comeDown ? 1 : 0'
mutate hung-process-waited-for '    for (int i = 0; i < 500 && !ended; i++) {' '    for (int i = 0; !ended; i++) {'
mutate job-not-marked '        gIsJob = YES;' '        (void)0;'

[ $fails = 0 ] && echo "test-chargeprefsd: all pass" || { echo "test-chargeprefsd: FAILED"; exit 1; }
