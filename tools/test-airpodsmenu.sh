#!/bin/bash
# test-airpodsmenu.sh: the AirPods menu (1.8.8.1; plans/airpods-menu.md, design v2 and its check). A click or a finger tap on iPadOS's own AirPods
# item in the menu bar opens a Mac-style AirPods menu (statusbar/AirPodsMenu.h; its rules in plain C, common/AirPodsMenu.h).
#  (1) the rules (test-airpodsmenu.c, -Wall -Wextra -Werror): the button's place beside the battery's, which battery records are which
#      headphones', the cells, the levels, the modes, the route device, every menu kind's rows, the signature, the switch, the glyphs, VoiceOver;
#      since 1.8.8.1.1 when iPadOS's item is the headphones' (the glyph alone too) and which Bluetooth devices the menu lists;
#  (2) the Objective-C side that decides what the bar gets (test-airpodsmenu.m, Mac Catalyst, headless; the real code cut out of
#      statusbar/AirPodsMenu.h, statusbar/BatteryMenu.h and StatusBar.x), both families, release and DEBUG, and an item class with no
#      +batteryDisplayIdentifier; in DEBUG also the made-up Bluetooth item (sbfakebt_, 1.8.8.1.1) on stand-ins of both families' data: 15/16's
#      with setters, 17/18's immutable ones (a mutable data class, entries with instance variables only);
#  (3) the type table (kDMAPNeeds) against this Mac's own frameworks: every class and selector there with the table's types (x86_64's BOOL c read
#      as B). It catches misspellings; the iPads' arm64 types are read by podmenu_probe (D0);
#  (4) the wiring in StatusBar.x, Settings' row, the crash guard's rules (and what they resolve AirPodsMenu.h's functions to), the calls never
#      made, the debug triggers' place, the logs' privacy;
#  then made-to-fail copies of each file, each must fail.
# AP_ROOT: another tree (e.g. the code before the AirPods menu, a git archive): run on it, no made-to-fail copies.
cd "$(dirname "$0")" || exit 1
R0=$(cd "${AP_ROOT:-..}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
fails=0
fndef() {   # $1 file, $2 name: a static function's definition (not a declaration), whole, by its braces
  awk -v n="$2" '
    !f && $0 ~ ("^(__attribute__\\(\\(noinline\\)\\) )?static (inline )?[^(=]*[ *]" n "\\(") && index($0, "{") { f = 1 }
    f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }
  ' "$1"
}
classdef() {   # $1 file, $2 class: its @interface ... @end and @implementation ... @end
  awk -v c="$2" '($0 == "@interface " c " : NSObject" || $0 == "@implementation " c) { f = 1 } f { print } f && $0 == "@end" { f = 0 }' "$1"
}
nocomments() { sed -E 's://.*$::' "$1"; }
ifdebug() {   # $1 file, $2 text: is the line holding it inside an "#if DEBUG" (and not in its #else)? (every such line; "no" if any is not)
  awk -v s="$2" '
    /^#if DEBUG/ { st[++n] = 1; next } /^#if/ { st[++n] = 0; next } /^#else/ { if (st[n] == 1) st[n] = 2; next } /^#endif/ { n--; next }
    index($0, s) { seen = 1; ok = 0; for (i = 1; i <= n; i++) if (st[i] == 1) ok = 1; if (!ok) bad = 1 }
    END { print (seen && !bad) ? "yes" : "no" }
  ' "$1"
}

# ---- (1) the rules ----
plainc() {   # $1 common/AirPodsMenu.h, $2 dir, $3 quiet: rc of the plain-C test on that header
  mkdir -p "$2/common" "$2/tools"
  cp "$1" "$2/common/AirPodsMenu.h" 2>/dev/null || { [ -n "$3" ] || echo "FAIL  no common/AirPodsMenu.h"; return 1; }
  cp "$R0/common/BatteryMenu.h" "$R0/common/ChargeWhy.h" "$2/common/"; cp test-airpodsmenu.c "$2/tools/"   # (BatteryMenu.h includes ChargeWhy.h since 1.8.8.1 F6)
  clang -O2 -Wall -Wextra -Werror -o "$2/t" "$2/tools/test-airpodsmenu.c" > "$2/cc.txt" 2>&1 || { [ -n "$3" ] || { cat "$2/cc.txt" | head -20; echo "FAIL  the rules did not build"; }; return 1; }
  if [ -n "$3" ]; then "$2/t" > /dev/null; else "$2/t"; fi
}

# ---- (2) the Objective-C side ----
harness() {   # $1 StatusBar.x, $2 statusbar/AirPodsMenu.h, $3 statusbar/BatteryMenu.h, $4 dir, $5 quiet, $6 flavours: rc
  local X=$1 A=$2 B=$3 d=$4 q=$5 fl r=0 f
  mkdir -p "$d"
  [ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; return 1; }
  { grep -E '^static inline BOOL DMBarRTL\(' "$X"; fndef "$X" DMBarRect; grep -E '^static inline CGFloat (DMBarLead|DMBarTrail)\(' "$X"; fndef "$X" DMImageInkRect; } > "$d/ap-bar.inc"
  { fndef "$B" DMBattItemClass; fndef "$B" DMBattViewShown; fndef "$B" DMBattItemViews; fndef "$B" DMBattItemRect; fndef "$B" DMBattCoverAX; fndef "$B" DMBattLayoutButton; } > "$d/ap-batt.inc"
  { fndef "$A" DMAPTypes; fndef "$A" DMAPObj; fndef "$A" DMAPStr; fndef "$A" DMAPCopyStr; classdef "$A" DMAPHeadsetRec; } > "$d/ap-types.inc"
  { fndef "$A" DMAPItemClass; fndef "$A" DMAPItemViews; fndef "$A" DMAPBluetoothState; fndef "$A" DMAPCoverAX; fndef "$A" DMAPUnion; fndef "$A" DMAPHideButton; fndef "$A" DMAPButton
    grep -E '^static const void \*kAPItemSeenKey = ' "$A"; fndef "$A" DMAPItemSeen; fndef "$A" DMAPOwnHolds; fndef "$A" DMAPOwnLetGo; fndef "$A" DMAPOwnGlyph
    fndef "$A" DMAirPodsLayoutButton; fndef "$A" DMAirPodsLayoutOwnIcon; fndef "$A" DMAirPodsLockLayout; } > "$d/ap-button.inc"
  { fndef "$A" DMAPMergeHeadsets; fndef "$A" DMAPPartsCopy; fndef "$A" DMAPReadHeadsets; } > "$d/ap-data.inc"
  { fndef "$A" DMAPFakeSet; fndef "$A" DMAPFakeFlag; fndef "$A" DMAPFakeClass; grep -E '^static (const void \*kAPFakeBTKey|NSString \*gAPFakeBarArgs) = ' "$A"
    fndef "$A" DMAPFakeMerged; fndef "$A" DMAPFakeReadBack; fndef "$A" DMAPFakeApply; fndef "$A" DMAPFakeBarItem; fndef "$A" DMAPFakeBarRecheck; fndef "$A" DMAPFakeShowItem; } > "$d/ap-fake.inc"
  # (the Mac's Catalyst UIKit loads the real BluetoothManager framework: the stand-ins' class names are the test's own, the code otherwise as it is)
  sed -i '' 's/objc_getClass("BluetoothManager")/objc_getClass("TBluetoothManager")/; s/objc_getClass("BluetoothDevice")/objc_getClass("TBluetoothDevice")/; s/objc_getClass("BCBatteryDevice")/objc_getClass("TBCBatteryDevice")/' "$d/ap-data.inc"
  [ "$(grep -c 'objc_getClass("TB' "$d/ap-data.inc")" = 3 ] || { [ -n "$q" ] || echo "FAIL  the class names to stand in for were not found"; return 99; }
  for f in DMBarRect:ap-bar DMBattLayoutButton:ap-batt DMAPTypes:ap-types DMAPHeadsetRec:ap-types DMAirPodsLayoutButton:ap-button DMAirPodsLockLayout:ap-button DMAPItemViews:ap-button DMAPMergeHeadsets:ap-data DMAPPartsCopy:ap-data DMAPReadHeadsets:ap-data \
           DMAPFakeSet:ap-fake DMAPFakeFlag:ap-fake DMAPFakeClass:ap-fake DMAPFakeBarItem:ap-fake DMAPFakeShowItem:ap-fake DMAPBluetoothState:ap-button DMAPButton:ap-button DMAPOwnLetGo:ap-button DMAPOwnGlyph:ap-button DMAirPodsLayoutOwnIcon:ap-button DMImageInkRect:ap-bar kAPItemSeenKey:ap-button; do
    grep -q "${f%%:*}" "$d/${f#*:}.inc" || { [ -n "$q" ] || echo "FAIL  ${f%%:*} was not found"; return 99; }
  done
  for fl in $6; do
    local fam=${fl%-*} dbg=${fl#*-}
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" -DDEBUG=$dbg $([ $fam = t17 ] && echo -DT_STUI) $([ $fam = tn ] && echo -DT_NOBATTID) \
          -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/$fl" test-airpodsmenu.m 2> "$d/cc-$fl.txt" || { [ -n "$q" ] || { head -30 "$d/cc-$fl.txt"; echo "FAIL  the real code did not build ($fl)"; }; return 99; }
    [ -s "$d/cc-$fl.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings ($fl):"; cat "$d/cc-$fl.txt"; r=1; }
    if [ -n "$q" ]; then "$d/$fl" > /dev/null 2>&1 || r=1; else echo "-- $fl"; "$d/$fl" 2>/dev/null || r=1; fi
  done
  return $r
}

# ---- (3) the type table against this Mac's frameworks ----
table() {   # $1 statusbar/AirPodsMenu.h: rc
  python3 -I - "$1" "$W/tbl.m" <<'PY' || return 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'static const DMAPNeedRow kDMAPNeeds\[\] = \{(.*?)\n\};', src, re.S)
rows = re.findall(r'\{ "([^"]+)", "([^"]+)", "([^"]+)", (YES|NO), (kDMAPPart\w+) \}', m.group(1)) if m else []
if len(rows) < 20: sys.exit('the table was not found (%d rows)' % len(rows))
out = ['#import <Foundation/Foundation.h>', '#import <objc/runtime.h>', '#include <dlfcn.h>', 'int main(void) { @autoreleasepool { int bad = 0, n = 0;',
       'const char *fw[] = { "/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", "/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter",',
       '  "/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote" };',
       'for (int i = 0; i < 4; i++) if (!dlopen(fw[i], RTLD_LAZY)) { printf("FAIL  %s not on this Mac\\n", fw[i]); bad++; }',
       'struct { const char *c, *s, *e; int meta; } rows[] = {']
for c, s, e, meta, part in rows: out.append('  { "%s", "%s", "%s", %d },' % (c, s, e, meta == 'YES'))
out += ['};', 'for (unsigned i = 0; i < sizeof rows / sizeof rows[0]; i++) {', '  Class k = objc_getClass(rows[i].c); n++;',
        '  Method m = !k ? NULL : rows[i].meta ? class_getClassMethod(k, sel_registerName(rows[i].s)) : class_getInstanceMethod(k, sel_registerName(rows[i].s));',
        '  const char *t = m ? method_getTypeEncoding(m) : NULL; char want[64]; snprintf(want, sizeof want, "%s", rows[i].e);',
        '#if defined(__x86_64__)', '  for (char *p = want; *p; p++) if (*p == \'B\') *p = \'c\';   /* (BOOL is a char on x86_64) */', '#endif',
        '  if (!t || strcmp(t, want)) { printf("FAIL  %c[%s %s]: %s, the table %s\\n", rows[i].meta ? \'+\' : \'-\', rows[i].c, rows[i].s, t ? t : (k ? "no selector" : "no class"), rows[i].e); bad++; }',
        '}', 'printf("%s  the type table: %d rows, every class and selector on this Mac with the table\'s types\\n", bad ? "FAIL" : "PASS", n);', 'return bad ? 1 : 0; } }']
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
PY
  clang -fobjc-arc -Wall -framework Foundation -o "$W/tbl" "$W/tbl.m" 2> "$W/tbl.txt" || { cat "$W/tbl.txt"; echo "FAIL  the table check did not build"; return 1; }
  "$W/tbl"
}

# ---- (4) the wiring, Settings, the crash guard, the calls never made, debug, privacy ----
pins() {   # $1 StatusBar.x, $2 statusbar/AirPodsMenu.h, $3 common/AirPodsMenu.h, $4 Root.plist, $5 crashmap-rules.txt, $6 quiet: the number that fail
  local X=$1 A=$2 C=$3 P=$4 R=$5 q=$6 n=0
  ok() { [ -n "$q" ] || echo "PASS  $1"; }
  no() { [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); }
  ck() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
  fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
  ck "StatusBar.x: AirPodsMenu.h included right after CC18Tiles.h (it uses nothing of the tiles)" \
     "awk 'index(\$0, \"#include \\\"CC18Tiles.h\\\"\") == 1 { a = NR } index(\$0, \"#include \\\"AirPodsMenu.h\\\"\") == 1 { b = NR } END { exit !(a && b == a + 1) }' $X"
  ck "StatusBar.x: the switch, the button's key and the close paths' noinline declaration with the other status items' globals" \
     "grep -qF 'static BOOL gAirPodsMenuOn = NO;' $X && grep -qF 'static const void *kAirPodsButtonKey = &kAirPodsButtonKey;' $X && grep -qF '__attribute__((noinline)) static void DMAirPodsMenuGone(NSString *why);' $X"
  ck "the button laid out right before the battery's (its comment between), so the battery's is in front and its pins hold" \
     "awk 'index(\$0, \"        DMAirPodsLayoutButton(fg, left, k);\") == 1 { a = NR } index(\$0, \"        DMBattLayoutButton(fg, left, k);\") == 1 { b = NR } END { exit !(a && b == a + 2) }' $X"
  ck "our control: the bar's own region action refused over it (DMPointOverOurControl, between the Wi-Fi and Spotlight buttons)" \
     "fn $X 'static BOOL DMPointOverOurControl(' | grep -qF 'kVPNButtonKey, kWiFiButtonKey, kAirPodsButtonKey, kSpotButtonKey, kClockButtonKey, kBattButtonKey, kCCButtonKey, DM_AM_BUTTONS };'"
  ck "iPadOS 16's first touch after a respring sent again on it (DMBarControlAtScreenPoint; test-touchreplay's two lines whole)" \
     "fn $X 'static UIView *DMBarControlAtScreenPoint(' | grep -qF 'kDispButtonKey, kAudioButtonKey, kSSHButtonKey, kAirPodsButtonKey,' && fn $X 'static UIView *DMBarControlAtScreenPoint(' | grep -qF 'kVPNButtonKey, kWiFiButtonKey, kSpotButtonKey, kClockButtonKey, kBattButtonKey, kCCButtonKey, DM_AM_BUTTONS };'"
  ck "with another menu open, a touch on it switches to the AirPods menu (DMTitleTapSwitch -titleAt: and both openers)" \
     "awk 'index(\$0, \"- (UIButton *)titleAt:(CGPoint)p {\") == 1 { f = 1 } f && index(\$0, \"kAirPodsButtonKey, kBattButtonKey, kCCButtonKey, DM_AM_BUTTONS };\") { ok = 1 } f && /^}/ { exit } END { exit !ok }' $X \
      && [ \$(grep -cF 'else if (b == objc_getAssociatedObject(bfg, kAirPodsButtonKey)) DMOpenAirPodsMenu(b);' $X) = 1 ] && [ \$(grep -cF 'else if (b == objc_getAssociatedObject(fg, kAirPodsButtonKey)) DMOpenAirPodsMenu(b);' $X) = 2 ]"
  ck "every way a menu closes forgets the AirPods menu's state (DMRemoveOverlayNow, DMCloseOverlay)" \
     "fn $X 'static void DMRemoveOverlayNow(' | grep -qF 'DMAirPodsMenuGone(@\"removed\");' && fn $X 'static void DMCloseOverlay(' | grep -qF 'DMAirPodsMenuGone(@\"closed\");'"
  ck "the Lock Screen's layout and copies with no clock: no button (DMAirPodsLockLayout right after DMBattLockLayout)" \
     "fn $X 'static BOOL DMLayoutWithoutClock(' | awk 'index(\$0, \"    DMBattLockLayout(fg);\") == 1 { a = NR } index(\$0, \"    DMAirPodsLockLayout(fg);\") == 1 { b = NR } END { exit !(a && b == a + 1) }'"
  ck "a collapsed copy (narrower than 300 pt) hides it with our other views" "grep -qF 'kWiFiIconKey, kWiFiButtonKey, kBattButtonKey, kAirPodsButtonKey, kCCIconKey, kCCButtonKey, kCCPillKey, kMuteIconKey' $X"
  ck "iPadOS's data updates lay our copy out again with the AirPods Menu on (the item comes, goes, moves: DMStatusIconsUpdated's gate)" \
     "fn $X 'static void DMStatusIconsUpdated(' | grep -qF '    if (!(gVPNActive || gSSHActive || gMuteIconShown || gWiFiMenuOn || gAirPodsMenuOn)) return;'"
  ck "  ... its debug counters (podmenu_probe) inside #if DEBUG only (test-wifirecheck builds it without)" \
     "[ \"\$(ifdebug $X 'gDMIconsUpdatedCalls++;')\" = yes ] && [ \"\$(ifdebug $X 'gDMIconsUpdatedLayouts++;')\" = yes ] && [ \"\$(ifdebug $X 'static unsigned gDMIconsUpdatedCalls = 0')\" = yes ]"
  ck "the pull from the top right starting on it brings Control Center down: the button in DMOurStatusIconsEdge's list (it stands in as its own icon)" \
     "fn $X 'static BOOL DMOurStatusIconsEdge(' | grep -qF '{kWiFiIconKey, kWiFiButtonKey}, {kAirPodsButtonKey, NULL} };'"
  ck "the switch read in DMLoadPrefs, on unless switched off (MSBDAirPodsMenuOn), applied by DMAirPodsApplyPref" \
     "fn $X 'static void DMLoadPrefs(' | grep -qF 'CFPreferencesCopyValue(CFSTR(MSBD_AIRPODS_MENU_KEY), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' \
      && fn $X 'static void DMLoadPrefs(' | grep -qF 'DMAirPodsApplyPref(MSBDAirPodsMenuOn(isBool, isBool && CFBooleanGetValue(apRef)));' && grep -qF '#define MSBD_AIRPODS_MENU_KEY \"airpodsMenu\"' $C"
  ck "menutitles and menucheck know it (one name per key; menucheck opens it)" \
     "grep -qF 'kBattButtonKey, kAirPodsButtonKey, kCCButtonKey, kSpotButtonKey, DM_AM_BUTTONS };' $X && grep -qF '\"wifi\", \"clock\", \"battery\", \"airpods\", \"cc\", \"spotlight\",' $X \
      && grep -qF '_Static_assert(sizeof(names) / sizeof(names[0]) == sizeof(keys) / sizeof(keys[0]), \"menutitles: one name per key\");' $X && grep -qF 'kVPNButtonKey, kWiFiButtonKey, kBattButtonKey, kAirPodsButtonKey, DM_AM_BUTTONS };' $X"
  ck "Settings > Status Bar: AIRPODS_MENU (airpodsMenu, on by default, PSSwitchCell \"AirPods Menu\", prefsChanged) in its group (hidden with the stock status bar, its footer), right after Battery Percentage in Icon" \
     "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; ids=[x.get('id') for x in it]; i=ids.index('AIRPODS_MENU'); s=it[i]; g=it[i-1]; sys.exit(0 if s['key']=='airpodsMenu' and s['default'] is True and s['cell']=='PSSwitchCell' and s['label']=='AirPods Menu' and s['defaults']=='com.besiktasliseba.macstatusbar' and s['PostNotification']=='com.besiktasliseba.macstatusbar/prefsChanged' and g.get('id')=='AIRPODS_MENU_GROUP' and g['cell']=='PSGroupCell' and g.get('stockHides') is True and g['footerText'].startswith('Click or tap the AirPods icon in the status bar') and ids[i-2]=='BATTERY_INSIDE' else 1)\""
  ck "the crash guard: a crash in its code turns AirPods Menu off (its target, a sym rule for its names, a file rule for both headers)" \
     "grep -qx 'target airpodsMenu pref com.besiktasliseba.macstatusbar airpodsMenu 0 1 AirPods Menu|the AirPods menu' $R && grep -qxF 'sym MacStatusBarCore ^_*([0-9]*[-+]\\[)?(DMAP|DMAirPods|MSBDAirPods)[A-Z] airpodsMenu' $R && grep -qx 'file MacStatusBarCore ^AirPodsMenu\\\\.h\$ airpodsMenu' $R"
  ck "  ... the entry points StatusBar.x calls stay functions of their own in a release build (noinline)" \
     "( for f in 'void DMAirPodsLayoutButton(UIView \\*fg, CGFloat left, CGFloat k)' 'void DMAirPodsLockLayout(UIView \\*fg)' 'void DMAirPodsMenuGone(NSString \\*why)' 'void DMAirPodsApplyPref(BOOL on)' 'void DMOpenAirPodsMenu(UIButton \\*btn)'; do grep -q \"^__attribute__((noinline)) static \$f {\" $A || exit 1; done )"
  ck "no hook, no timer; never called: BatteryCenter's shared instance or notification name, BluetoothDevice's battery status struct, the leader device, key-value reads, a shared-instance queue" \
     "! nocomments $A | grep -qE '%hook|%group|NSTimer|batteryStatus:|valueForKey:|logicalLeaderOutputDevice|connectedDevicesDidChangeNotificationName|setSharedInstanceQueue|MSHookMessageEx' \
      && ! nocomments $A | grep -E 'BCBatteryDeviceController' | grep -q 'sharedInstance'"
  ck "its own copies of the checks it needs: nothing of our Control Center's tiles, of the battery menu only DMBattItemClass and DMBattViewShown" \
     "! nocomments $A | grep -q 'DMCCT' && [ \"\$(nocomments $A | grep -oE 'DMBatt[A-Za-z]+' | sort -u | tr '\\n' ' ')\" = 'DMBattItemClass DMBattViewShown ' ]"
  ck "the type check runs outside the layout pass: in the first placement's main-queue block only, with the sources" \
     "[ \$(fn $A '__attribute__((noinline)) static void DMAirPodsLayoutButton(' | grep -c 'DMAPCheck()') = 1 ] && fn $A '__attribute__((noinline)) static void DMAirPodsLayoutButton(' | grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{ DMAPCheck(); DMAPStartSources(); });'"
  ck "the switch off, then on (the check's must-fix 3): off removes BatteryCenter's observer and forgets the records; on adds it again on the next main-queue turn; never from the constructor" \
     "fn $A '__attribute__((noinline)) static void DMAirPodsApplyPref(' | awk 'index(\$0, \"    dispatch_async(dispatch_get_main_queue(), ^{\") == 1 { a = NR } a && index(\$0, \"        if (!gAirPodsMenuOn) { if (gAPMenuOpen) DMCloseOverlay(); DMAPPartsStop(); }\") == 1 { b = NR } b && index(\$0, \"        else if (gAPSourcesStarted) DMAPPartsStart();\") == 1 { c = NR } END { exit !(a && b == a + 1 && c == b + 1) }' \
      && fn $A 'static void DMAPPartsStop(' | grep -qF '    gAPParts = nil;' && fn $A 'static void DMAPPartsStop(' | grep -qF 'removeBatteryDeviceObserver:' \
      && [ \$(nocomments $A | grep -c 'DMAPPartsStart();') = 2 ] && fn $A 'static void DMAPStartSources(' | grep -qF '    DMAPPartsStart();'"
  ck "debug only: every podfake_ and podmenu trigger, DMAPTrigger and its dispatch, and sbfakebt_" \
     "[ \"\$(ifdebug $A '@\"podfake_')\" = yes ] && [ \"\$(ifdebug $A '@\"podmenu')\" = yes ] && [ \"\$(ifdebug $A 'static BOOL DMAPTrigger(NSString *cmd) {')\" = yes ] \
      && [ \"\$(ifdebug $X 'else if ([cmd hasPrefix:@\"pod\"] && DMAPTrigger(cmd)) {}')\" = yes ] && [ \"\$(ifdebug $X 'else if ([cmd hasPrefix:@\"sbfakebt_\"]) {')\" = yes ]"
  ck "  ... the made-up Bluetooth item (1.8.8.1.1) and its writes into iPadOS's data objects, debug only: DMAPFakeBarItem, DMAPFakeSet, the instance variable writes" \
     "[ \"\$(ifdebug $A 'static void DMAPFakeBarItem(NSString *args) {')\" = yes ] && [ \"\$(ifdebug $A 'static NSString *DMAPFakeSet(id o, NSString *key, id obj, long long num, char kind) {')\" = yes ] \
      && [ \"\$(ifdebug $A 'object_setIvarWithStrongDefault(')\" = yes ] && [ \"\$(ifdebug $A 'ivar_getOffset(')\" = yes ] && [ \"\$(ifdebug $A '@\"setOverlayData:\"')\" = yes ] \
      && [ \"\$(ifdebug $X 'DMAPFakeBarItem([cmd substringFromIndex:9]);')\" = yes ] && [ \"\$(ifdebug $A 'static void DMAPFakeBarRecheck(UIView *bar) {')\" = yes ] \
      && [ \"\$(ifdebug $X 'DMAPFakeBarRecheck((UIView *)bar);')\" = yes ]"
  ck "logs never name a device: names, addresses and uids in a log line only through DMWiFiTag or the uid's shape" \
     "! nocomments $A | grep -E 'DMLog\\(|appendFormat:' | grep -E '\\.(name|address|uid)\\b|groupName|matchId' | grep -vE 'DMWiFiTag\\(|DMAPUIDShape\\(|strcmp\\(|[^A-Za-z]e\\.name\\b' | grep -q . \
      && fn $A 'static NSString *DMAPRowsLog(' | grep -qF 'DMWiFiTag(@(r[i].text))'"
  ck "no em or en dash in its code, its test or its Settings row" \
     "! grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $A $C test-airpodsmenu.c test-airpodsmenu.m test-airpodsmenu.sh && ! python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; sys.exit(0 if any(('\\u2014' in str(x) or '\\u2013' in str(x)) for x in it if 'AIRPODS' in str(x.get('id'))) else 1)\""
  return $n
}

# ---- the crash map: what make-crashmap.py resolves AirPodsMenu.h's functions to (sym, then sec by the section a function sits under, then file) ----
crashnames() {   # $1 crashmap-rules.txt, $2 statusbar/AirPodsMenu.h, $3 common/AirPodsMenu.h, $4 quiet: rc
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import re, sys
rules, a, c, quiet = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
sym, sec, fil = [], [], []
for raw in open(rules):
    line = re.split(r'\s+#', raw, 1)[0].strip()
    if not line or line.startswith('#'): continue
    f = line.split()
    if len(f) == 4 and f[0] in ('sym', 'sec', 'file') and f[1] == 'MacStatusBarCore': {'sym': sym, 'sec': sec, 'file': fil}[f[0]].append((re.compile(f[2]), f[3]))
first = lambda rs, s: next((t for rx, t in rs if rx.search(s)), None)
bad = 0
def check(ok, what):
    global bad
    if not quiet: print(('PASS  ' if ok else 'FAIL  ') + what)
    if not ok: bad += 1
heads = []
for path in (a, c):
    for l in open(path, errors='replace'):
        if re.match(r'^(// =+|// -+|%group)', l): heads.append(l.rstrip())
taken = [h for h in heads if first(sec, h)]
check(not taken, 'no section header of the two AirPodsMenu.h matches a sec rule (%d headers)%s' % (len(heads), ' -- taken: ' + '; '.join(taken) if taken else ''))
names = ['_DMAirPodsLayoutButton', '_DMAirPodsLockLayout', '_DMAirPodsMenuGone', '_DMAirPodsApplyPref', '_DMOpenAirPodsMenu', '___DMAirPodsLayoutButton_block_invoke',
         '___DMAPStartSources_block_invoke', '___DMAPStartSources_block_invoke_2', '_DMAPReadHeadsets', '_DMAPPartsCopy', '_DMAPTrigger', '___DMOpenAirPodsMenu_block_invoke',
         '_MSBDAirPodsBlocks', '_MSBDAirPodsMenuRows', '-[DMAPStripRow layoutSubviews]', '-[DMAPBatteryWatch connectedDevicesDidChange:]',
         '___39-[DMAPBatteryWatch connectedDevicesDidChange:]_block_invoke', '-[DMAPHeaderRow refresh]', '_DMAPPartsStart.cold.1']
wrong = ['%s %s' % (n, first(sym, n) or first(fil, 'AirPodsMenu.h')) for n in names if (first(sym, n) or first(fil, 'AirPodsMenu.h')) != 'airpodsMenu']
check(not wrong, 'its functions, blocks and methods resolve to airpodsMenu (DMOpenAirPodsMenu and the methods by the file rule)' + (' -- not: ' + ', '.join(wrong) if wrong else ''))
symonly = ['-[DMAPSectionRow dmRowHeight]', '-[DMAPStripRow dmRowHeight]', '-[DMAPBatteryWatch connectedDevicesDidChange:].cold.1', '___39-[DMAPBatteryWatch connectedDevicesDidChange:]_block_invoke',
           '_DMAPConnect.cold.1', '___DMAirPodsApplyPref_block_invoke.cold.1', '+[DMAPHeadsetRec new]', '_MSBDAirPodsCellsAXText.names']
wrong = ['%s %s' % (n, first(sym, n)) for n in symonly if first(sym, n) != 'airpodsMenu']
check(not wrong, 'methods whose first line is an inlined StatusBar.x helper (the rows\' -dmRowHeight), cold parts (no line) and blocks resolve to airpodsMenu by name alone' + (' -- not: ' + ', '.join(wrong) if wrong else ''))
check(first(sym, '_DMBattLayoutButton') == 'batteryMenu' and first(sym, '_DMWiFiTag') == 'wifiMenu' and first(sym, '_DMCCTCheck') == 'controlcenter',
      "the battery menu's, the Wi-Fi menu's and our Control Center's names keep their own targets")
sys.exit(1 if bad else 0)
PY
}

# ---- the run ----
X0=$R0/statusbar/StatusBar.x; A0=$R0/statusbar/AirPodsMenu.h; C0=$R0/common/AirPodsMenu.h; B0=$R0/statusbar/BatteryMenu.h
P0=$R0/statusbar/macstatusbarprefs/Resources/Root.plist; RR0=$R0/tools/crashmap-rules.txt
echo "== (1) the rules (plain C)"
plainc "$C0" "$W/c" "" || fails=1
echo "== (2) the Objective-C side (Mac Catalyst, real code cut out)"
harness "$X0" "$A0" "$B0" "$W/h" "" "t-0 t-1 t17-0 t17-1 tn-0" || fails=1
echo "== (3) the type table against this Mac's frameworks"
if [ -f "$A0" ]; then table "$A0" || fails=1; else echo "FAIL  no statusbar/AirPodsMenu.h"; fails=1; fi
echo "== (4) wiring, Settings, crash guard, calls never made, debug, privacy"
pins "$X0" "$A0" "$C0" "$P0" "$RR0" "" || fails=1
crashnames "$RR0" "$A0" "$C0" "" || { [ -f "$A0" ] || echo "FAIL  no statusbar/AirPodsMenu.h"; fails=1; }
mkdir -p "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle" "$W/lib/PreferenceLoader/Preferences"; cp "$P0" "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle/Root.plist"
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
        MTIEntry *e = MTIMatch(MTIBuild(c), @"airpods menu", 10).firstObject;
        BOOL ok = e && [e.title isEqualToString:@"AirPods Menu"] && [e.crumb isEqualToString:@"Status Bar"] && [MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_STATUS_BAR#AIRPODS_MENU"];
        printf("%s  the switch in the Settings search: \"airpods menu\" finds %s (%s, %s)\n", ok ? "PASS" : "FAIL", e ? e.title.UTF8String : "nothing", e ? e.crumb.UTF8String : "-", e ? MTIPrefsURL(e.uid).UTF8String : "-");
        return ok ? 0 : 1;
    }
}
OBJC
clang -fobjc-arc -Wall -Wno-unused-function -I"$R0/common" -framework Foundation -o "$W/tidx" "$W/tidx.m" && "$W/tidx" "$W/lib" || fails=1

if [ -z "$AP_ROOT" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mc() {   # $1 what, $2 perl expression on common/AirPodsMenu.h: the rules must fail
    local d="$W/mc$((++k))"; mkdir -p "$d"; perl -0777 -pe "$2" "$C0" > "$d/h"
    cmp -s "$d/h" "$C0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    if plainc "$d/h" "$d/w" q; then echo "FAIL  not caught: $1"; fails=1; else echo "PASS  caught: $1"; fi
  }
  mh() {   # $1 what, $2 perl expression on statusbar/AirPodsMenu.h: the Objective-C side must fail
    local d="$W/mh$((++k))"; mkdir -p "$d"; perl -0777 -pe "$2" "$A0" > "$d/AirPodsMenu.h"
    cmp -s "$d/AirPodsMenu.h" "$A0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    harness "$X0" "$d/AirPodsMenu.h" "$B0" "$d/w" q "t-0"; local r=$?
    if [ $r = 0 ]; then echo "FAIL  not caught: $1"; fails=1; elif [ $r = 99 ]; then echo "FAIL  made-to-fail copy \"$1\": did not build"; fails=1; else echo "PASS  caught: $1"; fi
  }
  mp() {   # $1 what, $2 which file (X A C P R), $3 perl expression: the site checks or the crash names must fail
    local d="$W/mp$((++k))" x=$X0 a=$A0 c=$C0 p=$P0 r=$RR0 src; mkdir -p "$d"
    case $2 in X) src=$X0; x=$d/f;; A) src=$A0; a=$d/f;; C) src=$C0; c=$d/f;; P) src=$P0; p=$d/f;; R) src=$RR0; r=$d/f;; esac
    perl -0777 -pe "$3" "$src" > "$d/f"
    cmp -s "$d/f" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    pins "$x" "$a" "$c" "$p" "$r" q; local n=$?
    crashnames "$r" "$a" "$c" q 2>/dev/null || n=$((n + 1))
    if [ $n -gt 0 ]; then echo "PASS  caught: $1 ($n)"; else echo "FAIL  not caught: $1"; fails=1; fi
  }
  # the rules
  mc "span: over the battery's button" 's/if \(batt\.has && batt\.lead < batt\.trail\) \{/if (0) {/'
  mc "span: past the middle of the gap after the item" 's/if \(next\.has\) \{ double mid = \(trail \+ next\.lead\) \/ 2\.0; if \(b > mid\) b = mid; \}//'
  mc "span: before the floor (our Wi-Fi icon's area)" 's/    if \(a < floor\) a = floor;\n//'
  mc "match: by name only (no product-id fallback)" 's/    if \(h && h->productId\) \{/    if (0) {/'
  mc "match: the Case not joined by matchIdentifier" 's/if \(!p\[one\]\.matchId\[0\]\) \{/if (1) {/'
  mc "match: an ambiguous name taken (the first candidate's group)" 's/for \(int i = 1; i < nc; i\+\+\) if \(strcmp\(p\[cand\[i\]\]\.matchId, p\[cand\[0\]\]\.matchId\)\) return -1;//'
  mc "match: the iPad's own battery counted" 's/if \(!p\[i\]\.internal && !strcmp\(p\[i\]\.matchId, p\[one\]\.matchId\)\)/if (!strcmp(p[i].matchId, p[one].matchId))/'
  mc "cells: parts 3 read as Left (no merged cell)" 's/int k = \(bits & 3ULL\) == 3ULL \? kMSBDAPCellBoth : /int k = /'
  mc "modes: in the list's order, not Control Center's" 's/for \(int i = 0; i < kMSBDAPModes; i\+\+\) if \(mask & \(1u << i\)\)/for (int i = kMSBDAPModes - 1; i >= 0; i--) if (mask \& (1u << i))/'
  mc "uid: the whole uid equal to the address" 's/!strncasecmp\(uid, address, 17\)/!strcasecmp(uid, address)/'
  mc "uid: the one Bluetooth output taken though it is another device's address" 's/    if \(address && address\[0\] && MSBDAirPodsLooksLikeAddress\(r\[found\]\.uid\)\) return -1;[^\n]*\n//'
  mc "percent: a level over 100 shown" 's/if \(p < 0 \|\| p > 100\) snprintf\(buf, n, "--"\);/if (p < 0) snprintf(buf, n, "--");/'
  mc "rows: no Connect after a drop" 's/if \(b->canConnect\) \{ MSBDAPAddRow\(rows, &n, max, kMSBDAPRowSeparator, i, NULL\); MSBDAPAddRow\(rows, &n, max, kMSBDAPRowConnect, i, "Connect"\); \}//'
  mc "rows: the strip shown when they dropped" 's/            continue;\n        \}\n        if \(b->ncells/        }\n        if (b->ncells/'
  mc "signature: the cells' levels left out" 's/ MSBD_AP_MIX\(r->cells\[c\]\.percent\);//'
  mc "switch: never set reads off" 's/return isBool \? value != 0 : 1;/return isBool ? value != 0 : 0;/'
  mc "item: the glyph alone taken for a Bluetooth indicator (1.8.8.1's rule: the level asked)" 's/return viewsShown > 0 && \(levelShown \|\| !stateRead \|\| state == MSBD_AP_BT_HEADPHONES\);/return viewsShown > 0 \&\& levelShown;/'
  mc "item: any Bluetooth indicator taken for headphones" 's/ \|\| !stateRead \|\| state == MSBD_AP_BT_HEADPHONES\);/ || 1);/'
  mc "list: headphones with no battery level left out (1.8.8.1's rule)" 's/return connected && \(reportsLevel \|\| MSBDAirPodsIsHeadphonesType\(typeRead, type\)\);/return connected \&\& reportsLevel;/'
  mc "list: any type taken" 's/return typeRead && \(type == MSBD_AP_BT_TYPE_HEADSET \|\| type == MSBD_AP_BT_TYPE_HEADPHONES\);/return 1;/'
  # the Objective-C side
  mh "a button for any Bluetooth glyph (the bar's state not asked)" 's/DMAPBluetoothState\(fg, &stateRead\) : MSBD_AP_BT_HEADPHONES;/MSBD_AP_BT_HEADPHONES : MSBD_AP_BT_HEADPHONES;/'
  mh "the glyph alone given no button (1.8.8.1's gate: the level asked)" 's/if \(!MSBDAirPodsItemIsHeadphones\(\(int\)views\.count, battShown, stateRead, state\)\)/if (!battShown || !views.count)/'
  mh "the bar's own data not read (the state from the wrong object)" 's/id e = DMAPObj\(DMAPObj\(fg\.superview, sData\), sEntry\);/id e = DMAPObj(DMAPObj(fg, sData), sEntry);/'
  mh "the battery's covered set used for the AirPods views (DMBattCoverAX)" 's/    DMAPCoverAX\(fg, views, YES\);/    DMBattCoverAX(fg, views, YES);/'
  mh "neighbours from every region, not the item's own" 's/        if \(mine\) \[others addObjectsFromArray:rest\];/        [others addObjectsFromArray:rest];/'
  mh "the battery's button not stood clear of" 's/if \(gBattMenuOn && battViews\.count\) \{/if (0) {/'
  mh "a set that went dropped from the open menu (no Not Connected)" 's/        else was\.connected = NO;/        else { [gAPMenuHeadsets removeObjectAtIndex:i]; i--; }/'
  mh "BatteryCenter's level read without its type" 's/ \|\| !DMAPTypes\(x, sPct, "q16\@0:8"\)//'
  mh "Bluetooth devices that are neither headphones nor report a level taken" 's/if \(!MSBDAirPodsListsDevice\(\(\(BOOL \(\*\)\(id, SEL\)\)objc_msgSend\)\(d, sIsConn\), level, typeRead, type\)\) continue;/if (!((BOOL (*)(id, SEL))objc_msgSend)(d, sIsConn)) continue;/'
  mh "headphones by type left out (the type not asked)" 's/BOOL typeRead = DMAPTypes\(d, sType, "i16\@0:8"\) \|\| DMAPTypes\(d, sType, "I16\@0:8"\);/BOOL typeRead = NO;/'
  mh "a level read for a device that reports none" 's/h\.level = level \? \(\(int \(\*\)\(id, SEL\)\)objc_msgSend\)\(d, sLevel\) : -1;/h.level = ((int (*)(id, SEL))objc_msgSend)(d, sLevel);/'
  mh "the iPad's own battery kept" 's/if \(\(\(BOOL \(\*\)\(id, SEL\)\)objc_msgSend\)\(x, sInt\)\) \{ \(\*internal\)\+\+; continue; \}/if (((BOOL (*)(id, SEL))objc_msgSend)(x, sInt)) (*internal)++;/'
  mh "the switch not asked by the layout" 's/if \(!gAirPodsMenuOn \|\| !\(left < CGFLOAT_MAX\)/if (!(left < CGFLOAT_MAX)/'
  mhd() {   # $1 what, $2 perl expression on statusbar/AirPodsMenu.h: the DEBUG side (the made-up Bluetooth item, 1.8.8.1.1) must fail
    local d="$W/mh$((++k))"; mkdir -p "$d"; perl -0777 -pe "$2" "$A0" > "$d/AirPodsMenu.h"
    cmp -s "$d/AirPodsMenu.h" "$A0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    harness "$X0" "$d/AirPodsMenu.h" "$B0" "$d/w" q "t17-1"; local r=$?
    if [ $r = 0 ]; then echo "FAIL  not caught: $1"; fails=1; elif [ $r = 99 ]; then echo "FAIL  made-to-fail copy \"$1\": did not build"; fails=1; else echo "PASS  caught: $1"; fi
  }
  mhd "the fake: 17/18's immutable data class taken for the overlay (no mutable sibling)" 's/return m && \[m isSubclassOfClass:c\] && \[m instancesRespondToSelector:needs\] \? m : c;/return c;/'
  mhd "the fake: the glyph alone given a level" 's/DMAPFakeFlag\(b, \@"enabled", level\)/DMAPFakeFlag(b, \@"enabled", YES)/'
  mhd "the fake: the bar's own overlay not given back" 's/kept\.firstObject == \[NSNull null\] \? nil : kept\.firstObject/nil/'
  mhd "the fake: 17/18's entries left without their values (no instance variable writes)" 's/    Ivar iv = class_getInstanceVariable\(object_getClass\(o\), \[\@"_" stringByAppendingString:key\]\.UTF8String\);/    Ivar iv = NULL;/'
  mhd "the fake: the made-up headphones' shape not followed" 's/DMAPFakeBarItem\(gAPFakeGlyphOnly \? \@"2_-1" :/DMAPFakeBarItem(0 ? \@"2_-1" :/'
  mhd "the fake: not put back where iPadOS replaced the bar's overlay" 's/if \(DMAPFakeMerged\(bar, &st, &batt\) && st == want && batt == \(pct >= 0\)\) return;/return;/'
  mhd "the fake: put back over a fresh overlay (iPadOS's own entries lost)" 's/id data = \[base respondsToSelector:sBT\] \? base : \[D new\]/id data = [D new]/'
  # the wiring and the rest
  mp "the key out of DMPointOverOurControl" X 's/kWiFiButtonKey, kAirPodsButtonKey, kSpotButtonKey, kClockButtonKey/kWiFiButtonKey, kSpotButtonKey, kClockButtonKey/'
  mp "the key out of DMBarControlAtScreenPoint" X 's/kAudioButtonKey, kSSHButtonKey, kAirPodsButtonKey,/kAudioButtonKey, kSSHButtonKey,/'
  mp "the key out of DMTitleTapSwitch -titleAt:" X 's/kAirPodsButtonKey, kBattButtonKey, kCCButtonKey, DM_AM_BUTTONS \};/kBattButtonKey, kCCButtonKey, DM_AM_BUTTONS };/'
  mp "an opener without the AirPods menu" X 's/        else if \(b == objc_getAssociatedObject\(bfg, kAirPodsButtonKey\)\) DMOpenAirPodsMenu\(b\);\n//'
  mp "a close path that keeps its state" X 's/    DMAirPodsMenuGone\(\@"closed"\);\n//'
  mp "no lock layout" X 's/    DMAirPodsLockLayout\(fg\);[^\n]*\n//'
  mp "the narrow copies' list without it" X 's/kBattButtonKey, kAirPodsButtonKey, kCCIconKey,/kBattButtonKey, kCCIconKey,/'
  mp "the data updates' gate without the switch" X 's/ \|\| gWiFiMenuOn \|\| gAirPodsMenuOn\)\) return;/ || gWiFiMenuOn)) return;/'
  mp "the pull region without the button" X 's/, \{kAirPodsButtonKey, NULL\} \};/ };/'
  mp "laid out after the battery's button" X 's/(        DMAirPodsLayoutButton\(fg, left, k\);\n)([^\n]*\n        DMBattLayoutButton\(fg, left, k\);\n)/$2$1/'
  mp "the switch not read at the start" X 's/        DMAirPodsApplyPref\(MSBDAirPodsMenuOn\(isBool, isBool && CFBooleanGetValue\(apRef\)\)\);\n//'
  mp "Settings' row off by default" P 's/(<key>default<\/key>\n\t\t\t<)true(\/>\n\t\t\t<key>defaults<\/key>\n\t\t\t<string>com.besiktasliseba.macstatusbar<\/string>\n\t\t\t<key>id<\/key>\n\t\t\t<string>AIRPODS_MENU<\/string>)/$1false$2/'
  mp "Settings' group shown with the stock status bar" P 's/(<string>AIRPODS_MENU_GROUP<\/string>\n\t\t\t<key>stockHides<\/key>\n\t\t\t<)true/$1false/'
  mp "the crash map's sym rule out" R 's/sym MacStatusBarCore \^_\*\(\[0-9\]\*\[-\+\]\\\[\)\?\(DMAP\|DMAirPods\|MSBDAirPods\)\[A-Z\] airpodsMenu\n//'
  mp "the crash map's sym rule without the methods (their first line can be StatusBar.x's)" R 's/\^_\*\(\[0-9\]\*\[-\+\]\\\[\)\?\(DMAP/^_*(DMAP/'
  mp "the crash map's target out" R 's/target airpodsMenu pref [^\n]*\n//'
  mp "a section header a sec rule takes" A 's/\/\/ ---- the menu ----/\/\/ ---- the menu (Aerial) ----/'
  mp "noinline off the layout entry point" A 's/__attribute__\(\(noinline\)\) static void DMAirPodsLayoutButton\(/static void DMAirPodsLayoutButton(/'
  mp "a timer while the menu is open" A 's/(static BOOL gAPRebuildPending = NO;)/$1\nstatic NSTimer *gAPTimer = nil;/'
  mp "BatteryCenter's shared instance asked" A 's/(Class c = objc_getClass\("BCBatteryDeviceController"\);)/$1 id sh = [(id)objc_getClass("BCBatteryDeviceController") sharedInstance]; (void)sh;/'
  mp "the type check in the layout pass" A 's/(    BOOL rtl = DMBarRTL\(fg\);\n    CGRect u = DMAPUnion)/    DMAPCheck();\n$1/'
  mp "back on without BatteryCenter's observer (must-fix 3)" A 's/        else if \(gAPSourcesStarted\) DMAPPartsStart\(\);[^\n]*\n//'
  mp "switched off with the records kept" A 's/    gAPParts = nil;\n    if \(!gAPBatteryWatch\) return;/    if (!gAPBatteryWatch) return;/'
  mp "a borrowed Control Center tile helper" A 's/DMAPFrameworkString\(DMAP_MP, "MPAVRouteDidChangeNotification"\)/DMCCTFrameworkString(DMAP_MP, "MPAVRouteDidChangeNotification")/'
  mp "a device named in a log" A 's/DMLog\(\[NSString stringWithFormat:\@"\[podmenu\] headphones %\@: %\@", DMWiFiTag\(h\.name\)/DMLog([NSString stringWithFormat:@"[podmenu] headphones %@: %@", h.name/'
  mp "a test trigger in a release build" A 's/\n#endif\n\z/\n#endif\nstatic NSString *kAPLeft = \@"podfake_left";\n/'
  mp "menutitles without its name" X 's/"battery", "airpods", "cc"/"battery", "cc"/'
fi
[ $fails = 0 ] && echo "test-airpodsmenu: all pass" || { echo "test-airpodsmenu: FAILED"; exit 1; }
