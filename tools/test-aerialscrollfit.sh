#!/bin/bash
# test-aerialscrollfit.sh: Aerial 3.0: a page scrolled inside a tiled window leaves it in Fit to Window -- only the end of a drag or a resize whose start
# was taken acts as a move by hand (1.8.7.3, audit M5 of 1.8.7.2) -- see test-aerialscrollfit.m. The real DMAerialPanBefore ... DMAerialGestureAfter,
# DMTitleRecordHandEnded, DMFitGroupForget with gFitGroup / gFitSlots, kStageBarHeight, the %hook AerialStage bodies of -handlePan: and
# -handleResizeBR: and the 5.0 reference functions h5_pan / h5_resizeBR are cut out of statusbar/StatusBar.x (ASF_SB_X: another copy, e.g. the code
# before the fix) and run on the Mac (Mac Catalyst); then a site check; then made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${ASF_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }    # one function of a file, from its first line
mth() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one method of a %hook, from its first line
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                       # one line of a file (a global)
# the drag's two steps and what lies between them: from the comment above DMAerialPanBefore to DMAerialGestureAfter's closing brace
blockcut() { awk 'index($0, "// A drag by hand. NO: the drag was cancelled here") == 1 {f=1} f {print} f && index($0, "static void DMAerialGestureAfter(") == 1 {g=1} g && /^[}]/ {exit}' "$1"; }

ONE=('static const CGFloat kStageBarHeight = ' 'static NSMutableArray<NSString *> *gFitGroup = nil;' 'static NSMutableDictionary<NSString *, NSString *> *gFitSlots = nil;'
     'static void DMFitGroupForget(NSString *bundleID) {')
TRE='static void DMTitleRecordHandEnded(UIView *v, UIGestureRecognizerState s) {'
PAN='- (void)handlePan:(id)gesture {'; RES='- (void)handleResizeBR:(id)gesture {'
H5P='static void h5_pan(id self, SEL _cmd, id gesture) {'; H5R='static void h5_resizeBR(id self, SEL _cmd, id gesture) {'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out
  mkdir -p "$d"
  for h in "${ONE[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "$TRE" "$H5P" "$H5R"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  for h in "$PAN" "$RES"; do [ "$(grep -cF -e "$h" "$X")" = 1 ] || { echo "FAIL  $X: not one \"$h\""; return 99; }; done
  [ -n "$(blockcut "$X")" ] || { echo "FAIL  $X: no DMAerialPanBefore ... DMAerialGestureAfter"; return 99; }
  { for h in "${ONE[@]}"; do line "$X" "$h"; done; fn "$X" "$TRE"; blockcut "$X"; } > "$d/asf-real.inc"
  { fn "$X" "$H5P"; fn "$X" "$H5R"; } > "$d/asf-h5.inc"
  { mth "$X" "$PAN" | sed 's/^\( *\)%orig;/\1[self k_origPan:gesture];/'; mth "$X" "$RES" | sed 's/^\( *\)%orig;/\1[self k_origResize:gesture];/'; } > "$d/asf-hooks.inc"
  grep -q '%orig' "$d/asf-hooks.inc" && { echo "FAIL  $X: a %orig left in the hooks cut out"; return 99; }
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -o "$d/t" test-aerialscrollfit.m 2>"$d/cc.txt" \
    || { cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -n "$q" ] || cat "$d/cc.txt"
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (the site check) the hooks run above are Aerial 3.0's real-named ones (%group AerialStyleNamed, %hook AerialStage), each hook passes Aerial's
  # recogniser itself to DMAerialGestureAfter (the end is judged by that recogniser's start), and both resize starts mark theirs
  if awk -v p="$PAN" -v r="$RES" '/^%group AerialStyleNamed/{g=1} g && /^%hook AerialStage/{h=1} h && index($0, p) == 1 {a=1} h && index($0, r) == 1 {b=1} h && /^%end/{exit} END{exit !(a && b)}' "$X" \
     && [ "$(grep -cF 'DMAerialGestureAfter((UIView *)self, gesture, ' "$X")" = 4 ] && ! grep -qF 'DMAerialGestureAfter((UIView *)self, [(UIGestureRecognizer *)gesture state]' "$X" \
     && [ "$(grep -cF 'UIGestureRecognizerStateBegan) DMAerialHandStart((UIView *)self, gesture);' "$X")" = 2 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the hooks run are Aerial 3.0's (AerialStyleNamed, AerialStage); all four pass the recogniser on, both resize starts mark it"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the hooks do not judge a gesture's end by that recogniser's start"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$ASF_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x (-0: the whole file)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "every end acts again (the audit's case)" 's/\n *if \(!\[objc_getAssociatedObject\(g, kAerialHandStartKey\) boolValue\]\) return;[^\n]*//'
  mtf "the end judged by the window's gesture key, not the recogniser's start" 's/if \(!\[objc_getAssociatedObject\(g, kAerialHandStartKey\) boolValue\]\) return;/if (![objc_getAssociatedObject(stage, kStageGestureKey) boolValue]) return;/'
  mtf "the mark not cleared at a start (an earlier drag's carries over)" 's/\n *objc_setAssociatedObject\(g, kAerialHandStartKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);[^\n]*//'
  mtf "the start marked before it is refused" 's/(\n *)(objc_setAssociatedObject\(g, kAerialHandStartKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);[^\n]*)/$1$2$1DMAerialHandStart(stage, g);/; s/\n        DMAerialHandStart\(stage, g\);\n    \}\n    return YES;/\n    }\n    return YES;/'
  mtf "a resize's start not marked (the window's key only)" 's/UIGestureRecognizerStateBegan\) DMAerialHandStart\(\(UIView \*\)self, gesture\);/UIGestureRecognizerStateBegan) objc_setAssociatedObject(self, kStageGestureKey, \@YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);/g'
  mtf "a taken start not shown as a gesture by hand (the window's key)" 's/\n    objc_setAssociatedObject\(stage, kStageGestureKey, \@YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);\n    objc_setAssociatedObject\(g, kAerialHandStartKey, \@YES/\n    objc_setAssociatedObject(g, kAerialHandStartKey, \@YES/'
fi
exit $rc
