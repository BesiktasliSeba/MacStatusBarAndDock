#!/bin/bash
# test-nativehooks.sh: the native windows' hooks do not depend on Finder (1.8.7.4, audit M12 of 1.8.7.2) -- see test-nativehooks.m. Finder off at the
# start, Activity Monitor (and Display Settings) took SpringBoard's keyboard lock with none of the touch and key hooks that give it back: the hooks now
# go in the first time any native window comes on screen; not while the crash guard has Finder off for a crash in that code; and Finder switched
# off closes only Finder's own windows. The real code is cut out of statusbar/StatusBar.x, NativeWindow.h, ActivityMonitor.h, DisplaySettings.h and
# common/CrashGuard.h (NH_SB_X / NH_NATIVE_H / NH_AM_H / NH_DS_H / NH_GUARD_H: other copies, e.g. the code before the fix, where the fix's
# functions do not exist yet) and run on the Mac (Mac Catalyst), one scenario per process; then site checks; then made-to-fail copies: each takes
# one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${NH_SB_X:-../statusbar/StatusBar.x}; N0=${NH_NATIVE_H:-../statusbar/NativeWindow.h}; A0=${NH_AM_H:-../statusbar/ActivityMonitor.h}
D0=${NH_DS_H:-../statusbar/DisplaySettings.h}; G0=${NH_GUARD_H:-../common/CrashGuard.h}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

N_METHODS=('- (void)show {' '- (void)close {')
N_FN=('static void DMNativeSetActive(DMNativeWindow *w) {'); N_NEW=('static BOOL DMNativeGuardTookFinder(void) {' 'static BOOL DMNativeMayOpen(NSString *what) {')
X_FN=('static void DMNativeSysGesturesInit(void) {' 'static void DMFinderApplyPref(void) {'); X_NEW=('static void DMNativeHooksInit(void) {' 'static BOOL DMNativeIsFinders(DMNativeWindow *w) {')
A_FN='static void DMActivityMonitorOpen(void) {'; D_FN='static void DMDispSettingsOpenIPad(NSString *display) {'; G_NEW='static inline int MSBDGuardRecordNames('

sites() {   # $1 StatusBar.x, $2 ActivityMonitor.h, $3 DisplaySettings.h, $4 quiet: the number of site checks that fail
  local X=$1 A=$2 D=$3 q=$4 n=0 c rule re name
  # the hooks' %init: once, in DMNativeHooksInit (not in Finder's switch alone)
  if [ "$(grep -c '%init(DMNativeHooks);' "$X")" = 1 ] && fn "$X" "${X_NEW[0]}" | grep -q '^    %init(DMNativeHooks);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the native windows' hook group is installed in one place, DMNativeHooksInit"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: %init(DMNativeHooks) is not once, in DMNativeHooksInit"; n=$((n + 1)); fi
  # every native window is Finder's (closes with it) or made only in an opener that asks DMNativeMayOpen
  c=$(cat ../statusbar/*.h ../statusbar/*.x | sed -n -E 's/^@interface ([A-Za-z0-9_]+) : DMNativeWindow.*/\1/p' | sort | tr '\n' ' ')
  if [ "$c" = "DMActivityMonitorWindow DMDispSettingsWindow DMFinderWindow DMQuickLookWindow DMTextWindow " ]; then
    [ -n "$q" ] || echo "PASS  the native windows are the five this test knows: $c"
  else [ -n "$q" ] || echo "FAIL  the native windows are now: $c-- a new one: decide whether it is Finder's (DMNativeIsFinders) or opens through DMNativeMayOpen, and add it here"; n=$((n + 1)); fi
  if [ "$(cat ../statusbar/*.h ../statusbar/*.x | grep -c '\[DMActivityMonitorWindow alloc\]')" = 1 ] && fn "$A" "$A_FN" | grep -q '\[DMActivityMonitorWindow alloc\]' &&
     [ "$(cat ../statusbar/*.h ../statusbar/*.x | grep -c '\[DMDispSettingsWindow alloc\]')" = 1 ] && fn "$D" "$D_FN" | grep -q '\[DMDispSettingsWindow alloc\]'; then
    [ -n "$q" ] || echo "PASS  Activity Monitor's and Display Settings' windows are made only in their openers (the ones run above, which ask DMNativeMayOpen)"
  else [ -n "$q" ] || echo "FAIL  an Activity Monitor or Display Settings window is made outside its opener"; n=$((n + 1)); fi
  # the crash map: the fix's functions are Finder's, like the rest of the native windows' code (the guard's step for them is Finder's switch)
  rule=$(grep -E '^sym MacStatusBarCore \^_\?DM\(Finder\|Native' crashmap-rules.txt | head -1); re=$(echo "$rule" | awk '{print $3}')
  c=0; for name in DMNativeHooksInit DMNativeGuardTookFinder DMNativeMayOpen DMNativeIsFinders; do echo "_$name" | grep -qE "$re" || c=1; done
  if [ -n "$re" ] && [ "$(echo "$rule" | awk '{print $4}')" = finder ] && [ $c = 0 ]; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: DMNativeHooksInit, DMNativeGuardTookFinder, DMNativeMayOpen and DMNativeIsFinders fall under Finder's rule"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the fix's functions are not under Finder's rule"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 NativeWindow.h, $3 ActivityMonitor.h, $4 DisplaySettings.h, $5 CrashGuard.h, $6 work dir, $7 quiet; failed checks (99: not built)
  local X=$1 N=$2 A=$3 D=$4 G=$5 d=$6 q=$7 h out n=0 s r defs=""
  mkdir -p "$d"
  for h in "${N_METHODS[@]}" "${N_FN[@]}"; do [ -n "$(fn "$N" "$h")" ] || { echo "FAIL  $N: no \"$h\""; return 99; }; done
  for h in "${X_FN[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  [ -n "$(fn "$A" "$A_FN")" ] && [ -n "$(fn "$D" "$D_FN")" ] || { echo "FAIL  no DMActivityMonitorOpen / DMDispSettingsOpenIPad"; return 99; }
  [ -n "$(fn "$G" "$G_NEW")" ] || defs="$defs -DNH_NO_READER"
  for h in "${N_NEW[@]}" "${X_NEW[@]}"; do [ -n "$(fn "$N" "$h")$(fn "$X" "$h")" ] || { [ -n "$q" ] || echo "   (no \"$h\": the code before the fix)"; }; done
  for h in "${N_METHODS[@]}"; do fn "$N" "$h"; done > "$d/nh-methods.inc"
  { fn "$G" "$G_NEW"
    for h in "${N_NEW[@]}" "${N_FN[@]}"; do fn "$N" "$h"; done
    for h in "${X_FN[0]}" "${X_NEW[@]}" "${X_FN[1]}"; do fn "$X" "$h"; done
    fn "$A" "$A_FN"; fn "$D" "$D_FN"
  } | sed -E 's/%init\(([A-Za-z0-9_]+)\);/KInit(@"\1");/g' > "$d/nh-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" $defs \
        -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/t" test-nativehooks.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -n "$defs" ] && [ -z "$q" ] && echo "   (built as the code before the fix:$defs)"
  for s in $("$d/t" list); do
    [ -n "$q" ] || echo "-- $s"
    out=$("$d/t" "$s"); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; r=1; }
    n=$((n + r))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$A" "$D" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$N0" "$A0" "$D0" "$G0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-nativehooks: all pass" || echo "test-nativehooks: FAILED ($rc check(s))"
if [ -z "$NH_SB_X$NH_NATIVE_H$NH_AM_H$NH_DS_H$NH_GUARD_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (sbx|nw|am|ds|guard), $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" X=$X0 N=$N0 A=$A0 D=$D0 G=$G0 c src
    mkdir -p "$d"
    case $2 in sbx) src=$X0; c="$d/StatusBar.x"; X=$c;; nw) src=$N0; c="$d/NativeWindow.h"; N=$c;; am) src=$A0; c="$d/ActivityMonitor.h"; A=$c;;
               ds) src=$D0; c="$d/DisplaySettings.h"; D=$c;; guard) src=$G0; c="$d/CrashGuard.h"; G=$c;; esac
    perl -0777 -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$X" "$N" "$A" "$D" "$G" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "a native window shown without its hooks (Finder's switch alone puts them in)" nw 's/\n    DMNativeHooksInit\(\);[^\n]*//'
  mtf "the hook group back in Finder's switch only" sbx 's/\n    %init\(DMNativeHooks\);[^\n]*//; s/(        hooked = YES;\n)/$1        %init(DMNativeHooks);\n/'
  mtf "Finder on no longer puts the hooks in at once (the desktop needs them before any window)" sbx 's/\n    if \(on\) DMNativeHooksInit\(\);[^\n]*//'
  mtf "the hooks installed again at every window" sbx 's/(static void DMNativeHooksInit\(void\) \{\n    static BOOL done = NO;\n)    if \(done\) return;\n/$1/'
  mtf "the native windows' hooks set up Finder's Dock icon too" sbx 's/(    DMNativeSysGesturesInit\(\);\n    DMLog\(\@"\[native\] the native windows)/    DMFinderDockInit();\n$1/'
  mtf "Activity Monitor opens whatever the crash guard did" am 's/\n    if \(!DMNativeMayOpen\(\@"Activity Monitor"\)\) return;//'
  mtf "Display Settings opens whatever the crash guard did" ds 's/\n        if \(!DMNativeMayOpen\(\@"Display Settings"\)\) return;[^\n]*//'
  mtf "the guard's record read without its note (a cleared note still refuses)" nw 's/return MSBDStepGuardAction\(\) != 0 && MSBDGuardRecordNames/return MSBDGuardRecordNames/'
  mtf "the guard's refusal kept with Finder switched back on" nw 's/if \(gFinderOn \|\| !DMNativeGuardTookFinder\(\)\) return YES;/if (!DMNativeGuardTookFinder()) return YES;/'
  mtf "the guard's note read once (no change without a respring)" nw 's/(static BOOL DMNativeGuardTookFinder\(void\) \{\n)/$1    static int once = -1; if (once < 0) once = MSBDStepGuardAction() != 0 \&\& MSBDGuardRecordNames(MSBD_GUARD_RECORD, "com.besiktasliseba.macstatusbar", "finderEnabled"); return once;\n/'
  mtf "Finder switched off closes every native window again" sbx 's/for \(DMNativeWindow \*w in \[gNativeWindows copy\]\) if \(DMNativeIsFinders\(w\)\) \{/for (DMNativeWindow *w in [gNativeWindows copy]) {/'
  mtf "Finder switched off brings another native window forward (the close's own pick kept)" sbx 's/\n    if \(gNativeActive != keep\) DMNativeSetActive\(keep\);//'
  mtf "TextEdit no longer counted as Finder's" sbx 's/ \|\| \[w isKindOfClass:\[DMTextWindow class\]\];/;/'
  mtf "the reader takes any domain" guard 's/ && !strcmp\(d, domain\) && !strcmp\(k, key\)\)/ \&\& !strcmp(k, key))/'
  mtf "the reader matches the key's start only" guard 's/!strcmp\(k, key\)\)/!strncmp(k, key, strlen(key)))/'
  mtf "the reader reads the rest of a long line as a line" guard 's/if \(whole && sscanf/if (sscanf/'
  mtf "the reader takes step 1b lines only (step 1's switch line missed)" guard 's/\(!strcmp\(kind, "switch"\) \|\| !strcmp\(kind, "feature"\)\)/!strcmp(kind, "feature")/'
fi
exit $rc
