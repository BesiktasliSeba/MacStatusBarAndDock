#!/bin/bash
# test-mswhold.sh: the hold that opens the Mac Switcher from a swipe up (statusbar/MSWHoldRule.h) -- see test-mswhold.c. Then the wiring of
# Reduce Motion's end at a pause (1.7.9, statusbar/MacSwitcher.h): SpringBoard may end a swipe with the fingers still down only while they rest.
cd "$(dirname "$0")" || exit 1
OUT="${TMPDIR:-/tmp}/test-mswhold.$$"
clang -std=c11 -O1 -Wall -Werror -o "$OUT" test-mswhold.c -lm || exit 1
"$OUT"; rc=$?
rm -f "$OUT"
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; rc=1; fi; }
M=../statusbar/MacSwitcher.h
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$M"; }
check "Reduce Motion's move handling, its final destination and its dip are hooked only in their known shape (else SpringBoard's own pause)" \
  "fn 'static void DMMSWHookGestures(void) {' | grep -q 'if (o_MSWActivateRM && DMMSWHasMethod(rm, @\"_updateForGestureDidChangeWithEvent:\", @\"@@:@\") && fdi && ivar_getTypeEncoding(fdi)\[0\] == .@.' \
   && fn 'static void DMMSWHookGestures(void) {' | grep -q '&& DMMSWHasMethod(fdc, @\"currentFinalDestination\", @\"q@:\") && DMMSWHasMethod(fdc, @\"hasSeenAccelerationDipForAppSwitcher\", @\"B@:\")) {'"
check "the check runs only inside that move handling, for the watched fingers, and ends with it (even when it throws)" \
  "fn 'static id DMMSWRMChange(id self, SEL _cmd, id event) {' | grep -q 'if (gMSWRMFD || !gMSWRestGesture || !gMSWHold.on) return o_MSWRMChange(self, _cmd, event);' \
   && fn 'static id DMMSWRMChange(id self, SEL _cmd, id event) {' | grep -q 'gMSWRMFD = fd; gMSWRMRest = DMMSWPauseResting(&gMSWHold) != 0; gMSWRMSaw = -1;' \
   && fn 'static id DMMSWRMChange(id self, SEL _cmd, id event) {' | grep -q '@try { r = o_MSWRMChange(self, _cmd, event); }' \
   && fn 'static id DMMSWRMChange(id self, SEL _cmd, id event) {' | grep -q '@finally { gMSWRMFD = nil; }'"
check "  ... there the destination reads App Switcher only while the fingers rest; the dip reads seen while they rest" \
  "fn 'static long long DMMSWRMDest(id self, SEL _cmd) {' | grep -q 'if (!gMSWRMFD || self != gMSWRMFD) return d;' \
   && fn 'static long long DMMSWRMDest(id self, SEL _cmd) {' | grep -q 'if (d != 3 || gMSWRMRest) return d;' \
   && fn 'static long long DMMSWRMDest(id self, SEL _cmd) {' | grep -q 'return 4;' \
   && fn 'static BOOL DMMSWRMDip(id self, SEL _cmd) {' | grep -q 'if (!gMSWRMFD || self != gMSWRMFD) return dip;' \
   && fn 'static BOOL DMMSWRMDip(id self, SEL _cmd) {' | grep -q 'return gMSWRMRest ? YES : dip;'"
check "the lift still answers as before (Home without a hold), and an end without a lift keeps SpringBoard's destination" \
  "fn 'static id DMMSWActivateWith(id self, SEL _cmd, long long dest, id (\*orig)(id, SEL, long long)) {' | grep -q 'if (eff == 3 && dest == 3 && DMMSWRestSaysHome()) return orig(self, _cmd, 4);' \
   && fn 'static BOOL DMMSWRestSaysHome(void) {' | grep -q 'BOOL home = DMMSWPauseSaysHome(&gMSWHold, &rest) != 0;'"
[ $rc = 0 ] && echo "test-mswhold: site checks pass" || echo "test-mswhold: FAILED"
exit $rc
