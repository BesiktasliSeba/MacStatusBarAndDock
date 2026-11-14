#!/bin/bash
# test-keepcoveredmin.sh: the App menu's Minimize with Keep Covered Windows in Front minimizes the window of the app the menu bar names (1.8.7.3,
# audit M10 of 1.8.7.2) -- see test-keepcoveredmin.m. The real DMMinimizeActiveApp, DMActiveApp and the top-window look-ups (statusbar/StatusBar.x)
# and Keep Covered's rule (statusbar/KeepCovered.h) are cut out of the sources (KCM_SB_X / KCM_KC_H: other copies, e.g. the code before the fix)
# and run on the Mac (Mac Catalyst) for Aerial, Zetsu and MilkyWay4; then a site check on StatusBar.x; then made-to-fail copies: each takes one
# part of the fix out (or breaks the menu bar's side of the rule) and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${KCM_SB_X:-../statusbar/StatusBar.x}; K0=${KCM_KC_H:-../statusbar/KeepCovered.h}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                    # one line of a file (a global, a one-line function)

X_FN=('static UIView *DMTopWindow(void) {' 'static UIView *DMTopStageOn(UIScreen *screen) {' 'static BOOL DMWindowsInFront(void) {' 'static BOOL DMWindowsOwnStatusBar(void) {')
X_ONE='static UIView *DMTopStage(void) { return DMTopStageOn(nil); }'
K_ONE=('static BOOL gDMKeepCoveredBusy = NO;' 'static __weak UIView *gDMKeptUnder = nil;' 'static NSHashTable<UIView *> *gDMKeptAbove = nil;' 'static __weak UIView *gDMKeepLastTop = nil;')
K_FN=('static CGRect DMKeepCoveredFrame(UIView *s) {' 'static BOOL DMKeepCoveredShows(UIView *s, UIScreen *scr) {')
K_FORGET='static void DMKeepCoveredForget(void) {'
K_FN2=('__attribute__((noinline)) static void DMKeepCoveredAfterRaise(UIView *w, NSString *why) {' 'static UIView *DMKeepCoveredActive(UIView *top) {' 'static void DMKeepCoveredTouched(UIView *s) {')
X_FN2=('static SBApplication *DMActiveApp(void) {' 'static void DMMinimizeActiveApp(void) {')

run() {   # $1 StatusBar.x, $2 KeepCovered.h, $3 work dir, $4 quiet; the number of failed checks
  local X=$1 K=$2 d=$3 q=$4 n=0 h out
  mkdir -p "$d"
  for h in "${X_FN[@]}" "${X_FN2[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  [ -n "$(line "$X" "$X_ONE")" ] || { echo "FAIL  $X: no line \"$X_ONE\""; return 99; }
  for h in "${K_ONE[@]}" "$K_FORGET"; do [ -n "$(line "$K" "$h")" ] || { echo "FAIL  $K: no line starting \"$h\""; return 99; }; done
  for h in "${K_FN[@]}" "${K_FN2[@]}"; do [ -n "$(fn "$K" "$h")" ] || { echo "FAIL  $K: no function starting \"$h\""; return 99; }; done
  {
    for h in "${K_ONE[@]}"; do line "$K" "$h"; done
    fn "$X" "${X_FN[0]}"; fn "$X" "${X_FN[1]}"; line "$X" "$X_ONE"; fn "$X" "${X_FN[2]}"; fn "$X" "${X_FN[3]}"
    for h in "${K_FN[@]}"; do fn "$K" "$h"; done
    line "$K" "$K_FORGET"
    for h in "${K_FN2[@]}"; do fn "$K" "$h"; done
    for h in "${X_FN2[@]}"; do fn "$X" "$h"; done
  } > "$d/kcm-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-keepcoveredmin.m || { echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (the site check) DMMinimizeActiveApp asks KeepCovered.h's DMKeepCoveredActive, which comes in at the end of StatusBar.x: it is declared before it
  local i f
  i=$(grep -nF 'static UIView *DMKeepCoveredActive(UIView *top);' "$X" | head -1 | cut -d: -f1); f=$(grep -nF "${X_FN2[1]}" "$X" | head -1 | cut -d: -f1)
  if [ -n "$i" ] && [ -n "$f" ] && [ "$i" -lt "$f" ]; then [ -n "$q" ] || echo "PASS  StatusBar.x declares DMKeepCoveredActive before DMMinimizeActiveApp (it builds)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMKeepCoveredActive is not declared before DMMinimizeActiveApp"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$K0" "$W/real"; rc=$?
if [ -z "$KCM_SB_X$KCM_KC_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (sbx|kch), $3 perl expression
    local d="$W/m$((++k))" X=$X0 K=$K0 c
    mkdir -p "$d"
    if [ "$2" = kch ]; then c="$d/KeepCovered.h"; perl -pe "$3" "$K0" > "$c"; K=$c; cmp -s "$c" "$K0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    else c="$d/StatusBar.x"; perl -pe "$3" "$X0" > "$c"; X=$c; cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }; fi
    run "$X" "$K" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "Minimize takes the top window again (Aerial, Zetsu)" sbx 's/\{ DMMinimizeStage\(activeStage\); return; \}/{ DMMinimizeStage(topStage); return; }/'
  mtf "Minimize takes MilkyWay4's top window again" sbx 's/UIView \*top = DMKeepCoveredActive\(DMTopWindow\(\)\);   \/\/ \(MilkyWay4, as above\)/UIView *top = DMTopWindow();/'
  mtf "the menu bar names the top window (Aerial, Zetsu: DMActiveApp without the rule)" sbx 's/\? DMKeepCoveredActive\(DMTopStage\(\)\) : nil;/? DMTopStage() : nil;/'
  mtf "Keep Covered's active window is always the top one" kch 's/^    return a >= 0 && a < n \? stages\[a\] : top;/    (void)a; return top;/'
  mtf "DMKeepCoveredActive declared only further down" sbx '$_ = "" if /^static UIView \*DMKeepCoveredActive\(UIView \*top\);/'
fi
exit $rc
