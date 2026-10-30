#!/bin/bash
# Mac test of the windows' App Switcher cards plan (statusbar/WindowCardPlan.h, test-wincards.m): when SpringBoard is asked for a window's card,
# when the front window's card goes first (cases from the M1, 15.6.1, 28 Oct), and which windows are pictured as the App Switcher comes, in which order.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/twc" test-wincards.m
"$W/twc"
