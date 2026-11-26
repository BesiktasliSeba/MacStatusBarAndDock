#!/bin/bash
# test-autohidetop.sh: one window top for every engine while the menu bar hides itself (1.8.8.4, engine parity): the retop of the same windows through
# the other engines' real DMAutoHideRetopAll and our real DMAutoHideSMRetop (the same frames), our title bars sliding down with the bar by the other
# engines' rule and a drag on a slid one through the real -[DMSMTitleBar dm_pan:], and Stage Manager's stage top for the iPad and a TV (our
# _statusBarHeight answer, DMSMStageTopByDisplay, the desktop, the size grid's top), and the tick after the setting goes off (DMAutoHideStopTimerLater:
# on while our windows wait, stopped at once when the setting is on again). See test-autohidetop.m. The real code is cut out of
# statusbar/StatusBar.x (AHT_SB_X: another copy, e.g. the code before the change) into test-smpastedge.m's harness, built as a release and a DEBUG
# build (they must answer the same); then made-to-fail copies, each breaking one part, must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${AHT_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }      # one function or method of a file, from its first line
blk() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^@end/ {exit}' "$1"; }   # an @interface, to its @end
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                        # one line of a file (a global)
# (test-smpastedge.m's harness: as test-smpastedge.sh cuts it)
SM_IFACE='@interface DMSMTitleBar : UIView <UIGestureRecognizerDelegate>'
SM_DECL=('static const CGFloat kSMBarH = ' 'static CFTimeInterval gSMDragUntil = 0;' 'static NSMutableSet<NSString *> *gSMBehindDock;'
         'static NSMutableDictionary<NSString *, NSNumber *> *gSMDockHeightBySize;')
SM_LINES=('static NSMutableDictionary<NSString *, NSArray<NSValue *> *> *gSMPastEdge;' 'static NSMutableArray<NSString *> *gSMPastEdgeOrder;'
          'static NSString *gSMPastEdgeResizeKey; static CGRect gSMPastEdgeResizeFrom;' 'static CGRect gSMPastEdgeDesk; static CGSize gSMPastEdgeScreen;'
          'static NSMutableDictionary<NSString *, NSValue *> *gSMGridFirstBySize;'   # (1.8.9: the size grid's first sizes, test-smpastedge.sh's list)
          'static id gSMDragItem16;' 'static NSString *gSMAppleDragKey;' 'static CFTimeInterval gSMAppleDragToldAt;')   # (1.8.9, B114: Stage Manager's own drag)
SM_FN=('static CGSize DMSMPastEdgeGridFirst(CGSize scr) {' 'static CGSize DMSMPastEdgeLaid(CGSize s, CGSize scr) {' 'static void DMSMPastEdgeGridNote(CGSize container, int axis, id list) {'
       'static BOOL DMSMPastEdgeAllowedOn(CGSize scr) {' 'static void DMSMPastEdgeRemove(NSString *key) {' 'static BOOL DMSMPastEdgeHeld(CGPoint c, CGSize s, CGSize scr) {'
       'static void DMSMPastEdgeResizeBegan(unsigned dragged, CGRect start) {'
       'static BOOL DMSMPastEdgeKeepIn(CGPoint *cp, CGSize pts, CGSize scr, CGRect u) {' 'static CGRect DMSMPastEdgeDeskOn(UIScreen *s, CGSize size) {'
       'static BOOL DMSMPastEdgeHeldAt(CGPoint c, CGSize s, CGSize scr, CGPoint *keep) {' 'static void DMSMPastEdgeDragBegin(UIView *card) {'
       'static CGPoint DMSMPastEdgeDragKept(UIView *card, CGPoint t) {'
       'static void DMSMPastEdgeSet(NSString *key, CGPoint centre, CGSize size, CGSize S, BOOL prune) {'
       'static void DMSMPastEdgeDropped(NSString *key, UIScreen *scn, CGRect droppedOnScreen, BOOL snapped, CGPoint at, CGPoint plain) {'
       'static BOOL DMSMWindowDragLive(void) {' 'static BOOL DMSMAppleDragNote(NSString *key, CGPoint *c, CGSize s, CGSize scr) {'
       'static BOOL DMSMAppleDragPass17(id item, CGPoint *p, CGSize z, CGSize container) {'
       'static CGRect DMSMCardDesk(CGRect u, CGSize scr, BOOL behindDock) {' 'static void DMSMJoinOwnPlace(NSString *key, CGSize *pts, CGPoint *cp, CGSize scr, CGRect u) {'
       'static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle) {'
       'static NSArray<NSArray *> *DMSMPastEdgeBefore16(id m, CGRect area) {' 'static void DMSMPastEdgeAfter16(id m, NSArray<NSArray *> *held) {')
SM_PAN='- (void)dm_pan:(UIPanGestureRecognizer *)g {'
SM_TOUCH='- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {'   # (the bar's touch filter: where the finger went down, 1.8.8.3)
# (the top: DMTopLimit; ours: its desktop, the size grid's top, the _statusBarHeight answer's globals and the hook, DMSMStageTopByDisplay)
TOP_FN='static CGFloat DMTopLimit(void) {'; DESK_FN='static CGRect DMSMUsableAreaForIdentity(id identity, CGSize *screenOut) {'; BAR_FN='static CGFloat DMSMTopBarOf(CGSize size) {'
PASS_FN='static CGRect DMSMStageTopByDisplay(CGRect r, CGRect b) {'; ANS_LINE='static CGFloat gSMStatusBarOrigH = -1'; LOW_LINE='static BOOL gSMStatusBarLowered'
HOOK_FN='- (CGFloat)_statusBarHeight {'
# (the retop: the other engines' and ours; our title bars' slide and the drag's bake)
RT_LINES=('static const void *kSBRetopKey = &kSBRetopKey, *kSBWasTopKey = &kSBWasTopKey;' 'static NSMutableDictionary<NSString *, NSNumber *> *gSMRetopTries;'
          'static int gSMRetopPending = -1;' 'static CFTimeInterval gSMRetopAt = 0;' 'static NSTimer *gAutoHideTimer = nil;')
RT_FN=('static void DMSMPastEdgeMoved(CGRect was, CGRect now, CGSize scr) {' 'static id DMSMAttrsForFrameIn(id attrs, CGRect w, id stage) {'
       'static void DMAutoHideRetopAll(BOOL layout, BOOL tiled, BOOL modeChanged) {' 'static CGRect DMAutoHideSMWindowFrame(id attrs, NSString *key, CGSize scr, BOOL onScreen) {'
       'static BOOL DMAutoHideSMAnyAtLine(NSDictionary *m) {'
       'static void DMAutoHideSMRetop(BOOL layout, BOOL active, BOOL modeChanged) {' 'static void DMAutoHideStopTimerLater(NSTimer *t, int waited) {')
SL_LINES=('static CGFloat gSMSlideBarH = 0;' 'static BOOL DMAutoHideSMBarDragged(UIView *bar);')
CB_FN='static UIView *DMAutoHideSMCardOf(UIView *bar) {'   # (a title bar's card: its layout's, the bar anywhere under it -- cut when there: the code before has none)
SL_FN=('static CGFloat DMAutoHideSMSlideFor(UIView *card, UIView *bar) {' 'static CGRect DMSMBarFrameNow(UIView *card, UIView *bar) {' 'static CGFloat DMAutoHideSMSlideDrawn(UIView *bar) {'
       'static BOOL DMAutoHideSMBarDragged(UIView *bar) {' 'static void DMAutoHideSMSlideBars(BOOL show, CGFloat h, BOOL animated) {' 'static CGFloat DMAutoHideSMBake(UIView *v) {')
NW_FN=('static CGRect DMNewWindowFrameWindowAt(int choice) {' 'static CGRect DMSMNewWindowDesk(CGRect u, CGSize scr) {' 'static CGRect DMSMNewWindowFrameAt(int choice, CGRect u, CGSize scr) {')
MS='s/\[UIScreen mainScreen\]/TMainScreen()/g; s/\[UIScreen screens\]/TScreens()/g'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet: the number of failed checks (99: the code could not be cut out or built)
  local X=$1 d=$2 q=$3 h n=0 r out dbg
  mkdir -p "$d"
  cp SMPastEdge.h "$d/SMPastEdge.h" 2>/dev/null || cp ../statusbar/SMPastEdge.h "$d/SMPastEdge.h" || { echo "FAIL  no SMPastEdge.h"; return 99; }
  [ -n "$(blk "$X" "$SM_IFACE")" ] && [ "$(grep -cF -e "$SM_PAN" "$X")" = 1 ] && [ "$(grep -cF -e "$SM_TOUCH" "$X")" = 1 ] || { echo "FAIL  $X: no title bar drag of the Stage Manager engine"; return 99; }
  for h in "${SM_DECL[@]}" "${SM_LINES[@]}" "${RT_LINES[@]}" "${SL_LINES[@]}" "$ANS_LINE" "$TOP_FN"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${SM_FN[@]}" "${RT_FN[@]}" "${SL_FN[@]}" "${NW_FN[@]}" "$DESK_FN" "$BAR_FN" "$PASS_FN" "$HOOK_FN"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no \"$h\""; return 99; }; done
  { for h in "${SM_DECL[@]}"; do line "$X" "$h"; done; blk "$X" "$SM_IFACE"; } > "$d/spe-decl.inc"
  { for h in "${SM_LINES[@]}"; do line "$X" "$h"; done; for h in "${SM_FN[@]}"; do fn "$X" "$h"; done; } | sed "$MS" > "$d/spe-glue.inc"
  { fn "$X" "$SM_TOUCH"; fn "$X" "$SM_PAN"; } | sed "$MS" > "$d/spe-pan.inc"
  { echo '#include "../common/MenuBarHeight.h"'; echo '#include "../common/BarAutoHide.h"'
    echo 'static BOOL gTAH = NO;   // (the menu bar hiding itself: auto-hide on, a pointer attached)'
    echo 'static BOOL DMAutoHideLayout(void) { return gTAH; }'; echo 'static CGFloat DMMenuBarHeight(void) { return 24.0; }'; line "$X" "$TOP_FN"; } > "$d/par-top.inc"
  { echo '#include "par-top.inc"'
    echo 'static int gTUsableReads = 0;   // (the desktop read: SpringBoard measures its Dock from the Dock window'"'"'s views)'
    echo 'static CGRect DMUsableArea(void) { gTUsableReads++; CGSize s = gIPad.size; CGFloat top = DMTopLimit(); return CGRectMake(0, top, s.width, MAX(200.0, s.height - gTIPadDock - 2.0 - top)); }'
    echo 'static int gTTVSize = 0; static CGFloat gTTVBarH = 24.0;   // (the TV'"'"'s Menu Bar Size and its bar'"'"'s height: the iPad'"'"'s, Small, until changed)'
    echo 'static CGFloat DMTVBarHeight(void) { return gTTVBarH; }'; echo 'static int gDMBarSize = 0; static int DMTVBarSizeNow(void) { return gTTVSize; }'
    echo 'static BOOL DMDockAutoHidesOn(UIScreen *s) { (void)s; return NO; }'
    echo 'static double MSBDAutoHideRoomEdge(int autoHide, double dockEdge, double screenEdge) { return autoHide ? screenEdge : dockEdge; }'
    echo 'static NSArray<UIScreen *> *TScreens(void) { return @[gIPad, gTV]; }'
    fn "$X" "$DESK_FN"; fn "$X" "$BAR_FN"; line "$X" "$ANS_LINE"; [ -n "$(line "$X" "$LOW_LINE")" ] && line "$X" "$LOW_LINE"; fn "$X" "$PASS_FN"
    echo 'static CGFloat gTIOSStatusBarH = 24.0;   // (iOS'"'"'s own status bar height on a Face ID iPad)'
    fn "$X" "$HOOK_FN" | sed 's/^- (CGFloat)_statusBarHeight {$/static CGFloat TSMStatusBarHeight(void) {/; s/%orig/gTIOSStatusBarH/'
  } | sed "$MS" > "$d/spe-desk.inc"
  { for h in "${RT_LINES[@]}"; do line "$X" "$h"; done; for h in "${RT_FN[@]}"; do fn "$X" "$h"; done; } | sed "$MS" > "$d/aht-retop.inc"
  { for h in "${SL_LINES[@]}"; do line "$X" "$h"; done; [ -n "$(fn "$X" "$CB_FN")" ] && fn "$X" "$CB_FN"; for h in "${SL_FN[@]}"; do fn "$X" "$h"; done; } | sed "$MS" > "$d/aht-slide.inc"
  for h in "${NW_FN[@]}"; do fn "$X" "$h"; done | sed "$MS" > "$d/aht-newwin.inc"
  grep -q '%orig' "$d/spe-desk.inc" && { echo "FAIL  $X: a %orig left in the hook cut out"; return 99; }
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-const-variable -Werror=implicit-function-declaration \
          -I"$d" -I. -I../statusbar -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-autohidetop.m 2>"$d/cc$dbg.txt" \
      || { [ -n "$q" ] || cat "$d/cc$dbg.txt"; echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
  done
  [ -n "$q" ] || grep -E 'warning:|error:' "$d/cc0.txt"
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); r=$?
  if [ $r != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($r failed checks, release $n)"; echo "$out" | grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  [ $n -gt 98 ] && n=98
  return $n
}

run "$X0" "$W/real"; rc=$?
# (site: the slide's height comes from the iPad's own menu bar alone -- gSMSlideBarH is set only by DMAutoHideSMSlideBars, which only
#  DMStatusBarMoveWindows calls, and only the iPad's bar code calls that (DMStatusBarSetHidden, DMAutoHideTick, DMAutoHideAfterRetile): a TV's bar,
#  shown or hidden by its own code (DMAutoHideTV...), never slides the iPad's title bars. 1.8.8.4's first device pass: with the pointer crossing to the TV and back,
#  the only slides seen were the iPad bar's, by a card's layout)
sl_set=$(grep 'gSMSlideBarH = ' "$X0" | grep -vc '^static CGFloat gSMSlideBarH = 0;'); sl_in=$(fn "$X0" 'static void DMAutoHideSMSlideBars(BOOL show, CGFloat h, BOOL animated) {' | grep -c 'gSMSlideBarH = ')
sl_calls=$(grep 'DMAutoHideSMSlideBars(' "$X0" | grep -vc '^static void DMAutoHideSMSlideBars('); sl_mw=$(fn "$X0" 'static void DMStatusBarMoveWindows(BOOL show, CGFloat h, BOOL animated) {' | grep -c 'DMAutoHideSMSlideBars(show, h, animated);')
mw_by=$(awk '/DMStatusBarMoveWindows\(/ && !/^static void DMStatusBarMoveWindows/ { sub(/\(.*/, "", hdr); sub(/^static void /, "", hdr); print hdr } /^(static|-|\+) / {hdr=$0}' "$X0" | sort -u | tr '\n' ' ')
if [ "$sl_set" = 1 ] && [ "$sl_in" = 1 ] && [ "$sl_calls" = 1 ] && [ "$sl_mw" = 1 ] && [ "$mw_by" = "DMAutoHideAfterRetile DMAutoHideTick DMStatusBarSetHidden " ]; then
  echo "PASS  site: our title bars' slide follows the iPad's own menu bar only (set in DMAutoHideSMSlideBars, by DMStatusBarMoveWindows, called by $mw_by-- no TV bar code)"
else echo "FAIL  site: the slide's height set or called elsewhere (set $sl_set, in DMAutoHideSMSlideBars $sl_in, calls $sl_calls, from DMStatusBarMoveWindows $sl_mw, DMStatusBarMoveWindows called by: $mw_by)"; rc=1; fi
if [ -z "$AHT_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x (-0777: the whole file)
    local d="$W/m$((++k))" out r
    mkdir -p "$d"; out="$d/StatusBar.x"
    perl -0777 -pe "$2" "$X0" > "$out"
    cmp -s "$out" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$out" "$d/w" q; r=$?
    if [ $r -gt 0 ] && [ $r -lt 99 ]; then echo "PASS  caught: $1 ($r check(s) fail)"; else echo "FAIL  not caught: $1 ($r)"; rc=1; fi
  }
  k=0
  mtf "our stage top keeping the bar's room while it hides itself (1.8.8.3's answer)" 's/MSBDBarAHSMStageTop\(h, DMMenuBarHeight\(\), title, hides\)/MSBDBarAHSMStageTop(h, DMMenuBarHeight(), title, 0)/'
  mtf "our desktop raised to the bar while it hides itself (1.8.8.3's)" 's/    CGFloat top = DMTopLimit\(\);\n    if \(CGRectGetMinY\(u\) < top\)/    CGFloat top = DMMenuBarHeight();\n    if (CGRectGetMinY(u) < top)/'
  mtf "a top of 24 taken for our answer before the bar ever hid itself (iOS's own height)" 's/gSMStatusBarTitle, gSMStatusBarLowered\)\) \{/gSMStatusBarTitle, YES)) {/; s/DMAutoHideLayout\(\), gSMStatusBarLowered, tv,/DMAutoHideLayout(), YES, tv,/'
  mtf "a TV's pass at the iPad's size left with the iPad's lowered top (1.8.7's early return)" 's/(static CGRect DMSMStageTopByDisplay\(CGRect r, CGRect b\) \{\n    UIScreen \*s = DMSMScreenOfSize\(b.size\);\n)/$1    if (s != [UIScreen mainScreen] && DMTVBarSizeNow() == gDMBarSize) return r;\n/'
  mtf "the other engines' retop by another bottom (their full-height windows would not grow as ours)" 's/if \(!MSBDBarAHRetop\(&ry, &rh, bottom, DMMenuBarHeight\(\), layout, wasTop\)\) continue;/if (!MSBDBarAHRetop(&ry, &rh, bottom + 30.0, DMMenuBarHeight(), layout, wasTop)) continue;/'
  mtf "our retop taking the bar's room back without the fit (a window Stage Manager moved down first stays past the Dock's line)" 's/id fa = a \? DMSMAttrsFitScreen\(a, nil, DMSMKeySetHas\(gSMBehindDock, k\), DMSMKeyText\(k\)\) : nil;/id fa = a;/'
  mtf "a window past an edge moved by our retop without its record (the request fits it inside)" 's/        if \(moved\) DMSMPastEdgeMoved\(was, f, scr\);[^\n]*\n//'
  mtf "our retop with no wait for a transition in flight" 's/ \|\| DMSMWorkspaceBusy\(\) \|\| DMSMTurnSettling\(\)/ || DMSMTurnSettling()/'
  mtf "our retop without the 4 tries (also the once-a-second pass's look, review of 1.8.8.4)" 's/        if \(tries >= 4\) continue;   \/\/ \(Stage Manager keeps putting it back[^\n]*\n//; s/if \(!k\.length \|\| \[gSMRetopTries\[k\] intValue\] >= 4\) continue;/if (!k.length) continue;/'
  mtf "a title bar's card asked as its superview (SpringBoard's card holds it in an inner clipping view: no show or hide moves a title bar, the first 1.8.8.4 device pass)" 's/    return card && \[bar isDescendantOfView:card\] \? card : nil;/    return card \&\& bar.superview == card ? card : nil;/'
  mtf "our title bars' slide left out of the bar's frame" 's/    f\.origin\.y \+= DMAutoHideSMSlideFor\(card, bar\);\n//'
  mtf "our title bars slid by a rule of their own (the bar's whole height at any top)" 's/return MSBDBarAHTitleSlide\(CGRectGetMinY\(c\) - kSMBarH, gSMSlideBarH,/return gSMSlideBarH; (void)MSBDBarAHTitleSlide(CGRectGetMinY(c) - kSMBarH, gSMSlideBarH,/'
  mtf "a drag on a slid title bar not moving the window down to it" 's/    t\.y \+= gSMDragSlid;\n//'
  mtf "the slide added before 1.8.8.3's follow (the follow works the travel out anew: the window's title bar back up under the menu bar)" 's/(    \/\/ \(1\.8\.8\.4: a drag that starts on the title bar slid down[^\n]*\n[^\n]*\n    if \(g\.state == UIGestureRecognizerStateBegan\) gSMDragSlid = DMAutoHideSMBake\(self\);\n    t\.y \+= gSMDragSlid;\n)//; s/(    \/\/ \(1\.8\.8\.3: the window follows the finger)/    if (g.state == UIGestureRecognizerStateBegan) gSMDragSlid = DMAutoHideSMBake(self);\n    t.y += gSMDragSlid;\n$1/'
  mtf "the once-a-second pass reading the desktop with nothing at the bar's line (review of 1.8.8.4)" 's/    if \(!atSwitch && !DMAutoHideSMAnyAtLine\(m\)\) return;[^\n]*\n//'
  mtf "the old tick left waiting beside a new one when the setting is turned on again (review of 1.8.8.4)" 's/        BOOL again = gAutoHideTimer != nil;/        BOOL again = NO;/'
  mtf "the tick stopped with our windows still waiting to go under the bar" 's/        if \(!again && gSMRetopPending >= 0 && waited < 20\) \{ DMAutoHideStopTimerLater\(t, waited \+ 1\); return; \}\n//'
  mtf "our new window in the desktop from the top edge while the bar hides itself (not the other engines' under the bar)" 's/    if \(choice != MSBDWindowSizeDefault\) u = DMSMNewWindowDesk\(u, scr\);[^\n]*\n//'
fi
[ $rc = 0 ] && echo "test-autohidetop: all checks pass" || echo "test-autohidetop: checks FAILED"
exit $rc
