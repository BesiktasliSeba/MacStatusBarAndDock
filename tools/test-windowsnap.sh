#!/bin/bash
# Mac test of window snapping (statusbar/WindowSnap.h, test-windowsnap.c; 1.7.3 item 3): moves and resizes on the A12Z's and the M1's desktops,
# then the sites in the code as built -- every engine ends a move and a resize by hand through it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tws" test-windowsnap.c
"$W/tws"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
check "the glue: an engine window as drawn on the screen (Aerial 5.x: the stage less its margins), the others on this desktop (not minimized, not closing, not hidden), the desktop every layout uses" \
  "grep -q 'return DMActiveEngine() == DMEngineAerial ? DMA5WindowFromStage(f) : f;' $S && grep -q 'if (st.hidden || st.alpha < 0.05 || DMStageMinimized(st) || \[objc_getAssociatedObject(st, kStageClosingKey) boolValue\]) continue;' $S && grep -q 'return DMSnapFrameFor(DMStageBundle(st), window, how, others, n, DMUsableArea());' $S"
check "the glue: a move uses the move distance, a resize the resize distance, the 6 pt gap and the smallest window" \
  "grep -q 'MSBDSnapFrame(window, how, others, n, area, kMSBDSnapGap, move ? kMSBDSnapMoveDistance : kMSBDSnapResizeDistance, MSBDWindowMinSize(), &why);' $S"
check "Aerial 5.x (none of its classes hooked): a drag let go snaps in our target after Aerial's, under the bar first" \
  "awk '/^- \\(void\\)dragTrace:\\(UIPanGestureRecognizer \\*\\)g \\{/{f=1} f&&/CGRect f = stage.frame; f.origin.y = DMTopLimit\\(\\); stage.frame = f;/{a=NR} f&&/if \\(g.state == UIGestureRecognizerStateEnded && stage.superview\\) DMSnapMoveEnded\\(stage\\);/{b=NR; print (a&&b&&a<b) ? \"ok\" : \"no\"; exit}' $S | grep -q ok"
check "Aerial 5.1: a drag on its drag area (a recogniser of its own over the top strip) snaps the same way, under the bar first; hooked on every look, before the guard's early return" \
  "awk '/^- \\(void\\)areaDragEnded:\\(UIPanGestureRecognizer \\*\\)g \\{/{f=1} f&&/CGRect f = stage.frame; f.origin.y = DMTopLimit\\(\\); stage.frame = f;/{a=NR} f&&/DMSnapMoveEnded\\(stage\\);/{b=NR; print (a&&b&&a<b) ? \"ok\" : \"no\"; exit}' $S | grep -q ok && awk '/^static void DMAerial5DragGuard\\(UIView \\*stage\\) \\{/{f=1} f&&/\\[a addTarget:\\[DMA5DragGuard shared\\] action:@selector\\(areaDragEnded:\\)\\];/{a=NR} f&&/if \\(objc_getAssociatedObject\\(stage, kA5DragGuardKey\\)\\) return;/{b=NR; print (a&&b&&a<b) ? \"ok\" : \"no\"; exit}' $S | grep -q ok && grep -q 'areaClass = objc_getClass(\"AerialDragAreaView\");' $S"
check "Aerial 3.0 (its hooks): a drag let go snaps (under the bar first), before the place is remembered" \
  "awk '/^static void DMAerialGestureAfter\\(UIView \\*stage, UIGestureRecognizerState s, BOOL wasPan\\) \\{/{f=1} f&&/if \\(wasPan && s == UIGestureRecognizerStateEnded\\) \\{/{a=NR} f&&/DMSnapMoveEnded\\(stage\\);/{b=NR} f&&/DMRememberStageFrame\\(stage\\);/{c=NR; print (a&&b&&a<b&&b<c) ? \"ok\" : \"no\"; exit}' $S | grep -q ok"
check "Aerial: a corner let go snaps through the offset of Aerial's last step (in front of it), else the frame after it" \
  "grep -q 'if (s == UIGestureRecognizerStateEnded && !DMSnapOff()) {' $S && grep -q 'CGRect snapped = CGRectIsNull(win) ? win : DMSnapEngineWindow(stage, win, (left ? MSBDSnapLeft : MSBDSnapRight) | MSBDSnapBottom);' $S && grep -q 'objc_setAssociatedObject(g, &kA5MinFirstKey, @(first), OBJC_ASSOCIATION_RETAIN_NONATOMIC);' $S"
check "Zetsu: its title bar let go snaps (a move), its grips let go snap their two sides" \
  "grep -q 'if (g.state == UIGestureRecognizerStateEnded) DMSnapMoveEnded(w);   // (1.7.3 item 3' $S && grep -q 'if (g.state == UIGestureRecognizerStateEnded) f = DMSnapEngineWindow(w, f, (self.left ? MSBDSnapLeft : MSBDSnapRight) | MSBDSnapBottom);' $S"
check "MilkyWay4: its title bar let go snaps, its handle's right and bottom sides after the catch-up" \
  "grep -q 'if (g.state == UIGestureRecognizerStateEnded) DMSnapMoveEnded(win);   // (1.7.3 item 3' $S && grep -q 'CGRect s = DMSnapEngineWindow(win, w, MSBDSnapRight | MSBDSnapBottom);' $S"
check "Stage Manager (16-18): our title bar let go asks for the snapped place; 16's last resize step puts the dragged sides where they snap (17 / 18: Apple's own)" \
  "grep -q 'BOOL snapped = DMSMSnapMoveTarget(w, card, t, &at);   // (1.7.3 item 3' $S && grep -q 'CGPoint snapped = DMSMRASnapEnd(edge, start, cur);' ../statusbar/SMResizeAnchor.h && grep -q 'static id DMSMRAStep16(id self, SEL _cmd, BOOL end)' ../statusbar/SMResizeAnchor.h"
check "  ... 16's resize snaps only the iPad's own window found on the working stage by its held sides (a TV's, or one not found, is left as Apple's step has it, as a move leaves a TV's), never a neighbour of its own" \
  "awk '/^static CGPoint DMSMRASnapEnd/,/^}/' ../statusbar/SMResizeAnchor.h | awk '/if \\(MSBDSnapHeldSidesMatch\\(c, start, how\\)\\) \\{/{m=1} m && /!= \\[UIScreen mainScreen\\]\\) offIPad = YES;/{o=1} o && /continue;/{c=1} c && /if \\(!mine \\|\\| offIPad\\) \\{/{g=1} g && /return at;/{r=1} r && /DMSnapFrameFor\\(/{print \"ok\"; exit}' | grep -q ok"
[ $fails = 0 ] && echo "test-windowsnap: site checks pass" || { echo "test-windowsnap: site checks FAILED"; exit 1; }
