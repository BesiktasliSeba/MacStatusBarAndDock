#!/bin/bash
# test-lockbarhide.sh: the Lock Screen's status bar (1.8.9: B113, Hide Status Bar on Lock Screen on iPadOS 18; F49 rev 2's one-status-drawing rule):
# common/LockBarHide.h and LockStatusBar.x's functions as built, run with stand-ins (test-lockbarhide.m), then the wiring of the hooks, then
# made-to-fail copies (the published way -- only the Cover Sheet's copy turned off --, no re-ask, the level, the dismissal, the pair on the
# preference, 15.6.1's ivar): each must fail.
# MSBD_TEST_LSB / LBH_H: other copies of the sources.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X=${MSBD_TEST_LSB:-../macsettings/LockStatusBar.x}
H=${LBH_H:-../common/LockBarHide.h}
fn() { awk -v s="$2" 'index($0, s) == 1 && !f {f=1; print; if ($0 !~ /\{ *(\/\/.*)?$/) exit; next} f {print} f && /^}/ {exit}' "$1"; }
build() {   # $1 LockStatusBar.x, $2 header, $3 out dir
  mkdir -p "$3"
  {
    echo 'static void LSBTruth(UIViewController *cs, const char *when);'
    fn "$1" 'static BOOL LSBCoverShown(UIViewController *cs) {'
    fn "$1" 'static void LSBSetFlag(UIViewController *cs, BOOL hid) {'
    fn "$1" 'static void LSBRealBar(UIViewController *cs, BOOL switchOn, const char *when) {'
    fn "$1" 'static void LSBTruth(UIViewController *cs, const char *when) {'
    fn "$1" 'static void LSBStatusUpdated(UIViewController *cs, const char *when) {'
  } > "$3/lockbar-gen.h"
  cp "$2" "$3/LockBarHide.h"
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$3" -DLBH_HEADER="\"$3/LockBarHide.h\"" -framework Foundation -framework CoreGraphics -o "$3/t" test-lockbarhide.m 2> "$3/cc" || { cat "$3/cc"; return 99; }
  [ -s "$3/cc" ] && { echo "FAIL  warnings:"; cat "$3/cc"; return 98; }
  return 0
}
rc=0
build "$X" "$H" "$W/real" || { echo "FAIL  the sources as built did not build"; exit 1; }
"$W/real/t" || rc=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; rc=1; fi; }
grp() { awk '/^%group LSBReal$/{f=1} f{print} f&&/^%end$/{n++} n==2{exit}' "$X"; }
check "the hooks: our reason follows the appearance, every status update after iPadOS's own, the dismissal's start, the Cover Sheet gone and iPadOS's own invalidation (before it)" \
  "grp | awk '/- \(void\)viewWillAppear/{a=1} a&&/LSBRealBar\(\(UIViewController \*\)self, gLSBSwitchCache, \"appearing\"\)/{b=1} /- \(void\)_updateStatusBar/{c=1} c&&/%orig;/{d=1} d&&/LSBStatusUpdated\(\(UIViewController \*\)self, \"a status update\"\)/{e=1} /- \(void\)viewWillDisappear/{g=1} g&&/gLSBDismissing = YES;/{h=1} h&&/\"the dismissal starts\"/{i=1} /- \(void\)viewDidDisappear/{j=1} j&&/LBHSet\(self, NO\)/{k=1} /- \(void\)_invalidateStatusBarAssertions/{l=1} l&&/LBHSet\(self, NO\)/{m=1} m&&/%orig;/{o=1} END{exit !(b&&e&&i&&k&&o)}'"
check "every status request of the Cover Sheet's is followed: -_updateStatusBar and the alpha request SpringBoard's controller gets" \
  "grp | awk '/- \(void\)_updateStatusBar/{a=1} a&&/LSBStatusUpdated\(\(UIViewController \*\)self, \"a status update\"\);/{b=1} END{exit !b}' && awk '/^%group LSBRealAlpha/{f=1} f&&/LSBStatusUpdated\(cs, \"the Cover Sheet.s alpha request\"\);/{b=1} END{exit !b}' $X && fn $X '%ctor {' | grep -qF '%init(LSBRealAlpha);'"
check "the hooks go in where the Cover Sheet has both calls (15.6.1-18.5), the switch's note too" \
  "fn $X '%ctor {' | grep -qF '[c instancesRespondToSelector:NSSelectorFromString(@\"_updateStatusBar\")] && [c instancesRespondToSelector:NSSelectorFromString(@\"_invalidateStatusBarAssertions\")]' && fn $X '%ctor {' | grep -qF '%init(LSBReal);' && fn $X '%ctor {' | grep -qF 'notify_register_dispatch(LSB_NOTIFY'"
check "15/16: the Cover Sheet's own -_setFakeStatusBarEnabled: is hooked when it overrides UIViewController's (16.7.7's never calls it)" \
  "fn $X '%ctor {' | grep -qF 'BOOL coverHook = !coverDone ? (c && own) : (generic && c && own && base && method_getImplementation(own) != method_getImplementation(base));' && fn $X '%ctor {' | grep -qF 'if (coverHook && !gLSBCoverOwn) { gLSBCoverOwn = YES; coverDone = YES; %init(LSBCover); }'"
check "the Cover Sheet's alpha request is hooked as iPadOS has it (the alpha an NSNumber: v40@0:8@16q24@32 on 15.6.1-18.5; a 1.8.9 test build's crash), each B113 group behind its type check (test-hooktypes.sh)" \
  "awk '/^%group LSBRealAlpha/{f=1} f&&/^- \\(void\\)setStatusBarAlpha:\\(id\\)alpha style:\\(long long\\)style legibilitySettings:\\(id\\)ls \\{/{b=1} END{exit !b}' $X && ! grep -q 'setStatusBarAlpha:(double)' $X && fn $X '%ctor {' | grep -qF '&& LSB_TYPES_OK(LSBReal)) {' && fn $X '%ctor {' | grep -qF '&& LSB_TYPES_OK(LSBRealAlpha)) %init(LSBRealAlpha);'"
check "a crash in a B113 hook (installed whatever the switch says) turns the part off at once, the rest the switch (crash map)" \
  "grep -qx 'image MacLockStatusBar hideLockStatusBar map' crashmap-rules.txt && grep -qxF 'sym MacLockStatusBar \\\$LSBReal(Alpha)?\\\$ part' crashmap-rules.txt && grep -q '^%group LSBReal\$' $X && grep -q '^%group LSBRealAlpha\$' $X"
check "the switch's row posts its note" \
  "python3 -I -c \"import plistlib,sys; d=plistlib.load(open('../statusbar/macstatusbarprefs/Resources/Root.plist','rb')); r=[i for i in d['items'] if i.get('key')=='hideStatusBar']; sys.exit(0 if r and r[0].get('PostNotification')=='com.besiktasliseba.maclockstatusbar/prefsChanged' else 1)\""
check "the log claims \"hidden\" only from what is read (LSBTruth), never from the switch" \
  "[ \$(grep -c 'status bar is hidden' $X) = 1 ] && fn $X 'static void LSBTruth(UIViewController *cs, const char *when) {' | grep -qF 'status bar is hidden: nothing drawn'"
echo "== made-to-fail copies"
mut() {   # $1 name, $2 file kind (x|h), $3 old, $4 new
  rm -rf "$W/m"; mkdir -p "$W/m"
  local src="$X"; [ "$2" = h ] && src="$H"
  python3 -I -c "import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[2])>=1, 'gone'; open(sys.argv[3],'w').write(s.replace(sys.argv[2], sys.argv[4], 1))" "$src" "$3" "$W/m/src" "$4" || { echo "FAIL  made to fail ($1): the line to change is gone"; rc=1; return; }
  if [ "$2" = h ]; then build "$X" "$W/m/src" "$W/m/b" >/dev/null || { echo "FAIL  made to fail ($1): did not build"; rc=1; return; }
  else build "$W/m/src" "$H" "$W/m/b" >/dev/null || { echo "FAIL  made to fail ($1): did not build"; rc=1; return; }; fi
  if "$W/m/b/t" > "$W/m/out" 2>&1; then echo "FAIL  made to fail ($1): the test still passes"; rc=1; else echo "PASS  made to fail ($1): caught ($(grep -c '^FAIL' "$W/m/out") checks)"; fi
}
mut "the published way: only the Cover Sheet's copy (B113)" x 'int r = LBHSet(cs, YES);' 'int r = 0;'
mut "no second ask after the Cover Sheet's own" x 'gLSBHeals < 2' 'gLSBHeals < 0'
mut "the re-ask budget per appearance (review finding 2)" x '    gLSBHeals = 0;
    LSBRealBar(cs, gLSBSwitchCache, when);' '    LSBRealBar(cs, gLSBSwitchCache, when);'
mut "no read after a request with our reason already in (review finding 2)" x '    if (LBHReasonIn()) LSBTruth(cs, when);' ''
mut "Q27 hides while Hide Status Bar on Lock Screen does it" h 'if (!partOn || hidByLSB || !pageWantsBar || today) return NO;' 'if (!partOn || !pageWantsBar || today) return NO;'
mut "Q27 keeps it hidden on Today (review finding 5)" h 'if (!partOn || hidByLSB || !pageWantsBar || today) return NO;' 'if (!partOn || hidByLSB) return NO;'
mut "a bar below the Cover Sheet counted" h 'f.windowLevel >= f.coverLevel && ' ''
mut "kept through the dismissal" h 'BOOL want = switchOn && !otherDoesIt && coverShown && !dismissing;' 'BOOL want = switchOn && !otherDoesIt && coverShown;'
mut "the pair on the preference alone (the 18.5 photo)" h 'return f.partOn && !f.barDrawn && (f.hidByLSB || f.hidByUs) && f.pageWantsBar && !f.today;' 'return f.partOn && f.hidByLSB;'
mut "15.6.1's context ivar not read" h 'LBHObjCall(cs, @"coverSheetContext") ?: LBHIvarObj(cs, "_coverSheetContext")' 'LBHObjCall(cs, @"coverSheetContext")'
mut "window coordinates taken for the screen's" h 'CGRect r = [v convertRect:v.bounds toCoordinateSpace:screen.coordinateSpace];' 'CGRect r = [v convertRect:v.bounds toCoordinateSpace:nil]; r = [v.window convertRect:r toCoordinateSpace:nil];'
[ $rc = 0 ] && echo "test-lockbarhide: all pass" || echo "test-lockbarhide: FAILED"
exit $rc
