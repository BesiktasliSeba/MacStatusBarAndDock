#!/bin/bash
# Mac test of the display in use with another display up and the TV desktop's empty state (1.8.8.2, B81 and B86; KT: "as on a Mac with two
# displays: the app you last touched or clicked is the active one, on either display"). Four parts:
#  1. the rules (common/DisplayInUse.h): the state's sequences of the device rows, the way to the active window's stage, a gone stage.
#  2. the real code, cut out of statusbar/StatusBar.x (DI_SB_X: another copy, e.g. the code before the fix) and run on the Mac against a world model of
#     SpringBoard with a TV (test-displayinuse.m): the active window after each step of rows T3, T4, T5, T6, T7b, the keys asked back, a TV unplugged,
#     the crash guard's piece off, and the iPad alone against 1.8.8.1.1's own lines over a sweep of states.
#  3. the sites: every user's bring-forward and click, the actions from the other display's bar, the bars' display in use, the active window's
#     stage, the gone stage of a display's switcher, the TV's empty desktop first for its last window, the TV's auto-hide from its system gestures
#     window, an open menu over a Finder window, the crash guard's rule.
#  4. made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${DI_SB_X:-../statusbar/StatusBar.x}; P0=../statusbar/PointerRegion.h; N0=../statusbar/NativeWindow.h; R0=crashmap-rules.txt
fails=0

# ---- 1. the rules ----
cat > "$W/rule.c" <<'C'
#include <stdio.h>
#include "DisplayInUse.h"
static int fails = 0, n = 0;
static void expect(int got, int want, const char *what) { n++; if (got != want) { fails++; printf("FAIL  %s (got %d)\n", what, got); } else printf("PASS  %s\n", what); }
int main(void) {
    MSBDInUseState s = {0};
    // (sig numbers: what SpringBoard's most recent stage is; d its display; shown; time)
    expect(MSBDInUseFirst(&s, 1, 1, 1, 10.0), 1, "the first reading takes the most recent stage's display (the TV's), as 1.8.8.1");
    expect(s.inUse, 1, "  ... the TV in use");
    expect(MSBDInUseUser(&s, 0, 1, 11.0), 1, "T3: a click on the iPad's window in front there (no transition): the iPad in use");
    expect(MSBDInUseFirst(&s, 1, 1, 1, 12.0), 0, "  ... SpringBoard's order unchanged: still the iPad");
    expect(s.inUse, 0, "  ... in use: the iPad");
    expect(MSBDInUseFirst(&s, 2, 1, 1, 13.0), 1, "a launch on the TV later (a new front window there, shown): the TV");
    // T4
    s = (MSBDInUseState){0};
    MSBDInUseFirst(&s, 5, 0, 1, 20.0);
    MSBDInUseBarAction(&s, 1, 21.0);
    expect(MSBDInUseHeld(&s, 6, 1, 1, 21.3), 1, "T4: that reading is a held one (its app may have taken the keys: they go back)");
    expect(MSBDInUseFirst(&s, 6, 1, 1, 21.3), 0, "T4: the TV bar's green (its transition makes the TV's stage first): held, the iPad stays in use");
    expect(MSBDInUseHeld(&s, 6, 1, 1, 21.5), 0, "  ... the same stage read again: no new held reading");
    expect(MSBDInUseFirst(&s, 6, 1, 1, 25.0), 0, "  ... after the hold, the same stage: still the iPad");
    expect(s.inUse, 0, "  ... in use: the iPad");
    MSBDInUseState t = {0}; MSBDInUseFirst(&t, 5, 0, 1, 20.0);
    expect(MSBDInUseHeld(&t, 6, 1, 1, 21.3), 0, "  (without the hold: not a held reading ...");
    expect(MSBDInUseFirst(&t, 6, 1, 1, 21.3), 1, "  ... the TV would have taken it: 1.8.8.1.1's fault)");
    // T6
    s = (MSBDInUseState){0};
    MSBDInUseFirst(&s, 5, 0, 1, 30.0);
    MSBDInUseBarAction(&s, 1, 31.0);
    expect(MSBDInUseHeld(&s, 7, 1, 0, 31.4), 0, "T6: a hidden stage first while held: not a held reading (its app takes no keys)");
    expect(MSBDInUseFirst(&s, 7, 1, 0, 31.4), 0, "T6: Minimize from the TV bar: its hidden stage first, not shown: the iPad stays in use");
    expect(MSBDInUseFirst(&s, 7, 1, 0, 40.0), 0, "  ... after the hold: a minimized window's stage first is not an activation");
    expect(MSBDInUseFirst(&s, 12, 1, 1, 41.0), 1, "  ... once shown there (brought back: shown, a new one): the TV");
    // T7b
    s = (MSBDInUseState){0};
    MSBDInUseFirst(&s, 5, 0, 1, 50.0);
    MSBDInUseFollow(&s);
    expect(MSBDInUseFirst(&s, 8, 1, 1, 50.2), 1, "T7b: Tips opened cold on the TV: the TV");
    expect(MSBDInUseUser(&s, 0, 8, 51.3), 1, "  ... a tap on the iPad's Settings window 1.1 s later: the iPad");
    s = (MSBDInUseState){0};
    MSBDInUseFirst(&s, 5, 0, 1, 60.0);
    MSBDInUseUser(&s, 0, 5, 60.1);
    expect(MSBDInUseHeld(&s, 9, 1, 1, 60.4), 1, "  ... a TV launch landing 0.3 s after the tap: a held reading");
    expect(MSBDInUseHeld(&s, 9, 0, 1, 60.4), 0, "  ... (a new stage on the display in use itself: not one)");
    expect(MSBDInUseFirst(&s, 9, 1, 1, 60.4), 0, "  ... a TV launch landing 0.3 s after the tap: held, the iPad stays");
    expect(MSBDInUseFirst(&s, 9, 1, 1, 70.0), 0, "  ... and later: the same stage, still the iPad");
    s = (MSBDInUseState){0};
    MSBDInUseFirst(&s, 5, 0, 1, 60.0);
    MSBDInUseUser(&s, 0, 5, 60.1); MSBDInUseFollow(&s);
    expect(MSBDInUseFirst(&s, 9, 1, 1, 60.4), 1, "an app's icon tapped right after a touch: its launch is followed (no hold)");
    // T5 / B86
    s = (MSBDInUseState){0};
    MSBDInUseFirst(&s, 5, 0, 1, 80.0);
    expect(MSBDInUseFirst(&s, 10, 1, 0, 90.0), 0, "T5: the TV's stage taken out, an older hidden TV stage first: not an activation");
    expect(MSBDInUseFirst(&s, 0, 0, 1, 91.0), 0, "no stage at all: nothing changes");
    MSBDInUseForget(&s);
    expect(MSBDInUseFirst(&s, 11, 1, 0, 92.0), 1, "forgotten (a display came or went): the next reading starts afresh (1.8.8.1's rule)");
    // the stage's way
    expect(MSBDInUseWay(0, 0, 1), kMSBDInUseWayRecent, "way: the iPad alone or the piece off: 1.8.8.1's rule");
    expect(MSBDInUseWay(1, 0, 0), kMSBDInUseWayRecent, "way: the iPad in use, its stage the most recent: 1.8.8.1's rule");
    expect(MSBDInUseWay(1, 0, 1), kMSBDInUseWayIPad, "way: the iPad in use, the TV's stage the most recent: the stage the iPad shows");
    expect(MSBDInUseWay(1, 1, 0), kMSBDInUseWayOther, "way: the TV in use: the stage the TV shows");
    expect(MSBDInUseWay(1, 1, 1), kMSBDInUseWayOther, "way: the TV in use, its stage the most recent: the stage the TV shows (none at its empty desktop)");
    // B86: a gone stage
    expect(MSBDShownStageGone(1, 0, 0), 1, "B86: a settled state naming a stage no longer in the model, none of its windows there: gone (its empty desktop)");
    expect(MSBDShownStageGone(0, 0, 0), 0, "  ... a transition's stage (on its way in): as it is");
    expect(MSBDShownStageGone(1, 1, 0), 0, "  ... one of the model's stages: as it is");
    expect(MSBDShownStageGone(1, 0, 1), 0, "  ... a copy of a stage whose windows are drawn there (our own model change): as it is");
    printf("%s  rules: %d of %d\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails != 0;
}
C
clang -std=c11 -Wall -Werror -I../common -o "$W/rule" "$W/rule.c" && "$W/rule" || fails=$((fails+1))

# ---- 2. the real code on the world model ----
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }
run() {   # run <StatusBar.x> <work dir> [quiet]: builds and runs the harness on that code; prints its output unless quiet; returns its failed checks (99: no build)
  local X=$1 d=$2 q=$3 h has
  mkdir -p "$d"
  : > "$d/inuse.inc"; has=1
  for h in 'static UIScreen *DMBarFrontInUseScreen(id identity) {' 'static unsigned long long DMBarFrontInUseSig(id first, BOOL shown, int *d) {' \
           'static BOOL DMBarFrontInUseShown(id stage) {' 'static BOOL DMBarFrontInUseAbout(id identity) {' \
           '__attribute__((noinline)) static int DMBarFrontInUseRead(id first, id *other) {' \
           'static id DMBarFrontInUseIdentity(void) {' '__attribute__((noinline)) static id DMBarFrontInUseStage(id first, int *way) {' \
           '__attribute__((noinline)) static void DMBarFrontInUseUser(id identity, NSString *why) {' \
           'static void DMBarFrontInUseKeysBack(NSString *acted, int left) {' '__attribute__((noinline)) static void DMBarFrontInUseBarAction(NSString *key) {'; do
    if [ -n "$(fn "$X" "$h")" ]; then fn "$X" "$h" >> "$d/inuse.inc"; else has=0; fi
  done
  grep -m1 '^static void DMBarFrontInUseFollow(void) {' "$X" >> "$d/inuse.inc" || has=0
  fn "$X" 'static void DMBarFrontInUseKeysStep(NSString *acted, int left, int asks) {' >> "$d/inuse.inc"   # (1.8.8.2: the keys read and asked in steps; none before)
  fn "$X" 'static id DMSMInUseStageNow(void) {' > "$d/stagenow.inc"; [ -s "$d/stagenow.inc" ] || has=0
  fn "$X" 'static NSString *DMSMNewestKeyIn(id stage) {' > "$d/newestkeyin.inc"
  fn "$X" 'static NSString *DMSMNewestKeyNow(void) {' > "$d/newestnow.inc"
  fn "$X" 'static NSString *DMSMFrontWindowKeyNow(void) {' > "$d/frontkey.inc"
  [ -s "$d/newestkeyin.inc" ] && [ -s "$d/newestnow.inc" ] && [ -s "$d/frontkey.inc" ] || { echo "FAIL  $X: the active window's lines not found"; return 99; }
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -Werror=implicit-function-declaration -DHAS_INUSE=$has -I"$d" \
        -framework Foundation -o "$d/t" test-displayinuse.m > "$d/cc.txt" 2>&1 || { cat "$d/cc.txt"; echo "FAIL  the cut-out code did not build"; return 99; }
  local out; out=$("$d/t"); local rc=$?
  [ -n "$q" ] || echo "$out"
  [ $rc = 0 ] && return 0
  local nf; nf=$(printf '%s\n' "$out" | grep -c '^FAIL')
  return $(( nf > 0 ? nf : 1 ))
}
run "$X0" "$W/now" || fails=$((fails+1))

# ---- 3. the sites ----
site() { if grep -Eq -- "$2" "$3"; then echo "PASS  site: $1"; else echo "FAIL  site: $1"; fails=$((fails+1)); fi; }
body() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }
body "$X0" 'static void DMSMBringToFront(NSString *key) {' > "$W/bring.txt"
site "a window brought forward (a tap, a click, its title bar, Dock icon, Command-Tab, the Mac Switcher, Spotlight, the Window menu) makes its display the one in use, before the in-front return" \
  'DMBarFrontInUseUser\(DMSMStageDisplayIdentity\(stage\), @"a window brought forward"\);' "$W/bring.txt"
awk '/DMBarFrontInUseUser\(DMSMStageDisplayIdentity\(stage\)/ {u=NR} /in front already, alone/ {r=NR} END {exit !(u && r && u < r)}' "$W/bring.txt" && echo "PASS  site: ... ahead of 'in front already'" || { echo "FAIL  site: the bring-forward's display in use comes after its in-front return"; fails=$((fails+1)); }
body "$X0" 'static BOOL DMSMAddToStage(NSString *bundle, UIView *from) {' > "$W/add.txt"
site "an app's icon tapped lets go of a hold (its transition is the user's)" '^    DMBarFrontInUseFollow\(\);' "$W/add.txt"
site "an app's icon tapped with its window in the stage its display shows: that display in use" 'if \(\[inStage containsObject:bundle\] && \(main \? \(al && \[al isEqual:DMSMShownMainStage\(\)\]\) : DMSMStageShownOnDisplay\(al, identity\)\)\) DMBarFrontInUseUser\(identity,' "$W/add.txt"
awk '/its app.s icon tapped there/ {u=NR} /is not in the front stage/ {r=NR} END {exit !(u && r && u < r)}' "$W/add.txt" && echo "PASS  site: ... before the 'app in front is not in the front stage' way out" || { echo "FAIL  site: the icon's display in use comes after a way out"; fails=$((fails+1)); }
body "$X0" '__attribute__((noinline)) static void DMBarFrontInUseUser(id identity, NSString *why) {' > "$W/user.txt"
site "the keys go with a window made active, wherever they are (not the window active before: a transition may have made the state read it first)" '^    DMBarFrontInUseKeysBack\(nil, 20\);' "$W/user.txt"
awk '/^    DMBarFrontInUseKeysBack\(nil, 20\);/ {u=NR} /^    if \(!changed\) return;/ {r=NR} END {exit !(u && r && u < r)}' "$W/user.txt" && echo "PASS  site: ... also when the display in use was already that one" || { echo "FAIL  site: the keys follow only a change of the display in use"; fails=$((fails+1)); }
body "$X0" 'static void DMBarFrontInUseKeysStep(NSString *acted, int left, int asks) {' > "$W/step.txt"
site "the keys: read again after each ask (asked again while they stay), 3 asks at most" 'if \(asked && left > 1\) DMBarFrontInUseKeysStep\(acted, left - 1, asks - 1\);' "$W/step.txt"
site "the keys: nothing asked while SpringBoard holds them or one of our menus is open" 'if \(!holder.length \|\| gOverlay \|\| \(xb.length && !\[holder isEqualToString:xb\]\)\)' "$W/step.txt"
body "$X0" '__attribute__((noinline)) static int DMBarFrontInUseRead(id first, id *other) {' > "$W/read.txt"
site "a transition the hold keeps: its reading told apart before the state takes it" 'BOOL held = MSBDInUseHeld\(&gDMInUse, sig, d, shown, now\);' "$W/read.txt"
site "... the keys its app may have taken asked back" 'if \(k.length\) DMBarFrontInUseKeysBack\(k, 3\);' "$W/read.txt"
body "$X0" 'static BOOL DMBarFrontActivate(NSString *key) {' > "$W/act.txt"
site "a window made active from its display's bar: its display in use" 'if \(ok\) DMBarFrontInUseUser\(DMSMStageDisplayIdentity\(stage\),' "$W/act.txt"
body "$X0" 'static void DMSMFullScreenActivate(NSString *key) {' > "$W/full.txt"
site "a full-screen window tapped behind the windows: its display in use" 'DMBarFrontInUseUser\(DMSMStageDisplayIdentity\(DMSMStageOf\(key\)\)' "$W/full.txt"
site "the pointer's click goes through SpringBoard's touches hook" 'DMSMActivateOnTouch\(event\); DMSMStripTouch\(event\); DMBarFrontInUsePress\(event\);' "$X0"
body "$X0" '__attribute__((noinline)) static void DMBarFrontInUsePress(UIEvent *event) {' > "$W/press.txt"
site "a click: the pointer's only (a finger's tap at its lift), as it begins" 'x.type != UITouchTypeIndirectPointer \|\| x.phase != UITouchPhaseBegan' "$W/press.txt"
site "a click: not on the menu bar, not in an App Switcher or the Mac Switcher" 'DMSwitcherVisible\(\) \|\| gMSWOpen \|\| gMSWSwitching \|\| DMSMScreenPointOnMenuBar\(p, screen\)' "$W/press.txt"
site "a click: not on our title bar (its lights act without making the window active)" 'isKindOfClass:\[DMSMTitleBar class\]\]\) return;' "$W/press.txt"
site "a click: in a window card only" 'if \(!DMSMCardKey\(DMSMCardOfView\(hit\)\).length\) return;' "$W/press.txt"
site "a click: nothing with the iPad alone" '^        if \(DMBarFrontSkipped\(\) \|\| DMDispScreens\(\).count < 2\) return;' "$W/press.txt"
body "$X0" 'static void DMBarFrontLightTap(NSInteger which, NSString *key) {' > "$W/light.txt"
site "the other display's bar's lights hold the display in use, before they act" 'DMBarFrontInUseBarAction\(key\);' "$W/light.txt"
body "$X0" 'static void DMBarFrontMinimize(NSString *key) {' > "$W/min.txt"
site "the other display's bar's Minimize holds it" 'DMBarFrontInUseBarAction\(key\);' "$W/min.txt"
site "the App menu's Force Quit from the other display's bar holds it" 'if \(own.length\) DMBarFrontInUseBarAction\(own\); DMForceQuit\(app\);' "$X0"
site "the Apple menu's Force Quit from the other display's bar holds it" 'if \(front && frontOther && frontKey.length\) DMBarFrontInUseBarAction\(frontKey\); if \(front\) DMForceQuit\(front\);' "$X0"
body "$X0" '__attribute__((noinline)) static int DMBarFrontOn(UIScreen *tv, SBApplication **app, NSString **key, BOOL *noLights, BOOL *native) {' > "$W/on.txt"
site "the bars' display in use is the state's (not the most recent stage's)" 'id at = DMBarFrontInUseIdentity\(\);' "$W/on.txt"
body "$X0" 'static NSString *DMSMFrontWindowKeyNow(void) {' > "$W/front.txt"
site "the active window: the stage of the display in use" 'id stage = DMSMInUseStageNow\(\);' "$W/front.txt"
body "$X0" 'static NSString *DMSMNewestKeyNow(void) {' > "$W/newest.txt"
site "the window in front (a full-screen window made active behind windows): the same stage" 'id stage = DMSMInUseStageNow\(\);' "$W/newest.txt"
body "$X0" 'static BOOL DMBarFrontSwitcherOn(UIScreen *screen, long long *env, id *stage) {' > "$W/sw.txt"
site "a display's switcher: settled is its layout state's, not a transition's" 'if \(DMSMHomeStateOf\(state, &e, &st\)\) \{ read = YES; settled = going == nil; break; \}' "$W/sw.txt"
site "a display's switcher: a gone stage is shown nowhere" 'if \(MSBDShownStageGone\(settled, inModel, !inModel && DMSMStageShownOnDisplay\(st, DMSMIdentityOfScreen\(screen\)\)\)\) st = nil;' "$W/sw.txt"
body "$X0" 'static BOOL DMSMWindowActionAs(NSString *key, NSString *name, BOOL users) {' > "$W/wa.txt"
site "the TV desktop's last window: its empty desktop first, then the stage taken out (tools/test-tvemptyfirst)" '^        if \(DMSMTVEmptyFirst\(ownIdentity, ownItem, wk\)\) return YES;' "$W/wa.txt"
body "$X0" '__attribute__((noinline)) static BOOL DMSMTVEmptyFirst(id identity, id item, NSString *wk) {' > "$W/empty.txt"
site "... nothing with the per-display bar's piece off (its functions read the TV's state; review 1.8.8.2)" '^    if \(DMBarFrontSkipped\(\)\) return NO;' "$W/empty.txt"
awk '/if \(DMBarFrontSkipped\(\)\) return NO;/ {u=NR} /DMMSWSMRequestEmpty\(identity,/ {r=NR} END {exit !(u && r && u < r)}' "$W/empty.txt" && echo "PASS  site: ... before anything is asked" || { echo "FAIL  site: the TV's empty desktop asked before the piece's off switch"; fails=$((fails+1)); }
site "... the Mac Switcher's empty desktop of the TV" 'DMMSWSMRequestEmpty\(identity,' "$W/empty.txt"
site "the TV's system gestures window's hover feeds the TV's auto-hide" 'if \(learn\) DMAutoHideTVSystemHover\(g, inside\);' "$P0"
site "the pointer seen on the iPad is off the TV's bar" 'if \(inside\) DMAutoHideTVPointerOnIPad\(\);' "$P0"
body "$X0" '__attribute__((noinline)) static void DMAutoHideTVSystemHover(UIHoverGestureRecognizer *g, BOOL inside) {' > "$W/tvh.txt"
site "... from the top edge to the bar's bottom: on the bar (the TV's points)" 'BOOL onBar = p.y >= -1.0 && p.y <= DMTVBarHeight\(\);' "$W/tvh.txt"
site "... the TV's own display only, while its auto-hide is on" 'if \(!inside \|\| !gDMTVBarAH.on\) return;' "$W/tvh.txt"
site "... the state's pointer" 'MSBDBarAHPointer\(&gDMTVBarAH, onBar, CACurrentMediaTime\(\)\);' "$W/tvh.txt"
body "$N0" '__attribute__((noinline)) static void DMNativeTouchBegan(UITouch *t) {' > "$W/native.txt"
site "an open menu over a Finder window takes the touch before any window is made active" 'if \(overlayHost && overlayHost != gNativeLayer && \(overlayHost.screen \?: \[UIScreen mainScreen\]\) == \(t.window.screen \?: \[UIScreen mainScreen\]\)\) \{' "$W/native.txt"
awk '/overlayHost && overlayHost != gNativeLayer/ {u=NR} /UIView \*hit = DMNativeLayerHitTest/ {r=NR} END {exit !(u && r && u < r)}' "$W/native.txt" && echo "PASS  site: ... before the hit test" || { echo "FAIL  site: the open menu's check comes after the hit test"; fails=$((fails+1)); }
grep -Fq 'LightTap|Minimize|InUse[A-Za-z]+)|MSBDBarFrontWay|MSBDBarLightsFor|MSBDInUse[A-Za-z]+|MSBDShownStageGone)' "$R0" && grep -q ' barPerDisplay$' "$R0" \
  && echo "PASS  site: the crash guard's rule names the display in use's functions (barPerDisplay)" || { echo "FAIL  site: the crash guard's rule"; fails=$((fails+1)); }
for f in DMBarFrontInUseRead DMBarFrontInUseStage DMBarFrontInUseUser DMBarFrontInUseBarAction DMBarFrontInUsePress DMAutoHideTVSystemHover DMAutoHideTVPointerOnIPad; do
  grep -q "^__attribute__((noinline)) static [a-z ]*\*\{0,1\}$f(" "$X0" && echo "PASS  site: $f is a function of its own (its own frame, the crash map's name)" || { echo "FAIL  site: $f inlined"; fails=$((fails+1)); }
done

# ---- 4. made-to-fail copies ----
mtf() {   # mtf <what> <file key> <perl substitution>: the fix with that part taken out must fail (in the harness or in a site check)
  local what=$1 key=$2 sub=$3 f d
  case $key in sbx) f=$X0;; ptr) f=$P0;; nat) f=$N0;; esac
  d=$W/mtf$RANDOM; mkdir -p "$d"
  perl -0pe "$sub" "$f" > "$d/copy"
  if cmp -s "$d/copy" "$f"; then echo "FAIL  made-to-fail: the copy is unchanged: $what"; fails=$((fails+1)); return; fi
  local caught=0
  if [ $key = sbx ]; then run "$d/copy" "$d/h" quiet; [ $? = 0 ] || caught=1; fi
  if [ $caught = 0 ]; then   # (the sites on the copy)
    local pat
    while IFS= read -r pat; do [ -n "$pat" ] && ! grep -Eq -- "$pat" "$d/copy" && caught=1; done <<'PATS'
DMBarFrontInUseUser\(DMSMStageDisplayIdentity\(stage\), @"a window brought forward"\);
DMSMActivateOnTouch\(event\); DMSMStripTouch\(event\); DMBarFrontInUsePress\(event\);
if \(own.length\) DMBarFrontInUseBarAction\(own\); DMForceQuit\(app\);
id at = DMBarFrontInUseIdentity\(\);
if \(DMSMTVEmptyFirst\(ownIdentity, ownItem, wk\)\) return YES;
if \(learn\) DMAutoHideTVSystemHover\(g, inside\);
if \(overlayHost && overlayHost != gNativeLayer
PATS
    case $key in sbx) grep -q 'DMBarFrontInUseBarAction(key);   // (B81: the transition' "$d/copy" && grep -q 'DMBarFrontInUseBarAction(key);   // (B81: as the lights' "$d/copy" || caught=1
                     grep -q 'MSBDShownStageGone(settled, inModel' "$d/copy" || caught=1
                     body "$d/copy" '__attribute__((noinline)) static BOOL DMSMTVEmptyFirst(id identity, id item, NSString *wk) {' | grep -q '^    if (DMBarFrontSkipped()) return NO;' || caught=1;;
    esac
  fi
  [ $caught = 1 ] && echo "PASS  made-to-fail caught: $what" || { echo "FAIL  made-to-fail NOT caught: $what"; fails=$((fails+1)); }
}
mtf "a window brought forward leaves the display in use as it was" sbx 's/    DMBarFrontInUseUser\(DMSMStageDisplayIdentity\(stage\), @"a window brought forward"\);\n//'
mtf "the active window from the most recent stage again (1.8.8.1.1's rule with a TV)" sbx 's/    if \(way != kMSBDInUseWayRecent\) return inUse;\n/    (void)inUse;\n/'
mtf "an action from the other display's bar not held" sbx 's/    MSBDInUseBarAction\(&gDMInUse, onOther \? 1 : 0, CACurrentMediaTime\(\)\);\n//'
mtf "a new most recent stage taken while not shown (a minimized window's, one left by a closed stage)" sbx 's/    BOOL shown = first && DMBarFrontInUseShown\(first\);/    BOOL shown = first != nil;/'
mtf "the TV in use: its most recent stage whatever it shows" sbx 's/if \(sc && DMBarFrontSwitcherOn\(sc, &env, &shown\)\) return env == 3 \? shown : nil;/(void)sc;/'
mtf "the iPad in use: the iPad's most recent stage, shown or not" sbx 's/if \(\*way == kMSBDInUseWayIPad\) return DMSMIPadStageShown\(\);/if (*way == kMSBDInUseWayIPad) return DMSMFrontStageOnDisplay(nil);/'
mtf "the keys never asked back" sbx 's/    DMBarFrontInUseKeysBack\(\[key copy\], 3\);\n//'
mtf "the keys left with the app of a transition the hold kept (review 1.8.8.2)" sbx 's/        if \(k.length\) DMBarFrontInUseKeysBack\(k, 3\);\n//'
mtf "the keys left with the app that was active after a window made active with no touch in it (review 1.8.8.2)" sbx 's/    DMBarFrontInUseKeysBack\(nil, 20\);\n//'
mtf "the keys asked back even when they stayed with the active app" sbx 's/ \|\| \[holder isEqualToString:ab\] \|\| !DMHardwareKeyboardAttached/ || !DMHardwareKeyboardAttached/'
mtf "the keys followed only when the display in use changed (the Window menu's pick)" sbx 's/    DMBarFrontInUseKeysBack\(nil, 20\);\n    if \(!changed\) return;/    if (!changed) return;\n    DMBarFrontInUseKeysBack(nil, 20);/'
mtf "the keys asked once, not read again (a click)" sbx 's/        if \(asked && left > 1\) DMBarFrontInUseKeysStep\(acted, left - 1, asks - 1\);\n//'
mtf "the keys asked without end" sbx 's/if \(asked && left > 1\) DMBarFrontInUseKeysStep\(acted, left - 1, asks - 1\);/if (asked \&\& left > 1) DMBarFrontInUseKeysStep(acted, left - 1, asks);/'
mtf "the keys asked away from SpringBoard (a menu's lock, Spotlight)" sbx 's/if \(!holder.length \|\| gOverlay \|\| /if (gOverlay || /'
mtf "the keys moved while one of our menus is open" sbx 's/if \(!holder.length \|\| gOverlay \|\| /if (!holder.length || /'
mtf "the iPad's Home Screen with no front app: a stage named (not 1.8.8.1's)" sbx 's/    if \(DMSMIsMainIdentity\(DMSMStageDisplayIdentity\(stage\)\) && !DMFrontApp\(\)\) return nil;   \/\/ \(the iPad.s Home Screen, no TV stage in use\)\n    return stage;/    return stage;/'
mtf "a click not seen" sbx 's/ DMBarFrontInUsePress\(event\); \}/ }/'
mtf "the bars' display in use from the most recent stage" sbx 's/id at = DMBarFrontInUseIdentity\(\);/id at = [DMSMStageDisplayIdentity([DMSMRecentStages() firstObject]) self];/'
mtf "the lights from the other display's bar not held" sbx 's/    DMBarFrontInUseBarAction\(key\);   \/\/ \(B81: the transition it asks there does not make that display the one in use\)\n//'
mtf "the TV's state left naming the stage taken out" sbx 's/        if \(DMSMTVEmptyFirst\(ownIdentity, ownItem, wk\)\) return YES;\n//'
mtf "the TV's empty desktop asked with the per-display bar's piece off (review 1.8.8.2)" sbx 's/(static BOOL DMSMTVEmptyFirst\(id identity, id item, NSString \*wk\) \{\n)    if \(DMBarFrontSkipped\(\)\) return NO;\n/$1/'
mtf "a gone stage still named by the bar" sbx 's/if \(MSBDShownStageGone\(settled, inModel, [^\n]*\n/\n/'
mtf "the TV's auto-hide from its bar copies only" ptr 's/        if \(learn\) DMAutoHideTVSystemHover\(g, inside\);[^\n]*\n//'
mtf "a menu row over a Finder window makes it active again" nat 's/if \(overlayHost && overlayHost != gNativeLayer/if (0 \&\& overlayHost \&\& overlayHost != gNativeLayer/'

if [ $fails = 0 ]; then echo "PASS  test-displayinuse: all parts"; exit 0; fi
echo "FAIL  test-displayinuse: $fails part(s) failed"; exit 1
