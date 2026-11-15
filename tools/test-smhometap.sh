#!/bin/bash
# test-smhometap.sh: the Stage Manager engine, Open Apps as Windows off -- a minimized window tapped in the Dock (or the App Library) at the Home
# Screen comes back as that window, no longer full screen (1.8.7.4, audit M13 of 1.8.7.2); an app with no minimized window opens full screen as
# before. See test-smhometap.m. The real code is cut out of statusbar/StatusBar.x (SHT_SB_X: another copy, e.g. the code before the fix, which has
# no DMSMHomeTapBringsWindow) and run on the Mac; then site checks on StatusBar.x (SpringBoard's own launch and the join that brings the window back);
# then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SHT_SB_X:-../statusbar/StatusBar.x}
# one function of a file, from its first line to its closing brace (a function on one line: that line)
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; l = $0; sub(/[ \t]*\/\/.*$/, "", l); if (l ~ /\}[ \t]*$/) exit; next } f { print } f && /^[}]/ { exit }' "$1"; }
SHT_FN=('static BOOL DMSMIsMinimized(NSString *key) {' 'static void DMSMGrowFromDockAtTapForApp(NSString *bundle) {' 'static id DMSMStageOf(NSString *key) {'
        'static id DMSMFrontStageOnDisplay(id identity) {' 'static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {' 'static BOOL DMSMAddNo(NSString *bundle, NSString *why) {'
        'static BOOL DMSMHomeTapBringsWindow(NSString *bundle) {' 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' 'static id DMSMFrontStage(void) {'
        'static BOOL DMSMOpensAsWindow(NSString *key, BOOL windowed, BOOL minimized) {')
SHT_NEW='static BOOL DMSMHomeTapBringsWindow(NSString *bundle) {'   # (the fix's: not in the code before it)

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0 j re
  # the fix's question: asked in one place, the Home Screen's branch of the icon tap, after Open Apps as Windows and before our full-screen stage
  if [ "$(grep -c 'DMSMHomeTapBringsWindow(' "$X")" = 2 ] &&
     fn "$X" 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' | awk '/^    if \(main && !front\) \{/ {h=NR} h && /if \(windowed \|\| !map.count\)/ {w=NR}
        h && /^        if \(DMSMHomeTapBringsWindow\(bundle\)\) \{ DMSMGrowFromDockAtTapForApp\(bundle\); return DMSMAddNo\(bundle, / {b=NR} h && /return DMSMOpenFullScreenStage\(bundle,/ {o=NR; exit}
        END {exit !(h && w > h && b > w && o > b)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the Home Screen's branch asks DMSMHomeTapBringsWindow (its one caller) before it makes a full-screen stage"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the Home Screen's branch does not ask for a minimized window before its full-screen stage"; n=$((n + 1)); fi
  # not added = SpringBoard's own launch, on 16 and on 17
  if awk '/^%group SMEngine$/ {g=1} g && index($0, "- (void)_handleTap {") == 1 {f=1} f {print} f && /^[}]/ {exit}' "$X" | awk '/BOOL added = DMSMAddToStage\(bundle, \(UIView \*\)self\);/ {a=NR} a && /if \(added\) \{ if \(library\) DMSMLibraryLaunched\(bundle\); return; \}/ {r=NR} r && /^    %orig;/ {o=NR} END {exit !(a && r > a && o > r)}' &&
     fn "$X" 'static void DMSMIconTapMods(id self, SEL _cmd, long long flags) {' | awk '/BOOL added = DMSMAddToStage\(bundle, \(UIView \*\)self\);/ {a=NR} a && /if \(added\) \{ if \(library\) DMSMLibraryLaunched\(bundle\); return; \}/ {r=NR} r && /^    o_SMIconTapMods\(self, _cmd, flags\);/ {o=NR} END {exit !(a && r > a && o > r)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: a tap not added to a stage goes on as SpringBoard's own launch (-_handleTap on 16, -_handleTapWithModifierFlags: on 17)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: a tap not added no longer reaches SpringBoard's own launch"; n=$((n + 1)); fi
  # the join of that launch from the Home Screen: no desktop to join, the window opens as DMSMOpensAsWindow says for its key and its mark from before
  # the launch, and the mark goes once the join is written
  j=$(fn "$X" 'static void DMSMJoinDesktop(id ctx) {')
  if echo "$j" | awk '/^    BOOL wasMinimized = DMSMIsMinimized\(key\);/ {m=NR} /^    BOOL fromHome = !tv && DMSMHomeStateOf\(DMSMHomePrevState\(ctx\), &prevEnv, &prevStage\) && prevEnv == 1;/ {h=NR}
        /^    id desk = fromHome \? nil : DMSMDesktopFor\(/ {d=NR} /^    if \(!map.count\) \{/ {e=NR} e && !w && /^        BOOL windowed = DMSMOpensAsWindow\(key, DMWindowedLaunchOn\(\), wasMinimized\);/ {w=NR}
        w && /^        id attrs = DMSMJoinAttributesOn\(key, nil, windowed, 0, nil, / {a=NR} /^    if \(ok\) DMSMSetMinimized\(key, NO\);/ {o=NR}
        END {exit !(m && h > m && d > h && e > d && w > e && a > w && o > a)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the join of a launch from the Home Screen opens the window as DMSMOpensAsWindow says (its key, its mark before the launch), then clears the mark"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the join from the Home Screen no longer asks DMSMOpensAsWindow with the window's mark"; n=$((n + 1)); fi
  # the crash map: the new function is the Stage Manager engine's, as DMSMAddToStage (the guard's step for it is the windowing switch)
  re=$(grep -E '^sym MacStatusBarCore \^_\*DMSM\[A-Z0-9\] windowingEnabled$' crashmap-rules.txt | awk '{print $3}')
  if [ -n "$re" ] && echo "_DMSMHomeTapBringsWindow" | grep -qE "$re" && echo "_DMSMAddToStage" | grep -qE "$re"; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: DMSMHomeTapBringsWindow falls under the Stage Manager engine's rule (windowingEnabled), as DMSMAddToStage"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: DMSMHomeTapBringsWindow is not under the Stage Manager engine's rule"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (99: not built)
  local X=$1 d=$2 q=$3 h n s out
  mkdir -p "$d"
  for h in "${SHT_FN[@]}"; do
    [ "$h" = "$SHT_NEW" ] && continue
    [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }
  done
  [ -n "$(fn "$X" "$SHT_NEW")" ] || { [ -n "$q" ] || echo "   (no DMSMHomeTapBringsWindow: the code before the fix)"; }
  for h in "${SHT_FN[@]}"; do fn "$X" "$h"; done > "$d/smhometap-real.inc"
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" -I../statusbar \
        -framework Foundation -o "$d/t" test-smhometap.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-smhometap: all pass" || echo "test-smhometap: FAILED ($rc check(s))"
if [ -z "$SHT_SB_X" ]; then
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
  mtf "the Home Screen's branch no longer asks (a minimized window opens full screen again)" 's/\n        if \(DMSMHomeTapBringsWindow\(bundle\)\) \{[^\n]*//'
  mtf "any minimized window of the app counts (a full-screen app sent away no longer opens full screen)" 's/ && DMSMOpensAsWindow\(k, NO, YES\)\) return YES;/) return YES;/'
  mtf "any app's minimized window counts" 's/if \(\[DMSMKeyBundle\(k\) isEqualToString:bundle\] && DMSMOpensAsWindow\(k, NO, YES\)\)/if (DMSMOpensAsWindow(k, NO, YES))/'
  mtf "asked by the app, not by each window" 's/&& DMSMOpensAsWindow\(k, NO, YES\)\) return YES;/&& DMSMOpensAsWindow(bundle, NO, YES)) return YES;/'
  mtf "asked as if apps opened as windows" 's/&& DMSMOpensAsWindow\(k, NO, YES\)\) return YES;/&& DMSMOpensAsWindow(k, YES, YES)) return YES;/'
  mtf "no picture grows out of the Dock" 's/if \(DMSMHomeTapBringsWindow\(bundle\)\) \{ DMSMGrowFromDockAtTapForApp\(bundle\); /if (DMSMHomeTapBringsWindow(bundle)) { /'
  mtf "our full-screen stage made first (the question after it)" 's/(\n        if \(DMSMHomeTapBringsWindow\(bundle\)\) \{[^\n]*)(\n        return DMSMOpenFullScreenStage\([^\n]*)/$2$1/'
  mtf "the join from the Home Screen reads the mark after it was cleared" 's/(    if \(!map.count\) \{.*?        BOOL windowed = DMSMOpensAsWindow\(key, DMWindowedLaunchOn\(\), )wasMinimized\);/$1NO);/s'
  mtf "a tap not added no longer goes on as SpringBoard's launch (17)" 's/(        if \(added\) \{ if \(library\) DMSMLibraryLaunched\(bundle\); return; \}\n    \}\n    gSMInIconTap = YES;\n)    o_SMIconTapMods\(self, _cmd, flags\);/$1/'
fi
exit $rc
