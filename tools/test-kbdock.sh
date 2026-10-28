#!/bin/bash
# Mac test of when the Dock goes under our own on-screen keyboard (statusbar/KeyboardDock.h, test-kbdock.m): the frames iPadOS announced on the
# A12Z (18.5) and the iPad 2 (16), and the decision with the keyboard drawn in SpringBoard's keyboard windows.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tkd" test-kbdock.m
"$W/tkd"
