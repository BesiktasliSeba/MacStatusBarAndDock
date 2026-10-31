#!/bin/bash
# Mac test of one turn rule on every engine, Fit to Window's spread and the saved windows across engines (statusbar/TurnPlace.h, test-turnplace.c;
# 1.7.4 items 4, 5, 7, 11, 14), then the sites in the code as built: each engine's turn, Fit's switch-off, the save and the restore, and the Stage
# Manager engine's minimized windows and title-bar drop (items 1, 13).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/ttp" test-turnplace.c
"$W/ttp"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
# item 5: Aerial, Zetsu, MilkyWay4
check "item 5: each window's layout is noted while the screen keeps its shape (not while a hand moves it, not while it is not shown), held after a change" \
  "grep -q 'int i = MSBDTurnLayoutIndex(f, t, kMSBDTurnLayoutCount, kMSBDTurnLayoutTolerance);' $S && grep -q 'objc_setAssociatedObject(st, kStageLayoutNameKey, i >= 0 ? @(kMSBDTurnLayouts\[i\]) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' $S && grep -q 'if (t - lastNote >= 1.0 && DMActiveEngine() != DMEngineNone) { lastNote = t; DMNoteWindowLayouts(); }' $S && grep -q 'DMLayoutNoteHold(2.4);   // (the layouts noted are the old shape' $S"
check "item 5: the turn puts a window into its layout of the new shape first, then where it was in that shape, then in proportion (fitted)" \
  "grep -q 'CGRect f = MSBDTurnPlaceFor(lay.length ? DMLayoutFrame(lay) : CGRectNull, saved ? saved.CGRectValue : CGRectNull, DMScaleFrame(from, fromScreen, newSize), &why);' $S && grep -q 'if (why != MSBDTurnLayout) f = DMFitInto(f, usable);' $S"
check "item 5: a Mac Switcher desktop that comes back turned keeps the layouts its windows had (the hold before its turn)" \
  "grep -q 'DMLayoutNoteHold(2.4);   // (the layouts its windows had when it was left' ../statusbar/MacSwitcher.h"
# items 7 and 11: Stage Manager
check "items 7/11: Stage Manager notes each window's layout and its frame per shape while still, not under the App Switcher, a slide or a transition" \
  "grep -q 'if (!turnPending && now - lastSnap >= 1.0 && !(gSidePromptCtx && !\[gSidePromptCtx\[@\"decided\"\] boolValue\]) && !DMSwitcherVisible() && !gMSWSwitching && DMFrontApp() && !DMSMWorkspaceBusy()) { lastSnap = now; DMSMTurnNote(); }' $S && grep -q 'by\[shape\] = frames\[b\];' $S"
check "items 7/11: the turn's records are the shape before it until its body has run (only that turn's body ends the wait)" \
  "grep -q 'unsigned gen = ++turnGen;' $S && grep -q 'if (gen == turnGen) { turnPending = NO; lastSnap = CACurrentMediaTime() + 1.5; }' $S"
check "item 7: a window in no layout goes back where it was in this shape (Stage Manager scales it itself otherwise)" \
  "grep -q 'CGRect t = MSBDTurnPlaceFor(CGRectNull, was ? was.CGRectValue : CGRectNull, CGRectNull, &why);' $S"
check "item 11: the stages not on screen take the same rule in the model (layout, else the place in this shape), a full-screen window stays" \
  "grep -q 'id placed = lay ? DMSMAttrsForLayoutIn(a, lay, al) : (was ? DMSMAttrsForFrameIn(a, was.CGRectValue, al) : nil);' $S && grep -q 'if (k && !DMSMAttrsFullScreen(a)) {' $S && grep -q 'DMSMFitHiddenStages(frames.count ? DMSMWorkingStage() : nil, layouts, places);' $S"
# item 4: Fit to Window off
check "item 4: Fit to Window off spreads the tiles on every engine (Stage Manager: DMSMSpreadFit), one geometry" \
  "grep -q 'if (primed && wasOn && !now) { if (sm) DMSMSpreadFit(0); else DMSpreadFitGroup(); }' $S && [ \$(grep -c 'MSBDSpreadFrame((int)i, (int)' $S) = 2 ]"
check "item 4: Stage Manager's spread: only windows still in their own tiles, oldest first, the Medium size, one request; the arrangement let go" \
  "grep -q 'if (!\[slotNow isEqualToString:slots\[sk\]\] && !(\[slots\[sk\] isEqualToString:@\"fill\"\] && !slotNow)) continue;' $S && grep -q 'CGRect u = DMSMUsableAreaForStage(stage, &scr), size = DMSMLayoutFrameIn(@\"medium\", u, scr);' $S && grep -q 'BOOL ok = DMSMApplyPlacesIn(plan, stage);' $S && grep -q 'gSMFitSlots = nil;   // (let go' $S"
# item 14: the saved windows across an engine switch
check "item 14: the save names its frames' kind (Aerial 5.x's stage with its margins, or the window), the restore turns them into this engine's" \
  "grep -q 'if (DMA5MacGeometry()) { saving\[@\"frameKind\"\] = @\"a5stage\"; saving\[@\"a5margins\"\] = NSStringFromUIEdgeInsets(gA5Insets); }' $S && grep -q 'CGRect f = DMSavedFrameForThisEngine(CGRectFromString(w\[@\"frame\"\]), state, bundle, waited == 0);' $S && grep -q 'CGRect g = MSBDSavedFrameForEngine(f, savedStage, sm, nowStage, nm, &converted);' $S"
# item 1: a minimized window on another desktop (Stage Manager)
check "item 1: a minimized Stage Manager window takes the Go / Bring decision as any window (no minimized exception)" \
  "grep -q 'if (!gMSWSwitching && DMMSWSMElsewhere(key)) {' ../statusbar/MacSwitcherSM.h && ! grep -q '!wasMinimized && !gMSWSwitching' ../statusbar/MacSwitcherSM.h"
check "item 1: SpringBoard's own transition to a minimized window of another desktop (card, Command-Tab) with Go on: opened again there, not by a gesture" \
  "grep -q 'if (reopenAsk && askedW.count == 1 && !(flags & ~DMSMJoinOtherDesk) && !(\[label0 isKindOfClass:\[NSString class\]\] && \[label0 isEqualToString:@\"FinalFluidSwitcherGestureAction\"\])' ../statusbar/SMDesktop.h && grep -q 'if (reopened && DMSMJoinMinimizedGo(ctx, asked, askedW, flags, identity, reopened)) return;' ../statusbar/SMDesktop.h && grep -q 'if (!gMSWOn || !gMSWGoToAppDesk || !DMSMEngine() || !DMMSWMulti() || gMSWSwitching || !k.length || !DMSMIsMinimized(k)) return NO;' ../statusbar/SMDesktop.h"
# item 11: the place before full screen, across a respring
check "item 11: Stage Manager keeps each window's place before full screen in its state file (with the minimized set: one writer) and the green finds it after a respring" \
  "grep -q 'DMSMPreZoomPlaces()\[wk\] = @{@\"f\": NSStringFromCGRect(on.CGRectValue), @\"s\": NSStringFromCGSize(scr)};' $S && grep -q 'back = DMSMAttrsForFrameIn(attrs, f, stage);' $S && [ \$(grep -c 'DMSMStateWrite();' $S) -ge 4 ] && ! grep -q 'writeToFile:DMSMStatePath()' <(grep -v 'static void DMSMStateWrite' $S | grep -v '\[st writeToFile:DMSMStatePath() atomically:YES\];')"
check "item 11: Aerial, Zetsu and MilkyWay4 keep the green's places of apps not in a window with the saved windows, and get them back first at a restore" \
  "grep -q 'if (places.count) saving\[@\"lastFrames\"\] = places;' $S && awk '/NSDictionary \*state = \[NSDictionary dictionaryWithContentsOfFile:DMWindowStatePath\(\)\];/{a=NR} /DMRestoreLastFrames\(state\);   \/\/ \(1.7.4 item 11/{b=NR} /if \(!wins.count\) \{ gWindowSaveOn = YES; return; \}/{c=NR} END{print (a&&b&&c&&a<b&&b<c) ? \"ok\" : \"no\"}' $S | grep -q ok"
check "  ... and never keeps more than the windows still in a stage once there are over 64 (a window closed while full screen left its place for good), the one just kept stays" \
  "awk '/^static void DMSMPreZoomPrune\\(NSString \\*keep\\) \\{/,/^}/' $S | awk '/if \\(gSMPreZoomPlaces.count <= 64\\) return;/{a=1} a && /if \\(!alive.count\\) return;/{b=1} b && /if \\(\\[k isEqualToString:keep\\] \\|\\| \\[alive containsObject:k\\]\\) continue;/{c=1} c && /if \\(!covered\\) \\[gSMPreZoomPlaces removeObjectForKey:k\\];/{print \"ok\"; exit}' | grep -q ok && awk '/DMSMPreZoomPlaces\\(\\)\\[wk\\] = @\\{/{p=NR} /DMSMPreZoomPrune\\(wk\\);/{q=NR} /DMSMStateWrite\\(\\);/{if (q && !w) w=NR} END{exit !(p && q == p + 1 && w == q + 1)}' $S"
# item 13: Stage Manager's title-bar drop
check "item 13: a title-bar drop in open space asks for the dropped card's middle, not its anchor's point (the snap path's way)" \
  "grep -q 'CGRect dropped = \[card convertRect:card.bounds toView:sup\];' $S && grep -q 'else if (b.width > 0 && b.height > 0) DMSMSetWindowGeometry(w, CGPointMake(mid.x / b.width, mid.y / b.height), CGSizeZero);' $S"
check "item 13: Stage Manager's window drag (_unpinSplitViewApplicationGestureRecognizer) leaves a touch on our title bar to the bar -- not a pointer press on its resize band; installed with the engine, not only with Finder" \
  "grep -q 'if (DMSMTitleBarDragTouch(self, g, touch)) return NO;' $S && grep -q 'iv = class_getInstanceVariable(ivClass, \"_unpinSplitViewApplicationGestureRecognizer\");' $S && grep -q 'if (t.type == UITouchTypeIndirectPointer && DMSMPointerOnResizeEdge(bar.card)) return NO;' $S && grep -q 'DMNativeSysGesturesInit();  // (Stage Manager' $S && [ \$(grep -c '%init(DMNativeSysGestures);' $S) = 1 ]"
[ $fails = 0 ] && echo "test-turnplace: site checks pass" || { echo "test-turnplace: site checks FAILED"; exit 1; }
