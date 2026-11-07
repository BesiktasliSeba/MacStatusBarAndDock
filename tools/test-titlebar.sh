#!/bin/bash
# Mac test of the title bar's double tap (1.8.3 item 8; statusbar/TitleBarRule.h, test-titlebar.c), then the sites: one recogniser of ours on every
# engine's title bar and our own windows' (MilkyWay4's and Zetsu's own double taps there switched off), never on a traffic light, Aerial's stage
# only in its title strip; Fill's way back through Return to Previous Size's record, Zoom's through its own; the Settings row.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/ttb" test-titlebar.c
"$W/ttb"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
B=../statusbar/TitleBarTap.h; S=../statusbar/StatusBar.x; N=../statusbar/NativeWindow.h; K=../statusbar/WindowKeys.h; PL=../statusbar/macstatusbarprefs/Resources/Windows.plist
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
has() { grep -qF -- "$1" "$W/fn"; }   # (a line, as written, in the function fn read last)
before() { awk -v a="$1" -v b="$2" 'index($0, a) && !x {x=NR} index($0, b) && !y {y=NR} END{exit !(x && y && x < y)}' "$W/fn"; }   # (line $1 before line $2 there)
A=../statusbar/WindowAPI.h; R=../statusbar/SMResizeAnchor.h
check "a recogniser of ours on each title bar: our windows (their zoom-only double tap gone), Stage Manager's (ours), Aerial 5.x and 3.0's stage, MilkyWay4's bar, Zetsu's top bar" \
  "grep -q 'DMTitleTapAttach(_titleBar, kDMTitleNative);' $N && ! grep -q 'initWithTarget:self action:@selector(zoom)' $N && grep -q 'DMTitleTapAttach(self, kDMTitleSM);' $S \
   && [ \$(grep -c 'DMTitleTapAttach(stage, kDMTitleAerial);' $S) = 2 ] && grep -q 'DMTitleTapAttach(bar, kDMTitleMilkyWay);' $S && grep -q 'DMTitleTapAttach(menu, kDMTitleZetsu);' $S \
   && grep -q '#include \"TitleBarTap.h\"' $S"
check "  ... two taps, waiting for nothing and letting every other recogniser go on (the window's drag, a tap that brings it forward); never a touch on a light or a button; Aerial's stage in its title strip only" \
  "fn 'static void DMTitleTapAttach(UIView *bar, int kind) {' $B && grep -q 't.numberOfTapsRequired = 2;' \$W/fn && grep -q 't.cancelsTouchesInView = NO; t.delaysTouchesBegan = NO; t.delaysTouchesEnded = NO;' \$W/fn \
   && grep -q 'shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer \*)other { return YES; }' $B \
   && grep -q 'if (\[v isKindOfClass:\[UIControl class\]\]) return NO;' $B && grep -q 'return gAerialFlavor == 5 ? DMA5DragAllowedAt(stage, p) : (p.y >= -12.0 && p.y < kStageBarHeight);' $B"
check "  ... MilkyWay4's and Zetsu's own double taps on their bars switched off only while ours acts there (a choice made, not Do Nothing), and back on at Do Nothing and never set: the engine's own as in 1.8.2.2 at the default (review 1.8.3 P3-2); the setting's change looks at every bar again" \
  "fn 'static void DMTitleTapAttach(UIView *bar, int kind) {' $B && grep -q 'BOOL ours = MSBDTitleActionFor(gTitleDoubleTap, kind == kDMTitleNative) != kMSBDTitleNothing;' \$W/fn \
   && grep -q 'if (ours && g.enabled) {' \$W/fn && grep -q 'g.enabled = NO; objc_setAssociatedObject(g, &kTitleTapOffKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \$W/fn \
   && grep -q '} else if (!ours && offByUs) {' \$W/fn && grep -q 'g.enabled = YES; objc_setAssociatedObject(g, &kTitleTapOffKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \$W/fn \
   && grep -q 'if (titleChanged) DMTitleTapSettingChanged();' $S && fn 'static void DMTitleTapSettingChanged(void) {' $B && grep -q 'DMTitleTapAttach(bar, \[objc_getAssociatedObject(g, &kTitleTapKindKey) intValue\]); break;' \$W/fn"
check "Fill and Zoom go back with the frame the window had just before -- taken at every fill from a frame that is not Fill, a Fit to Window tile or a half too (1.8.3 regression F2: Fill used Return to Previous Size's record, which a tiled window never takes) -- on Stage Manager, the engines and our own windows; Fill still takes Return to Previous Size's record as the Window menu's Fill; every engine moves its window as the Window menu does" \
  "grep -q 'static BOOL DMWinPrevWanted(void) { return gWindowKeysOn; }' $K && ! grep -q 'MSBDTitleWantsRecords' $K \
   && fn 'static void DMTitleTapEngineWindow(NSString *bundleID, NSString *why) {' $B && has 'NSValue *rec = DMTitleRecordHeldView(v, v.frame, bundleID);' && ! grep -q 'kWinPrevKey' \$W/fn \
   && has 'DMTitleRecordEngineTo(v, to);' && has 'if (step != kMSBDTitleBack && !zoom) DMWinPrevNoteView(v, DMWinTiledEngine(v.frame), v.frame);' \
   && has 'DMAerialMoveStage(v, to, nil);' && has 'DMFitGroupForget(bundleID);' \
   && fn 'static void DMTitleTapSMWindow(NSString *key, NSString *why) {' $B && has 'NSValue *rec = DMTitleRecordHeldSM(key, now.CGRectValue);' && ! grep -q 'gSMWinPrev\[key\]' \$W/fn \
   && has 'DMTitleRecordSMTo(key, stage, DMSMLayoutFrameIn(@\"fill\", u, scr));' && has 'DMTitleRecordSMTo(key, stage, rec.CGRectValue);' \
   && has 'if (!zoom) DMWinPrevNoteSM(key, stage);' && has 'BOOL ok = DMSMApplyLayoutsIn(@{key: @\"fill\"}, stage);' \
   && fn 'static void DMTitleTapNative(DMNativeWindow *w, NSString *why) {' $B && has 'if (action == kMSBDTitleZoom) { [w zoom]; return; }' && has 'NSValue *rec = DMTitleRecordHeldView(w, w.frame, w.title ?: @\"our window\");' \
   && has 'DMTitleRecordNativeTo(w, f);' && has 'DMNativeLayout(w, @\"fill\");' \
   && fn 'static void DMWindowKeysApply(void) {' $K && has 'if (!MSBDTitleKeepsFrames(gTitleDoubleTap)) gSMWinZoom = nil;'"
check "  ... Minimize as each engine minimizes a window; nothing while SpringBoard is busy or in Guided Access" \
  "grep -q 'if (DMActiveEngine() == DMEngineMilkyWay) DMMinimizeWindow(v); else DMMinimizeStage(v);' $B && grep -q 'BOOL ok = DMSMWindowAction(key, @\"removeFromSet\");' $B \
   && fn '- (void)doubleTap:(UITapGestureRecognizer *)g {' $B && grep -q 'DMGARefuses(@\"window title bar\")' \$W/fn && grep -q 'if (act) DMTitleTapWhenFree(act, 0);' \$W/fn \
   && fn 'static void DMTitleTapWhenFree(void (^act)(NSString *), int tries) {' $B && grep -q 'NSString \*busy = DMWindowAPIBusyWhyPassing(&passing);' \$W/fn && grep -q 'switch (MSBDTitleTapWhen(busy != nil, passing, tries)) {' \$W/fn \
   && grep -q 'DMTitleTapWhenFree(act, tries + 1);' \$W/fn"
check "  ... a double tap during a transition (its own first tap's activation) waits for it and then acts, on the window tapped" \
  "fn '- (void)doubleTap:(UITapGestureRecognizer *)g {' $B && grep -q 'act = ^(NSString \*why) { DMTitleTapSMWindow(key, why); };' \$W/fn && [ \$(grep -c 'act = ^(NSString \*why) { DMTitleTapEngineWindow(b, why); };' \$W/fn) = 3 ] \
   && grep -q 'if (w) DMTitleTapNative(w, why);' \$W/fn"
check "Stage Manager's Fill / Zoom records (the frame from before and the Fill it was kept with, by window): pruned of closed windows at each take, as Return to Previous Size's, dropped when the setting is neither Fill nor Zoom; a bar that knows only its app names the app's newest window (review 1.8.3 P2-5)" \
  "fn 'static void DMTitleTapSMWindow(NSString *key, NSString *why) {' $B && has 'key = DMSMWindowKeyOf(key);' \
   && fn 'static void DMTitleRecordSMTo(NSString *key, id stage, CGRect to) {' $K && has 'key = DMSMWindowKeyOf(key);' && has 'DMSMRecordsPrune(gSMWinZoom);' && has 'gSMWinZoom[key] = DMTitleRecordPair(now.CGRectValue, fill);' \
   && fn 'static void DMWindowKeysApply(void) {' $K && has 'if (!MSBDTitleKeepsFrames(gTitleDoubleTap)) gSMWinZoom = nil;'"
check "the setting read with the others; never set (KT, review 1.8.3 P2-3): an app's window does nothing on every engine, our own windows zoom as before 1.8.3" \
  "grep -q 'int title = MSBDTitleActionFromStored(tr && CFGetTypeID(tr) == CFStringGetTypeID() ? \[(__bridge NSString \*)tr UTF8String\] : NULL);' $S && grep -q 'static int gTitleDoubleTap = kMSBDTitleNeverSet;' $S \
   && fn 'static void DMTitleTapNative(DMNativeWindow *w, NSString *why) {' $B && grep -q 'int action = MSBDTitleActionFor(gTitleDoubleTap, true);' \$W/fn \
   && fn 'static void DMTitleTapSMWindow(NSString *key, NSString *why) {' $B && grep -q 'int action = MSBDTitleActionFor(gTitleDoubleTap, false);' \$W/fn \
   && fn 'static void DMTitleTapEngineWindow(NSString *bundleID, NSString *why) {' $B && grep -q 'int action = MSBDTitleActionFor(gTitleDoubleTap, false);' \$W/fn \
   && fn '- (void)doubleTap:(UITapGestureRecognizer *)g {' $B && awk '/MSBDTitleActionFor\\(gTitleDoubleTap, kind == kDMTitleNative\\) == kMSBDTitleNothing\\) return;/{a=NR} /DMGARefuses/{b=NR} /DMTitleTapWhenFree\\(act, 0\\);/{c=NR} END{exit !(a && b && c && a < b && b < c)}' \$W/fn"
check "the Settings row: Windows & Multitasking under Window Size, Apple's four choices, Do Nothing shown while never set (review 1.8.3 P2-3), posted to SpringBoard" \
  "plutil -convert json -o - $PL | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; k=[x.get(\"key\") for x in it]; r=[x for x in it if x.get(\"key\")==\"titleBarDoubleTap\"]; sys.exit(0 if len(r)==1 and k.index(\"titleBarDoubleTap\")==k.index(\"windowSize\")+1 and r[0][\"validValues\"]==[\"fill\",\"zoom\",\"minimize\",\"none\"] and r[0][\"validTitles\"]==[\"Fill\",\"Zoom\",\"Minimize\",\"Do Nothing\"] and r[0][\"default\"]==\"none\" and r[0][\"PostNotification\"]==\"com.besiktasliseba.macstatusbar/prefsChanged\" and r[0][\"label\"]==\"Double-Tap a Title Bar to\" else 1)'"
check "P4-1: the Window menu's layouts keep the title bar's frame from before in step on every engine, before each moves its window -- Stage Manager, Zetsu, Aerial, MilkyWay4 --; the window keys' and the window API's layouts are the same calls (DMLayoutFrontWindow), our own windows' through DMNativeLayout (review 1.8.3 P4-1: only the title bar's double tap wrote or cleared it)" \
  "fn 'static void DMWindowLayout(NSString *name) {' $S && before 'DMTitleRecordSMTo(smKey, DMSMStageOf(smKey), w);' 'BOOL ok = DMSMSetWindowGeometry(smKey,' \
   && before 'DMTitleRecordEngineTo(zw, target);' 'DMZetsuMove(zw, target, YES,' && before 'DMTitleRecordEngineTo(stage, target);' 'DMAerialMoveStage(stage, target,' \
   && before 'DMTitleRecordEngineTo(window, target);' 'window.frame = target;' \
   && fn 'static void DMLayoutFrontWindow(NSString *name, NSString *why) {' $A && has 'if (nw) { DMNativeLayout(nw, name); return; }' && has 'DMWindowLayout(name);' \
   && fn 'static void DMNativeLayout(DMNativeWindow *w, NSString *name) {' $A && before 'DMTitleRecordNativeTo(w, f);' 'w.frame = f;' \
   && grep -qF 'DMLayoutFrontWindow(@(layout), @\"the window API\");' $A"
check "  ... the window keys' Center and Return to Previous Size (our windows, Stage Manager, the engines) and their arrangements (each window, Stage Manager's in one plan)" \
  "fn 'static void DMCenterFrontWindow(NSString *why) {' $K && before 'DMTitleRecordNativeTo(nw, f);' 'nw.frame = f;' \
   && before 'DMTitleRecordSMTo(key, stage, f);' 'DMSMApplyPlacesIn(@{key: [NSValue valueWithCGRect:f]}, stage);' && before 'DMTitleRecordEngineTo(v, f);' 'DMAerialMoveStage(v, f, nil);' \
   && fn 'static void DMWindowBackFromTile(NSString *why) {' $K && before 'DMTitleRecordNativeTo(nw, f);' 'nw.frame = f;' \
   && before 'DMTitleRecordSMTo(key, stage, rec.CGRectValue);' 'DMSMApplyPlacesIn(@{key: rec}, stage);' && before 'DMTitleRecordEngineTo(v, f);' 'DMAerialMoveStage(v, f, nil);' \
   && fn 'static void DMArrangeWindows(const char *const *slots, int count, NSString *why) {' $K && before 'DMTitleRecordSMPlan(plan, stage);' 'BOOL ok = DMSMApplyLayoutsIn(plan, stage);' \
   && before 'DMTitleRecordEngineTo(s, f);' 'DMAerialMoveStage(s, f, nil);'"
check "  ... the Window menu's Swap rows (two windows, a half and two quarters), on Stage Manager and the engines" \
  "fn 'static void DMSwapWindows(BOOL horizontal) {' $S && has 'if (DMSMSwapPlan(horizontal, plan)) { DMTitleRecordSMPlan(plan, DMSMWorkingStage()); DMSMApplyLayouts(plan); }' \
   && before 'DMTitleRecordEngineTo(stages[i], DMLayoutFrame(slots[i]));' 'DMAerialMoveStage(stages[i], DMLayoutFrame(slots[i]), nil);' \
   && fn 'static void DMApplyHalfQuarterSwap(UIView *half, NSString *halfSlot, UIView *quarter, NSString *quarterSlot) {' $S \
   && before 'DMTitleRecordEngineTo(half, DMLayoutFrame(quarterSlot)); DMTitleRecordEngineTo(quarter, DMLayoutFrame(halfSlot));' 'DMAerialMoveStage(half, DMLayoutFrame(quarterSlot), nil);' \
   && grep -qF 'NSDictionary *plan = @{hb: qs[i], qb[i]: hs}; DMTitleRecordSMPlan(plan, DMSMWorkingStage()); DMSMApplyLayouts(plan);' $S"
check "  ... Fit to Window's placements: the engines' (its tiles, the side picked, No Fit, the spread, back from full screen) and Stage Manager's (every plan it applies, one window at Fill, No Fit, the spread)" \
  "fn 'static void DMApplyGroupSlots(UIView *fresh) {' $S && before 'DMTitleRecordEngineTo(s, f);' 'DMAerialMoveStage(s, f, nil);' \
   && fn 'static void DMApplySideChoice(' $S && has 'DMTitleRecordEngineTo(stage, c); DMAerialMoveStage(stage, c, nil);' \
   && fn 'static void DMSpreadFitGroup(void) {' $S && has 'DMTitleRecordEngineTo(stages[i], f); DMAerialMoveStage(stages[i], f, nil);' \
   && fn 'static void DMFitRejoinAfterFullScreen(NSString *bundleID) {' $S && [ \$(grep -c 'DMTitleRecordEngineTo(st, f);' \$W/fn) = 2 ] && [ \$(grep -c 'DMAerialMoveStage(st, f, nil)' \$W/fn) = 2 ] \
   && fn 'static void DMSMFitTick(BOOL force) {' $S && [ \$(grep -cE 'DMSMApply(Layouts|Places)In\(' \$W/fn) = \$(grep -c 'DMTitleRecordSMPlan(' \$W/fn) ] \
   && before 'DMTitleRecordSMPlan(@{ one: @\"fill\" }, DMSMFrontStage());' 'DMSMApplyLayoutsIn(@{ one: @\"fill\" }, DMSMFrontStage());' \
   && fn 'static void DMSMFitAskThen(NSString *bundle, NSString *leftB, NSString *rightB, void (^open)(void)) {' $S && has 'DMTitleRecordSMPlan(@{newB: DMSMNoFitPlace(st)}, st); DMSMApplyPlacesIn(@{newB: DMSMNoFitPlace(st)}, st);' \
   && fn 'static void DMSMSpreadFit(int tries) {' $S && before 'DMTitleRecordSMPlan(plan, stage);' 'BOOL ok = DMSMApplyPlacesIn(plan, stage);'"
check "  ... and a move or a resize by hand drops it (a frame from before is never older than the window's last move by hand): every engine's move (DMSnapMoveEnded, first), Zetsu's corner, MilkyWay4's handle, Aerial 5.x's corner, Aerial 3.0's drag and resize, Stage Manager's title bar drag and 16's resize, our own windows' move and resize" \
  "fn 'static void DMSnapMoveEnded(UIView *st) {' $S && sed -n 2p \$W/fn | grep -qF 'DMTitleRecordMovedView(st);' \
   && grep -A1 -F 'if (g.state == UIGestureRecognizerStateEnded) DMTitleRecordMovedView(w);' $S | grep -qF 'f = DMSnapEngineWindow(w, f, (self.left' \
   && grep -A1 -F 'if (g.state == UIGestureRecognizerStateEnded) DMTitleRecordMovedView(win);' $S | grep -qF \"the handle's two sides\" \
   && grep -A1 -F 'if (s == UIGestureRecognizerStateEnded) DMTitleRecordMovedView(stage);   // (a resize by hand' $S | grep -qF 'if (s == UIGestureRecognizerStateEnded && !DMSnapOff()) {' \
   && fn 'static void DMAerialGestureAfter(UIView *stage, UIGestureRecognizerState s, BOOL wasPan) {' $S && has 'if (s == UIGestureRecognizerStateEnded) DMTitleRecordMovedView(stage);' \
   && grep -A1 -F 'gSMDragUntil = CACurrentMediaTime() + 1.0;' $S | grep -qF 'DMTitleRecordMovedSM(w);' \
   && grep -A2 -F 'if (MSBDSnapHeldSidesMatch(c, start, how)) {' $R | grep -qF 'DMTitleRecordMovedSM(k);' \
   && [ \$(grep -c 'self.restoreFrame = CGRectNull; self.layoutName = nil; DMTitleRecordMovedView(self);' $N) = 2 ]"
check "  ... at a double tap the frame from before counts only while the window is still at the Fill it was kept with (else dropped: the engine's own maximize, a turn); the title bar's own placements go through the same rule, and nothing else writes the records" \
  "[ \$(grep -c 'DMTitleRecordHeld' $B) = 3 ] && ! grep -q 'objc_setAssociatedObject([a-z]*, &kWinZoomKey' $B && ! grep -qE 'gSMWinZoom\[[a-zA-Z]+\] = ' $B \
   && [ \$(grep -c 'gSMWinZoom\[key\] = ' $K) = 1 ] && [ \$(grep -c 'objc_setAssociatedObject([a-z]*, &kWinZoomKey' $K) = 3 ] \
   && fn 'static NSValue *DMTitleRecordHeldView(UIView *v, CGRect now, NSString *who) {' $K && has 'if (MSBDTitleRecordHolds(rec != nil, rec && MSBDWinNear(now, rec[1].CGRectValue))) return rec[0];' \
   && fn 'static NSValue *DMTitleRecordHeldSM(NSString *key, CGRect now) {' $K && has 'if (MSBDTitleRecordHolds(rec != nil, rec && MSBDWinNear(now, rec[1].CGRectValue))) return rec[0];' \
   && fn 'static void DMTitleRecordView(UIView *v, CGRect now, CGRect to, CGRect fill) {' $K && has 'MSBDTitleRecordOnPlace(MSBDTitleKeepsFrames(gTitleDoubleTap), MSBDWinNear(to, fill), MSBDWinNear(now, fill));'"
check "P4-2: TitleBarTap.h's header says Fill and Zoom go back with their own frame from before (not Return to Previous Size's record)" \
  "! grep -qF \"Fill's way back is Return to\" $B && grep -qF 'Fill and Zoom go back with their own frame' $B"
exit $fails
