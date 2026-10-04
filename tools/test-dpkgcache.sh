#!/bin/bash
# Mac test of the dpkg status lookups in common/CrashExplain.h (S-2: read once per change, never on the main thread for the Apple menu).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
D="-DDEBUG=1 -DMSBD_GUARD_RECORD=\"$W/record.txt\" -DMSBD_GUARD_VERDICTS=\"$W/verdicts.txt\" -DMSBD_DPKG_DIR=\"$W/dpkg\" -DMSBD_DPKG_STATUS=\"$W/status\""
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable $D -framework Foundation -o "$W/t" test-dpkgcache.m
"$W/t"; rc=$?
rm -rf "$W"
exit $rc
