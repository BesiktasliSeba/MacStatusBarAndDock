#!/bin/bash
# Mac test of sshtoggled's watch on Choicy's settings file (macsettings/sshtoggled/main.m WatchChoicyFile, battery drain F7): with no such file it
# looks again only twice (5 s, 60 s: ChoicyRetry.h, test-choicyretry.c); the preferences folder's own watch arms the file's watch when the file
# comes; a watch already armed is not armed twice.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -o "$W/tcr" test-choicyretry.c && "$W/tcr" || fails=1
M=../macsettings/sshtoggled/main.m
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
WC="awk '/^static void WatchChoicyFile\\(void\\) \\{/,/^}/' $M"
check "no file: the next look is MSBDChoicyRetryDelay's (no fixed 5 s retry any more)" \
  "$WC | grep -q 'double wait = MSBDChoicyRetryDelay(++gChoicyRetries);' && ! grep -q '5 \\* NSEC_PER_SEC), dispatch_get_main_queue(), ^{ WatchChoicyFile(); }' $M"
check "  ... no retry scheduled when the delay is 0" \
  "$WC | grep -q 'if (wait > 0) dispatch_after('"
check "  ... the count starts again once the file is watched" \
  "$WC | grep -q 'if (gChoicyFileSrc) { gChoicyRetries = 0; return; }'"
check "  ... a watch already armed (not cancelled) is not armed again" \
  "$WC | awk 'NR==2' | grep -q 'if (gChoicyFileSrc && !dispatch_source_testcancel(gChoicyFileSrc)) return;'"
check "the preferences folder's watch arms the file's watch on every folder event" \
  "grep -q 'prefsDir = WatchPath(PREFSDIR, DISPATCH_VNODE_WRITE, @\"the preferences folder\", nil, ^{ WatchChoicyFile(); });' $M"
check "WatchPath runs the event block before its own work" \
  "awk '/^static dispatch_source_t WatchPath\\(/,/^}/' $M | awk '/if \\(onEvent\\) onEvent\\(\\);/{a=NR} /EvaluateMacStatusBarConfig\\(name\\);/{b=NR} END{exit !(a && b > a)}'"
[ $fails = 0 ] && echo "test-choicyretry: all checks pass" || { echo "test-choicyretry: checks FAILED"; exit 1; }
