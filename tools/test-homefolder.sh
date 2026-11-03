#!/bin/bash
# Mac test of the windows stepping aside for a Home Screen folder (1.7.9; code review of d73fb47): the rule (common/HomeFolderRule.h,
# test-homefolder.c) and its wiring in SpringBoard -- every fade asks the rule, never -hasOpenFolder alone, and an app icon's tap or a native
# window made active ends it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -Werror -o "$W/thf" test-homefolder.c && "$W/thf" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
X=../statusbar/StatusBar.x; SM=../statusbar/SMDesktop.h; N=../statusbar/NativeWindow.h; H=../common/HomeFolderRule.h
check "the engines' windows: the fade's first look is the rule's, whatever the engine, and its answer is what fades them" \
  "fn $X 'static void DMSyncWindowFade(' | sed -n 2p | grep -q 'BOOL folder = DMHomeFolderShowing();' && fn $X 'static void DMSyncWindowFade(' | grep -q 'BOOL want = DMLibraryVisible() || gHomeMenuOpen || folder;'"
check "the Stage Manager engine's stages: the rule's answer" \
  "fn $SM 'static void DMSMDeskSyncFade(' | grep -q 'BOOL folder = DMHomeFolderShowing();' && fn $SM 'static void DMSMDeskSyncFade(' | grep -q '(DMLibraryVisible() || gHomeMenuOpen || folder) && !DMSwitcherVisible()'"
check "our native windows (Finder, Activity Monitor, TextEdit): the rule's answer" \
  "fn $X 'static void DMNativeTick(' | grep -q 'BOOL away = DMLibraryVisible() || gHomeMenuOpen || DMHomeFolderShowing() || DMSwitcherVisible()'"
check "-hasOpenFolder is read in one place for the windows (the rule's input), not as the answer (the old DMHomeFolderOpen is gone)" \
  "[ \$(grep -c '@\"hasOpenFolder\"' $X) = 2 ] && grep -q 'static BOOL DMHomeFolderOpenNow(void) { return \[DMBoolStr(DMCall(DMSBManager(\"SBIconController\"), @\"iconManager\"), @\"hasOpenFolder\") isEqualToString:@\"Y\"\]; }' $X \
   && ! grep -q 'DMHomeFolderOpen()' $X $SM $N ../statusbar/FinderFolders.h"
check "the rule's inputs: the menu bar's app in front, and whether a full-screen app covers the Home Screen (asked only as it opens)" \
  "fn $X 'static BOOL DMHomeFolderShowing(' | grep -q 'MSBDHomeFolderFrontID(\[DMActiveApp() bundleIdentifier\].UTF8String)' \
   && fn $X 'static BOOL DMHomeFolderShowing(' | grep -q 'BOOL covered = open && !gHomeFolder.wasOpen && (DMSMEngine() ? DMSMFrontIsFullScreen() : DMFrontApp() != nil);' \
   && fn $X 'static BOOL DMHomeFolderShowing(' | grep -q 'MSBDHomeFolderStep(&gHomeFolder, open, front, covered)'"
check "an app icon tapped ends it: the tap's recognizer action, shape-checked (v@:@), not for a folder's icon or while editing, installed at start" \
  "fn $X 'static void DMHomeFolderTapInstall(' | grep -q 'NSSelectorFromString(@\"tapGestureDidChange:\")' && fn $X 'static void DMHomeFolderTapInstall(' | grep -q 'isEqualToString:@\"v@:@\"\]) {' \
   && fn $X 'static void DMIconTapGesture(' | grep -q 'UIGestureRecognizerStateEnded' && fn $X 'static void DMIconTapGesture(' | grep -q '@\"isFolderIcon\"' && fn $X 'static void DMIconTapGesture(' | grep -q '@\"isEditing\"' \
   && fn $X 'static void DMIconTapGesture(' | grep -q 'DMHomeFolderMovedOn(@\"an app icon was tapped\");' && fn $X 'static void DMIconTapGesture(' | grep -q 'o_IconTapGesture(self, _cmd, g);' \
   && grep -q 'if (!DMCtorSkip(\"foldertap\")) DMHomeFolderTapInstall();' $X"
check "a native window made active ends it (another window than the active one)" \
  "fn $N 'static void DMNativeSetActive(' | grep -q 'if (w && w != gNativeActive) DMHomeFolderMovedOn(@\"a native window was made active\");'"
check "  ... and the windows come back at once, not at the next tick" \
  "fn $X 'static void DMHomeFolderMovedOn(' | grep -q 'MSBDHomeFolderMovedOn(&gHomeFolder, DMHomeFolderOpenNow());' && fn $X 'static void DMHomeFolderMovedOn(' | grep -q 'dispatch_async(dispatch_get_main_queue(), ^{ DMSyncWindowFade(); });'"
check "the rule header is plain C (the Mac test runs this very code)" "! grep -q -E '#import|@interface|NSString' $H"
check "no em dash in the change's files" "! grep -q \$'\\xe2\\x80\\x94' $H test-homefolder.c test-homefolder.sh"
[ $fails = 0 ] && echo "test-homefolder: all checks pass" || { echo "test-homefolder: checks FAILED"; exit 1; }
