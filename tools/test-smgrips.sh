#!/bin/bash
# test-smgrips.sh: the Stage Manager engine's resize handles follow Settings > Resize Handles, Tint Resize Handles, the app's tint and Dark Mode at
# once, and our own "hide the grabber" is never taken for Apple's (1.8.7.5, audit L41 and L42 of 1.8.7.2) -- see test-smgrips.m. The real code is
# cut out of statusbar/StatusBar.x (SMG_SB_X: another copy, e.g. the code before the fix: what is not in it is left out, as that code had it) and
# run on the Mac (Mac Catalyst), in a release and a DEBUG build; then the site checks; then made-to-fail copies: each breaks one part and must fail.
# With them (1.8.7.5, GRIPS, the iPad 2's check of 1.8.7.5~a02): the grips stay over the window's content when SpringBoard puts its own views of
# the card back on top (DMSMChrome's last word on the order of the card's views, and DMSMChromeOnTop).
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SMG_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }   # one line (a global)
has() { /usr/bin/grep -qF -e "$2" "$1"; }
# one method of a %hook / @implementation block (the first line of the block, then the method's first line), by its braces
meth() { awk -v b="$2" -v s="$3" 'index($0, b) == 1 {inb=1} inb && !f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }

LINES=('static const CGFloat kSMCornerR = 10.0;' 'static BOOL gTintGrips = YES;' 'static BOOL gSMAppleHandles = NO;' 'static const CGFloat kResizeGripLength'
       'static char kSMGripLKey, kSMGripRKey;' 'static char kSMGrabberTintKey;' 'static char kSMGrabberAppleAlphaKey;')
FNS=('static UIView *DMMakeResizeGrip(void) {' 'static UIColor *DMResizeGripColor(BOOL dark) {' 'static void DMSMPlaceGrips(UIView *card, NSString *bundle, BOOL show) {')
REAPPLY='static void DMSMReapplyGrabbers(UIView *card) {'
CHROME='static void DMSMChrome(UIView *card) {'
HOOK='%hook SBAppResizeGrabberView'
BARIMPL='@implementation DMSMTitleBar'
NEW_OWN='static void DMSMGrabberAlphaOurs(UIView *g, CGFloat a) {'
NEW_TRAIT='- (void)traitCollectionDidChange:(UITraitCollection *)previous {'
NEW_TOP='static void DMSMChromeOnTop(UIView *card, UIView *bar) {'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg chk
  mkdir -p "$d"
  for h in "${LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${FNS[@]}" "$REAPPLY" "$CHROME"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  # (DMSMChrome's change check: from the laid-out size to the grips' placing)
  chk=$(cutfn "$X" "$CHROME" | awk '/^    static char kSMLaidSizeKey;$/ {f=1} f {print} f && /DMSMPlaceGrips\(card, bundle, !scaled\);/ {exit}')
  [ -n "$chk" ] && echo "$chk" | tail -1 | /usr/bin/grep -qF 'DMSMPlaceGrips(card, bundle, !scaled);' || { echo "FAIL  $X: no change check in DMSMChrome"; return 99; }
  # (DMSMChrome's last word on the order of the card's views: the lines between the bar's frame and its lights -- before GRIPS the bar alone was
  #  raised there; a copy with nothing there keeps nothing on top)
  local top; top=$(cutfn "$X" "$CHROME" | awk 'index($0, "    if (!CGRectEqualToRect(bar.frame, f)) bar.frame = f;") == 1 {f=1; next} index($0, "    if (!wasShown || bundleChanged) [bar dm_updateLights];") == 1 {exit} f {print}')
  {
    for h in "${LINES[@]}"; do line "$X" "$h"; done
    cutfn "$X" "${FNS[0]}"; cutfn "$X" "${FNS[1]}"; cutfn "$X" "${FNS[2]}"
    echo 'static void KChangeCheck(UIView *card, NSString *bundle, BOOL wasShown, BOOL bundleChanged, BOOL scaled) {'
    echo "$chk"
    echo '}'
    if has "$X" "$NEW_TOP"; then cutfn "$X" "$NEW_TOP"; fi
    echo 'static void KOnTop(UIView *card, UIView *bar) {'
    echo "$top"
    echo '}'
    if has "$X" "$NEW_OWN"; then line "$X" 'static int gSMGrabberOwnAlpha = 0;'; cutfn "$X" "$NEW_OWN"; fi
    cutfn "$X" "$REAPPLY"
    echo '@implementation SBAppResizeGrabberView'
    meth "$X" "$HOOK" '- (void)setAlpha:(CGFloat)a {' | perl -pe 's/^(\s*)%orig\((.*)\);$/$1\[super setAlpha:($2)\];/'
    meth "$X" "$HOOK" '- (void)layoutSubviews {' | perl -pe 's/^(\s*)%orig;$/$1\[super layoutSubviews\];/'
    echo '@end'
    echo '@implementation KBar'
    meth "$X" "$BARIMPL" "$NEW_TRAIT"
    echo '@end'
  } > "$d/smg-real.inc"
  /usr/bin/grep -q '%orig' "$d/smg-real.inc" && { echo "FAIL  a %orig left in the cut code"; return 99; }
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-smgrips.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (site checks) a settings change lays every card out again and puts the grabbers back (DMSMRefreshBars, from DMLoadPrefs's Resize Handles
  # read); the grabber hooks and the bar's trait change are the ones cut out above (a hook of its own for nothing else)
  if cutfn "$X" 'void DMSMRefreshBars(void) {' | /usr/bin/grep -qF 'for (DMSMTitleBar *b in gSMBars.allObjects) { [b dm_updateLights]; [b.card setNeedsLayout]; if (b.card) DMSMReapplyGrabbers(b.card); }' \
     && /usr/bin/grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{ if (DMSMEngine()) DMSMRefreshBars(); });   // (Stage Manager engine only: logic test C1)' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: a Resize Handles change lays every window card out again and puts the grabbers back (DMSMRefreshBars)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: a settings change does not reach every window card"; n=$((n + 1)); fi
  if [ "$(/usr/bin/grep -cF -e "$HOOK" "$X")" = 1 ] && [ "$(awk -v b="$BARIMPL" 'index($0, b) == 1 {f=1} f && /^@end/ {exit} f && /traitCollectionDidChange:/ {n++} END {print n + 0}' "$X")" -le 2 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: one grabber hook, the bar's own trait change only"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: more than one grabber hook, or more trait changes in the bar"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$SMG_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the look left out of the change check (the audit's case)" 's/ \|\| scaledChanged \|\| lookChanged\) DMSMPlaceGrips/ || scaledChanged) DMSMPlaceGrips/'
  mtf "the look without Resize Handles" 's/id look = gSMAppleHandles \? \@"stagemanager" : \(scaled/id look = (scaled/'
  mtf "the look without the colour (tint, Dark Mode)" 's/\(scaled \? \@"none" : DMResizeGripColorFor\(bundle, card.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark\)\)/(scaled ? \@"none" : \@"ours")/'
  mtf "the look never stored" 's/    if \(lookChanged\) objc_setAssociatedObject\(card, &kSMGripLookKey, look, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);\n//'
  mtf "our own write recorded as Apple's (the audit's L42)" 's/    if \(!gSMGrabberOwnAlpha\) objc_setAssociatedObject\(self, &kSMGrabberAppleAlphaKey/    objc_setAssociatedObject(self, &kSMGrabberAppleAlphaKey/'
  mtf "Apple's alpha not kept before our first write" 's/    if \(!objc_getAssociatedObject\(g, &kSMGrabberAppleAlphaKey\)\) objc_setAssociatedObject\(g, &kSMGrabberAppleAlphaKey, \@\(g.alpha\), OBJC_ASSOCIATION_RETAIN_NONATOMIC\);\n//'
  mtf "the layout's hide not marked ours" 's/if \(!gSMAppleHandles && me.alpha > 0\) DMSMGrabberAlphaOurs\(me, 0\);/if (!gSMAppleHandles \&\& me.alpha > 0) me.alpha = 0;/'
  mtf "no relayout at a Dark Mode change" 's/    \[card setNeedsLayout\];\n    DMSMReapplyGrabbers\(card\);\n/    DMSMReapplyGrabbers(card);\n/'
  mtf "the bar's trait change for any trait" 's/    if \(!card \|\| \(previous && previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle\)\) return;/    if (!card) return;/'
  mtf "only the bar kept on top, as before GRIPS (the grips stay under SpringBoard's content)" 's/        if \(g && g.superview == box\) ours\[k\+\+\] = g;\n//'
  mtf "the card's own views read (16's card hands added views to an inner view)" 's/    UIView \*box = bar.superview;/    UIView *box = card;/'
  mtf "ours raised at every layout (the order not looked at)" 's/    if \(onTop\) return;\n//'
  mtf "DMSMChrome no longer keeps ours on top" 's/    DMSMChromeOnTop\(card, bar\);[^\n]*\n//'
  mtf "a grip under SpringBoard's content not logged" 's/    if \(!gripsUnder\) return;/    return;/'
fi
exit $rc
