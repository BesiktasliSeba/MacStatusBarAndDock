#!/bin/bash
# test-appmenushold.sh: F-7 (p08's rows on the 17.5, 20 Nov, 2 of 2): with one of our menus open before an app's first answer (Go, opened in the
# first second of Maps' cold launch), that answer laid the bar out again under it: Go and its highlight moved ~97 pt right while its menu hung
# where it was, and the closing tap opened Edit. The answer came by the app's word (B12: SpringBoard asks at once), which p08's wait in DMAMAskSoon
# never covered, and so can a title's late answer, the minute's layout and any ask still out when a menu opens. The fix is where the bar lays out
# an answer: while one of our menus or panels is open a copy keeps the app's titles it laid out last (DMAMTitlesToLay), every answer still comes
# in, and once the last of ours is gone the bar is laid out again (DMAMOverlayGone, from DMCloseOverlay and DMRemoveOverlayNow). The real code of
# both sides on real Darwin notifications and the real main run loop (test-appmenushold.m), one scenario per process: AMH_SB = statusbar/AppMenus.h,
# AMH_SBX = statusbar/StatusBar.x (the layout's lines and the two ends of a menu), AMH_APP = appbridge/AppMenus.h (another copy, e.g. before the
# fix); then site checks and made-to-fail copies, each must fail. F-7b (1.8.8.1; p08's device rows: a finger tap on Go 23 ms before Maps' first
# answer re-laid the bar opened nothing, Go had moved from under the finger): a copy keeps the app's titles too while one of its titles is under a
# finger (UIKit tracking the touch on its button), and the end of every title's touch lays it out again (DMLayoutTitle's lines for each title:
# touch.inc; DMAMTitleTouched, DMAMTitleTouchEnded).
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
if [ -n "$AMH_KEEP" ]; then W=$AMH_KEEP; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi   # (AMH_KEEP=<dir>: the builds kept there)
SB0=${AMH_SB:-../statusbar/AppMenus.h}; SBX0=${AMH_SBX:-../statusbar/StatusBar.x}; APP0=${AMH_APP:-../appbridge/AppMenus.h}; RULES=../common/AppMenuRules.h
fnst() { awk -v n="$2(" '(index($0, "static ") == 1 || index($0, "__attribute__((noinline)) static ") == 1) && index($0, n) {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # a static function by its name
fnx() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }                             # a function by its first line
SCEN="word switch tap minute gone front nohold touch touchend"

build() {   # $1 SpringBoard's AppMenus.h, $2 its StatusBar.x, $3 the app's AppMenus.h, $4 dir, $5 quiet
  local d=$4; mkdir -p "$d"; cp "$RULES" "$d/AppMenuRules.h"
  local sub='s/"com\.besiktasliseba\.appbridge\.appmenus"/TSwitchName()/g; s/"com\.besiktasliseba\.appbridge\./TPFX "/g; s/\[NSBundle mainBundle\]\.bundleIdentifier/TBundle()/g'
  { awk '/^static BOOL gAMOn = YES;/ {f=1} f {print} f && /^static void DMAMFrontSeen\(SBApplication \*app\) \{/ {g=1} g && /^[}]/ {exit}' "$1"
    fnst "$1" DMAMApplyPref
    if grep -q '^static void DMAMOverlayGone(void) {' "$1"; then   # (DMAMTitles and the hold after it, to the end of DMAMOverlayGone)
      awk '/^static NSArray<NSString \*> \*DMAMTitles\(NSString \*bundle\) \{/ {f=1} f {print} f && /^static void DMAMOverlayGone\(void\) \{/ {g=1} g && /^[}]/ {exit}' "$1"
    else fnst "$1" DMAMTitles; fi; } | sed -E "$sub" > "$d/sb-block.inc"
  # (the bar layout's own lines, -dm_layoutLogoBody: the app it lays out the titles for, its ask, the titles it lays out)
  awk 'index($0, "    NSString *amBundle = (gAMOn && !finderTitles && appRight > 0 && frontApp) ? [frontApp bundleIdentifier] : nil;") == 1 {f=1}
       f {print} f && index($0, "    NSArray<NSString *> *amWant = ") == 1 {exit}' "$2" > "$d/layout.inc"
  # (what the two ends of one of our menus or panels do for the app's titles)
  fnx "$2" 'static void DMCloseOverlay(void) {' | grep -E '^    DMAM[A-Za-z]+\(\);' > "$d/close.inc"
  fnx "$2" 'static void DMRemoveOverlayNow(void) {' | grep -E '^    DMAM[A-Za-z]+\(\);' > "$d/remove.inc"
  # (what DMLayoutTitle adds to each title's button for the hold, F-7b: none before 1.8.8.1)
  awk 'index($0, "        NSHashTable *titles = objc_getAssociatedObject(fg, kAMTitleButtonsKey);") == 1 {f=1} f {print} f && index($0, "UIControlEventTouchCancel];") {exit}' "$2" > "$d/touch.inc"
  awk 'BEGIN { n = split("MABMenuKeyWindow MABMenuStart MABMenuRoot MABMenuPerform", a, " ") }
       !skip && index($0, "static ") == 1 && /\{$/ { for (i = 1; i <= n; i++) if (index($0, "*" a[i] "(") || index($0, " " a[i] "(")) skip = 1 }
       skip { if ($0 ~ /^[}]/) skip = 0; next } { print }' "$3" \
    | sed -E "$sub"'; s#^\#include "\.\./common/AppMenuRules\.h"#\#include "AppMenuRules.h"#; s/NSTemporaryDirectory\(\)/TTmp()/g' > "$d/app-block.inc"
  [ "$(wc -l < "$d/layout.inc" | tr -d ' ')" = 4 ] && grep -q 'amWant' "$d/layout.inc" && grep -q 'static NSArray<NSString \*> \*DMAMTitles(NSString \*bundle) {' "$d/sb-block.inc" \
    && grep -q 'DMAMFrontSeen' "$d/sb-block.inc" && grep -q 'static void MABRegisterMenus(void) {' "$d/app-block.inc" && ! grep -q 'static UIWindow \*MABMenuKeyWindow(void) {' "$d/app-block.inc" \
    && { ! grep -q 'kAMTitleButtonsKey' "$2" || [ "$(wc -l < "$d/touch.inc" | tr -d ' ')" = 5 ]; } \
    || { echo "FAIL  the code was not found in $1 / $2 / $3"; return 99; }
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -DTPFX="\"test.f7.$$.$RANDOM.\"" -I"$d" \
        -framework UIKit -framework QuartzCore -o "$d/t" test-appmenushold.m 2> "$d/cc.txt" || { [ -n "$5" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$5" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  return 0
}
runall() {   # $1 dir, $2 quiet: the number of scenarios that fail (side by side: each waits on its timers, not the CPU)
  local d=$1 n=0 s
  for s in $SCEN; do ( "$d/t" "$s" > "$d/out-$s.txt" 2>&1; echo $? > "$d/rc-$s" ) & done; wait
  for s in $SCEN; do [ -n "$2" ] || cat "$d/out-$s.txt"; [ "$(cat "$d/rc-$s")" = 0 ] || n=$((n + 1)); done
  echo "$n"
}

fails=0
build "$SB0" "$SBX0" "$APP0" "$W/real" || exit 1
runall "$W/real" > "$W/real.txt"; sed '$d' "$W/real.txt"; [ "$(tail -1 "$W/real.txt")" = 0 ] || fails=1

# site checks (what the scenarios can't see: that the layout and the two ends are where the scenarios cut them from, and nothing else)
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the bar's layout takes the app's titles only through the hold (one call, in -dm_layoutLogoBody; DMAMTitles has no other caller)" \
  "[ \$(grep -c 'DMAMTitlesToLay(' $SBX0) = 1 ] && grep -qxF '    NSArray<NSString *> *amWant = DMAMTitlesToLay(fg, amBundle);   // (kept as they are while one of our menus or panels is open: F-7)' $SBX0 && ! grep -q 'DMAMTitles(' $SBX0 && [ \$(grep -c 'DMAMTitles(' $SB0) = 2 ] && fnst $SB0 DMAMTitlesToLay | grep -qF 'DMAMTitles(bundle)'"
check "both ends of one of our menus or panels lay the waiting titles out, after gOverlay is nil, and nothing else sets it nil" \
  "( for f in 'static void DMCloseOverlay(void) {' 'static void DMRemoveOverlayNow(void) {'; do fnx $SBX0 \"\$f\" | awk '/^    gOverlay = nil;\$/{a=NR} /^    DMAMOverlayGone\\(\\);/{b=NR} END{exit !(a && b && a < b)}' || exit 1; done ) && [ \$(grep -cE '^ *gOverlay = nil;' $SBX0) = 2 ] && [ \$(grep -cE 'gOverlay = [^=]' $SBX0) = 4 ] && [ \$(grep -cxF '    gOverlay = o;' $SBX0) = 1 ] && ! grep -qE 'gOverlay = [^=]' ../statusbar/*.h"
check "the hold is only in those two and the layout (nothing from a constructor; one forward declaration)" \
  "[ \$(cat ../statusbar/*.x ../statusbar/*.h | grep -c 'DMAMOverlayGone();') = 2 ] && [ \$(grep -c 'static void DMAMOverlayGone(void);' $SBX0) = 1 ] && ! grep -qE 'DMAMTitlesToLay|DMAMOverlayGone|gAMHeld|kAMLaidKey' ../appbridge/*.h ../appbridge/*.x"
check "a menu or panel holds only the copies on its own screen (a menu on the TV, the TV's bars; the iPad stays in use beside it: DMSMOurMenuOpenOn's rule)" \
  "fnst $SB0 DMAMTitlesToLay | grep -qxF '    BOOL menu = gOverlay && (fg.window.screen ?: ms) == (gOverlay.window.screen ?: ms);   // (one of ours open on its screen)' && fnst $SB0 DMAMTitlesToLay | grep -qxF '    UIScreen *ms = [UIScreen mainScreen];'"
check "F-7b: a copy holds while one of its own titles is under a finger (only with an app's titles to hold: off, nothing of it is read); every title of the bar is kept for that as DMLayoutTitle makes it, and lays the bar out again at the end of each of its touches (inside, outside, cancelled); nothing else calls them" \
  "fnst $SB0 DMAMTitlesToLay | grep -qxF '    if (!menu && !(bundle.length && DMAMTitleTouched(fg))) {' && fnst $SB0 DMAMTitleTouched | grep -qF 'if (b.tracking) return YES;' && [ \$(cat ../statusbar/*.x ../statusbar/*.h | grep -c 'DMAMTitleTouched(') = 2 ] && [ \$(cat ../statusbar/*.x ../statusbar/*.h | grep -c 'DMAMTitleTouchEnded()') = 1 ] && [ \$(cat ../statusbar/*.x ../statusbar/*.h | grep -c 'kAMTitleButtonsKey') = 4 ] && fnx $SBX0 'static CGFloat DMLayoutTitle(UIView *fg, BOOL rtl, const void *labelKey, const void *buttonKey, const void *pillKey,' | grep -qxF '        [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMAMTitleTouchEnded(); }]' && fnx $SBX0 'static CGFloat DMLayoutTitle(UIView *fg, BOOL rtl, const void *labelKey, const void *buttonKey, const void *pillKey,' | grep -qxF '      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];' && fnx $SBX0 'static CGFloat DMLayoutTitle(UIView *fg, BOOL rtl, const void *labelKey, const void *buttonKey, const void *pillKey,' | grep -qxF '        [titles addObject:btn];' && ! grep -qE 'DMAMTitleTouch|kAMTitleButtonsKey' ../appbridge/*.h ../appbridge/*.x"
check "F-7b: the finger's end lays the bar out a turn later (UIKit may still track the touch while its actions run), and only when something waited" \
  "fnst $SB0 DMAMTitleTouchEnded | sed -n 2,3p | tr -d '\\n' | grep -qF '    if (!gAMHeld) return;   // (nothing waited)    dispatch_async(dispatch_get_main_queue(), ^{'"
check "the crash guard: the new functions are in AppMenus.h, whose crash turns Show Apps' Own Menus off (the hold kept out of line: -Os put it in the bar's layout; the finger's end too, called from StatusBar.x)" \
  "grep -qxF 'file MacStatusBarCore ^AppMenus\\.h\$ appOwnMenus' crashmap-rules.txt && grep -q '^__attribute__((noinline)) static NSArray<NSString \\*> \\*DMAMTitlesToLay(UIView \\*fg, NSString \\*bundle) {' $SB0 && grep -q '^static void DMAMOverlayGone(void) {' $SB0 && grep -q '^__attribute__((noinline)) static void DMAMTitleTouchEnded(void) {' $SB0 && grep -q '^static BOOL DMAMTitleTouched(UIView \\*fg) {' $SB0"
check "no em dash in the test" "! grep -q \$'\\xe2\\x80\\x94' test-appmenushold.m test-appmenushold.sh"

# made-to-fail copies: each must make at least one scenario fail
mtf() {   # $1 what, $2 file (sb|sbx|app), $3 sed
  local d="$W/m$((++mi))" s=$SB0 x=$SBX0 a=$APP0 src out
  mkdir -p "$d"
  case $2 in sb) src=$SB0; s="$d/AppMenus-sb.h"; out=$s;; sbx) src=$SBX0; x="$d/StatusBar.x"; out=$x;; *) src=$APP0; a="$d/AppMenus-app.h"; out=$a;; esac
  sed -E "$3" "$src" > "$out"; cmp -s "$out" "$src" && { echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; }
  build "$s" "$x" "$a" "$d/b" q || { echo "PASS  made-to-fail ($1): caught (does not build)"; return; }
  local k; k=$(runall "$d/b" q | tail -1)
  if [ "$k" -gt 0 ]; then echo "PASS  made-to-fail ($1): caught ($k scenarios fail)"; else echo "FAIL  made-to-fail ($1): not caught"; fails=1; fi
}
mi=0
mtf "the layout takes the answer as it comes (1.8.8 RC 2, p08)" sbx 's/DMAMTitlesToLay\(fg, amBundle\);/amBundle ? DMAMTitles(amBundle) : @[];/'
mtf "the hold never holds" sb 's/^    if \(!menu && !\(bundle\.length && DMAMTitleTouched\(fg\)\)\) \{$/    if (1) {/'
mtf "a menu holds the copies on every other screen instead of its own" sb 's/\(fg\.window\.screen \?: ms\) == \(gOverlay\.window\.screen \?: ms\)/(fg.window.screen ?: ms) != (gOverlay.window.screen ?: ms)/'
mtf "nothing laid out again once ours is gone" sb '/^    for \(UIView \*fg in gCopies\.allObjects\) \[fg setNeedsLayout\];$/d'
mtf "the hold not noted" sb '/^        gAMHeld = YES;$/d'
mtf "the hold keeps another app's titles for the app in front" sb 's/bundle\.length && \[laid\[0\] isEqual:bundle\] \? laid\[1\] : @\[\];/laid ? laid[1] : @[];/'
mtf "DMCloseOverlay lays nothing out again" sbx '/^    DMAMOverlayGone\(\);   \/\/ \(the app.s titles that waited under it are laid out now -- F-7\)$/d'
mtf "DMRemoveOverlayNow lays nothing out again" sbx '/^    DMAMOverlayGone\(\);   \/\/ \(the app.s titles that waited under it are laid out at the end of this turn/d'
mtf "laid out again at once, before the next menu of a switch is open" sb 's/^    for \(UIView \*fg in gCopies\.allObjects\) \[fg setNeedsLayout\];$/    for (UIView *fg in gCopies.allObjects) { [fg setNeedsLayout]; [fg layoutIfNeeded]; }/'
mtf "the bar laid out again at every close, with nothing that waited" sb 's/^    if \(!gAMHeld\) return;$/    (void)0;/'
mtf "SpringBoard asks a move under one of our open menus" sb '/^        if \(gOverlay\) \{ DMAMAskSoon\(b, 1\.0\); return; \}$/d'
# (F-7b)
mtf "no hold for a title under a finger (1.8.8)" sb 's/^    if \(!menu && !\(bundle\.length && DMAMTitleTouched\(fg\)\)\) \{$/    if (!menu) {/'
mtf "the titles' buttons not kept for the hold" sbx 's/^        \[titles addObject:btn\];$/        (void)titles;/'
mtf "nothing laid out again as the finger lifts" sbx 's/\{ DMAMTitleTouchEnded\(\); \}/{ }/'
mtf "laid out again in the touch's own turn (UIKit still tracking it)" sb 's/^    dispatch_async\(dispatch_get_main_queue\(\), \^\{$/    ({/'
mtf "the end of every touch lays the bar out, with nothing that waited" sb 's/^    if \(!gAMHeld\) return;   \/\/ \(nothing waited\)$/    (void)0;/; s/^        if \(!gAMHeld\) return;$/        (void)0;/'
[ "$fails" = 0 ] && echo "test-appmenushold: all pass" || { echo "test-appmenushold: FAILED"; exit 1; }
