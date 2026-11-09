#!/bin/bash
# Mac test of the Dock's hover (the magnification's pointer, dock/Dock.x dm_hover): the debug line of review 1.8.4 Pass 4's watch item.
cd "$(dirname "$0")" || exit 1
fails=0
D=../dock/Dock.x
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
hov() { awk '/^- \(void\)dm_hover:\(UIHoverGestureRecognizer \*\)gesture \{/,/^}/' "$D"; }
check "a debug line at the hover's Began and at its end: the pointer, the platter's frame and as drawn, UIKit's hit-test there and whether it is in the platter, the Dock presented" \
  "grep -q '^static void DMHoverDebugLine(UIView \*platter, UIGestureRecognizer \*g) {' $D \
   && grep -q '\\[hover\\] %ld t %.3f p %@ frame %@ pres %@ hit %@ inside %d presented %d' $D \
   && hov | grep -q 'if (gesture.state == UIGestureRecognizerStateBegan) DMHoverDebugLine(self, gesture);' \
   && [ \$(hov | grep -c 'DMHoverDebugLine(self, gesture);') = 2 ]"
check "  ... in debug builds only" \
  "awk '/^static void DMHoverDebugLine/{f=1} f&&/^#endif/{print; exit}' $D | grep -q endif && awk 'NR>1 && prev ~ /^#if DEBUG\$/ && /^\/\/ \(debug, review 1.8.4 Pass 4/ {ok=1} {prev=\$0} END{exit !ok}' $D \
   && [ \$(hov | grep -B1 'DMHoverDebugLine(self, gesture);' | grep -c '^#if DEBUG') = 2 ]"
check "  ... a cancelled hover logs who cancelled it, and a Dock settings change logs its steps (debug builds only: nothing in release)" \
  "grep -q 'if (g.state == UIGestureRecognizerStateCancelled) {' $D && grep -q '\\[hover\\] cancelled from:' $D \
   && grep -q '^#define DM_PREFS_STEP(name) DMLog(@\"\\[prefs-step\\] \" name)' $D && grep -q '^#define DM_PREFS_STEP(name) do {} while (0)' $D \
   && [ \$(awk '/^static void DMPrefsChanged\\(/,/^}/' $D | grep -c 'DM_PREFS_STEP(\"') = 6 ]"
[ $fails = 0 ] && echo "test-dockhover: all checks pass" || { echo "test-dockhover: checks FAILED"; exit 1; }
