#!/bin/bash
# Mac test of the link to Settings' Battery Health page at our groups (1.7.9: the battery menu's Charge Limit and Sleep Guard rows): the link and the
# path (common/BatteryHealthLink.h, test-batteryhealthlink.m), the battery menu's rows, and Settings' side (macsettings/BatteryHealthLink.x).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -fobjc-arc -Wall -framework Foundation -o "$W/tbhl" test-batteryhealthlink.m && "$W/tbhl" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
B=../statusbar/BatteryMenu.h; L=../macsettings/BatteryHealthLink.x
check "the battery menu: Charge Limit opens the page at the Charging group, Sleep Guard and iPad Can't Sleep at Battery Use, Battery Settings… Battery" \
  "fn $B 'static NSArray *DMBattMenuItems(' | grep -q 'DMBattOpenSettings(@MSBD_BH_CHARGING_GROUP, @\"battery settings (charge limit)\")' \
   && [ \$(fn $B 'static NSArray *DMBattMenuItems(' | grep -c 'DMBattOpenSettings(@MSBD_BH_BATTERY_USE_GROUP, ') = 2 ] \
   && fn $B 'static NSArray *DMBattMenuItems(' | grep -q 'DMBattOpenSettings(nil, @\"battery settings\")' \
   && grep -q 'DMOpenURL(group ? MSBDBatteryHealthLink(group) : @\"prefs:root=BATTERY_USAGE\", why);' $B"
check "the groups the link names are the ones the page has (BatteryUse.x's Battery Use group; BatteryHealth.x's Charging group where the job is in the tree)" \
  "grep -q 'groupSpecifierWithName:@\"Battery Use\"\\];' ../macsettings/BatteryUse.x && grep -q '\\[g setIdentifier:@\"MSBD_BATTERY_USE_GROUP\"\\];' ../macsettings/BatteryUse.x \
   && grep -q '#define MSBD_BH_BATTERY_USE_GROUP \"MSBD_BATTERY_USE_GROUP\"' ../common/BatteryHealthLink.h \
   && { ! grep -q 'MSBD_CHARGING_GROUP' ../macsettings/BatteryHealth.x || grep -q 'groupSpecifierWithID:@\"MSBD_CHARGING_GROUP\"\\]' ../macsettings/BatteryHealth.x; } \
   && grep -q '#define MSBD_BH_CHARGING_GROUP \"MSBD_CHARGING_GROUP\"' ../common/BatteryHealthLink.h"
check "Settings: the Battery page's row found by its page (BatteryHealthUIController), not by a fixed identifier" \
  "fn $L 'static NSString *MSBHLRowID(' | grep -q 'if (health && d && \\[d isSubclassOfClass:health\\] && \\[sp identifier\\].length) return \\[sp identifier\\];'"
check "  ... the link handed on to Settings' own handling with the row's identifier (its own push), the prepare step too" \
  "fn $L '- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {' | grep -q 'u\\[@\"path\"\\] = mapped;' && grep -q '%orig(u, completion);' $L \
   && grep -q 'BOOL r = %orig(rowID, d, animate, completion);' $L"
check "  ... the group shown at the page's top once the page is on screen and settled, from either way the rest of the link comes" \
  "grep -q 'MSBHLShowGroup(page, path, 0);' $L && fn $L 'static void MSBHLAwait(' | grep -q 'MSBHLShowGroup(page, group, 0);' && fn $L 'static void MSBHLShowGroup(' | grep -q 'MSBDScrollOffsetForGroup('"
check "  ... kept there while the page's own scroll animation moves the list (shown again once it rests, twice at most), never against a touch" \
  "fn $L 'static void MSBHLKeepGroup(' | grep -q 'if (t.isTracking || t.isDragging || t.isDecelerating)' && fn $L 'static void MSBHLKeepGroup(' | grep -q 'if (again >= 2) return;' \
   && fn $L 'static void MSBHLKeepGroup(' | grep -q 'fabs(now - y) >= 1.0 && fabs(now - last) < 0.5' && fn $L 'static void MSBHLShowGroup(' | grep -q 'MSBHLKeepGroup(t, page, group, y, y, 0, 0);'"
check "  ... hooked only with the types read, with another battery health tweak too (no step-aside: the page is ours), built into MacSettings" \
  "fn $L 'static void MSBHLTryInit(' | grep -q 'if (prepare) %init(MSBHLPrepare);' && ! fn $L 'static void MSBHLTryInit(' | grep -q -i 'BatteryHealthEnabler\\|MSBDTweakPresent' \
   && ! grep -q 'OtherTweaks.h' $L && grep -q '^MacSettings_FILES = .* BatteryHealthLink.x' ../macsettings/Makefile"
check "  ... Shuffle's misrouted link taken back in Settings' URL handler (from Settings' start, with the types read): our link as sent, routed by Shuffle's own answer for Battery alone" \
  "grep -q 'NSString \\*sent = MSBDBatteryHealthLinkAsSent(' $L && grep -q 'NSString \\*routed = sent ? MTSShuffleRoute(sent) : nil;' $L && grep -q '%orig(u ?: url, animated, fromSearch, completion);' $L \
   && fn $L '%ctor {' | grep -q 'processURL:animated:fromSearch:withCompletion:\", @\[@\"v@:@BB@?\", @\"v@:@BB@\"\])) %init(MSBHLShuffle);' \
   && grep -q '^__attribute__((visibility(\"hidden\"))) NSString \\*MTSShuffleRoute(NSString \\*prefs) {' ../macsettings/TweakSearch.x && grep -q '^MacSettings_FILES = .* TweakSearch.x .*BatteryHealthLink.x' ../macsettings/Makefile"
check "no em dash in the feature's files" "! grep -q \$'\\xe2\\x80\\x94' $L ../common/BatteryHealthLink.h test-batteryhealthlink.m test-batteryhealthlink.sh"
[ $fails = 0 ] && echo "test-batteryhealthlink: all checks pass" || { echo "test-batteryhealthlink: checks FAILED"; exit 1; }
