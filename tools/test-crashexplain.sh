#!/bin/bash
# Mac test of common/CrashExplain.h (the guard's explanation, the Report a Problem text, the note about another tweak's crash) with a fake dpkg
# database and the real Settings pages' lists; run once as a supported iPadOS version and once acting as an untested one (17).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); mkdir -p "$W/dpkg/info" "$W/bundles/MacStatusBarPrefs.bundle" "$W/bundles/DockMagnificationPrefs.bundle"
cp ../statusbar/macstatusbarprefs/Resources/Root.plist "$W/bundles/MacStatusBarPrefs.bundle/"
cp ../dock/dockmagnificationprefs/Resources/Root.plist "$W/bundles/DockMagnificationPrefs.bundle/"
printf 'Package: com.example.someothertweak\nStatus: install ok installed\nVersion: 2.1\nName: Some Other Tweak\n\nPackage: com.example.aerial\nVersion: 5.0.1\nName: Aerial\n\nPackage: com.besiktasliseba.macstatusbaranddock\nVersion: 1.0.0\nName: MacStatusBar&Dock\n' > "$W/dpkg/status"
printf '/.\n/var/jb/Library/MobileSubstrate/DynamicLibraries/SomeOtherTweak.dylib\n/var/jb/Library/MobileSubstrate/DynamicLibraries/SomeOtherTweak.plist\n' > "$W/dpkg/info/com.example.someothertweak.list"
printf '/.\n/var/jb/Library/MobileSubstrate/DynamicLibraries/Aerial.dylib\n' > "$W/dpkg/info/com.example.aerial.list"
D="-DDEBUG=1 -DMSBD_GUARD_RECORD=\"$W/record.txt\" -DMSBD_GUARD_VERDICTS=\"$W/verdicts.txt\" -DMSBD_DPKG_DIR=\"$W/dpkg\" -DMSBD_PREF_BUNDLES=\"$W/bundles\" -DMSBD_TWEAKNAME_CACHE=\"$W/name.txt\""
clang -fobjc-arc -Wall -Wno-unused-function $D -framework Foundation -o "$W/t" test-crashexplain.m
"$W/t"; rm -f "$W"/*.txt; "$W/t" untested
rm -rf "$W"
