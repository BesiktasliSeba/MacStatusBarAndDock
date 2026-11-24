#!/bin/bash
# test-a5cornerclip.sh: Aerial 5's app corners are a clip on the app's picture, not a mask on its holder (1.8.8.4, plans/efficiency.md) -- see
# test-a5cornerclip.m. The real code is cut out of statusbar/StatusBar.x (ACC_SB_X: another copy, e.g. 1.8.8.3's, where the clip is missing) and run
# on the Mac (Mac Catalyst) with real Core Animation commits, in a release and a DEBUG build; then the site checks; then made-to-fail copies, each
# must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
S0=${ACC_SB_X:-../statusbar/StatusBar.x}
fn() {   # $1 file, $2 first line: one function, by its braces
  awk -v s="$2" '!f && index($0, s) == 1 { f = 1 } f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }' "$1"
}
span() {   # $1 file, $2 first line, $3 the first line of the function that ends it: from $2 to the end of that function
  awk -v s="$2" -v e="$3" '!f && index($0, s) == 1 { f = 1 } f && !g && index($0, e) == 1 { g = 1 } f { print } g { t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }' "$1"
}
build() {   # $1 StatusBar.x, $2 dir, $3 quiet, $4 debug values: the test built on that code
  local X=$1 d=$2 dbg
  mkdir -p "$d"
  { echo '#if DEBUG'; echo 'static CADisplayLink *gA5FrameLink;'; echo '#endif'
    fn "$X" 'static UIView *DMStageInnerView(UIView *stage) {'
    span "$X" 'static const void *kA5MaskKey = &kA5MaskKey;' 'static void DMA5SyncHostMaskFor(UIView *stage, UIView *holder) {'
    echo '#if DEBUG'; fn "$X" 'static void DMA5MaskTrace(UIView *stage, CGSize was, CGSize now) {'; echo '#endif'
    fn "$X" 'static BOOL DMA5MaskStale(UIView *stage) {'; } > "$d/one-corners.inc"
  grep -q 'gA5MaskBy' "$d/one-corners.inc" || { echo '#if DEBUG'; echo 'static const char *gA5MaskBy;   // (not in this source)'; echo '#endif'; } >> "$d/one-corners.inc"
  grep -q '^static void DMA5SyncHostMaskFor(UIView \*stage, UIView \*holder) {' "$d/one-corners.inc" && grep -q 'static UIView \*DMStageInnerView' "$d/one-corners.inc" && grep -q '^static BOOL DMA5MaskStale' "$d/one-corners.inc" \
    || { echo "FAIL  the code was not found in $X"; return 99; }
  for dbg in $4; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" -DDEBUG=$dbg \
          -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/t-$dbg" test-a5cornerclip.m 2> "$d/cc-$dbg.txt" || { [ -n "$3" ] || cat "$d/cc-$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
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
  # the corner resize's held picture rounds its own corners (it sits in the holder, which carries no mask any more)
  fn "$X" 'static void DMA5PictureEnd(UIView *stage) {' | grep -qF '        if (DMA5HolderClipped(in)) DMA5RoundBottom(box.layer);' \
    && ok "StatusBar.x: the corner resize's held picture rounds its bottom corners as the app's picture does" || no "StatusBar.x: the held picture's corners"
  # Aerial's own radius on the holder stays disarmed (theme 3b, the young window)
  fn "$X" 'static void DMAerial5Theme(UIView *stage) {' | grep -qF '    if (in0 && !minimized && in0.layer.maskedCorners != 0) in0.layer.maskedCorners = 0;' \
    && fn "$X" 'static void DMA5FixYoungStage(UIView *stage) {' | grep -qF 'h.layer.maskedCorners = 0;' \
    && ok "StatusBar.x: Aerial's own 30 pt radius on the holder stays disarmed (theme 3b, the young window)" || no "StatusBar.x: Aerial's radius not disarmed"
  # the commit pass walks the views above every shown window for pending layout, a clipped one's too: Aerial's layout in the commit can move or add
  # its app's picture or fill its holder, and the pre-commit handler then puts the mask back before that commit is drawn (test-a5maskcommit T22-T24)
  fn "$X" 'static void DMA5MasksAtCommit(void) {' | grep -qF '        for (UIView *v = st; v && !layoutLater; v = v.superview) layoutLater = v.layer.needsLayout;' \
    && ! fn "$X" 'static void DMA5MasksAtCommit(void) {' | grep -q 'DMA5HolderMasked' \
    && ok "StatusBar.x: the commit pass looks for pending layout above every shown window, a clipped one's too" || no "StatusBar.x: the commit pass's layout look skips clipped windows"
  # the A/B switch is debug only
  [ "$(ifdebug "$X" 'return DMTestFlag("/tmp/msb-a5-cornermask");')" = yes ] && ok "StatusBar.x: /tmp/msb-a5-cornermask is inside #if DEBUG" || no "StatusBar.x: the A/B switch is not debug only"
  return $n
}
run() {   # $1 StatusBar.x, $2 dir, $3 quiet, $4 debug values: the number of checks that fail
  local q=$3 n=0 out r dbg
  build "$1" "$2" "$q" "$4"; r=$?; [ $r = 99 ] && return 99; n=$r
  for dbg in $4; do
    [ -n "$q" ] || echo "-- $([ $dbg = 1 ] && echo DEBUG || echo release)"
    out=$("$2/t-$dbg" 2>/dev/null); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((r - 128))"; }
    n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$q"; n=$((n + $?)); [ $n -ge 99 ] && n=98
  return $n
}
run "$S0" "$W/real" "" "0 1"; rc=$?
[ $rc = 0 ] && echo "test-a5cornerclip: all pass" || echo "test-a5cornerclip: FAILED ($rc check(s))"
if [ -z "$ACC_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression (StatusBar.x, the whole file at once)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"
    perl -0777 -pe "$2" "$S0" > "$c"
    cmp -s "$c" "$S0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    build "$c" "$d/w" q "1" >/dev/null; local b=$?
    [ $b = 99 ] && { echo "FAIL  made-to-fail copy \"$1\": did not build"; rc=1; return; }
    local out; out=$("$d/w/t-1" 2>/dev/null); local n=$(echo "$out" | grep -c '^FAIL')
    if [ "$n" -gt 0 ]; then echo "PASS  caught: $1 ($(echo "$out" | grep '^FAIL' | sed -E 's/^FAIL  (C[0-9]+).*/\1/' | sort -u | tr '\n' ' '))"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the clip's curve circular" 's/l\.cornerCurve = kCACornerCurveContinuous; l\.maskedCorners = kA5BottomCorners; \}/l.cornerCurve = kCACornerCurveCircular; l.maskedCorners = kA5BottomCorners; }/'
  mtf "all four corners rounded" 's/static const CACornerMask kA5BottomCorners = kCALayerMinXMaxYCorner \| kCALayerMaxXMaxYCorner;/static const CACornerMask kA5BottomCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner | kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;/'
  mtf "Aerial's 30 pt radius" 's/static void DMA5RoundBottom\(CALayer \*l\) \{ l\.cornerRadius = kMilkyWayCorner;/static void DMA5RoundBottom(CALayer *l) { l.cornerRadius = 30.0;/'
  mtf "the picture not clipped (masksToBounds off)" 's/DMA5RoundBottom\(host\.layer\); host\.layer\.masksToBounds = YES;/DMA5RoundBottom(host.layer); host.layer.masksToBounds = NO;/'
  mtf "the holder keeps its fill (square corners in the base colour)" 's/    if \(filled\) in\.backgroundColor = nil;\n//'
  mtf "the picture without the fill" 's/host\.layer\.masksToBounds = YES; host\.backgroundColor = fill;/host.layer.masksToBounds = YES;/'
  mtf "our mask left on the holder" 's/    if \(masked\) in\.layer\.mask = nil;\n//'
  mtf "the young holder without the mask (no picture yet: no corners)" 's/    DMA5UnclipHosts\(in\);\n/    DMA5UnclipHosts(in); return;\n/'
  mtf "the mask kept as in 1.8.8.3 (no clip at all)" 's/    if \(host\) \{ DMA5ClipHosts\(stage, in, host\); return; \}[^\n]*\n//'
  mtf "two pictures clipped (no mask for them)" 's/\{ if \(host\) return nil; host = v; \}/{ host = v; }/'
  mtf "a picture laid out off the holder's bounds clipped" 's/    if \(fabs\(f\.origin\.x - b\.origin\.x\) > 0\.01 [^\n]*return nil;\n//'
  mtf "a held picture left square" 's/    for \(UIView \*v in in\.subviews\) if \(DMA5IsHeldPicture\(v\) && !DMA5BottomRounded\(v\.layer\)\) DMA5RoundBottom\(v\.layer\);\n//'
  mtf "a clipped holder not seen as stale when it becomes the mask's" 's/    if \(in && DMA5HolderClipped\(in\)\) return YES;[^\n]*\n//'
  mtf "the A/B switch back to the mask leaves the picture clipped" 's/    if \(!objc_getAssociatedObject\(in, kA5ClipKey\)\) return;\n    \[CATransaction begin\];/    return;\n    [CATransaction begin];/'
fi
exit $rc
