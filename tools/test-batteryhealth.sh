#!/bin/bash
# Mac test of the Battery Health page on iPad (macsettings/BatteryHealth.x, 1.7.8): its figures (common/BatteryHealthFigures.h, test-batteryhealth.c),
# then the wiring as built: Apple's isiPhone question answered "yes" only while the Battery page builds its Battery Health row, Apple's own answers
# kept where it has them, each version's hooks only where that version has the method, and the page left to another battery health tweak.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tbh" test-batteryhealth.c
"$W/tbh"
B=../macsettings/BatteryHealth.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
check "built into the Settings part" "grep -q '^MacSettings_FILES = .* BatteryHealth.x' ../macsettings/Makefile"
check "isiPhone is 'yes' only inside the row's builder, on the main thread (15/16 and 17/18 builders)" \
  "fn '+ (BOOL)isiPhone {' $B | grep -q 'return gMSBHGateDepth > 0 && \[NSThread isMainThread\] ? YES : %orig;' && fn '- (id)setUpBatteryHealthSpecifiers {' $B | tr -d '\n' | grep -q 'gMSBHGateDepth++;    id r = %orig;    gMSBHGateDepth--;    return r;' && fn '- (id)setUpBatteryHealthGroup {' $B | tr -d '\n' | grep -q 'gMSBHGateDepth++;    id r = %orig;    gMSBHGateDepth--;    return r;'"
check "Apple's own figures win: ours only where Apple's getter has none (15-17, and 18's error variant)" \
  "grep -q 'if (apple >= 0) return apple;' $B && [ \$(grep -c 'if (apple >= 0) return apple;' $B) = 2 ] && grep -q 'getBatteryMaximumCapacityPercentWithError:(NSError \*\*)error' $B"
check "service state, battery check and management state go through the tested rules" \
  "fn '+ (int)getBatteryHealthServiceState {' $B | tr -d '\\n' | grep -q 'int apple = %orig;    return MSBDBatteryHealthServiceState(apple, MSBHFiguresNow().percent);' && fn '+ (int)genuineBatteryStatus {' $B | tr -d '\\n' | grep -q 'int apple = %orig;    return MSBDBatteryGenuineStatus(apple, MSBHFiguresNow().percent);' && fn '+ (int)getManagementState {' $B | tr -d '\\n' | grep -q 'int apple = %orig;    return MSBDBatteryManagementState(apple, MSBHFiguresNow().percent);'"
check "the figure is NominalChargeCapacity / DesignCapacity (AppleRawMaxCapacity when there is none), DesignCapacity also from BatteryData" \
  "grep -q 'f.percent = MSBDBatteryHealthPercent(MSBHInt(d, @\"NominalChargeCapacity\"), MSBHInt(d, @\"AppleRawMaxCapacity\"), design);' $B && grep -q 'if (design <= 0) design = MSBHInt(bd, @\"DesignCapacity\");' $B"
check "every version's hook only where the method is (no %orig into nothing)" \
  "fn 'static void MSBHTryInit(void) {' $B | grep -q 'if (MSBHHas(resource, YES, \"getBatteryMaximumCapacityPercent\")) %init(MSBHCapacity);' && fn 'static void MSBHTryInit(void) {' $B | grep -q 'else if (MSBHHas(resource, YES, \"getBatteryMaximumCapacityPercentWithError:\")) %init(MSBHCapacity18);' && fn 'static void MSBHTryInit(void) {' $B | grep -q 'if (MSBHHas(resource, YES, \"isQMaxUnknown\")) %init(MSBHQMax);' && fn 'static void MSBHTryInit(void) {' $B | grep -q 'if (MSBHHas(health, NO, \"setUpChargingOptionsSpecifiers\")) %init(MSBHNoSmartCharging17);' && fn 'static void MSBHTryInit(void) {' $B | grep -q 'else if (MSBHHas(health, NO, \"smartChargingGroupSpecifier\")) %init(MSBHNoSmartCharging15);' && fn 'static void MSBHTryInit(void) {' $B | grep -q 'if (MSBHHas(health, NO, \"cleanEnergyChargingGroupSpecifier\")) %init(MSBHNoCleanEnergy);'"
check "  ... and nothing at all on a page we do not know (no row builder, no isiPhone)" \
  "fn 'static void MSBHTryInit(void) {' $B | grep -q 'if ((!gate15 && !gate17) || !MSBHHas(modeling, YES, \"isiPhone\")) { MSBHLog(@\"no row builder or isiPhone: Apple.s page untouched\"); return; }'"
check "another battery health tweak loaded in Settings: nothing installed, the page is that tweak's" \
  "fn 'static void MSBHTryInit(void) {' $B | grep -q 'if (MSBHOtherTweakLoaded()) { MSBHLog(@\"another battery health tweak is loaded: its page, nothing installed\"); return; }' && grep -q 'return MSBDTweakPresent(\"BatteryHealthEnabler\", YES);' $B"
check "iPhone features left out: Peak Performance, Optimized Battery Charging (15/16 switch, 17/18 options), Clean Energy Charging" \
  "fn '- (id)peakPowerCapacityGroupSpecifier {' $B | grep -q '    return @\[\];' && fn '- (id)smartChargingGroupSpecifier {' $B | grep -q '    return @\[\];' && fn '- (id)setUpChargingOptionsSpecifiers {' $B | grep -q '    return @\[\];' && fn '- (id)cleanEnergyChargingGroupSpecifier {' $B | grep -q '    return @\[\];'"
check "Cycle Count row under Maximum Capacity, read through a getter added to Apple's page class (stock title-value cell)" \
  "grep -q 'class_addMethod(health, sel_registerName(\"msbdCycleCount:\"), (IMP)MSBHCycleCountValue, \"@24@0:8@16\");' $B && grep -q 'target:self set:NULL get:NSSelectorFromString(@\"msbdCycleCount:\")' $B"
check "installed when BatteryUsageUI loads (NSBundle's notification, before the page is made), with the dyld fallback" \
  "grep -q 'CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, MSBHBundleLoaded, (__bridge CFStringRef)NSBundleDidLoadNotification' $B && grep -q '_dyld_register_func_for_add_image(MSBHImageAdded);' $B"
check "the header: Apple's iPad sentence (normal at 80 % or more, else its service sentence), English where the table has none, Apple's link kept" \
  "fn 'static void MSBHSetHeaderText(id specs, Class page) {' $B | grep -q 'BOOL normal = percent >= 80;' && fn 'static void MSBHSetHeaderText(id specs, Class page) {' $B | grep -q 'MSBHString(page, normal ? @\"BATTERY_HEALTH_STATE_FOOTER_NORMAL_IPAD\" : @\"BATTERY_HEALTH_STATE_FOOTER_SERVICE\")' && fn 'static void MSBHSetHeaderText(id specs, Class page) {' $B | grep -q 'NSRange r = \[text rangeOfString:link\];' && fn 'static void MSBHSetHeaderText(id specs, Class page) {' $B | grep -q 'setProperty:NSStringFromRange(r) forKey:\*rangeKey' && fn '- (id)aboutBatteriesGroupSpecifier {' $B | grep -q 'MSBHSetHeaderText(r, \[(id)self class\]);'"
check "  ... and no figure: Apple's page as it is" "fn 'static void MSBHSetHeaderText(id specs, Class page) {' $B | grep -q 'if (percent < 0) return;'"
check "Cycle Count titled from Apple's table where it has one (17/18), English otherwise" "grep -q 'preferenceSpecifierNamed:MSBHString(\[(id)self class\], @\"CYCLE_COUNT_TITLE\") ?: @\"Cycle Count\"' $B"
[ $fails = 0 ] && echo "test-batteryhealth: wiring checks pass" || { echo "test-batteryhealth: wiring checks FAILED"; exit 1; }
