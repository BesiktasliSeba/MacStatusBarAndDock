#!/bin/bash
# Mac test of where an app opens when its windows are on other Mac Switcher desktops (statusbar/MSWAppDesk.h, test-mswappdesk.m; 1.7.1 item 5):
# its window comes here, or with Go to the App's Desktop on its desktop comes; a window here keeps the launch here.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tad" test-mswappdesk.m
"$W/tad"
