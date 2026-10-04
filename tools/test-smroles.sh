#!/bin/bash
# Mac test of the Stage Manager engine's window roles (statusbar/SMRoles.h: SpringBoard's own role functions as disassembled on 16.7.7, every
# variation keeps the engine's four) and Fit to Window past four windows (statusbar/SMFitPlan.h). test-smroles.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tsr" test-smroles.m
"$W/tsr"
