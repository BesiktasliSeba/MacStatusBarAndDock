#!/bin/bash
# test-fitgreen.sh: Fit to Window, green on a tiled window, one rule for Aerial, Zetsu and MilkyWay4: the window going full screen leaves the tiles and
# the others keep theirs; it takes its tile back when it returns; a real close (red) and a quit while full screen close the tiles up (1.8.7.5, audit
# L28 of 1.8.7.2) -- see test-fitgreen.m. The real closure check and the Fit records are cut out of statusbar/StatusBar.x (FG_SB_X: another copy,
# e.g. the code before the fix) and run on the Mac (Mac Catalyst), in a release and a DEBUG build; then the site checks; then made-to-fail copies.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${FG_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }   # one line (a global)
has() { /usr/bin/grep -qF -e "$2" "$1"; }

LINES=('static NSMutableSet<NSString *> *gFreeWindows;' 'static BOOL gMoveKeepsOrder = NO;' 'static NSMutableArray<NSString *> *gFitGroup = nil;'
       'static NSMutableDictionary<NSString *, NSString *> *gFitSlots = nil;' 'static const void *kStageClosingKey = &kStageClosingKey;'
       'static const void *kStageGoingFullKey = &kStageGoingFullKey;' 'static const void *kStageEnteringKey = &kStageEnteringKey;'
       'static NSString *gFSFitBundle; static NSArray<NSString *> *gFSFitGroup;' 'BOOL gFitClosureCheckDue = NO;' 'static NSArray<NSString *> *gFitWatchPrevious = nil;')
FNS=('static void DMFitGroupForget(NSString *bundleID) {' 'static BOOL DMStageTakesPartInFit(UIView *s) {' 'static void DMAssignTilesKeepingPlaces(NSString *fresh) {'
     'static NSString *DMTilesText(NSArray<NSString *> *order, NSDictionary<NSString *, NSString *> *slots) {'
     'static void DMRememberFitForFullScreen(NSString *bundleID) {' 'static void DMFitForgetFullScreenTile(NSString *bundleID) {'
     'static void DMFitFullScreenAppGone(NSString *bundleID) {' 'static void DMFitRejoinAfterFullScreen(NSString *bundleID) {'
     'static void DMFitWatchSync(void) {' 'void DMFitWatchSyncExtern(void) {' 'static void DMWatchFitClosures(void) {')
NEW_LEFT='static BOOL gFSFitLeft = NO;'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg i
  mkdir -p "$d"
  for h in "${LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${FNS[@]}"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  {
    for i in 0 1 2 3 4 5 6; do line "$X" "${LINES[$i]}"; done
    for i in 0 1 2 3; do cutfn "$X" "${FNS[$i]}"; done
    line "$X" "${LINES[7]}"
    if has "$X" "$NEW_LEFT"; then line "$X" "$NEW_LEFT"; fi
    for i in 4 5 6 7; do cutfn "$X" "${FNS[$i]}"; done
    line "$X" "${LINES[8]}"; line "$X" "${LINES[9]}"
    for i in 8 9 10; do cutfn "$X" "${FNS[$i]}"; done
  } > "$d/fg-real.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-fitgreen.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (site checks) every engine's green records the tiles it leaves before its window goes: Aerial's and Zetsu's lights, MilkyWay4's own green; the
  # quit while full screen and the return use the records; the window level still reads only Aerial's mark (not changed here)
  if cutfn "$X" 'static void DMStageLightAction(UIView *stage, NSInteger which) {' | awk '/DMRememberFitForFullScreen\(bundleID\);/{a=NR} /DMZetsuToFullScreen\(\(UIWindow \*\)stage\);/{z=NR} /DMAerialToFullScreen\(stage\);/{e=NR} END{exit !(a && z > a && e > a)}' \
     && cutfn "$X" 'static void DMMilkyWayToFullScreen(AXWindowView *window, NSString *bundleID, id sender) {' | awk '/DMRememberFitForFullScreen\(bundleID\);/{a=NR} /DMExpandWindowToFullScreen\(window, bundleID, sender\);/{b=NR} END{exit !(a && b > a)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: Aerial's, Zetsu's and MilkyWay4's greens record the tiles before the window goes"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: an engine's green does not record the tiles first"; n=$((n + 1)); fi
  if /usr/bin/grep -qF 'DMFitFullScreenAppGone(bundleID);   // (it had gone full screen out of a Fit pair: the tile it kept is closed up now)' "$X" \
     && [ "$(/usr/bin/grep -c 'kStageGoingFullKey, @YES' "$X")" = 1 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the app's exit closes its kept tile up; only Aerial's green sets the window-level mark"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the exit or the window-level mark is not as expected"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$FG_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the named app not taken for full screen (the audit's case)" 's/            if \(!going && named && \(!st \|\| \[objc_getAssociatedObject\(st, kStageClosingKey\) boolValue\]\)\) going = YES;\n//'
  mtf "the record taken more than once a green" 's/BOOL named = !gFSFitLeft && \[b isEqualToString:gFSFitBundle\];/BOOL named = [b isEqualToString:gFSFitBundle];/'
  mtf "the record never marked as used" 's/                if \(named\) gFSFitLeft = YES;\n//'
  mtf "every closing window taken for full screen" 's/if \(!going && named && \(!st/if (!going \&\& (!st/'
  mtf "the green not starting a fresh record" 's/(gFSFitSlots = tiled \? \[gFitSlots copy\] : nil;\n)    gFSFitLeft = NO;\n/$1/'
fi
exit $rc
