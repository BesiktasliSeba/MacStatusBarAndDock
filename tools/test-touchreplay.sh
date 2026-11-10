#!/bin/bash
# Mac test of where a held-back first touch is sent again from (statusbar/TouchReplay.h, test-touchreplay.c; 1.7.4 item 8).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -o "$W/ttr" test-touchreplay.c
"$W/ttr"
# 1.8.0 (release-1.8.0.md item 5): a still tap held back whose lift is on one of our menu bar's items is sent again there, at the screen's top edge
# too (the 20 pt edges stay the edges' own gestures elsewhere); never on the Lock Screen or the Cover Sheet, never for a swipe.
S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the menu bar's items count as a tap's place at the top edge: the item under the lift in a copy of the bar that shows" \
  "grep -q '            UIView \*barItem = !away && !path && !locked ? DMBarControlAtScreenPoint(lift) : nil;' $S && grep -q '            BOOL again = !path && (away || barItem) && !locked && held < 0.6 && moved < 30.0 && CACurrentMediaTime() > gDMTFReinjectUntil;' $S"
check "  ... the items: the logo, the menu titles, the lights, the icons and the clock, in a bar on the main screen that is up and not faded" \
  "awk '/^static UIView \*DMBarControlAtScreenPoint\(CGPoint p\) \{/{f=1} f&&/w.screen != main/{a=1} f&&/DMEffectiveAlpha\(fg\) < 0.5/{b=1} f&&/kButtonKey, kAppButtonKey, kFileButtonKey, kEditButtonKey, kViewButtonKey, kGoButtonKey, kWinButtonKey, kAudioButtonKey, kSSHButtonKey,/{c=1} f&&/kVPNButtonKey, kWiFiButtonKey, kSpotButtonKey, kClockButtonKey, kBattButtonKey, kCCButtonKey, DM_AM_BUTTONS \};/{d=1} f&&/^}/{exit} END{exit !(a && b && c && d)}' $S"
[ $fails = 0 ] && echo "test-touchreplay: wiring checks pass" || { echo "test-touchreplay: wiring checks FAILED"; exit 1; }
