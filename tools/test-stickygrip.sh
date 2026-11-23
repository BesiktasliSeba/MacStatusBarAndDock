#!/bin/bash
# Mac test of a sticky note's resize grips at its free area's sides (1.8.8.2 B72), and of our own windows' resize, which keeps 1.8.8.1's maths.
# Built from the source as written: DMNativeResized cut out of statusbar/NativeWindow.h; the frame line of -dm_noteResize: (statusbar/DesktopNotes.h)
# and the one of -dm_resize: (NativeWindow.h) made into functions; the sides DMDockSideKept (statusbar/StatusBar.x) keeps out of a side Dock when a
# window is let go, with common/DockSide.h's MSBDDockSideKeepOut (test-stickygrip.m). MSB_NW, MSB_DN and MSB_SB point it at copies of those three
# files: that is how made-to-fail copies of the sources are run against it, each of which must fail.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
NW=${MSB_NW:-../statusbar/NativeWindow.h}; DN=${MSB_DN:-../statusbar/DesktopNotes.h}; SB=${MSB_SB:-../statusbar/StatusBar.x}

awk '/^static CGRect DMNativeResized\(/{f=1} f{print} f&&/^}/{exit}' "$NW" > "$W/resized.h"
check "DMNativeResized is in NativeWindow.h as one function (the test builds it from there)" "[ \$(wc -l < '$W/resized.h') -ge 8 ] && grep -q 'return f;' '$W/resized.h'"

# the note: the one line of -dm_noteResize: that makes its frame, as a function of the grip's start, translation and tag and the free area
fnf '- (void)dm_noteResize:(UIPanGestureRecognizer *)g {' "$DN" > "$W/noteresize.txt"
grep -F 'DMNativeResized(' "$W/noteresize.txt" > "$W/noteline.txt" || true
check "-dm_noteResize: makes the note's frame in one line from DMNativeResized and the free area, shows it and keeps it when the finger lifts" \
  "[ \$(wc -l < '$W/noteline.txt') -eq 1 ] && grep -q '^    CGRect f = ' '$W/noteline.txt' && grep -qx '    DMStickySetFrame(ed, f, \"the editor resized\");' '$W/noteresize.txt' && grep -qF 'CGRect mine = [lay convertRect:[host convertRect:f toCoordinateSpace:scr]' '$W/noteresize.txt'"
{ echo 'static CGRect TNoteResized(CGRect start, CGPoint tr, int tag, CGRect desk) {'
  sed -e 's/_notes\.resizeStart/start/g' -e 's/\[g translationInView:host\]/tr/g' -e 's/(int)g\.view\.tag/tag/g' "$W/noteline.txt"
  echo '    return f;'; echo '}'; } > "$W/noteresize.h"
check "  ... that line takes only the grip's start, its translation, its tag and the area (nothing else of the method's)" \
  "! grep -qE '_notes|\\[g |g\\.view|self|ed\\.|host' '$W/noteresize.h' && grep -qF 'MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H' '$W/noteresize.h'"
check "  ... and the area is the desktop's free area (-dm_area) in the note's own space" \
  "grep -qF 'CGRect desk = [host convertRect:[lay convertRect:[self dm_area] toCoordinateSpace:' '$W/noteresize.txt'"

# a native window (Finder, TextEdit): -dm_resize:'s frame line, over the native desktop, and its let go
fnf '- (void)dm_resize:(UIPanGestureRecognizer *)g {' "$NW" > "$W/winresize.txt"
grep -F 'DMNativeResized(' "$W/winresize.txt" > "$W/winline.txt" || true
check "-dm_resize: (a native window) sets its frame in one line from DMNativeResized over the native desktop, nothing after it in the drag" \
  "[ \$(wc -l < '$W/winline.txt') -eq 1 ] && grep -q '^    self.frame = DMNativeResized(_panStart, d, (int)g.view.tag, self.minSize, DMNativeDesktop()' '$W/winline.txt' && [ \$(grep -cF 'self.frame = ' '$W/winresize.txt') -eq 1 ]"
{ echo 'static CGRect TWindowResized(CGRect start, CGPoint d, int tag, CGSize mn, CGRect desk) {'
  sed -e 's/self\.frame = /return /' -e 's/_panStart/start/g' -e 's/(int)g\.view\.tag/tag/g' -e 's/self\.minSize/mn/g' -e 's/DMNativeDesktop()/desk/g' "$W/winline.txt"
  echo '}'; } > "$W/winresize.h"
check "  ... it is let go through -dm_keepOutOfSideDock: with the moved side and the bottom, which takes DMDockSideKept's frame" \
  "grep -qF '[self dm_keepOutOfSideDock:(g.view.tag == 0 ? MSBDSnapLeft : MSBDSnapRight) | MSBDSnapBottom];' '$W/winresize.txt' && fnf '- (void)dm_keepOutOfSideDock:(unsigned)how {' '$NW' | grep -qF 'CGRect kept = DMDockSideKept(self.frame, how);'"
fnf 'static CGRect DMDockSideKept(CGRect window, unsigned how) {' "$SB" > "$W/kept.txt"
grep -F 'unsigned sides = ' "$W/kept.txt" > "$W/sidesline.txt" || true
check "DMDockSideKept picks the sides in one line, only with the Dock at a side, and keeps them out with MSBDDockSideKeepOut over the usable desktop" \
  "[ \$(wc -l < '$W/sidesline.txt') -eq 1 ] && grep -qF 'if (!DMDockSideKeepsOut() || CGRectIsNull(window)) return window;' '$W/kept.txt' && grep -qF 'CGRect s = MSBDDockSideKeepOut(window, DMUsableArea(), sides);' '$W/kept.txt' && grep -qF 'static CGRect DMNativeDesktop(void) { CGRect u = DMUsableArea();' '$NW'"
{ echo 'static unsigned TSidesFor(unsigned how) {'; cat "$W/sidesline.txt"; echo '    return sides;'; echo '}'; } > "$W/sides.h"
check "a native window's grips: 22 pt, their middle 6 pt in from its bottom corners (so a finger on the screen takes its side at most 17 pt past the screen's side)" \
  "grep -qF 'static const CGFloat kNWGrip = 22.0;' '$NW' && grep -qF '_gripL.frame = CGRectMake(-kNWGrip / 2.0 + 6.0, b.size.height - kNWGrip / 2.0 - 6.0, kNWGrip, kNWGrip);' '$NW' && grep -qF '_gripR.frame = CGRectMake(b.size.width - kNWGrip / 2.0 - 6.0, b.size.height - kNWGrip / 2.0 - 6.0, kNWGrip, kNWGrip);' '$NW'"

clang -O2 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -framework CoreGraphics -o "$W/tsg" test-stickygrip.m
"$W/tsg" || fails=1
[ $fails = 0 ] && echo "test-stickygrip: all passed" || echo "test-stickygrip: FAILED"
exit $fails
