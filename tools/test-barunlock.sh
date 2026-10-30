#!/bin/bash
# Mac test of the status bar's locked look (statusbar/BarUnlock.h, test-barunlock.c): the unlocked look as soon as the Cover Sheet starts to leave
# (1.7.1 item 11: the M1's wake gave it 2 s late), the Lock Screen and Notification Center keep the locked look.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tbu" test-barunlock.c
"$W/tbu"
