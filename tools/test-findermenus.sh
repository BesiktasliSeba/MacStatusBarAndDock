#!/bin/bash
# test-findermenus.sh: the menu bar's Finder menus are Finder's own (1.8.7.3, audit M7 of 1.8.7.2) -- see test-findermenus.m. File, View and Go's
# Finder rows are there only while a Finder window or Finder's Quick Look is active (not TextEdit, Activity Monitor or Display Settings), and every
# row, File > Eject too, acts on the Finder window the menu was opened for while it is still open and not minimized. The real code is cut out of
# statusbar/StatusBar.x, Finder.h, DriveEject.h and NativeWindow.h (FM_SB_X / FM_FINDER_H / FM_DRIVE_H / FM_NATIVE_H: other copies, e.g. the code
# before the fix, where the new Finder.h helpers do not exist yet) and run on the Mac (Mac Catalyst); then made-to-fail copies: each takes one part
# of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${FM_SB_X:-../statusbar/StatusBar.x}; F0=${FM_FINDER_H:-../statusbar/Finder.h}; D0=${FM_DRIVE_H:-../statusbar/DriveEject.h}; N0=${FM_NATIVE_H:-../statusbar/NativeWindow.h}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                    # one line of a file (a global, a one-line function)

N_ONE='static DMNativeWindow *DMNativeActiveApp(void) {'
F_FN='static DMFinderWindow *DMFinderFront(void) {'
F_NEW_FN=('static BOOL DMFinderNamedInBar(void) {' 'static DMFinderWindow *DMFinderMenuWindow(void) {'); F_NEW_ONE='static BOOL DMFinderMenuCanAct(DMFinderWindow *f) {'
D_ONE='static NSString *DMDriveEjectTitle(NSArray<NSDictionary *> *targets) {'; D_FN='static NSArray *DMDriveEjectMenuWith(NSArray *items, DMFinderWindow *f) {'
X_FN=('static DMRow *DMFinderRow(' 'static void DMOpenFinderFileMenu(UIButton *btn) {' 'static void DMOpenFinderViewMenu(UIButton *btn) {'
      'static void DMOpenFinderEditMenu(UIButton *btn, DMFinderWindow *f) {' 'static void DMOpenGoMenu(UIButton *btn) {')
X_TITLES='    BOOL finderTitles = '

run() {   # $1 StatusBar.x, $2 Finder.h, $3 DriveEject.h, $4 NativeWindow.h, $5 work dir, $6 quiet; the number of failed checks (99: not built)
  local X=$1 F=$2 D=$3 N=$4 d=$5 q=$6 h out n
  mkdir -p "$d"
  [ -n "$(line "$N" "$N_ONE")" ] || { echo "FAIL  $N: no line \"$N_ONE\""; return 99; }
  [ -n "$(fn "$F" "$F_FN")" ] || { echo "FAIL  $F: no function \"$F_FN\""; return 99; }
  [ -n "$(line "$D" "$D_ONE")" ] && [ -n "$(fn "$D" "$D_FN")" ] || { echo "FAIL  $D: no DMDriveEjectTitle / DMDriveEjectMenuWith"; return 99; }
  for h in "${X_FN[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  [ -n "$(line "$X" "$X_TITLES")" ] || { echo "FAIL  $X: no line \"$X_TITLES\""; return 99; }
  {
    line "$N" "$N_ONE"
    fn "$F" "$F_FN"
    fn "$F" "${F_NEW_FN[0]}"; line "$F" "$F_NEW_ONE"; fn "$F" "${F_NEW_FN[1]}"   # (the fix's helpers: not in the code before it)
    line "$D" "$D_ONE"; fn "$D" "$D_FN"
    for h in "${X_FN[@]}"; do fn "$X" "$h"; done
    printf 'static BOOL KFinderTitles(CGFloat appRight) {\n%s\n    return finderTitles;\n}\n' "$(line "$X" "$X_TITLES")"
  } > "$d/fm-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -o "$d/t" test-findermenus.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  return $n
}

run "$X0" "$F0" "$D0" "$N0" "$W/real"; rc=$?
if [ -z "$FM_SB_X$FM_FINDER_H$FM_DRIVE_H$FM_NATIVE_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (sbx|fh|drh), $3 perl expression
    local d="$W/m$((++k))" X=$X0 F=$F0 D=$D0 c src
    mkdir -p "$d"
    case $2 in sbx) src=$X0; c="$d/StatusBar.x"; X=$c;; fh) src=$F0; c="$d/Finder.h"; F=$c;; drh) src=$D0; c="$d/DriveEject.h"; D=$c;; esac
    perl -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$X" "$F" "$D" "$N0" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the bar's File and View for any native window again" sbx 's/BOOL finderTitles = DMFinderNamedInBar\(\) && appRight > 0;/BOOL finderTitles = DMNativeActiveApp() != nil && appRight > 0;/'
  mtf "Go's Finder rows for any native window again" sbx 's/if \(DMFinderNamedInBar\(\)\) \{   \/\/ \(Finder.s own rows/if (DMNativeActiveApp()) {   \/\/ (Finder own rows/'
  mtf "the File menu's window: the front Finder window, hidden or not" sbx 's/DMFinderWindow \*f = DMFinderMenuWindow\(\); BOOL sel/DMFinderWindow *f = DMFinderFront(); BOOL sel/'
  mtf "Go's window: the front Finder window, hidden or not" sbx 's/^        DMFinderWindow \*f = DMFinderMenuWindow\(\);$/        DMFinderWindow *f = DMFinderFront();/'
  mtf "a row looks its window up when it fires" sbx 's/^        DMFinderWindow \*w = wf;$/        DMFinderWindow *w = DMFinderFront();/'
  mtf "a row without a window is not greyed" sbx 's/enabled:enabled && f != nil handler:/enabled:enabled handler:/'
  mtf "File > Eject looks its window up when it fires" drh 's/DMFinderWindow \*w = wf; if \(DMFinderMenuCanAct\(w\)\)/DMFinderWindow *w = DMFinderFront(); if (DMFinderMenuCanAct(w))/'
  mtf "the menus' window: the front Finder window, whatever is active" fh 's/^    return \[w isKindOfClass:\[DMFinderWindow class\]\] && DMFinderMenuCanAct\(\(DMFinderWindow \*\)w\) \? \(DMFinderWindow \*\)w : nil;/    return DMFinderFront();/'
  mtf "a minimized Finder window can still be acted on" fh 's/return f && !f\.hidden && \[gNativeWindows/return f && [gNativeWindows/'
  mtf "Quick Look is not Finder's (no File or View for it)" fh 's/ \|\| \[a isKindOfClass:\[DMQuickLookWindow class\]\];/;/'
fi
exit $rc
