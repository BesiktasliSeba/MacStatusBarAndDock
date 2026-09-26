#!/bin/bash
# Builds and runs the Mac unit test of the crash-report classifier (common/CrashBlame.h) against tools/crash-fixtures.
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)/test-crashblame
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$OUT" test-crashblame.m
"$OUT" crash-fixtures
