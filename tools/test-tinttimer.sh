#!/bin/bash
# Mac test of MacAppBridge's title-bar tint refresh (appbridge/AppBridge.x MABStartTintReports, battery drain F4): the 4 s timer runs only while
# the app is active (MABPublishTint does nothing otherwise) -- started on becoming active (or at once if active already), stopped on resigning
# active and on entering the background; it never ran for ever in apps kept running in the background or behind a locked screen again.
set -e
cd "$(dirname "$0")"
B=../appbridge/AppBridge.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
F="awk '/^static void MABStartTintReports\\(void\\) \\{/,/^}/' $B"
check "the 4 s timer is made only inside start(), once (no timer made outside it)" \
  "$F | awk '/void \\(\\^start\\)\\(void\\) = \\^\\{/{s=NR} /if \\(t\\) return;/{g=NR} /timerWithTimeInterval:4.0/{t=NR; n++} /^        \\};/&&s&&!e{e=NR} END{exit !(s && g > s && t > g && e > t && n == 1)}'"
check "started on becoming active" "$F | grep -q 'addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:mq usingBlock:^(NSNotification \\*n) { start(); }'"
check "  ... or at once when the app is active already" "$F | grep -q 'if (\\[UIApplication sharedApplication\\].applicationState == UIApplicationStateActive) start();'"
check "stopped on resigning active (a locked screen, another window in front)" "$F | grep -q 'addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:mq usingBlock:^(NSNotification \\*n) { stop(); }'"
check "  ... and on entering the background" "$F | grep -q 'addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:mq usingBlock:^(NSNotification \\*n) { stop(); }'"
check "stop() invalidates and forgets the timer" "$F | grep -q 'void (^stop)(void) = ^{ \\[t invalidate\\]; t = nil; };'"
check "the publish still asks for the active state itself" "awk '/^static void MABPublishTint\\(void\\) \\{/,/^}/' $B | grep -q 'app.applicationState != UIApplicationStateActive) return;'"
[ $fails = 0 ] && echo "test-tinttimer: all checks pass" || { echo "test-tinttimer: checks FAILED"; exit 1; }
