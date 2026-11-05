#!/bin/bash
# Mac test of the Stage Manager engine's App Switcher cards plan (statusbar/SMCardPlan.h, test-smcards.m): one card per window of a desktop, in the
# stage's place, the window used last first; other cards as SpringBoard has them (cases from the iPad 2 16.7.7 and the 17.5, 30 Oct).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tsc" test-smcards.m
"$W/tsc"
# As built (1.8.1 item 7, Mac Switcher off): a window's card keeps its title bar in the App Switcher.
S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
check "a window's card keeps its bar (scaled no longer takes it away), not a full-screen one's" "fn $S 'static void DMSMChrome(' | grep -qF 'if (full || (scaled && DMTestFlag(\"/tmp/msb-sm-cards-nobar\"))) want = NO;'"
check "  ... there it takes no touch and has no grips (a tap opens the card, no light acts)" "fn $S 'static void DMSMChrome(' | grep -qF 'bar.userInteractionEnabled = !scaled' && fn $S 'static void DMSMChrome(' | grep -qF 'DMSMPlaceGrips(card, bundle, !scaled);'"
[ $fails = 0 ] || exit 1
