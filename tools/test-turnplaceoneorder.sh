#!/bin/bash
# Mac test of the re-placement after a turn on the Stage Manager engine (test-turnplaceoneorder.m): the placing part of DMSMWatchTurn as built, with stand-ins (1.8.4.1 item 14).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
awk '/^        NSMutableDictionary \*put = \[NSMutableDictionary dictionary\];/ {f=1} f {print} f && /sm-turn-remembered-place/ {exit}' ../statusbar/StatusBar.x > "$W/turnplace-gen.h"
[ -s "$W/turnplace-gen.h" ]
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -I../common -I../statusbar -framework Foundation -framework CoreGraphics -o "$W/t" test-turnplaceoneorder.m
"$W/t"
