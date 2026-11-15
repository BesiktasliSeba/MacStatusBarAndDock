#!/bin/bash
# test-smminregrow.sh: a Stage Manager window minimized again while it still grows out of its Dock icon flies, and keeps for its next restore, a
# picture with its content and title bar (1.8.7.5, audit L39 of 1.8.7.2) -- see test-smminregrow.m; and the desktop's last window, minimized during
# its restore (its minimize is the Home Screen), gives the grow up first too (review of track f, finding 2). The real DMSMFlyToDock, the window
# action DMSMWindowActionAs and what they use are cut
# out of statusbar/StatusBar.x (SMR_SB_X: another copy, e.g. the code before the fix: what is not in it is stood in for by nothing) and run on the
# Mac (Mac Catalyst), in a release and a DEBUG build; then the site checks; then made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SMR_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }   # one line (a global)
has() { /usr/bin/grep -qF -e "$2" "$1"; }

LINES=('static const void *kSMBarKey = &kSMBarKey;' 'static NSMutableDictionary<NSString *, UIView *> *gSMMinPictures;' 'static char kSMMinPlaceKey,'
       'static char kSMGrowToKey, kSMGrownKey, kSMHeldKey;' 'static NSMutableDictionary<NSString *, UIView *> *gSMGrowing;')
ROOT='static UIView *DMSMScreenRootOf(UIView *card) {'
KEEP='static void DMSMKeepMinPicture(NSString *key, UIView *card, UIView *bar, CGRect cardR, CGRect barR, CGRect full, UIView *root) {'
FLY='static void DMSMFlyToDock(NSString *key) {'
ACT='static BOOL DMSMWindowActionAs(NSString *key, NSString *name, BOOL users) {'
NEW_END='static void DMSMEndGrowNow(NSString *key) {'
OPT=('static void DMSMFreeMinPictures(NSString *why) {' 'static void DMSMWatchMemoryForPictures(void) {')

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg
  mkdir -p "$d"
  for h in "${LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "$ROOT" "$KEEP" "$FLY" "$ACT"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  {
    line "$X" "${LINES[0]}"; line "$X" "${LINES[1]}"
    cutfn "$X" "$ROOT"
    line "$X" "${LINES[2]}"
    for h in "${OPT[@]}"; do if has "$X" "$h"; then cutfn "$X" "$h"; fi; done
    cutfn "$X" "$KEEP"
    line "$X" "${LINES[3]}"; line "$X" "${LINES[4]}"
    if has "$X" "$NEW_END"; then cutfn "$X" "$NEW_END"; fi
    cutfn "$X" "$FLY"
    cutfn "$X" "$ACT"
  } > "$d/smr-real.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-smminregrow.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (site checks) the grow ends before anything else of the minimize, and is pushed to the screen before the pictures are taken; the grow's
  # watch stops by itself once its picture is out of the view tree (showing what it held)
  if cutfn "$X" "$FLY" | awk 'NR == 2 {exit !($0 ~ /^    DMSMEndGrowNow\(key\);$/)}' \
     && cutfn "$X" "$NEW_END" | awk '/\[keep removeFromSuperview\];/{a=NR} /v.alpha = 1.0;/{b=NR} /\[CATransaction flush\];/{c=NR} END{exit !(a && b && c && a < c && b < c)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMSMFlyToDock ends a grow in progress first, flushed to the screen before its pictures"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMSMFlyToDock does not end a grow in progress first"; n=$((n + 1)); fi
  if cutfn "$X" 'static void DMSMGrowWatch(NSString *key, UIView *keep, UIView *root, CFTimeInterval started, CFTimeInterval cardSince) {' \
       | awk 'NR == 3 && /if \(!keep.superview\) \{/ {f=1} f && /for \(UIView \*v in held.allObjects\) v.alpha = 1.0;/ {g=1} f && g && /return;/ {ok=1; exit} END{exit !ok}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the grow's watch stops when its picture is out of the view tree, its held views shown"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the grow's watch does not stop on a picture taken away"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$SMR_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the grow not ended (the audit's case)" 's/(static void DMSMFlyToDock\(NSString \*key\) \{\n)    DMSMEndGrowNow\(key\);\n/$1/'
  mtf "the grow ended after the card's pictures" 's/(static void DMSMFlyToDock\(NSString \*key\) \{\n)    DMSMEndGrowNow\(key\);\n(.*?)(    DMSMKeepMinPicture\(key, card)/$1$2    DMSMEndGrowNow(key);\n$3/s'
  mtf "the held views left out of sight" 's/(\[keep removeFromSuperview\];\n)    for \(UIView \*v in held.allObjects\) v.alpha = 1.0;\n    \[CATransaction flush\];/$1    [CATransaction flush];/'
  mtf "the growing picture left on the stage" 's/(NSHashTable \*held = objc_getAssociatedObject\(keep, &kSMHeldKey\);\n)    \[keep removeFromSuperview\];\n/$1/'
  mtf "the grow's entry kept" 's/(    if \(!keep\) return;\n)    \[gSMGrowing removeObjectForKey:key\];\n(    NSHashTable \*held)/$1$2/'
  mtf "every grow ended, not the window's own" 's/(static void DMSMEndGrowNow\(NSString \*key\) \{\n)/$1    for (NSString *o in [gSMGrowing allKeys]) if (![o isEqualToString:key]) { UIView *kp = gSMGrowing[o]; [gSMGrowing removeObjectForKey:o]; [kp removeFromSuperview]; }\n/'
  mtf "the desktop's last window minimized without ending its grow (review finding 2)" 's/\n        DMSMEndGrowNow\(wk\);   \/\/ \(minimized during its restore[^\n]*//'
  mtf "the last window's grow ended after the Home was asked" 's/\n        DMSMEndGrowNow\(wk\);(   \/\/ \(minimized during its restore[^\n]*)(\n.*?\n        DMSMGoHomeForReal\(\@"the desktop.s last window minimized"\);[^\n]*)/$2\n        DMSMEndGrowNow(wk);$1/s'
  mtf "not flushed before the pictures" 's/(    for \(UIView \*v in held.allObjects\) v.alpha = 1.0;\n)    \[CATransaction flush\];\n(    DM_FEATURE_MARK\("sm-minimize-during-restore"\);)/$1$2/'
fi
exit $rc
