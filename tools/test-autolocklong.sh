#!/bin/bash
# Mac test of the longer Auto-Lock times' SpringBoard side (macsettings/AutoLockLongest.h): test-autolocklong.m; and the wiring: the step's hook uses
# the tested rule, goes in only with Apple's method and the descriptor's setters as expected, and Settings offers the times only while it is in.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-autolocklong.m
"$W/t"
T=../macsettings/AutoLockTimer.x; L=../macsettings/AutoLock.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the hook decides with MSAutoLockKeepsTime, after SpringBoard's own step" \
  "awk '/^- \\(BOOL\\)updateIdleTimerSettingsForAutoLockTimeout:\\(id\\)desc \\{/{f=1} f' $T | awk '/%orig/{o=1} o && /MSAutoLockKeepsTime\\(t, total\\)/{print \"ok\"; exit}' | grep -q ok"
check "  ... and gives the warn interval back as it was before the step" \
  "grep -q 'double warnBefore = MSALTInterval(desc, @selector(warnInterval));' $T && grep -q 'setWarnInterval:), warnBefore);' $T"
check "it goes in only with the step's and the descriptor's methods as on 15-18 (encodings checked)" \
  "grep -q '\"B24@0:8@16\"' $T && grep -q 'setTotalInterval:\"), \"v24@0:8d16\"' $T && grep -q 'setWarnInterval:\"), \"v24@0:8d16\"' $T && grep -q 'if (!ok) { if (token) notify_set_state(token, 0); return; }' $T"
check "  ... and publishes this SpringBoard's pid once it is in" \
  "grep -q '%init(MSAutoLockTimer);' $T && grep -q 'notify_set_state(token, (uint64_t)getpid());' $T"
check "Settings adds 2 hours only while a running SpringBoard keeps it (30 min and 1 h: stock SpringBoard keeps them)" \
  "awk '/^static NSArray<NSNumber \\*> \\*MSLongTimes/{f=1} f && /return MSAutoLockLongTimesKept\\(\\) \\? kept : stock;/{print \"ok\"; exit}' $L | grep -q ok && grep -q 'stock = @\\[@1800, @3600\\];' $L"
check "the list's longest time is the one SpringBoard keeps (one constant)" \
  "grep -q 'kept = @\\[@1800, @3600, @((NSInteger)MS_AUTOLOCK_LONGEST)\\];' $L"
check "the step's hook is built into the Settings part SpringBoard loads (MacSettingsBadge)" \
  "grep -q '^MacSettingsBadge_FILES = Badge.x AutoLockTimer.x$' ../macsettings/Makefile"
[ $fails = 0 ] && echo "test-autolocklong: wiring checks pass" || { echo "test-autolocklong: WIRING FAILED"; exit 1; }
