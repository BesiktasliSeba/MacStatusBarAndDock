#!/bin/bash
# test-typingturn.sh: a turn while a desktop name or a sticky note is typed (1.8.8.2). The desktop's typing window (Desktop.h DMDesktopRenameHost,
# a SpringBoard orientation window of our own) fitted its turned container only in its own layout pass, which a turn did not always bring (the
# window keeps its bounds through a turn: iPadOS 16.7.7 {768, 1024} both ways): the field and the note followed to their place, but their text
# was drawn sideways (17.5.1 on its turn to landscape, 16.7.7 to portrait). SpringBoard tells each shown orientation window of every turn
# (-activeInterfaceOrientationDidChangeToOrientation:willAnimateWithDuration:fromOrientation:, read in the 17.6.1 and 18.2 decompiles): the
# typing window answers it, SpringBoard's own handling first, then the fit at once, in its next layout pass and on the next main-queue turn.
#  (1) the real code (test-typingturn.m, Mac Catalyst, headless, release and DEBUG): the call of the shape read, of another shape, missing;
#  (2) the wiring: the method added only for the shape read, before the class is registered; SpringBoard's handling first; the debug Dock note
#      debug only; the crash guard's names;
#  then made-to-fail copies, each must fail.
# TT_ROOT: another tree (e.g. the code before it): run on it, no made-to-fail copies.
cd "$(dirname "$0")" || exit 1
R0=$(cd "${TT_ROOT:-..}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
fails=0
fndef() {   # $1 file, $2 name: a static function's definition (not a declaration), whole, by its braces
  awk -v n="$2" '
    !f && $0 ~ ("^(__attribute__\\(\\(noinline\\)\\) )?static (inline )?[^(=]*[ *]" n "\\(") && index($0, "{") { f = 1 }
    f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }
  ' "$1"
}
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
ifdebug() {   # $1 file, $2 text: is every line holding it inside an "#if DEBUG" (not its #else)?
  awk -v s="$2" '
    /^#if DEBUG/ { st[++n] = 1; next } /^#if/ { st[++n] = 0; next } /^#else/ { if (st[n] == 1) st[n] = 2; next } /^#endif/ { n--; next }
    index($0, s) { seen = 1; ok = 0; for (i = 1; i <= n; i++) if (st[i] == 1) ok = 1; if (!ok) bad = 1 }
    END { print (seen && !bad) ? "yes" : "no" }
  ' "$1"
}

harness() {   # $1 Desktop.h, $2 dir, $3 quiet: rc
  local D=$1 d=$2 q=$3 r=0 fl
  mkdir -p "$d"
  [ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; return 1; }
  { grep -E '^static UIWindow \*gDesktopRenameWindow;$|^static UIView \*gDesktopRenameRotator;' "$D"
    fndef "$D" DMDesktopRenameHitTest; fndef "$D" DMDesktopRenameYes; fndef "$D" DMDesktopRenameLayout; fndef "$D" DMDesktopTurnArgs
    echo '#if DEBUG'; fndef "$D" DMDesktopTurnDockNote; echo '#endif'
    fndef "$D" DMDesktopRenameTurned; fndef "$D" DMDesktopRenameHost; } > "$d/tt-desk.inc"
  for f in gDesktopRenameWindow DMDesktopRenameLayout DMDesktopTurnArgs DMDesktopRenameTurned DMDesktopRenameHost; do
    grep -q "$f" "$d/tt-desk.inc" || { [ -n "$q" ] || echo "FAIL  $f was not found in Desktop.h"; return 99; }
  done
  for fl in 0-0 0-1 1-0 2-0; do
    local shape=${fl%-*} dbg=${fl#*-}
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" -DT_SHAPE=$shape -DDEBUG=$dbg -framework UIKit -o "$d/t$fl" test-typingturn.m 2> "$d/cc-$fl.txt" \
      || { [ -n "$q" ] || { head -30 "$d/cc-$fl.txt"; echo "FAIL  the real code did not build ($fl)"; }; return 99; }
    [ -s "$d/cc-$fl.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings ($fl):"; cat "$d/cc-$fl.txt"; r=1; }
    if [ -n "$q" ]; then "$d/t$fl" > /dev/null 2>&1 || r=1; else echo "-- shape $shape, DEBUG $dbg"; "$d/t$fl" || r=1; fi
  done
  return $r
}

pins() {   # $1 Desktop.h, $2 crashmap-rules.txt, $3 quiet: the number that fail
  local D=$1 R=$2 q=$3 n=0
  ok() { [ -n "$q" ] || echo "PASS  $1"; }
  no() { [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); }
  ck() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
  ck "Desktop.h: the turn method added to the typing window's class only for the shape read (v@:qdq), with SpringBoard's own type encoding, before the class is registered" \
     "fn $D 'static UIView *DMDesktopRenameHost(' | awk 'index(\$0, \"                if ([turnArgs isEqualToString:@\\\"v@:qdq\\\"]) class_addMethod(sub, turnSel, (IMP)DMDesktopRenameTurned, method_getTypeEncoding(turn));\") == 1 { a = NR } index(\$0, \"                objc_registerClassPair(sub);\") == 1 { b = NR } END { exit !(a && b == a + 2) }'"
  ck "  ... SpringBoard's own handling first, then only for the shown typing window" \
     "fn $D 'static void DMDesktopRenameTurned(' | sed -n '2,4p' | tr -d '\\n' | grep -qF '    struct objc_super sup = { self, [self superclass] };    ((void (*)(struct objc_super *, SEL, long long, double, long long))objc_msgSendSuper)(&sup, _cmd, to, duration, from);    if (self != gDesktopRenameWindow || self.hidden) return;'"
  ck "  ... the fit at once, in the next layout pass and on the next main-queue turn" \
     "[ \$(fn $D 'static void DMDesktopRenameTurned(' | grep -c 'DMDesktopRenameFit();') = 2 ] && fn $D 'static void DMDesktopRenameTurned(' | grep -qF '    [self setNeedsLayout];' && fn $D 'static void DMDesktopRenameTurned(' | grep -qF '    dispatch_async(dispatch_get_main_queue(), ^{'"
  ck "  ... the iPadOS Dock's state at the turn read in a debug build only" "[ \"\$(ifdebug $D 'DMDesktopTurnDockNote(@')\" = yes ] && [ \"\$(ifdebug $D 'static void DMDesktopTurnDockNote(NSString *when) {')\" = yes ]"
  ck "the crash guard: the new names map where the typing window's do" \
     "python3 -I - $R <<'PY'
import re, sys
rules = [l.split() for l in open(sys.argv[1]) if l.strip() and not l.startswith('#')]
sym = [(re.compile(f[2]), f[3]) for f in rules if len(f) >= 4 and f[0] == 'sym' and f[1] == 'MacStatusBarCore']
fil = [(re.compile(f[2]), f[3]) for f in rules if len(f) >= 4 and f[0] == 'file' and f[1] == 'MacStatusBarCore']
first = lambda rs, s: next((t for rx, t in rs if rx.search(s)), None)
want = first(sym, '_DMDesktopRenameLayout') or first(fil, 'Desktop.h')
got = [first(sym, n) or first(fil, 'Desktop.h') for n in ('_DMDesktopRenameTurned', '_DMDesktopTurnArgs', '___DMDesktopRenameTurned_block_invoke')]
sys.exit(0 if want and all(g == want for g in got) else 1)
PY"
  ck "no em or en dash in Desktop.h or this test" "! grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $D test-typingturn.sh test-typingturn.m"
  return $n
}

D0=$R0/statusbar/Desktop.h; RR0=$R0/tools/crashmap-rules.txt
echo "== (1) the real code (Mac Catalyst)"
harness "$D0" "$W/h" "" || fails=1
echo "== (2) the wiring"
pins "$D0" "$RR0" "" || fails=1
if [ -z "$TT_ROOT" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mk() {   # $1 what, $2 perl substitution on Desktop.h
    local d="$W/m"; rm -rf "$d"; mkdir -p "$d"; cp "$D0" "$d/f"
    perl -0pi -e "$2" "$d/f"
    cmp -s "$d/f" "$D0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    local n=0
    harness "$d/f" "$d/h" q || n=$((n + 1))
    pins "$d/f" "$RR0" q; n=$((n + $?))
    if [ $n -gt 0 ]; then echo "PASS  caught: $1 ($n)"; else echo "FAIL  not caught: $1"; fails=1; fi
  }
  mk "the turn not answered (1.8.8.1.1)" 's/                if \(\[turnArgs isEqualToString:\@"v\@:qdq"\]\) class_addMethod\(sub, turnSel, \(IMP\)DMDesktopRenameTurned, method_getTypeEncoding\(turn\)\);\n/                (void)turnArgs;\n/'
  mk "answered whatever its shape" 's/if \(\[turnArgs isEqualToString:\@"v\@:qdq"\]\) class_addMethod/if (turn) class_addMethod/'
  mk "SpringBoard's own handling skipped" 's/(static void DMDesktopRenameTurned[^\n]*\n[^\n]*\n)    \(\(void \(\*\)\(struct objc_super \*, SEL, long long, double, long long\)\)objc_msgSendSuper\)\(&sup, _cmd, to, duration, from\);\n/$1    (void)sup;\n/'
  mk "fitted before SpringBoard's own handling" 's/(static void DMDesktopRenameTurned[^\n]*\n[^\n]*\n)(    \(\(void[^\n]*\n)/$1    DMDesktopRenameFit();\n$2/'
  mk "fitted while hidden" 's/    if \(self != gDesktopRenameWindow \|\| self\.hidden\) return;/    if (self != gDesktopRenameWindow) return;/'
  mk "no fit after SpringBoard's turn is applied" 's/    dispatch_async\(dispatch_get_main_queue\(\), \^\{\n        DMDesktopRenameFit\(\);\n/    dispatch_async(dispatch_get_main_queue(), ^{\n/'
  mk "no layout pass asked for" 's/    \[self setNeedsLayout\];\n//'
fi
[ $fails = 0 ] && echo "test-typingturn: all pass" || { echo "test-typingturn: FAILED"; exit 1; }
