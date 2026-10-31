#!/bin/bash
# Mac test of the scene monitor guard's owner cleanup (common/MonitorGuard.h, 1.7.3 item 11): test-monitorguard.m with stand-ins for Zetsu's window
# controller, FrontBoard's scene monitor and a scene's layer manager; the KVO crash itself reproduced (and prevented) in a child process.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-monitorguard.m
"$W/t"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
check "the guard: the owner's cleanup (its own layer manager and the monitored scene's) runs before FrontBoard's invalidate, both before -dealloc" \
  "awk '/^%hook FBSceneMonitor/{f=1} f&&/removed = MSBDMonitorOwnerCleanup\\(\\(id\\)self, \"_manager\", sceneLayers, kMSBDMonitorOwnerKeyPath, &owner\\);/{a=NR} f&&/performSelector:@selector\\(invalidate\\)\\]/{b=NR} f&&/^    %orig;/{c=NR; print (a&&b&&a<b&&b<c) ? \"ok\" : \"no\"; exit}' $S | grep -q ok"
check "Zetsu: a closed window's launch retry stops (its close marks the controller, -setHost: returns), installed only for a tested build with both methods of the types read" \
  "grep -q 'objc_setAssociatedObject(self, kZetsuCtlClosedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' $S && grep -q 'if (\\[objc_getAssociatedObject(self, kZetsuCtlClosedKey) boolValue\\]) {' $S && grep -q 'strcmp(ce, \"v20@0:8B16\") || strcmp(he, \"v20@0:8f16\")' $S && grep -q '    if (!DMZetsuInstalled()) return;   // (an untested Zetsu build runs on its own)' $S && grep -q '        DMZetsuStopClosedRetry();' $S"
[ $fails = 0 ] && echo "test-monitorguard: site checks pass" || { echo "test-monitorguard: site checks FAILED"; exit 1; }
