#!/bin/bash
# Mac test of moving a sticky note (1.8.8.2 B78, KT 22 Nov: "with mouse/trackpad it sometimes goes straight into edit mode and cannot be moved for a
# while"; "the long press with finger takes too long"): one decider for typing (a press that went past its drag distance never types), the top bar
# as the handle (at once, also while typed in), a finger's 0.2 s hold with the lift cue on the paper. The rules (common/StickyNotes.h, with
# DesktopHold.h's whose-touch answer and Desktop.h's hold times, test-stickymove.m) and site checks of where the desktop and the notes use them.
# MSB_D, MSB_DN, MSB_N point it at copies of Desktop.h, DesktopNotes.h and StickyNotes.h: made-to-fail copies must each fail.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
D=${MSB_D:-../statusbar/Desktop.h}; DN=${MSB_DN:-../statusbar/DesktopNotes.h}; N=${MSB_N:-../common/StickyNotes.h}
mkdir -p "$W/common"; cp "$N" "$W/common/StickyNotes.h"; cp ../statusbar/DesktopHold.h "$W/DesktopHold.h"
grep -E '^static inline double DMDesktopHoldToTake\(BOOL onIcon\) \{ return onIcon \? 0\.3 : 0\.35; \}$' "$D" > "$W/holdtotake.h" || true
grep -E '^static const double kDMDesktopHoldMenu(Pointer)? = ' "$D" >> "$W/holdtotake.h" || true
check "Desktop.h's hold times as one line each (the test builds them from there): an icon 0.3 s, the empty desktop 0.35 s, the menus 0.45 s and a click's 0.75 s" \
  "[ \$(wc -l < '$W/holdtotake.h') -eq 3 ]"
clang -O2 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -framework CoreGraphics -o "$W/tsm" test-stickymove.m
"$W/tsm" || fails=1

# ---- one decider: -dm_event: notes the press's distance, the tap judges by it ----
EV=$(fnf '- (void)dm_event:(UIEvent *)e {' "$D")
check "-dm_event: notes per press whether it went past its drag distance: cleared at the touch-down, set right after the distance test, before any branch takes the move" \
  "printf '%s\n' \"\$EV\" | grep -qF '_holdMenu = NO; _trackMoved = NO;' \
   && printf '%s\n' \"\$EV\" | awk '/if \\(hypot\\(sp.x - _trackDown.x, sp.y - _trackDown.y\\) <= \\(_trackPointer \\? 4.0 : 10.0\\)\\) continue;/{a=NR} /_trackMoved = YES;/{b=NR} /CFTimeInterval held = CACurrentMediaTime\\(\\) - _trackAt;/{c=NR} /if \\(_trackOwner == MSBDTouchGivenAway\\) \\{/{d=NR} END{exit !(a && b == a + 1 && c == b + 1 && d > c)}' \
   && grep -qF 'BOOL _trackMoved;' '$D'"
check "  ... the desktop's tap keeps its touch and where it went down (-dm_noteTapDown:, from shouldReceiveTouch:, which UIKit asks before -dm_event: has the touch)" \
  "fnf '- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {' '$D' | grep -qF 'if ([g.name isEqualToString:@\"dm.desktop.tap\"] || [g.name isEqualToString:@\"dm.note.tap\"]) { _lastTapPointer = DMDesktopPointerTouch(t, nil); [self dm_noteTapDown:t]; }' \
   && fnf '- (void)dm_noteTapDown:(UITouch *)t {' '$DN' | grep -qF '_notes.tapTouch = t; _notes.tapDownAt = CACurrentMediaTime();' && fnf '- (void)dm_noteTapDown:(UITouch *)t {' '$DN' | grep -qF '_notes.tapDown = DMStickyTouchAt(t);' \
   && grep -qF '@property (nonatomic, weak) UITouch *tapTouch;' '$DN' && ! grep -q 'tapPressAt' '$DN'"
check "  ... -dm_event: keeps the touch of the press it follows past that press's end (_pressTouch), set with _track at the touch-down" \
  "printf '%s\n' \"\$EV\" | grep -qF '_track = t; _pressTouch = t; _trackView = onIcon ? (DMDesktopItemView *)at : nil;' && grep -qF '__weak UITouch *_pressTouch;' '$D' \
   && [ \$(grep -c '_pressTouch = ' '$D') = 1 ]"
NT=$(fnf '- (void)dm_noteTap:(UITapGestureRecognizer *)g {' "$DN")
check "  ... -dm_noteTap: types only by MSBDStickyPressTypes: moved (its own press's note, or down to up past the drag distance), a menu of ours up, held past the menu's time" \
  "printf '%s\n' \"\$NT\" | grep -qF 'BOOL samePress = tt != nil && tt == _pressTouch;' && printf '%s\n' \"\$NT\" | grep -qF 'UITouch *tt = _notes.tapTouch;' \
   && printf '%s\n' \"\$NT\" | grep -qF 'CGPoint lift = tt ? DMStickyTouchAt(tt) : up;' \
   && printf '%s\n' \"\$NT\" | grep -qF 'BOOL moved = MSBDStickyTapMoved(samePress, _trackMoved, hypot(_trackLast.x - _trackDown.x, _trackLast.y - _trackDown.y), hypot(lift.x - _notes.tapDown.x, lift.y - _notes.tapDown.y), _lastTapPointer ? 4.0 : 10.0);' \
   && printf '%s\n' \"\$EV\" | grep -qF '_trackLast = sp;' \
   && printf '%s\n' \"\$NT\" | grep -qF 'if (!MSBDStickyPressTypes(moved, gOverlay != nil, held, _lastTapPointer ? kDMDesktopHoldMenuPointer : kDMDesktopHoldMenu)) {' \
   && printf '%s\n' \"\$NT\" | awk '/if \\(!MSBDStickyPressTypes\\(/{a=NR} /\\[self dm_noteBegin:v at:/{b=NR} END{exit !(a && b > a)}' && ! printf '%s\n' \"\$NT\" | grep -qF '_notes.track == v && CACurrentMediaTime() - _trackAt'"
# ---- the top bar: the note's from the touch down ----
check "the press records whether it began on the note's top bar (MSBDStickyOnBar, in the note's own layer)" \
  "grep -qF 'BOOL onNote = !onIcon && [self dm_noteTrackBegin:at at:sp];' '$D' && fnf '- (BOOL)dm_noteTrackBegin:(UIView *)at at:(CGPoint)sp {' '$DN' | grep -qF '_notes.trackBar = v && MSBDStickyOnBar(v.frame, [v.superview convertPoint:sp fromCoordinateSpace:'"
check "  ... its hold to move is 0 (the bar) or 0.2 s (the paper), for the drag and for the Dock's swipe down alike; icons and the empty desktop keep theirs" \
  "[ \$(grep -cF '[self dm_noteTracked] ? [self dm_noteHoldToMove] : DMDesktopHoldToTake(_trackView != nil)' '$D') = 2 ] && fnf '- (double)dm_noteHoldToMove {' '$DN' | grep -qF 'return MSBDStickyHoldToMove(_notes.trackBar);' \
   && printf '%s\n' \"\$EV\" | grep -qF 'if (!_trackPointer && held < ([self dm_noteTracked] ? [self dm_noteHoldToMove] : DMDesktopHoldToTake(_trackView != nil)) && !_menuOpen) {' \
   && fnf '- (BOOL)dm_touchIsOursFor:(UIGestureRecognizer *)g {' '$D' | grep -qF 'CACurrentMediaTime() - _trackAt, [self dm_noteTracked] ? [self dm_noteHoldToMove] : DMDesktopHoldToTake(_trackView != nil));'"
BF=$(fnf '- (void)dm_noteBarFirstMove:(UITouch *)t {' "$DN")
check "  ... at its first move (before the drag distance) a bar press is the note's: its other gestures and the page's scroll let go -- an undecided, primary press only" \
  "printf '%s\n' \"\$EV\" | awk '/if \\(!_trackMode\\) \\{/{a=NR} /\\[self dm_noteBarFirstMove:t\\];/{b=NR} /if \\(hypot\\(sp.x - _trackDown.x, sp.y - _trackDown.y\\) <= /{c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' \
   && printf '%s\n' \"\$BF\" | grep -qF 'if (![self dm_noteTracked] || !_notes.trackBar || _trackOwner != MSBDTouchUndecided || _trackSecondary || !t) return;' \
   && printf '%s\n' \"\$BF\" | grep -qF '_trackOwner = MSBDTouchDesktop;' && printf '%s\n' \"\$BF\" | grep -qF '[self dm_noteTakeTouch:t];' \
   && fnf '- (void)dm_noteTakeTouch:(UITouch *)t {' '$DN' | grep -qF 'if (![o.name hasPrefix:@\"dm.\"] && o.enabled) { o.enabled = NO; o.enabled = YES; }' \
   && fnf '- (void)dm_noteTakeTouch:(UITouch *)t {' '$DN' | grep -qF 'UIPanGestureRecognizer *pan = ((UIScrollView *)v).panGestureRecognizer; pan.enabled = NO; pan.enabled = YES;'"
# ---- a pointer's press: the note's from the touch down (a click held on a note opened iPadOS's Home Screen editing before our menu's 0.75 s) ----
# (1.8.8.4: the same take for our icons and the empty desktop, Desktop.h -dm_pointerPressTake: with DesktopHold.h's rule: test-desktophold.sh)
PP=$(fnf '- (void)dm_pointerPressTake:(UITouch *)t {' "$D")
check "a pointer's primary press on a note is the note's at its touch-down: asked right after the press is noted (with the finger's cue), by the desktop's pointer rule, a note always" \
  "printf '%s\n' \"\$EV\" | awk '/_holdMenu = NO; _trackMoved = NO;/{a=NR} /if \\(onNote\\) \\[self dm_noteHoldCueFor:t\\];/{b=NR} /if \\(MSBDDesktopPointerPressOurs\\(pointer, _trackSecondary, onNote, DMDesktopFingerOwnMenu\\(\\)\\)\\) \\[self dm_pointerPressTake:t\\];/{c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' \
   && grep -qF 'return pointer && !secondary && (onNote || ownMenu);' ../statusbar/DesktopHold.h && grep -qF -- '- (void)dm_noteTakeTouch:(UITouch *)t;' '$D'"
check "  ... a pointer's, primary (a secondary click keeps the note's own menu interaction), the press followed now; never a finger's" \
  "printf '%s\n' \"\$PP\" | grep -qF 'if (!t || t != _track || !_trackPointer || _trackSecondary) return;'"
check "  ... the press is the desktop's (the Dock's swipe down and Spotlight's pull refused) and every other gesture on it lets go now, the Home Screen's hold among them" \
  "printf '%s\n' \"\$PP\" | awk '/_trackOwner = MSBDTouchDesktop;/{a=NR} /\\[self dm_noteTakeTouch:t\\];/{b=NR} END{exit !(a && b == a + 1)}' && printf '%s\n' \"\$PP\" | grep -qF 'if ([self dm_noteTracked]) DM_FEATURE_MARK(\"sticky-note-pointer-press\");'"
check "  ... and once more on the next turn of the main queue, for the same press only, still down (UIKit gives a touch its gestures around -sendEvent:)" \
  "printf '%s\n' \"\$PP\" | grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{' \
   && printf '%s\n' \"\$PP\" | grep -qF 'if (s && x && s->_track == x && s->_trackAt == at && x.phase != UITouchPhaseEnded && x.phase != UITouchPhaseCancelled) [s dm_noteTakeTouch:x];'"
# ---- the paper: the finger's cue ----
check "a finger on a note's paper: the cue is asked at the touch-down (after the press is noted) and comes 0.2 s in, only while the press is still on and within its drag distance" \
  "printf '%s\n' \"\$EV\" | awk '/_holdMenu = NO; _trackMoved = NO;/{a=NR} /if \\(onNote\\) \\[self dm_noteHoldCueFor:t\\];/{b=NR} END{exit !(a && b == a + 1)}' \
   && fnf '- (void)dm_noteHoldCueFor:(UITouch *)t {' '$DN' | grep -qF 'if (!_notes.track || _notes.trackBar || _trackPointer || !t) return;' \
   && fnf '- (void)dm_noteHoldCueFor:(UITouch *)t {' '$DN' | grep -qF '(int64_t)(MSBD_NOTE_HOLD_TO_MOVE * NSEC_PER_SEC)' \
   && fnf '- (void)dm_noteCueCheck:(UITouch *)t since:(CFTimeInterval)at {' '$DN' | grep -qF 'if (!on || !v || !v.window || v.hidden || _trackMode || _lifted || hypot(_trackLast.x - _trackDown.x, _trackLast.y - _trackDown.y) > 10.0) return;'"
check "  ... the cue is the dragged look and goes back when the press ends without a drag; the lift and the drop use the same look" \
  "fnf '- (void)dm_noteCueCheck:(UITouch *)t since:(CFTimeInterval)at {' '$DN' | grep -qF '_notes.cued = nil; DMStickyLiftLook(c, NO);' && fnf '- (void)dm_noteCueCheck:(UITouch *)t since:(CFTimeInterval)at {' '$DN' | grep -qF '_notes.cued = v; DMStickyLiftLook(v, YES);' \
   && fnf '- (BOOL)dm_noteLiftAt:(CGPoint)sp {' '$DN' | grep -qF 'if (_notes.cued == v) _notes.cued = nil; else DMStickyLiftLook(v, YES);' && fnf '- (void)dm_noteDropAt:(CGPoint)sp {' '$DN' | grep -qF 'DMStickyLiftLook(v, NO);' \
   && ! grep -qF 'v.layer.shadowOpacity = 0.35' '$DN'"
# ---- while typed in: the editor's bar moves it ----
check "the note being typed in: its bar has a pan named dm.note.move (-dm_noteMove:), drawn as the idle note's bar, the text below it" \
  "grep -qF '_movePan = [[UIPanGestureRecognizer alloc] initWithTarget:target action:@selector(dm_noteMove:)];' '$DN' && grep -qF '_movePan.name = @\"dm.note.move\"; _movePan.maximumNumberOfTouches = 1;' '$DN' \
   && grep -qF '[_band addGestureRecognizer:_movePan];' '$DN' && grep -qF 'DMStickySetFrame(_band, MSBDStickyBarRect(b), \"the editor'\"'\"'s bar\");' '$DN' && grep -qF 'DMStickySetFrame(_textView, CGRectMake(0, MSBD_NOTE_BAR, b.size.width, MAX(0.0, b.size.height - MSBD_NOTE_BAR)), \"the editor'\"'\"'s text\");' '$DN' \
   && grep -qF '[DMStickyColor(_colorIndex, YES) setFill]; UIRectFill(MSBDStickyBarRect(b));' '$DN' && grep -qF 'CGRect tr = CGRectMake(kDMNoteSide, MSBD_NOTE_BAR + kDMNoteUnderBand,' '$DN' && ! grep -q 'MSBD_NOTE_BAND' '$DN' '$N'"
MV=$(fnf '- (void)dm_noteMove:(UIPanGestureRecognizer *)g {' "$DN")
check "  ... -dm_noteMove: does nothing once the editor has gone; follows inside the free area; holds the keyboard's moves off while pulled" \
  "printf '%s\n' \"\$MV\" | grep -qF 'if (!ed || !host || g.view.superview != ed) return;' && printf '%s\n' \"\$MV\" | grep -qF 'CGRect f = MSBDStickyClampInside(CGRectOffset(_notes.resizeStart, d.x, d.y), desk);' \
   && printf '%s\n' \"\$MV\" | grep -qF '_notes.resizeStart = ed.frame; _notes.resizing = YES;' && printf '%s\n' \"\$MV\" | grep -qF '_notes.resizing = NO;' && fnf '- (void)dm_noteFit {' '$DN' | grep -qF 'if (!ed || !host || _notes.resizing) return;'"
check "  ... let go, the place is stored as a drop stores it (clear of the app icons, the centre's share, on top, saved) and laid out; the typing is never ended by it" \
  "printf '%s\n' \"\$MV\" | grep -qF 'CGRect anchor, placed = DMStickyPlaceFit(DMStickyAtItsSize(e, mine, area), area, r, (int)occ.count, &anchor, ed.noteId);' \
   && printf '%s\n' \"\$MV\" | grep -qF 'e[@\"x\"] = c[0]; e[@\"y\"] = c[1];' && printf '%s\n' \"\$MV\" | grep -qF 'DMStickyChanged(0.3);' && printf '%s\n' \"\$MV\" | grep -qF '[self dm_placeAgain]; [self layoutIfNeeded];' \
   && ! printf '%s\n' \"\$MV\" | grep -qE 'dm_noteEnd|resignFirstResponder'"
check "  ... lifted over the on-screen keyboard: no move (the pan off, as the grips hide); the screen-edge pulls leave the bar's drag (DMStickyGripAt)" \
  "fnf '- (void)dm_noteFit {' '$DN' | grep -qF 'ed.gripL.hidden = lifted; ed.gripR.hidden = lifted; ed.movePan.enabled = !lifted;' \
   && fnf '- (BOOL)dm_noteGripAt:(CGPoint)sp {' '$DN' | grep -qF 'return ed.movePan.enabled && CGRectContainsPoint([ed.band convertRect:ed.band.bounds toCoordinateSpace:scr], sp);'"
[ $fails = 0 ] && echo "test-stickymove: all passed" || echo "test-stickymove: FAILED"
exit $fails
