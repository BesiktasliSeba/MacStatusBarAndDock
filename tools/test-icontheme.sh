#!/bin/bash
# Mac test of the Dock items as app icons an icon theme can change (1.7.5 item 7): the shared rules (common/IconThemeIDs.h, test-icontheme.m), and the
# wiring -- each Dock view asks the app-icon chain first and keeps its own drawing as the fallback, Activity Monitor's class comes from
# SBApplicationIcon with no picture method of its own there, the chain never overrides a picture method, the crash map knows the new code.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tit" test-icontheme.m
"$W/tit"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the Dock library builds the glue" "grep -q '^DockMagnification_FILES = .* IconTheme.m' ../dock/Makefile"
check "Finder asks the chain first, its own theme lookup only as the fallback" \
  "grep -q 'DMIconThemePicture(MSBDIconFinder' ../dock/FinderIcon.m && grep -q 'DMIconThemeSetDrawer(MSBDIconFinder' ../dock/FinderIcon.m && grep -q 'UIImage \*themed = DMFinderThemedImage();' ../dock/FinderIcon.m"
check "Launchpad asks the chain (its style's item), hides the App Library picture under it, and gives it back" \
  "grep -q 'DMIconThemePicture(MSBDIconLaunchpadItem(classic)' ../dock/Launchpad.m && grep -q 'DMLaunchpadHideOwn(imageView, overlay, YES)' ../dock/Launchpad.m && [ \$(grep -c 'DMLaunchpadHideOwn(imageView, overlay, NO)' ../dock/Launchpad.m) = 2 ]"
check "Downloads asks the chain, its folder drawn as the fallback" "grep -q 'DMIconThemePicture(MSBDIconDownloads' ../dock/Downloads.m && grep -q 'DMIconThemeSetDrawer(MSBDIconDownloads' ../dock/Downloads.m"
check "the Trash asks the chain for its empty / full bin, darkens any picture under a drag, Eject stays drawn" \
  "grep -q 'DMIconThemePicture(MSBDIconTrashItem(full)' ../dock/TrashIcon.m && grep -q 'self.hover ? DMTrashDarkened(base) : base' ../dock/TrashIcon.m && grep -q 'if (look != DMTrashLookEject)' ../dock/TrashIcon.m"
check "every Dock view asks again when a theme engine refreshed" "[ \$(grep -l 'DMIconThemeChangedNotification' ../dock/FinderIcon.m ../dock/Launchpad.m ../dock/Downloads.m ../dock/TrashIcon.m | wc -l) = 4 ]"
check "Activity Monitor: SBApplicationIcon with our data source where the chain is there, its own picture methods only where not" \
  "grep -q 'Class base = themable ? objc_getClass(\"SBApplicationIcon\") : leaf;' ../statusbar/AppLibraryApps.h && grep -q 'if (!themable) {   // (its own picture methods' ../statusbar/AppLibraryApps.h && grep -q 'MSBDIconAttachSource(icon, MSBDIconActivityMonitor' ../statusbar/AppLibraryApps.h"
check "Activity Monitor's bundle id is its own id only on the chain (unchanged where not)" \
  "grep -q 'kDMALActMonIdentifier, gDMALThemable ? kDMALActMonIdentifier : nil' ../statusbar/AppLibraryApps.h"
check "the chain's classes never override a picture method (a theme engine's hooks on SBApplicationIcon must run)" \
  "! awk '/^static void MSBDIconThemeAppOverrides/,/^}/; /^static Class MSBDIconThemableClass/,/^}/' ../common/IconTheme.h | grep -q -E 'iconImageWithInfo|generateIconImageWithInfo|unmaskedIconImageWithInfo|genericIconImageWithInfo'"
check "our data source never answers bundleIdentifier (SpringBoard would take it for an app)" "! grep -q '\"bundleIdentifier\"' ../common/IconTheme.h"
check "the probe runs SpringBoard's own SBLeafIcon chain before anything is shown" \
  "grep -q 'class_getMethodImplementation(leaf, @selector(generateIconImageWithInfo:))' ../common/IconTheme.h && grep -q 'class_getMethodImplementation(leaf, @selector(unmaskedIconImageWithInfo:))' ../common/IconTheme.h"
check "no UIKit in the shape check or the probe (Activity Monitor's class is made in a constructor: +[UIScreen mainScreen] threw there, w03)" \
  "! awk '/^static BOOL MSBDIconThemeShapeOK/,/^}/; /^static BOOL MSBDIconThemeReady/,/^}/; /^static Class MSBDIconSourceClass/,/^}/; /^static Class MSBDIconThemableClass/,/^}/' ../common/IconTheme.h | grep -q -E 'UIScreen|UIGraphics|imageWithActions|imageNamed|UIImage alloc'"
check "Activity Monitor's class: the shapes only in the constructor, the probe before its first icon (its own picture methods back if it fails)" \
  "grep -q 'BOOL themable = MSBDIconThemeShapeOK();' ../statusbar/AppLibraryApps.h && grep -q 'if (gDMALThemable && !MSBDIconThemeReady()) DMALThemeOff();' ../statusbar/AppLibraryApps.h && ! grep -q 'themable = MSBDIconThemeReady()' ../statusbar/AppLibraryApps.h"
check "the crash map: the chain in the status bar's library is Activity Monitor's" "grep -q '^file MacStatusBarCore ^IconTheme\\\\.h\$ actmonLibrary' crashmap-rules.txt"
[ $fails = 0 ] && echo "test-icontheme: all wiring checks pass" || { echo "test-icontheme: wiring checks FAILED"; exit 1; }
