#!/bin/bash
# Mac test of a finger held on the desktop (statusbar/DesktopHold.h, test-desktophold.c; 1.7.8): the hold's menu for a finger that wobbles in
# place (review m2), and whose a touch is, decided once between the desktop and the Dock's swipe down (review N1), and a pointer's press taken at
# its touch-down (1.8.8.4: a click held on one of our desktop icons began the Home Screen's editing before our menu) -- then the wiring.
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
  "grep -q 'return MSBDDesktopTouchOursAnswer(&_trackOwner, _trackMode != 0, _holdMenu, _trackPointer, CACurrentMediaTime() - _trackAt, \\[self dm_noteTracked\\] ? \\[self dm_noteHoldToMove\\] : DMDesktopHoldToTake(_trackView != nil));' $D \
   && grep -q '_trackPointer = pointer; _trackOwner = MSBDTouchUndecided;' $D && grep -q '_trackOwner = MSBDTouchDesktop;   // (the desktop.s from here' $D"
check "  ... a move of a touch the swipe down took is left to it (no rectangle, no drag)" \
  "awk '/if \(_trackOwner == MSBDTouchGivenAway\) \{   \/\/ \(the Dock.s swipe down fired/{f=1} f&&/_track = nil; continue;/{print \"ok\"; exit}' $D | grep -q ok"
check "the Dock tells the desktop when its swipe down fires (found with dlsym, as its ask), only when the App Library was presented" \
  "grep -q 'if (DMPresentAppLibrary()) { gSwipeLibraryAt = CACurrentMediaTime(); DMDesktopTouchGivenAway(gesture); }' $K && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDesktopTouchGivenAway\")' $K \
   && grep -q '__attribute__((visibility(\"default\"))) void MSBDDesktopTouchGivenAway(UIGestureRecognizer \*g)' $D"
# ---- a pointer's press: the desktop's from the touch-down (1.8.8.4) ----
N=../statusbar/DesktopNotes.h
EV=$(awk 'index($0, "- (void)dm_event:(UIEvent *)e {") == 1 {f=1} f {print} f && /^}/ {exit}' $D)
PT=$(awk 'index($0, "- (void)dm_pointerPressTake:(UITouch *)t {") == 1 {f=1} f {print} f && /^}/ {exit}' $D)
check "a pointer's primary press on an icon, a note or the empty desktop is the desktop's at its touch-down: asked by the shared rule right after the press is noted" \
  "printf '%s\n' \"\$EV\" | awk '/_holdMenu = NO; _trackMoved = NO;/{a=NR} /if \\(onNote\\) \\[self dm_noteHoldCueFor:t\\];/{b=NR} /if \\(MSBDDesktopPointerPressOurs\\(pointer, _trackSecondary, onNote, DMDesktopFingerOwnMenu\\(\\)\\)\\) \\[self dm_pointerPressTake:t\\];/{c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' \
   && printf '%s\n' \"\$EV\" | awk '/if \\(!onIcon && !onNote && !\\[self dm_shownAt:sp\\]\\) continue;/{a=NR} /dm_pointerPressTake:t/{b=NR} END{exit !(a && b > a)}' \
   && ! grep -q 'dm_notePointerPress' $D $N"
check "  ... the press is the desktop's (the Dock's swipe down and Spotlight's pull refused) and its other gestures let go now (our own dm. ones keep it), a pointer's primary press only" \
  "printf '%s\n' \"\$PT\" | grep -qF 'if (!t || t != _track || !_trackPointer || _trackSecondary) return;' \
   && printf '%s\n' \"\$PT\" | awk '/_trackOwner = MSBDTouchDesktop;/{a=NR} /\\[self dm_noteTakeTouch:t\\];/{b=NR} END{exit !(a && b == a + 1)}' \
   && awk 'index(\$0, \"- (void)dm_noteTakeTouch:(UITouch *)t {\") == 1 {f=1} f {print} f && /^}/ {exit}' $N | grep -qF 'if (![o.name hasPrefix:@\"dm.\"] && o.enabled) { o.enabled = NO; o.enabled = YES; }' \
   && grep -qF -- '- (void)dm_noteTakeTouch:(UITouch *)t;' $D"
check "  ... and once more on the next turn of the main queue, for the same press only, while it is still down" \
  "printf '%s\n' \"\$PT\" | grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{' \
   && printf '%s\n' \"\$PT\" | grep -qF 'if (s && x && s->_track == x && s->_trackAt == at && x.phase != UITouchPhaseEnded && x.phase != UITouchPhaseCancelled) [s dm_noteTakeTouch:x];'"
check "  ... a held click still opens our menu at 0.75 s from the hold check (scheduled for a primary press, a click's time)" \
  "printf '%s\n' \"\$EV\" | grep -qF '(int64_t)((pointer ? kDMDesktopHoldMenuPointer : kDMDesktopHoldMenu) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws dm_holdCheck:wt since:at]; });' \
   && grep -qF 'static const double kDMDesktopHoldMenuPointer = 0.75;' $D"
# (1.8.8.4 review: the take at the touch-down comes before any gesture of the press has seen it, so it also stopped our own watcher of touches
#  outside the windows -- Aerial, Zetsu and our Stage Manager engine tell the windowed apps from it to put their keyboard away, as a click on a
#  Mac's desktop does: a click on page 1's desktop or one of our icons no longer did. Ours by name, it keeps every press: every take of the
#  desktop's leaves "dm." gestures alone)
SB=../statusbar/StatusBar.x
outside_ours() {
  local ot n
  ot=$(awk 'index($0, "static void DMAttachOutsideTaps(void) {") == 1 {f=1} f {print} f && /^}/ {exit}' $SB)
  printf '%s\n' "$ot" | grep -qF 'UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(tapped:)];' || return 1
  printf '%s\n' "$ot" | awk '/g\.name = @"dm\.focus\.outside";/{a=NR} /\[w addGestureRecognizer:g\];/{b=NR} END{exit !(a && b > a)}' || return 1
  n=$(cat $D $N | grep -c 'in \[t\.gestureRecognizers copy\]')
  [ "$n" -ge 5 ] && [ "$(cat $D $N | grep 'in \[t\.gestureRecognizers copy\]' | grep -cF 'if (![o.name hasPrefix:@"dm."]')" = "$n" ]
}
check "our watcher of touches outside the windows (the windowed apps put their keyboard away) is named in the desktop's \"dm.\" space, before it is added; every take of a press's gestures (the pointer's at its touch-down among them) leaves \"dm.\" ones alone" outside_ours
[ $fails = 0 ] && echo "test-desktophold: site checks pass" || { echo "test-desktophold: site checks FAILED"; exit 1; }
