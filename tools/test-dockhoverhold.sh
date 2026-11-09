#!/bin/bash
# Mac test of the Dock's hover magnification held through UIKit's cancel while the pointer rests over the platter (1.8.4.1, spec item 4;
# common/DockHover.h, test-dockhoverhold.c), then the sites (dock/Dock.x, dock/EditProxy.m): a cancel with the magnification on is held; backboardd's
# place of the pointer read off the main thread in its shape only, in the platter's own space; UIKit's hover beginning again takes over; the Launchpad
# stand-in of Edit Home Screen gets the magnification back after a Dock layout under a resting pointer.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/thh" test-dockhoverhold.c
"$W/thh"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../dock/Dock.x; E=../dock/EditProxy.m
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
fnin() { awk -v head="$1" 'index($0, head) && !f {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }   # (a method in a %hook: indented head)
has() { grep -qF -- "$1" "$W/fn"; }
before() { awk -v a="$1" -v b="$2" 'index($0, a) && !x {x=NR} index($0, b) && !y {y=NR} END{exit !(x && y && x < y)}' "$W/fn"; }
check "the platter's hover: UIKit's end is held first (before the ease-out); UIKit's Began or Changed ends a hold" \
  "grep -qF '#include \"../common/DockHover.h\"' $D && fnin '- (void)dm_hover:(UIHoverGestureRecognizer *)gesture {' $D \
   && before 'if (DMDockHoverHold(self, gesture)) break;' 'gHovering = NO;' && before 'gHoverHeld = NO;   // (UIKit has the pointer again' 'gHovering = YES;'"
check "  ... held only for a cancel with the magnification on, on the iPad's own screen; then the pointer looked for" \
  "fn 'static BOOL DMDockHoverHold(UIView *platter, UIGestureRecognizer *g) {' $D && has 'if (!MSBDHoverHoldsAfter((long)g.state, gHovering && gEnabled, gDMDockTouchAt < 0 ? -1.0 : CACurrentMediaTime() - gDMDockTouchAt) || !platter.window) return NO;' \
   && has 'if (platter.window.screen && platter.window.screen != [UIScreen mainScreen]) return NO;' && before 'gHoverHeld = YES;' 'DMDockHoverLook(gHoverHoldGen);' \
   && has 'gHoverHeld = YES; gHoverHoldLooks = 0; gHoverHoldPlatter = platter; gHoverHoldGen++;'"
check "  ... one chain of looks at a time: each hold its own, a look of an earlier hold's stops at once and after its read (review 1.8.4.1 L3: a cancel, a move, a cancel again ran two chains, two reads a second)" \
  "grep -qF 'static void DMDockHoverLook(unsigned gen);' $D && fn 'static void DMDockHoverLook(unsigned gen) {' $D && has 'if (!gHoverHeld || gen != gHoverHoldGen) return;' \
   && has 'if (!gHoverHeld || gen != gHoverHoldGen || pl != platter || !pl.window) return;' && has 'dispatch_get_main_queue(), ^{ DMDockHoverLook(gen); });' \
   && [ \$(grep -c 'DMDockHoverLook(' $D) = 4 ]"
check "  ... each look: backboardd's place off the main thread, in its shape only, turned to the screen and into the platter; kept, UIKit's, or the ease-out (MSBDHoverHoldStep); less often while the pointer rests; ended with the screen off or the Dock gone" \
  "fn 'static void DMDockHoverLook(unsigned gen) {' $D && has 'dispatch_async(q, ^{' && has 'BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: \"\", \"{CGPoint=dd}16@0:8\");' \
   && has 'p = [pl convertPoint:MSBDDockPointerOnScreen(n, o, native) fromCoordinateSpace:(pl.window.screen ?: [UIScreen mainScreen]).coordinateSpace];' \
   && has 'switch (MSBDHoverHoldStep(DMDockHoverTracking(pl), known, attached, MSBDHoverInside(p, pl.bounds))) {' && has 'double next = MSBDHoverHoldInterval(gHoverHoldLooks++);' \
   && has 'if (DMDockScreenBlank()) { DMDockHoverHoldEnd(platter, @\"the screen is off\"); return; }' && has 'if (!platter.window) { DMDockHoverHoldEnd(platter, @\"the Dock is gone\"); return; }' \
   && has 'gFocusX = p.x;' && has 'if (!gLink) [(SBFloatingDockPlatterView *)pl dm_startLink];'"
check "  ... a hold that ends eases the magnification out as UIKit's end does" \
  "fn 'static void DMDockHoverHoldEnd(UIView *platter, NSString *why) {' $D && has 'gHovering = NO;' && has '[(SBFloatingDockPlatterView *)platter dm_startLink];'"
check "every cancel is held unless a touch came just before it; either order: the touch first, the cancel finds its time; the cancel first, the touch ends the hold (review 1.8.4.1 L4; the iPad 2's cancel of a resting pointer is held)" \
  "fn 'static void DMDockHoverTouchBegan(void) {' $D && before 'gDMDockTouchAt = CACurrentMediaTime();' 'if (gHoverHeld) { gHoverEasedByTouch = YES; DMDockHoverHoldEnd(gHoverHoldPlatter, @\"a touch or a click\"); return; }' && before 'if (gHoverHeld) {' 'gHovering = NO;' && has '[(SBFloatingDockPlatterView *)gLinkPlatter dm_startLink];' \
   && grep -qF 'if (t.phase == UITouchPhaseBegan) { DMDownloadsTouchBegan(t.view); break; }' $D && grep -qF 'if (t.phase == UITouchPhaseBegan && t.type != UITouchTypeIndirect) { DMDockHoverTouchBegan(); break; }' $D && ! grep -q 'gDMDockLayoutChangedAt' $D"
check "Edit Home Screen: the Launchpad stand-in fitted at rest size by a Dock layout gets the magnification back at once under a resting pointer" \
  "fn 'static void EPFollow(UIView *proxy, UIView *library) {' $E && before 'EPFit(proxy, want, t);' 'DMDockHoverReapply();' \
   && fn 'void DMDockHoverReapply(void) {' $D && has 'if (gHovering && !gLink && pl.window) [(SBFloatingDockPlatterView *)pl dm_startLink];'"
exit $fails
