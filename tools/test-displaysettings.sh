#!/bin/bash
# Mac test of Settings > Desktop > Displays (1.8.7 commit 12; plans/design-1.8.7-displays.md section 6): the store and the one writer against the Mac's
# own cfprefsd in scratch domains (test-displaysettings.m), then the sites -- the Desktop page's Displays group (last, from the registry, greyed and
# iPadOS 15 states, Forget), the display's page (the table's rows, the same writer as the window), the search's row -- and made-to-fail copies.
set -e
cd "$(dirname "$0")"
P=com.besiktasliseba.msbdtest.displays.$$
W=$(mktemp -d)
cleanpf() { for d in "$P" "$P.msb" "$P.dock"; do defaults delete "$d" >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$d.plist"; done; }
trap 'rm -rf "$W"; cleanpf' EXIT
build() {   # <out> <store header dir>: the ObjC test with the scratch domains
  clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -I"$2" -DMSBD_DISP_DOMAIN="\"$P\"" -DMSBD_DISP_MSB_DOMAIN="\"$P.msb\"" -DMSBD_DISP_DOCK_DOMAIN="\"$P.dock\"" \
    -DMSBD_GUARD_RECENT="\"$W/recent.txt\"" -o "$1" "$3"
}
build "$W/tds" ../common test-displaysettings.m
cleanpf; "$W/tds"; cleanpf
fails=0
check() { if (eval "$2"); then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
M=../statusbar/macstatusbarprefs/MSBRootListController.m; DP=../statusbar/macstatusbarprefs/Resources/Desktop.plist; R=../common/DisplayRows.h; D=../statusbar/DisplaySettings.h
python3 -I - "$DP" "$R" > "$W/plist" <<'PY'
import plistlib,re,sys
items=plistlib.load(open(sys.argv[1],'rb'))['items']
foot=re.search(r'#define MSBD_DISP_TEXT_GROUP +"([^"]*)"', open(sys.argv[2]).read()).group(1)
g,r=items[-2],items[-1]
print('last-group' if g.get('cell')=='PSGroupCell' and g.get('id')=='DISPLAYS_GROUP' and g.get('label')=='Displays' else 'no-group')
print('footer-same' if g.get('footerText')==foot else 'footer-differs')
print('row' if r.get('id')=='DISPLAY_SETTINGS' and r.get('label')=='Display Settings' and r.get('detail')=='MSBDisplayListController' else 'no-row')
PY
check "Desktop.plist: the Displays group at the very bottom, its footer the table's words, the placeholder row the search indexes (Displays, Display Settings)" \
  "[ \"\$(cat \$W/plist | tr '\n' ' ')\" = 'last-group footer-same row ' ]"
check "the Desktop page: the placeholder becomes one row per remembered display (the registry), the group's first row keeps the search's id" \
  "fn '- (NSArray *)specifiers {' <(awk '/^@implementation MSBDesktopListController/{f=1} f' $M) && grep -q 'NSArray \*rows = MSBDisplaysGroup(self, group);' \$W/fn \
   && fn 'static NSArray<PSSpecifier *> *MSBDisplaysGroup(PSListController *target, PSSpecifier *group) {' $M && grep -q 'for (NSString \*d in MSBDDispStoreRemembered(all))\|for (NSString \*d in remembered) {' \$W/fn \
   && grep -q 'setProperty:@\"DISPLAY_SETTINGS\" forKey:@\"id\"' \$W/fn"
check "  ... a connected display's row opens its page, enabled only on 16+ with Display Settings on; one not connected: Not Connected and Forget This Display" \
  "fn 'static NSArray<PSSpecifier *> *MSBDisplaysGroup(PSListController *target, PSSpecifier *group) {' $M \
   && grep -q 'detail:on ? NSClassFromString(@\"MSBDisplayListController\") : Nil cell:on ? PSLinkListCell : PSTitleValueCell' \$W/fn && grep -q 'setProperty:@(on && layerOn && !os15) forKey:@\"enabled\"' \$W/fn \
   && grep -q 'if (!on) {' \$W/fn && grep -q 'forget.buttonAction = @selector(msb_forgetDisplay:);' \$W/fn \
   && grep -q '@MSBD_DISP_TEXT_NOT_CONNECTED' $M"
check "  ... the footer: no display connected says so, iPadOS 15 the mirror's words, Display Settings off why; none remembered: only the switch (no greyed placeholder)" \
  "fn 'static NSArray<PSSpecifier *> *MSBDisplaysGroup(PSListController *target, PSSpecifier *group) {' $M && grep -q 'else if (!connected.count) \[footer appendFormat:@\" %s\", MSBD_DISP_TEXT_NONE\];' \$W/fn \
   && grep -q 'else if (os15) \[footer appendFormat:@\" %s\", MSBD_DISP_TEXT_MIRROR\];' \$W/fn && grep -q 'if (!layerOn) \[footer setString:@MSBD_DISP_TEXT_OFF\];' \$W/fn \
   && ! grep -q 'PSStaticTextCell' \$W/fn"
check "the displays domain's switches in the group (the crash guard's targets: a step that set one off is switched back on here): Display Settings first (the search lands on it), More Space while off or with a display listing two scales" \
  "fn 'static NSArray<PSSpecifier *> *MSBDisplaysGroup(PSListController *target, PSSpecifier *group) {' $M \
   && grep -q 'preferenceSpecifierNamed:@MSBD_DISP_TEXT_SWITCH target:target set:@selector(msb_setDisplaySwitch:specifier:) get:@selector(msb_displaySwitch:) detail:Nil cell:PSSwitchCell' \$W/fn \
   && grep -q '\[master setProperty:@\"DISPLAY_SETTINGS\" forKey:@\"id\"\];' \$W/fn && grep -q 'if (MSBDDispStoreScaleSwitchShown(all)) {' \$W/fn && grep -q 'setProperty:@MSBD_DISP_SCALE_SWITCH_KEY forKey:@\"msbdSwitch\"' \$W/fn \
   && awk '/\[rows addObject:master\];/{a=NR} /for \(NSString \*d in remembered\) \{/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && fn '- (void)msb_setDisplaySwitch:(id)value specifier:(PSSpecifier *)spec {' $M && grep -q 'if (!MSBDDispStoreSetSwitch(key.UTF8String, on)) return;' \$W/fn && grep -q 'MSBDNoteSwitch(@MSBD_DISP_DOMAIN, key, spec.name, was, on);' \$W/fn \
   && grep -q '#define MSBD_DISP_TEXT_SWITCH     \"Display Settings\"' ../common/DisplayRows.h && grep -q '#define MSBD_DISP_TEXT_SCALE_SWITCH \"More Space\"' ../common/DisplayRows.h \
   && grep -q '^target displaySettings pref com.besiktasliseba.macstatusbar.displays displaySettings 0 1 Display Settings|' crashmap-rules.txt && grep -q '^target displayScale pref com.besiktasliseba.macstatusbar.displays displayScale 0 1 More Space|' crashmap-rules.txt"
check "  ... Forget asks first, then the store forgets (never a connected display); the page follows the displays domain" \
  "fn '- (void)msb_forgetDisplay:(PSSpecifier *)spec {' $M && grep -q 'MSBDDispStoreForget(d);' \$W/fn && grep -q 'UIAlertActionStyleDestructive' \$W/fn \
   && grep -q 'notify_register_dispatch(MSBD_DISP_NOTIFY, &_msbDispToken,' $M"
check "the display's page: the table's rows by its rules, as the window's (MSBDDispRowShown / MSBDDispRowEnabled, the same conditions as SpringBoard reads them)" \
  "fn '- (NSArray *)specifiers {' <(awk '/^@implementation MSBDisplayListController/{f=1} f' $M) && grep -q 'if (!MSBDDispRowShown(r, &ctx)) continue;' \$W/fn \
   && grep -q 'BOOL enabled = MSBDDispRowEnabled(r, &ctx, connected, layerOn);' \$W/fn && grep -q 'for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {' \$W/fn \
   && fn 'static MSBDDispCtx MSBDispCtxFor(NSDictionary *all, NSDictionary *info) {' $M && grep -q 'c.extended = c.osMajor >= 16 && \[info\[@\"desktop\"\] isKindOfClass:\[NSNumber class\]\] && \[info\[@\"desktop\"\] boolValue\];' \$W/fn \
   && grep -q 'c.ourDock = MSBDDispStoreOurDock(own.dockLine);' \$W/fn && grep -q 'c.smEngine = own.stageManagerEngine;' \$W/fn && grep -q 'c.finder = own.finder;' \$W/fn"
check "the window and Settings write the same keys: Settings only through the store's writer, Use iPad Settings and Forget; the window through DMDispWrite, which is that writer" \
  "! grep -n 'CFPreferencesSet' $M | grep -i 'disp' | grep -q . && fn '- (void)msb_set:(id)value specifier:(PSSpecifier *)spec {' $M && grep -q 'MSBDDispStoreWrite(_display, r->part, r->key, stored, was, @(r->title));' \$W/fn \
   && fn '- (void)msb_reset:(PSSpecifier *)spec {' $M && grep -q 'MSBDDispStoreWrite(_display, r->part, r->key, nil, was, @(r->title));' \$W/fn \
   && grep -q 'MSBDDispStoreUseIPad(self->_display);' $M && grep -q 'BOOL ok = DMDispWrite(_display, r->part, r->key, stored, was, @(r->title));' $D \
   && grep -q 'NSString \*fk = MSBDDispStoreWrite(display, part, key, value, wasOn, title);' ../statusbar/DisplayPrefs.h"
check "  ... a slider's title in its group's header and the display's name and mode on top, as the groups' names (a slider cell shows none; a \"label\" property is not a header: found on the A12Z with d17 and d18)" \
  "grep -q 'if (r->kind == kMSBDRowSlider) g.name = @(r->title);' $M && grep -q 'top.name = mode ? ' $M && ! grep -q 'forKey:@\"label\"' $M"
check "  ... a changed row says so with its reset (the Trash's: Default: On); Use iPad Settings asks first" \
  "grep -q 'Changed for this display. %@.' $M && grep -q 'NSString \*back = hasDef ? @MSBD_DISP_TEXT_DEFAULT_ON' $M && fn '- (void)msb_useIPad:(PSSpecifier *)spec {' $M && grep -q 'alertControllerWithTitle:@MSBD_DISP_TEXT_USE_IPAD message:@MSBD_DISP_TEXT_USE_IPAD_ASK' \$W/fn"
check "  ... the page follows the window and the iPad's settings live, and leaves when its display goes" \
  "fn '- (void)viewDidLoad {' <(awk '/^@implementation MSBDisplayListController/{f=1} f' $M) && grep -q 'MSBD_DISP_NOTIFY, \"com.besiktasliseba.macstatusbar/prefsChanged\", \"com.besiktasliseba.dockmagnification/prefsChanged\"' \$W/fn \
   && fn '- (void)msb_follow {' $M && grep -q 'popViewControllerAnimated:YES' \$W/fn"
check "Settings: no screens and no private display calls" "! awk '/^static MSBDDispCtx MSBDispCtxFor/{f=1} f' $M | grep -q 'UIScreen\|CADisplay\|SBSExternalDisplayService'"
check "\"connected\" let go wherever SpringBoard's part does not keep it: Mac Status Bar off, the stock bar (%ctor), Display Settings off at the start, switched off, or when the registry would run" \
  "grep -q 'if (!DMCtorSkip(\"dispprefs\")) MSBDDispStoreDropConnected();   // (1.8.7: the displays' ../statusbar/StatusBar.x \
   && grep -q 'DMPrewarmBlockOff(@\"Use Stock Status Bar\"); if (!DMCtorSkip(\"dispprefs\")) MSBDDispStoreDropConnected(); if (!DMCtorSkip(\"ccstyle\"))' ../statusbar/StatusBar.x \
   && fn 'static void DMDispInit(void) {' ../statusbar/DisplayPrefs.h && grep -q 'MSBDDispStoreDropConnected() ? @\"; the connected list let go\"' \$W/fn \
   && grep -q 'if (was && !gDMDispLayerOn) DMDispRegistryUpdate(@\"Display Settings switched off\");' \$W/fn \
   && fn '__attribute__((noinline)) static void DMDispRegistryUpdate(NSString *why) {' ../statusbar/DisplayPrefs.h \
   && awk '/if \(!gDMDispLayerOn\) \{/{a=NR} /BOOL dropped = MSBDDispStoreDropConnected\(\);/{b=NR} /^        return;$/{if(!c)c=NR} END{exit !(a && b > a && c > b)}' \$W/fn"
# Made to fail: the store with one thing broken must fail the ObjC test.
mutant() {
  local M2="$W/m-$1"; mkdir -p "$M2"; cp ../common/*.h "$M2/"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' \
    ../common/DisplayRowStore.h "$M2/DisplayRowStore.h" "$2" "$3" || return 1
  cp test-displaysettings.m "$M2/t.m"; sed -i '' 's|#include "../common/DisplayRowStore.h"|#include "DisplayRowStore.h"|' "$M2/t.m"
  build "$M2/t" "$M2" "$M2/t.m" 2>/dev/null || return 1
  cleanpf; ! "$M2/t" > "$M2/out"; local r=$?; cleanpf; return $r
}
check "made to fail: an override of the wrong form taken" "mutant form '            return isNum && MSBDDispChoiceIndexNum(r, num) >= 0 ? @((int)num) : nil;' '            return isNum ? @((int)num) : nil;'"
check "made to fail: the display default ignored (the TV's Trash follows the iPad's off)" "mutant def '    if (f == kMSBDDispFromDefault) return @(def != 0);' ''"
check "made to fail: Use iPad Settings deletes another display's overrides too" "mutant useipad '|| strcmp(d, display.UTF8String) != 0) return NULL;' ') return NULL;'"
check "made to fail: Use iPad Settings deletes More Space's crash-revert record (any key of the display taken as its own)" "mutant pending '    return r && r->kind != kMSBDRowScale ? r : NULL;' '    return r ?: &kMSBDDispRows[0];'"
check "made to fail: the Dock rows with the Dock's own switch off" "mutant ourdock 'static inline BOOL MSBDDispDockSwitchOn(id v) { return !(MSBDDispIsBool(v) && ![v boolValue]); }' 'static inline BOOL MSBDDispDockSwitchOn(id v) { return YES; }'"
check "made to fail: Forget takes a connected display" "mutant forget '    if ([MSBDDispStoreConnected(all) containsObject:display]) return -1;' ''"
check "made to fail: a switch turned on not noted for the crash guard" "mutant note 'if ((isSwitch || !value) && on != wasOn) MSBDDispNoteRecent' 'if (0) MSBDDispNoteRecent'"
check "made to fail: a switch read as a numeric choice (the guard's false for Menu Bar Size taken as a size)" "mutant small 'BOOL isBool = MSBDDispIsBool(v), isNum = !isBool && [v isKindOfClass:[NSNumber class]];' 'BOOL isBool = MSBDDispIsBool(v), isNum = [v isKindOfClass:[NSNumber class]];'"
check "made to fail: More Space's switch hidden while off (no way back after the guard's step)" "mutant scaleswitch '    if (!MSBDDispStoreSwitchOn(all, MSBD_DISP_SCALE_SWITCH_KEY)) return YES;' ''"
check "made to fail: the connected list kept where nothing keeps it" "mutant connected 'BOOL there = v && (CFGetTypeID(v) != CFArrayGetTypeID() || CFArrayGetCount((CFArrayRef)v) > 0);' 'BOOL there = NO;'"
[ $fails = 0 ] && echo "test-displaysettings: wiring checks pass" || { echo "test-displaysettings: wiring checks FAILED"; exit 1; }
