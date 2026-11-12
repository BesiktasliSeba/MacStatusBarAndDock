#!/bin/bash
# Mac test of the bar height our items in a status bar copy take (common/MenuBarHeight.h MSBDMenuBarCopyHeight, test-shotlogo.c; 1.8.7, Reddit: an
# iPad 6 on 15.7 showed a huge Apple logo while taking a screenshot with the corner swipe -- SpringBoard's placeholder status bar of the screenshot
# editor is the whole screen, and the logo took that height), then the sites in the code as built: every layout of ours in a copy takes the bar's
# height (DMBarCopyHeight), not the copy's.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tsl" test-shotlogo.c
"$W/tsl"
# made-to-fail copy: 1.8.7's code before the fix took the copy's own height everywhere -- the C cases must fail
mkdir -p "$W/mtf/common" "$W/mtf/tools"; cp ../common/*.h "$W/mtf/common/"; cp test-shotlogo.c "$W/mtf/tools/"
perl -0pi -e 's/(static inline double MSBDMenuBarCopyHeight\(double providerHeight, double viewHeight, double known\) \{\n)/$1    return viewHeight;\n/' "$W/mtf/common/MenuBarHeight.h"
cmp -s ../common/MenuBarHeight.h "$W/mtf/common/MenuBarHeight.h" && { echo "made-to-fail copy: the change did not apply"; exit 1; }
clang -O2 -Wall -Wno-unused-function -o "$W/mtf/t" "$W/mtf/tools/test-shotlogo.c" 2>/dev/null
if "$W/mtf/t" >/dev/null 2>&1; then echo "made-to-fail copy (the copy's own height) PASSED (it must fail)"; exit 1; else echo "made-to-fail copy (the copy's own height) fails, as it must"; fi
# made-to-fail copy: the provider's height whenever the copy is taller than it (the patch before review) -- a TV's 24 pt bar over its provider's 20
# shrank to 20: the C cases must fail
cp ../common/MenuBarHeight.h "$W/mtf/common/MenuBarHeight.h"
perl -0pi -e 's/    if \(!\(viewHeight > 40\.0\)\) return viewHeight;[^\n]*\n/    if (MSBDMenuBarPlausible(providerHeight) \&\& viewHeight > providerHeight + 0.5) return providerHeight;\n    if (!(viewHeight > 40.0)) return viewHeight;\n/' "$W/mtf/common/MenuBarHeight.h"
cmp -s ../common/MenuBarHeight.h "$W/mtf/common/MenuBarHeight.h" && { echo "made-to-fail copy (provider when taller): the change did not apply"; exit 1; }
clang -O2 -Wall -Wno-unused-function -o "$W/mtf/t2" "$W/mtf/tools/test-shotlogo.c" 2>/dev/null
if "$W/mtf/t2" >/dev/null 2>&1; then echo "made-to-fail copy (the provider's height whenever the copy is taller) PASSED (it must fail)"; exit 1; else echo "made-to-fail copy (the provider's height whenever the copy is taller) fails, as it must"; fi
cp ../common/MenuBarHeight.h "$W/mtf/common/MenuBarHeight.h"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
sites() {   # sites <StatusBar.x> <BatteryMenu.h> <WiFiMenu.h> <LiveActivities.h>
  local S="$1" B="$2" F="$3" L="$4"
  check "DMBarCopyHeight: the provider's +height (both type-checked) or the copy's, through MSBDMenuBarCopyHeight with the known bar height" \
    "awk '/^static CGFloat DMBarCopyHeight\\(UIView \\*fg\\) \\{/{f=1} f&&/\"@16@0:8\"/{a=1} f&&/\"d16@0:8\"/{b=1} f&&/return MSBDMenuBarCopyHeight\\(provided, fg.bounds.size.height, DMMenuBarKnownHeight\\(\\)\\);/{c=1} f&&/^}/{print (a&&b&&c) ? \"ok\" : \"no\"; exit}' $S | grep -q ok"
  check "the logo: its ink and its middle from the bar's height (DMBarCopyHeight), not the copy's" \
    "grep -qF 'CGFloat barH = DMBarCopyHeight(fg);' $S && grep -qF 'CGFloat targetInk = MSBDMenuBarLogoInk(copySize, barH, timeFont.pointSize);' $S && grep -qF 'lf = CGRectMake(baseLeft, barH / 2.0 - inkMidFromTop,' $S"
  check "no layout of ours in a copy takes the copy's own height (dm_layoutLogoBody, the Spotlight button, the battery and Control Center buttons and pill, the Wi-Fi button, the Live Activities' pills)" \
    "[ \$(awk '/^- \\(void\\)dm_layoutLogoBody \\{/{f=1} f&&/fg\\.bounds\\.size\\.height/{n++} f&&/^}/{print n+0; exit}' $S) = 0 ] && [ \$(grep -c 'fg.bounds.size.height' $S) = 2 ] && ! grep -q 'fg.bounds.size.height' $B $F $L"
  check "the logo's button, the lights, Spotlight, the clock, VPN and SSH buttons: the bar's height (barH)" \
    "[ \$(grep -c 'lf.size.width + 2.0 \\* kLogoHitSlop \\* k, barH));\\|(noWindows ? 2.0 : 3.0), barH);\\|side.spotBtnTrail - side.spotBtnLead, barH));\\|clockW + 8.0 \\* k, barH));\\|w + 12.0 \\* k, barH));' $S) = 6 ]"
  check "the battery's and Control Center's buttons and pill, the Wi-Fi button, the Live Activities' pills: DMBarCopyHeight(fg)" \
    "[ \$(grep -c 'DMBarCopyHeight(fg)' $B) = 3 ] && grep -q 'w + 12.0 \\* k, DMBarCopyHeight(fg)));' $F && grep -q 'CGFloat H = MIN(round(18.0 \\* k), DMBarCopyHeight(fg) - 4.0);' $L"
}
sites ../statusbar/StatusBar.x ../statusbar/BatteryMenu.h ../statusbar/WiFiMenu.h ../statusbar/LiveActivities.h
[ $fails = 0 ] || exit 1
# made-to-fail copy of the sites: the logo's ink from the copy's own height again (1.8.7 before the fix) -- the site checks must fail
mkdir -p "$W/mtf/statusbar"; cp ../statusbar/StatusBar.x ../statusbar/BatteryMenu.h ../statusbar/WiFiMenu.h ../statusbar/LiveActivities.h "$W/mtf/statusbar/"
sed -i '' 's/    CGFloat targetInk = MSBDMenuBarLogoInk(copySize, barH, timeFont.pointSize);/    CGFloat targetInk = MSBDMenuBarLogoInk(copySize, fg.bounds.size.height, timeFont.pointSize);/' "$W/mtf/statusbar/StatusBar.x"
cmp -s ../statusbar/StatusBar.x "$W/mtf/statusbar/StatusBar.x" && { echo "made-to-fail site copy: the change did not apply"; exit 1; }
sites "$W/mtf/statusbar/StatusBar.x" "$W/mtf/statusbar/BatteryMenu.h" "$W/mtf/statusbar/WiFiMenu.h" "$W/mtf/statusbar/LiveActivities.h" > "$W/mtf/sites.out"
if [ $fails = 0 ]; then echo "made-to-fail site copy PASSED (it must fail)"; exit 1; else echo "made-to-fail site copy fails, as it must"; fi
echo "test-shotlogo: all passed"
