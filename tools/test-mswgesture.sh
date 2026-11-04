#!/bin/bash
# test-mswgesture.sh: a swipe up opens the Mac Switcher exactly where iPadOS would open its App Switcher (KT 3 Nov, 1.8.0). SpringBoard decides
# Home or the App Switcher by its own speed and pause rule, with Reduce Motion too; the Mac Switcher only takes the App Switcher's destination
# at the lift (statusbar/MacSwitcher.h DMMSWActivateWith) and never turns a swipe into Home or Home into the switcher. Site checks: no rule of
# our own between SpringBoard's decision and the lift (1.7.8's hold rule, 1.7.9's Reduce Motion pause check are gone), and SpringBoard's own
# fly-in and multitasking (part of its decision; 1.4 to 1.8.0 told it the finger never paused): iPadOS's cards are only not drawn.
cd "$(dirname "$0")" || exit 1
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
M=../statusbar/MacSwitcher.h
A='static id DMMSWActivateWith(id self, SEL _cmd, long long dest, id (*orig)(id, SEL, long long)) {'
check "SpringBoard's decision is its own: nothing hooks its final destination, its acceleration dip or Reduce Motion's move handling" \
  "! grep -rqE --include='*.h' --include='*.x' --include='*.m' 'MSHookMessageEx\([^;]*(currentFinalDestination|hasSeenAccelerationDipForAppSwitcher|_updateForGestureDidChangeWithEvent:)' ../statusbar ../common ../dock"
check "  ... and no hold rule of ours is left (MSWHoldRule.h gone, nothing includes it)" \
  "[ ! -e ../statusbar/MSWHoldRule.h ] && ! grep -rq 'MSWHoldRule' ../statusbar ../common"
check "the lift: SpringBoard's App Switcher destination opens the Mac Switcher as it is given" \
  "fn $M \"\$A\" | grep -q 'if (eff == 3) act = ^{ gMSWGestureAt = CACurrentMediaTime(); DMMSWOpen(@\"the App Switcher gesture\"); };'"
check "  ... SpringBoard is given its own destination or the takeover's stay (0), never Home (4) in place of the App Switcher" \
  "[ \"\$(fn $M \"\$A\" | grep -oE 'orig\(self, _cmd, [a-z0-9]+\)' | sort -u | tr '\n' ' ')\" = 'orig(self, _cmd, 0) orig(self, _cmd, dest) ' ]"
check "  ... Home and stay go through as SpringBoard decided them (Home Minimizes Windows sees the 4 in its trampoline)" \
  "fn $M \"\$A\" | grep -q 'if (inside || (eff != 3 && eff != 1 && eff != 2) || !gMSWGestHooked || !DMMSWGesturesOn()) return orig(self, _cmd, dest);' \
   && grep -q 'static id DMMSWActOrig(id self, SEL _cmd, long long dest) { if (dest == 4) DMHomeAwayLift(); return o_MSWActivate(self, _cmd, dest); }' $M"
check "with Reduce Motion, the Mac Switcher opens where its modifier ends the gesture: the same lift, by the same code" \
  "grep -q 'static id DMMSWActivateRM(id self, SEL _cmd, long long dest) { return DMMSWActivateWith(self, _cmd, dest, DMMSWActOrigRM); }' $M \
   && fn $M 'static void DMMSWHookActivation(void) {' | grep -q 'MSHookMessageEx(rm, NSSelectorFromString(@\"_responseForActivatingFinalDestination:\"), (IMP)DMMSWActivateRM, (IMP \*)&o_MSWActivateRM);'"
check "the gesture's updates and end reach SpringBoard as they are, but for a side swipe's slide that follows the fingers" \
  "fn $M 'static void DMMSWGUpdate(id self, SEL _cmd, id transaction, id gesture) {' | sed -n 3p | grep -q 'if (inside || (gMSWTrack != 1 && gMSWTrack != 2) || gesture != gMSWTrackGesture) { o_MSWGUpdate(self, _cmd, transaction, gesture); return; }' \
   && fn $M 'static void DMMSWGEnd(id self, SEL _cmd, id transaction, id gesture) {' | sed -n 3p | grep -q 'if (inside || (gMSWTrack != 1 && gMSWTrack != 2) || gesture != gMSWTrackGesture) { o_MSWGEnd(self, _cmd, transaction, gesture); return; }'"
check "  ... and its fly-in and multitasking: the home gesture's -_hasPausedEnoughForFlyIn is not hooked (the debug probe only reads it)" \
  "! grep -q 'MSHookMessageEx(c, NSSelectorFromString(@\"_hasPausedEnoughForFlyIn\")' $M && ! grep -q 'DMMSWFlyIn(id self' $M"
check "iPadOS's cards are only not drawn: in multitasking, while the gesture is ours, the switcher draws just the app layout it drags" \
  "fn $M 'static id DMMSWVisible(id self, SEL _cmd) {' | grep -q 'if (!\*((const BOOL \*)((const char \*)(__bridge const void \*)self + ivar_getOffset(gMSWMultiIv))) || !DMMSWGesturesOn() || !\[v isKindOfClass:\[NSSet class\]\]) return v;' \
   && fn $M 'static id DMMSWVisible(id self, SEL _cmd) {' | grep -q 'return dragged && \[(NSSet \*)v containsObject:dragged\] ? \[NSSet setWithObject:dragged\] : \[NSSet set\];'"
check "  ... hooked only with the shapes it reads (visibleAppLayouts, _inMultitasking a BOOL, _selectedAppLayout an object), else no takeover" \
  "fn $M 'static void DMMSWHookGestures(void) {' | grep -q 'BOOL cards = DMMSWHasMethod(c, @\"visibleAppLayouts\", @\"@@:\") && multi && !strcmp(ivar_getTypeEncoding(multi), \"B\") && dragged && ivar_getTypeEncoding(dragged)\[0\] == .@.;' \
   && fn $M 'static void DMMSWHookGestures(void) {' | grep -q 'if (!dest || !cards || (!ok15 && !ok16 && !okGM)) {' \
   && fn $M 'static void DMMSWHookGestures(void) {' | grep -q 'MSHookMessageEx(c, NSSelectorFromString(@\"visibleAppLayouts\"), (IMP)DMMSWVisible, (IMP \*)&o_MSWVisible);'"
[ $fails = 0 ] && echo "test-mswgesture: all pass" || echo "test-mswgesture: FAILED"
exit $fails
