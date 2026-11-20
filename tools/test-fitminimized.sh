#!/bin/bash
# test-fitminimized.sh: KT's decision A (19 Nov, 1.8.8 H2): minimized tiled windows keep their tiles on every engine. Aerial, Zetsu and MilkyWay4
# (test-fitminimized.m, rows Z8, Z11 and Z11c of p03): a window that opens while every window of the arrangement is minimized opens on its own and
# the arrangement stays (it joins the tiles at a minimized window's return: DMFitShownAgain), one that opens next to a tiled window on screen and a
# minimized one takes the first tile and the minimized one keeps its own, the close-ups with no window on screen keep the minimized windows in the
# plan, the green light's way back rejoins next to a minimized tile, a minimized window is put in its tile out of sight. Our Stage Manager engine
# (test-fitminimized-sm.m, rows C14 and C15 of p03): the launch's open-in-tile and Fit's look plan with the arrangement's minimized windows
# (DMSMFitKeptAway), so a window opened from the Dock with one tile minimized no longer takes the pair and the minimized window comes back into its
# tile with no question. The real code is cut out of statusbar/StatusBar.x (FM_SB_X: another copy, e.g. the code before the fix) and run on the Mac
# (Aerial's side as Mac Catalyst, in a release and a DEBUG build); then the site checks; then made-to-fail copies; then the file before H2
# (5a9ff095, or its -reg twin 82c24a91), which must fail every row the device failed, on every engine.
# The H2-H5 review's fixes (20 Nov), each with its rows: R1 the full-screen record's app back from the Dock next to a window that opened on its
# own keeps the minimized tiles (finding 1); R2 the close-ups with two or more windows on screen keep a minimized tile, one on screen fills alone
# (O1; finding 2); R3 the Mac Switcher -- a window brought here meets the minimized tiles as a window that opens, a tiled window moved away
# closes up by the same rule, our Stage Manager engine's move too (finding 3); R5 the green light's way back takes the windows that opened on their
# own into the tiles, and Aerial's with no entrance cover is placed as Zetsu's and MilkyWay4's, not cascaded (finding 5); R6 a minimized window put
# in its tile notes its layout, which a turn reads (finding 6); then the file before those
# fixes (ef8ed7fc, or cea5cd20), which must fail each of their rows.
# R2 on our Stage Manager engine (p07 on the iPad 2, 20 Nov): Stage Manager's own Close (or ours) lays the windows left out in its own transition
# (DMSMPlacesInClose, cut as written with DMSMItemFor), and its plan keeps the arrangement's minimized windows by FitPlan.h's close-up rule, as
# Zetsu's close-up; then the file before that fix (8cd44f8a, or 5adf1c79), which must fail those rows.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${FM_SB_X:-../statusbar/StatusBar.x}
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
f1() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && (/^}/ || /^static .*\{ .*\}( *\/\/.*)?$/) {exit}' "$2"; }   # f1 <first line> <file>: to its closing brace
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }
has() { /usr/bin/grep -qF -e "$2" "$1"; }
CASCADE='static void DMCascadeStage(UIView *stage) {'
KEEPS='static BOOL DMFitKeepsTile(UIView *s) {'; ALONE='static const void *kStageFitAloneKey = &kStageFitAloneKey;'
LEFTAT='static NSMutableArray<NSString *> *DMFitLeftAtCloseUp(NSArray<NSString *> *candidates) {'
BESIDE='static BOOL DMFitOpensBesideMinimized(UIView *stage, NSString *me, NSMutableArray<NSString *> *group, NSArray<NSString *> *loose) {'
MININ='static NSArray<NSString *> *DMSMFitMinimizedIn(NSArray<NSString *> *keys, NSDictionary<NSString *, NSString *> *slots) {'
NOTE='static void DMStageSetLayoutNote(UIView *st, id saved) {'; NOTEKEY='static const void *kStageLayoutNameKey = &kStageLayoutNameKey;'   # (the layout a window is noted in: DMFitPlaceAway notes its tile's, the H2-H5 review fix 6)
ALONEJOIN='static NSArray<NSString *> *DMFitAloneJoin(NSArray<NSString *> *part, NSMutableArray<NSString *> *fresh) {'
ASKED='static BOOL DMAerialAskedPlaceTake(NSString *bundle, CGRect *frame) {'
MSWFNS=('static NSDictionary *DMMSWFitWithout(NSDictionary *fit, NSString *b) {' 'static BOOL DMMSWFitBringHere(NSString *b, NSInteger fromId, BOOL join, NSString **askLeft, NSString **askRight) {'
        'static BOOL DMMSWFitMove(NSString *b, NSInteger toId) {')   # (MacSwitcher.h: a window brought here, one moved away -- the H2-H5 review, finding 3)
SHOWN='static void DMFitShownAgain(NSString *bundleID) {'; AWAYP='static void DMFitPlaceAway(UIView *stage, CGRect frame) {'
KEPTAWAY='static NSArray<NSString *> *DMSMFitKeptAway(NSArray<NSString *> *keys, NSDictionary<NSString *, NSString *> *slots) {'
JOIN='static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {'
INCLOSE='static void DMSMPlacesInClose(id ctx) {'; ITEMFOR='static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {'   # (Stage Manager's own Close, R2 of p07)
SMFNS=('static NSArray<NSString *> *DMDefaultSlotNames(NSUInteger n) {' 'static void DMSMFitForgetClosed(NSString *opening) {' 'static NSSet<NSString *> *DMSMFitFullAway(NSSet<NSString *> *onScreen) {'
       'static void DMSMFitBackInTile(NSArray<NSString *> *keys) {' 'static void DMSMFitTick(BOOL force) {'
       'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {')

# Aerial, Zetsu and MilkyWay4: the Fit code a window meets (test-fitgreen.sh's cut, H2's functions), DMCascadeStage's Fit part as written
cut_engines() {   # $1 StatusBar.x, $2 out dir, $3 MacSwitcher.h (of the same tree)
  local X=$1 d=$2 M=$3 h
  {
    for h in 'static NSMutableSet<NSString *> *gFreeWindows;' 'static BOOL gMoveKeepsOrder = NO;' 'static NSMutableArray<NSString *> *gFitGroup = nil;' \
             'static NSMutableDictionary<NSString *, NSString *> *gFitSlots = nil;' 'static const void *kStageClosingKey = &kStageClosingKey;' \
             'static const void *kStageGoingFullKey = &kStageGoingFullKey;' 'static const void *kStageEnteringKey = &kStageEnteringKey;' 'static BOOL gStageFrameBypass = NO;'; do
      [ -n "$(line "$X" "$h")" ] || { echo "MISSING $h" >&2; return 99; }; line "$X" "$h"
    done
    if has "$X" "$ALONE"; then line "$X" "$ALONE"; fi
    for h in 'static BOOL DMStageTakesPartInFit(UIView *s) {' 'static void DMFitGroupForget(NSString *bundleID) {' 'static void DMAssignTilesKeepingPlaces(NSString *fresh) {' \
             'static NSString *DMTilesText(NSArray<NSString *> *order, NSDictionary<NSString *, NSString *> *slots) {'; do
      [ -n "$(cutfn "$X" "$h")" ] || { echo "MISSING $h" >&2; return 99; }; cutfn "$X" "$h"
    done
    if has "$X" "$KEEPS"; then cutfn "$X" "$KEEPS"; fi
    if has "$X" "$LEFTAT"; then cutfn "$X" "$LEFTAT"; fi
    if has "$X" "$NOTE"; then line "$X" "$NOTEKEY"; cutfn "$X" "$NOTE"; fi
    if has "$X" "$AWAYP"; then cutfn "$X" "$AWAYP"; fi
    cutfn "$X" 'static void DMApplyGroupSlots(UIView *fresh) {'
    line "$X" 'static NSString *gFSFitBundle; static NSArray<NSString *> *gFSFitGroup;'; line "$X" 'static BOOL gFSFitLeft = NO;'; line "$X" 'static BOOL gFSFitBack = NO;'
    if has "$X" "$ALONEJOIN"; then cutfn "$X" "$ALONEJOIN"; fi
    # (Aerial's way back with no entrance cover, the H2-H5 review's fix 5: the window asked for is placed, not cascaded -- the ask's globals, the
    #  take, the placed mark, and the cascade's lines for it as written, KCascadeAsked; the file before: none, so the cascade's Fit part runs)
    line "$X" 'static NSString *gA5EntranceBundle = nil;'; line "$X" 'static CGRect gA5EntranceFrame = {{0, 0}, {0, 0}};'; line "$X" 'static CFTimeInterval gA5EntranceAt = 0;'
    line "$X" 'static const void *kStageCascadedKey = &kStageCascadedKey;'; cutfn "$X" 'static void DMMarkStagePlaced(UIView *stage, CGRect frame) {'
    if has "$X" "$ASKED"; then
      cutfn "$X" "$ASKED"
      echo 'static BOOL KCascadeAsked(UIView *stage, NSString *me, CGRect base) {'
      cutfn "$X" "$CASCADE" | awk 'index($0, "    CGRect askedAt = CGRectNull;") == 1 {f=1} f {print} f && $0 == "    }" {exit}' | sed -e 's/^        return;$/        return YES;/'
      echo '    return NO;'; echo '}'; echo '#define K_HAS_ASKED 1'
    fi
    for h in 'static void DMRememberFitForFullScreen(NSString *bundleID) {' 'static void DMFitForgetFullScreenTile(NSString *bundleID, NSString *why) {' \
             'static void DMFitForgetFullScreenWayBack(NSString *bundleID, NSString *why) {' 'static void DMFitFullScreenOpensNew(NSString *bundleID) {' \
             'static void DMFitFullScreenTileGoes(NSString *bundleID, NSString *why) {' 'static void DMFitFullScreenAppGone(NSString *bundleID) {' \
             'static void DMFitFullScreenBackFree(NSString *bundleID) {' 'static void DMFitRejoinAfterFullScreen(NSString *bundleID) {' 'static void DMMarkFreeWindow(NSString *bundleID) {'; do
      [ -n "$(cutfn "$X" "$h")" ] || { echo "MISSING $h" >&2; return 99; }; cutfn "$X" "$h"
    done
    if has "$X" "$SHOWN"; then cutfn "$X" "$SHOWN"; echo '#define K_HAS_H2 1'; fi
    line "$X" 'BOOL gFitClosureCheckDue = NO;'; line "$X" 'static NSArray<NSString *> *gFitWatchPrevious = nil;'
    for h in 'static void DMFitWatchSync(void) {' 'void DMFitWatchSyncExtern(void) {' 'static void DMWatchFitClosures(void) {'; do cutfn "$X" "$h"; done
    if has "$X" "$BESIDE"; then cutfn "$X" "$BESIDE"; fi
    # (DMCascadeStage's Fit part as written: from its "if (fitOn) {" after the No Fit goto, to the line before "regularWindow:;")
    echo 'static BOOL gKRegular;'
    echo 'static void KCascadeFitPart(UIView *stage, NSString *me, NSArray<UIView *> *others, CGRect base) {'
    echo '    BOOL fitOn = YES; gKRegular = NO;'
    cutfn "$X" "$CASCADE" | awk '/goto regularWindow;   \/\/ \(a free window, No Fit\)/{a=1; next} a && !s && $0 == "    if (fitOn) {" {s=1} s && $0 == "regularWindow:;" {exit} s {print}'
    echo 'regularWindow:; gKRegular = YES;'
    echo '}'
    echo 'static void KCascadeFitLines(NSString *me, BOOL fitOn, int app, BOOL own, BOOL preLaunched) {'; cutfn "$X" "$CASCADE" | /usr/bin/grep -E '^    if \(.*\) DMFitFullScreenOpensNew\(me\);'; echo '}'
    echo 'static void KAppSizeForgetFit(NSString *bundle) {'; cutfn "$X" 'static void DMAppSizeForgetPlace(NSString *bundle) {' | /usr/bin/grep -E '^    DMFitForgetFullScreen[A-Za-z]*\(bundle, '; echo '}'
    # (the Mac Switcher: a window brought from another desktop, a tiled window moved to another one -- MacSwitcher.h as written)
    line "$M" 'static NSMutableDictionary<NSString *, NSDictionary *> *gMSWFit;'
    for h in "${MSWFNS[@]}"; do [ -n "$(cutfn "$M" "$h")" ] || { echo "MISSING $h" >&2; return 99; }; cutfn "$M" "$h"; done
  } > "$d/fm-real.inc" || return 99
  /usr/bin/grep -q '^    if (fitOn) {' "$d/fm-real.inc" && /usr/bin/grep -q 'DMFitForgetFullScreen[A-Za-z]*(bundle, ' "$d/fm-real.inc" || { echo "MISSING the cascade's Fit part or the forget's Fit call" >&2; return 99; }
}
# Our Stage Manager engine: test-smfitfullaway.sh's cut (Fit's look and its helpers), DMSMFitKeptAway, and the launch's open-in-tile as written
# (KJoinPlan: DMSMAddToStage's plan block; KJoinAfter: the arrangement it leaves once the request is asked)
cut_sm() {   # $1 StatusBar.x, $2 out dir, $3 MacSwitcherSM.h (of the same tree)
  local X=$1 d=$2 MS=$3 h
  for h in "${SMFNS[@]}"; do [ -n "$(f1 "$h" "$X")" ] || { echo "MISSING $h" >&2; return 99; }; done
  {
    for h in "${SMFNS[@]:0:3}"; do f1 "$h" "$X"; done
    if has "$X" "$MININ"; then f1 "$MININ" "$X"; echo '#define K_HAS_MIN_IN 1'; fi
    if has "$X" "$KEPTAWAY"; then f1 "$KEPTAWAY" "$X"; echo '#define K_HAS_KEPT_AWAY 1'; fi
    for h in "${SMFNS[@]:3}"; do f1 "$h" "$X"; done
    echo 'static NSMutableArray *KJoinPlan(NSString *bundle, NSString *newKey, NSDictionary *map, id al, id attrs, id entity, long role, NSDictionary **fitPlanOut) {'
    echo '    BOOL main = YES, asWindow = YES;'
    echo '    NSMutableArray *addPlan = [NSMutableArray arrayWithObject:@[entity, @(role), attrs]];'
    echo '    NSDictionary *fitPlan = nil;'
    f1 "$JOIN" "$X" | awk 'index($0, "    if (main && asWindow && DMFitEnabled() && !DMSMKeySetHas(gSMFreeWindows, newKey)") == 1 {f=1} f {print} f && $0 == "    }" {exit}'
    echo '    *fitPlanOut = fitPlan;'
    echo '    return addPlan;'
    echo '}'
    echo 'static void KJoinAfter(NSString *newKeyC, NSDictionary *fitPlanC, NSUInteger laidC) {'
    f1 "$JOIN" "$X" | awk 'index($0, "        if (fitPlanC) {") == 1 {f=1} f {print} f && $0 == "        }" {exit}'
    echo '}'
    # (the Mac Switcher's move of a tiled window to another desktop: DMMSWSMMoveFinish's Fit block as written -- MacSwitcherSM.h)
    echo 'static void KSMMoveFit(NSString *b) {'
    f1 'static void DMMSWSMMoveFinish(NSString *b, NSInteger toId) {' "$MS" | awk 'index($0, "    BOOL wasTiled = gSMFitSlots[b] != nil;") == 1 {f=1} f {print} f && $0 == "    }" {exit}'
    echo '}'
    # (Stage Manager's own Close: the windows left take their tiles in its transition, before Fit's look -- DMSMPlacesInClose as written, R2 of p07)
    f1 "$ITEMFOR" "$X"; f1 "$INCLOSE" "$X"
  } > "$d/fms-real.inc"
  /usr/bin/grep -q 'gSMFitSlots = plan;' "$d/fms-real.inc" || { echo "MISSING the Mac Switcher's move block (MacSwitcherSM.h)" >&2; return 99; }
  /usr/bin/grep -qF 'DM_FEATURE_MARK("sm-fit-in-close");' "$d/fms-real.inc" && /usr/bin/grep -qF 'NSUInteger i = DMSMKeyPick(wins, key);' "$d/fms-real.inc" || { echo "MISSING Stage Manager's own Close (DMSMPlacesInClose) or DMSMItemFor" >&2; return 99; }
  [ "$(/usr/bin/grep -c 'sm-fit-open-in-tile' "$d/fms-real.inc")" = 1 ] && /usr/bin/grep -q 'gSMFitSlots = \[fitPlanC mutableCopy\];' "$d/fms-real.inc" || { echo "MISSING the join's plan block or its arrangement" >&2; return 99; }
}
run() {   # $1 StatusBar.x, $2 work dir, $3 quiet, $4 MacSwitcher.h, $5 MacSwitcherSM.h (default: this tree's); 0 all pass, 1 a check failed (their
          # number in RUN_FAILS, counted from the outputs), 99 the code could not be cut out or built; the outputs in $2/out-*
  local X=$1 d=$2 q=$3 M=${4:-../statusbar/MacSwitcher.h} MS=${5:-../statusbar/MacSwitcherSM.h} n=0 r dbg
  mkdir -p "$d"
  cut_engines "$X" "$d" "$M" || { echo "FAIL  $X: the engines' code could not be cut out"; return 99; }
  cut_sm "$X" "$d" "$MS" || { echo "FAIL  $X: the Stage Manager engine's code could not be cut out"; return 99; }
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-label -Werror=implicit-function-declaration -I"$d" \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-fitminimized.m 2>"$d/cc$dbg.txt" \
      || { cat "$d/cc$dbg.txt"; echo "FAIL  the engines' real code did not build (DEBUG=$dbg)"; return 99; }
  done
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" -framework Foundation -framework CoreGraphics -framework QuartzCore \
        -o "$d/s" test-fitminimized-sm.m 2> "$d/ccs.txt" || { cat "$d/ccs.txt"; echo "FAIL  the Stage Manager engine's real code did not build"; return 99; }
  "$d/t0" > "$d/out-engines"; r=$?
  "$d/t1" > "$d/out-engines-debug"; [ $? = $r ] && cmp -s "$d/out-engines" "$d/out-engines-debug" || { echo "FAIL  the DEBUG build answers otherwise"; n=$((n + 1)); }
  "$d/s" > "$d/out-sm"
  n=$((n + $(/usr/bin/grep -c '^FAIL  ' "$d/out-engines") + $(/usr/bin/grep -c '^FAIL  ' "$d/out-sm")))   # (not the exit codes: 256 failures read as none)
  [ -n "$q" ] || { cat "$d/out-engines"; echo "(the DEBUG build: the same)"; cat "$d/out-sm"; }
  RUN_FAILS=$n
  [ $n = 0 ]
}
RUN_FAILS=0
run "$X0" "$W/real"; rc=$?
[ $rc = 99 ] && exit 1
X=$X0
# (site checks) DMSurfaceWindowForApp's three branches call DMFitShownAgain while the window is still minimized, before it is shown: Zetsu's
# before DMZetsuSurface, Aerial's before its frame is enforced and the stage restored, MilkyWay4's first in its minimized block; nowhere else
if cutfn "$X" 'static BOOL DMSurfaceWindowForApp(NSString *bundleID) {' > "$W/surf" && [ "$(/usr/bin/grep -c 'DMFitShownAgain(' "$W/surf")" = 3 ] && [ "$(/usr/bin/grep -c 'DMFitShownAgain(' "$X")" = 5 ] \
   && awk 'index($0, "        if (DMStageMinimized(zw)) DMFitShownAgain(bundleID);") == 1 {a=NR} index($0, "        DMZetsuSurface(zw);") == 1 {b=NR}
           index($0, "        if (minimized) DMFitShownAgain(bundleID);") == 1 {c=NR} index($0, "        DMEnforceStageFrame(stage, @\"a relaunch\");") == 1 {e=NR} index($0, "        if ([objc_getAssociatedObject(stage, kStageHiddenKey) boolValue]) DMRestoreStage(stage);") == 1 {r=NR}
           index($0, "    if (DMWindowMinimized(window)) {") == 1 {m=NR} index($0, "        DMFitShownAgain(bundleID);") == 1 {s=NR} index($0, "        DMRestoreAnimate(window);") == 1 {t=NR}
           END {exit !(a && b == a + 1 && c && e == c + 1 && r > e && m && s == m + 1 && t > s)}' "$W/surf" \
   && awk -v s="$SHOWN" 'index($0, "static void DMFitShownAgain(NSString *bundleID);") == 1 {d=NR} index($0, "static BOOL DMSurfaceWindowForApp(NSString *bundleID) {") == 1 {u=NR} index($0, s) == 1 {f=NR} END {exit !(d && u == d + 1 && f > u)}' "$X"; then
  echo "PASS  StatusBar.x: DMSurfaceWindowForApp's Zetsu, Aerial and MilkyWay4 branches call DMFitShownAgain while the window is still minimized, before it is shown; nowhere else"
else echo "FAIL  StatusBar.x: DMFitShownAgain's three calls in DMSurfaceWindowForApp not as expected"; rc=$((rc + 1)); fi
# (site checks) the cascade's Fit part keeps a minimized window (DMFitKeepsTile, once); DMApplyGroupSlots puts a minimized one in its tile out of
# sight, first in its loop; the turn's rule is FitPlan.h's (MSBDFitTileStaysAtTurn) as before; the three-window question needs both halves on screen
if cutfn "$X" "$CASCADE" > "$W/casc" && /usr/bin/grep -qxF '        for (NSString *b in [gFitGroup copy]) if (!DMFitKeepsTile(DMStageForBundle(b))) [gFitGroup removeObject:b];' "$W/casc" \
   && ! /usr/bin/grep -qF 'if (!DMStageTakesPartInFit(DMStageForBundle(b))) [gFitGroup removeObject:b];' "$W/casc" \
   && /usr/bin/grep -qxF '            if (!DMStageTakesPartInFit(a) || !DMStageTakesPartInFit(b)) a = b = nil;' "$W/casc" \
   && cutfn "$X" 'static void DMApplyGroupSlots(UIView *fresh) {' | awk 'index($0, "        if (!s || CGRectIsNull(f)) continue;") == 1 {c=NR} index($0, "        if (s != fresh && (s.hidden || DMStageMinimized(s))) { DMFitPlaceAway(s, f); continue; }") == 1 {p=NR} END {exit !(c && p == c + 1)}' \
   && cutfn "$X" "$KEEPS" | /usr/bin/grep -qF 'return MSBDFitTileStaysAtTurn(s != nil, s && [objc_getAssociatedObject(s, kStageClosingKey) boolValue], b.length && [gFreeWindows containsObject:b], s && !s.hidden && !DMStageMinimized(s), s && DMStageMinimized(s));' \
   && [ "$(/usr/bin/grep -c 'DMFitKeepsTile(' "$X")" = 4 ] && cutfn "$X" "$LEFTAT" | /usr/bin/grep -qF 'BOOL keep = MSBDFitMinimizedStayAtCloseUp(shown);' \
   && cutfn "$X" 'static void DMFitFullScreenTileGoes(NSString *bundleID, NSString *why) {' | /usr/bin/grep -qxF '    NSMutableArray<NSString *> *g = DMFitLeftAtCloseUp(gFitGroup);' \
   && cutfn "$X" 'static void DMWatchFitClosures(void) {' | /usr/bin/grep -qxF '    NSMutableArray<NSString *> *left = DMFitLeftAtCloseUp(stay);' \
   && [ "$(/usr/bin/grep -c 'DMFitLeftAtCloseUp(' "$X")" -ge 3 ]; then
  echo "PASS  StatusBar.x: the cascade keeps a minimized window (DMFitKeepsTile: FitPlan.h's turn rule), the question needs both halves on screen, DMApplyGroupSlots puts a minimized window in its tile out of sight; DMFitKeepsTile in the cascade, the rejoin and DMFitLeftAtCloseUp only; the closure watcher and G2's close-up close up by DMFitLeftAtCloseUp (FitPlan.h's close-up rule)"
else echo "FAIL  StatusBar.x: H2's sites in the cascade, DMApplyGroupSlots or DMFitKeepsTile's uses not as expected"; rc=$((rc + 1)); fi
# (site checks) Stage Manager: DMSMFitKeptAway in the join right before its taking-part line and in the tick right before its own, once each
if f1 "$JOIN" "$X" | awk 'index($0, "        [keys addObjectsFromArray:DMSMFitKeptAway(keys, slotsNow)];") == 1 {k=NR} index($0, "        NSArray<NSString *> *part = DMTestFlag(\"/tmp/msb-fitloose-asbuilt\") ? keys : DMSMFitTakingPart(keys, slotsNow, gSMFitLoose, NULL);") == 1 {p=NR} END {exit !(k && p > k && p <= k + 3)}' \
   && f1 'static void DMSMFitTick(BOOL force) {' "$X" | awk 'index($0, "        keptAway = DMSMFitKeptAway(bundles, slotsForPart ?: gSMFitSlots);") == 1 {k=NR} index($0, "        NSArray<NSString *> *part = DMSMFitTakingPart(keptAway.count ? [bundles arrayByAddingObjectsFromArray:keptAway] : bundles, slotsForPart ?: gSMFitSlots, gSMFitLoose, &looseNow);") == 1 {p=NR}
        index($0, "        [bundles removeObjectsInArray:keptAway];") == 1 {s=NR} index($0, "        bundles = [part mutableCopy];") == 1 {b=NR} END {exit !(k && p == k + 1 && b > p && s == b + 1)}' \
   && [ "$(/usr/bin/grep -c 'DMSMFitKeptAway(' "$X")" = 4 ] && awk -v k="$KEPTAWAY" 'index($0, "static NSArray<NSString *> *DMSMFitKeptAway(NSArray<NSString *> *keys, NSDictionary<NSString *, NSString *> *slots);") == 1 {d=NR} index($0, "static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {") == 1 {j=NR} index($0, k) == 1 {f=NR} index($0, "static void DMSMFitTick(BOOL force) {") == 1 {t=NR} END {exit !(d && j == d + 1 && f > j && t > f)}' "$X" \
   && { f1 "$MININ" "$X"; f1 "$KEPTAWAY" "$X"; } > "$W/ka" && /usr/bin/grep -qF 'if (there && DMSMIsMinimized(k)) [away addObject:k];' "$W/ka" && /usr/bin/grep -qxF '    return DMSMFitMinimizedIn(keys, slots);' "$W/ka" \
   && ! /usr/bin/grep -q 'DMSMApply\|gSMFitSlots\|UIKit\|UIScreen\|UIApplication\|DMSMFitFullAway' "$W/ka"; then
  echo "PASS  StatusBar.x: DMSMFitKeptAway before the tick, read only, minimized windows only; the join and the tick add it right before their taking-part line, the tick lays out the windows on screen only"
else echo "FAIL  StatusBar.x: DMSMFitKeptAway or its two uses not as expected"; rc=$((rc + 1)); fi
# (site checks) the Mac Switcher (the H2-H5 review, finding 3): a window brought here meets this desktop's minimized tiles as a window that opens
# (DMFitKeepsTile, DMFitOpensBesideMinimized, the question with both halves on screen); a tiled window moved away closes the tiles up by the rule of
# every close-up (DMFitLeftAtCloseUp; Stage Manager: FitPlan.h's rule with DMSMFitMinimizedIn, right before its plan)
MSH=../statusbar/MacSwitcher.h; MSS=../statusbar/MacSwitcherSM.h
if cutfn "$MSH" "${MSWFNS[1]}" > "$W/bh" && /usr/bin/grep -qxF '    for (NSString *x in gFitGroup) if (![x isEqualToString:b] && DMFitKeepsTile(DMStageForBundle(x))) [group addObject:x];' "$W/bh" \
   && awk 'index($0, "    if (DMFitOpensBesideMinimized(bst, b, group, loose)) {") == 1 {o=NR} index($0, "    NSArray<NSString *> *joined = MSBDFitWhenOneOpens(b, group, loose);") == 1 {j=NR} END {exit !(o && j > o)}' "$W/bh" \
   && /usr/bin/grep -qF 'NSString *s0 = both ? DMSlotNameForFrame(' "$W/bh" \
   && cutfn "$MSH" "${MSWFNS[2]}" | /usr/bin/grep -qxF '        NSMutableArray<NSString *> *left = DMFitLeftAtCloseUp(gFitGroup);' \
   && f1 'static void DMMSWSMMoveFinish(NSString *b, NSInteger toId) {' "$MSS" | awk 'index($0, "        if (MSBDFitMinimizedStayAtCloseUp(items.count - full.count)) [left addObjectsFromArray:DMSMFitMinimizedIn(left, was)];") == 1 {r=NR}
        index($0, "        NSMutableDictionary<NSString *, NSString *> *plan = left.count ? [MSBDFitPlanKeepingPlaces(left, was) mutableCopy] : nil;") == 1 {p=NR} END {exit !(r && p == r + 1)}' \
   && [ "$(/usr/bin/grep -c 'DMFitOpensBesideMinimized(' "$X")" = 2 ] && [ "$(/usr/bin/grep -c 'DMFitOpensBesideMinimized(' "$MSH")" = 1 ] && [ "$(/usr/bin/grep -c 'DMSMFitMinimizedIn(' "$MSS")" = 1 ]; then
  echo "PASS  MacSwitcher.h / MacSwitcherSM.h: a window brought here keeps this desktop's minimized tiles (or opens on its own), the question needs both halves on screen; a tiled window moved away closes up by the close-up rule, on every engine"
else echo "FAIL  MacSwitcher.h / MacSwitcherSM.h: the Mac Switcher's Fit sites not as expected"; rc=$((rc + 1)); fi
# (site checks) Stage Manager's own Close (R2 of p07): the arrangement's minimized windows join its plan by FitPlan.h's close-up rule, none of the
# windows it takes away, right before the plan; only the windows in its roles are written
if f1 "$INCLOSE" "$X" > "$W/inclose" && awk 'index($0, "        if (MSBDFitMinimizedStayAtCloseUp(keys.count)) keptMin = DMSMFitMinimizedIn([keys arrayByAddingObjectsFromArray:going], gSMFitSlots);") == 1 {r=NR}
        index($0, "        [keys addObjectsFromArray:keptMin];") == 1 {a=NR} index($0, "        plan = MSBDFitPlanKeepingPlaces(keys, gSMFitSlots);") == 1 {p=NR} END {exit !(r && a == r + 1 && p == a + 1)}' "$W/inclose" \
   && /usr/bin/grep -qF 'for (id e in removals) { NSString *k = DMSMIsEntity(e) ? DMSMEntityKey(e) : nil; if (k) [going addObject:k]; if (k && gSMFitSlots[k]) goingTiled = YES; }' "$W/inclose" \
   && /usr/bin/grep -qF '    for (NSArray *w in stay) {' "$W/inclose" && [ "$(/usr/bin/grep -c 'keptMin' "$W/inclose")" = 4 ] \
   && awk -v m="$MININ" -v c="$INCLOSE" 'index($0, m) == 1 {a=NR} index($0, c) == 1 {b=NR} END {exit !(a && b > a)}' "$X"; then
  echo "PASS  StatusBar.x: Stage Manager's own Close keeps the arrangement's minimized windows in its plan by the close-up rule (DMSMFitMinimizedIn, none of the windows going), right before the plan; it writes the windows in its roles only"
else echo "FAIL  StatusBar.x: DMSMPlacesInClose's minimized windows not as expected"; rc=$((rc + 1)); fi
# (site checks) the way back (the H2-H5 review, finding 5): DMFitShownAgain and the rejoin take the windows that opened on their own through
# DMFitAloneJoin, the rejoin before its two-window test; the cascade places Aerial's asked window right after its "nothing to do" line and returns,
# before any of its moves or Fit's part; nothing else takes the ask but the entrance
if cutfn "$X" 'static void DMFitRejoinAfterFullScreen(NSString *bundleID) {' | awk 'index($0, "    NSArray<NSString *> *withAlone = DMFitAloneJoin(g, fresh);") == 1 {a=NR} index($0, "    if (g.count < 2) return;") == 1 {t=NR} END {exit !(a && t > a)}' \
   && cutfn "$X" "$SHOWN" | /usr/bin/grep -qF 'NSArray<NSString *> *part = DMFitAloneJoin(gFitGroup, fresh);' && [ "$(/usr/bin/grep -c 'DMFitAloneJoin(' "$X")" = 3 ] \
   && cutfn "$X" "$CASCADE" | awk 'index($0, "    if (!win || !me.length || CGRectIsNull(usable) || CGRectIsEmpty(base)) {") == 1 {n=NR} index($0, "    if (DMActiveEngine() == DMEngineAerial && DMAerialAskedPlaceTake(me, &askedAt)) {") == 1 {a=NR}
        index($0, "        DMMarkStagePlaced(stage, askedAt);") == 1 {m=NR} index($0, "    BOOL preLaunched = ") == 1 {p=NR} END {exit !(n && a == n + 8 && m > a && p > m)}' \
   && [ "$(/usr/bin/grep -c 'DMAerialAskedPlaceTake(' "$X")" = 2 ] && [ "$(/usr/bin/grep -c 'gA5EntranceBundle = nil;' "$X")" = 4 ]; then
  echo "PASS  StatusBar.x: the way back and a minimized window's return take the windows that opened on their own (DMFitAloneJoin); Aerial's asked window with no cover is placed by the cascade before anything else, the ask taken once"
else echo "FAIL  StatusBar.x: the way back's sites (finding 5) not as expected"; rc=$((rc + 1)); fi
# (site checks) a minimized window put in its tile notes the tile's layout (the H2-H5 review, finding 6); the turn tiles an arrangement of two or more
# and puts every other window, an arrangement of one too, back by its note
if cutfn "$X" "$AWAYP" | /usr/bin/grep -qxF '    if (b.length && gFitSlots[b]) DMStageSetLayoutNote(stage, gFitSlots[b]);' \
   && cutfn "$X" 'static void DMRelayoutForOrientation(CGSize oldSize, CGSize newSize) {' > "$W/turn" && /usr/bin/grep -qxF '    BOOL tiled = gFitGroup.count >= 2;' "$W/turn" \
   && /usr/bin/grep -qxF '        NSString *lay = objc_getAssociatedObject(s, kStageLayoutNameKey);' "$W/turn" && /usr/bin/grep -qF 'CGRect f = MSBDTurnPlaceFor(lay.length ? DMLayoutFrame(lay) : CGRectNull,' "$W/turn"; then
  echo "PASS  StatusBar.x: a minimized window put in its tile notes the tile's layout, which the turn reads for a window not tiled with others"
else echo "FAIL  StatusBar.x: DMFitPlaceAway's layout note or the turn's read of it not as expected"; rc=$((rc + 1)); fi
# (the crash map) the new functions are window code: Fit's rule (Aerial / Zetsu / MilkyWay4) and the Stage Manager engine's DMSM rule, both
# windowingEnabled, not App Window Sizes' piece
cat > "$W/rule.py" <<'EOF'
import re, sys
name = "_" + sys.argv[2]
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) >= 4 and p[0] == "sym" and p[1] == "MacStatusBarCore" and re.search(p[2], name):
        print(p[3]); break
EOF
for fnn in DMFitKeepsTile DMFitShownAgain DMFitPlaceAway DMSMFitKeptAway DMFitLeftAtCloseUp DMFitOpensBesideMinimized DMSMFitMinimizedIn DMFitAloneJoin DMAerialAskedPlaceTake; do
  t=$(python3 -I "$W/rule.py" crashmap-rules.txt "$fnn" 2>/dev/null)
  if [ "$t" = windowingEnabled ]; then echo "PASS  crash map: $fnn falls under a windowingEnabled rule (the first sym rule that matches)"
  else echo "FAIL  crash map: $fnn falls under \"$t\""; rc=$((rc + 1)); fi
done

if [ -z "$FM_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x (or, $3 = M / MS, on MacSwitcher.h / MacSwitcherSM.h)
    local d="$W/m$((++k))" c o x="$X0" m=../statusbar/MacSwitcher.h ms=../statusbar/MacSwitcherSM.h
    mkdir -p "$d"
    case "$3" in M) o=$m; c="$d/MacSwitcher.h"; m=$c;; MS) o=$ms; c="$d/MacSwitcherSM.h"; ms=$c;; *) o=$X0; c="$d/StatusBar.x"; x=$c;; esac
    perl -0pe "$2" "$o" > "$c"
    cmp -s "$c" "$o" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=$((rc + 1)); return; }
    run "$x" "$d/w" q "$m" "$ms"; local n=$?
    if [ $n = 1 ]; then echo "PASS  caught: $1 ($RUN_FAILS check(s) fail)"; else echo "FAIL  not caught: $1"; rc=$((rc + 1)); fi
  }
  k=0
  mtf "the cascade's drop as before (a minimized window out of the arrangement when a window opens: Z11c, Z11)" 's/if \(!DMFitKeepsTile\(DMStageForBundle\(b\)\)\) \[gFitGroup removeObject:b\];/if (!DMStageTakesPartInFit(DMStageForBundle(b))) [gFitGroup removeObject:b];/'
  mtf "no window opening on its own (squeezed into a tile next to the minimized ones: the owner's old bug)" 's/(static BOOL DMFitOpensBesideMinimized\([^\n]*\{\n)/$1    return NO;\n/'
  mtf "the full-screen record's app back from the Dock next to a window that opened on its own taken for a new set (Settings' tile forgotten: the H2-H5 review, finding 1)" 's/    if \(!\[gFSFitBundle isEqualToString:me\] \|\| !gFSFitGroup\) \{ for/    if (1) { for/'
  mtf "a window that joined the tiles still marked as opened on its own (DMApplyGroupSlots)" 's/        if \(s\) objc_setAssociatedObject\(s, kStageFitAloneKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);   \/\/ \(in the tiles[^\n]*\n//'
  mtf "no mark for a window that opened on its own (not tiled at a minimized window's return)" 's/        if \(stage\) objc_setAssociatedObject\(stage, kStageFitAloneKey, \@YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);\n//'
  mtf "nothing at a minimized window's return (Z11c: Settings next to Clock in no tile)" 's/(static void DMFitShownAgain\(NSString \*bundleID\) \{\n)/$1    return;\n/'
  mtf "a window placed by the user still taken for one that opened on its own (it slid into a tile at a return)" 's/    if \(s\) objc_setAssociatedObject\(s, kStageFitAloneKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);\n//'
  mtf "the regular windows over the tiles always joining at a return (a window placed by the user taken into the tiles)" 's/\[\(\[objc_getAssociatedObject\(o, kStageFitAloneKey\) boolValue\] \? alone : regular\) addObject:b\];/[alone addObject:b];/'
  mtf "G2's close-up with no window on screen as before (Z8: Settings back at its old half)" 's/    NSMutableArray<NSString \*> \*g = DMFitLeftAtCloseUp\(gFitGroup\);/    NSMutableArray<NSString *> *g = [NSMutableArray array]; for (NSString *b in gFitGroup) if (DMStageTakesPartInFit(DMStageForBundle(b))) [g addObject:b];/'
  mtf "the closure watcher with no window on screen as before (the closed tile kept empty)" 's/    NSMutableArray<NSString \*> \*left = DMFitLeftAtCloseUp\(stay\);/    NSMutableArray<NSString *> *left = [NSMutableArray array]; for (NSString *b in stay) if (DMStageTakesPartInFit(DMStageForBundle(b))) [left addObject:b];/'
  mtf "the close-ups keeping the minimized windows with one on screen too (O1: Settings next to an empty half)" 's/    BOOL keep = MSBDFitMinimizedStayAtCloseUp\(shown\);/    BOOL keep = YES;/'
  mtf "the close-ups keeping the minimized windows only with none on screen, as H2 (four tiles, Clock minimized, Notes quits: Clock's tile goes -- the H2-H5 review, finding 2)" 's/    BOOL keep = MSBDFitMinimizedStayAtCloseUp\(shown\);/    BOOL keep = !shown;/'
  mtf "the way back without the windows that opened on their own (Maps left over Clock's half, outside the tiles: the H2-H5 review, finding 5)" 's/    NSArray<NSString \*> \*withAlone = DMFitAloneJoin\(g, fresh\);/    NSArray<NSString *> *withAlone = nil;/'
  mtf "the way back's old tiles for a set of the same size but other windows (Maps in no tile)" 's/\[\[NSSet setWithArray:g\] isEqualToSet:\[NSSet setWithArray:old\]\] \? \[oldSlots mutableCopy\]/g.count == old.count ? [oldSlots mutableCopy]/'
  mtf "Aerial's way back with no cover through the cascade's Fit part (logged and marked as opened on its own, then tiled)" 's/    if \(DMActiveEngine\(\) == DMEngineAerial && DMAerialAskedPlaceTake\(me, &askedAt\)\) \{/    if (0) {/'
  mtf "the ask for a place taken more than once (a later window of the app put there too)" 's/(    if \(frame\) \*frame = gA5EntranceFrame;\n)    gA5EntranceBundle = nil;\n/$1/'
  mtf "a minimized window put in its tile with its old layout note (Z8, then a turn: Settings back at its old half -- the H2-H5 review, finding 6)" 's/    if \(b.length && gFitSlots\[b\]\) DMStageSetLayoutNote\(stage, gFitSlots\[b\]\);\n//'
  mtf "the green light's way back as before (Clock outside the tiles, Settings' tile dropped)" 's/if \(\[b isEqualToString:bundleID\] \? DMStageTakesPartInFit\(DMStageForBundle\(b\)\) : DMFitKeepsTile\(DMStageForBundle\(b\)\)\) \[g addObject:b\];/if (DMStageTakesPartInFit(DMStageForBundle(b))) [g addObject:b];/'
  mtf "a minimized window slid on its way to its tile (not put there out of sight)" 's/        if \(s != fresh && \(s.hidden \|\| DMStageMinimized\(s\)\)\) \{ DMFitPlaceAway\(s, f\); continue; \}[^\n]*\n//'
  mtf "the three-window question with one half minimized" 's/            if \(!DMStageTakesPartInFit\(a\) \|\| !DMStageTakesPartInFit\(b\)\) a = b = nil;\n//'
  mtf "Stage Manager: the join without the minimized windows (C15: App Store took the pair, Clock asked where it goes)" 's/        \[keys addObjectsFromArray:DMSMFitKeptAway\(keys, slotsNow\)\];\n//'
  mtf "Stage Manager: Fit's look without them (a window opened some other way took the pair)" 's/        keptAway = DMSMFitKeptAway\(bundles, slotsForPart \?: gSMFitSlots\);[^\n]*\n//'
  mtf "Stage Manager: Fit's look laying the minimized windows out with the others" 's/        \[bundles removeObjectsInArray:keptAway\];[^\n]*\n//; s/    if \(keptAway.count\) \{ NSMutableDictionary \*laid = \[plan mutableCopy\]; \[laid removeObjectsForKeys:keptAway\]; keep = plan.count - laid.count; plan = laid; \}\n//'
  mtf "Stage Manager: the minimized windows kept with no window of the arrangement among the windows laid out (two windows opened alone in quarters)" 's/    if \(!tiled\) return \@\[\];\n//'
  mtf "Stage Manager: a window full screen out of sight kept as minimized (G1's way back: Maps opened next to Settings left a quarter empty for Notes)" 's/if \(there && DMSMIsMinimized\(k\)\) \[away addObject:k\];/if (there) [away addObject:k];/'
  mtf "the Mac Switcher: a window brought here drops this desktop's minimized tiles (the H2-H5 review, finding 3)" 's/if \(!\[x isEqualToString:b\] && DMFitKeepsTile\(DMStageForBundle\(x\)\)\) \[group addObject:x\];/if (![x isEqualToString:b] \&\& DMStageTakesPartInFit(DMStageForBundle(x))) [group addObject:x];/' M
  mtf "the Mac Switcher: a window brought here next to minimized tiles only squeezed in, never on its own" 's/    if \(DMFitOpensBesideMinimized\(bst, b, group, loose\)\) \{/    if (0) {/' M
  mtf "the Mac Switcher: the side question for a window brought here with one half minimized" 's/        BOOL both = DMStageTakesPartInFit\(DMStageForBundle\(group\[0\]\)\) && DMStageTakesPartInFit\(DMStageForBundle\(group\[1\]\)\);/        BOOL both = YES;/' M
  mtf "the Mac Switcher: a tiled window moved away drops the minimized tiles left here" 's/        NSMutableArray<NSString \*> \*left = DMFitLeftAtCloseUp\(gFitGroup\);/        NSMutableArray<NSString *> *left = [NSMutableArray array]; for (NSString *x in gFitGroup) { UIView *s = DMStageForBundle(x); if (s \&\& DMStageTakesPartInFit(s)) [left addObject:x]; }/' M
  mtf "the Mac Switcher, Stage Manager: a tiled window moved away drops the minimized tiles left here" 's/        if \(MSBDFitMinimizedStayAtCloseUp\(items.count - full.count\)\) \[left addObjectsFromArray:DMSMFitMinimizedIn\(left, was\)\];\n//' MS
  mtf "the Mac Switcher, Stage Manager: the minimized tiles kept with one window left on screen too (O1)" 's/        if \(MSBDFitMinimizedStayAtCloseUp\(items.count - full.count\)\) \[left/        if (1) [left/' MS
  mtf "Stage Manager's own Close without the minimized windows (R2 of p07: Clock's tile gone, its Dock icon asked where it goes)" 's/        if \(MSBDFitMinimizedStayAtCloseUp\(keys.count\)\) keptMin = [^\n]*\n//'
  mtf "Stage Manager's own Close keeping the minimized windows with one on screen too (O1: Settings next to an empty quarter)" 's/        if \(MSBDFitMinimizedStayAtCloseUp\(keys.count\)\) keptMin/        if (1) keptMin/'
  mtf "Stage Manager's own Close keeping the tile of a minimized window it takes away (Clock's own app quits: its quarter kept empty)" 's/DMSMFitMinimizedIn\(\[keys arrayByAddingObjectsFromArray:going\], gSMFitSlots\)/DMSMFitMinimizedIn(keys, gSMFitSlots)/'
  # (the file before H2: it fails every row the device failed, on every engine: Z11c, Z11 and Z8 -- Settings out of the arrangement or its old half --
  #  and our Stage Manager engine's C15 and C14 -- the pair taken, the question)
  for c in 5a9ff095 82c24a91; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/before.x"; git -C .. show $c:statusbar/MacSwitcher.h > "$W/before-m.h"; git -C .. show $c:statusbar/MacSwitcherSM.h > "$W/before-ms.h"
    run "$W/before.x" "$W/before" q "$W/before-m.h" "$W/before-ms.h"; n=$?
    miss=0
    for en in Aerial Zetsu MilkyWay4; do
      for w in "Z11c Clock back by its Dock icon while Settings is minimized: Clock opens on its own at its place, Settings keeps its tile" "Z11c ... Settings back: both tiled" \
               "Z11 ... Clock opens on its own at Window Size's place, Settings (minimized) keeps its tile" "Z11 ... Settings back: Clock left, Settings right" \
               "Z8 ... Settings' tile closed up to Fill while minimized" "Z8 ... Settings back: it fills"; do
        /usr/bin/grep -qF "FAIL  $en: $w" "$W/before/out-engines" || { echo "      (the file before H2: no FAIL line for \"$en: $w\")"; miss=1; }
      done
    done
    for w in "C15 (Home Minimizes Windows off): App Store from the Dock" "C15 ... Clock's Dock icon: no question" "C14 (17.5): Safari from the Dock" "C15 (Home Minimizes Windows on): Clock from the Dock"; do
      /usr/bin/grep -qF "FAIL  $w" "$W/before/out-sm" || { echo "      (the file before H2: no FAIL line for \"$w\")"; miss=1; }
    done
    if [ $n = 1 ] && [ $miss = 0 ]; then echo "PASS  the file before H2 ($c) fails $RUN_FAILS check(s): every row the devices failed, on every engine (Z8, Z11, Z11c; C14, C15)"
    else echo "FAIL  the file before H2 ($c): $n ($RUN_FAILS failed), not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before H2 are not in this tree's history: that comparison left out)"; fi
  # (the file before the H2-H5 review's fixes -- ef8ed7fc, or its -reg twin cea5cd20 --: it fails every row the review found, on every engine)
  for c in ef8ed7fc cea5cd20; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/before-r.x"; git -C .. show $c:statusbar/MacSwitcher.h > "$W/before-r-m.h"; git -C .. show $c:statusbar/MacSwitcherSM.h > "$W/before-r-ms.h"
    run "$W/before-r.x" "$W/before-r" q "$W/before-r-m.h" "$W/before-r-ms.h"; n=$?
    miss=0
    for en in Aerial Zetsu MilkyWay4; do
      for w in "R1 ... Clock's Dock icon: Clock the left half, Maps the top right, Settings keeps the bottom right" "R1 ... Settings' Dock icon: into its tile, nothing moves" \
               "R2 four tiles, Clock minimized, Notes quits: the two on screen and Clock close the tile up" "R2 ... Clock back: into its tile" "R2 four tiles, Clock minimized, Notes back free from full screen" \
               "R3 Maps brought from another desktop, Clock minimized" "R3 every tile minimized, Maps brought here" "R3 four tiles, Clock minimized, Notes dragged to another desktop" "R3 Settings and Clock, Clock minimized, Settings dragged away" \
               "R5 Settings minimized, Maps opened on its own, Clock's way back" "R5 Settings closed while minimized, Maps on its own, Clock's way back" \
               "R6 Z8 ... Settings' layout noted as Fill while minimized" "R6 ... Clock's layout noted as the bottom right quarter while minimized"; do
        /usr/bin/grep -qF "FAIL  $en: $w" "$W/before-r/out-engines" || { echo "      (the file before the review's fixes: no FAIL line for \"$en: $w\")"; miss=1; }
      done
    done
    /usr/bin/grep -qF "FAIL  Aerial: R5 Clock's way back with Settings minimized and nothing else on screen" "$W/before-r/out-engines" || { echo "      (the file before the review's fixes: no FAIL line for Aerial's way back with no cover)"; miss=1; }
    for w in "R3 (Stage Manager): four tiles, Clock minimized, Notes dragged to another desktop" "R3 (Stage Manager): Settings and Clock, Clock minimized, Settings dragged away"; do
      /usr/bin/grep -qF "FAIL  $w" "$W/before-r/out-sm" || { echo "      (the file before the review's fixes: no FAIL line for \"$w\")"; miss=1; }
    done
    if [ $n = 1 ] && [ $miss = 0 ]; then echo "PASS  the file before the H2-H5 review's fixes ($c) fails $RUN_FAILS check(s): every row the review found, on every engine"
    else echo "FAIL  the file before the H2-H5 review's fixes ($c): $n ($RUN_FAILS failed), not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before the H2-H5 review's fixes are not in this tree's history: that comparison left out)"; fi
  # (the file before the fix of R2 on our Stage Manager engine -- 8cd44f8a, or its -reg twin 5adf1c79 --: it fails R2 by Stage Manager's own Close
  #  and by ours, as the iPad 2 did on p07, and every other row of the Close as now; the counters pass)
  for c in 8cd44f8a 5adf1c79; do git -C .. cat-file -e $c:statusbar/StatusBar.x 2>/dev/null && break; c=; done
  if [ -n "$c" ]; then
    git -C .. show $c:statusbar/StatusBar.x > "$W/before-s.x"; git -C .. show $c:statusbar/MacSwitcher.h > "$W/before-s-m.h"; git -C .. show $c:statusbar/MacSwitcherSM.h > "$W/before-s-ms.h"
    run "$W/before-s.x" "$W/before-s" q "$W/before-s-m.h" "$W/before-s-ms.h"; n=$?
    miss=0
    for w in "R2 (Stage Manager's own Close): four tiles, Clock minimized, App Store closes" "R2 ... Clock's Dock icon: into its tile (the bottom right quarter), no question" \
             "R2sb (our close): the same, Clock keeps the bottom right" "R2sb ... Clock's Dock icon: into its tile, no question" \
             "R2 (Stage Manager's own Close): four tiles, Clock minimized, Safari closes" "R2 (Home Minimizes Windows off): Clock sent to the background by Home, App Store closes"; do
      /usr/bin/grep -qF "FAIL  $w" "$W/before-s/out-sm" || { echo "      (the file before the Stage Manager Close fix: no FAIL line for \"$w\")"; miss=1; }
    done
    if /usr/bin/grep '^FAIL  counter' "$W/before-s/out-sm" | /usr/bin/grep -q .; then echo "      (the file before the Stage Manager Close fix fails a counter)"; miss=1; fi
    if [ "$(/usr/bin/grep -c '^FAIL  ' "$W/before-s/out-engines")" != 0 ]; then echo "      (the file before the Stage Manager Close fix fails an Aerial / Zetsu / MilkyWay4 row)"; miss=1; fi
    if [ $n = 1 ] && [ $miss = 0 ]; then echo "PASS  the file before the fix of R2 on our Stage Manager engine ($c) fails $RUN_FAILS check(s): R2 by Stage Manager's own Close and by ours, as on the iPad 2 (the counters and the other engines pass)"
    else echo "FAIL  the file before the fix of R2 on our Stage Manager engine ($c): $n ($RUN_FAILS failed), not as expected"; rc=$((rc + 1)); fi
  else echo "PASS  (the files before the fix of R2 on our Stage Manager engine are not in this tree's history: that comparison left out)"; fi
fi
exit $rc
