#!/bin/bash
# Mac test of the desktop's icon placement (statusbar/DesktopPlace.h, test-desktopplace.m): where icons go, and the cost of a layout pass.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/tdp" test-desktopplace.m
"$W/tdp"
