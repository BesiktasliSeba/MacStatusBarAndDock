#!/bin/bash
# Mac test of the Dock's floor watch (dock/Dock.x DMDockFloorWatchStart, battery drain F5): the 0.5 s watcher that lowers a raised Dock when the
# status bar's tick does not run is not started while the screen is off, stops itself when the screen goes off (it used to keep firing twice a
# second all night), and the screen's return starts it again while the Dock is still raised.
set -e
cd "$(dirname "$0")"
D=../dock/Dock.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
F="awk '/^static void DMDockFloorWatchStart\\(void\\) \\{/,/^}/' $D"
check "not started with the screen off (nor twice)" "$F | grep -q 'if (gDockFloorWatch || DMDockScreenBlank()) return;'"
check "each tick: stopped when not needed any more or the screen is off (invalidated, not just skipped)" \
  "$F | grep -q 'if (!DMDockFloorWatchNeeded() || DMDockScreenBlank()) { \\[t invalidate\\]; gDockFloorWatch = nil; return; }'"
check "  ... no path keeps it alive with the screen off (the old early return is gone)" "! $F | grep -q 'if (blank) return;'"
check "the screen's return starts it again while the Dock is still raised (hasBlankedScreen, registered once)" \
  "$F | grep -q 'notify_register_dispatch(\"com.apple.springboard.hasBlankedScreen\", &gDockBlankToken' && $F | grep -q 'if (!DMDockScreenBlank() && DMDockFloorWatchNeeded()) DMDockFloorWatchStart();'"
check "needed = raised to the floor level and the tick quiet for 1.5 s (as before)" \
  "awk '/^static BOOL DMDockFloorWatchNeeded\\(void\\) \\{/,/^}/' $D | grep -q 'fabs(w.windowLevel - kDockMinWindowLevel) < 0.01 && CACurrentMediaTime() - gDockTickReassertAt >= 1.5;'"
[ $fails = 0 ] && echo "test-dockfloor: all checks pass" || { echo "test-dockfloor: checks FAILED"; exit 1; }
