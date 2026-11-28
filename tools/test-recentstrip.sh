#!/bin/bash
# test-recentstrip.sh: the Recent Windows Strip (1.8.8.2 F29, KT 20 Nov: "it can be like on macos"; reworked in 1.8.8.4). Part 1: its rules
# (common/RecentStripRule.h: the list of the windows off the desktop by entry time, the slots, a swap, Minimize All's flights, when it shows, steps
# aside and is a drop target, the reveals and their ends, the place on every iPad size and Dock side with a slot open, the cover, the Home Screen's
# room and the desktop items' area, the drop zone, a card's press, size and drop frame, the handle, the keys, the motion's numbers, the pictures,
# a group's stack, the iPadOS) run on the Mac, see test-recentstrip.m. Part 2: site checks in SpringBoard's part (statusbar/RecentStrip.h),
# StatusBar.x, Settings and the crash map. Part 3: made-to-fail copies of the rules, each must be caught.
cd "$(dirname "$0")" || exit 1
TOOLS=$(pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
rc=0
R=../common/RecentStripRule.h; H=../statusbar/RecentStrip.h; S=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/MSBRootListController.m
PL=../statusbar/macstatusbarprefs/Resources/Windows.plist; O=../common/OwnPageRows.h; C=crashmap-rules.txt
[ -f "$R" ] && [ -f "$H" ] || { echo "FAIL  no recent windows strip: $R or $H is missing"; exit 1; }

echo "== the rules (test-recentstrip.m)"
clang -fobjc-arc -Wall -Werror -framework Foundation -o "$W/t" test-recentstrip.m || { echo "FAIL  test-recentstrip.m does not build"; exit 1; }
"$W/t" || rc=1

echo "== site checks"
ck() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; rc=1; fi; }
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
fn "$S" 'static void DMSyncWindowsForLibraryBody(void) {' > "$W/watcher"
fn "$H" '__attribute__((noinline)) static void DMRStripTick(void) {' > "$W/tick"
fn "$H" 'static BOOL DMRStripOn(void) {' > "$W/on"
fn "$S" 'static void DMMinimizeWindow(UIView *window) {' > "$W/minw"
fn "$S" 'static void DMMinimizeStage(UIView *stage) {' > "$W/mins"
fn "$S" 'static CGAffineTransform DMMinimizedTransform(UIView *window) {' > "$W/mint"
fn "$S" 'static void DMMinimizeAnimate(UIView *window, CGAffineTransform away, void (^done)(BOOL)) {' > "$W/mina"
fn "$S" 'static void DMRestoreAnimate(UIView *window) {' > "$W/resa"
fn "$S" 'static void DMMinimizeAllWindows(void) {' > "$W/minall"
fn "$S" 'static void DMSaveWindowState(void) {' > "$W/save"
fn "$H" 'static void DMRStripPick(DMRStripCard *card, BOOL shift, NSString *how) {' > "$W/pick"
fn "$H" 'static void DMRStripPicture(UIView *stage, NSString *k, NSString *why) {' > "$W/pic"
fn "$H" 'static BOOL DMRStripPictureAsync(UIView *v, double k, void (^done)(UIView *pic, double ms)) {' > "$W/async"
fn "$H" 'static void DMRStripSysHoverUpdate(BOOL want) {' > "$W/hover"
fn "$H" 'static UIView *DMRStripWindowHit(id self, SEL _cmd, CGPoint p, UIEvent *e) {' > "$W/hit"
fn "$H" '__attribute__((noinline)) static CGRect DMRStripFlightRect(UIView *window, BOOL *faded) {' > "$W/flight"
fn "$H" '__attribute__((noinline)) static void DMRStripWillMinimize(UIView *stage) {' > "$W/willmin"
fn "$H" 'static NSArray<NSString *> *DMRStripCollect(NSDictionary<NSString *, UIView *> **stageOfOut, BOOL *anyShownOut) {' > "$W/collect"
fn "$H" 'static BOOL DMRStripRelayout(BOOL animated) {' > "$W/relayout"
fn "$H" 'static void DMRStripGoneStep(CFTimeInterval now) {' > "$W/gone"
fn "$H" '__attribute__((noinline)) static NSArray<UIView *> *DMRStripBurstBegin(void) {' > "$W/burst"
fn "$H" '__attribute__((noinline)) static void DMRStripSwitchedOff(void) {' > "$W/off"
fn "$H" 'static DMRStripCard *DMRStripCardFor(NSString *k) {' > "$W/card"
fn "$H" 'static BOOL DMRStripCoveredNow(BOOL laid) {' > "$W/cover"
fn "$H" '__attribute__((noinline)) static BOOL DMRStripWindowDrag(UIView *win, UIGestureRecognizer *g, UIGestureRecognizerState state) {' > "$W/drag"
fn "$H" 'static uint64_t DMRStripRestSig(void) {' > "$W/sig"
fn "$H" 'static MSBDRStripShow DMRStripApplyShow(BOOL laid, BOOL covered, NSString *why) {' > "$W/apply"
fn "$H" 'static void DMRStripLiftTo(DMRStripCard *c) {' > "$W/lift"
fn "$H" 'static void DMRStripTurnIn(void) {' > "$W/turn"
fn "$H" 'static void DMRStripShowAs(MSBDRStripShow show, NSString *why) {' > "$W/show"
ck "the strip's step rides the 0.2 s window watcher, right after the window cards' (no timer of its own)" \
   "grep -A1 -F 'DM_PERF(\"wincards\", DMWinCardsTick());' \"$W/watcher\" | grep -qF 'DM_PERF(\"rstrip\", DMRStripTick());'"
ck "  ... and returns at once while it is off, or while no window (an engine's or ours) and no kept card exists (letting go of the windows it looked at)" \
   "head -6 \"$W/tick\" | grep -qF 'if (!DMRStripOn()) {' && grep -qF 'if (!DMWindowWorkNeeded() && !gRStripGhosts.count && !gRStripGone.count && !gNativeWindows.count) { gRStripStageOf = nil; DMRStripShowAs(MSBDRStripHidden, @\"no window\"); DMRStripSysHoverUpdate(NO); return; }' \"$W/tick\""
ck "no timer, display link, timed dispatch or poll in the strip (no new polling)" \
   "! grep -nE 'NSTimer|CADisplayLink|dispatch_source_create|dispatch_after|afterDelay|globalPointerPosition|BKSMousePointerService' $H $R"
ck "no portal: still pictures only (a portal has the server draw the window in every frame)" "! grep -nE '_UIPortalView|DMMSWPortal' $H"
ck "it runs for Aerial, Zetsu and MilkyWay4 only, on the rules' iPadOS, with the pictures that need no waiting" \
   "grep -qF 'if (e != DMEngineAerial && e != DMEngineZetsu && e != DMEngineMilkyWay) return NO;' \"$W/on\" && grep -qF 'os = MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion) ? 1 : 0;' \"$W/on\" \
    && grep -qF 'return os && DMMSWAsyncPicturesOK();' \"$W/on\" && grep -qF 'if (!gRStripPref || gStockBar) return NO;' \"$W/on\""
ck "the list is the rules': this desktop's windows our minimize hid (MSBDRStripIsOff), by their entry times, a window with none seeded, the kept cards with theirs" \
   "grep -qF 'return st && MSBDRStripIsOff(DMRStripHiddenByUs(st) || DMRStripBurstPending(st), [objc_getAssociatedObject(st, kStageClosingKey) boolValue],' $H \
    && grep -qF 'if (!DMRStripOffDesktop(st) || gRStripLeaving[k] || [k isEqualToString:gRStripDraggingKey ?: @\"\"]) continue;' \"$W/collect\" && grep -qF 't = MSBDRStripEntryAt(MSBDRStripWhySeeded, DMRStripClock(), NAN, seed);' \"$W/collect\" \
    && grep -qF 'return MSBDRStripList(off, at);' \"$W/collect\" && grep -qF 'for (UIView *st in [stages reverseObjectEnumerator]) {' \"$W/collect\" && grep -qF 'NSArray<UIView *> *stages = DMAerialStages();' \"$W/collect\" \
    && ! grep -qE 'MSBDRStripOrderStep|gRStripOrder' $H $R"
ck "  ... our minimize's mark of each engine: kStageHiddenKey (Aerial, Zetsu), MilkyWay4's own (DMWindowMinimized); the entry time from the clock since 2001 (a respring keeps it)" \
   "fn $H 'static BOOL DMRStripHiddenByUs(UIView *st) {' > \"$W/hid\" && grep -qF 'if (mw && [st isKindOfClass:mw]) return DMWindowMinimized(st);' \"$W/hid\" && grep -qF 'return [objc_getAssociatedObject(st, kStageHiddenKey) boolValue];' \"$W/hid\" \
    && grep -qF 'static double DMRStripClock(void) { return CFAbsoluteTimeGetCurrent(); }' $H"
ck "every minimize asks the strip first (DMMinimizedTransform: the slot it flies into, before the Dock icon, also with Reduce Motion), every way back too (DMRestoreAnimate's start)" \
   "sed -n 2p \"$W/mint\" | grep -qF '(the Recent Windows Strip first' && grep -qF 'CGRect strip = DMRStripFlightRect(window, NULL);' \"$W/mint\" \
    && [ \"\$(grep -n 'CGRect strip = DMRStripFlightRect(window, NULL);' \"$W/mint\" | cut -d: -f1)\" -lt \"\$(grep -n 'if (MSBReduceMotion()) return' \"$W/mint\" | cut -d: -f1)\" ] \
    && grep -qF 'CGRect target = CGRectIsNull(strip) ? DMDockTargetFor(DMStageBundle(window), &what) : strip;' \"$W/mint\" && grep -qF 'CGAffineTransform from = DMMinimizedTransform(window);' \"$W/resa\" \
    && [ \"\$(grep -c 'DMMinimizedTransform(' $S)\" = 4 ]"
ck "  ... into it only as the rules say (the switch on, calm, the windows in front, and a desktop or a Home Screen band to show it on), at the slot of the list, past the cap the last one" \
   "grep -qF 'if (!laid || !MSBDRStripFliesIn(YES, gRStripCalmNow, gRStripFrontNow) || (!gRStripAnyShown && !gRStripHomeBand)) {' \"$W/flight\" && grep -qF 'int at = MSBDRStripFlightSlot(slot, gRStripFit, &past);' \"$W/flight\" \
    && grep -qF 'NSUInteger slot = [gRStripList indexOfObject:k];' \"$W/flight\" && grep -qF 'if (!past) DMRStripCardLanding(c, delay);' \"$W/flight\""
ck "  ... out of its card as the rules say (on screen, landed), the card going into the window's flight, its entry cleared, the gap closed" \
   "grep -qF 'if (!r && MSBDRStripGrowsOut(c && c.superview && !c.going, gRStripShown != MSBDRStripHidden, c.landing)) r = [NSValue valueWithCGRect:DMRStripCardScreenRect(c)];' \"$W/flight\" \
    && grep -qF 'DMRStripCardGoes(k, r != nil);' \"$W/flight\" && grep -qF 'DMRStripClearEntry(window);' \"$W/flight\""
ck "  ... a strip stepped aside comes out for the landing (the Flight reveal) and steps aside again by the rules' time" \
   "grep -qF 'gRStripReveal = MSBDRStripRevealFlight;' \"$W/flight\" && grep -qF 'if (gRStripReveal && MSBDRStripRevealEnds(gRStripReveal, now - gRStripTouchedAt, gRStripPointerOutAt > 0 ? now - gRStripPointerOutAt : 0, DMRStripAssistive()))' \"$W/tick\""
ck "before every minimize of ours its entry (a swap's, a burst's or a respring's set before, else now) and its picture (the rules'), before its flag (all three engines)" \
   "grep -B1 -F 'objc_setAssociatedObject(window, kMinimizedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/minw\" | grep -qF 'DMRStripWillMinimize(window);' \
    && grep -B1 -F 'objc_setAssociatedObject(stage, kStageHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/mins\" | grep -qF 'DMRStripWillMinimize(stage);' \
    && grep -qF 'DMRStripSetEntry(stage, at, why);' \"$W/willmin\" && grep -qF 'if (!MSBDRStripPicAtEntry(gRStripPics[k] != nil, t ? CACurrentMediaTime() - t.doubleValue : 1e9, burst, !burst || [k isEqualToString:gRStripBurstFront ?: @\"\"])) return;' \"$W/willmin\""
ck "  ... and its card shown where its flight landed (after its window is hidden), on both minimizes" \
   "grep -A1 -F 'DMApplyWindowLevel();' \"$W/minw\" | grep -qF 'DMRStripLanded(window);' && grep -A1 -F 'DMApplyWindowLevel();' \"$W/mins\" | grep -qF 'DMRStripLanded(stage);'"
ck "Minimize All and Home: every window's slot set first (the rules' times, the one in front newest), each flight 30 ms after the one before, the burst ended on every way out" \
   "grep -qF 'NSArray<UIView *> *burst = DMRStripBurstBegin();' \"$W/minall\" && [ \"\$(grep -c 'DMRStripBurstEnd(burst);' \"$W/minall\")\" = 2 ] \
    && grep -B1 -F 'return;' \"$W/minall\" | grep -qF 'DMRStripBurstEnd(burst);' \
    && grep -qF '@[@(MSBDRStripBurstAt(now, (int)i)), @(MSBDRStripWhyMinimized)]' \"$W/burst\" && grep -qF '@(MSBDRStripBurstDelay((int)i))' \"$W/burst\" \
    && grep -qF 'double delay = DMRStripFlightDelay(window);' \"$W/mina\" && grep -qF 'animateKeyframesWithDuration:0.36 delay:delay options:' \"$W/mina\""
ck "a pick is taken by the rules (settled, one at a time), the window in front read before the picked one comes back, the swap by the rules, the front one into the card's slot (its time)" \
   "grep -qF 'if (!MSBDRStripPickTakes(now, card.settledAt, gRStripLastPickAt))' \"$W/pick\" && grep -qF 'BOOL swaps = MSBDRStripPickSwaps(YES, shift, front != nil, frontJoins, front == st);' \"$W/pick\" \
    && [ \"\$(grep -n 'UIView \*front = DMRStripFrontWindow(&ours);' \"$W/pick\" | cut -d: -f1)\" -lt \"\$(grep -n 'if (!DMSurfaceWindowForApp(k)) DMRaiseStageForBundle(k);' \"$W/pick\" | cut -d: -f1)\" ] \
    && [ \"\$(grep -n 'if (!DMSurfaceWindowForApp(k)) DMRaiseStageForBundle(k);' \"$W/pick\" | cut -d: -f1)\" -lt \"\$(grep -n 'DMRStripMinimizeNow(front);' \"$W/pick\" | cut -d: -f1)\" ] \
    && grep -qF '@[@(MSBDRStripEntryAt(MSBDRStripWhySwapped, DMRStripClock(), pickedAt, 0)), @(MSBDRStripWhySwapped)]' \"$W/pick\" && grep -qF 'gRStripLeaving[k] = [NSValue valueWithCGRect:DMRStripCardScreenRect(card)];' \"$W/pick\""
ck "  ... the window in front is the focused one (Command-M's; our own window focused: that one), none with the windows behind a full-screen app; Shift: only back" \
   "fn $H 'static UIView *DMRStripFrontWindow(BOOL *ours) {' > \"$W/front\" && grep -qF 'if (!DMWindowsInFront()) return nil;' \"$W/front\" && grep -qF 'DMNativeWindow *nw = DMNativeActiveApp();' \"$W/front\" \
    && grep -qF 'return DMKeepCoveredActive(stageEngine ? DMTopStage() : DMTopWindow());' \"$W/front\" && grep -qF 'BOOL shift = (g.mods & UIKeyModifierShift) != 0;' $H"
ck "  ... a kept card's app opens again at its place, MilkyWay4's grey window closed first; one card touched at a time" \
   "grep -qF 'DMRStripRelaunchNow(k, [kept[@\"place\"] CGRectValue]);' \"$W/pick\" && grep -qF 'DMMSWMWCloseGone(st);' \"$W/pick\" && grep -qF 'c.exclusiveTouch = YES;' \"$W/card\""
ck "a waiting window whose window went: decided by the rules a moment later with SpringBoard's exit notes (iPadOS's end: kept; the user's quit, a crash: gone)" \
   "grep -qF 'BOOL quit = [gAppsEndedByQuit containsObject:k], crashed = [gAppsEndedInCrash containsObject:k];' \"$W/gone\" \
    && grep -qF 'MSBDRStripGone step = MSBDRStripGoneStep(since, [gAppsQuitting containsObject:k], quit, crashed, back);' \"$W/gone\" && grep -qF 'if ([anywhere containsObject:k]) continue;' \"$W/gone\""
ck "the switch off: the swapped and dragged windows come back (the rules'), the minimized ones stay, every entry goes; read before the new value is taken" \
   "grep -qF 'if (!DMRStripEntryOf(st, &at, &why) || !DMRStripOffDesktop(st) || !MSBDRStripBackAtOff(why)) continue;' \"$W/off\" && grep -qF 'for (UIView *st in DMAerialStagesAll()) DMRStripClearEntry(st);' \"$W/off\" \
    && grep -A1 -F 'if (gRStripPref && !recentStrip) DMRStripSwitchedOff();' $S | grep -qF 'gRStripPref = recentStrip;'"
ck "the order kept across a respring: a minimized window's entry in the windows' state file, given back before the restore minimizes it again" \
   "grep -qF 'NSDictionary *strip = minimized ? DMRStripSavedEntry(st) : nil;' \"$W/save\" && grep -A1 -F 'if (minimizedAgain) DMRStripRestoreEntry(stage, w);' $S | grep -qF 'if (minimizedAgain) { Class mwc = objc_getClass(\"AXWindowView\");' \
    && fn $H '__attribute__((noinline)) static void DMRStripRestoreEntry(UIView *st, NSDictionary *saved) {' | grep -qF 'MSBDRStripSavedEntry(saved[@\"stripAt\"], saved[@\"stripWhy\"], &at, &why)' \
    && fn $H '__attribute__((noinline)) static NSDictionary *DMRStripSavedEntry(UIView *st) {' | grep -qF 'if (!DMRStripOn() || !DMRStripEntryOf(st, &at, &why) || !isfinite(at)) return nil;'"
ck "every strip function another part's code calls keeps its own frame (out of line: a crash in it is the strip's)" \
   "( for f in DMRStripTick DMRStripWillMinimize DMRStripFlightRect DMRStripFlightDelay DMRStripLanded DMRStripBurstBegin DMRStripBurstEnd DMRStripSwitchedOff DMRStripSavedEntry DMRStripRestoreEntry DMRStripMenuOffered DMRStripMenuReveal DMRStripMoveOffered DMRStripTrigger \
             DMRStripWindowDrag DMRStripTouchOnScreen DMRStripHomeBandStep DMRStripHomeAreaBeside DMRStripHomeBandOn DMRStripKeys DMRStripNativeFlight DMRStripNativeLanded; do \
      grep -qE \"^__attribute__\\(\\(noinline\\)\\) static [^(]*\\b\$f\\(\" $H || exit 1; done )"
ck "when it shows is the rules' answer, the reveal's too, one step for the tick, a drag and a flight (a drop target in it; a card dragged out counts, 1.8.8.4 fix round)" "grep -qF 'MSBDRStripShow show = MSBDRStripShowFor(s);' \"$W/apply\" && grep -qF 'gRStripMayRevealNow = MSBDRStripMayReveal(s);' \"$W/apply\" \
   && grep -qF 'MSBDRStripState s = { 1, laid ? (int)gRStripItems.count + (DMRStripDragHolds() ? 1 : 0) : 0, gRStripCalmNow, gRStripFrontNow, gRStripAnyShown, covered, gRStripReveal != 0, gRStripHomeBand, gRStripDropTarget };' \"$W/apply\" \
   && grep -qF 'MSBDRStripShow show = DMRStripApplyShow(laid, covered, nil);' \"$W/tick\""
ck "nothing laid out or measured while it cannot show (nothing in it and no card dragged out, something over the windows, the windows behind a full-screen app)" \
   "grep -qF 'gRStripCalmNow = (gRStripList.count || gRStripDropTarget || DMRStripDragHolds()) && DMRStripCalm();' \"$W/relayout\" && grep -qF 'if (!gRStripCalmNow || !gRStripFrontNow) {' \"$W/relayout\" && grep -qF 'if (covered || !laid) break;' \"$W/cover\" \
    && grep -qF 'BOOL covered = DMRStripCoveredNow(laid);' \"$W/tick\""
ck "  ... the windows in front as DMWindowsInFront reads them, a full-screen app behind them covers the edge, every window as drawn and Finder's are tested against the cards" \
   "grep -qF 'gRStripFrontNow = gRStripCalmNow && DMDesiredWindowLevel() > 10.0;' \"$W/relayout\" && grep -qF 'BOOL covered = laid && DMFrontApp() != nil && DMFullScreenAppInFront();' \"$W/cover\" \
    && grep -qF 'CGRect w = DMSnapWindowOf(st);' \"$W/cover\" && grep -qF 'if (!CGRectIsNull(w) && MSBDRStripCovers(gRStripSpan, DMRStripRectOf(w))) covered = YES;' \"$W/cover\" && grep -qF 'for (DMNativeWindow *nw in gNativeWindows)' \"$W/cover\" \
    && grep -qF 'MSBDRStripState s = { 1, (int)gRStripItems.count, gRStripCalmNow, gRStripFrontNow, gRStripAnyShown, DMRStripCoveredNow(YES), gRStripReveal != 0, gRStripHomeBand, 0 };' \"$W/flight\""
ck "  ... calm: no App Switcher, Mac Switcher, lock, App Library, folder or icon menu fade, Dock menu, keyboard, Guided Access, Spotlight, Notification Center" \
   "fn $H 'static BOOL DMRStripCalm(void) {' > \"$W/calm\" && grep -qF 'if (!DMScreenOnAndUnlocked() || DMSwitcherVisible() || gMSWOpen || gMSWClosing || !DMMSWSessionIdle()) return NO;' \"$W/calm\" \
    && grep -qF 'if (gWindowsHiddenForLibrary || gHomeMenuOpen || gDockMenuOpen || gSoftKeyboardH >= 100.0) return NO;' \"$W/calm\" \
    && grep -qF 'if (MSBDGuidedAccessActive() || DMLibraryVisible() || DMSpotlightShown() || DMCoverSheetShown()) return NO;' \"$W/calm\""
ck "the place, the count and the side are the rules' (a slot open among the cards for a drop target)" "grep -qF 'n = MSBDRStripLayoutGap(sc.width, sc.height, usable, gRStripRight, n, aspect, gRStripGapAt, &gRStripBand, cards, &gapRect);' $H \
   && grep -qF 'gRStripRight = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);' \"$W/relayout\" && grep -qF 'gRStripFit = MSBDRStripFit(sc.width, sc.height, usable);' \"$W/relayout\" \
   && grep -qF 'NSArray<NSString *> *items = MSBDRStripShown(gRStripList, (NSUInteger)gRStripFit);' \"$W/relayout\" \
   && grep -qF 'MSBDRRect usable = DMRStripRectOf(u);' \"$W/relayout\" && grep -qF '{ u = DMUsableArea(); uFor = sc; uDock = gDMDockGen; uPlace = gDMDockPlaceGen; uAt = now; }' \"$W/relayout\""
ck "its window just above the windows' level, and only a card that is there takes a touch (stepped aside, the handle's touch area alone)" \
   "grep -qF 'CGFloat level = DMDesiredWindowLevel() + 0.5;' \"$W/show\" && grep -qF 'CGFloat level = DMDesiredWindowLevel() + 0.5;' \"$W/tick\" && grep -qF 'class_addMethod(sub, @selector(hitTest:withEvent:), (IMP)DMRStripWindowHit, \"@@:{CGPoint=dd}@\");' $H \
    && grep -qF 'if ([c pointInside:q withEvent:e]) return c;' \"$W/hit\" && grep -qF 'if (c.hidden || c.alpha < 0.05 || !c.superview || c.going || c.landing) continue;' \"$W/hit\" && [ \"\$(grep -c 'return' \"$W/hit\")\" = 4 ]"
ck "a window's drag over it, at every engine's drag and our own windows': Zetsu's title bar, MilkyWay4's, Aerial's (3.0 and 5.0 through DMAerialGestureAfter, 5.x -dragTrace:, 5.1 -areaDrag:), -dm_move:" \
   "awk '/^@implementation DMZetsuBarPan/,/^@end/' $S > \"$W/zbar\" && grep -qF 'DMRStripWindowDrag(w, g, g.state);   // (the Recent Windows Strip, 1.8.8.4: a drag begins)' \"$W/zbar\" \
    && grep -qF 'BOOL toStrip = DMRStripWindowDrag(w, g, g.state);' \"$W/zbar\" && grep -A3 -F 'BOOL toStrip = DMRStripWindowDrag(w, g, g.state);' \"$W/zbar\" | grep -qF 'objc_setAssociatedObject(w, kStageGestureKey, nil' \
    && grep -A1 -F 'if (toStrip) { DMZetsuFixScale(w); return; }' \"$W/zbar\" | grep -qF 'if (g.state == UIGestureRecognizerStateEnded) DMSnapMoveEnded(w);' \
    && fn $S '- (void)dragged:(UIPanGestureRecognizer *)g {' | grep -A1 -F 'if (DMRStripWindowDrag(win, g, g.state)) return;' | grep -qF 'if (g.state == UIGestureRecognizerStateEnded) DMSnapMoveEnded(win);' \
    && fn $S 'static void DMAerialGestureAfter(UIView *stage, UIGestureRecognizer *g, BOOL wasPan) {' > \"$W/aga\" && grep -qF 'BOOL toStrip = wasPan && [objc_getAssociatedObject(g, kAerialHandStartKey) boolValue] && DMRStripWindowDrag(stage, g, s);' \"$W/aga\" \
    && grep -A1 -F 'objc_setAssociatedObject(stage, kStageGestureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/aga\" | grep -qF 'if (toStrip) return;' \
    && fn $S '- (void)dragTrace:(UIPanGestureRecognizer *)g {' | grep -A3 -F 'if (DMRStripWindowDrag(stage, g, st)) return;' | grep -qF 'if (g.state == UIGestureRecognizerStateEnded && stage.superview) DMSnapMoveEnded(stage);' \
    && fn $S '- (void)areaDrag:(UIPanGestureRecognizer *)g {' > \"$W/area\" && grep -qF 'DMRStripWindowDrag(stage, g, g.state); return; }   // (as -dragTrace:)' \"$W/area\" \
    && grep -A1 -F 'if (DMRStripWindowDrag(stage, g, g.state)) return;' \"$W/area\" | grep -qF 'if (g.state == UIGestureRecognizerStateCancelled) DMTitleRecordHandEnded(stage, g.state);' \
    && fn ../statusbar/NativeWindow.h '- (void)dm_move:(UIPanGestureRecognizer *)g {' | grep -qF 'if (DMRStripWindowDrag(self, g, g.state)) return;' \
    && [ \"\$(grep -c 'DMRStripWindowDrag(' $S)\" = 8 ] && ! grep -q 'DMRStripTouchOnScreen' $S ../statusbar/NativeWindow.h"
ck "  ... never for a window in Aerial's Lock: in -dragTrace: and -areaDrag: the lock check comes before the strip's first call (else a locked drag steps the cards aside or opens the slot, and its end, stopped by the lock, never closes it)" \
   "( for h in '- (void)dragTrace:(UIPanGestureRecognizer *)g {' '- (void)areaDrag:(UIPanGestureRecognizer *)g {'; do fn $S \"\$h\" > \"$W/lk\"; \
      l=\$(grep -nF 'if (DMAerialLockedDrag(stage, g)) return;' \"$W/lk\" | head -1 | cut -d: -f1); r=\$(grep -nF 'DMRStripWindowDrag(' \"$W/lk\" | head -1 | cut -d: -f1); \
      [ -n \"\$l\" ] && [ -n \"\$r\" ] && [ \"\$l\" -lt \"\$r\" ] || exit 1; done )"
ck "  ... one test per move with the switch off; the drop zone and the drop are the rules'; the window itself is never moved or turned by the strip during the drag" \
   "sed -n 2p \"$W/drag\" | grep -qF 'if (!gRStripPref || !win || !DMRStripOn()) return NO;' && sed -n 3p \"$W/drag\" | grep -qF 'CGPoint p = DMRStripTouchOnScreen(g);' && grep -qF 'BOOL inZone = joins && isfinite(p.x) && isfinite(p.y) && MSBDRStripInDropZone(p.x, p.y, gRStripDragBand, gRStripDragRight);' \"$W/drag\" \
    && grep -qF 'BOOL take = state == UIGestureRecognizerStateEnded && MSBDRStripDropTakes(inZone, DMRStripCalm() && DMDesiredWindowLevel() > 10.0, joins);' \"$W/drag\" \
    && ! grep -qE 'win\.(transform|frame|center|bounds|alpha|hidden) *=' \"$W/drag\" && grep -qF 'if (covers != gRStripDragCovers)' \"$W/drag\""
ck "  ... let go there: the window goes in by our minimize (the drag's entry), and back to its frame from before the drag once hidden, by the engine's own setter" \
   "grep -qF 'objc_setAssociatedObject(win, kRStripPendingKey, @[@(DMRStripClock()), @(MSBDRStripWhyDragged)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/drag\" \
    && grep -qF 'objc_setAssociatedObject(win, kRStripReturnKey, [NSValue valueWithCGRect:gRStripDragFrom], OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/drag\" && grep -qF 'DMRStripMinimizeNow(win);' \"$W/drag\" \
    && fn $H '__attribute__((noinline)) static void DMRStripLanded(UIView *window) {' | grep -qF 'DMRStripPutBack(window, back.CGRectValue);' \
    && fn $H 'static void DMRStripPutBack(UIView *st, CGRect f) {' > \"$W/putback\" && grep -qF '!DMRStripHiddenByUs(st)) return;' \"$W/putback\" && grep -qF 'if (DMActiveEngine() == DMEngineAerial) DMAerial5SyncState(st, f);' \"$W/putback\" \
    && grep -qF '[UIView performWithoutAnimation:^{ DMSetStageFrameSafe(st, f); [st layoutIfNeeded]; }];' \"$W/putback\" && grep -qF 'DMSetStageIntent(st, f);' \"$W/putback\""
ck "  ... at its edge it comes out over the windows with a slot open at the top and the band's highlight (light or dark, solid for Reduce Transparency and Increase Contrast), also with no card" \
   "fn $H 'static void DMRStripSetDropTarget(BOOL on) {' > \"$W/target\" && grep -qF 'gRStripDropTarget = on; gRStripGapAt = on ? 0 : -1;' \"$W/target\" \
    && grep -qF 'solid = UIAccessibilityIsReduceTransparencyEnabled() || UIAccessibilityDarkerSystemColorsEnabled();' \"$W/target\" && grep -qF 'gRStripCalmNow = (gRStripList.count || gRStripDropTarget || DMRStripDragHolds()) && DMRStripCalm();' \"$W/relayout\" \
    && grep -qF 'return gRStripItems.count > 0 || gRStripDropTarget || DMRStripDragHolds();' \"$W/relayout\""
ck "nothing at rest: the step returns after its signature while nothing it reads changed and nothing time-bound waits, before any look or allocation of its own" \
   "grep -qF 'if (!MSBDRStripTickWorks(sig != lastSig, timed)) return;' \"$W/tick\" \
    && [ \"\$(grep -n 'if (!MSBDRStripTickWorks(sig != lastSig, timed)) return;' \"$W/tick\" | cut -d: -f1)\" -lt \"\$(grep -n 'BOOL laid = DMRStripRelayout(' \"$W/tick\" | cut -d: -f1)\" ] \
    && [ \"\$(grep -n 'if (!MSBDRStripTickWorks(sig != lastSig, timed)) return;' \"$W/tick\" | cut -d: -f1)\" -lt \"\$(grep -n 'gRStripWorkTicks++;' \"$W/tick\" | cut -d: -f1)\" ] \
    && ! grep -qE 'alloc\]|arrayWith|dictionaryWith|stringWith|@\[|@\{|copy\]' \"$W/sig\" && grep -qF 'h = MSBDRStripSigMix(h, (uint64_t)(uintptr_t)(__bridge void *)st);' \"$W/sig\" \
    && grep -qF 'ticks %u, work ticks %u, layouts %u, pictures taken %u' $H"
ck "the hover lift and tilt, the press, the settle are the rules' numbers, by springs; Increase Contrast gives the cards an outline" \
   "grep -qF 't = CATransform3DMakeScale(kMSBDRStripPressScale, kMSBDRStripPressScale, 1);' \"$W/lift\" && grep -qF 't = CATransform3DTranslate(t, 0, -kMSBDRStripHoverLift, 0);' \"$W/lift\" \
    && grep -qF 'kMSBDRStripHoverTilt * M_PI / 180.0, 0, 1, 0);' \"$W/lift\" && grep -qF 't = CATransform3DScale(t, kMSBDRStripHoverScale, kMSBDRStripHoverScale, 1);' \"$W/lift\" \
    && grep -qF 'CGFloat want = up ? kMSBDRStripHoverShadow : kMSBDRStripShadow;' \"$W/lift\" && grep -qF 'MSBAnimate(kMSBDRStripHoverTime, 0, kMSBDRStripHoverDamp,' \"$W/lift\" \
    && grep -qF 'self.pressed = YES; self.fingerDown = touches.anyObject.type != UITouchTypeIndirectPointer' $H && grep -qF 'BOOL hc = UIAccessibilityDarkerSystemColorsEnabled();' $H"
fn "$H" '__attribute__((noinline)) static void DMRStripHomeBandStep(void) {' > "$W/band"
ck "the Home Screen keeps the band while the switch is on (the rules' width and side), handed on once per change: to the Dock part's page frames, or with the Dock part not loaded our own same hook, never both; off with no band handed on, the step reads and hands nothing (every iPadOS)" \
   "grep -qF 'double room = MSBDRStripHomeRoom(on, sc.width, sc.height);' \"$W/band\" && grep -qF 'BOOL right = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);' \"$W/band\" \
    && grep -qF 'dockRoom = (int (*)(double, int))dlsym(RTLD_DEFAULT, \"MSBDHomeStripRoom\");' \"$W/band\" && grep -qF 'if (dockRoom) kept = dockRoom(room, right) != 0;' \"$W/band\" \
    && grep -qF 'else if (room > 0.0 ? DMRStripTwinHook() : gRStripTwinHooked) {' \"$W/band\" && sed -n 2p \"$W/band\" | grep -qF 'BOOL on = DMRStripOn();' \
    && sed -n 4p \"$W/band\" | grep -qF 'if (MSBDRStripBandIdle(on, handed)) return;' && grep -qF 'static double handed = 0.0;' \"$W/band\" \
    && grep -qF 'if (!MSBDRStripBandHandsOn(room, handed, right, handedRight)) return;' \"$W/band\" \
    && grep -A1 -F 'gRStripTicks++;' \"$W/tick\" | grep -qF 'DMRStripHomeBandStep();' && grep -qF 'gRStripHomeBand = kept && room > 0.0;' \"$W/band\""
ck "  ... our own hook only of the exact type, the band alone (the two-sided rule with no Dock room), Edit Home Screen's buttons off it, the iPad's screen only" \
   "fn $H 'static BOOL DMRStripTwinHook(void) {' > \"$W/twin\" && grep -qF 'MSHookMessageEx(rv, lfs, (IMP)DMRStripTwinListFrame, &gRStripTwinListFrameOrig);' \"$W/twin\" \
    && grep -B4 -F 'MSHookMessageEx(rv, lfs, (IMP)DMRStripTwinListFrame, &gRStripTwinListFrameOrig);' \"$W/twin\" | grep -qF 'if (!lf || strcmp(method_getTypeEncoding(lf) ?: \"\", \"{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16Q48\")) {' \
    && grep -qF 'return MSBDHomeListFrameTwoSided(f, MSBDDockBottom, 0.0, gRStripHomeRight, gRStripHomeRoom, fl, fr);' $H \
    && grep -qF '[(UIView *)self window].screen != [UIScreen mainScreen])) return f;' $H && grep -qF 'if (band && !gRStripHomeRight && CGRectGetMinX(f) < gRStripHomeRoom) f.origin.x += gRStripHomeRoom;' $H"
ck "review 1.8.8.4: our own hook gives Edit Home Screen's buttons back their own place when the band goes (SpringBoard's frame kept, as the Dock part's), never moving one twice" \
   "fn $H 'static void DMRStripTwinLayout(id self, SEL _cmd) {' > \"$W/twinlay\" && ! grep -qF 'if (!(gRStripHomeRoom > 0.0)) return;' \"$W/twinlay\" \
    && grep -qF 'if (!band && !set) continue;   // (never moved by us: nothing to give back)' \"$W/twinlay\" \
    && grep -qF 'CGRect apple = set && base && CGRectEqualToRect(v.frame, set.CGRectValue) ? base.CGRectValue : v.frame;' \"$W/twinlay\" \
    && grep -qF 'objc_setAssociatedObject(v, kRStripTwinButtonBase, [NSValue valueWithCGRect:apple], OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \"$W/twinlay\""
ck "  ... the Dock part: one export, its page frames two-sided (no band: the side Dock's own frame, test-dockside), its Home Screen hooks installed once for either, Edit Home Screen's buttons off the band" \
   "D=../dock/Dock.x; grep -qF '__attribute__((visibility(\"default\"))) int MSBDHomeStripRoom(double room, int right) {' \$D \
    && grep -qF 'return MSBDHomeListFrameTwoSided(f, side, side ? gDockSideHomeRoom : 0.0, MSBDHomeStripOnRight(gDockPosition, f.size.width, f.size.height), gHomeStripRoom, fl, fr);' \$D \
    && [ \"\$(grep -c '%init(DockSideHomeLists)' \$D)\" = 1 ] && [ \"\$(grep -c 'DMDockSideHomeHook();' \$D)\" = 2 ] \
    && grep -qF 'if (gHomeStripRoom > 0.0 && !stripRight && CGRectGetMinX(f) < gHomeStripRoom) f.origin.x += gHomeStripRoom;' \$D \
    && grep -qF 'if (room > 0.0 && !gDMInCtor) DMDockSideHomeHook();' \$D"
ck "  ... the desktop's files and sticky notes shown beside the band (the rules' area), their saved places shares of the area without it (never rewritten by it)" \
   "grep -qF -e '- (CGRect)dm_area { return DMRStripHomeAreaBeside([self dm_areaBeforeStrip]); }' ../statusbar/Desktop.h \
    && fn ../statusbar/Desktop.h '- (CGRect)dm_placesArea:(CGRect)a {' | sed -n 2p | grep -qF 'if (DMRStripHomeBandOn()) a = [self dm_areaBeforeStrip];' \
    && grep -qF 'return DMRStripCGRect(MSBDRStripAreaBeside(DMRStripRectOf(area), band, right));' $H && grep -qF 'if (gDesktop) [gDesktop dm_placeAgain];' \"$W/band\""
ck "review 1.8.8.4: with the Dock at Left a turn lays the Home Screen out once: the pages, Edit Home Screen's buttons and the desktop's files take the band's side from their own shape (DockSide.h MSBDHomeStripOnRight, the strip's own rule); a new side alone places nothing again" \
   "D=../dock/Dock.x; grep -qF 'BOOL stripRight = MSBDHomeStripOnRight(gDockPosition, b.width, b.height);' \$D && ! grep -q 'gHomeStripRight' \$D \
    && grep -qF 'if (fabs(room - gHomeStripRoom) < 0.25) return gDockSideHomeHooked && room > 0.0;' \$D \
    && fn $H '__attribute__((noinline)) static CGRect DMRStripHomeAreaBeside(CGRect area) {' | grep -qF 'BOOL right = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);' \
    && grep -qF 'static inline bool MSBDHomeStripOnRight(int position, double width, double height) { return MSBDDockSideFor(position, width, height) == MSBDDockLeft; }' ../common/DockSide.h \
    && grep -qF 'static inline BOOL MSBDRStripOnRight(BOOL dockAtLeft) { return dockAtLeft; }' $R"
ck "  ... the Today View at the strip's side keeps it off (the rules'), SpringBoard asked only where it answers with a BOOL" \
   "grep -qF 'if (MSBDRStripTodayKeepsOff(!gRStripRight && DMRStripTodayShown(), gRStripRight)) return NO;' $H \
    && fn $H 'static BOOL DMRStripBoolGetter(Class c, SEL s) {' | grep -qF 'return t && (t[0] == '\\''B'\\'' || t[0] == '\\''c'\\'') && !strcmp(t + 1, \"16@0:8\");' \
    && fn $H 'static BOOL DMRStripTodayShown(void) {' | grep -qF 'if (mgr && object_getClass(mgr) != mc) { mc = object_getClass(mgr); for (int i = 0; i < 2; i++) mok[i] = DMRStripBoolGetter(mc, ms[i]); }'"
ck "  ... a crash in the strip's one call into the Dock part is the strip's (the crash map)" "grep -qxF 'sym DockMagnification ^_*MSBDHomeStripRoom\$ recentStrip' $C"
fn "$H" 'static void DMRStripPressed(DMRStripPress *g) {' > "$W/pressed"
fn "$H" 'static void DMRStripCardDragEnd(DMRStripPress *g) {' > "$W/dragend"
ck "a card's press: one recognizer for a finger and a pointer (no tap recognizer), the rules' tap, menu on a held finger's release, a drag after any hold; a secondary click, two fingers or Control: the menu" \
   "grep -qF 'DMRStripPress *press = [[DMRStripPress alloc] initWithTarget:t action:@selector(press:)];' \"$W/card\" && grep -qF 'press.cancelsTouchesInView = NO;' \"$W/card\" && ! grep -q 'UITapGestureRecognizer' \"$W/card\" \
    && grep -qF 'if (!g.secondary && MSBDRStripPressFor(held, moved, NO, g.pointer) == MSBDRStripPressDrag)' \"$W/pressed\" && grep -qF 'MSBDRStripPress kind = MSBDRStripPressFor(held, moved, YES, g.pointer);' \"$W/pressed\" \
    && grep -qF 'if (g.secondary || (g.mods & UIKeyModifierControl)) kind = MSBDRStripPressMenu;' \"$W/pressed\" && grep -qF 'self.secondary = (event.buttonMask & UIEventButtonMaskSecondary) != 0;' $H \
    && grep -qF 'self.pointer = t.type == UITouchTypeIndirectPointer;' $H \
    && grep -qF '[UIView addKeyframeWithRelativeStartTime:kMSBDRStripHold / total relativeDuration:kMSBDRStripHoldRise / total animations:^{ c.lift.transform3D = ready; }];' \"$W/lift\""
ck "  ... a drag out: the proxy (our own view, the card's picture) follows by the rules' size and grab point; the window is not touched while it is dragged" \
   "fn $H 'static void DMRStripDragFollow(CGPoint p) {' > \"$W/follow\" && grep -qF 'MSBDRStripProxySize(d.cw, d.ch, d.ww, d.wh, DMRStripRectOf(u), MSBDRStripPastBand(p.x, gRStripBand, gRStripRight), &w, &h);' \"$W/follow\" \
    && grep -qF 'd.holder.center = CGPointMake(p.x - d.gx * w + w / 2.0, p.y - d.gy * h + h / 2.0);' \"$W/follow\" && ! grep -qE 'st\.|DMStageForBundle|DMSetStageFrameSafe' \"$W/follow\" \
    && fn $H 'static void DMRStripCardDragBegin(DMRStripCard *c, DMRStripPress *g) {' | grep -qF '[gRStripRoot addSubview:holder];'"
ck "  ... let go: back in the band, or the window where it was let go (the rules' frame, a throw's point), snapped as a move by hand, placed hidden by the engine's setter, out of the card, at the front with no swap" \
   "grep -qF 'if (MSBDRStripDropsBack(ox, gRStripBand, gRStripRight)) { DMRStripCardDragReturn(@\"let go in the band\", NO); return; }' \"$W/dragend\" \
    && grep -qF 'if (hypot(vx, vy) > 400.0) MSBDRStripFlickTo(p.x, p.y, vx, vy, &ox, &oy);' \"$W/dragend\" && grep -qF 'CGRect drawn = DMRStripCGRect(MSBDRStripDropFrame(d.ww, d.wh, d.gx, d.gy, ox, oy, desk));' \"$W/dragend\" \
    && grep -qF 'if (st) drawn = DMSnapEngineWindow(st, drawn, MSBDSnapMove);' \"$W/dragend\" && grep -qF 'DMRStripPlaceHidden(st, engine);' \"$W/dragend\" && grep -qF 'DMFitGroupForget(k);' \"$W/dragend\" \
    && grep -qF 'gRStripLeaving[k] = [NSValue valueWithCGRect:from];' \"$W/dragend\" && grep -qF 'if (!DMSurfaceWindowForApp(k)) DMRaiseStageForBundle(k);' \"$W/dragend\" && ! grep -q 'DMRStripMinimizeNow' \"$W/dragend\" \
    && grep -qF 'if (!kept && (!st || !DMRStripHiddenByUs(st))) { DMRStripCardDragReturn(@\"its window went meanwhile\", YES); return; }' \"$W/dragend\""
ck "  ... cut short first by anything that puts the strip aside (a lock, the App Switcher, the Mac Switcher, Spotlight...) and by a turn: back to its slot" \
   "grep -A1 -F 'if (show == MSBDRStripHidden) {' \"$W/show\" | grep -qF 'if (gRStripCardDrag) DMRStripCardDragReturn(' && grep -qF 'if (gRStripCardDrag) DMRStripCardDragReturn(@\"the iPad turned\", NO);' \"$W/turn\""
ck "the card's menu: ours, beside the card (Bring Back with no swap, Close Window: the red light's way), with the menus' keys and VoiceOver" \
   "fn $H 'static void DMRStripCardMenu(DMRStripCard *c, NSString *how) {' > \"$W/cmenu\" && grep -qF 'UIView *panel = DMMakeBarMenuPanel(items, host, anchor);' \"$W/cmenu\" && grep -qF 'DMAXMenuPanel(panel, ' \"$W/cmenu\" \
    && grep -qF 'initWithTitle:members.count > 1 ? @\"Bring Back All\" : @\"Bring Back\" enabled:YES handler:DMCloseThen(^{ DMRStripCard *x = gRStripCards[k]; if (x) DMRStripPick(x, YES, ' \"$W/cmenu\" \
    && grep -qF 'initWithTitle:members.count > 1 ? @\"Close Windows\" : @\"Close Window\" enabled:YES handler:DMCloseThen(^{ DMRStripCloseCard(k); })' \"$W/cmenu\" && fn $H 'static void DMRStripCloseCard(NSString *k) {' | grep -qF 'DMForceQuitBundle(k);'"
ck "VoiceOver, Switch Control, Full Keyboard Access: each card a button named for its window with Bring Back and Close Window, activate a pick, the strip a container of its cards in order" \
   "grep -qF 'c.accessibilityLabel = [NSString stringWithFormat:@\"%@ window, in the strip\", name];' \"$W/card\" && grep -qF 'c.accessibilityTraits = UIAccessibilityTraitButton;' \"$W/card\" \
    && grep -qF 'initWithName:@\"Bring Back\" actionHandler:' \"$W/card\" && grep -qF 'initWithName:@\"Close Window\" actionHandler:' \"$W/card\" \
    && grep -qF -e '- (BOOL)accessibilityActivate { DMRStripPick(self, NO, @\"VoiceOver' $H && grep -qF 'gRStripSlide.accessibilityElements = ax;' $H"
ck "the keys on a Window menu reveal: the keyboard's focus held only then (with a hardware keyboard), let go at its end or as it hides; Up and Down the rules' step, Return a pick, Escape the end; read from SpringBoard's presses" \
   "fn $H 'static void DMRStripKeysTake(BOOL take) {' > \"$W/keys\" && grep -qF 'gRStripFocusLock = MSBDFocusLock(gRStripWindow.windowScene, ' \"$W/keys\" && grep -qF 'if (!DMHardwareKeyboardAttached() || !gRStripWindow.windowScene) return;' \"$W/keys\" \
    && grep -qF 'MSBDFocusUnlock(l);' \"$W/keys\" && grep -qF 'if (gRStripReveal == MSBDRStripRevealMenu) DMRStripKeysTake(YES);' $H && grep -A4 -F 'gRStripReveal = 0; gRStripPointerOutAt = 0;' $H | grep -qF 'DMRStripKeysTake(NO);' \
    && grep -qF 'gRStripKeySel = MSBDRStripKeyStep(gRStripKeySel, (int)gRStripItems.count, code == UIKeyboardHIDUsageKeyboardDownArrow ? 1 : -1);' $H \
    && grep -B1 -F 'o_OverlayPressesBegan(self, _cmd, presses, event);' $S | grep -qF 'if (!gOverlay && DMRStripKeys(presses)) return;'"
ck "a file, text or picture held over a card: UIKit's own spring loading brings its window back with no swap (KT's choice), no timer of ours" \
   "grep -qF '[c addInteraction:[[UISpringLoadedInteraction alloc] initWithActivationHandler:^(UISpringLoadedInteraction *i, id<UISpringLoadedInteractionContext> ctx) {' \"$W/card\" \
    && grep -qF 'if (x) { DM_FEATURE_MARK(\"recent-strip-spring-load\"); DMRStripPick(x, YES, @\"a drag held over it\"); }' \"$W/card\""
NW=../statusbar/NativeWindow.h
ck "our own windows (Finder, TextEdit, Activity Monitor, Display Settings) wait in it too: the ones our minimize hid, one card per app, its time its most recent window's, its windows most recent first" \
   "grep -qF 'if (!going && (!nw.hidden || !nw.dm_wasMinimized)) { if (!nw.hidden && nw.superview && nw.alpha > 0.05) anyShown = YES; continue; }' \"$W/collect\" \
    && grep -qF 'NSString *k = DMRStripNativeKey(nw);' \"$W/collect\" && grep -qF 'if (!at[k] || at[k].doubleValue < t) at[k] = @(t);' \"$W/collect\" && grep -qF 'gRStripGroups = groups;' \"$W/collect\" \
    && grep -qF 'static NSString *DMRStripNativeKey(DMNativeWindow *w) { return [@\"native:\" stringByAppendingString:w.appName.length ? w.appName : @\"Window\"]; }' $H \
    && grep -qF 'if ([st isKindOfClass:[DMNativeWindow class]]) return st.hidden && ((DMNativeWindow *)st).dm_wasMinimized;' $H"
ck "  ... their minimize flies into their app's card and their way back grows out of it (NativeWindow.h asks the strip first, the Dock's Finder icon as before otherwise), the card stays while others of the app wait" \
   "fn \$NW '- (void)minimize {' > \"$W/nmin\" && sed -n 3p \"$W/nmin\" | grep -qF 'CGRect strip = DMRStripNativeFlight(self, YES);' \
    && grep -qF 'CGRect target = CGRectIsNull(strip) || !gNativeRotator ? DMNativeDockTarget() : [gNativeRotator convertRect:strip fromCoordinateSpace:[UIScreen mainScreen].coordinateSpace];' \"$W/nmin\" \
    && [ \"\$(grep -c 'DMRStripNativeLanded(self);' \"$W/nmin\")\" = 2 ] && fn \$NW '- (void)show {' | grep -qF 'CGRect strip = self.dm_wasMinimized ? DMRStripNativeFlight(self, NO) : CGRectNull;' \
    && fn $H '__attribute__((noinline)) static CGRect DMRStripNativeFlight(DMNativeWindow *w, BOOL into) {' | grep -qF 'if (!others) DMRStripCardGoes(k, r != nil);'"
ck "  ... a stack of up to 3 of its windows' pictures, each lower and smaller, a count over 3 (the rules' stack)" \
   "fn $H 'static void DMRStripCardPicture(DMRStripCard *c) {' > \"$W/cpic\" && grep -qF 'b.hidden = i + 1 >= (NSUInteger)MSBDRStripStackShown((int)n);' \"$W/cpic\" \
    && grep -qF 'b.frame = DMRStripCGRect(MSBDRStripStackRect(DMRStripRectOf(c.picRect), (int)i + 1));' \"$W/cpic\" && grep -qF 'c.badge.hidden = !MSBDRStripStackBadge((int)n);' \"$W/cpic\""
ck "  ... a pick brings them all back, the most recent in front (KT's choice); the window in front may be ours now and waits in the strip by a swap; dropped on the strip they go in" \
   "grep -qF 'for (DMNativeWindow *nw in [members reverseObjectEnumerator]) [nw show];' \"$W/pick\" && fn $H 'static UIView *DMRStripFrontWindow(BOOL *ours) {' | grep -qF 'if (nw) { if (ours) *ours = YES; return nw; }' \
    && fn $H 'static void DMRStripMinimizeNow(UIView *w) {' | grep -qF 'if ([w isKindOfClass:[DMNativeWindow class]]) { [(DMNativeWindow *)w minimize]; return; }' \
    && fn $H 'static BOOL DMRStripCanJoin(UIView *w) {' | grep -qF 'if ([w isKindOfClass:[DMNativeWindow class]]) return !w.hidden && w.superview && [gNativeWindows containsObject:(DMNativeWindow *)w];' \
    && fn \$NW '- (void)dm_move:(UIPanGestureRecognizer *)g {' | grep -qF 'if (DMRStripWindowDrag(self, g, g.state)) return;'"
ck "  ... its menu names each window (back alone, a pile's pick), Close Windows closes each; the switch off brings back the ones a swap or a drag put there" \
   "grep -qF '[items addObject:[[DMRow alloc] initWithTitle:nw.title.length ? nw.title : name enabled:YES handler:DMCloseThen(^{ DMNativeWindow *x = wnw; if (x && DMRStripHiddenByUs(x)) { DM_FEATURE_MARK(\"recent-strip-pile-pick\"); [x show]; } })]];' $H \
    && grep -qF 'if (DMRStripIsNativeKey(k)) { for (DMNativeWindow *nw in [gRStripGroups[k] copy]) [nw close]; DMRStripRelayout(YES); return; }' $H \
    && grep -qF 'BOOL backNow = DMRStripEntryOf(nw, &at, &why) && DMRStripHiddenByUs(nw) && MSBDRStripBackAtOff(why);' \"$W/off\""
ck "the finger's handle (KT's choice): shown by the rules (stepped aside with cards, no trackpad or mouse), at the rules' place, its touch area alone taking touches while aside; a tap or a swipe toward the desktop brings the strip out" \
   "grep -qF 'static BOOL DMRStripHandleWanted(void) { return MSBDRStripHandleShown(gRStripMayRevealNow && gRStripShown == MSBDRStripHidden && gRStripItems.count > 0, gDMPointerAttached); }' $H \
    && grep -qF 'h.frame = DMRStripCGRect(MSBDRStripHandleRect(sc.width, gRStripSpan, gRStripRight));' $H && grep -qF 't.frame = DMRStripCGRect(MSBDRStripHandleTouch(sc.width, gRStripSpan, gRStripRight));' $H \
    && grep -qF 'if ([gRStripHandleTouch pointInside:q withEvent:e]) return gRStripHandleTouch;' \"$W/hit\" && grep -qF 'gRStripReveal = MSBDRStripRevealHandle; DMRStripTouched();' $H \
    && grep -A1 -F 'MSBDRStripShow show = DMRStripApplyShow(laid, covered, nil);' \"$W/tick\" | grep -qF 'DMRStripHandleUpdate();' && grep -qF 'if (gRStripRight ? dx < -12.0 : dx > 12.0) DMRStripHandleReveal(' $H \
    && grep -qF 'touch.isAccessibilityElement = YES; touch.accessibilityLabel = @\"Recent Windows Strip\";' $H"
ck "the turn and the steps aside are apart: the root's transform is the turn alone (DMRStripTurnIn), each card slides by its own (DMRStripShowAs, the rules' motion), the slide never moves" \
   "grep -qF 'root.transform = turned ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity;' \"$W/turn\" && grep -qF 'slide.bounds = CGRectMake(0, 0, want.size.width, want.size.height);' \"$W/turn\" \
    && [ \"\$(grep -cE 'root\.transform =' $H)\" = \"\$(grep -cE 'root\.transform =' \"$W/turn\")\" ] && ! grep -qE '(slide|gRStripSlide)\.(transform|alpha) =' $H \
    && grep -qF 'MSBAnimate(kMSBDRStripAsideTime, 0, 0, UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState, ^{ c.transform = DMRStripAway();' \"$W/show\" \
    && grep -qF 'MSBAnimate(kMSBDRStripShowTime, MSBDRStripStaggerAt(i++), kMSBDRStripShowDamp,' \"$W/show\" && grep -qF '[gRStripSlide addSubview:c];' $H && ! grep -qF '[gRStripRoot addSubview:c]' $H"
ck "one layer per card picture: the picture as its own layer's contents, its corners on that layer, nothing under the mask; the shadow by a path" \
   "grep -qF 'pl.cornerRadius = 7.0; pl.masksToBounds = YES; pl.contentsGravity = kCAGravityResize;' \"$W/card\" && ! grep -qE '\[c\.pic addSubview|\[c\.pic\.layer addSublayer' $H \
    && grep -qF 'if (c.pic.layer.contents != contents) c.pic.layer.contents = contents;' $H && grep -qF 'c.shadow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:c.shadow.bounds cornerRadius:7.0].CGPath;' $H"
ck "pictures at the card's size, from the background queue (the Mac Switcher's request, the scale in its transform)" \
   "grep -qF 'double scale = MSBDRStripPicScale(bb.size.width, bb.size.height, MSBDRStripCardW(sc.width, sc.height), MSBDRStripCardH(sc.width, sc.height));' \"$W/pic\" \
    && grep -qF 'double s = [UIScreen mainScreen].scale * k;' \"$W/async\" && grep -qF 'dispatch_async(DMMSWPicQueue(), ^{' \"$W/async\" && grep -qF 'ok = gMSWSnapFn(MACH_PORT_NULL, opts);' \"$W/async\" \
    && grep -qF 'opts[gMSWSnapKeyMode] = gMSWSnapModeLayer;' \"$W/async\" && ! grep -q 'snapshotViewAfterScreenUpdates' $H"
ck "  ... the one that left the front once SpringBoard is calm (the window cards' rule), still on screen, never the one in front; a memory warning lets go of every one no card shows" \
   "grep -qF 'BOOL calmForPic = !DMSwitcherVisible() && !gMSWOpen && !gMSWClosing && DMMSWSessionIdle() && !DMWinCardBusy();' \"$W/tick\" \
    && grep -qF 'if (DMRStripStageOnScreen(st) && ![k isEqualToString:front]) DMRStripPicture(st, k, @\"it left the front\");' \"$W/tick\" && grep -qF 'gRStripPicDue[was] = @(now + 0.6);' \"$W/tick\" \
    && grep -qF 'name:UIApplicationDidReceiveMemoryWarningNotification object:nil];' $H && fn $H 'static void DMRStripMemoryWarning(void) {' | grep -qF 'if (![shown containsObject:k])'"
ck "the pointer: a hover recognizer that only watches (PointerRegion.h's), on the iPad's system gestures window, only while wanted" \
   "grep -qF 'UIHoverGestureRecognizer *h = [[DMPtrHoverRecognizer alloc] initWithTarget:[DMRStripTarget shared] action:@selector(sysHover:)];' \"$W/hover\" \
    && grep -qF 'h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;' \"$W/hover\" && grep -qF 'if (x.screen != [UIScreen mainScreen] || ![NSStringFromClass([x class]) isEqualToString:@\"_UISystemGestureWindow\"]) continue;' \"$W/hover\" \
    && grep -qF 'DMRStripSysHoverUpdate(gDMPointerAttached && (gRStripMayRevealNow || gRStripReveal == MSBDRStripRevealPointer));' \"$W/tick\" && grep -qF '@interface DMPtrHoverRecognizer : UIHoverGestureRecognizer' ../statusbar/PointerRegion.h"
ck "  ... the edge and the leaving are the rules'" "fn $H 'static void DMRStripSysHoverSeen(UIHoverGestureRecognizer *g) {' > \"$W/seen\" && grep -qF 'if (!gRStripMayRevealNow || !MSBDRStripPointerAtEdge(p.x, s.bounds.size.width, gRStripRight)) return;' \"$W/seen\" \
   && grep -qF 'if (MSBDRStripPointerLeft(p.x, gRStripBand, gRStripRight)) { if (!gRStripPointerOutAt) gRStripPointerOutAt = now; }' \"$W/seen\""
ck "Window > Move to Strip (the window in front, Command-M's way) and Show Recent Windows with Aerial, Zetsu and MilkyWay4 (the engines' branch of the menu)" \
   "fn $S 'static void DMOpenWindowMenu(UIButton *btn) {' > \"$W/menu\"; awk '/if \\(DMActiveEngine\\(\\) != DMEngineNone\\) \\{   \\/\\/ \"Open Apps as Windows\"/,/\\} else if \\(DMSMEngine\\(\\)\\) \\{/' \"$W/menu\" > \"$W/menueng\" \
    && grep -qF 'if (DMRStripMenuOffered()) [items addObject:[[DMRow alloc] initWithTitle:@\"Show Recent Windows\" enabled:YES handler:DMCloseThen(^{ DMRStripMenuReveal(); })]];' \"$W/menueng\" \
    && grep -qF 'if (aboutActive && DMRStripMoveOffered()) [items addObject:[[DMRow alloc] initWithTitle:@\"Move to Strip\" enabled:YES handler:DMCloseThen(^{ DMMinimizeActiveApp(); })]];' \"$W/menueng\" \
    && grep -qF '__attribute__((noinline)) static BOOL DMRStripMenuOffered(void) { return DMRStripOn() && gRStripMayRevealNow && gRStripItems.count > 0; }' $H \
    && grep -qF '__attribute__((noinline)) static BOOL DMRStripMoveOffered(void) { BOOL ours = NO; return DMRStripOn() && DMRStripFrontWindow(&ours) != nil; }' $H"
ck "the switch: recentStrip, off unless switched on (1.8.8.2.1), a boolean only, read with the preferences" \
   "grep -qF 'CFPropertyListRef rs = CFPreferencesCopyValue(CFSTR(\"recentStrip\"), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
    && grep -qF 'BOOL recentStrip = (rs && CFGetTypeID(rs) == CFBooleanGetTypeID() && CFBooleanGetValue(rs));' $S && grep -qF 'gRStripPref = recentStrip;' $S \
    && grep -qF 'static BOOL gRStripPref = NO; ' $H"
ck "  ... one default in all four places, off (1.8.8.2.1): SpringBoard before and after reading the preferences, the Settings row and the crash guard's target" \
   "python3 -I -c 'import re,sys,plistlib
h=open(\"$H\").read(); s=open(\"$S\").read(); c=open(\"$C\").read()
it=plistlib.load(open(\"$PL\",\"rb\"))[\"items\"]; row=[x for x in it if x.get(\"key\")==\"recentStrip\"]
a=re.findall(r\"^static BOOL gRStripPref = (YES|NO);\", h, re.M)
b=re.findall(r\"BOOL recentStrip = (.*);\", s)
t=re.findall(r\"^target recentStrip pref com.besiktasliseba.macstatusbar recentStrip 0 ([01]) \", c, re.M)
ok = a==[\"NO\"] and len(b)==1 and b[0].startswith(\"(rs\") and \"!CFBooleanGetValue\" not in b[0] and len(row)==1 and row[0][\"default\"] is False and t==[\"0\"]
sys.exit(0 if ok else 1)'"
ck "the include: after the window cards (their calm check, the Mac Switcher's pictures)" \
   "grep -A1 -F '#include \"WindowCards.h\"' $S | grep -qF '#include \"RecentStrip.h\"' && grep -qF '#include \"../common/RecentStripRule.h\"' $H"
ck "Settings: Recent Windows Strip right after Recent Apps with Left-Edge Swipe in the Mac Switcher's group, off by default (1.8.8.2.1), its sentence in the footer and the page's words" \
   "plutil -convert json -o - $PL | python3 -I -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; ids=[x.get(\"id\") for x in it]; i=ids.index(\"RECENT_STRIP\"); s=it[i]
g=[x for x in it[:i] if x.get(\"cell\")==\"PSGroupCell\"][-1]
f=g[\"footerText\"]
ok = ids[i-1]==\"STRIP_SWIPE\" and s[\"key\"]==\"recentStrip\" and s[\"default\"] is False and s[\"cell\"]==\"PSSwitchCell\" and s[\"label\"]==\"Recent Windows Strip\" and g.get(\"id\")==\"MSW_GROUP\"
p=[x for x in f.split(\"\\n\\n\") if x.startswith(\"Recent Windows Strip:\")]
w=open(\"$P\").read()
ok = ok and len(p)==1 and (\"@\\\"recentStrip\\\": @\\\"\" + p[0] + \"\\\",\") in w and all(c not in f for c in \"\\u2014\\u2013\")
sys.exit(0 if ok else 1)'"
ck "  ... its sentence tells what it does now: the minimized windows, a swap, a drag out and in, the Home Screen's room, the ways out (KT's short style, no dash)" \
   "plutil -convert json -o - $PL | python3 -I -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; g=[x for x in it if x.get(\"id\")==\"MSW_GROUP\"][0]
p=[x for x in g[\"footerText\"].split(\"\\n\\n\") if x.startswith(\"Recent Windows Strip:\")][0]
need=[\"minimized windows wait\", \"swap it with the window in front\", \"drag it out\", \"Drag a window to the strip\", \"The Home Screen keeps room for it\", \"tap its handle\", \"Window > Show Recent Windows\"]
sys.exit(0 if all(n in p for n in need) and len(p) < 420 else 1)'"
ck "  ... shown only with a working Aerial, Zetsu or MilkyWay4 on the rules' iPadOS, on the page and in the search" \
   "grep -qF 'if ([ident isEqualToString:kMSBDRecentStripRowID] && (!s.engineWorks || s.stageManagerEngine || !s.recentStripOS)) return YES;' $O \
    && grep -qF '    s.recentStripOS = MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion);' ../common/OwnPageState.h \
    && ! grep -n 'kMSBDRecentStripRowID' $O | grep -q 'NSProcessInfo' \
    && grep -qF '#define kMSBDRecentStripRowID @\"RECENT_STRIP\"' $O && grep -qF '#include \"RecentStripRule.h\"' $O \
    && grep -qF 'if ([sp.identifier isEqualToString:kMSBDRecentStripRowID]) continue;   // (Recent Windows Strip: the engines' $P \
    && grep -qF 'if (sm || !MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion)) {' $P \
    && grep -qF 'for (PSSpecifier *sp in _specifiers) if (![sp.identifier isEqualToString:kMSBDRecentStripRowID]) [kept addObject:sp];' $P"
ck "the crash guard: its own switch, the whole strip and its rules (a crash there turns the strip off, nothing else)" \
   "grep -qxF 'target recentStrip pref com.besiktasliseba.macstatusbar recentStrip 0 0 Recent Windows Strip|the recent windows strip' $C \
    && grep -qxF 'file MacStatusBarCore ^RecentStrip(Rule)?\\.h\$ recentStrip' $C \\
    && grep -qxF 'sym MacStatusBarCore ([-+]\\[DMRStrip(Card|Target)\\s|^_*DMRStrip[A-Z]|^_*MSBDR(Strip|ecentStrip|MaxX|MaxY)) recentStrip' $C"
ck "  ... no section of the strip's files names a section rule (they would take its functions first)" \
   "python3 -I -c 'import re,sys
rules=[re.compile(l.split()[2]) for l in open(\"$C\") if l.startswith(\"sec MacStatusBarCore \")]
heads=[l.rstrip() for f in (\"$H\",\"$R\") for l in open(f) if re.match(r\"^(//\\s*(=|-){3,}|%group)\", l)]
sys.exit(1 if any(r.search(h) for r in rules for h in heads) else 0)'"
ck "  ... and no name rule of another target matches a function of the strip" \
   "python3 -I -c 'import re,sys
rules=[(re.compile(l.split()[2]), l.split()[3]) for l in open(\"$C\") if l.startswith(\"sym MacStatusBarCore \") and l.split()[3] != \"recentStrip\"]
names=set(re.findall(r\"^static [^(]*?\\b(DMRStrip\\w+|MSBDR\\w+)\\(\", open(\"$H\").read()+open(\"$R\").read(), re.M))
bad=[(n,t) for n in names for r,t in rules if r.search(\"_\"+n) or r.search(n)]
print(\"  strip functions:\", len(names)); sys.exit(1 if bad or len(names) < 30 else 0)'"
# (review of 1.8.8.4: our own windows in the strip)
fn "$H" 'static void DMRStripMemoryWarning(void) {' > "$W/memwarn"
fn "$S" 'static void DMOpenNativeWindowMenu(UIButton *btn) {' > "$W/nwmenu"
ck "review 1.8.8.4: the step's trim keeps a card of our own windows' pictures (its stack's, by their own keys), a memory warning too" \
   "grep -qF 'NSSet<NSString *> *cards = MSBDRStripPicsFor(gRStripList, gRStripItems.count + kMSBDRStripPicKeepMore, DMRStripGroupPics());' \"$W/tick\" \
    && grep -qF 'if ([cards containsObject:k] || [recent containsObject:k]) continue;' \"$W/tick\" && ! grep -qF 'MSBDRStripPicKept(i, gRStripItems.count)' \"$W/tick\" \
    && grep -qF 'NSSet<NSString *> *shown = MSBDRStripPicsFor(gRStripItems ?: @[], gRStripItems.count, DMRStripGroupPics());' \"$W/memwarn\" \
    && grep -qF 'for (DMNativeWindow *w in gRStripGroups[k]) [keys addObject:DMRStripNativePicKey(w)];' $H"
ck "review 1.8.8.4: our own windows minimized on another Mac Switcher desktop wait in that desktop's strip only (as the engines' windows), the step sees a desktop switch" \
   "grep -qF 'if (DMRStripNativeAway(nw)) continue;' \"$W/collect\" && fn $H 'static BOOL DMRStripNativeAway(DMNativeWindow *w) {' > \"$W/away\" \
    && grep -qF 'if (!w || !DMMSWForMain() || !DMMSWMulti()) return NO;' \"$W/away\" && grep -qF 'NSNumber *d = objc_getAssociatedObject(w, kMSWNativeDeskKey);' \"$W/away\" \
    && grep -qF 'return [d isKindOfClass:[NSNumber class]] && d.integerValue != DMMSWCurId();' \"$W/away\" && grep -qF 'h = MSBDRStripSigMix(h, (uint64_t)DMMSWCurId());' \"$W/sig\""
ck "review 1.8.8.4: one of our own windows dropped into the strip comes back where it was at the touch (-dm_move: moves it by the pan's start before the strip hears of it)" \
   "grep -qF 'if ([win isKindOfClass:[DMNativeWindow class]] && [g isKindOfClass:[UIPanGestureRecognizer class]] && win.superview) {' \"$W/drag\" \
    && grep -qF 'if (isfinite(t.x) && isfinite(t.y)) gRStripDragFrom = CGRectOffset(win.frame, -t.x, -t.y);' \"$W/drag\" \
    && grep -qF 'w.frame = DMNativeClamp(back.CGRectValue, w.minSize);' $H"
ck "review 1.8.8.4: Finder's own Window menu has the strip's rows as the engines' has (Move to Strip, Show Recent Windows)" \
   "grep -qF 'if (w && DMRStripOn()) [items addObject:R(@\"Move to Strip\", nil, ^{ [w minimize]; })];' \"$W/nwmenu\" \
    && grep -qF 'if (DMRStripMenuOffered()) [items addObject:[[DMRow alloc] initWithTitle:@\"Show Recent Windows\" enabled:YES handler:DMCloseThen(^{ DMRStripMenuReveal(); })]];' \"$W/nwmenu\" \
    && [ \"\$(grep -n '^#include \"RecentStrip.h\"' $S | cut -d: -f1)\" -lt \"\$(grep -n '^static void DMOpenNativeWindowMenu(UIButton \*btn) {' $S | cut -d: -f1)\" ]"
# (review of 1.8.8.4: the press, the ends of a reveal, the drop zone on a turn, jiggle mode, rest)
fn "$H" 'static void DMRStripTapOutside(void) {' > "$W/outside"
fn "$H" 'static BOOL DMRStripCalm(void) {' > "$W/calm2"
ck "review 1.8.8.4: a finger's press and its hold's rise are one animation of the lift (the press recogniser animates nothing; a release springs back from where it is drawn, no jump)" \
   "grep -qF 'if (c.pressed && c.fingerDown && !rm) {' \"$W/lift\" && grep -qF '[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:kMSBDRStripPressIn / total animations:^{ c.lift.transform3D = t; }];' \"$W/lift\" \
    && grep -qF 'animateKeyframesWithDuration:total delay:0 options:UIViewKeyframeAnimationOptionBeginFromCurrentState | UIViewKeyframeAnimationOptionAllowUserInteraction' \"$W/lift\" \
    && ! grep -q 'MSBAnimate' \"$W/pressed\" && [ \"\$(grep -c 'removeAllAnimations' \"$W/pressed\")\" = 1 ] && grep -qF 'c.pressed = NO; c.fingerDown = NO; DMRStripLiftTo(c);' \"$W/pressed\" \
    && grep -qF 'self.pressed = YES; self.fingerDown = touches.anyObject.type != UITouchTypeIndirectPointer && (event.buttonMask & UIEventButtonMaskSecondary) == 0;' $H"
ck "review 1.8.8.4: a tap outside the cards ends a reveal by the Window menu or the handle (on the next main-queue turn, a touch only, never the pointer's hover)" \
   "grep -qF 'if (e && e.type == UIEventTypeTouches && gRStripReveal) DMRStripTapOutside();' \"$W/hit\" && grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{' \"$W/outside\" \
    && grep -qF 'DMRStripRevealEnd(@\"a tap outside\");' \"$W/outside\" && [ \"\$(grep -c 'gRStripReveal != MSBDRStripRevealMenu && gRStripReveal != MSBDRStripRevealHandle' \"$W/outside\")\" = 2 ]"
ck "review 1.8.8.4: Edit Home Screen (jiggle mode) puts the strip away, as the App Library does (the design's own line; the band stays)" \
   "grep -qF 'if (DMRStripHomeEditing()) return NO;' \"$W/calm2\" && fn $H 'static BOOL DMRStripHomeEditing(void) {' | grep -qF 'return [im respondsToSelector:@selector(isEditing)] && ((BOOL (*)(id, SEL))objc_msgSend)(im, @selector(isEditing));' \
    && ! grep -q 'DMDesktopEditing()' $H"
ck "review 1.8.8.4: a window drag's drop zone follows a turn during the drag (the new shape's band and side)" \
   "grep -qF 'if (!CGSizeEqualToSize(sc, gRStripDragScreen)) {' \"$W/drag\" && grep -qF 'gRStripDragScreen = CGSizeZero;   // (its band just below)' \"$W/drag\" \
    && [ \"\$(grep -n 'if (!CGSizeEqualToSize(sc, gRStripDragScreen)) {' \"$W/drag\" | cut -d: -f1)\" -lt \"\$(grep -n 'BOOL inZone = joins' \"$W/drag\" | cut -d: -f1)\" ]"
ck "review 1.8.8.4: nothing at rest while a reveal waits for an event (a pointer held in the band, the Window menu's under VoiceOver): the rules' MSBDRStripRevealTimed" \
   "grep -qF 'BOOL timed = MSBDRStripRevealTimed(gRStripReveal, gRStripPointerOutAt > 0, menuLike && DMRStripAssistive()) || gRStripPointerOutAt > 0' \"$W/tick\" && ! grep -qF 'BOOL timed = gRStripReveal ||' \"$W/tick\""
ck "1.8.9.1: the 0.2 s watcher skips DMRStripTick while the strip is off and idle, and DMRStripTick checks DMRStripOn() before gRStripTicks++ and DMRStripHomeBandStep()" \
   "grep -qF 'if (DMRStripTickNeeded()) DM_PERF(\"rstrip\", DMRStripTick());' \"$W/watcher\" \
    && grep -qF 'static BOOL DMRStripTickNeeded(void) { return MSBDRStripTickNeeded(DMRStripOn(), gRStripActive); }' $H \
    && [ \"\$(grep -n 'if (!DMRStripOn()) {' \"$W/tick\" | head -1 | cut -d: -f1)\" -lt \"\$(grep -n 'gRStripTicks++;' \"$W/tick\" | head -1 | cut -d: -f1)\" ]"
ck "no em or en dash in the strip's files" "! grep -nP '\\x{2014}|\\x{2013}' $H $R test-recentstrip.m test-recentstrip.sh 2>/dev/null && ! LC_ALL=C grep -n \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $H $R test-recentstrip.m test-recentstrip.sh"

echo "== made-to-fail copies of the rules (each must fail)"
mut() {   # $1 what, $2 the text in the rules, $3 its replacement
  local f="$W/rule.$RANDOM.h"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); a,b=sys.argv[2],sys.argv[3]; assert s.count(a)==1, a; open(sys.argv[4],"w").write(s.replace(a,b))' "$TOOLS/$R" "$2" "$3" "$f" || { echo "FAIL  made-to-fail copy \"$1\": its text is not in the rules once"; rc=1; return; }
  if ! clang -fobjc-arc -Wall -Werror -Wno-unknown-warning-option -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -framework Foundation -DRSTRIP_RULE="\"$f\"" -o "$W/m" test-recentstrip.m 2>"$W/m.err"; then echo "FAIL  made-to-fail copy \"$1\" does not build"; rc=1; return; fi
  "$W/m" -q > "$W/m.out"; local r=$?
  if [ $r -gt 0 ]; then echo "PASS  caught: $1 ($r checks fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
}
mut "brought out only where nothing covers it" 'if (s.revealed) return MSBDRStripOverWindows;' 'if (s.revealed && !s.covered) return MSBDRStripOverWindows;'
mut "shows on the Home Screen with no band" 'if (!s.windowShown && !s.homeBand) return MSBDRStripHidden;' 'if (NO) return MSBDRStripHidden;'
mut "never on the Home Screen, band or not" 'if (!s.windowShown && !s.homeBand) return MSBDRStripHidden;' 'if (!s.windowShown) return MSBDRStripHidden;'
mut "shows over a full-screen app in front" 'if (!s.on || !s.calm || !s.windowsFront) return MSBDRStripHidden;' 'if (!s.on || !s.calm) return MSBDRStripHidden;'
mut "no drop target for an empty strip" 'if (s.dropTarget) return MSBDRStripOverWindows;' 'if (s.dropTarget && s.items > 0) return MSBDRStripOverWindows;'
mut "the list oldest first" 'return x > y ? NSOrderedAscending : (x < y ? NSOrderedDescending : NSOrderedSame);' 'return x < y ? NSOrderedAscending : (x > y ? NSOrderedDescending : NSOrderedSame);'
mut "a window with no time on top" 'if (!ta) return NSOrderedDescending;
        if (!tb) return NSOrderedAscending;' 'if (!ta) return NSOrderedAscending;
        if (!tb) return NSOrderedDescending;'
mut "windows with no time out of the stage order" 'if (!ta && !tb) return NSOrderedSame;' 'if (!ta && !tb) return [a compare:b] == NSOrderedAscending ? NSOrderedDescending : NSOrderedAscending;'
mut "a swap goes to the top" 'if (why == MSBDRStripWhySwapped && isfinite(picked)) return picked;' 'if (NO) return picked;'
mut "a found window is new" 'if (why == MSBDRStripWhySeeded) return kMSBDRStripSeedAt - (seed > 0 ? seed : 0);' 'if (NO) return 0;'
mut "a tie goes after" 'if (tk && tk.doubleValue > t) n++;' 'if (tk && tk.doubleValue >= t) n++;'
mut "no cap past the cards that fit" 'NSUInteger n = MIN(MIN(list.count, fit), (NSUInteger)kMSBDRStripMax);' 'NSUInteger n = MIN(list.count, (NSUInteger)kMSBDRStripMax);'
mut "a flight past the cap lands off the strip" 'return past ? last : (int)slot;' 'return (int)slot;'
mut "Minimize All all at once" 'static inline double MSBDRStripBurstDelay(int i) { return i > 0 ? i * kMSBDRStripBurstStep : 0.0; }' 'static inline double MSBDRStripBurstDelay(int i) { return 0.0; }'
mut "Shift still swaps" 'return onCard && !shift && front && frontJoins && !frontIsPicked;' 'return onCard && front && frontJoins && !frontIsPicked;'
mut "the Dock icon swaps too" 'return onCard && !shift && front && frontJoins && !frontIsPicked;' 'return !shift && front && frontJoins && !frontIsPicked;'
mut "a double tap swaps back" 'return now >= settledAt && now - lastPickAt >= kMSBDRStripPickGap;' 'return now >= settledAt;'
mut "a pick before the card landed" 'return now >= settledAt && now - lastPickAt >= kMSBDRStripPickGap;' 'return now - lastPickAt >= kMSBDRStripPickGap;'
mut "the switch off brings every window back" 'static inline BOOL MSBDRStripBackAtOff(int why) { return why == MSBDRStripWhySwapped || why == MSBDRStripWhyDragged; }' 'static inline BOOL MSBDRStripBackAtOff(int why) { return why != MSBDRStripWhyNone; }'
mut "a crashed app keeps its card" 'return !closedOrQuitByUser && !crashed;' 'return !closedOrQuitByUser;'
mut "a menu reveal ends under VoiceOver" 'return !assistive && untouchedFor > kMSBDRStripIdleEnd;' 'return untouchedFor > kMSBDRStripIdleEnd;'
mut "1.8.8.2's larger cards" 'double w = round(MIN(sw, sh) * 0.095); return w < 72.0 ? 72.0 : (w > 104.0 ? 104.0 : w);' 'double w = round(MIN(sw, sh) * 0.115); return w < 80.0 ? 80.0 : (w > 118.0 ? 118.0 : w);'
mut "the band without its edge gaps" 'static inline double MSBDRStripBandW(double sw, double sh) { return MSBDRStripCardW(sw, sh) + 2.0 * kMSBDRStripEdgeGap; }' 'static inline double MSBDRStripBandW(double sw, double sh) { return MSBDRStripCardW(sw, sh) + kMSBDRStripEdgeGap; }'
mut "a slot opened takes no box" 'int boxes = n + (gap >= 0 ? 1 : 0);' 'int boxes = n;'
mut "no zone past the band" 'return right ? x >= band.x - kMSBDRStripDropBy : x <= MSBDRMaxX(band) + kMSBDRStripDropBy;' 'return right ? x >= band.x : x <= MSBDRMaxX(band);'
mut "the zone the whole screen's height" 'if (y < band.y - kMSBDRStripDropBy || y > MSBDRMaxY(band) + kMSBDRStripDropBy) return NO;' 'if (NO) return NO;'
mut "a hold then a move opens the menu" 'if (moved >= (pointer ? kMSBDRStripPointerSlop : kMSBDRStripFingerSlop)) return MSBDRStripPressDrag;' 'if (held < kMSBDRStripHold && moved >= (pointer ? kMSBDRStripPointerSlop : kMSBDRStripFingerSlop)) return MSBDRStripPressDrag;'
mut "a pointer's drag needs 10 pt" 'if (moved >= (pointer ? kMSBDRStripPointerSlop : kMSBDRStripFingerSlop)) return MSBDRStripPressDrag;' 'if (moved >= kMSBDRStripFingerSlop) return MSBDRStripPressDrag;'
mut "a long click opens the menu" 'return !pointer && held >= kMSBDRStripHold ? MSBDRStripPressMenu : MSBDRStripPressTap;' 'return held >= kMSBDRStripHold ? MSBDRStripPressMenu : MSBDRStripPressTap;'
mut "a dragged card grows at once" 'double t = (past - kMSBDRStripGrowFrom) / kMSBDRStripGrowOver;' 'double t = past / kMSBDRStripGrowOver;'
mut "a dragged card grows past the desktop" 'if (ww > 0 && wh > 0 && desk.w > 0 && desk.h > 0) k = MIN(1.0, MIN(desk.w / ww, desk.h / wh));
    double tw' 'double tw'
mut "a dragged card blown up to its window" 'if (cw > 0 && ch > 0 && tw > 0 && th > 0) { double m = MIN(1.0, MIN(kMSBDRStripGrowMax * cw / tw, kMSBDRStripGrowMax * ch / th)); tw *= m; th *= m; }' '(void)0;'
mut "the drop not under the grab point" 'MSBDRRect f = { px - gx * w, py - gy * h, w, h };' 'MSBDRRect f = { px, py, w, h };'
mut "a drop over the menu bar" 'f.y = MAX(desk.y, MIN(f.y, MSBDRMaxY(desk) - 40.0));' 'f.y = MIN(f.y, MSBDRMaxY(desk) - 40.0);'
mut "a drop over the Dock stays there" 'px = MAX(desk.x, MIN(px, MSBDRMaxX(desk))); py = MAX(desk.y, MIN(py, MSBDRMaxY(desk)));' '(void)0;'
mut "a thrown card stops where let go" 'if (ox) *ox = px + (isfinite(vx) ? vx : 0.0) * kMSBDRStripFlick;' 'if (ox) *ox = px;'
mut "the handle with a mouse" 'static inline BOOL MSBDRStripHandleShown(BOOL asideWithCards, BOOL pointerAttached) { return asideWithCards && !pointerAttached; }' 'static inline BOOL MSBDRStripHandleShown(BOOL asideWithCards, BOOL pointerAttached) { return asideWithCards; }'
mut "the handle takes the whole edge" 'h.y - kMSBDRStripHandleTouchPad, kMSBDRStripHandleTouchW, h.h + 2.0 * kMSBDRStripHandleTouchPad };' '0.0, kMSBDRStripHandleTouchW, 1.0e5 };'
mut "only the window in front pictured as it goes in" 'if (!burst) return age > 0.5;' 'if (!burst) return front && age > 0.5;'
mut "every window pictured in a burst" 'return front && age > kMSBDRStripMinPicLife;
}' 'return age > kMSBDRStripMinPicLife;
}'
mut "the files' area under the band" 'if (right) { double end = MIN(MSBDRMaxX(area), band.x); r.w = end - r.x; }' 'if (right) { }'
mut "a stack not lower behind" 'front.y + (front.h - h) + depth * kMSBDRStripStackStep, w, h };' 'front.y, w, h };'
mut "the keys wrap around" 'return s < 0 ? 0 : (s >= n ? n - 1 : s);' 'return s < 0 ? n - 1 : (s >= n ? 0 : s);'
mut "no stagger cap" 'return d > kMSBDRStripStaggerMax ? kMSBDRStripStaggerMax : d; }' 'return d; }'
mut "no slack in the cover" 'return ox > kMSBDRStripCoverSlack && oy > kMSBDRStripCoverSlack;' 'return ox > 0 && oy > 0;'
mut "always the left edge" 'static inline BOOL MSBDRStripOnRight(BOOL dockAtLeft) { return dockAtLeft; }' 'static inline BOOL MSBDRStripOnRight(BOOL dockAtLeft) { return NO; }'
mut "the edge 1 pt wide" 'return right ? x >= sw - kMSBDRStripEdgeAt : x <= kMSBDRStripEdgeAt;' 'return right ? x >= sw - 1.0 : x <= 1.0;'
mut "8 cards" '#define kMSBDRStripMax        6' '#define kMSBDRStripMax        8'
mut "cards not centred" 'top = usable.y + floor((usable.h - total) / 2.0);' 'top = usable.y + kMSBDRStripEnds;'
mut "pictures at the window's size" 'return k > 1.0 ? 1.0 : (k < 0.02 ? 0.02 : k);' 'return 1.0;'
mut "a closing window waits in the strip" 'return hiddenByUs && !closing && !goingFull && !away; }' 'return hiddenByUs && !goingFull && !away; }'
mut "Aerial's lock chip in the strip" 'return hiddenByUs && !closing && !goingFull && !away; }' 'return !closing && !goingFull && !away; }'
mut "another desktop's window in this strip" 'return hiddenByUs && !closing && !goingFull && !away; }' 'return hiddenByUs && !closing && !goingFull; }'
mut "a burst all at one time" 'return now + (i > 0 ? i : 0) * 0.001; }' 'return now; }'
mut "a burst's front one the oldest" 'return now + (i > 0 ? i : 0) * 0.001; }' 'return now - (i > 0 ? i : 0) * 0.001; }'
mut "a saved entry with any reason" 'if (!isfinite(t) || w < MSBDRStripWhyMinimized || w > MSBDRStripWhySeeded) return NO;' 'if (!isfinite(t)) return NO;'
mut "a saved time that is not a number" 'if (!isfinite(t) || w < MSBDRStripWhyMinimized || w > MSBDRStripWhySeeded) return NO;' 'if (w < MSBDRStripWhyMinimized || w > MSBDRStripWhySeeded) return NO;'
mut "a minimize into the strip over the App Switcher" 'static inline BOOL MSBDRStripFliesIn(BOOL on, BOOL calm, BOOL windowsFront) { return on && calm && windowsFront; }' 'static inline BOOL MSBDRStripFliesIn(BOOL on, BOOL calm, BOOL windowsFront) { return on && windowsFront; }'
mut "a way back out of a card still landing" 'return cardOnScreen && stripShown && !landing; }' 'return cardOnScreen && stripShown; }'
mut "a way back out of a hidden strip" 'return cardOnScreen && stripShown && !landing; }' 'return cardOnScreen && !landing; }'
mut "a kept card decided at once" 'if (since < kMSBDRStripGoneWait) return MSBDRStripGoneWait;' '(void)since;'
mut "a kept card stays with its app back" 'if (windowBack || quitting) return MSBDRStripGoneDrop;' 'if (quitting) return MSBDRStripGoneDrop;'
mut "a card waits after a quit asked just now" 'if (windowBack || quitting) return MSBDRStripGoneDrop;' 'if (windowBack) return MSBDRStripGoneDrop;'
mut "a flight's peek never ends" 'if (kind == MSBDRStripRevealFlight) return untouchedFor > kMSBDRStripFlightShow;' '(void)0;'
mut "a drop outside the zone goes in" 'static inline BOOL MSBDRStripDropTakes(BOOL inZone, BOOL canShow, BOOL windowJoins) { return inZone && canShow && windowJoins; }' 'static inline BOOL MSBDRStripDropTakes(BOOL inZone, BOOL canShow, BOOL windowJoins) { return canShow && windowJoins; }'
mut "a drop over the App Switcher goes in" 'static inline BOOL MSBDRStripDropTakes(BOOL inZone, BOOL canShow, BOOL windowJoins) { return inZone && canShow && windowJoins; }' 'static inline BOOL MSBDRStripDropTakes(BOOL inZone, BOOL canShow, BOOL windowJoins) { return inZone && windowJoins; }'
mut "a closing window dropped in" 'static inline BOOL MSBDRStripDropTakes(BOOL inZone, BOOL canShow, BOOL windowJoins) { return inZone && canShow && windowJoins; }' 'static inline BOOL MSBDRStripDropTakes(BOOL inZone, BOOL canShow, BOOL windowJoins) { return inZone && canShow; }'
mut "the step always works" 'static inline BOOL MSBDRStripTickWorks(BOOL changed, BOOL timed) { return changed || timed; }' 'static inline BOOL MSBDRStripTickWorks(BOOL changed, BOOL timed) { return YES; }'
mut "the step deaf to time" 'static inline BOOL MSBDRStripTickWorks(BOOL changed, BOOL timed) { return changed || timed; }' 'static inline BOOL MSBDRStripTickWorks(BOOL changed, BOOL timed) { return changed; }'
mut "a signature of the low byte only" 'for (int i = 0; i < 8; i++) { h ^= (v >> (i * 8)) & 0xff; h *= 1099511628211ull; }' 'for (int i = 0; i < 1; i++) { h ^= (v >> (i * 8)) & 0xff; h *= 1099511628211ull; }'
mut "the Today View kept off at the right too" 'static inline BOOL MSBDRStripTodayKeepsOff(BOOL todayShown, BOOL stripRight) { return todayShown && !stripRight; }' 'static inline BOOL MSBDRStripTodayKeepsOff(BOOL todayShown, BOOL stripRight) { return todayShown; }'
mut "the strip over the Today View" 'static inline BOOL MSBDRStripTodayKeepsOff(BOOL todayShown, BOOL stripRight) { return todayShown && !stripRight; }' 'static inline BOOL MSBDRStripTodayKeepsOff(BOOL todayShown, BOOL stripRight) { return NO; }'
mut "on iPadOS 16 too" 'static inline BOOL MSBDRecentStripOS(long major) { return major == 15; }' 'static inline BOOL MSBDRecentStripOS(long major) { return major >= 15; }'
mut "the band's step works while off" 'static inline BOOL MSBDRStripBandIdle(BOOL on, double handed) { return !on && !(handed > 0.0); }' 'static inline BOOL MSBDRStripBandIdle(BOOL on, double handed) { return NO; }'
mut "the band kept after the switch went off" 'static inline BOOL MSBDRStripBandIdle(BOOL on, double handed) { return !on && !(handed > 0.0); }' 'static inline BOOL MSBDRStripBandIdle(BOOL on, double handed) { return !on; }'
mut "a new side handed on with no band" '|| (room > 0.0 && right != handedRight);' '|| right != handedRight;'
mut "the room handed on every tick" 'return !(fabs(room - handed) < 0.25) || (room > 0.0 && right != handedRight);' 'return YES;'
mut "our own windows' pictures trimmed by their app's key" 'NSArray<NSString *> *g = groupPics[list[i]];' 'NSArray<NSString *> *g = nil; (void)groupPics;'
mut "a whole group's pictures kept" 'for (NSUInteger j = 0; j < g.count && j < (NSUInteger)kMSBDRStripStackMax; j++) [keep addObject:g[j]];' 'for (NSUInteger j = 0; j < g.count; j++) [keep addObject:g[j]];'
mut "every card's pictures kept" 'for (NSUInteger i = 0; i < list.count && i < upTo; i++) {
        NSArray<NSString *> *g' 'for (NSUInteger i = 0; i < list.count; i++) {
        NSArray<NSString *> *g'
mut "a pointer held in the band works every tick" 'if (kind == MSBDRStripRevealPointer) return pointerOut;
    if (kind == MSBDRStripRevealFlight) return YES;' 'if (kind == MSBDRStripRevealPointer) return YES;
    if (kind == MSBDRStripRevealFlight) return YES;'
mut "a flight's peek rests" 'if (kind == MSBDRStripRevealFlight) return YES;
    if (kind == MSBDRStripRevealMenu' 'if (kind == MSBDRStripRevealFlight) return NO;
    if (kind == MSBDRStripRevealMenu'
mut "the Window menu's reveal rests and never ends" 'if (kind == MSBDRStripRevealMenu || kind == MSBDRStripRevealHandle) return !assistive;' 'if (kind == MSBDRStripRevealMenu || kind == MSBDRStripRevealHandle) return NO;'
mut "the Window menu's reveal works every tick under VoiceOver" 'if (kind == MSBDRStripRevealMenu || kind == MSBDRStripRevealHandle) return !assistive;' 'if (kind == MSBDRStripRevealMenu || kind == MSBDRStripRevealHandle) return YES;'
mut "the step runs every 0.2 s while off" 'static inline BOOL MSBDRStripTickNeeded(BOOL on, BOOL active) { return on || active; }' 'static inline BOOL MSBDRStripTickNeeded(BOOL on, BOOL active) { return YES; }'
exit $rc
