#!/bin/bash
# Mac test of the App Switcher clean-up (statusbar/SwitcherStale.h, StatusBar.x DMCleanStaleSwitcherCards; test-switcherstale.m): the cards iPadOS
# brings back after a respring stay (a window engine switch, 17.5.1, 29 Oct); only the card of an app that went away while SpringBoard ran goes,
# after the grace, and only when the user quit it or it crashed: one iPadOS ended for memory, a time-out or the watchdog keeps its card (1.8.7.4,
# audit M3 of 1.8.7.2). The user's quit is how the app last ended (a kill for the user's quit, then its end), not the prewarm quit set: an app quit,
# running again without coming in front, then ended by iPadOS keeps its card (review of the M3 fix). The rule, the exit read (on this Mac's
# RunningBoard and FrontBoard) and the real clean-up and kill hook cut out of StatusBar.x (SST_H / SST_SB_X: other copies, e.g. the code before the
# fix); then site checks on StatusBar.x; then made-to-fail copies: each must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H0=${SST_H:-../statusbar/SwitcherStale.h}; X0=${SST_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
SST_SBX=('static NSSet<NSString *> *DMSwitcherBundleIDs(id sw) {' 'static NSMutableDictionary<NSString *, NSNumber *> *DMStaleCandidates(void) {'
         'static void DMNoteAppInFront(NSString *bid) {' 'static void DMCleanStaleSwitcherCards(id sw, NSString *reason) {')
SST_SBX_NEW='static void DMNoteAppExit(NSString *bid, id context) {'   # (cut out when there: the code before the fix has none)
SST_SBX_QUIT='static void DMNoteAppQuitting(NSString *bid) {'   # (cut out when there: the M3 fix before its review has none)
SST_SBX_KILL='static void DMPrewarmQuitAddFromKill(id process, long long reason) {'   # (the kill hook's body: last, it calls the one above)

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0 r
  # the exit hook: SpringBoard's exit callback notes every app's end before SpringBoard's own work
  r=$(awk '/^%group SwitcherExitKind$/ {g=1; next} g && /^%hook SBApplication$/ {h=1; next} h && /^- \(void\)_didExitWithContext:\(id\)context \{$/ {m=1; next}
           m && /^    DMNoteAppExit\(\[\(SBApplication \*\)self bundleIdentifier\], context\);$/ {d=1; next} m && /^    %orig;$/ {o=d; exit} m && /^[}]/ {exit} END {print o+0}' "$X")
  if [ "$r" = 1 ]; then [ -n "$q" ] || echo "PASS  StatusBar.x: SwitcherExitKind hooks SBApplication's exit callback and notes the end (DMNoteAppExit) before %orig"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: no SwitcherExitKind hook noting each app's end (DMNoteAppExit) before %orig"; n=$((n + 1)); fi
  # installed with the switcher's hooks (every engine and none), unconditionally, once
  r=$(awk '/^static void DMSwitcherHooksInit\(void\) \{$/ {f=1; next} f && /^[}]/ {exit} f && /^    %init\(SwitcherExitKind\);/ {k++} END {print k+0}' "$X")
  if [ "$r" = 1 ] && [ "$(grep -c '%init(SwitcherExitKind)' "$X")" = 1 ] && grep -q '^    if (!DMCtorSkip("switcher")) { DMRinger18Init(); DMSwitcherHooksInit(); }' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the exit hook is installed once, with the switcher's hooks (every engine and none), not with an engine's"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the exit hook is not installed once, unconditionally, in DMSwitcherHooksInit"; n=$((n + 1)); fi
  # one caller of the rule, handed the apps whose last end was the user's quit or a crash (not the prewarm quit set)
  r=$(fn "$X" "${SST_SBX[3]}")
  if [ "$(grep -c 'MSBDStaleCards(' "$X")" = 1 ] && echo "$r" | grep -qF 'NSMutableSet<NSString *> *quit = [NSMutableSet set];' &&
     echo "$r" | grep -qF 'if (gAppsEndedByQuit) [quit unionSet:gAppsEndedByQuit];' && ! echo "$r" | grep -q 'gPrewarmQuitSet' &&
     echo "$r" | grep -qF 'if (gAppsEndedInCrash) [quit unionSet:gAppsEndedInCrash];' && echo "$r" | grep -qF 'gAppsInFrontSinceStart, quit, frontBid,'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the clean-up alone calls the rule, with the apps whose last end was the user's quit or a crash"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the rule's caller does not hand it the apps whose last end was the user's quit or a crash"; n=$((n + 1)); fi
  # the user's quit is noted at the one kill hook every quit passes (both FrontBoard kill methods call it: test-switcherquit), once, after its reason test
  r=$(fn "$X" "$SST_SBX_KILL")
  if [ "$(grep -c '^    DMNoteAppQuitting(bid);' "$X")" = 1 ] && echo "$r" | awk '/^    if \(reason != 1\) return;$/ {a=NR} /^    DMNoteAppQuitting\(bid\);/ {b=NR} END {exit !(a && b > a)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the kill hook notes the user's quit for the app's coming end (DMNoteAppQuitting), only for reason 1"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the kill hook does not note the user's quit for the app's coming end"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 SwitcherStale.h, $2 StatusBar.x, $3 work dir, $4 quiet; the number of failed checks (99: did not build)
  local H=$1 X=$2 d=$3 q=$4 n=0 s h out defs=""
  mkdir -p "$d/statusbar" "$d/tools"
  cp "$H" "$d/statusbar/SwitcherStale.h" && cp test-switcherstale.m "$d/tools/" || return 99
  grep -qF 'NSSet<NSString *> *quit,' "$d/statusbar/SwitcherStale.h" || defs="$defs -DSST_OLD_RULE"
  grep -q 'MSBDExitContextIsCrash' "$d/statusbar/SwitcherStale.h" || defs="$defs -DSST_NO_EXIT_RULE"
  for h in "${SST_SBX[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  [ -n "$(fn "$X" "$SST_SBX_KILL")" ] || { echo "FAIL  $X: no function starting \"$SST_SBX_KILL\""; return 99; }
  { for h in "${SST_SBX[@]}"; do fn "$X" "$h"; done; fn "$X" "$SST_SBX_NEW"; fn "$X" "$SST_SBX_QUIT"; fn "$X" "$SST_SBX_KILL"; } > "$d/tools/sst-real.inc"
  [ -n "$(fn "$X" "$SST_SBX_NEW")" ] || defs="$defs -DSST_NO_EXIT_NOTE"
  [ -n "$(fn "$X" "$SST_SBX_QUIT")" ] || defs="$defs -DSST_NO_QUIT_END"
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration $defs -framework Foundation \
        -o "$d/t" "$d/tools/test-switcherstale.m" 2>"$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; return 99; }
  [ -n "$defs" ] && [ -z "$q" ] && echo "   (built as the code before the fix:$defs)"
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$q"; s=$?
  return $((n + s))
}

run "$H0" "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-switcherstale: all pass" || echo "test-switcherstale: FAILED ($rc check(s))"
if [ -z "$SST_H$SST_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (h|sbx), $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" H=$H0 X=$X0 c
    mkdir -p "$d"
    if [ "$2" = h ]; then c="$d/SwitcherStale.h"; perl -0777 -pe "$3" "$H0" > "$c"; H=$c; cmp -s "$c" "$H0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    else c="$d/StatusBar.x"; perl -0777 -pe "$3" "$X0" > "$c"; X=$c; cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }; fi
    run "$H" "$X" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  k=0
  mtf "\"not running\" taken for a quit again (the quit set left out of the rule)" h 's/\[inFront containsObject:b\] && \[quit containsObject:b\] && /[inFront containsObject:b] && /'
  mtf "a kill (SIGKILL) taken for a crash" h 's/case SIGSYS: return YES;/case SIGSYS: case SIGKILL: return YES;/'
  mtf "an end for memory taken for a crash" h 's/(    if \(domain != kMSBDExitDomainSignal\) return NO;)/    if (domain == 1) return YES;\n$1/'
  mtf "any exit status that can be read taken for a crash" h 's/return MSBDExitStatusIsCrash\(\(\(unsigned/return YES || MSBDExitStatusIsCrash(((unsigned/'
  mtf "the crash read off the context itself, not its RunningBoard context" h 's/id rbs = \[context respondsToSelector:under\] \? \(\(id \(\*\)\(id, SEL\)\)objc_msgSend\)\(context, under\) : nil;/id rbs = context;/'
  mtf "the crashes left out of the clean-up (a crash keeps its card)" sbx 's/\n    if \(gAppsEndedInCrash\) \[quit unionSet:gAppsEndedInCrash\];//'
  mtf "the user's quits left out of the clean-up" sbx 's/\n    if \(gAppsEndedByQuit\) \[quit unionSet:gAppsEndedByQuit\];//'
  mtf "the prewarm quit set taken for the user's quit again (the M3 fix before its review)" sbx 's/NSMutableSet<NSString \*> \*quit = \[NSMutableSet set\];/NSMutableSet<NSString *> *quit = [NSMutableSet setWithArray:gPrewarmQuitSet ?: \@[]];/'
  mtf "a quit never forgotten (a later end for memory still takes the card)" sbx 's/if \(quit\) \[gAppsEndedByQuit addObject:b\]; else \[gAppsEndedByQuit removeObject:b\];/if (quit) [gAppsEndedByQuit addObject:b];/'
  mtf "the quit's note kept past its end (the next end taken for a quit too)" sbx 's/\n        \[gAppsQuitting removeObject:b\];//'
  mtf "the kill no longer notes the user's quit" sbx 's/\n    DMNoteAppQuitting\(bid\);[^\n]*//'
  mtf "a kill for any reason taken for the user's quit" sbx 's/(static void DMPrewarmQuitAddFromKill\(id process, long long reason\) \{\n)    if \(reason != 1\) return;/$1    if (reason < 0) return;/'
  mtf "the quit noted off the main thread" sbx 's/    if \(\[NSThread isMainThread\]\) note\(\);\n    else dispatch_async\(dispatch_get_main_queue\(\), note\);   \/\/ \(in order/    note(); \/\/ (in order/'
  mtf "a crash never forgotten (a later end for memory still takes the card)" sbx 's/if \(crash\) \[gAppsEndedInCrash addObject:b\]; else \[gAppsEndedInCrash removeObject:b\];/if (crash) [gAppsEndedInCrash addObject:b];/'
  mtf "the record changed off the main thread" sbx 's/    if \(\[NSThread isMainThread\]\) note\(\); else dispatch_async\(dispatch_get_main_queue\(\), note\);/    note();/'
  mtf "the exit hook installed only with an engine (none: no crash noted)" sbx 's/\n    %init\(SwitcherExitKind\);[^\n]*//; s/(\n    %init\(AppExitForget\);)/$1\n    %init(SwitcherExitKind);/'
  mtf "the exit hook no longer notes the end" sbx 's/\n    DMNoteAppExit\(\[\(SBApplication \*\)self bundleIdentifier\], context\);//'
  mtf "the grace shortened (a launch's card taken)" h 's/kMSBDStaleCardGrace = 4\.0;/kMSBDStaleCardGrace = 0.0;/'
fi
exit $rc
