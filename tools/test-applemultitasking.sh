#!/bin/bash
# Mac test of where Apple keeps its multitasking settings per iPadOS version, for our Windows & Multitasking page (common/AppleMultitaskingTable.h,
# test-applemultitasking.m; 1.6.0).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tam" test-applemultitasking.m
"$W/tam"
