#!/bin/bash
# test-pastedgeparity.sh: the same title-bar drag ends in the same place on every window engine (1.8.8.3, GitHub #19; KT 23 Nov: "We should match
# the other engines in this version"): one window, 600 x 400 pt as drawn, the same touch-down on its title bar and the same finger path, on our
# Stage Manager engine (where its drop asks Stage Manager to put it, and where the layout passes keep it), Aerial 5 (its stage recogniser and 5.1's
# drag area, Aerial's own step and fit pass as test-aerialpastedge.m plays them), Aerial 3.0 (our -handlePan: hook), Zetsu (our title-bar pan) and
# MilkyWay4 (our catch-up on its own move): every engine's window as drawn within 2 pt of the others' and of the finger's travel with only the top
# held under the menu bar. See test-pastedgeparity.m. The real code is cut out of statusbar/StatusBar.x (PAR_SB_X / PAR_H: other copies, e.g. the
# code before a change) as test-smpastedge.sh and test-aerialpastedge.sh cut it, and run in their harnesses (their own checks left out); Zetsu's and
# MilkyWay4's drag code is cut out here. No case ends within 45 pt of an edge: the snap is one step on every engine (WindowSnap.h, test-windowsnap.sh).
# Every engine meets the finger as UIKit reports it: the finger goes down on the title bar, UIKit begins the pan further on (its hysteresis: each case
# at 12, 28, 52 and 59 pt, the iPads' ways up to 52 on the 17.5.1 for a quick finger) and counts its translation from there, none at its start; each
# engine's touch-down note sees where it went down (1.8.8.3: our Stage Manager engine's too: its drag went by UIKit's translation alone and ended
# 12 pt short here, 9 to 52 pt on the 17.5.1 and 16.7.7 device passes; review: Aerial 3.0's, whose start was the pan's, and every engine's limit
# at 60 pt, Aerial's and MilkyWay4's 40 leaving a quick finger's drag unfollowed). Then a site check of the four limits.
# 1.8.8.4 (engine parity, item 5): every case again with the menu bar hiding itself (auto-hide on, a pointer attached): the real DMTopLimit in every
# engine's code, our engine's real desktop (DMSMUsableAreaForIdentity) and Stage Manager's stage top (our real _statusBarHeight answer, put right by the
# real DMSMStageTopByDisplay) that its layout pass keeps a card under: the top case at the screen's top edge on all six, as on a Mac.
# Then made-to-fail copies: each breaks one engine and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${PAR_SB_X:-../statusbar/StatusBar.x}; H0=${PAR_H:-../statusbar/SMPastEdge.h}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }      # one function or method of a file, from its first line
blk() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^@end/ {exit}' "$1"; }   # an @interface, to its @end
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                        # one line of a file (a global)
# (our Stage Manager engine: as test-smpastedge.sh cuts it)
SM_IFACE='@interface DMSMTitleBar : UIView <UIGestureRecognizerDelegate>'
SM_DECL=('static const CGFloat kSMBarH = ' 'static CFTimeInterval gSMDragUntil = 0;' 'static NSMutableSet<NSString *> *gSMBehindDock;'
         'static NSMutableDictionary<NSString *, NSNumber *> *gSMDockHeightBySize;')
SM_LINES=('static NSMutableDictionary<NSString *, NSArray<NSValue *> *> *gSMPastEdge;' 'static NSMutableArray<NSString *> *gSMPastEdgeOrder;'
          'static NSString *gSMPastEdgeResizeKey; static CGRect gSMPastEdgeResizeFrom;' 'static CGRect gSMPastEdgeDesk; static CGSize gSMPastEdgeScreen;')
SM_FN=('static BOOL DMSMPastEdgeAllowedOn(CGSize scr) {' 'static void DMSMPastEdgeRemove(NSString *key) {' 'static BOOL DMSMPastEdgeHeld(CGPoint c, CGSize s, CGSize scr) {'
       'static void DMSMPastEdgeResizeBegan(unsigned dragged, CGRect start) {'
       'static BOOL DMSMPastEdgeKeepIn(CGPoint *cp, CGSize pts, CGSize scr, CGRect u) {' 'static CGRect DMSMPastEdgeDeskOn(UIScreen *s, CGSize size) {'
       'static BOOL DMSMPastEdgeHeldAt(CGPoint c, CGSize s, CGSize scr, CGPoint *keep) {' 'static void DMSMPastEdgeDragBegin(UIView *card) {'
       'static CGPoint DMSMPastEdgeDragKept(UIView *card, CGPoint t) {'
       'static void DMSMPastEdgeDropped(NSString *key, UIScreen *scn, CGRect droppedOnScreen, BOOL snapped, CGPoint at, CGPoint plain) {'
       'static CGRect DMSMCardDesk(CGRect u, CGSize scr, BOOL behindDock) {' 'static void DMSMJoinOwnPlace(NSString *key, CGSize *pts, CGPoint *cp, CGSize scr, CGRect u) {'
       'static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle) {'
       'static NSArray<NSArray *> *DMSMPastEdgeBefore16(id m, CGRect area) {' 'static void DMSMPastEdgeAfter16(id m, NSArray<NSArray *> *held) {')
SM_PAN='- (void)dm_pan:(UIPanGestureRecognizer *)g {'
SM_TOUCH='- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {'   # (the bar's touch filter: where the finger went down, 1.8.8.3)
# (Aerial: as test-aerialpastedge.sh cuts it)
A_CHAIN=('static void DMAerial5SyncState(UIView *stage, CGRect frame) {' 'static void DMKeepStagePlace(UIView *stage, CGRect frame) {'
         'static void DMSetStageIntent(UIView *stage, CGRect frame) {' 'static void DMRememberStageFrame(UIView *stage) {' 'static CGRect DMA5WindowFromStage(CGRect f) {')
A_PAN='- (void)handlePan:(id)gesture {'
A_LIVE=('static BOOL DMAerial5GestureLive(UIView *stage) {' 'static BOOL DMAerial5HandGestureLive(UIView *stage) {')   # (its harness includes them: 1.8.8.4 review)
a30cut() { awk 'index($0, "// A drag by hand. NO: the drag was cancelled here") == 1 {f=1} f {print} f && index($0, "static void DMAerialGestureAfter(") == 1 {g=1} g && /^[}]/ {exit}' "$1"; }
a5cut() { awk 'index($0, "// ---- Aerial 5.0: a window moves by its title strip only") == 1 {f=1} f {print} f && index($0, "@implementation DMA5DragGuard") == 1 {g=1} g && /^@end/ {exit}' "$1"; }
# (Zetsu: our title-bar pan and where it reads the finger; MilkyWay4: our catch-up's touch-down note and its title-bar target)
Z_LINES=('static const void *kZetsuTouchDownKey = &kZetsuTouchDownKey;' 'static const void *kZetsuTouchNowKey = &kZetsuTouchNowKey;')
Z_FN=('static void DMZetsuNoteTouchDown(UIWindow *w, NSSet<UITouch *> *touches) {' 'static CGPoint DMZetsuPanPointOnScreen(UIPanGestureRecognizer *g, UIWindow *w) {'
      'static CGPoint DMPanDownPointOnScreen(UIPanGestureRecognizer *g, UIWindow *w, CGRect *frame) {')
Z_IFACE='@interface DMZetsuBarPan : NSObject'
MW_LINE='static char kMWDownKey, kMWWatchedKey, kMWOffsetKey;'
# (the top: DMTopLimit; ours: its desktop, the _statusBarHeight answer's globals and the hook, DMSMStageTopByDisplay)
TOP_FN='static CGFloat DMTopLimit(void) {'; DESK_FN='static CGRect DMSMUsableAreaForIdentity(id identity, CGSize *screenOut) {'
PASS_FN='static CGRect DMSMStageTopByDisplay(CGRect r, CGRect b) {'; ANS_LINE='static CGFloat gSMStatusBarOrigH = -1'; LOW_LINE='static BOOL gSMStatusBarLowered'
HOOK_FN='- (CGFloat)_statusBarHeight {'
MW_DRAG='- (void)dragged:(UIPanGestureRecognizer *)g {'
mwtouch() { awk 'index($0, "@implementation DMMWResizeCatchUp") == 1 {f=1} f && index($0, "- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {") == 1 {g=1} g {print} g && /^[}]/ {exit}' "$1"; }

build() {   # $1 engine number, $2 work dir, $3 output binary, $4 the menu bar hiding itself (0 / 1): built from test-pastedgeparity.m
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -DPAR_ENGINE="$1" -DPAR_AUTOHIDE="${4:-0}" -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-const-variable -Werror=implicit-function-declaration -I"$2" -I. -I../statusbar \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$3" test-pastedgeparity.m 2>>"$2/cc.txt"
}
run() {   # $1 StatusBar.x, $2 SMPastEdge.h, $3 work dir, $4 quiet, $5 the menu bar hiding itself (0 / 1): the number of failed checks (99: not built)
  local X=$1 H=$2 d=$3 q=$4 ah=${5:-0} h n=0
  mkdir -p "$d"; : > "$d/cc.txt"
  cp "$H" "$d/SMPastEdge.h" || { echo "FAIL  no $H"; return 99; }
  [ -n "$(blk "$X" "$SM_IFACE")" ] && [ "$(grep -cF -e "$SM_PAN" "$X")" = 1 ] && [ "$(grep -cF -e "$SM_TOUCH" "$X")" = 1 ] || { echo "FAIL  $X: no title bar drag of the Stage Manager engine"; return 99; }
  for h in "${SM_DECL[@]}" "${SM_LINES[@]}" "${Z_LINES[@]}" "$MW_LINE"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${SM_FN[@]}" "${A_CHAIN[@]}" "${A_LIVE[@]}" "${Z_FN[@]}" "$MW_DRAG"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  [ "$(grep -cF -e "$A_PAN" "$X")" = 1 ] && [ -n "$(a30cut "$X")" ] && a5cut "$X" | grep -q '^@implementation DMA5DragGuard' || { echo "FAIL  $X: no Aerial drag code"; return 99; }
  awk -v h="$Z_IFACE" 'index($0, h) == 1 {f=1} f {print} f && /^@end/ {n++} n == 2 {exit}' "$X" | grep -q '^@implementation DMZetsuBarPan' || { echo "FAIL  $X: no Zetsu title-bar pan"; return 99; }
  [ -n "$(mwtouch "$X")" ] || { echo "FAIL  $X: no MilkyWay4 touch-down note"; return 99; }
  # (the Stage Manager engine, UIKit's main screen asked as the harness's TMainScreen())
  { for h in "${SM_DECL[@]}"; do line "$X" "$h"; done; blk "$X" "$SM_IFACE"; } > "$d/spe-decl.inc"
  { for h in "${SM_LINES[@]}"; do line "$X" "$h"; done; for h in "${SM_FN[@]}"; do fn "$X" "$h"; done; } | sed 's/\[UIScreen mainScreen\]/TMainScreen()/g' > "$d/spe-glue.inc"
  { fn "$X" "$SM_TOUCH"; fn "$X" "$SM_PAN"; } | sed 's/\[UIScreen mainScreen\]/TMainScreen()/g' > "$d/spe-pan.inc"
  # (Aerial, UIKit's main screen as the harness's screen)
  for h in "${A_CHAIN[@]}"; do fn "$X" "$h"; done | sed 's/\[UIScreen mainScreen\]\.bounds/KScreenBounds()/g' > "$d/ape-chain.inc"
  a30cut "$X" | sed 's/\[UIScreen mainScreen\]\.bounds/KScreenBounds()/g' > "$d/ape-30.inc"
  a5cut "$X" | sed 's/\[UIScreen mainScreen\]\.bounds/KScreenBounds()/g' > "$d/ape-drag.inc"
  for h in "${A_LIVE[@]}"; do fn "$X" "$h"; done > "$d/ape-live.inc"
  awk -v h="$A_PAN" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$X" | sed 's/^\( *\)%orig;/\1[self k_origPan:gesture];/' > "$d/ape-hook.inc"
  grep -q '%orig' "$d/ape-hook.inc" && { echo "FAIL  $X: a %orig left in the hook cut out"; return 99; }
  # (Zetsu and MilkyWay4)
  { for h in "${Z_LINES[@]}"; do line "$X" "$h"; done; for h in "${Z_FN[@]}"; do fn "$X" "$h"; done
    awk -v h="$Z_IFACE" 'index($0, h) == 1 {f=1} f {print} f && /^@end/ {n++} n == 2 {exit}' "$X"; } > "$d/par-zetsu.inc"
  { line "$X" "$MW_LINE"; echo '@implementation TMWCatchUp'; mwtouch "$X"; fn "$X" "$MW_DRAG"; echo '@end'; } > "$d/par-mw.inc"
  # (every engine's top: StatusBar.x's DMTopLimit with the bar hiding itself or not; ours also its desktop and Stage Manager's stage top)
  [ -n "$(line "$X" "$TOP_FN")" ] && [ -n "$(fn "$X" "$DESK_FN")" ] && [ -n "$(fn "$X" "$PASS_FN")" ] && [ -n "$(line "$X" "$ANS_LINE")" ] \
    && [ -n "$(awk -v h="$HOOK_FN" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$X")" ] || { echo "FAIL  $X: no top code to cut out"; return 99; }
  { echo '#include "../common/MenuBarHeight.h"'; echo '#include "../common/BarAutoHide.h"'
    echo "static BOOL DMAutoHideLayout(void) { return $ah; }   // (the menu bar hiding itself: auto-hide on, a pointer attached)"
    echo 'static CGFloat DMMenuBarHeight(void) { return 24.0; }'; line "$X" "$TOP_FN"; } > "$d/par-top.inc"
  { echo '#include "par-top.inc"'
    echo 'static CGRect DMUsableArea(void) { CGSize s = gIPad.size; CGFloat top = DMTopLimit(); return CGRectMake(0, top, s.width, MAX(200.0, s.height - gTIPadDock - 2.0 - top)); }'
    echo 'static CGFloat DMTVBarHeight(void) { return 24.0; }'; echo 'static int gDMBarSize = 0; static int DMTVBarSizeNow(void) { return 0; }'
    echo 'static BOOL DMDockAutoHidesOn(UIScreen *s) { (void)s; return NO; }'
    echo 'static double MSBDAutoHideRoomEdge(int autoHide, double dockEdge, double screenEdge) { return autoHide ? screenEdge : dockEdge; }'
    echo 'static NSArray<UIScreen *> *TScreens(void) { return @[gIPad, gTV]; }'
    fn "$X" "$DESK_FN"; line "$X" "$ANS_LINE"; [ -n "$(line "$X" "$LOW_LINE")" ] && line "$X" "$LOW_LINE"; fn "$X" "$PASS_FN"
    echo 'static CGFloat gTIOSStatusBarH = 24.0;   // (iOS'"'"'s own status bar height on a Face ID iPad)'
    awk -v h="$HOOK_FN" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$X" | sed 's/^- (CGFloat)_statusBarHeight {$/static CGFloat TSMStatusBarHeight(void) {/; s/%orig/gTIOSStatusBarH/'
  } | sed 's/\[UIScreen mainScreen\]/TMainScreen()/g; s/\[UIScreen screens\]/TScreens()/g' > "$d/spe-desk.inc"
  for h in 1 2 3; do build $h "$d" "$d/t$h" $ah || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build (engine part $h)"; return 99; }; done
  [ -n "$q" ] || grep -E 'warning:|error:' "$d/cc.txt"
  { "$d/t1"; "$d/t2"; "$d/t3"; } > "$d/frames.txt" 2>&1
  python3 -I - "$d/frames.txt" "$q" <<'PY'
import sys
lines = open(sys.argv[1]).read().split('\n'); quiet = sys.argv[2] != ''
engines = ['sm', 'aerial5', 'aerial51', 'aerial30', 'zetsu', 'milkyway4']
names = {'sm': 'our Stage Manager engine', 'aerial5': "Aerial 5 (its stage recogniser)", 'aerial51': "Aerial 5.1 (its drag area)",
         'aerial30': 'Aerial 3.0 (our hook)', 'zetsu': 'Zetsu', 'milkyway4': 'MilkyWay4'}
frames, kept, want, what, order = {}, {}, {}, {}, []
for l in lines:
    p = l.split()
    if not p: continue
    if p[0] == 'CASE': want[p[1]] = tuple(map(float, p[2:6])); what[p[1]] = ' '.join(p[6:]); order.append(p[1])
    elif p[0] == 'FRAME': frames[(p[1], p[2])] = tuple(map(float, p[3:7]))
    elif p[0] == 'KEPT': kept[(p[1], p[2])] = p[3] == '1'
    elif not quiet: print(l)
fails = 0
def out(ok, s):
    global fails
    if not ok: fails += 1
    if not quiet: print(('PASS  ' if ok else 'FAIL  ') + s)
if len(set(order)) < 28: out(False, 'the cases were not all played (%d)' % len(set(order)))
for c in dict.fromkeys(order):
    w = want[c]; got = {e: frames.get((e, c)) for e in engines}
    missing = [e for e in engines if got[e] is None]
    off = [e for e in engines if got[e] is not None and max(abs(a - b) for a, b in zip(got[e], w)) > 2.0]
    notkept = [e for e in engines if kept.get((e, c)) is False]
    r = lambda f: '{{%g, %g}, {%g, %g}}' % f
    if missing or off or notkept:
        out(False, '%s (%s): not the same on every engine: expected %s; %s' % (c, what[c], r(w),
            '; '.join(['%s %s' % (names[e], r(got[e]) if got[e] else 'no frame') + (' (its place not kept)' if e in notkept else '') for e in engines if e in missing + off + notkept])))
    else:
        spread = max(max(abs(got[a][i] - got[b][i]) for i in range(4)) for a in engines for b in engines)
        out(True, '%s (%s): the same window on all six (%s), %s, within %.2f pt of each other, its place kept' % (c, what[c], ', '.join(names[e] for e in engines), r(w), spread))
sys.exit(min(fails, 98))
PY
  return $?
}

[ -f "$H0" ] || { echo "FAIL  no statusbar/SMPastEdge.h: our Stage Manager engine keeps no window past an edge"; exit 1; }
run "$X0" "$H0" "$W/real"; rc=$?
# (1.8.8.3 review) one limit for every engine: a touch-down 60 pt or more from where UIKit began the pan is not this drag's (ours, Zetsu's, Aerial's,
# MilkyWay4's title bar)
if grep -qF '&& hypot(before.x, before.y) < 60.0) { _follows = YES;' "$X0" && grep -qF 'if (hypot(now.x - down.x, now.y - down.y) >= 60.0 || ' "$X0" \
   && grep -qF 'if (began && !(hypot(dx, dy) < 60.0)) { objc_setAssociatedObject(g, &kA5DragDownKey, nil,' "$X0" \
   && [ "$(fn "$X0" "$MW_DRAG" | grep -cF '(hypot(d.x, d.y) >= 0.5 && hypot(d.x, d.y) < 60.0) ?')" = 1 ]; then
  echo "PASS  site: every engine's title-bar drag follows a touch-down up to 60 pt from where UIKit began the pan (ours, Zetsu, Aerial, MilkyWay4)"
else echo "FAIL  site: the engines' title-bar drags do not share the 60 pt limit"; rc=1; fi
echo "-- the same with the menu bar hiding itself (1.8.8.4)"
run "$X0" "$H0" "$W/real-ah" "" 1; r=$?; [ $r = 0 ] || rc=$r
if [ -z "$PAR_SB_X$PAR_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 which file (X StatusBar.x, H SMPastEdge.h), $3 perl expression on it (-0777: the whole file)
    local d="$W/m$((++k))" x=$X0 h=$H0 f out r
    mkdir -p "$d"
    case $2 in X) f=$X0; out="$d/StatusBar.x"; x=$out;; H) f=$H0; out="$d/SMPastEdge.h.src"; h=$out;; esac
    perl -0777 -pe "$3" "$f" > "$out"
    cmp -s "$out" "$f" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$x" "$h" "$d/w" q; r=$?
    if [ $r -gt 0 ] && [ $r -lt 99 ]; then echo "PASS  caught: $1 ($r case(s) differ)"; else echo "FAIL  not caught: $1 ($r)"; rc=1; fi
  }
  k=0
  mtf "Aerial 5's sides held at the screen's edges (1.7.5)" X 's/want = CGPointMake\(c0\.x \+ dx, /want = CGPointMake(MAX(stage.frame.size.width \/ 2.0 - 6.0, MIN(c0.x + dx, stage.superview.bounds.size.width - stage.frame.size.width \/ 2.0 + 6.0)), /'
  mtf "Aerial's y left to its own step after the start (1.7.5)" X 's/MAX\(c0\.y \+ dy, DMAerialDragTop\(\) \+ stage\.frame\.size\.height \/ 2\.0\)\);/(began ? c0.y + dy : c.y));/'
  mtf "our Stage Manager engine with F47's grab area (112 pt of the window kept on the screen at the sides)" H 's/return CGRectMake\(w.origin.x, fmax\(w.origin.y, CGRectGetMinY\(desk\)\), w.size.width, w.size.height\);/return CGRectMake(fmax(fmin(w.origin.x, CGRectGetMaxX(desk) - 112.0), CGRectGetMinX(desk) + 112.0 - w.size.width), fmax(w.origin.y, CGRectGetMinY(desk)), w.size.width, w.size.height);/'
  mtf "our Stage Manager engine's drop not recorded (its window back inside after Stage Manager's passes)" X 's/^        DMSMPastEdgeDropped\(w, scn, droppedOnScreen, snapped, at, [^\n]*\n//m'
  mtf "our Stage Manager engine's drag by UIKit's translation alone (from where its pan began, 12 pt on)" X 's/^    BOOL followed = _follows;$/    BOOL followed = NO;/m'
  mtf "Zetsu's top not held under the menu bar" X 's/    f\.origin\.y = MAX\(DMTopLimit\(\), f\.origin\.y\);   \/\/ the title bar never goes above/    \/\/ the title bar never goes above/'
  mtf "MilkyWay4's catch-up left out (its window as far behind the finger as its recogniser's start)" X 's/f\.origin\.x \+= d\.x; f\.origin\.y \+= d\.y;/(void)d;/'
  mtf "Aerial's limit at 40 pt (a quick finger's drag kept inside by Aerial's own step)" X 's/if \(began && !\(hypot\(dx, dy\) < 60\.0\)\)/if (began \&\& !(hypot(dx, dy) < 40))/'
  mtf "MilkyWay4's limit at 40 pt (a quick finger's drag as far behind as its recogniser's start)" X 's/\(hypot\(d\.x, d\.y\) >= 0\.5 && hypot\(d\.x, d\.y\) < 60\.0\) \? \[NSValue valueWithCGPoint:d\] : \[NSValue valueWithCGPoint:CGPointZero\]/(hypot(d.x, d.y) >= 0.5 \&\& hypot(d.x, d.y) <= 40) ? [NSValue valueWithCGPoint:d] : [NSValue valueWithCGPoint:CGPointZero]/'
  mtf "Aerial 3.0's touch-down not noted (its drag from where UIKit began the pan)" X 's/    if \(gAerialFlavor != 3 \|\| !stage\.superview \|\| !touch\) return;/    return;/'
  # (1.8.8.4: with the menu bar hiding itself)
  mtfah() {   # as mtf, the run with the menu bar hiding itself
    local d="$W/m$((++k))" out
    mkdir -p "$d"; out="$d/StatusBar.x"
    perl -0777 -pe "$2" "$X0" > "$out"
    cmp -s "$out" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$out" "$H0" "$d/w" q 1; r=$?
    if [ $r -gt 0 ] && [ $r -lt 99 ]; then echo "PASS  caught with the bar hiding itself: $1 ($r case(s) differ)"; else echo "FAIL  not caught with the bar hiding itself: $1 ($r)"; rc=1; fi
  }
  mtfah "our stage top keeping the bar's room while it hides itself (1.8.8.3's answer, the iPad's pass as it carries it)" 's/MSBDBarAHSMStageTop\(h, DMMenuBarHeight\(\), title, hides\)/MSBDBarAHSMStageTop(h, DMMenuBarHeight(), title, 0)/; s/    BOOL tv = s != \[UIScreen mainScreen\];\n/    BOOL tv = s != [UIScreen mainScreen];\n    if (!tv) return r;\n/'
  mtfah "our desktop raised to the bar while it hides itself (1.8.8.3's)" 's/    CGFloat top = DMTopLimit\(\);\n    if \(CGRectGetMinY\(u\) < top\)/    CGFloat top = DMMenuBarHeight();\n    if (CGRectGetMinY(u) < top)/'
  mtfah "Zetsu's title bar held under the bar while it hides itself" 's/    f\.origin\.y = MAX\(DMTopLimit\(\), f\.origin\.y\);   \/\/ the title bar never goes above/    f.origin.y = MAX(24.0, f.origin.y);   \/\/ the title bar never goes above/'
fi
exit $rc
