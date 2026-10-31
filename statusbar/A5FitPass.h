// A5FitPass.h -- Aerial 5.x's fit-to-screen pass, as it shows from outside (plain C on CoreGraphics, so the Mac test tools/test-a5fitpass.m runs
// this very code). Aerial (-_adjustStageToFitScreenIfNeeded, the method Aerial 3.0's hook answers with DMEnforceStageFrame) keeps no window bigger
// than the screen inset by 20 pt: an oversized one is scaled down to fit and centred on the screen. Its classes cannot be hooked on 5.x (its anti-hook
// protection), so StatusBar.x recognises the pass by its result and puts the window back before the commit that would draw it (DMA5AnswerFitPass).
//  - Measured (M1 15.6.1, Aerial 5.1, stage trace of 31 Oct: the frame set from Aerial.dylib's fit method, run from a block it dispatches when a
//    window opens or the Mac Switcher opens): Fill {{-6, 24}, {1206, 738.825}} -> {{20, 63.516}, {1154, 706.969}}, Bottom {{-6, 395}, {1206,
//    367.825}} -> {{20, 241.017}, {1154, 351.965}} on 1194 x 834; the iPad 2's Fill 780 x 919 -> 728 x 858 (1.4.1). Halves and quarters (606 wide)
//    are left where they are, also at x -6.
//  - The frames are the stage's (the window and its invisible 6 pt side margins): until 1.7.2 every layout stopped 26 pt from the sides, which is
//    exactly that limit, so the pass never changed one; since 1.7.2 Fill, Top and Bottom reach the edges and are wider.
#ifndef MSBD_A5_FIT_PASS_H
#define MSBD_A5_FIT_PASS_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <math.h>

#define kMSBDA5FitInset 20.0   // Aerial 5.x's margin to every screen edge for a window it fits

// The largest stage Aerial's pass leaves alone on this screen.
static inline CGSize MSBDA5FitLimit(CGSize screen) { return CGSizeMake(screen.width - 2.0 * kMSBDA5FitInset, screen.height - 2.0 * kMSBDA5FitInset); }

// Does the pass change this stage frame at all? (Only its size decides: a frame within the limit stays where it is, at the edges too.)
static inline bool MSBDA5FitTooBig(CGRect f, CGSize screen) {
    CGSize lim = MSBDA5FitLimit(screen);
    return f.size.width > lim.width + 0.5 || f.size.height > lim.height + 0.5;
}

// What the pass makes of a frame: unchanged when it is within the limit, else scaled down evenly to fit and centred on the screen.
static inline CGRect MSBDA5FitOf(CGRect f, CGSize screen) {
    if (!MSBDA5FitTooBig(f, screen) || f.size.width <= 0.0 || f.size.height <= 0.0) return f;
    CGSize lim = MSBDA5FitLimit(screen);
    CGFloat k = fmin(lim.width / f.size.width, lim.height / f.size.height);
    CGFloat w = f.size.width * k, h = f.size.height * k;
    return CGRectMake((screen.width - w) / 2.0, (screen.height - h) / 2.0, w, h);
}

// Is `cur` what the pass made of `want`? Only for a want it changes, and only that result (half a point either way): a window the user made smaller
// or moved, or one Aerial placed some other way, is not taken for it.
static inline bool MSBDA5FitShrank(CGRect want, CGRect cur, CGSize screen) {
    if (!MSBDA5FitTooBig(want, screen)) return false;
    CGRect fit = MSBDA5FitOf(want, screen);
    return fabs(cur.origin.x - fit.origin.x) < 0.5 && fabs(cur.origin.y - fit.origin.y) < 0.5
        && fabs(cur.size.width - fit.size.width) < 0.5 && fabs(cur.size.height - fit.size.height) < 0.5;
}
#endif
