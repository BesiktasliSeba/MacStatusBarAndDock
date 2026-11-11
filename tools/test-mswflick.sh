#!/bin/bash
# test-mswflick.sh: Swipe Up to Quit's rule (statusbar/MSWFlick.h) -- see test-mswflick.c.
cd "$(dirname "$0")" || exit 1
OUT="${TMPDIR:-/tmp}/test-mswflick.$$"
clang -std=c11 -O1 -Wall -Werror -o "$OUT" test-mswflick.c || exit 1
"$OUT"; rc=$?
rm -f "$OUT"
# The trackpad's quit takes continuous scrolls only (review 1.8.6, gestures: with every scroll type a mouse wheel's notches down over a thumbnail quit
# its app).
m=$(grep -c 'scroll.allowedScrollTypesMask = ' ../statusbar/MacSwitcher.h)
if [ "$m" = 1 ] && grep -q 'scroll.allowedScrollTypesMask = UIScrollTypeMaskContinuous;' ../statusbar/MacSwitcher.h; then
  echo "PASS  the two-finger swipe's pan takes continuous scrolls only (a trackpad or Magic Mouse swipe, never a mouse wheel's notches)"
else echo "FAIL  statusbar/MacSwitcher.h: the two-finger swipe's pan is not continuous-only"; rc=1; fi
# The drop target is MSWFlick.h's rule, on the strip's shared layout (1.8.6 row 4c: a window let go on a desktop's name goes to that desktop).
f=../statusbar/MacSwitcher.h
body=$(awk '/^static NSInteger DMMSWDropTargetAt\(CGPoint p\) \{/,/^\}/' "$f")
if echo "$body" | grep -q 'MSBDMSWDropOnDesk(p.x, p.y, CGRectGetMinX(r), CGRectGetMinY(r), CGRectGetMaxX(r), CGRectGetMaxY(r))' && ! echo "$body" | grep -q 'DMMSWDeskAt('; then
  echo "PASS  DMMSWDropTargetAt takes a desktop by MSBDMSWDropOnDesk (its tile and its name), not the tile alone"
else echo "FAIL  $f: DMMSWDropTargetAt does not use MSBDMSWDropOnDesk for every desktop"; rc=1; fi
if echo "$body" | grep -qF 'return p.x > CGRectGetMaxX([gMSWDeskRects.lastObject CGRectValue]) + 6.0 ? kMSWDropNew : kMSWDropNone;'; then
  echo "PASS  \"+\" unchanged: the strip's end right of the last desktop's 6 pt reach"
else echo "FAIL  $f: the \"+\" target changed"; rc=1; fi
if grep -qF 'static const CGFloat kMSWStripGap = kMSBDMSWStripGap, kMSWStripLabelH = kMSBDMSWStripLabelH;' "$f" \
   && grep -qF 'dl.frame = CGRectMake(CGRectGetMinX(r) - 20, CGRectGetMaxY(r) + kMSBDMSWStripLabelTop, r.size.width + 40, labelH);' "$f" \
   && grep -qF 'MSBDMSWFlickOverStrip(p.x, p.y, CGRectGetMinX(first), MSBDMSWNamesMaxY(CGRectGetMaxY(last)), kMSWStripGap)' "$f"; then
  echo "PASS  the strip's names, the flick's strip and the drop share MSWFlick.h's layout (gap, name height, name offset)"
else echo "FAIL  $f: the strip's layout is not MSWFlick.h's in one of the names, the flick or the drop"; rc=1; fi
grep -q 'kMSBDMSWDropReach      6.0' ../statusbar/MSWFlick.h && echo "PASS  a desktop's reach is 6 pt, as its tile's (DMMSWDeskAt)" || { echo "FAIL  MSWFlick.h: the drop reach is not 6 pt"; rc=1; }
grep -qF 'CGRectInset([gMSWDeskRects[i] CGRectValue], -6, -6)' "$f" && echo "PASS  DMMSWDeskAt (taps, hover, hold) unchanged: the tile and 6 pt" || { echo "FAIL  $f: DMMSWDeskAt changed"; rc=1; }
exit $rc
