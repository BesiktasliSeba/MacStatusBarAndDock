#!/bin/bash
# Mac test of Activity Monitor's in-place refresh (statusbar/ActivityMonitor.h, -dm_rebuildRowsInPlace:), as built. 1.7.7 RC, A12Z 18.5: opened
# from the App Library's search over a Finder window, the window's quick second reading put the new rows in the data source BEFORE
# -performBatchUpdates:; the list, whose rows were not up to date (its first layout still to come), read the data source again as the updates
# began, found the new count, and the added rows counted twice: "invalid batch updates", SpringBoard aborted (Safe Mode). Now the work UIKit
# holds for the list is done (the window laid out) and the list counted while the data source still gives the old rows; only a list that then
# counts exactly them gets rows added or taken off, and the new rows go into the data source inside the updates, as UIKit asks; anything else
# is reloaded.
set -e
cd "$(dirname "$0")"
A=../statusbar/ActivityMonitor.h
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$A"; }
F='- (void)dm_rebuildRowsInPlace:(BOOL)inPlace {'
check "in place: the window laid out and the list counted before the new rows go in anywhere" \
  "fn '$F' | awk '/\\[self layoutIfNeeded\\];/{a=NR} /settled = \\[_list numberOfRowsInSection:0\\] == had;/{b=NR} /_rows = rows;/&&!c{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... only for a list in a window (no window: a reload)" \
  "fn '$F' | grep -q 'if (inPlace && _list.window) {'"
check "  ... not settled: the new rows, then a reload" \
  "fn '$F' | grep -q 'if (!settled) { _rows = rows; \\[_list reloadData\\]; }'"
check "  ... settled with rows to add or take off: the new rows go into the data source inside the updates, before the rows are added or taken off" \
  "fn '$F' | awk '/\\[_list performBatchUpdates:\\^\\{/{a=NR} a&&/_rows = rows;/&&!b{b=NR} /insertRowsAtIndexPaths:ends/{c=NR} /deleteRowsAtIndexPaths:ends/{d=NR} END{exit !(a && b > a && c > b && d > b)}'"
check "  ... the list is never counted after the new rows are in to decide on a batch (the rule that crashed)" \
  "! fn '$F' | grep -q '\\[_list numberOfRowsInSection:0\\] != had'"
check "the one batch update in the file outside debug code is the settled in-place one" \
  "[ \$(awk '/^#if DEBUG/{d=1} /^#endif/{d=0} !d && /performBatchUpdates:\\^/' $A | wc -l | tr -d ' ') = 1 ]"
check "the readings come in through the in-place rebuild (the 2 s refresh and the quick second reading)" \
  "grep -q '    \\[self dm_rebuildRowsInPlace:YES\\];' $A && grep -q '_secondSoon = YES;' $A"
[ $fails = 0 ] && echo "test-actmonrefresh: all checks pass" || { echo "test-actmonrefresh: checks FAILED"; exit 1; }
