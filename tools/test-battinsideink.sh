#!/bin/bash
# test-battinsideink.sh: the battery number inside the icon reads at every level (1.8.7.4 round 2, KT 14 Nov: "after lower than like 70% the
# number start to become illegible") -- see test-battinsideink.m. One colour for the whole number left part of it on the wrong side of the fill's
# edge; now two copies, split exactly at the edge of UIKit's own fill, each in the ink that reads on its side. The real code is cut out of
# statusbar/BatteryMenu.h (BI_MENU_H: another copy, e.g. the code before the change) with common/BatteryInside.h (BI_INSIDE_H) and run on the
# Mac (Mac Catalyst) on UIKit's own battery views, one scenario per process; then site checks; then made-to-fail copies, each must fail. With
# it, the Charge Limit's hold of the glyph (BatteryMenu.h's MSBD_BATT_CHARGE block, common/BatteryMenu.h's plug place): its state change turns
# the fill's colour, and the number's inks must follow.
# BI_PICTURES=<dir> (with BI_REF_MENU_H / BI_REF_INSIDE_H: the code before the change): the bar at KT's levels, light and dark, before and after.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${BI_MENU_H:-../statusbar/BatteryMenu.h}; I0=${BI_INSIDE_H:-../common/BatteryInside.h}; R0=crashmap-rules.txt
fnst() { awk -v n="$2(" 'index($0, "static ") == 1 && index($0, n) {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # a static function by its name

build() {   # $1 BatteryMenu.h, $2 BatteryInside.h, $3 dir, $4 quiet: the test built on that code
  local d=$3
  mkdir -p "$d"; cp "$2" "$d/BatteryInside.h"
  { fnst "$1" DMBattTypes; fnst "$1" DMBattTypesOf; } > "$d/bi-types.inc"
  grep -E '^typedef struct \{ int percent; BOOL onAC, charging, known; \} DMBattInfo;' "$1" > "$d/bi-info.inc"
  awk '/^static BOOL gBattInsideOn = NO;/ {f=1} f {print} f && /^static void DMBattInsideApplyPref\(BOOL on\) \{/ {g=1} g && /^[}]/ {exit}' "$1" > "$d/bi-block.inc"
  awk '/^static BOOL gBattHoldPlug = NO;/ {f=1} f && /^#endif/ {exit} f {print}' "$1" > "$d/bi-hold.inc"
  { grep -E '^#define MSBD_BATT_PLUG_(BODY|HEIGHT|HALO)_SHARE ' ../common/BatteryMenu.h; grep -E '^typedef struct \{ double x, y, w, h, halo; \} MSBDBattPlugBox;' ../common/BatteryMenu.h
    fnst ../common/BatteryMenu.h MSBDBattPlugPlace; } > "$d/bi-plug.inc"
  [ -s "$d/bi-types.inc" ] && [ -s "$d/bi-info.inc" ] && grep -q 'DMBattInsideApplyPref' "$d/bi-block.inc" || { echo "FAIL  the code was not found in $1"; return 99; }
  grep -q 'static void DMBattHoldEveryBar(void) {' "$d/bi-hold.inc" && [ "$(grep -c '' "$d/bi-plug.inc")" -ge 9 ] || { echo "FAIL  the charge hold's code was not found in $1 / ../common/BatteryMenu.h"; return 99; }
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/t" test-battinsideink.m 2> "$d/cc.txt" || { [ -n "$4" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$4" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  return 0
}

sites() {   # $1 BatteryMenu.h, $2 rules, $3 quiet: the number of site checks that fail
  local B=$1 R=$2 q=$3 n=0 one o
  one=$(awk '/^__attribute__\(\(noinline\)\) static void DMBattInsideOne\(/ {f=1} f {print} f && /^[}]/ {exit}' "$B")
  # the number's colours: only the two-tone rule's (no other colour rule), the fill read from the battery, both copies masked
  if echo "$one" | grep -q 'MSBDBattInsideInksFor(' && echo "$one" | grep -q 'DMBattInsideFillLayer(v)' && echo "$one" | grep -q 'MSBDBattInsideFillPart(' \
     && [ "$(echo "$one" | grep -c 'DMBattInsideSide(')" = 1 ] && ! grep -q 'MSBDBattInsideTextIsDark' "$B" ../common/BatteryInside.h; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: the number's two copies take MSBDBattInsideInksFor's inks, split at the battery's own fill (DMBattInsideFillLayer, MSBDBattInsideFillPart)"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: the number is not two-tone at the battery's own fill"; n=$((n + 1)); fi
  # both of the power state's notifications look again after iPadOS's bars redraw
  if [ "$(grep -c 'DMBattInsidePowerChanged(); }' "$B")" = 2 ] && fnst "$B" DMBattInsidePowerChanged | grep -q 'dispatch_after'; then
    [ -n "$q" ] || echo "PASS  BatteryMenu.h: both power state notifications run DMBattInsidePowerChanged (now, and again after the bars redraw)"
  else [ -n "$q" ] || echo "FAIL  BatteryMenu.h: a power state notification does not look again after the bars redraw"; n=$((n + 1)); fi
  # the bar's layout as the hold scenarios play it (LayoutPass): the number's pass, then the hold's; the job's notification runs the hold's alone
  if awk '/^        DMBattInsideBar\(fg\);   \/\/ \(Battery Percentage in Icon/ {a=NR} /^        DMBattHoldBar\(fg\);/ {b=NR} END {exit !(a && b == a + 2)}' ../statusbar/StatusBar.x \
     && grep -qF 'notify_register_dispatch(MSBD_CHARGE_STATE, &t, dispatch_get_main_queue(), ^(int tok) { DMBattHoldEveryBar(); });' "$B"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the bar's layout places the number, then the charge hold's glyph (as the test plays it); the job's notification runs the hold's alone"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x / BatteryMenu.h: the layout's or the notification's order is not as the test plays it"; n=$((n + 1)); fi
  # the crash map: every new function of the number is Battery Percentage in Icon's (its switch is turned off after a crash in it)
  o=$(python3 -I - "$R" <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'bi'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
for name in ['_DMBattInsideOne', '_DMBattInsideLabel', '_DMBattInsideSide', '_DMBattInsideFillLayer', '_DMBattInsideRGBA', '_DMBattInsidePowerChanged',
             '___DMBattInsidePowerChanged_block_invoke', '___DMBattInsideApplyPref_block_invoke']:
    print(g['classify']('MacStatusBarCore', name, 'BatteryMenu.h', '', rules, im, hits), end=' ')
EOF
)
  if [ "$o" = "batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside batteryPercentInside " ]; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: the number's new functions are Battery Percentage in Icon's (classified with make-crashmap.py's own code)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the number's functions classify as: $o"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 BatteryMenu.h, $2 BatteryInside.h, $3 rules, $4 dir, $5 quiet: the number of checks that fail
  local q=$5 n=0 s out r
  build "$1" "$2" "$4" "$q"; r=$?; [ $r = 99 ] && return 99; n=$r
  for s in $("$4/t" list); do
    [ -n "$q" ] || echo "-- $s"
    out=$("$4/t" "$s" 2>/dev/null); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; }
    n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$3" "$q"; n=$((n + $?)); [ $n -ge 99 ] && n=98
  return $n
}

if [ -n "$BI_PICTURES" ]; then
  mkdir -p "$BI_PICTURES"
  build "$M0" "$I0" "$W/new" || exit 1
  "$W/new/t" png "$W" after
  if [ -n "$BI_REF_MENU_H" ]; then
    build "$BI_REF_MENU_H" "${BI_REF_INSIDE_H:-$I0}" "$W/old" q || exit 1
    "$W/old/t" png "$W" before
  fi
  for bar in light dark; do
    all=()
    for l in 005 020 035 050 055 065 075 090 100; do
      if [ -f "$W/before-$bar-$l.png" ]; then
        "$W/new/t" compose "$BI_PICTURES/battery-number-$bar-${l#0}.png" "${l#0} % on a $bar bar: before (one colour), after (split at the fill)" 2 "$W/before-$bar-$l.png" "$W/after-$bar-$l.png"
        all+=("$W/before-$bar-$l.png")
      fi
    done
    for l in 005 020 035 050 055 065 075 090 100; do all+=("$W/after-$bar-$l.png"); done
    "$W/new/t" compose "$BI_PICTURES/battery-number-$bar-all.png" "$bar bar, 5 20 35 50 55 65 75 90 100 %$([ -f "$W/before-$bar-005.png" ] && echo ': top row before, bottom row after')" 9 "${all[@]}"
    st=()
    for s in charging lowpower; do
      [ -f "$W/before-$bar-$s-035.png" ] && for l in 035 065 090; do st+=("$W/before-$bar-$s-$l.png"); done
      for l in 035 065 090; do st+=("$W/after-$bar-$s-$l.png"); done
    done
    "$W/new/t" compose "$BI_PICTURES/battery-number-$bar-charging-lowpower.png" "$bar bar, charging and Low Power Mode at 35 65 90 %$([ -f "$W/before-$bar-charging-035.png" ] && echo ': before row, after row')" 3 "${st[@]}"
  done
  echo "   (pictures: $BI_PICTURES)"; ls "$BI_PICTURES" | sed 's/^/   /'
  exit 0
fi

run "$M0" "$I0" "$R0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-battinsideink: all pass" || echo "test-battinsideink: FAILED ($rc check(s))"
if [ -z "$BI_MENU_H$BI_INSIDE_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (menu|inside), $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" M=$M0 I=$I0 c src
    mkdir -p "$d"
    case $2 in menu) src=$M0; c="$d/BatteryMenu.h"; M=$c;; inside) src=$I0; c="$d/BatteryInside.h"; I=$c;; esac
    perl -0777 -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$M" "$I" "$R0" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "one colour again (the copy over the fill never shown)" menu 's/label\.hidden = NO; onFill\.hidden = !split;/label.hidden = NO; onFill.hidden = YES;/'
  mtf "the split guessed from the level, not the battery's fill" menu 's/part = MSBDBattInsideFillPart\(\(MSBDBattInsideBox\)\{ r\.origin\.x, r\.origin\.y, r\.size\.width, r\.size\.height, radius \}/part = MSBDBattInsideFillPart((MSBDBattInsideBox){ 0, 0, frame.size.width * level, frame.size.height, radius }/'
  mtf "the fill's colour not read (the icon's taken: white over a green or yellow fill on a light bar)" menu 's/DMBattInsideRGBA\(fillColour \?: icon, v\.traitCollection, fc\);/DMBattInsideRGBA(icon, v.traitCollection, fc);/'
  mtf "over the fill always the icon's opposite, whatever the fill's colour" inside 's/k\.fillDark = MSBDBattInsideDarkReads\(MSBDBattInsideLuminance\(rgb\[0\], rgb\[1\], rgb\[2\]\)\);/k.fillDark = iconLight;/'
  mtf "the two inks swapped" inside 's/k\.emptyDark = !iconLight;/k.emptyDark = iconLight;/'
  mtf "no second look after the bars redraw" menu 's/\n    dispatch_after\(dispatch_time\(DISPATCH_TIME_NOW, \(int64_t\)\(1\.0 \* NSEC_PER_SEC\)\), dispatch_get_main_queue\(\), \^\{ gBattInsideReadAt = -100; DMBattInsideEveryBar\(\); \}\);//'
  mtf "the copy over the fill left showing when switched off" menu 's/if \(!show\) \{ label\.hidden = YES; onFill\.hidden = YES; return; \}/if (!show) { label.hidden = YES; return; }/'
  mtf "no fill to read: the rest's ink at every level" menu 's/restDark = fill \? inks\.emptyDark : MSBDBattInsideOneInk\(level, inks\);/restDark = inks.emptyDark;/'
  mtf "the fill's corners square, not rounded as the battery rounds them" inside 's/p\.r = fill\.r > 0 \? fill\.r : 0;/p.r = 0;/'
  mtf "the corners from the fill layer only (the static battery draws them into its image)" menu 's/if \(DMBattTypes\(v, \@"_fillLayerFrame:cornerRadius:"/if (0 && DMBattTypes(v, \@"_fillLayerFrame:cornerRadius:"/'
  mtf "a hidden fill read as the fill (its copy of the number over the bare bar)" menu 's/if \(fill && !fill\.hidden\) \{/if (fill) {/'
  mtf "a fill layer outside the battery's own layers taken as its fill" menu 's/    for \(CALayer \*l = fill\.superlayer; l; l = l\.superlayer\) if \(l == v\.layer\) return fill;\n    return nil;/    return fill;/'
  mtf "the number not placed again when the hold changes the battery's state" menu 's/\n    if \(changed\) DMBattInsideBar\(fg\);//'
  mtf "the hold's start not taken as a change of the fill" menu 's/\[v layoutIfNeeded\]; changed = YES; \}/[v layoutIfNeeded]; }/'
  mtf "the hold's end not taken as a change of the fill" menu 's/\[v setNeedsLayout\];\n        return changed;/[v setNeedsLayout];\n        return NO;/'
fi
exit $rc
