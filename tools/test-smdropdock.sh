#!/bin/bash
# test-smdropdock.sh: a Stage Manager title-bar drop puts a window behind the Dock only when it is let go under the Dock's line, the drag counted
# once (1.8.7.3, audit M4 of 1.8.7.2) -- see test-smdropdock.m. The real -[DMSMTitleBar dm_pan:], its @interface and the globals it uses are cut
# out of statusbar/StatusBar.x (SMD_SB_X: another copy, e.g. the code before the fix) and run on the Mac (Mac Catalyst), in a release and a DEBUG
# build; then a site check; then made-to-fail copies: each breaks one part of the drop and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SMD_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }      # one function or method of a file, from its first line
blk() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^@end/ {exit}' "$1"; }   # an @interface, to its @end
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                        # one line of a file (a global)

IFACE='@interface DMSMTitleBar : UIView <UIGestureRecognizerDelegate>'
ONE=('static CFTimeInterval gSMDragUntil = 0;' 'static NSMutableSet<NSString *> *gSMBehindDock;' 'static NSMutableDictionary<NSString *, NSNumber *> *gSMDockHeightBySize;')
PAN='- (void)dm_pan:(UIPanGestureRecognizer *)g {'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg
  mkdir -p "$d"
  [ -n "$(blk "$X" "$IFACE")" ] || { echo "FAIL  $X: no \"$IFACE\""; return 99; }
  for h in "${ONE[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  [ "$(grep -cF -e "$PAN" "$X")" = 1 ] || { echo "FAIL  $X: not one \"$PAN\""; return 99; }
  { blk "$X" "$IFACE"; for h in "${ONE[@]}"; do line "$X" "$h"; done; } > "$d/smd-real.inc"
  fn "$X" "$PAN" > "$d/smd-pan.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-smdropdock.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"   # (a made-to-fail copy's warnings are not shown: an unused variable is the point of some)
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (the site check) the drop reads the dropped card once, at the drag's travel, and decides "behind the Dock" from that card's bottom on the
  # screen, with nothing added; the old reading (the card as it was, plus the drag) is gone
  local body; body=$(fn "$X" "$PAN")
  if echo "$body" | grep -qF 'CGRect droppedOnScreen = [card convertRect:card.bounds toCoordinateSpace:scn.coordinateSpace];' \
     && echo "$body" | grep -qF 'if (CGRectGetMaxY(droppedOnScreen) > line + 4.0) [gSMBehindDock addObject:w];' \
     && ! echo "$body" | grep -qE '\+ *t\.y *> *line' \
     && echo "$body" | awk '/card.transform = CGAffineTransformMakeTranslation\(t.x, t.y\);/{a=NR} /CGRect droppedOnScreen = /{b=NR} /card.transform = was;/{c=NR} /CGRectGetMaxY\(droppedOnScreen\)/{e=NR} END{exit !(a && a < b && b < c && c < e)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the drop decides \"behind the Dock\" from the dropped card's bottom on the screen, read once at the drag's travel"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the drop does not decide \"behind the Dock\" from the one dropped card"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$SMD_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the drag added again (the audit's double count)" 's/if \(CGRectGetMaxY\(droppedOnScreen\) > line \+ 4\.0\)/if (CGRectGetMaxY(droppedOnScreen) + t.y > line + 4.0)/'
  mtf "the card read without the drag (where it started)" 's/^(\s*)CGRect droppedOnScreen = \[card convertRect:card.bounds toCoordinateSpace:scn.coordinateSpace\];/$1card.transform = CGAffineTransformIdentity; CGRect droppedOnScreen = [card convertRect:card.bounds toCoordinateSpace:scn.coordinateSpace];/'
  mtf "the stage view's frame instead of the screen's" 's/if \(CGRectGetMaxY\(droppedOnScreen\) > line \+ 4\.0\)/if (CGRectGetMaxY(dropped) > line + 4.0)/'
  mtf "no 4 pt allowance under the line" 's/if \(CGRectGetMaxY\(droppedOnScreen\) > line \+ 4\.0\)/if (CGRectGetMaxY(droppedOnScreen) > line)/'
  mtf "the Dock at a side not asked" 's/^\s*if \(DMDockSideNow\(scn.bounds.size\)\) line = scn.bounds.size.height \+ 1000\.0;.*$//'
  mtf "the place from the card's anchor again (1.7.4 item 13)" 's/mid = CGPointMake\(CGRectGetMidX\(dropped\), CGRectGetMidY\(dropped\)\)/mid = CGPointMake(card.center.x + t.x, card.center.y + t.y)/'
fi
exit $rc
