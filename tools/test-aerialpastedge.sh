#!/bin/bash
# test-aerialpastedge.sh: an Aerial window (5.x and 3.0) dragged past the screen's left, right and bottom edges goes there as on every engine, only
# its title bar's top held under the menu bar, and stays (1.8.8.3, GitHub #19); a window in Aerial's Lock stays where it is, no snap at the end of a
# drag (1.8.8.4): see test-aerialpastedge.m. The real code is cut out of
# statusbar/StatusBar.x (APE_SB_X: another copy, e.g. the code before the change): Aerial 5's drag section (from its header to the end of
# DMA5DragGuard's implementation), Aerial 3.0's drag steps (DMAerialPanBefore ... DMAerialGestureAfter) and its %hook AerialStage -handlePan: body,
# DMRememberStageFrame with DMSetStageIntent, DMKeepStagePlace and DMAerial5SyncState, DMA5WindowFromStage; UIKit's main screen as the code asks it
# ([UIScreen mainScreen].bounds) is the test's screen. Run on the Mac (Mac Catalyst); then the site checks; then made-to-fail copies: each breaks
# one part and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${APE_SB_X:-../statusbar/StatusBar.x}; T0=../statusbar/TitleBarTap.h
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }    # one function of a file, from its first line
blockcut() { awk 'index($0, "// A drag by hand. NO: the drag was cancelled here") == 1 {f=1} f {print} f && index($0, "static void DMAerialGestureAfter(") == 1 {g=1} g && /^[}]/ {exit}' "$1"; }
dragcut() { awk 'index($0, "// ---- Aerial 5.0: a window moves by its title strip only") == 1 {f=1} f {print} f && index($0, "@implementation DMA5DragGuard") == 1 {g=1} g && /^@end/ {exit}' "$1"; }
CHAIN=('static void DMAerial5SyncState(UIView *stage, CGRect frame) {' 'static void DMKeepStagePlace(UIView *stage, CGRect frame) {'
       'static void DMSetStageIntent(UIView *stage, CGRect frame) {' 'static void DMRememberStageFrame(UIView *stage) {' 'static CGRect DMA5WindowFromStage(CGRect f) {')
PAN='- (void)handlePan:(id)gesture {'
# (1.8.8.4 review: the 0.2 s watcher's "a move or a resize by hand under way", whose end keeps the place, leaves Fit's tiles and saves)
LIVE=('static BOOL DMAerial5GestureLive(UIView *stage) {' 'static BOOL DMAerial5HandGestureLive(UIView *stage) {')
WATCH='static void DMAerial5Watch(void) {'
scr() { sed 's/\[UIScreen mainScreen\]\.bounds/KScreenBounds()/g'; }

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out
  mkdir -p "$d"
  for h in "${CHAIN[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  [ "$(grep -cF -e "$PAN" "$X")" = 1 ] || { echo "FAIL  $X: not one \"$PAN\""; return 99; }
  [ -n "$(blockcut "$X")" ] || { echo "FAIL  $X: no DMAerialPanBefore ... DMAerialGestureAfter"; return 99; }
  dragcut "$X" | grep -q '^@implementation DMA5DragGuard' || { echo "FAIL  $X: no Aerial 5 drag section"; return 99; }
  for h in "${CHAIN[@]}"; do fn "$X" "$h"; done | scr > "$d/ape-chain.inc"
  blockcut "$X" | scr > "$d/ape-30.inc"
  dragcut "$X" | scr > "$d/ape-drag.inc"
  for h in "${LIVE[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  for h in "${LIVE[@]}"; do fn "$X" "$h"; done > "$d/ape-live.inc"
  awk -v h="$PAN" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$X" | sed 's/^\( *\)%orig;/\1[self k_origPan:gesture];/' > "$d/ape-hook.inc"
  grep -q '%orig' "$d/ape-hook.inc" && { echo "FAIL  $X: a %orig left in the hook cut out"; return 99; }
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-aerialpastedge.m 2>"$d/cc.txt" \
    || { cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -n "$q" ] || cat "$d/cc.txt"
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (the site checks) the hook run is Aerial 3.0's real-named one (%group AerialStyleNamed, %hook AerialStage) and the 5.0 reference h5_pan does the
  # same: where its drag began noted before Aerial's step, the follow after it; Aerial 5's two targets are the ones DMAerial5DragGuard adds (the
  # stage recogniser's after Aerial's own, the drag area's on every look)
  if awk -v p="$PAN" '/^%group AerialStyleNamed/{g=1} g && /^%hook AerialStage/{h=1} h && index($0, p) == 1 {a=1} h && /^%end/{exit} END{exit !a}' "$X" \
     && [ "$(grep -cF 'DMAerialPanFollow((UIView *)self, gesture, NO);' "$X")" = 2 ] && [ "$(grep -cF 'DMAerialPanFollow((UIView *)self, gesture, YES);' "$X")" = 2 ] \
     && awk '/^static void h5_pan\(id self, SEL _cmd, id gesture\) \{/{f=1} f && /DMAerialPanFollow\(\(UIView \*\)self, gesture, NO\);/{a=NR} f && /if \(o5_pan\) o5_pan\(self, _cmd, gesture\);/{b=NR} f && /DMAerialPanFollow\(\(UIView \*\)self, gesture, YES\);/{c=NR} f && /^[}]/{exit} END{exit !(a && b && c && a < b && b < c)}' "$X" \
     && grep -qF '[drag addTarget:[DMA5DragGuard shared] action:@selector(dragTrace:)];' "$X" && grep -qF '[a addTarget:[DMA5DragGuard shared] action:@selector(areaDrag:)];' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: Aerial 3.0's -handlePan: hook and h5_pan note the start before Aerial's step and follow after it; Aerial 5's targets are DMAerial5DragGuard's"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the Aerial drag sites are not as tested"; n=$((n + 1)); fi
  # (1.8.8.3 review) Aerial 3.0's touch-down: our title strip's double tap notes every touch it is offered on an Aerial window, before its strip check
  if awk '/^- \(BOOL\)gestureRecognizer:\(UIGestureRecognizer \*\)g shouldReceiveTouch:\(UITouch \*\)touch \{$/{f=1} f && /== kDMTitleAerial\) DMAerial30NoteDown\(g.view, touch\);$/{a=NR} f && /if \(!DMTitleTapOnBar\(g, touch\)\) return NO;/{b=NR} f && /^[}]/{exit} END{exit !(a && b && a < b)}' "$T0"; then
    [ -n "$q" ] || echo "PASS  TitleBarTap.h: the title strip's double tap notes each touch on an Aerial window (Aerial 3.0's touch-down) before its strip check"
  else [ -n "$q" ] || echo "FAIL  TitleBarTap.h: Aerial 3.0's touch-down is not noted where every touch on its window comes"; n=$((n + 1)); fi
  # (1.8.8.4 review) the 0.2 s watcher takes a pan for a move by hand only by DMAerial5HandGestureLive (not on a window in Aerial's Lock), and its
  # end is the one that keeps the place, leaves Fit's tiles and saves
  if fn "$X" "$WATCH" | grep -qF 'BOOL live = DMAerial5HandGestureLive(stage), was = [objc_getAssociatedObject(stage, kA5GestureKey) boolValue];' \
     && fn "$X" "$WATCH" | awk '/\} else if \(!live && was\) \{/{f=1} f && /DMFitGroupForget\(bundle\);/{a=1} f && /DMSaveWindowState\(\);/{b=1} END{exit !(a && b)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: Aerial 5's 0.2 s watcher counts a move by hand by DMAerial5HandGestureLive (a locked window's drag is none), its end keeps the place, leaves Fit's tiles and saves"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: Aerial 5's 0.2 s watcher does not count a move by hand as tested"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$APE_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x (-0: the whole file)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the sides held again (the drawn window kept on the screen, as 1.7.5 had it)" 's/want = CGPointMake\(c0\.x \+ dx, /want = CGPointMake(MAX(stage.frame.size.width \/ 2.0 - 6.0, MIN(c0.x + dx, stage.superview.bounds.size.width - stage.frame.size.width \/ 2.0 + 6.0)), /'
  mtf "y left to Aerial after the start (as 1.7.5 had it)" 's/MAX\(c0\.y \+ dy, DMAerialDragTop\(\) \+ stage\.frame\.size\.height \/ 2\.0\)\);/(began ? c0.y + dy : c.y));/'
  mtf "the top not held by the follow" 's/MAX\(c0\.y \+ dy, DMAerialDragTop\(\) \+ stage\.frame\.size\.height \/ 2\.0\)\);/c0.y + dy);/'
  mtf "3.0's top left to Aerial (the screen's top)" 's/\(DMA5MacGeometry\(\) \|\| gAerialFlavor == 3\) \? DMTopLimit\(\) : 0\.0;/DMA5MacGeometry() ? DMTopLimit() : 0.0;/'
  mtf "the place not kept at the end of a drag by its stage recogniser" 's/\n    if \(\(g\.state == UIGestureRecognizerStateEnded \|\| g\.state == UIGestureRecognizerStateCancelled\) && stage\.superview\) DMRememberStageFrame\(stage\);//'
  mtf "the place not kept at the end of a drag area's drag" 's/\n    DMSnapMoveEnded\(stage\);\n    DMRememberStageFrame\(stage\);\n\}/\n    DMSnapMoveEnded(stage);\n}/'
  mtf "a drag cut short not followed (its stage recogniser)" 's/ \|\| st == UIGestureRecognizerStateEnded \|\| st == UIGestureRecognizerStateCancelled\)/ || st == UIGestureRecognizerStateEnded)/'
  mtf "a drag cut short not followed (the drag area)" 's/if \(g\.state == UIGestureRecognizerStateEnded \|\| g\.state == UIGestureRecognizerStateCancelled\) DMA5DragFollow\(stage, g, NO\);/if (g.state == UIGestureRecognizerStateEnded) DMA5DragFollow(stage, g, NO);/'
  mtf "Aerial 5: a locked window's drag taken as a move by hand (its stage recogniser)" 's/\n    if \(DMAerialLockedDrag\(stage, g\)\) return;   \/\/ \(Aerial.s Lock: no move by hand[^\n]*//'
  mtf "Aerial 5.1: a locked window's drag taken as a move by hand (its drag area)" 's/\n    if \(DMAerialLockedDrag\(stage, g\)\) return;   \/\/ \(as -dragTrace:\)//'
  mtf "Aerial 3.0: a locked window's drag marked as one by hand" 's/\n        if \(DMAerialStageLocked\(stage\)\) \{ DMAerialLockedNote\(stage\); return YES; \}//'
  mtf "Aerial's Lock never read (its reader always says unlocked)" 's/return iv && \*\(\(uint8_t \*\)\(__bridge void \*\)stage \+ ivar_getOffset\(iv\)\) != 0;/return NO;/'
  mtf "Aerial 5's watcher: a locked window's drag a move by hand (its reader without the Lock)" 's/return !DMAerialStageLocked\(stage\) && DMAerial5GestureLive\(stage\);/return DMAerial5GestureLive(stage);/'
  mtf "Aerial 5's watcher: every pan a move by hand again (its own live read)" 's/BOOL live = DMAerial5HandGestureLive\(stage\), was/BOOL live = DMAerial5GestureLive(stage), was/'
  mtf "the trim baseline not followed" 's/\n        DMAerialTrimFollow\(stage, want\.x - c\.x, want\.y - c\.y\);//'
  mtf "3.0: no follow after Aerial's step" 's/\n    DMAerialPanFollow\(\(UIView \*\)self, gesture, YES\);   \/\/[^\n]*//'
  mtf "3.0: the touch-down not noted (the start where UIKit began the pan, 12 pt on)" 's/    if \(gAerialFlavor != 3 \|\| !stage\.superview \|\| !touch\) return;/    return;/'
  mtf "3.0: the touch-down noted replaced by where UIKit began the pan" 's/\n        if \(\[\(NSArray \*\)objc_getAssociatedObject\(stage, &kA5DragDownKey\) count\] == 2\) return;//'
  mtf "the limit at 40 pt (a quick finger's pan not followed)" 's/if \(began && !\(hypot\(dx, dy\) < 60\.0\)\)/if (began \&\& !(hypot(dx, dy) < 40))/'
  mtf "the drop past an edge not noted" 's/DMAerialDropNote\(stage, s\);\n\}/;\n}/'
  mtf "a start 60 pt off taken all the same" 's/if \(began && !\(hypot\(dx, dy\) < 60\.0\)\) \{ objc_setAssociatedObject\(g, &kA5DragDownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC\); return; \}/if (0) { }/'
fi
exit $rc
