#!/bin/bash
# Mac test of common/GuidedAccess.h (+ AlertQueue.h's rule), built for Mac Catalyst (UIKit on the Mac) three ways: see test-guidedaccess.m.
set -e
cd "$(dirname "$0")"
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL: no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
for v in "1 0" "0 1" "0 0"; do
  set -- $v
  clang -target x86_64-apple-ios14.0-macabi -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -DWITH_SB=$1 -DWITH_LISTENER=$2 -Wl,-export_dynamic -framework UIKit -o "$W/tga$1$2" test-guidedaccess.m
  printf "WITH_SB=%s WITH_LISTENER=%s: " "$1" "$2"
  "$W/tga$1$2"
done
