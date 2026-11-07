#!/bin/bash
# Mac test of the windows' App Switcher cards plan (statusbar/WindowCardPlan.h, test-wincards.m): when SpringBoard is asked for a window's card,
# when the front window's card goes first (cases from the M1, 15.6.1, 28 Oct), and which windows are pictured as the App Switcher comes, in which order.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/twc" test-wincards.m
"$W/twc"
# The title bar on a window's card, as built (WindowCards.h; 1.8.1 item 7): never with the Stage Manager engine (its cards have theirs, DMSMChrome),
# placed on every layout of a card and on the tick, taking no touch, the picture's top corners square under it and back without it.
C=../statusbar/WindowCards.h
fails=0
check() { if eval "$2"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
check "the bar: another engine's window only (DMCardWindowApp: a one-app card whose app has a window), not with Stage Manager's, debug flag to compare" \
  "fn $C 'static void DMWinCardBarSync(' | grep -qF '!DMSMEngine() && DMActiveEngine() != DMEngineNone && !DMWinCardsOff() && !DMTestFlag(\"/tmp/msb-wincards-nobar\")' && fn $C 'static void DMWinCardBarSync(' | grep -qF 'b = DMCardWindowApp(card);'"
check "  ... placed by the plain rule, in the picture's scale" "fn $C 'static void DMWinCardBarSync(' | grep -qF 'MSBDWinCardBarPlace(pic.origin.x, pic.origin.y, pic.size.width, w, kStageBarHeight, &s, &cx, &cy);'"
check "  ... no touch (a tap on a card stays the card's)" "fn $C '- (instancetype)initWithFrame:(CGRect)f {' | grep -qF 'self.userInteractionEnabled = NO;'"
check "  ... on every layout of both card classes (installed once with the cards), on the tick, and about each frame as the App Switcher comes" \
  "fn $C 'static void DMWinCardLayout(' ; grep -qF 'static void DMWinCardLayout(id self, SEL _cmd) { o_WinCardLayout(self, _cmd); DMWinCardBarSync((UIView *)self); }' $C && grep -qF 'static void DMWinCardSnapLayout(id self, SEL _cmd) { o_WinCardSnapLayout(self, _cmd); DMWinCardBarSync((UIView *)self); }' $C && grep -qF 'DMWinCardAdoptInstall(); DMWinCardBarsInstall(); }' $C && fn $C 'static void DMWinCardsTick(' | grep -qF 'DMWinCardBarsTick();' && fn $C 'static void DMWinCardsSwitcherComing(' | grep -qF 'DMWinCardBarsSoon(18);'"
check "  ... the picture's top corners square under it, all four again without it (the card is SpringBoard's and reused)" \
  "fn $C 'static void DMWinCardBarShapePicture(' | grep -qF 'kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner : kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner' && fn $C 'static void DMWinCardBarSync(' | grep -qF 'bar.hidden = YES; DMWinCardBarShapePicture(bar, bar.picture, NO);'"
check "the bar only while iPadOS's App Switcher shows (WindowCardPlan.h MSBDWinCardBarShown): a full-screen app's card kept one, its lower edge a line over the menu bar (M1, 7 Nov); all hidden as the switcher goes" \
  "fn $C 'static void DMWinCardBarSync(' | grep -qF 'if (MSBDWinCardBarShown(gEnvMode) && !DMSMEngine()' && fn $C 'static void DMWinCardsSwitcherComing(' | grep -qF 'if (!MSBDWinCardBarShown(mode)) DMWinCardBarsHideAll();' \
   && fn $C 'static void DMWinCardBarsHideAll(' | grep -qF 'bar.hidden = YES; DMWinCardBarShapePicture(bar, bar.picture, NO);' && grep -qF '[gWinCardBars addObject:bar];' $C"
[ $fails = 0 ] || exit 1
