#!/bin/bash
# Mac test of which of our Spotlight rows the typed text matches (spotlight/MacSpotlightMatch.h): test-spotmatch.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-spotmatch.m
"$W/t"
