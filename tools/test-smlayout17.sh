#!/bin/bash
# Mac test of the Stage Manager engine's version-aware self-check and its iPadOS 17 layout wrappers (statusbar/SMEngineAPI.h), with stand-in
# classes carrying the iPadOS 17.0.3 headers' signatures. BOOL is bool here, as on arm64 iOS.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -DDEBUG=1 -framework Foundation -framework CoreGraphics -o "$W/t" test-smlayout17.m
"$W/t"; r=$?
rm -rf "$W"
exit $r
