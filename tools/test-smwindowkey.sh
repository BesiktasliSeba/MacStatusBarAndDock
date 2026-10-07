#!/bin/bash
# Mac test of the Stage Manager engine's window keys (statusbar/SMWindowKey.h, M-2: two windows of one app are two windows) and of Fit to Window
# with two windows of one app (statusbar/SMFitPlan.h). test-smwindowkey.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/twk" test-smwindowkey.m
"$W/twk"
