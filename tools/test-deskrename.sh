#!/bin/bash
# Mac test of where a name edited on the desktop is typed (statusbar/DesktopRename.h, test-deskrename.m): the level of the field's own window from
# the window levels measured on the iPad 2 (16.7.7) for each engine, the keyboard windows UIKit puts above it, and the field's place over a keyboard.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tdr" test-deskrename.m
"$W/tdr"
