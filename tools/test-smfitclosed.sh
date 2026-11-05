#!/bin/bash
# Mac test of Fit to Window forgetting the windows that closed with the Stage Manager engine (1.8.0 engine parity, KT 3 Nov: a behaviour that
# differs between engines is a bug): the rule (statusbar/SMFitPlan.h, test-smfitclosed.m), then its sites in StatusBar.x as built -- Fit's every
# look asks it, also with nothing on screen, and so does every way a window opens; the windows left close up as on every engine; No Fit, the
# arrangement left for full screen and the memory per desktop lose a closed window too; a minimized window keeps its tile and its No Fit.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tsfc" test-smfitclosed.m
"$W/tsfc"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $S > "$W/fn"; }   # (one function of StatusBar.x, from its first line to its closing brace)
check "the check reads every window of every recent stage, the hidden ones too (no display or minimized filter), and takes nothing for closed when a stage or a window can't be read" \
  "fn 'static void DMSMFitForgetClosed(NSString *opening) {' && grep -q 'NSArray \*stages = DMSMRecentStages();' \$W/fn && grep -q 'if (!stages) return;' \$W/fn \
   && grep -q 'NSDictionary \*m = DMSMStageItemsMap(al);' \$W/fn && grep -q 'if (!m) return;' \$W/fn && grep -q 'if (!k.length) return;' \$W/fn \
   && ! grep -q 'DMSMIsMainIdentity\|DMSMIsMinimized' \$W/fn && grep -q 'if (gMSWSwitching || DMSMGestureLive()) return;' \$W/fn \
   && grep -q 'NSSet<NSString \*> \*closed = DMSMFitClosedKeys(remembered, present, \[NSSet setWithArray:gSMFitPending.allKeys ?: @\[\]\]);' \$W/fn"
check "  ... everything Fit remembers is asked about: the tiles, No Fit, full screen's, the memory per desktop" \
  "grep -q 'NSMutableSet<NSString \*> \*remembered = \[NSMutableSet setWithArray:gSMFitSlots.allKeys ?: @\[\]\];' \$W/fn && grep -q 'if (gSMFreeWindows) \[remembered unionSet:gSMFreeWindows\];' \$W/fn \
   && grep -q 'if (gSMFitWentFull) \[remembered unionSet:gSMFitWentFull\];' \$W/fn && grep -q '\[remembered addObjectsFromArray:gSMFitSlotsBeforeFull.allKeys ?: @\[\]\];' \$W/fn \
   && grep -q 'for (NSString \*desk in gSMFitByDesk) \[remembered addObjectsFromArray:\[desk componentsSeparatedByString:@\"\\\\n\"\]\];' \$W/fn"
check "a closed tile: the windows left close up as on every engine (FitPlan.h, each keeping its place), laid out at Fit's next look" \
  "grep -q 'NSArray<NSString \*> \*left = DMSMFitLeftAfterClose(gSMFitSlots, closed, times);' \$W/fn && grep -q 'gSMFitSlots = left.count ? \[MSBDFitPlanKeepingPlaces(left, gSMFitSlots) mutableCopy\] : nil;' \$W/fn \
   && grep -q 'gSMFitLookAgain = YES;' \$W/fn && grep -q 'DM_FEATURE_MARK(\"sm-fit-closed-forgotten\");' \$W/fn \
   && grep -q 'times\[k\] = @(MAX(\[times\[k\] longLongValue\], (long long)DMSMAttrTimeOr(m\[it\], 0)));' \$W/fn"
check "  ... No Fit, the arrangement left for full screen and the memory per desktop lose it too" \
  "grep -q 'for (NSString \*k in closed) { \[gSMFreeWindows removeObject:k\]; \[gSMFitWentFull removeObject:k\]; \[gSMFitLoose removeObject:k\]; }' \$W/fn && grep -q 'if (leftFull) gSMFitSlotsBeforeFull = nil;' \$W/fn \
   && grep -q 'NSDictionary \*mem = DMSMFitMemoryWithout(gSMFitByDesk, closed);' \$W/fn && grep -q 'for (NSString \*d in \[gSMFitByDeskOrder copy\]) if (!mem\[d\]) \[gSMFitByDeskOrder removeObject:d\];' \$W/fn"
check "Fit's look asks it after a transaction in flight and BEFORE every other wait (a turn, Spotlight, the App Switcher, the Home Screen, full screen): nothing on screen is no reason to keep a closed window" \
  "fn 'static void DMSMFitTick(BOOL force) {' && awk '/if \(DMSMWorkspaceBusy\(\)\) \{ if \(force\) forceWaiting = YES; return; \}/{b=NR} /^    DMSMFitForgetClosed\(nil\);/{c=NR} /if \(DMSMTurnSettling\(\)\)/{t=NR} /if \(!DMFrontApp\(\)\) return;/{h=NR} END{exit !(b && c == b + 1 && t > c && h > c)}' \$W/fn"
check "  ... and lays the windows left out again when it forgot a tile, though the set on screen is the same" \
  "grep -q 'if (!force && !gSMFitLookAgain && \[set isEqualToArray:lastSet ?: @\[\]\]) return;' \$W/fn && grep -q '    gSMFitLookAgain = NO;' \$W/fn \
   && grep -q 'NSDictionary \*slotsNow = DMSMFitSlotsFor(gSMFitSlots, gSMFitByDesk, bundles);' \$W/fn && ! grep -q 'static NSMutableDictionary<NSString \*, NSDictionary \*> \*byDesk;' \$W/fn"
check "  ... and its one-window rule is the one the Mac test plays: the desktop's only window fills only when its arrangement says so" \
  "grep -q 'if (one && gSMFitSlots.count == 1 && \[gSMFitSlots\[one\] isEqualToString:@\"fill\"\]) {' \$W/fn"
check "No Fit is no longer forgotten for a window only out of sight (minimized, another desktop): the not-on-screen rule is gone" \
  "! grep -q 'if (!\[onScreen containsObject:b\] && !gSMFitPending\[b\]) \[gSMFreeWindows removeObject:b\];' $S"
check "every way a window opens asks it first: SpringBoard's launches (DMSMJoinDesktop, before the Mac Switcher's join) our icon taps (DMSMAddToStage, before Fit's question and the open-in-tile) and the opens from outside (DMSMOpenRequest, before Fit's question)" \
  "fn 'static void DMSMJoinDesktop(id ctx) {' && awk '/NSString \*key = DMSMEntityKey\(act\) \?: bundle;/{k=NR} /DMSMFitForgetClosed\(key\);/{c=NR} /if \(DMMSWSMJoin\(ctx, act, key\)\) return;/{j=NR} END{exit !(k && c == k + 1 && j == c + 1)}' \$W/fn \
   && fn 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' && awk '/DMSMFitForgetClosed\(bundle\);/{c=NR} /DMSMFitAsksAbout\(bundle, stageKeys, &leftB, &rightB\)/{q=NR} /NSMutableDictionary \*slotsNow = gSMFitSlots/{o=NR} END{exit !(c && q > c && o > c)}' \$W/fn \
   && fn 'static void DMSMOpenRequest(id self, SEL _cmd, id request, id options, id settings, id origin, id result) {' && awk '/DMSMFitForgetClosed\(bundle\);/{c=NR} /DMSMFitAsksAbout\(bundle, stageKeys, &leftB, &rightB\)/{q=NR} END{exit !(c && q > c)}' \$W/fn"
check "the rule lives in SMFitPlan.h with the window keys (SMWindowKey.h), declared ahead of its callers" \
  "grep -q '#include \"SMWindowKey.h\"' ../statusbar/SMFitPlan.h && grep -q 'static NSSet<NSString \*> \*DMSMFitClosedKeys(id<NSFastEnumeration> keys, NSSet<NSString \*> \*present, NSSet<NSString \*> \*pending) {' ../statusbar/SMFitPlan.h \
   && grep -q '^static void DMSMFitForgetClosed(NSString \*opening);' $S"
[ $fails = 0 ] && echo "test-smfitclosed wiring: all passed" || { echo "test-smfitclosed wiring: FAILED"; exit 1; }
