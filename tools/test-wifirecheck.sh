#!/bin/bash
# test-wifirecheck.sh: the menu bar after a respring onto the Lock Screen (GitHub issue #14, iPad Air 5 16.3.1, 1.8.7.5: two Wi-Fi icons after the
# unlock, one going a while later, whether unlocked at once or after a minute, and sometimes iPadOS's stock bar instead of ours). See
# test-wifirecheck.m. The real code is cut out of statusbar/StatusBar.x (WR_SB_X: another copy, e.g. the code before the fix) and run on the Mac,
# both families (15/16 UIKit's bar, 17/18 SystemStatusUI's), one row per process: the hold and its release, the ask of iOS's items, iOS's Wi-Fi
# item's answer, the copy's own layout pass (-layoutSubviews and -didMoveToWindow hooks), -dm_layoutLogo, the no-clock layout and the newlyOurs
# block of -dm_layoutLogoBody, the start-up watcher, DMEnsureLogo, the unlock (DMBarCoverLeaving, DMWatchLock with DMSkipLockAfterRespring and K-5,
# DMRelayoutUnattachedBars), the time label's arrival (DMClockBackNow on 15/16, DMAttachIfFilledNow on 17/18) and DMStatusIconsUpdated. Then site
# checks on StatusBar.x (what the model wires as SpringBoard does); then made-to-fail copies: each takes one part of the fix out and must fail.
# Rows 20-24 (1.8.7.6, the iPad 2's f03 pass): a Notification Center pull let go and a full pull, the time label back inside the bar's own constraint
# pass (DMBarDecideNextTurn cut out too) or outside it: the copy laid out with its clock in that frame, never inside the pass.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${WR_SB_X:-../statusbar/StatusBar.x}
# a static function's definition, whole, by its braces (the first line has its name and "{")
fndef() {
  awk -v n="$2" '
    !f && $0 ~ ("^static [^(=]*[ *]" n "\\(") && index($0, "{") { f = 1 }
    f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }
  ' "$1"
}
ln1() { awk -v h="$2" 'index($0, h) == 1 { print; exit }' "$1"; }
# a method's body (without its first and last lines) in the file, the one whose block holds `$3`; %orig; becomes `$4`
body() {
  awk -v h="$2" -v m="$3" -v r="$4" '
    index($0, h) == 1 && !done { f = 1; b = ""; next }
    f && /^[}]/ { if (index(b, m)) { printf "%s", b; done = 1 } f = 0; next }
    f { s = $0; gsub(/%orig;/, r, s); b = b s "\n" }
  ' "$1"
}
WR_NEED=(DMCall DMSBIs DMSBIsBarWindowName DMLockUp DMHideStockWiFi DMWiFiItemCanEnable DMStockWiFiInit DMStockVPNRecheck DMBarCopyPooled
         DMHoldStatusBarCopy DMHoldSafetyCheck DMReleaseStatusBarCopy DMStatusIconsUpdated DMFindForegroundView DMStartupLockScreenDressed DMEnsureLogo
         DMSkipLockAfterRespring DMBarCoverLeaving DMRelayoutUnattachedBars DMHideAppBarItemsNow DMWatchLock DMAttachIfFilledNow DMAttachIfFilled
         DMClockBackNow DMClosedUpClockBack DMClockBackLayout)

sites() {   # $1 StatusBar.x, $2 quiet: the number of site checks that fail
  local X=$1 q=$2 n=0 lib
  # every direct layout of a copy is one this test knows (6): the own pass, the watcher, DMEnsureLogo, DMSMRefreshBars, the front watch over gCopies
  # (copies already ours) and DMSMChrome; each reaches the newlyOurs block. A new one: does it hold the copy, or rely on the newlyOurs ask?
  if [ "$(/usr/bin/grep -c 'dm_layoutLogo\]' "$X")" = 6 ] && /usr/bin/grep -qF '    [self dm_layoutLogo];' "$X" &&
     awk 'index($0, "        for (UIView *fg in gCopies.allObjects) {") == 1 { p = NR } index($0, "            if ((frontChanged || ownChanged) && fg.window) [(_UIStatusBarForegroundView *)fg dm_layoutLogo];") == 1 && p == NR - 1 { ok = 1 } END { exit !ok }' "$X" &&
     /usr/bin/grep -qF 'if (fgc && [v isKindOfClass:fgc]) { [(_UIStatusBarForegroundView *)v dm_layoutLogo];' "$X" &&
     awk 'index($0, "void DMSMRefreshBars(void) {") == 1 { f = 1 } f && /^[}]/ { exit } f && index($0, "        [(_UIStatusBarForegroundView *)fg dm_layoutLogo];") == 1 { ok = 1 } END { exit !ok }' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: every direct layout of a copy is one this test knows (6: own pass, watcher, DMEnsureLogo, DMSMRefreshBars, front watch, DMSMChrome)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: a direct layout of a copy this test does not know (or one gone)"; n=$((n + 1)); fi
  # the logo's creation always reaches the newlyOurs block (no return between), and the logo is never taken off: ours once, ours for good
  if awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { b = 1 } b && index($0, "        objc_setAssociatedObject(fg, kLogoKey, logo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);") == 1 { f = 1 }
          f && /return/ { bad = 1 } f && index($0, "    BOOL newlyOurs = ![gCopies containsObject:fg];") == 1 { ok = 1; exit } END { exit !(ok && !bad) }' "$X" &&
     ! /usr/bin/grep -q 'kLogoKey, nil' "$X" $(ls "$(dirname "$X")"/*.h 2>/dev/null); then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the logo's creation reaches the newlyOurs block (no return between) and is never taken off"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the logo can be made without the newlyOurs block, or taken off"; n=$((n + 1)); fi
  # the full layout's marks as the model sets them after the newlyOurs block
  if awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { b = 1 } b && index($0, "    BOOL newlyOurs = ![gCopies containsObject:fg];") == 1 { k = 1 }
          k && index($0, "    BOOL locked = DMBarLockedNow();") == 1 { l = 1 }
          l && index($0, "    objc_setAssociatedObject(fg, kBarLaidOutLockedKey, @(locked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);") == 1 { m = 1 }
          m && index($0, "    objc_setAssociatedObject(fg, kBarLookLockedKey, @(locked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);") == 1 { ok = 1; exit } b && /^[}]/ { exit } END { exit !ok }' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the full layout records its lock state after the newlyOurs block (kBarLaidOutLockedKey, kBarLookLockedKey), as the model does"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the full layout's lock marks are not where the model sets them"; n=$((n + 1)); fi
  # SpringBoard's calls the model makes: the time label's arrival (15/16 SBClockBack, 17+ SBAttach17), iOS's data updates (StockVPNItem), the Cover
  # Sheet's dismissal start (CoverSheetLeaving), DMWatchLock from the 0.2 s library timer started 8 s in
  lib=$(awk 'index($0, "static void DMSyncWindowsForLibraryBody(void) {") == 1 { f = 1 } f { print } f && /^[}]/ { exit }' "$X")
  if awk '/^%group SBClockBack/ { g = 1 } g && /^%end/ { exit } g && index($0, "    DMClockBackNow(((UIView *)self).superview.superview);") { ok = 1 } END { exit !ok }' "$X" &&
     /usr/bin/grep -qF '    if (!DMSBUseSTUI() && !DMCtorSkip("clockback")) %init(SBClockBack' "$X" &&
     awk '/^%group SBAttach17$/ { g = 1 } g && /^%end/ { exit } g && index($0, "    DMAttachIfFilledNow(((UIView *)self).superview.superview, \"a label arrived\", YES);") { ok = 1 } END { exit !ok }' "$X" &&
     awk '/^%group StockVPNItem/ { g = 1 } g && /^%end/ { exit } g && index($0, "- (void)_updateWithAggregatedData:(id)data {") { a = 1 } a && index($0, "    %orig;") { b = 1 } b && index($0, "    DMStatusIconsUpdated(self);") { ok = 1; exit } END { exit !ok }' "$X" &&
     awk '/^%group CoverSheetLeaving/ { g = 1 } g && /^%end/ { exit } g && index($0, "    DMBarCoverLeaving();") { ok = 1 } END { exit !ok }' "$X" &&
     echo "$lib" | /usr/bin/grep -qF 'DM_PERF("lock", DMWatchLock());' &&
     /usr/bin/grep -qF 'NSTimer *libraryWatch = [NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { DMSyncWindowsForLibrary(); }];' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: SpringBoard's calls as the model makes them (the label's arrival 15/16 and 17+, data updates, the Cover Sheet leaving, DMWatchLock)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: a call the model makes is not wired so in StatusBar.x"; n=$((n + 1)); fi
  # the unlock reaches a copy not ours yet on every iPadOS: no OS return in DMRelayoutUnattachedBars (until 1.8.7.7: 17+ only)
  if ! fndef "$X" DMRelayoutUnattachedBars | /usr/bin/grep -q 'DMSBUseSTUI'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMRelayoutUnattachedBars lays out the copies not ours yet on 15/16 too (no OS return)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMRelayoutUnattachedBars returns on some iPadOS: the unlock leaves a copy not ours there to DMEnsureLogo"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (at most 97; 99: not built)
  local X=$1 d=$2 q=$3 f n s out bu
  mkdir -p "$d"
  for f in "${WR_NEED[@]}"; do [ -n "$(fndef "$X" "$f")" ] || { echo "FAIL  $X: no $f"; return 99; }; done
  bu="$(dirname "$X")/BarUnlock.h"; [ -f "$bu" ] || bu=../statusbar/BarUnlock.h
  cp "$bu" "$d/BarUnlock.h"
  { fndef "$X" DMCall; fndef "$X" DMSBIs; fndef "$X" DMSBIsBarWindowName; fndef "$X" DMLockUp
    /usr/bin/grep -E '^static (void|BOOL) DMStockVPNRecheck\(UIView \*fg\);' "$X"; } > "$d/wr-base.inc"
  { fndef "$X" DMHideStockWiFi; fndef "$X" DMWiFiItemCanEnable; fndef "$X" DMStockWiFiInit; } > "$d/wr-item.inc"
  # (the ask of iOS's items, 1.8.7.7: DMBarItemsAskAgain and its mark -- none in the code before it)
  { fndef "$X" DMBarCopyPooled; fndef "$X" DMHoldStatusBarCopy; fndef "$X" DMHoldSafetyCheck
    ln1 "$X" 'static const void *kItemsAskKey = &kItemsAskKey;'; fndef "$X" DMBarItemsAskAgain
    fndef "$X" DMReleaseStatusBarCopy; fndef "$X" DMStockVPNRecheck; fndef "$X" DMStatusIconsUpdated; } > "$d/wr-hold.inc"
  { fndef "$X" DMSkipLockAfterRespring; fndef "$X" DMBarCoverLeaving; fndef "$X" DMRelayoutUnattachedBars; fndef "$X" DMHideAppBarItemsNow; fndef "$X" DMWatchLock; } > "$d/wr-lock.inc"
  { fndef "$X" DMAttachIfFilledNow; fndef "$X" DMAttachIfFilled; fndef "$X" DMClockBackNow; fndef "$X" DMClosedUpClockBack; fndef "$X" DMClockBackLayout; } > "$d/wr-attach.inc"
  # (1.8.7.6: a copy's layout asked for inside its bar's own constraint pass waits for the next turn, DMBarDecideNextTurn as it is; the code before has none)
  if [ -n "$(fndef "$X" DMBarDecideNextTurn)" ]; then
    { fndef "$X" DMBarLayingOut; ln1 "$X" 'static const void *kBarDecideNextTurnKey = &kBarDecideNextTurnKey;'; fndef "$X" DMBarDecideNextTurn; } > "$d/wr-decide.inc"
    /usr/bin/grep -q 'kBarDecideNextTurnKey = ' "$d/wr-decide.inc" && /usr/bin/grep -q 'static BOOL DMBarLayingOut' "$d/wr-decide.inc" || { echo "FAIL  $X: DMBarDecideNextTurn's parts were not found"; return 99; }
  else echo 'static void DMBarDecideNextTurn(UIView *fg, NSString *what) { (void)fg; (void)what; }   /* (the code before 1.8.7.6: none) */' > "$d/wr-decide.inc"; fi
  { fndef "$X" DMFindForegroundView; fndef "$X" DMStartupLockScreenDressed
    awk 'index($0, "@interface DMStartupWatcher : NSObject") == 1 { f = 1 } f { print } index($0, "static void DMStartStartupWatcher(void) {") == 1 { s = 1 } s && /^[}]/ { exit }' "$X"
    fndef "$X" DMEnsureLogo; } > "$d/wr-watch.inc"
  # the copy's hooks: -layoutSubviews (iOS's own part, %orig, played by the model), -didMoveToWindow; -dm_layoutLogo (%new)
  body "$X" '- (void)layoutSubviews {' 'CFTimeInterval origBegan = CACurrentMediaTime();' 'TIOSPart(self);' > "$d/wr-layoutsubviews.inc"
  body "$X" '- (void)didMoveToWindow {' '[gAllBarCopies addObject:self];' '' > "$d/wr-didmove.inc"
  body "$X" '- (void)dm_layoutLogo {' '[self dm_layoutLogoBody];' '' > "$d/wr-wrapper.inc"
  # -dm_layoutLogoBody: from the leading region's lookup through the no-clock branch and the two marks the clock layout clears; the newlyOurs part
  awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { b = 1 } b && index($0, "    UIView *container = DMLeadingContainer(fg);") == 1 { f = 1 } f { print }
       f && index($0, "    objc_setAssociatedObject(fg, kBarClosedUpKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);") == 1 { exit }' "$X" > "$d/wr-noclock.inc"
  awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { b = 1 } b && index($0, "    if (!gCopies) gCopies = [NSHashTable weakObjectsHashTable];") == 1 { f = 1 }
       f && index($0, "    DMStartClockBalanceIfNeeded();") == 1 { exit } f { print }' "$X" > "$d/wr-newly.inc"
  /usr/bin/grep -qF 'objc_setAssociatedObject(fg, kNoClockLayoutKey, (laidOut && (lockedNow || keepsLockedLook))' "$d/wr-noclock.inc" &&
    [ "$(tail -n 1 "$d/wr-noclock.inc")" = '    objc_setAssociatedObject(fg, kBarClosedUpKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' ] || { echo "FAIL  $X: the no-clock layout was not found"; return 99; }
  /usr/bin/grep -qF '    BOOL newlyOurs = ![gCopies containsObject:fg];' "$d/wr-newly.inc" || { echo "FAIL  $X: the newlyOurs block was not found"; return 99; }
  /usr/bin/grep -qF 'TIOSPart(self);' "$d/wr-layoutsubviews.inc" && /usr/bin/grep -qF 'DMHoldStatusBarCopy((UIView *)self);' "$d/wr-didmove.inc" &&
    /usr/bin/grep -qF '[self dm_layoutLogoBody];' "$d/wr-wrapper.inc" || { echo "FAIL  $X: a hook's body was not found"; return 99; }
  [ -n "$q" ] || echo "   (the newlyOurs ask: $(/usr/bin/grep -E '^    if \(newlyOurs( &&|\))' "$d/wr-newly.inc" | /usr/bin/grep -v 'DMSMMainBarChanged' | sed 's/ *{.*//; s/^ *//; s/ DMBarItemsAskAgain(fg);.*//'))"
  clang -O1 -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -Werror=implicit-function-declaration -I"$d" \
        -framework Foundation -o "$d/t" test-wifirecheck.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 97; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 128 ] && { [ -n "$q" ] || echo "FAIL  ended by signal $((n - 128))"; n=1; }
  [ -n "$q" ] || echo "-- site checks"
  sites "$X" "$q"; s=$?
  n=$((n + s)); [ $n -gt 97 ] && n=97
  return $n
}

run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-wifirecheck: all pass" || echo "test-wifirecheck: FAILED ($rc check(s))"
if [ -z "$WR_SB_X" ]; then
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
  NEWLY='if \(newlyOurs && !\[objc_getAssociatedObject\(fg, kHoldKey\) boolValue\]\) DMBarItemsAskAgain\(fg\);'
  mtf "only a given-up copy asked in its layout (1.8.1.1's rule)" "s/$NEWLY/if (newlyOurs \&\& objc_getAssociatedObject(fg, kHoldGaveUpKey)) DMBarItemsAskAgain(fg);/"
  mtf "no ask in the layout at all" "s/$NEWLY//"
  mtf "every new copy asked in its layout, held ones too" "s/$NEWLY/if (newlyOurs) DMBarItemsAskAgain(fg);/"
  mtf "the hold's release no longer asks" 's/(DMSMMainBarChanged\(fg\);   \/\/ \(the screen.s own bar released[^\n]*\n(?:[^\n]*\n)*?)    DMBarItemsAskAgain\(fg\);\n/$1/'
  mtf "an ask that found no bar or data is not made again (no owed ask)" 's/\n    if \(\[objc_getAssociatedObject\(self, kItemsAskKey\) intValue\] == 2[^\n]*//'
  mtf "an ask taken as made whatever it found" 's/    if \(!data \|\| !\[bar respondsToSelector:upd\]\) return NO;\n/    if (!data || ![bar respondsToSelector:upd]) return YES;\n/'
  mtf "DMRelayoutUnattachedBars on 17+ only again" 's/(static void DMRelayoutUnattachedBars\(NSString \*why\) \{\n)/$1    if (!DMSBUseSTUI()) return;\n/'
  mtf "the time label's arrival lays out only a copy of ours (as before)" 's/    if \(!ours && \(!objc_getAssociatedObject\(fg, kBarClosedUpKey\) [^\n]*\n/    if (!ours) return;\n/'
  # (1.8.7.6, the iPad 2's f03 pass: a Notification Center pull let go)
  CLOSEDUP='    if \(ours && !\[objc_getAssociatedObject\(fg, kBarLookLockedKey\) boolValue\]\) \{[^\n]*\n[^\n]*DMClosedUpClockBack\(fg\);\n        return;\n    \}\n'
  mtf "15/16: a closed-up copy of ours left so at its time label's return (1.8.7.5's rule: the locked look only)" "s/$CLOSEDUP/    if (ours \&\& ![objc_getAssociatedObject(fg, kBarLookLockedKey) boolValue]) return;\n/"
  mtf "15/16: the closed-up copy laid out at once at its time label's return, not through DMClockBackLayout (inside its bar's constraint pass)" "s/$CLOSEDUP/    if (ours \&\& ![objc_getAssociatedObject(fg, kBarLookLockedKey) boolValue]) { [fg setNeedsLayout]; [fg layoutIfNeeded]; return; }\n/"
  mtf "the closed-up copy laid out inside its bar's own constraint pass (DMClockBackLayout's wait out: the NC-pull crash's way)" 's/    BOOL later = now && gDMBarConstraintDepth > 0;\n/    BOOL later = NO;\n/'
  mtf "the Wi-Fi item left out only of a held bar" 's/(static BOOL DMHideStockWiFi\(id item\) \{\n(?:[^\n]*\n)*?)    return objc_getAssociatedObject\(fg, kLogoKey\) \|\| /$1    return /'
  mtf "an ask whose own update made the copy ours not made again (that layout's ask dropped)" 's/\n        if \(asked && !wasOurs && objc_getAssociatedObject\(f, kLogoKey\)\) DMBarItemsAskAgain\(f\);//'
fi
exit $rc
