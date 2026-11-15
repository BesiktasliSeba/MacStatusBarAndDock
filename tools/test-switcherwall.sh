#!/bin/bash
# test-switcherwall.sh: the Mac Switcher shows the desktop the user sees (1.8.7.5 SWITCHERWALL, seen on the 17.5 on 15 Nov: with our Desktop
# Picture on, the switcher's background and Desktop 1's thumbnail showed iPadOS's wallpaper while the Home Screen showed ours; and the M1's gap
# in 1.8.7.5~a01: another picture of ours chosen while the switcher was open left the picture before as its background until it was opened
# again, scenario openchangedlate; and SWTHUMBS, the iPad 2's check of a01 and the M1: with the switcher open the other desktops' thumbnails kept
# the picture before, also after None, and a picture chosen from None left iPadOS's wallpaper as its background, until it was opened again,
# scenarios openthumbs, openfromnone, closedthumbs, closednoviews, othershape). See
# test-switcherwall.m. The real code is cut out of statusbar/MacSwitcher.h (SW_MSW_H) and statusbar/DesktopWallpaper.h (SW_WP_H: another copy,
# e.g. the code before the fix, which has no DMWPDesktopPictureView) and run on the Mac (Mac Catalyst); then site checks (also on
# statusbar/MacSwitcherSM.h, SW_SM_H); then made-to-fail copies, each must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${SW_MSW_H:-../statusbar/MacSwitcher.h}; D0=${SW_WP_H:-../statusbar/DesktopWallpaper.h}; S0=${SW_SM_H:-../statusbar/MacSwitcherSM.h}; X0=../statusbar/StatusBar.x
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; next } f { print } f && /^[}]/ { exit }' "$1"; }   # one function, by its first line

build() {   # $1 MacSwitcher.h, $2 DesktopWallpaper.h, $3 dir, $4 quiet
  local M=$1 D=$2 d=$3 q=$4
  mkdir -p "$d"
  fn "$D" 'static UIImageView *DMWPDesktopPictureView(void) {' > "$d/sw-wp.inc"
  [ -s "$d/sw-wp.inc" ] || { [ -n "$q" ] || echo "   (no DMWPDesktopPictureView: the code before the fix)"; }
  {
    awk 'index($0, "static NSInteger DMMSWTurnKey(void);") == 1 { f = 1 } index($0, "static UIView *DMMSWWallpaperImageView(UIView *wall);") == 1 { exit } f { print }' "$M"
    fn "$M" 'static UIView *DMMSWWallpaperImageView(UIView *wall) {'
    fn "$M" 'static UIImage *DMMSWWallImage(UIView *wall) {'
    fn "$M" 'static UIView *DMMSWWallpaperBackground(UIView *root, NSString **why) {'
    fn "$M" 'static void DMMSWWallLazy(void) {'
    fn "$M" 'static void DMMSWOurWallChanged(void) {'
  } > "$d/sw-real.inc"
  {   # the code before the fix: what it does not have, as it was (nothing let go when our picture changes)
    grep -q 'static void DMMSWOurWallChanged(void) {' "$d/sw-real.inc" || echo 'static void DMMSWOurWallChanged(void) {}'
    grep -q 'gMSWBackWall;' "$d/sw-real.inc" || echo 'static __weak UIView *gMSWBackWall;'
  } > "$d/sw-compat.inc"
  [ -s "$d/sw-compat.inc" ] && [ -z "$q" ] && echo "   (the code before the fix: $(wc -l < "$d/sw-compat.inc" | tr -d ' ') part(s) as before)"
  {   # the code before SWTHUMBS: no DMMSWWallView -- its places made the view as here, with their own copy of the picture, nothing remembered
    grep -qF 'static UIView *DMMSWWallView(UIView *into, BOOL tile) {' "$d/sw-real.inc" || cat <<'EOC'
static UIView *DMMSWWallView(UIView *into, BOOL tile) {
    if (!gMSWWallContents) return nil;
    UIView *wv = [[UIView alloc] initWithFrame:tile ? into.bounds : CGRectZero];
    if (tile) { wv.layer.contents = gMSWWallContents; wv.layer.contentsRect = gMSWWallContentsRect; wv.layer.contentsGravity = kCAGravityResizeAspectFill; }
    else { DMMSWApplyWall(wv.layer); wv.bounds = gMSWWallBounds; wv.center = gMSWWallCenter; wv.transform = gMSWWallTransform; }
    [into addSubview:wv];
    return wv;
}
EOC
  } > "$d/sw-compat2.inc"
  [ -s "$d/sw-compat2.inc" ] && [ -z "$q" ] && echo "   (the code before SWTHUMBS: the views made as its places made them, nothing remembered)"
  grep -q 'static id gMSWWallContents;' "$d/sw-real.inc" && grep -q 'DMMSWWallLazy' "$d/sw-real.inc" && grep -q 'DMMSWWallpaperBackground' "$d/sw-real.inc" || { echo "FAIL  the switcher's wallpaper code was not found in $M"; return 99; }
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/t" test-switcherwall.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  return 0
}

sites() {   # $1 MacSwitcher.h, $2 DesktopWallpaper.h, $3 quiet, $4 MacSwitcherSM.h: the number of site checks that fail
  local M=$1 D=$2 q=$3 S=$4 n=0 o
  # every reader of the wallpaper takes ours first: the two places that read iPadOS's view, and nothing else reads it
  if [ "$(grep -c 'DMMSWWallpaperView()' "$M")" = "$(grep -c '?: DMMSWWallpaperView()' "$M")" ] && fn "$M" 'static UIView *DMMSWWallpaperBackground(UIView *root, NSString **why) {' | grep -qF 'UIView *wall = ours ?: DMMSWWallpaperView();' \
     && fn "$M" 'static void DMMSWWallLazy(void) {' | grep -qF 'UIView *wall = DMWPDesktopPictureView() ?: DMMSWWallpaperView();' \
     && ! grep -q 'DMMSWWallpaperView()' "$S" ../statusbar/MacSwitcherButton.h "$X0"; then
    [ -n "$q" ] || echo "PASS  MacSwitcher.h: every reader of the wallpaper (the background, the desktops drawn from their parts, the debug read-out) takes our Desktop Picture first"
  else [ -n "$q" ] || echo "FAIL  MacSwitcher.h: a reader of the wallpaper does not take our Desktop Picture first"; n=$((n + 1)); fi
  # our picture changed or gone: the switcher told at each place its picture changes (decoded, unreadable, removed); the open switcher's background
  # is the one DMMSWBuildRoot takes (it is taken again there)
  if [ "$(grep -c 'DMMSWOurWallChanged();' "$D")" = 3 ] && fn "$D" 'static void DMWPRemove(NSString *why) {' | grep -qF '    DMMSWOurWallChanged();' \
     && fn "$M" 'static UIView *DMMSWBuildRoot(void) {' | grep -A2 -F 'UIView *wall = DMMSWIsMain() ? DMMSWWallpaperBackground(root, &why) : nil;' | grep -qF '    gMSWBackWall = wall;'; then
    [ -n "$q" ] || echo "PASS  DesktopWallpaper.h tells the switcher at each change of our picture (decoded, unreadable, None); MacSwitcher.h keeps the open background's picture"
  else [ -n "$q" ] || echo "FAIL  the switcher is not told of every change of our picture, or the open background is not kept"; n=$((n + 1)); fi
  # every view given the picture besides the background is made by DMMSWWallView (remembered: a change of ours reaches it at once): the desktops
  # drawn from their parts on every engine (the strip's, kept, a slide's), the desktop on the screen drawn from its parts, the strip's tile of a
  # desktop showing only its wallpaper; no layer is given the picture anywhere else (DMMSWApplyWall: the background and DMMSWWallPlace)
  if fn "$M" 'static UIView *DMMSWComposedDesktop(NSInteger did, CGRect b) {' | grep -qF 'DMMSWWallView(c, NO);' \
     && fn "$M" 'static UIView *DMMSWDeskPicture(NSUInteger i, CGRect b) {' | grep -qF 'DMMSWWallView(c, NO);' \
     && fn "$M" 'static UIView *DMMSWLeftFromParts(UIView *fsPic, UIView *fsSrc) {' | grep -qF 'DMMSWWallView(c, NO);' \
     && fn "$M" 'static UIView *DMMSWBuildStrip(UIView *root, CGRect b) {' | grep -qF 'DMMSWWallView(clip, YES);' \
     && fn "$S" 'static UIView *DMMSWSMComposedDesktop(NSInteger did, CGRect b) {' | grep -qF 'DMMSWWallView(c, NO);' \
     && [ "$(cat "$M" "$S" | grep -c 'contents = gMSWWallContents')" = 2 ] && [ "$(cat "$M" "$S" | grep -c 'DMMSWApplyWall(')" = 3 ]; then
    [ -n "$q" ] || echo "PASS  MacSwitcher.h / MacSwitcherSM.h: every desktop drawn from its parts (every engine) and the strip's wallpaper tile take the picture through DMMSWWallView, nothing else gives it to a layer"
  else [ -n "$q" ] || echo "FAIL  a view is given the wallpaper's picture outside DMMSWWallView (it would keep the picture before when ours changes)"; n=$((n + 1)); fi
  # DesktopWallpaper.h comes before MacSwitcher.h in StatusBar.x (its view is asked for there)
  if awk 'index($0, "#include \"DesktopWallpaper.h\"") == 1 {d = NR} index($0, "#include \"MacSwitcher.h\"") == 1 {m = NR} END {exit !(d && m > d)}' "$X0"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DesktopWallpaper.h is included before MacSwitcher.h"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DesktopWallpaper.h is not included before MacSwitcher.h"; n=$((n + 1)); fi
  # the crash map: the switcher's new function is the Mac Switcher's, the picture's the Desktop Picture's
  o=$(python3 -I - crashmap-rules.txt <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'sw'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
print(g['classify']('MacStatusBarCore', '_DMMSWWallImage', 'MacSwitcher.h', '', rules, im, hits), g['classify']('MacStatusBarCore', '_DMWPDesktopPictureView', 'DesktopWallpaper.h', '', rules, im, hits), g['classify']('MacStatusBarCore', '_DMMSWOurWallChanged', 'MacSwitcher.h', '', rules, im, hits),
      g['classify']('MacStatusBarCore', '_DMMSWWallView', 'MacSwitcher.h', '', rules, im, hits), g['classify']('MacStatusBarCore', '_DMMSWWallPlace', 'MacSwitcher.h', '', rules, im, hits))
EOF
)
  if [ "$o" = "macSwitcher desktopWallpaper macSwitcher macSwitcher macSwitcher" ]; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: DMMSWWallImage, DMMSWWallView and DMMSWWallPlace are the Mac Switcher's, DMWPDesktopPictureView the Desktop Picture's (classified with make-crashmap.py's own code)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the new functions classify as: $o"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 MacSwitcher.h, $2 DesktopWallpaper.h, $3 dir, $4 quiet, $5 MacSwitcherSM.h: the number of checks that fail (99: not built)
  local q=$4 n=0 s out r
  build "$1" "$2" "$3" "$q"; r=$?; [ $r = 99 ] && return 99; n=$r
  for s in $("$3/t" list); do
    [ -n "$q" ] || echo "-- $s"
    out=$("$3/t" "$s" 2>/dev/null); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; }
    n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$2" "$q" "$5"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$M0" "$D0" "$W/real" "" "$S0"; rc=$?
[ $rc = 0 ] && echo "test-switcherwall: all pass" || echo "test-switcherwall: FAILED ($rc check(s))"
if [ -z "$SW_MSW_H$SW_WP_H$SW_SM_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 which file (m: MacSwitcher.h, d: DesktopWallpaper.h, s: MacSwitcherSM.h), $3 perl expression on it (the whole file at once)
    local d="$W/m$((++k))" c m=$M0 dd=$D0 ss=$S0 src
    mkdir -p "$d"
    case $2 in m) src=$M0; c="$d/MacSwitcher.h"; m=$c;; d) src=$D0; c="$d/DesktopWallpaper.h"; dd=$c;; s) src=$S0; c="$d/MacSwitcherSM.h"; ss=$c;; esac
    perl -0777 -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$m" "$dd" "$d/w" q "$ss"; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  mtf "the background reads iPadOS's wallpaper only (as before)" m 's/UIImageView \*ours = DMWPDesktopPictureView\(\);/UIImageView *ours = nil;/'
  mtf "the desktops drawn from their parts read iPadOS's only" m 's/UIView \*wall = DMWPDesktopPictureView\(\) \?: DMMSWWallpaperView\(\);/UIView *wall = DMMSWWallpaperView();/'
  mtf "ours found, but a picture looked for inside it (not taken as shown)" m 's/UIView \*iv = ours \?: DMMSWWallpaperImageView\(wall\);/UIView *iv = DMMSWWallpaperImageView(wall);/'
  mtf "the fill takes iPadOS's view's picture" m 's/    if \(wall && wall == DMWPDesktopPictureView\(\)\) return \(\(UIImageView \*\)wall\)\.image;\n//'
  mtf "the key without the picture (another picture of ours not taken again)" m 's/\(__bridge void \*\)shown, NSStringFromCGSize\(b\.size\)/(void *)NULL, NSStringFromCGSize(b.size)/'
  mtf "ours read from its view's layer, as before (the M1's gap: the picture before while open)" m 's/id shown = ours \? \(__bridge id\)ours\.image\.CGImage : iv\.layer\.contents;/id shown = iv.layer.contents;/'
  mtf "ours placed as shown with its view's layer's picture" m 's/gMSWWallContents = shown; gMSWWallBounds = ib;/gMSWWallContents = iv.layer.contents; gMSWWallBounds = ib;/'
  mtf "our view taken before its picture is decoded" d 's/return p\.image\.CGImage && p\.window/return p.window/'
  mtf "our view taken out of its place" d 's/ && p\.superview == gWPHost \? p : nil;/ ? p : nil;/'
  mtf "our picture's copy not let go when it changes" m 's/    gMSWWallContents = nil; gMSWWallKey = nil; gMSWWallOurs = NO;\n/    gMSWWallOurs = NO;\n/'
  mtf "the open switcher's background not taken again" m 's/        \[old.superview insertSubview:wall aboveSubview:old\];\n        \[old removeFromSuperview\];\n/        [wall removeFromSuperview];\n/'
  mtf "a desktop drawn from its parts does not mark ours" m 's/    gMSWWallOurs = wall && wall == DMWPDesktopPictureView\(\);/    gMSWWallOurs = NO;/'
  mtf "iPadOS's picture let go as if ours" m 's/    if \(!wasOurs && !DMWPDesktopPictureView\(\)\) return;[^\n]*\n//'
  mtf "a picture chosen from None not acted on, only a copy of ours (as before SWTHUMBS)" m 's/if \(!wasOurs && !DMWPDesktopPictureView\(\)\) return;/if (!wasOurs) return;/'
  mtf "the views given the picture not remembered" m 's/    \[gMSWWallViews addObject:wv\];\n//'
  mtf "the views remembered not given the picture taken now" m 's/\{ DMMSWWallPlace\(wv\); n\+\+; \}/{ n++; }/'
  mtf "the switcher closed: no picture taken for the views showing it" m 's/    if \(views\.count && !gMSWWallContents\) DMMSWWallLazy\(\);[^\n]*\n//'
  mtf "a strip tile given the picture placed as on the screen (not filling its tile)" m 's/    if \(tile\) objc_setAssociatedObject\(wv, kMSWWallTileKey, \@YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);\n//'
  mtf "iPadOS 17's poster's turn left on ours" m 's/if \(\[t isKindOfClass:\[NSValue class\]\] && !CGAffineTransformIsIdentity\(\[t CGAffineTransformValue\]\)\) \[l setValue:\[NSValue valueWithCGAffineTransform:CGAffineTransformIdentity\] forKey:\@"contentsTransform"\];//'
  mtf "a desktop picture of the other shape not covered" m 's/MAX\(box\.width \/ w\.width, box\.height \/ w\.height\) : 1\.0;/1.0 : 1.0;/'
  mtf "Stage Manager's desktops drawn from their parts given the picture by hand (as before)" s 's/        DMMSWWallView\(c, NO\);   \/\/ \(the wallpaper as the other engines/        if (gMSWWallContents) { UIView *wv = [UIView new]; wv.layer.contents = gMSWWallContents; wv.bounds = gMSWWallBounds; [c addSubview:wv]; }   \/\/ (the wallpaper as the other engines/'
  mtf "the strip's wallpaper tile given the picture by hand (as before)" m 's/\} else DMMSWWallView\(clip, YES\);/} else if (gMSWWallContents) { UIView *wv = [[UIView alloc] initWithFrame:clip.bounds]; wv.layer.contents = gMSWWallContents; [clip addSubview:wv]; }/'
  mtf "the switcher not told at a decode" d 's/                    if \(q == gWPPlane\) DMMSWOurWallChanged\(\);\n//'
  mtf "the switcher not told at None" d 's/    gWPHostNote = nil;\n    DMMSWOurWallChanged\(\);/    gWPHostNote = nil;/'
  mtf "the debug read-out names iPadOS's view only" m 's/UIView \*wall = ours \?: DMMSWWallpaperView\(\), \*iv = ours \?: /UIView *wall = DMMSWWallpaperView(), *iv = /'
fi
exit $rc
