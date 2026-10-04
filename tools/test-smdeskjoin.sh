#!/bin/bash
# Mac test of the Stage Manager engine's one-desktop rule for transitions SpringBoard builds itself (statusbar/SMDeskJoin.h, test-smdeskjoin.m):
# another stage asked for joins the desktop (the 4-window rule), the desktop's own and Stage Manager's own arrangements pass, a random sweep.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tdj" test-smdeskjoin.m
"$W/tdj"
