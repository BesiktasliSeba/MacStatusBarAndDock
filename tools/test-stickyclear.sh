#!/bin/bash
# Mac test of a sticky note's resize against the page's app icons, widgets and page dots (1.8.8.2 B72 full fix; B83's corner findings): the
# grip's moving side and the bottom stop where the note would meet them, so the let go (the layout's MSBDStickyPlaceClear, MSBDStickyPlaceClearFit
# where the tree has it) never moves the note.
# Built from the source as written: DMNativeResized cut out of statusbar/NativeWindow.h; -dm_noteResize:'s frame lines (statusbar/DesktopNotes.h)
# made into one function, with its stop at the occupied rects when the source has it (1.8.8.1.1 had none: then the function is 1.8.8.1.1's, and
# the checks show the device's numbers). MSB_NW, MSB_DN, MSB_N point it at copies of NativeWindow.h, DesktopNotes.h and common/StickyNotes.h:
# that is how made-to-fail copies are run against it, each of which must fail.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
NW=${MSB_NW:-../statusbar/NativeWindow.h}; DN=${MSB_DN:-../statusbar/DesktopNotes.h}; N=${MSB_N:-../common/StickyNotes.h}
mkdir -p "$W/common"; cp "$N" "$W/common/StickyNotes.h"

awk '/^static CGRect DMNativeResized\(/{f=1} f{print} f&&/^}/{exit}' "$NW" > "$W/resized.h"
check "DMNativeResized is in NativeWindow.h as one function (the test builds it from there)" "[ \$(wc -l < '$W/resized.h') -ge 8 ] && grep -q 'return f;' '$W/resized.h'"
fnf '- (void)dm_noteResize:(UIPanGestureRecognizer *)g {' "$DN" > "$W/noteresize.txt"
grep -F 'DMNativeResized(' "$W/noteresize.txt" > "$W/line1.txt" || true
grep -F 'f = DMStickyResizeClear(' "$W/noteresize.txt" > "$W/line2.txt" || true
check "-dm_noteResize: makes the note's frame from DMNativeResized in one line" "[ \$(wc -l < '$W/line1.txt') -eq 1 ] && grep -q '^    CGRect f = MSBDStickyClampInside(DMNativeResized(' '$W/line1.txt'"
check "  ... then stops it at the page's app icons, widgets and page dots in the next line, before the editor is set to it" \
  "[ \$(wc -l < '$W/line2.txt') -eq 1 ] && grep -qxF '    f = DMStickyResizeClear(_notes.resizeStart, f, (int)g.view.tag, [self dm_noteOccupiedIn:host]);' '$W/line2.txt' \
   && awk '/CGRect f = MSBDStickyClampInside\\(DMNativeResized\\(/{a=NR} /f = DMStickyResizeClear\\(/{b=NR} /^    DMStickySetFrame\\(ed, f, \"the editor resized\"\\);/{c=NR} END{exit !(a && b == a + 1 && c == b + 1)}' '$W/noteresize.txt'"
check "  ... with the note's minimum and every rect given (DMStickyResizeClear), the rects the layout keeps notes clear of (-dm_occupied), in the editor's space" \
  "fnf '__attribute__((noinline)) static CGRect DMStickyResizeClear(CGRect start, CGRect want, int tag, NSArray<NSValue *> *occ) {' '$DN' | grep -qF 'CGRect f = MSBDStickyResizeClear(start, want, tag, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), r, (int)occ.count);' \
   && fnf '- (NSArray<NSValue *> *)dm_noteOccupiedIn:(UIView *)host {' '$DN' | grep -qF '[host convertRect:[lay convertRect:r.CGRectValue toCoordinateSpace:mine] fromCoordinateSpace:theirs]' \
   && fnf '- (NSArray<NSValue *> *)dm_noteOccupiedIn:(UIView *)host {' '$DN' | grep -qF 'for (NSValue *r in [self dm_occupiedIn:[self dm_noteListOfPage:[self dm_notePageOfLayer:lay]] into:lay])' \
   && fnf '- (void)dm_noteLayoutIn:(CGRect)area {' '$DN' | grep -qE '^        f = (MSBDStickyPlaceClear\\(f, area, r, \\(int\\)occ.count, MSBD_NOTE_CLEAR_TESTS, NULL\\)|DMStickyPlaceFit\\(f, area, r, \\(int\\)occ.count, NULL, v.noteId\\));'"
check "  ... and at the let go the note is stored as its frame (the centre's share, the size as shown: never rounded) and laid out again" \
  "grep -qF 'e[@\"x\"] = c[0]; e[@\"y\"] = c[1]; e[@\"w\"] = @(mine.size.width); e[@\"h\"] = @(mine.size.height);' '$W/noteresize.txt' && grep -qF '[self dm_placeAgain]; [self layoutIfNeeded];' '$W/noteresize.txt'"
# (the frame lines as a function: the start, the translation, the tag, the area and the rects; without the second line, 1.8.8.1.1's)
{ echo 'static CGRect TNoteResized(CGRect start, CGPoint tr, int tag, CGRect desk, const CGRect *rects, int n) {'
  sed -e 's/_notes\.resizeStart/start/g' -e 's/\[g translationInView:host\]/tr/g' -e 's/(int)g\.view\.tag/tag/g' "$W/line1.txt"
  sed -e 's/f = DMStickyResizeClear(_notes\.resizeStart, f, (int)g\.view\.tag, \[self dm_noteOccupiedIn:host\]);/f = MSBDStickyResizeClear(start, f, tag, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), rects, n);/' "$W/line2.txt"
  echo '    (void)rects; (void)n; return f;'; echo '}'; } > "$W/noteresize.h"
[ -s "$W/line2.txt" ] && echo '#define T_HAS_CLEAR 1' >> "$W/noteresize.h"
grep -q 'static inline CGRect MSBDStickyPlaceClearFit(' "$N" && echo '#define T_HAS_FIT 1' >> "$W/noteresize.h"   # (1.8.8.2: the layout's rule is the fitting one: test-stickyfit)
check "  ... those lines take only the grip's start, its translation, its tag, the area and the rects" "! grep -qE '_notes|\\[g |g\\.view|self|ed\\.|host' '$W/noteresize.h'"
clang -O2 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -framework CoreGraphics -o "$W/tsc" test-stickyclear.m
"$W/tsc" || fails=1
[ $fails = 0 ] && echo "test-stickyclear: all passed" || echo "test-stickyclear: FAILED"
exit $fails
