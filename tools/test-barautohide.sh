#!/bin/bash
# Mac test of Automatically Hide and Show the Menu Bar per display (1.8.7 row 14; common/BarAutoHide.h, test-barautohide.c), then the sites in
# SpringBoard's status bar part: the iPad's machine moves only the iPad's copies, the TV's own state by its own setting and pointer, its strip in the
# per-scene layer helper, a copy by its own display's state, no window moved for the TV; 1.8.8.4: the iPad's one window top for every engine while its bar
# hides itself (our Stage Manager engine's stage top, desktop, retop and title bars by the rules the other engines use). Each site check is a function of the file it reads, so a copy
# with one site broken runs the same check: those made-to-fail copies, last, must each fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/t" test-barautohide.c && "$W/t" || fails=1
check() { if (eval "$2"); then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
S=../statusbar/StatusBar.x
c_split() {   # the iPad's machine moves the iPad's copies only; a TV's copies by the TV's state
  fn 'static NSArray<UIView *> *DMStatusBarsToMoveOn(int which) {' "$1" | grep -qF 'if ((which == 0 && other) || (which == 1 && !other)) continue;' \
    && grep -qF 'static NSArray<UIView *> *DMStatusBarsToMove(void) { return DMStatusBarsToMoveOn(0); }' "$1" \
    && fn 'static void DMAutoHideTVApply(NSString *why) {' "$1" | grep -qF 'for (UIView *b in bars) DMStatusBarApplyOffset(b, MSBDBarAHCopyOffset(&gDMTVBarAH, MIN(40.0, b.bounds.size.height)), YES);' \
    && fn 'static void DMAutoHideTVApply(NSString *why) {' "$1" | grep -qF 'NSArray *bars = DMStatusBarsToMoveOn(1);'
}
c_tv_state() {   # the TV's own state: its setting (msb autoHideStatusBar for that display, the iPad's until changed), a pointer, not locked; hides by the rule
  grep -qF 'static BOOL DMAutoHideTVSetting(UIScreen *tv) { return tv && !gStockBar && DMDispBool(tv, "msb", "autoHideStatusBar", DMAutoHidePref()); }' "$1" \
    && fn 'static void DMAutoHideTVTick(void) {' "$1" > "$W/tt" && grep -qF 'BOOL on = MSBDBarAHActive(DMAutoHideTVSetting(tv), DMAutoHidePointerAttached(), DMLockUp(lm));' "$W/tt" \
    && grep -qF 'if (MSBDBarAHShouldHide(&gDMTVBarAH, DMMenuOpenOnTV(), now)) { gDMTVBarAH.hidden = 1; DMAutoHideTVApply(@"the pointer left the TV' "$W/tt" \
    && grep -qF 'if (gDMTVBarAH.hidden) for (UIView *b in bars) DMStatusBarApplyOffset(b, MSBDBarAHCopyOffset(&gDMTVBarAH' "$W/tt" \
    && awk '/^@implementation DMStatusBarHover$/,/^@end$/' "$1" | grep -qF 'if (DMExternalScreenOf(g.view)) { DMAutoHideTVPointer(inside, [g locationInView:g.view], g.view.bounds.size); return; }'
}
c_fade() {   # a TV copy's hover that ends with the pointer still well inside the bar is a fade (iPadOS hid the idle pointer): on the bar until it moves
  fn 'static void DMAutoHideTVPointer(BOOL inside, CGPoint at, CGSize bar) {' "$1" > "$W/fa" && grep -qF 'if (gDMTVBarAH.pointerIn && MSBDBarAHEndIsFade(at.x, at.y, bar.width, bar.height)) {' "$W/fa" \
    && awk '/^@implementation DMStatusBarHover$/,/^@end$/' "$1" | grep -qF 'DMAutoHideTVPointer(inside, [g locationInView:g.view], g.view.bounds.size);' \
    && fn 'static void DMAutoHideTVTick(void) {' "$1" > "$W/ft" && grep -qF 'BOOL moved = !isnan(gDMTVFadePos.x) && !isnan(gDMTVPtrNow.x) && MSBDBarAHMovedAfterFade(gDMTVPtrNow.x - gDMTVFadePos.x, gDMTVPtrNow.y - gDMTVFadePos.y);' "$W/ft" \
    && awk '/BOOL moved = !isnan\(gDMTVFadePos.x\)/{a=NR} /    if \(!gDMTVBarAH.on\) return;/{b=NR} END{exit !(a && b && a < b)}' "$W/ft"   # (resolved with the TV's own off too: d09)
}
c_strip() {   # the TV's strip: in the per-scene layer helper, on while the TV's bar is hidden, its hover brings the bar
  fn 'static void DMAutoHideTVStrip(BOOL on) {' "$1" > "$W/st" && grep -qF 'DMSceneLayer(tv, @"autohide-strip", kMenuWindowLevel - 5.0, (DMSceneLayerKind){ "MSBSceneStripWindow", (IMP)DMSceneStripHitTest, NULL, "autohide" }, nil)' "$W/st" \
    && grep -qF 'strip.frame = CGRectMake(0, 0, w.bounds.size.width, kMSBDBarAHStripH);' "$W/st" && fn 'static void DMAutoHideTVApply(NSString *why) {' "$1" | grep -qF 'DMAutoHideTVStrip(gDMTVBarAH.hidden);' \
    && grep -qF 'if (inside && MSBDBarAHReveal(&gDMTVBarAH, CACurrentMediaTime())) DMAutoHideTVApply(@"the pointer reached the TV' "$1"
}
c_ipad() {   # the iPad's machine: as before, run with the TV's in the same tick; its zone not read with the pointer on a TV's bar; a TV menu holds only the TV's
  fn 'static void DMAutoHideTick(void) {' "$1" > "$W/it" && awk '/    DMAutoHideTVTick\(\);/{a=NR} /    if \(!active\) \{ gSBZone = 0; return; \}/{b=NR} END{exit !(a && b > a)}' "$W/it" \
    && grep -qF '(!gOverlay || DMMenuOpenOnTV())' "$W/it" && fn 'static void DMAutoHideSetZone(uint64_t z) {' "$1" | grep -qF 'z = MSBDBarAHIPadZone(z, DMAutoHidePointerOnTV());' \
    && fn 'static void DMAutoHideRefreshTimer(void) {' "$1" | grep -qF 'BOOL on = DMAutoHidePref() || DMAutoHideTVSetting(DMAutoHideTVScreen());'
}
c_no_window() {   # the TV's machine moves no window (Stage Manager parity): none of the window movers in it
  for f in 'static void DMAutoHideTVApply(NSString *why) {' 'static void DMAutoHideTVTick(void) {'; do
    fn "$f" "$1" | grep -qE 'DMStatusBarMoveWindows|DMAutoHideRetopAll|DMAutoHideSM|DMAerialMoveStage|DMSMRequestWindow|DMSMApply' && return 1
  done
  grep -qF '#include "../common/BarAutoHide.h"' "$1"
}
c_sm_top() {   # 1.8.8.4: our Stage Manager engine's top is every engine's -- the stage top (our answer), its desktop, the size grid's tallest window, a pass's top
  grep -qF 'static CGFloat DMTopLimit(void) { return MSBDBarAHWindowTop(MSBDMenuBarTopLimit(DMMenuBarHeight()), DMAutoHideLayout()); }' "$1" \
    && awk '/^- \(CGFloat\)_statusBarHeight \{$/{f=1} f' "$1" | awk '{print} /^}/{exit}' > "$W/sh" && grep -qF 'CGFloat a = ours ? MSBDBarAHSMStageTop(h, DMMenuBarHeight(), title, hides) : h;' "$W/sh" \
    && grep -qF 'BOOL ours = DMSMEngine(), hides = ours && DMAutoHideLayout();' "$W/sh" && grep -qF 'if (hides && !gSMStatusBarLowered) { gSMStatusBarLowered = YES;' "$W/sh" \
    && fn 'static CGRect DMSMUsableAreaForIdentity(id identity, CGSize *screenOut) {' "$1" | grep -qF 'CGFloat top = DMTopLimit();' \
    && fn 'static CGFloat DMSMTopBarOf(CGSize size) {' "$1" | grep -qF '? DMTopLimit() : DMTVBarHeight();' \
    && fn 'static CGRect DMSMStageTopByDisplay(CGRect r, CGRect b) {' "$1" > "$W/tb" && grep -qF 'BOOL tv = s != [UIScreen mainScreen];' "$W/tb" && ! grep -qF 's == [UIScreen mainScreen] ||' "$W/tb" \
    && grep -qF 'if (!MSBDBarAHIsOurTop(was, gSMStatusBarOrigH, bar, gSMStatusBarTitle, gSMStatusBarLowered)) {' "$W/tb" \
    && grep -qF 'MSBDBarAHPassTop(was, gSMStatusBarOrigH, bar, gSMStatusBarTitle, DMAutoHideLayout(), gSMStatusBarLowered, tv, DMTVBarSizeNow() == gDMBarSize, DMTVBarHeight());' "$W/tb"
}
c_sm_retop() {   # ... its windows at the top as the other engines' at a mode change and once a second: one rule (MSBDBarAHRetop), the stage on screen of the iPad
  fn 'static void DMAutoHideTick(void) {' "$1" > "$W/rt" && grep -qF 'DMAutoHideSMRetop(layout, active, modeChanged);' "$W/rt" && grep -qF 'wasLayout = layout; modeChanged = YES;' "$W/rt" \
    && grep -qF 'if (DMSMFree() && DMFitEnabled() && gSMFitSlots.count >= 2) DMSMFitTick(YES);' "$W/rt" \
    && fn 'static void DMAutoHideRetopAll(BOOL layout, BOOL tiled, BOOL modeChanged) {' "$1" | grep -qF 'if (!MSBDBarAHRetop(&ry, &rh, bottom, DMMenuBarHeight(), layout, wasTop)) continue;' \
    && fn 'static void DMAutoHideSMRetop(BOOL layout, BOOL active, BOOL modeChanged) {' "$1" > "$W/sr" && grep -qF 'BOOL moved = MSBDBarAHRetop(&y, &h, bottom, bar, give, NO);' "$W/sr" \
    && grep -qF 'if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(shown))) return;' "$W/sr" && grep -qF 'if (!shown) { if (atSwitch) gSMRetopPending = give ? 1 : 0; return; }' "$W/sr" && grep -qF 'DMSMApplyPlacesMarkedIn(places, shown, [NSSet setWithArray:places.allKeys])' "$W/sr" \
    && grep -qF 'if (moved) DMSMPastEdgeMoved(was, f, scr);' "$W/sr" && grep -qF 'if (tries >= 4) continue;' "$W/sr" && grep -qF 'if (gSMRetopPending < 0 && !(layout && active)) return;' "$W/sr" \
    && grep -qF 'id fa = a ? DMSMAttrsFitScreen(a, nil, DMSMKeySetHas(gSMBehindDock, k), DMSMKeyText(k)) : nil;' "$W/sr" && grep -qF 'gOverlay || gSMGrowing.count' "$W/sr" \
    && fn 'static void DMAutoHideStopTimerLater(NSTimer *t, int waited) {' "$1" > "$W/stl" && grep -qF 'if (!again && gSMRetopPending >= 0 && waited < 20) { DMAutoHideStopTimerLater(t, waited + 1); return; }' "$W/stl" \
    && grep -qF 'BOOL again = gAutoHideTimer != nil;' "$W/stl" && grep -qF 'if (!again && gSMRetopPending >= 0) { gSMRetopPending = -1;' "$W/stl" \
    && ! grep -qE 'DMSMStageWithAttrs\(st, na' "$W/sr"
}
c_sm_slide() {   # ... its title bars slide down with the bar as the other engines' (MSBDBarAHTitleSlide), in the bar's frame from the card's place; a drag on a slid one bakes it
  fn 'static void DMStatusBarMoveWindows(BOOL show, CGFloat h, BOOL animated) {' "$1" > "$W/mw" && grep -qF 'DMAutoHideSMSlideBars(show, h, animated);' "$W/mw" \
    && grep -qF 'MSBDBarAHTitleSlide(top, h, touching, show)' "$W/mw" \
    && fn 'static CGFloat DMAutoHideSMSlideFor(UIView *card, UIView *bar) {' "$1" > "$W/sf" && grep -qF 'return MSBDBarAHTitleSlide(CGRectGetMinY(c) - kSMBarH, gSMSlideBarH, MSBDMenuBarFixedSite(gDMBarSize, DMMenuBarHeight()) - 1.0, YES);' "$W/sf" \
    && grep -qF 'if (!(gSMSlideBarH > 0) || !bar.userInteractionEnabled || !card.window || DMAutoHideSMBarDragged(bar)) return 0.0;' "$W/sf" \
    && fn 'static void DMSMChrome(UIView *card) {' "$1" | grep -qF 'CGRect f = DMSMBarFrameNow(card, bar);' \
    && fn 'static CGRect DMSMBarFrameNow(UIView *card, UIView *bar) {' "$1" | grep -qF 'f.origin.y += DMAutoHideSMSlideFor(card, bar);' \
    && fn 'static void DMAutoHideSMSlideBars(BOOL show, CGFloat h, BOOL animated) {' "$1" | grep -qF 'gSMSlideBarH = show && DMSMFree() && h > 0 ? h : 0.0;' \
    && awk '/^- \(void\)dm_pan:\(UIPanGestureRecognizer \*\)g \{$/{f=1} f' "$1" | awk '{print} /^}/{exit}' > "$W/dp" && grep -qF 'if (g.state == UIGestureRecognizerStateBegan) gSMDragSlid = DMAutoHideSMBake(self);' "$W/dp" && grep -qF '    t.y += gSMDragSlid;' "$W/dp" \
    && grep -qF 'CGRectMake(0, -kSMBarH + DMAutoHideSMSlideDrawn(bar), card.bounds.size.width, kSMBarH)' ../statusbar/MacSwitcherSM.h
}
c_sm_rule() {   # ... and the crash guard's rule for its new functions: the auto-hide's (^_?DMAutoHide), not the whole window code
  # (review of 1.8.8.4: the slide and the drag's bake are their own functions -- inlined, the slide was DMSMBarFrameNow's, the window code's switch,
  #  and the bake -[DMSMTitleBar dm_pan:]'s, the traffic lights' switch)
  [ "$(grep -cE '^static [A-Za-z]+ \**DMAutoHideSM[A-Za-z]*\(' "$1")" -ge 6 ] && ! grep -qE '^static [A-Za-z]+ \**DMSMAutoHide' "$1" \
    && grep -qxF '__attribute__((noinline)) static CGFloat DMAutoHideSMSlideFor(UIView *card, UIView *bar);' "$1" \
    && grep -qE '^__attribute__\(\(noinline\)\) static CGFloat DMAutoHideSMBake\(UIView \*bar\);' "$1"
}
check "1.8.8.4: our Stage Manager engine's top is every engine's while the bar hides itself: its stage top (our answer), its desktop, the size grid's tallest window; a pass's top for the iPad by its bar now, a TV's with its own room" "c_sm_top $S"
check "1.8.8.4: ... its windows at the top move as the other engines' (one rule) at a mode change and once a second, its tiles laid out again, the iPad's stages only" "c_sm_retop $S"
check "1.8.8.4: ... its title bars slide down with the bar as the other engines' (one rule), kept in the bar's frame; a drag on a slid one moves the window down to it first" "c_sm_slide $S"
check "1.8.8.4: ... its new functions under the auto-hide's crash rule (the slide and the drag's bake their own functions)" "c_sm_rule $S && grep -q '^sym MacStatusBarCore \^_?DMAutoHide autoHideStatusBar\$' crashmap-rules.txt"
check "the iPad's machine moves only the iPad's bar copies; a TV's by the TV's own state (each copy its own display's)" "c_split $S"
check "the TV's own state: its own setting (the iPad's until changed), a pointer, not on the Lock Screen; it hides by the rule; a new copy hidden like its display's" "c_tv_state $S"
check "the TV's bar: a hover ended with the pointer still on it is a fade (iPadOS hid the idle pointer), kept until the pointer moves (A12Z, d07)" "c_fade $S"
check "the TV's top-edge strip in the per-scene layer helper, on while its bar is hidden; its hover brings the bar" "c_strip $S"
check "the iPad's machine as before, with the TV's in the same tick; its zone not read while the pointer is on a TV's bar; a TV's menu holds only the TV's bar; the tick runs for either setting" "c_ipad $S"
check "the TV's bar hides with no window moved (as the iPad's Stage Manager engine)" "c_no_window $S"
check "crash rules: the TV's auto-hide functions are the auto-hide's (^_?DMAutoHide), the strip's hit test in its section" "grep -q '^sym MacStatusBarCore \^_?DMAutoHide autoHideStatusBar\$' crashmap-rules.txt && [ \$(grep -cE '^static [A-Za-z]+ \**DMAutoHideTV[A-Za-z]*\(' $S) -ge 5 ]"
mutant() {   # <name> <file> <old> <new> <check function>
  local M="$W/m-$1"; mkdir -p "$M"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' "$2" "$M/f" "$3" "$4" || return 1
  ! $5 "$M/f" 2>/dev/null
}
check "made to fail: the iPad's machine moving every display's copies (1.8.6's one bar for both)" "mutant split $S 'static NSArray<UIView *> *DMStatusBarsToMove(void) { return DMStatusBarsToMoveOn(0); }' 'static NSArray<UIView *> *DMStatusBarsToMove(void) { return DMStatusBarsToMoveOn(2); }' c_split"
check "made to fail: the TV's setting read as the iPad's" "mutant tvset $S 'DMDispBool(tv, \"msb\", \"autoHideStatusBar\", DMAutoHidePref())' 'DMAutoHidePref()' c_tv_state"
check "made to fail: a TV copy's hover taken as the iPad's" "mutant tvhover $S '    if (DMExternalScreenOf(g.view)) { DMAutoHideTVPointer(inside, [g locationInView:g.view], g.view.bounds.size); return; }   // (1.8.7 row 14: a TV'\''s copy -- that display'\''s state)
' '' c_tv_state"
check "made to fail: every ended hover taken as the pointer leaving (a resting pointer's fade hid the bar)" "mutant fade $S 'if (gDMTVBarAH.pointerIn && MSBDBarAHEndIsFade(at.x, at.y, bar.width, bar.height)) {' 'if (0) {' c_fade"
check "made to fail: a fade on the TV's bar resolved only while the TV's own is on (the iPad's zone kept unread for good, d09)" "mutant fadeoff $S '    if (!gDMTVBarAH.on) return;
' '    if (!gDMTVBarAH.on) return;
    BOOL moved = !isnan(gDMTVFadePos.x) && !isnan(gDMTVPtrNow.x) && MSBDBarAHMovedAfterFade(gDMTVPtrNow.x - gDMTVFadePos.x, gDMTVPtrNow.y - gDMTVFadePos.y);
' c_fade"
check "made to fail: the TV's strip never shown" "mutant strip $S '    DMAutoHideTVStrip(gDMTVBarAH.hidden);
' '' c_strip"
check "made to fail: the iPad's zone read with the pointer on the TV's top" "mutant zone $S '    z = MSBDBarAHIPadZone(z, DMAutoHidePointerOnTV());   // (1.8.7: the pointer on a TV'\''s bar or strip is not on the iPad'\''s)
' '' c_ipad"
check "made to fail: the TV's tick only while the iPad's is on (after its early return)" "mutant tick $S '    DMAutoHideTVTick();   // (1.8.7 row 14: the TV'\''s own bar, by its own setting)
    if (!active) { gSBZone = 0; return; }' '    if (!active) { gSBZone = 0; return; }
    DMAutoHideTVTick();' c_ipad"
check "made to fail: the TV's windows moved down with its bar" "mutant windows $S '    DMAutoHideTVStrip(gDMTVBarAH.hidden);
' '    DMAutoHideTVStrip(gDMTVBarAH.hidden);
    DMStatusBarMoveWindows(!gDMTVBarAH.hidden, 37.0, YES);
' c_no_window"
check "made to fail: our stage top keeping the bar's room while it hides itself (1.8.8.3)" "mutant smanswer $S 'MSBDBarAHSMStageTop(h, DMMenuBarHeight(), title, hides)' 'MSBDBarAHSMStageTop(h, DMMenuBarHeight(), title, 0)' c_sm_top"
check "made to fail: our desktop raised to the bar while it hides itself (1.8.8.3)" "mutant smdesk $S '    CGFloat top = DMTopLimit();
    if (CGRectGetMinY(u) < top)' '    CGFloat top = DMMenuBarHeight();
    if (CGRectGetMinY(u) < top)' c_sm_top"
check "made to fail: the iPad's own pass left as it carried it (the main screen skipped, 1.8.8.3)" "mutant smpass $S '    if (!s || !(gSMStatusBarAnswer > 0) || !(gSMStatusBarOrigH >= 0)) return r;
    BOOL tv = s != [UIScreen mainScreen];' '    if (!s || !(gSMStatusBarAnswer > 0) || !(gSMStatusBarOrigH >= 0)) return r;
    BOOL tv = s != [UIScreen mainScreen]; if (s == [UIScreen mainScreen] || 0) return r;' c_sm_top"
check "made to fail: our windows not retopped" "mutant smretop $S '    DMAutoHideSMRetop(layout, active, modeChanged);' '' c_sm_retop"
check "made to fail: our retop by a rule of its own (the bar's line taken as 24 exactly)" "mutant smrule $S 'BOOL moved = MSBDBarAHRetop(&y, &h, bottom, bar, give, NO);' 'BOOL moved = fabs(y - 24.0) < 0.5; if (moved) y = 0;' c_sm_retop"
check "made to fail: the bar's room taken back without the fit (a window Stage Manager's own pass moved down first stays 24 pt past the Dock's line)" "mutant smfit $S '            id fa = a ? DMSMAttrsFitScreen(a, nil, DMSMKeySetHas(gSMBehindDock, k), DMSMKeyText(k)) : nil;' '            id fa = a;' c_sm_retop"
check "made to fail: a TV's stage retopped too" "mutant smtv $S '    if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(shown))) return;' '' c_sm_retop"
check "made to fail: a switch at the Home Screen dropped" "mutant smhome $S '    if (!shown) { if (atSwitch) gSMRetopPending = give ? 1 : 0; return; }' '    if (!shown) return;' c_sm_retop"
check "made to fail: the tick stopped with our windows still waiting to go under the bar" "mutant smtimer $S '        if (!again && gSMRetopPending >= 0 && waited < 20) { DMAutoHideStopTimerLater(t, waited + 1); return; }
' '' c_sm_retop"
check "made to fail: the old tick left waiting beside a new one (the setting on again meanwhile)" "mutant smagain $S '        BOOL again = gAutoHideTimer != nil;' '        BOOL again = NO;' c_sm_retop"
check "made to fail: the slide inlined into DMSMBarFrameNow (a crash in it the window code's)" "mutant smslideinl $S '__attribute__((noinline)) static CGFloat DMAutoHideSMSlideFor(UIView *card, UIView *bar);' 'static CGFloat DMAutoHideSMSlideFor(UIView *card, UIView *bar);' c_sm_rule"
check "made to fail: the bake inlined into -dm_pan: (a crash in it the traffic lights')" "mutant smbakeinl $S '__attribute__((noinline)) static CGFloat DMAutoHideSMBake(UIView *bar);' 'static CGFloat DMAutoHideSMBake(UIView *bar);' c_sm_rule"
check "made to fail: our title bars not slid with the bar" "mutant smslide $S '    DMAutoHideSMSlideBars(show, h, animated);   // (1.8.8.4' '    // (1.8.8.4' c_sm_slide"
check "made to fail: the slide left out of the bar's frame (DMSMChrome's own layout undoes it)" "mutant smframe $S '    CGRect f = DMSMBarFrameNow(card, bar);   // (17/18' '    CGRect f = DMSMBarFrame(card);   // (17/18' c_sm_slide"
check "made to fail: the slide kept while its own drag goes on" "mutant smdrag $S ' || DMAutoHideSMBarDragged(bar)) return 0.0;' ') return 0.0;' c_sm_slide"
check "made to fail: a drag on a slid title bar not moving the window down to it" "mutant smbake $S '    t.y += gSMDragSlid;
' '' c_sm_slide"
[ $fails = 0 ] && echo "test-barautohide: all checks pass" || { echo "test-barautohide: checks FAILED"; exit 1; }
