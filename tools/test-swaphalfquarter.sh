#!/bin/bash
# test-swaphalfquarter.sh: the Window menu's Swap Half and Quarter is there on MilkyWay4 as on Aerial, Zetsu and the Stage Manager engine (1.8.7.3,
# audit L30 of 1.8.7.2) -- see test-swaphalfquarter.m. The row's state and action, the plans, the move and the Swap rows beside it
# (statusbar/StatusBar.x) are cut out of the source (SWQ_SB_X: another copy, e.g. the code before the fix) and run on the Mac (Mac Catalyst) for
# every engine; then a site check (the Window menu's row asks that state); then made-to-fail copies: each breaks one engine's row and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SWQ_SB_X:-../statusbar/StatusBar.x}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

X_FN=('static void DMSetStageFrameSafe(UIView *stage, CGRect f) {'
      'static void DMAerialMoveStage(UIView *stage, CGRect target, void (^done)(void)) {'
      'static NSString *DMSlotNameForFrame(CGRect f) {'
      'static NSString *DMMirrorSlot(NSString *slot, BOOL horizontal) {'
      'static BOOL DMSwapPlan(BOOL horizontal, NSMutableArray<UIView *> *stagesOut, NSMutableArray<NSString *> *slotsOut) {'
      'static BOOL DMSMSwapPlan(BOOL horizontal, NSMutableDictionary<NSString *, NSString *> *out) {'
      'static BOOL DMSMHalfQuarterPlan(NSString **halfB, NSString **halfSlot, NSArray<NSString *> **quarterBs, NSArray<NSString *> **quarterSlots) {'
      'static BOOL DMSwapAvailable(BOOL horizontal) {'
      'static void DMSwapWindows(BOOL horizontal) {'
      'static NSString *DMOtherHalfQuarter(NSString *halfSlot, BOOL first) {'
      'static BOOL DMHalfQuarterPlan(UIView **halfStage, NSString **halfSlot, NSArray<UIView *> **quarterStages, NSArray<NSString *> **quarterSlots) {'
      'static BOOL DMHalfQuarterAvailable(void) {'
      'static void DMApplyHalfQuarterSwap(UIView *half, NSString *halfSlot, UIView *quarter, NSString *quarterSlot) {'
      'static void DMSwapHalfWithQuarter(void) {')
ROW='[items addObject:[[DMRow alloc] initWithTitle:@"Swap Half and Quarter" enabled:DMHalfQuarterAvailable() handler:DMCloseThen(^{ DMSwapHalfWithQuarter(); })]];'
ROWS_IF='if (DMActiveEngine() != DMEngineNone || DMSMEngine()) {   // swap the places of opposed windows'

run() {   # $1 StatusBar.x, $2 work dir, $3 quiet; the number of failed checks
  local X=$1 d=$2 q=$3 n=0 h out a b
  mkdir -p "$d"
  for h in "${X_FN[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function starting \"$h\""; return 99; }; done
  for h in "${X_FN[@]}"; do fn "$X" "$h"; done > "$d/swq-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-swaphalfquarter.m || { echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (the site check) the Window menu's row takes its state from DMHalfQuarterAvailable, inside the block of the Swap rows (any engine of ours)
  a=$(grep -nF "$ROWS_IF" "$X" | head -1 | cut -d: -f1); b=$(grep -nF "$ROW" "$X" | head -1 | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ "$b" -gt "$a" ] && [ $((b - a)) -le 4 ]; then [ -n "$q" ] || echo "PASS  the Window menu's Swap Half and Quarter row is enabled by DMHalfQuarterAvailable, with the Swap rows"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the Window menu's Swap Half and Quarter row does not ask DMHalfQuarterAvailable with the Swap rows"; n=$((n + 1)); fi
  return $n
}

run "$X0" "$W/real"; rc=$?
if [ -z "$SWQ_SB_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 perl expression on StatusBar.x
    local d="$W/m$((++k))" c
    mkdir -p "$d"; c="$d/StatusBar.x"; perl -pe "$2" "$X0" > "$c"
    cmp -s "$c" "$X0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$c" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the row left out on MilkyWay4 again (1.8.7.2's gate)" 's/^    return DMActiveEngine\(\) != DMEngineNone && DMHalfQuarterPlan\(NULL, NULL, NULL, NULL\);.*$/    return (DMActiveEngine() == DMEngineAerial || DMActiveEngine() == DMEngineZetsu) && DMHalfQuarterPlan(NULL, NULL, NULL, NULL);/'
  mtf "the row left out on Zetsu" 's/^    return DMActiveEngine\(\) != DMEngineNone && DMHalfQuarterPlan\(NULL, NULL, NULL, NULL\);.*$/    return (DMActiveEngine() == DMEngineAerial || DMActiveEngine() == DMEngineMilkyWay) && DMHalfQuarterPlan(NULL, NULL, NULL, NULL);/'
  mtf "the row greyed on Stage Manager" 's/^    if \(DMSMEngine\(\)\) return DMSMHalfQuarterPlan\(NULL, NULL, NULL, NULL\);/    if (DMSMEngine()) return NO;/'
  mtf "the row always enabled" 's/^    return DMActiveEngine\(\) != DMEngineNone && DMHalfQuarterPlan\(NULL, NULL, NULL, NULL\);.*$/    return YES;/'
  mtf "the menu row with a state of its own" 's/initWithTitle:\@"Swap Half and Quarter" enabled:DMHalfQuarterAvailable\(\)/initWithTitle:\@"Swap Half and Quarter" enabled:DMActiveEngine() != DMEngineMilkyWay/'
fi
exit $rc
