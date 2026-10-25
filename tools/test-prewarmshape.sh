#!/bin/bash
# Mac test of the prewarm block's method-shape check (prewarmblock/PrewarmShape.h, test-prewarmshape.m): only an object return with one object
# argument is ever hooked (1.5.1 logic test C1).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tps" test-prewarmshape.m
"$W/tps"
