#!/bin/bash
# Mac test of the plain "no figure" lines the Activity Monitor window shows (common/ActMonText.h, test-actmontext.c).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tat" test-actmontext.c
"$W/tat"
