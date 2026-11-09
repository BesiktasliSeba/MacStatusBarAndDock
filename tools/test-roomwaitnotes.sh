#!/bin/bash
# Mac test of the Stage Manager notes while the windows wait for the Dock's room (test-roomwaitnotes.m; 1.8.4.1 item 8): the code as built, cut out of statusbar/StatusBar.x, then the wiring.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
S=../statusbar/StatusBar.x
fn() { awk -v s="$2" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$1"; }
{ grep -F 'static NSMutableDictionary<NSString *, id> *gSMRoomWaitLayouts;' $S
  fn $S 'static NSDictionary<NSString *, NSString *> *DMSMRoomWaitMerged(NSDictionary<NSString *, NSString *> *notes) {'
  fn $S 'static void DMSMRoomWaitNote(NSDictionary<NSString *, NSValue *> *frames) {'
  fn $S 'static void DMSMRoomWaitLift(void) {'; } > "$W/roomwait-gen.h"
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -framework Foundation -framework CoreGraphics -o "$W/t" test-roomwaitnotes.m
fails=0; "$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
watch() { fn $S 'static void DMSMWatchTurn(void) {'; }
check "a note during the wait is kept apart, and nothing else is noted then" "fn $S 'static void DMSMTurnNote(void) {' | grep -qF 'if (DMDockRoomChangedSinceSave()) { DMSMRoomWaitNote(frames); return; }'"
check "a turn takes those with the notes, and ends the wait only after it has placed the windows" "watch | grep -qF '[DMSMRoomWaitMerged(DMSMTurnLayouts()) copy]' && watch | awk '/DMSMApplyPlacesMarkedIn\(allPlaces/{a=NR} /DMSMRoomWaitLift\(\);/{b=NR} END{exit !(a && b > a)}'"
check "the start's own step takes them too" "fn $S 'static void DMDockRoomAfterStartSMTry(int tries) {' | grep -qF 'DMSMRoomWaitMerged(DMSMTurnLayouts())' && fn $S 'static void DMDockRoomAfterStartSMTry(int tries) {' | grep -qF 'DMSMRoomWaitLift();'"
[ $fails = 0 ] && echo "test-roomwaitnotes: all pass" || { echo "test-roomwaitnotes: FAILED"; exit 1; }
