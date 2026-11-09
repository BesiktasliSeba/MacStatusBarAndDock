#!/bin/bash
# Mac test of a Dock Position change on the Stage Manager engine (test-dockpositionfront.m): the Stage Manager branch of DMDockPositionMoved as built, with stand-ins.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
awk -v s='static void DMDockPositionMoved(NSDictionary<NSString *, NSString *> *layouts) {' 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' ../statusbar/StatusBar.x | awk '/^    if \(DMSMEngine\(\)\) \{/ {f=1} f {print} f && /^    }$/ {exit}' > "$W/dockpositionfront-gen.h"
[ -s "$W/dockpositionfront-gen.h" ]
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -I../common -framework Foundation -framework CoreGraphics -o "$W/t" test-dockpositionfront.m
"$W/t"
