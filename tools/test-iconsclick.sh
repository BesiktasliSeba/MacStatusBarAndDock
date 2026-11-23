#!/bin/bash
# test-iconsclick.sh: a click on iPadOS's own status icons in our bar (the AirPods battery, rotation lock, location, Focus, Wi-Fi with the Wi-Fi
# Menu off, ...) no longer opens Control Center while our Control Center icon shows (1.8.7.9, KT 18 Nov: Control Center opens only from our
# icon) -- see test-iconsclick.m. The swipe down from the top right is other recognizers (SpringBoard's pulls), so it is not touched: the site
# checks keep their hooks as they were. The real code is cut out of statusbar/StatusBar.x (IC_SB_X: another copy, e.g. 1.8.7.8's, where the new
# functions are missing and stood in for by "no": its hook as it was) and statusbar/BatteryMenu.h (IC_MENU_H), and run on the Mac (Mac Catalyst)
# on a stand-in of iPadOS's bar, both families (15/16 UIKit's names, 17+ SystemStatusUI's), in a release and a DEBUG build; then the site checks;
# then made-to-fail copies, each must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
S0=${IC_SB_X:-../statusbar/StatusBar.x}; M0=${IC_MENU_H:-../statusbar/BatteryMenu.h}
fndef() {   # $1 file, $2 name: a static function's definition (not a declaration), whole, by its braces
  awk -v n="$2" '
    !f && $0 ~ ("^(__attribute__\\(\\(noinline\\)\\) )?static [^(=]*[ *]" n "\\(") && index($0, "{") { f = 1 }
    f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }
  ' "$1"
}
hookbody() {   # $1 file, $2 the method's first line: its body inside %hook _UIStatusBar (without the first and last lines)
  awk -v m="$2" '
    $0 == "%hook _UIStatusBar" { h = 1 } h && $0 == "%end" { h = 0 }
    h && !f && $0 == m { f = 1; d = 1; next }
    f { t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit; print }
  ' "$1"
}
block() {   # $1 file, $2 first line: from it to the next "%end" line after a "%end" (a %group with one %hook) -- or a function by its braces
  awk -v s="$2" '!f && index($0, s) == 1 { f = 1 } f { print; if ($0 == "%end") { e++; if (e == 2) exit } }' "$1"
}
BEGIN_M='- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {'
GESTURE_M='- (void)statusBarGesture:(UIGestureRecognizer *)g {'

build() {   # $1 StatusBar.x, $2 BatteryMenu.h, $3 dir, $4 quiet, $5 families, $6 debug values: the test built on that code
  local X=$1 d=$3 fam dbg
  mkdir -p "$d"
  fndef "$X" DMCall > "$d/one-call.inc"; fndef "$2" DMBattItemClass > "$d/one-battclass.inc"; fndef "$X" DMPointOverOurControl > "$d/one-over.inc"
  { fndef "$X" DMIconsClickRefused; fndef "$X" DMBarDropTarget; } > "$d/one-refused.inc"
  grep -q '^static BOOL DMIconsClickRefused(' "$d/one-refused.inc" || echo 'static BOOL DMIconsClickRefused(UIView *bar, UIGestureRecognizer *g) { return NO; }   // (not in this source)' >> "$d/one-refused.inc"
  grep -q '^static void DMBarDropTarget(' "$d/one-refused.inc" || echo 'static void DMBarDropTarget(UIView *bar, UIGestureRecognizer *g) {}   // (not in this source)' >> "$d/one-refused.inc"
  { fndef "$X" DMIconsActionableText; fndef "$X" DMIconsLog; } > "$d/one-log.inc"
  hookbody "$X" "$BEGIN_M" | sed 's/%orig/[super gestureRecognizerShouldBegin:g]/g' > "$d/one-begin.inc"
  hookbody "$X" "$GESTURE_M" | sed 's/%orig/[super statusBarGesture:g]/g' > "$d/one-gesture.inc"
  for f in one-call one-battclass one-over one-begin one-gesture; do [ -s "$d/$f.inc" ] || { echo "FAIL  $f: the code was not found"; return 99; }; done
  grep -q 'DMPointOverOurControl((UIView \*)self, g)' "$d/one-begin.inc" || { echo "FAIL  the hook's -gestureRecognizerShouldBegin: was not found in $X"; return 99; }
  for fam in $5; do for dbg in $6; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" -DDEBUG=$dbg $([ $fam = t17 ] && echo -DT_STUI) \
          -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/$fam-$dbg" test-iconsclick.m 2> "$d/cc-$fam-$dbg.txt" || { [ -n "$4" ] || cat "$d/cc-$fam-$dbg.txt"; echo "FAIL  the real code did not build ($fam, DEBUG=$dbg)"; return 99; }
    [ -s "$d/cc-$fam-$dbg.txt" ] && [ -z "$4" ] && { echo "FAIL  warnings ($fam, DEBUG=$dbg):"; cat "$d/cc-$fam-$dbg.txt"; return 1; }
  done; done
  return 0
}

ifdebug() {   # $1 file, $2 text: is the line holding it inside an "#if DEBUG" (and not in its #else)?
  awk -v s="$2" '
    /^#if DEBUG/ { st[++n] = 1; next } /^#if/ { st[++n] = 0; next } /^#else/ { if (st[n] == 1) st[n] = 2; next } /^#endif/ { n--; next }
    index($0, s) { ok = 0; for (i = 1; i <= n; i++) if (st[i] == 1) ok = 1; print ok ? "yes" : "no"; exit }
  ' "$1"
}
sites() {   # $1 StatusBar.x, $2 BatteryMenu.h, $3 quiet: the number of site checks that fail
  local X=$1 B=$2 q=$3 n=0 o
  ok() { [ -n "$q" ] || echo "PASS  $1"; }
  no() { [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); }
  # the rule is asked only from the bar's own hook, after iPadOS's answer and our controls; the drop only there
  o=$(hookbody "$X" "$BEGIN_M")
  if [ "$(grep -c 'DMIconsClickRefused(' "$X")" = 2 ] && [ "$(grep -c 'DMBarDropTarget(' "$X")" = 2 ] \
     && echo "$o" | grep -qF 'BOOL icons = orig && !over && !old && DMIconsClickRefused((UIView *)self, g);' && echo "$o" | grep -qF 'if (!old) DMBarDropTarget((UIView *)self, g);'; then
    ok "StatusBar.x: DMIconsClickRefused and DMBarDropTarget are called only from %hook _UIStatusBar -gestureRecognizerShouldBegin: (after %orig and our controls)"
  else no "StatusBar.x: the rule or the drop is called elsewhere, or not as the test plays it"; fi
  # -statusBarGesture: as it was (a refused begin never reaches it)
  if [ "$(hookbody "$X" "$GESTURE_M" | shasum | cut -c1-16)" = "$GESTURE_SUM" ]; then ok "StatusBar.x: the hook's -statusBarGesture: unchanged"; else no "StatusBar.x: the hook's -statusBarGesture: changed"; fi
  # the pulls from the top edge, Control Center's region, our icon's own call and our controls' list: byte for byte as in 1.8.7.8 (7e0589ee)
  local g s
  for g in "CCRegionOurIcons" "TopEdgeNote" "TopEdgeTongue" "TopEdgeCCPull"; do
    s=$(block "$X" "%group $g" | shasum | cut -c1-16)
    eval "want=\$SUM_$g"
    [ "$s" = "$want" ] && ok "StatusBar.x: %group $g unchanged (the swipe down from the top right)" || no "StatusBar.x: %group $g changed ($s)"
  done
  # (1.8.8.1, the AirPods menu: its button is one of our controls and stands in as its own icon in the pull region -- exactly that key, once, in
  #  each list; everything else as in 7e0589ee)
  [ "$(fndef "$X" DMOurStatusIconsEdge | sed 's/, {kAirPodsButtonKey, NULL} };/ };/' | shasum | cut -c1-16)" = "$SUM_EDGE" ] && [ "$(fndef "$X" DMOurStatusIconsEdge | grep -o kAirPodsButtonKey | wc -l | tr -d ' ')" -le 1 ] \
    && ok "StatusBar.x: DMOurStatusIconsEdge unchanged but for the AirPods button (1.8.8.1)" || no "StatusBar.x: DMOurStatusIconsEdge changed"
  # (1.8.8.2, Scroll Menus That Don't Fit: the scrolling titles' room is ours too -- exactly that line, once, after the Live Activities' pills)
  [ "$(fndef "$X" DMPointOverOurControl | sed -e 's/kWiFiButtonKey, kAirPodsButtonKey, kSpotButtonKey/kWiFiButtonKey, kSpotButtonKey/' -e '/^    if (DMStripInRoom(fg, p)) return YES;   \/\/ (the scrolling titles/d' | shasum | cut -c1-16)" = "$SUM_OVER" ] && [ "$(fndef "$X" DMPointOverOurControl | grep -o kAirPodsButtonKey | wc -l | tr -d ' ')" -le 1 ] \
       && [ "$(fndef "$X" DMPointOverOurControl | grep -c 'DMStripInRoom')" -le 1 ] \
    && ok "StatusBar.x: DMPointOverOurControl (our controls) unchanged but for the AirPods button (1.8.8.1) and the scrolling titles' room (1.8.8.2)" || no "StatusBar.x: DMPointOverOurControl changed"
  [ "$(fndef "$B" DMBattOpenControlCenter | shasum | cut -c1-16)" = "$SUM_OPEN" ] && ok "BatteryMenu.h: DMBattOpenControlCenter (our icon's call) unchanged" || no "BatteryMenu.h: DMBattOpenControlCenter changed"
  # nothing of ours hooks SpringBoard's region handler or Control Center's indirect action (our icon calls the latter)
  if ! cat "$X" ../statusbar/*.h ../common/*.h | grep -E '^- \([^)]*\)(handleStatusBarHoverActionForRegion:|handleIndirectStatusBarAction)' >/dev/null \
     && ! cat "$X" ../statusbar/*.h ../common/*.h | grep -E '(MSHookMessageEx|method_setImplementation|class_replaceMethod|method_exchangeImplementations)[^;]*(handleStatusBarHoverActionForRegion|handleIndirectStatusBarAction)' >/dev/null; then
    ok "nothing hooks -handleStatusBarHoverActionForRegion: or -handleIndirectStatusBarAction"
  else no "something hooks -handleStatusBarHoverActionForRegion: or -handleIndirectStatusBarAction"; fi
  # the kill switch and the Bluetooth overlay trigger are debug only
  [ "$(ifdebug "$X" 'old = DMTestFlag("/tmp/msb-iconscc");')" = yes ] && [ "$(ifdebug "$X" 'else if ([cmd hasPrefix:@"sbfakebt_"]) {')" = yes ] && [ "$(ifdebug "$X" 'static void DMIconsLog(UIView *bar')" = yes ] \
    && ok "StatusBar.x: the kill switch /tmp/msb-iconscc, DMIconsLog and the sbfakebt_ trigger are inside #if DEBUG" || no "StatusBar.x: the kill switch, DMIconsLog or sbfakebt_ is not debug only"
  return $n
}
# (7e0589ee's, 1.8.7.7 = 1.8.7.8's: the parts this fix must not touch)
GESTURE_SUM=9bbc40588d2e16aa; SUM_CCRegionOurIcons=952ad63de0cbbb8d; SUM_TopEdgeNote=c880d993806434f6; SUM_TopEdgeTongue=4ea19b4b7b85827d; SUM_TopEdgeCCPull=139981b9c37ebb9e
SUM_EDGE=72e978f65bbf875a; SUM_OVER=2558d195262cf5f3; SUM_OPEN=d32f449be5b45279

run() {   # $1 StatusBar.x, $2 BatteryMenu.h, $3 dir, $4 quiet, $5 families, $6 debug values: the number of checks that fail
  local q=$4 n=0 out r fam dbg
  build "$1" "$2" "$3" "$q" "$5" "$6"; r=$?; [ $r = 99 ] && return 99; n=$r
  for fam in $5; do for dbg in $6; do
    [ -n "$q" ] || echo "-- $([ $fam = t ] && echo "15/16: _UIStatusBar" || echo "17+: STUIStatusBar"), $([ $dbg = 1 ] && echo DEBUG || echo release)"
    out=$("$3/$fam-$dbg" 2>/dev/null); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((r - 128))"; }
    n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
  done; done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$2" "$q"; n=$((n + $?)); [ $n -ge 99 ] && n=98
  return $n
}

run "$S0" "$M0" "$W/real" "" "t t17" "0 1"; rc=$?
[ $rc = 0 ] && echo "test-iconsclick: all pass" || echo "test-iconsclick: FAILED ($rc check(s))"
if [ -z "$IC_SB_X$IC_MENU_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression (StatusBar.x, the whole file at once)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"
    perl -0777 -pe "$2" "$S0" > "$c"
    cmp -s "$c" "$S0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    build "$c" "$M0" "$d/w" q "t" "1" >/dev/null; local b=$?
    [ $b = 99 ] && { echo "FAIL  made-to-fail copy \"$1\": did not build"; rc=1; return; }
    local out; out=$("$d/w/t-1" 2>/dev/null); local n=$(echo "$out" | grep -c '^FAIL')
    if [ "$n" -gt 0 ]; then echo "PASS  caught: $1 ($(echo "$out" | grep '^FAIL' | sed -E 's/^FAIL  (C[0-9A-Z]+).*/\1/' | sort -u | tr '\n' ' '))"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "(a) not asked: any recognizer refused (another tweak's gesture)" 's/\n    if \(!\[bar respondsToSelector:sAGR\] \|\| \(\(id \(\*\)\(id, SEL\)\)objc_msgSend\)\(bar, sAGR\) != g\) return NO;   \/\/ \(a\)//'
  mtf "(b) not asked whether the bar is ours (strips, Control Center's header copy)" 's/ \|\| !objc_getAssociatedObject\(fg, kLogoKey\)\) return NO;   \/\/ \(b\) our bar/) return NO;   \/\/ (b) our bar/'
  mtf "(b) not asked whether our icon shows (the Lock Screen look, Battery Menu off with iPadOS's style)" 's/\n    if \(!cc \|\| cc\.hidden \|\| cc\.superview != fg\) return NO;   \/\/ \(b\) our Control Center icon in it//'
  mtf "(c) without the battery test (the time's region refused: Notification Center)" 's/\n    if \(!icons\) return NO;\n/\n/'
  mtf "(c) without the hovered fallback (an iOS that picks the target later)" 's/\n    if \(!target && \[bar respondsToSelector:sHovered\]\) target = [^\n]*//'
  mtf "(d) not asked (a region action iPadOS switched off)" 's/\n    if \(!\[act respondsToSelector:sEnabled\] \|\| ![^\n]*//'
  mtf "(e) not asked (a tap elsewhere while the pointer rests on the icons)" 's/    return \[bar respondsToSelector:sInside\] && [^\n]*/    return YES;/'
  mtf "the target not dropped" 's/\n    if \(!old\) DMBarDropTarget\(\(UIView \*\)self, g\);//'
  mtf "the target dropped for any recognizer" 's/ \|\| \(\(id \(\*\)\(id, SEL\)\)objc_msgSend\)\(bar, sAGR\) != g\) return;\n    \(\(void \(\*\)\(id, SEL, id\)\)objc_msgSend\)\(bar, sSet, nil\);/) return;\n    ((void (*)(id, SEL, id))objc_msgSend)(bar, sSet, nil);/'
  mtf "1.8.7.8's hook (our controls only)" 's/\n    if \(!orig \|\| !\(over \|\| icons\)\) return orig;\n    if \(!old\) DMBarDropTarget\(\(UIView \*\)self, g\);\n    return NO;/\n    return (orig && over) ? NO : orig;/'
  mtf "the AirPods button not one of our controls (1.8.8.1: a click on it would run iPadOS's region action, Control Center without our icon)" 's/kWiFiButtonKey, kAirPodsButtonKey, kSpotButtonKey/kWiFiButtonKey, kSpotButtonKey/'
  mtf "the debug kill switch not read" 's/\n    old = DMTestFlag\("\/tmp\/msb-iconscc"\);[^\n]*//'
fi
exit $rc
