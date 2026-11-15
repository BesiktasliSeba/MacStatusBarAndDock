#!/bin/bash
# Mac test of MilkyWay4's "Launch As Window" row (statusbar/MilkyWayRow.h, test-milkywayrow.m): the rule -- where the row opens a window, and (1.8.7.5,
# audit L31 of 1.8.7.2) never for an app that has a MilkyWay window already --, the hook of -effectiveApplicationShortcutItems as built (cut out of
# StatusBar.x, run with a stand-in icon view and window finder), then, as built, that StatusBar.x asks it on the list both menu styles are built from,
# only while MilkyWay4 is our engine. MWR_H / MWR_SB_X: another MilkyWayRow.h / StatusBar.x (e.g. the code before the fix: a header without the
# window rule is stood in for by its place rule alone, as that code had it).
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=${MWR_H:-../statusbar/MilkyWayRow.h}; X=${MWR_SB_X:-../statusbar/StatusBar.x}
cp "$H" "$W/MilkyWayRow.h"
/usr/bin/grep -qF 'static BOOL DMMilkyRowKept(id location, BOOL hasWindow) {' "$W/MilkyWayRow.h" \
  || echo 'static BOOL DMMilkyRowKept(id location, BOOL hasWindow) { (void)hasWindow; return DMMilkyRowOpensWindowAt(location); }   // (not in this header: the place rule alone)' >> "$W/MilkyWayRow.h"
# the hook's lines, in the group installed 3 s after SpringBoard starts
B=$(awk '/^%group ZetsuIconItems/{on=1} on{print} on&&/^%end/{e++; if(e==2) exit}' "$X")
hook=$(printf '%s\n' "$B" | awk '/^- \(NSArray \*\)effectiveApplicationShortcutItems/{on=1} on{print} on&&/^}/{exit}')
printf '%s\n' "$hook" | perl -pe 's/^(\s*NSArray \*items = )%orig;$/$1self.kItems;/' > "$W/mwrow-hook.inc"
fails=0
if /usr/bin/grep -q '%orig' "$W/mwrow-hook.inc" || [ ! -s "$W/mwrow-hook.inc" ]; then echo "FAIL  the hook could not be cut out"; fails=1
else
  clang -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$W" -framework Foundation -o "$W/t" test-milkywayrow.m || { echo "FAIL  the test did not build"; exit 1; }
  "$W/t" || fails=1
fi
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the row goes through the hook of -effectiveApplicationShortcutItems, in the icon menu group" "[ -n \"\$hook\" ]"
check "... only while MilkyWay4 is our engine" "printf '%s\n' \"\$hook\" | sed -n '2,3p' | grep -qF 'if (DMActiveEngine() != DMEngineMilkyWay) return items;'"
check "... by the icon view's place and whether its app has a MilkyWay window already (here, minimized or on another desktop)" "printf '%s\n' \"\$hook\" | grep -qF 'id location = DMCall(self, @\"location\");' && printf '%s\n' \"\$hook\" | grep -qF 'NSString *app = DMIconViewApp(self);' \
   && printf '%s\n' \"\$hook\" | grep -qF 'BOOL hasWindow = app.length && DMFindMilkyWayWindow(app) != nil;' && printf '%s\n' \"\$hook\" | grep -qF 'DMMilkyRowKept(location, hasWindow)'"
check "... and the row is taken out where it doesn't open one" "printf '%s\n' \"\$hook\" | grep -qF '? items : DMMilkyRowsWithoutLaunch(items);' && printf '%s\n' \"\$hook\" | grep -qF 'return kept;'"
check "the window finder skips a window on its way out and finds minimized and other desktops' ones (they stay in MilkyWay's layer)" \
  "awk '/^static UIView \*DMFindMilkyWayWindow\(NSString \*bundleID\) \{/{f=1} f{print} f&&/^}/{exit}' $X | grep -qF 'if ([objc_getAssociatedObject(v, kStageClosingKey) boolValue]) continue;' \
   && awk '/^static UIView \*DMFindMilkyWayWindow\(NSString \*bundleID\) \{/{f=1} f{print} f&&/^}/{exit}' $X | grep -qF 'return shown ?: found;'"
check "... and an icon tap on such an app brings that window (DMWindowedLaunch asks DMSurfaceWindowForApp first, its MilkyWay branch the same finder)" \
  "awk '/^static BOOL DMWindowedLaunch\(NSString \*bundleID\) \{/{f=1} f{print} f&&/^}/{exit}' $X | sed -n '2,5p' | grep -qF 'if (DMSurfaceWindowForApp(bundleID)) return YES;' \
   && awk '/^static BOOL DMSurfaceWindowForApp\(NSString \*bundleID\) \{/{f=1} f{print} f&&/^}/{exit}' $X | grep -qF 'UIView *window = DMFindMilkyWayWindow(bundleID);'"
check "our own launch into a MilkyWay window still sends the same type (DMLaunchAsWindow: never through the menu's list)" "grep -qF '[item setType:@\"jp.yuri.milkyway3.launchinwindow\"];' $X"
check "a crash in the row's rule is the windowing's (the sym rule for DMMilky..., and the group's)" "grep -qF '|DMMilky|' crashmap-rules.txt && [ \"\$(grep -c '^static' $H)\" = \"\$(grep -c '^static [A-Za-z]* \*\?DMMilky' $H)\" ]"
if [ -z "$MWR_H$MWR_SB_X" ]; then   # made-to-fail copies of the header and the hook: each must fail
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 file (h or x), $3 perl expression
    local d="$W/m$((++k))"; mkdir -p "$d"; cp "$H" "$d/MilkyWayRow.h"; cp "$X" "$d/StatusBar.x"
    if [ "$2" = h ]; then perl -0pi -e "$3" "$d/MilkyWayRow.h"; cmp -s "$d/MilkyWayRow.h" "$H" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    else perl -0pi -e "$3" "$d/StatusBar.x"; cmp -s "$d/StatusBar.x" "$X" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }; fi
    if MWR_H="$d/MilkyWayRow.h" MWR_SB_X="$d/StatusBar.x" bash "$SELF" > "$d/out.txt" 2>&1; then echo "FAIL  not caught: $1"; fails=1
    else n=$(/usr/bin/grep -c 'FAIL' "$d/out.txt"); [ "$n" -gt 1 ] && echo "PASS  caught: $1 ($((n - 1)) check(s) fail)" || { echo "FAIL  made-to-fail copy \"$1\" did not run"; fails=1; }; fi
  }
  mtf "the window rule left out of the header (the audit's case)" h 's/    return !hasWindow && DMMilkyRowOpensWindowAt\(location\);/    return DMMilkyRowOpensWindowAt(location);/'
  mtf "the hook not asking for a window" x 's/BOOL hasWindow = app.length && DMFindMilkyWayWindow\(app\) != nil;/BOOL hasWindow = NO;/'
  mtf "the window rule dropping the App Library rule" h 's/    return !hasWindow && DMMilkyRowOpensWindowAt\(location\);/    return !hasWindow;/'
  mtf "the hook keeping the row for an app with a window" x 's/NSArray \*kept = DMMilkyRowKept\(location, hasWindow\)/NSArray *kept = DMMilkyRowOpensWindowAt(location)/'
fi
[ "$fails" = 0 ] && echo "test-milkywayrow wiring: passed" || { echo "test-milkywayrow wiring: FAILED"; exit 1; }
