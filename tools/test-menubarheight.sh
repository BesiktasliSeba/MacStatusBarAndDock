#!/bin/bash
# Mac test of our menu bar's height and the window geometry from it (common/MenuBarHeight.h, test-menubarheight.c; 1.7.1 item 14: on Home-button
# iPads windows and tiles started 3-4 pt below the 20 pt bar), then the sites in the code as built: every one takes the bar's height.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tmbh" test-menubarheight.c
"$W/tmbh"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
check "DMTopLimit: one point into the bar's height (0 while it hides itself)" "grep -q 'static CGFloat DMTopLimit(void) { return DMAutoHideLayout() ? 0.0 : MSBDMenuBarTopLimit(DMMenuBarHeight()); }' $S"
check "DMMenuBarHeight: iOS's provider (+height, type-checked) or the copy's height, on the main screen, 24 until known" \
  "awk '/^static CGFloat DMMenuBarHeight\\(void\\) \\{/{f=1} f&&/fg.window.screen != \\[UIScreen mainScreen\\]/{a=1} f&&/\"d16@0:8\"/{b=1} f&&/MSBDMenuBarHeightOf\\(provided, fg.bounds.size.height\\)/{c=1} f&&/return kMSBDMenuBarDefault;/{d=1} f&&/^}/{print (a&&b&&c&&d) ? \"ok\" : \"no\"; exit}' $S | grep -q ok"
check "Stage Manager: the stage starts under the bar's height, not at least 24 (the _statusBarHeight hook)" "grep -q 'return DMSMEngine() ? MAX(h, DMMenuBarHeight()) + ' $S && ! grep -q 'MAX(h, 24.0)' $S"
check "Stage Manager: our usable area on the iPad starts at the bar's height" "awk '/^static CGRect DMSMUsableAreaForIdentity\\(id identity, CGSize \\*screenOut\\) \\{/{f=1} f&&/CGFloat bar = DMMenuBarHeight\\(\\);/{a=1} f&&/if \\(CGRectGetMinY\\(u\\) < bar\\)/{b=1} f&&/^}/{print (a&&b) ? \"ok\" : \"no\"; exit}' $S | grep -q ok"
check "Stage Manager: the size grid's tallest window leaves the bar of its screen (both grids)" "[ \$(grep -c 'dock.doubleValue - 2.0 - (DMSMTopBarOf(b.size) + kSMBarH)' $S) = 2 ] && ! grep -q '(24.0 + kSMBarH)' $S"
check "the center layout and MilkyWay4's default place: 12 pt under the bar" "grep -q 'MSBDMenuBarCenterTop(DMMenuBarHeight()) : 36.0;' $S && grep -q 'CGRectMake(round(screen.width \\* 0.11), MSBDMenuBarCenterTop(DMMenuBarHeight()), round(screen.width \\* 0.78)' $S"
check "auto-hide: windows move down by at least the bar's height, and its top band follows the bar" "grep -q 'CGFloat h = DMMenuBarHeight();' $S && grep -q 'fabs(f.origin.y - MSBDMenuBarWasTop(bar)) < 2.0' $S && grep -q 'f.origin.y < MSBDMenuBarUnderTop(bar)' $S"
check "native windows: a touch on the bar is judged by the bar's height" "grep -q 'if (p.y < MSBDMenuBarTouchBand(DMMenuBarHeight())) return;' ../statusbar/NativeWindow.h"
[ $fails = 0 ] && echo "test-menubarheight: site checks pass" || { echo "test-menubarheight: site checks FAILED"; exit 1; }
