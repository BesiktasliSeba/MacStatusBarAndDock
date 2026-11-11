#!/bin/bash
# test-lightmagnify.sh: Magnify Traffic Lights' layout and pick rule (common/LightMagnify.h) -- see test-lightmagnify.c.
cd "$(dirname "$0")" || exit 1
OUT="${TMPDIR:-/tmp}/test-lightmagnify.$$"
clang -std=c11 -O1 -Wall -Werror -o "$OUT" test-lightmagnify.c || exit 1
"$OUT"; rc=$?
rm -f "$OUT"
# Only a finger opens the pill: a mouse or trackpad click reaches SpringBoard as a DIRECT touch (type 0), so the press refuses a pointer's touch by
# Desktop.h's DMDesktopPointerTouch, not by its type alone (review 1.8.6, gestures: every click on a light opened the pill).
if grep -q 'else if (DMDesktopPointerTouch(touch, nil)) why = @"not a finger (pointer)";' ../statusbar/LightMagnify.h; then
  echo "PASS  the press refuses a pointer's click (a type 0 touch from the pointer): a click on a light is the light's own"
else echo "FAIL  statusbar/LightMagnify.h: the press takes a pointer's click (refused by touch type only)"; rc=1; fi
exit $rc
