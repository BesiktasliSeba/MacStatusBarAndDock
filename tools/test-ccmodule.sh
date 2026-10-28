#!/bin/bash
# Mac test of RAM & CPU's place in Control Center's module lists (common/CCModuleList.h, test-ccmodule.m): our folder and identifier added once,
# in the list's own kind, nothing else touched; and where the tile puts its lines in a 2 x 1 and in a square tile (ccmodule/RAMCPULayout.h).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/tcm" test-ccmodule.m
"$W/tcm"
