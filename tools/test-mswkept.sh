#!/bin/bash
# Mac test of the Mac Switcher's desktops kept while it is off and what comes back when it is on again (statusbar/MSWKept.h, test-mswkept.m;
# 1.5.2 item 14).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tmk" test-mswkept.m
"$W/tmk"
