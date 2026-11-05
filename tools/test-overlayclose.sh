#!/bin/bash
# Mac test of when Spotlight closes an open menu, dialog or question of ours (statusbar/OverlayClose.h, test-overlayclose.c), and, as built
# (StatusBar.x), that Fit's side question notes the Spotlight it opened over, no other overlay does, and the tick asks the rule: 1.8.1 item 11.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wextra -Wno-unused-function -o "$W/toc" test-overlayclose.c
"$W/toc"
X=../statusbar/StatusBar.x; fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$X"; }
check "the side question notes whether Spotlight was showing when it opened; every other overlay notes nothing (a menu opened over Spotlight goes, as before)" \
  "fn 'static UIControl *DMMakeOverlayFor(UIView *host, CGFloat dimAlpha, BOOL menu) {' | awk '/gOverlay = o;/ {a=NR} /gOverlayOpenedOverSpotlight = NO;/ {b=NR} END {exit !(a && b && b == a + 1)}' && fn 'static void DMShowSidePrompt(NSMutableDictionary *ctx, BOOL rebuilt) {' | awk '/UIControl \\*o = DMMakeOverlay\\(host, 0.32\\);/ {a=NR} /gOverlayOpenedOverSpotlight = DMSpotlightShown\\(\\);/ {b=NR} END {exit !(a && b && b == a + 1)}'"
check "the tick closes it for Spotlight only by the rule (a Spotlight that came up over it), keeping the note only while that Spotlight stays" \
  "grep -q 'gOverlayOpenedOverSpotlight = MSBDSpotlightStillFromOpen(spotNow, gOverlayOpenedOverSpotlight);' $X && grep -q 'else if (MSBDSpotlightCameUp(spotNow, gOverlayOpenedOverSpotlight)) systemUI = @\"Spotlight\";' $X && ! grep -q 'else if (DMSpotlightShown()) systemUI = @\"Spotlight\";' $X"
check "the same for Notification Center (review 1.8.1, 1): the side question notes the Cover Sheet it opened over, no other overlay does, the tick asks the rule, the note lasts only while that Cover Sheet stays" \
  "fn 'static UIControl *DMMakeOverlayFor(UIView *host, CGFloat dimAlpha, BOOL menu) {' | grep -q 'gOverlayOpenedOverCover = NO;' && fn 'static void DMShowSidePrompt(NSMutableDictionary *ctx, BOOL rebuilt) {' | grep -q 'gOverlayOpenedOverCover = DMCoverSheetShown();' \
   && grep -q 'gOverlayOpenedOverCover = MSBDCoverSheetStillFromOpen(coverNow, gOverlayOpenedOverCover);' $X && grep -q 'else if (MSBDCoverSheetCameUp(coverNow, gOverlayOpenedOverCover)) systemUI = @\"Notification Center\";' $X && ! grep -q 'else if (DMCoverSheetShown()) systemUI = @\"Notification Center\";' $X"
exit $fails
