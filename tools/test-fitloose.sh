#!/bin/bash
# Mac test of the windows past Fit to Window's four tiles and of a turn with a tiled window minimized, one rule on every engine (1.8.0 engine
# parity, KT 3 Nov: a behaviour that differs between engines is a bug): the rules (statusbar/FitPlan.h, SMFitPlan.h, test-fitloose.m: both engines
# played event by event), then their sites as built -- Aerial / Zetsu / MilkyWay4 when a window opens (StatusBar.x DMCascadeStage) or comes from
# another desktop (MacSwitcher.h DMMSWFitBringHere) and at a turn (DMRelayoutForOrientation); the Stage Manager engine at Fit's look (DMSMFitTick),
# the launch's open-in-tile and its question (DMSMAddToStage), Stage Manager's own Close (DMSMPlacesInClose), Fit forgetting a closed window
# (DMSMFitForgetClosed), a window brought from another desktop (MacSwitcherSM.h) and Fit switched off.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tfl" test-fitloose.m
"$W/tfl"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; MS=../statusbar/MacSwitcher.h; MSM=../statusbar/MacSwitcherSM.h; P=../statusbar/SMFitPlan.h; F=../statusbar/FitPlan.h
fn() { awk -v head="$2" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$1" > "$W/fn"; [ -s "$W/fn" ]; }   # (one function of a file, from its first line to its closing brace)
check "the rules are FitPlan.h's (a window that opens, a turn) and SMFitPlan.h's (Stage Manager's look, which plays the first one window by window)" \
  "grep -q '^static NSArray<NSString \*> \*MSBDFitWhenOneOpens(NSString \*fresh, NSArray<NSString \*> \*tiled, NSArray<NSString \*> \*loose) {' $F \
   && grep -q '^static inline BOOL MSBDFitTileStaysAtTurn(BOOL there, BOOL leaving, BOOL noFit, BOOL onScreen, BOOL minimized) {' $F \
   && fn $P 'static NSArray<NSString *> *DMSMFitTakingPart(' && grep -q 'NSArray<NSString \*> \*joined = MSBDFitWhenOneOpens(f, part, regular);' \$W/fn"
check "Aerial / Zetsu / MilkyWay4, a window opens: the regular windows (on screen, outside the tiles, not No Fit) newest first, the rule decides, a regular window joins as a new one -- the old count with No Fit windows in it gone" \
  "fn $S 'static void DMCascadeStage(UIView *stage) {' && grep -q 'for (UIView \*o in others.reverseObjectEnumerator) {' \$W/fn \
   && grep -q 'if (b.length && !\[b isEqualToString:me\] && !\[gFitGroup containsObject:b\] && !\[loose containsObject:b\] && DMStageTakesPartInFit(o)) \[loose addObject:b\];' \$W/fn \
   && grep -q 'NSArray<NSString \*> \*joined = MSBDFitWhenOneOpens(me, gFitGroup, loose);' \$W/fn && grep -q 'for (NSString \*b in loose) \[gFitSlots removeObjectForKey:b\];' \$W/fn \
   && awk '/if \(!joined\) \{/{j=NR} /goto regularWindow;/{if (j && !g && NR > j) g=NR} END{exit !(j && g && g <= j + 2)}' \$W/fn \
   && ! grep -q 'if (gFitGroup.count >= 4 || others.count >= 4) {' \$W/fn && ! grep -q 'gFitGroup removeObjectsInRange' \$W/fn"
check "  ... a window brought from another desktop: the same rule" \
  "fn $MS 'static BOOL DMMSWFitBringHere(NSString *b, NSInteger fromId, BOOL join, NSString **askLeft, NSString **askRight) {' && grep -q 'NSArray<NSString \*> \*joined = MSBDFitWhenOneOpens(b, group, loose);' \$W/fn \
   && grep -q 'for (UIView \*s in DMAerialStages().reverseObjectEnumerator) {' \$W/fn && grep -q 'for (NSString \*x in loose) \[gFitSlots removeObjectForKey:x\];' \$W/fn \
   && ! grep -q 'open.count >= 4' \$W/fn"
check "  ... a tile closes: only the tiles close up (the closure watcher's group), a regular window is left where it is" \
  "fn $S 'static void DMWatchFitClosures(void) {' && grep -q 'for (NSString \*b in before) if (!\[closed containsObject:b\] && \[gFitGroup containsObject:b\] && DMStageTakesPartInFit(DMStageForBundle(b))) \[left addObject:b\];' \$W/fn"
check "Stage Manager, Fit's look: the windows that take part from the rule, the regular ones kept from look to look, then the plan for them alone (a window back from full screen counts with the tile it left)" \
  "fn $S 'static void DMSMFitTick(BOOL force) {' && grep -q 'NSArray<NSString \*> \*part = DMSMFitTakingPart(bundles, slotsForPart ?: gSMFitSlots, gSMFitLoose, &looseNow);' \$W/fn \
   && grep -q 'gSMFitLoose = looseNow.count ? \[looseNow mutableCopy\] : nil;' \$W/fn && grep -q 'slotsForPart\[b\] = gSMFitSlotsBeforeFull\[b\];' \$W/fn \
   && awk '/bundles = \[part mutableCopy\];/{b=NR} /NSDictionary \*plan = DMSMFitPlanDecide\(gSMFitSlots, bundles,/{p=NR} /if \(bundles.count < 2\) \{/{o=NR} /if \(!returning && bundles.count == 3 && gSMFitSlots.count == 2 && !force\) \{/{q=NR} END{exit !(b && p > b && o > b && q > b)}' \$W/fn \
   && grep -q 'if (!DMSMEngine() || !DMFitEnabled()) { lastSet = nil; gSMFitAdopt = nil; gSMFitLoose = nil; forceWaiting = NO; return; }' \$W/fn"
check "  ... the set compared from look to look is every window on the desktop (a regular one coming or going is a change)" \
  "awk '/NSArray \*sorted = \[bundles sortedArrayUsingSelector:@selector\(compare:\)\];/{s=NR} /bundles = \[part mutableCopy\];/{b=NR} END{exit !(s && b > s)}' \$W/fn"
check "  ... the desktop back after a respring with windows past the tiles: those in a tile each keep it, the others are regular windows (they were tiled again as a new set, the newest four)" \
  "fn $S 'static void DMSMFitTick(BOOL force) {' && grep -q 'NSArray<NSString \*> \*inTiles = DMSMFitWindowsSittingInTiles(bundles);' \$W/fn \
   && grep -q 'inTiles.count >= 2 && inTiles.count <= 4 && inTiles.count < bundles.count && DMSMFitWindowsInTilesNow(inTiles)' \$W/fn \
   && grep -q 'for (NSString \*b in bundles) if (!tiles\[b\]) \[gSMFitLoose addObject:b\];' \$W/fn \
   && awk '/if \(DMSMFitWindowsInTilesNow\(bundles\)\) \{/{a=NR} /NSArray<NSString \*> \*inTiles = DMSMFitWindowsSittingInTiles\(bundles\);/{b=NR} /laid out for another screen shape -- the iPad turned while SpringBoard restarted/{c=NR} END{exit !(a && b > a && c > b)}' \$W/fn \
   && fn $S 'static NSArray<NSString *> *DMSMFitWindowsSittingInTiles(NSArray<NSString *> *keys) {' && grep -q 'if (f && DMSMSlotNameForFrameIn(f.CGRectValue, stage)) \[in addObject:k\];' \$W/fn"
check "  ... the launch's open-in-tile: the same windows take part, a regular one keeps its place and role, one that joins is regular no more" \
  "fn $S 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' && grep -q 'NSArray<NSString \*> \*part = DMTestFlag(\"/tmp/msb-fitloose-asbuilt\") ? keys : DMSMFitTakingPart(keys, slotsNow, gSMFitLoose, NULL);' \$W/fn \
   && grep -q 'NSDictionary \*plan = \[part containsObject:newKey\] && part.count >= 2 && part.count <= 4 ? DMSMFitPlanDecide(slotsNow, part, DMDefaultSlotNames(part.count), &how) : nil;' \$W/fn \
   && grep -q 'if (plan.count == part.count && how != DMSMFitFourKept && newAttrs) {' \$W/fn && grep -q 'if (!plan\[k\]) continue;   // (a regular window over the tiles' \$W/fn \
   && grep -q 'for (NSString \*k in fitPlanC) \[gSMFitLoose removeObject:k\];' \$W/fn"
check "  ... its third-window question counts the windows that take part, as the other engines (a No Fit window is none)" \
  "grep -q 'DMSMFitAsksAbout(bundle, stageKeys, &leftB, &rightB)' \$W/fn && ! grep -q 'map.count == 2 && gSMFitSlots.count == 2' \$W/fn && awk '/^static BOOL DMSMFitAsksAbout\(/{f=1} f{print} f&&/^}/{exit}' $S > \$W/fa \
   && grep -q 'for (NSString \*k in stageKeys) if (!DMSMKeySetHas(gSMFreeWindows, k)) takingPart++;' \$W/fa && grep -q '!DMFitEnabled() || takingPart != 2 || gSMFitSlots.count != 2' \$W/fa"
check "  ... Stage Manager's own Close: the tiled windows close up in its transition, a regular or No Fit window keeps its own place" \
  "fn $S 'static void DMSMPlacesInClose(id ctx) {' && grep -q 'BOOL over = !gSMFitSlots\[k\] && !DMSMAttrsFullScreen(attrs) && (DMSMKeySetHas(gSMFitLoose, k) || DMSMKeySetHas(gSMFreeWindows, k));' \$W/fn \
   && grep -q 'if (!over && (!gSMFitSlots\[k\] || DMSMAttrsFullScreen(attrs) || DMSMKeySetHas(gSMFreeWindows, k))) fit = NO;' \$W/fn && grep -q 'if (!over) tiledStay++;' \$W/fn \
   && grep -q 'for (NSArray \*w in stay) if (!\[w\[4\] boolValue\]) \[keys addObject:w\[1\]\];' \$W/fn && grep -q 'if (plan && !\[w\[4\] boolValue\]) {' \$W/fn && grep -q 'if (tiledStay > 4 || !tiledStay) fit = NO;' \$W/fn"
check "  ... a regular window that closed is forgotten with the rest (the app's next window, the same key, is a new one)" \
  "fn $S 'static void DMSMFitForgetClosed(NSString *opening) {' && grep -q 'if (gSMFitLoose) \[remembered unionSet:gSMFitLoose\];' \$W/fn \
   && grep -q '\[gSMFitLoose removeObject:k\]; }' \$W/fn && grep -q '!gSMFitLoose.count' \$W/fn"
check "  ... a window brought from another desktop joins here as a window that opens; Fit switched off lets the regular windows go" \
  "fn $MSM 'static void DMMSWSMFitBringHere(NSString *k, NSInteger fromId) {' && grep -q '^    \[gSMFitLoose removeObject:k\];' \$W/fn \
   && fn $S 'static void DMSMSpreadFit(int tries) {' && grep -q 'gSMFitSlots = nil; gSMFitLoose = nil;' \$W/fn"
check "a turn (Aerial / Zetsu / MilkyWay4): a minimized tiled window keeps its tile -- the rule decides who leaves the group; the tiled loop places a minimized one while hidden, not moved on screen" \
  "fn $S 'static void DMRelayoutForOrientation(CGSize oldSize, CGSize newSize) {' \
   && grep -q 'if (asBuilt ? !DMStageTakesPartInFit(s) : !MSBDFitTileStaysAtTurn(s != nil, s && \[objc_getAssociatedObject(s, kStageClosingKey) boolValue\], \[gFreeWindows containsObject:b\], s && !s.hidden && !DMStageMinimized(s), s && DMStageMinimized(s)))' \$W/fn \
   && grep -q 'if (s.hidden || DMStageMinimized(s)) { gStageFrameBypass = YES; s.frame = f; gStageFrameBypass = NO; DMSetStageIntent(s, f); }' \$W/fn \
   && ! grep -q 'for (NSString \*b in \[gFitGroup copy\]) if (!DMStageTakesPartInFit(DMStageForBundle(b))) \[gFitGroup removeObject:b\];' \$W/fn"
check "the debug switches to the old ways (/tmp/msb-fitloose-asbuilt, /tmp/msb-turnmin-asbuilt) are test flags only: compiled out of release builds" \
  "grep -q '^#define DMTestFlag(path) 0' $S && [ \$(grep -c 'DMTestFlag(\"/tmp/msb-fitloose-asbuilt\")' $S) = 3 ] && [ \$(grep -c 'DMTestFlag(\"/tmp/msb-turnmin-asbuilt\")' $S) = 1 ]"
[ $fails = 0 ] && echo "test-fitloose wiring: all passed" || { echo "test-fitloose wiring: FAILED"; exit 1; }
