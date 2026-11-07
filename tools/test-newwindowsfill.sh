#!/bin/bash
# Mac test of New Windows Open at Fill (1.8.3 item 2, KeyPilot's author's design: Settings > Windows & Multitasking, off unless switched on): the rule
# (common/WindowSize.h, test-newwindowsfill.c), then the sites in the code as built -- every engine's way of opening a window with no place of its
# own asks the one opening frame (the windowed launch, Aerial's cascade, Zetsu's and MilkyWay4's new window, the green light's way back, the Stage
# Manager join), applied where a window opens and never on a layout pass, Fit to Window leaves such a window out on every engine (no side question),
# and the Settings row.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tnf" test-newwindowsfill.c
"$W/tnf"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; PL=../statusbar/macstatusbarprefs/Resources/Windows.plist
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $S > "$W/fn"; }
check "the switch: read with the other preferences, off unless switched on" \
  "grep -q 'CFPropertyListRef fr = CFPreferencesCopyValue(CFSTR(kMSBDNewWindowsFillKey), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
   && grep -q 'static BOOL gNewWindowsFill = NO;' $S"
check "one opening frame: Window Size's window, or Fill with the switch on (the engine's frame: Aerial 5.x's stage)" \
  "fn 'static CGRect DMOpeningWindowFrame(void) {' && grep -q 'if (!MSBDNewWindowAtFill(gNewWindowsFill, false, false)) return DMNewWindowFrame();' \$W/fn && grep -q 'return DMLayoutFrame(@\"fill\");' \$W/fn"
check "asked by every engine's opening: the windowed launch (twice), Zetsu's and MilkyWay4's new window, Aerial's cascade, the green light's way back" \
  "[ \$(grep -c 'DMOpeningWindowFrame()' $S) = 6 ] && fn 'static BOOL DMWindowedLaunch(NSString *bundleID) {' && grep -q 'CGRect target = DMOpeningWindowFrame();' \$W/fn \
   && fn 'static void DMZetsuAdopt(UIWindow *w) {' && grep -q 'lastPlace.CGRectValue : DMOpeningWindowFrame()));' \$W/fn \
   && fn 'static BOOL DMEnlargeNewWindow(UIView *window) {' && grep -q ': DMOpeningWindowFrame();' \$W/fn \
   && fn 'static void DMWindowLayout(NSString *name) {' && grep -q 'if (gPreferRememberedFrame) target = gLastWindowFrames\\[bundleID\\] ? gLastWindowFrames\\[bundleID\\].CGRectValue : DMOpeningWindowFrame();' \$W/fn"
check "  ... and nowhere else: No Fit's window and a window put back at the standard place stay Window Size's" \
  "fn 'static CGRect DMNoFitFrame(void) {' && grep -q 'return DMNewWindowFrame();' \$W/fn && ! grep -q 'DMOpeningWindowFrame' \$W/fn"
check "Aerial, Zetsu, MilkyWay4: where a window is adopted (DMCascadeStage) one with no place of its own is put at Fill (one an engine opened elsewhere too), kept there, out of Fit's tiles" \
  "fn 'static void DMCascadeStage(UIView *stage) {' && grep -q 'if (MSBDNewWindowAtFill(gNewWindowsFill, ownPlace || (DMActiveEngine() == DMEngineAerial && DMOpensAtOwnPlace(me)), preLaunched)) {' \$W/fn \
   && grep -q 'if (fabs(base.origin.x - usable.origin.x) > 1.0 || fabs(base.origin.y - usable.origin.y) > 1.0 || fabs(base.size.width - usable.size.width) > 1.0 || fabs(base.size.height - usable.size.height) > 1.0) {' \$W/fn && grep -q 'if (!DMIsZetsuWindow(stage)) DMSetStageIntent(stage, usable);' \$W/fn && grep -q 'if (fitOn) DMMarkFreeWindow(me);' \$W/fn \
   && awk '/if \(MSBDNewWindowAtFill\(gNewWindowsFill, ownPlace \|\| /{a=NR} /if \(fitOn && \[gFreeWindows containsObject:me\]\) goto regularWindow;/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && grep -q '(gWindowSizeChoice != MSBDWindowSizeDefault || gNewWindowsFill) && !gLastWindowFrames\\[me\\];' \$W/fn"
check "Stage Manager: the join's window with no size of its own is Fill, not moved on, out of Fit's tiles (a free window)" \
  "fn 'static id DMSMJoinAttributes(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage) {' && grep -q 'BOOL atFill = MSBDNewWindowAtFill(gNewWindowsFill, false, false);' \$W/fn \
   && grep -q 'CGRect placed = atFill ? opening : MSBDWindowCascadeIn(opening, others, n, u, NO, &how);' \$W/fn \
   && grep -q 'if (DMFitEnabled()) { if (!gSMFreeWindows) gSMFreeWindows = \\[NSMutableSet set\\]; \\[gSMFreeWindows addObject:key\\]; }' \$W/fn"
check "no side question for a window that opens at Fill, before its launch on every engine" \
  "fn 'static BOOL DMThirdWindowSides(NSString *bundleID, NSString **leftOut, NSString **rightOut) {' && grep -q 'if (!MSBDFitTakesOpening(YES, MSBDNewWindowAtFill(gNewWindowsFill, DMOpensAtOwnPlace(bundleID), NO))) return NO;' \$W/fn \
   && fn 'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {' && grep -q 'if (!MSBDFitTakesOpening(YES, MSBDNewWindowAtFill(gNewWindowsFill, DMSMOpensAtOwnSize(bundle), NO))) return NO;' \$W/fn"
check "one 'opens at its own place' per engine for New Windows Open at Fill, asked before the launch and as the window comes (review 1.8.3 F5) -- for the Fill decision only: the cascade's own place is 1.8.2.2's (review P2-4)" \
  "grep -q 'static BOOL DMOpensAtOwnPlace(NSString \\*bundleID) { return bundleID.length && gLastWindowFrames\\[bundleID\\] != nil; }' $S \
   && fn 'static void DMCascadeStage(UIView *stage) {' && grep -q 'if (MSBDNewWindowAtFill(gNewWindowsFill, ownPlace || (DMActiveEngine() == DMEngineAerial && DMOpensAtOwnPlace(me)), preLaunched)) {' \$W/fn \
   && grep -q 'if (remembered) ownPlace = YES;' \$W/fn && [ \$(grep -c 'DMOpensAtOwnPlace(' \$W/fn) = 1 ] && [ \$(grep -c 'DMOpensAtOwnPlace(' $S) = 3 ]"
# The cascade with every new switch off is 1.8.2.2's (review 1.8.3 P2-4): DMCascadeStage as built, its New Windows Open at Fill parts taken out --
# the Fill block, and the three lines that read the switch, each the same as 1.8.2.2's with it off (DMOpeningWindowFrame is DMNewWindowFrame then)
# -- equals 1.8.2.2's (cascade-fixtures/DMCascadeStage-1.8.2.2.txt, from d5f83ff). No iPad has Aerial 3.0 (all four: Aerial 5.1, 7 Nov).
fill_off_is_1822() {
  fn 'static void DMCascadeStage(UIView *stage) {'
  awk 'index($0, "    // New Windows Open at Fill (1.8.3 item 2") == 1 {skip=1} skip && /^    }$/ {skip=0; next} !skip {print}' "$W/fn" \
    | sed -e 's/(gWindowSizeChoice != MSBDWindowSizeDefault || gNewWindowsFill)/gWindowSizeChoice != MSBDWindowSizeDefault/' \
          -e 's|DMOpeningWindowFrame();   // (where a new window opens: Window Size, or Fill)|DMNewWindowFrame();   // (where a new window opens: Window Size)|' \
          -e 's/ : gNewWindowsFill ? @"Fill (New Windows Open at Fill)" : \[NSString/ : [NSString/' > "$W/cas"
  diff -q "$W/cas" cascade-fixtures/DMCascadeStage-1.8.2.2.txt >/dev/null
}
check "with every new switch off the cascade (Aerial 3.0 and 5.x, Zetsu, MilkyWay4) is 1.8.2.2's, line for line, but for what reads New Windows Open at Fill (review 1.8.3 P2-4)" \
  "fill_off_is_1822 && fn 'static CGRect DMOpeningWindowFrame(void) {' && grep -q 'if (!MSBDNewWindowAtFill(gNewWindowsFill, false, false)) return DMNewWindowFrame();' \$W/fn"
check "  ... Stage Manager's: the side question and the join read the same size of its own (its own window's, one from before our full screen; not one Stage Manager works out itself)" \
  "grep -q 'static BOOL DMSMOpensAtOwnSize(NSString \\*key) { return DMSMAttrsOwnSize(DMSMOwnAttrsFor(key, YES, NULL)); }' $S \
   && fn 'static id DMSMJoinAttributes(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage) {' && grep -q 'id own = DMSMOwnAttrsFor(key, windowed, &ownItem);' \$W/fn && grep -q 'BOOL fresh = !DMSMAttrsOwnSize(own);' \$W/fn \
   && fn 'static BOOL DMSMAttrsOwnSize(id attrs) {' && grep -q 'return attrs && !DMSMAttrsFullScreen(attrs) && DMSMAttrAttributedSize(attrs, &sz) && sz.type != 3 && sz.normalizedSize.width > 0 && sz.normalizedSize.height > 0;' \$W/fn"
check "never on a layout pass: the layouts and Fit's own tiling ask no opening frame" \
  "fn 'static void DMApplyGroupSlots(UIView *fresh) {' && ! grep -q 'gNewWindowsFill\\|DMOpeningWindowFrame' \$W/fn && fn 'static void DMSMFitTick(BOOL force) {' && ! grep -q 'gNewWindowsFill' \$W/fn"
check "the Settings row: Windows & Multitasking, a switch of its own group, off by default, posted to SpringBoard" \
  "plutil -convert json -o - $PL | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; r=[x for x in it if x.get(\"key\")==\"newWindowsFill\"]; sys.exit(0 if len(r)==1 and r[0][\"cell\"]==\"PSSwitchCell\" and r[0][\"default\"]==False and r[0][\"label\"]==\"New Windows Open at Fill\" and r[0][\"PostNotification\"]==\"com.besiktasliseba.macstatusbar/prefsChanged\" and r[0][\"defaults\"]==\"com.besiktasliseba.macstatusbar\" else 1)'"
exit $fails
