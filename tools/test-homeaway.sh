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
        NSDictionary *want = @{@"home minimizes": @"Home Minimizes Windows", @"minimize": @"Home Minimizes Windows",   // (1.8.8.1: Adapt to Trackpad & Mouse
                               @"trackpad": @"Adapt to Trackpad & Mouse", @"adapt": @"Adapt to Trackpad & Mouse"};  //  by its words, Home Minimizes Windows still first)
        NSDictionary *ids = @{@"Home Minimizes Windows": @"HOME_MINIMIZES_WINDOWS", @"Adapt to Trackpad & Mouse": @"HOME_MINIMIZES_ADAPT"};
        for (NSString *q in @[@"home minimizes", @"minimize", @"trackpad", @"adapt"]) {
            MTIEntry *e = MTIMatch(MTIBuild(c), q, 10).firstObject;
            BOOL ok = e && [e.title isEqualToString:want[q]] && [e.crumb isEqualToString:@"Windows & Multitasking"]
                && [MTIPrefsURL(e.uid) isEqualToString:[@"prefs:root=MAC_WINDOWS#" stringByAppendingString:ids[want[q]]]];
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
check "1.8.7.1 (KT 13 Nov, WhatsApp from the Dock with Aerial 5.1): the full-screen-first cold start (DMAerialWarmStartIfNeeded) only for Aerial 5.0 and a build we have not tested; a tested later build (5.1) opens it straight into its window" \
  "fn $X 'static BOOL DMAerialNeedsWarmStart(NSString *bundleID) {' | grep -q 'if (!DMAerialBuildNeedsWarmStart()) return NO;' \
   && fn $X 'static BOOL DMAerialBuildNeedsWarmStart(void) {' | grep -q 'known = (!label || \[label hasPrefix:@\"5.0\"\]) ? 1 : 0;' \
   && fn $X 'static BOOL DMAerialBuildNeedsWarmStart(void) {' | grep -q 'MSBDEngineBuildLabel(@\"Aerial\", uuid)' \
   && grep -q '\"Aerial\", \"5.1 arm64e\"' ../common/EngineBuilds.h && grep -q '\"Aerial\", \"5.0 arm64e\"' ../common/EngineBuilds.h"
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
   && grep -qF '__attribute__((noinline)) static BOOL DMHomeAwayPressCovered(void) { return gHomeMinimizes && DMHomeAwayCovered(); }' $X \
   && grep -q 'static BOOL DMHomeAwayCovered(void) { return DMCoverSheetShown() || DMControlCenterActive(); }' $X"
check "  ... the decision from HomeAway.h, after SpringBoard's own handling; one Home per lift and per press" \
  "fn $X 'static void DMHomeAwayRun(' | grep -qF 'int what = DMHomeAwayWhat(gHomeMinimizes, ours, keys, coveredBefore || DMHomeAwayCovered(), MSBDGuidedAccessActive(), sm, engineWins, ourWins), pointer = -1;' \
   && fn $X 'static void DMHomeAwayRun(' | grep -q 'dispatch_async(dispatch_get_main_queue(), ^{' && fn $X 'static void DMHomeAwayRun(' | grep -q 'DMMinimizeAllWindows();' \
   && fn $X '__attribute__((noinline)) static void DMHomeAwayLift(void) {' | grep -q 'DMHomeAwayOnce(CACurrentMediaTime(), &gHomeAwayLiftAt)' && fn $X '__attribute__((noinline)) static void DMHomeAwayPress(BOOL handled, BOOL coveredBefore) {' | grep -q 'DMHomeAwayOnce(CACurrentMediaTime(), &gHomeAwayPressAt)' \
   && fn $X '__attribute__((noinline)) static void DMHomeAwayPress(BOOL handled, BOOL coveredBefore) {' | grep -q 'DMHomeIsOurs(), DMHomeFromKeys(), coveredBefore);'"
check "the App Switcher's tap beside its cards: iPadOS's main App Switcher only, not with the Stage Manager engine (its Home rule has that one)" \
  "fn $X 'static void DMHomeAwayDismissTap(' | grep -q 'BOOL main = gHomeMinimizes && !DMSMEngine() && self == DMMainSwitcherContent() && DMMainSwitcherVisible();' \
   && fn $X 'static void DMHomeAwayDismissTap(' | awk '/o_HomeAwayDismissTap\(self, _cmd, recognizer\);/{a=NR} /if \(main\) DMHomeAwayRun/{b=NR} END{exit !(a && b > a)}'"
check "the Stage Manager engine: the user's Home (never our own press) takes the windows with it -- Home as SpringBoard built it, each window minimized" \
  "fn $H '__attribute__((noinline)) static void DMSMHomeKeepsDesktop(' | grep -qF 'if (!DMHomeIsOurs() && !DMHomeFromKeys() && DMHomeAdaptMinimizes(NULL)) flags |= DMSMHomeHide;' \
   && fn $H '__attribute__((noinline)) static void DMSMHomeKeepsDesktop(' | awk '/flags \|= DMSMHomeHide;/{a=NR} /DMSMHomePlan\(windows, roles, nRoles, flags/{b=NR} /if \(plan\[@\"hide\"\]\) \{/{c=NR} /DMSMSetMinimized\(k, YES\);/{d=d?d:(c&&NR>c?NR:0)} /The plan in SpringBoard.s terms/{e=NR} END{exit !(a && b > a && c > b && d > c && e > d)}'"
check "  ... the Home gesture then looks as Apple has it (the stage follows the finger; no kept-still desktop, no sharp Home Screen under it)" \
  "fn $H 'static BOOL DMSMHGOverDesk(id mod, Ivar start) {' | grep -qF 'BOOL goes = env == 3 && DMHomeAdaptMinimizes(NULL), yes = NO;' && fn $H 'static BOOL DMSMHGOverDesk(id mod, Ivar start) {' | grep -qF 'if (env == 3 && !goes) {'"
check "Cmd-H keeps its Home as before (KT 2 Nov): SpringBoard's Home shortcut marked while it runs and a second after, its exact type only" \
  "fn $X 'static void DMHomeAwayKeysHome(id self, SEL _cmd, id sender) {' | awk '/gDMKeysHomeAt = CACurrentMediaTime\(\);/{a=a?a:NR} /gDMKeysHomeDepth\+\+;/{b=NR} /o_HomeAwayKeysHome\(self, _cmd, sender\);/{c=NR} /gDMKeysHomeDepth--;/{d=NR} END{exit !(a && b > a && c > b && d > c)}' \
   && grep -q 'static BOOL DMHomeFromKeys(void) { return gDMKeysHomeDepth > 0 || CACurrentMediaTime() - gDMKeysHomeAt < 1.0; }' $X \
   && fn $X '__attribute__((noinline)) static void DMHomeAwayHookKeys(void) {' | grep -q 'SEL s = NSSelectorFromString(@\"_handleGotoHomeScreenShortcut:\");' \
   && fn $X '__attribute__((noinline)) static void DMHomeAwayHookKeys(void) {' | grep -q 'DMSMExpect(@encode(void), @encode(id), NULL)' && fn $X '__attribute__((noinline)) static void DMHomeAwayHookKeys(void) {' | grep -q 'MSHookMessageEx(c, s, (IMP)DMHomeAwayKeysHome, (IMP \*)&o_HomeAwayKeysHome);'"
check "  ... its Home goes nowhere else: the gesture's lift and the App Switcher's tap are never the keyboard's" \
  "fn $X '__attribute__((noinline)) static void DMHomeAwayLift(void) {' | grep -q 'DMHomeAwayRun(@\"a Home gesture\", DMHomeIsOurs(), NO, NO);' \
   && fn $X 'static void DMHomeAwayDismissTap(' | grep -q 'DMHomeAwayRun(@\"a tap beside the App Switcher.s cards\", DMHomeIsOurs(), NO, NO);'"
check "  ... and SpringBoard's other key commands for H (Globe-H, if it has its own action): read once SpringBoard is up, each marked the same way" \
  "fn $X '__attribute__((noinline)) static void DMHomeAwayScanKeys(void) {' | grep -q 'if (!\[c isKindOfClass:\[UIKeyCommand class\]\] || !\[\[c.input lowercaseString\] isEqualToString:@\"h\"\] || !c.action) continue;' \
   && fn $X '__attribute__((noinline)) static void DMHomeAwayScanKeys(void) {' | grep -q 'if (sel_isEqual(c.action, NSSelectorFromString(@\"_handleGotoHomeScreenShortcut:\")) || gDMHomeKeysCount >= kDMHomeKeysMax) continue;' \
   && fn $X '__attribute__((noinline)) static void DMHomeAwayScanKeys(void) {' | grep -q 'DMSMExpect(@encode(void), @encode(id), NULL)' \
   && fn $X '__attribute__((noinline)) static void DMHomeAwayScanKeys(void) {' | grep -q 'MSHookMessageEx(k, c.action, (IMP)DMHomeAwayKeysOther, (IMP \*)&gDMHomeKeysOrig\[gDMHomeKeysCount\]);' \
   && fn $X 'static void DMHomeAwayKeysOther(id self, SEL _cmd, id sender) {' | awk '/gDMKeysHomeDepth\+\+;/{a=NR} /if \(orig\) orig\(self, _cmd, sender\);/{b=NR} /gDMKeysHomeDepth--;/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $X 'static void DMTickBody(void) {' | grep -q 'if (gHomeMinimizes && DMProcessAge() > 8.0) DMHomeAwayScanKeys();'"
check "on for updaters too: no old default frozen for it in the root helper, and nothing writes the key (only a tap on the switch stores one)" \
  "! awk '/^static NSArray<NSArray \*> \*OldDefaults\(void\) \{/,/^}/' ../macsettings/sshtoggled/main.m | grep -q 'homeMinimizesWindows' \
   && ! grep -rn 'CFPreferencesSet[A-Za-z]*Value(CFSTR(\"homeMinimizesWindows\")' ../macsettings ../statusbar ../common ../dock"
# ---- Adapt to Trackpad & Mouse (1.8.8.1, F28; HomeAway.h DMHomeAwayOn, StatusBar.x DMHomeAdaptMinimizes): the row, its sentence and its grey, the
# read of the switch, the pointer read only with both switches on and only for a Home that would minimize, every Home decision on every engine
# through the one rule, the hooks and early outs still on the switch itself. f28 runs over the files in X H P PM HM, so a made-to-fail copy runs
# the same checks.
PM=../statusbar/macstatusbarprefs/MSBRootListController.m; HM=../macsettings/sshtoggled/main.m
cat > "$W/f28row.py" <<'PY'
import plistlib, sys
P, PM = sys.argv[1], sys.argv[2]
SENT = "Adapt to Trackpad & Mouse: while a trackpad or mouse is connected, such as the Magic Keyboard for iPad, going Home leaves the windows where they are, as on a Mac. Without one, Home minimizes them. A keyboard alone doesn't count."
HOME = "Home Minimizes Windows: swiping up from the bottom or pressing the Home button minimizes the windows, so the Home Screen shows. Opening an app brings its window back."
it = plistlib.load(open(P, 'rb'))['items']; ids = [x.get('id') for x in it]
i = ids.index('HOME_MINIMIZES_ADAPT') if ids.count('HOME_MINIMIZES_ADAPT') == 1 else -1
r = it[i] if i > 0 else {}
g = [x for x in it[:i] if x.get('cell') == 'PSGroupCell'][-1] if i > 0 else {}
paras = g.get('footerText', '').split('\n\n')
ok = (i > 0 and it[i - 1].get('id') == 'HOME_MINIMIZES_WINDOWS' and r.get('key') == 'homeMinimizesAdapt' and r.get('default') is True and r.get('cell') == 'PSSwitchCell'
      and r.get('label') == 'Adapt to Trackpad & Mouse' and r.get('defaults') == 'com.besiktasliseba.macstatusbar' and r.get('PostNotification') == 'com.besiktasliseba.macstatusbar/prefsChanged'
      and g.get('id') == 'WINDOW_BEHAVIOR_GROUP' and g.get('stockHides') is True and HOME in paras and SENT in paras and paras.index(SENT) == paras.index(HOME) + 1
      and not any(d in g.get('footerText', '') for d in ('\u2014', '\u2013')))
code = open(PM).read()
ok = ok and ('\t\t@"homeMinimizesAdapt": @"%s",\n' % SENT) in code and ('\t\t@"homeMinimizesWindows": @"%s",\n' % HOME) in code
sys.exit(0 if ok else 1)
PY
cat > "$W/f28sites.py" <<'PY'
# every function of StatusBar.x and statusbar/*.h that reads gHomeMinimizes, gHomeAdapt or calls DMHomeAdaptMinimizes / DMHomeAdaptPointer, by name
import glob, os, re, sys
X, H = sys.argv[1], sys.argv[2]
files = [X, H] + [f for f in sorted(glob.glob(os.path.join(os.path.dirname(os.path.abspath(X)), '*.h'))) if os.path.basename(f) != os.path.basename(H)]
HEAD = re.compile(r'^(__attribute__\(\(noinline\)\) )?static [^;=(]*?\b(\w+)\((.*)\)\s*\{')
seen = {}
for f in files:
    cur = None
    for t in open(f, errors='replace'):
        m = HEAD.match(t)
        if m: cur = m.group(2)
        elif re.match(r'^(%hook|%end|%group|%subclass|[-+] ?\()', t): cur = None
        code = t.split('//')[0]
        for w in ('gHomeMinimizes', 'gHomeAdapt', 'DMHomeAdaptMinimizes(', 'DMHomeAdaptPointer('):
            if re.search(re.escape(w) + (r'\b' if not w.endswith('(') else ''), code) and not (m and w.startswith(m.group(2) + '(')):
                seen.setdefault(w, set()).add('%s:%s' % (os.path.basename(f), cur or '(file scope)'))
        if t.startswith('}'): cur = None
want = {
    'gHomeMinimizes': {'StatusBar.x:(file scope)', 'StatusBar.x:DMHomeAdaptMinimizes', 'StatusBar.x:DMHomeAwayPressCovered', 'StatusBar.x:DMHomeAwayRun', 'StatusBar.x:DMHomeAwayLift',
                       'StatusBar.x:DMHomeAwayPress', 'StatusBar.x:DMHomeAwayDismissTap', 'StatusBar.x:DMHomeAwayScanKeys', 'StatusBar.x:DMLoadPrefs', 'StatusBar.x:DMTickBody',
                       'MacSwitcherButton.h:DMMSWHookHomeButton'},
    'gHomeAdapt': {'StatusBar.x:(file scope)', 'StatusBar.x:DMHomeAdaptMinimizes', 'StatusBar.x:DMHomeAwayRun', 'StatusBar.x:DMLoadPrefs'},
    'DMHomeAdaptMinimizes(': {'StatusBar.x:DMHomeAwayRun', 'SMHome.h:DMSMHomeKeepsDesktop', 'SMHome.h:DMSMHGOverDesk'},
    'DMHomeAdaptPointer(': {'StatusBar.x:DMHomeAdaptMinimizes'},
}
bad = ['%s: %s (want %s)' % (w, sorted(seen.get(w, set())), sorted(want[w])) for w in want if seen.get(w, set()) != want[w]]
for b in bad: print('  ' + b)
sys.exit(1 if bad else 0)
PY
f28() {   # $1: q = quiet. The number of checks that fail.
  local q=$1 n=0
  c() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  c "F28 Settings: Adapt to Trackpad & Mouse (homeMinimizesAdapt, on by default, applied at once) right under Home Minimizes Windows in Window Behavior, hidden with the stock status bar; its sentence after Home Minimizes Windows' in the group's footer, the same words where the page composes it, no dash" \
    "python3 -I \"\$W/f28row.py\" \"\$P\" \"\$PM\""
  c "  ... greyed while Home Minimizes Windows is off (never set: on, as SpringBoard reads it) and where MacStatusBar&Dock is not running, live when that switch changes" \
    "fn \$PM '- (void)msb_updateHomeAdaptRow:(BOOL)reload {' > \"\$W/hr\" && grep -qF 'CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR(\"homeMinimizesWindows\"), kMSBBarDomain);' \"\$W/hr\" \
     && grep -qF 'BOOL on = !(v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v));   // (never set: on)' \"\$W/hr\" && grep -qF 'if (!MSBDGateWanted()) on = NO;' \"\$W/hr\" \
     && grep -qF 'if (![spec.identifier isEqualToString:@\"HOME_MINIMIZES_ADAPT\"]) continue;' \"\$W/hr\" && grep -qF '[spec setProperty:@(on) forKey:@\"enabled\"];' \"\$W/hr\" \
     && grep -qF 'if (reload) [self reloadSpecifier:spec animated:YES];' \"\$W/hr\" \
     && fn \$PM '- (NSArray *)specifiers {' | grep -qF '[self msb_updateHomeAdaptRow:NO];' \
     && grep -qF 'if ([[specifier propertyForKey:@\"key\"] isEqual:@\"homeMinimizesWindows\"]) { [self msb_updateHomeAdaptRow:YES]; return; }' \$PM"
  c "  ... read by SpringBoard as a boolean, else ON (every user, updaters too), with Home Minimizes Windows' read; nothing of its own hooked" \
    "fn \$X 'static void DMLoadPrefs(' > \"\$W/lp\" && awk '/gHomeMinimizes = hm;/{a=NR} /BOOL ha = YES;/{b=NR} /CFPropertyListRef haRef = CFPreferencesCopyValue\\(CFSTR\\(\"homeMinimizesAdapt\"\\), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost\\);/{c=NR} /if \\(haRef\\) \\{ if \\(CFGetTypeID\\(haRef\\) == CFBooleanGetTypeID\\(\\)\\) ha = CFBooleanGetValue\\(haRef\\); CFRelease\\(haRef\\); \\}/{d=NR} /gHomeAdapt = ha;/{e=NR} /if \\(hm\\) \\{ DMMSWHookActivation\\(\\);/{f=NR} END{exit !(a && b > a && c > b && d > c && e > d && f > e)}' \"\$W/lp\" \
     && [ \"\$(grep -c '^static BOOL gHomeAdapt = NO;' \$X)\" = 1 ]"
  c "  ... the rule asks the pointer only with both switches on, and the pointer's answer keeps the windows (DMHomeAwayOn); the release build's feature mark on that branch" \
    "fn \$X '__attribute__((noinline)) static BOOL DMHomeAdaptMinimizes(int *pointer) {' > \"\$W/am\" && grep -qF 'int p = gHomeMinimizes && gHomeAdapt ? DMHomeAdaptPointer() : -1;' \"\$W/am\" \
     && grep -qF 'return DMHomeAwayOn(gHomeMinimizes, gHomeAdapt, p == 1);' \"\$W/am\" && grep -qF 'if (p == 1) DM_FEATURE_MARK(\"home-adapt-keeps-windows\");' \"\$W/am\" \
     && [ \"\$(grep -c 'home-adapt-keeps-windows' \$X)\" = 1 ] && ! grep -q 'MSHook' \"\$W/am\""
  c "  ... the pointer: SpringBoard's pointer manager asked fresh (the Haptic Touch menus' answer), its signature checked once, the 2 s poll only where it cannot be asked; the debug stand-ins only through DMTestFlag, which a release build compiles to 0" \
    "fn \$X '__attribute__((noinline)) static int DMHomeAdaptPointer(void) {' > \"\$W/ap\" && grep -qF 'if (DMTestFlag(\"/tmp/msb-noptr\")) return 0;' \"\$W/ap\" && grep -qF 'if (DMTestFlag(\"/tmp/msb-fakeptr\")) return 1;' \"\$W/ap\" \
     && grep -qF 'id mgr = DMCall([UIApplication sharedApplication], @\"mousePointerManager\");' \"\$W/ap\" && grep -qF 'SEL s = NSSelectorFromString(@\"isHardwarePointingDeviceAttached\");' \"\$W/ap\" \
     && grep -qF 'sig = m && [DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(BOOL), NULL)] ? 1 : 0;' \"\$W/ap\" && grep -qF 'if (sig == 1 && [mgr respondsToSelector:s]) return ((BOOL (*)(id, SEL))objc_msgSend)(mgr, s) ? 1 : 0;' \"\$W/ap\" \
     && grep -qF 'return gDMPointerAttached ? 1 : 0;' \"\$W/ap\" && [ \"\$(grep -c '/tmp/' \"\$W/ap\")\" = \"\$(grep -c 'DMTestFlag(\"/tmp/' \"\$W/ap\")\" ] && ! grep -q 'access(\\|fileExists\\|MSHook' \"\$W/ap\" \
     && grep -qx '#define DMTestFlag(path) 0' \$X && grep -qx 'static BOOL gDMPointerAttached;   // (the MacPointer bridge.s 2 s answer: a trackpad or mouse attached; defined there)' \$X"
  c "  ... Aerial, Zetsu, MilkyWay4, no engine and our own windows: the run asks it last, after the switch's own answer (never for our own Home, the keyboard's, a covered one, Guided Access's, or one with no window)" \
    "fn \$X 'static void DMHomeAwayRun(' > \"\$W/hr2\" && awk '/int what = DMHomeAwayWhat\\(gHomeMinimizes, ours, keys, coveredBefore \\|\\| DMHomeAwayCovered\\(\\), MSBDGuidedAccessActive\\(\\), sm, engineWins, ourWins\\), pointer = -1;/{a=NR} /^        if \\(what != DMHomeAwayNone && !DMHomeAdaptMinimizes\\(&pointer\\)\\) what = DMHomeAwayNone;/{b=NR} /if \\(what == DMHomeAwayNone\\) return;/{c=NR} END{exit !(a && b > a && c > b)}' \"\$W/hr2\" \
     && [ \"\$(grep -c 'DMHomeAdaptMinimizes(' \"\$W/hr2\")\" = 1 ]"
  c "  ... our Stage Manager engine: its Home takes the windows only as the rule says, asked after our own Home and the keyboard's" \
    "fn \$H '__attribute__((noinline)) static void DMSMHomeKeepsDesktop(' | grep -qxF '    if (!DMHomeIsOurs() && !DMHomeFromKeys() && DMHomeAdaptMinimizes(NULL)) flags |= DMSMHomeHide;'"
  c "  ... and its Home gesture's look: the rule asked once per gesture from application mode, inside the one answer kept for the gesture (no stage read when the windows go, as before)" \
    "fn \$H 'static BOOL DMSMHGOverDesk(id mod, Ivar start) {' > \"\$W/od\" && ! grep -q 'gHomeMinimizes' \"\$W/od\" \
     && awk '/if \\(cached\\) return cached.boolValue;/{a=NR} /^    BOOL goes = env == 3 && DMHomeAdaptMinimizes\\(NULL\\), yes = NO;/{b=NR} /^    if \\(env == 3 && !goes\\) \\{/{c=NR} /DMSMFrontStageOnDisplay/{d=NR} /objc_setAssociatedObject\\(mod, &kSMHGDeskKey, @\\(yes\\), OBJC_ASSOCIATION_RETAIN_NONATOMIC\\);/{e=NR} END{exit !(a && b > a && c > b && d > c && e > d)}' \"\$W/od\" && [ \"\$(grep -c 'DMHomeAdaptMinimizes(NULL)' \"\$W/od\")\" = 1 ]"
  c "  ... engine parity: every Home decision takes the rule, nothing else reads the switches -- the switch itself only for the hooks' install and the early outs, the rule only from the run and the Stage Manager engine's Home and look" \
    "python3 -I \"\$W/f28sites.py\" \"\$X\" \"\$H\""
  c "  ... the hooks' install and the early outs still on the switch itself (the Homes by hand need the hooks in with a trackpad attached)" \
    "fn \$X '__attribute__((noinline)) static void DMHomeAwayLift(void) {' | grep -qF 'if (!gHomeMinimizes || !DMHomeAwayOnce(CACurrentMediaTime(), &gHomeAwayLiftAt)) return;' \
     && fn \$X '__attribute__((noinline)) static void DMHomeAwayPress(BOOL handled, BOOL coveredBefore) {' | grep -qF 'if (!gHomeMinimizes || !DMHomeAwayOnce(CACurrentMediaTime(), &gHomeAwayPressAt)) return;' \
     && fn \$X 'static void DMLoadPrefs(' | grep -qF 'if (hm) { DMMSWHookActivation(); DMHomeAwayHookDismissTap(); DMHomeAwayHookKeys(); }'"
  c "  ... on for updaters too: no old default frozen for it in the root helper, and nothing writes the key (only a tap on the switch, or the crash guard, stores one)" \
    "! awk '/^static NSArray<NSArray \\*> \\*OldDefaults\\(void\\) \\{/,/^}/' \$HM | grep -q 'homeMinimizesAdapt' \
     && ! grep -rn 'CFPreferencesSet[A-Za-z]*Value(CFSTR(\"homeMinimizesAdapt\")' ../macsettings ../statusbar ../common ../dock"
  return $n
}
f28 || fails=1
echo "== F28 made-to-fail copies (each must fail)"
mk=0
mutf() {   # $1 what, $2 the variable (X H P PM HM), $3 perl expression on that file (the whole file at once)
  local d="$W/mf$((++mk))" v=$2 o; o=${!v}; mkdir -p "$d"; perl -0777 -pe "$3" "$o" > "$d/f"
  if cmp -s "$d/f" "$o"; then echo "FAIL  made to fail ($1): the copy did not change"; fails=1; return; fi
  if (eval "$v=\"$d/f\""; f28 q); then echo "FAIL  made to fail ($1): still passes"; fails=1; else echo "PASS  made to fail ($1): caught"; fi
}
mutf "Adapt ignored by the rule's caller" X 's/return DMHomeAwayOn\(gHomeMinimizes, gHomeAdapt, p == 1\);/return DMHomeAwayOn(gHomeMinimizes, 0, p == 1);/'
mutf "the pointer read with Adapt off" X 's/int p = gHomeMinimizes && gHomeAdapt \? DMHomeAdaptPointer\(\) : -1;/int p = gHomeMinimizes ? DMHomeAdaptPointer() : -1;/'
mutf "the row off by default" P 's/(<string>HOME_MINIMIZES_ADAPT<\/string>)/$1/; s/(<key>default<\/key>\s*<)true(\/>\s*<key>defaults<\/key>\s*<string>com\.besiktasliseba\.macstatusbar<\/string>\s*<key>id<\/key>\s*<string>HOME_MINIMIZES_ADAPT)/$1false$2/'
mutf "SpringBoard reading it off when never set" X 's/BOOL ha = YES;/BOOL ha = NO;/'
mutf "the row not greyed live" PM 's/ \{ \[self msb_updateHomeAdaptRow:YES\]; return; \}/ { return; }/'
mutf "the row greyed by the wrong switch" PM 's/(msb_updateHomeAdaptRow:\(BOOL\)reload \{\n\tCFPreferencesAppSynchronize\(kMSBBarDomain\);\n\tCFPropertyListRef v = CFPreferencesCopyAppValue\(CFSTR\(")homeMinimizesWindows/$1macSwitcher/'
mutf "the pointer read before the run's early outs" X 's/int what = DMHomeAwayWhat\(gHomeMinimizes, ours,/int what = DMHomeAwayWhat(DMHomeAdaptMinimizes(&pointer), ours,/'
mutf "the Stage Manager engine reading the pointer before our own Home" H 's/if \(!DMHomeIsOurs\(\) && !DMHomeFromKeys\(\) && DMHomeAdaptMinimizes\(NULL\)\)/if (DMHomeAdaptMinimizes(NULL) && !DMHomeIsOurs() && !DMHomeFromKeys())/'
mutf "the Stage Manager engine's Home left on the switch (parity)" H 's/if \(!DMHomeIsOurs\(\) && !DMHomeFromKeys\(\) && DMHomeAdaptMinimizes\(NULL\)\)/if (gHomeMinimizes && !DMHomeIsOurs() \&\& !DMHomeFromKeys())/'
mutf "the gesture's look left on the switch (parity)" H 's/BOOL goes = env == 3 && DMHomeAdaptMinimizes\(NULL\), yes = NO;/BOOL goes = env == 3 \&\& gHomeMinimizes, yes = NO;/'
mutf "the gesture's look asked outside its cache" H 's/(    NSNumber \*cached = objc_getAssociatedObject\(mod, &kSMHGDeskKey\);\n)/    if (DMHomeAdaptMinimizes(NULL)) return NO;\n$1/'
mutf "the gesture's lift keyed on the rule (no hooks' Home by hand with a trackpad in)" X 's/if \(!gHomeMinimizes \|\| !DMHomeAwayOnce\(CACurrentMediaTime\(\), &gHomeAwayLiftAt\)\) return;/if (!DMHomeAdaptMinimizes(NULL) || !DMHomeAwayOnce(CACurrentMediaTime(), \&gHomeAwayLiftAt)) return;/'
mutf "a release build reading a /tmp flag" X 's/if \(DMTestFlag\("\/tmp\/msb-noptr"\)\) return 0;/if (access("\/tmp\/msb-noptr", F_OK) == 0) return 0;/'
mutf "an old default frozen for updaters" HM 's/(static NSArray<NSArray \*> \*OldDefaults\(void\) \{[^\n]*\n)/$1    (void)\@[\@"com.besiktasliseba.macstatusbar", \@"homeMinimizesAdapt", \@NO, \@6];\n/'
# the plain C rule itself, made to fail: test-homeaway.c on a changed HomeAway.h
mutc() {   # $1 what, $2 perl expression on HomeAway.h
  local d="$W/mc$((++mk))"; mkdir -p "$d/tools" "$d/statusbar"; cp test-homeaway.c "$d/tools/"; perl -0777 -pe "$2" ../statusbar/HomeAway.h > "$d/statusbar/HomeAway.h"
  if cmp -s "$d/statusbar/HomeAway.h" ../statusbar/HomeAway.h; then echo "FAIL  made to fail ($1): the copy did not change"; fails=1; return; fi
  if clang -std=c11 -O1 -Wall -Werror -o "$d/t" "$d/tools/test-homeaway.c" 2>/dev/null && ! "$d/t" > "$d/out"; then echo "PASS  made to fail ($1): caught ($(grep -c '^FAIL' "$d/out") case(s) fail)"
  else echo "FAIL  made to fail ($1): test-homeaway.c still passes"; fails=1; fi
}
mutc "the rule ignoring Adapt" 's/return on && !\(adapt && pointer\);/return on;/'
mutc "the rule with the pointer inverted" 's/return on && !\(adapt && pointer\);/return on \&\& !(adapt \&\& !pointer);/'
mutc "the rule ignoring the switch" 's/return on && !\(adapt && pointer\);/return !(adapt \&\& pointer);/'
[ $fails = 0 ] && echo "test-homeaway: all pass" || echo "test-homeaway: FAILED"
exit $fails
