#!/bin/bash
# Mac test of Keep Covered Windows in Front (Settings > Windows & Multitasking, 1.8.4.1 item 7, off unless switched on; common/WindowOrder.h,
# test-keepcovered.c), then the sites: the switch read with the others; the rule after every raise of ours and from the tick on Aerial, Zetsu and
# MilkyWay4, Stage Manager's in one request once its transition is over; the window that came forward the active one; the Settings row (off by
# default), the page and the Settings search leaving it out without an engine; the crash guard's rule.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tkc" test-keepcovered.c
"$W/tkc"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; K=../statusbar/KeepCovered.h; F=../statusbar/WindowFront.h; T=../statusbar/TitleBarTap.h; PL=../statusbar/macstatusbarprefs/Resources/Windows.plist
R=../common/OwnPageRows.h; P=../statusbar/macstatusbarprefs/MSBRootListController.m; C=crashmap-rules.txt
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
has() { grep -qF -- "$1" "$W/fn"; }
before() { awk -v a="$1" -v b="$2" 'index($0, a) && !x {x=NR} index($0, b) && !y {y=NR} END{exit !(x && y && x < y)}' "$W/fn"; }
check "the switch: off unless switched on, read with the other window settings (a boolean only)" \
  "grep -qF 'static BOOL gKeepCoveredInFront = NO;' $S && grep -qF 'CFPropertyListRef kc = CFPreferencesCopyValue(CFSTR(kMSBDKeepCoveredKey), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
   && grep -qF 'BOOL keepCovered = kc && CFGetTypeID(kc) == CFBooleanGetTypeID() && CFBooleanGetValue(kc);' $S && tail -1 $S | grep -qF '#include \"KeepCovered.h\"'"
check "Aerial, Zetsu, MilkyWay4: after every raise of ours (DMEngineRaise: a tap or click, the Dock icon, Command-Tab, the Mac Switcher, our menus) the rule runs, never from inside its own raises" \
  "fn 'static void DMEngineRaise(UIView *stage, NSString *why) {' $F && sed -n '\$p' \$W/fn | grep -q '^}' && grep -qF '    DMKeepCoveredAfterRaise(stage, why);   // (the windows it covers' \$W/fn \
   && fn '__attribute__((noinline)) static void DMKeepCoveredAfterRaise(UIView *w, NSString *why) {' $K && has 'if (!gKeepCoveredInFront || gDMKeepCoveredBusy || !w || DMSMEngine() || DMActiveEngine() == DMEngineNone || gMSWOpen) return;' \
   && has 'int m = MSBDOrderKeepCovered(frames, shown, n, at, order, &kept);' && before 'gDMKeepCoveredBusy = YES;' 'DMEngineRaise(s, @\"kept in front of the window that covers it\");' \
   && before 'DMEngineRaise(s, @\"kept in front of the window that covers it\");' 'gDMKeepCoveredBusy = NO;' && has 'NSArray<UIView *> *stages = DMAerialStages();'"
check "  ... the windows taken part: showing, on that screen, this desktop (minimized, hidden, going, another screen or desktop left alone); the window as it shows (Aerial 5.x's inside its stage)" \
  "fn 'static BOOL DMKeepCoveredShows(UIView *s, UIScreen *scr) {' $K && has '!DMStageMinimized(s)' && has 'DMSnapScreenOf(s) == scr' && has 'kStageClosingKey' \
   && fn 'static CGRect DMKeepCoveredFrame(UIView *s) {' $K && has '[s.superview convertRect:DMA5WindowFromStage(s.frame) toView:nil]'"
check "  ... the engine's own raises (a tap on its title bar) from the tick, every tick while on; a window touched where it is: a kept one is the active one now, any other comes forward only if it was not in front at the last raise or tick (review 1.8.4.1 L6)" \
  "fn 'static void DMKeepCoveredTick(void) {' $K && has 'if (!gKeepCoveredInFront || gMSWOpen) return;' && has 'if (top && ![gDMKeptAbove containsObject:top]) DMKeepCoveredAfterRaise(top, @\"came forward (the engine'\"'\"'s own)\");' \
   && fn 'static void DMTickBody(void) {' $S && has 'DMKeepCoveredTick();' \
   && fn 'static void DMRaiseStageForBundle(NSString *bundle) {' $S && has 'if (DMTopStage() == stage) { DMKeepCoveredTouched(stage); return; }' \
   && fn 'static void DMKeepCoveredTouched(UIView *s) {' $K && has 'if ([gDMKeptAbove containsObject:s]) { DMKeepCoveredForget(); gDMKeepLastTop = s; return; }' \
   && before 'if ([gDMKeptAbove containsObject:s])' 'if (s == gDMKeepLastTop) return;' && before 'if (s == gDMKeepLastTop) return;' 'DMKeepCoveredAfterRaise(s, @\"a tap or click in it\");'"
check "  ... the switch turned on or off: nothing kept from before -- the window that came forward and its kept windows, the window last seen in front, Stage Manager's (review 1.8.4.1 L5)" \
  "grep -qF 'static void DMKeepCoveredReset(void);' $S && fn 'static void DMLoadPrefs(void) {' $S && before 'if (keepCovered != gKeepCoveredInFront) {' 'DMKeepCoveredReset();' \
   && before 'DMKeepCoveredReset();' 'gKeepCoveredInFront = keepCovered;' \
   && fn 'static void DMKeepCoveredReset(void) {' $K && has 'DMKeepCoveredForget();' && has 'gDMKeepLastTop = nil;' && has 'gDMSMKeepLastFront = nil;' && has '[gDMSMKeptKeys removeAllObjects];'"
check "  ... the window that came forward stays the active one (the menu bar, the window keys, the keyboard: DMActiveApp) while only its kept windows are above it, still inside it (review 1.8.4.1 M1: their frames as they show now), Aerial / Zetsu and MilkyWay4" \
  "fn 'static SBApplication *DMActiveApp(void) {' $S && has 'UIView *stage = DMWindowsOwnStatusBar() ? DMKeepCoveredActive(DMTopStage()) : nil;' && has 'UIView *top = DMWindowsOwnStatusBar() ? DMKeepCoveredActive(DMTopWindow()) : nil;' \
   && fn 'static UIView *DMKeepCoveredActive(UIView *top) {' $K && has 'int a = MSBDActiveWithKept(shown, keptAbove, frames, n, at);' && has 'if (!gKeepCoveredInFront || !under || !top || top == under || ![gDMKeptAbove containsObject:top]) return top;' \
   && has 'frames[i] = (keptAbove[i] || stages[i] == under) ? DMKeepCoveredFrame(stages[i]) : CGRectNull;'"
check "  ... a kept window handled by hand is an ordinary one again (review 1.8.4.1 M1): a touch on its title bar or its lights, on every engine's bar (the title-tap recogniser's delegate, before its answer, which is unchanged), a move or a resize by hand ended on every engine (Zetsu's own seen by its watcher); off: nothing" \
  "grep -qF 'static void DMKeepCoveredByHand(UIView *v);' $S && fn 'static void DMKeepCoveredByHand(UIView *v) {' $K && has 'if (!gKeepCoveredInFront || !gDMKeptAbove.count) return;' \
   && has 'for (; v; v = v.superview) if ([gDMKeptAbove containsObject:v]) { DMKeepCoveredForget(); return; }' \
   && fn 'static void DMTitleRecordHandEnded(UIView *v, UIGestureRecognizerState s) {' $S && has 'if (s == UIGestureRecognizerStateEnded || s == UIGestureRecognizerStateCancelled) { DMTitleRecordMovedView(v); DMKeepCoveredByHand(v); }' \
   && fn 'static void DMSnapMoveEnded(UIView *st) {' $S && before 'DMTitleRecordMovedView(st);' 'DMKeepCoveredByHand(st);' && before 'DMKeepCoveredByHand(st);' 'if (!st ||' \
   && grep -A3 -F 'moved by hand %@ -> %@: remembered, no longer tiled' $S | grep -qF 'DMKeepCoveredByHand(w);' \
   && fn '- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {' $T && before 'if (!DMTitleTapOnBar(g, touch)) return NO;' 'DMKeepCoveredByHand(g.view);' \
   && before 'DMKeepCoveredByHand(g.view);' 'if ([v isKindOfClass:[UIControl class]]) return NO;' && sed -n '\$p' \$W/fn | grep -q '^}' \
   && fn 'static BOOL DMTitleTapOnBar(UIGestureRecognizer *g, UITouch *touch) {' $T && has 'return gAerialFlavor == 5 ? DMA5DragAllowedAt(stage, p) : (p.y >= -12.0 && p.y < kStageBarHeight);'"
check "Stage Manager: from the tick once its own transition is over, the covered windows newer than the front one in one request; the front change that request makes is not taken for another" \
  "fn '__attribute__((noinline)) static void DMKeepCoveredSMTick(void) {' $K && before 'if (DMSMWorkspaceBusy()) return;' 'gDMSMKeepLastFront = [front copy];' \
   && has 'if ([gDMSMKeptKeys containsObject:front]) return;' && has 'BOOL ok = last && DMSMRequestStageOrderAs(stage, times, last, NO);' && has 'shown[i] = f != nil && !DMSMAttrsFullScreen(map[items[i]]);' \
   && fn 'static void DMKeepCoveredTick(void) {' $K && has 'if (DMSMEngine()) { if (kDMKeepCoveredOnStageManager) DMKeepCoveredSMTick(); return; }' && grep -qF 'static const BOOL kDMKeepCoveredOnStageManager = NO;' $K"
check "the Settings row: Windows & Multitasking after New Windows Open at Fill, a switch off by default, posted to SpringBoard, in a group of its own with its footer (no em dash)" \
  "plutil -convert json -o - $PL | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; k=[x.get(\"key\") or x.get(\"id\") for x in it]; r=[x for x in it if x.get(\"key\")==\"keepCoveredInFront\"]; g=[x for x in it if x.get(\"id\")==\"KEEP_COVERED_GROUP\"]; sys.exit(0 if len(r)==1 and len(g)==1 and r[0][\"cell\"]==\"PSSwitchCell\" and r[0][\"default\"]==False and r[0][\"label\"]==\"Keep Covered Windows in Front\" and r[0][\"PostNotification\"]==\"com.besiktasliseba.macstatusbar/prefsChanged\" and r[0][\"defaults\"]==\"com.besiktasliseba.macstatusbar\" and k.index(\"KEEP_COVERED_GROUP\")==k.index(\"newWindowsFill\")+1 and k.index(\"keepCoveredInFront\")==k.index(\"KEEP_COVERED_GROUP\")+1 and g[0][\"stockHides\"]==True and \"footerText\" in g[0] and \"\\u2014\" not in g[0][\"footerText\"] else 1)'"
check "  ... the page and the Settings search leave it out where no engine works (as New Windows Open at Fill) and with Stage Manager for now" \
  "grep -qF '#define kMSBDKeepCoveredGroupID @\"KEEP_COVERED_GROUP\"' $R && grep -qF 'if ([group isEqualToString:kMSBDKeepCoveredGroupID] && (!s.engineWorks || s.stageManagerEngine)) return YES;' $R && [ \"\$(grep -cF 'if (sp.cellType == PSGroupCell && [sp.identifier isEqualToString:kMSBDKeepCoveredGroupID]) { hiding = YES; continue; }' $P)\" = 2 ] \
   && grep -qF 'if (sp.cellType == PSGroupCell && [sp.identifier isEqualToString:kMSBDKeepCoveredGroupID]) { hiding = YES; continue; }' $P"
check "the crash guard: a crash in it turns the switch off (0, never set off), named in its explanation; its functions kept out of line for the map" \
  "grep -qF 'target keepCoveredInFront pref com.besiktasliseba.macstatusbar keepCoveredInFront 0 0 Keep Covered Windows in Front|the covered windows kept in front' $C \
   && grep -qF 'sym MacStatusBarCore ^_*DMKeepCovered[A-Z] keepCoveredInFront' $C && grep -qF 'file MacStatusBarCore ^KeepCovered\\.h\$ keepCoveredInFront' $C \
   && awk '/^sym MacStatusBarCore \\^_\\*DMKeepCovered/{a=NR} /^sym MacStatusBarCore \\^_\\?DMMSWPressesBegan/{b=NR} END{exit !(a && b && a < b)}' $C \
   && [ \$(grep -c '^__attribute__((noinline)) static void DMKeepCovered' $K) = 2 ]"
exit $fails
