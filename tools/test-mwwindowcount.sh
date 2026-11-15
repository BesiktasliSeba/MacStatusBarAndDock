#!/bin/bash
# test-mwwindowcount.sh: MilkyWay4's count of the windows on screen leaves out the other Mac Switcher desktops' windows and the closing ones (1.8.7.5,
# audit L33 of 1.8.7.2) -- see test-mwwindowcount.m. The real DMMilkyWayWindowCount and DMVisibleWindowCount and the marks they read are cut out of
# statusbar/StatusBar.x (MWC_SB_X: another copy, e.g. the code before the fix) and run on the Mac (Mac Catalyst), in a release and a DEBUG build;
# then the site checks of their callers; then made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${MWC_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }   # one line (a global)

LINES=('typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;' 'static const void *kMinimizedKey = &kMinimizedKey;'
       'static const void *kMSWAwayKey = &kMSWAwayKey;' 'static const void *kStageClosingKey = &kStageClosingKey;')
FNS=('static BOOL DMWindowMinimized(UIView *window) {' 'static UIWindow *DMMilkyWayLayer(void) {' 'static NSUInteger DMMilkyWayWindowCount(void) {'
     'static NSUInteger DMVisibleWindowCount(void) {')

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg
  mkdir -p "$d"
  for h in "${LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${FNS[@]}"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  { for h in "${LINES[@]}"; do line "$X" "$h"; done; for h in "${FNS[@]}"; do cutfn "$X" "$h"; done; } > "$d/mwc-real.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -o "$d/t$dbg" test-mwwindowcount.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (site checks) the count's users: the Window menu's Minimize All rows, the Dock tap's "no windows over it" test, Home Minimizes (WindowAPI.h), and
  # the menu's host with windows on screen (DMHostFor) -- all of them mean windows the user sees
  if [ "$(/usr/bin/grep -cF 'initWithTitle:@"Minimize All Windows" enabled:DMVisibleWindowCount() + DMNativeVisibleWindowCount() > 0' "$X")" = 3 ] \
     && /usr/bin/grep -qF 'if (!DMVisibleWindowCount() || DMDesiredWindowLevel() == kMilkyWayBackLevel) return NO;' "$X" \
     && cutfn "$X" 'static UIView *DMHostFor(UIView *fg) {' | /usr/bin/grep -qF 'if (bar && fg.window != bar && DMMilkyWayWindowCount() > 0) return bar;' \
     && /usr/bin/grep -qF '(unsigned long)(DMVisibleWindowCount() + DMNativeVisibleWindowCount())' "$(dirname "$X")/WindowAPI.h"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x / WindowAPI.h: Minimize All, the Dock tap's test, Home Minimizes and the menu's host read the count of windows on screen"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x / WindowAPI.h: the count's users are not as expected"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$MWC_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"; cp "$(dirname "$X0")/WindowAPI.h" "$d/WindowAPI.h"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the other desktops' windows counted (the audit's case)" 's/if \(\[objc_getAssociatedObject\(v, kMSWAwayKey\) boolValue\] \|\| \[objc_getAssociatedObject\(v, kStageClosingKey\) boolValue\]\) continue;/if ([objc_getAssociatedObject(v, kStageClosingKey) boolValue]) continue;/'
  mtf "closing windows counted" 's/if \(\[objc_getAssociatedObject\(v, kMSWAwayKey\) boolValue\] \|\| \[objc_getAssociatedObject\(v, kStageClosingKey\) boolValue\]\) continue;/if ([objc_getAssociatedObject(v, kMSWAwayKey) boolValue]) continue;/'
  mtf "hidden windows counted" 's/\|\| v.hidden \|\| DMWindowMinimized\(v\)\) continue;/|| DMWindowMinimized(v)) continue;/'
  mtf "minimized windows counted" 's/\|\| v.hidden \|\| DMWindowMinimized\(v\)\) continue;/|| v.hidden) continue;/'
fi
exit $rc
