#!/bin/bash
# Mac test of the green light on the TV with the Stage Manager engine (test-smfullscreenref.m): DMSMSetFullScreenInStage as built, with stand-ins.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
awk -v s='static BOOL DMSMSetFullScreenInStage(NSString *key, BOOL front) {' 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' ../statusbar/StatusBar.x > "$W/smfullscreenref-gen.h"
[ -s "$W/smfullscreenref-gen.h" ]
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -framework Foundation -framework CoreGraphics -o "$W/t" test-smfullscreenref.m
"$W/t"
