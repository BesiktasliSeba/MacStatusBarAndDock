// Mac test of where a Stage Manager window may go (statusbar/SMFit.h, the code the engine in StatusBar.x runs), with the iPad 2's real numbers in
// both shapes: the desktops measured on the device (landscape card area {0,48}..697.07, portrait {0,48}..970.07), the two cases seen on 3 Oct
// (Settings back from full screen with portrait's reference in landscape; a window from portrait put back after a turn), behind-the-Dock windows,
// the edge rule after Stage Manager's own constraint, and a random sweep over sizes, centers, references and the four orientations: after the fit
// every window is inside its desktop (title bar under the menu bar), no bigger than it, and fitting again changes nothing. Run by test-smfit.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/SMFit.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }

static const CGFloat kBarH = 24.0;   // (our title bar; the menu bar is 24 pt too)
// The card area as the engine builds it (DMSMCardDesk): the usable window area (DMUsableArea: under the menu bar, ending 2 pt above the Dock) less our
// title bar at its top; behind the Dock: down to the screen's bottom edge.
static CGRect desk(CGSize scr, CGFloat dockTop, BOOL behind) {
    CGFloat top = 24.0 + kBarH, bottom = behind ? scr.height : dockTop - 2.0;
    return CGRectMake(0, top, scr.width, bottom - top);
}
static const CGSize kLand = {1024, 768}, kPort = {768, 1024};
static const CGFloat kLandDockTop = 699.06844892501829, kPortDockTop = 972.06844892501829;   // (iPad 2, 3 Oct log: stage areas end at 697.07 / 970.07)

int main(void) {
    @autoreleasepool {
        CGRect landDesk = desk(kLand, kLandDockTop, NO), portDesk = desk(kPort, kPortDockTop, NO);
        CHECK(near(landDesk.size.height, 649.06844892501829) && near(portDesk.size.height, 922.06844892501829), "desks as on the device: %.2f / %.2f", landDesk.size.height, portDesk.size.height);

        // 1. What the owner saw (22:02:43): the default window worked out as 0.6 x 0.72 OF THE SCREEN, but handed over with the full-screen attributes'
        //    portrait reference -- Stage Manager read 461 x 737 pt in landscape, taller than the 649 pt desktop.
        CGSize bug = DMSMFitSizeInPoints(CGSizeMake(0.6, 0.72), CGRectMake(0, 0, 768, 1024), 0, kLand);
        CHECK(near(bug.width, 460.8) && near(bug.height, 737.28), "the reported size as Stage Manager read it: %.2f x %.2f", bug.width, bug.height);
        CHECK(bug.height > landDesk.size.height, "it is taller than the landscape desktop (the bug)");
        //    Fitted, it is no taller than the desktop and starts at its top: the title bar sits right under the menu bar.
        CGSize s = bug; CGPoint c = CGPointMake(0.5 * 1024, 0.4278235012044509 * 768);
        CHECK(DMSMFitInDesk(&s, &c, landDesk) == 1, "fitting changes it");
        CHECK(near(s.height, landDesk.size.height) && near(s.width, 460.8), "fitted size %.2f x %.2f", s.width, s.height);
        CHECK(near(c.y - s.height / 2.0, 48.0), "fitted top %.2f (want 48: menu bar 24 + title bar 24)", c.y - s.height / 2.0);
        //    The engine's default window is now worked out in points of the screen it joins: 0.6 x 0.72 of landscape, inside the desktop as it is.
        CGSize d = CGSizeMake(0.6 * kLand.width, 0.72 * kLand.height); CGPoint dc = CGPointMake(0.5 * kLand.width, 0.48 * kLand.height);
        CHECK(DMSMFitInDesk(&d, &dc, landDesk) == 0, "the default window in landscape fits as it is: %.1f x %.1f at %.1f, %.1f", d.width, d.height, dc.x, dc.y);
        CHECK(dc.y - d.height / 2.0 >= 48.0 - 0.01, "default window top %.2f below the menu bar and title bar", dc.y - d.height / 2.0);
        CGSize dp = CGSizeMake(0.6 * kPort.width, 0.72 * kPort.height); CGPoint dpc = CGPointMake(0.5 * kPort.width, 0.48 * kPort.height);
        CHECK(DMSMFitInDesk(&dp, &dpc, portDesk) == 0, "the default window in portrait fits as it is: %.1f x %.1f", dp.width, dp.height);

        // 2. The window made in portrait put back after a turn (green, turn, green): {154,70} 461 x 737 in portrait; in landscape the same attributes
        //    were again 737 pt tall at y -40. Fitted: inside the landscape desktop.
        CGSize pz = DMSMFitSizeInPoints(CGSizeMake(0.6, 0.72), CGRectMake(0, 0, 768, 1024), 0, kLand);
        CGPoint pzc = CGPointMake(0.5 * 1024, 0.427734375 * 768);
        DMSMFitInDesk(&pz, &pzc, landDesk);
        CHECK(near(pzc.y - pz.height / 2.0, 48.0) && pzc.y + pz.height / 2.0 <= CGRectGetMaxY(landDesk) + 0.01, "turned window inside: top %.2f bottom %.2f", pzc.y - pz.height / 2.0, pzc.y + pz.height / 2.0);
        //    A wide landscape window put back in portrait: no wider than the screen, its left edge (the traffic lights) on the screen.
        CGSize wz = DMSMFitSizeInPoints(CGSizeMake(0.9, 0.85), CGRectMake(0, 0, 1024, 768), 0, kPort);
        CGPoint wzc = CGPointMake(0.55 * 768, 0.5 * 1024);
        CHECK(near(wz.width, 921.6), "landscape window in portrait points: %.1f x %.1f", wz.width, wz.height);
        DMSMFitInDesk(&wz, &wzc, portDesk);
        CHECK(near(wz.width, 768) && near(wzc.x - wz.width / 2.0, 0), "wide window fitted: width %.1f left %.1f", wz.width, wzc.x - wz.width / 2.0);

        // 3. A window the user put behind the Dock keeps that (its desk reaches the screen's bottom edge), and keeps its title bar on the screen.
        CGRect behind = desk(kLand, kLandDockTop, YES);
        CGSize bs = CGSizeMake(600, 600); CGPoint bc = CGPointMake(500, 150 + 300);   // (top 150, bottom 750: under the Dock line 697)
        CHECK(DMSMFitInDesk(&bs, &bc, behind) == 0, "behind the Dock: kept");
        CGSize bs2 = CGSizeMake(600, 600); CGPoint bc2 = CGPointMake(500, 150 + 300);
        CHECK(DMSMFitInDesk(&bs2, &bc2, landDesk) == 1 && near(bc2.y + bs2.height / 2.0, CGRectGetMaxY(landDesk)), "the same window not behind the Dock: lifted above it");

        // 4. Sizes: a reference of none = the screen; type 3 = the whole screen; any other type is Stage Manager's own (not ours: zero).
        CGSize e = DMSMFitSizeInPoints(CGSizeMake(0.5, 0.5), CGRectZero, 0, kLand);
        CHECK(near(e.width, 512) && near(e.height, 384), "no reference: fractions of the screen %.1f x %.1f", e.width, e.height);
        CGSize f3 = DMSMFitSizeInPoints(CGSizeMake(1, 1), CGRectMake(0, 0, 768, 1024), 3, kLand);
        CHECK(CGSizeEqualToSize(f3, kLand), "type 3 = the screen as it is now");
        CHECK(CGSizeEqualToSize(DMSMFitSizeInPoints(CGSizeMake(0, 0), CGRectZero, 1, kLand), CGSizeZero), "a symbolic size: not ours");
        CHECK(CGSizeEqualToSize(DMSMFitSizeInPoints(CGSizeMake(NAN, 0.5), CGRectZero, 0, kLand), CGSizeZero), "not a number: not ours");
        CGSize nn = CGSizeMake(NAN, 300); CGPoint nc = CGPointMake(10, 10);
        CHECK(DMSMFitInDesk(&nn, &nc, landDesk) == 0 && near(nc.x, 10), "not a number: nothing changed");

        // 5. The edge rule after Stage Manager's own constraint (iPadOS 16): its result for the owner's window (bottom on the area's bottom, top at -40)
        //    becomes top on the area's top; a window inside is not moved; a full-screen window is Apple's; too wide: the left edge wins.
        CGRect area = CGRectMake(0, 48, 1024, 649.06844892501829);
        CGPoint ac = CGPointMake(512.5, 328.5); CGSize as = CGSizeMake(461, 737);
        CHECK(DMSMFitEdgesWin(&ac, as, area, kLand, 1) == 1 && near(ac.y - as.height / 2.0, 48.0), "Apple's bottom-kept window: top now %.2f", ac.y - as.height / 2.0);
        CGPoint ok = CGPointMake(512, 400); CHECK(DMSMFitEdgesWin(&ok, CGSizeMake(500, 500), area, kLand, 1) == 0 && near(ok.y, 400), "a window inside is not moved");
        CGPoint fs = CGPointMake(512, 384); CHECK(DMSMFitEdgesWin(&fs, kLand, area, kLand, 1) == 0 && near(fs.y, 384), "full screen is left as Apple has it");
        CGPoint wide = CGPointMake(450, 400); CHECK(DMSMFitEdgesWin(&wide, CGSizeMake(900, 400), CGRectMake(0, 48, 768, 922), kPort, 0) == 0 && near(wide.x, 450), "too wide but its left edge on the area's: kept");
        CGPoint wide3 = CGPointMake(300, 400); CHECK(DMSMFitEdgesWin(&wide3, CGSizeMake(900, 400), CGRectMake(0, 48, 768, 922), kPort, 0) == 1 && near(wide3.x - 450, 0), "too wide, left edge outside: left edge wins (%.1f)", wide3.x - 450);

        // 6. Sweep: random sizes (up to twice the screen), centers (also off the screen), references (either shape, none) in all four orientations
        //    (portrait and landscape both ways have the same desks), with and without behind-the-Dock. After the fit: inside the desk, no bigger
        //    than it, the title bar row (24 pt above the card) at or below the menu bar, and a second fit changes nothing.
        srand48(20261003);
        int sweep = 0;
        for (int o = 1; o <= 4; o++) {
            BOOL land = o >= 3;
            CGSize scr = land ? kLand : kPort;
            for (int b = 0; b < 2; b++) {
                CGRect dk = desk(scr, land ? kLandDockTop : kPortDockTop, b);
                for (int i = 0; i < 4000; i++) {
                    CGRect ref = drand48() < 0.2 ? CGRectZero : (drand48() < 0.5 ? CGRectMake(0, 0, 768, 1024) : CGRectMake(0, 0, 1024, 768));
                    CGSize n = CGSizeMake(0.05 + drand48() * 1.6, 0.05 + drand48() * 1.6);
                    CGSize sz = DMSMFitSizeInPoints(n, ref, drand48() < 0.05 ? 3 : 0, scr);
                    CGPoint cc = CGPointMake((drand48() * 1.6 - 0.3) * scr.width, (drand48() * 1.6 - 0.3) * scr.height);
                    DMSMFitInDesk(&sz, &cc, dk);
                    CGRect card = CGRectMake(cc.x - sz.width / 2.0, cc.y - sz.height / 2.0, sz.width, sz.height);
                    BOOL inside = CGRectGetMinX(card) >= CGRectGetMinX(dk) - 0.01 && CGRectGetMinY(card) >= CGRectGetMinY(dk) - 0.01
                               && CGRectGetMaxX(card) <= CGRectGetMaxX(dk) + 0.01 && CGRectGetMaxY(card) <= CGRectGetMaxY(dk) + 0.01;
                    BOOL barOK = CGRectGetMinY(card) - kBarH >= 24.0 - 0.01;
                    CGSize s2 = sz; CGPoint c2 = cc;
                    int again = DMSMFitInDesk(&s2, &c2, dk);
                    if (!inside || !barOK || again) {
                        fails++;
                        if (fails < 10) printf("FAIL: sweep o=%d behind=%d card {%.1f,%.1f %.1fx%.1f} desk {%.1f,%.1f %.1fx%.1f} again %d\n", o, b, card.origin.x, card.origin.y, card.size.width, card.size.height, dk.origin.x, dk.origin.y, dk.size.width, dk.size.height, again);
                    } else passes++;
                    sweep++;
                }
            }
        }
        printf("sweep: %d windows fitted in 4 orientations\n", sweep);
        printf("%s: %d passed, %d failed\n", fails ? "FAILED" : "OK", passes, fails);
    }
    return fails ? 1 : 0;
}
