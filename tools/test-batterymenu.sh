#!/bin/bash
# Mac test of the battery menu and the Control Center icon (1.7.9 items 1-2): the plain C (common/BatteryMenu.h, test-batterymenu.c) -- built
# twice where the Charge Limit's job is in the tree: with its rows, and as a tree without the job (its header out of reach) builds it --, and
# the wiring in SpringBoard (statusbar/BatteryMenu.h, StatusBar.x), Settings (the switch) and the crash guard's map.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -o "$W/tbm" test-batterymenu.c && "$W/tbm" || fails=1
if [ -f ../common/ChargeLimit.h ]; then   # (the same, as a tree without the job compiles it: BatteryMenu.h and ChargeWhy.h, no ChargeLimit.h beside them)
  mkdir -p "$W/nojob/common" "$W/nojob/tools"; cp ../common/BatteryMenu.h ../common/ChargeWhy.h "$W/nojob/common/"; cp test-batterymenu.c "$W/nojob/tools/"
  clang -O2 -Wall -o "$W/tbm2" "$W/nojob/tools/test-batterymenu.c" && "$W/tbm2" | grep -q 'no Charge Limit job in this tree' \
    && echo "PASS  without the job's header: no charge rows compiled, the rest as above" || { echo "FAIL  without the job's header"; fails=1; }
fi

B=../statusbar/BatteryMenu.h; X=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/Resources/Root.plist
# ---- the switch in the Settings search: the index (common/TweakIndex.h) read from the real Status Bar page, searched as Settings searches it
mkdir -p "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle" "$W/lib/PreferenceLoader/Preferences"; cp "$P" "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle/Root.plist"
cat > "$W/tidx.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import "TweakIndex.h"
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *root = @(argv[1]);
        MTIConfig *c = [MTIConfig new];
        c.plDirs = @[[root stringByAppendingPathComponent:@"PreferenceLoader/Preferences"]]; c.bundleDirs = @[[root stringByAppendingPathComponent:@"PreferenceBundles"]];
        c.supportDir = root; c.languages = @[@"en-US"]; c.cfVersion = 1953.1; c.maxPerPane = 400; c.maxTotal = 6000;
        c.own = @[@{@"id": @"MAC_STATUS_BAR", @"title": @"Status Bar", @"bundle": [root stringByAppendingPathComponent:@"PreferenceBundles/MacStatusBarPrefs.bundle"]}];
        c.skipBundles = @[@"MacStatusBarPrefs"];
        NSArray<MTIEntry *> *hits = MTIMatch(MTIBuild(c), @"battery menu", 10);
        MTIEntry *e = hits.firstObject;
        BOOL ok = e && [e.title isEqualToString:@"Battery Menu"] && [e.crumb isEqualToString:@"Status Bar"] && [MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_STATUS_BAR#BATTERY_MENU"];
        printf("%s  the switch in the Settings search: \"battery menu\" finds %s (%s, %s)\n", ok ? "PASS" : "FAIL", e ? e.title.UTF8String : "nothing",
               e ? e.crumb.UTF8String : "-", e ? MTIPrefsURL(e.uid).UTF8String : "-");
        return ok ? 0 : 1;
    }
}
OBJC
clang -fobjc-arc -Wall -Wno-unused-function -I../common -framework Foundation -o "$W/tidx" "$W/tidx.m" && "$W/tidx" "$W/lib" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line (not a declaration)
check "the switch: Settings' Battery Menu (batteryMenu, on by default, hidden with the stock status bar), read as MSBDBattMenuOn" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; i=[x.get('id') for x in it].index('BATTERY_MENU'); s=it[i]; g=it[i-1]; sys.exit(0 if s['key']=='batteryMenu' and s['default'] is True and s['cell']=='PSSwitchCell' and s['label']=='Battery Menu' and s['PostNotification']=='com.besiktasliseba.macstatusbar/prefsChanged' and g['cell']=='PSGroupCell' and g.get('stockHides') is True else 1)\" \
   && grep -q 'CFPreferencesCopyValue(CFSTR(MSBD_BATT_MENU_KEY), MSB_DOMAIN' $X && grep -q 'DMBattApplyPref(MSBDBattMenuOn(isBool, isBool && CFBooleanGetValue(bmRef)));' $X"
check "the crash guard: a crash in the menu's code turns Battery Menu off" \
  "grep -q '^target batteryMenu pref com.besiktasliseba.macstatusbar batteryMenu 0 1 Battery Menu|the battery menu$' crashmap-rules.txt && grep -q '^file MacStatusBarCore ^(BatteryMenu|ChargeWhy)\\\\.h\$ batteryMenu$' crashmap-rules.txt"
check "  ... (1.8.8.1) why iPad is not charging too: common/ChargeWhy.h's functions a release build keeps out of line (MSBDBattWhyLine at -Os) are Battery Menu's, not the whole bar's (make-crashmap.py's own code)" \
  "[ \"\$(python3 -I - crashmap-rules.txt <<'PYEOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'bm'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
print(' '.join(g['classify']('MacStatusBarCore', n, f, '', rules, im, hits) for n, f in [('_MSBDBattWhyLine', 'ChargeWhy.h'), ('_MSBDBattWhyDecide', 'ChargeWhy.h'), ('_MSBDBattChargeLine', 'BatteryMenu.h'), ('_MSBDChargeQuietAfterCut', 'ChargeQuiet.x')]))
PYEOF
)\" = 'batteryMenu batteryMenu batteryMenu part' ]"
check "the battery and the icon are our controls: the status bar's own region action (Control Center for a click) is not run on them" \
  "fn $X 'static BOOL DMPointOverOurControl(' | grep -q 'kSpotButtonKey, kClockButtonKey, kBattButtonKey, kCCButtonKey, DM_AM_BUTTONS };'"
check "the right end from MSBDBattRightSideLayout: the icon left of the clock, then Spotlight's icon and touch area, then the status icons" \
  "grep -q 'MSBDBattRightSide side = DMBattCCLayout(fg, rtl, clockEdge, timeCentre.y, timeFont, k, gShowSpotlight, spotW, kSpotHitSlop \\* k, kSpotClockGap \\* k);' $X \
   && grep -q 'spotBtn.frame = DMBarRect(fg, rtl, CGRectMake(side.spotBtnLead, 0, side.spotBtnTrail - side.spotBtnLead, barH));' $X \
   && grep -q 'CGFloat iconsEnd = side.iconsEnd;' $X && fn $B 'static MSBDBattRightSide DMBattCCLayout(' | grep -q 'MSBDBattRightSideLayout(clockEdge, show, w, spot, spotW, gap, spotSlop);'"
check "the battery's button laid out where the status icons start, before our own headphones icon (1.8.8.2) and our Wi-Fi icon take their place; its area from MSBDBattButtonSpan" \
  "awk '/DMBattLayoutButton\\(fg, left, k\\);/{a=NR} /left = DMAirPodsLayoutOwnIcon\\(fg, left, timeCentre.y, k\\);/{o=NR} /left = DMWiFiLayoutIcon\\(fg, left, timeCentre.y, k\\);/{b=NR} END{exit !(a && o == a + 6 && b == a + 9)}' $X \
   && fn $B 'static void DMBattLayoutButton(' | grep -q 'MSBDBattButtonSpan(DMBarLead(fg, rtl, r), DMBarTrail(fg, rtl, r), 4.0 \\* k, left - 2.0 \\* k, &a, &b)'"
check "  ... the battery's views are its item's own (each region's display items whose item is the battery item), shown ones only" \
  "fn $B 'static NSArray<UIView *> *DMBattItemViews(' | grep -q 'if (!\\[it isKindOfClass:ic\\]) continue;' && grep -q 'static Class DMBattItemClass(void) { return objc_getClass(DMSBUseSTUI() ? \"STUIStatusBarBatteryItem\" : \"_UIStatusBarBatteryItem\"); }' $B"
check "  ... iOS's battery views under it not read a second time (their own setting kept and given back)" \
  "fn $B 'static void DMBattLayoutButton(' | grep -q 'DMBattCoverAX(fg, views, YES);' && fn $B 'static void DMBattCoverAX(' | grep -q 'if (own) v.isAccessibilityElement = own.boolValue;'"
check "the Lock Screen's layout: the battery iOS's own, the icon gone (DMBattLockLayout), as the Spotlight icon" \
  "fn $X 'static BOOL DMLayoutWithoutClock(' | grep -q 'DMBattLockLayout(fg);'"
check "every way a menu closes stops the battery menu's refresh (DMBattMenuGone)" \
  "fn $X 'static void DMRemoveOverlayNow(' | grep -q 'DMBattMenuGone(@\"removed\");' && fn $X 'static void DMCloseOverlay(' | grep -q 'DMBattMenuGone(@\"closed\");'"
check "another title tapped with a menu open: the battery opens its menu, the icon Control Center (DMTitleTapSwitch, both paths)" \
  "[ \$(grep -c 'else if (b == objc_getAssociatedObject(bfg, kBattButtonKey)) DMOpenBatteryMenu(b);\\|else if (b == objc_getAssociatedObject(fg, kBattButtonKey)) DMOpenBatteryMenu(b);' $X) -ge 2 ] \
   && [ \$(grep -c 'kCCButtonKey)) DMBattOpenControlCenter(b);' $X) = 2 ]"
check "the menu's level and power source from the battery service (issue #15), looked up once more after a failed read, then iPadOS's power sources, SBUIController last" \
  "fn $B 'static DMBattInfo DMBattNow(' | awk '/if \(!DMBattServiceRead\(DMBattService\(NULL\), &b, &why\)\) \{/{n++; if (n == 1) a=NR; else c=NR} /DMBattServiceForget\(\);/{b=NR} /b = DMBattPowerSources\(\);/{d=NR} /b = DMBattSBUI\(\);/{e=NR} END{exit !(a && b > a && c > b && d > c && e > d)}' \
   && fn $B 'static DMBattInfo DMBattPowerSources(' | grep -q 'IOPSCopyPowerSourcesInfo' && fn $B 'static DMBattInfo DMBattSBUI(' | grep -q 'DMBattTypes(ui, @\"batteryCapacityAsPercentage\", \"i16@0:8\")'"
check "  ... the keys SBUIController is fed with, each with its type: CurrentCapacity, MaxCapacity (numbers), ExternalConnected (not the cable: our adapter cut reads Battery, as before), IsCharging" \
  "fn $B 'static BOOL DMBattServiceRead(' | grep -q 'DMBattReadKey(s, @\"CurrentCapacity\", NO, &cur)' && fn $B 'static BOOL DMBattServiceRead(' | grep -q 'DMBattReadKey(s, @\"MaxCapacity\", NO, &max)' \
   && fn $B 'static BOOL DMBattServiceRead(' | grep -q 'DMBattReadKey(s, @\"ExternalConnected\", YES, &ext)' && fn $B 'static BOOL DMBattServiceRead(' | grep -q 'DMBattReadKey(s, @\"IsCharging\", YES, &chg)' \
   && ! fn $B 'static BOOL DMBattServiceRead(' | grep -q 'AppleRawExternalConnected' && fn $B 'static BOOL DMBattReadKey(' | grep -q 'CFNumberGetTypeID()' && fn $B 'static BOOL DMBattReadKey(' | grep -q 'CFBooleanGetTypeID()'"
check "Low Power Mode as Control Center's toggle: _PMLowPowerMode -setPowerMode:fromSource:withCompletion: with kPMLPMSourceControlCenter, the types read" \
  "fn $B 'static DMBattLPMWay DMBattLPMHow(' | grep -q 'dlsym(RTLD_DEFAULT, \"kPMLPMSourceControlCenter\")' && fn $B 'static DMBattLPMWay DMBattLPMHow(' | grep -q 'DMBattTypes(lpm, @\"setPowerMode:fromSource:withCompletion:\", \"v40@0:8q16@24@?32\")'"
check "  ... off the main thread; the switch shows what iPadOS says (NSProcessInfo), the open menu follows its notification" \
  "fn $B 'static void DMBattSetLowPower(' | grep -q 'dispatch_async(q, ^{' && grep -q 'return \\[NSProcessInfo processInfo\\].isLowPowerModeEnabled;' $B && fn $B 'static void DMBattApplyPref(' | grep -q 'NSProcessInfoPowerStateDidChangeNotification'"
check "the icon opens Control Center as a click on the status icons does (-handleIndirectStatusBarAction, no argument, either return), else -presentAnimated:" \
  "fn $B 'static void DMBattOpenControlCenter(' | grep -q 'DMBattTypes(cc, @\"handleIndirectStatusBarAction\", \"v16@0:8\") || DMBattTypes(cc, @\"handleIndirectStatusBarAction\", \"B16@0:8\")' && fn $B 'static void DMBattOpenControlCenter(' | grep -q '@\"presentAnimated:\", @\"presentAnimated:completion:\"'"
check "  ... not on the Lock Screen, the Cover Sheet or in Guided Access" \
  "fn $B 'static void DMBattOpenControlCenter(' | grep -q 'if (DMLockUp(lm) || DMCoverSheetShown())' && fn $B 'static void DMBattOpenControlCenter(' | grep -q 'DMGARefuses(@\"Control Center\")'"
check "the Charge Limit job's rows only where it is part of the build and installed; Charge to Full Now as Settings' button (the job's notification)" \
  "fn $B 'static NSArray *DMBattMenuItems(' | grep -q '    job = DMBattChargeJob();' && fn $B 'static NSArray *DMBattMenuItems(' | grep -q 'notify_post(MSBD_CHARGE_FULL_NOW);' \
   && fn $B 'static NSArray *DMBattMenuItems(' | grep -q 'BOOL full = MSBDChargeOffersFullNow(word, limitPref);' && grep -q '^#if MSBD_BATT_CHARGE' $B"
check "  ... the job found from its file's mode (stat), never asked with access(X_OK): SpringBoard's sandbox answers that check with EPERM on 18.5" \
  "grep -q 'static BOOL DMBattChargeJob(void) { struct stat st; return stat(MSBD_BATT_CHARGE_JOB, &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & S_IXUSR); }' $B \
   && ! grep 'static BOOL DMBattChargeJob' $B | grep -q 'access('"
check "Sleep Guard's state as Settings shows it; the helper's notifications the same as Settings' and the helper's" \
  "for n in CHECK UPDATED; do a=\$(grep -o \"#define MSBD_SG_\$n *\\\"[^\\\"]*\\\"\" $B | sed 's/  */ /g'); b=\$(grep -o \"#define MSBD_SG_\$n *\\\"[^\\\"]*\\\"\" ../macsettings/BatteryUse.x | sed 's/  */ /g'); c=\$(grep -o \"#define MSBD_SG_\$n *\\\"[^\\\"]*\\\"\" ../macsettings/sshtoggled/SleepGuardDaemon.h | sed 's/  */ /g'); [ -n \"\$a\" ] && [ \"\$a\" = \"\$b\" ] && [ \"\$a\" = \"\$c\" ] || exit 1; done \
   && fn $B 'static NSString *DMBattCantSleep(' | grep -q \"if (!\\[st\\[@\\\"cantSleep\\\"\\] boolValue\\] || \\[st\\[@\\\"stuck\\\"\\] intValue\\] <= 0) return nil;\""
check "1.8.0 (KT 3 Nov): the Control Center icon shows with Battery Menu on, or with our own Control Center the style in force (CCPanel.h DMCCPanelWanted), Battery Menu off too" \
  "fn $B 'static MSBDBattRightSide DMBattCCLayout(' | grep -q 'BOOL want = gBattMenuOn || DMCCPanelWanted();' && fn $B 'static MSBDBattRightSide DMBattCCLayout(' | grep -q 'BOOL show = want && icon.image != nil;' && fn $B 'static MSBDBattRightSide DMBattCCLayout(' | grep -q 'if (want && !icon) {'"
check "  ... lit while Control Center is open (a highlight behind it, the title pills' 25 %), from its -_willPresent to its -_didDismiss, out again if a close was missed (the tick); gone with the icon (the Lock Screen's layout, a collapsed copy)" \
  "awk '/^%group CCPresentSeen/,/^%end/' $X | grep -q 'DMBattCCLight(YES);' && awk '/^%group CCIconLight/,/^%end/' $X | grep -q 'DMBattCCLight(NO);' && grep -q '        DMBattCCLight(NO);   // (a close whose -_didDismiss we did not see' $X && fn $B 'static void DMBattCCLightCopy(' | grep -q 'BOOL on = gCCIconLit && icon && !icon.hidden;' && fn $B 'static void DMBattLockLayout(' | grep -q 'kCCPillKey' && grep -q 'kCCButtonKey, kCCPillKey, kMuteIconKey' $X"
check "1.8.6: during a charge hold the bars' batteries show a plug, not iOS's bolt: kept at state 0 (iOS's state given back after), drawn at each bar layout and when the job's state changes" \
  "grep -qF 'DMBattHoldBar(fg);     // (a plug in the battery' $X && grep -qF 'static BOOL DMBattHoldTakes(id battery, long long *state)' $B && grep -qF 'notify_register_dispatch(MSBD_CHARGE_STATE, &t, dispatch_get_main_queue(), ^(int tok) { DMBattHoldEveryBar(); });' $B && grep -qF 'MSBDBattHoldPlug(DMBattChargeWord())' $B"
check "  ... -setChargingState: hooked only where its types are as read, on each class with its own, the first time a hold is seen" \
  "grep -qF 'MSHookMessageEx(c, sel, imps[i], (IMP *)&o_BattHoldSet[i]);' $X && grep -qF 'strcmp(method_getTypeEncoding(m) ?: \"\", \"v24@0:8q16\")' $X && grep -qF 'DMBattHoldHookInit();' $B"
check "  ... the crash guard turns it off by itself (batteryHoldPlug, a piece: no Settings row, Turn Back On brings it back), not Battery Menu" \
  "grep -qx 'target batteryHoldPlug piece the battery icon|the plug in the battery icon during a charge hold' ../tools/crashmap-rules.txt && grep -q '^sym MacStatusBarCore ^_\\*DMBattHold\\[A-Z\\] batteryHoldPlug' ../tools/crashmap-rules.txt && grep -qF 'skipped = MSBDCrashSkipped(MSBD_BATT_HOLD_PIECE);' $B && grep -qF '#define MSBD_BATT_HOLD_PIECE \"batteryHoldPlug\"' ../common/BatteryMenu.h && ! grep -q 'batteryHoldPlug pref\\|MSBD_BATT_HOLD_PLUG_KEY' ../tools/crashmap-rules.txt $B ../common/BatteryMenu.h"
check "1.8.8.1 BATTWHY: the menu's line is MSBDBattMenuLine's, from MSBDBattWhyDecide on what DMBattWhyRead read, with or without the job (no line outside it)" \
  "fn $B 'static NSArray *DMBattMenuItems(' | grep -qF 'MSBDBattWhyIn why = DMBattWhyRead(b);' && fn $B 'static NSArray *DMBattMenuItems(' | grep -qF 'int whyNow = MSBDBattWhyDecide(why);' \
   && fn $B 'static NSArray *DMBattMenuItems(' | grep -qF 'if (MSBDBattMenuLine(word, b.percent, whyNow, why.watts, line, sizeof line)) [items addObject:[[DMBattInfoRow alloc] initWithText:@(line)]];' \
   && ! grep -q 'MSBDBattChargeLine(' $B && [ \$(grep -c 'MSBDBattWhyDecide(' $B) = 2 ] && fn $B 'static void DMBattLogMenu(' | grep -qF 'MSBDBattWhyName(MSBDBattWhyDecide(w))' \
   && awk '/^static NSArray \\*DMBattMenuItems\\(/{f=1} f && /MSBDBattWhyRead|DMBattWhyRead/ {r=NR} f && /^#if MSBD_BATT_CHARGE/ && !a {a=NR} f && /^#endif/ && a && !e {e=NR} f && /^}/ {exit} END{exit !(r && e && r > e)}' $B"
check "  ... (review of the line) \"Charging Can't Be Paused\" kept after its reason: MSBDBattMenuLineAfter's row right after the line's, on the same reading, in the menu's signature" \
  "fn $B 'static NSArray *DMBattMenuItems(' | awk '/if \\(MSBDBattMenuLine\\(word, b.percent, whyNow, why.watts, line, sizeof line\\)\\)/{a=NR} /if \\(MSBDBattMenuLineAfter\\(word, b.percent, whyNow, why.watts, after, sizeof after\\)\\) \\[items addObject:\\[\\[DMBattInfoRow alloc\\] initWithText:@\\(after\\)\\]\\];/{b=NR} END{exit !(a && b == a + 1)}' \
   && fn $B 'static NSArray *DMBattMenuItems(' | grep -qF '[sig appendFormat:@\"%d%s|%s|\", job, line, after];' && [ \$(grep -c 'MSBDBattMenuLineAfter(' $B) = 1 ]"
check "  ... no new cost with the menu closed: the stamps only in the power sources note DMBattApplyPref already registers (still 3 such registrations, one timer), from DMBattNow's read; the current read there only while not charging under 95 % with no hold of the job's, from the battery service DMBattNow read" \
  "[ \$(grep -c '\"com.apple.system.powersources\"' $B) = 3 ] && fn $B 'static void DMBattApplyPref(' | grep -qF '^(int tok) { DMBattWhyNote(); DMBattMenuChanged(); });' \
   && [ \$(grep -c 'DMBattWhyNote();' $B) = 1 ] && [ \$(grep -c 'scheduledTimerWithTimeInterval' $B) = 1 ] && fn $B 'static void DMBattWhyNote(' | grep -qF 'if (!gBattMenuOn) { gBattWhyClock.notChargingSince = gBattWhyClock.drainingSince = 0; return; }' \
   && fn $B 'static void DMBattWhyNote(' | grep -qF 'if (!b.known || !b.onAC) { MSBDBattWhyTick(&gBattWhyClock, CACurrentMediaTime(), 0, 0); return; }' && [ \$(fn $B 'static void DMBattWhyNote(' | grep -c 'DMBattProp(') = 1 ] \
   && fn $B 'static void DMBattWhyNote(' | grep -qF 'int notCharging = !b.charging, draining = -1;' \
   && fn $B 'static void DMBattWhyNote(' | grep -F 'DMBattProp(DMBattService(NULL), @\"Amperage\")' | grep -qF 'if (gBattFrom == kDMBattFromService && notCharging && b.percent < 95 && !gBattWhyClock.ours) {'"
check "  ... the battery service read one key at a time (never its whole dictionary) through the level's own lookup (1.8.8, one DMBattService, looked up again after a read that failed): the level's read (DMBattReadKey), why it is not charging only by the note and the menu's own read (DMBattMenuItems' alone), the debug probe; nothing more where the level's read could not read it, nothing off the adapter" \
  "[ \$(grep -c 'IORegistryEntryCreateCFProperty(' $B) = 1 ] && ! grep -q 'IORegistryEntryCreateCFProperties\\|BatteryData' $B \
   && [ \$(grep -c '^static io_service_t DMBattService(' $B) = 1 ] && [ \$(grep -c 'IOServiceGetMatchingService(' $B) = 2 ] && [ \$(grep -c '^static id DMBattProp(' $B) = 1 ] \
   && [ \$(grep -c 'DMBattWhyRead(' $B) = 2 ] && [ \"\$(grep -n 'DMBattProp(' $B | awk -F: '{print \$1}' | while read n; do awk -v n=\$n 'NR<=n && /^static /{h=\$0} NR==n{print h}' $B; done | sort -u | sed 's/^static [^(]*[ *]\\(DM[A-Za-z]*\\)(.*/\\1/' | tr '\\n' ' ')\" = 'DMBattReadKey DMBattTrigger DMBattWhyRead DMBattProp DMBattWhyNote ' ] \
   && awk '/^#if/{n++; d[n] = (\$0 ~ /^#if DEBUG/)} /^#endif/{d[n]=0; n--} /^static BOOL DMBattTrigger\\(NSString \\*cmd\\) \\{/{for (i = 1; i <= n; i++) if (d[i]) ok=1; seen=1; exit} END{exit !(seen && ok)}' $B \
   && fn $B 'static MSBDBattWhyIn DMBattWhyRead(' | awk '/if \\(!in.onAdapter\\) \\{/{a=NR} /io_service_t s = gBattFrom == kDMBattFromService \\? DMBattService\\(&pmu\\) : MACH_PORT_NULL;/{b=NR} END{exit !(a && b > a)}' \
   && fn $B 'static MSBDBattWhyIn DMBattWhyRead(' | grep -qF 'if (MSBDBattWhyFirst(in) < 0) in.obc = DMBattOBC();' && fn $B 'static MSBDBattWhyIn DMBattWhyRead(' | grep -qF 'in.charging = b.charging ? 1 : 0;' \
   && ! fn $B 'static MSBDBattWhyIn DMBattWhyRead(' | grep -qF '@\"IsCharging\"'"
check "  ... (review) the job's own hold ending seen by its state note DMBattApplyPref already registers (no new one) and by the menu's read of its word, before the read: no reason for 3 minutes after it; the clocks common/ChargeWhy.h's (MSBDBattWhyClock), the job's way" \
  "[ \$(grep -c 'notify_register_dispatch(MSBD_CHARGE_STATE' $B) = 2 ] && [ \$(fn $B 'static void DMBattApplyPref(' | grep -c 'MSBDBattWhyOurs(&gBattWhyClock, CACurrentMediaTime(), MSBDBattOurHold(DMBattChargeWord()));') = 2 ] \
   && fn $B 'static void DMBattApplyPref(' | awk '/notify_register_dispatch\(MSBD_CHARGE_STATE/{a=NR} /MSBDBattOurHold\(DMBattChargeWord\(\)\)/{b=NR} END{exit !(a && b == a + 1)}' \
   && fn $B 'static NSArray *DMBattMenuItems(' | awk '/MSBDBattWhyOurs\(&gBattWhyClock, CACurrentMediaTime\(\), MSBDBattOurHold\(word\)\);/{a=NR} /DMBattWhyRead\(b\)/{b=NR} END{exit !(a && b == a + 1)}' \
   && fn $B 'static MSBDBattWhyIn DMBattWhyRead(' | awk '/MSBDBattWhyTick\(&gBattWhyClock, now, MSBDBattWhyCharging\(in\) \? 0 : 1, in.ampKnown \? in.amp <= MSBD_WHY_DRAIN_MA : -1\);/{a=NR} /MSBDBattWhyTimes\(&gBattWhyClock, now, &in\);/{b=NR} /MSBDBattWhyFirst\(in\) < 0/{c=NR} END{exit !(a && b == a + 1 && c > b)}' \
   && ! grep -q 'gBattNotChargingSince\|DMBattWhyStamp' $B"
check "  ... debug builds only: battmenu_why_ fakes the readings (as battmenu_word_ fakes the job's word)" \
  "awk '/^#if/{n++; d[n] = (\$0 ~ /^#if DEBUG/)} /^#endif/{d[n]=0; n--} /gBattFakeWhyOn = p.count >= 5;/{seen=1; for (i = 1; i <= n; i++) if (d[i]) ok=1} END{exit !(seen && ok)}' $B && grep -q '^static BOOL gBattFakeWhyOn = NO;' $B \
   && awk '/^static BOOL gBattFakeWhyOn = NO;/{exit !(prev ~ /^#if DEBUG/)} {prev=\$0}' $B"
check "no Mac's \"Using Significant Energy\" (nothing honest to read live) and no em dash in the menu's code" \
  "! grep -q '@\"Using Significant Energy' $B && ! grep -q \$'\\xe2\\x80\\x94' $B ../common/BatteryMenu.h ../common/ChargeWhy.h test-batterymenu.c"
[ $fails = 0 ] && echo "test-batterymenu: all checks pass" || { echo "test-batterymenu: checks FAILED"; exit 1; }
