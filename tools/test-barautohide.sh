#!/bin/bash
# Mac test of Automatically Hide and Show the Menu Bar per display (1.8.7 row 14; common/BarAutoHide.h, test-barautohide.c), then the sites in
# SpringBoard's status bar part: the iPad's machine moves only the iPad's copies, the TV's own state by its own setting and pointer, its strip in the
# per-scene layer helper, a copy by its own display's state, no window moved for the TV. Each site check is a function of the file it reads, so a copy
# with one site broken runs the same check: those made-to-fail copies, last, must each fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/t" test-barautohide.c && "$W/t" || fails=1
check() { if (eval "$2"); then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
S=../statusbar/StatusBar.x
c_split() {   # the iPad's machine moves the iPad's copies only; a TV's copies by the TV's state
  fn 'static NSArray<UIView *> *DMStatusBarsToMoveOn(int which) {' "$1" | grep -qF 'if ((which == 0 && other) || (which == 1 && !other)) continue;' \
    && grep -qF 'static NSArray<UIView *> *DMStatusBarsToMove(void) { return DMStatusBarsToMoveOn(0); }' "$1" \
    && fn 'static void DMAutoHideTVApply(NSString *why) {' "$1" | grep -qF 'for (UIView *b in bars) DMStatusBarApplyOffset(b, MSBDBarAHCopyOffset(&gDMTVBarAH, MIN(40.0, b.bounds.size.height)), YES);' \
    && fn 'static void DMAutoHideTVApply(NSString *why) {' "$1" | grep -qF 'NSArray *bars = DMStatusBarsToMoveOn(1);'
}
c_tv_state() {   # the TV's own state: its setting (msb autoHideStatusBar for that display, the iPad's until changed), a pointer, not locked; hides by the rule
  grep -qF 'static BOOL DMAutoHideTVSetting(UIScreen *tv) { return tv && !gStockBar && DMDispBool(tv, "msb", "autoHideStatusBar", DMAutoHidePref()); }' "$1" \
    && fn 'static void DMAutoHideTVTick(void) {' "$1" > "$W/tt" && grep -qF 'BOOL on = MSBDBarAHActive(DMAutoHideTVSetting(tv), DMAutoHidePointerAttached(), DMLockUp(lm));' "$W/tt" \
    && grep -qF 'if (MSBDBarAHShouldHide(&gDMTVBarAH, DMMenuOpenOnTV(), now)) { gDMTVBarAH.hidden = 1; DMAutoHideTVApply(@"the pointer left the TV' "$W/tt" \
    && grep -qF 'if (gDMTVBarAH.hidden) for (UIView *b in bars) DMStatusBarApplyOffset(b, MSBDBarAHCopyOffset(&gDMTVBarAH' "$W/tt" \
    && awk '/^@implementation DMStatusBarHover$/,/^@end$/' "$1" | grep -qF 'if (DMExternalScreenOf(g.view)) { DMAutoHideTVPointer(inside, [g locationInView:g.view], g.view.bounds.size); return; }'
}
c_fade() {   # a TV copy's hover that ends with the pointer still well inside the bar is a fade (iPadOS hid the idle pointer): on the bar until it moves
  fn 'static void DMAutoHideTVPointer(BOOL inside, CGPoint at, CGSize bar) {' "$1" > "$W/fa" && grep -qF 'if (gDMTVBarAH.pointerIn && MSBDBarAHEndIsFade(at.x, at.y, bar.width, bar.height)) {' "$W/fa" \
    && awk '/^@implementation DMStatusBarHover$/,/^@end$/' "$1" | grep -qF 'DMAutoHideTVPointer(inside, [g locationInView:g.view], g.view.bounds.size);' \
    && fn 'static void DMAutoHideTVTick(void) {' "$1" > "$W/ft" && grep -qF 'BOOL moved = !isnan(gDMTVFadePos.x) && !isnan(gDMTVPtrNow.x) && MSBDBarAHMovedAfterFade(gDMTVPtrNow.x - gDMTVFadePos.x, gDMTVPtrNow.y - gDMTVFadePos.y);' "$W/ft" \
    && awk '/BOOL moved = !isnan\(gDMTVFadePos.x\)/{a=NR} /    if \(!gDMTVBarAH.on\) return;/{b=NR} END{exit !(a && b && a < b)}' "$W/ft"   # (resolved with the TV's own off too: d09)
}
c_strip() {   # the TV's strip: in the per-scene layer helper, on while the TV's bar is hidden, its hover brings the bar
  fn 'static void DMAutoHideTVStrip(BOOL on) {' "$1" > "$W/st" && grep -qF 'DMSceneLayer(tv, @"autohide-strip", kMenuWindowLevel - 5.0, (DMSceneLayerKind){ "MSBSceneStripWindow", (IMP)DMSceneStripHitTest, NULL, "autohide" }, nil)' "$W/st" \
    && grep -qF 'strip.frame = CGRectMake(0, 0, w.bounds.size.width, kMSBDBarAHStripH);' "$W/st" && fn 'static void DMAutoHideTVApply(NSString *why) {' "$1" | grep -qF 'DMAutoHideTVStrip(gDMTVBarAH.hidden);' \
    && grep -qF 'if (inside && MSBDBarAHReveal(&gDMTVBarAH, CACurrentMediaTime())) DMAutoHideTVApply(@"the pointer reached the TV' "$1"
}
c_ipad() {   # the iPad's machine: as before, run with the TV's in the same tick; its zone not read with the pointer on a TV's bar; a TV menu holds only the TV's
  fn 'static void DMAutoHideTick(void) {' "$1" > "$W/it" && awk '/    DMAutoHideTVTick\(\);/{a=NR} /    if \(!active\) \{ gSBZone = 0; return; \}/{b=NR} END{exit !(a && b > a)}' "$W/it" \
    && grep -qF '(!gOverlay || DMMenuOpenOnTV())' "$W/it" && fn 'static void DMAutoHideSetZone(uint64_t z) {' "$1" | grep -qF 'z = MSBDBarAHIPadZone(z, DMAutoHidePointerOnTV());' \
    && fn 'static void DMAutoHideRefreshTimer(void) {' "$1" | grep -qF 'BOOL on = DMAutoHidePref() || DMAutoHideTVSetting(DMAutoHideTVScreen());'
}
c_no_window() {   # the TV's machine moves no window (Stage Manager parity): none of the window movers in it
  for f in 'static void DMAutoHideTVApply(NSString *why) {' 'static void DMAutoHideTVTick(void) {'; do
    fn "$f" "$1" | grep -qE 'DMStatusBarMoveWindows|DMAutoHideRetopAll|DMAerialMoveStage|DMSMRequestWindow|DMSMApply' && return 1
  done
  grep -qF '#include "../common/BarAutoHide.h"' "$1"
}
check "the iPad's machine moves only the iPad's bar copies; a TV's by the TV's own state (each copy its own display's)" "c_split $S"
check "the TV's own state: its own setting (the iPad's until changed), a pointer, not on the Lock Screen; it hides by the rule; a new copy hidden like its display's" "c_tv_state $S"
check "the TV's bar: a hover ended with the pointer still on it is a fade (iPadOS hid the idle pointer), kept until the pointer moves (A12Z, d07)" "c_fade $S"
check "the TV's top-edge strip in the per-scene layer helper, on while its bar is hidden; its hover brings the bar" "c_strip $S"
check "the iPad's machine as before, with the TV's in the same tick; its zone not read while the pointer is on a TV's bar; a TV's menu holds only the TV's bar; the tick runs for either setting" "c_ipad $S"
check "the TV's bar hides with no window moved (as the iPad's Stage Manager engine)" "c_no_window $S"
check "crash rules: the TV's auto-hide functions are the auto-hide's (^_?DMAutoHide), the strip's hit test in its section" "grep -q '^sym MacStatusBarCore \^_?DMAutoHide autoHideStatusBar\$' crashmap-rules.txt && [ \$(grep -cE '^static [A-Za-z]+ \**DMAutoHideTV[A-Za-z]*\(' $S) -ge 5 ]"
mutant() {   # <name> <file> <old> <new> <check function>
  local M="$W/m-$1"; mkdir -p "$M"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' "$2" "$M/f" "$3" "$4" || return 1
  ! $5 "$M/f" 2>/dev/null
}
check "made to fail: the iPad's machine moving every display's copies (1.8.6's one bar for both)" "mutant split $S 'static NSArray<UIView *> *DMStatusBarsToMove(void) { return DMStatusBarsToMoveOn(0); }' 'static NSArray<UIView *> *DMStatusBarsToMove(void) { return DMStatusBarsToMoveOn(2); }' c_split"
check "made to fail: the TV's setting read as the iPad's" "mutant tvset $S 'DMDispBool(tv, \"msb\", \"autoHideStatusBar\", DMAutoHidePref())' 'DMAutoHidePref()' c_tv_state"
check "made to fail: a TV copy's hover taken as the iPad's" "mutant tvhover $S '    if (DMExternalScreenOf(g.view)) { DMAutoHideTVPointer(inside, [g locationInView:g.view], g.view.bounds.size); return; }   // (1.8.7 row 14: a TV'\''s copy -- that display'\''s state)
' '' c_tv_state"
check "made to fail: every ended hover taken as the pointer leaving (a resting pointer's fade hid the bar)" "mutant fade $S 'if (gDMTVBarAH.pointerIn && MSBDBarAHEndIsFade(at.x, at.y, bar.width, bar.height)) {' 'if (0) {' c_fade"
check "made to fail: a fade on the TV's bar resolved only while the TV's own is on (the iPad's zone kept unread for good, d09)" "mutant fadeoff $S '    if (!gDMTVBarAH.on) return;
' '    if (!gDMTVBarAH.on) return;
    BOOL moved = !isnan(gDMTVFadePos.x) && !isnan(gDMTVPtrNow.x) && MSBDBarAHMovedAfterFade(gDMTVPtrNow.x - gDMTVFadePos.x, gDMTVPtrNow.y - gDMTVFadePos.y);
' c_fade"
check "made to fail: the TV's strip never shown" "mutant strip $S '    DMAutoHideTVStrip(gDMTVBarAH.hidden);
' '' c_strip"
check "made to fail: the iPad's zone read with the pointer on the TV's top" "mutant zone $S '    z = MSBDBarAHIPadZone(z, DMAutoHidePointerOnTV());   // (1.8.7: the pointer on a TV'\''s bar or strip is not on the iPad'\''s)
' '' c_ipad"
check "made to fail: the TV's tick only while the iPad's is on (after its early return)" "mutant tick $S '    DMAutoHideTVTick();   // (1.8.7 row 14: the TV'\''s own bar, by its own setting)
    if (!active) { gSBZone = 0; return; }' '    if (!active) { gSBZone = 0; return; }
    DMAutoHideTVTick();' c_ipad"
check "made to fail: the TV's windows moved down with its bar" "mutant windows $S '    DMAutoHideTVStrip(gDMTVBarAH.hidden);
' '    DMAutoHideTVStrip(gDMTVBarAH.hidden);
    DMStatusBarMoveWindows(!gDMTVBarAH.hidden, 37.0, YES);
' c_no_window"
[ $fails = 0 ] && echo "test-barautohide: all checks pass" || { echo "test-barautohide: checks FAILED"; exit 1; }
