#!/bin/bash
# test-smturnbehind.sh: the Stage Manager engine -- a window the user put behind the Dock keeps that place and its mark when the iPad turns and
# turns back (1.8.7.4 round 2, the 1.8.7.3 device check, M4 row on the A12Z); a layout the user chooses, or Centre, takes the mark as before, and
# a window that is not behind the Dock is still kept above it. 1.8.7.5: the title bar's Back after Fill or Zoom puts such a window back behind the
# Dock with its mark (the record keeps it), and the Window menu's places take the mark as every other place of ours. See test-smturnbehind.m. The real
# code is cut out of statusbar/StatusBar.x, WindowKeys.h and TitleBarTap.h (SBT_SB_X, SBT_WK_H, SBT_TB_H: other copies, e.g. the code before a fix)
# and run on the Mac; then site checks; then made-to-fail copies: each takes one part of a fix out (or widens it) and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SBT_SB_X:-../statusbar/StatusBar.x}; K0=${SBT_WK_H:-../statusbar/WindowKeys.h}; B0=${SBT_TB_H:-../statusbar/TitleBarTap.h}
# one function of a file, from its first line to its closing brace (a function on one line: that line)
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; l = $0; sub(/[ \t]*\/\/.*$/, "", l); if (l ~ /\}[ \t]*$/) exit; next } f { print } f && /^[}]/ { exit }' "$1"; }
# one line of a file that starts with this text
ln1() { awk -v h="$2" 'index($0, h) == 1 { print; exit }' "$1"; }
SBT_DECL=('typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long type; } DMSMAttributedSize;' 'static const CGFloat kSMBarH = '
          'static NSMutableSet<NSString *> *gSMBehindDock;' 'static CFTimeInterval gSwitcherEventAt = ' 'static CFTimeInterval gSMTurnAt = ' 'static unsigned gSMTurns;')
SBT_FN=('static BOOL DMSMTurnSettling(void) {' 'static NSString *DMSMShapeKey(CGSize s) {' 'static NSDictionary<NSString *, NSString *> *DMSMLayoutsFor(NSDictionary<NSString *, NSValue *> *frames) {'
        'static void DMSMTurnNote(void) {' 'static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {' 'static CGRect DMSMCardDesk(CGRect u, CGSize scr, BOOL behindDock) {'
        'static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle) {' 'static NSArray<NSArray *> *DMSMPlanFitted(id identity, NSArray<NSArray *> *plan) {'
        'static BOOL DMSMRequestOn(id identity, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity) {'
        'static id DMSMAttrsForLayoutIn(id attrs, NSString *name, id stage) {' 'static id DMSMAttrsForFrameIn(id attrs, CGRect w, id stage) {'
        'static BOOL DMSMApplyLayouts(NSDictionary<NSString *, NSString *> *keyToLayout) {' 'static BOOL DMSMAttrsSamePlace(id a, id b, CGSize screen) {'
        'static BOOL DMSMApplyLayoutsIn(NSDictionary<NSString *, NSString *> *bundleToLayout, id stage) {'
        'static BOOL DMSMApplyPlacesIn(NSDictionary<NSString *, id> *bundleToLayout, id stage) {'
        'static BOOL DMSMApplyPlacesMarkedIn(NSDictionary<NSString *, id> *bundleToLayout, id stage, NSSet<NSString *> *placedByUser) {'
        'static void DMSMWatchTurn(void) {' 'static NSString *DMSMWindowKeyOf(NSString *key) {')
# (the title bar's records: WindowKeys.h; "?": only where the code has it -- new in 1.8.7.5) and its double tap: TitleBarTap.h
SBT_WK=('static NSMutableDictionary<NSString *, NSArray<NSValue *> *> *gSMWinZoom;' 'static NSArray<NSValue *> *DMTitleRecordPair(CGRect before, CGRect fill' '?static BOOL DMTitleRecordIs(id r) {'
        '?static BOOL DMTitleRecordBehind(NSArray *r) {' 'static void DMSMRecordsPrune(NSMutableDictionary *map) {' 'static void DMTitleRecordMovedSM(NSString *key) {'
        'static void DMTitleRecordSMAt(NSString *key, id stage, CGRect to, CGRect fill) {' 'static void DMTitleRecordSMTo(NSString *key, id stage, CGRect to) {'
        'static NSValue *DMTitleRecordHeldSM(NSString *key, CGRect now) {' '?static BOOL DMTitleRecordBehindSM(NSString *key) {')
SBT_TB=('static void DMTitleTapSMWindow(NSString *key, NSString *why) {')
# the Window menu's layouts on the Stage Manager engine: DMWindowLayout's branch for it, as a function of its own
smlayout() { awk 'index($0, "static void DMWindowLayout(NSString *name) {") == 1 {w = 1} w && index($0, "    if (DMSMEngine()) {   // Stage Manager: the window'"'"'s place in the stage") == 1 {f = 1; print "static void TWindowLayoutSM(NSString *name, NSString *bundleID) {"} f {print} f && $0 == "    }" {print "}"; exit}' "$1"; }
cutlist() {   # $1 file, $2 out, the rest: the heads (a "?" head: only if there; a head ending in ";": that line)
  local f=$1 o=$2 h opt t; shift 2
  : > "$o"
  for h in "$@"; do
    opt=; [ "${h:0:1}" = "?" ] && { opt=1; h=${h:1}; }
    if [ "${h: -1}" = ";" ]; then t=$(ln1 "$f" "$h"); else t=$(fn "$f" "$h"); fi
    if [ -z "$t" ]; then [ -n "$opt" ] && continue; echo "FAIL  $f: no line starting \"$h\""; return 1; fi
    printf '%s\n' "$t" >> "$o"
  done
}

sites() {   # $1 StatusBar.x, $2 quiet, $3 TitleBarTap.h: the number of site checks that fail
  local X=$1 q=$2 B=$3 n=0 t
  # the mark is written in five places: the title-bar drop (put behind the Dock or not), the place applier (taken for a place of ours), the Window menu's
  # places (taken: 1.8.7.5), the title bar's Back (given back with the record, taken again when not placed: 1.8.7.5); App Window Sizes' forget takes
  # it with each place before full screen it forgets (1.8.8, review R1 of its port: test-appwindowsize.sh c3_behind); a closed window's goes with its
  # turn records (1.8.8 H5, DMSMTurnForget's one removeObject:, test-smturnclosed.sh)
  if [ "$(grep -c '\[gSMBehindDock addObject:' "$X")" = 1 ] && [ "$(grep -c 'DMSMKeySetRemove(gSMBehindDock, ' "$X")" = 4 ] &&
     { [ "$(grep -c '\[gSMBehindDock removeObject:' "$X")" = 0 ] || { [ "$(grep -c '\[gSMBehindDock removeObject:' "$X")" = 1 ] && fn "$X" 'static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) {' | grep -qF '[gSMBehindDock removeObject:k];'; }; } &&
     fn "$X" 'static void DMWindowLayout(NSString *name) {' | grep -qF '        if (ok) DMSMKeySetRemove(gSMBehindDock, DMSMWindowKeyOf(smKey));' &&
     fn "$X" 'static void DMSMAppSizeForgetPlace(NSString *bundle) {' | grep -qxF '    for (NSString *k in went) if (DMSMKeySetRemove(gSMBehindDock, k)) marks++;' &&
     [ "$(grep -c 'gSMBehindDock addObject:' "$B")" = 1 ] && [ "$(grep -c 'DMSMKeySetRemove(gSMBehindDock, ' "$B")" = 1 ] &&
     fn "$B" 'static void DMTitleTapSMWindow(NSString *key, NSString *why) {' | grep -qF 'if (behind) { if (!gSMBehindDock) gSMBehindDock = [NSMutableSet set]; [gSMBehindDock addObject:key]; }' &&
     grep -qF 'if (w.length) { if (endsAt > line + 4.0) [gSMBehindDock addObject:w]; else DMSMKeySetRemove(gSMBehindDock, w); }' "$X" &&
     fn "$X" 'static BOOL DMSMApplyPlacesMarkedIn(NSDictionary<NSString *, id> *bundleToLayout, id stage, NSSet<NSString *> *placedByUser) {' | grep -qF 'if (it && ![placedByUser containsObject:k]) DMSMKeySetRemove(gSMBehindDock, DMSMItemKey(it));'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the mark is set or taken at the title-bar drop, taken by the place applier except for a window put back where the user had it and by the Window menu's places; TitleBarTap.h: given back by Back"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x / TitleBarTap.h: gSMBehindDock is written somewhere else, or the place applier takes every window's mark"; n=$((n + 1)); fi
  # only the turn names windows as put back where the user had them: every other place of ours (DMSMApplyPlacesIn) names none and takes the mark
  if [ "$(grep -c 'DMSMApplyPlacesMarkedIn(' "$X")" = 4 ] && grep -qF 'static BOOL DMSMApplyPlacesIn(NSDictionary<NSString *, id> *bundleToLayout, id stage) { return DMSMApplyPlacesMarkedIn(bundleToLayout, stage, nil); }' "$X" &&
     fn "$X" 'static void DMSMWatchTurn(void) {' | grep -qF 'BOOL placed = !allPlaces.count || DMSMApplyPlacesMarkedIn(allPlaces, DMSMWorkingStage(), movedByTurn);' &&
     [ "$(grep -c 'DMSMApplyPlacesMarkedIn(' "$B")" = 1 ] && fn "$B" 'static void DMTitleTapSMWindow(NSString *key, NSString *why) {' | grep -qF 'BOOL ok = DMSMApplyPlacesMarkedIn(@{key: rec}, stage, behind ? [NSSet setWithObject:key] : nil);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the turn and the title bar's Back (TitleBarTap.h: a window back behind the Dock) are the callers that name windows as the user's; DMSMApplyPlacesIn (layouts, tiles, Centre, Zoom, swaps) names none"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: another caller names windows as the user's, or DMSMApplyPlacesIn does"; n=$((n + 1)); fi
  # the stage area reaches the screen's bottom while the stage on screen has a marked window (unchanged: what keeps the window there between turns)
  t=$(grep -n 'for (id it in DMSMStageItemsMap(al)) if (DMSMKeySetHas(gSMBehindDock, DMSMItemKey(it))) { behind = YES; break; }' "$X" | head -1 | cut -d: -f1)
  if [ -n "$t" ] && awk -v s="$t" 'NR > s && NR < s + 8 && index($0, "CGFloat bottom = (dh || dock <= 0 || dragging || behind) ? CGRectGetMaxY(b) : ") {f=1} END {exit !f}' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the stage area of a stage with a window behind the Dock reaches the screen's bottom"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the stage area no longer reaches the screen's bottom for a window behind the Dock"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet, $4 WindowKeys.h, $5 TitleBarTap.h: the number of failed checks (99: not built)
  local X=$1 d=$2 q=$3 K=${4:-$K0} B=${5:-$B0} h n s out
  mkdir -p "$d"
  for h in "${SBT_DECL[@]}"; do [ -n "$(ln1 "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${SBT_FN[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  for h in "${SBT_DECL[@]}"; do ln1 "$X" "$h"; done > "$d/smturnbehind-decl.inc"
  for h in "${SBT_FN[@]}"; do fn "$X" "$h"; done > "$d/smturnbehind-real.inc"
  cutlist "$K" "$d/smturnbehind-wk.inc" "${SBT_WK[@]}" || return 99
  cutlist "$B" "$d/smturnbehind-tb.inc" "${SBT_TB[@]}" || return 99
  smlayout "$X" > "$d/smturnbehind-layout.inc"; [ -s "$d/smturnbehind-layout.inc" ] || { echo "FAIL  $X: no Stage Manager branch in DMWindowLayout"; return 99; }
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" -I../statusbar \
        -framework Foundation -framework CoreGraphics -o "$d/t" test-smturnbehind.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -n "$q" ] || [ ! -s "$d/cc.txt" ] || { echo "-- compiler warnings:"; cat "$d/cc.txt"; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$q" "$B"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-smturnbehind: all pass" || echo "test-smturnbehind: FAILED ($rc check(s))"
if [ -z "$SBT_SB_X$SBT_WK_H$SBT_TB_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 perl expression on StatusBar.x (the whole file at once); $3 another file of the three (wk, tb) instead
    local d="$W/m$((++k))" c src=$X0 x=$X0 kk=$K0 bb=$B0
    case $3 in wk) src=$K0;; tb) src=$B0;; esac
    mkdir -p "$d"; c="$d/$(basename "$src")"
    perl -0777 -pe "$2" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    case $3 in wk) kk=$c;; tb) bb=$c;; *) x=$c;; esac
    run "$x" "$d/w" q "$kk" "$bb"; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  mtf "the place applier takes every window's mark again (the turn's too)" 's/if \(it && !\[placedByUser containsObject:k\]\) DMSMKeySetRemove\(gSMBehindDock/if (it) DMSMKeySetRemove(gSMBehindDock/'
  mtf "the place applier keeps every window's mark (a layout or Centre the user chose too)" 's/\n[ \t]*if \(it && !\[placedByUser containsObject:k\]\) DMSMKeySetRemove\(gSMBehindDock, DMSMItemKey\(it\)\);//'
  mtf "the turn names no window as the user's" 's/DMSMApplyPlacesMarkedIn\(allPlaces, DMSMWorkingStage\(\), movedByTurn\)/DMSMApplyPlacesMarkedIn(allPlaces, DMSMWorkingStage(), nil)/'
  mtf "the turn keeps a window behind the Dock above it (its desktop not down to the screen's bottom)" 's/CGRect desk = userBehind && /CGRect desk = NO && /'
  mtf "every window's desktop reaches the screen's bottom at a turn (one not behind the Dock stays under it)" 's/CGRect desk = userBehind && /CGRect desk = /'
  mtf "the turn's log names no window kept behind the Dock" 's/            if \(userBehind\) \[behind addObject:b\];\n//'
  mtf "the request's own fit ignores the mark" 's/id a = DMSMAttrsFitScreen\(row\[2\], identity, DMSMKeySetHas\(gSMBehindDock, key\), /id a = DMSMAttrsFitScreen(row[2], identity, NO, /'
  mtf "Back gives no mark back (1.8.7.5)" 's/\n        if \(behind\) \{ if \(!gSMBehindDock\) gSMBehindDock = \[NSMutableSet set\]; \[gSMBehindDock addObject:key\]; \}//' tb
  mtf "Back names no window as the user's (its mark taken again by the place applier)" 's/behind \? \[NSSet setWithObject:key\] : nil\);/nil);/' tb
  mtf "the title bar's record keeps no mark" 's/DMTitleRecordPair\(now\.CGRectValue, fill, DMSMKeySetHas\(gSMBehindDock, key\)\)/DMTitleRecordPair(now.CGRectValue, fill, NO)/' wk
  mtf "a record with the mark is no record" 's/\(\[\(NSArray \*\)r count\] == 2 \|\| \[\(NSArray \*\)r count\] == 3\)/([(NSArray *)r count] == 2)/' wk
  mtf "the Window menu's places keep the mark (1.8.7.5)" 's/\n        if \(ok\) DMSMKeySetRemove\(gSMBehindDock, DMSMWindowKeyOf\(smKey\)\);//'
  mtf "a Window menu place takes the mark though not placed (round 1)" 's/        if \(ok\) DMSMKeySetRemove\(gSMBehindDock, DMSMWindowKeyOf\(smKey\)\);/        DMSMKeySetRemove(gSMBehindDock, DMSMWindowKeyOf(smKey));/'
fi
exit $rc
