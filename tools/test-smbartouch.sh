#!/bin/bash
# Mac test of what a touch on the menu bar is with the Stage Manager engine (1.8.1, GitHub #10; regression F1, iPadOS 17 and 18): the functions as built, cut out of statusbar/StatusBar.x and run
# with stand-ins (test-smbartouch.m); then the wiring: Stage Manager's window drag leaves such a touch at its start, every gate that asks "on the menu bar" still asks this one question.
# 1.8.4 device pass: with one of our menus or cards open, the window drag leaves every touch (run above), and the pointer's click-down to front and the live resize do not begin.
# MSBD_TEST_STATUSBAR: another copy of the source, to see these checks fail on it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X=${MSBD_TEST_STATUSBAR:-../statusbar/StatusBar.x}
fn() { awk -v s="$2" 'index($0, s) == 1 && !f {f=1; print; if ($0 !~ /\{ *(\/\/.*)?$/) exit; next} f {print} f && /^}/ {exit}' "$1"; }   # one function of a file, from its first line (a one-line one too)
{
  fn "$X" 'static UIView *DMSMMainBarOn(UIScreen *scr, UIView *strip) {'
  fn "$X" 'static BOOL DMSMMainBarShown(UIView *strip) {'
  fn "$X" 'static BOOL DMSMStripIsMenuBar(UIView *strip) {'
  fn "$X" 'static BOOL DMSMScreenPointOnMenuBar(CGPoint sp, UIScreen *screen) {'
  fn "$X" 'static BOOL DMSMTouchOnMenuBar(UITouch *t) {'
  fn "$X" 'static BOOL DMSMIsWindowDrag(id manager, UIGestureRecognizer *g) {'
  fn "$X" 'static BOOL DMSMWindowDragLeavesTouch(id manager, UIGestureRecognizer *g, UITouch *t) {'
  fn "$X" 'static BOOL DMSMUnpinBegin(id self, SEL _cmd, id g) {'
} > "$W/smbartouch-gen.h"
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -framework Foundation -framework CoreGraphics -o "$W/t" test-smbartouch.m
fails=0
"$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the hook of the manager's touch question asks the window drag's gate, before Apple's answer" \
  "awk '/^%group DMNativeSysGestures/{f=1} f&&/DMSMWindowDragLeavesTouch\(self, g, touch\)\) return NO;/{a=NR} f&&/return %orig;/{b=NR; exit} END{exit !(a && b > a)}' $X"
check "the gate for the touch asks the two questions the tap and click ask" \
  "fn $X 'static BOOL DMSMWindowDragLeavesTouch(id manager, UIGestureRecognizer *g, UITouch *t) {' | grep -qF 'BOOL onBar = DMSMTouchOnMenuBar(t), own = !onBar && DMSMTouchFullScreenOwn(t);'"
check "our title bar's touch and that gate name the same recogniser" \
  "fn $X 'static BOOL DMSMIsWindowDrag(id manager, UIGestureRecognizer *g) {' | grep -qF '\"_unpinSplitViewApplicationGestureRecognizer\"' && fn $X 'static BOOL DMSMTitleBarDragTouch(id manager, UIGestureRecognizer *g, UITouch *t) {' | grep -qF 'if (!DMSMIsWindowDrag(manager, g)) return NO;'"
check "one reader of the screen's own bar: the strip's question and the touch's" \
  "fn $X 'static BOOL DMSMMainBarShown(UIView *strip) {' | grep -qF 'return DMSMMainBarOn(strip.window.screen, strip) != nil;' && fn $X 'static BOOL DMSMScreenPointOnMenuBar(CGPoint sp, UIScreen *screen) {' | grep -qF 'UIView *own = DMSMMainBarOn(screen, nil);'"
check "one of our menus open: the pointer's click-down to front does not begin (before a full-screen window is made active where it is), as the finger's tap" \
  "fn $X 'static BOOL DMSMClickForwardBegin(id self, SEL _cmd, id g) {' | awk '/if \(DMSMFree\(\) && DMSMOurMenuOpenOn\(DMSMGestureScreen\(g\)\)\) \{ DM_FEATURE_MARK\(\"sm-menu-click-not-forward\"\); return NO; \}/{a=NR} /DMSMFullScreenActivate\(k\)/{b=NR} END{exit !(a && b > a)}' \
   && fn $X 'static BOOL DMSMTapForwardBegin(id self, SEL _cmd, id g) {' | grep -qF 'if (DMSMFree() && DMSMOurMenuOpenOn(DMSMGestureScreen(g))) { DM_FEATURE_MARK(\"sm-menu-tap-not-forward\"); return NO; }'"
check "  ... nor the live resize (the Mac Switcher's view first, as before)" \
  "fn $X 'static BOOL DMSMLiveResizeBegin(id self, SEL _cmd, id g) {' | awk '/if \(DMSMOverWindows\(\)\) return NO;/{a=NR} /if \(DMSMFree\(\) && DMSMOurMenuOpenOn\(DMSMGestureScreen\(g\)\)\) \{ DM_FEATURE_MARK\(\"sm-menu-no-live-resize\"\); return NO; \}/{b=NR} /return o_SMLiveResizeBegin\(self, _cmd, g\);/{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... and \"our menu is open\" is one question, asked for the gesture's or touch's own screen (P3-L3): the iPad's menu window with an overlay, or that display's menu window" \
  "fn $X 'static BOOL DMSMOurMenuOpenOn(UIScreen *screen) {' | grep -qF 'if (gMenuWindow && !gMenuWindow.hidden && gOverlay && (gMenuWindow.screen ?: main) == screen) return YES;' \
   && fn $X 'static BOOL DMSMOurMenuOpenOn(UIScreen *screen) {' | grep -qF 'for (UIWindow *w in gExtMenuWindows) if (!w.hidden && (w.screen ?: main) == screen) return YES;' \
   && ! grep -q 'DMSMOurMenuOpen()' $X && [ \"\$(grep -c 'DMSMOurMenuOpenOn(DMSMGestureScreen(g))' $X)\" = 3 ] && grep -qF 'DMSMOurMenuOpenOn(DMSMTouchScreen(t))' $X"
check "no em dashes in the new files" "! grep -n \$'\\xe2\\x80\\x94' test-smbartouch.m test-smbartouch.sh"
exit $fails
