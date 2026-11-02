#!/bin/bash
# test-mswhold.sh: the hold that opens the Mac Switcher from a swipe up (statusbar/MSWHoldRule.h) -- see test-mswhold.c.
cd "$(dirname "$0")" || exit 1
OUT="${TMPDIR:-/tmp}/test-mswhold.$$"
clang -std=c11 -O1 -Wall -Werror -o "$OUT" test-mswhold.c -lm || exit 1
"$OUT"; rc=$?
rm -f "$OUT"
exit $rc
