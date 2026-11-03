#!/bin/bash
# Mac test of the battery menu and the Control Center icon (1.7.9 items 1-2): the plain C (common/BatteryMenu.h, test-batterymenu.c) -- built
# twice where the Charge Limit's job is in the tree: with its rows, and as a tree without the job (its header out of reach) builds it --, and
# the wiring in SpringBoard (statusbar/BatteryMenu.h, StatusBar.x), Settings (the switch) and the crash guard's map.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -o "$W/tbm" test-batterymenu.c && "$W/tbm" || fails=1
if [ -f ../common/ChargeLimit.h ]; then   # (the same, as a tree without the job compiles it: BatteryMenu.h alone, no ChargeLimit.h beside it)
  mkdir -p "$W/nojob/common" "$W/nojob/tools"; cp ../common/BatteryMenu.h "$W/nojob/common/"; cp test-batterymenu.c "$W/nojob/tools/"
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
  "grep -q '^target batteryMenu pref com.besiktasliseba.macstatusbar batteryMenu 0 1 Battery Menu|the battery menu$' crashmap-rules.txt && grep -q '^file MacStatusBarCore ^BatteryMenu\\\\.h\$ batteryMenu$' crashmap-rules.txt"
check "the battery and the icon are our controls: the status bar's own region action (Control Center for a click) is not run on them" \
  "fn $X 'static BOOL DMPointOverOurControl(' | grep -q 'kSpotButtonKey, kClockButtonKey, kBattButtonKey, kCCButtonKey };'"
check "the right end from MSBDBattRightSideLayout: the icon left of the clock, then Spotlight's icon and touch area, then the status icons" \
  "grep -q 'MSBDBattRightSide side = DMBattCCLayout(fg, rtl, clockEdge, timeCentre.y, timeFont, k, gShowSpotlight, spotW, kSpotHitSlop \\* k, kSpotClockGap \\* k);' $X \
   && grep -q 'spotBtn.frame = DMBarRect(fg, rtl, CGRectMake(side.spotBtnLead, 0, side.spotBtnTrail - side.spotBtnLead, fg.bounds.size.height));' $X \
   && grep -q 'CGFloat iconsEnd = side.iconsEnd;' $X && fn $B 'static MSBDBattRightSide DMBattCCLayout(' | grep -q 'MSBDBattRightSideLayout(clockEdge, show, w, spot, spotW, gap, spotSlop);'"
check "the battery's button laid out where the status icons start, before our Wi-Fi icon takes its place; its area from MSBDBattButtonSpan" \
  "awk '/DMBattLayoutButton\\(fg, left, k\\);/{a=NR} /left = DMWiFiLayoutIcon\\(fg, left, timeCentre.y, k\\);/{b=NR} END{exit !(a && b == a + 3)}' $X \
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
check "the menu's level and power source are the bar's own (SpringBoard's SBUIController, the types read), iPadOS's power sources only without them" \
  "fn $B 'static DMBattInfo DMBattNow(' | awk '/DMBattTypes\(ui, @\"batteryCapacityAsPercentage\", \"i16@0:8\"\)/{a=NR} /if \(b.known\) return b;/{b=NR} /IOPSCopyPowerSourcesInfo|copyInfo\(\)/{c=NR} END{exit !(a && b > a && c > b)}'"
check "Low Power Mode as Control Center's toggle: _PMLowPowerMode -setPowerMode:fromSource:withCompletion: with kPMLPMSourceControlCenter, the types read" \
  "fn $B 'static DMBattLPMWay DMBattLPMHow(' | grep -q 'dlsym(RTLD_DEFAULT, \"kPMLPMSourceControlCenter\")' && fn $B 'static DMBattLPMWay DMBattLPMHow(' | grep -q 'DMBattTypes(lpm, @\"setPowerMode:fromSource:withCompletion:\", \"v40@0:8q16@24@?32\")'"
check "  ... off the main thread; the switch shows what iPadOS says (NSProcessInfo), the open menu follows its notification" \
  "fn $B 'static void DMBattSetLowPower(' | grep -q 'dispatch_async(q, ^{' && grep -q 'return \\[NSProcessInfo processInfo\\].isLowPowerModeEnabled;' $B && fn $B 'static void DMBattApplyPref(' | grep -q 'NSProcessInfoPowerStateDidChangeNotification'"
check "the icon opens Control Center as a click on the status icons does (-handleIndirectStatusBarAction, no argument, either return), else -presentAnimated:" \
  "fn $B 'static void DMBattOpenControlCenter(' | grep -q 'DMBattTypes(cc, @\"handleIndirectStatusBarAction\", \"v16@0:8\") || DMBattTypes(cc, @\"handleIndirectStatusBarAction\", \"B16@0:8\")' && fn $B 'static void DMBattOpenControlCenter(' | grep -q '@\"presentAnimated:\", @\"presentAnimated:completion:\"'"
check "  ... not on the Lock Screen, the Cover Sheet or in Guided Access" \
  "fn $B 'static void DMBattOpenControlCenter(' | grep -q 'if (DMLockUp(lm) || DMCoverSheetShown())' && fn $B 'static void DMBattOpenControlCenter(' | grep -q 'DMGARefuses(@\"Control Center\")'"
check "the Charge Limit job's rows only where it is part of the build and installed; Charge to Full Now as Settings' button (the job's notification)" \
  "fn $B 'static NSArray *DMBattMenuItems(' | grep -q 'BOOL job = DMBattChargeJob();' && fn $B 'static NSArray *DMBattMenuItems(' | grep -q 'notify_post(MSBD_CHARGE_FULL_NOW);' \
   && fn $B 'static NSArray *DMBattMenuItems(' | grep -q 'BOOL full = MSBDChargeOffersFullNow(word, limitPref);' && grep -q '^#if MSBD_BATT_CHARGE' $B"
check "  ... the job found from its file's mode (stat), never asked with access(X_OK): SpringBoard's sandbox answers that check with EPERM on 18.5" \
  "grep -q 'static BOOL DMBattChargeJob(void) { struct stat st; return stat(MSBD_BATT_CHARGE_JOB, &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & S_IXUSR); }' $B \
   && ! grep 'static BOOL DMBattChargeJob' $B | grep -q 'access('"
check "Sleep Guard's state as Settings shows it; the helper's notifications the same as Settings' and the helper's" \
  "for n in CHECK UPDATED; do a=\$(grep -o \"#define MSBD_SG_\$n *\\\"[^\\\"]*\\\"\" $B | sed 's/  */ /g'); b=\$(grep -o \"#define MSBD_SG_\$n *\\\"[^\\\"]*\\\"\" ../macsettings/BatteryUse.x | sed 's/  */ /g'); c=\$(grep -o \"#define MSBD_SG_\$n *\\\"[^\\\"]*\\\"\" ../macsettings/sshtoggled/SleepGuardDaemon.h | sed 's/  */ /g'); [ -n \"\$a\" ] && [ \"\$a\" = \"\$b\" ] && [ \"\$a\" = \"\$c\" ] || exit 1; done \
   && fn $B 'static NSString *DMBattCantSleep(' | grep -q \"if (!\\[st\\[@\\\"cantSleep\\\"\\] boolValue\\] || \\[st\\[@\\\"stuck\\\"\\] intValue\\] <= 0) return nil;\""
check "no Mac's \"Using Significant Energy\" (nothing honest to read live) and no em dash in the menu's code" \
  "! grep -q '@\"Using Significant Energy' $B && ! grep -q \$'\\xe2\\x80\\x94' $B ../common/BatteryMenu.h test-batterymenu.c"
[ $fails = 0 ] && echo "test-batterymenu: all checks pass" || { echo "test-batterymenu: checks FAILED"; exit 1; }
