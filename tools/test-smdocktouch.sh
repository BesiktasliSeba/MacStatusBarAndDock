#!/bin/bash
# Mac test of a touch on the Dock with the Stage Manager engine (1.8.9, GitHub #20, the second report: a tap on a Dock icon over a window behind another
# brought that window forward too): the functions as built, cut out of statusbar/StatusBar.x and run with stand-ins (test-smdocktouch.m), in a release and a
# DEBUG build; then the wiring (each gate asks the Dock's question; the hooks are the ones Stage Manager's gestures ask); then made-to-fail copies.
# MSBD_TEST_STATUSBAR: another copy of the source.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${MSBD_TEST_STATUSBAR:-../statusbar/StatusBar.x}
fn() { awk -v s="$2" 'index($0, s) == 1 && !f {f=1; print; if ($0 !~ /\{ *(\/\/.*)?$/) exit; next} f {print} f && /^}/ {exit}' "$1"; }   # one function of a file, from its first line (a one-line one too)
FNS=('static BOOL DMSMScreenPointOnDock(CGPoint sp, UIScreen *screen) {' 'static BOOL DMSMTouchOnDock(UITouch *t) {' 'static BOOL DMSMGestureOnDock(UIGestureRecognizer *g) {'
     'static BOOL DMSMScreenPointOnDockPlatter(CGPoint sp, UIScreen *screen) {' 'static BOOL DMSMGestureStartOnDock(UIGestureRecognizer *g) {'
     'static BOOL DMSMTapForwardBegin(id self, SEL _cmd, id g) {' 'static BOOL DMSMTapForwardTouch(id self, SEL _cmd, id g, id touch) {'
     'static BOOL DMSMClickForwardBegin(id self, SEL _cmd, id g) {' 'static BOOL DMSMLiveResizeBegin(id self, SEL _cmd, id g) {'
     'static BOOL DMSMWindowDragLeavesTouch(id manager, UIGestureRecognizer *g, UITouch *t) {')
run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (99: not cut out or not built)
  local X=$1 d=$2 q=$3 n=0 h dbg out
  mkdir -p "$d"
  for h in "${FNS[@]}"; do [ -n "$(fn "$X" "$h")" ] || { [ -n "$q" ] || echo "FAIL  $X: no function \"$h\""; return 99; }; done
  for h in "${FNS[@]}"; do fn "$X" "$h"; done > "$d/smdocktouch-gen.h"
  for dbg in 0 1; do
    clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -DDEBUG=$dbg -I"$d" -framework Foundation -framework CoreGraphics -o "$d/t$dbg" test-smdocktouch.m 2>"$d/cc$dbg.txt" \
      || { [ -n "$q" ] || cat "$d/cc$dbg.txt"; [ -n "$q" ] || echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || echo "FAIL  the DEBUG build answers otherwise ($h, release $n)"; n=$((n + 1)); else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  return $n
}
sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0
  # (the gates are the hooks of Stage Manager's own gesture questions -- as built for the menu bar, 1.8.1 -- and each one asks the Dock's question)
  if grep -qF 'MSHookMessageEx(gm, tf, (IMP)DMSMTapForwardBegin, (IMP *)&o_SMTapForwardBegin);' "$X" && grep -qF 'MSHookMessageEx(gm, tt, (IMP)DMSMTapForwardTouch, (IMP *)&o_SMTapForwardTouch);' "$X" \
     && grep -qF 'MSHookMessageEx(gm, cd, (IMP)DMSMClickForwardBegin, (IMP *)&o_SMClickForwardBegin);' "$X" && grep -qF 'MSHookMessageEx(gm, lr, (IMP)DMSMLiveResizeBegin, (IMP *)&o_SMLiveResizeBegin);' "$X" \
     && grep -qF '@"_shouldTapToBringItemContainerForward:receiveTouch:"' "$X" && grep -qF '@"_shouldBeginTapToBringItemContainerForwardGesture:"' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the gates are the hooks of Stage Manager's tap and click to front and live resize"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: Stage Manager's gesture hooks are not as built"; n=$((n + 1)); fi
  if awk '/^%group DMNativeSysGestures/{f=1} f&&/DMSMWindowDragLeavesTouch\(self, g, touch\)\) return NO;/{a=NR} f&&/return %orig;/{b=NR; exit} END{exit !(a && b > a)}' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the window drag's touch question asks the gate before Apple's answer"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the window drag's touch question does not ask the gate"; n=$((n + 1)); fi
  # (the Dock's question asks a shown Dock window of that screen: SpringBoard's floating Dock, the iPad's and a TV's)
  if fn "$X" 'static BOOL DMSMScreenPointOnDock(CGPoint sp, UIScreen *screen) {' | grep -qF '[NSStringFromClass([w class]) hasPrefix:@"SBFloatingDock"]'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the Dock's question reads SpringBoard's Dock windows"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the Dock's question does not read the Dock's windows"; n=$((n + 1)); fi
  # (the crash map: the new functions are the Stage Manager engine's, windowingEnabled)
  local f bad=0
  for f in DMSMScreenPointOnDock DMSMTouchOnDock DMSMGestureOnDock DMSMScreenPointOnDockPlatter DMSMGestureStartOnDock; do
    [ "$(python3 -I -c 'import re, sys
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) >= 4 and p[0] == "sym" and p[1] == "MacStatusBarCore" and re.search(p[2], "_" + sys.argv[2]): print(p[3]); break' crashmap-rules.txt "$f")" = windowingEnabled ] || bad=$((bad + 1))
  done
  if [ $bad = 0 ]; then [ -n "$q" ] || echo "PASS  crashmap-rules.txt: the Dock's question is the Stage Manager engine's (windowingEnabled)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: $bad new function(s) not under windowingEnabled"; n=$((n + 1)); fi
  return $n
}
run "$X0" "$W/real"; rc=$?
sites "$X0"; s=$?; [ $s -gt 0 ] && rc=1
if [ -z "$MSBD_TEST_STATUSBAR" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" r m
    mkdir -p "$d"; perl -0777 -pe "$2" "$X0" > "$d/StatusBar.x"
    cmp -s "$d/StatusBar.x" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$d/StatusBar.x" "$d/w" q; r=$?; sites "$d/StatusBar.x" q; m=$?
    if { [ $r -gt 0 ] && [ $r -lt 99 ]; } || [ $m -gt 0 ]; then echo "PASS  caught: $1 ($r check(s), $m site check(s) fail)"; else echo "FAIL  not caught: $1 ($r, $m)"; rc=1; fi
  }
  mtf "tap-to-front's touch gate without the Dock (1.8.8.4: a Dock tap over a window behind brings it forward)" 's/    if \(DMSMFree\(\) && \[touch isKindOfClass:\[UITouch class\]\] && DMSMTouchOnDock\(touch\)\) \{/    if (0) {/'
  mtf "tap-to-front's begin without the Dock" 's/^    if \(DMSMFree\(\) && DMSMGestureOnDock\(g\)\) \{ DM_FEATURE_MARK\("sm-dock-tap-not-forward"\); return NO; \}[^\n]*\n//m'
  mtf "the pointer's click without the Dock" 's/^    if \(DMSMFree\(\) && DMSMGestureOnDock\(g\)\) \{ DM_FEATURE_MARK\("sm-dock-click-not-forward"\); return NO; \}[^\n]*\n//m'
  mtf "the live resize from the Dock" 's/^    if \(DMSMFree\(\) && DMSMGestureStartOnDock\(g\)\) \{ DM_FEATURE_MARK\("sm-dock-no-live-resize"\); return NO; \}[^\n]*\n//m'
  mtf "the live resize asked where the finger is now, not where it went down" 's/if \(DMSMFree\(\) && DMSMGestureStartOnDock\(g\)\) \{ DM_FEATURE_MARK\("sm-dock-no-live-resize"\)/if (DMSMFree() \&\& DMSMGestureOnDock(g)) { DM_FEATURE_MARK("sm-dock-no-live-resize")/'
  mtf "the live resize refused in the Dock window's band above its platter (a corner right above the Dock)" 's/    return DMSMScreenPointOnDockPlatter\(\[v convertPoint:p toCoordinateSpace:screen.coordinateSpace\], screen\);/    return DMSMScreenPointOnDock([v convertPoint:p toCoordinateSpace:screen.coordinateSpace], screen);/'
  mtf "a hidden platter taken" 's/            if \(v.hidden \|\| v.alpha < 0.01\) continue;\n//'
  mtf "the Dock window's own answer taken for the Dock" 's/        if \(hit && hit != w\) return YES;/        if (hit) return YES;/'
  mtf "the window drag from the Dock" 's/BOOL dock = !onBar && !own && !menu && DMSMTouchOnDock\(t\);/BOOL dock = NO;/'
  mtf "the whole Dock window taken for the Dock (its pass-through root too)" 's/        if \(hit && hit != w\) return YES;/        if (w) return YES;/'
  mtf "a hidden Dock taken" 's/if \(w.hidden \|\| w.alpha < 0.01 \|\| !w.userInteractionEnabled \|\| \(w.screen \?: \[UIScreen mainScreen\]\) != screen\) continue;\n        if \(!\[NSStringFromClass/if ((w.screen ?: [UIScreen mainScreen]) != screen) continue;\n        if (![NSStringFromClass/'
  mtf "any screen's Dock" 's/if \(w.hidden \|\| w.alpha < 0.01 \|\| !w.userInteractionEnabled \|\| \(w.screen \?: \[UIScreen mainScreen\]\) != screen\) continue;\n        if \(!\[NSStringFromClass/if (w.hidden || w.alpha < 0.01 || !w.userInteractionEnabled) continue;\n        if (![NSStringFromClass/'
fi
exit $rc
