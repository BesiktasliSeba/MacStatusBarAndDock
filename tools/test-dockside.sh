#!/bin/bash
# Mac test of Settings > Dock > Position (1.8.2; common/DockSide.h, test-dockside.c), then the sites in the code as built.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tds" test-dockside.c
"$W/tds"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
D=../dock/Dock.x
P=../dock/dockmagnificationprefs/Resources/Root.plist
check "the row: Settings > Dock, Bottom by default, Left and Right, posts the Dock's prefsChanged" \
  "plutil -convert xml1 -o - $P | grep -q '<string>dockPosition</string>' && plutil -convert xml1 -o - $P | grep -q '<string>Position on Screen</string>'"
check "one usable area: DMUsableArea asks the side first, on the bottom nothing else runs" \
  "grep -q 'int dockSide = DMDockSideNow(screen); if (dockSide) return DMDockSideDesktopOf(screen, dockSide);' $S"
check "Stage Manager's area asks the same desktop, whole width during a title-bar drag as the bottom's rule" \
  "grep -q 'CGRect u = DMDockSideDesktopOf(b.size, dockSide);' $S && grep -q 'CGFloat x0 = dragging ? CGRectGetMinX(b) : CGRectGetMinX(u)' $S"
check "the 18.5 height limit: Apple's bottom insets are [0] with the Dock at a side, shape-checked, left alone at the bottom" \
  "grep -q 'return DMSMFree() && (DMDockSideNow(\[UIScreen mainScreen\].bounds.size) || hides) ? @\[@0.0\] : v;' $S && grep -q 'if (mb && \[DMSMSigOfMethod(mb) isEqualToString:list\]) MSHookMessageEx(c, bot, (IMP)DMSMBottomInsets17, (IMP \*)&o_SMBottomInsets17);' $S"
check "the drop on every engine: moves and resizes, also with snapping off, keep out of the Dock (common/DockSide.h)" \
  "grep -q 'return DMDockSideKept(DMSnapFrameFor(DMStageBundle(st), window, how, others, n, DMUsableArea()), how);' $S && grep -q 'if (!st || (DMSnapOff() && !DMDockSideKeepsOut())) return;' $S && grep -q 'CGRect kept = DMDockSideKept(w.frame, MSBDSnapMove);' $S"
check "the Dock's menus: beside it, the arrow on the facing edge, reaching the icon's middle at the Dock's ends (1.8.2.2, iPad 2 F2)" \
  "grep -q 'CGRect f = dockSide ? MSBDArrowSideMenuFrameReaching(menu, src, bounds, reach, kMSBDArrowHeight, kMSBDArrowTipGap, kCtxMenuCorner, kMSBDArrowWidth, dockSide == MSBDDockRight, &dir)' $S"
check "the finger: Apple's y rule no longer holds the Dock out at a side, nor puts it away for a tap on its own icons: the rest of Apple's rule alone (code review 1.8.2, 9)" \
  "grep -q 'g == ((id (\*)(id, SEL))objc_msgSend)(self, @selector(dismissFloatingDockSystemGestureRecognizer))) return DMDockSideDismissTouch(self, touch);' $D \
   && grep -q 'if (DMDockSideControls(self) && \[self respondsToSelector:@selector(dismissFloatingDockSystemGestureRecognizer)\]' $D && ! grep -q 'apple || DMDockSideDismissTouch' $D"
check "the pointer: the bottom edge's reveal stands down at a side, the look named a workaround and off the main thread" \
  "grep -q 'if (gDockSideApplied && !gDockSideAskingApple) {' $D && grep -q 'WORKAROUND, named' $D"
check "nothing is hooked until Left or Right is chosen" \
  "grep -q 'if (gDockPosition != MSBDDockBottom) {' $D && grep -q '%init(DockSideRoot);' $D"
check "Finder's windows too: the drop keeps out, a position change lays them out again" \
  "grep -q 'dm_keepOutOfSideDock:MSBDSnapMove' ../statusbar/NativeWindow.h && grep -q 'DMNativeLayoutForDesktop(NO);' $S"
check "the Home Screen's icons stay: it asks the height the Dock would have at the bottom" \
  "grep -q '%group DockSideHome' $D && grep -q 'return h > 0.0 ? h : apple;' $D && grep -q 'gDockSideAsAtBottom = YES;' $D"
check "a folder in the Dock opens upright and an app icon lifts: the host's turn taken back, the real size given to UIKit" \
  "grep -q 'DMDockSideFoldersUpright(host, side);' $D && grep -q 'DMCtxSidePreviewSize(input);' $S"
check "Icon Size means the same icon as at the bottom, the fit taking over" \
  "grep -q 'longDock.userList.size.height / m->userList.size.height' $D"
check "the Dock's real root: a child of the window's own on 15.6.1" \
  "grep -q 'if (\[vc isKindOfClass:rc\]) { DMDockSideApplyToRoot(vc);' $D"
check "the desktop's files stay too: their saved places are shares of the area as at the bottom" \
  "grep -q 'a = \[self dm_placesArea:a\]; return CGPointMake' ../statusbar/Desktop.h && grep -q 'a = \[self dm_placesArea:a\]; return @\[' ../statusbar/Desktop.h && grep -q 'double MSBDDockHeightAtBottom(void)' $D"
check "the Home Screen keeps out of the Dock: each page's list placed beside it by SpringBoard's own frame method, shape-checked, hooked with a side chosen only" \
  "grep -q 'return DMDockSideHomeFrame((UIView \*)self, f, index);' $D && grep -q '{ %init(DockSideHomeLists); gDockSideHomeHooked = YES; }' $D && grep -q 'return MSBDDockSideHomeListFrame(f, side, gDockSideHomeRoom, fl, fr);' $D"
check "  ... in portrait and at the bottom iPadOS's own frames: decided by the page's own shape" \
  "grep -q 'int side = MSBDDockSideFor(gDockPosition, f.size.width, f.size.height);' $D"
check "  ... the room is the Dock's at rest, measured where the side Dock lays out (never the magnified icons), and moves the pages at once" \
  "grep -q 'DMDockSideHomeLaidOut(DMDockSideRestingRoom((UIView \*)self, platter));' $D && grep -q 'if (DMDockSidePresentedNow() || !(gDockSideHomeRoom > 0.0))' $D && grep -q 'DMDockSideHomeDockBack();' $D && grep -q 'DMDockSideHomeRelayout(@\"the Dock.s size\");' $D && grep -q 'DMDockSideHomeRelayout(side ? @\"the Dock at a side\" : @\"the Dock at the bottom\");' $D"
check "  ... the desktop's files stay on their page of the screen when page 1's list moves" \
  "grep -q 'self.frame = DMDesktopPageFrameIn(found);' ../statusbar/Desktop.h && grep -q 'void MSBDDesktopFollowPage(void)' ../statusbar/Desktop.h && grep -q 'CGRectInset(\[_list convertRect:v.frame toView:self\], -4.0, -4.0)' ../statusbar/Desktop.h"
check "  ... MacSettings' portrait places are never learnt from a list laid out again beside the Dock" \
  "grep -q 'fabs(list.bounds.size.width - page.bounds.size.width) > 0.5) return;' ../macsettings/IconLayout.x"
check "  ... the safety check after a Home Screen layout is in debug builds only" \
  "awk '/static void DMDockSideHomeCheckNow/{f=1} f&&/^#endif/{print; exit}' $D | grep -q endif && grep -B2 'DMDockSideHomeCheckHook();' $D | grep -q '#if DEBUG'"
check "a change of side lays the Dock itself out again: portrait and a side give its view the same bounds, so UIKit wouldn't" \
  "grep -A12 'if (changed) {' $D | grep -q 'UIView \*dockView = DMDockSideDockViewIn(host);' && grep -q '\[dockView setNeedsLayout\]; \[dockView layoutIfNeeded\];' $D"
check "the clock's Today panel keeps out of a side Dock: hung from the clock inside the span the desktop leaves, the narrowed panel too" \
  "grep -q 'MSBDPanelSpan span = MSBDDockSidePanelSpan(host.bounds.size.width, DMIsExtMenuHost(host) ? MSBDDockBottom : DMDockSideNow(\[UIScreen mainScreen\].bounds.size), DMUsableArea());' $S && grep -q 'CGFloat x = MSBDPanelHungX(anchor.origin.x, CGRectGetMaxX(anchor), W, span, DMBarRTL(fg));' $S && grep -q 'pf.origin.x = MAX(span.lo, right - pf.size.width);' $S"
check "no prototype flags left" "! grep -q 'msb-dockside' $S $D"
# (a function's body as built: from its first line to its closing brace)
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
M=../statusbar/MacSwitcher.h
moved() { fn 'static void DMDockPositionMoved(NSDictionary<NSString *, NSString *> *layouts) {' $S; }
check "a Position change places every desktop's windows on every engine (code review 1.8.2, 6): Aerial, Zetsu and MilkyWay4 over all their windows, not this desktop's only" \
  "moved | grep -q 'for (UIView \*st in DMAerialStagesAll()) {' && ! moved | grep -q 'DMAerialStages()' \
   && moved | grep -q 'BOOL away = \[objc_getAssociatedObject(st, kMSWAwayKey) boolValue\];'"
check "  ... one not shown (another desktop's, minimized into the Dock) placed without a move, its kept place too, as a turn places one; the engine's own minimized form left to it" \
  "moved | grep -q 'gStageFrameBypass = YES; DMSetStageFrameSafe(st, f); gStageFrameBypass = NO;' && moved | grep -q 'DMSetStageIntent(st, f);' \
   && moved | grep -q 'CGRect w = DMSnapWindowOfFrame(st, from);' && moved | grep -q 'if (!st.hidden) continue;' \
   && moved | grep -q 'CGRect t = name ? DMLayoutFrameWindow(name) : MSBDDockSideKeepOut(w, DMUsableArea(), MSBDDockKeepMove);'"
check "  ... Stage Manager's stages not on screen into the layouts their windows had when last on screen, as the other engines' windows" \
  "moved | grep -q 'NSMutableDictionary<NSString \*, NSString \*> \*noted = \[DMSMTurnLayouts() mutableCopy\];' && moved | grep -q 'DMSMFitHiddenStages(frames.count ? DMSMWorkingStage() : nil, noted, nil);'"
check "  ... what the Mac Switcher keeps of the other desktops follows on every engine: the away windows' places, a closed app's place, Finder's windows there" \
  "[ \$(moved | grep -c 'DMMSWDockMovedRecords();') = 2 ] && fn 'static void DMMSWDockMovedRecords(void) {' $M | grep -q 'gMSWWinFrame\[b\] = NSStringFromCGRect(t); gMSWDesksDirty = YES;' \
   && fn 'static void DMMSWDockMovedRecords(void) {' $M | grep -q 'CGRect t = alive\[b\] ? alive\[b\].frame : CGRectIsNull(usable) ? f : MSBDDockSideKeepOut(f, usable, MSBDDockKeepMove);' \
   && fn 'static void DMMSWDockMovedRecords(void) {' $M | grep -q 'for (DMNativeWindow \*w in gMSWAwayNatives) DMNativeLayoutOneForDesktop(w, desk);' \
   && fn 'static void DMNativeLayoutForDesktop(BOOL log) {' ../statusbar/NativeWindow.h | grep -q 'for (DMNativeWindow \*w in gNativeWindows) DMNativeLayoutOneForDesktop(w, desk);'"
check "the Dock's height as at the bottom asks a host it holds, and with none Apple's height, before its views are looked through (code review 1.8.2, 3: an array of nil)" \
  "fn 'static CGFloat DMDockSideHeightAtBottom(void) {' $D | awk '/UIView \*host = gDockSideHost;/{a=NR} /if \(!host\) return -1.0;/{b=NR} /UIView \*dockView = DMDockSideDockViewIn\(host\);/{c=NR} /arrayWithObject:/{bad=1} END{exit !(a && b == a + 1 && c > b && !bad)}' \
   && ! fn 'static CGFloat DMDockSideHeightAtBottom(void) {' $D | grep -q 'gDockSideHost\.' \
   && fn 'static UIView \*DMDockSideDockViewIn(UIView \*host) {' $D | grep -q 'NSMutableArray<UIView \*> \*look = host ? \[NSMutableArray arrayWithObject:host\] : \[NSMutableArray array\];'"
check "the pointer leaving: Apple's hover dismissal (the bottom's y rule) stands down for the Dock at a side, after the Downloads panel's hold, before Apple's (code review 1.8.2, 1)" \
  "awk '/^- \(void\)_handleDismissFloatingDockHoverGesture:\(id\)gesture \{/{f=1} f&&/if \(gKeepDockVisible\)/{a=NR} f&&/if \(DMDockSideControls\(self\)\) \{/{b=NR} f&&/^    %orig;/{c=NR} f&&/^}/{exit} END{exit !(a && b > a && c > b)}' $D"
check "  ... the Dock at a side is the iPad's own screen's: a TV's Dock keeps its bottom and Apple's rules" \
  "fn 'static BOOL DMDockSideControls(id controller) {' $D | grep -q 'if (!gDockSideApplied) return NO;' && fn 'static BOOL DMDockSideControls(id controller) {' $D | grep -q 'return !w || DMDockOnMainScreen(w);'"
check "the pointer's Dock goes again only over the app it came out over (code review 1.8.2, 2): SpringBoard's front app kept at the reveal, asked while it is the pointer's Dock" \
  "fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'if (presented && gDockSidePointer.byPointer) {' \
   && fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'sameApp = \[front isEqualToString:gDockSidePointerApp ?: @\"\"\];' \
   && fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'MSBDDockPointerStep(&gDockSidePointer, gDockSideApplied, p, s, presented, may, stay, h, CACurrentMediaTime(), sameApp)' \
   && fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'gDockSidePointerApp = \[DMDockSideFrontApp() copy\];' \
   && fn 'static NSString \*DMDockSideFrontApp(void) {' $D | grep -q '_accessibilityFrontMostApplication'"
check "a TV's Dock is not the side Dock (code review 1.8.2, 4): an icon is turned, its touches shared and its lifted copy made only inside the side Dock's own view" \
  "grep -q 'static inline BOOL DMDockSideInHost(UIView \*v) { UIView \*host = gDockSideHost; return host && \[v isDescendantOfView:host\]; }' $D \
   && grep -q 'BOOL dock = gDockSideApplied && DMIsDockIcon((UIView \*)self) && DMDockSideInHost((UIView \*)self);' $D \
   && grep -q 'if (!r || !gDockSideApplied || gDockSideStep <= 0 || !DMIsDockIcon((UIView \*)self) || !DMDockSideInHost((UIView \*)self)) return r;' $D \
   && grep -q 'if (!gDockSideApplied || !icon.window || !picture || !DMDockSideInHost(icon)) return nil;' $D"
check "  ... the icons' step is measured in the side Dock's own layout only (a TV's Dock lays out too, with a wider step)" \
  "grep -q 'if (side) DMDockSideMeasureStep(platter);' $D && [ \$(grep -c 'DMDockSideMeasureStep(platter);' $D) = 1 ]"
check "a Position change moves windows only when the Dock moved on the screen as it is (code review 1.8.2, 5): in portrait it stays at the bottom" \
  "fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | grep -q 'BOOL moved = gDMDockPosition >= 0 && MSBDDockSideMoved(gDMDockPosition, position, scrNow.width, scrNow.height);' \
   && fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | grep -qF 'if (moved || ahChanged) DMDockPositionMoved(layouts);' && fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | grep -qF 'BOOL side = !moved && gDMDockPosition >= 0 && MSBDDockSideFor(position, scrNow.width, scrNow.height) != MSBDDockBottom;' && [ \$(grep -c 'DMDockPositionMoved(layouts);' $S) = 3 ] && fn 'static void DMDockRoomAfterStartSMTry(int tries) {' $S | awk '/if \(changed\) \{/{a=NR} /DMDockPositionMoved\(layouts\);/{b=NR} END{exit !(a && b > a)}' \
   && [ \$(fn 'static void DMDockSideThicknessChanged(double was, double now, int side) {' $S | grep -c '^    DMDockPositionMoved(layouts);') = 1 ]"
check "the pointer's reveal sends SpringBoard's present and dismiss as the Downloads panel does: asked first, an empty completion (code review 1.8.2, 8)" \
  "fn 'static void DMDockSideSend(id ctrl, NSString \*name) {' $D | grep -q 'if (\[ctrl respondsToSelector:s\]) ((void (\*)(id, SEL, BOOL, id))objc_msgSend)(ctrl, s, YES, ^{});' \
   && fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'DMDockSideSend(ctrl, @\"presentFloatingDockIfDismissedAnimated:completionHandler:\");' \
   && fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'DMDockSideSend(ctrl, @\"dismissFloatingDockIfPresentedAnimated:completionHandler:\");' \
   && ! grep -q 'objc_msgSend)(ctrl, NSSelectorFromString(@\"\(present\|dismiss\)FloatingDock' $D"
check "the pointer's look never stops for good: a look it can't make now is made again (code review 1.8.2, 10)" \
  "fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'if (!gDockSideHost.window) { DMDockSidePointerArm(0.5); return; }' \
   && fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -q 'if (!\[ctrl respondsToSelector:ps\]) { DMDockSidePointerArm(2.0); return; }' \
   && [ \$(fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -c 'return;') = \$(fn 'static void DMDockSidePointerSeen(CGPoint native) {' $D | grep -c 'DMDockSidePointerArm(.*); return;\|if (!gDockSideApplied) return;') ]"
check "the host's bounds are hooked on its class itself, never on the isa of the moment (a key-value observing subclass goes again; code review 1.8.2, 11)" \
  "grep -q 'MSHookMessageEx(\[host class\], @selector(setBounds:), (IMP)DMDockSideHostSetBounds, (IMP \*)&o_DockSideHostSetBounds);' $D && ! grep -q 'MSHookMessageEx(object_getClass(host)' $D"
check "no hooks at the bottom (code review 1.8.2, 12): Apple's bottom limit for a window is hooked from the first Left or Right on, once the 17 / 18 hooks are in" \
  "fn 'static void DMSMHookBottomInsets17(void) {' $S | grep -q 'if (done || !gSMEdgeReach17In || (gDMDockPosition != MSBDDockLeft && gDMDockPosition != MSBDDockRight && gDMDockAutoHideTaken <= 0 && !DMDockAutoHideAnyTakenOn())) return;' \
   && [ \$(grep -c 'MSHookMessageEx(c, bot, (IMP)DMSMBottomInsets17' $S) = 1 ] && fn 'static void DMSMHookBottomInsets17(void) {' $S | grep -q 'MSHookMessageEx(c, bot, (IMP)DMSMBottomInsets17' \
   && fn 'static void DMSMHookEdgeReach17(void) {' $S | grep -q '^    gSMEdgeReach17In = YES;' && fn 'static void DMSMHookEdgeReach17(void) {' $S | grep -q '^    DMSMHookBottomInsets17();' \
   && fn 'static int DMDockSideNow(CGSize screen) {' $S | grep -q 'DMSMHookBottomInsets17();' && fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | grep -q 'gDMDockPosition = position; DMSMHookBottomInsets17();'"
check "  ... and MacSettings' landscape places are learnt at the bottom as before: its rule for a list laid out beside the Dock only with Left or Right chosen" \
  "grep -q 'if (ILDockPosition() != 0 && \[page isKindOfClass:\[UIScrollView class\]\] && fabs(list.bounds.size.width - page.bounds.size.width) > 0.5) return;' ../macsettings/IconLayout.x \
   && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDDockPositionChosen\")' ../macsettings/IconLayout.x && grep -q 'int MSBDDockPositionChosen(void) { return gDockPosition; }' $D"
check "the Mac-style banners keep out of a side Dock as the Today panel does, with its rule (MSBDBannerX on MSBDDockSideSpanWithin); on the iPad's own screen, as before elsewhere" \
  "fn 'static CGRect DMBannerPresentedFrame(CGRect stock, CGRect cb) {' $S | grep -q 'int side = fabs(cb.size.width - main.width) < 0.5 && fabs(cb.size.height - main.height) < 0.5 ? DMDockSideNow(main) : MSBDDockBottom;' \
   && fn 'static CGRect DMBannerPresentedFrame(CGRect stock, CGRect cb) {' $S | grep -q 'double x = MSBDBannerX(cb.size.width, side, side ? DMUsableArea() : CGRectNull, kDMBannerWidth, DMBannerRTL(), &w);' \
   && fn 'static CGRect DMBannerPresentedFrame(CGRect stock, CGRect cb) {' $S | grep -q 'return CGRectMake(CGRectGetMinX(cb) + x, CGRectGetMinY(cb) + DMBannerTop(), w, stock.size.height);' \
   && grep -q 'static inline MSBDPanelSpan MSBDDockSidePanelSpan(double screenWidth, int side, CGRect area) { return MSBDDockSideSpanWithin(screenWidth, side, area, kMSBDPanelScreenMargin); }' ../common/DockSide.h \
   && grep -q 'MSBDPanelSpan s = MSBDDockSideSpanWithin(screenWidth, side, area, kMSBDBannerScreenMargin);' ../common/DockSide.h"
check "an icon's turn is ours alone (1.8.2 engines check, M1: Atria's icon scale lost): set on top of what the layer has, given back exactly, an icon never turned never written" \
  "fn 'static void DMDockSideStyleIcon(UIView \*icon, int side) {' $D | grep -q 'switch (MSBDDockSideIconTurnStep(turned, still, side)) {' \
   && fn 'static void DMDockSideStyleIcon(UIView \*icon, int side) {' $D | grep -q 'CATransform3D want = CATransform3DConcat(below, DMDockSideIconTurn(side));' \
   && fn 'static void DMDockSideStyleIcon(UIView \*icon, int side) {' $D | grep -q 'if (under && !CATransform3DEqualToTransform(l.sublayerTransform, under.CATransform3DValue)) l.sublayerTransform = under.CATransform3DValue;' \
   && fn 'static void DMDockSideStyleIcon(UIView \*icon, int side) {' $D | grep -q 'default: return;' \
   && [ \$(fn 'static void DMDockSideStyleIcon(UIView \*icon, int side) {' $D | grep -c 'sublayerTransform = ') = 2 ] \
   && ! grep -q 'icon.layer.sublayerTransform = want' $D"
check "  ... the windows' noted layouts are held at a Position change until they are placed, as at a turn (a note in between found a half in no layout of the new desktop)" \
  "fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | awk '/BOOL moved = gDMDockPosition >= 0 && MSBDDockSideMoved/{a=NR} /if \(moved \|\| ahChanged\) DMLayoutNoteHold\(2.4\);/{b=NR} /dispatch_after/{if (!c) c=NR} END{exit !(a && b > a && c > b)}'"
strip() { fn 'static double DMDockSideStripNow(CGSize screen, int side) {' $S; }
check "  ... Stage Manager reads them at the change against the old side, and a Dock already at the other side is no strip of that side: the one last seen there is kept (regression 1.8.2.1 F1)" \
  "fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | awk '/NSDictionary \*layouts = DMSMEngine\(\) \? DMSMLayoutsNow\(\) : nil;/{a=NR} /gDMDockPosition = position;/{b=NR} END{exit !(a && b > a)}' \
   && strip | grep -q 'double m = MSBDDockSideStripOf(r, screen, side);' && strip | grep -q 'if (m > 0) measured = m; else if' \
   && strip | grep -qF 'gDMDockSideStripUsed = gDMDockSideStrip > 0 ? gDMDockSideStrip : MAX(DMSpringBoardDockHeight(), 60.0);' && [ \$(grep -c 'MSBDDockSideStripOf(' $S) = 2 ]"
# ---- 1.8.2.2 ----
arb() { fn '- (id)computedLayoutWithInput:(id)input {' $S; }
check "1.8.2.2 iPad 2 F2 / M1 F4: every side Dock menu's room runs from under the bar to 8 pt over the bottom, Finder's and the Trash's too (UIKit's content bounds start 20 pt lower for our icons), and reaches the Dock's end margin when its arrow needs it" \
  "arb | grep -qF 'bounds.origin.y = barEnd; bounds.size.height = bottomEnd - barEnd;' && arb | grep -qF 'reach = CGRectMake(bounds.origin.x, barEnd, bounds.size.width, CGRectGetMaxY(container.bounds) - kMSBDDockSideEndMargin - barEnd);' \
   && ! arb | grep -qF 'if (CGRectGetMinY(bounds) < barEnd)'"
check "  ... and the Downloads panel's arrow reaches the stack at the Dock's bottom end, its reach the Dock's own end margin" \
  "grep -qF 'CGRect place = MSBDArrowSideMenuFrameReaching(CGRectMake(0, 0, width, height), source, CGRectMake(12.0, 54.0, window.bounds.size.width - 24.0, window.bounds.size.height - 66.0),' ../dock/Downloads.m \
   && grep -qF 'CGRectMake(12.0, 54.0, window.bounds.size.width - 24.0, window.bounds.size.height - kMSBDDockSideEndMargin - 54.0), kMSBDArrowHeight, kMSBDArrowTipGap, kPanelCorner, kMSBDArrowWidth, dockSide == MSBDDockRight, &arrowDir);' ../dock/Downloads.m"
check "1.8.2.2 M1 F1 / A12Z F1: a lifted picture too big for the side icon stands beside the Dock (MenuArrow.h) and the menu beside it; an icon-sized one stays on its icon" \
  "arb | grep -qF 'CGRect lifted = MSBDArrowSidePreviewFrame(previewAt, home, inner, bounds, CGRectGetWidth(container.bounds), kMSBDArrowHeight, kMSBDArrowTipGap, dockSide == MSBDDockRight, &onIcon);' \
   && arb | grep -qF 'if (onIcon) src.origin.y = home.y - src.size.height / 2.0;' && arb | grep -qF 'else src = lifted;' \
   && arb | grep -qF 'pdx = CGRectGetMidX(lifted) - CGRectGetMidX(previewAt); pdy = CGRectGetMidY(lifted) - CGRectGetMidY(previewAt);'"
check "  ... (code review 1.8.2.2, 6) the picture is moved only once the menu is known to fit beside it: with no room for the menu, UIKit's own place for both, never a moved picture over UIKit's menu" \
  "arb | awk '/CGRect f = dockSide \? MSBDArrowSideMenuFrameReaching\(/{a=NR} /if \(dir == MSBDArrowNone\) \{/{b=NR} /if \(movePreview\) \{/{c=NR} /NSSelectorFromString\(@\"setPreviewFrame:\"\), previewAt\);/{d=NR; n++} /NSSelectorFromString\(@\"setPreview:\"\), pv\);/{e=NR; m++} END{exit !(a && b > a && c > b && d > c && e > c && n == 1 && m == 1)}'"
check "1.8.2.2 iPad 2 F1: every menu beside a side Dock reads top-down: its anchor takes the attachment of a menu below its source (UIKit's own placement read first), shape-checked" \
  "arb | grep -qF 'BOOL uikitAbove = CGRectGetMidY(menu) <= CGRectGetMidY(src);' && arb | grep -qF 'if (sideways) DMCtxSideOrderTopDown(out, uikitAbove, say);' \
   && fn 'static void DMCtxSideOrderTopDown(id out, BOOL uikitAbove, BOOL say) {' $S | grep -qF 'if (!DMCtxEncIs(out, g, DM_CTX_ANCHOR_GET) || !DMCtxEncIs(out, s, DM_CTX_ANCHOR_SET)) {' \
   && fn 'static void DMCtxSideOrderTopDown(id out, BOOL uikitAbove, BOOL say) {' $S | grep -qF 'unsigned long long below = MSBDCtxAttachmentBelow(a.attachment, uikitAbove);' \
   && grep -qF '#define DM_CTX_ANCHOR_GET \"{?=QQddq}16@0:8\"' $S"
check "1.8.2.2 M1 F2 / A12Z F7: Fit to Window's questions centre their title over the desktop beside a side Dock (the seam), at the bottom as before" \
  "[ \$(grep -cF 'if (!DMIsExtMenuHost(host) && DMDockSideNow([UIScreen mainScreen].bounds.size)) pillX = MSBDDockSideTitleX(' $S) = 2 ] \
   && grep -qF 'pillX = MSBDDockSideTitleX(noFit.center.x, pillW, host.bounds.size.width, 12.0);' $S && grep -qF 'pillX = MSBDDockSideTitleX(CGRectGetMidX(usable), pillW, host.bounds.size.width, 12.0);' $S \
   && [ \$(grep -cF 'pill.frame = CGRectMake(pillX, MSBDFitQuestionTitleY(usable), pillW, 40.0);' $S) = 2 ]"
strip2() { fn 'static double DMDockSideStripNow(CGSize screen, int side) {' $S; }
thick() { fn 'static void DMDockSideThicknessChanged(double was, double now, int side) {' $S; }
check "1.8.2.2 17.5 F3 / A12Z F5: the strip is the Dock's real thickness (DockSide.h MSBDDockSideStripStep), the last one taken only while the Dock is away; a change it makes by itself is followed by the windows on every engine, their layouts read against the Dock before it" \
  "strip2 | grep -qF 'double use = MSBDDockSideStripStep(st, measured, CACurrentMediaTime(), MAX(DMSpringBoardDockHeight(), 60.0), &event, &was);' \
   && strip2 | grep -qF 'if (event == MSBDStripCandidate) DMLayoutNoteHold(1.0);' && strip2 | grep -qF 'DMDockSideThicknessChanged(was, now, s);' \
   && strip2 | grep -qF 'if (gDMDockSideStripHeld > 0) return gDMDockSideStripHeld;' && ! strip2 | grep -qF 'measured > gDMDockSideStrip + 0.25' \
   && thick | awk '/gDMDockSideStripHeld = was;/{a=NR} /NSDictionary \*layouts = DMSMEngine\(\) \? DMSMLayoutsNow\(\) : nil;/{b=NR} /gDMDockSideStripHeld = -1.0;/{c=NR} /if \(DMSMEngine\(\)\) \{ if \(layouts.count\) DMSMApplyLayouts\(layouts\); \}/{d=NR} /DMDockPositionMoved\(layouts\);/{e=NR} END{exit !(a && b == a + 2 && c == b + 1 && d > c && e > d)}'"
check "1.8.2.2 M1 F5: a Dock icon's running dot goes where its content stands upright, by the turn itself (Dock.x MSBDDockSideIconTurnSide), apps' and Finder's; the turn first in a layout and on arriving in the side Dock, the dot following every change of the turn" \
  "grep -qF 'int dockSide = MSBDDockSideIconTurnSide(iconView);' ../dock/RunningIndicator.m && grep -qF 'int dockSide = MSBDDockSideIconTurnSide(self);' ../dock/FinderIcon.m \
   && ! grep -q 'gDockSideApplied' ../dock/RunningIndicator.m ../dock/FinderIcon.m \
   && fn 'int MSBDDockSideIconTurnSide(UIView *icon) {' $D | grep -qF 'if (!ours || !CATransform3DEqualToTransform(icon.layer.sublayerTransform, ours.CATransform3DValue)) return 0;' \
   && [ \$(fn 'static void DMDockSideStyleIcon(UIView *icon, int side) {' $D | grep -c 'DMDockSideDotFollows(icon);') = 3 ] \
   && awk '/^%hook SBIconView/{h=1} h&&/^- \(void\)layoutSubviews \{/{f=1} f&&/DMDockSideStyleIcon\(\(UIView \*\)self, dock \? gDockSideApplied : 0\);/{a=NR} f&&/DMUpdateRunningIndicator\(\(UIView \*\)self\);/{b=NR} f&&/^}/{exit} END{exit !(a && b > a)}' $D \
   && awk '/^%group DockSideTouches/{g=1} g&&/^- \(void\)didMoveToWindow \{/{w=1} g&&/^- \(void\)didMoveToSuperview \{/{u=1} g&&/^%end/{exit} END{exit !(w && u)}' $D"
check "1.8.2.2 A12Z F8: Zetsu's title-bar watcher keeps out of a side Dock only a window at its place, never one flying into the Dock from its yellow light (it came back 54-66 pt toward the middle)" \
  "awk '/^- \(void\)clamp \{/{f=1} f&&/if \(!w \|\| w.hidden \|\| \[objc_getAssociatedObject\(w, kStageGestureKey\) boolValue\]\) return;/{a=NR} f&&/if \(\[objc_getAssociatedObject\(w, kStageHiddenKey\) boolValue\] \|\| DMStageMinimized\(w\) \|\| !CGAffineTransformIsIdentity\(w.transform\)\) return;/{b=NR} f&&/CGRect kept = DMDockSideKept\(w.frame, MSBDSnapMove\);/{c=NR} f&&/^}/{exit} END{exit !(a && b == a + 4 && c > b)}' $S"
relay() { fn 'static void DMDockChangedRelayout(NSString \*why) {' $S; }
check "1.8.2.2 (code review 3): a Dock setting of ours or a change of its own apps beside a side Dock is followed through its strip as the Dock's own changes are: the windows are placed only when the thickness really changed and settled, once, on every engine; nothing for a setting that leaves it as it was or at each step of a slider" \
  "relay | grep -qF 'BOOL side = !moved && gDMDockPosition >= 0 && MSBDDockSideFor(position, scrNow.width, scrNow.height) != MSBDDockBottom;' \
   && relay | grep -qF 'if (moved || ahChanged) DMLayoutNoteHold(2.4);' && ! relay | grep -qF 'moved || side' \
   && relay | awk '/\(void\)DMUsableArea\(\);/{n++; if (n == 2) a=NR} /if \(side && !ahChanged\) return;/{b=NR} /if \(DMSMEngine\(\)\) \{ if \(layouts.count\) DMSMApplyLayouts\(layouts\); else if \(ahChanged\) DMDockAutoHideSMPass\(\); \}/{c=NR} /if \(moved \|\| ahChanged\) DMDockPositionMoved\(layouts\);/{d=NR} END{exit !(a && b == a + 1 && c == b + 2 && d > c)}' \
   && relay | awk '/if \(gDMDockPosition >= 0 && position != gDMDockPosition\) gDMDockPlaceGen\+\+;/{a=NR} /if \(gDMDockPosition >= 0\) \{ gDMDockPosition = position;/{b=NR} END{exit !(a && b == a + 1)}' \
   && strip2 | grep -qF 'if (seenPlace != gDMDockPlaceGen || seenSide != side) { seenPlace = gDMDockPlaceGen; seenSide = side; gDMDockSideStrip = 0; st->settled = 0; st->cand = -1.0; st->placed = 0; }' \
   && ! strip2 | grep -qF 'seenGen != gDMDockGen' && [ \$(grep -c 'gDMDockPlaceGen' $S) = 3 ]"
check "1.8.2.2 17.5 F1 / A12Z F2: an app's zoom into its side Dock icon goes to the place SpringBoard works out: no match-move to an icon of the turned side Dock (-shouldMatchMoveIconZoomingView: NO there), shape-checked, hooked with a side chosen only; SpringBoard's own icon frame untouched" \
  "fn '- (BOOL)shouldMatchMoveIconZoomingView:(UIView *)iconView {' $D | grep -qF 'if (!r || !gDockSideApplied || ![iconView isKindOfClass:[UIView class]] || !iconView.window || !DMIsDockIcon(iconView) || !DMDockSideInHost(iconView)) return r;' \
   && fn '- (BOOL)shouldMatchMoveIconZoomingView:(UIView *)iconView {' $D | grep -qF 'return NO;' \
   && grep -qF 'if (zm && !strcmp(method_getTypeEncoding(zm) ?: \"\", \"B24@0:8@16\")) %init(DockSideZoom);' $D \
   && fn 'static void DMDockSideChoose(void) {' $D | grep -qF '%init(DockSideZoom);' && ! grep -q '_iconImageFrameForIconView' $D"
notes() { fn 'static void DMNoteWindowLayouts(void) {' $S; }
smnote() { fn 'static void DMSMTurnNote(void) {' $S; }
check "1.8.2.2 (code review 1): a look that takes a new side Dock thickness holds the windows' layout notes in that same look, before the follow is sent; a note pass asks the hold again after its own measurement of the desktop (that measurement may be the look), on Aerial, Zetsu and MilkyWay4 and on Stage Manager's notes" \
  "strip2 | awk '/else if \(event == MSBDStripChanged\) \{/{a=NR} /^            DMLayoutNoteHold\(2.4\);/{b=NR} /dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMDockSideThicknessChanged\(was, now, s\); \}\);/{c=NR} END{exit !(a && b > a && c > b)}' \
   && notes | awk 'NR == 2 && /^    if \(DMLayoutNotesHeld\(\) \|\| gMSWSwitching \|\| DMSwitcherVisible\(\)\) return;/{a=NR} /^    CGRect u = DMUsableArea\(\);/{b=NR} /^    if \(DMLayoutNotesHeld\(\)\) return;/{c=NR} /MSBDTurnLayoutIndex\(f, t, kMSBDTurnLayoutCount, kMSBDTurnLayoutTolerance\)/{d=NR} END{exit !(a && b > a && c > b && d > c)}' \
   && smnote | awk '/^    if \(DMDockSideNow\(\[UIScreen mainScreen\]\.bounds\.size\)\) \{/{g=NR} /^        \(void\)DMUsableArea\(\);/{a=NR} /^        if \(DMLayoutNotesHeld\(\)\) return;/{b=NR} /DMSMOpenWindowFrames\(\);/{c=NR} /DMSMLayoutsFor\(frames\)/{d=NR} END{exit !(g && a == g + 1 && b == a + 1 && c > b && d > c)}' \
   && grep -qF 'static BOOL DMLayoutNotesHeld(void) { return CACurrentMediaTime() < gLayoutNoteHold; }' $S"
z17() { fn 'static BOOL DMDockSideZoomLeavesOut(id switcher, id response) {' $D; }
check "1.8.2.2 (code review 2, second pass 1-3) 15-17: the switcher's match-move response: for an app whose zoom goes into the Dock at a side, on the main screen's switcher, left out, its end too; the decision DockSide.h's (a set of apps, a new start begins anew, never swallowing a later end at the bottom), the response's class asked first, shape-checked; 18 keeps its own hook, the other iPadOS's one missing by design in the diagnostics" \
  "fn '- (void)_performModifierMatchMoveToIconViewResponse:(id)response {' $D | awk '/if \(DMDockSideZoomLeavesOut\(self, response\)\) \{/{a=NR} /^        return;/{b=NR} /^    %orig;/{c=NR} END{exit !(a && b > a && c > b)}' \
   && z17 | awk '/if \(!rc \|\| !\[response isKindOfClass:rc\]\) return NO;/{a=NR} /NSSelectorFromString\(@\"appLayout\"\)/{b=NR} /BOOL recorded = \[gDMZoomLeftOut containsObject:layout\], into = NO;/{c=NR} /w && w.screen == \[UIScreen mainScreen\] \?/{d=NR} /into = \[loc isKindOfClass:\[NSString class\]\] && MSBDZoomLocationIsDock\(/{e=NR} /BOOL leave = MSBDZoomLeaveOut\(active, recorded, into, &op\) != 0;/{f=NR} END{exit !(a && b > a && c > b && d > c && e > d && f > e)}' \
   && z17 | grep -qF 'if (op > 0) { if (!gDMZoomLeftOut) gDMZoomLeftOut = [NSMutableSet set];' && z17 | grep -qF 'else if (op < 0) [gDMZoomLeftOut removeObject:layout];' \
   && ! grep -q 'gDMZoomUnmatchedLayout' $D \
   && grep -qF 'else if (zp && zl && ra && rk && !strcmp(method_getTypeEncoding(zp) ?: \"\", \"v24@0:8@16\") && !strcmp(method_getTypeEncoding(zl) ?: \"\", \"@24@0:8@16\")' $D \
   && grep -qF '&& !strcmp(method_getTypeEncoding(ra) ?: \"\", \"@16@0:8\") && !strcmp(method_getTypeEncoding(rk) ?: \"\", \"B16@0:8\")) {   // (15, 16, 17)' $D && grep -qF '%init(DockSideZoom17);' $D \
   && grep -qF 'return c && ![c instancesRespondToSelector:sel_registerName(sel)] && [c instancesRespondToSelector:sel_registerName(other)];' ../statusbar/SMEngineAPI.h"
check "1.8.2.2 (second pass 4): the windows placed against SpringBoard's figure while the Dock was away (no thickness taken since the Position changed) follow the Dock's first measured thickness: the strip keeps what they stand against, DMDockPositionMoved notes it" \
  "fn 'static void DMDockPositionMoved(NSDictionary<NSString *, NSString *> *layouts) {' $S | grep -qF 'if (DMDockSideNow([UIScreen mainScreen].bounds.size) && gDMDockStrip.settled <= 0) gDMDockStrip.placed = gDMDockSideStripUsed;' \
   && strip2 | grep -qF 'st->settled = 0; st->cand = -1.0; st->placed = 0; }' && [ \$(strip2 | grep -c 'gDMDockSideStripUsed = ') = 2 ] \
   && grep -qF 'double base = st->settled > 0 ? st->settled : (st->placed > 0 && fabs(measured - st->placed) > kMSBDDockStripSame ? st->placed : 0.0);' ../common/DockSide.h"
check "1.8.3 item 7 (regression-1.8.2.2-m1.md F1): a recents icon fading in -- a Handoff tile, the app's own icon back -- is turned again once SpringBoard's fade-in is over (Atria sets the icon's layer value inside it), over the value written, and on the next turn of the main loop; the fade-in hooked on its exact type only, with a side chosen" \
  "awk '/^static void DMDockFadeIn\(id self, SEL _cmd, id icon, BOOL replacing, id completion\) \{/{f=1} f{print} f && /^}/{exit}' $D > \$W/fi && grep -q 'o_DockFadeIn(self, _cmd, icon, replacing, completion);' \$W/fi && grep -q 'DMDockSideStyleAll(root, gDockSideApplied);' \$W/fi \
   && grep -q 'dispatch_async(dispatch_get_main_queue(), ^{ UIView \*r = weakRoot; if (r && gDockSideApplied) DMDockSideStyleAll(r, gDockSideApplied); });' \$W/fi \
   && grep -q 'if (!m || strcmp(method_getTypeEncoding(m) ?: \"\", \"v36@0:8@16B24@?28\"))' $D && grep -q '            DMDockSideHookFadeIn();' $D"
[ $fails = 0 ] && echo "test-dockside: site checks pass" || { echo "test-dockside: site checks FAILED"; exit 1; }
