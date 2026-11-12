#!/bin/bash
# Mac test of the stage the iPad's own screen shows (1.8.7, A12Z d39 with the 4K TV): every check that means "the stage on the iPad's screen" reads
# DMSMIPadStageShown (StatusBar.x): the iPad switcher's layout state (DMSMShownMainStage, nil at its Home Screen and in its App Switcher), the old
# "DMFrontApp() ? DMSMFrontStage() : nil" way only where that state cannot be read. SpringBoard's front app is any display's: with an app in front on
# the TV and the iPad at its Home Screen it is the TV's app, and DMSMFrontStage then answers the iPad's most recent stage, so the Mac Switcher's tick
# took that stage for the one on screen and changed the current desktop while the screen showed an empty one. Also the view's keyboard focus taken
# again after a Home of ours under the open view (the drop that leaves the iPad's desktop empty: Esc went to the TV's app). Site checks, then
# made-to-fail copies (the old way put back at each site, the helper without its layout state, the focus not taken again) that must fail them.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
sites() {   # sites <root>: 0 when every site is as it must be
  local S="$1/statusbar/StatusBar.x" SM="$1/statusbar/MacSwitcherSM.h" M="$1/statusbar/MacSwitcher.h" WA="$1/statusbar/WindowAPI.h" f=0
  c() { if eval "$2"; then [ -n "$Q" ] || echo "PASS  $1"; else [ -n "$Q" ] || echo "FAIL  $1"; f=1; fi; }
  c "the helper: the iPad's layout state read (DMSMShownMainStage), the front app's way only where it cannot be read" \
    "fn $S 'static id DMSMIPadStageShown(void) {' | grep -qF 'if (DMSMHomeStateOf(DMSMHomeCurrentState(), &env, &st)) return DMSMShownMainStage();' \
     && [ \"\$(fn $S 'static id DMSMIPadStageShown(void) {' | grep -c 'return')\" = 2 ] && fn $S 'static id DMSMIPadStageShown(void) {' | tail -2 | grep -qF '    return DMFrontApp() ? DMSMFrontStage() : nil;' \
     && grep -qF 'static id DMSMIPadStageShown(void);   // (below:' $S"
  c "  ... no other check reads the front app's way for the iPad's stage (StatusBar.x, the Mac Switcher, WindowAPI.h)" \
    "[ \"\$(cat $S $SM $M $WA | grep -v '^ *//' | grep -cE 'DMFrontApp\(\) (\?|&&) [^;]*DMSMFrontStage\(\)|DMFrontApp\(\) && \[DMSMFrontStage\(\)|== DMSMFrontStage\(\) && DMFrontApp\(\)|if \(DMFrontApp\(\)\) for \(id it in DMSMStageItemsMap\(DMSMFrontStage')\" = 1 ]"
  c "the Mac Switcher's tick: the stage on the iPad's screen, not the TV app's front (the iPad at its Home Screen shows none)" \
    "grep -qF 'id front = main ? (!DMSwitcherVisible() && !DMCoverSheetShown() && !gMSWOpen ? DMSMIPadStageShown() : nil)' $SM"
  c "  ... the stages now (the start / switch-on's current desktop), the wait for a desktop drawn, the thumbnails, SpringBoard's own transition's windows" \
    "grep -qF '    id front = !DMSwitcherVisible() ? DMSMIPadStageShown() : nil;' $SM \
     && [ \"\$(grep -cF 'id shown = DMMSWIsMain() ? DMSMIPadStageShown() : DMMSWSMShownHere();' $SM)\" = 2 ] \
     && fn $SM 'static NSArray<NSArray *> *DMMSWSMAskedDeskWindows(void) {' | grep -qF 'id front = DMSMIPadStageShown();' && fn $SM 'static NSArray<NSArray *> *DMMSWSMAskedDeskWindows(void) {' | grep -qF '    if (front) {'"
  c "  ... an empty desktop goes Home for real only while the iPad shows a stage (no Home press at its Home Screen for the TV's app)" \
    "[ \"\$(grep -cF 'if (DMSMIPadStageShown()) ' $SM)\" = 2 ] && ! grep -qF 'if (DMFrontApp()) DMSMGoHomeForReal' $SM && ! grep -qF 'if (DMFrontApp()) { DMLog' $SM"
  c "the desktop's last window, the window that came back after Home, force quit (hidden stages, the stage on screen), the start's re-fit, Minimize All" \
    "grep -qF 'BOOL last = own && ownItem && [DMSMStageItemsMap(own) count] == 1 && own == DMSMIPadStageShown();' $S && grep -qF 'BOOL shown = st && [DMSMIPadStageShown() isEqual:st];' $S \
     && grep -qF '    id shown = DMSMIPadStageShown();' $S && grep -qF '    id shownStage = DMSMIPadStageShown();' $S && grep -qF '    id front = !DMSwitcherVisible() ? DMSMIPadStageShown() : nil;' $S \
     && grep -qF '        for (id it in DMSMStageItemsMap(DMSMIPadStageShown())) {' $WA"
  c "the view's keyboard focus again after our Home under it (the drop that empties the iPad's desktop, a full-screen app sent away)" \
    "fn $SM 'static void DMMSWSMMoveFinish(NSString *b, NSInteger toId) {' | awk '/DMMSWSMShowDesk\\(cur, why\\);/{a=NR} /DMMSWFocusAgain\\(why\\);/{b=NR} END{exit !(a && b > a)}' \
     && fn $M 'static void DMMSWOwnHome(void) {' | awk '/DMMinimize\\(\\);/{a=NR} /DMMSWFocusAgain\\(/{b=NR} END{exit !(a && b > a)}'"
  c "  ... only while the view is open with its lock, after SpringBoard's Home transition (at most 2 s), the new lock before the old is given back" \
    "fn $M 'static void DMMSWFocusAgain(NSString *why) {' > $W/fa && grep -qF 'if (!gMSWOpen || gMSWClosing || !gMSWFocusLock) return;' $W/fa \
     && grep -qF 'if (!gMSWOpen || gMSWClosing || !gMSWFocusLock) { step = nil; return; }' $W/fa && grep -qF 'if (DMSMWorkspaceBusy() && ++tries < 8) { DMMSWAfter(0.25, step); return; }' $W/fa \
     && awk '/id lock = MSBDFocusLock\\(gMSWWindow.windowScene, @\"MacStatusBar Mac Switcher\", &how\\);/{a=NR} /id old = gMSWFocusLock; gMSWFocusLock = lock;/{b=NR} /MSBDFocusUnlock\\(old\\);/{u=NR} END{exit !(a && b > a && u > b)}' $W/fa \
     && grep -qF 'if (!lock) {' $W/fa && grep -qF '    DMMSWAfter(0.25, step);' $W/fa && [ \$(grep -c MSBDFocusUnlock $W/fa) = 1 ]"
  return $f
}
sites ..
echo "-- made-to-fail copies:"
mk() { rm -rf "$W/r"; mkdir -p "$W/r/statusbar"; cp ../statusbar/StatusBar.x ../statusbar/MacSwitcherSM.h ../statusbar/MacSwitcher.h ../statusbar/WindowAPI.h "$W/r/statusbar/"; }
mtf() {   # mtf <name> <file> <perl substitution>: that change must make the sites fail
  mk; perl -0pi -e "$3" "$W/r/$2"
  cmp -s "../$2" "$W/r/$2" && { echo "made-to-fail copy $1: the change did not apply"; exit 1; }
  if Q=1 sites "$W/r"; then echo "made-to-fail copy $1 PASSED (it must fail)"; exit 1; else echo "made-to-fail copy $1 fails, as it must"; fi
}
mtf "the tick reads the front app's way (1.8.6, d39's FAIL)" statusbar/MacSwitcherSM.h 's/id front = main \? \(!DMSwitcherVisible\(\) && !DMCoverSheetShown\(\) && !gMSWOpen \? DMSMIPadStageShown\(\) : nil\)/id front = main ? (DMFrontApp() \&\& !DMSwitcherVisible() \&\& !DMCoverSheetShown() \&\& !gMSWOpen ? DMSMFrontStage() : nil)/'
mtf "the helper never reads the layout state" statusbar/StatusBar.x 's/    if \(DMSMHomeStateOf\(DMSMHomeCurrentState\(\), &env, &st\)\) return DMSMShownMainStage\(\);\n//'
mtf "the helper is the most recent stage" statusbar/StatusBar.x 's/    return DMFrontApp\(\) \? DMSMFrontStage\(\) : nil;\n\}/    return DMSMFrontStage();\n}/'
mtf "the thumbnails read the front app's way" statusbar/MacSwitcherSM.h 's/(\/\/ ---- the view.s thumbnails.*?)id shown = DMMSWIsMain\(\) \? DMSMIPadStageShown\(\)/$1id shown = DMMSWIsMain() ? (DMFrontApp() ? DMSMFrontStage() : nil)/s'
mtf "SpringBoard's own transition adds the front app's stage" statusbar/MacSwitcherSM.h 's/    id front = DMSMIPadStageShown\(\);   \/\/ \(the stage the iPad shows: none at its Home Screen[^\n]*\n    if \(front\) \{/    id front = DMSMFrontStage();\n    if (DMFrontApp()) {/'
mtf "an empty desktop presses Home at the Home Screen" statusbar/MacSwitcherSM.h 's/if \(DMSMIPadStageShown\(\)\) \{ DMLog/if (DMFrontApp()) { DMLog/'
mtf "force quit's stage on screen the front app's way" statusbar/StatusBar.x 's/    id shownStage = DMSMIPadStageShown\(\);/    id shownStage = DMFrontApp() ? DMSMFrontStage() : nil;/'
mtf "Minimize All the front app's way" statusbar/WindowAPI.h 's/        for \(id it in DMSMStageItemsMap\(DMSMIPadStageShown\(\)\)\) \{/        if (DMFrontApp()) for (id it in DMSMStageItemsMap(DMSMFrontStage())) {/'
mtf "the drop's Home: the focus not taken again (d39)" statusbar/MacSwitcherSM.h 's/        DMMSWFocusAgain\(why\);[^\n]*\n//'
mtf "a full-screen app sent away: the focus not taken again" statusbar/MacSwitcher.h 's/    DMMSWFocusAgain\(\@"a full-screen app went to another desktop"\);\n//'
mtf "the old lock given back before the new one is taken" statusbar/MacSwitcher.h 's/(        id lock = MSBDFocusLock\(gMSWWindow\.windowScene[^\n]*\n)(.*?\n)(        id old = gMSWFocusLock; gMSWFocusLock = lock;\n        MSBDFocusUnlock\(old\);\n)/        MSBDFocusUnlock(gMSWFocusLock);\n$1$2$3/s'
mtf "the focus taken again in the middle of SpringBoard's Home" statusbar/MacSwitcher.h 's/        if \(DMSMWorkspaceBusy\(\) && \+\+tries < 8\) \{ DMMSWAfter\(0\.25, step\); return; \}\n//'
echo "test-ipadstageshown: all passed"
