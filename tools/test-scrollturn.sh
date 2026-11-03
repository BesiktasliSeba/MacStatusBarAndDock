#!/bin/bash
# Mac test of a trackpad's scroll in our turned containers (1.7.9; KT on the A12Z: the Today panel scrolled sideways with the Magic Keyboard's
# trackpad): the rule (common/ScrollTurn.h, test-scrollturn.c, with UIKit's two turns modelled on its own code) and its wiring in SpringBoard --
# both containers note their turn where they are turned, UIKit's turn of the delta is told that orientation for our two windows only, and only
# while it runs.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -Werror -o "$W/tst" test-scrollturn.c && "$W/tst" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
X=../statusbar/StatusBar.x; N=../statusbar/NativeWindow.h; H=../common/ScrollTurn.h
check "the menus' container: its turn noted where it is turned, 0 when the window is used unturned" \
  "fn $X 'static UIView *DMMenuHost(' | grep -q 'gMenuRotator.transform = CGAffineTransformMakeRotation(angle);' \
   && fn $X 'static UIView *DMMenuHost(' | grep -q 'atomic_store(&gDMMenuScrollTurn, MSBDScrollTurnOrientation(angle));' \
   && fn $X 'static UIView *DMMenuHost(' | grep -q 'atomic_store(&gDMMenuScrollTurn, 0);'"
check "the native windows' container: its turn noted on every measure, before the unchanged-turn return" \
  "fn $N 'static void DMNativeUpdateRotation(' | awk '/atomic_store\(&gDMNativeScrollTurn, MSBDScrollTurnOrientation\(angle\)\);/ {a=NR} /CGAffineTransformEqualToTransform/ {b=NR} END {exit !(a && b && a < b)}'"
check "both window classes answer the turn (MSBMenuWindow, MSBNativeLayer), added before the class is registered" \
  "fn $X 'static void DMCreateMenuWindow(' | awk '/DMScrollTurnWindowClass\(sub\);/ {a=NR} /objc_registerClassPair\(sub\);/ {b=NR} END {exit !(a && b && a < b)}' \
   && grep -A2 'class_addMethod(sub, NSSelectorFromString(@\"_canBecomeKeyWindow\"), (IMP)DMNativeYes, \"B@:\");' $N | grep -q 'DMScrollTurnWindowClass(sub);'"
check "  ... only with getters of the expected shape (q@:), from one base class, the base's own answer otherwise" \
  "fn $X 'static void DMScrollTurnWindowClass(' | grep -q 'isEqualToString:@\"q@:\"\]' && fn $X 'static void DMScrollTurnWindowClass(' | grep -q 'gDMScrollTurnOwnOverridden != io' \
   && fn $X 'static long DMScrollTurnOverridden(' | grep -q 'if (gDMScrollTurnTo && self == gDMScrollTurnFor) return gDMScrollTurnTo;' \
   && fn $X 'static long DMScrollTurnOverridden(' | grep -q 'return ((long (\*)(id, SEL))gDMScrollTurnOwnOverridden)(self, _cmd);'"
check "UIKit's turn of the delta: told the orientation for our two windows only, only during the call, put back after" \
  "fn $X 'static CGVector DMScrollDeltaToFixed(' | grep -q 'if (w && w == gMenuWindow) to = atomic_load(&gDMMenuScrollTurn);' \
   && fn $X 'static CGVector DMScrollDeltaToFixed(' | grep -q 'else if (w && w == gNativeLayer) to = atomic_load(&gDMNativeScrollTurn);' \
   && fn $X 'static CGVector DMScrollDeltaToFixed(' | grep -q 'if (!to || !gDMScrollTurnOwnOverridden) return o_DMScrollDeltaToFixed(self, _cmd, d);' \
   && fn $X 'static CGVector DMScrollDeltaToFixed(' | grep -q 'gDMScrollTurnFor = wasFor; gDMScrollTurnTo = wasTo;'"
check "the hook: shape-checked ({CGVector=dd}@:{CGVector=dd}, the window getter @@:), from 17 (15 turns its windows, 16 asks the window scene), installed at start" \
  "fn $X 'static void DMScrollTurnInit(' | grep -q 'isEqualToString:@\"{CGVector=dd}@:{CGVector=dd}\"\]' && fn $X 'static void DMScrollTurnInit(' | grep -q 'majorVersion < 17) return;' \
   && grep -q 'if (!DMCtorSkip(\"scrollturn\")) DMScrollTurnInit();' $X"
check "the thread's state is thread-local and never retains a window" \
  "grep -q '^static __thread __unsafe_unretained id gDMScrollTurnFor = nil;' $X && grep -q '^static __thread int gDMScrollTurnTo = 0;' $X"
check "the rule header is plain C (the Mac test runs this very code)" "! grep -q -E '#import|@interface|NSString' $H"
check "no em dash in the change's files" "! grep -q \$'\\xe2\\x80\\x94' $H test-scrollturn.c test-scrollturn.sh"
[ $fails = 0 ] && echo "test-scrollturn: all checks pass" || { echo "test-scrollturn: checks FAILED"; exit 1; }
