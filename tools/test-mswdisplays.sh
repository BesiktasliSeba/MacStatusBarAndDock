#!/bin/bash
# Mac test of the Mac Switcher's desktops per display (1.8.7 commits 14-16; plans/design-1.8.7-displays.md section 7): statusbar/MSWDisplays.h's
# model and file (test-mswdisplays.m: version 1 -> 2, a save keeps version 1's keys, 1.8.6's loader on version 2 keeps the iPad's, another display's
# ids from 1001, 8 desktops per display, 8 displays, Forget This Display), then the sites in the code as built: the model in use behind gMSWDesks /
# gMSWCur, the file, every deferred step under its model. Made-to-fail copies of the header and of the sites must fail.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tmd" test-mswdisplays.m
"$W/tmd"
sites() {   # sites <root>: 0 when every site is as it must be
  local R="$1" M="$1/statusbar/MacSwitcher.h" SM="$1/statusbar/MacSwitcherSM.h" f=0
  c() { if eval "$2"; then [ -n "$Q" ] || echo "PASS  $1"; else [ -n "$Q" ] || echo "FAIL  $1"; f=1; fi; }
  fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
  c "the desktops and the current place are the model in use's (no list of their own left)" \
    "grep -qF '#define gMSWDesks (DMMSWM()->desks)' $M && grep -qF '#define gMSWCur (DMMSWM()->cur)' $M && ! grep -qE '^static [A-Za-z_<> ]*\\*? *gMSW(Desks|Cur) *(=|;)' $M $SM"
  c "  ... the iPad's model when nothing else is in use" \
    "fn $M 'static DMMSWModel *DMMSWM(void) {' | grep -qF 'if (!gMSWModel) gMSWModel = gMSWMain;'"
  c "no raw dispatch_after or main-queue dispatch_async in MacSwitcher.h or MacSwitcherSM.h: every deferred step goes through DMMSWAfter / DMMSWAsync" \
    "[ \$(grep -hE 'dispatch_after\\(|dispatch_async\\(dispatch_get_main_queue\\(\\)' $M $SM | grep -cvE '^static void DMMSW(After|Async|AsyncWith)\\(|\\^\\{ DMMSWRunUnder\\(m, b\\); \\}\\);\$') = 0 ] && [ \$(grep -cE '^static void DMMSW(After|Async|AsyncWith)\\(' $M) = 3 ] && [ \$(grep -cF '^{ DMMSWRunUnder(m, b); });' $M) = 1 ]"
  c "  ... which run it with the model it was asked under and put back the one in use (a session the step started keeps its model)" \
    "fn $M 'static void DMMSWRunUnder(DMMSWModel *m, dispatch_block_t b) {' | grep -qF 'if (m) gMSWModel = m;' && fn $M 'static void DMMSWRunUnder(DMMSWModel *m, dispatch_block_t b) {' | grep -qF 'if (m && gMSWModel == m) gMSWModel = was;' \
     && fn $M 'static dispatch_block_t DMMSWModelBlock(DMMSWModel *m, dispatch_block_t b) {' | grep -qF 'return ^{ DMMSWRunUnder(m, b); };' && grep -qF 'dispatch_get_main_queue(), DMMSWModelBlock(gMSWModel, b)); }' $M"
  c "  ... and wait while a session runs on another display's model (its view, switch and slide are not theirs: review)" \
    "fn $M 'static void DMMSWRunUnder(DMMSWModel *m, dispatch_block_t b) {' | awk '/if \\(m && m != DMMSWM\\(\\) && !DMMSWSessionIdle\\(\\)\\) \\{/{a=NR} /\\^\\{ DMMSWRunUnder\\(m, b\\); \\}\\);/{b=NR} /        return;/{c=NR} /    b\\(\\);/{d=NR} END{exit !(a && b > a && c > b && d > c)}'"
  c "the iPad's model is made where it is read (gMSWMain never a nil model: no raw ivar read of nil, review)" \
    "grep -qF '#define gMSWMain (DMMSWMainModel())' $M && ! grep -qE '^static DMMSWModel \\*gMSWMain;' $M $SM && [ \$(grep -c 'gMSWMainModel' $M) = 3 ] && ! grep -q 'gMSWMainModel' $SM"
  c "  ... an answer from the picture queue comes back under the model it was asked under" \
    "[ \$(grep -cF 'DMMSWModel *asked = gMSWModel;   // (the answer comes back under the model it was asked under)' $M) = 2 ] && [ \$(grep -cF 'DMMSWAsyncWith(asked, ^{' $M) = 2 ]"
  c "the save: version 1's keys are the iPad's model whatever is in use; version 2's added" \
    "fn $M 'static void DMMSWSave(void) {' | grep -qF 'for (NSNumber *n in gMSWMain->desks ?: @[@1]) [ids addObject:n];' && fn $M 'static void DMMSWSave(void) {' | grep -qF '@\"current\": @(MSWDispCurId(gMSWMain))' && fn $M 'static void DMMSWSave(void) {' | grep -qF 'MSWDispWrite(st, gMSWModels, gMSWNextDesk);'"
  c "the load: every model from the file; records and full-screen apps kept for a desktop of any model; the iPad's in use" \
    "fn $M 'static void DMMSWLoad(void) {' | grep -qF 'MSWDispRead(st, kMSWMaxDesks, gMSWMain, gMSWModels, &gMSWNextDesk);' && fn $M 'static void DMMSWLoad(void) {' | grep -qF 'gMSWModel = gMSWMain;' \
     && [ \$(fn $M 'static void DMMSWLoad(void) {' | grep -c 'MSWDispDeskKnown(') = 2 ] && ! fn $M 'static void DMMSWLoad(void) {' | grep -qF '[gMSWDesks containsObject:'"
  # ---- commit 15: the Mac Switcher on the TV ----
  local X="$1/statusbar/StatusBar.x" D="$1/statusbar/SMDesktop.h" SP="$1/statusbar/SpotlightBridge.h" AM="$1/statusbar/ActMonDock.h"
  c "15: a desktop's windows, the alive windows and Desktop 1's first are the stages of the model's display (no iPad-only filter left in them)" \
    "fn $SM 'static NSArray<NSArray *> *DMMSWSMDeskWindows(NSInteger did) {' | grep -qF 'if (!DMMSWStageHere(al)) continue;' && ! fn $SM 'static NSArray<NSArray *> *DMMSWSMDeskWindows(NSInteger did) {' | grep -qF 'DMSMIsMainIdentity' \
     && fn $SM 'static void DMMSWSMApply(void) {' | grep -qF 'if (!DMMSWStageHere(al)) continue;' && fn $SM 'static void DMMSWSMRecordFirst(void) {' | grep -qF 'DMMSWStageHere(al)' \
     && grep -qF 'return DMMSWIsMain() ? DMSMIsMainIdentity(i) : [i isEqual:DMMSWIdentity()];' $M"
  c "15: the view's cards and the drawn cards are of the model's screen; the view, the slide and the pictures on that display's screen" \
    "[ \$(grep -cF 'card.window.screen != DMMSWScreen()' $SM) = 2 ] && grep -qF 'w.screen != DMMSWScreen()) continue;   // (the display the view is on)' $M && grep -qF '    UIScreen *on = DMMSWScreen();' $M \
     && grep -qF 'pic = [DMMSWScreen() snapshotViewAfterScreenUpdates:wasOpen];' $M && grep -qF 'DMMSWDeskPicture(to, DMMSWScreen().bounds)' $SM"
  c "15: another display's layer: a window of ours in its scene at the iPad layer's level (SceneLayer.h), its going ends a session on it" \
    "grep -qF 'DMSceneLayer(s, @\"macswitcher\", kMenuWindowLevel - 0.5,' $M && grep -qF '^(NSArray<UIWindow *> *gone) { DMMSWTVLayerGone(gone); }' $M && fn $M 'static void DMMSWTVLayerGone(NSArray<UIWindow *> *gone) {' | grep -qF 'DMMSWEndOtherDisplay(@\"its display went\");'"
  c "15: the model changes only between sessions; the tick takes the iPad's back and opens a display's view asked while busy" \
    "fn $M 'static BOOL DMMSWUse(DMMSWModel *m, NSString *why) {' | grep -qF 'if (!DMMSWSessionIdle()) {' && grep -qF 'static BOOL DMMSWSessionIdle(void) { return !gMSWOpen && !gMSWClosing && !gMSWSwitching && !gMSWSlRoot && !gMSWTrack && !gMSWDropping && !gMSWDragTile && !gMSWDropFinish; }' $M \
     && fn $M 'static void DMMSWTick(void) {' | grep -qF 'if (!DMMSWIsMain()) DMMSWUse(gMSWMain, @\"the session on another display ended\");' && fn $M 'static void DMMSWTick(void) {' | grep -qF 'if (!gMSWSwitching && DMMSWIsMain()) DMMSWApply();'"
  c "15: an empty desktop of another display is its own empty state (every window role empty, its stages kept), never the iPad's Home" \
    "fn $SM 'static NSString *DMMSWSMShowDesk(NSInteger did, NSString *why) {' | grep -qF 'if (!DMMSWIsMain() && !wins.count) {' && fn $SM 'static NSString *DMMSWSMShowDesk(NSInteger did, NSString *why) {' | grep -qF 'if (!DMMSWSMRequestEmpty(DMMSWIdentity(), why))' \
     && fn $SM 'static NSString *DMMSWSMShowDesk(NSInteger did, NSString *why) {' | grep -qF 'id identity = DMMSWIdentity();' \
     && fn $SM 'static BOOL DMMSWSMRequestEmpty(id identity, NSString *why) {' | grep -qF 'for (NSNumber *r in roles) ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, empty, r.longLongValue);' \
     && fn $SM 'static BOOL DMMSWSMRequestEmpty(id identity, NSString *why) {' | grep -qF 'if (list[i] != 3 && ![roles containsObject:@(list[i])]) [roles addObject:@(list[i])];'"
  c "15: the stage another display shows is read from its own switcher (environment 1: none, its empty desktop)" \
    "fn $SM 'static id DMMSWSMShownOn(id identity) {' | grep -qF 'switcherControllerForWindowScene:' && fn $SM 'static id DMMSWSMShownOn(id identity) {' | grep -qF '|| env == 1 || !shown) return nil;'"
  c "15: Fit to Window and Finder's windows stay the iPad's (leave, arrive, the switch, the view)" \
    "fn $SM 'static void DMMSWSMArrive(NSInteger toId) {' | grep -qF 'if (!DMMSWIsMain()) return;' && grep -qF 'if (settled >= 3 && !fitDone && frames < 60 && DMFitEnabled() && DMMSWIsMain()) {' $SM \
     && grep -qF 'if (gNativeLayer && !gNativeLayer.hidden && DMMSWIsMain())' $SM && grep -qF '    if (DMMSWIsMain()) {   // (Finder' $SM"
  c "15: a TV launch with desktops of its own joins them as an iPad launch (its display's attributes and room)" \
    "grep -qF '    if (tv && DMMSWSMJoinOn(identity, ctx, act, key)) return;' $X && grep -qF '    if (!tv && DMMSWForMain() && DMMSWSMJoin(ctx, act, key)) return;' $X \
     && grep -qF 'attrs = DMSMJoinAttributesOn(key, others.firstObject[2], windowed, (long)newest, others.firstObject[0], on);' $SM && grep -qF 'NSArray *plan = DMSMPlanFitted(on, DMMSWSMPlan(others, @[act, attrs, key], left));' $SM \
     && grep -qF 'if (DMMSWSMElsewhereFor(identity, bundle)) return DMSMAddNo(bundle, @\"its window is on another desktop\");' $X"
  c "15: the iPad's own steps read the iPad's desktops (SpringBoard's own transitions, the tick, Spotlight, Command-Tab, the gestures)" \
    "[ \$(grep -c '!DMMSWForMain()' $SM) -ge 4 ] && grep -qF 'return DMMSWForMain() && DMMSWSMElsewhere(key); }' $D && grep -qF '!DMMSWForMain() || !DMMSWMulti()) return NO;' $D \
     && grep -qF 'if (!DMMSWForMain()) return;   // (1.8.7: the iPad' $M && [ \$(grep -c 'DMMSWForMain()' $SP) = 5 ] && grep -qF 'DMMSWForMain() && DMMSWMulti()' $AM \
     && grep -qF 'if (!other && !gMSWGestureScreen && DMMSWForMain()) @try { DMMSWTrackBegin(gesture); }' $M && grep -qF 'else if (DMMSWForMain() && DMMSWMulti()) {' $M"
  c "15: a new desktop's id from one place (the iPad's lowest free from 2; another display's above 1000)" \
    "[ \$(grep -c 'NSInteger nid = 2;' $M $SM | awk -F: '{s+=\$2} END {print s}') = 1 ] && grep -qF 'return MSWDispNextId(MSWDispAllIds(gMSWMain, gMSWModels), gMSWNextDesk);' $M && [ \$(grep -c 'DMMSWDeskAdded(nid);' $M $SM | awk -F: '{s+=\$2} END {print s}') = 3 ]"
  c "15: the records of other displays: their own tick (MSWDispRecordFate), kept when the iPad's collapse or its last desktop clears its own, kept by the bring back" \
    "fn $SM 'static void DMMSWSMApply(void) {' | grep -qF 'MSWDispFate own = MSWDispRecordFate(gMSWWinDesk[k], model, gMSWMain, gMSWModels, [alive containsObject:k]);' && fn $SM 'static void DMMSWSMApply(void) {' | grep -qF '            if (own != MSWDispFateForget) continue;' && grep -qF 'gMSWModel = m;' $SM \
     && fn $M 'static void DMMSWCollapse(void) {' | grep -qF 'DMMSWClearMine();' && grep -qF 'if (gMSWDesks.count == 1) DMMSWClearMine();' $M && grep -qF '[gMSWWinDesk addEntriesFromDictionary:ow];' $M"
  c "15: SpringBoard's own transitions on the TV and a TV Dock tap keep its desktops apart (another desktop's stage comes as built; the empty desktop gets a stage of its own)" \
    "grep -qF 'if (tv) { NSMutableArray *ks = [NSMutableArray array]; for (NSDictionary *w in askedW) [ks addObject:w[@\"w\"]]; if (DMMSWSMAskedLeaveOn(identity, ks)) return; }' $D \
     && fn $SM 'static BOOL DMMSWSMAskedLeaveOn(id identity, NSArray<NSString *> *keys) {' | grep -qF 'if (!DMMSWSMDeskWindows(cur).count) leave = YES;' \
     && grep -qF 'if (DMMSWSMTVDesktops(identity) && al != DMMSWSMShownOn(identity) && ![al isEqual:DMMSWSMShownOn(identity)]) return DMSMAddNo(bundle, @\"the TV shows no stage of its current desktop\");' $X"
  c "15: Forget This Display forgets its desktops (the displays domain's note), the Apple menu's Mac Switcher opens on its own display" \
    "fn $M 'static void DMMSWForgetGone(void) {' | grep -qF 'MSWDispForget(gMSWModels, k, gMSWWinDesk, gMSWWinFrame,' && grep -qF 'notify_register_dispatch(MSBD_DISP_NOTIFY, &token, dispatch_get_main_queue(), ^(int t) { DMMSWForgetGone(); });' $M \
     && grep -qF 'DMMSWOpenOn(menuScreen, menuScreen ?' $X && grep -qF '__weak UIScreen *menuScreen = DMIsExtMenuHost(host) ? DMExternalScreenOf(host) : nil;' $X"
  # ---- commit 16: keys, three fingers and Show App Switcher on the TV ----
  c "16: Control-Up / Left / Right act on the display the rule gives (a session's, the keyboard focus's, the pointer's last, the iPad)" \
    "fn $M 'static void DMMSWControlKey(id self, SEL _cmd, id sender) {' | grep -qF 'UIScreen *on = DMMSWKeysScreen(&why);' && fn $M 'static void DMMSWControlKey(id self, SEL _cmd, id sender) {' | grep -qF 'DMMSWOpenOn(on, @\"Control-Up\"); return;' \
     && fn $M 'static void DMMSWControlKey(id self, SEL _cmd, id sender) {' | grep -qF 'DMMSWModel *m = DMMSWArrowsModel(&on, &why);' && fn $M 'static void DMMSWControlKey(id self, SEL _cmd, id sender) {' | grep -qF 'if (m != DMMSWM() && !DMMSWUse(m, key)) return;' \
     && fn $M 'static void DMMSWControlKey(id self, SEL _cmd, id sender) {' | grep -qF 'if (!m) { DMMSWKeysRefresh(); return; }' \
     && fn $M 'static UIScreen *DMMSWKeysScreen(NSString **why) {' | grep -qF 'BOOL onOther = MSWDispKeysOnOther(session, focus, DMPtrOtherDisplayAt(), gDMPtrAnyAt, other != nil);' \
     && fn $M 'static UIScreen *DMMSWKeysScreen(NSString **why) {' | grep -qF 'externalSceneWithFocus'"
  c "16: the Control-arrows are offered while the keys' display has two desktops, else the iPad's has (review); the edge bump is the iPad's" \
    "fn $M 'static int DMMSWKeysWanted(void) {' | grep -qF 'return DMMSWArrowsModel(NULL, NULL) ? 2 : 1;' && grep -qF '|| !DMMSWAsyncScreenOn() || !DMMSWIsMain()) return;' $M \
     && fn $M 'static DMMSWModel *DMMSWArrowsModel(UIScreen **onOut, NSString **why) {' | grep -qF 'int a = MSWDispArrowsOn(on != nil, DMMSWSessionIdle(), om ? om->desks.count : 0, DMMSWDesktopsHere() ? gMSWMain->desks.count : 0);' \
     && fn $M 'static DMMSWModel *DMMSWArrowsModel(UIScreen **onOut, NSString **why) {' | grep -qF 'UIScreen *on = DMMSWKeysScreen(why);' && ! grep -qF 'DMMSWAnyMulti' $M"
  c "16: a switcher gesture SpringBoard gives the other display opens or switches there and is not followed by the iPad's slide" \
    "fn $M 'static void DMMSWGBegin(id self, SEL _cmd, id transaction, id gesture) {' | grep -qF 'gMSWGestureScreen = DMMSWGesturesOn() ? DMMSWGestureScreen(self) : nil;' \
     && grep -qF 'if (eff == 3 && gs) act = ^{ gMSWGestureAt = CACurrentMediaTime(); DM_FEATURE_MARK(\"msw-tv-gesture\"); DMMSWOpenOn(gs,' $M \
     && grep -qF 'act = ^{ if (gm != DMMSWM() && !DMMSWUse(gm, @\"a side swipe on the other display\")) return;' $M && fn $M 'static BOOL DMMSWHolds(id o, id manager) {' | grep -qF 'void *p = *(void **)'"
  c "16: Show App Switcher on the TV's Apple menu is the TV's own (its scene's switcher), disabled where there is none" \
    "grep -qF 'enabled:DMMSWAppSwitcherAvailableOn(menuScreen) handler:DMCloseThen(^{ DMMSWShowAppSwitcherOn(menuScreen); })' $X \
     && fn $M 'static id DMMSWSwitcherOf(UIScreen *s, SEL *how) {' | grep -qF 'toggleMainSwitcherWithSource:animated:' && fn $M 'static id DMMSWSwitcherOf(UIScreen *s, SEL *how) {' | grep -qF 'UIWindowScene *scene = s ? DMSceneLayerSceneOf(s) : nil;' \
     && fn $M 'static BOOL DMMSWShowAppSwitcherOn(UIScreen *s) {' | grep -qF 'gMSWStockAskedAt = CACurrentMediaTime();'"
  c "16: the notice on the TV: in its scene, under its own bar" \
    "fn $SM 'static void DMMSWSMNotice(NSString *text) {' | grep -qF 'DMSceneLayer(DMMSWScreen(), @\"mswnotice\", kMenuWindowLevel - 0.4,' && fn $SM 'static void DMMSWSMNotice(NSString *text) {' | grep -qF ': DMTVBarHeight();'"
  # ---- fixes from the device (d26) ----
  c "d26: the iPad's view reads the iPad's own wallpaper window (with a TV connected the TV's came first)" \
    "fn $M 'static UIView *DMMSWWallpaperView(void) {' | grep -qF 'if (w.screen && w.screen != [UIScreen mainScreen]) continue;'"
  c "d26: a display's current desktop comes back after the start or its connect (after the iPad's, while it shows no stage, behind its own crash-loop guard)" \
    "fn $SM 'static BOOL DMMSWSMBringBackOn(DMMSWModel *m, CFTimeInterval now) {' | grep -qF 'if (m->broughtBack || !gSMRestoreDone || !m->connectedAt || now - m->connectedAt < 3.0) return NO;' \
     && fn $SM 'static BOOL DMMSWSMBringBackOn(DMMSWModel *m, CFTimeInterval now) {' | grep -qF 'if (DMMSWSMShownHere()) { m->broughtBack = YES; return NO; }' \
     && fn $SM 'static BOOL DMMSWSMBringBackOn(DMMSWModel *m, CFTimeInterval now) {' | grep -qF 'static const char *guard = \"/tmp/macstatusbar-mswtv-guard\";' \
     && fn $SM 'static void DMMSWSMApplyDisplays(void) {' | grep -qF 'if (m && !DMMSWScreenOf(m)) { m->connectedAt = 0; m->broughtBack = NO; continue; }'"
  # ---- review fixes (d27) ----
  local H="$1/statusbar/SMHome.h"
  c "review: the iPad's desktop after the start waits while another display's session runs; Home of a full-screen-only desktop reads the iPad's" \
    "fn $H 'static void DMSMRestoreDesktopTick(void) {' | awk '/    if \\(!DMMSWForMain\\(\\)\\) return;/{a=NR} /^    gSMRestoreDone = YES;\$/{b=NR} END{exit !(a && b == a + 1)}' \
     && grep -qF 'if ([why isEqualToString:kDMSMHomeOnlyFullScreen] && DMMSWForMain() && DMMSWMulti()) {' $H"
  c "review (iPad 2 d27): another display's opening picture leaves our window out; an empty desktop's strip tile takes the wallpaper if no view took it" \
    "grep -qF 'gMSWOpenShot = DMMSWScreenWithoutView() ?: [DMMSWScreen() snapshotViewAfterScreenUpdates:NO];' $M && fn $M 'static UIView *DMMSWBuildStrip(UIView *root, CGRect b) {' | grep -qF 'if (!shot && !gMSWWallContents) DMMSWWallLazy();'"
  c "the crash guard: MSWDisplays.h is the Mac Switcher's (its file rule)" \
    "grep -qF 'file MacStatusBarCore ^(MacSwitcher(SM|Button)?|MSWDisplays)\\.h\$ macSwitcher' $R/tools/crashmap-rules.txt"
  c "review of 1.8.7: the 9th display's model made keeps the ones with desktops of their own (the window records in use), the plain ones go first" \
    "fn $M 'static DMMSWModel *DMMSWModelOfScreen(UIScreen *s, BOOL make) {' | grep -qF 'MSWDispTrim(gMSWModels, k, kMSWDispMaxDisplays, gMSWWinDesk)'"
  return $f
}
sites ..
echo "-- made-to-fail copies:"
mk() { rm -rf "$W/r"; mkdir -p "$W/r/statusbar" "$W/r/tools"; cp ../statusbar/MacSwitcher.h ../statusbar/MacSwitcherSM.h ../statusbar/StatusBar.x ../statusbar/SMDesktop.h ../statusbar/SpotlightBridge.h ../statusbar/ActMonDock.h ../statusbar/SMHome.h "$W/r/statusbar/"; cp crashmap-rules.txt "$W/r/tools/"; }
mtf() {   # mtf <name> <file> <perl substitution>: that change must make the sites fail
  mk; perl -0pi -e "$3" "$W/r/$2"
  cmp -s "../$2" "$W/r/$2" && { echo "made-to-fail copy $1: the change did not apply"; exit 1; }
  if Q=1 sites "$W/r"; then echo "made-to-fail copy $1 PASSED (it must fail)"; exit 1; else echo "made-to-fail copy $1 fails, as it must"; fi
}
mtf "review of 1.8.7: the 9th display's model trimmed without the window records" statusbar/MacSwitcher.h 's/MSWDispTrim\(gMSWModels, k, kMSWDispMaxDisplays, gMSWWinDesk\)/MSWDispTrim(gMSWModels, k, kMSWDispMaxDisplays, nil)/'
mtf "a raw dispatch_after left" statusbar/MacSwitcherSM.h 's/DMMSWAfter\(3\.2, \^\{/dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{/'
mtf "a raw main-queue dispatch_async left" statusbar/MacSwitcher.h 's/    DMMSWAsync\(\^\{ DMMSWOpen\(h\); \}\);/    dispatch_async(dispatch_get_main_queue(), ^{ DMMSWOpen(h); });/'
mtf "a deferred step left under the model in use when it runs" statusbar/MacSwitcher.h 's/    if \(m\) gMSWModel = m;\n//'
mtf "review: a deferred step of one display run in the other's session" statusbar/MacSwitcher.h 's/    if \(m && m != DMMSWM\(\) && !DMMSWSessionIdle\(\)\) \{/    if (0) {/'
mtf "review: the iPad's model read raw" statusbar/MacSwitcher.h 's/#define gMSWMain \(DMMSWMainModel\(\)\)/static DMMSWModel *gMSWMain;/'
mtf "the save writing the model in use as the iPad's" statusbar/MacSwitcher.h 's/for \(NSNumber \*n in gMSWMain->desks \?: \@\[\@1\]\)/for (NSNumber *n in gMSWDesks ?: \@[\@1])/'
mtf "the load keeping only the records of the desktops in use" statusbar/MacSwitcher.h 's/MSWDispDeskKnown\(w\[k\], gMSWMain, gMSWModels\)/[gMSWDesks containsObject:w[k]]/'
mtf "a list of its own for the desktops" statusbar/MacSwitcher.h 's/#define gMSWDesks \(DMMSWM\(\)->desks\)/static NSMutableArray *gMSWDesks;/'
mtf "15: a desktop's windows of the iPad's stages only" statusbar/MacSwitcherSM.h 's/        if \(!DMMSWStageHere\(al\)\) continue;   \/\/ \(a stage of the display whose desktops are in use/        if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(al))) continue;   \/\/ (/'
mtf "15: another display's empty desktop asked as the iPad's Home" statusbar/MacSwitcherSM.h 's/    if \(!DMMSWIsMain\(\) && !wins.count\) \{/    if (0 \&\& !wins.count) {/'
mtf "15: the model re-pointed during a session" statusbar/MacSwitcher.h 's/    if \(!DMMSWSessionIdle\(\)\) \{ DMLog\(\[NSString stringWithFormat:\@"\[macswitcher\] %\@: %\@.s Mac Switcher is busy/    if (0) { DMLog([NSString stringWithFormat:\@"[macswitcher] %\@: %\@ is busy/'
mtf "15: the iPad's tick forgetting another display's records" statusbar/MacSwitcherSM.h 's/            if \(own != MSWDispFateForget\) continue;/            if ([alive containsObject:k]) continue;/'
mtf "15: a TV launch left to the TV's own join" statusbar/StatusBar.x 's/    if \(tv && DMMSWSMJoinOn\(identity, ctx, act, key\)\) return;/    if (0) return;/'
mtf "15: a desktop id of its own in the full-desktop join" statusbar/MacSwitcherSM.h 's/        NSInteger nid = DMMSWNewDeskId\(\);\n        DMMSWDeskAdded\(nid\);/        NSInteger nid = 2;\n        while ([gMSWDesks containsObject:\@(nid)]) nid++;\n        [gMSWDesks addObject:\@(nid)];/'
mtf "15: the collapse clearing every display's records" statusbar/MacSwitcher.h 's/    gMSWDesks = \[NSMutableArray arrayWithObject:\@1\]; gMSWCur = 0;\n    DMMSWClearMine\(\);/    gMSWDesks = [NSMutableArray arrayWithObject:\@1]; gMSWCur = 0;\n    [gMSWWinDesk removeAllObjects];/'
mtf "15: SpringBoard's own TV transition joined into another TV desktop's stage" statusbar/SMDesktop.h 's/if \(DMMSWSMAskedLeaveOn\(identity, ks\)\) return; \}/if (0) return; }/'
mtf "15: Spotlight reading whichever display's desktops are in use" statusbar/SpotlightBridge.h 's/    if \(DMMSWForMain\(\) && DMMSWMulti\(\)\) \{   \/\/ \(the Mac Switcher.s desktops, two or more/    if (DMMSWMulti()) {   \/\/ (/'
mtf "16: Control-Up always the iPad's" statusbar/MacSwitcher.h 's/DMMSWOpenOn\(on, \@"Control-Up"\); return;/DMMSWOpen(\@"Control-Up"); return;/'
mtf "16: the arrows offered for the iPad's desktops only" statusbar/MacSwitcher.h 's/    return DMMSWArrowsModel\(NULL, NULL\) \? 2 : 1;/    return DMMSWMulti() ? 2 : 1;/'
mtf "review: an arrow with no desktops for it swallowed" statusbar/MacSwitcher.h 's/    if \(!m\) \{ DMMSWKeysRefresh\(\); return; \}/    if (!m) return;/'
mtf "review: the iPad's desktop restored during another display's session" statusbar/SMHome.h 's/    if \(!DMMSWForMain\(\)\) return;\n    gSMRestoreDone = YES;/    gSMRestoreDone = YES;/'
mtf "review: Home of a full-screen-only desktop reading the desktops in use" statusbar/SMHome.h 's/kDMSMHomeOnlyFullScreen\] && DMMSWForMain\(\) && DMMSWMulti\(\)/kDMSMHomeOnlyFullScreen] \&\& DMMSWMulti()/'
mtf "review: another display's opening picture with our window in it" statusbar/MacSwitcher.h 's/gMSWOpenShot = DMMSWScreenWithoutView\(\) \?: \[DMMSWScreen\(\) snapshotViewAfterScreenUpdates:NO\];/gMSWOpenShot = [DMMSWScreen() snapshotViewAfterScreenUpdates:NO];/'
mtf "review: an empty desktop's tile black with no wallpaper taken" statusbar/MacSwitcher.h 's/            if \(!shot && !gMSWWallContents\) DMMSWWallLazy\(\);\n//'
mtf "16: a gesture of the other display read as the iPad's" statusbar/MacSwitcher.h 's/gMSWGestureScreen = DMMSWGesturesOn\(\) \? DMMSWGestureScreen\(self\) : nil;/gMSWGestureScreen = nil;/'
mtf "16: the TV's Show App Switcher asking the iPad's" statusbar/StatusBar.x 's/DMCloseThen\(\^\{ DMMSWShowAppSwitcherOn\(menuScreen\); \}\)/DMCloseThen(^{ DMMSWShowAppSwitcher(); })/'
mtf "d26: the iPad's view taking any display's wallpaper" statusbar/MacSwitcher.h 's/        if \(w.screen && w.screen != \[UIScreen mainScreen\]\) continue;\n//'
mtf "d26: a TV desktop brought back over what it shows" statusbar/MacSwitcherSM.h 's/    if \(DMMSWSMShownHere\(\)\) \{ m->broughtBack = YES; return NO; \}/    if (0) { m->broughtBack = YES; return NO; }/'
mkdir -p "$W/h/statusbar" "$W/h/tools" "$W/h/common"; cp test-mswdisplays.m "$W/h/tools/"; cp ../common/DisplayPrefs.h "$W/h/common/"
for m in base reuse ipadrange share main fate keys arrows arrowsapp trimbusy busyrecords; do
  cp ../statusbar/MSWDisplays.h "$W/h/statusbar/"
  case $m in
    base) perl -pi -e 's/static const NSInteger kMSWDispBase = 1000;/static const NSInteger kMSWDispBase = 1;/' "$W/h/statusbar/MSWDisplays.h" ;;
    reuse) perl -pi -e 's/    return MAX\(nextDesk, top \+ 1\);/    return top + 1;/' "$W/h/statusbar/MSWDisplays.h" ;;
    ipadrange) perl -pi -e 's/\[n integerValue\] > kMSWDispBase && !\[used/[n integerValue] > 0 \&\& ![used/' "$W/h/statusbar/MSWDisplays.h" ;;
    share) perl -pi -e 's/\{ \[m->desks addObject:\@\(\[n integerValue\]\)\]; \[used addObject:\@\(\[n integerValue\]\)\]; \}/[m->desks addObject:\@([n integerValue])];/' "$W/h/statusbar/MSWDisplays.h" ;;
    main) perl -pi -e 's/ && !\[k isEqualToString:kMSWDispMain\] && MSBDDispKeyValid/ \&\& (1 || MSBDDispKeyValid/; s/MSBDDispKeyValid\(\[k UTF8String\]\);/MSBDDispKeyValid([k UTF8String]));/' "$W/h/statusbar/MSWDisplays.h" ;;
    keys) perl -pi -e 's/    if \(focus >= 0\) return focus == 1;/    if (hoverOther > 0 \&\& hoverOther >= hoverAny) return YES;\n    if (focus >= 0) return focus == 1;/' "$W/h/statusbar/MSWDisplays.h" ;;
    arrows) perl -pi -e 's/        if \(!sessionIdle\) return -1;   /        return -1;   /' "$W/h/statusbar/MSWDisplays.h" ;;
    arrowsapp) perl -pi -e 's/    return mainDesks >= 2 \? 0 : -1;/    return 0;/' "$W/h/statusbar/MSWDisplays.h" ;;
    trimbusy) perl -pi -e 's/                if \(pass == 0 && MSWDispBusy\(displays\[k\], windows\)\) continue;   \/\/ \(the plain ones first\)/                (void)pass;/' "$W/h/statusbar/MSWDisplays.h" ;;   # (review of 1.8.7: by lastSeen alone)
    busyrecords) perl -pi -e 's/    return MSBDDispMSWBusy\(\(int\)m->desks.count, records\);/    return MSBDDispMSWBusy((int)m->desks.count, 0);/' "$W/h/statusbar/MSWDisplays.h" ;;   # (a window record not counted)
    fate) perl -pi -e 's/    if \(tick == main \? \(owner && owner != main\) : owner != tick\) return MSWDispFateNotMine;/    if (tick != main \&\& owner != tick) return MSWDispFateNotMine;/' "$W/h/statusbar/MSWDisplays.h" ;;
  esac
  cmp -s ../statusbar/MSWDisplays.h "$W/h/statusbar/MSWDisplays.h" && { echo "made-to-fail header $m: the change did not apply"; exit 1; }
  clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/h/t" "$W/h/tools/test-mswdisplays.m" 2>/dev/null || { echo "made-to-fail header $m: does not build"; exit 1; }
  if "$W/h/t" >/dev/null 2>&1; then echo "made-to-fail header $m PASSED (it must fail)"; exit 1; else echo "made-to-fail header $m fails, as it must"; fi
done
echo "test-mswdisplays: all passed"
