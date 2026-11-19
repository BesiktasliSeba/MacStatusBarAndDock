#!/bin/bash
# test-barlayoutorder.sh: UIKit's layout order around a held status bar copy's ask (1.8.7.9 W2 and its review: 1.8.7.8~h01 D1, our icons 18 pt left
# for one frame at the unlock after a respring) -- see test-barlayoutorder.m. Built for the Mac (Mac Catalyst) and run on the real UIKit: what
# test-wifirecheck.m's stand-in assumes (T1-T4), then the real code's bar layout right after the ask, cut out of DMBarItemsAskBeforeOurs in
# statusbar/StatusBar.x (BLO_SB_X: another copy, e.g. 1.8.7.8's, where there is none), at both kinds of call site (T5-T7). Then a site check: every
# call of DMBarItemsAskBeforeOurs lays the copy out right after it (T5/T6's call sites). Then made-to-fail copies, each must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${BLO_SB_X:-../statusbar/StatusBar.x}

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (99: not built)
  local X=$1 d=$2 q=$3 n s
  mkdir -p "$d"
  # the lines right after the ask inside its no-animation block: from "asked = DMStockVPNRecheck(fg);" to the block's end (none in the code before 1.8.7.9)
  awk '!f && index($0, "static BOOL DMBarItemsAskBeforeOurs(UIView *fg) {") == 1 { f = 1 } f && /^[}]/ { exit }
       f && a && index($0, "        }];") == 1 { exit } a { print } f && index($0, "            asked = DMStockVPNRecheck(fg);") == 1 { a = 1 }' "$X" > "$d/blo-after.inc"
  /usr/bin/grep -q '^static BOOL DMBarItemsAskBeforeOurs(UIView \*fg) {' "$X" || { echo "FAIL  $X: DMBarItemsAskBeforeOurs was not found"; return 99; }
  [ -n "$q" ] || echo "   (after the ask: $(tr -s ' \n' ' ' < "$d/blo-after.inc" | sed 's/^ //; s/ $//')$( [ -s "$d/blo-after.inc" ] || echo 'nothing'))"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Werror=implicit-function-declaration -I"$d" -framework UIKit -o "$d/t" test-barlayoutorder.m 2> "$d/cc.txt" \
    || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 97; }
  local out; out=$("$d/t" 2>&1); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  # every call of DMBarItemsAskBeforeOurs lays its copy out within the next 4 lines (or on its own line): T5 / T6's call sites
  s=$(awk 'function seen(t) { if (v != "" && index(t, "[" v " layoutIfNeeded]")) { ok++; v = "" } }
           v != "" { seen($0); if (v != "" && --left == 0) { bad++; v = "" } }
           index($0, "DMBarItemsAskBeforeOurs(") && !index($0, "static BOOL DMBarItemsAskBeforeOurs(") {
             if (v != "") { bad++; v = "" }
             t = substr($0, index($0, "DMBarItemsAskBeforeOurs(") + 24); v = substr(t, 1, index(t, ")") - 1); calls++; left = 4
             seen(substr(t, length(v) + 2))
           }
           END { if (v != "") bad++; print calls + 0, ok + 0, bad + 0 }' "$X")
  if [ "$s" = "4 4 0" ]; then [ -n "$q" ] || echo "PASS  StatusBar.x: each of the 4 calls of DMBarItemsAskBeforeOurs lays its copy out right after it (calls, laid out, not: $s)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: a call of DMBarItemsAskBeforeOurs that does not lay its copy out right after it, or a new one (calls, laid out, not: $s)"; n=$((n + 1)); fi
  [ $n -gt 97 ] && n=97
  return $n
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-barlayoutorder: all pass" || echo "test-barlayoutorder: FAILED ($rc check(s))"
if [ -z "$BLO_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 perl expression on StatusBar.x (the whole file at once)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"
    perl -0777 -pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  ASKED='\n            if \(asked\) \{ UIView \*bar = fg\.superview; \[bar setNeedsLayout\]; \[bar layoutIfNeeded\]; \[fg setNeedsLayout\]; \}'
  mtf "the bar not laid out after the held ask (1.8.7.8's way)" "s/$ASKED//"
  mtf "the bar laid out after the held ask without being marked first (W2 as first built)" "s/$ASKED/\n            if (asked) [fg.superview layoutIfNeeded];/"
  mtf "the copy not marked again after the bar's layout" "s/$ASKED/\n            if (asked) { UIView *bar = fg.superview; [bar setNeedsLayout]; [bar layoutIfNeeded]; }/"
  mtf "the copy's layout after the ask dropped at one call site (DMClockBackLayout's \"now\")" 's/else if \(now\) \{ DMBarItemsAskBeforeOurs\(fg\); \[fg layoutIfNeeded\]; \}/else if (now) { DMBarItemsAskBeforeOurs(fg); }/'
fi
exit $rc
