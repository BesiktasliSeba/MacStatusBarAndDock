#!/bin/bash
# Mac test of the smallest window of the window engines (statusbar/WindowMinSize.h, test-winminsize.m): the layouts' tiles on the iPad 2's real
# desktops and on smaller ones, frames fitted into the desktop, Zetsu's and MilkyWay4's corner drags, Aerial's corner drag steps (traced drags).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/twm" test-winminsize.m
"$W/twm"
