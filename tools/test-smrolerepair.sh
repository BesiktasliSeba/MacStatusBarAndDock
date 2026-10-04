#!/bin/bash
# Mac test of "one window, one role" (statusbar/SMRoleRepair.h): the transition contexts Stage Manager's own Minimize builds on desktops of four to
# seven windows (its role shift as disassembled on 16.7.7), our desktop join's, and the cases that must be left alone. test-smrolerepair.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/trr" test-smrolerepair.m
"$W/trr"
