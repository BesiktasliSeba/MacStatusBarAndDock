#!/bin/bash
# Mac test of the orientation feed (statusbar/StatusBar.x DMOrientationFeedApply / DMOrientationFeedWant, battery drain F2): the accelerometer feed
# we ask UIKit for runs only while the screen is on. The real functions are taken out of StatusBar.x and run against a stand-in UIDevice that counts
# begins and ends (test-orientfeed.m): every screen and switch sequence keeps UIKit's count at 0 or 1, never below, and the feed is on exactly when
# wanted with the screen on. Wiring: nothing else in our code begins or ends the feed, the screen-off gate applies it on every change and at start.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
SB=../statusbar/StatusBar.x
awk '/^static BOOL gDMOrientFeedWanted = NO, gDMOrientFeedOn = NO;/,/^static void DMOrientationFeedWant\(BOOL want\)/' "$SB" > "$W/feed.inc"
[ -s "$W/feed.inc" ] || { echo "FAIL  the orientation feed functions are not in StatusBar.x"; exit 1; }
clang -O0 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -o "$W/tof" test-orientfeed.m && "$W/tof" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "nothing else in our SpringBoard code begins or ends UIDevice's orientation feed (only DMOrientationFeedApply)" \
  "[ \$(grep -h -E 'beginGeneratingDeviceOrientationNotifications|endGeneratingDeviceOrientationNotifications' ../statusbar/*.x ../statusbar/*.h | grep -v '^ *//' | wc -l | tr -d ' ') = 2 ]"
check "the screen-off gate applies the feed on every change (DMScreenPowerChanged)" \
  "awk '/^static void DMScreenPowerChanged\\(BOOL off\\) \\{/,/^}/' $SB | grep -q 'DMOrientationFeedApply();'"
check "  ... and once at start, after the screen's state is read (DMScreenPowerWatch)" \
  "awk '/^static void DMScreenPowerWatch\\(void\\) \\{/,/^}/' $SB | awk '/gDMScreenOff = st != 0;/{a=NR} /DMOrientationFeedApply\\(\\);/{b=NR} END{exit !(a && b > a)}'"
check "the full start and the stock-bar start ask through DMOrientationFeedWant (the debug kill switch kept)" \
  "grep -q 'if (!DMTestFlag(\"/tmp/msb-noorientnotes\")) DMOrientationFeedWant(YES);' $SB && grep -q 'if (!DMTestFlag(\"/tmp/msb-noorientnotes\")) DMOrientationFeedWant(YES);' ../statusbar/StockBar.h"
[ $fails = 0 ] && echo "test-orientfeed: all checks pass" || { echo "test-orientfeed: checks FAILED"; exit 1; }
