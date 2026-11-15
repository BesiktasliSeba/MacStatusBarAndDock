#!/bin/bash
# test-battinsideone.sh: Battery Percentage in Icon with one switch (1.8.7.4 round 2, KT 14 Nov: "currently I have to toggle it on first and
# then turn off the battery percentage in the battery settings") -- see test-battinsideone.m. With the switch on, our bars leave iPadOS's own
# number beside the icon out at its source (the battery item's -canEnableDisplayItem:fromData:, so the bar lays the battery out alone and the items
# beside it close up), ours is inside the icon whatever iPadOS's Battery Percentage says; switched off, iPadOS's number is back as its setting
# says, live; any other bar keeps it. The real code is cut out of statusbar/BatteryMenu.h (BO_MENU_H: another copy, e.g. the code before the
# change) with common/BatteryInside.h (BO_INSIDE_H) and StatusBar.x (BO_SB_X: DMCall, DMStockVPNRecheck, the no-clock layout of
# -dm_layoutLogoBody, the hold: DMHoldStatusBarCopy, DMCopyHasStockText, DMHoldSafetyCheck, DMReleaseStatusBarCopy) and run on the Mac (Mac
# Catalyst) on stand-ins of iPadOS's bar, both families (15/16 UIKit's names, 17+ SystemStatusUI's), one scenario per process; then site
# checks; then made-to-fail copies, each must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${BO_MENU_H:-../statusbar/BatteryMenu.h}; I0=${BO_INSIDE_H:-../common/BatteryInside.h}; S0=${BO_SB_X:-../statusbar/StatusBar.x}; R0=crashmap-rules.txt
fndef() {   # $1 file, $2 name: a static function's definition (not a declaration), whole, by its braces
  awk -v n="$2" '
    !f && $0 ~ ("^(__attribute__\\(\\(noinline\\)\\) )?static [^(=]*[ *]" n "\\(") && index($0, "{") { f = 1 }
    f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }
  ' "$1"
}

build() {   # $1 BatteryMenu.h, $2 BatteryInside.h, $3 dir, $4 quiet, $5 StatusBar.x: the test built on that code, both families (t: 15/16, t17: 17+)
  local d=$3 fam X=${5:-$S0}
  mkdir -p "$d"; cp "$2" "$d/BatteryInside.h"
  fndef "$X" DMCall > "$d/one-call.inc"; fndef "$X" DMStockVPNRecheck > "$d/one-recheck.inc"
  { fndef "$X" DMHoldStatusBarCopy; fndef "$X" DMCopyHasStockText; fndef "$X" DMHoldSafetyCheck; fndef "$X" DMReleaseStatusBarCopy; } > "$d/one-hold.inc"
  # the no-clock part of the copy's layout: from the leading region's lookup to the end of its branch (as test-startupwatch.sh cuts it)
  awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { b = 1 } b && index($0, "    UIView *container = DMLeadingContainer(fg);") == 1 { f = 1 } f { print } f && /^    [}]$/ { exit }' "$X" > "$d/one-noclock.inc"
  fndef "$1" DMBattLockLayout > "$d/one-locklayout.inc"
  [ "$(grep -cE '^static void (DMHoldStatusBarCopy|DMHoldSafetyCheck|DMReleaseStatusBarCopy)\(|^static BOOL DMCopyHasStockText\(' "$d/one-hold.inc")" = 4 ] || { echo "FAIL  the hold was not found in $X"; return 99; }
  grep -qF 'objc_setAssociatedObject(fg, kNoClockLayoutKey, (laidOut && (lockedNow || keepsLockedLook))' "$d/one-noclock.inc" || { echo "FAIL  the no-clock layout was not found in $X"; return 99; }
  [ -s "$d/one-locklayout.inc" ] || { echo "FAIL  DMBattLockLayout was not found in $1"; return 99; }
  { fndef "$1" DMBattTypes; fndef "$1" DMBattTypesOf; } > "$d/one-types.inc"
  grep -E '^typedef struct \{ int percent; BOOL onAC, charging, known; \} DMBattInfo;' "$1" > "$d/one-info.inc"
  { fndef "$1" DMBattItemClass; fndef "$1" DMBattViewShown; fndef "$1" DMBattItemViews; } > "$d/one-views.inc"
  awk '/^static BOOL gBattInsideOn = NO;/ {f=1} f {print} f && /^static void DMBattInsideApplyPref\(BOOL on\) \{/ {g=1} g && /^[}]/ {exit}' "$1" > "$d/one-block.inc"
  for f in one-call one-recheck one-types one-info one-views; do [ -s "$d/$f.inc" ] || { echo "FAIL  $f: the code was not found"; return 99; }; done
  grep -q 'DMBattInsideApplyPref' "$d/one-block.inc" && grep -q 'DMBattItemViews' "$d/one-views.inc" || { echo "FAIL  the code was not found in $1"; return 99; }
  for fam in t t17; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" $([ $fam = t17 ] && echo -DT_STUI) \
          -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/$fam" test-battinsideone.m 2> "$d/cc-$fam.txt" || { [ -n "$4" ] || cat "$d/cc-$fam.txt"; echo "FAIL  the real code did not build ($fam)"; return 99; }
    [ -s "$d/cc-$fam.txt" ] && [ -z "$4" ] && { echo "FAIL  warnings ($fam):"; cat "$d/cc-$fam.txt"; return 1; }
  done
  return 0
}

sites() {   # $1 BatteryMenu.h, $2 rules, $3 quiet, $4 StatusBar.x: the number of site checks that fail
  local B=$1 R=$2 q=$3 X=$4 n=0 o blk
  blk=$(awk '/^static BOOL gBattInsideOn = NO;/ {f=1} f {print} f && /^static void DMBattInsideApplyPref\(BOOL on\) \{/ {g=1} g && /^[}]/ {exit}' "$B")
  # added to the battery item's own class only, as the Wi-Fi item's method (StatusBar.x DMStockWiFiInit); no hook of the superclass's
  if echo "$blk" | grep -qF 'Class c = DMBattItemClass();' && echo "$blk" | grep -qF 'class_addMethod(c, sel, (IMP)DMBattInsideCanEnable, method_getTypeEncoding(m))' \
     && ! echo "$blk" | grep -q 'MSHookMessageEx\|method_setImplementation\|method_exchangeImplementations'; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: -canEnableDisplayItem:fromData: added to the battery item's own class (DMBattItemClass) only, nothing swizzled"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: the battery item's answer is not added to its own class alone"; n=$((n + 1)); fi
  # iPadOS's setting never written: nothing in the file writes iPadOS's battery data or SpringBoard's preferences, and the number's block no preference
  if ! grep -q 'setProminentlyShowsDetailString\|SBShowBatteryPercentage\|com\.apple\.springboard' "$B" && ! echo "$blk" | grep -q 'CFPreferencesSet\|NSUserDefaults'; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: iPadOS's Battery Percentage never written (no data or preference write)"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: something writes iPadOS's battery percentage"; n=$((n + 1)); fi
  # the copy's layout pass as the test plays it (OurPass): the -layoutSubviews hook holds the copy, lays it out, releases it when ours; and the
  # no-clock layout is the one that runs DMBattLockLayout (the test's DMLayoutWithoutClock stands in for the rest of it)
  o=$(awk '/^%hook _UIStatusBarForegroundView/ { g = 1 } g && /^- \(void\)layoutSubviews \{/ && !d { f = 1 } f && index($0, "DMHoldStatusBarCopy((UIView *)self);") { h = NR } f && index($0, "[self dm_layoutLogo];") { l = NR }
           f && index($0, "if (objc_getAssociatedObject(self, kLogoKey) || objc_getAssociatedObject(self, kNoClockLayoutKey)) DMReleaseStatusBarCopy((UIView *)self);") { r = NR; d = 1; f = 0 }
           END { print (h && l && r && h < l && l < r) ? "ok" : "no" }' "$X")
  if [ "$o" = ok ] && fndef "$X" DMLayoutWithoutClock | grep -qF '    DMBattLockLayout(fg);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: a copy's layout pass holds, lays out, releases when ours (as the test plays it); the no-clock layout runs DMBattLockLayout"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the copy's layout pass or the no-clock layout is not as the test plays it ($o)"; n=$((n + 1)); fi
  # the crash map: the new functions are Battery Percentage in Icon's (its switch is turned off after a crash in them)
  o=$(python3 -I - "$R" <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'bo'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
for name in ['_DMBattInsideOwnCan', '_DMBattInsideBarOurs', '_DMBattInsideOwnOut', '_DMBattInsideCanEnable', '_DMBattInsideOwnHookInit', '_DMBattInsideOwnAskAgain',
             '_DMBattInsideLockLayout', '___DMBattInsideLockLayout_block_invoke', '___DMBattInsideApplyPref_block_invoke',
             '_DMBattInsideLeftToIOS', '___DMBattInsideLeftToIOS_block_invoke', '_DMBattInsideNumberIn']:
    print(g['classify']('MacStatusBarCore', name, 'BatteryMenu.h', '', rules, im, hits), end=' ')
EOF
)
  if [ "$o" = "batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside " ]; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: the new functions are Battery Percentage in Icon's (classified with make-crashmap.py's own code)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the new functions classify as: $o"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 BatteryMenu.h, $2 BatteryInside.h, $3 rules, $4 dir, $5 quiet, $6 StatusBar.x: the number of checks that fail
  local q=$5 n=0 s out r fam X=${6:-$S0}
  build "$1" "$2" "$4" "$q" "$X"; r=$?; [ $r = 99 ] && return 99; n=$r
  for fam in t t17; do
    for s in $("$4/$fam" list); do
      [ -n "$q" ] || echo "-- $s ($([ $fam = t ] && echo "15/16: _UIStatusBarBatteryItem" || echo "17+: STUIStatusBarBatteryItem"))"
      out=$("$4/$fam" "$s" 2>/dev/null); r=$?
      [ -n "$q" ] || echo "$out"
      [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; }
      n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
    done
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$3" "$q" "$X"; n=$((n + $?)); [ $n -ge 99 ] && n=98
  return $n
}

run "$M0" "$I0" "$R0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-battinsideone: all pass" || echo "test-battinsideone: FAILED ($rc check(s))"
if [ -z "$BO_MENU_H$BO_INSIDE_H$BO_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (menu|inside|sbx), $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" M=$M0 I=$I0 X=$S0 c src
    mkdir -p "$d"
    case $2 in menu) src=$M0; c="$d/BatteryMenu.h"; M=$c;; inside) src=$I0; c="$d/BatteryInside.h"; I=$c;; sbx) src=$S0; c="$d/StatusBar.x"; X=$c;; esac
    perl -0777 -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$M" "$I" "$R0" "$d/w" q "$X"; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "iPadOS's number never left out (the item's answer as iPadOS's)" menu 's/    if \(DMBattInsideOwnOut\(self, displayItem\)\) return NO;\n//'
  mtf "iPadOS's number hidden instead of left out (its room kept: a gap)" menu 's/if \(DMBattInsideOwnOut\(self, displayItem\)\) return NO;/if (DMBattInsideOwnOut(self, displayItem)) ((UIView *)DMCall(displayItem, \@"view")).hidden = YES;/'
  mtf "our bars not asked again when the switch changes" menu 's/DMBattInsideOwnAskAgain\(\); DMBattInsideEveryBar\(\);/DMBattInsideEveryBar();/'
  mtf "the bar's old rule (ours gives way to iPadOS's)" menu 's/MSBDBattInsideOwnLeftOut\(gBattInsideOn, DMBattInsideOwnCan\(\), DMBattInsideBarOurs\(fg\)\), 0, b\.charging\);/0, 0, b.charging);/'
  mtf "left out of every bar, Control Center's too" menu 's/MSBDBattInsideOwnLeftOut\(gBattInsideOn, DMBattInsideOwnCan\(\), DMBattInsideBarOurs\(fg\)\);\n\}/MSBDBattInsideOwnLeftOut(gBattInsideOn, DMBattInsideOwnCan(), 1);\n}/'
  mtf "every display item of the battery left out, its icon too" menu 's/    if \(!ident \|\| !\(ident == gBattInsideOwnID \|\| \[ident isEqual:gBattInsideOwnID\]\)\) return NO;\n//'
  mtf "the superclass's own answer not asked" menu 's/return orig \? orig\(self, _cmd, displayItem, data\) : YES;/return YES;/'
  mtf "the method's types not read" menu 's/ && !strcmp\(method_getTypeEncoding\(m\) \?: "", "B32\@0:8\@16\@24"\)//'
  mtf "the kill switch on the item's answer only (two numbers)" menu 's/MSBDBattInsideOwnLeftOut\(gBattInsideOn, DMBattInsideOwnCan\(\), DMBattInsideBarOurs\(fg\)\), 0, b\.charging\);/MSBDBattInsideOwnLeftOut(gBattInsideOn, gBattInsideOwnHook, DMBattInsideBarOurs(fg)), 0, b.charging);/'
  mtf "the Lock Screen's bar not ours" menu 's/ \|\| objc_getAssociatedObject\(fg, kNoClockLayoutKey\);\n\}/;\n}/'
  mtf "no number at the Lock Screen's layout" menu 's/(static void DMBattInsideLockLayout\(UIView \*fg, BOOL wasOurs\) \{.*?)\n    DMBattInsideBar\(fg\);\n\}/$1\n}/s'
  mtf "a Lock Screen copy newly ours not asked again" menu 's/if \(DMBattInsideBarOurs\(fg\) != wasOurs && gBattInsideOn && DMBattInsideOwnCan\(\)\) \{/if (0) {/'
  mtf "the Lock Screen's bar not asked again when the switch changes" menu 's/if \(!objc_getAssociatedObject\(fg, kLogoKey\) && !objc_getAssociatedObject\(fg, kNoClockLayoutKey\)\) continue;/if (!objc_getAssociatedObject(fg, kLogoKey)) continue;/'
  mtf "the no-clock layout without its part for the number" sbx 's/\n        if \(laidOut\) DMBattInsideLockLayout\(fg, battWasOurs\);//'
  mtf "the number's part before the layout's record (the copy newly ours not seen)" sbx 's/(\n        objc_setAssociatedObject\(fg, kNoClockLayoutKey, \(laidOut[^\n]*)(\n(?:        \/\/[^\n]*\n)*        if \(laidOut\) DMBattInsideLockLayout\(fg, battWasOurs\);)/$2$1/'
  mtf "every layout without a clock marks the bar ours for good (Control Center's header copy, a copy given up)" menu 's/objc_getAssociatedObject\(fg, kNoClockLayoutKey\);\n\}/objc_getAssociatedObject(fg, \&gBattInsideOwnItem);\n}/; s/(static void DMBattInsideLockLayout\(UIView \*fg, BOOL wasOurs\) \{\n)/$1    objc_setAssociatedObject(fg, \&gBattInsideOwnItem, \@YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n/'
  mtf "a copy given up keeps our number (it does not follow iPadOS's)" sbx 's/\n            DMBattInsideLeftToIOS\(v\);[^\n]*//'
  mtf "a copy given up: the number not placed again after its items are asked" menu 's/UIView \*f = weakFg; if \(!f\) return; DMBattInsideBar\(f\); \[f setNeedsLayout\];/UIView *f = weakFg; if (!f) return;/'
  mtf "the hold's text test without our number (a copy whose one text was iPadOS's number waits 30 s)" sbx 's/    return DMBattInsideNumberIn\(fg\);\n\}/    return NO;\n}/'
  mtf "our number not counted while it shows" menu 's/if \(l && !l\.hidden && l\.superview == v && l\.text\.length\) return YES;/if (0) return YES;/'
  mtf "the method added even if the switch is never on" menu 's/    if \(on\) DMBattInsideOwnHookInit\(\);/    DMBattInsideOwnHookInit();/'
  mtf "the rule: left out of any bar, ours or not" inside 's/return on && canLeaveOut && ourBar;/return on \&\& canLeaveOut;/'
  mtf "the rule: iPadOS's number beside the icon still wins in our bars" inside 's/if \(!on \|\| \(iosOwnShown && !ownLeftOut\)\) return 0;/if (!on || iosOwnShown) return 0;/'
fi
exit $rc
