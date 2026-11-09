#!/bin/bash
# Mac test of a Live Activity card's first open (test-lacardfirstopen.m): DMLAOpenCard and DMLACardFrame as built, with stand-ins for the menu window and the bar.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cut1() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' ../statusbar/LiveActivities.h; }
{ cut1 'static CGRect DMLACardFrame(UIView *host, CGRect anchor, CGSize size) {'; cut1 'static void DMLAOpenCard(DMLAPill *pill) {'; } > "$W/lacardfirstopen-gen.h"
[ -s "$W/lacardfirstopen-gen.h" ]
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-value -I"$W" -framework Foundation -framework CoreGraphics -o "$W/t" test-lacardfirstopen.m
"$W/t"
