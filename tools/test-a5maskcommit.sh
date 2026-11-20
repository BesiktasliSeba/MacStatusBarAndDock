#!/bin/bash
# test-a5maskcommit.sh: Aerial 5's corner mask on a window's app holder is committed at the holder's size (1.8.7.9, KT's M1 recording of 18 Nov:
# a Finder open or close drew the app of the Fill window behind cut 52 x 32 pt along its right and bottom edges for one frame; KT's report of a
# window behind that briefly shrinks as another is minimized or closed) -- see test-a5maskcommit.m. The real code is cut out of
# statusbar/StatusBar.x (A5M_SB_X: another copy, e.g. 1.8.7.8's, where the new parts are missing: its catcher is then the pass alone) and run on
# the Mac (Mac Catalyst) with real Core Animation commits, in a release and a DEBUG build; then the site checks; then made-to-fail copies, each
# must fail. T16-T21 (1.8.8, H2 row 3 on Aerial 5.1): the fit-pass answer counts only what it put back, so a window minimized at Fill that the pass
# shrank out of sight is put back by the commit that shows it again (Z8, the counter, the turn), and a fight on screen is still left to Aerial.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
S0=${A5M_SB_X:-../statusbar/StatusBar.x}
fn() {   # $1 file, $2 first line: one function, by its braces
  awk -v s="$2" '!f && index($0, s) == 1 { f = 1 } f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }' "$1"
}
span() {   # $1 file, $2 first line, $3 the first line of the function that ends it: from $2 to the end of that function
  awk -v s="$2" -v e="$3" '!f && index($0, s) == 1 { f = 1 } f && !g && index($0, e) == 1 { g = 1 } f { print } g { t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }' "$1"
}
SCREEN='s/\[UIScreen mainScreen\]\.bounds\.size/TScreenSize()/g'

build() {   # $1 StatusBar.x, $2 dir, $3 quiet, $4 debug values: the test built on that code
  local X=$1 d=$2 dbg
  mkdir -p "$d"; cp ../statusbar/A5FitPass.h "$d/"
  { echo '#if DEBUG'; echo 'static CADisplayLink *gA5FrameLink;'; echo '#endif'
    fn "$X" 'static UIView *DMStageInnerView(UIView *stage) {'
    span "$X" 'static const void *kA5MaskKey = &kA5MaskKey;' 'static void DMA5SyncHostMaskFor(UIView *stage, UIView *holder) {'
    echo '#if DEBUG'; fn "$X" 'static void DMA5MaskTrace(UIView *stage, CGSize was, CGSize now) {'; echo '#endif'; } > "$d/one-mask.inc"
  grep -q 'gA5MaskBy' "$d/one-mask.inc" || { echo '#if DEBUG'; echo 'static const char *gA5MaskBy;   // (not in this source)'; echo '#endif'; } >> "$d/one-mask.inc"
  { fn "$X" 'static BOOL DMA5MaskOld(void) {'; fn "$X" 'static void DMStagePutBack(UIView *stage, CGRect frame) {'; fn "$X" 'static void DMEnforceStageFrame(UIView *stage, NSString *why) {'; } | sed "$SCREEN" > "$d/one-putback.inc"
  span "$X" 'static const void *kA5EntranceTargetKey = &kA5EntranceTargetKey;' 'static void DMA5HoldEntranceFrame(UIView *stage) {' | sed "$SCREEN" > "$d/one-hold.inc"
  { grep -E '^static const void \*kA5FitBackTimesKey = ' "$X"; fn "$X" 'static void DMA5AnswerFitPass(UIView *stage, CFTimeInterval now) {'; } | sed "$SCREEN" > "$d/one-fit.inc"
  span "$X" 'static BOOL DMA5MaskStale(UIView *stage) {' 'static void DMA5CatchNewStages(void) {' > "$d/one-commit.inc"
  grep -q '^static void DMA5CatchNewStages(void) {' "$d/one-commit.inc" || echo 'static void DMA5CatchNewStages(void) { DMA5CatchNewStagesPass(); }   // (not in this source: the pass alone)' > "$d/one-commit.inc"
  grep -q '^static void DMA5SyncHostMaskFor(UIView \*stage, UIView \*holder) {' "$d/one-mask.inc" && grep -q 'static UIView \*DMStageInnerView' "$d/one-mask.inc" \
    && grep -q '^static void DMEnforceStageFrame' "$d/one-putback.inc" && grep -q '^static void DMA5AnswerFitPass' "$d/one-fit.inc" && grep -q '^static void DMA5HoldEntranceFrame' "$d/one-hold.inc" \
    || { echo "FAIL  the code was not found in $X"; return 99; }
  for dbg in $4; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" -DDEBUG=$dbg \
          -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/t-$dbg" test-a5maskcommit.m 2> "$d/cc-$dbg.txt" || { [ -n "$3" ] || cat "$d/cc-$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -s "$d/cc-$dbg.txt" ] && [ -z "$3" ] && { echo "FAIL  warnings (DEBUG=$dbg):"; cat "$d/cc-$dbg.txt"; return 1; }
  done
  return 0
}

ifdebug() {   # $1 file, $2 text: is the line holding it inside an "#if DEBUG" (and not in its #else)?
  awk -v s="$2" '
    /^#if DEBUG/ { st[++n] = 1; next } /^#if/ { st[++n] = 0; next } /^#else/ { if (st[n] == 1) st[n] = 2; next } /^#endif/ { n--; next }
    index($0, s) { ok = 0; for (i = 1; i <= n; i++) if (st[i] == 1) ok = 1; print ok ? "yes" : "no"; exit }
  ' "$1"
}
sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0 o
  ok() { [ -n "$q" ] || echo "PASS  $1"; }
  no() { [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); }
  # the catcher: the pass, then the masks; the observer still calls it; the pass's order as the test plays it
  o=$(fn "$X" 'static void DMA5CatchNewStages(void) {' | sed 1d)
  if [ "$o" = "$(printf '    DMA5CatchNewStagesPass();\n    DMA5MasksAtCommit();\n}')" ] && grep -qF '^(CFRunLoopObserverRef o, CFRunLoopActivity a) { DMA5CatchNewStages(); });' "$X" \
     && [ "$(grep -c 'DMA5MasksAtCommit();' "$X")" = 1 ]; then ok "StatusBar.x: DMA5CatchNewStages is the pass, then DMA5MasksAtCommit (its only call); the pre-commit observer calls it"
  else no "StatusBar.x: DMA5CatchNewStages is not the pass then the masks"; fi
  o=$(fn "$X" 'static void DMA5CatchNewStagesPass(void) {')
  if [ "$(echo "$o" | sed -n 2p)" = "    DMA5WakeFrameWatcher();" ] && [ "$(echo "$o" | grep -n 'DMA5HoldEntranceFrame(st);' | cut -d: -f1)" -lt "$(echo "$o" | grep -n 'else DMA5AnswerFitPass(st, now);' | cut -d: -f1)" ] 2>/dev/null; then
    ok "StatusBar.x: the pass runs the paused watcher's pass first, then the entrance holds, then the fit-pass answers (the order the test plays)"
  else no "StatusBar.x: the pass's order is not the one the test plays"; fi
  # the put-backs bring the mask (one helper), guarded by Aerial 5's geometry; the commit pass starts with that guard
  if fn "$X" 'static void DMStagePutBack(UIView *stage, CGRect frame) {' | grep -qF '    if (DMA5MacGeometry() && !DMA5MaskOld()) DMA5SyncHostMaskBy(stage, "the put-back");' \
     && fn "$X" 'static void DMEnforceStageFrame(UIView *stage, NSString *why) {' | grep -qF '    DMStagePutBack(stage, vis);' && ! fn "$X" 'static void DMEnforceStageFrame(UIView *stage, NSString *why) {' | grep -q performWithoutAnimation \
     && fn "$X" 'static void DMA5HoldEntranceFrame(UIView *stage) {' | grep -qF '    DMStagePutBack(stage, want);' && ! fn "$X" 'static void DMA5HoldEntranceFrame(UIView *stage) {' | grep -q performWithoutAnimation \
     && [ "$(grep -c 'DMStagePutBack(' "$X")" = 3 ]; then ok "StatusBar.x: DMEnforceStageFrame and DMA5HoldEntranceFrame put back through DMStagePutBack (mask synced, Aerial 5 only), nothing else does"
  else no "StatusBar.x: the put-backs do not go through DMStagePutBack as the test plays it"; fi
  [ "$(fn "$X" 'static void DMA5MasksAtCommit(void) {' | sed -n 2p)" = "    if (!DMA5MacGeometry() || gDMScreenOff || !gA5StageCache.count) return;" ] \
    && ok "StatusBar.x: DMA5MasksAtCommit starts with the DMA5MacGeometry guard (Aerial 3.0, Zetsu, MilkyWay4, Stage Manager: nothing)" || no "StatusBar.x: DMA5MasksAtCommit's guard"
  # the catcher is installed only for Aerial 5 (DMAerial5Watch, after its check)
  o=$(fn "$X" 'static void DMAerial5Watch(void) {')
  if [ "$(grep -c 'DMA5InstallCatcher();' "$X")" = 1 ] && [ "$(echo "$o" | sed -n 2p)" = "    if (gAerialFlavor != 5 || DMActiveEngine() != DMEngineAerial) { gA5CatchOn = NO; return; }" ] && echo "$o" | grep -qF '    DMA5InstallCatcher();'; then
    ok "StatusBar.x: the pre-commit catcher is installed only by DMAerial5Watch, after its Aerial 5 check"
  else no "StatusBar.x: the catcher is installed elsewhere"; fi
  # nothing on Finder's, the native windows' or the keyboard hand-over's path: byte for byte as in 1.8.7.8 (7e0589ee)
  if [ "$(shasum < ../statusbar/NativeWindow.h | cut -c1-16)" = 0bff62e6405d99da ] && [ "$(shasum < ../statusbar/Finder.h | cut -c1-16)" = 6fdf816e0e533b8a ] \
     && [ "$(shasum < ../statusbar/KeyboardBehind.h | cut -c1-16)" = 38db8b74b23dde3c ]; then ok "NativeWindow.h, Finder.h, KeyboardBehind.h as in 1.8.7.8 (no focus, key window or level change)"
  else no "NativeWindow.h, Finder.h or KeyboardBehind.h changed"; fi
  # the trace and the kill switch are debug only
  [ "$(ifdebug "$X" 'return DMTestFlag("/tmp/msb-a5-maskold");')" = yes ] && [ "$(ifdebug "$X" 'static void DMA5MaskDebugAtCommit(void) {')" = yes ] && [ "$(ifdebug "$X" 'static void DMA5MaskTrace(UIView *stage, CGSize was, CGSize now) {')" = yes ] \
    && [ "$(ifdebug "$X" 'static void DMA5MaskCost(double spent, BOOL handler) {')" = yes ] && ok "StatusBar.x: the kill switch /tmp/msb-a5-maskold and the [a5mask] trace are inside #if DEBUG" || no "StatusBar.x: the kill switch or the trace is not debug only"
  return $n
}

run() {   # $1 StatusBar.x, $2 dir, $3 quiet, $4 debug values: the number of checks that fail
  local q=$3 n=0 out r dbg
  build "$1" "$2" "$q" "$4"; r=$?; [ $r = 99 ] && return 99; n=$r
  for dbg in $4; do
    [ -n "$q" ] || echo "-- $([ $dbg = 1 ] && echo DEBUG || echo release)"
    out=$("$2/t-$dbg" 2>/dev/null); r=$?
    out2=$("$2/t-$dbg" T15 2>/dev/null); r2=$?; out="$out"$'\n'"$out2"; [ $r2 != 0 ] && r=$r2
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((r - 128))"; }
    n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$q"; n=$((n + $?)); [ $n -ge 99 ] && n=98
  return $n
}

run "$S0" "$W/real" "" "0 1"; rc=$?
[ $rc = 0 ] && echo "test-a5maskcommit: all pass" || echo "test-a5maskcommit: FAILED ($rc check(s))"
if [ -z "$A5M_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression (StatusBar.x, the whole file at once)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"
    perl -0777 -pe "$2" "$S0" > "$c"
    cmp -s "$c" "$S0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    build "$c" "$d/w" q "1" >/dev/null; local b=$?
    [ $b = 99 ] && { echo "FAIL  made-to-fail copy \"$1\": did not build"; rc=1; return; }
    local out; out=$("$d/w/t-1" 2>/dev/null; "$d/w/t-1" T15 2>/dev/null); local n=$(echo "$out" | grep -c '^FAIL')
    if [ "$n" -gt 0 ]; then echo "PASS  caught: $1 ($(echo "$out" | grep '^FAIL' | sed -E 's/^FAIL  (T[0-9]+).*/\1/' | sort -u | tr '\n' ' '))"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "a put-back without the mask (a)" 's/\n    if \(DMA5MacGeometry\(\) && !DMA5MaskOld\(\)\) DMA5SyncHostMaskBy\(stage, "the put-back"\);//'
  mtf "no mask set at the end of the pass" 's/\n        if \(DMA5MaskStale\(st\)\) DMA5SyncHostMaskBy\(st, "the end of the pass before the commit"\);//'
  mtf "no handler after the commit's layout" 's/        \(\(void \(\*\)\(id, SEL, id, int\)\)objc_msgSend\)\(\[CATransaction class\], NSSelectorFromString\(\@"addCommitHandler:forPhase:"\), afterLayout, 1\);[^\n]*\n//'
  mtf "the layout check never true" 's/layoutLater = v\.layer\.needsLayout;/layoutLater = NO;/'
  mtf "the layout check always true (a handler every turn)" 's/layoutLater = v\.layer\.needsLayout;/layoutLater = YES;/'
  mtf "the commit pass without the DMA5MacGeometry guard" 's/    if \(!DMA5MacGeometry\(\) \|\| gDMScreenOff \|\| !gA5StageCache\.count\) return;/    if (gDMScreenOff || !gA5StageCache.count) return;/'
  mtf "the debug kill switch not read" 's/    return DMTestFlag\("\/tmp\/msb-a5-maskold"\);/    return NO;/'
  mtf "1.8.7.8's order (no mask at the put-back, none at the commit)" 's/\n    if \(DMA5MacGeometry\(\) && !DMA5MaskOld\(\)\) DMA5SyncHostMaskBy\(stage, "the put-back"\);//; s/    DMA5CatchNewStagesPass\(\);\n    DMA5MasksAtCommit\(\);/    DMA5CatchNewStagesPass();/'
  # (1.8.8 H2 row 3 on Aerial 5.1: the fit-pass answer counts only what it put back)
  mtf "p07's count (every answer counted, a minimized window's too)" 's/    CGRect was = stage\.frame;\n(    DMEnforceStageFrame\(stage, \@"Aerial 5.s fit-to-screen pass, before it is drawn"\);\n)    if \(CGRectEqualToRect\(stage\.frame, was\)\) return;[^\n]*\n(    \[times addObject:\@\(now\)\];\n)/$2$1/'
  mtf "no count at all (a fight on screen never left to Aerial)" 's/(no fight to count\)\n)    \[times addObject:\@\(now\)\];\n/$1/'
fi
exit $rc
