#!/bin/bash
# Mac test of the App Switcher clean-up's stale-card rule (statusbar/SwitcherStale.h, test-switcherstale.m): the cards iPadOS brings back after a
# respring stay (a window engine switch, 17.5.1, 29 Oct), only the card of an app that went away while SpringBoard ran goes, after the grace.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tss" test-switcherstale.m
"$W/tss"
