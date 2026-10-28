#!/bin/bash
# Mac test of the one-time welcome's decisions (common/WelcomeRule.h, test-welcomerule.c).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wextra -Wno-unused-function -o "$W/twr" test-welcomerule.c
"$W/twr"
