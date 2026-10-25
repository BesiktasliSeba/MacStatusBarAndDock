#!/bin/bash
# Mac test of the Zetsu observer guard (common/ZetsuGuard.h): test-zetsuguard.m with a stand-in ZetsuAlertHostController.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-zetsuguard.m
"$W/t"
