#!/bin/bash
# Mac test of common/TweakIndex.h (the tweak settings index of the Settings search and Spotlight): builds made-up tweak folders
# (tools/make-tweakindex-fixture.py) and checks what the index finds in them (test-tweakindex.m).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
python3 make-tweakindex-fixture.py "$W/Library"
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-tweakindex.m
"$W/t" "$W/Library"
