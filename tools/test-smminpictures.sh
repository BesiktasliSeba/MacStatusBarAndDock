#!/bin/bash
# test-smminpictures.sh: the Stage Manager engine's minimized windows -- their marks and their pictures for the grow back out of the Dock (1.8.7.5,
# audit L37, L38 and O6 of 1.8.7.2) -- see test-smminpictures.m. The real code is cut out of statusbar/StatusBar.x (SMP_SB_X: another copy, e.g.
# the code before the fix: what is not in it is stood in for by what that code did -- nothing) and run on the Mac (Mac Catalyst), in a release
# and a DEBUG build; then the site checks; then made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SMP_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }   # one line (a global)
has() { /usr/bin/grep -qF -e "$2" "$1"; }

LINES=('static NSMutableDictionary<NSString *, UIView *> *gSMMinPictures;' 'static NSMutableDictionary<NSString *, UIView *> *gSMGrowing;'
       'static BOOL gSMTurnStartSettled = NO;' 'static char kSMMinPlaceKey,')
FNS=('static NSSet<NSString *> *DMSMWindowKeysIn(NSArray *stages) {' 'static BOOL DMSMIsMinimized(NSString *key) {'
     'static void DMSMMinimizedDrop(NSSet<NSString *> *keys) {' 'static void DMSMSetMinimized(NSString *key, BOOL on) {'
     'static void DMSMKeepMinPicture(NSString *key, UIView *card, UIView *bar, CGRect cardR, CGRect barR, CGRect full, UIView *root) {'
     'static void DMSMForgetApp(NSString *bundle) {')
NEW_CLOSED='static void DMSMMinimizedForgetClosed(void) {'
NEW_FREE='static void DMSMFreeMinPictures(NSString *why) {'
NEW_WATCH='static void DMSMWatchMemoryForPictures(void) {'
NEW_LOOK='static void DMSMMinimizedLook(void) {'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg
  mkdir -p "$d"
  for h in "${LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${FNS[@]}"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  {
    for h in "${LINES[@]}"; do line "$X" "$h"; done
    cutfn "$X" "${FNS[0]}"; cutfn "$X" "${FNS[1]}"; cutfn "$X" "${FNS[2]}"; cutfn "$X" "${FNS[3]}"
    if has "$X" "$NEW_CLOSED"; then cutfn "$X" "$NEW_CLOSED"; else echo 'static void DMSMMinimizedForgetClosed(void) { }   // (not in this source: kept until the next start)'; fi
    # (the look's moments; a source without DMSMMinimizedLook ran it from DMSMWatchTurn under the turn's own gate, the App Switcher's included)
    if has "$X" "$NEW_LOOK"; then cutfn "$X" "$NEW_LOOK"
    else echo 'static void DMSMMinimizedLook(void) { if (!DMSwitcherVisible() && !gMSWSwitching && !DMSMGestureLive() && !DMSMWorkspaceBusy()) DMSMMinimizedForgetClosed(); }   // (not in this source: the turn gate)'; fi
    if has "$X" "$NEW_FREE"; then cutfn "$X" "$NEW_FREE"; fi
    if has "$X" "$NEW_WATCH"; then cutfn "$X" "$NEW_WATCH"; fi
    cutfn "$X" "${FNS[4]}"; cutfn "$X" "${FNS[5]}"
  } > "$d/smp-real.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-smminpictures.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (site checks) the look runs from DMSMWatchTurn (not while a turn waits; its own gate, not the layout notes'), next to the turn's look for
  # closed windows, which keeps its gate; an icon tap looks first, before it reads a mark or a picture; the minimize keeps its picture through
  # DMSMKeepMinPicture; the start's prune (SMHome.h) still drops marks -- now with their pictures -- through DMSMMinimizedDrop
  if cutfn "$X" 'static void DMSMWatchTurn(void) {' | awk '/^        if \(!turnPending && !DMSwitcherVisible\(\) && !gMSWSwitching && !DMSMGestureLive\(\) && !DMSMWorkspaceBusy\(\)\) DMSMTurnForgetClosed\(\);/ {t=NR}
       /^        if \(!turnPending\) DMSMMinimizedLook\(\);/ {l=NR} END {exit !(t && l == t + 1)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMSMWatchTurn looks for gone minimized windows (DMSMMinimizedLook) next to its look for closed windows, which keeps its gate"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMSMWatchTurn does not run DMSMMinimizedLook next to DMSMTurnForgetClosed"; n=$((n + 1)); fi
  if cutfn "$X" 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' | awk '/^    if \(!DMSMEngine\(\) \|\| !bundle.length/ {e=NR} /^    DMSMMinimizedLook\(\);/ && !l {l=NR}
       /DMSMHomeTapBringsWindow|DMSMGrowFromDockAtTap|DMSMIsMinimized|DMSMMinimizedSet|gSMMinPictures|DMMSWSMElsewhereFor/ && !r {r=NR} END {exit !(e && l == e + 1 && r > l)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: an icon tap (DMSMAddToStage) looks for gone minimized windows first, before it reads a mark or a picture"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: an icon tap reads the minimized marks and pictures without a look first"; n=$((n + 1)); fi
  if cutfn "$X" 'static void DMSMFlyToDock(NSString *key) {' | /usr/bin/grep -qF 'DMSMKeepMinPicture(key, card, withBar ? bar : nil, cardR, barR, full, root);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the minimize keeps its picture through DMSMKeepMinPicture"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the minimize does not keep its picture through DMSMKeepMinPicture"; n=$((n + 1)); fi
  if [ -f "$(dirname "$X")/SMHome.h" ] && /usr/bin/grep -qF 'DMSMMinimizedDrop(gone);' "$(dirname "$X")/SMHome.h"; then
    [ -n "$q" ] || echo "PASS  SMHome.h: the start's prune drops gone marks through DMSMMinimizedDrop (their pictures with them)"
  else [ -n "$q" ] || echo "FAIL  SMHome.h: the start's prune does not go through DMSMMinimizedDrop"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$SMP_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"; cp ../statusbar/SMHome.h "$d/SMHome.h"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the eviction back to the dictionary's first key" 's/if \(oldest\) \[gSMMinPictures removeObjectForKey:oldest\];/if (oldest) [gSMMinPictures removeObjectForKey:gSMMinPictures.allKeys.firstObject];/'
  mtf "a picture kept under Reduce Motion" 's/    if \(MSBReduceMotion\(\)\) \{   \/\/ \(no grow under Reduce Motion/    if (0) {   \/\/ (no grow under Reduce Motion/'
  mtf "stages not read whole taken as read" 's/(NSSet<NSString \*> \*present = DMSMWindowKeysIn\(stages\);\n    if \(!present\)) return;\n    NSMutableSet<NSString \*> \*keys = \[DMSMMinimizedSet\(\) mutableCopy\];/$1 present = [NSSet set];\n    NSMutableSet<NSString *> *keys = [DMSMMinimizedSet() mutableCopy];/'
  mtf "the look without the per-window gate" 's/if \(!gSMTurnStartSettled \|\| !DMSMPerWindow\(\) \|\| \(!gSMMinPictures/if (!gSMTurnStartSettled || (!gSMMinPictures/'
  mtf "the look before the start has settled" 's/if \(!gSMTurnStartSettled \|\| !DMSMPerWindow\(\) \|\| \(!gSMMinPictures/if (!DMSMPerWindow() || (!gSMMinPictures/'
  mtf "DMSMMinimizedDrop keeps the pictures" 's/    for \(NSString \*k in keys\) \[gSMMinPictures removeObjectForKey:k\];\n//'
  mtf "DMSMForgetApp keeps the pictures" 's/    for \(NSString \*k in \[gSMMinPictures allKeys\]\) if \(\[DMSMKeyBundle\(k\) isEqualToString:bundle\]\) \[gSMMinPictures removeObjectForKey:k\];\n//'
  mtf "no memory watch" 's/    DMSMWatchMemoryForPictures\(\);\n//'
  mtf "a memory warning frees nothing" 's/(static void DMSMFreeMinPictures\(NSString \*why\) \{\n    NSUInteger n = gSMMinPictures.count;\n    if \(!n\)) return;/$1 return; return;/'
  mtf "the look waits for the App Switcher again" 's/    if \(gMSWSwitching \|\| DMSMGestureLive\(\) \|\| DMSMWorkspaceBusy\(\)\) return;\n    DMSMMinimizedForgetClosed\(\);/    if (DMSwitcherVisible() || gMSWSwitching || DMSMGestureLive() || DMSMWorkspaceBusy()) return;\n    DMSMMinimizedForgetClosed();/'
  mtf "the look inside a workspace transaction" 's/    if \(gMSWSwitching \|\| DMSMGestureLive\(\) \|\| DMSMWorkspaceBusy\(\)\) return;/    if (gMSWSwitching || DMSMGestureLive()) return;/'
  mtf "the look during a switcher gesture or a Mac Switcher slide" 's/    if \(gMSWSwitching \|\| DMSMGestureLive\(\) \|\| DMSMWorkspaceBusy\(\)\) return;/    if (DMSMWorkspaceBusy()) return;/'
  mtf "an icon tap without the look first" 's/\n    DMSMMinimizedLook\(\);   \/\/ \(a minimized window gone since the last look[^\n]*//'
  mtf "the look no longer from DMSMWatchTurn" 's/\n        if \(!turnPending\) DMSMMinimizedLook\(\);[^\n]*//'
  mtf "pictures without a mark not looked at" 's/    if \(gSMMinPictures.count\) \[keys addObjectsFromArray:gSMMinPictures.allKeys\];[^\n]*\n//'
fi
exit $rc
