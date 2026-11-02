#!/bin/bash
# Mac test of a finger held on the desktop (statusbar/DesktopHold.h, test-desktophold.c; 1.7.8): the hold's menu for a finger that wobbles in
# place (review m2), and whose a touch is, decided once between the desktop and the Dock's swipe down (review N1) -- then the wiring.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tdh" test-desktophold.c
"$W/tdh"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../statusbar/Desktop.h; K=../dock/Dock.x
check "the hold check follows the shared rule: wait (the press is the desktop's, its other gestures let go), the menu, or nothing" \
  "grep -q 'MSBDHoldStep step = MSBDDesktopHoldStep(now - at, now - _trackRestAt, hypot(_trackLast.x - _trackDown.x, _trackLast.y - _trackDown.y), _trackPointer, kDMDesktopRestTime);' $D \
   && awk '/if \(step == MSBDHoldWait\) \{/{f=1} f&&/o.enabled = NO; o.enabled = YES;/{g=1} f&&g&&/dm_holdCheck:wt since:at/{print \"ok\"; exit}' $D | grep -q ok && grep -q 'if (step == MSBDHoldNone) return;' $D"
check "  ... no menu from a touch the swipe down took" \
  "awk '/^- \(void\)dm_holdCheck:\(UITouch \*\)t since:\(CFTimeInterval\)at \{/{f=1} f&&/if \(_trackOwner == MSBDTouchGivenAway\) return;/{print \"ok\"; exit} f&&/MSBDDesktopHoldStep/{exit}' $D | grep -q ok"
check "whose a touch is: one answer per touch, reset at each touch-down, the desktop's once it takes a move" \
  "grep -q 'return MSBDDesktopTouchOursAnswer(&_trackOwner, _trackMode != 0, _holdMenu, _trackPointer, CACurrentMediaTime() - _trackAt, DMDesktopHoldToTake(_trackView != nil));' $D \
   && grep -q '_trackPointer = pointer; _trackOwner = MSBDTouchUndecided;' $D && grep -q '_trackOwner = MSBDTouchDesktop;   // (the desktop.s from here' $D"
check "  ... a move of a touch the swipe down took is left to it (no rectangle, no drag)" \
  "awk '/if \(_trackOwner == MSBDTouchGivenAway\) \{   \/\/ \(the Dock.s swipe down fired/{f=1} f&&/_track = nil; continue;/{print \"ok\"; exit}' $D | grep -q ok"
check "the Dock tells the desktop when its swipe down fires (found with dlsym, as its ask), only when the App Library was presented" \
  "grep -q 'if (DMPresentAppLibrary()) { gSwipeLibraryAt = CACurrentMediaTime(); DMDesktopTouchGivenAway(gesture); }' $K && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDesktopTouchGivenAway\")' $K \
   && grep -q '__attribute__((visibility(\"default\"))) void MSBDDesktopTouchGivenAway(UIGestureRecognizer \*g)' $D"
[ $fails = 0 ] && echo "test-desktophold: site checks pass" || { echo "test-desktophold: site checks FAILED"; exit 1; }
