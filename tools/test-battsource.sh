#!/bin/bash
# test-battsource.sh: where the battery menu, the battery's VoiceOver value and the number in the icon read the battery (issue #15, 1.8.7.6) --
# see test-battsource.m. Up to 1.8.7.5 they read SpringBoard's SBUIController, whose feed (UIKit's battery monitoring, one switch for the whole
# process) stops when code in SpringBoard switches it off: the menu said 43 % and "Power Source: Battery" while the bar said 47 % charging, until a
# respring. Now the battery service itself (CurrentCapacity, MaxCapacity, ExternalConnected, IsCharging, each with its type), looked up once more
# after a read that failed, then iPadOS's power sources, SBUIController last. The real code is cut out of statusbar/BatteryMenu.h (BS_MENU_H:
# another copy, e.g. the code before the change) with common/BatteryMenu.h, ChargeLimit.h, BatteryInside.h and AXText.h, and run on the Mac (Mac
# Catalyst) on stand-ins of the battery service, the power sources, SBUIController, the Charge Limit's job and UIKit's own battery view, one
# scenario per process, release and DEBUG; then site checks; then made-to-fail copies, each must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${BS_MENU_H:-../statusbar/BatteryMenu.h}; R0=crashmap-rules.txt
fnst() { awk -v n="$2(" 'index($0, "static ") == 1 && index($0, n) {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # a static function by its name

build() {   # $1 BatteryMenu.h, $2 dir, $3 quiet: the test built on that code, release (t) and DEBUG (td)
  local d=$2 fl
  mkdir -p "$d"; cp ../common/BatteryMenu.h ../common/ChargeLimit.h ../common/BatteryInside.h ../common/AXText.h "$d/"
  { fnst "$1" DMBattTypes; fnst "$1" DMBattTypesOf; } > "$d/bs-types.inc"
  # the battery's read: from its DMBattInfo to DMBattAXValue (the read, the level's text, the VoiceOver value)
  awk '/^typedef struct \{ int percent; BOOL onAC, charging, known; \} DMBattInfo;/ {f=1} f {print} f && /^static NSString \*DMBattAXValue\(void\) \{/ {g=1} g && /^[}]/ {exit}' "$1" > "$d/bs-read.inc"
  awk '/^\/\/ ---- the menu.s own rows ----/ {f=1} /^\/\/ ---- the menu ----$/ {exit} f {print}' "$1" > "$d/bs-rows.inc"
  fnst "$1" DMBattMenuItems > "$d/bs-items.inc"
  awk '/^static BOOL gBattInsideOn = NO;/ {f=1} f {print} f && /^static void DMBattInsideApplyPref\(BOOL on\) \{/ {g=1} g && /^[}]/ {exit}' "$1" > "$d/bs-block.inc"
  grep -q '^static DMBattInfo DMBattNow(void) {' "$d/bs-read.inc" && grep -q '^static NSString \*DMBattAXValue(void) {' "$d/bs-read.inc" && grep -q '@implementation DMBattHeaderRow' "$d/bs-rows.inc" \
    && grep -q 'DMBattInfo b = DMBattNow();' "$d/bs-items.inc" && grep -q 'cached = DMBattNow();' "$d/bs-block.inc" && [ -s "$d/bs-types.inc" ] || { echo "FAIL  the code was not found in $1"; return 99; }
  for fl in t td; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" $([ $fl = td ] && echo -DDEBUG=1) \
          -framework UIKit -framework QuartzCore -framework CoreGraphics -framework IOKit -o "$d/$fl" test-battsource.m 2> "$d/cc-$fl.txt" || { [ -n "$3" ] || cat "$d/cc-$fl.txt"; echo "FAIL  the real code did not build ($fl)"; return 99; }
    [ -s "$d/cc-$fl.txt" ] && [ -z "$3" ] && { echo "FAIL  warnings ($fl):"; cat "$d/cc-$fl.txt"; return 1; }
  done
  return 0
}

sites() {   # $1 BatteryMenu.h, $2 rules, $3 quiet: the number of site checks that fail
  local B=$1 R=$2 q=$3 n=0 o
  # read only: the battery service is read (IOKit, linked), never written
  if grep -q '^#import <IOKit/IOKitLib.h>' "$B" && grep -q '^MacStatusBarCore_FRAMEWORKS = .*IOKit' ../statusbar/Makefile && ! grep -q 'IORegistryEntrySetCFPropert\|IOConnect' "$B"; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: the battery service read through IOKit (linked), never written"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: no IOKit read of the battery service, or a write to it"; n=$((n + 1)); fi
  # the readers: the menu, the VoiceOver value and the number in the icon all through DMBattNow; SBUIController's state only in its last source
  # (DMBattSBUI) and the debug probe
  if fnst "$B" DMBattMenuItems | grep -q 'DMBattInfo b = DMBattNow();' && fnst "$B" DMBattAXValue | grep -q 'DMBattInfo b = DMBattNow();' && fnst "$B" DMBattInsideNow | grep -q 'cached = DMBattNow();' \
     && [ "$(grep -c 'NSSelectorFromString(@"batteryCapacityAsPercentage")' "$B")" = 1 ] && fnst "$B" DMBattSBUI | grep -q 'NSSelectorFromString(@"batteryCapacityAsPercentage")'; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: the menu, the VoiceOver value and the number in the icon read DMBattNow; SBUIController's level only in DMBattSBUI (its last source)"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: a reader of the battery not through DMBattNow, or SBUIController's level read elsewhere"; n=$((n + 1)); fi
  # the menu's refresh paths as they were: opened, its 3 s refresh, the power sources' note; the number's: the note, every 5 s at most
  if fnst "$B" DMOpenBatteryMenu | grep -q 'scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer \*t) { if (!gBattPanel) { \[t invalidate\]; if (gBattTimer == t) gBattTimer = nil; return; } DMBattMenuChanged(); }' \
     && fnst "$B" DMBattApplyPref | grep -qF 'notify_register_dispatch("com.apple.system.powersources", &t, dispatch_get_main_queue(), ^(int tok) { DMBattMenuChanged(); });' \
     && fnst "$B" DMBattInsideApplyPref | grep -qF 'notify_register_dispatch("com.apple.system.powersources", &t, dispatch_get_main_queue(), ^(int tok) { DMBattInsidePowerChanged(); });' \
     && fnst "$B" DMBattInsideNow | grep -qF 'if (now - gBattInsideReadAt > 5.0) { cached = DMBattNow(); gBattInsideReadAt = now; }'; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: the refresh paths as they were (the open menu's 3 s refresh and the power sources' note; the number's note and 5 s read)"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: a refresh path changed"; n=$((n + 1)); fi
  # UIDevice battery monitoring (another tweak's switch, one for the whole process) is left alone outside the debug triggers: only the test's
  # trigger battmenu_monitor_<0|1> switches it, to reproduce the issue
  o=$(awk '/^\/\/ ---- debug triggers/ {d=1} /\.batteryMonitoringEnabled|setBatteryMonitoringEnabled/ && !d {print NR}' "$B")
  if [ -z "$o" ] && awk '/^\/\/ ---- debug triggers/ {d=1} d' "$B" | grep -qF '[UIDevice currentDevice].batteryMonitoringEnabled = on;' \
     && awk '/^#if DEBUG$/ {d=1} /^#endif$/ {d=0} /^static BOOL DMBattTrigger\(NSString \*cmd\) \{/ {print d; exit}' "$B" | grep -qx 1; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: UIDevice battery monitoring switched only by the debug trigger battmenu_monitor_<0|1> (DEBUG builds)"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: UIDevice battery monitoring switched outside the debug triggers (lines: ${o:-none}), or no trigger"; n=$((n + 1)); fi
  # the crash map: the read's functions are Battery Menu's (its switch is turned off after a crash in them)
  o=$(python3 -I - "$R" <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'bs'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
for name in ['_DMBattService', '_DMBattServiceForget', '_DMBattProp', '_DMBattReadKey', '_DMBattServiceRead', '_DMBattSBUI', '_DMBattPowerSources',
             '_DMBattNow', '_DMBattFromSaid', '_DMBattSBUIApart', '_DMBattAXValue']:
    print(g['classify']('MacStatusBarCore', name, 'BatteryMenu.h', '', rules, im, hits), end=' ')
EOF
)
  if [ "$o" = "batteryMenu batteryMenu batteryMenu batteryMenu batteryMenu batteryMenu batteryMenu batteryMenu batteryMenu batteryMenu batteryMenu " ]; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: the battery's read is Battery Menu's (classified with make-crashmap.py's own code)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the read's functions classify as: $o"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 BatteryMenu.h, $2 rules, $3 dir, $4 quiet: the number of checks that fail
  local q=$4 n=0 s fl out r
  build "$1" "$3" "$q"; r=$?; [ $r = 99 ] && return 99; n=$r
  for fl in t td; do
    for s in $("$3/$fl" list); do
      [ -n "$q" ] || echo "-- $([ $fl = t ] && echo release || echo DEBUG): $s"
      out=$("$3/$fl" "$s" 2>/dev/null); r=$?
      [ -n "$q" ] || echo "$out"
      [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; }
      n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
    done
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$2" "$q"; n=$((n + $?)); [ $n -ge 99 ] && n=98
  return $n
}

run "$M0" "$R0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-battsource: all pass" || echo "test-battsource: FAILED ($rc check(s))"
if [ -z "$BS_MENU_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression (the whole of BatteryMenu.h at once)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/BatteryMenu.h"
    perl -0777 -pe "$2" "$M0" > "$c"
    cmp -s "$c" "$M0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$R0" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "SBUIController first again (its stopped feed shown: issue #15)" 's/(static DMBattInfo DMBattNow\(void\) \{\n    DMBattInfo b = \{ -1, NO, NO, NO \};\n)/$1    b = DMBattSBUI(); if (b.known) return b;\n/'
  mtf "the cable taken for the adapter (Power Adapter during the job's cut on a PMU iPad)" 's/DMBattReadKey\(s, \@"ExternalConnected", YES, &ext\)/DMBattReadKey(s, \@"AppleRawExternalConnected", YES, &ext)/'
  mtf "charging taken from the adapter (Charging during the job's hold)" 's/DMBattReadKey\(s, \@"IsCharging", YES, &chg\)/DMBattReadKey(s, \@"ExternalConnected", YES, &chg)/'
  mtf "no second lookup after a read that failed" 's/\n        DMBattServiceForget\(\);[^\n]*//'
  mtf "SBUIController before iPadOS's power sources" 's/b = DMBattPowerSources\(\); from = kDMBattFromPowerSources;\n            if \(!b\.known\) \{ b = DMBattSBUI\(\); from = b\.known \? kDMBattFromSBUI : kDMBattFromNone; \}/b = DMBattSBUI(); from = kDMBattFromSBUI;\n            if (!b.known) { b = DMBattPowerSources(); from = b.known ? kDMBattFromPowerSources : kDMBattFromNone; }/'
  mtf "a key taken whatever its type" 's/    if \(!v \|\| t != CFNumberGetTypeID\(\) \|\| !CFNumberGetValue\(\(__bridge CFNumberRef\)v, kCFNumberLongLongType, &n\)\) return NO;/    if (![v respondsToSelector:\@selector(longLongValue)]) return NO;\n    n = [v longLongValue];/'
  mtf "MaxCapacity not used" 's/int p = max > 0 && max != 100 \? \(int\)MIN\(100L, lround\(100\.0 \* cur \/ max\)\) : cur;/int p = cur;/'
  mtf "a scaled level over 100 not kept at 100" 's/\(int\)MIN\(100L, lround\(100\.0 \* cur \/ max\)\)/(int)lround(100.0 * cur \/ max)/'
  mtf "the power sources' level over the service's (80 where the bar says 79)" 's/(\n    gBattFrom = from;\n)/\n    if (from == kDMBattFromService && DMBattPowerSources().known) b.percent = DMBattPowerSources().percent;$1/'
  mtf "the service's lookup logged at each look (the debug log)" 's/if \(found != told\) \{ told = found;/if (1) { told = found;/'
  mtf "(debug) SBUIController apart: said every time" 's/    if \(told \|\| now - apartSince <= 60\.0\) return;/    if (now - apartSince <= 60.0) return;/'
  mtf "(debug) SBUIController apart: said at once" 's/now - apartSince <= 60\.0\) return;/now - apartSince < 0) return;/'
  mtf "(debug) SBUIController apart: not said again after they agreed" 's/\{ apartSince = 0; told = NO; return; \}/{ apartSince = 0; return; }/'
fi
exit $rc
