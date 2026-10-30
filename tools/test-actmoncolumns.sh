#!/bin/bash
# Mac test of the Activity Monitor window's columns (statusbar/ActMonColumns.h, test-actmoncolumns.m): every title fits its column with the sort
# arrow, in every tab, at the window's smallest and largest widths (29 Oct: "Memory ↓" and "Network ↓" were cut off).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework AppKit -o "$W/tac" test-actmoncolumns.m
"$W/tac"
