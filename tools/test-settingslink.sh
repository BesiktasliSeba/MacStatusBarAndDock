#!/bin/bash
# Mac test of the links into our Settings pages where iPadOS 18's Settings has them, and of the way our pages are opened as Open Apps as Windows
# says (common/SettingsRoot.h, test-settingslink.m; 1.6.0).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tsl" test-settingslink.m
"$W/tsl"
