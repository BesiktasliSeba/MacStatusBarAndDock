#!/bin/bash
# Mac test of common/Relaunch.h (test-relaunch.m, built four ways): the request our Respring sends where SpringBoard may not start sbreload is
# sbreload's own, and nothing is sent where this iPadOS lacks a part of it. And wiring checks on statusbar/StatusBar.x: sbreload stays first, the
# request only after its spawn failed, the old fallback (gone since iPadOS 17) not called any more (1.7.4 item 6).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
for v in "1 1 1" "1 0 1" "1 1 0" "0 0 0"; do
  set -- $v
  clang -O2 -fobjc-arc -Wall -Wno-unused-function -DWITH_CLASSES=$1 -DWITH_ACTION=$2 -DWITH_SEND=$3 -framework Foundation -o "$W/trl$1$2$3" test-relaunch.m
  "$W/trl$1$2$3" || fails=1
done
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
DMR="awk '/^static void DMRespring\\(void\\) \\{/,/^}/' ../statusbar/StatusBar.x"
check "DMRespring: the relaunch request first on every iPadOS (one start; sbreload's own stop 2 s on restarted SpringBoard a second time on 16-18, 1.8.4.3), sbreload only where there is no request" \
  "$DMR | awk '/posix_spawn\\(/{s=NR} /MSBDRelaunchLikeSbreload\\(\\)/{r=NR} END{exit !(s && r && r < s)}'"
check "DMRespring: a sent request returns before sbreload (never both)" \
  "$DMR | grep -q 'if (MSBDRelaunchLikeSbreload()) {.*return; }'"
check "the old fallback -_relaunchSpringBoardNow (gone since iPadOS 17) is not called from SpringBoard's Respring any more" \
  "! $DMR | grep -q '_relaunchSpringBoardNow'"
check "the request path carries a release feature marker" \
  "$DMR | grep -q 'DM_FEATURE_MARK(\"respring-relaunch-action\")'"
exit $fails
