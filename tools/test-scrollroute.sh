#!/bin/bash
# Mac test of the scroll routing over native windows (statusbar/StatusBar.x, 1.7.2 item 6), as built: SpringBoard gets every trackpad / wheel
# scroll as a global copy for its system gesture window, and a copy for our layer too when the window server's hit test finds the layer (M1,
# 15.6.1). Until 1.7.1 our own path moved the list by every global copy as well -- a second hand beside UIKit's (clamped rubber band, extra layout
# per event). Checked here: the global copy is left alone when the layer gets its own; a lone one is named for our layer (UIKit scrolls it); the
# old path only where the hook cannot go in; every private piece read only with the type it was checked to have.
set -e
cd "$(dirname "$0")"
SB=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$SB"; }
check "the decision asks whether the window server sends the scroll to the layer as well, before anything else is looked at" \
  "fn 'static BOOL DMNativeScrollIsOurs(UIEvent *event, UIWindow *named) {' | awk '/DMScrollAlsoToLayer\\(event, layer\\)\\) return NO;/{a=NR} /DMNativeWindowTaking\\(sp/{b=NR} END{exit !(a && b && a < b)}'"
check "  ... only global copies named for SpringBoard's system gesture window (or none) can be ours; one named for the layer never is" \
  "fn 'static BOOL DMNativeScrollIsOurs(UIEvent *event, UIWindow *named) {' | grep -q 'named == layer' && fn 'static BOOL DMNativeScrollIsOurs(UIEvent *event, UIWindow *named) {' | grep -q 'isEqualToString:@\"_UISystemGestureWindow\"\\]) return NO;'"
check "the layer's own copy: the hit test's contexts read only with the checked types (ivar, contextID, pid, _contextId)" \
  "fn 'static BOOL DMScrollAlsoToLayer(UIEvent *event, UIWindow *layer) {' | grep -q '\"@\\\\\"BKSHIDEventPointerAttributes\\\\\"\"' && fn 'static BOOL DMScrollAlsoToLayer(UIEvent *event, UIWindow *layer) {' | grep -c 'I16@0:8' | grep -q 2 && fn 'static BOOL DMScrollAlsoToLayer(UIEvent *event, UIWindow *layer) {' | grep -q 'i16@0:8'"
check "  ... matched by this process and the layer's own context (a context of 0 never matches)" \
  "fn 'static BOOL DMScrollAlsoToLayer(UIEvent *event, UIWindow *layer) {' | grep -q '== getpid() &&' && fn 'static BOOL DMScrollAlsoToLayer(UIEvent *event, UIWindow *layer) {' | grep -q 'return mine != 0;'"
check "the hook goes in only on UIScrollEvent's own -_windowServerHitTestWindow typed @16@0:8 (with -_hidEvent and -_windows there)" \
  "fn 'static void DMScrollRoutingInit(void) {' | grep -q 'strcmp(method_getTypeEncoding(m) ?: \"\", \"@16@0:8\")' && fn 'static void DMScrollRoutingInit(void) {' | grep -q 'MSHookMessageEx(c, sel, (IMP)DMScrollWSWindow, (IMP \\*)&o_DMScrollWS);'"
check "the hook decides once per event, on the main thread, and never inside its own decision (the event's location asks it again)" \
  "fn 'static id DMScrollWSWindow(id self, SEL _cmd) {' | grep -q 'if (deciding || !layer || named == layer) return named;' && fn 'static id DMScrollWSWindow(id self, SEL _cmd) {' | grep -q 'NSThread isMainThread'"
check "the old path (the list moved by the event's delta) runs only without the hook" \
  "grep -q 'static BOOL DMNativeScrollEvent(UIEvent \\*event) { return (!gDMScrollRouted || DMScrollOldPath()) && !DMScrollNone() && DMNativeScrollMove(event); }' $SB"
check "  ... and makes the same decision (so it never moves a list the layer's own copy already scrolls)" \
  "fn 'static BOOL DMNativeScrollMove(UIEvent *event) {' | grep -q 'if (!DMNativeScrollIsOurs(event, named)) return NO;'"
check "the test switches are debug-only (release: neither the old path nor 'none' can be forced)" \
  "awk '/^#if DEBUG/{d=1} /^#else/{d=0} /^#endif/{d=0} /static BOOL DMScrollOldPath\\(void\\) \\{ return access/{print d}' $SB | grep -qx 1"
check "the routing is set up with the native windows' hooks (Finder on), skippable for tests" \
  "grep -q 'if (!DMCtorSkip(\"scrollroute\")) DMScrollRoutingInit();' $SB"
check "no research probe left in the source (ScrollProbe.h, scrollrec_, amprobe)" \
  "! grep -rn 'ScrollProbe.h\\|scrollrec_\\|amprobe\\|gDMSP' ../statusbar/*.x ../statusbar/*.h && [ ! -e ../statusbar/ScrollProbe.h ]"
# Activity Monitor's refresh (the same item: a 40-45 ms frame every 2 s while it was open -- every visible label drawn again by -reloadData)
AM=../statusbar/ActivityMonitor.h
check "Activity Monitor: the 2 s refresh fills the rows in place, the user's own changes (tab, sort, filter, search) reload" \
  "awk '/- \\(void\\)dm_took:/{f=1} f&&/\\[self dm_rebuildRowsInPlace:YES\\];/{print \"ok\"; exit}' $AM | grep -q ok && grep -q '^- (void)dm_rebuildRows { \\[self dm_rebuildRowsInPlace:NO\\]; }' $AM"
check "  ... in place: no -reloadData unless the table's own count is not the old one; rows added or taken off the end without animation" \
  "awk '/^- \\(void\\)dm_rebuildRowsInPlace:/{f=1} f&&/if \\(!inPlace \\|\\| \\[_list numberOfRowsInSection:0\\] != had\\) \\[_list reloadData\\];/{a=1} f&&/performWithoutAnimation/{b=1} f&&/^}/{print (a && b) ? \"ok\" : \"no\"; exit}' $AM | grep -q ok"
check "  ... a label is given only a text that differs (an equal one would be drawn again)" \
  "awk '/^- \\(void\\)dm_fillCell:/{f=1} f&&/if \\(!\\[l.text isEqualToString:vals\\[i\\]\\]\\) l.text = vals\\[i\\];/{print \"ok\"; exit}' $AM | grep -q ok"
[ $fails = 0 ] && echo "test-scrollroute: all checks pass" || { echo "test-scrollroute: checks FAILED"; exit 1; }
