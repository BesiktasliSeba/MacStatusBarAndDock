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
# (1.7.6 review S1) 18's gallery: RAM & CPU's app does not hang on the App Library's icon class (made only while Show in App Library is on); the
# status bar part says it names Activity Monitor's section by an exported function, and renames only that section
check "RAM & CPU's app is asked of the status bar part's exported function, not of the App Library's icon class" \
  "awk '/^static NSString \\*MSBDCCContainerFor\\(/{f=1} f&&/dlsym\\(RTLD_DEFAULT, kMSBDCCActivityMonitorSectionFn\\)/{a=1} f&&/DMALActivityMonitorIcon/{bad=1} f&&/^}/{exit} END{exit !(a && !bad)}' ../common/CCModuleRegister.h"
check "  ... that function is exported under the name asked for, and answers whether the gallery hook is in" \
  "grep -q '^#define kMSBDCCActivityMonitorSectionFn \"MSBDCCActivityMonitorSectionReady\"' ../common/CCModuleList.h && grep -q '__attribute__((visibility(\"default\"))) BOOL MSBDCCActivityMonitorSectionReady(void) { return gDMALGalleryReady; }' ../statusbar/AppLibraryApps.h && grep -q 'gDMALGalleryReady = DMALHook(@\"SBHApplicationWidgetCollection\"' ../statusbar/AppLibraryApps.h"
check "  ... set whatever Show in App Library says (DMALGalleryIconInit runs at SpringBoard's start, outside DMALApplyPref)" \
  "! awk '/^static void DMALApplyPref\\(/{f=1} f&&/gDMALGalleryReady|DMALGalleryIconInit/{print; exit} f&&/^}/{exit}' ../statusbar/AppLibraryApps.h | grep -q . && grep -q 'DMALGalleryIconInit();' ../statusbar/StatusBar.x"
check "a gallery section is named Activity Monitor only when it is Activity Monitor's (MSBDCCGallerySectionIsActivityMonitor)" \
  "awk '/^static id DMALCollIcon\\(/{f=1} f&&/MSBDCCGallerySectionIsActivityMonitor\\(/{print \"ok\"; exit} f&&/^}/{exit}' ../statusbar/AppLibraryApps.h | grep -q ok"
[ $fails = 0 ] && echo "test-ccmodule: offer wiring checks pass" || { echo "test-ccmodule: offer wiring checks FAILED"; exit 1; }
