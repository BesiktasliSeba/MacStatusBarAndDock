#!/bin/bash
# Mac test of RAM & CPU put in Control Center by itself, once per iPad, where there is room (1.7.7 item 8; common/CCAutoAdd.h, test-ccautoadd.m):
# the once-only marker, what the user's lists say, where the control goes, the room in Apple's Control Center and in BigSurCenter's, 18's layout;
# then the wiring in SpringBoard (statusbar/StatusBar.x, macsettings/CCGrabber.x).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tca" test-ccautoadd.m
"$W/tca"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
check "the marker is kept in our main preferences (MSB_DOMAIN), which the package's removal leaves" \
  "awk '/^static void DMCCAutoAddMark\\(/{f=1} f&&/CFPreferencesSetValue\\(.*MSB_DOMAIN/{print \"ok\"; exit} f&&/^}/{exit}' $S | grep -q ok && ! grep -n 'com.besiktasliseba.macstatusbar.plist' ../layout/DEBIAN/postrm ../layout/DEBIAN/prerm"
check "added through Control Center's settings provider, as Settings' + (the list with ours at the end)" \
  "awk '/^static void DMCCAutoAddDecide\\(/{f=1} f&&/setAndSaveOrderedUserEnabledModuleIdentifiers:\"\\), MSBDCCAutoAddList\\(enabled\\)\\)/{print \"ok\"; exit} f&&/^}/{exit}' $S | grep -q ok"
check "  ... only after the marker says it is due, the lists say absent, RAM & CPU loads and there is room (in that order)" \
  "awk '/^static void DMCCAutoAddDecide\\(/{f=1} f&&/MSBDCCAutoAddDue\\(/{a=NR} f&&/MSBDCCAutoAddListState\\(/{b=NR} f&&/DMCCRAMCPULoads\\(\\)/{c=NR} f&&/if \\(!gCCAutoAddRoom\\)/{d=NR} f&&/setAndSaveOrderedUserEnabledModuleIdentifiers/{e=NR} f&&/^}/{exit} END{exit !(a && a<b && b<c && c<d && d<e)}' $S"
check "  ... and marked added only once the provider's list has it" \
  "awk '/^static void DMCCAutoAddConfirm\\(/{f=1} f&&/containsObject:kMSBDCCModuleID/{a=1} f&&/DMCCAutoAddMark\\(kMSBDCCAutoAddDone, @\"added\"\\)/{b=1} f&&/^}/{exit} END{exit !(a && b)}' $S"
check "no room is kept for the version that found it (looked at again after an update)" \
  "grep -q 'if (!gCCAutoAddRoom) { DMCCAutoAddMark(kMSBDCCAutoAddNoRoom, version);' $S"
check "measured while Control Center shows, looked at when it closes, in either status bar style" \
  "grep -q 'DMCCAutoAddInit(); DMStockBarStart(); return; }' $S && grep -q '^    if (!DMCtorSkip(\"ccautoadd\")) DMCCAutoAddInit();' $S && awk '/^%group CCAutoAddWatch/{f=1} f&&/^- \\(void\\)_willPresent/{w=1} w&&/DMCCAutoAddMeasureNow\\(@\"Control Center open\"\\)/{m=1} f&&/^- \\(void\\)_didDismiss/{d=1} d&&/DMCCAutoAddDecide\\(@\"Control Center closed\"\\)/{c=1} f&&/^%end/{exit} END{exit !(m && c)}' $S"
check "  ... a close decides only on the measure of its own presentation (taken back at every present, used once)" \
  "awk '/^%group CCAutoAddWatch/{f=1} f&&/gCCAutoAddMeasured = NO;/{print \"ok\"; exit} f&&/^%end/{exit}' $S | grep -q ok && grep -q 'gCCAutoAddMeasured = NO;   // (one presentation' $S"
check "18 adds nothing in this version: it only marks a tile that is there" \
  "! awk '/^static void DMCCAutoAdd18Look\\(/{f=1} f&&/setAndSave|handleIconElementRequest/{print; exit} f&&/^}/{exit}' $S | grep -q . && grep -q 'DMCCAutoAddMark(kMSBDCCAutoAddDone, @\"there\")' $S"
check "the debug-only no-room flag never reaches a release build" \
  "awk '/msb-ccadd-noroom/{print prev} {prev=\$0}' $S | grep -q '#if DEBUG'"
check "MacCCGrabber answers under the name the status bar part asks (RAM & CPU in Control Center's repository)" \
  "grep -q '^#define kMSBDCCRAMCPURegisteredFn \"MSBDCCRAMCPURegistered\"' ../common/CCAutoAdd.h && grep -q '__attribute__((visibility(\"default\"))) BOOL MSBDCCRAMCPURegistered(void) { return gMSBDCCHooked == 3 && \\[gMSBDCCIdentifiers containsObject:kMSBDCCModuleID\\]; }' ../macsettings/CCGrabber.x"
check "the crash guard turns the status bar part off for a crash in this code (as for the Memory Magic offer)" \
  "grep -q '^sec MacStatusBarCore RAM\\\\s&\\\\sCPU\\\\sin\\\\sControl\\\\sCenter\\\\sby\\\\sitself part' crashmap-rules.txt"
check "BigSurCenter: no add when the user's list changed since SpringBoard's start (its grid is the start's list)" \
  "awk '/^static void DMCCAutoAddDecide\\(/{f=1} f&&/gCCAutoAddBSC && !\\[enabled isEqualToArray:gCCAutoAddStartList\\]/{b=1} b&&/setAndSaveOrderedUserEnabledModuleIdentifiers/{print \"ok\"; exit} f&&/^}/{exit}' $S | grep -q ok && grep -q 'gCCAutoAddStartList = \\[list isKindOfClass' $S"
H=../macsettings/sshtoggled/main.m
check "the removal forgets an \"added\" / \"there\" marker where it takes RAM & CPU out (1.7.7: lost across a reinstall): before SpringBoard is told" \
  "awk '/^static void Uninstall\\(void\\) \\{/{f=1} f&&/ForgetCCAutoAddWhereShown\\(\\);/{a=NR} f&&/notify_post\\(kMSBDCCRemovingNote\\);/{b=NR} f&&/TakeOurControlsOut\\(\\);/{c=NR} f&&/^}/{exit} END{exit !(a && a<b && b<c)}' $H"
check "  ... from the 15-17 files and 18's layout, cleared in StatusBar.x's own domain only when MSBDCCAutoAddForgetOnRemoval says so" \
  "awk '/^static void ForgetCCAutoAddWhereShown\\(void\\) \\{/{f=1} f&&/kMSBDCCAppleListFile, kMSBDCCCCSupportListFile, kMSBDCCAutoAdd18LayoutFile/{a=NR} f&&/if \\(!MSBDCCAutoAddForgetOnRemoval\\(marker, lists, layout\\)\\)/{b=NR} f&&/WriteMobilePrefsKey\\(\\(__bridge NSString \\*\\)domain, kMSBDCCAutoAddDone, nil, NO\\);/{c=NR} f&&/^}/{exit} END{exit !(a && a<b && b<c)}' $H && grep -q 'CFStringRef domain = CFSTR(\"com.besiktasliseba.macstatusbar\");' $H && grep -q '^#define MSB_DOMAIN CFSTR(\"com.besiktasliseba.macstatusbar\")' $S"
check "1.8.0: with our own Control Center showing, the room is the panel's by its own rules (CCPanel.h DMCCPanelRoomForModule, CCLayout.h MSBDCCRoomForOne), measured first; Apple's grid under it is empty and never measured then" \
  "awk '/^static void DMCCAutoAddMeasureNow/{f=1} f&&/if \(DMCCPanelOn\(\)\) \{/{a=NR} f&&/told = DMCCPanelRoomForModule\(kMSBDCCModuleID, 2, 1, &room, &why\);/{b=NR} f&&/gCCAutoAddBSC = NO; gCCAutoAddWhy = why; gCCAutoAddKind = @\"our Control Center\";/{c=NR} f&&/BOOL told = DMCCMeasureBSC\(&bg, &why\)/{d=NR} f&&/^}/{exit} END{exit !(a && a<b && b<c && c<d)}' $S && awk '/^static BOOL DMCCMeasureApple/{f=1} f&&/memset\(g, 0, sizeof \*g\);/{a=NR} f&&/if \(DMCCPanelOn\(\)\) DMCC_UNTOLD/{b=NR} f&&/Class ppc = objc_getClass/{c=NR} f&&/^}/{exit} END{exit !(a && a<b && b<c)}' $S"
[ $fails = 0 ] && echo "test-ccautoadd: wiring checks pass" || { echo "test-ccautoadd: wiring checks FAILED"; exit 1; }
