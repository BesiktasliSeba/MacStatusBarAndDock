#!/bin/bash
# Mac test of which processes the loader gives the app-side parts (common/BundledPath.h, test-bundledpath.c: path forms of apps, extensions,
# XPC services, cryptexes, ExtensionKit, daemons, DriverKit drivers) and the loader's wiring: UIKit loaded AND a bundled process for the app-side
# parts; MixAudio never in an app extension; no path rule of its own left in the loader (one place decides).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/tbp" test-bundledpath.c && "$W/tbp" || fails=1
L=../loader/Loader.c
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the app-side parts: UIKit loaded (RTLD_NOLOAD, only a look) and MSBDBundledProcess" \
  "grep -q 'void \\*uikit = dlopen(\"/System/Library/Frameworks/UIKit.framework/UIKit\", RTLD_LAZY | RTLD_NOLOAD);' $L && grep -q 'if (uikit) { if (MSBDBundledProcess(path)) kind |= kUIKit; dlclose(uikit); }' $L"
check "MixAudio: never in an app extension (MSBDAppExtension), nor with Use Stock Status Bar" \
  "grep -q 'if (strcmp(kPayloads\\[i\\].name, \"MixAudio\") == 0 && (MSBDAppExtension(path) || MSBDStockBar())) continue;' $L"
check "the loader has no bundle path rule of its own (.app/, .appex/, .xpc/ only in BundledPath.h)" \
  "! grep -q '\"\\.app/\"\\|\"\\.appex/\"\\|\"\\.xpc/\"' $L && grep -q '#include \"../common/BundledPath.h\"' $L"
[ $fails = 0 ] && echo "test-bundledpath: all checks pass" || { echo "test-bundledpath: checks FAILED"; exit 1; }
