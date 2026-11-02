#!/bin/bash
# Mac test of the Battery Use group on the Battery Health page (macsettings/BatteryUse.x, battery drain F1): where it goes (test-batteryuse.m, the
# real MSBUInsertIndex / MSBUHasGroup), and wiring: the Sleep Guard switch (our domain, on unless switched off, the helper told), the "iPad Can't
# Sleep" row only while the helper says so, a fresh look asked only for an old state (no rebuild loop), the rebuild only while the page shows,
# nothing while another battery health tweak owns the page.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
U=../macsettings/BatteryUse.x
awk '/^static NSUInteger MSBUInsertIndex\(NSArray \*specs\) \{/,/^}/' $U > "$W/insert.inc"
awk '/^static BOOL MSBUHasGroup\(NSArray \*specs\) \{/,/^}/' $U >> "$W/insert.inc"
clang -O0 -fobjc-arc -Wall -I"$W" -framework Foundation -o "$W/tbu" test-batteryuse.m && "$W/tbu" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
F="awk '/^static NSArray \\*MSBUSpecifiers\\(UIViewController \\*page\\) \\{/,/^}/' $U"
check "Sleep Guard: a switch on our domain's sleepGuard key, on by default, telling the helper" \
  "$F | grep -q '\\[sw setProperty:@MSBD_SG_KEY forKey:@\"key\"\\];' && $F | grep -q '\\[sw setProperty:@MSBD_SG_DOMAIN forKey:@\"defaults\"\\];' && $F | grep -q '\\[sw setProperty:@YES forKey:@\"default\"\\];' && $F | grep -q '\\[sw setProperty:@MSBD_SG_CHANGED forKey:@\"PostNotification\"\\];'"
check "\"iPad Can't Sleep\" only while the helper says the iPad can't sleep and something is stuck" \
  "$F | grep -q 'if (\\[st\\[@\"cantSleep\"\\] boolValue\\] && \\[st\\[@\"stuck\"\\] intValue\\] > 0) {'"
check "a fresh look asked for only when the state is older than a minute (a rebuild after the helper's answer asks nothing)" \
  "$F | grep -q 'if (time(NULL) - \\[st\\[@\"checked\"\\] doubleValue\\] > 60) notify_post(MSBD_SG_CHECK);'"
check "the page rebuilt on the helper's update only while it shows" \
  "grep -q 'if (page.isViewLoaded && page.view.window) \\[page reloadSpecifiers\\];' $U"
check "the group put into the page's own list (its _specifiers), once" \
  "awk '/^- \\(id\\)specifiers \\{/,/^}/' $U | grep -q 'MSBUHasGroup(r)) return r;' && awk '/^- \\(id\\)specifiers \\{/,/^}/' $U | grep -q 'object_setIvarWithStrongDefault(self, iv, m);'"
check "nothing while another battery health tweak owns the page (as BatteryHealth.x)" \
  "awk '/^static void MSBUTryInit\\(void\\) \\{/,/^}/' $U | grep -q 'if (MSBDTweakPresent(\"BatteryHealthEnabler\", YES)) return;'"
check "the helper and Settings use the same names (the state file, the check and update notifications)" \
  "grep -q '#define MSBD_SG_CHECK   \"com.besiktasliseba.sleepguard.check\"' $U && grep -q '#define MSBD_SG_CHECK   \"com.besiktasliseba.sleepguard.check\"' ../macsettings/sshtoggled/SleepGuardDaemon.h && grep -q '#define MSBD_SG_UPDATED \"com.besiktasliseba.sleepguard.updated\"' $U && grep -q '#define MSBD_SG_UPDATED \"com.besiktasliseba.sleepguard.updated\"' ../macsettings/sshtoggled/SleepGuardDaemon.h"
check "BatteryUse.x is built into MacSettings" "grep -q '^MacSettings_FILES = .* BatteryUse.x' ../macsettings/Makefile"
[ $fails = 0 ] && echo "test-batteryuse: all checks pass" || { echo "test-batteryuse: checks FAILED"; exit 1; }
