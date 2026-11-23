// test-recentstrip.m: the recent windows strip's rules (common/RecentStripRule.h, 1.8.8.2 F29), run on the Mac. RSTRIP_RULE: the header to test
// (a made-to-fail copy from test-recentstrip.sh). Exit status: the number of failed checks (0: all pass).
#import <Foundation/Foundation.h>
#ifndef RSTRIP_RULE
#define RSTRIP_RULE "../common/RecentStripRule.h"
#endif
#include RSTRIP_RULE

static int gFails = 0, gChecks = 0, gQuiet = 0;
static void check(BOOL ok, NSString *what) {
    gChecks++;
    if (!ok) gFails++;
    if (!gQuiet || !ok) printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
}
static NSString *J(NSArray *a) { return [a componentsJoinedByString:@" "]; }
static NSArray *W(NSString *s) { return s.length ? [s componentsSeparatedByString:@" "] : @[]; }
// one step: the order before, the front before and now, the pick, the windows (front to back): the order after
static NSString *step(NSString *order, NSString *was, NSString *now, NSString *picked, NSString *present) {
    NSMutableArray *o = [W(order) mutableCopy];
    MSBDRStripOrderStep(o, was, now, picked, W(present));
    return J(o);
}
// an oracle of the show rule, written apart from the header's
static int oracle(MSBDRStripState s) {
    BOOL can = s.on && s.items > 0 && s.calm && s.windowsFront;
    if (!can) return 0;
    if (s.revealed) return 2;
    return s.windowShown && !s.covered ? 1 : 0;
}
static BOOL near(double a, double b) { return fabs(a - b) < 0.51; }

int main(int argc, char **argv) {
    @autoreleasepool {
        gQuiet = argc > 1 && !strcmp(argv[1], "-q");
        // ---- the order ----
        check([step(@"", @"", @"A", nil, @"A B C") isEqualToString:@"B C"], @"first look: the windows behind the front one, from the front back (A in front: B C)");
        check([step(@"B C", @"A", @"B", nil, @"B A C") isEqualToString:@"A C"], @"a tap in B (no pick): B leaves the strip, A that was in front goes to the top (A C)");
        check([step(@"A C", @"B", @"C", @"C", @"C B A") isEqualToString:@"A B"], @"a pick of C in slot 2: C comes forward, B that was in front takes C's slot (A B)");
        check([step(@"A B", @"C", @"A", @"A", @"A C B") isEqualToString:@"C B"], @"a pick of A in slot 1: C that was in front takes slot 1 (C B)");
        check([step(@"A B C D", @"E", @"C", @"C", @"C E A B D") isEqualToString:@"A B E D"], @"a pick in slot 3 of 4: the front one takes slot 3, the others keep theirs (A B E D)");
        check([step(@"A B C D", @"E", @"C", nil, @"C E A B D") isEqualToString:@"E A B D"], @"the same window come forward another way (the Dock): the one in front goes to the top (E A B D)");
        check([step(@"A B C D", @"E", @"C", @"D", @"C E A B D") isEqualToString:@"E A B D"], @"a pick of another window than the one that came: no swap, the top");
        check([step(@"C B", @"A", @"", nil, @"C B A") isEqualToString:@"A C B"], @"the front one minimized (none in front now): it goes to the top, minimized windows live there (A C B)");
        check([step(@"A C B", @"", @"C", @"C", @"C A B") isEqualToString:@"A B"], @"a pick with none in front (every window minimized): it comes, nothing takes its slot (A B)");
        check([step(@"A C B", @"D", @"D", nil, @"D A B") isEqualToString:@"A B"], @"a window closed (C): it leaves the strip, the others keep their order");
        check([step(@"A B", @"D", @"A", nil, @"A B") isEqualToString:@"B"], @"the window in front closed (D gone) as A comes forward: nothing takes a slot (B)");
        check([step(@"A B", @"D", @"D", nil, @"D A B N") isEqualToString:@"A B N"], @"a window new to the list that is not in front (from another desktop, after a respring) joins the end");
        check([step(@"A B", @"D", @"N", nil, @"N D A B") isEqualToString:@"D A B"], @"a new window opened in front: the one that was in front goes to the top, the new one is never in the strip");
        check([step(@"A B", @"D", @"D", nil, @"D A B") isEqualToString:@"A B"], @"the same front: nothing moves");
        check([step(@"", @"", @"", nil, @"") isEqualToString:@""], @"no window: an empty strip");
        {   // the one in front is never in the order, whatever the step (a sweep of picks and fronts over five windows)
            NSArray *apps = @[@"A", @"B", @"C", @"D", @"E"];
            NSMutableArray *o = [NSMutableArray array]; NSString *was = @"";
            BOOL ok = YES; unsigned seed = 7;
            for (int i = 0; i < 4000; i++) {
                seed = seed * 1103515245u + 12345u;
                NSMutableArray *present = [NSMutableArray array];
                for (NSString *a in apps) if (((seed >> (8 + [apps indexOfObject:a])) & 7) != 0) [present addObject:a];
                NSString *now = present.count && ((seed >> 20) & 3) ? present[(seed >> 22) % present.count] : @"";
                NSString *picked = ((seed >> 25) & 1) ? now : (((seed >> 26) & 1) ? @"C" : nil);
                if (now.length) { [present removeObject:now]; [present insertObject:now atIndex:0]; }
                NSArray *before = [o copy];
                MSBDRStripOrderStep(o, was, now, picked, present);
                NSSet *here = [NSSet setWithArray:present];
                if ([o containsObject:now] || [NSSet setWithArray:o].count != o.count) ok = NO;
                for (NSString *b in o) if (![here containsObject:b]) ok = NO;
                for (NSString *b in present) if (![b isEqualToString:now] && ![o containsObject:b]) ok = NO;
                if (was.length && ![now isEqualToString:was] && [here containsObject:was]) {
                    // (the oracle: the order before without the apps gone and with the new ones at its end, where the new front stood in it)
                    NSMutableArray *mid = [NSMutableArray array];
                    for (NSString *b in before) if ([here containsObject:b]) [mid addObject:b];
                    for (NSString *b in present) if (![mid containsObject:b] && ![b isEqualToString:now]) [mid addObject:b];
                    [mid removeObject:was];
                    NSUInteger slot = now.length ? [mid indexOfObject:now] : NSNotFound;
                    BOOL swap = now.length && [picked isEqualToString:now] && slot != NSNotFound;
                    if ([o indexOfObject:was] != (swap ? slot : 0)) ok = NO;
                }
                was = now;
            }
            check(ok, @"a sweep of 4000 steps: the front one never in the strip, no app twice, every other window in it and only those, the one that left the front at its pick's slot or the top");
        }
        check([J(MSBDRStripItems(W(@"A B C D E F G H"), 3)) isEqualToString:@"A B C"] && [J(MSBDRStripItems(W(@"A B C D E F G H"), 20)) isEqualToString:@"A B C D E F"]
              && MSBDRStripItems(W(@"A B"), 0).count == 0 && [J(MSBDRStripItems(W(@"A B"), 6)) isEqualToString:@"A B"], @"the cards: the first of the order, as many as fit, at most 6");

        // ---- when it shows ----
        {
            BOOL ok = YES; int n = 0;
            for (int m = 0; m < 128; m++) {
                MSBDRStripState s = { m & 1, (m >> 1) & 1 ? 3 : 0, (m >> 2) & 1, (m >> 3) & 1, (m >> 4) & 1, (m >> 5) & 1, (m >> 6) & 1 };
                if ((int)MSBDRStripShowFor(s) != oracle(s)) ok = NO;
                MSBDRStripState r = s; r.revealed = 0;
                BOOL may = MSBDRStripMayReveal(s), want = s.on && s.items > 0 && s.calm && s.windowsFront && (!s.windowShown || s.covered);
                if (may != want) ok = NO;
                n++;
            }
            check(ok, [NSString stringWithFormat:@"the show rule over all %d states, against an oracle: on the desktop with a window on screen and nothing over the cards; out over the windows only when brought; never without the switch, cards, calm or the windows in front", n]);
        }
        MSBDRStripState base = { 1, 2, 1, 1, 1, 0, 0 };
        check(MSBDRStripShowFor(base) == MSBDRStripOnDesktop, @"a window on screen, the desktop free beside it: the strip shows on the desktop");
        { MSBDRStripState s = base; s.covered = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && MSBDRStripMayReveal(s), @"a window over the cards: it steps aside, and the pointer may bring it"); }
        { MSBDRStripState s = base; s.covered = 1; s.revealed = 1; check(MSBDRStripShowFor(s) == MSBDRStripOverWindows, @"... brought by the pointer or the Window menu: out over the windows"); }
        { MSBDRStripState s = base; s.windowShown = 0; check(MSBDRStripShowFor(s) == MSBDRStripHidden && MSBDRStripMayReveal(s), @"every window minimized (the Home Screen in use): it steps aside, its Home Screen icons stay free; the pointer may bring it"); }
        { MSBDRStripState s = base; s.windowsFront = 0; s.revealed = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"the windows behind a full-screen app: no strip, not even brought"); }
        { MSBDRStripState s = base; s.calm = 0; s.revealed = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"the App Switcher, a lock, Spotlight, a keyboard...: no strip"); }
        { MSBDRStripState s = base; s.items = 0; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"nothing in it (one window): no strip"); }
        { MSBDRStripState s = base; s.on = 0; s.revealed = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"switched off: never"); }
        check(!MSBDRStripMayReveal(base), @"already on the desktop: nothing to bring");

        // ---- the place ----
        struct { const char *name; double w, h; } pads[] = { { "iPad Air 2 / 9.7\"", 768, 1024 }, { "iPad mini 6", 744, 1133 }, { "10.2\"", 810, 1080 }, { "10.9\" / Air 4", 820, 1180 },
                                                              { "11\"", 834, 1194 }, { "12.9\"", 1024, 1366 }, { "a small screen", 600, 800 } };
        double wantW[] = { 88, 86, 93, 94, 96, 118, 80 };
        BOOL widthsOK = YES;
        for (int i = 0; i < 7; i++) if (!near(MSBDRStripCardW(pads[i].w, pads[i].h), wantW[i]) || !near(MSBDRStripCardW(pads[i].h, pads[i].w), wantW[i])) widthsOK = NO;
        check(widthsOK, @"a card's width: 11.5 % of the screen's short side, 80 to 118 pt (Air 2 88, mini 86, 10.2\" 93, 10.9\" 94, 11\" 96, 12.9\" 118), the same in both turns");
        check(near(MSBDRStripCardH(768, 1024), 69) && near(MSBDRStripCardH(1366, 1024), 92), @"its height 78 % of that (Air 2 69 pt, 12.9\" 92 pt)");
        BOOL placesOK = YES, centredOK = YES, fitOK = YES; int layouts = 0;
        for (int i = 0; i < 7; i++) for (int turn = 0; turn < 2; turn++) for (int dock = 0; dock < 3; dock++) for (int n = 0; n <= 8; n++) {
            double sw = turn ? pads[i].h : pads[i].w, sh = turn ? pads[i].w : pads[i].h;
            MSBDRRect usable = dock == 1 ? (MSBDRRect){ 90, 24, sw - 90, sh - 24 } : dock == 2 ? (MSBDRRect){ 0, 24, sw - 90, sh - 24 } : (MSBDRRect){ 0, 24, sw, sh - 24 - 86 };
            BOOL right = MSBDRStripOnRight(dock == 1);
            double aspect[8]; for (int k = 0; k < 8; k++) aspect[k] = k % 3 == 0 ? 1.6 : (k % 3 == 1 ? 0.7 : 0.0);
            MSBDRRect band, cards[8];
            int fit = MSBDRStripFit(sw, sh, usable), got = MSBDRStripLayout(sw, sh, usable, right, n, aspect, &band, cards);
            layouts++;
            if (got != MIN(n, fit) || fit > kMSBDRStripMax || fit < 4) fitOK = NO;
            if (band.x < usable.x - 0.01 || MSBDRMaxX(band) > MSBDRMaxX(usable) + 0.01 || (right ? !near(MSBDRMaxX(band), MSBDRMaxX(usable)) : !near(band.x, usable.x))) placesOK = NO;
            double top = 1e9, bottom = -1e9;
            for (int k = 0; k < got; k++) {
                MSBDRRect c = cards[k];
                if (c.x < band.x + kMSBDRStripEdgeGap - 0.01 || MSBDRMaxX(c) > MSBDRMaxX(band) - kMSBDRStripEdgeGap + 0.01) placesOK = NO;
                if (c.y < usable.y + kMSBDRStripEnds - 0.6 || MSBDRMaxY(c) > MSBDRMaxY(usable) - kMSBDRStripEnds + 0.6) placesOK = NO;
                if (c.w > MSBDRStripCardW(sw, sh) + 0.01 || c.h > MSBDRStripCardH(sw, sh) + 0.01 || c.w < 10 || c.h < 10) placesOK = NO;
                if (k && c.y < MSBDRMaxY(cards[k - 1]) + kMSBDRStripCardGap - 0.6) placesOK = NO;
                double box = MSBDRStripCardH(sw, sh);
                top = MIN(top, c.y - floor((box - c.h) / 2.0)); bottom = MAX(bottom, c.y - floor((box - c.h) / 2.0) + box);
            }
            if (got && fabs((top + bottom) / 2.0 - (usable.y + usable.h / 2.0)) > 1.01) centredOK = NO;
        }
        check(fitOK, [NSString stringWithFormat:@"how many fit: as many as the desktop's height takes, at least 4 and at most 6, on every iPad size, both turns, every Dock side (%d layouts)", layouts]);
        check(placesOK, @"every card inside the band, 14 pt from its edges, inside the desktop's height with 24 pt to spare, 18 pt apart, no bigger than its box; the band at its side's edge of the desktop");
        check(centredOK, @"the cards' run centred in the desktop's height");
        {
            MSBDRRect band, cards[2]; double aspect[2] = { 2.0, 0.5 };
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 2, aspect, &band, cards);
            check(near(cards[0].w, 88) && near(cards[0].h, 44) && near(cards[1].h, 69) && near(cards[1].w, 35) && near(band.w, 116) && near(band.x, 0),
                  @"a card keeps its window's shape in its box (a wide window 88 x 44, a tall one 35 x 69 on an Air 2), the band 116 pt at the left");
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 1, (double[]){ 0.0 }, &band, cards);
            check(near(cards[0].w, 88) && near(cards[0].h, 66), @"a window's shape not known: a 4:3 card");
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 1, (double[]){ 50.0 }, &band, cards);
            check(near(cards[0].w, 88) && near(cards[0].h, 29), @"an extreme shape is held to 3:1 (and 1:3)");
        }
        check(MSBDRStripOnRight(YES) && !MSBDRStripOnRight(NO), @"the left edge, the right one with the Dock at Left (as macOS)");
        {
            MSBDRRect band, cards[3]; double aspect[3] = { 1.5, 1.5, 1.5 };
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 90, 24, 934, 744 }, YES, 3, aspect, &band, cards);
            check(near(band.x, 908) && near(MSBDRMaxX(band), 1024) && near(cards[0].x, 922), @"... at the right edge: the band 908 to 1024, the cards 14 pt in");
        }

        // ---- a window over the cards ----
        {
            MSBDRRect band, cards[3]; double aspect[3] = { 1.5, 1.5, 1.5 };
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 3, aspect, &band, cards);
            MSBDRRect span = MSBDRStripCardsSpan(band, cards, 3);
            check(near(span.y, cards[0].y - 8) && near(MSBDRMaxY(span), MSBDRMaxY(cards[2]) + 10) && near(span.w, band.w), @"the cards' part: the band across the cards, with the corner icons below the last");
            check(!MSBDRStripCovers(span, (MSBDRRect){ 116, 60, 700, 500 }), @"a window beside the band: no cover");
            check(!MSBDRStripCovers(span, (MSBDRRect){ 112, 60, 700, 500 }), @"... overlapping it by 4 pt: no cover (the slack)");
            check(MSBDRStripCovers(span, (MSBDRRect){ 111, 60, 700, 500 }), @"... by 5 pt: it covers");
            check(!MSBDRStripCovers(span, (MSBDRRect){ 0, 24, 600, span.y - 24 }), @"a window over the band above the cards: no cover");
            check(MSBDRStripCovers(span, (MSBDRRect){ 0, 24, 1024, 658 }), @"a window that fills the desktop: it covers");
            check(!MSBDRStripCovers((MSBDRRect){ 0, 0, 116, 0 }, (MSBDRRect){ 0, 24, 1024, 658 }), @"no cards: nothing to cover");
        }

        // ---- the pointer ----
        check(MSBDRStripPointerAtEdge(0, 1024, NO) && MSBDRStripPointerAtEdge(2, 1024, NO) && !MSBDRStripPointerAtEdge(2.5, 1024, NO)
              && MSBDRStripPointerAtEdge(1022, 1024, YES) && !MSBDRStripPointerAtEdge(1021.5, 1024, YES) && !MSBDRStripPointerAtEdge(0, 1024, YES), @"the pointer at the strip's edge: within 2 pt of it, that side only");
        check(MSBDRStripPointerLeft(157, (MSBDRRect){ 0, 24, 116, 658 }, NO) && !MSBDRStripPointerLeft(150, (MSBDRRect){ 0, 24, 116, 658 }, NO)
              && MSBDRStripPointerLeft(867, (MSBDRRect){ 908, 24, 116, 658 }, YES) && !MSBDRStripPointerLeft(870, (MSBDRRect){ 908, 24, 116, 658 }, YES), @"the pointer has left it 40 pt past the band, either side");

        // ---- the pictures ----
        check(near(MSBDRStripPicScale(1000, 700, 88, 69) * 1000, 88) && MSBDRStripPicScale(50, 40, 88, 69) == 1.0 && MSBDRStripPicScale(0, 700, 88, 69) == 0.0,
              @"a picture at its card's size: the window fitted into the box (1000 x 700 at 0.088), never above its own size, none of an empty view");
        check(MSBDRStripPicScale(1366, 1024, 118, 92) * 1366 * 2 < 240.0, @"... a full-screen window on a 12.9\" at 2x: under 240 px wide (about 150 KB)");
        check(MSBDRStripPicDue(NO, 0, NO) && MSBDRStripPicDue(YES, 31, YES) && !MSBDRStripPicDue(YES, 31, NO) && !MSBDRStripPicDue(YES, 5, YES),
              @"a picture is due as the strip comes: none yet, or over 30 s old of a window on screen (a minimized window keeps its own)");
        check(MSBDRStripPicAtMinimize(NO, 0, NO) && MSBDRStripPicAtMinimize(NO, 0, YES) && MSBDRStripPicAtMinimize(YES, 11, YES) && !MSBDRStripPicAtMinimize(YES, 9, YES),
              @"a minimize pictures the window in front unless its picture is under 10 s old, and any window with none");
        check(!MSBDRStripPicAtMinimize(YES, 600, NO), @"... a window behind with a picture keeps it (Minimize All and Home: one picture, not one per window)");

        // ---- where it runs ----
        check(MSBDRecentStripOS(15) && !MSBDRecentStripOS(14) && !MSBDRecentStripOS(16) && !MSBDRecentStripOS(17) && !MSBDRecentStripOS(18), @"iPadOS 15 only in this build (the pictures without waiting are read there)");
        check(kMSBDRStripMax == 6, @"at most 6 cards");
        printf("%d of %d checks passed\n", gChecks - gFails, gChecks);
    }
    return gFails > 250 ? 250 : gFails;
}
