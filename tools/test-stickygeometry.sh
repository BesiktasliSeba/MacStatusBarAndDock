#!/bin/bash
# Mac test of the geometry a sticky note gives its views (1.8.8.2). Rename from an idle note's menu raised in SpringBoard in 1.8.8.2's test build
# (CALayerInvalidGeometry: a selection grabber dot at a NaN position, on an iPad with the on-screen keyboard): the name field was made from the
# note's top bar with CGRectInset before the bar was laid out (CGRectNull: an infinite origin). The rules (common/StickyNotes.h, test-stickygeometry.m);
# UIKit itself on the Mac (Mac Catalyst, test-stickygeometry-ui.m): the old construction gives the device's exception, the real DMNoteBar with
# MSBDStickyNameFieldRect never does; then site checks of where DesktopNotes.h makes and lays out the field.
# The free area a note is placed in (Desktop.h -dm_area, cut out of it and run as written): never CGRectNull, also for a desktop not on its page yet.
# MSB_DN, MSB_N, MSB_D point it at copies of DesktopNotes.h, StickyNotes.h and Desktop.h: made-to-fail copies must each fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
DN=${MSB_DN:-../statusbar/DesktopNotes.h}; N=${MSB_N:-../common/StickyNotes.h}; D=${MSB_D:-../statusbar/Desktop.h}
mkdir -p "$W/common"; cp "$N" "$W/common/StickyNotes.h"
# (-dm_area as Desktop.h has it, up to its closing brace: run by test-stickygeometry.m in a stand-in desktop)
fnf '- (CGRect)dm_area {' "$D" > "$W/sg-area.inc"
grep -q '^- (CGRect)dm_area {' "$W/sg-area.inc" || { echo "FAIL  -dm_area was not found in $D"; fails=1; }
# ---- the rules ----
if clang -O2 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -framework CoreGraphics -o "$W/tsg" test-stickygeometry.m 2> "$W/cc.txt"; then
  "$W/tsg" || fails=1
else cat "$W/cc.txt" | head -5; echo "FAIL  the rules did not build"; fails=1; fi
# ---- UIKit (Mac Catalyst): the old construction and the real bar ----
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
if [ ! -d "$FW/UIKit.framework" ]; then echo "FAIL  no Mac Catalyst UIKit in $SDK"; fails=1
else
  # (DMNoteBar as DesktopNotes.h has it: its interface and its implementation, each up to its @end)
  awk '/^@interface DMNoteBar : UIView/ {f=1} /^@implementation DMNoteBar/ {f=1} f {print} f && /^@end/ {f=0}' "$DN" > "$W/sg-bar.inc"
  # (the setters: from DMStickyGeometryRefused to the end of DMStickySetBottomInset, as DesktopNotes.h has them)
  awk '/^__attribute__\(\(noinline\)\) static void DMStickyGeometryRefused\(/ {f=1} f {print} f && /^}/ && seen {exit} /static void DMStickySetBottomInset\(/ {seen=1}' "$DN" > "$W/sg-set.inc"
  if [ "$(grep -c '^@end' "$W/sg-bar.inc")" != 2 ]; then echo "FAIL  DMNoteBar was not found in $DN"; fails=1
  elif ! grep -q 'static void DMStickySetBottomInset(' "$W/sg-set.inc" || ! grep -q 'static void DMStickySetFrame(' "$W/sg-set.inc"; then echo "FAIL  the notes' geometry setters were not found in $DN"; fails=1
  else
    for dbg in 0 1; do
      if clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
           -fobjc-arc -Wall -Wno-unused-function -DDEBUG=$dbg -I"$W" -framework UIKit -framework CoreGraphics -o "$W/tsgu$dbg" test-stickygeometry-ui.m 2> "$W/ccu$dbg.txt"; then
        if [ -s "$W/ccu$dbg.txt" ]; then echo "FAIL  warnings (DEBUG=$dbg):"; cat "$W/ccu$dbg.txt"; fails=1; fi
        echo "-- $([ $dbg = 1 ] && echo DEBUG || echo release)"
        "$W/tsgu$dbg" 2> "$W/ui-err.txt"; r=$?
        [ $r = 0 ] || { echo "FAIL  the UIKit part ended with $r (DEBUG=$dbg)"; head -5 "$W/ui-err.txt"; fails=1; }
      else head -5 "$W/ccu$dbg.txt"; echo "FAIL  the UIKit part did not build (DEBUG=$dbg)"; fails=1; fi
    done
  fi
fi
# ---- the sites ----
RN=$(fnf '- (void)dm_noteRename:(NSString *)noteId {' "$DN")
check "Rename: the editor is laid out before the field is made (an idle note's editor is a moment old: its bar's bounds were zero)" \
  "printf '%s\n' \"\$RN\" | awk '/\\[ed layoutIfNeeded\\];/{a=NR} /DMNoteNameField \\*tf = \\[\\[DMNoteNameField alloc\\] initWithFrame:/{b=NR} END{exit !(a && b == a + 1)}'"
check "  ... the field's frame is MSBDStickyNameFieldRect of the bar's bounds (never CGRectInset: CGRectNull for a zero bar), and no autoresizing" \
  "printf '%s\n' \"\$RN\" | grep -qF 'DMNoteNameField *tf = [[DMNoteNameField alloc] initWithFrame:DMStickyFrame(MSBDStickyNameFieldRect(ed.band.bounds), \"the name field made\")];' \
   && ! grep -qF 'CGRectInset(ed.band' '$DN' && ! printf '%s\n' \"\$RN\" | grep -qF 'autoresizingMask'"
check "  ... the bar knows its field and lays it out from its own bounds; Rename's end lets it go" \
  "printf '%s\n' \"\$RN\" | grep -qF 'ed.band.field = tf; [ed.band addSubview:tf];' \
   && grep -qF '@property (nonatomic, weak) UITextField *field;' '$DN' \
   && fnf '- (void)dm_noteRenameEnd:(BOOL)keep refocus:(BOOL)refocus {' '$DN' | grep -qF '[tf removeFromSuperview]; if (ed.band.field == tf) ed.band.field = nil;'"
# (every frame, centre, transform and inset the notes' code sets, and every frame a view of theirs is made with, goes through the setters; only
#  the setters themselves set them; a view made at CGRectZero is laid out later through them)
RAW=$(awk '/^__attribute__\(\(noinline\)\) static void DMStickyGeometryRefused\(/ {skip=1} skip && /static void DMStickySetBottomInset\(/ {inb=1} {if (!skip) print FNR": "$0} skip && inb && /^}/ {skip=0; inb=0}' "$DN" \
  | grep -E '\.frame = |\.center = |\.transform = |contentInset = |\.bounds = |setFrame:|setCenter:|setTransform:' )
check "every frame, centre, transform and inset the notes give a view goes through DMStickySetFrame, DMStickySetCenter, DMStickySetTransform, DMStickySetBottomInset" \
  "[ -z \"\$RAW\" ] && [ \$(grep -c 'DMStickySetFrame(' '$DN') -ge 18 ]" || printf '%s\n' "$RAW" | head -5
MADE=$(grep -n 'initWithFrame:' "$DN" | grep -vE 'initWithFrame:DMStickyFrame\(|initWithFrame:CGRectZero\]|\(instancetype\)initWithFrame:\(CGRect\)frame|\[super initWithFrame:frame\]')
check "  ... and every view the notes make gets its frame through DMStickyFrame (or CGRectZero, laid out after)" "[ -z \"\$MADE\" ] && [ \$(grep -c 'initWithFrame:DMStickyFrame(' '$DN') -ge 6 ]" || printf '%s\n' "$MADE" | head -5
GR=$(fnf '__attribute__((noinline)) static void DMStickyGeometryRefused(const char *site, NSString *value) {' "$DN")
check "  ... the setters refuse what MSBDStickyRectOK, MSBDStickyPointOK, MSBDStickyTransformOK refuse; DEBUG logs it naming the value and the site, never raises; release keeps the view" \
  "grep -qF 'static void DMStickySetFrame(UIView *v, CGRect f, const char *site) { if (MSBDStickyRectOK(f)) v.frame = f; else DMStickyGeometryRefused(site, NSStringFromCGRect(f)); }' '$DN' \
   && printf '%s\n' \"\$GR\" | grep -qF 'DMLog([NSString stringWithFormat:@\"[notes] ASSERTION: a geometry that is not finite (%@) refused at %s\", value, site]);' \
   && ! printf '%s\n' \"\$GR\" | grep -qE 'NSException|raise|abort|assert\\(|__builtin_trap' && ! grep -q 'MSBDStickyNonFiniteGeometry' '$DN'"
[ $fails = 0 ] && echo "test-stickygeometry: all passed" || echo "test-stickygeometry: FAILED"
exit $fails
