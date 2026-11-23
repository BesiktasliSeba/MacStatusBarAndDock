#!/bin/bash
# Mac test of where a sticky note is shown when its Home Screen page has no clear frame of its size (1.8.8.2): the rules (common/StickyNotes.h
# MSBDStickyPlaceClearFit and MSBDStickyTrimClear, test-stickyfit.m, with the numbers of a device pass where the Dock set at a side left a note
# under an app icon) and site checks that every place a note is put uses it (page 1's and the other pages' layouts, the drop, the top bar's move,
# Move to Page) and stores the centre of its own size's frame. MSB_DN, MSB_N point it at copies of DesktopNotes.h and StickyNotes.h.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
DN=${MSB_DN:-../statusbar/DesktopNotes.h}; N=${MSB_N:-../common/StickyNotes.h}
mkdir -p "$W/common"; cp "$N" "$W/common/StickyNotes.h"
if clang -O2 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -framework CoreGraphics -o "$W/tsf" test-stickyfit.m 2> "$W/cc.txt"; then
  "$W/tsf" || fails=1
else head -5 "$W/cc.txt"; echo "FAIL  the rules did not build"; fails=1; fi
# ---- the sites ----
PF=$(fnf '__attribute__((noinline)) static CGRect DMStickyPlaceFit(CGRect f, CGRect area, const CGRect *r, int n, CGRect *anchor, NSString *noteId) {' "$DN")
check "DMStickyPlaceFit: MSBDStickyPlaceClearFit with the note's minimum and the rect tests' cap; says when a note is shown smaller (its size kept)" \
  "printf '%s\n' \"\$PF\" | grep -qF 'CGRect a, out = MSBDStickyPlaceClearFit(f, area, r, n, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), MSBD_NOTE_CLEAR_TESTS, &a);' \
   && printf '%s\n' \"\$PF\" | grep -qF 'if (anchor) *anchor = a;' && printf '%s\n' \"\$PF\" | grep -qF 'DM_FEATURE_MARK(\"sticky-note-fit\");'"
check "  ... every place a note is put goes through it: no MSBDStickyPlaceClear left in DesktopNotes.h" \
  "! grep -q 'MSBDStickyPlaceClear(' '$DN' && [ \$(grep -c 'DMStickyPlaceFit(' '$DN') = 6 ]"
check "  ... page 1's layout and every other page's" \
  "fnf '- (void)dm_noteLayoutIn:(CGRect)area {' '$DN' | grep -qF 'f = DMStickyPlaceFit(f, area, r, (int)occ.count, NULL, v.noteId);' \
   && fnf '- (void)dm_noteLayoutPage:(NSUInteger)page layer:(UIView *)layer {' '$DN' | grep -qF 'f = DMStickyPlaceFit(f, area, r, (int)occ.count, NULL, v.noteId);'"
DR=$(fnf '- (void)dm_noteDropAt:(CGPoint)sp {' "$DN"); MV=$(fnf '- (void)dm_noteMove:(UIPanGestureRecognizer *)g {' "$DN"); TP=$(fnf '- (void)dm_noteToPage:(NSUInteger)page of:(NSString *)noteId {' "$DN")
check "  ... the drop, the top bar's move and Move to Page: the note at its own stored size where it was put (DMStickyAtItsSize), its own size's centre stored" \
  "printf '%s\n' \"\$DR\" | grep -qF 'CGRect anchor, f = DMStickyPlaceFit(DMStickyAtItsSize(e, start, area), area, r, (int)occ.count, &anchor, v.noteId);' \
   && printf '%s\n' \"\$DR\" | grep -qF 'NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor)) area:area];' \
   && printf '%s\n' \"\$MV\" | grep -qF 'CGRect anchor, placed = DMStickyPlaceFit(DMStickyAtItsSize(e, mine, area), area, r, (int)occ.count, &anchor, ed.noteId);' \
   && printf '%s\n' \"\$MV\" | grep -qF 'NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor)) area:area];' \
   && printf '%s\n' \"\$TP\" | grep -qF 'CGRect anchor, f = DMStickyPlaceFit(DMStickyAtItsSize(e, v.frame, area), area, r, (int)occ.count, &anchor, noteId);' \
   && printf '%s\n' \"\$TP\" | grep -qF 'NSArray *c = [self dm_fractionFor:CGPointMake(CGRectGetMidX(anchor), CGRectGetMidY(anchor)) area:area];'"
check "  ... DMStickyAtItsSize: the stored size centred where it was put (MSBDStickyFrameAt), as the layout makes it" \
  "fnf '__attribute__((noinline)) static CGRect DMStickyAtItsSize(NSDictionary *e, CGRect put, CGRect area) {' '$DN' | grep -qF 'return MSBDStickyFrameAt(area, CGPointMake(CGRectGetMidX(put), CGRectGetMidY(put)), CGSizeMake([e[@\"w\"] doubleValue], [e[@\"h\"] doubleValue]));'"
check "  ... and the size stored by a resize is still the frame the finger left (a note shown smaller is resized from what shows)" \
  "fnf '- (void)dm_noteResize:(UIPanGestureRecognizer *)g {' '$DN' | grep -qF 'e[@\"w\"] = @(mine.size.width); e[@\"h\"] = @(mine.size.height);'"
[ $fails = 0 ] && echo "test-stickyfit: all passed" || echo "test-stickyfit: FAILED"
exit $fails
