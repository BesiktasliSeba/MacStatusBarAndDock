#!/bin/bash
# Mac test of a Stage Manager window resized by a corner or side with its opposite corner kept (statusbar/SMResizeAnchorMath.h, test-smresizeanchor.c):
# a model of iPadOS 16.7.7's resize step, as Apple has it (around the window's centre) and as SMResizeAnchor.h gives it its values.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tra" test-smresizeanchor.c
"$W/tra"
