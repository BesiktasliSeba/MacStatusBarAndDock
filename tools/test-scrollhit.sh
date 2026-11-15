#!/bin/bash
# test-scrollhit.sh: the scroll routing asks our own layer before it walks every window (1.8.7.4, audit O4 of 1.8.7.2). While a native window is
# on screen, each trackpad or mouse scroll SpringBoard gets (60-120 a second, mostly over apps) built the window list and hit-tested every window
# above our layer before the layer's own test, which over an app answers no at once; now the layer is asked first and the windows only for a point
# on a native window, as a touch's own test does. See test-scrollhit.m. The real code is cut out of statusbar/NativeWindow.h and StatusBar.x
# (OS_NATIVE_H / OS_SB_X: other copies, e.g. the code before the fix) and run on the Mac, one scenario per process; then site checks; then
# made-to-fail copies (each takes one part out and must fail); then the proof that the answer is the same for every scroll: random worlds run on
# this code and on the code before the fix (OS_REF_X, else this file with the fix taken out) give the same window for every scroll, the same
# windows asked wherever the layer's test hits, and none asked where it does not.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${OS_SB_X:-../statusbar/StatusBar.x}; N0=${OS_NATIVE_H:-../statusbar/NativeWindow.h}
DECIDE='static BOOL DMNativeScrollIsOurs(UIEvent *event, UIWindow *named) {'
# one function of a file, from its first line to its closing brace
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; next } f { print } f && /^[}]/ { exit }' "$1"; }

cut() {   # $1 StatusBar.x, $2 NativeWindow.h, $3 out .inc: 0 when cut
  local X=$1 N=$2 o=$3
  {
    fn "$N" 'static id DMNativeLayerHitTest(UIWindow *self, SEL _cmd, CGPoint p, UIEvent *e) {'
    fn "$N" 'static UIWindow *DMNativeWindowTaking(CGPoint p, CGFloat aboveLevel) {'
    # (the decision and the hook that makes it once per event, with its state)
    awk -v h="$DECIDE" 'index($0, h) == 1 { f = 1 } f { print } f && index($0, "static id DMScrollWSWindow(id self, SEL _cmd) {") == 1 { s = 1 } s && /^[}]/ { exit }' "$X"
  } > "$o"
  grep -qF "$DECIDE" "$o" && grep -qF 'static id DMScrollWSWindow(id self, SEL _cmd) {' "$o" && grep -qF 'static id (*o_DMScrollWS)(id, SEL);' "$o" &&
    grep -qF 'static UIWindow *DMNativeWindowTaking(CGPoint p, CGFloat aboveLevel) {' "$o" && grep -qF 'static id DMNativeLayerHitTest(' "$o"
}
build() {   # $1 .inc, $2 binary
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$(dirname "$1")" \
        -framework Foundation -framework CoreGraphics -o "$2" test-scrollhit.m 2> "$2.cc.txt"
}

sites() {   # $1 StatusBar.x, $2 NativeWindow.h, $3 quiet: the number of site checks that fail
  local X=$1 N=$2 q=$3 n=0
  if fn "$X" "$DECIDE" | awk '/UIView \*hit = DMNativeLayerHitTest\(layer, @selector\(hitTest:withEvent:\), p, nil\);/ && !a { a = NR }
                              /^    if \(!hit\) return NO;$/ && !b { b = NR } /DMNativeWindowTaking\(sp, layer\.windowLevel\)\) return NO;/ && !c { c = NR }
                              END { exit !(a && b == a + 1 && c > b) }'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the decision asks our layer first and stops at its no, before the windows above it are walked"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMNativeScrollIsOurs walks the windows above the layer before (or without) the layer's own no"; n=$((n + 1)); fi
  if [ "$(fn "$X" "$DECIDE" | grep -c 'DMNativeWindowTaking(')" = 1 ] && [ "$(fn "$X" "$DECIDE" | grep -c 'DMNativeLayerHitTest(')" = 1 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: each of the two tests once per decision"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the decision asks the layer or the windows more than once"; n=$((n + 1)); fi
  if fn "$N" 'static DMNativeWindow *DMNativeWindowAtScreenPoint(CGPoint p) {' | awk '/DMNativeLayerHitTest\(gNativeLayer/ && !a { a = NR } /if \(!hit\) return nil;/ && !b { b = NR }
                                                                                    /DMNativeWindowTaking\(p, gNativeLayer\.windowLevel\)/ && !c { c = NR } END { exit !(a && b > a && c > b) }'; then
    [ -n "$q" ] || echo "PASS  NativeWindow.h: a touch's own test (DMNativeWindowAtScreenPoint) asks in the same order: the layer, then the windows above it"
  else [ -n "$q" ] || echo "FAIL  NativeWindow.h: DMNativeWindowAtScreenPoint no longer asks the layer first (this test's reference)"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 NativeWindow.h, $3 work dir, $4 quiet: the number of failed checks (99: not built)
  local X=$1 N=$2 d=$3 q=$4 n=0 s r out
  mkdir -p "$d"
  cut "$X" "$N" "$d/scrollhit-real.inc" || { echo "FAIL  $X / $N: the decision, the hook or the two tests were not found"; return 99; }
  build "$d/scrollhit-real.inc" "$d/t" || { [ -n "$q" ] || cat "$d/t.cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  for s in $("$d/t" list); do
    [ -n "$q" ] || echo "-- $s"
    out=$("$d/t" "$s"); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; r=1; }
    n=$((n + r))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$N" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$N0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-scrollhit: all pass" || echo "test-scrollhit: FAILED ($rc check(s))"
[ -n "$OS_SB_X$OS_NATIVE_H" ] && exit $rc

# the code before the fix: the two tests in their old order, the fix's comment gone
unfix() { perl -0777 -pe '$n = s/\n    \/\/ \(our own windows first,[^\n]*\n    \/\/ [^\n]*\n(    UIView \*hit = DMNativeLayerHitTest\([^\n]*\n    if \(!hit\) return NO;\n)(    CGPoint sp = [^\n]*\n    if \(DMNativeWindowTaking\(sp[^\n]*\n)/\n$2$1/; END { exit($n == 1 ? 0 : 1) }' "$1"; }

echo "-- made-to-fail copies (each must fail)"
k=0
mtf() {   # $1 what, $2 perl expression on StatusBar.x (the whole file at once), or "unfix"
  local d="$W/m$((++k))" c
  mkdir -p "$d"; c="$d/StatusBar.x"
  if [ "$2" = unfix ]; then unfix "$X0" > "$c"; else perl -0777 -pe "$2" "$X0" > "$c"; fi
  cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
  run "$c" "$N0" "$d/w" q; local n=$?
  if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
}
mtf "the windows walked before the layer's test again (the order before the fix)" unfix
mtf "the layer's no not taken as the answer (the windows walked for every scroll)" 's/(UIView \*hit = DMNativeLayerHitTest\(layer, \@selector\(hitTest:withEvent:\), p, nil\);\n)    if \(!hit\) return NO;\n/$1/'
mtf "the windows above the layer no longer asked (the Dock's platter, a menu, an app window over an inactive Finder)" 's/\n    if \(DMNativeWindowTaking\(sp, layer\.windowLevel\)\) return NO;[^\n]*//'
mtf "the decision made at every ask (the once-per-event memory taken out)" 's/BOOL known = hid && hid == gDMScrollWSHID && ts == gDMScrollWSTime, ours = gDMScrollWSOurs;/BOOL known = NO, ours = gDMScrollWSOurs;/'

echo "-- the same answer for every scroll: random worlds on this code and on the code before the fix"
REF=$OS_REF_X
if [ -z "$REF" ]; then
  REF="$W/ref/StatusBar.x"; mkdir -p "$W/ref"
  unfix "$X0" > "$REF" || { echo "FAIL  the fix could not be taken out of this copy (pass OS_REF_X=<StatusBar.x before the fix>)"; exit 1; }
  echo "   (the code before the fix: this file with the fix taken out)"
else echo "   (the code before the fix: $REF)"; fi
mkdir -p "$W/new" "$W/old"
cut "$X0" "$N0" "$W/new/scrollhit-real.inc" && build "$W/new/scrollhit-real.inc" "$W/new/t" || { echo "FAIL  this code did not build for the traces"; exit 1; }
cut "$REF" "$N0" "$W/old/scrollhit-real.inc" && build "$W/old/scrollhit-real.inc" "$W/old/t" || { cat "$W/old/t.cc.txt"; echo "FAIL  the code before the fix did not build"; exit 1; }
"$W/new/t" trace 1874 400 > "$W/new/trace.txt" || { echo "FAIL  this code crashed in the random worlds"; exit 1; }
"$W/old/t" trace 1874 400 > "$W/old/trace.txt" || { echo "FAIL  the code before the fix crashed in the random worlds"; exit 1; }
# s<n> w<world> <ours|theirs|MIXED> decided <n> layer <0|1> lists <n> hits <windows|->
res=$(paste -d'|' "$W/old/trace.txt" "$W/new/trace.txt" | awk -F'|' '
  { split($1, o, " "); split($2, m, " "); lines++
    if (o[1] != m[1] || o[3] != m[3] || o[5] != m[5] || o[7] != m[7]) { bad++; if (!shown++) print "differ: " $1 " / " $2 > "/dev/stderr" }
    if (m[3] == "MIXED" || o[3] == "MIXED") mixed++
    if (m[3] == "ours") ours++
    if (o[7] == 1) { if (o[9] != m[9] || o[11] != m[11]) { bad++; if (!shown++) print "walk differs where the layer hits: " $1 " / " $2 > "/dev/stderr" } }
    else { if (m[9] != 0 || m[11] != "-") { bad++; if (!shown++) print "a walk where the layer says no: " $2 > "/dev/stderr" } if (o[9] > 0) saved++ }
    lo += o[9]; ln += m[9]; ho += (o[11] == "-" ? 0 : split(o[11], x, "+")); hn += (m[11] == "-" ? 0 : split(m[11], y, "+")) }
  END { printf "%d %d %d %d %d %d %d %d %d\n", lines, bad, mixed, ours, saved, lo, ln, ho, hn }')
read -r lines bad mixed ours saved lo ln ho hn <<< "$res"
if [ "$lines" = 8000 ] && [ "$(wc -l < "$W/old/trace.txt" | tr -d " ")" = 8000 ] && [ "$bad" = 0 ] && [ "$mixed" = 0 ] && [ "$ours" -gt 0 ] && [ "$saved" -gt 0 ] && [ "$ln" -lt "$lo" ]; then
  echo "PASS  400 random worlds, $lines scrolls ($ours ours): the same window for every scroll and the same decision count; where the layer's test hits, the same windows asked in the same order; where it does not, none ($saved scrolls no longer walk): window lists $lo -> $ln, window hit tests $ho -> $hn"
else echo "FAIL  the random worlds: $lines scrolls, $bad differ, $mixed mixed answers, $ours ours, $saved saved, lists $lo -> $ln"; rc=1; fi
exit $rc
