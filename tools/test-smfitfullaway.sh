#!/bin/bash
# test-smfitfullaway.sh: Fit to Window on our Stage Manager engine while a tiled window is full screen out of sight (1.8.8 G1, KT's decision b,
# 19 Nov): the desktop's windows keep their tiles and the full-screen window keeps its way back, as with Aerial -- no re-tile of the two left, no
# third window's question when it returns (see test-smfitfullaway.m). Fit's look (DMSMFitTick), the windows full screen out of sight
# (DMSMFitFullAway), the closed windows' forget (DMSMFitForgetClosed) and the question before a launch (DMSMFitAsksAbout) are cut out of
# statusbar/StatusBar.x (SFA_SB_X: another copy, e.g. the code before the fix) and run on the Mac with stand-ins for SpringBoard's stages; then the
# site checks; then made-to-fail copies; then the file before the fix (d1eb4882, or its -reg twin 35434141), which must fail as the review read it.
# 1.8.8 G2 (KT's decision c, 19 Nov): a window back from full screen as a free window -- its place before full screen forgotten by App Window Sizes
# while it was full screen -- gives its tile up at once, the windows left close it up (DMSMFitBackFree, from the join's free mark: DMSMJoinAttributesOn's
# lines as written), and its later quit changes nothing more; the file before G2 (3349eed7 / b7a8f6a1) must fail that, as on the other engines
# (test-fitgreen).
# The review of G1-G2, finding 1 (engine parity): such a window back as a window Fit tiles (its entry removed, Open at Fill off) is a new window:
# its old tile is no way back (DMSMFitBackAsNew, from the join's line after G2's), so it takes the first tile and the others keep their places,
# as Aerial, Zetsu and MilkyWay4 tile it (test-fitgreen); the file before this fix (1be5be97 / 34f591ab) must fail that (it took its old tile again).
# 1.8.8 H3 (the iPad 2's row C14 of p03): a window back from full screen into the tile Fit kept for it is done with its way back where Fit's look
# returns early -- the minimized rule and the one-window rule (DMSMFitBackInTile, cut out when the file has it) -- as at the tick's last path; the
# file before this fix (9fd96881, or its -reg twin f166cd70) must fail that (Clock listed as full screen in its tile, then the third window's question).
# The H-round review of H3, finding 1: the one-window rule's call is the first line of its fill branch (it ends the way back only where it lays the
# window out), so a window back alone in a stage of its own with its tile kept (L-7) keeps its way back until it joins the desktop; the file before
# this fix (2e54542b, or its -reg twin b2316ceb) must fail that ("its tile again" for a window in no tile).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SFA_SB_X:-../statusbar/StatusBar.x}
f1() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && (/^}/ || /^static .*\{ .*\}( *\/\/.*)?$/) {exit}' "$2"; }   # f1 <first line> <file>: that function, to its closing brace (a one-line one: that line)
has() { /usr/bin/grep -qF -e "$2" "$1"; }
FNS=('static NSArray<NSString *> *DMDefaultSlotNames(NSUInteger n) {' 'static void DMSMFitForgetClosed(NSString *opening) {' 'static void DMSMFitTick(BOOL force) {'
     'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {')
AWAY='static NSSet<NSString *> *DMSMFitFullAway(NSSet<NSString *> *onScreen) {'   # (1.8.8 G1)
INTILE='static void DMSMFitBackInTile(NSArray<NSString *> *keys) {'   # (1.8.8 H3)
KEPTAWAY='static NSArray<NSString *> *DMSMFitKeptAway(NSArray<NSString *> *keys, NSDictionary<NSString *, NSString *> *slots) {'   # (1.8.8 H2: the tick plans with the minimized windows, test-fitminimized)
MININ='static NSArray<NSString *> *DMSMFitMinimizedIn(NSArray<NSString *> *keys, NSDictionary<NSString *, NSString *> *slots) {'   # (the H2-H5 review: DMSMFitKeptAway's look at the minimized windows)
BACK='static void DMSMFitBackFree(NSString *key) {'   # (1.8.8 G2)
NEW='static void DMSMFitBackAsNew(NSString *key) {'   # (1.8.8, the review of G1-G2)
JOIN='static id DMSMJoinAttributesOn(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage, id identity) {'   # (its free mark's lines)

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks (99: the code could not be cut out or built); the run's output in $2/out
  local X=$1 d=$2 q=$3 n h
  mkdir -p "$d"
  for h in "${FNS[@]}"; do [ -n "$(f1 "$h" "$X")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  [ -n "$(f1 "$JOIN" "$X" | /usr/bin/grep -E '^                if \(opensFree && DMFitEnabled\(\)')" ] || { echo "FAIL  $X: no free mark in DMSMJoinAttributesOn"; return 99; }
  { f1 "${FNS[0]}" "$X"; f1 "${FNS[1]}" "$X"; if has "$X" "$BACK"; then f1 "$BACK" "$X"; fi; if has "$X" "$NEW"; then f1 "$NEW" "$X"; fi; if has "$X" "$AWAY"; then f1 "$AWAY" "$X"; fi; if has "$X" "$INTILE"; then f1 "$INTILE" "$X"; echo '#define K_HAS_BACK_IN_TILE 1'; fi; if has "$X" "$MININ"; then f1 "$MININ" "$X"; fi; if has "$X" "$KEPTAWAY"; then f1 "$KEPTAWAY" "$X"; fi
    f1 "${FNS[2]}" "$X"; f1 "${FNS[3]}" "$X"
    # (the join's free mark as written -- a window joining at no size of its own, at the app's own size or Fill -- G2's line after it, and the
    #  review's line for one that is not free)
    echo 'static void KJoinFreeLines(NSString *key, id own, BOOL opensFree) {'; f1 "$JOIN" "$X" | /usr/bin/grep -E '^                if \(!?opensFree && DMFitEnabled\(\)'; echo '}'
  } > "$d/sfa-real.inc"
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" -framework Foundation -framework CoreGraphics -framework QuartzCore \
        -o "$d/t" test-smfitfullaway.m 2> "$d/cc.txt" || { cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -n "$q" ] || cat "$d/cc.txt"
  "$d/t" > "$d/out"; n=$?
  [ -n "$q" ] || cat "$d/out"
  return $n
}
run "$X0" "$W/real/x"; rc=$?
[ $rc = 99 ] && exit 1
X=$X0
# (site checks) the rule where the windows on screen are known, before the minimized rule and the "closed meanwhile" line that read it; one call
if f1 'static void DMSMFitTick(BOOL force) {' "$X" > "$W/tick" && [ "$(/usr/bin/grep -c 'DMSMFitFullAway(' "$X")" = 2 ] && [ "$(/usr/bin/grep -c 'DMSMFitFullAway(' "$W/tick")" = 1 ] \
   && awk 'index($0, "static NSSet<NSString *> *DMSMFitFullAway(NSSet<NSString *> *onScreen) {") == 1 {a=NR} index($0, "static void DMSMFitTick(BOOL force) {") == 1 {t=NR} END {exit !(a && t > a)}' "$X" \
   && awk 'index($0, "        bundles = [part mutableCopy];") == 1 {p=NR} index($0, "    NSSet<NSString *> *fullAway = DMSMFitFullAway(onScreen);") == 1 {f=NR}
           index($0, "    if (bundles.count && gSMFitSlots.count > bundles.count) {") == 1 {m=NR} index($0, "(closed meanwhile)") {c=NR} END {exit !(p && f > p && m == f + 1 && c > m)}' "$W/tick" \
   && /usr/bin/grep -qF 'if (!there || !(DMSMIsMinimized(k) || DMSMKeySetHas(fullAway, k))) { onlyMinimizedOut = NO; break; }' "$W/tick" \
   && /usr/bin/grep -qF 'if (![onScreen containsObject:b] && !((gSMFitSlots[b] || gSMFitSlotsBeforeFull[b]) && [fullAway containsObject:b])) [gSMFitWentFull removeObject:b];   // (closed meanwhile)' "$W/tick"; then
  echo "PASS  StatusBar.x: DMSMFitFullAway once, before the tick; the tick reads it once the windows taking part are known, for the minimized rule and the \"closed meanwhile\" line"
else echo "FAIL  StatusBar.x: DMSMFitFullAway or its two uses in DMSMFitTick not as expected"; rc=$((rc + 1)); fi
# (G2) the join's free mark, then the close-up for a window back from full screen (only one that was full screen), once; DMSMFitBackFree after
# DMSMFitForgetClosed, laying out at Fit's next look
if f1 "$JOIN" "$X" > "$W/join" && awk 'index($0, "                if (opensFree && DMFitEnabled()) { if (!gSMFreeWindows) gSMFreeWindows = [NSMutableSet set]; [gSMFreeWindows addObject:key]; }") == 1 {m=NR}
         index($0, "                if (opensFree && DMFitEnabled() && own && DMSMAttrsFullScreen(own)) DMSMFitBackFree(key);") == 1 {b=NR} END {exit !(m && b > m && b <= m + 3)}' "$W/join" \
   && [ "$(/usr/bin/grep -c 'DMSMFitBackFree(' "$X")" = 3 ] && [ "$(/usr/bin/grep -c 'DMSMFitBackFree(' "$W/join")" = 1 ] \
   && awk 'index($0, "static void DMSMFitForgetClosed(NSString *opening) {") == 1 {c=NR} index($0, "static void DMSMFitBackFree(NSString *key) {") == 1 {b=NR} END {exit !(c && b > c)}' "$X" \
   && f1 "$BACK" "$X" | /usr/bin/grep -qxF '    gSMFitLookAgain = YES;'; then
  echo "PASS  StatusBar.x: G2: the join's free mark, then the close-up for a window back from full screen, once; DMSMFitBackFree has Fit look again"
else echo "FAIL  StatusBar.x: G2's close-up in the join not as expected"; rc=$((rc + 1)); fi
# (the review of G1-G2) the join's line for a window back that Fit tiles, right after G2's, once; DMSMFitBackAsNew after DMSMFitBackFree, giving the
# tile up with no close-up (no plan of the windows left, no look of Fit's asked for: the window's own join tiles it)
if awk 'index($0, "                if (opensFree && DMFitEnabled() && own && DMSMAttrsFullScreen(own)) DMSMFitBackFree(key);") == 1 {b=NR}
        index($0, "                if (!opensFree && DMFitEnabled() && own && DMSMAttrsFullScreen(own)) DMSMFitBackAsNew(key);") == 1 {n=NR} END {exit !(b && n > b && n <= b + 3)}' "$W/join" \
   && [ "$(/usr/bin/grep -c 'DMSMFitBackAsNew(' "$X")" = 3 ] && [ "$(/usr/bin/grep -c 'DMSMFitBackAsNew(' "$W/join")" = 1 ] \
   && awk 'index($0, "static void DMSMFitBackFree(NSString *key) {") == 1 {b=NR} index($0, "static void DMSMFitBackAsNew(NSString *key) {") == 1 {n=NR} END {exit !(b && n > b)}' "$X" \
   && f1 "$NEW" "$X" > "$W/new" && ! /usr/bin/grep -q 'gSMFitLookAgain\|MSBDFitPlanKeepingPlaces\|DMSMFitLeftAfterClose\|DMSMApply' "$W/new" \
   && /usr/bin/grep -qxF '    NSDictionary *mem = DMSMFitMemoryWithout(gSMFitByDesk, keys);' "$W/new"; then
  echo "PASS  StatusBar.x: the review's line for a window back that Fit tiles, after G2's, once; DMSMFitBackAsNew gives the tile up with no close-up and forgets the arrangements remembered with it"
else echo "FAIL  StatusBar.x: the review's line in the join or DMSMFitBackAsNew not as expected"; rc=$((rc + 1)); fi
# (H3) DMSMFitBackInTile once, after DMSMFitFullAway and before the tick, called twice and only there: in the minimized rule right after its plan
# (before its log and its return) and in the one-window rule as the first line of its fill branch, after the other windows' close-up (where it lays
# the window out: not for a window alone in a stage of its own, L-7 -- the H-round review, finding 1); it ends only a way back whose tile Fit kept,
# and drops the arrangement left only when it names no window still full screen
if [ "$(/usr/bin/grep -cF "$INTILE" "$X")" = 1 ] && [ "$(/usr/bin/grep -c 'DMSMFitBackInTile(' "$X")" = 3 ] && [ "$(/usr/bin/grep -c 'DMSMFitBackInTile(' "$W/tick")" = 2 ] \
   && awk -v i="$INTILE" 'index($0, "static NSSet<NSString *> *DMSMFitFullAway(NSSet<NSString *> *onScreen) {") == 1 {a=NR} index($0, i) == 1 {h=NR} index($0, "static void DMSMFitTick(BOOL force) {") == 1 {t=NR} END {exit !(a && h > a && t > h)}' "$X" \
   && awk 'index($0, "            for (NSString *b in bundles) plan[b] = gSMFitSlots[b];") == 1 {p=NR} index($0, "            DMSMFitBackInTile(bundles);   // (one of them ") == 1 {m=NR}
           index($0, "            if (!full) DMLog(") == 1 {l=NR} index($0, "            DMSMFitBackInTile(bundles);   // (the one ") == 1 {o=NR}
           index($0, "        if (one && gSMFitSlots.count == 1 && [gSMFitSlots[one] isEqualToString:@\"fill\"]) {") == 1 {f=NR}
           index($0, "                gSMFitSlots = [MSBDFitPlanKeepingPlaces(@[one], nil) mutableCopy];   // (it fills)") == 1 {g=NR}
           END {exit !(p && m == p + 1 && l > m && g && f > g && o == f + 1)}' "$W/tick" \
   && f1 "$INTILE" "$X" > "$W/intile" && /usr/bin/grep -qF 'for (NSString *k in keys) if ([gSMFitWentFull containsObject:k] && gSMFitSlots[k]) [back addObject:k];' "$W/intile" \
   && /usr/bin/grep -qF 'for (NSString *k in gSMFitWentFull) if (gSMFitSlotsBeforeFull[k]) { named = YES; break; }' "$W/intile" && /usr/bin/grep -qxF '    if (!named) gSMFitSlotsBeforeFull = nil;' "$W/intile" \
   && ! /usr/bin/grep -q 'DMSMApply\|gSMFitLookAgain\|UIKit\|UIScreen\|UIApplication' "$W/intile"; then
  echo "PASS  StatusBar.x: H3: DMSMFitBackInTile once, before the tick; called in the minimized rule after its plan and first in the one-window rule's fill branch, nowhere else; Fit's memory only"
else echo "FAIL  StatusBar.x: H3's DMSMFitBackInTile or its two calls not as expected"; rc=$((rc + 1)); fi
# (the crash map) the new functions are window code: the Stage Manager engine's DMSM rule (windowingEnabled), not App Window Sizes' piece
r=$(awk '$1 == "sym" && $2 == "MacStatusBarCore" && $4 == "appWindowSizes" {print $3}' crashmap-rules.txt); w=$(awk '$1 == "sym" && $2 == "MacStatusBarCore" && $3 == "^_*DMSM[A-Z0-9]" {print $4}' crashmap-rules.txt)
for fnn in DMSMFitFullAway DMSMFitBackFree DMSMFitBackAsNew DMSMFitBackInTile; do
  if [ -n "$r" ] && [ "$w" = windowingEnabled ] && python3 -I -c 'import re, sys; sys.exit(0 if re.search(sys.argv[2], sys.argv[3]) and not re.search(sys.argv[1], sys.argv[3]) else 1)' "$r" '^_*DMSM[A-Z0-9]' "_$fnn"; then
    echo "PASS  crash map: $fnn falls under the DMSM rule (windowingEnabled)"
  else echo "FAIL  crash map: $fnn not under the DMSM rule"; rc=$((rc + 1)); fi
done

if [ -z "$SFA_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -0pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=$((rc + 1)); return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=$((rc + 1)); fi
  }
  k=0
  mtf "the minimized rule without the windows full screen out of sight (the desktop's two windows tiled again as a pair)" 's/ \|\| !\(DMSMIsMinimized\(k\) \|\| DMSMKeySetHas\(fullAway, k\)\)\)/ || !DMSMIsMinimized(k))/'
  mtf "the way back dropped for a window not on screen (\"closed meanwhile\" as before: the third window's question on its return)" 's/ && !\(\(gSMFitSlots\[b\] \|\| gSMFitSlotsBeforeFull\[b\]\) && \[fullAway containsObject:b\]\)\) \[gSMFitWentFull removeObject:b\];/) [gSMFitWentFull removeObject:b];/'
  mtf "the way back kept only while its tile is (a later look drops it once another window took the tile)" 's/\(gSMFitSlots\[b\] \|\| gSMFitSlotsBeforeFull\[b\]\) && \[fullAway/gSMFitSlots[b] \&\& [fullAway/'
  mtf "the way back kept for any window full screen out of sight (a No Fit window too, which left no tile)" 's/\(gSMFitSlots\[b\] \|\| gSMFitSlotsBeforeFull\[b\]\) && \[fullAway/[fullAway/'
  mtf "every window out of the desktop taken for full screen out of sight (a window in a stage of its own keeps a tile)" 's/ && DMSMAttrsFullScreen\(m\[it\]\)\) \[away addObject:k\];/) [away addObject:k];/'
  mtf "only the stage on screen read (a full-screen window in a stage of its own not seen)" 's/(static NSSet<NSString \*> \*DMSMFitFullAway\(NSSet<NSString \*> \*onScreen\) \{\n[^\n]*\n)    for \(id al in DMSMRecentStages\(\)\) \{/$1    for (id al in \@[DMSMFrontStage() ?: \@{}]) {/'
  # (G2, KT's decision c)
  mtf "the join not giving the tile up (the other window kept its half next to the empty one until the window closed)" 's/                if \(opensFree && DMFitEnabled\(\) && own && DMSMAttrsFullScreen\(own\)\) DMSMFitBackFree\(key\);\n//'
  mtf "the tile given up by any window joining free (one that was not full screen: a window moved by hand out of its tile)" 's/ && own && DMSMAttrsFullScreen\(own\)\) DMSMFitBackFree\(key\);/) DMSMFitBackFree(key);/'
  mtf "the tile given up without Fit's look (the windows left not laid out until another change)" 's/(    gSMFitSlots = left.count \? \[MSBDFitPlanKeepingPlaces\(left, gSMFitSlots\) mutableCopy\] : nil;\n)    gSMFitLookAgain = YES;\n(    for \(NSString \*k in gone\))/$1$2/'
  mtf "the tile given up in no order of the windows' (the default tiles: Safari to the left half)" 's/    gSMFitSlots = left.count \? \[MSBDFitPlanKeepingPlaces\(left, gSMFitSlots\) mutableCopy\] : nil;\n    gSMFitLookAgain = YES;\n    for \(NSString \*k in gone\)/    gSMFitSlots = left.count ? [MSBDFitPlanKeepingPlaces(left, nil) mutableCopy] : nil;\n    gSMFitLookAgain = YES;\n    for (NSString *k in gone)/'
  # (the review of G1-G2, finding 1: a window back as one Fit tiles is a new window)
  mtf "the join leaving the old tile to a window back as one Fit tiles (the review's case: it took its old tile again)" 's/                if \(!opensFree && DMFitEnabled\(\) && own && DMSMAttrsFullScreen\(own\)\) DMSMFitBackAsNew\(key\);\n//'
  mtf "the old tile closed up instead (Settings filled first, then gave the new window a half)" 's/(if \(!opensFree && DMFitEnabled\(\) && own && DMSMAttrsFullScreen\(own\)\)) DMSMFitBackAsNew\(key\);/$1 DMSMFitBackFree(key);/'
  mtf "the join's line for any window joining (a tiled window not full screen lost its tile)" 's/if \(!opensFree && DMFitEnabled\(\) && own && DMSMAttrsFullScreen\(own\)\) DMSMFitBackAsNew/if (!opensFree \&\& DMFitEnabled()) DMSMFitBackAsNew/'
  mtf "the arrangements remembered with it kept (the same two windows took their old tiles from there)" 's/    NSDictionary \*mem = DMSMFitMemoryWithout\(gSMFitByDesk, keys\);\n/    NSDictionary *mem = gSMFitByDesk;\n/'
  mtf "its way back from full screen kept (Fit's look took it back from full screen: no question as a new window)" 's/    for \(NSString \*k in \[gSMFitWentFull allObjects\]\) if \(\[keys containsObject:k\] \|\| DMSMKeyCovers\(k, key\)\) \[gSMFitWentFull removeObject:k\];\n//'
  mtf "the arrangement it left kept (its tile taken meanwhile: its way back stayed)" 's/    if \(leftFull\) gSMFitSlotsBeforeFull = nil;\n    for \(NSString \*k in gone\) \[gSMFitSlots removeObjectForKey:k\];/    for (NSString *k in gone) [gSMFitSlots removeObjectForKey:k];/'
  mtf "a window that left no tile treated so too (its way back from full screen dropped, as before it was not)" 's/    if \(!gone.count && !leftFull\) return;\n//'
  # (H3, the iPad 2's C14 of p03)
  mtf "the minimized rule without the way back's end (C14: Clock in its tile listed as full screen until Settings came back, later the third window's question)" 's/\n            DMSMFitBackInTile\(bundles\);   \/\/ \(one of them[^\n]*\n/\n/'
  mtf "the one-window rule without it (a window back alone, filling, kept as full screen's)" 's/\n            DMSMFitBackInTile\(bundles\);   \/\/ \(the one[^\n]*\n/\n/'
  # (the H-round review of H3, finding 1)
  mtf "the one-window rule's call before its fill branch, as H3 first had it (Notes alone in its own stage, in no tile: \"its tile again\", way back gone)" 's/\n(        if \(one && gSMFitSlots\.count == 1 && \[gSMFitSlots\[one\] isEqualToString:\@"fill"\]\) \{\n)            (DMSMFitBackInTile\(bundles\);   \/\/ \(the one[^\n]*\n)/\n        $2$1/'
  mtf "the way back ended for a window whose tile was taken (G1: it takes part with the tile it left when it joins)" 's/\[gSMFitWentFull containsObject:k\] && gSMFitSlots\[k\]\) \[back addObject:k\];/[gSMFitWentFull containsObject:k]) [back addObject:k];/'
  mtf "the arrangement left always dropped (another window full screen out of sight lost its way back)" 's/    if \(!named\) gSMFitSlotsBeforeFull = nil;/    gSMFitSlotsBeforeFull = nil;/'
  mtf "the arrangement left never dropped by it (smfit kept \"arrangement left\" for the window back in its tile)" 's/    if \(!named\) gSMFitSlotsBeforeFull = nil;\n//'
  mtf "the way back ended but nothing logged (\"its tile again\" only once Settings came back, as on the iPad 2)" 's/        DMLog\(\[NSString stringWithFormat:@"\[sm\] Fit to Window: %@ back from full screen -- its tile again \(%@\)", DMSMKeyText\(k\), gSMFitSlots\[k\]\]\);\n//'
  # (the file before this fix: it fails as the review of F1-F4 read it, item 5 -- the two windows on screen tiled again as a pair, the way back dropped,
  #  the third window's question at the launch and at the return)
  for c in d1eb4882 35434141; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/before.x"
    run "$W/before.x" "$W/before" q; n=$?
    want=("1. Settings and Safari over the full-screen Notes: they keep their tiles" "2. the desktop tapped in the strip, Notes full screen in its own stage: Settings and Safari keep their tiles"
          "2. ... and Notes keeps its way back" "2. Notes opened from the Dock now: no third window's question before its launch" "2. Notes back on the desktop as a window: its tile again, no third window's question"
          "3. Maps opens on the desktop: tiled with Settings; Notes keeps its way back" "3. Notes back from full screen: tiled with the two, no third window's question"
          "8. a size given to Notes while full screen, then the desktop: the tiles kept while Notes is full screen")
    miss=0; for w in "${want[@]}"; do /usr/bin/grep -qF "FAIL  $w" "$W/before/out" || { echo "      (the file before: no FAIL line for \"$w\")"; miss=1; }; done
    if [ $n -gt 0 ] && [ $n -lt 99 ] && [ $miss = 0 ]; then echo "PASS  the file before this fix ($c) fails $n check(s), every one the review named (the pair tiled again, the question at the launch and the return)"
    else echo "FAIL  the file before this fix ($c): $n failed, not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before this fix are not in this tree's history: that comparison left out)"; fi
  # (the file before G2: on our Stage Manager engine the free window's tile stayed until it closed -- with two tiles Settings kept its half; with
  #  three, Fit's look already tiled the two left again, so that row passes there)
  for c in 3349eed7 b7a8f6a1; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/beforeg2.x"
    run "$W/beforeg2.x" "$W/beforeg2" q; n=$?
    want=("9. two tiles, Notes back from full screen as a free window: Settings fills at once" "9. ... then Notes quits: nothing more (Settings stays filling)"
          "9. from its Dock icon instead (Notes full screen in a stage of its own, joining the desktop free): Settings fills at once")
    miss=0; for w in "${want[@]}"; do /usr/bin/grep -qF "FAIL  $w" "$W/beforeg2/out" || { echo "      (the file before G2: no FAIL line for \"$w\")"; miss=1; }; done
    if [ $n -gt 0 ] && [ $n -lt 99 ] && [ $miss = 0 ]; then echo "PASS  the file before G2 ($c) fails $n check(s): the free window's tile kept until it closed (Settings in its half)"
    else echo "FAIL  the file before G2 ($c): $n failed, not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before G2 are not in this tree's history: that comparison left out)"; fi
  # (the file before the review's fix: a window back as one Fit tiles took its old tile again -- two tiles with Notes on the right, kept there; three,
  #  the bottom right quarter -- and with the arrangement it left still naming it, it was never asked about as a new window)
  for c in 1be5be97 34f591ab; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/beforeh1.x"
    run "$W/beforeh1.x" "$W/beforeh1" q; n=$?
    want=("10. two tiles, Notes back as a window Fit tiles: its tile and way back go, Settings keeps its half (no close-up)"
          "10. ... Fit's look tiles it as a new window: Notes the left half, Settings the right one (as the other engines)"
          "10. ... three tiles: Notes the left half, Safari the top right, Settings the bottom right, no question (as the other engines)"
          "10. from its Dock icon instead (a stage of its own): Notes the left half, Settings the right one"
          "10. ... Notes then a new window next to two halves: asked where it goes, as on the other engines")
    miss=0; for w in "${want[@]}"; do /usr/bin/grep -qF "FAIL  $w" "$W/beforeh1/out" || { echo "      (the file before the review's fix: no FAIL line for \"$w\")"; miss=1; }; done
    if [ $n -gt 0 ] && [ $n -lt 99 ] && [ $miss = 0 ]; then echo "PASS  the file before the review's fix ($c) fails $n check(s): the window back as one Fit tiles took its old tile again"
    else echo "FAIL  the file before the review's fix ($c): $n failed, not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before the review's fix are not in this tree's history: that comparison left out)"; fi
  # (the file before H3: Clock back in its tile stayed full screen's while Settings stayed minimized -- the iPad 2's C14 -- and what that led to)
  for c in 9fd96881 f166cd70; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/beforeh3.x"
    run "$W/beforeh3.x" "$W/beforeh3" q; n=$?
    want=("11. C14: ... and Clock is full screen's no more: its way back used there, \"its tile again\" now (smfit: full screen none, arrangement left none)"
          "11. C14: Settings back from the Dock: the three tiles as they were, nothing back from full screen any more"
          "11. ... Clock back: tiled with the two, no third window's question (decision b)"
          "11. Settings quit while Notes was full screen, Notes back alone: it fills, its way back used"
          "11. ... Notes back: tiled with the two, no third window's question")
    miss=0; for w in "${want[@]}"; do /usr/bin/grep -qF "FAIL  $w" "$W/beforeh3/out" || { echo "      (the file before H3: no FAIL line for \"$w\")"; miss=1; }; done
    if [ $n -gt 0 ] && [ $n -lt 99 ] && [ $miss = 0 ] && [ -z "$(/usr/bin/grep '^FAIL  ' "$W/beforeh3/out" | /usr/bin/grep -v '^FAIL  11\. ')" ]; then echo "PASS  the file before H3 ($c) fails $n check(s), all in case 11: the window back in its tile kept as full screen's (C14), and the third window's question it led to"
    else echo "FAIL  the file before H3 ($c): $n failed, not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before H3 are not in this tree's history: that comparison left out)"; fi
  # (the file before the H-round review's fix: H3 as first committed -- Notes back alone in its own stage, in no tile, was done with its way back
  #  there: "its tile again" logged for it, smfit full screen none, and nothing of it left for when it joined the desktop)
  for c in 2e54542b b2316ceb; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/beforeh3r.x"
    run "$W/beforeh3r.x" "$W/beforeh3r" q; n=$?
    want=("11. L-7: Notes back alone in its own stage, its tile kept, Settings on the desktop: nothing laid out, Notes keeps its way back (no \"its tile again\")"
          "11. L-7: ... the desktop in front again: Notes still keeps its way back"
          "11. L-7: ... Notes joins the desktop: \"its tile again\" there, the two halves, no question")
    miss=0; for w in "${want[@]}"; do /usr/bin/grep -qF "FAIL  $w" "$W/beforeh3r/out" || { echo "      (the file before the review's fix: no FAIL line for \"$w\")"; miss=1; }; done
    if [ $n -gt 0 ] && [ $n -lt 99 ] && [ $miss = 0 ] && [ -z "$(/usr/bin/grep '^FAIL  ' "$W/beforeh3r/out" | /usr/bin/grep -v '^FAIL  11\. L-7: ')" ]; then echo "PASS  the file before the H-round review's fix ($c) fails $n check(s), only the L-7 ones: \"its tile again\" for a window alone in its own stage, in no tile"
    else echo "FAIL  the file before the H-round review's fix ($c): $n failed, not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before the H-round review's fix are not in this tree's history: that comparison left out)"; fi
fi
exit $rc
