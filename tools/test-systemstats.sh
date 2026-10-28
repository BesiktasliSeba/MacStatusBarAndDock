#!/bin/bash
# Mac test of the memory and CPU numbers our Control Center tiles show (common/SystemStats.h, test-systemstats.c): the arithmetic on fixed
# numbers (the 17.5 iPad's and the A12Z's), the formatting, and a live sample of this Mac (the same calls exist on macOS).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tss" test-systemstats.c
"$W/tss"
