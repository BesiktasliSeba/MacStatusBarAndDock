#!/bin/bash
# Mac test of the quit set's file (common/PrewarmQuitSet.h, test-prewarmquitset.m): SpringBoard's write read back as dasd reads it, damaged files,
# and the file stamp that has the set read again when the file changed (iPad 2, palera1n, 29 Oct).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tpq" test-prewarmquitset.m
"$W/tpq"
