#!/bin/bash
# Mac test of New Windows Open at Fill (1.8.3 item 2, KeyPilot's author's design: Settings > Windows & Multitasking, off unless switched on): the rule
# (common/WindowSize.h, test-newwindowsfill.c), then the sites in the code as built -- every engine's way of opening a window with no place of its
# own asks the one opening frame (the windowed launch, Aerial's cascade, Zetsu's and MilkyWay4's new window, the green light's way back, the Stage
# Manager join), applied where a window opens and never on a layout pass, Fit to Window leaves such a window out on every engine (no side question),
# and the Settings row.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tnf" test-newwindowsfill.c
"$W/tnf"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; PL=../statusbar/macstatusbarprefs/Resources/Windows.plist
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $S > "$W/fn"; }
check "the switch: read with the other preferences, off unless switched on" \
  "grep -q 'CFPropertyListRef fr = CFPreferencesCopyValue(CFSTR(kMSBDNewWindowsFillKey), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' $S \
   && grep -q 'static BOOL gNewWindowsFill = NO;' $S"
check "one opening frame: Window Size's window, or Fill with the switch on (the engine's frame: Aerial 5.x's stage); since 1.8.8 the app's own size first (App Window Sizes, common/AppWindowSize.h MSBDOpeningSize: with no entry the switch decides as before)" \
  "fn 'static CGRect DMOpeningWindowFrameFor(NSString *bundle) {' && grep -q 'int app = DMAppSizeOf(bundle), s = MSBDOpeningSize(app, gWindowSizeChoice, gNewWindowsFill);' \$W/fn \
   && grep -q 'if (s == kMSBDOpenFill) {' \$W/fn && grep -q 'return DMLayoutFrame(@\"fill\");' \$W/fn && grep -q 'return DMA5StageFromWindow(DMNewWindowFrameWindowAt(s));' \$W/fn"
check "asked by every engine's opening: the windowed launch (twice), Zetsu's and MilkyWay4's new window, Aerial's cascade, the green light's way back" \
  "[ \$(grep -c 'DMOpeningWindowFrameFor(\\(bundle\\|bundleID\\|me\\))' $S) = 6 ] && ! grep -q 'DMOpeningWindowFrame()' $S && fn 'static BOOL DMWindowedLaunch(NSString *bundleID) {' && grep -q 'CGRect target = DMOpeningWindowFrameFor(bundleID);' \$W/fn \
   && fn 'static void DMZetsuAdopt(UIWindow *w) {' && grep -q 'lastPlace.CGRectValue : DMOpeningWindowFrameFor(bundleID)));' \$W/fn \
   && fn 'static BOOL DMEnlargeNewWindow(UIView *window) {' && grep -q ': DMOpeningWindowFrameFor(bundle);' \$W/fn \
   && fn 'static void DMWindowLayout(NSString *name) {' && grep -q 'if (gPreferRememberedFrame) target = gLastWindowFrames\\[bundleID\\] ? gLastWindowFrames\\[bundleID\\].CGRectValue : DMOpeningWindowFrameFor(bundleID);' \$W/fn"
check "  ... and nowhere else: No Fit's window and a window put back at the standard place stay Window Size's" \
  "fn 'static CGRect DMNoFitFrame(void) {' && grep -q 'return DMNewWindowFrame();' \$W/fn && ! grep -q 'DMOpeningWindowFrame' \$W/fn"
check "Aerial, Zetsu, MilkyWay4: where a window is adopted (DMCascadeStage) one with no place of its own is put at Fill (one an engine opened elsewhere too), kept there, out of Fit's tiles" \
  "fn 'static void DMCascadeStage(UIView *stage) {' && grep -q 'BOOL own = ownPlace || (DMActiveEngine() == DMEngineAerial && DMOpensAtOwnPlace(me));' \$W/fn \
   && grep -q 'BOOL atFill = MSBDNewWindowAtFill(MSBDOpeningSize(app, gWindowSizeChoice, gNewWindowsFill) == kMSBDOpenFill, own, preLaunched);' \$W/fn && grep -q '    if (atFill) {' \$W/fn \
   && grep -q 'if (fabs(base.origin.x - usable.origin.x) > 1.0 || fabs(base.origin.y - usable.origin.y) > 1.0 || fabs(base.size.width - usable.size.width) > 1.0 || fabs(base.size.height - usable.size.height) > 1.0) {' \$W/fn && grep -q 'if (!DMIsZetsuWindow(stage)) DMSetStageIntent(stage, usable);' \$W/fn && grep -q 'if (fitOn) DMMarkFreeWindow(me);' \$W/fn \
   && awk '/    if \(atFill\) \{/{a=NR} /if \(fitOn && \[gFreeWindows containsObject:me\]\) goto regularWindow;/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && grep -q '!MSBDOpeningIsPlainDefault(app, gWindowSizeChoice, gNewWindowsFill) && !gLastWindowFrames\\[me\\];' \$W/fn"
check "Stage Manager: the join's window with no size of its own is Fill, not moved on, out of Fit's tiles (a free window); since 1.8.8 the app's own size first (DMSMOpeningFrameIn: with no entry the switch of the display it joins decides as before)" \
  "fn 'static id DMSMJoinAttributesOn(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage, id identity) {' && grep -q 'CGRect opening = DMSMOpeningFrameIn(bundle, u, scr, onDisplay, &atFill);' \$W/fn \
   && grep -q 'BOOL opensFree = MSBDOpensFree(app, DMNewWindowsFillFor(onDisplay), false, false);' \$W/fn \
   && grep -q 'CGRect placed = atFill ? opening : MSBDWindowCascadeIn(opening, others, n, u, NO, &how);' \$W/fn \
   && grep -q 'if (opensFree && DMFitEnabled()) { if (!gSMFreeWindows) gSMFreeWindows = \\[NSMutableSet set\\]; \\[gSMFreeWindows addObject:key\\]; }' \$W/fn \
   && fn 'static CGRect DMSMOpeningFrameIn(NSString *bundle, CGRect u, CGSize scr, id identity, BOOL *atFill) {' && grep -q 'if (atFill) \\*atFill = s == kMSBDOpenFill;' \$W/fn \
   && grep -q 'if (s == kMSBDOpenFill) return DMSMLayoutFrameIn(@\"fill\", u, scr);' \$W/fn"
check "no side question for a window that opens at Fill, before its launch on every engine" \
  "fn 'static BOOL DMThirdWindowSides(NSString *bundleID, NSString **leftOut, NSString **rightOut) {' && grep -q 'if (!MSBDFitTakesOpening(YES, MSBDOpensFree(DMAppSizeOf(bundleID), gNewWindowsFill, DMOpensAtOwnPlace(bundleID), NO))) return NO;' \$W/fn \
   && fn 'static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **leftOut, NSString **rightOut) {' && grep -q 'if (!MSBDFitTakesOpening(YES, MSBDOpensFree(DMAppSizeOf(DMSMKeyBundle(bundle)), gNewWindowsFill, DMSMOpensAtOwnSize(bundle), NO))) return NO;' \$W/fn"
check "one 'opens at its own place' per engine for New Windows Open at Fill, asked before the launch and as the window comes (review 1.8.3 F5) -- for the Fill decision only: the cascade's own place is 1.8.2.2's (review P2-4)" \
  "grep -q 'static BOOL DMOpensAtOwnPlace(NSString \\*bundleID) { return bundleID.length && gLastWindowFrames\\[bundleID\\] != nil; }' $S \
   && fn 'static void DMCascadeStage(UIView *stage) {' && grep -q 'BOOL own = ownPlace || (DMActiveEngine() == DMEngineAerial && DMOpensAtOwnPlace(me));' \$W/fn \
   && grep -q 'if (remembered) ownPlace = YES;' \$W/fn && [ \$(grep -c 'DMOpensAtOwnPlace(' \$W/fn) = 1 ] && [ \$(grep -c 'DMOpensAtOwnPlace(' $S) = 4 ] \
   && awk '/^static void DMAppSizeDebugTrigger\(NSString \*cmd\) \{/,/^}/' $S | grep -qF 'MSBDOpensFree(app, gNewWindowsFill, DMOpensAtOwnPlace(b), NO)'"
# The cascade with every new switch off is 1.8.2.2's (review 1.8.3 P2-4): DMCascadeStage as built, its New Windows Open at Fill parts taken out --
# the Fill block, and the three lines that read the switch, each the same as 1.8.2.2's with it off (DMOpeningWindowFrame is DMNewWindowFrame then)
# -- equals 1.8.2.2's (cascade-fixtures/DMCascadeStage-1.8.2.2.txt, from d5f83ff). No iPad has Aerial 3.0 (all four: Aerial 5.1, 7 Nov).
# Since 1.8.8 also its App Window Sizes parts with no app listed (common/AppWindowSize.h, test-appwindowsize: with no entry every rule is 1.8.7's):
# the app's lookup, the own-size branch and its free mark after the cascade (ownSizeOpening is false), regularWindow's exception for it, and the
# lines that read the app's size, each the same as 1.8.2.2's with no entry and the switch off (MSBDOpeningIsPlainDefault(None, ws, NO) is ws ==
# Default; DMOpeningWindowFrameFor is DMNewWindowFrame). And the line taking 1.8.7.5's behind-the-Dock mark of a window that opens with no place of
# its own kept (review R1 of the port): with no entry no place is forgotten, and an app's exit takes the mark with its place, so it takes nothing.
# (The Fill part taken out holds, since the review of G1-G2, the line that ends Fit's full-screen record as the app's window opens not free,
# DMFitFullScreenOpensNew: it reads the opening's free test, and moves no window -- it is Fit's record, not the cascade's place; test-fitgreen.)
# (1.8.8 H2, KT's decision A: Fit to Window's part of the cascade keeps a minimized window in its arrangement and lets a window open on its own
#  while every tiled window is minimized -- not a switch's, Fit's own rule, DMFitOpensBesideMinimized since the H2-H5 review; test-fitminimized runs
#  it: each of its lines put back as it was. The H2-H5 review's fix 5 too: Aerial's window asked for at a place with no entrance cover is placed
#  there before the cascade does anything, as the cover's entrance keeps it and Zetsu's and MilkyWay4's adoption places theirs -- the asked place's
#  own rule, not a switch's)
cat > "$W/h2drop.py" <<'EOF'
import sys
s = sys.stdin.read()
for new, old in [
    ('    // (Aerial, a window asked to open at a place of the user\'s -- the green light\'s way back to where it was, a Window menu layout -- that came with\n    //  no entrance cover (the cover\'s entrance places it and marks it so: DMAerial5BeginEntrance, DMBeginStageEntrance): kept there and marked\n    //  placed, as Zetsu\'s and MilkyWay4\'s adoption marks theirs (DMMarkStagePlaced); the way back gives it its tile 0.6 s later (DMWindowLayout:\n    //  DMFitRejoinAfterFullScreen). It went through Fit\'s part below as a new window first, tiled with the windows on screen, then the way back put\n    //  it into its tile: with the other tiles minimized it was logged and marked as opened on its own, or tiled with a window that had, which was\n    //  then left on its half, outside the tiles -- the H2-H5 review, finding 5)\n    CGRect askedAt = CGRectNull;\n    if (DMActiveEngine() == DMEngineAerial && DMAerialAskedPlaceTake(me, &askedAt)) {\n        if (fabs(askedAt.origin.x - base.origin.x) > 1.0 || fabs(askedAt.origin.y - base.origin.y) > 1.0 || fabs(askedAt.size.width - base.size.width) > 1.0 || fabs(askedAt.size.height - base.size.height) > 1.0) {\n            gStageFrameBypass = YES;\n            [UIView performWithoutAnimation:^{ DMSetStageFrameSafe(stage, askedAt); [stage layoutIfNeeded]; }];\n            gStageFrameBypass = NO;\n        }\n        DM_FEATURE_MARK("aerial-asked-place-no-cover");\n        DMMarkStagePlaced(stage, askedAt);\n        return;\n    }\n',
     ''),
    ("        // Windows that have gone (closed, or on another desktop: no stage here), windows on their way out (closing, to full screen) and hidden ones\n        // leave the arrangement. A minimized window stays in it with its tile (1.8.8 H2, KT's decision A, 19 Nov: minimized tiled windows keep their\n        // tiles on every engine, as our Stage Manager engine keeps them -- DMSMFitKeptAway), and comes back into it (DMFitShownAgain). Before, every\n        // window not on screen left it here: Settings minimized by Home while Clock was full screen, Clock's Dock icon, and Settings shown again\n        // was in no tile (Z11c, Z11 of p03 on the iPad 2, Zetsu; Aerial and MilkyWay4 the same).\n        for (NSString *b in [gFitGroup copy]) if (!DMFitKeepsTile(DMStageForBundle(b))) [gFitGroup removeObject:b];\n",
     '        // Windows that have gone, and windows that are minimized, hidden or closing: they are not on screen, so they don\'t take a tile. (Bug, the owner:\n        // with one app minimized, every app opened on its own was still squeezed into half the screen -- log: "0 other windows" then "2 windows\n        // tiled" -- because a minimized window still has its stage, so the old "has it gone?" test kept it in the group.)\n        for (NSString *b in [gFitGroup copy]) if (!DMStageTakesPartInFit(DMStageForBundle(b))) [gFitGroup removeObject:b];\n'),
    ('        // Every window of the arrangement minimized (1.8.8 H2): it opens on its own, or joins them -- DMFitOpensBesideMinimized, the rule the Mac\n        // Switcher\'s join takes too (MacSwitcher.h DMMSWFitBringHere).\n        if (DMFitOpensBesideMinimized(stage, me, gFitGroup, loose)) goto regularWindow;\n',
     ''),
    ("        // Two windows each cover a side and a third opens: ask on which side it goes. (Both on screen, as the question before a launch counts them --\n        // DMThirdWindowSides, our Stage Manager engine's DMSMFitAsksAbout --: with one of them minimized it takes the first tile, the others keeping\n        // their places, 1.8.8 H2.)\n",
     '        // Two windows each cover a side and a third opens: ask on which side it goes.\n'),
    ('            if (!DMStageTakesPartInFit(a) || !DMStageTakesPartInFit(b)) a = b = nil;\n',
     ''),
]:
    if s.count(new) == 1: s = s.replace(new, old)
sys.stdout.write(s)
EOF
fill_off_is_1822() {
  fn 'static void DMCascadeStage(UIView *stage) {'
  python3 -I "$W/h2drop.py" < "$W/fn" > "$W/fn.h2" && mv "$W/fn.h2" "$W/fn"
  awk 'index($0, "    // New Windows Open at Fill (1.8.3 item 2") == 1 {skip=1} skip && /^    }$/ {skip=0; next}
       index($0, "    // App Window Sizes (1.8.8, design 1.3)") == 1 {own=1} own {if (index($0, "    if (ownSizeOpening) goto regularWindow;") == 1) own=0; next}
       index($0, "    if (ownSizeOpening) {   // (App Window Sizes") == 1 {mark=1} mark {if ($0 ~ /^    }$/) mark=0; next}
       index($0, "    int app = DMAppSizeOf(me);   // (App Window Sizes, 1.8.8") == 1 {next}
       index($0, "    if (DMActiveEngine() == DMEngineAerial && !gLastWindowFrames[me]) DMBehindDockSet(me, NO, @\"its window opens with no place of its own kept (App Window Sizes)\");") == 1 {next}
       !skip {print}' "$W/fn" \
    | sed -e 's/!MSBDOpeningIsPlainDefault(app, gWindowSizeChoice, gNewWindowsFill)/gWindowSizeChoice != MSBDWindowSizeDefault/' \
          -e 's|DMOpeningWindowFrameFor(me);   // (where a new window opens: the app.s own size, Window Size, or Fill)|DMNewWindowFrame();   // (where a new window opens: Window Size)|' \
          -e 's/ : MSBDAppSizeValid(app) ? \[NSString stringWithFormat:@"the app.s own size (App Window Sizes %s)", MSBDAppSizeName(app)\] : gNewWindowsFill ? @"Fill (New Windows Open at Fill)" : \[NSString/ : [NSString/' \
          -e 's/if (\[gFreeWindows containsObject:me\] \&\& !ownSizeOpening) return;/if ([gFreeWindows containsObject:me]) return;/' > "$W/cas"
  diff -q "$W/cas" cascade-fixtures/DMCascadeStage-1.8.2.2.txt >/dev/null
}
check "with every new switch off the cascade (Aerial 3.0 and 5.x, Zetsu, MilkyWay4) is 1.8.2.2's, line for line, but for what reads New Windows Open at Fill (review 1.8.3 P2-4)" \
  "fill_off_is_1822 && fn 'static CGRect DMOpeningWindowFrameFor(NSString *bundle) {' && grep -q 'int app = DMAppSizeOf(bundle), s = MSBDOpeningSize(app, gWindowSizeChoice, gNewWindowsFill);' \$W/fn"
check "  ... Stage Manager's: the side question and the join read the same size of its own (its own window's, one from before our full screen; not one Stage Manager works out itself)" \
  "grep -q 'static BOOL DMSMOpensAtOwnSize(NSString \\*key) { return DMSMAttrsOwnSize(DMSMOwnAttrsFor(key, YES, NULL)); }' $S \
   && fn 'static id DMSMJoinAttributesOn(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage, id identity) {' && grep -q 'id own = DMSMOwnAttrsFor(key, windowed, &ownItem);' \$W/fn && grep -q 'BOOL fresh = !DMSMAttrsOwnSize(own);' \$W/fn \
   && fn 'static BOOL DMSMAttrsOwnSize(id attrs) {' && grep -q 'return attrs && !DMSMAttrsFullScreen(attrs) && DMSMAttrAttributedSize(attrs, &sz) && sz.type != 3 && sz.normalizedSize.width > 0 && sz.normalizedSize.height > 0;' \$W/fn"
check "never on a layout pass: the layouts and Fit's own tiling ask no opening frame" \
  "fn 'static void DMApplyGroupSlots(UIView *fresh) {' && ! grep -q 'gNewWindowsFill\\|DMOpeningWindowFrame' \$W/fn && fn 'static void DMSMFitTick(BOOL force) {' && ! grep -q 'gNewWindowsFill' \$W/fn"
check "the Settings row: Windows & Multitasking, a switch of its own group, off by default, posted to SpringBoard" \
  "plutil -convert json -o - $PL | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; r=[x for x in it if x.get(\"key\")==\"newWindowsFill\"]; sys.exit(0 if len(r)==1 and r[0][\"cell\"]==\"PSSwitchCell\" and r[0][\"default\"]==False and r[0][\"label\"]==\"New Windows Open at Fill\" and r[0][\"PostNotification\"]==\"com.besiktasliseba.macstatusbar/prefsChanged\" and r[0][\"defaults\"]==\"com.besiktasliseba.macstatusbar\" else 1)'"
exit $fails
