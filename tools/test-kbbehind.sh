#!/bin/bash
# Mac test of the windows kept from the hardware keyboard (statusbar/KeyboardBehind.h, test-kbbehind.m): only the active app's windows take the keys
# (1.7.1 item 9: Amazon's window took the typing back from Settings' search field).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tkb" test-kbbehind.m
"$W/tkb"
