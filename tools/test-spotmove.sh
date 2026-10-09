#!/bin/bash
# Mac test of how search-143's Settings items are moved out of Apple's Spotlight sections (spotlight/MacSpotlightMove.h): test-spotmove.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-spotmove.m
"$W/t"
