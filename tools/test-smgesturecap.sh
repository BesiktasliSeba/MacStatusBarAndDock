#!/bin/bash
# Mac test of the Stage Manager engine's gesture hold and a window's live resize that SpringBoard never completes (1.8.0 item 7, A12Z 18.5: one
# stayed "Completed: NO" for 350 s): the rule (statusbar/SMGestureCap.h, test-smgesturecap.c), then the hold as built (SMGestureHold.h) -- the
# cap only for a live resize, the finger read from the transaction's own recognizer, a transaction let go counted as ended (the writes it held
# run), the half-second look while writes wait.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wno-unused-function -o "$W/tgc" test-smgesturecap.c
"$W/tgc"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
H=../statusbar/SMGestureHold.h
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $H > "$W/fn"; [ -s "$W/fn" ]; }
check "the rule is SMGestureCap.h's, included by the hold" "grep -q '^#include \"SMGestureCap.h\"' $H && grep -q '^static inline int MSBDGestureTxHolds(int complete, int liveResize, int fingerDown, double upSince, double now) {' ../statusbar/SMGestureCap.h"
check "every transaction the hold counts is asked: complete, or a live resize up long enough, is let go -- and counts as ended, so the writes it held run" \
  "fn 'static BOOL DMSMGestureLive(void) {' && grep -q 'if (!DMSMGestureTxHolds(t, complete)) { \[gSMGestureTxs removeObject:t\]; dropped++; continue; }' \$W/fn \
   && grep -q 'BOOL ended = lastN > 0 && n == 0 && (dropped || gSMGestureTxs.count == 0);' \$W/fn && grep -q 'if (ended && gSMAfterGesture.count) dispatch_async(dispatch_get_main_queue(), ^{ DMSMGestureFlush(); });' \$W/fn"
check "  ... the cap only for a live resize (its own -isLiveResize); the finger from its recognizer's state (began or changed: down), shape-checked; unreadable: down" \
  "fn 'static BOOL DMSMGestureTxHolds(id t, BOOL complete) {' && grep -q 'BOOL live = !complete && DMSMGTGetter(t, lr, .B.) && ((BOOL (\*)(id, SEL))objc_msgSend)(t, lr);' \$W/fn \
   && grep -q 'if (!live) return MSBDGestureTxHolds(complete, NO, YES, 0, 0);' \$W/fn && grep -q 'BOOL down = YES;' \$W/fn && grep -q 'BOOL readable = r && \[r respondsToSelector:st\];' \$W/fn && grep -q 'down = MSBDGestureFingerDown(readable, readable ? ((long long (\*)(id, SEL))objc_msgSend)(r, st) : 0);' \$W/fn \
   && grep -q 'double up = MSBDGestureUpSince(down, \[objc_getAssociatedObject(t, kSMGTUpSinceKey) doubleValue\], now);' \$W/fn && grep -q 'DM_FEATURE_MARK(\"sm-gesture-lifted-cap\");' \$W/fn \
   && grep -q 'SEL lr = NSSelectorFromString(@\"isLiveResize\"), gr = NSSelectorFromString(@\"gestureRecognizer\"), st = NSSelectorFromString(@\"state\");' \$W/fn"
check "  ... while writes wait, a look every half second lets them go at the cap with nothing else asking (queued while a transaction holds)" \
  "fn 'static void DMSMGestureWatchCap(void) {' && grep -q 'dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 \* NSEC_PER_SEC)), dispatch_get_main_queue(), ^{' \$W/fn \
   && grep -q 'if (gSMAfterGesture.count && DMSMGestureLive()) DMSMGestureWatchCap();' \$W/fn \
   && fn 'static void DMSMGestureFlushSoon(void) {' && grep -q 'if (gSMGestureHooked) { if (!DMSMGestureLive()) dispatch_async(dispatch_get_main_queue(), ^{ DMSMGestureFlush(); }); else DMSMGestureWatchCap(); return; }' \$W/fn"
check "the hold's hooks are as before: SpringBoard's begin and end of the base gesture transaction (every subclass, the live resize's too)" \
  "grep -q 'Class c = objc_getClass(\"SBFluidSwitcherGestureWorkspaceTransaction\");' ../statusbar/SMGestureHook.h && grep -q 'MSHookMessageEx(c, d, (IMP)DMSMGTDidComplete, (IMP \*)&o_SMGTDidComplete);' ../statusbar/SMGestureHook.h"
[ $fails = 0 ] && echo "test-smgesturecap wiring: all passed" || { echo "test-smgesturecap wiring: FAILED"; exit 1; }
