#!/bin/bash
# Mac test of the Stage Manager engine's Home rule (statusbar/SMHomeRule.h, test-smhomerule.m): Home keeps the desktop's windows, a full-screen
# window goes to the background, everything else is left as SpringBoard built it; a random sweep of the plan's invariants (4 and 7 window roles).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/thr" test-smhomerule.m
"$W/thr"
