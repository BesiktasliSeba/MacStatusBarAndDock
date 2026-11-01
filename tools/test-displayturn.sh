#!/bin/bash
# Mac test of the screen against the display's own space (statusbar/DisplayTurn.h, test-displayturn.c; 1.7.7 items 2 and 3 and the code review's
# S1): a window's scene frame turned for its app and back, the still's turn and its quarter-turn rule, both against iOS's fixed coordinate space;
# then the sites in the code as built: StatusBar.x uses this code, and a window's frame is turned exactly once on its way to the app.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tdt" test-displayturn.c
"$W/tdt"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$S"; }
check "StatusBar.x takes the turn from DisplayTurn.h: a window's frame for its app and back, with the screen's sides" \
  "grep -q '^#include \"DisplayTurn.h\"' $S && fn 'static CGRect DMWindowFrameForApp(CGRect f, long o) {' | grep -q 'return MSBDFrameForApp(f, o, MIN(sc.width, sc.height), MAX(sc.width, sc.height));' \
   && fn 'static CGRect DMWindowFrameOnScreen(CGRect f, long o) {' | grep -q 'return MSBDFrameOnScreen(f, o, MIN(sc.width, sc.height), MAX(sc.width, sc.height));'"
check "  ... and the still's turn and quarter rule (DMScreenStillView)" \
  "fn 'static UIView *DMScreenStillView(CGRect bounds) {' | grep -q 'CGFloat angle = (CGFloat)MSBDStillAngle(o, native.width, native.height);' && fn 'static UIView *DMScreenStillView(CGRect bounds) {' | grep -q 'BOOL quarter = MSBDStillQuarter(angle);' \
   && fn 'static UIView *DMScreenStillView(CGRect bounds) {' | grep -q 'iv.transform = CGAffineTransformMakeRotation(angle);'"
check "S1: a window's frame is turned once -- the scene hook with a completion turns it last; DMSetSceneFrame only for its three-argument sends (past our hooks), its two-argument send left to that hook" \
  "fn '- (void)updateSettings:(id)settings withTransitionContext:(id)context completion:(id)completion {' | grep -q 'settings = DMWindowSettingsForApp(self, settings);' \
   && [ \$(fn 'static BOOL DMSetSceneFrame(id scene, CGRect frame) {' | grep -c 'updateSettings:withTransitionContext:completion:\"), DMWindowSettingsForApp(scene, mutable), context,') = 3 ] \
   && fn 'static BOOL DMSetSceneFrame(id scene, CGRect frame) {' | grep -q 'updateSettings:withTransitionContext:\"), mutable, context);   // (turned in our three-argument hook)' \
   && ! fn 'static BOOL DMSetSceneFrame(id scene, CGRect frame) {' | grep -q 'mutable = DMWindowSettingsForApp' \
   && ! fn '- (void)updateSettings:(id)settings withTransitionContext:(id)context {' | grep -q 'DMWindowSettingsForApp('"
check "S1: the pass-on's two looks compare a frame read back from the scene in the space it holds it in (DMSceneHasWindowFrame), not the screen's" \
  "[ \$(fn 'static void DMPassWindowFrameToShownScene(id scene, id settings) {' | grep -c 'DMSceneHasWindowFrame(') = 2 ] && ! fn 'static void DMPassWindowFrameToShownScene(id scene, id settings) {' | grep -q 'CGRectEqualToRect(now, f)'"
check "the passon_ debug trigger is debug only and uses the pass-on's own check" \
  "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /hasPrefix:@\"passon_\"/{print d}' $S | grep -qx 1 && grep -q 'BOOL (^has)(CGRect) = ^BOOL(CGRect r) { return DMSceneHasWindowFrame(sc, r, f, o); };' $S"
[ $fails = 0 ] && echo "test-displayturn: site checks pass" || { echo "test-displayturn: site checks FAILED"; exit 1; }
