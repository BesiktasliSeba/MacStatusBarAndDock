#!/bin/bash
# test-switcherquit.sh: an app quit with iPadOS's own App Switcher forgets its Mac Switcher desktop records, so its desktop does not open it again
# (1.8.7.3, audit M9 of 1.8.7.2), and MilkyWay4's window of it on another desktop closes with the quit (the review of that fix) -- see
# test-switcherquit.m. The real DMPrewarmQuitAdd and DMPrewarmQuitAddFromKill (statusbar/StatusBar.x), DMMSWFitWithout, DMMSWForgetApp,
# DMMSWMWAppGone, DMMSWMWCloseGone, DMMSWMWCloseQuitAway (when the file has it: the code before the fix has none), DMMSWRelaunchAt,
# DMMSWRelaunchClosed and DMMSWApply (statusbar/MacSwitcher.h) are cut out of the sources (SQ_MSW_H / SQ_SB_X: other copies, e.g. the code before
# the fix) and run on the Mac (Mac Catalyst); then a site check on StatusBar.x (both of FrontBoard's kill methods pass the hook); then made-to-fail
# copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${SQ_MSW_H:-../statusbar/MacSwitcher.h}; X0=${SQ_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

SQ_MSW=('static NSDictionary *DMMSWFitWithout(NSDictionary *fit, NSString *b) {' 'static void DMMSWForgetApp(NSString *b) {'
        'static BOOL DMMSWMWAppGone(UIView *st, NSString *b, NSSet **running) {' 'static void DMMSWMWCloseGone(UIView *st) {'
        'static void DMMSWRelaunchAt(NSString *b, BOOL afterMWClose) {' 'static void DMMSWRelaunchClosed(void) {' 'static void DMMSWApply(void) {')
SQ_MSW_NEW='static void DMMSWMWCloseQuitAway(NSString *b) {'   # (cut out when there; after DMMSWMWCloseGone)
SQ_SBX=('static void DMPrewarmQuitAdd(NSString *bundleID) {' 'static void DMPrewarmQuitAddFromKill(id process, long long reason) {')

run() {   # $1 MacSwitcher.h, $2 StatusBar.x, $3 work dir, $4 quiet; the number of failed checks
  local M=$1 X=$2 d=$3 q=$4 n=0 h out
  mkdir -p "$d"
  for h in "${SQ_MSW[@]}"; do [ -n "$(fn "$M" "$h")" ] || { echo "FAIL  $M: no function starting \"$h\""; return 99; }; done
  for h in "${SQ_SBX[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  { for h in "${SQ_MSW[@]}"; do fn "$M" "$h"; [ "$h" = 'static void DMMSWMWCloseGone(UIView *st) {' ] && fn "$M" "$SQ_MSW_NEW"; done
    for h in "${SQ_SBX[@]}"; do fn "$X" "$h"; done; } > "$d/sq-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-switcherquit.m || { echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (the site check) both of FrontBoard's kill methods hand every kill to the hook before the kill itself
  local c
  c=$(awk '/^static void DMPrewarmQuitAddFromKill\(/{s=1} s && /^%hook FBApplicationProcess$/{f=1; next} f && /^%end/{exit} f && /^- \(void\)killForReason:/{m=1; next} m && /^    DMPrewarmQuitAddFromKill\(self, reason\);$/{k++; m=0} m && /%orig/{m=0}
           END{print k+0}' "$X")
  if [ "$c" = 2 ]; then [ -n "$q" ] || echo "PASS  StatusBar.x: both of FBApplicationProcess's kill methods pass the hook before %orig"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: $c of FBApplicationProcess's 2 kill methods pass the hook before %orig"; n=$((n + 1)); fi
  return $n
}

run "$M0" "$X0" "$W/real"; rc=$?
if [ -z "$SQ_MSW_H$SQ_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (msw|sbx), $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" M=$M0 X=$X0 c
    mkdir -p "$d"
    if [ "$2" = msw ]; then c="$d/MacSwitcher.h"; perl -0777 -pe "$3" "$M0" > "$c"; M=$c; cmp -s "$c" "$M0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    else c="$d/StatusBar.x"; perl -0777 -pe "$3" "$X0" > "$c"; X=$c; cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }; fi
    run "$M" "$X" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the kill hook feeds the prewarm quit set only again" sbx 's/\^\{ DMPrewarmQuitAdd\(bid\); DMMSWForgetApp\(bid\); dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMMSWMWCloseQuitAway\(bid\); \}\); \}/^{ DMPrewarmQuitAdd(bid); }/'
  mtf "the forget inside DMPrewarmQuitAdd, after its early return for an app already on the set" sbx \
      's/\^\{ DMPrewarmQuitAdd\(bid\); DMMSWForgetApp\(bid\); /^{ DMPrewarmQuitAdd(bid); /; s/(\n    DMPrewarmQuitPublish\(\);\n\}\nstatic void DMPrewarmQuitClear)/\n    DMPrewarmQuitPublish(); DMMSWForgetApp(bundleID);\n}\nstatic void DMPrewarmQuitClear/'
  mtf "the quit leaves MilkyWay4's away window to the dead-window check again (as the M9 fix did)" sbx 's/ dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMMSWMWCloseQuitAway\(bid\); \}\);//'
  mtf "MilkyWay's close run inside FrontBoard's kill" sbx 's/dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMMSWMWCloseQuitAway\(bid\); \}\);/DMMSWMWCloseQuitAway(bid);/'
  mtf "a window already closing (our Force Quit's) closed again" msw 's/ \|\| \[objc_getAssociatedObject\(st, kStageClosingKey\) boolValue\]\) continue;\n        DMLog\(\[NSString stringWithFormat:\@"\[macswitcher\] %\@ quit: its MilkyWay/) continue;\n        DMLog([NSString stringWithFormat:\@"[macswitcher] %\@ quit: its MilkyWay/'
  mtf "the window on the desktop on screen closed by the quit too" msw 's/isEqualToString:b\] \|\| !\[objc_getAssociatedObject\(st, kMSWAwayKey\) boolValue\] \|\| \[objc_getAssociatedObject\(st, kStageClosingKey\)/isEqualToString:b] || [objc_getAssociatedObject(st, kStageClosingKey)/'
  mtf "the forget on FrontBoard's queue (not the main thread)" sbx 's/    else dispatch_async\(dispatch_get_main_queue\(\), quit\);/    else quit();/'
  mtf "a kill for any reason taken for the user's quit" sbx 's/(static void DMPrewarmQuitAddFromKill\(id process, long long reason\) \{\n)    if \(reason != 1\) return;/$1    if (reason < 0) return;/'
  mtf "one kill method no longer passes the hook" sbx 's/(withDescription:\(id\)desc \{\n)    DMPrewarmQuitAddFromKill\(self, reason\);\n/$1/'
fi
exit $rc
