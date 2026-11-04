#!/bin/bash
# Mac test of where Fit to Window's windows go when its set of windows changes, one rule on every engine (1.8.0 engine parity, KT 3 Nov: a behaviour
# that differs between engines is a bug): the rule (statusbar/FitPlan.h, test-fitorder.m), then every site as built that lays tiles out again --
# a tiled window closed, quit while full screen, back from full screen, gone to another desktop, a desktop's arrangement without a window, a
# window joining (opened, brought from another desktop), the third window's question with no side chosen, a turn after a window left, the
# restore -- on Aerial / Zetsu / MilkyWay4 (StatusBar.x, MacSwitcher.h) and our Stage Manager engine (StatusBar.x, SMFitPlan.h, MacSwitcherSM.h):
# each window that stays keeps its place, a new one takes the first tile; no site hands out the default tiles in an order of its own.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tfo" test-fitorder.m
"$W/tfo"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; MS=../statusbar/MacSwitcher.h; MSM=../statusbar/MacSwitcherSM.h; P=../statusbar/SMFitPlan.h
fn() { awk -v head="$2" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$1" > "$W/fn"; [ -s "$W/fn" ]; }   # (one function of a file, from its first line to its closing brace)
check "the rule is FitPlan.h's, included by StatusBar.x before SMFitPlan.h and by SMFitPlan.h (whose DMSMFitPlanDecide runs it)" \
  "awk '/^#include \"FitPlan.h\"/{f=NR} /^#include \"SMFitPlan.h\"/{s=NR} END{exit !(f && s == f + 1)}' $S && grep -q '^#include \"FitPlan.h\"' $P \
   && grep -q '^static NSDictionary<NSString \*, NSString \*> \*MSBDFitPlanKeepingPlaces(NSArray<NSString \*> \*windows, NSDictionary<NSString \*, NSString \*> \*was) {' ../statusbar/FitPlan.h"
check "one list of default tiles (DMDefaultSlotNames is FitPlan.h's), and no plan of its own left anywhere (DMFitPlanAfterLeave gone)" \
  "grep -q '^static NSArray<NSString \*> \*DMDefaultSlotNames(NSUInteger n) { return MSBDFitDefaultTiles(n); }' $S && ! grep -q 'DMFitPlanAfterLeave' $S $MS $MSM $P"
check "Fit switched on (a fresh tiling, nothing to keep): DMAssignDefaultSlots is the rule with no tiles, called only for that -- DMTileOpenWindows and a desktop that comes with Fit switched on while it was away" \
  "grep -q '^static void DMAssignDefaultSlots(void) { gFitSlots = \[MSBDFitPlanKeepingPlaces(gFitGroup, nil) mutableCopy\]; }' $S \
   && [ \$(grep -c 'DMAssignDefaultSlots();' $S) = 1 ] && fn $S 'static void DMTileOpenWindows(void) {' && grep -q '    DMAssignDefaultSlots();' \$W/fn \
   && [ \$(grep -c 'DMAssignDefaultSlots();' $MS) = 1 ] && grep -q 'if (gFitGroup.count >= 2) DMAssignDefaultSlots();' $MS"
check "a changed group keeps its places: DMAssignTilesKeepingPlaces gives the rule the group's tiles, the fresh window's own taken out (it is new)" \
  "fn $S 'static void DMAssignTilesKeepingPlaces(NSString *fresh) {' && grep -q 'NSMutableDictionary<NSString \*, NSString \*> \*was = \[gFitSlots mutableCopy\] ?: \[NSMutableDictionary dictionary\];' \$W/fn \
   && grep -q 'if (fresh.length) \[was removeObjectForKey:fresh\];' \$W/fn && grep -q 'gFitSlots = \[MSBDFitPlanKeepingPlaces(gFitGroup, was) mutableCopy\];' \$W/fn"
check "Aerial / Zetsu / MilkyWay4: a tiled window closed -- the windows left keep their places (one fills)" \
  "fn $S 'static void DMWatchFitClosures(void) {' && awk '/^    gFitGroup = left;\$/{g=NR} /^    DMAssignTilesKeepingPlaces\(nil\);\$/{a=NR} END{exit !(g && a == g + 1)}' \$W/fn && ! grep -q 'DMAssignDefaultSlots\|@\"fill\"' \$W/fn"
check "  ... the app that went full screen out of the tiles quit: the same" \
  "fn $S 'static void DMFitFullScreenAppGone(NSString *bundleID) {' && awk '/^    gFitGroup = g;\$/{g=NR} /^    DMAssignTilesKeepingPlaces\(nil\);\$/{a=NR} END{exit !(g && a == g + 1)}' \$W/fn"
check "  ... back from full screen with another window gone meanwhile: the arrangement it left, each keeping its place" \
  "fn $S 'static void DMFitRejoinAfterFullScreen(NSString *bundleID) {' && grep -q 'gFitSlots = g.count == old.count ? \[oldSlots mutableCopy\] : \[MSBDFitPlanKeepingPlaces(g, oldSlots) mutableCopy\];' \$W/fn"
check "  ... a window joins (DMCascadeStage): it takes the first tile, the others keep their places" \
  "fn $S 'static void DMCascadeStage(UIView *stage) {' && awk '/\[gFitGroup insertObject:me atIndex:0\];/{i=NR} /DMAssignTilesKeepingPlaces\(me\);/{a=NR} END{exit !(i && a == i + 2)}' \$W/fn && ! grep -q 'DMAssignDefaultSlots' \$W/fn"
check "  ... the third window's question with no side chosen: the new one first, the two tiles kept as places (the Stage Manager engine's default too)" \
  "fn $S 'static void DMSetSideChoiceGroup(NSString *newBundle, NSString *leftBundle, NSString *rightBundle, NSString *side) {' \
   && grep -q 'gFitSlots = \[MSBDFitPlanKeepingPlaces(gFitGroup, @{leftBundle: @\"left\", rightBundle: @\"right\"}) mutableCopy\];' \$W/fn && ! grep -q 'DMAssignDefaultSlots' \$W/fn"
check "  ... a turn after a window left the group: the same rule (no order on the screen of its own any more)" \
  "fn $S 'static void DMRelayoutForOrientation(CGSize oldSize, CGSize newSize) {' && awk '/if \(tiled && gFitSlots.count != gFitGroup.count\) \{/{b=NR} /^        DMAssignTilesKeepingPlaces\(nil\);/{a=NR} END{exit !(b && a > b && a < b + 6)}' \$W/fn \
   && ! grep -q 'in their order on the screen\|DMAssignDefaultSlots' \$W/fn"
check "  ... the windows brought back after a respring, one without a saved tile: the others keep theirs" \
  "fn $S 'static void DMFinishRestore(NSDictionary *state) {' && grep -q 'if (gFitSlots.count != group.count) DMAssignTilesKeepingPlaces(nil);' \$W/fn"
check "  ... Mac Switcher: a window gone to another desktop (the tiles here close up), and joining that desktop's (new there: its tile on this one taken out)" \
  "fn $MS 'static BOOL DMMSWFitMove(NSString *b, NSInteger toId) {' && grep -q 'gFitSlots = \[MSBDFitPlanKeepingPlaces(left, gFitSlots) mutableCopy\];' \$W/fn \
   && grep -q 'NSMutableDictionary \*had = \[fit\[@\"slots\"\] isKindOfClass:\[NSDictionary class\]\] ? \[fit\[@\"slots\"\] mutableCopy\] : \[NSMutableDictionary dictionary\];' \$W/fn \
   && awk '/\[had removeObjectForKey:b\];/{r=NR} /\[slots addEntriesFromDictionary:MSBDFitPlanKeepingPlaces\(group, had\)\];/{a=NR} END{exit !(r && a == r + 1)}' \$W/fn"
check "  ... a desktop's arrangement without a window (brought here, quit), and a window brought here joining these tiles" \
  "fn $MS 'static NSDictionary *DMMSWFitWithout(NSDictionary *fit, NSString *b) {' && grep -q 'nf\[@\"slots\"\] = MSBDFitPlanKeepingPlaces(left, \[fit\[@\"slots\"\] isKindOfClass:\[NSDictionary class\]\] ? fit\[@\"slots\"\] : nil);' \$W/fn \
   && fn $MS 'static BOOL DMMSWFitBringHere(NSString *b, NSInteger fromId, BOOL join, NSString **askLeft, NSString **askRight) {' && grep -q 'DMAssignTilesKeepingPlaces(b);' \$W/fn && ! grep -q 'DMAssignDefaultSlots' \$W/fn"
check "Stage Manager: a closed window forgotten -- the windows left keep their places (not the order of their last use)" \
  "fn $S 'static void DMSMFitForgetClosed(NSString *opening) {' && grep -q 'gSMFitSlots = left.count ? \[MSBDFitPlanKeepingPlaces(left, gSMFitSlots) mutableCopy\] : nil;' \$W/fn"
check "  ... Stage Manager's own Close lays out the same plan in its transition" \
  "fn $S 'static void DMSMPlacesInClose(id ctx) {' && grep -q 'plan = MSBDFitPlanKeepingPlaces(keys, gSMFitSlots);' \$W/fn"
check "  ... the Fit tick's new set and the launch's open-in-tile decide with DMSMFitPlanDecide, whose new tiles are the rule's for the newest windows" \
  "fn $P 'static NSDictionary<NSString *, NSString *> *DMSMFitPlanDecide(' && grep -q 'NSUInteger n = MIN(bundles.count, defaults.count);' \$W/fn \
   && grep -q 'return n ? MSBDFitPlanKeepingPlaces(\[bundles subarrayWithRange:NSMakeRange(0, n)\], slots) : @{};' \$W/fn && ! grep -q 'plan\[bundles\[i\]\] = defaults\[i\]' \$W/fn \
   && fn $S 'static void DMSMFitTick(BOOL force) {' && grep -q 'NSDictionary \*plan = DMSMFitPlanDecide(gSMFitSlots, bundles, DMDefaultSlotNames(MIN((NSUInteger)4, bundles.count)), &how);' \$W/fn \
   && fn $S 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' && grep -q 'DMSMFitPlanDecide(slotsNow, part, DMDefaultSlotNames(part.count), &how)' \$W/fn"
check "  ... the third window's question with no side chosen, before the launch and at the Fit tick: the two tiles are kept as places (they were dropped: the last use decided)" \
  "[ \$(grep -c 'gSMFitSlots = \[@{leftB: @\"left\", rightB: @\"right\"} mutableCopy\];' $S) = 2 ] && ! grep -q 'gSMFitSlots = nil;   // (no choice' $S"
check "  ... the desktop's only window: it fills (the rule's one window)" \
  "fn $S 'static void DMSMFitTick(BOOL force) {' && grep -q 'gSMFitSlots = \[MSBDFitPlanKeepingPlaces(@\[one\], nil) mutableCopy\];' \$W/fn"
check "  ... Mac Switcher: joining another desktop's tiles (new there), its arrangement without a window brought here, the tiles left when one goes" \
  "fn $MSM 'static void DMMSWSMFitJoin(NSString *b, NSInteger toId) {' && awk '/NSMutableDictionary \*had = \[was mutableCopy\];/{h=NR} /\[had removeObjectForKey:b\];/{r=NR} /\[slots addEntriesFromDictionary:MSBDFitPlanKeepingPlaces\(group, had\)\];/{a=NR} END{exit !(h && r == h + 1 && a == r + 1)}' \$W/fn \
   && fn $MSM 'static void DMMSWSMFitBringHere(NSString *k, NSInteger fromId) {' && grep -q 'slots = MSBDFitPlanKeepingPlaces(left, was);' \$W/fn \
   && fn $MSM 'static void DMMSWSMMoveFinish(NSString *b, NSInteger toId) {' && grep -q 'NSMutableDictionary<NSString \*, NSString \*> \*plan = left.count ? \[MSBDFitPlanKeepingPlaces(left, was) mutableCopy\] : nil;' \$W/fn"
check "no other site hands out the default tiles in an order: DMDefaultSlotNames only counts tiles (DMSMFitPlanDecide's two callers), sorts a desktop's slots (MacSwitcherSM.h) or repairs overlapping tiles by their frames" \
  "[ \$(grep -c 'DMDefaultSlotNames(' $S) = 4 ] && [ \$(grep -c 'DMDefaultSlotNames(' $MS) = 0 ] && [ \$(grep -c 'DMDefaultSlotNames(' $MSM) = 2 ] \
   && fn $S 'static void DMFitRepairOverlappingSlots(void) {' && grep -q 'NSArray \*names = DMDefaultSlotNames(g.count);' \$W/fn"
check "a crash in the rule is the windowing's (the crash guard turns Windowing off), not Resize Apps to Fit Windows' (^DMFit)" \
  "grep -q '^file MacStatusBarCore \^(WindowCards|WindowMinSize|WindowSize|FitPlan|SBLaunchRule)\\\\.h\$ windowingEnabled' crashmap-rules.txt && ! grep -q '^static[^(]* \*\?DMFit[A-Za-z]*(' ../statusbar/FitPlan.h"
[ $fails = 0 ] && echo "test-fitorder wiring: all passed" || { echo "test-fitorder wiring: FAILED"; exit 1; }
