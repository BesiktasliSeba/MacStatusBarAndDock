#!/bin/bash
# Mac test of when and how the Stage Manager engine switches Stage Manager on (statusbar/SMSwitchOn.h, test-smswitchon.m): never on the Lock
# Screen, Apple's first-time path only when no key (SpringBoard's own, Apple's, TrollPad's) says Stage Manager was ever on.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tso" test-smswitchon.m
"$W/tso"
