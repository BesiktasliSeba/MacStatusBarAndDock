#!/bin/bash
# test-smturnclosed.sh: 1.8.8 H5 -- on our Stage Manager engine a closed window's turn records (its places per shape, its layout, its behind-the-Dock
# mark) go with it, also when it was the iPad's last window and when the app's next window opens before the look has seen the close, so that next
# window (the same scene, the same key) starts with none of them: rows C17 V2 and D5 of p05 on the A12Z 18.5. See test-smturnclosed.m. The real code
# is cut out of statusbar/StatusBar.x (STC_SB_X: another copy, e.g. the code before H5, which has no DMSMWindowKeysAfterStart and no
# DMSMTurnForgetOpening: stood in for by what that code did -- the look read SpringBoard's list as before, an opening forgot nothing) and run on the
# Mac; then site checks; then made-to-fail copies (each takes one part of the fix out, or widens it, and must fail); then the file before H5
# (8109fa0e, or its -reg twin 2f4eaf58), which must fail the rows the A12Z failed.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${STC_SB_X:-../statusbar/StatusBar.x}
# one function of a file, from its first line to its closing brace (a function on one line: that line)
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; l = $0; sub(/[ \t]*\/\/.*$/, "", l); if (l ~ /\}[ \t]*$/) exit; next } f { print } f && /^[}]/ { exit }' "$1"; }
ln1() { awk -v h="$2" 'index($0, h) == 1 { print; exit }' "$1"; }   # one line of a file that starts with this text
has() { grep -qF -e "$2" "$1"; }
STC_DECL=('typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long type; } DMSMAttributedSize;' 'static const CGFloat kSMBarH = '
          'static NSMutableSet<NSString *> *gSMBehindDock;' 'static CFTimeInterval gSwitcherEventAt = ' 'static CFTimeInterval gSMTurnAt = ' 'static unsigned gSMTurns;'
          'static NSMutableDictionary<NSString *, NSString *> *gSMTurnLayout;' 'static NSDictionary<NSString *, NSString *> *gSMTurnLayoutWritten;'
          'static NSMutableDictionary<NSString *, NSDictionary<NSString *, NSValue *> *> *gSMTurnFrames;' 'static NSMutableDictionary<NSString *, NSValue *> *gSMTurnPlaced;'
          'static BOOL gSMTurnStartSettled = NO;' 'static NSMutableDictionary<NSString *, id> *gSMPreZoom;')
STC_FN=('static BOOL DMSMTurnSettling(void) {' 'static NSString *DMSMShapeKey(CGSize s) {' 'static NSDictionary<NSString *, NSString *> *DMSMLayoutsFor(NSDictionary<NSString *, NSValue *> *frames) {'
        'static void DMSMTurnNote(void) {' 'static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {' 'static CGRect DMSMCardDesk(CGRect u, CGSize scr, BOOL behindDock) {'
        'static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle) {' 'static NSArray<NSArray *> *DMSMPlanFitted(id identity, NSArray<NSArray *> *plan) {'
        'static BOOL DMSMRequestOn(id identity, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity) {'
        'static id DMSMAttrsForLayoutIn(id attrs, NSString *name, id stage) {' 'static id DMSMAttrsForFrameIn(id attrs, CGRect w, id stage) {'
        'static BOOL DMSMApplyLayouts(NSDictionary<NSString *, NSString *> *keyToLayout) {' 'static BOOL DMSMAttrsSamePlace(id a, id b, CGSize screen) {'
        'static BOOL DMSMApplyLayoutsIn(NSDictionary<NSString *, NSString *> *bundleToLayout, id stage) {'
        'static BOOL DMSMApplyPlacesIn(NSDictionary<NSString *, id> *bundleToLayout, id stage) {'
        'static BOOL DMSMApplyPlacesMarkedIn(NSDictionary<NSString *, id> *bundleToLayout, id stage, NSSet<NSString *> *placedByUser) {'
        'static void DMSMWatchTurn(void) {' 'static NSString *DMSMWindowKeyOf(NSString *key) {'
        'static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) {' 'static NSSet<NSString *> *DMSMWindowKeysIn(NSArray *stages) {'
        'static void DMSMTurnForgetClosed(void) {' 'static BOOL DMSMForgetPlacesOf(NSString *bundle) {' 'static void DMSMForgetApp(NSString *bundle) {'
        'static void DMSMAppSizeForgetPlace(NSString *bundle) {')
AFTER='static NSSet<NSString *> *DMSMWindowKeysAfterStart(NSArray *stages) {'   # (H5's: not in the code before it)
OPENING='static void DMSMTurnForgetOpening(NSString *opening) {'
CLOSEDKEYS='static NSSet<NSString *> *DMSMFitClosedKeys(id<NSFastEnumeration> keys, NSSet<NSString *> *present, NSSet<NSString *> *pending) {'

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0 t
  # the look: SpringBoard's list read through DMSMWindowKeysAfterStart, the marks among the keys it looks at
  t=$(fn "$X" 'static void DMSMTurnForgetClosed(void) {')
  if echo "$t" | grep -qxF '    NSSet<NSString *> *present = DMSMWindowKeysAfterStart(stages);' && echo "$t" | grep -qF '    if (gSMBehindDock.count) [keys unionSet:gSMBehindDock];' &&
     echo "$t" | grep -qF '(!DMSMTurnLayouts().count && !gSMTurnFrames.count && !gSMBehindDock.count)) return;' && ! echo "$t" | grep -qF 'DMSMWindowKeysIn('; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the look for closed windows reads the stages through DMSMWindowKeysAfterStart and looks at the marks too"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the look for closed windows reads the stages otherwise, or leaves the marks"; n=$((n + 1)); fi
  # the after-start reader: two callers, the look and the opening; the start (SMHome.h), the 64 cap and the minimized marks keep DMSMWindowKeysIn
  if [ "$(grep -c 'DMSMWindowKeysAfterStart(' "$X")" = 3 ] && fn "$X" "$OPENING" | grep -qF 'NSSet<NSString *> *present = DMSMWindowKeysAfterStart(DMSMRecentStages());' &&
     fn "$X" "$AFTER" | grep -qxF '    if (!gSMTurnStartSettled || !stages) return nil;' && fn "$X" "$AFTER" | grep -qxF '    return stages.count ? DMSMWindowKeysIn(stages) : [NSSet set];' &&
     fn "$X" 'static void DMSMMinimizedForgetClosed(void) {' | grep -qF 'NSSet<NSString *> *present = DMSMWindowKeysIn(stages);' &&
     ! grep -q 'DMSMWindowKeysAfterStart' ../statusbar/SMHome.h; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMSMWindowKeysAfterStart (nil before the start and with no list, no window for an empty list) has the look and the opening as its callers; the start, the 64 cap and the minimized marks' look as before"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMSMWindowKeysAfterStart is not as built, or has other callers"; n=$((n + 1)); fi
  # the opening: SpringBoard's launch right after Fit's own forget, our icon tap right after the minimized marks' look -- its two callers
  if [ "$(grep -c 'DMSMTurnForgetOpening(' "$X")" = 3 ] &&
     fn "$X" 'static void DMSMJoinDesktop(id ctx) {' | awk '/^    DMSMFitForgetClosed\(key\);/ {c=NR} /^    DMSMTurnForgetOpening\(key\);/ {t=NR} /^    if \(!tv && DMMSWForMain\(\) && DMMSWSMJoin\(ctx, act, key\)\) return;/ {j=NR} END {exit !(c && t == c + 1 && j == t + 1)}' &&
     fn "$X" 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' | awk '/^    DMSMMinimizedLook\(\);/ {l=NR} /^    DMSMTurnForgetOpening\(bundle\);/ {t=NR} END {exit !(l && t == l + 1)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the window opening drops a closed window's records in SpringBoard's launch (DMSMJoinDesktop, after Fit's forget, before the Mac Switcher's join) and at our icon tap (DMSMAddToStage, after the minimized marks' look)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMSMTurnForgetOpening is not called where a window opens, or elsewhere"; n=$((n + 1)); fi
  # the forget takes each key's mark exactly; the app's quit hands it the app's marks; the mark's other writers are unchanged (test-smturnbehind.sh)
  if fn "$X" 'static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) {' | grep -qF '[gSMTurnPlaced removeObjectForKey:k]; [gSMBehindDock removeObject:k];' &&
     [ "$(grep -c '\[gSMBehindDock removeObject:' "$X")" = 1 ] &&
     fn "$X" 'static void DMSMForgetApp(NSString *bundle) {' | grep -qF '    for (NSString *k in gSMBehindDock) if ([DMSMKeyBundle(k) isEqualToString:bundle]) [mine addObject:k];' &&
     ! fn "$X" 'static BOOL DMSMForgetPlacesOf(NSString *bundle) {' | grep -q 'BehindDock'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMSMTurnForget takes each closed key's mark exactly (its one removeObject:); DMSMForgetApp hands it the app's marks; DMSMForgetPlacesOf (App Window Sizes' too) none"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the forget does not take the marks as built"; n=$((n + 1)); fi
  # the crash map: the new functions are the Stage Manager engine's (windowingEnabled: the first sym rule that matches), not App Window Sizes' piece
  for t in DMSMWindowKeysAfterStart DMSMTurnForgetOpening; do
    if [ "$(python3 -I -c 'import re, sys
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) >= 4 and p[0] == "sym" and p[1] == "MacStatusBarCore" and re.search(p[2], "_" + sys.argv[2]): print(p[3]); break' crashmap-rules.txt "$t")" = windowingEnabled ]; then
      [ -n "$q" ] || echo "PASS  crashmap-rules.txt: $t falls under a windowingEnabled rule (the Stage Manager engine's)"
    else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: $t is not under the Stage Manager engine's rule"; n=$((n + 1)); fi
  done
  return $n
}

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (99: not built)
  local X=$1 d=$2 q=$3 h n s t out
  mkdir -p "$d"
  : > "$d/smturnclosed-decl.inc"
  for h in "${STC_DECL[@]}"; do t=$(ln1 "$X" "$h"); [ -n "$t" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; printf '%s\n' "$t" >> "$d/smturnclosed-decl.inc"; done
  fn ../statusbar/SMFitPlan.h "$CLOSEDKEYS" > "$d/smturnclosed-real.inc"
  if has "$X" "$AFTER"; then fn "$X" "$AFTER" >> "$d/smturnclosed-real.inc"; else [ -n "$q" ] || echo "   (no DMSMWindowKeysAfterStart: the code before H5)"; fi
  for h in "${STC_FN[@]}"; do t=$(fn "$X" "$h"); [ -n "$t" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; printf '%s\n' "$t" >> "$d/smturnclosed-real.inc"; done
  if has "$X" "$OPENING"; then fn "$X" "$OPENING" >> "$d/smturnclosed-real.inc"
  else echo 'static void DMSMTurnForgetOpening(NSString *opening) { (void)opening; }   // (not in this source: an opening forgot nothing)' >> "$d/smturnclosed-real.inc"; fi
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" -I../statusbar \
        -framework Foundation -framework CoreGraphics -o "$d/t" test-smturnclosed.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -n "$q" ] || [ ! -s "$d/cc.txt" ] || { echo "-- compiler warnings:"; cat "$d/cc.txt"; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  [ "$4" = nosites ] && return $n
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-smturnclosed: all pass" || echo "test-smturnclosed: FAILED ($rc check(s))"
if [ -z "$STC_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 perl expression on StatusBar.x (the whole file at once)
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"
    perl -0777 -pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  mtf "the forget leaves the marks (D5: the new window named behind the Dock)" 's/ \[gSMBehindDock removeObject:k\];//'
  mtf "the look reads an empty list as one not read (C17 V2: the last window's close unseen)" 's/return stages\.count \? DMSMWindowKeysIn\(stages\) : \[NSSet set\];/return stages.count ? DMSMWindowKeysIn(stages) : nil;/'
  mtf "the look leaves the marks out of the keys it looks at" 's/\n    if \(gSMBehindDock\.count\) \[keys unionSet:gSMBehindDock\];[^\n]*//'
  mtf "the look reads the list as before H5 (DMSMWindowKeysIn)" 's/NSSet<NSString \*> \*present = DMSMWindowKeysAfterStart\(stages\);/NSSet<NSString *> *present = DMSMWindowKeysIn(stages);/'
  mtf "an empty list trusted before the start has settled" 's/    if \(!gSMTurnStartSettled \|\| !stages\) return nil;/    if (!stages) return nil;/'
  mtf "no list taken for no window" 's/    if \(!gSMTurnStartSettled \|\| !stages\) return nil;/    if (!gSMTurnStartSettled) return nil;/'
  mtf "the opening forgets nothing (a close and an open back to back: the old records kept)" 's/(static void DMSMTurnForgetOpening\(NSString \*opening\) \{\n)/$1    return;\n/'
  mtf "the opening drops every closed window's records, not only its own key's" 's/    for \(NSString \*k in gSMBehindDock\) if \(DMSMKeyCovers\(opening, k\) \|\| DMSMKeyCovers\(k, opening\)\) \[mine addObject:k\];/    for (NSString *k in gSMBehindDock) [mine addObject:k];/'
  mtf "the opening during a switcher gesture or a Mac Switcher slide" 's/    if \(!opening\.length \|\| gMSWSwitching \|\| DMSMGestureLive\(\)\) return;/    if (!opening.length) return;/'
  mtf "the opening takes a window that is in a stage for closed (no look at the stages)" 's/    if \(present\) DMSMTurnForget\(DMSMFitClosedKeys\(mine, present, nil\), /    if (present) DMSMTurnForget(mine, /'
  mtf "the app's quit leaves its marks" 's/\n    for \(NSString \*k in gSMBehindDock\) if \(\[DMSMKeyBundle\(k\) isEqualToString:bundle\]\) \[mine addObject:k\];[^\n]*//'
  mtf "the forget takes a window key's app-wide mark too (a window of the app still there loses it)" 's/ \[gSMBehindDock removeObject:k\];/ DMSMKeySetRemove(gSMBehindDock, k);/'
  mtf "SpringBoard's launch does not ask (the join's call gone)" 's/\n    DMSMTurnForgetOpening\(key\);[^\n]*//'
  mtf "our icon tap does not ask (DMSMAddToStage's call gone)" 's/\n    DMSMTurnForgetOpening\(bundle\);[^\n]*//'
  mtf "the opening asked after the Mac Switcher's join (a Mac Switcher launch keeps the old records)" 's/(\n    DMSMTurnForgetOpening\(key\);[^\n]*)(\n    if \(!tv && DMMSWForMain\(\) && DMMSWSMJoin\(ctx, act, key\)\) return;[^\n]*)/$2$1/'
  echo "-- the file before H5 (8109fa0e, or its -reg twin 2f4eaf58) fails the rows the A12Z failed:"
  for c in 8109fa0e 2f4eaf58; do git -C .. show $c:statusbar/StatusBar.x > "$W/before.x" 2>/dev/null && break; rm -f "$W/before.x"; done
  if [ -s "$W/before.x" ]; then
    out=$(run "$W/before.x" "$W/before" "" nosites 2>&1); n=$?
    f=$(echo "$out" | grep -c '^FAIL ')
    if [ $n -gt 0 ] && [ $n -lt 99 ] && echo "$out" | grep -qF 'FAIL  the close of the iPad'"'"'s last window is seen' && echo "$out" | grep -qF 'FAIL    ... not at the old iPhone window'"'"'s portrait frame' &&
       echo "$out" | grep -qF 'FAIL  the turn to portrait: the new iPhone window is not behind the Dock' && echo "$out" | grep -qF 'FAIL  the turn back: above the Dock' &&
       echo "$out" | grep -qF 'FAIL  its close: its places and its mark go' && echo "$out" | grep -qF 'FAIL  the launch: the closed window'"'"'s places and mark go'; then
      echo "PASS  the file before H5 fails $f checks, among them C17 V2 (the old iPhone window's portrait frame), D5 (behind the Dock at both turns, under the Dock after the turn back), the second close's mark and the open back to back"
    else echo "FAIL  the file before H5 does not fail the device's rows ($n)"; echo "$out" | grep '^FAIL ' | head -20; rc=1; fi
  else echo "SKIP  8109fa0e (2f4eaf58) not in this repository"; fi
fi
[ $rc = 0 ] && echo "test-smturnclosed: everything as it must be" || { echo "test-smturnclosed: FAILED"; exit 1; }
exit 0
