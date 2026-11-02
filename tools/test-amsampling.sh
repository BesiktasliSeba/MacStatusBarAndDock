#!/bin/bash
# Mac test of when Activity Monitor samples (statusbar/ActivityMonitor.h, battery drain F3): its 2 s refresh (a sweep of every process) runs only
# while its window can be seen -- in a window, not minimized, the screen on. The shared screen-off gate parks it; a minimized window stops it and
# its return starts it; the first reading after a pause takes no %CPU averaged over the pause.
set -e
cd "$(dirname "$0")"
A=../statusbar/ActivityMonitor.h; SB=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
ST="awk '/^- \\(void\\)dm_start \\{/,/^}/' $A"
check "dm_start: no timer for a window that is minimized (hidden) or not in a window" \
  "$ST | grep -q 'if (_timer || self.hidden || !self.window) return;'"
check "  ... the first reading only with the screen on" "$ST | grep -q 'if (!gDMScreenOff) \\[self dm_sample\\];'"
check "  ... each tick samples only with the screen on and the window on the screen" \
  "$ST | grep -q 'if (!gDMScreenOff && \\[ws dm_onScreen\\]) \\[ws dm_sample\\];'"
check "  ... the timer is put under the screen-off gate (DMGateTimer), after it is added to the run loop" \
  "$ST | awk '/addTimer:_timer/{a=NR} /DMGateTimer\\(_timer\\);/{b=NR} END{exit !(a && b > a)}'"
check "minimizing (setHidden: YES) stops the timer, showing again starts it" \
  "awk '/^- \\(void\\)setHidden:\\(BOOL\\)hidden \\{/,/^}/' $A | grep -q 'if (hidden && !was) \\[self dm_stop\\];' && awk '/^- \\(void\\)setHidden:\\(BOOL\\)hidden \\{/,/^}/' $A | grep -q 'else if (!hidden && was) \\[self dm_start\\];'"
check "a reading after a pause of more than 6 s on the clock that runs asleep: no %CPU from before it, a fresh pair asked for" \
  "grep -q 'uint64_t cont = clock_gettime_nsec_np(CLOCK_MONOTONIC);' $A && grep -q 'BOOL paused = _lastCont && cont - _lastCont > 6000000000ULL;' $A && grep -q 'if (paused) { wallNs = 0; _secondSoon = YES; }' $A"
check "the gate (DMGateTimer, gDMScreenOff) is defined in StatusBar.x before ActivityMonitor.h is included" \
  "awk '/^static void DMGateTimer\\(NSTimer \\*t\\) \\{/{a=NR} /#include \"ActivityMonitor.h\"/{b=NR} END{exit !(a && b > a)}' $SB"
[ $fails = 0 ] && echo "test-amsampling: all checks pass" || { echo "test-amsampling: checks FAILED"; exit 1; }
