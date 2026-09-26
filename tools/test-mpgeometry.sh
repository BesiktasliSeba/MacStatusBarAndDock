#!/bin/bash
# Mac test of the Mac pointer's external-display math (statusbar/macpointer/MPDisplayGeometry.h, test-mpgeometry.c).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wextra -Wno-unused-function -o "$W/tmg" test-mpgeometry.c
"$W/tmg"
