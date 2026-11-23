#!/bin/bash
# test-editmenulie.sh: how the edit menu's container lies on the iPad's screen, read on the device (1.8.8.2, the edit menu on iPadOS 17). On
# 17.5.1 in landscape a desktop rename's or a sticky note's Cut / Copy / Paste menu stays off the screen: its container in the text effects window
# lies in SpringBoard's fixed portrait space like its scene ({1024, 1366}, "the scene's space is the container's") and UIKit's bottom inset is
# 1372. 17's insets method is 16's formula (17.6.1 decompile, hooked there by the 1.8.8.1.1 fix), so the keyboard's frame is already in the
# container's space: the room is not that fault's. Whether that container is drawn turned on the screen or upright for portrait decides 17's
# fix; a debug build's [editmenu] line now says how it lies (statusbar/EditMenuRoom.h DMEditMenuLie). Nothing changes in what UIKit gets.
#  (1) the wiring: the reading in a debug build only, in the line of the three cases where UIKit's answer stands or is redone, the private
#      getters asked by their return type first, the decision itself unchanged by it;
#  then made-to-fail copies, each must fail. (The code builds and runs in test-editmenuroom.sh, release and DEBUG.)
# EL_ROOT: another tree (e.g. the code before it): run on it, no made-to-fail copies.
cd "$(dirname "$0")" || exit 1
R0=$(cd "${EL_ROOT:-..}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
ifdebug() {   # $1 file, $2 text: is every line holding it inside an "#if DEBUG" (not its #else)?
  awk -v s="$2" '
    /^#if DEBUG/ { st[++n] = 1; next } /^#if/ { st[++n] = 0; next } /^#else/ { if (st[n] == 1) st[n] = 2; next } /^#endif/ { n--; next }
    index($0, s) { seen = 1; ok = 0; for (i = 1; i <= n; i++) if (st[i] == 1) ok = 1; if (!ok) bad = 1 }
    END { print (seen && !bad) ? "yes" : "no" }
  ' "$1"
}
pins() {   # $1 statusbar/EditMenuRoom.h, $2 quiet: the number that fail
  local H=$1 q=$2 n=0
  ok() { [ -n "$q" ] || echo "PASS  $1"; }
  no() { [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); }
  ck() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
  ck "EditMenuRoom.h: the reading is there, in a debug build only (its definition and every use)" \
     "grep -qxF 'static NSString *DMEditMenuLie(UIView *c) {' $H && [ \"\$(ifdebug $H 'DMEditMenuLie(')\" = yes ]"
  ck "  ... added to the line where UIKit's answer stands (the spaces agree: 17.5.1's case), is redone, or is kept by the debug switch" \
     "fn $H 'static void DMEditMenuNote(' | grep -qF '    if (why == MSBDEditMenuSpacesSame || why == MSBDEditMenuRedo || why == MSBDEditMenuKept) more = [more stringByAppendingString:DMEditMenuLie(c)];'"
  ck "  ... what it says: the container on the screen and in the fixed space, its x axis's turn, the window's bounds, orientation and the layers above it, SpringBoard's orientation, the screen" \
     "fn $H 'static NSString *DMEditMenuLie(' | grep -qF '@\"; on the screen %@ (its x axis at %.0f deg), in the fixed space %@; window %@ orientation %ld, layers above it %@ %@; SpringBoard' && fn $H 'static NSString *DMEditMenuLie(' | grep -qF ' orientation %ld, screen %@\",'"
  ck "  ... only the iPad's own screen (the TV keeps its line as it was)" "fn $H 'static NSString *DMEditMenuLie(' | grep -qF '    if (!w || w.screen != s) return @\"\";'"
  ck "  ... the window's and SpringBoard's orientation getters asked only where they return an integer" \
     "fn $H 'static NSString *DMEditMenuLie(' | grep -qF \"return t && (t[0] == 'q' || t[0] == 'l') ? ((long (*)(id, SEL))objc_msgSend)(obj, io) : -1;\""
  ck "the decision does not read it: UIKit's answer as the 1.8.8.1.1 fix gives it, everywhere" "! fn $H '__attribute__((noinline)) static UIEdgeInsets DMEditMenuRoom(' | grep -q 'DMEditMenuLie'"
  ck "no em or en dash in it or this test" "! grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $H test-editmenulie.sh"
  return $n
}
H0=$R0/statusbar/EditMenuRoom.h
echo "== (1) the wiring"
pins "$H0" "" || fails=1
if [ -z "$EL_ROOT" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mk() {   # $1 what, $2 perl substitution
    local d="$W/m"; rm -rf "$d"; mkdir -p "$d"; cp "$H0" "$d/f"
    perl -0pi -e "$2" "$d/f"
    cmp -s "$d/f" "$H0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    pins "$d/f" q; local n=$?
    if [ $n -gt 0 ]; then echo "PASS  caught: $1 ($n)"; else echo "FAIL  not caught: $1"; fails=1; fi
  }
  mk "the reading in a release build" 's/\n#if DEBUG\n(\/\/ How the container lies)/\n$1/'
  mk "not in 17.5.1's case" 's/if \(why == MSBDEditMenuSpacesSame \|\| why == MSBDEditMenuRedo/if (why == MSBDEditMenuRedo/'
  mk "the getters asked whatever their type" "s/return t && \\(t\\[0\\] == 'q' \\|\\| t\\[0\\] == 'l'\\) \\? /return 1 ? /"
  mk "the decision reads it" 's/(            mine\.bottom = MSBDEditMenuBottom\(safe, maxY, CGRectGetMinY\(kbIn\)\);)/$1 (void)DMEditMenuLie(c);/'
  mk "the TV's line read too" 's/    if \(!w \|\| w\.screen != s\) return \@"";/    if (!w) return \@"";/'
fi
[ $fails = 0 ] && echo "test-editmenulie: all pass" || { echo "test-editmenulie: FAILED"; exit 1; }
