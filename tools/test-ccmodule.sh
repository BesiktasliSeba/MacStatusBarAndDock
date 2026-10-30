#!/bin/bash
# Mac test of RAM & CPU's place in Control Center's module lists (common/CCModuleList.h, test-ccmodule.m): our folder and identifier added once,
# in the list's own kind, nothing else touched; and where the tile puts its lines in a 2 x 1 and in a square tile (ccmodule/RAMCPULayout.h).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/tcm" test-ccmodule.m
"$W/tcm"
# (1.7.0, KT) the offer on the tile drawn over Memory Magic's is asked once: Not Now is kept in our main preferences, which the package's removal
# leaves (so an update or a reinstall does not ask again), and a tap after it offers nothing
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "Not Now is kept (ramcpuOfferDeclined, our main preferences)" \
  "grep -q 'CFPreferencesSetValue(CFSTR(\"ramcpuOfferDeclined\"), kCFBooleanTrue, MSB_DOMAIN' ../statusbar/StatusBar.x"
check "a tap after Not Now offers nothing (checked before the offer)" \
  "awk '/^static void DMOfferRAMCPU\\(void\\)/{f=1} f&&/DMRAMCPUOfferDeclined\\(\\)/{print \"ok\"; exit} f&&/DMShowRAMCPUOffer\\(0\\)/{exit}' ../statusbar/StatusBar.x | grep -q ok"
check "the package's removal leaves our main preferences (the record stays for a reinstall)" \
  "! grep -n 'com.besiktasliseba.macstatusbar.plist' ../layout/DEBIAN/postrm ../layout/DEBIAN/prerm"
check "the debug-only fake list never reaches a release build" \
  "awk '/^static void DMOfferRAMCPU\\(void\\)/{f=1} f&&/msb-ccoffer-fake/{print prev} f{prev=\$0} f&&/DMShowRAMCPUOffer\\(0\\)/{exit}' ../statusbar/StatusBar.x | grep -q '#if DEBUG'"
[ $fails = 0 ] && echo "test-ccmodule: offer wiring checks pass" || { echo "test-ccmodule: offer wiring checks FAILED"; exit 1; }
