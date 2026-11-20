#!/bin/bash
# Mac test of Window Size (1.8.0 item 4, KT 2 Nov: Settings > Windows & Multitasking > Window Size, Small / Default / Large on every engine): the
# size rule (common/WindowSize.h, test-windowsize.m) on the iPads' desktops in both orientations, then the sites in the code as built -- every
# engine's way of opening a window without a place of its own asks the same window (Aerial 3.0 / 5.x, Zetsu, MilkyWay4, our Stage Manager engine,
# the green light's way back, No Fit), a window back where it last was keeps its place, the layouts stay as they are, and Settings writes nothing
# for Default. 1.8.0's engine parity (KT 3 Nov): Stage Manager's Default and cascade are the other engines' (DMSMJoinAttributes, one rule in
# WindowSize.h), the Window menu's Small and Large are Window Size's, No Fit's window is one rule, and Aerial's green way back for a window with no
# place of its own opens it as a new window, as Zetsu's and MilkyWay4's.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/tws" test-windowsize.m
"$W/tws"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/MSBRootListController.m; PL=../statusbar/macstatusbarprefs/Resources/Windows.plist; R=../common/OwnPageRows.h; C=crashmap-rules.txt
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $S > "$W/fn"; }   # (one function of StatusBar.x, from its first line to its closing brace)
check "the one new window: Default is the middle place as before, Small / Large the rule's in the iPad's desktop under the menu bar -- also while it hides itself, as Stage Manager's desktop -- (its middle place's top, the smallest window)" \
  "fn 'static CGRect DMNewWindowFrameWindowAt(int choice) {' && grep -q 'if (choice == MSBDWindowSizeDefault) return DMLayoutFrameWindow(@\"center\");' \$W/fn \
   && grep -q 'CGRect u = DMUsableArea(); CGFloat bar = DMMenuBarHeight();' \$W/fn && grep -q 'if (CGRectGetMinY(u) < bar) u = CGRectMake(u.origin.x, bar, u.size.width, MAX(100.0, CGRectGetMaxY(u) - bar));' \$W/fn \
   && grep -q 'return MSBDWindowSizeFrameIn(choice, u, scr, DMCenterTopFor(scr), MSBDWindowMinSize());' \$W/fn \
   && awk '/^static CGRect DMSMUsableAreaForIdentity\(id identity, CGSize \*screenOut\) \{/,/^}/' $S | grep -q 'if (CGRectGetMinY(u) < bar) u = CGRectMake(u.origin.x, bar, u.size.width, MAX(100.0, CGRectGetMaxY(u) - bar));' \
   && grep -q 'static CGRect DMNewWindowFrame(void) { return DMA5StageFromWindow(DMNewWindowFrameWindowAt(gWindowSizeChoice)); }' $S"
check "  ... read with the other preferences (never set or anything but small / large: Default), from the stored value as Settings reads it" \
  "grep -q 'CFPropertyListRef ws = CFPreferencesCopyValue(CFSTR(kMSBDWindowSizeKey), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
   && grep -q 'int size = MSBDWindowSizeFromStored(ws);' $S && grep -q '        gWindowSizeChoice = size;' $S && grep -q 'int size = MSBDWindowSizeFromStored(v);' $P"
check "the layouts keep theirs: the center layout from the same header (the same numbers), Medium as it was; the Window menu's Small and Large are Window Size's own windows (one definition, its Large no longer 86% x 92%)" \
  "grep -q 'if (\\[name isEqualToString:@\"center\"\\]) return MSBDWindowCenterIn(u, screen, DMCenterTopFor(screen));' $S \
   && grep -q 'if (\\[name isEqualToString:@\"small\"\\]) return MSBDWindowSizeShapeIn(MSBDWindowSizeSmall, u, screen, DMCenterTopFor(screen));' $S \
   && grep -q 'if (\\[name isEqualToString:@\"large\"\\]) return MSBDWindowSizeShapeIn(MSBDWindowSizeLarge, u, screen, DMCenterTopFor(screen));' $S \
   && grep -q 'if (\\[name isEqualToString:@\"medium\"\\]) return MSBDWindowShareIn(u, 0.66, 0.74);' $S \
   && ! awk '/^static CGRect DMLayoutFrameInArea\(NSString \*name, CGRect u, CGSize screen\) \{/,/^}/' $S | grep -q '0\.86\|0\.92' \
   && grep -q 'CGRect f = MSBDWindowSizeShapeIn(size, u, screen, top);' ../common/WindowSize.h"
check "Zetsu: a new window asked for nowhere and with no last place opens at the new window (DMZetsuAdopt); its last place is kept" \
  "fn 'static void DMZetsuAdopt(UIWindow *w) {' && grep -q 'NSValue \*lastPlace = gLastWindowFrames\\[bundleID\\];' \$W/fn && grep -q 'CGRect target = asked ? askedFrame : (inTile ? tile : (lastPlace ? lastPlace.CGRectValue : DMOpeningWindowFrameFor(bundleID)));' \$W/fn \
   && grep -q 'if (MSBDZetsuOpensAtOwnPlace(asked, lastPlace != nil) && !CGRectIsNull(target)) DMMarkOwnPlace(w, target);' \$W/fn"
check "MilkyWay4: the same (DMEnlargeNewWindow), its own copy of the middle place gone; asked for or remembered first" \
  "fn 'static BOOL DMEnlargeNewWindow(UIView *window) {' && grep -q 'CGRect big = pending ? gPendingWindowFrame' \$W/fn && grep -q '               : (remembered && !CGRectIsNull(usable)) ? DMFitInto(remembered.CGRectValue, usable)' \$W/fn \
   && grep -q '               : DMOpeningWindowFrameFor(bundle);   // (the app.s own size, App Window Sizes; else Window Size.s window, or Fill: New Windows Open at Fill)' \$W/fn && grep -q 'if (CGRectIsNull(big) || CGRectIsEmpty(big)) return NO;' \$W/fn && ! grep -q '0.78' \$W/fn"
check "Aerial: our launch opens at the new window (DMWindowedLaunch), and a window Aerial opens itself is moved there -- 5.x always (its own remembered frame), 3.0 at Small / Large with no last place of ours" \
  "fn 'static BOOL DMWindowedLaunch(NSString *bundleID) {' && grep -q 'CGRect target = DMOpeningWindowFrameFor(bundleID);' \$W/fn \
   && fn 'static void DMCascadeStage(UIView *stage) {' && grep -q 'BOOL a3Sized = gAerialFlavor == 3 && DMActiveEngine() == DMEngineAerial && !MSBDOpeningIsPlainDefault(app, gWindowSizeChoice, gNewWindowsFill) && !gLastWindowFrames\\[me\\];' \$W/fn \
   && grep -q 'if ((gAerialFlavor == 5 || a3Sized) && !preLaunched) {' \$W/fn && grep -q 'CGRect want = remembered ? DMFitInto(remembered.CGRectValue, usable) : DMOpeningWindowFrameFor(me);' \$W/fn \
   && grep -q 'if (remembered) ownPlace = YES;' \$W/fn"
check "  ... and every other way it opens one: into its tile (no frame), the side question not shown, the cold start of an app full screen first" \
  "grep -q 'if (CGRectIsNull(frame)) frame = DMNewWindowFrame();' $S && grep -q 'DMAerialTrigger(bundleID, frame);' $S && grep -q 'else launch(DMNewWindowFrame());' $S \
   && grep -q 'CGRect target = gLastWindowFrames\\[bundleID\\] ? gLastWindowFrames\\[bundleID\\].CGRectValue : DMOpeningWindowFrameFor(bundleID);' $S"
check "the green light's way back from full screen (Aerial, Zetsu, MilkyWay4): where the window last was, else the new window" \
  "fn 'static void DMWindowLayout(NSString *name) {' && grep -q 'if (gPreferRememberedFrame) target = gLastWindowFrames\\[bundleID\\] ? gLastWindowFrames\\[bundleID\\].CGRectValue : DMOpeningWindowFrameFor(bundleID);' \$W/fn"
check "No Fit: the new window at Small / Large (DMNoFitFrame), Stage Manager's too (DMSMNoFitPlace at both questions); at Default one rule on every engine (MSBDWindowNoFitIn: Stage Manager's was the middle place itself)" \
  "fn 'static CGRect DMNoFitFrame(void) {' && grep -q 'if (gWindowSizeChoice != MSBDWindowSizeDefault) return DMNewWindowFrame();' \$W/fn \
   && grep -q 'return MSBDWindowNoFitIn(DMLayoutFrame(@\"center\"), DMLayoutFrame(@\"fill\"));' \$W/fn \
   && [ \$(grep -c 'DMSMApplyPlacesIn(@{newB: DMSMNoFitPlace(st)}, st);' $S) = 2 ] && ! grep -q 'DMSMApplyLayoutsIn(@{newB: @\"center\"}' $S \
   && fn 'static id DMSMNoFitPlace(id stage) {' && grep -q 'CGRect f = DMWindowSizeChoiceFor(identity) != MSBDWindowSizeDefault ? DMSMNewWindowFrameIn(u, scr, identity) : MSBDWindowNoFitIn(DMSMLayoutFrameIn(@\"center\", u, scr), u);' \$W/fn \
   && grep -q 'return CGRectIsNull(f) ? @\"center\" : \\[NSValue valueWithCGRect:f\\];' \$W/fn"
check "the middle place is asked for nowhere else as a new window's (only No Fit's own default, DMNoFitFrame)" "[ \$(grep -c 'DMLayoutFrame(@\"center\")' $S) = 1 ] && fn 'static CGRect DMNoFitFrame(void) {' && grep -q 'DMLayoutFrame(@\"center\")' \$W/fn"
check "Stage Manager: a window with no size of its own -- nothing to start from, a full-screen one's, or one joining a desktop with a front window -- opens at the engines' new window (Default too), kept off the desktop's other windows by the engines' rule; its own is kept" \
  "fn 'static id DMSMJoinAttributesOn(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage, id identity) {' && grep -q 'BOOL fresh = !DMSMAttrsOwnSize(own);' \$W/fn && grep -q '            if (fresh) {' \$W/fn \
   && grep -q 'CGRect opening = DMSMOpeningFrameIn(bundle, u, scr, onDisplay, &atFill);' \$W/fn && grep -q 'if (CGRectIsNull(opening)) return nil;' \$W/fn \
   && grep -q 'if (atFill || n >= 32 || it == ownItem || DMSMKeyCovers(key, DMSMItemKey(it)) || DMSMAttrsFullScreen(sm\\[it\\])) continue;' \$W/fn \
   && grep -q 'CGRect o = DMSMWindowFrameOfAttrs(sm\\[it\\], scr);' \$W/fn && grep -q 'CGRect placed = atFill ? opening : MSBDWindowCascadeIn(opening, others, n, u, NO, &how);' \$W/fn \
   && grep -q 'CGRect card = MSBDWindowCardOf(placed, kSMBarH);' \$W/fn && grep -q 'pts = card.size; cp = CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card));' \$W/fn \
   && grep -q 'CGSize pts = DMSMFitSizeInPoints(sz.normalizedSize, sz.referenceBounds, 0, scr);' \$W/fn && grep -q '} else if (fresh) return nil;' \$W/fn \
   && ! grep -q 'CGSizeMake(0.6\\|0.6 \\* scr\\|BOOL cascaded\\|DMSMCascadeClear(' \$W/fn && ! grep -q 'DMSMCascadeClear' ../statusbar/SMFit.h \
   && fn 'static CGRect DMSMWindowFrameOfAttrs(id attrs, CGSize scr) {' && grep -q 'return MSBDWindowOfCard(CGPointMake(c.x \\* scr.width, c.y \\* scr.height), pts, kSMBarH);' \$W/fn"
check "  ... at every choice, Default the middle place (Stage Manager's own 60% x 72% gone), the engines' rule with Stage Manager's smallest window (since 1.8.8 DMSMNewWindowFrameAt, Window Size's window DMSMNewWindowFrameIn's at that display's choice)" \
  "fn 'static CGRect DMSMNewWindowFrameAt(int choice, CGRect u, CGSize scr) {' && grep -q 'if (CGRectIsNull(u) || CGRectIsEmpty(u) || scr.width < 1.0 || scr.height < 1.0) return CGRectNull;' \$W/fn \
   && ! grep -q 'gWindowSizeChoice\\|DMAppSizeOf' \$W/fn \
   && grep -q 'CGSize least = CGSizeMake(MAX(DMSMMinWindowWidth(scr), kMSBDWindowMinWidth), kMSBDWindowMinAppHeight + kSMBarH);' \$W/fn \
   && grep -q 'return MSBDWindowSizeFrameIn(choice, u, scr, DMCenterTopFor(scr), least);' \$W/fn \
   && grep -qF 'static CGRect DMSMNewWindowFrameIn(CGRect u, CGSize scr, id identity) { return DMSMNewWindowFrameAt(DMWindowSizeChoiceFor(identity), u, scr); }' $S"
check "the engines' one cascade: DMCascadeStage hands the rule every other window's frame, the desktop and its own place (Aerial, Zetsu, MilkyWay4) -- its own old loop gone" \
  "fn 'static void DMCascadeStage(UIView *stage) {' && grep -q 'for (UIView \\*o in others) if (nOthers < 32) otherFrames\\[nOthers++\\] = o.frame;' \$W/fn \
   && grep -q 'CGRect pick = MSBDWindowCascadeIn(base, otherFrames, nOthers, usable, ownPlace, &how);' \$W/fn && grep -q 'if (how == MSBDCascadeOwnKept) {' \$W/fn \
   && grep -q 'if (CGRectEqualToRect(pick, base)) return;' \$W/fn && ! grep -q 'stepX\\|+ 30.0\\|DMOverlapFraction' \$W/fn && ! grep -q 'DMOverlapFraction' $S \
   && grep -q 'if (gs && MSBDWindowOverlap(st.frame, gs.frame) > kMSBDCascadeCovers) covers = YES;' $S"
check "Aerial, the green light's way back from full screen with no place of its own: a new window (tiled or kept off the others) that then flies there, as on Zetsu and MilkyWay4 -- 5.x and 3.0; where it was asked: flown there and kept" \
  "fn 'static void DMWindowLayout(NSString *name) {' && grep -q 'BOOL asked = !gPreferRememberedFrame || gLastWindowFrames\\[bundleID\\] != nil;' \$W/fn \
   && grep -q 'if (asked) { gA5EntranceBundle = \\[bundleID copy\\]; gA5EntranceFrame = target; gA5EntranceAt = CACurrentMediaTime(); gAerialGreenNewBundle = nil; }' \$W/fn \
   && grep -q 'else { gA5EntranceBundle = nil; gAerialGreenNewBundle = \\[bundleID copy\\]; gAerialGreenNewAt = CACurrentMediaTime(); }' \$W/fn \
   && [ \$(grep -c 'if (!gPreferRememberedFrame || gLastWindowFrames\\[bundleID\\]) DM\\(Zetsu\\|MilkyWay\\)AskFrame(bundleID, target);' \$W/fn) = 2 ] \
   && fn 'static void DMAerial5AdoptNewStage(UIView *stage) {' && awk '/if \\(DMAerialGreenOpensNew\\(bundle\\)\\) \\{ DM_FEATURE_MARK\\(\"aerial-green-new-window\"\\); DMCascadeStage\\(stage\\); \\}/{a=NR} /DMAerial5BeginEntrance\\(stage\\);/{if(!b)b=NR} END{exit !(a && b == a + 1)}' \$W/fn \
   && fn 'static void DMStyleStage(UIView *stage) {' && grep -q 'BOOL asNew = DMAerialGreenOpensNew(DMStageBundle(stage));' \$W/fn \
   && grep -q 'dispatch_async(dispatch_get_main_queue(), ^{ if (asNew) DMCascadeStage(stage); DMBeginStageEntrance(stage, inner); });' \$W/fn \
   && fn 'static void DMBeginStageEntrance(UIView *stage, UIView *inner) {' && grep -q 'objc_setAssociatedObject(stage, kStageCascadedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \$W/fn \
   && fn 'static BOOL DMAerialGreenOpensNew(NSString *bundle) {' && grep -q 'if (mine) gAerialGreenNewBundle = nil;' \$W/fn && grep -q 'CACurrentMediaTime() - gAerialGreenNewAt < 4.0' \$W/fn"
check "Settings: Window Size in the Windows group -- Small / Default / Large, Default the default, SpringBoard told" \
  "plutil -convert json -o - $PL | python3 -c 'import json,sys
it=json.load(sys.stdin)[\"items\"]; g=None; ok=False
for x in it:
    if x.get(\"cell\")==\"PSGroupCell\": g=x.get(\"id\"); continue
    if x.get(\"key\")==\"windowSize\": ok = g==\"WINDOWS_GROUP\" and x.get(\"cell\")==\"PSLinkListCell\" and x.get(\"detail\")==\"PSListItemsController\" and x.get(\"validValues\")==[\"small\",\"default\",\"large\"] and x.get(\"validTitles\")==[\"Small\",\"Default\",\"Large\"] and x.get(\"default\")==\"default\" and x.get(\"label\")==\"Window Size\" and x.get(\"id\")==\"WINDOW_SIZE\" and x.get(\"defaults\")==\"com.besiktasliseba.macstatusbar\" and x.get(\"PostNotification\")==\"com.besiktasliseba.macstatusbar/prefsChanged\"
sys.exit(0 if ok else 1)'"
check "  ... Default is never written: picked, a stored value is taken away and SpringBoard told; Small / Large stored only when they change; shown as SpringBoard reads it" \
  "awk '/isEqual:@kMSBDWindowSizeKey\\]\\) \\{/{f=1} f{print} f&&/^\\t}/{exit}' $P > \$W/set && grep -q 'if (size != now) \\[super setPreferenceValue:@(MSBDWindowSizeName(size)) specifier:specifier\\];' \$W/set \
   && grep -q 'if (!stored) return;' \$W/set && grep -q 'CFPreferencesSetValue(CFSTR(kMSBDWindowSizeKey), NULL, kMSBBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' \$W/set \
   && grep -q 'notify_post(\"com.besiktasliseba.macstatusbar/prefsChanged\");' \$W/set && ! grep -q '\"default\"' \$W/set \
   && grep -q 'if (\\[\\[specifier propertyForKey:@\"key\"\\] isEqual:@kMSBDWindowSizeKey\\]) return @(MSBDWindowSizeName(MSBWindowSizeStored(NULL)));' $P"
check "  ... with Stage Manager as the engine the row stays (its windows open at it too), on the page and in the Settings search; the same key" \
  "awk '/^static inline BOOL MSBDStageManagerKeepsRow\\(NSString \\*key\\) \\{/,/^}/' $R | grep -q 'MSBDHandlesRow(key) || \\[key isEqualToString:kMSBDWindowSizeRowKey\\]' \
   && grep -q '#define kMSBDWindowSizeRowKey @\"windowSize\"' $R && grep -q '#define kMSBDWindowSizeKey \"windowSize\"' ../common/WindowSize.h \
   && grep -q '(s.stageManagerEngine && !MSBDStageManagerKeepsRow(key))' $R && grep -q 'BOOL itsToo = MSBDStageManagerKeepsRow(MSBDRowRuleKey(\\[sp propertyForKey:@\"key\"\\], sp.identifier));' $P"
check "the crash guard: a crash in this code is window code (windowing off), as the rest of the new window's" \
  "grep -qxF 'file MacStatusBarCore ^(WindowCards|WindowMinSize|WindowSize|FitPlan|SBLaunchRule|AerialHeld)\\.h\$ windowingEnabled' $C && grep -qF '|DMWindowed|DMNewWindow|DMInstallAppExitForget) windowingEnabled' $C"
# 1.8.8 F2 (a window whose first step was taken went up and left before a second step down: in front of the windows it opened over, their traffic
# lights hidden): test-windowsize.m built on copies of WindowSize.h with the cascade's order broken, and on the file before the fix; each must fail.
echo "-- the cascade's made-to-fail copies of WindowSize.h (1.8.8 F2; each must fail test-windowsize.m):"
wsrun() {   # wsrun <WindowSize.h> <dir>: test-windowsize.m built on that header; its exit code, 3 if it does not build
  mkdir -p "$2/common" "$2/statusbar" "$2/tools"
  cp "$1" "$2/common/WindowSize.h"; cp ../statusbar/WindowMinSize.h ../statusbar/SMFit.h "$2/statusbar/"; cp test-windowsize.m "$2/tools/"
  clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$2/t" "$2/tools/test-windowsize.m" > "$2/build" 2>&1 || return 3
  "$2/t"
}
wsmtf() {   # wsmtf <name> <perl substitution on WindowSize.h>
  local d="$W/wsmtf$((++wn))"; mkdir -p "$d"; cp ../common/WindowSize.h "$d/WindowSize.h"; perl -0pi -e "$2" "$d/WindowSize.h"
  cmp -s ../common/WindowSize.h "$d/WindowSize.h" && { echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; }
  wsrun "$d/WindowSize.h" "$d/tree" > "$d/out" 2>&1 && rc=0 || rc=$?
  if [ $rc = 3 ]; then echo "FAIL  made-to-fail copy $1 does not build (it must build and fail)"; head -5 "$d/tree/build"; fails=1
  elif [ $rc = 0 ]; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1
  else echo "PASS  made-to-fail copy $1 fails, as it must ($(grep -c '^FAIL:' "$d/out") checks)"; fi
}
wn=0
L='    for (int sign = 1; sign >= -1; sign -= 2) for (int k = 1; k <= 8; k++) {'
grep -qF "$L" ../common/WindowSize.h && echo "PASS  the cascade tries every step down and right before any up and left (1.8.8 F2)" || { echo "FAIL  the cascade's loop is not the one F2 wrote"; fails=1; }
wsmtf "each step down and right, then up and left (the order until 1.8.8)" 's/for \(int sign = 1; sign >= -1; sign -= 2\) for \(int k = 1; k <= 8; k\+\+\) \{/for (int k = 1; k <= 8; k++) for (int sign = 1; sign >= -1; sign -= 2) {/'
wsmtf "every step up and left first" 's/for \(int sign = 1; sign >= -1; sign -= 2\) for/for (int sign = -1; sign <= 1; sign += 2) for/'
wsmtf "one step down and right only, then up and left" 's/for \(int sign = 1; sign >= -1; sign -= 2\) for \(int k = 1; k <= 8; k\+\+\) \{/for (int sign = 1; sign >= -1; sign -= 2) for (int k = 1; k <= (sign > 0 ? 1 : 8); k++) {/'
wsmtf "no up and left at all (no room down and right: where it opened)" 's/for \(int sign = 1; sign >= -1; sign -= 2\) for/for (int sign = 1; sign >= 1; sign -= 2) for/'
echo "-- the file before F2 (f7f634f7, or its -reg twin 9dfd76d9: the same tree) fails test-windowsize.m:"
for c in f7f634f7 9dfd76d9; do git -C .. show $c:common/WindowSize.h > "$W/ws-f2base" 2>/dev/null && break; rm -f "$W/ws-f2base"; done
if [ -s "$W/ws-f2base" ]; then
  wsrun "$W/ws-f2base" "$W/f2base" > "$W/f2base.out" 2>&1 && rc=0 || rc=$?
  if [ $rc = 0 ] || [ $rc = 3 ]; then echo "FAIL  the file before F2 passes or does not build (rc $rc)"; fails=1
  elif ! grep -q "^FAIL: the iPad 2's row A6: the first iPhone window {402.00, 47.07, 320.00, 650.00} (how 1), the second {302.00, 20.00, 320.00, 650.00} (how -1)" "$W/f2base.out"; then
    echo "FAIL  the file before F2 fails, but not on the iPad 2's row A6 as the s01 pass saw it ({302, 20})"; fails=1
  else echo "PASS  the file before F2 fails, the iPad 2's row A6 as on the device ({402, 47.07} then {302, 20}; $(grep -c '^FAIL:' "$W/f2base.out") checks)"; fi
else echo "SKIP  f7f634f7 (9dfd76d9) not in this repository"; fi
[ $fails = 0 ] && echo "test-windowsize: wiring checks pass" || { echo "test-windowsize: wiring checks FAILED"; exit 1; }
