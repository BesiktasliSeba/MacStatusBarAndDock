#!/bin/bash
# Mac test of the battery percentage inside the icon (1.8.4.2, off unless switched on): the rule (common/BatteryInside.h, test-batteryinside.c), the
# Settings row, the pref, iPadOS's own drawing asked first with its types read, the crash guard's target.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -o "$W/t" test-batteryinside.c && "$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
B=../statusbar/BatteryMenu.h; S=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/Resources/Root.plist; C=crashmap-rules.txt
check "the Settings row: right after Battery Menu, off by default, in a stock-hidden group with a footer, no em dash" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; i=[x.get('id') for x in it].index('BATTERY_INSIDE'); s=it[i]; g=it[i-1]; sys.exit(0 if s['key']=='batteryPercentInside' and s['default'] is False and s['cell']=='PSSwitchCell' and g['cell']=='PSGroupCell' and g['stockHides'] and it[i-2].get('id')=='BATTERY_MENU' and '\\u2014' not in g['footerText'] else 1)\""
check "read with the other settings: a boolean only, never set is off" "grep -qF 'DMBattInsideApplyPref(bi && CFGetTypeID(bi) == CFBooleanGetTypeID() && CFBooleanGetValue(bi));' $S"
check "every bar's layout places it, after the battery's button" "awk '/DMBattLayoutButton\(fg, left, k\);/{a=NR} /DMBattInsideBar\(fg\);/{b=NR} END{exit !(a&&b&&b==a+1)}' $S"
check "nothing of ours touches a battery if it was never switched on" "grep -qF 'if (!everOn) return;' $B"
check "iPadOS's own drawing first, its setter's types read, undone only if we set it" \
  "! grep -qF 'setShowsPercentage:' $B && grep -qF 'BOOL show = b.known && MSBDBattInsideShows(shown, 0, 1, b.charging && !canHideBolt);' $B && grep -qF 'kBattInsideBoltKey, @YES' $B && grep -qF 'kBattInsideBoltKey, nil' $B"
check "one number, never two: iPadOS's own beside the icon wins" "grep -qF 'if ([v isKindOfClass:[UILabel class]]) iosOwn = YES;' $B && grep -qF 'BOOL shown = MSBDBattInsideShows(gBattInsideOn, iosOwn, 0, b.charging);' $B"
check "the crash guard turns it off, ahead of Battery Menu's rule" \
  "grep -qF 'target batteryPercentInside pref com.besiktasliseba.macstatusbar batteryPercentInside 0 0 Battery Percentage in Icon' $C && awk '/\^_\*DMBattInside\[A-Z\] batteryPercentInside/{a=NR} /\^_\*DMBatt\[A-Z\] batteryMenu/{b=NR} END{exit !(a&&b&&a<b)}' $C"
exit $fails
