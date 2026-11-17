#!/bin/bash
# test-startupwatch.sh: the start-up watcher stops once the Lock Screen's bar is laid out, instead of laying it out again every frame for 12 s after
# each boot or respring onto the Lock Screen (1.8.7.4, audit O2 of 1.8.7.2); an empty copy, a copy still being built, the clock layout, nothing found
# and DMEnsureLogo's look as before. See test-startupwatch.m. The real code is cut out of statusbar/StatusBar.x (SW_SB_X: another copy, e.g. the code
# before the fix, which has no DMStartupLockScreenDressed) and run on the Mac; then site checks on StatusBar.x (the copy's own layout pass releases the
# same layout, the unlock lays out copies not ours yet, DMEnsureLogo's look); then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SW_SB_X:-../statusbar/StatusBar.x}
# one function of a file, from its first line to its closing brace
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; next } f { print } f && /^[}]/ { exit }' "$1"; }
SW_FN=('static void DMHoldStatusBarCopy(UIView *fg) {' 'static void DMReleaseStatusBarCopy(UIView *fg) {' 'static UIView *DMFindForegroundView(UIView *v) {'
       'static BOOL DMStartupLockScreenDressed(UIView *fg) {' 'static void DMEnsureLogo(int attempt) {')
SW_NEW='static BOOL DMStartupLockScreenDressed(UIView *fg) {'   # (the fix's: not in the code before it)

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0
  # the status icon test is DMLayoutWithoutClock's own (a status icon it closes up = one that makes the copy dressed)
  if [ -z "$(fn "$X" "$SW_NEW")" ] || { fn "$X" 'static BOOL DMLayoutWithoutClock(UIView *fg) {' | grep -qF 'if (sub.hidden || sub.alpha < 0.05 || sub.bounds.size.width < 1.0) continue;' &&
       fn "$X" "$SW_NEW" | grep -qF 'if (!sub.hidden && sub.alpha >= 0.05 && sub.bounds.size.width >= 1.0) return YES;'; }; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: a status icon is what DMLayoutWithoutClock closes up (shown, alpha 0.05 or more, 1 pt wide or more)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the watcher's status icon test is not DMLayoutWithoutClock's"; n=$((n + 1)); fi
  # the copy's own layout pass releases the same layout (ours: the clock layout or the Lock Screen's, kNoClockLayoutKey)
  if grep -qF '    if (objc_getAssociatedObject(self, kLogoKey) || objc_getAssociatedObject(self, kNoClockLayoutKey)) DMReleaseStatusBarCopy((UIView *)self);' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the copy's own layout pass releases it after the clock layout or the Lock Screen's (kNoClockLayoutKey)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the copy's own layout pass no longer releases the Lock Screen's layout"; n=$((n + 1)); fi
  # the unlock lays out every copy not ours yet (every iPadOS since 1.8.7.7: there is no pass of iOS's own on 15/16 either -- test-wifirecheck.sh),
  # the Lock Screen's included (only the logo skips it)
  if fn "$X" 'static void DMRelayoutUnattachedBars(NSString *why) {' | grep -qF '        if (!fg.window || objc_getAssociatedObject(fg, kLogoKey)) continue;' &&
     fn "$X" 'static void DMBarCoverLeaving(void) {' | grep -qF 'DMRelayoutUnattachedBars(@"the Cover Sheet starts to leave");' &&
     fn "$X" 'static void DMWatchLock(void) {' | grep -qF '    DMRelayoutUnattachedBars(locked ? @"locked" : @"unlocked");'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the unlock (the Cover Sheet leaving, the reported unlock) lays out every copy without the logo"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the unlock no longer lays out a copy laid out the Lock Screen's way"; n=$((n + 1)); fi
  # the constructor: the watcher started on the main queue, DMEnsureLogo 2 s after (41 looks, attempt < 40)
  if grep -qF "    if (!DMCtorSkip(\"startup\")) dispatch_async(dispatch_get_main_queue(), ^{ DMStartStartupWatcher(); });" "$X" &&
     awk 'index($0, "    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),") == 1 { a = NR } a && NR - a < 14 && index($0, "        DMEnsureLogo(0); DMTick(); });") == 1 { ok = 1; exit } END { exit !ok }' "$X" &&
     fn "$X" 'static void DMEnsureLogo(int attempt) {' | grep -qF '    if (attempt < 40) {'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the watcher starts with SpringBoard, DMEnsureLogo looks once a second from 2 s (41 looks)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the watcher's start or DMEnsureLogo's look changed"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (99: not built)
  local X=$1 d=$2 q=$3 h n s out
  mkdir -p "$d"
  for h in "${SW_FN[@]}" '@interface DMStartupWatcher : NSObject' 'static void DMStartStartupWatcher(void) {' '- (void)dm_layoutLogoBody {'; do
    [ "$h" = "$SW_NEW" ] && continue
    grep -qF -- "$h" "$X" || { echo "FAIL  $X: no \"$h\""; return 99; }
  done
  [ -n "$(fn "$X" "$SW_NEW")" ] || { [ -n "$q" ] || echo "   (no DMStartupLockScreenDressed: the code before the fix)"; }
  {
    # (the ask of iOS's items that a hold's release makes, 1.8.7.7: DMBarItemsAskAgain and its mark -- none in the code before it)
    fn "$X" 'static void DMHoldStatusBarCopy(UIView *fg) {'; awk 'index($0, "static const void *kItemsAskKey = &kItemsAskKey;") == 1 { print; exit }' "$X"
    fn "$X" 'static void DMBarItemsAskAgain(UIView *fg) {'; fn "$X" 'static void DMReleaseStatusBarCopy(UIView *fg) {'; fn "$X" 'static UIView *DMFindForegroundView(UIView *v) {'
    fn "$X" "$SW_NEW"
    awk 'index($0, "@interface DMStartupWatcher : NSObject") == 1 { f = 1 } f { print } index($0, "static void DMStartStartupWatcher(void) {") == 1 { s = 1 } s && /^[}]/ { exit }' "$X"
    fn "$X" 'static void DMEnsureLogo(int attempt) {'
  } > "$d/startupwatch-real.inc"
  # the no-clock part of the copy's layout: from the leading region's lookup to the end of its branch
  awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { b = 1 } b && index($0, "    UIView *container = DMLeadingContainer(fg);") == 1 { f = 1 } f { print } f && /^    [}]$/ { exit }' "$X" > "$d/startupwatch-noclock.inc"
  grep -qF 'objc_setAssociatedObject(fg, kNoClockLayoutKey, (laidOut && (lockedNow || keepsLockedLook))' "$d/startupwatch-noclock.inc" || { echo "FAIL  $X: the no-clock layout was not found"; return 99; }
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
        -framework Foundation -o "$d/t" test-startupwatch.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-startupwatch: all pass" || echo "test-startupwatch: FAILED ($rc check(s))"
if [ -z "$SW_SB_X" ]; then
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
  mtf "the Lock Screen's layout is not counted (every frame for 12 s again)" 's/\n        else if \(DMStartupLockScreenDressed\(fg\)\) \{[^\n]*//'
  mtf "any layout without a clock counts, not only the locked one" 's/ \|\| !\[objc_getAssociatedObject\(fg, kBarLaidOutLockedKey\) boolValue\]\) return NO;/) return NO;/'
  mtf "an empty copy counts (no status icon needed)" 's/(static BOOL DMStartupLockScreenDressed\(UIView \*fg\) \{\n[^\n]*\n)[^\n]*\n[^\n]*\n    return NO;/$1    return YES;/'
  mtf "the copy not released when the watcher stops on the Lock Screen" 's/else if \(DMStartupLockScreenDressed\(fg\)\) \{ DMReleaseStatusBarCopy\(fg\); lockScreen = YES; \}/else if (DMStartupLockScreenDressed(fg)) { lockScreen = YES; }/'
  mtf "released, but the watcher goes on" 's/if \(attached \|\| lockScreen \|\| link\.timestamp/if (attached || link.timestamp/'
  mtf "the clock layout no longer stops it" 's/if \(objc_getAssociatedObject\(fg, kLogoKey\)\) \{ DMReleaseStatusBarCopy\(fg\); attached = YES; \}\n        else if/if (0) { }\n        else if/'
  mtf "DMEnsureLogo looks only once" 's/    if \(attempt < 40\) \{/    if (attempt < 0) {/'
fi
exit $rc
