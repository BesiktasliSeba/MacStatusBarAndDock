#!/bin/bash
# test-tvemptyfirst.sh: the TV desktop's last window closing leaves every app launch working and the TV at its own empty desktop (1.8.8.2, B86) --
# see test-tvemptyfirst.m. The real DMSMWindowActionAs and the TV's close (statusbar/StatusBar.x), the request for another display's empty desktop
# (statusbar/MacSwitcherSM.h) and statusbar/SMAfterHome.h are cut out (TE_TREE: another tree, e.g. the code before the fix) and run on the Mac (Mac
# Catalyst) against a world model of SpringBoard, in a release and a DEBUG build; then the site checks; then made-to-fail copies: each takes one part
# of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
T0=${TE_TREE:-..}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
has() { /usr/bin/grep -qF -e "$2" "$1"; }
ACT='static BOOL DMSMWindowActionAs(NSString *key, NSString *name, BOOL users) {'
FIRST='__attribute__((noinline)) static BOOL DMSMTVEmptyFirst(id identity, id item, NSString *wk) {'
TAKE='__attribute__((noinline)) static void DMSMTVTakeOut(id identity, id item, NSString *wk, BOOL ended) {'
OLD='static void DMSMTVEmptyAfterLastWindow(id identity, NSString *what) {'
REQ='static BOOL DMMSWSMRequestEmpty(id identity, NSString *why) {'
GONE='static BOOL DMMSWSMStateNamesGone(id identity) {'
STAGE='static id DMMSWSMStateStage(id identity) {'

run() {   # $1 StatusBar.x, $2 MacSwitcherSM.h, $3 SMAfterHome.h, $4 work dir, $5 quiet: the number of failed checks (99: not cut out or built)
  local X=$1 M=$2 A=$3 d=$4 q=$5 n=0 h out dbg holds=0
  mkdir -p "$d"
  for h in "$ACT"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  [ -n "$(cutfn "$M" "$REQ")" ] || { echo "FAIL  $M: no \"$REQ\""; return 99; }
  has "$A" 'static BOOL DMSMAfterTVEmptyHolds(NSString *bundle, dispatch_block_t block) {' && holds=1
  {
    /usr/bin/grep -v '^#pragma once' "$A"
    /usr/bin/grep -m1 '^static BOOL gMSWSMEmptyTaken = NO;' "$M"
    if has "$M" "$STAGE"; then cutfn "$M" "$STAGE"; fi
    if has "$M" "$GONE"; then cutfn "$M" "$GONE"; fi
    cutfn "$M" "$REQ"
    if has "$X" "$FIRST"; then echo '__attribute__((noinline)) static void DMSMTVTakeOut(id identity, id item, NSString *wk, BOOL ended);'; cutfn "$X" "$FIRST"; cutfn "$X" "$TAKE"; fi
    if has "$X" "$OLD"; then cutfn "$X" "$OLD"; fi
    cutfn "$X" "$ACT"
  } > "$d/te-real.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -DTE_HOLDS=$holds -DMSBD_TV_EMPTY_LONGEST=4.5 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-incompatible-pointer-types -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework QuartzCore -o "$d/t$dbg" test-tvemptyfirst.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  return $n
}

rc=0
run "$T0/statusbar/StatusBar.x" "$T0/statusbar/MacSwitcherSM.h" "$T0/statusbar/SMAfterHome.h" "$W/real"; n=$?; [ $n = 0 ] || rc=1

# ---- the sites (the code the harness cannot reach: the force quit's own clean-up, the hook's TV branch, the crash map's names) ----
site() { if /usr/bin/grep -Eq -- "$2" "$3"; then echo "PASS  site: $1"; else echo "FAIL  site: $1"; rc=1; fi; }
X0=$T0/statusbar/StatusBar.x; A0=$T0/statusbar/SMAfterHome.h; M0=$T0/statusbar/MacSwitcherSM.h
site "the force quit's switcher clean-up waits for the TV's empty desktop" '^    if \(!DMSMAfterTVEmptyHolds\(bundleID, remove\)\) remove\(\);' "$X0"
site "... and so does its second clean-up 0.6 s on" 'dispatch_get_main_queue\(\), \^\{ if \(!DMSMAfterTVEmptyHolds\(bundleID, remove\)\) remove\(\); \}\);' "$X0"
site "the TV desktop's last window: its empty desktop first, before the 1.8.6 close" '^        if \(DMSMTVEmptyFirst\(ownIdentity, ownItem, wk\)\) return YES;' "$X0"
site "the end of a transition on another display goes to the TV's wait" '^            DMSMAfterTVEmptyEnded\(did, ac, tRead, tenv\);' "$A0"
site "the request never from a state naming a stage the model no longer has" '^    if \(DMMSWSMStateNamesGone\(identity\)\) \{' "$M0"
site "no end seen in 4 s: the TV's wait goes on while the stage is on screen" 'dispatch_get_main_queue\(\), \^\{ DMSMAfterTVEmptyCap\(w\); \}\);' "$A0"
site "the TV's close functions keep their own frames (the crash map: windowingEnabled)" '^__attribute__\(\(noinline\)\) static BOOL DMSMTVEmptyFirst\(' "$X0"
if [ -z "$TE_TREE" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 which file (x m a), $3 perl expression
    local d="$W/m$((++k))" X=$X0 M=$M0 A=$A0 c
    mkdir -p "$d"; case $2 in x) c="$d/StatusBar.x"; X=$c; perl -0pe "$3" "$X0" > "$c"; cmp -s "$c" "$X0";; m) c="$d/MacSwitcherSM.h"; M=$c; perl -0pe "$3" "$M0" > "$c"; cmp -s "$c" "$M0";; a) c="$d/SMAfterHome.h"; A=$c; perl -0pe "$3" "$A0" > "$c"; cmp -s "$c" "$A0";; esac
    [ $? = 0 ] && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$X" "$M" "$A" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  mtf "taken out first, then the empty desktop (B86's first version)" x 's/        if \(DMSMTVEmptyFirst\(ownIdentity, ownItem, wk\)\) return YES;\n(.*?)        if \(done\) \{ DM_FEATURE_MARK\("sm-tv-close-last-window"\); DMSMSetMinimized\(wk, NO\); return YES; \}/$1        if (done) { DM_FEATURE_MARK("sm-tv-close-last-window"); DMSMSetMinimized(wk, NO); DMSMTVEmptyFirst(ownIdentity, ownItem, wk); return YES; }/s'
  mtf "the stage taken out at once after asking (no wait for the TV's end)" x 's/    DMSMAfterTVEmpty\(\[NSString stringWithFormat:\@"%\@.s removal from the TV", DMSMKeyText\(k\)\], identity, item, \^\(BOOL ended\) \{ DMSMTVTakeOut\(identity, item, k, ended\); \}\);/    DMSMTVTakeOut(identity, item, k, NO);/'
  mtf "a request SpringBoard took but has not begun counted as nothing asked" x 's/    if \(!asked && !gMSWSMEmptyTaken\) return NO;/    if (!asked) return NO;/'
  mtf "the request from a stale state" m 's/    if \(DMMSWSMStateNamesGone\(identity\)\) \{/    if (0 \&\& DMMSWSMStateNamesGone(identity)) {/'
  mtf "the force quit's clean-up not held" a 's/        \[\(NSMutableArray \*\)w\[5\] addObject:\[block copy\]\];\n(.*?)        return YES;/$1        return NO;/s'
  mtf "the TV's end never told to its wait" a 's/            DMSMAfterTVEmptyEnded\(did, ac, tRead, tenv\);\n//'
  mtf "a window opened again taken out anyway" x 's/    if \(!st \|\| shown \|\| /    if (!st || /'
  mtf "no end seen in 4 s: taken out while the TV or the iPad still shows the stage" a 's/    if \(DMSMTVStageStillShown\(w\[1\], w\[2\]\)\) \{\n        if \(waited/    if (0) {\n        if (waited/'
  mtf "the TV's state not read for the stage still on screen" a 's/    return \(named && \(named == st \|\| \[named isEqual:st\]\)\) \|\| /    return /'
fi
[ $rc = 0 ] && echo "PASS  test-tvemptyfirst: all parts" || echo "FAIL  test-tvemptyfirst"
exit $rc
