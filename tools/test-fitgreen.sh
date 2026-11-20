#!/bin/bash
# test-fitgreen.sh: Fit to Window, green on a tiled window, one rule for Aerial, Zetsu and MilkyWay4: the window going full screen leaves the tiles and
# the others keep theirs; it takes its tile back when it returns; a real close (red) and a quit while full screen close the tiles up (1.8.7.5, audit
# L28 of 1.8.7.2) -- see test-fitgreen.m. App Window Sizes' forget (1.8.8, the review of F1-F4) takes only the way back into the tile: a quit while
# full screen still closes it up, and the green light's way back with no place of its own kept ends the record on every engine. KT's decision c
# (19 Nov, 1.8.8 G2): a window that comes back from full screen as a free window (that way back at its new size, or its Dock icon) has its tile
# closed up at once, on every engine, and its later quit changes nothing more. The real closure check and the Fit records are cut out of
# statusbar/StatusBar.x (FG_SB_X: another copy, e.g. the code before the fix), with the forget's Fit call (DMAppSizeForgetPlace), DMWindowLayout's
# lines that end the record and the free mark (DMMarkFreeWindow), and run on the Mac (Mac Catalyst), in a release and a DEBUG build; then the site
# checks; then made-to-fail copies; then the file before G2 (3349eed7, or its -reg twin b7a8f6a1), which must fail as KT's decision c reads it.
# The review of G1-G2, finding 1 (engine parity): the way back as a window Fit tiles is a new window, its tiles played as DMCascadeStage's Fit part
# (test-fitgreen.m FitJoinsAsNew, the real DMAssignTilesKeepingPlaces): the same tiles test-smfitfullaway checks on our Stage Manager engine.
# Finding 2: the record ends when the app is back as a window -- DMCascadeStage's line (DMFitFullScreenOpensNew) for a window that opens not free
# while the record keeps no way back (else marked back, gFSFitBack), and the forget (DMFitForgetFullScreenWayBack) once the app is a window again (that mark) -- so G2's close-ups act only on
# an app still full screen; the file before (1be5be97 / 34f591ab) must fail that (the status bar's green on Notes as a window closed the tiles up).
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${FG_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }   # one line (a global)
has() { /usr/bin/grep -qF -e "$2" "$1"; }

LINES=('static NSMutableSet<NSString *> *gFreeWindows;' 'static BOOL gMoveKeepsOrder = NO;' 'static NSMutableArray<NSString *> *gFitGroup = nil;'
       'static NSMutableDictionary<NSString *, NSString *> *gFitSlots = nil;' 'static const void *kStageClosingKey = &kStageClosingKey;'
       'static const void *kStageGoingFullKey = &kStageGoingFullKey;' 'static const void *kStageEnteringKey = &kStageEnteringKey;'
       'static NSString *gFSFitBundle; static NSArray<NSString *> *gFSFitGroup;' 'BOOL gFitClosureCheckDue = NO;' 'static NSArray<NSString *> *gFitWatchPrevious = nil;')
FNS=('static void DMFitGroupForget(NSString *bundleID) {' 'static BOOL DMStageTakesPartInFit(UIView *s) {' 'static void DMAssignTilesKeepingPlaces(NSString *fresh) {'
     'static NSString *DMTilesText(NSArray<NSString *> *order, NSDictionary<NSString *, NSString *> *slots) {'
     'static void DMRememberFitForFullScreen(NSString *bundleID) {' 'static void DMFitForgetFullScreenTile(NSString *bundleID, NSString *why) {'
     'static void DMFitFullScreenAppGone(NSString *bundleID) {' 'static void DMFitRejoinAfterFullScreen(NSString *bundleID) {'
     'static void DMFitWatchSync(void) {' 'void DMFitWatchSyncExtern(void) {' 'static void DMWatchFitClosures(void) {')
NEW_LEFT='static BOOL gFSFitLeft = NO;'
NEW_BACKMARK='static BOOL gFSFitBack = NO;'   # (the review of G1-G2, finding 2: the app back as a window, its record kept with its way back)
NEW_WAYBACK='static void DMFitForgetFullScreenWayBack(NSString *bundleID, NSString *why) {'   # (1.8.8: App Window Sizes' forget, the way back only)
FORGET='static void DMAppSizeForgetPlace(NSString *bundle) {'   # (1.8.8: App Window Sizes' forget, its Fit call)
GOES='static void DMFitFullScreenTileGoes(NSString *bundleID, NSString *why) {'   # (1.8.8 G2: the close-up the quit and the free return share)
BACKFREE='static void DMFitFullScreenBackFree(NSString *bundleID) {'   # (1.8.8 G2: back from full screen as a free window, KT's decision c)
MARKFREE='static void DMMarkFreeWindow(NSString *bundleID) {'   # (the free mark: a window Fit leaves out)
OPENSNEW='static void DMFitFullScreenOpensNew(NSString *bundleID) {'   # (the review of G1-G2, finding 2: the record ends as the app's window opens)
CASCADE='static void DMCascadeStage(UIView *stage) {'
ALONE='static const void *kStageFitAloneKey = &kStageFitAloneKey;'   # (1.8.8 H2: the mark of a window that opened on its own, DMFitGroupForget takes it)
KEEPS='static BOOL DMFitKeepsTile(UIView *s) {'; AWAYP='static void DMFitPlaceAway(UIView *stage, CGRect frame) {'   # (1.8.8 H2: a minimized window keeps its tile)
LEFTAT='static NSMutableArray<NSString *> *DMFitLeftAtCloseUp(NSArray<NSString *> *candidates) {'   # (the H2-H5 review, finding 2: the windows that close the tiles up)
NOTE='static void DMStageSetLayoutNote(UIView *st, id saved) {'; NOTEKEY='static const void *kStageLayoutNameKey = &kStageLayoutNameKey;'   # (the layout a window is noted in: DMFitPlaceAway notes its tile's, the H2-H5 review fix 6)
ALONEJOIN='static NSArray<NSString *> *DMFitAloneJoin(NSArray<NSString *> *part, NSMutableArray<NSString *> *fresh) {'   # (the H2-H5 review, finding 5: the way back takes them in)

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 n=0 h out dbg i
  mkdir -p "$d"
  for h in "${LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${FNS[@]}" "$MARKFREE"; do [ -n "$(cutfn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  {
    for i in 0 1 2 3 4 5 6; do line "$X" "${LINES[$i]}"; done
    if has "$X" "$ALONE"; then line "$X" "$ALONE"; fi
    for i in 0 1 2 3; do cutfn "$X" "${FNS[$i]}"; done
    if has "$X" "$KEEPS"; then cutfn "$X" "$KEEPS"; fi
    if has "$X" "$LEFTAT"; then cutfn "$X" "$LEFTAT"; fi
    if has "$X" "$NOTE"; then line "$X" "$NOTEKEY"; cutfn "$X" "$NOTE"; fi
    if has "$X" "$AWAYP"; then cutfn "$X" "$AWAYP"; fi
    if has "$X" "$ALONEJOIN"; then cutfn "$X" "$ALONEJOIN"; fi
    line "$X" "${LINES[7]}"
    if has "$X" "$NEW_LEFT"; then line "$X" "$NEW_LEFT"; fi
    if has "$X" "$NEW_BACKMARK"; then line "$X" "$NEW_BACKMARK"; fi
    for i in 4 5; do cutfn "$X" "${FNS[$i]}"; done
    if has "$X" "$GOES"; then cutfn "$X" "$GOES"; fi
    cutfn "$X" "${FNS[6]}"
    if has "$X" "$BACKFREE"; then cutfn "$X" "$BACKFREE"; fi
    cutfn "$X" "${FNS[7]}"
    if has "$X" "$NEW_WAYBACK"; then cutfn "$X" "$NEW_WAYBACK"; fi
    if has "$X" "$OPENSNEW"; then cutfn "$X" "$OPENSNEW"; fi
    cutfn "$X" "$MARKFREE"
    line "$X" "${LINES[8]}"; line "$X" "${LINES[9]}"
    for i in 8 9 10; do cutfn "$X" "${FNS[$i]}"; done
    # (DMWindowLayout's lines that end the record as written: a layout from the Window menu, the green light's way back with no place kept -- and
    #  1.8.8 G2's, that way back as a free window closing its tile up)
    echo 'static void KLayoutFitLines(NSString *bundleID) {'; cutfn "$X" 'static void DMWindowLayout(NSString *name) {' | /usr/bin/grep -E '^    if \(.*\) DMFit(ForgetFullScreenTile\(bundleID, |FullScreenBackFree\(bundleID\);)'; echo '}'
    # (DMCascadeStage's line that ends the record as the app's window opens, as written: none in the file before the review's fix)
    echo 'static void KCascadeFitLines(NSString *me, BOOL fitOn, int app, BOOL own, BOOL preLaunched) {'; cutfn "$X" "$CASCADE" | /usr/bin/grep -E '^    if \(.*\) DMFitFullScreenOpensNew\(me\);'; echo '}'
    # (App Window Sizes' forget: its Fit call as written)
    if has "$X" "$FORGET"; then echo 'static void KAppSizeForgetFit(NSString *bundle) {'; cutfn "$X" "$FORGET" | /usr/bin/grep -E '^    DMFitForgetFullScreen[A-Za-z]*\(bundle, '; echo '}'; fi
  } > "$d/fg-real.inc"
  /usr/bin/grep -qF 'if (!gPreferRememberedFrame) DMFitForgetFullScreenTile(bundleID, @"placed from the Window menu");' "$d/fg-real.inc" || { echo "FAIL  $X: no Window menu line in DMWindowLayout"; return 99; }
  ka=0; if has "$X" "$FORGET"; then ka=1; [ "$(/usr/bin/grep -c '^    DMFitForgetFullScreen[A-Za-z]*(bundle, ' "$d/fg-real.inc")" = 1 ] || { echo "FAIL  $X: no Fit call in DMAppSizeForgetPlace"; return 99; }; fi
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -DKAPPSIZES=$ka -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-fitgreen.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | /usr/bin/grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  # (site checks) every engine's green records the tiles it leaves before its window goes: Aerial's and Zetsu's lights, MilkyWay4's own green; the
  # quit while full screen and the return use the records; the window level still reads only Aerial's mark (not changed here)
  if cutfn "$X" 'static void DMStageLightAction(UIView *stage, NSInteger which) {' | awk '/DMRememberFitForFullScreen\(bundleID\);/{a=NR} /DMZetsuToFullScreen\(\(UIWindow \*\)stage\);/{z=NR} /DMAerialToFullScreen\(stage\);/{e=NR} END{exit !(a && z > a && e > a)}' \
     && cutfn "$X" 'static void DMMilkyWayToFullScreen(AXWindowView *window, NSString *bundleID, id sender) {' | awk '/DMRememberFitForFullScreen\(bundleID\);/{a=NR} /DMExpandWindowToFullScreen\(window, bundleID, sender\);/{b=NR} END{exit !(a && b > a)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: Aerial's, Zetsu's and MilkyWay4's greens record the tiles before the window goes"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: an engine's green does not record the tiles first"; n=$((n + 1)); fi
  if /usr/bin/grep -qF 'DMFitFullScreenAppGone(bundleID);   // (it had gone full screen out of a Fit pair: the tile it kept is closed up now)' "$X" \
     && [ "$(/usr/bin/grep -c 'kStageGoingFullKey, @YES' "$X")" = 1 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the app's exit closes its kept tile up; only Aerial's green sets the window-level mark"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the exit or the window-level mark is not as expected"; n=$((n + 1)); fi
  # (1.8.8) App Window Sizes' forget takes the way back only; the green light's way back with no place kept ends the record before any engine's part
  if [ $ka = 1 ]; then
    if cutfn "$X" "$FORGET" > "$d/fp" && [ "$(/usr/bin/grep -c 'DMFitForgetFullScreen' "$d/fp")" = 1 ] \
       && /usr/bin/grep -qxF '    DMFitForgetFullScreenWayBack(bundle, @"has a new size (App Window Sizes)");' "$d/fp" \
       && cutfn "$X" "$NEW_WAYBACK" | /usr/bin/grep -qxF '    gFSFitGroup = nil; gFSFitSlots = nil;' \
       && cutfn "$X" 'static void DMWindowLayout(NSString *name) {' | awk 'index($0, "    if (gPreferRememberedFrame && !gLastWindowFrames[bundleID]) DMFitForgetFullScreenTile(bundleID, ") == 1 {a=NR} index($0, "    if (gPreferRememberedFrame) target = ") == 1 {t=NR} index($0, "    if (DMActiveEngine() == DMEngineZetsu) {") == 1 {z=NR} END{exit !(a && t > a && z > a)}'; then
      [ -n "$q" ] || echo "PASS  StatusBar.x: App Window Sizes' forget takes the way back into the tile only; the green light's way back with no place kept ends the record before every engine's part"
    else [ -n "$q" ] || echo "FAIL  StatusBar.x: App Window Sizes' forget or the way back's end of the record is not as expected"; n=$((n + 1)); fi
  fi
  # (1.8.8 G2, KT's decision c) the way back as a free window closes the tile up just before the line that ends the record, before every engine's
  # part; the free mark does it for a window opened some other way; the quit and the free return share one close-up (the quit's log as before)
  if cutfn "$X" 'static void DMWindowLayout(NSString *name) {' | awk 'index($0, "    if (gPreferRememberedFrame && !gLastWindowFrames[bundleID] && DMFitEnabled() && MSBDOpensFree(DMAppSizeOf(bundleID), gNewWindowsFill, NO, NO)) DMFitFullScreenBackFree(bundleID);") == 1 {b=NR}
         index($0, "    if (gPreferRememberedFrame && !gLastWindowFrames[bundleID]) DMFitForgetFullScreenTile(bundleID, ") == 1 {a=NR} index($0, "    if (DMActiveEngine() == DMEngineZetsu) {") == 1 {z=NR} END{exit !(b && a == b + 1 && z > a)}' \
     && [ "$(/usr/bin/grep -c 'DMFitFullScreenBackFree(' "$X")" = 4 ] \
     && cutfn "$X" "$MARKFREE" | awk 'index($0, "    [gFreeWindows addObject:bundleID];") == 1 {m=NR} index($0, "    DMFitFullScreenBackFree(bundleID);") == 1 {f=NR} END{exit !(m && f > m)}' \
     && /usr/bin/grep -qxF 'static void DMFitFullScreenAppGone(NSString *bundleID) { DMFitFullScreenTileGoes(bundleID, @"quit while full screen"); }' "$X" \
     && cutfn "$X" "$BACKFREE" | /usr/bin/grep -qxF '    DMFitFullScreenTileGoes(bundleID, @"comes back from full screen as a free window, not into its tile");' \
     && [ "$(/usr/bin/grep -c 'DMFitFullScreenTileGoes(' "$X")" = 3 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: G2: the green light's way back as a free window closes its tile up before the record's end and every engine's part; the free mark does it too; one close-up with the quit's"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: G2's close-up of a window back free is not where expected"; n=$((n + 1)); fi
  # (the review of G1-G2, finding 2) the record's end as the app's window opens: once in DMCascadeStage, after the Fill decision is known and before
  # its block (which returns), for a window that does not open free; only a record with no way back; the forget ends a record outlived by its window
  if has "$X" "$OPENSNEW"; then
    if cutfn "$X" "$CASCADE" | awk 'index($0, "    BOOL atFill = MSBDNewWindowAtFill(") == 1 {a=NR} index($0, "    if (!fitOn || !MSBDOpensFree(app, gNewWindowsFill, own, preLaunched)) DMFitFullScreenOpensNew(me);") == 1 {o=NR} index($0, "    if (atFill) {") == 1 {f=NR} END{exit !(a && o > a && f > o)}' \
       && [ "$(/usr/bin/grep -c 'DMFitFullScreenOpensNew(me)' "$X")" = 1 ] \
       && cutfn "$X" "$OPENSNEW" | /usr/bin/grep -qxF '    if (gFSFitGroup) { gFSFitBack = YES; return; }' \
       && cutfn "$X" "$NEW_WAYBACK" | awk 'index($0, "    if (gFSFitBack) { DMFitForgetFullScreenTile(bundleID, [why stringByAppendingString:@\" while it is a window again\"]); return; }") == 1 {b=NR} index($0, "    gFSFitGroup = nil; gFSFitSlots = nil;") == 1 {g=NR} END{exit !(b && g > b)}' \
       && cutfn "$X" 'static void DMRememberFitForFullScreen(NSString *bundleID) {' | /usr/bin/grep -qxF '    gFSFitBack = NO;' \
       && [ "$(/usr/bin/grep -c 'gFSFitBack = YES' "$X")" = 1 ]; then
      [ -n "$q" ] || echo "PASS  StatusBar.x: the record ends as the app's window opens (DMCascadeStage, once, before the Fill block), or is marked back when it keeps its way back, and ends at the forget then; every green starts it unmarked"
    else [ -n "$q" ] || echo "FAIL  StatusBar.x: the record's end as the app's window opens is not where expected"; n=$((n + 1)); fi
  fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$FG_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the named app not taken for full screen (the audit's case)" 's/            if \(!going && named && \(!st \|\| \[objc_getAssociatedObject\(st, kStageClosingKey\) boolValue\]\)\) going = YES;\n//'
  mtf "the record taken more than once a green" 's/BOOL named = !gFSFitLeft && \[b isEqualToString:gFSFitBundle\];/BOOL named = [b isEqualToString:gFSFitBundle];/'
  mtf "the record never marked as used" 's/                if \(named\) gFSFitLeft = YES;\n//'
  mtf "every closing window taken for full screen" 's/if \(!going && named && \(!st/if (!going \&\& (!st/'
  mtf "the green not starting a fresh record" 's/(gFSFitSlots = tiled \? \[gFitSlots copy\] : nil;\n)    gFSFitLeft = NO;\n/$1/'
  # (1.8.8, the review of F1-F4: App Window Sizes' forget and the record)
  mtf "the forget taking the whole record again (the review's case: a quit while full screen left the other window in its half)" 's/    DMFitForgetFullScreenWayBack\(bundle, \@"has a new size \(App Window Sizes\)"\);/    DMFitForgetFullScreenTile(bundle, \@"has a new size (App Window Sizes)");/'
  mtf "the forget leaving the way back (the window back in its old tile, not at its new size)" 's/\n    gFSFitGroup = nil; gFSFitSlots = nil;\n/\n/'
  mtf "the forget taking the record of an app not full screen (any app's tile forgotten)" 's/if \(!bundleID.length \|\| !\[gFSFitBundle isEqualToString:bundleID\] \|\| !gFSFitGroup\) return;/if (!bundleID.length || !gFSFitGroup) return;/'
  mtf "the way back with no place kept keeping the record (MilkyWay4: a later quit of its new window closed the tiles up)" 's/    if \(gPreferRememberedFrame && !gLastWindowFrames\[bundleID\]\) DMFitForgetFullScreenTile\(bundleID, [^\n]*\n//'
  mtf "the way back ending the record of a window that has its place (no tile taken back)" 's/    if \(gPreferRememberedFrame && !gLastWindowFrames\[bundleID\]\) DMFitForgetFullScreenTile\(bundleID, /    if (gPreferRememberedFrame) DMFitForgetFullScreenTile(bundleID, /'
  # (1.8.8 G2, KT's decision c: a window back from full screen as a free window has its tile closed up at once)
  mtf "the green light's way back free not closing the tile up (the record just ended: Settings kept its half next to the empty one for good)" 's/    if \(gPreferRememberedFrame && !gLastWindowFrames\[bundleID\] && DMFitEnabled\(\) && MSBDOpensFree\([^\n]*\n//'
  mtf "the close-up after the record's end (it finds no record: nothing closed up)" 's/(    if \(gPreferRememberedFrame && !gLastWindowFrames\[bundleID\] && DMFitEnabled\(\) && MSBDOpensFree\([^\n]*\n)(    if \(gPreferRememberedFrame && !gLastWindowFrames\[bundleID\]\) DMFitForgetFullScreenTile\([^\n]*\n)/$2$1/'
  mtf "the free mark not closing the tile up (its Dock icon: the tile closed up only at its quit)" 's/    DMFitFullScreenBackFree\(bundleID\);   \/\/ \(its app was full screen[^\n]*\n//'
  mtf "the way back closing the tile up for a window Fit tiles (the entry removed: Settings filled, then gave the new window a half again)" 's/MSBDOpensFree\(DMAppSizeOf\(bundleID\), gNewWindowsFill, NO, NO\)/YES/'
  mtf "the way back's free test without Open at Fill (a window back at Fill left its tile empty)" 's/MSBDOpensFree\(DMAppSizeOf\(bundleID\), gNewWindowsFill, NO, NO\)/MSBDOpensFree(DMAppSizeOf(bundleID), NO, NO, NO)/'
  mtf "the way back closing the tile up with the window's place kept (A7 b': out of its tile)" 's/    if \(gPreferRememberedFrame && !gLastWindowFrames\[bundleID\] && DMFitEnabled\(\) && /    if (gPreferRememberedFrame \&\& DMFitEnabled() \&\& /'
  mtf "the free return closing up whatever app the record names (another app's free window closed Notes' tile up)" 's/(static void DMFitFullScreenTileGoes\(NSString \*bundleID, NSString \*why\) \{\n)    if \(!bundleID.length \|\| !\[gFSFitBundle isEqualToString:bundleID\]\) return;/$1    if (!bundleID.length || !gFSFitBundle) return;/; s/(static void DMFitFullScreenBackFree\(NSString \*bundleID\) \{\n)    if \(!bundleID.length \|\| !\[gFSFitBundle isEqualToString:bundleID\]\) return;/$1    if (!bundleID.length || !gFSFitBundle) return;/'
  mtf "the free return leaving the record (a later quit of that window closed the tiles up again)" 's/(static void DMFitFullScreenTileGoes\(NSString \*bundleID, NSString \*why\) \{\n[^\n]*\n)    gFSFitBundle = nil; gFSFitGroup = nil; gFSFitSlots = nil;\n/$1/'
  # (the review of G1-G2, finding 2: the record ends when the app is back as a window)
  mtf "the window's open not ending a record with no way back (its later quit closed the tiles up as if it quit while full screen)" 's/    if \(!fitOn \|\| !MSBDOpensFree\(app, gNewWindowsFill, own, preLaunched\)\) DMFitFullScreenOpensNew\(me\);\n//'
  mtf "the window's open ending a record that keeps its way back (Aerial's green with no entrance cover lost its tile)" 's/    if \(gFSFitGroup\) \{ gFSFitBack = YES; return; \}\n//'
  mtf "the window's open not marking a record that keeps its way back (the Dock icon's record stayed: a size, then the status bar's green, closed the tiles up)" 's/    if \(gFSFitGroup\) \{ gFSFitBack = YES; return; \}/    if (gFSFitGroup) return;/'
  mtf "the window's open ending the record of a window that opens free (its Dock icon at its new size: no close-up)" 's/    if \(!fitOn \|\| !MSBDOpensFree\(app, gNewWindowsFill, own, preLaunched\)\) DMFitFullScreenOpensNew\(me\);/    DMFitFullScreenOpensNew(me);/'
  mtf "the forget keeping a record its window outlived (the status bar's green on Notes as a window closed the tiles up)" 's/    if \(gFSFitBack\) \{[^\n]*\n//'
  mtf "a new green not clearing the mark (an earlier window's: the forget then ended the new record, and its quit while full screen closed nothing up)" 's/    gFSFitLeft = NO;\n    gFSFitBack = NO;\n/    gFSFitLeft = NO;\n/'
  # (the file before the review's fix 2: the status bar's green on Notes back as a window by its Dock icon, after a size given then, closed the tiles
  #  up as if it came back from full screen as a free window; and a window opened after the forget while full screen left a record its quit used)
  for c in 1be5be97 34f591ab; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/beforeh2.x"
    run "$W/beforeh2.x" "$W/beforeh2" q > /dev/null; n=$?
    "$W/beforeh2/t0" > "$W/beforeh2.out" 2>&1
    miss=0
    for en in Aerial Zetsu MilkyWay4; do
      for w in "finding 2: ... the status bar's green on that window: no close-up, the record gone" "finding 2: ... a size given while it is a window again: the record ends" \
               "finding 2: the forget while full screen, then its Dock icon as a window Fit tiles: the record ends as it opens" "finding 2: ... then Notes quits from that window: no close-up as if full screen"; do
        /usr/bin/grep -qF "FAIL  $en: $w" "$W/beforeh2.out" || { echo "      (the file before the review's fix 2: no FAIL line for \"$en: $w\")"; miss=1; }
      done
    done
    if [ $n -gt 0 ] && [ $n -lt 99 ] && [ $miss = 0 ]; then echo "PASS  the file before the review's fix 2 ($c) fails $n check(s), on every engine: the record outlived its window"
    else echo "FAIL  the file before the review's fix 2 ($c): $n failed, not as expected"; rc=1; fi
  else echo "PASS  (the files before the review's fix 2 are not in this tree's history: that comparison left out)"; fi
  # (the file before G2: it fails as KT's decision c reads it -- the green light's way back at the new size and the Dock icon left Settings in its
  #  half on every engine (closed up only at the quit after the Dock), the three tiles' two left as they were)
  for c in 3349eed7 b7a8f6a1; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/before.x"
    run "$W/before.x" "$W/before" q > "$W/before.out"; n=$?
    "$W/before/t0" > "$W/before.out" 2>&1
    miss=0
    for en in Aerial Zetsu MilkyWay4; do
      for w in "G2 ... green back free at its new size: Settings fills at once, once; the record ended" "G2 three tiles, Notes back free: Settings keeps its half, Safari takes the right half, at once" \
               "G2 ... Notes from its Dock icon instead, free: Settings fills at once, once" "G2 ... with New Windows Open at Fill on: back free at Fill, Settings fills at once"; do
        /usr/bin/grep -qF "FAIL  $en: $w" "$W/before.out" || { echo "      (the file before: no FAIL line for \"$en: $w\")"; miss=1; }
      done
    done
    if [ $n -gt 0 ] && [ $n -lt 99 ] && [ $miss = 0 ]; then echo "PASS  the file before G2 ($c) fails $n check(s), every engine's free return among them (Settings left in its half)"
    else echo "FAIL  the file before G2 ($c): $n failed, not as expected"; rc=1; fi
  else echo "PASS  (the files before G2 are not in this tree's history: that comparison left out)"; fi
fi
exit $rc
