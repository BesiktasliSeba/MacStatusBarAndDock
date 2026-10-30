#!/bin/bash
# Mac test of Esc Ends Typing in Windows' rule (appbridge/EscRule.h, test-escrule.c): M-9's sessions keep Esc, the app's own text inputs end their
# typing again unless the app reads the keys itself (1.7.1 item 10), the older rules hold.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/ter" test-escrule.c
"$W/ter"
