#!/bin/bash
# Mac test of where a Stage Manager window may go (statusbar/SMFit.h, test-smfit.m): sizes read through their own reference, windows fitted into the
# desktop under the menu bar, the top/left edge rule after Stage Manager's constraint, a random sweep in four orientations.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/tsf" test-smfit.m
"$W/tsf"
