#!/bin/bash
# Mac test of the menu bar over a full-screen app that hides it (common/BarReveal.h, test-barreveal.c), then the sites in SpringBoard's code.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/t" test-barreveal.c
fails=0; "$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; B=../statusbar/BarReveal.h
check "shown the same way as over a game with a window in front: the gesture's app is the one SpringBoard is told shows its bar" \
  "grep -qF 'if (DMBarRevealWants(fb)) want = fb;' $S && grep -qF 'DMBarRevealTick(DMBarFrontBundle());' $S && grep -qF 'if (DMSMEngine() && DMSMFrontIsFullScreen()) { NSString *b = DMSMFullScreenBundle(); if (b.length) return b; }' $S && grep -qF 'BOOL full = DMSMEngine() ? DMSMFrontIsFullScreen() : DMFullScreenAppInFront();' $B && grep -qF '#include \"BarReveal.h\"' $S"
check "the app's own answer is noted before ours replaces it" "grep -qF 'if (hidden || [gHiddenBarProviders containsObject:provider]) DMBarNoteOrigHidden(provider, hidden);' $S"
check "the pointer's push: the Cover Sheet's pointer recogniser shows the bar first, before the auto-hiding bar's own use of it" \
  "grep -n 'DMBarRevealPointerPull()) return NO' $S | head -1 | cut -d: -f1 > \$W/a && grep -n 'DMAutoHideHandlePointerPull()) return NO' $S | head -1 | cut -d: -f1 > \$W/b && [ \$(cat \$W/a) -lt \$(cat \$W/b) ]"
check "touches are only looked at: the event goes on unchanged" "grep -qF 'if (event.type == UIEventTypeTouches) DMBarRevealSeeTouches(event);   // (looked at only; the event goes on unchanged)' $B && ! grep -q 'return;.*sendEvent' $B"
check "nothing is watched without such an app in front, and nothing with the stock bar" "grep -qF 'if (!hides && !gBarRevealApp) return;' $B && grep -qF 'if (!gBarRevealCandidate && !gBarRevealApp) { gBarRevealFinger.live = NO; return; }' $B && grep -qF 'if (gBarRevealFinger.live && t.timestamp - gBarRevealFinger.at > kMSBDRevealSwipeTime) gBarRevealFinger.live = NO;' $B && grep -qF 'if (gStockBar ||' $B"
check "the pointer counts only when it moved to the edge (a pointer resting there as the app opens is no push)" "grep -qF 'if (z == 1 && moved && gBarRevealCandidate' $B && grep -qF 'gBarRevealLastPt = CGPointMake(-1, -1);' $B"
check "started in the constructor, and its release marker" "grep -qF 'DMBarRevealInit();' $S && grep -qF 'DM_FEATURE_MARK(\"bar-reveal-over-full-screen\");' $B"
[ "$fails" = 0 ] && echo "test-barreveal: all pass" || { echo "test-barreveal: FAILED"; exit 1; }
