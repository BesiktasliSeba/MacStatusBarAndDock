#!/bin/bash
# Mac test of the steps after Aerial 5's round-icon minimize (statusbar/A5WakeFollow.h, test-a5wake.c): after a wake the windows are back as soon as
# Aerial's own animations have run out (1.7.4 item 3e: 1.6 s of fixed waits before), never mid-animation, never later than before.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/ta5w" test-a5wake.c
"$W/ta5w"
