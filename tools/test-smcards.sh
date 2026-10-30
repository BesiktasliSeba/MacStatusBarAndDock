#!/bin/bash
# Mac test of the Stage Manager engine's App Switcher cards plan (statusbar/SMCardPlan.h, test-smcards.m): one card per window of a desktop, in the
# stage's place, the window used last first; other cards as SpringBoard has them (cases from the iPad 2 16.7.7 and the 17.5, 30 Oct).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tsc" test-smcards.m
"$W/tsc"
