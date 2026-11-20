#!/bin/bash
# test-engineturnbehind.sh: Aerial (3.0 and 5.x), Zetsu and MilkyWay4 -- a window the user left partly behind the Dock stays behind it when the iPad
# turns and turns back, as on the Stage Manager engine (1.8.7.5, engine parity with SMBEHIND, test-smturnbehind.sh); a place of ours takes the mark,
# the title bar's Back gives it back. See test-engineturnbehind.m. The real code is cut out of statusbar/StatusBar.x, WindowKeys.h, TitleBarTap.h and
# MacSwitcher.h (ETB_SB_X, ETB_WK_H, ETB_TB_H, ETB_MSW_H: other copies, e.g. the code before the change) and run on the Mac for each engine; then
# site checks; then made-to-fail copies: each takes one part of the change out (or widens it) and must fail. 1.8.8 (App Window Sizes, review R1 of its
# port): the green light's way back of an open window whose place the forget took is a place of ours and takes the mark (scenario 14).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SB0=${ETB_SB_X:-../statusbar/StatusBar.x}; WK0=${ETB_WK_H:-../statusbar/WindowKeys.h}; TB0=${ETB_TB_H:-../statusbar/TitleBarTap.h}; MSW0=${ETB_MSW_H:-../statusbar/MacSwitcher.h}
# one function of a file, from its first line to its closing brace (a function on one line: that line)
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; l = $0; sub(/[ \t]*\/\/.*$/, "", l); if (l ~ /\}[ \t]*$/) exit; next } f { print } f && /^[}]/ { exit }' "$1"; }
ln1() { awk -v h="$2" 'index($0, h) == 1 { print; exit }' "$1"; }
# (in this order; "?" first: only where the code has it -- the record and its readers are new in 1.8.7.5, the code before has none)
SB_FN=('static CGFloat DMA5StageShift(void) {' 'static CGRect DMA5StageFromWindow(CGRect r) {' 'static CGRect DMA5WindowFromStage(CGRect f) {' 'static CGSize DMEngineWindowMin(void) {'
       'static CGRect DMLayoutFrameWindow(NSString *name) {' 'static CGRect DMLayoutFrame(NSString *name) {' 'static NSString *DMOrientKey(void) {'
       'static void DMKeepStagePlace(UIView *stage, CGRect frame) {' 'static void DMSetStageIntent(UIView *stage, CGRect frame) {' 'static void DMRememberStageFrame(UIView *stage) {'
       'static CGRect DMFitInto(CGRect f, CGRect usable) {' 'static CGRect DMScaleFrame(CGRect f, CGSize from, CGSize to) {' 'static UIScreen *DMSnapScreenOf(UIView *v) {'
       'static CGRect DMSnapWindowOfFrame(UIView *st, CGRect f) {' 'static CGRect DMSnapWindowOf(UIView *st) {'
       'static CGRect DMSnapFrameFor(NSString *who, CGRect window, unsigned how, const CGRect *others, int n, CGRect area) {' 'static BOOL DMDockSideKeepsOut(void) {'
       'static CGRect DMDockSideKept(CGRect window, unsigned how) {' 'static CGRect DMSnapEngineWindow(UIView *st, CGRect window, unsigned how) {'
       '?static NSMutableSet<NSString *> *gBehindDock;' '?static BOOL DMBehindDockHas(NSString *bundle) {' '?static void DMBehindDockSet(NSString *bundle, BOOL behind, NSString *why) {'
       '?static void DMBehindDockMoveEndedAt(UIView *st, CGRect w) {' '?static void DMBehindDockMoveEnded(UIView *st) {' '?static void DMBehindDockPlacedByUs(UIView *v, NSString *why) {' '?static CGRect DMBehindDockTurnArea(NSString *bundle, CGRect usable) {'
       'static void DMSnapMoveEnded(UIView *st) {' 'static void DMNoteWindowLayouts(void) {' 'static void DMRelayoutStageWhenLanded(UIView *stage, CGSize oldSize, CGSize newSize, int attempt) {'
       'static void DMRelayoutForOrientation(CGSize oldSize, CGSize newSize) {')
WK_FN=('static char kWinZoomKey;' 'static NSArray<NSValue *> *DMTitleRecordPair(CGRect before, CGRect fill' '?static BOOL DMTitleRecordIs(id r) {' '?static BOOL DMTitleRecordBehind(NSArray *r) {'
       'static void DMTitleRecordMovedView(UIView *v) {' 'static void DMTitleRecordView(UIView *v, CGRect now, CGRect to, CGRect fill' 'static void DMTitleRecordEngineTo(UIView *v, CGRect to) {'
       'static NSValue *DMTitleRecordHeldView(UIView *v, CGRect now, NSString *who) {' '?static BOOL DMTitleRecordBehindView(UIView *v) {')
TB_FN=('static void DMTitleTapEngineWindow(NSString *bundleID, NSString *why) {')
MSW_FN=('static void DMMSWFitTurned(UIView *st, NSInteger fromId) {')

cut() {   # $1 file, $2 out, the rest: the heads (a "?" head: only if there)
  local f=$1 o=$2 h opt; shift 2
  : > "$o"
  for h in "$@"; do
    opt=; [ "${h:0:1}" = "?" ] && { opt=1; h=${h:1}; }
    if [ "${h: -1}" = ";" ]; then t=$(ln1 "$f" "$h"); else t=$(fn "$f" "$h"); fi
    if [ -z "$t" ]; then [ -n "$opt" ] && continue; echo "FAIL  $f: no line starting \"$h\""; return 1; fi
    printf '%s\n' "$t" >> "$o"
  done
}

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local S=$1 q=$2 n=0
  # every engine's move by hand records the mark at its end: let go (DMSnapMoveEnded, before its snap) and cut short (each engine's pan)
  if [ "$(grep -c 'DMBehindDockMoveEnded(' "$S")" = 7 ] && fn "$S" 'static void DMSnapMoveEnded(UIView *st) {' | grep -qF '    DMBehindDockMoveEndedAt(st, s);' &&
     grep -A1 -F 'else DMTitleRecordHandEnded(w, g.state);   // (a move by hand cut short' "$S" | grep -qF 'if (g.state == UIGestureRecognizerStateCancelled) DMBehindDockMoveEnded(w);' &&
     grep -A1 -F 'else DMTitleRecordHandEnded(win, g.state);   // (a move by hand cut short' "$S" | grep -qF 'if (g.state == UIGestureRecognizerStateCancelled) DMBehindDockMoveEnded(win);' &&
     fn "$S" 'static void DMAerialGestureAfter(UIView *stage, UIGestureRecognizer *g, BOOL wasPan) {' | grep -qF 'if (wasPan && s == UIGestureRecognizerStateCancelled) DMBehindDockMoveEnded(stage);' &&
     fn "$S" '- (void)dragTrace:(UIPanGestureRecognizer *)g {' | grep -qF 'if (g.state == UIGestureRecognizerStateCancelled && stage.superview) DMBehindDockMoveEnded(stage);' &&
     fn "$S" '- (void)areaDrag:(UIPanGestureRecognizer *)g {' | grep -qF 'if (g.state == UIGestureRecognizerStateCancelled) DMBehindDockMoveEnded(stage);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the mark is recorded at the end of every engine's move by hand, let go (where it ends, after its snap) or cut short (Zetsu, MilkyWay4, Aerial 3.0, Aerial 5.x's two drags)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: a move by hand ends without recording the mark"; n=$((n + 1)); fi
  # the Dock's move or room change takes a window out from under it: a place of ours, the mark goes (as Stage Manager's DMDockPositionMoved takes it)
  if fn "$S" 'static void DMDockPositionMoved(NSDictionary<NSString *, NSString *> *layouts) {' | grep -qF 'if (!CGRectIsNull(t) && !CGRectEqualToRect(t, w)) { DMBehindDockPlacedByUs(st, @"the Dock moved or its room changed: out from under it"); DMSnapMoveEngineTo(st, t); }'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: a window the Dock's move takes out from under it loses the mark"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the Dock's move keeps the mark of a window it moved"; n=$((n + 1)); fi
  # the Window menu's layouts (DMWindowLayout): a window moved takes the mark through DMTitleRecordEngineTo (after the title bar's record kept it, run
  # in the scenarios); an app opening from full screen into the layout, which no record names, takes it in each engine's branch (3 places), and no
  # line takes it before the engines' branches (round 1: Back lost the mark on Aerial, Zetsu and MilkyWay4)
  if fn "$S" 'static void DMWindowLayout(NSString *name) {' > "$W/wl.txt" && [ "$(grep -cF 'if (!gPreferRememberedFrame) DMBehindDockSet(bundleID, NO, @"placed by a layout of the Window menu");   // (its window opens there)' "$W/wl.txt")" = 3 ] &&
     ! awk 'index($0, "DMBehindDockSet(bundleID, NO,") {a=NR} index($0, "if (DMActiveEngine() == DMEngineZetsu) {") && !z {z=NR} END{exit !(a && z && a < z) && !(a && !z)}' "$W/wl.txt" &&
     [ "$(grep -c 'DMBehindDockSet(bundleID, NO,' "$W/wl.txt")" = 3 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the Window menu's layouts take the mark in each engine's branch for an app opening from full screen, none before the branches"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: a Window menu layout takes the mark before the record, or keeps it for an app opening from full screen"; n=$((n + 1)); fi
  # an app's exit forgets it, with where its window was (every engine: %group AppExitForget)
  if awk '/^%group AppExitForget/{g=1} g && /^- \(void\)_didExitWithContext:\(id\)context \{/{f=1} f && index($0, "DMBehindDockSet(bundleID, NO, @\"its app exited") {ok=1} f && /^}/{exit} END{exit !ok}' "$S"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: an app's exit forgets its window's mark (every engine)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: an app's exit keeps the mark"; n=$((n + 1)); fi
  # one writer
  if [ "$(grep -c '\[gBehindDock addObject:' "$S")" = 1 ] && [ "$(grep -c '\[gBehindDock removeObject:' "$S")" = 1 ] && [ "$(grep -c 'gBehindDock = ' "$S")" = 1 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the record is written in one place (DMBehindDockSet)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the record is written somewhere else too"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 WindowKeys.h, $3 TitleBarTap.h, $4 MacSwitcher.h, $5 work dir, $6 quiet: the number of failed checks (99: not built)
  local S=$1 K=$2 T=$3 M=$4 d=$5 q=$6 n s out
  mkdir -p "$d"
  cut "$S" "$d/engineturnbehind-sb.inc" "${SB_FN[@]}" || return 99
  cut "$K" "$d/engineturnbehind-wk.inc" "${WK_FN[@]}" || return 99
  cut "$T" "$d/engineturnbehind-tb.inc" "${TB_FN[@]}" || return 99
  cut "$M" "$d/engineturnbehind-msw.inc" "${MSW_FN[@]}" || return 99
  # the Window menu's layouts on Aerial, Zetsu and MilkyWay4: DMWindowLayout from where the engines' part begins, as a function of its own
  awk 'index($0, "static void DMWindowLayout(NSString *name) {") == 1 {w = 1} w && index($0, "    DMFitGroupForget(bundleID);   // placed by a layout of its own") == 1 {f = 1; print "static void TWindowLayoutEngines(NSString *name, NSString *bundleID, CGRect target) {"} f {print} f && $0 == "}" {exit}' "$S" > "$d/engineturnbehind-layout.inc"
  grep -q 'DMFindMilkyWayWindow(bundleID)' "$d/engineturnbehind-layout.inc" || { echo "FAIL  $S: no engines' part in DMWindowLayout"; return 99; }
  if grep -q '^static NSMutableSet<NSString \*> \*gBehindDock;' "$d/engineturnbehind-sb.inc"; then echo 'static void TForgetMarks(void) { [gBehindDock removeAllObjects]; }' > "$d/engineturnbehind-reset.inc"
  else echo 'static void TForgetMarks(void) { }' > "$d/engineturnbehind-reset.inc"; fi
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" -I../statusbar \
        -framework Foundation -framework CoreGraphics -o "$d/t" test-engineturnbehind.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -n "$q" ] || [ ! -s "$d/cc.txt" ] || { echo "-- compiler warnings:"; cat "$d/cc.txt"; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  [ -n "$q" ] || echo "-- site checks"
  sites "$S" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$SB0" "$WK0" "$TB0" "$MSW0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-engineturnbehind: all pass" || echo "test-engineturnbehind: FAILED ($rc check(s))"
if [ -z "$ETB_SB_X$ETB_WK_H$ETB_TB_H$ETB_MSW_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 which file (sb wk tb msw), $3 perl expression on it (the whole file at once)
    local d="$W/m$((++k))" c src S=$SB0 K=$WK0 T=$TB0 M=$MSW0
    case $2 in sb) src=$SB0;; wk) src=$WK0;; tb) src=$TB0;; msw) src=$MSW0;; esac
    mkdir -p "$d"; c="$d/$(basename "$src")"
    perl -0777 -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    case $2 in sb) S=$c;; wk) K=$c;; tb) T=$c;; msw) M=$c;; esac
    run "$S" "$K" "$T" "$M" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  mtf "the drop never records a window behind the Dock" sb 's/BOOL behind = !DMDockSideKeepsOut\(\) && CGRectGetMaxY\(w\) > line \+ 4\.0;/BOOL behind = NO;/'
  mtf "the drop records a window let go 4 pt or less under the Dock's line" sb 's/CGRectGetMaxY\(w\) > line \+ 4\.0;/CGRectGetMaxY(w) > line - 4.0;/'
  mtf "the drop records a window past the screen's bottom with the Dock at a side" sb 's/BOOL behind = !DMDockSideKeepsOut\(\) && /BOOL behind = /'
  mtf "a move let go does not record (DMSnapMoveEnded)" sb 's/\n    DMBehindDockMoveEndedAt\(st, s\);   \/\/ \(behind the Dock where it ends[^\n]*//'
  mtf "the mark from the frame let go, before its snap (round 1)" sb 's/    DMBehindDockMoveEndedAt\(st, s\);   \/\//    DMBehindDockMoveEndedAt(st, w);   \/\//'
  mtf "a Window menu layout takes the mark before the record (round 1: Back loses it)" sb 's/(    \/\/ \(a layout is a place of ours: the window is no longer behind the Dock -- taken by DMTitleRecordEngineTo below)/    if (!gPreferRememberedFrame) DMBehindDockSet(bundleID, NO, \@"placed by a layout of the Window menu");\n$1/'
  mtf "the turn's area ignores the mark" sb 's/if \(!DMBehindDockHas\(bundle\) \|\| CGRectIsNull\(usable\)/if (YES || CGRectIsNull(usable)/'
  mtf "the turn fits every window above the Dock again" sb 's/f = DMFitInto\(f, DMBehindDockTurnArea\(b, usable\)\);/f = DMFitInto(f, usable);/'
  mtf "the turn keeps the mark of a window it puts into a layout" sb 's/ DMBehindDockSet\(b, NO, @"a turn put it back into its layout"\);//'
  mtf "a window landing after the turn is fitted above the Dock" sb 's/\n        usable = DMBehindDockTurnArea\(b, usable\);   \/\/ \(a window the user left behind the Dock[^\n]*//'
  mtf "the green light's places are fitted above the Dock at a turn" sb 's/DMFitInto\(DMScaleFrame\(f, oldSize, newSize\), DMBehindDockTurnArea\(b, usable\)\)/DMFitInto(DMScaleFrame(f, oldSize, newSize), usable)/'
  mtf "the Dock's move keeps the mark of a window it moves out" sb 's/ DMBehindDockPlacedByUs\(st, @"the Dock moved or its room changed: out from under it"\);//'
  mtf "a Window menu layout keeps the mark (an Aerial app opening from full screen into it)" sb 's/(            DMStageCoverPrepare\(YES\);\n)            if \(!gPreferRememberedFrame\) DMBehindDockSet\(bundleID, NO, @"placed by a layout of the Window menu"\);[^\n]*\n/$1/'
  mtf "a Window menu layout keeps the mark (a Zetsu app opening from full screen into it)" sb 's/(DMZetsuAskFrame\(bundleID, target\);\n)            if \(!gPreferRememberedFrame\) DMBehindDockSet\(bundleID, NO, @"placed by a layout of the Window menu"\);[^\n]*\n/$1/'
  mtf "a Window menu layout keeps the mark (a MilkyWay4 app opening from full screen into it)" sb 's/(DMMilkyWayAskFrame\(bundleID, target\);\n)        if \(!gPreferRememberedFrame\) DMBehindDockSet\(bundleID, NO, @"placed by a layout of the Window menu"\);[^\n]*\n/$1/'
  mtf "an app's exit keeps the mark" sb 's/\n    DMBehindDockSet\(bundleID, NO, @"its app exited[^\n]*//'
  mtf "a window from a desktop left in the other shape is fitted above the Dock" msw 's/\n    usable = DMBehindDockTurnArea\(DMStageBundle\(st\), usable\);[^\n]*//'
  mtf "a place of ours keeps the mark" wk 's/\n    if \(!gPreferRememberedFrame\) DMBehindDockPlacedByUs\(v, @"placed by a layout or a place of ours"\);//'
  mtf "the green light's way back takes the mark" wk 's/if \(!gPreferRememberedFrame\) DMBehindDockPlacedByUs\(v, @"placed by a layout/DMBehindDockPlacedByUs(v, @"placed by a layout/'
  mtf "the title bar's record keeps no mark" wk 's/return behindDock \? \[r arrayByAddingObject:\@YES\] : r;/return r;/'
  mtf "a record with the mark is no record" wk 's/\(\[\(NSArray \*\)r count\] == 2 \|\| \[\(NSArray \*\)r count\] == 3\)/([(NSArray *)r count] == 2)/'
  mtf "Back gives no mark back" tb 's/\n    if \(behind\) DMBehindDockSet\(bundleID, YES, @"back from Fill or Zoom[^\n]*//'
  mtf "the green light's way back with no place of its own kept keeps the mark (App Window Sizes, review R1)" wk 's/\n    if \(gPreferRememberedFrame && !gLastWindowFrames\[DMStageBundle\(v\)\]\) DMBehindDockPlacedByUs\([^\n]*//'
  mtf "the green light's way back takes the mark with its place held too (review R1 widened)" wk 's/if \(gPreferRememberedFrame && !gLastWindowFrames\[DMStageBundle\(v\)\]\) DMBehindDockPlacedByUs/if (gPreferRememberedFrame) DMBehindDockPlacedByUs/'
  mtf "Zoom keeps the mark" tb 's/ DMBehindDockPlacedByUs\(v, @"zoomed by its title bar"\);//'
fi
exit $rc
