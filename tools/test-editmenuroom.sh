#!/bin/bash
# test-editmenuroom.sh: UIKit's edit menu in a turned SpringBoard (1.8.8.2). On iPadOS 16 in landscape the edit menu of a name renamed on the
# desktop and of a sticky note was drawn above the screen's top edge, under the menu bar: UIKit's insets method takes the keyboard's frame in the
# window scene's space, and SpringBoard's scene stays in the screen's fixed portrait space while its interface is turned (the bottom inset read 774
# in a 768 point container). statusbar/EditMenuRoom.h keeps UIKit's answer but where the two spaces differ, and there works UIKit's formula out
# again with the keyboard taken into the container (the rule: common/EditMenuRoom.h). The real header (EMR_H, EMR_RULE: another copy) on models of
# UIKit's two shapes of the method, transcribed from UIKit's code (test-editmenuroom.m), in a release and a DEBUG build, one scenario per process;
# then site checks of where it plugs in; then made-to-fail copies, each must fail. On a tree without the fix the models run alone: UIKit's 774.
# (1.8.8.2 B75 review: a container on another display keeps UIKit's answer, and so does an answer UIKit made another way than its formula.)
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H0=${EMR_H:-../statusbar/EditMenuRoom.h}; R0=${EMR_RULE:-../common/EditMenuRoom.h}
SB=../statusbar/StatusBar.x; CR=crashmap-rules.txt
fnz() { awk -v s="$2" '!f && index($0, s) == 1 { f = 1 } f { print } f && /^}/ { exit }' "$1"; }   # (to the first "}" at a line's start)
fn() { awk -v s="$2" '!f && index($0, s) == 1 { f = 1 } f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }' "$1"; }
SCEN="main skip badksd bad16 no18 mid17"

build() {   # $1 statusbar header, $2 rule, $3 dir, $4 quiet: the harness on that code, release and DEBUG
  local d=$3 dbg; mkdir -p "$d/sb" "$d/common"
  # (SpringBoard's helpers as written: two functions up to their closing brace at the line's start, and the one-line getter)
  { fnz ../statusbar/SMEngineAPI.h 'static NSString *DMSMNormEncoding(const char *e) {'; fnz ../statusbar/SMEngineAPI.h 'static NSString *DMSMExpect(const char *ret, ...) {'
    grep '^static NSString \*DMSMSigOfMethod(Method m) { return .*; }$' ../statusbar/SMEngineAPI.h; } > "$d/cut-sig.h"
  grep -q '^static NSString \*DMSMSigOfMethod' "$d/cut-sig.h" && grep -q '^static NSString \*DMSMExpect' "$d/cut-sig.h" || { echo "FAIL  the signature helpers were not found in SMEngineAPI.h"; return 99; }
  if [ -f "$1" ]; then
    # (UIKit's class names pointed at the stand-ins: the Mac's own UIKit is never hooked)
    sed -E 's/objc_getClass\("_UIEditMenuPresentation"\)/objc_getClass("TEMPresentation16")/; s/objc_getClass\("_UIEditMenuContentPresentation"\)/objc_getClass("TEMPresentation18")/;
            s/objc_getClass\("UIKeyboardSceneDelegate"\)/objc_getClass("TKeyboardSceneDelegate")/; s/objc_getClass\("UIWindow"\)/objc_getClass("TWindow")/' "$1" > "$d/sb/EditMenuRoom.h"
    cp "$2" "$d/common/EditMenuRoom.h"
    grep -q 'objc_getClass("TEMPresentation16")' "$d/sb/EditMenuRoom.h" && grep -q 'objc_getClass("TEMPresentation18")' "$d/sb/EditMenuRoom.h" \
      && grep -q 'objc_getClass("TKeyboardSceneDelegate")' "$d/sb/EditMenuRoom.h" && grep -q 'objc_getClass("TWindow")' "$d/sb/EditMenuRoom.h" \
      && grep -q '^__attribute__((noinline)) static void DMEditMenuRoomInit(void) {' "$d/sb/EditMenuRoom.h" || { echo "FAIL  the code was not found in $1"; return 99; }
  else
    # (a tree without the fix: the models alone, as UIKit runs there)
    echo "note: no $1 in this tree: UIKit's models alone (the fix's own checks then fail)"
    printf '%s\n' '@protocol DMEditMenuKeyboard' '- (BOOL)isOnScreen;' '- (CGRect)visibleInputViewFrameInView:(UIView *)view;' '@end' \
      'static UIEdgeInsets (*o_DMEditMenuInsets16)(id, SEL);' 'static UIEdgeInsets (*o_DMEditMenuInsets18)(id, SEL, id);' 'static void DMEditMenuRoomInit(void) { }' > "$d/sb/EditMenuRoom.h"
  fi
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -fno-optimize-sibling-calls -I"$d" -I"$d/sb" -DDEBUG=$dbg \
          -framework UIKit -framework CoreGraphics -o "$d/t-$dbg" test-editmenuroom.m 2> "$d/cc-$dbg.txt" || { [ -n "$4" ] || cat "$d/cc-$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -s "$d/cc-$dbg.txt" ] && [ -z "$4" ] && { echo "FAIL  warnings (DEBUG=$dbg):"; cat "$d/cc-$dbg.txt"; return 1; }
  done
  return 0
}
run() {   # $1 header, $2 rule, $3 dir, $4 quiet: the number of failed checks
  local n=0 out r dbg s
  build "$1" "$2" "$3" "$4"; r=$?; [ $r = 99 ] && return 99; n=$r
  for dbg in 0 1; do
    [ -n "$4" ] || echo "-- $([ $dbg = 1 ] && echo DEBUG || echo release)"
    for s in $SCEN; do
      out=$("$3/t-$dbg" $s 2>/dev/null); r=$?
      [ -n "$4" ] || echo "$out"
      [ $r -ge 128 ] && { [ -n "$4" ] || echo "FAIL  $s ended by signal $((r - 128))"; n=$((n + 1)); }
      n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ $r -lt 128 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
    done
  done
  return $n
}

echo "== the real code on models of UIKit's two shapes"
run "$H0" "$R0" "$W/real" ""; rc=$?

echo "== where it plugs in"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi; }
if [ -f "$H0" ]; then
  check "StatusBar.x includes EditMenuRoom.h once, after PointerRegion.h (SMEngineAPI.h's signature helpers and the crash guard's reader are above)" \
    "[ \$(grep -c '^#include \"EditMenuRoom.h\"' $SB) = 1 ] && awk '/^#include \"SMEngineAPI.h\"/{a=NR} /^#include \"PointerRegion.h\"/{b=NR} /^#include \"EditMenuRoom.h\"/{c=NR} END{exit !(a && b && c == b + 1)}' $SB"
  check "%ctor puts it in once, with the Mac status bar: after the Stock Status Bar return, before the preferences are read" \
    "[ \$(grep -c 'DMEditMenuRoomInit()' $SB) = 1 ] && awk '/^%ctor \{/{k=NR} k && /^    if \(gStockBar\) \{/{s=NR} k && /DMEditMenuRoomInit\(\);/{e=NR} k && /DMLoadPrefs\(\);/ && !p{p=NR} END{exit !(k && s && e > s && p > e)}' $SB \
     && grep -qF '    if (!DMCtorSkip(\"editmenu\")) DMEditMenuRoomInit();' $SB"
  check "the hook is MSHookMessageEx on the two shapes only, both from DMEditMenuRoomInit, each after its type encoding check" \
    "[ \$(grep -c 'MSHookMessageEx(' $H0) = 2 ] && fn $H0 '__attribute__((noinline)) static void DMEditMenuRoomInit(void) {' | grep -qF '        if (shape && first && !k) MSHookMessageEx(classes[i], s, (IMP)DMEditMenuInsets16, (IMP *)&o_DMEditMenuInsets16);' \
     && fn $H0 '__attribute__((noinline)) static void DMEditMenuRoomInit(void) {' | grep -qF '        if (shape && first && k) MSHookMessageEx(classes[i], s, (IMP)DMEditMenuInsets18, (IMP *)&o_DMEditMenuInsets18);' \
     && ! grep -q 'method_setImplementation\|class_replaceMethod\|%hook' $H0"
  check "UIKit's class and selector names as read in UIKit (16.7.7 and the iOS 18 code base)" \
    "grep -qF 'Class classes[2] = { objc_getClass(\"_UIEditMenuPresentation\"), objc_getClass(\"_UIEditMenuContentPresentation\") };' $H0 && grep -qF 'SEL s16 = sel_registerName(\"_preferredContentInsetsForContainerView\"), s18 = sel_registerName(\"_preferredContentInsetsForContainerViewWithConfiguration:\");' $H0 \
     && grep -qF 'Class ksd = objc_getClass(\"UIKeyboardSceneDelegate\"), win = objc_getClass(\"UIWindow\");' $H0"
  check "the crash guard: the piece editMenuRoom (no Settings row), its reader, the pass-throughs transparent before the file's rule" \
    "grep -qx 'target editMenuRoom piece the edit menu.s place|the edit menu.s place above the keyboard in landscape' $CR && grep -qF '#define MSBD_EDIT_MENU_PIECE \"editMenuRoom\"' $H0 \
     && grep -qF 'if (MSBDCrashSkipped(MSBD_EDIT_MENU_PIECE)) {' $H0 && ! grep -q 'editMenuRoom pref' $CR \
     && awk '/^sym MacStatusBarCore \^_\*DMEditMenuInsets\(16\|18\)\\$ transparent$/{a=NR} /^file MacStatusBarCore \^EditMenuRoom\\\\\.h\\$ editMenuRoom$/{b=NR} END{exit !(a && b && a < b)}' $CR"
  check "the decision and the start-up check are functions of their own (the piece's in the crash map), the pass-throughs plain" \
    "grep -q '^__attribute__((noinline)) static UIEdgeInsets DMEditMenuRoom(id presentation, UIEdgeInsets uikit, id configuration) {' $H0 && grep -q '^__attribute__((noinline)) static void DMEditMenuRoomInit(void) {' $H0 \
     && grep -q '^static UIEdgeInsets DMEditMenuInsets16(id self, SEL _cmd) {' $H0 && grep -q '^static UIEdgeInsets DMEditMenuInsets18(id self, SEL _cmd, id configuration) {' $H0"
  ifdebug() { awk -v s="$2" '/^#if DEBUG/ { st[++n] = 1; next } /^#if/ { st[++n] = 0; next } /^#else/ { if (st[n] == 1) st[n] = 2; next } /^#endif/ { n--; next }
    index($0, s) { ok = 0; for (i = 1; i <= n; i++) if (st[i] == 1) ok = 1; print ok ? "yes" : "no"; exit }' "$1"; }
  check "the debug switch /tmp/msb-editmenu-uikit and the lines are DEBUG only; the release markers are not" \
    "[ \"\$(ifdebug $H0 'if (DMTestFlag(\"/tmp/msb-editmenu-uikit\")) why = MSBDEditMenuKept;')\" = yes ] && [ \"\$(ifdebug $H0 'static void DMEditMenuNote(UIView *c,')\" = yes ] \
     && [ \"\$(ifdebug $H0 'DM_FEATURE_MARK(\"edit-menu-room\");')\" = no ] && [ \"\$(ifdebug $H0 'DM_FEATURE_MARK(\"edit-menu-room-hook\");')\" = no ]"
  check "the lines carry geometry and class names only (no text of a field or a note)" \
    "! grep -nE 'NSLog|printf|os_log|\\.text\\b|attributedText|selectedText' $H0 $R0"
else
  check "statusbar/EditMenuRoom.h is in this tree" "false"
fi
[ $fails -gt 0 ] && rc=$((rc + fails))
[ $rc = 0 ] && echo "test-editmenuroom: all pass" || echo "test-editmenuroom: FAILED ($rc check(s))"

if [ -z "$EMR_H$EMR_RULE" ] && [ -f "$H0" ]; then
  echo "== made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 h or r (which file), $3 perl expression on the whole file
    local d="$W/m$((++k))" h=$H0 r=$R0 c
    mkdir -p "$d"
    if [ "$2" = h ]; then c="$d/EditMenuRoom.h"; perl -0777 -pe "$3" "$H0" > "$c"; h=$c; cmp -s "$c" "$H0"; else c="$d/rule.h"; perl -0777 -pe "$3" "$R0" > "$c"; r=$c; cmp -s "$c" "$R0"; fi \
      && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$h" "$r" "$d/w" q; local n=$?
    [ $n = 99 ] && { echo "FAIL  made-to-fail copy \"$1\": did not build"; rc=1; return; }
    if [ $n -gt 0 ]; then echo "PASS  caught: $1 ($n failed checks)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  mtf "UIKit's step only (the keyboard never taken into the container)" h 's/MSBDEditMenuKeyboardUsable\(kbIn = \[space convertRect:kb toCoordinateSpace:c\]\)/MSBDEditMenuKeyboardUsable(kbIn = kb)/'
  mtf "the spaces always taken to agree" h 's/else if \(MSBDEditMenuSpacesAgree\(probe, \[space convertRect:probe toCoordinateSpace:c\]\)\)/else if (1)/'
  mtf "the spaces compared by size only (a half turn passes)" r 's/return fabs\(back\.origin\.x - probe\.origin\.x\) <= 0\.5 && fabs\(back\.origin\.y - probe\.origin\.y\) <= 0\.5\n        && /return /'
  mtf "no 6 points" r 's/double want = overlap \+ 6\.0;/double want = overlap;/'
  mtf "the safe area's bottom not kept" r 's/return safeBottom < want \? want : safeBottom;/return want;/'
  mtf "the remote keyboard window not kept to UIKit's" h 's/\n        else if \(DMEditMenuAsk\(w, "_isRemoteKeyboardWindow"\)\) why = MSBDEditMenuRemoteKeyboard;//'
  mtf "the configuration that ignores the keyboard not kept to UIKit's" h 's/\n        else if \(configuration && DMEditMenuAsk\(configuration, "_ignoresKeyboardAvoidance"\)\) why = MSBDEditMenuIgnoresKeyboard;//'
  mtf "the keyboard's state not asked" h 's/ \|\| !\[ksd isOnScreen\]\) why = MSBDEditMenuKeyboardOff;/) why = MSBDEditMenuKeyboardOff;/'
  mtf "UIKit's other branch (not a text effects window) redone" h 's/\n        else if \(!DMEditMenuAsk\(w, "_isTextEffectsWindow"\)\) why = MSBDEditMenuOtherBranch;//'
  mtf "UIKit's CGRectZero (an undocked keyboard) taken as a frame" r 's/return !\(kb\.origin\.x == 0\.0 && kb\.origin\.y == 0\.0 && kb\.size\.width == 0\.0 && kb\.size\.height == 0\.0\);/return 1;/'
  mtf "the pass-through does not call UIKit's method" h 's/UIEdgeInsets uikit = o_DMEditMenuInsets16\(self, _cmd\);/UIEdgeInsets uikit = UIEdgeInsetsZero;/'
  mtf "the crash guard's piece not read" h 's/if \(MSBDCrashSkipped\(MSBD_EDIT_MENU_PIECE\)\) \{/if (0) {/'
  mtf "UIKit's calls not checked by type encoding" h 's/if \(!m \|\| !\[DMSMSigOfMethod\(m\) isEqualToString:calls\[i\]\.want\]\) \{/if (!m) {/'
  mtf "a method hooked whatever its shape" h 's/BOOL shape = \[DMSMSigOfMethod\(m\) isEqualToString:k \? want18 : want16\], first/BOOL shape = YES, first/'
  mtf "an inherited method hooked again on the subclass" h 's/return m && \(!up \|\| class_getInstanceMethod\(up, s\) != m\) \? m : NULL;/return m;/'
  mtf "only 16's class looked at for 16's shape (a 17 in between missed)" h 's/for \(int i = 0; i < 2; i\+\+\) for \(int k = 0; k < 2; k\+\+\) \{/for (int i = 0; i < 2; i++) for (int k = 0; k < 2; k++) { if (i != k) continue;/'
  mtf "the debug switch not read (DEBUG)" h 's/if \(DMTestFlag\("\/tmp\/msb-editmenu-uikit"\)\) why = MSBDEditMenuKept;/if (0) why = MSBDEditMenuKept;/'
  # (the review's two guards, 1.8.8.2 B75 review)
  mtf "a container on another display (the TV) redone" h 's/\n        else if \(w\.screen != \[UIScreen mainScreen\]\) why = MSBDEditMenuOtherDisplay;[^\n]*//'
  mtf "an answer UIKit made another way redone (its formula not compared)" h 's/else if \(!MSBDEditMenuIsUIKits\((uikit\.bottom, safe = c\.safeAreaInsets\.bottom, maxY = CGRectGetMaxY\(c\.bounds\), CGRectGetMinY\(kb\))\)\) why = MSBDEditMenuNotUIKits;/else if (!(MSBDEditMenuIsUIKits($1) || 1)) why = MSBDEditMenuNotUIKits;/'
  mtf "UIKit's formula compared loosely (another tweak's 10 points taken as UIKit's)" r 's/return fabs\(uikitBottom - MSBDEditMenuBottom\(safeBottom, containerMaxY, keyboardMinY\)\) <= 0\.01;/return fabs(uikitBottom - MSBDEditMenuBottom(safeBottom, containerMaxY, keyboardMinY)) <= 20.0;/'
fi
exit $rc
