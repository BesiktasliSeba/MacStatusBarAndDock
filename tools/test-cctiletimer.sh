#!/bin/bash
# Mac test of the RAM & CPU tile's 1 s refresh (ccmodule/MSBDRAMCPUModule.m, battery drain F6): it runs only while the tile or its panel is on the
# screen. Control Center's appearance calls start and stop it; where a host never sends them (a Control Center kept hidden: BigSurCenter keeps
# iPadOS's own), 3 ticks in a row off the screen stop it, and the screen going off stops every tile at once. Showing again starts it.
set -e
cd "$(dirname "$0")"
C=../ccmodule/MSBDRAMCPUModule.m
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
T="awk '/^- \\(void\\)tick \\{/,/^}/' $C"
check "a tick off the screen (or with the screen off) samples nothing" "$T | grep -q 'if (!MSBDViewShows(self.view) || MSBDScreenBlank()) {'"
check "  ... the third such tick in a row, or the screen off, stops the timer" "$T | grep -q 'if (++_unshownTicks >= 3 || MSBDScreenBlank()) \\[self stopUpdating\\];'"
check "  ... a tick on the screen counts again from 0" "$T | grep -q '_unshownTicks = 0;'"
S="awk '/^- \\(void\\)startUpdating \\{/,/^}/' $C"
check "starting: the count from 0, the tile watched for the screen going off" "$S | grep -q '_unshownTicks = 0;' && $S | grep -q 'MSBDWatchScreen(self);'"
check "the screen going off stops every tile updating (once registered, weak list)" \
  "awk '/^static void MSBDWatchScreen\\(id tile\\) \\{/,/^}/' $C | grep -q 'if (!MSBDScreenBlank()) return;' && awk '/^static void MSBDWatchScreen\\(id tile\\) \\{/,/^}/' $C | grep -q 'NSSelectorFromString(@\"stopUpdating\")'"
check "shown again without an appearance call (a host's own panel laid out on the screen): started" \
  "awk '/^- \\(void\\)viewDidLayoutSubviews \\{/,/^}/' $C | grep -q 'if (!_timer && MSBDViewShows(self.view) && !MSBDScreenBlank()) \\[self startUpdating\\];'"
check "the panel opening starts it too" "grep -q 'if (expanded) { \\[self sample\\]; \\[self refreshLabels\\]; \\[self startUpdating\\]; }' $C"
check "Control Center's own calls still start and stop it" \
  "grep -q '^- (void)controlCenterWillPresent { \\[self startUpdating\\]; }' $C && grep -q '^- (void)controlCenterDidDismiss { \\[self stopUpdating\\]; }' $C && grep -q 'viewDidDisappear:animated\\]; \\[self stopUpdating\\];' $C"
[ $fails = 0 ] && echo "test-cctiletimer: all checks pass" || { echo "test-cctiletimer: checks FAILED"; exit 1; }
