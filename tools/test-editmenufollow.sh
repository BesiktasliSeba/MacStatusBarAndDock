#!/bin/bash
# test-editmenufollow.sh: UIKit's edit menu follows what is typed in the desktop's typing window through a turn (1.8.8.2, seen on iPadOS 17.5.1 in a
# device pass: a desktop rename's Cut | Copy | AutoFill stayed where the field had been before the turn to landscape, pointing at nothing, while the
# field followed). In an app UIKit hides and shows its edit menu around its window's rotation; SpringBoard's scene never turns, the typing window's
# container does (statusbar/Desktop.h DMDesktopRenameFit), so UIKit was never told. (1) DMDesktopEditMenuFollow cut out of Desktop.h and run on
# views with edit menu interactions of the test's own (test-editmenufollow.m, Mac Catalyst); (2) site checks: the container's turn asks it on the
# next main-queue turn and again 0.4 s later, for the first responder in the typing window; (3) made-to-fail copies, each must fail.
# EMF_D=<file>: another Desktop.h (the code before the fix: then it must fail).
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
D0=${EMF_D:-../statusbar/Desktop.h}
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$2" '!f && index($0, s) == 1 { f = 1 } f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0 && o + c > 0) exit }' "$1"; }
run() {   # $1 Desktop.h, $2 dir, $3 quiet: the function cut out and the harness built on it and run
  local d=$2; mkdir -p "$d"
  fn "$1" '__attribute__((noinline)) static int DMDesktopEditMenuFollow(UIView *typing) {' > "$d/cut.h"
  [ -s "$d/cut.h" ] || { [ -n "$3" ] || echo "FAIL  DMDesktopEditMenuFollow not found in $1 (the edit menu is never told of a turn)"; return 1; }
  clang -target "$(uname -m)-apple-ios16.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" -fobjc-arc -Wall -Wno-unused-function -Wno-deprecated-declarations \
        -Werror=implicit-function-declaration -framework UIKit -framework CoreGraphics -framework QuartzCore -DCUT_H="\"$d/cut.h\"" -o "$d/t" test-editmenufollow.m 2> "$d/cc.txt" || { [ -n "$3" ] || { head -5 "$d/cc.txt"; echo "FAIL  the harness did not build"; }; return 1; }
  [ -s "$d/cc.txt" ] && { [ -n "$3" ] || { echo "FAIL  warnings:"; cat "$d/cc.txt"; }; return 1; }
  if [ -n "$3" ]; then "$d/t" > /dev/null 2>&1; else "$d/t"; fi
}
echo "== 1. the follow (Mac Catalyst)"
run "$D0" "$W/real" || fails=1
echo "== 2. site checks"
sites() {   # $1 Desktop.h: the number of failed checks (quiet with $2)
  local D=$1 q=$2 bad=0
  sc() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; bad=$((bad+1)); fi; }
  local FIT; FIT=$(fn "$D" 'static void DMDesktopRenameFit(void) {')
  sc "the container turned (DMDesktopRenameFit's change): the edit menu asked to follow on the next main-queue turn and again 0.4 s later, inside the change only" \
     "printf '%s\n' \"\$FIT\" | awk '/r.transform = t;/{a=NR} /dispatch_async\\(dispatch_get_main_queue\\(\\), \\^\\{ DMDesktopRenameMenuFollow\\(\\); \\}\\);/{b=NR} /\\(int64_t\\)\\(0\\.4 \\* NSEC_PER_SEC\\)\\), dispatch_get_main_queue\\(\\), \\^\\{ DMDesktopRenameMenuFollow\\(\\); \\}\\);/{c=NR} /\\[gDesktop dm_fitRenameField\\];/{e=NR} END{exit !(a && b > a && c > b && e > c)}' \
      && [ \$(grep -c 'DMDesktopRenameMenuFollow();' '$D') = 2 ]"
  sc "  ... for what is typed in the typing window (its first responder, bounded), only while the window shows" \
     "fn '$D' 'static UIView *DMDesktopRenameTyping(void) {' | grep -qF 'if (!w || w.hidden) return nil;' && fn '$D' 'static UIView *DMDesktopRenameTyping(void) {' | grep -qF 'for (NSUInteger k = 0; k < todo.count && k < 400; k++) { UIView *v = todo[k]; if (v.isFirstResponder) return v; [todo addObjectsFromArray:v.subviews]; }' \
      && fn '$D' 'static void DMDesktopRenameMenuFollow(void) {' | grep -qF 'int asked = DMDesktopEditMenuFollow(DMDesktopRenameTyping());'"
  sc "  ... UIKit's call by name and shape only (\"v@:B\", a BOOL; \"v@:c\" on an Intel Mac), no hook; iPadOS 15's UIMenuController only where there is no edit menu interaction class" \
     "fn '$D' '__attribute__((noinline)) static int DMDesktopEditMenuFollow(UIView *typing) {' > '$W/f.txt' && grep -qF 'if (![shape isEqualToString:@\"v@:B\"] && ![shape isEqualToString:@\"v@:c\"]) return 0;' '$W/f.txt' && grep -qF 'Class emi = objc_getClass(\"UIEditMenuInteraction\");' '$W/f.txt' \
      && awk '/return asked;/{a=NR} /UIMenuController \\*mc = \\[UIMenuController sharedMenuController\\];/{b=NR} END{exit !(a && b > a)}' '$W/f.txt' && grep -qF 'if ((!shown && !hidByTurn) || ![typing conformsToProtocol:@protocol(UITextInput)]) return 0;' '$W/f.txt' && ! grep -q 'MSHook\\|%hook' '$W/f.txt'"
  sc "iPadOS 15 (1.8.8.3): the typing window told of a turn notes when; UIMenuController's menu beginning to hide while it types is noted (the window made, 15 only, once)" \
     "fn '$D' 'static void DMDesktopRenameTurned(UIWindow *self, SEL _cmd, long long to, double duration, long long from) {' | grep -qF 'gDesktopTurnToldAt = CACurrentMediaTime();' \
      && fn '$D' 'static void DMDesktopEditMenuWatch(void) {' | grep -qF 'addObserverForName:UIMenuControllerWillHideMenuNotification' && fn '$D' 'static void DMDesktopEditMenuWatch(void) {' | grep -qF 'if (DMDesktopRenameTyping()) gDesktopEditMenuHidAt = CACurrentMediaTime();' \
      && fn '$D' 'static void DMDesktopEditMenuWatch(void) {' | grep -qF 'if (objc_getClass(\"UIEditMenuInteraction\")) return;' && grep -qF '            DMDesktopEditMenuWatch();   // (iPadOS 15' '$D'"
  return $bad
}
sites "$D0" || fails=1
echo "== 3. made-to-fail copies (each must fail)"
mi=0
mtf() {   # $1 what, $2 perl substitution on Desktop.h: the harness or the site checks on that copy must fail
  local d="$W/m$((++mi))"; mkdir -p "$d"; cp "$D0" "$d/Desktop.h"; perl -0pi -e "$2" "$d/Desktop.h"
  if cmp -s "$d/Desktop.h" "$D0"; then echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; fi
  if run "$d/Desktop.h" "$d/b" q && sites "$d/Desktop.h" q; then echo "FAIL  made-to-fail ($1): not caught"; fails=1; else echo "PASS  made-to-fail ($1): caught"; fi
}
mtf "the edit menu never told of the turn" 's/        dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMDesktopRenameMenuFollow\(\); \}\);\n//; s/        dispatch_after\(dispatch_time\(DISPATCH_TIME_NOW, \(int64_t\)\(0\.4 \* NSEC_PER_SEC\)\), dispatch_get_main_queue\(\), \^\{ DMDesktopRenameMenuFollow\(\); \}\);\n//'
mtf "only the field's own interaction (not UIKit's views inside it)" 's/            if \(v == typing \|\| \[v isDescendantOfView:typing\]\) \[views addObjectsFromArray:v.subviews\];\n//'
mtf "the menu moved with an animation" 's/\(\(void \(\*\)\(id, SEL, BOOL\)\)objc_msgSend\)\(i, up, NO\)/((void (*)(id, SEL, BOOL))objc_msgSend)(i, up, YES)/'
mtf "every view's interactions asked, also another field's" 's/            if \(v == typing \|\| \[v isDescendantOfView:typing\]\) \[views addObjectsFromArray:v.subviews\];/            [views addObjectsFromArray:v.subviews];/'
mtf "not bounded" 's/k < views\.count && k < 96; k\+\+/k < views.count; k++/'
mtf "iPadOS 15: a menu UIKit hid as the screen turned never shown again (1.8.8.3)" 's/BOOL shown = mc\.isMenuVisible, hidByTurn = [^;]*;/BOOL shown = mc.isMenuVisible, hidByTurn = NO;/'
mtf "iPadOS 15: any menu that hid shown again, not only one the turn hid" 's/ && gDesktopEditMenuHidAt >= gDesktopTurnToldAt - 1\.0;/;/'
mtf "iPadOS 15: a turn's hide undone more than once" 's/    gDesktopEditMenuHidAt = 0;   \/\/ \(a hide is undone once[^\n]*\n//'
mtf "iPadOS 15: a menu the user closed after the turn's follow showed it shown again 0.4 s on (once per turn, review 1.8.8.3)" 's/    if \(thisTurn\) gDesktopEditMenuTurnDone = gDesktopTurnToldAt;[^\n]*\n//'
[ $fails = 0 ] && echo "test-editmenufollow: all pass" || { echo "test-editmenufollow: FAILED"; exit 1; }
