#!/bin/bash
# Mac test of Pointer Animations with the Mac pointer (common/PointerAnim.h, test-pointeranim.m): off once per Mac-pointer period, never fought,
# given back only while still off as we left it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tpa" test-pointeranim.m
"$W/tpa"
