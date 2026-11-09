// test-dockhoverhold.c -- Mac test of common/DockHover.h (1.8.4.1, spec item 4): the Dock's hover magnification held through UIKit's cancel while the
// pointer rests over the platter. Run by test-dockhoverhold.sh.
#include <stdio.h>
#include <math.h>
#include <CoreGraphics/CoreGraphics.h>
#include "../common/DockHover.h"
static int fails = 0, checks = 0;
static void Int(const char *what, long got, long want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %ld, want %ld)\n", what, got, want); } }
int main(void) {
    Int("UIKit cancels the hover (state 4) while the magnification shows, no touch yet: held (a Dock layout, a setting, a resting pointer)", MSBDHoverHoldsAfter(4, true, -1.0), 1);
    Int("  ... the last touch long before: held", MSBDHoverHoldsAfter(4, true, kMSBDHoverHoldTouchWindow + 0.5), 1);
    Int("  ... a touch just before it (a finger on the screen, a click): as before, no hold", MSBDHoverHoldsAfter(4, true, 0.05), 0);
    Int("  ... at the end of the touch's window: no hold", MSBDHoverHoldsAfter(4, true, kMSBDHoverHoldTouchWindow), 0);
    Int("  ... at the very moment of the touch: no hold", MSBDHoverHoldsAfter(4, true, 0.0), 0);
    Int("  ... an Ended (3): the pointer left the platter, as before", MSBDHoverHoldsAfter(3, true, -1.0), 0);
    Int("  ... a Failed (5) or anything else: as before", MSBDHoverHoldsAfter(5, true, -1.0), 0);
    Int("  ... not hovering: nothing to hold", MSBDHoverHoldsAfter(4, false, -1.0), 0);
    Int("held, the pointer still over the platter (a Dock layout or setting under a resting pointer): the magnification stays", MSBDHoverHoldStep(false, true, true, true), MSBDHoverHoldKeep);
    Int("  ... the pointer moved, UIKit's hover began again: UIKit's from there", MSBDHoverHoldStep(true, true, true, true), MSBDHoverHoldUIKit);
    Int("  ... the pointer elsewhere: it ends, easing out as before", MSBDHoverHoldStep(false, true, true, false), MSBDHoverHoldEnd);
    Int("  ... its place not known (no service in its shape): it ends as before", MSBDHoverHoldStep(false, false, true, true), MSBDHoverHoldEnd);
    Int("  ... no trackpad or mouse any more: it ends", MSBDHoverHoldStep(false, true, false, true), MSBDHoverHoldEnd);
    Int("looks soon after the cancel", MSBDHoverHoldInterval(0) < 0.2, 1);
    Int("  ... less often while the pointer rests (a second at most)", MSBDHoverHoldInterval(3) < MSBDHoverHoldInterval(4) && MSBDHoverHoldInterval(11) < MSBDHoverHoldInterval(12) && MSBDHoverHoldInterval(1000) == 1.0, 1);
    CGRect platter = CGRectMake(0, 0, 900, 90);
    Int("the pointer in the platter", MSBDHoverInside(CGPointMake(450, 45), platter), 1);
    Int("  ... on its edge (the pointer stops on the screen's last pixel)", MSBDHoverInside(CGPointMake(900.4, 89.8), platter), 1);
    Int("  ... above it (over the magnified icons' tops, outside UIKit's hover region): outside", MSBDHoverInside(CGPointMake(450, -10), platter), 0);
    Int("  ... beside it: outside", MSBDHoverInside(CGPointMake(-5, 45), platter), 0);
    Int("  ... a place that is not a number: never", MSBDHoverInside(CGPointMake(NAN, 45), platter), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
