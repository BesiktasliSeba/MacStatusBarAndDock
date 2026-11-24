#!/bin/bash
# test-rstripdragout.sh: a card dragged out of the Recent Windows Strip (1.8.8.4), through statusbar/RecentStrip.h's real code cut out into
# test-rstripdragout.m (a card that, taken off its window, has its live press cancelled as UIKit does), built for Mac Catalyst as a release and a
# DEBUG build (they must answer the same); a site check that the card's stand-in keeps the real code's rule; then made-to-fail copies, each must fail.
# RSD_H: another RecentStrip.h (e.g. the code before the change).
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H0=${RSD_H:-../statusbar/RecentStrip.h}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }      # one function of a file, from its first line
blk() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^@end/ {exit}' "$1"; }   # an @interface or @implementation, to its @end
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                        # one line of a file
range() { awk -v a="$2" -v b="$3" 'index($0, a) == 1 {f=1} index($0, b) == 1 {f=0} f {print}' "$1"; }   # from a line to before another
GLOB_A='static UIWindow *gRStripWindow;'; GLOB_B='static BOOL DMRStripOn(void) {'
BLK=('@interface DMRStripCard : UIView' '@interface DMRStripPress : UIGestureRecognizer' '@implementation DMRStripPress' '@interface DMRStripDrag : NSObject' '@implementation DMRStripDrag')
ONE1=('static MSBDRRect DMRStripRectOf(CGRect r) {' 'static CGRect DMRStripCGRect(MSBDRRect r) {' 'static void DMRStripTouched(void) {')
FN1=('static CGAffineTransform DMRStripAway(void) {' 'static void DMRStripCardGoes(NSString *k, BOOL intoWindow) {' 'static void DMRStripCardPlace(DMRStripCard *c, MSBDRRect r) {'
     'static void DMRStripLayoutCards(NSArray<NSString *> *items, NSDictionary<NSString *, UIView *> *stageOf, CGSize sc, MSBDRRect usable, BOOL animated) {'
     'static void DMRStripShowAs(MSBDRStripShow show, NSString *why) {')
HOLDS='static BOOL DMRStripDragHolds(void) {'   # (the code before has none: cut when there)
FN2=('static NSArray<NSString *> *DMRStripCollect(NSDictionary<NSString *, UIView *> **stageOfOut, BOOL *anyShownOut) {' 'static BOOL DMRStripRelayout(BOOL animated) {' 'static MSBDRStripShow DMRStripApplyShow(BOOL laid, BOOL covered, NSString *why) {')
ONE2=('static CGRect DMRStripCardScreenRect(DMRStripCard *c) {')
FN3=('static void DMRStripDragFollow(CGPoint p) {' 'static void DMRStripCardDragBegin(DMRStripCard *c, DMRStripPress *g) {' 'static void DMRStripCardDragReturn(NSString *why, BOOL gone) {'
     'static void DMRStripCardDragEnd(DMRStripPress *g) {' 'static void DMRStripPressed(DMRStripPress *g) {')
MS='s/\[UIScreen mainScreen\]\.bounds\.size/TScreenSize()/g'

run() {   # $1 RecentStrip.h, $2 work dir, $3 quiet: the number of failed checks (99: the code could not be cut out or built)
  local H=$1 d=$2 q=$3 h n out r
  mkdir -p "$d"
  [ -n "$(range "$H" "$GLOB_A" "$GLOB_B")" ] || { echo "FAIL  $H: no globals block"; return 99; }
  for h in "${BLK[@]}"; do [ -n "$(blk "$H" "$h")" ] || { echo "FAIL  $H: no \"$h\""; return 99; }; done
  for h in "${ONE1[@]}" "${ONE2[@]}"; do [ -n "$(line "$H" "$h")" ] || { echo "FAIL  $H: no line \"$h\""; return 99; }; done
  for h in "${FN1[@]}" "${FN2[@]}" "${FN3[@]}"; do [ -n "$(fn "$H" "$h")" ] || { echo "FAIL  $H: no \"$h\""; return 99; }; done
  { echo '@class DMRStripCard;'; range "$H" "$GLOB_A" "$GLOB_B"; } > "$d/rsd-glob.inc"
  for h in "${BLK[@]}"; do blk "$H" "$h"; done > "$d/rsd-decl.inc"
  { for h in "${ONE1[@]}"; do line "$H" "$h"; done; for h in "${FN1[@]}"; do fn "$H" "$h"; done; [ -n "$(line "$H" "$HOLDS")" ] && line "$H" "$HOLDS"
    for h in "${FN2[@]}"; do fn "$H" "$h"; done; for h in "${ONE2[@]}"; do line "$H" "$h"; done; for h in "${FN3[@]}"; do fn "$H" "$h"; done; } | sed "$MS" > "$d/rsd-real.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-const-variable -Wno-unused-but-set-variable -Werror=implicit-function-declaration \
          -I"$d" -I. -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-rstripdragout.m 2>"$d/cc$dbg.txt" \
      || { [ -n "$q" ] || cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
  done
  [ -n "$q" ] || grep -E 'warning:|error:' "$d/cc0.txt"
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); r=$?
  if [ $r != $n ]; then [ -n "$q" ] || echo "FAIL  the DEBUG build answers otherwise ($r failed checks, release $n)"; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  [ $n -gt 98 ] && n=98
  return $n
}

run "$H0" "$W/real"; rc=$?
# (site: the card's stand-in keeps the real code's rule -- every card carries the press that drives its drag (DMRStripCardFor))
c3=$(fn "$H0" 'static DMRStripCard *DMRStripCardFor(NSString *k) {' | grep -cE 'DMRStripPress \*press = \[\[DMRStripPress alloc\] initWithTarget:t action:@selector\(press:\)\];|\[c addGestureRecognizer:press\];')
if [ "$c3" = 2 ]; then echo "PASS  site: every card carries the press that drives its drag (DMRStripCardFor, the card's stand-in's rule)"
else echo "FAIL  site: DMRStripCardFor's press moved ($c3): look at the card's stand-in in test-rstripdragout.m"; rc=1; fi
if [ -z "$RSD_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on RecentStrip.h (-0777: the whole file)
    local d="$W/m$((++k))" out r
    mkdir -p "$d"; out="$d/RecentStrip.h"
    perl -0777 -pe "$2" "$H0" > "$out"
    cmp -s "$out" "$H0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$out" "$d/w" q; r=$?
    if [ $r -gt 0 ] && [ $r -lt 99 ]; then echo "PASS  caught: $1 ($r check(s) fail)"; else echo "FAIL  not caught: $1 ($r)"; rc=1; fi
  }
  k=0
  mtf "the dragged card let go by the layout (its view off the window: UIKit cancels the drag inside its begin, the first 1.8.8.4 device pass)" 's/    if \(!c \|\| \(gRStripCardDrag && \[k isEqualToString:gRStripDraggingKey \?: \@""\]\)\) return;/    if (!c) return;/'
  mtf "the layout's signature without the card a drag holds out (after the drop the held card stays, hidden, with the same cards left)" 's/ gap %d held %\@", sc\.width, sc\.height, usable\.x, usable\.y, usable\.w, usable\.h, gRStripRight, gRStripGapAt, gRStripCardDrag \? gRStripDraggingKey : \@"-"\];/ gap %d", sc.width, sc.height, usable.x, usable.y, usable.w, usable.h, gRStripRight, gRStripGapAt];/'
  mtf "a hide cutting a card drag short after the cards that step aside are gathered (the held card stays out, shown, for the handle)" 's/(    if \(show == MSBDRStripHidden\) \{ if \(gRStripCardDrag\) DMRStripCardDragReturn\(\[NSString stringWithFormat:\@"the strip steps aside: %\@", why\], NO\); \}\n)(    UIWindow \*w = gRStripWindow;\n    NSMutableArray<DMRStripCard \*> \*cards = \[NSMutableArray array\];\n    for \(NSString \*k in gRStripItems\) \{[^\n]*\n)/$2$1/'
  mtf "the held card left hidden when its drag ends as gone and it is still in the strip" 's/        if \(left && !left\.going\) \{ left\.landing = NO; left\.alpha = 1\.0; \}\n//'
  mtf "our own windows' card dragged out with its windows left out of its group (the drop takes them for gone: nothing comes out, the card left hidden)" 's/        if \(!groups\[k\]\) \{ groups\[k\] = \[NSMutableArray array\]; if \(!\[k isEqualToString:gRStripDraggingKey \?: \@""\]\) \[off addObject:k\]; \}/        if ([k isEqualToString:gRStripDraggingKey ?: \@""]) continue;\n        if (!groups[k]) { groups[k] = [NSMutableArray array]; [off addObject:k]; }/'
  mtf "the dragged card not counted for the strip's show (the last card's drag cut short by the strip stepping aside)" 's/laid \? \(int\)gRStripItems\.count \+ \(DMRStripDragHolds\(\) \? 1 : 0\) : 0/laid ? (int)gRStripItems.count : 0/'
  mtf "the dragged card not counted for the strip's calm and layout (the last card's drag cut short)" 's/\(gRStripList\.count \|\| gRStripDropTarget \|\| DMRStripDragHolds\(\)\) && DMRStripCalm\(\)/(gRStripList.count || gRStripDropTarget) \&\& DMRStripCalm()/'
fi
[ $rc = 0 ] && echo "test-rstripdragout: all checks pass" || echo "test-rstripdragout: checks FAILED"
exit $rc
