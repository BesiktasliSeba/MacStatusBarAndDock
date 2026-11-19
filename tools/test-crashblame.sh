#!/bin/bash
# Builds and runs the Mac unit test of the crash-report classifier (common/CrashBlame.h) against tools/crash-fixtures.
# (1.8.7.7: CRASHBLAME_COMMON=<folder>: the classifier's headers from there -- e.g. the code before the fix, whose new checks must fail.)
set -e
cd "$(dirname "$0")"
T=$(mktemp -d); OUT=$T/test-crashblame
trap 'rm -rf "$T"' EXIT
C=${CRASHBLAME_COMMON:-$PWD/../common}
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -DMSBD_TEST_FEATURE_H="\"$C/CrashFeature.h\"" -DMSBD_CAUSE_FILE="\"$T/causes.txt\"" \
  -DMSBD_CHOICY_PREFS="\"$T/choicy.plist\"" -o "$OUT" test-crashblame.m
"$OUT" crash-fixtures
