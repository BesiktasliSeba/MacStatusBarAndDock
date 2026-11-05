#!/bin/bash
# Mac test of Aerial 5's windows keeping their turn (16 and later) and their frame (15) around iPadOS's App Switcher (statusbar/AerialTurn.h, test-aerialturn.c; 1.8.1 item 7), then the wiring.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/tat" test-aerialturn.c -lm && "$W/tat" || fails=1
S=../statusbar/StatusBar.x
check() { if eval "$2"; then echo "PASS  wiring: $1"; else echo "FAIL  wiring: $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
check "UIKit's window setters are hooked, never a class of Aerial's (it kills SpringBoard then): the frame on every iPadOS, the transform only on 16 and later" \
  "fn $S 'static void DMA5TurnKeepInstall(' | grep -qF 'Class w = [UIWindow class];' && fn $S 'static void DMA5TurnKeepInstall(' | grep -qF 'gA5WindowTurns = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 16;' && fn $S 'static void DMA5TurnKeepInstall(' | grep -qF 'if (gA5WindowTurns) MSHookMessageEx(w, @selector(setTransform:)' && fn $S 'static void DMA5TurnKeepInstall(' | grep -F 'MSHookMessageEx(w, @selector(setFrame:)' | grep -qv 'if (' && ! fn $S 'static void DMA5TurnKeepInstall(' | grep -q 'objc_getClass'"
check "  ... only for Aerial's two windows, only around the App Switcher" \
  "fn $S 'static BOOL DMA5TurnFadeNow(' | grep -qF 'c != a && c != k' && fn $S 'static BOOL DMA5TurnFadeNow(' | grep -qF 'gEnvMode == 2 || CACurrentMediaTime() - gEnvLeftSwitcherAt < 1.5'"
check "  ... installed with Aerial 5 (the flavour that turns), the time of leaving noted at the switcher's event" \
  "grep -A3 'Aerial 5.0: upside-down fix installed' $S | grep -qF 'DMA5TurnKeepInstall();' && fn $S '- (void)setToEnvironmentMode:(long long)mode {' | grep -qF 'if (gEnvMode == 2 && mode != 2) gEnvLeftSwitcherAt = CACurrentMediaTime();'"
check "the transform: the plain rule keeps the turn, an equal turn is not written again" \
  "fn $S 'static void DMA5WindowTransform(' | grep -qF 'MSBDA5KeepsTurn(YES, o, t.a, t.b, t.c, t.d)' && fn $S 'static void DMA5WindowTransform(' | grep -qF 'if (MSBDA5SameTransform('"
check "the frame: the plain rule, against the native screen, where the window turns" "fn $S 'static void DMA5WindowFrame(' | grep -A2 -F 'if (gA5WindowTurns) {' | grep -qF 'MSBDA5FrameGoes(YES, DMRealInterfaceOrientation(), f.origin.x, f.origin.y, f.size.width, f.size.height, MIN(sc.width, sc.height), MAX(sc.width, sc.height))'"
check "  ... else (15): the plain rule, against the window's transform and bounds now: not the frame Aerial's pass writes under the fade's scale" "fn $S 'static void DMA5WindowFrame(' | grep -A2 -F '} else {' | grep -qF 'CGAffineTransform t = self.transform;' && fn $S 'static void DMA5WindowFrame(' | grep -qF 'if (!MSBDA5FrameGoesNoTurn(YES, t.a, t.b, t.c, t.d, f.origin.x, f.origin.y, f.size.width, f.size.height, bs.width, bs.height)) {'"
[ $fails = 0 ] && echo "test-aerialturn: pass" || { echo "test-aerialturn: FAILED"; exit 1; }
