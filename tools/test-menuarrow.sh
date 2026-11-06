#!/bin/bash
# Mac test of the menus' arrow (common/MenuArrow.h, test-menuarrow.c; 1.7.5 item 5): where a menu that opens from a point goes and where its arrow
# sits, then the sites in the code as built: the Dock's menus (StatusBar.x) and the Downloads stack's panel (dock/Downloads.m).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tma" test-menuarrow.c
"$W/tma"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
D=../dock/Downloads.m
check "the Dock's menus: after UIKit's layout arbiter, a menu whose source is in the Dock's window is centred over it with room for the arrow (MenuArrow.h), UIKit's own pop-up anchor worked out for that place" \
  "grep -q 'MSBDArrowMenuFrame(menu, src, bounds, kMSBDArrowHeight, kMSBDArrowTipGap, &dir);' $S && grep -q 'CGRect src = DMCtxDockSource(container, input, previewAt);' $S && grep -q 'return w && \[NSStringFromClass(\[w class\]) hasPrefix:@\"SBFloatingDock\"\];' $S && grep -q 'CGPoint a = ((CGPoint (\*)(id, SEL, CGRect, CGRect))objc_msgSend)(self, anchorFor, f, previewAt);' $S"
check "  ... only with the Mac look (Haptic Touch Menus: Mac), never for a menu without a Dock source; the arrow drawn on the menu view in the menu's own material" \
  "awk '/^- \(id\)computedLayoutWithInput:\(id\)input \{/{f=1} f&&/if \(!DMContextMenuTheme\(\) \|\| DMTestFlag\(\"\/tmp\/msb-noctxarrow\"\)\) return out;/{a=1} f&&a&&/if \(CGRectIsNull\(src\)\) return out;/{print \"ok\"; exit}' $S | grep -q ok && grep -q 'DMCtxPlaceArrow((UIView \*)self);' $S && grep -q 'UIVisualEffectView \*look = DMCtxMenuBackdrop(menu);' $S && grep -q 'fx.maskView = mask;   // (a blur view is masked through its mask view, never its layer' $S"
check "  ... both shapes of UIKit's answer: frames (15.6.1) and places (18.5: bounds, centre, anchor point -- the menu pops up from the arrow's tip), told apart by exact types" \
  "grep -q 'if (DMCtxEncIs(out, NSSelectorFromString(@\"menu\"), DM_CTX_PLACE_GET) && DMCtxEncIs(out, NSSelectorFromString(@\"setMenu:\"), DM_CTX_PLACE_SET)) return DMCtxOutPlaces;' $S && grep -q 'CGPointMake(f.size.width > 0 ? off / f.size.width : 0.5, dir == MSBDArrowDown ? 1.0 : 0.0);' $S && grep -q 'if (!CGAffineTransformIsIdentity(p.transform)) return CGRectNull;' $S"
check "  ... installed only where the arbiter's method has the known type (15.6.1 / 18.5)" \
  "grep -q 'if (mv && enc && !strcmp(enc, \"@24@0:8@16\")) %init(DockMenuArrow);' $S"
check "the Downloads stack's panel: the arrow under it at the stack's middle (MSBDArrowOffset, the panel's corner), its tip 3 pt above the stack, the panel's anchor; it fades, moves and goes with the panel" \
  "grep -q 'MSBDArrowOffset(CGRectMake(x, y, width, height), CGRectGetMidX(iconFrame), kPanelCorner, kMSBDArrowWidth);' $D && grep -q 'gap = kMSBDArrowHeight + kMSBDArrowTipGap' $D && grep -q 'arrow.alpha = 0.0; arrow.transform = away;' $D && grep -q 'arrow.layer.position = CGPointMake(arrow.layer.position.x, arrow.layer.position.y + moved); arrow.alpha = arrowAlpha;' $D && grep -q 'panel.alpha = 0.0; arrow.alpha = 0.0;' $D"
check "  ... beside a side Dock, laid out again (a search, the keyboard): the arrow stays level with the stack and the panel pops up from it (MSBDArrowSidePanelRelayout, code review 1.8.2, 7); at the bottom as before" \
  "grep -q 'self.arrowDir = arrowDir; self.stackMidY = CGRectGetMidY(iconFrame);' $D \
   && grep -q 'if (self.arrowDir == MSBDArrowRight || self.arrowDir == MSBDArrowLeft) { \[self relayoutBesideDockTo:b bottom:bottom animated:animated\]; return; }' $D \
   && grep -q 'CGRect f = MSBDArrowSidePanelRelayout(was, b.size.height, bottom, self.stackMidY, kPanelCorner, kMSBDArrowWidth, &anchorY, &arrowMidY);' $D \
   && grep -q 'al.position = pos; arrow.alpha = arrowAlpha; };' $D"
[ $fails = 0 ] && echo "test-menuarrow: site checks pass" || { echo "test-menuarrow: site checks FAILED"; exit 1; }
