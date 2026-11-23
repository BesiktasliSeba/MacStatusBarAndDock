#!/bin/bash
# test-docklevelowner.sh: one owner for the Dock window's level while our on-screen keyboard is up (1.8.8.2). After Rename from the Downloads
# stack's item menu the Dock stayed over the on-screen keyboard, its bottom row covered (iPadOS 16.7.7: level 25 over the keyboard's 8): the
# panel's close put its saved level back after the keyboard rule's -3 (dock/Downloads.m -restoreHostWindowIfIdle). And the panel's own search
# field dropped the panel under the windows while it typed: the rule took the Dock under for a keyboard that was the Dock's own.
#  (1) the real code (test-docklevelowner.m, Mac Catalyst, headless): Desktop.h's DMDesktopDockUnder, MSBDDockLevelAfterKeyboard and
#      DMKeyboardForTheDock and the panel's restore lines out of Downloads.m, on stand-ins of SpringBoard's windows;
#  (2) the wiring: the rule's question asked with the Dock's own keyboard left out, the hand-over found by name, nothing else setting the
#      saved level, the names the crash guard maps;
#  then made-to-fail copies, each must fail.
# DL_ROOT: another tree (e.g. the code before it): run on it, no made-to-fail copies.
cd "$(dirname "$0")" || exit 1
R0=$(cd "${DL_ROOT:-..}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
fails=0
fndef() {   # $1 file, $2 name: a function's definition (static, or exported with default visibility), whole, by its braces
  awk -v n="$2" '
    !f && $0 ~ ("^(__attribute__\\(\\((noinline|visibility\\(\"default\"\\))\\)\\) )?(static )?(inline )?[^(=]*[ *]" n "\\(") && index($0, "{") { f = 1 }
    f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }
  ' "$1"
}
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
nocomments() { sed -E 's://.*$::' "$1"; }

harness() {   # $1 Desktop.h, $2 Downloads.m, $3 dir, $4 quiet: rc
  local D=$1 L=$2 d=$3 q=$4
  mkdir -p "$d"
  [ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; return 1; }
  { grep -E '^static NSMutableSet<NSString \*> \*gDockUnderReasons;$|^static __weak UIWindow \*gDockLowered; static CGFloat gDockLevelWas, gDockLevelLow;$' "$D"
    fndef "$D" DMDesktopDockIsUnder; fndef "$D" DMDesktopDockUnder; fndef "$D" MSBDDockLevelAfterKeyboard; fndef "$D" DMKeyboardForTheDock; } > "$d/dl-desk.inc"
  fn "$L" '- (void)restoreHostWindowIfIdle {' | awk 'index($0, "    static BOOL (*afterKeyboard)") == 1 { f = 1 } f { print } f && index($0, "self.hostWindow.windowLevel = self.savedLevel;") { exit }' > "$d/dl-restore.inc"
  for f in gDockUnderReasons DMDesktopDockUnder MSBDDockLevelAfterKeyboard DMKeyboardForTheDock; do
    grep -q "$f" "$d/dl-desk.inc" || { [ -n "$q" ] || echo "FAIL  $f was not found in Desktop.h"; return 99; }
  done
  grep -q 'afterKeyboard' "$d/dl-restore.inc" || { [ -n "$q" ] || echo "FAIL  the panel's restore asks nothing of the keyboard rule (Downloads.m)"; return 99; }
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" -framework UIKit -o "$d/t" test-docklevelowner.m 2> "$d/cc.txt" \
    || { [ -n "$q" ] || { head -30 "$d/cc.txt"; echo "FAIL  the real code did not build"; }; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  if [ -n "$q" ]; then "$d/t" > /dev/null 2>&1; else "$d/t"; fi
}

pins() {   # $1 Desktop.h, $2 Downloads.m, $3 crashmap-rules.txt, $4 quiet: the number that fail
  local D=$1 L=$2 R=$3 q=$4 n=0
  ok() { [ -n "$q" ] || echo "PASS  $1"; }
  no() { [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); }
  ck() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
  ck "Desktop.h: the keyboard rule takes the Dock under only for a keyboard that is not the Dock's own (the frame of ours kept either way)" \
     "fn $D 'static void DMKeyboardDockDecide(' | grep -qF '    BOOL forDock = own && DMKeyboardForTheDock();' && fn $D 'static void DMKeyboardDockDecide(' | grep -qF 'BOOL under = MSBDKeyboardDockUnder(own && !forDock, ' \
      && fn $D 'static void DMKeyboardDockDecide(' | grep -qF 'CGRect frame = !own ? CGRectZero :'"
  ck "  ... the hand-over exported for the Dock part, on the window held only" \
     "grep -qF '__attribute__((visibility(\"default\"))) BOOL MSBDDockLevelAfterKeyboard(UIWindow *w, CGFloat level) {' $D && fn $D '__attribute__((visibility(\"default\"))) BOOL MSBDDockLevelAfterKeyboard(' | grep -qF 'w != gDockLowered'"
  ck "Downloads.m: the panel's restore asks the keyboard rule by name first, then sets its saved level only if the rule does not hold the window" \
     "fn $L '- (void)restoreHostWindowIfIdle {' | grep -qF 'afterKeyboard = (BOOL (*)(UIWindow *, CGFloat))dlsym(RTLD_DEFAULT, \"MSBDDockLevelAfterKeyboard\");' \
      && fn $L '- (void)restoreHostWindowIfIdle {' | grep -qF '    if (!(afterKeyboard && afterKeyboard(self.hostWindow, self.savedLevel))) self.hostWindow.windowLevel = self.savedLevel;' \
      && [ \$(nocomments $L | grep -c 'windowLevel = self.savedLevel') = 1 ]"
  ck "the crash guard: the new names map to the desktop's piece, as the rule they belong to" \
     "python3 -I - $R <<'PY'
import re, sys
rules = [l.split() for l in open(sys.argv[1]) if l.strip() and not l.startswith('#')]
sym = [(re.compile(f[2]), f[3]) for f in rules if len(f) >= 4 and f[0] == 'sym' and f[1] == 'MacStatusBarCore']
fil = [(re.compile(f[2]), f[3]) for f in rules if len(f) >= 4 and f[0] == 'file' and f[1] == 'MacStatusBarCore']
first = lambda rs, s: next((t for rx, t in rs if rx.search(s)), None)
want = first(sym, '_DMDesktopDockUnder') or first(fil, 'Desktop.h')
got = [first(sym, n) or first(fil, 'Desktop.h') for n in ('_MSBDDockLevelAfterKeyboard', '_DMKeyboardForTheDock')]
sys.exit(0 if want and all(g == want for g in got) else 1)
PY"
  ck "no em or en dash in Desktop.h, the panel's restore or this test" "! grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $D test-docklevelowner.sh test-docklevelowner.m && ! fn $L '- (void)restoreHostWindowIfIdle {' | grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93'"
  return $n
}

D0=$R0/statusbar/Desktop.h; L0=$R0/dock/Downloads.m; RR0=$R0/tools/crashmap-rules.txt
echo "== (1) the real code (Mac Catalyst)"
harness "$D0" "$L0" "$W/h" "" || fails=1
echo "== (2) the wiring"
pins "$D0" "$L0" "$RR0" "" || fails=1
if [ -z "$DL_ROOT" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mk() {   # $1 what, $2 D or L, $3 perl substitution
    local src; case $2 in D) src=$D0;; L) src=$L0;; esac
    local d="$W/m"; rm -rf "$d"; mkdir -p "$d"; cp "$src" "$d/f"
    perl -0pi -e "$3" "$d/f"
    cmp -s "$d/f" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    local dd=$D0 ll=$L0 n=0
    case $2 in D) dd=$d/f;; L) ll=$d/f;; esac
    harness "$dd" "$ll" "$d/h" q || n=$((n + 1))
    pins "$dd" "$ll" "$RR0" q; n=$((n + $?))
    if [ $n -gt 0 ]; then echo "PASS  caught: $1 ($n)"; else echo "FAIL  not caught: $1"; fails=1; fi
  }
  mk "the panel sets its level at once (1.8.8.1.1)" L 's/    if \(!\(afterKeyboard && afterKeyboard\(self\.hostWindow, self\.savedLevel\)\)\) self\.hostWindow\.windowLevel = self\.savedLevel;/    self.hostWindow.windowLevel = self.savedLevel;/'
  mk "the hand-over never takes it" D 's/(BOOL MSBDDockLevelAfterKeyboard\(UIWindow \*w, CGFloat level\) \{\n)/$1    return NO;\n/'
  mk "the hand-over takes any Dock window" D 's/if \(!w \|\| w != gDockLowered \|\| /if (!w || /'
  mk "the Dock's own keyboard taken under (1.8.8.1.1)" D 's/BOOL under = MSBDKeyboardDockUnder\(own && !forDock, /BOOL under = MSBDKeyboardDockUnder(own, /'
  mk "any key window taken for the Dock's" D 's/if \(w\.isKeyWindow && !w\.hidden && \[NSStringFromClass\(\[w class\]\) isEqualToString:\@"SBFloatingDockWindow"\]\) return YES;/if (w.isKeyWindow) return YES;/'
  mk "the keyboard frame of ours dropped for the Dock's search" D 's/CGRect frame = !own \? CGRectZero :/CGRect frame = !own || forDock ? CGRectZero :/'
fi
[ $fails = 0 ] && echo "test-docklevelowner: all pass" || { echo "test-docklevelowner: FAILED"; exit 1; }
