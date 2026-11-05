#!/bin/bash
# Mac test of the Mac Switcher's window records across an engine change (statusbar/MSWEngineRecords.h, test-mswenginerecords.m): a stay on another engine
# forgets no window of Stage Manager's, nor the other way round.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tmer" test-mswenginerecords.m
"$W/tmer"
