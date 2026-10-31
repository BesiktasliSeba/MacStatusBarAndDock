#!/bin/bash
# Mac test of Aerial 5.x's fit-to-screen pass as StatusBar.x recognises it before a commit (statusbar/A5FitPass.h, test-a5fitpass.m): the traced
# frames, the frames the pass leaves alone, a user's own size or place never taken for it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/ta5" test-a5fitpass.m
"$W/ta5"
