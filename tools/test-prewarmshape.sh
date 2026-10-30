#!/bin/bash
# Mac test of the prewarm block's method-shape check (prewarmblock/PrewarmShape.h, test-prewarmshape.m): only an object return with one object
# argument is ever hooked (1.5.1 logic test C1). And wiring checks: the debug build's log list is changed and read only under its lock; no
# switch read from notifyd on dasd's queues (the quit set's file decides, 1.7.1).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tps" test-prewarmshape.m
"$W/tps"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the debug log's list is changed and joined only under its lock (dasd asks from two queues at once: it aborted on 18.5, 29 Oct)" \
  "awk '/^static void DebugWrite/,/^}/' ../prewarmblock/PrewarmBlock.x | awk '/os_unfair_lock_lock\\(&gDebugLock\\)/{l=1} l && /addObject:/{a=1} a && /componentsJoinedByString:/{j=1} j && /os_unfair_lock_unlock\\(&gDebugLock\\)/{print \"ok\"; exit}' | grep -q ok"
check "no switch is read from notifyd on dasd's queues: the quit set's file decides (1.7.1); the one notification is registered by the constructor" \
  "! grep -n 'notify_get_state\\|notify_register_check' ../prewarmblock/PrewarmBlock.x && [ \"\$(grep -c 'notify_register' ../prewarmblock/PrewarmBlock.x)\" = 1 ] && awk '/^%ctor/,/^}/' ../prewarmblock/PrewarmBlock.x | grep -q 'notify_register_dispatch(kPrewarmChanged'"
exit $fails
