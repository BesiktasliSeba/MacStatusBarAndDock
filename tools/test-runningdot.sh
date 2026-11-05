#!/bin/bash
# Mac test of the Dock's running dot (KT, 1.7.8.1: "the calendar keeps launching in background and i see an open app indicator underneath"): a
# running app has the dot once its process has been on screen, or while the user has a window of it away (dock/RunningDotRule.h,
# test-runningdot.c) -- not when iPadOS started it in the background (prewarm, calaccessd's background launch). Then the wiring as built:
# SpringBoard's process state read only in its known shape, the rule applied to every running app, and what the dot had before kept.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/trd" test-runningdot.c && "$W/trd" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
R=../dock/RunningIndicator.m; S=../statusbar/StatusBar.x; L=../dock/RunningDotRule.h
fnr() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$R"; }
fns() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$S"; }
check "the rule is the header's (the Mac test runs the same code)" \
  "grep -q '^#include \"RunningDotRule.h\"' $R && grep -q '^static inline int MSBDDotSeenPid(int running, int pid, int onScreenNow, int seenPid) {' $L \
   && grep -q '^static inline int MSBDDotShown(int running, int stateKnown, int pid, int seenPid, int windowAway) {' $L"
check "SpringBoard's process state is read only in its known shape: -processState @16@0:8, -pid i16@0:8, -isForeground B16@0:8 (else every running app has the dot)" \
  "fnr 'static BOOL RIProcessState(id app, int *pid, int *foreground) {' | grep -q 'appOK = RIShape(ac, stateSel, \"@16@0:8\");' \
   && fnr 'static BOOL RIProcessState(id app, int *pid, int *foreground) {' | grep -q 'stateOK = RIShape(sc, pidSel, \"i16@0:8\") && RIShape(sc, fgSel, \"B16@0:8\");' \
   && fnr 'static BOOL RIProcessState(id app, int *pid, int *foreground) {' | grep -q 'if (!st) return NO;' \
   && fnr 'static BOOL RIShape(Class c, SEL s, const char \*enc) {' | grep -q 'return e && !strcmp(e, enc);'"
check "every running app goes through the rule: the seen pid remembered or forgotten, the dot only when the rule says so" \
  "fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'int seen = known ? MSBDDotSeenPid(1, pid, foreground, \[gRISeenPid\[bid\] intValue\]) : 0;' \
   && fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'if (seen) gRISeenPid\[bid\] = @(seen); else \[gRISeenPid removeObjectForKey:bid\];' \
   && fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'if (MSBDDotShown(1, known, pid, seen, \[away containsObject:bid\])) \[ids addObject:bid\];' \
   && ! fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'if (bid.length) \[ids addObject:bid\];'"
check "  ... an app no longer running is forgotten (a later process of it starts unseen)" \
  "fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'for (NSString \*b in gRISeenPid.allKeys) if (!\[live containsObject:b\]) \[gRISeenPid removeObjectForKey:b\];'"
check "kept as before: windows on screen (the Stage Manager restore set) and our own apps (Activity Monitor), running or not" \
  "fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'dlsym(RTLD_DEFAULT, \"MSBDAppsWithWindows\")' \
   && fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'if (shown.count) \[ids unionSet:shown\];' \
   && fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'dlsym(RTLD_DEFAULT, \"MSBDOwnAppsRunning\")' \
   && fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'if (own.count) \[ids unionSet:own\];'"
check "the windows away come from MacStatusBar (another desktop's records and full-screen app, the Stage Manager engine's minimized set, the other engines' minimized or hidden windows)" \
  "fnr 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' | grep -q 'withWindowsAway = (NSSet \*(\*)(void))dlsym(RTLD_DEFAULT, \"MSBDAppsWithWindowsAway\");' \
   && fns '__attribute__((visibility(\"default\"))) NSSet<NSString *> *MSBDAppsWithWindowsAway(void) {' | grep -q 'if (b.length && gMSWWinDesk\[k\].integerValue != cur && MSWRecordIsWindowHere(k, appsOnly)) \[out addObject:b\];' \
   && fns '__attribute__((visibility(\"default\"))) NSSet<NSString *> *MSBDAppsWithWindowsAway(void) {' | grep -q 'd.integerValue != cur) \[out addObject:b\];' \
   && fns '__attribute__((visibility(\"default\"))) NSSet<NSString *> *MSBDAppsWithWindowsAway(void) {' | grep -q 'if (DMSMEngine()) for (NSString \*k in DMSMMinimizedSet())' \
   && fns '__attribute__((visibility(\"default\"))) NSSet<NSString *> *MSBDAppsWithWindowsAway(void) {' | grep -q 'if (DMMSWMulti()) {' \
   && fns '__attribute__((visibility(\"default\"))) NSSet<NSString *> *MSBDAppsWithWindowsAway(void) {' | grep -q 'else for (UIView \*st in DMAerialStagesAll()) { if (!(DMStageMinimized(st) || st.hidden)) continue;'"
[ $fails = 0 ] && echo "test-runningdot: site checks pass" || { echo "test-runningdot: site checks FAILED"; exit 1; }
