#!/bin/bash
# Mac test of which finger touch brings a window forward (common/TapRule.h, test-taprule.c): 1.8.1, GitHub #10 after 1.7.9.2 -- a tap, the same on
# every engine (MacAppBridge's tap for Aerial and Zetsu, the Stage Manager engine's own), never a slide, and never a touch on the menu bar. Then
# the wiring: the bridge asks the rule; with the Stage Manager engine the touch's lift asks it, the menu bar strip is the full-screen window's
# own strip while it is the menu bar, and Stage Manager's own tap, click and window drag that bring a window forward pass over the menu bar.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -std=c11 -O1 -Wall -Werror -o "$W/ttap" test-taprule.c && "$W/ttap" || fails=1
X=../statusbar/StatusBar.x B=../appbridge/AppBridge.x
wire() { if grep -qF -- "$3" "$2"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
check() { if eval "$2"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
wire "the bridge includes the rule" "$B" '#include "../common/TapRule.h"'
wire "the bridge reports a tap by the rule" "$B" 'if (MSBDTapLike(hypot(p.x - [start[0] doubleValue], p.y - [start[1] doubleValue]), CACurrentMediaTime() - [start[2] doubleValue])) MABTouched();'
check "  ... and by no number of its own" "! grep -qE '< 12\.0 && CACurrentMediaTime' $B"
wire "StatusBar.x includes the rule" "$X" '#include "../common/TapRule.h"'
check "Stage Manager: the touch's start, its time and whether it went down on the menu bar are kept" \
  "fn $X 'static void DMSMActivateOnTouch(' | grep -qF 'gSMPendingAt = p; gSMPendingSince = CACurrentMediaTime(); gSMPendingOnBar = DMSMScreenPointOnMenuBar(p, screen);'"
check "Stage Manager: the lift decides by the rule, with whether the window is a full-screen one under windows" \
  "fn $X 'static void DMSMActivateOnTouch(' | grep -qF 'what = MSBDSMTouchOutcome(gSMPendingOnBar, [bundle isEqualToString:DMSMFullScreenUnderWindows()], moved, secs);' \
   && fn $X 'static void DMSMActivateOnTouch(' | grep -qF 'double moved = hypot(p.x - gSMPendingAt.x, p.y - gSMPendingAt.y), secs = CACurrentMediaTime() - gSMPendingSince;'"
check "  ... the rule before the bring-forward; a full-screen window under windows active where it is instead" \
  "fn $X 'static void DMSMActivateOnTouch(' | awk '/what = MSBDSMTouchOutcome\(/ {r=NR} /if \(what == kMSBDSMTouchNothing\) \{/ {n=NR} /if \(what == kMSBDSMTouchActiveInPlace\) \{ NSString \*k = \[bundle copy\]; dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMSMFullScreenActivate\(k\); \}\); continue; \}/ {a=NR} /DMSMBringToFront\(bundle\)/ {b=NR} END {exit !(r && n > r && a > n && b > a)}'"
check "a full-screen window under windows: its stage's full-screen window with a newer one in front (a tie is not), a touch on it where none of them covers it" \
  "fn $X 'static NSString *DMSMFullScreenUnderWindows(' | grep -qF 'return at >= 0 && n > 1 && !MSBDSMNewestAlone(times, n, at) ? fk : nil;' \
   && fn $X 'static BOOL DMSMFullScreenOwnAt(' | grep -qF 'return CGRectContainsPoint(card.bounds, p) && !DMSMCardCoveredAt(card, p, card);'"
check "  ... Stage Manager's tap-to-front (when it would begin, at the touch) and the pointer's click-down pass over it (the click makes it active too)" \
  "fn $X 'static BOOL DMSMTapForwardBegin(' | grep -qF 'if (DMSMFree() && DMSMGestureFullScreenOwn(g)) return NO;' && fn $X 'static BOOL DMSMTapForwardTouch(' | grep -qF '(DMSMTouchOnMenuBar(touch) || DMSMTouchFullScreenOwn(touch))) return NO;' \
   && fn $X 'static BOOL DMSMClickForwardBegin(' | grep -qF 'if (DMSMFree() && DMSMGestureFullScreenOwn(g)) {' && fn $X 'static BOOL DMSMClickForwardBegin(' | grep -qF 'DMSMFullScreenActivate(k);'"
check "  ... active where it is: the active window (DMSMFrontWindowKey) while it is still that and the same window is in front, SpringBoard's own focus request for its scene" \
  "fn $X 'static NSString *DMSMFrontWindowKeyNow(' | grep -qF 'if ([gSMFullActiveOver isEqualToString:newest] && [gSMFullActive isEqualToString:DMSMFullScreenUnderWindows()]) return gSMFullActive;' \
   && fn $X 'static void DMSMFullScreenActivate(' | grep -qF 'BOOL keys = DMKBUserFocusRequest(DMKeyboardFocusController(), scene ?: DMKBSceneForApp(DMSMKeyBundle(key))' \
   && fn $X 'static void DMSMFullScreenActivate(' | grep -qF 'gSMFullActive = [key copy]; gSMFullActiveOver = [DMSMNewestKeyNow() copy];'"
check "  ... any window brought forward (the Dock, a launch, the Mac Switcher, Command-Tab, the Window menu, a tap on a window in front) ends it" \
  "fn $X 'static void DMSMBringToFront(' | grep -qF 'if (gSMFullActive) DMSMFullScreenActiveEnd();'"
check "the menu bar: a full-screen window's strip only while it is the menu bar, on that screen, not in the App Switcher" \
  "fn $X 'static BOOL DMSMScreenPointOnMenuBar(' | grep -qF '!DMSMStripIsMenuBar(fg)) continue;' && fn $X 'static BOOL DMSMScreenPointOnMenuBar(' | grep -qF 'if (gEnvMode == 2 || !screen' \
   && fn $X 'static BOOL DMSMScreenPointOnMenuBar(' | grep -qF '(w.screen ?: [UIScreen mainScreen]) != screen' && fn $X 'static BOOL DMSMScreenPointOnMenuBar(' | grep -qF '[NSStringFromClass([w class]) isEqualToString:@\"SBMainSwitcherWindow\"]'"
check "Stage Manager's tap-to-front passes over the menu bar (when it would begin, and at the touch)" \
  "fn $X 'static BOOL DMSMTapForwardBegin(' | grep -qF 'DMSMGestureOnMenuBar(g)) { DM_FEATURE_MARK(\"sm-menubar-tap-not-forward\"); return NO; }' && fn $X 'static BOOL DMSMTapForwardTouch(' | grep -qF '[touch isKindOfClass:[UITouch class]] && (DMSMTouchOnMenuBar(touch) ||'"
check "the pointer's click-down to front passes over it too" "fn $X 'static BOOL DMSMClickForwardBegin(' | grep -qF '(DMSMGestureOnOurLights(g) || DMSMGestureOnMenuBar(g))) return NO;'"
check "a window drag that starts on the menu bar does not begin" "fn $X 'static BOOL DMSMUnpinBegin(' | grep -qF 'if (DMSMScreenPointOnMenuBar(start, scr)) { DM_FEATURE_MARK(\"sm-menubar-drag-not-window\"); return NO; }'"
exit $fails
