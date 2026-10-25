#!/bin/bash
# Mac test of the Aerial 5.x role resolver (statusbar/AerialResolve.h) on two builds' method lists (private fixtures): test-a5resolve.m.
set -e
cd "$(dirname "$0")"
# (the fixtures are method lists of a closed-source tweak: private, kept out of the public source tree, so the test skips without them)
if [ ! -f a5resolve-fixtures/aerial-5.0.txt ] || [ ! -f a5resolve-fixtures/aerial-5.1.txt ] || [ ! -f a5resolve-fixtures/expect-5.0.txt ]; then echo "test-a5resolve: skipped (no tools/a5resolve-fixtures)"; exit 0; fi
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-a5resolve.m
"$W/t" a5resolve-fixtures
