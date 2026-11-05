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
  "fn 'static CGRect DMNewWindowFrameWindow(void) {' && grep -q 'if (gWindowSizeChoice == MSBDWindowSizeDefault) return DMLayoutFrameWindow(@\"center\");' \$W/fn \
   && grep -q 'CGRect u = DMUsableArea(); CGFloat bar = DMMenuBarHeight();' \$W/fn && grep -q 'if (CGRectGetMinY(u) < bar) u = CGRectMake(u.origin.x, bar, u.size.width, MAX(100.0, CGRectGetMaxY(u) - bar));' \$W/fn \
   && grep -q 'return MSBDWindowSizeFrameIn(gWindowSizeChoice, u, scr, DMCenterTopFor(scr), MSBDWindowMinSize());' \$W/fn \
   && awk '/^static CGRect DMSMUsableAreaForIdentity\(id identity, CGSize \*screenOut\) \{/,/^}/' $S | grep -q 'if (CGRectGetMinY(u) < bar) u = CGRectMake(u.origin.x, bar, u.size.width, MAX(100.0, CGRectGetMaxY(u) - bar));' \
   && grep -q 'static CGRect DMNewWindowFrame(void) { return DMA5StageFromWindow(DMNewWindowFrameWindow()); }' $S"
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
  "fn 'static void DMZetsuAdopt(UIWindow *w) {' && grep -q 'NSValue \*lastPlace = gLastWindowFrames\\[bundleID\\];' \$W/fn && grep -q 'CGRect target = asked ? askedFrame : (inTile ? tile : (lastPlace ? lastPlace.CGRectValue : DMNewWindowFrame()));' \$W/fn \
   && grep -q 'if (MSBDZetsuOpensAtOwnPlace(asked, lastPlace != nil) && !CGRectIsNull(target)) DMMarkOwnPlace(w, target);' \$W/fn"
check "MilkyWay4: the same (DMEnlargeNewWindow), its own copy of the middle place gone; asked for or remembered first" \
  "fn 'static BOOL DMEnlargeNewWindow(UIView *window) {' && grep -q 'CGRect big = pending ? gPendingWindowFrame' \$W/fn && grep -q '               : (remembered && !CGRectIsNull(usable)) ? DMFitInto(remembered.CGRectValue, usable)' \$W/fn \
   && grep -q '               : DMNewWindowFrame();' \$W/fn && grep -q 'if (CGRectIsNull(big) || CGRectIsEmpty(big)) return NO;' \$W/fn && ! grep -q '0.78' \$W/fn"
check "Aerial: our launch opens at the new window (DMWindowedLaunch), and a window Aerial opens itself is moved there -- 5.x always (its own remembered frame), 3.0 at Small / Large with no last place of ours" \
  "fn 'static BOOL DMWindowedLaunch(NSString *bundleID) {' && grep -q 'CGRect target = DMNewWindowFrame();' \$W/fn \
   && fn 'static void DMCascadeStage(UIView *stage) {' && grep -q 'BOOL a3Sized = gAerialFlavor == 3 && DMActiveEngine() == DMEngineAerial && gWindowSizeChoice != MSBDWindowSizeDefault && !gLastWindowFrames\\[me\\];' \$W/fn \
   && grep -q 'if ((gAerialFlavor == 5 || a3Sized) && !preLaunched) {' \$W/fn && grep -q 'CGRect want = remembered ? DMFitInto(remembered.CGRectValue, usable) : DMNewWindowFrame();' \$W/fn \
   && grep -q 'if (remembered) ownPlace = YES;' \$W/fn"
check "  ... and every other way it opens one: into its tile (no frame), the side question not shown, the cold start of an app full screen first" \
  "grep -q 'if (CGRectIsNull(frame)) frame = DMNewWindowFrame();' $S && grep -q 'DMAerialTrigger(bundleID, frame);' $S && grep -q 'else launch(DMNewWindowFrame());' $S \
   && grep -q 'CGRect target = gLastWindowFrames\\[bundleID\\] ? gLastWindowFrames\\[bundleID\\].CGRectValue : DMNewWindowFrame();' $S"
check "the green light's way back from full screen (Aerial, Zetsu, MilkyWay4): where the window last was, else the new window" \
  "fn 'static void DMWindowLayout(NSString *name) {' && grep -q 'if (gPreferRememberedFrame) target = gLastWindowFrames\\[bundleID\\] ? gLastWindowFrames\\[bundleID\\].CGRectValue : DMNewWindowFrame();' \$W/fn"
check "No Fit: the new window at Small / Large (DMNoFitFrame), Stage Manager's too (DMSMNoFitPlace at both questions); at Default one rule on every engine (MSBDWindowNoFitIn: Stage Manager's was the middle place itself)" \
  "fn 'static CGRect DMNoFitFrame(void) {' && grep -q 'if (gWindowSizeChoice != MSBDWindowSizeDefault) return DMNewWindowFrame();' \$W/fn \
   && grep -q 'return MSBDWindowNoFitIn(DMLayoutFrame(@\"center\"), DMLayoutFrame(@\"fill\"));' \$W/fn \
   && [ \$(grep -c 'DMSMApplyPlacesIn(@{newB: DMSMNoFitPlace(st)}, st);' $S) = 2 ] && ! grep -q 'DMSMApplyLayoutsIn(@{newB: @\"center\"}' $S \
   && fn 'static id DMSMNoFitPlace(id stage) {' && grep -q 'CGRect f = gWindowSizeChoice != MSBDWindowSizeDefault ? DMSMNewWindowFrameIn(u, scr) : MSBDWindowNoFitIn(DMSMLayoutFrameIn(@\"center\", u, scr), u);' \$W/fn \
   && grep -q 'return CGRectIsNull(f) ? @\"center\" : \\[NSValue valueWithCGRect:f\\];' \$W/fn"
check "the middle place is asked for nowhere else as a new window's (only No Fit's own default, DMNoFitFrame)" "[ \$(grep -c 'DMLayoutFrame(@\"center\")' $S) = 1 ] && fn 'static CGRect DMNoFitFrame(void) {' && grep -q 'DMLayoutFrame(@\"center\")' \$W/fn"
check "Stage Manager: a window with no size of its own -- nothing to start from, a full-screen one's, or one joining a desktop with a front window -- opens at the engines' new window (Default too), kept off the desktop's other windows by the engines' rule; its own is kept" \
  "fn 'static id DMSMJoinAttributes(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage) {' && grep -q 'BOOL fresh = dflt || base != own;' \$W/fn && grep -q '            if (fresh) {' \$W/fn \
   && grep -q 'CGRect opening = DMSMNewWindowFrameIn(u, scr);' \$W/fn && grep -q 'if (CGRectIsNull(opening)) return nil;' \$W/fn \
   && grep -q 'if (n >= 32 || it == ownItem || DMSMKeyCovers(key, DMSMItemKey(it)) || DMSMAttrsFullScreen(sm\\[it\\])) continue;' \$W/fn \
   && grep -q 'CGRect o = DMSMWindowFrameOfAttrs(sm\\[it\\], scr);' \$W/fn && grep -q 'CGRect placed = MSBDWindowCascadeIn(opening, others, n, u, NO, &how);' \$W/fn \
   && grep -q 'CGRect card = MSBDWindowCardOf(placed, kSMBarH);' \$W/fn && grep -q 'pts = card.size; cp = CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card));' \$W/fn \
   && grep -q 'CGSize pts = DMSMFitSizeInPoints(sz.normalizedSize, sz.referenceBounds, 0, scr);' \$W/fn && grep -q '} else if (fresh) return nil;' \$W/fn \
   && ! grep -q 'CGSizeMake(0.6\\|0.6 \\* scr\\|BOOL cascaded\\|DMSMCascadeClear(' \$W/fn && ! grep -q 'DMSMCascadeClear' ../statusbar/SMFit.h \
   && fn 'static CGRect DMSMWindowFrameOfAttrs(id attrs, CGSize scr) {' && grep -q 'return MSBDWindowOfCard(CGPointMake(c.x \\* scr.width, c.y \\* scr.height), pts, kSMBarH);' \$W/fn"
check "  ... at every choice, Default the middle place (Stage Manager's own 60% x 72% gone), the engines' rule with Stage Manager's smallest window" \
  "fn 'static CGRect DMSMNewWindowFrameIn(CGRect u, CGSize scr) {' && grep -q 'if (CGRectIsNull(u) || CGRectIsEmpty(u) || scr.width < 1.0 || scr.height < 1.0) return CGRectNull;' \$W/fn \
   && ! grep -q 'gWindowSizeChoice == MSBDWindowSizeDefault' \$W/fn \
   && grep -q 'CGSize least = CGSizeMake(MAX(DMSMMinWindowWidth(scr), kMSBDWindowMinWidth), kMSBDWindowMinAppHeight + kSMBarH);' \$W/fn \
   && grep -q 'return MSBDWindowSizeFrameIn(gWindowSizeChoice, u, scr, DMCenterTopFor(scr), least);' \$W/fn"
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
  "grep -q 'static inline BOOL MSBDStageManagerKeepsRow(NSString \\*key) { return MSBDHandlesRow(key) || \\[key isEqualToString:kMSBDWindowSizeRowKey\\]; }' $R \
   && grep -q '#define kMSBDWindowSizeRowKey @\"windowSize\"' $R && grep -q '#define kMSBDWindowSizeKey \"windowSize\"' ../common/WindowSize.h \
   && grep -q '(s.stageManagerEngine && !MSBDStageManagerKeepsRow(key))' $R && grep -q 'BOOL itsToo = MSBDStageManagerKeepsRow(\\[sp propertyForKey:@\"key\"\\]);' $P"
check "the crash guard: a crash in this code is window code (windowing off), as the rest of the new window's" \
  "grep -qxF 'file MacStatusBarCore ^(WindowCards|WindowMinSize|WindowSize|FitPlan|SBLaunchRule|AerialHeld)\\.h\$ windowingEnabled' $C && grep -qF '|DMWindowed|DMNewWindow|DMInstallAppExitForget) windowingEnabled' $C"
[ $fails = 0 ] && echo "test-windowsize: wiring checks pass" || { echo "test-windowsize: wiring checks FAILED"; exit 1; }
