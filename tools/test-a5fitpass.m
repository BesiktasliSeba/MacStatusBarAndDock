// Mac test of Aerial 5.x's fit-to-screen pass as StatusBar.x recognises it (statusbar/A5FitPass.h, the code StatusBar.x runs): the frames the pass
// made of Fill and Bottom on the M1 (15.6.1, Aerial 5.1, stage trace of 31 Oct) and the iPad 2's Fill (1.4.1) come out of MSBDA5FitOf; a window put
// there by the pass is recognised, and nothing else is: the frames the pass leaves alone (halves, quarters, 1.7.1's layouts 26 pt from the sides),
// a window the user made smaller or moved, the pass's frame for another place. Run by test-a5fitpass.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/A5FitPass.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static bool same(CGRect a, CGRect b, CGFloat tol) { return fabs(a.origin.x - b.origin.x) < tol && fabs(a.origin.y - b.origin.y) < tol && fabs(a.size.width - b.size.width) < tol && fabs(a.size.height - b.size.height) < tol; }
static const char *S(CGRect r) { static char b[8][96]; static int i = 0; i = (i + 1) % 8; snprintf(b[i], 96, "{%.3f, %.3f, %.3f, %.3f}", r.origin.x, r.origin.y, r.size.width, r.size.height); return b[i]; }

int main(void) {
    @autoreleasepool {
        CGSize m1 = CGSizeMake(1194, 834), m1p = CGSizeMake(834, 1194), ipad2p = CGSizeMake(768, 1024);
        // 1. The pass's frames, as traced on the M1 (stage frames: the window plus its 6 pt side margins)
        struct { CGRect want, seen; CGSize screen; const char *what; } traced[] = {
            { {{-6, 24}, {1206, 738.82499819993973}}, {{20, 63.515734692068634}, {1154, 706.96853061586273}}, m1, "M1 Fill" },
            { {{-6, 395}, {1206, 367.82499819993973}}, {{20, 241.01739306686136}, {1154, 351.96521386627728}}, m1, "M1 Bottom" },
        };
        for (int i = 0; i < 2; i++) {
            CGRect fit = MSBDA5FitOf(traced[i].want, traced[i].screen);
            CHECK(same(fit, traced[i].seen, 0.01), "%s: the pass's frame %s, traced %s", traced[i].what, S(fit), S(traced[i].seen));
            CHECK(MSBDA5FitShrank(traced[i].want, traced[i].seen, traced[i].screen), "%s: the traced frame not recognised", traced[i].what);
        }
        CGRect i2 = MSBDA5FitOf(CGRectMake(-6, 24, 780, 919), ipad2p);   // (the iPad 2's Fill, 1.4.1: 780 x 919 -> 728 x 858, centred)
        CHECK(fabs(i2.size.width - 728) < 0.01 && fabs(i2.size.height - 857.74) < 0.1 && fabs(CGRectGetMidX(i2) - 384) < 0.01 && fabs(CGRectGetMidY(i2) - 512) < 0.01, "iPad 2 Fill: %s", S(i2));
        // 2. Frames the pass leaves alone: never taken for its work
        CGRect alone[] = {
            {{-6, 24}, {606, 738.82499819993973}},   // left half, at the edge (traced: unchanged)
            {{594, 24}, {606, 366}},                  // top right quarter (traced: unchanged)
            {{20, 24}, {1154, 738.82499819993973}},   // 1.7.1's Fill, 26 pt from the sides: exactly the limit
            {{125, 36}, {943, 668}},                  // Center
        };
        for (int i = 0; i < 4; i++) {
            CHECK(!MSBDA5FitTooBig(alone[i], m1), "%s taken for too big", S(alone[i]));
            CHECK(same(MSBDA5FitOf(alone[i], m1), alone[i], 0.001), "%s changed by the model", S(alone[i]));
            CGRect smaller = CGRectInset(alone[i], 30, 30);
            CHECK(!MSBDA5FitShrank(alone[i], smaller, m1), "%s: a smaller window taken for the pass", S(alone[i]));
        }
        // 3. Only the pass's own frame counts for a window it does change
        CGRect fill = traced[0].want, fit = traced[0].seen;
        CHECK(!MSBDA5FitShrank(fill, fill, m1), "Fill where it was taken for the pass");
        CHECK(!MSBDA5FitShrank(fill, CGRectOffset(fit, 40, 0), m1), "the pass's size moved by the user taken for the pass");
        CHECK(!MSBDA5FitShrank(fill, CGRectInset(fit, 10, 10), m1), "a window made smaller than the pass's taken for it");
        CHECK(!MSBDA5FitShrank(fill, traced[1].seen, m1), "Bottom's fitted frame taken for Fill's");
        CHECK(MSBDA5FitShrank(fill, CGRectOffset(fit, 0.3, -0.3), m1), "half a point of rounding not allowed");
        // 4. Portrait: Fill (846 wide on 834) is fitted to 794 wide, centred
        CGRect pf = CGRectMake(-6, 24, 846, 1117.3714261251009), pfit = MSBDA5FitOf(pf, m1p);
        CHECK(fabs(pfit.size.width - 794) < 0.01 && fabs(CGRectGetMidX(pfit) - 417) < 0.01 && fabs(CGRectGetMidY(pfit) - 597) < 0.01, "portrait Fill: %s", S(pfit));
        CHECK(MSBDA5FitShrank(pf, pfit, m1p), "portrait Fill's fitted frame not recognised");
        CHECK(!MSBDA5FitShrank(pf, pfit, m1), "a frame for the other screen shape recognised");
        // 5. Too tall, not too wide: fitted by its height
        CGRect tall = CGRectMake(100, 10, 600, 820), tfit = MSBDA5FitOf(tall, m1);
        CHECK(fabs(tfit.size.height - 794) < 0.01 && fabs(tfit.size.width - 600 * 794.0 / 820.0) < 0.01, "too tall: %s", S(tfit));
        printf("a5fitpass: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
