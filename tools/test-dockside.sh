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
  "grep -q 'return DMSMFree() && DMDockSideNow(\[UIScreen mainScreen\].bounds.size) ? @\[@0.0\] : v;' $S && grep -q 'if (mb && \[DMSMSigOfMethod(mb) isEqualToString:list\]) MSHookMessageEx(c, bot, (IMP)DMSMBottomInsets17, (IMP \*)&o_SMBottomInsets17);' $S"
check "the drop on every engine: moves and resizes, also with snapping off, keep out of the Dock (common/DockSide.h)" \
  "grep -q 'return DMDockSideKept(DMSnapFrameFor(DMStageBundle(st), window, how, others, n, DMUsableArea()), how);' $S && grep -q 'if (!st || (DMSnapOff() && !DMDockSideKeepsOut())) return;' $S && grep -q 'CGRect kept = DMDockSideKept(w.frame, MSBDSnapMove);' $S"
check "the Dock's menus: beside it, the arrow on the facing edge" \
  "grep -q 'CGRect f = dockSide ? MSBDArrowSideMenuFrame(menu, src, bounds, kMSBDArrowHeight, kMSBDArrowTipGap, dockSide == MSBDDockRight, &dir)' $S"
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
  "moved | grep -q 'NSMutableDictionary<NSString \*, NSString \*> \*noted = \[gSMTurnLayout mutableCopy\]' && moved | grep -q 'DMSMFitHiddenStages(frames.count ? DMSMWorkingStage() : nil, noted, nil);'"
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
   && fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | grep -q 'if (moved) DMDockPositionMoved(layouts);' && [ \$(grep -c 'DMDockPositionMoved(layouts);' $S) = 1 ]"
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
  "fn 'static void DMSMHookBottomInsets17(void) {' $S | grep -q 'if (done || !gSMEdgeReach17In || (gDMDockPosition != MSBDDockLeft && gDMDockPosition != MSBDDockRight)) return;' \
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
  "fn 'static void DMDockChangedRelayout(NSString \*why) {' $S | awk '/BOOL moved = gDMDockPosition >= 0 && MSBDDockSideMoved/{a=NR} /if \(moved\) DMLayoutNoteHold\(2.4\);/{b=NR} /dispatch_after/{if (!c) c=NR} END{exit !(a && b > a && c > b)}'"
[ $fails = 0 ] && echo "test-dockside: site checks pass" || { echo "test-dockside: site checks FAILED"; exit 1; }
