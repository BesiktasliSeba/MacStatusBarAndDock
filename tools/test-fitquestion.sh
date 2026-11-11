#!/bin/bash
# Mac test, as built (StatusBar.x), of Fit to Window's side question for a third window on Aerial, Zetsu and MilkyWay4 (1.8.1 item 13, KT: one way
# on every engine): it is asked before the launch on all three (Zetsu and MilkyWay4 asked once the window was up, the app drawn behind the
# question), each engine then opens the app straight into its tile, the cascade applies the choice, and the placed window is the active one
# (MilkyWay4's moves left the new window behind the two it joined).
set -e
cd "$(dirname "$0")"
X=../statusbar/StatusBar.x; fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$X"; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O1 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tfq" test-fitquestion.m
"$W/tfq" || fails=1
check "an open's URL and actions (review 1.8.1, 2): the hand-over waits with the launch while Fit's question holds it, starts at once otherwise, and the answer starts it right after the launch" \
  "awk '/^- \\(void\\)_handleOpenApplicationRequest:\\(id\\)request options:\\(id\\)options activationSettings:\\(id\\)settings origin:\\(id\\)origin withResult:\\(id\\)result \\{/{f=1} f&&/DMWindowedLaunch\\(bundleID\\);/{a=1} f&&a&&/void \\(\\^deliver\\)\\(void\\) = \\^\\{ if \\(url\\) DMDeliverURLToWindow\\(bundleID, url, 0\\); if \\(actions\\) DMDeliverActionsToWindow\\(bundleID, actions, 0\\); \\};/{b=1} f&&b&&/!MSBDFitHoldAfterLaunch\\(gSidePromptCtx, bundleID, deliver\\)\\) deliver\\(\\);/{print \"ok\"; exit} f&&/^}/{exit}' $X | grep -q ok \
   && [ \$(grep -c 'DMDeliverURLToWindow(bundleID, url, 0)' $X) = 1 ] && [ \$(grep -c 'DMDeliverActionsToWindow(bundleID, actions, 0)' $X) = 1 ] \
   && grep -A1 -F '        launch(f);' $X | grep -qF 'MSBDFitRunAfterLaunch(c);'"
check "the answer (review 1.8.1, 8): the lock state read again before the launch it holds starts, every engine's (the held launch on Aerial, Zetsu and MilkyWay4; Stage Manager's held open, not its question about a window already up)" \
  "fn 'static void DMShowSidePrompt(NSMutableDictionary *ctx, BOOL rebuilt) {' | awk '/if \\(DMLaunchWaitsForBack\\(c\\[@\"prelaunch\"\\] != nil \\|\\| \\[c\\[@\"heldOpen\"\\] boolValue\\]\\)\\) \\{/{a=1} a&&/DMHoldUntilBack\\(\\^\\{ DMSideChoiceFinish\\(c, side\\); \\}\\);/{b=1} b&&/^            DMSideChoiceFinish\\(c, side\\);\$/{print \"ok\"; exit}' | grep -q ok \
   && fn 'static void DMSMFitAskThen(NSString *bundle, NSString *leftB, NSString *rightB, void (^open)(void)) {' | grep -qF 'gSidePromptCtx[@\"heldOpen\"] = @YES;'"
check "  ... the read: the screen off, off since the user was last back, or locked; it waits with every other follow-up of the user's return, and on if gone again" \
  "fn 'static BOOL DMLaunchWaitsForBack(BOOL heldLaunch) {' >/dev/null; grep -qF 'static BOOL DMLaunchWaitsForBack(BOOL heldLaunch) { return MSBDFitLaunchWaitsForBack(heldLaunch, gDMScreenOff, gDMOffSinceBack, DMLockUp(DMSBManager(\"SBLockScreenManager\"))); }' $X \
   && fn 'static void DMBackAfterScreenOff(NSString *why, double zetsuDelay) {' | awk '/gDMOffSinceBack = NO;/{a=NR} /DMRunHeldForBack\\(\\);/{b=NR} /if \\(gStockBar/{c=NR} END{exit !(a && b == a + 1 && c > b)}' \
   && fn 'static void DMRunHeldForBack(void) {' | grep -qF 'if (gDMScreenOff || gDMOffSinceBack) DMHoldUntilBack(go); else go();'"
check "the third window is asked about on Aerial, Zetsu and MilkyWay4 (not Aerial alone)" \
  "fn 'static BOOL DMThirdWindowSides(NSString *bundleID, NSString **leftOut, NSString **rightOut) {' | grep -q '(engine != DMEngineAerial && engine != DMEngineZetsu && engine != DMEngineMilkyWay)' && ! fn 'static BOOL DMThirdWindowSides(NSString *bundleID, NSString **leftOut, NSString **rightOut) {' | grep -q 'DMActiveEngine() != DMEngineAerial ||'"
check "the question comes before every engine's launch into a window (MilkyWay4's, Zetsu's and Aerial's)" \
  "fn 'static BOOL DMWindowedLaunch(NSString *bundleID) {' | awk '/DMPromptBeforeLaunch\\(b, leftB, rightB, \\^\\(CGRect f\\) \\{ DMLaunchIntoTile\\(b, f\\); \\}\\);/ {q=NR} /DMLaunchAsWindow\\(bundleID\\); return YES;/ {m=NR} /DMZetsuLaunch\\(bundleID\\);/ {z=NR} /DMAerialTrigger\\(bundleID, target\\);/ {a=NR} END {exit !(q && m && z && a && q < m && q < z && q < a)}' && [ \$(fn 'static BOOL DMWindowedLaunch(NSString *bundleID) {' | grep -c 'DMPromptBeforeLaunch(') = 1 ]"
check "the answer opens the app each engine's way, at its tile: MilkyWay4 with its new window's frame, Zetsu's adopt at the tile, Aerial's trigger" \
  "fn 'static void DMLaunchIntoTile(NSString *bundleID, CGRect frame) {' | awk '/gPendingWindowFrame = frame;/ {p=NR} /DMLaunchAsWindow\\(bundleID\\);/ {l=NR} /DMZetsuLaunch\\(bundleID\\);/ {z=NR} /DMAerialTrigger\\(bundleID, frame\\);/ {a=NR} END {exit !(p && l && p < l && z && a)}' && grep -q '^        gPreSideFrame = f;' $X && fn 'static void DMZetsuAdopt(UIWindow *w) {' | grep -q 'BOOL inTile = !asked && DMPreSideTileFor(bundleID, &tile);' && fn 'static void DMZetsuAdopt(UIWindow *w) {' | grep -q 'if (inTile) lastPlace = nil;'"
check "the cascade still applies a choice made before the launch (any engine) rather than asking again" \
  "grep -q 'if (\\[gPreSideBundle isEqualToString:me\\] && CACurrentMediaTime() < gPreSideUntil) {   // (asked before the launch: the choice is applied, not asked again)' $X"
check "the placed window becomes the active one on MilkyWay4 too, after the side question and in the two-window tiling" \
  "fn 'static void DMApplySideChoice(UIView *stage, NSString *newBundle, NSString *leftBundle, NSString *rightBundle, NSString *side) {' | grep -q 'else if (DMActiveEngine() == DMEngineMilkyWay && stage.superview && !stage.hidden) { \\[stage.superview bringSubviewToFront:stage\\]; DMApplyWindowLevel(); }' && [ \$(grep -c 'else if (DMActiveEngine() == DMEngineMilkyWay && stage.superview && !stage.hidden) { \\[stage.superview bringSubviewToFront:stage\\]; DMApplyWindowLevel(); }' $X) = 2 ]"
# ... and on our Stage Manager engine (1.8.1, KT): before the launch everywhere -- the Dock and the App Library (DMSMAddToStage), a Spotlight pick and a link (DMSMOpenRequest)
check "Stage Manager: one rule for the question (two tiles, a third window) on both paths, and one way to ask and then open" \
  "fn 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' | grep -q 'DMSMFitAsksAbout(bundle, stageKeys, &leftB, &rightB)' && fn 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' | grep -q 'DMSMFitAskThen(newB, leftB, rightB, ^{' \
   && fn 'static void DMSMOpenRequest(id self, SEL _cmd, id request, id options, id settings, id origin, id result) {' | grep -q 'DMSMFitAsksAbout(bundle, stageKeys, &leftB, &rightB)'"
check "  ... an open from outside is held for the answer, with everything it carries: SpringBoard's own request runs in the answer's block, or at once when nothing is asked" \
  "fn 'static void DMSMOpenRequest(id self, SEL _cmd, id request, id options, id settings, id origin, id result) {' | grep -q 'DMSMFitAskThen(bundle, leftB, rightB, ^{ o_SMOpenRequest(self, _cmd, request, options, settings, origin, result); });' \
   && fn 'static void DMSMOpenRequest(id self, SEL _cmd, id request, id options, id settings, id origin, id result) {' | tail -2 | grep -q '^    o_SMOpenRequest(self, _cmd, request, options, settings, origin, result);'"
check "  ... the plain rule decides which requests may wait; the Home Screen in front opens alone, no question; Spotlight is put away as it asks" \
  "fn 'static void DMSMOpenRequest(id self, SEL _cmd, id request, id options, id settings, id origin, id result) {' | grep -q 'MSBDSMOpenMayAsk(airDrop, background, gForceFullScreenLaunch, locked, DMHasHomeIcon(bundle), DMAppNeedsFullScreen(bundle), \[inStage containsObject:bundle\], DMMSWSMElsewhere(bundle))' \
   && fn 'static void DMSMOpenRequest(id self, SEL _cmd, id request, id options, id settings, id origin, id result) {' | grep -q 'DMFrontApp()) {' && fn 'static void DMSMOpenRequest(id self, SEL _cmd, id request, id options, id settings, id origin, id result) {' | grep -q 'DMDismissSpotlightSoon();'"
check "  ... installed with the engine, its shape checked (without it: the question once the window is up, as before)" \
  "fn 'static void DMSMOpenRequestInstall(void) {' | grep -q 'DMSMExpect(@encode(void), @encode(id), @encode(id), @encode(id), @encode(id), @encode(id), NULL)' && grep -q '^        DMSMOpenRequestInstall();' $X && grep -q 'sm-fit-third-window-question' $X"
check "  ... asked once: not again for the launch after the answer (gSMSkipFitAsk), nor while that launch is on the way (gSMFitPending)" \
  "fn 'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {' | grep -q 'gSMSkipFitAsk ||' && fn 'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {' | grep -q 'gSMFitPending\[bundle\]'"
check "  ... the answer's launch opens straight into its tile, the other windows moving in the same plan (a choice made only: Fit's look otherwise)" \
  "fn 'static NSArray<NSArray *> *DMSMFitPlanInTiles(NSArray<NSArray *> *plan, id act, NSString *key, NSString *bundle, id desk) {' | grep -q 'if (!gSMFitPending\[bundle\]' \
   && fn 'static void DMSMJoinDesktop(id ctx) {' | grep -q 'NSArray<NSArray \*> \*inTiles = tv ? nil : DMSMFitPlanInTiles(plan, act, key, bundle, desk);' \
   && fn 'static void DMSMJoinDesktop(id ctx) {' | awk '/DMSMFitPlanInTiles\(plan, act, key, bundle, desk\)/{a=NR} /DMSMPlanFitted\(identity, plan\)/{b=NR} END{exit !(a && b > a)}'"
check "a tile is a window's intended place from the start of its slide, a Zetsu window's too: the back-to-its-place passes after an unlock read it, and a launch Fit's question held for the unlock slides the tiles just then" \
  "fn 'static void DMApplyGroupSlots(UIView *fresh) {' | grep -B1 -F 'DMAerialMoveStage(s, f, nil);' | grep -qE '^ +DMSetStageIntent\(s, f\);\$' && fn 'void DMZetsuAfterUnlock(void) {' | grep -qF 'NSValue *intent = objc_getAssociatedObject(w, kStageIntentKey);'"
exit $fails
