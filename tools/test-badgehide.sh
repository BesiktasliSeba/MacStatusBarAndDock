#!/bin/bash
# test-badgehide.sh: Settings' badge hide follows the badge view (macsettings/Badge.x; 1.8.7.7, the M1's Dock badge A/B: Sileo's stored, allowed
# badge not drawn after a respring, its badge view hidden). Badge.x (BADGE_X: another copy, e.g. the code before the fix) goes through Theos's own
# logos.pl and is built, release and DEBUG, with test-badgehide.m: stand-in SpringBoard classes and Substrate's MSHookMessageEx, on the Mac (Mac
# Catalyst: UIKit's own views). Then site checks; then made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
[ -f "$LOGOS" ] || { echo "FAIL  no logos.pl at $LOGOS (THEOS)"; exit 1; }
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${BADGE_X:-../macsettings/Badge.x}
L=../common/HookList.h

sites() {   # $1 Badge.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0 m
  m=$(awk '/^%hook SBIconBadgeView$/ {f=1; next} f && /^%end/ {exit} f && /^- \(/ {print}' "$X")
  if [ "$(echo "$m" | grep -c .)" = 4 ] && echo "$m" | grep -qxF -e '- (void)didMoveToSuperview {' && echo "$m" | grep -qxF -e '- (void)layoutSubviews {' \
     && echo "$m" | grep -qxF -e '- (void)setHidden:(BOOL)hidden {' && echo "$m" | grep -qxF -e '- (void)setAlpha:(CGFloat)alpha {' \
     && [ "$(grep -c '^    {"SBIconBadgeView", ' $L)" = 4 ] && [ "$(grep -c '"macsettings/Badge.x"},' $L)" = 4 ]; then
    [ -n "$q" ] || echo "PASS  Badge.x: the same four badge view hooks, as common/HookList.h lists them (no new hook)"
  else [ -n "$q" ] || echo "FAIL  Badge.x: the badge view hooks are not the four HookList.h lists"; n=$((n + 1)); fi
  if grep -qF 'MSHookMessageEx(cls, sel, (IMP)repl_badgeNumberOrString, (IMP *)&orig_badgeNumberOrString);' "$X" \
     && [ "$(grep -c '^    gHiddenBundleIDs = ' "$X")" = 1 ] && grep -qF 'gHiddenBundleIDs = [NSSet setWithObject:@"com.apple.Preferences"];' "$X"; then
    [ -n "$q" ] || echo "PASS  Badge.x: the value hook as before, for Settings (com.apple.Preferences) only"
  else [ -n "$q" ] || echo "FAIL  Badge.x: the value hook or the hidden apps changed"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 Badge.x, $2 work dir, $3 quiet, $4 builds ("rel dbg"); the number of failed checks (99: the code could not be built)
  local X=$1 d=$2 q=$3 n=0 s b out defs
  mkdir -p "$d/inc"
  printf '#include <objc/runtime.h>\nvoid MSHookMessageEx(Class cls, SEL sel, IMP hook, IMP *old);\n' > "$d/inc/substrate.h"
  perl "$LOGOS" "$X" > "$d/badge.m" 2>"$d/logos.txt" || { cat "$d/logos.txt"; echo "FAIL  logos.pl could not read $X"; return 99; }
  grep -q 'linker_option.*CydiaSubstrate' "$d/badge.m" || { echo "FAIL  logos.pl's output is not as expected (Substrate generator)"; return 99; }
  /usr/bin/sed -i '' '/linker_option.*CydiaSubstrate/d' "$d/badge.m"   # (the stand-in MSHookMessageEx instead)
  for b in ${4:-rel dbg}; do
    [ "$b" = dbg ] && defs=-DDEBUG=1 || defs=
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration $defs -I"$d/inc" \
          -framework UIKit -framework CoreGraphics -o "$d/t-$b" test-badgehide.m "$d/badge.m" 2>"$d/cc-$b.txt" \
      || { cat "$d/cc-$b.txt"; echo "FAIL  the real code did not build ($b)"; return 99; }
    [ -n "$q" ] || { [ -s "$d/cc-$b.txt" ] && cat "$d/cc-$b.txt"; echo "== $([ "$b" = dbg ] && echo DEBUG || echo release) build"; }
    out=$("$d/t-$b"); s=$?
    [ -n "$q" ] || echo "$out"
    n=$((n + s))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$q"; s=$?
  return $((n + s))
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-badgehide: all pass" || echo "test-badgehide: FAILED ($rc)"
if [ -z "$BADGE_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on Badge.x (-0: the whole file)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/Badge.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q rel; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "the hide sticks again (nothing undone when the view leaves)" 's/\} else if \(place == MSBadgeElsewhere\) BadgeUndo\(badge\);/}/'
  mtf "a view taken off undone at once (Settings' badge drawn when it comes back inside another view: review F1)" 's/if \(!badge.superview\) return MSBadgeBetween;/if (!badge.superview) return MSBadgeElsewhere;/'
  mtf "SpringBoard's own hidden YES taken for ours (shown again after)" 's/BadgeNote\(badge, kBadgeOurHidden, hide && !hidden \? \@YES : nil\);/BadgeNote(badge, kBadgeOurHidden, hide ? \@YES : nil);/'
  mtf "the alpha not put back" 's/if \(alpha\) BadgeOwnAlpha\(badge, alpha.doubleValue\);//'
  mtf "our own hide taken for SpringBoard's" 's/(- \(void\)setHidden:\(BOOL\)hidden \{\n)    if \(gBadgeOwnSet\) \{/$1    if (0) {/'
  mtf "in between taken for elsewhere (Settings' badge shown on the way)" 's/\n    return MSBadgeBetween;\n\}/\n    return MSBadgeElsewhere;\n}/'
  mtf "an icon view without an icon taken for another app's" 's/return Call\(v, \@"icon"\) \? MSBadgeElsewhere : MSBadgeBetween;/return MSBadgeElsewhere;/'
  mtf "Settings' badge shown when SpringBoard asks (hidden not held)" 's/%orig\(hide \? YES : hidden\);/%orig(hidden);/'
  mtf "Settings' badge alpha not held at 0" 's/%orig\(hide \? 0.0 : alpha\);/%orig(alpha);/'
  mtf "no hide when the view comes onto Settings' icon" 's/        if \(badge.hidden\) return;\n/        return;\n/'
  mtf "an alpha asked elsewhere leaves our hidden in place" 's/(%orig\(hide \? 0.0 : alpha\);\n)    if \(place == MSBadgeElsewhere\) BadgeUndo\(badge\);/$1/'
  mtf "a hidden asked elsewhere leaves our alpha in place" 's/(%orig\(hide \? YES : hidden\);\n)    if \(place == MSBadgeElsewhere\) BadgeUndo\(badge\);/$1/'
fi
exit $rc
