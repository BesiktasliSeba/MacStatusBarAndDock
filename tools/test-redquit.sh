#!/bin/bash
# test-redquit.sh: the red light with the Stage Manager engine quits the app once the window is the app's last one on screen, as on every other
# engine and as Force Quit does; with another window of the app on screen only that window closes (1.8.7.6, REDDOT) -- see test-redquit.m. The real
# DMSMRedLight (when the tree has it), DMLightAction, -[DMSMTitleBar dm_light:], DMForceQuitBundle, DMForceQuit, DMSMForceQuitWindows and
# DMSMItemFor (statusbar/StatusBar.x) are cut out of the source (RQ_SB_X: another copy, e.g. the code before the fix) and run on the Mac (Mac
# Catalyst); then site checks on StatusBar.x; then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${RQ_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
line() { grep -F -m1 -x -- "$2" "$1"; }   # a function written on one line

RQ_SW='static double DMSMForceQuitWindows(NSString *bundleID, BOOL *windowed) {'
RQ_FB='static void DMForceQuitBundle(NSString *bundleID) {'
RQ_FQ='static void DMForceQuit(SBApplication *app) { DMForceQuitBundle([app bundleIdentifier]); }'
RQ_IF='static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {'
RQ_RL='static BOOL DMSMRedLight(NSString *key) {'
RQ_LA='static void DMLightAction(NSInteger which) {'
RQ_DL='- (void)dm_light:(UIButton *)b {'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks
  local X=$1 d=$2 q=$3 n=0 h out
  mkdir -p "$d"
  for h in "$RQ_SW" "$RQ_FB" "$RQ_IF" "$RQ_LA" "$RQ_DL"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  [ -n "$(line "$X" "$RQ_FQ")" ] || { echo "FAIL  $X: no line \"$RQ_FQ\""; return 99; }
  { fn "$X" "$RQ_SW"; fn "$X" "$RQ_FB"; line "$X" "$RQ_FQ"; fn "$X" "$RQ_IF"; fn "$X" "$RQ_RL"; fn "$X" "$RQ_LA"
    echo '@implementation DMSMTitleBar'; fn "$X" "$RQ_DL"; echo '@end'; } > "$d/rq-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-redquit.m 2> "$d/cc.txt" \
    || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (site checks) DMLightAction runs before DMSMRedLight's own place in the file: its declaration comes first (it builds); the crash map's rule for
  # the Stage Manager engine's functions names it (windowingEnabled, as DMSMForceQuitWindows)
  local dcl la
  dcl=$(grep -n '^static BOOL DMSMRedLight(NSString \*key);' "$X" | head -1 | cut -d: -f1); la=$(grep -nF "$RQ_LA" "$X" | head -1 | cut -d: -f1)
  if [ -n "$dcl" ] && [ -n "$la" ] && [ "$dcl" -lt "$la" ]; then [ -n "$q" ] || echo "PASS  StatusBar.x declares DMSMRedLight before DMLightAction (it builds)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMSMRedLight is not declared before DMLightAction"; n=$((n + 1)); fi
  if grep -q '^sym MacStatusBarCore \^_\*DMSM\[A-Z0-9\] windowingEnabled$' crashmap-rules.txt && echo _DMSMRedLight | grep -Eq '^_*DMSM[A-Z0-9]'; then
    [ -n "$q" ] || echo "PASS  the crash map's rule for DMSM functions names DMSMRedLight (windowingEnabled)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: no DMSM rule for DMSMRedLight"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$RQ_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression (whole file)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"
    perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "the title bar's red runs the window's Close again (1.8.7.5)" 's/if \(b\.tag == 0\) DMSMRedLight\(w\);/if (b.tag == 0) DMSMWindowAction(w, \@"close");/'
  mtf "the menu bar's red runs the window's Close again (1.8.7.5)" 's/\(which == 0 \? DMSMRedLight\(smKey\) : DMSMWindowAction\(smKey, \@"removeFromSet"\)\)/DMSMWindowAction(smKey, which == 0 ? \@"close" : \@"removeFromSet")/'
  mtf "the app's last window closes SpringBoard's way, no Force Quit" 's/(the app quits \(as Force Quit\)", DMSMKeyText\(key\)\]\);\n)    DMForceQuitBundle\(bundle\);/$1    DMSMWindowAction(key, \@"close");/'
  mtf "every stage counted, those not on screen too (a minimized window keeps the app)" 's/\n        if \(DMSMIsMainIdentity\(identity\) \? !\(ipad && \[al isEqual:ipad\]\) : !DMSMStageShownOnDisplay\(al, identity\)\) continue;//'
  mtf "only the iPad's desktop counted (the TV's windows not seen)" 's/: !DMSMStageShownOnDisplay\(al, identity\)\) continue;/: YES) continue;/'
  mtf "the window pressed counted among the app's other windows" 's/            else if \(!\[others containsObject:it\]\) \[others addObject:it\];/            if (![others containsObject:it]) [others addObject:it];/'
  mtf "windows told apart by their keys (windows by app share one)" 's/if \(own && \[it isEqual:own\]\) mine = it;/if (own \&\& [DMSMItemKey(it) isEqualToString:DMSMItemKey(own)]) mine = it;/'
  mtf "the window not found on screen quits its app" 's/(not in a stage on screen -- its own Close", DMSMKeyText\(key\)\]\);\n)        return DMSMWindowAction\(key, \@"close"\);/$1        DMForceQuitBundle(bundle); return YES;/'
  mtf "DMSMRedLight declared only at its place again" 's/\nstatic BOOL DMSMRedLight\(NSString \*key\);   \/\/[^\n]*//'
fi
exit $rc
