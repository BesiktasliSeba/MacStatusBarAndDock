#!/bin/bash
# test-flickquitapp.sh: Swipe Up to Quit with the Stage Manager engine quits the flicked window's app, every window of it (1.8.7.3, audit M8 of
# 1.8.7.2) -- see test-flickquitapp.m. The real DMMSWFlickQuit and DMMSWForgetApp (statusbar/MacSwitcher.h), DMForceQuitBundle and
# DMSMForceQuitWindows (statusbar/StatusBar.x) are cut out of the sources (FQ_MSW_H / FQ_SB_X: other copies, e.g. the code before the fix) and run
# on the Mac (Mac Catalyst); then a site check on StatusBar.x; then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${FQ_MSW_H:-../statusbar/MacSwitcher.h}; X0=${FQ_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

FQ_FL='__attribute__((noinline)) static void DMMSWFlickQuit(DMMSWTile *t, NSString *how) {'
FQ_FA='static void DMMSWForgetApp(NSString *b) {'
FQ_FB='static void DMForceQuitBundle(NSString *bundleID) {'
FQ_SW='static double DMSMForceQuitWindows(NSString *bundleID, BOOL *windowed) {'

run() {   # $1 MacSwitcher.h, $2 StatusBar.x, $3 work dir, $4 quiet; the number of failed checks
  local M=$1 X=$2 d=$3 q=$4 n=0 h out
  mkdir -p "$d"
  for h in "$FQ_FA" "$FQ_FL"; do [ -n "$(fn "$M" "$h")" ] || { echo "FAIL  $M: no function starting \"$h\""; return 99; }; done
  for h in "$FQ_SW" "$FQ_FB"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  { fn "$M" "$FQ_FA"; fn "$X" "$FQ_SW"; fn "$X" "$FQ_FB"; fn "$M" "$FQ_FL"; } > "$d/fq-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-flickquitapp.m || { echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (the site check) DMForceQuitBundle reads a window's key with SMWindowKey.h's DMSMKeyBundle: the header comes in before it (it came in only with
  # SMFitPlan.h, some 600 lines further down)
  local i f
  i=$(grep -n '^#include "SMWindowKey.h"' "$X" | head -1 | cut -d: -f1); f=$(grep -nF "$FQ_FB" "$X" | head -1 | cut -d: -f1)
  if [ -n "$i" ] && [ -n "$f" ] && [ "$i" -lt "$f" ]; then [ -n "$q" ] || echo "PASS  StatusBar.x has SMWindowKey.h before DMForceQuitBundle (it builds)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: SMWindowKey.h is not included before DMForceQuitBundle"; n=$((n + 1)); fi
  return $n
}

run "$M0" "$X0" "$W/real"; rc=$?
if [ -z "$FQ_MSW_H$FQ_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (msw|sbx), $3 perl expression
    local d="$W/m$((++k))" M=$M0 X=$X0 c
    mkdir -p "$d"
    if [ "$2" = msw ]; then c="$d/MacSwitcher.h"; perl -pe "$3" "$M0" > "$c"; M=$c; cmp -s "$c" "$M0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    else c="$d/StatusBar.x"; perl -pe "$3" "$X0" > "$c"; X=$c; cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }; fi
    run "$M" "$X" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the flick hands Force Quit the thumbnail's own name (the window's key) again" msw 's/NSString \*b = DMSMKeyBundle\(t\.bundle\);/NSString *b = [t.bundle copy];/'
  mtf "the app's other thumbnails matched by their key again" msw 's/\[DMSMKeyBundle\(o\.bundle\) isEqualToString:b\]/[o.bundle isEqualToString:b]/'
  mtf "Force Quit takes a key as it comes again" sbx '$_ = "" if /^    bundleID = DMSMKeyBundle\(bundleID\);/'
  mtf "SMWindowKey.h only further down again" sbx '$_ = "" if /^#include "SMWindowKey.h"/'
fi
exit $rc
