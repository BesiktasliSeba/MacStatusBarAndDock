// Mac test of the smallest window of the window engines (statusbar/WindowMinSize.h, the code StatusBar.x runs: the layouts' tiles, frames fitted
// into the desktop, Zetsu's and MilkyWay4's corner drags, the offset Aerial's corner drag steps with). With the iPad 2's real desktops (landscape
// {0,24}..697.07, portrait {0,24}..970.07, 3 Oct) every tile is as before; on a smaller desktop the tiles keep their own sides and grow over their
// neighbours; a frame fitted into the desktop is the old DMFitInto's above the minimum; Zetsu's grip is its old formula with the new minimum;
// Aerial's steps (the corner = finger + offset, the M1's and the iPad 2's traced drags of 28 Oct) never come out smaller and follow the finger
// exactly while the window is bigger. Run by test-winminsize.sh.
#import <Foundation/Foundation.h>
#include "../statusbar/WindowMinSize.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }
static BOOL same(CGRect a, CGRect b) { return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) && near(a.size.width, b.size.width) && near(a.size.height, b.size.height); }
static BOOL inside(CGRect r, CGRect a) { return r.origin.x >= a.origin.x - 0.01 && r.origin.y >= a.origin.y - 0.01 && CGRectGetMaxX(r) <= CGRectGetMaxX(a) + 0.01 && CGRectGetMaxY(r) <= CGRectGetMaxY(a) + 0.01; }
static const char *S(CGRect r) { static char b[8][96]; static int i = 0; i = (i + 1) % 8; snprintf(b[i], 96, "{%.2f, %.2f, %.2f, %.2f}", r.origin.x, r.origin.y, r.size.width, r.size.height); return b[i]; }

// The tiles as StatusBar.x's DMLayoutOuterArea / DMLayoutFrameInArea cut them (copied: this test checks the minimum, not the cut).
static CGRect outer(CGRect u, CGSize screen) {
    CGFloat minX = fmax(CGRectGetMinX(u), 26.0), maxX = fmin(CGRectGetMaxX(u), screen.width - 26.0);
    return maxX - minX < 200.0 ? u : CGRectMake(minX, u.origin.y, maxX - minX, u.size.height);
}
static CGRect cut(const char *name, CGRect u, CGSize screen) {
    u = outer(u, screen);
    CGFloat g = 10.0, halfW = floor((u.size.width - g) / 2.0), halfH = floor((u.size.height - g) / 2.0);
    CGFloat rightX = u.origin.x + u.size.width - halfW, bottomY = u.origin.y + u.size.height - halfH;
    if (!strcmp(name, "fill")) return u;
    if (!strcmp(name, "center")) return CGRectMake(round(screen.width * 0.11), 36.0, round(screen.width * 0.78), fmin(round(screen.height * 0.80), CGRectGetMaxY(u) - 36.0));
    if (!strcmp(name, "left")) return CGRectMake(u.origin.x, u.origin.y, halfW, u.size.height);
    if (!strcmp(name, "right")) return CGRectMake(rightX, u.origin.y, halfW, u.size.height);
    if (!strcmp(name, "top")) return CGRectMake(u.origin.x, u.origin.y, u.size.width, halfH);
    if (!strcmp(name, "bottom")) return CGRectMake(u.origin.x, bottomY, u.size.width, halfH);
    if (!strcmp(name, "topleft")) return CGRectMake(u.origin.x, u.origin.y, halfW, halfH);
    if (!strcmp(name, "topright")) return CGRectMake(rightX, u.origin.y, halfW, halfH);
    if (!strcmp(name, "bottomleft")) return CGRectMake(u.origin.x, bottomY, halfW, halfH);
    if (!strcmp(name, "bottomright")) return CGRectMake(rightX, bottomY, halfW, halfH);
    CGFloat fw = !strcmp(name, "small") ? 0.50 : (!strcmp(name, "medium") ? 0.66 : 0.86), fh = !strcmp(name, "small") ? 0.58 : (!strcmp(name, "medium") ? 0.74 : 0.92);
    CGFloat w = round(u.size.width * fw), h = round(u.size.height * fh);
    return CGRectMake(round(u.origin.x + (u.size.width - w) / 2.0), round(u.origin.y + (u.size.height - h) / 2.0), w, h);
}
// The engines' tile: the cut, then the minimum (StatusBar.x DMWindowSlotInArea).
static CGRect tile(const char *name, CGRect u, CGSize screen) { return MSBDWindowMinSlot(cut(name, u, screen), MSBDWindowKeepForLayout(name), outer(u, screen)); }
static const char *kNames[] = {"fill", "center", "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright", "small", "medium", "large"};

// The old DMFitInto (before 1.7.0) and Zetsu's old grip (DMZetsuGripBox -pan:, 320 x 260): what the new code must still give above the minimum.
static CGRect oldFitInto(CGRect f, CGRect usable) {
    f.size.width = MIN(f.size.width, usable.size.width); f.size.height = MIN(f.size.height, usable.size.height);
    f.origin.x = MAX(usable.origin.x, MIN(f.origin.x, CGRectGetMaxX(usable) - f.size.width));
    f.origin.y = MAX(usable.origin.y, MIN(f.origin.y, CGRectGetMaxY(usable) - f.size.height));
    return f;
}
static CGRect oldZetsuGrip(CGRect s0, CGFloat dx, CGFloat dy, BOOL left, CGSize sc, CGFloat minW, CGFloat minH) {
    CGFloat h = MIN(MAX(minH, s0.size.height + dy), sc.height - s0.origin.y);
    if (left) { CGFloat nw = MIN(MAX(minW, s0.size.width - dx), CGRectGetMaxX(s0)); return CGRectMake(CGRectGetMaxX(s0) - nw, s0.origin.y, nw, h); }
    CGFloat nw = MIN(MAX(minW, s0.size.width + dx), sc.width - s0.origin.x); return CGRectMake(s0.origin.x, s0.origin.y, nw, h);
}
// One step of Aerial's corner drag: the corner at the finger plus the offset, the other sides where the drag began.
static CGRect aerialStep(CGRect start, CGPoint finger, CGPoint o, BOOL left) {
    CGFloat right = CGRectGetMaxX(start), bottom = finger.y + o.y;
    if (left) { CGFloat x = finger.x + o.x; return CGRectMake(x, start.origin.y, right - x, bottom - start.origin.y); }
    return CGRectMake(start.origin.x, start.origin.y, finger.x + o.x - start.origin.x, bottom - start.origin.y);
}
static CGFloat rnd(CGFloat lo, CGFloat hi) { return lo + (hi - lo) * (arc4random_uniform(1000001) / 1000000.0); }

int main(void) {
    @autoreleasepool {
        CGSize m = MSBDWindowMinSize();
        CHECK(near(m.width, 320.0) && near(m.height, 324.0), "the smallest window: 320 x 324 (the app 320 x 300 under the 24 pt bar), is %.1f x %.1f", m.width, m.height);
        CHECK(MSBDWindowKeepForLayout("topleft") == (MSBDKeepTop | MSBDKeepLeft) && MSBDWindowKeepForLayout("bottomright") == (MSBDKeepBottom | MSBDKeepRight)
              && MSBDWindowKeepForLayout("left") == MSBDKeepLeft && MSBDWindowKeepForLayout("top") == MSBDKeepTop && MSBDWindowKeepForLayout("bottom") == MSBDKeepBottom
              && MSBDWindowKeepForLayout("center") == 0 && MSBDWindowKeepForLayout("medium") == 0 && MSBDWindowKeepForLayout("fill") == 0 && MSBDWindowKeepForLayout(NULL) == 0, "the sides each layout keeps");

        // 1. The iPad 2's desktops (as measured, 3 Oct; DMUsableArea: under the 24 pt menu bar, 2 pt above the Dock): every layout as before.
        const CGSize kLand = {1024, 768}, kPort = {768, 1024};
        const CGRect landU = CGRectMake(0, 24, 1024, 697.06844892501829 - 24), portU = CGRectMake(0, 24, 768, 970.06844892501829 - 24);
        for (int o = 0; o < 2; o++) {
            CGRect u = o ? portU : landU; CGSize s = o ? kPort : kLand;
            for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); i++)
                CHECK(same(tile(kNames[i], u, s), cut(kNames[i], u, s)), "iPad 2 %s, %s: unchanged by the minimum (%s -> %s)", o ? "portrait" : "landscape", kNames[i], S(cut(kNames[i], u, s)), S(tile(kNames[i], u, s)));
        }
        CHECK(near(cut("topleft", landU, kLand).size.height, 331.0) && near(cut("left", portU, kPort).size.width, 353.0), "the iPad 2's shortest and narrowest tiles: 331 pt (landscape quarters), 353 pt (portrait halves)");

        // 2. A smaller desktop (a screen smaller than our iPads': 690 x 560 under the menu bar): the quarters grow to the minimum, each keeps its own
        //    sides at the desktop's edges and grows over its neighbours; the halves keep their own side; everything stays inside the desktop.
        const CGSize kSmall = {742, 640}; const CGRect smallU = CGRectMake(0, 24, 742, 560);
        CGRect so = outer(smallU, kSmall);
        CGRect tl = tile("topleft", smallU, kSmall), tr = tile("topright", smallU, kSmall), bl = tile("bottomleft", smallU, kSmall), br = tile("bottomright", smallU, kSmall);
        CHECK(near(cut("topleft", smallU, kSmall).size.width, 340.0) && near(cut("topleft", smallU, kSmall).size.height, 275.0), "the small desktop's quarters are cut 340 x 275 (%s)", S(cut("topleft", smallU, kSmall)));
        for (int i = 0; i < 4; i++) { CGRect r = i == 0 ? tl : (i == 1 ? tr : (i == 2 ? bl : br));
            CHECK(r.size.width >= 320.0 - 0.01 && near(r.size.height, 324.0) && inside(r, so), "small desktop quarter %d is at least the minimum, inside the desktop: %s", i, S(r)); }
        CHECK(near(tl.origin.x, so.origin.x) && near(tl.origin.y, so.origin.y), "top left keeps the desktop's top left corner: %s", S(tl));
        CHECK(near(CGRectGetMaxX(tr), CGRectGetMaxX(so)) && near(tr.origin.y, so.origin.y), "top right keeps the top right corner: %s", S(tr));
        CHECK(near(bl.origin.x, so.origin.x) && near(CGRectGetMaxY(bl), CGRectGetMaxY(so)), "bottom left keeps the bottom left corner: %s", S(bl));
        CHECK(near(CGRectGetMaxX(br), CGRectGetMaxX(so)) && near(CGRectGetMaxY(br), CGRectGetMaxY(so)), "bottom right keeps the bottom right corner: %s", S(br));
        CHECK(near(tl.size.width, 340.0) && near(br.size.width, 340.0), "a side that is big enough keeps its size (340 wide)");
        CHECK(CGRectGetMaxY(tl) > bl.origin.y, "the top and bottom tiles overlap (grown over each other, nothing squeezed): %.1f > %.1f", CGRectGetMaxY(tl), bl.origin.y);
        CGRect t = tile("top", smallU, kSmall), b = tile("bottom", smallU, kSmall);
        CHECK(near(t.origin.y, so.origin.y) && near(CGRectGetMaxY(b), CGRectGetMaxY(so)) && near(t.size.width, so.size.width) && near(t.size.height, 324.0), "top / bottom halves keep their edge, full width: %s %s", S(t), S(b));
        //    a narrow one (a 600 pt wide desktop): the left and right halves are 269 wide when cut, 320 wide with the minimum, each at its own edge
        const CGSize kNarrow = {600, 900}; const CGRect narrowU = CGRectMake(0, 24, 600, 800); CGRect no = outer(narrowU, kNarrow);
        CGRect l = tile("left", narrowU, kNarrow), r = tile("right", narrowU, kNarrow);
        CHECK(near(cut("left", narrowU, kNarrow).size.width, 269.0) && near(l.size.width, 320.0) && near(r.size.width, 320.0), "narrow halves: cut 269, given 320 (%s %s)", S(l), S(r));
        CHECK(near(l.origin.x, no.origin.x) && near(CGRectGetMaxX(r), CGRectGetMaxX(no)) && near(l.size.height, no.size.height), "narrow halves keep their own side and the full height");
        //    centred sizes grow around their middle
        CGRect sm = tile("small", smallU, kSmall), smc = cut("small", smallU, kSmall);
        CHECK(near(sm.size.width, 345.0) && near(sm.size.height, 325.0) && same(sm, smc), "small (half the width, 58%% of the height) of the small desktop is big enough as it is: %s", S(sm));
        CGRect sn = tile("small", narrowU, kNarrow), snc = cut("small", narrowU, kNarrow);
        CHECK(near(sn.size.width, 320.0) && fabs(CGRectGetMidX(sn) - CGRectGetMidX(snc)) <= 0.5 && same(CGRectMake(0, snc.origin.y, 0, snc.size.height), CGRectMake(0, sn.origin.y, 0, sn.size.height)), "small on the narrow desktop: 274 -> 320 wide around its middle (%s -> %s)", S(snc), S(sn));
        //    the kept sides themselves (in the layouts they lie on the desktop's edges, where the desktop's own edge would hold them anyway): a
        //    100 x 100 tile in the middle of a big area grows from the sides it keeps, or around its middle
        CGRect big = CGRectMake(0, 0, 1000, 1000), mid = CGRectMake(500, 500, 100, 100);
        CHECK(same(MSBDWindowMinSlot(mid, MSBDKeepLeft | MSBDKeepTop, big), CGRectMake(500, 500, 320, 324)), "keeps its top left: %s", S(MSBDWindowMinSlot(mid, MSBDKeepLeft | MSBDKeepTop, big)));
        CHECK(same(MSBDWindowMinSlot(mid, MSBDKeepRight | MSBDKeepBottom, big), CGRectMake(280, 276, 320, 324)), "keeps its bottom right: %s", S(MSBDWindowMinSlot(mid, MSBDKeepRight | MSBDKeepBottom, big)));
        CHECK(same(MSBDWindowMinSlot(mid, MSBDKeepRight | MSBDKeepTop, big), CGRectMake(280, 500, 320, 324)), "keeps its top right: %s", S(MSBDWindowMinSlot(mid, MSBDKeepRight | MSBDKeepTop, big)));
        CHECK(same(MSBDWindowMinSlot(mid, 0, big), CGRectMake(390, 388, 320, 324)), "keeps its middle: %s", S(MSBDWindowMinSlot(mid, 0, big)));
        CHECK(same(MSBDWindowMinSlot(CGRectMake(900, 900, 100, 100), MSBDKeepLeft | MSBDKeepTop, big), CGRectMake(680, 676, 320, 324)), "kept sides too near the area's far edges: moved back in, the size kept");
        // 2b. Stage Manager's tiles (StatusBar.x DMSMLayoutFrameIn): the same minimum through MSBDWindowMinSlotOf, wider where Stage Manager's own
        //     smallest width is wider (-minimumWindowWidth: 320 on 16.7.7, 17.5.1, 18.5). The iPad 2's and the 17.5's desktops (12.9", a Dock of
        //     about 120 pt): every layout as cut; the small desktop: as the engines' tiles; a wider minimum of Stage Manager's (414): the halves of a
        //     narrow desktop keep their own side at 414.
        const CGSize smMin = {320, 324};
        for (int o = 0; o < 4; o++) {
            CGSize s = o == 0 ? kLand : (o == 1 ? kPort : (o == 2 ? CGSizeMake(1366, 1024) : CGSizeMake(1024, 1366)));
            CGRect u = o == 0 ? landU : (o == 1 ? portU : CGRectMake(0, 24, s.width, s.height - 24 - 122));
            for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); i++)
                CHECK(same(MSBDWindowMinSlotOf(cut(kNames[i], u, s), MSBDWindowKeepForLayout(kNames[i]), outer(u, s), smMin), cut(kNames[i], u, s)), "Stage Manager, %s %s: unchanged by the minimum", o < 2 ? "iPad 2" : "17.5", kNames[i]);
        }
        for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); i++)
            CHECK(same(MSBDWindowMinSlotOf(cut(kNames[i], smallU, kSmall), MSBDWindowKeepForLayout(kNames[i]), outer(smallU, kSmall), smMin), tile(kNames[i], smallU, kSmall)), "Stage Manager, small desktop %s: the engines' tile", kNames[i]);
        CGRect wl = MSBDWindowMinSlotOf(cut("left", narrowU, kNarrow), MSBDKeepLeft, no, CGSizeMake(414, 324)), wr = MSBDWindowMinSlotOf(cut("right", narrowU, kNarrow), MSBDKeepRight, no, CGSizeMake(414, 324));
        CHECK(near(wl.size.width, 414.0) && near(wl.origin.x, no.origin.x) && near(wr.size.width, 414.0) && near(CGRectGetMaxX(wr), CGRectGetMaxX(no)), "a wider minimum of Stage Manager's (414): each half keeps its own side (%s %s)", S(wl), S(wr));
        CHECK(same(MSBDWindowMinSlotOf(mid, MSBDKeepLeft | MSBDKeepTop, big, MSBDWindowMinSize()), MSBDWindowMinSlot(mid, MSBDKeepLeft | MSBDKeepTop, big)), "MSBDWindowMinSlot is MSBDWindowMinSlotOf with the minimum");

        // 3. A desktop smaller than a window may be: every tile is the whole of it on that axis, never more (it never goes past the desktop).
        const CGSize kTiny = {352, 300}; const CGRect tinyU = CGRectMake(0, 24, 352, 250); CGRect to = outer(tinyU, kTiny);
        for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); i++) {
            CGRect x = tile(kNames[i], tinyU, kTiny);
            if (!strcmp(kNames[i], "center")) continue;   // (the centre place starts at y 36 whatever the desktop: as before)
            CHECK(inside(x, to) && near(x.size.width, to.size.width) && near(x.size.height, to.size.height), "tiny desktop %s: the whole desktop, %s (desktop %s)", kNames[i], S(x), S(to));
        }

        // 4. A frame fitted into the desktop: as the old DMFitInto whenever the frame is at least the minimum, and with no minimum exactly that.
        CGSize none = CGSizeZero; int sweep = 0, ok = 0, okMin = 0;
        for (int i = 0; i < 4000; i++) {
            CGRect area = CGRectMake(rnd(0, 40), rnd(0, 60), rnd(400, 1400), rnd(400, 1100));
            CGRect f = CGRectMake(rnd(-300, 1500), rnd(-300, 1200), rnd(50, 1600), rnd(50, 1300));
            sweep++;
            if (same(MSBDWindowMinFit(f, area, none), oldFitInto(f, area))) ok++;
            CGRect g = MSBDWindowMinFit(f, area, m);
            BOOL big = f.size.width >= m.width && f.size.height >= m.height;
            if ((!big || same(g, oldFitInto(f, area))) && inside(g, area) && g.size.width >= fmin(m.width, area.size.width) - 0.01 && g.size.height >= fmin(m.height, area.size.height) - 0.01) okMin++;
        }
        CHECK(ok == sweep, "no minimum: exactly the old DMFitInto (%d of %d)", ok, sweep);
        CHECK(okMin == sweep, "with the minimum: at least it, inside the desktop, the old DMFitInto for big enough frames (%d of %d)", okMin, sweep);
        //    Clock left at 279 x 214 (Aerial 5.1, M1, 28 Oct) and saved so, brought back after a respring near the bottom right: 320 x 324, inside
        CGRect clock = MSBDWindowMinFit(CGRectMake(700, 520, 279, 214), landU, m);
        CHECK(near(clock.size.width, 320.0) && near(clock.size.height, 324.0) && inside(clock, landU) && near(clock.origin.x, 700.0) && near(CGRectGetMaxY(clock), CGRectGetMaxY(landU)), "Clock's 279 x 214 grows to the minimum from its corner, kept inside: %s", S(clock));
        //    a 330 pt wide landscape window turned to portrait, scaled (x 0.75): 247.5 wide, given 320 again; in the right part of the screen it moves in
        CGRect turned = MSBDWindowMinFit(CGRectMake(560, 100, 330 * 0.75, 400), portU, m);
        CHECK(near(turned.size.width, 320.0) && near(CGRectGetMaxX(turned), 768.0) && near(turned.size.height, 400.0), "a turn's scaled frame grows back to 320 and stays on the screen: %s", S(turned));
        //    Aerial 5.x: the minimum as its stage (the window grown by its margins 13/6/20/6): a stage of the minimum's window is not grown again
        CGSize stageMin = CGSizeMake(m.width + 12.0, m.height - 24.0 + 13.0 + 20.0);
        CHECK(same(MSBDWindowMinFit(CGRectMake(100, 100, 332, 333), landU, stageMin), CGRectMake(100, 100, 332, 333)) && same(MSBDWindowMinFit(CGRectMake(100, 100, 300, 300), landU, stageMin), CGRectMake(100, 100, 332, 333)), "Aerial 5.x's stage minimum 332 x 333 (%.0f x %.0f)", stageMin.width, stageMin.height);
        CHECK(same(MSBDWindowMinFit(CGRectMake(-50, 0, 2000, 2000), landU, m), landU), "a frame bigger than the desktop is the desktop");
        CHECK(same(MSBDWindowMinFit(CGRectMake(5, 6, 7, 8), CGRectNull, m), CGRectMake(5, 6, 7, 8)), "no desktop known: the frame as it is");

        // 5. Corner drags. MilkyWay4's step (and the end of Zetsu's): grown from the side that stays, only as far as the screen's edges, never shrunk.
        CGSize scr = kLand;
        CHECK(same(MSBDWindowMinCorner(CGRectMake(100, 100, 200, 150), false, m, scr), CGRectMake(100, 100, 320, 324)), "right corner: the top left stays");
        CHECK(same(MSBDWindowMinCorner(CGRectMake(500, 100, 200, 150), true, m, scr), CGRectMake(380, 100, 320, 324)), "left corner: the top right stays");
        CHECK(same(MSBDWindowMinCorner(CGRectMake(900, 100, 50, 400), false, m, scr), CGRectMake(900, 100, 124, 400)), "near the right edge: as wide as the screen allows (124)");
        CHECK(same(MSBDWindowMinCorner(CGRectMake(100, 600, 400, 50), false, m, scr), CGRectMake(100, 600, 400, 168)), "near the bottom: as tall as the screen allows (168)");
        CHECK(same(MSBDWindowMinCorner(CGRectMake(0, 100, 150, 400), true, m, scr), CGRectMake(0, 100, 150, 400)), "left corner, right edge 150 from the screen's left: stays 150 (no room)");
        CHECK(same(MSBDWindowMinCorner(CGRectMake(800, 300, 400, 500), false, m, scr), CGRectMake(800, 300, 400, 500)), "big enough (even past the screen's edge, MilkyWay4's own frame): left as it is");
        //    MilkyWay4's step from the frame its drag began with (131, 36, 931 x 667 on the M1) plus the finger's travel, turned round once that size is
        //    negative (as UIKit reads such a frame back: its origin where the corner went): the drag's top-left corner stays, at least the minimum
        CGPoint mwTL = CGPointMake(131, 36);
        CGRect (^mwStep)(CGFloat, CGFloat) = ^CGRect(CGFloat dx, CGFloat dy) { return CGRectStandardize(CGRectMake(131, 36, 931 + dx, 667 + dy)); };
        CHECK(same(MSBDWindowMinCornerFrom(mwStep(-100, -84), mwTL, m, scr), CGRectMake(131, 36, 831, 583)), "MilkyWay4, a step above the minimum: as it is (%s)", S(MSBDWindowMinCornerFrom(mwStep(-100, -84), mwTL, m, scr)));
        CHECK(same(MSBDWindowMinCornerFrom(mwStep(-748, -488), mwTL, m, scr), CGRectMake(131, 36, 320, 324)), "MilkyWay4, a step below the minimum: the minimum from its top left (%s)", S(MSBDWindowMinCornerFrom(mwStep(-748, -488), mwTL, m, scr)));
        CHECK(same(MSBDWindowMinCornerFrom(mwStep(-956.5, -612.5), mwTL, m, scr), CGRectMake(131, 36, 320, 324)), "MilkyWay4, the finger past the window's left edge (the step turned round, %s): the minimum from the top left it began with (%s)", S(mwStep(-956.5, -612.5)), S(MSBDWindowMinCornerFrom(mwStep(-956.5, -612.5), mwTL, m, scr)));
        CHECK(same(MSBDWindowMinCornerFrom(mwStep(-2000, -2000), mwTL, m, scr), CGRectMake(131, 36, 320, 324)), "MilkyWay4, travel past both edges (-2000, -2000; the step %s): the minimum from its top left, on the screen", S(mwStep(-2000, -2000)));
        CHECK(same(MSBDWindowMinCornerFrom(CGRectMake(900, 100, 50, 400), CGPointMake(900, 100), m, scr), CGRectMake(900, 100, 124, 400)), "MilkyWay4 near the right edge: as wide as the screen allows (124), as MSBDWindowMinCorner");
        int mws = 0, mwok = 0;   //    a random sweep: the top left always the drag's, at least the minimum (or the room), the step itself when it is bigger
        for (int i = 0; i < 4000; i++) {
            CGRect s0 = CGRectMake(rnd(0, 800), rnd(24, 500), rnd(320, 1000), rnd(324, 800));
            CGFloat dx = rnd(-2500, 1500), dy = rnd(-2500, 1500);
            CGRect step = CGRectStandardize(CGRectMake(s0.origin.x, s0.origin.y, s0.size.width + dx, s0.size.height + dy));
            CGRect r = MSBDWindowMinCornerFrom(step, s0.origin, m, scr);
            BOOL tl = near(r.origin.x, s0.origin.x) && near(r.origin.y, s0.origin.y);
            BOOL big = r.size.width >= fmin(m.width, scr.width - s0.origin.x) - 0.01 && r.size.height >= fmin(m.height, scr.height - s0.origin.y) - 0.01;
            BOOL own = !(s0.size.width + dx >= m.width && s0.size.height + dy >= m.height) || same(r, step);
            mws++; if (tl && big && own) mwok++;
        }
        CHECK(mwok == mws, "random MilkyWay4 drags: the drag's top left, at least the minimum, MilkyWay's own step while bigger (%d of %d)", mwok, mws);
        //    Zetsu's grip: its old formula exactly, with its old minimum and with the new one
        int zs = 0, zOld = 0, zNew = 0;
        for (int i = 0; i < 4000; i++) {
            CGRect s0 = CGRectMake(rnd(-100, 900), rnd(0, 600), rnd(150, 1000), rnd(150, 800));
            CGFloat dx = rnd(-1200, 1200), dy = rnd(-900, 900); BOOL left = arc4random_uniform(2);
            zs++;
            if (same(MSBDWindowCornerDrag(s0, CGPointMake(dx, dy), left, CGSizeMake(320, 260), scr), oldZetsuGrip(s0, dx, dy, left, scr, 320, 260))) zOld++;
            if (same(MSBDWindowCornerDrag(s0, CGPointMake(dx, dy), left, m, scr), oldZetsuGrip(s0, dx, dy, left, scr, m.width, m.height))) zNew++;
        }
        CHECK(zOld == zs && zNew == zs, "Zetsu's grip: its old frames (320 x 260: %d of %d), with the new minimum (%d of %d)", zOld, zs, zNew, zs);
        CGRect zr = MSBDWindowCornerDrag(CGRectMake(200, 150, 600, 450), CGPointMake(-500, -400), false, m, scr), zl = MSBDWindowCornerDrag(CGRectMake(200, 150, 600, 450), CGPointMake(500, -400), true, m, scr);
        CHECK(same(zr, CGRectMake(200, 150, 320, 324)) && same(zl, CGRectMake(480, 150, 320, 324)), "Zetsu shrunk past the minimum: stops there, from the side that stays (%s %s)", S(zr), S(zl));

        // 6. Aerial's steps (the corner = finger + offset). The M1's left-corner drag (Settings, 28 Oct 23:14: start {214, 118, 684, 485}, Aerial's
        //    offset {-18, 13} with our catch-up), here with Aerial 5.x's stage minimum: the finger goes far in (the window would be 150 x 120), out
        //    again past where it began, and lifts where the trace lifted ({120, 700}: stage {102, 118, 796, 595}).
        CGRect m1 = CGRectMake(214, 118, 684, 485); CGPoint m1o = CGPointMake(-18, 13), m1f0 = CGPointMake(221.5, 600.5), m1end = CGPointMake(120, 700);
        CGPoint deep = CGPointMake(CGRectGetMaxX(m1) - 150 + 18, 118 + 120 - 13);
        int steps = 0, atLeast = 0, follows = 0, bigSteps = 0, stopsRight = 0;
        for (int k = 0; k <= 200; k++) {   // in to deep, back out to the lift point
            CGFloat u = k <= 100 ? k / 100.0 : (k - 100) / 100.0;
            CGPoint a = k <= 100 ? m1f0 : deep, z = k <= 100 ? deep : m1end;
            CGPoint finger = CGPointMake(a.x + (z.x - a.x) * u, a.y + (z.y - a.y) * u);
            CGPoint o = MSBDWindowMinCornerOffset(finger, m1o, m1, stageMin, true, scr);
            CGRect f = aerialStep(m1, finger, o, true), free = aerialStep(m1, finger, m1o, true);
            steps++;
            if (f.size.width >= stageMin.width - 0.01 && f.size.height >= stageMin.height - 0.01) atLeast++;
            if (near(CGRectGetMaxX(f), CGRectGetMaxX(m1)) && near(f.origin.y, m1.origin.y)) stopsRight++;
            if (free.size.width >= stageMin.width && free.size.height >= stageMin.height) { bigSteps++; if (same(f, free) && near(o.x, m1o.x) && near(o.y, m1o.y)) follows++; }
        }
        CHECK(atLeast == steps, "M1 left-corner drag: no step smaller than the stage minimum (%d of %d)", atLeast, steps);
        CHECK(stopsRight == steps, "M1 left-corner drag: the right edge and the top stay (%d of %d)", stopsRight, steps);
        CHECK(bigSteps > 40 && follows == bigSteps, "M1 left-corner drag: while the window is bigger, Aerial's own offset and frame exactly (%d of %d)", follows, bigSteps);
        CGPoint oEnd = MSBDWindowMinCornerOffset(m1end, m1o, m1, stageMin, true, scr);
        CHECK(same(aerialStep(m1, m1end, oEnd, true), CGRectMake(102, 118, 796, 595)), "M1 drag lifted as traced: stage {102, 118, 796, 595} as before (%s)", S(aerialStep(m1, m1end, oEnd, true)));
        CGPoint oDeep = MSBDWindowMinCornerOffset(deep, m1o, m1, stageMin, true, scr);
        CHECK(same(aerialStep(m1, deep, oDeep, true), CGRectMake(CGRectGetMaxX(m1) - 332, 118, 332, 333)), "M1 drag lifted deep inside: exactly the minimum, the right edge kept (%s)", S(aerialStep(m1, deep, oDeep, true)));
        //    The iPad 2's right-corner drag (Settings, 21:42: start {185, 111, 654, 508}, offset {17, 21}): shrunk to a finger at {300, 250}, lifted there
        CGRect p2 = CGRectMake(185, 111, 654, 508); CGPoint p2o = CGPointMake(17, 21);
        CGPoint o2 = MSBDWindowMinCornerOffset(CGPointMake(300, 250), p2o, p2, stageMin, false, scr);
        CHECK(same(aerialStep(p2, CGPointMake(300, 250), o2, false), CGRectMake(185, 111, 332, 333)), "iPad 2 right-corner drag lifted small: the minimum, the top left kept (%s)", S(aerialStep(p2, CGPointMake(300, 250), o2, false)));
        CHECK(same(aerialStep(p2, CGPointMake(900, 660), MSBDWindowMinCornerOffset(CGPointMake(900, 660), p2o, p2, stageMin, false, scr), false), CGRectMake(185, 111, 732, 570)), "iPad 2 drag lifted as traced ({900, 660}): stage {185, 111, 732, 570} as before");
        CHECK(near(MSBDWindowMinCornerOffset(CGPointMake(320, 700), p2o, p2, stageMin, false, scr).y, p2o.y) && !near(MSBDWindowMinCornerOffset(CGPointMake(320, 700), p2o, p2, stageMin, false, scr).x, p2o.x), "only the axis past the minimum is held (narrow but tall: the height follows the finger)");
        //    a window near the screen's right edge, its right corner dragged in: no wider than the room to the edge for the minimum
        CGRect edge = CGRectMake(900, 200, 120, 400);
        CGRect fe = aerialStep(edge, CGPointMake(910, 400), MSBDWindowMinCornerOffset(CGPointMake(910, 400), CGPointMake(10, 200), edge, stageMin, false, scr), false);
        CHECK(near(fe.size.width, 124.0) && near(fe.size.height, 400.0), "near the screen's right edge: 124 wide (the room), its height its own: %s", S(fe));
        //    a random sweep of drags, both corners: every step at least the minimum (or all the room there is), Aerial's own while bigger
        int rs = 0, rok = 0;
        for (int i = 0; i < 4000; i++) {
            CGRect st = CGRectMake(rnd(0, 600), rnd(24, 400), rnd(340, 900), rnd(340, 700));
            BOOL left = arc4random_uniform(2);
            CGPoint off = CGPointMake(rnd(-25, 25), rnd(-25, 25)), finger = CGPointMake(rnd(-200, 1300), rnd(-200, 1000));
            CGPoint o = MSBDWindowMinCornerOffset(finger, off, st, stageMin, left, scr);
            CGRect f = aerialStep(st, finger, o, left), free = aerialStep(st, finger, off, left);
            CGFloat roomW = left ? CGRectGetMaxX(st) : scr.width - st.origin.x, roomH = scr.height - st.origin.y;
            BOOL wOK = f.size.width >= fmin(stageMin.width, roomW) - 0.01, hOK = f.size.height >= fmin(stageMin.height, roomH) - 0.01;
            BOOL keep = !(free.size.width >= stageMin.width && free.size.height >= stageMin.height) || same(f, free);
            BOOL bigger = f.size.width >= free.size.width - 0.01 && f.size.height >= free.size.height - 0.01;   // (it only ever holds the corner back from shrinking)
            rs++; if (wOK && hOK && keep && bigger) rok++;
        }
        CHECK(rok == rs, "random Aerial drags: at least the minimum, Aerial's own step while bigger, never smaller than its own (%d of %d)", rok, rs);
    }
    printf("%s: %d checks passed, %d failed\n", fails ? "FAILED" : "ok", passes, fails);
    return fails ? 1 : 0;
}
