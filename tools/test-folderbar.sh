#!/bin/bash
# Mac test of the menu bar while a Home Screen folder is open (1.7.9; KT on the A12Z: the bar shifted left behind the folder; the M1's regression:
# with a folder left open behind an app the bar took no touches). iPadOS hides the real bar and puts a stand-in under the folder as it opens
# (-[SBFolderController _addFakeStatusBarView]); with our bar that swap is not made, and nothing else of iPadOS's bar hiding changes.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
X=../statusbar/StatusBar.x
check "a folder's opening makes no stand-in and hides no bar: the swap is not called on (only the debug comparison flag calls it)" \
  "[ \$(fn $X 'static void DMFolderAddFakeBar(' | grep -c 'o_DMFolderAddFakeBar(self, _cmd)') = 1 ] && fn $X 'static void DMFolderAddFakeBar(' | grep -q 'DMTestFlag(\"/tmp/msb-folderbar-stock\")' \
   && fn $X 'static void DMFolderAddFakeBar(' | awk '/#if DEBUG/ {d=1} /o_DMFolderAddFakeBar\(self, _cmd\)/ {c=d} /#endif/ {d=0} END {exit !c}'"
check "only the swap is hooked: the folder delegate's hide (also the edit mode's and the widget sheet's) and the close's undo stay iPadOS's" \
  "! grep -q 'folderControllerWantsToHideStatusBar:animated:\")' $X && ! grep -q 'MSHookMessageEx([^;]*fakeStatusBarForFolderController' $X \
   && ! grep -q 'MSHookMessageEx(c, undo' $X"
check "shape-checked: -_addFakeStatusBarView and its undo -_removeFakeStatusBarAndAssertionIfExists are v@:, else left alone" \
  "fn $X 'static void DMFolderBarInstall(' | grep -q 'NSSelectorFromString(@\"_addFakeStatusBarView\"), undo = NSSelectorFromString(@\"_removeFakeStatusBarAndAssertionIfExists\")' \
   && fn $X 'static void DMFolderBarInstall(' | grep -q 'if (!\[t isEqualToString:@\"v@:\"\] || !\[ut isEqualToString:@\"v@:\"\]) {' \
   && fn $X 'static void DMFolderBarInstall(' | awk '/return;/ {r=NR} /MSHookMessageEx\(c, s, \(IMP\)DMFolderAddFakeBar/ {h=NR} END {exit !(r && h && r < h)}'"
check "installed at start with our bar only (after the stock bar's early return)" \
  "L1=\$(grep -n 'if (gStockBar) { DMSpotPublishOff();' $X | cut -d: -f1); L2=\$(grep -n 'if (!DMCtorSkip(\"folderbar\")) DMFolderBarInstall();' $X | cut -d: -f1); [ -n \"\$L1\" ] && [ -n \"\$L2\" ] && [ \$L1 -lt \$L2 ]"
check "no em dash in the change's files" "! grep -q \$'\\xe2\\x80\\x94' test-folderbar.sh && ! fn $X 'static void DMFolderBarInstall(' | grep -q \$'\\xe2\\x80\\x94'"
[ $fails = 0 ] && echo "test-folderbar: all checks pass" || { echo "test-folderbar: checks FAILED"; exit 1; }
