#!/bin/bash
# Mac test of our own Control Center's Mac tiles (1.8.0 P3): their plain-C logic (common/CCTileLogic.h, test-cctiles.c: the sliders, Connectivity's
# rows -- Airplane Mode, Wi-Fi, Bluetooth --, the wide tiles' and Now Playing's parts, a tile at Control Center Size), then the sites in the code
# as built (statusbar/CCTiles.h and its glue in
# CCPanel.h, WiFiMenu.h and StatusBar.x): the tiles in place of the placeholders, the checked API table, a page's rows closing Control Center
# first (DMCloseThen asks the rows' host), the Wi-Fi page scanning only while it shows, nothing running while Control Center is closed, the
# artwork off the main thread, the Stage Manager spot, the reading order, the crash guard's rules, the tests' fakes never switching a radio.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/t" test-cctiles.c
"$W/t"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; P=../statusbar/CCPanel.h; T=../statusbar/CCTiles.h; F=../statusbar/WiFiMenu.h
check "StatusBar.x includes the tiles right after the panel; the panel makes them at its build (a role none took keeps its placeholder)" \
  "awk '/^#include \"CCPanel.h\" /{a=NR} /^#include \"CCTiles.h\" /{b=NR} END{exit !(a && b == a + 1)}' $S && grep -q '    DMCCTMakeTiles();   // (our Mac tiles, CCTiles.h' $P \
   && grep -q 'if (!have\[MSBDCCRoleTileSound\]) \[gCCPTiles addObject:' $P && grep -q 'DMCCPanelAddTile(t); }' $T"
check "  ... told at each presentation (before each tile's tileWillPresent) and after each close (after each tileDidDismiss)" \
  "awk '/^static void DMCCPWillPresent\(void\)/{f=1} f&&/DMCCTPanelWillPresent\(\);/{a=1} f&&a&&/\[t tileWillPresent\];/{print \"ok\"; exit}' $P | grep -q ok \
   && awk '/^static void DMCCPDidDismissHook/{f=1} f&&/\[t tileDidDismiss\];/{a=1} f&&a&&/DMCCTPanelDidDismiss\(\);/{print \"ok\"; exit}' $P | grep -q ok"
check "the API table: every private call with the types read on 15.6.1 and 17.5.1, all of a part's rows or that part falls back" \
  "grep -qF '{ \"BluetoothManager\", \"setPowered:\", \"B20@0:8B16\", NO, kDMCCTPartBT },' $T && grep -qF '{ \"RadiosPreferences\", \"setAirplaneMode:\", \"v20@0:8B16\", NO, kDMCCTPartAirplane },' $T \
   && grep -qF '{ \"AVSystemController\", \"setActiveCategoryVolumeTo:\", \"B20@0:8f16\", NO, kDMCCTPartVolume },' $T && grep -qF '{ \"SBDisplayBrightnessController\", \"setBrightnessLevel:animated:\", \"B24@0:8f16B20\", NO, kDMCCTPartBright },' $T \
   && grep -q 'gCCTPart\[kDMCCTNeeds\[i\].part\] = NO;' $T && grep -q 'gCCTMR.ok = gCCTMR.info && gCCTMR.playing && gCCTMR.reg && gCCTMR.send' $T"
check "Airplane Mode as Control Center's own button does it (17.5.1's cache): AppSupport's RadiosPreferences made with a serial queue (-initWithQueue:, ours), every call on that queue, never SpringBoard's main thread" \
  "for r in 'initWithQueue:\", \"@24@0:8@16' 'airplaneMode\", \"B16@0:8' 'setAirplaneMode:\", \"v20@0:8B16' 'refresh\", \"v16@0:8' 'setDelegate:\", \"v24@0:8@16'; do grep -qF \"{ \\\"RadiosPreferences\\\", \\\"\$r\\\", NO, kDMCCTPartAirplane },\" $T || exit 1; done \
   && grep -qF 'gCCTRadios = [(id<DMCCTRadios>)[objc_getClass(\"RadiosPreferences\") alloc] initWithQueue:DMCCTQueue()];' $T \
   && [ \$(grep -c 'id<DMCCTRadios> p = DMCCTRadiosNow();' $T) = 4 ] \
   && ! awk '/^static (void|int) DMCCTAirplane(Read|Watch|Set|State)/{f=1} f&&/dispatch_async\(DMCCTQueue\(\), \^\{/{q=1} f&&/\[(p|gCCTRadios) (airplaneMode|setAirplaneMode:|refresh|setDelegate:)/{if (!q) print \"bad\"} f&&/^}/{f=0; q=0}' $T | grep -q bad"
check "  ... told of a change only while Control Center shows (-refresh, then -setDelegate:; closed: -setDelegate: nil), as Apple's module; the button sets the opposite of what shows; an unknown state opens Apple's own" \
  "awk '/^static void DMCCTAirplaneWatch\(BOOL watch\) \{/{f=1} f&&/if \(!watch\) \{ \[p setDelegate:nil\]; return; \}/{a=1} f&&a&&/\[p refresh\];/{b=1} f&&b&&/\[p setDelegate:gCCTAirplaneDelegate\];/{print \"ok\"; exit}' $T | grep -q ok \
   && grep -q 'static void DMCCTPanelWillPresent(void) { gCCTShown = YES; DMCCTAirplaneWatch(YES); }' $T && awk '/^static void DMCCTPanelDidDismiss/{f=1} f&&/DMCCTAirplaneWatch\(NO\);/{print \"ok\"; exit}' $T | grep -q ok \
   && grep -q '        DMCCTAirplaneSet(!now);' $T && grep -q '        \[p setAirplaneMode:on\];' $T && grep -q 'if (now < 0) {   // (not read on this iPadOS, or not yet: Apple.s own button, in its module)' $T"
# (1.8.0 review 10: the delegate as built -- its class from CCTiles.h, run here -- answers only what it implements, -airplaneModeChanged, the one
#  delegate method Apple's own button has: it answered a no-argument void signature for any selector and dropped the message, so a call that
#  returns a value would have read garbage, and an unknown message never raised)
{ echo '#import <Foundation/Foundation.h>'; echo 'static int gReads = 0; static void DMCCTAirplaneRead(NSString *why) { gReads++; } static void DMLog(NSString *s) { (void)s; }'
  awk '/^@interface DMCCTAirplaneDelegate : NSObject$/{f=1} f{print} f&&/^@end$/{f=0}' $T; awk '/^@implementation DMCCTAirplaneDelegate$/{f=1} f{print} f&&/^@end$/{exit}' $T
  cat <<'M'
int main(void) {
    @autoreleasepool {
        DMCCTAirplaneDelegate *d = [DMCCTAirplaneDelegate new]; int bad = 0;
        [d performSelector:NSSelectorFromString(@"airplaneModeChanged")]; if (gReads != 1) { bad++; puts("FAIL airplaneModeChanged does not read again"); }
        SEL unknown = NSSelectorFromString(@"airplaneModeChangedForIdentifier:"), value = NSSelectorFromString(@"shouldSyncAirplaneMode");
        if ([d respondsToSelector:unknown] || [d respondsToSelector:value]) { bad++; puts("FAIL answers a selector it does not implement"); }
        if ([d methodSignatureForSelector:value] || [d methodSignatureForSelector:unknown]) { bad++; puts("FAIL a signature for a selector it does not implement"); }
        BOOL raised = NO; @try { [d performSelector:value]; } @catch (NSException *e) { raised = [e.name isEqualToString:NSInvalidArgumentException]; }
        if (!raised) { bad++; puts("FAIL an unknown message is swallowed (no unrecognized selector)"); }
        if (gReads != 1) { bad++; puts("FAIL an unknown message read Airplane Mode again"); }
        return bad;
    }
}
M
} > "$W/apd.m"
check "  ... its delegate answers only -airplaneModeChanged (run: an unknown or value-returning selector is not answered and raises, as for any object; review 10)" \
  "clang -fobjc-arc -Wno-unused-function -Wno-arc-performSelector-leaks -framework Foundation -o '$W/apd' '$W/apd.m' 2>/dev/null && '$W/apd'"
check "  ... its button Apple's orange when on (+[UIColor systemOrangeColor], the module's own), its symbol Apple's airplane; no chevron, no page, only its button takes a touch, no Show Details for VoiceOver" \
  "grep -q 'UIColor \*onColor = MSBDCCTRowTint(_kind) == kMSBDCCTTintOrange ? \[UIColor systemOrangeColor\] : \[UIColor systemBlueColor\];' $T && grep -qF '_kind == kMSBDCCTRowAirplane ? @\"airplane\" : @\"wifi\"' $T \
   && grep -q '_chevron.hidden = !MSBDCCTRowHasPage(kind);' $T && grep -q 'if (MSBDCCTRowHasPage(k)) r.onDetails = ^{ \[weakSelf dm_openPage:k\]; };' $T && grep -q 'if (!MSBDCCTRowHasPage(kind) || gCCPDetail || gCCPExpanded) return;' $T \
   && grep -qF 'return CGRectContainsPoint(CGRectInset(_circle.frame, -6.0, -6.0), p);' $T && grep -qF 'if (!self.onDetails) return nil;   // (no page)' $T"
check "AirDrop is gone from the block: no AirDrop row, page, controller or test state (it stays in Apple's Connectivity module, a hold on the block)" \
  "! grep -n 'SFAirDrop\|kMSBDCCTRowAirDrop\|AirDropPage\|DMCCTAirDrop\|gCCTFakeAirDrop\|cct_adfake' $T ../common/CCTileLogic.h && grep -qF 'BOOL opened = DMCCPanelExpandModule(@\"com.apple.control-center.ConnectivityModule\");' $T"
check "  ... the frameworks opened only at the panel's build (when Apple builds Control Center), never earlier" \
  "awk '/^static void DMCCTMakeTiles/{f=1} f&&/DMCCTCheck\(\);/{print \"ok\"; exit}' $T | grep -q ok && [ \$(grep -c 'dlopen(\"/System/Library/PrivateFrameworks/BluetoothManager' $T) = 1 ] \
   && ! grep -q 'DMCCTCheck();' $S"
check "a page's rows close Control Center, not a menu: DMCloseThen asks the rows' host, our builder sets it around a menu's own builder and puts it back" \
  "grep -q '    if (gDMRowsHost != kDMRowsHostMenu) return DMCCTCloseThen(action);' $S \
   && awk '/^static NSArray \*DMCCTRows/{f=1} f&&/int was = gDMRowsHost;/{a=1} f&&a&&/NSArray \*items = builder\(\);/{b=1} f&&b&&/gDMRowsHost = was;/{print \"ok\"; exit}' $T | grep -q ok"
check "  ... its action once Apple's dismissal is done (a second later where no close comes); the Lock Screen greys rows that need Settings or our menu window" \
  "awk '/^static dispatch_block_t DMCCTCloseThen/{f=1} f&&/DMCCPanelDismiss\(\);/{a=1} f&&a&&/DMCCTRunAfterClose\(@\"no close seen in 1 s\"\)/{print \"ok\"; exit}' $T | grep -q ok \
   && awk '/^static void DMCCTPanelDidDismiss/{f=1} f&&/DMCCTRunAfterClose\(@\"Control Center closed\"\);/{print \"ok\"; exit}' $T | grep -q ok \
   && grep -q 'if (route != DMWiFiRouteJoin && DMRowsHostLocked()) { row.enabled = NO; \[row refresh\]; }' $F && grep -q 'initWithTitle:@\"Wi-Fi Settings…\" enabled:!DMRowsHostLocked()' $F \
   && grep -q 'initWithTitle:@\"Bluetooth Settings…\" enabled:!DMRowsHostLocked()' $T && grep -q 'initWithTitle:@\"Sound Settings…\" enabled:!DMRowsHostLocked()' $T"
check "the Wi-Fi page is the Wi-Fi menu's own rows, scanning only while it shows: the watchdog knows the page, its close and Control Center's stop the scan, the screen going off too" \
  "grep -q 'return DMWiFiMenuItems(&sig);' $T && grep -q 'if (!gWiFiPanel.window && !DMCCTWiFiPageShown()) { DMWiFiStopScanning(@\"watchdog: the menu is gone\"); return; }' $F && grep -q 'DMGateTimer(gWiFiWatchdog);' $F \
   && grep -q 'DMWiFiStopScanning(@\"Control Center.s Wi-Fi page closed\")' $T && grep -q 'if (gWiFiScanning && !gWiFiPanel.window) DMWiFiStopScanning(@\"Control Center closed\");' $T \
   && grep -q '    DMCCTScreenOff();   // (our own Control Center' $S && grep -q '    DMCCTWiFiListChanged();   // (our own Control Center' $F"
check "  ... with the Wi-Fi Menu switched off its chevron opens Apple's own Connectivity (the crash guard's switch for that code holds)" \
  "grep -q 'if (kind == kMSBDCCTRowWiFi && !(gWiFiMenuOn && DMWiFiSupported())) {' $T"
check "the Audio menu and the Sound page have one builder (DMAudioMenuItems); the page adds Sound Settings…" \
  "grep -q '^static NSArray \*DMAudioMenuItems(NSUInteger \*countOut) {' $S && awk '/^static void DMOpenAudioMenu/{f=1} f&&/NSArray \*items = DMAudioMenuItems\(&n\);/{print \"ok\"; exit}' $S | grep -q ok \
   && grep -q 'NSMutableArray \*it = \[DMAudioMenuItems(&n) mutableCopy\];' $T"
check "nothing runs while Control Center is closed: the observers only mark a tile's state old (a change of the volume asks the level again, off the main thread; Airplane Mode's preferences tell nothing then), no timer or display link of the tiles' own" \
  "grep -q 'if (!gCCTShown) { c.old = YES; return; }' $T && grep -q 'if (!gCCTShown) { t.old = YES; return; }' $T && [ \$(grep -c 'if (!gCCTShown) { t.old = YES; return; }' $T) = 2 ] \
   && ! grep -q 'NSTimer\|CADisplayLink\|scheduledTimer' $T && grep -q 'static void DMCCTPanelWillPresent(void) { gCCTShown = YES; DMCCTAirplaneWatch(YES); }' $T \
   && grep -q 'dispatch_async(dispatch_get_main_queue(), ^{ DMCCTLevelChanged(MSBDCCRoleTileSound, 0, NO); });' $T && grep -q 'static double DMCCTVolumeNow(BOOL \*ok) {   // (our queue only)' $T"
check "the artwork is decoded off the main thread (MediaRemote answers on our queue), only when it is another picture" \
  "[ \$(grep -c 'imageWithData:' $T) = 1 ] && grep -q 'gCCTMR.info(DMCCTQueue(), ^(CFDictionaryRef infoRef) {' $T && grep -q 'if (data && !\[key isEqual:haveKey\]) {' $T"
check "Apple's Stage Manager module: left out while another window engine of ours runs, looked at again at each presentation" \
  "grep -q '        it->leftOut = MSBDCCLeftOut(it->role, gCCPEngine);' $P && grep -q 'BOOL engine = DMCCPEngineKind() != gCCPEngine;' $P && grep -q 'if (DMSMEnginePicked()) return kMSBDCCEngineStageManager;' $P"
check "assistive features read the panel in its order on the screen (CCLayout.h MSBDCCAXOrder), escape goes back or closes; sliders adjustable, rows with Show Details" \
  "grep -q 'int na = MSBDCCAXOrder(items, k, ax);' $P && grep -q 'gCCPScroll.accessibilityElements = els;' $P && grep -q 'if (gCCPDetail) DMCCPanelCloseDetail(YES);' $P \
   && grep -q '(UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitAdjustable; }' $T && [ \$(grep -c 'initWithName:@\"Show Details\"' $T) = 2 ] && grep -q 'DMCCPanelAddBlocking(_slider.drag);' $T"
check "the crash guard: a crash in the tiles sets Control Center Style back to iPadOS's (their functions DMCCT..., their file)" \
  "grep -q '^sym MacStatusBarCore ^_\*DMCCT\[A-Z\] controlcenter$' crashmap-rules.txt && grep -qxF 'file MacStatusBarCore ^(CCTiles|CCTileLogic)\\.h\$ controlcenter' crashmap-rules.txt \
   && ! grep -E '^(__attribute__\(\(unused\)\) )?static [A-Za-z_<> *]+[ *]([A-Za-z_]+)\(' $T | grep -v -E '[ *](DMCCT[A-Za-z]*)\(' | grep -q ."
check "the tests' triggers never switch a real radio (Airplane Mode included), device or KT's music (only test states), and the logs name no network, device or track" \
  "grep -q 'cct_tap_ refused: no test state set (it would switch the radio)' $T && grep -q 'cct_np_ refused: no test state set' $T && grep -q 'refused (it would join a network or switch a device: use a test state)' $T \
   && grep -q 'gCCTFakeBT != 0 : gCCTFakeAirplane >= 0;' $T && grep -q 'if (gCCTFakeAirplane >= 0) { gCCTFakeAirplane = on ? 1 : 0;' $T \
   && grep -q 'title %lu chars' $T && ! grep -n 'DMLog(.*DMCCTBTDeviceName(d)\]' $T | grep -v DMWiFiTag | grep -q ."
check "no em dashes in the new files" "! grep -n \$'\\xe2\\x80\\x94' $T ../common/CCTileLogic.h test-cctiles.c test-cctiles.sh"
[ $fails = 0 ] && echo "test-cctiles: wiring checks pass" || { echo "test-cctiles: wiring checks FAILED"; exit 1; }
