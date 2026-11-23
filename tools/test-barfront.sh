#!/bin/bash
# Mac test of each display's own menu bar (1.8.8.2, B69, KT 21 Nov 2026: "when the agent opens an app on the ipad, ... the app name also appears on
# tv status bar, as well as its traffic lights"; KT's rule: every display's bar is its own, at full strength). Five parts:
#  1. the rule (common/BarFront.h): the iPad alone always gives 1.8.8's answer; each display otherwise its own front, Finder with none; the lights.
#  2. the real decision, cut out of statusbar/StatusBar.x (BF_SB_X: another copy, e.g. the code before the fix) and run on the Mac against a world
#     model of SpringBoard with two displays (test-barfront.m): what each copy names, its lights and the window they act on, its App menu's app, the
#     tick's signature; and the iPad alone against 1.8.8's own decision lines over a sweep of states.
#  2b. the wait before a row from another display's bar acts (its review): the real code on the Mac's main run loop against a model of the front
#     window and of SpringBoard's keyboard focus -- Edit's key presses only once the keys go to that bar's app.
#  3. the sites: the layout, the lights' tap and arrows, the tick, the menus (App, Edit, Apple, Window, Go, the apps' own), the apps' own menus' "last"
#     per display, the snapshot, the crash guard's piece and its rule.
#  4. made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${BF_SB_X:-../statusbar/StatusBar.x}; M0=../statusbar/AppMenus.h; R0=crashmap-rules.txt
fails=0

# ---- 1. the rule ----
cat > "$W/rule.c" <<'C'
#include <stdio.h>
#include "BarFront.h"
static int fails = 0, n = 0;
static void expect(int got, int want, const char *what) { n++; if (got != want) { fails++; printf("FAIL  %s (got %d)\n", what, got); } else printf("PASS  %s\n", what); }
int main(void) {
    int all = 1;
    for (int a = 0; a < 2; a++) for (int h = 0; h < 2; h++) for (int r = 0; r < 2; r++) for (long long e = 0; e < 4; e++) for (int s = 0; s < 2; s++) for (int i = 0; i < 2; i++)
        if (MSBDBarFrontWay(0, 0, a, h, r, e, s, i) != kMSBDBarFrontActive) all = 0;
    expect(all, 1, "the iPad alone: 1.8.8's answer (the active window) in all 128 states");
    // (tvUp, onTV, activeHere, homeRule, read, env, shows, activeInShown)
    expect(MSBDBarFrontWay(1, 1, 0, 1, 1, 1, 0, 0), kMSBDBarFrontNone, "KT's case: an app opened on the iPad, the TV at its empty desktop: the TV's bar Finder");
    expect(MSBDBarFrontWay(1, 0, 1, 1, 1, 3, 1, 1), kMSBDBarFrontActive, "  ... the iPad's bar: the active window, as 1.8.8");
    expect(MSBDBarFrontWay(1, 1, 0, 1, 1, 3, 1, 0), kMSBDBarFrontShown, "a window on the TV, the iPad in use: the TV's bar its own front window");
    expect(MSBDBarFrontWay(1, 1, 1, 1, 1, 3, 1, 1), kMSBDBarFrontActive, "  ... the TV in use: the active window");
    expect(MSBDBarFrontWay(1, 0, 0, 1, 1, 3, 1, 0), kMSBDBarFrontShown, "  ... the iPad's bar then: its own front window, not the TV's");
    expect(MSBDBarFrontWay(1, 0, 0, 1, 1, 1, 0, 0), kMSBDBarFrontNone, "  ... the iPad at its Home Screen: Finder");
    expect(MSBDBarFrontWay(1, 0, 1, 1, 1, 1, 0, 0), kMSBDBarFrontNone, "the iPad in use at its Home Screen with another display up (Stage Manager): Finder, not a stage it left");
    expect(MSBDBarFrontWay(1, 0, 1, 0, 1, 1, 0, 0), kMSBDBarFrontActive, "  ... the other engines (their windows over the Home Screen): 1.8.8's answer");
    expect(MSBDBarFrontWay(1, 0, 1, 1, 1, 2, 0, 0), kMSBDBarFrontActive, "  ... its App Switcher: 1.8.8's answer");
    expect(MSBDBarFrontWay(1, 1, 1, 1, 1, 1, 0, 0), kMSBDBarFrontNone, "the TV in use, its last window sent to its empty desktop: Finder");
    expect(MSBDBarFrontWay(1, 1, 1, 1, 1, 3, 1, 0), kMSBDBarFrontShown, "the TV in use, showing another stage than the active window's: that stage's front");
    expect(MSBDBarFrontWay(1, 1, 0, 1, 0, 0, 0, 0), kMSBDBarFrontRecent, "the TV's switcher unread, the iPad in use: its most recent stage drawn there");
    expect(MSBDBarFrontWay(1, 1, 1, 1, 0, 0, 0, 0), kMSBDBarFrontActive, "  ... the TV in use: the active window");
    expect(MSBDBarFrontWay(1, 0, 0, 1, 0, 0, 0, 0), kMSBDBarFrontRecent, "the iPad's switcher unread, the TV in use: the iPad's stage as its other checks read it");
    // lights (way, onTV, ownLights, window)
    expect(MSBDBarLightsFor(kMSBDBarFrontActive, 0, 0, 0), 1, "lights: the iPad's bar in use, a full-screen front: shown (every engine, as 1.8.8)");
    expect(MSBDBarLightsFor(kMSBDBarFrontActive, 0, 1, 1), 0, "  ... a window: none in the bar (its own title bar has them)");
    expect(MSBDBarLightsFor(kMSBDBarFrontShown, 1, 1, 0), 1, "  ... the TV's full-screen window, Stage Manager: on the TV's bar, acting on it (audit row 9)");
    expect(MSBDBarLightsFor(kMSBDBarFrontActive, 1, 0, 0), 0, "  ... the other engines: never on a TV's bar (their lights act on the iPad's windows)");
    expect(MSBDBarLightsFor(kMSBDBarFrontShown, 0, 0, 0), 0, "  ... the other engines: not on the iPad's bar while the TV's app is the active one (they would act on it)");
    printf("%s  rule: %d of %d\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails != 0;
}
C
clang -std=c11 -Wall -Werror -I../common -o "$W/rule" "$W/rule.c" && "$W/rule" || fails=$((fails+1))

# ---- 2. the real decision on the world model ----
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }
run() {   # run <StatusBar.x> <work dir> [quiet]: builds and runs the harness on that code; prints its output unless quiet; returns its failed checks (99: no build)
  local X=$1 d=$2 q=$3 h has
  mkdir -p "$d"
  : > "$d/barfront.inc"; has=1
  for h in 'static int DMBarFrontToday(SBApplication **app, BOOL *noLights, BOOL *native) {' 'static BOOL DMBarFrontStageHas(id stage, NSString *bundle) {' \
           '__attribute__((noinline)) static int DMBarFrontOn(UIScreen *tv, SBApplication **app, NSString **key, BOOL *noLights, BOOL *native) {' \
           'static NSString *DMBarFrontsSig(void) {' 'static SBApplication *DMBarFrontOfTitle(UIView *title, NSString **key, BOOL *other) {'; do
    if [ -n "$(fn "$X" "$h")" ]; then fn "$X" "$h" >> "$d/barfront.inc"; else has=0; fi
  done
  fn "$X" 'static NSString *DMSMFullScreenKeyIn(id stage) {' > "$d/fullkeyin.inc"
  fn "$X" 'static NSString *DMSMNewestKeyIn(id stage) {' > "$d/newestkeyin.inc"
  # (the layout's decision: after the clock balance's line, to the app's name; the lights' want; the lights' key)
  awk '/^    DMStartClockBalanceIfNeeded\(\);/ {f=1; next} f {print} f && index($0, "    NSString *appName = frontApp ?") == 1 {exit}' "$X" > "$d/decide.inc"
  grep -m1 '^    BOOL wantLights = ' "$X" > "$d/wantlights.inc"
  grep -m1 '^        lights.barKey = ' "$X" > "$d/barkey.inc"
  fn "$X" 'static void DMOpenAppMenu(UIButton *btn) {' | awk 'f && index($0, "    if (!app) { DMOpenFinderMenu(btn); return; }") == 1 {exit} f {print} /^    if \(DMTitleTapWithMenuOpen\(btn\)\) return;/ {f=1}' > "$d/appmenu.inc"
  [ -s "$d/decide.inc" ] && [ -s "$d/wantlights.inc" ] && [ -s "$d/appmenu.inc" ] && [ -s "$d/newestkeyin.inc" ] || { echo "FAIL  $X: the bar's decision lines not found"; return 99; }
  local defs="-DHAS_BARFRONT=$has -DHAS_FULLKEYIN=$([ -s "$d/fullkeyin.inc" ] && echo 1 || echo 0) -DHAS_BARKEY=$([ -s "$d/barkey.inc" ] && echo 1 || echo 0)"
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -Werror=implicit-function-declaration $defs -I"$d" \
        -framework Foundation -o "$d/t" test-barfront.m > "$d/cc.txt" 2>&1 || { cat "$d/cc.txt"; echo "FAIL  the cut-out code did not build"; return 99; }
  local out; out=$("$d/t"); local rc=$?
  [ -n "$q" ] || echo "$out"
  [ $rc = 0 ] && return 0
  return $(printf '%s\n' "$out" | grep -c '^FAIL  ')
}
run "$X0" "$W/real"; rc=$?
[ $rc = 0 ] || fails=$((fails+1))

# ---- 2b. the wait before a row from another display's bar acts ----
cat > "$W/wait.m" <<'WAITM'
// Part 2b of test-barfront.sh (1.8.8.2, B69 review): the wait before a row from another display's bar acts, cut out of StatusBar.x
// (DMBarFrontKeysTo, DMBarFrontReady, DMBarFrontWhenActiveStep, DMBarFrontWhenActive) and run on the Mac's main run loop against a model of the
// stages' front window and of SpringBoard's keyboard focus (-externalSceneWithFocus). Edit's key presses must wait for the keys too: they follow a
// window made active a moment after the front window does, and a press before that reaches the app that had them.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <stdio.h>
static NSString *gFrontKey, *gKeysApp;
static BOOL gKeysReadable = YES;
static int gActivations;
static NSMutableArray<NSString *> *gLog;
@interface TKFC : NSObject
- (id)externalSceneWithFocus;
@end
@implementation TKFC
- (id)externalSceneWithFocus { return gKeysApp; }
@end
static id DMKeyboardFocusController(void) { static TKFC *k; if (!k) k = [TKFC new]; return k; }
static BOOL MSBDFocusHas(id obj, SEL sel, NSString *types) { (void)types; return gKeysReadable && [obj respondsToSelector:sel]; }
static NSString *DMBundleOfSceneID(id scene) { return scene; }
static NSString *DMSMFrontWindowKey(void) { return gFrontKey; }
static NSString *DMSMKeyBundle(NSString *k) { NSRange r = [k rangeOfString:@"#"]; return r.location == NSNotFound ? k : [k substringToIndex:r.location]; }
static NSString *DMSMKeyText(NSString *k) { return k; }
static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMBarFrontActivate(NSString *key) { (void)key; gActivations++; return YES; }
#include "wait.inc"
#if WAIT_OLD   // (B69's first commit: no keyboard term -- the scenarios then show what it did)
#define WHEN(key, keys, blk) DMBarFrontWhenActive((key), (blk))
#else
#define WHEN(key, keys, blk) DMBarFrontWhenActive((key), (keys), (blk))
#endif

static int fails = 0, n = 0;
static void expect(BOOL ok, NSString *what) { n++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static void RunFor(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
typedef struct { int ran, ranAtOnce, activations; BOOL front, keys; NSString *log; } TOut;
// frontAt / keysAt: when the Tips window becomes the front window / its app gets the keys (0: already; < 0: never); keys: the row presses keys
static TOut Scenario(double frontAt, double keysAt, BOOL readable, BOOL keys) {
    NSString *key = @"com.t.tips#1", *tips = @"com.t.tips";
    gFrontKey = frontAt == 0 ? key : @"com.t.settings#1"; gKeysApp = keysAt == 0 ? tips : @"com.t.settings"; gKeysReadable = readable; gActivations = 0; [gLog removeAllObjects];
    if (frontAt > 0) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(frontAt * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gFrontKey = key; });
    if (keysAt > 0) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(keysAt * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gKeysApp = tips; });
    __block TOut o = {0};
    WHEN(key, keys, ^{ o.ran++; o.front = [gFrontKey isEqualToString:key]; o.keys = [gKeysApp isEqualToString:tips]; });
    o.ranAtOnce = o.ran;
    RunFor(2.2);
    o.activations = gActivations; o.log = [gLog componentsJoinedByString:@" | "];
    return o;
}
int main(void) {
    @autoreleasepool {
        gLog = [NSMutableArray array];
        TOut o = Scenario(0.15, 0.55, YES, YES);
        expect(o.ran == 1 && o.front && o.keys && o.activations == 1, [NSString stringWithFormat:@"Edit's key press from another display's bar: once, when its window is the active one AND the keys go to its app (ran %d, front %d, keys %d, asked %d)", o.ran, o.front, o.keys, o.activations]);
        o = Scenario(0.15, -1, YES, YES);
        expect(o.ran == 0 && [o.log containsString:@"its keys stayed with another app"], [NSString stringWithFormat:@"  ... the keys never come: nothing pressed, said so (ran %d: %s)", o.ran, o.log.UTF8String]);
        o = Scenario(0.15, -1, NO, YES);
        expect(o.ran == 1 && o.front, [NSString stringWithFormat:@"  ... the keyboard's focus can't be read: once the window is the active one, as the menus' keys before (ran %d, front %d)", o.ran, o.front]);
        o = Scenario(0, 0, YES, YES);
        expect(o.ran == 1 && o.ranAtOnce == 1 && o.activations == 0, [NSString stringWithFormat:@"  ... already the active window with the keys: at once, nothing asked (ran %d at once %d, asked %d)", o.ran, o.ranAtOnce, o.activations]);
        o = Scenario(0, 0.3, YES, YES);
        expect(o.ran == 1 && o.keys && o.activations == 0, [NSString stringWithFormat:@"  ... already the active window, the keys a moment later: then, nothing asked again (ran %d, keys %d, asked %d)", o.ran, o.keys, o.activations]);
        o = Scenario(0.15, -1, YES, NO);
        expect(o.ran == 1 && o.front && o.activations == 1, [NSString stringWithFormat:@"the Window menu (no keys): once its window is the active one, wherever the keys are (ran %d, front %d, asked %d)", o.ran, o.front, o.activations]);
        o = Scenario(-1, -1, YES, NO);
        expect(o.ran == 0 && [o.log containsString:@"did not become the active window: nothing done"], [NSString stringWithFormat:@"  ... never the active window: nothing done, said so (ran %d: %s)", o.ran, o.log.UTF8String]);
        printf("%s  the wait: %d of %d\n", fails ? "FAIL" : "PASS", n - fails, n);
    }
    return fails != 0;
}
WAITM
waitrun() {   # waitrun <StatusBar.x> <work dir> [quiet]: the wait's real code on the model; returns its failed checks (99: not found or no build)
  local X=$1 d=$2 q=$3 h out rc old=0
  mkdir -p "$d"; : > "$d/wait.inc"
  if [ -z "$(fn "$X" 'static int DMBarFrontKeysTo(NSString *bundle) {')" ] && [ -n "$(fn "$X" 'static void DMBarFrontWhenActive(NSString *key, dispatch_block_t action) {')" ]; then
    old=1   # (B69's first commit: the wait for the window only; run as it is, to show what it does)
    for h in 'static void DMBarFrontWhenActiveStep(NSString *key, dispatch_block_t action, int left) {' 'static void DMBarFrontWhenActive(NSString *key, dispatch_block_t action) {'; do fn "$X" "$h" >> "$d/wait.inc"; done
  else for h in 'static int DMBarFrontKeysTo(NSString *bundle) {' 'static BOOL DMBarFrontReady(NSString *key, BOOL keys) {' \
           'static void DMBarFrontWhenActiveStep(NSString *key, BOOL keys, dispatch_block_t action, int left) {' \
           'static void DMBarFrontWhenActive(NSString *key, BOOL keys, dispatch_block_t action) {'; do
    [ -n "$(fn "$X" "$h")" ] || { [ -n "$q" ] || echo "FAIL  $X: no function starting \"$h\""; return 99; }
    fn "$X" "$h" >> "$d/wait.inc"
  done; fi
  clang -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -DWAIT_OLD=$old -I"$d" -framework Foundation -o "$d/t" "$W/wait.m" > "$d/cc.txt" 2>&1 \
    || { [ -n "$q" ] || { cat "$d/cc.txt"; echo "FAIL  the wait's code did not build"; }; return 99; }
  out=$("$d/t"); rc=$?
  [ -n "$q" ] || echo "$out"
  [ $rc = 0 ] && return 0
  return $(printf '%s\n' "$out" | grep -c '^FAIL  ')
}
waitrun "$X0" "$W/wait"; wrc=$?; [ $wrc = 0 ] || fails=$((fails+1))
[ -n "$BF_SB_X" ] && { echo "test-barfront (other code $BF_SB_X): decision $([ $rc = 0 ] && echo passed || echo "FAILED ($rc)"), the wait $([ $wrc = 0 ] && echo passed || echo "FAILED ($wrc)")"; exit $([ $rc = 0 ] && [ $wrc = 0 ] && echo 0 || echo 1); }

# ---- 3. the sites ----
sites() {   # sites <StatusBar.x> <AppMenus.h> <crashmap-rules.txt> [quiet]: 0 when every site is as it must be
  local S=$1 M=$2 R=$3 q=$4 f=0
  ck() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; f=$((f+1)); fi; return 0; }
  ck "the rule is included ahead of every user, with the helpers declared there" \
    "awk '/^#include \"..\/common\/BarFront.h\"/{i=NR} /^static int DMBarFrontOn\(UIScreen \*tv, SBApplication \*\*app, NSString \*\*key, BOOL \*noLights, BOOL \*native\);/{d=NR} /^- \(void\)dm_layoutLogoBody \{/{l=NR} END{exit !(i && d > i && l > d)}' '$S' && [ \$(grep -c '^#include \"../common/BarFront.h\"' '$S') = 1 ]"
  ck "the layout: the front of the copy's own display (DMBarFrontOn), the name from it, our own windows' name on the iPad's bar only" \
    "grep -qxF '    UIScreen *barTV = DMExternalScreenOf(fg);' '$S' && grep -qxF '    int barWay = DMBarFrontOn(barTV, &frontApp, &barKey, &activeIsWindow, &barNative);' '$S' \
     && grep -qF 'NSString *appName = frontApp ? ([frontApp displayName] ?: [frontApp bundleIdentifier]) : ((barTV ? nil : DMNativeActiveAppName()) ?: @\"Finder\");' '$S' \
     && ! grep -qF 'SBApplication *frontApp = DMNativeActiveApp() ? nil : DMActiveApp();' '$S'"
  ck "  ... Finder's File and View on the iPad's bar only; the lights' frame Aerial drops from is the iPad bar's; the apps' own menus asked per display" \
    "grep -qF 'BOOL finderTitles = !barTV && DMFinderNamedInBar() && appRight > 0;' '$S' && grep -qF 'if (!barTV) { gStatusLightsFrame = lights.frame;' '$S' \
     && grep -qF 'if (amBundle) DMAMFrontSeenOn(frontApp, barTV != nil);' '$S' && grep -qF 'else if (gAMOn && !frontApp) DMAMFrontSeenOn(nil, barTV != nil);' '$S'"
  ck "the lights: another display's front carries its window's key, the tap acts on it, the arrows inward for it (no key: as before)" \
    "grep -qF 'lights.barKey = (barTV || barWay != kMSBDBarFrontActive) ? barKey : nil;' '$S' && grep -qF -e '- (void)tapped:(DMLightCell *)cell { DMBarFrontLightTap(cell.tag, self.barKey); }' '$S' \
     && grep -qF 'BOOL inward = !DMSMEngine() || self.barKey.length || DMSMFrontIsFullScreen();' '$S' \
     && fn '$S' 'static void DMBarFrontLightTap(NSInteger which, NSString *key) {' | grep -qF 'if (!key.length || !DMSMEngine()) { DMLightAction(which); return; }' \
     && fn '$S' 'static void DMBarFrontLightTap(NSInteger which, NSString *key) {' | grep -qF 'if (which == 2 ? DMSMToggleZoom(key) : (which == 0 ? DMSMRedLight(key) : DMSMWindowAction(key, @\"removeFromSet\"))) return;'"
  ck "the tick: a change of any display's front lays the bars out (empty signature with the iPad alone)" \
    "grep -qF 'NSString *bars = DMBarFrontsSig();' '$S' && grep -qF 'if (![bars isEqualToString:lastBars ?: @\"\"]) { lastBars = [bars copy]; ownChanged = YES; }' '$S' \
     && awk '/BOOL ownNow = DMWindowsOwnStatusBar\(\), ownChanged = ownNow != lastOwn;/{a=NR} /NSString \*bars = DMBarFrontsSig\(\);/{b=NR} /if \(\(frontChanged \|\| ownChanged\) && fg.window\)/{c=NR} END{exit !(a && b > a && c > b)}' '$S'"
  ck "the snapshot: each display's switcher read once per tick scope, dropped with the front window" \
    "grep -qF 'gDMSnapSMShownKnown = NO; gDMSnapSMShown = nil; DMBarFrontForget(); }' '$S' && fn '$S' 'static BOOL DMBarFrontSwitcherOn(UIScreen *screen, long long *env, id *stage) {' | grep -qF 'if (gDMSnapDepth && gDMSnapBarKnown[i] && gDMSnapBarScreen[i] == screen)' \
     && fn '$S' 'static BOOL DMBarFrontSwitcherOn(UIScreen *screen, long long *env, id *stage) {' | grep -qF -e 'id state = DMSwitcherObjCall(lc, @\"transitioningToLayoutState\") ?: DMSwitcherObjCall(lc, @\"layoutState\");' -e 'id state = going ?: DMSwitcherObjCall(lc, @\"layoutState\");' \
     && fn '$S' 'static BOOL DMBarFrontSwitcherOn(UIScreen *screen, long long *env, id *stage) {' | grep -qF 'DMSMSigOK(c, forScene, DMSMSigObjObj(), \"switcherControllerForWindowScene:\")'"
  ck "the iPad alone or the piece off: 1.8.8's answer (DMBarFrontOn, the titles' menus)" \
    "fn '$S' '__attribute__((noinline)) static int DMBarFrontOn(UIScreen *tv, SBApplication **app, NSString **key, BOOL *noLights, BOOL *native) {' | grep -qF 'if ((!tv && !DMBarFrontTV()) || DMBarFrontSkipped()) return DMBarFrontToday(app, noLights, native);' \
     && fn '$S' 'static SBApplication *DMBarFrontOfTitle(UIView *title, NSString **key, BOOL *other) {' | grep -qF 'if ((!tv && !DMBarFrontTV()) || DMBarFrontSkipped()) return DMNativeActiveApp() ? nil : DMActiveApp();' \
     && grep -qF 'static BOOL DMBarFrontSkipped(void) { static int s = -1; if (s < 0) s = MSBDCrashSkipped(MSBD_BAR_FRONT_PIECE); return s != 0; }' '$S' && grep -qF '#define MSBD_BAR_FRONT_PIECE \"barPerDisplay\"' '$S'"
  ck "the App menu: about its bar's app; Minimize that bar's own window from another display (greyed where nothing reaches it)" \
    "fn '$S' 'static void DMOpenAppMenu(UIButton *btn) {' > '$W/am' && grep -qF 'SBApplication *app = DMBarFrontOfTitle(btn, &barKey, &otherBar);' '$W/am' \
     && grep -qF 'enabled:(!otherBar || own.length) handler:DMCloseThen(^{ if (own.length) DMBarFrontMinimize(own); else DMMinimizeActiveApp(); })' '$W/am'"
  ck "the Edit menu: about its bar's app; its key presses make that bar's window active first, greyed where nothing can (set only while its rows are made)" \
    "fn '$S' 'static void DMOpenEditMenu(UIButton *btn) {' > '$W/em' && grep -qF 'NSString *activeBundle = otherBar ? [barApp bundleIdentifier] : [DMActiveApp() bundleIdentifier];' '$W/em' \
     && grep -qF 'gDMRowsBarKey = otherBar && barKey.length ? barKey : nil; gDMRowsBarStuck = otherBar && !barKey.length;' '$W/em' && grep -qF 'gDMRowsBarKey = nil; gDMRowsBarStuck = NO;' '$W/em' \
     && grep -qF 'DMNativeWindow *nw = onTV ? nil : DMNativeActiveApp();' '$W/em' \
     && fn '$S' 'static DMRow *DMShortcutRow(NSString *title, NSString *hint, BOOL enabled, uint32_t usage, BOOL shift) {' | grep -qF 'if (barKey) DMBarFrontWhenActive(barKey, YES, ^{ DMSendShortcut(usage, shift); }); else DMSendShortcut(usage, shift);' \
     && fn '$S' 'static DMRow *DMShortcutRow(NSString *title, NSString *hint, BOOL enabled, uint32_t usage, BOOL shift) {' | grep -qF 'enabled = enabled && DMHardwareKeyboardAttached() && !gDMRowsBarStuck;'"
  ck "the Apple menu's Force Quit row: the app its bar names; Go's Finder rows on the iPad's bar only" \
    "grep -qF 'SBApplication *front = DMBarFrontOfTitle(btn, &frontKey, &frontOther);' '$S' && ! fn '$S' 'static void DMOpenMenu(UIButton *btn) {' | grep -qF 'DMForceQuitTargetApp()' \
     && grep -qF 'if (DMFinderNamedInBar() && !DMExternalScreenOf(btn)) {' '$S'"
  ck "the Window menu: from another display's bar, that bar's window made active first and the menu opened once it is; greyed layouts where nothing can" \
    "fn '$S' 'static void DMOpenWindowMenu(UIButton *btn) {' > '$W/wm' && grep -qF 'if (otherBar && barKey.length) {' '$W/wm' && grep -qF 'gDMWinMenuAfterActive = YES; DMOpenWindowMenu(b); gDMWinMenuAfterActive = NO;' '$W/wm' \
     && grep -qF 'if (!b || b.hidden || !b.window || gOverlay) return;' '$W/wm' && grep -qF '&& DMActiveApp() != nil && !otherBar;' '$W/wm' && grep -qF 'if (!onTV && DMNativeActiveApp()) { DMOpenNativeWindowMenu(btn); return; }' '$W/wm' \
     && grep -qF '        DMBarFrontWhenActive(barKey, NO, ^{' '$W/wm'"
  ck "  ... on a bar that names another app than the active one (Finder there, the other engines' TV app): none of the rows about the active app's own windows (Move to Other Display, Bring All to Front, its list), as with no app" \
    "fn '$S' 'static void DMOpenWindowMenu(UIButton *btn) {' > '$W/wm2' && grep -qxF '    BOOL aboutActive = !otherBar;' '$W/wm2' \
     && [ \$(grep -cF 'if (aboutActive && DMVisibleWindowCount() > 0) [items addObject:[[DMRow alloc] initWithTitle:@\"Bring All to Front\"' '$W/wm2') = 2 ] \
     && grep -qF 'if (aboutActive && [UIScreen screens].count > 1 && active.length)' '$W/wm2' && grep -qF 'if (listed.count && aboutActive) {' '$W/wm2' \
     && ! grep -qE '^ +if \(DMVisibleWindowCount\(\) > 0\) \[items addObject' '$W/wm2'"
  ck "  ... made active as a tap makes it (the stage, that window the newest and activating), the row only once it is, at most 1.5 s, never on another window" \
    "fn '$S' 'static BOOL DMBarFrontActivate(NSString *key) {' | grep -qF 'BOOL ok = DMSMRequestStageOrderAs(stage, @{item: @(newest + 1)}, item, YES);' \
     && fn '$S' 'static void DMBarFrontWhenActive(NSString *key, BOOL keys, dispatch_block_t action) {' | grep -qF 'DMBarFrontWhenActiveStep([key copy], keys, [action copy], 15);' \
     && fn '$S' 'static void DMBarFrontWhenActive(NSString *key, BOOL keys, dispatch_block_t action) {' | grep -qF 'if (![DMSMFrontWindowKey() isEqualToString:key] && !DMBarFrontActivate(key)) return;' \
     && fn '$S' 'static void DMBarFrontWhenActiveStep(NSString *key, BOOL keys, dispatch_block_t action, int left) {' | grep -qF 'if (DMBarFrontReady(key, keys)) { action(); return; }' \
     && fn '$S' 'static void DMBarFrontWhenActiveStep(NSString *key, BOOL keys, dispatch_block_t action, int left) {' | grep -qF 'did not become the active window%@: nothing done\"' \
     && [ \$(fn '$S' 'static void DMBarFrontWhenActiveStep(NSString *key, BOOL keys, dispatch_block_t action, int left) {' | grep -c 'action()') = 1 ]"
  ck "  ... Edit's key presses only once the keys go to that bar's app too (SpringBoard's focus, checked: -externalSceneWithFocus), the Window menu without" \
    "fn '$S' 'static BOOL DMBarFrontReady(NSString *key, BOOL keys) {' | grep -qF 'return [DMSMFrontWindowKey() isEqualToString:key] && (!keys || DMBarFrontKeysTo(DMSMKeyBundle(key)) != 0);' \
     && fn '$S' 'static int DMBarFrontKeysTo(NSString *bundle) {' | grep -qF 'if (!MSBDFocusHas(kfc, s, @\"@@:\")) return -1;' \
     && fn '$S' 'static int DMBarFrontKeysTo(NSString *bundle) {' | grep -qF 'return bundle.length && [fb isEqualToString:bundle] ? 1 : 0;'"
  ck "the apps' own menus: one \"last\" per display (two bars, two apps: no ask at every layout), the menu about its bar's app" \
    "fn '$M' 'static void DMAMFrontSeenOn(SBApplication *app, int display) {' > '$W/fs' && grep -qF 'NSString * __strong *last = &gAMBarLast[display ? 1 : 0];' '$W/fs' && grep -qF 'if (!bundle.length) { *last = nil; return; }' '$W/fs' \
     && ! grep -q '^static void DMAMFrontSeen(SBApplication \*app)' '$M' && fn '$M' 'static void DMOpenAppOwnMenu(UIButton *btn) {' | grep -qF 'NSString *bundle = [(otherBar ? barApp : DMActiveApp()) bundleIdentifier];'"
  ck "  ... asked again (its word, a thin answer, menuschanged, a tap) while it is the active app or, with another display up, on a display's bar (its review: B12's late titles there)" \
    "fn '$M' 'static BOOL DMAMInFront(NSString *b) {' | grep -qF 'return b.length && DMBarFrontTV() && ([gAMBarLast[0] isEqualToString:b] || [gAMBarLast[1] isEqualToString:b]);' \
     && [ \$(grep -cF 'DMAMInFront(b)' '$M') = 4 ] && [ \$(grep -cF '[[DMActiveApp() bundleIdentifier] isEqualToString:b]' '$M') = 1 ]"
  ck "the crash guard: the piece barPerDisplay, a rule naming the functions (with the display in use's, B81)" \
    "grep -qxF \"target barPerDisplay piece the menu bar with another display|each display's own menu bar\" '$R' && grep -qxF 'sym MacStatusBarCore ^_*(DMBarFront(On|Today|TV|SwitcherOn|StageHas|OfTitle|sSig|Forget|Skipped|Activate|WhenActive|WhenActiveStep|KeysTo|KeysHolder|Ready|LightTap|Minimize|InUse[A-Za-z]+)|MSBDBarFrontWay|MSBDBarLightsFor|MSBDInUse[A-Za-z]+|MSBDShownStageGone)(_block_invoke(_[0-9]+)?(\\.[0-9]+)?)?\$ barPerDisplay' '$R'"
  return $f
}
sites "$X0" "$M0" "$R0"; s=$?
[ $s = 0 ] || fails=$((fails+1))

# ---- 4. made-to-fail copies ----
echo "-- made-to-fail copies (each must fail)"
k=0
mtf() {   # mtf <what> <sbx|amh|rules> <perl expression>
  local d="$W/m$((++k))" X=$X0 M=$M0 R=$R0 c n wn
  mkdir -p "$d"
  case $2 in sbx) c="$d/StatusBar.x"; perl -0pe "$3" "$X0" > "$c"; X=$c; cmp -s "$c" "$X0";;
             amh) c="$d/AppMenus.h"; perl -0pe "$3" "$M0" > "$c"; M=$c; cmp -s "$c" "$M0";;
             rules) c="$d/rules.txt"; perl -0pe "$3" "$R0" > "$c"; R=$c; cmp -s "$c" "$R0";; esac
  [ $? = 0 ] && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=$((fails+1)); return; }
  n=0
  if [ "$2" = sbx ]; then run "$X" "$d/w" q; n=$?; [ $n = 99 ] && n=0; fi
  if [ "$2" = sbx ] && ! cmp -s <(for h in 'static int DMBarFrontKeysTo(' 'static BOOL DMBarFrontReady(' 'static void DMBarFrontWhenActiveStep(' 'static void DMBarFrontWhenActive('; do fn "$X" "$h"; done) "$W/wait/wait.inc"; then
    waitrun "$X" "$d/w2" q; wn=$?; [ $wn = 99 ] && wn=1; n=$((n + wn))   # (the wait's code changed: its scenarios too)
  fi
  sites "$X" "$M" "$R" q; n=$((n + $?))
  if [ $n -gt 0 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; fails=$((fails+1)); fi
}
mtf "the layout takes 1.8.8's one answer for every copy" sbx 's/int barWay = DMBarFrontOn\(barTV, /int barWay = DMBarFrontOn(nil, /'
mtf "no copy is ever on another display (the iPad's answer everywhere)" sbx 's/if \(\(!tv && !DMBarFrontTV\(\)\) \|\| DMBarFrontSkipped\(\)\) return DMBarFrontToday\(app, noLights, native\);   \/\/ \(the iPad alone, or the piece off\)/if (1) return DMBarFrontToday(app, noLights, native);/'
mtf "the iPad alone through the per-display path (not 1.8.8's answer)" sbx 's/if \(\(!tv && !DMBarFrontTV\(\)\) \|\| DMBarFrontSkipped\(\)\) return DMBarFrontToday\(app, noLights, native\);   \/\/ \(the iPad alone, or the piece off\)/if (DMBarFrontSkipped()) return DMBarFrontToday(app, noLights, native);/'
mtf "the active window's display taken as every copy's own" sbx 's/activeHere = onTV \? \(at && \[at isEqual:DMSMIdentityOfScreen\(tv\)\]\) : DMSMIsMainIdentity\(at\);/activeHere = YES;/'
mtf "a display's own switcher never read" sbx 's/BOOL read = DMBarFrontSwitcherOn\(onTV \? tv : \[UIScreen mainScreen\], &env, &shown\);/BOOL read = NO;/'
mtf "the iPad's Home Screen not Finder (the stage it left named)" sbx 's/int way = MSBDBarFrontWay\(YES, onTV, activeHere, sm, read, env, shows, activeInShown\);/int way = MSBDBarFrontWay(YES, onTV, activeHere, NO, read, env, shows, activeInShown);/'
mtf "the TV's front window's lights never (audit row 9 again)" sbx 's/\*noLights = !MSBDBarLightsFor\(way, onTV, YES, !\(full.length && \[full isEqualToString:k\]\)\);/*noLights = YES;/'
mtf "the lights act on the active window wherever they are" sbx 's/lights.barKey = \(barTV \|\| barWay != kMSBDBarFrontActive\) \? barKey : nil;/lights.barKey = nil;/'
mtf "the other engines' TV bar with lights" sbx 's/\*app = a; \*noLights = !MSBDBarLightsFor\(way, onTV, NO, NO\);/*app = a; *noLights = NO;/'
mtf "the App menu about the active app" sbx 's/SBApplication \*app = DMBarFrontOfTitle\(btn, &barKey, &otherBar\);/SBApplication *app = DMNativeActiveApp() ? nil : DMActiveApp();/'
mtf "the tick lays the bars out only for the active app" sbx 's/if \(!\[bars isEqualToString:lastBars \?: @""\]\) \{ lastBars = \[bars copy\]; ownChanged = YES; \}/(void)bars;/'
mtf "the tick's signature never empty with the iPad alone" sbx 's/if \(!tv \|\| DMBarFrontSkipped\(\)\) return @"";/if (DMBarFrontSkipped()) return @"";/'
mtf "Edit's key presses straight to the active app from another display's bar" sbx 's/if \(barKey\) DMBarFrontWhenActive\(barKey, (YES, )?\^\{ DMSendShortcut\(usage, shift\); \}\); else //'
mtf "the Window menu opened at once from another display's bar" sbx 's/    if \(otherBar && barKey.length\) \{/    if (0) {/'
mtf "a row run after the wait whatever is active" sbx 's/    if \(left <= 0\) \{ DMLog\(\[NSString stringWithFormat:\@"\[barfront\] %\@ did not become the active window%\@: nothing done"[^\n]*\]\); return; \}/    if (left <= 0) { action(); return; }/'
mtf "the snapshot not dropped with the front window" sbx 's/ DMBarFrontForget\(\); \}/ }/'
mtf "one \"last\" for every display's bar" amh 's/NSString \* __strong \*last = &gAMBarLast\[display \? 1 : 0\];/NSString * __strong *last = \&gAMBarLast[0];/'
mtf "Edit's key presses once the window is active, wherever the keys are (its review)" sbx 's/if \(barKey\) DMBarFrontWhenActive\(barKey, YES, /if (barKey) DMBarFrontWhenActive(barKey, NO, /'
mtf "the wait never looks at the keyboard (its review)" sbx 's/ && \(!keys \|\| DMBarFrontKeysTo\(DMSMKeyBundle\(key\)\) != 0\);/;/'
mtf "the Window menu's rows about the active app's windows on a bar that names another (its review)" sbx 's/    BOOL aboutActive = !otherBar;/    BOOL aboutActive = YES;/'
mtf "the apps' own menus asked again only for the active app (its review)" amh 's/    return b\.length && DMBarFrontTV\(\) && /    return NO \&\& b.length \&\& DMBarFrontTV() \&\& /'
mtf "the crash guard's piece without its rule" rules 's/^sym MacStatusBarCore \^_\*\(DMBarFront\(On[^\n]* barPerDisplay\n//m'
echo "test-barfront: $([ $fails = 0 ] && echo "all passed" || echo "$fails part(s) FAILED")"
exit $([ $fails = 0 ] && echo 0 || echo 1)
