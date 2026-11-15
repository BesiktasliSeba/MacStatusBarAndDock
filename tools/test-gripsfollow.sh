#!/bin/bash
# test-gripsfollow.sh: every engine's resize grips follow Tint Resize Handles, Dark Mode and an app's tint coming in late at the watcher's next
# tick (1.8.7.5, review of audit track f, finding 3: engine parity of audit L41) -- see test-gripsfollow.m. The real code is cut out of
# statusbar/StatusBar.x (GF_SB_X: another copy, e.g. the code before the fix: what is not in it is stood in for by what that code did at a tick --
# Zetsu's own pass, Aerial 5's theme tick on a light/dark change) and run on the Mac (Mac Catalyst), in a release and a DEBUG build; then the site
# checks; then made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${GF_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }   # one line (a global)
has() { /usr/bin/grep -qF -e "$2" "$1"; }

LINES=('typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;'
       'static const void *kZetsuGripLKey = &kZetsuGripLKey, *kZetsuGripRKey = &kZetsuGripRKey;'
       'static const CGFloat kResizeGripLength = 13.0, kResizeGripThickness = 2.5;' 'static BOOL gTintGrips = YES;'
       'static const void *kMWGripKey = &kMWGripKey;' 'static const void *kStageGripBLKey = &kStageGripBLKey;' 'static const void *kStageGripBRKey = &kStageGripBRKey;'
       'static const void *kA5ChromeKey = &kA5ChromeKey, *kA5GripBLKey = &kA5GripBLKey,' 'static NSHashTable *gSMCards;' 'static char kSMGripLKey, kSMGripRKey;')
FNS=('static UIView *DMMakeResizeGrip(void) {' 'static UIColor *DMResizeGripColor(BOOL dark) {' 'static UIColor *DMResizeGripColorFor(NSString *bundleID, BOOL dark) {')
NEW_OF='static NSArray<UIView *> *DMWindowedGripsOf(UIView *w) {'
NEW_FOLLOW='static void DMWindowedGripsFollow(void) {'
# (the code before: no look of its own at a tick. What did follow then: Zetsu's pass every tick, DMZetsuMacShape, on its windows shown; Aerial 5's
#  theme tick when its signature changed, light or dark among it, DMAerial5ThemeIfChanged (the rest at its full pass, within a second: not at this
#  tick); our Stage Manager engine's cards at a settings change (DMSMRefreshBars) or a style change (its bar's trait change), laid out and compared
#  (1.8.7.5 L41), not at an app's tint coming in late; Aerial 3.0's and MilkyWay4's only at each window's own next layout)
BEFORE='static void DMWindowedGripsFollow(void) {   // (not in this source: what the code before did at a tick, or at the change itself)
    static int lastDark = -1, lastTint = -1;
    BOOL dark = DMSystemInterfaceStyle() == UIUserInterfaceStyleDark, styleChanged = lastDark >= 0 && lastDark != (int)dark, tintChanged = lastTint >= 0 && lastTint != (int)gTintGrips;
    lastDark = dark; lastTint = gTintGrips;
    if (DMSMEngine()) {
        if (!styleChanged && !tintChanged) return;
        for (UIView *card in gSMCards.allObjects) for (int side = 0; side < 2; side++) {
            UIView *g = objc_getAssociatedObject(card, side == 0 ? &kSMGripLKey : &kSMGripRKey);
            if (g && !g.hidden) g.backgroundColor = DMResizeGripColorFor(DMSMCardBundle(card), card.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
        }
        return;
    }
    if (DMActiveEngine() == DMEngineNone) return;
    for (UIView *w in DMAerialStagesAll()) {
        BOOL zetsu = [w isKindOfClass:NSClassFromString(@"ZetsuWindow")];
        if ((zetsu && w.hidden) || (!zetsu && !styleChanged)) continue;
        for (int side = 0; side < 2; side++) {
            UIView *box = objc_getAssociatedObject(w, zetsu ? (side == 0 ? kZetsuGripLKey : kZetsuGripRKey) : (side == 0 ? kA5GripBLKey : kA5GripBRKey));
            UIView *g = box.hidden ? nil : box.subviews.firstObject; UIColor *c = DMResizeGripColorFor(DMStageBundle(w), dark);
            if (g && ![g.backgroundColor isEqual:c]) g.backgroundColor = c;
        }
    }
}'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg body
  mkdir -p "$d"
  for h in "${LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${FNS[@]}"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  for h in "${LINES[@]}"; do line "$X" "$h"; done > "$d/gf-lines.inc"
  {
    for h in "${FNS[@]}"; do cutfn "$X" "$h"; done
    if has "$X" "$NEW_FOLLOW"; then cutfn "$X" "$NEW_OF"; cutfn "$X" "$NEW_FOLLOW"; else echo "$BEFORE"; fi
  } > "$d/gf-real.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-gripsfollow.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (site checks) the watcher runs the look every tick, after Zetsu's own pass; each engine's own pass colours its grips with the same function and
  # the same light or dark as the look (Aerial 3 DMStyleStage, Aerial 5 DMAerial5Theme, Zetsu DMZetsuMacShape, MilkyWay4 DMRestyleWindowButtons:
  # the screen's style; our Stage Manager engine DMSMPlaceGrips: the card's), so the two never take turns
  body=$(cutfn "$X" 'static void DMSyncWindowsForLibraryBody(void) {')
  if echo "$body" | awk '/DM_PERF\("zetsu", DMWatchZetsu\(\)\);/ {z=NR} /DM_PERF\("grips", DMWindowedGripsFollow\(\)\);/ {g=NR} END {exit !(z && g == z + 1)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the 0.2 s watcher runs DMWindowedGripsFollow every tick, right after Zetsu's own pass"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the watcher does not run DMWindowedGripsFollow after DMWatchZetsu"; n=$((n + 1)); fi
  if cutfn "$X" 'static void DMStyleStage(UIView *stage) {' | /usr/bin/grep -qF 'BOOL dark = DMSystemInterfaceStyle() == UIUserInterfaceStyleDark;' \
     && cutfn "$X" 'static void DMStyleStage(UIView *stage) {' | /usr/bin/grep -qF 'grip.backgroundColor = DMResizeGripColorFor(DMStageBundle(stage), dark);' \
     && cutfn "$X" 'static void DMAerial5Theme(UIView *stage) {' | /usr/bin/grep -qF 'BOOL dark = DMSystemInterfaceStyle() == UIUserInterfaceStyleDark;' \
     && cutfn "$X" 'static void DMAerial5Theme(UIView *stage) {' | /usr/bin/grep -qF 'UIColor *gc = DMResizeGripColorFor(DMStageBundle(stage), dark);' \
     && cutfn "$X" 'static void DMZetsuMacShape(UIWindow *w, UIView *menu, UIView *toolbar) {' | /usr/bin/grep -qF 'BOOL dark = DMSystemInterfaceStyle() == UIUserInterfaceStyleDark;' \
     && cutfn "$X" 'static void DMZetsuMacShape(UIWindow *w, UIView *menu, UIView *toolbar) {' | /usr/bin/grep -qF 'UIColor *gc = DMResizeGripColorFor(DMZetsuWindowBundle(w), dark);' \
     && cutfn "$X" 'static void DMRestyleWindowButtons(AXWindowView *w) {' | /usr/bin/grep -qF 'BOOL darkStyle = DMSystemInterfaceStyle() == UIUserInterfaceStyleDark;' \
     && cutfn "$X" 'static void DMRestyleWindowButtons(AXWindowView *w) {' | /usr/bin/grep -qF 'grip.backgroundColor = DMResizeGripColorFor([w bundleIdentifier], darkStyle);' \
     && cutfn "$X" 'static void DMSMPlaceGrips(UIView *card, NSString *bundle, BOOL show) {' | /usr/bin/grep -qF 'BOOL dark = card.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;' \
     && cutfn "$X" 'static void DMSMPlaceGrips(UIView *card, NSString *bundle, BOOL show) {' | /usr/bin/grep -qF 'grip.backgroundColor = DMResizeGripColorFor(bundle, dark);' \
     && cutfn "$X" 'static void DMSMChrome(UIView *card) {' | /usr/bin/grep -qF 'NSString *bundle = DMSMCardBundle(card);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: every engine's own pass colours its grips as the look does (DMResizeGripColorFor, the same light or dark, the same app)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: an engine's own pass colours its grips with other inputs than the look"; n=$((n + 1)); fi
  if [ -f crashmap-rules.txt ] && re=$(/usr/bin/grep -E '^sym MacStatusBarCore \^_\?\(DMZetsu\|DMAerial\|DMMilky\|DMMinimize\|DMSwap\|DMCascade\|DMRestoreWindow\|DMSaveWindow\|DMRememberStage\|DMWindowed\|' crashmap-rules.txt | awk '{print $3}') \
     && [ -n "$re" ] && echo "_DMWindowedGripsFollow" | /usr/bin/grep -qE "$re" && echo "_DMWindowedGripsOf" | /usr/bin/grep -qE "$re"; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: DMWindowedGripsFollow and DMWindowedGripsOf fall under the window code's rule (windowingEnabled)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the new functions are not under the window code's rule"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$GF_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the watcher no longer runs the look" 's/\n    DM_PERF\("grips", DMWindowedGripsFollow\(\)\);[^\n]*//'
  mtf "the Stage Manager engine's cards left out" 's/(    if \(DMSMEngine\(\)\) \{   \/\/ \(our Stage Manager engine: the cards. grips[^\n]*\n)        for \(UIView \*card in gSMCards.allObjects\) \{/$1        for (UIView *card in @[]) {/'
  mtf "the cards' grips by the screen's style, not the card's" 's/UIColor \*c = DMResizeGripColorFor\(DMSMCardBundle\(card\), card.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark\);/UIColor *c = DMResizeGripColorFor(DMSMCardBundle(card), DMSystemInterfaceStyle() == UIUserInterfaceStyleDark);/'
  mtf "Aerial 3's grips on the stage left out" 's/        if \(g && !g.hidden\) \[out addObject:g\];\n        for \(int e = 0;/        for (int e = 0;/'
  mtf "MilkyWay4's grip on its size changer left out" 's/    Class mw = objc_getClass\("AXWindowView"\);/    Class mw = nil;/'
  mtf "the boxes' grips (Aerial 5, Zetsu) left out" 's/            if \(in && !in.hidden\) \[out addObject:in\];/            (void)in;/'
  mtf "a hidden box's grip coloured too" 's/UIView \*in = box && !box.hidden \? box.subviews.firstObject : nil;/UIView *in = box.subviews.firstObject;/'
  mtf "hidden grips coloured too" 's/        if \(g && !g.hidden\) \[out addObject:g\];\n        for \(int e = 0;/        if (g) [out addObject:g];\n        for (int e = 0;/'
  mtf "every grip written every tick" 's/for \(UIView \*g in gs\) if \(!\[g.backgroundColor isEqual:c\]\) \{ g.backgroundColor = c; took = YES; \}\n            if \(took\) n\+\+;\n        \}\n    \}\n    if \(!n\) return;/for (UIView *g in gs) { g.backgroundColor = c; took = YES; }\n            if (took) n++;\n        }\n    }\n    if (!n) return;/'
  mtf "with no engine of ours too" 's/\} else if \(DMActiveEngine\(\) != DMEngineNone && DMWindowWorkNeeded\(\)\) \{/} else if (DMWindowWorkNeeded()) {/'
fi
exit $rc
