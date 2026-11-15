#!/bin/bash
# test-macfolder.sh: Finder's folders are the desktop's macOS folder (1.8.7.4 round 2, KT 14 Nov) -- see test-macfolder.m. Finder drew iPadOS's
# folder.fill symbol (a clear line across the top, between the tab and the front); now its folders, an app's folder in On My iPad (with the
# app's icon on it) and a package it shows as a folder are the picture the desktop draws (statusbar/MacFolder.h, moved out of Desktop.h), at
# the icon's side and the screen's scale, once per side. The real code is cut out of statusbar/MacFolder.h (Desktop.h before the move),
# Finder.h and Desktop.h (MF_FOLDER_H / MF_FINDER_H / MF_DESKTOP_H / MF_SB_X / MF_RULES: other copies, e.g. the code before the change) and run
# on the Mac (Mac Catalyst), one scenario per process; then site checks; then made-to-fail copies: each takes one part of the change out and
# must fail. MF_REF_FINDER_H / MF_REF_DESKTOP_H (the code before the change): every other kind of item keeps its picture, and the desktop's
# folders are the pictures they were, pixel for pixel. MF_PICTURES=<dir>: Finder's folder and an app's folder as PNGs (16, 32, 64 pt, 2x).
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
P0=${MF_FOLDER_H:-../statusbar/MacFolder.h}; F0=${MF_FINDER_H:-../statusbar/Finder.h}; D0=${MF_DESKTOP_H:-../statusbar/Desktop.h}
X0=${MF_SB_X:-../statusbar/StatusBar.x}; R0=${MF_RULES:-crashmap-rules.txt}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }    # one function of a file, from its first line
fnst() { awk -v n="$2(" 'index($0, "static ") == 1 && index($0, n) {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # ... a static one by its name
F_FN=('static UIImage *DMFinderAppIcon(DMFinderItem *it, CGFloat side) {' 'static UIImage *DMFinderFolderPicture(CGFloat side) {' 'static UIImage *DMFinderIcon(DMFinderItem *it, CGFloat side) {')
D_M='- (UIImage *)dm_folderImage {'
PAINT_FILL='^static void DMDesktopFolderFill\(' PAINT_DRAW='^static .*void DMDesktopDrawFolder\('
painter() { local f; for f in "$@"; do [ -f "$f" ] && [ -n "$(fnst "$f" DMDesktopDrawFolder)" ] && { fnst "$f" DMDesktopFolderFill; fnst "$f" DMDesktopDrawFolder; return 0; }; done; return 1; }

sites() {   # $1 MacFolder.h, $2 Finder.h, $3 Desktop.h, $4 StatusBar.x, $5 rules, $6 quiet: the number of site checks that fail
  local P=$1 F=$2 D=$3 X=$4 R=$5 q=$6 n=0 c others o body im ifi ide
  others=$(ls ../statusbar/*.h ../statusbar/*.x | grep -vE '/(MacFolder|Finder|Desktop)\.h$|/StatusBar\.x$')
  # no folder in Finder asks for iPadOS's folder.fill (nor anywhere else of ours)
  c=$(cat "$F" $others | grep -c '"folder\.fill"')
  if [ "$c" = 0 ]; then [ -n "$q" ] || echo "PASS  Finder.h (and every other file of the status bar) asks for no \"folder.fill\""
  else [ -n "$q" ] || echo "FAIL  \"folder.fill\" still asked for $c time(s) ($(grep -n '"folder\.fill"' "$F" | cut -d: -f1 | tr '\n' ' ')in Finder.h)"; n=$((n + 1)); fi
  # the painter: one, in MacFolder.h (moved, no copy) -- its colours written once in all of the status bar
  c=$( { [ -f "$P" ] && cat "$P"; cat "$F" "$D" "$X" $others; } | grep -cE "$PAINT_DRAW|$PAINT_FILL|0x41A2D6, 0x2F96D2, 0x007AC9|0x6CC9F6, 0x74CFFB")
  if [ -f "$P" ] && [ "$c" = 4 ] && [ "$(grep -cE "$PAINT_DRAW|$PAINT_FILL|0x41A2D6, 0x2F96D2, 0x007AC9|0x6CC9F6, 0x74CFFB" "$P")" = 4 ]; then
    [ -n "$q" ] || echo "PASS  the macOS folder is painted in one place, MacFolder.h (DMDesktopFolderFill, DMDesktopDrawFolder and their colours, once)"
  else [ -n "$q" ] || echo "FAIL  the painter is not once, in MacFolder.h ($c definition/colour line(s) in the status bar)"; n=$((n + 1)); fi
  # Finder's picture calls it; DMFinderIcon gives that picture to a folder and to an app's folder
  body=$(fn "$F" "${F_FN[2]}")
  if fn "$F" "${F_FN[1]}" | grep -q 'DMDesktopDrawFolder(ctx.CGContext, side)' && [ "$(echo "$body" | grep -c 'DMFinderFolderPicture(side)')" = 2 ]; then
    [ -n "$q" ] || echo "PASS  Finder.h: DMFinderFolderPicture draws MacFolder.h's folder; DMFinderIcon gives it to folders and to apps' folders"
  else [ -n "$q" ] || echo "FAIL  Finder.h: DMFinderIcon does not use DMFinderFolderPicture (MacFolder.h's folder) for folders and apps' folders"; n=$((n + 1)); fi
  # StatusBar.x: MacFolder.h before Finder.h and Desktop.h
  im=$(grep -n '^#include "MacFolder\.h"' "$X" | head -1 | cut -d: -f1); ifi=$(grep -n '^#include "Finder\.h"' "$X" | head -1 | cut -d: -f1); ide=$(grep -n '^#include "Desktop\.h"' "$X" | head -1 | cut -d: -f1)
  if [ -n "$im" ] && [ -n "$ifi" ] && [ -n "$ide" ] && [ "$im" -lt "$ifi" ] && [ "$im" -lt "$ide" ] && [ "$(grep -c '#include "MacFolder\.h"' "$X" ../statusbar/*.h | awk -F: '{s+=$2} END {print s}')" = 1 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x includes MacFolder.h once, before Finder.h and Desktop.h (lines $im, $ifi, $ide)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: MacFolder.h is not included once before Finder.h and Desktop.h ($im, $ifi, $ide)"; n=$((n + 1)); fi
  # the crash map: a crash in the painter is its caller's (transparent), Finder's picture is Finder's, the desktop's the desktop's; the painter
  # stays a function of its own, so the rule always matches one (make-crashmap.py stops a build whose rule matches none)
  o=$(python3 -I - "$R" <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'mf'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
for name, fname in [('_DMDesktopDrawFolder', 'MacFolder.h'), ('_DMDesktopFolderFill', 'MacFolder.h'), ('_DMFinderFolderPicture', 'Finder.h'),
                    ('___DMFinderFolderPicture_block_invoke', 'Finder.h'), ('_DMFinderFolderPicture.cold.1', 'Finder.h'), ('_DMFinderIcon', 'Finder.h'),
                    ('-[DMDesktop dm_folderImage]', 'Desktop.h'), ('___28-[DMDesktop dm_folderImage]_block_invoke', 'Desktop.h'), ('_DMDesktopAppCornerIcon', 'DesktopCorner.h')]:
    print(g['classify']('MacStatusBarCore', name, fname, '', rules, im, hits), end=' ')
EOF
)
  if [ "$o" = "transparent transparent finder finder finder finder desktopIcons desktopIcons desktopIcons " ] && [ -f "$P" ] && grep -qE '^static __attribute__\(\(noinline\)\) void DMDesktopDrawFolder\(' "$P"; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: the painter is passed over (its caller decides: Finder's picture Finder, the desktop's Desktop Icons); it stays out of line"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt / MacFolder.h: the painter's crashes are not its caller's, or it may be inlined away ($o)"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 MacFolder.h, $2 Finder.h, $3 Desktop.h, $4 StatusBar.x, $5 rules, $6 work dir, $7 quiet; failed checks (99: not built)
  local P=$1 F=$2 D=$3 X=$4 R=$5 d=$6 q=$7 h out n=0 s r defs="" scen
  mkdir -p "$d"
  painter "$P" "$D" > "$d/mf-painter.inc" || { echo "FAIL  no DMDesktopDrawFolder in $P or $D"; return 99; }
  for h in "${F_FN[0]}" "${F_FN[2]}"; do [ -n "$(fn "$F" "$h")" ] || { echo "FAIL  $F: no \"$h\""; return 99; }; done
  [ -n "$(fn "$D" "$D_M")" ] || { echo "FAIL  $D: no \"$D_M\""; return 99; }
  [ -n "$(fn "$F" "${F_FN[1]}")" ] || { [ -n "$q" ] || echo "   (no DMFinderFolderPicture: the code before the change)"; }
  for h in "${F_FN[@]}"; do fn "$F" "$h"; done > "$d/mf-finder.inc"
  fn "$D" "$D_M" > "$d/mf-desktop.inc"
  if [ -n "$MF_REF_FINDER_H" ]; then
    for h in "${F_FN[@]}"; do fn "$MF_REF_FINDER_H" "$h"; done | perl -pe 's/\b(DMFinderIcon|DMFinderAppIcon|DMFinderFolderPicture)\b/$1Ref/g' > "$d/mf-ref.inc"; defs="$defs -DMF_REF"
  fi
  if [ -n "$MF_REF_DESKTOP_H" ]; then
    painter "$MF_REF_DESKTOP_H" | perl -pe 's/\b(DMDesktopFolderFill|DMDesktopDrawFolder)\b/$1Ref/g' > "$d/mf-refpainter.inc" || { echo "FAIL  no painter in $MF_REF_DESKTOP_H"; return 99; }
    fn "$MF_REF_DESKTOP_H" "$D_M" | perl -pe 's/\bDMDesktopDrawFolder\b/DMDesktopDrawFolderRef/g' > "$d/mf-refdesktop.inc"; defs="$defs -DMF_REF_DESKTOP"
  fi
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" $defs \
        -framework UIKit -framework CoreGraphics -o "$d/t" test-macfolder.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; n=$((n + 1)); }
  scen=$("$d/t" list); [ -n "$MF_REF_FINDER_H" ] && scen="$scen ref"; [ -n "$MF_REF_DESKTOP_H" ] && scen="$scen refdesk"
  for s in $scen; do
    [ -n "$q" ] || echo "-- $s"
    out=$("$d/t" "$s" 2>/dev/null); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; r=1; }
    n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
  done
  if [ -n "$MF_PICTURES" ] && [ -z "$q" ]; then
    mkdir -p "$MF_PICTURES"
    for s in 16 32 64; do "$d/t" png $s "$MF_PICTURES/${MF_PICTURES_TAG:-finder-folder}-${s}pt@2x.png" && "$d/t" pngapp $s "$MF_PICTURES/${MF_PICTURES_TAG:-finder-folder}-app-${s}pt@2x.png"; done
    echo "   (pictures: $MF_PICTURES)"
  fi
  [ -n "$q" ] || echo "-- site checks"
  sites "$P" "$F" "$D" "$X" "$R" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$P0" "$F0" "$D0" "$X0" "$R0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-macfolder: all pass" || echo "test-macfolder: FAILED ($rc check(s))"
if [ -z "$MF_FOLDER_H$MF_FINDER_H$MF_DESKTOP_H$MF_SB_X$MF_RULES$MF_REF_FINDER_H$MF_REF_DESKTOP_H$MF_PICTURES" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (folder|finder|desktop|sbx|rules), $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" P=$P0 F=$F0 D=$D0 X=$X0 R=$R0 c src
    mkdir -p "$d"
    case $2 in folder) src=$P0; c="$d/MacFolder.h"; P=$c;; finder) src=$F0; c="$d/Finder.h"; F=$c;; desktop) src=$D0; c="$d/Desktop.h"; D=$c;;
               sbx) src=$X0; c="$d/StatusBar.x"; X=$c;; rules) src=$R0; c="$d/crashmap-rules.txt"; R=$c;; esac
    perl -0777 -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$P" "$F" "$D" "$X" "$R" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  OLDSYM='[[UIImage systemImageNamed:\@"folder.fill" withConfiguration:cfg] imageWithTintColor:[UIColor colorWithRed:0.33 green:0.66 blue:0.96 alpha:1] renderingMode:UIImageRenderingModeAlwaysOriginal]'
  mtf "a plain folder back on iPadOS's folder.fill" finder "s/if \\(!it\\.locked\\) return DMFinderFolderPicture\\(side\\);/if (!it.locked) return $OLDSYM;/"
  mtf "an app's folder back on folder.fill" finder "s/UIImage \\*folder = DMFinderFolderPicture\\(side\\);/UIImage *folder = $OLDSYM;/"
  mtf "Finder's folder drawn again for every row (no cache)" finder 's/\n    UIImage \*hit = \[pictures objectForKey:\@\(side\)\]; if \(hit\) return hit;//'
  mtf "one picture kept for every side" finder 's/objectForKey:\@\(side\)\]; if \(hit\)/objectForKey:\@1]; if (hit)/; s/forKey:\@\(side\)\];\n    return made;/forKey:\@1];\n    return made;/'
  mtf "Finder's folder at 1x, not the screen's scale" finder 's/initWithSize:CGSizeMake\(side, side\)\];/initWithSize:CGSizeMake(side, side) format:({ UIGraphicsImageRendererFormat *f1 = [UIGraphicsImageRendererFormat preferredFormat]; f1.scale = 1; f1; })];/'
  mtf "a locked folder gets the macOS folder (not the lock)" finder 's/if \(!it\.locked\) return DMFinderFolderPicture\(side\);/return DMFinderFolderPicture(side);/'
  mtf "the app's icon where folder.fill had it (0.58 of the height)" finder 's/140\.75 \* k - a \/ 2\.0/folder.size.height * 0.58 - a \/ 2.0/'
  mtf "the app's icon less than half its size (40 of 256)" finder 's/a = 92\.0 \* k;/a = 40.0 * k;/'
  mtf "the app's icon drawn inset in its box" finder 's/\[app drawInRect:box\];/[app drawInRect:CGRectInset(box, a * 0.2, a * 0.2)];/'
  mtf "a copy of the painter in Finder.h" finder 's/\{ DMDesktopDrawFolder\(ctx\.CGContext, side\); \}/{ CGFloat k = side \/ 256.0; (void)(unsigned[]){ 0x41A2D6, 0x2F96D2, 0x007AC9 }; CGPathRef p = CGPathCreateWithRoundedRect(CGRectMake(26 * k, 68 * k, 209 * k, 145.5 * k), 12.5 * k, 12.5 * k, NULL); CGContextAddPath(ctx.CGContext, p); CGContextSetRGBFillColor(ctx.CGContext, 0.31, 0.71, 0.91, 1); CGContextFillPath(ctx.CGContext); CGPathRelease(p); }/'
  mtf "another blue on the front" folder 's/0x6CC9F6, 0x74CFFB, 0x70CDF9/0x6CC9F6, 0x40CFFB, 0x70CDF9/'
  mtf "the front panel shorter (another folder)" folder 's/CGRectMake\(26 \* k, 68 \* k, 209 \* k, 145\.5 \* k\)/CGRectMake(26 * k, 90 * k, 209 * k, 123.5 * k)/'
  mtf "the painter may be inlined away (noinline taken out)" folder 's/static __attribute__\(\(noinline\)\) void DMDesktopDrawFolder/static void DMDesktopDrawFolder/'
  mtf "the crash map without the painter's rule (the desktop takes Finder's crash)" rules 's/\nsym MacStatusBarCore \^_\*DMDesktop\(DrawFolder\|FolderFill\)\$ transparent//'
  mtf "the painter's rule after the desktop's (the desktop's wins)" rules 's/\n(sym MacStatusBarCore \^_\*DMDesktop\(DrawFolder\|FolderFill\)\$ transparent)(\nsym MacStatusBarCore \^_\?DMDesktop\[A-Z\] desktopIcons)/$2\n$1/'
  mtf "MacFolder.h included after Finder.h" sbx 's/(#include "MacFolder\.h"[^\n]*\n)(#include "Finder\.h"[^\n]*\n)/$2$1/'
  mtf "the desktop draws its own copy again" desktop 's/(- \(UIImage \*\)dm_folderImage \{)/static void DMDesktopFolderFillCopy(void) { (void)(unsigned[]){ 0x41A2D6, 0x2F96D2, 0x007AC9 }; }\n$1/'
fi
exit $rc
