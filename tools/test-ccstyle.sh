#!/bin/bash
# Mac test of Control Center Style (common/CCStyle.h, test-ccstyle.c; 1.8.0 item 3, KT 2-3 Nov): the rule itself, then the readers built on the
# Mac with our own Control Center's check (common/CCStyleNow.h: CCMacCheck.h is the panel's, 1.8.0 P2, built in), then, in the code as built,
# that every side reads the one rule -- Settings (the row, its page, the rows that go with a style), SpringBoard (the style in force, Settings
# told, the start's switch) and the root helper (whether BigSurCenter loads) -- and that nothing writes the default.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreFoundation -o "$W/t" test-ccstyle.c
"$W/t"
# the readers: our Control Center's verdict, its check built in (CCMacCheck.h)
cat > "$W/now.m" <<'EOF'
#import <Foundation/Foundation.h>
#include "CCStyleNow.h"
int main(void) { @autoreleasepool { printf("%d %d\n", MSBD_CC_MAC_BUILT, MSBDCCMacVerdictNow(NULL)); } return 0; }
EOF
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -I "$PWD/../common" -o "$W/now" "$W/now.m"
# (no record of a check on this Mac: the panel's verdict is -1 under a macOS 15-17, 0 outside it)
mac=$(sw_vers -productVersion | cut -d. -f1); [ "$mac" -ge 15 ] && [ "$mac" -le 17 ] && want="1 -1" || want="1 0"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the readers: our Control Center's check is built in (CCMacCheck.h, imported as it is, no stand-in): its verdict is the one read (the Mac row's states from it: test-ccstyle.c, test-choicepage)" \
  "[ \"\$(\"$W/now\")\" = '$want' ] && grep -q '^#import \"CCMacCheck.h\" ' ../common/CCStyleNow.h && ! grep -q '__has_include' ../common/CCStyleNow.h \
   && grep -qF 'static inline int MSBDCCMacVerdictNow(NSString **reason) { return MSBDCCMacVerdict(reason); }' ../common/CCStyleNow.h"
P=../statusbar/macstatusbarprefs/MSBRootListController.m; SB=../statusbar/StatusBar.x; C=../statusbar/CCStyleSB.h; H=../macsettings/sshtoggled/main.m
N=../common/CCStyleNow.h; R=../statusbar/macstatusbarprefs/Resources/Root.plist
check "the readers: the stored style (for a user: the helper reads mobile's), BigSurCenter installed and switched off by the user (ExclusiveChoice.h), the verdict, Status Bar Style -- one rule" \
  "awk '/^static inline int MSBDCCStyleNowFor/,/^}/' $N > \$W/nowfor && grep -q 'BOOL userOff = bsc && MSBDExUserOffNow(@\"BigSurCenter\");' \$W/nowfor \
   && grep -q 'return MSBDCCStyleChosen(MSBDCCStyleStoredFor(user), bsc, userOff, MSBDCCMacRuns(' \$W/nowfor && grep -q ', v, MSBDCCStockBarStoredFor(user)));' \$W/nowfor \
   && grep -q 'CFPreferencesCopyValue(CFSTR(\"stockStatusBar\"), kMSBDCCStyleDomain, user, kCFPreferencesAnyHost);' $N \
   && grep -q 'return MSBDExInstalled(@\"BigSurCenter\");' $N && grep -q 'if (display && MSBDCCStylePretendNoBSC()) return NO;' $N"
check "Settings: the row shows the rule's style (the debug pretend only on the pages), a tap stores only a style that is not in force already" \
  "grep -q 'static int MSBCCStyleShown(void) { return MSBDCCStyleNow(YES); }' $P && grep -q 'isEqual:@kMSBDCCStyleKey\\]) return @(MSBDCCStyleValue(MSBCCStyleShown()));' $P \
   && grep -q 'if (!style || style == before) return;   // (the style in force tapped again: nothing stored' $P && grep -q 'BOOL want = MSBDCCStyleLoadsBigSurCenter(style);' $P"
check "  ... the exclusivity from the real files, never in safe mode or on an untested iPadOS; the respring only when what loads changes" \
  "awk '/^- \\(void\\)msb_ccStyleChanged:/,/^}/' $P > \$W/chg && grep -q 'if (!MSBDGateWanted()) return;' \$W/chg && grep -q 'if (!MSBDCCBigSurCenterInstalled(NO)) return;' \$W/chg \
   && [ \$(grep -c 'if (want != loaded) {' \$W/chg) = 2 ] && grep -q 'MSBChoicyApplyChoice(@kMSBDCCStyleKey, @(MSBDCCStyleValue(style)))' \$W/chg && grep -q 'notify_post(\"com.besiktasliseba.msb.engines.apply\")' \$W/chg"
check "  ... the group: the size slider with BigSurCenter (our status bar) and Mac (KT 3 Nov; greyed on 18, its footer says so; never set it shows each one's own size), Hide Grabber with iPadOS, the footer \"Only the chosen Control Center is loaded.\"" \
  "grep -q 'BOOL sizeSlider = MSBDCCSizeRowShown(ccStyle, MSBStockBarStored()), grabber = ccStyle == kMSBDCCStyleStock;' $P \
   && grep -q 'BOOL sizeGreyed = sizeSlider && MSBDCCSizeRowGreyed(ccStyle, \[NSProcessInfo processInfo\].operatingSystemVersion.majorVersion);' $P && grep -q 'isEqual:kMSBDCCScaleKey\] && sizeGreyed) \[spec setProperty:@NO forKey:@\"enabled\"\];' $P \
   && grep -qF 'if (sizeSlider && style == kMSBDCCStyleBigSurCenter) [s appendString:@\" The slider sets how large BigSurCenter appears when you open it from the status bar.\"];' $P \
   && grep -qF 'else if (sizeSlider) [s appendString:@\" The slider sets how large Control Center appears.\"];' $P && grep -qF 'if ([[specifier propertyForKey:@\"key\"] isEqual:kMSBDCCScaleKey]) return @(MSBCCSizeShown());' $P \
   && grep -q '(\\[spec.identifier isEqualToString:kMSBDCCGrabberRowID\\] && !grabber)' $P && grep -q 'stringWithString:@\"Only the chosen Control Center is loaded.\"' $P"
check "Root.plist: Control Center Style first in the Control Center group (mac / stock / bigsurcenter, the shared choice page, no default), Hide Grabber by its id" \
  "plutil -convert json -o - $R | python3 -c '
import json,sys
it=json.load(sys.stdin)[\"items\"]
g=[i for i,x in enumerate(it) if x.get(\"id\")==\"CC_GROUP\"][0]
r=it[g+1]
ok=r.get(\"id\")==\"CC_STYLE\" and r.get(\"key\")==\"controlCenterStyle\" and r.get(\"validValues\")==[\"mac\",\"stock\",\"bigsurcenter\"] and r.get(\"validTitles\")==[\"Mac\",\"iPadOS\",\"BigSurCenter\"]
ok=ok and r.get(\"detail\")==\"MSBChoiceListController\" and \"default\" not in r and r.get(\"cell\")==\"PSLinkListCell\" and it[g].get(\"footerText\")==\"Only the chosen Control Center is loaded.\"
ok=ok and [x.get(\"id\") for x in it if x.get(\"label\")==\"Hide Grabber\"]==[\"CC_GRABBER\"]
sys.exit(0 if ok else 1)'"
check "SpringBoard: the style from the real files (no pretend), BigSurCenter in force while loaded, Settings told; with either status bar style" \
  "grep -q 'int chosen = MSBDCCStyleNowFor(kCFPreferencesCurrentUser, NO, &installed, &verdict);' $C && grep -q 'int inForce = MSBDCCStyleInForce(chosen, loaded);' $C \
   && grep -q 'notify_set_state(token, state)' $C && grep -q 'if (!DMCtorSkip(\"ccstyle\")) DMCCStyleInit();   // (Control Center Style' $SB \
   && grep -q 'if (!DMCtorSkip(\"ccstyle\")) DMCCStyleInit(); if (!DMCtorSkip(\"ccautoadd\")) DMCCAutoAddInit(); DMStockBarStart(); return; }' $SB"
check "  ... at the start: the helper's word awaited when BigSurCenter loaded the wrong way, the question only for what the helper changed" \
  "grep -q 'gEngineAskCC = DMCCStyleSwitchDue();' $SB && grep -q 'if ((engineAsk || gEngineAskCC || gEngineAskBanners) && DMEngineHelperInstalled()) {' $SB \
   && grep -q 'gEngineAskWhat = ((what & 1) && engineAsk ? 1 : 0) | ((what & 2) && gEngineAskCC ? 2 : 0) | ((what & 4) && gEngineAskBanners ? 4 : 0);' $SB && grep -q 'if (gEngineAskWhat & 2) {' $SB"
check "the root helper: the style read for mobile by the same rule; BigSurCenter kept or kept out with Choicy and with iCleaner Pro's renames" \
  "awk '/^static int ChosenCCStyle/,/^}/' $H > \$W/hc && grep -q 'return MSBDCCStyleChosen(MSBDCCStyleStoredFor(CFSTR(\"mobile\")), installed, installed && MSBDExUserOffNow(@\"BigSurCenter\"),' \$W/hc \
   && grep -q 'verdict, MSBDCCStockBarStoredFor(CFSTR(\"mobile\"))));' \$W/hc \
   && grep -q 'else \\[MSBDCCStyleLoadsBigSurCenter(style) ? keep : deny addObject:@\"BigSurCenter\"\\];' $H \
   && grep -q 'if (bsc && MSBDCCStyleLoadsBigSurCenter(style)) EnableOurs(@\"BigSurCenter\", record, @\"BigSurCenter is the Control Center Style\");' $H"
check "nothing writes the default: no controlCenterStyle written by SpringBoard, the helper or our Settings code (only the row's own store, at a tap)" \
  "! grep -n 'CFPreferencesSet[A-Za-z]*Value(CFSTR(\"controlCenterStyle\")\\|CFPreferencesSet[A-Za-z]*Value(CFSTR(kMSBDCCStyleKey)' $SB $C $H $P ../common/*.h"
[ $fails = 0 ] && echo "test-ccstyle: wiring checks pass" || { echo "test-ccstyle: wiring checks FAILED"; exit 1; }
