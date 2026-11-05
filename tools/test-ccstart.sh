#!/bin/bash
# Mac test of a Control Center Style change in SpringBoard's first seconds (1.8.1 item 16, review 1.8.0.1 finding 1): the lookups and the style's apply as built, cut out of
# statusbar/CCPanel.h and CC18Shape.h and run with stand-ins (test-ccstart.m); then the wiring: the constructor's own look asks nothing, and only the style change (and the debug
# read-outs) ask, never a hook of Apple's views (they run inside Apple's build). MSBD_TEST_CCPANEL, MSBD_TEST_CC18: other copies of the sources, to see these checks fail on the old ones.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
P=${MSBD_TEST_CCPANEL:-../statusbar/CCPanel.h}
Q=${MSBD_TEST_CC18:-../statusbar/CC18Shape.h}
fn() { awk -v s="$2" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
{
  fn "$P" 'static UIViewController *DMCCPFindOverlay(void) {'
  fn "$P" 'static void DMCCPApplyStyle(NSString *why) {'
  fn "$Q" 'static UIViewController *DMCC18MainIfOurs(id vc) {'
  fn "$Q" 'static UIViewController *DMCC18FindMain(void) {'
  fn "$Q" 'static id DMCC18StoreInit(id self, SEL _cmd, NSURL *current, NSURL *desired) {'
  fn "$Q" 'static void DMCC18ApplyStyle(NSString *why) {'
} > "$W/ccstart-gen.h"
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -framework Foundation -o "$W/t" test-ccstart.m
fails=0
"$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
nodebug() { awk '/^#if/{if (d || /^#if DEBUG/) d++} !d{print} /^#endif/{if (d) d--}' "$1"; }   # (a file without its debug blocks)
check "15-17: the constructor's look asks SpringBoard nothing: the start's apply runs with the mark, the mark off right after, no other sets it" \
  "fn $P 'static void DMCCPanelInit(void) {' | awk '/gCCPInConstructor = YES;/{a=NR} /DMCCPApplyStyle\(@\"start\"\);/{b=NR} /gCCPInConstructor = NO;/{c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' \
   && [ \$(grep -c 'gCCPInConstructor = YES' $P) = 1 ] && fn $P 'static void DMCCPApplyStyle(NSString *why) {' | grep -qF 'UIViewController *ov = gCCPInConstructor ? nil : DMCCPFindOverlay();'"
check "18: the same" \
  "fn $Q 'static void DMCC18Init(void) {' | awk '/gCC18InConstructor = YES;/{a=NR} /DMCC18ApplyStyle\(@\"start\"\);/{b=NR} /gCC18InConstructor = NO;/{c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' \
   && [ \$(grep -c 'gCC18InConstructor = YES' $Q) = 1 ] && fn $Q 'static void DMCC18ApplyStyle(NSString *why) {' | grep -qF 'UIViewController *m = gCC18InConstructor ? nil : DMCC18FindMain();'"
check "the lookups: only the style's apply (and the debug read-outs) ask, never a hook of Apple's views: those run inside Apple's build, and a lookup there re-enters its +sharedInstance's dispatch_once (1.8.0~i11)" \
  "[ \$(nodebug $P | grep -c 'DMCCPFindOverlay()') = 1 ] && [ \$(nodebug $Q | grep -c 'DMCC18FindMain()') = 1 ]"
check "  ... and Control Center's window flag stays what it was for: DMControlCenterActive's question, not the lookups'" \
  "! fn $P 'static UIViewController *DMCCPFindOverlay(void) {' | grep -qE 'gCCWindowSeen|DMStarting' && ! fn $Q 'static UIViewController *DMCC18FindMain(void) {' | grep -qE 'gCCWindowSeen|DMStarting' \
   && grep -qF 'if (!gCCWindowSeen) return NO;' ../statusbar/StatusBar.x"
check "no em dashes in the new files" "! grep -n \$'\\xe2\\x80\\x94' test-ccstart.m test-ccstart.sh"
exit $fails
