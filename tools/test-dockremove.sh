#!/bin/bash
# test-dockremove.sh: Remove from Dock and an app dropped on the Trash follow the Dock part's own switch, not Magnify Icons (1.8.7.3, audit M6 of
# 1.8.7.2) -- see test-dockremove.m. The real code is cut out of dock/Dock.x (the settings' reading DMLoadPrefs with the Dock's own globals, the
# menu's Remove from Dock, the removal itself) and dock/TrashIcon.m (the bin's drop side) -- DR_DOCK_X / DR_TRASH_M: other copies, e.g. the code
# before the fix -- and run on the Mac (Mac Catalyst); then a site check; then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
D0=${DR_DOCK_X:-../dock/Dock.x}; T0=${DR_TRASH_M:-../dock/TrashIcon.m}
# one function, method or constant of a file, from its first line: to the closing brace in column 0, or that line alone when its braces close on it
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1; s=$0; gsub(/"[^"]*"/, "", s); o=gsub(/[{]/, "", s); c=gsub(/[}]/, "", s); print; if (o == c) exit; next} f {print} f && /^[}]/ {exit}' "$1"; }
globals() { awk '/^static BOOL    gEnabled /{f=1} f && /^static (BOOL|CGFloat|int) +g[A-Za-z]+ *=/ {print} f && /^static int     gDockPosition /{exit}' "$1"; }

DR_TY='static NSString * const kDMRemoveFromDockType = '
DR_OB='static id DMObj(id o, NSString *sel) {'
DR_MR='static id DMIconModelRoot(id *mgrOut, id *modelOut) {'
DR_KD='static BOOL DMIconKeptInDock(id icon) {'
DR_RM='static BOOL DMRemoveFromDock(id icon) {'
DR_OW='static BOOL DMIsOwnAppIcon(id icon) {'
DR_GT='BOOL DMDockAppsCanLeave(void) {'   # (the shared test, from 1.8.7.3: taken when the file has it)
DR_TR='BOOL DMTrashRemoveIconFromDock(id icon) {'
DR_DI='BOOL DMTrashIconDragInfo(id session, MSBDTrashIconDrag *info, id *iconOut) {'
DR_LP='static void DMLoadPrefs(void) {'
DR_SI='- (NSArray *)applicationShortcutItems {'
DR_AS='+ (void)activateShortcut:(id)item withBundleIdentifier:(NSString *)bundleID forIconView:(id)iconView {'
DR_CH='- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {'
DR_PD='- (void)dropInteraction:(UIDropInteraction *)interaction performDrop:(id<UIDropSession>)session {'
DR_SE='- (void)dropInteraction:(UIDropInteraction *)interaction sessionDidEnd:(id<UIDropSession>)session {'

run() {   # $1 Dock.x, $2 TrashIcon.m, $3 work dir, $4 quiet; the number of failed checks
  local D=$1 T=$2 d=$3 q=$4 n=0 h out
  mkdir -p "$d"
  for h in "$DR_TY" "$DR_OB" "$DR_MR" "$DR_KD" "$DR_RM" "$DR_OW" "$DR_TR" "$DR_DI" "$DR_LP" "$DR_SI" "$DR_AS"; do
    [ -n "$(fn "$D" "$h")" ] || { echo "FAIL  $D: no function starting \"$h\""; return 99; }; done
  for h in "$DR_CH" "$DR_PD" "$DR_SE"; do [ -n "$(fn "$T" "$h")" ] || { echo "FAIL  $T: no method starting \"$h\""; return 99; }; done
  [ -n "$(globals "$D")" ] || { echo "FAIL  $D: no globals block"; return 99; }
  globals "$D" > "$d/dr-globals.inc"
  { for h in "$DR_TY" "$DR_OB" "$DR_MR" "$DR_KD" "$DR_RM" "$DR_OW" "$DR_GT" "$DR_TR" "$DR_DI" "$DR_LP"; do fn "$D" "$h"; done; } > "$d/dr-dock.inc"
  { fn "$D" "$DR_SI"; fn "$D" "$DR_AS"; } | sed 's/%orig/DROrig(self)/' > "$d/dr-menu.inc"   # (Logos: SpringBoard's own method, a stand-in)
  { fn "$T" "$DR_CH"; fn "$T" "$DR_PD"; fn "$T" "$DR_SE"; } > "$d/dr-trash.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-dockremove.m || { echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  # (the site check) TrashIcon.m is its own file in the build: it declares the shared test it asks, Dock.x's
  if grep -qF 'MSBDTrashRemovesFromDock(info) && DMDockAppsCanLeave()' "$T"; then
    if grep -qF 'extern BOOL DMDockAppsCanLeave(void);' "$T"; then [ -n "$q" ] || echo "PASS  TrashIcon.m declares Dock.x's DMDockAppsCanLeave (it builds)"
    else [ -n "$q" ] || echo "FAIL  TrashIcon.m asks DMDockAppsCanLeave without declaring it"; n=$((n + 1)); fi
  fi
  return $n
}

run "$D0" "$T0" "$W/real"; rc=$?
if [ -z "$DR_DOCK_X$DR_TRASH_M" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (dock|trash), $3 perl expression
    local d="$W/m$((++k))" D=$D0 T=$T0 c
    mkdir -p "$d"
    if [ "$2" = dock ]; then c="$d/Dock.x"; perl -pe "$3" "$D0" > "$c"; D=$c; else c="$d/TrashIcon.m"; perl -pe "$3" "$T0" > "$c"; T=$c; fi
    if cmp -s "$c" "$([ "$2" = dock ] && echo "$D0" || echo "$T0")"; then echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; fi
    run "$D" "$T" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "the shared test is Magnify Icons again" dock 's/^BOOL DMDockAppsCanLeave\(void\) \{ return gTweakOn; \}/BOOL DMDockAppsCanLeave(void) { return gEnabled; }/'
  mtf "the menu's Remove from Dock waits for Magnify Icons again" dock 's/if \(!DMDockAppsCanLeave\(\) \|\| !itemClass/if (!gEnabled || !itemClass/'
  mtf "the removal waits for Magnify Icons again" dock 's/if \(!DMDockAppsCanLeave\(\) \|\| !DMIconKeptInDock\(icon\)/if (!gEnabled || !DMIconKeptInDock(icon)/'
  mtf "Activity Monitor's removal waits for Magnify Icons again" dock 's/if \(DMDockAppsCanLeave\(\) && DMIsOwnAppIcon\(icon\)\)/if (gEnabled \&\& DMIsOwnAppIcon(icon))/'
  mtf "the bin takes a drag without asking the shared test again" trash 's/BOOL yes = DMTrashIconDragInfo\(session, &info, &icon\) && MSBDTrashRemovesFromDock\(info\) && DMDockAppsCanLeave\(\);/BOOL yes = DMTrashIconDragInfo(session, \&info, \&icon) \&\& MSBDTrashRemovesFromDock(info);/'
  mtf "the drop keeps the app without asking the shared test again" trash 's/if \(DMTrashIconDragInfo\(session, &info, &icon\) && MSBDTrashRemovesFromDock\(info\) && DMDockAppsCanLeave\(\)\) self\.pendingIcon/if (DMTrashIconDragInfo(session, \&info, \&icon) \&\& MSBDTrashRemovesFromDock(info)) self.pendingIcon/'
  mtf "TrashIcon.m without its declaration" trash '$_ = "" if /^extern BOOL DMDockAppsCanLeave\(void\);/'
fi
exit $rc
