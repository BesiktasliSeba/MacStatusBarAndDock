#!/bin/bash
# Mac test of our choice pages (common/ChoicePage.h, test-choicepage.m; 1.8.0): every row of the Window Engine, Control Center Style and Banner
# Style pages in every state, then, in the code as built: one page controller draws them all (MSBChoiceListController; the engine page is it under
# its old name, which Settings' links open), each row as ChoicePage.h says -- greyed rows not picked, GET or the reason where the checkmark would
# be, rows left off.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-choicepage.m
"$W/t"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
P=../statusbar/macstatusbarprefs/MSBRootListController.m; S=../statusbar/macstatusbarsettings/StatusBarSettingsRow.x
check "one controller for the choice pages; the engine page is it under its own name (Settings' links: StatusBarSettingsRow.x)" \
  "grep -q '^@interface MSBChoiceListController : PSListItemsController$' $P && grep -q '^@interface MSBEngineListController : MSBChoiceListController$' $P \
   && grep -q 'NSClassFromString(target == 2 ? @\"MSBEngineListController\"' $S && [ \$(grep -c '^@implementation MSBEngineListController$' $P) = 1 ]"
check "the rows from ChoicePage.h: the engines with their states and Stage Manager's check; the Control Center Style with ours and BigSurCenter's" \
  "awk '/^- \\(NSDictionary \\*\\)msb_rowFor:/,/^}/' $P > \$W/rows && grep -q 'return MSBDChoiceEngineRow(value, st, st == 1 ? MSBEngineNameVersion(value) : nil, sm && MSBDStageManagerAvailable(), sm ? MSBDStageManagerVerdict(NULL, NULL) : 1);' \$W/rows \
   && grep -q 'int st = MSBEngineState(value);' \$W/rows \
   && grep -q 'return MSBDChoiceCCStyleRow(value, os, MSBDCCMacVerdictNow(NULL), MSBD_CC_MAC_BUILT, MSBDCCBigSurCenterInstalled(YES), MSBDStockBarStored());' \$W/rows"
check "  ... grouped Native / Third-Party (a row left off the page where it is not offered), the footers: the engines' why and license hint, Mac's why" \
  "grep -q 'if (\\[row\\[@\"hidden\"\\] boolValue\\]) continue;' $P && grep -q '\\[(row && \\[row\\[@\"native\"\\] boolValue\\] ? native : thirdParty) addObject:s\\];' $P \
   && grep -q 'if (!native) return kMSBLicenseHint;' $P && grep -q 'return MSBDChoiceCCStyleNativeFooter(' $P && grep -q 'MSBDOSVersionString(), MSBDStockBarStored());' $P"
check "  ... drawn: a greyed row is not picked, its GET button opens the page, the reason where the checkmark would be; an untested build's title" \
  "grep -q 'return (v && \\[\\[self msb_rowFor:v\\]\\[@\"state\"\\] intValue\\] == 0) ? nil : ip;' $P && grep -q 'if (state == 0 && url) {' $P && grep -q '} else if (state == 0 && reason) {' $P \
   && grep -q 'if (\\[row\\[@\"title\"\\] isKindOfClass:\\[NSString class\\]\\]) cell.textLabel.text = row\\[@\"title\"\\];' $P"
check "  ... the Banner Style with ours, iPadOS's and Destra's (installed as the page shows it), Destra's footer under Third-Party" \
  "awk '/^- \\(NSDictionary \\*\\)msb_rowFor:/,/^}/' $P | grep -q 'if (\\[key isEqualToString:@kMSBDBannerStyleKey\\]) return MSBDChoiceBannerRow(value, MSBDDestraInstalled(YES));' \
   && awk '/^- \\(NSString \\*\\)msb_footer:/,/^}/' $P | grep -q 'if (\\[key isEqualToString:@kMSBDBannerStyleKey\\] && !native) {'"
check "the Window Engine row still opens the engine page; the Control Center Style and Banner Style rows the shared one" \
  "plutil -convert json -o - ../statusbar/macstatusbarprefs/Resources/Windows.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; sys.exit(0 if [x.get(\"detail\") for x in it if x.get(\"key\")==\"windowEngine\"]==[\"MSBEngineListController\"] else 1)' \
   && plutil -convert json -o - ../statusbar/macstatusbarprefs/Resources/Root.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; sys.exit(0 if [x.get(\"detail\") for x in it if x.get(\"key\")==\"controlCenterStyle\"]==[\"MSBChoiceListController\"] else 1)' \
   && plutil -convert json -o - ../statusbar/macstatusbarprefs/Resources/Root.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; sys.exit(0 if [x.get(\"detail\") for x in it if x.get(\"key\")==\"bannerStyle\"]==[\"MSBChoiceListController\"] else 1)'"
[ $fails = 0 ] && echo "test-choicepage: wiring checks pass" || { echo "test-choicepage: wiring checks FAILED"; exit 1; }
