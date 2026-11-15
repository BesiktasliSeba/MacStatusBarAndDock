#!/bin/bash
# test-kbnokeyboard.sh: the keyboard-behind pass with no hardware keyboard (1.8.7.4, audit O3 and L52 of 1.8.7.2). With no hardware keyboard and
# nothing to undo, the pass no longer walks every window 5 times a second (it only notes the active app); the give-back needs a hardware keyboard
# (no on-screen keyboard put up for an app brought to the front without a tap, after a keyboard was attached and removed); the apps held back while
# a keyboard was attached are let go when it goes. See test-kbnokeyboard.m. The real code is cut out of statusbar/StatusBar.x (KN_SB_X: another
# copy, e.g. the code before the fix) and run on the Mac, release and DEBUG; then site checks; then made-to-fail copies (each takes one part of
# the fix out and must fail); then the proof that nothing else changed: random sequences run on this code and on the code before the fix
# (KN_REF_X, else this file with the fix taken out) give the same calls and state at every pass: with a hardware keyboard attached all along
# (class A, the windows walked as often too) and with the keyboard coming and going outside the L52 cases (class B).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${KN_SB_X:-../statusbar/StatusBar.x}
# one function of a file, from its first line to its closing brace
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; next } f { print } f && /^[}]/ { exit }' "$1"; }

cut() {   # $1 StatusBar.x, $2 out .inc: 0 when cut
  local X=$1 o=$2
  {
    fn "$X" 'static id DMCall(id obj, NSString *name) {'
    fn ../common/FocusLock.h '__attribute__((unused)) static NSString *MSBDFocusBareTypes(Method m) {'
    fn ../common/FocusLock.h '__attribute__((unused)) static BOOL MSBDFocusHas(id obj, SEL sel, NSString *types) {'
    # (the gate's state, the arbiter's hooks and their install, the give-back and the pass; the iPadOS version is the test's)
    awk 'index($0, "#include \"KeyboardBehind.h\"") == 1 { f = 1 } f { print } f && index($0, "static void DMKeyboardFocusBehindWindows(void) {") == 1 { s = 1 } s && /^[}]/ { exit }' "$X" |
      sed 's/\[NSProcessInfo processInfo\]\.operatingSystemVersion\.majorVersion/TOSMajor()/'
  } > "$o"
  grep -qF 'static void DMKeyboardFocusBehindWindows(void) {' "$o" && grep -qF 'TOSMajor()' "$o" && grep -qF 'static void DMKBArbiterGateInit(void) {' "$o" &&
    grep -qF 'static BOOL MSBDFocusHas(id obj, SEL sel, NSString *types) {' "$o" && grep -qF 'static id DMCall(id obj, NSString *name) {' "$o"
}
build() {   # $1 .inc, $2 binary, $3 extra flags
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$(dirname "$1")" -I../statusbar $3 \
        -framework Foundation -o "$2" test-kbnokeyboard.m 2> "$2.cc.txt"
}

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0
  if fn "$X" 'static void DMSyncWindowsForLibraryBody(void) {' | grep -qF '    DM_PERF("kbbehind", DMKeyboardFocusBehindWindows());'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the 0.2 s tick runs the pass (DMSyncWindowsForLibraryBody)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the tick no longer runs the pass"; n=$((n + 1)); fi
  if fn "$X" 'static BOOL DMHardwareKeyboardAttached(void) {' | grep -qF '"GSEventIsHardwareKeyboardAttached"'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the hardware keyboard is GraphicsServices' flag, the one UIKit itself reads"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMHardwareKeyboardAttached is not GraphicsServices' flag"; n=$((n + 1)); fi
  if grep -qF '    if (!hardwareKeyboard || !engine) return out;' ../statusbar/KeyboardBehind.h; then
    [ -n "$q" ] || echo "PASS  KeyboardBehind.h: with no hardware keyboard no window is kept from the keys (what the early return stands on)"
  else [ -n "$q" ] || echo "FAIL  KeyboardBehind.h: MSBDKeyboardBehind may keep windows with no hardware keyboard"; n=$((n + 1)); fi
  if [ "$(fn "$X" 'static void DMKeyboardFocusBehindWindows(void) {' | grep -c 'DMHardwareKeyboardAttached()')" = 1 ] &&
     fn "$X" 'static void DMKeyboardFocusBehindWindows(void) {' | grep -qF '    NSSet<NSString *> *behind = MSBDKeyboardBehind(bundles, active, keyboard, can);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the pass reads the keyboard once (the early return and the list agree)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the pass reads the keyboard more than once"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (99: not built)
  local X=$1 d=$2 q=$3 n s out k
  mkdir -p "$d"
  cut "$X" "$d/kbnokeyboard-real.inc" || { echo "FAIL  $X: the pass was not found"; return 99; }
  build "$d/kbnokeyboard-real.inc" "$d/t" || { [ -n "$q" ] || cat "$d/t.cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  if [ -z "$q" ]; then   # (the same scenarios, the DEBUG build: its own lines in the pass and the hooks)
    build "$d/kbnokeyboard-real.inc" "$d/td" "-DDEBUG=1" || { cat "$d/td.cc.txt"; echo "FAIL  the real code did not build with DEBUG"; return 99; }
    k=$("$d/td" | grep -c '^FAIL')
    [ "$k" = 0 ] && echo "PASS  the same scenarios, DEBUG build" || { echo "FAIL  the DEBUG build: $k check(s) fail"; n=$((n + k)); }
    echo "-- site checks"
  fi
  sites "$X" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-kbnokeyboard: all pass" || echo "test-kbnokeyboard: FAILED ($rc check(s))"
[ -n "$KN_SB_X" ] && exit $rc

echo "-- made-to-fail copies (each must fail)"
k=0
mtf() {   # $1 what, $2 perl expression on StatusBar.x (the whole file at once)
  local d="$W/m$((++k))" c
  mkdir -p "$d"; c="$d/StatusBar.x"
  perl -0777 -pe "$2" "$X0" > "$c"
  cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
  run "$c" "$d/w" q; local n=$?
  if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
}
mtf "the windows walked again with no keyboard (the early return taken out)" 's/\n    if \(!keyboard && !gKBBehind\.count && !DMKBGateHolds\(\)\) \{\n.*?\n        return;\n    \}//s'
mtf "the early return does not note the active app" 's/\n        gKBBehindLastActive = \[active copy\];\n        return;/\n        return;/'
mtf "the early return taken with something still to undo" 's/if \(!keyboard && !gKBBehind\.count && !DMKBGateHolds\(\)\) \{/if (!keyboard) {/'
mtf "the early return before the gate-off one (the active app noted with the gate off)" 's/(\n    if \(!can && !gKBBehind\.count && !DMKBGateHolds\(\)\) return;)(\n.*?\n        return;\n    \})/$2$1/s'
mtf "the give-back with no hardware keyboard" 's/\n    if \(!DMHardwareKeyboardAttached\(\)\) return;\n    if \(!DMKBUserFocusRequest\(/\n    if (!DMKBUserFocusRequest(/'
mtf "the held-back list kept with no keyboard" 's/if \(!can \|\| !keyboard\) DMKBClearHeldBack\(\);/if (!can) DMKBClearHeldBack();/'

echo "-- nothing else changed: random sequences on this code and on the code before the fix"
REF=$KN_REF_X
if [ -z "$REF" ]; then   # (this file with the fix taken out, each part of it)
  REF="$W/ref/StatusBar.x"; mkdir -p "$W/ref"
  perl -0777 -pe '
    $n = 0;
    $n += s/\n    \/\/ \(only with a hardware keyboard, the one the gate is for\.[^\n]*(\n    \/\/ [^\n]*){3}\n    if \(!DMHardwareKeyboardAttached\(\)\) return;//;
    $n += s/\n    \/\/ \(no hardware keyboard: no window is kept from the keys[^\n]*(\n    \/\/ [^\n]*){3}\n    BOOL keyboard = DMHardwareKeyboardAttached\(\);\n    if \(!keyboard && !gKBBehind\.count && !DMKBGateHolds\(\)\) \{\n.*?\n        return;\n    \}//s;
    $n += s/MSBDKeyboardBehind\(bundles, active, keyboard, can\)/MSBDKeyboardBehind(bundles, active, DMHardwareKeyboardAttached(), can)/;
    $n += s/ without it\.\n    \/\/  Only with a hardware keyboard \(DMKBGiveBack\)[^\n]*\n/ without it)\n/;
    $n += s/if \(!can \|\| !keyboard\) DMKBClearHeldBack\(\);/if (!can) DMKBClearHeldBack();/;
    END { exit($n == 5 ? 0 : 1) }' "$X0" > "$REF" || { echo "FAIL  the fix could not be taken out of this copy (pass KN_REF_X=<StatusBar.x before the fix>)"; exit 1; }
  echo "   (the code before the fix: this file with the fix taken out)"
else echo "   (the code before the fix: $REF)"; fi
mkdir -p "$W/new" "$W/old"
cut "$X0" "$W/new/kbnokeyboard-real.inc" && build "$W/new/kbnokeyboard-real.inc" "$W/new/t" || { echo "FAIL  this code did not build for the traces"; exit 1; }
cut "$REF" "$W/old/kbnokeyboard-real.inc" && build "$W/old/kbnokeyboard-real.inc" "$W/old/t" || { cat "$W/old/t.cc.txt"; echo "FAIL  the code before the fix did not build"; exit 1; }
for c in A B; do
  "$W/new/t" trace $c 250 > "$W/new/$c.txt" || { echo "FAIL  class $c: this code crashed"; rc=1; continue; }
  "$W/old/t" trace $c 250 > "$W/old/$c.txt" || { echo "FAIL  class $c: the code before the fix crashed"; rc=1; continue; }
  passes=$(grep -c '^p' "$W/new/$c.txt"); nokb=$(grep -c '^p[0-9]* kb0' "$W/new/$c.txt")
  wn=$(awk '/^#cost/ { s += $3 } END { print s + 0 }' "$W/new/$c.txt"); wo=$(awk '/^#cost/ { s += $3 } END { print s + 0 }' "$W/old/$c.txt")
  if [ $c = A ]; then
    if cmp -s "$W/new/$c.txt" "$W/old/$c.txt" && [ "$nokb" = 0 ]; then
      echo "PASS  class A (a hardware keyboard attached all along; apps asking from behind, fields keeping the keys, engines, Finder): 250 sequences, $passes passes: the same calls and state at every pass, the windows walked as often ($wn walks)"
    else echo "FAIL  class A: the calls, the state or the walks differ from the code before the fix:"; diff "$W/old/$c.txt" "$W/new/$c.txt" | head -8; rc=1; fi
  else
    if cmp -s <(grep -v '^#' "$W/new/$c.txt") <(grep -v '^#' "$W/old/$c.txt") && [ "$nokb" -gt 0 ] && [ "$wn" -lt "$wo" ]; then
      echo "PASS  class B (the keyboard coming and going, outside the L52 cases): 250 sequences, $passes passes ($nokb with no keyboard): the same calls and state at every pass; walks $wo -> $wn"
    else echo "FAIL  class B: the calls or the state differ from the code before the fix (or no walk saved: $wo -> $wn):"; diff <(grep -v '^#' "$W/old/$c.txt") <(grep -v '^#' "$W/new/$c.txt") | head -8; rc=1; fi
  fi
done
exit $rc
