#!/bin/bash
# test-mswslide.sh: the Mac Switcher slide's arithmetic (statusbar/MSWSlideMath.h) -- see test-mswslide.c.
cd "$(dirname "$0")" || exit 1
OUT="${TMPDIR:-/tmp}/test-mswslide.$$"
clang -std=c11 -O1 -Wall -Werror -o "$OUT" test-mswslide.c -lm || exit 1
"$OUT"; rc=$?
rm -f "$OUT"
exit $rc
