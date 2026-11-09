#!/bin/bash
# Mac test of windows brought to the front as on a Mac (1.8.4.1 item 6; common/WindowOrder.h, test-windoworder.c), then the sites (statusbar/WindowFront.h,
# StatusBar.x): one reliable raise for Aerial, Zetsu and MilkyWay4 (Aerial's own, checked against the layer's order); an app's Dock icon, Command-Tab
# and the Mac Switcher's pick through it; Window > Bring All to Front as on a Mac on every engine; the Window menu's list of the front app's windows.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/two" test-windoworder.c
"$W/two"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x; F=../statusbar/WindowFront.h; M=../statusbar/MacSwitcher.h
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
has() { grep -qF -- "$1" "$W/fn"; }   # (a line, as written, in the function fn read last)
before() { awk -v a="$1" -v b="$2" 'index($0, a) && !x {x=NR} index($0, b) && !y {y=NR} END{exit !(x && y && x < y)}' "$W/fn"; }
check "WindowFront.h is part of SpringBoard's code (after TitleBarTap.h), its rules from common/WindowOrder.h" \
  "tail -3 $S | grep -qF '#include \"WindowFront.h\"' && grep -qF '#include \"../common/WindowOrder.h\"' $F \
   && grep -qF 'static void DMEngineRaise(UIView *stage, NSString *why);' $S && grep -qF 'static void DMBringAllToFrontNow(void);' $S && grep -qF 'static NSArray *DMWindowListRows(void);' $S"
check "one window to the front on every engine: Zetsu's order (ours), MilkyWay4's view order, Aerial's own raise and then -- where it did not take -- its place among the layer's views, never for a window that does not show" \
  "fn 'static void DMEngineRaise(UIView *stage, NSString *why) {' $F && has 'if (DMIsZetsuWindow(stage)) DMZetsuRaise((UIWindow *)stage);' \
   && has 'else if (DMActiveEngine() == DMEngineMilkyWay) [stage.superview bringSubviewToFront:stage];' \
   && before 'if ([stage respondsToSelector:front]) ((void (*)(id, SEL))objc_msgSend)(stage, front);' 'if (MSBDRaiseNeedsOrder(DMTopStageOn(DMSnapScreenOf(stage)) == stage, shown) && stage.superview) {' \
   && has 'BOOL shown = !stage.hidden && stage.alpha > 0.05 && !DMStageMinimized(stage) && ![objc_getAssociatedObject(stage, kStageClosingKey) boolValue];' \
   && has '[stage.superview bringSubviewToFront:stage];'"
check "an app's Dock icon, Command-Tab and the Mac Switcher's pick bring its window above the others on Aerial through that raise (Zetsu's and MilkyWay4's already ours)" \
  "fn 'static BOOL DMSurfaceWindowForApp(NSString *bundleID) {' $S && has 'DMEngineRaise(stage, [NSString stringWithFormat:@\"%@ opened (its Dock icon, Command-Tab, the Mac Switcher)\", bundleID]);' \
   && ! has '_bringStageToFrontIfNeeded' && has 'DMZetsuSurface(zw);' && has '[window.superview bringSubviewToFront:window];' \
   && grep -qF 'if (bundleID.length && DMStageForBundle(bundleID) && DMSurfaceWindowForApp(bundleID))' $S \
   && [ \$(grep -c 'dispatch_async(dispatch_get_main_queue(), ^{ DMWindowedLaunch(b); });' $S) -ge 2 ] && grep -qF 'if (DMSurfaceWindowForApp(bundleID)) return YES;' $S \
   && grep -qF 'else if (t.kind == DMMSWKindStage && DMActiveEngine() != DMEngineNone && DMSurfaceWindowForApp(t.bundle)) {}' $M"
check "  ... and a tap or a click in a window (MacAppBridge's touched note) the same way" \
  "fn 'static void DMRaiseStageForBundle(NSString *bundle) {' $S && has 'DMEngineRaise(stage, [NSString stringWithFormat:@\"a tap or click in %@'\"'\"'s window\", bundle]);' && ! has '_bringStageToFrontIfNeeded'"
check "Bring All to Front as on a Mac: the front app's windows above the others (Stage Manager: every window of the app in one request, as Stage Manager asks it), the windows over a full-screen app first as before" \
  "fn 'static void DMBringAllToFrontNow(void) {' $F && has 'if (DMSMFullScreenBundle().length && DMSMWindowsBehindFullScreen()) { DMSMWindowsForward(YES); return; }' \
   && has 'if ((gWindowsBehindApps || gFullScreenRaised) && !gWindowsPinnedForward) DMToggleWindowsForward();' && has 'if (front.length) DMBringAppWindowsForward(front, @\"Bring All to Front\");' \
   && fn 'static BOOL DMSMAppWindowsForward(NSString *bundle, NSString *why) {' $F && has 'int m = MSBDOrderAppToFront(apps, n, 1, order);' && has 'BOOL ok = front && DMSMRequestStageOrderAs(stage, times, front, YES);' \
   && has 'if (!moves) return YES;' && has '!DMSMAttrsFullScreen(map[items[i]])'"
check "  ... the Window menu offers it on every engine with windows showing, and Send All to Back only while the windows are in front of a full-screen app" \
  "fn 'static void DMOpenWindowMenu(UIButton *btn) {' $S && [ \$(grep -c 'initWithTitle:@\"Bring All to Front\" enabled:YES handler:DMCloseThen(^{ DMBringAllToFrontNow(); })' \$W/fn) = 2 ] \
   && has 'if ((gWindowsBehindApps || gFullScreenRaised) && gWindowsPinnedForward && DMVisibleWindowCount() > 0)' && has 'initWithTitle:@\"Send All to Back\" enabled:YES handler:DMCloseThen(^{ DMToggleWindowsForward(); })' \
   && has 'if (DMSMFullScreenBundle().length && DMVisibleWindowCount() > 0 && !DMSMWindowsBehindFullScreen())' && has 'initWithTitle:@\"Send All to Back\" enabled:YES handler:DMCloseThen(^{ DMSMWindowsForward(NO); })' \
   && ! has 'gWindowsPinnedForward ? @\"Send All to Back\" : @\"Bring All to Front\"'"
check "the Window menu's list of the front app's windows: a pick brings it to the front (Stage Manager as a tap does; the engines through the raise), the front one ticked" \
  "fn 'static void DMOpenWindowMenu(UIButton *btn) {' $S && before 'NSArray *listed = DMWindowListRows();' 'DMPresentMenu(btn, kWinLabelKey, kWinPillKey, items);' \
   && fn 'static NSArray *DMWindowListRows(void) {' $F && has 'handler:DMCloseThen(^{ DMSMBringToFront(key); })' && has 'r.checked = [key isEqualToString:frontKey];' \
   && has 'if (s) DMEngineRaise(s, @\"the Window menu'\"'\"'s list\");' && has 'if (!front.length || DMNativeActiveApp()) return rows;'"
check "our own windows' Window menu keeps its Bring All to Front and list (Finder)" \
  "grep -qF '[items addObject:R(@\"Bring All to Front\", nil, ^{ for (DMNativeWindow *x in [gNativeWindows copy]) if (!x.hidden) [x.superview bringSubviewToFront:x]; [w activate]; })];' $S"
exit $fails
