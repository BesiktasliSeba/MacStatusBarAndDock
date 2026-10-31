#!/bin/bash
# Mac test of where a held-back first touch is sent again from (statusbar/TouchReplay.h, test-touchreplay.c; 1.7.4 item 8).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -o "$W/ttr" test-touchreplay.c
"$W/ttr"
