#!/bin/bash
# test-crashguardlook.sh: the crash guard's step 1b at the 8 s look (1.8.7.5, audit L103 of 1.8.7.2). A part that crashes SpringBoard some seconds
# after each start, with crash reports written late: at a start the guard has only one report; at the 8 s look the second has landed, both point
# at the part, and step 1b stops loading it. But the part is loaded in that SpringBoard already, and step 1b's count of crashes "after switching
# off" started at the look: the part crashed that SpringBoard once more, and the next start went straight to step 2 (safe mode) instead of giving
# the skip its start. Now a part skipped at the look counts from the next start (the guard's mark says so: its sixth field); a switch set at the
# look (applied at once) and a skip made at the start (nothing loaded) count from then, as before; a five-field mark (1.8.7.4) reads as before.
# Review of 1.8.7.5: so does a setting SpringBoard reads as it starts, set back at the look -- Menu Bar Size by step 1 (noted since L62) and the
# stock status bar by step 1b: the larger bar or our status bar is still in that SpringBoard, and its own next crash sent the next start to safe
# mode although the cause was already set back.
# Review of round 2: the crash of the SpringBoard that ended just before a start whose time the count starts from (that next start, or a start
# that acted) is not counted from it, whatever second its report names: SpringBoard is often back within the second of its crash, and a report
# written late can name a later second. Before, a count from a start took every report of that start's second, so the crash the skip was to
# forgive sent the next start to safe mode when the restart was quick. The guard tells that SpringBoard's reports by their pid (the reports here
# carry one where it matters, as the system's do); the new SpringBoard's own crash in its first second still counts.
# Real starts of the guard (common/CrashGuard.h MSBDCrashGuardStart) in test-crashguardlook.c, one process each, each on its own clock and wall
# clock (the timers fired and the reports placed by the program in time order), with the real report judge and step 1b's lookup (MacCrashBlame
# built for the Mac with tools/crash-fixtures/test-crashmap.txt) and the step1b-* fixtures. CRASHGUARD_H=<file>: another copy of the guard (e.g.
# the code before the fix: it must fail; its CrashStep.h is the one next to it). Without it, made-to-fail copies follow.
# The guard writes com.besiktasliseba.macstatusbaranddock and step 1b com.besiktasliseba.test-crashstep (the test map's domain): run it only while
# holding the mac-tests lock (as test-crashstep.sh and test-crashguardhang.sh, which use them too). Refused if the Mac has the first.
cd "$(dirname "$0")" || exit 1
GATE=com.besiktasliseba.macstatusbaranddock TD=com.besiktasliseba.test-crashstep DISP=com.besiktasliseba.test-crashguardlook.displays
if defaults read $GATE >/dev/null 2>&1; then echo "the Mac has settings in $GATE: not touching them"; exit 1; fi
W=$(mktemp -d); R="$W/reports"; FIX="$PWD/crash-fixtures"
cleanup() {
  for d in $GATE $TD $TD.dock $DISP; do defaults delete $d >/dev/null 2>&1 || true; defaults read $d >/dev/null 2>&1 || rm -f ~/Library/Preferences/$d.plist; done
  rm -rf "$W"
}
trap cleanup EXIT
G0=${CRASHGUARD_H:-$PWD/../common/CrashGuard.h}
TDISP=(-DMSBD_DISP_DOMAIN="\"$DISP\"" -DMSBD_DISP_MSB_DOMAIN="\"$TD\"" -DMSBD_DISP_DOCK_DOMAIN="\"$TD.dock\"")
mkdir -p "$W/tweaks"   # (1.8.7.7: no tweak installed, no Choicy, an empty death record: the Mac's own are never read)
HR=${CRASHGUARD_HELPER_ROOT:-$PWD/..}
clang -fobjc-arc -dynamiclib -framework Foundation -framework CoreFoundation -DMSBD_CRASHMAP="\"$FIX/test-crashmap.txt\"" "${TDISP[@]}" \
  -DMSBD_CAUSE_FILE="\"$W/causes.txt\"" -DMSBD_CHOICY_PREFS="\"$W/choicy.plist\"" -DMSBD_BLAME_TWEAK_DIR="\"$W/tweaks\"" \
  -o "$W/MacCrashBlame.dylib" "$HR/loader/CrashBlameHelper.m" "$HR/loader/CrashFeatureHelper.m" || exit 1
build() {   # $1 the guard's header (as the test includes it), $2 the program
  clang -Wall -Wno-unused-function -framework CoreFoundation -iquote ../common -DMSBD_TEST_GUARD_H="\"$1\"" \
    -DMSBD_GUARD_FILE="\"$W/guard.txt\"" -DMSBD_GUARD_REPORTS="\"$R\"" -DMSBD_GUARD_VERDICTS="\"$W/verdicts.txt\"" \
    -DMSBD_GUARD_RECORD="\"$W/record.txt\"" -DMSBD_GUARD_RECENT="\"$W/recent.txt\"" -DMSBD_GUARD_NOTICE_LIB="\"$W/missing-notice.dylib\"" \
    -DMSBD_GUARD_BLAME_LIB="\"$W/MacCrashBlame.dylib\"" -DMSBD_STEP_FILE="\"$W/step.txt\"" -DMSBD_CRASHMAP="\"$FIX/test-crashmap.txt\"" \
    -DMSBD_CAUSE_FILE="\"$W/causes.txt\"" "${TDISP[@]}" -o "$2" test-crashguardlook.c
}
fresh() {
  rm -rf "$R" "$W"/guard.txt* "$W"/verdicts.txt* "$W"/record.txt* "$W"/recent.txt "$W"/step.txt*; mkdir -p "$R"
  for d in $GATE $TD $TD.dock $DISP; do defaults delete $d >/dev/null 2>&1 || true; done
}
place() {   # $1 the report's wall time (the crash it tells about), $2 fixture, [$3 the crashed SpringBoard's pid]: a report there before a start
  local to="$R/SpringBoard-$(date -r "$1" +%Y-%m-%d-%H%M%S).ips"
  if [ -n "$3" ]; then sed '2s/^{$/{ "pid": '"$3"',/' "$FIX/$2" > "$to"; else cp "$FIX/$2" "$to"; fi
}
start() {   # $1 program, $2 wall at the start, $3 end s (0: runs 70 s), then "<at s>:<wall>:<fixture>[:<pid>|:self]"...: one SpringBoard start;
  local p=$1; shift   # SKIPPED and SPID (its pid) from its line
  local line; line=$("$p" "$@" 2>/dev/null)
  SKIPPED=$(echo "$line" | sed -n 's/^pid [0-9]* skipped \([01]\)$/\1/p')
  SPID=$(echo "$line" | sed -n 's/^pid \([0-9]*\) skipped [01]$/\1/p')
}
fld() { awk -v i="$1" 'NR == 1 { print $i }' "$W/guard.txt" 2>/dev/null; }   # the guard's mark: pid t0 stage ta fakes [next [prev]]
recent() { echo "$1 $TD $2 $3" > "$W/recent.txt"; }   # (a switch noted by the pages: time, key, row title)
note() { defaults read $GATE crashGuardAction 2>/dev/null; }
safe() { defaults read $GATE crashSafeMode 2>/dev/null; }
B=$(( $(date +%s) / 60 * 60 - 3600 ))   # (the scenarios' clock: an hour ago, whole minutes)
scenarios() {   # $1 program, $2 quiet; the number of failed checks
  local T=$1 q=$2 n=0 W1 W2 W3 T0
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  W1=$((B + 40)); T0=$((W1 - 40)); W2=$((W1 + 33)); W3=$((W2 + 23))
  # A. the entry: the Dock part (DockMagnification) crashes ~30 s after each start, its reports land late
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-dock.ips
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/step1b-dock.ips" "30:$((W1 + 30)):$FIX/step1b-dock.ips"
  c "A. start 1, one Dock crash: nothing at the start; at the 8 s look the second report: step 1b stops loading the Dock" \
    "[ \"\$(note)\" = 4 ] && grep -qx 'part DockMagnification the Dock|the Dock' '$W/record.txt' && grep -q '^skip DockMagnification ' '$W/step.txt' && [ \"\$(fld 3)\" = 1 ] && [ -z \"\$(safe)\" ]"
  c "  ... the Dock was loaded in that SpringBoard (the skip list came after its start)" "[ \"\$SKIPPED\" = 0 ]"
  start "$T" $W2 20 "20:$((W2 + 20)):$FIX/step1b-core-banners.ips"
  c "  start 2, after that SpringBoard's own Dock crash at 30 s: no action (the skip gets its start), no safe mode" "[ \"\$(note)\" = 4 ] && [ -z \"\$(safe)\" ] && grep -qx 'action 4' '$W/record.txt' && [ \"\$(fld 3)\" = 1 ]"
  c "  ... the Dock not loaded there" "[ \"\$SKIPPED\" = 1 ]"
  c "  ... its count of crashes after the skip starts at start 2 (the mark's ta)" "[ \"\$(fld 4)\" = $W2 ]"
  start "$T" $W3 0
  c "  start 3, after a crash of start 2 (at 20 s, not the Dock's): step 2, safe mode on (action 3), the mark gone" \
    "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ] && grep -qx 'action 3' '$W/record.txt' && [ ! -e '$W/guard.txt' ]"
  # B. as before: step 1b at the look that only sets a switch (Mac-Style Banners: applied at once) counts from the look
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-core-banners.ips
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/step1b-core-banners.ips" "30:$((W1 + 30)):$FIX/step1b-core-banners.ips"
  c "B. two banners crashes, the second found at the look: step 1b switches Mac-Style Banners off, its count from the look (ta)" \
    "[ \"\$(note)\" = 4 ] && [ \"\$(defaults read $TD macBanners)\" = 0 ] && [ \"\$(fld 3)\" = 1 ] && [ \"\$(fld 4)\" = $((W1 + 8)) ]"
  start "$T" $W2 0
  c "  start 2, after a crash of that SpringBoard at 30 s: step 2, safe mode on, as before" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ]"
  # C. as before: step 1b at the start (the part never loads in that SpringBoard) counts from the start
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-dock.ips; place $((W1 - 2)) step1b-dock.ips
  start "$T" $W1 30 "30:$((W1 + 30)):$FIX/step1b-core-banners.ips"
  c "C. both Dock reports there at start 1: step 1b at the start, the Dock not loaded, its count from the start" \
    "[ \"\$(note)\" = 4 ] && [ \"\$SKIPPED\" = 1 ] && [ \"\$(fld 3)\" = 1 ] && [ \"\$(fld 4)\" = $W1 ]"
  start "$T" $W2 0
  c "  start 2, after a crash of start 1 at 30 s: step 2, safe mode on, as before" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ]"
  # D. a mark of 1.8.7.4 (five fields) in stage 1 reads as before: crashes count from its ta
  fresh; echo "1 $T0 1 $((W1 - 20)) 0" > "$W/guard.txt"; place $((W1 - 10)) apple-only-our-class-in-reason.ips
  start "$T" $W1 0
  c "D. a five-field mark in stage 1, one crash since its ta: step 2, safe mode on, as before" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ] && [ ! -e '$W/guard.txt' ]"
  # E. a healthy start after the look's skip: the mark goes at 60 s (the row is over), the Dock stays skipped under the note
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-dock.ips
  start "$T" $W1 0 "4:$((W1 - 2)):$FIX/step1b-dock.ips"
  c "E. the look's skip, then that SpringBoard runs: its mark goes at 60 s, the note and the skip list stay" "[ \"\$(note)\" = 4 ] && [ ! -e '$W/guard.txt' ] && grep -q '^skip DockMagnification ' '$W/step.txt'"
  start "$T" $((W1 + 75)) 0
  c "  the next start: a new row, the Dock not loaded" "[ \"\$SKIPPED\" = 1 ] && [ \"\$(note)\" = 4 ] && [ -z \"\$(safe)\" ]"
  # F. (review) Large picked, then crashes with Apple code only, the second report found at the look: step 1 sets Menu Bar Size back, but this
  #    SpringBoard made its bar at the start (Large) and crashes once more
  local A=apple-only-our-class-in-reason.ips
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) $A; recent $((T0 - 60)) menuBarSize "Menu Bar Size"
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/$A" "30:$((W1 + 30)):$FIX/$A"
  c "F. Menu Bar Size noted, two Apple-only crashes, the second found at the look: step 1 sets it back (false), counted from the next start" \
    "[ \"\$(note)\" = 1 ] && [ \"\$(defaults read $TD menuBarSize)\" = 0 ] && grep -qx 'switch $TD menuBarSize Menu Bar Size' '$W/record.txt' && [ \"\$(fld 3)\" = 1 ] && [ \"\$(fld 6)\" = 1 ] && [ -z \"\$(safe)\" ]"
  start "$T" $W2 20 "20:$((W2 + 20)):$FIX/$A"
  c "  start 2, after that SpringBoard's own crash at 30 s (still Large): no action, no safe mode, the note stays" "[ \"\$(note)\" = 1 ] && [ -z \"\$(safe)\" ] && grep -qx 'action 1' '$W/record.txt' && [ \"\$(fld 3)\" = 1 ]"
  c "  ... its count starts at start 2 (the mark's ta)" "[ \"\$(fld 4)\" = $W2 ] && [ \"\$(fld 6)\" = 0 ]"
  start "$T" $W3 0
  c "  start 3, after a crash of start 2 (Small by then): step 2, safe mode on (action 3)" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ] && [ ! -e '$W/guard.txt' ]"
  # G. (review) step 1b at the look turns on the stock status bar (read as SpringBoard starts): also from the next start
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-core-menu.ips
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/step1b-core-menu.ips" "30:$((W1 + 30)):$FIX/step1b-core-menu.ips"
  c "G. two status bar crashes, the second found at the look: step 1b turns on the stock status bar, counted from the next start" \
    "[ \"\$(note)\" = 4 ] && [ \"\$(defaults read $TD stockStatusBar)\" = 1 ] && [ \"\$(fld 3)\" = 1 ] && [ \"\$(fld 6)\" = 1 ] && [ -z \"\$(safe)\" ]"
  start "$T" $W2 20 "20:$((W2 + 20)):$FIX/$A"
  c "  start 2, after that SpringBoard's own crash at 30 s (our status bar still in it): no action, no safe mode" "[ \"\$(note)\" = 4 ] && [ -z \"\$(safe)\" ] && [ \"\$(fld 4)\" = $W2 ]"
  start "$T" $W3 0
  c "  start 3, after a crash of start 2 (the stock status bar by then): step 2, safe mode on" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ]"
  # H. as before: step 1 at the look on a switch that applies at once (Mac-Style Banners) counts from the look
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) $A; recent $((T0 - 60)) macBanners "Mac-Style Banners"
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/$A" "30:$((W1 + 30)):$FIX/$A"
  c "H. Mac-Style Banners noted, the second crash found at the look: step 1 switches it off, its count from the look (ta), as before" \
    "[ \"\$(note)\" = 1 ] && [ \"\$(defaults read $TD macBanners)\" = 0 ] && [ \"\$(fld 4)\" = $((W1 + 8)) ] && [ \"\$(fld 6)\" = 0 ]"
  start "$T" $W2 0
  c "  start 2, after a crash of that SpringBoard at 30 s: step 2, safe mode on, as before" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ]"
  # I. (review of round 2) A with a quick restart: start 2 comes in the second of start 1's own Dock crash at 30 s, so that crash's report names
  #    start 2's second. It is start 1's (its pid): not held against the skip
  local P1 P2 WS=$((W1 + 30))
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-dock.ips
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/step1b-dock.ips:1" "30:$WS:$FIX/step1b-dock.ips:self"; P1=$SPID
  c "I. as A (start 1's own crash reported with its pid): step 1b at the look, counted from the next start" "[ -n '$P1' ] && [ \"\$(note)\" = 4 ] && [ \"\$(fld 6)\" = 1 ]"
  start "$T" $WS 20 "20:$((WS + 20)):$FIX/step1b-core-banners.ips:self"
  c "  start 2 in the second of start 1's crash: no action (the skip gets its start), no safe mode" "[ \"\$(note)\" = 4 ] && [ -z \"\$(safe)\" ] && grep -qx 'action 4' '$W/record.txt' && [ \"\$(fld 3)\" = 1 ]"
  c "  ... its count starts at start 2, start 1 the SpringBoard before it (the mark's ta and prev)" "[ \"\$(fld 4)\" = $WS ] && [ \"\$(fld 7)\" = '$P1' ]"
  start "$T" $((WS + 23)) 0
  c "  start 3, after a crash of start 2 (at 20 s): step 2, safe mode on, the mark gone" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ] && [ ! -e '$W/guard.txt' ]"
  # II. (review of round 2) start 1's crash at 30 s reported late, at start 2's 3 s, naming the second after start 2's: not held against the skip
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-dock.ips
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/step1b-dock.ips:1"; P1=$SPID
  start "$T" $((WS + 1)) 20 "3:$((WS + 2)):$FIX/step1b-dock.ips:$P1" "20:$((WS + 21)):$FIX/step1b-core-banners.ips:self"
  c "II. start 1's crash reported after start 2 began, a second later than its start: no action at start 2's look, no safe mode" \
    "[ -n '$P1' ] && [ \"\$(note)\" = 4 ] && [ -z \"\$(safe)\" ] && [ \"\$(fld 3)\" = 1 ] && [ \"\$(fld 4)\" = $((WS + 1)) ]"
  start "$T" $((WS + 24)) 0
  c "  start 3, after a crash of start 2: step 2, safe mode on" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ]"
  # III. (review of round 2) start 2's own crash in its own first second (the second of start 1's crash) counts: only start 1's is before it
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-dock.ips
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/step1b-dock.ips:1" "30:$WS:$FIX/step1b-dock.ips:self"
  start "$T" $WS 0.5 "0.5:$WS:$FIX/step1b-core-banners.ips:self"; P2=$SPID
  c "III. start 2 in the second of start 1's crash, crashing within that second: no action at its start (it had not crashed yet)" \
    "[ -n '$P2' ] && [ \"\$(note)\" = 4 ] && [ -z \"\$(safe)\" ] && [ \"\$(fld 1)\" = '$P2' ]"
  start "$T" $((WS + 3)) 0
  c "  start 3: start 2's crash of that same second counts: step 2, safe mode on" "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ]"
  # IV. (review of round 2) step 1b at start 1 for crashes before it, the last in start 1's own second (SpringBoard pid 1's); start 1 ends at
  #     30 s without a crash (a respring): start 2 does not count that crash again (before: safe mode)
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) step1b-dock.ips 1; place $W1 step1b-dock.ips 1
  start "$T" $W1 30
  c "IV. both Dock reports there at start 1, the second of its own second: step 1b at the start, counted from it, SpringBoard 1 before it" \
    "[ \"\$(note)\" = 4 ] && [ \"\$SKIPPED\" = 1 ] && [ \"\$(fld 3)\" = 1 ] && [ \"\$(fld 4)\" = $W1 ] && [ \"\$(fld 7)\" = 1 ]"
  start "$T" $((W1 + 33)) 0
  c "  start 2, after start 1 ended without a crash: no action, no safe mode, the row over at 60 s" "[ \"\$(note)\" = 4 ] && [ -z \"\$(safe)\" ] && [ ! -e '$W/guard.txt' ]"
  # V. (review of round 2) step 1 at start 1 (a noted switch) for two crashes before it, the last (the Dock's) in start 1's own second; start 1
  #    crashes with Apple code only: step 1b looks at the crashes after step 1 only, as when that Dock crash is a second earlier: step 2
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) $A 1; place $W1 step1b-dock.ips 1; recent $((T0 - 60)) macBanners "Mac-Style Banners"
  start "$T" $W1 20 "20:$((W1 + 20)):$FIX/$A:self"
  c "V. a noted switch, two crashes, the Dock's in start 1's own second: step 1 at the start, SpringBoard 1 before it" \
    "[ \"\$(note)\" = 1 ] && [ \"\$(fld 4)\" = $W1 ] && [ \"\$(fld 7)\" = 1 ]"
  start "$T" $((W1 + 23)) 0
  c "  start 2, after start 1's Apple-only crash: the Dock not blamed for the crash before step 1: step 2, safe mode on" \
    "[ \"\$(note)\" = 3 ] && [ \"\$(safe)\" = 1 ] && ! grep -q '^skip DockMagnification ' '$W/step.txt' 2>/dev/null"
  # 1.8.7.7 (GitHub #14), with the REAL reports (trimmed): crashes with only Apple code on their stacks while other tweaks are loaded are not pinned
  # on us any more. J. the reporter's row: two popover aborts, the second reported late (found at the look), then the wallpaper tweak's crash,
  #    then the Do Not Disturb listener's: nothing at any start or look (before: safe mode at the first look, "turned off after SpringBoard crashed
  #    twice")
  local P14=real-issue14-popover-1.ips Q14=real-issue14-popover-2.ips
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) $P14
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/$Q14" "30:$((W1 + 30)):$FIX/real-issue14-wallpaper-tweak.ips"
  c "J. #14: two popover aborts, the second found at the look: no action, no safe mode, no record (the row goes on)" \
    "[ -z \"\$(note)\" ] && [ -z \"\$(safe)\" ] && [ ! -e '$W/record.txt' ] && [ \"\$(fld 3)\" = 0 ] && [ \"\$(fld 2)\" = $T0 ]"
  c "  ... the verdicts kept as not pinned (4), with what crashed" "grep -q '4 Apple_code_only;_3_other_tweaks_loaded	' '$W/verdicts.txt' && grep -q 'presentationTransitionWillBegin' '$W/verdicts.txt'"
  start "$T" $W2 20 "20:$((W2 + 20)):$FIX/real-issue14-dnd-listener.ips"
  c "  start 2, after the wallpaper tweak's crash: no action, no safe mode" "[ -z \"\$(note)\" ] && [ -z \"\$(safe)\" ] && [ ! -e '$W/record.txt' ]"
  start "$T" $W3 0
  c "  start 3, after the Do Not Disturb listener's crash (another tweak's crash in the row): no action, no safe mode, the row over at 60 s" \
    "[ -z \"\$(note)\" ] && [ -z \"\$(safe)\" ] && [ ! -e '$W/record.txt' ] && [ ! -e '$W/guard.txt' ]"
  # K. the same two right after a switch was turned on: step 1 only (that switch), at the look; one more not pinned on anyone: nothing more
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) $P14; recent $((T0 - 60)) macBanners "Mac-Style Banners"
  start "$T" $W1 30 "4:$((W1 - 2)):$FIX/$Q14" "30:$((W1 + 30)):$FIX/$P14"
  c "K. a switch noted, then two crashes not pinned on anyone: step 1 at the look, only that switch (no step 1b, no safe mode)" \
    "[ \"\$(note)\" = 1 ] && [ \"\$(defaults read $TD macBanners)\" = 0 ] && grep -qx 'unknown 2' '$W/record.txt' && [ -z \"\$(safe)\" ] && [ ! -e '$W/step.txt' ]"
  start "$T" $W2 0
  c "  start 2, after one more such crash: no further step, no safe mode" "[ \"\$(note)\" = 1 ] && [ -z \"\$(safe)\" ]"
  # L. one of ours (the 17.5's Notification Center crash, ours through our hooks) seconded by a popover abort found at the look: the guard acts
  fresh; echo "1 $T0 0 0 0" > "$W/guard.txt"; place $((T0 + 10)) real-175-nc-pull-ours.ips
  start "$T" $W1 0 "4:$((W1 - 2)):$FIX/$P14"
  c "L. a crash of ours and one not pinned on anyone, the second found at the look: step 1b (the status bar's fallback), no safe mode" \
    "[ \"\$(note)\" = 4 ] && [ \"\$(defaults read $TD stockStatusBar)\" = 1 ] && grep -qx 'verdict 1' '$W/record.txt' && [ -z \"\$(safe)\" ]"
  return $n
}

build "$G0" "$W/t" || exit 1
scenarios "$W/t"; rc=$?
if [ -z "$CRASHGUARD_H" ]; then
  mtf() {   # $1 name, $2 file (CrashGuard.h or CrashStep.h), $3.. sed arguments that take one part of the fix out
    local name=$1 file=$2; shift 2
    rm -rf "$W/mtf"; mkdir -p "$W/mtf"; cp ../common/CrashGuard.h ../common/CrashStep.h "$W/mtf/"
    sed -i '' "$@" "$W/mtf/$file"
    if cmp -s "$W/mtf/$file" "../common/$file"; then echo "FAIL  made-to-fail ($name): the copy did not change"; rc=1; return; fi
    if ! build "$W/mtf/CrashGuard.h" "$W/tm"; then echo "FAIL  made-to-fail ($name): did not build"; rc=1; return; fi
    if scenarios "$W/tm" quiet; then echo "FAIL  made-to-fail ($name): the checks still pass"; rc=1; else echo "PASS  made-to-fail ($name): caught"; fi
  }
  mtf "a skip at the look counts from the look (the code before L103)" CrashGuard.h -e 's/s->next = !gMSBDGuardAtStart \&\& (action == 1 || action == MSBD_GUARD_ACTION_FEATURE) \&\& gMSBDGuardNextStartNow > 0;/s->next = 0;/'
  mtf "the next start does not move ta" CrashGuard.h -e '/if (early \&\& s.stage == 1 \&\& s.next) {/d'
  mtf "a switch set at the look counts from the next start too" CrashGuard.h -e 's/ \&\& gMSBDGuardNextStartNow > 0;/;/'
  mtf "a skip at the start counts from the next start too" CrashGuard.h -e 's/s->next = !gMSBDGuardAtStart \&\& /s->next = /'
  mtf "step 1b does not count its parts" CrashStep.h -e '/gMSBDGuardNextStartNow++;   \/\/ (it stops loading/d'
  mtf "step 1 at the look counts from the look (the code before the review)" CrashGuard.h -e 's/(action == 1 || action == MSBD_GUARD_ACTION_FEATURE) \&\& gMSBDGuardNextStartNow/action == MSBD_GUARD_ACTION_FEATURE \&\& gMSBDGuardNextStartNow/'
  mtf "step 1 does not count a setting read at the start" CrashGuard.h -e '/if (MSBDGuardSetAtNextStart(domain, key)) gMSBDGuardNextStartNow++;/d'
  mtf "step 1b does not count a setting read at the start" CrashStep.h -e '/if (MSBDGuardSetAtNextStart(domain, key)) gMSBDGuardNextStartNow++;/d'
  mtf "Menu Bar Size not read at the start" CrashGuard.h -e 's/strcmp(key, kMSBDMenuBarSizeKey) == 0 || //'
  mtf "the stock status bar not read at the start" CrashGuard.h -e 's/ || strcmp(key, "stockStatusBar") == 0//'
  mtf "a five-field mark not read" CrashGuard.h -e 's/ok = n >= 5;/ok = n >= 6;/'
  mtf "the crash of the SpringBoard before a start's count counted (the code before the review of round 2)" CrashGuard.h -e 's/if (prev > 0 \&\& MSBDGuardReportPid(path) == prev)/if (0)/'
  mtf "only a report of the start's own second told apart" CrashGuard.h -e 's/if (prev > 0 \&\& MSBDGuardReportPid(path) == prev)/if (prev > 0 \&\& t == since \&\& MSBDGuardReportPid(path) == prev)/'
  mtf "a start's count from the second after it, no pid" CrashGuard.h -e 's/if (t < since) return 0;/if (t < since + (prev > 0)) return 0;/' -e 's/if (prev > 0 \&\& MSBDGuardReportPid(path) == prev)/if (0)/'
  mtf "the next start does not keep the SpringBoard before it" CrashGuard.h -e 's/s.ta = now; s.next = 0; s.prev = prev;/s.ta = now; s.next = 0;/'
  mtf "a start that acts does not keep the SpringBoard before it" CrashGuard.h -e 's/s->prev = gMSBDGuardAtStart ? gMSBDGuardPrevPid : 0;/s->prev = 0;/'
  mtf "step 1b counts the crash of the SpringBoard before a start's count" CrashStep.h -e 's/if (MSBDGuardFrom(e->d_name, p, t, since, prev) \&\& /if (t >= since \&\& /'
  mtf "the mark's seventh field not written" CrashGuard.h -e 's/, s->next, s->prev, s->wfakes);/, s->next, 0, s->wfakes);/'
  mtf "a seven-field mark not read" CrashGuard.h -e 's/ok = n >= 5;/ok = n >= 5 \&\& n < 7;/'
  mtf "an Apple-only crash with other tweaks loaded is strong (the code before 1.8.7.7)" CrashGuard.h -e 's/{ return v == kMSBDVerdictUnpinned; }/{ return 0; }/'
  mtf "no rule 2 (a weak crash cannot second one of ours)" CrashGuard.h -e 's/if (S >= 2 || (S == 1 \&\& W >= 1))/if (S >= 2)/'
  mtf "no rule 3 (no step 1 for crashes right after a switch)" CrashGuard.h -e 's/else if (S == 0 \&\& W >= 2 \&\& recent) {/else if (0) {/'
fi
[ $rc = 0 ] && echo "test-crashguardlook: all pass" || echo "test-crashguardlook: FAILED"
exit $rc
