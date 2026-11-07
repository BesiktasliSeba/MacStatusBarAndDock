#!/bin/bash
# Mac test of the Settings search following our pages' hide rules (1.7.9, KT): the rule (common/OwnPageRows.h, test-ownpagerows.m) over the real
# plists of the Status Bar, Windows & Multitasking, Desktop and Dock pages in each state the pages leave rows out in; and, in the code as built,
# that the pages and the search ask the same readers and lists (common/OwnPageState.h): the search does not copy the pages' conditions.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-ownpagerows.m
"$W/t" ../statusbar/macstatusbarprefs/Resources ../dock/dockmagnificationprefs/Resources
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
P=../statusbar/macstatusbarprefs/MSBRootListController.m; DP=../dock/dockmagnificationprefs/DMRootListController.m; R=../common/OwnPageRows.h; ST=../common/OwnPageState.h
S=../common/TweakSpotlight.h; L=../common/LineSwitch.h; I=../common/TweakIndex.h; T=../macsettings/TweakSearch.x
check "the search (and Spotlight's Tweak Settings) list our pages' rows as the pages show them now, with the state the pages read" \
  "grep -q 'return rows.count ? MSBDOwnRowsShown(rows, MSBDOwnPagesNow()) : rows;' $S && grep -q '#import \"OwnPageState.h\"' $S"
check "  ... the state from the pages' own readers: the stored style and Finder, the line switches, the Control Center Style, the 17 / 18 checks, the engine the row shows" \
  "awk '/^static inline MSBDOwnPages MSBDOwnPagesNow\\(void\\) \\{/,/^}/' $ST > \$W/now && grep -q 's.stockBar = MSBDStockBarStored();' \$W/now && grep -q 's.barLine = MSBDLineEnabled(@\"MacStatusBar\");' \$W/now \
   && grep -q 's.dockLine = MSBDLineEnabled(@\"MacDock\");' \$W/now && grep -q 's.finder = MSBDFinderStored();' \$W/now && grep -q 's.ccStyle = MSBDCCStyleNow(YES);' \$W/now \
   && grep -q 's.focus18Failed = MSBDFocusLock18Failed();' \$W/now && grep -q 's.desktopFailed = MSBDDesktopRowsFailed();' \$W/now && grep -q 'NSString \\*engine = MSBDEngineShownWithoutRow();' \$W/now \
   && grep -q \"s.engineWorks = !\\[engine isEqualToString:@\\\"none\\\"\\] && MSBDEngineState(engine) == 2;\" \$W/now && grep -q 's.batteryUseOff = gMSBDOwnBatteryUseOff ? gMSBDOwnBatteryUseOff() : NO;' \$W/now"
check "the Status Bar / Windows / Desktop pages read the same: the stored style and Finder, the engine's state and the engine shown" \
  "grep -q 'static BOOL MSBStockBarStored(void) { return MSBDStockBarStored(); }' $P && grep -q 'static BOOL MSBFinderStored(void) { return MSBDFinderStored(); }' $P \
   && grep -q 'static int MSBEngineState(NSString \\*engine) { return MSBDEngineState(engine); }' $P && grep -q 'static NSString \\*MSBEngineShown(id value, NSArray \\*offered) { return MSBDEngineShown(value, offered); }' $P \
   && grep -q 'static NSString \\*MSBEngineShownWithoutRow(void) { return MSBDEngineShownWithoutRow(); }' $P && ! grep -q 'MSBDEngineFileTested(lib, path)' $P"
check "  ... and leave rows out by the same conditions and lists: Control Center's size and Hide Grabber (the style), the desktop's rows and the Mac Switcher (17 / 18), the Wi-Fi Menu (18)" \
  "grep -q 'static int MSBCCStyleShown(void) { return MSBDCCStyleNow(YES); }' $P && grep -q 'int ccStyle = MSBCCStyleShown();' $P \
   && grep -q 'BOOL sizeSlider = MSBDCCSizeRowShown(ccStyle, MSBStockBarStored()), grabber = ccStyle == kMSBDCCStyleStock;' $P \
   && grep -q 'isEqual:kMSBDCCScaleKey\\] && !sizeSlider) || (\\[spec.identifier isEqualToString:kMSBDCCGrabberRowID\\] && !grabber)) \\[kept removeObject:spec\\];' $P \
   && grep -q 'BOOL noFocus18 = MSBDFocusLock18Failed();' $P && grep -q 'BOOL desktopFailed = MSBDDesktopRowsFailed();' $P \
   && grep -q 'if ((desktopFailed && MSBDDesktopCheckRow(\\[spec propertyForKey:@\"key\"\\], spec.identifier))' $P && grep -q '(noFocus18 && \\[\\[spec propertyForKey:@\"key\"\\] isEqual:kMSBDMacSwitcherKey\\])' $P \
   && grep -q 'inGroup = \\[spec.identifier isEqualToString:kMSBDMacSwitcherGroupID\\];' $P && grep -q '^		if (MSBDFocusLock18Failed()) {' $P && grep -q 'hiding = \\[sp.identifier isEqualToString:kMSBDWiFiGroupID\\];' $P"
check "  ... the engine's groups (the Windows group, the resize handles, Window Size and Double-Tap a Title Bar to kept with Stage Manager, Resize Handles, Resize Apps), Report a Problem, Keep Tailspin Off" \
  "[ \$(grep -c 'hiding = \\[sp.identifier isEqualToString:kMSBDWindowsGroupID\\];' $P) = 2 ] && grep -q 'BOOL itsToo = MSBDStageManagerKeepsRow(\\[sp propertyForKey:@\"key\"\\]);' $P \
   && grep -q 'if (!\\[\\[sp propertyForKey:@\"key\"\\] isEqual:kMSBDResizeHandlesKey\\]) \\[kept addObject:sp\\];' $P && grep -q 'hiding = \\[sp.identifier isEqualToString:kMSBDResizeGroupID\\];' $P \
   && grep -q 'if (\\[spec.identifier isEqualToString:kMSBDReportRowID\\]) report = spec;' $P && grep -q 'tailspin = MSBDBarOffKeepsGroup(sp.identifier);' $P"
check "the Dock page: no Finder group with Finder off, Finder read the same way; the line switch's rows go with it (LineSwitch.h, the index's line)" \
  "grep -q 'if (!MSBDFinderStored()) for (PSSpecifier \\*sp in \\[specs copy\\]) if (\\[sp.identifier isEqual:kMSBDDockFinderRowID\\] || \\[sp.identifier isEqual:kMSBDDockFinderGroupID\\]) \\[specs removeObject:sp\\];' $DP \
   && grep -q 'isEqualToString:@\"MSBD_LINE\"\\]) { at = i; break; }' $L && grep -q '#define kMTILineRowID @\"MSBD_LINE\"' $I && grep -q '#define kMSBDLineRowID      @\"MSBD_LINE\"' $R \
   && plutil -convert json -o - ../statusbar/macstatusbarprefs/Resources/Root.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; sys.exit(0 if [x.get(\"lineName\") for x in it if x.get(\"id\")==\"MSBD_LINE\"]==[\"MacStatusBar\"] else 1)' \
   && plutil -convert json -o - ../dock/dockmagnificationprefs/Resources/Root.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; sys.exit(0 if [x.get(\"lineName\") for x in it if x.get(\"id\")==\"MSBD_LINE\"]==[\"MacDock\"] else 1)'"
check "the index records each row's group, the group's stockHides, its key and whether it is below its page's line switch" \
  "awk '/^- \\(void\\)walkItems:/,/^}/' $I > \$W/walk && grep -q 'groupID = MTIStr(it\\[@\"id\"\\]); groupStock = ' \$W/walk && grep -q 'e.groupID = groupID; e.stockHides = groupStock; e.key = MTIStr(it\\[@\"key\"\\]); e.belowLine = self.belowLine;' \$W/walk \
   && grep -q 'if (depth == 2 && \\[MTIStr(it\\[@\"id\"\\]) isEqualToString:kMTILineRowID\\]) self.lineNext = YES;' \$W/walk && awk '/^- \\(void\\)addPage:/,/^}/' $I | grep -q 'self.belowLine = NO; self.lineNext = NO;'"
check "Sleep Guard only where our Battery Use group is on Battery Health, as our own battery parts decided once Apple's pages loaded" \
  "grep -q 'gMSBDOwnBatteryUseOff = MTSBatteryUseOff;' $T && grep -q 'static BOOL MTSBatteryUseOff(void) { return MSBHPageVerdict() == 1 || MSBUGroupVerdict() == 1; }' $T \
   && grep -q '{ gMSBHVerdict = 1; MSBHLog(@\"no row builder or isiPhone: Apple.s page untouched\"); return; }' ../macsettings/BatteryHealth.x && grep -q '^    gMSBHVerdict = 2;' ../macsettings/BatteryHealth.x \
   && grep -q '{ gMSBUVerdict = 1; return; }' ../macsettings/BatteryUse.x && grep -q '^    gMSBUVerdict = 2;' ../macsettings/BatteryUse.x"
check "Double-Tap a Title Bar to stays with Stage Manager as the engine, on the page and in the search (GitHub #11): the rule's key is the setting's and the page row's, and Stage Manager's windows have our title bar's double tap" \
  "grep -q '#define kMSBDTitleDoubleTapRowKey @\"titleBarDoubleTap\"' $R && grep -q '#define kMSBDTitleDoubleTapKey \"titleBarDoubleTap\"' ../statusbar/TitleBarRule.h \
   && awk '/^static inline BOOL MSBDStageManagerKeepsRow\\(NSString \\*key\\) \\{/,/^}/' $R | grep -q '\\[key isEqualToString:kMSBDTitleDoubleTapRowKey\\]' \
   && grep -q '(s.stageManagerEngine && !MSBDStageManagerKeepsRow(key))' $R && grep -q 'BOOL itsToo = MSBDStageManagerKeepsRow(\\[sp propertyForKey:@\"key\"\\]);' $P \
   && grep -q 'case kDMTitleSM: {' ../statusbar/TitleBarTap.h && grep -q 'act = ^(NSString \\*why) { DMTitleTapSMWindow(key, why); };' ../statusbar/TitleBarTap.h \
   && plutil -convert json -o - ../statusbar/macstatusbarprefs/Resources/Windows.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; g=None; r=[]
for x in it:
    g = x.get(\"id\") if x.get(\"cell\")==\"PSGroupCell\" else g
    r += [g] if x.get(\"key\")==\"titleBarDoubleTap\" and x.get(\"id\")==\"TITLE_BAR_DOUBLE_TAP\" else []
sys.exit(0 if r==[\"WINDOWS_GROUP\"] else 1)'"
check "with no working engine Double-Tap a Title Bar to stays, as Finder's and TextEdit's windows use it: on the page, in its group with a line saying so, and in the search; the rest of the Windows group goes (1.8.3.1)" \
  "grep -q 'static inline BOOL MSBDNoEngineKeepsRow(NSString \\*key) { return \\[key isEqualToString:kMSBDTitleDoubleTapRowKey\\]; }' $R \
   && grep -q '((!s.engineWorks && !MSBDNoEngineKeepsRow(key)) || (s.stageManagerEngine && !MSBDStageManagerKeepsRow(key)))' $R \
   && grep -q 'BOOL windowsGroup = sp.cellType == PSGroupCell && \\[sp.identifier isEqualToString:kMSBDWindowsGroupID\\];' $P \
   && grep -q 'if (!hiding || windowsGroup || MSBDNoEngineKeepsRow(\\[sp propertyForKey:@\"key\"\\])) \\[kept addObject:sp\\];' $P \
   && [ \$(grep -c 'Finder and TextEdit windows still use this setting.' $P) = 1 ] \
   && grep -q 'if (windowsGroup) \\[sp setProperty:@\"Finder and TextEdit windows still use this setting.\" forKey:@\"footerText\"\\];' $P \
   && grep -q 'DMTitleTapAttach(_titleBar, kDMTitleNative);' ../statusbar/NativeWindow.h && grep -q 'CGRect fill = DMLayoutFrameInArea(@\"fill\", DMNativeDesktop(), \\[UIScreen mainScreen\\].bounds.size);' ../statusbar/TitleBarTap.h"
check "with no working engine New Windows Open at Fill goes too, on the page (its group and row) and in the search: every window it sizes is an engine's (audit 1.8.3 M4)" \
  "grep -q '#define kMSBDNewWindowsFillGroupID @\"NEW_WINDOWS_FILL_GROUP\"' $R && grep -q 'if (\\[group isEqualToString:kMSBDNewWindowsFillGroupID\\] && !s.engineWorks) return YES;' $R \
   && grep -q 'if (sp.cellType == PSGroupCell && \\[sp.identifier isEqualToString:kMSBDNewWindowsFillGroupID\\]) { hiding = YES; continue; }' $P \
   && plutil -convert json -o - ../statusbar/macstatusbarprefs/Resources/Windows.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; g=None; r=[]
for x in it:
    g = x.get(\"id\") if x.get(\"cell\")==\"PSGroupCell\" else g
    r += [g] if x.get(\"key\")==\"newWindowsFill\" else []
sys.exit(0 if r==[\"NEW_WINDOWS_FILL_GROUP\"] else 1)'"
[ $fails = 0 ] && echo "test-ownpagerows: wiring checks pass" || { echo "test-ownpagerows: wiring checks FAILED"; exit 1; }
