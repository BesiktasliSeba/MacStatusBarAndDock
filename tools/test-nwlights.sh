#!/bin/bash
# Mac test of our own windows' traffic lights (Finder, TextEdit: statusbar/NativeWindow.h), 1.8.3.1, GitHub #11: in Finder's Trash on an iPad
# with 16.3.1 the red and yellow lights sat 4 pt left of and 20 pt above their places, green where it belongs. The window's layout found each
# light's dot as its button's first subview; with an assistive feature running, UIKit puts a view of its own first in the red and yellow buttons
# when the light group reads their labels (green's label is set before), so those two dots were never centred and stayed where they were made,
# at the top left of their 20 x 52 cells. Seen on the M1 (15.6.1) with Full Keyboard Access on: red and yellow at (-4, -20), green right.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
N=../statusbar/NativeWindow.h; S=../statusbar/StatusBar.x
L=$(mktemp); trap 'rm -f "$L"' EXIT
awk '/_lights.frame = CGRectMake\(8.0, 0, kLightCell \* 3.0, th\);/{f=1} f{print} f&&/^}/{exit}' $N > "$L"

check "the window's layout centres each light's own dot (kept from -init in _dots) in its button's cell" \
  "grep -q 'for (UIView \\*dot in _dots) {' \"$L\" && grep -q 'UIView \\*btn = dot.superview;' \"$L\" \
   && grep -q 'btn.frame = CGRectMake(btn.tag \\* kLightCell, 0, kLightCell, th);' \"$L\" && grep -q 'dot.center = CGPointMake(kLightCell / 2.0, th / 2.0);' \"$L\" \
   && grep -q '_dots = dots;' $N && grep -q '\\[buttons addObject:b\\]; \\[dots addObject:dot\\];' $N"
check "  ... and never finds a dot by its place among a button's subviews (UIKit may put its own view there first)" \
  "! grep -n 'subviews.firstObject' $N | grep -v -E 'UIView \\*grip = g.subviews.firstObject;' | grep -q ."
check "  ... the dots as made (12 pt at the top left of a 20 x 52 cell) are where the report saw red and yellow: 4 pt left, 20 pt up" \
  "python3 -I -c 'cell, th, dot = 20.0, 52.0, 12.0; made = (dot / 2, dot / 2); centred = (cell / 2, th / 2); import sys; sys.exit(0 if (made[0] - centred[0], made[1] - centred[1]) == (-4.0, -20.0) else 1)' \
   && grep -q 'static const CGFloat kLightCell = 20.0;' $S && grep -q 'static const CGFloat kLightDot = 12.0;' $S && grep -q 'self.titleBarHeight = 52.0;' ../statusbar/Finder.h"
# The other sets of lights take their dots right after making them, before the light group reads any label, and centre them as they are made:
# nothing of UIKit's is in the buttons yet (Aerial's stage lights, our Stage Manager title bar).
check "the other lights take each dot before the light group reads the labels (Aerial's stage lights, our Stage Manager title bar)" \
  "awk '/^- \\(instancetype\\)initWithStage:\\(UIView \\*\\)stage \\{/{f=1} f&&/\\[dots addObject:b.subviews.firstObject\\]/{a=NR} f&&/DMLightGroupAttach\\(self, self.subviews, dots,/{b=NR} f&&/^}/{exit} END{exit !(a && b > a)}' $S \
   && awk '/for \\(UIButton \\*b in ls\\) \\[dots addObject:b.subviews.firstObject\\];/{a=NR} /DMLightGroupAttach\\(self, ls, dots,/{b=NR} END{exit !(a && b == a + 1)}' $S"

[ $fails = 0 ] && echo "test-nwlights: all checks pass" || { echo "test-nwlights: FAILED"; exit 1; }
