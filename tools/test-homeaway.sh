#!/bin/bash
# Mac test of Home Minimizes Windows (1.7.9): the plain C (statusbar/HomeAway.h, test-homeaway.c), the switch in Settings and its search, and the
# wiring -- the gesture's lift and the Home button's press (MacSwitcher.h, MacSwitcherButton.h), our own simulated press (StatusBar.x DMMinimize),
# the App Switcher's tap beside its cards, and the Stage Manager engine's Home rule (SMHome.h; the rule itself: test-smhomerule.sh).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -std=c11 -O1 -Wall -Werror -o "$W/tha" test-homeaway.c && "$W/tha" || fails=1
M=../statusbar/MacSwitcher.h; Bt=../statusbar/MacSwitcherButton.h; H=../statusbar/SMHome.h; X=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/Resources/Windows.plist
# ---- the switch in the Settings search: the index (common/TweakIndex.h) of the real Windows & Multitasking page, searched as Settings searches it
mkdir -p "$W/b"; cp "$P" "$W/b/Windows.plist"
cat > "$W/tidx.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import "TweakIndex.h"
int main(int argc, char **argv) {
    @autoreleasepool {
        MTIConfig *c = [MTIConfig new];
        c.plDirs = @[]; c.bundleDirs = @[]; c.supportDir = @(argv[1]); c.languages = @[@"en-US"]; c.cfVersion = 1953.1; c.maxPerPane = 400; c.maxTotal = 6000;
        c.own = @[@{@"id": @"MAC_WINDOWS", @"title": @"Windows & Multitasking", @"bundle": @(argv[1]), @"plist": @"Windows", @"icon": @"windows"}];
        int bad = 0;
        for (NSString *q in @[@"home minimizes", @"minimize"]) {
            MTIEntry *e = MTIMatch(MTIBuild(c), q, 10).firstObject;
            BOOL ok = e && [e.title isEqualToString:@"Home Minimizes Windows"] && [e.crumb isEqualToString:@"Windows & Multitasking"]
                && [MTIPrefsURL(e.uid) isEqualToString:@"prefs:root=MAC_WINDOWS#HOME_MINIMIZES_WINDOWS"];
            printf("%s  the switch in the Settings search: \"%s\" finds %s (%s, %s)\n", ok ? "PASS" : "FAIL", q.UTF8String, e ? e.title.UTF8String : "nothing",
                   e ? e.crumb.UTF8String : "-", e ? MTIPrefsURL(e.uid).UTF8String : "-");
            if (!ok) bad = 1;
        }
        return bad;
    }
}
OBJC
clang -fobjc-arc -Wall -Wno-unused-function -I../common -framework Foundation -o "$W/tidx" "$W/tidx.m" && "$W/tidx" "$W/b" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
check "the switch: Home Minimizes Windows (homeMinimizesWindows, on by default) in Window Behavior (1.8.6) with its sentence in the group's footer, hidden with the stock status bar" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; i=[x.get('id') for x in it].index('HOME_MINIMIZES_WINDOWS'); s=it[i]; g=[x for x in it[:i] if x.get('cell')=='PSGroupCell'][-1]; sys.exit(0 if s['key']=='homeMinimizesWindows' and s['default'] is True and s['cell']=='PSSwitchCell' and s['label']=='Home Minimizes Windows' and s['PostNotification']=='com.besiktasliseba.macstatusbar/prefsChanged' and g.get('id')=='WINDOW_BEHAVIOR_GROUP' and g.get('stockHides') is True and 'minimizes the windows' in g.get('footerText', '') and 'brings its window back' in g.get('footerText', '') else 1)\""
check "  ... read by SpringBoard as a boolean, else ON (every user, updaters too); on, the lift, the App Switcher's tap and Cmd-H are hooked, then the Home button's presses" \
  "fn $X 'static void DMLoadPrefs(' | grep -q 'CFPreferencesCopyValue(CFSTR(\"homeMinimizesWindows\"), MSB_DOMAIN' \
   && fn $X 'static void DMLoadPrefs(' | awk '/BOOL hm = YES;/{a=NR} /CFPreferencesCopyValue\(CFSTR\(\"homeMinimizesWindows\"\)/{b=NR} /if \(CFGetTypeID\(hmRef\) == CFBooleanGetTypeID\(\)\) hm = CFBooleanGetValue\(hmRef\);/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $X 'static void DMLoadPrefs(' | grep -q 'if (hm) { DMMSWHookActivation(); DMHomeAwayHookDismissTap(); DMHomeAwayHookKeys(); }' \
   && fn $X 'static void DMLoadPrefs(' | awk '/gHomeMinimizes = hm;/{a=NR} /DMMSWHookHomeButton\(\);/{b=NR} END{exit !(a && b > a)}' \
   && fn $Bt 'static void DMMSWHookHomeButton(void) {' | grep -q 'if (done || (!gMSWOn && !gHomeMinimizes)) return;'"
# (our own Home's mark, run as built: DMOwnHome and DMHomeIsOurs cut out of StatusBar.x, a stand-in clock -- the review of the 1.8.4 fixes, L1 and L3)
{ grep -F 'static CFTimeInterval gDMOwnHomeAt = -100;' $X; grep -F 'static int gDMOwnHomeDepth = 0;' $X; grep -F 'static BOOL DMHomeIsOurs(void) { return' $X
  if grep -q '^static void DMOwnHome(void (^home)(void)) {' $X; then fn $X 'static void DMOwnHome(void (^home)(void)) {'
  else echo 'static void DMOwnHome(void (^home)(void)) { home(); }   // (not in this source: our Home marked by DMMinimize only)'; fi; } > "$W/ownhome-gen.h"
check "our own Home (DMOwnHome: Minimize, Aerial's way into a window) is never the user's Home: marked while it runs and for a second from its start, the mark ended whatever happens in it (test-ownhome.m, run as built)" \
  "clang -fobjc-arc -Wall -Wno-unused-function -I\"\$W\" -framework Foundation -o \"\$W/toh\" test-ownhome.m && \"\$W/toh\" > \"\$W/toh.out\" 2>&1 && grep -q 'test-ownhome: all pass' \"\$W/toh.out\" \
   && grep -q '^static void DMMinimize(void) { DMOwnHome(^{ DMMinimizeBody(); }); }' $X"
check "F3 (regression 1.8.4, A12Z, engine parity): Aerial's way into a window goes home as our own Home too -- the Window menu's layouts, the green light and the window keys' arrangements from a full-screen app (its quiet transition or -_returnToHomeScreenWithCompletion:), and a cold start that goes full screen first: no other window minimized (Zetsu and MilkyWay4 go through DMMinimize)" \
  "fn $X 'static void DMWindowLayout(NSString *name) {' | tr -d '\n' | grep -q 'DMOwnHome(^{   // (our own Home on the way into the window, not the user.s: regression 1.8.4 F3)                quiet = DMMSWQuietTransition(nil, @\"green: the full-screen app back into its window\");                if (!quiet && canHome) ((void (\\*)(id, SEL, id))objc_msgSend)(ui, goHome, ^{});            });' \
   && [ \"\$(grep -c 'objc_msgSend)(ui, goHome, ^{})' $X)\" = 2 ] && [ \"\$(grep -c 'DMMSWQuietTransition(nil, @\"green' $X)\" = 1 ] \
   && fn $X 'BOOL DMAerialWarmStartIfNeeded(NSString *bundleID) {' | grep -q 'else DMOwnHome(^{ ((void (\\*)(id, SEL, id))objc_msgSend)(ui, goHome, ^{}); });' \
   && fn $X 'static void DMSendToWindow(NSString *bundleID) {' | grep -c 'DMMinimize();' | grep -q '^2$'"
check "the gesture's lift: whatever destination SpringBoard is finally given (after the takeover's stay), a 4 is a Home" \
  "grep -q 'static id DMMSWActOrig(id self, SEL _cmd, long long dest) { if (dest == 4) DMHomeAwayLift(); return o_MSWActivate(self, _cmd, dest); }' $M \
   && grep -q 'static id DMMSWActOrigRM(id self, SEL _cmd, long long dest) { if (dest == 4) DMHomeAwayLift(); return o_MSWActivateRM(self, _cmd, dest); }' $M \
   && grep -q 'static id DMMSWActOrigCE(id self, SEL _cmd, long long dest) { if (dest == 4) DMHomeAwayLift(); return o_MSWActivateCE(self, _cmd, dest); }' $M \
   && grep -q 'return DMMSWActivateWith(self, _cmd, dest, DMMSWActOrig); }' $M && grep -q 'return DMMSWActivateWith(self, _cmd, dest, DMMSWActOrigRM); }' $M \
   && grep -q 'return DMMSWActivateWith(self, _cmd, dest, DMMSWActOrigCE); }' $M"
check "  ... Reduce Motion's side swipe still known by its own activation; the Mac Switcher's takeover only once its own hooks are in" \
  "fn $M 'static id DMMSWActivateWith(id self, SEL _cmd, long long dest, id (*orig)(id, SEL, long long)) {' | grep -q 'if (dest == 0 && orig == DMMSWActOrigRM) {' \
   && fn $M 'static id DMMSWActivateWith(id self, SEL _cmd, long long dest, id (*orig)(id, SEL, long long)) {' | grep -q '|| !gMSWGestHooked || !DMMSWGesturesOn()) return orig(self, _cmd, dest);' \
   && fn $M 'static void DMMSWHookGestures(void) {' | awk '/DMMSWHookActivation\(\);/{a=NR} /gMSWGestHooked = YES;/{b=NR} END{exit !(a && b > a)}' \
   && fn $M 'static void DMMSWHookActivation(void) {' | grep -q 'if (gMSWActHooked) return;'"
check "the Home button: every single-press replacement asks the rule after SpringBoard's own press, with what was over the screen before it (5 signatures)" \
  "[ \$(grep -c '{ BOOL c = DMHomeAwayPressCovered(); DMMSWHomeSingle(); BOOL r = o_MSWSingle[A-Za-z]*(self, _cmd[a-z, ]*); DMHomeAwayPress(r, c); return r; }' $Bt) = 5 ] \
   && grep -q 'static BOOL DMHomeAwayPressCovered(void) { return gHomeMinimizes && DMHomeAwayCovered(); }' $X \
   && grep -q 'static BOOL DMHomeAwayCovered(void) { return DMCoverSheetShown() || DMControlCenterActive(); }' $X"
check "  ... the decision from HomeAway.h, after SpringBoard's own handling; one Home per lift and per press" \
  "fn $X 'static void DMHomeAwayRun(' | grep -q 'int what = DMHomeAwayWhat(gHomeMinimizes, ours, keys, coveredBefore || DMHomeAwayCovered(), MSBDGuidedAccessActive(), sm, engineWins, ourWins);' \
   && fn $X 'static void DMHomeAwayRun(' | grep -q 'dispatch_async(dispatch_get_main_queue(), ^{' && fn $X 'static void DMHomeAwayRun(' | grep -q 'DMMinimizeAllWindows();' \
   && fn $X 'static void DMHomeAwayLift(void) {' | grep -q 'DMHomeAwayOnce(CACurrentMediaTime(), &gHomeAwayLiftAt)' && fn $X 'static void DMHomeAwayPress(BOOL handled, BOOL coveredBefore) {' | grep -q 'DMHomeAwayOnce(CACurrentMediaTime(), &gHomeAwayPressAt)' \
   && fn $X 'static void DMHomeAwayPress(BOOL handled, BOOL coveredBefore) {' | grep -q 'DMHomeIsOurs(), DMHomeFromKeys(), coveredBefore);'"
check "the App Switcher's tap beside its cards: iPadOS's main App Switcher only, not with the Stage Manager engine (its Home rule has that one)" \
  "fn $X 'static void DMHomeAwayDismissTap(' | grep -q 'BOOL main = gHomeMinimizes && !DMSMEngine() && self == DMMainSwitcherContent() && DMMainSwitcherVisible();' \
   && fn $X 'static void DMHomeAwayDismissTap(' | awk '/o_HomeAwayDismissTap\(self, _cmd, recognizer\);/{a=NR} /if \(main\) DMHomeAwayRun/{b=NR} END{exit !(a && b > a)}'"
check "the Stage Manager engine: the user's Home (never our own press) takes the windows with it -- Home as SpringBoard built it, each window minimized" \
  "fn $H '__attribute__((noinline)) static void DMSMHomeKeepsDesktop(' | grep -q 'if (gHomeMinimizes && !DMHomeIsOurs() && !DMHomeFromKeys()) flags |= DMSMHomeHide;' \
   && fn $H '__attribute__((noinline)) static void DMSMHomeKeepsDesktop(' | awk '/flags \|= DMSMHomeHide;/{a=NR} /DMSMHomePlan\(windows, roles, nRoles, flags/{b=NR} /if \(plan\[@\"hide\"\]\) \{/{c=NR} /DMSMSetMinimized\(k, YES\);/{d=d?d:(c&&NR>c?NR:0)} /The plan in SpringBoard.s terms/{e=NR} END{exit !(a && b > a && c > b && d > c && e > d)}'"
check "  ... the Home gesture then looks as Apple has it (the stage follows the finger; no kept-still desktop, no sharp Home Screen under it)" \
  "fn $H 'static BOOL DMSMHGOverDesk(id mod, Ivar start) {' | grep -q 'if (gHomeMinimizes) return NO;'"
check "Cmd-H keeps its Home as before (KT 2 Nov): SpringBoard's Home shortcut marked while it runs and a second after, its exact type only" \
  "fn $X 'static void DMHomeAwayKeysHome(id self, SEL _cmd, id sender) {' | awk '/gDMKeysHomeAt = CACurrentMediaTime\(\);/{a=a?a:NR} /gDMKeysHomeDepth\+\+;/{b=NR} /o_HomeAwayKeysHome\(self, _cmd, sender\);/{c=NR} /gDMKeysHomeDepth--;/{d=NR} END{exit !(a && b > a && c > b && d > c)}' \
   && grep -q 'static BOOL DMHomeFromKeys(void) { return gDMKeysHomeDepth > 0 || CACurrentMediaTime() - gDMKeysHomeAt < 1.0; }' $X \
   && fn $X 'static void DMHomeAwayHookKeys(void) {' | grep -q 'SEL s = NSSelectorFromString(@\"_handleGotoHomeScreenShortcut:\");' \
   && fn $X 'static void DMHomeAwayHookKeys(void) {' | grep -q 'DMSMExpect(@encode(void), @encode(id), NULL)' && fn $X 'static void DMHomeAwayHookKeys(void) {' | grep -q 'MSHookMessageEx(c, s, (IMP)DMHomeAwayKeysHome, (IMP \*)&o_HomeAwayKeysHome);'"
check "  ... its Home goes nowhere else: the gesture's lift and the App Switcher's tap are never the keyboard's" \
  "fn $X 'static void DMHomeAwayLift(void) {' | grep -q 'DMHomeAwayRun(@\"a Home gesture\", DMHomeIsOurs(), NO, NO);' \
   && fn $X 'static void DMHomeAwayDismissTap(' | grep -q 'DMHomeAwayRun(@\"a tap beside the App Switcher.s cards\", DMHomeIsOurs(), NO, NO);'"
check "  ... and SpringBoard's other key commands for H (Globe-H, if it has its own action): read once SpringBoard is up, each marked the same way" \
  "fn $X 'static void DMHomeAwayScanKeys(void) {' | grep -q 'if (!\[c isKindOfClass:\[UIKeyCommand class\]\] || !\[\[c.input lowercaseString\] isEqualToString:@\"h\"\] || !c.action) continue;' \
   && fn $X 'static void DMHomeAwayScanKeys(void) {' | grep -q 'if (sel_isEqual(c.action, NSSelectorFromString(@\"_handleGotoHomeScreenShortcut:\")) || gDMHomeKeysCount >= kDMHomeKeysMax) continue;' \
   && fn $X 'static void DMHomeAwayScanKeys(void) {' | grep -q 'DMSMExpect(@encode(void), @encode(id), NULL)' \
   && fn $X 'static void DMHomeAwayScanKeys(void) {' | grep -q 'MSHookMessageEx(k, c.action, (IMP)DMHomeAwayKeysOther, (IMP \*)&gDMHomeKeysOrig\[gDMHomeKeysCount\]);' \
   && fn $X 'static void DMHomeAwayKeysOther(id self, SEL _cmd, id sender) {' | awk '/gDMKeysHomeDepth\+\+;/{a=NR} /if \(orig\) orig\(self, _cmd, sender\);/{b=NR} /gDMKeysHomeDepth--;/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $X 'static void DMTickBody(void) {' | grep -q 'if (gHomeMinimizes && DMProcessAge() > 8.0) DMHomeAwayScanKeys();'"
check "on for updaters too: no old default frozen for it in the root helper, and nothing writes the key (only a tap on the switch stores one)" \
  "! awk '/^static NSArray<NSArray \*> \*OldDefaults\(void\) \{/,/^}/' ../macsettings/sshtoggled/main.m | grep -q 'homeMinimizesWindows' \
   && ! grep -rn 'CFPreferencesSet[A-Za-z]*Value(CFSTR(\"homeMinimizesWindows\")' ../macsettings ../statusbar ../common ../dock"
[ $fails = 0 ] && echo "test-homeaway: all pass" || echo "test-homeaway: FAILED"
exit $fails
