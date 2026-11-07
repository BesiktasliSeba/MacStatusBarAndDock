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
KB=../macsettings/KeyboardSettings.x
check "KeyPilot (1.8.3): its row under Custom Shortcuts, below the Window Tiling Shortcuts at the Keyboard page's end -- its name and developer, GET or OPEN as ChoicePage.h says, installed when its app is registered (its tweak file alone: GET, review 1.8.3 P2-8), its app opened by bundle ID" \
  "grep -q 'NSDictionary \*row = MSBDKeyPilotRow(installed);' $KB && grep -q 'BOOL installed = MSKeyPilotInstalled();' $KB && grep -q 'sub.text = row\[@\"subtitle\"\];' $KB \
   && grep -q 'SEL open = NSSelectorFromString(@\"openApplicationWithBundleID:\");' $KB && ! grep -q 'kMSBDKeyPilotLib stringByAppendingString' $KB \
   && awk '/^static BOOL MSKeyPilotInstalled\(void\) \{/{f=1} f{print} f && /^}/{exit}' $KB | grep -q '    return MSKeyPilotAppRegistered();' \
   && grep -q 'PSSpecifier \*cg = MSKeyGroup(@\"Custom Shortcuts\",' $KB && awk '/@\"MAC_WINDOW_KEYS_GROUP\"/{a=NR} /@\"MAC_CUSTOM_SHORTCUTS_GROUP\"/{b=NR} END{exit !(a && b > a)}' $KB"
check "  ... OPEN off the main queue with its answer taken; when Settings cannot open the app, SpringBoard asked to (review 1.8.3 F4)" \
  "grep -q 'BOOL ok = !skipOwn && \[ws respondsToSelector:open\] && ((BOOL (\*)(id, SEL, id))objc_msgSend)(ws, open, app);' $KB && grep -q 'if (!ok) notify_post(kMSBDKeyPilotOpenNote);' $KB \
   && grep -q 'dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{' $KB && grep -q 'define kMSBDKeyPilotOpenNote  \"com.besiktasliseba.macstatusbar.keypilot.open\"' ../common/ChoicePage.h"
check "  ... GET or OPEN read again each time Settings comes to the front (an install meanwhile), on our page and Apple's 18 page alike (review 1.8.3 F9)" \
  "grep -q 'w.token = \[\[NSNotificationCenter defaultCenter\] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:\[NSOperationQueue mainQueue\] usingBlock:' $KB \
   && grep -q 'if (c && \[objc_getAssociatedObject(c, kMSKPShownKey) boolValue\] != MSKeyPilotInstalled())' $KB && grep -q '(void)dealloc { if (_token) \[\[NSNotificationCenter defaultCenter\] removeObserver:_token\]; }' $KB"
check "  ... SpringBoard opens it when Settings cannot (kMSBDKeyPilotOpenNote, DMOpenApp), watched from the start -- only an app it has (review 1.8.3 P2-8)" \
  "awk '/^static void DMKeyPilotOpenWatch\(void\) \{/{f=1} f{print} f && /^}/{exit}' ../statusbar/WindowAPI.h | grep -q 'NSString \*app = kMSBDKeyPilotApp;' \
   && awk '/^static void DMKeyPilotOpenWatch\(void\) \{/{f=1} f{print} f && /^}/{exit}' ../statusbar/WindowAPI.h | awk '/if \(!DMAppForBundle\(app\)\)/{a=NR} /DMOpenApp\(app\);/{b=NR} END{exit !(a && b && a < b)}' \
   && awk '/^static void DMKeyPilotOpenWatch\(void\) \{/{f=1} f{print} f && /^}/{exit}' ../statusbar/WindowAPI.h | grep -q 'DMOpenApp(app);' \
   && grep -q 'notify_register_dispatch(kMSBDKeyPilotOpenNote, &token, dispatch_get_main_queue(), ^(int t) {' ../statusbar/WindowAPI.h \
   && grep -q '    DMKeyPilotOpenWatch();   // (Settings > Keyboard' ../statusbar/StatusBar.x"
check "  ... an enabled row its button can be tapped in (a static text row is drawn grey and takes no touch: iPad 2, 16.7.7)" \
  "grep -q 'PSSpecifier \*kp = \[PSSpecifier preferenceSpecifierNamed:@\"KeyPilot\" target:target set:nil get:nil detail:nil cell:kCellTitleValue edit:nil\];' $KB \
   && grep -q '\[kp setProperty:@YES forKey:@\"enabled\"\];' $KB && grep -q 'cell.userInteractionEnabled = YES;' $KB"
[ $fails = 0 ] && echo "test-choicepage: wiring checks pass" || { echo "test-choicepage: wiring checks FAILED"; exit 1; }
