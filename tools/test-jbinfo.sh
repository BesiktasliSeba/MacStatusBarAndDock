#!/bin/bash
# Mac test of which jailbreak About This iPad and the Shut Down question name (statusbar/JailbreakInfo.h), on fake roots: test-jbinfo.m.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-jbinfo.m
"$W/t"
